class_name HudSobrevivencia
extends CanvasLayer
## INTERFACE DA PARTE 2
##  - barras Vida / Fome / Energia / Mente (estresse), com botão STATUS para esconder/mostrar
##  - relógio (Dia N · 21:40) e aviso quando a noite chega
##  - botões: MOCHILA, CRIAR, ATACAR, LUZ, CORRER (segure)
##  - painel da MOCHILA (grade 4x3) e painel de CRIAÇÃO (receitas)
##  - menu de escolha (ex.: no carro: VASCULHAR / FARÓIS / ESCONDER...)
##  - efeito de visão com estresse (bordas escuras + vultos)
## Tudo em 1280x720, com botões grandes para o dedo.

signal usar_slot(i: int)
signal largar_slot(i: int)
signal organizar
signal criar_receita(r: Dictionary)
signal escolheu(opcao: String)
signal botao_atacar
signal botao_luz
signal botao_mochila_aberta(aberta: bool)
signal barras_alternadas(visivel: bool)
signal peixe_mordeu

const COR_TEXTO := Color(0.9, 0.86, 0.78)
const CORES_BARRA := {"Vida": Color("c94a44"), "Fome": Color("d9a04a"), "Energia": Color("6aaa6a"), "Mente": Color("9a6ad0")}
const NOMES_BARRAS := ["Vida", "Fome", "Energia", "Mente"]

var barras := {}
var painel_barras: PanelContainer
var botao_status: Button
var alertas: HBoxContainer
var _alertas_chave := ""
var chips := {}
var relogio: Label
var aviso_noite: Label
var toast: Label
var vinheta: Control
var botao_correr: Button
var botao_luz_btn: Button
var botao_atacar_btn: Button
var mochila: PanelContainer
var criacao: PanelContainer
var escolha: PanelContainer
var _grade: GridContainer
var _detalhe: Label
var _slot_sel := -1
var _lista_receitas: VBoxContainer
var _info_bancada: Label
var _escolha_box: VBoxContainer
var _escolha_titulo: Label
var _estresse := 0.0
var _vultos_t := 0.0
var correr_pressionado := false

var inv: Inventario
var fonte_receitas: Callable   ## devolve [receitas liberadas, perto_bancada]


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_criar_vinheta()
	_criar_barras()
	_criar_relogio()
	_criar_botoes()
	_criar_mochila()
	_criar_criacao()
	_criar_escolha()
	_criar_pesca()
	_criar_toast()


# ---------------------------------------------------------------
# ESTILO
# ---------------------------------------------------------------
func _caixa(cor_fundo := Color(0, 0, 0, 0.6), borda := Color(0.35, 0.1, 0.1)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = cor_fundo
	s.border_color = borda
	s.set_border_width_all(2)
	s.set_corner_radius_all(8)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _botao(texto: String, tamanho := Vector2(150, 64), fonte := 22) -> Button:
	var b := Button.new()
	b.text = texto
	b.custom_minimum_size = tamanho
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", fonte)
	b.add_theme_color_override("font_color", COR_TEXTO)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.5))
	var n := _caixa(Color(0.06, 0.06, 0.06, 0.78), Color(0.45, 0.12, 0.12))
	n.content_margin_left = 6
	n.content_margin_right = 6
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(0.25, 0.06, 0.06, 0.9)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("disabled", n)
	return b


func _label(texto: String, tam := 20, cor := COR_TEXTO) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", cor)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------------------------------------------------------------
# BARRAS (com botão para esconder/mostrar)
# v8: tela mais limpa — saiu a SEDE, as barras ficam mais finas, o aviso
# "Normal" não aparece mais (só Atenção/Crítico) e tem o botão STATUS.
# Com as barras escondidas, aparece só um alerta pequeno quando algo está baixo.
# ---------------------------------------------------------------
func _criar_barras() -> void:
	botao_status = _botao("STATUS ▲", Vector2(150, 44), 18)
	botao_status.icon = Itens.icone("kit")
	botao_status.expand_icon = true
	botao_status.add_theme_constant_override("icon_max_width", 24)
	botao_status.position = Vector2(20, 14)
	botao_status.pressed.connect(func(): mostrar_barras(not painel_barras.visible))
	add_child(botao_status)

	# alertas que aparecem do lado do botão quando as barras estão escondidas
	alertas = HBoxContainer.new()
	alertas.position = Vector2(180, 22)
	alertas.add_theme_constant_override("separation", 6)
	alertas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(alertas)

	painel_barras = PanelContainer.new()
	painel_barras.position = Vector2(20, 64)
	var estilo := _caixa(Color(0, 0, 0, 0.45), Color(0.2, 0.2, 0.2, 0.5))
	estilo.content_margin_top = 8
	estilo.content_margin_bottom = 8
	painel_barras.add_theme_stylebox_override("panel", estilo)
	painel_barras.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(painel_barras)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	painel_barras.add_child(v)
	for nome in NOMES_BARRAS:
		var linha := HBoxContainer.new()
		linha.mouse_filter = Control.MOUSE_FILTER_IGNORE
		linha.add_theme_constant_override("separation", 8)
		var l := _label(nome, 16)
		l.custom_minimum_size = Vector2(66, 0)
		linha.add_child(l)
		var barra := ProgressBar.new()
		barra.custom_minimum_size = Vector2(140, 10)
		barra.show_percentage = false
		barra.max_value = 100
		barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
		barra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fundo := StyleBoxFlat.new()
		fundo.bg_color = Color(0.18, 0.18, 0.18)
		fundo.set_corner_radius_all(5)
		var cheio := StyleBoxFlat.new()
		cheio.bg_color = CORES_BARRA[nome]
		cheio.set_corner_radius_all(5)
		barra.add_theme_stylebox_override("background", fundo)
		barra.add_theme_stylebox_override("fill", cheio)
		linha.add_child(barra)
		var chip := _label("", 14)
		chip.custom_minimum_size = Vector2(60, 0)
		linha.add_child(chip)
		v.add_child(linha)
		barras[nome] = barra
		chips[nome] = chip
	mostrar_barras(GameData.hud_barras)


## Esconde/mostra as barras (e lembra a escolha para a próxima vez).
func mostrar_barras(sim: bool) -> void:
	painel_barras.visible = sim
	botao_status.text = "STATUS ▲" if sim else "STATUS ▼"
	alertas.visible = not sim
	if GameData.hud_barras != sim:
		GameData.hud_barras = sim
		GameData.salvar_config()
	barras_alternadas.emit(sim)


func atualizar_status(s: StatusJogador) -> void:
	var valores := {"Vida": s.vida, "Fome": s.fome, "Energia": s.energia, "Mente": 100.0 - s.estresse}
	var avisos: Array = []
	for nome in valores:
		barras[nome].value = valores[nome]
		var r := StatusJogador.rotulo(valores[nome])
		var novo := "" if r == "Normal" else r   # "Normal" não precisa aparecer
		if chips[nome].text != novo:   # v10: só mexe no tema quando muda (antes: 20x por segundo)
			chips[nome].text = novo
			chips[nome].add_theme_color_override("font_color", Color("e06060") if r == "Crítico" else Color("e0a050"))
		if r != "Normal":
			avisos.append([nome, r])
	_atualizar_alertas(avisos)
	var antes := _estresse
	_estresse = s.prejuizo_visao()
	if absf(antes - _estresse) > 0.005:
		vinheta.queue_redraw()


## Barras escondidas: mostra só o que está baixo, ex.: "■ Fome" piscando em vermelho.
func _atualizar_alertas(avisos: Array) -> void:
	var chave := str(avisos)
	if chave == _alertas_chave:
		return
	_alertas_chave = chave
	for c in alertas.get_children():
		c.queue_free()
	for a in avisos:
		var l := _label("■ " + a[0], 17, CORES_BARRA[a[0]].lightened(0.15))
		l.add_theme_color_override("font_shadow_color", Color.BLACK)
		if a[1] == "Crítico":
			l.text += "!"
		alertas.add_child(l)


# ---------------------------------------------------------------
# RELÓGIO E AVISOS
# ---------------------------------------------------------------
func _criar_relogio() -> void:
	relogio = _label("DIA 1 · 08:00", 26)
	relogio.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	relogio.offset_left = -200
	relogio.offset_right = 200
	relogio.offset_top = 14
	relogio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	relogio.add_theme_color_override("font_shadow_color", Color.BLACK)
	add_child(relogio)

	aviso_noite = _label("", 46, Color(0.85, 0.15, 0.15))
	aviso_noite.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	aviso_noite.offset_left = -500
	aviso_noite.offset_right = 500
	aviso_noite.offset_top = -160
	aviso_noite.offset_bottom = -80
	aviso_noite.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	aviso_noite.add_theme_color_override("font_shadow_color", Color.BLACK)
	aviso_noite.modulate.a = 0.0
	add_child(aviso_noite)


func atualizar_relogio(dia: int, hora_txt: String, fase: String) -> void:
	var nomes := {"dia": "", "entardecer": "  · ENTARDECER", "noite": "  · NOITE", "amanhecer": "  · AMANHECER"}
	relogio.text = "DIA %d · %s%s" % [dia, hora_txt, nomes.get(fase, "")]
	relogio.add_theme_color_override("font_color", Color(0.9, 0.4, 0.35) if fase == "noite" else COR_TEXTO)


func anunciar(texto: String, cor := Color(0.85, 0.15, 0.15)) -> void:
	aviso_noite.text = texto
	aviso_noite.add_theme_color_override("font_color", cor)
	var tw := create_tween()
	tw.tween_property(aviso_noite, "modulate:a", 1.0, 0.8)
	tw.tween_interval(2.5)
	tw.tween_property(aviso_noite, "modulate:a", 0.0, 1.2)


func _criar_toast() -> void:
	toast = _label("", 24)
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toast.offset_left = -400
	toast.offset_right = 400
	toast.offset_top = -240
	toast.offset_bottom = -200
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_color_override("font_shadow_color", Color.BLACK)
	toast.add_theme_constant_override("shadow_offset_x", 2)
	toast.add_theme_constant_override("shadow_offset_y", 2)
	toast.modulate.a = 0.0
	add_child(toast)


## Mensagem rápida no meio da tela (ex.: "+2 Madeira").
func avisar(texto: String) -> void:
	toast.text = texto
	toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(toast, "modulate:a", 0.0, 0.6)


# ---------------------------------------------------------------
# BOTÕES DE AÇÃO
# ---------------------------------------------------------------
func _criar_botoes() -> void:
	var direita := VBoxContainer.new()
	direita.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	direita.offset_left = -190
	direita.offset_right = -24
	direita.offset_top = 100
	direita.add_theme_constant_override("separation", 10)
	add_child(direita)
	var b_moch := _botao("MOCHILA", Vector2(166, 58))
	_por_icone(b_moch, icone_botao("mochila"), false)
	b_moch.pressed.connect(func(): abrir_mochila(not mochila.visible))
	direita.add_child(b_moch)
	var b_criar := _botao("CRIAR", Vector2(166, 58))
	_por_icone(b_criar, icone_botao("criar"), false)
	b_criar.pressed.connect(func(): abrir_criacao(not criacao.visible))
	direita.add_child(b_criar)

	# coluna de baixo: ATACAR / LUZ / CORRER (o EXAMINAR fica no HUD da Parte 1)
	var baixo := HBoxContainer.new()
	baixo.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	baixo.offset_left = -580
	baixo.offset_right = -270
	baixo.offset_top = -160
	baixo.offset_bottom = -64
	baixo.add_theme_constant_override("separation", 10)
	add_child(baixo)
	botao_atacar_btn = _botao("ATACAR", Vector2(100, 96), 16)
	_por_icone(botao_atacar_btn, icone_botao("atacar"), true)
	botao_atacar_btn.pressed.connect(func(): botao_atacar.emit())
	baixo.add_child(botao_atacar_btn)
	botao_luz_btn = _botao("LUZ", Vector2(96, 96), 16)
	_por_icone(botao_luz_btn, icone_botao("luz"), true)
	botao_luz_btn.pressed.connect(func(): botao_luz.emit())
	baixo.add_child(botao_luz_btn)
	botao_correr = _botao("CORRER", Vector2(100, 96), 16)
	_por_icone(botao_correr, icone_botao("correr"), true)
	botao_correr.button_down.connect(func(): correr_pressionado = true)
	botao_correr.button_up.connect(func(): correr_pressionado = false)
	baixo.add_child(botao_correr)


## Coloca um ícone pixelado no botão. em_cima = ícone em cima e texto embaixo.
func _por_icone(b: Button, tex: Texture2D, em_cima: bool) -> void:
	b.icon = tex
	b.expand_icon = true
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.add_theme_constant_override("icon_max_width", 48 if em_cima else 36)
	b.add_theme_constant_override("h_separation", 8)
	if em_cima:
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP


## Troca o ícone do ATACAR para a arma que está na mão.
func atualizar_arma(id_arma: String) -> void:
	botao_atacar_btn.icon = Itens.icone(id_arma) if id_arma != "" else icone_botao("atacar")


static var _icones_botao := {}


## Ícones 16x16 dos botões (também esculpidos e iluminados).
static func icone_botao(nome: String) -> Texture2D:
	if _icones_botao.has(nome):
		return _icones_botao[nome]
	var t: Texture2D
	match nome:
		"luz":
			t = Itens.icone("lanterna")
		"atacar":
			var r := Relevo.new(16, 16)
			r.material("pele", [Color("3a2418"), Color("6a4430"), Color("9a6a4a"), Color("c8946a"), Color("ecc29a")], false, 0.2)
			r.bola(Vector2(8, 9), Vector2(5, 4.5), 4, 0, "pele")          # punho fechado
			for k in 4:
				r.bola(Vector2(4.5 + k * 2.4, 5.5), Vector2(1.5, 1.6), 1.5, 3, "pele")
			r.bola(Vector2(3.5, 10), Vector2(1.6, 2.4), 1.5, 3, "pele")   # dedão
			t = r.textura()
		"correr":
			var r := Relevo.new(16, 16)
			r.material("bota", [Color("120c08"), Color("2a1c12"), Color("4a3220"), Color("6e4c32"), Color("94704c")], false, 0.3)
			r.material("sola", [Color("101012"), Color("1e1e22"), Color("2e2e34"), Color("44444c"), Color("5c5c66")])
			r.material("vento", [Color("cfe6ff")], true)
			r.caixa(Rect2(5, 2, 5, 9), 3, 0, "bota")
			r.bola(Vector2(10, 11), Vector2(4.5, 2.6), 3, 0, "bota")
			r.caixa(Rect2(4, 12.5, 11, 2), 1.5, 0, "sola")
			for y in [4, 7, 10]:
				for x in range(0, 3):
					r.pintar(Vector2(x, y), "vento", 0.1)
			t = r.textura()
		"mochila":
			var r := Relevo.new(16, 16)
			r.material("lona", [Color("10180e"), Color("22321c"), Color("3a5030"), Color("566e44"), Color("7a9060")], false, 0.1)
			r.material("couro", [Color("1e120a"), Color("3e2816"), Color("5e3e22"), Color("80583a"), Color("a67a52")])
			r.curva(Vector2(5, 4), Vector2(8, -0.5), Vector2(11, 4), 0.9, 0.9, 0, "couro", 5)
			r.caixa(Rect2(2.5, 3.5, 11, 11.5), 4, 0, "lona", 3)
			r.caixa(Rect2(4.5, 9, 7, 5), 2, 3.5, "lona", 1.5)
			r.caixa(Rect2(2.5, 6, 11, 2), 1, 4, "couro")
			t = r.textura()
		"criar":
			var r := Relevo.new(16, 16)
			r.material("cabo", Itens.C_MADEIRA, false, 0.2)
			r.material("ferro", Itens.C_METAL, false, 0.9)
			r.tubo(Vector2(3, 14), Vector2(10, 5), 1.2, 1.2, 0, "cabo")
			r.caixa(Rect2(6.5, 1.5, 8, 4.5), 3, 0.5, "ferro", 1.5)
			t = r.textura()
		_:
			t = Itens.icone(nome)
	_icones_botao[nome] = t
	return t


func atualizar_luz(texto: String) -> void:
	botao_luz_btn.text = texto


# ---------------------------------------------------------------
# MOCHILA
# ---------------------------------------------------------------
func _criar_mochila() -> void:
	mochila = PanelContainer.new()
	mochila.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	mochila.offset_left = -330
	mochila.offset_right = 330
	mochila.offset_top = -250
	mochila.offset_bottom = 250
	mochila.add_theme_stylebox_override("panel", _caixa(Color(0.04, 0.04, 0.05, 0.95)))
	mochila.visible = false
	add_child(mochila)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	mochila.add_child(v)
	v.add_child(_label("MOCHILA", 28, Color(0.8, 0.2, 0.2)))
	_grade = GridContainer.new()
	_grade.columns = 4
	_grade.add_theme_constant_override("h_separation", 10)
	_grade.add_theme_constant_override("v_separation", 10)
	v.add_child(_grade)
	for i in Inventario.ESPACOS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(140, 84)
		b.focus_mode = Control.FOCUS_NONE
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_constant_override("icon_max_width", 48)
		b.add_theme_color_override("font_color", COR_TEXTO)
		var n := _caixa(Color(0.12, 0.12, 0.12, 1.0), Color(0.3, 0.3, 0.3))
		n.content_margin_left = 8
		b.add_theme_stylebox_override("normal", n)
		var sel := n.duplicate() as StyleBoxFlat
		sel.border_color = Color(0.9, 0.3, 0.2)
		sel.set_border_width_all(3)
		b.add_theme_stylebox_override("hover", n)
		b.add_theme_stylebox_override("pressed", sel)
		b.toggle_mode = true
		b.pressed.connect(_selecionar_slot.bind(i))
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_grade.add_child(b)
	_detalhe = _label("Toque em um item.", 18)
	_detalhe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detalhe.custom_minimum_size = Vector2(600, 50)
	v.add_child(_detalhe)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var b_usar := _botao("USAR", Vector2(140, 56))
	b_usar.pressed.connect(func():
		if _slot_sel >= 0:
			usar_slot.emit(_slot_sel))
	h.add_child(b_usar)
	var b_largar := _botao("LARGAR", Vector2(140, 56))
	b_largar.pressed.connect(func():
		if _slot_sel >= 0:
			largar_slot.emit(_slot_sel))
	h.add_child(b_largar)
	var b_org := _botao("ORGANIZAR", Vector2(160, 56), 20)
	b_org.pressed.connect(func(): organizar.emit())
	h.add_child(b_org)
	var b_fechar := _botao("FECHAR", Vector2(140, 56))
	b_fechar.pressed.connect(func(): abrir_mochila(false))
	h.add_child(b_fechar)


func abrir_mochila(sim: bool) -> void:
	if sim:
		abrir_criacao(false)
	mochila.visible = sim
	_slot_sel = -1
	atualizar_mochila()
	botao_mochila_aberta.emit(sim or criacao.visible)


func _selecionar_slot(i: int) -> void:
	_slot_sel = i
	atualizar_mochila()


func atualizar_mochila() -> void:
	if inv == null:
		return
	for i in Inventario.ESPACOS:
		var b: Button = _grade.get_child(i)
		var s: Dictionary = inv.slots[i]
		b.button_pressed = i == _slot_sel
		if s.is_empty():
			b.icon = null
			b.text = ""
		else:
			b.icon = Itens.icone(s["id"])
			b.text = "x%d" % s["qtd"]
	if _slot_sel >= 0 and not inv.slots[_slot_sel].is_empty():
		var id: String = inv.slots[_slot_sel]["id"]
		_detalhe.text = "%s — %s" % [Itens.nome(id), Itens.desc(id)]
	else:
		_detalhe.text = "Toque em um item. Espaços livres: %d de %d" % [inv.espacos_livres(), Inventario.ESPACOS]


# ---------------------------------------------------------------
# CRIAÇÃO
# v10 — menu refeito:
#  - antes a lista INTEIRA era apagada e recriada a cada item que entrava na
#    mochila (a rolagem pulava para o topo, os botões piscavam e dava para tocar
#    num botão que já tinha sido apagado). Agora cada receita tem a sua linha,
#    criada uma vez só, e só o texto/estado dela muda.
#  - abas: TUDO / MÃO / BANCADA / FOGO
#  - o que dá para criar aparece primeiro; o botão diz o que falta
#  - barra de progresso enquanto cria (e os botões ficam travados)
#  - dá para rolar a lista arrastando o dedo por cima dos botões
# ---------------------------------------------------------------
var _linhas_receita := {}       ## id -> {linha, t1, t2, botao, receita}
var _aba := "tudo"
var _abas := {}
var _criando := false
var _barra_criar: ProgressBar
var _rotulo_criar: Label
var _rolagem: ScrollContainer
var _vazio_lbl: Label


func _criar_criacao() -> void:
	criacao = PanelContainer.new()
	criacao.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	criacao.offset_left = -430
	criacao.offset_right = 430
	criacao.offset_top = -310
	criacao.offset_bottom = 310
	criacao.add_theme_stylebox_override("panel", _caixa(Color(0.04, 0.04, 0.05, 0.96)))
	criacao.visible = false
	add_child(criacao)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	criacao.add_child(v)
	var topo := HBoxContainer.new()
	topo.add_theme_constant_override("separation", 8)
	v.add_child(topo)
	topo.add_child(_label("CRIAR", 28, Color(0.8, 0.2, 0.2)))
	_info_bancada = _label("", 17)
	_info_bancada.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_bancada.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	topo.add_child(_info_bancada)
	var b_x := _botao("X", Vector2(54, 44), 22)
	b_x.pressed.connect(func(): abrir_criacao(false))
	topo.add_child(b_x)
	# abas
	var abas := HBoxContainer.new()
	abas.add_theme_constant_override("separation", 6)
	v.add_child(abas)
	for d in [["tudo", "TUDO"], ["mao", "NA MÃO"], ["bancada", "BANCADA"], ["fogo", "NO FOGO"]]:
		var b := _botao(d[1], Vector2(150, 46), 18)
		b.toggle_mode = true
		b.button_pressed = d[0] == _aba
		var sel := _caixa(Color(0.3, 0.07, 0.07, 0.95), Color(0.9, 0.3, 0.2))
		sel.content_margin_left = 6
		sel.content_margin_right = 6
		b.add_theme_stylebox_override("pressed", sel)
		b.pressed.connect(_escolher_aba.bind(d[0]))
		abas.add_child(b)
		_abas[d[0]] = b
	_rolagem = ScrollContainer.new()
	_rolagem.custom_minimum_size = Vector2(820, 410)
	_rolagem.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rolagem.scroll_deadzone = 12
	v.add_child(_rolagem)
	_lista_receitas = VBoxContainer.new()
	_lista_receitas.add_theme_constant_override("separation", 6)
	_lista_receitas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lista_receitas.mouse_filter = Control.MOUSE_FILTER_PASS
	_rolagem.add_child(_lista_receitas)
	_vazio_lbl = _label("Nada para criar aqui ainda.", 18, Color(0.6, 0.6, 0.6))
	_lista_receitas.add_child(_vazio_lbl)
	# barra de progresso (aparece enquanto cria)
	var baixo := HBoxContainer.new()
	baixo.add_theme_constant_override("separation", 10)
	v.add_child(baixo)
	_rotulo_criar = _label("", 18)
	_rotulo_criar.custom_minimum_size = Vector2(260, 0)
	baixo.add_child(_rotulo_criar)
	_barra_criar = ProgressBar.new()
	_barra_criar.show_percentage = false
	_barra_criar.custom_minimum_size = Vector2(300, 14)
	_barra_criar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_barra_criar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fundo := StyleBoxFlat.new()
	fundo.bg_color = Color(0.15, 0.15, 0.15)
	var cheio := StyleBoxFlat.new()
	cheio.bg_color = Color("c9a04a")
	_barra_criar.add_theme_stylebox_override("background", fundo)
	_barra_criar.add_theme_stylebox_override("fill", cheio)
	_barra_criar.visible = false
	baixo.add_child(_barra_criar)
	var b_fechar := _botao("FECHAR", Vector2(160, 50))
	b_fechar.pressed.connect(func(): abrir_criacao(false))
	baixo.add_child(b_fechar)


func _escolher_aba(aba: String) -> void:
	_aba = aba
	for k in _abas:
		_abas[k].set_pressed_no_signal(k == aba)
	_rolagem.scroll_vertical = 0
	atualizar_criacao()


func abrir_criacao(sim: bool) -> void:
	if sim:
		mochila.visible = false
	criacao.visible = sim
	if sim:
		atualizar_criacao()
	botao_mochila_aberta.emit(sim or mochila.visible)


## Cria (uma vez só) a linha de uma receita.
func _linha_receita(r: Dictionary) -> Dictionary:
	if _linhas_receita.has(r["id"]):
		return _linhas_receita[r["id"]]
	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 10)
	linha.mouse_filter = Control.MOUSE_FILTER_PASS
	var ic := TextureRect.new()
	ic.texture = Itens.icone(r["da"])
	ic.custom_minimum_size = Vector2(46, 46)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.mouse_filter = Control.MOUSE_FILTER_PASS
	linha.add_child(ic)
	var txt := VBoxContainer.new()
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.mouse_filter = Control.MOUSE_FILTER_PASS
	var onde := ""
	if r["bancada"]:
		onde = "  [bancada]"
	elif r.get("fogo", false):
		onde = "  [no fogo]"
	var t1 := _label("%s%s%s" % [Itens.nome(r["da"]), (" x%d" % r["qtd"]) if r["qtd"] > 1 else "", onde], 20)
	txt.add_child(t1)
	var t2 := RichTextLabel.new()
	t2.bbcode_enabled = true
	t2.fit_content = true
	t2.scroll_active = false
	t2.mouse_filter = Control.MOUSE_FILTER_PASS
	t2.custom_minimum_size = Vector2(420, 0)
	t2.add_theme_font_size_override("normal_font_size", 16)
	t2.add_theme_color_override("default_color", Color(0.7, 0.68, 0.6))
	txt.add_child(t2)
	linha.add_child(txt)
	var b := _botao("CRIAR", Vector2(170, 52), 18)
	b.mouse_filter = Control.MOUSE_FILTER_PASS   # deixa a lista rolar arrastando por cima
	b.pressed.connect(func():
		if not _criando and not b.disabled:
			criar_receita.emit(r))
	linha.add_child(b)
	_lista_receitas.add_child(linha)
	var d := {"linha": linha, "t2": t2, "botao": b, "receita": r}
	_linhas_receita[r["id"]] = d
	return d


func _aba_da_receita(r: Dictionary) -> String:
	if r["bancada"]:
		return "bancada"
	if r.get("fogo", false):
		return "fogo"
	return "mao"


func atualizar_criacao() -> void:
	if not criacao.visible or not fonte_receitas.is_valid():
		return
	var dados: Array = fonte_receitas.call()
	var receitas: Array = dados[0]
	var perto: bool = dados[1]
	var fogo: bool = dados[2] if dados.size() > 2 else false
	_info_bancada.text = ("Bancada: PERTO" if perto else "Bancada: longe") + ("  ·  Fogo: PERTO" if fogo else "  ·  Fogo: longe")
	var ids_visiveis := {}
	var podem: Array = []
	var nao_podem: Array = []
	for r in receitas:
		if _aba != "tudo" and _aba_da_receita(r) != _aba:
			continue
		ids_visiveis[r["id"]] = true
		var d := _linha_receita(r)
		var ok := Receitas.pode_criar(r, inv, perto, fogo)
		d["t2"].text = Receitas.texto_ingredientes_bb(r, inv)
		var b: Button = d["botao"]
		b.disabled = not ok or _criando
		b.text = "CRIAR" if ok else Receitas.motivo(r, inv, perto, fogo)
		(podem if ok else nao_podem).append(d)
	for id in _linhas_receita:
		_linhas_receita[id]["linha"].visible = ids_visiveis.has(id)
	# o que dá para criar vem primeiro (sem recriar nada: só muda a ordem)
	var pos := 1
	for d in podem + nao_podem:
		_lista_receitas.move_child(d["linha"], pos)
		pos += 1
	_vazio_lbl.visible = ids_visiveis.is_empty()


## Mostra a barra enchendo enquanto cria. Os botões ficam travados até acabar.
func mostrar_criando(nome: String, tempo: float) -> void:
	_criando = true
	_rotulo_criar.text = "Criando %s..." % nome
	_barra_criar.visible = true
	_barra_criar.value = 0
	var tw := create_tween()
	tw.tween_property(_barra_criar, "value", 100.0, maxf(tempo, 0.05))
	atualizar_criacao()


func terminou_criar(texto: String) -> void:
	_criando = false
	_barra_criar.visible = false
	_rotulo_criar.text = texto
	atualizar_criacao()


func painel_aberto() -> bool:
	return mochila.visible or criacao.visible or escolha.visible or pesca.visible


# ---------------------------------------------------------------
# PESCA (minijogo: espere morder e puxe na hora certa!)
# ---------------------------------------------------------------
var pesca: PanelContainer
var _pesca_lbl: Label
var _pesca_puxar: Button
var _pesca_clique := ""


func _criar_pesca() -> void:
	pesca = PanelContainer.new()
	pesca.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	pesca.offset_left = -300
	pesca.offset_right = 300
	pesca.offset_top = -250
	pesca.offset_bottom = -110
	pesca.add_theme_stylebox_override("panel", _caixa(Color(0.03, 0.05, 0.08, 0.92), Color(0.2, 0.35, 0.5)))
	pesca.visible = false
	add_child(pesca)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 8)
	pesca.add_child(v)
	_pesca_lbl = _label("", 24)
	_pesca_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_pesca_lbl)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 14)
	v.add_child(h)
	_pesca_puxar = _botao("PUXAR!", Vector2(220, 60), 24)
	_por_icone(_pesca_puxar, Itens.icone("vara_pescar"), false)
	_pesca_puxar.pressed.connect(func(): _pesca_clique = "puxar")
	h.add_child(_pesca_puxar)
	var b := _botao("RECOLHER", Vector2(180, 60), 20)
	b.pressed.connect(func(): _pesca_clique = "cancelar")
	h.add_child(b)


## Para o teclado (tecla E) e para os testes.
func puxar() -> void:
	_pesca_clique = "puxar"


## Devolve "pegou", "escapou" ou "cancelou".
##   espera = segundos até o peixe morder | janela = tempo para puxar
func pescar(espera: float, janela: float) -> String:
	pesca.visible = true
	botao_mochila_aberta.emit(true)
	_pesca_clique = ""
	_pesca_lbl.text = "Linha na água… espere o peixe morder."
	_pesca_lbl.add_theme_color_override("font_color", COR_TEXTO)
	var resultado := ""
	var inicio := Time.get_ticks_msec() / 1000.0
	while resultado == "":
		await get_tree().process_frame
		if not is_inside_tree():
			return "cancelou"
		var t := Time.get_ticks_msec() / 1000.0 - inicio
		var mordeu := t >= espera
		if mordeu and _pesca_lbl.text.begins_with("Linha"):
			peixe_mordeu.emit()
			_pesca_lbl.text = "PUXE AGORA!"
			_pesca_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		elif not mordeu:
			var p := int(t * 2.0) % 4
			_pesca_lbl.text = "Linha na água… espere o peixe morder" + ".".repeat(p)
		if _pesca_clique == "cancelar":
			resultado = "cancelou"
		elif _pesca_clique == "puxar":
			resultado = "pegou" if mordeu else "escapou"   # puxou antes da hora: assusta o peixe
		elif t > espera + janela:
			resultado = "escapou"
	pesca.visible = false
	botao_mochila_aberta.emit(painel_aberto())
	return resultado


# ---------------------------------------------------------------
# MENU DE ESCOLHA
# ---------------------------------------------------------------
func _criar_escolha() -> void:
	escolha = PanelContainer.new()
	escolha.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	escolha.offset_left = -220
	escolha.offset_right = 220
	escolha.offset_top = -200
	escolha.offset_bottom = 200
	escolha.add_theme_stylebox_override("panel", _caixa(Color(0.04, 0.04, 0.05, 0.95)))
	escolha.visible = false
	add_child(escolha)
	_escolha_box = VBoxContainer.new()
	_escolha_box.add_theme_constant_override("separation", 8)
	_escolha_box.alignment = BoxContainer.ALIGNMENT_CENTER
	escolha.add_child(_escolha_box)


## Mostra opções e espera o jogador escolher. Devolve o texto escolhido ("" = cancelou).
func escolher(titulo: String, opcoes: Array) -> String:
	for c in _escolha_box.get_children():
		c.queue_free()
	_escolha_titulo = _label(titulo, 24, Color(0.85, 0.3, 0.25))
	_escolha_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_escolha_box.add_child(_escolha_titulo)
	for o in opcoes + ["CANCELAR"]:
		var b := _botao(o, Vector2(380, 56), 20)
		b.pressed.connect(func(): escolheu.emit("" if o == "CANCELAR" else o))
		_escolha_box.add_child(b)
	escolha.visible = true
	botao_mochila_aberta.emit(true)
	var r: String = await escolheu
	escolha.visible = false
	botao_mochila_aberta.emit(painel_aberto())
	return r


# ---------------------------------------------------------------
# VISÃO COM ESTRESSE (vinheta + vultos)
# ---------------------------------------------------------------
func _criar_vinheta() -> void:
	vinheta = Control.new()
	vinheta.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vinheta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vinheta.draw.connect(_desenhar_vinheta)
	add_child(vinheta)


var _acum_vinheta := 0.0

func _process(delta: float) -> void:
	_vultos_t += delta
	# v10: os vultos piscam 10x por segundo (antes: redesenhava 60x por segundo)
	_acum_vinheta += delta
	if _estresse > 0.45 and _acum_vinheta >= 0.1:
		_acum_vinheta = 0.0
		vinheta.queue_redraw()


func _desenhar_vinheta() -> void:
	if _estresse <= 0.01:
		return
	var s := vinheta.size
	# bordas escuras em "degraus" (pixel), mais grossas com mais estresse
	for k in 6:
		var m := (k + 1) * 26.0 * _estresse
		var a := 0.16 * _estresse
		vinheta.draw_rect(Rect2(0, 0, s.x, m), Color(0, 0, 0, a))
		vinheta.draw_rect(Rect2(0, s.y - m, s.x, m), Color(0, 0, 0, a))
		vinheta.draw_rect(Rect2(0, 0, m, s.y), Color(0, 0, 0, a))
		vinheta.draw_rect(Rect2(s.x - m, 0, m, s.y), Color(0, 0, 0, a))
	# vultos rápidos nos cantos (alucinação) quando o estresse está muito alto
	if _estresse > 0.45 and fmod(_vultos_t, 4.0) < 0.25:
		var x := 40.0 if fmod(_vultos_t, 8.0) < 4.0 else s.x - 80.0
		vinheta.draw_rect(Rect2(x, s.y * 0.45, 30, 90), Color(0, 0, 0, 0.75))
		vinheta.draw_rect(Rect2(x + 8, s.y * 0.45 - 18, 14, 18), Color(0, 0, 0, 0.75))
