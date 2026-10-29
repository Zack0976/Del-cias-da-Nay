/* Mirage Protocol — regras do modo Desarme: equipes, rodadas, bomba, economia, compras, modos de treino e livre. */
(function (root) {
  'use strict';
  const MP = root.MP;
  const { V3, math: M, map, world, WEAPONS, GEAR, Agent, BotBrain, intel } = MP;
  const ev = MP.events;

  const ECON = { start: 800, max: 16000, winElim: 3250, winBomb: 3500, winDefuse: 3500, winTime: 3250, lossBase: 1400, lossStep: 500, lossMax: 3400, plant: 300, defuse: 300, plantTeamBonus: 800 };
  const TIMES = { freeze: 6, round: 115, post: 5, buyWindow: 20 };
  MP.ECON = ECON; MP.TIMES = TIMES;

  const BOT_NAMES = ['Areia', 'Corvo', 'Brasa', 'Faísca', 'Nômade', 'Sombra', 'Trovão', 'Granito', 'Vulto', 'Cobalto', 'Miragem', 'Duna', 'Ferro', 'Escarlate', 'Vigia', 'Chacal'];

  const game = MP.game = {
    mode: 'idle',           // competitive | training | free | idle
    phase: 'idle',          // freeze | live | post | over | idle
    phaseStart: 0, phaseEnd: 0,
    roundNum: 0, score: { T: 0, CT: 0 }, lossStreak: { T: 0, CT: 0 },
    config: null, player: null, roundHistory: [], spotted: new Map(),
    lastRoundResult: null, matchStart: 0, paused: false,
    trainingStats: null,

    // ------------------------------------------------------------- início de partida
    start(cfg) {
      this.stop();
      const c = this.config = Object.assign({ mode: 'competitive', team: 'CT', difficulty: 'normal', teamSize: 5, roundsToWin: 8, playerName: 'Você', withPlayer: true, dummiesArmed: false, dummiesMove: true, loadout: null }, cfg || {});
      this.mode = c.mode;
      world.time = 0;
      intel.reset();
      this.score = { T: 0, CT: 0 }; this.lossStreak = { T: 0, CT: 0 }; this.roundNum = 0; this.roundHistory = [];
      this.matchStart = world.time; this.spotted.clear();
      let team = c.team === 'auto' ? (Math.random() < 0.5 ? 'T' : 'CT') : c.team;
      c.team = team;
      let id = 1;
      const names = M.shuffle(BOT_NAMES.slice());
      if (c.withPlayer) {
        this.player = world.addAgent(new Agent({ id: id++, name: c.playerName, team, isBot: false }));
      } else this.player = null;
      if (this.mode === 'competitive') {
        const size = M.clamp(c.teamSize | 0, 1, 5);
        for (const t of ['T', 'CT']) {
          const n = size - (this.player && this.player.team === t ? 1 : 0);
          for (let i = 0; i < n; i++) {
            const a = world.addAgent(new Agent({ id: id++, name: names.pop() || ('Bot ' + id), team: t, isBot: true, difficulty: c.difficulty }));
            new BotBrain(a);
          }
        }
        for (const a of world.agents) a.money = ECON.start;
        this.beginRound();
      } else if (this.mode === 'training') {
        this.trainingStats = { shots: 0, hits: 0, kills: 0, headshots: 0, start: world.time };
        const p = this.player;
        p.team = 'CT'; p.money = 16000;
        p.spawnAt(map.cellX(23.5), map.cellZ(28), 0);
        this.giveDefault(p);
        if (c.loadout) this.buy(p, c.loadout, true);
        p.armor = 100; p.helmet = true;
        for (let i = 0; i < 6; i++) this.spawnDummy(id++, i);
        this.setPhase('live', Infinity);
      } else if (this.mode === 'free') {
        const p = this.player; p.money = 16000;
        p.spawnAt(map.cellX(23.5), map.cellZ(35), 0);
        this.giveDefault(p);
        if (c.loadout) this.buy(p, c.loadout, true);
        this.setPhase('live', Infinity);
      }
      world.hooks.onKill = (k, v, w, hs) => this.onKill(k, v, w, hs);
      world.hooks.onDamage = null;
      ev.emit('match:start', this);
    },
    stop() {
      world.clearAll();
      this.mode = 'idle'; this.phase = 'idle'; this.player = null; this.paused = false;
      world.hooks.onKill = null;
    },
    spawnDummy(id, i) {
      const spots = [[23, 16], [21, 13], [26, 14], [22, 20], [25, 18], [24, 12], [21, 22], [26, 20]];
      const s = spots[i % spots.length];
      const a = world.addAgent(new Agent({ id, name: 'Alvo ' + (i + 1), team: 'T', isBot: true, difficulty: 'easy' }));
      const b = new BotBrain(a); b.dummy = true; b.dummyMove = this.config.dummiesMove && i % 2 === 0; b.dummyArmed = this.config.dummiesArmed;
      a.inv.secondary = new MP.WeaponState('viper');
      if (this.config.dummiesArmed) a.inv.primary = new MP.WeaponState('vespa');
      a.spawnAt(map.cellX(s[0]) + M.rand(-0.5, 0.5), map.cellZ(s[1]), Math.PI);
      a.armor = i % 3 === 0 ? 100 : 0; a.helmet = i % 3 === 0;
      a.dummySlot = i; a.respawnAt = 0;
      return a;
    },

    giveDefault(a) {
      if (!a.inv.secondary) a.inv.secondary = new MP.WeaponState(a.team === 'T' ? 'viper' : 'lince');
    },

    // ------------------------------------------------------------- rodadas
    setPhase(p, dur) {
      this.phase = p; this.phaseStart = world.time; this.phaseEnd = world.time + dur;
      ev.emit('phase', p, this);
    },
    roundTimeLeft() {
      if (this.phase === 'live') return Math.max(0, this.phaseEnd - world.time);
      if (this.phase === 'freeze') return TIMES.round;
      return 0;
    },
    buyTimeLeft() {
      if (this.mode !== 'competitive') return Infinity;
      if (this.phase === 'freeze') return (this.phaseEnd - world.time) + TIMES.buyWindow;
      if (this.phase === 'live') return Math.max(0, TIMES.buyWindow - (world.time - this.phaseStart));
      return 0;
    },
    beginRound() {
      this.roundNum++;
      world.clear();
      world.bomb.reset();
      intel.reset();
      this.spotted.clear();
      this.lastRoundResult = null;
      const sp = { T: M.shuffle(map.spawns.T.slice()), CT: M.shuffle(map.spawns.CT.slice()) };
      const pistolRound = this.roundNum === 1;
      for (const a of world.agents) {
        const wasAlive = a.alive && this.roundNum > 1;
        if (!wasAlive) {
          // morto: perde arma principal (já caída) e recebe a pistola padrão
          a.inv.primary = null;
          if (!a.inv.secondary || this.roundNum === 1) a.inv.secondary = null;
          a.armor = 0; a.helmet = false; a.inv.kit = false;
          a.inv.grenades.he = a.inv.grenades.flash = a.inv.grenades.smoke = a.inv.grenades.molotov = 0;
        }
        a.inv.bomb = false;
        this.giveDefault(a);
        // munição reabastecida a cada rodada
        if (a.inv.primary) a.inv.primary.refill();
        if (a.inv.secondary) a.inv.secondary.refill();
        const s = sp[a.team].pop() || [24, a.team === 'T' ? 35 : 3];
        a.spawnAt(map.cellX(s[0]) + M.rand(-0.4, 0.4), map.cellZ(s[1]) + M.rand(-0.4, 0.4), a.team === 'T' ? 0 : Math.PI);
        if (a.ai) a.ai.resetRound();
      }
      // portador da bomba
      const ts = world.agents.filter(a => a.team === 'T');
      if (ts.length) {
        const carrier = this.player && this.player.team === 'T' && Math.random() < 0.5 ? this.player : M.pick(ts);
        carrier.inv.bomb = true;
        world.bomb.carrier = carrier; world.bomb.setState('carried', world.time);
        ev.emit('bomb:carrier', carrier);
      }
      this.setPhase('freeze', TIMES.freeze);
      // compras dos bots (na fase de congelamento, dentro da zona de compra)
      for (const t of ['T', 'CT']) {
        const team = world.agents.filter(a => a.team === t);
        const avg = team.reduce((s, a) => s + a.money, 0) / Math.max(1, team.length);
        for (const a of team) if (a.isBot) MP.botBuy(a, avg, pistolRound);
      }
      ev.emit('round:start', this.roundNum, this);
    },
    endRound(winner, reason) {
      if (this.phase !== 'live') return;
      const loser = winner === 'T' ? 'CT' : 'T';
      this.score[winner]++;
      this.lossStreak[winner] = 0;
      const lossBonus = Math.min(ECON.lossMax, ECON.lossBase + ECON.lossStep * this.lossStreak[loser]);
      this.lossStreak[loser] = Math.min(4, this.lossStreak[loser] + 1);
      const winReward = reason === 'bomb' ? ECON.winBomb : reason === 'defuse' ? ECON.winDefuse : reason === 'time' ? ECON.winTime : ECON.winElim;
      for (const a of world.agents) {
        if (a.team === winner) this.addMoney(a, winReward);
        else {
          // T que sobrevive ao tempo esgotado não recebe bônus de derrota (regra clássica)
          let bonus = lossBonus;
          if (a.team === 'T' && reason === 'time' && a.alive) bonus = 0;
          if (a.team === 'T' && world.bomb.plantedAt > 0) bonus += ECON.plantTeamBonus;
          this.addMoney(a, bonus);
        }
      }
      // MVP
      let mvp = null;
      for (const a of world.agents) if (a.team === winner && (!mvp || a.roundKills * 100 + a.roundDamage > mvp.roundKills * 100 + mvp.roundDamage)) mvp = a;
      if (reason === 'defuse' && world.bomb.defuser) mvp = world.bomb.defuser;
      if (reason === 'bomb' && world.bomb.planter) mvp = world.bomb.planter;
      if (mvp) mvp.mvps++;
      const res = { winner, reason, round: this.roundNum, mvp: mvp ? mvp.name : null, score: { T: this.score.T, CT: this.score.CT } };
      this.lastRoundResult = res;
      this.roundHistory.push(res);
      for (const a of world.agents) { a.intent.fire = false; a.intent.use = false; }
      if (world.bomb.state === 'planting') world.bomb.setState('carried', world.time);
      const over = this.score[winner] >= this.config.roundsToWin || this.roundNum >= this.config.roundsToWin * 2 - 1;
      this.setPhase('post', TIMES.post);
      ev.emit('round:end', res, this);
      if (over) this.matchOver = true;
    },
    finishMatch() {
      const p = this.player;
      const winner = this.score.T > this.score.CT ? 'T' : this.score.CT > this.score.T ? 'CT' : 'draw';
      const res = { winner, score: { T: this.score.T, CT: this.score.CT }, rounds: this.roundNum, playerTeam: p ? p.team : null, date: Date.now(), difficulty: this.config.difficulty, teamSize: this.config.teamSize };
      if (p) Object.assign(res, { kills: p.kills, deaths: p.deaths, assists: p.assists, hs: p.headshots, dmg: p.damageDealt, shots: p.shotsFired, hits: p.shotsHit, mvps: p.mvps, result: winner === 'draw' ? 'empate' : winner === p.team ? 'vitória' : 'derrota' });
      MP.history.add(res);
      this.setPhase('over', Infinity);
      ev.emit('match:end', res, this);
    },
    addMoney(a, amt) { a.money = M.clamp(Math.round(a.money + amt), 0, ECON.max); },
    onKill(killer, victim, weaponId, hs) {
      if (this.mode === 'training') {
        if (killer === this.player) { this.trainingStats.kills++; if (hs) this.trainingStats.headshots++; }
        victim.respawnAt = world.time + 2.5;
        return;
      }
      if (killer && killer !== victim && killer.team !== victim.team && this.phase === 'live') {
        const def = WEAPONS[weaponId];
        this.addMoney(killer, def && def.kill !== undefined ? def.kill : 300);
      }
      // bomba cai
      if (victim.inv.bomb) {
        victim.inv.bomb = false;
        const b = world.bomb;
        if (b.state === 'planting') b.setState('available', world.time); else b.setState('available', world.time);
        b.carrier = null; b.planter = null; b.pos.copy(victim.pos); b.pos.y = map.groundBelow(b.pos.x - 0.1, b.pos.z - 0.1, b.pos.x + 0.1, b.pos.z + 0.1, victim.pos.y + 0.5);
        b.droppedAt = world.time;
        ev.emit('bomb:dropped', b);
      }
      if (world.bomb.defuser === victim && world.bomb.state === 'defusing') { world.bomb.setState('planted', world.time); world.bomb.defuser = null; }
      intel[victim.team] && intel[victim.team].allyDown.push({ pos: victim.pos.clone(), time: world.time, killerTeam: killer ? killer.team : null });
      if (victim.isBot && Math.random() < 0.6) {
        const near = world.agents.find(a => a.alive && a.team === victim.team && a.isBot && a.pos.dist(victim.pos) < 30);
        if (near) ev.emit('radio', near, victim.name + ' caiu' + ((map.zoneAt(victim.pos.x, victim.pos.z) || {}).name ? ' em ' + map.zoneAt(victim.pos.x, victim.pos.z).name : '') + '!');
      }
    },
    markSpotted(agent, now) { this.spotted.set(agent, now); },
    isSpotted(agent) { const t = this.spotted.get(agent); return t !== undefined && world.time - t < 1.2; },

    // ------------------------------------------------------------- compras
    inBuyZone(a) {
      if (this.mode !== 'competitive') return true;
      const z = map.buyZones[a.team]; const c = map.colOf(a.pos.x), r = map.rowOf(a.pos.z);
      return c >= z.c0 && c <= z.c1 && r >= z.r0 && r <= z.r1;
    },
    canBuyNow(a) {
      if (!a || !a.alive) return { ok: false, reason: 'Você está morto' };
      if (this.mode === 'training' || this.mode === 'free') return { ok: true };
      if (this.mode !== 'competitive' || (this.phase !== 'freeze' && this.phase !== 'live')) return { ok: false, reason: 'Compras indisponíveis agora' };
      if (this.buyTimeLeft() <= 0) return { ok: false, reason: 'Tempo de compra encerrado' };
      if (!this.inBuyZone(a)) return { ok: false, reason: 'Fora da zona de compra' };
      return { ok: true };
    },
    itemInfo(id) { return WEAPONS[id] || GEAR[id] || null; },
    /** Verifica se `a` pode comprar o item; retorna {ok, reason}. */
    checkBuy(a, id) {
      const can = this.canBuyNow(a); if (!can.ok) return can;
      const item = this.itemInfo(id); if (!item) return { ok: false, reason: 'Item inválido' };
      if (item.team && item.team !== a.team) return { ok: false, reason: 'Indisponível para sua equipe' };
      if (id === 'bomb' || id === 'knife') return { ok: false, reason: 'Não comprável' };
      const free = this.mode !== 'competitive';
      if (!free && a.money < item.cost) return { ok: false, reason: 'Dinheiro insuficiente' };
      if (WEAPONS[id]) {
        const def = WEAPONS[id];
        if (def.slot === 'grenade') {
          const g = a.inv.grenades; const total = g.he + g.flash + g.smoke + g.molotov;
          if (g[def.gtype] >= def.max) return { ok: false, reason: 'Limite deste tipo atingido' };
          if (total >= 4) return { ok: false, reason: 'Limite de 4 granadas' };
        } else {
          const cur = a.weaponIn(def.slot);
          if (cur && cur.id === id) return { ok: false, reason: 'Você já possui esta arma' };
        }
      } else if (id === 'vest') { if (a.armor >= 100) return { ok: false, reason: 'Colete já completo' }; }
      else if (id === 'vesthelm') { if (a.armor >= 100 && a.helmet) return { ok: false, reason: 'Já equipado' }; }
      else if (id === 'kit') { if (a.inv.kit) return { ok: false, reason: 'Você já possui o kit' }; }
      return { ok: true, cost: item.cost };
    },
    buy(a, id, force) {
      const chk = force ? { ok: true } : this.checkBuy(a, id);
      if (!chk.ok) { if (a.isPlayer) ev.emit('buy:fail', a, id, chk.reason); return false; }
      const item = this.itemInfo(id);
      let cost = item.cost;
      if (id === 'vesthelm' && a.armor >= 100 && !a.helmet) cost = 350; // só o capacete
      if (this.mode === 'competitive' && !force) {
        if (a.money < cost) { if (a.isPlayer) ev.emit('buy:fail', a, id, 'Dinheiro insuficiente'); return false; }
        a.money -= cost;
      }
      if (WEAPONS[id]) {
        const def = WEAPONS[id];
        if (def.slot === 'grenade') { a.inv.grenades[def.gtype]++; if (def.gtype === 'molotov') a.inv.grenadeIds.molotov = id; }
        else {
          const { old } = a.giveWeapon(id, world.time);
          if (old && this.mode === 'competitive') {
            const dp = a.pos.clone(); dp.y += 1;
            world.dropWeapon(old, dp, MP.math.dirFromAngles(a.yaw, 0.3).scale(2));
          }
        }
      } else if (id === 'vest') { a.armor = 100; }
      else if (id === 'vesthelm') { a.armor = 100; a.helmet = true; }
      else if (id === 'kit') { a.inv.kit = true; }
      ev.emit('buy', a, id);
      return true;
    },

    // ------------------------------------------------------------- atualização
    update(dt) {
      if (this.mode === 'idle' || this.paused) return;
      const now = world.time + dt;
      const frozen = this.phase === 'freeze';
      // IA antes da física
      for (const a of world.agents) if (a.ai) a.ai.update(dt, now, this.phase);
      world.update(dt);
      for (const a of world.agents) {
        const busy = a === world.bomb.planter && world.bomb.state === 'planting' || a === world.bomb.defuser && world.bomb.state === 'defusing';
        a.update(dt, now, frozen || this.phase === 'over' || busy);
        if (a.alive && this.phase !== 'post' && this.phase !== 'over' && !frozen) {
          if (a.intent.fire) a.tryFire(now);
        }
      }
      if (this.phase === 'live' || this.phase === 'post') this.updateBomb(now);
      this.updatePickups(now);
      if (this.mode === 'competitive') this.updateRound(now);
      else if (this.mode === 'training') this.updateTraining(now);
    },
    updateRound(now) {
      if (this.phase === 'freeze' && now >= this.phaseEnd) { this.setPhase('live', TIMES.round); ev.emit('round:live', this); }
      else if (this.phase === 'live') {
        const b = world.bomb;
        const tAlive = world.alive('T'), ctAlive = world.alive('CT');
        if (ctAlive === 0 && b.state !== 'defused') return this.endRound('T', 'elim');
        if (tAlive === 0 && !b.isPlanted && b.state !== 'detonated') return this.endRound('CT', 'elim');
        if (now >= this.phaseEnd && !b.isPlanted) return this.endRound('CT', 'time');
      } else if (this.phase === 'post' && now >= this.phaseEnd) {
        if (this.matchOver) { this.matchOver = false; this.finishMatch(); }
        else this.beginRound();
      }
    },
    updateTraining(now) {
      for (const a of world.agents) {
        if (a.isBot && !a.alive && a.respawnAt && now >= a.respawnAt) {
          const s = [[23, 16], [21, 13], [26, 14], [22, 20], [25, 18], [24, 12], [21, 22], [26, 20]][M.randInt(0, 7)];
          a.spawnAt(map.cellX(s[0]) + M.rand(-0.5, 0.5), map.cellZ(s[1]), Math.PI);
          if (!a.inv.secondary) a.inv.secondary = new MP.WeaponState('viper');
          a.ai.anchorPos = null; a.respawnAt = 0;
          ev.emit('agent:respawn', a);
        }
      }
      const p = this.player;
      if (p && !p.alive && now - p.deathTime > 3) { p.spawnAt(map.cellX(23.5), map.cellZ(28), 0); this.giveDefault(p); p.armor = 100; p.helmet = true; ev.emit('agent:respawn', p); }
      if (p) { this.trainingStats.shots = p.shotsFired; this.trainingStats.hits = p.shotsHit; }
    },
    updateBomb(now) {
      const b = world.bomb;
      if (this.mode !== 'competitive') return;
      // coleta da bomba caída
      if (b.state === 'available' && this.phase === 'live') {
        for (const a of world.agents) {
          if (!a.alive || a.team !== 'T' || now - b.droppedAt < 0.8) continue;
          if (a.pos.distXZ(b.pos) < 1.1 && Math.abs(a.pos.y - b.pos.y) < 1.5) {
            a.inv.bomb = true; b.carrier = a; b.setState('carried', now);
            ev.emit('bomb:pickup', a); break;
          }
        }
      }
      // plantio
      if (b.state === 'carried' && this.phase === 'live') {
        const a = b.carrier;
        if (a && a.alive && a.intent.use && a.onGround) {
          const site = map.inPlantZone(a.pos.x, a.pos.z);
          if (site) {
            if (a.active !== 'bomb') a.switchTo('bomb', null, now);
            b.planter = a; b.site = site; b.plantStart = now; b.plantEnd = now + MP.PLANT_TIME;
            b.setState('planting', now);
            ev.emit('bomb:plantStart', a, site);
          } else if (a.isPlayer && !a._plantWarned) { a._plantWarned = true; ev.emit('hint', 'Vá até a área de bomba A ou B para plantar.'); }
        }
        if (a && !a.intent.use) a._plantWarned = false;
      } else if (b.state === 'planting') {
        const a = b.planter;
        if (!a || !a.alive) { /* tratado em onKill */ }
        else if (!a.intent.use || this.phase !== 'live') { b.setState('carried', now); b.planter = null; ev.emit('bomb:plantAbort', a); }
        else if (now >= b.plantEnd) {
          a.inv.bomb = false; b.carrier = null;
          b.pos.set(a.pos.x, a.pos.y, a.pos.z);
          b.plantedAt = now; b.explodeAt = now + MP.BOMB_TIMER; b.nextBeep = now;
          b.setState('planted', now);
          this.addMoney(a, ECON.plant);
          a.switchToBest(now);
          ev.emit('bomb:planted', b, a);
          world.emitNoise(b.pos, 200, a, 'bomb');
        }
      }
      if (b.isPlanted) {
        // bipes acelerando
        if (now >= b.nextBeep) {
          const left = b.explodeAt - now;
          ev.emit('bomb:beep', b, left);
          b.nextBeep = now + M.clamp(left / 40, 0.12, 1.0);
        }
        if (now >= b.explodeAt) {
          b.setState('detonated', now);
          b.defuser = null;
          ev.emit('explosion', b.pos.clone().add(new V3(0, 0.5, 0)), 3);
          ev.emit('bomb:exploded', b);
          // dano letal em área
          for (const a of world.agents) {
            if (!a.alive) continue;
            const d = a.pos.dist(b.pos);
            if (d < 22) a.applyDamage(Math.round(500 * Math.pow(1 - d / 22, 1.6) + (d < 10 ? 100 : 0)), null, 'bomb', 'chest', b.pos, now);
          }
          if (this.phase === 'live') this.endRound('T', 'bomb');
          return;
        }
        if (b.state === 'planted' && this.phase === 'live') {
          for (const a of world.agents) {
            if (!a.alive || a.team !== 'CT' || !a.intent.use) continue;
            if (a.pos.distXZ(b.pos) < 1.6 && Math.abs(a.pos.y - b.pos.y) < 1.4 && a.onGround) {
              b.defuser = a; b.defuseStart = now; b.defuseEnd = now + (a.inv.kit ? MP.DEFUSE_KIT_TIME : MP.DEFUSE_TIME);
              b.setState('defusing', now);
              ev.emit('bomb:defuseStart', a, a.inv.kit);
              break;
            }
          }
        } else if (b.state === 'defusing') {
          const a = b.defuser;
          if (!a || !a.alive || !a.intent.use || a.pos.distXZ(b.pos) > 1.8) { b.setState('planted', now); b.defuser = null; ev.emit('bomb:defuseAbort', a); }
          else if (now >= b.defuseEnd) {
            b.setState('defused', now);
            this.addMoney(a, ECON.defuse);
            ev.emit('bomb:defused', b, a);
            if (this.phase === 'live') this.endRound('CT', 'defuse');
          }
        }
      }
    },
    /** Coleta automática (slot vazio) e troca com E (interação). */
    updatePickups(now) {
      if (!world.drops.length) return;
      for (const a of world.agents) {
        if (!a.alive) continue;
        for (const d of world.drops) {
          if (now - d.born < 0.9 || a.pos.distXZ(d.pos) > 1.3 || Math.abs(a.pos.y - d.pos.y) > 1.6) continue;
          const slot = d.ws.def.slot;
          const cur = a.weaponIn(slot);
          const swap = a.isPlayer && a.intent.use && !a._useLatch && cur && world.bomb.state !== 'planted';
          if (!cur || swap) {
            if (a.isPlayer && a.intent.use) a._useLatch = true;
            world.removeDrop(d);
            if (cur) world.dropWeapon(cur, a.pos.clone().add(new V3(0, 1, 0)), M.dirFromAngles(a.yaw, 0.2).scale(2));
            if (slot === 'primary') a.inv.primary = d.ws; else a.inv.secondary = d.ws;
            if (!cur || a.active === slot) { a.active = '__'; a.switchTo(slot, null, now); }
            ev.emit('pickup', a, d.ws);
            break;
          }
        }
        if (a.isPlayer && !a.intent.use) a._useLatch = false;
      }
    },
    /** Item interativo mais próximo do jogador (para dica de "E"). */
    interactionHint(a) {
      if (!a || !a.alive) return null;
      const b = world.bomb;
      if (this.mode === 'competitive') {
        if (a.team === 'T' && a.inv.bomb && map.inPlantZone(a.pos.x, a.pos.z) && (b.state === 'carried' || b.state === 'planting')) return { kind: 'plant', text: 'Segure E para plantar a bomba' };
        if (a.team === 'CT' && b.isPlanted && a.pos.distXZ(b.pos) < 1.6) return { kind: 'defuse', text: 'Segure E para desarmar' + (a.inv.kit ? ' (kit)' : '') };
      }
      for (const d of world.drops) if (a.pos.distXZ(d.pos) < 1.3) return { kind: 'pickup', text: 'E para pegar ' + d.ws.def.name };
      return null;
    }
  };
})(typeof window !== 'undefined' ? window : globalThis);
