class_name Inventario
extends RefCounted
## MOCHILA EM GRADE
## Tem um número limitado de espaços (slots). Cada espaço guarda UM tipo de item,
## empilhado até o limite daquele item (ex.: 10 madeiras por espaço).
## Se a mochila estiver cheia, você precisa largar algo ou guardar na cabana.

signal mudou

const ESPACOS := 12  ## 4 colunas x 3 linhas

var slots: Array = []  ## cada slot: {} (vazio) ou {"id": "madeira", "qtd": 3}


func _init() -> void:
	slots.resize(ESPACOS)
	for i in ESPACOS:
		slots[i] = {}


## Tenta guardar "qtd" itens. Devolve quantos SOBRARAM (não couberam).
func adicionar(id: String, qtd := 1) -> int:
	var max_pilha := Itens.pilha(id)
	# 1º: completa pilhas que já existem
	for s in slots:
		if qtd <= 0:
			break
		if not s.is_empty() and s["id"] == id and s["qtd"] < max_pilha:
			var cabe := mini(max_pilha - s["qtd"], qtd)
			s["qtd"] += cabe
			qtd -= cabe
	# 2º: usa espaços vazios
	for i in ESPACOS:
		if qtd <= 0:
			break
		if slots[i].is_empty():
			var cabe := mini(max_pilha, qtd)
			slots[i] = {"id": id, "qtd": cabe}
			qtd -= cabe
	mudou.emit()
	return qtd


func cabe(id: String, qtd := 1) -> bool:
	var max_pilha := Itens.pilha(id)
	var livre := 0
	for s in slots:
		if s.is_empty():
			livre += max_pilha
		elif s["id"] == id:
			livre += max_pilha - s["qtd"]
	return livre >= qtd


func contar(id: String) -> int:
	var total := 0
	for s in slots:
		if not s.is_empty() and s["id"] == id:
			total += s["qtd"]
	return total


func tem(id: String, qtd := 1) -> bool:
	return contar(id) >= qtd


## Remove "qtd" itens (de qualquer pilha). Devolve true se conseguiu.
func remover(id: String, qtd := 1) -> bool:
	if not tem(id, qtd):
		return false
	for i in range(ESPACOS - 1, -1, -1):  # tira das últimas pilhas primeiro
		if qtd <= 0:
			break
		var s: Dictionary = slots[i]
		if not s.is_empty() and s["id"] == id:
			var tira := mini(s["qtd"], qtd)
			s["qtd"] -= tira
			qtd -= tira
			if s["qtd"] <= 0:
				slots[i] = {}
	mudou.emit()
	return true


func remover_do_slot(i: int, qtd := 1) -> void:
	if i < 0 or i >= ESPACOS or slots[i].is_empty():
		return
	slots[i]["qtd"] -= qtd
	if slots[i]["qtd"] <= 0:
		slots[i] = {}
	mudou.emit()


func espacos_livres() -> int:
	var n := 0
	for s in slots:
		if s.is_empty():
			n += 1
	return n


## Junta pilhas iguais e coloca tudo no começo (botão ORGANIZAR).
func organizar() -> void:
	var totais := {}
	var ordem: Array[String] = []
	for s in slots:
		if not s.is_empty():
			if not totais.has(s["id"]):
				totais[s["id"]] = 0
				ordem.append(s["id"])
			totais[s["id"]] += s["qtd"]
	for i in ESPACOS:
		slots[i] = {}
	for id in ordem:
		adicionar(id, totais[id])
	mudou.emit()


# --- salvar / carregar ---
func para_dados() -> Array:
	return slots.duplicate(true)


func de_dados(dados: Array) -> void:
	for i in ESPACOS:
		slots[i] = {}
		if i < dados.size() and dados[i] is Dictionary and not dados[i].is_empty():
			slots[i] = {"id": str(dados[i]["id"]), "qtd": int(dados[i]["qtd"])}
	mudou.emit()
