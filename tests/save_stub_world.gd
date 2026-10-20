extends RefCounted
## Monde factice pour tests/test_save.gd : même forme de constructeur que le WorldSim de la Planète
## (seed, generate, scenario, planet: Dictionary) et crochets prepare_save() / post_load().

var seed := 0
var generated := true
var scenario := ""
var planet := {}
var data := PackedFloat32Array()
var _pending := 0.0
var prepared := 0
var loaded := 0


func _init(p_seed: int, p_generate := true, p_scenario := "genesis", p_planet := {}) -> void:
	seed = p_seed
	generated = p_generate
	scenario = p_scenario
	planet = p_planet


## Un calcul « en cours » terminé avant la sauvegarde.
func prepare_save() -> void:
	prepared += 1
	if _pending != 0.0:
		data.append(_pending)
		_pending = 0.0


func post_load() -> void:
	loaded += 1
