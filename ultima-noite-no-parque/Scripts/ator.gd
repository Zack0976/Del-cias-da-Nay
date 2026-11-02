class_name Ator
extends Node2D
## Um personagem da cutscene. Sabe andar até um ponto (com a animação certa),
## olhar para os lados, aparecer e sumir.
##
## Exemplo:
##     var lucas := Ator.criar("lucas", "Lucas")
##     add_child(lucas)
##     await lucas.andar_ate(Vector2(100, 50))

var sprite: SpritePersonagem
var nome_exibido := ""
var velocidade := 45.0  ## pixels por segundo


static func criar(personagem: String, nome: String) -> Ator:
	var a := Ator.new()
	a.name = nome
	a.nome_exibido = nome
	a.sprite = SpritePersonagem.new()
	a.sprite.personagem = personagem
	a.add_child(a.sprite)
	return a


func _draw() -> void:
	# sombrinha nos pés
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 8.0, Color(0, 0, 0, 0.35))


## Anda em linha reta até "destino". Use "await" para esperar chegar.
func andar_ate(destino: Vector2, vel := -1.0) -> void:
	if vel <= 0.0:
		vel = velocidade
	var dist := position.distance_to(destino)
	if dist < 0.5:
		return
	sprite.animar(destino - position, true)
	var tw := create_tween()
	tw.tween_property(self, "position", destino, dist / vel)
	await tw.finished
	sprite.animar(Vector2.ZERO, false)


## Anda passando por vários pontos.
func andar_caminho(pontos: Array, vel := -1.0) -> void:
	for p in pontos:
		await andar_ate(p, vel)


func olhar(direcao: String) -> void:
	sprite.olhar(direcao)


func aparecer(duracao := 0.5) -> void:
	visible = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, duracao)
	await tw.finished


func sumir(duracao := 0.5) -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, duracao)
	await tw.finished
	visible = false


## Personagem deitado (dormindo / caído no chão).
func deitar(sim: bool) -> void:
	sprite.rotation = -PI / 2.0 if sim else 0.0
	# girando 90°, o corpo iria para o lado; empurramos de volta para ficar centralizado
	sprite.position = Vector2(SpriteLibrary.ALTURA_PERSONAGEM / 2.0, -5) if sim else Vector2.ZERO
	if sim:
		sprite.olhar("baixo")
		sprite.stop()
