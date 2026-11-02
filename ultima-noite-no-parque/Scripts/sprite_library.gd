class_name SpriteLibrary
extends RefCounted
## Biblioteca de sprites do jogo.
##
## PROBLEMA QUE ISSO RESOLVE: as folhas de sprite (ex.: lucas_frente.png) não têm
## os quadros com o mesmo espaçamento, e algumas têm "sobras" de outras linhas.
## Dividir a largura pelo número de quadros cortava os bonecos no meio (BUG antigo).
##
## Aqui cada quadro tem o seu retângulo exato (x, y, largura, altura), medido
## pixel a pixel. Assim nenhum boneco sai cortado ou "pulando".

const PASTA := "res://Sprites/"
const PASTA_PIXEL := "res://Sprites/pixel/"

## Altura (em pixels do mundo) de TODOS os personagens.
const ALTURA_PERSONAGEM := 32.0

## As folhas "pixel" já vêm prontas em tamanho de pixel art (geradas a partir das
## imagens grandes, que ficaram guardadas em Sprites/originais).
## Cada folha é uma fileira de quadros do mesmo tamanho: [quantidade, largura, altura]
##
## OTIMIZAÇÃO: as imagens originais tinham até 3882 pixels de largura e ocupavam
## mais de 150 MB de memória de vídeo no celular. As versões pixel ocupam menos de 2 MB!
const FOLHAS := {
	"lucas_frente": [9, 17, 32],
	"lucas_costas": [9, 17, 32],
	"marina_frente": [9, 17, 32],
	"marina_costas": [9, 17, 32],
	"rafa_frente": [8, 22, 32],
	"rafa_costas": [9, 17, 32],
	"jogadora_frente": [8, 13, 32],
	"jogadora_costas": [8, 14, 32],
	"carro": [4, 110, 70],
	"cabana": [4, 150, 178],
	"radio": [2, 16, 19],
	"lanterna": [2, 8, 16],
	"arvores": [3, 88, 136],
}

## Quais folhas cada personagem usa.
## "frente" = andando para baixo, "costas" = andando para cima.
const PERSONAGENS := {
	"lucas": {"frente": "lucas_frente", "costas": "lucas_costas"},
	"marina": {"frente": "marina_frente", "costas": "marina_costas"},
	"rafa": {"frente": "rafa_frente", "costas": "rafa_costas"},
	"jogadora": {"frente": "jogadora_frente", "costas": "jogadora_costas"},
	# "protagonista" é especial (folha 4x4 de 32px + quadros parados soltos), veja abaixo.
}

static var _cache_frames := {}


static func textura(nome: String) -> Texture2D:
	var caminho := (PASTA_PIXEL if FOLHAS.has(nome) else PASTA) + nome + ".png"
	if not ResourceLoader.exists(caminho):
		push_error("Sprite não encontrado: " + caminho)
		return null
	return load(caminho)


## Retângulo do quadro "indice" dentro da folha.
static func regiao(nome: String, indice: int) -> Rect2:
	var f: Array = FOLHAS[nome]
	var i := clampi(indice, 0, int(f[0]) - 1)
	return Rect2(i * int(f[1]), 0, int(f[1]), int(f[2]))


## Um quadro específico de uma folha (ex.: quadro("radio", 1) = rádio ligado).
static func quadro(nome: String, indice: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = textura(nome)
	atlas.region = regiao(nome, indice)
	return atlas


## Cria um Sprite2D com um quadro, no tamanho original da pixel art.
## O ponto de origem fica nos "pés" do objeto (bom para ordenar quem está na frente).
static func criar_sprite(nome: String, indice: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = quadro(nome, indice)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if s.texture:
		if nome == "carro":
			s.scale = Vector2(0.55, 0.55)
			s.offset = Vector2(0, -s.texture.get_size().y * 0.5)
		else:
			s.offset = Vector2(0, -s.texture.get_size().y / 2.0)
	return s


## Monta as animações de um personagem:
## andar_baixo, andar_cima, andar_direita, andar_esquerda,
## parado_baixo, parado_cima, parado_direita, parado_esquerda
##
## Também guarda na "meta" a escala de cada animação, porque cada folha tem um tamanho
## diferente (a do Rafa de frente é minúscula, a do Lucas é enorme...).
static func frames_personagem(personagem: String) -> SpriteFrames:
	if _cache_frames.has(personagem):
		return _cache_frames[personagem]
	var sf := SpriteFrames.new()
	var escalas := {}
	if sf.has_animation("default"):
		sf.remove_animation("default")

	if personagem == "protagonista":
		_montar_protagonista(sf, escalas)
	else:
		var info: Dictionary = PERSONAGENS[personagem]
		# Não existe folha de lado: usamos a de frente andando (fica natural no top-down).
		for dados in [["baixo", info["frente"]], ["cima", info["costas"]], ["direita", info["frente"]], ["esquerda", info["frente"]]]:
			var dir: String = dados[0]
			var folha: String = dados[1]
			var qtd: int = FOLHAS[folha][0]
			var tex := textura(folha)
			_add_anim(sf, "andar_" + dir, 10.0, true)
			for q in qtd:
				sf.add_frame("andar_" + dir, _atlas(tex, regiao(folha, q)))
			_add_anim(sf, "parado_" + dir, 1.0, false)
			sf.add_frame("parado_" + dir, _atlas(tex, regiao(folha, 0)))
			escalas["andar_" + dir] = 1.0
			escalas["parado_" + dir] = 1.0

	sf.set_meta("escalas", escalas)
	_cache_frames[personagem] = sf
	return sf


static func _montar_protagonista(sf: SpriteFrames, escalas: Dictionary) -> void:
	# protagonista_andar.png = grade 4x4 de quadros 32x32.
	# Linha 0: baixo | Linha 1: cima | Linha 2: direita | Linha 3: esquerda
	var tex := textura("protagonista_andar")
	var linhas := ["baixo", "cima", "direita", "esquerda"]
	for l in 4:
		var dir: String = linhas[l]
		_add_anim(sf, "andar_" + dir, 8.0, true)
		for c in 4:
			sf.add_frame("andar_" + dir, _atlas(tex, Rect2(c * 32, l * 32, 32, 32)))
		_add_anim(sf, "parado_" + dir, 1.0, false)
		sf.add_frame("parado_" + dir, _atlas(tex, Rect2(0, l * 32, 32, 32)))
		escalas["andar_" + dir] = 1.0
		escalas["parado_" + dir] = 1.0
	# Parado de frente: usa a animação de respirar (Player.png + Player (1..5).png).
	sf.clear("parado_baixo")
	sf.set_animation_speed("parado_baixo", 4.0)
	sf.set_animation_loop("parado_baixo", true)
	var soltos := ["Player"]
	for i in range(1, 6):
		soltos.append("Player (%d)" % i)
	for nome in soltos:
		var t := textura(nome)
		if t:
			sf.add_frame("parado_baixo", t)


static func _add_anim(sf: SpriteFrames, nome: String, fps: float, loop: bool) -> void:
	sf.add_animation(nome)
	sf.set_animation_speed(nome, fps)
	sf.set_animation_loop(nome, loop)


static func _atlas(tex: Texture2D, r: Rect2) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = tex
	a.region = r
	return a


## Qual personagem o jogador controla, de acordo com a escolha no menu.
static func personagem_do_jogador() -> String:
	return "jogadora" if GameData.personagem_escolhido == "feminino" else "protagonista"
