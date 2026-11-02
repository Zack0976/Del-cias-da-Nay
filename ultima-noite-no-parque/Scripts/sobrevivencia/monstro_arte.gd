class_name MonstroArte
extends RefCounted
## DESENHO DOS MONSTROS (pixel art esculpida e iluminada — veja relevo.gd)
##
## Cada monstro tem 4 quadros de animação. Os quadros são criados uma vez só
## (ficam no cache) e depois o monstro só troca de imagem: leve no celular.
## Todos olham para a DIREITA; o monstro espelha a imagem quando anda para a esquerda.

static var _cache := {}

# Paletas (escuro → claro)
const PELE_CINZA := [Color("151219"), Color("2e2a35"), Color("534d5c"), Color("857e8f"), Color("bdb6c4")]
const CARAPACA := [Color("0f0b0a"), Color("251a17"), Color("42302a"), Color("654a3e"), Color("8f7262")]
const OSSO := [Color("3a3328"), Color("6e6452"), Color("a69a80"), Color("d4cab0"), Color("f2ecdc")]
const CASCA := [Color("0e0806"), Color("22150d"), Color("3a2617"), Color("573a24"), Color("7a5636")]
const MUSGO := [Color("0d1a0c"), Color("1c3318"), Color("2f5226"), Color("4a7534"), Color("6f9a48")]
const PEDRA := [Color("17171b"), Color("2f2f36"), Color("4d4d56"), Color("71717c"), Color("9d9da8")]
const FUMACA := [Color("030206"), Color("0b0814"), Color("171127"), Color("261c3d"), Color("3b2c5c")]
const ESCAMA := [Color("050c0a"), Color("0e1f1b"), Color("1c3a32"), Color("2f5a4a"), Color("4f8270")]
const BARBATANA := [Color("1a0d16"), Color("3a1a2c"), Color("5c2a40"), Color("86405a"), Color("b0687e")]
const BOCA := [Color("120204"), Color("2a0508"), Color("4a0a10"), Color("6e1418"), Color("8e2228")]


static func quadros(tipo: String) -> Array:
	if _cache.has(tipo):
		return _cache[tipo]
	var lista: Array = []
	for f in 4:
		var r: Relevo
		match tipo:
			"observador": r = _observador(f)
			"rastejante": r = _rastejante(f)
			"colosso": r = _colosso(f)
			"sombra": r = _sombra(f)
			"uivador": r = _uivador(f)
			"imitador": r = _imitador(f)
			_: r = _agua(f)
		lista.append(r.textura(Color(0.02, 0.01, 0.03) if tipo != "sombra" else Color(0, 0, 0, 0.6)))
	_cache[tipo] = lista
	return lista


## Ponto dos "pés" dentro da imagem (para desenhar no lugar certo).
static func base(tipo: String) -> Vector2:
	var t: Texture2D = quadros(tipo)[0]
	return Vector2(t.get_width() / 2.0, t.get_height() - 1.0)


# ---------------------------------------------------------------
# O OBSERVADOR — alto, magro, pálido. Braços que quase tocam o chão,
# rosto liso com UM olho vertical. Fica parado, balançando devagar.
# ---------------------------------------------------------------
static func _observador(f: int) -> Relevo:
	var r := Relevo.new(28, 52)
	r.material("pele", PELE_CINZA, false, 0.25)
	r.material("sombra", [Color("0b090e"), Color("151219"), Color("1f1b25"), Color("2e2a35"), Color("3a3542")])
	r.material("olho", [Color("bff6ff")], true)
	r.material("boca", BOCA)
	r.material("dente", OSSO)
	var bal := sin(f * PI / 2.0) * 0.9
	# pernas finas e compridas, joelhos marcados
	r.tubo(Vector2(11, 50), Vector2(11.5, 41), 0.9, 1.2, 0, "pele")
	r.tubo(Vector2(11.5, 41), Vector2(12, 33), 1.3, 1.5, 0, "pele")
	r.tubo(Vector2(16, 50), Vector2(15.5, 41), 0.9, 1.2, 0, "pele")
	r.tubo(Vector2(15.5, 41), Vector2(15, 33), 1.3, 1.5, 0, "pele")
	# tronco magro e curvado para a frente (costelas)
	r.bola(Vector2(13.5, 32), Vector2(3.0, 2.2), 2.2, 0, "pele")
	r.curva(Vector2(13.5, 31), Vector2(13.5, 24), Vector2(15 + bal * 0.3, 18), 2.4, 3.0, 0, "pele")
	for k in 4:
		r.pintar(Vector2(12, 21 + k * 2.4), "sombra")
		r.pintar(Vector2(15.5, 21 + k * 2.4), "sombra")
	# braços enormes, abertos, quase tocando o chão
	r.bola(Vector2(10, 19), Vector2(2.0, 1.6), 2, 0.5, "pele")
	r.bola(Vector2(19.5, 19), Vector2(2.0, 1.6), 2, 0.5, "pele")
	r.curva(Vector2(9, 19), Vector2(4 - bal, 31), Vector2(3.5 - bal * 1.5, 45), 1.3, 0.8, 1, "pele")
	r.curva(Vector2(20.5, 19), Vector2(25 + bal, 31), Vector2(24.5 + bal * 1.5, 45), 1.3, 0.8, 1, "pele")
	for d in [-1, 0, 1]:  # dedos compridos
		r.tubo(Vector2(3.5 - bal * 1.5, 45), Vector2(3.5 - bal * 1.5 + d * 1.2, 49), 0.45, 0.35, 1, "pele")
		r.tubo(Vector2(24.5 + bal * 1.5, 45), Vector2(24.5 + bal * 1.5 + d * 1.2, 49), 0.45, 0.35, 1, "pele")
	# pescoço comprido e cabeça alongada, inclinada para a frente
	var cab := Vector2(16 + bal * 0.6, 7.5)
	r.tubo(Vector2(15 + bal * 0.3, 17), cab + Vector2(0, 4), 1.1, 1.3, 1, "pele")
	r.bola(cab, Vector2(3.4, 5.6), 4, 1, "pele")
	# rosto: buraco escuro com UM olho vertical, e uma boca rasgada com dentes
	var cx := roundi(cab.x)
	for y in range(3, 9):
		r.pintar(Vector2(cx - 1, y), "sombra", 1)
		r.pintar(Vector2(cx + 1, y), "sombra", 1)
	for y in range(4, 8):
		r.pintar(Vector2(cx, y), "olho", 1.5)
	for x in range(cx - 2, cx + 3):
		r.pintar(Vector2(x, 11), "boca", 1)
	for x in [cx - 2, cx, cx + 2]:
		r.pintar(Vector2(x, 10), "dente", 1.2)
	return r


# ---------------------------------------------------------------
# O RASTEJANTE — corpo comprido em gomos (carapaça), muitas patas finas,
# mandíbulas de osso e 3 olhinhos vermelhos. As patas andam em onda.
# ---------------------------------------------------------------
static func _rastejante(f: int) -> Relevo:
	var r := Relevo.new(44, 22)
	r.material("casco", CARAPACA, false, 0.6)
	r.material("pata", [Color("0c0a09"), Color("1e1a17"), Color("332c27"), Color("4d4239"), Color("6a5d50")])
	r.material("osso", OSSO, false, 0.4)
	r.material("olho", [Color("ff3a2a")], true)
	r.material("boca", BOCA)
	# patas (atrás do corpo) — cada gomo tem 2 patas, que mexem em onda
	for k in 6:
		var x := 6.0 + k * 5.0
		var fase := sin((f + k) * PI / 2.0)
		r.tubo(Vector2(x, 13), Vector2(x - 3 + fase * 2.0, 20), 0.9, 0.6, 0, "pata")
		r.tubo(Vector2(x, 10), Vector2(x - 2 - fase * 2.0, 4.5), 0.8, 0.5, -1, "pata")
	# gomos do corpo (do rabo para a cabeça)
	for k in 7:
		var x := 5.0 + k * 4.6
		var ond := sin((f * 0.8 + k) * 1.3) * 0.6
		var raio := 3.2 + k * 0.35
		r.bola(Vector2(x, 12 + ond), Vector2(raio, raio * 0.85), raio, 1, "casco")
	# cabeça
	r.bola(Vector2(36.5, 11.5), Vector2(5.5, 4.8), 5, 2, "casco")
	r.bola(Vector2(35, 8.5), Vector2(3, 2), 2, 5, "casco")  # couraça da cabeça
	# mandíbulas (abrem e fecham)
	var abre := 1.0 if f % 2 == 0 else 2.2
	r.curva(Vector2(40, 10), Vector2(43, 9 - abre), Vector2(43.5, 11.5 - abre * 0.3), 1.1, 0.4, 5, "osso", 4)
	r.curva(Vector2(40, 14), Vector2(43, 15 + abre), Vector2(43.5, 12.5 + abre * 0.3), 1.1, 0.4, 5, "osso", 4)
	r.pintar(Vector2(41, 12), "boca", 3)
	# 3 olhos vermelhos
	for p in [Vector2(37, 9), Vector2(39, 10), Vector2(38, 12)]:
		r.pintar(p, "olho", 3)
	return r


# ---------------------------------------------------------------
# O COLOSSO — gigante de madeira podre e pedra, coberto de musgo,
# com rachaduras de brasa no peito. Braços que arrastam no chão.
# ---------------------------------------------------------------
static func _colosso(f: int) -> Relevo:
	var r := Relevo.new(58, 64)
	r.material("casca", CASCA, false, 0.1)
	r.material("musgo", MUSGO)
	r.material("pedra", PEDRA, false, 0.3)
	r.material("boca", BOCA)
	r.material("brasa", [Color("ff8a20")], true)
	r.material("brasa2", [Color("ffd25a")], true)
	var passo := sin(f * PI / 2.0)
	# pernas curtas e grossas
	r.tubo(Vector2(22, 48), Vector2(21 - passo, 61), 5.0, 4.5, 0, "casca")
	r.tubo(Vector2(36, 48), Vector2(37 + passo, 61), 5.0, 4.5, 0, "casca")
	r.bola(Vector2(21 - passo, 61), Vector2(5.5, 2.5), 2, 0, "pedra")
	r.bola(Vector2(37 + passo, 61), Vector2(5.5, 2.5), 2, 0, "pedra")
	# braço de trás: comprido, arrastando no chão
	r.curva(Vector2(12, 22), Vector2(5, 38 + passo), Vector2(7, 54 + passo), 5.0, 4.0, 0, "casca")
	r.bola(Vector2(7, 57 + passo), Vector2(6.5, 5), 5, 1, "pedra")
	for d in [-4, 0, 4]:
		r.tubo(Vector2(7 + d, 59 + passo), Vector2(7 + d * 1.3, 62), 1.2, 0.6, 2, "pedra")
	# corpo curvado: barriga + peito largo (ombros altos, como um gorila)
	r.bola(Vector2(29, 38), Vector2(13, 11), 10, 2, "casca")
	r.bola(Vector2(29, 26), Vector2(18, 11), 12, 4, "casca")
	# cristas de casca (costelas)
	for k in 4:
		r.tubo(Vector2(19 + k * 6, 22), Vector2(20 + k * 6, 34), 1.2, 0.8, 13, "casca")
	# musgo pendurado nos ombros
	for p in [Vector2(15, 18), Vector2(20, 16), Vector2(38, 16), Vector2(43, 19), Vector2(13, 24), Vector2(45, 25)]:
		r.bola(p, Vector2(3.4, 2.4), 3, 15, "musgo")
	for p in [Vector2(14, 27), Vector2(44, 28)]:
		r.tubo(p, p + Vector2(0, 6), 1.2, 0.5, 15, "musgo")
	# braço da frente
	r.curva(Vector2(46, 22), Vector2(53, 38 - passo), Vector2(51, 54 - passo), 5.0, 4.0, 12, "casca")
	r.bola(Vector2(51, 57 - passo), Vector2(6.5, 5), 5, 14, "pedra")
	for d in [-4, 0, 4]:
		r.tubo(Vector2(51 + d, 59 - passo), Vector2(51 + d * 1.3, 62), 1.2, 0.6, 15, "pedra")
	# cabeça pequena e baixa, com chifres de galho
	r.bola(Vector2(29, 15), Vector2(6.5, 5.5), 6, 14, "casca")
	r.curva(Vector2(25, 11), Vector2(21, 6), Vector2(18, 1), 1.6, 0.5, 15, "casca", 4)
	r.curva(Vector2(33, 11), Vector2(37, 6), Vector2(40, 1), 1.6, 0.5, 15, "casca", 4)
	r.tubo(Vector2(29, 10), Vector2(29, 4), 1.2, 0.4, 15, "casca")
	# olhos e boca de brasa; rachaduras que pulsam
	var b := "brasa2" if f % 2 == 1 else "brasa"
	r.pintar(Vector2(26, 14), b, 8)
	r.pintar(Vector2(32, 14), b, 8)
	for x in range(25, 34):
		r.pintar(Vector2(x, 18), "boca", 8)
	for x in range(25, 34, 2):
		r.pintar(Vector2(x, 18), b, 8.2)
	for p in [Vector2(28, 26), Vector2(29, 27), Vector2(29, 28), Vector2(30, 29), Vector2(30, 30), Vector2(29, 31),
			Vector2(23, 33), Vector2(24, 34), Vector2(25, 35), Vector2(35, 31), Vector2(36, 32), Vector2(29, 38),
			Vector2(28, 39), Vector2(28, 40), Vector2(33, 41), Vector2(34, 42)]:
		r.pintar(p, b, 3)
	return r


# ---------------------------------------------------------------
# A SOMBRA — fumaça viva. Corpo que se desmancha em fiapos,
# dois olhinhos roxos. Os fiapos mexem a cada quadro.
# ---------------------------------------------------------------
static func _sombra(f: int) -> Relevo:
	var r := Relevo.new(30, 42)
	r.material("fumaca", FUMACA, false, 0.3)
	r.material("olho", [Color("c58bff")], true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + f
	# fiapos que escorrem para baixo
	for k in 5:
		var x0 := 9.0 + k * 3.0
		var balanco := sin((f + k) * 1.7) * 2.5
		r.curva(Vector2(x0, 26), Vector2(x0 + balanco, 33), Vector2(x0 - balanco + rng.randf_range(-1, 1), 40), 2.4, 0.4, 0, "fumaca", 5)
	# corpo (várias bolhas de fumaça)
	for k in 9:
		var p := Vector2(15 + rng.randf_range(-4, 4), 14 + k * 1.6 + rng.randf_range(-1, 1))
		var rr := rng.randf_range(3.0, 5.0)
		r.bola(p, Vector2(rr, rr), rr, 1, "fumaca")
	# braços compridos que se desfazem
	var bal := sin(f * PI / 2.0) * 2.0
	r.curva(Vector2(11, 16), Vector2(5, 22 + bal), Vector2(3, 30 - bal), 1.8, 0.4, 2, "fumaca", 5)
	r.curva(Vector2(19, 16), Vector2(25, 22 - bal), Vector2(27, 30 + bal), 1.8, 0.4, 2, "fumaca", 5)
	# cabeça
	r.bola(Vector2(15, 7), Vector2(5, 5.5), 5, 3, "fumaca")
	r.pintar(Vector2(13, 7), "olho", 6)
	r.pintar(Vector2(17, 7), "olho", 6)
	return r


# ---------------------------------------------------------------
# O MONSTRO DO LAGO — serpente de escamas verdes-escuras com
# barbatanas e olhos amarelos. Só a parte de cima sai da água.
# ---------------------------------------------------------------
static func _agua(f: int) -> Relevo:
	var r := Relevo.new(48, 40)
	r.material("escama", ESCAMA, false, 0.9)
	r.material("barbatana", OSSO, false, 0.3)
	r.material("barriga", [Color("1c1a10"), Color("35321e"), Color("514c2c"), Color("6f6840"), Color("8e8758")], false, 0.6)
	r.material("olho", [Color("ffd84a")], true)
	r.material("olho_agua", [Color("9fd8e8")], true)
	r.material("boca", BOCA)
	r.material("dente", OSSO)
	var bal := sin(f * PI / 2.0) * 2.0
	# pescoço saindo da água (curvado)
	r.curva(Vector2(20, 39), Vector2(16 + bal, 24), Vector2(26, 12), 6.5, 4.5, 0, "escama", 8)
	# barbatanas nas costas do pescoço
	for k in 4:
		var t := float(k) / 4.0
		var p := Vector2(20, 39).lerp(Vector2(16 + bal, 24), t).lerp(Vector2(16 + bal, 24).lerp(Vector2(26, 12), t), t)
		r.tubo(p + Vector2(-4, 0), p + Vector2(-9, -3), 1.6, 0.4, 2, "barbatana")
	# barriga clara
	r.curva(Vector2(23, 38), Vector2(20 + bal, 25), Vector2(29, 15), 2.5, 1.8, 5, "barriga", 6)
	# cabeça
	r.bola(Vector2(31, 11), Vector2(8.5, 6), 7, 4, "escama")
	r.bola(Vector2(37, 13), Vector2(5, 3.5), 4, 6, "escama")  # focinho
	# boca aberta com dentes
	var abre := 2 if f % 2 == 0 else 3
	for x in range(32, 42):
		for y in range(14, 14 + abre):
			r.pintar(Vector2(x, y), "boca", 4)
	for x in range(32, 42):
		if x % 2 == 0:
			r.pintar(Vector2(x, 14), "dente", 5)
		else:
			r.pintar(Vector2(x, 13 + abre), "dente", 5)
	# água escorrendo
	for p in [Vector2(23, 30 + f % 2), Vector2(14 + f % 3, 28), Vector2(34, 18 + f % 2)]:
		r.pintar(p, "olho_agua", 6)
	# barbatana da cabeça e olho
	r.tubo(Vector2(27, 6), Vector2(21, 1), 2.0, 0.5, 6, "barbatana")
	r.tubo(Vector2(30, 5), Vector2(27, 0), 1.5, 0.4, 6, "barbatana")
	r.pintar(Vector2(33, 9), "olho", 10)
	r.pintar(Vector2(34, 9), "olho", 10)
	return r


# ---------------------------------------------------------------
# v11 — O UIVADOR: parecido com um lobo magro demais, pelo cinza
# molhado, costelas aparecendo e olhos amarelos. Corre em 4 patas.
# ---------------------------------------------------------------
const PELO := [Color("101012"), Color("24242a"), Color("3c3c44"), Color("5a5a64"), Color("7e7e88")]


static func _uivador(f: int) -> Relevo:
	var r := Relevo.new(40, 24)
	r.material("pelo", PELO, false, 0.35)
	r.material("osso", OSSO, false, 0.4)
	r.material("olho", [Color("ffd23a")], true)
	r.material("boca", BOCA)
	var passo := sin(f * PI / 2.0)
	# patas (galope: dianteiras e traseiras em oposição)
	r.tubo(Vector2(10, 14), Vector2(8 - passo * 3.0, 22), 1.3, 0.8, 0, "pelo")
	r.tubo(Vector2(13, 14), Vector2(14 + passo * 3.0, 22), 1.2, 0.8, -1, "pelo")
	r.tubo(Vector2(26, 14), Vector2(28 + passo * 3.0, 22), 1.3, 0.8, 0, "pelo")
	r.tubo(Vector2(29, 14), Vector2(27 - passo * 3.0, 22), 1.2, 0.8, -1, "pelo")
	# corpo comprido e magro, costas curvadas
	r.curva(Vector2(7, 12), Vector2(18, 8 + passo * 0.6), Vector2(30, 11), 4.0, 4.4, 1, "pelo")
	for k in 4:   # costelas
		r.pintar(Vector2(17 + k * 2.4, 13), "osso", 2)
	# rabo
	r.curva(Vector2(6, 11), Vector2(2, 8), Vector2(1, 4 + passo), 1.4, 0.6, 1, "pelo", 4)
	# cabeça e focinho
	r.bola(Vector2(33, 9), Vector2(4.2, 3.6), 3.5, 2, "pelo")
	r.tubo(Vector2(35, 10), Vector2(39, 11), 2.0, 1.4, 2, "pelo")
	r.bola(Vector2(32, 4.5), Vector2(1.2, 2.2), 1.5, 3, "pelo")   # orelha
	var abre := 0.5 if f % 2 == 0 else 1.5
	r.tubo(Vector2(35, 12 + abre), Vector2(39, 12.5 + abre), 0.9, 0.7, 2, "boca")
	r.pintar(Vector2(37, 12), "osso", 3)
	r.pintar(Vector2(34, 8), "olho", 3)
	return r


# ---------------------------------------------------------------
# v11 — O IMITADOR (forma verdadeira): de longe ele parece um dos seus
# amigos. Quando a luz bate ou você chega perto, ele se revela: um corpo
# pálido e torto, com uma boca vertical enorme no lugar do rosto.
# ---------------------------------------------------------------
static func _imitador(f: int) -> Relevo:
	var r := Relevo.new(24, 40)
	r.material("pele", [Color("1a1416"), Color("3a2e30"), Color("6a5a5a"), Color("9a8a86"), Color("cbbcb4")], false, 0.5)
	r.material("boca", BOCA)
	r.material("dente", OSSO)
	r.material("olho", [Color("ffffff")], true)
	var bal := sin(f * PI / 2.0)
	r.tubo(Vector2(10, 39), Vector2(10.5, 27), 1.0, 1.4, 0, "pele")
	r.tubo(Vector2(14, 39), Vector2(13.5, 27), 1.0, 1.4, 0, "pele")
	r.curva(Vector2(12, 27), Vector2(12 + bal * 0.5, 19), Vector2(11, 12), 2.8, 2.4, 0, "pele")
	r.curva(Vector2(9.5, 15), Vector2(4 - bal, 22), Vector2(2.5, 31), 1.0, 0.6, 1, "pele")
	r.curva(Vector2(14.5, 15), Vector2(20 + bal, 22), Vector2(21.5, 31), 1.0, 0.6, 1, "pele")
	r.bola(Vector2(11.5, 7), Vector2(4.2, 5.5), 4, 1, "pele")
	# boca vertical abrindo o rosto inteiro
	var abre := 0.8 if f % 2 == 0 else 1.6
	r.caixa(Rect2(11.5 - abre, 3, abre * 2.0, 8.5), 1, 5, "boca", 0.5)
	for y in [4, 6, 8, 10]:
		r.pintar(Vector2(11.5 - abre, y), "dente", 6)
		r.pintar(Vector2(11.5 + abre - 0.5, y + 1), "dente", 6)
	r.pintar(Vector2(8.5, 5), "olho", 5)
	return r
