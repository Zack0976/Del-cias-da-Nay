extends Node2D
## Desenha o "Colosso" (o monstro do menu) por código.
## Cada monstro sorteia uma "semente": assim, se o desenho precisar ser refeito,
## ele sai IGUAL (antes, os tentáculos e dentes mudavam toda vez que redesenhava).

var semente := randi()

func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	var c_skull = Color(0.9, 0.9, 0.9) # Branco osso
	var c_black = Color(0.0, 0.0, 0.0) # Preto absoluto
	var c_red_blood = Color(0.5, 0.0, 0.0) # Vermelho sangue
	
	# 1. TENTÁCULOS E SANGUE (Fundo)
	for i in range(15):
		var ang = rng.randf_range(0, PI * 2)
		var dist = rng.randf_range(100, 400)
		var end_pos = Vector2(cos(ang), sin(ang)) * dist
		# Linhas grossas simulando os tentáculos saindo da caveira
		draw_line(Vector2(0, 50), end_pos, c_red_blood, rng.randf_range(10, 30))
	
	# 2. OSSOS DA FACE
	draw_circle(Vector2(0, -20), 140, c_skull)
	draw_rect(Rect2(-80, 40, 160, 120), c_skull)
	
	# 3. OLHOS VAZIOS E PUPILAS VERMELHAS
	draw_circle(Vector2(-55, -50), 45, c_black)
	draw_circle(Vector2(55, -50), 45, c_black)
	# Brilho vermelho dentro do olho
	draw_circle(Vector2(-55, -50), 15, c_red_blood)
	draw_circle(Vector2(55, -50), 15, c_red_blood)
	
	# 4. BOCA RASGADA (Cheia de picos e dentes tortos)
	var mouth_points = PackedVector2Array([
		Vector2(-90, 60), Vector2(-70, 100), Vector2(-50, 50), 
		Vector2(-30, 110), Vector2(-10, 50), Vector2(10, 120), 
		Vector2(30, 50), Vector2(50, 110), Vector2(70, 60), 
		Vector2(90, 100), Vector2(100, 160), Vector2(-100, 160)
	])
	draw_colored_polygon(mouth_points, c_black)
	
	# 5. DENTES AFIADOS (Dentro da boca)
	for i in range(-80, 80, 20):
		# Dentes de cima
		draw_colored_polygon(PackedVector2Array([
			Vector2(i, 50), Vector2(i+15, 50), Vector2(i+7, 90 + rng.randf_range(-10, 20))
		]), c_skull)
		# Dentes de baixo
		draw_colored_polygon(PackedVector2Array([
			Vector2(i, 160), Vector2(i+15, 160), Vector2(i+7, 120 - rng.randf_range(-10, 20))
		]), c_skull)

	# 6. RACHADURAS NO CRÂNIO
	for i in range(5):
		var start = Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 0))
		var end = start + Vector2(rng.randf_range(-30, 30), rng.randf_range(20, 60))
		draw_line(start, end, c_black, 3.0)
