class_name StatusJogador
extends RefCounted
## OS 3 INDICADORES (+ ESTRESSE)
## (v8: a SEDE foi tirada para deixar o jogo e a tela mais simples)
##
## Vida    → chegou a zero, o jogador morre.
## Fome    → baixa: a energia recupera mais devagar; zerada: perde vida.
## Energia → correr gasta; sem energia não dá para correr. Dormir e água recuperam.
## Estresse (escondido nas barras, aparece como "Mente"): escuro, monstros por perto,
##   fome e falta de sono aumentam. Estresse alto = a visão escurece e aparecem vultos.
##
## Todos vão de 0 a 100.

var vida := 100.0
var fome := 100.0      ## 100 = satisfeito, 0 = morrendo de fome
var energia := 100.0
var estresse := 0.0    ## 0 = calmo, 100 = em pânico

# Velocidades (por segundo de jogo)
const FOME_POR_SEG := 0.17
const CANSACO_POR_SEG := 0.04     ## ficar acordado cansa
const CORRIDA_POR_SEG := 7.0
const DESCANSO_POR_SEG := 2.5     ## parado recupera energia


## Contexto: o que está acontecendo com o jogador agora.
##   correndo, parado, no_escuro, noite, monstro_perto, observador_visivel, em_seguranca
func atualizar(delta: float, ctx: Dictionary) -> void:
	fome = maxf(fome - FOME_POR_SEG * delta, 0.0)
	energia -= CANSACO_POR_SEG * delta
	if ctx.get("correndo", false):
		energia -= CORRIDA_POR_SEG * delta
	elif ctx.get("parado", false):
		var rec := DESCANSO_POR_SEG * (0.4 if fome < 25.0 else 1.0)  # com fome, recupera menos
		energia += rec * delta
	energia = clampf(energia, 0.0, 100.0)

	# Sem comida: perde vida
	if fome <= 0.0:
		vida -= 0.6 * delta

	# Estresse
	var e := 0.0
	if ctx.get("noite", false) and ctx.get("no_escuro", false):
		e += 1.2
	if ctx.get("monstro_perto", false):
		e += 2.5
	if ctx.get("observador_visivel", false):
		e += 1.8
	if fome < 20.0:
		e += 0.5
	if energia < 15.0:
		e += 0.6
	if not ctx.get("no_escuro", false):
		e -= 0.8
	if ctx.get("em_seguranca", false):
		e -= 0.8
	estresse = clampf(estresse + e * delta, 0.0, 100.0)
	if estresse >= 95.0:
		vida -= 0.3 * delta  # pânico total machuca
	vida = clampf(vida, 0.0, 100.0)


func pode_correr() -> bool:
	return energia > 5.0


func morto() -> bool:
	return vida <= 0.0


## 0..1: quanto a visão está prejudicada (para escurecer a tela)
func prejuizo_visao() -> float:
	return clampf((estresse - 50.0) / 50.0, 0.0, 1.0) * 0.6 + clampf((20.0 - energia) / 20.0, 0.0, 1.0) * 0.3


static func rotulo(valor: float, invertido := false) -> String:
	var v := 100.0 - valor if invertido else valor
	if v < 25.0:
		return "Crítico"
	if v < 55.0:
		return "Atenção"
	return "Normal"


func para_dados() -> Dictionary:
	return {"vida": vida, "fome": fome, "energia": energia, "estresse": estresse}


func de_dados(d: Dictionary) -> void:
	vida = float(d.get("vida", 100.0))
	fome = float(d.get("fome", 100.0))
	energia = float(d.get("energia", 100.0))
	estresse = float(d.get("estresse", 0.0))
