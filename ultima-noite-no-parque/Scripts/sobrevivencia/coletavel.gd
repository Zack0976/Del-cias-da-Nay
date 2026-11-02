class_name Coletavel
extends Node2D
## RECURSO NO CHÃO (galhos, tocos, troncos caídos, pedras, ervas, latas...)
## Fica brilhando um pouquinho para o jogador achar. Quando você chega perto,
## aparece uma SETINHA pulando em cima dele e o botão vira "PEGAR".
## Pegar faz barulho (quebrar galho, arrastar pedra), o que pode atrair monstros à noite.

var item := "madeira"
var qtd := 1
var ruido := 0.0
var visual := ""                 ## textura do chão (ex.: "toco"). Vazio = escolhe pelo item
var destacado := false:          ## o controlador liga isto no coletável mais perto do jogador
	set(v):
		if v != destacado:
			destacado = v
			queue_redraw()
var interagivel: Interagivel
var _t := randf() * 6.0
var _sprite: Sprite2D

const RUIDO_POR_ITEM := {"madeira": 90.0, "pedra": 90.0, "metal": 70.0}
const VISUAL := {"madeira": "galhos", "pedra": "pedra_m", "ervas": "samambaia", "fruta": "arbusto"}


static func criar(id_item: String, quantidade: int, pos: Vector2, textura_chao := "") -> Coletavel:
	var c := Coletavel.new()
	c.item = id_item
	c.qtd = quantidade
	c.position = pos.round()
	c.ruido = RUIDO_POR_ITEM.get(id_item, 0.0)
	c.visual = textura_chao
	return c


func _ready() -> void:
	add_to_group("coletavel")
	_sprite = Sprite2D.new()
	var nome_vis: String = visual if visual != "" else VISUAL.get(item, "")
	if nome_vis != "":
		_sprite.texture = PixelArte.textura(nome_vis)
	else:
		_sprite.texture = Itens.icone(item)
	_sprite.offset = Vector2(0, -_sprite.texture.get_size().y / 2.0)
	add_child(_sprite)
	var raio := 12.0 if visual != "tronco_caido" else 16.0
	interagivel = Interagivel.criar("coletar_" + item, Vector2(0, -3), raio, "PEGAR")
	add_child(interagivel)


func _process(delta: float) -> void:
	_t += delta
	# brilhinho pulsando (ajuda a achar no escuro, mas sem exagero)
	var brilho := 1.05 + maxf(0.0, sin(_t * 2.1)) * 0.4
	_sprite.modulate = Color(brilho, brilho, brilho * 0.95)
	if destacado:
		queue_redraw()


func _draw() -> void:
	if not destacado:
		return
	# setinha pixelada pulando em cima do item + ícone do que você vai ganhar
	var alto := _sprite.texture.get_size().y + 6.0 + roundi(absf(sin(_t * 5.0)) * 3.0)
	var cor := Color(1.0, 0.95, 0.7)
	for k in 4:
		draw_rect(Rect2(-3 + k, -alto + k, 7 - k * 2, 1), cor)
	draw_rect(Rect2(-1, -alto - 4, 3, 4), cor)
	var ic := Itens.icone(item)
	draw_texture_rect(ic, Rect2(-8, -alto - 22, 16, 16), false)
	if qtd > 1:
		draw_rect(Rect2(6, -alto - 10, 7, 6), Color(0, 0, 0, 0.6))
		draw_string(ThemeDB.fallback_font, Vector2(7, -alto - 5), "x%d" % qtd, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, cor)
