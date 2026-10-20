extends RefCounted
## Prologue (départ à -3,8 Ga) : microbes marins au départ, étapes déclenchées par l'état du monde
## et enchaînées sans intervention, dinosaures avant -66 Ma, rythme à x1 avec l'ouverture lente de
## GameState, interventions qui changent durablement l'issue, pouvoirs actifs, parcelle.
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const WorldSim := preload("res://src/sim/world_sim.gd")
const Eras := preload("res://src/sim/eras.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")
const MapMath := preload("res://src/map/map_math.gd")
const GameStateScript := preload("res://src/core/game_state.gd")

## Pas de la boucle du HUD simulée (secondes réelles) : 4 appels par seconde suffisent, le modèle
## étant indépendant du découpage du temps.
const FRAME := 0.25


func _fast(sim: RefCounted, until_year: float) -> void:
	var guard := 0
	while sim.year < until_year and guard < 20000:
		guard += 1
		sim.step(minf(until_year - sim.year, sim.ideal_step_years() * sim.max_substeps))


## Boucle du HUD à x1 : MapMath.base_years_per_second(ideal) × GameState.opening_pace(temps de jeu)
## tant qu'aucun peuple n'est conscient. Renvoie {mesozoic_time, end_time, dinos_before_66, ...}.
func _play(seed_value: int) -> Dictionary:
	var sim := WorldSim.new(seed_value, true, WorldSim.SCENARIO_PROLOGUE)
	var t := 0.0
	var res := {sim = sim, mesozoic_time = -1.0, end_time = -1.0, dino_year = NAN, sapience_year = NAN}
	while sim.year < Eras.CRETACEOUS_END and t < 3600.0:
		var pace := 1.0 if not sim.get_sapient_species().is_empty() else GameStateScript.opening_pace(t)
		for ev in sim.step(MapMath.base_years_per_second(sim.ideal_step_years()) * pace * FRAME):
			if ev.type == "clade" and is_nan(res.dino_year) and sim.species.has(ev.species_id) \
					and sim.species[ev.species_id].traits.clade == "dinosaure":
				res.dino_year = ev.year
			if ev.type == "sapience" and is_nan(res.sapience_year):
				res.sapience_year = ev.year
		t += FRAME
		if res.mesozoic_time < 0.0 and sim.era_index() >= Eras.MESOZOIC:
			res.mesozoic_time = t
		if not is_nan(res.sapience_year):
			break
	res.end_time = t
	return res


func test_starts_with_marine_microbes() -> String:
	var sim := WorldSim.new(7, true, WorldSim.SCENARIO_PROLOGUE)
	if sim.year != WorldSim.PROLOGUE_START_YEAR or sim.era_index() != Eras.ARCHEAN:
		return "départ inattendu : %.0f, ère %s" % [sim.year, sim.current_era()]
	if sim.current_period() != "Archéen" or sim.current_era() != "Archéen":
		return "période : %s" % sim.current_period()
	if sim.oxygen > 0.0 or sim.land_flora > 0.0 or sim.max_complexity > 0.0:
		return "planète trop vivante au départ"
	for id in sim.get_alive_species():
		var t: Dictionary = sim.species[id].traits
		if t.clade != "microbe" or t.habitat != "marine":
			return "espèce de départ inattendue : %s (%s, %s)" % [sim.species[id].name, t.clade, t.habitat]
	var dom := sim.get_dominant_species()
	if dom < 0:
		return "aucune vie dominante (la vie marine doit compter)"
	return ""


func test_prologue_is_deterministic() -> String:
	var a := WorldSim.new(5, true, WorldSim.SCENARIO_PROLOGUE)
	var b := WorldSim.new(5, true, WorldSim.SCENARIO_PROLOGUE)
	_fast(a, -1.5e9)
	_fast(b, -1.5e9)
	var fa := "%f|%f|%s|%d|%d" % [a.year, a.oxygen, str(a.era_years), a.causal_log.next_id, a.get_alive_species().size()]
	var fb := "%f|%f|%s|%d|%d" % [b.year, b.oxygen, str(b.era_years), b.causal_log.next_id, b.get_alive_species().size()]
	if fa != fb:
		return "même graine, prologues différents :\n%s\n%s" % [fa, fb]
	return ""


func test_stages_follow_and_pace_at_x1() -> String:
	for seed_value in [7, 2024]:
		var r := _play(seed_value)
		var sim: RefCounted = r.sim
		var stages := []
		for k in range(Eras.ARCHEAN, Eras.MESOZOIC + 1):
			if sim.era_years.has(k):
				stages.append("%s %.0f Ma" % [Eras.NAMES[k], sim.era_years[k] / 1e6])
		print("  graine %d : %s" % [seed_value, " → ".join(stages)])
		print("    prologue %.0f s à x1, acte I %.0f s ; premier dinosaure %.0f Ma" % [
			r.mesozoic_time, r.end_time - r.mesozoic_time, r.dino_year / 1e6])
		# Les étapes indispensables se suivent dans l'ordre, sans intervention.
		var prev := -INF
		for k in [Eras.GREAT_OXIDATION, Eras.CAMBRIAN, Eras.LAND_CONQUEST, Eras.CARBONIFEROUS, Eras.MESOZOIC]:
			if not sim.era_years.has(k):
				return "graine %d : étape %s jamais atteinte" % [seed_value, Eras.NAMES[k]]
			if float(sim.era_years[k]) < prev:
				return "graine %d : étape %s hors d'ordre" % [seed_value, Eras.NAMES[k]]
			prev = sim.era_years[k]
		# Dates proches de l'histoire réelle (larges : ce sont des conséquences, pas des dates).
		var goe: float = sim.era_years[Eras.GREAT_OXIDATION]
		var cambrian: float = sim.era_years[Eras.CAMBRIAN]
		if goe < -3.0e9 or goe > -1.9e9:
			return "graine %d : Grande Oxydation à %.0f Ma" % [seed_value, goe / 1e6]
		if cambrian < -1.0e9 or cambrian > -0.4e9:
			return "graine %d : explosion cambrienne à %.0f Ma" % [seed_value, cambrian / 1e6]
		if is_nan(r.dino_year) or r.dino_year > Eras.CRETACEOUS_END:
			return "graine %d : pas de dinosaures avant -66 Ma" % seed_value
		if r.mesozoic_time < 600.0 or r.mesozoic_time > 900.0:
			return "graine %d : prologue de %.0f s à x1 (cible 600-900)" % [seed_value, r.mesozoic_time]
		if is_nan(r.sapience_year):
			var act_one: float = r.end_time - r.mesozoic_time
			if act_one < 900.0 or act_one > 1500.0:
				return "graine %d : Trias → Crétacé en %.0f s à x1 (cible 900-1500)" % [seed_value, act_one]
	return ""


func test_preventing_oxidation_changes_the_outcome() -> String:
	var base := WorldSim.new(7, true, WorldSim.SCENARIO_PROLOGUE)
	var held := WorldSim.new(7, true, WorldSim.SCENARIO_PROLOGUE)
	_fast(base, -3.2e9)
	_fast(held, -3.2e9)
	# Dieu anéantit les cyanobactéries et réveille les volcans : le fer et les gaz réducteurs
	# continuent d'absorber le peu d'oxygène qui reparaîtra.
	for id in held.get_alive_species():
		if bool(held.species[id].traits.get("oxygenic", false)):
			held.apply_divine_action({type = "extinct", region = Vector2i(60, 64), species_id = id, radius = 4})
	held.apply_divine_action({type = "volcano", region = Vector2i(60, 64), species_id = -1, radius = 8})
	_fast(base, -0.4e9)
	_fast(held, -0.4e9)
	var goe_base: float = base.era_years.get(Eras.GREAT_OXIDATION, INF)
	var goe_held: float = held.era_years.get(Eras.GREAT_OXIDATION, INF)
	print("  sans geste : Grande Oxydation %.0f Ma, ère %s à -400 Ma, complexité %s" % [goe_base / 1e6, base.current_era(), base.complexity_name()])
	print("  cyanobactéries anéanties : Grande Oxydation %.0f Ma, ère %s à -400 Ma, complexité %s" % [goe_held / 1e6, held.current_era(), held.complexity_name()])
	if goe_held < goe_base + 150.0e6:
		return "la Grande Oxydation n'est pas durablement retardée (%.0f / %.0f Ma)" % [goe_base / 1e6, goe_held / 1e6]
	if held.era_index() >= base.era_index() and held.max_complexity >= base.max_complexity:
		return "à -400 Ma, le monde où l'oxydation a été freinée n'est pas en retard"
	return ""


func test_divine_powers_act_during_prologue() -> String:
	var sim := WorldSim.new(11, true, WorldSim.SCENARIO_PROLOGUE)
	_fast(sim, -3.0e9)
	var cell := Vector2i(120, 60)
	for type in ["meteor", "flood", "bless", "spawn_species", "plague", "save", "uplift", "extinct", "soothe"]:
		var evs: Array = sim.apply_divine_action({type = type, region = cell, species_id = -1, radius = 8})
		if evs.is_empty() or not String(evs[0].type).begins_with("divine_"):
			return "action %s sans événement racine" % type
		sim.step(sim.ideal_step_years())
	var before: float = sim.oxygen
	sim.apply_divine_action({type = "oxygenate", region = cell, species_id = -1, radius = 8})
	if sim.oxygen <= before:
		return "le souffle d'oxygène ne change rien"
	before = sim.oxygen
	sim.apply_divine_action({type = "volcano", region = cell, species_id = -1, radius = 8})
	if sim.oxygen >= before:
		return "les volcans n'abaissent pas l'oxygène"
	# Un âge glaciaire divin peut geler toute la planète.
	sim.apply_divine_action({type = "ice_age", region = cell, species_id = -1, radius = 30})
	var frozen := false
	for k in 4:
		sim.step(sim.ideal_step_years())
		frozen = frozen or sim.snowball
	if not frozen:
		return "l'âge glaciaire divin ne déclenche pas de Terre boule de neige"
	if sim.get_alive_species().is_empty():
		return "toute vie a disparu"
	return ""


func test_parcel_shows_living_sea_and_barren_land() -> String:
	var sim := WorldSim.new(7, true, WorldSim.SCENARIO_PROLOGUE)
	_fast(sim, -3.5e9)
	var sea := Vector2i(-1, -1)
	var land := Vector2i(-1, -1)
	for y in range(20, 108, 4):
		for x in range(0, WorldSim.WIDTH, 4):
			var e: float = sim.elevation[y * WorldSim.WIDTH + x]
			if sea.x < 0 and e < 0.0 and e > -0.3 and sim.temperature[y * WorldSim.WIDTH + x] > 0.4:
				sea = Vector2i(x, y)
			if land.x < 0 and e > 0.1:
				land = Vector2i(x, y)
	var ps := ParcelSim.new(sim, sea)
	if not ps.land_use in ["microbial_mat", "seabed"]:
		return "mer de l'Archéen : %s" % ps.land_use
	if ps.fauna.is_empty() or ps.fauna[0].role != "producer" or ps.fauna[0].habitat != "marine":
		return "la mer devrait grouiller de microbes : %s" % str(ps.fauna)
	var pl := ParcelSim.new(sim, land)
	if pl.land_use != "barren" or pl.vegetation > 0.01 or not pl.fauna.is_empty():
		return "terre de l'Archéen : %s, végétation %.2f, %d espèces" % [pl.land_use, pl.vegetation, pl.fauna.size()]
	if pl.land_use_label != "Terres nues" or ps.land_use_label == "":
		return "libellés : %s / %s" % [pl.land_use_label, ps.land_use_label]
	return ""
