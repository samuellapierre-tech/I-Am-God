extends RefCounted
## Fonctions pures du panneau de dilemme (sans nœud ni autoload) : normalisation et validation du
## dilemme reçu du Narrateur, barre de temps, écriture progressive, raccourcis clavier.
## Testées par tests/test_dilemma_ui.gd.
##
## Contrat attendu (Narrator.dilemma_ready) :
##   {id, title, text, options: [{label, hint, action}], timeout_s}
## Champs facultatifs reconnus : title (titre par défaut), hint, action, timeout_s (DEFAULT_TIMEOUT),
## default_index (option retenue si le temps s'écoule ; -1 = « Dieu se tait »),
## speaker (nom du narrateur qui signe le dilemme).

## Nom du narrateur, maître du jeu, quand ni le dilemme ni ai_config.gd ne le donnent.
## Seul endroit de l'interface où il est écrit : tout passe par speaker_name().
const DEFAULT_SPEAKER := "Ézéchiel"
const AI_CONFIG_PATH := "res://src/ai/ai_config.gd"

const MIN_OPTIONS := 2
const MAX_OPTIONS := 4
const DEFAULT_TITLE := "Un choix s'impose"
const DEFAULT_TIMEOUT := 30.0
const MIN_TIMEOUT := 5.0
const MAX_TIMEOUT := 300.0
## Délai (s) avant d'accepter un choix : évite qu'une touche pressée par réflexe tranche le dilemme.
const ARM_DELAY := 0.6
const CHARS_PER_SECOND := 55.0

const OPTION_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4]
const OPTION_KEYS_KP := [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4]


## Copie propre du dilemme : types convertis, valeurs par défaut, au plus MAX_OPTIONS options.
## Ne valide pas : appeler validate() sur le résultat.
static func normalize(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var d: Dictionary = raw
	var title := _text(d.get("title"))
	var options: Array[Dictionary] = []
	var raw_options = d.get("options", [])
	if raw_options is Array:
		for o in raw_options:
			if options.size() >= MAX_OPTIONS:
				break
			if o is Dictionary:
				options.append({
					label = _text(o.get("label")),
					hint = _text(o.get("hint")),
					action = o.get("action", {}),
				})
			elif o is String:
				options.append({label = _text(o), hint = "", action = {}})
	var timeout := DEFAULT_TIMEOUT
	var raw_timeout = d.get("timeout_s", null)
	if (raw_timeout is float or raw_timeout is int) and float(raw_timeout) > 0.0:
		timeout = clampf(float(raw_timeout), MIN_TIMEOUT, MAX_TIMEOUT)
	var default_index := int(d.get("default_index", -1)) if (d.get("default_index") is int) else -1
	if default_index >= options.size():
		default_index = -1
	return {
		id = d.get("id", null),
		title = title if title != "" else DEFAULT_TITLE,
		text = _text(d.get("text")),
		options = options,
		timeout_s = timeout,
		default_index = default_index,
		speaker = _text(d.get("speaker")),
	}


## Texte d'un champ quelconque (null -> "").
static func _text(v: Variant) -> String:
	return "" if v == null else str(v).strip_edges()


## "" si le dilemme (normalisé) est affichable, sinon la raison du refus.
static func validate(d: Dictionary) -> String:
	if d.is_empty():
		return "le dilemme n'est pas un dictionnaire"
	var id = d.get("id", null)
	if id == null or (id is String and (id as String).is_empty()):
		return "identifiant manquant"
	if not (id is int or id is String or id is StringName):
		return "identifiant de type inattendu"
	if _text(d.get("text")).is_empty():
		return "texte vide"
	var options = d.get("options", [])
	if not options is Array or options.size() < MIN_OPTIONS:
		return "il faut au moins %d options" % MIN_OPTIONS
	if options.size() > MAX_OPTIONS:
		return "au plus %d options" % MAX_OPTIONS
	for i in options.size():
		var o = options[i]
		if not o is Dictionary or _text(o.get("label")).is_empty():
			return "option %d sans libellé" % (i + 1)
	return ""


## Nom du narrateur : `speaker` du dilemme, sinon NARRATOR_NAME des constantes de ai_config.gd,
## sinon DEFAULT_SPEAKER.
static func speaker_name(speaker: Variant = null, config_constants: Dictionary = {}) -> String:
	var name := _text(speaker)
	if name == "":
		name = _text(config_constants.get("NARRATOR_NAME"))
	return name if name != "" else DEFAULT_SPEAKER


## « — Ézéchiel »
static func signature(name: String) -> String:
	return "— " + name


## Constantes de src/ai/ai_config.gd ({} si le script n'existe pas). Lu une fois par panneau.
static func load_config_constants() -> Dictionary:
	if not ResourceLoader.exists(AI_CONFIG_PATH):
		return {}
	var script := load(AI_CONFIG_PATH) as Script
	var out := {}
	if script:
		var constants := script.get_script_constant_map()
		for k in constants:
			out[str(k)] = constants[k]  # clés en String (la carte peut contenir des StringName)
	return out


## Part de temps restant (1 = plein, 0 = écoulé).
static func time_ratio(remaining: float, total: float) -> float:
	if total <= 0.0:
		return 0.0
	return clampf(remaining / total, 0.0, 1.0)


## Temps restant après `delta` secondes ; figé quand le jeu est en pause.
static func tick(remaining: float, delta: float, paused: bool) -> float:
	if paused:
		return remaining
	return maxf(0.0, remaining - maxf(delta, 0.0))


## Couleur de la barre : or tant qu'il reste du temps, puis orange, puis rouge.
static func time_color(ratio: float) -> Color:
	var gold := Color(1.0, 0.82, 0.4)
	var orange := Color(1.0, 0.55, 0.2)
	var red := Color(1.0, 0.25, 0.2)
	if ratio >= 0.5:
		return gold
	if ratio >= 0.2:
		return orange.lerp(gold, (ratio - 0.2) / 0.3)
	return red.lerp(orange, clampf(ratio, 0.0, 1.0) / 0.2)


## « 12 s », « 1 min 05 ».
static func format_remaining(seconds: float) -> String:
	var s := int(ceilf(maxf(seconds, 0.0)))
	if s < 60:
		return "%d s" % s
	return "%d min %02d" % [s / 60, s % 60]


## Nombre de caractères affichés par l'écriture progressive.
static func visible_chars(elapsed: float, total_chars: int, chars_per_second: float = CHARS_PER_SECOND) -> int:
	if chars_per_second <= 0.0:
		return total_chars
	return clampi(int(floorf(maxf(elapsed, 0.0) * chars_per_second)), 0, total_chars)


static func can_choose(elapsed: float) -> bool:
	return elapsed >= ARM_DELAY


## Touche physique -> option (0..3), ou -1. Rangée du haut (AZERTY comme QWERTY) et pavé numérique.
static func key_to_option(physical_keycode: int, option_count: int) -> int:
	var i := OPTION_KEYS.find(physical_keycode)
	if i < 0:
		i = OPTION_KEYS_KP.find(physical_keycode)
	return i if i >= 0 and i < option_count else -1
