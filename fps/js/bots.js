/* Mirage Protocol — inteligência artificial dos bots.
 * Máquina de estados com percepção (visão por FOV + raycast + fumaça, audição por eventos de ruído),
 * memória de última posição conhecida, navegação A* na grade, combate com tempo de reação, controle
 * de rajada, compensação parcial de recuo, cobertura, recuo, granadas e cooperação por quadro de equipe. */
(function (root) {
  'use strict';
  const MP = root.MP;
  const { V3, math: M, map, world, WEAPONS } = MP;
  const ev = MP.events;
  const DEG = Math.PI / 180;

  // Parâmetros por dificuldade: todos afetam comportamento real
  const DIFF = {
    easy: { reaction: [0.6, 0.95], turn: 200 * DEG, aimErr: 4.0 * DEG, track: 1.6, headChance: 0.08, burst: [5, 9], burstPause: [0.15, 0.3],
      recoilComp: 0.15, fov: 100 * DEG, viewDist: 42, hearing: 0.55, strafe: 0.1, crouchSpray: 0.1, cover: 0.3, grenade: 0.15,
      think: 0.55, perceive: 0.22, fireTol: 1.9, retreatHp: 15, prefire: 0, memory: 3, regroup: false, counterStrafe: 0.2 },
    normal: { reaction: [0.3, 0.5], turn: 360 * DEG, aimErr: 2.2 * DEG, track: 3.0, headChance: 0.3, burst: [3, 6], burstPause: [0.22, 0.4],
      recoilComp: 0.55, fov: 120 * DEG, viewDist: 62, hearing: 0.85, strafe: 0.45, crouchSpray: 0.35, cover: 0.7, grenade: 0.5,
      think: 0.35, perceive: 0.14, fireTol: 1.3, retreatHp: 30, prefire: 0.3, memory: 5, regroup: true, counterStrafe: 0.6 },
    hard: { reaction: [0.16, 0.27], turn: 620 * DEG, aimErr: 1.1 * DEG, track: 5.0, headChance: 0.55, burst: [2, 4], burstPause: [0.25, 0.42],
      recoilComp: 0.85, fov: 140 * DEG, viewDist: 90, hearing: 1.0, strafe: 0.8, crouchSpray: 0.5, cover: 0.95, grenade: 0.85,
      think: 0.22, perceive: 0.09, fireTol: 1.05, retreatHp: 35, prefire: 0.6, memory: 7, regroup: true, counterStrafe: 0.95 }
  };
  MP.BOT_DIFFICULTY = DIFF;

  const _a = new V3(), _b = new V3(), _c = new V3(), _d = new V3();

  // Quadro de informações por equipe (comunicação interna)
  const intel = MP.intel = {
    T: null, CT: null,
    reset() { for (const t of ['T', 'CT']) this[t] = { sightings: [], allyDown: [], radioAt: 0, smokesUsed: {}, rotateTo: null, plan: null }; },
    report(team, pos, enemy, zone) {
      const I = this[team];
      I.sightings.push({ pos: pos.clone(), enemy, time: world.time, zone: zone ? zone.id : null });
      if (I.sightings.length > 30) I.sightings.shift();
    },
    recentCount(team, zoneIds, window) {
      const I = this[team]; const seen = new Set();
      for (const s of I.sightings) if (world.time - s.time < window && zoneIds.indexOf(s.zone) >= 0) seen.add(s.enemy);
      return seen.size;
    },
    latestNear(team, pos, radius, window) {
      const I = this[team]; let best = null;
      for (let i = I.sightings.length - 1; i >= 0; i--) {
        const s = I.sightings[i]; if (world.time - s.time > window) break;
        if (s.pos.distXZ(pos) < radius) { best = s; break; }
      }
      return best;
    }
  };
  intel.reset();

  function radio(agent, msg) {
    const I = intel[agent.team];
    if (world.time - I.radioAt < 2.5) return;
    I.radioAt = world.time;
    ev.emit('radio', agent, msg);
  }

  const SITE_ZONES = { A: ['siteA', 'along', 'cat'], B: ['siteB', 'btun', 'bshort'] };

  class BotBrain {
    constructor(agent) {
      this.agent = agent; agent.ai = this; this._look = new V3();
      this.setDifficulty(agent.difficulty);
      this.resetRound();
    }
    setDifficulty(k) { this.dk = DIFF[k] ? k : 'normal'; this.d = DIFF[this.dk]; }
    resetRound() {
      this.state = 'idle'; this.stateTime = 0;
      this.path = null; this.pathIdx = 0; this.goal = null; this.goalKey = '';
      this.target = null; this.targetVisible = false; this.visibleSince = 0; this.reactAt = 0; this.lastSeen = -100;
      this.lastKnown = new V3(); this.hasLastKnown = false;
      this.aimYaw = this.agent.yaw; this.aimPitch = 0; this.errY = 0; this.errP = 0;
      this.burstCount = 0; this.burstPauseUntil = 0; this.burstLen = 3;
      this.nextPerceive = Math.random() * 0.2; this.nextThink = Math.random() * 0.3;
      this.noiseCursor = world.time;
      this.investigatePos = null; this.investigateUntil = 0;
      this.stuckCheckAt = 0; this.stuckPos = new V3(); this.stuckCount = 0;
      this.strafeDir = 1; this.strafeUntil = 0; this.crouchUntil = 0;
      this.coverPos = null; this.fleeUntil = 0; this.fleeDir = new V3();
      this.role = null; this.route = null; this.routeStep = 0; this.site = null;
      this.holdSpot = null; this.holdLook = null; this.holdSince = 0; this.patrolAt = 0;
      this.regroupUntil = 0; this.plantSpot = null; this.waitingForRegroup = false; this.fellBack = false; this.siteSpot = null; this.guardSpot = null;
      this.throwPlan = null; this.thrownSmoke = false; this.thrownFlash = false; this.lastNadeAt = -100;
      this.speedCap = 0; this.lookAt = null; this.walk = false;
      this.dummy = this.dummy || false;
      this.pendingRetreat = false; this.lastHp = 100;
    }
    setState(s) { if (this.state !== s) { this.state = s; this.stateTime = 0; } }

    // ============================================================ ciclo principal
    update(dt, now, phase) {
      const a = this.agent, it = a.intent;
      if (!a.alive) { this.setState('dead'); it.fire = false; it.use = false; it.f = it.r = 0; return; }
      this.stateTime += dt;
      it.fire = false; it.jump = false; it.walk = false; it.use = false; it.firePressed = false;
      if (phase === 'freeze') { this.setState('buy'); it.f = it.r = 0; this.lookAround(dt, now); this.applyAim(dt); return; }
      if (phase === 'post' || phase === 'over') { it.f = it.r = 0; it.crouch = false; this.applyAim(dt); return; }
      if (this.dummy) { this.updateDummy(dt, now); return; }

      if (now >= this.nextPerceive) { this.perceive(now); this.nextPerceive = now + this.d.perceive * M.rand(0.8, 1.2); }
      if (now >= this.nextThink) { this.think(now); this.nextThink = now + this.d.think * M.rand(0.8, 1.2); }
      this.execute(dt, now);
      this.applyAim(dt);
      this.checkStuck(now);
      this.lastHp = a.hp;
    }

    // ============================================================ percepção
    perceive(now) {
      const a = this.agent, d = this.d;
      const eye = a.eyePos(_a);
      const blind = a.isFlashed(now) && a.flashAmount(now) > 0.35;
      let best = null, bestScore = 1e9;
      const fwdYaw = this.aimYaw;
      for (const e of world.agents) {
        if (!e.alive || e.team === a.team) continue;
        if (blind) break;
        const dist = e.pos.dist(a.pos);
        if (dist > d.viewDist) continue;
        const yawTo = M.yawTo(a.pos, e.pos);
        const off = Math.abs(M.wrapAngle(yawTo - fwdYaw));
        const close = dist < 2.2; // sente quem encosta
        if (off > d.fov / 2 && !close) continue;
        // dois raios: cabeça e peito
        let vis = world.losClear(eye, e.headPos(_b));
        if (!vis) vis = world.losClear(eye, e.chestPos(_b));
        if (!vis && e.crouchAmt < 0.5) vis = world.losClear(eye, _b.set(e.pos.x, e.pos.y + 0.6, e.pos.z));
        if (!vis) continue;
        // agachado e parado ao longe é mais difícil de notar
        let score = dist + off * 20 - (e === this.target ? 15 : 0);
        if (e.recentlyHitBy === a) score -= 5;
        if (score < bestScore) { bestScore = score; best = e; }
      }
      if (best) {
        if (best !== this.target || !this.targetVisible) {
          // novo alvo ou reaparecimento: tempo de reação
          const fresh = best !== this.target || now - this.lastSeen > 1.0;
          if (fresh) {
            let rt = M.rand(d.reaction[0], d.reaction[1]);
            if (this.hasLastKnown && best.pos.dist(this.lastKnown) < 4 && now - this.lastSeen < 3) rt *= 0.5; // esperava por ele
            // alvo parado/agachado ao longe é notado mais tarde; correndo chama atenção
            const bd = best.pos.dist(a.pos);
            if (bd > 15 && best.speedNow < 1) rt += best.crouchAmt > 0.5 ? 0.2 : 0.1;
            if (best.speedNow > 4) rt *= 0.9;
            // segurando um ângulo: mira já posicionada reage mais rápido
            if (this.state === 'hold' && Math.abs(M.wrapAngle(M.yawTo(a.pos, best.pos) - this.aimYaw)) < 15 * DEG) { rt *= 0.6; this.errY *= 0.5; }
            this.reactAt = now + rt;
            this.errY = (Math.random() - 0.5) * 2 * d.aimErr * (1 + best.pos.dist(a.pos) / 40);
            this.errP = (Math.random() - 0.5) * d.aimErr;
            this.burstCount = 0;
          }
          if (best !== this.target) {
            this.target = best;
            const zone = map.zoneAt(best.pos.x, best.pos.z);
            intel.report(a.team, best.pos, best, zone);
            radio(a, 'Inimigo avistado' + (zone ? ' em ' + zone.name : '') + '!');
          }
          this.visibleSince = now;
        }
        this.targetVisible = true; this.lastSeen = now;
        this.lastKnown.copy(best.pos); this.hasLastKnown = true;
        MP.game && MP.game.markSpotted && MP.game.markSpotted(best, now);
        if (Math.random() < 0.15) intel.report(a.team, best.pos, best, map.zoneAt(best.pos.x, best.pos.z));
      } else {
        this.targetVisible = false;
        if (this.target && (!this.target.alive || now - this.lastSeen > d.memory)) this.target = null;
      }
      // fui atingido por alguém que não vejo: vira para a origem
      if (a.recentlyHitBy && a.recentlyHitBy.alive && !this.targetVisible && now - a.lastDamageTime < 0.5) {
        const att = a.recentlyHitBy;
        this.investigatePos = att.pos.clone().add(_c.set(M.rand(-2, 2), 0, M.rand(-2, 2)));
        this.investigateUntil = now + 6;
        this.lookAt = att.eyePos(new V3());
      }
      a.recentlyHitBy = null;
      // audição
      for (const n of world.noises) {
        if (n.time <= this.noiseCursor) continue;
        if (!n.source || n.source === a) continue;
        if (n.source.team === a.team && n.kind !== 'explosion') continue;
        const dist = n.pos.dist(a.pos);
        if (dist > n.radius * d.hearing) continue;
        if (this.targetVisible) continue;
        // posição aproximada (sem visão exata)
        const err = dist * 0.12;
        const guess = n.pos.clone().add(_c.set(M.rand(-err, err), 0, M.rand(-err, err)));
        const prio = n.kind === 'shot' ? 3 : n.kind === 'step' ? 2 : 1;
        // passos/tiros ouvidos viram informação de equipe (posição aproximada)
        if (n.source.team !== a.team && (n.kind === 'step' || n.kind === 'shot')) intel.report(a.team, guess, n.source, map.zoneAt(guess.x, guess.z));
        if (!this.investigatePos || prio >= (this.investigatePrio || 0) || now > this.investigateUntil) {
          this.investigatePos = guess; this.investigatePrio = prio; this.investigateUntil = now + (prio === 3 ? 8 : 6);
          if (n.kind === 'step' && Math.random() < 0.3) radio(a, 'Passos ouvidos perto de ' + ((map.zoneAt(guess.x, guess.z) || {}).name || 'mim') + '.');
        }
      }
      this.noiseCursor = world.time;
    }

    // ============================================================ decisão
    think(now) {
      const a = this.agent, d = this.d, g = MP.game, bomb = world.bomb;
      const w = a.weapon;
      // 1. emergências
      if (a.isFlashed(now) && a.flashAmount(now) > 0.35) { this.setState('blind'); return; }
      const danger = this.findDanger();
      if (danger) {
        this.fleeDir.subVectors(a.pos, danger).normalize(); this.fleeDir.y = 0;
        this.fleeUntil = now + 1.2; this.setState('flee'); this.path = null; return;
      }
      if (this.state === 'flee' && now < this.fleeUntil) return;
      if (this.state === 'throw' && this.throwPlan && now < this.throwPlan.at + 1.5 && !(this.targetVisible && now >= this.reactAt)) return;
      if (this.state === 'throw' && a.active === 'grenade') { this.throwPlan = null; a.switchToBest(now); }
      // 2. ações de objetivo críticas
      if (this.state === 'plant' && bomb.state === 'planting' && bomb.planter === a) {
        if (!(this.targetVisible && this.dk === 'hard' && now >= this.reactAt)) return;
      }
      if (this.state === 'defuse' && bomb.state === 'defusing' && bomb.defuser === a) {
        const left = bomb.defuseEnd - now;
        if (!this.targetVisible || left < 1.5 || bomb.explodeAt - now < left + 1.5) return;
      }
      // 3. combate
      if (this.target && this.target.alive && this.targetVisible) {
        // munição
        if (w && w.clip === 0) {
          const sec = a.inv.secondary;
          if (a.active === 'primary' && sec && sec.clip > 0 && a.pos.dist(this.target.pos) < 12 && this.dk !== 'easy') { a.switchTo('secondary', null, now); }
          else if (w.reserve > 0) { this.retreatToCover(now, true); return; }
          else if (a.active === 'primary' && sec && (sec.clip > 0 || sec.reserve > 0)) a.switchTo('secondary', null, now);
          else if (!sec || (sec.clip === 0 && sec.reserve === 0)) a.switchTo('knife', null, now);
        }
        if (a.active === 'grenade' || a.active === 'bomb' || (a.active === 'knife' && a.pos.dist(this.target.pos) > 3)) a.switchToBest(now);
        // desvantagem: recua
        const outnumbered = this.visibleEnemies(now) >= 2 && world.alive(a.team) < world.alive(this.target.team);
        if (Math.random() < d.cover && (a.hp < d.retreatHp && this.target.hp > a.hp || outnumbered && a.hp < 60) && this.state !== 'retreat') {
          if (this.retreatToCover(now, false)) return;
        }
        this.setState('engage');
        return;
      }
      if (this.state === 'retreat' || this.state === 'reload') {
        if (w && w.reloading) return;
        if (this.state === 'retreat' && this.stateTime < 2.5 && this.coverPos && a.pos.distXZ(this.coverPos) > 1) return;
      }
      // 4. recarregar com calma
      if (w && w.def.mag && w.clip < w.def.mag * (this.target ? 0.3 : 0.6) && w.reserve > 0 && !w.reloading && now - this.lastSeen > 1.5) {
        a.startReload(now);
        this.setState('reload'); return;
      }
      if (w && w.reloading && this.state === 'reload') return;
      // troca para melhor arma
      if (a.active !== a.bestSlot() && a.active !== 'grenade' && !(a.active === 'bomb')) a.switchToBest(now);
      // 5. memória do alvo: perseguir/investigar
      if (this.target && this.target.alive && this.hasLastKnown && now - this.lastSeen < d.memory) {
        if (this.considerNade(now, this.lastKnown)) return;
        const hold = (a.team === 'CT' && !bomb.isPlanted) || (a.team === 'T' && bomb.isPlanted);
        const far = a.pos.dist(this.lastKnown) > (hold ? 12 : 18);
        if (hold && (far || this.dk !== 'easy' && now - this.lastSeen < 2.5)) { this.setState('hold'); this.lookAt = this._look.copy(this.lastKnown).add(_c.set(0, 1.5, 0)); if (far) this.target = null; return; }
        if (!far) { this.setState('chase'); return; }
        this.target = null;
      }
      // 6. objetivo de bomba
      if (this.objectiveBomb(now)) return;
      // 7. investigar ruído
      if (this.investigatePos && now < this.investigateUntil) {
        // investiga só o que está perto; ao longe apenas vira o olhar (sem abandonar o plano)
        const dist = a.pos.dist(this.investigatePos);
        // defensor segurando posição não sai para investigar: só ajusta a mira para o ruído
        const limit = (a.team === 'CT' && !bomb.isPlanted) ? (this.state === 'hold' ? 0 : 10) : 20;
        if (dist < limit) { this.setState('investigate'); return; }
        if (dist < 35) this.lookAt = this._look.copy(this.investigatePos).add(_c.set(0, 1.5, 0));
        this.investigatePos = null;
      }
      // 8. companheiros mortos por perto
      const I = intel[a.team];
      for (const dn of I.allyDown) {
        if (now - dn.time < 4 && dn.pos.dist(a.pos) < 25 && !dn.handled) {
          dn.handled = true;
          this.investigatePos = dn.pos.clone(); this.investigatePrio = 2; this.investigateUntil = now + 6;
          this.walk = true; this.setState('investigate'); return;
        }
      }
      // 9. papel de equipe
      if (a.team === 'T') this.thinkT(now); else this.thinkCT(now);
    }

    objectiveBomb(now) {
      const a = this.agent, bomb = world.bomb;
      if (a.team === 'T') {
        if (bomb.state === 'available' && (!a.inv.bomb)) {
          // aliado mais próximo busca a bomba
          let nearest = null, nd = 1e9;
          for (const o of world.agents) if (o.alive && o.team === 'T' && o.isBot) { const dd = o.pos.dist(bomb.pos); if (dd < nd) { nd = dd; nearest = o; } }
          if (nearest === a) { this.goalKey !== 'bombpick' && this.goTo(bomb.pos, 'bombpick'); this.setState('objective'); return true; }
        }
        if (bomb.isPlanted) {
          this.setState('guardBomb'); return true;
        }
        return false;
      }
      // CT
      if (bomb.isPlanted) {
        const left = bomb.explodeAt - now;
        const myDefuse = a.inv.kit ? MP.DEFUSE_KIT_TIME : MP.DEFUSE_TIME;
        const dist = a.pos.dist(bomb.pos);
        const eta = dist / 6 + myDefuse;
        if (left < eta - 1 && this.dk === 'hard' && world.alive('T') > 0) { // salvar arma: impossível chegar
          if (this.state !== 'save') { this.setState('save'); this.goTo(map.idxPos(map.nearestWalkable(map.cellX(24), map.cellZ(3))), 'save'); radio(a, 'Sem tempo para desarmar, salvando.'); }
          return true;
        }
        // quem desarma: CT mais próximo
        let nearest = null, nd = 1e9;
        for (const o of world.agents) if (o.alive && o.team === 'CT') { const dd = o.pos.dist(bomb.pos); if (dd < nd) { nd = dd; nearest = o; } }
        if (nearest === a || bomb.defuser === a) { this.setState('defuse'); return true; }
        this.setState('retake'); return true;
      }
      return false;
    }

    thinkT(now) {
      const a = this.agent, g = MP.game, bomb = world.bomb, d = this.d;
      const timeLeft = g ? g.roundTimeLeft() : 100;
      if (!this.site) this.assignTPlan();
      // tempo acabando: corre para o site mais próximo
      if (timeLeft < 30 && !bomb.isPlanted && this.routeStep < (this.route ? this.route.via.length : 0)) this.routeStep = this.route.via.length;
      if (a.inv.bomb) {
        if (this.routeStep >= this.route.via.length) {
          if (!this.plantSpot) this.plantSpot = this.choosePlantSpot(this.site);
          if (a.pos.distXZ(this.plantSpot) < 1.0 && map.inPlantZone(a.pos.x, a.pos.z)) {
            if (a.active !== 'bomb') a.switchTo('bomb', null, now);
            this.setState('plant'); return;
          }
          this.setState('objective'); return;
        }
      }
      // reagrupar antes de executar
      if (this.route && this.routeStep === this.route.via.length - 1 && d.regroup && timeLeft > 40) {
        const me = a.pos.dist(map.idxPos(this.viaIdx(this.routeStep)));
        if (me < 4) {
          if (!this.regroupUntil) this.regroupUntil = now + M.rand(3, 6);
          let near = 0, total = 0;
          for (const o of world.agents) if (o.alive && o.team === 'T' && o.ai && o.ai.site === this.site && o.ai.route) { total++; if (o.ai.routeStep >= o.ai.route.via.length - 1) near++; }
          if (now < this.regroupUntil && near < total) { this.setState('regroup'); return; }
          // executa: utilitária
          if (!this.thrownSmoke && a.inv.grenades.smoke > 0 && !intel.T.smokesUsed[this.site + this.route.name]) {
            const sp = M.pick(map.smokeSpots[this.site]);
            if (this.prepareThrow('smoke', map.idxPos(map.idxOf(map.cellX(sp[0]), map.cellZ(sp[1]))))) { intel.T.smokesUsed[this.site + this.route.name] = true; this.thrownSmoke = true; return; }
          }
          if (!this.thrownFlash && a.inv.grenades.flash > 0 && Math.random() < d.grenade) {
            this.thrownFlash = true;
            const z = map.plantZones[this.site];
            if (this.prepareThrow('flash', new V3(map.cellX((z.c0 + z.c1) / 2), 2, map.cellZ((z.r0 + z.r1) / 2)))) return;
          }
          this.routeStep++;
          radio(a, 'Executando ' + this.site + '! Vai, vai, vai!');
        }
      }
      this.setState('objective');
    }
    assignTPlan() {
      const a = this.agent; const I = intel.T;
      if (!I.plan) {
        const site = Math.random() < 0.5 ? 'A' : 'B';
        I.plan = { site, split: Math.random() < 0.45, counter: 0 };
        ev.emit('tplan', I.plan);
      }
      const plan = I.plan; this.site = plan.site;
      const routes = map.routes[plan.site];
      const k = plan.split ? (plan.counter++ % routes.length) : (a.inv.bomb ? 0 : (Math.random() < 0.25 ? 1 : 0));
      this.route = routes[k];
      this.routeStep = 0;
    }
    viaIdx(step) {
      const v = this.route.via[Math.min(step, this.route.via.length - 1)];
      return map.nearestWalkable(map.cellX(v[0]), map.cellZ(v[1]));
    }
    choosePlantSpot(site) {
      const cells = map.cellsInRect(map.plantZones[site]);
      // prefere células com cobertura adjacente
      const good = cells.filter(i => {
        const c = i % map.W, r = (i / map.W) | 0;
        for (const [dc, dr] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { const n = map.cellAt(c + dc, r + dr); if (n && n.spans.length && n.top >= 1) return true; }
        return false;
      });
      return map.idxPos(M.pick(good.length ? good : cells));
    }

    thinkCT(now) {
      const a = this.agent, d = this.d;
      if (!this.holdSpot) this.assignCTHold();
      // rotação por informação da equipe
      const I = intel.CT;
      for (const s of ['A', 'B']) {
        const n = intel.recentCount('CT', SITE_ZONES[s], 8);
        let downs = 0;
        for (const dn of I.allyDown) { const z = map.zoneAt(dn.pos.x, dn.pos.z); if (z && SITE_ZONES[s].indexOf(z.id) >= 0 && now - dn.time < 10) downs++; }
        if ((n >= 2 || (n >= 1 && downs >= 1)) && this.role !== s && (!I.rotateTo || I.rotateTo.site !== s || now - I.rotateTo.time > 10)) {
          I.rotateTo = { site: s, time: now }; radio(a, 'Rotacionando para ' + s + '!');
        }
        // defensor sozinho contra muitos: recua para esperar reforço (retomada)
        if (this.role === s && n >= 3 && this.state === 'hold' && !this.fellBack) {
          let mates = 0;
          for (const o of world.agents) if (o !== a && o.alive && o.team === 'CT' && o.pos.dist(a.pos) < 15) mates++;
          if (mates === 0 && Math.random() < d.cover) {
            this.fellBack = true; this.setHold(map.holds[s][3]); this.setState('objective');
            radio(a, 'Muitos no ' + s + ', recuando!'); return;
          }
        }
      }
      if (I.rotateTo && now - I.rotateTo.time < 15 && this.role !== I.rotateTo.site && this.role !== 'rotating') {
        // nem todos rotacionam: o primeiro defensor de cada site fica (exceto fácil)
        const keep = this.dk !== 'easy' && this.anchor;
        if (!keep && (this.role === 'mid' || Math.random() < 0.85)) {
          this.role = I.rotateTo.site; this.anchor = false;
          const spots = map.holds[this.role];
          const h = M.pick(spots); this.setHold(h);
        }
      }
      // patrulha ocasional
      if (this.state === 'hold' && now > this.patrolAt && Math.random() < 0.25) {
        this.patrolAt = now + M.rand(15, 30);
        const h = M.pick(map.holds[this.role] || map.holds.mid); this.setHold(h); this.setState('patrol'); return;
      }
      if (this.holdSpot && a.pos.distXZ(this.holdSpot) < 1.2) { this.setState('hold'); if (!this.holdSince) this.holdSince = now; }
      else this.setState(this.state === 'patrol' ? 'patrol' : 'objective');
    }
    assignCTHold() {
      const a = this.agent;
      const cts = world.agents.filter(o => o.team === 'CT' && o.ai);
      const idx = cts.indexOf(a);
      const order = ['A', 'B', 'mid', 'B', 'A', 'mid'];
      this.role = order[idx % order.length];
      // primeiro de cada site é âncora
      this.anchor = order.indexOf(this.role) === idx;
      const spots = map.holds[this.role];
      const sameRole = cts.slice(0, idx).filter(o => o.ai && o.ai.role === this.role).length;
      this.setHold(spots[sameRole % spots.length]);
      this.patrolAt = world.time + M.rand(20, 40);
    }
    setHold(h) {
      const i = map.nearestWalkable(map.cellX(h.c), map.cellZ(h.r));
      this.holdSpot = map.idxPos(i);
      this.holdLook = new V3(map.cellX(h.look[0]), 1.5, map.cellZ(h.look[1]));
      this.holdSince = 0; this.goalKey = '';
    }

    retreatToCover(now, reload) {
      const a = this.agent;
      const threat = this.target ? this.lastKnown : null;
      const cp = threat ? this.findCover(threat) : null;
      if (cp) {
        this.coverPos = cp; this.goTo(cp, 'cover'); this.setState('retreat');
        if (reload) this.pendingReload = true;
        if (Math.random() < 0.5) radio(a, reload ? 'Recarregando, me cubram!' : 'Recuando, estou ferido!');
        return true;
      }
      if (reload) { a.startReload(now); this.setState('reload'); return true; }
      return false;
    }
    findCover(threat) {
      const a = this.agent;
      const te = _c.set(threat.x, threat.y + 1.6, threat.z);
      const c0 = map.colOf(a.pos.x), r0 = map.rowOf(a.pos.z);
      let best = null, bs = 1e9;
      const cand = [];
      for (let dr = -6; dr <= 6; dr++) for (let dc = -6; dc <= 6; dc++) {
        const c = c0 + dc, r = r0 + dr; if (c < 0 || r < 0 || c >= map.W || r >= map.H) continue;
        const i = r * map.W + c; if (!map.walkable[i]) continue;
        cand.push(i);
      }
      M.shuffle(cand);
      const p = new V3();
      for (let k = 0; k < Math.min(36, cand.length); k++) {
        map.idxPos(cand[k], p);
        const dist = p.distXZ(a.pos);
        if (dist > 13) continue;
        _d.set(p.x, p.y + 1.15, p.z);
        if (map.segmentClear(te, _d)) continue; // exposto
        const away = p.distXZ(threat) < a.pos.distXZ(threat) ? 6 : 0;
        const s = dist + away;
        if (s < bs) { bs = s; best = p.clone(); }
      }
      return best;
    }
    findDanger() {
      const a = this.agent;
      for (const g of world.grenades) {
        if (g.type !== 'he' && g.type !== 'molotov') continue;
        if (g.team === a.team && g.owner !== a && !world.friendlyFire) continue;
        if (g.pos.dist(a.pos) < 7 && world.time - g.born > 0.25 && Math.random() < this.d.cover) return g.pos;
      }
      const f = world.inFire(a.pos, 0.5); if (f) return f.pos;
      return null;
    }
    visibleEnemies(now) {
      let n = 0; const eye = this.agent.eyePos(new V3());
      for (const e of world.agents) if (e.alive && e.team !== this.agent.team && e.pos.dist(this.agent.pos) < this.d.viewDist && world.losClear(eye, e.chestPos(_b))) n++;
      return n;
    }

    // ============================================================ granadas
    considerNade(now, at) {
      const a = this.agent, d = this.d;
      if (now - this.lastNadeAt < 6 || Math.random() > d.grenade * 0.5) return false;
      const dist = a.pos.dist(at);
      if (dist < 6 || dist > 24) return false;
      const type = a.inv.grenades.he > 0 ? 'he' : a.inv.grenades.molotov > 0 ? 'molotov' : null;
      if (!type) return false;
      return this.prepareThrow(type, at);
    }
    prepareThrow(type, target) {
      const a = this.agent;
      if (a.inv.grenades[type] <= 0) return false;
      const eye = a.eyePos(new V3());
      const sol = solveThrow(eye, target, 17);
      if (!sol) return false;
      // checa se o arco inicial não bate de cara numa parede
      const dir = M.dirFromAngles(sol.yaw, sol.pitch);
      const h = map.raycast(eye, dir, 3);
      if (h) return false;
      this.throwPlan = { type, yaw: sol.yaw, pitch: sol.pitch - 0.06, at: world.time + 0.35 };
      a.switchTo('grenade', type, world.time);
      this.lastNadeAt = world.time;
      this.setState('throw');
      return true;
    }

    // ============================================================ execução
    execute(dt, now) {
      const a = this.agent, it = a.intent, d = this.d, bomb = world.bomb;
      let moveTo = null; this.speedCap = 0; this.walk = false;
      it.crouch = false;
      a.ai.speedCap = 0;
      switch (this.state) {
        case 'blind': {
          // cego: recua para trás e não atira
          it.f = -0.6; it.r = Math.sin(now * 3) * 0.6;
          this.aimYaw += dt * 1.5 * this.strafeDir;
          return;
        }
        case 'flee': {
          const tgt = _c.copy(a.pos).addScaled(this.fleeDir, 4);
          this.moveDirect(tgt);
          this.faceMove(dt);
          return;
        }
        case 'throw': {
          it.f = it.r = 0;
          const p = this.throwPlan;
          if (!p || a.active !== 'grenade') { this.throwPlan = null; this.setState('idle'); this.nextThink = now; return; }
          this.desiredYaw = p.yaw; this.desiredPitch = p.pitch;
          this.aimYaw = this.turnToward(this.aimYaw, p.yaw, d.turn * dt);
          this.aimPitch = this.turnToward(this.aimPitch, p.pitch, d.turn * dt);
          if (now >= p.at && now >= a.drawEnd && Math.abs(M.wrapAngle(this.aimYaw - p.yaw)) < 0.05) {
            a.yaw = this.aimYaw; a.pitch = this.aimPitch;
            it.fire = true; a.tryFire(now);
            this.throwPlan = null; this.setState('idle'); this.nextThink = now + 0.3;
            radio(a, { he: 'Granada!', flash: 'Lançando flash!', smoke: 'Fumaça saindo!', molotov: 'Fogo saindo!' }[p.type]);
          }
          return;
        }
        case 'engage': return this.executeEngage(dt, now);
        case 'retreat': {
          if (this.coverPos) moveTo = this.coverPos;
          if (a.weapon && this.pendingReload && (a.pos.distXZ(this.coverPos || a.pos) < 1.5 || this.stateTime > 2)) { a.startReload(now); this.pendingReload = false; }
          if (this.targetVisible && now >= this.reactAt && a.weapon && a.weapon.clip > 0) { this.fireControl(now, true); }
          break;
        }
        case 'reload': {
          it.f = it.r = 0;
          if (this.hasLastKnown) this.lookAt = this._look.copy(this.lastKnown).add(_d.set(0, 1.5, 0));
          it.crouch = this.dk !== 'easy';
          break;
        }
        case 'chase': {
          moveTo = this.lastKnown; this.walk = this.dk === 'hard' && a.pos.dist(this.lastKnown) < 15;
          this.lookAt = this._look.copy(this.lastKnown).add(_d.set(0, 1.5, 0));
          if (a.pos.distXZ(this.lastKnown) < 1.5) { this.hasLastKnown = false; this.target = null; }
          break;
        }
        case 'investigate': {
          moveTo = this.investigatePos; this.walk = this.dk !== 'easy';
          if (moveTo) this.lookAt = this._look.copy(moveTo).add(_d.set(0, 1.5, 0));
          if (!moveTo || a.pos.distXZ(moveTo) < 1.5 || now > this.investigateUntil) { this.investigatePos = null; this.walk = false; }
          break;
        }
        case 'hold': {
          if (this.holdSpot && a.pos.distXZ(this.holdSpot) > 1.4) moveTo = this.holdSpot;
          if (!this.lookAt || this.stateTime > 3) this.lookAt = this.holdLook;
          it.crouch = this.dk === 'hard' && (Math.floor(now / 6 + a.id) % 3 === 0);
          break;
        }
        case 'patrol':
        case 'objective': {
          moveTo = this.objectiveTarget(now);
          break;
        }
        case 'regroup': {
          it.f = it.r = 0;
          const z = map.plantZones[this.site];
          this.lookAt = this._look.set(map.cellX((z.c0 + z.c1) / 2), 1.5, map.cellZ((z.r0 + z.r1) / 2));
          break;
        }
        case 'plant': {
          it.f = it.r = 0; it.use = true; it.crouch = true;
          if (a.active !== 'bomb' && a.inv.bomb) a.switchTo('bomb', null, now);
          break;
        }
        case 'defuse': {
          if (!bomb.isPlanted) { this.setState('idle'); break; }
          if (a.pos.distXZ(bomb.pos) > 0.9) { moveTo = bomb.pos; }
          else { it.f = it.r = 0; it.use = true; it.crouch = true; this.lookAt = this._look.copy(bomb.pos); }
          break;
        }
        case 'retake': {
          if (!bomb.isPlanted) break;
          const bd = a.pos.distXZ(bomb.pos);
          // reagrupa antes de retomar, a não ser que o tempo esteja acabando
          let mates = 0;
          for (const o of world.agents) if (o !== a && o.alive && o.team === 'CT' && o.pos.distXZ(a.pos) < 12) mates++;
          const waitRetake = bd < 22 && bd > 14 && mates === 0 && world.alive('CT') > 1 && bomb.explodeAt - now > 22 && this.stateTime < 10;
          if (waitRetake) { it.f = it.r = 0; this.lookAt = this._look.copy(bomb.pos).add(_d.set(0, 1.5, 0)); break; }
          if (bd > 7) moveTo = bomb.pos;
          else { it.f = it.r = 0; this.lookAt = this.lookAt && this.stateTime % 4 > 2 ? this.lookAt : this._look.copy(bomb.pos).add(_d.set(M.rand(-10, 10), 1.6, M.rand(-10, 10))); }
          break;
        }
        case 'guardBomb': {
          if (!this.guardSpot || this.guardSpot.site !== bomb.site) {
            const cp = this.findGuardSpot(bomb.pos);
            this.guardSpot = { pos: cp || bomb.pos.clone(), site: bomb.site };
          }
          if (a.pos.distXZ(this.guardSpot.pos) > 1.2) moveTo = this.guardSpot.pos;
          else { it.crouch = this.dk !== 'easy'; this.lookAt = this._look.copy(bomb.pos).add(_d.set(0, 1.0, 0)); }
          break;
        }
        case 'save': {
          moveTo = this.goal;
          break;
        }
        case 'buy': case 'idle': default: break;
      }
      if (moveTo) {
        this.navigateTo(moveTo, dt, now);
        if (!this.lookAt || this.state === 'objective' || this.state === 'patrol' || this.state === 'retreat') this.faceMove(dt);
      } else if (this.state !== 'blind') { if (it.use) { it.f = 0; it.r = 0; } else if (this.state !== 'flee') { it.f = it.r = 0; } }
      if (this.lookAt && !(moveTo && (this.state === 'objective' || this.state === 'patrol' || this.state === 'retreat'))) this.lookToward(this.lookAt, dt);
      it.walk = this.walk;
      // fogo de oportunidade enquanto se move
      if (this.targetVisible && this.target && now >= this.reactAt && this.state !== 'plant' && this.state !== 'defuse') this.fireControl(now, false);
    }

    objectiveTarget(now) {
      const a = this.agent, bomb = world.bomb;
      if (this.goalKey === 'bombpick') return bomb.state === 'available' ? bomb.pos : null;
      if (a.team === 'T') {
        if (!this.route) return null;
        if (this.routeStep < this.route.via.length) {
          const p = map.idxPos(this.viaIdx(this.routeStep));
          const needRegroup = this.routeStep === this.route.via.length - 1 && this.d.regroup && MP.game.roundTimeLeft() > 40;
          if (a.pos.distXZ(p) < 2.2 && !needRegroup) this.routeStep++;
          return p;
        }
        if (a.inv.bomb) { if (!this.plantSpot) this.plantSpot = this.choosePlantSpot(this.site); return this.plantSpot; }
        // escolta: posição no site
        if (!this.siteSpot) this.siteSpot = this.choosePlantSpot(this.site);
        if (a.pos.distXZ(this.siteSpot) < 1.5) { this.lookAt = this._look.set(a.pos.x + M.rand(-10, 10), 1.6, a.pos.z - 10); return null; }
        return this.siteSpot;
      }
      return this.holdSpot;
    }
    findGuardSpot(bp) {
      const cand = [];
      const c0 = map.colOf(bp.x), r0 = map.rowOf(bp.z);
      for (let dr = -6; dr <= 6; dr++) for (let dc = -6; dc <= 6; dc++) {
        const i = (r0 + dr) * map.W + (c0 + dc);
        if (r0 + dr < 0 || c0 + dc < 0 || r0 + dr >= map.H || c0 + dc >= map.W || !map.walkable[i]) continue;
        cand.push(i);
      }
      M.shuffle(cand);
      const p = new V3();
      for (const i of cand.slice(0, 30)) {
        map.idxPos(i, p);
        const dd = p.distXZ(bp);
        if (dd < 4 || dd > 12) continue;
        if (map.segmentClear(_c.set(p.x, p.y + 1.1, p.z), _d.set(bp.x, bp.y + 0.3, bp.z))) return p.clone();
      }
      return null;
    }

    executeEngage(dt, now) {
      const a = this.agent, it = a.intent, d = this.d, tgt = this.target;
      if (!tgt) return;
      const dist = a.pos.dist(tgt.pos);
      const w = a.weapon;
      // movimento de combate
      const firing = now < this.burstPauseUntil ? false : true;
      const longRange = dist > 14;
      if (a.active === 'knife') {
        this.navigateTo(tgt.pos, dt, now);
      } else if (longRange && Math.random() < d.counterStrafe) {
        // para e atira (precisão), com passos laterais entre rajadas
        if (now < this.burstPauseUntil && Math.random() < d.strafe) { it.f = 0; it.r = this.strafeDir * 0.6; it.walk = true; }
        else { it.f = 0; it.r = 0; }
        if (now > this.crouchUntil && Math.random() < d.crouchSpray * 0.1) this.crouchUntil = now + M.rand(1, 2.5);
        it.crouch = now < this.crouchUntil;
      } else {
        // curta distância: strafe
        if (now > this.strafeUntil) { this.strafeDir = Math.random() < 0.5 ? -1 : 1; this.strafeUntil = now + M.rand(0.35, 0.9); }
        it.r = Math.random() < d.strafe ? this.strafeDir : 0;
        it.f = dist > 8 ? 0.3 : dist < 3 ? -0.5 : 0;
        // evita andar para dentro de parede
        if (it.r !== 0) {
          const right = _c.set(Math.cos(a.yaw), 0, -Math.sin(a.yaw));
          if (map.boxBlocked(a.pos.x + right.x * it.r * 0.8 - 0.3, a.pos.y + 0.5, a.pos.z + right.z * it.r * 0.8 - 0.3, a.pos.x + right.x * it.r * 0.8 + 0.3, a.pos.y + 1.6, a.pos.z + right.z * it.r * 0.8 + 0.3)) { this.strafeDir *= -1; it.r = 0; }
        }
      }
      // sniper: usa luneta à distância
      if (w && w.def.zoom) {
        if (dist > 8 && w.zoomLevel === 0 && now >= a.drawEnd && !w.reloading && now > w.nextFire - 0.1) a.altAction(now);
        if (dist <= 8 && w.zoomLevel > 0) { w.zoomLevel = 0; }
        if (w.zoomLevel > 0) { it.f = 0; it.r = 0; }
      }
      this.aimAtTarget(dt, now);
      if (now >= this.reactAt) this.fireControl(now, false);
    }

    aimAtTarget(dt, now) {
      const a = this.agent, d = this.d, tgt = this.target;
      const eye = a.eyePos(_a);
      const head = this.aimHead === undefined || now - (this.aimHeadAt || 0) > 1.2;
      if (head) { this.aimHead = Math.random() < d.headChance; this.aimHeadAt = now; }
      const p = this.aimHead ? tgt.headPos(_b) : tgt.chestPos(_b);
      if (!this.targetVisible && this.hasLastKnown) p.set(this.lastKnown.x, this.lastKnown.y + 1.4, this.lastKnown.z);
      // erro de mira que diminui ao acompanhar o alvo
      const decay = Math.exp(-d.track * dt);
      this.errY *= decay; this.errP *= decay;
      // movimento lateral do alvo aumenta o erro
      const lat = Math.abs(tgt.vel.x * Math.cos(a.yaw) - tgt.vel.z * Math.sin(a.yaw));
      this.errY += (Math.random() - 0.5) * lat * 0.004 * (2 - d.recoilComp);
      const yaw = M.yawTo(eye, p) + this.errY;
      const pitch = M.pitchTo(eye, p) + this.errP;
      this.desiredYaw = yaw; this.desiredPitch = pitch;
      this.aimYaw = this.turnToward(this.aimYaw, yaw, d.turn * dt);
      this.aimPitch = this.turnToward(this.aimPitch, pitch, d.turn * dt * 0.7);
    }

    fireControl(now, moving) {
      const a = this.agent, it = a.intent, d = this.d, tgt = this.target, w = a.weapon;
      if (!tgt || !tgt.alive || !this.targetVisible) return;
      if (a.active === 'grenade' || a.active === 'bomb') { a.switchToBest(now); return; }
      if (!w) return;
      if (w.reloading) return;
      if (w.def.mag && w.clip <= 0) return;
      if (now < this.burstPauseUntil) return;
      if (moving && this.state !== 'retreat') this.aimAtTarget(0.016, now);
      const eye = a.eyePos(_a);
      const tp = tgt.chestPos(_b);
      const dist = eye.dist(tp);
      if (w.def.mode === 'melee' && dist > 2.2) return;
      // tolerância angular ~ largura do alvo
      const tol = Math.atan2(0.32, dist) * d.fireTol + (w.def.pellets ? 2 * DEG : 0);
      const ey = Math.abs(M.wrapAngle(this.aimYaw - M.yawTo(eye, tp)));
      const ep = Math.abs(this.aimPitch - M.pitchTo(eye, tp));
      if (ey > tol * 1.5 || ep > tol * 2.2) return;
      // não atira se um aliado estiver na frente
      const dir = M.dirFromAngles(this.aimYaw, this.aimPitch, _c);
      for (const o of world.agents) {
        if (o === a || !o.alive || o.team !== a.team) continue;
        const h = o.rayHit(eye, dir, dist); if (h) { this.strafeDir *= -1; return; }
      }
      // checa linha de tiro (sem atirar em parede)
      if (!map.segmentClear(eye, tp) && !map.segmentClear(eye, tgt.headPos(_d))) { this.targetVisible = false; return; }
      // sniper sem luneta à distância: espera
      if (w.def.zoom && dist > 8 && w.zoomLevel === 0) return;
      // semiautomática: solta o gatilho entre tiros
      if (w.triggerHeld && w.def.mode !== 'auto') { it.fire = false; w.triggerHeld = false; return; }
      it.fire = true;
      a.yaw = this.aimYaw - a.punchY * d.recoilComp; a.pitch = this.aimPitch - a.punchP * d.recoilComp;
      if (a.tryFire(now)) {
        this.burstCount++;
        const auto = w.def.mode === 'auto';
        const longR = dist > 15;
        if (auto && (longR || this.dk === 'easy')) {
          if (this.burstCount >= this.burstLen) {
            this.burstCount = 0; this.burstLen = M.randInt(d.burst[0], d.burst[1]);
            this.burstPauseUntil = now + M.rand(d.burstPause[0], d.burstPause[1]) * (longR ? 1 : 0.5);
          }
        } else if (auto && this.burstCount > 12 + (this.dk === 'hard' ? 10 : 0)) {
          this.burstCount = 0; this.burstPauseUntil = now + 0.2;
        } else if (!auto) {
          this.burstPauseUntil = now + (w.def.mode === 'bolt' ? 0 : M.rand(0.05, 0.25) * (this.dk === 'easy' ? 2 : 1));
        }
      }
    }

    // ============================================================ navegação
    goTo(pos, key) {
      const a = this.agent;
      const from = map.nearestWalkable(a.pos.x, a.pos.z);
      const to = map.nearestWalkable(pos.x, pos.z);
      this.goal = pos.clone ? pos.clone() : new V3(pos.x, pos.y, pos.z);
      this.goalKey = key || '';
      const jitter = Math.random() * 0.3;
      const path = map.findPath(from, to, (i) => {
        let c = 0;
        const p = map.idxPos(i, _d);
        if (world.fires.length && world.inFire(p, 1)) c += 40;
        return c + jitter * ((i * 2654435761) % 7) / 7;
      });
      if (!path) { this.path = null; return false; }
      this.path = map.smoothPath(a.pos, path, 0.45);
      this.pathIdx = 0;
      this.pathGoalIdx = to;
      return true;
    }
    navigateTo(pos, dt, now) {
      const a = this.agent;
      const toIdx = map.nearestWalkable(pos.x, pos.z);
      if (!this.path || this.pathGoalIdx !== toIdx || this.repathAt && now > this.repathAt) {
        this.repathAt = now + 4;
        if (!this.goTo(pos, this.goalKey)) { this.moveDirect(pos); return; }
      }
      if (!this.path || !this.path.length) { this.moveDirect(pos); return; }
      let wp = this.path[this.pathIdx];
      while (wp && a.pos.distXZ(wp) < 0.7 && this.pathIdx < this.path.length - 1) { this.pathIdx++; wp = this.path[this.pathIdx]; }
      if (!wp) return;
      if (this.pathIdx === this.path.length - 1 && a.pos.distXZ(pos) < 0.5) { a.intent.f = a.intent.r = 0; return; }
      this.moveDirect(this.pathIdx === this.path.length - 1 ? pos : wp);
    }
    moveDirect(p) {
      const a = this.agent, it = a.intent;
      let dx = p.x - a.pos.x, dz = p.z - a.pos.z;
      const l = Math.sqrt(dx * dx + dz * dz);
      if (l < 0.05) { it.f = it.r = 0; return; }
      dx /= l; dz /= l;
      // separação entre aliados
      for (const o of world.agents) {
        if (o === a || !o.alive) continue;
        const ox = a.pos.x - o.pos.x, oz = a.pos.z - o.pos.z; const od = Math.sqrt(ox * ox + oz * oz);
        if (od < 1.1 && od > 0.01) { dx += ox / od * 0.6 * (1.1 - od); dz += oz / od * 0.6 * (1.1 - od); }
      }
      const l2 = Math.sqrt(dx * dx + dz * dz) || 1; dx /= l2; dz /= l2;
      this.moveYaw = Math.atan2(-dx, -dz);
      // converte direção do mundo em intenção relativa à orientação do corpo
      const sy = Math.sin(a.yaw), cy = Math.cos(a.yaw);
      const fx = -sy, fz = -cy, rx = cy, rz = -sy;
      it.f = dx * fx + dz * fz; it.r = dx * rx + dz * rz;
      const slow = l < 1.2 ? Math.max(0.35, l / 1.2) : 1;
      it.f *= slow; it.r *= slow;
    }
    faceMove(dt) {
      if (this.moveYaw === undefined) return;
      this.aimYaw = this.turnToward(this.aimYaw, this.moveYaw, this.d.turn * dt * 0.6);
      // mira na altura da cabeça (posicionamento de mira) em vez do chão
      const target = this.d.prefire > 0.2 ? 0 : -0.12;
      this.aimPitch = this.turnToward(this.aimPitch, target, this.d.turn * dt * 0.3);
    }
    lookToward(p, dt) {
      const eye = this.agent.eyePos(_a);
      this.aimYaw = this.turnToward(this.aimYaw, M.yawTo(eye, p), this.d.turn * dt * 0.5);
      this.aimPitch = this.turnToward(this.aimPitch, M.clamp(M.pitchTo(eye, p), -0.6, 0.6), this.d.turn * dt * 0.3);
    }
    lookAround(dt, now) {
      this.aimYaw += Math.sin(now * 0.7 + this.agent.id) * dt * 0.3;
    }
    turnToward(cur, target, maxStep) {
      const diff = M.wrapAngle(target - cur);
      if (Math.abs(diff) <= maxStep) return target;
      // aproximação suave: passo máximo, mais lento perto do alvo
      return cur + Math.sign(diff) * Math.max(maxStep * Math.min(1, Math.abs(diff) / 0.35), Math.min(Math.abs(diff), maxStep * 0.25));
    }
    applyAim(dt) {
      const a = this.agent;
      if (!a.intent.fire) { a.yaw = this.aimYaw; a.pitch = this.aimPitch; }
      a.yaw = M.wrapAngle(a.yaw);
    }
    checkStuck(now) {
      const a = this.agent, it = a.intent;
      const wants = Math.abs(it.f) + Math.abs(it.r) > 0.3;
      if (now < this.stuckCheckAt) return;
      this.stuckCheckAt = now + 0.8;
      if (wants && a.pos.distXZ(this.stuckPos) < 0.35) {
        this.stuckCount++;
        it.jump = true;
        this.strafeDir *= -1;
        if (this.stuckCount >= 2) { this.path = null; this.repathAt = 0; }
        if (this.stuckCount >= 4) {
          // empurra para o centro da célula caminhável mais próxima
          const i = map.nearestWalkable(a.pos.x, a.pos.z);
          if (i >= 0) { const p = map.idxPos(i); this.moveDirect(p); }
          this.stuckCount = 0;
          if (this.state === 'investigate') { this.investigatePos = null; this.setState('idle'); }
          if (this.state === 'chase') { this.hasLastKnown = false; this.target = null; }
        }
      } else if (!wants || a.pos.distXZ(this.stuckPos) > 1) this.stuckCount = 0;
      this.stuckPos.copy(a.pos);
    }

    // ============================================================ alvo de treino
    updateDummy(dt, now) {
      const a = this.agent, it = a.intent;
      if (!this.anchorPos) this.anchorPos = a.pos.clone();
      if (now > this.strafeUntil) { this.strafeDir *= -1; this.strafeUntil = now + M.rand(0.6, 1.6); this.dummyCrouch = Math.random() < 0.25; }
      it.r = this.dummyMove ? this.strafeDir : 0; it.f = 0; it.walk = Math.random() < 0.02 ? !it.walk : it.walk;
      it.crouch = this.dummyCrouch && this.dummyMove;
      if (a.pos.distXZ(this.anchorPos) > 3) { this.strafeDir = Math.sign((this.anchorPos.x - a.pos.x) * Math.cos(a.yaw) - (this.anchorPos.z - a.pos.z) * Math.sin(a.yaw)) || 1; }
      const pl = MP.game && MP.game.player;
      if (pl) this.lookToward(pl.eyePos(new V3()), dt);
      if (this.dummyArmed && pl && pl.alive) {
        this.target = pl;
        const eye = a.eyePos(new V3());
        this.targetVisible = world.losClear(eye, pl.chestPos(_b));
        if (this.targetVisible) { if (!this.reactAt || now - this.lastSeen > 1) this.reactAt = now + 0.6; this.lastSeen = now; this.aimAtTarget(dt, now); this.fireControl(now, false); }
        if (a.weapon && a.weapon.clip === 0) a.startReload(now);
      }
      this.applyAim(dt);
    }
  }
  MP.BotBrain = BotBrain;

  /** Resolve o ângulo de lançamento balístico para atingir `target`. */
  function solveThrow(from, target, v) {
    const g = 15;
    const dx = target.x - from.x, dz = target.z - from.z, dy = target.y - from.y;
    const x = Math.sqrt(dx * dx + dz * dz);
    const v2 = v * v;
    const disc = v2 * v2 - g * (g * x * x + 2 * dy * v2);
    const yaw = Math.atan2(-dx, -dz);
    if (disc < 0) return x < 30 ? { yaw, pitch: Math.PI / 4 } : null;
    const pitch = Math.atan((v2 - Math.sqrt(disc)) / (g * x));
    return { yaw, pitch };
  }
  MP.solveThrow = solveThrow;

  // ============================================================ compras dos bots
  MP.botBuy = function (a, teamAvgMoney, isPistolRound) {
    const g = MP.game;
    const buy = (id) => g.buy(a, id);
    const T = a.team === 'T';
    const rifle = T ? 'brutus' : 'guardiao';
    const smg = T ? 'vespa' : 'sentinela';
    const eco = !isPistolRound && teamAvgMoney < 2200 && a.money < 3700;
    if (isPistolRound) {
      if (Math.random() < 0.5) buy('vest'); else { buy('flash'); if (Math.random() < 0.5) buy('falcao'); }
      if (!T && Math.random() < 0.4) buy('kit');
      return;
    }
    if (eco) { if (a.money > 900 && Math.random() < 0.4) buy('falcao'); return; }
    if (!a.inv.primary) {
      if (a.money >= 4750 + 1000 && Math.random() < 0.18) buy('mamba');
      else if (a.money >= 2700 + 1000) buy(rifle);
      else if (a.money >= 2000 + 650) buy(Math.random() < 0.5 ? 'tempestade' : smg);
      else if (a.money >= 1500) buy(smg);
      else if (a.money >= 1200 && Math.random() < 0.3) buy('trovao');
    }
    if (a.armor < 100 || !a.helmet) { if (!buy('vesthelm')) buy('vest'); }
    if (!T && !a.inv.kit && a.money > 400) buy('kit');
    if (a.money > 300 && Math.random() < 0.8) buy('smoke');
    if (a.money > 200 && Math.random() < 0.7) buy('flash');
    if (a.money > 300 && Math.random() < 0.6) buy('he');
    if (a.money > 600 && Math.random() < 0.4) buy(T ? 'molotov' : 'incend');
  };
})(typeof window !== 'undefined' ? window : globalThis);
