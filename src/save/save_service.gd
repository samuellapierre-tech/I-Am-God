extends Node
## Service de sauvegarde, enfant de GameState (« Saver ») :
## - instantané complet du jeu : monde (WorldSim, ParcelSim et tout leur graphe d'objets), partie
##   (temps de jeu, nom et paramètres de la planète, suivi du Panthéon), mémoire d'Ézéchiel, et tout
##   nœud du groupe « save_state » (épingles, statistiques…) exposant save_state() / load_state() ;
## - sauvegarde automatique toutes les AUTOSAVE_SECONDS et à la fermeture de la fenêtre ;
## - suivi des espèces marquantes du monde courant pour le Panthéon (apogées, créations divines).

const Serializer := preload("res://src/save/serializer.gd")
const SaveStore := preload("res://src/save/save_store.gd")

const AUTOSAVE_SECONDS := 300.0
const AUTO_SLOT := "auto"
## Groupe des nœuds qui ont un état à sauver (save_state() -> Dictionary, load_state(d)).
const GROUP := "save_state"
## Champs de repli de la mémoire d'Ézéchiel tant que Narrator n'expose pas save_state().
const NARRATOR_FIELDS := ["chronicle", "lens", "variety", "_divine_history", "_recent_events", "_last_era", "_last_stage"]
## Fréquence du suivi des apogées (secondes réelles).
const TRACK_SECONDS := 1.0

## Sauvegarde automatique active (désactivée par les tests et par --no-autosave).
var autosave := true
var dir := SaveStore.DIR
## Espèces du monde courant : id -> régions à l'apogée ; ids créées par Dieu.
var peaks := {}
var created := {}
var last_error := ""

var _autosave_timer := 0.0
var _track_timer := 0.0


func _ready() -> void:
	if "--no-autosave" in OS.get_cmdline_user_args():
		autosave = false


func _process(delta: float) -> void:
	var gs := get_parent()
	if gs == null or gs.get("sim") == null:
		return
	_track_timer += delta
	if _track_timer >= TRACK_SECONDS:
		_track_timer = 0.0
		track(gs.sim)
	if autosave and not gs.paused:
		_autosave_timer += delta
		if _autosave_timer >= AUTOSAVE_SECONDS:
			_autosave_timer = 0.0
			save(AUTO_SLOT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and autosave:
		save(AUTO_SLOT)


## Note les apogées des espèces vivantes (borné par les fiches d'espèces du monde).
func track(sim: RefCounted) -> void:
	for id in sim.get_alive_species():
		var r := int(sim.species[id].get("regions", 0))
		if r > int(peaks.get(id, 0)):
			peaks[id] = r
	if peaks.size() > sim.species.size() + 64:
		for id in peaks.keys():
			if not sim.species.has(id):
				peaks.erase(id)


## Un événement du monde : retient les espèces créées par Dieu.
func note_event(ev: Dictionary) -> void:
	if String(ev.get("type", "")) == "spawn" and int(ev.get("species_id", -1)) >= 0:
		created[int(ev.species_id)] = true


func reset_tracking() -> void:
	peaks.clear()
	created.clear()
	_autosave_timer = 0.0


# =============================================================================================
# Instantané
# =============================================================================================

func snapshot() -> Dictionary:
	var gs := get_parent()
	return {
		world = Serializer.encode({sim = gs.sim, parcel = gs.parcel}),
		game = {
			play_time = gs.play_time, world_name = gs.world_name, world_index = gs.world_index,
			planet = gs.planet_params, peaks = peaks, created = created,
			# Cadence de la parcelle : la reprise rafraîchit la parcelle aux mêmes instants.
			parcel_timer = gs._parcel_timer, pending_events = gs._pending_events.duplicate(true),
		},
		narrator = _narrator_state(),
		participants = _participants_state(),
	}


func meta() -> Dictionary:
	var gs := get_parent()
	return {
		world_name = gs.world_name, world_index = gs.world_index, year = int(gs.sim.year),
		era = gs.sim.current_era(), species_alive = gs.sim.get_alive_species().size(),
		play_time = int(gs.play_time),
	}


## Restaure un instantané. Renvoie "" ou un message d'erreur (rien n'est changé en cas d'erreur).
func restore(payload: Dictionary) -> String:
	var res := Serializer.decode(payload.get("world", {}))
	var root: Variant = res.value
	if not res.errors.is_empty() or typeof(root) != TYPE_DICTIONARY or root.get("sim") == null:
		return "monde illisible : %s" % ", ".join(res.errors)
	var gs := get_parent()
	var game: Dictionary = payload.get("game", {})
	gs.adopt_world(root.sim, root.get("parcel"), {
		world_name = String(game.get("world_name", "")), world_index = int(game.get("world_index", 1)),
		planet = game.get("planet", {}), play_time = float(game.get("play_time", 0.0)),
		parcel_timer = float(game.get("parcel_timer", 0.0)), pending_events = game.get("pending_events", []),
	})
	peaks = game.get("peaks", {})
	created = game.get("created", {})
	_restore_narrator(payload.get("narrator", {}))
	_restore_participants(payload.get("participants", {}))
	_autosave_timer = 0.0
	return ""


func save(slot: String) -> String:
	var gs := get_parent()
	if gs == null or gs.get("sim") == null:
		last_error = "aucun monde"
		return last_error
	last_error = SaveStore.save_slot(slot, snapshot(), meta(), dir)
	if last_error == SaveStore.ERR_NONE and gs.has_signal("game_saved"):
		gs.game_saved.emit(slot)
	return last_error


func load_slot(slot: String) -> String:
	var res := SaveStore.load_slot(slot, dir)
	if res.error != SaveStore.ERR_NONE:
		last_error = res.error
		return last_error
	last_error = restore(res.payload)
	var gs := get_parent()
	if last_error == "" and gs.has_signal("game_loaded"):
		gs.game_loaded.emit(slot)
	return last_error


func has_save(slot := AUTO_SLOT) -> bool:
	return FileAccess.file_exists(SaveStore.path_of(slot, dir))


# =============================================================================================
# Ézéchiel et participants
# =============================================================================================

func _narrator() -> Node:
	return get_node_or_null("/root/Narrator") if is_inside_tree() else null


func _narrator_state() -> Dictionary:
	var n := _narrator()
	if n == null:
		return {}
	if n.has_method("save_state"):
		return {api = n.save_state()}
	var fields := {}
	for name in NARRATOR_FIELDS:
		if name in n:
			fields[name] = n.get(name)
	return {fallback = Serializer.encode(fields)}


func _restore_narrator(state: Dictionary) -> void:
	var n := _narrator()
	if n == null or state.is_empty():
		return
	if state.has("api") and n.has_method("load_state"):
		n.load_state(state.api)
		return
	if not state.has("fallback"):
		return
	var live := {}
	for name in NARRATOR_FIELDS:
		if name in n and typeof(n.get(name)) == TYPE_OBJECT:
			live[name] = n.get(name)
	var res := Serializer.decode(state.fallback, live)
	if typeof(res.value) != TYPE_DICTIONARY:
		return
	for name in res.value:
		if name in n and typeof(n.get(name)) != TYPE_OBJECT:
			n.set(name, Serializer.Decoder.conform(n.get(name), res.value[name]))


func _participants_state() -> Dictionary:
	var out := {}
	if not is_inside_tree():
		return out
	for node in get_tree().get_nodes_in_group(GROUP):
		if node.has_method("save_state"):
			out[String(node.name)] = node.save_state()
	return out


func _restore_participants(states: Dictionary) -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group(GROUP):
		if states.has(String(node.name)) and node.has_method("load_state"):
			node.load_state(states[String(node.name)])
