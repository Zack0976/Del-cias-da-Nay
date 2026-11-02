class_name Player
extends CharacterBody2D
## Personagem jogável de "Última Noite no Parque".
## Movimento top-down (teclado + joystick virtual), animação nas 4 direções,
## luz em volta do jogador e detecção de objetos para examinar.

signal alvo_mudou(alvo: Interagivel)  ## o HUD usa para mostrar/esconder o botão "EXAMINAR"

@export_group("Movimento")
@export var velocidade: float = 70.0       ## pixels por segundo
@export var aceleracao: float = 700.0      ## quão rápido atinge a velocidade
@export var atrito: float = 1000.0         ## quão rápido para ao soltar
@export_range(0.0, 0.9) var zona_morta: float = 0.2  ## ignora toques fracos no joystick

var som_passo := "passo"                   ## v11: "passo_madeira" dentro da cabana
var pode_mover: bool = true                 ## desligado em cutscenes, diálogos e pausa
var alvo: Interagivel = null                ## objeto mais perto que dá para examinar

var _entrada_virtual: Vector2 = Vector2.ZERO
var _proximos: Array[Interagivel] = []
var _tempo_passo := 0.0
var _glow: LuzFake

@onready var sprite: SpritePersonagem = $Sprite
@onready var camera: Camera2D = $Camera2D
@onready var luz: PointLight2D = get_node_or_null("Luz")
@onready var area_interacao: Area2D = $AreaInteracao


func _ready() -> void:
	add_to_group("jogador")  # o joystick e os inimigos (no futuro) encontram o player por aqui
	sprite.configurar(SpriteLibrary.personagem_do_jogador())
	area_interacao.area_entered.connect(_on_area_entrou)
	area_interacao.area_exited.connect(_on_area_saiu)
	# PointLight2D derruba o Godot em vários Android (crash nativo).
	# Se luzes estiverem desligadas, removemos o nó em vez de só disabled.
	if GameData.permite_luzes() and luz != null:
		luz.texture = criar_textura_luz()
		luz.texture_scale = 0.9 if GameData.eh_mobile else 1.0
		luz.energy = 0.7 if GameData.eh_mobile else 0.9
		atualizar_luz()
	else:
		if luz != null:
			luz.enabled = false
			luz.queue_free()
			luz = null
		_glow = LuzFake.new()
		_glow.name = "GlowJogador"
		_glow.position = Vector2(0, -12)
		_glow.raio = 28.0
		_glow.cor = Color(0.75, 0.8, 1.0, 0.3)
		_glow.energia = 0.7
		add_child(_glow)
		atualizar_luz()


func _physics_process(delta: float) -> void:
	var direcao := _ler_entrada() if pode_mover else Vector2.ZERO

	if direcao != Vector2.ZERO:
		velocity = velocity.move_toward(direcao * velocidade, aceleracao * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, atrito * delta)

	move_and_slide()
	sprite.animar(direcao, velocity.length() > 5.0)
	_sons_de_passo(delta)
	_atualizar_alvo()


# ---------------------------------------------------------------
# ENTRADA
# ---------------------------------------------------------------

## O joystick virtual chama esta função com um Vector2 (de -1 a 1).
func definir_entrada_virtual(valor: Vector2) -> void:
	_entrada_virtual = valor.limit_length(1.0)


## Liga/desliga o controle do jogador (cutscenes, diálogos, etc.).
func definir_pode_mover(valor: bool) -> void:
	pode_mover = valor
	if not valor:
		_entrada_virtual = Vector2.ZERO


func _ler_entrada() -> Vector2:
	# Teclado tem prioridade (get_vector já normaliza as diagonais).
	var teclado := Input.get_vector("mover_esquerda", "mover_direita", "mover_cima", "mover_baixo")
	if teclado != Vector2.ZERO:
		return teclado
	if _entrada_virtual.length() < zona_morta:
		return Vector2.ZERO
	return _entrada_virtual


func _sons_de_passo(delta: float) -> void:
	if velocity.length() < 20.0:
		_tempo_passo = 0.2
		return
	_tempo_passo -= delta
	if _tempo_passo <= 0.0:
		_tempo_passo = 0.36
		Sons.tocar(self, som_passo, -14.0, randf_range(0.85, 1.15))


# ---------------------------------------------------------------
# OBJETOS PARA EXAMINAR
# ---------------------------------------------------------------
func _on_area_entrou(area: Area2D) -> void:
	if area is Interagivel and area not in _proximos:
		_proximos.append(area)


func _on_area_saiu(area: Area2D) -> void:
	_proximos.erase(area)


func _atualizar_alvo() -> void:
	var melhor: Interagivel = null
	var melhor_dist := INF
	for obj in _proximos:
		if not is_instance_valid(obj) or not obj.ativo:
			continue
		var d := global_position.distance_to(obj.global_position)
		if d < melhor_dist:
			melhor_dist = d
			melhor = obj
	if melhor != alvo:
		alvo = melhor
		alvo_mudou.emit(alvo)


# ---------------------------------------------------------------
# LUZ
# ---------------------------------------------------------------

## Luz fraca normalmente; com a lanterna ela fica maior e amarelada.
func atualizar_luz() -> void:
	if GameData.permite_luzes() and luz != null and is_instance_valid(luz):
		luz.enabled = true
		if GameData.tem_item("lanterna"):
			luz.texture_scale = 1.6
			luz.energy = 1.25
			luz.color = Color(1.0, 0.85, 0.55)
		else:
			luz.texture_scale = 0.75
			luz.energy = 0.8
			luz.color = Color(0.75, 0.8, 1.0)
		return
	if _glow == null or not is_instance_valid(_glow):
		return
	if GameData.tem_item("lanterna"):
		_glow.raio = 55.0
		_glow.cor = Color(1.0, 0.85, 0.5, 0.4)
		_glow.energia = 1.2
	else:
		_glow.raio = 26.0
		_glow.cor = Color(0.7, 0.75, 1.0, 0.28)
		_glow.energia = 0.65
	_glow.queue_redraw()


## Textura redonda (degradê do centro para fora) usada pelas luzes.
static func criar_textura_luz() -> GradientTexture2D:
	# Do branco (centro) para o preto (borda), caindo suave: luz em modo "somar"
	# com preto = não soma nada, então a borda some sem deixar "anel".
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1), Color(0.62, 0.62, 0.62), Color(0.3, 0.3, 0.3), Color(0.09, 0.09, 0.09), Color(0, 0, 0)
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 256
	tex.height = 256
	return tex
