class_name DialogueBox
extends CanvasLayer
## Caixa de diálogo / legendas.
##
## Uso:
##     await dialogo.falar("Lucas", "Mano, olha o tamanho desse lugar!")
##     await dialogo.narrar("Eu passei muito tempo tentando esquecer...")
##     await dialogo.radio("...não... saiam...")
##
## Toque na tela (ou Espaço/Enter) para mostrar o texto todo; toque de novo para avançar.
## Se ninguém tocar, avança sozinho depois de um tempo (tempo de leitura).

signal avancou
signal _terminou_de_digitar

const VELOCIDADE_LETRAS := 55.0  ## letras por segundo

const CORES := {
	"Você": Color(0.95, 0.85, 0.6),
	"Lucas": Color(0.55, 0.75, 1.0),
	"Marina": Color(0.85, 0.65, 0.95),
	"Rafa": Color(0.6, 0.9, 0.6),
	"Rádio": Color(0.95, 0.25, 0.2),
}

var painel: PanelContainer
var nome_label: Label
var texto_label: Label
var seta: Label
var narracao_label: Label

var _label_atual: Label
var _digitando := false
var _esperando := false
var _ultimo_toque := 0
var _tempo_letras := 0.0
var _total_letras := 0
var _tremer := false
var _painel_base := Vector2.ZERO
var _timer_leitura: Timer


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Timer "filho": se a cena for apagada no meio de uma fala, ele some junto
	# e nada fica tentando continuar depois (evita erros ao pular a cutscene).
	_timer_leitura = Timer.new()
	_timer_leitura.one_shot = true
	_timer_leitura.timeout.connect(_avancar_automatico)
	add_child(_timer_leitura)
	_montar_caixa()
	_montar_narracao()


func _montar_caixa() -> void:
	painel = PanelContainer.new()
	painel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	painel.offset_left = 60
	painel.offset_right = -60
	painel.offset_top = -170
	painel.offset_bottom = -24
	painel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.03, 0.03, 0.04, 0.92)
	estilo.border_color = Color(0.45, 0.08, 0.08)
	estilo.set_border_width_all(2)
	estilo.set_corner_radius_all(6)
	estilo.content_margin_left = 24
	estilo.content_margin_right = 24
	estilo.content_margin_top = 12
	estilo.content_margin_bottom = 12
	painel.add_theme_stylebox_override("panel", estilo)
	add_child(painel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	painel.add_child(vbox)

	nome_label = Label.new()
	nome_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(nome_label)

	texto_label = Label.new()
	texto_label.add_theme_font_size_override("font_size", 26)
	texto_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.9))
	texto_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texto_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(texto_label)

	seta = Label.new()
	seta.text = "▼"
	seta.add_theme_font_size_override("font_size", 18)
	seta.add_theme_color_override("font_color", Color(0.7, 0.15, 0.15))
	seta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vbox.add_child(seta)
	painel.visible = false


func _montar_narracao() -> void:
	narracao_label = Label.new()
	# uma faixa escura atravessando a tela, para ler a narração por cima de qualquer imagem
	narracao_label.set_anchors_and_offsets_preset(Control.PRESET_HCENTER_WIDE)
	narracao_label.offset_top = -110
	narracao_label.offset_bottom = 110
	var faixa := StyleBoxFlat.new()
	faixa.bg_color = Color(0, 0, 0, 0.55)
	faixa.content_margin_left = 160
	faixa.content_margin_right = 160
	narracao_label.add_theme_stylebox_override("normal", faixa)
	narracao_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	narracao_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	narracao_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	narracao_label.add_theme_font_size_override("font_size", 30)
	narracao_label.add_theme_color_override("font_color", Color(0.78, 0.74, 0.68))
	narracao_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	narracao_label.add_theme_constant_override("shadow_offset_x", 2)
	narracao_label.add_theme_constant_override("shadow_offset_y", 2)
	narracao_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	narracao_label.visible = false
	add_child(narracao_label)


# ---------------------------------------------------------------
# FUNÇÕES PRINCIPAIS
# ---------------------------------------------------------------

## Fala de personagem, na caixa de baixo.
func falar(nome: String, texto: String, tempo_extra := 0.0) -> void:
	nome_label.text = nome
	nome_label.visible = nome != ""
	nome_label.add_theme_color_override("font_color", CORES.get(nome, Color(0.8, 0.8, 0.8)))
	texto_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.9))
	_tremer = false
	painel.visible = true
	narracao_label.visible = false
	await _mostrar(texto_label, texto, tempo_extra)
	painel.visible = false


## Voz do rádio: vermelha e tremendo.
func radio(texto: String, tempo_extra := 0.6) -> void:
	nome_label.text = "VOZ NO RÁDIO"
	nome_label.visible = true
	nome_label.add_theme_color_override("font_color", CORES["Rádio"])
	texto_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	painel.visible = true
	narracao_label.visible = false
	_painel_base = painel.position
	_tremer = true
	await _mostrar(texto_label, texto, tempo_extra)
	_tremer = false
	painel.position = _painel_base
	painel.visible = false


## Narração do protagonista adulto: texto no meio da tela, sem caixa.
func narrar(texto: String, tempo_extra := 0.8) -> void:
	painel.visible = false
	narracao_label.visible = true
	narracao_label.modulate.a = 1.0
	await _mostrar(narracao_label, texto, tempo_extra)
	var tw := create_tween()
	tw.tween_property(narracao_label, "modulate:a", 0.0, 0.5)
	await tw.finished
	narracao_label.visible = false


## Mensagem simples (examinar objetos no jogo). Igual a falar, sem nome.
func mensagem(texto: String) -> void:
	await falar("", texto)


func esta_ocupado() -> bool:
	return _digitando or _esperando


## Esconde tudo na hora (usado ao pular a cutscene).
func fechar() -> void:
	var estava_digitando := _digitando
	_digitando = false
	painel.visible = false
	narracao_label.visible = false
	if estava_digitando:
		_terminou_de_digitar.emit()
	if _esperando:
		avancou.emit()


# ---------------------------------------------------------------
# DIGITAÇÃO E AVANÇO
# ---------------------------------------------------------------
func _mostrar(label: Label, texto: String, tempo_extra: float) -> void:
	_label_atual = label
	label.text = texto
	label.visible_characters = 0
	_total_letras = texto.length()
	_tempo_letras = 0.0
	_digitando = true
	seta.visible = false
	await _terminou_de_digitar
	label.visible_characters = -1
	seta.visible = true
	# tempo de leitura: mais texto = mais tempo
	var tempo := 1.0 + _total_letras * 0.035 + tempo_extra
	_esperando = true
	_timer_leitura.start(tempo)
	await avancou
	_timer_leitura.stop()
	_esperando = false


func _avancar_automatico() -> void:
	if _esperando:
		avancou.emit()


func _process(delta: float) -> void:
	if _digitando and _label_atual:
		_tempo_letras += delta * VELOCIDADE_LETRAS
		_label_atual.visible_characters = int(_tempo_letras)
		if _tempo_letras >= _total_letras:
			_digitando = false
			_terminou_de_digitar.emit()
	if _tremer:
		# treme a caixa inteira (mexer só no texto bagunçava o VBoxContainer)
		painel.position = _painel_base + Vector2(randf_range(-3, 3), randf_range(-2, 2))
	if seta and seta.visible:
		seta.modulate.a = 0.4 + 0.6 * absf(sin(Time.get_ticks_msec() * 0.004))


## Chamado ao tocar na tela / apertar Espaço / botão do HUD.
func avancar() -> void:
	var agora := Time.get_ticks_msec()
	if agora - _ultimo_toque < 180:  # evita "toque duplo" sem querer
		return
	_ultimo_toque = agora
	if _digitando:
		_digitando = false  # mostra o texto inteiro de uma vez
		_terminou_de_digitar.emit()
	elif _esperando:
		avancou.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not esta_ocupado():
		return
	var tocou: bool = event is InputEventScreenTouch and event.pressed
	var tecla: bool = event.is_action_pressed("ui_accept") or event.is_action_pressed("interagir")
	if tocou or tecla:
		avancar()
		get_viewport().set_input_as_handled()
