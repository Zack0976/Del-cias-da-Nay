class_name FarolCone
extends RefCounted
## CONE DE LUZ DO FAROL (com bloqueio por obstáculos)
##
## BUG ANTIGO: o farol era um triângulo fixo que atravessava árvores e a cabana.
## Agora a luz é calculada com "raios": saem vários raios da frente do carro,
## espalhados num leque. Cada raio PARA no primeiro obstáculo (árvore, cabana...).
## Juntando as pontas dos raios, temos o formato real da luz.
## E a luz fica mais fraca com a distância (3 faixas: perto forte, longe fraca).

const RAIOS := 18


## origem: ponto do farol | angulo: para onde aponta (radianos) | alcance: comprimento
## abertura: metade do ângulo do cone | obstaculos: lista de [centro: Vector2, raio: float]
static func poligono(origem: Vector2, angulo: float, alcance: float, abertura: float, obstaculos: Array) -> PackedVector2Array:
	var pts := PackedVector2Array([origem])
	for i in RAIOS + 1:
		var a := angulo - abertura + (abertura * 2.0) * i / RAIOS
		var dir := Vector2(cos(a), sin(a))
		var dist := alcance
		for o in obstaculos:
			var centro: Vector2 = o[0]
			if centro.distance_squared_to(origem) > (alcance + o[1]) * (alcance + o[1]):
				continue  # longe demais, nem testa (economiza contas)
			var t := _raio_circulo(origem, dir, centro, o[1])
			if t >= 0.0 and t < dist:
				dist = t
		pts.append((origem + dir * dist).round())
	return pts


## Distância até o raio bater no círculo (ou -1 se não bate).
static func _raio_circulo(o: Vector2, d: Vector2, c: Vector2, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var cc := oc.dot(oc) - r * r
	var h := b * b - cc
	if h < 0.0:
		return -1.0
	var t := -b - sqrt(h)
	return t if t >= 0.0 else (0.0 if cc < 0.0 else -1.0)


## Desenha o cone em 3 faixas (queda de intensidade com a distância).
## "c" deve ter material ADITIVO e estar na camada de luz.
static func desenhar(c: CanvasItem, origem: Vector2, poli: PackedVector2Array, cor: Color, intensidade := 1.0) -> void:
	if poli.size() < 3:
		return
	for faixa in [[1.0, 0.18], [0.66, 0.16], [0.36, 0.2]]:
		var escala: float = faixa[0]
		var pts := PackedVector2Array()
		for p in poli:
			pts.append((origem + (p - origem) * escala).round())
		var k: float = faixa[1] * intensidade
		c.draw_colored_polygon(pts, Color(cor.r * k, cor.g * k, cor.b * k, 1.0))
