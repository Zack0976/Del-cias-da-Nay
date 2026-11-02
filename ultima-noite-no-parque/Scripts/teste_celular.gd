extends Control
## TESTE DO CELULAR — descobre qual parte do jogo faz o Godot fechar no SEU aparelho.
##
## Como usar:
##   1. Abra a cena Scenes/teste_celular.tscn
##   2. Aperte "Executar cena atual" (o botão de claquete com play, ou F6)
##   3. Se o Godot fechar, abra o projeto de novo e rode o teste outra vez:
##      a tela vai mostrar EM QUAL TESTE ele fechou. Manda um print disso!
##
## Cada teste liga UMA coisa diferente por alguns segundos e anota no arquivo
## user://teste_celular.log ANTES de começar. Se o app morrer, a anotação fica lá.

const ARQUIVO := "user://teste_celular.log"
const TEMPO_POR_TESTE := 3.0

var _texto: Label
var _area: Node2D
var _testes := []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fundo := ColorRect.new()
	fundo.color = Color(0.05, 0.05, 0.07)
	fundo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fundo)
	_area = Node2D.new()
	_area.position = Vector2(900, 360)
	add_child(_area)
	_texto = Label.new()
	_texto.position = Vector2(40, 30)
	_texto.add_theme_font_size_override("font_size", 24)
	add_child(_texto)

	_testes = [
		["Desenho com formas", _t_desenho],
		["Texto com contorno grande", _t_texto],
		["Partículas", _t_particulas],
		["Arquivo de som pronto (Sons/gerados)", _t_som_pronto],
		["Som gerado por código", _t_som_codigo],
		["Canais de áudio (Música/Efeitos)", _t_canais],
		["Luz 2D + escurecer a tela", _t_luz],
		["Tela pixelada (SubViewport)", _t_subviewport],
		["Sprites do jogo", _t_sprites],
		["Cabana desenhada", _t_cabana],
		["Parque com 330 árvores", _t_parque],
	]
	_rodar()


func _rodar() -> void:
	var anterior := ""
	if FileAccess.file_exists(ARQUIVO):
		anterior = FileAccess.get_file_as_string(ARQUIVO).strip_edges()
	var cabecalho := "TESTE DO CELULAR\n"
	if anterior != "" and not anterior.ends_with("FIM"):
		var linhas := anterior.split("\n")
		cabecalho += "⚠ Da última vez o Godot FECHOU durante: %s\n" % linhas[-1]
	elif anterior.ends_with("FIM"):
		cabecalho += "Da última vez todos os testes passaram.\n"
	var f := FileAccess.open(ARQUIVO, FileAccess.WRITE)
	f.close()
	for i in _testes.size():
		var nome: String = _testes[i][0]
		_anotar("teste %d: %s" % [i + 1, nome])
		_texto.text = cabecalho + "\nRodando teste %d de %d:\n%s" % [i + 1, _testes.size(), nome]
		for c in _area.get_children():
			c.queue_free()
		await get_tree().process_frame
		_testes[i][1].call()
		await get_tree().create_timer(TEMPO_POR_TESTE).timeout
	for c in _area.get_children():
		c.queue_free()
	_anotar("FIM")
	_texto.text = cabecalho + "\n✔ TODOS OS TESTES PASSARAM!\nNenhuma dessas partes derruba o Godot neste celular."


func _anotar(linha: String) -> void:
	print("[TESTE] ", linha)
	var f := FileAccess.open(ARQUIVO, FileAccess.READ_WRITE)
	if f:
		f.seek_end()
		f.store_line(linha)
		f.flush()  # grava NA HORA (se o app morrer logo depois, a linha já está salva)
		f.close()


# ---------------- os testes ----------------
func _t_desenho() -> void:
	var n := Node2D.new()
	n.draw.connect(func():
		for i in 200:
			n.draw_circle(Vector2(randf_range(-200, 200), randf_range(-200, 200)), randf_range(4, 30), Color(randf(), randf(), randf())))
	_area.add_child(n)


func _t_texto() -> void:
	var l := Label.new()
	l.text = "ÚLTIMA NOITE"
	l.position = Vector2(-300, -60)
	l.add_theme_font_size_override("font_size", 72)
	l.add_theme_color_override("font_outline_color", Color(0.7, 0.1, 0.1))
	l.add_theme_constant_override("outline_size", 16)
	_area.add_child(l)


func _t_particulas() -> void:
	var p := CPUParticles2D.new()
	p.amount = 40
	p.lifetime = 3.0
	p.preprocess = 3.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(200, 150)
	p.gravity = Vector2(0, -4)
	_area.add_child(p)


func _t_som_pronto() -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://Sons/gerados/vento.res")
	_area.add_child(p)
	p.play()


func _t_som_codigo() -> void:
	var dados := PackedByteArray()
	dados.resize(22050 * 2)
	for i in 22050:
		dados.encode_s16(i * 2, int(sin(TAU * 440.0 * i / 22050.0) * 8000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.data = dados
	var p := AudioStreamPlayer.new()
	p.stream = wav
	_area.add_child(p)
	p.play()


func _t_canais() -> void:
	var p := AudioStreamPlayer.new()
	p.stream = load("res://Sons/gerados/drone.res")
	p.bus = "Musica"
	_area.add_child(p)
	p.play()
	var tw := p.create_tween()
	tw.tween_property(p, "volume_db", -30.0, 2.5)


func _t_luz() -> void:
	var cm := CanvasModulate.new()
	cm.color = Color(0.2, 0.2, 0.3)
	_area.add_child(cm)
	var luz := PointLight2D.new()
	luz.texture = Player.criar_textura_luz()
	luz.texture_scale = 2.0
	_area.add_child(luz)
	var r := ColorRect.new()
	r.size = Vector2(300, 300)
	r.position = Vector2(-150, -150)
	r.color = Color(0.6, 0.4, 0.2)
	_area.add_child(r)


func _t_subviewport() -> void:
	var c := SubViewportContainer.new()
	c.stretch = true
	c.stretch_shrink = 4
	c.size = Vector2(400, 300)
	c.position = Vector2(-200, -150)
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var v := SubViewport.new()
	v.snap_2d_transforms_to_pixel = true
	c.add_child(v)
	var n := Node2D.new()
	n.draw.connect(func(): n.draw_circle(Vector2(50, 37), 30, Color.ORANGE))
	v.add_child(n)
	_area.add_child(c)


func _t_sprites() -> void:
	for i in 4:
		var suporte := Node2D.new()
		suporte.position = Vector2(-150 + i * 100, 80)
		suporte.scale = Vector2(4, 4)
		var s := SpritePersonagem.new()
		s.personagem = ["protagonista", "lucas", "marina", "jogadora"][i]
		suporte.add_child(s)
		_area.add_child(suporte)
		s.play("andar_baixo")


func _t_cabana() -> void:
	var c := CabanaInterior.new()
	c.position = Vector2(-144, -96)
	_area.add_child(c)


func _t_parque() -> void:
	var p := ParqueExterior.new()
	p.scale = Vector2(0.2, 0.2)
	_area.add_child(p)
