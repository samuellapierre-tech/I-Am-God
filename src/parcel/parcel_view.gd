extends Node2D
## Vue parcelle : le terrain suivi, plein écran, vu de haut. Le jeu ne montre qu'elle.
## - Terrain (shader) : sol selon biome et usage, végétation, eau, fondus de transition.
## - Créatures : exactement parcel.fauna[].count individus animés par espèce.
## - Structures : parcel.structures à leurs positions stables.
## - Pouvoirs : appliqués par src/ui/parcel_powers.gd (nœud frère "ParcelPowers") ; la vue ne fait
##   qu'afficher l'aperçu sous le curseur et l'effet local quand divine_action_applied arrive.
## La vue n'invente rien : nombres, rôles et constructions viennent de GameState.parcel.

const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")
const ParcelAssets := preload("res://src/parcel/parcel_assets.gd")
const WorldSim := preload("res://src/sim/world_sim.gd")
const Terrain := preload("res://src/parcel/parcel_terrain.gd")
const StructureLayer := preload("res://src/parcel/structure_layer.gd")
const CreatureLayer := preload("res://src/parcel/creature_layer.gd")
const PowerFx := preload("res://src/parcel/power_fx.gd")
const ParcelCamera := preload("res://src/parcel/parcel_camera.gd")
const TrailLayer := preload("res://src/parcel/trail_layer.gd")
const AmbientLayer := preload("res://src/parcel/ambient_layer.gd")

## Rayon visuel (unités monde) d'un pouvoir : base + par cellule de rayon.
const FX_BASE_RADIUS := 90.0
const FX_RADIUS_PER_CELL := 8.0

var assets := ParcelAssets.new()
var _cell := Vector2i(-999, -999)

@onready var terrain: Terrain = $Terrain
@onready var trail: TrailLayer = $Trail
@onready var structures: StructureLayer = $Structures
@onready var creatures: CreatureLayer = $Creatures
@onready var ambient: AmbientLayer = $Ambient
@onready var fx: PowerFx = $Fx
@onready var camera: ParcelCamera = $Camera


func _ready() -> void:
	structures.assets = assets
	creatures.assets = assets
	creatures.trail = trail
	GameState.parcel_updated.connect(_on_parcel_updated)
	GameState.divine_action_applied.connect(_on_divine_action)
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
	trail.set_ground(ParcelLogic.ground_kind(p.land_use, p.biome))
	ambient.apply_parcel(p, ParcelLogic.swarm_centers(p.cell, AmbientLayer.SWARMS, PackedVector2Array()))


func _process(_delta: float) -> void:
	var powers := _powers()
	var power := String(powers.get("power")) if powers != null and "power" in powers else ""
	fx.preview_power = power
	if power != "":
		fx.preview_radius = _fx_radius(int(powers.get("radius")) if "radius" in powers else 0)


## Effet visuel local. ParcelPowers applique le pouvoir pendant le clic : si le bouton gauche est
## enfoncé, l'effet part du curseur ; sinon (action venue d'ailleurs) du centre de la parcelle.
func _on_divine_action(action: Dictionary, _consequences: Array) -> void:
	var p = GameState.parcel
	var power := String(action.get("type", ""))
	var radius := int(action.get("radius", 0))
	if p == null or not ParcelLogic.region_hits_parcel(action.get("region", Vector2i(-999, -999)), radius, p.cell, WorldSim.WIDTH):
		return
	var rect := Rect2(Vector2.ZERO, ParcelLogic.PARCEL_SIZE)
	var mouse := get_global_mouse_position()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and rect.has_point(mouse):
		fx.spawn(power, mouse, _fx_radius(radius))
	else:
		fx.spawn(power, rect.get_center(), _fx_radius(radius) * 2.0)
	if power == "meteor":
		camera.shake(28.0)
	elif power in ["flood", "ice_age", "extinct"]:
		camera.shake(8.0)


func _fx_radius(cells: int) -> float:
	return FX_BASE_RADIUS + FX_RADIUS_PER_CELL * cells


## État du pouvoir choisi dans le HUD (power, radius, target_species, signal state_changed).
func _powers() -> Node:
	var parent := get_parent()
	return parent.get_node_or_null("ParcelPowers") if parent != null else null
