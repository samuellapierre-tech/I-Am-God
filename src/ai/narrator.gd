extends Node
## Autoload « Narrator » : le Chroniqueur des dieux.
## Contrat : narrate(context) émet narration_ready(text) de façon asynchrone.
##
## - Écoute GameState (événements, changements d'ère, actions divines), regroupe et limite le débit
##   des événements importants, puis raconte en 1 à 3 phrases.
## - Utilise un LLM local (Ollama / llama.cpp, accéléré GPU) s'il est disponible,
##   sinon un narrateur procédural : le jeu reste entièrement jouable sans IA.
## - Oracle (ask_oracle), Prières (generate_prayer) et décisions de civilisation (suggest_civilization_decision).

signal narration_ready(text: String)
signal oracle_answered(text: String)
signal prayer_received(species_id: int, text: String)
signal decision_ready(species_id: int, decision: Dictionary)
## "ollama", "llamacpp" ou "none" (repli procédural).
signal backend_changed(backend: String)

const AiConfig := preload("res://src/ai/ai_config.gd")
const LlmClient := preload("res://src/ai/llm_client.gd")
const Procedural := preload("res://src/ai/procedural_narrator.gd")
const Prompts := preload("res://src/ai/prompt_builder.gd")
const DecisionSchema := preload("res://src/ai/decision_schema.gd")

## Importance (0..1) par type d'événement canonique ; une clé "importance" dans l'événement l'emporte.
const EVENT_IMPORTANCE := {
	"meteor": 1.0, "uplift": 1.0, "era_change": 1.0, "extinct": 0.9, "ice_age": 0.9,
	"extinction": 0.8, "save": 0.8, "plague": 0.8, "flood": 0.8, "spawn_species": 0.8,
	"civilization": 0.7, "disaster": 0.7, "bless": 0.6, "war": 0.6, "discovery": 0.6,
	"speciation": 0.5, "climate": 0.5, "migration": 0.3, "generic": 0.3,
}
## Délai minimal après un geste divin avant de le raconter (laisse arriver ses conséquences).
const DIVINE_DELAY := 0.4

var config: AiConfig
var client: LlmClient
var procedural: Procedural
## Narration automatique des événements de GameState (désactivable par l'UI).
var auto_narrate := true

var _pending: Array[Dictionary] = []
var _absorbed_ids := {}
var _cooldown := 0.0
var _auto_in_flight := false
var _last_era := ""
var _game_state: Node


func _ready() -> void:
	config = AiConfig.new()
	config.load_or_create()
	procedural = Procedural.new()
	client = LlmClient.new()
	client.name = "LlmClient"
	add_child(client)
	client.setup(config)
	client.backend_changed.connect(func(b: String) -> void: backend_changed.emit(b))
	client.detect_backend()
	auto_narrate = config.get_value("narrator", "enabled")
	_connect_game_state.call_deferred()


# ---------------------------------------------------------------------------
# API publique
# ---------------------------------------------------------------------------

## Raconte un contexte : {type, era, year, summary, species_name|species_id, events: Array, action: Dictionary}.
## Émet narration_ready(text) plus tard (jamais pendant l'appel).
func narrate(context: Dictionary) -> void:
	var ctx := context.duplicate()
	var action: Variant = ctx.get("action", null)
	if action is Dictionary:
		if not ctx.has("type"):
			ctx["type"] = str(action.get("type", "generic"))
		if not ctx.has("species_id"):
			ctx["species_id"] = action.get("species_id", -1)
	if not ctx.has("species_name"):
		var name := _species_name_for(ctx.get("species_id", -1))
		if name != "":
			ctx["species_name"] = name
	_request_narration(ctx, false)


## Oracle « et si ? » : transforme le résumé de WorldSim.project_future() en prophétie. Émet oracle_answered.
func ask_oracle(question: String, projection: Dictionary) -> void:
	_ask(
		Prompts.PERSONA_ORACLE, Prompts.build_oracle_prompt(question, projection),
		func() -> String: return procedural.prophecy(question, projection),
		func(text: String) -> void: oracle_answered.emit(text), 3)


## Prière d'une espèce sapiente. species : {id, name, traits, population} ; situation : {type, era, enemy, summary, region}.
## Émet prayer_received(species_id, text). Les choix proposés au joueur : get_prayer_choices().
func generate_prayer(species: Dictionary, situation: Dictionary) -> void:
	var sit := situation.duplicate()
	if not sit.has("era"):
		sit["era"] = _current_era()
	var sid := int(species.get("id", sit.get("species_id", -1)))
	_ask(
		Prompts.PERSONA_PRIERE, Prompts.build_prayer_prompt(species, sit),
		func() -> String: return procedural.prayer(species, sit),
		func(text: String) -> void: prayer_received.emit(sid, text), 3)


## Choix moraux associés à une prière : [{label: String, action: Dictionary}] ({} = ne rien faire).
func get_prayer_choices(species: Dictionary, situation: Dictionary) -> Array:
	return Procedural.prayer_choices(species, situation)


## Crochet pour de futures décisions de civilisation pilotées par l'IA.
## Renvoie immédiatement la décision heuristique {action, target, reason, source} ; si un LLM est disponible,
## émet ensuite decision_ready(species_id, décision validée) (ou l'heuristique si la réponse est invalide).
func suggest_civilization_decision(context: Dictionary) -> Dictionary:
	var heuristic := DecisionSchema.fallback(context)
	heuristic["source"] = "heuristic"
	var sid := int(context.get("species_id", -1))
	if client != null and client.is_available():
		var on_reply := func(ok: bool, raw: String) -> void:
			decision_ready.emit(sid, DecisionSchema.decide(raw if ok else "", context))
		client.request(Prompts.PERSONA_DECISION, Prompts.build_decision_prompt(context), on_reply,
			{"json": true, "max_tokens": 120, "temperature": 0.4})
	else:
		decision_ready.emit.call_deferred(sid, heuristic.duplicate())
	return heuristic


func is_ai_available() -> bool:
	return client != null and client.is_available()


func get_backend() -> String:
	return client.backend if client != null else LlmClient.BACKEND_NONE


## Recharge user://ai_settings.cfg et relance la détection (après modification des options).
func reload_config() -> void:
	config.load_config()
	client.cancel_all()
	client.setup(config)
	auto_narrate = config.get_value("narrator", "enabled")
	client.detect_backend()


# ---------------------------------------------------------------------------
# Écoute de GameState (connexion défensive : la simulation peut ne pas exister encore)
# ---------------------------------------------------------------------------

func _connect_game_state() -> void:
	_game_state = get_node_or_null("/root/GameState")
	if _game_state == null:
		return
	var links := {
		"event_occurred": _on_event_occurred,
		"era_changed": _on_era_changed,
		"divine_action_applied": _on_divine_action_applied,
	}
	for sig in links:
		if _game_state.has_signal(sig) and not _game_state.is_connected(sig, links[sig]):
			_game_state.connect(sig, links[sig])
	# GameState a déjà émis la première ère avant notre connexion : on ouvre la chronique.
	var era := _current_era()
	if era != "":
		_on_era_changed(era)


func _on_event_occurred(event: Dictionary) -> void:
	if not auto_narrate:
		return
	if event.has("id") and _absorbed_ids.has(event["id"]):
		_absorbed_ids.erase(event["id"])
		return
	var importance := event_importance(event)
	if importance < float(config.get_value("narrator", "min_importance")):
		return
	_push(event, importance)


func _on_era_changed(era: String) -> void:
	if era == _last_era:
		return
	_last_era = era
	if auto_narrate:
		_push({"type": "era_change", "era": era, "year": _current_year()}, 1.0)


func _on_divine_action_applied(action: Dictionary, consequences: Array) -> void:
	if not auto_narrate:
		return
	# Les conséquences arrivent aussi via event_occurred : on les fond dans ce récit.
	var summaries := PackedStringArray()
	var target: Variant = action.get("species_id", -1)
	for c in consequences:
		if c is Dictionary:
			# La simulation choisit la cible réelle (espèce la plus proche) : on la préfère à celle demandée.
			if int(c.get("species_id", -1)) >= 0 and (typeof(target) != TYPE_INT or target < 0):
				target = int(c["species_id"])
			if c.has("id"):
				_absorbed_ids[c["id"]] = true
			if str(c.get("summary", "")) != "":
				summaries.append(str(c["summary"]))
	var event := {
		"type": str(action.get("type", "generic")), "year": _current_year(),
		"species_id": target, "region": action.get("region", Vector2i.ZERO),
		"summary": "; ".join(summaries.slice(0, 3)), "action": action,
	}
	_push(event, 1.1)  # le geste du joueur passe avant tout
	_cooldown = minf(_cooldown, DIVINE_DELAY)
	# Évite que l'ensemble grossisse indéfiniment si la simulation ne réémet pas certaines conséquences.
	if _absorbed_ids.size() > 256:
		_absorbed_ids.clear()


static func event_importance(event: Dictionary) -> float:
	var v: Variant = event.get("importance", null)
	if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
		return clampf(float(v), 0.0, 1.0)
	return EVENT_IMPORTANCE.get(Procedural.event_key(event.get("type", "generic")), 0.3)


func _push(event: Dictionary, importance: float) -> void:
	var e := event.duplicate()
	# Les événements de la simulation ne portent que species_id : on y joint le nom pour la narration.
	if not e.has("species_name"):
		var name := _species_name_for(e.get("species_id", -1))
		if name != "":
			e["species_name"] = name
	e["_importance"] = importance
	_pending.append(e)
	# Garde-fou mémoire : on ne conserve que les plus importants.
	if _pending.size() > 64:
		_sort_pending()
		_pending.resize(32)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _pending.is_empty() or _auto_in_flight or _cooldown > 0.0:
		return
	_flush()


func _flush() -> void:
	_sort_pending()
	var batch := _pending.slice(0, int(config.get_value("narrator", "max_batch")))
	_pending.clear()
	var context := {"era": _current_era(), "year": _current_year(), "events": []}
	for e in batch:
		var clean: Dictionary = e.duplicate()
		clean.erase("_importance")
		if clean.has("action") and not context.has("action"):
			context["action"] = clean["action"]
		clean.erase("action")
		context["events"].append(clean)
	if context["era"] == "":
		context["era"] = str(batch[0].get("era", ""))
	_request_narration(context, true)


func _sort_pending() -> void:
	_pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["_importance"] > b["_importance"])


func _current_era() -> String:
	if _game_state != null and "sim" in _game_state and _game_state.sim != null and _game_state.sim.has_method("current_era"):
		return str(_game_state.sim.current_era())
	return _last_era


func _species_name_for(id: Variant) -> String:
	if not (typeof(id) in [TYPE_INT, TYPE_FLOAT]) or int(id) < 0:
		return ""
	if _game_state == null or not ("sim" in _game_state) or _game_state.sim == null or not ("species" in _game_state.sim):
		return ""
	var sp: Variant = _game_state.sim.species.get(int(id), null)
	return str(sp.get("name", "")) if sp is Dictionary else ""


func _current_year() -> Variant:
	if _game_state != null and "sim" in _game_state and _game_state.sim != null and "year" in _game_state.sim:
		return float(_game_state.sim.year)
	return null


# ---------------------------------------------------------------------------
# Génération : LLM si possible, sinon procédural ; émission toujours asynchrone
# ---------------------------------------------------------------------------

func _request_narration(context: Dictionary, automatic: bool) -> void:
	if automatic:
		_auto_in_flight = true
		_cooldown = float(config.get_value("narrator", "min_interval_sec"))
	var on_text := func(text: String) -> void:
		if automatic:
			_auto_in_flight = false
		narration_ready.emit(text)
	_ask(
		Prompts.narration_system(), Prompts.build_narration_prompt(context),
		func() -> String: return procedural.narrate(context), on_text, 3, not automatic)


## Envoie au LLM ; en cas d'échec ou d'absence de serveur, utilise le générateur procédural.
func _ask(system: String, prompt: String, fallback: Callable, emit: Callable, max_sentences: int, priority: bool = true) -> void:
	if client == null or not (client.is_available() or client.detecting):
		_emit_deferred(emit, fallback.call())
		return
	var on_reply := func(ok: bool, text: String) -> void:
		var out: String = Prompts.sanitize_output(text, max_sentences) if ok else ""
		if out == "":
			out = fallback.call()
		emit.call(out)
	client.request(system, prompt, on_reply, {"priority": priority})


func _emit_deferred(emit: Callable, text: String) -> void:
	emit.call_deferred(text)
