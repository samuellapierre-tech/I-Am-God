extends Node
## État des pouvoirs divins quand le jeu ne montre que la parcelle suivie (pas de globe, pas de carte).
## Expose la même API publique que l'ancienne carte (src/map/world_map.gd) pour que le HUD s'y branche
## via bind_map() sans changement : toute l'interaction vise la cellule de GameState.parcel.
## Clic gauche n'importe où (hors interface) avec un pouvoir sélectionné = pouvoir sur la parcelle.

const ToolStateScript := preload("res://src/ui/tools/tool_state.gd")
const Powers := preload("res://src/map/divine_powers.gd")
const WorldSim := preload("res://src/sim/world_sim.gd")

## Gardé pour la compatibilité du HUD ; une seule couche : la parcelle elle-même.
const LAYERS := ["Parcelle"]

## Émis quand le pouvoir, le rayon ou l'espèce ciblée change.
signal state_changed
## Émis quand la parcelle suivie change (le HUD affiche alors ses infos).
signal region_hovered(region: Vector2i)

var power := ""
var radius := 8
var layer := 0
var target_species := -1
var grid := Vector2i(WorldSim.WIDTH, WorldSim.HEIGHT)

## Le panneau d'infos du HUD suit la parcelle au plus une fois par seconde (1.0 : dès la première mise à jour).
var _info_timer := 1.0


func _ready() -> void:
	GameState.parcel_changed.connect(region_hovered.emit)
	GameState.parcel_updated.connect(_on_parcel_updated)


func set_power(power_id: String) -> void:
	if power_id == power:
		return
	power = power_id
	var p := Powers.get_power(power_id)
	if not p.is_empty():
		radius = p.radius
	state_changed.emit()


func set_radius(r: int) -> void:
	r = clampi(r, Powers.MIN_RADIUS, Powers.MAX_RADIUS)
	if r != radius:
		radius = r
		state_changed.emit()


func set_layer(_i: int) -> void:
	pass


func set_target_species(id: int) -> void:
	if id != target_species:
		target_species = id
		state_changed.emit()


## Les événements de la chronique ne déplacent rien : on reste sur la parcelle.
func focus_region(_region: Vector2i) -> void:
	pass


## Tout l'écran est la parcelle.
func screen_to_region(_screen_pos: Vector2) -> Vector2i:
	return parcel_cell()


func parcel_cell() -> Vector2i:
	return GameState.parcel.cell if GameState.parcel != null else GameState.DEFAULT_PARCEL


func dominant_species_at(region: Vector2i) -> int:
	var sim = GameState.sim
	if sim == null:
		return -1
	var i := region.y * grid.x + region.x
	return sim.dominant_species[i] if i >= 0 and i < sim.dominant_species.size() else -1


## Outil de la palette (src/ui/tools/tool_state.gd) : semence ou pouvoir, avec recharge.
func _tools() -> Node:
	return ToolStateScript.shared(get_tree())


func _has_tool() -> bool:
	return power != "" or _tools().has_tool()


## Applique l'outil sélectionné (semence ou pouvoir) sur une région, via GameState. La palette
## démarre la recharge ; sans outil de palette, on retombe sur le pouvoir de la vue.
func apply_power_at(region: Vector2i) -> void:
	if GameState.sim == null or region.x < 0:
		return
	var tools := _tools()
	if tools.has_tool():
		var tool: Dictionary = tools.selected_tool()
		if str(tool.get("kind", "")) == "power":
			var params: Dictionary = tool.get("params", {})
			params.radius = radius
			params.species_id = target_species
			tool.params = params
		var a: Dictionary = tools.use(tool, region)
		if a.is_empty():
			return
		var p := Powers.get_power(str(a.get("type", "")))
		if p.get("needs_species", false) and int(a.get("species_id", -1)) < 0:
			a.species_id = dominant_species_at(region)
		GameState.apply_divine_action(a)
		return
	if power == "":
		return
	var p := Powers.get_power(power)
	var species_id := target_species
	if p.get("needs_species", false) and species_id < 0:
		species_id = dominant_species_at(region)
	elif not p.get("needs_species", false) and power != "spawn_species":
		species_id = -1
	GameState.apply_divine_action(Powers.make_action(power, region, species_id, radius))


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT and _has_tool():
		apply_power_at(parcel_cell())
		get_viewport().set_input_as_handled()
	elif mb.shift_pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		set_radius(radius + 1)
		get_viewport().set_input_as_handled()
	elif mb.shift_pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		set_radius(radius - 1)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_info_timer += delta


func _on_parcel_updated() -> void:
	if _info_timer >= 1.0:
		_info_timer = 0.0
		region_hovered.emit(parcel_cell())
