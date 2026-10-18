extends RefCounted
## Tests du contrat ParcelSim (src/sim/parcel_sim.gd) : champs présents, déterminisme, historique,
## indépendance de la cadence d'appel, coût. La dynamique (hystérésis, cratère, progression d'un
## peuple) est testée dans tests/test_parcel_sim.gd.
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const WorldSim := preload("res://src/sim/world_sim.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")

const CELL := Vector2i(70, 40)
const FAUNA_KEYS := ["species_id", "name", "count", "density", "trend", "role", "size", "clade"]
const HISTORY_KEYS := ["year", "temperature_c", "global_temperature_c", "population_total", "population"]
const ALERT_KEYS := ["kind", "species_id", "severity", "summary"]
const ROLES := ["herbivore", "carnivore", "omnivore", "sapient", "producer"]
const STRUCTURE_KINDS := ["field", "hut", "road", "building", "tower", "ruin"]


func _advance(sim: RefCounted, parcel: RefCounted, frames: int) -> Array:
	var events := []
	for i in frames:
		events.append_array(parcel.update(sim.step(sim.ideal_step_years() * sim.max_substeps)))
	return events


func _check_state(parcel: RefCounted) -> String:
	if not parcel.land_use in ParcelSim.LAND_USES:
		return "usage du sol inconnu : " + parcel.land_use
	if parcel.biome == "" or parcel.land_use_label == "":
		return "biome ou libellé vide"
	if not (is_finite(parcel.temperature_c) and is_finite(parcel.global_temperature_c)):
		return "température invalide"
	for v in [parcel.vegetation, parcel.water, parcel.tech]:
		if not (v >= 0.0 and v <= 1.0):
			return "valeur 0..1 hors bornes : %s" % str(v)
	if parcel.fauna.size() > ParcelSim.MAX_FAUNA:
		return "trop d'espèces : %d" % parcel.fauna.size()
	for f in parcel.fauna:
		for key in FAUNA_KEYS:
			if not f.has(key):
				return "champ de faune manquant : " + key
		if f.count <= 0 or f.count > ParcelSim.MAX_VISIBLE:
			return "nombre d'individus hors bornes : %d" % f.count
		if not f.trend in [-1, 0, 1]:
			return "tendance invalide : %s" % str(f.trend)
		if not f.role in ROLES:
			return "rôle invalide : %s" % str(f.role)
		if f.density < 0.0 or f.density > 1.0 or f.size < 0.0 or f.size > 1.0:
			return "densité ou taille hors bornes"
	for s in parcel.structures:
		if not s.kind in STRUCTURE_KINDS:
			return "structure inconnue : %s" % str(s.kind)
		if s.pos.x < 0.0 or s.pos.x > 1.0 or s.pos.y < 0.0 or s.pos.y > 1.0:
			return "structure hors parcelle : %s" % str(s.pos)
	for a in parcel.alerts:
		for key in ALERT_KEYS:
			if not a.has(key):
				return "champ d'alerte manquant : " + key
		if a.severity < 0.0 or a.severity > 1.0:
			return "gravité hors bornes : %s" % str(a.severity)
	for h in parcel.history:
		for key in HISTORY_KEYS:
			if not h.has(key):
				return "champ d'historique manquant : " + key
	return ""


## Format des événements de parcelle (narrateur, HUD).
static func check_events(events: Array) -> String:
	for e in events:
		for key in ["year", "type", "region", "species_id", "summary", "cause_id", "id"]:
			if not e.has(key):
				return "champ d'événement manquant : %s (%s)" % [key, str(e)]
		if not String(e.type).begins_with("parcel_"):
			return "type non préfixé : " + String(e.type)
		var s := String(e.summary)
		if s == "" or (s.contains("%") and not s.contains(" %)")) or s.contains("{"):
			return "résumé mal formé : « %s »" % s
		if s.substr(0, 1) != s.substr(0, 1).to_upper():
			return "résumé sans majuscule : « %s »" % s
		if not s.ends_with("."):
			return "résumé sans point final : « %s »" % s
	return ""


func test_contract_fields() -> String:
	var sim := WorldSim.new(7, true, WorldSim.SCENARIO_CRETACEOUS)
	var parcel := ParcelSim.new(sim, CELL)
	var err := _check_state(parcel)
	if err != "":
		return "à la création : " + err
	var events := _advance(sim, parcel, 20)
	err = _check_state(parcel)
	if err != "":
		return err
	return check_events(events)


func test_several_species_live_on_the_parcel() -> String:
	# Au Crétacé, une parcelle de terre fertile voit passer plusieurs espèces, pas seulement la dominante.
	for seed_value in [7, 11, 42]:
		var sim := WorldSim.new(seed_value, true, WorldSim.SCENARIO_CRETACEOUS)
		var parcel := ParcelSim.new(sim, _land_cell(sim, CELL))
		_advance(sim, parcel, 10)
		if parcel.land_use != "ocean" and parcel.fauna.size() >= 2:
			return ""
	return "jamais plus d'une espèce sur la parcelle"


func test_history_grows_and_is_bounded() -> String:
	var sim := WorldSim.new(11, true, WorldSim.SCENARIO_CRETACEOUS)
	var parcel := ParcelSim.new(sim, CELL)
	_advance(sim, parcel, 30)
	if parcel.history.size() <= 1:
		return "historique vide"
	for k in range(1, parcel.history.size()):
		if parcel.history[k].year <= parcel.history[k - 1].year:
			return "historique non chronologique"
	if parcel.history[-1].year > parcel.year:
		return "échantillon dans le futur"
	# Échantillonnage en temps simulé : ~ un point tous les HISTORY_STEPS pas idéaux.
	var expected: float = (parcel.year - parcel.history[0].year) / (sim.ideal_step_years() * ParcelSim.HISTORY_STEPS)
	if absf(parcel.history.size() - 1 - expected) > 2.0:
		return "%d échantillons pour %.1f attendus" % [parcel.history.size(), expected]
	_advance(sim, parcel, ParcelSim.HISTORY_SIZE)
	if parcel.history.size() > ParcelSim.HISTORY_SIZE:
		return "historique non borné"
	if parcel.history.size() < ParcelSim.HISTORY_SIZE:
		return "historique tronqué trop tôt : %d" % parcel.history.size()
	return ""


func test_deterministic() -> String:
	var a := WorldSim.new(42, true, WorldSim.SCENARIO_CRETACEOUS)
	var b := WorldSim.new(42, true, WorldSim.SCENARIO_CRETACEOUS)
	var pa := ParcelSim.new(a, CELL)
	var pb := ParcelSim.new(b, CELL)
	var ea := _advance(a, pa, 25)
	var eb := _advance(b, pb, 25)
	for prop in ["land_use", "fauna", "structures", "alerts", "history", "vegetation", "water", "development"]:
		if str(pa.get(prop)) != str(pb.get(prop)):
			return "même graine, parcelles différentes (%s)" % prop
	if str(ea) != str(eb):
		return "même graine, événements de parcelle différents"
	return ""


func test_independent_of_call_rate() -> String:
	# Deux parcelles sur le même monde : l'une recalculée à chaque pas, l'autre tous les 4 pas.
	var sim := WorldSim.new(7, true, WorldSim.SCENARIO_CRETACEOUS)
	var cell := _land_cell(sim, CELL)
	var every := ParcelSim.new(sim, cell)
	var sparse := ParcelSim.new(sim, cell)
	var pending := []
	for frame in 120:
		var events := sim.step(sim.ideal_step_years() * sim.max_substeps)
		every.update(events)
		pending.append_array(events)
		if frame % 4 == 3:
			sparse.update(pending)
			pending = []
	if every.land_use != sparse.land_use:
		return "usage du sol différent : %s / %s" % [every.land_use, sparse.land_use]
	if absf(every.development - sparse.development) > 0.3 or absf(every.vegetation - sparse.vegetation) > 0.05:
		return "état divergent (développement %.2f / %.2f, végétation %.2f / %.2f)" % [
			every.development, sparse.development, every.vegetation, sparse.vegetation]
	var counts := {}
	for f in sparse.fauna:
		counts[f.species_id] = f.count
	for f in every.fauna:
		if f.count < 5:
			continue
		var other: int = counts.get(f.species_id, 0)
		if absi(other - f.count) > maxi(3, int(f.count * 0.25)):
			return "effectif de %s : %d / %d" % [f.name, f.count, other]
	# Quand le rythme change (passage au Cénozoïque), l'intervalle d'échantillonnage change aussi :
	# quelques échantillons d'écart selon la cadence, pas davantage.
	if absi(every.history.size() - sparse.history.size()) > maxi(2, int(every.history.size() * 0.03)):
		return "historique : %d / %d échantillons" % [every.history.size(), sparse.history.size()]
	return ""


func test_update_cost_under_a_millisecond() -> String:
	var sim := WorldSim.new(42, true, WorldSim.SCENARIO_CRETACEOUS)
	var parcel := ParcelSim.new(sim, _land_cell(sim, CELL))
	_advance(sim, parcel, 10)
	var total := 0
	var n := 100
	for k in n:
		var events := sim.step(sim.ideal_step_years() * sim.max_substeps)
		var t0 := Time.get_ticks_usec()
		parcel.update(events)
		total += Time.get_ticks_usec() - t0
	var ms := total / 1000.0 / n
	print("  parcelle : %.3f ms par update()" % ms)
	if ms > 1.0:
		return "update() trop lent : %.3f ms" % ms
	return ""


## Première cellule de terre autour de `start` (même balayage que GameState).
static func _land_cell(sim: RefCounted, start: Vector2i) -> Vector2i:
	for r in range(0, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := Vector2i(posmod(start.x + dx, WorldSim.WIDTH), clampi(start.y + dy, 0, WorldSim.HEIGHT - 1))
				if sim.elevation[c.y * WorldSim.WIDTH + c.x] >= 0.0:
					return c
	return start
