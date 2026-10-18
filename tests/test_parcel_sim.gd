extends RefCounted
## Dynamique de la parcelle (src/sim/parcel_sim.gd) : hystérésis, tendances lisibles, cratère et
## recolonisation, crises, déclin jusqu'aux ruines, progression d'un peuple sur une partie accélérée.
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const WorldSim := preload("res://src/sim/world_sim.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")
const Text := preload("res://src/sim/parcel_text.gd")
const Contract := preload("res://tests/test_parcel.gd")

const CELL := Vector2i(70, 40)
const YUCATAN := Vector2i(60, 50)
const INDUSTRIAL := WorldSim.Eras.FIRST_SAPIENT_ERA + 4


func _frame(sim: RefCounted) -> Array[Dictionary]:
	return sim.step(sim.ideal_step_years() * sim.max_substeps)


func _advance(sim: RefCounted, parcel: RefCounted, frames: int) -> Array:
	var events := []
	for i in frames:
		events.append_array(parcel.update(_frame(sim)))
	return events


## Cellule de terre franche (ni rivage ni sommet) autour de `start`, entourée de terres.
static func _inland_cell(sim: RefCounted, start: Vector2i) -> Vector2i:
	for r in range(0, 60):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := Vector2i(posmod(start.x + dx, WorldSim.WIDTH), clampi(start.y + dy, 2, WorldSim.HEIGHT - 3))
				if _is_inland(sim, c):
					return c
	return start


static func _is_inland(sim: RefCounted, c: Vector2i) -> bool:
	for oy in range(-2, 3):
		for ox in range(-2, 3):
			var x := posmod(c.x + ox, WorldSim.WIDTH)
			var e: float = sim.elevation[(c.y + oy) * WorldSim.WIDTH + x]
			if e < 0.0:
				return false
	var e0: float = sim.elevation[c.y * WorldSim.WIDTH + c.x]
	var t0: float = sim.temperature[c.y * WorldSim.WIDTH + c.x]
	return e0 >= 0.1 and e0 <= 0.6 and t0 > 0.3


## Cellule de terre franche à une distance comprise entre rmin et rmax (cellules) de `center`.
static func _inland_ring(sim: RefCounted, center: Vector2i, rmin: float, rmax: float) -> Vector2i:
	var r := int(ceil(rmax))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d := sqrt(float(dx * dx + dy * dy))
			var y := center.y + dy
			if d < rmin or d > rmax or y < 2 or y > WorldSim.HEIGHT - 3:
				continue
			var c := Vector2i(posmod(center.x + dx, WorldSim.WIDTH), y)
			if _is_inland(sim, c):
				return c
	return Vector2i(-1, -1)


## Meilleure cellule de terre (technologie locale maximale) de la région écologique de `origin`.
static func _settled_cell(sim: RefCounted, origin: Vector2i) -> Vector2i:
	var rs: int = ParcelSim.Ecosystem.RS
	var x0 := (posmod(origin.x, WorldSim.WIDTH) / rs) * rs
	var y0 := (clampi(origin.y, 0, WorldSim.HEIGHT - 1) / rs) * rs
	var best := Vector2i(-1, -1)
	var best_t := -1.0
	for y in range(y0, y0 + rs):
		for x in range(x0, x0 + rs):
			var i := y * WorldSim.WIDTH + x
			if sim.elevation[i] >= 0.0 and sim.tech[i] > best_t:
				best_t = sim.tech[i]
				best = Vector2i(x, y)
	return best if best.x >= 0 else Contract._land_cell(sim, origin)


func _find(events: Array, type: String) -> Dictionary:
	for e in events:
		if e.type == type:
			return e
	return {}


func test_development_hysteresis() -> String:
	# Un développement qui oscille autour d'un seuil ne fait pas clignoter l'usage du sol.
	var lv := 2
	var changes := 0
	for k in 400:
		var d := 3.1 + 0.15 * sin(k * 0.7)
		var n := ParcelSim.step_level(d, lv)
		if n != lv:
			changes += 1
		lv = n
	if changes > 1:
		return "%d changements de palier pour une oscillation de ±0,15" % changes
	# Une croissance continue traverse tous les paliers, un par un, dans l'ordre.
	lv = 0
	for k in 900:
		var n := ParcelSim.step_level(k * 0.01, lv)
		if n != lv and n != lv + 1:
			return "palier sauté : %d -> %d" % [lv, n]
		lv = n
	if ParcelSim.DEV_USES[lv] != "arcology":
		return "croissance maximale : %s" % ParcelSim.DEV_USES[lv]
	for k in 900:
		var n := ParcelSim.step_level(8.9 - k * 0.01, lv)
		if n != lv and n != lv - 1:
			return "déclin sauté : %d -> %d" % [lv, n]
		lv = n
	if lv != 0:
		return "déclin incomplet : palier %d" % lv
	# La cible croît avec la technologie.
	var prev := -1.0
	for k in 81:
		var d := ParcelSim.development_for_tech(k * 0.1)
		if d < prev:
			return "development_for_tech non monotone en %.1f" % (k * 0.1)
		prev = d
	return ""


func test_ice_hysteresis() -> String:
	var sim := WorldSim.new(7, true, WorldSim.SCENARIO_CRETACEOUS)
	var cell := _inland_cell(sim, CELL)
	var i := cell.y * WorldSim.WIDTH + cell.x
	var parcel := ParcelSim.new(sim, cell)
	# Températures de grille successives, et l'état glacé attendu (entrée < 0,11, sortie > 0,14).
	var temps := [0.5, 0.10, 0.125, 0.105, 0.135, 0.12, 0.2, 0.125, 0.115, 0.13, 0.09]
	var iced := [false, true, true, true, true, true, false, false, false, false, true]
	for k in temps.size():
		sim.temperature[i] = temps[k]
		sim.year += 1000.0
		parcel.update([])
		if (parcel.land_use == "ice") != iced[k]:
			return "étape %d (t = %.3f) : usage %s" % [k, temps[k], parcel.land_use]
	return ""


func test_trends_do_not_flicker() -> String:
	var sim := WorldSim.new(11, true, WorldSim.SCENARIO_CRETACEOUS)
	var parcel := ParcelSim.new(sim, Contract._land_cell(sim, CELL))
	var last := {}
	var changes := 0
	for frame in 150:
		parcel.update(_frame(sim))
		for f in parcel.fauna:
			if not last.has(f.species_id):
				last[f.species_id] = [f.trend, parcel.year]
			elif last[f.species_id][0] != f.trend:
				changes += 1
				var steps: float = (parcel.year - last[f.species_id][1]) / sim.ideal_step_years()
				if steps < ParcelSim.TREND_HOLD - 0.01:
					return "%s : tendance changée après %.1f pas seulement" % [f.name, steps]
				last[f.species_id] = [f.trend, parcel.year]
	print("  tendances : %d changements en 150 images" % changes)
	return ""


func test_crater_after_meteor() -> String:
	var sim := WorldSim.new(7, true, WorldSim.SCENARIO_CRETACEOUS)
	var cell := _inland_cell(sim, CELL)
	var parcel := ParcelSim.new(sim, cell)
	var events := _advance(sim, parcel, 5)
	# Comme GameState : conséquences de l'action, puis l'action brute (sans id).
	var pending: Array = sim.apply_divine_action({type = "meteor", region = cell, species_id = -1, radius = 8})
	pending.append({type = "meteor", region = cell})
	events.append_array(parcel.update(pending))
	if parcel.land_use != "crater":
		return "pas de cratère après le météore (usage : %s)" % parcel.land_use
	var impact := _find(events, "parcel_impact")
	if impact.is_empty() or impact.cause_id <= 0:
		return "événement parcel_impact absent ou sans cause"
	var chain: Array = sim.get_causal_chain(impact.cause_id)
	if chain.is_empty() or chain[-1].type != "divine_meteor":
		return "la cause du cratère ne remonte pas au météore divin"
	if not parcel.fauna.is_empty() or parcel.vegetation > 0.01 or not parcel.structures.is_empty():
		return "la vie survit au cœur de l'impact"
	var cold := false
	var frames := 0
	while parcel.land_use == "crater" and frames < 1000:
		frames += 1
		events.append_array(parcel.update(_frame(sim)))
		for a in parcel.alerts:
			if a.kind == "heat_drift" and String(a.summary).begins_with("Le froid"):
				cold = true
	if parcel.land_use == "crater":
		return "le cratère ne se recolonise jamais"
	if _find(events, "parcel_recolonized").is_empty():
		return "pas d'événement de recolonisation"
	if not cold:
		return "l'hiver d'impact ne déclenche pas d'alerte de froid"
	events.append_array(_advance(sim, parcel, 80))
	print("  cratère recolonisé en %d images ; végétation %.2f, %d espèces" % [frames, parcel.vegetation, parcel.fauna.size()])
	if parcel.vegetation < 0.05 or parcel.fauna.is_empty():
		return "la vie ne revient pas (végétation %.2f, %d espèces)" % [parcel.vegetation, parcel.fauna.size()]
	return Contract.check_events(events)


func test_impact_nearby_raises_crisis() -> String:
	# Hors du cratère mais dans la zone dévastée : les espèces s'effondrent, le joueur est alerté.
	var sim := WorldSim.new(7, true, WorldSim.SCENARIO_CRETACEOUS)
	var target := _inland_cell(sim, CELL)
	var cell := _inland_ring(sim, target, 11.0, 16.0)
	if cell.x < 0:
		return "pas de terre franche à 11-16 cellules de %s" % str(target)
	var parcel := ParcelSim.new(sim, cell)
	var events := _advance(sim, parcel, 5)
	var pending: Array = sim.apply_divine_action({type = "meteor", region = target, species_id = -1, radius = 8})
	events.append_array(parcel.update(pending))
	if parcel.land_use == "crater":
		return "parcelle voisine dans le cratère (%s / %s)" % [str(cell), str(target)]
	var collapse := false
	for frame in 30:
		events.append_array(parcel.update(_frame(sim)))
		for a in parcel.alerts:
			if a.kind == "species_collapse" and a.severity >= 0.5 and a.species_id >= 0:
				collapse = true
	if not collapse:
		return "aucune alerte d'effondrement près de l'impact"
	if _find(events, "parcel_crisis").is_empty():
		return "aucun événement parcel_crisis"
	return Contract.check_events(events)


func test_decline_leaves_ruins_then_nature() -> String:
	# Une ville sans habitants (aucun peuple au Crétacé) : déclin palier par palier, ruines,
	# végétation qui les envahit, puis nature sauvage. On place l'état de départ à la main.
	var sim := WorldSim.new(7, true, WorldSim.SCENARIO_CRETACEOUS)
	var parcel := ParcelSim.new(sim, _inland_cell(sim, CELL))
	parcel.development = 6.0
	parcel._built = 6.0
	parcel._level = 6
	parcel._peak_level = 6
	parcel._base_use = "city"
	parcel.land_use = "city"
	var uses := ["city"]
	var events := []
	for k in 1000:
		sim.year += sim.ideal_step_years()
		events.append_array(parcel.update([]))
		if parcel.land_use != uses[-1]:
			uses.append(parcel.land_use)
		if parcel.land_use == "wild":
			break
	print("  déclin : %s" % " → ".join(uses))
	var expected := ["city", "town", "village", "farmland", "pasture", "camp", "ruins", "rewild", "wild"]
	if str(uses) != str(expected):
		return "séquence inattendue : %s" % " → ".join(uses)
	return Contract.check_events(events)


func test_sapient_progression_on_accelerated_game() -> String:
	var sim := WorldSim.new(7, true, WorldSim.SCENARIO_CRETACEOUS)
	sim.apply_divine_action({type = "meteor", region = YUCATAN, species_id = -1, radius = 12})
	var origin := Vector2i(-1, -1)
	var guard := 0
	while origin.x < 0 and guard < 20000:
		guard += 1
		for ev in _frame(sim):
			if ev.type == "sapience" and origin.x < 0:
				origin = ev.region
	if origin.x < 0:
		return "aucune sapience"
	var parcel := ParcelSim.new(sim, _settled_cell(sim, origin))
	var uses := [parcel.land_use]
	var events := []
	var max_level := ParcelSim.DEV_USES.find(parcel.land_use)
	var saw_people := false
	var usec := 0
	var worst := 0
	guard = 0
	while sim.era_index() < INDUSTRIAL and guard < 8000:
		guard += 1
		var world_events := _frame(sim)
		var t0 := Time.get_ticks_usec()
		events.append_array(parcel.update(world_events))
		var spent := Time.get_ticks_usec() - t0
		usec += spent
		worst = maxi(worst, spent)
		if parcel.land_use != uses[-1]:
			uses.append(parcel.land_use)
		max_level = maxi(max_level, ParcelSim.DEV_USES.find(parcel.land_use))
		for f in parcel.fauna:
			if f.role == "sapient":
				saw_people = true
	print("  progression (%s) : %s, ère %s" % [str(parcel.cell), " → ".join(uses), sim.current_era()])
	print("  update() en ère sapiente : %.3f ms en moyenne, %.3f ms au pire (%d appels)" % [
		usec / 1000.0 / maxi(guard, 1), worst / 1000.0, guard])
	if usec / 1000.0 / maxi(guard, 1) > 1.0:
		return "update() trop lent en ère sapiente"
	if sim.era_index() < INDUSTRIAL:
		return "ère industrielle non atteinte (%s)" % sim.current_era()
	if not saw_people:
		return "le peuple n'apparaît jamais dans la faune de sa parcelle d'origine"
	if max_level < ParcelSim.DEV_USES.find("village"):
		return "aucun village en vue à l'ère industrielle : %s" % " → ".join(uses)
	if uses.size() > 40:
		return "usage du sol instable (%d changements)" % uses.size()
	for k in range(1, uses.size()):
		var a := ParcelSim.DEV_USES.find(uses[k - 1])
		var b := ParcelSim.DEV_USES.find(uses[k])
		if a >= 1 and b >= 1 and absi(b - a) > 1:
			return "palier sauté : %s -> %s" % [uses[k - 1], uses[k]]
	var farm := uses.find("farmland")
	var village := uses.find("village")
	if village > 0 and (farm < 0 or farm > village):
		return "un village sans champs : %s" % " → ".join(uses)
	var caused := false
	for e in events:
		if e.type == "parcel_land_use" and e.cause_id > 0:
			caused = true
	if not caused:
		return "aucun essor de la parcelle n'est relié à un événement mondial"
	return Contract.check_events(events)


func test_summaries_agree_in_number() -> String:
	var cases := [
		[Text.about("Multituberculés", "%s arrive.", "%s arrivent."), "Les Multituberculés arrivent."],
		[Text.about("Verpha moloum", "%s arrive.", "%s arrivent."), "L'espèce Verpha moloum arrive."],
		[Text.about("Squamates nuloa", "%s arrive.", "%s arrivent."), "L'espèce Squamates nuloa arrive."],
		[Text.about("Humains", "%s s'effondre (-50 %%).", "%s s'effondrent (-50 %%)."), "Les Humains s'effondrent (-50 %)."],
		[Text.of_species("Humains"), "des Humains"],
		[Text.of_species("Verpha moloum"), "de l'espèce Verpha moloum"],
		[Text.use_subject("farmland", "se réduit", "se réduisent"), "les terres agricoles se réduisent"],
		[Text.signed_decimal(-12.04), "-12,0"],
		[Text.use_label("wild", "Forêt tempérée"), "Forêt sauvage"],
	]
	for c in cases:
		if c[0] != c[1]:
			return "« %s » au lieu de « %s »" % [c[0], c[1]]
	return ""
