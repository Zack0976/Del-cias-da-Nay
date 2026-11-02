class_name Relevo
extends RefCounted
## ============================================================
##  RELEVO: pixel art com ILUMINAÇÃO CALCULADA (mini "ray tracing")
## ============================================================
## Em vez de pintar cada pixel na mão, a gente "esculpe" o desenho com bolas
## e cilindros (como massinha). Cada pixel guarda:
##   - a ALTURA (o quanto ele sai da tela, na direção do jogador)
##   - a NORMAL (para que lado a superfície está virada)
##   - o MATERIAL (pele, casca de árvore, escama...)
##
## Depois, para cada pixel, o computador calcula a luz:
##   1. Luz difusa:  quanto a superfície está virada para a lua  (n · L)
##   2. Brilho:      reflexo molhado/lustroso (especular)
##   3. SOMBRA:      lança um RAIO do pixel em direção à luz. Se o raio bater
##                   em uma parte mais alta do desenho, o pixel fica na sombra.
##                   Isso é ray tracing de verdade, só que num mapa de alturas!
##   4. Oclusão:     cantinhos fundos ficam mais escuros
## E no fim troca o valor da luz por uma das 5 cores da paleta do material
## (com "dithering" de pixel art). Assim continua 100% pixel art.
##
## Tudo é feito UMA vez quando o jogo abre (as imagens ficam guardadas),
## então não pesa no celular durante o jogo.

var w := 0
var h := 0
var _z: PackedFloat32Array
var _n: PackedVector3Array
var _m: PackedInt32Array            ## índice do material (-1 = vazio)
var _materiais: Array = []          ## [nome, rampa de cores, emissivo, brilho]
var _ids := {}

const LUZ := Vector3(-0.55, -0.75, 0.62)   ## luz da lua: vem de cima e da esquerda
const BAYER := [0.0, 0.5, 0.75, 0.25]      ## dithering 2x2


func _init(largura: int, altura: int) -> void:
	w = largura
	h = altura
	_z.resize(w * h)
	_n.resize(w * h)
	_m.resize(w * h)
	_z.fill(-1000.0)
	_m.fill(-1)


## rampa = 5 cores, do mais escuro ao mais claro. emissivo = brilha sozinho (olhos).
## brilho = 0 (fosco) a 1 (molhado/lustroso)
func material(nome: String, rampa: Array, emissivo := false, brilho := 0.0) -> void:
	_ids[nome] = _materiais.size()
	_materiais.append([nome, rampa, emissivo, brilho])


## Bola achatada (elipsoide). z0 = altura da base.
func bola(c: Vector2, raio: Vector2, rz: float, z0: float, mat: String) -> void:
	var id: int = _ids[mat]
	for y in range(floori(c.y - raio.y), ceili(c.y + raio.y) + 1):
		if y < 0 or y >= h:
			continue
		for x in range(floori(c.x - raio.x), ceili(c.x + raio.x) + 1):
			if x < 0 or x >= w:
				continue
			var u := (x + 0.5 - c.x) / raio.x
			var v := (y + 0.5 - c.y) / raio.y
			var d := u * u + v * v
			if d > 1.0:
				continue
			var wz := sqrt(1.0 - d)
			var z := z0 + rz * wz
			var i := y * w + x
			if z > _z[i]:
				_z[i] = z
				_m[i] = id
				_n[i] = Vector3(u, v, wz * 1.2).normalized()


## "Cilindro" com pontas redondas entre a e b (braços, pernas, tentáculos).
## r_a e r_b permitem afinar (tentáculo fica fino na ponta).
func tubo(a: Vector2, b: Vector2, r_a: float, r_b: float, z0: float, mat: String) -> void:
	var passos := maxi(ceili(a.distance_to(b) * 1.5), 1)
	for k in passos + 1:
		var t := float(k) / passos
		var r := lerpf(r_a, r_b, t)
		bola(a.lerp(b, t), Vector2(r, r), r, z0, mat)


## Curva (3 pontos) feita de tubos — bom para pescoços e caudas.
func curva(a: Vector2, meio: Vector2, b: Vector2, r_a: float, r_b: float, z0: float, mat: String, partes := 6) -> void:
	var antes := a
	for k in range(1, partes + 1):
		var t := float(k) / partes
		var p := a.lerp(meio, t).lerp(meio.lerp(b, t), t)
		tubo(antes, p, lerpf(r_a, r_b, float(k - 1) / partes), lerpf(r_a, r_b, t), z0, mat)
		antes = p


## Caixa com as bordas arredondadas (tábuas, latas, caixas).
func caixa(r: Rect2, rz: float, z0: float, mat: String, chanfro := 1.5) -> void:
	var id: int = _ids[mat]
	for y in range(floori(r.position.y), ceili(r.end.y)):
		if y < 0 or y >= h:
			continue
		for x in range(floori(r.position.x), ceili(r.end.x)):
			if x < 0 or x >= w:
				continue
			var dx := minf(x + 0.5 - r.position.x, r.end.x - x - 0.5)
			var dy := minf(y + 0.5 - r.position.y, r.end.y - y - 0.5)
			var nx := 0.0
			var ny := 0.0
			if dx < chanfro:
				nx = (-1.0 if x + 0.5 - r.position.x < r.end.x - x - 0.5 else 1.0) * (1.0 - dx / chanfro)
			if dy < chanfro:
				ny = (-1.0 if y + 0.5 - r.position.y < r.end.y - y - 0.5 else 1.0) * (1.0 - dy / chanfro)
			var z := z0 + rz * (1.0 - maxf(absf(nx), absf(ny)) * 0.4)
			var i := y * w + x
			if z > _z[i]:
				_z[i] = z
				_m[i] = id
				_n[i] = Vector3(nx, ny, 1.0).normalized()


## Pinta pixels por cima (detalhes: olhos, rachaduras, dentes) sem mudar a forma.
func pintar(p: Vector2, mat: String, z_extra := 0.5) -> void:
	var x := roundi(p.x)
	var y := roundi(p.y)
	if x < 0 or x >= w or y < 0 or y >= h:
		return
	var i := y * w + x
	if _m[i] < 0:
		_z[i] = 0.0
		_n[i] = Vector3(0, 0, 1)
	_m[i] = _ids[mat]
	_z[i] += z_extra


func ocupado(x: int, y: int) -> bool:
	return x >= 0 and x < w and y >= 0 and y < h and _m[y * w + x] >= 0


## Calcula a luz de cada pixel e devolve a imagem pronta.
func renderizar(contorno := Color(0.03, 0.02, 0.04), luz := LUZ) -> Image:
	var L := luz.normalized()
	var meio := (L + Vector3(0, 0, 1)).normalized()   # para o brilho especular
	var passo_raio := Vector2(L.x, L.y).normalized()
	var subida := L.z / maxf(Vector2(L.x, L.y).length(), 0.01)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var i := y * w + x
			var id := _m[i]
			if id < 0:
				# contorno: pixel vazio colado num pixel cheio
				if ocupado(x - 1, y) or ocupado(x + 1, y) or ocupado(x, y - 1) or ocupado(x, y + 1):
					img.set_pixel(x, y, contorno)
				continue
			var mat: Array = _materiais[id]
			var rampa: Array = mat[1]
			if mat[2]:  # emissivo: cor mais clara, sem sombra
				img.set_pixel(x, y, rampa[rampa.size() - 1])
				continue
			var n: Vector3 = _n[i]
			var z := _z[i]
			var difusa := maxf(n.dot(L), 0.0)
			var espec := pow(maxf(n.dot(meio), 0.0), 18.0) * float(mat[3])
			# RAIO DE SOMBRA: anda em direção à luz procurando algo mais alto
			var sombra := 1.0
			var px := x + 0.5
			var py := y + 0.5
			for t in range(1, 14):
				px += passo_raio.x
				py += passo_raio.y
				var xi := floori(px)
				var yi := floori(py)
				if xi < 0 or xi >= w or yi < 0 or yi >= h:
					break
				var j := yi * w + xi
				if _m[j] >= 0 and _z[j] > z + subida * t + 0.6:
					sombra = 0.45
					break
			# oclusão (cantinhos)
			var viz := 0.0
			var cont := 0
			for d in [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, -2), Vector2i(0, 2)]:
				var xx: int = x + d.x
				var yy: int = y + d.y
				if xx >= 0 and xx < w and yy >= 0 and yy < h and _m[yy * w + xx] >= 0:
					viz += _z[yy * w + xx]
					cont += 1
			var oclusao := 1.0
			if cont > 0 and viz / cont > z + 1.5:
				oclusao = 0.75
			var luz_total := (0.18 + difusa * 0.85 * sombra) * oclusao + espec * sombra
			var nivel: float = luz_total * rampa.size() + float(BAYER[(x % 2) + (y % 2) * 2]) - 0.4
			img.set_pixel(x, y, rampa[clampi(floori(nivel), 0, rampa.size() - 1)])
	return img


func textura(contorno := Color(0.03, 0.02, 0.04)) -> ImageTexture:
	return ImageTexture.create_from_image(renderizar(contorno))
