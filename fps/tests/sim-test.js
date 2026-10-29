/* Testes headless da simulação (Node.js, sem navegador):
 *   node tests/sim-test.js
 * Carrega os mesmos módulos usados no jogo (sem renderização/áudio/UI), executa testes unitários
 * de sistemas e partidas completas bot contra bot, verificando invariantes a cada passo. */
'use strict';
const path = require('path');
const files = ['core', 'map', 'weapons', 'world', 'agent', 'bots', 'game', 'selftest'];
for (const f of files) require(path.join(__dirname, '..', 'js', f + '.js'));
const MP = globalThis.MP;

let failures = 0;
function report(name, ok, info) {
  console.log((ok ? '  OK   ' : '  FALHA ') + name + (info ? '  — ' + info : ''));
  if (!ok) failures++;
}

console.log('== Testes unitários (MP.selftest) ==');
for (const r of MP.selftest.run()) report(r.name, r.ok, r.info);

console.log('\n== Partidas completas bot x bot ==');
function simulateMatch(difficulty, teamSize, roundsToWin, maxSeconds) {
  const g = MP.game, w = MP.world;
  g.start({ mode: 'competitive', withPlayer: false, difficulty, teamSize, roundsToWin });
  const ids = w.agents.map(a => a.id).join(',');
  const dt = 1 / 60;
  const stats = { reasons: {}, plants: 0, defuses: 0, explosions: 0, kills: 0, shots: 0, reloads: 0, nades: 0, invariantErrors: [], rounds: 0, stuckMax: 0, deadFire: 0 };
  const on = (n, fn) => MP.events.on(n, fn);
  const handlers = [];
  const add = (n, fn) => { on(n, fn); handlers.push([n, fn]); };
  add('round:end', r => { stats.reasons[r.reason] = (stats.reasons[r.reason] || 0) + 1; stats.rounds++; });
  add('bomb:planted', () => stats.plants++);
  add('bomb:defused', () => stats.defuses++);
  add('bomb:exploded', () => stats.explosions++);
  add('kill', () => stats.kills++);
  add('fired', (a) => { stats.shots++; if (!a.alive) stats.deadFire++; });
  add('reload:start', () => stats.reloads++);
  add('grenade:throw', () => stats.nades++);
  let ended = false; add('match:end', () => { ended = true; });
  const idle = new Map();
  let steps = 0;
  const maxSteps = maxSeconds / dt;
  while (!ended && steps < maxSteps) {
    g.update(dt); steps++;
    if (steps % 30 !== 0) continue;
    // invariantes
    if (w.agents.map(a => a.id).join(',') !== ids) stats.invariantErrors.push('agentes duplicados/perdidos');
    for (const a of w.agents) {
      for (const ws of [a.inv.primary, a.inv.secondary]) {
        if (!ws) continue;
        if (ws.clip < 0 || ws.reserve < 0 || ws.clip > ws.def.mag) stats.invariantErrors.push('munição inválida ' + ws.id + ' ' + ws.clip + '/' + ws.reserve);
      }
      if (!isFinite(a.pos.x + a.pos.y + a.pos.z)) stats.invariantErrors.push('posição NaN ' + a.name);
      if (a.hp < 0 || a.hp > 100) stats.invariantErrors.push('hp inválido');
      if (a.money < 0 || a.money > 16000) stats.invariantErrors.push('dinheiro inválido ' + a.money);
      if (a.alive && MP.map.boxBlocked(a.pos.x - 0.25, a.pos.y + 0.1, a.pos.z - 0.25, a.pos.x + 0.25, a.pos.y + 1.1, a.pos.z + 0.25)) stats.invariantErrors.push('agente dentro de parede ' + a.name + ' @' + a.pos.x.toFixed(1) + ',' + a.pos.z.toFixed(1));
      // bots presos: mesma posição por muito tempo querendo andar
      if (a.alive && a.ai && g.phase === 'live') {
        const k = idle.get(a) || { p: a.pos.clone(), t: 0 };
        const wants = Math.abs(a.intent.f) + Math.abs(a.intent.r) > 0.3;
        if (wants && a.pos.distXZ(k.p) < 0.3) k.t += 0.5; else { k.t = 0; k.p.copy(a.pos); }
        idle.set(a, k); stats.stuckMax = Math.max(stats.stuckMax, k.t);
      }
    }
    const b = w.bomb;
    if (b.state === 'detonated' && b.defuser) stats.invariantErrors.push('bomba detonada com desarmador');
    if (b.state === 'carried' && (!b.carrier || !b.carrier.inv.bomb)) stats.invariantErrors.push('bomba carregada sem portador');
  }
  for (const [n, fn] of handlers) MP.events.off(n, fn);
  stats.simSeconds = Math.round(steps * dt);
  stats.ended = ended;
  stats.score = g.score.T + 'x' + g.score.CT;
  g.stop();
  return stats;
}

const t0 = Date.now();
const runs = [['easy', 5, 3], ['normal', 5, 5], ['hard', 5, 5], ['normal', 2, 3], ['hard', 1, 3]];
let totalPlants = 0, totalDefuses = 0, totalReloads = 0, totalNades = 0;
for (const [d, s, r] of runs) {
  const st = simulateMatch(d, s, r, 60 * 30);
  totalPlants += st.plants; totalDefuses += st.defuses; totalReloads += st.reloads; totalNades += st.nades;
  const info = `placar T×CT ${st.score}, rodadas ${st.rounds}, motivos ${JSON.stringify(st.reasons)}, plantios ${st.plants}, desarmes ${st.defuses}, explosões ${st.explosions}, abates ${st.kills}, tiros ${st.shots}, recargas ${st.reloads}, granadas ${st.nades}, ${st.simSeconds}s simulados, maior tempo preso ${st.stuckMax}s`;
  report(`partida ${d} ${s}x${s} até ${r}`, st.ended && st.invariantErrors.length === 0 && st.kills > 0 && st.deadFire === 0, info);
  if (st.invariantErrors.length) console.log('     invariantes:', [...new Set(st.invariantErrors)].slice(0, 8));
  if (st.stuckMax > 12) report('  bots sem ficar presos permanentemente', false, 'preso por ' + st.stuckMax + 's');
}
report('bots recarregam e usam granadas', totalReloads > 0 && totalNades > 0, totalReloads + ' recargas, ' + totalNades + ' granadas');
report('bomba foi plantada em alguma partida', totalPlants > 0, totalPlants + ' plantios');
console.log('  info: desarmes em partidas bot x bot: ' + totalDefuses + ' (o ciclo plantio/detonação/desarme é verificado de forma determinística nos autotestes)');
console.log(`\nTempo real: ${((Date.now() - t0) / 1000).toFixed(1)}s`);
console.log(failures ? `\n${failures} FALHA(S)` : '\nTODOS OS TESTES PASSARAM');
process.exit(failures ? 1 : 0);
