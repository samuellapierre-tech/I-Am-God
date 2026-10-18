extends RefCounted
## STUB — remplacé par la branche feature/simulation-core.
## Le contrat public (champs + méthodes ci-dessous) doit être conservé.

const WIDTH := 256
const HEIGHT := 128

const ERAS := [
	"Mésozoïque", "Cénozoïque", "Préhistoire", "Antiquité",
	"Moyen Âge", "Renaissance", "Industriel", "Moderne", "Cyberpunk", "Post-singularité",
]

var seed: int
var year: float = -66_000_000.0
## Grilles WIDTH*HEIGHT, indexées par y * WIDTH + x.
var elevation := PackedFloat32Array()   # -1 (abysses) .. 1 (montagnes)
var temperature := PackedFloat32Array() # 0 (glacial) .. 1 (torride)
var population := PackedFloat32Array()  # 0 .. 1 densité de l'espèce dominante
var tech := PackedFloat32Array()        # 0 .. 1 niveau technologique local
var dominant_species := PackedInt32Array() # -1 = aucune
## id -> {name, alive, sapient, population, traits}
var species := {}


func _init(p_seed: int) -> void:
	seed = p_seed
	var n := WIDTH * HEIGHT
	elevation.resize(n)
	temperature.resize(n)
	population.resize(n)
	tech.resize(n)
	dominant_species.resize(n)
	dominant_species.fill(-1)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	for y in HEIGHT:
		for x in WIDTH:
			var i := y * WIDTH + x
			elevation[i] = noise.get_noise_2d(x, y)
			temperature[i] = 1.0 - absf(float(y) / HEIGHT - 0.5) * 2.0


func step(years: float) -> Array:
	year += years
	return []


func apply_divine_action(_action: Dictionary) -> Array:
	return []


func current_era() -> String:
	return ERAS[0]


func fork() -> RefCounted:
	return get_script().new(seed)


func project_future(_years: float) -> Dictionary:
	return {}
