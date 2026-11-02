class_name Abertura
extends Node2D
## PORTA OU JANELA DA CABANA (com barricada)
##
## Cada abertura tem "resistência" (hp). 0 = aberta/quebrada: o Rastejante e a
## Sombra conseguem ENTRAR por ela. O Colosso destrói barricadas batendo nelas.
## Toda manhã as barricadas perdem parte da resistência (madeira racha, pregos soltam),
## então é preciso reforçar a casa TODAS as noites.
##
## Este nó fica do lado de FORA. "ponto_dentro" é onde o monstro aparece lá dentro.

signal quebrou(abertura: Abertura)
signal mudou(abertura: Abertura)

const MAX_HP := 200.0

var id := "porta"
var hp := 0.0:
	set(v):
		hp = v
		_redesenhar()   # qualquer mudança redesenha as tábuas (dentro e fora)
var ponto_dentro := Vector2.ZERO       ## posição global do outro lado (interior)
var retangulo_fora := Rect2()          ## onde desenhar as tábuas do lado de fora (local)
var desenho_dentro: Node2D            ## nó que desenha as tábuas no interior
var retangulo_dentro := Rect2()


func reforcar(valor: float) -> void:
	hp = minf(hp + valor, MAX_HP)
	_redesenhar()
	mudou.emit(self)


func danificar(valor: float) -> void:
	if hp <= 0.0:
		return
	hp = maxf(hp - valor, 0.0)
	_redesenhar()
	mudou.emit(self)
	if hp <= 0.0:
		quebrou.emit(self)


func aberta() -> bool:
	return hp <= 0.0


## Chamado ao amanhecer.
func desgastar() -> void:
	hp = floorf(hp * 0.65)
	_redesenhar()
	mudou.emit(self)


func _ready() -> void:
	z_index = 3
	if desenho_dentro:
		desenho_dentro.draw.connect(_desenhar_tabuas.bind(desenho_dentro, retangulo_dentro))


func _redesenhar() -> void:
	queue_redraw()
	if desenho_dentro and is_instance_valid(desenho_dentro):
		desenho_dentro.queue_redraw()


func _draw() -> void:
	_desenhar_tabuas(self, retangulo_fora)


## Tábuas em pixel art: quanto mais resistência, mais tábuas (e metal acima de 100).
func _desenhar_tabuas(c: CanvasItem, r: Rect2) -> void:
	if hp <= 0.0 or r.size == Vector2.ZERO:
		return
	var tabuas := clampi(ceili(hp / 40.0), 1, 5)
	var horizontal := r.size.x >= r.size.y
	for k in tabuas:
		var t := float(k + 1) / (tabuas + 1)
		var cor := Color("6b4b2a") if k % 2 == 0 else Color("5c3e22")
		if horizontal:
			var y := roundi(r.position.y + r.size.y * t) - 1
			c.draw_rect(Rect2(r.position.x - 2, y, r.size.x + 4, 3), cor)
			c.draw_rect(Rect2(r.position.x - 2, y, r.size.x + 4, 1), Color("8a6a40"))
			c.draw_rect(Rect2(r.position.x, y + 1, 1, 1), Color("b0a080"))  # prego
			c.draw_rect(Rect2(r.end.x - 1, y + 1, 1, 1), Color("b0a080"))
		else:
			var x := roundi(r.position.x + r.size.x * t) - 1
			c.draw_rect(Rect2(x, r.position.y - 2, 3, r.size.y + 4), cor)
			c.draw_rect(Rect2(x, r.position.y - 2, 1, r.size.y + 4), Color("8a6a40"))
	if hp > 100.0:  # chapas de metal
		c.draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(minf(r.size.x - 2, 8), minf(r.size.y - 2, 6))), Color("6a6a72"))
		c.draw_rect(Rect2(r.position + Vector2(2, 2), Vector2(1, 1)), Color("2a2a2a"))
