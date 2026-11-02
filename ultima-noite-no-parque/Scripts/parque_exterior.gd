class_name ParqueExterior
extends Node2D
## O lado de fora: estrada de terra, floresta, lago, a cabana, a fogueira e o portão.
## Desenhado por código + sprites (árvores, cabana). Usado na cutscene.

# Lugares importantes do mapa
const PONTOS := {
	"inicio_carro": Vector2(-1650, 0),
	"portao": Vector2(-1250, 0),
	"placa_parque": Vector2(-1480, -46),
	"placa_camping": Vector2(-760, -46),
	"placa_restrito": Vector2(-300, 46),
	"carro_para": Vector2(612, 0),
	"cabana": Vector2(760, -70),
	"porta_cabana": Vector2(760, -78),
	"frente_cabana": Vector2(760, -40),
	"janela_cabana": Vector2(722, -140),
	"fogueira": Vector2(905, 30),
	"lago": Vector2(1090, -300),
	"margem_lago": Vector2(1000, -165),
	"trilha_inicio": Vector2(790, -30),
	"trilha_fim": Vector2(1090, 270),
	"tecido": Vector2(1180, 330),
	"silhueta": Vector2(330, 0),
	"vista_portao": Vector2(-1110, 0),
}

const TRILHA := [Vector2(780, -40), Vector2(840, 40), Vector2(900, 120), Vector2(980, 190), Vector2(1060, 250), Vector2(1100, 280)]

var cabana: Sprite2D
var arvores: Node2D
var luz_fogueira: LuzFake           ## luz pixelada da fogueira
var fogo_particulas: CPUParticles2D  ## (não usado: o fogo é desenhado em pixel art)
var _luz_farol: LuzFake
var _luz_lua: LuzFake
var _luzes_janela: Array[LuzFake] = []
var _arvores_fundo: Array = []       ## árvores distantes (desenhadas no chão, bem leves)
var _enfeites: Array = []            ## flores, pedras, arbustos... [textura, posição, espelhar]
var portao_fechado := false:
	set(v):
		portao_fechado = v
		queue_redraw()
var fogueira_acesa := false:
	set(v):
		fogueira_acesa = v
		if luz_fogueira:
			luz_fogueira.visible = v
		queue_redraw()
var pegadas_visiveis := 0.0:  ## 0 = nenhuma, 1 = todas (vão sumindo no fim da trilha)
	set(v):
		pegadas_visiveis = v
		queue_redraw()
var tecido_visivel := false:
	set(v):
		tecido_visivel = v
		queue_redraw()
var lua_no_lago := false:
	set(v):
		lua_no_lago = v
		if _luz_lua:
			_luz_lua.visible = v
		queue_redraw()
var farois_acesos := false:
	set(v):
		farois_acesos = v
		_atualizar_farois()

var carro_node: Node2D = null
var _farol_node: Node2D = null      # cone visual auxiliar

var cortina_mexendo := false:
	set(v):
		cortina_mexendo = v
		if _cortina and is_instance_valid(_cortina):
			_cortina.queue_redraw()
## Cortina da janela da esquerda: fechada = tapa a visão e a luz de dentro.
var cortina_fechada := true:
	set(v):
		cortina_fechada = v
		if _cortina and is_instance_valid(_cortina):
			_cortina.queue_redraw()
		_atualizar_janela_esquerda()
var luz_dentro := false:  ## tem luz acesa dentro da cabana? (aparece pela janela aberta)
	set(v):
		luz_dentro = v
		_atualizar_janela_esquerda()

## PARTE 2 (v9): árvores dentro desta área viram sólidas (sprite + colisão no tronco)
## e os tocos/troncos/galhos/pedras do chão viram coisas que dá para PEGAR.
var limites_solidos := Rect2()
var agua: AguaLago
var troncos: Array = []                ## base de cada árvore sólida (colisão e luz)
var enfeites_coletaveis: Array = []    ## [tipo, posição] — o controlador cria os coletáveis
const ENFEITES_DE_PEGAR := ["toco", "tronco_caido", "galhos", "pedra_m"]

var _tempo := 0.0
var _obstaculos_cache: Array = []
var _nivel_luz := 0
var _acum_desenho := 0.0
var _cortina: Node2D = null


func _ready() -> void:
	y_sort_enabled = false
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	_preparar_floresta(rng)

	# O chão é desenhado UMA vez só (num nó separado), assim o celular não
	# precisa redesenhar centenas de formas a cada quadro.
	var chao := Node2D.new()
	chao.name = "Chao"
	chao.show_behind_parent = true
	chao.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	chao.draw.connect(_desenhar_chao.bind(chao))
	add_child(chao)

	# v9: a água do lago mexe (ondas, brilho, espuma, peixes pulando)
	agua = AguaLago.new()
	agua.name = "AguaLago"
	add_child(agua)

	arvores = Node2D.new()
	arvores.name = "Objetos"
	arvores.y_sort_enabled = true
	add_child(arvores)

	cabana = SpriteLibrary.criar_sprite("cabana", 0)
	cabana.position = PONTOS["cabana"]
	arvores.add_child(cabana)

	_plantar_arvores_perto(rng)
	if limites_solidos.has_area():
		_preparar_sobrevivencia()
	_criar_luzes()

	_cortina = Node2D.new()
	_cortina.name = "Cortina"
	_cortina.z_index = 5
	_cortina.draw.connect(_desenhar_cortina.bind(_cortina))
	add_child(_cortina)
	_cortina.queue_redraw()

	# Cone dos faróis: fica na camada de luz, com mistura aditiva (brilha no escuro)
	_farol_node = Node2D.new()
	_farol_node.name = "FarolCone"
	_farol_node.visible = false
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_farol_node.material = mat
	_farol_node.draw.connect(_desenhar_farois.bind(_farol_node))
	var camada := MundoPixel.camada_luz_atual()
	if camada:
		camada.add_child(_farol_node)
		tree_exiting.connect(_apagar_cone)
	else:
		add_child(_farol_node)


func _process(delta: float) -> void:
	_tempo += delta
	# OTIMIZAÇÃO: redesenha as partes animadas só 12x por segundo
	_acum_desenho += delta
	if _acum_desenho >= 1.0 / 12.0:
		_acum_desenho = 0.0
		queue_redraw()
		if _cortina:
			_cortina.queue_redraw()
		if farois_acesos:
			_atualizar_farois()


func ponto(nome: String) -> Vector2:
	return position + PONTOS[nome]


## Cabana com mais ou menos janelas acesas (0 = apagada, 3 = tudo aceso).
func luzes_cabana(nivel: int) -> void:
	cabana.texture = SpriteLibrary.quadro("cabana", nivel)
	# o sprite acende: janela da direita, depois a porta, depois a da esquerda
	_nivel_luz = nivel
	for k in _luzes_janela.size():
		_luzes_janela[k].visible = nivel > k
	_atualizar_janela_esquerda()


## A janela da esquerda é a que tem cortina: a luz de dentro só aparece se ela estiver aberta.
func _atualizar_janela_esquerda() -> void:
	if _luzes_janela.size() < 3:
		return
	var acesa := (_nivel_luz >= 3 or luz_dentro) and not cortina_fechada
	_luzes_janela[2].visible = acesa


# ---------------------------------------------------------------
# ÁRVORES
# ---------------------------------------------------------------
func _livre(p: Vector2) -> bool:
	if p.x < 640.0 and absf(p.y) < 90.0:
		return false  # estrada
	if p.distance_to(Vector2(760, -30)) < 230.0:
		return false  # clareira da cabana
	if p.distance_to(Vector2(905, 30)) < 90.0:
		return false  # fogueira
	var d := (p - Vector2(1090, -300)) / Vector2(300, 185)
	if d.length() < 1.0:
		return false  # lago
	for i in TRILHA.size() - 1:
		if Geometry2D.get_closest_point_to_segment(p, TRILHA[i], TRILHA[i + 1]).distance_to(p) < 34.0:
			return false  # trilha das pegadas
	for nome in ["placa_parque", "placa_camping", "placa_restrito"]:
		if p.distance_to(PONTOS[nome]) < 40.0:
			return false
	if p.distance_to(Vector2(1180, 330)) < 16.0:
		return false
	return true


## Lugares onde a câmera passa (estrada, cabana, lago, trilha): ali ficam as árvores
## "de verdade" (sprites que entram na frente/atrás dos personagens).
func _perto_da_acao(p: Vector2) -> bool:
	if absf(p.y) < 240.0 and p.x < 700.0:
		return true
	if p.distance_to(Vector2(860, -60)) < 520.0:
		return true
	if p.distance_to(Vector2(-400, 220)) < 200.0 or p.distance_to(Vector2(1180, 330)) < 160.0:
		return true
	return false


## Grade de vizinhos: true se já tem algo perto demais (e anota o ponto se estiver livre).
func _ocupado(grade: Dictionary, p: Vector2, dist: float) -> bool:
	var celula := Vector2i(floori(p.x / dist), floori(p.y / dist))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for q in grade.get(celula + Vector2i(dx, dy), []):
				if q.distance_squared_to(p) < dist * dist:
					return true
	if not grade.has(celula):
		grade[celula] = []
	grade[celula].append(p)
	return false


## Escolhe onde ficam as árvores do fundo e os enfeites do chão.
## OTIMIZAÇÃO: "grade de vizinhos" (só olha os quadradinhos ao lado),
## em vez de comparar cada árvore com todas as outras.
func _preparar_floresta(rng: RandomNumberGenerator) -> void:
	var grade := {}
	var meta := Otimizacao.qtd_arvores_fundo()
	var tentativas := 0
	while _arvores_fundo.size() < meta and tentativas < meta * 12:
		tentativas += 1
		var p := Vector2(rng.randf_range(-1950, 1950), rng.randf_range(-980, 980)).round()
		if not _livre(p) or _perto_da_acao(p) or _ocupado(grade, p, 40.0):
			continue
		_arvores_fundo.append([p, _sortear_arvore(rng), rng.randf() > 0.5, rng.randf_range(0.55, 0.8)])
	_arvores_fundo.sort_custom(func(a, b): return a[0].y < b[0].y)  # de trás para frente

	# Enfeites do chão: a maioria perto das áreas onde a câmera passa
	var tipos := ["tufo", "tufo", "tufo2", "flor_v", "flor_a", "flor_b", "pedra_p", "pedra_m", "arbusto",
		"arbusto2", "cogumelo", "samambaia", "galhos", "folhas", "toco", "tronco_caido"]
	var qtd := Otimizacao.qtd_enfeites()
	tentativas = 0
	while _enfeites.size() < qtd and tentativas < qtd * 8:
		tentativas += 1
		var p := Vector2(rng.randf_range(-1900, 1300), rng.randf_range(-700, 600)).round()
		if rng.randf() < 0.8 and not _perto_da_acao(p):
			continue
		var tipo: String = tipos[rng.randi_range(0, tipos.size() - 1)]
		var na_estrada := p.x < 640.0 and absf(p.y) < 38.0
		if na_estrada and tipo not in ["pedra_p", "folhas", "galhos"]:
			continue
		if ((p - Vector2(1090, -300)) / Vector2(290, 175)).length() < 1.0 or p.distance_to(Vector2(905, 30)) < 40.0:
			continue
		if absf(p.x - 760.0) < 90.0 and p.y > -120.0 and p.y < 30.0:
			continue  # na frente da porta da cabana fica limpo
		if absf(p.x - 612.0) < 60.0 and absf(p.y) < 50.0:
			continue  # onde o carro estaciona
		_enfeites.append([tipo, p, rng.randf() > 0.5])
	# taboas na margem e vitórias-régias no lago
	for k in Otimizacao.qtd_enfeites_lago():
		var a := rng.randf() * TAU
		var borda := Vector2(1090, -300) + Vector2(cos(a) * 262.0, sin(a) * 150.0)
		_enfeites.append(["taboa", borda.round(), rng.randf() > 0.5])
		if k % 2 == 0:
			var dentro := Vector2(1090, -300) + Vector2(cos(a) * rng.randf_range(120, 220), sin(a) * rng.randf_range(60, 120))
			_enfeites.append(["vitoria", dentro.round(), false])
	_enfeites.sort_custom(func(a, b): return a[1].y < b[1].y)


func _plantar_arvores_perto(rng: RandomNumberGenerator) -> void:
	var grade := {}
	var colocadas := 0
	var tentativas := 0
	var meta := Otimizacao.qtd_arvores()
	while colocadas < meta and tentativas < meta * 30:
		tentativas += 1
		var p := Vector2(rng.randf_range(-1900, 1500), rng.randf_range(-700, 650)).round()
		if not _livre(p) or not _perto_da_acao(p) or _ocupado(grade, p, 46.0):
			continue
		_nova_arvore(p, _sortear_arvore(rng), rng.randf() > 0.5, rng.randf_range(0.75, 1.0))
		colocadas += 1


## Mais pinheiros que árvores redondas; poucas árvores secas.
func _sortear_arvore(rng: RandomNumberGenerator) -> int:
	var n := rng.randf()
	if n < 0.32: return 0
	if n < 0.6: return 1
	if n < 0.78: return 2
	if n < 0.9: return 4
	return 3


func _nova_arvore(p: Vector2, variante: int, espelhar: bool, tom: float) -> Sprite2D:
	var arv := PixelArte.sprite_arvore(variante)
	if espelhar:  # espelha com escala negativa (o tronco fica no mesmo lugar)
		arv.scale.x = -1.0
	arv.position = p
	arv.modulate = Color(tom, tom * 1.03, tom)
	arvores.add_child(arv)
	troncos.append(p)
	return arv


## Parte 2: tudo que está dentro da área jogável fica "de verdade".
func _preparar_sobrevivencia() -> void:
	var area := limites_solidos.grow(70.0)
	var sobra: Array = []
	for a in _arvores_fundo:
		if area.has_point(a[0]):
			_nova_arvore(a[0], a[1], a[2], minf(a[3] + 0.2, 1.0))   # vira árvore sólida
		else:
			sobra.append(a)
	_arvores_fundo = sobra
	var enfeites: Array = []
	for e in _enfeites:
		if e[0] in ENFEITES_DE_PEGAR and limites_solidos.has_point(e[1]):
			enfeites_coletaveis.append([e[0], e[1]])
		else:
			enfeites.append(e)
	_enfeites = enfeites
	# A cabana passa a "contar" a partir da parede (y = -100), não do pé da escada.
	# Assim quem sobe a escada e fica na varanda aparece NA FRENTE da cabana.
	cabana.position.y = PONTOS["cabana"].y - 30.0
	cabana.offset.y += 30.0


func _criar_luzes() -> void:
	luz_fogueira = _nova_luz(PONTOS["fogueira"] + Vector2(0, -4), 80.0, Color(1.0, 0.55, 0.2, 0.45))
	luz_fogueira.tremer = 0.18
	luz_fogueira.visible = fogueira_acesa
	_luz_farol = _nova_luz(Vector2.ZERO, 34.0, Color(1.0, 0.92, 0.6, 0.3))
	_luz_farol.visible = false
	_luz_lua = _nova_luz(Vector2(1060, -330), 40.0, Color(0.6, 0.7, 1.0, 0.25))
	_luz_lua.visible = lua_no_lago
	# janelas da cabana (direita, porta, esquerda) — acendem com luzes_cabana()
	for d in [Vector2(37, -70), Vector2(0, -71), Vector2(-38, -70)]:
		var l := _nova_luz(PONTOS["cabana"] + d, 30.0, Color(1.0, 0.75, 0.35, 0.4))
		l.visible = false
		_luzes_janela.append(l)


func _nova_luz(pos: Vector2, raio: float, cor: Color) -> LuzFake:
	var l := LuzFake.new()
	l.position = pos
	l.raio = raio
	l.cor = cor
	add_child(l)
	return l


# ---------------------------------------------------------------
# DESENHO DO CHÃO, ESTRADA, LAGO, PLACAS, PORTÃO...
# ---------------------------------------------------------------
func _desenhar_chao(c: Node2D) -> void:
	var grama := PixelArte.textura("grama")
	var grama_seca := PixelArte.textura("grama_seca")
	var terra := PixelArte.textura("terra")
	# grama em todo o mapa (um único comando de desenho!)
	PixelArte.azulejo(c, Rect2(-2000, -1000, 4000, 2000), grama)
	# manchas mais escuras e mais secas (pixeladas)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in Otimizacao.qtd_manchas():
		var centro := Vector2(rng.randf_range(-1950, 1950), rng.randf_range(-980, 980))
		var r := Vector2(rng.randf_range(20, 70), rng.randf_range(12, 40))
		if rng.randf() < 0.5:
			PixelArte.elipse(c, centro, r, Color(0.75, 0.8, 0.72), grama)
		else:
			PixelArte.elipse(c, centro, r, Color.WHITE, grama_seca)
	# clareira da cabana: grama pisada/seca
	PixelArte.elipse(c, Vector2(760, -30), Vector2(215, 175), Color(0.9, 0.9, 0.85), grama_seca)
	PixelArte.elipse(c, Vector2(760, -30), Vector2(165, 130), Color.WHITE, grama_seca)
	# estrada de terra: azulejo + beiras irregulares + marcas de pneu
	PixelArte.azulejo(c, Rect2(-2000, -36, 2640, 72), terra)
	for x in range(-2000, 640, 4):
		var cima := int(2.0 + sin(x * 0.11) * 2.0 + sin(x * 0.037) * 2.0)
		var baixo := int(2.0 + sin(x * 0.09 + 2.0) * 2.0 + sin(x * 0.041) * 2.0)
		if cima > 0:
			PixelArte.azulejo(c, Rect2(x, -36, 4, cima), grama)  # grama invadindo a beira
		if baixo > 0:
			PixelArte.azulejo(c, Rect2(x, 36 - baixo, 4, baixo), grama)
		c.draw_rect(Rect2(x, -36 + maxi(cima, 0), 4, 1), Color(0.18, 0.13, 0.08))  # sombra da beira
	for y in [-14, -11, 10, 13]:  # trilhos dos pneus
		c.draw_rect(Rect2(-2000, y, 2640, 2), Color(0.22, 0.16, 0.10, 0.55))
	PixelArte.elipse(c, Vector2(640, 0), Vector2(46, 38), Color.WHITE, terra)
	# trilha das pegadas
	for i in TRILHA.size() - 1:
		PixelArte.trilha(c, TRILHA[i], TRILHA[i + 1], 9.0, Color(0.85, 0.8, 0.75), terra)
	# lago: lama na margem, água e um tom mais claro no meio
	PixelArte.elipse(c, Vector2(1090, -300), Vector2(276, 160), Color(0.65, 0.55, 0.45), terra)
	PixelArte.elipse(c, Vector2(1090, -300), Vector2(262, 150), Color.WHITE, PixelArte.textura("agua"))
	PixelArte.elipse(c, Vector2(1090, -306), Vector2(240, 132), Color(0.85, 0.9, 1.0), PixelArte.textura("agua"))
	# árvores do fundo (bem leves: desenhadas aqui, junto com o chão)
	var sombras := GameData.nivel_detalhe() >= 3
	for a in _arvores_fundo:
		var tex_arv := PixelArte.arvore(a[1])
		var tam := tex_arv.get_size()
		var base: Vector2 = a[0]
		var tom: float = a[3]
		if sombras:  # sombra projetada pela lua (só no detalhe ALTO)
			PixelArte.elipse(c, base + Vector2(14, 2), Vector2(22, 6), Color(0, 0, 0, 0.22))
		var reg := Rect2(Vector2.ZERO, tam)
		var destino := Rect2(base - Vector2(tam.x / 2.0, tam.y - 3.0), tam)
		if a[2]:  # espelhado
			destino = Rect2(destino.position + Vector2(destino.size.x, 0), Vector2(-destino.size.x, destino.size.y))
		c.draw_texture_rect_region(tex_arv, destino, reg, Color(tom, tom * 1.04, tom))
	# enfeites (flores, pedras, arbustos, cogumelos...)
	for e in _enfeites:
		var t := PixelArte.textura(e[0])
		var tam := t.get_size()
		var pos: Vector2 = (e[1] - Vector2(tam.x / 2.0, tam.y)).round()
		var destino := Rect2(pos, tam)
		if e[2]:
			destino = Rect2(pos + Vector2(tam.x, 0), Vector2(-tam.x, tam.y))
		c.draw_texture_rect(t, destino, false)
	# fogueira (pedras + lenha) e toras para sentar em volta
	var f: Vector2 = PONTOS["fogueira"]
	PixelArte.elipse(c, f, Vector2(13, 8), Color(0.1, 0.08, 0.06))
	var pedra := PixelArte.textura("pedra_p")
	for i in 9:
		var a := TAU * i / 9.0
		c.draw_texture_rect(pedra, Rect2((f + Vector2(cos(a) * 11.0, sin(a) * 7.0) - Vector2(3, 2)).round(), Vector2(6, 4)), false)
	c.draw_rect(Rect2(f + Vector2(-7, -1), Vector2(14, 2)), Color(0.35, 0.22, 0.10))
	c.draw_rect(Rect2(f + Vector2(-1, -5), Vector2(2, 10)), Color(0.30, 0.19, 0.09))
	var tora := PixelArte.textura("tronco_caido")
	for d in [Vector2(-38, -8), Vector2(34, -10), Vector2(-4, 26)]:
		c.draw_texture_rect(tora, Rect2((f + d - Vector2(13, 4)).round(), Vector2(26, 8)), false)
	# placas
	_placa(c, PONTOS["placa_parque"], "PARQUE ESTADUAL\nDA SERRA NEGRA", Color(0.20, 0.30, 0.18), true)
	_placa(c, PONTOS["placa_camping"], "ÁREA DE CAMPING\n2 KM", Color(0.40, 0.25, 0.15), false)
	_placa(c, PONTOS["placa_restrito"], "ACESSO RESTRITO\nAPÓS O PÔR DO SOL", Color(0.45, 0.12, 0.10), false)
	# arbustos escondendo a placa de acesso restrito
	var arbusto := PixelArte.textura("arbusto")
	for d in [Vector2(-28, 10), Vector2(22, 12), Vector2(-12, 16), Vector2(32, 4)]:
		c.draw_texture_rect(arbusto, Rect2((PONTOS["placa_restrito"] + d - Vector2(9, 13)).round(), Vector2(18, 13)), false)


func _draw() -> void:
	if lua_no_lago:
		PixelArte.elipse(self, Vector2(1060, -330), Vector2(24, 9 + roundi(sin(_tempo) * 1.5)), Color(0.75, 0.8, 0.9, 0.45))
		PixelArte.elipse(self, Vector2(1060, -330), Vector2(11, 4), Color(0.95, 0.95, 1.0, 0.7))
		for k in 5:  # reflexos tremendo na água
			var x := 1060 + roundi(sin(_tempo * 1.3 + k * 2.1) * 30.0)
			draw_rect(Rect2(x, -318 + k * 4, 6 + k % 3 * 2, 1), Color(0.8, 0.85, 1.0, 0.35))
	if pegadas_visiveis > 0.0:
		_desenhar_pegadas()
	var f: Vector2 = PONTOS["fogueira"]
	if fogueira_acesa:
		_desenhar_fogo(f)
	# portão
	_desenhar_portao()
	# pedaço de tecido preso no galho
	if tecido_visivel:
		var t: Vector2 = PONTOS["tecido"]
		draw_line(t + Vector2(-14, -10), t + Vector2(10, 4), Color(0.25, 0.16, 0.08), 2.5)
		var bal := sin(_tempo * 2.3) * 1.5
		draw_colored_polygon(PackedVector2Array([t, t + Vector2(5, 1), t + Vector2(4 + bal, 9), t + Vector2(-1 + bal, 7)]), Color(0.25, 0.35, 0.6))


## A cortina fica num nó por cima da cabana (senão a cabana cobriria o desenho).
func _desenhar_cortina(c: Node2D) -> void:
	# BUG ANTIGO: a cortina era desenhada num lugar que não batia com a janela do
	# sprite e só aparecia quando "mexia". Agora ela fica EXATAMENTE em cima da
	# janela da esquerda (medida pixel a pixel no sprite) e tem dois estados:
	#   fechada → pano cobrindo o vidro (bloqueia visão e luz)
	#   aberta  → pano preso nos cantos, dá para ver o vidro (e a luz de dentro)
	var r := Rect2(PONTOS["cabana"] + Vector2(-45, -77), Vector2(14, 15))
	var vidro := Color(0.95, 0.7, 0.3) if (luz_dentro or _nivel_luz >= 3) else Color(0.05, 0.07, 0.11)
	c.draw_rect(r, vidro)
	c.draw_rect(Rect2(r.position.x + 6, r.position.y, 2, r.size.y), Color("2a1b0e"))  # divisória
	c.draw_rect(Rect2(r.position.x, r.position.y + 7, r.size.x, 1), Color("2a1b0e"))
	var pano := Color(0.66, 0.6, 0.48)
	var dobra := Color(0.5, 0.45, 0.36)
	if cortina_fechada:
		var bal := roundi(sin(_tempo * 2.0) * 1.5) if cortina_mexendo else 0
		for k in 7:  # 7 faixas de pano (dobras)
			var x := r.position.x + k * 2
			var onda := (roundi(sin(_tempo * 2.6 + k * 0.9) * 1.2) if cortina_mexendo else 0)
			c.draw_rect(Rect2(x + (bal if k > 3 else 0), r.position.y, 2, r.size.y + onda), pano if k % 2 == 0 else dobra)
	else:
		var bal := roundi(sin(_tempo * 2.0) * 1.2) if cortina_mexendo else 0
		c.draw_rect(Rect2(r.position.x, r.position.y, 3 + bal, r.size.y), pano)
		c.draw_rect(Rect2(r.end.x - 3, r.position.y, 3, r.size.y), pano)
		c.draw_rect(Rect2(r.position.x + 1, r.position.y, 1, r.size.y), dobra)
	c.draw_rect(Rect2(r.position.x - 1, r.position.y - 1, r.size.x + 2, 1), Color("4a3018"))  # varão

func _desenhar_fogo(f: Vector2) -> void:
	var cores := [Color("7a1e08"), Color("c2410c"), Color("f08a1c"), Color("ffd35a"), Color("fff3b0")]
	for k in 5:
		var largura := 9 - k * 2
		var altura := 3 + k
		var balanco := roundi(sin(_tempo * (9.0 + k * 3.0) + k) * (1.5 - k * 0.2))
		var topo := -2 - k * 2 - roundi(absf(sin(_tempo * 7.0 + k)) * 2.0)
		draw_rect(Rect2(roundi(f.x - largura / 2.0) + balanco, f.y + topo - altura + 3, largura, altura), cores[k])
	# faíscas subindo
	for k in 3:
		var fase := fmod(_tempo * 0.9 + k * 0.33, 1.0)
		draw_rect(Rect2(roundi(f.x + sin(_tempo * 3.0 + k * 2.0) * 4.0), roundi(f.y - 10.0 - fase * 22.0), 1, 1), Color(1.0, 0.7, 0.2, 1.0 - fase))


func _elipse(c: CanvasItem, centro: Vector2, raio: Vector2, cor: Color) -> void:
	var pts := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		pts.append(centro + Vector2(cos(a) * raio.x, sin(a) * raio.y))
	c.draw_colored_polygon(pts, cor)


func _placa(c: CanvasItem, p: Vector2, texto: String, cor: Color, musgo: bool) -> void:
	p = p.round()
	c.draw_rect(Rect2(p + Vector2(-2, -4), Vector2(4, 18)), Color(0.25, 0.17, 0.10))
	c.draw_rect(Rect2(p + Vector2(-2, -4), Vector2(1, 18)), Color(0.35, 0.24, 0.14))
	var r := Rect2(p + Vector2(-34, -24), Vector2(68, 22))
	c.draw_rect(Rect2(r.position + Vector2(2, 2), r.size), Color(0, 0, 0, 0.35))  # sombra
	c.draw_rect(r, cor)
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), cor.lightened(0.2))
	c.draw_rect(r, Color(0.12, 0.08, 0.05), false, 1.0)
	if musgo:
		PixelArte.elipse(c, r.position + Vector2(6, 18), Vector2(6, 4), Color(0.18, 0.32, 0.12, 0.95))
		PixelArte.elipse(c, r.position + Vector2(60, 3), Vector2(5, 3), Color(0.18, 0.32, 0.12, 0.95))
	var fonte := ThemeDB.fallback_font
	var linhas := texto.split("\n")
	for i in linhas.size():
		c.draw_string(fonte, r.position + Vector2(0, 9 + i * 8), linhas[i], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 7, Color(0.92, 0.88, 0.75))


func _atualizar_farois() -> void:
	var c := carro_ref()
	if c == null or not is_instance_valid(c):
		if _luz_farol:
			_luz_farol.visible = false
		if _farol_node:
			_farol_node.visible = false
		return
	if _luz_farol:
		_luz_farol.position = c.position + Vector2(48, -6)
		_luz_farol.visible = farois_acesos
	if _farol_node and is_instance_valid(_farol_node):
		_farol_node.visible = farois_acesos
		_farol_node.queue_redraw()


func _apagar_cone() -> void:
	if is_instance_valid(_farol_node):
		_farol_node.queue_free()


func _desenhar_farois(n: Node2D) -> void:
	# BUG ANTIGO: o farol era um triângulo fixo que atravessava árvores.
	# Agora usa FarolCone: raios que param nos obstáculos + 3 faixas de intensidade.
	if not farois_acesos or carro_ref() == null:
		return
	var origem: Vector2 = carro_ref().global_position + Vector2(30, -9)
	var poli := FarolCone.poligono(origem, 0.0, 150.0, 0.4, obstaculos_luz())
	FarolCone.desenhar(n, origem, poli, Color(1.0, 0.92, 0.65), 0.9)


## Troncos das árvores e paredes da cabana: bloqueiam a luz dos faróis.
func obstaculos_luz() -> Array:
	if _obstaculos_cache.is_empty():
		# o tronco (e a parte de baixo da copa) bloqueiam a luz
		for p in troncos:
			_obstaculos_cache.append([p + Vector2(0, -4), 6.0])
		for a in _arvores_fundo:
			_obstaculos_cache.append([a[0] + Vector2(0, -4), 6.0])
		for k in 5:  # a cabana (5 círculos cobrindo a parede)
			_obstaculos_cache.append([PONTOS["cabana"] + Vector2(-56 + k * 28, -40), 22.0])
	return _obstaculos_cache

func carro_ref() -> Node2D:
	return carro_node


func _desenhar_portao() -> void:
	var g: Vector2 = PONTOS["portao"]
	# ===== Portão de madeira de parque (pixel) =====
	var madeira := Color(0.45, 0.30, 0.16)
	var madeira_esc := Color(0.28, 0.18, 0.10)
	var madeira_clara := Color(0.55, 0.40, 0.22)
	var ferro := Color(0.25, 0.25, 0.27)
	# Poste esquerdo (norte da estrada)
	draw_rect(Rect2(g + Vector2(-14, -62), Vector2(12, 28)), madeira)
	draw_rect(Rect2(g + Vector2(-14, -62), Vector2(12, 4)), madeira_esc)
	draw_rect(Rect2(g + Vector2(-12, -56), Vector2(3, 18)), madeira_esc)
	draw_rect(Rect2(g + Vector2(-6, -54), Vector2(3, 16)), madeira_clara)
	# Poste direito (sul)
	draw_rect(Rect2(g + Vector2(-14, 34), Vector2(12, 28)), madeira)
	draw_rect(Rect2(g + Vector2(-14, 58), Vector2(12, 4)), madeira_esc)
	draw_rect(Rect2(g + Vector2(-12, 36), Vector2(3, 18)), madeira_esc)
	draw_rect(Rect2(g + Vector2(-6, 38), Vector2(3, 16)), madeira_clara)
	# Travessa superior (placa do parque)
	draw_rect(Rect2(g + Vector2(-16, -68), Vector2(16, 6)), madeira_esc)
	draw_rect(Rect2(g + Vector2(-20, -74), Vector2(24, 8)), Color(0.22, 0.32, 0.18))
	draw_rect(Rect2(g + Vector2(-20, -74), Vector2(24, 8)), Color(0.10, 0.08, 0.05), false, 1.0)
	if portao_fechado:
		# Barreira de madeira fechada atravessando a estrada
		draw_rect(Rect2(g + Vector2(-8, -34), Vector2(8, 68)), madeira)
		for i in 6:
			var yy := -30.0 + i * 11.0
			draw_rect(Rect2(g + Vector2(-10, yy), Vector2(12, 3)), madeira_clara if i % 2 == 0 else madeira_esc)
		# Cadeado
		draw_rect(Rect2(g + Vector2(-6, -2), Vector2(8, 7)), Color(0.7, 0.6, 0.2))
		draw_arc(g + Vector2(-2, -4), 3.0, PI, TAU, 6, ferro, 1.5)
	else:
		# Aberto: barreiras recolhidas junto aos postes
		draw_rect(Rect2(g + Vector2(-30, -58), Vector2(20, 6)), madeira)
		draw_rect(Rect2(g + Vector2(-28, -56), Vector2(4, 4)), madeira_clara)
		draw_rect(Rect2(g + Vector2(-22, -56), Vector2(4, 4)), madeira_esc)
		draw_rect(Rect2(g + Vector2(-30, 52), Vector2(20, 6)), madeira)
		draw_rect(Rect2(g + Vector2(-28, 54), Vector2(4, 4)), madeira_clara)
		draw_rect(Rect2(g + Vector2(-22, 54), Vector2(4, 4)), madeira_esc)


func _desenhar_pegadas() -> void:
	var total := 22
	for i in total:
		var t := float(i) / (total - 1)
		var limite := pegadas_visiveis
		var alfa := clampf((1.0 - t) * 1.6, 0.0, 1.0) if t < limite else 0.0  # vão ficando rasas
		if alfa <= 0.0:
			continue
		var p := _ponto_na_trilha(t)
		var prox := _ponto_na_trilha(minf(t + 0.02, 1.0))
		var dirv := (prox - p).normalized()
		var lado := dirv.orthogonal() * (2.5 if i % 2 == 0 else -2.5)
		draw_set_transform(p + lado, dirv.angle() + PI / 2.0, Vector2(1.0, 1.7))
		draw_circle(Vector2.ZERO, 1.7, Color(0.08, 0.06, 0.04, alfa))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ponto_na_trilha(t: float) -> Vector2:
	var n := TRILHA.size() - 1
	var x := clampf(t, 0.0, 1.0) * n
	var i := mini(int(x), n - 1)
	return (TRILHA[i] as Vector2).lerp(TRILHA[i + 1], x - i)
