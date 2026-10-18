extends Node
## Client LLM local, non bloquant : Ollama (primaire) ou serveur llama.cpp compatible OpenAI (secondaire).
## - Détection automatique au démarrage du backend disponible (sondes HTTP courtes).
## - File d'attente de requêtes, pool de nœuds HTTPRequest, délai d'expiration.
## - Aucune attente active : tout passe par des signaux, la frame n'est jamais bloquée.
## En cas d'échec, le rappel reçoit ok = false et l'appelant bascule sur le repli procédural.

signal backend_changed(backend: String)

const AiConfig := preload("res://src/ai/ai_config.gd")

const BACKEND_NONE := "none"
const BACKEND_OLLAMA := "ollama"
const BACKEND_LLAMACPP := "llamacpp"
const PROBE_TIMEOUT := 2.0
## Délai avant une nouvelle détection quand aucun serveur ne répond (le joueur a pu lancer Ollama entre-temps).
const REDETECT_DELAY := 30.0
## Échecs consécutifs avant de considérer le serveur comme tombé.
const MAX_FAIL_STREAK := 3

var config: AiConfig
## Backend actif : "ollama", "llamacpp" ou "none".
var backend := BACKEND_NONE
## Modèles annoncés par le serveur (Ollama /api/tags ou /v1/models).
var available_models := PackedStringArray()
var detecting := false

var _queue: Array[Dictionary] = []
var _idle: Array[HTTPRequest] = []
var _active := {}  # HTTPRequest -> job
var _probe: HTTPRequest
var _probe_order: Array[String] = []
var _next_id := 1
var _fail_streak := 0
var _last_detect_msec := -1


func setup(p_config: AiConfig) -> void:
	config = p_config
	for child in get_children():
		child.queue_free()
	_idle.clear()
	_active.clear()
	for i in int(config.get_value("llm", "max_concurrent")):
		var http := HTTPRequest.new()
		http.name = "Http%d" % i
		add_child(http)
		http.request_completed.connect(_on_request_completed.bind(http))
		_idle.append(http)
	_probe = HTTPRequest.new()
	_probe.name = "Probe"
	_probe.timeout = PROBE_TIMEOUT
	add_child(_probe)
	_probe.request_completed.connect(_on_probe_completed)


func is_available() -> bool:
	return backend != BACKEND_NONE


func is_busy() -> bool:
	return not _active.is_empty() or not _queue.is_empty()


func pending_count() -> int:
	return _queue.size() + _active.size()


## Lance la détection du backend (asynchrone). Émet backend_changed à la fin.
func detect_backend() -> void:
	if config == null or detecting:
		return
	_last_detect_msec = Time.get_ticks_msec()
	match config.backend():
		"off":
			_probe_order = []
		"ollama":
			_probe_order = [BACKEND_OLLAMA]
		"llamacpp":
			_probe_order = [BACKEND_LLAMACPP]
		_:
			_probe_order = [BACKEND_OLLAMA, BACKEND_LLAMACPP]
	detecting = true
	_probe_next()


## Envoie une requête de complétion de type chat.
## callback : Callable(ok: bool, text: String). options : {json: bool, max_tokens: int, temperature: float, priority: bool}
## Renvoie l'identifiant de la requête (0 si refusée immédiatement — le rappel est alors appelé en différé).
func request(system: String, prompt: String, callback: Callable, options: Dictionary = {}) -> int:
	if config == null or config.backend() == "off":
		_fail_deferred(callback, "IA désactivée")
		return 0
	if not is_available() and not detecting:
		if _last_detect_msec < 0 or Time.get_ticks_msec() - _last_detect_msec > REDETECT_DELAY * 1000.0:
			detect_backend()
		if not detecting:
			_fail_deferred(callback, "aucun serveur LLM")
			return 0
	var job := {"id": _next_id, "system": system, "prompt": prompt, "callback": callback, "options": options}
	_next_id += 1
	if options.get("priority", false):
		# Requêtes du joueur (Oracle, prières) : avant les narrations automatiques, dans l'ordre d'arrivée.
		var at := 0
		while at < _queue.size() and _queue[at]["options"].get("priority", false):
			at += 1
		_queue.insert(at, job)
	else:
		_queue.push_back(job)
	# File pleine : on abandonne les plus anciennes requêtes non prioritaires (repli procédural).
	while _queue.size() > int(config.get_value("llm", "max_queue")):
		var idx := 0
		for i in _queue.size():
			if not _queue[i]["options"].get("priority", false):
				idx = i
				break
		var dropped: Dictionary = _queue.pop_at(idx)
		_fail_deferred(dropped["callback"], "file d'attente pleine")
	_pump()
	return job["id"]


## Annule tout (ex. changement de partie). Les rappels reçoivent ok = false.
func cancel_all() -> void:
	for job in _queue:
		_fail_deferred(job["callback"], "annulé")
	_queue.clear()
	for http in _active.keys():
		http.cancel_request()
		_fail_deferred(_active[http]["callback"], "annulé")
		_idle.append(http)
	_active.clear()


# ---------------------------------------------------------------------------
# Construction des requêtes (publiques pour les tests)
# ---------------------------------------------------------------------------

func endpoint_for(p_backend: String) -> String:
	if p_backend == BACKEND_OLLAMA:
		return config.ollama_url() + "/api/chat"
	return config.llamacpp_url() + "/v1/chat/completions"


func build_body(p_backend: String, system: String, prompt: String, options: Dictionary = {}) -> Dictionary:
	var messages := [{"role": "system", "content": system}, {"role": "user", "content": prompt}]
	var temperature: float = options.get("temperature", config.temperature())
	var max_tokens: int = options.get("max_tokens", config.get_value("llm", "max_tokens"))
	if p_backend == BACKEND_OLLAMA:
		var opts := {"temperature": temperature, "num_predict": max_tokens, "num_ctx": config.get_value("llm", "num_ctx")}
		var num_gpu: int = config.get_value("llm", "num_gpu")
		if num_gpu >= 0:
			opts["num_gpu"] = num_gpu
		var body := {
			"model": config.model(), "messages": messages, "stream": false,
			"keep_alive": config.get_value("llm", "keep_alive"), "options": opts,
		}
		if options.get("json", false):
			body["format"] = "json"
		return body
	var body := {
		"model": config.model(), "messages": messages, "stream": false,
		"temperature": temperature, "max_tokens": max_tokens,
	}
	if options.get("json", false):
		body["response_format"] = {"type": "json_object"}
	return body


## Extrait le texte d'une réponse JSON du serveur ("" si format inattendu).
static func extract_text(p_backend: String, data: Variant) -> String:
	if not (data is Dictionary):
		return ""
	if p_backend == BACKEND_OLLAMA:
		var msg: Variant = data.get("message", null)
		if msg is Dictionary:
			return str(msg.get("content", ""))
		return str(data.get("response", ""))  # /api/generate
	var choices: Variant = data.get("choices", null)
	if choices is Array and not choices.is_empty() and choices[0] is Dictionary:
		var m: Variant = choices[0].get("message", null)
		if m is Dictionary:
			return str(m.get("content", ""))
		return str(choices[0].get("text", ""))
	return ""


# ---------------------------------------------------------------------------
# Interne : détection
# ---------------------------------------------------------------------------

func _probe_next() -> void:
	if _probe_order.is_empty():
		_finish_detection(BACKEND_NONE)
		return
	var candidate: String = _probe_order[0]
	var url := config.ollama_url() + "/api/tags" if candidate == BACKEND_OLLAMA else config.llamacpp_url() + "/v1/models"
	if _probe.request(url) != OK:
		_probe_order.pop_front()
		_probe_next.call_deferred()


func _on_probe_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var candidate: String = _probe_order.pop_front() if not _probe_order.is_empty() else BACKEND_NONE
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		available_models.clear()
		var data: Variant = JSON.parse_string(body.get_string_from_utf8())
		if data is Dictionary:
			var list: Variant = data.get("models", data.get("data", []))
			if list is Array:
				for m in list:
					if m is Dictionary:
						available_models.append(str(m.get("name", m.get("id", ""))))
		_finish_detection(candidate)
	else:
		_probe_next()


func _finish_detection(found: String) -> void:
	detecting = false
	_probe_order.clear()
	var changed := found != backend
	backend = found
	_fail_streak = 0
	if found == BACKEND_NONE:
		_fail_queue("aucun serveur LLM")
	else:
		print("[IA] Backend local détecté : %s (modèle « %s »)." % [found, config.model()])
		if found == BACKEND_OLLAMA and not available_models.is_empty() and not _has_model(config.model()):
			print("[IA] Le modèle « %s » n'est pas installé. Lancez : ollama pull %s" % [config.model(), config.model()])
	if changed:
		backend_changed.emit(backend)
	_pump()


func _has_model(model: String) -> bool:
	for m in available_models:
		if m == model or m == model + ":latest" or m.trim_suffix(":latest") == model:
			return true
	return false


# ---------------------------------------------------------------------------
# Interne : file d'attente
# ---------------------------------------------------------------------------

func _pump() -> void:
	if detecting or not is_available():
		return
	while not _queue.is_empty() and not _idle.is_empty():
		var job: Dictionary = _queue.pop_front()
		var http: HTTPRequest = _idle.pop_back()
		http.timeout = config.timeout_sec()
		job["backend"] = backend
		var body := JSON.stringify(build_body(backend, job["system"], job["prompt"], job["options"]))
		var err := http.request(endpoint_for(backend), ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
		if err != OK:
			_idle.append(http)
			_fail_deferred(job["callback"], "requête impossible (%d)" % err)
			continue
		_active[http] = job


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	var job: Dictionary = _active.get(http, {})
	_active.erase(http)
	_idle.append(http)
	if job.is_empty():
		_pump()
		return
	var text := ""
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		text = extract_text(job["backend"], JSON.parse_string(body.get_string_from_utf8())).strip_edges()
	if text != "":
		_fail_streak = 0
		job["callback"].call(true, text)
	else:
		_fail_streak += 1
		if result in [HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR] or _fail_streak >= MAX_FAIL_STREAK:
			# Le serveur a disparu (ou répond mal) : on repasse en mode hors-ligne, nouvelle détection plus tard.
			if backend != BACKEND_NONE:
				backend = BACKEND_NONE
				_last_detect_msec = Time.get_ticks_msec()
				_fail_queue("serveur LLM injoignable")
				backend_changed.emit(backend)
		job["callback"].call(false, "échec HTTP (résultat %d, code %d)" % [result, code])
	_pump()


## Toutes les requêtes en attente basculent sur le repli.
func _fail_queue(reason: String) -> void:
	for job in _queue:
		_fail_deferred(job["callback"], reason)
	_queue.clear()


func _fail_deferred(callback: Callable, reason: String) -> void:
	if callback.is_valid():
		callback.call_deferred(false, reason)
