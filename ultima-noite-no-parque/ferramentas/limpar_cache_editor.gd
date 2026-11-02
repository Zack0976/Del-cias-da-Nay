@tool
extends EditorScript
## FERRAMENTA: Limpar Cache do Editor
## Como usar: abra este arquivo e clique em Arquivo > Executar (Ctrl+Shift+X).
##
## O Godot guarda versões convertidas das imagens em ".godot/imported".
## Quando arquivos são apagados, renomeados ou o projeto é descompactado POR CIMA
## de uma versão antiga, sobram arquivos velhos ali. Isso ocupa espaço e às vezes
## faz o jogo carregar coisa errada.
##
## Esta ferramenta apaga só o que sobrou (arquivos que nenhuma imagem usa mais)
## e manda o Godot reescanear o projeto. Seu jogo e seu save não são tocados.
##
## Se mesmo assim algo estiver estranho: feche o Godot, apague a pasta ".godot"
## inteira do projeto e abra de novo (ele recria tudo sozinho).

const PASTA_IMPORT := "res://.godot/imported/"


func _run() -> void:
	print("\n========== LIMPANDO CACHE ==========")
	var em_uso := {}
	_coletar_em_uso("res://", em_uso)
	var d := DirAccess.open(PASTA_IMPORT)
	if d == null:
		print("Pasta de cache não encontrada (tudo bem, o Godot cria quando precisar).")
		return
	var apagados := 0
	var bytes := 0
	for f in d.get_files():
		# os arquivos do cache se chamam "imagem.png-<código>.ctex" / ".md5"
		var base := f.get_basename()  # tira .ctex/.md5
		if not em_uso.has(base):
			var arq := FileAccess.open(PASTA_IMPORT + f, FileAccess.READ)
			if arq:
				bytes += arq.get_length()
				arq.close()
			d.remove(f)
			apagados += 1
	print("Arquivos velhos apagados: %d (%.2f MB liberados)" % [apagados, bytes / 1048576.0])
	EditorInterface.get_resource_filesystem().scan()
	print("Projeto reescaneado. Pronto!")
	print("====================================\n")


## Lê todos os arquivos ".import" para saber quais arquivos do cache ainda são usados.
func _coletar_em_uso(pasta: String, em_uso: Dictionary) -> void:
	var d := DirAccess.open(pasta)
	if d == null or FileAccess.file_exists(pasta.path_join(".gdignore")):
		return
	for f in d.get_files():
		if f.ends_with(".import"):
			var texto := FileAccess.get_file_as_string(pasta.path_join(f))
			for m in RegEx.create_from_string('res://\\.godot/imported/([^"]+)').search_all(texto):
				em_uso[m.get_string(1).get_basename()] = true
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_coletar_em_uso(pasta.path_join(sub), em_uso)
