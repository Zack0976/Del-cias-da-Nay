class_name LuzFake
extends Node2D
## LUZ PIXELADA (sem PointLight2D)
##
## No celular (Mali-G68) o PointLight2D derruba o Godot. Esta luz é um truque seguro:
##  - uma imagem de luz em "degraus" (pixel art), feita em pixel_arte.gd
##  - desenhada com mistura ADITIVA (soma cor, como luz de verdade)
##  - numa camada separada (MundoPixel.camada_luz), que NÃO é escurecida pelo
##    CanvasModulate da noite. Por isso ela brilha no escuro!
##
## Use como um nó normal: coloque como filho de quem "emite" a luz (jogador, lareira...).
## Ele cria o brilho de verdade na camada de luz e fica seguindo este nó.

var raio := 40.0:            ## tamanho da luz (pixels do mundo)
	set(v):
		raio = v
		_atualizar()
var cor := Color(1.0, 0.85, 0.5, 0.45):
	set(v):
		cor = v
		_atualizar()
var energia := 1.0:
	set(v):
		energia = v
		_atualizar()
var camadas := 4             ## (mantido por compatibilidade)
var tremer := 0.0            ## 0 = luz parada; 0.15 = fogo tremendo

var _brilho: Sprite2D
var _t := randf() * 10.0
static var _material: CanvasItemMaterial


func _ready() -> void:
	_brilho = Sprite2D.new()
	_brilho.name = "Brilho_" + name
	_brilho.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _material == null:
		_material = CanvasItemMaterial.new()
		_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_brilho.material = _material
	var camada := MundoPixel.camada_luz_atual()
	if camada:
		camada.add_child(_brilho)
	else:
		add_child(_brilho)  # sem camada de luz (ex.: tela de teste): desenha aqui mesmo
	_atualizar()


## BUG CORRIGIDO (v8): antes o brilho era apagado no "tree_exiting". Só que quando
## o jogador troca de pai (entra/sai da cabana) o nó também "sai da árvore" por um
## instante — e a luz do jogador sumia para sempre. Agora:
##   saiu da árvore  → só esconde o brilho
##   foi APAGADO     → aí sim apaga o brilho junto
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		if is_instance_valid(_brilho) and _brilho.get_parent() != self:
			_brilho.visible = false
	elif what == NOTIFICATION_PREDELETE:
		if is_instance_valid(_brilho) and _brilho.get_parent() != self:
			_brilho.queue_free()


func _atualizar() -> void:
	if _brilho == null:
		return
	var e := energia
	if tremer > 0.0:
		e *= 1.0 - tremer * 0.5 + sin(_t * 13.0) * tremer * 0.3 + randf() * tremer * 0.4
	_brilho.modulate = Color(cor.r * cor.a * 1.3 * e, cor.g * cor.a * 1.3 * e, cor.b * cor.a * 1.3 * e, 1.0)
	var tex := PixelArte.luz(raio)
	if _brilho.texture != tex:
		_brilho.texture = tex
	var esc := raio * 2.0 / tex.get_width()  # quase sempre ~1.0 (pixel perfeito)
	_brilho.scale = Vector2(esc, esc)
	_brilho.visible = visible and is_visible_in_tree() and energia > 0.01


func _process(delta: float) -> void:
	if _brilho == null or not is_instance_valid(_brilho):
		return
	if _brilho.get_parent() != self:
		_brilho.global_position = global_position.round()
		_brilho.visible = is_visible_in_tree() and energia > 0.01
	if tremer > 0.0:
		_t += delta
		_atualizar()
