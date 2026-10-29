/* Mirage Protocol — renderização: WebGLRenderer, céu, luz, sombras, malha procedural do mapa e qualidade. */
(function (root) {
  'use strict';
  const MP = root.MP;
  const THREE = root.THREE;
  const { map } = MP;

  const QUALITY = {
    low: { dpr: 1.0, shadows: 0, particles: 140, smokeSprites: 9, tex: 256, standard: false, fogFar: 110, lights: false, aniso: 1, decals: 50 },
    medium: { dpr: 1.5, shadows: 1, particles: 320, smokeSprites: 14, tex: 512, standard: false, fogFar: 150, lights: true, aniso: 2, decals: 100 },
    high: { dpr: 2.0, shadows: 2, particles: 650, smokeSprites: 20, tex: 512, standard: true, fogFar: 190, lights: true, aniso: 4, decals: 160 }
  };
  MP.QUALITY = QUALITY;

  function detectQuality() {
    const coarse = typeof matchMedia !== 'undefined' && matchMedia('(pointer: coarse)').matches;
    const cores = navigator.hardwareConcurrency || 4;
    const mem = navigator.deviceMemory || 4;
    if (coarse) return (cores >= 8 && mem >= 6) ? 'medium' : 'low';
    return cores >= 4 ? 'high' : 'medium';
  }

  /** Acumulador de geometria por material (uma malha por material = poucas chamadas de desenho). */
  class GeoBuilder {
    constructor() { this.pos = []; this.nor = []; this.uv = []; this.col = []; this.idx = []; }
    quad(p0, p1, p2, p3, n, uv, cols) {
      const b = this.pos.length / 3;
      for (const p of [p0, p1, p2, p3]) this.pos.push(p[0], p[1], p[2]);
      for (let i = 0; i < 4; i++) this.nor.push(n[0], n[1], n[2]);
      for (const t of uv) this.uv.push(t[0], t[1]);
      for (const c of cols) this.col.push(c, c, c);
      this.idx.push(b, b + 1, b + 2, b, b + 2, b + 3);
    }
    build() {
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute(this.pos, 3));
      g.setAttribute('normal', new THREE.Float32BufferAttribute(this.nor, 3));
      g.setAttribute('uv', new THREE.Float32BufferAttribute(this.uv, 2));
      g.setAttribute('color', new THREE.Float32BufferAttribute(this.col, 3));
      g.setIndex(this.idx);
      g.computeBoundingSphere();
      return g;
    }
    get empty() { return this.pos.length === 0; }
  }

  const R = MP.render = {
    renderer: null, scene: null, camera: null, vmScene: null, vmCamera: null,
    q: null, qKey: 'medium', sun: null, materials: {}, mapMeshes: [], ok: false, contextLost: false,
    tunnelLights: [],

    init(canvas) {
      const s = MP.settings.values;
      this.qKey = s.quality === 'auto' ? detectQuality() : s.quality;
      this.q = QUALITY[this.qKey];
      // cores hexadecimais tratadas como sRGB (iluminação linear correta)
      if (THREE.ColorManagement) THREE.ColorManagement.legacyMode = false;
      let renderer;
      try {
        renderer = new THREE.WebGLRenderer({ canvas, antialias: this.qKey === 'high', powerPreference: 'high-performance', alpha: false, stencil: false });
      } catch (e) {
        throw new Error('Não foi possível criar o contexto WebGL: ' + (e && e.message ? e.message : e));
      }
      this.renderer = renderer;
      renderer.info.autoReset = false;
      MP.guns.initEnv(renderer);
      renderer.outputEncoding = THREE.sRGBEncoding;
      renderer.toneMapping = THREE.ACESFilmicToneMapping;
      renderer.toneMappingExposure = 1.05;
      renderer.autoClear = false;
      renderer.shadowMap.type = THREE.PCFSoftShadowMap;
      canvas.addEventListener('webglcontextlost', (e) => { e.preventDefault(); this.contextLost = true; MP.events.emit('gl:lost'); }, false);
      canvas.addEventListener('webglcontextrestored', () => { this.contextLost = false; this.onRestore(); MP.events.emit('gl:restored'); }, false);

      const scene = this.scene = new THREE.Scene();
      scene.fog = new THREE.Fog(0xd9c8a8, 40, this.q.fogFar);
      this.camera = new THREE.PerspectiveCamera(s.fov, 16 / 9, 0.05, 400);
      this.camera.rotation.order = 'YXZ';
      scene.add(this.camera);

      // luzes
      const hemi = new THREE.HemisphereLight(0xe3ecff, 0xb08c5c, 0.75);
      scene.add(hemi);
      const sun = this.sun = new THREE.DirectionalLight(0xfff0d2, 1.35);
      sun.position.set(-45, 85, 30);
      sun.target.position.set(0, 0, 0);
      scene.add(sun); scene.add(sun.target);
      const sc = sun.shadow.camera;
      sc.left = -56; sc.right = 56; sc.top = 50; sc.bottom = -50; sc.near = 10; sc.far = 220;
      sun.shadow.bias = -0.0006; sun.shadow.normalBias = 0.03;
      this.ambient = new THREE.AmbientLight(0xffffff, 0.12); scene.add(this.ambient);

      this.buildSky();
      this.buildMaterials();
      this.buildMap();
      this.buildDecor();

      // cena do viewmodel (arma em primeira pessoa), renderizada por cima com depth limpo
      this.vmScene = new THREE.Scene();
      this.vmCamera = new THREE.PerspectiveCamera(56, 16 / 9, 0.01, 10);
      this.vmScene.add(new THREE.HemisphereLight(0xfff4e0, 0x6a5a48, 0.9));
      const vmSun = new THREE.DirectionalLight(0xfff0d2, 0.9); vmSun.position.set(-1, 2, 1); this.vmScene.add(vmSun);
      this.vmScene.add(new THREE.AmbientLight(0xffffff, 0.15));

      this.applyQuality();
      this.resize();
      this.ok = true;
      return this;
    },

    buildSky() {
      const geo = new THREE.SphereGeometry(300, 24, 12);
      const mat = new THREE.ShaderMaterial({
        side: THREE.BackSide, depthWrite: false, fog: false,
        uniforms: { sunDir: { value: new THREE.Vector3(-45, 85, 30).normalize() } },
        vertexShader: 'varying vec3 vDir; void main(){ vDir = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
        fragmentShader: [
          'uniform vec3 sunDir; varying vec3 vDir;',
          'void main(){',
          ' float h = clamp(vDir.y, -0.2, 1.0);',
          ' vec3 horizon = vec3(0.93,0.85,0.70); vec3 zenith = vec3(0.32,0.55,0.86);',
          ' vec3 col = mix(horizon, zenith, pow(max(h,0.0), 0.55));',
          ' if (h < 0.0) col = mix(horizon, vec3(0.78,0.66,0.48), clamp(-h*5.0,0.0,1.0));',
          ' float sd = max(dot(normalize(vDir), sunDir), 0.0);',
          ' col += vec3(1.0,0.85,0.6) * pow(sd, 18.0) * 0.45 + vec3(1.0,0.95,0.85) * pow(sd, 900.0) * 3.0;',
          ' // faixas de poeira no horizonte',
          ' col = mix(col, vec3(0.9,0.8,0.62), smoothstep(0.12,0.0,abs(h-0.02))*0.35);',
          ' gl_FragColor = vec4(col,1.0);',
          '}'
        ].join('\n')
      });
      const sky = new THREE.Mesh(geo, mat); sky.renderOrder = -10; sky.frustumCulled = false;
      this.scene.add(sky); this.sky = sky;
      // horizonte de prédios distantes
      const ring = new GeoBuilder();
      for (let i = 0; i < 46; i++) {
        const a = i / 46 * Math.PI * 2, dist = 95 + (i * 37 % 23);
        const w = 8 + (i * 13 % 9), h = 10 + (i * 29 % 17);
        const cx = Math.cos(a) * dist, cz = Math.sin(a) * dist * 0.9;
        const nx = -Math.cos(a), nz = -Math.sin(a);
        const tx = -nz, tz = nx;
        const p = (s, y) => [cx + tx * s * w / 2, y, cz + tz * s * w / 2];
        ring.quad(p(-1, 0), p(1, 0), p(1, h), p(-1, h), [nx, 0, nz], [[0, 0], [1, 0], [1, 1], [0, 1]], [0.8, 0.8, 1, 1]);
      }
      const ringMat = new THREE.MeshBasicMaterial({ color: 0xb8a588, vertexColors: true, fog: true });
      const ringMesh = new THREE.Mesh(ring.build(), ringMat); this.scene.add(ringMesh);
      // chão infinito além dos muros
      const g = new THREE.PlaneGeometry(600, 600); g.rotateX(-Math.PI / 2);
      const ground = new THREE.Mesh(g, new THREE.MeshBasicMaterial({ color: 0xbfa274 })); ground.position.y = -0.02; this.scene.add(ground);
    },

    tex(key, builder, aniso) {
      return MP.textures.get(key + '@' + this.q.tex, builder, { aniso: aniso || this.q.aniso });
    },
    buildMaterials() {
      const G = MP.textures.gen, S = this.q.tex;
      const defs = {
        plaster: { t: () => G.plaster(S), rough: 0.95 },
        plaster2: { t: () => G.plaster(S, '#d6ccb6'), rough: 0.95 },
        brick: { t: () => G.brick(S), rough: 0.9 },
        concrete: { t: () => G.concrete(S), rough: 0.9 },
        pillar: { t: () => G.concrete(S, '#b0a898'), rough: 0.9 },
        roof: { t: () => G.concrete(S, '#7e776c'), rough: 1 },
        trim: { t: () => G.trim(S), rough: 0.9 },
        sand: { t: () => G.sand(S), rough: 1 },
        tile: { t: () => G.tile(S), rough: 0.8 },
        slab: { t: () => G.slab(S), rough: 0.9 },
        tunnel: { t: () => G.tunnel(S), rough: 0.95 },
        wood: { t: () => G.crate(S, false), rough: 0.85 },
        woodLow: { t: () => G.crate(S, true), rough: 0.85 },
        metal0: { t: () => G.container(S, '#8c2f24'), rough: 0.55, metal: 0.4 },
        metal1: { t: () => G.container(S, '#2c5a7a'), rough: 0.55, metal: 0.4 },
        metal2: { t: () => G.container(S, '#4f6b38'), rough: 0.55, metal: 0.4 },
        sandbag: { t: () => G.sandbag(S), rough: 1 },
        step: { t: () => G.step(S), rough: 0.9 },
        window: { t: () => G.windowTex(256), rough: 0.4 },
        door: { t: () => G.door(256), rough: 0.8 },
        darkmetal: { t: () => G.metalDark(128), rough: 0.5, metal: 0.6 },
        roofprop: { t: () => G.concrete(128, '#9aa0a3'), rough: 0.6, metal: 0.3 }
      };
      for (const k of Object.keys(defs)) {
        const d = defs[k];
        const map0 = this.tex(k, d.t);
        const lam = new THREE.MeshLambertMaterial({ map: map0, vertexColors: true });
        const std = new THREE.MeshStandardMaterial({ map: map0, vertexColors: true, roughness: d.rough, metalness: d.metal || 0 });
        this.materials[k] = { lam, std };
      }
      const lamp = new THREE.MeshBasicMaterial({ color: 0xfff1c0 });
      this.materials.lamp = { lam: lamp, std: lamp };
    },
    mat(k) { const m = this.materials[k]; return this.q.standard ? m.std : m.lam; },

    buildMap() {
      const B = {}; const get = (k) => (B[k] = B[k] || new GeoBuilder());
      const W = map.W, H = map.H, S = map.S, OX = map.OX, OZ = map.OZ;
      const cells = map.cells;
      const wallMats = { plaster: 1, plaster2: 1, brick: 1, concrete: 1, pillar: 1 };
      // componentes de contêineres para cor consistente
      const contColor = new Map(); let cid = 0;
      for (let i = 0; i < W * H; i++) {
        if (cells[i].ch !== 'k' || contColor.has(i)) continue;
        const stack = [i]; const color = cid++ % 3;
        while (stack.length) { const j = stack.pop(); if (contColor.has(j) || cells[j].ch !== 'k') continue; contColor.set(j, color); const c = j % W, r = (j / W) | 0; if (c > 0) stack.push(j - 1); if (c < W - 1) stack.push(j + 1); if (r > 0) stack.push(j - W); if (r < H - 1) stack.push(j + W); }
      }
      const matOf = (cell) => {
        if (cell.ch === 'k') return 'metal' + contColor.get(cell.r * W + cell.c);
        if (cell.ch === 'c') return 'woodLow';
        if (cell.ch === 'C') return 'wood';
        if (cell.ch === 'w') return 'sandbag';
        if (cell.ch === '1' || cell.ch === '2' || cell.ch === '3') return 'step';
        if (cell.ch === '=' || cell.ch === 'D') return cell.ch === '=' ? 'tunnel' : 'trim';
        return cell.mat;
      };
      const perFace = (k) => k === 'woodLow' || k === 'wood' || k === 'sandbag';
      const texScale = (k) => k === 'brick' ? 3 : k === 'tile' ? 4 : k === 'trim' ? 4 : k === 'step' ? 2 : k.startsWith('metal') ? 2.6 : 4;
      const ao = (y) => 0.58 + 0.42 * Math.min(1, Math.max(0, y / 2.4));
      const covered = (cell) => cell && cell.ceil;

      // intervalos visíveis de [y0,y1] descontando os spans do vizinho
      const visible = (y0, y1, n) => {
        if (!n) return [];
        let segs = [[y0, y1]];
        for (const s of n.spans) {
          const out = [];
          for (const [a, b] of segs) {
            if (s[1] <= a || s[0] >= b) { out.push([a, b]); continue; }
            if (s[0] > a) out.push([a, s[0]]);
            if (s[1] < b) out.push([s[1], b]);
          }
          segs = out;
        }
        return segs.filter(([a, b]) => b - a > 0.01);
      };
      const sides = [
        { dc: 1, dr: 0, n: [1, 0, 0] }, { dc: -1, dr: 0, n: [-1, 0, 0] },
        { dc: 0, dr: 1, n: [0, 0, 1] }, { dc: 0, dr: -1, n: [0, 0, -1] }
      ];
      this.wallFaces = [];
      for (let r = 0; r < H; r++) for (let c = 0; c < W; c++) {
        const cell = cells[r * W + c];
        const x0 = OX + c * S, x1 = x0 + S, z0 = OZ + r * S, z1 = z0 + S;
        // chão
        if (cell.floor !== null && !(cell.spans.length && cell.spans[0][0] === 0)) {
          const k = cell.mat === 'concrete' ? 'slab' : cell.mat;
          const vAO = (vc, vr) => {
            let n = 0;
            for (const [a, b] of [[vc - 1, vr - 1], [vc, vr - 1], [vc - 1, vr], [vc, vr]]) { const cc = map.cellAt(a, b); if (!cc || (cc.spans.length && cc.spans[0][0] === 0 && cc.spans[0][1] > 0.5)) n++; }
            let v = 1 - n * 0.13;
            if (covered(cell)) v *= 0.48;
            return v;
          };
          const ts = texScale(k);
          get(k).quad([x0, 0, z1], [x1, 0, z1], [x1, 0, z0], [x0, 0, z0], [0, 1, 0],
            [[x0 / ts, z1 / ts], [x1 / ts, z1 / ts], [x1 / ts, z0 / ts], [x0 / ts, z0 / ts]],
            [vAO(c, r + 1), vAO(c + 1, r + 1), vAO(c + 1, r), vAO(c, r)]);
        }
        for (let si = 0; si < cell.spans.length; si++) {
          const sp = cell.spans[si];
          const isCeil = sp[0] > 0;
          const k = isCeil ? (cell.ch === 'D' ? 'trim' : 'tunnel') : matOf(cell);
          const ts = texScale(k);
          const isWall = !isCeil && wallMats[cell.mat] && T_isSolid(cell);
          // topo
          const above = cell.spans.find(s => s !== sp && Math.abs(s[0] - sp[1]) < 0.01);
          if (!above) {
            const tk = isWall ? 'roof' : k;
            const tts = texScale(tk);
            const uvs = perFace(tk) ? [[0, 0], [1, 0], [1, 1], [0, 1]] : [[x0 / tts, z1 / tts], [x1 / tts, z1 / tts], [x1 / tts, z0 / tts], [x0 / tts, z0 / tts]];
            get(tk).quad([x0, sp[1], z1], [x1, sp[1], z1], [x1, sp[1], z0], [x0, sp[1], z0], [0, 1, 0], uvs, [1, 1, 1, 1]);
          }
          // base (tetos de túnel/porta)
          if (isCeil) {
            get(k).quad([x0, sp[0], z0], [x1, sp[0], z0], [x1, sp[0], z1], [x0, sp[0], z1], [0, -1, 0],
              [[x0 / ts, z0 / ts], [x1 / ts, z0 / ts], [x1 / ts, z1 / ts], [x0 / ts, z1 / ts]], [0.45, 0.45, 0.45, 0.45]);
          }
          // laterais
          for (const sd of sides) {
            const nb = map.cellAt(c + sd.dc, r + sd.dr);
            const segs = visible(sp[0], sp[1], nb);
            if (!segs.length) continue;
            let ax, az, bx, bz;
            if (sd.dc === 1) { ax = x1; az = z1; bx = x1; bz = z0; }
            else if (sd.dc === -1) { ax = x0; az = z0; bx = x0; bz = z1; }
            else if (sd.dr === 1) { ax = x0; az = z1; bx = x1; bz = z1; }
            else { ax = x1; az = z0; bx = x0; bz = z0; }
            const dark = covered(nb) ? 0.5 : 1;
            for (let [y0, y1] of segs) {
              const emit = (kk, ya, yb, faceUV) => {
                const tsk = texScale(kk);
                const ua = sd.dc !== 0 ? az : ax, ub = sd.dc !== 0 ? bz : bx;
                let uv;
                if (faceUV) { const hh = cell.ch === 'C' ? 2 : 1; uv = [[0, ya / hh], [1, ya / hh], [1, yb / hh], [0, yb / hh]]; }
                else uv = [[ua / tsk * (sd.dc === -1 || sd.dr === 1 ? 1 : -1), ya / tsk], [ub / tsk * (sd.dc === -1 || sd.dr === 1 ? 1 : -1), ya / tsk], [ub / tsk * (sd.dc === -1 || sd.dr === 1 ? 1 : -1), yb / tsk], [ua / tsk * (sd.dc === -1 || sd.dr === 1 ? 1 : -1), yb / tsk]];
                const ca = (isCeil ? 0.5 : ao(ya)) * dark, cb = (isCeil ? 0.5 : ao(yb)) * dark;
                get(kk).quad([ax, ya, az], [bx, ya, bz], [bx, yb, bz], [ax, yb, az], sd.n, uv, [ca, ca, cb, cb]);
              };
              if (isWall && y1 >= sp[1] - 0.01 && y1 - y0 > 2.5) {
                emit(k, y0, y1 - 0.45, false);
                emit('trim', y1 - 0.45, y1, false);
                if (nb && nb.floor !== null && !nb.ceil) this.wallFaces.push({ ax, az, bx, bz, n: sd.n, h: y1, c, r, nb });
              } else emit(k, y0, y1, perFace(k));
            }
          }
        }
      }
      for (const k of Object.keys(B)) {
        if (B[k].empty) continue;
        const mesh = new THREE.Mesh(B[k].build(), this.mat(k));
        mesh.userData.matKey = k;
        mesh.receiveShadow = true; mesh.castShadow = k !== 'sand' && k !== 'tile' && k !== 'slab';
        mesh.matrixAutoUpdate = false; mesh.updateMatrix();
        this.scene.add(mesh); this.mapMeshes.push(mesh);
      }
      function T_isSolid(cell) { return MP.CELL_TYPES[cell.ch] && MP.CELL_TYPES[cell.ch].solid; }
    },

    /** Detalhes arquitetônicos: janelas, portas decorativas, letreiros, lâmpadas, objetos de telhado, fios. */
    buildDecor() {
      const win = new GeoBuilder(), door = new GeoBuilder(), props = new GeoBuilder(), lamps = new GeoBuilder();
      let seed = 1234; const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
      const off = 0.03;
      for (const f of this.wallFaces) {
        const nx = f.n[0], nz = f.n[2];
        const mx = (f.ax + f.bx) / 2 + nx * off, mz = (f.az + f.bz) / 2 + nz * off;
        const tx = (f.bx - f.ax) / 2, tz = (f.bz - f.az) / 2; // meia aresta
        const q = (b, w, y0, y1, uv) => {
          const s = w / 2;
          b.quad([mx - tx * s, y0, mz - tz * s], [mx + tx * s, y0, mz + tz * s], [mx + tx * s, y1, mz + tz * s], [mx - tx * s, y1, mz - tz * s], f.n, uv || [[0, 0], [1, 0], [1, 1], [0, 1]], [1, 1, 1, 1]);
        };
        const rr = rnd();
        if (f.h >= 5.5 && rr < 0.45) q(win, 0.6, 3.1, 4.5);
        if (f.h >= 7.4 && rnd() < 0.35) q(win, 0.6, 5.3, 6.6);
        const nbDoor = f.nb && (f.nb.ch === 'D');
        if (!nbDoor && rr > 0.88) q(door, 0.55, 0.0, 2.2);
      }
      const add = (b, k, shadow) => {
        if (b.empty) return;
        const m = new THREE.Mesh(b.build(), this.mat(k)); m.userData.matKey = k; m.castShadow = !!shadow; m.receiveShadow = true;
        m.matrixAutoUpdate = false; m.updateMatrix(); this.scene.add(m); this.mapMeshes.push(m);
      };
      add(win, 'window'); add(door, 'door');
      // objetos de telhado (ar-condicionado, caixas d'água) — fora do alcance do jogador
      const box = (b, cx, y, cz, sx, sy, sz, col) => {
        const x0 = cx - sx / 2, x1 = cx + sx / 2, z0 = cz - sz / 2, z1 = cz + sz / 2, y1 = y + sy;
        const uv = [[0, 0], [1, 0], [1, 1], [0, 1]], c = [col * 0.8, col * 0.8, col, col];
        b.quad([x0, y1, z1], [x1, y1, z1], [x1, y1, z0], [x0, y1, z0], [0, 1, 0], uv, [col, col, col, col]);
        b.quad([x1, y, z1], [x1, y, z0], [x1, y1, z0], [x1, y1, z1], [1, 0, 0], uv, c);
        b.quad([x0, y, z0], [x0, y, z1], [x0, y1, z1], [x0, y1, z0], [-1, 0, 0], uv, c);
        b.quad([x0, y, z1], [x1, y, z1], [x1, y1, z1], [x0, y1, z1], [0, 0, 1], uv, c);
        b.quad([x1, y, z0], [x0, y, z0], [x0, y1, z0], [x1, y1, z0], [0, 0, -1], uv, c);
      };
      for (let r = 1; r < map.H - 1; r++) for (let c = 1; c < map.W - 1; c++) {
        const cell = map.cellAt(c, r);
        if (!MP.CELL_TYPES[cell.ch].solid || cell.ch === 'p') continue;
        const v = ((c * 7919) ^ (r * 104729)) % 23;
        if (v === 0) box(props, map.cellX(c), cell.top, map.cellZ(r), 1.2, 0.8, 0.9, 0.9);
        else if (v === 5 && (c + r) % 3 === 0) { box(props, map.cellX(c), cell.top, map.cellZ(r), 0.2, 1.2, 0.2, 0.7); box(props, map.cellX(c), cell.top + 1.2, map.cellZ(r), 1.2, 1.1, 1.2, 1.0); }
        else if (v === 9 && c % 2 === 0) box(props, map.cellX(c) + 0.4, cell.top, map.cellZ(r), 0.06, 3.0, 0.06, 0.6);
      }
      add(props, 'roofprop', true);
      // lâmpadas no túnel (emissivas) + luzes pontuais na qualidade alta
      for (let r = 17; r <= 29; r += 4) {
        const cell = map.cellAt(40, r); if (!cell || !cell.ceil) continue;
        const x = map.cellX(40.5), z = map.cellZ(r), y = cell.ceil[0] - 0.05;
        box(lamps, x, y - 0.08, z, 1.4, 0.08, 0.25, 1);
        if (this.q.lights && this.qKey === 'high') {
          const pl = new THREE.PointLight(0xffe2a8, 0.9, 11, 2); pl.position.set(x, y - 0.4, z); this.scene.add(pl); this.tunnelLights.push(pl);
        }
      }
      add(lamps, 'lamp');
      // letreiros e letras dos bombsites
      const sprite = (key, builder, w, h, x, y, z, rotY) => {
        const t = MP.textures.get(key, builder, { clamp: true });
        const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshLambertMaterial({ map: t, transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2 }));
        m.position.set(x, y, z); m.rotation.y = rotY; this.scene.add(m);
      };
      const G = MP.textures.gen;
      sprite('siteA', () => G.siteLetter(256, 'A'), 3.2, 3.2, map.OX + 16 * map.S - 0.03, 3, map.cellZ(9.5), -Math.PI / 2);
      sprite('siteA2', () => G.siteLetter(256, 'A'), 2, 2, map.cellX(4.5), 2.4, map.OZ + 5 * map.S + 0.03, 0);
      sprite('siteB', () => G.siteLetter(256, 'B'), 3.2, 3.2, map.OX + 32 * map.S + 0.03, 3, map.cellZ(11.5), Math.PI / 2);
      sprite('siteB2', () => G.siteLetter(256, 'B'), 2, 2, map.cellX(40.5), 2.4, map.OZ + 5 * map.S + 0.03, 0);
      sprite('signAL', () => G.sign(256, '← BOMB A', 'A LONGO'), 1.6, 0.8, map.OX + 7 * map.S + 0.03, 2.6, map.cellZ(25), Math.PI / 2);
      sprite('signCat', () => G.sign(256, '← BOMB A', 'PASSARELA'), 1.6, 0.8, map.cellX(16), 3.2, map.OZ + 18 * map.S - 0.03, Math.PI);
      sprite('signBT', () => G.sign(256, 'BOMB B ↑', 'TÚNEL'), 1.6, 0.8, map.OX + 38 * map.S + 0.03, 2.2, map.cellZ(27), Math.PI / 2);
      sprite('signBS', () => G.sign(256, 'B →', 'APARTAMENTOS'), 1.6, 0.8, map.OX + 28 * map.S - 0.03, 3.4, map.cellZ(18), -Math.PI / 2);
      sprite('signMid', () => G.sign(256, 'MEIO', '← BASE CT'), 1.6, 0.8, map.cellX(24.5), 3.0, map.OZ + 13 * map.S + 0.03, 0);
      // fios entre prédios
      const wirePts = [];
      const wire = (x0, z0, x1, z1, y) => { for (let i = 0; i < 10; i++) { const t0 = i / 10, t1 = (i + 1) / 10; const sag = (t) => -Math.sin(t * Math.PI) * 0.8; wirePts.push(x0 + (x1 - x0) * t0, y + sag(t0), z0 + (z1 - z0) * t0, x0 + (x1 - x0) * t1, y + sag(t1), z0 + (z1 - z0) * t1); } };
      wire(map.OX + 20 * map.S, map.cellZ(20), map.OX + 28 * map.S, map.cellZ(23), 5.2);
      wire(map.OX + 20 * map.S, map.cellZ(26), map.OX + 28 * map.S, map.cellZ(24), 5.6);
      wire(map.OX + 2 * map.S, map.cellZ(30), map.OX + 2 * map.S, map.cellZ(33.9), 5.0);
      wire(map.cellX(5), map.OZ + 30 * map.S, map.cellX(14), map.OZ + 34 * map.S, 5.4);
      const wg = new THREE.BufferGeometry(); wg.setAttribute('position', new THREE.Float32BufferAttribute(wirePts, 3));
      this.scene.add(new THREE.LineSegments(wg, new THREE.LineBasicMaterial({ color: 0x222222 })));
    },

    applyQuality() {
      const s = MP.settings.values;
      const key = s.quality === 'auto' ? detectQuality() : s.quality;
      this.qKey = key; this.q = QUALITY[key];
      const r = this.renderer;
      const dpr = Math.min(root.devicePixelRatio || 1, this.q.dpr) * s.renderScale * (this.autoScale || 1);
      r.setPixelRatio(Math.max(0.35, dpr));
      const shadows = s.shadows && this.q.shadows > 0;
      r.shadowMap.enabled = shadows;
      r.shadowMap.autoUpdate = shadows && this.q.shadows === 2;
      this.sun.castShadow = shadows;
      this.sun.shadow.mapSize.set(this.q.shadows === 2 ? 2048 : 1024, this.q.shadows === 2 ? 2048 : 1024);
      if (this.sun.shadow.map) { this.sun.shadow.map.dispose(); this.sun.shadow.map = null; }
      r.shadowMap.needsUpdate = true;
      for (const m of this.mapMeshes) { const k = m.userData.matKey; if (k && this.materials[k]) m.material = this.mat(k); }
      for (const k of Object.keys(this.materials)) { this.materials[k].lam.needsUpdate = true; this.materials[k].std.needsUpdate = true; }
      this.scene.fog.far = this.q.fogFar;
      for (const l of this.tunnelLights) l.visible = this.qKey === 'high';
      r.toneMapping = this.q.standard ? THREE.ACESFilmicToneMapping : THREE.LinearToneMapping;
      this.sun.intensity = this.q.standard ? 1.6 : 1.05;
      MP.events.emit('render:quality', this.qKey, this.q);
    },
    resize() {
      const w = root.innerWidth, h = root.innerHeight;
      this.renderer.setSize(w, h, false);
      this.camera.aspect = w / h; this.camera.updateProjectionMatrix();
      this.vmCamera.aspect = w / h; this.vmCamera.updateProjectionMatrix();
    },
    onRestore() {
      for (const t of MP.textures.cache.values()) t.needsUpdate = true;
      for (const k of Object.keys(this.materials)) { this.materials[k].lam.needsUpdate = true; this.materials[k].std.needsUpdate = true; }
      this.renderer.shadowMap.needsUpdate = true;
    },
    frame(showViewmodel) {
      if (this.contextLost) return;
      const r = this.renderer;
      r.info.reset();
      r.clear();
      r.render(this.scene, this.camera);
      if (showViewmodel) { r.clearDepth(); r.render(this.vmScene, this.vmCamera); }
    }
  };
  R.GeoBuilder = GeoBuilder;
  R.detectQuality = detectQuality;
})(typeof window !== 'undefined' ? window : globalThis);
