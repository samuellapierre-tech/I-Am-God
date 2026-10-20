extends RefCounted
## Nouvelle planète pour la réincarnation : paramètres tirés au hasard (graine, part d'océans,
## inclinaison, luminosité de l'étoile, nombre de plaques) et nom procédural.
## Construction tolérante : si WorldSim._init a un argument `planet` (dictionnaire, contrat de la
## Planète : {ocean_fraction, axial_tilt, star_luminosity, plates}, clés absentes = DEFAULT_PLANET),
## les paramètres y passent ; sinon chacun par nom (préfixe « p_ » accepté). Le reste va à
## configure_planet() si elle existe.

const WorldSim := preload("res://src/sim/world_sim.gd")

## Paramètres de planète (dictionnaire `planet` de WorldSim._init).
const PLANET_KEYS := ["ocean_fraction", "axial_tilt", "star_luminosity", "plates"]

const SYLLABLES := ["ka", "lo", "mi", "ra", "the", "u", "va", "sel", "or", "ny", "da", "el", "is",
	"zo", "ar", "qui", "nae", "to", "bri", "an"]


static func random_params(rng: RandomNumberGenerator) -> Dictionary:
	return {
		seed = rng.randi(),
		ocean_fraction = snappedf(rng.randf_range(0.35, 0.85), 0.01),
		axial_tilt = snappedf(rng.randf_range(0.0, 45.0), 0.1),
		star_luminosity = snappedf(rng.randf_range(0.85, 1.2), 0.01),
		plates = rng.randi_range(5, 14),
	}


static func world_name(seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("nom:%d" % seed_value)
	var n := ""
	for i in rng.randi_range(2, 3):
		n += SYLLABLES[rng.randi_range(0, SYLLABLES.size() - 1)]
	return n.capitalize()


## Construit une planète vierge avec ces paramètres (tolérant aux arguments que WorldSim n'a pas).
static func make_world(params: Dictionary, script: Script = WorldSim) -> RefCounted:
	var info := {}
	for m in script.get_script_method_list():
		if m.name == "_init":
			info = m
			break
	var args := []
	var used := {}
	var defaults: Array = info.get("default_args", [])
	var n: int = info.get("args", []).size()
	var first_default := n - defaults.size()
	for i in n:
		var name := String(info.args[i].name).trim_prefix("p_")
		if name == "planet":
			var planet := {}
			for k in PLANET_KEYS:
				if params.has(k):
					planet[k] = params[k]
					used[k] = true
			args.append(planet)
		elif params.has(name):
			args.append(params[name])
			used[name] = true
		elif i >= first_default:
			args.append(defaults[i - first_default])
		else:
			args.append(null)
	var w: RefCounted = script.new.callv(args)
	if w.has_method("configure_planet"):
		var rest := {}
		for k in params:
			if not used.has(k):
				rest[k] = params[k]
		if not rest.is_empty():
			w.configure_planet(rest)
	return w


## Arguments de planète que WorldSim accepte aujourd'hui (pour l'affichage et les tests).
static func supported_params(script: Script = WorldSim) -> Array[String]:
	var out: Array[String] = []
	for m in script.get_script_method_list():
		if m.name == "_init":
			for a in m.args:
				var name := String(a.name).trim_prefix("p_")
				if name == "planet":
					out.append_array(PLANET_KEYS)
				else:
					out.append(name)
	return out
