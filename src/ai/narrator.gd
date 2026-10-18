extends Node
## Autoload « Narrator » : le Chroniqueur des dieux.
## Contrat : narrate(context) émet narration_ready(text) de façon asynchrone.
##
## - Écoute GameState (événements, changements d'ère, actions divines), regroupe et limite le débit
##   des événements importants, puis raconte en 1 à 3 phrases.
## - Utilise un LLM local (Ollama / llama.cpp, accéléré GPU) s'il est disponible,
##   sinon un narrateur procédural : le jeu reste entièrement jouable sans IA.
## - Oracle (ask_oracle), Prières (generate_prayer) et décisions de civilisation (suggest_civilization_decision).
## - Chronique de la parcelle suivie (parcel_narrator.gd) : événements « parcel_* » et changements
##   marquants de GameState.parcel, au plus une fois toutes les parcel_min_interval_sec secondes ;
##   les grands moments mondiaux (importance >= WORLD_PRIORITY, gestes divins) passent avant.
## - Maître du jeu (game_master.gd) : de temps en temps, un dilemme (dilemma_ready) que l'interface
##   affiche ; resolve_dilemma(id, option) applique le choix. Le narrateur ne met jamais le jeu en pause.
## - Stratégie (strategy_narrator.gd) : manches, menaces, pistes et épilogue relayés par GameState
##   (round_started, threat_revealed, threat_resolved, tracks_changed, game_over), s'ils existent.
## - Adversaire (adversary.gd) : il prend la parole sur les signaux samael_move / samael_learned (et
##   en début de manche, quand une menace frappe ou est contrée) ; au plus un échange avec le narrateur
##   par manche.
## - Chaque ligne a un orateur : speech_ready(speaker, text), et meta.speaker dans chronicle_line.
## - Zéro anachronisme (epoch.gd) : prompts avec l'époque et la liste des interdits, sortie du LLM filtrée.
## - Fil continu (chronicle.gd) : sans événement depuis 8 à 15 s, une phrase d'ambiance sur la parcelle.
##   Chaque ligne du fil, quelle qu'elle soit, est émise par narration_ready ET chronicle_line.

signal narration_ready(text: String)
signal oracle_answered(text: String)
signal prayer_received(species_id: int, text: String)
signal decision_ready(species_id: int, decision: Dictionary)
## "ollama", "llamacpp" ou "none" (repli procédural).
signal backend_changed(backend: String)
## Émis EN PLUS de narration_ready pour une narration de la parcelle (l'UI peut la styler à part ;
## moment : {kind, type, importance, land_use, species_name…}). Ne pas afficher les deux.
signal parcel_narration_ready(text: String, moment: Dictionary)
## Chaque ligne du fil écrit (événement du monde, de la parcelle, ambiance, dilemme…), dans l'ordre.
## meta : {source: "world"|"parcel"|"ambient"|"dilemma"|"manual", kind, speaker, era, year, world_mode…}.
signal chronicle_line(text: String, meta: Dictionary)
## Qui parle : AiConfig.NARRATOR_NAME ou AiConfig.ADVERSARY_NAME. Émis pour CHAQUE ligne du fil, en plus de
## narration_ready (compatibilité, sans orateur) et de chronicle_line (meta.speaker contient le même nom).
signal speech_ready(speaker: String, text: String)
## Le narrateur pousse Dieu à choisir. dilemma : {id, title, text, options: [{label, hint, action}],
## timeout_s, speaker, trigger, species_id} (voir game_master.gd). Jamais deux à la fois.
signal dilemma_ready(dilemma: Dictionary)
## Le dilemme est tranché (par Dieu ou, timed_out, par le délai : « Ne rien faire »).
signal dilemma_closed(id: int, option_index: int, timed_out: bool)

const AiConfig := preload("res://src/ai/ai_config.gd")
const LlmClient := preload("res://src/ai/llm_client.gd")
const Procedural := preload("res://src/ai/procedural_narrator.gd")
const Prompts := preload("res://src/ai/prompt_builder.gd")
const DecisionSchema := preload("res://src/ai/decision_schema.gd")
const ParcelNarrator := preload("res://src/ai/parcel_narrator.gd")
const Chronicle := preload("res://src/ai/chronicle.gd")
const Divergence := preload("res://src/ai/divergence.gd")
const GameMaster := preload("res://src/ai/game_master.gd")
const StrategyNarrator := preload("res://src/ai/strategy_narrator.gd")
const FactBase := preload("res://src/ai/facts/fact_base.gd")
const Adversary := preload("res://src/ai/adversary.gd")
const Epoch := preload("res://src/ai/epoch.gd")

## Importance (0..1) par type d'événement canonique ; une clé "importance" dans l'événement l'emporte.
const EVENT_IMPORTANCE := {
	"meteor": 1.0, "uplift": 1.0, "era_change": 1.0, "extinct": 0.9, "ice_age": 0.9,
	"extinction": 0.8, "save": 0.8, "plague": 0.8, "flood": 0.8, "spawn_species": 0.8,
	"civilization": 0.7, "disaster": 0.7, "bless": 0.6, "war": 0.6, "discovery": 0.6,
	"speciation": 0.5, "climate": 0.5, "migration": 0.3, "generic": 0.3,
}
## Délai minimal après un geste divin avant de le raconter (laisse arriver ses conséquences).
const DIVINE_DELAY := 0.4
## Un événement mondial au moins aussi important passe toujours, et aussitôt, avant la parcelle :
## changement d'ère, météore, éveil, gestes divins. Les extinctions et épidémies ordinaires de la
## simulation (0.8) sont trop fréquentes pour monopoliser le fil.
const WORLD_PRIORITY := 0.9
## Un moment de parcelle ordinaire non raconté au bout de ce délai (s) est oublié ; un moment rare
## (importance >= PARCEL_RARE) attend jusqu'à PARCEL_RARE_MAX_AGE.
const PARCEL_MAX_AGE := 40.0
const PARCEL_RARE := 0.75
const PARCEL_RARE_MAX_AGE := 120.0
const PARCEL_QUEUE_SIZE := 8
## Un événement compte comme « récent » pour le choix des faits pendant ce délai (s).
const RECENT_EVENT_SEC := 60.0
## Délai minimal (s) entre deux lignes de règles de la stratégie (manche, menaces, pistes).
const STORY_GAP := 2.0
## Lignes de règles (et répliques) en attente au plus.
const STORY_QUEUE_SIZE := 10
## Répliques de l'adversaire par manche, en plus de sa provocation d'ouverture.
const ADVERSARY_LINES_PER_ROUND := 4
## Types d'événements qui peuvent déclencher un dilemme (voir GameMaster.trigger_from_event).
const DILEMMA_EVENT_TYPES := ["sapience", "war", "discovery", "volcanism", "parcel_land_use", "parcel_heat", "parcel_cold"]

var config: AiConfig
var client: LlmClient
var procedural: Procedural
var parcel_narrator: ParcelNarrator
var chronicle: Chronicle
## Le monde suit-il l'histoire réelle ? (définitivement « divergent » une fois l'un des critères atteint)
var lens: Divergence
var game_master: GameMaster
## La voix de l'adversaire (il ne décide rien : src/strategy/ joue pour lui).
var adversary: Adversary
## Narration automatique des événements de GameState (désactivable par l'UI).
var auto_narrate := true
## Chronique automatique de la parcelle (désactivable séparément).
var auto_narrate_parcel := true

var _pending: Array[Dictionary] = []
var _absorbed_ids := {}
var _cooldown := 0.0
var _auto_in_flight := false
var _last_era := ""
var _game_state: Node
## Moments de parcelle en attente (avec "_t", leur heure d'arrivée en secondes).
var _parcel_pending: Array[Dictionary] = []
var _parcel_cooldown := 0.0
## Délai avant de raconter de nouveau un événement ordinaire du monde.
var _world_cooldown := 0.0
var _clock := 0.0
## Fil continu : temps écoulé depuis la dernière ligne, et délai avant la prochaine phrase d'ambiance.
var _since_line := 0.0
var _next_ambient := 10.0
var _ambient_rng := RandomNumberGenerator.new()
## Gestes divins déjà accomplis, du plus ancien au plus récent : [{type, year, species_id}].
var _divine_history: Array[Dictionary] = []
var _meteor_offered := false
## Étape datée de l'histoire (prologue…) où se trouve le monde, pour proposer son grand choix.
var _last_stage := ""
## Lignes de la stratégie prêtes à dire (règles : jamais réécrites par le LLM) : [{text, meta}].
var _story_pending: Array[Dictionary] = []
var _announced_threats := {}
var _tracks := {}
var _game_over := false
## Manche en cours, répliques de l'adversaire dans cette manche, et dernière manche avec un échange.
var _round_index := 0
var _adversary_lines := 0
var _exchange_round := -1
var _habits_said := {}
## Types des événements récents (bruts et canoniques) avec leur heure : [{type, t}].
var _recent_events: Array[Dictionary] = []


func _ready() -> void:
	config = AiConfig.new()
	config.load_or_create()
	procedural = Procedural.new()
	parcel_narrator = ParcelNarrator.new()
	chronicle = Chronicle.new()
	lens = Divergence.new()
	game_master = GameMaster.new()
	adversary = Adversary.new()
	_ambient_rng.randomize()
	client = LlmClient.new()
	client.name = "LlmClient"
	add_child(client)
	client.setup(config)
	client.backend_changed.connect(func(b: String) -> void: backend_changed.emit(b))
	client.detect_backend()
	_apply_narrator_config()
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


## Raconte tout de suite (sans file ni délai) un événement « parcel_* » ou l'état de la parcelle.
## event : format WorldSim ({type: "parcel_land_use"|"parcel_arrival"|…, species_id, summary}) ;
## {} = décrire la parcelle telle qu'elle est (moment « focus »). Émet narration_ready puis
## parcel_narration_ready, toujours de façon asynchrone. Rien n'est émis si l'événement est redondant.
func narrate_parcel(event: Dictionary = {}) -> void:
	var snap := ParcelNarrator.snapshot(_parcel())
	var moment: Dictionary
	if event.is_empty():
		moment = parcel_narrator.focus(snap)
	else:
		moment = parcel_narrator.on_event(_enrich_parcel_event(event), snap)
	if not moment.is_empty():
		_request_parcel_narration(moment, false)


## Tranche le dilemme `id` (dilemma_ready) : applique l'action de l'option via GameState.apply_divine_action
## (sauf « Ne rien faire »), raconte le choix et le mémorise pour la suite du récit.
func resolve_dilemma(id: int, option_index: int) -> void:
	_resolve_dilemma(id, option_index, false)


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
	if game_master != null:
		game_master.consider(GameMaster.trigger_from_prayer(species, sit, _gm_context()))
	_ask(
		Prompts.PERSONA_PRIERE, Prompts.build_prayer_prompt(species, sit),
		func() -> String: return procedural.prayer(species, sit),
		func(text: String) -> void: prayer_received.emit(sid, text), 3, true, _current_epoch())


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
	_apply_narrator_config()
	client.detect_backend()


func _apply_narrator_config() -> void:
	auto_narrate = config.get_value("narrator", "enabled")
	auto_narrate_parcel = config.get_value("narrator", "parcel_enabled")
	_next_ambient = _draw_ambient_delay()
	game_master.min_interval = config.get_value("narrator", "dilemma_min_interval_sec")
	game_master.timeout_s = config.get_value("narrator", "dilemma_timeout_sec")
	game_master.meteor_delay = config.get_value("narrator", "dilemma_first_delay_sec")
	parcel_narrator.heat_drift_c = config.get_value("narrator", "parcel_heat_drift_c")


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
		"parcel_updated": _on_parcel_updated,
		"parcel_changed": _on_parcel_changed,
		# Stratégie (src/strategy/) : ces signaux n'existent que si le module est fusionné.
		"round_started": _on_round_started,
		"threat_revealed": _on_threat_revealed,
		"threat_resolved": _on_threat_resolved,
		"tracks_changed": _on_tracks_changed,
		"game_over": _on_game_over,
		# Adversaire (src/strategy/) : ses coups et ce qu'il apprend de toi.
		"samael_move": _on_samael_move,
		"samael_learned": _on_samael_learned,
	}
	for sig in links:
		if _game_state.has_signal(sig) and not _game_state.is_connected(sig, links[sig]):
			_game_state.connect(sig, links[sig])
	# GameState a déjà émis la première ère avant notre connexion : on ouvre la chronique.
	var era := _current_era()
	if era != "":
		_on_era_changed(era)
	# La parcelle de départ sert de référence : on ne raconte que ce qui change ensuite.
	parcel_narrator.reset(ParcelNarrator.snapshot(_parcel()))


func _on_event_occurred(event: Dictionary) -> void:
	_note_event_type(str(event.get("type", "")))
	if str(event.get("type", "")).begins_with("parcel_"):
		_on_parcel_event(event)
		return
	if not auto_narrate:
		return
	if event.has("id") and _absorbed_ids.has(event["id"]):
		_absorbed_ids.erase(event["id"])
		return
	_consider_event(event)
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
	_note_event_type(str(action.get("type", "")))
	_divine_history.append({"type": str(action.get("type", "")), "year": _current_year(), "species_id": int(target) if typeof(target) in [TYPE_INT, TYPE_FLOAT] else -1})
	if _divine_history.size() > 64:
		_divine_history.pop_front()
	_push(event, 1.1)  # le geste du joueur passe avant tout
	_cooldown = minf(_cooldown, DIVINE_DELAY)
	# Évite que l'ensemble grossisse indéfiniment si la simulation ne réémet pas certaines conséquences.
	if _absorbed_ids.size() > 256:
		_absorbed_ids.clear()


# ---------------------------------------------------------------------------
# Chronique de la parcelle
# ---------------------------------------------------------------------------

func _on_parcel_event(event: Dictionary) -> void:
	# Même sans narration, le suivi reste à jour : rien ne déferle d'un coup à la réactivation.
	var moment := parcel_narrator.on_event(_enrich_parcel_event(event), ParcelNarrator.snapshot(_parcel()))
	if not moment.is_empty():
		_consider_event(moment)
	if auto_narrate and auto_narrate_parcel:
		_push_parcel(moment)


func _on_parcel_updated() -> void:
	for moment in parcel_narrator.observe(ParcelNarrator.snapshot(_parcel())):
		_consider_event(moment)
		if auto_narrate and auto_narrate_parcel:
			_push_parcel(moment)
	# Alertes de la parcelle (ParcelSim.alerts : [{kind, species_id, severity, summary}]).
	var p := _parcel()
	if p != null and "alerts" in p and p.get("alerts") is Array and not (p.get("alerts") as Array).is_empty():
		var ctx := _gm_context()
		for alert in p.get("alerts"):
			if alert is Dictionary:
				game_master.consider(GameMaster.trigger_from_alert(alert, ctx))


func _on_parcel_changed(_cell: Vector2i) -> void:
	var snap := ParcelNarrator.snapshot(_parcel())
	# Ce qui se passait sur l'ancienne parcelle n'a plus d'intérêt.
	_parcel_pending.clear()
	if not parcel_narrator.is_ready():
		parcel_narrator.reset(snap)
		return
	var moment := parcel_narrator.focus(snap)
	if auto_narrate and auto_narrate_parcel:
		_push_parcel(moment)


## Joint à un événement de parcelle le nom de l'espèce et sa survie dans le monde.
func _enrich_parcel_event(event: Dictionary) -> Dictionary:
	var e := event.duplicate()
	var sid: Variant = e.get("species_id", -1)
	if not e.has("species_name"):
		var name := _species_name_for(sid)
		if name != "":
			e["species_name"] = name
	if typeof(sid) in [TYPE_INT, TYPE_FLOAT] and int(sid) >= 0 and not e.has("species_alive"):
		var sp: Variant = _species_info(int(sid))
		if sp is Dictionary and sp.has("alive"):
			e["species_alive"] = bool(sp["alive"])
	return e


## File des moments de parcelle : seuil d'importance, annulations (arrivée puis départ de la même
## espèce), un seul état en attente par genre (usage du sol, chaleur…), taille bornée.
func _push_parcel(moment: Dictionary) -> void:
	if moment.is_empty():
		return
	_parcel_pending = queue_parcel_moment(_parcel_pending, moment, _clock,
		float(config.get_value("narrator", "parcel_min_importance")))


## Insère un moment dans une file de parcelle triée (fonction pure, testée sans GameState).
## Les annulations s'appliquent même si le moment est sous min_importance (un simple retour d'espèce
## annule le départ encore en attente), mais seul un moment assez important entre dans la file.
static func queue_parcel_moment(queue: Array[Dictionary], moment: Dictionary, now: float, min_importance := 0.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(queue)
	var kind := str(moment.get("kind", ""))
	var group := "temperature" if kind in ["heat", "cold"] else kind
	var sid := int(moment.get("species_id", -1))
	var importance := float(moment.get("importance", 0.0))
	for i in range(out.size() - 1, -1, -1):
		var p: Dictionary = out[i]
		var pk := str(p.get("kind", ""))
		var pgroup := "temperature" if pk in ["heat", "cold"] else pk
		if sid >= 0 and int(p.get("species_id", -1)) == sid and pk in ["arrival", "departure"] and kind in ["arrival", "departure"]:
			out.remove_at(i)
			if pk != kind:
				# L'espèce est venue puis repartie (ou l'inverse) avant d'être racontée : rien à dire.
				return out
		elif pgroup == group and group in ["land_use", "temperature", "focus"]:
			# Seul l'état le plus récent compte, sauf si l'ancien était plus rare (le cratère avant la repousse).
			if importance >= float(p.get("importance", 0.0)):
				out.remove_at(i)
	if importance < min_importance:
		return out
	var m := moment.duplicate()
	m["importance"] = importance
	m["_t"] = now
	out.append(m)
	# Le plus important d'abord ; à égalité, le plus récent.
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["importance"]) > float(b["importance"]) or (float(a["importance"]) == float(b["importance"]) and float(a["_t"]) > float(b["_t"])))
	if out.size() > PARCEL_QUEUE_SIZE:
		out.resize(PARCEL_QUEUE_SIZE)
	return out


## Oublie les moments trop anciens (les rares attendent plus longtemps).
static func expire_parcel_moments(queue: Array[Dictionary], now: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in queue:
		var max_age := PARCEL_RARE_MAX_AGE if float(m.get("importance", 0.0)) >= PARCEL_RARE else PARCEL_MAX_AGE
		if now - float(m.get("_t", now)) <= max_age:
			out.append(m)
	return out


## Faut-il raconter la parcelle maintenant plutôt que le monde ? Les grands moments mondiaux
## (importance >= WORLD_PRIORITY) passent avant ; sinon le plus rare des deux l'emporte.
## world_top / parcel_top : importance du premier de chaque file, -1 si elle est vide.
static func parcel_goes_first(world_top: float, parcel_top: float, parcel_ready: bool) -> bool:
	if parcel_top < 0.0 or not parcel_ready:
		return false
	if world_top < 0.0:
		return true
	return world_top < WORLD_PRIORITY and parcel_top > world_top


func _flush_parcel() -> void:
	var moment: Dictionary = _parcel_pending.pop_front()
	moment.erase("_t")
	_request_parcel_narration(moment, true)


func _request_parcel_narration(moment: Dictionary, automatic: bool) -> void:
	if automatic:
		_auto_in_flight = true
		_cooldown = float(config.get_value("narrator", "min_interval_sec"))
		_parcel_cooldown = float(config.get_value("narrator", "parcel_min_interval_sec"))
	var era := _current_era()
	var year: Variant = _current_year()
	var epoch := _current_epoch()
	var on_text := func(text: String) -> void:
		if automatic:
			_auto_in_flight = false
		_emit_line(text, {"source": "parcel", "kind": str(moment.get("kind", ""))})
		parcel_narration_ready.emit(text, moment)
	_ask(
		Prompts.parcel_system(), Prompts.build_parcel_prompt(moment, {"era": era, "year": year}),
		func() -> String: return parcel_narrator.narrate(moment, era, year, epoch), on_text, 2, not automatic, epoch)


# ---------------------------------------------------------------------------
# Fil continu
# ---------------------------------------------------------------------------

## Faut-il écrire une phrase d'ambiance maintenant ? (pure, testée sans GameState)
static func ambient_due(since_line: float, next_delay: float, enabled: bool, has_world: bool) -> bool:
	return enabled and has_world and since_line >= next_delay


func _draw_ambient_delay() -> float:
	var lo := float(config.get_value("narrator", "ambient_min_sec"))
	var hi := maxf(lo, float(config.get_value("narrator", "ambient_max_sec")))
	return _ambient_rng.randf_range(lo, hi)


## Contexte du fil : ère, date, parcelle, espèces, gestes divins, événements récents.
func world_context() -> Dictionary:
	var recent := []
	for e in _recent_events:
		if _clock - float(e["t"]) <= RECENT_EVENT_SEC:
			recent.append(e["type"])
	var ctx := _gm_context()
	ctx["recent_events"] = recent
	ctx["mode"] = lens.update(ctx)
	return ctx


## Contexte sans effet de bord (ni bascule réel/divergent) : ère, date, parcelle, espèces, gestes, choix.
func _gm_context() -> Dictionary:
	return {
		"era": _current_era(), "year": _current_year(), "snapshot": ParcelNarrator.snapshot(_parcel()),
		"species": _species_list(), "divine": _divine_history.duplicate(),
		"choices": game_master.choices.duplicate() if game_master != null else [],
	}


## Retient le type d'un événement (brut, canonique et sans préfixe parcel_) pour choisir des faits à propos.
func _note_event_type(t: String) -> void:
	if t == "":
		return
	for v in [t, t.trim_prefix("parcel_"), Procedural.event_key(t)]:
		_recent_events.append({"type": v, "t": _clock})
	while _recent_events.size() > 30:
		_recent_events.pop_front()


func _species_list() -> Array:
	var out := []
	if _game_state == null or not ("sim" in _game_state) or _game_state.sim == null or not ("species" in _game_state.sim):
		return out
	for id in _game_state.sim.species:
		var sp: Dictionary = _game_state.sim.species[id]
		var traits: Dictionary = sp.get("traits", {})
		out.append({
			"id": int(id), "name": str(sp.get("name", "")), "alive": bool(sp.get("alive", true)),
			"sapient": bool(sp.get("sapient", false)), "clade": str(traits.get("clade", sp.get("clade", ""))),
			"diet": str(traits.get("diet", "")), "size": float(traits.get("size", 0.3)),
			"intelligence": float(traits.get("intelligence", 0.0)), "aggression": float(traits.get("aggression", 0.5)),
			"tech_level": float(sp.get("tech_level", 0.0)), "parent": int(sp.get("parent", -1)),
		})
	return out


func _narrate_ambient() -> void:
	var ctx := world_context()
	var line := chronicle.ambient(ctx)
	if str(line.get("text", "")) == "":
		_since_line = 0.0
		return
	_auto_in_flight = true
	_cooldown = float(config.get_value("narrator", "min_interval_sec"))
	var on_text := func(text: String) -> void:
		_auto_in_flight = false
		var meta := {"source": "ambient", "kind": str(line.get("kind", ""))}
		for k in ["fact_id", "species_id", "world_mode", "scene"]:
			if line.has(k):
				meta[k] = line[k]
		_emit_line(text, meta)
	var fallback := func() -> String: return str(line["text"])
	var kind := str(line.get("kind", ""))
	var prompt := Prompts.build_invention_prompt(line, ctx) if kind in ["invention", "divergence"] else Prompts.build_ambient_prompt(line, ctx)
	_ask(Prompts.ambient_system(), prompt, fallback, on_text, 2, false, Epoch.current(ctx))
	if kind == "invention":
		_maybe_enrich(line, ctx)


## Un peuple inventé est enrichi une seule fois par le LLM (coutumes, croyance, fête), puis mémorisé.
func _maybe_enrich(line: Dictionary, ctx: Dictionary) -> void:
	var p: Variant = line.get("profile", null)
	if not (p is Dictionary) or not p.has("customs") or p.has("llm_requested") or not is_ai_available():
		return
	p["llm_requested"] = true
	var sid := int(p.get("id", -1))
	var on_reply := func(ok: bool, raw: String) -> void:
		if ok:
			chronicle.inventor.enrich_from_llm(sid, raw)
	client.request(Prompts.PERSONA_INVENTION, Prompts.build_enrich_prompt(p, ctx), on_reply,
		{"json": true, "max_tokens": 200, "temperature": 0.9})


## Toute ligne du fil passe par ici : compatibilité (narration_ready) + fil (chronicle_line).
func _emit_line(text: String, meta: Dictionary) -> void:
	var m := meta.duplicate()
	var speaker := str(meta.get("speaker", AiConfig.NARRATOR_NAME))
	m["speaker"] = speaker
	if not m.has("era"):
		m["era"] = _current_era()
	if not m.has("year"):
		m["year"] = _current_year()
	_since_line = 0.0
	_next_ambient = _draw_ambient_delay()
	narration_ready.emit(text)
	speech_ready.emit(speaker, text)
	chronicle_line.emit(text, m)


# ---------------------------------------------------------------------------
# Maître du jeu : dilemmes
# ---------------------------------------------------------------------------

func _consider_event(event: Dictionary) -> void:
	if game_master == null or not bool(config.get_value("narrator", "dilemma_enabled")):
		return
	# Filtre bon marché avant de construire le contexte (la simulation émet beaucoup d'événements).
	var t := str(event.get("type", ""))
	if not t in DILEMMA_EVENT_TYPES or (t == "discovery" and not str(event.get("summary", "")).contains("IA ")):
		return
	var trig := GameMaster.trigger_from_event(event, _gm_context())
	if not trig.is_empty():
		game_master.consider(trig)


func _tick_game_master(delta: float) -> void:
	if game_master == null or _game_state == null or _game_over or not bool(config.get_value("narrator", "dilemma_enabled")):
		return
	# Entrée dans une étape du prologue : son grand choix (docs/STRATEGIE.md §1).
	var stage := FactBase.stage_for(_current_era(), _current_year())
	if stage != _last_stage:
		_last_stage = stage
		game_master.consider(GameMaster.stage_trigger(stage, _gm_context()))
	if not _meteor_offered and _clock >= game_master.meteor_delay:
		var ctx := _gm_context()
		if GameMaster.meteor_due(ctx, _clock, game_master.meteor_delay):
			game_master.consider(GameMaster.meteor_trigger(ctx))
		_meteor_offered = true
	var r := game_master.tick(delta)
	if r.has("timeout"):
		_resolve_dilemma(int(r["timeout"]["id"]), int(r["timeout"]["option_index"]), true)
	elif r.has("open"):
		_open_dilemma(r["open"])


func _open_dilemma(trigger: Dictionary) -> void:
	var ctx := _gm_context()
	var d := game_master.open_dilemma(trigger, ctx)
	if d.is_empty():
		return
	if not is_ai_available():
		_show_dilemma.call_deferred(d)
		return
	# Le LLM ne rédige que titre, texte, libellés et indices ; options et actions restent celles des règles.
	var on_reply := func(ok: bool, raw: String) -> void:
		_show_dilemma(Prompts.merge_dilemma_text(d, raw, int(d.get("epoch", -1))) if ok else d)
	client.request(Prompts.dilemma_system(), Prompts.build_dilemma_prompt(d, ctx) + "\n" + Prompts.epoch_rules(int(d.get("epoch", -1))), on_reply,
		{"json": true, "max_tokens": 400, "temperature": 0.8, "priority": true})


func _show_dilemma(d: Dictionary) -> void:
	game_master.mark_shown(int(d["id"]))
	dilemma_ready.emit(d)
	_emit_line(str(d["text"]), {"source": "dilemma", "kind": str(d.get("trigger", "")), "dilemma_id": int(d["id"])})


func _resolve_dilemma(id: int, option_index: int, timed_out: bool) -> void:
	var d := game_master.active
	if d.is_empty() or int(d["id"]) != id or option_index < 0 or option_index >= (d["options"] as Array).size():
		return
	# Répondre à un dilemme coûte une action de la manche (STRATEGIE.md §2) : sans budget, rien ne se fait.
	var strategy := _strategy()
	var no_budget := false
	if not (d["options"][option_index]["action"] as Dictionary).is_empty() and strategy != null \
			and strategy.has_method("can_act") and not strategy.can_act():
		no_budget = true
		option_index = GameMaster.nothing_index(d)
	var r := game_master.resolve(id, option_index, timed_out, _gm_context())
	if not bool(r.get("ok", false)):
		return
	var text := str(r["text"])
	if no_budget:
		text = "Tu n'as plus d'action dans cette manche : ton geste reste suspendu, et le monde suit sa pente."
	_emit_line(text, {"source": "dilemma", "kind": "choice", "dilemma_id": id, "timed_out": timed_out, "no_budget": no_budget})
	var action: Dictionary = r["action"]
	if not action.is_empty() and _game_state != null and _game_state.has_method("apply_divine_action"):
		if strategy != null and strategy.has_method("spend_action"):
			# Le pouvoir choisi est une action comme une autre : il peut contrer une menace en attente.
			strategy.spend_action(str(action.get("type", "dilemma")))
		_game_state.apply_divine_action(action)
	dilemma_closed.emit(id, option_index, timed_out)


# ---------------------------------------------------------------------------
# Stratégie : le narrateur raconte les règles (manches, menaces, pistes, fin)
# ---------------------------------------------------------------------------

func _strategy() -> Object:
	if _game_state != null and "strategy" in _game_state:
		return _game_state.strategy
	return null


func _push_story(text: String, kind: String, extra: Dictionary = {}) -> void:
	if text == "":
		return
	# Deux cartes identiques qui frappent ensemble : une seule ligne.
	for s in _story_pending:
		if str(s["text"]) == text:
			return
	var meta := {"source": "strategy", "kind": kind}
	meta.merge(extra, true)
	_story_pending.append({"text": text, "meta": meta})
	_trim_story()


## File des règles trop longue : on oublie d'abord les lignes secondaires, jamais l'annonce de manche.
func _trim_story() -> void:
	while _story_pending.size() > STORY_QUEUE_SIZE:
		var dropped := false
		for i in _story_pending.size():
			if str(_story_pending[i]["meta"].get("kind", "")) != "round":
				_story_pending.remove_at(i)
				dropped = true
				break
		if not dropped:
			_story_pending.pop_front()


func _on_round_started(rd: Dictionary) -> void:
	var actions := -1
	var strategy := _strategy()
	if strategy != null and "actions_per_round" in strategy:
		actions = int(strategy.actions_per_round)
	for t in rd.get("threats", []):
		if t is Dictionary and t.has("id"):
			_announced_threats[t["id"]] = true
	_push_story(StrategyNarrator.round_line(rd, actions), "round", {"round": int(rd.get("index", 0))})
	_round_index = int(rd.get("index", _round_index + 1))
	_adversary_lines = 0
	_habits_said = {}
	# L'adversaire provoque en début de manche ; parfois, le narrateur lui répond (un échange par manche).
	var epoch := _current_epoch()
	if _exchange_round != _round_index and adversary.wants_exchange(_round_index):
		_exchange_round = _round_index
		if _round_index % 2 == 1:
			# L'adversaire répond directement à l'annonce du narrateur.
			_push_adversary(adversary.exchange_line(true, epoch), epoch, true)
		else:
			_push_adversary(adversary.round_taunt(rd, actions, epoch), epoch, true)
			_push_adversary(adversary.exchange_line(false, epoch), epoch, true)
	else:
		_push_adversary(adversary.round_taunt(rd, actions, epoch), epoch, true)


func _on_threat_revealed(threat: Dictionary) -> void:
	if threat.has("id") and _announced_threats.has(threat["id"]):
		return
	if threat.has("id"):
		_announced_threats[threat["id"]] = true
	_push_story(StrategyNarrator.threat_line(threat, _current_year()), "threat", {"threat_id": threat.get("id", -1)})


func _on_threat_resolved(threat: Dictionary, countered: bool) -> void:
	var target: Variant = threat.get("target", {})
	var sid := int(target.get("species_id", -1)) if target is Dictionary else -1
	_push_story(StrategyNarrator.resolved_line(threat, countered, _species_name_for(sid)), "threat_countered" if countered else "threat_struck",
		{"threat_id": threat.get("id", -1)})
	var epoch := _current_epoch()
	if countered:
		_push_adversary(adversary.spite_line(threat, epoch), epoch)
	elif _game_state == null or not _game_state.has_signal("samael_move"):
		# Sans coups de la stratégie pour le dire, l'adversaire savoure quand même.
		_push_adversary(adversary.strike_line(threat, epoch), epoch)


## Un coup de l'adversaire (samael_move) : {kind: "reveal"|"strike"|"taunt_hook", threat, reason_code}.
func _on_samael_move(move: Dictionary) -> void:
	var epoch := _current_epoch()
	var kind := str(move.get("kind", ""))
	# Les révélations ordinaires sont déjà dans l'annonce de manche : il ne parle que si le coup a une raison à dire.
	if kind == "reveal" and str(move.get("reason_code", "")) in ["", "random", "max_damage"]:
		return
	_push_adversary(adversary.move_line(move, epoch), epoch)


## L'adversaire a remarqué une habitude du joueur (samael_learned) : {power|counter|kind, count?}.
func _on_samael_learned(habit: Dictionary) -> void:
	var power := str(habit.get("power", habit.get("counter", habit.get("kind", ""))))
	if _habits_said.has(power):
		return
	_habits_said[power] = true
	var epoch := _current_epoch()
	_push_adversary(adversary.habit_line(habit, epoch), epoch)


## Une réplique de l'adversaire (ou du narrateur dans un échange) dans la file des règles.
## Au plus ADVERSARY_LINES_PER_ROUND répliques par manche, hors annonce : pas de spam.
func _push_adversary(line: Dictionary, epoch: int, always := false) -> void:
	if line.is_empty() or (not always and _adversary_lines >= ADVERSARY_LINES_PER_ROUND):
		return
	if not always:
		_adversary_lines += 1
	var l := line.duplicate()
	l["epoch"] = epoch
	var speaker := str(line.get("speaker", AiConfig.ADVERSARY_NAME))
	_story_pending.append({"text": str(line["text"]), "adversary": l,
		"meta": {"source": "adversary" if speaker == AiConfig.ADVERSARY_NAME else "exchange", "kind": str(line.get("kind", "")),
			"speaker": speaker, "reason": str(line.get("reason", ""))}})
	_trim_story()


func _on_tracks_changed(tracks: Dictionary) -> void:
	# Le premier relevé sert de référence : il n'y a encore rien à commenter.
	if _tracks.is_empty():
		_tracks = tracks.duplicate(true)
		return
	for line in StrategyNarrator.tracks_lines(_tracks, tracks):
		_push_story(str(line), "tracks")
	_tracks = tracks.duplicate(true)


func _on_game_over(victory: bool, reason: String) -> void:
	var memory := ""
	for i in range(game_master.choices.size() - 1, -1, -1):
		if not bool(game_master.choices[i].get("timed_out", false)):
			memory = GameMaster.memory_line(game_master.choices[i])
			break
	_game_over = true
	_story_pending.clear()
	_pending.clear()
	_parcel_pending.clear()
	# L'épilogue passe tout de suite, avant toute autre ligne.
	_emit_line(StrategyNarrator.epilogue(victory, reason, memory), {"source": "strategy", "kind": "epilogue", "victory": victory})


func _parcel() -> Object:
	if _game_state != null and "parcel" in _game_state:
		return _game_state.parcel
	return null


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
	_clock += delta
	_since_line += delta
	_tick_game_master(delta)
	_cooldown = maxf(_cooldown - delta, 0.0)
	_parcel_cooldown = maxf(_parcel_cooldown - delta, 0.0)
	_world_cooldown = maxf(_world_cooldown - delta, 0.0)
	# Les règles d'abord (manche, menaces, pistes), à leur propre rythme, plus serré que le reste.
	if not _story_pending.is_empty() and not _auto_in_flight and _since_line >= STORY_GAP:
		var s: Dictionary = _story_pending.pop_front()
		_cooldown = maxf(_cooldown, STORY_GAP)
		if s.has("adversary") and is_ai_available():
			# Le LLM ne fait que reformuler la réplique procédurale (et retombe dessus s'il dérape).
			_auto_in_flight = true
			var meta: Dictionary = s["meta"]
			var on_text := func(text: String) -> void:
				_auto_in_flight = false
				_emit_line(text, meta)
			var system := Prompts.adversary_system() if str(meta.get("speaker", "")) == AiConfig.ADVERSARY_NAME else Prompts.ambient_system()
			_ask(system, Prompts.build_adversary_prompt(s["adversary"], world_context()), func() -> String: return str(s["text"]),
				on_text, 2, false, int(s["adversary"].get("epoch", -1)))
		else:
			_emit_line(str(s["text"]), s["meta"])
		return
	if _auto_in_flight or _cooldown > 0.0:
		return
	if _game_over:
		return
	if not _parcel_pending.is_empty():
		_parcel_pending = expire_parcel_moments(_parcel_pending, _clock)
	var world_top := -1.0
	for e in _pending:
		world_top = maxf(world_top, float(e["_importance"]))
	var parcel_top := float(_parcel_pending[0]["importance"]) if not _parcel_pending.is_empty() else -1.0
	var ambient_ready := ambient_due(_since_line, _next_ambient,
		auto_narrate and bool(config.get_value("narrator", "ambient_enabled")), _game_state != null)
	match next_line_source(world_top, parcel_top, _parcel_cooldown <= 0.0, _world_cooldown <= 0.0, ambient_ready):
		"parcel":
			_flush_parcel()
		"world":
			if world_top < WORLD_PRIORITY:
				_world_cooldown = float(config.get_value("narrator", "world_min_interval_sec"))
			_flush()
		"ambient":
			_narrate_ambient()


## Que raconter maintenant ? "parcel", "world", "ambient" ou "" (pure, testée sans GameState).
## Les grands moments du monde (>= WORLD_PRIORITY) passent aussitôt ; les événements ordinaires du monde
## ne sont racontés qu'une fois par world_min_interval_sec (world_ready), pour laisser la place à la
## parcelle et au fil d'ambiance (faits réels, inventions).
static func next_line_source(world_top: float, parcel_top: float, parcel_ready: bool, world_ready: bool, ambient_ready: bool) -> String:
	var world_now := world_top >= WORLD_PRIORITY or (world_top >= 0.0 and world_ready)
	if parcel_goes_first(world_top if world_now else -1.0, parcel_top, parcel_ready):
		return "parcel"
	if world_now:
		return "world"
	if ambient_ready:
		return "ambient"
	return ""


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
	var sp: Variant = _species_info(int(id))
	return str(sp.get("name", "")) if sp is Dictionary else ""


func _species_info(id: int) -> Variant:
	if _game_state == null or not ("sim" in _game_state) or _game_state.sim == null or not ("species" in _game_state.sim):
		return null
	return _game_state.sim.species.get(id, null)


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
		var first: Variant = context.get("events", [{}])[0] if not context.get("events", []).is_empty() else context
		_emit_line(text, {"source": "world" if automatic else "manual", "kind": str(first.get("type", "")) if first is Dictionary else ""})
	var epoch := _current_epoch()
	context["epoch"] = epoch
	_ask(
		Prompts.narration_system(), Prompts.build_narration_prompt(context),
		func() -> String: return procedural.narrate(context), on_text, 3, not automatic, epoch)


## Envoie au LLM ; en cas d'échec ou d'absence de serveur, utilise le générateur procédural.
## epoch >= 0 : le prompt reçoit l'époque et la liste des interdits, et une réponse anachronique est
## remplacée par le repli procédural.
func _ask(system: String, prompt: String, fallback: Callable, emit: Callable, max_sentences: int, priority: bool = true, epoch := -1) -> void:
	if client == null or not (client.is_available() or client.detecting):
		_emit_deferred(emit, fallback.call())
		return
	var full_prompt := prompt
	if epoch >= 0:
		full_prompt += "\n" + Prompts.epoch_rules(epoch)
	var on_reply := func(ok: bool, text: String) -> void:
		var out: String = Prompts.vet_output(text, max_sentences, epoch) if ok else ""
		if out == "":
			out = fallback.call()
		emit.call(out)
	client.request(system, full_prompt, on_reply, {"priority": priority})


## Époque effective du monde (niveau technologique réel de la civilisation de tête, sinon ère et date).
func _current_epoch() -> int:
	return Epoch.current(_gm_context())


func _emit_deferred(emit: Callable, text: String) -> void:
	emit.call_deferred(text)
