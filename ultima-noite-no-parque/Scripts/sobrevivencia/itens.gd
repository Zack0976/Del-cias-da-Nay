class_name Itens
extends RefCounted
## CATÁLOGO DE ITENS da Parte 2 (sobrevivência).
##
## Cada item tem: nome, quanto empilha num espaço da mochila, tipo e descrição.
## Os ícones são pixel art desenhada por código (12x12), igual ao resto do mundo.
##
## Tipos:
##   "recurso"  = material para criar coisas
##   "consumo"  = come/bebe/usa e some
##   "arma"     = equipa na mão (botão ATACAR)
##   "luz"      = equipa na mão e ilumina
##   "colocar"  = coloca no chão (armadilha, lampião, bancada)
##   "barricada"= reforça porta/janela
##   "jogar"    = arremessa (distração)

const DADOS := {
	# --- recursos básicos ---
	"madeira":  {"nome": "Madeira", "pilha": 10, "tipo": "recurso", "desc": "Galhos, tocos e troncos. Base de quase tudo."},
	"pedra":    {"nome": "Pedra", "pilha": 10, "tipo": "recurso", "desc": "Pesada e útil para ferramentas."},
	"corda":    {"nome": "Corda", "pilha": 6, "tipo": "recurso", "desc": "Amarra barricadas e armadilhas."},
	"metal":    {"nome": "Sucata de metal", "pilha": 6, "tipo": "recurso", "desc": "Pedaços de ferro e latas."},
	"ervas":    {"nome": "Ervas medicinais", "pilha": 6, "tipo": "consumo", "desc": "Curam um pouco e acalmam. (+10 vida, -10 estresse)"},
	"fruta":    {"nome": "Fruta silvestre", "pilha": 6, "tipo": "consumo", "desc": "Mata a fome um pouco. (+20 fome)"},
	"enlatado": {"nome": "Enlatado", "pilha": 4, "tipo": "consumo", "desc": "Comida de verdade. (+45 fome)"},
	"agua":     {"nome": "Garrafa d'água", "pilha": 4, "tipo": "consumo", "desc": "Água limpa: tira o cansaço. (+25 energia)"},
	"fosforos": {"nome": "Fósforos", "pilha": 8, "tipo": "recurso", "desc": "Acende tochas, lampiões e a fogueira."},
	"bateria":  {"nome": "Bateria", "pilha": 4, "tipo": "consumo", "desc": "Recarrega a lanterna."},
	"tecido":   {"nome": "Pano", "pilha": 6, "tipo": "recurso", "desc": "Para tochas, curativos e cordas."},
	"peixe":    {"nome": "Peixe cru", "pilha": 4, "tipo": "consumo", "desc": "Melhor assar na fogueira! Cru: +10 fome, mas pode fazer mal (-5 vida)."},
	# --- feitos à mão ou na bancada ---
	"tocha":     {"nome": "Tocha", "pilha": 3, "tipo": "luz", "desc": "Luz forte por ~6 horas. Gasta 1 fósforo para acender."},
	"barricada": {"nome": "Tábuas pregadas", "pilha": 4, "tipo": "barricada", "desc": "Reforça porta ou janela (+50)."},
	"reforco":   {"nome": "Reforço de metal", "pilha": 3, "tipo": "barricada", "desc": "Reforço pesado (+100). Aguenta o Colosso por mais tempo."},
	"armadilha_corda":   {"nome": "Laço de corda", "pilha": 3, "tipo": "colocar", "desc": "Prende o Rastejante por alguns segundos."},
	"armadilha_estacas": {"nome": "Armadilha de estacas", "pilha": 3, "tipo": "colocar", "desc": "Fere e prende quem pisar. Ótima contra o Colosso."},
	"estaca":    {"nome": "Estaca afiada", "pilha": 1, "tipo": "arma", "desc": "Arma simples (20 de dano). Quebra depois de 8 golpes."},
	"lanca":     {"nome": "Lança de pedra", "pilha": 1, "tipo": "arma", "desc": "Alcance maior (28 de dano). Quebra depois de 15 golpes."},
	"bastao":    {"nome": "Bastão reforçado", "pilha": 1, "tipo": "arma", "desc": "Arma forte (35 de dano) e resistente."},
	"kit":       {"nome": "Kit médico", "pilha": 3, "tipo": "consumo", "desc": "Cura bastante. (+40 vida)"},
	"lampiao":   {"nome": "Lampião", "pilha": 2, "tipo": "colocar", "desc": "Luz fixa até o amanhecer. Afasta a Sombra."},
	"chocalho":  {"nome": "Lata-chocalho", "pilha": 3, "tipo": "jogar", "desc": "Jogue longe: o barulho atrai os monstros para lá."},
	"sinalizador": {"nome": "Sinalizador", "pilha": 3, "tipo": "jogar", "desc": "Jogue no chão: luz vermelha MUITO forte por 40 s. Espanta Observador e Sombra."},
	"bancada":   {"nome": "Bancada", "pilha": 1, "tipo": "colocar", "desc": "Coloque dentro da cabana para criar coisas melhores."},
	"vara_pescar": {"nome": "Vara de pescar", "pilha": 1, "tipo": "ferramenta", "desc": "Chegue na beira do lago e escolha PESCAR. Aguenta 12 pescarias."},
	"peixe_assado": {"nome": "Peixe assado", "pilha": 4, "tipo": "consumo", "desc": "Delicioso. (+40 fome, +5 vida)"},
	"ensopado":  {"nome": "Ensopado", "pilha": 2, "tipo": "consumo", "desc": "Comida quente. (+50 fome, +15 vida, +20 energia)"},
	# --- v10 ---
	"machado":   {"nome": "Machado de pedra", "pilha": 1, "tipo": "ferramenta", "desc": "Chegue perto de uma árvore e toque em CORTAR (+madeira). Também serve de arma (18 de dano). Aguenta 15 cortes."},
	"machado_ferro": {"nome": "Machado de ferro", "pilha": 1, "tipo": "ferramenta", "desc": "Corta árvores com 2 golpes e é uma arma boa (30 de dano). Aguenta 40 cortes."},
	"bandagem":  {"nome": "Bandagem", "pilha": 5, "tipo": "consumo", "desc": "Curativo rápido feito de pano. (+15 vida)"},
	"isca":      {"nome": "Isca", "pilha": 9, "tipo": "recurso", "desc": "Com isca na mochila o peixe morde mais rápido e às vezes vem um PEIXE GRANDE."},
	"covo":      {"nome": "Covo (armadilha de peixe)", "pilha": 2, "tipo": "colocar", "desc": "Coloque na beira do lago (LAGO → COLOCAR COVO). Pega peixes sozinho com o tempo."},
	"peixe_grande": {"nome": "Peixe grande", "pilha": 2, "tipo": "consumo", "desc": "Um peixe enorme. Asse no fogo! Cru: +18 fome, pode fazer mal."},
	"fruta_assada": {"nome": "Fruta assada", "pilha": 6, "tipo": "consumo", "desc": "Docinha e quente. (+25 fome, -5 estresse)"},
	"pagina":    {"nome": "Página do diário", "pilha": 6, "tipo": "recurso", "desc": "Páginas do caderno do Lucas. Use para ler."},
	"cha":       {"nome": "Chá de ervas", "pilha": 3, "tipo": "consumo", "desc": "Acalma a mente. (-35 estresse, +10 energia)"},
	# --- itens da Parte 1 ---
	"lanterna":  {"nome": "Lanterna", "pilha": 1, "tipo": "luz", "desc": "Da Marina. Gasta bateria."},
	"chave_barcos": {"nome": "Chave da casa de barcos", "pilha": 1, "tipo": "recurso", "desc": "Chave enferrujada. Abre a corrente da casa de barcos, no lago."},
	"chave":     {"nome": "Chave da cabana", "pilha": 1, "tipo": "recurso", "desc": "Abre a porta da cabana."},
}


static func nome(id: String) -> String:
	return DADOS.get(id, {}).get("nome", id)


static func pilha(id: String) -> int:
	return int(DADOS.get(id, {}).get("pilha", 1))


static func tipo(id: String) -> String:
	return DADOS.get(id, {}).get("tipo", "recurso")


static func desc(id: String) -> String:
	return DADOS.get(id, {}).get("desc", "")


# ---------------------------------------------------------------
# ÍCONES (v9): 16x16, esculpidos e iluminados por pixel (relevo.gd)
# ---------------------------------------------------------------
static var _icones := {}

const C_MADEIRA := [Color("1f130a"), Color("3d2716"), Color("5c3e22"), Color("80592f"), Color("a87c46")]
const C_ANEL := [Color("5a4024"), Color("8a6a40"), Color("b09060"), Color("cbb084"), Color("e2cda0")]
const C_PEDRA := [Color("1c1c20"), Color("36363c"), Color("55555c"), Color("7a7a82"), Color("a4a4ac")]
const C_METAL := [Color("1a1c20"), Color("3a3e46"), Color("5e636e"), Color("8f95a2"), Color("c9ced8")]
const C_CORDA := [Color("3a2a16"), Color("6a5030"), Color("9a7a4a"), Color("c0a06a"), Color("e0c890")]
const C_VERDE := [Color("0e200c"), Color("1e4018"), Color("2e6224"), Color("4a8a36"), Color("7ab858")]
const C_VERMELHO := [Color("2a0508"), Color("5a0c12"), Color("8a1a20"), Color("bb3038"), Color("e86a6a")]
const C_AZUL := [Color("0a1830"), Color("16345a"), Color("2a5a8a"), Color("4a8ac0"), Color("9ad0f0")]
const C_PANO := [Color("2a221a"), Color("4a3e32"), Color("6e5f4e"), Color("94836e"), Color("b8a890")]
const C_BRANCO := [Color("4a4640"), Color("7a766e"), Color("aaa69c"), Color("d6d2c8"), Color("f6f4ee")]
const C_OURO := [Color("3a2a08"), Color("6a5012"), Color("a07c20"), Color("d0aa38"), Color("f6dc78")]
const C_PRETO := [Color("08080a"), Color("16161a"), Color("26262c"), Color("3a3a42"), Color("54545e")]
const C_PEIXE := [Color("10202a"), Color("244656"), Color("3e7088"), Color("68a0b4"), Color("b8e0e8")]
const C_ASSADO := [Color("2a1206"), Color("5a2a0e"), Color("8a4a1a"), Color("b8722e"), Color("e0a85a")]


static func icone(id: String) -> Texture2D:
	if _icones.has(id):
		return _icones[id]
	var r := Relevo.new(16, 16)
	for d in [["madeira", C_MADEIRA, 0.1], ["anel", C_ANEL, 0.0], ["pedra", C_PEDRA, 0.2], ["metal", C_METAL, 0.9],
			["corda", C_CORDA, 0.1], ["verde", C_VERDE, 0.2], ["vermelho", C_VERMELHO, 0.6], ["azul", C_AZUL, 0.9],
			["pano", C_PANO, 0.0], ["branco", C_BRANCO, 0.3], ["ouro", C_OURO, 0.9], ["preto", C_PRETO, 0.5],
			["peixe", C_PEIXE, 0.8], ["assado", C_ASSADO, 0.4]]:
		r.material(d[0], d[1], false, d[2])
	r.material("fogo", [Color("ffcf4a")], true)
	r.material("fogo2", [Color("ff7a1a")], true)
	r.material("luz", [Color("fff2b0")], true)
	r.material("olho", [Color("101010")], true)
	match id:
		"madeira":
			r.tubo(Vector2(2.5, 10.5), Vector2(12.5, 11.5), 2.4, 2.4, 0, "madeira")
			r.tubo(Vector2(3.5, 5.5), Vector2(13, 6.5), 2.4, 2.4, 1, "madeira")
			r.bola(Vector2(13, 6.5), Vector2(2.2, 2.2), 2, 3, "anel")
			r.bola(Vector2(12.5, 11.5), Vector2(2.2, 2.2), 2, 2, "anel")
			r.pintar(Vector2(13, 6.5), "madeira", 3.5)
			r.pintar(Vector2(12.5, 11.5), "madeira", 2.5)
		"pedra":
			r.bola(Vector2(7.5, 9.5), Vector2(6, 4.5), 4.5, 0, "pedra")
			r.bola(Vector2(11.5, 11.5), Vector2(3, 2.5), 2.5, 1, "pedra")
		"corda":
			for k in 14:
				var ang := TAU * k / 14.0
				r.bola(Vector2(8, 8) + Vector2(cos(ang) * 4.6, sin(ang) * 3.6), Vector2(1.6, 1.6), 1.6, 0, "corda")
			r.tubo(Vector2(12, 10), Vector2(14.5, 14.5), 1.2, 1.0, 1, "corda")
		"metal":
			r.tubo(Vector2(2.5, 12.5), Vector2(11.5, 4), 1.8, 1.8, 0, "metal")
			r.caixa(Rect2(8, 9, 6, 5), 1.5, 0.5, "metal")
			r.bola(Vector2(11, 11.5), Vector2(1, 1), 1, 2.5, "pedra")
			r.pintar(Vector2(4, 11), "assado", 2.0)
		"ervas":
			r.curva(Vector2(8, 15), Vector2(8, 10), Vector2(8, 4), 0.6, 0.5, 0, "verde")
			for d in [[Vector2(5, 6), -1], [Vector2(11, 7), 1], [Vector2(5, 11), -1], [Vector2(11, 12), 1], [Vector2(8, 2.5), 0]]:
				r.bola(d[0], Vector2(2.5, 1.6), 1.8, 1, "verde")
		"fruta":
			r.bola(Vector2(5.5, 10), Vector2(3, 3), 3, 0, "vermelho")
			r.bola(Vector2(10.5, 10.5), Vector2(3, 3), 3, 0, "vermelho")
			r.bola(Vector2(8, 6.5), Vector2(3, 3), 3, 1, "vermelho")
			r.bola(Vector2(10, 2.5), Vector2(2.5, 1.3), 1, 3, "verde")
		"enlatado":
			r.caixa(Rect2(3.5, 3, 9, 11), 4, 0, "metal", 2.5)
			for y in range(6, 11):
				for x in range(4, 12):
					r.pintar(Vector2(x, y), "vermelho", 0.1)
			r.caixa(Rect2(3.5, 2, 9, 2), 2, 4, "metal")
		"agua":
			r.caixa(Rect2(4.5, 5, 7, 10), 4, 0, "azul", 2.5)
			r.caixa(Rect2(6.5, 2, 3, 3), 2, 1, "azul")
			r.caixa(Rect2(6, 0.5, 4, 2), 2, 2, "branco")
		"fosforos":
			r.caixa(Rect2(2, 7, 12, 7), 2, 0, "ouro")
			for k in 3:
				r.tubo(Vector2(4 + k * 3, 10), Vector2(5 + k * 3, 3), 0.6, 0.6, 2.5, "madeira")
				r.bola(Vector2(5 + k * 3, 2.5), Vector2(1.1, 1.3), 1, 3, "vermelho")
		"bateria":
			r.caixa(Rect2(4.5, 3, 7, 12), 3, 0, "preto", 2.5)
			r.caixa(Rect2(4.5, 3, 7, 4), 3.2, 0, "ouro", 2.5)
			r.caixa(Rect2(6.5, 1, 3, 2), 1.5, 1, "metal")
		"tecido":
			r.caixa(Rect2(2, 4, 12, 4), 2, 1, "pano")
			r.caixa(Rect2(2, 8, 12, 4), 2, 0, "pano")
			r.caixa(Rect2(3, 11, 11, 3), 2, 0.5, "pano")
		"machado", "machado_ferro":
			r.tubo(Vector2(3, 14.5), Vector2(10.5, 3.5), 1.1, 1.1, 0, "madeira")
			var lamina := "pedra" if id == "machado" else "metal"
			r.bola(Vector2(11, 4.5), Vector2(3.6, 2.8), 2.2, 1.5, lamina)
			r.tubo(Vector2(9, 2), Vector2(14.5, 7.5), 1.2, 1.0, 1.5, lamina)
			r.tubo(Vector2(9.5, 4.5), Vector2(11, 6), 0.9, 0.9, 3, "corda")
		"bandagem":
			for k in 9:
				var ang := TAU * k / 9.0
				r.bola(Vector2(8, 8) + Vector2(cos(ang) * 3.2, sin(ang) * 3.2), Vector2(2.4, 2.4), 2.0, 0, "branco")
			r.bola(Vector2(8, 8), Vector2(1.6, 1.6), 1, 1, "pano")
			r.tubo(Vector2(10, 11), Vector2(14.5, 14), 1.4, 1.2, 0.5, "branco")
			r.caixa(Rect2(11.5, 11.5, 2, 1), 0.5, 2, "vermelho")
		"isca":
			r.curva(Vector2(3, 11), Vector2(8, 4), Vector2(13, 11), 1.3, 1.0, 0, "vermelho", 6)
			r.curva(Vector2(5, 13), Vector2(9, 9), Vector2(13, 14), 1.0, 0.8, 0.5, "assado", 5)
		"covo":
			r.caixa(Rect2(2, 4, 12, 10), 4, 0, "madeira", 3)
			for x in [4, 7, 10, 13]:
				for y in range(5, 14):
					r.pintar(Vector2(x, y), "corda", 0.6)
			r.bola(Vector2(3, 9), Vector2(1.6, 2.5), 1, 4, "preto")
		"pagina":
			r.caixa(Rect2(3, 2, 10, 13), 1, 0, "branco", 1)
			for y in [5, 7, 9, 11]:
				for x in range(5, 11):
					r.pintar(Vector2(x, y), "azul", 0.2)
			r.pintar(Vector2(11, 13), "vermelho", 0.3)
		"fruta_assada":
			r.bola(Vector2(6, 10), Vector2(3, 3), 3, 0, "assado")
			r.bola(Vector2(10.5, 9), Vector2(3, 3), 3, 0.5, "assado")
			r.tubo(Vector2(1, 14), Vector2(15, 4), 0.6, 0.6, 3.5, "madeira")
		"peixe_grande":
			r.bola(Vector2(7, 8), Vector2(6.5, 4.2), 3.5, 0, "peixe")
			r.tubo(Vector2(12.5, 8), Vector2(15, 4), 1.8, 0.7, 0, "peixe")
			r.tubo(Vector2(12.5, 8), Vector2(15, 12), 1.8, 0.7, 0, "peixe")
			r.pintar(Vector2(3, 7), "olho", 3.6)
			for x in [6, 9]:
				r.pintar(Vector2(x, 10), "ouro", 3.5)
		"peixe", "peixe_assado":
			var m := "peixe" if id == "peixe" else "assado"
			r.bola(Vector2(7, 8), Vector2(5.5, 3), 3, 0, m)
			r.tubo(Vector2(11.5, 8), Vector2(14.5, 5.5), 1.4, 0.6, 0, m)
			r.tubo(Vector2(11.5, 8), Vector2(14.5, 10.5), 1.4, 0.6, 0, m)
			r.pintar(Vector2(4, 7), "olho", 3.2)
			if id == "peixe_assado":
				r.tubo(Vector2(0.5, 13.5), Vector2(15, 3), 0.6, 0.6, 3.5, "madeira")
				for x in [6, 8, 10]:
					r.pintar(Vector2(x, 7), "madeira", 3)
		"tocha":
			r.tubo(Vector2(8, 15), Vector2(8, 6), 1.2, 1.4, 0, "madeira")
			r.bola(Vector2(8, 5.5), Vector2(2.4, 2), 2, 1, "pano")
			for p in [Vector2(8, 2), Vector2(7, 3), Vector2(9, 3), Vector2(8, 1), Vector2(8, 3)]:
				r.pintar(p, "fogo", 3)
			r.pintar(Vector2(7, 2), "fogo2", 3)
			r.pintar(Vector2(9, 2), "fogo2", 3)
		"barricada":
			r.caixa(Rect2(1, 3, 14, 4), 2, 1, "madeira")
			r.caixa(Rect2(1, 9, 14, 4), 2, 1, "madeira")
			r.caixa(Rect2(4, 1, 3, 14), 2, 0, "madeira")
			r.caixa(Rect2(10, 1, 3, 14), 2, 0, "madeira")
			for p in [Vector2(5, 5), Vector2(11, 5), Vector2(5, 11), Vector2(11, 11)]:
				r.pintar(p, "metal", 3)
		"reforco":
			r.caixa(Rect2(1.5, 2.5, 13, 11), 2.5, 0, "metal", 2)
			for p in [Vector2(3.5, 4.5), Vector2(12, 4.5), Vector2(3.5, 11.5), Vector2(12, 11.5)]:
				r.bola(p, Vector2(1, 1), 1, 2.5, "pedra")
		"armadilha_corda":
			for k in 12:
				var ang := TAU * k / 12.0
				r.bola(Vector2(8, 10) + Vector2(cos(ang) * 5.5, sin(ang) * 3.2), Vector2(1.1, 1.1), 1, 0, "corda")
			r.tubo(Vector2(8, 7), Vector2(8, 1), 0.9, 0.7, 1, "corda")
		"armadilha_estacas":
			r.caixa(Rect2(1, 11, 14, 4), 2, 0, "madeira")
			for k in 4:
				r.tubo(Vector2(2.5 + k * 3.6, 12), Vector2(2.5 + k * 3.6, 3), 1.1, 0.3, 1.5, "anel")
		"estaca":
			r.tubo(Vector2(2, 14), Vector2(12, 4), 1.4, 1.1, 0, "madeira")
			r.tubo(Vector2(12, 4), Vector2(14.5, 1.5), 1.1, 0.3, 0, "anel")
		"lanca":
			r.tubo(Vector2(1, 15), Vector2(11, 5), 0.9, 0.9, 0, "madeira")
			r.tubo(Vector2(10, 6), Vector2(11.5, 4.5), 1.3, 1.3, 1, "corda")
			r.bola(Vector2(13, 3), Vector2(2.2, 2.2), 2, 1, "pedra")
			r.tubo(Vector2(13, 3), Vector2(15, 1), 1.3, 0.3, 1, "pedra")
		"bastao":
			r.tubo(Vector2(2, 14), Vector2(11, 5), 1.4, 2.0, 0, "madeira")
			r.tubo(Vector2(9, 7), Vector2(13, 3), 2.4, 2.4, 1, "metal")
			r.tubo(Vector2(5, 11), Vector2(6, 10), 1.6, 1.6, 1, "corda")
		"kit":
			r.caixa(Rect2(1.5, 3.5, 13, 10), 3, 0, "branco", 2)
			r.caixa(Rect2(6, 1.5, 4, 2.5), 1.5, 0.5, "branco")
			r.caixa(Rect2(6.5, 5.5, 3, 6), 1, 3, "vermelho")
			r.caixa(Rect2(5, 7, 6, 3), 1, 3, "vermelho")
		"lampiao":
			r.caixa(Rect2(4, 4, 8, 9), 3, 0, "preto", 1.5)
			for y in range(6, 11):
				for x in range(6, 10):
					r.pintar(Vector2(x, y), "luz", 0.5)
			r.caixa(Rect2(3, 12, 10, 3), 2, 0.5, "preto")
			r.curva(Vector2(5, 4), Vector2(8, -0.5), Vector2(11, 4), 0.6, 0.6, 1, "metal", 5)
		"chocalho":
			r.caixa(Rect2(4, 3, 8, 11), 4, 0, "metal", 2.5)
			r.bola(Vector2(7, 8), Vector2(1.3, 1.3), 1, 4.5, "pedra")
			r.bola(Vector2(9.5, 10), Vector2(1.3, 1.3), 1, 4.5, "pedra")
			r.tubo(Vector2(8, 3), Vector2(8, 0.5), 0.5, 0.5, 2, "corda")
		"sinalizador":
			r.tubo(Vector2(4, 13), Vector2(11, 6), 2.0, 2.0, 0, "vermelho")
			r.tubo(Vector2(10, 7), Vector2(12, 5), 2.1, 2.1, 0.5, "branco")
			for p in [Vector2(13, 3), Vector2(14, 2), Vector2(13, 2), Vector2(12, 3)]:
				r.pintar(p, "fogo2", 4)
			r.pintar(Vector2(13, 4), "fogo", 4)
		"bancada":
			r.caixa(Rect2(1, 5, 14, 4), 2.5, 2, "madeira")
			r.tubo(Vector2(3, 9), Vector2(3, 15), 1.0, 1.0, 0, "madeira")
			r.tubo(Vector2(13, 9), Vector2(13, 15), 1.0, 1.0, 0, "madeira")
			r.caixa(Rect2(3, 2, 5, 3), 1.5, 4, "metal")
			r.tubo(Vector2(10, 4.5), Vector2(13, 1.5), 0.6, 0.6, 4.5, "madeira")
		"vara_pescar":
			r.curva(Vector2(2, 15), Vector2(7, 7), Vector2(14.5, 1.5), 1.0, 0.4, 0, "madeira", 6)
			r.bola(Vector2(4.5, 11.5), Vector2(1.6, 1.6), 1.5, 1, "metal")
			for y in range(2, 13):
				r.pintar(Vector2(14.5, y), "branco", 0.2)
			r.bola(Vector2(14.5, 13.5), Vector2(1.2, 1.2), 1, 0.5, "vermelho")
		"ensopado":
			r.bola(Vector2(8, 10), Vector2(6.5, 4.5), 3, 0, "madeira")
			r.bola(Vector2(8, 8.5), Vector2(5, 2), 1, 2.5, "assado")
			r.pintar(Vector2(6, 8), "verde", 3.5)
			r.pintar(Vector2(10, 9), "peixe", 3.5)
			for p in [Vector2(6, 3), Vector2(7, 1), Vector2(10, 4), Vector2(9, 2)]:
				r.pintar(p, "branco", 0.1)
		"cha":
			r.caixa(Rect2(3, 6, 8, 8), 3, 0, "branco", 2)
			r.curva(Vector2(11, 8), Vector2(14, 10), Vector2(11, 12), 0.8, 0.8, 1, "branco", 4)
			for x in range(4, 10):
				r.pintar(Vector2(x, 6), "verde", 3.2)
			for p in [Vector2(5, 3), Vector2(6, 1), Vector2(8, 4), Vector2(9, 2)]:
				r.pintar(p, "branco", 0.1)
		"lanterna":
			r.tubo(Vector2(2, 9), Vector2(9, 9), 2.0, 2.0, 0, "preto")
			r.caixa(Rect2(9, 5, 4, 8), 3, 0, "metal", 1.5)
			for y in range(6, 12):
				r.pintar(Vector2(13, y), "luz", 3)
			r.caixa(Rect2(4, 6, 2, 1.5), 1, 2, "vermelho")
		"chave", "chave_barcos":
			for k in 10:
				var ang := TAU * k / 10.0
				r.bola(Vector2(4.5, 8) + Vector2(cos(ang) * 2.6, sin(ang) * 2.6), Vector2(1, 1), 1, 0, "ouro")
			r.tubo(Vector2(7, 8), Vector2(14, 8), 1.0, 1.0, 0, "ouro")
			r.tubo(Vector2(12, 8), Vector2(12, 11), 0.8, 0.8, 0, "ouro")
			r.tubo(Vector2(14, 8), Vector2(14, 10.5), 0.8, 0.8, 0, "ouro")
		_:
			r.bola(Vector2(8, 8), Vector2(5, 5), 5, 0, "vermelho")
	var t := r.textura(Color(0.02, 0.02, 0.03))
	_icones[id] = t
	return t
