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
## "globe" (la planète 3D) ou "ground" (vue rapprochée du lieu suivi, scenes/parcel_view.tscn).
signal view_mode_changed(mode: String)
## Fin des temps de la planète (docs/GENESE.md) : bilan à raconter par Ézéchiel.
## summary = {world_name, world_index, age_years, year, species_total, species_max_alive, extinctions,
##   civilizations, notable: [{name, description, clade, sapient}], cause}
signal end_of_times(summary: Dictionary)
## Réincarnation : une nouvelle planète vierge. info = {world_name, world_index, params, previous}
signal world_reborn(info: Dictionary)
## Sauvegarde écrite / partie reprise (emplacement : "auto", "quick", "slot_1"…).
signal game_saved(slot: String)
signal game_loaded(slot: String)
const WorldSim := preload("res://src/sim/world_sim.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")
const SaveService := preload("res://src/save/save_service.gd")
const Pantheon := preload("res://src/save/pantheon.gd")
const Planet := preload("res://src/save/planet.gd")

## Recalcul de la parcelle au plus 4 fois par seconde réelle.
const PARCEL_INTERVAL := 0.25
## Parcelle par défaut : zone tempérée côtière, choisie avant que le joueur n'en désigne une.
const DEFAULT_PARCEL := Vector2i(70, 40)

var sim: WorldSim
var parcel: ParcelSim
## Vue active : "globe" au lancement ; "ground" quand on est descendu au sol.
var view_mode := "globe"
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

## Planète courante : nom, rang parmi les vies du joueur, paramètres de création.
var world_name := ""
var world_index := 1
var planet_params := {}
## Sauvegarde (src/save/save_service.gd) et Panthéon des mondes passés (src/save/pantheon.gd).
var saver: SaveService
var pantheon: Pantheon
## La fin des temps de cette planète a été annoncée.
var ended := false

var _last_era := ""
var _parcel_timer := 0.0
var _pending_events: Array = []


## Fermeture : aucun calcul de la simulation ne doit survivre au monde qu'il lit.
func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_EXIT_TREE, NOTIFICATION_PREDELETE] and sim != null:
		sim.shutdown()


func _ready() -> void:
	_ensure_save_services()
	new_world(randi())


func _ensure_save_services() -> void:
	if saver == null:
		saver = SaveService.new()
		saver.name = "Saver"
		add_child(saver)
	if pantheon == null:
		pantheon = Pantheon.new()
		pantheon.load_from_disk()


## Nouvelle planète. `params` (réincarnation) : ocean_fraction, axial_tilt, star_luminosity,
## plates… transmis à WorldSim par nom s'il les accepte (src/save/planet.gd).
func new_world(seed: int, params := {}) -> void:
	if sim != null:
		sim.shutdown()
	if params.is_empty():
		sim = WorldSim.new(seed)
	else:
		var p: Dictionary = params.duplicate()
		p.seed = seed
		sim = Planet.make_world(p)
	planet_params = params.duplicate()
	planet_params.seed = seed
	world_name = Planet.world_name(seed)
	if pantheon != null:
		world_index = pantheon.lives + 1
	ended = false
	if saver != null:
		saver.reset_tracking()
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
		_watch_event(event)
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
		_watch_event(event)
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
	if mode == view_mode or not mode in ["globe", "ground"]:
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


# =============================================================================================
# Sauvegarde, fin des temps, réincarnation (src/save/)
# =============================================================================================

## Remplace le monde courant par un monde rechargé (src/save/save_service.gd).
## info : {world_name, world_index, planet, play_time, parcel_timer, pending_events}
func adopt_world(p_sim: RefCounted, p_parcel: RefCounted, info := {}) -> void:
	sim = p_sim
	world_name = String(info.get("world_name", Planet.world_name(sim.seed)))
	world_index = int(info.get("world_index", world_index))
	planet_params = info.get("planet", {})
	play_time = float(info.get("play_time", 0.0))
	ended = false
	_last_era = sim.current_era()
	if p_parcel != null:
		parcel = p_parcel
		_pending_events = info.get("pending_events", []).duplicate(true)
		_parcel_timer = float(info.get("parcel_timer", 0.0))
		parcel_changed.emit(parcel.cell)
		parcel_updated.emit()
	else:
		select_parcel(_liveliest_cell())
	world_updated.emit()
	era_changed.emit(_last_era)


func save_game(slot := "quick") -> String:
	_ensure_save_services()
	return saver.save(slot)


func load_game(slot := "auto") -> String:
	_ensure_save_services()
	return saver.load_slot(slot)


func _watch_event(event: Dictionary) -> void:
	if saver != null:
		saver.note_event(event)
	if String(event.get("type", "")) == "end_of_times" and not ended:
		announce_end_of_times(String(event.get("summary", "")))


## Fin des temps de cette planète : bilan pour Ézéchiel et l'écran de fin. La simulation continue
## de tourner (le joueur peut contempler) jusqu'à la réincarnation.
func announce_end_of_times(cause := "") -> Dictionary:
	ended = true
	var summary := planet_summary(cause)
	end_of_times.emit(summary)
	return summary


## Bilan de la planète courante.
func planet_summary(cause := "") -> Dictionary:
	var extinct := 0
	var civs := 0
	for id in sim.species:
		var sp: Dictionary = sim.species[id]
		if not sp.alive:
			extinct += 1
		if sp.sapient:
			civs += 1
	var notable := []
	if saver != null:
		for sp_id in _notable_ids(8):
			var sp: Dictionary = sim.species[sp_id]
			notable.append({name = sp.name, description = Pantheon.describe(sp), clade = sp.get("clade", ""), sapient = sp.sapient})
	var start_year: float = sim.era_years.get(0, sim.year) if "era_years" in sim and not sim.era_years.is_empty() else sim.year
	return {
		world_name = world_name, world_index = world_index, year = sim.year,
		age_years = sim.year - float(start_year), species_total = sim.get("_next_species_id") if "_next_species_id" in sim else sim.species.size(),
		species_max_alive = sim.get_alive_species().size(), extinctions = extinct, civilizations = civs,
		notable = notable, cause = cause,
	}


func _notable_ids(n: int) -> Array:
	var ranked := []
	for id in sim.species:
		var sp: Dictionary = sim.species[id]
		var score := int(saver.peaks.get(id, sp.get("regions", 0)))
		if sp.sapient:
			score += 100000
		if saver.created.has(id):
			score += 50000
		ranked.append([score, int(id)])
	ranked.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out := []
	for i in mini(n, ranked.size()):
		out.append(ranked[i][1])
	return out


## Réincarnation : les espèces marquantes rejoignent le Panthéon, puis le joueur renaît devant une
## nouvelle planète vierge aux paramètres différents. `params` vide : tirés au hasard.
func reincarnate(params := {}) -> Dictionary:
	_ensure_save_services()
	saver.track(sim)
	var previous := {index = world_index, name = world_name, seed = sim.seed, params = planet_params,
		ended_year = sim.year, species_total = sim.species.size()}
	pantheon.harvest(sim, {world_name = world_name, world_index = world_index}, saver.peaks, saver.created)
	pantheon.record_world(previous)
	pantheon.lives = maxi(pantheon.lives, world_index)
	pantheon.save_to_disk()
	if params.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%d:%d:%d" % [sim.seed, world_index, Time.get_ticks_usec()])
		params = Planet.random_params(rng)
	var seed_value := int(params.get("seed", randi()))
	new_world(seed_value, params)
	var info := {world_name = world_name, world_index = world_index, params = planet_params, previous = previous}
	world_reborn.emit(info)
	if saver.autosave:
		saver.save(SaveService.AUTO_SLOT)
	return info


## Ressème une espèce du Panthéon (semence « façonnée ») sur `cell`. Utilise WorldSim.sow() si la
## simulation l'expose ; sinon le pouvoir Création, dont l'espèce reçoit ensuite le nom et les traits
## de l'espèce du Panthéon. Renvoie les événements produits.
func reseed_from_pantheon(entry: Dictionary, cell: Vector2i) -> Array:
	var action: Dictionary = Pantheon.reseed_action(entry, cell)
	if sim.has_method("sow"):
		var evs: Array = sim.sow(action)
		for event in evs:
			_pending_events.append(event)
			event_occurred.emit(event)
			_watch_event(event)
		world_updated.emit()
		return evs
	var evs := apply_divine_action(action)
	for ev in evs:
		var sid := int(ev.get("species_id", -1))
		if String(ev.get("type", "")) == "spawn" and sim.species.has(sid):
			var sp: Dictionary = sim.species[sid]
			var traits: Dictionary = action.traits.duplicate(true)
			for key in sp.traits:
				if not traits.has(key):
					traits[key] = sp.traits[key]
			sp.traits = traits
			if action.name != "":
				sp.name = action.name
			if sim.has_method("_refresh_species"):
				sim._refresh_species(sid)
			break
	return evs
