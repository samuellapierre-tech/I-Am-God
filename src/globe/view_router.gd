extends RefCounted
## Bascule entre les deux vues (fonctions pures, testées par tests/test_globe.gd) :
## "globe" (la planète 3D, src/globe/globe.gd) et "ground" (la vue rapprochée, scenes/parcel_view.tscn).
## Une seule vue est visible et traite les entrées ; l'autre est PROCESS_MODE_DISABLED, ce qui
## garantit qu'un clic n'applique jamais un pouvoir deux fois. La simulation, elle, continue.

const GLOBE := "globe"
const GROUND := "ground"
const MODES := [GLOBE, GROUND]


static func is_valid(mode: String) -> bool:
	return mode in MODES


static func toggled(mode: String) -> String:
	return GROUND if mode == GLOBE else GLOBE


## Active les nœuds de la vue `mode` et désactive ceux de l'autre (visibilité, traitement, caméras).
## `views` : {"globe": [Node...], "ground": [Node...]}. Les nœuds sans vue (HUD, stats) ne bougent pas.
static func apply(mode: String, views: Dictionary) -> void:
	for key in views:
		var active: bool = key == mode
		for node in views[key]:
			if node == null:
				continue
			set_active(node, active)


static func set_active(node: Node, active: bool) -> void:
	node.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if "visible" in node:
		node.set("visible", active)
	for child in node.get_children():
		if child is Camera3D:
			(child as Camera3D).current = active
		elif child is Camera2D:
			# Godot 4 : Camera2D n'a pas de « current » ; enabled + make_current().
			(child as Camera2D).enabled = active
			if active and child.is_inside_tree():
				(child as Camera2D).make_current()


## Nœud qui reçoit les entrées dans `mode` parmi `views` (le premier de la liste).
static func input_owner(mode: String, views: Dictionary) -> Node:
	var list: Array = views.get(mode, [])
	return list[0] if not list.is_empty() else null


## Recopie l'outil choisi (pouvoir, rayon, cible) d'une vue à l'autre lors d'une bascule, pour que le
## HUD retrouve son état ; l'ancienne vue est désarmée (aucun pouvoir) pour qu'elle ne puisse rien
## appliquer en double.
static func transfer_power_state(from: Object, to: Object) -> void:
	if from == null or to == null or from == to:
		return
	var power := String(from.get("power")) if "power" in from else ""
	if "target_species" in from and to.has_method("set_target_species"):
		to.call("set_target_species", int(from.get("target_species")))
	if to.has_method("set_power"):
		to.call("set_power", power)
	if "radius" in from and to.has_method("set_radius"):
		to.call("set_radius", int(from.get("radius")))
	if from.has_method("set_power"):
		from.call("set_power", "")


## Vrai quand un cran de molette vers l'arrière, au sol, doit faire remonter au globe : la caméra de
## la vue rapprochée est déjà (presque) au zoom minimal.
static func should_ascend(target_zoom: float, zoom: float, min_zoom: float) -> bool:
	return target_zoom <= min_zoom * 1.001 and zoom <= min_zoom * 1.03
