extends RefCounted
## Genèse (scénario par défaut) : planète vierge, semences dont la simulation juge le succès,
## tectonique des plaques (cycle du supercontinent, parcelle qui suit sa croûte, geste « drift »),
## ozone, Soleil vieillissant et fin des temps, statistiques planétaires, mémoire et budget.
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const WorldSim := preload("res://src/sim/world_sim.gd")
const Eras := preload("res://src/sim/eras.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")
const MapMath := preload("res://src/map/map_math.gd")
const GameStateScript := preload("res://src/core/game_state.gd")


func _fast(sim: RefCounted, until_year: float) -> Array:
	var events := []
	var guard := 0
	while sim.year < until_year and guard < 20000:
		guard += 1
		events.append_array(sim.step(minf(until_year - sim.year, sim.ideal_step_years() * sim.max_substeps)))
	return events


## Cellule (tiède) dont l'altitude actuelle est dans [lo, hi].
static func _cell(sim: RefCounted, lo: float, hi: float) -> Vector2i:
	for y in range(30, 98, 3):
		for x in range(0, WorldSim.WIDTH, 3):
			var i := y * WorldSim.WIDTH + x
			var e: float = sim.elevation[i]
			if e >= lo and e <= hi and sim.temperature[i] > 0.45 and sim.temperature[i] < 0.85:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _seed(sim: RefCounted, kind: String, cell: Vector2i, traits := {}) -> Array:
	return sim.apply_divine_action({type = "seed", kind = kind, region = cell, species_id = -1, radius = 4, traits = traits})


## Espèce créée par une semence (l'événement « seeding » porte son id).
static func _seeded_id(events: Array) -> int:
	for e in events:
		if e.type == "seeding":
			return int(e.species_id)
	return -1


static func _alive(sim: RefCounted, id: int) -> bool:
	return id >= 0 and sim.species.has(id) and bool(sim.species[id].alive)


func test_virgin_planet_stays_lifeless_without_seeds() -> String:
	var sim := WorldSim.new(5)
	if sim.year != WorldSim.GENESIS_START_YEAR or sim.scenario != WorldSim.SCENARIO_GENESIS:
		return "départ inattendu : %.0f, %s" % [sim.year, sim.scenario]
	if not sim.get_alive_species().is_empty() or sim.oxygen > 0.0:
		return "la planète vierge n'est pas vierge"
	var st: Dictionary = sim.planet_stats()
	if st.co2 < 1000.0 or st.oxygen > 0.0 or st.biodiversity != 0:
		return "atmosphère primitive attendue : %s" % str(st)
	_fast(sim, -3.0e9)
	if not sim.get_alive_species().is_empty() or sim.rebirths > 0:
		return "la vie est née toute seule"
	if sim.era_index() != Eras.ARCHEAN or sim.oxygen > 0.001:
		return "un monde sans vie a changé d'ère ou d'atmosphère (%s, O2 %.3f)" % [sim.current_era(), sim.oxygen]
	if sim.end_of_times:
		return "fin des temps prématurée"
	return ""


func test_genesis_is_deterministic() -> String:
	var prints := []
	for k in 2:
		var sim := WorldSim.new(9)
		_seed(sim, "light", _cell(sim, -0.25, -0.02))
		_seed(sim, "spark", _cell(sim, -0.6, -0.3))
		_fast(sim, -3.6e9)
		prints.append("%f|%d|%d|%d|%d|%d|%f" % [sim.year, sim.geography_version, hash(sim.elevation), hash(sim.plate_id),
			sim.causal_log.next_id, sim.get_alive_species().size(), sim.oxygen])
	if prints[0] != prints[1]:
		return "même graine, mondes différents :\n%s\n%s" % prints
	return ""


func test_light_triggers_great_oxidation() -> String:
	var sim := WorldSim.new(7)
	var cell := _cell(sim, -0.25, -0.02)
	if cell.x < 0:
		return "pas de haut-fond tiède"
	var evs := _seed(sim, "light", cell)
	var seeding := {}
	for e in evs:
		if e.type == "seeding":
			seeding = e
	if seeding.is_empty() or seeding.cause_id != evs[0].id:
		return "pas d'événement de semence relié au geste divin"
	_fast(sim, -1.4e9)
	print("  Grande Oxydation à %.0f Ma, oxygène %.3f, %d espèces" % [
		float(sim.era_years.get(Eras.GREAT_OXIDATION, NAN)) / 1e6, sim.oxygen, sim.get_alive_species().size()])
	if not sim.era_years.has(Eras.GREAT_OXIDATION) or sim.oxygen <= 0.001:
		return "la lumière semée n'a pas oxygéné le monde"
	return ""


func test_spore_needs_ozone_and_germ_needs_oxygen() -> String:
	var sim := WorldSim.new(11)
	var land := _cell(sim, 0.05, 0.4)
	var sea := _cell(sim, -0.25, -0.02)
	if land.x < 0 or sea.x < 0:
		return "terres ou hauts-fonds introuvables"
	var spore := _seeded_id(_seed(sim, "spore", land))
	var germ := _seeded_id(_seed(sim, "animal_germ", sea, {role = "brouteur"}))
	if spore < 0 or germ < 0:
		return "semences non créées (%d, %d)" % [spore, germ]
	if sim.species[spore].traits.habitat != "land" or float(sim.species[germ].traits.complexity) < 3.0:
		return "traits de semence inattendus : %s / %s" % [str(sim.species[spore].traits.habitat), str(sim.species[germ].traits.complexity)]
	for k in 30:
		sim.step(sim.ideal_step_years())
	if _alive(sim, spore):
		return "une spore a survécu sans couche d'ozone (ozone %.2f)" % sim.ozone
	if _alive(sim, germ):
		return "un germe d'animal a survécu sans oxygène"
	for k in 3:
		sim.apply_divine_action({type = "oxygenate", region = sea, species_id = -1, radius = 8})
	sim.step(sim.ideal_step_years())
	if sim.ozone < 0.5:
		return "l'oxygène ne fait pas d'ozone (%.2f)" % sim.ozone
	var spore2 := _seeded_id(_seed(sim, "spore", land))
	# L'oxygène soufflé par Dieu retombe (rien ne l'entretient) : on juge la spore tant qu'il protège.
	for k in 3:
		sim.step(sim.ideal_step_years())
	if not _alive(sim, spore2) or int(sim.species[spore2].regions) < 1:
		return "une spore n'a pas pris malgré la couche d'ozone"
	return ""


func test_supercontinent_forms_then_breaks_up() -> String:
	var sim := WorldSim.new(7)
	var best_super := 0.0
	var after := 1.0
	var phases := []
	while sim.year < -1.0e9:
		sim.step(sim.ideal_step_years())
		var ph: String = sim.tectonics_phase()
		if phases.is_empty() or phases[-1] != ph:
			phases.append(ph)
		if ph == "supercontinent":
			best_super = maxf(best_super, sim.supercontinent_fraction)
		elif ph == "dispersal" and best_super >= 0.6:
			after = minf(after, sim.supercontinent_fraction)
		if not is_finite(sim.supercontinent_fraction) or not is_finite(sim.sea_level):
			return "valeur non finie"
	print("  phases : %s ; plus grande masse %.2f puis %.2f" % [" → ".join(phases.slice(0, 8)), best_super, after])
	if best_super < 0.6:
		return "aucun supercontinent (plus grande masse %.2f)" % best_super
	if after > 0.5:
		return "le supercontinent ne se fracture pas (%.2f après)" % after
	for i in range(0, sim.elevation.size(), 97):
		if not is_finite(sim.elevation[i]) or not is_finite(sim.temperature[i]):
			return "NaN dans les grilles"
	return ""


func test_parcel_follows_its_crust() -> String:
	var sim := WorldSim.new(7)
	var start := _cell(sim, 0.05, 0.4)
	var parcel := ParcelSim.new(sim, start)
	var anchor: Dictionary = sim.make_anchor(start)
	var version: int = sim.geography_version
	while sim.year < -3.6e9:
		parcel.update(sim.step(sim.ideal_step_years()))
	if sim.geography_version == version:
		return "la géographie n'a pas changé"
	var expected: Vector2i = sim.anchor_cell(anchor)
	if parcel.cell != expected:
		return "la parcelle n'est pas sur sa croûte : %s au lieu de %s" % [str(parcel.cell), str(expected)]
	var dx := absi(parcel.cell.x - start.x)
	dx = mini(dx, WorldSim.WIDTH - dx)
	if dx + absi(parcel.cell.y - start.y) < 3:
		return "la croûte n'a pas bougé (%s -> %s)" % [str(start), str(parcel.cell)]
	if sim.crust_elevation(parcel.cell.y * WorldSim.WIDTH + parcel.cell.x) < -0.35:
		return "la parcelle a quitté la croûte continentale"
	print("  parcelle %s -> %s en 400 Ma" % [str(start), str(parcel.cell)])
	return ""


func test_divine_drift_changes_geography() -> String:
	var a := WorldSim.new(4)
	var b := WorldSim.new(4)
	var cell := _cell(a, 0.05, 0.4)
	var evs: Array = b.apply_divine_action({type = "drift", region = cell, species_id = -1, radius = 4, target = cell + Vector2i(80, 0)})
	var drift := {}
	for e in evs:
		if e.type == "drift":
			drift = e
	if drift.is_empty() or drift.cause_id != evs[0].id:
		return "le geste drift n'est pas tracé"
	_fast(a, -3.75e9)
	_fast(b, -3.75e9)
	var differ := 0
	for i in a.elevation.size():
		if (a.elevation[i] >= 0.0) != (b.elevation[i] >= 0.0):
			differ += 1
	var share := float(differ) / a.elevation.size()
	print("  après 250 Ma : %.1f %% des cellules ont changé de terre en mer ou l'inverse" % (share * 100.0))
	if share < 0.02:
		return "la poussée d'une plaque ne change pas durablement la géographie (%.3f)" % share
	return ""


func test_sun_makes_planet_uninhabitable() -> String:
	var sim := WorldSim.new(2)
	_seed(sim, "light", _cell(sim, -0.25, -0.02))
	var ends := 0
	var hab_now: float = sim.habitability
	var guard := 0
	while sim.year < 5.0e9 and guard < 20000:
		guard += 1
		for e in sim.step(minf(5.0e9 - sim.year, 1.0e8)):
			if e.type == "end_of_times":
				ends += 1
	print("  à %+.1f Ga : habitabilité %.2f, Soleil %.2f, mer %.2f, %d espèces, fin des temps %d" % [
		sim.year / 1e9, sim.habitability, sim.sun_luminosity, sim.sea_level, sim.get_alive_species().size(), ends])
	if hab_now <= 0.5 or sim.habitability > 0.0:
		return "habitabilité : %.2f au départ, %.2f à +5 Ga" % [hab_now, sim.habitability]
	if not sim.get_alive_species().is_empty():
		return "de la vie survit sous le Soleil de +5 Ga"
	if ends != 1 or not sim.end_of_times:
		return "événement end_of_times émis %d fois" % ends
	sim.step(1.0e8)
	return ""


func test_planet_stats_and_bounded_memory() -> String:
	var sim := WorldSim.new(6)
	_seed(sim, "light", _cell(sim, -0.25, -0.02))
	_seed(sim, "spark", _cell(sim, -0.6, -0.3))
	_fast(sim, -0.5e9)
	var st: Dictionary = sim.planet_stats()
	for key in ["global_temperature_c", "ozone", "oxygen", "co2", "methane", "sea_level", "ice_cover",
			"biomass", "biodiversity", "recent_extinctions", "sun_luminosity", "habitability"]:
		if not st.has(key):
			return "statistique manquante : " + key
		if typeof(st[key]) == TYPE_FLOAT and not is_finite(st[key]):
			return "statistique non finie : " + key
	var mem: Dictionary = sim.memory_report()
	print("  stats %s\n  mémoire %s" % [str(st), str(mem)])
	if sim.planet_history.size() < 10 or sim.planet_history.size() > WorldSim.PLANET_HISTORY_SIZE:
		return "historique planétaire : %d échantillons" % sim.planet_history.size()
	for k in range(1, sim.planet_history.size()):
		if sim.planet_history[k].year < sim.planet_history[k - 1].year:
			return "historique planétaire non chronologique"
	if mem.species_records > WorldSim.MAX_SPECIES_RECORDS or mem.history > 4608 or mem.craters > 32:
		return "mémoire non bornée : %s" % str(mem)
	return ""


func test_step_budget_in_real_play() -> String:
	var sim := WorldSim.new(8)
	_seed(sim, "light", _cell(sim, -0.25, -0.02))
	var t := 0.0
	var total := 0
	var worst := 0
	var frames := 900
	for f in frames:
		var pace := GameStateScript.opening_pace(t)
		var t0 := Time.get_ticks_usec()
		sim.step(MapMath.base_years_per_second(sim.ideal_step_years()) * pace / 60.0)
		var spent := Time.get_ticks_usec() - t0
		total += spent
		worst = maxi(worst, spent)
		t += 1.0 / 60.0
		# Rythme d'une vraie partie (60 images/s) : le recalcul de la géographie tourne pendant ce temps.
		OS.delay_usec(maxi(0, 16667 - spent))
	var mean := total / 1000.0 / frames
	print("  step() en partie réelle : %.2f ms en moyenne, %.1f ms au pire (%d recalculs de géographie)" % [
		mean, worst / 1000.0, sim.geography_version])
	if mean > 6.0 or worst / 1000.0 > 50.0:
		return "budget de step() dépassé (%.2f ms en moyenne, %.1f ms au pire)" % [mean, worst / 1000.0]
	return ""


func test_parcel_works_anywhere() -> String:
	var sim := WorldSim.new(3)
	var spots := {abysses = _cell(sim, -1.0, -0.5), haut_fond = _cell(sim, -0.25, -0.02), terre = _cell(sim, 0.05, 0.4)}
	for y in [2, 125]:
		spots["pôle %d" % y] = Vector2i(40, y)
	for key in spots:
		var c: Vector2i = spots[key]
		if c.x < 0:
			continue
		var p := ParcelSim.new(sim, c)
		for k in 5:
			p.update(sim.step(sim.ideal_step_years()))
		if not p.land_use in ParcelSim.LAND_USES or p.land_use_label == "":
			return "%s : usage %s" % [key, p.land_use]
	return ""
