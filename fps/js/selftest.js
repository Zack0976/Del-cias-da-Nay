/* Mirage Protocol — autotestes dos sistemas centrais. Rodam no Node (tests/sim-test.js) e no
 * navegador (Configurações → Diagnóstico → Executar autotestes). Não exigem renderização. */
(function (root) {
  'use strict';
  const MP = root.MP;
  const { V3, map, world, WeaponState, Agent } = MP;

  function mkAgent(team, x, z) {
    const a = new Agent({ id: 900 + world.agents.length, name: 'teste', team, isBot: true });
    world.addAgent(a);
    a.spawnAt(x, z, 0);
    return a;
  }

  const tests = [
    ['recarga respeita o tempo e transfere a munição correta', () => {
      const w = new WeaponState('guardiao'); w.clip = 12;
      if (!w.startReload(0)) return 'não iniciou';
      w.updateReload(1.0); if (w.clip !== 12) return 'completou cedo';
      w.updateReload(3.2); if (w.clip !== 30 || w.reserve !== 90 - 18) return 'valores ' + w.clip + '/' + w.reserve;
      return true;
    }],
    ['reserva parcial não excede nem duplica', () => {
      const w = new WeaponState('brutus'); w.clip = 0; w.reserve = 7;
      w.startReload(0); w.updateReload(10);
      if (w.clip !== 7 || w.reserve !== 0) return w.clip + '/' + w.reserve;
      if (w.canReload()) return 'permitiu recarregar sem reserva';
      return true;
    }],
    ['escopeta recarrega cartucho por cartucho', () => {
      const w = new WeaponState('trovao'); w.clip = 5;
      w.startReload(0); w.updateReload(0.5); if (w.clip !== 6) return 'cartucho 1: ' + w.clip;
      w.updateReload(1.0); w.updateReload(1.5); if (w.clip !== 8 || w.reloading) return 'final: ' + w.clip;
      return true;
    }],
    ['trocar de arma durante a recarga cancela sem alterar munição', () => {
      MP.game.stop();
      const a = mkAgent('CT', map.cellX(23), map.cellZ(20));
      a.giveWeapon('guardiao', 0); a.inv.secondary = new WeaponState('lince');
      const w = a.inv.primary; w.clip = 10; a.drawEnd = 0;
      a.startReload(1); a.switchTo('secondary', null, 1.5);
      a.update(0.016, 5);
      const ok = !w.reloading && w.clip === 10 && w.reserve === 90;
      MP.game.stop();
      return ok || ('clip ' + w.clip + ' reserva ' + w.reserve);
    }],
    ['disparo consome munição e respeita a cadência', () => {
      MP.game.stop();
      const a = mkAgent('CT', map.cellX(23), map.cellZ(20));
      a.giveWeapon('guardiao', 0); a.drawEnd = 0;
      a.intent.fire = true;
      const s1 = a.tryFire(1.0), s2 = a.tryFire(1.01), s3 = a.tryFire(1.0 + 60 / 666 + 0.001);
      const ok = s1 && !s2 && s3 && a.inv.primary.clip === 28;
      MP.game.stop();
      return ok || `${s1} ${s2} ${s3} clip=${a.inv.primary.clip}`;
    }],
    ['semiautomática exige soltar o gatilho', () => {
      MP.game.stop();
      const a = mkAgent('T', map.cellX(23), map.cellZ(20));
      a.inv.secondary = new WeaponState('viper'); a.active = '__'; a.switchTo('secondary', null, 0); a.drawEnd = 0;
      a.inv.secondary.triggerHeld = false; a.intent.fire = true;
      const s1 = a.tryFire(1), s2 = a.tryFire(2);
      a.intent.fire = false; a.update(0.016, 2.1); a.intent.fire = true;
      const s3 = a.tryFire(2.2);
      MP.game.stop();
      return (s1 && !s2 && s3) || `${s1} ${s2} ${s3}`;
    }],
    ['carregador vazio não dispara nem fica negativo', () => {
      MP.game.stop();
      const a = mkAgent('CT', map.cellX(23), map.cellZ(20));
      a.giveWeapon('guardiao', 0); a.drawEnd = 0; a.inv.primary.clip = 0; a.inv.primary.reserve = 0;
      a.intent.fire = true;
      const s = a.tryFire(1);
      const ok = !s && a.inv.primary.clip === 0;
      MP.game.stop();
      return ok || 'disparou';
    }],
    ['dano por região e colete', () => {
      MP.game.stop();
      const v = mkAgent('T', 0, 0); v.armor = 0;
      v.applyDamage(MP.WEAPONS.brutus.dmg * 4, null, 'brutus', 'head', null, 0);
      if (v.alive) return 'tiro na cabeça sem capacete não matou';
      const v2 = mkAgent('T', 0, 0); v2.armor = 100; v2.helmet = true;
      v2.applyDamage(MP.WEAPONS.guardiao.dmg, null, 'guardiao', 'chest', null, 0);
      const ok = v2.hp === 100 - Math.round(33 * 0.7) && v2.armor < 100;
      MP.game.stop();
      return ok || ('hp ' + v2.hp + ' colete ' + v2.armor);
    }],
    ['balística: raio atinge agente e é bloqueado por parede', () => {
      MP.game.stop();
      const s = mkAgent('CT', map.cellX(21), map.cellZ(26));
      const t = mkAgent('T', map.cellX(21), map.cellZ(16));
      const o = s.eyePos(new V3()), d = new V3(0, 0, -1);
      const r = MP.combat.trace(s, o, d, MP.WEAPONS.guardiao);
      const hit1 = r.agentHit === t;
      // atrás da parede (A longo x meio)
      const t2 = mkAgent('T', map.cellX(4), map.cellZ(26)); t.alive = false;
      const o2 = new V3(map.cellX(22), 1.6, map.cellZ(26)), d2 = new V3(-1, 0, 0);
      const r2 = MP.combat.trace(s, o2, d2, MP.WEAPONS.guardiao);
      const ok = hit1 && r2.agentHit !== t2;
      MP.game.stop();
      return ok || `acerto=${hit1} atravessou=${r2.agentHit === t2}`;
    }],
    ['colisão impede atravessar paredes', () => {
      MP.game.stop();
      const a = mkAgent('CT', map.cellX(20.5), map.cellZ(20));
      a.yaw = Math.PI / 2; // olhando para -X
      a.intent.f = 1;
      for (let i = 0; i < 240; i++) a.update(1 / 60, i / 60, false);
      const wallX = map.OX + 20 * map.S;
      const ok = a.pos.x - 0.29 >= wallX - 0.01;
      MP.game.stop();
      return ok || 'x=' + a.pos.x.toFixed(2) + ' parede=' + wallX;
    }],
    ['degraus: sobe a passarela e desce', () => {
      MP.game.stop();
      const a = mkAgent('CT', map.cellX(21), map.cellZ(16));
      a.yaw = Math.PI / 2; a.intent.f = 1;
      let maxY = 0;
      for (let i = 0; i < 300; i++) { a.update(1 / 60, i / 60, false); maxY = Math.max(maxY, a.pos.y); }
      MP.game.stop();
      return maxY >= 1.19 || 'altura máxima ' + maxY.toFixed(2);
    }],
    ['navegação: caminhos entre bases e sites', () => {
      const from = map.nearestWalkable(map.cellX(23), map.cellZ(35));
      for (const [c, r] of [[9, 9], [40, 10], [23, 3], [4, 25], [40, 22], [16, 16]]) {
        const p = map.findPath(from, map.nearestWalkable(map.cellX(c), map.cellZ(r)));
        if (!p) return 'sem caminho para ' + c + ',' + r;
      }
      return true;
    }],
    ['estados da bomba rejeitam transições inválidas', () => {
      const b = new MP.Bomb(); const errs = MP.diag.errors.length; MP.diag.quiet = true;
      b.setState('carried'); b.setState('planting'); b.setState('planted');
      const bad = b.setState('carried');
      b.setState('detonated');
      const bad2 = b.setState('defusing');
      MP.diag.errors.length = errs; MP.diag.quiet = false;
      return (!bad && !bad2 && b.state === 'detonated') || 'estado ' + b.state;
    }],
    ['economia: saldo, limites e compra duplicada', () => {
      MP.game.stop();
      MP.game.mode = 'free';
      const a = mkAgent('CT', 0, 0);
      MP.game.mode = 'competitive'; MP.game.phase = 'freeze'; MP.game.phaseEnd = world.time + 10; MP.game.phaseStart = world.time;
      a.pos.set(map.cellX(23), 0, map.cellZ(3));
      a.money = 3000;
      const b1 = MP.game.buy(a, 'guardiao');
      const b2 = MP.game.buy(a, 'guardiao');
      const b3 = MP.game.buy(a, 'mamba');
      const b4 = MP.game.buy(a, 'brutus');
      const ok = b1 && !b2 && !b3 && !b4 && a.money === 100 && a.inv.primary.id === 'guardiao';
      MP.game.stop();
      return ok || `${b1} ${b2} ${b3} ${b4} $${a.money}`;
    }],
    ['fumaça bloqueia linha de visão', () => {
      MP.game.stop();
      const a = new V3(map.cellX(21), 1.6, map.cellZ(28)), b = new V3(map.cellX(21), 1.6, map.cellZ(16));
      const before = world.losClear(a, b);
      world.smokes.push({ pos: new V3(map.cellX(21), 1.4, map.cellZ(22)), radiusNow: 4.3, born: 0, life: 18 });
      const after = world.losClear(a, b);
      world.smokes.length = 0;
      return (before && !after) || `${before} ${after}`;
    }],
    ['bomba: plantio (3,2 s) → detonação dá vitória T', () => bombScenario(false)],
    ['bomba: desarme com kit (5 s) dá vitória CT', () => bombScenario(true)],
    ['configurações validam valores', () => {
      const v = MP.settings.validate;
      return (v('fov', 500) === 100 && v('mouseSens', 'x') === 1 && v('quality', 'ultra') === 'auto' && v('invertY', 1) === false) || 'falhou';
    }]
  ];

  /** Partida 1x1 controlada: T planta no A; CT desarma (ou não). Verifica estados e resultado. */
  function bombScenario(defuse) {
    const g = MP.game;
    g.start({ mode: 'competitive', withPlayer: false, teamSize: 1, roundsToWin: 3, difficulty: 'normal' });
    const t = world.agents.find(a => a.team === 'T'), ct = world.agents.find(a => a.team === 'CT');
    for (const a of world.agents) a.ai.update = function () { };
    // termina o congelamento
    g.phaseEnd = world.time; g.update(1 / 60);
    t.pos.set(map.cellX(7), 0, map.cellZ(10)); ct.pos.set(map.cellX(40), 0, map.cellZ(3));
    if (!t.inv.bomb) { for (const a of world.agents) a.inv.bomb = false; t.inv.bomb = true; world.bomb.carrier = t; }
    t.intent.use = true;
    const states = [];
    let plantedAt = -1;
    for (let i = 0; i < 60 * 60 && g.phase === 'live'; i++) {
      g.update(1 / 60);
      if (states[states.length - 1] !== world.bomb.state) states.push(world.bomb.state);
      if (world.bomb.state === 'planted' && plantedAt < 0) {
        plantedAt = world.time; t.intent.use = false;
        if (defuse) { ct.inv.kit = true; ct.pos.set(world.bomb.pos.x + 0.6, world.bomb.pos.y, world.bomb.pos.z); ct.intent.use = true; }
      }
    }
    const res = g.lastRoundResult;
    const plantTime = plantedAt >= 0 ? plantedAt : -1;
    g.stop();
    const want = defuse ? ['planting', 'planted', 'defusing', 'defused'] : ['planting', 'planted', 'detonated'];
    const ok = res && JSON.stringify(states) === JSON.stringify(want) && res.winner === (defuse ? 'CT' : 'T') && res.reason === (defuse ? 'defuse' : 'bomb') && plantTime > 3.1;
    return ok || ('estados ' + states.join('→') + ' resultado ' + JSON.stringify(res));
  }

  MP.selftest = {
    run() {
      const out = [];
      const savedMode = MP.game.mode;
      if (savedMode !== 'idle') return [{ name: 'autotestes', ok: false, info: 'saia da partida para executar' }];
      for (const [name, fn] of tests) {
        let r;
        try { r = fn(); } catch (e) { r = 'exceção: ' + e.message; }
        out.push({ name, ok: r === true, info: r === true ? '' : String(r) });
      }
      MP.game.stop();
      return out;
    }
  };
})(typeof window !== 'undefined' ? window : globalThis);
