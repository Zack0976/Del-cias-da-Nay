/* Mirage Protocol — mundo dinâmico: agentes, granadas, fumaça, fogo, armas no chão, bomba e ruídos. */
(function (root) {
  'use strict';
  const MP = root.MP;
  const { V3, math: M, map } = MP;
  const ev = MP.events;

  const GRAV = 15;
  const SMOKE_R = 4.3, SMOKE_LIFE = 18, FIRE_R = 3.0, FIRE_LIFE = 7, HE_R = 8.5, HE_DMG = 98;

  /** Bomba com máquina de estados explícita. */
  const BOMB_TRANSITIONS = {
    available: ['carried'],
    carried: ['available', 'planting'],
    planting: ['carried', 'available', 'planted'],
    planted: ['defusing', 'detonated'],
    defusing: ['planted', 'defused', 'detonated'],
    defused: [],
    detonated: []
  };
  class Bomb {
    constructor() { this.reset(); }
    reset() {
      this.state = 'available'; this.carrier = null; this.pos = new V3(); this.site = null;
      this.planter = null; this.plantStart = 0; this.plantEnd = 0;
      this.defuser = null; this.defuseStart = 0; this.defuseEnd = 0;
      this.explodeAt = 0; this.plantedAt = 0; this.nextBeep = 0; this.droppedAt = 0;
    }
    setState(s, now) {
      if (this.state === s) return true;
      if (BOMB_TRANSITIONS[this.state].indexOf(s) < 0) {
        MP.diag.error('bomba', new Error('transição inválida ' + this.state + ' → ' + s));
        return false;
      }
      const prev = this.state; this.state = s;
      ev.emit('bomb:state', s, prev, this);
      return true;
    }
    get isPlanted() { return this.state === 'planted' || this.state === 'defusing'; }
  }
  MP.Bomb = Bomb;
  MP.PLANT_TIME = 3.2; MP.BOMB_TIMER = 40; MP.DEFUSE_TIME = 10; MP.DEFUSE_KIT_TIME = 5;

  const world = MP.world = {
    time: 0,
    agents: [],
    grenades: [],
    smokes: [],
    fires: [],
    drops: [],
    noises: [],
    bomb: new Bomb(),
    friendlyFire: false,
    hooks: { onKill: null, onDamage: null },
    nextId: 1,

    clear() {
      for (const g of this.grenades) ev.emit('grenade:remove', g);
      for (const s of this.smokes) ev.emit('smoke:end', s);
      for (const f of this.fires) ev.emit('fire:end', f);
      for (const d of this.drops) ev.emit('drop:remove', d);
      this.grenades.length = 0; this.smokes.length = 0; this.fires.length = 0; this.drops.length = 0; this.noises.length = 0;
    },
    clearAll() {
      this.clear();
      for (const a of this.agents) ev.emit('agent:remove', a);
      this.agents.length = 0;
      this.bomb.reset();
      ev.emit('bomb:state', 'reset', null, this.bomb);
    },
    addAgent(a) { this.agents.push(a); ev.emit('agent:add', a); return a; },
    alive(team) { let n = 0; for (const a of this.agents) if (a.alive && (!team || a.team === team)) n++; return n; },

    // ------------------------------------------------------------- ruídos (percepção dos bots)
    emitNoise(pos, radius, source, kind) {
      this.noises.push({ pos: pos.clone(), radius, source, kind, time: this.time });
      if (this.noises.length > 64) this.noises.shift();
    },

    // ------------------------------------------------------------- linha de visão
    smokeBlocks(a, b) {
      for (const s of this.smokes) {
        if (s.radiusNow < 1.2) continue;
        if (M.distPointSegment(s.pos, a, b) < s.radiusNow * 0.9) return true;
      }
      return false;
    },
    losClear(a, b) { return map.segmentClear(a, b) && !this.smokeBlocks(a, b); },

    // ------------------------------------------------------------- granadas
    throwGrenade(agent, gtype, strong) {
      const dir = M.dirFromAngles(agent.yaw + agent.punchY, agent.pitch + agent.punchP + 0.06);
      const eye = agent.eyePos(new V3());
      const speed = strong ? 17 : 9;
      const g = {
        id: this.nextId++, type: gtype, owner: agent, team: agent.team,
        pos: eye.clone().addScaled(dir, 0.35),
        vel: dir.clone().scale(speed).add(new V3(agent.vel.x * 0.6, agent.vel.y * 0.3, agent.vel.z * 0.6)),
        born: this.time, fuse: gtype === 'smoke' ? 2.4 : gtype === 'molotov' ? 2.6 : 1.6,
        resting: false, restTime: 0, done: false, bounces: 0
      };
      // não nasce dentro da parede
      if (map.pointSolid(g.pos.x, g.pos.y, g.pos.z)) g.pos.copy(eye);
      this.grenades.push(g);
      ev.emit('grenade:throw', g);
      this.emitNoise(eye, 10, agent, 'throw');
      return g;
    },
    updateGrenades(dt) {
      const tmp = new V3();
      for (let i = this.grenades.length - 1; i >= 0; i--) {
        const g = this.grenades[i];
        if (!g.resting) {
          g.vel.y -= GRAV * dt;
          const step = g.vel.len() * dt;
          if (step > 1e-5) {
            tmp.copy(g.vel).normalize();
            const hit = map.raycast(g.pos, tmp, step + 0.08);
            if (hit) {
              const n = new V3(hit.nx, hit.ny, hit.nz);
              g.pos.addScaled(tmp, Math.max(0, hit.t - 0.08));
              if (g.type === 'molotov' && n.y > 0.6) { this.detonate(g); this.grenades.splice(i, 1); continue; }
              const vn = g.vel.dot(n);
              g.vel.addScaled(n, -2 * vn);
              g.vel.scale(0.45);
              g.bounces++;
              if (Math.abs(vn) > 1.5) ev.emit('grenade:bounce', g);
              if (n.y > 0.6 && g.vel.len() < 1.6) { g.resting = true; g.vel.set(0, 0, 0); g.restTime = this.time; }
            } else g.pos.addScaled(g.vel, dt);
          }
        }
        const age = this.time - g.born;
        let det = age >= g.fuse;
        if (g.type === 'smoke') det = (g.resting && this.time - g.restTime > 0.6) || age > 3.5;
        if (det) { this.detonate(g); this.grenades.splice(i, 1); }
      }
    },
    detonate(g) {
      g.done = true;
      ev.emit('grenade:remove', g);
      const p = g.pos;
      if (g.type === 'he') {
        ev.emit('explosion', p.clone(), 1);
        this.emitNoise(p, 50, g.owner, 'explosion');
        const c = new V3();
        for (const a of this.agents) {
          if (!a.alive) continue;
          if (!this.friendlyFire && a.team === g.team && a !== g.owner) continue;
          c.set(a.pos.x, a.pos.y + a.height * 0.6, a.pos.z);
          const d = c.dist(p);
          if (d > HE_R) continue;
          if (!map.segmentClear(p.clone().add(new V3(0, 0.2, 0)), c)) continue;
          let dmg = HE_DMG * Math.pow(1 - d / HE_R, 1.3);
          if (a.armor > 0) { const ad = dmg * 0.5; a.armor = Math.max(0, a.armor - ad * 0.5); dmg -= ad; }
          a.applyDamage(Math.round(dmg), g.owner, 'he', 'chest', p, this.time);
        }
      } else if (g.type === 'flash') {
        ev.emit('flashbang', p.clone());
        this.emitNoise(p, 40, g.owner, 'explosion');
        const eye = new V3(), dir = new V3(), view = new V3();
        for (const a of this.agents) {
          if (!a.alive) continue;
          a.eyePos(eye);
          const d = eye.dist(p);
          if (d > 30 || !this.losClear(p, eye)) continue;
          dir.subVectors(p, eye).normalize();
          M.dirFromAngles(a.yaw, a.pitch, view);
          const dot = view.dot(dir);
          let facing = dot > 0.6 ? 1 : dot > 0.1 ? 0.55 : dot > -0.4 ? 0.25 : 0.1;
          // bots aliados ouviram o aviso de rádio ("Lançando flash!") e desviaram o olhar
          if (a.ai && a.team === g.team && a.ai.dk !== 'easy') facing *= 0.15;
          const distF = M.clamp(1.15 - d / 30, 0.1, 1);
          const dur = 4.6 * facing * distF;
          if (dur < 0.25) continue;
          const until = this.time + dur;
          if (until > a.flashUntil) { a.flashUntil = until; a.flashDur = dur; }
          ev.emit('flash:blind', a, dur);
        }
      } else if (g.type === 'smoke') {
        const s = { id: this.nextId++, pos: p.clone().add(new V3(0, 1.4, 0)), born: this.time, life: SMOKE_LIFE, radiusNow: 0 };
        this.smokes.push(s);
        // fumaça apaga fogo
        for (let i = this.fires.length - 1; i >= 0; i--) if (this.fires[i].pos.distXZ(s.pos) < SMOKE_R + FIRE_R * 0.5) { ev.emit('fire:end', this.fires[i]); this.fires.splice(i, 1); }
        ev.emit('smoke:start', s);
      } else if (g.type === 'molotov') {
        // cai até o chão
        const down = map.raycast(p, new V3(0, -1, 0), 30);
        const fp = p.clone(); if (down) fp.y -= down.t; else fp.y = 0;
        for (const s of this.smokes) if (s.pos.distXZ(fp) < SMOKE_R) { ev.emit('fire:fizzle', fp); return; }
        const f = { id: this.nextId++, pos: fp, born: this.time, life: FIRE_LIFE, owner: g.owner, team: g.team, nextTick: this.time };
        this.fires.push(f);
        this.emitNoise(fp, 25, g.owner, 'explosion');
        ev.emit('fire:start', f);
      }
    },
    updateAreaEffects() {
      const t = this.time;
      for (let i = this.smokes.length - 1; i >= 0; i--) {
        const s = this.smokes[i]; const age = t - s.born;
        s.radiusNow = SMOKE_R * M.clamp(age / 1.2, 0, 1) * (age > s.life - 2 ? M.clamp((s.life - age) / 2, 0, 1) : 1);
        if (age > s.life) { ev.emit('smoke:end', s); this.smokes.splice(i, 1); }
      }
      for (let i = this.fires.length - 1; i >= 0; i--) {
        const f = this.fires[i];
        if (t - f.born > f.life) { ev.emit('fire:end', f); this.fires.splice(i, 1); continue; }
        if (t >= f.nextTick) {
          f.nextTick = t + 0.25;
          for (const a of this.agents) {
            if (!a.alive) continue;
            if (!this.friendlyFire && a.team === f.team && a !== f.owner) continue;
            if (a.pos.distXZ(f.pos) < FIRE_R && Math.abs(a.pos.y - f.pos.y) < 1.5) a.applyDamage(8, f.owner, 'molotov', 'legs', f.pos, t);
          }
        }
      }
    },
    inFire(pos, margin = 0) {
      for (const f of this.fires) if (pos.distXZ(f.pos) < FIRE_R + margin) return f;
      return null;
    },

    // ------------------------------------------------------------- armas no chão
    dropWeapon(ws, pos, vel) {
      if (!ws) return null;
      ws.reloading = false; ws.zoomLevel = 0;
      const d = { id: this.nextId++, ws, pos: pos.clone(), vel: vel ? vel.clone() : new V3(), born: this.time, resting: false };
      d.pos.y = Math.max(d.pos.y, 0.3);
      this.drops.push(d);
      ev.emit('drop:add', d);
      return d;
    },
    removeDrop(d) { const i = this.drops.indexOf(d); if (i >= 0) { this.drops.splice(i, 1); ev.emit('drop:remove', d); } },
    updateDrops(dt) {
      for (const d of this.drops) {
        if (d.resting) continue;
        d.vel.y -= GRAV * dt;
        d.vel.x *= 0.98; d.vel.z *= 0.98;
        const nx = d.pos.x + d.vel.x * dt, nz = d.pos.z + d.vel.z * dt;
        if (!map.pointSolid(nx, d.pos.y + 0.1, d.pos.z)) d.pos.x = nx; else d.vel.x = 0;
        if (!map.pointSolid(d.pos.x, d.pos.y + 0.1, nz)) d.pos.z = nz; else d.vel.z = 0;
        const g = map.groundBelow(d.pos.x - 0.05, d.pos.z - 0.05, d.pos.x + 0.05, d.pos.z + 0.05, d.pos.y);
        d.pos.y += d.vel.y * dt;
        if (d.pos.y <= g + 0.05) { d.pos.y = g + 0.05; d.resting = true; }
      }
    },

    update(dt) {
      this.time += dt;
      this.updateGrenades(dt);
      this.updateAreaEffects();
      this.updateDrops(dt);
      // descarta ruídos antigos
      while (this.noises.length && this.time - this.noises[0].time > 3) this.noises.shift();
    }
  };
  world.SMOKE_R = SMOKE_R; world.FIRE_R = FIRE_R;
})(typeof window !== 'undefined' ? window : globalThis);
