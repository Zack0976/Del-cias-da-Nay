extends Node2D
## ============================================================
##  PARTE 2 — SOBREVIVÊNCIA
## ============================================================
## Este é o "cérebro" da fase. Ele junta todos os sistemas:
##
##   CicloDia ........ relógio, dia/noite, cor do céu
##   StatusJogador ... vida, fome, energia, estresse
##   Inventario ...... mochila (12 espaços, itens empilham)
##   Receitas ........ criação (algumas só na bancada)
##   Abertura ........ porta e janelas com barricadas
##   Monstro ......... os 4 monstros (IA com 6 estados)
##   Iluminacao ...... quem está na luz (tocha, lampião, faróis...)
##   Ruido ........... barulho atrai monstros
##   Carro ........... faróis, esconderijo, bateria
##
## O MUNDO tem duas "salas" ao mesmo tempo:
##   - lá FORA: o parque (ParqueExterior) na posição (0, 0)
##   - lá DENTRO: a cabana (CabanaInterior) longe, na posição (4000, 0)
## Entrar/sair = teletransportar o jogador entre as duas (com um fade).
##
## OBJETIVO: sobreviver 5 noites. No amanhecer do dia 6 chega o resgate.
## ============================================================

const INTERIOR := Vector2(4000, 0)            ## onde fica a cabana por dentro
const LIMITES := Rect2(-1240, -650, 2740, 1300)  ## área jogável lá fora
const CABANA_RET := Rect2(686, -162, 148, 58)   ## parede da cabana (de fora) — termina em y = -104
const CAMADA_GRADE := 16                         ## camada só do jogador (grade da varanda)
const LAGO_CENTRO := Vector2(1090, -300)
const LAGO_RAIO := Vector2(265, 155)
const NOITES_PARA_VENCER := 5

const VEL_ANDAR := 70.0
const VEL_CORRER := 118.0
const VEL_CANSADO := 52.0

# Pontos das aberturas: [lado de fora (global), lado de dentro (local da cabana), retângulo fora, retângulo dentro, hp inicial]
const ABERTURAS := {
	"porta": [Vector2(760, -96), Vector2(144, 178), Rect2(-11, -54, 22, 34), Rect2(132, 189, 24, 9), 60.0],
	"janela_esq": [Vector2(722, -96), Vector2(206, 12), Rect2(-7, -51, 14, 15), Rect2(193, -23, 26, 16), 0.0],
	"janela_dir": [Vector2(797, -96), Vector2(276, 100), Rect2(-6, -51, 14, 15), Rect2(289, 90, 6, 20), 0.0],
}

@onready var player: Player = $Player
@onready var hud: HUD = $HUD

var mundo: MundoPixel
var ext: ParqueExterior
var cab: CabanaInterior
var ambiente: CanvasModulate
var ciclo: CicloDia
var hs: HudSobrevivencia
var carro: Carro
var status := StatusJogador.new()
var inv := Inventario.new()
var achados: Array = []                ## itens que já pegou alguma vez (libera receitas)
var aberturas := {}                    ## id -> Abertura

# Estado do jogador
var jogador_area := "fora"             ## "fora" ou "dentro"
var jogador_escondido := false         ## dentro do carro
var luz_equipada := ""                 ## "", "lanterna" ou "tocha"
var arma_equipada := ""                ## "", "estaca" ou "bastao"
var lanterna_ligada := false
var lanterna_bateria := 100.0
var tocha_tempo := 0.0
var golpes := 0                        ## golpes dados com a arma atual (ela gasta)
var luz_mao: FonteLuz
var usos_vara := 0
var pescando := false
var tocos_pegos: Array = []            ## índices dos tocos/troncos do chão que já foram pegos
var monstro_lago: MonstroAgua

# Casa
var bancada_pos := Vector2.INF         ## local, dentro da cabana (INF = sem bancada)
var _bancada_node: Node2D
var despensa_vasculhada := false
var fogueira_luz: FonteLuz
var lareira_luz: FonteLuz

# Controle
var _ocupado := false                  ## diálogo / criando / dormindo
var _painel := false                   ## mochila ou criação aberta
var _dormindo := false
var _fim := false
var _t_hud := 0.0
var _t_ruido := 0.0
var _t_pressao := 0.0
var _t_sombra := 0.0
var _t_ataque := 0.0
var _ultima_dir := Vector2.RIGHT
var _arvores_pos: Array = []           ## troncos (para colisão e para espalhar recursos)
var _tela: CanvasLayer                 ## fade, dano, fim de jogo
var _fade: ColorRect
var _flash: ColorRect
var _rng := RandomNumberGenerator.new()
var registro: Array[String] = []        ## o que aconteceu (ajuda nos testes)


# ===============================================================
# MONTAGEM DA FASE
# ===============================================================
func _ready() -> void:
	GameData.log_passo("sobrevivencia: começando")
	Iluminacao.limpar()
	await get_tree().process_frame
	mundo = MundoPixel.new()
	add_child(mundo)
	move_child(mundo, 0)
	await get_tree().process_frame

	ambiente = CanvasModulate.new()
	mundo.adicionar(ambiente)

	ext = ParqueExterior.new()
	ext.limites_solidos = LIMITES        # v9: árvores sólidas e tocos que dá para pegar
	ext.portao_fechado = true             # o portão está trancado: não tem como fugir a pé
	mundo.adicionar(ext)
	await get_tree().process_frame
	ext.luzes_cabana(0)
	ext.cortina_fechada = false

	cab = CabanaInterior.new()
	cab.position = INTERIOR
	cab.com_colisao = true
	cab.luz_acesa = false
	cab.lareira_acesa = false
	cab.mensagem_visivel = true
	cab.camas_baguncadas = true
	cab.janela_direita = true
	mundo.adicionar(cab)
	cab.cortina_fechada = false

	ciclo = CicloDia.new()
	add_child(ciclo)

	_criar_colisoes_fora()
	_criar_carro()
	_criar_aberturas()
	_criar_interagiveis()
	_criar_tela()

	hs = HudSobrevivencia.new()
	hs.layer = 9   # abaixo do HUD da Parte 1 (assim a PAUSA cobre tudo)
	hs.inv = inv
	hs.fonte_receitas = func(): return [_receitas_liberadas(), _perto_bancada(), perto_do_fogo()]
	add_child(hs)
	_ligar_hud()

	luz_mao = FonteLuz.criar(66.0, Color(1.0, 0.86, 0.55, 0.45))
	luz_mao.position = Vector2(0, -8)
	luz_mao.ligada = false
	player.add_child(luz_mao)
	if player._glow:   # brilhinho em volta do jogador: pequeno (a luz de verdade é a lanterna)
		player._glow.raio = 24.0
		player._glow.energia = 0.55

	player.collision_mask = 1 | CAMADA_GRADE   # o jogador bate na grade da varanda (monstros não)
	_carregar()
	_colocar_jogador_fora(Vector2(760, -60))
	_criar_coletaveis_do_chao()
	_espalhar_recursos()
	_atualizar_ambiente()
	_atualizar_hud()
	GameData.log_passo("sobrevivencia: pronta")
	if GameData.parte2.is_empty() or int(GameData.parte2.get("dia", 1)) == 1 and not GameData.parte2.get("viu_intro", false):
		_intro()
	_salvar()


func _ligar_hud() -> void:
	# o objetivo fica embaixo das barras (sobe quando as barras são escondidas)
	hs.barras_alternadas.connect(func(v: bool): hud.objetivo_painel.position = Vector2(24, 196 if v else 70))
	hud.objetivo_painel.position = Vector2(24, 196 if GameData.hud_barras else 70)
	hud.itens_label.visible = false
	player.alvo_mudou.connect(hud.mostrar_acao)
	hud.botao_examinar.connect(_on_examinar)
	hs.usar_slot.connect(_usar_slot)
	hs.largar_slot.connect(_largar_slot)
	hs.organizar.connect(func(): inv.organizar(); hs.atualizar_mochila())
	hs.criar_receita.connect(_criar)
	hs.botao_atacar.connect(_atacar)
	hs.botao_luz.connect(_alternar_luz)
	hs.botao_mochila_aberta.connect(_painel_aberto)
	inv.mudou.connect(func():
		hs.atualizar_mochila()
		hs.atualizar_criacao())
	ciclo.mudou_fase.connect(_mudou_fase)
	ciclo.hora_cheia.connect(_hora_cheia)
	ciclo.novo_dia.connect(_novo_dia)
	hud.pausa_painel.visibility_changed.connect(func(): hs.visible = not hud.pausa_painel.visible)


## Troncos, cabana, lago, carro e bordas do mapa viram paredes.
## v9: a colisão de cada árvore fica EXATAMENTE na base do tronco desenhado
## (as árvores novas têm a origem no pé do tronco).
func _criar_colisoes_fora() -> void:
	var corpo := StaticBody2D.new()
	corpo.name = "ColisoesFora"
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	ext.add_child(corpo)
	_arvores_pos = ext.troncos
	for p in _arvores_pos:
		var f := CollisionShape2D.new()
		var cap := CapsuleShape2D.new()   # tronco "deitado": mais largo que alto (visão de cima)
		cap.radius = 3.0
		cap.height = 9.0
		f.shape = cap
		f.rotation = PI / 2.0
		f.position = p + Vector2(0, -1)
		corpo.add_child(f)
	# CABANA: paredes + varanda. A varanda tem grade dos lados e na frente,
	# com a ESCADA aberta no meio — dá para subir e chegar na porta.
	_retangulo(corpo, CABANA_RET)
	var grade := StaticBody2D.new()
	grade.name = "GradeVaranda"
	grade.collision_layer = CAMADA_GRADE
	grade.collision_mask = 0
	ext.add_child(grade)
	_retangulo(grade, Rect2(682, -104, 6, 26))     # lado esquerdo
	_retangulo(grade, Rect2(832, -104, 6, 26))     # lado direito
	_retangulo(grade, Rect2(686, -84, 46, 5))      # frente, à esquerda da escada
	_retangulo(grade, Rect2(788, -84, 46, 5))      # frente, à direita da escada
	# lago (polígono em forma de elipse)
	var pts := PackedVector2Array()
	for i in 24:
		var ang := TAU * i / 24.0
		pts.append(LAGO_CENTRO + Vector2(cos(ang) * LAGO_RAIO.x, sin(ang) * LAGO_RAIO.y))
	var forma := CollisionShape2D.new()
	var conv := ConvexPolygonShape2D.new()
	conv.points = pts
	forma.shape = conv
	corpo.add_child(forma)
	# bordas
	var r := LIMITES
	_retangulo(corpo, Rect2(r.position.x - 100, r.position.y - 100, r.size.x + 200, 100))
	_retangulo(corpo, Rect2(r.position.x - 100, r.end.y, r.size.x + 200, 100))
	_retangulo(corpo, Rect2(r.position.x - 100, r.position.y, 100, r.size.y))
	_retangulo(corpo, Rect2(r.end.x, r.position.y, 100, r.size.y))


func _circulo(corpo: StaticBody2D, p: Vector2, raio: float) -> void:
	var f := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = raio
	f.shape = c
	f.position = p
	corpo.add_child(f)


func _retangulo(corpo: StaticBody2D, r: Rect2) -> void:
	var f := CollisionShape2D.new()
	var s := RectangleShape2D.new()
	s.size = r.size
	f.shape = s
	f.position = r.get_center()
	corpo.add_child(f)


func _criar_carro() -> void:
	carro = Carro.new()
	carro.name = "Carro"
	carro.position = ParqueExterior.PONTOS["carro_para"]
	# IMPORTANTE: pegar os obstáculos ANTES de pôr o sprite do carro no mundo,
	# senão o próprio carro "bloquearia" a luz dos faróis.
	carro.obstaculos = ext.obstaculos_luz()
	carro.sprite = SpriteLibrary.criar_sprite("carro", 0)
	carro.sprite.position = carro.position
	ext.arvores.add_child(carro.sprite)
	ext.add_child(carro)
	var corpo := StaticBody2D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	carro.add_child(corpo)
	# v9: a colisão cobre a parte de baixo da lataria (o carro ocupa y -38..0)
	_retangulo(corpo, Rect2(-29, -22, 58, 21))


func _criar_aberturas() -> void:
	for id in ABERTURAS:
		var d: Array = ABERTURAS[id]
		var a := Abertura.new()
		a.id = id
		a.name = "Abertura_" + id
		a.position = d[0]
		a.ponto_dentro = INTERIOR + d[1]
		a.retangulo_fora = d[2]
		var dentro := Node2D.new()
		dentro.name = "Tabuas_" + id
		dentro.z_index = 2
		cab.add_child(dentro)
		a.desenho_dentro = dentro
		a.retangulo_dentro = d[3]
		a.hp = d[4]
		ext.add_child(a)
		a.quebrou.connect(_abertura_quebrou)
		aberturas[id] = a


func _criar_interagiveis() -> void:
	# lá fora (o parque está na posição 0,0: posições já são globais)
	for d in [
		["entrar", Vector2(760, -100), 12.0, "ENTRAR"],
		["carro", ParqueExterior.PONTOS["carro_para"] + Vector2(0, 4), 26.0, "CARRO"],
		["fogueira", ParqueExterior.PONTOS["fogueira"], 18.0, "FOGUEIRA"],
		["portao", Vector2(-1225, 0), 30.0, "EXAMINAR"],
	]:
		ext.add_child(Interagivel.criar(d[0], d[1], d[2], d[3]))
	# beira do lago: vários pontos em volta (beber e pescar)
	for ang in [0.35, 1.2, 1.9, 2.6, 3.3, 4.2, 5.4]:
		var p := LAGO_CENTRO + Vector2(cos(ang) * (LAGO_RAIO.x + 12), sin(ang) * (LAGO_RAIO.y + 12))
		if LIMITES.grow(-10).has_point(p):
			ext.add_child(Interagivel.criar("lago", p.round(), 26.0, "LAGO"))
	# dentro da cabana (posições locais)
	for d in [
		["sair", Vector2(144, 184), 14.0, "PORTA"],
		["janela_cima", Vector2(206, 6), 16.0, "JANELA"],
		["janela_lado", Vector2(278, 100), 14.0, "JANELA"],
		["cama", Vector2(21, 46), 14.0, "DORMIR"],
		["lareira", Vector2(22, 104), 14.0, "LAREIRA"],
		["despensa", Vector2(35, 170), 16.0, "VASCULHAR"],
	]:
		cab.add_child(Interagivel.criar(d[0], d[1], d[2], d[3]))


func _criar_tela() -> void:
	_tela = CanvasLayer.new()
	_tela.layer = 30
	add_child(_tela)
	_flash = ColorRect.new()
	_flash.color = Color(0.7, 0.0, 0.0, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tela.add_child(_flash)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.modulate.a = 0.0
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tela.add_child(_fade)


func _intro() -> void:
	_ocupado = true
	player.definir_pode_mover(false)
	hud.modo_conversa(true)
	await get_tree().create_timer(0.6).timeout
	await hud.dialogo.mensagem("O sol nasceu. Você sobreviveu à primeira noite… mas o portão do parque está trancado.")
	await hud.dialogo.mensagem("O rádio disse: o resgate chega em 5 dias. Você precisa aguentar 5 NOITES.")
	await hud.dialogo.mensagem("De dia: junte madeira, pedras e comida. Galhos, TOCOS e TRONCOS CAÍDOS no chão viram madeira!")
	await hud.dialogo.mensagem("Chegue perto: aparece uma setinha em cima e o botão vira PEGAR. Toque nele (ou aperte E).")
	await hud.dialogo.mensagem("Com madeira e pedra, crie uma BANCADA (botão CRIAR) e coloque dentro da cabana.")
	await hud.dialogo.mensagem("Antes de escurecer: pregue tábuas na porta e nas janelas. Toda manhã elas racham e precisam de reforço.")
	await hud.dialogo.mensagem("A luz é sua melhor arma. O barulho é seu pior inimigo.")
	GameData.parte2["viu_intro"] = true
	hud.modo_conversa(false)
	_ocupado = false
	player.definir_pode_mover(true)
	_atualizar_objetivo()


# ===============================================================
# LOOP PRINCIPAL
# ===============================================================
func _physics_process(delta: float) -> void:
	if _fim or mundo == null or ciclo == null:
		return
	_movimento(delta)
	_luzes(delta)
	_t_ataque = maxf(_t_ataque - delta, 0.0)

	var ctx := {
		"correndo": player.velocidade > VEL_ANDAR and player.velocity.length() > 20.0,
		"parado": player.velocity.length() < 5.0 or jogador_escondido,
		"no_escuro": not Iluminacao.esta_iluminado(player.global_position),
		"noite": ciclo.eh_noite(),
		"monstro_perto": _monstro_perto(100.0) != null or _monstro_lago_perto(90.0),
		"observador_visivel": _observador_visivel(),
		"em_seguranca": _em_seguranca(),
	}
	if not ciclo.eh_noite() and ciclo.fase != "entardecer":
		ctx["no_escuro"] = false   # de dia não existe escuro
	if not _dormindo:
		status.atualizar(delta, ctx)
	if status.morto():
		_morrer()
		return
	_ruido_do_jogador(delta)
	_pressao_da_noite(delta)

	_t_hud += delta
	if _t_hud > 0.2:
		_t_hud = 0.0
		_atualizar_hud()
		_atualizar_ambiente()
		_conferir_monstros()
		_destacar_coletavel()


func _movimento(_delta: float) -> void:
	var correr := (Input.is_action_pressed("correr") or hs.correr_pressionado) and status.pode_correr()
	if status.energia < 12.0:
		player.velocidade = VEL_CANSADO      # cansado demais: anda devagar
	elif correr:
		player.velocidade = VEL_CORRER
	else:
		player.velocidade = VEL_ANDAR
	if player.velocity.length() > 10.0:
		_ultima_dir = player.velocity.normalized()


## Barulho dos passos: correr faz MUITO barulho, andar faz pouco.
func _ruido_do_jogador(delta: float) -> void:
	_t_ruido -= delta
	if _t_ruido > 0.0 or player.velocity.length() < 20.0:
		return
	if player.velocidade >= VEL_CORRER:
		_t_ruido = 0.4
		ruido(player.global_position, 85.0)
	else:
		_t_ruido = 1.0
		ruido(player.global_position, 18.0)


## Emite barulho. Barulho DENTRO da cabana também é ouvido lá fora (abafado),
## e quem ouve vai atacar a casa.
func ruido(pos: Vector2, raio: float) -> void:
	Ruido.emitir(get_tree(), pos, raio)
	if pos.x > INTERIOR.x - 500.0:
		var fora := Vector2(760, -80)
		var abafado := raio * 0.7
		for m in get_tree().get_nodes_in_group("monstro"):
			if m.area == "fora" and m.global_position.distance_to(fora) <= abafado + m.audicao:
				m.atacar_casa()


## De noite os monstros "sentem" que tem alguém na cabana. Luz na janela aberta piora.
func _pressao_da_noite(delta: float) -> void:
	if not ciclo.eh_noite():
		return
	_t_pressao += delta
	if _t_pressao >= 8.0:
		_t_pressao = 0.0
		if jogador_area == "dentro":
			var luz_na_janela := ext.luz_dentro and not ext.cortina_fechada
			var chance := 0.2 + 0.08 * ciclo.noite_numero() + (0.35 if luz_na_janela else 0.0)
			for m in get_tree().get_nodes_in_group("monstro"):
				if m.area == "fora" and m.estado in [Monstro.Estado.IDLE, Monstro.Estado.PATROL, Monstro.Estado.SEARCH] and _rng.randf() < chance:
					m.atacar_casa()
			if luz_na_janela:
				registro.append("luz_janela_atraiu")
	# A Sombra caça quem está sozinho no escuro
	_t_sombra += delta
	if _t_sombra >= 6.0:
		_t_sombra = 0.0
		if jogador_area == "fora" and not jogador_escondido and Iluminacao.distancia_luz(player.global_position) > 120.0:
			for m in get_tree().get_nodes_in_group("monstro"):
				if m.tipo_monstro == "sombra":
					m.ouviu(player.global_position, 999.0)


# ===============================================================
# API USADA PELOS MONSTROS (monstro.gd chama estas funções)
# ===============================================================
func saida_interior() -> Vector2:
	return INTERIOR + Vector2(144, 178)


func ponto_janela_observador() -> Vector2:
	return Vector2(700, 20)   # na frente da cabana, olhando para a janela com cortina


func ponto_valido(p: Vector2) -> Vector2:
	if p.x > INTERIOR.x - 500.0:   # ponto dentro da cabana
		p.x = clampf(p.x, INTERIOR.x + 12, INTERIOR.x + CabanaInterior.LARGURA - 12)
		p.y = clampf(p.y, 12, CabanaInterior.ALTURA - 12)
		return p
	p.x = clampf(p.x, LIMITES.position.x + 20, LIMITES.end.x - 20)
	p.y = clampf(p.y, LIMITES.position.y + 20, LIMITES.end.y - 20)
	var d := (p - LAGO_CENTRO) / (LAGO_RAIO + Vector2(12, 12))
	if d.length() < 1.0:
		p = LAGO_CENTRO + d.normalized() * (LAGO_RAIO + Vector2(16, 16))
	if CABANA_RET.grow(8).has_point(p):
		p.y = CABANA_RET.end.y + 30
	return p


func escolher_abertura(m: Node) -> Abertura:
	var melhor: Abertura = null
	var nota := INF
	for a in aberturas.values():
		var n: float = a.hp + m.global_position.distance_to(a.global_position) * 0.3
		if a.aberta() and m.tipo_monstro != "colosso":
			n -= 1000.0    # janela sem proteção: é por ali que eles entram!
		if n < nota:
			nota = n
			melhor = a
	return melhor


func monstro_entra(m: Node, ab: Abertura) -> void:
	if m.area == "dentro":
		return
	m.area = "dentro"
	_trocar_pai.call_deferred(m, cab.objetos, ab.ponto_dentro)
	Sons.tocar(self, "rangido", -2.0, 0.8)
	registro.append("entrou:%s:%s" % [m.tipo_monstro, ab.id])
	if jogador_area == "dentro":
		hs.avisar("Alguma coisa entrou pela %s!" % ("porta" if ab.id == "porta" else "janela"))
		tremer_tela(3.0)


func monstro_sai(m: Node) -> void:
	if m.area == "fora":
		return
	m.area = "fora"
	_trocar_pai.call_deferred(m, ext.arvores, Vector2(760, -76))


## Garante que cada monstro está desenhado na "sala" certa (fora/dentro).
func _conferir_monstros() -> void:
	for m in get_tree().get_nodes_in_group("monstro"):
		var pai: Node = cab.objetos if m.area == "dentro" else ext.arvores
		if m.get_parent() != pai:
			_trocar_pai(m, pai, m.global_position)


func _trocar_pai(m: Node, pai: Node, pos_global: Vector2) -> void:
	if not is_instance_valid(m):
		return
	m.reparent(pai)
	m.global_position = pos_global


func ferir_jogador(dano: float, m: Node) -> void:
	if _fim or _dormindo:
		return
	if jogador_escondido:
		if m.tipo_monstro == "colosso":
			_sair_do_carro()
			hs.avisar("O Colosso arrancou você do carro!")
		else:
			return
	status.vida = maxf(status.vida - dano, 0.0)
	status.estresse = minf(status.estresse + 8.0, 100.0)
	registro.append("dano:%s" % m.tipo_monstro)
	Sons.tocar(self, "batida", -2.0, 1.3)
	tremer_tela(4.0)
	_flash.color.a = 0.45
	create_tween().tween_property(_flash, "color:a", 0.0, 0.5)
	_atualizar_hud()


func tremer_tela(forca: float) -> void:
	if player.camera == null:
		return
	var tw := create_tween()
	for i in 6:
		tw.tween_property(player.camera, "offset", Vector2(randf_range(-forca, forca), randf_range(-forca, forca)), 0.04)
	tw.tween_property(player.camera, "offset", Vector2.ZERO, 0.05)


# ===============================================================
# DIA E NOITE
# ===============================================================
func _mudou_fase(fase: String) -> void:
	match fase:
		"entardecer":
			hs.anunciar("ESTÁ ESCURECENDO", Color(0.95, 0.6, 0.3))
			hs.avisar("Volte para a cabana e reforce portas e janelas!")
		"noite":
			hs.anunciar("NOITE %d" % ciclo.noite_numero())
			Sons.tocar(self, "coruja", -6.0, 0.9)
			_spawn_da_hora(19)
			spawnar_lago()
		"amanhecer":
			hs.anunciar("AMANHECENDO", Color(0.95, 0.8, 0.5))
			for m in get_tree().get_nodes_in_group("monstro"):
				m.ir_embora()
			if monstro_lago and is_instance_valid(monstro_lago):
				monstro_lago.ir_embora()
	_atualizar_objetivo()


func _hora_cheia(h: int) -> void:
	if ciclo.eh_noite() and h != 19:
		_spawn_da_hora(h)


func _novo_dia(dia: int) -> void:
	registro.append("dia:%d" % dia)
	if dia > NOITES_PARA_VENCER:
		_vitoria()
		return
	for a in aberturas.values():
		a.desgastar()     # madeira racha, prego solta: reforce de novo à noite!
	_espalhar_recursos()
	hs.anunciar("DIA %d" % dia, Color(0.95, 0.85, 0.6))
	hs.avisar("As barricadas racharam durante a noite.")
	_salvar()


## Quem aparece em cada hora da noite (fica mais difícil a cada noite).
func _spawn_da_hora(h: int) -> void:
	var n := ciclo.noite_numero()
	match h:
		19:
			spawnar("observador")
			spawnar("rastejante")
		20:
			if n >= 2:
				spawnar("sombra")
		21:
			if n >= 2:
				spawnar("rastejante")
		22:
			if n == 3 or n >= 5:
				spawnar("colosso")
		23:
			if n >= 3:
				spawnar("rastejante")
		0:
			if n >= 4:
				spawnar("sombra")


## O monstro do lago aparece toda noite (mas só ataca quem chega na beira).
func spawnar_lago() -> MonstroAgua:
	if monstro_lago and is_instance_valid(monstro_lago) and not monstro_lago.indo_embora:
		return monstro_lago
	monstro_lago = MonstroAgua.criar(self, ext.agua)
	ext.add_child(monstro_lago)
	registro.append("spawn:agua")
	return monstro_lago


func spawnar(tipo: String, pos := Vector2.INF) -> Monstro:
	if pos == Vector2.INF:
		var centro := player.global_position if jogador_area == "fora" else Vector2(760, -40)
		for tentativa in 20:
			var ang := _rng.randf() * TAU
			var p := ponto_valido(centro + Vector2(cos(ang), sin(ang)) * _rng.randf_range(320, 480))
			pos = p
			if p.distance_to(centro) > 300.0 and not Iluminacao.esta_iluminado(p, 30.0):
				break
	var m := Monstro.criar(tipo, pos, self)
	ext.arvores.add_child(m)
	registro.append("spawn:" + tipo)
	return m


func _atualizar_ambiente() -> void:
	var cor := ciclo.cor_ambiente()
	if jogador_area == "dentro":
		cor = cor.lerp(Color(0.42, 0.38, 0.36), 0.35)   # dentro é mais protegido do escuro total
	cor = cor.darkened(status.prejuizo_visao() * 0.25)   # estresse/cansaço escurecem a visão
	ambiente.color = cor
	# luz de dentro da cabana aparecendo pela janela (se a cortina estiver aberta)
	var luz_dentro := (lareira_luz != null and lareira_luz.ativa()) or (jogador_area == "dentro" and luz_mao.ativa())
	if ext.luz_dentro != luz_dentro:
		ext.luz_dentro = luz_dentro


# ===============================================================
# LUZ NA MÃO (lanterna / tocha)
# ===============================================================
func _luzes(delta: float) -> void:
	match luz_equipada:
		"lanterna":
			if lanterna_ligada:
				lanterna_bateria = maxf(lanterna_bateria - 0.5 * delta, 0.0)
				if lanterna_bateria <= 0.0:
					lanterna_ligada = false
					hs.avisar("A bateria da lanterna acabou!")
			luz_mao.ligada = lanterna_ligada and not jogador_escondido
			luz_mao.definir_raio(40.0 + 26.0 * clampf(lanterna_bateria / 30.0, 0.0, 1.0))
		"tocha":
			tocha_tempo -= delta
			luz_mao.ligada = not jogador_escondido
			if tocha_tempo <= 0.0:
				luz_equipada = ""
				luz_mao.ligada = false
				hs.avisar("A tocha apagou.")
		_:
			luz_mao.ligada = false


func _alternar_luz() -> void:
	if _ocupado or _fim:
		return
	if luz_equipada == "lanterna":
		if lanterna_bateria <= 0.0:
			hs.avisar("Sem bateria. Use uma Bateria da mochila.")
			return
		lanterna_ligada = not lanterna_ligada
		Sons.tocar(self, "clique", -8.0)
	elif luz_equipada == "tocha":
		hs.avisar("A tocha não apaga: ela queima até o fim.")
	elif inv.tem("lanterna"):
		_equipar_luz("lanterna")
		lanterna_ligada = lanterna_bateria > 0.0
		Sons.tocar(self, "clique", -8.0)
	elif inv.tem("tocha"):
		_usar_item("tocha", -1)
	else:
		hs.avisar("Você não tem lanterna nem tocha.")
	_atualizar_hud()


func _equipar_luz(id: String) -> void:
	luz_equipada = id
	if id == "tocha":
		luz_mao.definir_cor(Color(1.0, 0.6, 0.25, 0.5))
		luz_mao.definir_raio(80.0)
		luz_mao._luz.tremer = 0.15
	else:
		luz_mao.definir_cor(Color(1.0, 0.88, 0.6, 0.45))
		luz_mao._luz.tremer = 0.0


# ===============================================================
# INTERAÇÃO (botão EXAMINAR / tecla E)
# ===============================================================
func _unhandled_input(event: InputEvent) -> void:
	if _fim:
		return
	if event.is_action_pressed("interagir") and hs.pesca.visible:
		hs.puxar()
	elif event.is_action_pressed("interagir") and not hud.dialogo.esta_ocupado() and not _painel:
		_on_examinar()
	elif event.is_action_pressed("atacar"):
		_atacar()
	elif event.is_action_pressed("luz"):
		_alternar_luz()
	elif event.is_action_pressed("mochila"):
		hs.abrir_mochila(not hs.mochila.visible)
	elif event.is_action_pressed("criar"):
		hs.abrir_criacao(not hs.criacao.visible)


func _painel_aberto(sim: bool) -> void:
	_painel = sim
	if _ocupado and not sim:
		return
	player.definir_pode_mover(not sim and not jogador_escondido)
	hud.modo_conversa(sim)
	if not sim:
		hud.mostrar_acao(player.alvo)


func _on_examinar() -> void:
	if _ocupado or _fim or _painel or player.alvo == null:
		return
	var alvo: Interagivel = player.alvo
	await interagir(alvo.id, alvo)


## Também usado pelos testes automáticos.
func interagir(id: String, alvo: Interagivel = null) -> void:
	if id.begins_with("coletar_"):
		_coletar(alvo.get_parent() as Coletavel)
		return
	match id:
		"entrar":
			await _entrar()
		"sair":
			var r := await hs.escolher("PORTA (%s)" % _texto_hp(aberturas["porta"]), ["SAIR DA CABANA", "PREGAR TÁBUAS (+50)", "REFORÇO DE METAL (+100)"])
			match r:
				"SAIR DA CABANA": await _sair()
				"PREGAR TÁBUAS (+50)": reforcar("porta", "barricada")
				"REFORÇO DE METAL (+100)": reforcar("porta", "reforco")
		"janela_cima":
			var txt := "FECHAR CORTINA" if not cab.cortina_fechada else "ABRIR CORTINA"
			var r := await hs.escolher("JANELA (%s)" % _texto_hp(aberturas["janela_esq"]), [txt, "PREGAR TÁBUAS (+50)", "REFORÇO DE METAL (+100)"])
			match r:
				"FECHAR CORTINA": cortina(true)
				"ABRIR CORTINA": cortina(false)
				"PREGAR TÁBUAS (+50)": reforcar("janela_esq", "barricada")
				"REFORÇO DE METAL (+100)": reforcar("janela_esq", "reforco")
		"janela_lado":
			var r := await hs.escolher("JANELINHA (%s)" % _texto_hp(aberturas["janela_dir"]), ["PREGAR TÁBUAS (+50)", "REFORÇO DE METAL (+100)"])
			match r:
				"PREGAR TÁBUAS (+50)": reforcar("janela_dir", "barricada")
				"REFORÇO DE METAL (+100)": reforcar("janela_dir", "reforco")
		"cama":
			await dormir()
		"lareira":
			acender_lareira()
		"despensa":
			_vasculhar_despensa()
		"bancada":
			hs.abrir_criacao(true)
		"carro":
			await _menu_carro()
		"lago":
			var op: Array = ["BEBER ÁGUA"]
			if inv.tem("vara_pescar"):
				op.push_front("PESCAR")
			else:
				hs.avisar("Dica: crie uma VARA DE PESCAR (2 madeira + 1 corda).")
			var r := await hs.escolher("LAGO", op)
			if r == "BEBER ÁGUA":
				status.energia = minf(status.energia + 15.0, 100.0)
				Sons.tocar(self, "passo", -6.0, 0.6)
				ext.agua.respingo(_ponto_lago_perto(), 0.8)
				ruido(player.global_position, 30.0)
				hs.avisar("Você bebe a água gelada do lago e desperta. (+15 energia)")
			elif r == "PESCAR":
				await pescar()
		"fogueira":
			acender_fogueira()
		"portao":
			hs.avisar("Trancado com corrente. O resgate vai vir por aqui.")
	_atualizar_hud()


func _texto_hp(a: Abertura) -> String:
	if a.aberta():
		return "SEM PROTEÇÃO"
	return "resistência %d" % roundi(a.hp)


# ---------------------------------------------------------------
# ENTRAR / SAIR DA CABANA
# ---------------------------------------------------------------
func _entrar() -> void:
	_ocupado = true
	player.definir_pode_mover(false)
	await _fazer_fade(1.0, 0.25)
	Sons.tocar(self, "rangido", -6.0)
	jogador_area = "dentro"
	player.reparent(cab.objetos, false)
	player.position = Vector2(144, 168)
	_camera_dentro()
	_atualizar_ambiente()
	await _fazer_fade(0.0, 0.25)
	_ocupado = false
	player.definir_pode_mover(true)
	_atualizar_objetivo()


func _sair() -> void:
	_ocupado = true
	player.definir_pode_mover(false)
	await _fazer_fade(1.0, 0.25)
	Sons.tocar(self, "rangido", -6.0)
	_colocar_jogador_fora(Vector2(760, -92))
	_atualizar_ambiente()
	await _fazer_fade(0.0, 0.25)
	_ocupado = false
	player.definir_pode_mover(true)
	_atualizar_objetivo()


func _colocar_jogador_fora(pos: Vector2) -> void:
	jogador_area = "fora"
	if player.get_parent() != ext.arvores:
		player.reparent(ext.arvores, false)
	player.position = pos
	player.camera.zoom = mundo.zoom(4.0)
	player.camera.limit_left = int(LIMITES.position.x) - 40
	player.camera.limit_right = int(LIMITES.end.x) + 40
	player.camera.limit_top = int(LIMITES.position.y) - 40
	player.camera.limit_bottom = int(LIMITES.end.y) + 40
	player.camera.make_current()
	player.camera.reset_smoothing()


func _camera_dentro() -> void:
	player.camera.limit_left = int(INTERIOR.x) - 90
	player.camera.limit_right = int(INTERIOR.x) + 378
	player.camera.limit_top = -110
	player.camera.limit_bottom = 300
	player.camera.make_current()
	player.camera.reset_smoothing()


func _fazer_fade(alvo: float, tempo: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", alvo, tempo)
	await tw.finished


# ---------------------------------------------------------------
# CORTINA, BARRICADAS, FOGO
# ---------------------------------------------------------------
## Cortina fechada: não sai luz de dentro, não entra a luz da lua e o Observador
## não consegue espiar. Aberta: dá para ver lá fora (mas eles também veem você).
func cortina(fechada: bool) -> void:
	cab.cortina_fechada = fechada
	ext.cortina_fechada = fechada
	Sons.tocar(self, "rangido", -14.0, 1.8)
	hs.avisar("Cortina fechada." if fechada else "Cortina aberta.")


func reforcar(id_abertura: String, item: String) -> bool:
	if not inv.tem(item):
		hs.avisar("Você precisa de %s. (Crie na bancada)" % Itens.nome(item))
		return false
	var a: Abertura = aberturas[id_abertura]
	if a.hp >= Abertura.MAX_HP:
		hs.avisar("Já está no máximo!")
		return false
	inv.remover(item)
	a.reforcar(50.0 if item == "barricada" else 100.0)
	Sons.tocar(self, "batida", -4.0, 1.1)
	ruido(player.global_position, 110.0)   # martelar faz barulho!
	hs.avisar("Reforçado! Resistência: %d" % roundi(a.hp))
	return true


func _abertura_quebrou(a: Abertura) -> void:
	registro.append("quebrou:" + a.id)
	Sons.tocar(self, "batida", 4.0, 0.6)
	if jogador_area == "dentro":
		hs.avisar("A barricada da %s quebrou!" % ("porta" if a.id == "porta" else "janela"))
		tremer_tela(5.0)


func acender_fogueira() -> bool:
	if fogueira_luz and fogueira_luz.ativa():
		hs.avisar("A fogueira já está acesa.")
		return false
	if not (inv.tem("madeira", 2) and inv.tem("fosforos")):
		hs.avisar("Precisa de 2 Madeira e 1 Fósforo.")
		return false
	inv.remover("madeira", 2)
	inv.remover("fosforos")
	if fogueira_luz == null:
		fogueira_luz = FonteLuz.criar(90.0, Color(1.0, 0.55, 0.2, 0.5), -1.0, 0.18)
		fogueira_luz.position = ParqueExterior.PONTOS["fogueira"] + Vector2(0, -4)
		fogueira_luz.apagou.connect(func(): ext.fogueira_acesa = false)
		ext.add_child(fogueira_luz)
	fogueira_luz.duracao = 160.0       # ~8 horas do jogo
	fogueira_luz.ligada = true
	ext.fogueira_acesa = true
	Sons.tocar(self, "clique", -4.0, 0.7)
	hs.avisar("Fogueira acesa! Luz forte lá fora por ~8 horas.")
	return true


func acender_lareira() -> bool:
	if lareira_luz and lareira_luz.ativa():
		hs.avisar("A lareira já está acesa.")
		return false
	if not (inv.tem("madeira", 2) and inv.tem("fosforos")):
		hs.avisar("Precisa de 2 Madeira e 1 Fósforo.")
		return false
	inv.remover("madeira", 2)
	inv.remover("fosforos")
	if lareira_luz == null:
		lareira_luz = FonteLuz.criar(10.0, Color(0, 0, 0, 0))   # o brilho já é da cabana
		lareira_luz.position = Vector2(22, 104)
		lareira_luz.raio_protecao = 75.0
		lareira_luz.apagou.connect(func(): cab.lareira_acesa = false)
		cab.add_child(lareira_luz)
	lareira_luz.duracao = 160.0
	lareira_luz.ligada = true
	cab.lareira_acesa = true
	cab.luz_acesa = true
	hs.avisar("Lareira acesa. Cuidado: com a cortina aberta, a luz aparece lá fora!")
	return true


func _vasculhar_despensa() -> void:
	if despensa_vasculhada:
		hs.avisar("A despensa está vazia.")
		return
	despensa_vasculhada = true
	_ganhar({"enlatado": 2, "agua": 2, "fosforos": 3, "tecido": 2, "corda": 1})


# ---------------------------------------------------------------
# CARRO
# ---------------------------------------------------------------
func _menu_carro() -> void:
	var op: Array = []
	if jogador_escondido:
		op.append("SAIR DO CARRO")
	else:
		op.append("ESCONDER-SE NO CARRO")
	if not carro.vasculhado:
		op.append("VASCULHAR")
	if not carro.bateria_removida:
		op.append("DESLIGAR FARÓIS" if carro.farois else "LIGAR FARÓIS (%d%%)" % roundi(carro.bateria))
		op.append("TIRAR A BATERIA")
	var r := await hs.escolher("CARRO", op)
	if r == "SAIR DO CARRO":
		_sair_do_carro()
	elif r == "ESCONDER-SE NO CARRO":
		_esconder_no_carro()
	elif r == "VASCULHAR":
		carro.vasculhado = true
		_ganhar({"corda": 2, "metal": 2, "agua": 1, "enlatado": 1, "tecido": 1})
		ruido(player.global_position, 50.0)
	elif r.begins_with("LIGAR FARÓIS"):
		if not carro.ligar_farois(true):
			hs.avisar("A bateria do carro acabou.")
	elif r == "DESLIGAR FARÓIS":
		carro.ligar_farois(false)
	elif r == "TIRAR A BATERIA":
		var q := carro.remover_bateria()
		_ganhar({"bateria": q})
		hs.avisar("Agora os faróis não acendem mais.")


func _esconder_no_carro() -> void:
	jogador_escondido = true
	player.visible = false
	player.definir_pode_mover(false)
	player.velocity = Vector2.ZERO
	player.global_position = carro.global_position + Vector2(0, 6)
	Sons.tocar(self, "clique", -6.0, 0.6)
	hs.avisar("Escondido. O Rastejante e a Sombra não te enxergam aqui… o Colosso sim.")


func _sair_do_carro() -> void:
	jogador_escondido = false
	player.visible = true
	player.definir_pode_mover(not _painel)
	player.global_position = carro.global_position + Vector2(0, 14)


# ===============================================================
# COLETA E MOCHILA
# ===============================================================
func _coletar(c: Coletavel) -> void:
	if c == null or not is_instance_valid(c):
		return
	var sobra := inv.adicionar(c.item, c.qtd)
	if sobra == c.qtd:
		hs.avisar("Mochila cheia! Largue ou organize alguma coisa.")
		return
	hs.avisar("+%d %s" % [c.qtd - sobra, Itens.nome(c.item)])
	if c.item not in achados:
		achados.append(c.item)
	Sons.tocar(self, "item" if c.ruido <= 0.0 else "galho", -8.0)
	ruido(c.global_position, c.ruido)
	if sobra > 0:
		c.qtd = sobra
	else:
		if c.has_meta("toco"):
			tocos_pegos.append(c.get_meta("toco"))
		c.queue_free()


func _ganhar(itens: Dictionary) -> void:
	var partes: Array[String] = []
	for id in itens:
		var q: int = itens[id]
		if q <= 0:
			continue
		var sobra := inv.adicionar(id, q)
		if q - sobra > 0:
			partes.append("+%d %s" % [q - sobra, Itens.nome(id)])
		if id not in achados:
			achados.append(id)
	Sons.tocar(self, "item", -6.0)
	hs.avisar("  ".join(partes) if not partes.is_empty() else "Mochila cheia!")


func _usar_slot(i: int) -> void:
	if inv.slots[i].is_empty():
		return
	_usar_item(inv.slots[i]["id"], i)
	hs.atualizar_mochila()


func _largar_slot(i: int) -> void:
	var s: Dictionary = inv.slots[i]
	if s.is_empty():
		return
	var c := Coletavel.criar(s["id"], s["qtd"], player.global_position + _ultima_dir * 10.0)
	inv.slots[i] = {}
	inv.mudou.emit()
	_pai_atual().add_child(c)
	c.global_position = player.global_position + _ultima_dir * 10.0
	if s["id"] == luz_equipada and not inv.tem(s["id"]):
		luz_equipada = ""
	if s["id"] == arma_equipada and not inv.tem(s["id"]):
		arma_equipada = ""


func _pai_atual() -> Node:
	return cab.objetos if jogador_area == "dentro" else ext.arvores


## USAR um item da mochila. "slot" = de onde tirar (-1 = qualquer um).
func _usar_item(id: String, slot: int) -> bool:
	var gastar := func():
		if slot >= 0:
			inv.remover_do_slot(slot)
		else:
			inv.remover(id)
	match id:
		"fruta":
			status.fome = minf(status.fome + 20.0, 100.0)
			gastar.call()
		"enlatado":
			status.fome = minf(status.fome + 45.0, 100.0)
			gastar.call()
			ruido(player.global_position, 25.0)   # abrir a lata faz barulhinho
		"agua":
			status.energia = minf(status.energia + 25.0, 100.0)
			gastar.call()
		"ervas":
			status.vida = minf(status.vida + 10.0, 100.0)
			status.estresse = maxf(status.estresse - 10.0, 0.0)
			gastar.call()
		"kit":
			status.vida = minf(status.vida + 40.0, 100.0)
			gastar.call()
		"peixe":
			status.fome = minf(status.fome + 10.0, 100.0)
			gastar.call()
			if _rng.randf() < 0.5:
				status.vida = maxf(status.vida - 5.0, 1.0)
				hs.avisar("Peixe cru… sua barriga reclamou. (-5 vida)")
		"peixe_assado":
			status.fome = minf(status.fome + 40.0, 100.0)
			status.vida = minf(status.vida + 5.0, 100.0)
			gastar.call()
		"ensopado":
			status.fome = minf(status.fome + 50.0, 100.0)
			status.vida = minf(status.vida + 15.0, 100.0)
			status.energia = minf(status.energia + 20.0, 100.0)
			gastar.call()
		"cha":
			status.estresse = maxf(status.estresse - 35.0, 0.0)
			status.energia = minf(status.energia + 10.0, 100.0)
			gastar.call()
		"vara_pescar":
			hs.avisar("Vá até a beira do lago e toque em LAGO → PESCAR.")
			return false
		"sinalizador":
			gastar.call()
			_jogar_sinalizador(player.global_position + _ultima_dir * 40.0)
		"bateria":
			if lanterna_bateria >= 99.0:
				hs.avisar("A lanterna já está cheia.")
				return false
			lanterna_bateria = minf(lanterna_bateria + 60.0, 100.0)
			gastar.call()
			hs.avisar("Lanterna recarregada: %d%%" % roundi(lanterna_bateria))
		"lanterna":
			_equipar_luz("lanterna")
			lanterna_ligada = lanterna_bateria > 0.0
			hs.avisar("Lanterna na mão. Botão LUZ liga/desliga.")
		"tocha":
			if not inv.tem("fosforos"):
				hs.avisar("Precisa de 1 Fósforo para acender a tocha.")
				return false
			inv.remover("fosforos")
			gastar.call()
			_equipar_luz("tocha")
			tocha_tempo = 120.0
			lanterna_ligada = false
			hs.avisar("Tocha acesa! (dura ~6 horas do jogo)")
		"estaca", "bastao", "lanca":
			arma_equipada = id
			golpes = 0
			hs.atualizar_arma(id)
			hs.avisar("%s na mão. Botão ATACAR." % Itens.nome(id))
		"armadilha_corda", "armadilha_estacas":
			var a := Armadilha.criar("corda" if id == "armadilha_corda" else "estacas", Vector2.ZERO)
			_pai_atual().add_child(a)
			a.global_position = (player.global_position + _ultima_dir * 12.0).round()
			gastar.call()
			hs.avisar("Armadilha armada.")
		"lampiao":
			_colocar_lampiao(player.global_position + _ultima_dir * 10.0)
			gastar.call()
		"bancada":
			if jogador_area != "dentro":
				hs.avisar("A bancada precisa ficar DENTRO da cabana.")
				return false
			_colocar_bancada(player.position + _ultima_dir * 14.0)
			gastar.call()
		"chocalho":
			var alvo := player.global_position + _ultima_dir * 110.0
			gastar.call()
			Sons.tocar(self, "clique", -2.0, 0.5)
			ruido(alvo, 220.0)
			registro.append("chocalho")
			hs.avisar("Você joga a lata longe. Clanc! Clanc!")
		"barricada", "reforco":
			var a := _abertura_mais_perto()
			if a == null:
				hs.avisar("Chegue perto de uma porta ou janela (dentro da cabana).")
				return false
			return reforcar(a.id, id)
		_:
			hs.avisar("Isto é material: use em CRIAR.")
			return false
	Sons.tocar(self, "item", -10.0, 1.2)
	_atualizar_hud()
	return true


func _abertura_mais_perto() -> Abertura:
	for a in aberturas.values():
		var p: Vector2 = a.ponto_dentro if jogador_area == "dentro" else a.global_position
		if p.distance_to(player.global_position) < 40.0:
			return a
	return null


func _colocar_lampiao(pos: Vector2) -> void:
	var l := Node2D.new()
	l.name = "Lampiao"
	l.draw.connect(func():
		l.draw_rect(Rect2(-2, -7, 5, 1), Color("3a3a40"))
		l.draw_rect(Rect2(-2, -6, 5, 5), Color(1.0, 0.8, 0.35))
		l.draw_rect(Rect2(-2, -1, 5, 2), Color("3a3a40")))
	_pai_atual().add_child(l)
	l.global_position = pos.round()
	# dura até o amanhecer (ou ~10 horas)
	var horas := fmod(30.0 - ciclo.hora, 24.0) if ciclo.hora > 6.0 else 6.0 - ciclo.hora
	var f := FonteLuz.criar(62.0, Color(1.0, 0.82, 0.45, 0.45), maxf(horas, 2.0) * CicloDia.SEGUNDOS_POR_HORA)
	f.position = Vector2(0, -4)
	f.apagou.connect(l.queue_free)
	l.add_child(f)
	hs.avisar("Lampião colocado: luz fixa até o amanhecer.")


func _colocar_bancada(pos_local: Vector2) -> void:
	pos_local.x = clampf(pos_local.x, 20.0, CabanaInterior.LARGURA - 20.0)
	pos_local.y = clampf(pos_local.y, 60.0, CabanaInterior.ALTURA - 24.0)
	bancada_pos = pos_local.round()
	if _bancada_node:
		_bancada_node.queue_free()
	_bancada_node = Node2D.new()
	_bancada_node.name = "Bancada"
	_bancada_node.position = bancada_pos
	_bancada_node.draw.connect(func():
		var c := _bancada_node
		c.draw_rect(Rect2(-12, -10, 24, 6), Color("6b4b2a"))      # tampo
		c.draw_rect(Rect2(-12, -10, 24, 1), Color("8a6a40"))
		c.draw_rect(Rect2(-11, -4, 2, 5), Color("4a3018"))        # pernas
		c.draw_rect(Rect2(9, -4, 2, 5), Color("4a3018"))
		c.draw_rect(Rect2(-8, -13, 6, 3), Color("8a8a92"))        # serrote
		c.draw_rect(Rect2(3, -12, 2, 2), Color("5c3e22"))         # martelo
		c.draw_rect(Rect2(5, -13, 4, 1), Color("9a9aa2")))
	cab.objetos.add_child(_bancada_node)
	var it := Interagivel.criar("bancada", Vector2(0, -4), 16.0, "CRIAR")
	_bancada_node.add_child(it)
	hs.avisar("Bancada montada! Agora dá para criar coisas melhores.")


# ===============================================================
# CRIAÇÃO
# ===============================================================
func _receitas_liberadas() -> Array:
	var lista: Array = []
	for r in Receitas.LISTA:
		if r["id"] == "bancada" and bancada_pos != Vector2.INF:
			continue
		if Receitas.liberada(r, ciclo.dia, achados):
			lista.append(r)
	return lista


func _perto_bancada() -> bool:
	return jogador_area == "dentro" and bancada_pos != Vector2.INF and player.position.distance_to(bancada_pos) < 44.0


## Fogueira acesa lá fora ou lareira acesa dentro, a até ~50 pixels.
func perto_do_fogo() -> bool:
	if jogador_area == "fora":
		return fogueira_luz != null and fogueira_luz.ativa() and player.global_position.distance_to(fogueira_luz.global_position) < 55.0
	return lareira_luz != null and lareira_luz.ativa() and player.position.distance_to(Vector2(22, 104)) < 60.0


func _criar(r: Dictionary) -> void:
	if _ocupado or not Receitas.pode_criar(r, inv, _perto_bancada(), perto_do_fogo()):
		return
	_ocupado = true
	player.definir_pode_mover(false)
	hs.avisar("Criando %s..." % Itens.nome(r["da"]))
	Sons.tocar(self, "batida", -10.0, 1.4)
	await get_tree().create_timer(r["tempo"]).timeout
	if Receitas.criar(r, inv):
		ruido(player.global_position, r["ruido"])
		hs.avisar("+%d %s" % [r["qtd"], Itens.nome(r["da"])])
		registro.append("criou:" + r["id"])
	_ocupado = false
	player.definir_pode_mover(not _painel)
	hs.atualizar_criacao()


# ===============================================================
# COMBATE
# ===============================================================
func _atacar() -> void:
	if _ocupado or _fim or jogador_escondido or _t_ataque > 0.0:
		return
	_t_ataque = 0.6
	var dano := 6.0
	var alcance := 26.0
	match arma_equipada:
		"estaca": dano = 20.0
		"lanca":
			dano = 28.0
			alcance = 36.0     # a lança alcança mais longe
		"bastao": dano = 35.0
	ruido(player.global_position, 60.0)
	Sons.tocar(self, "passo", -4.0, 0.5)
	# monstro do lago: um golpe faz ele mergulhar
	if monstro_lago and is_instance_valid(monstro_lago) and monstro_lago.visivel() \
			and monstro_lago.global_position.distance_to(player.global_position) < alcance + 14.0:
		monstro_lago.tomar_dano(dano)
		hs.avisar("O monstro do lago mergulhou!")
		registro.append("acertou:agua")
		return
	var m := _monstro_perto(alcance)
	if m == null:
		return
	m.tomar_dano(dano)
	Sons.tocar(self, "batida", -2.0, 1.5)
	registro.append("acertou:" + m.tipo_monstro)
	if m.tipo_monstro in ["observador", "sombra"]:
		hs.avisar("Não adianta bater… só a LUZ funciona!")
	if arma_equipada != "":
		golpes += 1
		var limite: int = {"estaca": 8, "lanca": 15}.get(arma_equipada, 30)
		if golpes >= limite:
			inv.remover(arma_equipada)
			hs.avisar("Sua %s quebrou!" % Itens.nome(arma_equipada))
			arma_equipada = ""
			golpes = 0
			hs.atualizar_arma("")


func _monstro_lago_perto(dist: float) -> bool:
	return monstro_lago != null and is_instance_valid(monstro_lago) and monstro_lago.visivel() \
		and jogador_area == "fora" and monstro_lago.global_position.distance_to(player.global_position) < dist


func _monstro_perto(dist: float) -> Monstro:
	var melhor: Monstro = null
	for m in get_tree().get_nodes_in_group("monstro"):
		if m.area != jogador_area:
			continue
		var d: float = m.global_position.distance_to(player.global_position)
		if d < dist:
			dist = d
			melhor = m
	return melhor


func _observador_visivel() -> bool:
	for m in get_tree().get_nodes_in_group("monstro"):
		if m.tipo_monstro != "observador" or m.modulate.a < 0.3:
			continue
		if jogador_area == "fora" and m.global_position.distance_to(player.global_position) < 230.0:
			return true
		# lá dentro: só te vê pela janela se a cortina estiver ABERTA
		if jogador_area == "dentro" and not cab.cortina_fechada and m.global_position.distance_to(ponto_janela_observador()) < 90.0:
			return true
	return false


func _em_seguranca() -> bool:
	if jogador_area != "dentro":
		return false
	for a in aberturas.values():
		if a.aberta():
			return false
	for m in get_tree().get_nodes_in_group("monstro"):
		if m.area == "dentro":
			return false
	return true


# ===============================================================
# DORMIR
# ===============================================================
## Dormir passa o tempo rápido. De noite: dorme até as 6h. De dia: cochilo de 3 horas.
## Enquanto você dorme, os monstros lá fora continuam atacando a casa (simulado
## hora a hora). Se algo entrar, você ACORDA.
func dormir() -> void:
	if _dormindo:
		return
	for m in get_tree().get_nodes_in_group("monstro"):
		if m.area == "dentro":
			hs.avisar("Não dá para dormir com ISSO aqui dentro!")
			return
	if not ciclo.eh_noite() and status.energia > 60.0:
		hs.avisar("Você não está com sono.")
		return
	_dormindo = true
	_ocupado = true
	player.definir_pode_mover(false)
	ciclo.velocidade = 0.0
	for m in get_tree().get_nodes_in_group("monstro"):
		m.process_mode = Node.PROCESS_MODE_DISABLED
	await _fazer_fade(1.0, 0.6)
	var horas := 3
	if ciclo.eh_noite() or ciclo.fase == "entardecer":
		horas = int(ceil(fmod(30.0 - ciclo.hora, 24.0))) if ciclo.hora > 6.0 else int(ceil(6.0 - ciclo.hora))
	var acordou := ""
	for h in horas:
		ciclo.avancar(CicloDia.SEGUNDOS_POR_HORA)
		status.energia = minf(status.energia + 11.0, 100.0)
		status.fome = maxf(status.fome - 4.0, 0.0)
		status.estresse = maxf(status.estresse - 6.0, 0.0)
		acordou = _simular_hora_dormindo()
		if acordou != "" or _fim:
			break
		await get_tree().create_timer(0.12).timeout
	for m in get_tree().get_nodes_in_group("monstro"):
		m.process_mode = Node.PROCESS_MODE_INHERIT
	ciclo.velocidade = 1.0
	_dormindo = false
	if _fim:
		return
	_atualizar_ambiente()
	await _fazer_fade(0.0, 0.6)
	_ocupado = false
	player.definir_pode_mover(true)
	if acordou != "":
		hs.avisar(acordou)
		tremer_tela(4.0)
		status.estresse = minf(status.estresse + 25.0, 100.0)
	registro.append("dormiu:%d" % horas)
	_atualizar_hud()


## Uma hora de noite com você dormindo: cada monstro lá fora bate na casa.
func _simular_hora_dormindo() -> String:
	if not ciclo.eh_noite():
		return ""
	for m in get_tree().get_nodes_in_group("monstro"):
		if m.area != "fora" or m.tipo_monstro == "observador" or m.indo_embora:
			continue
		var a := escolher_abertura(m)
		if a == null:
			continue
		if a.aberta():
			if m.tipo_monstro != "colosso":
				m.process_mode = Node.PROCESS_MODE_INHERIT
				monstro_entra(m, a)
				m._mudar(Monstro.Estado.ATTACK)
				return "Um barulho te acorda… tem alguma coisa DENTRO da cabana!"
		else:
			a.danificar(45.0 if m.tipo_monstro == "colosso" else 7.0)
			if a.aberta():
				return "CRAAACK! Você acorda com a barricada quebrando!"
	return ""


# ===============================================================
# FIM: MORTE E VITÓRIA
# ===============================================================
func _morrer() -> void:
	if _fim:
		return
	_fim = true
	registro.append("morreu")
	player.definir_pode_mover(false)
	Sons.tocar(self, "grito", -2.0, 0.8)
	# v9: morreu = começa a Parte 2 do zero (não dá para "voltar ao amanhecer"
	# e pular as noites difíceis). O save da Parte 2 é apagado.
	GameData.parte2 = {}
	GameData.salvar_jogo()
	await _tela_final("VOCÊ NÃO SOBREVIVEU", "Você aguentou até a noite %d.\nA Parte 2 vai começar do início." % ciclo.noite_numero(), true)


func _vitoria() -> void:
	if _fim:
		return
	_fim = true
	registro.append("venceu")
	player.definir_pode_mover(false)
	GameData.parte2 = {}
	GameData.salvar_jogo()
	await _tela_final("VOCÊ SOBREVIVEU", "Ao amanhecer do 6º dia, um motor ronca no portão.\nO RESGATE CHEGOU.", false)


func _tela_final(titulo: String, texto: String, tentar: bool) -> void:
	hs.visible = false
	hud.modo_conversa(true)
	var caixa := VBoxContainer.new()
	caixa.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caixa.alignment = BoxContainer.ALIGNMENT_CENTER
	caixa.add_theme_constant_override("separation", 20)
	caixa.modulate.a = 0.0
	_tela.add_child(caixa)
	for d in [[titulo, 60, Color(0.8, 0.12, 0.12)], [texto, 26, Color(0.85, 0.8, 0.7)]]:
		var l := Label.new()
		l.text = d[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", d[1])
		l.add_theme_color_override("font_color", d[2])
		caixa.add_child(l)
	var botoes: Array = []
	if tentar:
		botoes.append(["RECOMEÇAR A PARTE 2", func(): GameData.trocar_cena(GameData.CENA_SOBREVIVENCIA)])
	botoes.append(["MENU PRINCIPAL", func(): GameData.trocar_cena(GameData.CENA_MENU)])
	for b in botoes:
		var bt := Button.new()
		bt.text = b[0]
		bt.custom_minimum_size = Vector2(480, 64)
		bt.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		bt.focus_mode = Control.FOCUS_NONE
		bt.add_theme_font_size_override("font_size", 24)
		bt.pressed.connect(b[1])
		caixa.add_child(bt)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 0.85, 1.5)
	tw.tween_property(caixa, "modulate:a", 1.0, 1.0)
	await tw.finished


# ===============================================================
# PESCA (v9)
# ===============================================================
## Minijogo: a linha vai para a água, espere o peixe morder e PUXE na hora.
## À noite os peixes mordem mais rápido… mas o monstro do lago sente a linha.
func pescar() -> void:
	if pescando:
		return
	pescando = true
	_ocupado = true
	player.definir_pode_mover(false)
	var ponto := _ponto_lago_perto()
	ext.agua.respingo(ponto, 0.7)
	Sons.tocar(self, "clique", -10.0, 0.6)
	var noite := ciclo.eh_noite()
	if noite and monstro_lago and is_instance_valid(monstro_lago):
		monstro_lago.atrair(player.global_position)
	var espera := _rng.randf_range(1.5, 3.5) if noite else _rng.randf_range(2.5, 6.0)
	ext.agua.boia = ponto
	ext.agua.boia_mordeu = false
	var ao_morder := func(): ext.agua.boia_mordeu = true; ext.agua.respingo(ponto, 0.5); Sons.tocar(self, "passo", -8.0, 1.6)
	hs.peixe_mordeu.connect(ao_morder)
	var r: String = await hs.pescar(espera, 1.2)
	hs.peixe_mordeu.disconnect(ao_morder)
	ext.agua.boia = Vector2.INF
	match r:
		"pegou":
			var premio := "peixe"
			var sorte := _rng.randf()
			if sorte < 0.12:
				premio = "metal"      # uma lata velha...
			elif sorte < 0.2:
				premio = "corda"      # um pedaço de linha de pesca
			_ganhar({premio: 1})
			if premio == "peixe":
				hs.avisar("Você pescou um PEIXE! Asse na fogueira para comer melhor.")
			ext.agua.respingo(ponto, 1.2)
			registro.append("pescou:" + premio)
		"escapou":
			hs.avisar("O peixe escapou…")
			registro.append("pesca:escapou")
		_:
			pass
	if r != "cancelou":
		usos_vara += 1
		ruido(player.global_position, 25.0)
		if usos_vara >= 12:
			usos_vara = 0
			inv.remover("vara_pescar")
			hs.avisar("A linha da vara arrebentou! Crie outra.")
	_ocupado = false
	pescando = false
	player.definir_pode_mover(not _painel)


func _ponto_lago_perto() -> Vector2:
	var d := (player.global_position - LAGO_CENTRO) / LAGO_RAIO
	return LAGO_CENTRO + d.normalized() * (LAGO_RAIO - Vector2(24, 24))


## Sinalizador: luz vermelha enorme por 40 s no chão.
func _jogar_sinalizador(pos: Vector2) -> void:
	var n := Node2D.new()
	n.name = "Sinalizador"
	n.draw.connect(func():
		n.draw_rect(Rect2(-1, -4, 3, 4), Color("a01818"))
		n.draw_rect(Rect2(0, -6, 1, 2), Color(1.0, 0.8, 0.5)))
	_pai_atual().add_child(n)
	n.global_position = pos.round()
	var f := FonteLuz.criar(115.0, Color(1.0, 0.25, 0.15, 0.55), 40.0, 0.25)
	f.position = Vector2(0, -4)
	f.apagou.connect(n.queue_free)
	n.add_child(f)
	Sons.tocar(self, "clique", -2.0, 1.6)
	ruido(pos, 60.0)
	registro.append("sinalizador")
	hs.avisar("Sinalizador aceso! Luz forte por 40 segundos.")


# ===============================================================
# TOCOS E TRONCOS DO CHÃO (v9: não são só enfeite!)
# ===============================================================
const MADEIRA_DO_ENFEITE := {"toco": ["madeira", 2], "tronco_caido": ["madeira", 3], "galhos": ["madeira", 1], "pedra_m": ["pedra", 1]}


func _criar_coletaveis_do_chao() -> void:
	for i in ext.enfeites_coletaveis.size():
		if i in tocos_pegos:
			continue
		var e: Array = ext.enfeites_coletaveis[i]
		var d: Array = MADEIRA_DO_ENFEITE[e[0]]
		var c := Coletavel.criar(d[0], d[1], e[1], e[0])
		c.set_meta("toco", i)
		ext.arvores.add_child(c)


## Mostra a setinha "PEGAR" em cima do coletável mais perto.
func _destacar_coletavel() -> void:
	var alvo_atual: Coletavel = null
	if player.alvo and player.alvo.get_parent() is Coletavel:
		alvo_atual = player.alvo.get_parent()
	for c in get_tree().get_nodes_in_group("coletavel"):
		c.destacado = c == alvo_atual


# ===============================================================
# RECURSOS ESPALHADOS (renascem todo dia)
# ===============================================================
const RECURSOS_DIA := {"madeira": 14, "pedra": 8, "ervas": 3, "fruta": 4, "corda": 2, "metal": 3, "tecido": 2, "agua": 1, "fosforos": 1, "bateria": 1, "enlatado": 1}


func _espalhar_recursos() -> void:
	_rng.seed = 1000 + ciclo.dia * 77
	var ja := {}
	for c in get_tree().get_nodes_in_group("coletavel"):
		ja[c.item] = int(ja.get(c.item, 0)) + 1
	for item in RECURSOS_DIA:
		var falta: int = RECURSOS_DIA[item] - int(ja.get(item, 0))
		for k in falta:
			var p := _lugar_livre()
			if p == Vector2.INF:
				continue
			var qtd := 2 if item in ["madeira", "pedra"] and _rng.randf() < 0.4 else 1
			var c := Coletavel.criar(item, qtd, p)
			ext.arvores.add_child(c)
	_rng.randomize()


func _lugar_livre() -> Vector2:
	for t in 30:
		# mais recursos perto da cabana; os raros ficam mais longe (vale o risco)
		var ang := _rng.randf() * TAU
		var dist := _rng.randf_range(80.0, 620.0)
		var p := (Vector2(760, -20) + Vector2(cos(ang), sin(ang) * 0.8) * dist).round()
		if not LIMITES.grow(-30).has_point(p):
			continue
		if ((p - LAGO_CENTRO) / (LAGO_RAIO + Vector2(16, 16))).length() < 1.0:
			continue
		if CABANA_RET.grow(16).has_point(p) or p.distance_to(carro.global_position) < 40.0:
			continue
		var ok := true
		for a in _arvores_pos:
			if (a as Vector2).distance_squared_to(p) < 196.0:
				ok = false
				break
		if ok:
			return p
	return Vector2.INF


# ===============================================================
# HUD
# ===============================================================
func _atualizar_hud() -> void:
	if hs == null:
		return
	hs.atualizar_status(status)
	hs.atualizar_relogio(ciclo.dia, ciclo.texto_hora(), ciclo.fase)
	var txt := "LUZ"
	if luz_equipada == "lanterna":
		txt = "LUZ\n%d%%" % roundi(lanterna_bateria)
	elif luz_equipada == "tocha":
		txt = "TOCHA\n%ds" % ceili(tocha_tempo)
	hs.atualizar_luz(txt)


func _atualizar_objetivo() -> void:
	if ciclo.eh_noite():
		hud.mostrar_objetivo("Sobreviva até o amanhecer.", "Noite %d de %d. Fique na luz e longe do barulho." % [ciclo.noite_numero(), NOITES_PARA_VENCER])
	elif ciclo.fase == "entardecer":
		hud.mostrar_objetivo("Volte para a cabana!", "Reforce porta e janelas antes das 19h.")
	elif bancada_pos == Vector2.INF and inv.contar("madeira") < 4:
		hud.mostrar_objetivo("Junte MADEIRA.", "Galhos, tocos e troncos caídos no chão. Chegue perto e toque em PEGAR.")
	elif bancada_pos == Vector2.INF:
		hud.mostrar_objetivo("Monte uma BANCADA.", "Junte 4 Madeira e 2 Pedras, CRIE a bancada e coloque dentro da cabana.")
	else:
		hud.mostrar_objetivo("Prepare-se para a noite.", "Junte recursos e crie tábuas (madeira + corda) para as janelas.")


# ===============================================================
# SAVE (a cada amanhecer)
# ===============================================================
func _dados() -> Dictionary:
	var ab := {}
	for id in aberturas:
		ab[id] = aberturas[id].hp
	return {
		"dia": ciclo.dia, "hora": ciclo.hora, "status": status.para_dados(), "inv": inv.para_dados(),
		"achados": achados, "aberturas": ab, "carro": carro.para_dados(),
		"bancada": [bancada_pos.x, bancada_pos.y] if bancada_pos != Vector2.INF else [],
		"despensa": despensa_vasculhada, "bateria": lanterna_bateria, "luz": luz_equipada,
		"arma": arma_equipada, "cortina": cab.cortina_fechada, "tocos": tocos_pegos, "vara": usos_vara, "viu_intro": GameData.parte2.get("viu_intro", false),
	}


func _salvar() -> void:
	GameData.parte2 = _dados()
	GameData.etapa = maxi(GameData.etapa, 5)
	GameData.salvar_jogo()


func _carregar() -> void:
	var d: Dictionary = GameData.parte2
	if d.is_empty():
		# Começo da Parte 2: o que você trouxe da Parte 1 + um pouco de comida
		ciclo.dia = 1
		ciclo.hora = 6.5
		inv.adicionar("lanterna")
		inv.adicionar("fosforos", 2)
		inv.adicionar("agua", 1)
		_equipar_luz("lanterna")
		ciclo.avancar(0.0)
		return
	ciclo.dia = int(d.get("dia", 1))
	ciclo.hora = float(d.get("hora", 6.5))
	ciclo.avancar(0.0)
	status.de_dados(d.get("status", {}))
	inv.de_dados(d.get("inv", []))
	achados = d.get("achados", [])
	for id in d.get("aberturas", {}):
		if aberturas.has(id):
			aberturas[id].hp = float(d["aberturas"][id])
	carro.de_dados(d.get("carro", {}))
	var b: Array = d.get("bancada", [])
	if b.size() == 2:
		_colocar_bancada(Vector2(b[0], b[1]))
	despensa_vasculhada = bool(d.get("despensa", false))
	lanterna_bateria = float(d.get("bateria", 100.0))
	var luz: String = d.get("luz", "")
	if luz == "lanterna" and inv.tem("lanterna"):
		_equipar_luz("lanterna")
	arma_equipada = d.get("arma", "") if inv.tem(d.get("arma", "-")) else ""
	cortina(bool(d.get("cortina", false)))
	tocos_pegos = d.get("tocos", [])
	usos_vara = int(d.get("vara", 0))
	hs.atualizar_arma(arma_equipada)
