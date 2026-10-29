/* Mirage Protocol — entrada: teclado + mouse (Pointer Lock) e controles de toque multitoque (Pointer Events). */
(function (root) {
  'use strict';
  const MP = root.MP;
  const { math: M } = MP;

  const DEFAULT_TOUCH = {
    fire: { x: 0.86, y: 0.62 }, fire2: { x: 0.07, y: 0.56 }, aim: { x: 0.94, y: 0.40 }, reload: { x: 0.74, y: 0.80 },
    jump: { x: 0.94, y: 0.82 }, crouch: { x: 0.84, y: 0.90 }, walk: { x: 0.30, y: 0.90 }, use: { x: 0.72, y: 0.55 },
    switch: { x: 0.74, y: 0.36 }, grenade: { x: 0.64, y: 0.88 }, buy: { x: 0.18, y: 0.07 }, score: { x: 0.24, y: 0.07 }, pause: { x: 0.30, y: 0.07 }
  };

  const I = MP.input = {
    keys: new Set(), edges: new Set(), look: { dx: 0, dy: 0 }, wheel: 0,
    mouse: { left: false, right: false, leftEdge: false, rightEdge: false },
    locked: false, lockWanted: false, touchMode: false, enabled: false,
    touch: { mx: 0, my: 0, held: {}, edges: new Set(), crouchToggle: false, walkToggle: false },
    pointers: new Map(), editing: false,

    init(canvas) {
      this.canvas = canvas;
      const s = MP.settings.values;
      this.touchMode = s.touchControls === 'on' || (s.touchControls === 'auto' && (('ontouchstart' in root) || (navigator.maxTouchPoints > 0 && matchMedia('(pointer: coarse)').matches)));
      document.body.classList.toggle('touch', this.touchMode);
      root.addEventListener('keydown', e => this.onKey(e, true), { passive: false });
      root.addEventListener('keyup', e => this.onKey(e, false));
      root.addEventListener('blur', () => this.releaseAll());
      document.addEventListener('visibilitychange', () => { if (document.hidden) { this.releaseAll(); MP.events.emit('app:hidden'); } });
      document.addEventListener('mousemove', e => {
        if (!this.locked) return;
        // filtra saltos anômalos de alguns navegadores ao travar o ponteiro
        if (Math.abs(e.movementX) > 400 || Math.abs(e.movementY) > 400) return;
        this.look.dx += e.movementX; this.look.dy += e.movementY;
      });
      canvas.addEventListener('mousedown', e => {
        if (this.touchMode) return;
        if (!this.locked && this.enabled) { this.requestLock(); return; }
        if (e.button === 0) { if (!this.mouse.left) this.mouse.leftEdge = true; this.mouse.left = true; }
        if (e.button === 2) { if (!this.mouse.right) this.mouse.rightEdge = true; this.mouse.right = true; }
      });
      root.addEventListener('mouseup', e => { if (e.button === 0) this.mouse.left = false; if (e.button === 2) this.mouse.right = false; });
      canvas.addEventListener('contextmenu', e => e.preventDefault());
      document.addEventListener('contextmenu', e => { if (this.enabled) e.preventDefault(); });
      canvas.addEventListener('wheel', e => { if (this.locked) { this.wheel += Math.sign(e.deltaY); e.preventDefault(); } }, { passive: false });
      document.addEventListener('pointerlockchange', () => {
        const was = this.locked;
        this.locked = document.pointerLockElement === canvas;
        if (was && !this.locked) { this.releaseAll(); MP.events.emit('input:unlocked'); }
      });
      document.addEventListener('pointerlockerror', () => { this.locked = false; MP.events.emit('input:lockerror'); });
      // gestos do iOS que interrompem a partida
      document.addEventListener('gesturestart', e => e.preventDefault());
      document.addEventListener('dblclick', e => e.preventDefault());
      this.initTouch();
    },
    requestLock() {
      if (this.touchMode || this.locked) return;
      const c = this.canvas;
      try {
        const p = c.requestPointerLock({ unadjustedMovement: true });
        if (p && p.catch) p.catch(() => { try { const p2 = c.requestPointerLock(); if (p2 && p2.catch) p2.catch(() => MP.events.emit('input:lockerror')); } catch (e) { MP.events.emit('input:lockerror'); } });
      } catch (e) { try { c.requestPointerLock(); } catch (e2) { MP.events.emit('input:lockerror'); } }
    },
    exitLock() { if (document.pointerLockElement) document.exitPointerLock(); },
    onKey(e, down) {
      const code = e.code;
      // evita rolagem/atalhos durante o jogo
      if (this.enabled && ['Tab', 'Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].indexOf(code) >= 0) e.preventDefault();
      if (this.enabled && (e.ctrlKey || code === 'ControlLeft') && ['KeyS', 'KeyD', 'KeyF', 'KeyR', 'KeyG'].indexOf(code) >= 0) e.preventDefault();
      if (down) {
        if (!e.repeat && !this.keys.has(code)) this.edges.add(code);
        this.keys.add(code);
      } else this.keys.delete(code);
      if (down && !e.repeat) MP.events.emit('key', code, e);
    },
    releaseAll() {
      this.keys.clear(); this.mouse.left = this.mouse.right = false;
      for (const k of Object.keys(this.touch.held)) this.touch.held[k] = false;
      this.touch.mx = this.touch.my = 0;
      for (const [id, p] of this.pointers) if (p.el) p.el.classList.remove('down');
      this.pointers.clear();
      const base = document.getElementById('joy-base'); if (base) base.classList.remove('active');
    },
    held(code) { return this.keys.has(code); },
    edge(code) { return this.edges.has(code); },
    /** Lê e zera os eventos do quadro. */
    endFrame() {
      this.edges.clear(); this.mouse.leftEdge = this.mouse.rightEdge = false;
      this.look.dx = this.look.dy = 0; this.wheel = 0; this.touch.edges.clear();
    },

    // ------------------------------------------------------------- toque
    initTouch() {
      const ui = document.getElementById('touch-ui');
      this.touchUI = ui;
      this.btns = {};
      for (const b of ui.querySelectorAll('.tbtn')) this.btns[b.dataset.b] = b;
      this.applyTouchLayout();
      const joyBase = document.getElementById('joy-base'), knob = document.getElementById('joy-knob');
      const R = () => 58 * MP.settings.values.touchButtonScale;
      ui.addEventListener('pointerdown', e => {
        if (e.pointerType === 'mouse' && !this.touchMode) return;
        e.preventDefault();
        if (this.editing) { this.editStart(e); return; }
        const btn = e.target.closest && e.target.closest('.tbtn');
        const p = { id: e.pointerId, x: e.clientX, y: e.clientY, sx: e.clientX, sy: e.clientY, role: null, el: null };
        if (btn) {
          const b = btn.dataset.b; p.role = 'btn:' + b; p.el = btn; btn.classList.add('down');
          this.touch.held[b] = true; this.touch.edges.add(b);
          if (b === 'crouch') this.touch.crouchToggle = !this.touch.crouchToggle;
          if (b === 'walk') this.touch.walkToggle = !this.touch.walkToggle;
          if (MP.settings.values.vibration && navigator.vibrate) { try { navigator.vibrate(8); } catch (err) { MP.diag.log('vibrate: ' + err.message); } }
        } else if (e.clientX < root.innerWidth * 0.42) {
          // analógico dinâmico: nasce onde o polegar toca
          if ([...this.pointers.values()].some(q => q.role === 'joy')) return;
          p.role = 'joy';
          joyBase.style.left = e.clientX + 'px'; joyBase.style.top = e.clientY + 'px'; joyBase.classList.add('active');
        } else p.role = 'look';
        this.pointers.set(e.pointerId, p);
        try { ui.setPointerCapture(e.pointerId); } catch (err) { MP.diag.log('capture: ' + err.message); }
      }, { passive: false });
      ui.addEventListener('pointermove', e => {
        const p = this.pointers.get(e.pointerId);
        if (this.editing) { this.editMove(e); return; }
        if (!p) return;
        e.preventDefault();
        const dx = e.clientX - p.x, dy = e.clientY - p.y;
        p.x = e.clientX; p.y = e.clientY;
        if (p.role === 'joy') {
          let ox = e.clientX - p.sx, oy = e.clientY - p.sy; const r = R();
          const l = Math.sqrt(ox * ox + oy * oy);
          if (l > r) { ox = ox / l * r; oy = oy / l * r; }
          knob.style.transform = `translate(calc(-50% + ${ox}px), calc(-50% + ${oy}px))`;
          let mx = ox / r, my = oy / r; const mag = Math.sqrt(mx * mx + my * my);
          if (mag < 0.12) { mx = 0; my = 0; }
          this.touch.mx = mx; this.touch.my = my;
        } else if (p.role === 'look' || p.role === 'btn:fire' || p.role === 'btn:fire2' || p.role === 'btn:aim') {
          // o botão de fogo também move a mira (padrão de FPS mobile)
          this.look.dx += dx * 1.6; this.look.dy += dy * 1.6;
        }
      }, { passive: false });
      const end = e => {
        if (this.editing) { this.editEnd(e); return; }
        const p = this.pointers.get(e.pointerId); if (!p) return;
        this.pointers.delete(e.pointerId);
        if (p.role === 'joy') { this.touch.mx = this.touch.my = 0; knob.style.transform = 'translate(-50%,-50%)'; joyBase.classList.remove('active'); }
        else if (p.role && p.role.startsWith('btn:')) { const b = p.role.slice(4); this.touch.held[b] = false; if (p.el) p.el.classList.remove('down'); }
      };
      ui.addEventListener('pointerup', end); ui.addEventListener('pointercancel', end); ui.addEventListener('lostpointercapture', end);
      document.getElementById('touch-edit-done').addEventListener('click', () => this.setEditing(false));
      document.getElementById('touch-edit-reset').addEventListener('click', () => { MP.settings.set('touchLayout', {}); this.applyTouchLayout(); });
      MP.events.on('settings:changed', (k) => { if (k === 'touchButtonScale' || k === 'touchOpacity' || k === 'touchLayout' || k === '*') this.applyTouchLayout(); if (k === 'touchControls' || k === '*') this.refreshTouchMode(); }, 'input:set');
    },
    refreshTouchMode() {
      const s = MP.settings.values;
      this.touchMode = s.touchControls === 'on' || (s.touchControls === 'auto' && (('ontouchstart' in root) || (navigator.maxTouchPoints > 0 && matchMedia('(pointer: coarse)').matches)));
      document.body.classList.toggle('touch', this.touchMode);
      MP.events.emit('input:touchmode', this.touchMode);
    },
    applyTouchLayout() {
      const s = MP.settings.values;
      document.documentElement.style.setProperty('--tb-scale', s.touchButtonScale);
      document.documentElement.style.setProperty('--tb-opacity', s.touchOpacity);
      for (const k of Object.keys(this.btns)) {
        const pos = (s.touchLayout && s.touchLayout[k]) || DEFAULT_TOUCH[k];
        const el = this.btns[k];
        el.style.left = `calc(${(pos.x * 100).toFixed(2)}% )`; el.style.top = `calc(${(pos.y * 100).toFixed(2)}% )`;
      }
    },
    setEditing(on) {
      this.editing = on;
      this.touchUI.classList.toggle('editing', on);
      document.getElementById('touch-edit-bar').hidden = !on;
      if (on) { this.touchUI.hidden = false; this.layoutDraft = Object.assign({}, MP.settings.values.touchLayout); }
      else { MP.settings.set('touchLayout', this.layoutDraft || {}); MP.events.emit('input:editdone'); }
    },
    editStart(e) {
      const btn = e.target.closest && e.target.closest('.tbtn'); if (!btn) return;
      this.dragBtn = btn; this.dragId = e.pointerId;
      try { this.touchUI.setPointerCapture(e.pointerId); } catch (err) { MP.diag.log('capture: ' + err.message); }
    },
    editMove(e) {
      if (!this.dragBtn || e.pointerId !== this.dragId) return;
      const x = M.clamp(e.clientX / root.innerWidth, 0.03, 0.97), y = M.clamp(e.clientY / root.innerHeight, 0.04, 0.96);
      this.dragBtn.style.left = (x * 100) + '%'; this.dragBtn.style.top = (y * 100) + '%';
      this.layoutDraft[this.dragBtn.dataset.b] = { x, y };
    },
    editEnd() { this.dragBtn = null; },
    showTouch(on) { this.touchUI.hidden = !(on && this.touchMode); if (!on) this.releaseAll(); },
    setContextButton(name, active) { const b = this.btns[name]; if (b) b.classList.toggle('ctx', !!active); },
    setToggle(name, on) { const b = this.btns[name]; if (b) b.classList.toggle('on', !!on); },
    setVisible(name, on) { const b = this.btns[name]; if (b) b.hidden = !on; }
  };
  I.DEFAULT_TOUCH = DEFAULT_TOUCH;
})(typeof window !== 'undefined' ? window : globalThis);
