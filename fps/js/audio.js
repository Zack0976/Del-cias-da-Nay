/* Mirage Protocol — áudio 100% sintetizado com Web Audio API (tiros, recargas, passos, impactos,
 * explosões, granadas, bomba, interface, avisos de rodada e ambiente). Inicia após interação do usuário. */
(function (root) {
  'use strict';
  const MP = root.MP;
  const { math: M } = MP;
  const ev = MP.events;

  const A = MP.audio = {
    ctx: null, master: null, sfx: null, music: null, ok: false, voices: 0, maxVoices: 28,
    noise: null, listener: { x: 0, y: 0, z: 0, yaw: 0 }, ambient: null, fireLoops: new Map(),
    error: null,

    /** Deve ser chamado dentro de um gesto do usuário (clique/toque). */
    unlock() {
      try {
        if (!this.ctx) {
          const AC = root.AudioContext || root.webkitAudioContext;
          if (!AC) { this.error = 'Web Audio API indisponível neste navegador'; MP.diag.log(this.error); return false; }
          const ctx = this.ctx = new AC();
          this.master = ctx.createGain();
          const comp = ctx.createDynamicsCompressor(); comp.threshold.value = -14; comp.ratio.value = 4;
          this.master.connect(comp); comp.connect(ctx.destination);
          this.sfx = ctx.createGain(); this.sfx.connect(this.master);
          this.music = ctx.createGain(); this.music.connect(this.master);
          // buffer de ruído branco reutilizável
          const len = ctx.sampleRate * 2; const buf = ctx.createBuffer(1, len, ctx.sampleRate); const d = buf.getChannelData(0);
          for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
          this.noise = buf;
          this.applyVolumes();
          this.ok = true;
          this.startAmbient();
        }
        if (this.ctx.state === 'suspended') this.ctx.resume();
        return true;
      } catch (e) { this.error = e.message; MP.diag.error('áudio', e); return false; }
    },
    applyVolumes() {
      if (!this.ctx) return;
      const s = MP.settings.values;
      this.master.gain.value = s.volume;
      this.sfx.gain.value = s.sfxVolume;
      this.music.gain.value = s.musicVolume * 0.5;
    },
    setListener(x, y, z, yaw) { const l = this.listener; l.x = x; l.y = y; l.z = z; l.yaw = yaw; },

    // ------------------------------------------------------------- primitivas
    /** Saída espacial simples: ganho por distância + panorâmica estéreo relativa ao ouvinte. */
    out(pos, range, vol) {
      const ctx = this.ctx; const g = ctx.createGain();
      let gain = vol; let pan = 0; let lp = 20000;
      if (pos) {
        const l = this.listener; const dx = pos.x - l.x, dy = pos.y - l.y, dz = pos.z - l.z;
        const d = Math.sqrt(dx * dx + dy * dy + dz * dz);
        if (d > range) return null;
        gain *= Math.pow(1 - d / range, 1.6) / (1 + d * 0.05);
        // direita do ouvinte: (cos yaw, 0, -sin yaw)
        const rx = Math.cos(l.yaw), rz = -Math.sin(l.yaw);
        pan = d > 0.5 ? M.clamp((dx * rx + dz * rz) / d, -1, 1) * 0.85 : 0;
        lp = 18000 - Math.min(16000, d * 220);
        // abafado atrás de paredes
        if (d > 3 && MP.map && !MP.map.segmentClear({ x: l.x, y: l.y, z: l.z }, { x: pos.x, y: pos.y + 0.5, z: pos.z })) { gain *= 0.55; lp = Math.min(lp, 1800); }
      }
      if (gain < 0.003) return null;
      g.gain.value = gain;
      let node = g;
      if (lp < 17000) { const f = ctx.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = lp; f.connect(g); node = f; }
      if (ctx.createStereoPanner) { const p = ctx.createStereoPanner(); p.pan.value = pan; g.connect(p); p.connect(this.sfx); }
      else g.connect(this.sfx);
      return node;
    },
    claim(dur) {
      if (this.voices >= this.maxVoices) return false;
      this.voices++; setTimeout(() => { this.voices--; }, dur * 1000 + 50);
      return true;
    },
    noiseBurst(dest, t, dur, f0, f1, type, q, vol, attack) {
      const ctx = this.ctx; const src = ctx.createBufferSource(); src.buffer = this.noise;
      src.playbackRate.value = 0.8 + Math.random() * 0.4;
      const f = ctx.createBiquadFilter(); f.type = type || 'bandpass'; f.Q.value = q || 1;
      f.frequency.setValueAtTime(f0, t); f.frequency.exponentialRampToValueAtTime(Math.max(40, f1), t + dur);
      const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(vol, t + (attack || 0.003)); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      src.connect(f); f.connect(g); g.connect(dest);
      src.start(t, Math.random() * 1.5); src.stop(t + dur + 0.05);
    },
    tone(dest, t, dur, f0, f1, type, vol, attack) {
      const ctx = this.ctx; const o = ctx.createOscillator(); o.type = type || 'sine';
      o.frequency.setValueAtTime(f0, t); if (f1 !== f0) o.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t + dur);
      const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(vol, t + (attack || 0.004)); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      o.connect(g); g.connect(dest); o.start(t); o.stop(t + dur + 0.05);
    },

    // ------------------------------------------------------------- sons do jogo
    gunshot(def, pos, local) {
      if (!this.ok || !this.claim(0.6)) return;
      const range = def.cat === 'sniper' ? 160 : 110;
      const d = this.out(local ? null : pos, range, local ? 0.9 : 1.0); if (!d) return;
      const t = this.ctx.currentTime;
      const cat = def.cat;
      const P = {
        pistol: [0.12, 2600, 600, 160, 0.5], smg: [0.1, 3200, 900, 140, 0.45], rifle: [0.16, 2200, 500, 110, 0.7],
        sniper: [0.45, 1600, 250, 70, 0.95], heavy: [0.3, 1400, 280, 80, 0.85]
      }[cat] || [0.12, 2400, 600, 140, 0.5];
      let [dur, f0, f1, thump, vol] = P;
      if (def.id === 'falcao' || def.id === 'rhino') { dur = 0.25; thump = 90; vol = 0.75; }
      if (def.id === 'sentinela') { vol *= 0.55; f0 = 1800; }
      this.noiseBurst(d, t, dur, f0, f1, 'lowpass', 0.7, vol, 0.001);
      this.noiseBurst(d, t, 0.03, 5000, 2000, 'highpass', 0.5, vol * 0.5, 0.0005);
      this.tone(d, t, dur * 0.6, thump * 2, thump * 0.6, 'triangle', vol * 0.6, 0.001);
      // cauda (eco do ambiente)
      if (cat === 'sniper' || cat === 'rifle' || cat === 'heavy') this.noiseBurst(d, t + 0.05, dur * 2.2, 700, 200, 'lowpass', 0.5, vol * 0.12, 0.02);
      if (local && (def.mode === 'bolt' || def.mode === 'pump')) this.mech(t + 0.35, def.mode === 'pump' ? 'pump' : 'bolt');
    },
    mech(t, kind) {
      const d = this.out(null, 1, 0.45); if (!d) return;
      if (kind === 'pump') { this.noiseBurst(d, t, 0.08, 1800, 900, 'bandpass', 3, 0.5); this.noiseBurst(d, t + 0.16, 0.08, 2200, 1200, 'bandpass', 3, 0.5); }
      else { this.noiseBurst(d, t, 0.06, 3000, 1500, 'bandpass', 4, 0.45); this.noiseBurst(d, t + 0.25, 0.07, 2500, 1300, 'bandpass', 4, 0.45); }
    },
    click(pos, local, f, vol) {
      if (!this.ok || !this.claim(0.15)) return;
      const d = this.out(local ? null : pos, 15, vol || 0.4); if (!d) return;
      this.noiseBurst(d, this.ctx.currentTime, 0.05, f || 3200, (f || 3200) * 0.6, 'bandpass', 5, 1);
    },
    reload(def, pos, local) {
      if (!this.ok || !this.claim(def.reload)) return;
      const d = this.out(local ? null : pos, 18, local ? 0.55 : 0.6); if (!d) return;
      const t = this.ctx.currentTime, R = def.reload;
      if (def.reloadType === 'shell') { this.noiseBurst(d, t + 0.25, 0.06, 1500, 800, 'bandpass', 3, 0.9); return; }
      this.noiseBurst(d, t + R * 0.15, 0.07, 2200, 1100, 'bandpass', 4, 0.9);      // carregador sai
      this.noiseBurst(d, t + R * 0.55, 0.08, 1700, 900, 'bandpass', 4, 1.0);       // carregador entra
      this.noiseBurst(d, t + R * 0.85, 0.06, 3200, 1600, 'bandpass', 5, 0.9);      // ferrolho
    },
    footstep(pos, mat, local) {
      if (!this.ok || !this.claim(0.2)) return;
      const d = this.out(local ? null : pos, 28, local ? 0.22 : 0.55); if (!d) return;
      const t = this.ctx.currentTime;
      if (mat === 'metal') { this.tone(d, t, 0.12, 420, 380, 'triangle', 0.3); this.noiseBurst(d, t, 0.08, 2500, 1500, 'bandpass', 2, 0.4); }
      else if (mat === 'wood' || mat === 'step') this.noiseBurst(d, t, 0.09, 900, 400, 'bandpass', 2, 0.7);
      else if (mat === 'sand') this.noiseBurst(d, t, 0.11, 1600, 700, 'bandpass', 0.8, 0.6);
      else this.noiseBurst(d, t, 0.07, 1200, 500, 'bandpass', 1.5, 0.7);
    },
    impact(pos, mat) {
      if (!this.ok || !this.claim(0.15)) return;
      const d = this.out(pos, 30, 0.35); if (!d) return;
      const t = this.ctx.currentTime;
      if (mat === 'metal') this.tone(d, t, 0.18, 1800 + Math.random() * 900, 1500, 'sine', 0.35);
      else if (mat === 'wood') this.noiseBurst(d, t, 0.08, 700, 300, 'bandpass', 2, 0.8);
      else this.noiseBurst(d, t, 0.06, 2600, 900, 'bandpass', 1.2, 0.7);
    },
    flesh(pos, head, local) {
      if (!this.ok || !this.claim(0.2)) return;
      const d = this.out(pos, 40, 0.6); if (!d) return;
      const t = this.ctx.currentTime;
      this.noiseBurst(d, t, 0.08, 500, 200, 'lowpass', 1, 0.8);
      if (head) this.tone(d, t, 0.25, 2600, 2200, 'sine', 0.35);
    },
    hitmarker(head, kill) {
      if (!this.ok) return;
      const d = this.out(null, 1, 0.35); if (!d) return;
      const t = this.ctx.currentTime;
      if (kill) { this.tone(d, t, 0.1, 1200, 1200, 'square', 0.12); this.tone(d, t + 0.06, 0.18, 1800, 1800, 'square', 0.1); }
      else this.tone(d, t, 0.05, head ? 2400 : 1500, head ? 2400 : 1500, 'square', 0.08);
    },
    hurt() {
      if (!this.ok) return;
      const d = this.out(null, 1, 0.4); if (!d) return;
      this.noiseBurst(d, this.ctx.currentTime, 0.15, 400, 150, 'lowpass', 1, 0.8);
    },
    explosion(pos, size) {
      if (!this.ok || !this.claim(2.5)) return;
      const d = this.out(pos, 220, 1.0 * Math.min(1.5, size)); if (!d) return;
      const t = this.ctx.currentTime;
      this.noiseBurst(d, t, 1.6 * Math.sqrt(size), 1400, 60, 'lowpass', 0.6, 1, 0.002);
      this.tone(d, t, 1.0, 90, 30, 'sine', 1, 0.003);
      this.noiseBurst(d, t + 0.02, 0.3, 4000, 800, 'bandpass', 0.5, 0.5);
    },
    flashbang(pos, blindDur) {
      if (!this.ok) return;
      const d = this.out(pos, 150, 0.9); if (d) { const t = this.ctx.currentTime; this.noiseBurst(d, t, 0.5, 6000, 900, 'lowpass', 0.5, 1, 0.001); this.tone(d, t, 0.3, 180, 60, 'sine', 0.6); }
    },
    tinnitus(dur) {
      if (!this.ok) return;
      const d = this.out(null, 1, 0.12); if (!d) return;
      this.tone(d, this.ctx.currentTime, Math.min(4, dur), 3600, 3500, 'sine', 1, 0.02);
    },
    bounce(pos) {
      if (!this.ok || !this.claim(0.2)) return;
      const d = this.out(pos, 25, 0.4); if (!d) return;
      this.tone(d, this.ctx.currentTime, 0.08, 900 + Math.random() * 400, 700, 'triangle', 0.6);
    },
    smokeHiss(pos) {
      if (!this.ok) return;
      const d = this.out(pos, 40, 0.35); if (!d) return;
      this.noiseBurst(d, this.ctx.currentTime, 3.5, 5000, 2000, 'highpass', 0.6, 0.6, 0.15);
    },
    glass(pos) {
      if (!this.ok) return;
      const d = this.out(pos, 50, 0.6); if (!d) return;
      const t = this.ctx.currentTime;
      for (let i = 0; i < 5; i++) this.tone(d, t + i * 0.02, 0.2, 2500 + Math.random() * 3000, 2000, 'sine', 0.2);
      this.noiseBurst(d, t, 0.4, 3000, 600, 'bandpass', 0.6, 0.6);
    },
    fireLoop(f, on) {
      if (!this.ok) return;
      if (!on) { const l = this.fireLoops.get(f); if (l) { try { l.g.gain.setTargetAtTime(0.0001, this.ctx.currentTime, 0.2); l.src.stop(this.ctx.currentTime + 1); } catch (e) { MP.diag.log('fireLoop stop: ' + e.message); } this.fireLoops.delete(f); } return; }
      const ctx = this.ctx; const src = ctx.createBufferSource(); src.buffer = this.noise; src.loop = true;
      const bp = ctx.createBiquadFilter(); bp.type = 'bandpass'; bp.frequency.value = 900; bp.Q.value = 0.5;
      const g = ctx.createGain(); g.gain.value = 0;
      const lfo = ctx.createOscillator(); lfo.frequency.value = 7; const lg = ctx.createGain(); lg.gain.value = 0.08; lfo.connect(lg); lg.connect(g.gain); lfo.start();
      src.connect(bp); bp.connect(g); g.connect(this.sfx); src.start();
      this.fireLoops.set(f, { src, g, pos: f.pos, lfo });
      src.onended = () => { try { lfo.stop(); } catch (e) { MP.diag.log('lfo: ' + e.message); } };
    },
    updateLoops() {
      for (const l of this.fireLoops.values()) {
        const L = this.listener; const d = Math.sqrt((l.pos.x - L.x) ** 2 + (l.pos.z - L.z) ** 2);
        l.g.gain.setTargetAtTime(Math.max(0, 0.25 * (1 - d / 35)), this.ctx.currentTime, 0.1);
      }
    },
    beep(pos, urgent) {
      if (!this.ok) return;
      const d = this.out(pos, 70, urgent ? 0.6 : 0.45); if (!d) return;
      this.tone(d, this.ctx.currentTime, 0.09, 1550, 1550, 'square', 0.25);
    },
    alarm() { // bomba plantada (anúncio global)
      if (!this.ok) return;
      const d = this.out(null, 1, 0.3); if (!d) return; const t = this.ctx.currentTime;
      for (let i = 0; i < 3; i++) { this.tone(d, t + i * 0.28, 0.22, 880, 880, 'sawtooth', 0.25); this.tone(d, t + i * 0.28 + 0.12, 0.12, 660, 660, 'sawtooth', 0.2); }
    },
    defuseTick(pos) {
      if (!this.ok) return; const d = this.out(pos, 20, 0.3); if (!d) return;
      this.noiseBurst(d, this.ctx.currentTime, 0.04, 4000, 3000, 'bandpass', 6, 1);
    },
    stinger(win) {
      if (!this.ok) return;
      const d = this.out(null, 1, 0.35); if (!d) return; const t = this.ctx.currentTime;
      const notes = win ? [392, 523, 659, 784] : [440, 349, 294, 220];
      notes.forEach((f, i) => { this.tone(d, t + i * 0.13, 0.5, f, f, 'triangle', 0.4, 0.01); this.tone(d, t + i * 0.13, 0.5, f * 2, f * 2, 'sine', 0.12, 0.01); });
    },
    roundStart() {
      if (!this.ok) return; const d = this.out(null, 1, 0.3); if (!d) return; const t = this.ctx.currentTime;
      this.tone(d, t, 0.15, 660, 660, 'square', 0.15); this.tone(d, t + 0.18, 0.3, 990, 990, 'square', 0.15);
    },
    ui(kind) {
      if (!this.ok) return; const d = this.out(null, 1, 0.25); if (!d) return; const t = this.ctx.currentTime;
      if (kind === 'hover') this.tone(d, t, 0.04, 1400, 1400, 'sine', 0.15);
      else if (kind === 'buy') { this.tone(d, t, 0.08, 900, 1300, 'triangle', 0.35); this.noiseBurst(d, t + 0.02, 0.06, 2500, 1500, 'bandpass', 3, 0.4); }
      else if (kind === 'deny') this.tone(d, t, 0.15, 220, 180, 'square', 0.18);
      else this.tone(d, t, 0.06, 1000, 800, 'triangle', 0.3);
    },
    switchSound(def) {
      if (!this.ok) return; const d = this.out(null, 1, 0.3); if (!d) return; const t = this.ctx.currentTime;
      this.noiseBurst(d, t, 0.12, 800, 400, 'bandpass', 1, 0.5);
      if (def.cat !== 'knife' && def.cat !== 'grenade') this.noiseBurst(d, t + 0.12, 0.05, 3000, 1500, 'bandpass', 4, 0.6);
      else if (def.cat === 'knife') this.tone(d, t + 0.05, 0.25, 3000, 5000, 'sine', 0.08);
    },
    knife(pos, local) {
      if (!this.ok) return; const d = this.out(local ? null : pos, 15, 0.4); if (!d) return;
      this.noiseBurst(d, this.ctx.currentTime, 0.15, 3000, 6000, 'bandpass', 1.5, 0.7, 0.02);
    },
    startAmbient() {
      // vento do deserto (ruído filtrado com LFO) + drone grave
      const ctx = this.ctx;
      const src = ctx.createBufferSource(); src.buffer = this.noise; src.loop = true;
      const f = ctx.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = 420; f.Q.value = 0.4;
      const g = ctx.createGain(); g.gain.value = 0.06;
      const lfo = ctx.createOscillator(); lfo.frequency.value = 0.07; const lg = ctx.createGain(); lg.gain.value = 200;
      lfo.connect(lg); lg.connect(f.frequency); lfo.start();
      src.connect(f); f.connect(g); g.connect(this.music); src.start();
      const pad = ctx.createGain(); pad.gain.value = 0.0; pad.connect(this.music);
      for (const fr of [55, 82.4, 110]) { const o = ctx.createOscillator(); o.type = 'sine'; o.frequency.value = fr; const og = ctx.createGain(); og.gain.value = 0.05; o.connect(og); og.connect(pad); o.start(); }
      this.ambient = { src, pad };
    },
    setMenuMusic(on) {
      if (!this.ambient) return;
      this.ambient.pad.gain.setTargetAtTime(on ? 0.5 : 0.08, this.ctx.currentTime, 0.8);
    },

    // ------------------------------------------------------------- ligação com eventos do jogo
    register() {
      const self = this;
      const isLocal = (a) => a && a === MP.game.player && !MP.main.thirdPerson;
      ev.on('shot', (a, o, end, def, i) => { if (i === 0 && def.mode !== 'melee') self.gunshot(def, a.pos, isLocal(a)); }, 'au:shot');
      ev.on('dryfire', (a) => self.click(a.pos, isLocal(a), 4500, 0.35), 'au:dry');
      ev.on('reload:start', (a, w) => self.reload(w.def, a.pos, isLocal(a)), 'au:rel');
      ev.on('reload:shell', (a, w) => self.reload(w.def, a.pos, isLocal(a)), 'au:shell');
      ev.on('footstep', (a, mat) => self.footstep(a.pos, mat, isLocal(a)), 'au:step');
      ev.on('land', (a) => self.footstep(a.pos, 'concrete', isLocal(a)), 'au:land');
      ev.on('impact:sound', (p, mat) => { if (Math.random() < 0.6) self.impact(p, mat); }, 'au:imp');
      ev.on('hitFlesh', (p, victim, att, dmg, group) => self.flesh(p, group === 'head', isLocal(att)), 'au:flesh');
      ev.on('explosion', (p, size) => self.explosion(p, size), 'au:boom');
      ev.on('flashbang', (p) => self.flashbang(p), 'au:fb');
      ev.on('flash:blind', (a, dur) => { if (a === MP.game.player && dur > 1.2) self.tinnitus(dur); }, 'au:tin');
      ev.on('grenade:bounce', (g) => self.bounce(g.pos), 'au:bnc');
      ev.on('grenade:throw', (g) => self.knife(g.pos, isLocal(g.owner)), 'au:thr');
      ev.on('smoke:start', (s) => self.smokeHiss(s.pos), 'au:smk');
      ev.on('fire:start', (f) => { self.glass(f.pos); self.fireLoop(f, true); }, 'au:fire');
      ev.on('fire:end', (f) => self.fireLoop(f, false), 'au:firee');
      ev.on('fire:fizzle', (p) => self.smokeHiss(p), 'au:fizz');
      ev.on('bomb:beep', (b, left) => self.beep(b.pos, left < 10), 'au:beep');
      ev.on('bomb:planted', () => self.alarm(), 'au:planted');
      ev.on('bomb:plantStart', (a) => self.click(a.pos, isLocal(a), 2000, 0.4), 'au:plants');
      ev.on('bomb:defuseStart', (a) => self.defuseTick(a.pos), 'au:defs');
      ev.on('bomb:defused', () => self.stinger(MP.game.player && MP.game.player.team === 'CT'), 'au:defd');
      ev.on('weapon:switch', (a, def) => { if (isLocal(a)) self.switchSound(def); }, 'au:sw');
      ev.on('knife', (a) => self.knife(a.pos, isLocal(a)), 'au:knife');
      ev.on('zoom', (a) => { if (isLocal(a)) self.click(a.pos, true, 2500, 0.3); }, 'au:zoom');
      ev.on('pickup', (a) => { if (isLocal(a)) self.ui('buy'); }, 'au:pick');
      ev.on('buy', (a) => { if (a === MP.game.player) self.ui('buy'); }, 'au:buy');
      ev.on('buy:fail', () => self.ui('deny'), 'au:buyf');
      ev.on('round:live', () => self.roundStart(), 'au:live');
      ev.on('round:end', (r) => { const p = MP.game.player; self.stinger(p ? r.winner === p.team : true); }, 'au:end');
      ev.on('damage', (v) => { if (v === MP.game.player) self.hurt(); }, 'au:hurt');
      ev.on('settings:changed', (k) => { if (k === 'volume' || k === 'sfxVolume' || k === 'musicVolume' || k === '*') self.applyVolumes(); }, 'au:set');
      ev.on('round:start', () => { for (const f of [...self.fireLoops.keys()]) self.fireLoop(f, false); }, 'au:rs');
      ev.on('match:start', () => { for (const f of [...self.fireLoops.keys()]) self.fireLoop(f, false); }, 'au:ms');
    }
  };
})(typeof window !== 'undefined' ? window : globalThis);
