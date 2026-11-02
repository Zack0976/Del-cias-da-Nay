class_name Otimizacao
extends RefCounted
## Quantidades de coisas no mundo, de acordo com o NÍVEL DE DETALHE (Opções)
## e com o aparelho (celular desenha menos que o PC).
##
## Nível: 1 = BAIXO (leve) | 2 = MÉDIO | 3 = ALTO (mais enfeites + sombras projetadas)
##
## Por que dá para ter MUITOS enfeites sem pesar?
##  - Os enfeites e as árvores do fundo são desenhados UMA vez só, junto com o chão.
##  - Todos usam poucas texturas pequenas, então o Godot junta tudo em poucos
##    comandos para a placa de vídeo ("batching").
##  - Só as árvores perto da ação são Sprites de verdade (para entrar na frente
##    ou atrás dos personagens).


static func _escolher(baixo: int, medio: int, alto: int) -> int:
	match GameData.nivel_detalhe():
		1: return baixo
		2: return medio
		_: return alto


## Árvores-sprite perto da ação (estrada, cabana, lago).
static func qtd_arvores() -> int:
	if GameData.eh_mobile:
		return _escolher(45, 70, 95)
	return _escolher(90, 140, 190)


## Árvores do fundo (floresta distante, desenhadas junto com o chão).
static func qtd_arvores_fundo() -> int:
	if GameData.eh_mobile:
		return _escolher(140, 230, 320)
	return _escolher(250, 400, 550)


## Flores, pedras, arbustos, cogumelos, tocos...
static func qtd_enfeites() -> int:
	if GameData.eh_mobile:
		return _escolher(250, 450, 700)
	return _escolher(500, 900, 1400)


static func qtd_enfeites_lago() -> int:
	return _escolher(14, 24, 36)


## Manchas de grama escura/seca no chão.
static func qtd_manchas() -> int:
	if GameData.eh_mobile:
		return _escolher(25, 45, 70)
	return _escolher(60, 110, 160)


## Redesenho limitado (economiza CPU em _draw animado).
static func deve_redesenhar(acumulado: float, fps_alvo: float = -1.0) -> bool:
	if fps_alvo < 0.0:
		fps_alvo = 8.0 if GameData.fps_maximo <= 30 else 12.0
	return acumulado >= (1.0 / fps_alvo)


static func escala_particulas() -> float:
	match GameData.nivel_detalhe():
		1: return 0.55
		2: return 0.8
		_: return 1.0
