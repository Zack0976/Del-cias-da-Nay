class_name ObjetosV10
extends RefCounted
## =============================================================================
##  OBJETOS NOVOS DO MAPA (v10)
##  Tudo desenhado em pixel art por código, com UM desenho só (sem _process):
##  não pesa nada no celular.
##    Cartaz de DESAPARECIDO (4 no mapa)  → botão LER
##    Barco virado na margem do lago      → botão VASCULHAR (uma vez)
##    Covo (armadilha de peixe)           → pega peixe sozinho, botão COVO
## =============================================================================

## Textos dos cartazes. Pessoas que sumiram no parque ANTES de vocês chegarem.
## (Não muda a história: são pistas do que já acontecia lá.)
const CARTAZES := [
	{"nome": "HELENA DUARTE, 17", "ano": "1987", "cor": Color(0.55, 0.35, 0.3),
	"texto": ["DESAPARECIDA — Helena Duarte, 17 anos. Vista pela última vez na área de camping do Parque Serra Negra, em 1987.",
		"Alguém escreveu à caneta embaixo: \"ela disse que ouviu batidas na porta a noite toda\"."]},
	{"nome": "JOÃO E PEDRO ALVES", "ano": "1999", "cor": Color(0.35, 0.4, 0.55),
	"texto": ["DESAPARECIDOS — os irmãos João e Pedro Alves, 12 e 15 anos. Saíram para pescar no lago e não voltaram.",
		"Embaixo, quase apagado: \"não pesquem depois que escurece\"."]},
	{"nome": "SÉRGIO MOTA, 34", "ano": "2006", "cor": Color(0.45, 0.45, 0.35),
	"texto": ["DESAPARECIDO — Sérgio Mota, 34 anos, guarda-florestal do parque. Última ronda: 2006.",
		"No verso do cartaz, rabiscado: \"eles não gostam de luz. NUNCA deixe a fogueira apagar\"."]},
	{"nome": "CAROLINA LIMA, 19", "ano": "2014", "cor": Color(0.5, 0.3, 0.45),
	"texto": ["DESAPARECIDA — Carolina Lima, 19 anos. Acampava com amigos. Os amigos voltaram. Ela não.",
		"Tem um bilhete preso com fita: \"deixei mantimentos embaixo do barco virado, na beira do lago. Se você está lendo isso, ainda dá tempo.\""]},
]
## Onde ficam (lá fora, dentro da área jogável, longe das árvores-sprite da cabana)
const POS_CARTAZES := [Vector2(-520, -48), Vector2(905, -150), Vector2(1030, 110), Vector2(-1150, 52)]
const POS_BARCO := Vector2(868, -205)


static func criar_cartaz(i: int) -> Node2D:
	var n := Node2D.new()
	n.name = "Cartaz_%d" % i
	n.position = POS_CARTAZES[i]
	var d: Dictionary = CARTAZES[i]
	n.draw.connect(func():
		# poste de madeira
		n.draw_rect(Rect2(-1, -22, 3, 22), Color("4a3018"))
		n.draw_rect(Rect2(-1, -22, 1, 22), Color("5e3e22"))
		# papel (amarelado, meio rasgado)
		n.draw_rect(Rect2(-7, -24, 15, 17), Color(0, 0, 0, 0.35))
		n.draw_rect(Rect2(-8, -25, 15, 17), Color("d8d0b4"))
		n.draw_rect(Rect2(-8, -25, 15, 3), Color("a01c1c"))           # faixa "DESAPARECIDO"
		n.draw_rect(Rect2(-6, -21, 7, 7), d["cor"])                    # "foto"
		n.draw_rect(Rect2(-4, -20, 3, 3), d["cor"].lightened(0.35))    # rosto
		for y in [-20, -18, -16]:
			n.draw_rect(Rect2(2, y, 4, 1), Color("6a6658"))
		n.draw_rect(Rect2(-7, -12, 13, 1), Color("6a6658"))
		n.draw_rect(Rect2(-7, -10, 9, 1), Color("6a6658"))
		n.draw_rect(Rect2(5, -10, 2, 2), Color("bcb498"))              # canto rasgado
		n.draw_rect(Rect2(-1, -26, 2, 2), Color("8a8a92")))           # prego
	var it := Interagivel.criar("cartaz_%d" % i, Vector2(0, -4), 16.0, "LER")
	n.add_child(it)
	return n


static func criar_barco() -> Node2D:
	var n := Node2D.new()
	n.name = "BarcoVirado"
	n.position = POS_BARCO
	n.draw.connect(func():
		var casco := Color("3a4a52")
		var escuro := Color("232e34")
		n.draw_rect(Rect2(-17, -3, 36, 4), Color(0, 0, 0, 0.35))       # sombra
		n.draw_rect(Rect2(-16, -9, 32, 8), casco)
		n.draw_rect(Rect2(-14, -11, 28, 2), casco.lightened(0.15))
		n.draw_rect(Rect2(-18, -6, 2, 4), casco)
		n.draw_rect(Rect2(16, -6, 3, 4), casco)
		n.draw_rect(Rect2(-16, -2, 32, 1), escuro)
		for x in [-9, -1, 7]:
			n.draw_rect(Rect2(x, -9, 1, 7), escuro)                    # tábuas do casco
		n.draw_rect(Rect2(10, -8, 3, 2), Color("7a3a1c"))              # ferrugem
		n.draw_rect(Rect2(-22, -2, 9, 1), Color("6b4b2a"))             # remo no chão
		n.draw_rect(Rect2(-24, -3, 3, 3), Color("6b4b2a")))
	var it := Interagivel.criar("barco", Vector2(0, -4), 20.0, "VASCULHAR")
	n.add_child(it)
	var corpo := StaticBody2D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	var f := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(30, 5)
	f.shape = r
	f.position = Vector2(0, -4)
	corpo.add_child(f)
	n.add_child(corpo)
	return n


## Covo: cesto de varetas na beira da água. peixes = quantos já pegou (0 a 3).
static func criar_covo(i: int, pos: Vector2) -> Node2D:
	var n := Node2D.new()
	n.name = "Covo_%d" % i
	n.position = pos
	n.set_meta("peixes", 0)
	n.draw.connect(func():
		n.draw_rect(Rect2(-6, -6, 12, 6), Color("5c3e22"))
		for x in range(-5, 6, 2):
			n.draw_rect(Rect2(x, -6, 1, 6), Color("9a7a4a"))
		n.draw_rect(Rect2(-7, -4, 2, 2), Color("1a1410"))              # boca do covo
		n.draw_rect(Rect2(6, -9, 1, 9), Color("4a3018"))               # estaca
		var p: int = n.get_meta("peixes", 0)
		for k in p:                                                    # peixes aparecendo
			n.draw_rect(Rect2(-3 + k * 3, -4, 2, 1), Color("68a0b4")))
	var it := Interagivel.criar("covo_%d" % i, Vector2(0, -3), 16.0, "COVO")
	n.add_child(it)
	return n
