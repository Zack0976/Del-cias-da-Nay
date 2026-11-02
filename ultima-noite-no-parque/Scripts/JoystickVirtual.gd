class_name JoystickVirtual
extends Control
## Joystick virtual para celular.
##
## BUG ANTIGO: este arquivo era uma cópia do script do Player (CharacterBody2D)
## e estava colocado num Control — o Godot dava erro e o joystick não existia.
##
## Como funciona: encoste o dedo em qualquer lugar da metade ESQUERDA da tela.
## O joystick aparece embaixo do dedo; arraste para andar. Solte para parar.
## A cada movimento ele avisa o jogador: player.definir_entrada_virtual(vetor)

@export var raio := 90.0                 ## até onde a bolinha pode ir (pixels da tela)
@export var area_da_tela := 0.45         ## parte da tela (da esquerda) que aceita o toque

var _toque := -1                          ## qual dedo está usando o joystick (-1 = nenhum)
var _centro := Vector2.ZERO
var _bolinha := Vector2.ZERO
var vetor := Vector2.ZERO                 ## direção atual (-1 a 1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # não "rouba" toques dos botões
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_posicao_descanso()


func _posicao_descanso() -> void:
	var tela := get_viewport_rect().size
	_centro = Vector2(170, tela.y - 170)
	_bolinha = _centro


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var toque := event as InputEventScreenTouch
		if toque.pressed and _toque == -1:
			if toque.position.x < get_viewport_rect().size.x * area_da_tela and toque.position.y > 90.0:
				_toque = toque.index
				_centro = toque.position
				_bolinha = _centro
				_atualizar(toque.position)
		elif not toque.pressed and toque.index == _toque:
			_soltar()
	elif event is InputEventScreenDrag:
		var arraste := event as InputEventScreenDrag
		if arraste.index == _toque:
			_atualizar(arraste.position)


func _atualizar(pos_dedo: Vector2) -> void:
	var desloc := (pos_dedo - _centro).limit_length(raio)
	_bolinha = _centro + desloc
	vetor = desloc / raio
	_avisar_jogador()
	queue_redraw()


func _soltar() -> void:
	_toque = -1
	vetor = Vector2.ZERO
	_posicao_descanso()
	_avisar_jogador()
	queue_redraw()


func _avisar_jogador() -> void:
	for jogador in get_tree().get_nodes_in_group("jogador"):
		if jogador.has_method("definir_entrada_virtual"):
			jogador.definir_entrada_virtual(vetor)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _toque == -1:
		_posicao_descanso()
		queue_redraw()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and _toque != -1:
		_soltar()


func _draw() -> void:
	var ativo := _toque != -1
	var alfa := 0.55 if ativo else 0.25
	draw_circle(_centro, raio, Color(0.05, 0.05, 0.05, alfa * 0.8))
	draw_arc(_centro, raio, 0.0, TAU, 48, Color(0.7, 0.15, 0.15, alfa), 3.0, true)
	draw_circle(_bolinha, raio * 0.42, Color(0.75, 0.72, 0.65, alfa + 0.15))
