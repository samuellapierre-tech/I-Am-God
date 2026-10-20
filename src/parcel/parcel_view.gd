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
const Atmosphere := preload("res://src/parcel/atmosphere.gd")
const NightLights := preload("res://src/parcel/night_lights.gd")
const ParcelParticles := preload("res://src/parcel/parcel_particles.gd")
const WaterVeil := preload("res://src/parcel/water_veil.gd")

## Rayon visuel (unités monde) d'un pouvoir : base + par cellule de rayon.
const FX_BASE_RADIUS := 90.0
const FX_RADIUS_PER_CELL := 8.0

var assets := ParcelAssets.new()
var _cell := Vector2i(-999, -999)
## Repères permanents de la parcelle (rivière en S, rocher) : fixés pour toute la partie.
var _landmarks := {}
## Pas plus d'un focus automatique de la caméra toutes les FOCUS_COOLDOWN secondes.
const FOCUS_COOLDOWN := 12.0
var _focus_cooldown := 0.0
## Pendant l'approche du météore, la parcelle n'est pas encore touchée : on retient ses mises à
## jour jusqu'à l'impact.
var _hold_updates := false
var _held_update := false

@onready var terrain: Terrain = $Terrain
@onready var trail: TrailLayer = $Trail
@onready var structures: StructureLayer = $Structures
@onready var creatures: CreatureLayer = $Creatures
@onready var ambient: AmbientLayer = $Ambient
@onready var fx: PowerFx = $Sky/Fx
@onready var atmosphere: Atmosphere = $Sky/Atmosphere
@onready var lights: NightLights = $Sky/NightLights
## Prologue : la parcelle vue à travers la mer, puis les terres qui émergent.
@onready var water: WaterVeil = $Sky/WaterVeil
## Lumière ambiante (jour, aube, nuit, temps couvert) : assombrit tout le calque du monde ;
## lumières, météo et effets sont dans le calque "Sky", non assombri.
@onready var daylight: CanvasModulate = $Daylight
@onready var camera: ParcelCamera = $Camera


func _ready() -> void:
	structures.assets = assets
	creatures.assets = assets
	creatures.trail = trail
	creatures.traits_of = _species_traits
	structures.trail = trail
	GameState.parcel_updated.connect(_on_parcel_updated)
	GameState.divine_action_applied.connect(_on_divine_action)
	fx.impact.connect(_on_impact)
	GameState.event_occurred.connect(_on_event)
	atmosphere.lightning_struck.connect(func(_at: Vector2) -> void: camera.shake(5.0))
	_on_parcel_updated()


func _on_parcel_updated() -> void:
	var p = GameState.parcel
	if p == null:
		return
	if _hold_updates:
		_held_update = true
		return
	var changed: bool = p.cell != _cell
	if changed:
		_cell = p.cell
		creatures.clear()
		structures.clear()
		camera.reset_view()
		var seed_value: int = GameState.sim.seed if GameState.sim != null else 0
		_landmarks = ParcelLogic.landmarks(seed_value, p.cell)
		terrain.set_landmarks(_landmarks)
		structures.landmarks = _landmarks
		creatures.set_landmarks(_landmarks)
		water.set_landmarks(_landmarks)
		water.set_cell(p.cell)
	terrain.apply_parcel(p, changed)
	structures.apply_parcel(p)
	creatures.spots = structures.spots()
	creatures.apply_parcel(p)
	trail.set_ground(ParcelLogic.ground_kind(p.land_use, p.biome))
	atmosphere.apply_parcel(p)
	lights.land_use = p.land_use
	lights.campfire = ParcelLogic.campfire_near(_landmarks)
	ambient.apply_parcel(p, ParcelLogic.swarm_centers(p.cell, AmbientLayer.SWARMS, _landmarks.river), p.year)


func _process(delta: float) -> void:
	_focus_cooldown = maxf(0.0, _focus_cooldown - delta)
	# Le temps qui passe : lumière, saisons, sommeil des animaux, lumières de la nuit.
	var night := 1.0 - atmosphere.daylight
	daylight.color = atmosphere.sky
	terrain.set_season(maxf(atmosphere.snow_cover, atmosphere.pulse_level("frost") * 0.9), atmosphere.autumn)
	ambient.set_night(night)
	creatures.night = night
	lights.intensity = clampf(night + (1.0 - atmosphere.sky.v) * 0.3, 0.0, 1.0)
	lights.sources = structures.light_sources()
	lights.roads = structures.road_centers()
	var p = GameState.parcel
	if p != null:
		var rs := ParcelLogic.river_state(p.land_use, p.water, atmosphere.snow_cover)
		creatures.set_river_open(rs.x > 0.5 and rs.y < 0.5 and terrain.submerged_level < 0.5)
		water.update_water(terrain.submerged_level, ParcelLogic.sea_tint(p.year), atmosphere.sky)

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
	if power == "meteor":
		_hold_updates = true
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and rect.has_point(mouse):
		fx.spawn(power, mouse, _fx_radius(radius))
	else:
		fx.spawn(power, rect.get_center(), _fx_radius(radius) * 2.0)


## Le pouvoir touche le sol (après la traînée pour le météore) : conséquences visuelles durables.
func _on_impact(power: String, at: Vector2, radius: float) -> void:
	if power == "meteor" and _hold_updates:
		_hold_updates = false
		if _held_update:
			_held_update = false
			_on_parcel_updated()
	if power in ["meteor", "flood", "extinct", "uplift", "spawn_species"]:
		_focus_on(at, 1.5 if power == "meteor" else 1.35, true)
	match power:
		"meteor":
			camera.shake(30.0)
			atmosphere.meteor_impact()
			trail.emit(TrailLayer.Kind.SCORCH, at, 0.0, radius * 2.4, 110.0)
			terrain.ignite(maxf(GameState.parcel.vegetation if GameState.parcel else 0.5, 0.5))
			_crater_smoke(at, radius)
		"flood":
			camera.shake(6.0)
			terrain.flood_pulse()
		"ice_age":
			camera.shake(4.0)
			atmosphere.pulse("frost", at)
		"plague":
			atmosphere.pulse("miasma", at)
		"bless":
			atmosphere.pulse("golden", at)
		"extinct":
			camera.shake(8.0)
			trail.emit(TrailLayer.Kind.SCORCH, at, 0.0, radius * 0.8, 40.0)


## Événements importants de la parcelle : on s'approche doucement, puis on revient.
func _on_event(event: Dictionary) -> void:
	var type := String(event.get("type", ""))
	match type:
		"parcel_land_use":
			_focus_on(ParcelLogic.PARCEL_SIZE * 0.5, 1.2)
		"parcel_arrival":
			var herd := creatures.herd_center_of(int(event.get("species_id", -1)))
			if herd.x < INF:
				_focus_on(herd, 1.6)


func _focus_on(point: Vector2, zoom_factor: float, force := false) -> void:
	if _focus_cooldown > 0.0 and not force:
		return
	_focus_cooldown = FOCUS_COOLDOWN
	camera.focus(point, zoom_factor, 2.5)


## Cratère fumant : colonne de fumée qui s'éteint en une trentaine de secondes.
func _crater_smoke(at: Vector2, radius: float) -> void:
	var smoke := ParcelParticles.make_smoke(Vector2(radius * 0.3, radius * 0.2), 60)
	smoke.position = at
	smoke.z_index = 7
	smoke.emitting = true
	add_child(smoke)
	get_tree().create_timer(25.0).timeout.connect(func() -> void: smoke.emitting = false)
	get_tree().create_timer(33.0).timeout.connect(smoke.queue_free)


## Génome d'une espèce (lecture seule dans la simulation) : l'apparence en découle.
func _species_traits(species_id: int) -> Dictionary:
	if GameState.sim == null:
		return {}
	var sp: Dictionary = GameState.sim.species.get(species_id, {})
	return sp.get("traits", {})


func _fx_radius(cells: int) -> float:
	return FX_BASE_RADIUS + FX_RADIUS_PER_CELL * cells


## État du pouvoir choisi dans le HUD (power, radius, target_species, signal state_changed).
func _powers() -> Node:
	var parent := get_parent()
	return parent.get_node_or_null("ParcelPowers") if parent != null else null
