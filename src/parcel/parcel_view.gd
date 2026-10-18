extends Node2D
## Vue parcelle : le terrain suivi, plein écran, vu de haut. Cœur visuel du jeu.
## - Terrain (shader) : sol selon biome et usage, végétation, eau, fondus de transition.
## - Créatures : exactement parcel.fauna[].count individus animés par espèce.
## - Structures : parcel.structures à leurs positions stables.
## - Pouvoirs : clic avec un pouvoir sélectionné sur le globe -> GameState.apply_divine_action.
## - Molette arrière au zoom minimal -> vue globe.
## La vue n'invente rien : nombres, rôles et constructions viennent de GameState.parcel.

const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")
const ParcelAssets := preload("res://src/parcel/parcel_assets.gd")
const Powers := preload("res://src/map/divine_powers.gd")
const WorldSim := preload("res://src/sim/world_sim.gd")
const Terrain := preload("res://src/parcel/parcel_terrain.gd")
const StructureLayer := preload("res://src/parcel/structure_layer.gd")
const CreatureLayer := preload("res://src/parcel/creature_layer.gd")
const PowerFx := preload("res://src/parcel/power_fx.gd")
const ParcelCamera := preload("res://src/parcel/parcel_camera.gd")

## Rayon visuel (unités monde) d'un pouvoir : base + par cellule de rayon.
const FX_BASE_RADIUS := 90.0
const FX_RADIUS_PER_CELL := 8.0

var assets := ParcelAssets.new()
var _cell := Vector2i(-999, -999)
## Position du dernier clic de pouvoir, en attente de divine_action_applied.
var _pending_click := Vector2.INF

@onready var terrain: Terrain = $Terrain
@onready var structures: StructureLayer = $Structures
@onready var creatures: CreatureLayer = $Creatures
@onready var fx: PowerFx = $Fx
@onready var camera: ParcelCamera = $Camera


func _ready() -> void:
	structures.assets = assets
	creatures.assets = assets
	GameState.parcel_updated.connect(_on_parcel_updated)
	GameState.divine_action_applied.connect(_on_divine_action)
	camera.exit_requested.connect(GameState.set_view_mode.bind("globe"))
	_on_parcel_updated()


func _on_parcel_updated() -> void:
	var p = GameState.parcel
	if p == null:
		return
	var changed: bool = p.cell != _cell
	if changed:
		_cell = p.cell
		creatures.clear()
		structures.clear()
		camera.reset_view()
	terrain.apply_parcel(p, changed)
	structures.apply_parcel(p)
	creatures.spots = structures.spots()
	creatures.apply_parcel(p)


func _process(_delta: float) -> void:
	var power := _power()
	fx.preview_power = power
	if power != "":
		fx.preview_radius = _fx_radius(_globe_int("radius", 0))


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var power := _power()
	var p = GameState.parcel
	if power == "" or p == null or GameState.sim == null:
		return
	var world_pos := get_canvas_transform().affine_inverse() * mb.position
	var info := Powers.get_power(power)
	var species_id := ParcelLogic.choose_species(info, creatures.species_at(world_pos),
		_globe_int("target_species", -1), p.fauna)
	_pending_click = world_pos
	GameState.apply_divine_action(Powers.make_action(power, p.cell, species_id, _globe_int("radius", int(info.get("radius", 0)))))
	_pending_click = Vector2.INF
	get_viewport().set_input_as_handled()


## Effet visuel : au point cliqué, ou au centre si l'action vient du globe et touche la parcelle.
func _on_divine_action(action: Dictionary, _consequences: Array) -> void:
	var power := String(action.get("type", ""))
	var radius := int(action.get("radius", 0))
	if _pending_click != Vector2.INF:
		fx.spawn(power, _pending_click, _fx_radius(radius))
	else:
		var p = GameState.parcel
		if p == null or not ParcelLogic.region_hits_parcel(action.get("region", Vector2i(-999, -999)), radius, p.cell, WorldSim.WIDTH):
			return
		fx.spawn(power, ParcelLogic.PARCEL_SIZE * 0.5, ParcelLogic.PARCEL_SIZE.x * 0.6)
	if power == "meteor":
		camera.shake(28.0)
	elif power in ["flood", "ice_age", "extinct"]:
		camera.shake(8.0)


func _fx_radius(cells: int) -> float:
	return FX_BASE_RADIUS + FX_RADIUS_PER_CELL * cells


## Le globe (ou l'ancienne carte) porte l'état du pouvoir choisi dans le HUD.
func _globe() -> Object:
	var parent := get_parent()
	if parent == null or not "globe" in parent:
		return null
	return parent.get("globe")


func _power() -> String:
	var g := _globe()
	if g == null or not "power" in g:
		return ""
	return String(g.get("power"))


func _globe_int(prop: String, fallback: int) -> int:
	var g := _globe()
	if g == null or not prop in g:
		return fallback
	return int(g.get(prop))
