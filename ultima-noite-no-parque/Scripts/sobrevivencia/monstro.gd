class_name Monstro
extends CharacterBody2D
## OS 4 MONSTROS — todos usam a mesma máquina de estados:
##
##   IDLE        parado, escutando
##   PATROL      andando pela área
##   INVESTIGATE indo até um barulho que ouviu
##   ATTACK      viu o jogador: persegue / ataca (ou ataca a barricada)
##   SEARCH      perdeu o jogador de vista: procura em volta do último lugar visto
##   RETURN      desiste e volta para a floresta (e ao amanhecer, vai embora)
##
## O que muda entre eles são os números e algumas regras especiais:
##   OBSERVADOR  observa de longe, some com luz, quase nunca ataca (tensão!)
##   RASTEJANTE  rápido, persegue, entra por janela sem barricada, cai em armadilhas
##   COLOSSO     lento, muita vida, DESTRÓI barricadas, exige preparação
##   SOMBRA      só existe no escuro, quase invisível, foge da luz

signal morreu(m: Monstro)

enum Estado { IDLE, PATROL, INVESTIGATE, ATTACK, SEARCH, RETURN }
const NOMES_ESTADO := ["IDLE", "PATROL", "INVESTIGATE", "ATTACK", "SEARCH", "RETURN"]

const PERFIS := {
	"observador": {"vida": 9999.0, "vel": 28.0, "vel_ataque": 34.0, "visao": 230.0, "audicao": 60.0, "dano": 8.0, "alcance": 16.0},
	"rastejante": {"vida": 45.0, "vel": 42.0, "vel_ataque": 98.0, "visao": 150.0, "audicao": 120.0, "dano": 12.0, "alcance": 14.0},
	"colosso":    {"vida": 320.0, "vel": 26.0, "vel_ataque": 36.0, "visao": 170.0, "audicao": 160.0, "dano": 30.0, "alcance": 20.0},
	"sombra":     {"vida": 9999.0, "vel": 40.0, "vel_ataque": 74.0, "visao": 130.0, "audicao": 40.0, "dano": 10.0, "alcance": 13.0},
}

var tipo_monstro := "rastejante"
var estado: Estado = Estado.IDLE
var vida := 45.0
var vel := 40.0
var vel_ataque := 90.0
var visao := 150.0
var audicao := 100.0
var dano := 10.0
var alcance := 14.0

var area := "fora"                 ## "fora" ou "dentro" (da cabana)
var mundo: Node                    ## o controlador da fase (sobrevivencia.gd)
var casa := Vector2.ZERO           ## de onde veio (volta para cá no RETURN)
var alvo := Vector2.ZERO
var ultimo_visto := Vector2.ZERO
var indo_embora := false           ## amanhecer: volta e some

var _t_estado := 0.0
var _t_ataque := 0.0
var _t_sem_ver := 0.0
var _preso := 0.0                  ## atordoado (armadilha / farol)
var _anim := 0.0
var _alfa := 1.0
var _desvio := Vector2.ZERO
var _t_desvio := 0.0
var _ultima_pos := Vector2.ZERO
var _t_parado := 0.0
var _flash := 0.0
var _sumido := 0.0                 ## Observador/Sombra: tempo escondido depois de tomar luz
var abertura_alvo: Abertura = null


static func criar(tipo: String, pos: Vector2, dono: Node) -> Monstro:
	var m := Monstro.new()
	m.tipo_monstro = tipo
	var p: Dictionary = PERFIS[tipo]
	m.vida = p["vida"]
	m.vel = p["vel"]
	m.vel_ataque = p["vel_ataque"]
	m.visao = p["visao"]
	m.audicao = p["audicao"]
	m.dano = p["dano"]
	m.alcance = p["alcance"]
	m.position = pos
	m.casa = pos
	m.mundo = dono
	return m


func _ready() -> void:
	add_to_group("monstro")
	collision_layer = 8   # camada 4: monstros
	collision_mask = 1    # bate só nas paredes/árvores
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var forma := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 10.0 if tipo_monstro == "colosso" else 5.0
	forma.shape = c
	forma.position = Vector2(0, -3)
	add_child(forma)
	_ultima_pos = global_position
	modulate.a = 0.0
	_mudar(Estado.PATROL if tipo_monstro != "observador" else Estado.IDLE)


# ===============================================================
# PERCEPÇÃO
# ===============================================================
func _jogador() -> Node2D:
	return mundo.player if mundo else null


func ve_jogador() -> bool:
	var j := _jogador()
	if j == null or mundo.jogador_area != area:
		return false
	if mundo.jogador_escondido and tipo_monstro in ["rastejante", "sombra", "observador"]:
		return false
	var d := global_position.distance_to(j.global_position)
	var alcance_visao := visao
	if Iluminacao.esta_iluminado(j.global_position):
		alcance_visao *= 1.35       # jogador iluminado é visto de mais longe...
	if tipo_monstro == "sombra" and Iluminacao.esta_iluminado(j.global_position):
		return false                # ...mas a Sombra não enxerga dentro da luz
	return d <= alcance_visao


## O sistema de ruído chama isto.
func ouviu(pos: Vector2, _raio: float) -> void:
	if indo_embora or tipo_monstro == "observador":
		return
	if estado in [Estado.IDLE, Estado.PATROL, Estado.SEARCH, Estado.RETURN]:
		alvo = pos
		_mudar(Estado.INVESTIGATE)


# ===============================================================
# LOOP
# ===============================================================
func _physics_process(delta: float) -> void:
	_anim += delta
	_t_estado += delta
	_t_ataque = maxf(_t_ataque - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	_atualizar_visibilidade(delta)
	if _preso > 0.0:
		_preso -= delta
		velocity = Vector2.ZERO
		queue_redraw()
		return
	if _sumido > 0.0:
		_sumido -= delta
		velocity = Vector2.ZERO
		if _sumido <= 0.0:
			_reaparecer()
		queue_redraw()
		return
	_regras_especiais(delta)
	match estado:
		Estado.IDLE: _idle()
		Estado.PATROL: _patrol()
		Estado.INVESTIGATE: _investigate()
		Estado.ATTACK: _attack(delta)
		Estado.SEARCH: _search()
		Estado.RETURN: _return()
	_mover(delta)
	_checar_armadilhas()
	queue_redraw()


func _mudar(novo: Estado) -> void:
	if estado == novo and _t_estado > 0.0:
		return
	estado = novo
	_t_estado = 0.0
	if novo == Estado.PATROL:
		alvo = _ponto_patrulha()
	elif novo == Estado.SEARCH:
		alvo = ultimo_visto + Vector2(randf_range(-50, 50), randf_range(-50, 50))


func nome_estado() -> String:
	return NOMES_ESTADO[estado]


# ---------------------------------------------------------------
# ESTADOS
# ---------------------------------------------------------------
func _idle() -> void:
	velocity = Vector2.ZERO
	if tipo_monstro == "observador":
		_observar()
		return
	if ve_jogador():
		_viu()
	elif _t_estado > 2.0:
		_mudar(Estado.PATROL)


func _patrol() -> void:
	if tipo_monstro == "observador":
		_observar()
		return
	if ve_jogador():
		_viu()
		return
	if _ir_para(alvo, vel):
		_mudar(Estado.IDLE)


func _investigate() -> void:
	if ve_jogador():
		_viu()
		return
	if _ir_para(alvo, vel * 1.4) or _t_estado > 12.0:
		ultimo_visto = alvo
		_mudar(Estado.SEARCH)


func _attack(delta: float) -> void:
	var j := _jogador()
	if j == null:
		_mudar(Estado.RETURN)
		return
	# Jogador DENTRO da cabana e eu FORA: vou atrás de uma porta/janela
	if mundo.jogador_area == "dentro" and area == "fora":
		_atacar_casa(delta)
		return
	# Jogador saiu e eu estou DENTRO: saio pela porta
	if mundo.jogador_area == "fora" and area == "dentro":
		if _ir_para(mundo.saida_interior(), vel_ataque):
			mundo.monstro_sai(self)
		return
	if ve_jogador():
		ultimo_visto = j.global_position
		_t_sem_ver = 0.0
	else:
		_t_sem_ver += delta
		if _t_sem_ver > 2.5:
			_mudar(Estado.SEARCH)
			return
	var d := global_position.distance_to(j.global_position)
	if d <= alcance:
		velocity = Vector2.ZERO
		if _t_ataque <= 0.0:
			_t_ataque = 1.2 if tipo_monstro != "colosso" else 1.8
			mundo.ferir_jogador(dano, self)
	else:
		_ir_para(ultimo_visto, vel_ataque)


func _search() -> void:
	if ve_jogador():
		_viu()
		return
	if _ir_para(alvo, vel) :
		alvo = ultimo_visto + Vector2(randf_range(-60, 60), randf_range(-60, 60))
	if _t_estado > 7.0:
		_mudar(Estado.RETURN)


func _return() -> void:
	if not indo_embora and ve_jogador():
		_viu()
		return
	var destino := casa
	if area == "dentro":
		destino = mundo.saida_interior()
	if _ir_para(destino, vel * (1.3 if indo_embora else 1.0)):
		if area == "dentro":
			mundo.monstro_sai(self)
			return
		if indo_embora:
			_sumir_de_vez()
		else:
			_mudar(Estado.IDLE)


func _viu() -> void:
	ultimo_visto = _jogador().global_position
	_t_sem_ver = 0.0
	_mudar(Estado.ATTACK)
	if tipo_monstro == "rastejante":
		Sons.tocar(self, "galho", -6.0, 1.6)


# ---------------------------------------------------------------
# ATACAR A CASA
# ---------------------------------------------------------------
func _atacar_casa(delta: float) -> void:
	if abertura_alvo == null or not is_instance_valid(abertura_alvo) or _t_estado > 25.0:
		abertura_alvo = mundo.escolher_abertura(self)
		_t_estado = 0.0
	if abertura_alvo == null:
		_mudar(Estado.SEARCH)
		return
	if not _ir_para(abertura_alvo.global_position, vel_ataque * 0.8, 6.0):
		return
	velocity = Vector2.ZERO
	if abertura_alvo.aberta():
		if tipo_monstro in ["rastejante", "sombra", "colosso"]:
			mundo.monstro_entra(self, abertura_alvo)
		return
	# barricada no caminho
	match tipo_monstro:
		"colosso":
			abertura_alvo.danificar(30.0 * delta)          # destrói
			if _t_ataque <= 0.0:
				_t_ataque = 1.0
				Sons.tocar(self, "batida", 2.0, 0.7)
				mundo.tremer_tela(2.0)
				Ruido.emitir(get_tree(), global_position, 120.0)
		"rastejante":
			abertura_alvo.danificar(2.0 * delta)           # arranha (fraco)
			if _t_estado > 8.0:
				abertura_alvo = null                       # tenta outra janela
		_:
			_mudar(Estado.SEARCH)


# ---------------------------------------------------------------
# REGRAS ESPECIAIS
# ---------------------------------------------------------------
func _regras_especiais(_delta: float) -> void:
	match tipo_monstro:
		"observador", "sombra":
			if Iluminacao.esta_iluminado(global_position, 4.0):
				_tomar_luz()
		"rastejante":
			# os faróis ofuscam
			for c in get_tree().get_nodes_in_group("carro"):
				if c.farois_ligados() and Geometry2D.is_point_in_polygon(global_position, c.poligono_global()):
					_preso = 1.5
					_flash = 0.3
					velocity = Vector2.ZERO
					alvo = global_position + (global_position - c.global_position).normalized() * 80.0
					_mudar(Estado.SEARCH)
					return


## Observador: fica de longe olhando. Raramente ataca (só no pânico e no escuro).
func _observar() -> void:
	var j := _jogador()
	if j == null or mundo.jogador_area != "fora":
		# jogador dentro: fica olhando pela janela da cabana
		var jan: Vector2 = mundo.ponto_janela_observador()
		_ir_para(jan, vel)
		return
	var d := global_position.distance_to(j.global_position)
	var desejado := 170.0
	if d > desejado + 30.0:
		_ir_para(j.global_position, vel)
	elif d < desejado - 40.0:
		_ir_para(global_position + (global_position - j.global_position).normalized() * 50.0, vel)
	else:
		# anda devagar de lado, em volta do jogador
		var lado := (global_position - j.global_position).orthogonal().normalized()
		velocity = lado * vel * 0.4
	if mundo.status.estresse > 85.0 and d < 70.0 and not Iluminacao.esta_iluminado(j.global_position) and _t_ataque <= 0.0:
		_t_ataque = 20.0
		_mudar(Estado.ATTACK)
		mundo.ferir_jogador(dano, self)
		_tomar_luz()  # ataca e some


func _tomar_luz() -> void:
	if _sumido > 0.0:
		return
	_sumido = 12.0 if tipo_monstro == "observador" else 8.0
	_alfa = 0.0
	modulate.a = 0.0
	if estado == Estado.ATTACK:
		_mudar(Estado.RETURN)


func _reaparecer() -> void:
	# volta longe do jogador, num lugar escuro
	var j := _jogador()
	if j:
		var ang := randf() * TAU
		global_position = mundo.ponto_valido(j.global_position + Vector2(cos(ang), sin(ang)) * randf_range(200, 260))
	area = "fora"
	_mudar(Estado.IDLE if tipo_monstro == "observador" else Estado.PATROL)


func _atualizar_visibilidade(delta: float) -> void:
	var alvo_alfa := 1.0
	if _sumido > 0.0:
		alvo_alfa = 0.0
	elif tipo_monstro == "sombra":
		var j := _jogador()
		var perto := j != null and global_position.distance_to(j.global_position) < 45.0
		alvo_alfa = 0.55 if perto else 0.14   # difícil de enxergar
	elif tipo_monstro == "observador":
		alvo_alfa = 0.85
	_alfa = move_toward(_alfa, alvo_alfa, delta * 1.5)
	modulate.a = _alfa


# ---------------------------------------------------------------
# MOVIMENTO
# ---------------------------------------------------------------
## Anda até "destino". Devolve true quando chegou.
func _ir_para(destino: Vector2, velocidade: float, chegada := 6.0) -> bool:
	var dif := destino - global_position
	if dif.length() <= chegada:
		velocity = Vector2.ZERO
		return true
	var dir := dif.normalized()
	if _t_desvio > 0.0:
		dir = (dir + _desvio * 1.5).normalized()
	velocity = dir * velocidade
	return false


func _mover(delta: float) -> void:
	move_and_slide()
	# preso numa árvore? dá um passo para o lado
	if velocity.length() > 5.0:
		if global_position.distance_to(_ultima_pos) < velocity.length() * delta * 0.3:
			_t_parado += delta
		else:
			_t_parado = 0.0
		if _t_parado > 0.5:
			_t_parado = 0.0
			_desvio = velocity.normalized().orthogonal() * (1.0 if randf() > 0.5 else -1.0)
			_t_desvio = 0.8
	_t_desvio = maxf(_t_desvio - delta, 0.0)
	_ultima_pos = global_position


func _ponto_patrulha() -> Vector2:
	var base := casa
	if mundo and mundo.player and randf() < 0.5:
		base = mundo.player.global_position  # às vezes patrulha perto do jogador
	return mundo.ponto_valido(base + Vector2(randf_range(-160, 160), randf_range(-120, 120))) if mundo else base


func _checar_armadilhas() -> void:
	if tipo_monstro in ["observador", "sombra"]:
		return  # não tocam o chão de verdade...
	for a in get_tree().get_nodes_in_group("armadilha"):
		if a.armada and a.global_position.distance_to(global_position) < Armadilha.RAIO:
			var r: Array = a.disparar(self)
			_preso = r[1]
			if r[0] > 0.0:
				tomar_dano(r[0])
			Sons.tocar(self, "galho", 0.0, 0.8)


# ---------------------------------------------------------------
# DANO
# ---------------------------------------------------------------
func tomar_dano(valor: float) -> void:
	if tipo_monstro in ["observador", "sombra"]:
		return  # armas não funcionam: só a LUZ
	vida -= valor
	_flash = 0.15
	if estado != Estado.ATTACK and _jogador():
		_viu()
	if vida <= 0.0:
		_sumir_de_vez()


func _sumir_de_vez() -> void:
	set_physics_process(false)
	remove_from_group("monstro")
	morreu.emit(self)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.8)
	tw.tween_callback(queue_free)


## O controlador chama isto quando o monstro "sabe" que o jogador está na cabana
## (ouviu barulho lá dentro, viu luz na janela...). Vai atacar portas e janelas.
func atacar_casa() -> void:
	if indo_embora or tipo_monstro == "observador" or area == "dentro":
		return
	abertura_alvo = null
	_mudar(Estado.ATTACK)


func ir_embora() -> void:
	indo_embora = true
	_mudar(Estado.RETURN)


# ===============================================================
# DESENHO — sprites esculpidos e iluminados por pixel (monstro_arte.gd)
# ===============================================================
var _olhando_esq := false


func _draw() -> void:
	var quadros: Array = MonstroArte.quadros(tipo_monstro)
	var vel_anim := 10.0 if estado == Estado.ATTACK else 5.0
	if velocity.length() < 3.0 and tipo_monstro != "sombra":
		vel_anim = 1.5   # parado: respira devagar
	var tex: Texture2D = quadros[int(_anim * vel_anim) % quadros.size()]
	if absf(velocity.x) > 2.0:
		_olhando_esq = velocity.x < 0.0
	var base := MonstroArte.base(tipo_monstro)
	# sombra no chão
	var largura := tex.get_width() * (0.35 if tipo_monstro != "rastejante" else 0.45)
	PixelArte.elipse(self, Vector2(0, -1), Vector2(largura, 3), Color(0, 0, 0, 0.35))
	var cor := Color.WHITE
	if _flash > 0.0:
		cor = Color(1.0, 0.45, 0.45)   # piscou vermelho: levou dano / ofuscado
	var destino := Rect2(-base, tex.get_size())
	if _olhando_esq:
		destino = Rect2(Vector2(base.x, -base.y), Vector2(-tex.get_width(), tex.get_height()))
	draw_texture_rect(tex, destino, false, cor)
	var topo := -base.y - 4
	if _preso > 0.0:  # estrelinhas de atordoado
		var k := int(_anim * 6.0) % 2
		draw_rect(Rect2(-4 + k * 2, topo, 1, 1), Color(1, 1, 0.6))
		draw_rect(Rect2(3 - k * 2, topo - 2, 1, 1), Color(1, 1, 0.6))
		draw_rect(Rect2(0, topo - 1, 1, 1), Color(1, 1, 0.6))
	if tipo_monstro == "colosso":
		var max_v: float = PERFIS["colosso"]["vida"]
		if vida < max_v:
			draw_rect(Rect2(-14, topo - 4, 28, 3), Color(0.15, 0.0, 0.0))
			draw_rect(Rect2(-14, topo - 4, roundi(28.0 * vida / max_v), 3), Color(0.85, 0.15, 0.1))
