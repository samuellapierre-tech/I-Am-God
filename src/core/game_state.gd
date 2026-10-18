extends Node
## Autoload central : possède la simulation et relaie les événements entre les systèmes.
## Contrat partagé entre les branches — ne pas changer les signatures sans mettre à jour docs/ARCHITECTURE.md.

signal world_updated
signal event_occurred(event: Dictionary)
signal era_changed(era: String)
signal divine_action_applied(action: Dictionary, consequences: Array)

const WorldSim := preload("res://src/sim/world_sim.gd")

var sim: WorldSim
var paused := false
## Années simulées par seconde réelle.
var years_per_second := 1_000_000.0

var _last_era := ""


func _ready() -> void:
	new_world(randi())


func new_world(seed: int) -> void:
	sim = WorldSim.new(seed)
	_last_era = sim.current_era()
	world_updated.emit()
	era_changed.emit(_last_era)


func _process(delta: float) -> void:
	if paused or sim == null:
		return
	for event in sim.step(years_per_second * delta):
		event_occurred.emit(event)
	var era := sim.current_era()
	if era != _last_era:
		_last_era = era
		era_changed.emit(era)
	world_updated.emit()


## action : {type: String, region: Vector2i, species_id: int, radius: int}
func apply_divine_action(action: Dictionary) -> Array:
	var consequences := sim.apply_divine_action(action)
	divine_action_applied.emit(action, consequences)
	for event in consequences:
		event_occurred.emit(event)
	world_updated.emit()
	return consequences
