class_name AguaLago
extends Node2D
## ÁGUA DO LAGO COM MOVIMENTO (v9)
## O fundo do lago continua desenhado uma vez só (no chão). Este nó desenha
## por cima só o que MEXE, 10 vezes por segundo (leve no celular):
##   - ondinhas: tracinhos claros que vão e voltam com o vento
##   - brilhos que deslizam na água
##   - espuma na margem, batendo em ondas
##   - círculos de peixes pulando (e de onde o monstro do lago passa!)
## Tudo com retângulos de 1 pixel: continua pixel art.

const CENTRO := Vector2(1090, -300)
const RAIO := Vector2(258, 146)

var tempo := 0.0
var _acum := 0.0
var _rng := RandomNumberGenerator.new()
var _circulos: Array = []    ## [posição, idade, tamanho]
var _t_peixe := 1.0
var _linhas: Array = []      ## ondinhas pré-calculadas: [y, x_base, largura, fase, velocidade]
var boia := Vector2.INF       ## onde está a boia da vara de pescar (INF = sem boia)
var boia_mordeu := false      ## o peixe mordeu: a boia afunda!
## v10: vagalumes piscando em cima da água à noite (só pontinhos: quase de graça)
var vagalumes := false
var _vagalumes: Array = []    ## [posição base, fase, velocidade]


func _ready() -> void:
	_rng.seed = 404
	for k in 18:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(0.75, 1.15)
		_vagalumes.append([CENTRO + Vector2(cos(a) * RAIO.x * d, sin(a) * RAIO.y * d), _rng.randf() * TAU, _rng.randf_range(0.6, 1.3)])
	z_index = -4   # v10: abaixo das sombras
	for k in 70:
		var y := _rng.randf_range(-RAIO.y + 6, RAIO.y - 6)
		var meia := RAIO.x * sqrt(maxf(0.0, 1.0 - pow(y / RAIO.y, 2.0))) - 10.0
		if meia < 12.0:
			continue
		_linhas.append([CENTRO.y + y, CENTRO.x + _rng.randf_range(-meia, meia), _rng.randi_range(3, 8), _rng.randf() * TAU, _rng.randf_range(0.6, 1.4), meia])


func _process(delta: float) -> void:
	tempo += delta
	# v10 OTIMIZAÇÃO: com o lago fora da tela, não calcula nem redesenha nada
	var cam := get_viewport().get_camera_2d()
	if cam and cam.get_screen_center_position().distance_squared_to(CENTRO) > 560.0 * 560.0:
		return
	_acum += delta
	_t_peixe -= delta
	if _t_peixe <= 0.0:
		_t_peixe = _rng.randf_range(1.5, 4.0)
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(0.1, 0.8)
		respingo(CENTRO + Vector2(cos(a) * RAIO.x * d, sin(a) * RAIO.y * d), 1.0)
	for c in _circulos:
		c[1] += delta
	_circulos = _circulos.filter(func(c): return c[1] < 2.0)
	if _acum >= 0.1:
		_acum = 0.0
		queue_redraw()


## Faz um círculo na água (peixe, pedra, monstro...). tamanho 1 = normal.
func respingo(pos: Vector2, tamanho := 1.0) -> void:
	_circulos.append([pos, 0.0, tamanho])


func dentro(p: Vector2, folga := 0.0) -> bool:
	return ((p - CENTRO) / (RAIO - Vector2(folga, folga))).length() < 1.0


func _draw() -> void:
	# 1) ondinhas que balançam de um lado para o outro
	for l in _linhas:
		var desloc := sin(tempo * l[4] + l[3]) * 6.0
		var x: float = clampf(l[1] + desloc, CENTRO.x - l[5], CENTRO.x + l[5] - l[2])
		var brilho := 0.10 + 0.08 * sin(tempo * 2.0 + l[3])
		draw_rect(Rect2(roundi(x), roundi(l[0]), l[2], 1), Color(0.55, 0.7, 0.85, brilho))
		draw_rect(Rect2(roundi(x) + 1, roundi(l[0]) + 1, l[2] - 2, 1), Color(0.02, 0.05, 0.08, 0.25))
	# 2) brilhos deslizando (como a luz da lua mexendo)
	for k in 9:
		var t := fmod(tempo * 0.05 + k * 0.111, 1.0)
		var p := CENTRO + Vector2(lerpf(-0.8, 0.8, t) * RAIO.x, sin(k * 1.7) * RAIO.y * 0.6)
		if dentro(p, 8.0):
			var a := sin(t * PI) * 0.35
			draw_rect(Rect2(roundi(p.x), roundi(p.y), 2, 1), Color(0.85, 0.92, 1.0, a))
	# 3) espuma batendo na margem (uma onda que dá a volta no lago)
	for k in 72:
		var ang := TAU * k / 72.0
		var onda := sin(ang * 6.0 - tempo * 2.2)
		if onda < 0.3:
			continue
		var p := CENTRO + Vector2(cos(ang) * (RAIO.x - 2 - onda * 2.0), sin(ang) * (RAIO.y - 2 - onda * 1.5))
		draw_rect(Rect2(roundi(p.x), roundi(p.y), 2, 1), Color(0.75, 0.85, 0.9, 0.18 + onda * 0.22))
	# 4) boia da vara de pescar (balança; quando o peixe morde, AFUNDA)
	if boia != Vector2.INF:
		var y := roundi(sin(tempo * 3.0) * 0.8)
		if boia_mordeu:
			y = 2 + roundi(absf(sin(tempo * 18.0)) * 1.5)
		draw_rect(Rect2(roundi(boia.x) - 1, roundi(boia.y) - 3 + y, 3, 2), Color(0.95, 0.95, 0.9))
		if not boia_mordeu or y < 3:
			draw_rect(Rect2(roundi(boia.x) - 1, roundi(boia.y) - 1 + y, 3, 2), Color(0.85, 0.15, 0.1))
		draw_rect(Rect2(roundi(boia.x) - 3, roundi(boia.y) + 1, 7, 1), Color(0.8, 0.9, 1.0, 0.35))
	# 6) vagalumes na beira (v10)
	if vagalumes:
		for v in _vagalumes:
			var pisca := sin(tempo * 2.3 * v[2] + v[1])
			if pisca < 0.2:
				continue
			var p: Vector2 = v[0] + Vector2(sin(tempo * 0.5 * v[2] + v[1]) * 10.0, cos(tempo * 0.7 + v[1]) * 5.0)
			draw_rect(Rect2(roundi(p.x), roundi(p.y) - 6, 1, 1), Color(0.85, 1.0, 0.45, pisca))
	# 5) círculos (peixes, respingos)
	for c in _circulos:
		var idade: float = c[1]
		var raio: float = (3.0 + idade * 9.0) * c[2]
		var alfa := (1.0 - idade / 2.0) * 0.5
		for k in 16:
			var ang := TAU * k / 16.0
			var p: Vector2 = c[0] + Vector2(cos(ang) * raio, sin(ang) * raio * 0.5)
			draw_rect(Rect2(roundi(p.x), roundi(p.y), 1, 1), Color(0.8, 0.9, 1.0, alfa))
		if idade < 0.25:  # gotinhas pulando
			draw_rect(Rect2(roundi(c[0].x), roundi(c[0].y - 3 - idade * 10.0), 1, 1), Color(0.85, 0.95, 1.0, 0.8))
