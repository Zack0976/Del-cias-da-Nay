/* Mirage Protocol — armas procedurais em alto detalhe.
 * Cada arma é montada com dezenas de peças: perfis laterais extrudados (receptor, coronha, empunhadura,
 * carregador curvo), peças torneadas (cano, freio de boca, supressor, luneta), trilhos Picatinny com
 * ranhuras, miras, rebites, gatilho e guarda-mato, alavancas, janelas de ejeção, cartuchos visíveis etc.
 * Materiais PBR com mapa de ambiente procedural (reflexos metálicos) e texturas geradas em Canvas.
 * O viewmodel usa a hierarquia completa (carregador animável); cópias no mundo usam malhas mescladas
 * por material (poucas chamadas de desenho). Convenção: cano para -Z, origem perto do punho. */
(function (root) {
  'use strict';
  const MP = root.MP;
  const THREE = root.THREE;
  const PI = Math.PI;

  // ---------------------------------------------------------------- texturas procedurais
  function cv(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
  function rng(seed) { let s = seed; return () => { s = (s * 16807) % 2147483647; return s / 2147483647; }; }
  const TEX = {
    wood(tint) {
      const c = cv(256, 256), x = c.getContext('2d'), r = rng(7 + tint.length);
      x.fillStyle = tint; x.fillRect(0, 0, 256, 256);
      for (let i = 0; i < 90; i++) {
        const y = r() * 256, a = 0.05 + r() * 0.18;
        x.strokeStyle = r() < 0.5 ? `rgba(40,18,6,${a})` : `rgba(255,210,150,${a * 0.6})`; x.lineWidth = 0.6 + r() * 2.2;
        x.beginPath(); x.moveTo(0, y);
        for (let k = 1; k <= 8; k++) x.lineTo(k * 32, y + Math.sin(k * 0.9 + i) * (2 + r() * 5));
        x.stroke();
      }
      for (let i = 0; i < 6; i++) { const cx = r() * 256, cy = r() * 256; const g = x.createRadialGradient(cx, cy, 0, cx, cy, 6 + r() * 10); g.addColorStop(0, 'rgba(40,15,5,0.5)'); g.addColorStop(1, 'rgba(40,15,5,0)'); x.fillStyle = g; x.fillRect(cx - 20, cy - 20, 40, 40); }
      return c;
    },
    stipple(base) {
      const c = cv(128, 128), x = c.getContext('2d'), r = rng(31);
      x.fillStyle = base; x.fillRect(0, 0, 128, 128);
      for (let i = 0; i < 2600; i++) { const v = r(); x.fillStyle = v < 0.5 ? 'rgba(0,0,0,0.13)' : 'rgba(255,255,255,0.06)'; x.fillRect(r() * 128, r() * 128, 1, 1); }
      return c;
    },
    worn(base, seed) {
      const c = cv(256, 256), x = c.getContext('2d'), r = rng(seed || 11);
      x.fillStyle = base; x.fillRect(0, 0, 256, 256);
      for (let i = 0; i < 2200; i++) { x.fillStyle = `rgba(255,255,255,${r() * 0.05})`; x.fillRect(r() * 256, r() * 256, 1 + r() * 2, 1); }
      for (let i = 0; i < 40; i++) { x.strokeStyle = `rgba(200,205,210,${0.08 + r() * 0.15})`; x.lineWidth = 0.5; x.beginPath(); const sx = r() * 256, sy = r() * 256; x.moveTo(sx, sy); x.lineTo(sx + (r() - 0.5) * 30, sy + (r() - 0.5) * 6); x.stroke(); }
      // desgaste nas bordas (claro)
      const g = x.createLinearGradient(0, 0, 0, 256); g.addColorStop(0, 'rgba(255,255,255,0.10)'); g.addColorStop(0.08, 'rgba(255,255,255,0)'); g.addColorStop(0.92, 'rgba(255,255,255,0)'); g.addColorStop(1, 'rgba(255,255,255,0.10)');
      x.fillStyle = g; x.fillRect(0, 0, 256, 256);
      return c;
    },
    engrave(text, sub) {
      const c = cv(256, 64), x = c.getContext('2d');
      x.clearRect(0, 0, 256, 64);
      x.fillStyle = 'rgba(210,215,220,0.55)'; x.font = 'bold 22px monospace'; x.fillText(text, 6, 26);
      if (sub) { x.font = '15px monospace'; x.fillText(sub, 6, 50); }
      return c;
    },
    canvasCloth(base) {
      const c = cv(128, 128), x = c.getContext('2d');
      x.fillStyle = base; x.fillRect(0, 0, 128, 128);
      for (let i = 0; i < 128; i += 3) { x.fillStyle = 'rgba(0,0,0,0.12)'; x.fillRect(i, 0, 1, 128); x.fillRect(0, i, 128, 1); }
      return c;
    },
    lcd(text) {
      const c = cv(128, 32), x = c.getContext('2d');
      x.fillStyle = '#1d3a1a'; x.fillRect(0, 0, 128, 32);
      x.fillStyle = '#8dff7a'; x.font = 'bold 22px monospace'; x.textBaseline = 'middle'; x.fillText(text, 8, 17);
      return c;
    }
  };

  // ---------------------------------------------------------------- materiais
  let envMap = null;
  const matCache = new Map();
  function texture(key, fn) {
    return MP.textures.get('gun_' + key, fn, { aniso: 4 });
  }
  function M(key) {
    if (matCache.has(key)) return matCache.get(key);
    const S = (o) => new THREE.MeshStandardMaterial(Object.assign({ envMap, envMapIntensity: 1.0 }, o));
    let m;
    switch (key) {
      case 'blued': m = S({ color: 0x2b2e33, metalness: 0.85, roughness: 0.38, map: texture('wornBlue', () => TEX.worn('#5d636b', 3)) }); break;
      case 'park': m = S({ color: 0x3b3e40, metalness: 0.55, roughness: 0.6, map: texture('wornPark', () => TEX.worn('#7a7d80', 5)) }); break;
      case 'steel': m = S({ color: 0x9da3aa, metalness: 1.0, roughness: 0.28, map: texture('wornSteel', () => TEX.worn('#d0d4d8', 9)) }); break;
      case 'chrome': m = S({ color: 0xd8dde2, metalness: 1.0, roughness: 0.12 }); break;
      case 'dark': m = S({ color: 0x0c0d0e, metalness: 0.4, roughness: 0.7 }); break;
      case 'poly': m = S({ color: 0x1a1c1e, metalness: 0.05, roughness: 0.72, map: texture('stipBlack', () => TEX.stipple('#4a4d50')) }); break;
      case 'polySmooth': m = S({ color: 0x202326, metalness: 0.1, roughness: 0.55 }); break;
      case 'grip': m = S({ color: 0x1b1d1f, metalness: 0.0, roughness: 0.9, map: texture('stipGrip', () => TEX.stipple('#3d4043')), bumpMap: texture('stipBump', () => TEX.stipple('#808080')), bumpScale: 0.004 }); break;
      case 'tan': m = S({ color: 0xa58b62, metalness: 0.05, roughness: 0.7, map: texture('stipTan', () => TEX.stipple('#d8c09a')) }); break;
      case 'od': m = S({ color: 0x4c5a3b, metalness: 0.05, roughness: 0.7, map: texture('stipOd', () => TEX.stipple('#8a9a74')) }); break;
      case 'wood': m = S({ color: 0xffffff, metalness: 0.0, roughness: 0.45, map: texture('woodAK', () => TEX.wood('#6a3519')) }); break;
      case 'woodLight': m = S({ color: 0xffffff, metalness: 0.0, roughness: 0.5, map: texture('woodLt', () => TEX.wood('#87592f')) }); break;
      case 'brass': m = S({ color: 0xc9a043, metalness: 1.0, roughness: 0.3 }); break;
      case 'copper': m = S({ color: 0xb86b3e, metalness: 1.0, roughness: 0.35 }); break;
      case 'shellRed': m = S({ color: 0x9c1d18, metalness: 0.0, roughness: 0.5 }); break;
      case 'lens': m = S({ color: 0x0b1e33, metalness: 0.9, roughness: 0.05, emissive: 0x06223a, emissiveIntensity: 0.6 }); break;
      case 'redDot': m = new THREE.MeshBasicMaterial({ color: 0xff2a1a }); break;
      case 'glowGreen': m = new THREE.MeshBasicMaterial({ color: 0x5dff6a }); break;
      case 'tritium': m = new THREE.MeshBasicMaterial({ color: 0xb6ff8a }); break;
      case 'rubber': m = S({ color: 0x111213, metalness: 0, roughness: 0.95 }); break;
      case 'cloth': m = S({ color: 0x6a6f4a, metalness: 0, roughness: 1, map: texture('cloth', () => TEX.canvasCloth('#9aa070')) }); break;
      case 'nadeOlive': m = S({ color: 0x46512e, metalness: 0.3, roughness: 0.55 }); break;
      case 'nadeGrey': m = S({ color: 0x8b9298, metalness: 0.6, roughness: 0.4 }); break;
      case 'nadeSmoke': m = S({ color: 0x55635a, metalness: 0.4, roughness: 0.5 }); break;
      case 'nadeRed': m = S({ color: 0x8e2b20, metalness: 0.4, roughness: 0.5 }); break;
      case 'yellow': m = S({ color: 0xd8b830, metalness: 0.1, roughness: 0.6 }); break;
      case 'glass': m = S({ color: 0x5a3c12, metalness: 0.1, roughness: 0.08, transparent: true, opacity: 0.6 }); break;
      case 'liquid': m = S({ color: 0xc27a20, metalness: 0, roughness: 0.2, transparent: true, opacity: 0.75 }); break;
      case 'rag': m = S({ color: 0xd7ccb0, metalness: 0, roughness: 1, map: texture('rag', () => TEX.canvasCloth('#e6dcc0')) }); break;
      case 'clay': m = S({ color: 0x9c8b6a, metalness: 0, roughness: 0.9, map: texture('clay', () => TEX.stipple('#cbb995')) }); break;
      case 'tape': m = S({ color: 0x3a3c40, metalness: 0.1, roughness: 0.6 }); break;
      case 'wireR': m = S({ color: 0xc8211b, roughness: 0.5 }); break;
      case 'wireB': m = S({ color: 0x1f47c8, roughness: 0.5 }); break;
      case 'wireY': m = S({ color: 0xd8b21b, roughness: 0.5 }); break;
      case 'lcd': m = new THREE.MeshBasicMaterial({ map: texture('lcd', () => TEX.lcd('MP-C7 ****')) }); break;
      case 'ledRed': m = new THREE.MeshBasicMaterial({ color: 0xff2020 }); break;
      case 'translucent': m = S({ color: 0x9a9578, metalness: 0, roughness: 0.3, transparent: true, opacity: 0.55 }); break;
      default: m = S({ color: 0x777777 });
    }
    m.name = key;
    matCache.set(key, m);
    return m;
  }
  function engraveMat(text, sub) {
    const key = 'eng:' + text;
    if (matCache.has(key)) return matCache.get(key);
    const t = texture(key, () => TEX.engrave(text, sub));
    const m = new THREE.MeshBasicMaterial({ map: t, transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2 });
    matCache.set(key, m); return m;
  }

  /** Mapa de ambiente procedural (céu do deserto + painéis de luz) para reflexos PBR. */
  function initEnv(renderer) {
    if (envMap) return envMap;
    try {
      const scene = new THREE.Scene();
      const sky = new THREE.Mesh(new THREE.SphereGeometry(10, 32, 16), new THREE.ShaderMaterial({
        side: THREE.BackSide,
        vertexShader: 'varying vec3 v; void main(){ v = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
        fragmentShader: 'varying vec3 v; void main(){ float h = v.y; vec3 c = mix(vec3(0.55,0.45,0.32), vec3(0.95,0.88,0.75), smoothstep(-0.3,0.05,h)); c = mix(c, vec3(0.45,0.62,0.9), smoothstep(0.1,0.8,h)); gl_FragColor = vec4(c,1.0); }'
      }));
      scene.add(sky);
      const panel = (x, y, z, w, h, int) => { const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: new THREE.Color(int, int, int * 0.92), side: THREE.DoubleSide })); m.position.set(x, y, z); m.lookAt(0, 0, 0); scene.add(m); };
      panel(-5, 6, 3, 4, 3, 6); panel(6, 3, -4, 3, 2, 2.5); panel(0, -6, 0, 8, 8, 0.5); panel(2, 2, 7, 3, 4, 2);
      const pm = new THREE.PMREMGenerator(renderer);
      envMap = pm.fromScene(scene, 0.02).texture;
      pm.dispose();
      for (const m of matCache.values()) if (m.isMeshStandardMaterial) { m.envMap = envMap; m.needsUpdate = true; }
    } catch (e) { MP.diag.error('mapa de ambiente', e); }
    return envMap;
  }

  // ---------------------------------------------------------------- primitivas de modelagem
  const geoCache = new Map();
  function cached(key, fn) { if (!geoCache.has(key)) geoCache.set(key, fn()); return geoCache.get(key); }
  /** Perfil lateral (avanço, altura) extrudado na largura (X). */
  function profile(pts, width, bevel, holes) {
    const key = 'p' + JSON.stringify(pts) + width + ',' + bevel + JSON.stringify(holes || null);
    return cached(key, () => {
      const s = new THREE.Shape(); s.moveTo(pts[0][0], pts[0][1]);
      for (let i = 1; i < pts.length; i++) {
        const p = pts[i];
        if (p.length === 4) s.quadraticCurveTo(p[0], p[1], p[2], p[3]); else s.lineTo(p[0], p[1]);
      }
      s.closePath();
      if (holes) for (const h of holes) { const hp = new THREE.Path(); hp.moveTo(h[0][0], h[0][1]); for (let i = 1; i < h.length; i++) { const p = h[i]; if (p.length === 4) hp.quadraticCurveTo(p[0], p[1], p[2], p[3]); else hp.lineTo(p[0], p[1]); } hp.closePath(); s.holes.push(hp); }
      const b = bevel === undefined ? 0.0015 : bevel;
      const g = new THREE.ExtrudeGeometry(s, { depth: Math.max(0.0005, width - b * 2), bevelEnabled: b > 0, bevelThickness: b, bevelSize: b, bevelSegments: 2, curveSegments: 10 });
      g.translate(0, 0, -(width - b * 2) / 2);
      g.rotateY(PI / 2); // avanço positivo → -Z
      g.computeVertexNormals();
      // UVs proporcionais ao tamanho real (texturas em escala correta)
      const uv = g.attributes.uv; for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * 6, uv.getY(i) * 6);
      return g;
    });
  }
  /** Sólido de revolução ao longo de -Z: pts = [[raio, avanço], ...]. */
  function lathe(pts, seg) {
    return cached('l' + JSON.stringify(pts) + seg, () => {
      const g = new THREE.LatheGeometry(pts.map(p => new THREE.Vector2(p[0], p[1])), seg || 18);
      g.rotateX(-PI / 2);
      return g;
    });
  }
  function boxG(w, h, d) { return cached('b' + w + ',' + h + ',' + d, () => new THREE.BoxGeometry(w, h, d)); }
  function cylG(r1, r2, h, seg) { return cached('c' + r1 + ',' + r2 + ',' + h + ',' + seg, () => new THREE.CylinderGeometry(r1, r2, h, seg || 14)); }
  function torusG(r, t, arc, seg) { return cached('t' + r + ',' + t + ',' + arc, () => new THREE.TorusGeometry(r, t, 6, seg || 16, arc)); }
  function sphG(r, ws, hs) { return cached('s' + r + ',' + ws, () => new THREE.SphereGeometry(r, ws || 12, hs || 8)); }

  class Builder {
    constructor() { this.g = new THREE.Group(); }
    add(geo, mat, x, y, z, rx, ry, rz, parent) {
      const m = new THREE.Mesh(geo, typeof mat === 'string' ? M(mat) : mat);
      m.position.set(x || 0, y || 0, z || 0);
      if (rx || ry || rz) m.rotation.set(rx || 0, ry || 0, rz || 0);
      (parent || this.g).add(m); return m;
    }
    box(w, h, d, mat, x, y, z, rx, ry, rz, parent) { return this.add(boxG(w, h, d), mat, x, y, z, rx, ry, rz, parent); }
    /** cilindro ao longo de Z (avanço) centrado em z */
    tube(r, len, mat, x, y, z, seg, parent) { return this.add(cylG(r, r, len, seg), mat, x, y, z, PI / 2, 0, 0, parent); }
    taper(r1, r2, len, mat, x, y, z, seg, parent) { return this.add(cylG(r2, r1, len, seg), mat, x, y, z, PI / 2, 0, 0, parent); }
    /** pino/rebite lateral (eixo X) */
    pin(r, len, mat, x, y, z, parent) { return this.add(cylG(r, r, len, 10), mat, x, y, z, 0, 0, PI / 2, parent); }
    prof(pts, w, mat, x, y, z, bevel, holes, parent) { return this.add(profile(pts, w, bevel, holes), mat, x, y, z, 0, 0, 0, parent); }
    lathe(pts, mat, x, y, z, seg, parent) { return this.add(lathe(pts, seg), mat, x, y, z, 0, 0, 0, parent); }
    /** trilho Picatinny: base + dentes */
    rail(len, x, y, z, mat, w, parent) {
      mat = mat || 'blued'; w = w || 0.021;
      const g = new THREE.Group(); g.position.set(x, y, z); (parent || this.g).add(g);
      this.box(w, 0.006, len, mat, 0, 0, 0, 0, 0, 0, g);
      this.box(w * 0.78, 0.004, len, mat, 0, 0.004, 0, 0, 0, 0, g);
      const n = Math.floor(len / 0.0102);
      for (let i = 0; i < n; i++) this.box(w * 1.02, 0.0045, 0.0052, mat, 0, 0.006, -len / 2 + 0.005 + i * 0.0102, 0, 0, 0, g);
      return g;
    }
    rivets(list, r, mat, w) { for (const [y, z] of list) { this.pin(r, w, mat, 0, y, z); } }
    triggerGroup(y, z, mat, guardMat) {
      // guarda-mato (arco) + gatilho curvo
      this.add(torusG(0.026, 0.0035, PI, 18), guardMat || mat, 0, y - 0.002, z, 0, PI / 2, PI);
      this.box(0.007, 0.004, 0.056, guardMat || mat, 0, y - 0.028, z);
      const t = this.add(torusG(0.014, 0.0028, PI * 0.55, 10), 'steel', 0, y - 0.006, z + 0.004, 0, PI / 2, PI * 1.15);
      return t;
    }
    /** carregador curvo (banana) com nervuras; devolve o grupo animável */
    curvedMag(top, len, width, depth, curve, mat, ribMat, x, y, z, ribs) {
      const grp = new THREE.Group(); grp.position.set(x, y, z); this.g.add(grp);
      const pts = []; const n = 10;
      // borda frontal e traseira seguindo um arco
      const front = [], back = [];
      for (let i = 0; i <= n; i++) {
        const t = i / n, yy = -t * len, off = curve * t * t;
        front.push([depth / 2 + off + t * 0.004, yy]); back.push([-depth / 2 + off, yy]);
      }
      for (const p of front) pts.push(p);
      for (let i = back.length - 1; i >= 0; i--) pts.push(back[i]);
      grp.add(new THREE.Mesh(profile(pts.map(p => [+p[0].toFixed(4), +p[1].toFixed(4)]), width, 0.0018), M(mat)));
      if (ribs) for (let i = 1; i < 5; i++) {
        const t = i / 5.2, yy = -t * len, off = curve * t * t;
        const rib = new THREE.Mesh(boxG(width + 0.003, 0.004, depth * 0.85), M(ribMat || mat));
        rib.position.set(0, yy, -off); rib.rotation.x = -Math.atan(2 * curve * t / len) * 0.9; grp.add(rib);
      }
      // base do carregador
      const tEnd = 1, off = curve;
      const base = new THREE.Mesh(boxG(width + 0.006, 0.008, depth + 0.012), M(ribMat || mat)); base.position.set(0, -len - 0.002, -off - 0.002); base.rotation.x = -Math.atan(2 * curve / len) * 0.9; grp.add(base);
      // cartucho no topo
      const c = new THREE.Mesh(cylG(0.0045, 0.0045, depth * 0.8, 8), M('brass')); c.rotation.x = PI / 2; c.position.set(0, 0.006, 0.004); grp.add(c);
      const tip = new THREE.Mesh(cylG(0.001, 0.0045, 0.012, 8), M('copper')); tip.rotation.x = -PI / 2; tip.position.set(0, 0.006, -depth * 0.4 - 0.004); grp.add(tip);
      grp.name = 'mag';
      return grp;
    }
    finish(muzzle, hold, mag) {
      const mz = new THREE.Object3D(); mz.name = 'muzzle'; mz.position.set(0, muzzle[0], -muzzle[1]); this.g.add(mz);
      if (!mag) { mag = new THREE.Group(); mag.name = 'mag'; this.g.add(mag); }
      this.g.userData = { muzzle: mz, mag, hold, magHome: mag.position.clone() };
      return this.g;
    }
  }

  // ---------------------------------------------------------------- peças compartilhadas
  function flashHider(B, y, z, len, r) {
    B.lathe([[0.0001, 0], [r, 0], [r, len * 0.15], [r * 0.9, len * 0.2], [r * 0.9, len], [r * 0.6, len], [r * 0.6, len * 0.25], [0.0001, len * 0.25]], 'blued', 0, y, -z, 16);
    for (let i = 0; i < 4; i++) { const a = i / 4 * PI * 2 + PI / 4; B.box(0.0025, 0.004, len * 0.6, 'dark', Math.cos(a) * r * 0.92, y + Math.sin(a) * r * 0.92, -z - len * 0.6, 0, 0, a); }
  }
  function muzzleBrake(B, y, z, r, len) {
    B.lathe([[0.0001, 0], [r * 1.1, 0], [r * 1.1, len], [r * 0.95, len * 1.05], [0.0001, len * 1.05]], 'blued', 0, y, -z, 18);
    for (let i = 0; i < 3; i++) { B.box(r * 2.3, 0.004, 0.006, 'dark', 0, y + 0.002, -z - len * (0.3 + i * 0.22)); }
  }
  function ironSightFront(B, y, z, mat) {
    B.prof([[0, 0], [0.02, 0], [0.016, 0.035], [0.004, 0.035]], 0.012, mat || 'blued', 0, y, -z + 0.01);
    B.box(0.0025, 0.012, 0.0025, mat || 'blued', 0, y + 0.041, -z);
    B.add(torusG(0.009, 0.0018, PI, 12), mat || 'blued', 0, y + 0.036, -z, 0, PI / 2, 0);
  }
  function scope(B, y, z0, len, objR, eyeR, bodyR) {
    // corpo torneado: ocular, tubo, torre central, sino da objetiva
    B.lathe([[0.0001, 0], [eyeR, 0], [eyeR, 0.05], [bodyR, 0.075], [bodyR, len * 0.42], [bodyR * 1.25, len * 0.45], [bodyR * 1.25, len * 0.55], [bodyR, len * 0.58], [bodyR, len * 0.72], [objR, len * 0.88], [objR, len], [0.0001, len]], 'blued', 0, y, -z0, 24);
    B.add(cylG(eyeR * 0.82, eyeR * 0.82, 0.002, 20), 'lens', 0, y, -z0 + 0.0005, PI / 2, 0, 0);
    B.add(cylG(objR * 0.86, objR * 0.86, 0.002, 20), 'lens', 0, y, -z0 - len - 0.0005, PI / 2, 0, 0);
    // torres de elevação e deriva
    B.add(cylG(0.011, 0.011, 0.022, 16), 'blued', 0, y + bodyR * 1.25 + 0.009, -z0 - len * 0.5);
    B.add(cylG(0.011, 0.011, 0.022, 16), 'blued', bodyR * 1.25 + 0.009, y, -z0 - len * 0.5, 0, 0, PI / 2);
    for (let i = 0; i < 12; i++) { const a = i / 12 * PI * 2; B.box(0.0015, 0.016, 0.003, 'park', Math.cos(a) * 0.0115, y + bodyR * 1.25 + 0.012, -z0 - len * 0.5 + Math.sin(a) * 0.0115); }
    // anel de ajuste da ocular (ranhurado)
    for (let i = 0; i < 16; i++) { const a = i / 16 * PI * 2; B.box(0.002, 0.002, 0.03, 'rubber', Math.cos(a) * eyeR, y + Math.sin(a) * eyeR, -z0 - 0.022, 0, 0, a); }
  }
  function scopeRings(B, y, zs, r, railY) {
    for (const z of zs) {
      B.add(torusG(r + 0.003, 0.004, PI * 2, 18), 'blued', 0, y, -z, 0, 0, 0);
      B.box(0.018, y - railY - r, 0.012, 'blued', 0, railY + (y - r - railY) / 2, -z);
      B.pin(0.0028, 0.03, 'steel', 0, railY + 0.006, -z);
    }
  }
  function redDot(B, y, z) {
    B.prof([[0, 0], [0.05, 0], [0.05, 0.012], [0.042, 0.04], [0.008, 0.04], [0, 0.03]], 0.03, 'park', 0, y, -z + 0.025);
    B.add(torusG(0.0145, 0.003, PI * 2, 20), 'park', 0, y + 0.026, -z + 0.024);
    B.add(torusG(0.0145, 0.003, PI * 2, 20), 'park', 0, y + 0.026, -z - 0.024);
    B.add(cylG(0.013, 0.013, 0.002, 20), 'lens', 0, y + 0.026, -z - 0.024, PI / 2, 0, 0);
    B.add(sphG(0.0016, 6, 4), 'redDot', 0, y + 0.026, -z + 0.0);
    B.add(cylG(0.006, 0.006, 0.01, 12), 'park', 0.019, y + 0.022, -z, 0, 0, PI / 2);
  }
  function pistolGrip(B, y, z, mat, angle) {
    const g = B.prof([[0, 0], [0.034, 0], [0.03, -0.02], [0.032, -0.05], [0.028, -0.08], [0.03, -0.1], [0.002, -0.104], [-0.006, -0.08], [-0.004, -0.04], [-0.01, -0.01]], 0.03, mat || 'grip', 0, y, -z, 0.003);
    g.rotation.x = -(angle || 0.28);
    return g;
  }
  function stamp(B, text, sub, x, y, z, w, h, side) {
    const m = new THREE.Mesh(cached('pl' + w + h, () => new THREE.PlaneGeometry(w, h)), engraveMat(text, sub));
    m.position.set(x, y, z); m.rotation.y = side > 0 ? PI / 2 : -PI / 2; B.g.add(m);
  }

  // ---------------------------------------------------------------- armas
  const BUILD = {
    // ---------- fuzil de alto impacto (estilo AK)
    rifle3() {
      const B = new Builder();
      // receptor estampado
      B.prof([[-0.11, 0], [0.18, 0], [0.18, 0.052], [-0.11, 0.052]], 0.046, 'blued', 0, 0.02, 0);
      // tampa de poeira arredondada com nervura
      B.prof([[-0.12, 0.05], [0.16, 0.05], [0.16, 0.066], [0.15, 0.074, 0.13, 0.076], [-0.09, 0.076], [-0.12, 0.06]], 0.042, 'blued', 0, 0.02, 0);
      B.box(0.03, 0.003, 0.2, 'park', 0, 0.098, -0.03);
      // janela de ejeção, alavanca de manejo e seletor
      B.box(0.002, 0.016, 0.07, 'dark', 0.0235, 0.06, -0.06);
      B.box(0.008, 0.008, 0.012, 'steel', 0.03, 0.06, -0.1); B.add(sphG(0.006), 'steel', 0.036, 0.06, -0.104);
      B.prof([[-0.06, 0], [0.09, 0], [0.09, 0.008], [-0.04, 0.012]], 0.003, 'steel', 0.0245, 0.05, 0);
      B.rivets([[0.03, 0.12], [0.03, 0.105], [0.045, 0.14], [0.03, -0.08], [0.045, -0.08], [0.012, 0.155], [0.012, -0.095]], 0.0028, 'steel', 0.05);
      stamp(B, 'BRUTUS K7', '7.62×39 · MP-0471', 0.0236, 0.047, -0.02, 0.09, 0.022, 1);
      // trunnion e bloco de mira traseira
      B.box(0.05, 0.03, 0.035, 'blued', 0, 0.05, -0.19);
      B.prof([[0, 0], [0.06, 0], [0.06, 0.012], [0.01, 0.02]], 0.026, 'blued', 0, 0.075, -0.17);
      B.box(0.022, 0.006, 0.04, 'blued', 0, 0.098, -0.2);
      // cano e tubo de gases
      B.tube(0.0105, 0.42, 'blued', 0, 0.058, -0.42);
      B.tube(0.0085, 0.22, 'blued', 0, 0.09, -0.3);
      B.box(0.03, 0.03, 0.03, 'blued', 0, 0.075, -0.45);              // bloco de gás
      B.add(torusG(0.011, 0.003, PI * 2, 12), 'blued', 0, 0.058, -0.47); // anel do bloco
      B.tube(0.0035, 0.32, 'steel', 0, 0.035, -0.41);                  // vareta de limpeza
      // guarda-mãos de madeira (inferior com sulcos + superior)
      B.prof([[0, 0], [0.2, 0], [0.2, 0.012], [0.195, 0.042], [0.01, 0.046], [0, 0.03]], 0.05, 'wood', 0, 0.034, -0.205, 0.004);
      for (let i = 0; i < 3; i++) B.box(0.052, 0.003, 0.15, 'dark', 0, 0.045 + i * 0.008, -0.31);
      B.prof([[0, 0], [0.16, 0], [0.16, 0.01], [0.15, 0.024, 0.13, 0.026], [0.02, 0.026], [0, 0.012]], 0.036, 'wood', 0, 0.082, -0.215, 0.003);
      B.box(0.054, 0.012, 0.012, 'park', 0, 0.06, -0.21); B.box(0.054, 0.012, 0.012, 'park', 0, 0.06, -0.405);
      // mira frontal e freio de boca
      ironSightFront(B, 0.068, 0.6);
      muzzleBrake(B, 0.058, 0.635, 0.013, 0.055);
      // empunhadura, guarda-mato e gatilho
      pistolGrip(B, 0.022, 0.0, 'wood', 0.32);
      B.triggerGroup(0.02, -0.055, 'steel', 'blued');
      // coronha de madeira com soleira
      B.prof([[0, 0], [0.24, -0.06], [0.25, 0.01], [0.24, 0.035], [0.0, 0.045]], 0.04, 'wood', 0, 0.018, 0.115, 0.004).rotation.y = PI;
      B.box(0.044, 0.1, 0.012, 'rubber', 0, 0.004, 0.365);
      B.pin(0.004, 0.046, 'steel', 0, 0.03, 0.2);
      // carregador curvo com nervuras
      const mag = B.curvedMag(0, 0.2, 0.03, 0.055, 0.075, 'park', 'blued', 0, 0.02, -0.09, true);
      return B.finish([0.058, 0.69], { grip: [0, -0.03, 0.03], support: [0, 0.03, -0.32] }, mag);
    },
    // ---------- fuzil equilibrado (estilo M4)
    rifle() {
      const B = new Builder();
      // receptor inferior com poço do carregador
      B.prof([[-0.06, 0], [0.12, 0], [0.13, 0.03], [0.12, 0.05], [-0.07, 0.05], [-0.08, 0.025]], 0.044, 'park', 0, 0.0, 0, 0.003);
      B.prof([[0, 0], [0.07, 0], [0.072, -0.03], [-0.002, -0.03]], 0.04, 'park', 0, 0.002, -0.055, 0.002);
      // receptor superior com trilho e assistência de avanço
      B.prof([[-0.08, 0], [0.13, 0], [0.13, 0.04], [-0.08, 0.04]], 0.04, 'park', 0, 0.05, 0, 0.003);
      B.rail(0.2, 0, 0.091, -0.025);
      B.tube(0.008, 0.03, 'park', 0.022, 0.07, 0.04);
      B.box(0.002, 0.016, 0.05, 'dark', 0.0205, 0.07, -0.04);           // janela de ejeção
      B.box(0.003, 0.018, 0.054, 'park', 0.023, 0.07, -0.04);           // tampa
      B.box(0.03, 0.008, 0.02, 'park', 0, 0.098, 0.085); B.box(0.044, 0.006, 0.006, 'park', 0, 0.098, 0.09); // alavanca T
      B.box(0.003, 0.01, 0.016, 'steel', -0.023, 0.035, 0.02);          // seletor
      B.pin(0.0035, 0.048, 'steel', 0, 0.03, -0.05); B.pin(0.0035, 0.048, 'steel', 0, 0.03, 0.06);
      stamp(B, 'GUARDIÃO M4', '5.56 NATO · MP-1123', 0.0225, 0.03, 0.02, 0.08, 0.02, 1);
      // guarda-mão quad-rail
      B.lathe([[0.0001, 0], [0.026, 0], [0.026, 0.24], [0.0001, 0.24]], 'park', 0, 0.068, -0.13, 8).rotation.z = PI / 8;
      B.rail(0.23, 0, 0.093, -0.25);
      B.rail(0.23, 0.027, 0.068, -0.25).rotation.z = -PI / 2;
      B.rail(0.23, -0.027, 0.068, -0.25).rotation.z = PI / 2;
      for (let i = 0; i < 10; i++) B.box(0.054, 0.004, 0.006, 'dark', 0, 0.04, -0.15 - i * 0.022);
      // cano, bloco de mira A e quebra-chamas
      B.tube(0.0095, 0.2, 'blued', 0, 0.068, -0.46);
      B.prof([[0, 0], [0.03, 0], [0.024, 0.05], [0.006, 0.05]], 0.016, 'blued', 0, 0.06, -0.39);
      B.box(0.0025, 0.012, 0.0025, 'blued', 0, 0.115, -0.405);
      flashHider(B, 0.068, 0.56, 0.06, 0.0115);
      // mira red dot
      redDot(B, 0.098, 0.0);
      // empunhadura, gatilho
      pistolGrip(B, 0.004, 0.02, 'grip', 0.3);
      B.triggerGroup(0.004, -0.035, 'park', 'park');
      // tubo do amortecedor e coronha retrátil
      B.tube(0.015, 0.2, 'park', 0, 0.06, 0.17);
      B.prof([[0, 0], [0.16, 0], [0.17, 0.02], [0.17, 0.09], [0.12, 0.09], [0.01, 0.045]], 0.042, 'poly', 0, 0.0, 0.31, 0.004, [[[0.04, 0.02], [0.1, 0.02], [0.1, 0.035], [0.04, 0.035]]]).rotation.y = PI;
      B.box(0.044, 0.1, 0.014, 'rubber', 0, 0.045, 0.33);
      // carregador STANAG levemente curvo
      const mag = B.curvedMag(0, 0.17, 0.026, 0.062, 0.025, 'park', 'park', 0, -0.005, -0.09, true);
      return B.finish([0.068, 0.62], { grip: [0, -0.04, 0.05], support: [0, 0.03, -0.26] }, mag);
    },
    // ---------- fuzil de alta cadência (bullpup)
    rifle2() {
      const B = new Builder();
      B.prof([[-0.32, 0], [0.22, 0], [0.24, 0.03], [0.24, 0.07], [-0.1, 0.075], [-0.32, 0.06]], 0.055, 'tan', 0, 0.0, 0, 0.004);
      // alça de transporte com abertura
      B.prof([[-0.06, 0], [0.2, 0], [0.2, 0.06], [-0.04, 0.06]], 0.024, 'polySmooth', 0, 0.072, 0, 0.003, [[[-0.03, 0.008], [0.17, 0.008], [0.17, 0.042], [-0.03, 0.042]]]);
      B.rail(0.12, 0, 0.133, -0.08);
      B.prof([[0, 0], [0.16, 0], [0.16, 0.035], [0, 0.03]], 0.06, 'polySmooth', 0, 0.035, -0.18);      // guarda-mão
      for (let i = 0; i < 6; i++) B.box(0.062, 0.003, 0.012, 'dark', 0, 0.045, -0.2 - i * 0.022);
      B.tube(0.01, 0.22, 'blued', 0, 0.055, -0.42);
      flashHider(B, 0.055, 0.5, 0.05, 0.011);
      // bipé dobrado
      B.box(0.006, 0.006, 0.18, 'blued', 0.02, 0.07, -0.26); B.box(0.006, 0.006, 0.18, 'blued', -0.02, 0.07, -0.26);
      B.box(0.003, 0.012, 0.11, 'dark', 0.028, 0.04, 0.12);  // janela de ejeção (atrás)
      B.prof([[-0.12, 0], [0.04, 0], [0.04, 0.02], [-0.1, 0.024]], 0.058, 'rubber', 0, 0.054, 0.15);    // apoio de face
      pistolGrip(B, 0.0, -0.08, 'grip', 0.25);
      B.add(torusG(0.04, 0.004, PI, 18), 'polySmooth', 0, -0.005, -0.14, 0, PI / 2, PI); // guarda-mão do gatilho longo
      B.box(0.006, 0.02, 0.006, 'steel', 0, -0.012, -0.135);
      const mag = B.curvedMag(0, 0.15, 0.026, 0.06, 0.02, 'park', 'park', 0, 0.0, 0.1, true);
      return B.finish([0.055, 0.56], { grip: [0, -0.04, -0.05], support: [0, 0.02, -0.25] }, mag);
    },
    // ---------- pistolas
    pistol() { return BUILD._pistol(false); },
    heavypistol() { return BUILD._pistol(true); },
    _pistol(big) {
      const B = new Builder();
      const L = big ? 0.27 : 0.19, H = big ? 0.042 : 0.032, W = big ? 0.034 : 0.027, mat = big ? 'steel' : 'blued';
      // ferrolho com serrilhas, janela de ejeção, miras com trítio
      B.prof([[-0.03, 0], [L - 0.03, 0], [L - 0.03, H * 0.8], [L - 0.045, H], [-0.03, H]], W, mat, 0, 0.05, 0, 0.002);
      for (let i = 0; i < 9; i++) { B.box(0.002, H * 0.7, 0.003, 'dark', W / 2 + 0.0002, 0.05 + H * 0.45, 0.012 - i * 0.006); B.box(0.002, H * 0.7, 0.003, 'dark', -W / 2 - 0.0002, 0.05 + H * 0.45, 0.012 - i * 0.006); }
      B.box(0.0015, H * 0.5, 0.045, 'dark', W / 2 + 0.0004, 0.05 + H * 0.62, -0.06);
      B.box(0.014, 0.008, 0.008, 'dark', 0, 0.05 + H + 0.004, 0.018); B.box(0.004, 0.004, 0.006, 'tritium', 0, 0.05 + H + 0.006, 0.0225);
      B.box(0.004, 0.009, 0.006, 'dark', 0, 0.05 + H + 0.004, -L + 0.045); B.add(sphG(0.0018, 6, 4), 'tritium', 0, 0.05 + H + 0.006, -L + 0.042);
      B.tube(big ? 0.012 : 0.0075, 0.01, 'steel', 0, 0.05 + H * 0.45, -L + 0.034);
      B.tube(big ? 0.006 : 0.0045, 0.012, 'dark', 0, 0.05 + H * 0.45, -L + 0.031);
      if (big) { B.box(0.02, 0.006, L * 0.7, 'steel', 0, 0.05 + H + 0.003, -L * 0.45); stamp(B, 'FALCÃO .50', 'AE · MP', W / 2 + 0.001, 0.07, -0.12, 0.08, 0.02, 1); }
      else stamp(B, 'LINCE · VIPER', '9mm · MP-0091', W / 2 + 0.001, 0.065, -0.08, 0.07, 0.018, 1);
      // armação com trilho, guarda-mato e alavancas
      B.prof([[-0.02, 0], [L - 0.06, 0], [L - 0.06, 0.02], [-0.02, 0.022]], W * 0.92, 'poly', 0, 0.03, 0, 0.002);
      B.box(W * 0.8, 0.004, 0.04, 'poly', 0, 0.027, -L + 0.09);
      for (let i = 0; i < 3; i++) B.box(W * 0.85, 0.003, 0.004, 'dark', 0, 0.024, -L + 0.08 + i * 0.01);
      B.add(torusG(0.019, 0.004, PI, 14), 'poly', 0, 0.03, -0.035, 0, PI / 2, PI);
      B.box(0.006, 0.0045, 0.038, 'poly', 0, 0.011, -0.035);
      B.add(torusG(0.01, 0.0025, PI * 0.6, 8), 'steel', 0, 0.026, -0.03, 0, PI / 2, PI * 1.15);
      B.box(0.003, 0.006, 0.026, 'dark', W / 2 * 0.95, 0.045, -0.05);     // retém do ferrolho
      B.box(0.012, 0.012, 0.008, mat, 0, 0.065, 0.031);                    // cão
      // empunhadura texturizada e base do carregador
      const gr = pistolGrip(B, 0.035, -0.005, 'grip', 0.22); gr.scale.set(big ? 1.1 : 1, 1, 1);
      const mag = new THREE.Group(); mag.name = 'mag'; B.g.add(mag);
      B.box(W * 0.85, 0.008, 0.038, 'poly', 0, -0.07, 0.008, 0.22, 0, 0, mag);
      B.box(W * 0.7, 0.012, 0.028, 'brass', 0, 0.025, -0.01, 0, 0, 0, mag);
      return B.finish([0.05 + H * 0.45, L - 0.03], { grip: [0, -0.02, 0.02], support: [-0.02, -0.03, 0.03] }, mag);
    },
    // ---------- revólver
    revolver() {
      const B = new Builder();
      B.prof([[-0.05, 0], [0.06, 0], [0.07, 0.045], [-0.03, 0.06], [-0.055, 0.04]], 0.026, 'steel', 0, 0.02, 0, 0.002);
      // tambor com caneluras e câmaras
      B.lathe([[0.0001, 0], [0.023, 0], [0.026, 0.006], [0.026, 0.044], [0.023, 0.05], [0.0001, 0.05]], 'steel', 0, 0.045, -0.005, 24);
      for (let i = 0; i < 6; i++) { const a = i / 6 * PI * 2; B.box(0.004, 0.004, 0.034, 'dark', Math.cos(a) * 0.026, 0.045 + Math.sin(a) * 0.026, -0.03, 0, 0, a); B.tube(0.0055, 0.002, 'brass', Math.cos(a + PI / 6) * 0.015, 0.045 + Math.sin(a + PI / 6) * 0.015, -0.055); }
      // cano com costela ventilada, ejetor e mira rampa
      B.tube(0.0105, 0.16, 'steel', 0, 0.052, -0.14);
      B.box(0.01, 0.01, 0.16, 'steel', 0, 0.064, -0.14);
      for (let i = 0; i < 6; i++) B.box(0.011, 0.004, 0.008, 'dark', 0, 0.069, -0.08 - i * 0.022);
      B.tube(0.006, 0.12, 'steel', 0, 0.034, -0.12);
      B.prof([[0, 0], [0.02, 0], [0.006, 0.012]], 0.004, 'steel', 0, 0.069, -0.215);
      B.box(0.006, 0.014, 0.012, 'steel', 0, 0.083, 0.045); B.box(0.004, 0.006, 0.01, 'dark', 0, 0.086, 0.06); // cão
      B.add(torusG(0.016, 0.0035, PI, 14), 'steel', 0, 0.022, -0.012, 0, PI / 2, PI);
      B.add(torusG(0.009, 0.0025, PI * 0.6, 8), 'chrome', 0, 0.022, -0.008, 0, PI / 2, PI * 1.15);
      const g = pistolGrip(B, 0.03, 0.03, 'woodLight', 0.38); g.scale.set(1.05, 1.05, 1.05);
      B.add(cylG(0.006, 0.006, 0.032, 14), 'brass', 0, -0.01, 0.045, 0, 0, PI / 2);
      stamp(B, 'RHINO R8', '.357 MAG', 0.0135, 0.04, 0.02, 0.06, 0.016, 1);
      return B.finish([0.052, 0.22], { grip: [0, -0.02, 0.04], support: [-0.02, -0.03, 0.05] });
    },
    // ---------- submetralhadoras
    smg() { // compacta
      const B = new Builder();
      B.prof([[-0.05, 0], [0.2, 0], [0.2, 0.07], [-0.05, 0.07]], 0.05, 'park', 0, 0.0, 0, 0.004);
      B.box(0.052, 0.006, 0.18, 'park', 0, 0.072, -0.07);
      B.box(0.016, 0.012, 0.012, 'steel', 0, 0.082, -0.01); B.box(0.006, 0.01, 0.006, 'park', 0, 0.083, -0.14); B.add(torusG(0.007, 0.0015, PI, 10), 'park', 0, 0.08, -0.14, 0, PI / 2, 0);
      B.box(0.002, 0.018, 0.06, 'dark', 0.0255, 0.045, -0.06);
      B.box(0.006, 0.008, 0.016, 'steel', 0, 0.082, 0.04); // manejo superior
      B.tube(0.0085, 0.07, 'blued', 0, 0.045, -0.235);
      for (let i = 0; i < 8; i++) B.add(torusG(0.0088, 0.001, PI * 2, 10), 'blued', 0, 0.045, -0.21 - i * 0.006);
      B.prof([[0, 0], [0.05, 0], [0.045, -0.15], [0.005, -0.15]], 0.04, 'grip', 0, 0.002, -0.03, 0.003).rotation.x = 0.08;
      B.triggerGroup(0.0, -0.1, 'park', 'park');
      // coronha de arame recolhida
      B.box(0.004, 0.004, 0.22, 'steel', 0.022, 0.05, 0.06); B.box(0.004, 0.004, 0.22, 'steel', -0.022, 0.05, 0.06);
      B.box(0.048, 0.06, 0.006, 'steel', 0, 0.03, 0.17);
      const mag = new THREE.Group(); mag.name = 'mag'; mag.position.set(0, -0.15, -0.06); B.g.add(mag);
      B.box(0.03, 0.09, 0.03, 'park', 0, -0.03, 0.0, 0.08, 0, 0, mag); B.box(0.036, 0.01, 0.04, 'poly', 0, -0.08, 0.004, 0.08, 0, 0, mag);
      stamp(B, 'VESPA C9', '.45 ACP', 0.0255, 0.025, -0.03, 0.07, 0.018, 1);
      return B.finish([0.045, 0.28], { grip: [0, -0.03, -0.07], support: [0, 0.0, -0.17] }, mag);
    },
    smg2() { // alta cadência (bullpup com carregador superior translúcido)
      const B = new Builder();
      B.prof([[-0.2, 0], [0.24, 0], [0.26, 0.04], [0.25, 0.085], [-0.2, 0.09], [-0.22, 0.04]], 0.06, 'tan', 0, -0.01, 0, 0.006,
        [[[0.0, 0.0], [0.09, 0.0], [0.1, 0.03], [0.0, 0.035]], [[-0.17, 0.01], [-0.06, 0.01], [-0.06, 0.04], [-0.17, 0.04]]]);
      // carregador translúcido com cartuchos visíveis
      const mag = new THREE.Group(); mag.name = 'mag'; mag.position.set(0, 0.095, -0.02); B.g.add(mag);
      B.box(0.05, 0.018, 0.34, 'translucent', 0, 0, 0, 0, 0, 0, mag);
      for (let i = 0; i < 16; i++) { B.box(0.0055, 0.0055, 0.02, 'brass', -0.015 + (i % 2) * 0.03, 0, 0.14 - i * 0.019, 0, PI / 2, 0, mag); }
      B.rail(0.1, 0, 0.115, -0.05, 'blued');
      redDot(B, 0.122, 0.04);
      B.tube(0.0095, 0.06, 'blued', 0, 0.035, -0.29); flashHider(B, 0.035, 0.3, 0.04, 0.0105);
      B.add(torusG(0.04, 0.004, PI, 16), 'poly', 0, -0.012, -0.05, 0, PI / 2, PI);
      B.box(0.006, 0.02, 0.006, 'steel', 0, -0.018, -0.045);
      B.box(0.003, 0.03, 0.05, 'dark', 0.031, 0.03, 0.12);
      stamp(B, 'CICLONE 50', '5.7 · MP', 0.031, 0.06, -0.12, 0.08, 0.02, 1);
      return B.finish([0.035, 0.34], { grip: [0, -0.02, 0.0], support: [0, -0.01, -0.13] }, mag);
    },
    smg3() { // precisa com supressor integral
      const B = new Builder();
      B.tube(0.025, 0.24, 'park', 0, 0.06, -0.02);                         // receptor tubular
      B.prof([[-0.08, 0], [0.12, 0], [0.12, 0.03], [-0.08, 0.03]], 0.046, 'park', 0, 0.02, 0, 0.003);
      B.box(0.002, 0.014, 0.05, 'dark', 0.0255, 0.06, -0.02);
      B.box(0.006, 0.01, 0.06, 'park', -0.024, 0.074, -0.15); B.add(sphG(0.006), 'park', -0.03, 0.074, -0.18); // manejo
      B.rail(0.1, 0, 0.088, 0.0);
      // tambor da mira traseira e túnel frontal
      B.add(cylG(0.012, 0.012, 0.012, 14), 'park', 0, 0.098, 0.07, 0, 0, PI / 2);
      B.add(torusG(0.011, 0.003, PI, 12), 'park', 0, 0.09, -0.12, 0, PI / 2, 0); B.box(0.003, 0.014, 0.003, 'park', 0, 0.09, -0.12);
      // supressor com anéis
      B.lathe([[0.0001, 0], [0.024, 0], [0.026, 0.01], [0.026, 0.2], [0.022, 0.21], [0.0001, 0.21]], 'blued', 0, 0.06, -0.13, 22);
      for (let i = 0; i < 9; i++) B.add(torusG(0.0262, 0.0012, PI * 2, 22), 'park', 0, 0.06, -0.15 - i * 0.02);
      // guarda-mão
      B.prof([[0, 0], [0.13, 0], [0.13, 0.04], [0.0, 0.045]], 0.054, 'poly', 0, 0.025, -0.13, 0.005);
      for (let i = 0; i < 4; i++) B.box(0.056, 0.003, 0.08, 'dark', 0, 0.035 + i * 0.008, -0.19);
      pistolGrip(B, 0.02, 0.06, 'grip', 0.25);
      B.triggerGroup(0.02, 0.02, 'park', 'poly');
      // coronha retrátil
      B.box(0.006, 0.006, 0.16, 'steel', 0.02, 0.05, 0.18); B.box(0.006, 0.006, 0.16, 'steel', -0.02, 0.05, 0.18);
      B.prof([[0, 0], [0.012, 0], [0.012, 0.09], [0, 0.09]], 0.05, 'rubber', 0, 0.0, 0.27);
      const mag = B.curvedMag(0, 0.15, 0.025, 0.04, 0.05, 'park', 'park', 0, 0.02, -0.06, true);
      stamp(B, 'SENTINELA SD', '9mm · SUPRIMIDA', 0.0255, 0.035, 0.02, 0.08, 0.018, 1);
      return B.finish([0.06, 0.35], { grip: [0, -0.02, 0.09], support: [0, 0.02, -0.2] }, mag);
    },
    // ---------- precisão
    dmr() { return BUILD._sniper(false); },
    awp() { return BUILD._sniper(true); },
    _sniper(awp) {
      const B = new Builder();
      const body = awp ? 'od' : 'poly';
      // receptor e trilho
      B.prof([[-0.1, 0], [0.18, 0], [0.18, 0.05], [-0.1, 0.05]], 0.044, 'blued', 0, 0.035, 0, 0.003);
      B.rail(0.3, 0, 0.088, -0.05);
      B.box(0.002, 0.018, 0.07, 'dark', 0.0225, 0.065, -0.02);
      if (awp) { // ferrolho com alavanca e pomo
        const bolt = B.box(0.006, 0.006, 0.05, 'steel', 0.03, 0.07, 0.05, 0, 0.6, 0); bolt.name = 'bolt';
        B.add(sphG(0.011, 12, 8), 'steel', 0.045, 0.062, 0.07);
        B.tube(0.019, 0.08, 'blued', 0, 0.06, 0.03);
      } else { B.box(0.006, 0.01, 0.02, 'steel', 0.026, 0.06, 0.02); stamp(B, 'ESCORPIÃO DMR', '7.62×51 · MP', 0.0225, 0.05, -0.08, 0.08, 0.018, 1); }
      // coronha (thumbhole na AWP) e guarda-mão
      if (awp) {
        B.prof([[-0.16, 0], [0.35, -0.03], [0.4, 0.05], [0.4, 0.12], [0.33, 0.13], [0.12, 0.09], [-0.16, 0.06]], 0.05, body, 0, -0.03, -0.0, 0.006,
          [[[0.07, 0.0], [0.15, -0.005], [0.2, 0.03], [0.16, 0.06], [0.08, 0.05]]]).rotation.y = PI;
        B.prof([[0, 0], [0.3, 0], [0.32, 0.06], [0.0, 0.07]], 0.052, body, 0, -0.005, -0.16, 0.006);
        B.box(0.06, 0.13, 0.016, 'rubber', 0, 0.03, 0.405);
        stamp(B, 'MAMBA .338', 'LAPUA · MP-0007', 0.0265, 0.02, -0.25, 0.1, 0.022, 1);
      } else {
        B.tube(0.016, 0.18, 'blued', 0, 0.06, 0.18);
        B.prof([[0, 0], [0.12, 0], [0.13, 0.03], [0.13, 0.1], [0.08, 0.1], [0.0, 0.05]], 0.046, 'poly', 0, 0.0, 0.32, 0.005).rotation.y = PI;
        B.box(0.03, 0.012, 0.08, 'poly', 0, 0.092, 0.25);
        B.lathe([[0.0001, 0], [0.028, 0], [0.028, 0.3], [0.0001, 0.3]], 'poly', 0, 0.06, -0.14, 8).rotation.z = PI / 8;
        for (let i = 0; i < 8; i++) B.box(0.058, 0.01, 0.022, 'dark', 0, 0.06, -0.17 - i * 0.032);
        pistolGrip(B, 0.035, 0.05, 'grip', 0.3);
      }
      // cano canelado e freio de boca
      const bl = awp ? 0.48 : 0.4;
      B.tube(awp ? 0.013 : 0.011, bl, 'blued', 0, 0.06, -0.14 - bl / 2);
      for (let i = 0; i < 6; i++) { const a = i / 6 * PI * 2; B.box(0.002, 0.002, bl * 0.6, 'dark', Math.cos(a) * 0.0125, 0.06 + Math.sin(a) * 0.0125, -0.2 - bl * 0.3, 0, 0, a); }
      muzzleBrake(B, 0.06, 0.14 + bl, awp ? 0.016 : 0.013, 0.06);
      // luneta com anéis
      scope(B, 0.128, -0.11, awp ? 0.34 : 0.3, awp ? 0.03 : 0.025, 0.021, 0.0155);
      scopeRings(B, 0.128, [-0.01, 0.13], 0.0155, 0.094);
      B.triggerGroup(0.035, -0.03, 'steel', 'blued');
      // carregador de caixa e bipé dobrado
      const mag = new THREE.Group(); mag.name = 'mag'; mag.position.set(0, 0.035, -0.06); B.g.add(mag);
      B.box(0.03, awp ? 0.05 : 0.09, 0.075, 'park', 0, -0.03, 0, 0, 0, 0, mag); B.box(0.034, 0.008, 0.08, 'poly', 0, awp ? -0.058 : -0.078, 0, 0, 0, 0, mag);
      if (awp) { B.box(0.006, 0.006, 0.17, 'blued', 0.015, -0.02, -0.33); B.box(0.006, 0.006, 0.17, 'blued', -0.015, -0.02, -0.33); }
      return B.finish([0.06, 0.2 + bl + (awp ? 0.06 : 0.06)], { grip: [0, -0.03, 0.08], support: [0, 0.0, -0.28] }, mag);
    },
    // ---------- escopeta
    shotgun() {
      const B = new Builder();
      B.prof([[-0.08, 0], [0.16, 0], [0.16, 0.06], [-0.06, 0.065], [-0.08, 0.045]], 0.046, 'blued', 0, 0.02, 0, 0.003);
      B.box(0.002, 0.03, 0.06, 'dark', 0.0235, 0.05, -0.05);               // janela de ejeção
      B.box(0.03, 0.002, 0.05, 'dark', 0, 0.019, -0.06);                    // porta de carregamento
      // cartucheira lateral
      for (let i = 0; i < 4; i++) { B.tube(0.009, 0.05, 'shellRed', -0.032, 0.03 + i * 0.0, -0.02 - i * 0.022 + 0.04); B.tube(0.0092, 0.012, 'brass', -0.032, 0.03, 0.026 - i * 0.022 + 0.04); }
      B.box(0.006, 0.03, 0.1, 'poly', -0.025, 0.04, -0.01);
      // canos com costela ventilada e massa de mira
      B.tube(0.0125, 0.5, 'blued', 0, 0.072, -0.41);
      B.box(0.008, 0.004, 0.48, 'blued', 0, 0.087, -0.41); for (let i = 0; i < 16; i++) B.box(0.006, 0.004, 0.006, 'dark', 0, 0.084, -0.19 - i * 0.03);
      B.add(sphG(0.0028, 8, 6), 'chrome', 0, 0.093, -0.645);
      B.tube(0.0115, 0.4, 'blued', 0, 0.044, -0.36);
      B.box(0.016, 0.03, 0.02, 'blued', 0, 0.058, -0.56);
      // telha com sulcos
      const pump = B.prof([[0, 0], [0.17, 0], [0.165, 0.035], [0.005, 0.035]], 0.052, 'woodLight', 0, 0.03, -0.27, 0.004); pump.name = 'pump';
      for (let i = 0; i < 7; i++) B.box(0.054, 0.004, 0.006, 'dark', 0, 0.04 + (i % 2) * 0.012, -0.3 - i * 0.02);
      // coronha de madeira e soleira
      B.prof([[0, 0], [0.26, -0.07], [0.27, 0.01], [0.26, 0.045], [0.0, 0.06]], 0.04, 'woodLight', 0, 0.022, 0.145, 0.005).rotation.y = PI;
      B.box(0.044, 0.12, 0.014, 'rubber', 0, 0.01, 0.415);
      pistolGrip(B, 0.024, 0.11, 'woodLight', 0.5).visible = false;
      B.triggerGroup(0.02, -0.0, 'steel', 'blued');
      stamp(B, 'TROVÃO 12', 'CAL 12 · 3"', 0.0235, 0.04, 0.08, 0.07, 0.018, 1);
      return B.finish([0.072, 0.67], { grip: [0, -0.02, 0.08], support: [0, 0.01, -0.36] });
    },
    // ---------- metralhadora leve
    lmg() {
      const B = new Builder();
      B.prof([[-0.12, 0], [0.2, 0], [0.2, 0.075], [-0.12, 0.08]], 0.064, 'park', 0, 0.02, 0, 0.004);
      B.prof([[-0.06, 0], [0.14, 0], [0.14, 0.012], [0.1, 0.03], [-0.04, 0.03], [-0.06, 0.015]], 0.06, 'park', 0, 0.098, -0.02, 0.003); // tampa de alimentação
      B.rail(0.14, 0, 0.13, -0.02);
      B.box(0.003, 0.03, 0.08, 'dark', 0.033, 0.055, -0.05);
      // alça de transporte
      B.box(0.01, 0.04, 0.012, 'blued', 0, 0.16, -0.22); B.box(0.01, 0.012, 0.09, 'blued', 0, 0.18, -0.26); B.box(0.01, 0.04, 0.012, 'blued', 0, 0.16, -0.3);
      // cano com protetor térmico perfurado
      B.tube(0.013, 0.45, 'blued', 0, 0.065, -0.42);
      B.lathe([[0.0001, 0], [0.022, 0], [0.022, 0.2], [0.0001, 0.2]], 'park', 0, 0.065, -0.2, 10);
      for (let i = 0; i < 6; i++) for (let k = -1; k <= 1; k += 2) B.add(cylG(0.004, 0.004, 0.003, 8), 'dark', k * 0.022, 0.065, -0.22 - i * 0.03, 0, 0, PI / 2);
      flashHider(B, 0.065, 0.64, 0.06, 0.014);
      ironSightFront(B, 0.077, 0.6);
      // bipé
      for (const s of [-1, 1]) { const l = B.box(0.006, 0.2, 0.006, 'blued', s * 0.03, -0.03, -0.55, 0.25, 0, s * 0.25); B.add(cylG(0.006, 0.004, 0.02, 8), 'rubber', s * 0.055, -0.125, -0.53); }
      // caixa de munição de lona com cinta de cartuchos
      const mag = new THREE.Group(); mag.name = 'mag'; mag.position.set(-0.04, 0.0, -0.06); B.g.add(mag);
      B.box(0.09, 0.11, 0.12, 'cloth', -0.02, -0.04, 0, 0, 0, 0, mag);
      B.box(0.094, 0.012, 0.124, 'od', -0.02, 0.018, 0, 0, 0, 0, mag);
      for (let i = 0; i < 6; i++) { B.tube(0.004, 0.045, 'brass', 0.03 + i * 0.008, 0.035 + i * 0.006, 0, 8, mag).rotation.set(0, PI / 2, 0); B.box(0.007, 0.002, 0.012, 'dark', 0.03 + i * 0.008, 0.03 + i * 0.006, 0.0, 0, 0, 0, mag); }
      pistolGrip(B, 0.022, 0.04, 'grip', 0.3);
      B.triggerGroup(0.02, -0.01, 'park', 'park');
      B.prof([[0, 0], [0.2, 0], [0.22, 0.03], [0.22, 0.11], [0.0, 0.08]], 0.05, 'poly', 0, 0.0, 0.32, 0.005).rotation.y = PI;
      stamp(B, 'MARTELO M249', '5.56 · CINTA', 0.033, 0.035, 0.05, 0.09, 0.02, 1);
      return B.finish([0.065, 0.7], { grip: [0, -0.03, 0.05], support: [0, -0.02, -0.3] }, mag);
    },
    // ---------- faca
    knife() {
      const B = new Builder();
      // lâmina drop point com fio, dorso e canal
      B.prof([[0, 0], [0.165, 0.002], [0.19, 0.016], [0.17, 0.024], [0.12, 0.03], [0.0, 0.03]], 0.0045, 'steel', 0, -0.012, -0.02, 0.0012);
      B.prof([[0.005, 0], [0.165, 0.002], [0.188, 0.015], [0.005, 0.009]], 0.0052, 'chrome', 0, -0.012, -0.02, 0.0004);
      B.box(0.0056, 0.004, 0.11, 'dark', 0, 0.008, -0.08);
      // serrilha do dorso
      for (let i = 0; i < 8; i++) B.box(0.0048, 0.004, 0.003, 'steel', 0, 0.019, -0.03 - i * 0.006, PI / 4);
      // guarda, cabo com anéis e pomo
      B.box(0.044, 0.012, 0.012, 'blued', 0, 0.002, -0.018);
      B.lathe([[0.0001, 0], [0.014, 0], [0.016, 0.03], [0.014, 0.06], [0.016, 0.09], [0.013, 0.11], [0.0001, 0.11]], 'rubber', 0, 0.002, 0.098, 12).rotation.y = PI;
      for (let i = 0; i < 6; i++) B.add(torusG(0.0155, 0.0015, PI * 2, 12), 'poly', 0, 0.002, 0.0 + i * 0.016);
      B.lathe([[0.0001, 0], [0.015, 0], [0.012, 0.015], [0.0001, 0.02]], 'blued', 0, 0.002, -0.112, 12).rotation.y = PI;
      B.pin(0.004, 0.034, 'steel', 0, 0.002, 0.08);
      return B.finish([0.0, 0.2], { grip: [0, 0, 0.05], support: null });
    },
    // ---------- granadas
    grenade() {
      const B = new Builder();
      B.lathe([[0.0001, -0.037], [0.022, -0.033], [0.034, -0.015], [0.036, 0.0], [0.034, 0.015], [0.024, 0.03], [0.012, 0.036], [0.0001, 0.036]], 'nadeOlive', 0, 0, 0, 20).rotation.x = -PI / 2 + PI / 2;
      for (let i = 0; i < 4; i++) B.add(torusG(0.035 - Math.abs(i - 1.5) * 0.004, 0.0012, PI * 2, 20), 'dark', 0, -0.018 + i * 0.012, 0, PI / 2, 0, 0);
      B.add(cylG(0.011, 0.012, 0.018, 12), 'steel', 0, 0.044, 0);
      B.prof([[0, 0], [0.008, 0], [0.008, -0.06], [0.004, -0.065], [0, -0.06]], 0.016, 'steel', 0.0, 0.05, -0.012).rotation.y = 0;
      B.add(torusG(0.011, 0.0018, PI * 2, 14), 'steel', 0.02, 0.052, 0.0, 0, PI / 2, 0);
      B.box(0.006, 0.003, 0.012, 'yellow', 0.0, 0.03, 0.033);
      return B.finish([0, 0], { grip: [0, -0.03, 0.02], support: null });
    },
    flash() { return BUILD._can('nadeGrey', 'yellow', true); },
    smoke() { return BUILD._can('nadeSmoke', 'yellow', false); },
    incend() { return BUILD._can('nadeRed', 'yellow', false); },
    _can(body, band, holes) {
      const B = new Builder();
      B.lathe([[0.0001, -0.055], [0.027, -0.055], [0.029, -0.05], [0.029, 0.045], [0.026, 0.05], [0.0001, 0.05]], body, 0, 0, 0, 22).rotation.x = 0;
      B.g.children[0].rotation.x = 0; B.g.children[0].geometry = cylG(0.029, 0.029, 0.105, 22);
      B.add(torusG(0.0292, 0.004, PI * 2, 22), band, 0, 0.01, 0, PI / 2, 0, 0);
      if (holes) for (let r = 0; r < 3; r++) for (let i = 0; i < 8; i++) { const a = i / 8 * PI * 2 + r * 0.4; B.add(cylG(0.0035, 0.0035, 0.002, 8), 'dark', Math.cos(a) * 0.029, -0.03 + r * 0.018, Math.sin(a) * 0.029, 0, -a, PI / 2); }
      else for (let i = 0; i < 6; i++) { const a = i / 6 * PI * 2; B.add(cylG(0.003, 0.003, 0.004, 8), 'dark', Math.cos(a) * 0.016, 0.0525, Math.sin(a) * 0.016); }
      B.add(cylG(0.012, 0.014, 0.014, 12), 'steel', 0, 0.06, 0);
      B.prof([[0, 0], [0.008, 0], [0.008, -0.085], [0.004, -0.09], [0, -0.085]], 0.016, 'steel', 0.0, 0.066, -0.012);
      B.add(torusG(0.011, 0.0018, PI * 2, 14), 'steel', 0.02, 0.066, 0.0, 0, PI / 2, 0);
      return B.finish([0, 0], { grip: [0, -0.03, 0.02], support: null });
    },
    molotov() {
      const B = new Builder();
      B.lathe([[0.0001, -0.07], [0.03, -0.07], [0.032, -0.066], [0.032, 0.02], [0.02, 0.045], [0.011, 0.05], [0.011, 0.085], [0.013, 0.09], [0.0001, 0.09]], 'glass', 0, 0, 0, 20).rotation.x = -PI / 2;
      B.g.children[0].rotation.x = PI / 2 - PI / 2;
      B.g.children[0].geometry = (function () { const g = new THREE.LatheGeometry([[0.0001, -0.07], [0.03, -0.07], [0.032, -0.066], [0.032, 0.02], [0.02, 0.045], [0.011, 0.05], [0.011, 0.085], [0.013, 0.09], [0.0001, 0.09]].map(p => new THREE.Vector2(p[0], p[1])), 20); return g; })();
      B.add(cylG(0.029, 0.029, 0.07, 18), 'liquid', 0, -0.035, 0);
      // pano enrolado no gargalo
      B.add(cylG(0.014, 0.013, 0.03, 10), 'rag', 0, 0.085, 0);
      B.box(0.018, 0.05, 0.004, 'rag', 0.006, 0.105, 0.004, 0.2, 0, 0.3);
      B.box(0.03, 0.03, 0.002, 'rag', -0.02, 0.04, 0.032, 0, 0, 0.4);
      return B.finish([0, 0.11], { grip: [0, -0.03, 0.02], support: null });
    },
    // ---------- explosivo C-7
    bomb() {
      const B = new Builder();
      // blocos de explosivo plástico envoltos em fita
      for (let i = 0; i < 3; i++) { B.box(0.06, 0.05, 0.14, 'clay', -0.065 + i * 0.065, 0.0, 0); B.box(0.062, 0.052, 0.02, 'tape', -0.065 + i * 0.065, 0.0, 0.04); B.box(0.062, 0.052, 0.02, 'tape', -0.065 + i * 0.065, 0.0, -0.045); }
      // painel com teclado, visor e LED
      B.box(0.12, 0.012, 0.09, 'poly', 0, 0.031, 0.0);
      B.box(0.09, 0.004, 0.024, 'lcd', 0, 0.039, -0.025);
      for (let r = 0; r < 4; r++) for (let c = 0; c < 3; c++) B.box(0.016, 0.006, 0.01, 'polySmooth', -0.02 + c * 0.02, 0.04, 0.0 + r * 0.013);
      const led = B.box(0.008, 0.008, 0.008, 'ledRed', 0.045, 0.041, -0.028); led.name = 'led';
      // fios e antena
      for (const [m, z] of [['wireR', 0.03], ['wireB', 0.02], ['wireY', 0.01]]) { B.add(torusG(0.035, 0.0025, PI, 10), m, 0.07, 0.02, z, 0, PI / 2, 0); }
      B.add(cylG(0.002, 0.002, 0.08, 6), 'steel', 0.05, 0.08, 0.04);
      B.add(sphG(0.004, 6, 4), 'rubber', 0.05, 0.12, 0.04);
      return B.finish([0, 0], { grip: [0, -0.04, 0.02], support: [0, -0.04, 0.02] });
    }
  };

  // ---------------------------------------------------------------- versões mescladas (mundo)
  const mergedCache = new Map();
  /** Mescla malhas (com transformações relativas a `rootObj`) em uma malha por material. */
  function mergeMeshes(meshes, rootObj) {
    rootObj.updateMatrixWorld(true);
    const inv = new THREE.Matrix4().copy(rootObj.matrixWorld).invert();
    const buckets = new Map();
    for (const o of meshes) {
      let g = o.geometry.index ? o.geometry.toNonIndexed() : o.geometry.clone();
      g.applyMatrix4(new THREE.Matrix4().multiplyMatrices(inv, o.matrixWorld));
      if (!g.attributes.uv) g.setAttribute('uv', new THREE.Float32BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2));
      const k = o.material.uuid;
      if (!buckets.has(k)) buckets.set(k, { mat: o.material, geos: [] });
      buckets.get(k).geos.push(g);
    }
    const parts = [];
    for (const { mat, geos } of buckets.values()) {
      let n = 0; for (const g of geos) n += g.attributes.position.count;
      const pos = new Float32Array(n * 3), nor = new Float32Array(n * 3), uv = new Float32Array(n * 2);
      let o = 0;
      for (const g of geos) {
        pos.set(g.attributes.position.array, o * 3);
        if (g.attributes.normal) nor.set(g.attributes.normal.array, o * 3);
        uv.set(g.attributes.uv.array.subarray(0, g.attributes.position.count * 2), o * 2);
        o += g.attributes.position.count; g.dispose();
      }
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      geo.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
      geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
      geo.computeBoundingSphere();
      parts.push({ geo, mat });
    }
    return parts;
  }
  function mergeTemplate(key) {
    if (mergedCache.has(key)) return mergedCache.get(key);
    const src = build(key);
    const meshes = []; src.traverse(o => { if (o.isMesh && o.visible) meshes.push(o); });
    const t = { parts: mergeMeshes(meshes, src), muzzle: src.userData.muzzle.position.clone(), hold: src.userData.hold };
    mergedCache.set(key, t);
    return t;
  }
  const vmCache = new Map();
  /** Viewmodel: peças estáticas mescladas por material; carregador, LED, ferrolho e telha seguem animáveis. */
  function viewmodelBuild(key) {
    const src = build(key);
    const keep = new Set(['mag', 'led', 'bolt', 'pump']);
    const isKept = (o) => { for (let p = o; p && p !== src; p = p.parent) if (keep.has(p.name)) return true; return false; };
    const statics = []; src.traverse(o => { if (o.isMesh && o.visible && !isKept(o)) statics.push(o); });
    let parts = vmCache.get(key);
    if (!parts) { parts = mergeMeshes(statics, src); vmCache.set(key, parts); }
    for (const o of statics) o.parent.remove(o);
    const merged = new THREE.Group(); merged.name = 'static';
    for (const p of parts) merged.add(new THREE.Mesh(p.geo, p.mat));
    src.add(merged);
    return src;
  }

  function build(key) {
    const fn = BUILD[key] || BUILD.rifle;
    const g = fn();
    g.name = 'gun:' + key;
    return g;
  }

  MP.guns = {
    initEnv, M, BUILD,
    /** Hierarquia para o viewmodel/bomba: peças estáticas mescladas, partes móveis preservadas. */
    detailed(key) { return viewmodelBuild(key); },
    /** Hierarquia completa sem mesclagem (inspeção/depuração). */
    raw(key) { return build(key); },
    /** Cópia leve para o mundo: malhas mescladas por material, compartilhando geometria. */
    world(key) {
      const t = mergeTemplate(key);
      const g = new THREE.Group();
      for (const p of t.parts) { const m = new THREE.Mesh(p.geo, p.mat); m.castShadow = true; g.add(m); }
      const mz = new THREE.Object3D(); mz.name = 'muzzle'; mz.position.copy(t.muzzle); g.add(mz);
      const mag = new THREE.Group(); mag.name = 'mag'; g.add(mag);
      g.userData = { muzzle: mz, mag, hold: t.hold, magHome: mag.position.clone() };
      return g;
    },
    stats(key) { let n = 0, tris = 0; build(key).traverse(o => { if (o.isMesh) { n++; const g = o.geometry; tris += (g.index ? g.index.count : g.attributes.position.count) / 3; } }); return { meshes: n, tris: Math.round(tris) }; }
  };
})(typeof window !== 'undefined' ? window : globalThis);
