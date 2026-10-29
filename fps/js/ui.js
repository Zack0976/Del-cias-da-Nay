/* Mirage Protocol — interface: HUD, radar, placar, menu de compra, menus, configurações, resultados e histórico. */
(function (root) {
  'use strict';
  const MP = root.MP;
  const { math: M, world, map, WEAPONS, GEAR } = MP;
  const ev = MP.events;
  const $ = (id) => document.getElementById(id);
  const DEG = Math.PI / 180;

  function fmtTime(s) { s = Math.max(0, Math.ceil(s)); return Math.floor(s / 60) + ':' + String(s % 60).padStart(2, '0'); }
  function esc(s) { return String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }
  const REASONS = { elim: 'Equipe eliminada', bomb: 'A bomba explodiu', defuse: 'Bomba desarmada', time: 'Tempo esgotado' };
  const TEAM_NAME = { T: 'TERRORISTAS', CT: 'CONTRA-TERRORISTAS' };

  const UI = MP.ui = {
    screen: null, setup: null, dmgMarks: [], cache: {}, buyCat: 0, lastSB: 0,
    settingsTab: 'controls', settingsReturn: null,

    init() {
      this.el = {};
      for (const id of ['hud', 'round-timer', 'round-label', 'bomb-ind', 'score-t', 'score-ct', 'alive-t', 'alive-ct', 'radar', 'location', 'killfeed', 'radio', 'crosshair', 'hitmarker', 'dmgind', 'center-msg', 'sub-msg', 'hint', 'action-wrap', 'action-label', 'action-bar', 'hp-val', 'ar-val', 'ar-ico', 'money', 'kit-ind', 'bomb-carry', 'weapon-name', 'ammo-clip', 'ammo-res', 'reload-wrap', 'reload-bar', 'ammo-warn', 'weapon-bar', 'death-panel', 'dp-killer', 'dp-detail', 'spectate', 'scope', 'flash', 'vignette', 'fps', 'scoreboard', 'buy-menu'])
        this.el[id] = $(id);
      this.radarCtx = this.el.radar.getContext('2d');
      this.dmgCtx = this.el.dmgind.getContext('2d');
      this.buildRadarBase();
      this.wireMenus();
      this.registerEvents();
      this.applyCrosshair();
      $('ver').textContent = 'v1.0';
    },

    // ------------------------------------------------------------- telas
    show(id) {
      for (const s of document.querySelectorAll('.screen')) if (s.id !== 'boot') s.classList.toggle('show', s.id === id);
      this.screen = id;
      if (id) MP.audio.setMenuMusic(id === 'menu-main' || id === 'menu-setup');
    },
    showOverlay(id, on) { const e = $(id); if (e) e.hidden = !on; },
    toast(msg, err) {
      const t = document.createElement('div'); t.className = 'toast' + (err ? ' err' : ''); t.textContent = msg;
      $('toasts').appendChild(t); setTimeout(() => t.remove(), err ? 6000 : 3000);
    },
    wireMenus() {
      const self = this;
      const on = (scr, act, fn) => { for (const b of document.querySelectorAll('#' + scr + ' [data-act="' + act + '"]')) b.addEventListener('click', () => { MP.audio.unlock(); MP.audio.ui('click'); fn(); }); };
      document.addEventListener('pointerover', e => { if (e.target.closest && e.target.closest('.btn') && e.pointerType === 'mouse') MP.audio.ui('hover'); });
      on('menu-main', 'play', () => this.openSetup('competitive'));
      on('menu-main', 'training', () => this.openSetup('training'));
      on('menu-main', 'free', () => this.openSetup('free'));
      on('menu-main', 'settings', () => this.openSettings('menu-main'));
      on('menu-main', 'tutorial', () => this.show('menu-tutorial'));
      on('menu-main', 'history', () => this.openHistory());
      on('menu-main', 'fullscreen', () => MP.main.toggleFullscreen());
      on('menu-setup', 'back', () => this.show('menu-main'));
      on('menu-setup', 'start', () => MP.main.startMatch(Object.assign({}, this.setup)));
      on('menu-pause', 'resume', () => MP.main.resume());
      on('menu-pause', 'settings', () => this.openSettings('menu-pause'));
      on('menu-pause', 'restart', () => MP.main.restartMatch());
      on('menu-pause', 'quit', () => MP.main.quitToMenu());
      on('menu-settings', 'close', () => this.closeSettings());
      on('menu-settings', 'reset', () => { MP.settings.reset(); this.renderSettings(); this.toast('Configurações restauradas.'); });
      on('menu-results', 'menu', () => MP.main.quitToMenu());
      on('menu-results', 'again', () => MP.main.restartMatch());
      on('menu-history', 'back', () => this.show('menu-main'));
      on('menu-history', 'clear', () => { MP.history.clear(); this.openHistory(); });
      on('menu-tutorial', 'back', () => { MP.settings.set('tutorialSeen', true); this.show(MP.main.pendingStart ? null : 'menu-main'); if (MP.main.pendingStart) MP.main.startMatch(MP.main.pendingStart, true); });
      // segmentados da configuração de partida
      for (const seg of document.querySelectorAll('#menu-setup .seg')) {
        seg.addEventListener('click', e => {
          const b = e.target.closest('button'); if (!b) return;
          const k = seg.dataset.key; let v = b.dataset.v;
          if (k === 'teamSize' || k === 'roundsToWin') v = +v;
          if (v === 'true') v = true; else if (v === 'false') v = false;
          this.setup[k] = v; this.refreshSetup(); MP.audio.ui('click');
        });
      }
      const sel = $('loadout-select');
      sel.innerHTML = '<option value="">— Padrão (pistola) —</option>' + MP.BUY_MENU.filter(c => c.cat !== 'Granadas' && c.cat !== 'Equipamento').map(c => '<optgroup label="' + c.cat + '">' + c.items.map(id => '<option value="' + id + '">' + WEAPONS[id].name + '</option>').join('') + '</optgroup>').join('');
      sel.addEventListener('change', () => { this.setup.loadout = sel.value || null; });
      $('buy-close').addEventListener('click', () => MP.main.toggleBuy(false));
      $('rotate-dismiss').addEventListener('click', () => { MP.main.rotateDismissed = true; $('rotate-hint').hidden = true; });
      $('set-tabs').addEventListener('click', e => { const b = e.target.closest('button'); if (!b) return; this.settingsTab = b.dataset.tab; this.renderSettings(); });
      $('weapon-bar').addEventListener('click', e => { const s = e.target.closest('.wslot'); if (s) MP.main.selectSlot(s.dataset.slot); });
    },
    openSetup(mode) {
      const s = MP.settings.values;
      this.setup = { mode, team: s.lastTeam, difficulty: s.lastDifficulty, teamSize: s.lastTeamSize, roundsToWin: s.lastRoundsToWin, dummiesMove: true, dummiesArmed: false, loadout: mode === 'competitive' ? null : 'brutus' };
      $('setup-title').textContent = mode === 'competitive' ? 'PARTIDA COMPETITIVA' : mode === 'training' ? 'CAMPO DE TIRO' : 'MODO LIVRE — EXPLORAR O MAPA';
      for (const e of document.querySelectorAll('#menu-setup .comp-only')) e.hidden = mode !== 'competitive';
      for (const e of document.querySelectorAll('#menu-setup .train-only')) e.hidden = mode !== 'training';
      for (const e of document.querySelectorAll('#menu-setup .noncomp')) e.hidden = mode === 'competitive';
      $('loadout-select').value = this.setup.loadout || '';
      this.refreshSetup();
      this.show('menu-setup');
    },
    refreshSetup() {
      for (const seg of document.querySelectorAll('#menu-setup .seg')) {
        const v = this.setup[seg.dataset.key];
        for (const b of seg.querySelectorAll('button')) b.classList.toggle('on', String(v) === b.dataset.v);
      }
    },

    // ------------------------------------------------------------- configurações
    openSettings(ret) { this.settingsReturn = ret; this.renderSettings(); this.show('menu-settings'); },
    closeSettings() { this.show(this.settingsReturn || 'menu-main'); },
    renderSettings() {
      for (const b of document.querySelectorAll('#set-tabs button')) b.classList.toggle('on', b.dataset.tab === this.settingsTab);
      const body = $('set-body'); const v = MP.settings.values; const tab = this.settingsTab;
      const slider = (k, label, min, max, step, fmt) => `<div class="row"><label>${label}</label><input type="range" data-k="${k}" min="${min}" max="${max}" step="${step}" value="${v[k]}"><span class="val" data-v="${k}">${fmt ? fmt(v[k]) : v[k]}</span></div>`;
      const seg = (k, label, opts) => `<div class="row"><label>${label}</label><div class="seg sseg" data-k="${k}">${opts.map(([val, txt]) => `<button data-v="${val}" class="${String(v[k]) === String(val) ? 'on' : ''}">${txt}</button>`).join('')}</div></div>`;
      const tog = (k, label) => seg(k, label, [[true, 'LIGADO'], [false, 'DESLIGADO']]);
      let h = '';
      if (tab === 'controls') {
        h += slider('mouseSens', 'Sensibilidade do mouse', 0.1, 5, 0.05, x => (+x).toFixed(2));
        h += slider('scopeSensMult', 'Sensibilidade na luneta', 0.2, 2, 0.05, x => (+x).toFixed(2));
        h += tog('invertY', 'Inverter eixo vertical');
        h += slider('fov', 'Campo de visão (FOV)', 60, 100, 1, x => x + '°');
        h += seg('shiftMode', 'Shift', [['walk', 'ANDAR (silencioso)'], ['run', 'CORRER (padrão anda)']]);
        h += tog('crouchToggle', 'Agachar alternado (teclado)');
        h += seg('crosshairColor', 'Cor da mira', MP.settings.schema.crosshairColor.values.map(c => [c, `<span style="color:${c}">■</span>`]));
      } else if (tab === 'video') {
        h += seg('quality', 'Qualidade gráfica', [['auto', 'AUTO'], ['low', 'BAIXA'], ['medium', 'MÉDIA'], ['high', 'ALTA']]);
        h += tog('shadows', 'Sombras');
        h += slider('renderScale', 'Escala de renderização', 0.4, 1, 0.05, x => Math.round(x * 100) + '%');
        h += seg('fpsLimit', 'Limite de FPS', [[0, 'SEM LIMITE'], [30, '30'], [60, '60'], [120, '120']]);
        h += tog('showFps', 'Mostrar FPS');
        h += `<div class="row"><label>Tela cheia</label><button class="btn small" id="set-fs">ALTERNAR TELA CHEIA</button></div>`;
        h += `<p class="note">Qualidade atual: <b>${MP.render.qKey}</b>. Antisserrilhamento é definido ao carregar a página.</p>`;
      } else if (tab === 'audio') {
        h += slider('volume', 'Volume geral', 0, 1, 0.05, x => Math.round(x * 100) + '%');
        h += slider('sfxVolume', 'Efeitos sonoros', 0, 1, 0.05, x => Math.round(x * 100) + '%');
        h += slider('musicVolume', 'Música e ambiente', 0, 1, 0.05, x => Math.round(x * 100) + '%');
        h += `<div class="row"><label>Teste</label><button class="btn small" id="set-test">TOCAR TIRO DE TESTE</button></div>`;
        if (MP.audio.error) h += `<p class="note">Áudio indisponível: ${esc(MP.audio.error)}</p>`;
      } else if (tab === 'touch') {
        h += seg('touchControls', 'Controles de toque', [['auto', 'AUTO'], ['on', 'SEMPRE'], ['off', 'DESLIGADOS']]);
        h += slider('touchSens', 'Sensibilidade do toque', 0.1, 5, 0.05, x => (+x).toFixed(2));
        h += slider('touchButtonScale', 'Tamanho dos botões', 0.6, 1.6, 0.05, x => Math.round(x * 100) + '%');
        h += slider('touchOpacity', 'Opacidade dos botões', 0.2, 1, 0.05, x => Math.round(x * 100) + '%');
        h += tog('vibration', 'Vibração');
        h += tog('invertY', 'Inverter eixo vertical');
        h += `<div class="row"><label>Layout</label><button class="btn small" id="set-touch-edit">REPOSICIONAR BOTÕES</button></div>`;
        h += `<p class="note">Toque detectado: ${MP.input.touchMode ? 'sim' : 'não'} · pontos de toque: ${navigator.maxTouchPoints || 0}</p>`;
      } else if (tab === 'diag') {
        const r = MP.render.renderer; const gl = r.getContext();
        let gpu = '—';
        try { const ext = gl.getExtension('WEBGL_debug_renderer_info'); if (ext) gpu = gl.getParameter(ext.UNMASKED_RENDERER_WEBGL); } catch (e) { gpu = 'indisponível'; }
        const info = r.info;
        h += `<div class="diag-box">WebGL: ${r.capabilities.isWebGL2 ? '2.0' : '1.0'}\nGPU: ${esc(gpu)}\nQualidade: ${MP.render.qKey} · pixel ratio ${r.getPixelRatio().toFixed(2)} · sombras ${r.shadowMap.enabled ? 'sim' : 'não'}\nChamadas de desenho (último quadro): ${info.render.calls} · triângulos: ${info.render.triangles}\nGeometrias: ${info.memory.geometries} · texturas: ${info.memory.textures}\nFPS médio: ${MP.main.fpsAvg.toFixed(1)}\nÁudio: ${MP.audio.ok ? 'ativo (' + MP.audio.ctx.sampleRate + ' Hz)' : (MP.audio.error || 'aguardando interação')}\nArmazenamento local: ${MP.storage.available ? 'disponível' : 'indisponível (configurações não serão salvas)'}\nAgentes na partida: ${world.agents.length}\nOuvintes de eventos 'shot': ${ev.count('shot')}\n\nErros registrados (${MP.diag.errors.length}):\n${MP.diag.errors.slice(-12).map(e => '• ' + esc(e.msg)).join('\n') || 'nenhum'}</div>`;
        h += `<div class="row"><button class="btn small" id="set-selftest">EXECUTAR AUTOTESTES</button><span class="note">${MP.game.mode === 'idle' ? '' : 'Disponível apenas fora de partida.'}</span></div><div class="diag-box" id="selftest-out" hidden></div>`;
      }
      body.innerHTML = h;
      for (const inp of body.querySelectorAll('input[type=range]')) {
        inp.addEventListener('input', () => {
          const k = inp.dataset.k; MP.settings.set(k, parseFloat(inp.value));
          const sp = body.querySelector('[data-v="' + k + '"]'); if (sp) sp.textContent = inp.parentNode.querySelector('.val').textContent = this.fmtSetting(k);
        });
      }
      for (const sg of body.querySelectorAll('.sseg')) {
        sg.addEventListener('click', e => {
          const b = e.target.closest('button'); if (!b) return;
          const k = sg.dataset.k; let val = b.dataset.v;
          const sch = MP.settings.schema[k];
          if (sch.type === 'bool') val = val === 'true'; else if (typeof sch.def === 'number' || (sch.values && typeof sch.values[0] === 'number')) val = +val;
          MP.settings.set(k, val); MP.audio.ui('click'); this.renderSettings();
        });
      }
      const fs = $('set-fs'); if (fs) fs.addEventListener('click', () => MP.main.toggleFullscreen());
      const tst = $('set-test'); if (tst) tst.addEventListener('click', () => { MP.audio.unlock(); MP.audio.gunshot(WEAPONS.brutus, null, true); });
      const te = $('set-touch-edit'); if (te) te.addEventListener('click', () => { this.show(null); MP.input.setEditing(true); });
      const st = $('set-selftest');
      if (st) st.addEventListener('click', () => {
        const out = $('selftest-out'); out.hidden = false;
        const res = MP.selftest.run();
        out.textContent = res.map(r => (r.ok ? '✔ ' : '✘ ') + r.name + (r.info ? ' — ' + r.info : '')).join('\n') + '\n\n' + res.filter(r => r.ok).length + '/' + res.length + ' aprovados';
      });
    },
    fmtSetting(k) {
      const v = MP.settings.values[k];
      if (k === 'fov') return v + '°';
      if (k === 'renderScale' || k === 'volume' || k === 'sfxVolume' || k === 'musicVolume' || k === 'touchButtonScale' || k === 'touchOpacity') return Math.round(v * 100) + '%';
      return (+v).toFixed(2);
    },
    applyCrosshair() { document.documentElement.style.setProperty('--ch', MP.settings.values.crosshairColor); },

    // ------------------------------------------------------------- histórico e resultados
    openHistory() {
      const list = MP.history.list();
      $('hist-body').innerHTML = list.length ? `<table class="hist"><tr><th>Data</th><th>Resultado</th><th>Placar T×CT</th><th>Equipe</th><th>Dificuldade</th><th>K/D/A</th><th>HS%</th><th>Precisão</th></tr>${list.map(h => `<tr><td>${new Date(h.date).toLocaleString('pt-BR')}</td><td class="${h.result || ''}">${(h.result || '—').toUpperCase()}</td><td>${h.score.T} × ${h.score.CT}</td><td>${h.playerTeam || '—'}</td><td>${h.difficulty}</td><td>${h.kills}/${h.deaths}/${h.assists}</td><td>${h.kills ? Math.round(h.hs / h.kills * 100) : 0}%</td><td>${h.shots ? Math.round(h.hits / h.shots * 100) : 0}%</td></tr>`).join('')}</table>` : '<p class="note">Nenhuma partida registrada ainda.</p>';
      this.show('menu-history');
    },
    showResults(res) {
      const p = MP.game.player;
      const t = $('res-title');
      const win = p && res.winner === p.team;
      t.textContent = res.winner === 'draw' ? 'EMPATE' : win ? 'VITÓRIA' : 'DERROTA';
      t.className = res.winner === 'draw' ? '' : win ? 'win' : 'lose';
      $('res-score').innerHTML = `<span style="color:var(--t)">T ${res.score.T}</span> × <span style="color:var(--ct)">${res.score.CT} CT</span>`;
      if (p) {
        const acc = p.shotsFired ? Math.round(p.shotsHit / p.shotsFired * 100) : 0;
        const hs = p.kills ? Math.round(p.headshots / p.kills * 100) : 0;
        $('res-stats').innerHTML = [['Abates', p.kills], ['Mortes', p.deaths], ['Assist.', p.assists], ['Dano', p.damageDealt], ['ADR', Math.round(p.damageDealt / Math.max(1, MP.game.roundNum))], ['HS%', hs + '%'], ['Precisão', acc + '%'], ['MVPs', p.mvps]].map(([k, v]) => `<div class="rstat"><b>${v}</b><span>${k}</span></div>`).join('');
      } else $('res-stats').innerHTML = '';
      $('res-tables').innerHTML = this.teamTable('T') + this.teamTable('CT');
      this.show('menu-results');
    },
    teamTable(team) {
      const rows = world.agents.filter(a => a.team === team).sort((a, b) => b.kills * 100 + b.damageDealt / 10 - (a.kills * 100 + a.damageDealt / 10));
      return `<table><tr><th>${TEAM_NAME[team]}</th><th class="n">$</th><th class="n">K</th><th class="n">A</th><th class="n">M</th><th class="n">DANO</th><th class="n">MVP</th></tr>${rows.map(a => `<tr class="${team}${a === MP.game.player ? ' me' : ''}${a.alive ? '' : ' dead'}"><td>${esc(a.name)}${a.isBot ? ' <small style="color:var(--muted)">BOT</small>' : ''}${a.inv.bomb ? ' 💣' : ''}</td><td class="n">${a.team === (MP.game.player && MP.game.player.team) || !MP.game.player ? a.money : '—'}</td><td class="n">${a.kills}</td><td class="n">${a.assists}</td><td class="n">${a.deaths}</td><td class="n">${a.damageDealt}</td><td class="n">${a.mvps ? '★' + a.mvps : ''}</td></tr>`).join('')}</table>`;
    },

    // ------------------------------------------------------------- placar
    showScoreboard(on) {
      this.el.scoreboard.hidden = !on;
      if (on && world.time - this.lastSB > 0.25) this.renderScoreboard();
    },
    renderScoreboard() {
      this.lastSB = world.time;
      const g = MP.game;
      $('sbt-score').textContent = g.score.T; $('sbct-score').textContent = g.score.CT;
      $('sb-table-t').outerHTML = '<table id="sb-table-t">' + this.teamTable('T').slice(7, -8) + '</table>';
      $('sb-table-ct').outerHTML = '<table id="sb-table-ct">' + this.teamTable('CT').slice(7, -8) + '</table>';
      $('sb-rounds').innerHTML = g.roundHistory.map(r => `<i class="${r.winner}" title="${REASONS[r.reason]}">${{ elim: '☠', bomb: '✹', defuse: '✂', time: '⏱' }[r.reason]}</i>`).join('');
      $('sb-map').textContent = g.mode === 'competitive' ? `MIRAGE PROTOCOL · DESARME · RODADA ${g.roundNum} · PRIMEIRO A ${g.config.roundsToWin}` : g.mode === 'training' ? 'CAMPO DE TIRO' : 'MODO LIVRE';
    },

    // ------------------------------------------------------------- compra
    renderBuy() {
      const p = MP.game.player; if (!p) return;
      const cats = MP.BUY_MENU;
      $('buy-cats').innerHTML = cats.map((c, i) => `<button data-i="${i}" class="${i === this.buyCat ? 'on' : ''}">${i + 1}. ${c.cat.toUpperCase()}</button>`).join('');
      for (const b of $('buy-cats').querySelectorAll('button')) b.onclick = () => { this.buyCat = +b.dataset.i; this.renderBuy(); MP.audio.ui('click'); };
      const cat = cats[this.buyCat];
      $('buy-items').innerHTML = cat.items.map((id, i) => {
        const it = MP.game.itemInfo(id); const chk = MP.game.checkBuy(p, id);
        const w = WEAPONS[id];
        let ds = '';
        if (w && w.dmg) ds = `Dano ${w.dmg}${w.pellets ? '×' + w.pellets : ''} · ${w.rpm} RPM · ${w.mag}/${w.reserve} · Recarga ${w.reload}s${w.reloadType === 'shell' ? '/cart.' : ''}`;
        else if (w && w.gtype) ds = { he: 'Explosão de fragmentação (até 98 de dano)', flash: 'Cega quem estiver olhando', smoke: 'Bloqueia a visão por 18 s', molotov: 'Área de fogo por 7 s' }[w.gtype];
        else ds = { vest: 'Reduz dano no corpo', vesthelm: 'Protege também a cabeça', kit: 'Desarme em 5 s' }[id] || '';
        const own = (w && w.slot && p.weaponIn(w.slot) && p.weaponIn(w.slot).id === id) || (id === 'kit' && p.inv.kit) || (id === 'vesthelm' && p.helmet && p.armor >= 100);
        const teamTag = it.team ? ` <small style="color:${it.team === 'T' ? 'var(--t)' : 'var(--ct)'}">${it.team}</small>` : '';
        return `<button class="bitem${chk.ok ? '' : ' no'}${own ? ' own' : ''}" data-id="${id}"><span class="nm">${esc(it.name)}${teamTag}<span class="key">${i + 1}</span></span><span class="pr">$${it.cost}</span><span class="ds">${ds}${!chk.ok && !own ? ' — ' + chk.reason : ''}</span></button>`;
      }).join('');
      for (const b of $('buy-items').querySelectorAll('.bitem')) b.onclick = () => this.doBuy(b.dataset.id);
      this.updateBuyHeader();
    },
    updateBuyHeader() {
      const p = MP.game.player; if (!p) return;
      $('buy-money').textContent = '$' + p.money;
      const left = MP.game.buyTimeLeft();
      $('buy-time').textContent = MP.game.mode !== 'competitive' ? 'Compras ilimitadas neste modo' : left > 0 ? 'Tempo de compra: ' + Math.ceil(left) + ' s' : 'Tempo de compra encerrado';
    },
    doBuy(id) {
      const p = MP.game.player;
      if (MP.game.buy(p, id)) { $('buy-msg').textContent = 'Comprado: ' + MP.game.itemInfo(id).name; }
      this.renderBuy();
    },
    buyByIndex(i) { const cat = MP.BUY_MENU[this.buyCat]; if (cat.items[i]) this.doBuy(cat.items[i]); },

    // ------------------------------------------------------------- eventos
    registerEvents() {
      const self = this;
      ev.on('kill', (k, v, wid, hs) => self.addKill(k, v, wid, hs), 'ui:kill');
      ev.on('radio', (a, msg) => self.addRadio(a, msg), 'ui:radio');
      ev.on('round:start', (n) => { const g = MP.game; self.center(g.mode === 'competitive' ? 'RODADA ' + n : '', '', 2.5); if (MP.game.player) self.sub(MP.game.player.team === 'T' ? 'Plante a bomba em A ou B · compre com B' : 'Defenda os bombsites · compre com B', 4); }, 'ui:rs');
      ev.on('round:live', () => self.center('VALENDO!', '', 1.2), 'ui:live');
      ev.on('round:end', (r) => { const p = MP.game.player; const cls = r.winner; self.center((r.winner === 'T' ? 'TERRORISTAS' : 'CONTRA-TERRORISTAS') + ' VENCEM', cls, 4.5); self.sub(REASONS[r.reason] + (r.mvp ? ' · MVP: ' + r.mvp : '') + (p ? (r.winner === p.team ? ' · VITÓRIA DA SUA EQUIPE' : ' · DERROTA DA SUA EQUIPE') : ''), 4.5); }, 'ui:re');
      ev.on('bomb:planted', (b) => { self.center('BOMBA PLANTADA', 'T', 2.5); self.sub('Site ' + b.site + ' · 40 segundos', 3); }, 'ui:bp');
      ev.on('bomb:defused', () => self.center('BOMBA DESARMADA', 'CT', 2.5), 'ui:bd');
      ev.on('bomb:carrier', (a) => { if (a === MP.game.player) self.toast('Você está com a bomba C-7. Leve-a até A ou B e segure E (USAR).'); }, 'ui:bc');
      ev.on('bomb:pickup', (a) => { if (a === MP.game.player) self.toast('Você pegou a bomba.'); else if (MP.game.player && a.team === MP.game.player.team) self.addRadio(a, 'Peguei a bomba!'); }, 'ui:bpk');
      ev.on('bomb:dropped', () => { const p = MP.game.player; if (p && p.team === 'T') self.addRadio(null, 'A bomba caiu!'); }, 'ui:bdr');
      ev.on('buy:fail', (a, id, reason) => { $('buy-msg').textContent = reason; if (self.el['buy-menu'].hidden) self.toast(reason); }, 'ui:bf');
      ev.on('buy', (a) => { if (a === MP.game.player) { self.flashMoney(); if (!self.el['buy-menu'].hidden) self.renderBuy(); } }, 'ui:buy');
      ev.on('hint', (t) => self.toast(t), 'ui:hint');
      ev.on('damage', (v, att, amt, group, from) => { if (v === MP.game.player && from) self.dmgMarks.push({ x: from.x, z: from.z, t: world.time, amt }); }, 'ui:dmg');
      ev.on('hitFlesh', (p, victim, att, dmg, group) => { if (att === MP.game.player) self.hitMarker(!victim.alive || victim.hp - dmg <= 0, group === 'head'); }, 'ui:hm');
      ev.on('settings:changed', (k) => { if (k === 'crosshairColor' || k === '*') self.applyCrosshair(); }, 'ui:set');
      ev.on('diag:error', (m) => { if (MP.main && MP.main.running) self.toast('Erro: ' + m, true); }, 'ui:err');
      ev.on('tplan', () => {}, 'ui:tplan');
    },
    center(text, cls, dur) {
      const e = this.el['center-msg']; e.textContent = text; e.className = (cls || '') + (text ? ' show' : '');
      clearTimeout(this._ct); if (text) this._ct = setTimeout(() => e.classList.remove('show'), dur * 1000);
    },
    sub(text, dur) { const e = this.el['sub-msg']; e.textContent = text; clearTimeout(this._st); this._st = setTimeout(() => { e.textContent = ''; }, dur * 1000); },
    addKill(k, v, wid, hs) {
      const kf = this.el.killfeed; const d = document.createElement('div');
      const p = MP.game.player;
      d.className = 'kf' + ((k === p || v === p) ? ' me' : '');
      const wname = WEAPONS[wid] ? WEAPONS[wid].name : wid === 'bomb' ? 'Explosão C-7' : wid;
      d.innerHTML = (k && k !== v ? `<span class="${k.team}">${esc(k.name)}</span>` : '') + `<span class="w">[${esc(wname)}]</span>` + (hs ? '<span class="hs">◉ HS</span>' : '') + `<span class="${v.team}">${esc(v.name)}</span>`;
      kf.prepend(d);
      while (kf.children.length > 6) kf.lastChild.remove();
      setTimeout(() => d.remove(), 7000);
    },
    addRadio(a, msg) {
      const p = MP.game.player;
      if (a && p && a.team !== p.team) return; // só ouve o próprio rádio
      const r = this.el.radio; const d = document.createElement('div'); d.className = 'rmsg';
      d.innerHTML = (a ? `<b class="${a.team}">${esc(a.name)}</b> (rádio): ` : '<b>Rádio:</b> ') + esc(msg);
      r.appendChild(d); while (r.children.length > 5) r.firstChild.remove();
      setTimeout(() => d.remove(), 6000);
    },
    hitMarker(kill, head) {
      const h = this.el.hitmarker; h.classList.toggle('kill', kill);
      h.style.transition = 'none'; h.style.opacity = '1';
      requestAnimationFrame(() => { h.style.transition = 'opacity 0.35s'; h.style.opacity = '0'; });
      MP.audio.hitmarker(head, kill);
      if (MP.settings.values.vibration && navigator.vibrate && MP.input.touchMode) { try { navigator.vibrate(kill ? 25 : 10); } catch (e) { MP.diag.log('vibrate'); } }
    },
    flashMoney() { const m = this.el.money; m.classList.remove('flash'); void m.offsetWidth; m.classList.add('flash'); },
    set(id, prop, val) {
      const key = id + '.' + prop;
      if (this.cache[key] === val) return;
      this.cache[key] = val;
      const e = this.el[id];
      if (prop === 'text') e.textContent = val; else if (prop === 'html') e.innerHTML = val; else if (prop === 'hidden') e.hidden = val; else if (prop === 'class') e.className = val; else e.style[prop] = val;
    },

    // ------------------------------------------------------------- HUD por quadro
    updateHUD(dt, view) {
      const g = MP.game, p = g.player, now = world.time;
      if (!p) return;
      // placar superior
      this.set('score-t', 'text', String(g.score.T)); this.set('score-ct', 'text', String(g.score.CT));
      let tl = 0, label = '';
      if (g.mode !== 'competitive') { tl = 0; label = g.mode === 'training' ? 'CAMPO DE TIRO' : 'MODO LIVRE'; }
      else if (g.phase === 'freeze') { tl = g.phaseEnd - now; label = 'COMPRAS · RODADA ' + g.roundNum; }
      else if (g.phase === 'live') { tl = g.phaseEnd - now; label = 'RODADA ' + g.roundNum; }
      else { tl = 0; label = 'FIM DA RODADA'; }
      const b = world.bomb;
      const planted = b.isPlanted;
      this.set('round-timer', 'text', g.mode !== 'competitive' ? '∞' : planted ? '— —' : fmtTime(tl));
      this.set('round-timer', 'class', (!planted && g.phase === 'live' && tl < 15) ? 'low' : '');
      this.set('round-label', 'text', label);
      this.set('bomb-ind', 'hidden', !planted);
      if (planted) this.set('bomb-ind', 'text', 'BOMBA · SITE ' + b.site);
      const alive = (team) => world.agents.filter(a => a.team === team).map(a => `<i class="${a.alive ? '' : 'dead'}"></i>`).join('');
      this.set('alive-t', 'html', alive('T')); this.set('alive-ct', 'html', alive('CT'));
      // vida, colete, dinheiro
      const tgt = view || p;
      this.set('hp-val', 'text', String(Math.max(0, tgt.hp)));
      this.set('ar-val', 'text', String(tgt.armor));
      this.set('ar-ico', 'text', tgt.helmet ? '⛑' : '⛉');
      this.el['hp-val'].parentNode.classList.toggle('low', tgt.hp <= 25);
      this.set('money', 'text', '$' + p.money);
      this.set('kit-ind', 'hidden', !(tgt.inv.kit));
      this.set('bomb-carry', 'hidden', !(tgt.inv.bomb));
      // arma e munição
      const def = tgt.activeDef, w = tgt.weapon;
      this.set('weapon-name', 'text', def.name + (tgt.active === 'grenade' ? ' ×' + tgt.inv.grenades[tgt.activeGrenade] : ''));
      if (w && def.mag) {
        this.set('ammo-clip', 'text', String(w.clip)); this.set('ammo-res', 'text', String(w.reserve));
        this.set('ammo-clip', 'class', w.clip <= Math.ceil(def.mag * 0.2) ? 'low' : '');
        const warn = w.reloading ? 'RECARREGANDO' : w.clip === 0 && w.reserve === 0 ? 'SEM MUNIÇÃO' : w.clip === 0 ? 'RECARREGUE [R]' : w.clip <= Math.ceil(def.mag * 0.2) ? 'MUNIÇÃO BAIXA' : '';
        this.set('ammo-warn', 'text', warn);
        this.set('reload-wrap', 'hidden', !w.reloading);
        if (w.reloading) this.el['reload-bar'].style.width = (w.reloadProgress(now) * 100).toFixed(1) + '%';
      } else {
        this.set('ammo-clip', 'text', tgt.active === 'grenade' ? String(tgt.inv.grenades[tgt.activeGrenade] || 0) : '—'); this.set('ammo-res', 'text', '—');
        this.set('ammo-clip', 'class', ''); this.set('ammo-warn', 'text', ''); this.set('reload-wrap', 'hidden', true);
      }
      // barra de armas
      const slots = [];
      const pushSlot = (slot, n, name) => slots.push(`<div class="wslot${tgt.active === slot ? ' on' : ''}" data-slot="${slot}"><b>${n}</b>${esc(name)}</div>`);
      if (tgt.inv.primary) pushSlot('primary', 1, tgt.inv.primary.def.name);
      if (tgt.inv.secondary) pushSlot('secondary', 2, tgt.inv.secondary.def.name);
      pushSlot('knife', 3, 'Faca');
      if (tgt.hasGrenades()) { const gr = tgt.inv.grenades; pushSlot('grenade', 4, 'Gran. ' + (gr.he ? 'HE ' : '') + (gr.flash ? 'FL' + (gr.flash > 1 ? '×2 ' : ' ') : '') + (gr.smoke ? 'SM ' : '') + (gr.molotov ? 'IN' : '')); }
      if (tgt.inv.bomb) pushSlot('bomb', 5, 'C-7');
      this.set('weapon-bar', 'html', slots.join(''));
      // mira dinâmica
      const ch = this.el.crosshair;
      const scoped = w && w.zoomLevel > 0;
      const showCh = tgt.alive && !scoped && def.cat !== 'sniper' && !(view && view !== p);
      ch.classList.toggle('hidden', !showCh && !(def.cat === 'sniper' && !scoped && tgt.alive));
      if (w && def.mag !== undefined && def.spread !== undefined) {
        const sp = tgt.currentSpread(w) + tgt.punchP * 0.25;
        const px = Math.tan(sp) / Math.tan(MP.render.camera.fov * DEG / 2) * (root.innerHeight / 2);
        ch.style.setProperty('--gap', Math.round(M.clamp(4 + px, 4, 60)) + 'px');
      } else ch.style.setProperty('--gap', '6px');
      this.set('scope', 'hidden', !scoped);
      // flash e dano
      const fa = tgt.flashAmount(now);
      this.set('flash', 'opacity', fa > 0 ? String(Math.min(1, fa * 1.1).toFixed(2)) : '0');
      const recent = now - tgt.lastDamageTime;
      this.set('vignette', 'opacity', String(M.clamp((recent < 0.6 ? (0.6 - recent) * 1.2 : 0) + (tgt.alive && tgt.hp < 30 ? 0.35 : 0), 0, 0.9).toFixed(2)));
      this.drawDamage(tgt);
      // dicas de interação e barra de ação
      const hint = g.interactionHint(p);
      const touch = MP.input.touchMode;
      this.set('hint', 'html', hint && p.alive ? hint.text.replace(/\bE\b/, touch ? '<b>USAR</b>' : '<b>E</b>') : (g.mode === 'competitive' && g.buyTimeLeft() > 0 && g.inBuyZone(p) && p.alive && g.phase !== 'post' ? (touch ? 'Toque em <b>$</b> para comprar' : 'Pressione <b>B</b> para comprar') : ''));
      MP.input.setContextButton('use', !!hint);
      MP.input.setVisible('buy', g.mode !== 'competitive' || (g.buyTimeLeft() > 0 && g.inBuyZone(p)));
      let act = null;
      if (b.state === 'planting' && b.planter === tgt) act = ['PLANTANDO A BOMBA', (now - b.plantStart) / MP.PLANT_TIME];
      else if (b.state === 'defusing' && b.defuser === tgt) act = ['DESARMANDO' + (tgt.inv.kit ? ' (KIT)' : ''), (now - b.defuseStart) / (b.defuseEnd - b.defuseStart)];
      this.set('action-wrap', 'hidden', !act);
      if (act) { this.set('action-label', 'text', act[0]); this.el['action-bar'].style.width = (M.clamp(act[1], 0, 1) * 100).toFixed(1) + '%'; }
      // morte / espectador
      this.set('death-panel', 'hidden', p.alive || g.mode !== 'competitive' && g.mode !== 'training');
      if (!p.alive) {
        const k = p.killer;
        this.set('dp-killer', 'html', k && k !== p ? `Eliminado por <b style="color:${k.team === 'T' ? 'var(--t)' : 'var(--ct)'}">${esc(k.name)}</b> (${k.hp} HP restante)` : 'Você morreu.');
        const dealt = k ? (k.damageLog.get(p) || 0) : 0; const taken = k ? (p.damageLog.get(k) || 0) : 0;
        this.set('dp-detail', 'text', k && k !== p ? `Dano causado nele: ${dealt} · Dano recebido: ${taken} · Arma: ${k.activeDef.name}` : '');
      }
      const spec = view && view !== p ? `ASSISTINDO: <b style="color:${view.team === 'T' ? 'var(--t)' : 'var(--ct)'}">${esc(view.name)}</b> · ${view.hp} HP · ${touch ? 'toque em FOGO' : 'clique'} para trocar` : (!p.alive && g.mode === 'competitive' ? 'Aguardando a próxima rodada…' : '');
      this.set('spectate', 'hidden', !spec);
      if (spec) this.set('spectate', 'html', spec);
      // local
      const z = map.zoneAt(tgt.pos.x, tgt.pos.z);
      this.set('location', 'text', z ? z.name : '—');
      // compra aberta
      if (!this.el['buy-menu'].hidden) this.updateBuyHeader();
      if (!this.el.scoreboard.hidden && now - this.lastSB > 0.5) this.renderScoreboard();
    },
    drawDamage(p) {
      const c = this.dmgCtx, now = world.time;
      c.clearRect(0, 0, 300, 300);
      this.dmgMarks = this.dmgMarks.filter(m => now - m.t < 1.6);
      for (const m of this.dmgMarks) {
        const ang = M.wrapAngle(Math.atan2(-(m.x - p.pos.x), -(m.z - p.pos.z)) - p.yaw);
        const a = M.clamp(1 - (now - m.t) / 1.6, 0, 1);
        c.save(); c.translate(150, 150); c.rotate(-ang);
        c.strokeStyle = `rgba(255,40,30,${(a * 0.9).toFixed(2)})`; c.lineWidth = 7 + Math.min(10, m.amt / 8);
        c.beginPath(); c.arc(0, 0, 110, -Math.PI / 2 - 0.35, -Math.PI / 2 + 0.35); c.stroke();
        c.restore();
      }
    },

    // ------------------------------------------------------------- radar
    buildRadarBase() {
      const S = 4; const cv = document.createElement('canvas'); cv.width = map.W * S; cv.height = map.H * S;
      const x = cv.getContext('2d');
      x.fillStyle = '#14181d'; x.fillRect(0, 0, cv.width, cv.height);
      for (let r = 0; r < map.H; r++) for (let c = 0; c < map.W; c++) {
        const cell = map.cellAt(c, r);
        if (cell.floor !== null) x.fillStyle = cell.ceil ? '#3a3f46' : cell.floor > 0 ? '#5d636b' : '#4b5159';
        else if (cell.ch === '#' || cell.ch === 'p') continue;
        else x.fillStyle = '#2a2f36';
        x.fillRect(c * S, r * S, S, S);
      }
      x.fillStyle = 'rgba(255,77,61,0.25)';
      for (const k of ['A', 'B']) { const z = map.plantZones[k]; x.fillRect(z.c0 * S, z.r0 * S, (z.c1 - z.c0 + 1) * S, (z.r1 - z.r0 + 1) * S); }
      x.fillStyle = '#ff7a5c'; x.font = 'bold 16px Arial'; x.textAlign = 'center'; x.textBaseline = 'middle';
      x.fillText('A', 8 * S, 9.5 * S); x.fillText('B', 40 * S, 9.5 * S);
      x.fillStyle = 'rgba(95,184,255,0.25)'; const ct = map.buyZones.CT; x.fillRect(ct.c0 * S, ct.r0 * S, (ct.c1 - ct.c0 + 1) * S, (ct.r1 - ct.r0 + 1) * S);
      x.fillStyle = 'rgba(232,176,74,0.25)'; const tt = map.buyZones.T; x.fillRect(tt.c0 * S, tt.r0 * S, (tt.c1 - tt.c0 + 1) * S, (tt.r1 - tt.r0 + 1) * S);
      this.radarBase = cv; this.radarScale = S / map.S; // px por metro
    },
    drawRadar(view) {
      const c = this.radarCtx, W = 220, g = MP.game, p = g.player; if (!p) return;
      const me = view || p;
      const k = this.radarScale * 1.25; // zoom
      c.setTransform(1, 0, 0, 1, 0, 0); c.clearRect(0, 0, W, W);
      c.save();
      c.beginPath(); c.arc(W / 2, W / 2, W / 2 - 2, 0, Math.PI * 2); c.clip();
      c.translate(W / 2, W / 2); c.rotate(me.yaw); c.scale(k, k);
      c.translate(-(me.pos.x - map.OX), -(me.pos.z - map.OZ));
      c.drawImage(this.radarBase, 0, 0, map.W * map.S, map.H * map.S);
      const dot = (a, col, r) => { c.fillStyle = col; c.beginPath(); c.arc(a.pos.x - map.OX, a.pos.z - map.OZ, r, 0, 7); c.fill(); };
      for (const a of world.agents) {
        if (a === me) continue;
        if (!a.alive) { if (a.team === p.team) { c.strokeStyle = '#888'; c.lineWidth = 0.4; const x0 = a.pos.x - map.OX, z0 = a.pos.z - map.OZ; c.beginPath(); c.moveTo(x0 - 0.8, z0 - 0.8); c.lineTo(x0 + 0.8, z0 + 0.8); c.moveTo(x0 + 0.8, z0 - 0.8); c.lineTo(x0 - 0.8, z0 + 0.8); c.stroke(); } continue; }
        if (a.team === p.team) dot(a, a.team === 'T' ? '#e8b04a' : '#5fb8ff', 1.1);
        else if (g.isSpotted(a) || g.mode !== 'competitive') dot(a, '#ff4d3d', 1.1);
      }
      const b = world.bomb;
      if (g.mode === 'competitive' && (p.team === 'T' || b.isPlanted)) {
        let bp = null;
        if (b.state === 'carried' && b.carrier && b.carrier !== me) bp = b.carrier.pos;
        else if (b.state === 'available' || b.isPlanted || b.state === 'planting') bp = b.state === 'planting' && b.planter ? b.planter.pos : b.pos;
        if (bp && (b.state !== 'carried')) { c.fillStyle = b.isPlanted && (world.time * 2) % 1 < 0.5 ? '#fff' : '#ff4d3d'; c.fillRect(bp.x - map.OX - 1, bp.z - map.OZ - 0.7, 2, 1.4); }
      }
      c.restore();
      // jogador no centro
      c.fillStyle = '#fff'; c.beginPath(); c.moveTo(W / 2, W / 2 - 7); c.lineTo(W / 2 + 5, W / 2 + 5); c.lineTo(W / 2 - 5, W / 2 + 5); c.closePath(); c.fill();
      c.strokeStyle = 'rgba(255,255,255,0.25)'; c.lineWidth = 2; c.beginPath(); c.arc(W / 2, W / 2, W / 2 - 2, 0, 7); c.stroke();
    }
  };
})(typeof window !== 'undefined' ? window : globalThis);
