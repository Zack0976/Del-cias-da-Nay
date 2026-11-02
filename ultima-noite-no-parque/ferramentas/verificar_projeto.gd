@tool
extends EditorScript
## FERRAMENTA: Verificar Projeto
## Como usar: abra este arquivo no editor de scripts e clique em Arquivo > Executar
## (ou Ctrl+Shift+X). O relatório aparece na aba "Saída", lá embaixo.
##
## Ela procura problemas que fazem o jogo dar erro ou fechar:
##  - cenas/scripts que apontam para arquivos que não existem mais
##  - dois arquivos com o mesmo UID (acontece ao copiar arquivos ou descompactar por cima)
##  - imagens enormes (pesam na memória do celular)
##  - arquivos ".import" sobrando, sem a imagem original

const LIMITE_IMAGEM := 2048  ## acima disso a imagem é considerada grande demais para celular

var _problemas := 0


func _run() -> void:
	_problemas = 0
	print("\n========== VERIFICANDO O PROJETO ==========")
	var arquivos: Array[String] = []
	_listar("res://", arquivos)
	var uids := {}
	for arq in arquivos:
		if arq.ends_with(".tscn") or arq.ends_with(".tres"):
			_verificar_referencias(arq)
		if arq.ends_with(".uid"):
			var uid := FileAccess.get_file_as_string(arq).strip_edges()
			_registrar_uid(uids, uid, arq.trim_suffix(".uid"))
		if arq.ends_with(".tscn"):
			var primeira := FileAccess.open(arq, FileAccess.READ).get_line()
			var m := RegEx.create_from_string('uid="(uid://[a-z0-9]+)"').search(primeira)
			if m:
				_registrar_uid(uids, m.get_string(1), arq)
		if arq.ends_with(".import"):
			var original := arq.trim_suffix(".import")
			if not FileAccess.file_exists(original):
				_problema("Arquivo .import sobrando (a imagem foi apagada): " + arq)
		if arq.get_extension() in ["png", "jpg", "jpeg", "webp"]:
			var img := Image.load_from_file(arq)
			if img and (img.get_width() > LIMITE_IMAGEM or img.get_height() > LIMITE_IMAGEM):
				_problema("Imagem muito grande para celular (%dx%d): %s" % [img.get_width(), img.get_height(), arq])
	for uid in uids:
		if uids[uid].size() > 1:
			_problema("UID repetido %s em: %s" % [uid, ", ".join(uids[uid])])
	print("-------------------------------------------")
	if _problemas == 0:
		print("Tudo certo! Nenhum problema encontrado.")
	else:
		print("%d problema(s) encontrado(s). Dica: rode também 'limpar_cache_editor.gd'." % _problemas)
	print("===========================================\n")


func _listar(pasta: String, lista: Array[String]) -> void:
	var d := DirAccess.open(pasta)
	if d == null:
		return
	if FileAccess.file_exists(pasta.path_join(".gdignore")):
		return  # pastas com .gdignore são ignoradas pelo Godot
	for f in d.get_files():
		lista.append(pasta.path_join(f))
	for sub in d.get_directories():
		if sub.begins_with("."):
			continue  # .godot e outras pastas escondidas
		_listar(pasta.path_join(sub), lista)


func _verificar_referencias(arq: String) -> void:
	var texto := FileAccess.get_file_as_string(arq)
	var regex := RegEx.create_from_string('path="(res://[^"]+)"')
	for m in regex.search_all(texto):
		var alvo := m.get_string(1)
		if not FileAccess.file_exists(alvo) and not FileAccess.file_exists(alvo + ".import"):
			_problema("%s aponta para um arquivo que não existe: %s" % [arq, alvo])


func _registrar_uid(uids: Dictionary, uid: String, arq: String) -> void:
	if uid == "":
		return
	if not uids.has(uid):
		uids[uid] = []
	uids[uid].append(arq)


func _problema(texto: String) -> void:
	_problemas += 1
	push_warning("[Verificar] " + texto)
	print("  ⚠ " + texto)
