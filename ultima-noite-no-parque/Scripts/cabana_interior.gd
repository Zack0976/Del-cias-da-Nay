class_name CabanaInterior
extends Node2D
## O interior da cabana, desenhado 100% por código.
## Usado na cutscene E no jogo (o mesmo cenário nos dois = a história bate certinho).
##
## O ponto (0, 0) é o canto de cima/esquerda do chão. O chão mede LARGURA x ALTURA.
## As paredes de cima aparecem "de frente" (visão top-down estilo RPG).

const LARGURA := 288.0
const ALTURA := 192.0
const PAREDE_CIMA := 30.0     ## altura da parede de cima (a que a gente vê de frente)
const PAREDE := 8.0           ## grossura das outras paredes
const PORTA_X := 132.0        ## onde começa a porta (na parede de baixo)
const PORTA_L := 24.0         ## largura da porta

# Cores
const C_CHAO := Color(0.30, 0.20, 0.12)
const C_CHAO_LINHA := Color(0.22, 0.14, 0.08)
const C_PAREDE := Color(0.36, 0.25, 0.16)
const C_PAREDE_ESCURA := Color(0.20, 0.13, 0.08)
const C_TOPO := Color(0.10, 0.07, 0.05)
const C_MADEIRA := Color(0.42, 0.28, 0.16)
const C_PEDRA := Color(0.32, 0.31, 0.30)

## Lugares importantes (para a cutscene saber onde colocar os personagens).
const PONTOS := {
	"spawn": Vector2(144, 150),
	"centro": Vector2(144, 140),
	"porta_dentro": Vector2(144, 178),
	"porta_fora": Vector2(144, 222),
	"cama_voce": Vector2(21, 52),
	"cama_lucas": Vector2(49, 52),
	"cama_marina": Vector2(239, 52),
	"cama_rafa": Vector2(267, 52),
	"deitado_voce": Vector2(21, 34),
	"deitado_lucas": Vector2(49, 34),
	"deitado_marina": Vector2(239, 34),
	"deitado_rafa": Vector2(267, 34),
	"mesa": Vector2(138, 124),
	"mesa_esq": Vector2(98, 98),
	"mesa_dir": Vector2(184, 98),
	"radio": Vector2(228, 130),
	"foto": Vector2(124, 92),
	"janela": Vector2(206, 14),
	"parede_msg": Vector2(118, 14),
	"lareira": Vector2(30, 104),
	"chao_porta": Vector2(150, 150),
}

# Estado visual (a cutscene e o jogo mudam isso)
var com_colisao := false
var porta_aberta := false:
	set(v):
		porta_aberta = v
		_atualizar_porta()
		_redesenhar_estatico()
var mensagem_visivel := false:
	set(v):
		mensagem_visivel = v
		if _msg_label:
			_msg_label.visible = v
var camas_baguncadas := false:
	set(v):
		camas_baguncadas = v
		_redesenhar_estatico()
var cama_lucas_vazia := true:
	set(v):
		cama_lucas_vazia = v
		_redesenhar_estatico()
var pegadas := false:
	set(v):
		pegadas = v
		_redesenhar_estatico()
var luz_acesa := true:
	set(v):
		luz_acesa = v
		if luz_teto:
			luz_teto.enabled = v
		_atualizar_glows_fake()
var lareira_acesa := false:
	set(v):
		lareira_acesa = v
		if luz_lareira:
			luz_lareira.enabled = v
		_atualizar_glows_fake()
		_redesenhar_estatico()
var cortina_tempo := 0.0
## PARTE 2: cortina da janela de cima. Fechada = tapa o vidro (não entra luz da lua,
## não sai luz de dentro e o Observador não consegue espiar).
var cortina_fechada := false:
	set(v):
		cortina_fechada = v
		_atualizar_glows_fake()
		queue_redraw()
## PARTE 2: janela pequena na parede da direita (mais um ponto fraco da casa).
var janela_direita := false:
	set(v):
		janela_direita = v
		_redesenhar_estatico()
var _acum_desenho := 0.0
var macaneta_tremendo := false  ## a maçaneta girando sozinha (cena 5)

var luz_teto: PointLight2D
var luz_lareira: PointLight2D
var luz_janela: PointLight2D
var radio_sprite: Sprite2D
var lanterna_sprite: Sprite2D
var objetos: Node2D  ## nó com y-sort onde ficam personagens e objetos altos
var _msg_label: Label
var _bloqueio_porta: StaticBody2D
var _textura_luz: Texture2D
var _glows: Array[Node2D] = []
var _estatico: Node2D


func _ready() -> void:
	_textura_luz = Player.criar_textura_luz()
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_criar_estatico()
	objetos = Node2D.new()
	objetos.name = "Objetos"
	objetos.y_sort_enabled = true
	add_child(objetos)

	_criar_mensagem_parede()
	_criar_objetos_com_sprite()
	_criar_luzes()
	if com_colisao:
		_criar_colisoes()
	_atualizar_porta()


func _process(delta: float) -> void:
	cortina_tempo += delta
	if lareira_acesa and luz_lareira:
		luz_lareira.energy = 0.9 + sin(cortina_tempo * 13.0) * 0.08 + randf() * 0.12
	# OTIMIZAÇÃO: só a cortina e o fogo mexem, então redesenhamos 12x por segundo
	# (e não 60x). Em pixel art ninguém percebe a diferença, e o celular agradece.
	_acum_desenho += delta
	if _acum_desenho >= 1.0 / 12.0:
		_acum_desenho = 0.0
		queue_redraw()


func ponto(nome: String) -> Vector2:
	return position + PONTOS[nome]


# ---------------------------------------------------------------
# DESENHO
# OTIMIZAÇÃO: o que não se mexe (chão, paredes, móveis) fica num nó "estático"
# que só é redesenhado quando algo muda (porta abre, cama bagunça...).
# A cada quadro só redesenhamos a cortina, o fogo e a maçaneta.
# ---------------------------------------------------------------
func _criar_estatico() -> void:
	_estatico = Node2D.new()
	_estatico.name = "Estatico"
	_estatico.show_behind_parent = true
	_estatico.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_estatico.draw.connect(_desenhar_estatico.bind(_estatico))
	add_child(_estatico)
	move_child(_estatico, 0)


func _redesenhar_estatico() -> void:
	if _estatico:
		_estatico.queue_redraw()
	queue_redraw()


func _desenhar_estatico(c: Node2D) -> void:
	_desenhar_chao(c)
	_desenhar_paredes(c)
	_desenhar_moveis(c)
	if pegadas:
		_desenhar_pegadas(c)


## Partes animadas (redesenhadas 12x por segundo).
func _draw() -> void:
	# cortina balançando na janela (sem vento...)
	var jx := 192.0
	var balanco := roundi(sin(cortina_tempo * 1.7) * 2.0 + sin(cortina_tempo * 3.1))
	if cortina_fechada:
		# FECHADA: 9 faixas de pano cobrindo o vidro inteiro (bloqueia luz e visão)
		for k in 9:
			var onda := roundi(sin(cortina_tempo * 1.3 + k * 0.7) * 0.6)
			draw_rect(Rect2(jx + 1 + k * 3, -23, 3 if k < 8 else 2, 17 + onda), Color(0.62, 0.58, 0.48).darkened((k % 2) * 0.12))
	else:
		# ABERTA: o pano fica preso no canto esquerdo, balançando um pouco
		for k in 3:
			var onda := roundi(sin(cortina_tempo * 2.4 + k) * 1.5)
			draw_rect(Rect2(jx + 2 + k * 3 + (balanco if k > 0 else 0), -22, 3, 14 + (onda if k == 2 else 0)), Color(0.62, 0.58, 0.48).darkened(k * 0.08))
	draw_rect(Rect2(jx - 1, -26, 30, 1), Color("4a3018"))  # varão da cortina
	# fogo da lareira
	if lareira_acesa:
		var cores := [Color("7a1e08"), Color("c2410c"), Color("f08a1c"), Color("ffd35a")]
		for k in 4:
			var bal := roundi(sin(cortina_tempo * (9.0 + k * 2.5)) * 1.2)
			draw_rect(Rect2(7 - k + bal + k, 112 - k * 3 - roundi(absf(sin(cortina_tempo * 7.0 + k)) * 2.0), 10 - k * 2, 3 + k), cores[k])
	else:
		draw_rect(Rect2(9, 112, 1, 1), Color(0.8, 0.25, 0.05) if fmod(cortina_tempo, 2.0) < 1.4 else Color(0.4, 0.12, 0.03))
	# maçaneta (treme na cena 5)
	if not porta_aberta:
		var treme := Vector2(randi_range(-1, 1), 0) if macaneta_tremendo else Vector2.ZERO
		draw_rect(Rect2(Vector2(PORTA_X + PORTA_L - 5, ALTURA + 1) + treme, Vector2(2, 2)), Color(0.75, 0.65, 0.3))


func _desenhar_chao(c: Node2D) -> void:
	PixelArte.azulejo(c, Rect2(0, 0, LARGURA, ALTURA), PixelArte.textura("piso"))
	# tapete embaixo da mesa (com franja)
	var tap := Rect2(92, 70, 92, 58)
	PixelArte.azulejo(c, tap, PixelArte.textura("tapete"))
	c.draw_rect(tap, Color("8a6a2a"), false, 1.0)
	for x in range(int(tap.position.x) + 1, int(tap.end.x), 3):
		c.draw_rect(Rect2(x, tap.position.y - 2, 1, 2), Color("b8a070"))
		c.draw_rect(Rect2(x, tap.end.y, 1, 2), Color("b8a070"))
	# sujeira e manchas no chão
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for k in 26 + GameData.nivel_detalhe() * 10:
		c.draw_rect(Rect2(rng.randi_range(4, 280), rng.randi_range(6, 186), rng.randi_range(1, 3), 1), Color(0, 0, 0, 0.18))
	# sombra perto das paredes (dá profundidade)
	c.draw_rect(Rect2(0, 0, LARGURA, 4), Color(0, 0, 0, 0.45))
	c.draw_rect(Rect2(0, 4, LARGURA, 3), Color(0, 0, 0, 0.2))
	c.draw_rect(Rect2(0, 0, 3, ALTURA), Color(0, 0, 0, 0.3))
	c.draw_rect(Rect2(LARGURA - 3, 0, 3, ALTURA), Color(0, 0, 0, 0.3))


func _desenhar_paredes(c: Node2D) -> void:
	# parede de cima (de frente), feita de troncos
	PixelArte.azulejo(c, Rect2(0, -PAREDE_CIMA, LARGURA, PAREDE_CIMA), PixelArte.textura("parede"))
	c.draw_rect(Rect2(0, -2, LARGURA, 2), Color(0.12, 0.08, 0.05))  # rodapé
	# prateleira com potes e livros
	c.draw_rect(Rect2(14, -20, 40, 2), Color("5c3e22"))
	for k in 6:
		var cor: Color = [Color("6b2a1f"), Color("2f4a5e"), Color("7a6a3a"), Color("4a5a2a"), Color("5a3a5a"), Color("8a8070")][k]
		c.draw_rect(Rect2(16 + k * 6, -27 + (k % 2), 4, 7 - (k % 2)), cor)
	# quadro torto (cabeça de cervo desenhada)
	c.draw_rect(Rect2(246, -26, 22, 16), Color("3a2614"))
	c.draw_rect(Rect2(248, -24, 18, 12), Color("4f5a4a"))
	c.draw_rect(Rect2(255, -21, 4, 6), Color("2a2018"))
	c.draw_rect(Rect2(252, -24, 1, 3), Color("2a2018"))
	c.draw_rect(Rect2(261, -24, 1, 3), Color("2a2018"))
	# relógio parado
	PixelArte.circulo(c, Vector2(176, -16), 5, Color("5c3e22"))
	PixelArte.circulo(c, Vector2(176, -16), 4, Color("c8c0a8"))
	c.draw_rect(Rect2(176, -19, 1, 3), Color.BLACK)
	c.draw_rect(Rect2(176, -16, 2, 1), Color.BLACK)
	# janela
	var jx := 192.0
	c.draw_rect(Rect2(jx - 1, -25, 30, 20), Color("2a1b0e"))
	c.draw_rect(Rect2(jx + 1, -23, 26, 16), Color(0.06, 0.08, 0.14))
	for k in 6:  # estrelas / céu lá fora
		c.draw_rect(Rect2(jx + 3 + k * 4, -21 + (k * 7) % 9, 1, 1), Color(0.5, 0.55, 0.7))
	c.draw_rect(Rect2(jx + 13, -23, 2, 16), Color("5c3e22"))
	c.draw_rect(Rect2(jx + 1, -16, 26, 1), Color("5c3e22"))
	c.draw_rect(Rect2(jx - 2, -6, 32, 2), Color("6b4b2a"))  # parapeito
	# topo das paredes (a "grossura" vista de cima)
	var topo := Color("120c08")
	c.draw_rect(Rect2(-PAREDE, -PAREDE_CIMA - PAREDE, LARGURA + PAREDE * 2, PAREDE), topo)
	c.draw_rect(Rect2(-PAREDE, -PAREDE_CIMA, PAREDE, ALTURA + PAREDE_CIMA + PAREDE), topo)
	c.draw_rect(Rect2(LARGURA, -PAREDE_CIMA, PAREDE, ALTURA + PAREDE_CIMA + PAREDE), topo)
	c.draw_rect(Rect2(-PAREDE, ALTURA, PORTA_X + PAREDE, PAREDE), topo)
	c.draw_rect(Rect2(PORTA_X + PORTA_L, ALTURA, LARGURA - PORTA_X - PORTA_L + PAREDE, PAREDE), topo)
	for x in range(-8, int(LARGURA) + 8, 12):  # pontas dos troncos no topo
		c.draw_rect(Rect2(x, -PAREDE_CIMA - PAREDE + 2, 2, 4), Color("2a1b0e"))
	# janela pequena da parede direita (Parte 2)
	if janela_direita:
		c.draw_rect(Rect2(LARGURA, 88, PAREDE, 24), Color("2a1b0e"))
		c.draw_rect(Rect2(LARGURA + 2, 90, PAREDE - 4, 20), Color(0.06, 0.08, 0.14))
		c.draw_rect(Rect2(LARGURA + 2, 99, PAREDE - 4, 1), Color("5c3e22"))
		c.draw_rect(Rect2(LARGURA - 2, 88, 2, 24), Color("6b4b2a"))  # parapeito
	# porta
	if porta_aberta:
		c.draw_rect(Rect2(PORTA_X, ALTURA, PORTA_L, PAREDE), Color(0.02, 0.02, 0.03))
		c.draw_rect(Rect2(PORTA_X - 4, ALTURA - 22, 4, 24), C_MADEIRA)  # porta encostada na parede
		c.draw_rect(Rect2(PORTA_X - 4, ALTURA - 22, 1, 24), Color("2a1b0e"))
	else:
		c.draw_rect(Rect2(PORTA_X, ALTURA - 2, PORTA_L, PAREDE + 2), C_MADEIRA)
		for k in 3:
			c.draw_rect(Rect2(PORTA_X + 1 + k * 8, ALTURA - 2, 1, PAREDE + 2), Color("3a2614"))
		c.draw_rect(Rect2(PORTA_X, ALTURA - 2, PORTA_L, PAREDE + 2), C_PAREDE_ESCURA, false, 1.0)


func _cama(c: Node2D, r: Rect2, cor: Color, vazia: bool) -> void:
	c.draw_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(0, 0, 0, 0.4))  # sombra
	c.draw_rect(r, C_MADEIRA)
	c.draw_rect(r, C_PAREDE_ESCURA, false, 1.0)
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), Color(0.5, 0.35, 0.2))  # cabeceira
	var colchao := r.grow(-2)
	c.draw_rect(colchao, Color(0.78, 0.74, 0.66))
	var trav := Rect2(colchao.position + Vector2(2, 2), Vector2(colchao.size.x - 4, 8))
	c.draw_rect(trav, Color(0.92, 0.90, 0.84))
	c.draw_rect(Rect2(trav.position + Vector2(0, trav.size.y - 1), Vector2(trav.size.x, 1)), Color(0.7, 0.68, 0.6))
	var cob: Rect2
	if camas_baguncadas and vazia:
		# coberta jogada torta, caindo para fora da cama
		c.draw_colored_polygon(PackedVector2Array([
			(colchao.position + Vector2(-3, 16)).round(), (colchao.position + Vector2(colchao.size.x + 2, 20)).round(),
			(colchao.position + Vector2(colchao.size.x, colchao.size.y + 3)).round(), (colchao.position + Vector2(2, colchao.size.y - 4)).round()
		]), cor)
		cob = Rect2(colchao.position + Vector2(0, 18), Vector2(colchao.size.x, colchao.size.y - 22))
	else:
		cob = Rect2(colchao.position + Vector2(0, 14), Vector2(colchao.size.x, colchao.size.y - 14))
		c.draw_rect(cob, cor)
		c.draw_rect(Rect2(cob.position, Vector2(cob.size.x, 2)), cor.lightened(0.18))  # dobra
	# costura de colcha (xadrez pixelado)
	for y in range(int(cob.position.y) + 3, int(cob.end.y), 4):
		for x in range(int(cob.position.x) + 1 + (y % 8) / 4 * 2, int(cob.end.x), 4):
			c.draw_rect(Rect2(x, y, 1, 1), cor.darkened(0.25))


func _desenhar_moveis(c: Node2D) -> void:
	# camas (quem tem cama: Você, Lucas, Marina, Rafa) + baús aos pés
	_cama(c, Rect2(10, 4, 22, 40), Color(0.45, 0.12, 0.12), true)
	_cama(c, Rect2(38, 4, 22, 40), Color(0.20, 0.30, 0.50), cama_lucas_vazia)
	_cama(c, Rect2(228, 4, 22, 40), Color(0.35, 0.28, 0.45), true)
	_cama(c, Rect2(256, 4, 22, 40), Color(0.20, 0.35, 0.20), true)
	# mochilas no chão
	c.draw_rect(Rect2(12, 48, 8, 7), Color("4a3a2a"))
	c.draw_rect(Rect2(13, 47, 6, 2), Color("5a4a36"))
	c.draw_rect(Rect2(233, 48, 8, 7), Color("2f3a4a"))
	# violão do Rafa encostado
	PixelArte.circulo(c, Vector2(281, 58), 4.5, Color(0.55, 0.30, 0.12))
	PixelArte.circulo(c, Vector2(281, 52), 3.5, Color(0.55, 0.30, 0.12))
	PixelArte.circulo(c, Vector2(281, 56), 1, Color(0.1, 0.06, 0.03))
	c.draw_rect(Rect2(280, 40, 2, 9), Color(0.3, 0.18, 0.08))
	c.draw_rect(Rect2(283, 50, 1, 6), Color(0.7, 0.7, 0.6))  # corda arrebentada

	# lareira de pedra (parede da esquerda)
	PixelArte.azulejo(c, Rect2(0, 84, 22, 44), PixelArte.textura("pedra"))
	c.draw_rect(Rect2(0, 84, 22, 44), Color(0.15, 0.15, 0.15), false, 1.0)
	c.draw_rect(Rect2(4, 92, 14, 26), Color(0.05, 0.04, 0.04))  # boca
	c.draw_rect(Rect2(4, 92, 14, 3), Color(0.12, 0.10, 0.09))
	c.draw_rect(Rect2(6, 113, 10, 2), Color(0.30, 0.18, 0.08))  # lenha
	c.draw_rect(Rect2(8, 111, 6, 2), Color(0.25, 0.15, 0.07))
	c.draw_rect(Rect2(5, 116, 12, 2), Color(0.16, 0.14, 0.13))  # cinzas
	c.draw_rect(Rect2(22, 120, 3, 8), Color("3a3a3a"))  # atiçador

	# mesa (com tampo de madeira) + cadeiras
	c.draw_rect(Rect2(112, 83, 58, 32), Color(0, 0, 0, 0.35))
	PixelArte.azulejo(c, Rect2(110, 80, 58, 32), PixelArte.textura("piso"), Color(1.15, 1.1, 1.05))
	c.draw_rect(Rect2(110, 80, 58, 32), Color(0.20, 0.12, 0.06), false, 1.0)
	c.draw_rect(Rect2(110, 80, 58, 1), Color(0.6, 0.42, 0.24))
	for x in [100, 170]:
		c.draw_rect(Rect2(x, 90, 8, 10), Color(0.35, 0.22, 0.12))
		c.draw_rect(Rect2(x, 90, 8, 2), Color(0.45, 0.30, 0.16))
	# fotografia antiga
	c.draw_rect(Rect2(118, 86, 12, 9), Color(0.85, 0.80, 0.68))
	c.draw_rect(Rect2(119, 87, 10, 7), Color(0.55, 0.50, 0.42))
	for i in 4:
		c.draw_rect(Rect2(120 + i * 2, 89, 1, 3), Color(0.25, 0.22, 0.2))
	# telefone fixo sem fio
	c.draw_rect(Rect2(150, 86, 10, 7), Color(0.12, 0.12, 0.12))
	c.draw_rect(Rect2(151, 85, 8, 3), Color(0.2, 0.2, 0.2))
	c.draw_rect(Rect2(152, 89, 1, 1), Color(0.6, 0.1, 0.1))
	# vela derretida e caneca
	c.draw_rect(Rect2(138, 92, 3, 5), Color("d8d0b8"))
	c.draw_rect(Rect2(137, 96, 5, 1), Color("c8c0a8"))
	c.draw_rect(Rect2(160, 100, 4, 4), Color("5a6a7a"))

	# criado-mudo do rádio
	c.draw_rect(Rect2(218, 116, 26, 16), Color(0, 0, 0, 0.35))
	c.draw_rect(Rect2(216, 114, 26, 16), C_MADEIRA)
	c.draw_rect(Rect2(216, 114, 26, 1), Color(0.55, 0.38, 0.2))
	c.draw_rect(Rect2(216, 114, 26, 16), Color(0.25, 0.16, 0.08), false, 1.0)
	c.draw_rect(Rect2(227, 123, 4, 1), Color(0.7, 0.6, 0.3))  # puxador

	# cozinha (balcão embaixo/esquerda)
	c.draw_rect(Rect2(8, 157, 58, 22), Color(0, 0, 0, 0.35))
	PixelArte.azulejo(c, Rect2(6, 154, 58, 22), PixelArte.textura("piso"), Color(0.9, 0.85, 0.8))
	c.draw_rect(Rect2(6, 154, 58, 22), Color(0.20, 0.12, 0.06), false, 1.0)
	c.draw_rect(Rect2(10, 158, 16, 12), Color(0.45, 0.46, 0.5))   # pia
	c.draw_rect(Rect2(11, 159, 14, 10), Color(0.3, 0.32, 0.36))
	c.draw_rect(Rect2(17, 157, 2, 3), Color(0.7, 0.7, 0.72))       # torneira
	PixelArte.circulo(c, Vector2(44, 165), 4, Color(0.12, 0.12, 0.12))  # fogareiro
	PixelArte.circulo(c, Vector2(56, 165), 3, Color(0.12, 0.12, 0.12))
	PixelArte.circulo(c, Vector2(44, 165), 2, Color(0.25, 0.25, 0.25))
	for k in 3:  # pratos sujos
		c.draw_rect(Rect2(28 + k * 2, 158 + k, 5, 2), Color(0.8, 0.78, 0.7))
	# lenha empilhada perto da porta
	for k in 4:
		c.draw_rect(Rect2(100 + (k % 2) * 3, 178 - k * 3, 14, 3), Color(0.38, 0.24, 0.12) if k % 2 else Color(0.32, 0.2, 0.1))
		c.draw_rect(Rect2(113 + (k % 2) * 3, 178 - k * 3, 2, 3), Color("7c5a34"))


func _desenhar_pegadas(c: Node2D) -> void:
	# pegadas de terra molhada saindo da cama do Lucas até a porta
	var a := Vector2(49, 50)
	var b := Vector2(PORTA_X + PORTA_L / 2.0, ALTURA + 4)
	var passos := 14
	var perp := (b - a).orthogonal().normalized()
	for i in passos:
		var p := a.lerp(b, float(i) / (passos - 1)) + perp * (2.5 if i % 2 == 0 else -2.5)
		c.draw_rect(Rect2(p.round() - Vector2(1, 2), Vector2(3, 4)), Color(0.12, 0.08, 0.05, 0.85))
		c.draw_rect(Rect2(p.round() + Vector2(-1, 2), Vector2(2, 1)), Color(0.12, 0.08, 0.05, 0.6))


# ---------------------------------------------------------------
# OBJETOS, LUZES, COLISÕES
# ---------------------------------------------------------------
func _criar_mensagem_parede() -> void:
	_msg_label = Label.new()
	_msg_label.text = "ELES JÁ ESTÃO DENTRO"
	_msg_label.add_theme_font_size_override("font_size", 9)
	_msg_label.add_theme_color_override("font_color", Color(0.06, 0.05, 0.05))
	_msg_label.position = Vector2(66, -23)
	_msg_label.rotation = deg_to_rad(-3.0)
	_msg_label.visible = mensagem_visivel
	add_child(_msg_label)


func _criar_objetos_com_sprite() -> void:
	radio_sprite = SpriteLibrary.criar_sprite("radio", 0)
	radio_sprite.position = Vector2(229, 122)
	objetos.add_child(radio_sprite)

	lanterna_sprite = SpriteLibrary.criar_sprite("lanterna", 0)
	lanterna_sprite.position = Vector2(162, 98)
	lanterna_sprite.visible = false
	objetos.add_child(lanterna_sprite)


func radio_ligado(ligado: bool) -> void:
	radio_sprite.texture = SpriteLibrary.quadro("radio", 1 if ligado else 0)


func _criar_luzes() -> void:
	# Mobile: só glows fake no interior (PointLight guardado pro farol/fogueira)
	if not GameData.permite_luzes() or GameData.eh_mobile:
		luz_teto = null
		luz_lareira = null
		luz_janela = null
		_criar_glows_fake()
		return
	luz_teto = _luz(Vector2(144, 80), Color(1.0, 0.82, 0.55), 0.85, 2.6)
	luz_teto.enabled = luz_acesa
	luz_lareira = _luz(Vector2(16, 104), Color(1.0, 0.5, 0.2), 1.0, 1.2)
	luz_lareira.enabled = lareira_acesa
	luz_janela = _luz(Vector2(206, 4), Color(0.5, 0.6, 1.0), 0.45, 0.8)


func _criar_glows_fake() -> void:
	# Brilhos mais fortes pra a cabana não ficar preta
	_add_glow(Vector2(144, 90), 90.0, Color(1.0, 0.85, 0.5, 0.35), "teto")
	_add_glow(Vector2(22, 100), 50.0, Color(1.0, 0.5, 0.18, 0.4), "lareira")
	_add_glow(Vector2(206, 20), 36.0, Color(0.6, 0.7, 1.0, 0.25), "janela")
	_atualizar_glows_fake()


func _add_glow(pos: Vector2, raio: float, cor: Color, nome: String) -> void:
	var g := LuzFake.new()
	g.name = "Glow_" + nome
	g.position = pos
	g.raio = raio
	g.cor = cor
	g.energia = 1.0
	if nome == "lareira":
		g.tremer = 0.18  # fogo tremendo
	add_child(g)
	_glows.append(g)


func _atualizar_glows_fake() -> void:
	if _glows.is_empty():
		return
	for g in _glows:
		if g == null or not is_instance_valid(g):
			continue
		match g.name:
			"Glow_teto":
				g.visible = luz_acesa
				g.energia = 1.0 if luz_acesa else 0.0
			"Glow_lareira":
				g.visible = lareira_acesa
				g.energia = 1.0 if lareira_acesa else 0.0
			"Glow_janela":
				g.visible = not cortina_fechada   # cortina fechada: a luz da lua não entra
				g.energia = 0.7
		g.queue_redraw()


func _luz(pos: Vector2, cor: Color, energia: float, tamanho: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = _textura_luz
	l.position = pos
	l.color = cor
	l.energy = energia
	l.texture_scale = tamanho
	add_child(l)
	return l


func _criar_colisoes() -> void:
	var corpo := StaticBody2D.new()
	corpo.name = "Paredes"
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	add_child(corpo)
	# paredes
	_ret(corpo, Rect2(-PAREDE, -PAREDE_CIMA - PAREDE, LARGURA + PAREDE * 2, PAREDE_CIMA + PAREDE + 2))
	_ret(corpo, Rect2(-PAREDE - 8, -PAREDE_CIMA, PAREDE + 8, ALTURA + PAREDE_CIMA + PAREDE))
	_ret(corpo, Rect2(LARGURA, -PAREDE_CIMA, PAREDE + 8, ALTURA + PAREDE_CIMA + PAREDE))
	_ret(corpo, Rect2(-PAREDE, ALTURA, PORTA_X + PAREDE, PAREDE + 8))
	_ret(corpo, Rect2(PORTA_X + PORTA_L, ALTURA, LARGURA - PORTA_X - PORTA_L + PAREDE, PAREDE + 8))
	# móveis
	for r in [Rect2(10, 4, 22, 38), Rect2(38, 4, 22, 38), Rect2(228, 4, 22, 38), Rect2(256, 4, 22, 38),
			Rect2(0, 84, 20, 40), Rect2(110, 80, 58, 28), Rect2(216, 112, 26, 14), Rect2(6, 154, 58, 18),
			Rect2(276, 40, 10, 20)]:
		_ret(corpo, r)
	# porta trancada
	_bloqueio_porta = StaticBody2D.new()
	_bloqueio_porta.name = "Porta"
	_bloqueio_porta.collision_layer = 1
	_bloqueio_porta.collision_mask = 0
	add_child(_bloqueio_porta)
	_ret(_bloqueio_porta, Rect2(PORTA_X, ALTURA - 2, PORTA_L, PAREDE + 10))


func _ret(corpo: StaticBody2D, r: Rect2) -> void:
	var forma := CollisionShape2D.new()
	var ret := RectangleShape2D.new()
	ret.size = r.size
	forma.shape = ret
	forma.position = r.get_center()
	corpo.add_child(forma)


func _atualizar_porta() -> void:
	if _bloqueio_porta:
		_bloqueio_porta.process_mode = Node.PROCESS_MODE_DISABLED if porta_aberta else Node.PROCESS_MODE_INHERIT
		for c in _bloqueio_porta.get_children():
			(c as CollisionShape2D).set_deferred("disabled", porta_aberta)
