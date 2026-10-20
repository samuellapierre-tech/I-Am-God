extends RefCounted
## Arbre de la vie : filiation des espèces d'une partie (parent, enfants, apparition, extinction,
## semée par le joueur, touchée par une action divine).
##
## On l'alimente avec les événements de WorldSim (`ingest(events, sim.species)`, après chaque
## step() et apply_divine_action()) ; `sync(sim.species)` rattrape les espèces déjà là (rosters de
## départ, chargement d'une sauvegarde). La mémoire est bornée : au-delà de MAX_NODES nœuds, les
## branches éteintes les plus anciennes (feuilles éteintes, sans descendance) sont résumées dans
## leur ancêtre (`hidden` : nombre d'espèces, dates, clades). Les lignées semées ou touchées par
## Dieu sont résumées en dernier. Un parent absent de la table (espèce oubliée par la simulation)
## devient un nœud « résumé » (`ghost`) : chaque parent existe ou est résumé, jamais de cycle.
##
## Formats exposés :
## - to_tree() : arbre imbriqué pour l'interface (arbre zoomable) ;
## - layout() : lignes à plat {id, parent, depth, x, born, extinct…} prêtes à dessiner ;
## - ancestors(id), descent_text(id) : pour Ézéchiel (« descend de… ») ;
## - to_dict() / from_dict() : sauvegarde.

const Species := preload("res://src/sim/species.gd")

const MAX_NODES := 4096
const PRUNE_TO := 3072
## Gestes divins gardés par nœud (les plus récents).
const MAX_TOUCHES := 8
## Racines d'actions divines suivies pour attribuer leurs conséquences (bornées).
const MAX_DIVINE_ROOTS := 256
## Types d'événements qui font naître une espèce.
const BIRTH_TYPES := ["speciation", "clade", "spawn", "seed", "seeding", "sow"]
const SEED_TYPES := ["seed", "seeding", "sow"]

## id -> nœud : {id, parent, children, name, vernacular, clade, born, extinct, seeded, created,
## sapient, touched: [{type, year}], ghost, hidden: {count, first_born, last_extinct, clades}}
var nodes := {}
## Branches résumées sans ancêtre connu (lignées éteintes très anciennes issues des racines).
var root_hidden := {count = 0, first_born = INF, last_extinct = -INF, clades = {}}
var _divine_roots := {}
## Noms vernaculaires déjà donnés (bornés : les plus anciens peuvent resservir).
var _used_vernacular := {}
const MAX_NAMES := 20000


# =============================================================================================
# Construction
# =============================================================================================

func _new_node(id: int, parent: int, year: float, info: Dictionary) -> Dictionary:
	return {
		id = id, parent = parent, children = [], name = String(info.get("name", "Espèce %d" % id)),
		vernacular = String(info.get("vernacular", "")), clade = String(info.get("clade", "")),
		born = year, extinct = NAN, seeded = bool(info.get("seeded", false)),
		created = bool(info.get("created", false)), sapient = bool(info.get("sapient", false)),
		touched = [], ghost = bool(info.get("ghost", false)),
		hidden = {count = 0, first_born = INF, last_extinct = -INF, clades = {}},
	}


## Ajoute une espèce. `parent` < 0 : racine. Un parent inconnu devient un ancêtre résumé.
func add_species(id: int, parent: int, year: float, info := {}) -> void:
	if nodes.has(id):
		var n: Dictionary = nodes[id]
		if bool(n.ghost):
			# L'ancêtre résumé est enfin connu : il garde sa place, ses enfants et ses résumés.
			n.ghost = false
			n.born = year
			for key in ["name", "vernacular", "clade"]:
				if info.has(key):
					n[key] = String(info[key])
			n.seeded = bool(info.get("seeded", n.seeded))
			n.created = bool(info.get("created", n.created))
		return
	if parent == id:
		parent = -1
	if parent >= 0 and not nodes.has(parent):
		nodes[parent] = _new_node(parent, -1, year, {name = "Ancêtre oublié", ghost = true})
	# Garde-fou : un parent qui descendrait déjà de cette espèce créerait un cycle.
	if parent >= 0 and _is_descendant(parent, id):
		parent = -1
	nodes[id] = _new_node(id, parent, year, info)
	if parent >= 0:
		(nodes[parent].children as Array).append(id)
	if nodes.size() > MAX_NODES:
		prune()


func _is_descendant(candidate: int, ancestor: int) -> bool:
	var cur := candidate
	var guard := 0
	while cur >= 0 and nodes.has(cur) and guard < 100000:
		if cur == ancestor:
			return true
		cur = int(nodes[cur].parent)
		guard += 1
	return false


func mark_extinct(id: int, year: float) -> void:
	if nodes.has(id):
		nodes[id].extinct = year


func mark_revived(id: int) -> void:
	if nodes.has(id):
		nodes[id].extinct = NAN


func mark_seeded(id: int) -> void:
	if nodes.has(id):
		nodes[id].seeded = true


## Une action divine a touché l'espèce (`type` : "meteor", "save", "uplift"…).
func mark_touched(id: int, type: String, year: float) -> void:
	if not nodes.has(id):
		return
	var t: Array = nodes[id].touched
	t.append({type = type, year = year})
	if t.size() > MAX_TOUCHES:
		t.remove_at(0)


func _info_from(sp: Dictionary, created := false) -> Dictionary:
	var traits: Dictionary = sp.get("traits", {})
	var info := {
		name = String(sp.get("name", "")), clade = String(traits.get("clade", sp.get("clade", ""))),
		sapient = bool(sp.get("sapient", false)), created = created,
		seeded = bool(sp.get("seeded", false)) or traits.has("seed_kind"),
	}
	if not traits.is_empty():
		info.vernacular = _unique_vernacular(traits)
	return info


## Nom vernaculaire (pluriel) unique dans la partie : en cas d'homonymie, une variante tirée
## d'une autre graine, puis un numéro d'ordre. C'est le nom canonique pour l'interface et Ézéchiel.
func _unique_vernacular(traits: Dictionary) -> String:
	var name := Species.vernacular_name(traits, true)
	var k := 0
	var t := traits
	while _used_vernacular.has(name) and k < 6:
		k += 1
		t = traits.duplicate()
		t.gseed = hash([int(traits.get("gseed", 0)), k])
		name = Species.vernacular_name(t, true)
	if _used_vernacular.has(name):
		var n := 2
		while _used_vernacular.has("%s (%d)" % [name, n]):
			n += 1
		name = "%s (%d)" % [name, n]
	_used_vernacular[name] = true
	if _used_vernacular.size() > MAX_NAMES:
		_used_vernacular.erase(_used_vernacular.keys()[0])
	return name


## Rattrape les espèces de la table (id -> {name, parent, born_year, alive, extinct_year, traits}).
func sync(species_table: Dictionary) -> void:
	var ids := species_table.keys()
	ids.sort()
	for id in ids:
		var sp: Dictionary = species_table[id]
		if not nodes.has(id) or bool(nodes[id].ghost):
			add_species(int(id), int(sp.get("parent", -1)), float(sp.get("born_year", 0.0)), _info_from(sp))
		if nodes.has(id):
			if bool(sp.get("alive", true)):
				nodes[id].extinct = NAN
			elif is_nan(float(nodes[id].extinct)):
				var ey := float(sp.get("extinct_year", NAN))
				nodes[id].extinct = ey if not is_nan(ey) else float(sp.get("born_year", 0.0))
			nodes[id].name = String(sp.get("name", nodes[id].name))
			nodes[id].sapient = bool(sp.get("sapient", false))


## Alimente l'arbre avec des événements de WorldSim. `species_table` : sim.species.
func ingest(events: Array, species_table: Dictionary) -> void:
	for ev in events:
		var type := String(ev.get("type", ""))
		var sid := int(ev.get("species_id", -1))
		var year := float(ev.get("year", 0.0))
		if type.begins_with("divine_"):
			_divine_roots[int(ev.get("id", -1))] = true
			if _divine_roots.size() > MAX_DIVINE_ROOTS:
				_divine_roots.erase(_divine_roots.keys()[0])
			if sid >= 0:
				if not nodes.has(sid) and species_table.has(sid):
					_add_from_table(sid, species_table, year, false)
				mark_touched(sid, type.trim_prefix("divine_"), year)
			continue
		if sid < 0:
			continue
		if BIRTH_TYPES.has(type) and species_table.has(sid):
			_add_from_table(sid, species_table, year, type == "spawn")
			if SEED_TYPES.has(type):
				mark_seeded(sid)
		elif not nodes.has(sid) and species_table.has(sid):
			_add_from_table(sid, species_table, year, false)
		if not nodes.has(sid):
			continue
		match type:
			"extinction":
				mark_extinct(sid, year)
			"lazarus":
				mark_revived(sid)
			"sapience":
				nodes[sid].sapient = true
				if species_table.has(sid):
					nodes[sid].name = String(species_table[sid].get("name", nodes[sid].name))
		var cause := int(ev.get("cause_id", -1))
		if cause > 0 and _divine_roots.has(cause) and type != "spawn":
			mark_touched(sid, type, year)


func _add_from_table(sid: int, species_table: Dictionary, year: float, created: bool) -> void:
	var sp: Dictionary = species_table[sid]
	var parent := int(sp.get("parent", -1))
	# Les ancêtres connus de la table passent avant, pour garder leurs vrais noms et dates.
	if parent >= 0 and not nodes.has(parent) and species_table.has(parent):
		_add_from_table(parent, species_table, float(species_table[parent].get("born_year", year)), false)
		if not bool(species_table[parent].get("alive", true)):
			mark_extinct(parent, float(species_table[parent].get("extinct_year", year)))
	var born := float(sp.get("born_year", year))
	add_species(sid, parent, born if not is_nan(born) else year, _info_from(sp, created))


# =============================================================================================
# Mémoire bornée
# =============================================================================================

func _protected(n: Dictionary) -> bool:
	return bool(n.seeded) or bool(n.created) or not (n.touched as Array).is_empty() or bool(n.sapient)


func _merge_hidden(into: Dictionary, n: Dictionary) -> void:
	var h: Dictionary = n.hidden
	into.count = int(into.count) + 1 + int(h.count)
	into.first_born = minf(float(into.first_born), minf(float(n.born), float(h.first_born)))
	var ext := float(n.extinct) if not is_nan(float(n.extinct)) else float(n.born)
	into.last_extinct = maxf(float(into.last_extinct), maxf(ext, float(h.last_extinct)))
	var clades: Dictionary = into.clades
	var c := String(n.clade)
	if c != "":
		clades[c] = int(clades.get(c, 0)) + 1
	for k in h.clades:
		clades[k] = int(clades.get(k, 0)) + int(h.clades[k])


## Résume les branches éteintes les plus anciennes jusqu'à PRUNE_TO nœuds.
func prune() -> void:
	var guard := 0
	while nodes.size() > PRUNE_TO and guard < 64:
		guard += 1
		var cands := []
		for id in nodes:
			var n: Dictionary = nodes[id]
			if (n.children as Array).is_empty() and not is_nan(float(n.extinct)):
				cands.append([1 if _protected(n) else 0, float(n.extinct), int(id)])
		if cands.is_empty():
			break
		cands.sort_custom(_older)
		var excess := nodes.size() - PRUNE_TO
		for i in mini(excess, cands.size()):
			_remove_leaf(int(cands[i][2]))
	# Les feuilles ne suffisent pas (beaucoup d'espèces vivantes) : les ancêtres éteints à un seul
	# enfant sont court-circuités, l'enfant se rattache à son grand-parent (`via` compte les
	# générations résumées entre eux).
	guard = 0
	while nodes.size() > PRUNE_TO and guard < 64:
		guard += 1
		var links := []
		for id in nodes:
			var n: Dictionary = nodes[id]
			if (n.children as Array).size() == 1 and not is_nan(float(n.extinct)) and not bool(n.ghost) \
					and not bool(n.seeded) and not bool(n.created):
				links.append([1 if _protected(n) else 0, float(n.extinct), int(id)])
		if links.is_empty():
			return
		links.sort_custom(_older)
		var excess := nodes.size() - PRUNE_TO
		for i in mini(excess, links.size()):
			_splice(int(links[i][2]))


static func _older(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	if a[1] != b[1]:
		return a[1] < b[1]
	return a[2] < b[2]


func _splice(id: int) -> void:
	if not nodes.has(id):
		return
	var n: Dictionary = nodes[id]
	var ch: Array = n.children
	if ch.size() != 1:
		return
	var child: int = ch[0]
	var parent := int(n.parent)
	var c: Dictionary = nodes[child]
	c.parent = parent
	c.via = int(c.get("via", 0)) + 1 + int(n.get("via", 0))
	# Les branches déjà résumées de l'ancêtre passent à l'enfant ; l'ancêtre lui-même est compté.
	var h: Dictionary = n.hidden
	var into: Dictionary = nodes[parent].hidden if parent >= 0 and nodes.has(parent) else root_hidden
	var solo := n.duplicate()
	solo.hidden = {count = 0, first_born = INF, last_extinct = -INF, clades = {}}
	_merge_hidden(into, solo)
	var ch_h: Dictionary = c.hidden
	ch_h.count = int(ch_h.count) + int(h.count)
	ch_h.first_born = minf(float(ch_h.first_born), float(h.first_born))
	ch_h.last_extinct = maxf(float(ch_h.last_extinct), float(h.last_extinct))
	for k in h.clades:
		ch_h.clades[k] = int(ch_h.clades.get(k, 0)) + int(h.clades[k])
	if parent >= 0 and nodes.has(parent):
		var pc: Array = nodes[parent].children
		pc[pc.find(id)] = child
	nodes.erase(id)


func _remove_leaf(id: int) -> void:
	var n: Dictionary = nodes[id]
	var parent := int(n.parent)
	if parent >= 0 and nodes.has(parent):
		_merge_hidden(nodes[parent].hidden, n)
		(nodes[parent].children as Array).erase(id)
	else:
		_merge_hidden(root_hidden, n)
	nodes.erase(id)


# =============================================================================================
# Lecture
# =============================================================================================

func has_species(id: int) -> bool:
	return nodes.has(id)


## Une ligne de l'arbre (copie) : {id, parent, name, vernacular, clade, born, extinct, alive,
## seeded, created, sapient, touched, ghost, via, hidden}, ou {} si l'espèce est inconnue.
func node(id: int) -> Dictionary:
	return _row(id) if nodes.has(id) else {}


func parent_of(id: int) -> int:
	return int(nodes[id].parent) if nodes.has(id) else -1


func children_of(id: int) -> Array:
	return (nodes[id].children as Array).duplicate() if nodes.has(id) else []


func roots() -> Array:
	var out := []
	for id in nodes:
		if int(nodes[id].parent) < 0:
			out.append(int(id))
	return out


## Ancêtres, du parent à la racine (au plus `max_depth`).
func ancestors(id: int, max_depth := 256) -> Array:
	var out := []
	var cur := parent_of(id)
	while cur >= 0 and nodes.has(cur) and out.size() < max_depth:
		out.append(cur)
		cur = int(nodes[cur].parent)
	return out


## Nombre d'espèces descendantes (nœuds présents + branches résumées).
func descendant_count(id: int) -> int:
	if not nodes.has(id):
		return 0
	var total := 0
	var stack := [id]
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		total += int(nodes[cur].hidden.count)
		for c in nodes[cur].children:
			total += 1
			stack.append(int(c))
	return total


## Ancêtre commun le plus proche de deux espèces (-1 si aucun).
func common_ancestor(a: int, b: int) -> int:
	var seen := {a: true}
	for x in ancestors(a):
		seen[x] = true
	if seen.has(b):
		return b
	for y in ancestors(b):
		if seen.has(y):
			return y
	return -1


func stats() -> Dictionary:
	var alive := 0
	var hidden := int(root_hidden.count)
	for id in nodes:
		if is_nan(float(nodes[id].extinct)):
			alive += 1
		hidden += int(nodes[id].hidden.count)
	return {nodes = nodes.size(), alive = alive, extinct = nodes.size() - alive, hidden = hidden, roots = roots().size()}


static func _de(name: String) -> String:
	if name.is_empty():
		return "de"
	var c := name.substr(0, 1).to_lower()
	return ("d'" if "aeiouyéèêâîôœ".contains(c) else "de ") + name


static func format_year(year: float) -> String:
	var a := absf(year)
	var s := ""
	if a >= 1.0e9:
		s = "%.1f Ga" % (a / 1.0e9)
	elif a >= 1.0e6:
		s = "%.0f Ma" % (a / 1.0e6)
	elif a >= 1.0e3:
		s = "%.0f000 ans" % (a / 1.0e3)
	else:
		s = "%.0f ans" % a
	s = s.replace(".", ",")
	return ("-" + s) if year < 0.0 else ("+" + s)


## Filiation en une phrase pour Ézéchiel : « Ceratops terribilis descend de Hadrosaurus
## albilaminus, lui-même issu de Grypania lata, une lignée semée par Dieu. »
func descent_text(id: int, depth := 3) -> String:
	if not nodes.has(id):
		return ""
	var n: Dictionary = nodes[id]
	var anc := ancestors(id, depth)
	if anc.is_empty():
		if bool(n.seeded):
			return "%s est une lignée semée par Dieu (%s)." % [n.name, format_year(float(n.born))]
		if bool(n.created):
			return "%s a été façonné par Dieu (%s)." % [n.name, format_year(float(n.born))]
		return "%s n'a pas d'ancêtre connu : c'est une lignée originelle." % n.name
	var parts := []
	for i in anc.size():
		var a: Dictionary = nodes[anc[i]]
		var nm := "un ancêtre oublié" if bool(a.ghost) else String(a.name)
		var note := ""
		if bool(a.seeded):
			note = ", une lignée semée par Dieu"
		elif bool(a.created):
			note = ", façonné par Dieu"
		elif not bool(a.ghost):
			note = " (apparu en %s)" % format_year(float(a.born))
		if bool(a.ghost):
			parts.append(("issu " if i > 0 else "") + "d'un ancêtre oublié")
			break
		parts.append(("lui-même issu " if i > 0 else "") + _de(nm) + note)
	return "%s descend %s." % [n.name, ", ".join(parts)]


func _row(id: int) -> Dictionary:
	var n: Dictionary = nodes[id]
	return {
		id = id, parent = int(n.parent), name = n.name, vernacular = n.vernacular, clade = n.clade,
		born = float(n.born), extinct = float(n.extinct), alive = is_nan(float(n.extinct)),
		seeded = bool(n.seeded), created = bool(n.created), sapient = bool(n.sapient),
		touched = (n.touched as Array).duplicate(true), ghost = bool(n.ghost), via = int(n.get("via", 0)),
		hidden = (n.hidden as Dictionary).duplicate(true),
	}


## Arbre imbriqué pour l'interface : [{…ligne…, children: [...]}], depuis `root` (-1 : toutes
## les racines). `max_depth` / `max_nodes` bornent la taille rendue (les branches coupées sont
## signalées par `truncated`).
func to_tree(root := -1, max_depth := 64, max_nodes := 4096) -> Array:
	var tops := roots() if root < 0 else ([root] if nodes.has(root) else [])
	var out := []
	# Parcours en largeur (sans récursion : une lignée peut compter des milliers de générations).
	var queue := []
	var budget := max_nodes
	for r in tops:
		var row := _row(int(r))
		out.append(row)
		queue.append([row, 0])
		budget -= 1
	var head := 0
	while head < queue.size():
		var item: Array = queue[head]
		head += 1
		var row: Dictionary = item[0]
		var depth: int = item[1]
		var kids := []
		var ch: Array = nodes[row.id].children
		if depth < max_depth:
			for c in ch:
				if budget <= 0:
					break
				budget -= 1
				var kid := _row(int(c))
				kids.append(kid)
				queue.append([kid, depth + 1])
		row.children = kids
		row.truncated = kids.size() < ch.size()
	return out


## Lignes à plat prêtes à dessiner : `depth` (génération), `x` (position verticale : les feuilles
## en ordre, chaque parent au milieu de ses enfants), dates d'apparition et d'extinction.
func layout(root := -1) -> Array:
	var rows := []
	var next_leaf := 0.0
	var tops := roots() if root < 0 else ([root] if nodes.has(root) else [])
	for r in tops:
		# Parcours en profondeur itératif : préordre pour les lignes, postordre pour les x.
		var stack := [[int(r), 0, -1, false]]
		while not stack.is_empty():
			var item: Array = stack.pop_back()
			var id: int = item[0]
			if bool(item[3]):
				var idx: int = item[2]
				var ch: Array = nodes[id].children
				if ch.is_empty():
					rows[idx].x = next_leaf
					next_leaf += 1.0
				else:
					var lo := INF
					var hi := -INF
					for c in ch:
						var cx: float = rows[_row_index[c]].x
						lo = minf(lo, cx)
						hi = maxf(hi, cx)
					rows[idx].x = (lo + hi) * 0.5
				continue
			var row := _row(id)
			row.depth = int(item[1])
			row.x = 0.0
			_row_index[id] = rows.size()
			rows.append(row)
			stack.append([id, int(item[1]), rows.size() - 1, true])
			var ch: Array = nodes[id].children
			for i in range(ch.size() - 1, -1, -1):
				stack.append([int(ch[i]), int(item[1]) + 1, -1, false])
	_row_index.clear()
	return rows


var _row_index := {}


## Vérifie la cohérence (tests) : renvoie "" si tout va bien.
func check() -> String:
	for id in nodes:
		var n: Dictionary = nodes[id]
		var p := int(n.parent)
		if p >= 0:
			if not nodes.has(p):
				return "parent %d de %d absent et non résumé" % [p, id]
			if not (nodes[p].children as Array).has(id):
				return "%d absent des enfants de %d" % [id, p]
		for c in n.children:
			if not nodes.has(c) or int(nodes[c].parent) != int(id):
				return "enfant %d de %d incohérent" % [c, id]
		var cur := p
		var steps := 0
		while cur >= 0:
			if cur == int(id) or steps > nodes.size():
				return "cycle passant par %d" % id
			cur = int(nodes[cur].parent) if nodes.has(cur) else -1
			steps += 1
	return ""


# =============================================================================================
# Sauvegarde
# =============================================================================================

func to_dict() -> Dictionary:
	var out := []
	for id in nodes:
		var n: Dictionary = (nodes[id] as Dictionary).duplicate(true)
		out.append(n)
	return {version = 1, nodes = out, root_hidden = root_hidden.duplicate(true)}


static func from_dict(d: Dictionary) -> RefCounted:
	var p: RefCounted = (load("res://src/life/phylogeny.gd") as GDScript).new()
	for n in d.get("nodes", []):
		var node: Dictionary = (n as Dictionary).duplicate(true)
		node.id = int(node.id)
		node.parent = int(node.parent)
		var kids := []
		for c in node.get("children", []):
			kids.append(int(c))
		node.children = kids
		p.nodes[node.id] = node
	p.root_hidden = (d.get("root_hidden", p.root_hidden) as Dictionary).duplicate(true)
	return p
