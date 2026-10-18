extends RefCounted
## Tests de la simulation (src/sim/) : déterminisme, effet papillon, chaîne causale,
## (scénario court « cretaceous », départ à -66 Ma ; le prologue est testé dans test_sim_prologue.gd)
## timelines, émergence de la sapience, robustesse et performance.

const WorldSim := preload("res://src/sim/world_sim.gd")
const Eras := preload("res://src/sim/eras.gd")

const FRAME_YEARS := 1_000_000.0 / 60.0
const YUCATAN := Vector2i(60, 50)


func _meteor(sim: RefCounted, cell := YUCATAN) -> Array:
	return sim.apply_divine_action({type = "meteor", region = cell, species_id = -1, radius = 12})


## Avance d'au moins `years` années en suivant la compression du temps de chaque ère.
func _run(sim: RefCounted, years: float, until_era := -1) -> Array:
	var events := []
	var target: float = sim.year + years
	var guard := 0
	while sim.year < target and guard < 20000:
		guard += 1
		events.append_array(sim.step(minf(target - sim.year, sim.ideal_step_years() * sim.max_substeps)))
		if until_era >= 0 and sim.era_index() >= until_era:
			break
	return events


func _fingerprint(sim: RefCounted) -> String:
	var names := []
	for id in sim.species:
		names.append("%d:%s:%s:%.5f" % [id, sim.species[id].name, sim.species[id].alive, sim.species[id].population])
	return "%f|%d|%d|%d|%d|%d|%s|%d" % [sim.year, hash(sim.population), hash(sim.dominant_species),
		hash(sim.tech), hash(sim.temperature), hash(sim.elevation), ",".join(names), sim.causal_log.next_id]


func _clade(sim: RefCounted, id: int) -> String:
	return sim.species[id].traits.clade if id >= 0 else "aucune"


func _alive_clade(sim: RefCounted, clade: String) -> bool:
	for id in sim.get_alive_species():
		if sim.species[id].traits.clade == clade:
			return true
	return false


func test_world_generation_is_deterministic() -> String:
	var a := WorldSim.new(1234, true, WorldSim.SCENARIO_CRETACEOUS)
	var b := WorldSim.new(1234, true, WorldSim.SCENARIO_CRETACEOUS)
	var c := WorldSim.new(4321, true, WorldSim.SCENARIO_CRETACEOUS)
	if a.elevation != b.elevation or a.temperature != b.temperature or a.biome != b.biome:
		return "même graine, planètes différentes"
	if a.elevation == c.elevation:
		return "graines différentes, planètes identiques"
	var land := 0
	for e in a.elevation:
		if e >= 0.0:
			land += 1
	var frac := float(land) / a.elevation.size()
	if frac < 0.3 or frac > 0.42:
		return "part de terres inattendue : %.2f" % frac
	if a.species.size() < 10 or a.current_era() != "Mésozoïque":
		return "roster initial incorrect (%d espèces, %s)" % [a.species.size(), a.current_era()]
	return ""


func test_simulation_is_deterministic() -> String:
	var a := WorldSim.new(99, true, WorldSim.SCENARIO_CRETACEOUS)
	var b := WorldSim.new(99, true, WorldSim.SCENARIO_CRETACEOUS)
	var ev_a := []
	var ev_b := []
	for sim in [a, b]:
		var evs: Array = ev_a if sim == a else ev_b
		for i in 30:
			evs.append_array(sim.step(FRAME_YEARS * 6.0))
		evs.append_array(sim.apply_divine_action({type = "plague", region = Vector2i(128, 64), species_id = -1, radius = 10}))
		for i in 30:
			evs.append_array(sim.step(FRAME_YEARS * 6.0))
	if _fingerprint(a) != _fingerprint(b):
		return "deux mondes de même graine ont divergé"
	if ev_a.size() != ev_b.size():
		return "nombre d'événements différent (%d / %d)" % [ev_a.size(), ev_b.size()]
	for i in ev_a.size():
		if ev_a[i].summary != ev_b[i].summary or ev_a[i].id != ev_b[i].id:
			return "événement %d différent" % i
	return ""


func test_meteor_changes_history() -> String:
	var base := WorldSim.new(7, true, WorldSim.SCENARIO_CRETACEOUS)
	var with_meteor: RefCounted = base.fork()
	var without: RefCounted = base.fork()
	_meteor(with_meteor)
	_run(with_meteor, 12_000_000.0)
	_run(without, 12_000_000.0)
	var dom_m: int = with_meteor.get_dominant_species()
	var dom_n: int = without.get_dominant_species()
	print("  sans météore : %s (%s) | avec météore : %s (%s)" % [
		without.species[dom_n].name, _clade(without, dom_n), with_meteor.species[dom_m].name, _clade(with_meteor, dom_m)])
	if _alive_clade(with_meteor, "dinosaure"):
		return "des dinosaures non aviens ont survécu au météore"
	if not _alive_clade(without, "dinosaure") or _clade(without, dom_n) != "dinosaure":
		return "sans météore, les dinosaures devraient dominer (dominant : %s)" % _clade(without, dom_n)
	if _clade(with_meteor, dom_m) == "dinosaure":
		return "avec météore, l'espèce dominante ne devrait pas être un dinosaure"
	if with_meteor.current_era() != "Cénozoïque" or without.current_era() != "Mésozoïque":
		return "ères inattendues : %s / %s" % [with_meteor.current_era(), without.current_era()]
	return ""


func test_causal_chain_reaches_divine_action() -> String:
	var sim := WorldSim.new(3, true, WorldSim.SCENARIO_CRETACEOUS)
	var cons := _meteor(sim)
	var root: Dictionary = cons[0]
	if root.type != "divine_meteor" or root.cause_id != -1:
		return "la première conséquence doit être l'action divine racine"
	var extinction := {}
	for ev in cons:
		for key in ["year", "type", "region", "species_id", "summary", "cause_id", "id"]:
			if not ev.has(key):
				return "événement sans clé '%s'" % key
		if ev.type == "extinction":
			extinction = ev
	if extinction.is_empty():
		return "le météore n'a éteint aucune espèce"
	var chain: Array = sim.get_causal_chain(extinction.id)
	if chain.size() < 3 or chain[-1].id != root.id or chain[1].type != "impact":
		return "chaîne extinction -> impact -> météore attendue, obtenu %s" % str(chain.map(func(e): return e.type))
	# Conséquences différées : des événements futurs remontent jusqu'au même geste divin.
	var later := _run(sim, 4_000_000.0)
	var linked := 0
	var radiation_linked := false
	for ev in later:
		var c: Array = sim.get_causal_chain(ev.id)
		if not c.is_empty() and c[-1].id == root.id:
			linked += 1
			if ev.type == "radiation":
				radiation_linked = true
	if not radiation_linked or linked < 3:
		return "conséquences différées non reliées au météore (%d liées)" % linked
	return ""


func test_all_divine_actions() -> String:
	var base := WorldSim.new(11, true, WorldSim.SCENARIO_CRETACEOUS)
	_run(base, 1_000_000.0)
	var dom: int = base.get_dominant_species()
	var cell := Vector2i(-1, -1)
	for i in base.dominant_species.size():
		if base.dominant_species[i] == dom:
			@warning_ignore("integer_division")
			cell = Vector2i(i % WorldSim.WIDTH, i / WorldSim.WIDTH)
			break
	for type in ["meteor", "extinct", "save", "bless", "plague", "uplift", "flood", "ice_age", "spawn_species"]:
		var sim: RefCounted = base.fork()
		var cons: Array = sim.apply_divine_action({type = type, region = cell, species_id = dom, radius = 8})
		if cons.is_empty() or cons[0].type != "divine_" + type:
			return "%s : pas d'événement racine" % type
		if cons.size() < 2:
			return "%s : aucune conséquence immédiate" % type
		for ev in cons.slice(1):
			var c: Array = sim.get_causal_chain(ev.id)
			if c[-1].id != cons[0].id:
				return "%s : conséquence '%s' non reliée à l'action" % [type, ev.type]
		var later := _run(sim, 3_000_000.0)
		var delayed := 0
		for ev in later:
			var c: Array = sim.get_causal_chain(ev.id)
			if not c.is_empty() and c[-1].id == cons[0].id:
				delayed += 1
		if delayed == 0:
			return "%s : aucune conséquence différée" % type
	var ext: RefCounted = base.fork()
	ext.apply_divine_action({type = "extinct", region = cell, species_id = dom, radius = 4})
	if ext.species[dom].alive or ext.dominant_species.has(dom):
		return "extinct : l'espèce visée survit"
	return ""


func test_fork_is_independent() -> String:
	var sim := WorldSim.new(21, true, WorldSim.SCENARIO_CRETACEOUS)
	_run(sim, 500_000.0)
	var before := _fingerprint(sim)
	var f: RefCounted = sim.fork()
	if _fingerprint(f) != before:
		return "la copie diffère de l'original"
	_meteor(f)
	_run(f, 2_000_000.0)
	if _fingerprint(sim) != before:
		return "modifier la copie a altéré l'original"
	# Deux copies du même instant rejouent exactement le même futur.
	var g1: RefCounted = sim.fork()
	var g2: RefCounted = sim.fork()
	_run(g1, 1_000_000.0)
	_run(g2, 1_000_000.0)
	if _fingerprint(g1) != _fingerprint(g2):
		return "deux copies identiques ont divergé"
	return ""


func test_project_future_previews_without_side_effects() -> String:
	var sim := WorldSim.new(5, true, WorldSim.SCENARIO_CRETACEOUS)
	var before := _fingerprint(sim)
	var preview := sim.project_future(5_000_000.0)
	if _fingerprint(sim) != before:
		return "project_future a modifié le monde"
	for key in ["era", "era_reached", "dominant_species", "extinct_species", "sapient_species", "key_events", "to_year"]:
		if not preview.has(key):
			return "résumé sans clé '%s'" % key
	if absf(preview.to_year - (sim.year + 5_000_000.0)) > 1.0:
		return "année de projection incorrecte : %f" % preview.to_year
	# « Et si ? » : prévisualiser le météore sur une copie.
	var what_if: RefCounted = sim.fork()
	_meteor(what_if)
	var p2: Dictionary = what_if.project_future(3_000_000.0)
	if p2.dominant_species.clade == "dinosaure":
		return "après le météore, la projection ne doit pas montrer de dinosaures dominants"
	return ""


func test_huge_steps_are_robust() -> String:
	var sim := WorldSim.new(8, true, WorldSim.SCENARIO_CRETACEOUS)
	var y0 := sim.year
	sim.step(70_000_000.0)
	if absf(sim.year - (y0 + 70_000_000.0)) > 1.0:
		return "année incorrecte après un pas géant : %f" % sim.year
	if sim.last_substeps > sim.max_substeps:
		return "trop de sous-pas : %d" % sim.last_substeps
	sim.step(1.0e12)
	sim.step(0.0)
	sim.step(-5.0)
	for v in sim.population:
		if is_nan(v) or v < 0.0 or v > 1.0:
			return "densité invalide : %f" % v
	for v in sim.temperature:
		if is_nan(v):
			return "température NaN"
	if sim.current_era() == "":
		return "ère vide"
	return ""


func test_sapience_emerges_and_eras_advance() -> String:
	var mammals := WorldSim.new(7, true, WorldSim.SCENARIO_CRETACEOUS)
	_meteor(mammals)
	var events := _run(mammals, 70_000_000.0, Eras.FIRST_SAPIENT_ERA + 1)
	var sapient_ev := {}
	for ev in events:
		if ev.type == "sapience":
			sapient_ev = ev
			break
	if sapient_ev.is_empty() or mammals.era_index() < Eras.FIRST_SAPIENT_ERA + 1:
		return "aucune civilisation après le météore (ère : %s)" % mammals.current_era()
	var sid: int = sapient_ev.species_id
	print("  avec météore : %s (%s) conscients en %d, %s en %d" % [
		mammals.species[sid].name, _clade(mammals, sid), sapient_ev.year, mammals.current_era(), mammals.year])
	if _clade(mammals, sid) == "dinosaure":
		return "sapience dinosaurienne alors que le météore les a anéantis"
	var chain: Array = mammals.get_causal_chain(sapient_ev.id)
	if chain[-1].type != "divine_meteor":
		return "la sapience devrait remonter causalement jusqu'au météore"
	# Sans météore : la sapience n'est pas réservée aux primates.
	var saurians := WorldSim.new(7, true, WorldSim.SCENARIO_CRETACEOUS)
	var ev2 := _run(saurians, 70_000_000.0, Eras.FIRST_SAPIENT_ERA)
	for ev in ev2:
		if ev.type == "sapience":
			print("  sans météore : %s (%s) conscients en %d" % [saurians.species[ev.species_id].name, _clade(saurians, ev.species_id), ev.year])
			if _clade(saurians, ev.species_id) != "dinosaure":
				return "sans météore, les dinosaures devraient accéder à la sapience"
			return ""
	return "sans météore, aucune sapience"


func test_performance_benchmark() -> String:
	var sim := WorldSim.new(42, true, WorldSim.SCENARIO_CRETACEOUS)
	_run(sim, 2_000_000.0)
	var mt: float = sim.benchmark(120, FRAME_YEARS, true)
	var st: float = sim.benchmark(30, FRAME_YEARS, false)
	var late := WorldSim.new(42, true, WorldSim.SCENARIO_CRETACEOUS)
	_meteor(late)
	_run(late, 70_000_000.0, Eras.FIRST_SAPIENT_ERA + 4)
	var mt_late: float = late.benchmark(60, late.ideal_step_years(), true)
	print("  perf : %.2f ms/pas (%d coeurs, WorkerThreadPool) | %.2f ms/pas (1 coeur) | ère %s : %.2f ms/pas" % [
		mt, OS.get_processor_count(), st, late.current_era(), mt_late])
	if mt > 6.0:
		return "pas trop lent : %.2f ms" % mt
	return ""
