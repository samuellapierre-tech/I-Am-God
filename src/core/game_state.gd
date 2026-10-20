extends Node
## Autoload central : possède la simulation et relaie les événements entre les systèmes.
## Contrat partagé entre les branches — ne pas changer les signatures sans mettre à jour docs/ARCHITECTURE.md.

signal world_updated
signal event_occurred(event: Dictionary)
signal era_changed(era: String)
signal divine_action_applied(action: Dictionary, consequences: Array)
## La parcelle suivie a été recalculée (cadence limitée, voir PARCEL_INTERVAL).
signal parcel_updated
## Le joueur suit une nouvelle parcelle.
signal parcel_changed(cell: Vector2i)
## "globe" (planète 3D) ou "parcel" (le terrain suivi, plein écran).
signal view_mode_changed(mode: String)
const WorldSim := preload("res://src/sim/world_sim.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")

## Recalcul de la parcelle au plus 4 fois par seconde réelle.
const PARCEL_INTERVAL := 0.25
## Parcelle par défaut : zone tempérée côtière, choisie avant que le joueur n'en désigne une.
const DEFAULT_PARCEL := Vector2i(70, 40)

var sim: WorldSim
var parcel: ParcelSim
var view_mode := "parcel"
var paused := false
## Années simulées par seconde réelle.
var years_per_second := 1_000_000.0

## Ouverture lente : avant toute espèce intelligente, le temps est ralenti pour qu'on ait le loisir
## de regarder vivre les dinosaures sur la parcelle. Facteur appliqué à la vitesse x1..x5 du HUD :
## OPENING_PACE_START au lancement, qui monte vers OPENING_PACE en OPENING_RAMP secondes de jeu.
## Une fois une espèce consciente apparue : 1.0 (une ère ≈ une minute à x1).
const OPENING_PACE_START := 0.02
const OPENING_PACE := 0.1
const OPENING_RAMP := 180.0

## Secondes réelles de jeu écoulées hors pause (pour la rampe d'ouverture).
var play_time := 0.0

var _last_era := ""
var _parcel_timer := 0.0
var _pending_events: Array = []


func _ready() -> void:
	new_world(randi())


func new_world(seed: int) -> void:
	sim = WorldSim.new(seed)
	play_time = 0.0
	_last_era = sim.current_era()
	select_parcel(_liveliest_cell())
	# Genèse (docs/GENESE.md) : la simulation ne s'arrête jamais.
	if sim.has_method("set_endless"):
		sim.set_endless(true)
	world_updated.emit()
	era_changed.emit(_last_era)


func _process(delta: float) -> void:
	if paused or sim == null:
		return
	play_time += delta
	for event in sim.step(years_per_second * delta):
		_pending_events.append(event)
		event_occurred.emit(event)
	var era := sim.current_era()
	if era != _last_era:
		_last_era = era
		era_changed.emit(era)
	world_updated.emit()
	_parcel_timer += delta
	if _parcel_timer >= PARCEL_INTERVAL:
		_refresh_parcel()


## action : {type: String, region: Vector2i, species_id: int, radius: int}
func apply_divine_action(action: Dictionary) -> Array:
	var consequences := sim.apply_divine_action(action)
	divine_action_applied.emit(action, consequences)
	for event in consequences:
		_pending_events.append(event)
		event_occurred.emit(event)
	_pending_events.append({type = action.get("type", ""), region = action.get("region", Vector2i(-1, -1))})
	world_updated.emit()
	_refresh_parcel()
	return consequences


## Multiplicateur de vitesse de l'ouverture (voir OPENING_PACE). Le HUD l'applique à sa vitesse.
func pace_factor() -> float:
	if sim == null or not sim.get_sapient_species().is_empty():
		return 1.0
	return opening_pace(play_time)


static func opening_pace(seconds: float) -> float:
	return lerpf(OPENING_PACE_START, OPENING_PACE, clampf(seconds / OPENING_RAMP, 0.0, 1.0))


## Le joueur suit désormais `cell` (coordonnées de la grille WorldSim).
func select_parcel(cell: Vector2i) -> void:
	parcel = ParcelSim.new(sim, cell)
	_pending_events.clear()
	_parcel_timer = 0.0
	parcel_changed.emit(parcel.cell)
	parcel_updated.emit()


func set_view_mode(mode: String) -> void:
	if mode == view_mode or not mode in ["globe", "parcel"]:
		return
	view_mode = mode
	view_mode_changed.emit(mode)


func _refresh_parcel() -> void:
	_parcel_timer = 0.0
	if parcel == null:
		return
	var events := _pending_events
	_pending_events = []
	for event in parcel.update(events):
		event_occurred.emit(event)
	parcel_updated.emit()


## Parcelle de départ : sur une planète vierge, une côte (un haut-fond qui émergera) ; déterministe.
func _liveliest_cell() -> Vector2i:
	# Planète vierge : le départ se fait sur une côte (haut-fond qui émergera), voir ParcelSim.
	return ParcelSim.pick_start_cell(sim)


func _first_land_cell(start: Vector2i) -> Vector2i:
	for r in range(0, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := Vector2i(posmod(start.x + dx, WorldSim.WIDTH), clampi(start.y + dy, 0, WorldSim.HEIGHT - 1))
				if sim.elevation[c.y * WorldSim.WIDTH + c.x] >= 0.0:
					return c
	return start
