extends Node2D
## A FASE: dentro da cabana trancada.
## Objetivo (do roteiro): "Encontre uma saída da cabana. Investigue o interior e
## descubra o que aconteceu com Marina e Rafa."
##
## A história avança pela variável GameData.etapa:
##   0 = começou | 1 = viu que a porta está trancada | 2 = achou a lanterna
##   3 = achou a chave | 4 = abriu a porta

# Sem PointLight2D no mobile a cabana ficava quase preta — ambiente mais claro.
const COR_AMBIENTE := Color(0.55, 0.52, 0.48)
const COR_AMBIENTE_ESCURO := Color(0.32, 0.32, 0.42)

@onready var player: Player = $Player
@onready var hud: HUD = $HUD

var mundo: MundoPixel  ## o mundo em pixel art (veja mundo_pixel.gd)
var cab: CabanaInterior
var ambiente: CanvasModulate
var som_vento: AudioStreamPlayer
var _ocupado := false        ## true durante falas/eventos (o jogador não anda)
var _terminou := false
var _ja_viu := {}            ## objetos que já foram examinados (para variar os textos)


func _ready() -> void:
	GameData.log_passo("jogo: começando")
	await get_tree().process_frame
	mundo = MundoPixel.new()
	add_child(mundo)
	GameData.log_passo("jogo: MundoPixel criado")
	await get_tree().process_frame

	ambiente = CanvasModulate.new()
	# Com luzes desligadas, usa tom mais claro para ainda enxergar a cabana
	ambiente.color = COR_AMBIENTE if not GameData.permite_luzes() else COR_AMBIENTE_ESCURO
	mundo.adicionar(ambiente)

	# O mesmo interior da cutscene, agora com paredes sólidas
	cab = CabanaInterior.new()
	cab.com_colisao = true
	cab.luz_acesa = false
	cab.lareira_acesa = false  # a lareira está APAGADA (a história diz "cinzas frias")
	cab.mensagem_visivel = true
	cab.camas_baguncadas = true
	cab.cama_lucas_vazia = true
	mundo.adicionar(cab)

	# O jogador fica dentro do nó com y-sort (para passar atrás/na frente do rádio)
	player.reparent(cab.objetos, false)
	player.position = Vector2(206, 44)
	player.sprite.olhar("baixo")
	player.camera.zoom = mundo.zoom(4.0)
	player.camera.limit_left = -90
	player.camera.limit_right = 378
	player.camera.limit_top = -110
	player.camera.limit_bottom = 300
	player.camera.position_smoothing_enabled = true
	# Garante câmera ativa depois do reparent (importante no Android)
	await get_tree().process_frame
	player.camera.make_current()
	player.camera.reset_smoothing()

	_criar_interagiveis()
	_aplicar_etapa_salva()

	player.alvo_mudou.connect(hud.mostrar_acao)
	hud.botao_examinar.connect(_on_examinar)
	hud.atualizar_itens()

	som_vento = Sons.tocar_loop(self, "vento", -40.0)
	GameData.log_passo("jogo: cabana montada")
	_comecar()


func _comecar() -> void:
	_ocupado = true
	player.definir_pode_mover(false)
	if GameData.vindo_da_cutscene:
		# "A câmera se afasta lentamente até a posição normal de jogo."
		GameData.vindo_da_cutscene = false
		player.camera.zoom = mundo.zoom(7.0)
		Sons.fade(som_vento, -18.0, 4.0)  # o som do vento começa a crescer
		var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(player.camera, "zoom", mundo.zoom(4.0), 4.0)
		await tw.finished
	else:
		Sons.fade(som_vento, -18.0, 2.0)
		await get_tree().create_timer(0.8).timeout
	_ocupado = false
	player.definir_pode_mover(true)
	_atualizar_objetivo()
	GameData.salvar_jogo()


func _physics_process(_delta: float) -> void:
	# Saiu pela porta aberta? Fim da demonstração.
	if GameData.etapa >= 4 and not _terminou and player.position.y > CabanaInterior.ALTURA + 4.0:
		_fim_da_demo()


# ---------------------------------------------------------------
# OBJETOS
# ---------------------------------------------------------------
func _criar_interagiveis() -> void:
	var lista := [
		["porta", Vector2(144, 186), 16.0, "ABRIR"],
		["mensagem", Vector2(118, 4), 22.0, "EXAMINAR"],
		["radio", Vector2(229, 124), 14.0, "LIGAR"],
		["foto", Vector2(124, 104), 12.0, "EXAMINAR"],
		["telefone", Vector2(155, 104), 10.0, "USAR"],
		["cama_voce", Vector2(21, 44), 12.0, "EXAMINAR"],
		["cama_lucas", Vector2(49, 44), 12.0, "EXAMINAR"],
		["cama_marina", Vector2(239, 44), 12.0, "EXAMINAR"],
		["cama_rafa", Vector2(270, 50), 12.0, "EXAMINAR"],
		["lareira", Vector2(22, 104), 14.0, "EXAMINAR"],
		["janela", Vector2(206, 4), 14.0, "OLHAR"],
		["cozinha", Vector2(35, 170), 16.0, "EXAMINAR"],
	]
	for dados in lista:
		var obj := Interagivel.criar(dados[0], dados[1], dados[2], dados[3])
		cab.add_child(obj)


func _aplicar_etapa_salva() -> void:
	player.atualizar_luz()
	if GameData.etapa >= 4:
		cab.porta_aberta = true


func _atualizar_objetivo() -> void:
	match GameData.etapa:
		0:
			hud.mostrar_objetivo("Encontre uma saída da cabana.", "Investigue o interior e descubra o que aconteceu com Marina e Rafa.")
		1:
			if GameData.tem_item("lanterna"):
				hud.mostrar_objetivo("Encontre a chave da porta.", "Use a lanterna nos cantos escuros.")
			else:
				hud.mostrar_objetivo("Encontre a chave da porta.", "Alguém trancou por dentro. Procure pela cabana.")
		2:
			hud.mostrar_objetivo("Encontre a chave da porta.", "Use a lanterna nos cantos escuros.")
		3:
			hud.mostrar_objetivo("Abra a porta da cabana.")
		_:
			hud.mostrar_objetivo("Saia da cabana.", "A noite está só começando…")


func _avancar_etapa(nova: int) -> void:
	if nova > GameData.etapa:
		GameData.etapa = nova
	GameData.salvar_jogo()
	hud.atualizar_itens()
	_atualizar_objetivo()


# ---------------------------------------------------------------
# EXAMINAR
# ---------------------------------------------------------------
func _on_examinar() -> void:
	if _ocupado or _terminou or player.alvo == null:
		return
	var id := player.alvo.id
	_ocupado = true
	player.definir_pode_mover(false)
	hud.modo_conversa(true)  # esconde botão e joystick: toque em qualquer lugar para avançar
	await _examinar(id)
	_ja_viu[id] = true
	_ocupado = false
	hud.modo_conversa(false)
	if not _terminou:
		player.definir_pode_mover(true)
		hud.mostrar_acao(player.alvo)


func _msg(texto: String) -> void:
	await hud.dialogo.mensagem(texto)


func _voce(texto: String) -> void:
	await hud.dialogo.falar("Você", texto)


func _examinar(id: String) -> void:
	var sozinho := GameData.g("sozinho", "sozinha")
	match id:
		"porta":
			if GameData.tem_item("chave") and GameData.etapa < 4:
				await _abrir_porta()
			elif GameData.etapa >= 4:
				await _msg("A porta está aberta. Lá fora, o vento parece chamar seu nome.")
			else:
				Sons.tocar(self, "batida", -10.0, 1.6)
				await _voce("Trancada… por dentro?")
				await _msg("A fechadura está vazia. Alguém trancou a porta e levou a chave. Mas eu estava %s aqui dentro…" % sozinho)
				_avancar_etapa(1)
		"mensagem":
			if not _ja_viu.has(id):
				await _msg("ELES JÁ ESTÃO DENTRO.")
				await _msg("Foi escrito com carvão. Ainda mancha os dedos: alguém escreveu isso há pouco tempo.")
				await _voce("Eles… quem?")
			else:
				await _msg("Você não consegue parar de olhar para as letras.")
		"radio":
			cab.radio_ligado(true)
			Sons.tocar(self, "clique", -6.0)
			var chiado := Sons.tocar_loop(self, "chiado", -14.0, "Efeitos")
			if GameData.tem_item("lanterna") and not GameData.tem_item("chave"):
				await get_tree().create_timer(0.8).timeout
				Sons.tocar(self, (null if GameData.eh_mobile else Sons.voz_radio(2.2)), -2.0)
				await hud.dialogo.radio("…nas… cinzas…")
			else:
				await _msg("Só chiado. Por um segundo, você jura ter ouvido seu nome.")
			chiado.queue_free()
			Sons.tocar(self, "clique", -6.0, 0.8)
			cab.radio_ligado(false)
		"foto":
			await _msg("A mesma fotografia. Quatro pessoas diante desta cabana, rostos apagados pelo tempo.")
			if not _ja_viu.has(id):
				await _msg("Atrás dela, uma data escrita à mão: 31 de outubro de 1987.")
				await _msg("Por um segundo, parece que uma das pessoas está olhando para você.")
		"telefone":
			await _msg("Sem linha. Só um silêncio pesado…")
			if not _ja_viu.has(id):
				await _msg("…e, bem baixinho, uma respiração do outro lado.")
		"cama_voce":
			await _voce("Minha cama. Eu acordei no chão… como fui parar lá?")
		"cama_lucas":
			await _msg("A cama do Lucas. Fria. Ninguém dorme aqui desde a primeira noite.")
		"cama_marina":
			if not GameData.tem_item("lanterna"):
				await _msg("A cama da Marina está toda desarrumada. Embaixo do travesseiro tem alguma coisa…")
				Sons.tocar(self, "item", -4.0)
				GameData.pegar_item("lanterna")
				player.atualizar_luz()
				await _msg("A lanterna dela! (Agora você enxerga melhor no escuro.)")
				_avancar_etapa(2)
			else:
				await _msg("O lençol ainda está quente. Ela estava aqui agora há pouco.")
		"cama_rafa":
			await _msg("O violão do Rafa, com uma corda arrebentada. Ele nunca deixaria o violão para trás.")
		"lareira":
			if GameData.tem_item("chave"):
				await _msg("Só cinzas frias.")
			elif not GameData.tem_item("lanterna"):
				await _msg("Está escuro demais para ver dentro da lareira.")
			else:
				await _msg("Você ilumina as cinzas com a lanterna… alguma coisa brilha lá no fundo.")
				Sons.tocar(self, "item", -4.0)
				GameData.pegar_item("chave")
				await _msg("Uma chave! Ainda está quente, como se alguém tivesse acabado de jogá-la aqui.")
				_avancar_etapa(3)
				await _evento_batida()
		"janela":
			await _msg("Lá longe, o portão principal do parque está fechado com correntes e cadeados novos.")
			if not _ja_viu.has(id):
				await _msg("A janela não abre: foi pregada por fora.")
		"cozinha":
			await _msg("Pratos sujos de três dias. Ninguém lavou nada desde que o Lucas sumiu.")


## Susto depois de achar a chave: a luz pisca e alguém bate na porta.
func _evento_batida() -> void:
	await get_tree().create_timer(0.6).timeout
	var tw := create_tween()
	for i in 3:
		tw.tween_property(ambiente, "color", Color(0.05, 0.05, 0.08), 0.06)
		tw.tween_property(ambiente, "color", COR_AMBIENTE, 0.12)
	await tw.finished
	Sons.tocar(self, "batida", 0.0)
	await get_tree().create_timer(1.4).timeout
	Sons.tocar(self, "batida", 4.0, 0.85)
	await _voce("…Marina? Rafa? São vocês?")
	await get_tree().create_timer(1.0).timeout
	await _msg("Nenhuma resposta.")


func _abrir_porta() -> void:
	await _msg("A chave entra na fechadura… e gira.")
	Sons.tocar(self, "rangido", -4.0)
	cab.porta_aberta = true
	_avancar_etapa(4)
	Sons.fade(som_vento, -10.0, 2.0)
	await _voce("Eu preciso encontrar os outros.")


func _fim_da_demo() -> void:
	_terminou = true
	player.definir_pode_mover(false)
	hud.mostrar_acao(null)
	var camada := CanvasLayer.new()
	camada.layer = 40
	add_child(camada)
	var fundo := ColorRect.new()
	fundo.color = Color.BLACK
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fundo.modulate.a = 0.0
	camada.add_child(fundo)
	var texto := Label.new()
	texto.text = "PARTE 2\n\nSOBREVIVA ATÉ O RESGATE"
	texto.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	texto.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	texto.add_theme_font_size_override("font_size", 44)
	texto.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
	texto.modulate.a = 0.0
	fundo.add_child(texto)
	var tw := create_tween()
	tw.tween_property(fundo, "modulate:a", 1.0, 2.0)
	tw.tween_property(texto, "modulate:a", 1.0, 1.5)
	tw.tween_interval(4.0)
	await tw.finished
	# Fim da Parte 1 → começa a Parte 2 (sobrevivência). Etapa 5 = Parte 2.
	GameData.etapa = 5
	GameData.parte2 = {}
	GameData.salvar_jogo()
	GameData.trocar_cena(GameData.CENA_SOBREVIVENCIA, 1.0)
