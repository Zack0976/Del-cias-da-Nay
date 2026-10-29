/* Mirage Protocol — agente (jogador ou bot): física, inventário, disparo, balística, dano e caixas de acerto.
 * Jogador e bots usam exatamente a mesma classe e as mesmas regras; só muda quem preenche `intent`. */
(function (root) {
  'use strict';
  const MP = root.MP;
  const { V3, math: M, map, WEAPONS, WeaponState, world } = MP;
  const ev = MP.events;
  const DEG = Math.PI / 180;

  const RUN_SPEED = 6.2, WALK_MULT = 0.52, CROUCH_MULT = 0.36;
  const GRAV = 15, JUMP_V = 5.6, STEP_H = 0.45, RADIUS = 0.3;
  const STAND_H = 1.8, CROUCH_H = 1.25, STAND_EYE = 1.64, CROUCH_EYE = 1.12;
  MP.PHYS = { RUN_SPEED, WALK_MULT, CROUCH_MULT, GRAV, JUMP_V, STEP_H, RADIUS, STAND_H, CROUCH_H };

  const _tmp = new V3(), _tmp2 = new V3(), _dir = new V3(), _org = new V3();

  class Agent {
    constructor(o) {
      this.id = o.id; this.name = o.name; this.team = o.team; this.isBot = !!o.isBot; this.isPlayer = !o.isBot;
      this.difficulty = o.difficulty || 'normal';
      this.pos = new V3(); this.vel = new V3(); this.yaw = 0; this.pitch = 0;
      this.punchP = 0; this.punchY = 0; this.recoilSeed = Math.random() * 10;
      this.crouchAmt = 0; this.onGround = true; this.jumpHeld = false; this.lastGroundTime = 0;
      this.money = 800; this.kills = 0; this.deaths = 0; this.assists = 0; this.score = 0;
      this.damageDealt = 0; this.headshots = 0; this.shotsFired = 0; this.shotsHit = 0; this.mvps = 0;
      this.roundKills = 0; this.roundDamage = 0;
      this.hp = 100; this.armor = 0; this.helmet = false; this.alive = true;
      this.inv = { primary: null, secondary: null, knife: new WeaponState('knife'), grenades: { he: 0, flash: 0, smoke: 0, molotov: 0 }, grenadeIds: { molotov: o.team === 'CT' ? 'incend' : 'molotov' }, bomb: false, kit: false };
      this.active = 'knife'; this.activeGrenade = null; this.prevSlot = 'secondary';
      this.drawEnd = 0;
      this.intent = { f: 0, r: 0, walk: false, crouch: false, jump: false, fire: false, firePressed: false, alt: false, use: false };
      this.stepDist = 0; this.flashUntil = 0; this.flashDur = 1;
      this.deathTime = 0; this.deathDir = 0; this.killer = null;
      this.lastDamageTime = -10; this.damageLog = new Map(); // atacante -> dano (assistências)
      this.footMat = 'sand'; this.speedNow = 0; this.moving = false;
      this.meleeAlt = false; this.inBuyZone = false;
      this.recentlyHitBy = null;
      this.ai = null;
    }

    // ---------------------------------------------------------------- geometria
    get height() { return M.lerp(STAND_H, CROUCH_H, this.crouchAmt); }
    get eyeHeight() { return M.lerp(STAND_EYE, CROUCH_EYE, this.crouchAmt); }
    eyePos(out) { return (out || new V3()).set(this.pos.x, this.pos.y + this.eyeHeight, this.pos.z); }
    chestPos(out) { return (out || new V3()).set(this.pos.x, this.pos.y + this.height * 0.68, this.pos.z); }
    headPos(out) { return (out || new V3()).set(this.pos.x, this.pos.y + this.height - 0.14, this.pos.z); }
    viewDir(out) { return M.dirFromAngles(this.yaw + this.punchY, this.pitch + this.punchP, out); }
    isFlashed(now) { return now < this.flashUntil; }
    flashAmount(now) { if (now >= this.flashUntil) return 0; const left = this.flashUntil - now; return M.clamp(left / Math.min(this.flashDur, 2.2), 0, 1); }

    /** Teste de raio contra as caixas de acerto. Retorna {t, group} ou null. */
    rayHit(o, d, maxT) {
      if (!this.alive) return null;
      const h = this.height, x = this.pos.x, y = this.pos.y, z = this.pos.z;
      const broad = M.rayAABB(o, d, x - 0.4, y, z - 0.4, x + 0.4, y + h + 0.05, z + 0.4);
      if (broad < 0 || broad > maxT) return null;
      let best = null, bt = maxT;
      const tHead = M.raySphere(o, d, this.headPos(_tmp2), 0.16);
      if (tHead >= 0 && tHead < bt) { bt = tHead; best = 'head'; }
      const tUp = M.rayAABB(o, d, x - 0.24, y + h * 0.42, z - 0.24, x + 0.24, y + h - 0.27, z + 0.24);
      if (tUp >= 0 && tUp < bt) {
        bt = tUp;
        const hy = o.y + d.y * tUp - y;
        best = hy > h * 0.6 ? 'chest' : 'stomach';
      }
      const tLeg = M.rayAABB(o, d, x - 0.2, y, z - 0.2, x + 0.2, y + h * 0.42, z + 0.2);
      if (tLeg >= 0 && tLeg < bt) { bt = tLeg; best = 'legs'; }
      return best ? { t: bt, group: best } : null;
    }

    // ---------------------------------------------------------------- inventário
    weaponIn(slot) {
      if (slot === 'primary') return this.inv.primary;
      if (slot === 'secondary') return this.inv.secondary;
      if (slot === 'knife') return this.inv.knife;
      return null;
    }
    get weapon() { return this.weaponIn(this.active); }
    get activeDef() {
      if (this.active === 'grenade') return WEAPONS[this.grenadeWeaponId(this.activeGrenade)];
      if (this.active === 'bomb') return WEAPONS.bomb;
      const w = this.weapon; return w ? w.def : WEAPONS.knife;
    }
    grenadeWeaponId(type) { return type === 'molotov' ? this.inv.grenadeIds.molotov : type; }
    hasGrenades() { const g = this.inv.grenades; return g.he + g.flash + g.smoke + g.molotov > 0; }
    nextGrenadeType(after) {
      const order = ['he', 'flash', 'smoke', 'molotov'];
      let i = after ? order.indexOf(after) : -1;
      for (let k = 0; k < 4; k++) { i = (i + 1) % 4; if (this.inv.grenades[order[i]] > 0) return order[i]; }
      return null;
    }
    canSwitchTo(slot, gtype) {
      if (slot === 'grenade') return !!(gtype && this.inv.grenades[gtype] > 0);
      if (slot === 'bomb') return this.inv.bomb;
      return !!this.weaponIn(slot);
    }
    switchTo(slot, gtype, now) {
      if (!this.alive) return false;
      if (slot === 'grenade' && !gtype) gtype = this.nextGrenadeType(this.active === 'grenade' ? this.activeGrenade : null);
      if (!this.canSwitchTo(slot, gtype)) return false;
      if (slot === this.active && (slot !== 'grenade' || gtype === this.activeGrenade)) return false;
      const cur = this.weapon;
      if (cur) { cur.cancelReload(); cur.zoomLevel = 0; cur.triggerHeld = false; }
      if (this.weaponIn(this.active)) this.prevSlot = this.active;
      this.active = slot; this.activeGrenade = slot === 'grenade' ? gtype : null;
      this.drawEnd = now + this.activeDef.draw;
      const nw = this.weapon; if (nw) { nw.shotsFired = 0; nw.triggerHeld = true; }
      ev.emit('weapon:switch', this, this.activeDef);
      return true;
    }
    bestSlot() { return this.inv.primary ? 'primary' : this.inv.secondary ? 'secondary' : 'knife'; }
    switchToBest(now) { const s = this.bestSlot(); if (s !== this.active) this.switchTo(s, null, now); }
    giveWeapon(id, now) {
      const def = WEAPONS[id]; const ws = new WeaponState(id);
      const slot = def.slot;
      const old = this.weaponIn(slot);
      if (slot === 'primary') this.inv.primary = ws; else if (slot === 'secondary') this.inv.secondary = ws;
      if (this.active === slot || old === null) { this.active = '__'; this.switchTo(slot, null, now || 0); }
      return { ws, old };
    }
    totalSpeedMult() { return this.activeDef.speed || 1; }

    // ---------------------------------------------------------------- reset de rodada
    spawnAt(x, z, yaw) {
      this.pos.set(x, map.groundBelow(x - 0.1, z - 0.1, x + 0.1, z + 0.1, 5), z);
      this.vel.set(0, 0, 0); this.yaw = yaw; this.pitch = 0; this.punchP = 0; this.punchY = 0;
      this.crouchAmt = 0; this.onGround = true; this.alive = true; this.hp = 100;
      this.flashUntil = 0; this.killer = null; this.damageLog.clear(); this.roundKills = 0; this.roundDamage = 0;
      this.intent.f = this.intent.r = 0; this.intent.fire = false;
      const w = this.weapon; if (w) w.cancelReload();
      for (const s of ['primary', 'secondary']) { const ws = this.weaponIn(s); if (ws) { ws.cancelReload(); ws.zoomLevel = 0; ws.shotsFired = 0; ws.nextFire = 0; } }
      this.active = '__'; this.switchTo(this.bestSlot(), null, 0); this.drawEnd = 0;
    }

    // ---------------------------------------------------------------- física
    update(dt, now, frozen) {
      if (!this.alive) return;
      const it = this.intent;
      // agachar (só levanta se houver espaço)
      const wantCrouch = it.crouch;
      if (wantCrouch) this.crouchAmt = Math.min(1, this.crouchAmt + dt * 8);
      else if (this.crouchAmt > 0) {
        const h = STAND_H;
        if (!map.boxBlocked(this.pos.x - RADIUS, this.pos.y + 0.05, this.pos.z - RADIUS, this.pos.x + RADIUS, this.pos.y + h, this.pos.z + RADIUS)) this.crouchAmt = Math.max(0, this.crouchAmt - dt * 8);
      }
      // velocidade desejada
      let f = frozen ? 0 : M.clamp(it.f, -1, 1), r = frozen ? 0 : M.clamp(it.r, -1, 1);
      const mag = Math.sqrt(f * f + r * r);
      if (mag > 1) { f /= mag; r /= mag; }
      const sy = Math.sin(this.yaw), cy = Math.cos(this.yaw);
      const wx = -sy * f + cy * r, wz = -cy * f - sy * r;
      const wl = Math.sqrt(wx * wx + wz * wz);
      const analog = Math.min(1, mag);
      let maxSpeed = RUN_SPEED * this.totalSpeedMult() * analog;
      if (it.walk) maxSpeed *= WALK_MULT;
      if (this.crouchAmt > 0.5) maxSpeed *= CROUCH_MULT;
      const w = this.weapon; if (w && w.zoomLevel > 0) maxSpeed *= 0.55;
      if (this.ai && this.ai.speedCap) maxSpeed = Math.min(maxSpeed, this.ai.speedCap);
      const dx = wl > 0 ? wx / wl : 0, dz = wl > 0 ? wz / wl : 0;
      if (this.onGround) {
        // atrito
        const sp = Math.sqrt(this.vel.x * this.vel.x + this.vel.z * this.vel.z);
        if (sp > 0) {
          const drop = Math.max(sp, 2.5) * 7.5 * dt;
          const ns = Math.max(0, sp - drop) / sp;
          this.vel.x *= ns; this.vel.z *= ns;
        }
        const cur = this.vel.x * dx + this.vel.z * dz;
        const add = maxSpeed - cur;
        if (add > 0 && wl > 0) { const acc = Math.min(add, 9 * Math.max(maxSpeed, 1) * dt); this.vel.x += dx * acc; this.vel.z += dz * acc; }
        // pulo
        if (it.jump && !this.jumpHeld && !frozen && this.crouchAmt < 0.9) {
          this.vel.y = JUMP_V; this.onGround = false; ev.emit('jump', this);
        }
      } else if (wl > 0) {
        const cur = this.vel.x * dx + this.vel.z * dz;
        const add = Math.min(maxSpeed, 0.9) - cur;
        if (add > 0) { const acc = Math.min(add, 40 * dt); this.vel.x += dx * acc; this.vel.z += dz * acc; }
      }
      this.jumpHeld = it.jump;
      this.vel.y -= GRAV * dt;
      this.moveAndCollide(dt);
      this.speedNow = Math.sqrt(this.vel.x * this.vel.x + this.vel.z * this.vel.z);
      this.moving = this.speedNow > 0.5;
      // passos (correr faz barulho; andar/agachar é silencioso)
      if (this.onGround && this.speedNow > RUN_SPEED * 0.6) {
        this.stepDist += this.speedNow * dt;
        if (this.stepDist > 2.1) {
          this.stepDist = 0;
          const cell = map.cellAt(map.colOf(this.pos.x), map.rowOf(this.pos.z));
          this.footMat = this.pos.y > 0.1 && cell ? cell.mat : (cell ? cell.mat : 'sand');
          ev.emit('footstep', this, this.footMat);
          world.emitNoise(this.pos, 16, this, 'step');
        }
      }
      this.updateWeapon(dt, now);
    }

    moveAndCollide(dt) {
      const p = this.pos, v = this.vel, h = this.height;
      const tryAxis = (ax, amount) => {
        if (Math.abs(amount) < 1e-7) return;
        const nx = ax === 0 ? p.x + amount : p.x, nz = ax === 1 ? p.z + amount : p.z;
        if (!map.boxBlocked(nx - RADIUS, p.y + 0.01, nz - RADIUS, nx + RADIUS, p.y + h, nz + RADIUS)) { p.x = nx; p.z = nz; return; }
        // degrau
        if (this.onGround || this.vel.y > -2) {
          const sy = p.y + STEP_H;
          if (!map.boxBlocked(nx - RADIUS, sy, nz - RADIUS, nx + RADIUS, sy + h, nz + RADIUS)) {
            const g = map.groundBelow(nx - RADIUS, nz - RADIUS, nx + RADIUS, nz + RADIUS, sy);
            if (g - p.y <= STEP_H + 0.01) { p.x = nx; p.z = nz; p.y = Math.max(p.y, g); return; }
          }
        }
        if (ax === 0) v.x = 0; else v.z = 0;
      };
      // sub-passos para evitar atravessar quinas em quedas de FPS
      const steps = Math.max(1, Math.ceil(Math.max(Math.abs(v.x), Math.abs(v.z)) * dt / 0.25));
      for (let s = 0; s < steps; s++) { tryAxis(0, v.x * dt / steps); tryAxis(1, v.z * dt / steps); }
      // vertical
      const fx0 = p.x - RADIUS, fz0 = p.z - RADIUS, fx1 = p.x + RADIUS, fz1 = p.z + RADIUS;
      const wasGround = this.onGround;
      if (v.y <= 0) {
        const g = map.groundBelow(fx0, fz0, fx1, fz1, p.y);
        const ny = p.y + v.y * dt;
        if (ny <= g) {
          if (!wasGround && v.y < -6) ev.emit('land', this, -v.y);
          p.y = g; v.y = 0; this.onGround = true;
        } else if (wasGround && p.y - g <= STEP_H + 0.01 && v.y > -3) {
          p.y = g; v.y = 0; this.onGround = true; // descendo escadas
        } else { p.y = ny; this.onGround = false; }
      } else {
        const ny = p.y + v.y * dt;
        if (map.boxBlocked(fx0, ny + 0.01, fz0, fx1, ny + h, fz1)) v.y = 0; else p.y = ny;
        this.onGround = false;
      }
      if (p.y < -5) { p.y = 0.1; v.y = 0; } // salvaguarda
    }

    // ---------------------------------------------------------------- arma
    updateWeapon(dt, now) {
      // recuperação do recuo
      const def = this.activeDef;
      const rec = (def.recovery || 10 * DEG) * dt;
      const w = this.weapon;
      const firingRecently = w && now - w.lastShot < w.interval * 1.5;
      const recMult = firingRecently ? 0.25 : 1;
      this.punchP = Math.max(0, this.punchP - rec * recMult * Math.max(1, this.punchP / (2 * DEG)));
      this.punchY *= Math.max(0, 1 - dt * (firingRecently ? 1.5 : 6));
      if (w) {
        if (!firingRecently && w.shotsFired > 0 && now - w.lastShot > 0.25) w.shotsFired = Math.max(0, w.shotsFired - dt * 18);
        if (w.reloading) {
          const r = w.updateReload(now);
          if (r === 'done') ev.emit('reload:done', this, w);
          else if (r === 'shell') ev.emit('reload:shell', this, w);
        }
        if (!this.intent.fire) w.triggerHeld = false;
      }
      if (!this.intent.fire) this._throwHeld = false;
    }
    startReload(now) {
      const w = this.weapon;
      if (!this.alive || !w || now < this.drawEnd) return false;
      if (w.startReload(now)) { ev.emit('reload:start', this, w); world.emitNoise(this.pos, 9, this, 'reload'); return true; }
      return false;
    }
    currentSpread(w) {
      const d = w.def;
      let s = (w.zoomLevel > 0 && d.scopedSpread !== undefined) ? d.scopedSpread : d.spread;
      const sf = M.clamp(this.speedNow / (RUN_SPEED * (d.speed || 1)), 0, 1.2);
      s += d.moveSpread * Math.pow(sf, 1.4);
      if (!this.onGround) s += d.airSpread;
      if (this.crouchAmt > 0.5) s *= 0.78;
      if (d.mode === 'auto') s += Math.min(w.shotsFired, 10) * 0.07 * DEG;
      return s;
    }
    /** Tenta disparar a arma ativa. Retorna true se disparou. */
    tryFire(now) {
      if (!this.alive || now < this.drawEnd) return false;
      if (this.active === 'grenade') return this.tryThrow(now, true);
      if (this.active === 'bomb') return false;
      const w = this.weapon; if (!w) return false;
      const d = w.def;
      if (now < w.nextFire) return false;
      if (d.mode === 'melee') return this.melee(now, false);
      if (w.reloading) {
        if (d.reloadType === 'shell' && w.clip > 0) { w.cancelReload(); ev.emit('reload:cancel', this, w); } else return false;
      }
      if ((d.mode === 'semi' || d.mode === 'pump' || d.mode === 'bolt') && w.triggerHeld) return false;
      if (w.clip <= 0) {
        w.triggerHeld = true; w.nextFire = now + 0.25;
        ev.emit('dryfire', this, w);
        if (w.reserve > 0) this.startReload(now);
        return false;
      }
      w.clip--; w.nextFire = now + w.interval; w.lastShot = now; w.triggerHeld = true;
      this.shotsFired++;
      const spread = this.currentSpread(w);
      this.eyePos(_org);
      const pellets = d.pellets || 1;
      let anyHit = false;
      for (let i = 0; i < pellets; i++) {
        this.viewDir(_dir);
        applySpread(_dir, spread);
        const res = MP.combat.trace(this, _org, _dir, d);
        if (res.agentHit) anyHit = true;
        ev.emit('shot', this, _org, res.end, d, i);
      }
      if (anyHit) this.shotsHit++;
      // recuo progressivo
      const sf = w.shotsFired;
      const prog = d.mode === 'auto' ? (1 + Math.min(sf, 9) * 0.09) : 1;
      const cm = this.crouchAmt > 0.5 ? 0.82 : 1;
      this.punchP = Math.min(this.punchP + d.recoil * prog * cm, 14 * DEG);
      let hk = 0;
      if (d.mode === 'auto' && sf > 3) hk = Math.sin(sf * 0.5 + this.recoilSeed) * d.recoilH * 1.4;
      hk += (Math.random() - 0.5) * d.recoilH;
      this.punchY = M.clamp(this.punchY + hk, -6 * DEG, 6 * DEG);
      w.shotsFired = sf + 1;
      if (d.mode === 'bolt' || d.mode === 'pump') { if (w.zoomLevel > 0) { w.unscopedByShot = w.zoomLevel; w.zoomLevel = 0; } }
      world.emitNoise(_org, d.cat === 'pistol' ? 38 : 50, this, 'shot');
      ev.emit('fired', this, w);
      if (w.clip === 0 && w.reserve > 0 && this.isBot) w.nextFire = Math.max(w.nextFire, now + 0.2);
      return true;
    }
    melee(now, alt) {
      const w = this.inv.knife; const d = w.def;
      w.nextFire = now + (alt ? 1.1 : 0.45);
      this.eyePos(_org); this.viewDir(_dir);
      ev.emit('knife', this, alt);
      let best = null, bt = d.range;
      for (const a of world.agents) {
        if (a === this || !a.alive) continue;
        if (!world.friendlyFire && a.team === this.team) continue;
        const h = a.rayHit(_org, _dir, bt);
        if (h) { best = { a, h }; bt = h.t; }
      }
      const wall = map.raycast(_org, _dir, d.range);
      if (best && (!wall || wall.t > best.h.t)) {
        // facada pelas costas
        const toV = M.yawTo(this.pos, best.a.pos);
        const back = Math.abs(M.wrapAngle(toV - best.a.yaw)) < 0.9;
        let dmg = alt ? (back ? 180 : d.dmg2) : (back ? 90 : d.dmg);
        if (best.h.group === 'head') dmg *= 1.2;
        best.a.applyDamage(dmg, this, 'knife', best.h.group, this.pos, now, true);
        this.shotsHit++;
        ev.emit('hitFlesh', _tmp.copy(_org).addScaled(_dir, best.h.t), best.a, this, dmg, best.h.group);
      } else if (wall) {
        ev.emit('impact', _tmp.copy(_org).addScaled(_dir, wall.t), new V3(wall.nx, wall.ny, wall.nz), wall.mat, 'knife');
      }
      return true;
    }
    tryThrow(now, strong) {
      const t = this.activeGrenade;
      if (!t || this.inv.grenades[t] <= 0) return false;
      if (this.intent.fire && this._throwHeld) return false;
      this.inv.grenades[t]--;
      this._throwHeld = true;
      world.throwGrenade(this, t, strong);
      const next = this.inv.grenades[t] > 0 ? t : null;
      this.drawEnd = now + 0.5;
      if (next) { this.drawEnd = now + 0.6; ev.emit('weapon:switch', this, this.activeDef); }
      else { this.active = '__'; this.switchTo(this.prevSlot && this.weaponIn(this.prevSlot) ? this.prevSlot : this.bestSlot(), null, now); }
      return true;
    }
    /** Mira secundária: zoom (snipers), facada forte (faca), arremesso curto (granada). */
    altAction(now) {
      if (!this.alive || now < this.drawEnd) return false;
      if (this.active === 'grenade') { this._throwHeld = false; const ok = this.tryThrow(now, false); return ok; }
      const w = this.weapon; if (!w) return false;
      if (w.def.mode === 'melee') { if (now >= w.nextFire) return this.melee(now, true); return false; }
      if (w.def.zoom && !w.reloading) {
        w.zoomLevel = (w.zoomLevel + 1) % (w.def.zoom.length + 1);
        ev.emit('zoom', this, w.zoomLevel);
        return true;
      }
      return false;
    }

    // ---------------------------------------------------------------- dano
    applyDamage(raw, attacker, weaponId, group, fromPos, now, ignoreArmorMult) {
      if (!this.alive || raw <= 0) return 0;
      if (attacker && attacker !== this && attacker.team === this.team && !world.friendlyFire) return 0;
      let dmg = raw;
      const def = WEAPONS[weaponId];
      const armored = this.armor > 0 && group !== 'legs' && (group !== 'head' || this.helmet) && weaponId !== 'molotov' && weaponId !== 'he';
      if (armored && def && def.armorPen !== undefined) {
        const hpD = dmg * def.armorPen;
        const arD = (dmg - hpD) * 0.5;
        this.armor = Math.max(0, Math.round(this.armor - arD));
        dmg = hpD;
      }
      dmg = Math.max(1, Math.round(dmg));
      const applied = Math.min(this.hp, dmg);
      this.hp -= applied;
      this.lastDamageTime = now;
      if (attacker && attacker !== this) {
        this.damageLog.set(attacker, (this.damageLog.get(attacker) || 0) + applied);
        attacker.damageDealt += applied; attacker.roundDamage += applied;
        this.recentlyHitBy = attacker;
      }
      ev.emit('damage', this, attacker, applied, group, fromPos);
      if (world.hooks.onDamage) world.hooks.onDamage(this, attacker, applied, group, fromPos);
      if (this.hp <= 0) this.die(attacker, weaponId, group === 'head', now, fromPos);
      return applied;
    }
    die(killer, weaponId, headshot, now, fromPos) {
      if (!this.alive) return;
      this.alive = false; this.hp = 0; this.deaths++; this.deathTime = now; this.killer = killer;
      this.deathDir = fromPos ? M.yawTo(fromPos, this.pos) : this.yaw;
      const w = this.weapon; if (w) w.cancelReload();
      // armas caem no chão
      const toss = new V3(-Math.sin(this.yaw) * 1.5, 2, -Math.cos(this.yaw) * 1.5);
      const dropPos = this.pos.clone(); dropPos.y += 1.0;
      if (this.inv.primary) { world.dropWeapon(this.inv.primary, dropPos, toss); this.inv.primary = null; }
      else if (this.inv.secondary && this.inv.secondary.def.cost > 200) { world.dropWeapon(this.inv.secondary, dropPos, toss); this.inv.secondary = null; }
      this.inv.grenades.he = this.inv.grenades.flash = this.inv.grenades.smoke = this.inv.grenades.molotov = 0;
      this.armor = 0; this.helmet = false; this.inv.kit = false;
      if (killer && killer !== this) {
        killer.kills++; killer.roundKills++;
        if (headshot) killer.headshots++;
        // assistências: quem causou >= 40 de dano
        for (const [att, d] of this.damageLog) if (att !== killer && d >= 40 && att.team !== this.team) att.assists++;
      }
      ev.emit('kill', killer, this, weaponId, headshot);
      if (world.hooks.onKill) world.hooks.onKill(killer, this, weaponId, headshot);
    }
  }
  MP.Agent = Agent;

  /** Aplica dispersão cônica aleatória a uma direção unitária. */
  const _u = new V3(), _v = new V3();
  function applySpread(dir, spread) {
    if (spread <= 0) return dir;
    // base ortonormal
    if (Math.abs(dir.y) < 0.99) _u.set(-dir.z, 0, dir.x).normalize(); else _u.set(1, 0, 0);
    _v.set(dir.y * _u.z - dir.z * _u.y, dir.z * _u.x - dir.x * _u.z, dir.x * _u.y - dir.y * _u.x);
    const r = spread * Math.sqrt(Math.random()), a = Math.random() * Math.PI * 2;
    const ox = Math.cos(a) * r, oy = Math.sin(a) * r;
    dir.addScaled(_u, ox).addScaled(_v, oy).normalize();
    return dir;
  }
  MP.applySpread = applySpread;

  // ---------------------------------------------------------------- balística
  const _end = new V3(), _p = new V3(), _n = new V3();
  MP.combat = {
    /** Traça um projétil: cenário + agentes, com penetração explícita em madeira. */
    trace(shooter, origin, dir, def, dmgScale = 1) {
      const maxRange = 200;
      let o = _p.copy(origin), traveled = 0, scale = dmgScale, penetrated = 0;
      const out = { end: _end, agentHit: null };
      for (let pass = 0; pass < 3; pass++) {
        const wall = map.raycast(o, dir, maxRange - traveled);
        const wallT = wall ? wall.t : maxRange - traveled;
        const wallInfo = wall ? { t: wall.t, nx: wall.nx, ny: wall.ny, nz: wall.nz, mat: wall.mat } : null;
        // agentes antes da parede
        let best = null, bt = wallT;
        for (const a of world.agents) {
          if (a === shooter || !a.alive) continue;
          if (!world.friendlyFire && a.team === shooter.team) continue; // atravessa aliados sem dano
          const h = a.rayHit(o, dir, bt);
          if (h) { best = { a, h }; bt = h.t; }
        }
        if (best) {
          const dist = traveled + best.h.t;
          const mult = def[best.h.group] || 1;
          const fall = dist > def.range ? Math.pow(def.falloff, (dist - def.range) / 10) : 1;
          const dmg = def.dmg * mult * fall * scale;
          const hp = _end.copy(o).addScaled(dir, best.h.t);
          ev.emit('hitFlesh', hp, best.a, shooter, dmg, best.h.group);
          best.a.applyDamage(dmg, shooter, def.id, best.h.group, origin, world.time);
          out.agentHit = best.a; out.group = best.h.group;
          return out;
        }
        _end.copy(o).addScaled(dir, wallT);
        if (!wallInfo) return out;
        _n.set(wallInfo.nx, wallInfo.ny, wallInfo.nz);
        ev.emit('impact', _end, _n, wallInfo.mat, def.id);
        // penetração balística explícita: só madeira (caixas) e com poder suficiente
        if (wallInfo.mat !== 'wood' || !def.pen || penetrated >= 1) return out;
        const maxPen = def.pen * 2.4;
        let exitT = -1;
        for (let s = 0.1; s <= maxPen; s += 0.1) {
          const x = _end.x + dir.x * s, y = _end.y + dir.y * s, z = _end.z + dir.z * s;
          if (!map.pointSolid(x, y, z)) { exitT = s; break; }
        }
        if (exitT < 0) return out;
        penetrated++;
        scale *= M.clamp(1 - exitT / maxPen, 0.25, 0.8);
        traveled += wallT + exitT;
        o = _p.set(_end.x + dir.x * exitT, _end.y + dir.y * exitT, _end.z + dir.z * exitT);
        ev.emit('impact', o.clone(), new V3(dir.x, dir.y, dir.z), 'wood', def.id);
      }
      return out;
    }
  };
})(typeof window !== 'undefined' ? window : globalThis);
