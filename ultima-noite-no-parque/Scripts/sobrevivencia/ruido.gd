class_name Ruido
extends RefCounted
## SISTEMA DE RUÍDO
## Correr, quebrar galhos, martelar na bancada e jogar o chocalho fazem barulho.
## Todo monstro (grupo "monstro") dentro do raio do barulho fica sabendo e
## pode ir INVESTIGAR o lugar.
##
## Valores de referência (raio em pixels do mundo):
##   andar = 0 | correr = 110 | coletar madeira/pedra = 90 | criar à mão = 40-120
##   bancada = 120-200 | chocalho = 260

static var ultimo := {"pos": Vector2.ZERO, "raio": 0.0, "tempo": 0.0}  ## para o HUD mostrar


static func emitir(arvore: SceneTree, pos: Vector2, raio: float) -> void:
	if raio <= 0.0 or arvore == null:
		return
	ultimo = {"pos": pos, "raio": raio, "tempo": Time.get_ticks_msec() / 1000.0}
	for m in arvore.get_nodes_in_group("monstro"):
		if is_instance_valid(m) and m.global_position.distance_to(pos) <= raio + m.audicao:
			m.ouviu(pos, raio)
