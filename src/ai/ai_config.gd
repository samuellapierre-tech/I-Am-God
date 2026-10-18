extends RefCounted
## Réglages de l'IA locale, persistés dans user://ai_settings.cfg (ConfigFile).
## Toutes les valeurs ont un défaut sûr : le jeu fonctionne sans fichier ni serveur LLM.

const DEFAULT_PATH := "user://ai_settings.cfg"

## Backends reconnus. "auto" = détection au démarrage (Ollama puis llama.cpp), "off" = repli procédural seul.
const BACKENDS := ["auto", "ollama", "llamacpp", "off"]

## section/clé -> valeur par défaut. Le type de la valeur par défaut fait foi lors du chargement.
const DEFAULTS := {
	"llm": {
		"backend": "auto",
		"ollama_url": "http://127.0.0.1:11434",
		"llamacpp_url": "http://127.0.0.1:8080",
		"model": "llama3.2:3b",
		"temperature": 0.8,
		"timeout_sec": 20.0,
		## Couches déchargées sur le GPU (Ollama « num_gpu »). -1 = laisser Ollama décider, 999 = tout sur GPU.
		"num_gpu": -1,
		## Durée de maintien du modèle en VRAM entre deux requêtes (Ollama « keep_alive »).
		"keep_alive": "10m",
		"num_ctx": 2048,
		"max_tokens": 160,
		## Requêtes simultanées vers le serveur : 1 suffit sur un GPU grand public.
		"max_concurrent": 1,
		## Au-delà, les requêtes les plus anciennes sont abandonnées (repli procédural).
		"max_queue": 8,
	},
	"narrator": {
		"enabled": true,
		## Délai minimal entre deux narrations automatiques (secondes réelles).
		"min_interval_sec": 6.0,
		## Nombre maximal d'événements résumés dans une seule narration.
		"max_batch": 5,
		## Importance minimale (0..1) pour qu'un événement de la simulation soit raconté.
		"min_importance": 0.4,
	},
}

var path := DEFAULT_PATH
var _values := {}


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path
	reset_to_defaults()


func reset_to_defaults() -> void:
	_values = DEFAULTS.duplicate(true)


func get_value(section: String, key: String) -> Variant:
	if _values.has(section) and _values[section].has(key):
		return _values[section][key]
	return null


## Affecte une valeur connue en la convertissant au type du défaut. Renvoie false si la clé est inconnue.
func set_value(section: String, key: String, value: Variant) -> bool:
	if not (DEFAULTS.has(section) and DEFAULTS[section].has(key)):
		return false
	_values[section][key] = _sanitize(section, key, value)
	return true


## Charge le fichier ; une clé absente ou invalide garde sa valeur par défaut.
## Renvoie OK, ou ERR_FILE_NOT_FOUND si le fichier n'existe pas encore (ce n'est pas une erreur de jeu).
func load_config() -> Error:
	reset_to_defaults()
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var cfg := ConfigFile.new()
	var err := cfg.load(path)
	if err != OK:
		return err
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			if cfg.has_section_key(section, key):
				_values[section][key] = _sanitize(section, key, cfg.get_value(section, key))
	return OK


func save_config() -> Error:
	var cfg := ConfigFile.new()
	for section in _values:
		for key in _values[section]:
			cfg.set_value(section, key, _values[section][key])
	return cfg.save(path)


## Charge, et crée le fichier avec les défauts s'il n'existe pas (pour que le joueur puisse l'éditer).
func load_or_create() -> void:
	if load_config() == ERR_FILE_NOT_FOUND:
		save_config()


func _sanitize(section: String, key: String, value: Variant) -> Variant:
	var def: Variant = DEFAULTS[section][key]
	var out: Variant = def
	match typeof(def):
		TYPE_BOOL:
			if typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT]:
				out = bool(value)
		TYPE_INT:
			if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
				out = int(value)
			elif typeof(value) == TYPE_STRING and String(value).is_valid_int():
				out = String(value).to_int()
		TYPE_FLOAT:
			if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
				out = float(value)
			elif typeof(value) == TYPE_STRING and String(value).is_valid_float():
				out = String(value).to_float()
		TYPE_STRING:
			if typeof(value) in [TYPE_STRING, TYPE_STRING_NAME]:
				out = String(value).strip_edges()
	# Bornes de sécurité.
	match key:
		"backend":
			if not (out in BACKENDS):
				out = def
		"temperature":
			out = clampf(out, 0.0, 2.0)
		"timeout_sec":
			out = clampf(out, 1.0, 300.0)
		"max_concurrent":
			out = clampi(out, 1, 8)
		"max_queue":
			out = clampi(out, 1, 64)
		"num_ctx":
			out = clampi(out, 256, 131072)
		"max_tokens":
			out = clampi(out, 16, 4096)
		"min_interval_sec":
			out = clampf(out, 0.0, 600.0)
		"max_batch":
			out = clampi(out, 1, 32)
		"min_importance":
			out = clampf(out, 0.0, 1.0)
		"model", "ollama_url", "llamacpp_url", "keep_alive":
			if String(out) == "":
				out = def
	if key.ends_with("_url"):
		out = String(out).trim_suffix("/")
	return out


# Raccourcis lisibles.
func backend() -> String: return get_value("llm", "backend")
func model() -> String: return get_value("llm", "model")
func ollama_url() -> String: return get_value("llm", "ollama_url")
func llamacpp_url() -> String: return get_value("llm", "llamacpp_url")
func temperature() -> float: return get_value("llm", "temperature")
func timeout_sec() -> float: return get_value("llm", "timeout_sec")
