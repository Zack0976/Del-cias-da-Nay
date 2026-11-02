extends Control

# ============================================================
# ÚLTIMA NOITE NO PARQUE - Menu Principal
# ============================================================

const COLOR_BG          := Color(0.02, 0.03, 0.02, 1.0)
const COLOR_TITLE       := Color(0.85, 0.8, 0.7, 1.0)
const COLOR_ACCENT      := Color(0.7, 0.1, 0.1, 1.0)
const COLOR_BUTTON      := Color(0.1, 0.12, 0.1, 0.9)
const COLOR_BUTTON_HOVER:= Color(0.25, 0.05, 0.05, 1.0)
const COLOR_DISABLED    := Color(0.5, 0.5, 0.5, 0.6)

var fog_layers: Array[ColorRect] = []
var particles: CPUParticles2D
var title_label: Label
var button_container: VBoxContainer
var btn_continuar: Button

var options_panel: ColorRect
var credits_panel: ColorRect
var quit_panel: ColorRect
var confirm_new_panel: ColorRect
var diag_panel: ColorRect
var diag_texto: Label
var aviso_label: Label

var colosso_bg: Node2D
var tree_time := 0.0
var _saindo := false
var _som_vento: AudioStreamPlayer
var _som_drone: AudioStreamPlayer


func _ready() -> void:
	GameData.log_passo("menu: começando")
	randomize()
	get_tree().quit_on_go_back = false  # o botão "voltar" do Android abre o "Sair?" em vez de fechar direto
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_create_redraw_timer()
	_create_fog()
	_create_particles()
	_create_main_ui()
	_create_fullscreen_panels()
	_create_timers()

	_iniciar_audio_menu()

	get_viewport().size_changed.connect(_on_tamanho_mudou)
	GameData.log_passo("menu: interface criada")
	_play_entrance()
	await RenderingServer.frame_post_draw
	GameData.log_passo("menu: primeiro quadro desenhado")
	await get_tree().create_timer(5.0).timeout
	GameData.log_passo("menu: estável (5 s sem fechar)")


func _iniciar_audio_menu() -> void:
	_som_vento = null
	_som_drone = null
	if not GameData.som_ligado:
		return
	# Mobile: NENHUM loop no menu (vento crashava o Mali ao ligar o som).
	if GameData.eh_mobile:
		GameData.log_passo("menu: som ligado (sem ambient no mobile)")
		return
	_som_vento = Sons.tocar_loop(self, "vento", -80.0)
	Sons.fade(_som_vento, -16.0, 3.0)
	_som_drone = Sons.tocar_loop(self, "drone", -80.0)
	Sons.fade(_som_drone, -24.0, 3.0)


func _on_tamanho_mudou() -> void:
	# celular girou / janela mudou de tamanho: reposiciona a neblina de partículas
	if particles == null or not is_instance_valid(particles):
		return
	var sz := get_viewport_rect().size
	particles.position = sz * 0.5
	particles.emission_rect_extents = Vector2(sz.x * 0.6, sz.y * 0.5)


func _play_entrance() -> void:
	# BUG ANTIGO: os botões apareciam, sumiam e depois voltavam (piscavam).
	# Agora tudo já começa invisível.
	modulate.a = 0.0
	title_label.modulate.a = 0.0
	for btn in button_container.get_children():
		(btn as Control).modulate.a = 0.0

	create_tween().tween_property(self, "modulate:a", 1.0, 1.5)
	await get_tree().create_timer(0.8).timeout

	# BUG ANTIGO: mexer no "position" de algo dentro de um VBoxContainer não funciona,
	# porque o container reposiciona os filhos. Usamos escala (o container não mexe nela).
	await get_tree().process_frame
	title_label.pivot_offset = title_label.size / 2.0
	title_label.scale = Vector2(1.15, 1.15)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(title_label, "modulate:a", 1.0, 1.2)
	tw.tween_property(title_label, "scale", Vector2.ONE, 1.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(0.6).timeout
	var i := 0
	for btn in button_container.get_children():
		var alvo := 1.0
		if btn == btn_continuar and btn_continuar.disabled:
			alvo = 0.45
		create_tween().tween_property(btn, "modulate:a", alvo, 0.4).set_delay(i * 0.1)
		i += 1


# ============================================================
# UI PRINCIPAL E BOTÕES
# ============================================================
func _create_main_ui() -> void:
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_theme_constant_override("separation", 40)
	main_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.z_index = 10
	add_child(main_vbox)

	title_label = Label.new()
	title_label.text = "ÚLTIMA NOITE\nNO PARQUE"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 72)
	title_label.add_theme_color_override("font_color", COLOR_TITLE)
	title_label.add_theme_color_override("font_outline_color", COLOR_ACCENT)
	title_label.add_theme_constant_override("outline_size", 16)
	main_vbox.add_child(title_label)

	button_container = VBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 12)
	button_container.custom_minimum_size = Vector2(320, 0)
	button_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main_vbox.add_child(button_container)

	var labels := ["NOVO JOGO", "CONTINUAR", "OPÇÕES", "CRÉDITOS", "SAIR"]
	var callbacks := [_on_new_game, _on_continue, _on_options, _on_credits, _on_quit]

	for i in range(labels.size()):
		var btn := _create_styled_button(labels[i])
		btn.pressed.connect(callbacks[i])
		button_container.add_child(btn)
		if labels[i] == "CONTINUAR":
			btn_continuar = btn

	# "Continuar" só funciona se existir um jogo salvo
	btn_continuar.disabled = not GameData.tem_save()

	# Aviso se o jogo fechou sozinho da última vez (ajuda a achar bugs)
	aviso_label = Label.new()
	aviso_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	aviso_label.add_theme_font_size_override("font_size", 18)
	aviso_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
	aviso_label.visible = GameData.fechou_sozinho
	aviso_label.text = "O jogo fechou sozinho da última vez (em: %s). Modo seguro (sem som). Veja OPÇÕES > DIAGNÓSTICO." % GameData.ultimo_passo
	main_vbox.add_child(aviso_label)

	var versao := Label.new()
	versao.text = "v10.0"
	versao.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	versao.offset_left = -60
	versao.offset_top = -36
	versao.add_theme_font_size_override("font_size", 16)
	versao.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.6))
	add_child(versao)


func _create_styled_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(300, 56)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_color_override("font_color", COLOR_TITLE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", COLOR_DISABLED)

	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_BUTTON
	normal.border_color = Color(0.3, 0.3, 0.3, 0.5)
	normal.set_border_width_all(2)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = COLOR_BUTTON_HOVER
	hover.border_color = COLOR_ACCENT

	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.4, 0.05, 0.05)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", normal)
	return btn


# ============================================================
# NOVO JOGO / CONTINUAR
# ============================================================
func _on_new_game() -> void:
	if GameData.tem_save():
		_open_panel(confirm_new_panel)  # pergunta antes de apagar o progresso
	else:
		_comecar_novo_jogo()


func _comecar_novo_jogo() -> void:
	if _saindo:
		return
	_saindo = true
	if _som_vento: Sons.fade(_som_vento, -80.0, 0.8)
	if _som_drone: Sons.fade(_som_drone, -80.0, 0.8)
	GameData.apagar_save()
	# BUG ANTIGO: o caminho era "res://Cutsene.tscn" (escrito errado e na pasta errada),
	# por isso sempre aparecia "ERRO 404". Agora os caminhos ficam todos no GameData.
	GameData.trocar_cena(GameData.CENA_SELECAO)


func _on_continue() -> void:
	if _saindo or not GameData.carregar_jogo():
		return
	_saindo = true
	GameData.vindo_da_cutscene = false
	if _som_vento: Sons.fade(_som_vento, -80.0, 0.8)
	if _som_drone: Sons.fade(_som_drone, -80.0, 0.8)
	GameData.trocar_cena(GameData.cena_do_save())  # etapa 5+ = Parte 2


# ============================================================
# TELAS DE TELA CHEIA (Opções, Créditos, Sair)
# ============================================================
func _create_fullscreen_panels() -> void:
	options_panel = _create_base_panel("OPÇÕES")
	var opt_vbox := options_panel.get_node("Margin/VBox") as VBoxContainer
	# BUG ANTIGO: os sliders não mudavam nada. Agora mexem no volume de verdade e salvam.
	_add_slider(opt_vbox, "Volume Geral", "Master")
	_add_slider(opt_vbox, "Volume Música", "Musica")
	_add_slider(opt_vbox, "Volume Efeitos", "Efeitos")
	opt_vbox.add_theme_constant_override("separation", 16)

	# Qualidade / desempenho
	var linha := HBoxContainer.new()
	linha.alignment = BoxContainer.ALIGNMENT_CENTER
	linha.add_theme_constant_override("separation", 16)
	opt_vbox.add_child(linha)
	var btn_pixel := _create_styled_button("")
	btn_pixel.custom_minimum_size = Vector2(280, 52)
	btn_pixel.add_theme_font_size_override("font_size", 20)
	var atualizar_pixel := func():
		btn_pixel.text = "DETALHE: " + {4: "BAIXO (leve)", 3: "MÉDIO", 2: "ALTO"}[GameData.tamanho_pixel]
	atualizar_pixel.call()
	btn_pixel.pressed.connect(func():
		GameData.tamanho_pixel = 4 if GameData.tamanho_pixel <= 2 else GameData.tamanho_pixel - 1
		GameData.salvar_config()
		atualizar_pixel.call())
	linha.add_child(btn_pixel)
	var btn_fps := _create_styled_button("")
	btn_fps.custom_minimum_size = Vector2(240, 52)
	btn_fps.add_theme_font_size_override("font_size", 20)
	var atualizar_fps := func():
		btn_fps.text = "FPS: %d%s" % [GameData.fps_maximo, " (economia)" if GameData.fps_maximo == 30 else ""]
	atualizar_fps.call()
	btn_fps.pressed.connect(func():
		GameData.fps_maximo = 30 if GameData.fps_maximo == 60 else 60
		GameData.aplicar_qualidade()
		atualizar_fps.call())
	linha.add_child(btn_fps)
	var btn_som := _create_styled_button("")
	btn_som.custom_minimum_size = Vector2(220, 52)
	btn_som.add_theme_font_size_override("font_size", 20)
	var atualizar_som := func():
		btn_som.text = "SOM: " + (("EFEITOS" if GameData.eh_mobile else "LIGADO") if GameData.som_ligado else "DESLIGADO")
	atualizar_som.call()
	btn_som.pressed.connect(func():
		GameData.som_ligado = not GameData.som_ligado
		GameData.salvar_config()
		if _som_vento and is_instance_valid(_som_vento):
			_som_vento.stop()
			_som_vento.queue_free()
			_som_vento = null
		if _som_drone and is_instance_valid(_som_drone):
			_som_drone.stop()
			_som_drone.queue_free()
			_som_drone = null
		if GameData.som_ligado:
			_iniciar_audio_menu()
		atualizar_som.call())
	linha.add_child(btn_som)

	var linha2 := HBoxContainer.new()
	linha2.alignment = BoxContainer.ALIGNMENT_CENTER
	linha2.add_theme_constant_override("separation", 16)
	opt_vbox.add_child(linha2)
	var btn_diag := _create_styled_button("DIAGNÓSTICO")
	btn_diag.custom_minimum_size = Vector2(300, 52)
	btn_diag.add_theme_font_size_override("font_size", 20)
	btn_diag.pressed.connect(_abrir_diagnostico)
	linha2.add_child(btn_diag)
	var btn_cache := _create_styled_button("LIMPAR CACHE")
	btn_cache.custom_minimum_size = Vector2(300, 52)
	btn_cache.add_theme_font_size_override("font_size", 20)
	btn_cache.pressed.connect(func():
		GameData.limpar_cache()
		btn_cache.text = "CACHE LIMPO!")
	linha2.add_child(btn_cache)

	var opt_back := _create_styled_button("VOLTAR")
	opt_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	opt_back.pressed.connect(func():
		GameData.salvar_config()
		btn_cache.text = "LIMPAR CACHE"
		_close_panel(options_panel))
	opt_vbox.add_child(opt_back)

	# Painel de diagnóstico
	diag_panel = _create_base_panel("DIAGNÓSTICO")
	var diag_vbox := diag_panel.get_node("Margin/VBox") as VBoxContainer
	diag_vbox.add_theme_constant_override("separation", 14)
	diag_texto = Label.new()
	diag_texto.add_theme_font_size_override("font_size", 17)
	diag_texto.add_theme_color_override("font_color", COLOR_TITLE)
	diag_texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diag_texto.custom_minimum_size = Vector2(900, 0)
	diag_texto.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	diag_vbox.add_child(diag_texto)
	var diag_back := _create_styled_button("VOLTAR")
	diag_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	diag_back.pressed.connect(func(): _close_panel(diag_panel))
	diag_vbox.add_child(diag_back)

	credits_panel = _create_base_panel("CRÉDITOS")
	var cred_vbox := credits_panel.get_node("Margin/VBox") as VBoxContainer
	var cred_label := Label.new()
	cred_label.text = "ÚLTIMA NOITE NO PARQUE\n\nCriado por Isaac\nDesenvolvido com Godot 4\n\nO que espreita na escuridão\nestá sempre observando.\n\nObrigado por jogar!"
	cred_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cred_label.add_theme_font_size_override("font_size", 24)
	cred_label.add_theme_color_override("font_color", COLOR_TITLE)
	cred_vbox.add_child(cred_label)
	var cred_back := _create_styled_button("VOLTAR")
	cred_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cred_back.pressed.connect(func(): _close_panel(credits_panel))
	cred_vbox.add_child(cred_back)

	quit_panel = _create_base_panel("SAIR")
	_add_yes_no(quit_panel, "Tem certeza de que\ndeseja sair?", _on_quit_yes)

	confirm_new_panel = _create_base_panel("NOVO JOGO")
	_add_yes_no(confirm_new_panel, "Começar de novo?\nO progresso salvo será apagado.", func():
		_close_panel(confirm_new_panel)
		_comecar_novo_jogo())


func _add_yes_no(panel: ColorRect, pergunta: String, ao_confirmar: Callable) -> void:
	var vbox := panel.get_node("Margin/VBox") as VBoxContainer
	var lbl := Label.new()
	lbl.text = pergunta
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", COLOR_ACCENT)
	vbox.add_child(lbl)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 30)

	var btn_yes := _create_styled_button("SIM")
	btn_yes.custom_minimum_size = Vector2(130, 60)
	btn_yes.pressed.connect(ao_confirmar)

	var btn_no := _create_styled_button("NÃO")
	btn_no.custom_minimum_size = Vector2(130, 60)
	btn_no.pressed.connect(func(): _close_panel(panel))

	hbox.add_child(btn_yes)
	hbox.add_child(btn_no)
	vbox.add_child(hbox)


func _create_base_panel(title_text: String) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.01, 0.01, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.visible = false
	bg.z_index = 50
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.name = "Margin"
	bg.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 30)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	vbox.add_child(title)
	return bg


func _add_slider(parent: VBoxContainer, label_text: String, barramento: String) -> void:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(220, 0)
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", COLOR_TITLE)
	hbox.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = GameData.volumes.get(barramento, 0.8)
	slider.custom_minimum_size = Vector2(300, 40)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v: float): GameData.definir_volume(barramento, v))
	hbox.add_child(slider)
	parent.add_child(hbox)


func _open_panel(panel: ColorRect) -> void:
	panel.visible = true
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, 0.3)


func _close_panel(panel: ColorRect) -> void:
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 0.0, 0.2)
	await tw.finished
	panel.visible = false


func _abrir_diagnostico() -> void:
	var info := PackedStringArray()
	info.append("Godot %s  |  Renderizador: %s" % [Engine.get_version_info().string, RenderingServer.get_current_rendering_method()])
	info.append("Placa de vídeo: %s" % RenderingServer.get_video_adapter_name())
	info.append("Sistema: %s  |  Tela: %s" % [OS.get_name(), str(DisplayServer.screen_get_size())])
	info.append("Memória usada: %.1f MB  |  Memória de vídeo: %.1f MB" % [OS.get_static_memory_usage() / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	info.append("FPS agora: %d  |  Cache: %.1f MB" % [Engine.get_frames_per_second(), GameData.tamanho_do_cache() / 1048576.0])
	if GameData.fechou_sozinho:
		info.append("\nATENÇÃO: na última vez o jogo fechou sozinho durante: " + GameData.ultimo_passo)
	if GameData.passos_anteriores != "":
		var linhas := GameData.passos_anteriores.strip_edges().split("\n")
		info.append("\nÚltimos passos da vez anterior:")
		info.append_array(linhas.slice(maxi(0, linhas.size() - 5)))
	info.append("\nErros do log da vez anterior:")
	info.append_array(GameData.erros_do_log_anterior(6))
	diag_texto.text = "\n".join(info)
	_open_panel(diag_panel)


func _on_options() -> void: _open_panel(options_panel)
func _on_credits() -> void: _open_panel(credits_panel)
func _on_quit() -> void: _open_panel(quit_panel)


## Botão "voltar" do Android (ou Esc no PC) fecha a janela aberta.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		for p in [diag_panel, options_panel, credits_panel, quit_panel, confirm_new_panel]:
			if p.visible:
				if p == options_panel:
					GameData.salvar_config()
				_close_panel(p)
				get_viewport().set_input_as_handled()
				return


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var algum_aberto := false
		for p in [diag_panel, options_panel, credits_panel, quit_panel, confirm_new_panel]:
			if p and p.visible:
				algum_aberto = true
				_close_panel(p)
		if not algum_aberto and quit_panel:
			_on_quit()


# ============================================================
# O JUMPSCARE ESTILO FNAF
# ============================================================
func _on_quit_yes() -> void:
	if _saindo:
		return
	_saindo = true
	quit_panel.visible = false
	title_label.visible = false
	button_container.visible = false
	for fog in fog_layers:
		if fog: fog.visible = false
	if _som_vento and is_instance_valid(_som_vento):
		_som_vento.stop()
	if _som_drone and is_instance_valid(_som_drone):
		_som_drone.stop()

	# Grito: no mobile usa batida forte se grito for bloqueado
	Sons.tocar(self, "grito", 2.0)
	Sons.tocar(self, "batida", 4.0, 0.7)

	var jumpscare_node := Node2D.new()
	jumpscare_node.set_script(load("res://Scripts/colosso_drawer.gd"))
	jumpscare_node.z_index = 100
	add_child(jumpscare_node)

	var sz := get_viewport_rect().size
	jumpscare_node.position = sz * 0.5
	jumpscare_node.scale = Vector2(0.1, 0.1)

	var tw_monster := create_tween()
	tw_monster.set_parallel(true)
	tw_monster.tween_property(jumpscare_node, "scale", Vector2(3.5, 3.5) * (sz.y / 720.0), 0.15).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw_monster.tween_property(jumpscare_node, "rotation", randf_range(-0.2, 0.2), 0.15)

	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 101
	add_child(flash)

	var tw_flash := create_tween()
	tw_flash.set_loops(5)
	tw_flash.tween_property(flash, "color", Color(1, 0, 0, 0.8), 0.05)
	tw_flash.tween_property(flash, "color", Color(0, 0, 0, 0.8), 0.05)

	# BUG ANTIGO: o tremor sorteava UMA posição só e repetia (não tremia de verdade).
	# Agora sorteia uma posição nova a cada tremida.
	for i in 15:
		position = Vector2(randf_range(-40, 40), randf_range(-40, 40))
		await get_tree().create_timer(0.03).timeout
	position = Vector2.ZERO

	await get_tree().create_timer(1.35).timeout
	get_tree().quit()


# ============================================================
# AMBIENTE E TIMERS
# ============================================================
func _create_redraw_timer() -> void:
	var timer := Timer.new()
	timer.wait_time = 1.0 / 20.0
	timer.timeout.connect(func():
		tree_time = Time.get_ticks_msec() * 0.001
		for i in fog_layers.size():  # neblina "respirando"
			fog_layers[i].modulate.a = 0.6 + 0.4 * sin(tree_time * (0.3 + i * 0.17) + i)
		queue_redraw()
	)
	timer.autostart = true
	add_child(timer)


func _draw() -> void:
	var sz := size
	if sz.x < 1.0: sz = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, sz), COLOR_BG, true)
	# lua
	draw_circle(Vector2(sz.x * 0.82, sz.y * 0.18), 46.0, Color(0.75, 0.75, 0.68, 0.18))
	draw_circle(Vector2(sz.x * 0.82, sz.y * 0.18), 34.0, Color(0.85, 0.85, 0.78, 0.25))
	# árvores passando devagar ao fundo
	for i in range(8):
		var x := fmod(i * 270.0 - tree_time * 10.0, sz.x + 400) - 200
		if x < -200: x += sz.x + 400
		draw_rect(Rect2(x, sz.y - 450, 80, 450), Color(0.05, 0.05, 0.05))
		draw_circle(Vector2(x + 40, sz.y - 450), 120, Color(0.03, 0.04, 0.03))


func _create_timers() -> void:
	var scare_timer := Timer.new()
	scare_timer.wait_time = 15.0
	scare_timer.timeout.connect(_spawn_background_colosso)
	scare_timer.autostart = true
	add_child(scare_timer)


func _spawn_background_colosso() -> void:
	if _saindo:
		return
	if colosso_bg and is_instance_valid(colosso_bg):
		colosso_bg.queue_free()

	colosso_bg = Node2D.new()
	colosso_bg.set_script(load("res://Scripts/colosso_drawer.gd"))
	colosso_bg.z_index = 1
	add_child(colosso_bg)

	var sz := size if size.x > 1.0 else get_viewport_rect().size
	colosso_bg.position = Vector2(randf_range(150, sz.x - 150), randf_range(sz.y * 0.4, sz.y - 100))
	colosso_bg.scale = Vector2(0.3, 0.3)
	colosso_bg.modulate.a = 0.0

	var tw := create_tween()
	tw.tween_property(colosso_bg, "modulate:a", 0.2, 2.0)
	tw.tween_interval(3.0)
	tw.tween_property(colosso_bg, "modulate:a", 0.0, 2.0)
	tw.tween_callback(colosso_bg.queue_free)


func _create_fog() -> void:
	for i in range(3):
		var fog := ColorRect.new()
		fog.color = Color(0.12, 0.18, 0.15, 0.08)
		fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fog.z_index = 2
		add_child(fog)
		fog_layers.append(fog)


func _create_particles() -> void:
	if not GameData.permite_particulas():
		particles = null
		return
	particles = CPUParticles2D.new()
	particles.z_index = 3
	particles.amount = 40
	particles.lifetime = 7.0
	particles.preprocess = 7.0
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.color = Color(0.5, 0.5, 0.5, 0.2)
	# BUG ANTIGO: as partículas tinham gravidade padrão (980) e "caíam" na hora.
	# Poeira/névoa flutua devagar:
	particles.gravity = Vector2(0, -4)
	particles.direction = Vector2(1, 0)
	particles.spread = 180.0
	particles.initial_velocity_min = 4.0
	particles.initial_velocity_max = 14.0
	particles.scale_amount_min = 1.5
	particles.scale_amount_max = 3.5
	particles.emitting = GameData.permite_particulas()
	add_child(particles)
	_on_tamanho_mudou()
