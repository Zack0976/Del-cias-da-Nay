class_name Interagivel
extends Area2D
## Objeto que o jogador pode examinar (porta, rádio, cama, foto...).
## Quando o jogador chega perto, aparece o botão "EXAMINAR".
## Quem decide o que acontece é o script da fase (jogo.gd), ouvindo o sinal "examinado".

signal examinado(obj: Interagivel)

@export var id := ""                 ## nome interno, ex.: "porta", "radio"
@export var acao := "EXAMINAR"       ## texto do botão
@export var raio := 18.0             ## distância para conseguir examinar
var ativo := true

const CAMADA_INTERAGIVEIS := 4  ## camada de física 3 (valor em bits: 1=camada1, 2=camada2, 4=camada3)


static func criar(id_obj: String, pos: Vector2, raio_obj := 18.0, texto_acao := "EXAMINAR") -> Interagivel:
	var i := Interagivel.new()
	i.id = id_obj
	i.name = "Interagivel_" + id_obj
	i.position = pos
	i.raio = raio_obj
	i.acao = texto_acao
	return i


func _ready() -> void:
	collision_layer = CAMADA_INTERAGIVEIS
	collision_mask = 0
	monitoring = false
	monitorable = true
	if get_child_count() == 0:
		var forma := CollisionShape2D.new()
		var circulo := CircleShape2D.new()
		circulo.radius = raio
		forma.shape = circulo
		add_child(forma)


func examinar() -> void:
	if ativo:
		examinado.emit(self)
