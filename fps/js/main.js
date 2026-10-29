/* Mirage Protocol — inicialização, laço principal (passo fixo), controle do jogador, câmera, espectador e fluxo de telas. */
(function (root) {
  'use strict';
  const MP = root.MP;
  const { V3, math: M, world, map } = MP;
  const ev = MP.events;
  const $ = (id) => document.getElementById(id);
  const DEG = Math.PI / 180;
  const STEP = 1 / 60;

  const main = MP.main = {
    running: false, loopStarted: false, paused: false, inMatch: false, lastCfg: null,
    acc: 0, last: 0, lastRender: 0, fpsAvg: 60, fpsFrames: 0, fpsTime: 0, lowFpsTime: 0,
    thirdPerson: false, specIndex: 0, specTarget: null, rotateDismissed: false, pendingStart: null,
    lookFrame: { dx: 0, dy: 0 }, shakeT: 0,

    // ------------------------------------------------------------- inicialização com diagnóstico
    boot() {
      const status = $('boot-status'), bar = $('boot-bar');
      const step = (t, p) => { status.textContent = t; bar.style.width = p + '%'; };
      try {
        step('Verificando WebGL…', 10);
        if (typeof root.THREE === 'undefined') throw new Error('A biblioteca Three.js (lib/three.min.js) não foi carregada. Verifique se a pasta "lib" está junto do index.html.');
        const test = document.createElement('canvas');
        const gl = test.getContext('webgl2') || test.getContext('webgl') || test.getContext('experimental-webgl');
        if (!gl) throw new Error('Seu navegador/dispositivo não oferece WebGL. Ative a aceleração de hardware nas configurações do navegador ou use um navegador atualizado (Chrome, Edge, Firefox, Safari).');
        step('Criando renderizador e texturas procedurais…', 30);
        const canvas = $('game');
        MP.render.init(canvas);
        step('Construindo efeitos e modelos…', 60);
        MP.fx.init();
        this.viewmodel = new MP.models.Viewmodel(MP.render.vmScene, MP.render.vmCamera);
        step('Preparando áudio, controles e interface…', 80);
        MP.audio.register();
        MP.input.init(canvas);
        MP.ui.init();
        this.registerEvents();
        root.addEventListener('resize', () => this.onResize());
        root.addEventListener('orientationchange', () => setTimeout(() => this.onResize(), 200));
        this.onResize();
        // cenário de fundo do menu: câmera orbitando o mapa
        step('Pronto.', 100);
        $('boot').classList.remove('show');
        MP.ui.show('menu-main');
        this.running = true;
        this.startLoop();
        document.addEventListener('pointerdown', () => MP.audio.unlock(), { once: true });
        document.addEventListener('keydown', () => MP.audio.unlock(), { once: true });
      } catch (e) {
        MP.diag.error('inicialização', e);
        $('boot-error').hidden = false;
        $('boot-error').textContent = 'Falha ao iniciar o Mirage Protocol:\n\n' + (e && e.message ? e.message : e) + '\n\nDetalhes técnicos:\n' + (e && e.stack ? e.stack : '—');
        status.textContent = 'Erro de inicialização';
        $('boot-retry').hidden = false;
        $('boot-retry').onclick = () => location.reload();
      }
    },
    registerEvents() {
      const self = this;
      ev.on('weapon:switch', (a, def) => { if (a === MP.game.player) { self.viewmodel.set(def, a.team); self.viewmodel.inspectT = 1; } }, 'main:sw');
      ev.on('fired', (a, w) => { if (a === MP.game.player) { self.viewmodel.onFire(w.def); if (MP.settings.values.vibration && MP.input.touchMode && navigator.vibrate && w.def.cat !== 'smg') { try { navigator.vibrate(6); } catch (e) { MP.diag.log('vib'); } } } }, 'main:fired');
      ev.on('knife', (a, alt) => { if (a === MP.game.player) self.viewmodel.onSlash(alt); }, 'main:knife');
      ev.on('grenade:throw', (g) => { if (g.owner === MP.game.player) self.viewmodel.onThrow(); }, 'main:thr');
      ev.on('match:start', () => { const p = MP.game.player; if (p) self.viewmodel.set(p.activeDef, p.team); self.specTarget = null; }, 'main:ms');
      ev.on('round:start', () => { const p = MP.game.player; if (p) self.viewmodel.set(p.activeDef, p.team); self.specTarget = null; self.deathCamDone = false; }, 'main:rs');
      ev.on('agent:respawn', (a) => { if (a === MP.game.player) self.viewmodel.set(a.activeDef, a.team); }, 'main:resp');
      ev.on('match:end', (res) => { self.inMatch = false; MP.input.enabled = false; MP.input.exitLock(); MP.input.showTouch(false); MP.ui.toggleOff && MP.ui.toggleOff(); self.toggleBuy(false); MP.ui.showScoreboard(false); setTimeout(() => MP.ui.showResults(res), 600); }, 'main:me');
      ev.on('input:unlocked', () => { if (self.inMatch && !self.paused && !MP.input.touchMode && !self.buyOpen && !self.ignoreUnlock) self.pause(); self.ignoreUnlock = false; }, 'main:unl');
      ev.on('input:lockerror', () => { if (self.inMatch && !MP.input.touchMode) MP.ui.toast('Clique na tela para capturar o mouse.'); }, 'main:lerr');
      ev.on('app:hidden', () => { if (self.inMatch && !self.paused) self.pause(); }, 'main:hid');
      ev.on('key', (code) => self.onKey(code), 'main:key');
      ev.on('settings:changed', (k) => {
        if (k === 'fov' || k === '*') { MP.render.camera.fov = MP.settings.values.fov; MP.render.camera.updateProjectionMatrix(); }
        if (k === 'quality' || k === 'shadows' || k === 'renderScale' || k === '*') { MP.render.autoScale = 1; MP.render.applyQuality(); }
        if (k === 'showFps' || k === '*') $('fps').hidden = !MP.settings.values.showFps;
      }, 'main:set');
      ev.on('gl:lost', () => { if (self.inMatch && !self.paused) self.pause(); MP.ui.toast('O contexto gráfico (WebGL) foi perdido. Tentando restaurar…', true); }, 'main:gll');
      ev.on('gl:restored', () => MP.ui.toast('Contexto gráfico restaurado.'), 'main:glr');
      ev.on('input:editdone', () => { MP.ui.openSettings(self.inMatch ? 'menu-pause' : 'menu-main'); MP.ui.settingsTab = 'touch'; MP.ui.renderSettings(); if (!self.inMatch) MP.input.showTouch(false); }, 'main:edit');
      $('fps').hidden = !MP.settings.values.showFps;
    },
    onResize() {
      MP.render.resize();
      const portrait = root.innerHeight > root.innerWidth;
      $('rotate-hint').hidden = !(portrait && MP.input.touchMode && this.inMatch && !this.rotateDismissed);
    },

    // ------------------------------------------------------------- fluxo de partida
    startMatch(cfg, skipTutorial) {
      MP.audio.unlock();
      const s = MP.settings;
      if (cfg.mode === 'competitive') { s.set('lastTeam', cfg.team); s.set('lastDifficulty', cfg.difficulty); s.set('lastTeamSize', cfg.teamSize); s.set('lastRoundsToWin', cfg.roundsToWin); }
      if (!s.values.tutorialSeen && !skipTutorial) { this.pendingStart = cfg; MP.ui.show('menu-tutorial'); return; }
      this.pendingStart = null;
      this.lastCfg = Object.assign({}, cfg);
      MP.game.start(cfg);
      this.inMatch = true; this.paused = false; MP.game.paused = false;
      this.acc = 0;
      MP.ui.show(null);
      $('hud').hidden = false;
      MP.input.enabled = true;
      MP.input.showTouch(true);
      if (MP.input.touchMode) this.enterFullscreen(); else MP.input.requestLock();
      this.onResize();
      MP.audio.setMenuMusic(false);
    },
    restartMatch() { if (this.lastCfg) { this.paused = false; this.startMatch(Object.assign({}, this.lastCfg), true); } },
    quitToMenu() {
      MP.game.stop();
      this.inMatch = false; this.paused = false;
      $('hud').hidden = true; MP.input.enabled = false; MP.input.exitLock(); MP.input.showTouch(false);
      this.toggleBuy(false); MP.ui.showScoreboard(false);
      MP.ui.show('menu-main'); this.onResize();
    },
    pause() {
      if (!this.inMatch || this.paused) return;
      this.paused = true; MP.game.paused = true;
      this.toggleBuy(false); MP.ui.showScoreboard(false);
      MP.input.releaseAll(); MP.input.exitLock(); MP.input.showTouch(false);
      MP.ui.show('menu-pause');
    },
    resume() {
      if (!this.inMatch) return;
      this.paused = false; MP.game.paused = false;
      MP.ui.show(null); MP.input.showTouch(true);
      if (!MP.input.touchMode) MP.input.requestLock();
      this.last = performance.now();
    },
    toggleBuy(on) {
      const p = MP.game.player;
      if (on === undefined) on = !this.buyOpen;
      if (on) {
        const chk = MP.game.canBuyNow(p);
        if (!chk.ok) { MP.ui.toast(chk.reason); MP.audio.ui('deny'); return; }
      }
      this.buyOpen = !!on;
      $('buy-menu').hidden = !on;
      if (on) { MP.ui.renderBuy(); if (!MP.input.touchMode) { this.ignoreUnlock = true; MP.input.exitLock(); } }
      else if (this.inMatch && !this.paused && !MP.input.touchMode && MP.ui.screen === null) MP.input.requestLock();
    },
    enterFullscreen() {
      const d = document.documentElement;
      const req = d.requestFullscreen || d.webkitRequestFullscreen;
      if (!req || document.fullscreenElement || document.webkitFullscreenElement) return;
      try {
        const pr = req.call(d, { navigationUI: 'hide' });
        const lock = () => { if (screen.orientation && screen.orientation.lock) screen.orientation.lock('landscape').catch(() => MP.diag.log('orientação não travada')); };
        if (pr && pr.then) pr.then(lock).catch(() => MP.diag.log('tela cheia negada')); else lock();
      } catch (e) { MP.diag.log('fullscreen: ' + e.message); }
    },
    toggleFullscreen() {
      if (document.fullscreenElement || document.webkitFullscreenElement) { (document.exitFullscreen || document.webkitExitFullscreen).call(document); return; }
      const d = document.documentElement;
      if (!d.requestFullscreen && !d.webkitRequestFullscreen) { MP.ui.toast('Tela cheia não suportada aqui. No iPhone: Compartilhar → "Adicionar à Tela de Início".'); return; }
      this.enterFullscreen();
    },
    selectSlot(slot) {
      const p = MP.game.player; if (!p || !p.alive) return;
      p.switchTo(slot, null, world.time);
    },
    onKey(code) {
      if (!this.inMatch) { if (code === 'Escape' && MP.ui.screen && MP.ui.screen !== 'menu-main') { if (MP.ui.screen === 'menu-settings') MP.ui.closeSettings(); else MP.ui.show('menu-main'); } return; }
      if (code === 'Escape') {
        if (this.buyOpen) { this.toggleBuy(false); return; }
        if (MP.ui.screen === 'menu-settings') { MP.ui.closeSettings(); return; }
        if (this.paused) this.resume(); else this.pause();
        return;
      }
      if (this.paused) return;
      if (code === 'KeyB') this.toggleBuy();
      if (this.buyOpen && /^Digit[1-9]$/.test(code)) { MP.ui.buyByIndex(+code.slice(5) - 1); MP.input.edges.delete(code); }
    },

    // ------------------------------------------------------------- jogador
    updatePlayerInput(dt) {
      const g = MP.game, p = g.player, inp = MP.input, s = MP.settings.values, now = world.time;
      if (!p) return;
      const t = inp.touch;
      const tEdge = (b) => t.edges.has(b);
      const menuBlock = this.buyOpen;
      // olhar
      const w = p.weapon;
      let zoomMul = 1;
      if (w && w.zoomLevel > 0 && w.def.zoom) zoomMul = (w.def.zoom[w.zoomLevel - 1] / s.fov) * s.scopeSensMult;
      const base = inp.touchMode ? 0.0042 * s.touchSens : 0.0011 * s.mouseSens * 2;
      const dx = inp.look.dx, dy = inp.look.dy;
      this.lookFrame.dx = dx; this.lookFrame.dy = dy;
      if (p.alive && !menuBlock) {
        p.yaw = M.wrapAngle(p.yaw - dx * base * zoomMul);
        p.pitch = M.clamp(p.pitch - dy * base * zoomMul * (s.invertY ? -1 : 1), -88 * DEG, 88 * DEG);
      }
      const it = p.intent;
      const key = (c) => inp.held(c);
      let f = (key('KeyW') || key('ArrowUp') ? 1 : 0) - (key('KeyS') || key('ArrowDown') ? 1 : 0);
      let r = (key('KeyD') || key('ArrowRight') ? 1 : 0) - (key('KeyA') || key('ArrowLeft') ? 1 : 0);
      if (inp.touchMode) { f += -t.my; r += t.mx; }
      it.f = M.clamp(f, -1, 1); it.r = M.clamp(r, -1, 1);
      const shift = key('ShiftLeft') || key('ShiftRight');
      it.walk = inp.touchMode ? t.walkToggle : (s.shiftMode === 'walk' ? shift : !shift);
      if (s.crouchToggle && (inp.edge('ControlLeft') || inp.edge('KeyC'))) this.crouchLatch = !this.crouchLatch;
      it.crouch = inp.touchMode ? t.crouchToggle : s.crouchToggle ? !!this.crouchLatch : (key('ControlLeft') || key('ControlRight') || key('KeyC'));
      it.jump = key('Space') || !!t.held.jump;
      it.use = key('KeyE') || !!t.held.use;
      const firing = (inp.mouse.left && inp.locked) || !!t.held.fire || !!t.held.fire2;
      it.fire = p.alive && !menuBlock && firing && !(g.phase === 'freeze');
      inp.setToggle('crouch', t.crouchToggle); inp.setToggle('walk', t.walkToggle);
      if (!p.alive) {
        // espectador: troca de alvo
        if ((inp.mouse.leftEdge && inp.locked) || tEdge('fire') || tEdge('fire2') || inp.edge('Space')) this.nextSpectate();
        return;
      }
      if (menuBlock) return;
      // ações de borda
      if ((inp.mouse.rightEdge && inp.locked) || tEdge('aim')) p.altAction(now);
      if (inp.edge('KeyR') || tEdge('reload')) p.startReload(now);
      if (inp.edge('KeyF')) this.viewmodel.inspect();
      if (inp.edge('Digit1')) p.switchTo('primary', null, now);
      if (inp.edge('Digit2')) p.switchTo('secondary', null, now);
      if (inp.edge('Digit3')) p.switchTo('knife', null, now);
      if (inp.edge('Digit4') || inp.edge('KeyG') || tEdge('grenade')) p.switchTo('grenade', null, now);
      if (inp.edge('Digit5')) p.switchTo('bomb', null, now);
      if (inp.edge('KeyQ')) { const prev = p.prevSlot; if (prev && p.weaponIn(prev) && prev !== p.active) p.switchTo(prev, null, now); }
      if (inp.wheel || tEdge('switch')) this.cycleWeapon(p, inp.wheel < 0 ? -1 : 1, now);
      if (tEdge('buy')) this.toggleBuy();
      if (tEdge('pause')) this.pause();
    },
    cycleWeapon(p, dir, now) {
      const order = ['primary', 'secondary', 'knife', 'grenade', 'bomb'].filter(sl => sl === 'grenade' ? p.hasGrenades() : p.canSwitchTo(sl));
      let i = order.indexOf(p.active);
      i = (i + dir + order.length) % order.length;
      p.switchTo(order[i], null, now);
    },
    nextSpectate() {
      const p = MP.game.player;
      const mates = world.agents.filter(a => a.alive && a !== p && a.team === p.team);
      if (!mates.length) { this.specTarget = null; return; }
      this.specIndex = (this.specIndex + 1) % mates.length;
      this.specTarget = mates[this.specIndex];
    },

    // ------------------------------------------------------------- câmera
    updateCamera(dt) {
      const g = MP.game, p = g.player, cam = MP.render.camera, s = MP.settings.values;
      let fov = s.fov;
      this.thirdPerson = false;
      let hide = p;
      if (!this.inMatch || !p) {
        // órbita cinematográfica no menu
        const t = performance.now() / 1000 * 0.05;
        cam.position.set(Math.sin(t) * 42, 30, Math.cos(t) * 34);
        cam.lookAt(0, 0, 0);
        return { hide: null, view: null };
      }
      const shake = MP.fx.shake; MP.fx.shake = Math.max(0, MP.fx.shake - dt * 1.6);
      const sx = (Math.random() - 0.5) * shake * 0.04, sy = (Math.random() - 0.5) * shake * 0.04;
      if (p.alive) {
        const eye = p.eyePos(this._eye || (this._eye = new V3()));
        const bob = p.onGround ? Math.sin(this.viewmodel.bob) * 0.025 * Math.min(1, p.speedNow / 6) : 0;
        cam.position.set(eye.x, eye.y + bob, eye.z);
        cam.rotation.set(p.pitch + p.punchP + sy, p.yaw + p.punchY + sx, 0);
        const w = p.weapon;
        if (w && w.zoomLevel > 0 && w.def.zoom) fov = w.def.zoom[w.zoomLevel - 1];
        return { hide: p, view: p };
      }
      // morto: câmera de morte por 2 s, depois espectador
      const since = world.time - p.deathTime;
      if (since < 2 || g.mode !== 'competitive') {
        const k = M.clamp(since / 0.8, 0, 1);
        cam.position.set(p.pos.x, p.pos.y + M.lerp(1.6, 0.35, k), p.pos.z);
        let yaw = p.yaw, pitch = M.lerp(p.pitch, -0.2, k);
        if (p.killer && p.killer !== p && p.killer.alive) { const ke = p.killer.eyePos(new V3()); yaw = M.yawTo(p.pos, ke); pitch = M.pitchTo(new V3(p.pos.x, p.pos.y + 0.35, p.pos.z), ke); }
        cam.rotation.set(pitch, yaw, k * 0.4);
        MP.render.camera.fov = M.lerp(cam.fov, fov, Math.min(1, dt * 12)); cam.updateProjectionMatrix();
        return { hide: p, view: p };
      }
      if (!this.specTarget || !this.specTarget.alive) { this.specTarget = null; this.nextSpectate(); }
      const tg = this.specTarget;
      if (tg) {
        this.thirdPerson = true;
        const e = tg.eyePos(new V3());
        const back = M.dirFromAngles(tg.yaw, tg.pitch * 0.5);
        const o = new V3(e.x, e.y + 0.3, e.z);
        const d = new V3(-back.x, -back.y, -back.z);
        const h = map.raycast(o, d, 3);
        const dist = h ? Math.max(0.3, h.t - 0.25) : 3;
        cam.position.set(o.x + d.x * dist, o.y + d.y * dist + 0.2, o.z + d.z * dist);
        cam.rotation.set(tg.pitch * 0.5 - 0.1, tg.yaw, 0);
        hide = null;
        cam.fov = M.lerp(cam.fov, s.fov, Math.min(1, dt * 12)); cam.updateProjectionMatrix();
        return { hide, view: tg };
      }
      // ninguém vivo: visão aérea
      const t = performance.now() / 1000 * 0.08;
      cam.position.set(Math.sin(t) * 30, 34, Math.cos(t) * 26); cam.lookAt(0, 0, 0);
      return { hide: null, view: p };
    },
    viewmodelMuzzleWorld(out) {
      const vm = this.viewmodel; if (!vm.weapon || !vm.root.visible) return null;
      const m = vm.weapon.userData.muzzle; if (!m) return null;
      const THREE = root.THREE;
      const v = this._mv || (this._mv = new THREE.Vector3());
      m.getWorldPosition(v);
      v.applyMatrix4(MP.render.camera.matrixWorld);
      out.copy(v); return out;
    },

    // ------------------------------------------------------------- laço
    startLoop() {
      if (this.loopStarted) return; // nunca cria dois laços
      this.loopStarted = true;
      this.last = performance.now();
      const frame = (ts) => {
        requestAnimationFrame(frame);
        try { this.tick(ts); } catch (e) { MP.diag.error('laço principal', e); }
      };
      requestAnimationFrame(frame);
    },
    tick(ts) {
      const s = MP.settings.values;
      this.frameNo = (this.frameNo || 0) + 1;
      if (s.fpsLimit > 0 && ts - this.lastRender < 1000 / s.fpsLimit - 1.5) return;
      let dt = (ts - this.last) / 1000; this.last = ts; this.lastRender = ts;
      if (!(dt > 0)) dt = STEP;
      dt = Math.min(dt, 0.1);
      // FPS médio e ajuste automático de resolução
      this.fpsFrames++; this.fpsTime += dt;
      if (this.fpsTime >= 1) {
        this.fpsAvg = this.fpsFrames / this.fpsTime; this.fpsFrames = 0; this.fpsTime = 0;
        if (s.showFps) $('fps').textContent = this.fpsAvg.toFixed(0) + ' FPS · ' + MP.render.qKey;
        if (s.quality === 'auto' && this.inMatch && !this.paused) {
          const R = MP.render; R.autoScale = R.autoScale || 1;
          if (this.fpsAvg < 28 && R.autoScale > 0.55) { this.lowFpsTime++; if (this.lowFpsTime >= 3) { R.autoScale *= 0.85; R.applyQuality(); this.lowFpsTime = 0; } }
          else { this.lowFpsTime = 0; if (this.fpsAvg > 57 && R.autoScale < 1) { R.autoScale = Math.min(1, R.autoScale * 1.05); R.applyQuality(); } }
        }
      }
      const g = MP.game;
      if (this.inMatch && !this.paused && g.mode !== 'idle') {
        this.updatePlayerInput(dt);
        this.acc += dt;
        let n = 0;
        while (this.acc >= STEP && n < 6) { g.update(STEP); this.acc -= STEP; n++; }
        if (n === 6) this.acc = 0;
        const sb = (MP.input.held('Tab') || !!MP.input.touch.held.score) && g.mode !== 'idle';
        MP.ui.showScoreboard(sb);
      }
      MP.input.endFrame();
      const camInfo = this.updateCamera(dt);
      const R = MP.render;
      const p = g.player;
      // listener de áudio acompanha a câmera
      MP.audio.setListener(R.camera.position.x, R.camera.position.y, R.camera.position.z, R.camera.rotation.y);
      if (MP.audio.ok) MP.audio.updateLoops();
      // FOV (luneta) suave
      if (p && p.alive && this.inMatch) {
        const w = p.weapon; const target = w && w.zoomLevel > 0 && w.def.zoom ? w.def.zoom[w.zoomLevel - 1] : s.fov;
        if (Math.abs(R.camera.fov - target) > 0.05) { R.camera.fov = M.lerp(R.camera.fov, target, Math.min(1, dt * 18)); R.camera.updateProjectionMatrix(); }
      }
      R.camera.updateMatrixWorld();
      MP.fx.update(dt, R.camera.position, camInfo.hide && !this.thirdPerson ? camInfo.hide : null);
      const showVM = !!(p && p.alive && this.inMatch && !this.thirdPerson);
      if (showVM) this.viewmodel.update(dt, p, this.lookFrame);
      if (this.inMatch && p) {
        MP.ui.updateHUD(dt, camInfo.view);
        this.radarT = (this.radarT || 0) + dt;
        if (this.radarT > 0.066) { this.radarT = 0; MP.ui.drawRadar(camInfo.view); }
      }
      R.frame(showVM);
    }
  };

  if (typeof document !== 'undefined') {
    root.addEventListener('error', (e) => MP.diag.error('janela', e.error || e.message));
    root.addEventListener('unhandledrejection', (e) => MP.diag.error('promessa', e.reason));
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => main.boot()); else main.boot();
  }
})(typeof window !== 'undefined' ? window : globalThis);
