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

## v11: o cone com degradê foi tirado (ficava feio). Agora o farol é uma luz
## REDONDA pixelada na frente do carro, igual às outras luzes do jogo.
## Para os monstros ela funciona como qualquer luz (FonteLuz), e o Rastejante
## que entra nela fica ofuscado.

var bateria := 100.0         ## carga da bateria do carro (0-100)
var bateria_removida := false
var vasculhado := false
var farois := false
var obstaculos: Array = []   ## (mantido por compatibilidade; não é mais usado)
var sprite: Sprite2D
var luz: FonteLuz

const RAIO_LUZ := 64.0
const GASTO := 1.6           ## % de bateria por segundo


func _ready() -> void:
	add_to_group("carro")
	luz = FonteLuz.criar(RAIO_LUZ, Color(1.0, 0.92, 0.65, 0.5))
	luz.position = Vector2(30 + RAIO_LUZ * 0.7, -6)
	luz.ligada = false
	add_child(luz)


func origem_farol() -> Vector2:
	return global_position + Vector2(30, -9)


## Centro da luz dos faróis (no chão, na frente do carro).
func ponto_luz() -> Vector2:
	return luz.global_position if luz else global_position


func farois_ligados() -> bool:
	return farois and bateria > 0.0


## Mantido para o código antigo: agora o farol não é mais um cone.
func poligono_global() -> PackedVector2Array:
	return PackedVector2Array()


## O ponto está dentro da luz dos faróis?
func iluminando(pos: Vector2) -> bool:
	return farois_ligados() and pos.distance_to(ponto_luz()) < RAIO_LUZ * 0.85


func ligar_farois(sim: bool) -> bool:
	if sim and (bateria <= 0.0 or bateria_removida):
		return false
	farois = sim
	if luz:
		luz.ligada = farois_ligados()
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


## v11: colocar uma bateria de volta (para a fuga no final).
func recolocar_bateria() -> void:
	bateria_removida = false
	bateria = maxf(bateria, 60.0)
	mudou.emit()


func _process(delta: float) -> void:
	if not farois:
		return
	bateria = maxf(bateria - GASTO * delta, 0.0)
	if bateria <= 0.0:
		ligar_farois(false)
		return
	if luz and luz._luz:   # bateria fraca = luz fraca
		luz._luz.energia = clampf(bateria / 40.0, 0.4, 1.0)


func _atualizar_sprite() -> void:
	if sprite:
		sprite.texture = SpriteLibrary.quadro("carro", 2 if farois_ligados() else 0)


func para_dados() -> Dictionary:
	return {"bateria": bateria, "removida": bateria_removida, "vasculhado": vasculhado}


func de_dados(d: Dictionary) -> void:
	bateria = float(d.get("bateria", 100.0))
	bateria_removida = bool(d.get("removida", false))
	vasculhado = bool(d.get("vasculhado", false))
