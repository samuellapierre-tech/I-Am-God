extends RefCounted
## Tests de la carte : formatage des années, conversion écran -> région avec bouclage,
## empaquetage des grilles en textures, catalogue des pouvoirs.

const MapMath := preload("res://src/map/map_math.gd")
const Packer := preload("res://src/map/world_texture_packer.gd")
const Powers := preload("res://src/map/divine_powers.gd")


## Simulation factice minimale respectant le contrat public de WorldSim.
class StubSim:
	const WIDTH := 4
	const HEIGHT := 2
	var year := -66_000_000.0
	var elevation := PackedFloat32Array()
	var temperature := PackedFloat32Array()
	var population := PackedFloat32Array()
	var tech := PackedFloat32Array()
	var dominant_species := PackedInt32Array()
	var species := {
		3: {name = "Raptors", alive = true, sapient = false, population = 100.0, traits = {}},
		7: {name = "Humains", alive = true, sapient = true, population = 1000.0, traits = {}},
	}

	func _init() -> void:
		var n := WIDTH * HEIGHT
		for i in n:
			elevation.append(-1.0 + i * 0.25)
			temperature.append(i / float(n))
			population.append(0.1 * i)
			tech.append(0.05 * i)
			dominant_species.append(-1 if i < 2 else (3 if i < 5 else 7))

	func current_era() -> String:
		return "Mésozoïque"


func _expect(got, want, what: String) -> String:
	if got != want:
		return "%s : obtenu %s, attendu %s" % [what, str(got), str(want)]
	return ""


func _near(got: float, want: float, what: String) -> String:
	if absf(got - want) > 1e-4:
		return "%s : obtenu %f, attendu %f" % [what, got, want]
	return ""


func test_format_year_millions() -> String:
	var cases := {
		-66_000_000.0: "66 M av. J.-C.",
		-65_950_000.0: "66 M av. J.-C.",
		-1_500_000.0: "1,5 M av. J.-C.",
		-2_500_000_000.0: "2,5 Md av. J.-C.",
		3_000_000.0: "3 M apr. J.-C.",
	}
	for y in cases:
		var err := _expect(MapMath.format_year(y), cases[y], "format_year(%s)" % y)
		if err != "":
			return err
	return ""


func test_format_year_historic() -> String:
	var cases := {
		1250.0: "1 250 apr. J.-C.",
		2077.0: "2 077 apr. J.-C.",
		476.4: "476 apr. J.-C.",
		-12_500.0: "12 500 av. J.-C.",
		-500.0: "500 av. J.-C.",
		-0.2: "1 av. J.-C.",
		250_000.0: "250 000 apr. J.-C.",
	}
	for y in cases:
		var err := _expect(MapMath.format_year(y), cases[y], "format_year(%s)" % y)
		if err != "":
			return err
	return ""


func test_group_thousands() -> String:
	for pair in [[0, "0"], [999, "999"], [1000, "1 000"], [1234567, "1 234 567"], [-4500, "-4 500"]]:
		var err := _expect(MapMath.group_thousands(pair[0]), pair[1], "group_thousands(%d)" % pair[0])
		if err != "":
			return err
	return ""


func test_world_to_region_wraps_horizontally() -> String:
	var cases := [
		[Vector2(4, 4), Vector2i(0, 0)],
		[Vector2(-1, 10), Vector2i(255, 1)],
		[Vector2(2048 + 9, 5), Vector2i(1, 0)],
		[Vector2(-2048 * 3 + 17, 20), Vector2i(2, 2)],
		[Vector2(10, -50), Vector2i(1, 0)],
		[Vector2(10, 99999), Vector2i(1, 127)],
	]
	for c in cases:
		var err := _expect(MapMath.world_to_region(c[0], 8.0, 256, 128), c[1], "world_to_region(%s)" % c[0])
		if err != "":
			return err
	return ""


func test_screen_to_region_with_camera_transform() -> String:
	# Caméra zoomée x2, origine du monde à +100 px à l'écran.
	var xform := Transform2D(0.0, Vector2(2, 2), 0.0, Vector2(100, 0))
	var world := Vector2(8 * 10 + 4, 8 * 3 + 4)
	var screen := xform * world
	var err := _expect(MapMath.screen_to_region(screen, xform, 8.0, 256, 128), Vector2i(10, 3), "screen_to_region")
	if err != "":
		return err
	# Un point écran à gauche de l'origine du monde boucle sur le bord droit de la grille.
	return _expect(MapMath.screen_to_region(Vector2(0, 0), xform, 8.0, 256, 128), Vector2i(249, 0),
			"screen_to_region (bouclage)")


func test_region_to_world_nearest_copy() -> String:
	var p := MapMath.region_to_world(Vector2i(255, 0), 8.0, 256, 4.0)
	var err := _near(p.x, -4.0, "copie la plus proche à gauche")
	if err != "":
		return err
	p = MapMath.region_to_world(Vector2i(0, 0), 8.0, 256, 2040.0)
	return _near(p.x, 2052.0, "copie la plus proche à droite")


func test_era_index() -> String:
	var err := _expect(MapMath.era_index("Cyberpunk"), 8, "Cyberpunk")
	if err == "":
		err = _expect(MapMath.era_index("Mésozoïque"), 0, "Mésozoïque")
	if err == "":
		err = _expect(MapMath.era_index("Ère industrielle"), 6, "repli par mot-clé")
	if err == "":
		err = _expect(MapMath.era_index("???"), 0, "ère inconnue")
	return err


func test_base_rate_follows_sim_pacing() -> String:
	# Le rythme vient du pas idéal de la simulation (ère / technologie), pas de l'année.
	var steps := [50_000.0, 500.0, 10.0, 0.5]
	for i in steps.size() - 1:
		if MapMath.base_years_per_second(steps[i]) <= MapMath.base_years_per_second(steps[i + 1]):
			return "le temps devrait ralentir quand le pas idéal diminue (%s -> %s)" % [steps[i], steps[i + 1]]
	var sim := preload("res://src/sim/world_sim.gd").new(1)
	var rate := MapMath.base_years_per_second(sim.ideal_step_years())
	if absf(rate - sim.pacing_years_per_second()) > 1e-6 or rate < 100_000.0:
		return "rythme initial incohérent avec la simulation : %f" % rate
	return ""


func test_species_color_is_stable_and_distinct() -> String:
	if MapMath.species_color(3) != MapMath.species_color(3):
		return "couleur instable"
	if MapMath.species_color(3).is_equal_approx(MapMath.species_color(4)):
		return "deux espèces voisines ont la même couleur"
	return _near(MapMath.species_hue(0), 0.13, "teinte de l'espèce 0")


func test_pack_stub_sim_size_and_values() -> String:
	var sim := StubSim.new()
	var packer := Packer.new()
	if Packer.grid_size(sim) != Vector2i(4, 2):
		return "grid_size : %s" % Packer.grid_size(sim)
	if not packer.pack(sim):
		return "pack a échoué"
	var img: Image = packer.data_image
	if img.get_size() != Vector2i(4, 2) or img.get_format() != Image.FORMAT_RGBAF:
		return "image de données : taille %s format %d" % [img.get_size(), img.get_format()]
	if packer.data_texture.get_size() != Vector2(4, 2):
		return "texture de données : %s" % packer.data_texture.get_size()
	# Cellule (1, 1) -> index 5.
	var c := img.get_pixel(1, 1)
	for e in [_near(c.r, sim.elevation[5], "élévation"), _near(c.g, sim.temperature[5], "température"),
			_near(c.b, sim.population[5], "population"), _near(c.a, sim.tech[5], "tech")]:
		if e != "":
			return e
	var s0 := packer.species_image.get_pixel(0, 0)
	var s5 := packer.species_image.get_pixel(1, 1)
	var s3 := packer.species_image.get_pixel(3, 0)
	for e in [_near(s0.r, -1.0, "aucune espèce"), _near(s0.g, 0.0, "aucune espèce vivante"),
			_near(s5.r, 7.0, "id espèce"), _near(s5.b, 1.0, "sapiente"), _near(s5.g, 1.0, "vivante"),
			_near(s3.r, 3.0, "id espèce 3"), _near(s3.b, 0.0, "non sapiente")]:
		if e != "":
			return e
	return ""


func test_pack_updates_textures_in_place() -> String:
	var sim := StubSim.new()
	var packer := Packer.new()
	packer.pack(sim)
	var tex := packer.data_texture
	var img := packer.data_image
	sim.elevation[0] = 0.75
	sim.species[7].alive = false
	packer.pack(sim)
	if packer.data_texture != tex or packer.data_image != img:
		return "la texture devrait être mise à jour, pas recréée"
	var err := _near(packer.data_image.get_pixel(0, 0).r, 0.75, "élévation mise à jour")
	if err != "":
		return err
	return _near(packer.species_image.get_pixel(1, 1).g, 0.0, "espèce éteinte")


func test_pack_rejects_incomplete_sim() -> String:
	var sim := StubSim.new()
	sim.tech.resize(3)
	if Packer.new().pack(sim):
		return "une grille trop courte devrait être refusée"
	if Packer.new().pack(null):
		return "null devrait être refusé"
	return ""


func test_divine_powers_catalogue() -> String:
	var expected := ["meteor", "extinct", "save", "bless", "plague", "uplift", "flood", "ice_age", "spawn_species"]
	if Powers.LIST.size() != expected.size():
		return "nombre de pouvoirs : %d" % Powers.LIST.size()
	var keys := {}
	for i in expected.size():
		if Powers.LIST[i].id != expected[i]:
			return "pouvoir %d : %s" % [i, Powers.LIST[i].id]
		if keys.has(Powers.LIST[i].key):
			return "raccourci en double : %s" % Powers.LIST[i].id
		keys[Powers.LIST[i].key] = true
	var a := Powers.make_action("plague", Vector2i(3, 4), 7, 5)
	if a.type != "plague" or a.region != Vector2i(3, 4) or a.species_id != 7 or a.radius != 5:
		return "action mal formée : %s" % a
	return ""
