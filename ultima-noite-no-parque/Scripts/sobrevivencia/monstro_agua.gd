class_name MonstroAgua
extends Node2D
## O MONSTRO DO LAGO (v9)
## Uma serpente que mora no fundo do lago. Ela NUNCA sai da água.
##
## Estados:
##   SUBMERSO   → nada escondida. Só aparece uma sombra escura e ondinhas.
##                Se você chega perto da beira, ela nada até você.
##   SUBINDO    → sobe da água (a cabeça vai aparecendo)
##   ATACANDO   → morde quem está perto da beira (muito dano!)
##   MERGULHANDO→ volta para o fundo
##
## Defesa: fique longe da beira à noite. LUZ forte (tocha, sinalizador,
## faróis) ou um golpe fazem ela mergulhar. Pescar à noite atrai ela!

enum E { SUBMERSO, SUBINDO, ATACANDO, MERGULHANDO }

const DANO := 18.0
const ALCANCE := 48.0       ## ela estica o pescoço para fora da água
const VEL := 38.0

var mundo: Node
var agua: AguaLago
var estado := E.SUBMERSO
var subida := 0.0          ## 0 = no fundo, 1 = totalmente para fora
var _t := 0.0
var _t_estado := 0.0
var _t_ataque := 0.0
var _cansada := 0.0         ## depois de levar luz/golpe fica um tempo sem subir
var _alvo := Vector2.ZERO
var _olhando_esq := false
var indo_embora := false
var tipo_monstro := "agua"
var area := "fora"


static func criar(dono: Node, lago: AguaLago) -> MonstroAgua:
	var m := MonstroAgua.new()
	m.mundo = dono
	m.agua = lago
	m.position = AguaLago.CENTRO
	return m


func _ready() -> void:
	add_to_group("monstro_agua")
	z_index = 1
	_alvo = global_position


func _process(delta: float) -> void:
	_t += delta
	_t_estado += delta
	_t_ataque = maxf(_t_ataque - delta, 0.0)
	_cansada = maxf(_cansada - delta, 0.0)
	var j: Node2D = mundo.player if mundo else null
	var perto_da_beira: bool = j != null and mundo.jogador_area == "fora" and not mundo.jogador_escondido \
		and agua.dentro(j.global_position, -60.0)
	match estado:
		E.SUBMERSO:
			subida = move_toward(subida, 0.0, delta * 2.0)
			if perto_da_beira and _cansada <= 0.0 and not indo_embora:
				_nadar_para(_ponto_na_agua(j.global_position), VEL * 1.4, delta)
				if global_position.distance_to(j.global_position) < ALCANCE + 14.0:
					_mudar(E.SUBINDO)
			else:
				# passeia devagar pelo lago
				if global_position.distance_to(_alvo) < 6.0 or _t_estado > 8.0:
					_alvo = AguaLago.CENTRO + Vector2(randf_range(-0.7, 0.7) * AguaLago.RAIO.x, randf_range(-0.7, 0.7) * AguaLago.RAIO.y)
					_t_estado = 0.0
				_nadar_para(_alvo, VEL * 0.5, delta)
			if indo_embora and subida <= 0.0:
				queue_free()
		E.SUBINDO:
			subida = move_toward(subida, 1.0, delta * 2.2)
			if subida >= 1.0:
				_mudar(E.ATACANDO)
				agua.respingo(global_position, 1.6)
				Sons.tocar(self, "rangido", -4.0, 0.5)
		E.ATACANDO:
			if j and perto_da_beira:
				_olhando_esq = j.global_position.x < global_position.x
				_nadar_para(_ponto_na_agua(j.global_position), VEL * 0.6, delta)
				if global_position.distance_to(j.global_position) <= ALCANCE and _t_ataque <= 0.0:
					_t_ataque = 1.6
					mundo.ferir_jogador(DANO, self)
					agua.respingo(j.global_position, 1.2)
			if _t_estado > 5.0 or not perto_da_beira:
				_mudar(E.MERGULHANDO)
		E.MERGULHANDO:
			subida = move_toward(subida, 0.0, delta * 1.8)
			if subida <= 0.0:
				_mudar(E.SUBMERSO)
	# LUZ forte faz mergulhar (mas ela não morre)
	if estado in [E.SUBINDO, E.ATACANDO] and Iluminacao.esta_iluminado(global_position, -20.0):
		espantar(6.0)
	if int(_t * 10.0) % 3 == 0:
		queue_redraw()


func _mudar(novo: int) -> void:
	estado = novo
	_t_estado = 0.0


func nome_estado() -> String:
	return ["SUBMERSO", "SUBINDO", "ATACANDO", "MERGULHANDO"][estado]


func visivel() -> bool:
	return subida > 0.3


## Golpe ou luz: mergulha e fica um tempo longe.
func espantar(segundos: float) -> void:
	if estado == E.SUBMERSO or estado == E.MERGULHANDO:
		return
	_cansada = segundos
	_mudar(E.MERGULHANDO)
	agua.respingo(global_position, 1.4)


func tomar_dano(_valor: float) -> void:
	espantar(10.0)


func ir_embora() -> void:
	indo_embora = true
	if estado != E.SUBMERSO:
		_mudar(E.MERGULHANDO)


## Pescar à noite: ela sente a linha balançando.
func atrair(pos: Vector2) -> void:
	if _cansada <= 0.0 and estado == E.SUBMERSO:
		_alvo = _ponto_na_agua(pos)


func _ponto_na_agua(p: Vector2) -> Vector2:
	var d := (p - AguaLago.CENTRO) / (AguaLago.RAIO - Vector2(14, 14))
	if d.length() > 1.0:
		d = d.normalized()
	return AguaLago.CENTRO + d * (AguaLago.RAIO - Vector2(14, 14))


func _nadar_para(destino: Vector2, velocidade: float, delta: float) -> void:
	var dif := destino - global_position
	if dif.length() > 1.0:
		global_position += dif.normalized() * minf(velocidade * delta, dif.length())
		if absf(dif.x) > 1.0:
			_olhando_esq = dif.x < 0.0
		if randf() < delta * 1.5:
			agua.respingo(global_position, 0.5)


func _draw() -> void:
	# sombra escura embaixo d'água (sempre um pouquinho visível — fique atento!)
	var a := 0.28 * (1.0 - subida * 0.5)
	PixelArte.elipse(self, Vector2(0, 0), Vector2(14, 5), Color(0.0, 0.03, 0.03, a))
	PixelArte.elipse(self, Vector2(-14 if not _olhando_esq else 14, 1), Vector2(8, 3), Color(0.0, 0.03, 0.03, a * 0.8))
	if subida <= 0.02:
		return
	var quadros: Array = MonstroArte.quadros("agua")
	var tex: Texture2D = quadros[int(_t * (8.0 if estado == E.ATACANDO else 4.0)) % quadros.size()]
	var tam := tex.get_size()
	# só a parte que já saiu da água aparece (recorte de baixo para cima)
	var altura_visivel := roundi(tam.y * subida)
	var regiao := Rect2(0, 0, tam.x, altura_visivel)
	var destino := Rect2(-tam.x / 2.0, -altura_visivel + 2, tam.x, altura_visivel)
	if _olhando_esq:
		destino = Rect2(tam.x / 2.0, -altura_visivel + 2, -tam.x, altura_visivel)
	draw_texture_rect_region(tex, destino, regiao)
	# anel de água em volta do pescoço
	for k in 14:
		var ang := TAU * k / 14.0 + _t * 2.0
		draw_rect(Rect2(roundi(cos(ang) * 9.0), roundi(sin(ang) * 3.0) + 1, 2, 1), Color(0.75, 0.88, 0.95, 0.55))
