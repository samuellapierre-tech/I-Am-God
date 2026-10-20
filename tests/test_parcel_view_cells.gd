extends RefCounted
## Vue rapprochée « partout » : changement de cellule sans fuite, coût CPU de centaines
## d'individus, caractéristiques et côtes des cellules. Chaque test renvoie "" si tout va bien.

const WorldSim := preload("res://src/sim/world_sim.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")
const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")
const CreatureLayer := preload("res://src/parcel/creature_layer.gd")
const StructureLayer := preload("res://src/parcel/structure_layer.gd")
const TrailLayer := preload("res://src/parcel/trail_layer.gd")

const PLANS := ["worm", "segmented", "fusiform", "quadruped", "biped", "flyer", "bell", "radial", "blob", "shell"]


func _traits(id: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = id
	return {body_plan = PLANS[id % PLANS.size()], size = rng.randf_range(0.05, 0.9), limbs = rng.randi_range(0, 8),
		eyes = rng.randi_range(0, 4), aggression = rng.randf(), temp_opt = rng.randf(),
		diet = ["herbivore", "omnivore", "carnivore"][id % 3]}


func _fauna(first_id: int, species: int, count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k in species:
		var id := first_id + k
		var t := _traits(id)
		out.append({species_id = id, name = "Espèce %d" % id, count = count, density = 0.5, trend = 0,
			role = t.diet, habitat = "land", size = t["size"], clade = "", diet = t.diet})
	return out


## Les tests tournent avant la boucle principale (pas d'arbre de scène) : on initialise les
## calques à la main, hors arbre.
func _init_node(n: Node) -> void:
	n._ready()


## Changer de cellule des dizaines de fois ne laisse ni nœuds ni objets derrière soi.
func test_cell_change_does_not_leak() -> String:
	var sim := WorldSim.new(5)
	var layer := CreatureLayer.new()
	layer.traits_of = _traits
	var structures := StructureLayer.new()
	var trail := TrailLayer.new()
	layer.trail = trail
	for n in [layer, structures, trail]:
		_init_node(n)
	var base := 0
	var base_nodes := 0
	for i in 60:
		var p := ParcelSim.new(sim, Vector2i((i * 37) % WorldSim.WIDTH, 20 + (i * 7) % 60))
		p.fauna.clear()
		p.fauna.append_array(_fauna(1000 + i * 10, 6, 12))
		layer.clear()
		structures.clear()
		trail.clear()
		layer.apply_parcel(p)
		structures.apply_parcel(p)
		layer._process(1.0 / 60.0)
		if i == 10:
			base = int(Performance.get_monitor(Performance.OBJECT_COUNT))
			base_nodes = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT)) - base
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - base_nodes
	for n in [layer, structures, trail]:
		n.free()
	if nodes > 2:
		return "%d nœuds de plus après 50 changements de cellule" % nodes
	if objects > 40:
		return "%d objets de plus après 50 changements de cellule" % objects
	print("après 50 changements de cellule : %+d objets, %+d nœuds" % [objects, nodes])
	return ""


## 300 individus de 40 espèces : le calcul des déplacements tient largement dans une image.
func test_300_individuals_40_species_cpu() -> String:
	var sim := WorldSim.new(3)
	var layer := CreatureLayer.new()
	layer.traits_of = _traits
	_init_node(layer)
	var p := ParcelSim.new(sim, Vector2i(70, 40))
	p.fauna.clear()
	p.fauna.append_array(_fauna(1, 40, 8))
	layer.apply_parcel(p)
	var total := 0
	for g in layer._groups.values():
		total += g.active_count()
	for i in 30: # mise en route (fondus, premières décisions)
		layer._process(1.0 / 60.0)
	var t0 := Time.get_ticks_usec()
	var frames := 120
	for i in frames:
		layer._process(1.0 / 60.0)
	var per_frame := float(Time.get_ticks_usec() - t0) / frames
	layer.free()
	if total < 300:
		return "seulement %d individus" % total
	print("%d individus, 40 espèces : %.2f ms de calcul par image" % [total, per_frame / 1000.0])
	if per_frame > 8000.0:
		return "trop lent : %.2f ms par image (budget 60 FPS : 16,7 ms tout compris)" % (per_frame / 1000.0)
	return ""


func test_cell_features_and_coast() -> String:
	var land := ParcelLogic.cell_features(9, Vector2i(10, 10), true, "Savane")
	if land != ParcelLogic.cell_features(9, Vector2i(10, 10), true, "Savane"):
		return "particularités de cellule non déterministes"
	var with_river := 0
	for x in 200:
		if ParcelLogic.cell_features(9, Vector2i(x, 33), true, "Savane").river:
			with_river += 1
	if with_river < 60 or with_river > 160:
		return "rivières mal réparties : %d cellules sur 200" % with_river
	for x in 50:
		if ParcelLogic.cell_features(9, Vector2i(x, 3), false, "Abysses").river:
			return "pas de rivière en mer"
	var lm := ParcelLogic.landmarks(9, Vector2i(1, 1), false, false)
	if not (lm.river as PackedVector2Array).is_empty() or Vector2(lm.rock_radii).x != 0.0:
		return "repères absents attendus"
	if ParcelLogic.avoid_landmarks(Vector2(300, 300), 20.0, lm) != Vector2(300, 300):
		return "rien à éviter sans repères"
	# Côte : grille 3×3, mer à gauche.
	var elev := PackedFloat32Array([-1, 0.5, 0.5, -1, 0.5, 0.5, -1, 0.5, 0.5])
	var c := ParcelLogic.coast_vector(elev, 3, 3, Vector2i(1, 1), 0.0)
	if c.x >= 0.0 or absf(c.y) > 0.01:
		return "la mer est à gauche : %s" % str(c)
	if not ParcelLogic.coast_is_water(Vector2(0.05, 0.5), c, false) or ParcelLogic.coast_is_water(Vector2(0.95, 0.5), c, false):
		return "côté mer / côté terre inversés"
	var inland := PackedFloat32Array([0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5])
	if ParcelLogic.coast_vector(inland, 3, 3, Vector2i(1, 1), 0.0) != Vector2.ZERO:
		return "pas de côte à l'intérieur des terres"
	if ParcelLogic.submerged("wild", "sea") != 1.0 or ParcelLogic.submerged("ocean") != 1.0 or ParcelLogic.submerged("wild", "land") != 0.0:
		return "immersion mal déduite du rivage"
	if ParcelLogic.depth_factor(4000.0) < 0.99 or ParcelLogic.depth_factor(10.0) > 0.0:
		return "profondeur mal normalisée"
	return ""
