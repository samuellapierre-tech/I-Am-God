extends RefCounted
## Tests de la vue parcelle (fonctions pures de src/parcel/parcel_logic.gd et groupes de
## créatures hors scène). Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")
const CreatureGroup := preload("res://src/parcel/creature_group.gd")


func _expect(got, want, what: String) -> String:
	if got != want:
		return "%s : obtenu %s, attendu %s" % [what, str(got), str(want)]
	return ""


func test_reconcile_counts() -> String:
	# [actifs, partants, cible] -> {revive, spawn, retire}
	var cases := [
		[[0, 0, 5], {revive = 0, spawn = 5, retire = 0}],
		[[5, 0, 5], {revive = 0, spawn = 0, retire = 0}],
		[[8, 0, 3], {revive = 0, spawn = 0, retire = 5}],
		[[3, 4, 5], {revive = 2, spawn = 0, retire = 0}],
		[[3, 1, 6], {revive = 1, spawn = 2, retire = 0}],
		[[4, 2, 0], {revive = 0, spawn = 0, retire = 4}],
		[[2, 0, -3], {revive = 0, spawn = 0, retire = 2}],
	]
	for c in cases:
		var a: Array = c[0]
		var r := ParcelLogic.reconcile(a[0], a[1], a[2])
		var err := _expect(r, c[1], "reconcile(%d, %d, %d)" % a)
		if err != "":
			return err
		# Invariant : après application, il reste exactement max(cible, 0) actifs.
		var active: int = a[0] + r.revive + r.spawn - r.retire
		if active != maxi(a[2], 0):
			return "reconcile(%d, %d, %d) laisse %d actifs" % [a[0], a[1], a[2], active]
	return ""


func test_group_tracks_count_exactly() -> String:
	var g := CreatureGroup.new(4, Vector2i(10, 20))
	g.set_species({role = "herbivore", clade = "dinosaure", size = 0.8})
	var ctx := {prey = PackedVector2Array(), prey_len = PackedFloat32Array(), hunters = PackedVector2Array(), spots = PackedVector2Array()}
	for target in [12, 30, 7, 7, 0, 18, 40, 3]:
		g.set_target(target)
		if g.active_count() != target:
			return "après set_target(%d) : %d actifs" % [target, g.active_count()]
		g.step(0.3, ctx)
		if g.active_count() != target:
			return "après un pas : %d actifs au lieu de %d" % [g.active_count(), target]
	# Les partants s'effacent en fondu puis disparaissent.
	for i in 20:
		g.step(0.2, ctx)
	return _expect(g.pos.size(), 3, "individus restants après les fondus")


func test_group_fades_instead_of_jumping() -> String:
	var g := CreatureGroup.new(1, Vector2i.ZERO)
	g.set_species({role = "carnivore", clade = "dinosaure", size = 0.9})
	var ctx := {prey = PackedVector2Array([Vector2(500, 500)]), prey_len = PackedFloat32Array([40.0]), hunters = PackedVector2Array(), spots = PackedVector2Array()}
	g.set_target(4)
	for a in g.alpha:
		if a != 0.0:
			return "un nouvel individu doit apparaître transparent"
	g.step(0.4, ctx)
	for a in g.alpha:
		if a <= 0.0 or a >= 1.0:
			return "fondu d'apparition attendu, alpha = %f" % a
	g.set_target(1)
	if g.pos.size() != 4:
		return "les partants doivent rester le temps du fondu"
	return ""


func test_group_buffer_layout() -> String:
	var g := CreatureGroup.new(2, Vector2i.ZERO)
	g.set_species({role = "sapient", clade = "primate", size = 0.1})
	g.set_target(5)
	g.step(0.1, {prey = PackedVector2Array(), prey_len = PackedFloat32Array(), hunters = PackedVector2Array(), spots = PackedVector2Array([Vector2(300, 300)])})
	if g.buffer.size() != g.capacity * CreatureGroup.STRIDE or g.capacity < 5:
		return "tampon MultiMesh mal dimensionné : %d pour %d" % [g.buffer.size(), g.capacity]
	for i in 5:
		var o := i * CreatureGroup.STRIDE
		if Vector2(g.buffer[o + 3], g.buffer[o + 7]) != g.pos[i]:
			return "origine de l'instance %d incorrecte" % i
	return ""


func test_asset_resolution() -> String:
	var files := {
		"res://assets/parcel/creatures/dinosaure.png": true,
		"res://assets/parcel/creatures/primate_sapient.png": true,
		"res://assets/parcel/structures/building_megacity.png": true,
		"res://assets/parcel/structures/hut.png": true,
	}
	var exists := func(path: String) -> bool: return files.has(path)
	var cases := [
		[ParcelLogic.creature_asset_candidates("dinosaure", "carnivore"), "res://assets/parcel/creatures/dinosaure.png"],
		[ParcelLogic.creature_asset_candidates("primate", "sapient"), "res://assets/parcel/creatures/primate_sapient.png"],
		[ParcelLogic.creature_asset_candidates("ptérosaure", "carnivore"), ""],
		[ParcelLogic.creature_asset_candidates("", "herbivore"), ""],
		[ParcelLogic.structure_asset_candidates("building", "megacity"), "res://assets/parcel/structures/building_megacity.png"],
		[ParcelLogic.structure_asset_candidates("building", "town"), ""],
		[ParcelLogic.structure_asset_candidates("hut", "village"), "res://assets/parcel/structures/hut.png"],
	]
	for c in cases:
		var err := _expect(ParcelLogic.resolve_asset(c[0], exists), c[1], "asset pour %s" % str(c[0]))
		if err != "":
			return err
	var cands := ParcelLogic.creature_asset_candidates("Ptérosaure", "carnivore")
	return _expect(cands[1], "res://assets/parcel/creatures/pterosaure.png", "nom sans accents")


func test_slug() -> String:
	var cases := {
		"Ptérosaure": "pterosaure", "mammifère": "mammifere", "chimère": "chimere",
		"Forêt tempérée": "foret_temperee", "Dromæosauridés": "dromaeosaurides", "a-b/c": "a_bc",
	}
	for k in cases:
		var err := _expect(ParcelLogic.slug(k), cases[k], "slug(%s)" % k)
		if err != "":
			return err
	return ""


func test_ground_state() -> String:
	var G: Dictionary = ParcelLogic.Ground
	var cases := [
		["wild", "Désert", G.SAND], ["wild", "Forêt tropicale", G.LUSH], ["ocean", "Savane", G.WATER],
		["crater", "Toundra", G.CRATER], ["megacity", "Steppe", G.URBAN], ["farmland", "Steppe", G.DRY],
		["rewild", "Inconnu", G.GRASS],
	]
	for c in cases:
		var err := _expect(ParcelLogic.ground_kind(c[0], c[1]), c[2], "ground_kind(%s, %s)" % [c[0], c[1]])
		if err != "":
			return err
	if ParcelLogic.ground_state("crater", "Savane").z != 0.0:
		return "pas de végétation dans un cratère"
	if ParcelLogic.ground_state("farmland", "Savane").y <= 0.0:
		return "les terres agricoles doivent être labourées"
	return ""


func test_transition() -> String:
	var a := Vector3(0, 0, 1)
	var b := Vector3(3, 0, 0.15)
	var c := Vector3(9, 0, 0)
	var err := _expect(ParcelLogic.next_transition(a, a, 1.0, b), [a, b, 0.0], "nouvelle cible")
	if err != "":
		return err
	err = _expect(ParcelLogic.next_transition(a, b, 0.4, b), [a, b, 0.4], "même cible : on continue")
	if err != "":
		return err
	err = _expect(ParcelLogic.next_transition(a, b, 0.25, a), [b, a, 0.75], "retour : on rembobine")
	if err != "":
		return err
	err = _expect(ParcelLogic.next_transition(a, b, 0.8, c), [b, c, 0.0], "cible pendant un fondu")
	if err != "":
		return err
	return _expect(ParcelLogic.next_transition(a, b, 0.2, c), [a, c, 0.0], "cible au début d'un fondu")


func test_creature_appearance() -> String:
	var S: Dictionary = ParcelLogic.Shape
	var cases := [
		["dinosaure", "carnivore", 0.95, S.BIPED], ["dinosaure", "herbivore", 1.0, S.LONG_NECK],
		["dinosaure", "herbivore", 0.8, S.QUADRUPED], ["oiseau", "omnivore", 0.1, S.BIRD],
		["ptérosaure", "carnivore", 0.5, S.BIRD], ["reptile", "carnivore", 0.6, S.REPTILE],
		["dinosaure", "sapient", 0.3, S.HUMANOID], ["mammifère", "herbivore", 0.1, S.QUADRUPED],
	]
	for c in cases:
		var err := _expect(ParcelLogic.shape_for(c[0], c[1], c[2]), c[3], "shape_for(%s, %s)" % [c[0], c[1]])
		if err != "":
			return err
	if ParcelLogic.creature_length(1.0) <= ParcelLogic.creature_length(0.1):
		return "les grosses espèces doivent être plus grandes"
	if ParcelLogic.species_color("carnivore", 3) != ParcelLogic.species_color("carnivore", 3):
		return "couleur non déterministe"
	if ParcelLogic.species_color("carnivore", 3).is_equal_approx(ParcelLogic.species_color("herbivore", 3)):
		return "rôles indiscernables"
	return ""


func test_camera_limits() -> String:
	var parcel := Vector2(1920, 1080)
	var err := _expect(ParcelLogic.cover_zoom(Vector2(1920, 1080), parcel), 1.0, "zoom de couverture")
	if err != "":
		return err
	if ParcelLogic.cover_zoom(Vector2(1920, 1200), parcel) < 1200.0 / 1080.0:
		return "la parcelle doit couvrir tout l'écran"
	err = _expect(ParcelLogic.wheel_out(1.0, 1.0, 1.15), 1.0, "molette au minimum : on reste sur la parcelle")
	if err != "":
		return err
	if not is_equal_approx(ParcelLogic.wheel_out(2.3, 1.0, 1.15), 2.0):
		return "dézoom d'un cran attendu"
	err = _expect(ParcelLogic.clamp_camera(Vector2(0, 0), 2.0, Vector2(1920, 1080), parcel), Vector2(480, 270), "coin haut-gauche")
	if err != "":
		return err
	return _expect(ParcelLogic.clamp_camera(Vector2(100, 900), 1.0, Vector2(1920, 1080), parcel), Vector2(960, 540), "zoom minimal : centré")


func test_region_hits_parcel() -> String:
	var cases := [
		[Vector2i(70, 40), 0, Vector2i(70, 40), true], [Vector2i(75, 40), 4, Vector2i(70, 40), false],
		[Vector2i(73, 44), 5, Vector2i(70, 40), true], [Vector2i(254, 40), 3, Vector2i(1, 40), true],
	]
	for c in cases:
		var err := _expect(ParcelLogic.region_hits_parcel(c[0], c[1], c[2], 256), c[3], "région %s rayon %d" % [c[0], c[1]])
		if err != "":
			return err
	return ""


func test_structure_key_stable() -> String:
	var a := {kind = "hut", pos = Vector2(0.31234, 0.7), size = 0.04}
	var b := {kind = "hut", pos = Vector2(0.31234, 0.7), size = 0.05}
	var c := {kind = "building", pos = Vector2(0.31234, 0.7), size = 0.05}
	if ParcelLogic.structure_key(a) != ParcelLogic.structure_key(b):
		return "la clé ne doit dépendre que du type et de la position"
	if ParcelLogic.structure_key(a) == ParcelLogic.structure_key(c):
		return "types différents, clés identiques"
	return ""


func test_fallen_prey_leave_first() -> String:
	var g := CreatureGroup.new(5, Vector2i(3, 3))
	g.set_species({role = "herbivore", clade = "dinosaure", size = 0.5})
	g.set_target(5)
	g.strike(2, g.pos[2] + Vector2(10, 0), false)
	if g.state[2] != CreatureGroup.DOWN:
		return "la proie attrapée doit être à terre"
	g.set_target(4)
	if g.leaving[2] != 1:
		return "la baisse d'effectif doit d'abord emporter la proie à terre"
	if g.active_count() != 4:
		return "4 actifs attendus, %d" % g.active_count()
	g.strike(0, g.pos[0] + Vector2(10, 0), true)
	return _expect(g.state[0], CreatureGroup.RUN, "proie qui s'échappe")


func test_footprints_emitted() -> String:
	var g := CreatureGroup.new(6, Vector2i(1, 2))
	g.set_species({role = "carnivore", clade = "dinosaure", size = 0.95})
	g.set_target(1)
	g.alpha[0] = 1.0
	g.state[0] = CreatureGroup.WANDER
	g.timer[0] = 30.0
	g.pos[0] = Vector2(300, 500)
	g.goal[0] = Vector2(1500, 500)
	var ctx := {prey = PackedVector2Array(), prey_len = PackedFloat32Array(), hunters = PackedVector2Array(), spots = PackedVector2Array()}
	var prints := 0
	var dust := 0
	for i in 100:
		g.step(0.1, ctx)
		for k in range(0, g.emits.size(), CreatureGroup.EMIT_STRIDE):
			match int(g.emits[k]):
				CreatureGroup.EMIT_FOOTPRINT: prints += 1
				CreatureGroup.EMIT_DUST: dust += 1
	if prints < 4:
		return "un gros dinosaure qui marche doit laisser des empreintes (%d)" % prints
	if dust == 0:
		return "un gros dinosaure qui marche doit soulever de la poussière"
	return ""


func test_ambient_and_states() -> String:
	var none := ParcelLogic.ambient_counts("crater", 0.0, 0.0, 10.0, true)
	if none.flocks != 0 or none.swarms != 0 or none.gliders != 0:
		return "rien ne vole au-dessus d'un cratère : %s" % str(none)
	var lush := ParcelLogic.ambient_counts("wild", 0.9, 0.8, 25.0, true)
	if lush.flocks < 2 or lush.swarms < 5 or lush.gliders == 0:
		return "forêt humide : trop peu de vie d'ambiance %s" % str(lush)
	if ParcelLogic.ambient_counts("wild", 0.9, 0.8, -10.0, false).swarms != 0:
		return "pas d'insectes dans le grand froid"
	var a := ParcelLogic.swarm_centers(Vector2i(7, 9), 8, PackedVector2Array())
	if a != ParcelLogic.swarm_centers(Vector2i(7, 9), 8, PackedVector2Array()) or a.size() != 8:
		return "centres d'essaims non déterministes"
	for st in [[CreatureGroup.POUNCE, 3.0], [CreatureGroup.DOWN, 4.0], [CreatureGroup.EAT, 1.0], [CreatureGroup.VISIT, 0.0]]:
		var err := _expect(ParcelLogic.visual_state(st[0]), st[1], "visual_state(%d)" % st[0])
		if err != "":
			return err
	return ""


func test_day_and_seasons() -> String:
	if ParcelLogic.daylight(0.5) < 0.95 or ParcelLogic.daylight(0.0) > 0.05:
		return "midi doit être clair, minuit sombre"
	var night := ParcelLogic.sky_color(0.0, 0.0)
	if night.b <= night.r or night.v > 0.7:
		return "la nuit doit être sombre et bleutée : %s" % str(night)
	if not ParcelLogic.sky_color(0.5, 0.0).is_equal_approx(Color.WHITE):
		return "midi sans nuages : lumière blanche"
	if ParcelLogic.season_offset_c(0.0, 10.0) >= 0.0 or ParcelLogic.season_offset_c(0.5, 10.0) <= 0.0:
		return "hiver plus froid, été plus chaud"
	if absf(ParcelLogic.season_offset_c(0.0, 30.0)) > absf(ParcelLogic.season_offset_c(0.0, 10.0)):
		return "saisons plus marquées en zone tempérée que sous les tropiques"
	if ParcelLogic.snow_cover(-10.0, 0.6) < 0.5 or ParcelLogic.snow_cover(10.0, 0.6) > 0.0:
		return "neige seulement par grand froid"
	if ParcelLogic.autumn(0.75, 12.0) < 0.5 or ParcelLogic.autumn(0.25, 12.0) > 0.0 or ParcelLogic.autumn(0.75, 30.0) > 0.1:
		return "feuilles rousses en automne, en zone tempérée seulement"
	return ""


func test_weather_choice() -> String:
	var seen := {}
	for i in 100:
		var r := i / 100.0
		if ParcelLogic.pick_weather(r, 0.0, 30.0, "wild") in ["rain", "storm", "snow"]:
			return "pas de précipitations dans un désert sec"
		seen[ParcelLogic.pick_weather(r, 0.9, 20.0, "wild")] = true
		if ParcelLogic.pick_weather(r, 0.9, -10.0, "wild") in ["rain", "storm"]:
			return "pas de pluie par -10 °C"
	for w in ["clear", "rain", "storm", "fog"]:
		if not seen.has(w):
			return "climat chaud et humide : météo « %s » jamais tirée" % w
	var ash := 0
	for i in 100:
		if ParcelLogic.pick_weather(i / 100.0, 0.3, 15.0, "crater") == "ash":
			ash += 1
	if ash < 40:
		return "un cratère doit surtout avoir des cendres (%d %%)" % ash
	return ""


func test_landmarks_continuity() -> String:
	var a := ParcelLogic.landmarks(42, Vector2i(70, 40))
	var b := ParcelLogic.landmarks(42, Vector2i(70, 40))
	if a != b:
		return "les repères doivent être identiques à graine et cellule égales"
	var river: PackedVector2Array = a.river
	var size := ParcelLogic.PARCEL_SIZE
	if river[0].x > size.x * 0.4 or river[0].y > 0.0:
		return "la rivière doit entrer en haut à gauche : %s" % str(river[0])
	if river[-1].x < size.x * 0.6 or river[-1].y < size.y:
		return "la rivière doit sortir en bas à droite : %s" % str(river[-1])
	var rock: Vector2 = a.rock_pos
	if rock.x > size.x / 3.0 + 20.0:
		return "le rocher doit être au tiers gauche : %s" % str(rock)
	if ParcelLogic.distance_to_polyline(rock, river) < float(a.river_width) * 0.5 + Vector2(a.rock_radii).x:
		return "le rocher ne doit pas toucher la rivière"
	# Forme en S : la rivière s'écarte des deux côtés de la diagonale.
	var dir := (river[-1] - river[0]).normalized()
	var perp := dir.orthogonal()
	var left := false
	var right := false
	for q in river:
		var off := (q - river[0]).dot(perp)
		left = left or off > 60.0
		right = right or off < -60.0
	if not (left and right):
		return "la rivière doit faire un S"
	return ""


func test_avoid_landmarks() -> String:
	var lm := ParcelLogic.landmarks(7, Vector2i(3, 4))
	var river: PackedVector2Array = lm.river
	var on_river := river[10]
	var moved := ParcelLogic.avoid_landmarks(on_river, 30.0, lm)
	if ParcelLogic.distance_to_polyline(moved, river) < float(lm.river_width) * 0.5 + 30.0:
		return "une maison posée sur la rivière doit être écartée"
	if moved != ParcelLogic.avoid_landmarks(on_river, 30.0, lm):
		return "l'écartement doit être stable"
	var on_rock := ParcelLogic.avoid_landmarks(lm.rock_pos, 20.0, lm)
	if on_rock.distance_to(lm.rock_pos) < Vector2(lm.rock_radii).x:
		return "une maison posée sur le rocher doit être écartée"
	var free := Vector2(1800, 60)
	if ParcelLogic.distance_to_polyline(free, river) > 200.0 and ParcelLogic.avoid_landmarks(free, 20.0, lm) != free:
		return "une maison loin des repères ne bouge pas"
	var spot := ParcelLogic.drinking_spot(Vector2(200, 900), river, lm.river_width, 10.0)
	var d := ParcelLogic.distance_to_polyline(spot, river)
	if absf(d - (float(lm.river_width) * 0.5 + 10.0)) > 1.0:
		return "le point où boire doit être au bord de l'eau (%f)" % d
	var rs := ParcelLogic.river_state("city", 0.5, 0.0)
	if rs.z != 1.0 or rs.w <= 0.0:
		return "en ville, la rivière devient un canal (pollué)"
	if ParcelLogic.river_state("wild", 0.02, 0.0).x > 0.0:
		return "rivière à sec quand l'eau manque"
	if ParcelLogic.river_state("ice", 0.5, 0.0).y != 1.0:
		return "rivière gelée sous la banquise"
	return ""
