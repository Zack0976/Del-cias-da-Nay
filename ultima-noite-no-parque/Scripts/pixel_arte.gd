class_name PixelArte
extends RefCounted
## PIXEL ART FEITA POR CÓDIGO
##
## Aqui o jogo "pinta" pequenas imagens pixel por pixel (grama, terra, água, madeira,
## flores, pedras...) UMA vez só, e guarda num cache. Depois o cenário só repete
## essas imagens (como azulejos). Isso deixa o mundo cheio de detalhes e continua leve:
##   - poucas imagens pequenas na memória (cada uma tem 64x64 pixels ou menos)
##   - o chão inteiro vira poucos comandos de desenho
##
## Também tem funções para desenhar formas "pixeladas" (círculos e elipses feitos de
## quadradinhos), assim nada fica com borda lisa: tudo parece pixel art de verdade.

static var _cache := {}

# Paleta (cores escuras de floresta de terror)
const GRAMA := [Color("1d2b17"), Color("223219"), Color("283a1d"), Color("2f4422"), Color("37502a")]
const GRAMA_SECA := [Color("2e3019"), Color("363a1e"), Color("3f4223"), Color("4a4b2a")]
const TERRA := [Color("3b2b1b"), Color("45331f"), Color("4f3b24"), Color("5a442a"), Color("2f2216")]
const AGUA := [Color("0d1a26"), Color("10202f"), Color("142739"), Color("1b3246")]
const MADEIRA := [Color("3a2614"), Color("452e18"), Color("51361d"), Color("5c3e22"), Color("2a1b0e")]
const PEDRA := [Color("3c3c3e"), Color("47474a"), Color("525257"), Color("2c2c2e"), Color("5e5e63")]


static func _rng(semente: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = semente
	return r


static func _tex(nome: String, img: Image) -> ImageTexture:
	var t := ImageTexture.create_from_image(img)
	_cache[nome] = t
	return t


static func textura(nome: String) -> Texture2D:
	if _cache.has(nome):
		return _cache[nome]
	match nome:
		"grama": return _gerar_grama("grama", GRAMA, 11)
		"grama_seca": return _gerar_grama("grama_seca", GRAMA_SECA, 12)
		"terra": return _gerar_terra()
		"agua": return _gerar_agua()
		"piso": return _gerar_piso()
		"parede": return _gerar_parede()
		"pedra": return _gerar_pedra()
		"tapete": return _gerar_tapete()
		"luz": return luz(32)
	return _decoracao(nome)


static func limpar_cache() -> void:
	_cache.clear()


# ---------------------------------------------------------------
# AZULEJOS (repetem sem emenda)
# ---------------------------------------------------------------
static func _gerar_grama(nome: String, pal: Array, semente: int) -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var r := _rng(semente)
	for y in 64:
		for x in 64:
			# ruído "manchado": mistura de seno com aleatório (sem emenda porque usa ciclos de 64)
			var n := sin(TAU * x / 64.0 * 2.0) * 0.5 + sin(TAU * y / 64.0 * 3.0 + x * 0.1) * 0.5
			var i := clampi(int((n + 1.0) * 0.8 + r.randf() * 2.2), 0, 3)
			img.set_pixel(x, y, pal[i])
	# folhinhas de grama (traços de 2-3 pixels mais claros)
	for k in 70:
		var x := r.randi_range(0, 63)
		var y := r.randi_range(0, 63)
		var h := r.randi_range(1, 3)
		for j in h:
			img.set_pixel(x, (y - j + 64) % 64, pal[mini(pal.size() - 1, 3 + (1 if j == h - 1 else 0))])
	# sombrinhas
	for k in 30:
		img.set_pixel(r.randi_range(0, 63), r.randi_range(0, 63), pal[0].darkened(0.25))
	return _tex(nome, img)


static func _gerar_terra() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var r := _rng(21)
	for y in 64:
		for x in 64:
			var i := clampi(int(r.randf() * 2.6 + sin(TAU * y / 32.0) * 0.6), 0, 3)
			img.set_pixel(x, y, TERRA[i])
	# pedrinhas
	for k in 26:
		var x := r.randi_range(0, 62)
		var y := r.randi_range(0, 62)
		img.set_pixel(x, y, PEDRA[2])
		img.set_pixel(x + 1, y, PEDRA[1])
		img.set_pixel(x, y + 1, TERRA[4])
	# rachaduras / marcas
	for k in 10:
		var x := r.randi_range(0, 63)
		var y := r.randi_range(0, 63)
		for j in r.randi_range(2, 5):
			img.set_pixel((x + j) % 64, (y + (j % 2)) % 64, TERRA[4])
	return _tex("terra", img)


static func _gerar_agua() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var r := _rng(31)
	for y in 64:
		for x in 64:
			var i := clampi(int(r.randf() * 1.6 + (sin(TAU * (x + y * 0.5) / 64.0) + 1.0) * 0.5), 0, 2)
			img.set_pixel(x, y, AGUA[i])
	# reflexos (tracinhos horizontais)
	for k in 22:
		var x := r.randi_range(0, 63)
		var y := r.randi_range(0, 63)
		for j in r.randi_range(2, 6):
			img.set_pixel((x + j) % 64, y, AGUA[3])
	return _tex("agua", img)


static func _gerar_piso() -> ImageTexture:
	# Tábuas de 8 px de altura, com veios e emendas
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	var r := _rng(41)
	for tabua in 4:
		var y0 := tabua * 8
		var tom := r.randi_range(0, 2)
		var emenda := (tabua * 23 + 11) % 64
		for y in range(y0, y0 + 8):
			for x in 64:
				var c: Color = MADEIRA[tom + (1 if (x + y * 3) % 17 == 0 else 0)]
				if y == y0:
					c = MADEIRA[4]  # fresta entre tábuas
				elif x == emenda:
					c = MADEIRA[4]
				elif r.randf() < 0.04:
					c = c.darkened(0.15)
				img.set_pixel(x, y, c)
		# pregos
		img.set_pixel((emenda + 2) % 64, y0 + 2, Color("8a7d63"))
		img.set_pixel((emenda + 2) % 64, y0 + 5, Color("8a7d63"))
	return _tex("piso", img)


static func _gerar_parede() -> ImageTexture:
	# Troncos empilhados (6 px cada), com sombra embaixo e brilho em cima
	var img := Image.create(32, 12, false, Image.FORMAT_RGBA8)
	var r := _rng(51)
	for y in 12:
		var faixa := y % 6
		for x in 32:
			var c: Color = MADEIRA[2]
			if faixa == 0:
				c = MADEIRA[3]
			elif faixa == 5:
				c = MADEIRA[4]
			elif faixa == 4:
				c = MADEIRA[1]
			if r.randf() < 0.08 and faixa in [1, 2, 3]:
				c = MADEIRA[1]
			img.set_pixel(x, y, c)
	# nós da madeira
	img.set_pixel(9, 2, MADEIRA[4])
	img.set_pixel(10, 2, MADEIRA[4])
	img.set_pixel(24, 8, MADEIRA[4])
	return _tex("parede", img)


static func _gerar_pedra() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var r := _rng(61)
	for y in 16:
		for x in 16:
			var linha := y % 8 == 0
			var coluna := (x + (4 if (y / 8) % 2 == 1 else 0)) % 8 == 0
			var c: Color = PEDRA[3] if linha or coluna else PEDRA[r.randi_range(0, 2)]
			img.set_pixel(x, y, c)
	return _tex("pedra", img)


static func _gerar_tapete() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var a := Color("5a1712")
	var b := Color("6e2016")
	var c := Color("8a6a2a")
	for y in 8:
		for x in 8:
			var d := absi(x - 3) + absi(y - 3)
			img.set_pixel(x, y, c if d == 3 else (b if d < 3 else a))
	return _tex("tapete", img)


## Luz em "faixas" (estilo pixel art): 5 degraus de brilho, sem degradê liso.
## Textura de luz do tamanho EXATO (1 pixel da imagem = 1 pixel do mundo),
## assim os "degraus" e o pontilhado ficam alinhados com o resto da pixel art.
## O raio é arredondado de 8 em 8 para reaproveitar texturas parecidas.
static func luz(raio: float) -> ImageTexture:
	var r := clampi(roundi(raio / 8.0) * 8, 8, 160)
	var nome := "luz_%d" % r
	if _cache.has(nome):
		return _cache[nome]
	return _gerar_luz(r * 2, nome)


static func _gerar_luz(t: int, nome: String) -> ImageTexture:
	var img := Image.create(t, t, false, Image.FORMAT_RGBA8)
	for y in t:
		for x in t:
			var d := Vector2(x - t / 2.0 + 0.5, y - t / 2.0 + 0.5).length() / (t / 2.0)
			var v := clampf(1.0 - d, 0.0, 1.0)
			v = v * v * (3.0 - 2.0 * v)            # cai suave
			var degrau := floorf(v * 6.0)          # 6 degraus de brilho (pixel art)
			# "dithering": na fronteira entre degraus, metade dos pixels pega o degrau de cima
			if fmod(v * 6.0, 1.0) > 0.5 and (x + y) % 2 == 0:
				degrau += 1.0
			v = clampf(degrau / 6.0, 0.0, 1.0) * 0.8
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return _tex(nome, img)


# ---------------------------------------------------------------
# DECORAÇÕES (pequenos sprites desenhados pixel a pixel)
# ---------------------------------------------------------------
const DECORACOES := ["arbusto", "arbusto2", "pedra_p", "pedra_m", "flor_v", "flor_a", "flor_b",
	"tufo", "tufo2", "cogumelo", "tronco_caido", "toco", "samambaia", "taboa", "vitoria", "galhos", "folhas"]


static func _decoracao(nome: String) -> Texture2D:
	var r := _rng(hash(nome))
	var img: Image
	match nome:
		"arbusto", "arbusto2":
			var w := 18 if nome == "arbusto" else 14
			var h := 13 if nome == "arbusto" else 10
			img = Image.create(w, h, false, Image.FORMAT_RGBA8)
			for y in h:
				for x in w:
					var d := Vector2((x - w / 2.0) / (w / 2.0), (y - h * 0.6) / (h * 0.6)).length()
					if d < 1.0 - r.randf() * 0.15:
						var i := 1 if y > h * 0.55 else (3 if r.randf() < 0.25 else 2)
						img.set_pixel(x, y, GRAMA[i].darkened(0.1 if y > h * 0.7 else 0.0))
			if nome == "arbusto":
				img.set_pixel(5, 4, Color("7a2020"))  # frutinhas
				img.set_pixel(11, 6, Color("7a2020"))
		"pedra_p", "pedra_m":
			var w := 6 if nome == "pedra_p" else 10
			var h := 4 if nome == "pedra_p" else 7
			img = Image.create(w, h, false, Image.FORMAT_RGBA8)
			for y in h:
				for x in w:
					var d := Vector2((x - w / 2.0 + 0.5) / (w / 2.0), (y - h / 2.0 + 0.5) / (h / 2.0)).length()
					if d < 1.0:
						img.set_pixel(x, y, PEDRA[4] if y < h * 0.35 else (PEDRA[3] if y >= h - 1 else PEDRA[1]))
		"flor_v", "flor_a", "flor_b":
			img = Image.create(5, 6, false, Image.FORMAT_RGBA8)
			var cor := {"flor_v": Color("8e2a2a"), "flor_a": Color("b0902c"), "flor_b": Color("b9b4a6")}[nome] as Color
			img.set_pixel(2, 5, GRAMA[3])
			img.set_pixel(2, 4, GRAMA[3])
			img.set_pixel(1, 3, GRAMA[4])
			for p in [Vector2i(2, 0), Vector2i(1, 1), Vector2i(3, 1), Vector2i(2, 2)]:
				img.set_pixel(p.x, p.y, cor)
			img.set_pixel(2, 1, Color("e0c050"))
		"tufo", "tufo2":
			img = Image.create(7, 6, false, Image.FORMAT_RGBA8)
			for k in 5:
				var x := 1 + k
				var h := r.randi_range(2, 5)
				for j in h:
					img.set_pixel(x, 5 - j, GRAMA[4 if j == h - 1 else 3] if nome == "tufo" else GRAMA_SECA[3 if j == h - 1 else 2])
		"cogumelo":
			img = Image.create(5, 6, false, Image.FORMAT_RGBA8)
			for x in 5:
				img.set_pixel(x, 1, Color("8a2a20"))
			for x in range(1, 4):
				img.set_pixel(x, 0, Color("a03526"))
			img.set_pixel(1, 1, Color("d8d0c0"))
			img.set_pixel(2, 2, Color("cfc6b2"))
			img.set_pixel(2, 3, Color("cfc6b2"))
			img.set_pixel(2, 4, Color("b8ad96"))
		"tronco_caido":
			img = Image.create(26, 8, false, Image.FORMAT_RGBA8)
			for y in range(1, 7):
				for x in range(1, 24):
					img.set_pixel(x, y, MADEIRA[1] if y in [1, 2] else (MADEIRA[4] if y == 6 else MADEIRA[0]))
			for y in range(1, 7):  # ponta cortada (anéis)
				img.set_pixel(24, y, Color("6b4b2a"))
				img.set_pixel(25, y, Color("7c5a34") if y in [3, 4] else Color("6b4b2a"))
			img.set_pixel(8, 2, GRAMA[3])  # musgo
			img.set_pixel(9, 2, GRAMA[4])
			img.set_pixel(15, 1, GRAMA[3])
		"toco":
			img = Image.create(10, 9, false, Image.FORMAT_RGBA8)
			for y in range(2, 9):
				for x in range(1, 9):
					img.set_pixel(x, y, MADEIRA[1] if x in [1, 2] else MADEIRA[0])
			for x in range(1, 9):
				img.set_pixel(x, 1, Color("7c5a34"))
				img.set_pixel(x, 2, Color("6b4b2a"))
			img.set_pixel(4, 1, Color("5a3e22"))
			img.set_pixel(0, 8, MADEIRA[0])
			img.set_pixel(9, 8, MADEIRA[0])
		"samambaia":
			img = Image.create(13, 10, false, Image.FORMAT_RGBA8)
			for folha in 5:
				var ang := lerpf(-2.6, -0.5, folha / 4.0)
				for t in 7:
					var p := Vector2(6, 9) + Vector2(cos(ang), sin(ang)) * t * 1.2
					if p.x >= 0 and p.x < 13 and p.y >= 0 and p.y < 10:
						img.set_pixel(int(p.x), int(p.y), GRAMA[3 if t % 2 == 0 else 4])
		"taboa":
			img = Image.create(7, 14, false, Image.FORMAT_RGBA8)
			for k in 3:
				var x := 1 + k * 2
				var h := r.randi_range(8, 13)
				for j in h:
					img.set_pixel(x, 13 - j, GRAMA[3])
				img.set_pixel(x, 13 - h, Color("4a2e18"))
				img.set_pixel(x, 14 - h, Color("4a2e18"))
		"vitoria":
			img = Image.create(9, 5, false, Image.FORMAT_RGBA8)
			for y in 5:
				for x in 9:
					if Vector2((x - 4) / 4.5, (y - 2) / 2.5).length() < 1.0 and not (x >= 4 and y == 2):
						img.set_pixel(x, y, GRAMA[3] if y < 2 else GRAMA[2])
		"galhos":
			img = Image.create(10, 6, false, Image.FORMAT_RGBA8)
			for x in 9:
				img.set_pixel(x, 2 + (1 if x % 3 == 0 else 0), MADEIRA[1])
			img.set_pixel(3, 1, MADEIRA[1])
			img.set_pixel(6, 4, MADEIRA[1])
			img.set_pixel(7, 5, MADEIRA[1])
		"folhas":
			img = Image.create(9, 6, false, Image.FORMAT_RGBA8)
			for k in 9:
				img.set_pixel(r.randi_range(0, 8), r.randi_range(0, 5), [Color("5a3a1a"), Color("6e4a1e"), Color("4a3a1a")][k % 3])
		_:
			img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	return _tex(nome, img)


# ---------------------------------------------------------------
# FORMAS PIXELADAS
# ---------------------------------------------------------------

## Elipse cheia feita de linhas de 1 pixel (borda em "escadinha", como pixel art).
## Se passar uma textura, ela é repetida alinhada ao mundo (sem emendas).
static func elipse(c: CanvasItem, centro: Vector2, raio: Vector2, cor: Color, tex: Texture2D = null) -> void:
	var cy := roundi(centro.y)
	var ry := maxi(roundi(raio.y), 1)
	for dy in range(-ry, ry + 1):
		var t := float(dy) / float(ry)
		var meia := roundi(raio.x * sqrt(maxf(0.0, 1.0 - t * t)))
		if meia <= 0:
			continue
		var r := Rect2(roundi(centro.x) - meia, cy + dy, meia * 2, 1)
		if tex:
			c.draw_texture_rect_region(tex, r, r, cor)
		else:
			c.draw_rect(r, cor)


static func circulo(c: CanvasItem, centro: Vector2, raio: float, cor: Color, tex: Texture2D = null) -> void:
	elipse(c, centro, Vector2(raio, raio), cor, tex)


## Retângulo preenchido com textura repetida, alinhada ao mundo.
static func azulejo(c: CanvasItem, r: Rect2, tex: Texture2D, cor := Color.WHITE) -> void:
	c.draw_texture_rect_region(tex, r, r, cor)


## Linha "grossa" pixelada (vários quadradinhos), boa para trilhas e caminhos.
static func trilha(c: CanvasItem, a: Vector2, b: Vector2, largura: float, cor: Color, tex: Texture2D = null) -> void:
	var passos := maxi(int(a.distance_to(b) / 3.0), 1)
	for i in passos + 1:
		elipse(c, a.lerp(b, float(i) / passos), Vector2(largura, largura * 0.7), cor, tex)


# ---------------------------------------------------------------
# ÁRVORES (v9) — esculpidas e iluminadas por pixel (veja relevo.gd)
# A ORIGEM da imagem é a BASE DO TRONCO: assim a colisão fica exatamente
# no tronco que você vê, e o jogador passa atrás/na frente certinho.
# ---------------------------------------------------------------
const TIPOS_ARVORE := 5
const PINHO := [Color("0b1610"), Color("14261a"), Color("1f3a25"), Color("2d5233"), Color("3f6b40")]
const FOLHA := [Color("101a0c"), Color("1c2e14"), Color("2c461d"), Color("3f6127"), Color("587e34")]
const TRONCO := [Color("150e09"), Color("2a1c12"), Color("3f2b1b"), Color("573c26"), Color("6f5034")]
const SECA := [Color("1a1714"), Color("2f2a25"), Color("4a423a"), Color("675c51"), Color("857a6c")]


static func arvore(variante: int) -> Texture2D:
	var nome := "arvore_%d" % variante
	if _cache.has(nome):
		return _cache[nome]
	var rng := _rng(900 + variante)
	var r: Relevo
	match variante:
		0, 1:  # pinheiros (alto e médio)
			var alto := variante == 0
			var w := 36 if alto else 30
			var h := 74 if alto else 58
			r = Relevo.new(w, h)
			r.material("tronco", TRONCO, false, 0.1)
			r.material("pinho", PINHO, false, 0.15)
			var cx := w / 2.0
			var base_y := h - 3.0
			r.tubo(Vector2(cx, base_y), Vector2(cx, base_y - h * 0.4), 2.4, 1.6, 0, "tronco")
			r.bola(Vector2(cx - 2.5, base_y), Vector2(2, 1.2), 1.5, 0, "tronco")  # raízes
			r.bola(Vector2(cx + 2.5, base_y), Vector2(2, 1.2), 1.5, 0, "tronco")
			var andares := 6 if alto else 5
			for k in andares:
				var t := float(k) / andares
				var y := base_y - h * 0.22 - t * h * 0.68
				var larg := (w * 0.47) * (1.0 - t * 0.78)
				r.bola(Vector2(cx, y), Vector2(larg, 5.5 - t * 1.5), 7, 2 + k * 2, "pinho")
				for lado in [-1, 1]:  # pontas caídas dos galhos
					r.tubo(Vector2(cx + lado * larg * 0.75, y + 1), Vector2(cx + lado * (larg + 1.5), y + 4), 1.6, 0.6, 2 + k * 2, "pinho")
			r.tubo(Vector2(cx, base_y - h * 0.86), Vector2(cx, 1), 1.6, 0.5, 14, "pinho")
		2, 4:  # árvores de copa redonda (média e grande)
			var grande := variante == 4
			var w := 54 if grande else 44
			var h := 68 if grande else 58
			r = Relevo.new(w, h)
			r.material("tronco", TRONCO, false, 0.1)
			r.material("folha", FOLHA, false, 0.1)
			var cx := w / 2.0
			var base_y := h - 3.0
			r.tubo(Vector2(cx, base_y), Vector2(cx - 1, base_y - h * 0.45), 3.2, 2.2, 0, "tronco")
			r.bola(Vector2(cx - 3.5, base_y), Vector2(2.6, 1.4), 1.5, 0, "tronco")
			r.bola(Vector2(cx + 3.5, base_y), Vector2(2.6, 1.4), 1.5, 0, "tronco")
			r.curva(Vector2(cx - 1, base_y - h * 0.4), Vector2(cx - 8, base_y - h * 0.5), Vector2(cx - 12, base_y - h * 0.62), 1.6, 0.8, 1, "tronco", 4)
			r.curva(Vector2(cx, base_y - h * 0.42), Vector2(cx + 8, base_y - h * 0.52), Vector2(cx + 13, base_y - h * 0.6), 1.6, 0.8, 1, "tronco", 4)
			var centro := Vector2(cx, h * 0.36)
			for k in (16 if grande else 12):
				var ang := rng.randf() * TAU
				var dist := rng.randf_range(0.0, 1.0)
				var p := centro + Vector2(cos(ang) * w * 0.3 * dist, sin(ang) * h * 0.2 * dist)
				var rr := rng.randf_range(6.0, 9.5) * (1.15 if grande else 1.0)
				r.bola(p, Vector2(rr, rr * 0.9), rr, 4 + (1.0 - dist) * 6, "folha")
		_:  # árvore seca (sem folhas, galhos tortos)
			var w := 38
			var h := 60
			r = Relevo.new(w, h)
			r.material("seca", SECA, false, 0.1)
			var cx := w / 2.0
			var base_y := h - 3.0
			r.curva(Vector2(cx, base_y), Vector2(cx + 2, base_y - 20), Vector2(cx - 1, base_y - 36), 3.0, 1.6, 0, "seca")
			r.bola(Vector2(cx - 3, base_y), Vector2(2.5, 1.2), 1.5, 0, "seca")
			r.bola(Vector2(cx + 3, base_y), Vector2(2.5, 1.2), 1.5, 0, "seca")
			r.curva(Vector2(cx + 1, base_y - 24), Vector2(cx + 9, base_y - 30), Vector2(cx + 15, base_y - 44), 1.6, 0.5, 1, "seca", 5)
			r.curva(Vector2(cx, base_y - 30), Vector2(cx - 9, base_y - 36), Vector2(cx - 14, base_y - 50), 1.5, 0.5, 1, "seca", 5)
			r.curva(Vector2(cx - 1, base_y - 36), Vector2(cx + 2, base_y - 46), Vector2(cx - 2, base_y - 55), 1.3, 0.4, 2, "seca", 5)
			r.tubo(Vector2(cx + 9, base_y - 31), Vector2(cx + 14, base_y - 30), 0.8, 0.4, 2, "seca")
			r.tubo(Vector2(cx - 8, base_y - 37), Vector2(cx - 13, base_y - 38), 0.8, 0.4, 2, "seca")
	var img := r.renderizar(Color(0.02, 0.03, 0.02))
	# sombra no chão (meio transparente) embaixo do tronco
	var cxs := img.get_width() / 2.0
	var by := img.get_height() - 3.0
	for y in range(img.get_height() - 5, img.get_height()):
		for x in img.get_width():
			var d := Vector2((x + 0.5 - cxs - 3.0) / (img.get_width() * 0.3), (y + 0.5 - by) / 2.5)
			if d.length() < 1.0 and img.get_pixel(x, y).a < 0.1:
				img.set_pixel(x, y, Color(0, 0, 0, 0.3))
	return _tex(nome, img)


## Sprite pronto de árvore, com a origem na base do tronco.
static func sprite_arvore(variante: int) -> Sprite2D:
	var s := Sprite2D.new()
	var t := arvore(variante)
	s.texture = t
	s.centered = false
	s.offset = Vector2(-t.get_width() / 2.0, -(t.get_height() - 3.0))
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return s
