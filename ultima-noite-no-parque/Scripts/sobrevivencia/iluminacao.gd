class_name Iluminacao
extends RefCounted
## ILUMINAÇÃO COMO RECURSO
## Toda fonte de luz que "protege" se registra aqui. Os monstros perguntam
## "este ponto está iluminado?" para decidir o que fazer:
##   - o Observador some quando recebe luz
##   - a Sombra não entra na luz
##   - o Rastejante fica ofuscado pelos faróis
##
## Fontes circulares: tocha, lanterna, lampião, fogueira, lâmpada.
## Fontes em cone: faróis do carro (com bloqueio por árvores!).

static var _circulos: Array = []  ## [nó, raio_extra_func]
static var _cones: Array = []     ## nós com get_poligono_luz()


static func registrar(no: Node2D) -> void:
	if no not in _circulos:
		_circulos.append(no)


static func registrar_cone(no: Node2D) -> void:
	if no not in _cones:
		_cones.append(no)


static func remover(no: Node2D) -> void:
	_circulos.erase(no)
	_cones.erase(no)


static func limpar() -> void:
	_circulos.clear()
	_cones.clear()


## Cada fonte circular precisa ter: raio_protecao (float) e ativa() -> bool
static func esta_iluminado(pos: Vector2, folga := 0.0) -> bool:
	for no in _circulos:
		if not is_instance_valid(no) or not no.ativa():
			continue
		if no.global_position.distance_to(pos) <= no.raio_protecao + folga:
			return true
	for no in _cones:
		if not is_instance_valid(no) or not no.farois_ligados():
			continue
		if Geometry2D.is_point_in_polygon(pos, no.poligono_global()):
			return true
	return false


## Quão perto da luz mais próxima (0 = dentro, 1 = longe/sem luz nenhuma).
static func distancia_luz(pos: Vector2) -> float:
	var melhor := INF
	for no in _circulos:
		if is_instance_valid(no) and no.ativa():
			melhor = minf(melhor, maxf(no.global_position.distance_to(pos) - no.raio_protecao, 0.0))
	return melhor
