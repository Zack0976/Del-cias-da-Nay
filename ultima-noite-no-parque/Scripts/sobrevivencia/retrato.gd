class_name Retrato
extends RefCounted
## =============================================================================
##  RETRATOS DOS CARTAZES (v11) — o rosto de cada desaparecido em pixel art
## =============================================================================
## Cada rosto é pintado pixel por pixel numa imagem de 32x32, UMA vez só
## (fica no cache). Depois a interface mostra ampliado, sem suavizar.
##
## dados: {"pele": Color, "cabelo": Color, "estilo": "curto|longo|cacheado|careca|rabo",
##         "roupa": Color, "oculos": bool, "barba": bool, "bone": Color ou null,
##         "antiga": bool (foto velha = sépia)}
## =============================================================================

static var _cache := {}


static func textura(id: String, d: Dictionary) -> ImageTexture:
	if _cache.has(id):
		return _cache[id]
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var fundo := Color(0.62, 0.62, 0.6)
	img.fill(fundo)
	# leve degradê de estúdio no fundo
	for y in 32:
		for x in 32:
			if (x + y) % 5 == 0:
				img.set_pixel(x, y, fundo.darkened(0.06))
	var pele: Color = d.get("pele", Color("e0b090"))
	var sombra_pele := pele.darkened(0.22)
	var cabelo: Color = d.get("cabelo", Color("3a2616"))
	var roupa: Color = d.get("roupa", Color("3a4a6a"))
	var estilo: String = d.get("estilo", "curto")
	# cabelo comprido fica ATRÁS do rosto
	if estilo in ["longo", "rabo"]:
		_elipse(img, Vector2(16, 15), Vector2(10, 12), cabelo)
		_ret(img, Rect2i(6, 15, 20, 12), cabelo)
	# ombros / roupa
	_elipse(img, Vector2(16, 34), Vector2(14, 9), roupa)
	_ret(img, Rect2i(13, 22, 6, 4), sombra_pele)      # pescoço
	_elipse(img, Vector2(16, 27), Vector2(4, 2), roupa.darkened(0.25))  # gola
	# rosto
	_elipse(img, Vector2(16, 15), Vector2(7, 9), pele)
	_elipse(img, Vector2(18, 17), Vector2(4, 6), pele.lightened(0.06))
	for y in range(9, 23):
		img.set_pixel(9, y, sombra_pele)
	_ret(img, Rect2i(8, 15, 1, 4), sombra_pele)       # orelhas
	_ret(img, Rect2i(23, 15, 1, 4), sombra_pele)
	# olhos, sobrancelhas, nariz, boca
	var olho := Color(0.12, 0.1, 0.1)
	_ret(img, Rect2i(12, 15, 2, 2), olho)
	_ret(img, Rect2i(18, 15, 2, 2), olho)
	img.set_pixel(12, 15, Color(0.9, 0.9, 0.9))
	img.set_pixel(18, 15, Color(0.9, 0.9, 0.9))
	_ret(img, Rect2i(11, 13, 4, 1), cabelo.darkened(0.2))
	_ret(img, Rect2i(17, 13, 4, 1), cabelo.darkened(0.2))
	_ret(img, Rect2i(15, 17, 2, 3), sombra_pele)
	_ret(img, Rect2i(14, 21, 4, 1), Color(0.45, 0.2, 0.2))
	if d.get("barba", false):
		_ret(img, Rect2i(10, 19, 12, 4), cabelo.darkened(0.1))
		_ret(img, Rect2i(12, 23, 8, 1), cabelo.darkened(0.1))
		_ret(img, Rect2i(14, 21, 4, 1), Color(0.3, 0.12, 0.12))
	if d.get("oculos", false):
		var aro := Color(0.1, 0.1, 0.12)
		_moldura(img, Rect2i(10, 14, 6, 4), aro)
		_moldura(img, Rect2i(16, 14, 6, 4), aro)
	# cabelo da frente
	match estilo:
		"careca":
			_ret(img, Rect2i(9, 13, 2, 4), cabelo)
			_ret(img, Rect2i(21, 13, 2, 4), cabelo)
		"cacheado":
			for k in 9:
				_elipse(img, Vector2(9 + k * 1.8, 7 + (k % 2) * 2), Vector2(2.5, 2.5), cabelo)
			_elipse(img, Vector2(8, 13), Vector2(2, 4), cabelo)
			_elipse(img, Vector2(24, 13), Vector2(2, 4), cabelo)
		_:
			_elipse(img, Vector2(16, 8), Vector2(8, 4), cabelo)
			_ret(img, Rect2i(8, 8, 3, 7), cabelo)
			_ret(img, Rect2i(21, 8, 3, 7), cabelo)
			_ret(img, Rect2i(11, 10, 7, 2), cabelo)       # franja
	if d.get("bone") != null:
		var b: Color = d["bone"]
		_elipse(img, Vector2(16, 8), Vector2(9, 4), b)
		_ret(img, Rect2i(15, 10, 11, 2), b.darkened(0.3))
	# borda de foto
	_moldura(img, Rect2i(0, 0, 32, 32), Color(0.95, 0.94, 0.9))
	if d.get("antiga", false):
		_sepia(img)
	var t := ImageTexture.create_from_image(img)
	_cache[id] = t
	return t


static func limpar_cache() -> void:
	_cache.clear()


static func _ret(img: Image, r: Rect2i, c: Color) -> void:
	for y in range(maxi(r.position.y, 0), mini(r.end.y, img.get_height())):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, img.get_width())):
			img.set_pixel(x, y, c)


static func _moldura(img: Image, r: Rect2i, c: Color) -> void:
	_ret(img, Rect2i(r.position.x, r.position.y, r.size.x, 1), c)
	_ret(img, Rect2i(r.position.x, r.end.y - 1, r.size.x, 1), c)
	_ret(img, Rect2i(r.position.x, r.position.y, 1, r.size.y), c)
	_ret(img, Rect2i(r.end.x - 1, r.position.y, 1, r.size.y), c)


static func _elipse(img: Image, c: Vector2, r: Vector2, cor: Color) -> void:
	for y in range(floori(c.y - r.y), ceili(c.y + r.y) + 1):
		for x in range(floori(c.x - r.x), ceili(c.x + r.x) + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var u := (x + 0.5 - c.x) / r.x
			var v := (y + 0.5 - c.y) / r.y
			if u * u + v * v <= 1.0:
				img.set_pixel(x, y, cor)


static func _sepia(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var l := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			img.set_pixel(x, y, Color(l * 1.05 + 0.04, l * 0.92 + 0.02, l * 0.72, 1.0))
