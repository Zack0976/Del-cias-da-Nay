extends Node2D
## CUTSCENE DE ABERTURA — segue o roteiro "Última Noite no Parque — Cutscene de Abertura Definitiva".
##
## Como funciona: a função _roteiro() é lida de cima para baixo, como o roteiro em texto.
## Cada "await" espera uma coisa terminar (uma fala, a câmera andar, um tempo...).
##
## Toque na tela para adiantar as falas. O botão "PULAR" vai direto para o jogo.

# ---------------------------------------------------------------
# CORES DE "HORA DO DIA" (o CanvasModulate pinta o mundo inteiro)
# ---------------------------------------------------------------
const COR_TARDE := Color(1.0, 0.84, 0.66)
const COR_TARDE_DENTRO := Color(0.85, 0.7, 0.55)
const COR_NOITE := Color(0.22, 0.26, 0.45)
const COR_NOITE_DENTRO := Color(0.30, 0.28, 0.40)
const COR_AMANHECER := Color(0.75, 0.72, 0.85)
const COR_DIA := Color(0.9, 0.9, 0.85)
const COR_POR_DO_SOL := Color(0.95, 0.55, 0.40)
const COR_ESCURO := Color(0.03, 0.03, 0.05)

const POS_CABANA := Vector2(4000, 0)  ## onde o interior da cabana fica no "mundo" da cutscene

## DICA PARA TESTAR: mude no Inspector para começar direto numa cena
## (0 = prólogo, 1 a 6 = cenas do roteiro). Assim você não precisa assistir tudo de novo!
@export_range(0, 6) var comecar_na_cena := 0

@onready var camera: Camera2D = $Camera2D

var mundo: MundoPixel  ## o mundo é desenhado em pixel art (veja mundo_pixel.gd)
var ambiente: CanvasModulate
var ext: ParqueExterior
var cab: CabanaInterior
var carro: Sprite2D
var silhueta: Node2D
var dialogo: DialogueBox

var voce: Ator
var lucas: Ator
var marina: Ator
var rafa: Ator

# Interface
var fade: ColorRect
var titulo_label: Label
var local_label: Label
var foto: Control
var botao_pular: Button

# Áudio
var som_vento: AudioStreamPlayer
var som_grilos: AudioStreamPlayer
var som_fogueira: AudioStreamPlayer
var som_chiado: AudioStreamPlayer
var som_drone: AudioStreamPlayer
var som_motor: AudioStreamPlayer
var som_musica: AudioStreamPlayer

var _seguir: Node2D = null
var _seguir_desloc := Vector2.ZERO
var _confirmar_pular := false
var _pulando := false
var _placa_camping := false
var _placa_restrito := false


func _ready() -> void:
	GameData.log_passo("cutscene: começando")
	# No mobile: NÃO monta o parque agora. O prólogo é só texto em tela preta.
	# Montar 40+ sprites + SubViewport no Mali-G68 crashava antes da 1ª fala.
	_montar_interface()
	_montar_audio_leve()
	GameData.log_passo("cutscene: interface pronta (mundo adiado)")
	_roteiro()


func _process(delta: float) -> void:
	# Placas da estrada: o texto delas aparece como legenda quando o carro passa
	# (em pixel art a letrinha da placa fica pequena demais para ler)
	if _mundo_pronto and carro and ext and not _placa_camping and carro.position.x > ext.PONTOS["placa_camping"].x - 60.0 and carro.position.x < 0.0:
		_placa_camping = true
		mostrar_local("ÁREA DE CAMPING — 2 KM", 2.0)
	if _mundo_pronto and carro and ext and not _placa_restrito and carro.position.x > ext.PONTOS["placa_restrito"].x - 60.0 and carro.position.x < 400.0:
		_placa_restrito = true
		mostrar_local("ACESSO RESTRITO APÓS O PÔR DO SOL", 2.5)
	if _seguir and is_instance_valid(_seguir):
		var alvo := _seguir.global_position + _seguir_desloc
		camera.position = camera.position.lerp(alvo, 1.0 - exp(-delta * 4.0))


# ===============================================================
# MONTAGEM DO MUNDO
# ===============================================================
var _mundo_pronto := false

## Monta o parque só quando a cutscene precisa mostrar imagem (depois do prólogo).
func _garantir_mundo() -> void:
	if _mundo_pronto:
		return
	GameData.log_passo("cutscene: montando mundo agora")
	_montar_mundo()
	_mundo_pronto = true
	GameData.log_passo("cutscene: mundo montado OK")
	# Um quadro de folga pro GPU respirar no Android
	await get_tree().process_frame
	await get_tree().process_frame


func _montar_mundo() -> void:
	GameData.log_passo("cutscene: _montar_mundo inicio")
	mundo = MundoPixel.new()
	add_child(mundo)

	var destino := mundo.raiz()
	if destino != null and is_instance_valid(destino):
		var pos_cam := camera.global_position
		camera.reparent(destino)
		camera.global_position = pos_cam
	else:
		push_warning("MundoPixel sem raiz — câmera na cutscene")
		GameData.log_passo("cutscene: AVISO mundo sem raiz")

	ambiente = CanvasModulate.new()
	ambiente.color = COR_TARDE  # já visível (tarde) — evita tela preta
	mundo.adicionar(ambiente)

	ext = ParqueExterior.new()
	ext.name = "ParqueExterior"
	mundo.adicionar(ext)
	GameData.log_passo("cutscene: parque criado")

	cab = CabanaInterior.new()
	cab.name = "CabanaInterior"
	cab.position = POS_CABANA
	mundo.adicionar(cab)

	carro = SpriteLibrary.criar_sprite("carro", 0)
	carro.name = "CarroCutscene"
	carro.position = ext.PONTOS["inicio_carro"]
	if ext.arvores:
		ext.arvores.add_child(carro)
	else:
		ext.add_child(carro)
	ext.carro_node = carro

	silhueta = Silhueta.new()
	silhueta.visible = false
	if ext.arvores:
		ext.arvores.add_child(silhueta)

	voce = Ator.criar(SpriteLibrary.personagem_do_jogador(), "Você")
	lucas = Ator.criar("lucas", "Lucas")
	marina = Ator.criar("marina", "Marina")
	rafa = Ator.criar("rafa", "Rafa")
	for a in [voce, lucas, marina, rafa]:
		a.visible = false
		if ext.arvores:
			ext.arvores.add_child(a)
		else:
			ext.add_child(a)

	camera.position = Vector2(-1500, -40)
	camera.zoom = mundo.zoom(2.0)
	camera.make_current()
	camera.enabled = true
	GameData.log_passo("cutscene: _montar_mundo fim")


func _montar_interface() -> void:
	var camada := CanvasLayer.new()
	camada.layer = 15
	add_child(camada)

	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camada.add_child(fade)

	foto = FotoAntiga.new()
	foto.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	foto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foto.visible = false
	camada.add_child(foto)

	local_label = Label.new()
	local_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	local_label.offset_top = 60
	local_label.offset_bottom = 120
	local_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	local_label.add_theme_font_size_override("font_size", 26)
	local_label.add_theme_color_override("font_color", Color(0.9, 0.86, 0.75))
	local_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	local_label.add_theme_constant_override("shadow_offset_x", 2)
	local_label.add_theme_constant_override("shadow_offset_y", 2)
	local_label.modulate.a = 0.0
	camada.add_child(local_label)

	titulo_label = Label.new()
	titulo_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	titulo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	titulo_label.add_theme_font_size_override("font_size", 84)
	titulo_label.add_theme_color_override("font_color", Color(0.88, 0.84, 0.74))
	titulo_label.add_theme_color_override("font_outline_color", Color(0.55, 0.05, 0.05))
	titulo_label.add_theme_constant_override("outline_size", 14)
	titulo_label.modulate.a = 0.0
	camada.add_child(titulo_label)

	dialogo = DialogueBox.new()
	add_child(dialogo)

	var camada_botao := CanvasLayer.new()
	camada_botao.layer = 30
	add_child(camada_botao)
	botao_pular = Button.new()
	botao_pular.text = "PULAR  ▶▶"
	botao_pular.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	botao_pular.offset_left = -230
	botao_pular.offset_right = -24
	botao_pular.offset_top = 20
	botao_pular.offset_bottom = 72
	botao_pular.add_theme_font_size_override("font_size", 22)
	botao_pular.focus_mode = Control.FOCUS_NONE
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0, 0, 0, 0.45)
	estilo.border_color = Color(0.5, 0.5, 0.5, 0.5)
	estilo.set_border_width_all(1)
	estilo.set_corner_radius_all(6)
	botao_pular.add_theme_stylebox_override("normal", estilo)
	botao_pular.add_theme_stylebox_override("hover", estilo)
	botao_pular.add_theme_stylebox_override("pressed", estilo)
	botao_pular.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.8))
	botao_pular.pressed.connect(_on_pular)
	camada_botao.add_child(botao_pular)


func _montar_audio_leve() -> void:
	# Prólogo: nenhum loop. Só one-shots (clique). Evita crash ao ligar som.
	som_vento = null
	som_grilos = null
	som_fogueira = null
	som_chiado = null
	som_drone = null
	som_motor = null
	som_musica = null
	GameData.log_passo("cutscene: audio leve ok")


func _montar_audio_resto() -> void:
	if not GameData.som_ligado:
		return
	# Mobile: 1 loop só (vento). Mais que isso = crash no Mali.
	if som_vento == null:
		som_vento = Sons.tocar_loop(self, "vento", -80.0)
	if GameData.eh_mobile:
		return
	if som_grilos == null:
		som_grilos = Sons.tocar_loop(self, "grilos", -80.0)
	if som_fogueira == null:
		som_fogueira = Sons.tocar_loop(self, "fogueira", -80.0, "Efeitos")
	if som_motor == null:
		som_motor = Sons.tocar_loop(self, "motor", -80.0, "Efeitos")


# ===============================================================
# FERRAMENTAS (deixam o roteiro curtinho e fácil de ler)
# ===============================================================

## Espera X segundos. Usa um Timer "filho": se a cena for trocada (botão PULAR),
## o timer some junto e o roteiro simplesmente para — sem erros.
func esperar(segundos: float) -> void:
	var t := Timer.new()
	t.one_shot = true
	add_child(t)
	t.start(segundos)
	await t.timeout
	t.queue_free()


func escurecer(duracao := 1.0) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", 1.0, duracao)
	await tw.finished


func clarear(duracao := 1.0) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", 0.0, duracao)
	await tw.finished


func corte_seco() -> void:
	fade.modulate.a = 1.0


## Move a câmera (posição e zoom). Zoom maior = mais perto.
func camera_para(pos: Vector2, zoom_final: float, duracao: float) -> void:
	_seguir = null
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(camera, "position", pos, duracao)
	tw.tween_property(camera, "zoom", mundo.zoom(zoom_final), duracao)
	await tw.finished


func camera_em(pos: Vector2, zoom_final: float) -> void:
	_seguir = null
	camera.position = pos
	camera.zoom = mundo.zoom(zoom_final)
	camera.reset_smoothing()


func seguir(alvo: Node2D, desloc := Vector2(0, -16)) -> void:
	_seguir = alvo
	_seguir_desloc = desloc


func tremer_camera(forca := 4.0, vezes := 10) -> void:
	var tw := create_tween()
	for i in vezes:
		tw.tween_property(camera, "offset", Vector2(randf_range(-forca, forca), randf_range(-forca, forca)), 0.04)
	tw.tween_property(camera, "offset", Vector2.ZERO, 0.05)


func ambiente_para(cor: Color, duracao := 0.0) -> void:
	if ambiente == null or not is_instance_valid(ambiente):
		return
	if duracao <= 0.0:
		ambiente.color = cor
		return
	var tw := create_tween()
	tw.tween_property(ambiente, "color", cor, duracao)
	await tw.finished


func mostrar_local(texto: String, duracao := 3.0) -> void:
	local_label.text = texto
	var tw := create_tween()
	tw.tween_property(local_label, "modulate:a", 1.0, 1.0)
	tw.tween_interval(duracao)
	tw.tween_property(local_label, "modulate:a", 0.0, 1.0)


## Coloca um personagem dentro da cabana (posição relativa ao interior).
func na_cabana(ator: Ator, nome_ponto: String, olhar_para := "baixo") -> void:
	if ator.get_parent() != cab.objetos:
		ator.reparent(cab.objetos, false)
	ator.position = CabanaInterior.PONTOS[nome_ponto]
	ator.visible = true
	ator.modulate.a = 1.0
	ator.deitar(false)
	ator.olhar(olhar_para)


## Coloca um personagem do lado de fora (posição do mapa).
func fora(ator: Ator, pos: Vector2, olhar_para := "baixo") -> void:
	if ator.get_parent() != ext.arvores:
		ator.reparent(ext.arvores, false)
	ator.position = pos
	ator.visible = true
	ator.modulate.a = 1.0
	ator.deitar(false)
	ator.olhar(olhar_para)


func esconder_todos() -> void:
	for a in [voce, lucas, marina, rafa]:
		a.visible = false


func falar(quem: Ator, texto: String) -> void:
	await dialogo.falar(quem.nome_exibido, texto)


func _volume(player: AudioStreamPlayer, db: float, duracao := 1.5) -> void:
	if player == null or not is_instance_valid(player):
		return
	Sons.fade(player, db, duracao)


func _tocar_musica(db := -14.0) -> void:
	if GameData.eh_mobile:
		return  # violao.res é enorme e crasha no Mali
	if som_musica == null:
		som_musica = Sons.tocar_loop(self, "violao", -40.0)
	_volume(som_musica, db, 2.5)


# ===============================================================
# O ROTEIRO
# ===============================================================
func _roteiro() -> void:
	var cena := comecar_na_cena
	for arg in OS.get_cmdline_user_args():  # também dá para passar "cena=3" ao rodar
		if arg.begins_with("cena="):
			cena = int(arg.trim_prefix("cena="))
	GameData.log_passo("cutscene: roteiro cena=%d" % cena)
	if cena <= 0:
		await _prologo()
	# A partir daqui precisamos do parque/cabana na tela
	await _garantir_mundo()
	_montar_audio_resto()
	if cena > 1 and carro:
		carro.position = ext.PONTOS["carro_para"]  # o carro já chegou
	if cena == 1:  # começando direto na cena 1: faz o que o prólogo faria
		ambiente_para(COR_TARDE)
		camera_em(Vector2(-1480, -40), 2.6)
		_volume(som_vento, -18.0, 1.0)
		clarear(1.0)
	if cena <= 1: await _cena1_chegada()
	if cena <= 2: await _cena2_cabana()
	if cena <= 3: await _cena3_primeira_noite()
	if cena <= 4: await _cena4_desaparecimento()
	if cena <= 5: await _cena5_montagem()
	await _cena6_eles_ja_estao_dentro()
	_ir_para_o_jogo()


# ---------------------------------------------------------------
# PRÓLOGO — A GRAVAÇÃO
# ---------------------------------------------------------------
func _prologo() -> void:
	corte_seco()
	await esperar(1.0)
	Sons.tocar(self, "clique", -4.0, 0.7)       # fita sendo inserida
	await esperar(0.6)
	Sons.tocar(self, "clique", -2.0)            # clique
	_volume(som_chiado, -26.0, 1.0)                  # chiado baixinho da fita
	await esperar(1.2)

	await dialogo.narrar("Eu passei muito tempo tentando esquecer o que aconteceu naquela semana.")
	await dialogo.narrar("Durante anos, eu disse a mim %s que tudo não passava de um acidente. Uma sequência de decisões erradas, coincidências… coisas que não deveriam ter acontecido." % GameData.g("mesmo", "mesma"))
	await esperar(1.5)
	await dialogo.narrar("Mas existe uma coisa que eu nunca consegui explicar.")
	_volume(som_drone, -18.0, 2.0)                   # ruído grave e distante
	await esperar(1.0)
	await dialogo.narrar("Por que, quando finalmente amanheceu… o parque estava completamente vazio?", 1.5)

	# A imagem aparece: no alto da floresta (agora sim monta o parque)
	GameData.log_passo("cutscene: prólogo texto OK, montando parque")
	await _garantir_mundo()
	_montar_audio_resto()
	ambiente_para(COR_TARDE)
	ext.luzes_cabana(0)
	camera_em(Vector2(-1500, -160), 0.9)
	_volume(som_chiado, -80.0, 2.0)
	_volume(som_drone, -80.0, 4.0)
	_volume(som_vento, -18.0, 3.0)
	await clarear(2.5)
	mostrar_local("PARQUE ESTADUAL DA SERRA NEGRA", 3.5)
	await camera_para(Vector2(-1480, -40), 2.6, 5.0)
	await esperar(1.0)


# ---------------------------------------------------------------
# CENA 1 — A CHEGADA
# ---------------------------------------------------------------
func _cena1_chegada() -> void:
	# Um carro se aproxima... faróis ligados
	carro.texture = SpriteLibrary.quadro("carro", 2)  # sprite com faróis
	ext.farois_acesos = true
	_volume(som_motor, -12.0, 1.5)
	var tw_carro := create_tween()
	tw_carro.tween_property(carro, "position:x", ext.PONTOS["carro_para"].x, 42.0)
	seguir(carro, Vector2(30, -20))
	_tocar_musica(-16.0)
	var tw_zoom := create_tween()
	tw_zoom.tween_property(camera, "zoom", mundo.zoom(2.2), 3.0)
	await esperar(9.0)  # passa pelo portão e pela placa "ÁREA DE CAMPING — 2 KM"

	# Dentro do carro (no top-down, a gente ouve as vozes enquanto o carro anda)
	await falar(lucas, "Mano, olha o tamanho desse lugar! A gente podia ficar aqui um mês.")
	await falar(marina, "Um mês? Eu só quero passar dois dias sem sinal de celular.")
	await falar(rafa, "Dois dias sem trabalho, sem internet, sem ninguém enchendo o saco. Isso aqui é perfeito.")
	await falar(voce, "Se ninguém se perder, já vai ser um ótimo começo.")
	await falar(lucas, "Relaxa. Eu tenho senso de direção.")
	await falar(marina, "Você se perdeu indo buscar pão ontem.")
	await esperar(0.6)

	# A música começa a desaparecer
	_volume(som_musica, -60.0, 4.0)
	if tw_carro.is_running():
		await tw_carro.finished

	# O carro para. Faróis e motor desligam.
	await esperar(0.3)
	ext.farois_acesos = false
	carro.texture = SpriteLibrary.quadro("carro", 0)  # faróis apagados
	_volume(som_motor, -80.0, 0.6)
	_volume(som_vento, -30.0, 1.0)
	await esperar(1.5)
	await falar(voce, "Chegamos… finalmente.")

	# A câmera sobe lentamente, revelando a cabana e a floresta ao redor
	_volume(som_vento, -20.0, 3.0)
	await camera_para(ext.ponto("cabana") + Vector2(-20, -40), 1.5, 4.0)
	# Uma janela está aberta. A cortina se move, apesar de não haver vento.
	ext.cortina_mexendo = true
	if ext._cortina: ext._cortina.queue_redraw()
	await camera_para(ext.ponto("janela_cabana"), 4.5, 3.5)
	await esperar(2.0)
	corte_seco()  # Corte.
	ext.cortina_mexendo = false
	if ext._cortina: ext._cortina.queue_redraw()
	await esperar(0.5)


# ---------------------------------------------------------------
# CENA 2 — A CABANA
# ---------------------------------------------------------------
func _cena2_cabana() -> void:
	# Saem do carro e vão até a PORTA (frente da cabana, não pela lateral)
	var porta: Vector2 = ext.PONTOS["porta_cabana"]
	# porta_cabana fica no "pé" da porta; aproximação pelo sul (y maior = na frente)
	var frente_porta := porta + Vector2(0, 28)
	fora(lucas, ext.PONTOS["carro_para"] + Vector2(20, 30), "direita")
	fora(marina, ext.PONTOS["carro_para"] + Vector2(-5, 34), "direita")
	fora(rafa, ext.PONTOS["carro_para"] + Vector2(-30, 30), "direita")
	fora(voce, ext.PONTOS["carro_para"] + Vector2(40, 20), "direita")
	camera_em(ext.ponto("frente_cabana") + Vector2(-60, 20), 2.6)
	clarear(0.8)
	lucas.andar_caminho([Vector2(700, 20), frente_porta + Vector2(0, 0)], 55.0)
	await esperar(0.5)
	marina.andar_caminho([Vector2(720, 30), frente_porta + Vector2(-12, 4)])
	rafa.andar_caminho([Vector2(710, 35), frente_porta + Vector2(12, 6)])
	await voce.andar_caminho([Vector2(730, 40), frente_porta + Vector2(-4, 10)])
	Sons.tocar(self, "rangido", -6.0)          # a porta range
	await esperar(0.8)
	await escurecer(0.6)

	# Dentro da cabana (fim de tarde)
	ambiente_para(COR_TARDE_DENTRO)
	cab.luz_acesa = false
	cab.porta_aberta = true
	cab.cama_lucas_vazia = false
	# Todos entram pela porta (spawn na soleira)
	na_cabana(lucas, "porta_dentro", "cima")
	na_cabana(marina, "porta_dentro", "cima")
	na_cabana(rafa, "porta_dentro", "cima")
	na_cabana(voce, "porta_dentro", "cima")
	marina.position += Vector2(-10, 8)
	rafa.position += Vector2(10, 10)
	voce.position += Vector2(0, 16)
	camera_em(cab.ponto("centro") + Vector2(0, -36), 3.3)
	_volume(som_vento, -30.0, 1.0)
	clarear(0.8)
	await lucas.andar_ate(CabanaInterior.PONTOS["centro"] + Vector2(-10, -20))
	marina.andar_ate(CabanaInterior.PONTOS["chao_porta"] + Vector2(-20, 0))
	rafa.andar_ate(CabanaInterior.PONTOS["mesa_dir"] + Vector2(10, 12))
	voce.andar_caminho([CabanaInterior.PONTOS["centro"] + Vector2(-60, 10), CabanaInterior.PONTOS["cama_voce"] + Vector2(0, 10)])

	await falar(lucas, "Olha isso! Quatro camas, uma cozinha… e ninguém cobrando diária.")
	await falar(marina, "Tem certeza de que a gente pode ficar aqui?")
	await falar(rafa, "Se tem cama, tem teto e não tem ninguém reclamando, eu considero um ótimo negócio.")

	# O protagonista coloca a mochila na cama... e a câmera mostra a fotografia
	voce.olhar("cima")
	await esperar(0.8)
	await camera_para(cab.ponto("foto"), 7.0, 2.0)
	await _mostrar_foto(3.5)
	await camera_para(cab.ponto("centro") + Vector2(-40, -30), 3.3, 1.2)
	voce.olhar("direita")
	await falar(voce, "Estranho…")
	marina.olhar("cima")
	await falar(marina, "O quê?")
	await falar(voce, "Nada. Deve ser de algum visitante antigo.")
	# A fotografia fica na tela um segundo a mais do que seria necessário
	await camera_para(cab.ponto("foto"), 6.0, 1.5)
	await esperar(2.2)


func _mostrar_foto(duracao: float) -> void:
	foto.visible = true
	foto.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(foto, "modulate:a", 1.0, 0.6)
	await tw.finished
	await esperar(duracao)
	var tw2 := create_tween()
	tw2.tween_property(foto, "modulate:a", 0.0, 0.6)
	await tw2.finished
	foto.visible = false


# ---------------------------------------------------------------
# CENA 3 — A PRIMEIRA NOITE
# ---------------------------------------------------------------
func _cena3_primeira_noite() -> void:
	await escurecer(2.0)
	_volume(som_vento, -32.0, 2.0)
	_volume(som_grilos, -16.0, 2.0)
	_volume(som_fogueira, -14.0, 2.0)

	# Fogueira acesa, lua no lago
	ambiente_para(COR_NOITE)
	ext.fogueira_acesa = true
	# Fake light: ambiente menos escuro perto da fogueira
	if ambiente:
		ambiente.color = Color(0.35, 0.28, 0.22)
	ext.lua_no_lago = true
	ext.luzes_cabana(2)
	cab.porta_aberta = false
	var f: Vector2 = ext.PONTOS["fogueira"]
	fora(voce, f + Vector2(-20, -10), "direita")
	fora(lucas, f + Vector2(20, -10), "esquerda")
	fora(marina, f + Vector2(-14, 16), "cima")
	fora(rafa, f + Vector2(16, 16), "cima")
	camera_em(f + Vector2(0, -10), 4.0)
	await clarear(2.0)
	_tocar_musica(-20.0)

	await falar(lucas, "Tá. Quem vai contar a primeira história de terror?")
	await falar(marina, "Eu não. Esse lugar já me dá arrepios o suficiente.")
	await falar(rafa, "Você fala isso em qualquer lugar que não tenha Wi-Fi.")
	await falar(marina, "E você fala isso porque nunca precisou dormir em um lugar desses.")
	await falar(lucas, "Ah, para. Se aparecer alguma coisa, eu resolvo.")
	await falar(voce, "Você vai resolver o quê? Vai pedir para ela esperar enquanto você corre?")
	await esperar(0.5)  # Lucas ri

	# A câmera se afasta. Os insetos diminuem. Uma coruja grita ao longe.
	_volume(som_musica, -60.0, 3.0)
	camera_para(f + Vector2(0, -20), 2.4, 4.0)
	_volume(som_grilos, -34.0, 3.0)
	await esperar(2.5)
	Sons.tocar(self, "coruja", -8.0)
	await esperar(1.6)
	marina.olhar("cima")  # olha para a floresta
	await falar(marina, "Vocês ouviram?")
	await falar(rafa, "Uma coruja.")
	await falar(marina, "Não. Antes disso.")
	await esperar(1.2)  # silêncio
	voce.olhar("cima")
	await esperar(2.0)  # nada se move

	# Interior da cabana: o rádio
	await escurecer(0.8)
	ext.fogueira_acesa = false
	_volume(som_fogueira, -80.0, 0.5)
	ambiente_para(COR_NOITE_DENTRO)
	cab.luz_acesa = true
	na_cabana(rafa, "radio", "direita")
	rafa.position += Vector2(-24, 0)  # do lado do rádio, mexendo no botão
	na_cabana(lucas, "mesa_dir", "direita")
	lucas.position += Vector2(-2, -4)
	na_cabana(marina, "mesa", "direita")
	na_cabana(voce, "centro", "direita")
	voce.position += Vector2(10, 20)
	camera_em(cab.ponto("radio") + Vector2(-30, -10), 4.2)
	await clarear(0.8)

	await falar(rafa, "Esse negócio só pega chiado.")
	cab.radio_ligado(true)
	Sons.tocar(self, "clique", -6.0)
	_volume(som_chiado, -16.0, 0.3)
	await falar(lucas, "Deve ser porque estamos no meio do nada.")
	# Rafa gira o botão. O chiado aumenta. Uma voz distorcida aparece.
	_volume(som_chiado, -9.0, 1.0)
	await esperar(1.2)
	Sons.tocar(self, (null if GameData.eh_mobile else Sons.voz_radio(2.0)), -4.0)
	tremer_camera(2.0, 12)
	await dialogo.radio("…não… saiam…")
	await esperar(0.6)  # Rafa para de girar o botão
	Sons.tocar(self, (null if GameData.eh_mobile else Sons.voz_radio(2.4)), -4.0)
	tremer_camera(2.0, 12)
	await dialogo.radio("…depois… do anoitecer…")
	# O rádio desliga sozinho.
	Sons.tocar(self, "clique", -4.0, 0.8)
	_volume(som_chiado, -80.0, 0.05)
	cab.radio_ligado(false)
	await esperar(1.8)  # ninguém fala

	# A câmera percorre os rostos
	await camera_para(rafa.global_position + Vector2(0, -16), 5.0, 0.9)
	await esperar(0.5)
	await camera_para(marina.global_position + Vector2(0, -16), 5.0, 0.9)  # Marina imóvel
	await esperar(0.7)
	await camera_para(lucas.global_position + Vector2(0, -16), 5.0, 0.9)   # Lucas tenta sorrir
	await falar(lucas, "Tá. Essa foi boa.")
	await falar(rafa, "Eu não fiz nada.")
	await falar(lucas, "Claro que não.")
	await camera_para(voce.global_position + Vector2(0, -16), 4.5, 0.9)
	voce.olhar("direita")
	await falar(voce, "Vamos dormir.")

	# Exterior: a câmera sobe. A cabana fica cada vez menor.
	await escurecer(0.8)
	ext.luzes_cabana(1)
	camera_em(ext.ponto("cabana") + Vector2(-100, -40), 2.6)
	_volume(som_grilos, -26.0, 1.0)
	_volume(som_vento, -22.0, 1.0)
	clarear(1.0)
	await camera_para(ext.ponto("cabana") + Vector2(-200, 20), 1.2, 5.0)
	ext.luzes_cabana(0)
	# Entre as árvores, uma silhueta atravessa a estrada (rápida demais)
	silhueta.visible = true
	silhueta.position = ext.PONTOS["silhueta"] + Vector2(0, -90)
	var tw := create_tween()
	tw.tween_property(silhueta, "position", ext.PONTOS["silhueta"] + Vector2(10, 90), 0.55)
	await tw.finished
	silhueta.visible = false
	await esperar(0.6)
	Sons.tocar(self, "galho", -2.0)  # um galho estala
	await esperar(0.5)
	corte_seco()  # Corte para preto.
	_volume(som_grilos, -80.0, 0.2)
	_volume(som_vento, -80.0, 0.2)
	await esperar(1.5)


# ---------------------------------------------------------------
# CENA 4 — O DESAPARECIMENTO
# ---------------------------------------------------------------
func _cena4_desaparecimento() -> void:
	# Amanhecer. Um despertador antigo.
	ambiente_para(COR_AMANHECER)
	cab.luz_acesa = false
	cab.cama_lucas_vazia = true
	cab.porta_aberta = true
	cab.pegadas = true
	esconder_todos()
	na_cabana(voce, "deitado_voce")
	voce.deitar(true)
	camera_em(cab.ponto("cama_voce") + Vector2(10, -6), 5.5)
	Sons.tocar(self, "despertador", -6.0)
	_volume(som_vento, -30.0, 2.0)
	await clarear(1.5)
	await esperar(0.8)
	# O protagonista acorda. A cama de Lucas está vazia.
	voce.deitar(false)
	voce.position = CabanaInterior.PONTOS["cama_voce"]
	voce.olhar("direita")
	await camera_para(cab.ponto("cama_lucas") + Vector2(0, -16), 5.0, 1.5)
	await esperar(0.8)
	# A porta da frente está aberta.
	await camera_para(cab.ponto("centro") + Vector2(-40, -20), 3.0, 1.5)
	await falar(voce, "Lucas?")
	await esperar(1.0)  # silêncio
	await falar(voce, "Lucas, para de brincadeira.")

	# Ele se levanta e vai até a porta. No chão, pegadas de terra molhada.
	seguir(voce)
	await voce.andar_caminho([CabanaInterior.PONTOS["centro"] + Vector2(-40, 0), CabanaInterior.PONTOS["chao_porta"] + Vector2(-6, 10)])
	voce.olhar("baixo")
	await camera_para(cab.ponto("chao_porta") + Vector2(0, 10), 5.0, 1.5)
	await esperar(1.5)  # elas seguem até a floresta

	# Exterior: Marina e Rafa saem da cabana
	await escurecer(0.6)
	ambiente_para(COR_DIA)
	ext.pegadas_visiveis = 1.0
	var frente: Vector2 = ext.PONTOS["frente_cabana"]
	fora(voce, frente + Vector2(14, 10), "baixo")
	fora(marina, frente + Vector2(-10, -24), "baixo")
	fora(rafa, frente + Vector2(-26, -20), "baixo")
	camera_em(frente + Vector2(10, 10), 3.4)
	clarear(0.6)
	_volume(som_vento, -22.0, 1.0)
	marina.andar_ate(frente + Vector2(-16, 6))
	await rafa.andar_ate(frente + Vector2(-34, 4))
	await falar(marina, "Ele não faria isso. Não sem avisar.")
	await falar(rafa, "Talvez tenha ido dar uma volta.")
	await falar(marina, "Sem o celular? Sem a mochila?")
	voce.olhar("direita")
	await esperar(0.8)  # o protagonista olha para as pegadas
	await falar(voce, "Vamos procurar.")

	# Os três entram na floresta seguindo as pegadas
	var trilha := ParqueExterior.TRILHA
	seguir(voce, Vector2(0, -10))
	voce.andar_caminho([trilha[1], trilha[2], trilha[3]], 40.0)
	await esperar(0.6)
	marina.andar_caminho([trilha[0], trilha[1], trilha[2] + Vector2(-10, -8)], 40.0)
	await esperar(0.5)
	await rafa.andar_caminho([trilha[0], trilha[1] + Vector2(-8, -6)], 40.0)
	await esperar(2.0)

	# Plano das pegadas: a câmera desce até o chão. As marcas ficam rasas...
	await escurecer(0.5)
	esconder_todos()
	camera_em(trilha[2], 5.5)
	clarear(0.5)
	await camera_para(trilha[4] + Vector2(12, 10), 6.5, 5.0)
	await esperar(1.0)  # depois dela, não há mais nada
	fora(marina, trilha[3] + Vector2(-6, -10), "baixo")
	fora(voce, trilha[3] + Vector2(10, -16), "baixo")
	await camera_para(trilha[3] + Vector2(10, 0), 4.0, 1.2)
	await falar(marina, "Isso não faz sentido…")
	voce.olhar("direita")
	await esperar(1.0)
	Sons.tocar(self, "galho", -14.0, 0.8)  # galhos quebrando, muito longe
	await esperar(1.6)
	corte_seco()
	await esperar(0.8)


# ---------------------------------------------------------------
# CENA 5 — O PARQUE NÃO QUER QUE VOCÊS SAIAM
# ---------------------------------------------------------------
func _cena5_montagem() -> void:
	# Montagem: a música aumenta aos poucos
	_volume(som_drone, -20.0, 3.0)
	_tocar_musica(-18.0)

	# • atravessam a floresta chamando por Lucas
	ambiente_para(COR_DIA)
	var p1 := Vector2(-400, 220)
	fora(voce, p1, "esquerda")
	fora(marina, p1 + Vector2(24, -10), "esquerda")
	fora(rafa, p1 + Vector2(40, 12), "esquerda")
	camera_em(p1, 3.0)
	clarear(0.4)
	voce.andar_ate(p1 + Vector2(-60, -10))
	marina.andar_ate(p1 + Vector2(-34, -20))
	rafa.andar_ate(p1 + Vector2(-20, 2))
	camera_para(p1 + Vector2(-40, -10), 3.0, 3.0)
	await falar(voce, "LUCAS!")

	# • Rafa grita o nome dele perto do lago
	await escurecer(0.3)
	esconder_todos()
	var margem: Vector2 = ext.PONTOS["margem_lago"]
	fora(rafa, margem, "cima")
	camera_em(margem + Vector2(0, -30), 3.2)
	clarear(0.3)
	await falar(rafa, "LUCAAAS!")

	# • Marina encontra um pedaço de tecido preso em um galho
	await escurecer(0.3)
	esconder_todos()
	ext.tecido_visivel = true
	var tec: Vector2 = ext.PONTOS["tecido"]
	fora(marina, tec + Vector2(-16, 16), "cima")
	camera_em(tec + Vector2(-6, 0), 5.0)
	clarear(0.3)
	await esperar(2.6)

	# • O protagonista observa o portão do parque ao longe
	await escurecer(0.3)
	esconder_todos()
	var vista: Vector2 = ext.PONTOS["vista_portao"]
	fora(voce, vista, "esquerda")
	camera_em(vista + Vector2(-70, -10), 2.6)
	clarear(0.3)
	await esperar(2.6)

	# • O sol desaparece atrás das árvores
	await escurecer(0.3)
	esconder_todos()
	camera_em(ext.ponto("lago") + Vector2(-100, 60), 1.6)
	clarear(0.3)
	await ambiente_para(COR_POR_DO_SOL, 2.0)
	await ambiente_para(COR_NOITE, 2.0)

	# • Os três retornam à cabana
	ext.luzes_cabana(3)
	fora(voce, ext.PONTOS["frente_cabana"] + Vector2(0, 60), "cima")
	fora(marina, ext.PONTOS["frente_cabana"] + Vector2(-20, 70), "cima")
	fora(rafa, ext.PONTOS["frente_cabana"] + Vector2(20, 72), "cima")
	camera_em(ext.ponto("frente_cabana") + Vector2(0, 20), 2.8)
	voce.andar_ate(ext.PONTOS["porta_cabana"] + Vector2(0, 10))
	marina.andar_ate(ext.PONTOS["porta_cabana"] + Vector2(-12, 20))
	await rafa.andar_ate(ext.PONTOS["porta_cabana"] + Vector2(12, 20))
	_volume(som_musica, -60.0, 2.0)
	await escurecer(0.6)

	# A montagem termina com Marina sentada na cama, exausta.
	ambiente_para(COR_NOITE_DENTRO)
	cab.luz_acesa = true
	cab.porta_aberta = false
	cab.pegadas = false
	ext.tecido_visivel = false
	na_cabana(marina, "cama_marina", "baixo")
	na_cabana(rafa, "radio", "esquerda")
	rafa.position += Vector2(-24, 0)
	na_cabana(voce, "janela", "cima")
	voce.position += Vector2(0, 12)
	camera_em(cab.ponto("cama_marina") + Vector2(-50, 20), 3.6)
	_volume(som_drone, -26.0, 1.0)
	_volume(som_vento, -28.0, 1.0)
	await clarear(0.8)
	await falar(marina, "A gente devia ter ido embora ontem.")
	await falar(rafa, "Vamos embora amanhã cedo. Assim que amanhecer.")
	await falar(voce, "E se o Lucas voltar?")
	await falar(marina, "Então a gente vai embora com ele.")

	# O rádio
	rafa.olhar("direita")
	await camera_para(cab.ponto("radio") + Vector2(-16, -6), 4.4, 1.0)
	Sons.tocar(self, "clique", -6.0)
	cab.radio_ligado(true)
	_volume(som_chiado, -14.0, 0.4)
	await esperar(1.2)
	Sons.tocar(self, (null if GameData.eh_mobile else Sons.voz_radio(2.6)), -2.0)
	await dialogo.radio("Eles acordam quando o sol se põe…")
	await voce.andar_ate(CabanaInterior.PONTOS["radio"] + Vector2(10, 20))
	voce.olhar("cima")
	await falar(voce, "Quem está falando?")
	Sons.tocar(self, (null if GameData.eh_mobile else Sons.voz_radio(2.4)), -1.0)
	tremer_camera(3.0, 14)
	await dialogo.radio("Não deixem… a luz apagar…")

	# Ruído agudo. A luz pisca.
	Sons.tocar(self, "microfonia", -6.0)
	for i in 4:
		cab.luz_acesa = false
		await esperar(0.08)
		cab.luz_acesa = true
		await esperar(0.15)
	marina.olhar("direita")
	await falar(marina, "Desliga isso!")
	await esperar(0.5)  # Rafa tenta desligar

	# A luz apaga. Silêncio absoluto.
	cab.luz_acesa = false
	cab.radio_ligado(false)
	ambiente_para(COR_ESCURO)
	for p in [som_chiado, som_drone, som_vento, som_grilos, som_fogueira, som_musica]:
		if p != null and is_instance_valid(p):  # no celular alguns sons nem existem (BUG da 6.x)
			p.volume_db = -80.0
	await esperar(3.0)  # por três segundos, não há som algum

	# Uma batida na porta. Uma única batida.
	Sons.tocar(self, "batida", -2.0)
	await esperar(2.2)  # ninguém se move
	# Outra batida, mais forte.
	Sons.tocar(self, "batida", 4.0, 0.85)
	tremer_camera(2.0, 6)
	await esperar(0.8)
	ambiente_para(Color(0.08, 0.08, 0.12), 0.5)
	camera_para(cab.ponto("porta_dentro"), 5.5, 4.0)  # a câmera se aproxima da porta
	await esperar(1.5)
	await dialogo.falar("Rafa", "(sussurrando) Tem alguém aí?")
	await esperar(1.5)  # nenhuma resposta
	# A maçaneta começa a girar...
	cab.macaneta_tremendo = true
	Sons.tocar(self, "rangido", -10.0, 1.6)
	await esperar(1.6)
	corte_seco()  # Corte para preto antes que a porta se abra.
	cab.macaneta_tremendo = false
	await esperar(2.0)


# ---------------------------------------------------------------
# CENA 6 — ELES JÁ ESTÃO DENTRO
# ---------------------------------------------------------------
func _cena6_eles_ja_estao_dentro() -> void:
	# Amanhecer. O protagonista acorda no chão da cabana.
	ambiente_para(COR_AMANHECER)
	esconder_todos()
	cab.camas_baguncadas = true
	cab.cama_lucas_vazia = true
	cab.porta_aberta = false
	cab.mensagem_visivel = true
	na_cabana(voce, "centro")
	voce.deitar(true)
	camera_em(cab.ponto("centro") + Vector2(-10, -4), 7.0)
	_volume(som_vento, -34.0, 3.0)
	await clarear(2.5)
	await esperar(1.2)
	voce.deitar(false)  # ele se levanta lentamente
	voce.position = CabanaInterior.PONTOS["centro"]
	await esperar(0.8)

	# A cabana está vazia. As camas de Marina e Rafa estão desarrumadas.
	await camera_para(cab.ponto("centro") + Vector2(0, -50), 3.2, 2.5)
	await camera_para(cab.ponto("cama_marina") + Vector2(10, -20), 4.5, 1.5)
	await esperar(1.0)
	# O protagonista olha para a parede: ELES JÁ ESTÃO DENTRO
	voce.olhar("cima")
	await camera_para(cab.ponto("parede_msg") + Vector2(0, -8), 5.5, 2.0)
	_volume(som_drone, -22.0, 2.0)
	await esperar(2.5)
	await voce.andar_ate(CabanaInterior.PONTOS["parede_msg"] + Vector2(0, 50))
	await falar(voce, "Marina?")
	await esperar(0.8)
	await falar(voce, "Rafa?")

	# Ele corre até a porta. A maçaneta não se move.
	seguir(voce)
	await voce.andar_caminho([Vector2(92, 128), CabanaInterior.PONTOS["porta_dentro"] + Vector2(0, -6)], 95.0)
	voce.olhar("baixo")
	Sons.tocar(self, "batida", -10.0, 1.6)
	tremer_camera(1.5, 4)
	await esperar(0.8)
	Sons.tocar(self, "batida", -8.0, 1.7)
	tremer_camera(1.5, 4)
	await esperar(1.2)  # trancada por dentro.

	# Ele olha pela janela: o portão principal está fechado, com correntes e cadeados novos.
	await voce.andar_ate(CabanaInterior.PONTOS["janela"] + Vector2(0, 14), 60.0)
	voce.olhar("cima")
	await esperar(0.6)
	await escurecer(0.4)
	ext.portao_fechado = true
	ambiente_para(COR_AMANHECER)
	esconder_todos()
	camera_em(ext.ponto("portao") + Vector2(160, 0), 1.6)
	clarear(0.6)
	await camera_para(ext.ponto("portao"), 4.0, 4.0)
	await esperar(1.0)

	# A narração retorna, mais baixa e mais distante
	await escurecer(0.6)
	na_cabana(voce, "janela", "baixo")
	voce.position += Vector2(0, 14)
	camera_em(voce.global_position + Vector2(0, -16), 6.0)
	clarear(0.6)
	_volume(som_chiado, -30.0, 1.0)
	await dialogo.narrar("Naquela manhã, eu ainda acreditava que havia alguma explicação. Eu ainda acreditava que, se encontrasse os outros, conseguiria sair dali.")
	await esperar(1.0)
	await dialogo.narrar("Eu não sabia que a noite já tinha começado.", 1.5)
	_volume(som_chiado, -80.0, 1.5)

	# A imagem escurece. O título aparece.
	await escurecer(2.0)
	botao_pular.visible = false
	_volume(som_drone, -14.0, 1.0)
	titulo_label.text = "ÚLTIMA NOITE\nNO PARQUE"
	var tw := create_tween()
	tw.tween_property(titulo_label, "modulate:a", 1.0, 2.0)
	await tw.finished
	await esperar(2.5)
	titulo_label.add_theme_font_size_override("font_size", 64)
	titulo_label.text = "SOBREVIVA."
	Sons.tocar(self, "batida", 0.0, 0.6)
	await esperar(2.5)
	var tw2 := create_tween()
	tw2.tween_property(titulo_label, "modulate:a", 0.0, 1.5)
	_volume(som_drone, -80.0, 2.0)
	await tw2.finished


# ===============================================================
# FIM / PULAR
# ===============================================================
func _ir_para_o_jogo() -> void:
	if _pulando:
		return
	_pulando = true
	GameData.vindo_da_cutscene = true
	GameData.etapa = 0
	GameData.salvar_jogo()
	GameData.trocar_cena(GameData.CENA_JOGO, 1.0)


func _on_pular() -> void:
	if not _confirmar_pular:
		_confirmar_pular = true
		botao_pular.text = "TOQUE DE NOVO"
		await esperar(2.5)
		if is_instance_valid(botao_pular) and not _pulando:
			botao_pular.text = "PULAR  ▶▶"
		_confirmar_pular = false
		return
	dialogo.fechar()
	_ir_para_o_jogo()


# ===============================================================
# PEQUENAS CLASSES DESENHADAS POR CÓDIGO
# ===============================================================

## A silhueta que atravessa a estrada na primeira noite.
class Silhueta extends Node2D:
	func _draw() -> void:
		var c := Color(0.0, 0.0, 0.0, 0.92)
		draw_circle(Vector2(0, -40), 5.0, c)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-6, -34), Vector2(6, -34), Vector2(8, -8), Vector2(4, 0), Vector2(-4, 0), Vector2(-8, -8)
		]), c)
		draw_line(Vector2(-6, -32), Vector2(-14, -10), c, 2.5)  # braços compridos demais...
		draw_line(Vector2(6, -32), Vector2(14, -10), c, 2.5)


## A fotografia antiga: quatro pessoas diante da mesma cabana, rostos irreconhecíveis.
class FotoAntiga extends Control:
	func _draw() -> void:
		var tela := size
		draw_rect(Rect2(Vector2.ZERO, tela), Color(0, 0, 0, 0.6))
		var l := minf(tela.x * 0.42, 520.0)
		var a := l * 0.72
		var r := Rect2((tela - Vector2(l, a)) / 2.0, Vector2(l, a))
		draw_rect(r.grow(14), Color(0.88, 0.84, 0.74))                       # borda de papel
		draw_rect(r, Color(0.52, 0.45, 0.35))                                # sépia
		draw_rect(Rect2(r.position + Vector2(0, a * 0.62), Vector2(l, a * 0.38)), Color(0.42, 0.36, 0.27))  # chão
		# cabana ao fundo
		var cx := r.position.x + l * 0.5
		var cy := r.position.y + a * 0.62
		draw_rect(Rect2(cx - l * 0.2, cy - a * 0.3, l * 0.4, a * 0.3), Color(0.3, 0.24, 0.18))
		draw_colored_polygon(PackedVector2Array([Vector2(cx - l * 0.25, cy - a * 0.3), Vector2(cx, cy - a * 0.5), Vector2(cx + l * 0.25, cy - a * 0.3)]), Color(0.24, 0.19, 0.14))
		draw_rect(Rect2(cx - l * 0.03, cy - a * 0.16, l * 0.06, a * 0.16), Color(0.15, 0.12, 0.09))
		# quatro pessoas (rostos apagados)
		for i in 4:
			var px := r.position.x + l * (0.2 + i * 0.2)
			var py := r.position.y + a * 0.86
			draw_colored_polygon(PackedVector2Array([Vector2(px - 14, py), Vector2(px - 10, py - 46), Vector2(px + 10, py - 46), Vector2(px + 14, py)]), Color(0.22, 0.18, 0.14))
			draw_circle(Vector2(px, py - 56), 11.0, Color(0.62, 0.55, 0.44))  # sem rosto...
		# manchas de foto velha
		var rng := RandomNumberGenerator.new()
		rng.seed = 1987
		for i in 40:
			draw_circle(r.position + Vector2(rng.randf() * l, rng.randf() * a), rng.randf_range(4, 22), Color(0.95, 0.9, 0.8, rng.randf_range(0.04, 0.14)))
		draw_rect(r, Color(0, 0, 0, 0.0))
