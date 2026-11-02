class_name MundoPixel
extends Node2D
## =============================================================================
## MundoPixel — onde o mundo do jogo é montado
## =============================================================================
##
## COMO O "EFEITO PIXEL" FUNCIONA AGORA (seguro no celular):
##  1. Tudo no mundo é pixel art de verdade: sprites pequenos + chão, água, madeira,
##     flores e pedras pintados pixel por pixel (pixel_arte.gd).
##  2. Os desenhos por código usam formas em "escadinha" (PixelArte.elipse), nada liso.
##  3. A câmera usa zoom fixo (o mesmo da versão 6.0): cada pixel do mundo vira
##     um quadradinho de ~5x5 na tela.
##  4. Filtro "Nearest" em tudo (project.godot) = pixels nítidos, sem borrão.
##
## SEM SubViewport e SEM PointLight2D: no Mali-G68 eles derrubavam o Godot.
##
## A interface (menus, falas, botões) NÃO passa por aqui: fica em 1280x720, nítida
## e no tamanho certo. (Na 6.4 a resolução do projeto inteiro tinha virado 480x270,
## por isso os menus ficaram GIGANTES.)
##
## LUZES: ficam numa camada própria (camada_luz) que não é escurecida pela noite.
## =============================================================================

## Zoom da versão 6.0 (pixels grandes): zoom(4.0) = 5.0 na câmera do jogo.
const FATOR_ZOOM := 1.25

static var _camada_luz_atual: CanvasLayer = null

var _direto: Node2D
var camada_luz: CanvasLayer


func _init() -> void:
	_direto = Node2D.new()
	_direto.name = "MundoDireto"
	_direto.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED  # azulejos de chão/madeira
	add_child(_direto)

	camada_luz = CanvasLayer.new()
	camada_luz.name = "CamadaLuz"
	camada_luz.layer = 1                   # acima do mundo, abaixo da interface (10+)
	camada_luz.follow_viewport_enabled = true  # acompanha a câmera, como se fosse o mundo
	add_child(camada_luz)
	_camada_luz_atual = camada_luz


func _exit_tree() -> void:
	if _camada_luz_atual == camada_luz:
		_camada_luz_atual = null


static func camada_luz_atual() -> CanvasLayer:
	if _camada_luz_atual and is_instance_valid(_camada_luz_atual):
		return _camada_luz_atual
	return null


func raiz() -> Node:
	return _direto


func adicionar(no: Node) -> void:
	_direto.add_child(no)


## Converte o zoom "do roteiro" no zoom real da câmera (igual à versão 6.0).
## Não depende mais da opção de detalhe: o enquadramento é sempre o mesmo.
func zoom(valor: float) -> Vector2:
	return Vector2.ONE * valor * FATOR_ZOOM


func nivel() -> int:
	return GameData.nivel_detalhe()
