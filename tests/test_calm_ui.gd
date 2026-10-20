extends RefCounted
## Tests de l'interface calme (docs/GENESE.md) : recharges et outil sélectionné, actions de semence,
## formatage des statistiques planétaires et filtres d'espèces, mise en page de l'arbre de la vie,
## nom du compagnon. Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const Cooldowns := preload("res://src/ui/tools/cooldowns.gd")
const ToolState := preload("res://src/ui/tools/tool_state.gd")
const SeedCatalog := preload("res://src/ui/seeds/seed_catalog.gd")
const PlanetMath := preload("res://src/ui/stats/planet_math.gd")
const TreeLayout := preload("res://src/ui/tree/tree_layout.gd")
const Speaker := preload("res://src/ui/chronicle/speaker.gd")


func _expect(got, want, what: String) -> String:
	if got != want:
		return "%s : obtenu %s, attendu %s" % [what, str(got), str(want)]
	return ""


func _near(got: float, want: float, what: String, eps: float = 1e-4) -> String:
	if absf(got - want) > eps:
		return "%s : obtenu %f, attendu %f" % [what, got, want]
	return ""


func _first_error(errors: Array) -> String:
	for e in errors:
		if e != "":
			return e
	return ""


# --- Recharges ---

func test_cooldown_lifecycle() -> String:
	var c := Cooldowns.new()
	var err := _first_error([
		_expect(c.is_ready("power:meteor"), true, "prêt au départ"),
		_near(c.ratio("power:meteor"), 0.0, "jauge vide au départ"),
	])
	if err != "":
		return err
	c.start("power:meteor", 10.0)
	err = _first_error([
		_expect(c.is_ready("power:meteor"), false, "en recharge"),
		_near(c.ratio("power:meteor"), 1.0, "jauge pleine"),
		_expect(c.is_ready("seed:spark"), true, "les autres outils restent libres"),
	])
	if err != "":
		return err
	var done := c.tick(4.0)
	err = _first_error([
		_expect(done.size(), 0, "rien n'est prêt après 4 s"),
		_near(c.remaining("power:meteor"), 6.0, "reste 6 s"),
		_near(c.ratio("power:meteor"), 0.6, "jauge à 60 %"),
		_expect(Cooldowns.format_remaining(c.remaining("power:meteor")), "6 s", "affichage"),
	])
	if err != "":
		return err
	done = c.tick(6.5)
	err = _first_error([
		_expect(done, ["power:meteor"] as Array[String], "redevenu prêt"),
		_expect(c.is_ready("power:meteor"), true, "prêt après la recharge"),
		_expect(c.active_ids().size(), 0, "plus de recharge active"),
		_expect(c.tick(-1.0).size(), 0, "delta négatif ignoré"),
		_expect(Cooldowns.format_remaining(65.0), "1 min 05", "minutes"),
		_expect(Cooldowns.format_remaining(0.0), "", "prêt : rien à afficher"),
	])
	c.start("seed:light", 0.0)
	if err == "" and not c.is_ready("seed:light"):
		err = "une recharge nulle ne bloque pas"
	return err


func test_tool_state_select_use_and_recharge() -> String:
	var ts: Node = ToolState.new()
	var changes := []
	ts.tool_changed.connect(func(t: Dictionary) -> void: changes.append(t))
	var err := _expect(ts.can_use(), false, "aucun outil sélectionné")
	ts.select_power("meteor")
	var tool: Dictionary = ts.selected_tool()
	if err == "":
		err = _first_error([
			_expect(tool.kind, "power", "type d'outil"),
			_expect(tool.params.radius, 8, "rayon par défaut du catalogue"),
			_expect(changes.size(), 1, "signal tool_changed"),
			_expect(ts.can_use(tool), true, "pouvoir prêt"),
		])
	var action: Dictionary = ts.use(tool, Vector2i(5, 6))
	if err == "":
		err = _first_error([
			_expect(action.get("type"), "meteor", "action renvoyée"),
			_expect(action.get("region"), Vector2i(5, 6), "région"),
			_expect(ts.can_use(tool), false, "en recharge après usage"),
			_expect(ts.use(tool, Vector2i(1, 1)), {}, "refusé pendant la recharge"),
			_near(ts.remaining(tool), ToolState.cooldown_of(tool), "recharge complète"),
		])
	# Les recharges sont propres à chaque outil.
	ts.select_seed("spark")
	if err == "":
		err = _expect(ts.can_use(), true, "une semence reste libre pendant la recharge d'un pouvoir")
	ts._process(ToolState.cooldown_of(tool) + 0.1)
	if err == "":
		err = _expect(ts.can_use(tool), true, "pouvoir rechargé")
	ts.set_param("radius", 999)
	if err == "":
		err = _expect(ts.selected_tool().params.radius, SeedCatalog.MAX_RADIUS, "rayon borné")
	ts.clear()
	if err == "":
		err = _first_error([
			_expect(ts.selected_tool(), {}, "désélection"),
			_expect(ToolState.normalize({kind = "power", id = "inconnu"}), {}, "pouvoir inconnu refusé"),
			_expect(ToolState.normalize({kind = "rune", id = "x"}), {}, "type inconnu refusé"),
		])
	ts.free()
	return err


# --- Semences ---

func test_seed_actions_validation() -> String:
	var ok := SeedCatalog.make_action("light", {}, Vector2i(3, 4), 6)
	var germ := SeedCatalog.make_action("animal_germ", {role = "hunter"}, Vector2i(0, 0), 4)
	var shaped := SeedCatalog.make_action("shaped", SeedCatalog.default_traits("shaped"), Vector2i(1, 2), 3)
	var err := _first_error([
		_expect(SeedCatalog.validate_action(ok), "", "lumière valide"),
		_expect(ok.type, "seed", "type"),
		_expect(SeedCatalog.validate_action(germ), "", "germe valide"),
		_expect(SeedCatalog.validate_action(shaped), "", "créature façonnée valide"),
	])
	if err != "":
		return err
	for kind in SeedCatalog.KINDS:
		var a := SeedCatalog.make_action(kind, SeedCatalog.default_traits(kind), Vector2i(0, 0), 4)
		if SeedCatalog.validate_action(a) != "":
			return "semence %s invalide avec ses traits par défaut" % kind
	var bad_shaped := shaped.duplicate(true)
	bad_shaped.traits.size = 1.5
	var bad_diet := shaped.duplicate(true)
	bad_diet.traits.diet = "lumière"
	var bad_color := shaped.duplicate(true)
	bad_color.traits.erase("color")
	var cases := [
		[42, "pas un dictionnaire"],
		[{type = "meteor", kind = "light", region = Vector2i(0, 0), radius = 4, traits = {}}, "mauvais type"],
		[SeedCatalog.make_action("dragon", {}, Vector2i(0, 0), 4), "semence inconnue"],
		[{type = "seed", kind = "light", radius = 4, traits = {}}, "sans région"],
		[SeedCatalog.make_action("light", {}, Vector2i(0, 0), 0), "rayon nul"],
		[SeedCatalog.make_action("light", {}, Vector2i(0, 0), 99), "rayon trop grand"],
		[SeedCatalog.make_action("animal_germ", {role = "licorne"}, Vector2i(0, 0), 4), "rôle inconnu"],
		[SeedCatalog.make_action("animal_germ", {}, Vector2i(0, 0), 4), "rôle manquant"],
		[bad_shaped, "taille hors bornes"],
		[bad_diet, "régime inconnu"],
		[bad_color, "couleur manquante"],
	]
	for c in cases:
		if SeedCatalog.validate_action(c[0]) == "":
			return "action acceptée à tort : " + c[1]
	return ""


func test_seed_conditions_hint() -> String:
	return _first_error([
		_expect(SeedCatalog.conditions("spark", {}).state, "ok", "étincelle : toujours possible"),
		_expect(SeedCatalog.conditions("animal_germ", {oxygen = 0.02}).state, "risky", "trop peu d'oxygène"),
		_expect(SeedCatalog.conditions("animal_germ", {oxygen = 0.5}).state, "ok", "oxygène suffisant"),
		_expect(SeedCatalog.conditions("spore", {}).state, "unknown", "ozone non renseigné"),
		_expect(SeedCatalog.conditions("spore", {ozone = 0.1}).state, "risky", "ozone trop mince"),
		_expect(SeedCatalog.conditions("shaped", {oxygen = 1.0, ozone = 1.0}).state, "ok", "monde mûr"),
		_expect(SeedCatalog.conditions("shaped", {oxygen = 1.0}).state, "unknown", "mesure manquante"),
	])


# --- Statistiques planétaires ---

func test_planet_metric_formatting() -> String:
	return _first_error([
		_expect(PlanetMath.format_metric("temperature_c", 14.84), "14,8 °C", "chaleur"),
		_expect(PlanetMath.format_metric("ozone", 0.62), "62 %", "ozone"),
		_expect(PlanetMath.format_metric("ozone", 0.045), "4,5 %", "ozone faible"),
		_expect(PlanetMath.format_metric("oxygen", 1.0), "21,0 %", "oxygène actuel"),
		_expect(PlanetMath.format_metric("oxygen", 0.0), "0,0 %", "pas d'oxygène"),
		_expect(PlanetMath.format_metric("co2_ppm", 280.4), "280 ppm", "CO₂"),
		_expect(PlanetMath.format_metric("co2_ppm", 12500.0), "12 500 ppm", "CO₂ archéen"),
		_expect(PlanetMath.format_metric("methane_ppm", 1.82), "1,8 ppm", "méthane"),
		_expect(PlanetMath.format_metric("sea_level_m", 12.4), "+12 m", "mers hautes"),
		_expect(PlanetMath.format_metric("sea_level_m", -120.0), "-120 m", "mers basses"),
		_expect(PlanetMath.format_metric("sea_level_m", 0.2), "0 m", "niveau de départ"),
		_expect(PlanetMath.format_metric("biodiversity", 1234), "1 234 espèces", "biodiversité"),
		_expect(PlanetMath.format_metric("biodiversity", 1), "1 espèce", "singulier"),
		_expect(PlanetMath.format_metric("extinctions_recent", 7.0), "7", "extinctions"),
		_expect(PlanetMath.format_metric("sun_luminosity", 1.08), "108 % de l'actuel", "Soleil"),
		_expect(PlanetMath.format_metric("habitability", 0.755), "76 %", "habitabilité"),
		_expect(PlanetMath.format_metric("ozone", NAN), "—", "valeur invalide"),
		_expect(PlanetMath.format_metric("ozone", null), "—", "valeur absente"),
	])


func test_planet_stats_reading_and_history() -> String:
	var sim := StubSim.new()
	var s := PlanetMath.read_stats(sim, StubParcel.new())
	var err := _first_error([
		_near(s.get("oxygen", -1.0), 0.4, "oxygène repris de sim.oxygen"),
		_expect(s.get("biodiversity"), 3, "biodiversité = espèces vivantes"),
		_near(s.get("temperature_c", -99.0), 14.0, "chaleur mondiale de la parcelle"),
		_near(s.get("local_temperature_c", -99.0), 21.0, "chaleur locale"),
		_expect(PlanetMath.read_stats(null, null), {}, "sans simulation"),
		_expect(PlanetMath.read_history(sim), [], "sans planet_history"),
	])
	if err != "":
		return err
	var rich := RichSim.new()
	var r := PlanetMath.read_stats(rich, null)
	err = _first_error([
		_near(r.get("oxygen", -1.0), 0.9, "planet_stats l'emporte"),
		_near(r.get("ozone", -1.0), 0.7, "ozone de planet_stats"),
		_expect(PlanetMath.read_history(rich).size(), 2, "planet_history lu"),
	])
	if err != "":
		return err
	var h := []
	for i in 6:
		PlanetMath.push_sample(h, {year = float(i), oxygen = 0.1 * i}, 4)
	PlanetMath.push_sample(h, {year = 5.0, oxygen = 0.9}, 4)
	return _first_error([
		_expect(h.size(), 4, "historique borné"),
		_near(h[0].year, 2.0, "les plus anciens sortent"),
		_near(h[-1].oxygen, 0.9, "même année : échantillon remplacé"),
	])


func test_species_filters_and_trends() -> String:
	var whale := {traits = {habitat = "marine", diet = "carnivore", size = 0.9}}
	var moss := {traits = {habitat = "land", diet = "autotrophe", size = 0.01}}
	return _first_error([
		_expect(PlanetMath.species_matches(whale, "all", "all", "all"), true, "sans filtre"),
		_expect(PlanetMath.species_matches(whale, "marine", "carnivore", "large"), true, "tous filtres"),
		_expect(PlanetMath.species_matches(whale, "land", "all", "all"), false, "mauvais milieu"),
		_expect(PlanetMath.species_matches(moss, "all", "autotrophe", "micro"), true, "producteur minuscule"),
		_expect(PlanetMath.species_matches(moss, "all", "herbivore", "all"), false, "mauvais régime"),
		_expect(PlanetMath.species_matches({}, "all", "all", "medium"), true, "taille par défaut moyenne"),
		_expect(PlanetMath.size_class(0.1), "small", "petite"),
		_expect(PlanetMath.population_trend(100.0, 120.0), 1, "hausse"),
		_expect(PlanetMath.population_trend(100.0, 80.0), -1, "baisse"),
		_expect(PlanetMath.population_trend(100.0, 102.0), 0, "stable"),
		_expect(PlanetMath.population_trend(0.0, 5.0), 1, "apparition"),
	])


# --- Arbre de la vie ---

func _random_lineage(count: int, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := []
	var year := -3.8e9
	for i in count:
		year += rng.randf_range(0.0, 2.0e6) if rng.randf() < 0.8 else 0.0  # naissances simultanées
		var parent := -1 if i < 3 else rng.randi_range(maxi(0, i - 200), i - 1)
		var extinct := year + rng.randf_range(1.0e5, 3.0e8) if rng.randf() < 0.7 else NAN
		out.append({id = i + 10, parent = parent + 10 if parent >= 0 else -1, name = "Espèce %d" % i,
			born_year = year, extinct_year = extinct, alive = is_nan(extinct), traits = {}})
	return out


func test_tree_layout_2000_species_no_overlap_and_fast() -> String:
	var entries := _random_lineage(2000, 7)
	var t0 := Time.get_ticks_usec()
	var layout := TreeLayout.compute(entries, -3.8e9 + 2000 * 2.0e6 + 1.0)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("arbre de 2 000 espèces : %.1f ms, %d couloirs" % [ms, layout.lanes])
	if layout.nodes.size() != 2000:
		return "espèces placées : %d" % layout.nodes.size()
	if TreeLayout.has_overlap(layout):
		return "deux espèces se chevauchent dans un couloir"
	if layout.lanes >= 2000:
		return "aucun compactage : %d couloirs" % layout.lanes
	for id in layout.nodes:
		var n: Dictionary = layout.nodes[id]
		if n.x1 <= n.x0:
			return "segment vide pour %d" % id
	if ms > 1500.0:
		return "mise en page trop lente : %.0f ms" % ms
	return ""


func test_tree_children_stay_near_parent_and_axis() -> String:
	# Une racine, deux enfants successifs : chaque enfant à côté de son parent.
	var entries := [
		{id = 1, parent = -1, born_year = 0.0, extinct_year = NAN},
		{id = 2, parent = 1, born_year = 10.0, extinct_year = NAN},
		{id = 3, parent = 1, born_year = 20.0, extinct_year = 30.0},
		{id = 4, parent = -1, born_year = 40.0, extinct_year = NAN},
	]
	var l := TreeLayout.compute(entries, 50.0)
	var births: PackedFloat64Array = l.ranks
	var err := _first_error([
		_expect(TreeLayout.has_overlap(l), false, "pas de chevauchement"),
		_expect(absi(l.nodes[2].lane - l.nodes[1].lane), 1, "premier enfant contre son parent"),
		_expect(l.nodes[2].lane != l.nodes[3].lane, true, "enfants contemporains séparés"),
		_near(TreeLayout.year_to_rank(births, 10.0), 1.0, "rang d'une naissance"),
		_near(TreeLayout.year_to_rank(births, 15.0), 1.5, "rang interpolé"),
		_near(TreeLayout.year_to_rank(births, -5.0), 0.0, "avant la première naissance"),
		_near(TreeLayout.rank_to_year(births, 2.5), 30.0, "année d'un rang"),
		_near(l.nodes[3].x1, TreeLayout.year_to_rank(births, 30.0), "fin d'une espèce éteinte"),
	])
	return err


func test_tree_ancestors_and_marks() -> String:
	var by_id := {1: {parent = -1}, 2: {parent = 1}, 3: {parent = 2}, 4: {parent = 4}}
	var m := TreeLayout.marks({type = "seed", kind = "light"}, [{type = "spawn", species_id = 9}])
	var p := TreeLayout.marks({type = "plague", species_id = 5}, [{type = "decline", species_id = 6}, {type = "x"}])
	return _first_error([
		_expect(TreeLayout.ancestors(by_id, 3), [2, 1] as Array[int], "lignée"),
		_expect(TreeLayout.ancestors(by_id, 1), [] as Array[int], "racine"),
		_expect(TreeLayout.ancestors(by_id, 4), [] as Array[int], "cycle ignoré"),
		_expect(m.sown, [9] as Array[int], "semée par le joueur"),
		_expect(p.touched, [5, 6] as Array[int], "touchées par un acte"),
		_expect(TreeLayout.describe_traits({size = 0.9, diet = "carnivore", habitat = "land", intelligence = 0.5}),
			"Grand carnivore terrestre, plutôt intelligent.", "description de repli"),
		_expect(TreeLayout.entries_from(StubSim.new()).size(), 4, "filiation depuis WorldSim.species"),
	])


func test_speaker_name() -> String:
	return _first_error([
		_expect(Speaker.speaker_name("  Autre "), "Autre", "orateur fourni"),
		_expect(Speaker.speaker_name(null, {NARRATOR_NAME = "Nom de config"}), "Nom de config", "ai_config"),
		_expect(Speaker.speaker_name(null, {}), "Ézéchiel", "nom par défaut"),
		_expect(Speaker.signature("Ézéchiel"), "— Ézéchiel", "signature"),
	])


class StubSim:
	var oxygen := 0.4
	var species := {
		1: {name = "A", alive = true, parent = -1, born_year = 0.0, extinct_year = NAN, traits = {}},
		2: {name = "B", alive = true, parent = 1, born_year = 5.0, extinct_year = NAN, traits = {}},
		3: {name = "C", alive = false, parent = 1, born_year = 6.0, extinct_year = 9.0, traits = {}},
		4: {name = "D", alive = true, parent = 2, born_year = 8.0, extinct_year = NAN, traits = {}},
	}

	func get_alive_species() -> Array[int]:
		return [1, 2, 4]


class StubParcel:
	var temperature_c := 21.0
	var global_temperature_c := 14.0


class RichSim:
	var oxygen := 0.2

	func planet_stats() -> Dictionary:
		return {oxygen = 0.9, ozone = 0.7}

	func planet_history() -> Array:
		return [{year = 0.0, oxygen = 0.5}, {year = 1.0, oxygen = 0.9}]


func test_recharge_starts_when_action_applied_elsewhere() -> String:
	# Une action appliquée par la vue ou le globe sans passer par use() lance quand même la recharge.
	var ts: Node = ToolState.new()
	var t: Dictionary = ts.notify_applied({type = "bless", region = Vector2i(1, 1), species_id = -1, radius = 8})
	var s: Dictionary = ts.notify_applied(SeedCatalog.make_action("spore", {}, Vector2i(0, 0), 6))
	var err := _first_error([
		_expect(t.get("id"), "bless", "pouvoir reconnu"),
		_expect(ts.can_use({kind = "power", id = "bless"}), false, "recharge du pouvoir lancée"),
		_expect(s.get("id"), "spore", "semence reconnue"),
		_expect(ts.can_use({kind = "seed", id = "spore"}), false, "recharge de la semence lancée"),
		_expect(ts.notify_applied({type = "inconnu"}), {}, "action inconnue ignorée"),
	])
	var before: float = ts.remaining({kind = "power", id = "bless"})
	ts._process(1.0)
	ts.notify_applied({type = "bless"})
	if err == "":
		err = _near(ts.remaining({kind = "power", id = "bless"}), before - 1.0, "une recharge en cours n'est pas relancée")
	ts.free()
	return err


func test_real_planet_keys_are_normalized() -> String:
	# Clés réelles de WorldSim.planet_stats() et de la propriété planet_history.
	var sim := WorldLikeSim.new()
	var s := PlanetMath.read_stats(sim, null)
	var h := PlanetMath.read_history(sim)
	return _first_error([
		_near(s.get("temperature_c", -99.0), 12.5, "global_temperature_c -> temperature_c"),
		_near(s.get("co2_ppm", -1.0), 4000.0, "co2 -> co2_ppm"),
		_near(s.get("methane_ppm", -1.0), 3.0, "methane -> methane_ppm"),
		_near(s.get("ice_fraction", -1.0), 0.1, "ice_cover -> ice_fraction"),
		_expect(s.get("extinctions_recent"), 2, "recent_extinctions -> extinctions_recent"),
		_expect(h.size(), 2, "propriété planet_history lue"),
		_near(h[1].get("temperature_c", -99.0), 13.0, "historique normalisé"),
		_expect(PlanetMath.normalize_keys({temperature_c = 1.0, global_temperature_c = 2.0}).temperature_c, 1.0,
			"la clé de mesure l'emporte"),
		_expect(PlanetMath.format_metric("biomass", 3.456), "3,46", "biomasse en indice"),
	])


class WorldLikeSim:
	var planet_history: Array[Dictionary] = [{year = 0.0, global_temperature_c = 12.0},
		{year = 1.0, global_temperature_c = 13.0}]

	func planet_stats() -> Dictionary:
		return {global_temperature_c = 12.5, co2 = 4000.0, methane = 3.0, ice_cover = 0.1,
			recent_extinctions = 2, oxygen = 0.0, ozone = 0.0}
