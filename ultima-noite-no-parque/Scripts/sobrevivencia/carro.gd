class_name Carro
extends Node2D
## O CARRO como recurso e esconderijo.
##   VASCULHAR      → acha itens (uma vez)
##   FARÓIS         → cone de luz forte (gasta a bateria do carro). Espanta o
##                    Observador e a Sombra; ofusca o Rastejante.
##   ESCONDER       → entra no carro: o Rastejante e a Sombra perdem você de vista.
##                    O Colosso consegue sacudir o carro e te tirar de lá!
##   PEGAR BATERIA  → tira a bateria do carro: vira 2 baterias para a lanterna,
##                    mas os faróis nunca mais acendem.

signal mudou

var bateria := 100.0         ## carga da bateria do carro (0-100)
var bateria_removida := false
var vasculhado := false
var farois := false
var obstaculos: Array = []   ## [centro, raio] que bloqueiam a luz
var sprite: Sprite2D

var _cone: Node2D
var _poligono := PackedVector2Array()
var _acum := 0.0
static var _mat_add: CanvasItemMaterial

const ALCANCE := 170.0
const ABERTURA := 0.42       ## ~24 graus para cada lado
const GASTO := 1.6           ## % de bateria por segundo


func _ready() -> void:
	add_to_group("carro")
	_cone = Node2D.new()
	_cone.name = "ConeFarol"
	if _mat_add == null:
		_mat_add = CanvasItemMaterial.new()
		_mat_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_cone.material = _mat_add
	_cone.draw.connect(_desenhar_cone)
	var camada := MundoPixel.camada_luz_atual()
	if camada:
		camada.add_child(_cone)
	else:
		add_child(_cone)
	_cone.visible = false


func _enter_tree() -> void:
	Iluminacao.registrar_cone(self)


func _exit_tree() -> void:
	Iluminacao.remover(self)
	if is_instance_valid(_cone) and _cone.get_parent() != self:
		_cone.queue_free()


func origem_farol() -> Vector2:
	return global_position + Vector2(30, -9)


func farois_ligados() -> bool:
	return farois and bateria > 0.0


func poligono_global() -> PackedVector2Array:
	return _poligono


func ligar_farois(sim: bool) -> bool:
	if sim and (bateria <= 0.0 or bateria_removida):
		return false
	farois = sim
	_recalcular()
	_atualizar_sprite()
	mudou.emit()
	return true


func remover_bateria() -> int:
	if bateria_removida:
		return 0
	bateria_removida = true
	var qtd := 2 if bateria > 30.0 else 1
	bateria = 0.0
	ligar_farois(false)
	mudou.emit()
	return qtd


func _process(delta: float) -> void:
	if not farois:
		return
	bateria = maxf(bateria - GASTO * delta, 0.0)
	if bateria <= 0.0:
		ligar_farois(false)
		return
	_acum += delta
	if _acum > 0.25:  # o cone só é recalculado 4x por segundo (economia)
		_acum = 0.0
		_recalcular()


func _recalcular() -> void:
	if farois_ligados():
		_poligono = FarolCone.poligono(origem_farol(), 0.0, ALCANCE, ABERTURA, obstaculos)
	else:
		_poligono = PackedVector2Array()
	_cone.visible = farois_ligados()
	_cone.queue_redraw()


func _desenhar_cone() -> void:
	if _poligono.size() < 3:
		return
	var intensidade := clampf(bateria / 40.0, 0.35, 1.0)  # bateria fraca = luz fraca
	FarolCone.desenhar(_cone, origem_farol(), _poligono, Color(1.0, 0.92, 0.65), intensidade)
	# brilho dos próprios faróis
	_cone.draw_rect(Rect2(origem_farol() + Vector2(-2, -2), Vector2(4, 4)), Color(0.6, 0.55, 0.35))


func _atualizar_sprite() -> void:
	if sprite:
		sprite.texture = SpriteLibrary.quadro("carro", 2 if farois_ligados() else 0)


func para_dados() -> Dictionary:
	return {"bateria": bateria, "removida": bateria_removida, "vasculhado": vasculhado}


func de_dados(d: Dictionary) -> void:
	bateria = float(d.get("bateria", 100.0))
	bateria_removida = bool(d.get("removida", false))
	vasculhado = bool(d.get("vasculhado", false))
