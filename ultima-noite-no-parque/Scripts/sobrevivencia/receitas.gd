class_name Receitas
extends RefCounted
## RECEITAS DE CRIAÇÃO (crafting)
##
## "precisa": ingredientes | "da": o que você ganha
## "bancada": true = só dá para fazer perto da bancada (dentro da cabana)
## "libera": quando a receita aparece:
##     "inicio"           = desde o começo
##     "dia:N"            = a partir do dia N
##     "achou:item"       = depois de pegar aquele item pela primeira vez
## "ruido": barulho ao criar (bancada = barulhento! pode atrair monstros à noite)
## "tempo": segundos trabalhando
## "fogo": true = precisa estar perto de FOGO aceso (fogueira lá fora ou lareira)

const LISTA := [
	{"id": "tocha", "da": "tocha", "qtd": 1, "precisa": {"madeira": 1, "tecido": 1}, "bancada": false, "libera": "inicio", "ruido": 40.0, "tempo": 1.5},
	{"id": "bancada", "da": "bancada", "qtd": 1, "precisa": {"madeira": 4, "pedra": 2}, "bancada": false, "libera": "inicio", "ruido": 120.0, "tempo": 3.0},
	{"id": "estaca", "da": "estaca", "qtd": 1, "precisa": {"madeira": 2, "pedra": 1}, "bancada": false, "libera": "inicio", "ruido": 60.0, "tempo": 2.0},
	{"id": "barricada", "da": "barricada", "qtd": 1, "precisa": {"madeira": 3, "corda": 1}, "bancada": true, "libera": "inicio", "ruido": 150.0, "tempo": 2.5},
	{"id": "kit", "da": "kit", "qtd": 1, "precisa": {"ervas": 2, "tecido": 1}, "bancada": true, "libera": "achou:ervas", "ruido": 20.0, "tempo": 2.0},
	{"id": "armadilha_corda", "da": "armadilha_corda", "qtd": 1, "precisa": {"corda": 2, "madeira": 2}, "bancada": true, "libera": "inicio", "ruido": 60.0, "tempo": 2.0},
	{"id": "chocalho", "da": "chocalho", "qtd": 2, "precisa": {"metal": 1, "pedra": 2}, "bancada": true, "libera": "achou:metal", "ruido": 80.0, "tempo": 1.5},
	{"id": "lampiao", "da": "lampiao", "qtd": 1, "precisa": {"metal": 1, "tecido": 1, "fosforos": 1}, "bancada": true, "libera": "dia:2", "ruido": 50.0, "tempo": 2.5},
	{"id": "reforco", "da": "reforco", "qtd": 1, "precisa": {"metal": 2, "corda": 1, "madeira": 1}, "bancada": true, "libera": "dia:2", "ruido": 200.0, "tempo": 3.5},
	{"id": "armadilha_estacas", "da": "armadilha_estacas", "qtd": 1, "precisa": {"madeira": 3, "metal": 1}, "bancada": true, "libera": "dia:3", "ruido": 120.0, "tempo": 3.0},
	{"id": "bastao", "da": "bastao", "qtd": 1, "precisa": {"madeira": 2, "metal": 2, "corda": 1}, "bancada": true, "libera": "dia:3", "ruido": 150.0, "tempo": 3.0},
	# --- v9: pesca, comida no fogo e mais coisas ---
	{"id": "vara_pescar", "da": "vara_pescar", "qtd": 1, "precisa": {"madeira": 2, "corda": 1}, "bancada": false, "libera": "inicio", "ruido": 20.0, "tempo": 2.0},
	{"id": "corda", "da": "corda", "qtd": 1, "precisa": {"tecido": 2}, "bancada": false, "libera": "inicio", "ruido": 10.0, "tempo": 1.5},
	{"id": "peixe_assado", "da": "peixe_assado", "qtd": 1, "precisa": {"peixe": 1}, "bancada": false, "fogo": true, "libera": "achou:peixe", "ruido": 15.0, "tempo": 2.0},
	{"id": "cha", "da": "cha", "qtd": 1, "precisa": {"ervas": 1, "agua": 1}, "bancada": false, "fogo": true, "libera": "achou:ervas", "ruido": 10.0, "tempo": 1.5},
	{"id": "ensopado", "da": "ensopado", "qtd": 1, "precisa": {"peixe": 1, "ervas": 1, "agua": 1}, "bancada": false, "fogo": true, "libera": "achou:peixe", "ruido": 15.0, "tempo": 3.0},
	{"id": "lanca", "da": "lanca", "qtd": 1, "precisa": {"madeira": 3, "pedra": 2, "corda": 1}, "bancada": true, "libera": "dia:2", "ruido": 90.0, "tempo": 2.5},
	{"id": "sinalizador", "da": "sinalizador", "qtd": 1, "precisa": {"fosforos": 2, "metal": 1, "tecido": 1}, "bancada": true, "libera": "dia:2", "ruido": 40.0, "tempo": 2.5},
]


static func liberada(r: Dictionary, dia: int, achados: Array) -> bool:
	var l: String = r["libera"]
	if l == "inicio":
		return true
	if l.begins_with("dia:"):
		return dia >= int(l.trim_prefix("dia:"))
	if l.begins_with("achou:"):
		return l.trim_prefix("achou:") in achados
	return false


static func pode_criar(r: Dictionary, inv: Inventario, perto_da_bancada: bool, perto_do_fogo := false) -> bool:
	if r["bancada"] and not perto_da_bancada:
		return false
	if r.get("fogo", false) and not perto_do_fogo:
		return false
	for id in r["precisa"]:
		if not inv.tem(id, r["precisa"][id]):
			return false
	return inv.cabe(r["da"], r["qtd"]) or _libera_espaco(r, inv)


## Mesmo com a mochila cheia, se os ingredientes liberam um espaço, dá para criar.
static func _libera_espaco(r: Dictionary, inv: Inventario) -> bool:
	for id in r["precisa"]:
		if inv.contar(id) == r["precisa"][id]:
			return true
	return false


static func criar(r: Dictionary, inv: Inventario) -> bool:
	for id in r["precisa"]:
		if not inv.tem(id, r["precisa"][id]):
			return false
	for id in r["precisa"]:
		inv.remover(id, r["precisa"][id])
	var sobrou := inv.adicionar(r["da"], r["qtd"])
	return sobrou == 0


static func texto_ingredientes(r: Dictionary, inv: Inventario) -> String:
	var partes: Array[String] = []
	for id in r["precisa"]:
		partes.append("%s %d/%d" % [Itens.nome(id), inv.contar(id), r["precisa"][id]])
	return ", ".join(partes)
