extends Control
## Tela "ESCOLHA SEU SOBREVIVENTE" + tela de carregamento macabra antes da cutscene.

const COLOR_ACCENT := Color(0.7, 0.1, 0.1)
const COLOR_TITLE := Color(0.85, 0.8, 0.7)

var _escolheu := false
var _botoes: Array[Button] = []

# Tela de carregamento
var loading_panel: ColorRect
var loading_bar: ProgressBar
var loading_label: Label
var loading_text_timer: Timer


func _ready() -> void:
	# BUG ANTIGO: a cena tinha só 40x40 pixels, então o fundo e os botões
	# ficavam espremidos no canto. Agora ocupa a tela inteira.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.02, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 30)
	add_child(vbox)

	var title := Label.new()
	title.text = "ESCOLHA SEU SOBREVIVENTE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	vbox.add_child(title)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 60)
	vbox.add_child(hbox)

	var btn_masc := _criar_botao_personagem("ELE", "protagonista", Color(0.5, 0.5, 0.8))
	btn_masc.pressed.connect(func(): _escolher("masculino"))
	hbox.add_child(btn_masc)

	var btn_fem := _criar_botao_personagem("ELA", "jogadora", Color(0.8, 0.5, 0.5))
	btn_fem.pressed.connect(func(): _escolher("feminino"))
	hbox.add_child(btn_fem)

	var voltar := Button.new()
	voltar.text = "VOLTAR"
	voltar.custom_minimum_size = Vector2(200, 50)
	voltar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	voltar.focus_mode = Control.FOCUS_NONE
	voltar.add_theme_font_size_override("font_size", 22)
	voltar.add_theme_color_override("font_color", COLOR_TITLE)
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.1, 0.12, 0.1, 0.9)
	estilo.border_color = Color(0.3, 0.3, 0.3, 0.5)
	estilo.set_border_width_all(2)
	voltar.add_theme_stylebox_override("normal", estilo)
	voltar.add_theme_stylebox_override("hover", estilo)
	voltar.add_theme_stylebox_override("pressed", estilo)
	voltar.pressed.connect(func():
		if not _escolheu:
			GameData.trocar_cena(GameData.CENA_MENU))
	vbox.add_child(voltar)

	_create_loading_screen()


func _criar_botao_personagem(texto: String, personagem: String, cor: Color) -> Button:
	var btn := Button.new()
	btn.text = texto
	btn.custom_minimum_size = Vector2(240, 330)
	btn.focus_mode = Control.FOCUS_NONE
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_BOTTOM
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_theme_font_size_override("font_size", 30)
	btn.add_theme_color_override("font_color", COLOR_TITLE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08)
	style.border_color = cor
	style.set_border_width_all(4)
	style.content_margin_top = 250  # empurra o texto para baixo (o boneco fica em cima)

	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = cor.darkened(0.6)

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)

	# Boneco animado andando dentro do botão
	var suporte := Node2D.new()
	suporte.position = Vector2(120, 230)
	suporte.scale = Vector2(6, 6)
	btn.add_child(suporte)
	var boneco := SpritePersonagem.new()
	boneco.personagem = personagem
	suporte.add_child(boneco)
	boneco.ready.connect(func(): boneco.play("andar_baixo"), CONNECT_ONE_SHOT)

	_botoes.append(btn)
	return btn


func _escolher(genero: String) -> void:
	if _escolheu:
		return
	_escolheu = true
	for b in _botoes:
		b.disabled = true
	GameData.novo_jogo(genero)  # salva a escolha no gerenciador global
	await _tela_de_carregamento()
	# BUG ANTIGO: o caminho era "res://cutscene.tscn", mas a cena fica em res://Scenes/
	GameData.trocar_cena(GameData.CENA_CUTSCENE, 1.0)


# ============================================================
# TELA DE CARREGAMENTO MACABRA (veio do menu)
# ============================================================
func _create_loading_screen() -> void:
	loading_panel = ColorRect.new()
	loading_panel.color = Color.BLACK
	loading_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading_panel.visible = false
	loading_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(loading_panel)

	var center_vbox := VBoxContainer.new()
	center_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center_vbox.add_theme_constant_override("separation", 40)
	loading_panel.add_child(center_vbox)

	loading_label = Label.new()
	loading_label.text = "CARREGANDO..."
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.add_theme_font_size_override("font_size", 32)
	loading_label.add_theme_color_override("font_color", COLOR_ACCENT)
	center_vbox.add_child(loading_label)

	loading_bar = ProgressBar.new()
	loading_bar.custom_minimum_size = Vector2(400, 30)
	loading_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	loading_bar.max_value = 100
	loading_bar.show_percentage = false
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.1)
	bg_style.border_color = Color(0.3, 0.0, 0.0)
	bg_style.set_border_width_all(2)
	loading_bar.add_theme_stylebox_override("background", bg_style)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.6, 0.0, 0.0)
	loading_bar.add_theme_stylebox_override("fill", fill_style)
	center_vbox.add_child(loading_bar)

	loading_text_timer = Timer.new()
	loading_text_timer.wait_time = 1.0
	loading_text_timer.timeout.connect(_glitch_loading_text)
	loading_panel.add_child(loading_text_timer)


func _glitch_loading_text() -> void:
	var spooky_texts := [
		"ELE ESTÁ VINDO...",
		"NÃO OLHE PARA TRÁS.",
		"VOCÊ NÃO ESTÁ %s." % GameData.g("SOZINHO", "SOZINHA"),
		"A ESCURIDÃO TE OBSERVA...",
		"CARREGANDO O PARQUE...",
	]
	loading_label.text = spooky_texts[randi() % spooky_texts.size()]
	# Glitch: o texto treme de vez em quando (usamos pivot/escala porque
	# o container não deixa mudar a posição)
	loading_label.pivot_offset = loading_label.size / 2.0
	loading_label.scale = Vector2(randf_range(0.97, 1.05), 1.0) if randf() < 0.35 else Vector2.ONE


func _tela_de_carregamento() -> void:
	loading_panel.visible = true
	loading_panel.modulate.a = 0.0
	loading_bar.value = 0
	var tw := create_tween()
	tw.tween_property(loading_panel, "modulate:a", 1.0, 0.8)
	await tw.finished

	loading_text_timer.start()
	var tw_bar := create_tween()
	tw_bar.tween_property(loading_bar, "value", 70.0, 1.6).set_trans(Tween.TRANS_QUAD)
	# "soluço": a barra trava, volta um pouco (estilo terror) e depois termina
	tw_bar.tween_interval(0.5)
	tw_bar.tween_property(loading_bar, "value", 62.0, 0.15)
	tw_bar.tween_interval(0.4)
	tw_bar.tween_property(loading_bar, "value", 100.0, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw_bar.finished

	loading_text_timer.stop()
	loading_label.scale = Vector2.ONE
	loading_label.text = "PRONTO PARA ENTRAR..."
	loading_label.add_theme_color_override("font_color", Color.WHITE)
	await get_tree().create_timer(0.8).timeout
