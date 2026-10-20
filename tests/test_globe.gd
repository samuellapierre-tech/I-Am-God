extends RefCounted
## Tests du globe 3D (fonctions pures, sans rendu) : rayon -> lat/long -> cellule (pôles, couture),
## caméra orbitale, bascule des vues, aucune double application d'un pouvoir, re-téléversement de la
## géographie quand geography_version change (simulation factice), lecture de la vie marine.

const GlobeMath := preload("res://src/globe/globe_math.gd")
const OrbitState := preload("res://src/globe/orbit_state.gd")
const GlobeTextures := preload("res://src/globe/globe_textures.gd")
const PlanetState := preload("res://src/globe/planet_state.gd")
const GlobePins := preload("res://src/globe/globe_pins.gd")
const ViewRouter := preload("res://src/globe/view_router.gd")

const GRID := Vector2i(256, 128)


## Simulation factice minimale (contrat public de WorldSim + champs de la future tectonique).
class StubSim:
	const WIDTH := 8
	const HEIGHT := 4
	var elevation := PackedFloat32Array()
	var temperature := PackedFloat32Array()
	var population := PackedFloat32Array()
	var tech := PackedFloat32Array()
	var dominant_species := PackedInt32Array()
	var species := {}
	var geography_version := 0
	var plate_id := PackedInt32Array()

	func _init() -> void:
		for i in WIDTH * HEIGHT:
			elevation.append(-0.5 if i % 2 == 0 else 0.3)
			temperature.append(0.5)
			population.append(0.0)
			tech.append(0.0)
			dominant_species.append(-1)
			plate_id.append(i % 3)

	func region_niches(cell: Vector2i) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		if cell.x < WIDTH / 2:
			out.append({species_id = 5, density = 0.6, habitat = "marine"})
		else:
			out.append({species_id = 9, density = 0.4, habitat = "land"})
		return out


## Variante : la version de géographie est une méthode, et pas de plaques.
class MethodSim:
	const WIDTH := 8
	const HEIGHT := 4
	var elevation := PackedFloat32Array()
	var temperature := PackedFloat32Array()
	var population := PackedFloat32Array()
	var tech := PackedFloat32Array()
	var dominant_species := PackedInt32Array()
	var species := {}
	var version := 3

	func _init() -> void:
		for i in WIDTH * HEIGHT:
			elevation.append(0.1)
			temperature.append(0.5)
			population.append(0.0)
			tech.append(0.0)
			dominant_species.append(-1)

	func geography_version() -> int:
		return version


## Vue factice : reçoit les clics seulement si elle traite les entrées (comme _unhandled_input).
class FakeView:
	extends Node
	signal state_changed
	var power := ""
	var radius := 8
	var target_species := -1
	var applied := 0

	func set_power(id: String) -> void:
		power = id
		state_changed.emit()

	func set_radius(r: int) -> void:
		radius = r

	func set_target_species(id: int) -> void:
		target_species = id

	func receive_click() -> void:
		if process_mode != Node.PROCESS_MODE_DISABLED and power != "":
			applied += 1


func _near(got: float, want: float, what: String, eps := 1e-4) -> String:
	if absf(got - want) > eps:
		return "%s : obtenu %f, attendu %f" % [what, got, want]
	return ""


# --- Coordonnées ---

func test_dir_uv_round_trip() -> String:
	for uv in [Vector2(0.1, 0.2), Vector2(0.5, 0.5), Vector2(0.99, 0.9), Vector2(0.0, 0.3)]:
		var back := GlobeMath.dir_to_uv(GlobeMath.uv_to_dir(uv))
		if absf(GlobeMath.wrap_angle((back.x - uv.x) * TAU)) > 1e-4 or absf(back.y - uv.y) > 1e-4:
			return "aller-retour uv %s -> %s" % [uv, back]
	return ""


func test_every_cell_round_trip() -> String:
	for y in GRID.y:
		for x in GRID.x:
			var c := Vector2i(x, y)
			var got := GlobeMath.dir_to_cell(GlobeMath.cell_to_dir(c, GRID), GRID)
			if got != c:
				return "cellule %s -> %s" % [c, got]
	return ""


func test_poles() -> String:
	if GlobeMath.dir_to_cell(Vector3.UP, GRID).y != 0:
		return "pôle Nord hors de la première ligne"
	if GlobeMath.dir_to_cell(Vector3.DOWN, GRID).y != GRID.y - 1:
		return "pôle Sud hors de la dernière ligne"
	for lon in [0.0, 1.0, -2.5, PI]:
		var c := GlobeMath.dir_to_cell(GlobeMath.lat_lon_to_dir(deg_to_rad(89.9), lon), GRID)
		if c.y != 0 or c.x < 0 or c.x >= GRID.x:
			return "près du pôle Nord : %s" % c
	return ""


func test_longitude_seam() -> String:
	var west := GlobeMath.dir_to_cell(GlobeMath.lat_lon_to_dir(0.1, -0.001), GRID)
	var east := GlobeMath.dir_to_cell(GlobeMath.lat_lon_to_dir(0.1, 0.001), GRID)
	if west.x != GRID.x - 1 or east.x != 0:
		return "couture : ouest %s, est %s" % [west, east]
	var anti := GlobeMath.dir_to_cell(GlobeMath.lat_lon_to_dir(0.0, PI - 1e-4), GRID)
	if anti.x != GRID.x / 2 - 1:
		return "antiméridien : %s" % anti
	if GlobeMath.uv_to_cell(Vector2(1.0, 0.5), GRID).x != 0:
		return "uv.x = 1 doit boucler sur la colonne 0"
	return ""


func test_ray_sphere() -> String:
	var err := _near(GlobeMath.ray_sphere(Vector3(0, 0, 3), Vector3(0, 0, -1)), 2.0, "entrée frontale")
	if err != "":
		return err
	if GlobeMath.ray_sphere(Vector3(0, 0, 3), Vector3(0, 1, 0)) >= 0.0:
		return "un rayon parallèle ne doit pas toucher"
	if GlobeMath.ray_sphere(Vector3(0, 0, 3), Vector3(0, 0, 1)) >= 0.0:
		return "un rayon qui s'éloigne ne doit pas toucher"
	if GlobeMath.ray_to_cell(Vector3(0, 0, 3), Vector3(1, 0, 0), GRID) != Vector2i(-1, -1):
		return "rayon manqué : (-1, -1) attendu"
	return ""


## Le rayon du centre de l'écran touche toujours la cellule visée, même incliné, au pôle et sur la couture.
func test_screen_center_hits_target() -> String:
	var vp := Vector2(1920, 1080)
	for case in [[0.3, 1.2, 2.0], [-0.7, -3.1, 0.5], [deg_to_rad(84.0), 0.0, 1.0], [0.0, PI - 0.002, 0.04],
			[0.2, -0.004, 0.1]]:
		var lat: float = case[0]
		var lon: float = case[1]
		var alt: float = case[2]
		var cam := GlobeMath.orbit_transform(lat, lon, alt, GlobeMath.tilt_for_altitude(alt))
		var ray := GlobeMath.perspective_ray(vp * 0.5, vp, cam, 45.0)
		var got := GlobeMath.ray_to_cell(ray[0], ray[1], GRID)
		var want := GlobeMath.dir_to_cell(GlobeMath.lat_lon_to_dir(lat, lon), GRID)
		if got != want:
			return "centre (%f, %f, alt %f) : %s au lieu de %s" % [lat, lon, alt, got, want]
	return ""


## Est à droite, nord en haut, et un coin d'écran en orbite haute manque la planète.
func test_screen_orientation() -> String:
	var vp := Vector2(1920, 1080)
	var cam := GlobeMath.orbit_transform(0.0, 0.5, 1.5)
	var center: Array = GlobeMath.perspective_ray(vp * 0.5, vp, cam, 45.0)
	var right: Array = GlobeMath.perspective_ray(vp * 0.5 + Vector2(120, 0), vp, cam, 45.0)
	var up: Array = GlobeMath.perspective_ray(vp * 0.5 - Vector2(0, 120), vp, cam, 45.0)
	var pc: Vector3 = center[0] + center[1] * GlobeMath.ray_sphere(center[0], center[1])
	var pr: Vector3 = right[0] + right[1] * GlobeMath.ray_sphere(right[0], right[1])
	var pu: Vector3 = up[0] + up[1] * GlobeMath.ray_sphere(up[0], up[1])
	if GlobeMath.dir_to_lat_lon(pr).y <= GlobeMath.dir_to_lat_lon(pc).y:
		return "la droite de l'écran n'est pas à l'est"
	if GlobeMath.dir_to_lat_lon(pu).x <= GlobeMath.dir_to_lat_lon(pc).x:
		return "le haut de l'écran n'est pas au nord"
	var corner: Array = GlobeMath.perspective_ray(Vector2.ZERO, vp, GlobeMath.orbit_transform(0.0, 0.0, 3.0), 45.0)
	if GlobeMath.ray_to_cell(corner[0], corner[1], GRID) != Vector2i(-1, -1):
		return "le coin de l'écran devrait voir l'espace"
	return ""


# --- Caméra orbitale ---

func test_orbit_drag_and_inertia() -> String:
	var o := OrbitState.new()
	o.jump_to(0.0, 0.0)
	o.altitude = 1.0
	o.target_altitude = 1.0
	o.drag(Vector2(40, 0), 1080.0, 45.0)
	o.update(1.0 / 60.0)
	if o.lon >= 0.0:
		return "glisser à droite doit montrer l'ouest (lon %f)" % o.lon
	o.drag(Vector2(0, 40), 1080.0, 45.0)
	if o.lat <= 0.0:
		return "glisser vers le bas doit montrer le nord (lat %f)" % o.lat
	o.release()
	var before := o.lon
	o.update(1.0 / 60.0)
	if o.lon >= before:
		return "l'inertie doit prolonger le mouvement"
	for i in 600:
		o.update(1.0 / 60.0)
	if o.velocity != Vector2.ZERO:
		return "l'inertie doit s'éteindre"
	return ""


func test_orbit_zoom_and_focus() -> String:
	var o := OrbitState.new()
	for i in 200:
		o.wheel(-1.0)
	if o.target_altitude != GlobeMath.MIN_ALTITUDE:
		return "zoom borné au minimum"
	for i in 300:
		o.update(1.0 / 60.0)
	if not GlobeMath.should_descend(o.target_altitude, o.altitude):
		return "au zoom maximal, un cran de plus doit descendre au sol"
	if GlobeMath.should_descend(0.5, 0.5):
		return "pas de descente en orbite"
	o.focus(0.4, PI - 0.1)
	o.jump_to(0.0, -PI + 0.1)
	o.focus(0.4, PI - 0.1)
	for i in 600:
		o.update(1.0 / 60.0)
	if absf(o.lat - 0.4) > 1e-3 or absf(GlobeMath.wrap_angle(o.lon - (PI - 0.1))) > 1e-3:
		return "centrage (par la couture) : %f, %f" % [o.lat, o.lon]
	return ""


# --- Bascule des vues ---

func test_view_switch() -> String:
	if ViewRouter.toggled("globe") != "ground" or ViewRouter.toggled("ground") != "globe":
		return "Tab doit alterner globe et sol"
	if ViewRouter.is_valid("parcel") or not ViewRouter.is_valid("ground"):
		return "modes valides : globe, ground"
	var g := FakeView.new()
	var cam3 := Camera3D.new()
	g.add_child(cam3)
	var p := FakeView.new()
	var cam2 := Camera2D.new()
	p.add_child(cam2)
	var views := {"globe": [g], "ground": [p]}
	ViewRouter.apply("ground", views)
	var err := ""
	if g.process_mode != Node.PROCESS_MODE_DISABLED or p.process_mode == Node.PROCESS_MODE_DISABLED:
		err = "au sol, seul le sol traite les entrées"
	elif cam3.current or not cam2.enabled:
		err = "au sol : caméra 2D active, caméra 3D éteinte"
	else:
		ViewRouter.apply("globe", views)
		if p.process_mode != Node.PROCESS_MODE_DISABLED or cam2.enabled:
			err = "au globe, la vue rapprochée doit être éteinte"
		elif ViewRouter.input_owner("globe", views) != g:
			err = "le globe doit recevoir les entrées"
	if err == "" and not ViewRouter.should_ascend(1.0, 1.01, 1.0):
		err = "dézoom au minimum au sol : retour au globe"
	if err == "" and ViewRouter.should_ascend(1.5, 1.5, 1.0):
		err = "pas de retour au globe tant qu'on peut dézoomer"
	g.free()
	p.free()
	return err


func test_no_double_power_application() -> String:
	var g := FakeView.new()
	var p := FakeView.new()
	var views := {"globe": [g], "ground": [p]}
	ViewRouter.apply("globe", views)
	g.set_power("meteor")
	g.set_radius(5)
	g.set_target_species(7)
	# On descend au sol : l'outil suit, l'ancienne vue est désarmée.
	ViewRouter.apply("ground", views)
	ViewRouter.transfer_power_state(g, p)
	var err := ""
	if p.power != "meteor" or p.radius != 5 or p.target_species != 7:
		err = "l'outil doit suivre la vue active (%s, %d, %d)" % [p.power, p.radius, p.target_species]
	elif g.power != "":
		err = "la vue quittée doit être désarmée"
	else:
		# Le même clic atteint les deux vues : une seule l'applique.
		g.receive_click()
		p.receive_click()
		if g.applied + p.applied != 1 or p.applied != 1:
			err = "pouvoir appliqué %d fois (globe %d, sol %d)" % [g.applied + p.applied, g.applied, p.applied]
	g.free()
	p.free()
	return err


# --- Textures et géographie ---

func test_geography_reupload_follows_version() -> String:
	var sim := StubSim.new()
	var tex := GlobeTextures.new()
	if not tex.pack(sim):
		return "empaquetage refusé"
	if tex.geography_uploads != 0 or tex.geography_fade != 1.0:
		return "pas de fondu au premier empaquetage"
	if not tex.has_plates() or tex.aux_image.get_pixel(1, 0).a != 1.0:
		return "plaques non écrites (%f)" % tex.aux_image.get_pixel(1, 0).a
	tex.pack(sim)
	if tex.geography_uploads != 0:
		return "re-téléversement sans changement de géographie"
	var old_elev := sim.elevation[0]
	sim.elevation[0] = 0.9
	sim.plate_id[1] = 2
	sim.geography_version += 1
	tex.pack(sim)
	if tex.geography_uploads != 1 or tex.geography_fade != 0.0:
		return "la nouvelle géographie doit déclencher un fondu (%d, %f)" % [tex.geography_uploads, tex.geography_fade]
	var err := _near(tex.prev_elevation_image.get_pixel(0, 0).r, old_elev, "élévation d'avant le changement")
	if err != "":
		return err
	if tex.aux_image.get_pixel(1, 0).a != 2.0:
		return "plaques non mises à jour"
	tex.advance_fade(GlobeTextures.GEO_FADE_TIME * 2.0)
	if tex.geography_fade != 1.0:
		return "le fondu doit se terminer"
	return ""


func test_geography_version_method_and_absence() -> String:
	var sim := MethodSim.new()
	if GlobeTextures.read_geography_version(sim) != 3:
		return "version lue par méthode"
	var tex := GlobeTextures.new()
	tex.pack(sim)
	sim.version = 4
	tex.pack(sim)
	if tex.geography_uploads != 1:
		return "changement de version (méthode) ignoré"
	if tex.has_plates():
		return "pas de plaques dans cette simulation"
	var plain := RefCounted.new()
	if GlobeTextures.read_geography_version(plain) != -1:
		return "sans tectonique, version -1"
	return ""


func test_life_reads_marine_and_land() -> String:
	var sim := StubSim.new()
	var tex := GlobeTextures.new()
	tex.pack(sim)
	var done := false
	for i in 10:
		if tex.update_life(sim, 1):
			done = true
			break
	if not done or tex.life_sweeps != 1:
		return "balayage de la vie non terminé"
	var sea := tex.aux_image.get_pixel(0, 0)
	var land := tex.aux_image.get_pixel(5, 2)
	if absf(sea.r - 0.6) > 1e-4 or sea.b != 5.0:
		return "vie marine mal lue : %s" % sea
	if absf(land.g - 0.4) > 1e-4 or land.r != 0.0:
		return "vie terrestre mal lue : %s" % land
	return ""


func test_planet_state_fallbacks() -> String:
	var s := PlanetState.read(RefCounted.new())
	if s.oxygen != 1.0 or s.land_flora != 1.0 or s.sea_level != 0.0 or s.snowball != 0.0:
		return "valeurs par défaut : %s" % s
	var sim := preload("res://src/sim/world_sim.gd").new(3)
	var w := PlanetState.read(sim)
	for key in ["oxygen", "ozone", "greenhouse", "land_flora"]:
		if not is_finite(float(w[key])) or w[key] < 0.0:
			return "%s invalide : %s" % [key, w[key]]
	if w.oxygen < 0.1 and w.ozone > 0.5:
		return "pas d'ozone sans oxygène"
	return ""


func test_pins() -> String:
	var pins := GlobePins.new()
	pins.add(Vector2i(1, 2), "a")
	if pins.add(Vector2i(1, 2), "b") != 0 or pins.pins.size() != 1:
		return "une cellule ne s'épingle qu'une fois"
	for i in GlobePins.MAX_PINS + 3:
		pins.add(Vector2i(10 + i, 3), "p")
	if pins.pins.size() != GlobePins.MAX_PINS:
		return "nombre d'épingles borné"
	pins.remove(0)
	if pins.pins.size() != GlobePins.MAX_PINS - 1:
		return "retrait d'une épingle"
	return ""


## Les moyennes des rangées polaires (convergence de la texture au pôle) suivent la simulation.
func test_pole_averages() -> String:
	var sim := StubSim.new()
	var tex := GlobeTextures.new()
	tex.pack(sim)
	# Rangée 0 : élévations -0.5 et 0.3 en alternance -> moyenne -0.1 ; température 0.5.
	var err := _near(tex.pole_data[0].x, -0.1, "élévation moyenne au pôle Nord")
	if err == "":
		err = _near(tex.pole_data[1].y, 0.5, "température moyenne au pôle Sud")
	if err != "":
		return err
	for x in StubSim.WIDTH:
		sim.temperature[(StubSim.HEIGHT - 1) * StubSim.WIDTH + x] = 0.1
	tex.pack(sim)
	err = _near(tex.pole_data[1].y, 0.1, "la moyenne polaire suit la simulation")
	if err != "":
		return err
	for i in 10:
		if tex.update_life(sim, 1):
			break
	# Pôle Nord : moitié ouest marine (0.6), moitié est terrestre (0.4).
	err = _near(tex.pole_aux[0].x, 0.3, "vie marine moyenne au pôle")
	if err == "":
		err = _near(tex.pole_aux[0].y, 0.2, "vie terrestre moyenne au pôle")
	return err
