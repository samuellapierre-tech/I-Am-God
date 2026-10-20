extends RefCounted
## Sauvegarde au niveau du jeu (GameState) : reprise exacte, Panthéon qui survit à la réincarnation,
## ressemis d'une espèce, fin des temps.
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const GameStateScript := preload("res://src/core/game_state.gd")
const Serializer := preload("res://src/save/serializer.gd")
const Pantheon := preload("res://src/save/pantheon.gd")
const Base := preload("res://tests/test_save.gd")


func _game(dir: String) -> Node:
	var gs: Node = GameStateScript.new()
	gs._ensure_save_services()
	gs.saver.dir = dir
	gs.saver.autosave = false
	gs.pantheon = Pantheon.new(dir.path_join("pantheon"))
	return gs


func _run(gs: Node, frames: int) -> void:
	gs.years_per_second = gs.sim.ideal_step_years() * gs.sim.max_substeps * 30.0
	for i in frames:
		gs._process(1.0 / 30.0)


func test_game_save_and_resume_exactly() -> String:
	var dir := Base._temp_dir("game")
	var a := _game(dir)
	a.new_world(21)
	_run(a, 60)
	var out := ""
	if a.save_game("slot_1") != "":
		out = "sauvegarde refusée : %s" % a.saver.last_error
	var b := _game(dir)
	b.new_world(99)
	var loaded := []
	b.game_loaded.connect(func(s): loaded.append(s))
	if out == "":
		var err: String = b.load_game("slot_1")
		if err != "":
			out = "reprise refusée : %s" % err
		elif loaded != ["slot_1"] or b.world_name != a.world_name or b.sim.seed != 21:
			out = "partie reprise incohérente : %s, %s" % [b.world_name, loaded]
		elif Serializer.fingerprint(b.sim) != Serializer.fingerprint(a.sim):
			out = "monde repris différent"
		else:
			# Même suite d'images des deux côtés (années par seconde fixées).
			b.years_per_second = a.years_per_second
			for i in 90:
				a._process(1.0 / 30.0)
				b._process(1.0 / 30.0)
			if Serializer.fingerprint(b.sim) != Serializer.fingerprint(a.sim):
				out = "la partie reprise diverge"
			elif Serializer.fingerprint(b.parcel) != Serializer.fingerprint(a.parcel):
				out = "la parcelle reprise diverge"
	a.free()
	b.free()
	Base._clean(dir.path_join("pantheon"))
	Base._clean(dir)
	return out


func test_pantheon_survives_reincarnation() -> String:
	var dir := Base._temp_dir("rebirth")
	var gs := _game(dir)
	gs.new_world(5)
	_run(gs, 120)
	# Une espèce créée par Dieu doit entrer au Panthéon.
	var evs: Array = gs.apply_divine_action({type = "spawn_species", region = gs.parcel.cell, species_id = -1, radius = 4})
	var created_id := -1
	for ev in evs:
		if ev.type == "spawn":
			created_id = int(ev.species_id)
	var reborn := []
	gs.world_reborn.connect(func(info): reborn.append(info))
	var first_seed: int = gs.sim.seed
	var info: Dictionary = gs.reincarnate({seed = 77, ocean_fraction = 0.7, axial_tilt = 12.0, star_luminosity = 1.05, plates = 9})
	var out := ""
	var created_name := ""
	for e in gs.pantheon.entries:
		if e.created_by_god:
			created_name = e.name
	if reborn.size() != 1 or info.world_index != 2 or gs.sim.seed != 77 or gs.sim.seed == first_seed:
		out = "réincarnation : %s" % [info]
	elif gs.pantheon.entries.is_empty() or (created_id >= 0 and created_name == ""):
		out = "Panthéon vide ou création oubliée (%d entrées)" % gs.pantheon.entries.size()
	else:
		# Le Panthéon est sur disque et survit à une nouvelle session.
		var again := Pantheon.new(dir.path_join("pantheon"))
		if not again.load_from_disk() or again.entries.size() != gs.pantheon.entries.size() or again.worlds.size() != 1:
			out = "Panthéon non relu depuis le disque"
		else:
			var count: int = gs.pantheon.entries.size()
			_run(gs, 60)
			gs.reincarnate()
			if gs.pantheon.entries.size() < count or gs.pantheon.worlds.size() != 2 or gs.world_index != 3:
				out = "le Panthéon n'a pas survécu à la deuxième réincarnation"
			else:
				# Ressemer une espèce du Panthéon sur la nouvelle planète.
				var entry: Dictionary = gs.pantheon.entries[0]
				gs.reseed_from_pantheon(entry, gs.parcel.cell)
				var found := false
				for id in gs.sim.species:
					if gs.sim.species[id].name == entry.name and gs.sim.species[id].alive:
						found = gs.sim.species[id].traits.get("size") == entry.traits.get("size")
				if not found:
					out = "ressemis sans effet (%s)" % entry.name
	gs.free()
	Base._clean(dir.path_join("pantheon"))
	Base._clean(dir)
	return out


func test_end_of_times_summary() -> String:
	var dir := Base._temp_dir("end")
	var gs := _game(dir)
	gs.new_world(8)
	_run(gs, 40)
	var got := []
	gs.end_of_times.connect(func(s): got.append(s))
	gs._watch_event({type = "end_of_times", summary = "Le Soleil a tout brûlé."})
	gs._watch_event({type = "end_of_times"})
	var out := ""
	if got.size() != 1:
		out = "fin des temps annoncée %d fois" % got.size()
	else:
		for k in ["world_name", "world_index", "age_years", "species_total", "species_max_alive", "extinctions", "civilizations", "notable", "cause"]:
			if not got[0].has(k):
				out = "bilan sans %s" % k
		if out == "" and got[0].cause != "Le Soleil a tout brûlé.":
			out = "cause : %s" % got[0].cause
	gs.free()
	Base._clean(dir)
	return out
