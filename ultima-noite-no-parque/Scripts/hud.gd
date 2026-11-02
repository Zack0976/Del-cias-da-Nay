class_name HUD
extends CanvasLayer
## Interface do jogo: objetivo, botão EXAMINAR, joystick, itens, pausa e mensagens.

signal botao_examinar
signal pediu_menu
signal pediu_salvar   ## v10: pausou / minimizou o app → a fase salva na hora

var objetivo_painel: PanelContainer
var objetivo_titulo: Label
var objetivo_texto: Label
var botao_acao: Button
var botao_pausa: Button
var itens_label: Label
var joystick: JoystickVirtual
var dialogo: DialogueBox
var pausa_painel: ColorRect
var dica_save: Label


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_criar_objetivo()
	_criar_botoes()
	_criar_pausa()

	joystick = $joystick as JoystickVirtual
	# No PC (sem tela de toque) o joystick fica escondido: use WASD / setas.
	_joystick_base = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or GameData.eh_mobile
	_aplicar_joystick()

	dialogo = DialogueBox.new()
	add_child(dialogo)


# ---------------------------------------------------------------
# OBJETIVO
# ---------------------------------------------------------------
func _criar_objetivo() -> void:
	objetivo_painel = PanelContainer.new()
	objetivo_painel.position = Vector2(24, 20)
	objetivo_painel.custom_minimum_size = Vector2(320, 0)
	objetivo_painel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0, 0, 0, 0.55)
	estilo.border_color = Color(0.5, 0.1, 0.1, 0.8)
	estilo.border_width_left = 4
	estilo.content_margin_left = 16
	estilo.content_margin_right = 16
	estilo.content_margin_top = 8
	estilo.content_margin_bottom = 10
	objetivo_painel.add_theme_stylebox_override("panel", estilo)
	add_child(objetivo_painel)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objetivo_painel.add_child(vbox)

	objetivo_titulo = Label.new()
	objetivo_titulo.text = "OBJETIVO"
	objetivo_titulo.add_theme_font_size_override("font_size", 18)
	objetivo_titulo.add_theme_color_override("font_color", Color(0.75, 0.15, 0.15))
	vbox.add_child(objetivo_titulo)

	objetivo_texto = Label.new()
	objetivo_texto.add_theme_font_size_override("font_size", 19)
	objetivo_texto.add_theme_color_override("font_color", Color(0.9, 0.88, 0.82))
	objetivo_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objetivo_texto.custom_minimum_size = Vector2(300, 0)
	vbox.add_child(objetivo_texto)
	objetivo_painel.modulate.a = 0.0


## Mostra um objetivo novo (aparece discretamente, como pede o roteiro).
func mostrar_objetivo(principal: String, detalhe := "") -> void:
	var texto := principal
	if detalhe != "":
		texto += "\n" + detalhe
	var tw := create_tween()
	if objetivo_painel.modulate.a > 0.0:
		tw.tween_property(objetivo_painel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): objetivo_texto.text = texto)
	tw.tween_property(objetivo_painel, "modulate:a", 1.0, 1.2)
	# um "pulso" vermelho no título para chamar atenção
	tw.tween_property(objetivo_titulo, "modulate", Color(2, 2, 2), 0.2)
	tw.tween_property(objetivo_titulo, "modulate", Color.WHITE, 0.6)
	# v9: depois de um tempo o objetivo fica clarinho (a tela fica mais limpa)
	tw.tween_interval(8.0)
	tw.tween_property(objetivo_painel, "modulate:a", 0.35, 1.5)


func atualizar_itens() -> void:
	var nomes := {"lanterna": "Lanterna", "chave": "Chave"}
	var lista: Array[String] = []
	for item in GameData.itens:
		lista.append(nomes.get(item, item))
	itens_label.text = "" if lista.is_empty() else "ITENS: " + ", ".join(lista)


# ---------------------------------------------------------------
# BOTÕES
# ---------------------------------------------------------------
func _estilo_botao(cor_borda: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.05, 0.05, 0.7)
	s.border_color = cor_borda
	s.set_border_width_all(3)
	s.set_corner_radius_all(60)
	return s


func _criar_botoes() -> void:
	botao_acao = Button.new()
	botao_acao.text = "EXAMINAR"
	botao_acao.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	botao_acao.offset_left = -250
	botao_acao.offset_top = -170
	botao_acao.offset_right = -50
	botao_acao.offset_bottom = -60
	botao_acao.focus_mode = Control.FOCUS_NONE
	botao_acao.add_theme_font_size_override("font_size", 26)
	botao_acao.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	botao_acao.add_theme_stylebox_override("normal", _estilo_botao(Color(0.7, 0.15, 0.15)))
	botao_acao.add_theme_stylebox_override("hover", _estilo_botao(Color(0.9, 0.2, 0.2)))
	botao_acao.add_theme_stylebox_override("pressed", _estilo_botao(Color(1.0, 0.4, 0.4)))
	botao_acao.pressed.connect(_on_botao_acao)
	botao_acao.visible = false
	add_child(botao_acao)

	botao_pausa = Button.new()
	botao_pausa.text = "II"
	botao_pausa.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	botao_pausa.offset_left = -90
	botao_pausa.offset_top = 20
	botao_pausa.offset_right = -24
	botao_pausa.offset_bottom = 86
	botao_pausa.focus_mode = Control.FOCUS_NONE
	botao_pausa.add_theme_font_size_override("font_size", 26)
	botao_pausa.add_theme_stylebox_override("normal", _estilo_botao(Color(0.4, 0.4, 0.4, 0.6)))
	botao_pausa.add_theme_stylebox_override("hover", _estilo_botao(Color(0.6, 0.6, 0.6, 0.8)))
	botao_pausa.add_theme_stylebox_override("pressed", _estilo_botao(Color(0.8, 0.8, 0.8)))
	botao_pausa.pressed.connect(pausar.bind(true))
	add_child(botao_pausa)

	itens_label = Label.new()
	itens_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	itens_label.offset_left = -500
	itens_label.offset_right = -110
	itens_label.offset_top = 36
	itens_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	itens_label.add_theme_font_size_override("font_size", 20)
	itens_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.45))
	itens_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(itens_label)


func _on_botao_acao() -> void:
	if dialogo.esta_ocupado():
		dialogo.avancar()  # durante uma mensagem, o botão serve para avançar
	else:
		botao_examinar.emit()


## Mostra o botão com o texto certo quando há algo perto para examinar.
func mostrar_acao(alvo: Interagivel) -> void:
	if alvo:
		botao_acao.text = alvo.acao
	botao_acao.visible = alvo != null


var _joystick_base := true          ## o aparelho usa joystick? (tela de toque)
var _motivos_escondido := {}        ## quem pediu para esconder o joystick (conversa, painel...)

## Durante falas e painéis, some com o botão e o joystick.
## v10 — BUG CORRIGIDO: antes o HUD "lembrava" se o joystick estava visível na hora
## de esconder. Abrindo a MOCHILA e depois o CRIAR (ou fechando o CRIAR enquanto
## algo era criado), ele lembrava "invisível" e o joystick sumia para sempre.
## Agora cada pedido tem um MOTIVO; o joystick volta quando não sobra nenhum motivo.
func modo_conversa(sim: bool, motivo := "conversa") -> void:
	if sim:
		_motivos_escondido[motivo] = true
		botao_acao.visible = false
	else:
		_motivos_escondido.erase(motivo)
	_aplicar_joystick()


func _aplicar_joystick() -> void:
	if joystick == null:
		return
	joystick.visible = _joystick_base and _motivos_escondido.is_empty()


## Segurança: limpa todos os motivos (ex.: depois de um teletransporte ou erro).
func liberar_controles() -> void:
	_motivos_escondido.clear()
	_aplicar_joystick()


# ---------------------------------------------------------------
# PAUSA
# ---------------------------------------------------------------
func _criar_pausa() -> void:
	pausa_painel = ColorRect.new()
	pausa_painel.color = Color(0, 0, 0, 0.85)
	pausa_painel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pausa_painel.visible = false
	add_child(pausa_painel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	pausa_painel.add_child(vbox)

	var titulo := Label.new()
	titulo.text = "PAUSADO"
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titulo.add_theme_font_size_override("font_size", 56)
	titulo.add_theme_color_override("font_color", Color(0.7, 0.1, 0.1))
	vbox.add_child(titulo)

	for dados in [["CONTINUAR", pausar.bind(false)], ["MENU PRINCIPAL", _on_menu]]:
		var b := Button.new()
		b.text = dados[0]
		b.custom_minimum_size = Vector2(320, 60)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 26)
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.1, 0.12, 0.1, 0.9)
		s.border_color = Color(0.5, 0.1, 0.1)
		s.set_border_width_all(2)
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_stylebox_override("hover", s)
		b.add_theme_stylebox_override("pressed", s)
		b.pressed.connect(dados[1])
		vbox.add_child(b)

	var dica := Label.new()
	dica_save = dica
	dica.text = "Seu progresso é salvo automaticamente."
	dica.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dica.add_theme_font_size_override("font_size", 18)
	dica.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(dica)


func pausar(sim: bool) -> void:
	if sim:
		pediu_salvar.emit()
	pausa_painel.visible = sim
	get_tree().paused = sim


## Texto embaixo do menu de pausa (ex.: "Salvo: Dia 2 · 14:20").
func info_save(texto: String) -> void:
	if dica_save:
		dica_save.text = texto


func _on_menu() -> void:
	pediu_salvar.emit()   # a fase atualiza o save ANTES de gravar (antes gravava dados velhos)
	GameData.salvar_jogo()
	pediu_menu.emit()
	GameData.trocar_cena(GameData.CENA_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pausar"):
		pausar(not pausa_painel.visible)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Android: botão voltar pausa. Celular minimizado: pausa também.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		pausar(not pausa_painel.visible)
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if is_inside_tree() and not pausa_painel.visible and OS.has_feature("mobile"):
			pausar(true)
		elif is_inside_tree():
			pediu_salvar.emit()   # o Android pode fechar o app minimizado: salva antes
