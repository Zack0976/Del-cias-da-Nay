/* Mirage Protocol — arsenal: definições de armas/equipamentos e estado de arma (munição, recarga, recuo). */
(function (root) {
  'use strict';
  const MP = root.MP;
  const M = MP.math;
  const DEG = Math.PI / 180;

  /* Campos:
   *  dmg: dano base por projétil   rpm: cadência     mode: semi|auto|bolt|pump|melee|grenade|bomb
   *  mag, reserve: munição         reload: s (mag) ou s por cartucho (shell)
   *  spread: dispersão base (rad, parado)          moveSpread: extra em velocidade máxima
   *  airSpread: extra no ar        recoil: chute vertical por tiro (rad)   recoilH: oscilação horizontal
   *  recovery: recuperação da mira (rad/s)          range: alcance efetivo (m), falloff: fração mantida a cada 10 m além do alcance
   *  head/chest/stomach/legs: multiplicadores        armorPen: fração do dano que atravessa o colete
   *  draw: tempo de troca (s)  speed: multiplicador de velocidade  cost  team: T|CT|null  kill: recompensa
   *  pellets: fragmentos (escopeta)  zoom: níveis de FOV  pen: penetração em madeira (m)
   */
  const W = {
    // ---------------------------------------------------------------- pistolas
    viper: { name: 'Viper-17', cat: 'pistol', slot: 'secondary', mode: 'semi', dmg: 30, rpm: 400, mag: 20, reserve: 120, reload: 2.2,
      spread: 0.9 * DEG, moveSpread: 2.6 * DEG, airSpread: 6 * DEG, recoil: 1.6 * DEG, recoilH: 0.6 * DEG, recovery: 9 * DEG,
      range: 22, falloff: 0.85, head: 4, chest: 1, stomach: 1.25, legs: 0.75, armorPen: 0.47, draw: 0.55, speed: 1.0, cost: 200, team: 'T', kill: 300, pen: 0.1, model: 'pistol', icon: 'P' },
    lince: { name: 'Lince P9', cat: 'pistol', slot: 'secondary', mode: 'semi', dmg: 35, rpm: 352, mag: 12, reserve: 72, reload: 2.2,
      spread: 0.6 * DEG, moveSpread: 2.4 * DEG, airSpread: 6 * DEG, recoil: 1.8 * DEG, recoilH: 0.5 * DEG, recovery: 9 * DEG,
      range: 26, falloff: 0.88, head: 4, chest: 1, stomach: 1.25, legs: 0.75, armorPen: 0.5, draw: 0.55, speed: 1.0, cost: 200, team: 'CT', kill: 300, pen: 0.1, model: 'pistol', icon: 'P' },
    falcao: { name: 'Falcão .50', cat: 'pistol', slot: 'secondary', mode: 'semi', dmg: 63, rpm: 267, mag: 7, reserve: 35, reload: 2.2,
      spread: 0.8 * DEG, moveSpread: 4.5 * DEG, airSpread: 8 * DEG, recoil: 5.5 * DEG, recoilH: 1.2 * DEG, recovery: 7 * DEG,
      range: 30, falloff: 0.82, head: 4, chest: 1, stomach: 1.25, legs: 0.75, armorPen: 0.93, draw: 0.75, speed: 0.95, cost: 700, team: null, kill: 300, pen: 0.4, model: 'heavypistol', icon: 'D' },
    rhino: { name: 'Rhino R8', cat: 'pistol', slot: 'secondary', mode: 'semi', dmg: 86, rpm: 120, mag: 8, reserve: 8, reload: 2.3,
      spread: 0.5 * DEG, moveSpread: 4 * DEG, airSpread: 8 * DEG, recoil: 7 * DEG, recoilH: 1.5 * DEG, recovery: 7 * DEG,
      range: 30, falloff: 0.86, head: 4, chest: 1, stomach: 1.25, legs: 0.75, armorPen: 0.93, draw: 0.85, speed: 0.95, cost: 600, team: null, kill: 300, pen: 0.4, model: 'revolver', icon: 'R' },
    // ---------------------------------------------------------------- submetralhadoras
    vespa: { name: 'Vespa C9', cat: 'smg', slot: 'primary', mode: 'auto', dmg: 29, rpm: 800, mag: 30, reserve: 100, reload: 2.6,
      spread: 1.1 * DEG, moveSpread: 1.8 * DEG, airSpread: 7 * DEG, recoil: 0.9 * DEG, recoilH: 0.7 * DEG, recovery: 10 * DEG,
      range: 18, falloff: 0.8, head: 4, chest: 1, stomach: 1.25, legs: 0.75, armorPen: 0.58, draw: 0.6, speed: 0.96, cost: 1050, team: 'T', kill: 600, pen: 0.15, model: 'smg', icon: 'S' },
    ciclone: { name: 'Ciclone 50', cat: 'smg', slot: 'primary', mode: 'auto', dmg: 25, rpm: 900, mag: 50, reserve: 100, reload: 3.3,
      spread: 1.0 * DEG, moveSpread: 1.6 * DEG, airSpread: 7 * DEG, recoil: 0.65 * DEG, recoilH: 0.55 * DEG, recovery: 10 * DEG,
      range: 20, falloff: 0.84, head: 4, chest: 1, stomach: 1.25, legs: 0.75, armorPen: 0.69, draw: 0.65, speed: 0.95, cost: 2350, team: null, kill: 300, pen: 0.2, model: 'smg2', icon: 'S' },
    sentinela: { name: 'Sentinela SD', cat: 'smg', slot: 'primary', mode: 'auto', dmg: 27, rpm: 750, mag: 30, reserve: 120, reload: 2.9,
      spread: 0.55 * DEG, moveSpread: 1.4 * DEG, airSpread: 7 * DEG, recoil: 0.7 * DEG, recoilH: 0.35 * DEG, recovery: 11 * DEG,
      range: 24, falloff: 0.86, head: 4, chest: 1, stomach: 1.25, legs: 0.75, armorPen: 0.62, draw: 0.6, speed: 0.95, cost: 1500, team: null, kill: 600, pen: 0.15, model: 'smg3', icon: 'S' },
    // ---------------------------------------------------------------- fuzis
    guardiao: { name: 'Guardião M4', cat: 'rifle', slot: 'primary', mode: 'auto', dmg: 33, rpm: 666, mag: 30, reserve: 90, reload: 3.1,
      spread: 0.32 * DEG, moveSpread: 4.5 * DEG, airSpread: 9 * DEG, recoil: 1.05 * DEG, recoilH: 0.75 * DEG, recovery: 12 * DEG,
      range: 45, falloff: 0.97, head: 4, chest: 1, stomach: 1.25, legs: 0.75, armorPen: 0.7, draw: 0.8, speed: 0.9, cost: 2900, team: 'CT', kill: 300, pen: 0.45, model: 'rifle', icon: 'M' },
    tempestade: { name: 'Tempestade AR', cat: 'rifle', slot: 'primary', mode: 'auto', dmg: 30, rpm: 750, mag: 35, reserve: 90, reload: 3.0,
      spread: 0.45 * DEG, moveSpread: 4.2 * DEG, airSpread: 9 * DEG, recoil: 1.0 * DEG, recoilH: 0.9 * DEG, recovery: 11 * DEG,
      range: 38, falloff: 0.95, head: 4, chest: 1, stomach: 1.25, legs: 0.75, armorPen: 0.7, draw: 0.75, speed: 0.92, cost: 2000, team: null, kill: 300, pen: 0.4, model: 'rifle2', icon: 'G' },
    brutus: { name: 'Brutus K7', cat: 'rifle', slot: 'primary', mode: 'auto', dmg: 36, rpm: 600, mag: 30, reserve: 90, reload: 2.5,
      spread: 0.38 * DEG, moveSpread: 5 * DEG, airSpread: 9 * DEG, recoil: 1.35 * DEG, recoilH: 1.0 * DEG, recovery: 11 * DEG,
      range: 45, falloff: 0.98, head: 4, chest: 1, stomach: 1.25, legs: 0.75, armorPen: 0.775, draw: 0.8, speed: 0.86, cost: 2700, team: 'T', kill: 300, pen: 0.5, model: 'rifle3', icon: 'K' },
    escorpiao: { name: 'Escorpião DMR', cat: 'sniper', slot: 'primary', mode: 'semi', dmg: 70, rpm: 240, mag: 20, reserve: 60, reload: 3.4,
      spread: 1.6 * DEG, scopedSpread: 0.12 * DEG, moveSpread: 6 * DEG, airSpread: 12 * DEG, recoil: 2.2 * DEG, recoilH: 0.6 * DEG, recovery: 9 * DEG,
      range: 70, falloff: 0.98, head: 4, chest: 1, stomach: 1.25, legs: 0.75, armorPen: 0.83, draw: 0.9, speed: 0.84, cost: 3800, team: null, kill: 300, pen: 0.6, model: 'dmr', zoom: [40, 18], icon: 'E' },
    mamba: { name: 'Mamba .338', cat: 'sniper', slot: 'primary', mode: 'bolt', dmg: 115, rpm: 41, mag: 5, reserve: 30, reload: 3.6,
      spread: 6 * DEG, scopedSpread: 0.05 * DEG, moveSpread: 9 * DEG, airSpread: 15 * DEG, recoil: 4 * DEG, recoilH: 0.5 * DEG, recovery: 6 * DEG,
      range: 120, falloff: 0.99, head: 4, chest: 1, stomach: 1.25, legs: 0.75, armorPen: 0.98, draw: 1.1, speed: 0.8, cost: 4750, team: null, kill: 100, pen: 0.9, model: 'awp', zoom: [40, 12], icon: 'A' },
    // ---------------------------------------------------------------- pesadas
    trovao: { name: 'Trovão 12', cat: 'heavy', slot: 'primary', mode: 'pump', dmg: 25, pellets: 9, rpm: 68, mag: 8, reserve: 32, reload: 0.5, reloadType: 'shell',
      spread: 4.2 * DEG, moveSpread: 1.0 * DEG, airSpread: 4 * DEG, recoil: 5 * DEG, recoilH: 1.0 * DEG, recovery: 7 * DEG,
      range: 9, falloff: 0.55, head: 2.2, chest: 1, stomach: 1.25, legs: 0.75, armorPen: 0.75, draw: 0.8, speed: 0.88, cost: 1200, team: null, kill: 900, pen: 0, model: 'shotgun', icon: 'X' },
    martelo: { name: 'Martelo M249', cat: 'heavy', slot: 'primary', mode: 'auto', dmg: 32, rpm: 750, mag: 100, reserve: 200, reload: 5.5,
      spread: 0.9 * DEG, moveSpread: 6 * DEG, airSpread: 10 * DEG, recoil: 0.85 * DEG, recoilH: 1.1 * DEG, recovery: 9 * DEG,
      range: 40, falloff: 0.96, head: 4, chest: 1, stomach: 1.25, legs: 0.75, armorPen: 0.8, draw: 1.0, speed: 0.78, cost: 5200, team: null, kill: 300, pen: 0.5, model: 'lmg', icon: 'L' },
    // ---------------------------------------------------------------- corpo a corpo e utilitários
    knife: { name: 'Faca de Combate', cat: 'knife', slot: 'knife', mode: 'melee', dmg: 40, dmg2: 65, rpm: 150, mag: 0, reserve: 0, reload: 0,
      spread: 0, moveSpread: 0, airSpread: 0, recoil: 0, recoilH: 0, recovery: 1,
      range: 1.7, falloff: 1, head: 1, chest: 1, stomach: 1, legs: 1, armorPen: 0.85, draw: 0.4, speed: 1.04, cost: 0, team: null, kill: 1500, model: 'knife', icon: 'F' },
    he: { name: 'Granada HE', cat: 'grenade', slot: 'grenade', mode: 'grenade', gtype: 'he', cost: 300, max: 1, draw: 0.5, speed: 1.0, model: 'grenade', icon: 'H', kill: 300 },
    flash: { name: 'Granada de Luz', cat: 'grenade', slot: 'grenade', mode: 'grenade', gtype: 'flash', cost: 200, max: 2, draw: 0.5, speed: 1.0, model: 'flash', icon: 'L', kill: 300 },
    smoke: { name: 'Granada de Fumaça', cat: 'grenade', slot: 'grenade', mode: 'grenade', gtype: 'smoke', cost: 300, max: 1, draw: 0.5, speed: 1.0, model: 'smoke', icon: 'F', kill: 300 },
    molotov: { name: 'Coquetel Incendiário', cat: 'grenade', slot: 'grenade', mode: 'grenade', gtype: 'molotov', cost: 400, max: 1, draw: 0.5, speed: 1.0, model: 'molotov', icon: 'I', team: 'T', kill: 300 },
    incend: { name: 'Granada Incendiária', cat: 'grenade', slot: 'grenade', mode: 'grenade', gtype: 'molotov', cost: 600, max: 1, draw: 0.5, speed: 1.0, model: 'incend', icon: 'I', team: 'CT', kill: 300 },
    bomb: { name: 'Explosivo C-7', cat: 'bomb', slot: 'bomb', mode: 'bomb', draw: 0.6, speed: 1.0, model: 'bomb', icon: 'C' }
  };
  for (const k of Object.keys(W)) W[k].id = k;
  MP.WEAPONS = W;

  // Itens de equipamento (não são armas)
  MP.GEAR = {
    vest: { id: 'vest', name: 'Colete', cost: 650 },
    vesthelm: { id: 'vesthelm', name: 'Colete + Capacete', cost: 1000 },
    kit: { id: 'kit', name: 'Kit de Desarme', cost: 400, team: 'CT' }
  };

  MP.BUY_MENU = [
    { cat: 'Pistolas', items: ['viper', 'lince', 'falcao', 'rhino'] },
    { cat: 'Submetralhadoras', items: ['vespa', 'sentinela', 'ciclone'] },
    { cat: 'Fuzis', items: ['tempestade', 'brutus', 'guardiao', 'escorpiao', 'mamba'] },
    { cat: 'Pesadas', items: ['trovao', 'martelo'] },
    { cat: 'Granadas', items: ['he', 'flash', 'smoke', 'molotov', 'incend'] },
    { cat: 'Equipamento', items: ['vest', 'vesthelm', 'kit'] }
  ];

  /** Estado de uma arma possuída por um agente. Mesmas regras para jogador e bots. */
  class WeaponState {
    constructor(id) {
      this.def = W[id];
      if (!this.def) throw new Error('Arma desconhecida: ' + id);
      this.id = id;
      this.clip = this.def.mag || 0;
      this.reserve = this.def.reserve || 0;
      this.nextFire = 0;        // tempo (s) mínimo do próximo disparo
      this.reloading = false;
      this.reloadEnd = 0;
      this.reloadStart = 0;
      this.shotsFired = 0;      // contador de rajada (recuo progressivo)
      this.lastShot = -10;
      this.triggerHeld = false; // para semiautomáticas
      this.zoomLevel = 0;       // 0 = sem mira
    }
    get interval() { return 60 / this.def.rpm; }
    canReload() { return !!this.def.mag && !this.reloading && this.clip < this.def.mag && this.reserve > 0; }
    startReload(now) {
      if (!this.canReload()) return false;
      this.reloading = true; this.reloadStart = now;
      this.reloadEnd = now + this.def.reload;
      this.zoomLevel = 0;
      return true;
    }
    cancelReload() { this.reloading = false; }
    /** Avança a recarga; retorna 'done' | 'shell' | null. */
    updateReload(now) {
      if (!this.reloading || now < this.reloadEnd) return null;
      if (this.def.reloadType === 'shell') {
        if (this.reserve > 0 && this.clip < this.def.mag) { this.clip++; this.reserve--; }
        if (this.clip >= this.def.mag || this.reserve <= 0) { this.reloading = false; return 'done'; }
        this.reloadEnd = now + this.def.reload; return 'shell';
      }
      const need = this.def.mag - this.clip;
      const take = Math.min(need, this.reserve);
      this.clip += take; this.reserve -= take;
      this.reloading = false;
      return 'done';
    }
    reloadProgress(now) {
      if (!this.reloading) return 0;
      if (this.def.reloadType === 'shell') return M.clamp(this.clip / this.def.mag, 0, 1);
      return M.clamp((now - this.reloadStart) / (this.reloadEnd - this.reloadStart), 0, 1);
    }
    refill() { this.clip = this.def.mag || 0; this.reserve = this.def.reserve || 0; this.reloading = false; }
  }
  MP.WeaponState = WeaponState;
})(typeof window !== 'undefined' ? window : globalThis);
