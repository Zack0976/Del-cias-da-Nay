/* Mirage Protocol — texturas procedurais geradas em Canvas 2D (nenhum arquivo de imagem externo). */
(function (root) {
  'use strict';
  const MP = root.MP;

  // gerador pseudoaleatório determinístico (texturas idênticas a cada execução)
  function rng(seed) { let s = seed >>> 0 || 1; return () => { s ^= s << 13; s ^= s >>> 17; s ^= s << 5; return ((s >>> 0) % 100000) / 100000; }; }
  function canvas(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
  function rgb(r, g, b, a) { return a === undefined ? `rgb(${r | 0},${g | 0},${b | 0})` : `rgba(${r | 0},${g | 0},${b | 0},${a})`; }
  function speckle(ctx, w, h, n, r, colorFn, rnd) {
    for (let i = 0; i < n; i++) { ctx.fillStyle = colorFn(rnd); const s = r * (0.5 + rnd()); ctx.fillRect(rnd() * w, rnd() * h, s, s); }
  }
  /** Ruído de valor suave em tons (camadas) aplicado sobre a cor base. */
  function cloudy(ctx, w, h, rnd, strength, scale) {
    // manchas suaves (desfoque quando suportado) para variação de tom sem padrões circulares visíveis
    const canBlur = 'filter' in ctx;
    if (canBlur) ctx.filter = 'blur(' + Math.max(2, w / 48) + 'px)';
    strength *= canBlur ? 0.8 : 0.45;
    for (let o = 0; o < 3; o++) {
      const cells = Math.max(2, Math.round(scale * Math.pow(2, o)));
      const cw = w / cells, ch = h / cells;
      for (let y = 0; y < cells; y++) for (let x = 0; x < cells; x++) {
        const v = rnd();
        ctx.fillStyle = v > 0.5 ? rgb(255, 255, 255, (v - 0.5) * strength / (o + 1)) : rgb(0, 0, 0, (0.5 - v) * strength / (o + 1));
        ctx.beginPath(); ctx.ellipse((x + 0.5 + (rnd() - 0.5) * 0.6) * cw, (y + 0.5 + (rnd() - 0.5) * 0.6) * ch, cw * (0.5 + rnd() * 0.5), ch * (0.4 + rnd() * 0.5), rnd() * 3, 0, Math.PI * 2); ctx.fill();
      }
    }
    if (canBlur) ctx.filter = 'none';
  }
  function cracks(ctx, w, h, rnd, n, color) {
    ctx.strokeStyle = color; ctx.lineWidth = 1;
    for (let i = 0; i < n; i++) {
      let x = rnd() * w, y = rnd() * h; ctx.beginPath(); ctx.moveTo(x, y);
      for (let k = 0; k < 6; k++) { x += (rnd() - 0.5) * w * 0.12; y += (rnd() - 0.3) * h * 0.1; ctx.lineTo(x, y); }
      ctx.stroke();
    }
  }

  const gen = {
    plaster(S, tint) {
      const c = canvas(S, S), x = c.getContext('2d'), r = rng(11 + (tint ? 7 : 0));
      x.fillStyle = tint || '#cdb48a'; x.fillRect(0, 0, S, S);
      cloudy(x, S, S, r, 0.22, 3);
      speckle(x, S, S, S * 6, S / 256, q => rgb(90 + q() * 60, 70 + q() * 40, 40, 0.25), r);
      // reboco descascado revelando tijolos
      for (let i = 0; i < 3; i++) {
        const px = r() * S * 0.8, py = r() * S * 0.8, pw = S * (0.08 + r() * 0.15), ph = S * (0.05 + r() * 0.1);
        x.fillStyle = '#9c6a48'; x.fillRect(px, py, pw, ph);
        x.strokeStyle = 'rgba(60,40,30,0.6)';
        for (let by = py; by < py + ph; by += S / 40) { x.beginPath(); x.moveTo(px, by); x.lineTo(px + pw, by); x.stroke(); }
        x.strokeStyle = 'rgba(80,60,40,0.5)'; x.lineWidth = 2; x.strokeRect(px, py, pw, ph); x.lineWidth = 1;
      }
      cracks(x, S, S, r, 5, 'rgba(70,50,30,0.35)');
      // escorrimentos verticais
      for (let i = 0; i < 8; i++) { const sx = r() * S; const g = x.createLinearGradient(0, 0, 0, S); g.addColorStop(0, 'rgba(60,45,30,0.12)'); g.addColorStop(1, 'rgba(60,45,30,0)'); x.fillStyle = g; x.fillRect(sx, 0, 2 + r() * 6, S * (0.3 + r() * 0.6)); }
      return c;
    },
    brick(S) {
      const c = canvas(S, S), x = c.getContext('2d'), r = rng(23);
      x.fillStyle = '#7d5a43'; x.fillRect(0, 0, S, S);
      const rows = 16, bh = S / rows, bw = S / 6;
      for (let j = 0; j < rows; j++) for (let i = -1; i < 7; i++) {
        const off = j % 2 ? bw / 2 : 0;
        const t = r();
        x.fillStyle = rgb(150 + t * 40, 95 + t * 30, 65 + t * 20);
        x.fillRect(i * bw + off + 2, j * bh + 2, bw - 4, bh - 4);
        x.fillStyle = 'rgba(0,0,0,' + (r() * 0.15) + ')'; x.fillRect(i * bw + off + 2, j * bh + bh * 0.6, bw - 4, bh * 0.35);
      }
      cloudy(x, S, S, r, 0.18, 4);
      speckle(x, S, S, S * 3, S / 200, () => 'rgba(40,25,15,0.3)', r);
      return c;
    },
    concrete(S, base) {
      const c = canvas(S, S), x = c.getContext('2d'), r = rng(31);
      x.fillStyle = base || '#9a968c'; x.fillRect(0, 0, S, S);
      cloudy(x, S, S, r, 0.2, 3);
      speckle(x, S, S, S * 10, S / 300, q => q() > 0.5 ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.15)', r);
      // juntas de forma
      x.strokeStyle = 'rgba(40,40,40,0.35)'; x.lineWidth = 2;
      x.beginPath(); x.moveTo(0, S / 2); x.lineTo(S, S / 2); x.moveTo(S / 2, 0); x.lineTo(S / 2, S); x.stroke();
      x.fillStyle = 'rgba(30,30,30,0.35)';
      for (const [px, py] of [[S / 4, S / 4], [3 * S / 4, S / 4], [S / 4, 3 * S / 4], [3 * S / 4, 3 * S / 4]]) { x.beginPath(); x.arc(px, py, S / 120, 0, 7); x.fill(); }
      cracks(x, S, S, r, 3, 'rgba(30,30,30,0.3)');
      return c;
    },
    sand(S) {
      const c = canvas(S, S), x = c.getContext('2d'), r = rng(41);
      x.fillStyle = '#c8aa78'; x.fillRect(0, 0, S, S);
      cloudy(x, S, S, r, 0.25, 2);
      speckle(x, S, S, S * 20, S / 260, q => { const t = q(); return rgb(150 + t * 80, 120 + t * 70, 80 + t * 50, 0.5); }, r);
      for (let i = 0; i < S / 6; i++) { x.fillStyle = rgb(110 + r() * 50, 95 + r() * 40, 75, 0.8); x.beginPath(); x.ellipse(r() * S, r() * S, 1 + r() * S / 120, 1 + r() * S / 160, r() * 3, 0, 7); x.fill(); }
      return c;
    },
    tile(S) {
      const c = canvas(S, S), x = c.getContext('2d'), r = rng(53);
      x.fillStyle = '#6f6253'; x.fillRect(0, 0, S, S);
      const n = 4, ts = S / n;
      for (let j = 0; j < n; j++) for (let i = 0; i < n; i++) {
        const t = r();
        x.fillStyle = rgb(182 + t * 30, 160 + t * 25, 122 + t * 20);
        x.fillRect(i * ts + 3, j * ts + 3, ts - 6, ts - 6);
        x.fillStyle = 'rgba(255,255,255,0.06)'; x.fillRect(i * ts + 3, j * ts + 3, ts - 6, 3);
        if (r() < 0.25) { x.strokeStyle = 'rgba(60,50,40,0.5)'; x.beginPath(); x.moveTo(i * ts + r() * ts, j * ts); x.lineTo(i * ts + r() * ts, (j + 1) * ts); x.stroke(); }
      }
      cloudy(x, S, S, r, 0.18, 3);
      speckle(x, S, S, S * 4, S / 250, () => 'rgba(70,55,40,0.3)', r);
      return c;
    },
    slab(S) {
      const c = gen.concrete(S, '#a39a8a'), x = c.getContext('2d');
      x.strokeStyle = 'rgba(50,45,40,0.5)'; x.lineWidth = 3; x.strokeRect(1, 1, S - 2, S - 2);
      return c;
    },
    tunnel(S) { return gen.concrete(S, '#6e6c66'); },
    crate(S, low) {
      const W2 = S, H2 = low ? S / 2 : S;
      const c = canvas(W2, H2), x = c.getContext('2d'), r = rng(low ? 61 : 67);
      x.fillStyle = '#8a6438'; x.fillRect(0, 0, W2, H2);
      const planks = low ? 4 : 7;
      for (let i = 0; i < planks; i++) {
        const t = r(); x.fillStyle = rgb(150 + t * 35, 108 + t * 25, 62 + t * 15);
        x.fillRect(0, i * H2 / planks + 1, W2, H2 / planks - 2);
        // veios
        x.strokeStyle = 'rgba(90,60,30,0.35)';
        for (let k = 0; k < 5; k++) { const yy = i * H2 / planks + r() * H2 / planks; x.beginPath(); x.moveTo(0, yy); x.bezierCurveTo(W2 * 0.3, yy + 3, W2 * 0.6, yy - 3, W2, yy + 1); x.stroke(); }
      }
      const fw = S * 0.08;
      x.fillStyle = '#6a4826'; x.fillRect(0, 0, W2, fw); x.fillRect(0, H2 - fw, W2, fw); x.fillRect(0, 0, fw, H2); x.fillRect(W2 - fw, 0, fw, H2);
      x.strokeStyle = '#6a4826'; x.lineWidth = fw * 0.9;
      x.beginPath(); x.moveTo(fw, fw); x.lineTo(W2 - fw, H2 - fw); x.stroke();
      // estêncil
      x.fillStyle = 'rgba(30,20,10,0.55)'; x.font = 'bold ' + (S * 0.09) + 'px monospace'; x.textAlign = 'center';
      x.fillText('MP-0' + (1 + ((r() * 8) | 0)), W2 * 0.72, H2 * 0.3);
      x.fillStyle = 'rgba(0,0,0,0.5)'; for (const [px, py] of [[fw / 2, fw / 2], [W2 - fw / 2, fw / 2], [fw / 2, H2 - fw / 2], [W2 - fw / 2, H2 - fw / 2]]) { x.beginPath(); x.arc(px, py, S / 70, 0, 7); x.fill(); }
      return c;
    },
    container(S, color) {
      const c = canvas(S, S), x = c.getContext('2d'), r = rng(71 + color.length);
      x.fillStyle = color; x.fillRect(0, 0, S, S);
      const ribs = 10, rw = S / ribs;
      for (let i = 0; i < ribs; i++) {
        const g = x.createLinearGradient(i * rw, 0, (i + 1) * rw, 0);
        g.addColorStop(0, 'rgba(0,0,0,0.25)'); g.addColorStop(0.3, 'rgba(255,255,255,0.12)'); g.addColorStop(0.7, 'rgba(255,255,255,0.05)'); g.addColorStop(1, 'rgba(0,0,0,0.3)');
        x.fillStyle = g; x.fillRect(i * rw, 0, rw, S);
      }
      // ferrugem
      for (let i = 0; i < 14; i++) { const sx = r() * S; const g = x.createLinearGradient(0, 0, 0, S); g.addColorStop(0, 'rgba(120,60,25,0.45)'); g.addColorStop(1, 'rgba(120,60,25,0)'); x.fillStyle = g; x.fillRect(sx, r() * S * 0.3, 2 + r() * 5, S * (0.2 + r() * 0.5)); }
      speckle(x, S, S, S * 3, S / 180, () => 'rgba(90,45,20,0.45)', r);
      x.fillStyle = 'rgba(255,255,255,0.7)'; x.font = 'bold ' + (S * 0.07) + 'px monospace'; x.fillText('MPRU 40' + ((r() * 9000 + 1000) | 0), S * 0.08, S * 0.14);
      return c;
    },
    sandbag(S) {
      const c = canvas(S, S / 2), x = c.getContext('2d'), r = rng(83);
      x.fillStyle = '#6d6142'; x.fillRect(0, 0, S, S / 2);
      const rows = 3, bh = S / 2 / rows;
      for (let j = 0; j < rows; j++) for (let i = -1; i < 4; i++) {
        const off = j % 2 ? S / 8 : 0; const t = r();
        x.fillStyle = rgb(160 + t * 25, 145 + t * 20, 100 + t * 15);
        x.beginPath(); x.ellipse(i * S / 4 + off + S / 8, j * bh + bh / 2, S / 8 - 2, bh / 2 - 1, 0, 0, 7); x.fill();
        x.strokeStyle = 'rgba(70,60,40,0.5)'; x.stroke();
      }
      speckle(x, S, S / 2, S * 3, S / 250, () => 'rgba(60,50,30,0.3)', r);
      return c;
    },
    step(S) {
      const c = gen.concrete(S, '#8f8a80'), x = c.getContext('2d');
      x.fillStyle = 'rgba(220,170,40,0.75)';
      for (let i = 0; i < 8; i++) { x.save(); x.translate(i * S / 8, 0); x.transform(1, 0, 0.6, 1, 0, 0); x.fillRect(0, 0, S / 16, S / 16); x.restore(); }
      return c;
    },
    trim(S) {
      const c = canvas(S, S / 4), x = c.getContext('2d'), r = rng(91);
      x.fillStyle = '#a58c66'; x.fillRect(0, 0, S, S / 4);
      x.fillStyle = 'rgba(255,255,255,0.15)'; x.fillRect(0, 0, S, S / 24);
      x.fillStyle = 'rgba(0,0,0,0.25)'; x.fillRect(0, S / 4 - S / 20, S, S / 20);
      speckle(x, S, S / 4, S, S / 200, () => 'rgba(60,40,20,0.3)', r);
      return c;
    },
    windowTex(S) {
      const c = canvas(S, S), x = c.getContext('2d');
      x.fillStyle = '#5b4632'; x.fillRect(0, 0, S, S);
      x.fillStyle = '#1b2228'; x.fillRect(S * 0.1, S * 0.1, S * 0.8, S * 0.8);
      const g = x.createLinearGradient(0, 0, S, S); g.addColorStop(0, 'rgba(160,190,210,0.35)'); g.addColorStop(0.5, 'rgba(30,40,50,0)'); g.addColorStop(1, 'rgba(120,150,170,0.2)');
      x.fillStyle = g; x.fillRect(S * 0.1, S * 0.1, S * 0.8, S * 0.8);
      x.fillStyle = '#5b4632'; x.fillRect(S * 0.47, S * 0.1, S * 0.06, S * 0.8); x.fillRect(S * 0.1, S * 0.47, S * 0.8, S * 0.06);
      // persiana parcialmente fechada
      x.fillStyle = '#7a8a6a'; for (let i = 0; i < 6; i++) x.fillRect(S * 0.1, S * 0.1 + i * S * 0.05, S * 0.8, S * 0.035);
      return c;
    },
    door(S) {
      const c = canvas(S / 2, S), x = c.getContext('2d'), r = rng(97);
      x.fillStyle = '#4b3a2a'; x.fillRect(0, 0, S / 2, S);
      for (let i = 0; i < 5; i++) { const t = r(); x.fillStyle = rgb(95 + t * 30, 70 + t * 20, 45 + t * 15); x.fillRect(4 + i * (S / 2 - 8) / 5, 4, (S / 2 - 8) / 5 - 3, S - 8); }
      x.fillStyle = '#2c241a'; x.fillRect(S * 0.36, S * 0.5, S * 0.06, S * 0.08);
      x.strokeStyle = 'rgba(30,20,10,0.7)'; x.lineWidth = 4; x.strokeRect(2, 2, S / 2 - 4, S - 4);
      return c;
    },
    siteLetter(S, letter) {
      const c = canvas(S, S), x = c.getContext('2d');
      x.clearRect(0, 0, S, S);
      x.fillStyle = 'rgba(230,60,40,0.85)'; x.font = 'bold ' + (S * 0.75) + 'px Impact, Arial Black, sans-serif'; x.textAlign = 'center'; x.textBaseline = 'middle';
      x.fillText(letter, S / 2, S / 2);
      // tinta escorrida
      x.fillStyle = 'rgba(230,60,40,0.6)'; for (let i = 0; i < 6; i++) x.fillRect(S * (0.3 + i * 0.08), S * 0.75, 3, S * (0.05 + (i % 3) * 0.05));
      return c;
    },
    sign(S, text, sub) {
      const c = canvas(S, S / 2), x = c.getContext('2d');
      x.fillStyle = '#e8e2d0'; x.fillRect(0, 0, S, S / 2);
      x.strokeStyle = '#3a3a3a'; x.lineWidth = S / 40; x.strokeRect(S / 40, S / 40, S - S / 20, S / 2 - S / 20);
      x.fillStyle = '#222'; x.font = 'bold ' + (S * 0.14) + 'px Arial, sans-serif'; x.textAlign = 'center'; x.textBaseline = 'middle';
      x.fillText(text, S / 2, S * 0.18);
      if (sub) { x.font = (S * 0.08) + 'px Arial, sans-serif'; x.fillText(sub, S / 2, S * 0.36); }
      return c;
    },
    bulletHole(S) {
      const c = canvas(S, S), x = c.getContext('2d');
      const g = x.createRadialGradient(S / 2, S / 2, 0, S / 2, S / 2, S / 2);
      g.addColorStop(0, 'rgba(10,8,6,1)'); g.addColorStop(0.25, 'rgba(20,16,12,0.95)'); g.addColorStop(0.45, 'rgba(60,50,40,0.6)'); g.addColorStop(1, 'rgba(60,50,40,0)');
      x.fillStyle = g; x.fillRect(0, 0, S, S);
      return c;
    },
    scorch(S) {
      const c = canvas(S, S), x = c.getContext('2d'), r = rng(101);
      for (let i = 0; i < 40; i++) { const g = x.createRadialGradient(S / 2 + (r() - 0.5) * S * 0.4, S / 2 + (r() - 0.5) * S * 0.4, 0, S / 2, S / 2, S * 0.3 * (0.4 + r())); g.addColorStop(0, 'rgba(15,12,10,0.35)'); g.addColorStop(1, 'rgba(15,12,10,0)'); x.fillStyle = g; x.fillRect(0, 0, S, S); }
      return c;
    },
    softDot(S) {
      const c = canvas(S, S), x = c.getContext('2d');
      const g = x.createRadialGradient(S / 2, S / 2, 0, S / 2, S / 2, S / 2);
      g.addColorStop(0, 'rgba(255,255,255,1)'); g.addColorStop(0.4, 'rgba(255,255,255,0.6)'); g.addColorStop(1, 'rgba(255,255,255,0)');
      x.fillStyle = g; x.fillRect(0, 0, S, S); return c;
    },
    smokePuff(S) {
      const c = canvas(S, S), x = c.getContext('2d'), r = rng(113);
      for (let i = 0; i < 26; i++) {
        const px = S / 2 + (r() - 0.5) * S * 0.45, py = S / 2 + (r() - 0.5) * S * 0.45, rr = S * (0.12 + r() * 0.22);
        const g = x.createRadialGradient(px, py, 0, px, py, rr);
        const v = 200 + r() * 40;
        g.addColorStop(0, rgb(v, v, v, 0.35)); g.addColorStop(1, rgb(v, v, v, 0));
        x.fillStyle = g; x.fillRect(0, 0, S, S);
      }
      return c;
    },
    flashStar(S) {
      const c = canvas(S, S), x = c.getContext('2d');
      x.translate(S / 2, S / 2);
      const g = x.createRadialGradient(0, 0, 0, 0, 0, S / 2);
      g.addColorStop(0, 'rgba(255,255,230,1)'); g.addColorStop(0.2, 'rgba(255,220,120,0.9)'); g.addColorStop(0.5, 'rgba(255,140,40,0.35)'); g.addColorStop(1, 'rgba(255,100,20,0)');
      x.fillStyle = g;
      for (let i = 0; i < 6; i++) { x.rotate(Math.PI / 3); x.beginPath(); x.moveTo(0, -S * 0.06); x.lineTo(S * 0.5, 0); x.lineTo(0, S * 0.06); x.closePath(); x.fill(); }
      x.beginPath(); x.arc(0, 0, S * 0.22, 0, 7); x.fill();
      return c;
    },
    camo(S, colors) {
      const c = canvas(S, S), x = c.getContext('2d'), r = rng(colors[0].length * 31 + 7);
      x.fillStyle = colors[0]; x.fillRect(0, 0, S, S);
      for (let i = 0; i < 40; i++) { x.fillStyle = colors[1 + (i % (colors.length - 1))]; x.beginPath(); x.ellipse(r() * S, r() * S, S * (0.04 + r() * 0.1), S * (0.03 + r() * 0.06), r() * 3, 0, 7); x.fill(); }
      speckle(x, S, S, S * 2, 2, () => 'rgba(0,0,0,0.15)', r);
      return c;
    },
    metalDark(S) {
      const c = canvas(S, S), x = c.getContext('2d'), r = rng(127);
      x.fillStyle = '#2b2d30'; x.fillRect(0, 0, S, S);
      for (let i = 0; i < S; i += 2) { x.fillStyle = 'rgba(255,255,255,' + (r() * 0.05) + ')'; x.fillRect(0, i, S, 1); }
      speckle(x, S, S, S, 1.5, () => 'rgba(255,255,255,0.08)', r);
      return c;
    }
  };

  MP.textures = {
    gen,
    cache: new Map(),
    /** Cria (ou recupera) uma THREE.CanvasTexture. */
    get(key, builder, opts) {
      if (this.cache.has(key)) return this.cache.get(key);
      const THREE = root.THREE;
      let cv;
      try { cv = builder(); } catch (e) { MP.diag.error('textura ' + key, e); cv = canvas(4, 4); }
      const t = new THREE.CanvasTexture(cv);
      t.wrapS = t.wrapT = (opts && opts.clamp) ? THREE.ClampToEdgeWrapping : THREE.RepeatWrapping;
      if (THREE.sRGBEncoding) t.encoding = THREE.sRGBEncoding;
      t.anisotropy = (opts && opts.aniso) || 1;
      this.cache.set(key, t);
      return t;
    },
    dispose() { for (const t of this.cache.values()) t.dispose(); this.cache.clear(); }
  };
})(typeof window !== 'undefined' ? window : globalThis);
