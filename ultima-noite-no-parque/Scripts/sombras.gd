class_name Sombras
extends Node
## =============================================================================
##  SOMBRAS DINÂMICAS (v10) — seguras para o Mali / celular fraco
## =============================================================================
## O que NÃO usamos (porque derruba o Godot no Mali-G68 ou pesa na CPU):
##   - PointLight2D / LightOccluder2D (sombras "de verdade" do Godot)
##   - shaders
##   - recalcular sombra a cada quadro
##
## Como funciona:
##   - Cada coisa que faz sombra (jogador, monstros, Lucas, árvores) ganha UM
##     Sprite2D com uma elipse pixelada preta (a mesma textura para todos: o Godot
##     desenha tudo junto, quase de graça na placa de vídeo).
##   - 10 vezes por segundo (5 no modo leve) o gerenciador olha só o que está PERTO
##     DA CÂMERA e gira/estica cada sombra:
##        DIA ..... sombra do SOL: comprida de manhã e no fim da tarde, curtinha ao
##                  meio-dia, e vai girando de oeste para leste com as horas.
##        NOITE ... sombra fraquinha da LUA. Perto de uma luz (fogueira, lampião,
##                  tocha, lareira) a sombra aponta PARA LONGE da luz e fica mais
##                  forte quanto mais perto. Nos faróis do carro ela fica comprida.
##   - O ângulo é arredondado em 16 direções (pixel art não "treme").
##
## Nível de detalhe (OPÇÕES > DETALHE):
##   BAIXO = só personagens | MÉDIO = + árvores perto | ALTO = + mais árvores
## =============================================================================

const INTERVALO_NORMAL := 0.1
const INTERVALO_LEVE := 0.2
const PASSO_ANGULO := PI / 8.0
const Z_SOMBRA := -2            ## abaixo de tudo que fica em pé, acima do chão (-5) e da água (-4)

static var _tex_pessoa: ImageTexture
static var _tex_arvore: ImageTexture

## Quem projeta sombra: [no, sprite, largura_base, comprimento_base]
var _moveis: Array = []
## Árvores: [posição da base, sprite]
var _arvores: Array = []
var hora := 12.0                 ## o controlador atualiza (CicloDia)
var interior_x := 3500.0         ## x a partir do qual é "dentro da cabana"
var _acum := 0.0
var _camada_arvores: Node2D


# ---------------------------------------------------------------
# TEXTURAS (criadas uma vez só, compartilhadas)
# ---------------------------------------------------------------
static func _elipse_pontilhada(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			# começa estreita no pé e alarga um pouco (sombra "saindo" do objeto)
			var u := (x + 0.5) / w * 2.0 - 1.0
			var v := (y + 0.5 - h / 2.0) / (h / 2.0)
			var largura := 0.75 + 0.25 * clampf((u + 1.0) * 0.8, 0.0, 1.0)
			var d := Vector2(u, v / largura).length()
			if d < 0.62:
				img.set_pixel(x, y, Color(0, 0, 0, 1.0))
			elif d < 1.0 and (x + y) % 2 == 0:   # borda pontilhada (dithering)
				img.set_pixel(x, y, Color(0, 0, 0, 1.0))
	return ImageTexture.create_from_image(img)


static func textura_pessoa() -> ImageTexture:
	if _tex_pessoa == null:
		_tex_pessoa = _elipse_pontilhada(20, 7)
	return _tex_pessoa


static func textura_arvore() -> ImageTexture:
	if _tex_arvore == null:
		_tex_arvore = _elipse_pontilhada(40, 11)
	return _tex_arvore


static func limpar_cache() -> void:
	_tex_pessoa = null
	_tex_arvore = null


# ---------------------------------------------------------------
# CADASTRO
# ---------------------------------------------------------------
## Sombra que acompanha um personagem (filha dele, fica embaixo de tudo).
func adicionar(no: Node2D, largura := 1.0, comprimento := 1.0) -> Sprite2D:
	var s := _novo_sprite(textura_pessoa())
	no.add_child(s)
	_moveis.append([no, s, largura, comprimento])
	return s


## Sombras das árvores ficam numa camada própria, ANTES dos objetos (assim nunca
## cobrem um personagem que está atrás da árvore).
func preparar_arvores(camada: Node2D, troncos: Array) -> void:
	_camada_arvores = camada
	if GameData.nivel_detalhe() <= 1:
		return
	for p in troncos:
		var s := _novo_sprite(textura_arvore())
		s.position = p
		s.visible = false
		camada.add_child(s)
		_arvores.append([p, s])


## Árvore cortada: some a sombra também.
func remover_arvore(indice: int) -> void:
	if indice >= 0 and indice < _arvores.size():
		var s: Sprite2D = _arvores[indice][1]
		if is_instance_valid(s):
			s.queue_free()
		_arvores[indice] = [Vector2.INF, null]


func _novo_sprite(t: Texture2D) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = t
	s.centered = false
	s.offset = Vector2(-3.0, -t.get_height() / 2.0)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.z_index = Z_SOMBRA
	s.modulate = Color(0, 0, 0, 0.0)
	return s


# ---------------------------------------------------------------
# ATUALIZAÇÃO (poucas vezes por segundo, só perto da câmera)
# ---------------------------------------------------------------
func _process(delta: float) -> void:
	_acum += delta
	var intervalo := INTERVALO_LEVE if (GameData.eh_mobile and GameData.nivel_detalhe() <= 2) or GameData.fps_maximo <= 30 else INTERVALO_NORMAL
	if _acum < intervalo:
		return
	_acum = 0.0
	var cam := get_viewport().get_camera_2d()
	var centro := cam.get_screen_center_position() if cam else Vector2.ZERO
	# moveis (personagens)
	var vivos: Array = []
	for m in _moveis:
		var no = m[0]
		if not is_instance_valid(no) or not is_instance_valid(m[1]):
			continue
		vivos.append(m)
		var s: Sprite2D = m[1]
		var vis: bool = no.is_visible_in_tree() and no.global_position.distance_squared_to(centro) < 250000.0
		s.visible = vis
		if vis:
			_aplicar(s, no.global_position, no, m[2], m[3])
	_moveis = vivos
	# árvores perto da câmera
	var raio2 := 300.0 * 300.0 if GameData.nivel_detalhe() >= 3 else 210.0 * 210.0
	for a in _arvores:
		var s = a[1]
		if s == null or not is_instance_valid(s):
			continue
		var perto: bool = (a[0] as Vector2).distance_squared_to(centro) < raio2
		s.visible = perto
		if perto:
			_aplicar(s, a[0], null, 1.0, 1.0)


## Calcula direção, comprimento e força da sombra num ponto do mundo.
func _aplicar(s: Sprite2D, pos: Vector2, dono: Node, largura: float, comprimento: float) -> void:
	var dentro := pos.x > interior_x
	var dir := Vector2(0.55, -0.35)
	var comp := 1.0
	var alfa := 0.0
	if not dentro:
		if hora >= 6.0 and hora < 18.0:
			# SOL: nasce no leste (sombra para oeste), se põe no oeste (sombra para leste)
			var t := (hora - 6.0) / 12.0
			dir = Vector2(lerpf(-1.0, 1.0, t), -0.45)
			comp = 0.7 + 1.5 * absf(t - 0.5) * 2.0
			alfa = 0.34 * clampf(minf(hora - 6.0, 18.0 - hora) / 1.2, 0.0, 1.0)
		else:
			alfa = 0.12   # lua
			comp = 1.1
	else:
		alfa = 0.08       # dentro: só uma sombrinha sob os pés
		comp = 0.6
	# LUZES PERTO: a mais forte decide a direção
	var melhor := 0.0
	for luz in Iluminacao._circulos:
		if not is_instance_valid(luz) or not luz.ativa():
			continue
		if dono != null and dono.is_ancestor_of(luz):
			continue   # a lanterna na mão não faz sombra do próprio jogador
		var d: Vector2 = pos - luz.global_position
		var alcance: float = luz.raio_protecao * 1.6
		var dist := d.length()
		if dist > alcance or dist < 2.0:
			continue
		var forca := 1.0 - dist / alcance
		if forca > melhor:
			melhor = forca
			dir = d
			comp = 0.6 + dist / alcance * 1.6
			alfa = maxf(alfa, 0.22 + 0.33 * forca)
	if melhor <= 0.0 and not dentro:
		for cone in Iluminacao._cones:
			if is_instance_valid(cone) and cone.farois_ligados() and Geometry2D.is_point_in_polygon(pos, cone.poligono_global()):
				dir = pos - cone.origem_farol()
				comp = 2.2
				alfa = 0.45
				break
	s.rotation = snappedf(dir.angle(), PASSO_ANGULO)
	s.scale = Vector2(comp * comprimento, largura)
	s.modulate.a = lerpf(s.modulate.a, alfa, 0.5)
