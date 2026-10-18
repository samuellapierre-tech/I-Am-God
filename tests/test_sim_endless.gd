extends RefCounted
## Mode Éternité (WorldSim.endless) : l'histoire continue après la post-singularité (exode,
## effondrements, âge des héritiers, nouveaux éveils), la vie renaît après une extinction totale,
## la mémoire reste bornée ; mode Épreuve (set_endless(false)) sans ces cycles. Parcelle de départ
## du prologue : un estran à stromatolites qui émerge et que la vie conquiert.
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const WorldSim := preload("res://src/sim/world_sim.gd")
const Eras := preload("res://src/sim/eras.gd")
const Species := preload("res://src/sim/species.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")
const Causality := preload("res://src/sim/causality.gd")
const MapMath := preload("res://src/map/map_math.gd")
const GameStateScript := preload("res://src/core/game_state.gd")


## Partie accélérée : 400 pas idéaux par appel (plafonnés à 2 Ma), chaque ère reste traversée.
func _accelerated(sim: RefCounted) -> Array[Dictionary]:
	return sim.step(minf(sim.ideal_step_years() * 400.0, 2.0e6))


func _fast(sim: RefCounted, until_year: float) -> void:
	var guard := 0
	while sim.year < until_year and guard < 20000:
		guard += 1
		sim.step(minf(until_year - sim.year, sim.ideal_step_years() * sim.max_substeps))


func test_endless_future_is_bounded() -> String:
	var sim := WorldSim.new(7, true, WorldSim.SCENARIO_CRETACEOUS)
	var parcel := ParcelSim.new(sim, Vector2i(70, 40))
	var singularity := NAN
	var counts := {}
	var peak := {species_records = 0, history = 0, pinned = 0, scheduled = 0, alive = 0}
	var calls := 0
	while calls < 6000 and (is_nan(singularity) or sim.year < singularity + 400.0e6):
		calls += 1
		var evs := _accelerated(sim)
		for e in evs:
			counts[e.type] = int(counts.get(e.type, 0)) + 1
		parcel.update(evs)
		if is_nan(singularity) and sim.era_index() == Eras.LAST_ERA:
			singularity = sim.year
		if sim.current_era() == "" or sim.era_index() < 0 or sim.era_index() > Eras.AFTERMATH:
			return "ère invalide : %d" % sim.era_index()
		var mem: Dictionary = sim.memory_report()
		for key in peak:
			peak[key] = maxi(int(peak[key]), int(mem[key]))
		if parcel.history.size() > ParcelSim.HISTORY_SIZE or parcel.fauna.size() > ParcelSim.MAX_FAUNA:
			return "parcelle non bornée"
	print("  post-singularité à %.1f Ma ; arrivée à %+.0f Ma en %d appels ; %d cycles, %d renaissances" % [
		singularity / 1e6, sim.year / 1e6, calls, sim.cycles, sim.rebirths])
	print("  exodes %d, effondrements %d, éveils %d ; pics mémoire %s" % [counts.get("exodus", 0),
		counts.get("collapse", 0), counts.get("sapience", 0), str(peak)])
	if is_nan(singularity):
		return "post-singularité jamais atteinte"
	if sim.year < singularity + 300.0e6:
		return "la partie n'a pas dépassé la post-singularité de 300 Ma (%+.0f Ma)" % (sim.year / 1e6)
	if int(counts.get("exodus", 0)) < 1 or sim.cycles < 1:
		return "aucun cycle : pas d'exode ni d'âge des héritiers"
	if int(counts.get("sapience", 0)) < 2:
		return "aucune nouvelle lignée consciente après la première civilisation"
	if peak.species_records > WorldSim.MAX_SPECIES_RECORDS or peak.alive > 128:
		return "registre d'espèces non borné : %s" % str(peak)
	if peak.history > Causality.MAX_HISTORY + Causality.TRIM_BATCH or peak.pinned > Causality.MAX_PINNED:
		return "journal causal non borné : %s" % str(peak)
	if peak.scheduled > 500:
		return "conséquences différées qui s'accumulent : %d" % peak.scheduled
	return ""


func test_endless_is_deterministic() -> String:
	var a := WorldSim.new(3, true, WorldSim.SCENARIO_CRETACEOUS)
	var b := WorldSim.new(3, true, WorldSim.SCENARIO_CRETACEOUS)
	for k in 400:
		_accelerated(a)
		_accelerated(b)
	var fa := "%f|%d|%d|%d|%s" % [a.year, a.cycles, a.causal_log.next_id, a.get_alive_species().size(), a.current_era()]
	var fb := "%f|%d|%d|%d|%s" % [b.year, b.cycles, b.causal_log.next_id, b.get_alive_species().size(), b.current_era()]
	if fa != fb:
		return "même graine, futurs différents :\n%s\n%s" % [fa, fb]
	return ""


func test_trial_mode_has_no_exodus() -> String:
	var sim := WorldSim.new(7, true, WorldSim.SCENARIO_CRETACEOUS)
	sim.set_endless(false)
	var guard := 0
	while sim.era_index() < Eras.LAST_ERA and guard < 3000:
		guard += 1
		_accelerated(sim)
	if sim.era_index() != Eras.LAST_ERA:
		return "post-singularité non atteinte en mode Épreuve"
	for k in 200:
		for e in _accelerated(sim):
			if e.type == "exodus":
				return "exode en mode Épreuve"
	if sim.get_sapient_species().is_empty():
		return "la civilisation a disparu en mode Épreuve"
	return ""


func test_life_restarts_after_total_extinction_of_complex_life() -> String:
	var sim := WorldSim.new(11)
	_fast(sim, -300.0e6)
	if sim.max_complexity < 4.0:
		return "pas de vie complexe à -300 Ma (complexité %.0f)" % sim.max_complexity
	# Dieu anéantit toute la vie complexe : il ne reste que microbes, algues et plantes.
	for id in sim.get_alive_species():
		if sim.species.has(id) and sim.species[id].alive and float(sim.species[id].traits.complexity) >= 3.0:
			sim.apply_divine_action({type = "extinct", region = Vector2i(128, 64), species_id = id, radius = 4})
	var reborn := false
	for e in sim.step(sim.ideal_step_years()):
		reborn = reborn or e.type == "rebirth"
	if sim.max_complexity >= 3.0:
		return "la vie complexe a survécu (complexité %.0f)" % sim.max_complexity
	if not reborn or sim.rebirths < 1:
		return "pas d'événement de renaissance"
	_fast(sim, sim.year + 400.0e6)
	print("  400 Ma après l'hécatombe : complexité %s, %d espèces" % [sim.complexity_name(), sim.get_alive_species().size()])
	if sim.max_complexity < 3.0:
		return "la vie complexe n'est pas revenue (%s)" % sim.complexity_name()
	return ""


func test_life_reappears_on_a_dead_world_only_in_endless_mode() -> String:
	for endless in [true, false]:
		var sim := WorldSim.new(5)
		sim.set_endless(endless)
		_fast(sim, -3.5e9)
		for id in sim.get_alive_species():
			sim.apply_divine_action({type = "extinct", region = Vector2i(128, 64), species_id = id, radius = 4})
		_fast(sim, sim.year + 60.0e6)
		var alive := not sim.get_alive_species().is_empty()
		if endless and (not alive or sim.rebirths < 1):
			return "la vie ne renaît pas d'un monde stérile en mode Éternité"
		if not endless and alive:
			return "la vie renaît en mode Épreuve"
	return ""


func test_start_parcel_is_a_tidal_flat_that_emerges() -> String:
	var sim := WorldSim.new(7)
	var cell := ParcelSim.pick_start_cell(sim)
	var parcel := ParcelSim.new(sim, cell)
	if parcel.shore == "land" or parcel.land_use != "microbial_mat":
		return "départ : %s / %s (attendu : sous l'eau ou estran, tapis microbiens)" % [parcel.shore, parcel.land_use]
	var shores := [parcel.shore]
	var uses := {}
	var dinos := false
	var t := 0.0
	var events := []
	while sim.year < Eras.CRETACEOUS_END and t < 3600.0:
		var pace := 1.0 if not sim.get_sapient_species().is_empty() else GameStateScript.opening_pace(t)
		events.append_array(parcel.update(sim.step(MapMath.base_years_per_second(sim.ideal_step_years()) * pace * 0.25)))
		t += 0.25
		if parcel.shore != shores[-1]:
			shores.append(parcel.shore)
		uses[parcel.land_use] = true
		for f in parcel.fauna:
			dinos = dinos or f.clade == "dinosaure"
	print("  rivage : %s ; usages : %s" % [" → ".join(shores), ", ".join(uses.keys())])
	if shores[-1] != "land" or not shores.has("intertidal"):
		return "la parcelle n'émerge pas en passant par l'estran : %s" % " → ".join(shores)
	if shores.size() > 12:
		return "le rivage bat sans cesse (%d changements)" % shores.size()
	if not uses.has("barren") or not (uses.has("wild") or uses.has("swamp_forest")):
		return "la terre émergée n'est pas conquise par les plantes : %s" % str(uses.keys())
	if not dinos:
		return "aucun dinosaure sur la parcelle avant -66 Ma"
	return preload("res://tests/test_parcel.gd").check_events(events)
