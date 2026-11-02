class_name LucasVulto
extends Node2D
## =============================================================================
##  O VULTO DO LUCAS (v10)
## =============================================================================
## O Lucas sumiu na primeira noite. Às vezes, no fim da tarde (ou quando a sua
## MENTE está muito ruim), você vê ele de longe, andando para dentro da floresta.
## Ele nunca deixa você chegar perto: quando você chega, ele some… e deixa cair
## uma PÁGINA do caderno dele (pista da história).
## Usa a folha nova lucas_andar.png (andando de frente, de costas e de lado).
## =============================================================================

signal alcancado(pos: Vector2)
signal sumiu

const VELOCIDADE := 24.0
const DIST_SUMIR := 46.0
const DURACAO := 30.0

var alvo: Node2D                ## o jogador
var _sprite: SpritePersonagem
var _vida := DURACAO
var _indo_embora := false
var _dir := Vector2.ZERO


func _ready() -> void:
	_sprite = SpritePersonagem.new()
	_sprite.personagem = "lucas"
	add_child(_sprite)
	_sprite.configurar("lucas")
	modulate = Color(0.85, 0.9, 1.0, 0.0)
	create_tween().tween_property(self, "modulate:a", 0.85, 1.2)


func _physics_process(delta: float) -> void:
	if _indo_embora:
		return
	_vida -= delta
	if alvo == null or not is_instance_valid(alvo) or _vida <= 0.0:
		_desaparecer(false)
		return
	var dist := global_position.distance_to(alvo.global_position)
	if dist < DIST_SUMIR:
		_desaparecer(true)
		return
	# fica um tempinho parado olhando para você, depois anda para longe
	if _vida > DURACAO - 2.5:
		_sprite.animar((alvo.global_position - global_position).normalized(), false)
		return
	_dir = (global_position - alvo.global_position).normalized().rotated(sin(_vida) * 0.4)
	global_position += _dir * VELOCIDADE * delta
	_sprite.animar(_dir, true)


func _desaparecer(pego: bool) -> void:
	_indo_embora = true
	_sprite.animar(_dir, false)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.6 if pego else 1.5)
	await tw.finished
	if pego:
		alcancado.emit(global_position)
	sumiu.emit()
	queue_free()
