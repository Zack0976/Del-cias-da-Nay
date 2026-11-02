class_name Sons
extends RefCounted
## Sons feitos 100% por código (sem arquivos de áudio!).
## Cada função cria um AudioStreamWAV: uma "gravação" montada amostra por amostra.
##
## Como usar:
##     Sons.tocar(self, Sons.batida())             # toca uma vez
##     var vento := Sons.tocar_loop(self, Sons.vento(), -12.0)   # fica tocando
##
## Dica: os sons "loop" já vêm com repetição ligada, então tocam para sempre
## até você chamar .stop() ou apagar o nó.

const TAXA := 22050  # amostras por segundo (qualidade suficiente e leve pro celular)

static var _cache := {}  # guarda sons já criados, para não recalcular toda vez
static var _trava := Mutex.new()  # protege o _cache quando uma "thread" também está criando sons

## CACHE EM DISCO: o som é calculado UMA vez e salvo no celular.
## Nas próximas vezes ele só é carregado (muito mais rápido do que calcular de novo).
## Se você mudar o jeito de gerar algum som, aumente a VERSÃO para refazer o cache.
const VERSAO_CACHE := 2
const PASTA_CACHE := "user://cache/sons_v%d/" % VERSAO_CACHE

## Lista de todos os sons (usada para "pré-aquecer" o cache no começo do jogo).
const TODOS := ["vento", "chiado", "grilos", "fogueira", "drone", "motor", "clique", "batida", "galho",
	"coruja", "despertador", "microfonia", "grito", "passo", "rangido", "item", "violao"]


## Sons "pré-assados": já vêm prontos dentro do projeto (pasta Sons/gerados).
## Assim o celular NUNCA precisa calcular os sons — abre na hora.
const PASTA_PRONTOS := "res://Sons/gerados/"

## No Mali-G68, WAV grandes em loop crasham o motor. Só estes são seguros:
const SONS_LEVES_MOBILE := ["clique", "batida", "passo", "galho", "item", "grito", "rangido"]
## Sons pesados (nunca em loop no mobile):
const SONS_PESADOS := ["vento", "drone", "violao", "fogueira", "chiado", "grilos", "motor", "grito", "coruja", "despertador", "microfonia", "rangido"]



static func _do_cache(nome: String) -> AudioStreamWAV:
	_trava.lock()
	var s: AudioStreamWAV = _cache.get(nome)
	_trava.unlock()
	if s:
		return s
	# 1º lugar: o som pronto que vem junto com o jogo
	var pronto := PASTA_PRONTOS + nome + ".res"
	if ResourceLoader.exists(pronto):
		s = load(pronto) as AudioStreamWAV
		if s:
			_trava.lock()
			_cache[nome] = s
			_trava.unlock()
			return s
	# 2º lugar: o cache salvo no celular
	var caminho := PASTA_CACHE + nome + ".res"
	if FileAccess.file_exists(caminho):
		s = ResourceLoader.load(caminho, "", ResourceLoader.CACHE_MODE_IGNORE) as AudioStreamWAV
		if s:
			_trava.lock()
			_cache[nome] = s
			_trava.unlock()
	return s


static func _guardar(nome: String, som: AudioStreamWAV) -> AudioStreamWAV:
	_trava.lock()
	if _cache.has(nome):  # outra thread terminou primeiro: usa o dela
		var existente: AudioStreamWAV = _cache[nome]
		_trava.unlock()
		return existente
	_cache[nome] = som
	_trava.unlock()
	# Salva num arquivo temporário e só depois renomeia: se o jogo fechar no meio,
	# nunca fica um arquivo de cache "pela metade" (que poderia dar erro depois).
	DirAccess.make_dir_recursive_absolute(PASTA_CACHE)
	var temp := PASTA_CACHE + nome + ".tmp.res"
	if ResourceSaver.save(som, temp, ResourceSaver.FLAG_COMPRESS) == OK:
		DirAccess.rename_absolute(temp, PASTA_CACHE + nome + ".res")
	return som


## Cria (ou carrega do disco) todos os sons. O GameData chama isto numa thread
## logo que o jogo abre, assim nenhuma cena trava esperando som ficar pronto.
static func preaquecer() -> void:
	for nome in TODOS:
		Callable(Sons, nome).call()


static func limpar_cache_memoria() -> void:
	_trava.lock()
	_cache.clear()
	_trava.unlock()


# ---------------------------------------------------------------
# AJUDANTES
# ---------------------------------------------------------------

## Transforma uma lista de números (-1.0 a 1.0) em um som WAV de 16 bits.
static func _criar_wav(amostras: PackedFloat32Array, repetir := false) -> AudioStreamWAV:
	var dados := PackedByteArray()
	dados.resize(amostras.size() * 2)
	for i in amostras.size():
		var v := int(clampf(amostras[i], -1.0, 1.0) * 32767.0)
		dados.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = TAXA
	wav.stereo = false
	wav.data = dados
	if repetir:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = amostras.size()
	return wav


## Limite de loops no mobile (vários WAV grandes crasham o Mali-G68).
static var _loops_ativos: Array = []
const MAX_LOOPS_MOBILE := 1
const MAX_LOOPS_PC := 6


static func _limpar_loops_mortos() -> void:
	var vivos: Array = []
	for p in _loops_ativos:
		if is_instance_valid(p):
			vivos.append(p)
	_loops_ativos = vivos


static func _registrar_loop(p: AudioStreamPlayer) -> void:
	_limpar_loops_mortos()
	var limite := MAX_LOOPS_MOBILE if GameData.eh_mobile else MAX_LOOPS_PC
	while _loops_ativos.size() >= limite:
		var velho = _loops_ativos.pop_front()
		if is_instance_valid(velho):
			velho.stop()
			velho.queue_free()
	_loops_ativos.append(p)


## Carrega por nome. No mobile NÃO gera som na hora (só usa .res prontos).
static func carregar(nome: String) -> AudioStream:
	if not GameData.som_ligado:
		return null
	var s := _do_cache(nome)
	if s:
		return s
	# Mobile: se não tem .res, ignora (gerar crashava)
	if GameData.eh_mobile:
		push_warning("Som ausente, ignorando no mobile: " + nome)
		return null
	if nome in TODOS:
		return Callable(Sons, nome).call()
	return null


## Toca uma vez. `som` pode ser AudioStream OU String (nome).
## No mobile só toca arquivos leves (clique/passo/batida...).
static func tocar(dono: Node, som, volume_db := 0.0, tom := 1.0, barramento := "Efeitos") -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	dono.add_child(p)
	if not GameData.som_ligado:
		p.queue_free()
		return p
	if GameData.eh_mobile and som is String and str(som) not in SONS_LEVES_MOBILE:
		# Som pesado no mobile: ignora (evita crash)
		p.queue_free()
		return p
	var stream: AudioStream = null
	if som is String:
		stream = carregar(str(som))
	elif som is AudioStream:
		# AudioStream gerado (voz_radio etc.): perigoso no mobile
		if GameData.eh_mobile:
			p.queue_free()
			return p
		stream = som
	if stream == null:
		p.queue_free()
		return p
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = tom
	if AudioServer.get_bus_index(barramento) >= 0:
		p.bus = barramento
	p.play()
	p.finished.connect(p.queue_free)
	return p


## Loop. No mobile: DESATIVADO (vento/drone crasham o Mali-G68).
## Retorna player mudo para o resto do código não quebrar.
static func tocar_loop(dono: Node, som, volume_db := 0.0, barramento := "Musica") -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	dono.add_child(p)
	if not GameData.som_ligado:
		return p
	# Mobile: zero loops de ambiente. Um WAV de 160KB em loop = crash nativo.
	if GameData.eh_mobile:
		GameData.log_passo("audio: loop ignorado no mobile (%s)" % str(som))
		return p
	var stream: AudioStream = null
	if som is String:
		stream = carregar(str(som))
	elif som is AudioStream:
		stream = som
	if stream == null:
		return p
	p.stream = stream
	p.volume_db = volume_db
	if AudioServer.get_bus_index(barramento) >= 0:
		p.bus = barramento
	_registrar_loop(p)
	p.play()
	return p


static func fade(player: AudioStreamPlayer, volume_final_db: float, duracao: float) -> void:
	if player == null or not is_instance_valid(player) or player.stream == null:
		return
	var tw := player.create_tween()
	tw.tween_property(player, "volume_db", volume_final_db, duracao)


static func _envelope(t: float, ataque: float, duracao: float) -> float:
	if t < ataque:
		return t / ataque
	return clampf(1.0 - (t - ataque) / maxf(duracao - ataque, 0.0001), 0.0, 1.0)


# ---------------------------------------------------------------
# SONS EM LOOP (ambiente)
# ---------------------------------------------------------------

## Vento: ruído suavizado que sobe e desce devagar.
static func vento() -> AudioStreamWAV:
	var _c := _do_cache("vento")
	if _c:
		return _c
	var n := TAXA * 4
	var a := PackedFloat32Array()
	a.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var filtro := 0.0
	for i in n:
		var t := float(i) / n
		filtro = lerpf(filtro, rng.randf_range(-1.0, 1.0), 0.02)  # "passa-baixa": deixa o som grave
		var rajada := 0.55 + 0.45 * sin(TAU * t * 2.0)            # 2 rajadas por volta (fecha o loop certinho)
		a[i] = filtro * 2.2 * rajada
	return _guardar("vento", _criar_wav(a, true))


## Chiado de rádio: ruído agudo com "estalos".
static func chiado() -> AudioStreamWAV:
	var _c := _do_cache("chiado")
	if _c:
		return _c
	var n := TAXA * 2
	var a := PackedFloat32Array()
	a.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var anterior := 0.0
	for i in n:
		var r := rng.randf_range(-1.0, 1.0)
		var agudo := r - anterior * 0.6   # "passa-alta": deixa o som chiado
		anterior = r
		var estalo := 0.0
		if rng.randf() < 0.0008:
			estalo = rng.randf_range(-1.0, 1.0)
		a[i] = agudo * 0.35 + estalo
	return _guardar("chiado", _criar_wav(a, true))


## Grilos/insetos da noite.
static func grilos() -> AudioStreamWAV:
	var _c := _do_cache("grilos")
	if _c:
		return _c
	var n := TAXA * 3
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / TAXA
		var pulso := 1.0 if fmod(t * 3.0, 1.0) < 0.35 else 0.0       # cri-cri-cri
		var tremido := 0.5 + 0.5 * sin(TAU * 40.0 * t)
		a[i] = sin(TAU * 4300.0 * t) * pulso * tremido * 0.12
	return _guardar("grilos", _criar_wav(a, true))


## Fogueira: estalinhos aleatórios sobre um ruído grave.
static func fogueira() -> AudioStreamWAV:
	var _c := _do_cache("fogueira")
	if _c:
		return _c
	var n := TAXA * 3
	var a := PackedFloat32Array()
	a.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var filtro := 0.0
	var estalo := 0.0
	for i in n:
		filtro = lerpf(filtro, rng.randf_range(-1.0, 1.0), 0.05)
		if rng.randf() < 0.0015:
			estalo = rng.randf_range(0.4, 0.9)
		estalo *= 0.995
		a[i] = filtro * 0.8 + rng.randf_range(-1.0, 1.0) * estalo * 0.6
	return _guardar("fogueira", _criar_wav(a, true))


## Zumbido grave e baixinho que dá tensão (o "ruído grave e distante" do roteiro).
static func drone() -> AudioStreamWAV:
	var _c := _do_cache("drone")
	if _c:
		return _c
	var n := TAXA * 4
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / TAXA
		a[i] = (sin(TAU * 55.0 * t) * 0.5 + sin(TAU * 55.5 * t) * 0.4 + sin(TAU * 82.5 * t) * 0.15) * 0.5
	return _guardar("drone", _criar_wav(a, true))


# ---------------------------------------------------------------
# SONS DE UMA VEZ SÓ (efeitos)
# ---------------------------------------------------------------

## Clique (gravador/fita cassete, botão do rádio).
static func clique() -> AudioStreamWAV:
	var _c := _do_cache("clique")
	if _c:
		return _c
	var n := int(TAXA * 0.12)
	var a := PackedFloat32Array()
	a.resize(n)
	var rng := RandomNumberGenerator.new()
	for i in n:
		var t := float(i) / TAXA
		a[i] = rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.9 + sin(TAU * 1800.0 * t) * exp(-t * 60.0) * 0.3
	return _guardar("clique", _criar_wav(a))


## Batida na porta (toc!).
static func batida() -> AudioStreamWAV:
	var _c := _do_cache("batida")
	if _c:
		return _c
	var n := int(TAXA * 0.45)
	var a := PackedFloat32Array()
	a.resize(n)
	var rng := RandomNumberGenerator.new()
	for i in n:
		var t := float(i) / TAXA
		var corpo := sin(TAU * 90.0 * t) * exp(-t * 14.0)
		var madeira := sin(TAU * 210.0 * t) * exp(-t * 30.0) * 0.6
		var impacto := rng.randf_range(-1.0, 1.0) * exp(-t * 120.0) * 0.5
		a[i] = (corpo + madeira + impacto) * 0.9
	return _guardar("batida", _criar_wav(a))


## Galho quebrando (crec!).
static func galho() -> AudioStreamWAV:
	var _c := _do_cache("galho")
	if _c:
		return _c
	var n := int(TAXA * 0.35)
	var a := PackedFloat32Array()
	a.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		var t := float(i) / TAXA
		var rachando := 1.0 if rng.randf() < 0.25 * exp(-t * 8.0) else 0.0
		a[i] = rng.randf_range(-1.0, 1.0) * (exp(-t * 25.0) * 0.8 + rachando * 0.7)
	return _guardar("galho", _criar_wav(a))


## Coruja (hu-huuu).
static func coruja() -> AudioStreamWAV:
	var _c := _do_cache("coruja")
	if _c:
		return _c
	var n := int(TAXA * 1.4)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / TAXA
		var env := 0.0
		if t < 0.3:
			env = sin(PI * t / 0.3)
		elif t > 0.45 and t < 1.3:
			env = sin(PI * (t - 0.45) / 0.85)
		var freq := 380.0 - 40.0 * clampf(t - 0.45, 0.0, 1.0)
		a[i] = sin(TAU * freq * t + sin(TAU * 5.0 * t) * 0.4) * env * 0.5
	return _guardar("coruja", _criar_wav(a))


## Despertador antigo (trimmm).
static func despertador() -> AudioStreamWAV:
	var _c := _do_cache("despertador")
	if _c:
		return _c
	var n := int(TAXA * 1.6)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / TAXA
		var liga := 1.0 if fmod(t, 0.4) < 0.28 else 0.0
		var sino := sin(TAU * 2200.0 * t) * (0.6 + 0.4 * sin(TAU * 28.0 * t))
		a[i] = sino * liga * 0.25
	return _guardar("despertador", _criar_wav(a))


## Ruído agudo do rádio (aquele "piiii" antes da luz apagar).
static func microfonia() -> AudioStreamWAV:
	var _c := _do_cache("microfonia")
	if _c:
		return _c
	var n := int(TAXA * 1.5)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / TAXA
		a[i] = sin(TAU * (2600.0 + 300.0 * t) * t) * _envelope(t, 0.3, 1.5) * 0.35
	return _guardar("microfonia", _criar_wav(a))


## "Voz" distorcida do rádio: um murmúrio filtrado, sem palavras (as palavras ficam na legenda).
static func voz_radio(duracao := 2.5) -> AudioStreamWAV:
	var n := int(TAXA * duracao)
	var a := PackedFloat32Array()
	a.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(duracao * 1000)
	var fase := 0.0
	for i in n:
		var t := float(i) / TAXA
		var silaba := maxf(0.0, sin(TAU * 3.2 * t + sin(TAU * 0.7 * t) * 2.0))
		var freq := 140.0 + 40.0 * sin(TAU * 1.3 * t)
		fase += TAU * freq / TAXA
		var voz := (sin(fase) + sin(fase * 2.0) * 0.5 + sin(fase * 3.0) * 0.25) * silaba
		var ruido := rng.randf_range(-1.0, 1.0) * 0.25
		var corte := 1.0 if rng.randf() > 0.02 else 0.0
		a[i] = clampf((voz * 0.5 + ruido) * corte * 1.6, -0.8, 0.8) * _envelope(t, 0.1, duracao)
	return _criar_wav(a)


## Grito do jumpscare do menu.
static func grito() -> AudioStreamWAV:
	var _c := _do_cache("grito")
	if _c:
		return _c
	var n := int(TAXA * 1.8)
	var a := PackedFloat32Array()
	a.resize(n)
	var rng := RandomNumberGenerator.new()
	for i in n:
		var t := float(i) / TAXA
		var ruido := rng.randf_range(-0.5, 0.5)
		var guincho := sin(TAU * (900.0 + 500.0 * sin(TAU * 7.0 * t)) * t) * 0.5
		var grave := sin(TAU * 60.0 * t) * 0.8
		a[i] = clampf((ruido + guincho + grave) * 0.6, -1.0, 1.0) * (1.0 - t / 1.8)
	return _guardar("grito", _criar_wav(a))


## Passo (tum suave). Varie o tom ao tocar para não ficar repetitivo.
static func passo() -> AudioStreamWAV:
	var _c := _do_cache("passo")
	if _c:
		return _c
	var n := int(TAXA * 0.12)
	var a := PackedFloat32Array()
	a.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var filtro := 0.0
	for i in n:
		var t := float(i) / TAXA
		filtro = lerpf(filtro, rng.randf_range(-1.0, 1.0), 0.15)
		a[i] = filtro * exp(-t * 40.0) * 1.2
	return _guardar("passo", _criar_wav(a))


## Porta rangendo.
static func rangido() -> AudioStreamWAV:
	var _c := _do_cache("rangido")
	if _c:
		return _c
	var n := int(TAXA * 1.0)
	var a := PackedFloat32Array()
	a.resize(n)
	var fase := 0.0
	for i in n:
		var t := float(i) / TAXA
		var freq := 300.0 + 250.0 * sin(PI * t) + 30.0 * sin(TAU * 13.0 * t)
		fase += TAU * freq / TAXA
		var serra := fmod(fase / TAU, 1.0) * 2.0 - 1.0
		a[i] = serra * sin(PI * t) * 0.25
	return _guardar("rangido", _criar_wav(a))


## "Item encontrado" (plim baixinho e sinistro).
static func item() -> AudioStreamWAV:
	var _c := _do_cache("item")
	if _c:
		return _c
	var n := int(TAXA * 0.9)
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / TAXA
		a[i] = (sin(TAU * 659.0 * t) * 0.5 + sin(TAU * 784.0 * t) * 0.3 * (1.0 if t > 0.15 else 0.0)) * exp(-t * 4.0) * 0.5
	return _guardar("item", _criar_wav(a))

## Motor do carro velho (ronco grave em loop).
static func motor() -> AudioStreamWAV:
	var _c := _do_cache("motor")
	if _c:
		return _c
	var n := TAXA * 2
	var a := PackedFloat32Array()
	a.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var filtro := 0.0
	for i in n:
		var t := float(i) / TAXA
		filtro = lerpf(filtro, rng.randf_range(-1.0, 1.0), 0.08)
		var ronco := sin(TAU * 38.0 * t) * 0.5 + sin(TAU * 76.0 * t) * 0.25 + (fmod(t * 38.0, 1.0) - 0.5) * 0.3
		a[i] = (ronco + filtro * 0.5) * (0.85 + 0.15 * sin(TAU * 4.0 * t)) * 0.6
	return _guardar("motor", _criar_wav(a, true))


## Violão do Rafa: arpejo triste em loop, feito com o algoritmo "Karplus-Strong"
## (um ruído curtinho que vai sendo repetido e suavizado vira som de corda!).
## Demora um pouquinho para calcular: chame uma vez no começo (a cutscene faz isso numa thread).
static func violao() -> AudioStreamWAV:
	var _c := _do_cache("violao")
	if _c:
		return _c
	# Lá menor - Fá - Dó - Mi  (cada número é a frequência da nota em Hz)
	var acordes := [
		[110.0, 164.8, 220.0, 261.6, 329.6, 261.6],
		[87.3, 174.6, 220.0, 261.6, 349.2, 261.6],
		[130.8, 196.0, 261.6, 329.6, 392.0, 329.6],
		[82.4, 164.8, 207.7, 246.9, 329.6, 246.9],
	]
	var intervalo := 0.42  # segundos entre notas
	var total := int(TAXA * intervalo * 6 * acordes.size())
	var a := PackedFloat32Array()
	a.resize(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var nota := 0
	for acorde in acordes:
		for f in acorde:
			var inicio := int(nota * intervalo * TAXA)
			var periodo := int(TAXA / f)
			var buf := PackedFloat32Array()
			buf.resize(periodo)
			for k in periodo:
				buf[k] = rng.randf_range(-1.0, 1.0)
			var dur := int(TAXA * 1.3)
			var idx := 0
			for k in dur:
				var prox := (idx + 1) % periodo
				var v := buf[idx]
				buf[idx] = (v + buf[prox]) * 0.4985  # média = suaviza (a corda "abafa" aos poucos)
				idx = prox
				var pos := (inicio + k) % total     # passa do fim? volta pro começo (loop perfeito)
				a[pos] += v * 0.22
			nota += 1
	return _guardar("violao", _criar_wav(a, true))
