extends SceneTree
## Vérification en vrai jeu (hors suite automatique) : lance la scène principale (globe, sol, HUD,
## Ézéchiel), laisse tourner, sauvegarde, recharge dans la partie en cours, puis compare octet pour
## octet la suite du monde rechargé à celle d'une copie gardée en mémoire.
## godot --path . -s res://tests/live/save_live_check.gd -- --no-menu --no-autosave

const Serializer := preload("res://src/save/serializer.gd")
const SaveStore := preload("res://src/save/save_store.gd")

const PLAY_FRAMES := 240
const AFTER_STEPS := 120


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	var gs: Node = get_root().get_node("GameState")
	gs.saver.dir = "user://live_check"
	for i in PLAY_FRAMES:
		await process_frame
	var y_before: float = gs.sim.year
	gs.hold_time("live_check", true)
	await process_frame
	var err: String = gs.save_game("slot_3")
	if err != "":
		_finish("FAIL sauvegarde : %s" % err)
		return
	# Copie de référence : l'état sauvé, décodé à part.
	var ref := Serializer.decode(SaveStore.load_slot("slot_3", gs.saver.dir).payload.world)
	var ref_sim: RefCounted = ref.value.sim
	# On laisse la partie avancer encore, puis on recharge la sauvegarde dans la partie en cours.
	gs.hold_time("live_check", false)
	for i in 30:
		await process_frame
	gs.hold_time("live_check", true)
	if gs.load_game("slot_3") != "":
		_finish("FAIL rechargement : %s" % gs.saver.last_error)
		return
	await process_frame
	if Serializer.fingerprint(gs.sim) != Serializer.fingerprint(ref_sim):
		_finish("FAIL monde rechargé différent de la sauvegarde")
		return
	var dt: float = gs.sim.ideal_step_years() * gs.sim.max_substeps
	for i in AFTER_STEPS:
		gs.sim.step(dt)
		ref_sim.step(dt)
		await process_frame
	if Serializer.fingerprint(gs.sim) != Serializer.fingerprint(ref_sim):
		_finish("FAIL divergence après %d pas" % AFTER_STEPS)
		return
	_finish("PASS en vrai jeu : sauvegarde à l'an %.0f (%s), rechargée, %d pas identiques octet pour octet" % [
		y_before, gs.sim.current_era(), AFTER_STEPS])


func _finish(msg: String) -> void:
	print("SAVE_LIVE ", msg)
	SaveStore.delete_slot("slot_3", "user://live_check")
	quit()
