class_name SpritePersonagem
extends AnimatedSprite2D
## Sprite animado de personagem, usado pelo Player e pelos atores da cutscene.
## - Ajusta o tamanho automaticamente a cada animação (todos ficam com a mesma altura).
## - Os pés ficam no ponto (0, 0) do nó: ótimo para y-sort (quem está mais embaixo aparece na frente).

@export var personagem := "protagonista"

var direcao := "baixo"  ## baixo, cima, direita, esquerda


func _ready() -> void:
	centered = true
	animation_changed.connect(_ajustar_escala)
	if sprite_frames == null:
		configurar(personagem)


func configurar(nome: String) -> void:
	personagem = nome
	sprite_frames = SpriteLibrary.frames_personagem(nome)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pixel art nítida
	play("parado_baixo")
	_ajustar_escala()


func _ajustar_escala() -> void:
	if sprite_frames == null or not sprite_frames.has_meta("escalas"):
		return
	var escalas: Dictionary = sprite_frames.get_meta("escalas")
	var esc: float = escalas.get(animation, 1.0)
	scale = Vector2(esc, esc)
	var tex := sprite_frames.get_frame_texture(animation, 0)
	if tex:
		offset = Vector2(0, -tex.get_height() / 2.0)


## Converte um vetor de direção em "baixo/cima/direita/esquerda".
static func nome_direcao(v: Vector2) -> String:
	if absf(v.x) > absf(v.y):
		return "direita" if v.x > 0.0 else "esquerda"
	return "baixo" if v.y > 0.0 else "cima"


## Toca andar/parado na direção dada.
func animar(dir: Vector2, andando: bool) -> void:
	if dir != Vector2.ZERO:
		direcao = nome_direcao(dir)
	var nome := ("andar_" if andando else "parado_") + direcao
	if not sprite_frames.has_animation(nome):
		return
	if animation != nome or not is_playing():
		play(nome)


func olhar(dir_nome: String) -> void:
	direcao = dir_nome
	play("parado_" + dir_nome)
