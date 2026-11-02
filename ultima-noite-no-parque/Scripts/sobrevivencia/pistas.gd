class_name Pistas
extends RefCounted
## =============================================================================
##  MICRO-PISTAS E O RESGATE DOS AMIGOS (v11)
## =============================================================================
## Não existe mais "o resgate chega em 5 dias". Agora a história é:
##   - Pelo parque inteiro tem pequenas PISTAS (um brilhinho no chão). Algumas
##     são dos seus amigos (Marina, Rafa e Lucas), outras são de pessoas que
##     visitaram o parque antes (as mesmas dos cartazes de desaparecido).
##   - Achou as 3 pistas de um amigo? Agora você sabe ONDE ele está.
##   - Cada resgate tem uma condição (machado, chave, luz...).
##   - Com os 3 salvos, vocês fogem de carro, de dia.
##
## amigo = "" → pista de outro visitante (história do parque)
## item   = o que você ganha ao examinar (ou "")
## =============================================================================

const POR_AMIGO := 3

const LISTA := [
	# ---------------- MARINA (presa na guarita, no norte) ----------------
	{"pos": Vector2(980, 250), "amigo": "marina", "item": "",
	"texto": "Um elástico de cabelo roxo, da Marina, preso num arbusto. Os galhos estão quebrados na direção NORTE."},
	{"pos": Vector2(1330, -740), "amigo": "marina", "item": "",
	"texto": "Marcas de arrasto na terra e pegadas pequenas. Vão para o norte, pela trilha… na direção da guarita."},
	{"pos": Vector2(1760, -850), "amigo": "marina", "item": "",
	"texto": "O celular da Marina, sem bateria. Na tela rachada, a última foto: a GUARITA, de noite, com raízes pretas saindo do chão."},
	# ---------------- RAFA (trancado na casa de barcos) ----------------
	{"pos": Vector2(1390, -230), "amigo": "rafa", "item": "",
	"texto": "Uma palheta de violão do Rafa, afundada na lama da margem do lago."},
	{"pos": Vector2(-330, 760), "amigo": "rafa", "item": "chave_barcos",
	"texto": "No acampamento abandonado: uma chave enferrujada num chaveiro de bóia escrito \"CASA DE BARCOS\". Você guarda a chave."},
	{"pos": Vector2(1040, -520), "amigo": "rafa", "item": "",
	"texto": "Uma corda de violão arrebentada, amarrada na maçaneta da casa de barcos. Lá dentro, alguém bate na madeira: toc… toc…"},
	# ---------------- LUCAS (na caverna, a sudeste) ----------------
	{"pos": Vector2(1420, 420), "amigo": "lucas", "item": "",
	"texto": "O boné do Lucas, molhado de orvalho, no fim da trilha das pegadas. A trilha continua para o SUDESTE."},
	{"pos": Vector2(1820, 620), "amigo": "lucas", "item": "",
	"texto": "Numa pedra, rabiscado com carvão, na letra do Lucas: \"tá escuro aqui embaixo. tragam LUZ.\""},
	{"pos": Vector2(2010, 800), "amigo": "lucas", "item": "",
	"texto": "Na entrada da caverna: o tênis do Lucas. Lá do fundo do escuro vem uma respiração fraca."},
	# ---------------- OUTROS VISITANTES (a história do parque) ----------------
	{"pos": Vector2(-820, -420), "amigo": "", "item": "agua",
	"texto": "Um cantil amassado com \"H.D.\" gravado. Helena Duarte, 1987. Ainda tem água dentro."},
	{"pos": Vector2(1450, -330), "amigo": "", "item": "corda",
	"texto": "Duas varinhas de pescar de criança, quebradas, amarradas juntas. João e Pedro, 1999."},
	{"pos": Vector2(1960, -870), "amigo": "", "item": "",
	"texto": "O livro de ronda do guarda Sérgio Mota. Última página: \"Eles levam as pessoas para onde a luz não chega. Mas não as matam logo. ELES ESPERAM.\""},
	{"pos": Vector2(-450, 700), "amigo": "", "item": "bateria",
	"texto": "Um walkman com uma fita: a voz da Carolina, tremendo: \"se ouvir alguém chamando seu nome na floresta… não é quem você pensa.\""},
	{"pos": Vector2(300, -930), "amigo": "", "item": "",
	"texto": "Uma placa de madeira arrancada do chão. Alguém pintou por cima: NÃO SIGA AS VOZES."},
	{"pos": Vector2(2250, -250), "amigo": "", "item": "",
	"texto": "Uma foto antiga: quatro jovens na frente da cabana. Os mesmos da foto que estava na mesa… e um deles parece muito com você."},
	{"pos": Vector2(-1000, 950), "amigo": "", "item": "metal",
	"texto": "Marcas de unhas num tronco, a três metros do chão. Embaixo, uma faca de caça enferrujada."},
	{"pos": Vector2(620, 1050), "amigo": "", "item": "",
	"texto": "Um diário de 1962, com páginas coladas de umidade: \"o portão fecha sozinho. sempre fechou. o parque escolhe quem fica.\""},
]

## Onde cada amigo está e o que precisa para salvar
const LOCAL := {
	"marina": Vector2(1900, -880),
	"rafa": Vector2(1130, -462),
	"lucas": Vector2(2080, 774),
}
const LOCAL_NOME := {"marina": "a GUARITA (norte)", "rafa": "a CASA DE BARCOS (lago)", "lucas": "a CAVERNA (sudeste)"}
const REQUISITO := {
	"marina": "Raízes pretas prendem a porta: leve um MACHADO.",
	"rafa": "A porta tem corrente: use a CHAVE da casa de barcos.",
	"lucas": "Lá dentro é escuro demais: leve LUZ acesa (lanterna ou tocha).",
}
const FALAS := {
	"marina": ["Eu sabia que você vinha. Eu SABIA.", "Fica perto da luz. Eles odeiam luz.", "Quando a gente sair daqui, eu nunca mais acampo."],
	"rafa": ["Valeu, irmão. Achei que ia morrer naquela casa de barcos.", "Eles ficavam batendo na porta. A noite toda.", "Se der, a gente sai de carro. Eu cuido do portão."],
	"lucas": ["Eu segui uma luz no lago… achei que era vocês.", "Desculpa. Eu juro que eu tenho senso de direção.", "Aquilo lá embaixo sabia o meu nome."],
}


## Desenha o brilhinho de uma pista no chão (um objeto pequeno + faísca).
static func criar_no(i: int) -> Node2D:
	var d: Dictionary = LISTA[i]
	var n := Node2D.new()
	n.name = "Pista_%d" % i
	n.position = d["pos"]
	var cor := Color(0.95, 0.85, 0.45) if d["amigo"] != "" else Color(0.75, 0.85, 1.0)
	n.draw.connect(func():
		n.draw_rect(Rect2(-3, -2, 6, 3), Color(0.12, 0.1, 0.08))
		n.draw_rect(Rect2(-2, -3, 4, 2), cor.darkened(0.3))
		var t := Time.get_ticks_msec() / 1000.0 + i
		if fmod(t, 2.0) < 0.5:   # faísca piscando (a cada 2 s)
			n.draw_rect(Rect2(-1, -7, 1, 3), cor)
			n.draw_rect(Rect2(-2, -6, 3, 1), cor))
	var it := Interagivel.criar("pista_%d" % i, Vector2(0, -2), 14.0, "EXAMINAR")
	n.add_child(it)
	return n
