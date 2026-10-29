/* Mirage Protocol — núcleo: namespace, matemática, eventos, configurações e persistência.
 * Este arquivo não depende de THREE nem do DOM, para que a simulação rode também em Node (testes). */
(function (root) {
  'use strict';
  const MP = root.MP = root.MP || {};

  // ---------------------------------------------------------------- matemática
  class V3 {
    constructor(x = 0, y = 0, z = 0) { this.x = x; this.y = y; this.z = z; }
    set(x, y, z) { this.x = x; this.y = y; this.z = z; return this; }
    copy(v) { this.x = v.x; this.y = v.y; this.z = v.z; return this; }
    clone() { return new V3(this.x, this.y, this.z); }
    add(v) { this.x += v.x; this.y += v.y; this.z += v.z; return this; }
    sub(v) { this.x -= v.x; this.y -= v.y; this.z -= v.z; return this; }
    scale(s) { this.x *= s; this.y *= s; this.z *= s; return this; }
    addScaled(v, s) { this.x += v.x * s; this.y += v.y * s; this.z += v.z * s; return this; }
    dot(v) { return this.x * v.x + this.y * v.y + this.z * v.z; }
    len() { return Math.sqrt(this.x * this.x + this.y * this.y + this.z * this.z); }
    lenXZ() { return Math.sqrt(this.x * this.x + this.z * this.z); }
    normalize() { const l = this.len(); if (l > 1e-9) this.scale(1 / l); return this; }
    dist(v) { const dx = this.x - v.x, dy = this.y - v.y, dz = this.z - v.z; return Math.sqrt(dx * dx + dy * dy + dz * dz); }
    distXZ(v) { const dx = this.x - v.x, dz = this.z - v.z; return Math.sqrt(dx * dx + dz * dz); }
    subVectors(a, b) { this.x = a.x - b.x; this.y = a.y - b.y; this.z = a.z - b.z; return this; }
  }
  MP.V3 = V3;

  const M = MP.math = {
    clamp: (v, a, b) => (v < a ? a : v > b ? b : v),
    lerp: (a, b, t) => a + (b - a) * t,
    rand: (a, b) => a + Math.random() * (b - a),
    randInt: (a, b) => Math.floor(a + Math.random() * (b - a + 1)),
    pick: (arr) => arr[Math.floor(Math.random() * arr.length)],
    chance: (p) => Math.random() < p,
    wrapAngle(a) { while (a > Math.PI) a -= Math.PI * 2; while (a < -Math.PI) a += Math.PI * 2; return a; },
    /** Direção (vetor unitário) a partir de yaw/pitch. yaw=0 olha para -Z. */
    dirFromAngles(yaw, pitch, out) {
      const cp = Math.cos(pitch);
      return (out || new V3()).set(-Math.sin(yaw) * cp, Math.sin(pitch), -Math.cos(yaw) * cp);
    },
    yawTo(from, to) { return Math.atan2(-(to.x - from.x), -(to.z - from.z)); },
    pitchTo(from, to) { const dx = to.x - from.x, dz = to.z - from.z; return Math.atan2(to.y - from.y, Math.sqrt(dx * dx + dz * dz)); },
    shuffle(arr) { for (let i = arr.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); const t = arr[i]; arr[i] = arr[j]; arr[j] = t; } return arr; },
    /** Distância de um ponto P a um segmento AB (3D). */
    distPointSegment(p, a, b) {
      const abx = b.x - a.x, aby = b.y - a.y, abz = b.z - a.z;
      const l2 = abx * abx + aby * aby + abz * abz;
      let t = l2 > 0 ? ((p.x - a.x) * abx + (p.y - a.y) * aby + (p.z - a.z) * abz) / l2 : 0;
      t = t < 0 ? 0 : t > 1 ? 1 : t;
      const dx = a.x + abx * t - p.x, dy = a.y + aby * t - p.y, dz = a.z + abz * t - p.z;
      return Math.sqrt(dx * dx + dy * dy + dz * dz);
    },
    /** Interseção raio-esfera; retorna t ou -1. dir deve ser unitário. */
    raySphere(o, d, c, r) {
      const ox = o.x - c.x, oy = o.y - c.y, oz = o.z - c.z;
      const b = ox * d.x + oy * d.y + oz * d.z;
      const cc = ox * ox + oy * oy + oz * oz - r * r;
      const disc = b * b - cc;
      if (disc < 0) return -1;
      const s = Math.sqrt(disc);
      let t = -b - s;
      if (t < 0) t = -b + s;
      return t >= 0 ? t : -1;
    },
    /** Interseção raio-AABB (método das placas). Retorna t de entrada ou -1. */
    rayAABB(o, d, minx, miny, minz, maxx, maxy, maxz) {
      let tmin = 0, tmax = Infinity;
      const axes = [[o.x, d.x, minx, maxx], [o.y, d.y, miny, maxy], [o.z, d.z, minz, maxz]];
      for (let i = 0; i < 3; i++) {
        const oo = axes[i][0], dd = axes[i][1], lo = axes[i][2], hi = axes[i][3];
        if (Math.abs(dd) < 1e-9) { if (oo < lo || oo > hi) return -1; continue; }
        let t1 = (lo - oo) / dd, t2 = (hi - oo) / dd;
        if (t1 > t2) { const t = t1; t1 = t2; t2 = t; }
        if (t1 > tmin) tmin = t1;
        if (t2 < tmax) tmax = t2;
        if (tmin > tmax) return -1;
      }
      return tmin;
    }
  };

  // ---------------------------------------------------------------- eventos
  /** Barramento de eventos simples. Assinantes de longa duração (render, áudio, UI) registram-se uma
   * única vez na inicialização; a simulação apenas emite. `once` evita duplicação por chave. */
  class Emitter {
    constructor() { this.map = new Map(); this.keys = new Set(); }
    on(name, fn, key) {
      if (key) { if (this.keys.has(key)) return; this.keys.add(key); }
      if (!this.map.has(name)) this.map.set(name, []);
      this.map.get(name).push(fn);
    }
    off(name, fn) { const l = this.map.get(name); if (!l) return; const i = l.indexOf(fn); if (i >= 0) l.splice(i, 1); }
    emit(name, a, b, c, d, e) {
      const l = this.map.get(name); if (!l) return;
      for (let i = 0; i < l.length; i++) {
        try { l[i](a, b, c, d, e); } catch (e) { MP.diag && MP.diag.error('evento "' + name + '"', e); }
      }
    }
    count(name) { const l = this.map.get(name); return l ? l.length : 0; }
  }
  MP.Emitter = Emitter;
  MP.events = new Emitter();

  // ---------------------------------------------------------------- heap binário (A*)
  class MinHeap {
    constructor() { this.items = []; this.prio = []; }
    get size() { return this.items.length; }
    clear() { this.items.length = 0; this.prio.length = 0; }
    push(item, p) {
      const it = this.items, pr = this.prio; it.push(item); pr.push(p);
      let i = it.length - 1;
      while (i > 0) {
        const parent = (i - 1) >> 1;
        if (pr[parent] <= pr[i]) break;
        [it[parent], it[i]] = [it[i], it[parent]]; [pr[parent], pr[i]] = [pr[i], pr[parent]];
        i = parent;
      }
    }
    pop() {
      const it = this.items, pr = this.prio;
      const top = it[0];
      const lastI = it.pop(), lastP = pr.pop();
      if (it.length > 0) {
        it[0] = lastI; pr[0] = lastP;
        let i = 0; const n = it.length;
        for (;;) {
          const l = i * 2 + 1, r = l + 1; let m = i;
          if (l < n && pr[l] < pr[m]) m = l;
          if (r < n && pr[r] < pr[m]) m = r;
          if (m === i) break;
          [it[m], it[i]] = [it[i], it[m]]; [pr[m], pr[i]] = [pr[i], pr[m]];
          i = m;
        }
      }
      return top;
    }
  }
  MP.MinHeap = MinHeap;

  // ---------------------------------------------------------------- diagnóstico
  MP.diag = {
    errors: [],
    logs: [],
    error(ctx, err) {
      const msg = '[' + ctx + '] ' + (err && err.message ? err.message : String(err));
      this.errors.push({ t: Date.now(), msg, stack: err && err.stack ? String(err.stack) : '' });
      if (this.errors.length > 50) this.errors.shift();
      if (typeof console !== 'undefined' && !this.quiet) console.error('MirageProtocol', msg, err);
      MP.events.emit('diag:error', msg);
    },
    log(msg) {
      this.logs.push(msg); if (this.logs.length > 100) this.logs.shift();
    }
  };

  // ---------------------------------------------------------------- armazenamento
  const storage = MP.storage = {
    available: (function () {
      try {
        if (typeof localStorage === 'undefined') return false;
        const k = '__mp_test__'; localStorage.setItem(k, '1'); localStorage.removeItem(k); return true;
      } catch (e) { return false; }
    })(),
    get(key, fallback) {
      if (!this.available) return fallback;
      try { const raw = localStorage.getItem(key); return raw ? JSON.parse(raw) : fallback; }
      catch (e) { MP.diag.error('storage.get ' + key, e); return fallback; }
    },
    set(key, val) {
      if (!this.available) return false;
      try { localStorage.setItem(key, JSON.stringify(val)); return true; }
      catch (e) { MP.diag.error('storage.set ' + key, e); return false; }
    }
  };

  // ---------------------------------------------------------------- configurações
  const SETTINGS_KEY = 'mirageProtocol.settings.v1';
  /** Esquema: tipo, limites e padrão. Toda leitura passa por validação. */
  const schema = {
    mouseSens: { type: 'num', min: 0.1, max: 5, def: 1.0 },
    touchSens: { type: 'num', min: 0.1, max: 5, def: 1.0 },
    scopeSensMult: { type: 'num', min: 0.2, max: 2, def: 1.0 },
    invertY: { type: 'bool', def: false },
    fov: { type: 'num', min: 60, max: 100, def: 78 },
    volume: { type: 'num', min: 0, max: 1, def: 0.8 },
    sfxVolume: { type: 'num', min: 0, max: 1, def: 1.0 },
    musicVolume: { type: 'num', min: 0, max: 1, def: 0.35 },
    quality: { type: 'enum', values: ['low', 'medium', 'high'], def: 'auto' },
    shadows: { type: 'bool', def: true },
    renderScale: { type: 'num', min: 0.4, max: 1, def: 1.0 },
    fpsLimit: { type: 'enum', values: [0, 30, 60, 120], def: 0 },
    showFps: { type: 'bool', def: false },
    vibration: { type: 'bool', def: true },
    shiftMode: { type: 'enum', values: ['walk', 'run'], def: 'walk' },
    crouchToggle: { type: 'bool', def: false },
    touchControls: { type: 'enum', values: ['auto', 'on', 'off'], def: 'auto' },
    touchButtonScale: { type: 'num', min: 0.6, max: 1.6, def: 1.0 },
    touchOpacity: { type: 'num', min: 0.2, max: 1, def: 0.75 },
    touchLayout: { type: 'obj', def: {} },
    crosshairColor: { type: 'enum', values: ['#5cff7a', '#ffffff', '#00e5ff', '#ffe14d', '#ff4dd2'], def: '#5cff7a' },
    tutorialSeen: { type: 'bool', def: false },
    lastDifficulty: { type: 'enum', values: ['easy', 'normal', 'hard'], def: 'normal' },
    lastTeam: { type: 'enum', values: ['T', 'CT', 'auto'], def: 'auto' },
    lastTeamSize: { type: 'num', min: 1, max: 5, def: 5, int: true },
    lastRoundsToWin: { type: 'enum', values: [3, 5, 8, 13], def: 8 }
  };
  // "auto" é valor especial de qualidade (detecção de dispositivo)
  schema.quality.values.push('auto');

  function validate(key, v) {
    const s = schema[key];
    if (!s) return undefined;
    switch (s.type) {
      case 'num': {
        let n = Number(v);
        if (!isFinite(n)) return s.def;
        n = M.clamp(n, s.min, s.max);
        return s.int ? Math.round(n) : n;
      }
      case 'bool': return typeof v === 'boolean' ? v : s.def;
      case 'enum': return s.values.indexOf(v) >= 0 ? v : s.def;
      case 'obj': {
        if (!v || typeof v !== 'object' || Array.isArray(v)) return {};
        const out = {};
        for (const k of Object.keys(v)) {
          const e = v[k];
          if (e && isFinite(e.x) && isFinite(e.y)) out[k] = { x: M.clamp(+e.x, 0, 1), y: M.clamp(+e.y, 0, 1) };
        }
        return out;
      }
    }
    return s.def;
  }

  MP.settings = {
    schema,
    values: {},
    load() {
      const raw = storage.get(SETTINGS_KEY, {}) || {};
      for (const k of Object.keys(schema)) this.values[k] = validate(k, raw[k] !== undefined ? raw[k] : schema[k].def);
      return this.values;
    },
    save() { return storage.set(SETTINGS_KEY, this.values); },
    get(k) { return this.values[k]; },
    set(k, v) {
      if (!schema[k]) return false;
      const nv = validate(k, v);
      const changed = JSON.stringify(nv) !== JSON.stringify(this.values[k]);
      this.values[k] = nv;
      if (changed) { this.save(); MP.events.emit('settings:changed', k, nv); }
      return true;
    },
    reset() {
      const keep = { tutorialSeen: this.values.tutorialSeen };
      for (const k of Object.keys(schema)) this.values[k] = validate(k, schema[k].def);
      Object.assign(this.values, keep);
      this.save();
      MP.events.emit('settings:changed', '*', null);
    },
    validate
  };
  MP.settings.load();

  // ---------------------------------------------------------------- histórico de partidas
  const HISTORY_KEY = 'mirageProtocol.history.v1';
  MP.history = {
    list() { const l = storage.get(HISTORY_KEY, []); return Array.isArray(l) ? l : []; },
    add(entry) { const l = this.list(); l.unshift(entry); while (l.length > 20) l.pop(); storage.set(HISTORY_KEY, l); },
    clear() { storage.set(HISTORY_KEY, []); }
  };
})(typeof window !== 'undefined' ? window : globalThis);
