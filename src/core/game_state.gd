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
## Couche stratégique (src/strategy/, docs/STRATEGIE.md) : signaux relayés depuis `strategy`.
signal round_started(round: Dictionary)
signal threat_revealed(threat: Dictionary)
signal threat_resolved(threat: Dictionary, countered: bool)
signal tracks_changed(tracks: Dictionary)
signal game_over(victory: bool, reason: String)
## Samaël, l'adversaire : {kind: "reveal"|"strike"|"taunt_hook", threat, reason_code} (le narrateur
## lui donne la parole), et les habitudes du joueur qu'il a apprises : {power, weight, share}.
signal samael_move(move: Dictionary)
signal samael_learned(habit: Dictionary)
## Éternité : un chapitre se ferme (fin douce d'une « défaite ») et le monde continue.
signal chapter_closed(chapter: Dictionary)

const WorldSim := preload("res://src/sim/world_sim.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")
const Strategy := preload("res://src/strategy/strategy.gd")

## Recalcul de la parcelle au plus 4 fois par seconde réelle.
const PARCEL_INTERVAL := 0.25
## Parcelle par défaut : zone tempérée côtière, choisie avant que le joueur n'en désigne une.
const DEFAULT_PARCEL := Vector2i(70, 40)

var sim: WorldSim
var parcel: ParcelSim
## Manches, menaces et pistes (contrat docs/ARCHITECTURE.md « Stratégie »). Recréée par new_world.
var strategy: Strategy
## Aspect divin et difficulté choisis au lancement (gardés d'une partie à l'autre).
var strategy_aspect := Strategy.Rules.DEFAULT_ASPECT
var strategy_difficulty := Strategy.Rules.DEFAULT_DIFFICULTY
## "eternity" (par défaut : calme, sans fin) | "trial" (victoire ou défaite).
var strategy_mode := Strategy.Rules.DEFAULT_MODE
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
	_make_strategy()
	world_updated.emit()
	era_changed.emit(_last_era)


func _process(delta: float) -> void:
	if paused or sim == null:
		return
	play_time += delta
	var stepped := sim.step(years_per_second * delta)
	for event in stepped:
		_pending_events.append(event)
		event_occurred.emit(event)
	if strategy != null:
		# Les menaces non contrées frappent via la simulation : leurs conséquences sont des événements.
		for event in strategy.update(sim, parcel, stepped):
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


## Change l'aspect divin et la difficulté (écran de lancement) : la stratégie repart de zéro sur le
## même monde. À appeler avant que la partie n'avance.
func configure_strategy(aspect: String, difficulty: String, mode := "") -> void:
	strategy_aspect = aspect
	strategy_difficulty = difficulty
	if mode != "":
		strategy_mode = mode
	_make_strategy()


func _make_strategy() -> void:
	strategy = Strategy.new(sim.seed, strategy_aspect, strategy_difficulty, strategy_mode)
	# Éternité : la simulation ne s'arrête jamais (si elle sait le faire).
	if sim.has_method("set_endless"):
		sim.set_endless(strategy_mode == "eternity")
	strategy.round_started.connect(round_started.emit)
	strategy.threat_revealed.connect(threat_revealed.emit)
	strategy.threat_resolved.connect(threat_resolved.emit)
	strategy.tracks_changed.connect(tracks_changed.emit)
	strategy.game_over.connect(game_over.emit)
	strategy.samael_move.connect(samael_move.emit)
	strategy.samael_learned.connect(samael_learned.emit)
	strategy.chapter_closed.connect(chapter_closed.emit)
	strategy.start(sim, parcel)


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


## Parcelle de départ : la terre la plus vivante du monde (plusieurs espèces établies, climat
## tempéré à chaud, humide), pour que la partie s'ouvre sur des dinosaures et non sur un désert.
## Une cellule testée par région écologique (4×4) ; déterministe à graine égale.
func _liveliest_cell() -> Vector2i:
	if sim.is_prologue() and sim.land_flora <= 0.0:
		# Avant toute vie terrestre : un estran à stromatolites qui émergera (voir ParcelSim).
		return ParcelSim.pick_start_cell(sim)
	var best := _first_land_cell(DEFAULT_PARCEL)
	var best_score := -1.0
	for y in range(2, WorldSim.HEIGHT, 4):
		for x in range(2, WorldSim.WIDTH, 4):
			var i := y * WorldSim.WIDTH + x
			if sim.elevation[i] < 0.0:
				continue
			var niches := sim.region_niches(Vector2i(x, y))
			if niches.is_empty():
				continue
			var density := 0.0
			for n in niches:
				density += float(n.density)
			var t := sim.temperature[i]
			var climate := clampf(1.0 - absf(t - 0.6) * 3.0, 0.05, 1.0)
			var score := density * niches.size() * climate * (0.5 + sim.moisture[i])
			if score > best_score:
				best_score = score
				best = Vector2i(x, y)
	return best


## Première cellule de terre en partant de `start` (balayage en spirale grossière).
func _first_land_cell(start: Vector2i) -> Vector2i:
	for r in range(0, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := Vector2i(posmod(start.x + dx, WorldSim.WIDTH), clampi(start.y + dy, 0, WorldSim.HEIGHT - 1))
				if sim.elevation[c.y * WorldSim.WIDTH + c.x] >= 0.0:
					return c
	return start
