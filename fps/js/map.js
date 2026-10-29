/* Mirage Protocol — mapa: planta em grade, colisões, raycast (DDA), navegação (A*) e zonas.
 * Sem dependência de THREE: o renderizador lê `MP.map` para construir a geometria. */
(function (root) {
  'use strict';
  const MP = root.MP;
  const { V3, math: M } = MP;

  const W = 48, H = 40, S = 2;           // colunas, linhas, tamanho da célula (m)
  const OX = -W * S / 2, OZ = -H * S / 2; // origem do mundo (canto noroeste)

  // Tipos de célula ------------------------------------------------------------
  // spans: [y0, y1] sólidos; floor: altura caminhável (null = bloqueado para navegação)
  const T = {
    '#': { solid: true, mat: 'wall' },
    'p': { solid: true, mat: 'pillar', h: 7.5 },
    '.': { floor: 0, mat: 'sand' },
    'a': { floor: 0, mat: 'tile' },
    ',': { floor: 0, mat: 'concrete' },
    '=': { floor: 0, mat: 'tunnel', ceil: [3.2, 6.6] },
    'D': { floor: 0, mat: 'concrete', ceil: [3.0, -1], door: true },
    'c': { top: 1.0, mat: 'wood' },
    'C': { top: 2.0, mat: 'wood' },
    'k': { top: 2.6, mat: 'metal' },
    'w': { top: 0.9, mat: 'sandbag' },
    '1': { floor: 0.4, top: 0.4, mat: 'step' },
    '2': { floor: 0.8, top: 0.8, mat: 'step' },
    '3': { floor: 1.2, top: 1.2, mat: 'step' }
  };
  MP.CELL_TYPES = T;

  // Construção da planta -------------------------------------------------------
  const grid = [];
  for (let r = 0; r < H; r++) { grid.push(new Array(W).fill('#')); }
  function fill(c0, r0, c1, r1, ch) {
    for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) if (r > 0 && r < H - 1 && c > 0 && c < W - 1) grid[r][c] = ch;
  }
  function put(c, r, ch) { if (r > 0 && r < H - 1 && c > 0 && c < W - 1) grid[r][c] = ch; }

  // Áreas abertas
  fill(19, 1, 28, 5, ',');     // Base CT
  fill(8, 2, 40, 4, ',');      // Corredor de rotação CT
  fill(2, 5, 15, 14, '.');     // Bomb A
  fill(32, 5, 45, 14, '.');    // Bomb B
  fill(21, 5, 26, 11, '.');    // Meio CT
  fill(20, 12, 27, 29, '.');   // Meio
  fill(12, 15, 19, 17, '.');   // Passarela (A curto)
  fill(12, 13, 13, 14, '.');
  fill(2, 15, 6, 31, '.');     // A longo
  fill(2, 30, 18, 33, '.');    // Pátio T → A
  fill(17, 33, 30, 38, ',');   // Base T
  fill(21, 29, 26, 33, '.');   // Saída T → meio
  fill(29, 30, 44, 33, '.');   // Pátio T → B
  fill(38, 17, 43, 29, '=');   // Túnel B (coberto)
  fill(38, 15, 43, 16, ',');   // Saída do túnel
  fill(28, 19, 35, 21, '.');   // B curto (apartamentos)
  fill(33, 15, 35, 18, ',');

  // Estreitamentos e portas
  fill(8, 4, 10, 4, '#'); fill(37, 4, 40, 4, '#');           // entradas CT mais estreitas
  put(2, 22, '#'); put(3, 22, '#'); put(6, 22, '#'); put(4, 22, 'D'); put(5, 22, 'D');   // portas do A longo
  put(28, 19, 'D'); put(28, 20, 'D'); put(28, 21, 'D');       // porta meio → B curto
  put(33, 15, 'D'); put(34, 15, 'D'); put(35, 15, 'D');       // porta B curto → B
  fill(20, 12, 20, 13, '#'); fill(27, 12, 27, 13, '#');       // boca do meio CT
  fill(38, 29, 43, 29, '=');

  // Meio em "S": quebra a linha de visão direta entre as bases
  fill(23, 12, 26, 12, '#');   // boca do meio CT só pelo lado oeste
  fill(21, 31, 23, 31, '#');   // saída T só pelo lado leste
  fill(23, 18, 24, 19, '#');   // bloco central do meio
  // Pisos de área de bomba (azulejos)
  fill(4, 6, 11, 12, 'a');
  fill(36, 6, 43, 12, 'a');

  // Passarela elevada com escadas nas duas pontas
  put(19, 15, '1'); put(19, 16, '1'); put(19, 17, '1');
  put(18, 15, '2'); put(18, 16, '2'); put(18, 17, '2');
  fill(15, 15, 17, 17, '3');
  put(14, 15, '2'); put(14, 16, '2'); put(14, 17, '2');
  put(13, 15, '1'); put(13, 16, '1'); put(13, 17, '1');
  // Plataforma do B (sacada) com escada
  put(42, 5, '1'); put(42, 6, '1');
  put(43, 5, '2'); put(43, 6, '2');
  fill(44, 5, 45, 7, '3');

  // Coberturas — Bomb A
  put(7, 8, 'c'); put(8, 8, 'c'); put(8, 9, 'C');
  put(5, 11, 'C'); put(6, 11, 'c');
  fill(11, 6, 13, 7, 'k');
  put(3, 13, 'c'); put(14, 9, 'C'); put(14, 10, 'c');
  put(10, 12, 'w'); put(11, 12, 'w');
  // Coberturas — Bomb B
  put(38, 8, 'c'); put(39, 8, 'c'); put(39, 9, 'C');
  put(41, 11, 'C'); put(42, 11, 'c');
  fill(33, 7, 34, 9, 'k');
  put(44, 12, 'c'); put(37, 13, 'w'); put(36, 13, 'w');
  // Meio
  put(23, 22, 'C'); put(24, 22, 'c');
  put(21, 16, 'c'); put(26, 25, 'c'); put(26, 26, 'C');
  put(20, 27, 'k'); put(20, 28, 'k');
  put(22, 8, 'c'); put(25, 9, 'w');
  fill(23, 14, 24, 14, 'p');
  // A longo
  put(5, 18, 'C'); put(3, 26, 'c'); put(2, 27, 'C'); put(6, 29, 'w');
  // Pátios T
  fill(10, 31, 12, 31, 'k'); put(15, 33, 'c'); put(7, 32, 'c');
  put(34, 31, 'C'); put(35, 31, 'c'); fill(39, 32, 41, 32, 'k');
  // Túnel B
  put(40, 24, 'c'); put(38, 20, 'C'); put(43, 27, 'c');
  // Bases
  fill(18, 35, 19, 36, 'k'); fill(28, 35, 29, 36, 'k');
  put(20, 2, 'c'); put(27, 2, 'c'); put(13, 3, 'c'); put(34, 2, 'C');
  // B curto
  put(31, 20, 'c'); put(34, 17, 'c');

  // Zonas nomeadas (para HUD, rádio e IA) ---------------------------------------
  const zones = [
    { id: 'ctspawn', name: 'Base CT', c0: 19, r0: 1, c1: 28, r1: 5 },
    { id: 'ctrot', name: 'Rotação CT', c0: 8, r0: 2, c1: 40, r1: 4 },
    { id: 'siteA', name: 'Bomb A', c0: 2, r0: 5, c1: 15, r1: 14 },
    { id: 'siteB', name: 'Bomb B', c0: 32, r0: 5, c1: 45, r1: 14 },
    { id: 'ctmid', name: 'Meio CT', c0: 21, r0: 5, c1: 26, r1: 11 },
    { id: 'mid', name: 'Meio', c0: 20, r0: 12, c1: 27, r1: 28 },
    { id: 'cat', name: 'Passarela', c0: 12, r0: 15, c1: 19, r1: 17 },
    { id: 'along', name: 'A Longo', c0: 2, r0: 15, c1: 6, r1: 29 },
    { id: 'tyardA', name: 'Pátio Oeste', c0: 2, r0: 30, c1: 16, r1: 33 },
    { id: 'tspawn', name: 'Base T', c0: 17, r0: 33, c1: 30, r1: 38 },
    { id: 'tyardB', name: 'Pátio Leste', c0: 29, r0: 30, c1: 44, r1: 33 },
    { id: 'btun', name: 'Túnel B', c0: 38, r0: 15, c1: 43, r1: 29 },
    { id: 'bshort', name: 'Apartamentos', c0: 28, r0: 15, c1: 35, r1: 21 },
    { id: 'tmid', name: 'Saída T', c0: 21, r0: 29, c1: 26, r1: 32 }
  ];
  const plantZones = {
    A: { c0: 4, r0: 6, c1: 11, r1: 12 },
    B: { c0: 36, r0: 6, c1: 43, r1: 12 }
  };

  // Conversões -----------------------------------------------------------------
  function cellX(c) { return OX + (c + 0.5) * S; }
  function cellZ(r) { return OZ + (r + 0.5) * S; }
  function colOf(x) { return Math.floor((x - OX) / S); }
  function rowOf(z) { return Math.floor((z - OZ) / S); }

  // Células compiladas ----------------------------------------------------------
  const cells = new Array(W * H);
  function wallHeight(c, r) {
    // alturas variadas por "quarteirão" para criar um horizonte urbano
    if (c === 0 || r === 0 || c === W - 1 || r === H - 1) return 9;
    const h = ((Math.floor(c / 5) * 73856093) ^ (Math.floor(r / 4) * 19349663)) >>> 0;
    return 5.5 + (h % 5) * 0.75;
  }
  function wallMaterial(c, r) {
    const h = ((Math.floor(c / 7) * 83492791) ^ (Math.floor(r / 6) * 2654435761)) >>> 0;
    return ['plaster', 'plaster', 'brick', 'plaster2', 'concrete'][h % 5];
  }
  for (let r = 0; r < H; r++) {
    for (let c = 0; c < W; c++) {
      const ch = grid[r][c];
      const t = T[ch];
      const cell = { ch, c, r, spans: [], floor: null, mat: t.mat, top: 0 };
      if (t.solid) {
        const h = t.h || wallHeight(c, r);
        cell.spans.push([0, h]); cell.top = h;
        cell.mat = t.mat === 'wall' ? wallMaterial(c, r) : t.mat;
      } else {
        if (t.top) { cell.spans.push([0, t.top]); cell.top = t.top; }
        if (t.floor !== undefined) cell.floor = t.floor;
      }
      cells[r * W + c] = cell;
    }
  }
  // tetos (túnel e portas) — a altura superior acompanha as paredes vizinhas
  for (let r = 0; r < H; r++) for (let c = 0; c < W; c++) {
    const cell = cells[r * W + c]; const t = T[cell.ch];
    if (!t.ceil) continue;
    let top = t.ceil[1];
    if (top < 0) {
      top = 6;
      for (const [dc, dr] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const n = cells[(r + dr) * W + (c + dc)];
        if (n && T[n.ch].solid) top = Math.max(top, n.top);
      }
    }
    cell.spans.push([t.ceil[0], top]);
    cell.ceil = [t.ceil[0], top];
  }

  function cellAt(c, r) { return (c < 0 || r < 0 || c >= W || r >= H) ? null : cells[r * W + c]; }

  // Colisão --------------------------------------------------------------------
  /** Verifica se uma AABB intersecta geometria sólida. Fora da grade conta como sólido. */
  function boxBlocked(minx, miny, minz, maxx, maxy, maxz) {
    const c0 = colOf(minx), c1 = colOf(maxx - 1e-6), r0 = rowOf(minz), r1 = rowOf(maxz - 1e-6);
    for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) {
      const cell = cellAt(c, r);
      if (!cell) return true;
      const sp = cell.spans;
      for (let i = 0; i < sp.length; i++) if (maxy > sp[i][0] + 1e-4 && miny < sp[i][1] - 1e-4) return true;
    }
    return false;
  }
  /** Maior topo sólido abaixo de `y` (+tolerância) sob a pegada XZ. */
  function groundBelow(minx, minz, maxx, maxz, y) {
    let g = 0;
    const c0 = colOf(minx), c1 = colOf(maxx - 1e-6), r0 = rowOf(minz), r1 = rowOf(maxz - 1e-6);
    for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) {
      const cell = cellAt(c, r); if (!cell) continue;
      for (const s of cell.spans) if (s[1] <= y + 0.02 && s[1] > g) g = s[1];
    }
    return g;
  }
  function pointSolid(x, y, z) {
    if (y < 0) return true;
    const cell = cellAt(colOf(x), rowOf(z));
    if (!cell) return true;
    for (const s of cell.spans) if (y >= s[0] && y <= s[1]) return true;
    return false;
  }

  // Raycast DDA na grade -------------------------------------------------------
  const _hit = { t: 0, nx: 0, ny: 0, nz: 0, mat: '', c: 0, r: 0 };
  /** Raio contra o cenário. dir unitário. Retorna objeto reutilizado (copie se precisar guardar) ou null. */
  function raycast(o, d, maxDist, ignoreCell) {
    let best = maxDist, found = false;
    // chão (y=0)
    if (d.y < -1e-6) {
      const t = -o.y / d.y;
      if (t >= 0 && t < best) { best = t; found = true; _hit.nx = 0; _hit.ny = 1; _hit.nz = 0; _hit.mat = 'ground'; _hit.c = colOf(o.x + d.x * t); _hit.r = rowOf(o.z + d.z * t); }
    }
    let c = colOf(o.x), r = rowOf(o.z);
    const stepC = d.x > 0 ? 1 : -1, stepR = d.z > 0 ? 1 : -1;
    const tDeltaX = Math.abs(d.x) > 1e-9 ? S / Math.abs(d.x) : Infinity;
    const tDeltaZ = Math.abs(d.z) > 1e-9 ? S / Math.abs(d.z) : Infinity;
    const nextX = OX + (c + (stepC > 0 ? 1 : 0)) * S, nextZ = OZ + (r + (stepR > 0 ? 1 : 0)) * S;
    let tMaxX = Math.abs(d.x) > 1e-9 ? (nextX - o.x) / d.x : Infinity;
    let tMaxZ = Math.abs(d.z) > 1e-9 ? (nextZ - o.z) / d.z : Infinity;
    let tEnter = 0, enterAxis = -1; // 0: x, 1: z
    for (let iter = 0; iter < 200; iter++) {
      if (tEnter > best) break;
      const tExit = Math.min(tMaxX, tMaxZ, best);
      const cell = cellAt(c, r);
      if (!cell) { // limite do mundo
        if (tEnter < best) { best = tEnter; found = true; setSideNormal(enterAxis, stepC, stepR); _hit.mat = 'wall'; _hit.c = c; _hit.r = r; }
        break;
      }
      if (cell.spans.length && cell !== ignoreCell) {
        const yIn = o.y + d.y * tEnter, yOut = o.y + d.y * tExit;
        for (const s of cell.spans) {
          let th = -1, side = false;
          if (yIn >= s[0] && yIn <= s[1]) { th = tEnter; side = true; }
          else if (yIn > s[1] && yOut <= s[1] && d.y < 0) th = (s[1] - o.y) / d.y;
          else if (yIn < s[0] && yOut >= s[0] && d.y > 0) th = (s[0] - o.y) / d.y;
          if (th >= 0 && th < best) {
            best = th; found = true; _hit.mat = cell.mat; _hit.c = c; _hit.r = r;
            if (side) {
              if (enterAxis < 0) { _hit.nx = -d.x; _hit.ny = -d.y; _hit.nz = -d.z; } else setSideNormal(enterAxis, stepC, stepR);
            } else { _hit.nx = 0; _hit.nz = 0; _hit.ny = d.y < 0 ? 1 : -1; }
          }
        }
      }
      if (tMaxX < tMaxZ) { tEnter = tMaxX; tMaxX += tDeltaX; c += stepC; enterAxis = 0; }
      else { tEnter = tMaxZ; tMaxZ += tDeltaZ; r += stepR; enterAxis = 1; }
      if (tEnter >= best) break;
    }
    if (!found) return null;
    _hit.t = best;
    return _hit;
  }
  function setSideNormal(axis, sc, sr) {
    if (axis === 0) { _hit.nx = -sc; _hit.ny = 0; _hit.nz = 0; } else { _hit.nx = 0; _hit.ny = 0; _hit.nz = -sr; }
  }
  const _d = new V3();
  /** Linha de visão livre entre dois pontos (ignora fumaça; ver MP.world.losClear). */
  function segmentClear(a, b) {
    _d.subVectors(b, a); const len = _d.len(); if (len < 1e-4) return true;
    _d.scale(1 / len);
    return raycast(a, _d, len - 0.05) === null;
  }

  // Navegação -------------------------------------------------------------------
  const walkable = new Uint8Array(W * H);
  const floorH = new Float32Array(W * H);
  for (let i = 0; i < W * H; i++) {
    const cell = cells[i];
    if (cell.floor !== null && cell.floor !== undefined) { walkable[i] = 1; floorH[i] = cell.floor; }
  }
  const nbrs = [];
  for (let i = 0; i < W * H; i++) {
    const list = [];
    if (walkable[i]) {
      const c = i % W, r = (i / W) | 0;
      for (let dr = -1; dr <= 1; dr++) for (let dc = -1; dc <= 1; dc++) {
        if (!dc && !dr) continue;
        const nc = c + dc, nr = r + dr;
        if (nc < 0 || nr < 0 || nc >= W || nr >= H) continue;
        const j = nr * W + nc;
        if (!walkable[j] || Math.abs(floorH[j] - floorH[i]) > 0.45) continue;
        if (dc && dr) { // diagonais só sem cortar quinas
          const a = r * W + nc, b = nr * W + c;
          if (!walkable[a] || !walkable[b] || Math.abs(floorH[a] - floorH[i]) > 0.45 || Math.abs(floorH[b] - floorH[i]) > 0.45) continue;
        }
        list.push(j, dc && dr ? 1.4142 : 1);
      }
    }
    nbrs.push(list);
  }
  const gScore = new Float32Array(W * H), cameFrom = new Int32Array(W * H), closed = new Uint8Array(W * H);
  const heap = new MP.MinHeap();
  /** A* na grade. extraCost(i) opcional para evitar perigos (fogo, rotas aleatórias). Retorna lista de índices. */
  function findPath(fromIdx, toIdx, extraCost) {
    if (fromIdx < 0 || toIdx < 0 || !walkable[fromIdx] || !walkable[toIdx]) return null;
    gScore.fill(1e9); cameFrom.fill(-1); closed.fill(0); heap.clear();
    const tc = toIdx % W, tr = (toIdx / W) | 0;
    gScore[fromIdx] = 0; heap.push(fromIdx, 0);
    let expanded = 0;
    while (heap.size) {
      const cur = heap.pop();
      if (cur === toIdx) break;
      if (closed[cur]) continue;
      closed[cur] = 1;
      if (++expanded > 4000) return null;
      const list = nbrs[cur];
      for (let k = 0; k < list.length; k += 2) {
        const j = list[k]; if (closed[j]) continue;
        const g = gScore[cur] + list[k + 1] + (extraCost ? extraCost(j) : 0);
        if (g < gScore[j]) {
          gScore[j] = g; cameFrom[j] = cur;
          const jc = j % W, jr = (j / W) | 0;
          const dx = Math.abs(jc - tc), dz = Math.abs(jr - tr);
          heap.push(j, g + Math.max(dx, dz) + 0.4142 * Math.min(dx, dz));
        }
      }
    }
    if (cameFrom[toIdx] < 0 && fromIdx !== toIdx) return null;
    const path = [];
    for (let i = toIdx; i !== -1; i = cameFrom[i]) { path.push(i); if (i === fromIdx) break; }
    path.reverse();
    return path;
  }
  /** Verifica se é possível andar em linha reta (com folga lateral) entre dois pontos. */
  function walkLineClear(ax, az, bx, bz, radius) {
    const dx = bx - ax, dz = bz - az; const len = Math.sqrt(dx * dx + dz * dz);
    if (len < 0.01) return true;
    const steps = Math.ceil(len / 0.5);
    const px = -dz / len * radius, pz = dx / len * radius;
    let prevH = null;
    for (let s = 0; s <= steps; s++) {
      const t = s / steps; const x = ax + dx * t, z = az + dz * t;
      for (let k = -1; k <= 1; k++) {
        const i = idxOf(x + px * k, z + pz * k);
        if (i < 0 || !walkable[i]) return false;
        if (k === 0) { if (prevH !== null && Math.abs(floorH[i] - prevH) > 0.45) return false; prevH = floorH[i]; }
      }
    }
    return true;
  }
  /** Converte caminho de índices em pontos suavizados (puxando o fio). */
  function smoothPath(startPos, idxPath, radius) {
    const pts = idxPath.map(i => new V3(cellX(i % W), floorH[i], cellZ((i / W) | 0)));
    if (pts.length <= 2) return pts.slice(1).length ? pts.slice(1) : pts;
    const out = [];
    let anchor = new V3(startPos.x, 0, startPos.z);
    let i = 0;
    while (i < pts.length - 1) {
      let far = i + 1;
      for (let j = pts.length - 1; j > i + 1; j--) {
        if (walkLineClear(anchor.x, anchor.z, pts[j].x, pts[j].z, radius)) { far = j; break; }
      }
      out.push(pts[far]);
      anchor = pts[far]; i = far;
    }
    return out;
  }
  function idxOf(x, z) {
    const c = colOf(x), r = rowOf(z);
    if (c < 0 || r < 0 || c >= W || r >= H) return -1;
    return r * W + c;
  }
  /** Célula caminhável mais próxima (busca em anel). */
  function nearestWalkable(x, z, maxRing = 6) {
    const c0 = colOf(x), r0 = rowOf(z);
    for (let ring = 0; ring <= maxRing; ring++) {
      let best = -1, bd = 1e9;
      for (let dr = -ring; dr <= ring; dr++) for (let dc = -ring; dc <= ring; dc++) {
        if (Math.max(Math.abs(dr), Math.abs(dc)) !== ring) continue;
        const c = c0 + dc, r = r0 + dr;
        if (c < 0 || r < 0 || c >= W || r >= H) continue;
        const i = r * W + c; if (!walkable[i]) continue;
        const d = (cellX(c) - x) ** 2 + (cellZ(r) - z) ** 2;
        if (d < bd) { bd = d; best = i; }
      }
      if (best >= 0) return best;
    }
    return -1;
  }
  function zoneAt(x, z) {
    const c = colOf(x), r = rowOf(z);
    // zonas mais específicas primeiro (menor área)
    let best = null, bestA = 1e9;
    for (const zn of zones) {
      if (c >= zn.c0 && c <= zn.c1 && r >= zn.r0 && r <= zn.r1) {
        const a = (zn.c1 - zn.c0 + 1) * (zn.r1 - zn.r0 + 1);
        if (a < bestA) { bestA = a; best = zn; }
      }
    }
    return best;
  }
  function inPlantZone(x, z) {
    const c = colOf(x), r = rowOf(z);
    for (const k of ['A', 'B']) { const p = plantZones[k]; if (c >= p.c0 && c <= p.c1 && r >= p.r0 && r <= p.r1) return k; }
    return null;
  }
  function cellsInRect(rc, filterWalk = true) {
    const out = [];
    for (let r = rc.r0; r <= rc.r1; r++) for (let c = rc.c0; c <= rc.c1; c++) { const i = r * W + c; if (!filterWalk || walkable[i]) out.push(i); }
    return out;
  }
  function idxPos(i, out) { return (out || new V3()).set(cellX(i % W), floorH[i], cellZ((i / W) | 0)); }

  // Pontos táticos -----------------------------------------------------------------
  // Spawns
  const spawns = {
    T: [[20, 34], [22, 34], [24, 34], [26, 34], [21, 36], [23, 36], [25, 36], [27, 37], [22, 37], [24, 37]],
    CT: [[21, 2], [23, 2], [25, 2], [22, 4], [24, 4], [26, 4], [21, 3], [26, 2], [23, 4], [25, 3]]
  };
  const buyZones = { T: { c0: 17, r0: 33, c1: 30, r1: 38 }, CT: { c0: 19, r0: 1, c1: 28, r1: 5 } };
  // Posições de defesa CT (célula + direção do olhar em direção ao estrangulamento)
  const holds = {
    A: [{ c: 8, r: 7, look: [4, 16] }, { c: 14, r: 7, look: [12, 15] }, { c: 3, r: 6, look: [4, 22] }, { c: 12, r: 4, look: [8, 14] }],
    B: [{ c: 39, r: 7, look: [40, 16] }, { c: 36, r: 11, look: [34, 15] }, { c: 44, r: 6, look: [41, 16] }, { c: 35, r: 4, look: [38, 14] }],
    mid: [{ c: 22, r: 7, look: [21, 14] }, { c: 25, r: 6, look: [22, 14] }]
  };
  // Rotas T: sequência de células intermediárias até o site
  const routes = {
    A: [
      { name: 'A Longo', via: [[10, 32], [4, 28], [4, 22], [4, 16]] },
      { name: 'Passarela', via: [[23, 30], [23, 22], [20, 16], [16, 16], [12, 14]] }
    ],
    B: [
      { name: 'Túnel B', via: [[34, 32], [40, 28], [40, 20], [40, 15]] },
      { name: 'Apartamentos', via: [[23, 30], [24, 22], [28, 20], [34, 18], [34, 15]] }
    ]
  };
  // Pontos de fumaça para executar o site (alvo de lançamento)
  const smokeSpots = { A: [[9, 4], [13, 12]], B: [[38, 4], [34, 10]] };

  MP.map = {
    W, H, S, OX, OZ, grid, cells, zones, plantZones, spawns, buyZones, holds, routes, smokeSpots,
    walkable, floorH,
    cellX, cellZ, colOf, rowOf, cellAt, idxOf, idxPos,
    boxBlocked, groundBelow, pointSolid, raycast, segmentClear,
    findPath, smoothPath, walkLineClear, nearestWalkable, zoneAt, inPlantZone, cellsInRect,
    toAscii() { return grid.map(row => row.join('')).join('\n'); }
  };
})(typeof window !== 'undefined' ? window : globalThis);
