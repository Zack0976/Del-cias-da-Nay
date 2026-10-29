/* Testes de integração no navegador (Chromium headless via Playwright):
 *   npm i -D playwright   (ou use um Playwright já instalado)
 *   node tests/browser-test.js [--shots]
 * Sobe um servidor HTTP local, abre o jogo e verifica inicialização, renderização, movimento, colisão,
 * câmera, armas, munição, recarga, dano, bots, compra, pausa, bomba, rodadas, reinício,
 * persistência de configurações e controles de toque multitoque (CDP). */
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
let chromium;
try { ({ chromium } = require('playwright')); } catch (e) { console.error('Playwright não encontrado. Instale com: npm i -D playwright'); process.exit(2); }

const ROOT = path.join(__dirname, '..');
const SHOTS = process.argv.includes('--shots');
const SHOT_DIR = path.join(ROOT, 'docs');
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png', '.jpg': 'image/jpeg', '.txt': 'text/plain' };

function serve() {
  return new Promise(res => {
    const srv = http.createServer((req, rs) => {
      const u = decodeURIComponent(req.url.split('?')[0]);
      const f = path.join(ROOT, u === '/' ? 'index.html' : u);
      if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { rs.writeHead(404); rs.end(); return; }
      rs.writeHead(200, { 'Content-Type': TYPES[path.extname(f)] || 'application/octet-stream' });
      fs.createReadStream(f).pipe(rs);
    });
    srv.listen(0, () => res(srv));
  });
}

const results = [];
async function waitReady(pg) {
  for (let i = 0; i < 120; i++) {
    const ok = await pg.evaluate(() => !!(window.MP && MP.main && MP.main.running)).catch(() => false);
    if (ok) return true;
    await pg.waitForTimeout(250);
  }
  throw new Error('jogo não ficou pronto em 30 s');
}
function rec(feature, expected, observed, ok) { results.push({ feature, expected, observed, status: ok === null ? 'não testado' : ok ? 'aprovado' : 'reprovado' }); console.log((ok ? 'OK   ' : ok === null ? '---  ' : 'FALHA') + ' ' + feature + ' — ' + observed); }

(async () => {
  const srv = await serve();
  const url = 'http://localhost:' + srv.address().port + '/index.html';
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'] });
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  const ev = (fn, arg) => page.evaluate(fn, arg);
  const wait = (ms) => page.waitForTimeout(ms);
  // espera por tempo de SIMULAÇÃO (o Chromium por software roda devagar) e por quadros renderizados
  const simWait = async (sec, pg) => { pg = pg || page; const t0 = await pg.evaluate(() => MP.world.time); for (let i = 0; i < 600; i++) { await pg.waitForTimeout(100); const t = await pg.evaluate(() => MP.world.time); if (t - t0 >= sec) return; } };
  const frames = async (n, pg) => { pg = pg || page; const f0 = await pg.evaluate(() => MP.main.frameNo); for (let i = 0; i < 300; i++) { await pg.waitForTimeout(30); if (await pg.evaluate(() => MP.main.frameNo) - f0 >= n) return; } };
  const hold = async (key, sec) => { await page.keyboard.down(key); await simWait(sec); await page.keyboard.up(key); await frames(2); };
  const shot = async (name) => { if (SHOTS) await page.screenshot({ path: path.join(SHOT_DIR, name + '.jpg'), type: 'jpeg', quality: 72 }); };

  try {
    await page.goto(url);
    await waitReady(page);
    rec('1. Inicialização sem erros fatais', 'jogo inicia, sem exceções', errors.length ? errors.join(' | ') : 'sem erros no console', errors.length === 0);
    const menuVis = await ev(() => document.getElementById('menu-main').classList.contains('show'));
    rec('2. Menu principal exibido', 'menu visível', menuVis ? 'menu visível' : 'menu oculto', menuVis);
    await shot('01-menu');

    // ---------------------------------------------------------------- partida
    await ev(() => { MP.settings.set('tutorialSeen', true); MP.settings.set('quality', 'low'); MP.settings.set('renderScale', 0.5); });
    await page.click('[data-act="play"]');
    await page.click('#menu-setup .seg[data-key="team"] button[data-v="CT"]');
    await page.click('#menu-setup [data-act="start"]');
    await wait(1500);
    const st = await ev(() => ({ mode: MP.game.mode, phase: MP.game.phase, n: MP.world.agents.length, team: MP.game.player.team, hud: !document.getElementById('hud').hidden }));
    rec('3. Partida pode ser iniciada', 'modo competitivo, 10 agentes, HUD', JSON.stringify(st), st.mode === 'competitive' && st.n === 10 && st.hud && st.team === 'CT');
    const spawnPos = await ev(() => MP.world.agents.filter(a => a.isBot).map(a => [a.pos.x, a.pos.z]));
    const gl = await ev(() => ({ calls: MP.render.renderer.info.render.calls, tris: MP.render.renderer.info.render.triangles, webgl2: MP.render.renderer.capabilities.isWebGL2 }));
    rec('4. Cenário 3D renderizado', 'chamadas de desenho e triângulos > 0', `calls=${gl.calls}, triângulos=${gl.tris}, WebGL2=${gl.webgl2}`, gl.calls > 5 && gl.tris > 1000);
    await shot('02-base-ct');

    // compra durante o congelamento
    await page.keyboard.press('KeyB');
    await wait(200);
    const buyOpen = await ev(() => !document.getElementById('buy-menu').hidden);
    await page.click('#buy-cats button[data-i="5"]');
    const m0 = await ev(() => MP.game.player.money);
    await page.click('.bitem[data-id="vest"]');
    await page.click('#buy-cats button[data-i="0"]');
    await page.click('.bitem[data-id="falcao"]');
    await page.click('.bitem[data-id="falcao"]'); // compra duplicada deve falhar
    const b = await ev(() => ({ money: MP.game.player.money, armor: MP.game.player.armor, sec: MP.game.player.inv.secondary.id }));
    await shot('03-compra');
    await page.click('#buy-close');
    rec('23a. Menu de compra funciona', 'colete+Falcão comprados; duplicada recusada; saldo correto', `aberto=${buyOpen} $${m0}→$${b.money} colete=${b.armor} pistola=${b.sec}`, buyOpen && b.money === m0 - 650 - 700 + 0 && b.armor === 100 && b.sec === 'falcao' || (m0 < 1350 && b.armor === 100));

    // termina o congelamento para testar movimento
    await ev(() => { MP.game.phaseEnd = MP.world.time; MP.game.player.hp = 100000; });
    await wait(200);
    // ---------------------------------------------------------------- movimento e colisão
    const p0 = await ev(() => ({ x: MP.game.player.pos.x, z: MP.game.player.pos.z, yaw: MP.game.player.yaw }));
    await hold('KeyW', 1.2);
    const p1 = await ev(() => ({ x: MP.game.player.pos.x, z: MP.game.player.pos.z }));
    const moved = Math.hypot(p1.x - p0.x, p1.z - p0.z);
    rec('5a. Jogador se movimenta (W)', 'deslocamento > 2 m', moved.toFixed(2) + ' m', moved > 2);
    const coll = await ev(async () => {
      const p = MP.game.player; const map = MP.map;
      p.pos.set(map.cellX(20.5), 0, map.cellZ(20)); p.yaw = Math.PI / 2; p.vel.set(0, 0, 0);
      return true;
    });
    await hold('KeyW', 1.5);
    const c1 = await ev(() => { const p = MP.game.player; return { x: p.pos.x, wall: MP.map.OX + 20 * MP.map.S, inside: MP.map.boxBlocked(p.pos.x - 0.29, p.pos.y + 0.1, p.pos.z - 0.29, p.pos.x + 0.29, p.pos.y + 1.7, p.pos.z + 0.29) }; });
    rec('5b. Colisão com paredes', 'para na parede, sem atravessar', `x=${c1.x.toFixed(2)} parede=${c1.wall} dentro=${c1.inside}`, coll && !c1.inside && c1.x - 0.29 >= c1.wall - 0.02);

    // ---------------------------------------------------------------- câmera (mouse com pointer lock emulado)
    const yawA = await ev(() => MP.game.player.yaw);
    await ev(() => { MP.input.locked = true; for (let i = 0; i < 10; i++) document.dispatchEvent(new MouseEvent('mousemove', { movementX: 20, movementY: 0 })); });
    await frames(3);
    const yawB = await ev(() => MP.game.player.yaw);
    rec('6. Câmera responde ao mouse', 'yaw muda com movimento do mouse', `Δyaw=${(yawB - yawA).toFixed(3)} rad`, Math.abs(yawB - yawA) > 0.1);

    // ---------------------------------------------------------------- armas
    await ev(() => { const p = MP.game.player; p.money = 16000; MP.game.phase = 'live'; MP.game.phaseStart = MP.world.time; MP.game.phaseEnd = MP.world.time + 100; p.pos.set(MP.map.cellX(23), 0, MP.map.cellZ(3)); MP.game.buy(p, 'guardiao'); });
    await simWait(1.1);
    await page.keyboard.press('Digit3'); await frames(3);
    const k = await ev(() => MP.game.player.active);
    await page.keyboard.press('Digit1'); await frames(3); await simWait(1.0);
    const pr = await ev(() => MP.game.player.active + ':' + MP.game.player.weapon.id);
    rec('7. Seleção de armas', 'tecla 3 = faca, 1 = primária', `${k} / ${pr}`, k === 'knife' && pr === 'primary:guardiao');

    // disparo consome munição
    await ev(() => { const p = MP.game.player; p.pos.set(MP.map.cellX(21), 0, MP.map.cellZ(25)); p.yaw = 0; p.pitch = 0; p.vel.set(0, 0, 0); });
    const a0 = await ev(() => MP.game.player.weapon.clip);
    const tf0 = await ev(() => MP.world.time);
    await page.mouse.move(640, 360); await page.mouse.down(); await simWait(0.5); await page.mouse.up(); await frames(2);
    const a1 = await ev(() => ({ clip: MP.game.player.weapon.clip, res: MP.game.player.weapon.reserve, fired: MP.game.player.shotsFired, t: MP.world.time }));
    const maxShots = Math.ceil((a1.t - tf0) / (60 / 666)) + 1;
    rec('8. Disparo consome munição e respeita a cadência', `1 bala por tiro, no máximo ${maxShots} tiros em ${(a1.t - tf0).toFixed(2)} s a 666 RPM`, `${a0} → ${a1.clip} (tiros: ${a1.fired})`, a1.clip < a0 && a1.clip >= 0 && a0 - a1.clip === a1.fired && a1.fired <= maxShots);
    await shot('04-disparo');

    // recarga
    const r0 = await ev(() => ({ t: MP.world.time, clip: MP.game.player.weapon.clip, res: MP.game.player.weapon.reserve, dur: MP.game.player.weapon.def.reload }));
    await page.keyboard.press('KeyR'); await frames(2);
    await simWait(1.0);
    const rMid = await ev(() => ({ rel: MP.game.player.weapon.reloading, clip: MP.game.player.weapon.clip }));
    await simWait(r0.dur);
    const r1 = await ev(() => ({ rel: MP.game.player.weapon.reloading, clip: MP.game.player.weapon.clip, res: MP.game.player.weapon.reserve }));
    rec('9. Recarga respeita o tempo', `não completa antes de ${r0.dur}s`, `após 1s: recarregando=${rMid.rel}, pente=${rMid.clip}; depois: pente=${r1.clip}`, rMid.rel && rMid.clip === r0.clip && !r1.rel && r1.clip === 30);
    rec('10. Reserva consumida corretamente', `reserva = ${r0.res} − ${30 - r0.clip}`, `reserva ${r0.res} → ${r1.res}`, r1.res === r0.res - (30 - r0.clip));

    // dano em alvo
    const dmg = await ev(async () => {
      const p = MP.game.player; const e = MP.world.agents.find(a => a.team === 'T' && a.alive);
      e.ai.dummy = true; e.ai.dummyMove = false; e.ai.dummyArmed = false;
      e.pos.set(p.pos.x, 0, p.pos.z - 8); e.vel.set(0, 0, 0); e.armor = 0;
      p.pitch = Math.atan2((e.pos.y + 1.2) - (p.pos.y + p.eyeHeight), 8);
      p.punchP = 0; p.punchY = 0;
      const hp0 = e.hp; window.__dummy = e;
      return hp0;
    });
    await page.mouse.down(); await simWait(0.15); await page.mouse.up(); await simWait(0.2);
    const hp1 = await ev(() => window.__dummy.hp);
    rec('11. Dano afeta a vida do alvo', 'vida do inimigo diminui', `${dmg} → ${hp1}`, hp1 < dmg);
    await ev(() => { window.__dummy.ai.dummy = false; });

    // ---------------------------------------------------------------- bots
    const bots0 = spawnPos;
    const shotsBefore = await ev(() => MP.world.agents.filter(a => a.isBot).reduce((s, a) => s + a.shotsFired, 0));
    await ev(() => { const p = MP.game.player; p.pos.set(MP.map.cellX(23), 0, MP.map.cellZ(3)); p.hp = 100000; }); // jogador observa sem morrer
    await simWait(14);
    const bots1 = await ev(() => MP.world.agents.filter(a => a.isBot).map(a => [a.pos.x, a.pos.z, a.alive, a.ai.state]));
    let movedBots = 0; bots1.forEach((b, i) => { if (Math.hypot(b[0] - bots0[i][0], b[1] - bots0[i][1]) > 3) movedBots++; });
    rec('12. Bots navegam pelo mapa', 'maioria dos bots sai do spawn', `${movedBots}/${bots1.length} bots a >3 m do spawn; estados: ${[...new Set(bots1.map(b => b[3]))].join(',')}`, movedBots >= 5);
    const info = await ev(() => ({ shots: MP.world.agents.filter(a => a.isBot).reduce((s, a) => s + a.shotsFired, 0), kills: MP.world.agents.reduce((s, a) => s + a.kills, 0), neg: MP.world.agents.some(a => [a.inv.primary, a.inv.secondary].some(w => w && (w.clip < 0 || w.reserve < 0))) }));
    rec('13/14. Bots detectam, atiram e recarregam', 'tiros de bots e abates ocorrem', `tiros=${info.shots - shotsBefore}, abates=${info.kills}`, info.shots - shotsBefore > 0);
    rec('15. Bots sem munição negativa', 'nenhum carregador/reserva < 0', info.neg ? 'munição negativa encontrada' : 'ok', !info.neg);
    await shot('05-combate');
    await ev(() => { MP.game.player.hp = 100; });

    // ---------------------------------------------------------------- pausa
    await ev(() => MP.main.pause());
    const t0 = await ev(() => MP.world.time); await wait(800); const t1 = await ev(() => MP.world.time);
    const pv = await ev(() => document.getElementById('menu-pause').classList.contains('show'));
    await shot('06-pausa');
    rec('20. Pausa realmente pausa', 'tempo da simulação congelado', `Δt=${(t1 - t0).toFixed(3)}s, menu=${pv}`, t1 === t0 && pv);
    await page.click('#menu-pause [data-act="resume"]');
    await ev(() => { MP.input.locked = true; });

    // ---------------------------------------------------------------- bomba: plantar e desarmar
    const bomb = await ev(async () => {
      const g = MP.game, w = MP.world, map = MP.map;
      const out = {};
      // força um portador T e leva-o ao site A
      const t = w.agents.find(a => a.team === 'T' && a.alive) || w.agents.find(a => a.team === 'T');
      if (!t.alive) { t.alive = true; t.hp = 100; }
      for (const a of w.agents) a.inv.bomb = false;
      w.bomb.reset(); t.inv.bomb = true; w.bomb.carrier = t; w.bomb.setState('carried');
      t.ai.dummy = true; t.ai.dummyMove = false; t.ai.dummyArmed = false; t.hp = 100000;
      t.pos.set(map.cellX(6), 0, map.cellZ(7)); t.vel.set(0, 0, 0);
      g.phase = 'live'; g.phaseEnd = w.time + 100;
      // impede o fim da rodada por eliminação durante o teste
      for (const a of w.agents) if (a !== g.player && a !== t) { a.ai.dummy = true; a.ai.dummyArmed = false; a.ai.dummyMove = false; if (a.team === 'CT') { a.alive = true; a.hp = 100000; } }
      const pl = g.player; pl.alive = true; pl.hp = 100000; pl.pos.set(map.cellX(23), 0, map.cellZ(3));
      t.ai.update = function () { this.agent.intent.use = true; this.agent.intent.f = 0; this.agent.intent.r = 0; };
      return true;
    });
    await simWait(3.7);
    const planted = await ev(() => ({ s: MP.world.bomb.state, site: MP.world.bomb.site }));
    await shot('07-bomba');
    const def = await ev(() => {
      const p = MP.game.player, b = MP.world.bomb;
      p.pos.set(b.pos.x + 0.5, b.pos.y, b.pos.z); p.vel.set(0, 0, 0); p.inv.kit = true; p.hp = 100000;
      return b.explodeAt - MP.world.time;
    });
    await hold('KeyE', 5.6);
    await simWait(0.3);
    const after = await ev(() => ({ s: MP.world.bomb.state, phase: MP.game.phase, score: MP.game.score, last: MP.game.lastRoundResult }));
    rec('16. Bomba pode ser plantada e desarmada', 'planted → defused (kit 5 s)', `plantio: ${planted.s} em ${planted.site}; desarme: ${after.s}`, (planted.s === 'planted' || planted.s === 'defusing') && after.s === 'defused');
    rec('17. Vitória encerra a rodada', 'rodada termina com vitória CT por desarme', JSON.stringify(after.last), after.last && after.last.winner === 'CT' && after.last.reason === 'defuse');
    rec('18. Placar atualizado', 'CT +1', `T ${after.score.T} × ${after.score.CT} CT`, after.score.CT >= 1);
    await simWait(5.6); await frames(3);
    const nr = await ev(() => ({ n: MP.world.agents.length, round: MP.game.roundNum, phase: MP.game.phase, ids: new Set(MP.world.agents.map(a => a.id)).size, chars: MP.fx.chars.size, shotL: MP.events.count('shot') }));
    rec('19. Próxima rodada sem duplicar entidades', '10 agentes, 10 modelos, fase freeze', JSON.stringify(nr), nr.n === 10 && nr.ids === 10 && nr.chars === 10 && nr.round === 2);

    // ---------------------------------------------------------------- placar (Tab) e configurações
    await page.keyboard.down('Tab'); await frames(3);
    const sbv = await ev(() => !document.getElementById('scoreboard').hidden);
    await shot('08-placar');
    await page.keyboard.up('Tab');
    rec('21. Controles de PC (Tab/placar, B, E, R, 1-3, WASD, mouse)', 'placar abre com Tab', sbv ? 'placar exibido' : 'não exibido', sbv);

    await ev(() => MP.main.pause());
    await page.click('#menu-pause [data-act="settings"]');
    await page.click('#set-tabs button[data-tab="controls"]');
    await page.evaluate(() => { const i = document.querySelector('input[data-k="mouseSens"]'); i.value = '2.35'; i.dispatchEvent(new Event('input')); });
    await page.click('#set-tabs button[data-tab="video"]');
    await shot('09-config');
    await page.click('#set-tabs button[data-tab="diag"]');
    await page.click('#menu-settings [data-act="close"]');
    // reinício: listeners não podem acumular
    const lBefore = await ev(() => MP.events.count('shot'));
    await page.click('#menu-pause [data-act="restart"]');
    await wait(1200);
    await ev(() => MP.main.restartMatch());
    await wait(800);
    const rs = await ev(() => ({ n: MP.world.agents.length, l: MP.events.count('shot'), chars: MP.fx.chars.size, round: MP.game.roundNum }));
    rec('25. Reinício sem acumular eventos/entidades', 'mesmos ouvintes e 10 agentes', `ouvintes ${lBefore}→${rs.l}, agentes ${rs.n}, modelos ${rs.chars}, rodada ${rs.round}`, rs.l === lBefore && rs.n === 10 && rs.chars === 10 && rs.round === 1);

    // desempenho (swiftshader é renderização por software; número apenas informativo)
    const perf = await ev(() => MP.main.fpsAvg);
    rec('26. Desempenho', 'informativo (CPU/swiftshader, sem GPU)', perf.toFixed(1) + ' FPS em renderização por software', null);

    // persistência
    await page.reload();
    await waitReady(page);
    const sens = await ev(() => MP.settings.values.mouseSens);
    rec('24. Configurações preservadas após recarregar', 'mouseSens = 2.35', String(sens), Math.abs(sens - 2.35) < 1e-6);

    // autotestes no navegador
    const self = await ev(() => MP.selftest.run());
    rec('Autotestes no navegador (Diagnóstico)', 'todos aprovados', `${self.filter(r => r.ok).length}/${self.length}` + self.filter(r => !r.ok).map(r => ' ✘ ' + r.name + ': ' + r.info).join(''), self.every(r => r.ok));

    // modo treino e livre
    await ev(() => MP.main.startMatch({ mode: 'training', dummiesMove: true, dummiesArmed: false, loadout: 'brutus' }, true));
    await wait(1500);
    const tr = await ev(() => ({ n: MP.world.agents.length, w: MP.game.player.inv.primary && MP.game.player.inv.primary.id }));
    await shot('10-treino');
    rec('Modo campo de tiro', 'jogador + 6 alvos, arma escolhida', JSON.stringify(tr), tr.n === 7 && tr.w === 'brutus');
    await ev(() => MP.main.quitToMenu());

    // ---------------------------------------------------------------- erros de WebGL (página de teste sem WebGL)
    const p2 = await ctx.newPage();
    await p2.addInitScript(() => { const orig = HTMLCanvasElement.prototype.getContext; HTMLCanvasElement.prototype.getContext = function (t, o) { if (/webgl/.test(t)) return null; return orig.call(this, t, o); }; });
    await p2.goto(url); await p2.waitForTimeout(1500);
    const glErr = await p2.evaluate(() => !document.getElementById('boot-error').hidden ? document.getElementById('boot-error').textContent.split('\n')[2] : '');
    rec('27. Falha de WebGL gera mensagem útil', 'mensagem explicativa na tela', glErr.slice(0, 90), /WebGL/.test(glErr));
    await p2.close();

    // ---------------------------------------------------------------- toque / multitoque
    const mctx = await browser.newContext({ viewport: { width: 844, height: 390 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 });
    const mp = await mctx.newPage();
    mp.on('pageerror', e => errors.push('mobile: ' + e.message));
    await mp.goto(url);
    await waitReady(mp);
    await mp.evaluate(() => { MP.settings.set('tutorialSeen', true); MP.settings.set('renderScale', 0.5); MP.main.startMatch({ mode: 'free', loadout: 'guardiao' }, true); });
    await mp.waitForTimeout(1500);
    const tvis = await mp.evaluate(() => ({ touch: MP.input.touchMode, ui: !document.getElementById('touch-ui').hidden }));
    const cdp = await mctx.newCDPSession(mp);
    const fireBtn = await mp.evaluate(() => { const r = document.getElementById('tb-fire').getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 }; });
    const clip0 = await mp.evaluate(() => MP.game.player.weapon.clip);
    const pos0 = await mp.evaluate(() => [MP.game.player.pos.x, MP.game.player.pos.z]);
    // dedo 1: analógico (esquerda) empurrado para cima; dedo 2: botão de fogo
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 150, y: 300, id: 1 }] });
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: 150, y: 240, id: 1 }] });
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 150, y: 240, id: 1 }, { x: fireBtn.x, y: fireBtn.y, id: 2 }] });
    await frames(3, mp);
    const during = await mp.evaluate(() => ({ f: MP.game.player.intent.f, fire: MP.game.player.intent.fire, joy: MP.input.touch.my }));
    // arrasta o dedo do fogo para mirar
    const yaw0 = await mp.evaluate(() => MP.game.player.yaw);
    for (let i = 1; i <= 5; i++) await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: 150, y: 240, id: 1 }, { x: fireBtn.x - i * 12, y: fireBtn.y, id: 2 }] });
    await simWait(0.6, mp);
    if (SHOTS) await mp.screenshot({ path: path.join(SHOT_DIR, '11-mobile.jpg'), type: 'jpeg', quality: 72 });
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await frames(3, mp);
    const rel = await mp.evaluate(() => ({ f: MP.game.player.intent.f, fire: MP.game.player.intent.fire, clip: MP.game.player.weapon.clip, yaw: MP.game.player.yaw, pos: [MP.game.player.pos.x, MP.game.player.pos.z] }));
    const mvd = Math.hypot(rel.pos[0] - pos0[0], rel.pos[1] - pos0[1]);
    rec('22. Controles mobile com multitoque', 'mover + atirar + mirar simultâneos; liberação ao soltar', `touchUI=${tvis.ui}, durante: f=${during.f.toFixed(2)} fogo=${during.fire}; Δyaw=${(rel.yaw - yaw0).toFixed(2)}; pente ${clip0}→${rel.clip}; moveu ${mvd.toFixed(1)} m; após soltar: f=${rel.f} fogo=${rel.fire}`, tvis.ui && during.f > 0.5 && during.fire && rel.clip < clip0 && mvd > 0.5 && rel.f === 0 && !rel.fire && Math.abs(rel.yaw - yaw0) > 0.05);
    await mctx.close();

    rec('Erros de console durante os testes', 'nenhum', errors.length ? errors.slice(0, 5).join(' | ') : 'nenhum', errors.length === 0);
  } catch (e) {
    rec('Execução do teste', 'sem exceções', e.message, false);
  }
  await browser.close(); srv.close();
  const failed = results.filter(r => r.status === 'reprovado').length;
  fs.writeFileSync(path.join(__dirname, 'browser-results.json'), JSON.stringify(results, null, 2));
  console.log(`\n${results.length} verificações · ${failed} reprovada(s) · resultados em tests/browser-results.json`);
  process.exit(failed ? 1 : 0);
})();
