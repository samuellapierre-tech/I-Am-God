extends RefCounted
## Nom du compagnon qui parle dans le fil (docs/GENESE.md : Ézéchiel).
## Seul endroit de l'interface où le nom est écrit : tout passe par speaker_name().

const DEFAULT_SPEAKER := "Ézéchiel"
const AI_CONFIG_PATH := "res://src/ai/ai_config.gd"


## Nom de l'orateur : `speaker` fourni (p. ex. dans les métadonnées d'une ligne), sinon NARRATOR_NAME
## des constantes de ai_config.gd, sinon DEFAULT_SPEAKER.
static func speaker_name(speaker: Variant = null, config_constants: Dictionary = {}) -> String:
	var name := _text(speaker)
	if name == "":
		name = _text(config_constants.get("NARRATOR_NAME"))
	return name if name != "" else DEFAULT_SPEAKER


## « — Ézéchiel »
static func signature(name: String) -> String:
	return "— " + name


## Constantes de src/ai/ai_config.gd ({} si le script n'existe pas), clés en String.
static func load_config_constants() -> Dictionary:
	if not ResourceLoader.exists(AI_CONFIG_PATH):
		return {}
	var script := load(AI_CONFIG_PATH) as Script
	var out := {}
	if script:
		var constants := script.get_script_constant_map()
		for k in constants:
			out[str(k)] = constants[k]
	return out


static func _text(v: Variant) -> String:
	return "" if v == null else str(v).strip_edges()
