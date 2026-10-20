extends RefCounted
## Arbre de la vie : données de filiation et mise en page (pure, testée par tests/test_calm_ui.gd).
##
## Format attendu (session Vie). Lu via has_method, sinon reconstruit depuis WorldSim.species :
##   sim.lineage() -> Array[Dictionary], une entrée par espèce ayant existé dans la partie :
##     {id: int, parent: int (-1 = racine), name: String, born_year: float,
##      extinct_year: float (NAN si vivante), alive: bool, traits: Dictionary,
##      sown: bool (semée par le joueur), touched: bool (visée par un acte du joueur),
##      description: String (facultatif)}
## Repli actuel : WorldSim.species[id] = {name, alive, parent, born_year, extinct_year, traits…}.
## Les marques « semée » / « touchée » sont aussi déduites des actions du joueur (TreeLayout.marks).
##
## Mise en page : abscisse = temps « déplié » (rang d'apparition : l'axe s'étire là où la vie
## foisonne), ordonnée = couloir. Chaque espèce est un segment [naissance, extinction ou présent] ;
## les espèces sont placées par date de naissance, au plus près du couloir de leur parent, dans un
## couloir libre sur tout leur intervalle (garantit l'absence de chevauchement).

## Écart minimal (en rangs) entre deux segments d'un même couloir.
const GAP := 0.6


## Entrées de filiation : sim.lineage() si disponible, sinon WorldSim.species.
static func entries_from(sim: Object) -> Array:
	if sim == null:
		return []
	if sim.has_method("lineage"):
		var l = sim.call("lineage")
		if l is Array:
			return l
	var out := []
	if not "species" in sim:
		return out
	var species: Dictionary = sim.get("species")
	for id in species:
		var s = species[id]
		if not s is Dictionary:
			continue
		out.append({
			id = int(id), parent = int(s.get("parent", -1)), name = str(s.get("name", "#%d" % int(id))),
			born_year = float(s.get("born_year", 0.0)), extinct_year = float(s.get("extinct_year", NAN)),
			alive = bool(s.get("alive", true)), traits = s.get("traits", {}),
			sown = bool(s.get("sown", false)), touched = bool(s.get("touched", false)),
			description = str(s.get("description", "")),
		})
	return out


## Mise en page. `now` = année courante (fin des segments des espèces vivantes).
## Renvoie {nodes: {id: {x0, x1, lane, parent}}, lanes: int, width: float, ranks: PackedFloat64Array}
## où x0/x1 sont en rangs (0..width) et ranks les années de naissance triées (pour l'axe du temps).
static func compute(entries: Array, now: float) -> Dictionary:
	var items := entries.duplicate()
	items.sort_custom(func(a, b):
		return a.born_year < b.born_year or (a.born_year == b.born_year and a.id < b.id))
	var births := PackedFloat64Array()
	births.resize(items.size())
	for i in items.size():
		births[i] = items[i].born_year
	var nodes := {}
	var lane_end := PackedFloat64Array()  # fin du dernier segment de chaque couloir
	for i in items.size():
		var e: Dictionary = items[i]
		var x0 := float(i)
		var end_year: float = e.extinct_year if is_finite(float(e.extinct_year)) else now
		var x1 := maxf(x0 + 0.5, year_to_rank(births, end_year))
		var parent_lane := -1
		if nodes.has(e.parent):
			parent_lane = nodes[e.parent].lane
		var lane := _free_lane(lane_end, x0, parent_lane)
		if lane == lane_end.size():
			lane_end.append(x1)
		else:
			lane_end[lane] = x1
		nodes[e.id] = {x0 = x0, x1 = x1, lane = lane, parent = e.parent}
	return {nodes = nodes, lanes = lane_end.size(), width = float(maxi(items.size(), 1)), ranks = births}


## Rang (abscisse) d'une année : nombre de naissances survenues avant (interpolé).
static func year_to_rank(births: PackedFloat64Array, year: float) -> float:
	var n := births.size()
	if n == 0:
		return 0.0
	var i := births.bsearch(year, true)
	if i <= 0:
		return 0.0
	if i >= n:
		return float(n)
	var a := births[i - 1]
	var b := births[i]
	var t := 0.0 if b <= a else clampf((year - a) / (b - a), 0.0, 1.0)
	return float(i - 1) + t


## Année au rang `x` (graduations de l'axe du temps).
static func rank_to_year(births: PackedFloat64Array, x: float) -> float:
	var n := births.size()
	if n == 0:
		return 0.0
	var i := clampi(int(floorf(x)), 0, n - 1)
	if i >= n - 1:
		return births[n - 1]
	return lerpf(births[i], births[i + 1], clampf(x - i, 0.0, 1.0))


## Couloir libre à partir de x0, le plus proche de `near` (couloir du parent) ; sinon un nouveau.
static func _free_lane(lane_end: PackedFloat64Array, x0: float, near: int) -> int:
	var n := lane_end.size()
	if near < 0:
		for l in n:
			if lane_end[l] + GAP <= x0:
				return l
		return n
	for d in range(1, n + 1):
		var below := near + d
		if below < n and lane_end[below] + GAP <= x0:
			return below
		var above := near - d
		if above >= 0 and lane_end[above] + GAP <= x0:
			return above
		if below >= n and above < 0:
			break
	return n


## Vrai si deux segments d'un même couloir se chevauchent (contrôle des tests).
static func has_overlap(layout: Dictionary) -> bool:
	var by_lane := {}
	for id in layout.nodes:
		var n: Dictionary = layout.nodes[id]
		if not by_lane.has(n.lane):
			by_lane[n.lane] = []
		by_lane[n.lane].append(Vector2(n.x0, n.x1))
	for lane in by_lane:
		var segs: Array = by_lane[lane]
		segs.sort_custom(func(a, b): return a.x < b.x)
		for i in range(1, segs.size()):
			if segs[i].x < segs[i - 1].y:
				return true
	return false


## Ancêtres de `id`, du parent à la racine (s'arrête sur un cycle ou un parent inconnu).
static func ancestors(by_id: Dictionary, id: int, max_depth: int = 256) -> Array[int]:
	var out: Array[int] = []
	var seen := {id: true}
	var cur: int = int(by_id[id].get("parent", -1)) if by_id.has(id) else -1
	while cur >= 0 and by_id.has(cur) and not seen.has(cur) and out.size() < max_depth:
		out.append(cur)
		seen[cur] = true
		cur = int(by_id[cur].get("parent", -1))
	return out


## Marques du joueur déduites d'une action divine et de ses conséquences :
## {sown: [ids], touched: [ids]}. Les semences (type « seed ») et « spawn_species » sèment ;
## les autres actes touchent l'espèce visée et celles que les conséquences nomment.
static func marks(action: Dictionary, consequences: Array) -> Dictionary:
	var sown: Array[int] = []
	var touched: Array[int] = []
	var t := str(action.get("type", ""))
	var sowing := t == "seed" or t == "spawn_species"
	var target := int(action.get("species_id", -1))
	if target >= 0 and not sowing:
		touched.append(target)
	for c in consequences:
		if not c is Dictionary:
			continue
		var sid := int(c.get("species_id", -1))
		if sid < 0:
			continue
		var ctype := str(c.get("type", ""))
		if sowing and ctype in ["spawn", "seed", "speciation", "seeded"]:
			if not sid in sown:
				sown.append(sid)
		elif not sid in touched and not sid in sown:
			touched.append(sid)
	return {sown = sown, touched = touched}


## Description de repli tirée des traits (si ni la simulation ni l'IA n'en fournissent) :
## « Grand carnivore terrestre, plutôt intelligent. »
static func describe_traits(traits: Dictionary) -> String:
	var size := float(traits.get("size", 0.3))
	var diet := str(traits.get("diet", ""))
	var habitat := str(traits.get("habitat", ""))
	var size_word := "Minuscule" if size < 0.03 else ("Petit" if size < 0.2 else ("Moyen" if size < 0.55 else "Grand"))
	var diet_word: String = {herbivore = "herbivore", omnivore = "omnivore", carnivore = "carnivore",
		autotrophe = "producteur"}.get(diet, "organisme")
	var habitat_word: String = {marine = "marin", amphibious = "des rivages", land = "terrestre"}.get(habitat, "")
	var text := "%s %s" % [size_word, diet_word]
	if habitat_word != "":
		text += " " + habitat_word
	var intel := float(traits.get("intelligence", 0.0))
	if intel >= 0.78:
		text += ", doué de conscience"
	elif intel >= 0.45:
		text += ", plutôt intelligent"
	var clade := str(traits.get("clade", ""))
	if clade != "":
		text += " (lignée : %s)" % clade
	return text + "."
