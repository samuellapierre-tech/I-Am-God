extends Node
## Autoload « Narrator » : le compagnon (AiConfig.NARRATOR_NAME, docs/GENESE.md). Il raconte et explique ; il ne
## propose rien, n'impose rien et n'est jamais un adversaire. La simulation décide, il raconte.
## Contrat : narrate(context) émet narration_ready(text) de façon asynchrone.
##
## - Écoute GameState (événements, changements d'ère, actions divines), regroupe et limite le débit
##   des événements importants, puis raconte en 1 à 3 phrases.
## - Utilise un LLM local (Ollama / llama.cpp, accéléré GPU) s'il est disponible, en arrière-plan,
##   sinon un narrateur procédural complet : le jeu reste entièrement jouable sans IA.
## - Oracle (ask_oracle), Prières (generate_prayer) et décisions de civilisation (suggest_civilization_decision).
## - Vue rapprochée (parcel_narrator.gd) : événements « parcel_* » et changements marquants du lieu
##   regardé ; les grands moments mondiaux (importance >= WORLD_PRIORITY, gestes divins) passent avant.
## - Chaque ligne a un orateur : speech_ready(speaker, text), et meta.speaker dans chronicle_line.
## - Zéro anachronisme (epoch.gd) : prompts avec l'époque et la liste des interdits, sortie du LLM filtrée.
## - Variété (variety.gd) : mémoire anti-répétition bornée partagée par tous les générateurs ; plutôt
##   que de redire une phrase récente, le narrateur se tait.
## - Il explique (explainer.gd, facts/phenomena.gd) : statistiques de la planète (planet_stats(),
##   planet_history, lus via has_method / in), phénomènes en cours, faits vrais de la science.
## - Il présente chaque espèce marquante à sa naissance et écrit l'épitaphe des espèces éteintes
##   (bestiary.gd) ; l'IA locale enrichit ces portraits si elle est là.
## - Il réagit aux semences du joueur (seeds.gd), avec réussite ou échec et la raison.
## - Il raconte la fin des temps et la réincarnation (worlds.gd), et se souvient des mondes passés.
## - Fil continu (chronicle.gd) : sans événement depuis 8 à 15 s, une phrase d'ambiance.
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
## Chaque ligne du fil écrit (événement du monde, du lieu regardé, ambiance…), dans l'ordre.
## meta : {source: "world"|"parcel"|"ambient"|"manual", kind, speaker, era, year, world_mode…}.
signal chronicle_line(text: String, meta: Dictionary)
## Qui parle : AiConfig.NARRATOR_NAME. Émis pour CHAQUE ligne du fil, en plus de
## narration_ready (compatibilité, sans orateur) et de chronicle_line (meta.speaker contient le même nom).
signal speech_ready(speaker: String, text: String)
## Une espèce marquante vient d'être présentée (pour le grand livre / Panthéon de l'interface).
signal species_presented(species_id: int, text: String)
## L'épitaphe d'une espèce éteinte.
signal epitaph_written(species_id: int, text: String)
## Réaction à une semence : kind ("spark", "light", "spore", "animal_germ", "shaped"), réussite, raison.
signal seed_reaction(kind: String, success: bool, reason_code: String, text: String)
## Fin des temps d'une planète, puis réincarnation : le texte du narrateur.
signal world_ended(text: String)
signal world_reborn(text: String)

const AiConfig := preload("res://src/ai/ai_config.gd")
const LlmClient := preload("res://src/ai/llm_client.gd")
const Procedural := preload("res://src/ai/procedural_narrator.gd")
const Prompts := preload("res://src/ai/prompt_builder.gd")
const DecisionSchema := preload("res://src/ai/decision_schema.gd")
const ParcelNarrator := preload("res://src/ai/parcel_narrator.gd")
const Chronicle := preload("res://src/ai/chronicle.gd")
const Divergence := preload("res://src/ai/divergence.gd")
const FactBase := preload("res://src/ai/facts/fact_base.gd")
const Epoch := preload("res://src/ai/epoch.gd")
const Variety := preload("res://src/ai/variety.gd")
const Explainer := preload("res://src/ai/explainer.gd")
const Bestiary := preload("res://src/ai/bestiary.gd")
const Seeds := preload("res://src/ai/seeds.gd")
const Worlds := preload("res://src/ai/worlds.gd")

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
## Délai minimal (s) entre deux lignes prioritaires (présentations, épitaphes, semences, fin des temps).
const PRIORITY_GAP := 2.0
## Lignes prioritaires en attente au plus.
const PRIORITY_QUEUE_SIZE := 10
## Échantillonnage des statistiques de la planète (s réelles) et taille de l'historique gardé.
const PLANET_SAMPLE_SEC := 5.0
const PLANET_HISTORY_SIZE := 240
## Comparaison pour reconnaître un phénomène : l'échantillon d'il y a PLANET_COMPARE_SAMPLES.
const PLANET_COMPARE_SAMPLES := 12
## Délai minimal (s) entre deux présentations d'espèces « ordinairement marquantes » (les espèces
## conscientes et celles nées d'un geste du joueur passent toujours).
const PRESENT_COOLDOWN := 25.0
## Types d'événements qui font naître une espèce (tolérant : sous-chaînes).
const BIRTH_TYPES := ["speciation", "spawn", "new_species", "radiation", "sapience", "seeded", "lazarus", "clade"]
## Noms de signaux possibles pour la réincarnation (session Sauvegarde : à définir).
## GameState.world_reborn(info) (contrat de la session Sauvegarde) d'abord ; les autres par tolérance.
const REBIRTH_SIGNALS := ["world_reborn", "reincarnated", "reincarnation", "planet_reborn", "new_planet"]
## Causes de la fin des temps reconnues dans un résumé libre (sous-chaînes) -> Worlds.ENDS.
const END_CAUSES := {"sun": "sun", "soleil": "sun", "ocean": "oceans", "océan": "oceans", "player": "player",
	"joueur": "player", "dieu": "player", "impact": "impact", "météor": "impact", "frozen": "frozen", "froid": "frozen",
	"glac": "frozen", "ice": "frozen"}
## Lignes retenues par la mémoire anti-répétition (aucun texte narratif identique en deçà).
const VARIETY_WINDOW := 200

var config: AiConfig
var client: LlmClient
var procedural: Procedural
var parcel_narrator: ParcelNarrator
var chronicle: Chronicle
## Le monde suit-il l'histoire réelle ? (définitivement « divergent » une fois l'un des critères atteint)
var lens: Divergence
## Mémoire anti-répétition partagée (bornée) : aucun texte identique à moins de VARIETY_WINDOW lignes.
var variety: Variety
var bestiary: Bestiary
## Mondes passés et monde en cours (fin des temps, réincarnation).
var worlds: Worlds
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
## Lignes prioritaires prêtes : [{text, meta, llm: {system, prompt, required}?}].
var _priority: Array[Dictionary] = []
## Phénomènes à expliquer, du plus récent au plus ancien (bornés).
var _phenomena: Array[String] = []
var _planet_history: Array[Dictionary] = []
var _planet_clock := 0.0
var _present_cooldown := 0.0
var _seen_clades := {}
## Espèces présentées (pour leur écrire une épitaphe), bornées.
var _presented: Array[int] = []
## Gestes du joueur par espèce (seed, bless, save, spawn_species), pour les épitaphes.
var _deeds := {}
var _sim_ref: WeakRef = null
## La fin des temps a été racontée (le signal et l'événement peuvent arriver tous deux).
var _ended := false
## Types des événements récents (bruts et canoniques) avec leur heure : [{type, t}].
var _recent_events: Array[Dictionary] = []


func _ready() -> void:
	config = AiConfig.new()
	config.load_or_create()
	procedural = Procedural.new()
	parcel_narrator = ParcelNarrator.new()
	chronicle = Chronicle.new()
	lens = Divergence.new()
	variety = Variety.new(VARIETY_WINDOW)
	bestiary = Bestiary.new()
	worlds = Worlds.new()
	for gen in [chronicle, parcel_narrator, procedural, bestiary]:
		gen.variety = variety
	chronicle.inventor.variety = variety
	chronicle.explainer.variety = variety
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


## Oracle « et si ? » : transforme le résumé de WorldSim.project_future() en prophétie. Émet oracle_answered.
func ask_oracle(question: String, projection: Dictionary) -> void:
	_ask(
		Prompts.PERSONA_ORACLE, Prompts.build_oracle_prompt(question, projection),
		func() -> String: return procedural.prophecy(question, projection),
		func(text: String) -> void: oracle_answered.emit(text), 3)


## Prière d'une espèce sapiente. species : {id, name, traits, population} ; situation : {type, era, enemy, summary, region}.
## Émet prayer_received(species_id, text).
func generate_prayer(species: Dictionary, situation: Dictionary) -> void:
	var sit := situation.duplicate()
	if not sit.has("era"):
		sit["era"] = _current_era()
	var sid := int(species.get("id", sit.get("species_id", -1)))
	_ask(
		Prompts.PERSONA_PRIERE, Prompts.build_prayer_prompt(species, sit),
		func() -> String: return procedural.prayer(species, sit),
		func(text: String) -> void: prayer_received.emit(sid, text), 3, true, _current_epoch())


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
	}
	for sig in REBIRTH_SIGNALS:
		links[sig] = _on_reincarnation
	links["end_of_times"] = _on_end_of_times_signal
	for sig in links:
		if _game_state.has_signal(sig) and not _game_state.is_connected(sig, links[sig]):
			_game_state.connect(sig, links[sig])
	_sim_ref = weakref(_game_state.sim) if "sim" in _game_state and _game_state.sim != null else null
	# GameState a déjà émis la première ère avant notre connexion : on ouvre la chronique.
	var era := _current_era()
	if era != "":
		_on_era_changed(era)
	# La parcelle de départ sert de référence : on ne raconte que ce qui change ensuite.
	parcel_narrator.reset(ParcelNarrator.snapshot(_parcel()))


func _on_event_occurred(event: Dictionary) -> void:
	var t := str(event.get("type", "")).to_lower()
	_note_event_type(t)
	if t.begins_with("parcel_"):
		_on_parcel_event(event)
		return
	worlds.note_year(_current_year())
	if t.contains("end_of_times") or t.contains("fin_des_temps"):
		_on_end_of_times(event)
		return
	for p in Explainer.phenomena_for_event(event):
		_queue_phenomenon(p)
	var sid := int(event.get("species_id", -1))
	if _is_birth(t) and sid >= 0:
		if _on_species_born(sid, t):
			return
	elif t.contains("extinction") and sid >= 0:
		if _on_species_extinct(sid, event):
			return
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
	var atype := str(action.get("type", ""))
	var target_id := int(action.get("species_id", -1))
	for c in consequences:
		if c is Dictionary and target_id < 0 and int(c.get("species_id", -1)) >= 0:
			target_id = int(c["species_id"])
	if atype in ["seed", "bless", "save", "spawn_species"] and target_id >= 0:
		_deeds[target_id] = atype
	if atype == "seed":
		_on_seed(action, consequences, target_id)
		return
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
	_divine_history.append({"type": str(action.get("type", "")), "year": _current_year(), "species_id": int(target) if typeof(target) in [TYPE_INT, TYPE_FLOAT] else -1,
		"species_name": _species_name_for(target)})
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
	if auto_narrate and auto_narrate_parcel:
		_push_parcel(moment)


func _on_parcel_updated() -> void:
	for moment in parcel_narrator.observe(ParcelNarrator.snapshot(_parcel())):
		if auto_narrate and auto_narrate_parcel:
			_push_parcel(moment)


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
		if text.strip_edges() != "":
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
	var ctx := _base_context()
	ctx["recent_events"] = recent
	ctx["mode"] = lens.update(ctx)
	ctx["planet"] = _planet_stats()
	ctx["planet_history"] = _history_for_comment()
	ctx["phenomena"] = _phenomena.duplicate()
	return ctx


## Contexte sans effet de bord (ni bascule réel/divergent) : ère, date, lieu regardé, espèces, gestes.
func _base_context() -> Dictionary:
	return {
		"era": _current_era(), "year": _current_year(), "snapshot": ParcelNarrator.snapshot(_parcel()),
		"species": _species_list(), "divine": _divine_history.duplicate(),
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
	if line.has("phenomenon"):
		_phenomena.erase(str(line["phenomenon"]))
	var on_text := func(text: String) -> void:
		_auto_in_flight = false
		var meta := {"source": "ambient", "kind": str(line.get("kind", ""))}
		for k in ["fact_id", "species_id", "world_mode", "scene", "phenomenon", "stat"]:
			if line.has(k):
				meta[k] = line[k]
		_emit_line(text, meta)
	var fallback := func() -> String: return str(line["text"])
	var kind := str(line.get("kind", ""))
	var prompt := Prompts.build_invention_prompt(line, ctx) if kind in ["invention", "divergence", "vision"] else Prompts.build_ambient_prompt(line, ctx)
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
	if text.strip_edges() == "":
		# Rien de neuf à dire sans se répéter : le narrateur se tait (le fil reste calme).
		_since_line = 0.0
		_next_ambient = _draw_ambient_delay()
		return
	if variety != null and not variety.seen(text):
		variety.remember(text)
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
# Le compagnon : planète, espèces, semences, fin des temps
# ---------------------------------------------------------------------------

## Statistiques de la planète, normalisées (Explainer.normalize). Source, dans l'ordre : planet_stats()
## de la simulation ou de GameState (session Planète), sinon une estimation documentée à partir de la
## simulation actuelle : oxygen (fraction du niveau actuel) x 0,21 ; ozone ~ oxygène / 10 % du niveau
## actuel (la couche protège presque pleinement au-delà) ; boule de neige -> glaces 90 % ; espèces vivantes.
func _planet_stats() -> Dictionary:
	var sim: Object = _game_state.sim if _game_state != null and "sim" in _game_state else null
	for src in [sim, _game_state]:
		if src != null and src.has_method("planet_stats"):
			var raw: Variant = src.planet_stats()
			if raw is Dictionary:
				var s := Explainer.normalize(_air_oxygen(raw))
				if not s.has("year") and _current_year() != null:
					s["year"] = float(_current_year())
				return s
	var out := {}
	if sim == null:
		return out
	if "oxygen" in sim:
		var pal := float(sim.get("oxygen"))
		out["oxygen"] = pal * 0.21
		out["ozone"] = clampf(pal / 0.1, 0.0, 1.0)
	if "snowball" in sim and bool(sim.get("snowball")):
		out["ice_cover"] = 0.9
	if "year" in sim:
		out["year"] = float(sim.get("year"))
	var p := _parcel()
	if p != null and "global_temperature_c" in p:
		out["temperature_c"] = float(p.get("global_temperature_c"))
	var alive := 0
	for sp in _species_list():
		if sp["alive"]:
			alive += 1
	out["biodiversity"] = float(alive)
	return out


## Contrat Planète : planet_stats().oxygen est une fraction du niveau ACTUEL (1 = 21 % de l'air) ;
## Explainer attend une fraction de l'air. Un pourcentage (> 5) est laissé à normalize().
static func _air_oxygen(raw: Dictionary) -> Dictionary:
	var r := raw.duplicate()
	if typeof(r.get("oxygen")) in [TYPE_INT, TYPE_FLOAT] and float(r["oxygen"]) <= 5.0:
		r["oxygen"] = float(r["oxygen"]) * 0.21
	return r


## Historique des statistiques (planet_history() ou planet_history de la simulation, sinon nos échantillons).
func _history_for_comment() -> Array:
	var sim: Object = _game_state.sim if _game_state != null and "sim" in _game_state else null
	var h: Variant = null
	if sim != null and sim.has_method("planet_history"):
		h = sim.planet_history()
	elif sim != null and "planet_history" in sim:
		h = sim.get("planet_history")
	if h is Array and not (h as Array).is_empty():
		var out := []
		for rec in (h as Array).slice(maxi(0, (h as Array).size() - PLANET_HISTORY_SIZE)):
			if rec is Dictionary:
				out.append(Explainer.normalize(_air_oxygen(rec)))
		return out
	return _planet_history


## Échantillonne la planète, reconnaît les phénomènes en cours, et repère une réincarnation.
func _sample_planet() -> void:
	if _game_state == null:
		return
	var sim: Object = _game_state.sim if "sim" in _game_state else null
	if _sim_ref != null and sim != null and _sim_ref.get_ref() != sim:
		# Nouvelle simulation (partie chargée ou planète nouvelle) : l'historique ne se compare plus.
		_planet_history.clear()
	_sim_ref = weakref(sim) if sim != null else null
	var now := _planet_stats()
	if now.is_empty():
		return
	_planet_history.append(now)
	while _planet_history.size() > PLANET_HISTORY_SIZE:
		_planet_history.pop_front()
	var i := maxi(0, _planet_history.size() - 1 - PLANET_COMPARE_SAMPLES)
	if i < _planet_history.size() - 1:
		for p in Explainer.detect(_planet_history[i], now):
			_queue_phenomenon(p)


func _queue_phenomenon(p: String) -> void:
	if p == "":
		return
	_phenomena.erase(p)
	_phenomena.push_front(p)
	while _phenomena.size() > 8:
		_phenomena.pop_back()


static func _is_birth(t: String) -> bool:
	for b in BIRTH_TYPES:
		if t.contains(b):
			return true
	return false


## Une espèce naît : si elle est marquante, le narrateur la présente (true : l'événement est raconté).
func _on_species_born(sid: int, t: String) -> bool:
	var info: Variant = _species_info(sid)
	if not (info is Dictionary):
		return false
	var sp: Dictionary = (info as Dictionary).duplicate()
	# Description procédurale de la session Vie, si elle existe.
	var sim: Object = _game_state.sim
	if str(sp.get("description", "")) == "" and sim.has_method("describe_species"):
		sp["description"] = str(sim.describe_species(sid))
	if bool(sp.get("sown", false)) and not _deeds.has(sid):
		_deeds[sid] = "seed"
	var name := str(sp.get("name", ""))
	var traits: Dictionary = sp.get("traits", {})
	var clade := str(traits.get("clade", sp.get("clade", "")))
	var player := _deeds.has(sid) or t.contains("seed") or t.contains("spawn")
	var sapient := bool(sp.get("sapient", false)) or t.contains("sapience")
	var new_clade := clade != "" and not _seen_clades.has(clade)
	_seen_clades[clade] = true
	var notable := player or sapient or ((new_clade or float(traits.get("size", 0.0)) >= 0.75) and _present_cooldown <= 0.0)
	worlds.note_species(name, notable)
	if sapient:
		worlds.note_civilization(name)
	if not notable or not auto_narrate:
		return false
	if not (player or sapient):
		_present_cooldown = PRESENT_COOLDOWN
	var ctx := _base_context()
	var line := bestiary.present(_with_id(sp, sid), ctx)
	_presented.append(sid)
	while _presented.size() > 64:
		_presented.pop_front()
	_push_priority(str(line["text"]), {"source": "species", "kind": "presentation", "species_id": sid},
		Prompts.species_system() if is_ai_available() else "",
		Prompts.build_species_prompt(_with_id(sp, sid), ctx, str(line["text"]), "presentation") if is_ai_available() else "", name)
	return true


## Une espèce s'éteint : si elle comptait (présentée, consciente, grande, ou touchée par le joueur),
## le narrateur écrit son épitaphe (true : l'événement est raconté).
func _on_species_extinct(sid: int, event: Dictionary) -> bool:
	var sp: Variant = _species_info(sid)
	if not (sp is Dictionary):
		return false
	var traits: Dictionary = sp.get("traits", {})
	if not (sid in _presented or _deeds.has(sid) or bool(sp.get("sapient", false)) or float(traits.get("size", 0.0)) >= 0.75):
		return false
	if not auto_narrate:
		return true
	var ctx := _base_context()
	var summary := str(event.get("summary", "")).to_lower()
	var cause := ""
	if summary.contains("impact") or summary.contains("météor") or summary.contains("meteor"):
		cause = "impact"
	elif str(event.get("cause_type", "")) == "extinct" or summary.contains("dieu"):
		cause = "divine"
	var line := bestiary.epitaph(_with_id(sp, sid), ctx, cause, str(_deeds.get(sid, "")))
	_push_priority(str(line["text"]), {"source": "species", "kind": "epitaph", "species_id": sid, "cause": str(line.get("cause", ""))},
		Prompts.species_system() if is_ai_available() else "",
		Prompts.build_species_prompt(_with_id(sp, sid), ctx, str(line["text"]), "epitaph") if is_ai_available() else "", str(sp.get("name", "")))
	var c := str(line.get("cause", ""))
	if c in ["climate", "predation", "competition"]:
		_queue_phenomenon("decline_" + c)
	return true


## Semence du joueur : réussite ou échec, toujours avec la raison.
func _on_seed(action: Dictionary, consequences: Array, target_id: int) -> void:
	worlds.note_seed()
	_divine_history.append({"type": "seed", "year": _current_year(), "species_id": target_id, "species_name": _species_name_for(target_id)})
	if _divine_history.size() > 64:
		_divine_history.pop_front()
	for c in consequences:
		if c is Dictionary and c.has("id"):
			_absorbed_ids[c["id"]] = true
	var r := Seeds.react(action, consequences, _planet_stats(), _base_context())
	_push_priority(str(r["text"]), {"source": "seed", "kind": str(r["kind"]), "success": bool(r["success"]), "reason_code": str(r["reason_code"])})
	seed_reaction.emit(str(r["kind"]), bool(r["success"]), str(r["reason_code"]), str(r["text"]))
	if str(r.get("phenomenon", "")) != "":
		_queue_phenomenon(str(r["phenomenon"]))
	_since_line = maxf(_since_line, PRIORITY_GAP)


## GameState.end_of_times(summary) : summary est la cause (texte libre) ou un bilan {cause|reason|summary}.
func _on_end_of_times_signal(summary: Variant = null, _b: Variant = null) -> void:
	_on_end_of_times(summary if summary is Dictionary else {"summary": str(summary) if summary != null else ""})


## Cause de la fin des temps (clé de Worlds.ENDS) d'après l'événement ou le bilan.
static func end_cause(event: Dictionary) -> String:
	var raw := ("%s %s %s" % [event.get("cause", ""), event.get("reason", ""), event.get("summary", "")]).to_lower()
	for k in END_CAUSES:
		if raw.contains(k):
			return END_CAUSES[k]
	return ""


## La fin des temps de cette planète (événement {type: "end_of_times", summary} ou signal) : une seule fois.
func _on_end_of_times(event: Dictionary) -> void:
	if _ended:
		return
	_ended = true
	var text := worlds.end_of_times(end_cause(event), _current_year())
	_priority.clear()
	_pending.clear()
	_parcel_pending.clear()
	_emit_line(text, {"source": "world", "kind": "end_of_times"})
	world_ended.emit(text)


## Réincarnation (signal de la session Sauvegarde, ou nouvelle simulation) : arguments facultatifs,
## le premier peut décrire la nouvelle planète {size, ocean_fraction, star, …}.
func _on_reincarnation(a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	_ended = false
	if not (worlds.current.get("species_born", 0) == 0 and worlds.current.get("first_year") == null):
		# Le monde précédent n'a pas eu de fin des temps racontée : on le range quand même.
		worlds.remember(worlds.current)
		worlds.current = Worlds._blank()
	var planet: Dictionary = a if a is Dictionary else {}
	var text := worlds.reincarnation(planet)
	_priority.clear()
	_pending.clear()
	_parcel_pending.clear()
	_phenomena.clear()
	_planet_history.clear()
	_seen_clades.clear()
	_presented.clear()
	_deeds.clear()
	parcel_narrator.reset(ParcelNarrator.snapshot(_parcel()))
	_emit_line(text, {"source": "world", "kind": "reincarnation"})
	world_reborn.emit(text)


## Mémoire du narrateur pour la sauvegarde (contrat de la session Sauvegarde) : mondes passés, cultures
## inventées, gestes de Dieu, espèces présentées. Que des types simples (pas de Callable ni de Node).
func save_state() -> Dictionary:
	return {"worlds": worlds.snapshot(), "fallen": chronicle.inventor.fallen.duplicate(true),
		"archive": chronicle.inventor.archive.duplicate(true), "forgotten": chronicle.inventor.forgotten,
		"divine": _divine_history.duplicate(true), "deeds": _deeds.duplicate(), "presented": _presented.duplicate(),
		"clades": _seen_clades.keys(), "last_era": _last_era, "ended": _ended}


func load_state(data: Dictionary) -> void:
	if data.get("worlds") is Dictionary:
		worlds.restore(data["worlds"])
	_divine_history.clear()
	for d in data.get("divine", []):
		if d is Dictionary:
			_divine_history.append(d)
	_deeds.clear()
	var deeds: Variant = data.get("deeds", {})
	if deeds is Dictionary:
		for k in deeds:
			_deeds[int(k)] = str(deeds[k])
	_presented.clear()
	for i in data.get("presented", []):
		_presented.append(int(i))
	_seen_clades.clear()
	for c in data.get("clades", []):
		_seen_clades[str(c)] = true
	_last_era = str(data.get("last_era", _last_era))
	_ended = bool(data.get("ended", false))
	_planet_history.clear()
	var inv := chronicle.inventor
	inv.fallen.clear()
	for f in data.get("fallen", []):
		if f is Dictionary:
			inv.fallen.append(f)
	inv.archive.clear()
	for f in data.get("archive", []):
		if f is Dictionary:
			inv.archive.append(f)
	inv.forgotten = int(data.get("forgotten", 0))


func _push_priority(text: String, meta: Dictionary, system := "", prompt := "", required := "") -> void:
	if text.strip_edges() == "":
		return
	var item := {"text": text, "meta": meta}
	if system != "":
		item["llm"] = {"system": system, "prompt": prompt, "required": required}
	_priority.append(item)
	while _priority.size() > PRIORITY_QUEUE_SIZE:
		_priority.pop_front()


func _emit_priority(item: Dictionary) -> void:
	var meta: Dictionary = item["meta"]
	var finish := func(text: String) -> void:
		_emit_line(text, meta)
		if text.strip_edges() == "":
			return
		match str(meta.get("kind", "")):
			"presentation":
				species_presented.emit(int(meta.get("species_id", -1)), text)
			"epitaph":
				epitaph_written.emit(int(meta.get("species_id", -1)), text)
	if item.has("llm") and is_ai_available():
		# L'IA locale enrichit le portrait en arrière-plan ; repli immédiat sur le texte procédural.
		_auto_in_flight = true
		var llm: Dictionary = item["llm"]
		var on_text := func(text: String) -> void:
			_auto_in_flight = false
			finish.call(text)
		_ask(str(llm["system"]), str(llm["prompt"]), func() -> String: return str(item["text"]), on_text, 3, false,
			_current_epoch(), str(llm["required"]))
	else:
		finish.call(str(item["text"]))


static func _with_id(sp: Dictionary, sid: int) -> Dictionary:
	var d := sp.duplicate()
	d["id"] = sid
	return d


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
	_cooldown = maxf(_cooldown - delta, 0.0)
	_parcel_cooldown = maxf(_parcel_cooldown - delta, 0.0)
	_world_cooldown = maxf(_world_cooldown - delta, 0.0)
	_present_cooldown = maxf(_present_cooldown - delta, 0.0)
	_planet_clock += delta
	if _planet_clock >= PLANET_SAMPLE_SEC:
		_planet_clock = 0.0
		_sample_planet()
	# Présentations, épitaphes, semences, fin des temps : elles passent avant le reste, à leur rythme.
	if not _priority.is_empty() and not _auto_in_flight and _since_line >= PRIORITY_GAP:
		_emit_priority(_priority.pop_front())
		return
	if _auto_in_flight or _cooldown > 0.0:
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
func _ask(system: String, prompt: String, fallback: Callable, emit: Callable, max_sentences: int, priority: bool = true, epoch := -1, required := "") -> void:
	if client == null or not (client.is_available() or client.detecting):
		_emit_deferred(emit, fallback.call())
		return
	var full_prompt := prompt
	if epoch >= 0:
		full_prompt += "\n" + Prompts.epoch_rules(epoch)
	var on_reply := func(ok: bool, text: String) -> void:
		var out: String = Prompts.vet_output(text, max_sentences, epoch) if ok else ""
		if required != "" and not out.contains(required):
			out = ""
		if out == "":
			out = fallback.call()
		emit.call(out)
	client.request(system, full_prompt, on_reply, {"priority": priority})


## Époque effective du monde (niveau technologique réel de la civilisation de tête, sinon ère et date).
func _current_epoch() -> int:
	return Epoch.current(_base_context())


func _emit_deferred(emit: Callable, text: String) -> void:
	emit.call_deferred(text)
