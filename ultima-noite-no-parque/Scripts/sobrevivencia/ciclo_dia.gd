class_name CicloDia
extends Node
## CICLO DIA / NOITE
## 1 hora do jogo = SEGUNDOS_POR_HORA segundos de verdade.
## Dia: 6h às 18h (seguro, hora de coletar). Entardecer: 18h–19h (prepare-se!).
## Noite: 19h às 6h (os monstros saem).

signal mudou_fase(fase: String)    ## "dia", "entardecer", "noite", "amanhecer"
signal novo_dia(dia: int)
signal hora_cheia(hora: int)

const SEGUNDOS_POR_HORA := 20.0     ## um dia inteiro = 8 minutos

var dia := 1
var hora := 8.0                      ## 0.0 a 24.0
var fase := "dia"
var velocidade := 1.0                ## 0 = tempo parado (menus), maior = acelera (dormindo)

# Cores do mundo em cada hora (o CanvasModulate usa isto)
const CORES := [
	[0.0, Color(0.21, 0.23, 0.38)],
	[4.5, Color(0.21, 0.23, 0.38)],
	[6.0, Color(0.62, 0.55, 0.66)],
	[8.0, Color(0.92, 0.9, 0.85)],
	[16.0, Color(0.95, 0.9, 0.82)],
	[18.0, Color(0.9, 0.55, 0.42)],
	[19.5, Color(0.28, 0.27, 0.45)],
	[21.0, Color(0.21, 0.23, 0.38)],
	[24.0, Color(0.21, 0.23, 0.38)],
]


func _process(delta: float) -> void:
	avancar(delta * velocidade)


func avancar(segundos: float) -> void:
	var antes := int(hora)
	hora += segundos / SEGUNDOS_POR_HORA
	while hora >= 24.0:
		hora -= 24.0
	if int(hora) != antes:
		hora_cheia.emit(int(hora))
		if int(hora) == 6:
			dia += 1
			novo_dia.emit(dia)
	_atualizar_fase()


func _atualizar_fase() -> void:
	var nova := "dia"
	if hora >= 18.0 and hora < 19.0:
		nova = "entardecer"
	elif hora >= 19.0 or hora < 5.0:
		nova = "noite"
	elif hora >= 5.0 and hora < 6.0:
		nova = "amanhecer"
	if nova != fase:
		fase = nova
		mudou_fase.emit(fase)


func eh_noite() -> bool:
	return fase == "noite"


## Número da noite atual (a noite que começa no dia N é a "noite N").
func noite_numero() -> int:
	return dia if hora >= 12.0 else dia - 1


func cor_ambiente() -> Color:
	for i in CORES.size() - 1:
		var a: Array = CORES[i]
		var b: Array = CORES[i + 1]
		if hora >= a[0] and hora <= b[0]:
			return (a[1] as Color).lerp(b[1], (hora - a[0]) / maxf(b[0] - a[0], 0.001))
	return CORES[0][1]


func texto_hora() -> String:
	return "%02d:%02d" % [int(hora), int(fmod(hora, 1.0) * 60.0)]
