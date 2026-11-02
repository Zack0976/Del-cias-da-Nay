class_name FonteLuz
extends Node2D
## Uma luz que PROTEGE (tocha, lampião, fogueira...).
## Junta duas coisas: o brilho visível (LuzFake, pixelado e seguro no celular)
## e o registro na Iluminacao (para os monstros saberem que ali tem luz).
##
## duracao < 0 = dura para sempre (até desligar). Quando acaba, a luz apaga sozinha.

signal apagou

var raio_protecao := 50.0
var duracao := -1.0
var ligada := true:
	set(v):
		ligada = v
		if _luz:
			_luz.visible = v
var _luz: LuzFake


static func criar(raio: float, cor: Color, tempo := -1.0, tremer := 0.0) -> FonteLuz:
	var f := FonteLuz.new()
	f.raio_protecao = raio * 0.8
	f.duracao = tempo
	f._luz = LuzFake.new()
	f._luz.raio = raio
	f._luz.cor = cor
	f._luz.tremer = tremer
	f.add_child(f._luz)
	return f


## BUG CORRIGIDO: antes registrava só no _ready. Quando o jogador entra/sai da
## cabana, ele é "trocado de pai" (reparent) e a luz saía da lista para sempre.
## Agora ela entra na lista toda vez que entra na árvore.
func _enter_tree() -> void:
	Iluminacao.registrar(self)


func _exit_tree() -> void:
	Iluminacao.remover(self)


func ativa() -> bool:
	return ligada and is_visible_in_tree()


func _process(delta: float) -> void:
	if not ligada or duracao < 0.0:
		return
	duracao -= delta
	if duracao <= 10.0 and _luz:  # acabando: pisca
		_luz.energia = 0.5 + 0.5 * absf(sin(duracao * 8.0))
	if duracao <= 0.0:
		ligada = false
		apagou.emit()


func definir_raio(raio: float) -> void:
	raio_protecao = raio * 0.8
	if _luz:
		_luz.raio = raio


func definir_cor(cor: Color) -> void:
	if _luz:
		_luz.cor = cor
