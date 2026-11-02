class_name Armadilha
extends Node2D
## ARMADILHA colocada no chão.
##   corda   → prende (atordoa) por 5 s. O Colosso arrebenta a corda (só 1 s).
##   estacas → 60 de dano + prende por 3 s. Funciona bem no Colosso.
## Cada armadilha funciona UMA vez.

var tipo := "corda"
var armada := true
const RAIO := 10.0


static func criar(t: String, pos: Vector2) -> Armadilha:
	var a := Armadilha.new()
	a.tipo = t
	a.position = pos.round()
	return a


func _ready() -> void:
	add_to_group("armadilha")
	z_index = 0


## O monstro chama isto quando pisa. Devolve [dano, segundos_preso].
func disparar(monstro: Node) -> Array:
	if not armada:
		return [0.0, 0.0]
	armada = false
	queue_redraw()
	var resultado := [0.0, 5.0] if tipo == "corda" else [60.0, 3.0]
	if tipo == "corda" and monstro.tipo_monstro == "colosso":
		resultado = [0.0, 1.0]
	# some depois de um tempinho
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(self, "modulate:a", 0.0, 1.0)
	tw.tween_callback(queue_free)
	return resultado


func _draw() -> void:
	if tipo == "corda":
		var cor := Color("b09060") if armada else Color("6a5a40")
		for k in 16:
			var a := k * TAU / 16.0
			draw_rect(Rect2((Vector2(cos(a) * 6.0, sin(a) * 3.5)).round(), Vector2(1, 1)), cor)
		draw_rect(Rect2(6, -1, 4, 1), cor)
	else:
		draw_rect(Rect2(-7, -1, 14, 3), Color("4a3018"))
		if armada:
			for k in 4:
				draw_rect(Rect2(-6 + k * 4, -5, 1, 4), Color("8a6a40"))
				draw_rect(Rect2(-6 + k * 4, -6, 1, 1), Color("d0c0a0"))
		else:
			draw_rect(Rect2(-6, -2, 12, 1), Color("6a2020"))
