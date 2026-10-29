/* Mirage Protocol — modelos procedurais: armas, personagens articulados (com animação) e viewmodel em 1ª pessoa. */
(function (root) {
  'use strict';
  const MP = root.MP;
  const THREE = root.THREE;
  const M = MP.math;

  // ---------------------------------------------------------------- materiais compartilhados
  const mats = {};
  function mat(key, color, opts) {
    if (!mats[key]) mats[key] = new THREE.MeshLambertMaterial(Object.assign({ color }, opts || {}));
    return mats[key];
  }
  const geoCache = new Map();
  function boxGeo(w, h, d) {
    const k = w + ',' + h + ',' + d;
    if (!geoCache.has(k)) geoCache.set(k, new THREE.BoxGeometry(w, h, d));
    return geoCache.get(k);
  }
  function cylGeo(rt, rb, h, seg) {
    const k = 'c' + rt + ',' + rb + ',' + h + ',' + seg;
    if (!geoCache.has(k)) { const g = new THREE.CylinderGeometry(rt, rb, h, seg || 10); geoCache.set(k, g); }
    return geoCache.get(k);
  }
  function box(parent, w, h, d, x, y, z, m, name) {
    const mesh = new THREE.Mesh(boxGeo(w, h, d), m); mesh.position.set(x, y, z); if (name) mesh.name = name; parent.add(mesh); return mesh;
  }
  function cyl(parent, r, h, x, y, z, m, axis, seg) {
    const mesh = new THREE.Mesh(cylGeo(r, r, h, seg), m); mesh.position.set(x, y, z);
    if (axis === 'z') mesh.rotation.x = Math.PI / 2; else if (axis === 'x') mesh.rotation.z = Math.PI / 2;
    parent.add(mesh); return mesh;
  }

  // ---------------------------------------------------------------- armas
  /** Modelos de arma vêm de guns.js: hierarquia detalhada (viewmodel/bomba) ou cópia mesclada (mundo). */
  function buildWeapon(key, detailed) { return detailed ? MP.guns.detailed(key) : MP.guns.world(key); }

  // ---------------------------------------------------------------- personagens
  const TEAM_LOOK = {
    T: { shirt: 0x8a6a45, pants: 0x6d5c43, vest: 0x4a3e2c, skin: 0xb98a63, head: 0x2a2622, accent: 0xa0281e, boots: 0x2c2218 },
    CT: { shirt: 0x2e3f5c, pants: 0x29344a, vest: 0x56637a, skin: 0xc49a76, head: 0x1a1d22, accent: 0x7ec8ff, boots: 0x15171b }
  };
  function teamMat(team, part) {
    const L = TEAM_LOOK[team];
    if (part === 'shirt') {
      const key = 'camo' + team;
      if (!mats[key]) {
        const t = MP.textures.get(key, () => MP.textures.gen.camo(128, team === 'T' ? ['#8a6a45', '#6e5636', '#a58660', '#4f3d27'] : ['#2e3f5c', '#24324a', '#3c4f6e', '#1b2638']));
        mats[key] = new THREE.MeshLambertMaterial({ map: t });
      }
      return mats[key];
    }
    return mat(team + part, L[part]);
  }

  class Character {
    constructor(agent) {
      this.agent = agent; const team = agent.team;
      const root0 = this.root = new THREE.Group();
      const hips = this.hips = new THREE.Group(); hips.position.y = 0.95; root0.add(hips);
      const chest = this.chest = new THREE.Group(); chest.position.y = 0.05; hips.add(chest);
      const shirt = teamMat(team, 'shirt'), pants = teamMat(team, 'pants'), vest = teamMat(team, 'vest'), skin = teamMat(team, 'skin'), headM = teamMat(team, 'head'), accent = teamMat(team, 'accent'), boots = teamMat(team, 'boots');
      box(chest, 0.4, 0.55, 0.22, 0, 0.3, 0, shirt);
      box(chest, 0.42, 0.36, 0.25, 0, 0.36, 0, vest);              // colete
      if (team === 'CT') { box(chest, 0.3, 0.32, 0.12, 0, 0.36, 0.17, vest); }   // mochila
      else { const band = box(chest, 0.44, 0.06, 0.07, 0, 0.42, 0.05, mat('bandolier', 0x3a2c1c)); band.rotation.z = 0.7; }
      const neck = new THREE.Group(); neck.position.y = 0.6; chest.add(neck); this.neck = neck;
      box(neck, 0.1, 0.08, 0.1, 0, 0.03, 0, skin);
      const head = this.head = new THREE.Group(); head.position.y = 0.17; neck.add(head);
      box(head, 0.2, 0.24, 0.22, 0, 0, 0, team === 'T' ? headM : skin);
      if (team === 'CT') {
        box(head, 0.25, 0.12, 0.27, 0, 0.09, 0, headM);           // capacete
        box(head, 0.22, 0.05, 0.03, 0, 0.02, -0.12, mat('visor', 0x111518));
      } else {
        box(head, 0.16, 0.05, 0.02, 0, 0.02, -0.11, skin);         // abertura dos olhos
        box(head, 0.06, 0.03, 0.02, 0, 0.12, -0.08, headM);
      }
      // braços
      this.arms = [];
      for (const s of [-1, 1]) {
        const sh = new THREE.Group(); sh.position.set(0.25 * s, 0.5, 0); chest.add(sh);
        box(sh, 0.11, 0.3, 0.11, 0, -0.14, 0, shirt);
        if (s === -1) box(sh, 0.12, 0.05, 0.12, 0, -0.08, 0, accent);   // braçadeira (identificação além da cor)
        const el = new THREE.Group(); el.position.y = -0.29; sh.add(el);
        box(el, 0.1, 0.28, 0.1, 0, -0.13, 0, shirt);
        box(el, 0.09, 0.09, 0.09, 0, -0.29, 0, team === 'CT' ? mat('glove', 0x222222) : skin);
        this.arms.push({ sh, el });
      }
      // pernas
      this.legs = [];
      for (const s of [-1, 1]) {
        const hp = new THREE.Group(); hp.position.set(0.11 * s, 0, 0); hips.add(hp);
        box(hp, 0.16, 0.46, 0.17, 0, -0.22, 0, pants);
        const kn = new THREE.Group(); kn.position.y = -0.45; hp.add(kn);
        box(kn, 0.14, 0.44, 0.15, 0, -0.21, 0, pants);
        box(kn, 0.15, 0.08, 0.26, 0, -0.45, -0.05, boots);
        this.legs.push({ hp, kn });
      }
      // arma na mão
      this.weaponHolder = new THREE.Group(); this.weaponHolder.position.set(0.12, 0.32, -0.32); chest.add(this.weaponHolder);
      this.weaponKey = null;
      root0.traverse(o => { if (o.isMesh) { o.castShadow = true; } });
      this.phase = Math.random() * 6; this.deathT = 0; this.flashT = 0;
      this.muzzle = null;
    }
    setWeapon(def) {
      const key = def ? def.model : null;
      if (key === this.weaponKey) return;
      this.weaponKey = key;
      while (this.weaponHolder.children.length) this.weaponHolder.remove(this.weaponHolder.children[0]);
      if (!key) return;
      const w = buildWeapon(key); w.traverse(o => { if (o.isMesh) o.castShadow = true; });
      this.weaponHolder.add(w); this.muzzle = w.userData.muzzle;
      // pose dos braços conforme o tipo
      const pistol = def.cat === 'pistol' || def.cat === 'knife' || def.cat === 'grenade' || def.cat === 'bomb';
      this.pose = pistol ? 'pistol' : 'rifle';
    }
    update(dt) {
      const a = this.agent; const r = this.root;
      r.position.set(a.pos.x, a.pos.y, a.pos.z);
      if (!a.alive) {
        // queda (animação de morte simplificada)
        this.deathT = Math.min(1, this.deathT + dt * 2.2);
        const t = this.deathT, e = t * t * (3 - 2 * t);
        r.rotation.set(0, a.deathDir + Math.PI, 0);
        this.hips.rotation.x = e * 1.45;
        this.hips.position.y = 0.95 - e * 0.75;
        for (const l of this.legs) { l.hp.rotation.x = e * 0.6; l.kn.rotation.x = e * 0.4; }
        for (const am of this.arms) { am.sh.rotation.x = -e * 2.2; am.sh.rotation.z = 0; }
        return;
      }
      this.deathT = 0;
      r.rotation.set(0, a.yaw, 0);
      const crouch = a.crouchAmt;
      const sp = a.speedNow;
      this.phase += dt * (sp * 1.9);
      const swing = Math.min(1, sp / 5) * 0.7;
      const s = Math.sin(this.phase);
      this.hips.position.y = M.lerp(0.95, 0.62, crouch) + Math.abs(Math.cos(this.phase)) * 0.03 * swing;
      this.hips.rotation.x = 0;
      for (let i = 0; i < 2; i++) {
        const l = this.legs[i]; const side = i === 0 ? 1 : -1;
        const base = -crouch * 1.1;
        l.hp.rotation.x = base + s * swing * side;
        l.kn.rotation.x = crouch * 1.9 + Math.max(0, -s * side) * swing * 1.2;
      }
      if (!a.onGround) { this.legs[0].hp.rotation.x = -0.5; this.legs[1].hp.rotation.x = 0.2; this.legs[0].kn.rotation.x = 0.9; this.legs[1].kn.rotation.x = 0.5; }
      // inclinação do tronco segue o pitch da mira
      const p = M.clamp(a.pitch, -1.0, 1.0);
      this.chest.rotation.x = p * 0.6 + crouch * 0.15;
      this.neck.rotation.x = p * 0.4;
      // braços segurando a arma
      const [L, Rr] = this.arms;
      if (this.pose === 'rifle') {
        Rr.sh.rotation.set(-1.25, 0, 0.15); Rr.el.rotation.set(-0.5, 0, 0);
        L.sh.rotation.set(-1.4, 0, -0.55); L.el.rotation.set(-0.3, 0, 0);
        this.weaponHolder.position.set(0.1, 0.36, -0.36);
      } else {
        Rr.sh.rotation.set(-1.45, 0, 0.3); Rr.el.rotation.set(-0.1, 0, 0);
        L.sh.rotation.set(-1.45, 0, -0.3); L.el.rotation.set(-0.1, 0, 0);
        this.weaponHolder.position.set(0.02, 0.4, -0.52);
      }
      // recarga visível: abaixa a arma
      const w = a.weapon;
      if (w && w.reloading) { this.weaponHolder.rotation.x = -0.5; } else this.weaponHolder.rotation.x = 0;
      // plantando/desarmando: agachado com os braços abaixados
      if (a.intent.use && crouch > 0.5) { L.sh.rotation.x = -0.6; Rr.sh.rotation.x = -0.6; }
    }
    resetPose() { this.deathT = 0; this.root.rotation.set(0, 0, 0); this.hips.rotation.set(0, 0, 0); }
    muzzleWorld(out) {
      if (this.muzzle) { this.muzzle.getWorldPosition(out); return out; }
      return out.set(this.agent.pos.x, this.agent.pos.y + 1.4, this.agent.pos.z);
    }
  }

  function cylGeoV(r, h) { return cylGeo(r, r, h, 12); }
  let _armGeo = null;
  function armGeo() {
    if (!_armGeo) { _armGeo = new THREE.CylinderGeometry(0.026, 0.036, 1, 12); _armGeo.rotateX(Math.PI / 2); }
    return _armGeo;
  }
  // ---------------------------------------------------------------- viewmodel
  class Viewmodel {
    constructor(scene, camera) {
      this.scene = scene; this.camera = camera;
      this.root = new THREE.Group(); scene.add(this.root);
      this.current = null; this.key = null; this.team = null;
      this.kick = 0; this.kickRot = 0; this.swayX = 0; this.swayY = 0; this.bob = 0;
      this.drawT = 1; this.drawDur = 0.5; this.slashT = 1; this.slashAlt = false; this.throwT = 1; this.inspectT = 1;
      this.flash = new THREE.Sprite(new THREE.SpriteMaterial({ map: MP.textures.get('flashStar', () => MP.textures.gen.flashStar(128), { clamp: true }), blending: THREE.AdditiveBlending, depthWrite: false, transparent: true }));
      this.flash.visible = false; this.flash.scale.set(0.22, 0.22, 0.22);
      this.flashUntil = 0;
      this.arms = new THREE.Group();
    }
    set(def, team) {
      const key = def ? def.model : null;
      if (key === this.key && team === this.team) { this.drawT = 0; this.drawDur = def ? def.draw : 0.5; return; }
      this.key = key; this.team = team;
      if (this.current) this.root.remove(this.current);
      this.current = null;
      if (!key) return;
      const g = new THREE.Group();
      const w = buildWeapon(key, true); g.add(w);
      this.weapon = w; this.mag = w.userData.mag; this.magHome = w.userData.magHome;
      // braços: mangas da equipe + luvas, apontando dos ombros (fora da tela) até as mãos
      const L = TEAM_LOOK[team || 'CT'];
      const sleeve = mat('vmSleeve' + team, L.shirt), glove = mat('vmGlove' + team, team === 'CT' ? 0x222428 : 0x6b5a45);
      const mkArm = (hand, shoulder) => {
        const hv = new THREE.Vector3(...hand), sv = new THREE.Vector3(...shoulder);
        const len = hv.distanceTo(sv);
        // antebraço arredondado e afunilado em direção ao punho
        const arm = new THREE.Mesh(armGeo(), sleeve);
        arm.scale.z = len; arm.position.copy(hv).add(sv).multiplyScalar(0.5); arm.lookAt(hv);
        const gl = new THREE.Group(); gl.position.copy(hv); gl.quaternion.copy(arm.quaternion);
        const palm = new THREE.Mesh(boxGeo(0.055, 0.062, 0.08), glove); gl.add(palm);
        const cuff = new THREE.Mesh(cylGeoV(0.034, 0.03), sleeve); cuff.rotation.x = Math.PI / 2; cuff.position.z = 0.055; gl.add(cuff);
        const band = new THREE.Mesh(cylGeoV(0.031, 0.012), mat('vmBand', 0x15171a)); band.rotation.x = Math.PI / 2; band.position.z = 0.035; gl.add(band);
        // dedos fechados em volta da empunhadura + polegar
        for (let i = 0; i < 4; i++) {
          const f1 = new THREE.Mesh(boxGeo(0.014, 0.016, 0.03), glove); f1.position.set(0.034, 0.018 - i * 0.015, -0.02); f1.rotation.y = 0.4; gl.add(f1);
          const f2 = new THREE.Mesh(boxGeo(0.013, 0.015, 0.024), glove); f2.position.set(0.04, 0.018 - i * 0.015, -0.045); f2.rotation.y = 1.3; gl.add(f2);
          const k = new THREE.Mesh(boxGeo(0.006, 0.012, 0.012), mat('vmKnuckle' + team, team === 'CT' ? 0x34373c : 0x4a3d2e)); k.position.set(0.03, 0.018 - i * 0.015, -0.002); gl.add(k);
        }
        const th = new THREE.Mesh(boxGeo(0.015, 0.016, 0.04), glove); th.position.set(-0.03, 0.02, -0.03); th.rotation.set(0.2, -0.5, 0); gl.add(th);
        return [arm, gl];
      };
      const h = w.userData.hold;
      for (const m of mkArm(h.grip, [0.16, -0.38, 0.5])) g.add(m);
      if (h.support) for (const m of mkArm(h.support, [-0.3, -0.42, 0.3])) g.add(m);
      g.traverse(o => { if (o.isMesh) { o.frustumCulled = false; } });
      w.userData.muzzle.add(this.flash);
      this.current = g; this.root.add(g);
      this.def = def;
      this.drawT = 0; this.drawDur = def.draw || 0.5;
    }
    onFire(def) {
      const heavy = def.cat === 'sniper' || def.cat === 'heavy' || def.id === 'falcao' || def.id === 'rhino';
      this.kick = Math.min(this.kick + (heavy ? 0.07 : 0.035), 0.12);
      this.kickRot = Math.min(this.kickRot + (heavy ? 0.16 : 0.06), 0.3);
      if (def.mode !== 'melee' && def.cat !== 'grenade') {
        this.flash.visible = true; this.flash.material.rotation = Math.random() * 6;
        const s = (def.cat === 'pistol' ? 0.16 : 0.26) * (0.8 + Math.random() * 0.4); this.flash.scale.set(s, s, s);
        this.flashUntil = 0.045;
      }
    }
    onSlash(alt) { this.slashT = 0; this.slashAlt = alt; }
    onThrow() { this.throwT = 0; }
    inspect() { if (this.drawT >= 1 && this.inspectT >= 1) this.inspectT = 0; }
    update(dt, a, look) {
      if (!this.current) return;
      const w = a.weapon; const def = this.def;
      const now = MP.world.time;
      // decaimentos
      this.kick *= Math.exp(-dt * 14); this.kickRot *= Math.exp(-dt * 11);
      if (this.flashUntil > 0) { this.flashUntil -= dt; if (this.flashUntil <= 0) this.flash.visible = false; }
      this.drawT = Math.min(1, this.drawT + dt / Math.max(0.1, this.drawDur));
      this.slashT = Math.min(1, this.slashT + dt * 3);
      this.throwT = Math.min(1, this.throwT + dt * 2.5);
      this.inspectT = Math.min(1, this.inspectT + dt / 3.2);
      const busy = (w && w.reloading) || now - (w ? w.lastShot : -9) < 0.3;
      if (busy) this.inspectT = 1;
      // balanço ao andar
      const sp = a.onGround ? Math.min(1, a.speedNow / 6) : 0;
      this.bob += dt * a.speedNow * 1.7;
      const bx = Math.sin(this.bob) * 0.012 * sp, by = -Math.abs(Math.cos(this.bob)) * 0.012 * sp;
      // atraso ao olhar
      this.swayX = M.lerp(this.swayX, M.clamp(-look.dx * 0.0009, -0.05, 0.05), Math.min(1, dt * 10));
      this.swayY = M.lerp(this.swayY, M.clamp(look.dy * 0.0009, -0.05, 0.05), Math.min(1, dt * 10));
      const pistol = def.cat === 'pistol';
      let x = pistol ? 0.13 : 0.16, y = pistol ? -0.13 : -0.165, z = pistol ? -0.42 : -0.47;
      if (def.cat === 'knife') { x = 0.15; y = -0.14; z = -0.36; }
      if (def.cat === 'grenade' || def.cat === 'bomb') { x = 0.14; y = -0.15; z = -0.38; }
      // guinada: cano aponta para o centro e a lateral direita da arma fica à mostra (como nos FPS táticos)
      let rx = 0.02, ry = def.cat === 'knife' ? 0.45 : pistol ? 0.24 : 0.36, rz = def.cat === 'knife' ? -0.25 : -0.07;
      // saque
      const d = 1 - this.drawT, de = d * d;
      y -= de * 0.3; rx -= de * 0.8;
      // recarga
      if (w && w.reloading && def.mag) {
        const p = w.reloadProgress(now);
        if (def.reloadType === 'shell') { const k = (now * 2) % 1; rx += 0.25; rz += 0.2; z += Math.sin(k * Math.PI) * 0.02; }
        else {
          const dip = Math.sin(Math.min(1, p) * Math.PI);
          y -= dip * 0.07; rx += dip * 0.35; rz += dip * 0.45;
          if (this.mag) {
            const out = p < 0.18 ? p / 0.18 : p < 0.55 ? 1 : p < 0.75 ? 1 - (p - 0.55) / 0.2 : 0;
            this.mag.position.set(this.magHome.x, this.magHome.y - out * 0.3, this.magHome.z + out * 0.05);
          }
        }
      } else if (this.mag) this.mag.position.copy(this.magHome);
      // facada
      if (this.slashT < 1) { const t = Math.sin(this.slashT * Math.PI); if (this.slashAlt) { z -= t * 0.15; rx -= t * 0.3; } else { x -= t * 0.18; ry += t * 1.1; rz += t * 0.6; } }
      // arremesso
      if (this.throwT < 1) { const t = Math.sin(this.throwT * Math.PI); z -= t * 0.25; y += t * 0.12; rx -= t * 0.9; }
      // inspeção: gira a arma para mostrar as laterais
      if (this.inspectT < 1) {
        const t = this.inspectT, sm = (u) => u * u * (3 - 2 * u);
        const k1 = sm(Math.min(1, t / 0.18)), k2 = sm(Math.max(0, Math.min(1, (t - 0.45) / 0.15))), k3 = sm(Math.max(0, Math.min(1, (t - 0.82) / 0.18)));
        const side = k1 * (1 - k2), other = k2 * (1 - k3);
        ry += side * 1.25 - other * 0.55; rz += side * 0.25 - other * 0.35; rx += side * 0.1 + other * 0.35;
        x -= (side + other) * 0.06; z += (side + other) * 0.06; y += side * 0.03;
      }
      // agachado
      y -= a.crouchAmt * 0.012;
      this.root.position.set(x + bx + this.swayX, y + by + this.swayY, z + this.kick);
      this.root.rotation.set(rx + this.kickRot + this.swayY * 2, ry + this.swayX * 2, rz);
      // led da bomba pisca
      const led = this.current.getObjectByName && this.current.getObjectByName('led');
      if (led) led.visible = (now * 2) % 1 < 0.5;
      const scoped = w && w.zoomLevel > 0;
      this.root.visible = !scoped;
    }
  }

  MP.models = { buildWeapon, Character, Viewmodel, mat, box, TEAM_LOOK };
})(typeof window !== 'undefined' ? window : globalThis);
