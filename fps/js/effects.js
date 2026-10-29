/* Mirage Protocol — representação visual das entidades e efeitos: personagens, traçantes, impactos,
 * partículas (pool), marcas de tiro, fumaça, fogo, explosões, granadas, bomba e armas no chão.
 * Reage a eventos emitidos pela simulação; todos os objetos são reutilizados (sem alocação por quadro). */
(function (root) {
  'use strict';
  const MP = root.MP;
  const THREE = root.THREE;
  const { V3, math: M, world } = MP;
  const ev = MP.events;

  const _v = new THREE.Vector3(), _v2 = new THREE.Vector3(), _q = new THREE.Quaternion();

  /** Sistema de partículas em pool com um único THREE.Points por tipo de mistura. */
  class Particles {
    constructor(scene, max, additive, texture) {
      this.max = max; this.n = 0;
      this.pos = new Float32Array(max * 3); this.col = new Float32Array(max * 3); this.size = new Float32Array(max);
      this.vel = new Float32Array(max * 3); this.life = new Float32Array(max); this.maxLife = new Float32Array(max);
      this.baseCol = new Float32Array(max * 3); this.grav = new Float32Array(max); this.baseSize = new Float32Array(max);
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
      g.setAttribute('color', new THREE.BufferAttribute(this.col, 3).setUsage(THREE.DynamicDrawUsage));
      g.setAttribute('size', new THREE.BufferAttribute(this.size, 1).setUsage(THREE.DynamicDrawUsage));
      g.setDrawRange(0, 0);
      const mat = new THREE.ShaderMaterial({
        uniforms: { map: { value: texture }, scale: { value: 400 } },
        vertexShader: 'attribute float size; varying vec3 vCol; void main(){ vCol = color; vec4 mv = modelViewMatrix * vec4(position,1.0); gl_PointSize = size * 400.0 / -mv.z; gl_Position = projectionMatrix * mv; }',
        fragmentShader: 'uniform sampler2D map; varying vec3 vCol; void main(){ vec4 t = texture2D(map, gl_PointCoord); gl_FragColor = vec4(vCol, 1.0) * t; if (gl_FragColor.a < 0.02) discard; }',
        vertexColors: true, transparent: true, depthWrite: false,
        blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending
      });
      this.additive = additive;
      this.points = new THREE.Points(g, mat); this.points.frustumCulled = false;
      scene.add(this.points);
      this.limit = max;
    }
    emit(p, vx, vy, vz, r, g, b, size, life, grav) {
      if (this.n >= this.limit) return;
      const i = this.n++;
      this.pos[i * 3] = p.x; this.pos[i * 3 + 1] = p.y; this.pos[i * 3 + 2] = p.z;
      this.vel[i * 3] = vx; this.vel[i * 3 + 1] = vy; this.vel[i * 3 + 2] = vz;
      this.baseCol[i * 3] = r; this.baseCol[i * 3 + 1] = g; this.baseCol[i * 3 + 2] = b;
      this.baseSize[i] = size; this.life[i] = life; this.maxLife[i] = life; this.grav[i] = grav;
    }
    update(dt) {
      let n = this.n;
      for (let i = 0; i < n; i++) {
        this.life[i] -= dt;
        if (this.life[i] <= 0) { // remove trocando com o último
          n--;
          if (i !== n) {
            for (let k = 0; k < 3; k++) { this.pos[i * 3 + k] = this.pos[n * 3 + k]; this.vel[i * 3 + k] = this.vel[n * 3 + k]; this.baseCol[i * 3 + k] = this.baseCol[n * 3 + k]; }
            this.life[i] = this.life[n]; this.maxLife[i] = this.maxLife[n]; this.grav[i] = this.grav[n]; this.baseSize[i] = this.baseSize[n];
            i--;
          }
          continue;
        }
        this.vel[i * 3 + 1] -= this.grav[i] * dt;
        const drag = this.grav[i] < 0 ? 0.96 : 0.99;
        this.vel[i * 3] *= drag; this.vel[i * 3 + 2] *= drag;
        this.pos[i * 3] += this.vel[i * 3] * dt; this.pos[i * 3 + 1] += this.vel[i * 3 + 1] * dt; this.pos[i * 3 + 2] += this.vel[i * 3 + 2] * dt;
        if (this.pos[i * 3 + 1] < 0.02) { this.pos[i * 3 + 1] = 0.02; this.vel[i * 3 + 1] *= -0.3; }
        const t = this.life[i] / this.maxLife[i];
        const f = this.additive ? t : Math.min(1, t * 1.6);
        this.col[i * 3] = this.baseCol[i * 3] * f; this.col[i * 3 + 1] = this.baseCol[i * 3 + 1] * f; this.col[i * 3 + 2] = this.baseCol[i * 3 + 2] * f;
        this.size[i] = this.baseSize[i] * (this.grav[i] < 0 ? (1.6 - t * 0.6) : 1);
      }
      this.n = n;
      const g = this.points.geometry;
      g.setDrawRange(0, n);
      g.attributes.position.needsUpdate = true; g.attributes.color.needsUpdate = true; g.attributes.size.needsUpdate = true;
    }
    clear() { this.n = 0; }
  }

  const FX = MP.fx = {
    chars: new Map(), drops: new Map(), nades: new Map(), smokes: new Map(), fires: new Map(), nameTags: new Map(),
    shake: 0, followAgent: null,

    init() {
      const R = MP.render, scene = R.scene, q = R.q;
      this.scene = scene;
      const dot = MP.textures.get('softDot', () => MP.textures.gen.softDot(64), { clamp: true });
      this.sparks = new Particles(scene, 700, true, dot);
      this.dust = new Particles(scene, 700, false, dot);
      this.setLimits(q);
      // traçantes
      this.tracers = [];
      const tmat = new THREE.MeshBasicMaterial({ color: 0xffe9a8, transparent: true, opacity: 0.8, blending: THREE.AdditiveBlending, depthWrite: false });
      const tgeo = new THREE.BoxGeometry(0.018, 0.018, 1); tgeo.translate(0, 0, -0.5);
      for (let i = 0; i < 40; i++) { const m = new THREE.Mesh(tgeo, tmat.clone()); m.visible = false; m.userData.life = 0; scene.add(m); this.tracers.push(m); }
      this.tracerI = 0;
      // marcas de tiro
      const holeTex = MP.textures.get('bulletHole', () => MP.textures.gen.bulletHole(64), { clamp: true });
      const hmat = new THREE.MeshBasicMaterial({ map: holeTex, transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -4 });
      const hgeo = new THREE.PlaneGeometry(0.075, 0.075);
      this.decals = []; this.decalI = 0;
      for (let i = 0; i < 160; i++) { const m = new THREE.Mesh(hgeo, hmat); m.visible = false; m.matrixAutoUpdate = false; scene.add(m); this.decals.push(m); }
      const scorchTex = MP.textures.get('scorch', () => MP.textures.gen.scorch(128), { clamp: true });
      this.scorchMat = new THREE.MeshBasicMaterial({ map: scorchTex, transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -3 });
      this.scorches = [];
      // clarão de tiro de terceira pessoa (sprites em pool)
      const flashTex = MP.textures.get('flashStar', () => MP.textures.gen.flashStar(128), { clamp: true });
      this.flashes = [];
      for (let i = 0; i < 12; i++) { const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: flashTex, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true })); s.visible = false; s.userData.life = 0; scene.add(s); this.flashes.push(s); }
      this.flashI = 0;
      // luz de disparo/explosão compartilhada
      this.light = new THREE.PointLight(0xffc070, 0, 9, 2); scene.add(this.light); this.lightLife = 0;
      this.boomLight = new THREE.PointLight(0xffa040, 0, 26, 2); scene.add(this.boomLight); this.boomLife = 0;
      // fumaça
      this.smokeTex = MP.textures.get('smokePuff', () => MP.textures.gen.smokePuff(128), { clamp: true });
      this.fireMat = new THREE.SpriteMaterial({ map: dot, color: 0xff8a2a, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true });
      // bomba
      this.bombMesh = MP.models.buildWeapon('bomb', true); this.bombMesh.scale.setScalar(1.6); this.bombMesh.visible = false; scene.add(this.bombMesh);
      this.bombLed = this.bombMesh.getObjectByName('led');
      this.bombGlow = new THREE.Sprite(new THREE.SpriteMaterial({ map: dot, color: 0xff2020, blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }));
      this.bombGlow.scale.set(0.5, 0.5, 0.5); this.bombMesh.add(this.bombGlow); this.bombGlow.position.set(-0.06, 0.06, 0.03);
      this.registerEvents();
    },
    setLimits(q) { this.sparks.limit = Math.min(700, q.particles); this.dust.limit = Math.min(700, q.particles); this.smokeSprites = q.smokeSprites; this.decalLimit = q.decals; },

    registerEvents() {
      const self = this;
      ev.on('agent:add', a => self.addChar(a), 'fx:add');
      ev.on('agent:remove', a => self.removeChar(a), 'fx:rm');
      ev.on('render:quality', (k, q) => self.setLimits(q), 'fx:q');
      ev.on('shot', (a, o, end, def, i) => self.onShot(a, o, end, def, i), 'fx:shot');
      ev.on('impact', (p, n, mat, wid) => self.onImpact(p, n, mat, wid), 'fx:imp');
      ev.on('hitFlesh', (p, victim) => self.onBlood(p, victim), 'fx:blood');
      ev.on('explosion', (p, size) => self.onExplosion(p, size), 'fx:boom');
      ev.on('flashbang', p => self.onFlashbang(p), 'fx:fb');
      ev.on('grenade:throw', g => self.addNade(g), 'fx:nade');
      ev.on('grenade:remove', g => self.removeNade(g), 'fx:nader');
      ev.on('smoke:start', s => self.addSmoke(s), 'fx:smk');
      ev.on('smoke:end', s => self.removeSmoke(s), 'fx:smke');
      ev.on('fire:start', f => self.addFire(f), 'fx:fire');
      ev.on('fire:end', f => self.removeFire(f), 'fx:firee');
      ev.on('drop:add', d => self.addDrop(d), 'fx:drop');
      ev.on('drop:remove', d => self.removeDrop(d), 'fx:dropr');
      ev.on('round:start', () => self.clearTransient(), 'fx:round');
      ev.on('match:start', () => self.clearTransient(), 'fx:match');
      ev.on('agent:respawn', a => { const c = self.chars.get(a); if (c) c.resetPose(); }, 'fx:resp');
    },

    // ------------------------------------------------------------- personagens
    addChar(a) {
      if (this.chars.has(a)) return;
      const c = new MP.models.Character(a);
      this.scene.add(c.root); this.chars.set(a, c);
    },
    removeChar(a) {
      const c = this.chars.get(a); if (!c) return;
      this.scene.remove(c.root); this.chars.delete(a);
      const tag = this.nameTags.get(a); if (tag) { this.scene.remove(tag); tag.material.map.dispose(); tag.material.dispose(); this.nameTags.delete(a); }
    },
    nameTag(a) {
      let s = this.nameTags.get(a);
      if (!s) {
        const cv = document.createElement('canvas'); cv.width = 256; cv.height = 64;
        const x = cv.getContext('2d');
        x.font = 'bold 30px Rajdhani, Arial, sans-serif'; x.textAlign = 'center'; x.textBaseline = 'middle';
        x.lineWidth = 6; x.strokeStyle = 'rgba(0,0,0,0.8)'; x.strokeText(a.name, 128, 32);
        x.fillStyle = a.team === 'T' ? '#ffcf7a' : '#9fd4ff'; x.fillText(a.name, 128, 32);
        const t = new THREE.CanvasTexture(cv);
        s = new THREE.Sprite(new THREE.SpriteMaterial({ map: t, depthTest: false, transparent: true }));
        s.scale.set(1.2, 0.3, 1); s.renderOrder = 5;
        this.scene.add(s); this.nameTags.set(a, s);
      }
      return s;
    },

    // ------------------------------------------------------------- disparos e impactos
    onShot(a, o, end, def, i) {
      const isLocal = a === MP.game.player && !MP.main.thirdPerson;
      const c = this.chars.get(a);
      const start = _v.set(o.x, o.y, o.z);
      if (isLocal) { start.set(o.x, o.y - 0.12, o.z); const vm = MP.main.viewmodelMuzzleWorld(_v2); if (vm) start.copy(vm); }
      else if (c) c.muzzleWorld(start);
      if (i === 0) {
        if (!isLocal && def.mode !== 'melee') {
          const f = this.flashes[this.flashI++ % this.flashes.length];
          f.position.copy(start); const s = def.cat === 'pistol' ? 0.35 : 0.6; f.scale.set(s, s, s); f.material.rotation = Math.random() * 6; f.visible = true; f.userData.life = 0.05;
        }
        if (MP.render.q.lights) { this.light.position.copy(start); this.light.intensity = 2.2; this.lightLife = 0.05; }
      }
      // traçante (nem todo tiro; escopeta: alguns fragmentos)
      if (def.pellets ? i % 3 === 0 : Math.random() < (isLocal ? 0.45 : 0.6)) {
        const t = this.tracers[this.tracerI++ % this.tracers.length];
        const ex = end.x, ey = end.y, ez = end.z;
        const len = Math.sqrt((ex - start.x) ** 2 + (ey - start.y) ** 2 + (ez - start.z) ** 2);
        if (len > 1) {
          t.position.copy(start); t.lookAt(_v2.set(ex, ey, ez));
          t.scale.set(1, 1, Math.min(len, 6)); t.userData.speed = 220; t.userData.dist = 0; t.userData.len = len;
          t.userData.dir = new THREE.Vector3(ex - start.x, ey - start.y, ez - start.z).normalize();
          t.userData.life = len / 220 + 0.02; t.visible = true; t.material.opacity = 0.75;
        }
      }
    },
    onImpact(p, n, mat, wid) {
      const q = MP.render.q;
      // partículas por material
      const metal = mat && mat.startsWith && (mat === 'metal');
      const wood = mat === 'wood';
      const cnt = Math.max(2, Math.round(q.particles / 110));
      for (let i = 0; i < cnt; i++) {
        const vx = n.x * 2 + M.rand(-1.5, 1.5), vy = n.y * 2 + M.rand(0, 2.2), vz = n.z * 2 + M.rand(-1.5, 1.5);
        if (wood) this.dust.emit(p, vx, vy, vz, 0.55, 0.4, 0.22, 0.05, 0.6, 9);
        else this.dust.emit(p, vx * 0.6, vy * 0.6, vz * 0.6, 0.75, 0.68, 0.55, 0.09, 0.7, -0.4);
      }
      if (metal || Math.random() < 0.4) for (let i = 0; i < (metal ? 5 : 2); i++) this.sparks.emit(p, n.x * 3 + M.rand(-3, 3), n.y * 3 + M.rand(0, 3), n.z * 3 + M.rand(-3, 3), 1, 0.75, 0.35, 0.035, 0.25, 14);
      if (wid === 'knife' || mat === 'ground' && p.y < 0.01 && Math.random() < 0.5) {}
      // marca de tiro
      const d = this.decals[this.decalI++ % Math.min(this.decals.length, this.decalLimit || 100)];
      d.position.set(p.x + n.x * 0.01, p.y + n.y * 0.01, p.z + n.z * 0.01);
      _v.set(p.x + n.x, p.y + n.y, p.z + n.z);
      d.lookAt(_v); d.rotateZ(Math.random() * 6);
      const s = wid === 'knife' ? 0.6 : 0.7 + Math.random() * 0.6; d.scale.set(s, s, s);
      d.updateMatrix(); d.visible = true;
      ev.emit('impact:sound', p, mat);
    },
    onBlood(p, victim) {
      const n = Math.max(3, Math.round(MP.render.q.particles / 60));
      for (let i = 0; i < n; i++) this.dust.emit(p, M.rand(-1.2, 1.2), M.rand(0, 1.8), M.rand(-1.2, 1.2), 0.55, 0.05, 0.04, 0.07, 0.5, 6);
    },
    onExplosion(p, size) {
      const q = MP.render.q;
      const n = Math.round(q.particles * 0.35 * size);
      for (let i = 0; i < n; i++) {
        const a = Math.random() * 6.28, e = Math.random() * 1.3, sp = M.rand(4, 13) * Math.sqrt(size);
        this.sparks.emit(p, Math.cos(a) * Math.cos(e) * sp, Math.sin(e) * sp, Math.sin(a) * Math.cos(e) * sp, 1, M.rand(0.45, 0.8), 0.2, M.rand(0.06, 0.16), M.rand(0.3, 0.8), 9);
      }
      for (let i = 0; i < n * 0.6; i++) {
        const a = Math.random() * 6.28, sp = M.rand(1, 5) * Math.sqrt(size);
        const g = M.rand(0.25, 0.45);
        this.dust.emit(p, Math.cos(a) * sp, M.rand(0.5, 3), Math.sin(a) * sp, g, g * 0.92, g * 0.8, M.rand(0.5, 1.1) * size, M.rand(1.2, 2.5), -0.6);
      }
      this.boomLight.position.set(p.x, p.y + 1, p.z); this.boomLight.intensity = 6 * size; this.boomLife = 0.35;
      // marca de explosão no chão
      const sm = new THREE.Mesh(new THREE.PlaneGeometry(4 * size, 4 * size), this.scorchMat);
      sm.rotation.x = -Math.PI / 2; sm.position.set(p.x, MP.map.groundBelow(p.x - 0.1, p.z - 0.1, p.x + 0.1, p.z + 0.1, p.y + 0.5) + 0.02, p.z);
      this.scene.add(sm); this.scorches.push(sm);
      if (this.scorches.length > 10) { const o = this.scorches.shift(); this.scene.remove(o); o.geometry.dispose(); }
      const pl = MP.game.player;
      if (pl) { const d = pl.pos.dist(p); this.shake = Math.max(this.shake, M.clamp(1.2 - d / (20 * size), 0, 1) * size); }
    },
    onFlashbang(p) {
      for (let i = 0; i < 30; i++) this.sparks.emit(p, M.rand(-6, 6), M.rand(-2, 6), M.rand(-6, 6), 1, 1, 0.95, 0.12, 0.25, 5);
      this.boomLight.position.set(p.x, p.y, p.z); this.boomLight.color.setHex(0xffffff); this.boomLight.intensity = 8; this.boomLife = 0.15;
      setTimeout(() => this.boomLight.color.setHex(0xffa040), 200);
    },

    // ------------------------------------------------------------- granadas, fumaça e fogo
    addNade(g) {
      const key = g.type === 'he' ? 'grenade' : g.type === 'molotov' ? (g.owner && g.owner.inv.grenadeIds.molotov === 'incend' ? 'incend' : 'molotov') : g.type;
      const m = MP.models.buildWeapon(key); m.scale.setScalar(1.3);
      this.scene.add(m); this.nades.set(g, m);
    },
    removeNade(g) { const m = this.nades.get(g); if (m) { this.scene.remove(m); this.nades.delete(g); } },
    addSmoke(s) {
      const group = new THREE.Group(); group.position.set(s.pos.x, s.pos.y, s.pos.z);
      const n = this.smokeSprites || 12; const parts = [];
      for (let i = 0; i < n; i++) {
        const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: this.smokeTex, color: new THREE.Color().setHSL(0.1, 0.05, M.rand(0.68, 0.82)), transparent: true, depthWrite: false, opacity: 0 }));
        const a = Math.random() * 6.28, r = Math.sqrt(Math.random()), h = M.rand(-0.6, 1.0);
        sp.userData = { ox: Math.cos(a) * r, oy: h, oz: Math.sin(a) * r, rot: M.rand(-0.2, 0.2), size: M.rand(3.2, 4.6) };
        sp.material.rotation = Math.random() * 6;
        group.add(sp); parts.push(sp);
      }
      this.scene.add(group); this.smokes.set(s, { group, parts });
    },
    removeSmoke(s) { const o = this.smokes.get(s); if (o) { this.scene.remove(o.group); for (const p of o.parts) p.material.dispose(); this.smokes.delete(s); } },
    addFire(f) {
      const group = new THREE.Group(); group.position.set(f.pos.x, f.pos.y + 0.05, f.pos.z);
      const parts = [];
      for (let i = 0; i < 16; i++) {
        const sp = new THREE.Sprite(this.fireMat.clone());
        const a = Math.random() * 6.28, r = Math.sqrt(Math.random()) * 2.7;
        sp.userData = { x: Math.cos(a) * r, z: Math.sin(a) * r, ph: Math.random() * 6 };
        group.add(sp); parts.push(sp);
      }
      let light = null;
      if (MP.render.q.lights) { light = new THREE.PointLight(0xff7a20, 2, 9, 2); light.position.y = 0.8; group.add(light); }
      this.scene.add(group); this.fires.set(f, { group, parts, light });
    },
    removeFire(f) { const o = this.fires.get(f); if (o) { this.scene.remove(o.group); for (const p of o.parts) p.material.dispose(); this.fires.delete(f); } },
    addDrop(d) {
      const m = MP.models.buildWeapon(d.ws.def.model); m.traverse(o => { if (o.isMesh) o.castShadow = true; });
      this.scene.add(m); this.drops.set(d, m);
    },
    removeDrop(d) { const m = this.drops.get(d); if (m) { this.scene.remove(m); this.drops.delete(d); } },
    clearTransient() {
      this.sparks.clear(); this.dust.clear();
      for (const d of this.decals) d.visible = false;
      for (const t of this.tracers) t.visible = false;
      for (const s of this.scorches) { this.scene.remove(s); s.geometry.dispose(); }
      this.scorches.length = 0;
      for (const [g] of this.nades) this.removeNade(g);
      for (const [s] of this.smokes) this.removeSmoke(s);
      for (const [f] of this.fires) this.removeFire(f);
      for (const [d] of this.drops) this.removeDrop(d);
      for (const c of this.chars.values()) c.resetPose();
    },

    // ------------------------------------------------------------- atualização por quadro
    update(dt, camPos, hideAgent) {
      const t = world.time;
      for (const [a, c] of this.chars) {
        const hide = a === hideAgent;
        c.root.visible = !hide;
        if (!hide) { c.setWeapon(a.alive ? a.activeDef : null); c.update(dt); }
        // nomes dos aliados
        const pl = MP.game.player;
        const showTag = pl && a !== pl && a.alive && a.team === pl.team && !hide;
        const tag = showTag ? this.nameTag(a) : this.nameTags.get(a);
        if (tag) {
          tag.visible = showTag;
          if (showTag) { tag.position.set(a.pos.x, a.pos.y + a.height + 0.35, a.pos.z); const d = camPos.distanceTo(tag.position); const s = M.clamp(d * 0.05, 0.6, 2.5); tag.scale.set(1.2 * s, 0.3 * s, 1); tag.material.opacity = M.clamp(1.4 - d / 50, 0.35, 1); }
        }
      }
      this.sparks.update(dt); this.dust.update(dt);
      for (const tr of this.tracers) {
        if (!tr.visible) continue;
        tr.userData.life -= dt;
        if (tr.userData.life <= 0) { tr.visible = false; continue; }
        const step = tr.userData.speed * dt; tr.userData.dist += step;
        tr.position.addScaledVector(tr.userData.dir, step);
        const remain = tr.userData.len - tr.userData.dist;
        if (remain < 6) tr.scale.z = Math.max(0.01, remain);
      }
      for (const f of this.flashes) { if (f.visible && (f.userData.life -= dt) <= 0) f.visible = false; }
      if (this.lightLife > 0) { this.lightLife -= dt; if (this.lightLife <= 0) this.light.intensity = 0; }
      if (this.boomLife > 0) { this.boomLife -= dt; this.boomLight.intensity *= 0.86; if (this.boomLife <= 0) this.boomLight.intensity = 0; }
      // granadas
      for (const [g, m] of this.nades) { m.position.set(g.pos.x, g.pos.y, g.pos.z); if (!g.resting) { m.rotation.x += dt * 8; m.rotation.z += dt * 5; } }
      // fumaça
      for (const [s, o] of this.smokes) {
        const age = t - s.born; const grow = M.clamp(age / 1.4, 0, 1); const fade = age > s.life - 2.5 ? M.clamp((s.life - age) / 2.5, 0, 1) : 1;
        const R = 4.3 * (0.35 + 0.65 * grow);
        for (const p of o.parts) {
          const u = p.userData;
          p.position.set(u.ox * R * 0.75, u.oy * R * 0.45 + age * 0.03, u.oz * R * 0.75);
          const sz = u.size * (0.4 + 0.6 * grow); p.scale.set(sz, sz, sz);
          p.material.rotation += u.rot * dt; p.material.opacity = 0.92 * fade * Math.min(1, age * 2);
        }
      }
      for (const [f, o] of this.fires) {
        const age = t - f.born; const fade = age > f.life - 1 ? M.clamp(f.life - age, 0, 1) : Math.min(1, age * 4);
        for (const p of o.parts) {
          const u = p.userData; const fl = 0.5 + 0.5 * Math.sin(t * 13 + u.ph);
          const h = 0.5 + fl * 0.7;
          p.position.set(u.x, h * 0.45, u.z); p.scale.set(0.9 * h, 1.3 * h, 1);
          p.material.opacity = 0.75 * fade; p.material.color.setRGB(1, 0.45 + fl * 0.3, 0.12);
        }
        if (o.light) o.light.intensity = (1.5 + Math.sin(t * 17) * 0.5) * fade;
        if (Math.random() < 0.4) this.dust.emit(_v.set(f.pos.x + M.rand(-2, 2), f.pos.y + 0.8, f.pos.z + M.rand(-2, 2)), 0, 1.2, 0, 0.18, 0.16, 0.14, 0.7, 1.5, -0.8);
      }
      // armas no chão
      for (const [d, m] of this.drops) { m.position.set(d.pos.x, d.pos.y + 0.03, d.pos.z); m.rotation.set(0, d.id * 1.7, Math.PI / 2 * 0.98); }
      // bomba (no chão ou plantada; nas costas do portador não é desenhada)
      const b = world.bomb;
      const showBomb = b.state === 'available' || b.state === 'planted' || b.state === 'defusing' || b.state === 'defused' || b.state === 'planting';
      this.bombMesh.visible = showBomb && MP.game.mode === 'competitive' && b.state !== 'detonated';
      if (this.bombMesh.visible) {
        let p = b.pos;
        if (b.state === 'planting' && b.planter) p = b.planter.pos;
        this.bombMesh.position.set(p.x, p.y + 0.07, p.z);
        const planted = b.isPlanted;
        let blink = false;
        if (planted) { const left = b.explodeAt - t; const per = M.clamp(left / 40, 0.12, 1); blink = ((t - b.plantedAt) % per) < per * 0.35; }
        this.bombLed.visible = !planted || blink; this.bombGlow.visible = planted && blink;
      }
    }
  };
  MP.Particles = Particles;
})(typeof window !== 'undefined' ? window : globalThis);
