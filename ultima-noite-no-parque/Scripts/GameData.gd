extends Node
## GameData — script "global" (Autoload). Ele existe o jogo inteiro, em todas as cenas.
## Guarda: personagem escolhido, progresso (save), configurações de volume
## e faz a troca de cena com um fade preto bonito.

const CAMINHO_SAVE := "user://save.cfg"
const CAMINHO_CONFIG := "user://config.cfg"

# Nomes das cenas (num lugar só: se mudar o caminho, muda aqui e pronto!)
const CENA_MENU := "res://Scenes/main_menu.tscn"
const CENA_SELECAO := "res://Scenes/character_select.tscn"
const CENA_CUTSCENE := "res://Scenes/cutscene.tscn"
const CENA_JOGO := "res://Scenes/jogo.tscn"
const CENA_SOBREVIVENCIA := "res://Scenes/sobrevivencia.tscn"  ## PARTE 2

# ---------------------------------------------------------------
# DADOS DO JOGADOR
# ---------------------------------------------------------------
var personagem_escolhido := "masculino"   ## "masculino" ou "feminino"
var etapa := 0                            ## em que parte da história o jogador está
var itens: Array[String] = []             ## ex.: ["lanterna", "chave"]
var parte2 := {}                         ## save da Parte 2 (sobrevivência): status, mochila, dia...
var vindo_da_cutscene := false            ## o jogo faz a câmera "descer" suave quando é true

# ---------------------------------------------------------------
# CONFIGURAÇÕES (volume de 0.0 a 1.0)
# ---------------------------------------------------------------
var volumes := {"Master": 0.8, "Musica": 0.6, "Efeitos": 0.8}
var tamanho_pixel := 3        ## NÍVEL DE DETALHE: 4 = baixo (leve), 3 = médio, 2 = alto (mais enfeites)
var fps_maximo := 60          ## 30 economiza bateria e esquenta menos o celular
var hud_barras := true       ## Parte 2: barras de status abertas (true) ou escondidas (false)
var som_ligado := true        ## dá para desligar nas Opções (e o modo seguro desliga)

# ---------------------------------------------------------------
# COMPATIBILIDADE MOBILE (evita crash nativo no Android)
# PointLight2D / partículas / SubViewport pesado derrubam o motor em vários celulares.
# No Android ligamos o modo conservador automaticamente.
# ---------------------------------------------------------------
var eh_mobile := false
var luzes_habilitadas := true   ## PointLight2D — causa mais comum de crash no Android
var particulas_habilitadas := true
var subviewport_habilitado := true

# ---------------------------------------------------------------
# DIAGNÓSTICO (para descobrir por que o jogo fechou, se fechar)
# ---------------------------------------------------------------
const CAMINHO_SESSAO := "user://sessao.cfg"
var fechou_sozinho := false   ## true se na última vez o jogo fechou sem passar pelo "Sair"
var ultimo_passo := ""        ## onde o jogo estava quando fechou sozinho
var modo_seguro := false       ## liga sozinho se o jogo fechou sozinho: desliga partículas e luzes
const CAMINHO_PASSOS := "user://passos.log"

var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _trocando_cena := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # funciona mesmo com o jogo pausado
	_detectar_plataforma()
	_verificar_sessao_anterior()
	_aplicar_modo_conservador()
	_registrar_controles()
	_criar_barramentos_de_audio()
	carregar_config()
	_criar_fade()
	log_passo("GameData pronto (mobile=%s seguro=%s luzes=%s pixel=%s subvp=%s)" % [eh_mobile, modo_seguro, luzes_habilitadas, tamanho_pixel, subviewport_habilitado])
	marcar_passo("menu")


## Detecta Android/iOS e liga proteções antes de qualquer cena carregar.
## (Para testar o "modo celular" no PC, rode o jogo com o argumento:  -- mobile)
func _detectar_plataforma() -> void:
	eh_mobile = OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios") \
		or "mobile" in OS.get_cmdline_user_args()
	# PointLight2D NUNCA é usada (nem no PC): as luzes são LuzFake (pixeladas e seguras).
	# Na 6.4 ela tinha sido religada no celular — isso podia derrubar o Godot de novo.
	luzes_habilitadas = false
	subviewport_habilitado = false
	if eh_mobile:
		particulas_habilitadas = false
		fps_maximo = mini(fps_maximo, 30)


## Depois de um crash, desliga tudo que pode derrubar o motor.
func _aplicar_modo_conservador() -> void:
	luzes_habilitadas = false
	subviewport_habilitado = false
	if modo_seguro or eh_mobile:
		particulas_habilitadas = false
	if modo_seguro:
		som_ligado = false


## PointLight2D: sempre desligada (usamos LuzFake). Mantido para o código antigo funcionar.
func permite_luzes() -> bool:
	return false


func max_luzes() -> int:
	return 0


func permite_particulas() -> bool:
	return particulas_habilitadas and not modo_seguro


func permite_subviewport() -> bool:
	# No mobile sempre false (tela preta / crash)
	if eh_mobile:
		return false
	return subviewport_habilitado and not modo_seguro


## 1 = leve (pixels grandes), 2 = médio, 3 = rico (pixels pequenos)
func nivel_detalhe() -> int:
	if tamanho_pixel >= 4:
		return 1
	if tamanho_pixel == 3:
		return 2
	return 3


func _exit_tree() -> void:
	_encerrar_sessao()
	# Limpa os "caches" estáticos ao fechar o jogo (evita aviso de memória vazada).
	Sons.limpar_cache_memoria()
	SpriteLibrary._cache_frames.clear()
	PixelArte.limpar_cache()
	Sombras.limpar_cache()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			_encerrar_sessao()
		NOTIFICATION_APPLICATION_PAUSED:
			_encerrar_sessao()  # o Android pode fechar apps minimizados: isso NÃO é bug
		NOTIFICATION_APPLICATION_RESUMED:
			marcar_passo(ultimo_passo_atual)


# ---------------------------------------------------------------
# DIAGNÓSTICO: anota em que parte do jogo estamos. Se o jogo fechar sozinho
# (travou/crashou), na próxima vez o menu avisa onde foi.
# ---------------------------------------------------------------
var ultimo_passo_atual := "iniciando"

func _verificar_sessao_anterior() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CAMINHO_SESSAO) == OK and bool(cfg.get_value("sessao", "rodando", false)):
		fechou_sozinho = true
		ultimo_passo = str(cfg.get_value("sessao", "passo", "?"))
		modo_seguro = true  # nesta vez: sem som, sem partículas e sem luzes 2D
	# Guarda o "diário de passos" da vez anterior e começa um novo
	if FileAccess.file_exists(CAMINHO_PASSOS):
		passos_anteriores = FileAccess.get_file_as_string(CAMINHO_PASSOS)
	var f := FileAccess.open(CAMINHO_PASSOS, FileAccess.WRITE)
	if f:
		f.store_line("=== jogo iniciado ===")
		f.close()
	marcar_passo("iniciando")


var passos_anteriores := ""

## Escreve um passo no diário (user://passos.log) E na aba "Saída" do editor.
## Se o jogo fechar, o último passo escrito mostra ONDE ele estava.
func log_passo(texto: String) -> void:
	var linha := "[%6.2fs] %s" % [Time.get_ticks_msec() / 1000.0, texto]
	print("[PASSO] ", linha)
	var f := FileAccess.open(CAMINHO_PASSOS, FileAccess.READ_WRITE)
	if f:
		f.seek_end()
		f.store_line(linha)
		f.flush()
		f.close()


func marcar_passo(passo: String) -> void:
	ultimo_passo_atual = passo
	var cfg := ConfigFile.new()
	cfg.set_value("sessao", "rodando", true)
	cfg.set_value("sessao", "passo", passo)
	cfg.save(CAMINHO_SESSAO)


func _encerrar_sessao() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("sessao", "rodando", false)
	cfg.set_value("sessao", "passo", ultimo_passo_atual)
	cfg.save(CAMINHO_SESSAO)


## Últimas linhas de erro do log da vez anterior (o Godot grava em user://logs/).
func erros_do_log_anterior(max_linhas := 12) -> PackedStringArray:
	var resultado := PackedStringArray()
	var pasta := DirAccess.open("user://logs")
	if pasta == null:
		resultado.append("(nenhum log encontrado)")
		return resultado
	var arquivos := Array(pasta.get_files())
	arquivos.sort()
	arquivos.erase("godot.log")  # godot.log é o desta vez; os outros são das vezes anteriores
	if arquivos.is_empty():
		resultado.append("(ainda não há log de uma vez anterior)")
		return resultado
	var texto := FileAccess.get_file_as_string("user://logs/" + str(arquivos[-1]))
	for linha in texto.split("\n"):
		if "ERROR" in linha or "error" in linha or "CrashHandler" in linha or "signal" in linha.to_lower():
			resultado.append(linha.strip_edges().left(110))
	if resultado.is_empty():
		resultado.append("(nenhum erro no log anterior)")
	return resultado.slice(maxi(0, resultado.size() - max_linhas))


# ---------------------------------------------------------------
# CACHE: limpar arquivos temporários (o save NÃO é apagado)
# ---------------------------------------------------------------
func tamanho_do_cache() -> int:
	return _tamanho_pasta("user://cache")


func _tamanho_pasta(caminho: String) -> int:
	var total := 0
	var d := DirAccess.open(caminho)
	if d == null:
		return 0
	for f in d.get_files():
		var arq := FileAccess.open(caminho + "/" + f, FileAccess.READ)
		if arq:
			total += arq.get_length()
	for sub in d.get_directories():
		total += _tamanho_pasta(caminho + "/" + sub)
	return total


func limpar_cache() -> void:
	_apagar_pasta("user://cache")
	Sons.limpar_cache_memoria()
	SpriteLibrary._cache_frames.clear()
	PixelArte.limpar_cache()


func _apagar_pasta(caminho: String) -> void:
	var d := DirAccess.open(caminho)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_apagar_pasta(caminho + "/" + sub)
		d.remove(sub)


func aplicar_qualidade() -> void:
	Engine.max_fps = fps_maximo
	log_passo("qualidade aplicada: fps=%d detalhe=%d" % [fps_maximo, nivel_detalhe()])


# ---------------------------------------------------------------
# CONTROLES: cria as ações por código (assim não precisa mexer no Mapa de Entrada)
# ---------------------------------------------------------------
func _registrar_controles() -> void:
	_criar_acao("mover_esquerda", [KEY_A, KEY_LEFT])
	_criar_acao("mover_direita", [KEY_D, KEY_RIGHT])
	_criar_acao("mover_cima", [KEY_W, KEY_UP])
	_criar_acao("mover_baixo", [KEY_S, KEY_DOWN])
	_criar_acao("interagir", [KEY_E, KEY_ENTER, KEY_SPACE])
	_criar_acao("pausar", [KEY_ESCAPE, KEY_P])
	# Parte 2 (sobrevivência)
	_criar_acao("correr", [KEY_SHIFT])
	_criar_acao("atacar", [KEY_F, KEY_J])
	_criar_acao("luz", [KEY_Q, KEY_L])
	_criar_acao("mochila", [KEY_I, KEY_TAB])
	_criar_acao("criar", [KEY_C])


func _criar_acao(nome: StringName, teclas: Array) -> void:
	if not InputMap.has_action(nome):
		InputMap.add_action(nome)
	for tecla in teclas:
		var evento := InputEventKey.new()
		evento.physical_keycode = tecla
		if not InputMap.action_has_event(nome, evento):
			InputMap.action_add_event(nome, evento)


# ---------------------------------------------------------------
# ÁUDIO: cria os canais "Musica" e "Efeitos" (barramentos)
# ---------------------------------------------------------------
func _criar_barramentos_de_audio() -> void:
	# Os canais vêm prontos em default_bus_layout.tres. Isto só cria se estiver faltando.
	for nome in ["Musica", "Efeitos"]:
		if AudioServer.get_bus_index(nome) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, nome)
			AudioServer.set_bus_send(i, "Master")


func definir_volume(barramento: String, valor: float) -> void:
	volumes[barramento] = clampf(valor, 0.0, 1.0)
	var i := AudioServer.get_bus_index(barramento)
	if i == -1:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(volumes[barramento], 0.0001)))
	AudioServer.set_bus_mute(i, volumes[barramento] <= 0.001)


func salvar_config() -> void:
	var cfg := ConfigFile.new()
	for chave in volumes:
		cfg.set_value("audio", chave, volumes[chave])
	cfg.set_value("video", "tamanho_pixel", tamanho_pixel)
	cfg.set_value("video", "fps_maximo", fps_maximo)
	cfg.set_value("video", "hud_barras", hud_barras)
	cfg.set_value("audio", "som_ligado", som_ligado if not modo_seguro else true)
	cfg.save(CAMINHO_CONFIG)


func carregar_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CAMINHO_CONFIG) == OK:
		for chave in volumes:
			volumes[chave] = float(cfg.get_value("audio", chave, volumes[chave]))
		tamanho_pixel = clampi(int(cfg.get_value("video", "tamanho_pixel", tamanho_pixel)), 2, 4)
		fps_maximo = int(cfg.get_value("video", "fps_maximo", fps_maximo))
		hud_barras = bool(cfg.get_value("video", "hud_barras", true))
		som_ligado = bool(cfg.get_value("audio", "som_ligado", true))
	for chave in volumes:
		definir_volume(chave, volumes[chave])
	if modo_seguro:
		som_ligado = false
	aplicar_qualidade()


# ---------------------------------------------------------------
# SAVE (Continuar)
# ---------------------------------------------------------------
func novo_jogo(personagem: String) -> void:
	personagem_escolhido = personagem
	etapa = 0
	itens.clear()
	parte2 = {}


func tem_save() -> bool:
	return FileAccess.file_exists(CAMINHO_SAVE) or FileAccess.file_exists(CAMINHO_SAVE_BAK)


## v10 — SAVE SEGURO:
##  1. grava num arquivo temporário (save.tmp)
##  2. o save antigo vira backup (save.bak)
##  3. o temporário vira o save de verdade
## Se o celular fechar o app NO MEIO da gravação, o save antigo continua inteiro
## (antes o arquivo podia ficar pela metade e o CONTINUAR perdia tudo).
const CAMINHO_SAVE_TMP := "user://save.tmp"
const CAMINHO_SAVE_BAK := "user://save.bak"
var ultimo_save_ms := 0


func salvar_jogo() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("jogo", "versao_save", 10)
	cfg.set_value("jogo", "personagem", personagem_escolhido)
	cfg.set_value("jogo", "etapa", etapa)
	cfg.set_value("jogo", "itens", itens)
	cfg.set_value("jogo", "parte2", parte2)
	if cfg.save(CAMINHO_SAVE_TMP) != OK:
		push_warning("Não consegui gravar o save temporário.")
		return
	# confere se o temporário abre direitinho antes de trocar
	var teste := ConfigFile.new()
	if teste.load(CAMINHO_SAVE_TMP) != OK:
		push_warning("Save temporário corrompido: mantendo o anterior.")
		return
	if FileAccess.file_exists(CAMINHO_SAVE):
		if FileAccess.file_exists(CAMINHO_SAVE_BAK):
			DirAccess.remove_absolute(CAMINHO_SAVE_BAK)
		DirAccess.rename_absolute(CAMINHO_SAVE, CAMINHO_SAVE_BAK)
	if DirAccess.rename_absolute(CAMINHO_SAVE_TMP, CAMINHO_SAVE) != OK:
		DirAccess.copy_absolute(CAMINHO_SAVE_TMP, CAMINHO_SAVE)
	ultimo_save_ms = Time.get_ticks_msec()


func carregar_jogo() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(CAMINHO_SAVE) != OK:
		# save principal estragado ou sumido: tenta o backup
		if cfg.load(CAMINHO_SAVE_BAK) != OK:
			return false
		log_passo("save: usando o backup (save.bak)")
	personagem_escolhido = str(cfg.get_value("jogo", "personagem", "masculino"))
	etapa = int(cfg.get_value("jogo", "etapa", 0))
	itens.clear()
	for item in cfg.get_value("jogo", "itens", []):
		itens.append(str(item))
	var p2 = cfg.get_value("jogo", "parte2", {})
	parte2 = p2 if p2 is Dictionary else {}
	return true


## Para onde o "Continuar" leva: Parte 1 (cabana) ou Parte 2 (sobrevivência).
func cena_do_save() -> String:
	return CENA_SOBREVIVENCIA if etapa >= 5 else CENA_JOGO


func apagar_save() -> void:
	for c in [CAMINHO_SAVE, CAMINHO_SAVE_BAK, CAMINHO_SAVE_TMP]:
		if FileAccess.file_exists(c):
			DirAccess.remove_absolute(c)


func tem_item(nome: String) -> bool:
	return nome in itens


func pegar_item(nome: String) -> void:
	if not tem_item(nome):
		itens.append(nome)


## Ajuda nos textos: escolhe a palavra certa pro menino ou pra menina.
## Ex.: GameData.g("sozinho", "sozinha")
func g(masculino: String, feminino: String) -> String:
	return feminino if personagem_escolhido == "feminino" else masculino


# ---------------------------------------------------------------
# TROCA DE CENA COM FADE
# ---------------------------------------------------------------
func _criar_fade() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100  # acima de tudo
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.modulate.a = 0.0
	_fade_layer.add_child(_fade_rect)


func trocar_cena(caminho: String, duracao := 0.6) -> void:
	if _trocando_cena:
		return
	if not ResourceLoader.exists(caminho):
		push_error("Cena não encontrada: " + caminho)
		return
	_trocando_cena = true
	if _fade_rect:
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		var tw := create_tween()
		tw.tween_property(_fade_rect, "modulate:a", 1.0, duracao)
		await tw.finished
	get_tree().paused = false
	marcar_passo(caminho.get_file().get_basename())
	log_passo("trocando para a cena " + caminho)
	get_tree().change_scene_to_file(caminho)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if _fade_rect:
		var tw2 := create_tween()
		tw2.tween_property(_fade_rect, "modulate:a", 0.0, duracao)
		await tw2.finished
		_fade_rect.modulate.a = 0.0  # garante
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trocando_cena = false


func forcar_clarear() -> void:
	if _fade_rect:
		_fade_rect.modulate.a = 0.0
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
