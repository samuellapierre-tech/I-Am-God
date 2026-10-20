extends Node3D
## Globe 3D de la planète (docs/GENESE.md, chantier 1) : rendu par shaders/globe.gdshader à partir des
## grilles de WorldSim, atmosphère (globe_atmosphere.gdshader) et ciel étoilé (globe_sky.gdshader).
##
## Contrôles : glisser (gauche, droit ou milieu) = tourner avec inertie ; molette = zoom continu,
## légèrement attiré vers le curseur ; double-clic = centrer ; clic avec un pouvoir = pouvoir à cet
## endroit ; clic simple = infos de la région ; F1…F7 = calques ; P = épingler le centre ; flèches et
## sticks de manette = tourner, stick droit = zoomer, A = pouvoir au centre.
## Zoom maximal puis un cran de plus : descend_requested(cellule) — main.gd descend dans la vue
## rapprochée de ce lieu.
##
## La racine expose la même API que l'ancienne carte (src/map/world_map.gd) pour le HUD (bind_map) :
## power, radius, layer, target_species, grid, LAYERS, set_power, set_radius, set_layer,
## set_target_species, focus_region, screen_to_region, dominant_species_at, apply_power_at,
## signaux state_changed et region_hovered.

const GlobeMath := preload("res://src/globe/globe_math.gd")
const OrbitState := preload("res://src/globe/orbit_state.gd")
const GlobeTextures := preload("res://src/globe/globe_textures.gd")
const PlanetState := preload("res://src/globe/planet_state.gd")
const GlobePins := preload("res://src/globe/globe_pins.gd")
const GlobeUI := preload("res://src/globe/globe_ui.gd")
const ToolStateScript := preload("res://src/ui/tools/tool_state.gd")
const Powers := preload("res://src/map/divine_powers.gd")
const WorldSim := preload("res://src/sim/world_sim.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")
const GLOBE_SHADER := preload("res://shaders/globe.gdshader")
const ATMOSPHERE_SHADER := preload("res://shaders/globe_atmosphere.gdshader")
const SKY_SHADER := preload("res://shaders/globe_sky.gdshader")

## Calques (index envoyé au shader) : nature, vie, température, ozone, plaques, espèces, civilisations.
const LAYERS := ["Nature", "Vie", "Temp.", "Ozone", "Plaques", "Espèces", "Civil."]
const LAYER_NAMES := ["Nature", "Vie", "Température", "Ozone", "Plaques", "Espèces", "Civilisations"]
const MAX_IMPACTS := 8
const ANIM_TIME_WRAP := 3600.0
## Au-delà de ce déplacement (pixels), un clic devient un glissement.
const CLICK_SLOP := 6.0
## Délai avant d'afficher les infos d'un clic simple (laisse place au double-clic).
const INFO_DELAY := 0.28
const STICK_DEADZONE := 0.2

## Émis quand le pouvoir, le rayon, la couche ou l'espèce ciblée change.
signal state_changed
## Émis quand la souris survole une nouvelle cellule.
signal region_hovered(region: Vector2i)
## Molette au zoom maximal : descendre dans la vue rapprochée de `cell`.
signal descend_requested(cell: Vector2i)

## Intervalle minimal entre deux envois des grilles au GPU (secondes).
@export var pack_interval := 0.25
## Échantillons de vie (region_niches) lus par image.
@export var life_budget := 96
## Durée d'un jour (rotation complète du terminateur), en secondes réelles.
@export var day_length := 120.0

var power := ""
var radius := 8
var layer := 0
var target_species := -1
var grid := Vector2i(WorldSim.WIDTH, WorldSim.HEIGHT)

var orbit := OrbitState.new()
var textures := GlobeTextures.new()
var pins := GlobePins.new()

var _mat := ShaderMaterial.new()
var _atmo_mat := ShaderMaterial.new()
var _sky_mat := ShaderMaterial.new()
var _ui: GlobeUI
var _dirty := true
var _pack_timer := 0.0
var _anim_time := 0.0
var _impacts := PackedFloat32Array()
var _impact_next := 0
var _last_impact := {cell = Vector2i(-1, -1), time = -10.0}
var _flash := 0.0
var _shake := 0.0
var _rng := RandomNumberGenerator.new()
var _hover := Vector2i(-1, -1)
var _mouse_in := true
var _press_button := MOUSE_BUTTON_NONE
var _press_pos := Vector2.ZERO
var _dragged := false
var _info_at := -1.0
var _info_pos := Vector2.ZERO
var _world_seed := 0

@onready var camera: Camera3D = $Camera
@onready var planet: MeshInstance3D = $Planet
@onready var atmosphere: MeshInstance3D = $Atmosphere
@onready var particles: GPUParticles3D = $ImpactParticles


func _ready() -> void:
	_mat.shader = GLOBE_SHADER
	planet.material_override = _mat
	_atmo_mat.shader = ATMOSPHERE_SHADER
	atmosphere.material_override = _atmo_mat
	_sky_mat.shader = SKY_SHADER
	camera.environment = _make_environment()
	_mat.set_shader_parameter("noise_tex", _make_noise())
	_impacts.resize(MAX_IMPACTS * 5)
	for i in MAX_IMPACTS:
		_impacts[i * 5 + 4] = -1.0
	_setup_particles()

	_ui = GlobeUI.new()
	add_child(_ui)
	_ui.build(LAYERS)
	_ui.select_layer(layer)
	_ui.layer_pressed.connect(set_layer)
	_ui.pin_requested.connect(pin_center)
	_ui.pin_go.connect(go_to_pin)
	_ui.pin_remove.connect(_on_pin_remove)
	visibility_changed.connect(func() -> void: _ui.visible = is_visible_in_tree())

	GameState.world_updated.connect(func() -> void: _dirty = true)
	GameState.divine_action_applied.connect(_on_divine_action_applied)
	GameState.event_occurred.connect(_on_event)
	if GameState.sim != null:
		grid = GlobeTextures.Packer.grid_size(GameState.sim)
		_world_seed = int(GameState.sim.seed)
	pins.load_for(_world_seed)
	_ui.set_pins(pins.pins)
	if GameState.parcel != null:
		var ll := GlobeMath.cell_lat_lon(GameState.parcel.cell, grid)
		orbit.jump_to(ll.x, ll.y)
	_pack_now()
	_apply_camera(0.0)


# --- État piloté par le HUD (même API que src/map/world_map.gd) ---

func set_power(power_id: String) -> void:
	if power_id == power:
		return
	power = power_id
	var p := Powers.get_power(power_id)
	if not p.is_empty():
		radius = p.radius
	state_changed.emit()


func set_radius(r: int) -> void:
	r = clampi(r, Powers.MIN_RADIUS, Powers.MAX_RADIUS)
	if r != radius:
		radius = r
		state_changed.emit()


func set_layer(i: int) -> void:
	i = clampi(i, 0, LAYERS.size() - 1)
	if _ui != null:
		_ui.select_layer(i)
	if i != layer:
		layer = i
		if i == 4 and not textures.has_plates() and _ui != null:
			_ui.toast("La tectonique des plaques n'est pas encore simulée.")
		state_changed.emit()


func set_target_species(id: int) -> void:
	if id != target_species:
		target_species = id
		state_changed.emit()


## Centre doucement la vue sur une région (ex. clic sur une entrée de la chronique).
func focus_region(region: Vector2i) -> void:
	var ll := GlobeMath.cell_lat_lon(region, grid)
	orbit.focus(ll.x, ll.y)
	if orbit.target_altitude > 1.0:
		orbit.set_altitude(0.8)


## Cellule sous un point écran, ou (-1, -1) hors de la planète.
func screen_to_region(screen_pos: Vector2) -> Vector2i:
	if camera == null or not camera.is_inside_tree():
		return Vector2i(-1, -1)
	var inv := planet.global_transform.affine_inverse()
	var origin := inv * camera.project_ray_origin(screen_pos)
	var dir := inv.basis * camera.project_ray_normal(screen_pos)
	return GlobeMath.ray_to_cell(origin, dir, grid)


func dominant_species_at(region: Vector2i) -> int:
	var sim = GameState.sim
	if sim == null:
		return -1
	var i := region.y * grid.x + region.x
	return sim.dominant_species[i] if i >= 0 and i < sim.dominant_species.size() else -1


## Outil de la palette (src/ui/tools/tool_state.gd) : semence ou pouvoir, avec recharge.
func _tools() -> Node:
	return ToolStateScript.shared(get_tree())


func _has_tool() -> bool:
	return power != "" or _tools().has_tool()


## Applique l'outil sélectionné (semence ou pouvoir) sur une région, via GameState. La palette
## démarre la recharge ; sans outil de palette, on retombe sur le pouvoir de la vue.
func apply_power_at(region: Vector2i) -> void:
	if GameState.sim == null or region.x < 0:
		return
	var tools := _tools()
	if tools.has_tool():
		var tool: Dictionary = tools.selected_tool()
		if str(tool.get("kind", "")) == "power":
			var params: Dictionary = tool.get("params", {})
			params.radius = radius
			params.species_id = target_species
			tool.params = params
		var a: Dictionary = tools.use(tool, region)
		if a.is_empty():
			return
		var p := Powers.get_power(str(a.get("type", "")))
		if p.get("needs_species", false) and int(a.get("species_id", -1)) < 0:
			a.species_id = dominant_species_at(region)
		GameState.apply_divine_action(a)
		return
	if power == "":
		return
	var p := Powers.get_power(power)
	var species_id := target_species
	if p.get("needs_species", false) and species_id < 0:
		species_id = dominant_species_at(region)
	elif not p.get("needs_species", false) and power != "spawn_species":
		species_id = -1
	GameState.apply_divine_action(Powers.make_action(power, region, species_id, radius))


## Cellule au centre de la vue.
func center_cell() -> Vector2i:
	return GlobeMath.dir_to_cell(GlobeMath.lat_lon_to_dir(orbit.lat, orbit.lon), grid)


## Remonte depuis la vue rapprochée : la caméra repart du lieu, au ras du sol.
func arrive_from_ground(cell: Vector2i) -> void:
	var ll := GlobeMath.cell_lat_lon(cell, grid)
	orbit.jump_to(ll.x, ll.y)
	# On repart du sol puis la caméra s'élève d'elle-même jusqu'à voir la courbure de la planète :
	# arriver à 0,18 remplissait l'écran de mer (« carte toute brune » à l'Archéen).
	orbit.set_altitude(GlobeMath.MIN_ALTITUDE, true)
	orbit.set_altitude(GlobeMath.ARRIVAL_ALTITUDE)
	_apply_camera(0.0)


func pin_center() -> void:
	var cell := center_cell()
	pins.add(cell, _place_name(cell))
	pins.save()
	_ui.set_pins(pins.pins)
	_ui.toast("Lieu épinglé : %s" % _place_name(cell))


func go_to_pin(index: int) -> void:
	if index < 0 or index >= pins.pins.size():
		return
	focus_region(pins.pins[index].cell)
	orbit.set_altitude(minf(orbit.target_altitude, 0.35))


func _on_pin_remove(index: int) -> void:
	pins.remove(index)
	pins.save()
	_ui.set_pins(pins.pins)


# --- Entrées ---

func _input(event: InputEvent) -> void:
	# Remis à vrai dans _unhandled_input si l'interface n'a pas consommé le mouvement.
	if event is InputEventMouseMotion:
		_mouse_in = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_in = true
		var mm := event as InputEventMouseMotion
		if _press_button != MOUSE_BUTTON_NONE:
			if not _dragged and mm.position.distance_to(_press_pos) > CLICK_SLOP:
				_dragged = true
				_ui.hide_info()
			if _dragged:
				orbit.drag(mm.relative, get_viewport().get_visible_rect().size.y, camera.fov)
		return
	if event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventJoypadButton and event.pressed:
		if (event as InputEventJoypadButton).button_index == JOY_BUTTON_A and _has_tool():
			apply_power_at(center_cell())
			get_viewport().set_input_as_handled()


func _on_mouse_button(mb: InputEventMouseButton) -> void:
	match mb.button_index:
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				if mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
					_info_at = -1.0
					var cell := screen_to_region(mb.position)
					if cell.x >= 0:
						focus_region(cell)
					get_viewport().set_input_as_handled()
					return
				_press_button = mb.button_index
				_press_pos = mb.position
				_dragged = false
				orbit.stop()
			elif mb.button_index == _press_button:
				_press_button = MOUSE_BUTTON_NONE
				if _dragged:
					orbit.release()
				elif mb.button_index == MOUSE_BUTTON_LEFT:
					_click(mb.position)
			get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not mb.pressed:
				return
			var up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
			if mb.shift_pressed:
				set_radius(radius + (1 if up else -1))
			elif up and GlobeMath.should_descend(orbit.target_altitude, orbit.altitude):
				descend_requested.emit(center_cell())
			else:
				_zoom_toward(mb.position, -1.0 if up else 1.0)
			get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var key := k.physical_keycode
	if key >= KEY_F1 and key < KEY_F1 + LAYERS.size():
		set_layer(key - KEY_F1)
	elif key == KEY_P:
		pin_center()
	else:
		return
	get_viewport().set_input_as_handled()


func _click(pos: Vector2) -> void:
	var cell := screen_to_region(pos)
	if cell.x < 0:
		_ui.hide_info()
		return
	if _has_tool():
		apply_power_at(cell)
	else:
		_info_at = _anim_time + INFO_DELAY
		_info_pos = pos


## Un cran de molette : zoom, avec le centre attiré vers le point visé quand on s'approche.
func _zoom_toward(pos: Vector2, notches: float) -> void:
	orbit.wheel(notches)
	if notches < 0.0:
		var cell := screen_to_region(pos)
		if cell.x >= 0:
			var ll := GlobeMath.cell_lat_lon(cell, grid)
			var k := 0.18
			orbit.jump_to(lerpf(orbit.lat, ll.x, k), orbit.lon + GlobeMath.wrap_angle(ll.y - orbit.lon) * k)


# --- Boucle ---

func _process(delta: float) -> void:
	_anim_time += delta
	if _anim_time > ANIM_TIME_WRAP:
		_anim_time -= ANIM_TIME_WRAP
		_info_at = -1.0
		for i in MAX_IMPACTS:
			_impacts[i * 5 + 3] -= ANIM_TIME_WRAP

	_read_continuous_input(delta)
	orbit.update(delta)
	_apply_camera(delta)

	_pack_timer += delta
	if _dirty and _pack_timer >= pack_interval:
		_pack_now()
	if textures.update_life(GameState.sim, life_budget):
		_mat.set_shader_parameter("aux_tex", textures.aux_texture)
		_mat.set_shader_parameter("aux_smooth", textures.aux_texture)
	textures.advance_fade(delta)
	_set_pole_uniforms()
	_flash = maxf(_flash - delta * 2.5, 0.0)

	var mouse := get_viewport().get_mouse_position()
	var region := screen_to_region(mouse) if _mouse_in else Vector2i(-1, -1)
	if region != _hover and region.x >= 0:
		region_hovered.emit(region)
	_hover = region
	if _info_at >= 0.0 and _anim_time >= _info_at:
		_info_at = -1.0
		var cell := screen_to_region(_info_pos)
		if cell.x >= 0:
			_ui.show_info(region_info(cell), _info_pos)

	_update_uniforms(region)


func _read_continuous_input(delta: float) -> void:
	var spin := Input.get_vector("ui_left", "ui_right", "ui_down", "ui_up")
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), -Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if stick.length() > STICK_DEADZONE:
		spin += stick
	if spin != Vector2.ZERO:
		var rate := 0.35 + orbit.altitude * 0.6
		orbit.spin(Vector2(spin.y, spin.x) * rate, delta)
	var zoom := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(zoom) > STICK_DEADZONE:
		orbit.set_altitude(orbit.target_altitude * pow(2.0, zoom * delta * 1.5))


func _apply_camera(delta: float) -> void:
	var t := orbit.camera_transform()
	if _shake > 0.001:
		t.origin += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) \
				* _shake * orbit.altitude * 0.02
		_shake = lerpf(_shake, 0.0, 1.0 - exp(-5.0 * delta))
	camera.transform = planet.transform * t
	camera.near = clampf(orbit.altitude * 0.05, 0.0005, 0.05)
	camera.far = 40.0


func _update_uniforms(hover: Vector2i) -> void:
	var sim = GameState.sim
	var state := PlanetState.read(sim)
	var sun_lon := fposmod(-_anim_time / day_length, 1.0)
	var season := sin(_anim_time / (day_length * 8.0) * TAU)
	var sun := GlobeMath.sun_direction(sun_lon, season)
	var m := _mat
	m.set_shader_parameter("anim_time", _anim_time)
	m.set_shader_parameter("sun_dir", sun)
	m.set_shader_parameter("detail", GlobeMath.detail_level(orbit.altitude))
	m.set_shader_parameter("layer", layer)
	m.set_shader_parameter("geo_fade", textures.geography_fade)
	for key in ["oxygen", "ozone", "greenhouse", "land_flora", "snowball", "sea_level"]:
		m.set_shader_parameter(key, state[key])
	var atmo := PlanetState.atmosphere_color(state)
	m.set_shader_parameter("atmo_color", Vector3(atmo.r, atmo.g, atmo.b))
	m.set_shader_parameter("selected_species", target_species)
	var show_cursor := _has_tool() and _mouse_in and hover.x >= 0
	m.set_shader_parameter("cursor_visible", 1.0 if show_cursor else 0.0)
	if show_cursor:
		m.set_shader_parameter("cursor_dir", GlobeMath.cell_to_dir(hover, grid))
		m.set_shader_parameter("cursor_angle", radius * PI / grid.y)
		m.set_shader_parameter("cursor_color", Powers.get_power(power).get("color", Color.WHITE))
	if GameState.parcel != null:
		m.set_shader_parameter("parcel_dir", GlobeMath.cell_to_dir(GameState.parcel.cell, grid))
	m.set_shader_parameter("impact_data", _impacts)
	m.set_shader_parameter("flash", _flash)

	_atmo_mat.set_shader_parameter("sun_dir", sun)
	for key in ["oxygen", "ozone", "greenhouse"]:
		_atmo_mat.set_shader_parameter(key, state[key])
	_atmo_mat.set_shader_parameter("planet_radius", 1.0)
	_sky_mat.set_shader_parameter("sun_dir", sun)
	_sky_mat.set_shader_parameter("time", _anim_time)
	# Au sol, en plein jour, le ciel bleu cache les étoiles.
	var cam_dir := GlobeMath.lat_lon_to_dir(orbit.lat, orbit.lon)
	var low := 1.0 - smoothstep(0.04, 0.3, orbit.altitude)
	_sky_mat.set_shader_parameter("daylight_mask", low * smoothstep(-0.1, 0.3, cam_dir.dot(sun)) * 0.95)


func _set_pole_uniforms() -> void:
	_mat.set_shader_parameter("pole_data_n", textures.pole_data[0])
	_mat.set_shader_parameter("pole_data_s", textures.pole_data[1])
	_mat.set_shader_parameter("pole_aux_n", textures.pole_aux[0])
	_mat.set_shader_parameter("pole_aux_s", textures.pole_aux[1])
	_mat.set_shader_parameter("pole_prev_n", textures.pole_prev[0])
	_mat.set_shader_parameter("pole_prev_s", textures.pole_prev[1])


func _pack_now() -> void:
	_pack_timer = 0.0
	if GameState.sim == null or not textures.pack(GameState.sim):
		return
	_dirty = false
	grid = Vector2i(textures.width, textures.height)
	_mat.set_shader_parameter("data_tex", textures.packer.data_texture)
	_mat.set_shader_parameter("species_tex", textures.packer.species_texture)
	_mat.set_shader_parameter("aux_tex", textures.aux_texture)
	_mat.set_shader_parameter("aux_smooth", textures.aux_texture)
	_mat.set_shader_parameter("prev_elev_tex", textures.prev_elevation_texture)
	_mat.set_shader_parameter("grid_size", Vector2(grid))
	var dirs := PackedVector3Array()
	for c in pins.cells():
		dirs.append(GlobeMath.cell_to_dir(c, grid))
	_mat.set_shader_parameter("pin_count", dirs.size())
	dirs.resize(GlobePins.MAX_PINS)
	_mat.set_shader_parameter("pins", dirs)


# --- Informations d'une région ---

func region_info(cell: Vector2i) -> String:
	var sim = GameState.sim
	if sim == null:
		return ""
	var i := cell.y * grid.x + cell.x
	if i < 0 or i >= sim.elevation.size():
		return ""
	var lines: Array[String] = []
	lines.append(_place_name(cell))
	var ll := GlobeMath.cell_lat_lon(cell, grid)
	lines.append("%d° %s, %d° %s" % [absi(int(rad_to_deg(ll.x))), "N" if ll.x >= 0.0 else "S",
		absi(int(rad_to_deg(GlobeMath.wrap_angle(ll.y)))), "E" if GlobeMath.wrap_angle(ll.y) >= 0.0 else "O"])
	lines.append("Température : %d °C" % roundi(ParcelSim.to_celsius(sim.temperature[i])))
	var land_sp: int = sim.dominant_species[i]
	if land_sp >= 0:
		lines.append("Domine : %s (densité %d %%)" % [_species_name(land_sp), int(sim.population[i] * 100.0)])
	if sim.has_method("region_niches"):
		var shown := 0
		for n in sim.region_niches(cell):
			if shown >= 4:
				break
			var hab: String = {"marine": "mer", "amphibious": "rivage", "land": "terre"}.get(str(n.habitat), "")
			lines.append("  • %s — %s, %d %%" % [_species_name(int(n.species_id)), hab, int(float(n.density) * 100.0)])
			shown += 1
		if shown == 0:
			lines.append("Aucune vie ici.")
	if sim.tech[i] > 0.01:
		lines.append("Technologie : %d %%" % int(sim.tech[i] * 100.0))
	if "plate_id" in sim and sim.plate_id.size() > i:
		lines.append("Plaque n° %d" % int(sim.plate_id[i]))
	return "\n".join(lines)


func _place_name(cell: Vector2i) -> String:
	var sim = GameState.sim
	var i := cell.y * grid.x + cell.x
	var kind := "Lieu"
	if sim != null and i >= 0 and i < sim.biome.size():
		kind = str(WorldSim.BIOME_NAMES[clampi(sim.biome[i], 0, WorldSim.BIOME_NAMES.size() - 1)])
	return "%s (%d, %d)" % [kind, cell.x, cell.y]


func _species_name(id: int) -> String:
	var sim = GameState.sim
	var info = sim.species.get(id) if sim != null else null
	return str(info.get("name", "#%d" % id)) if info is Dictionary else "#%d" % id


# --- Impacts ---

func _on_divine_action_applied(action: Dictionary, _consequences: Array) -> void:
	var region: Vector2i = action.get("region", Vector2i(-1, -1))
	if region.x < 0:
		return
	_spawn_at(region, Powers.index_of(str(action.get("type", ""))))


func _on_event(event: Dictionary) -> void:
	# Impacts naturels (astéroïdes de la simulation) : même effet qu'un météore divin.
	if str(event.get("type", "")) != "impact":
		return
	var region = event.get("region")
	if region is Vector2i and region.x >= 0:
		_spawn_at(region, 0)


func _spawn_at(region: Vector2i, kind: int) -> void:
	if region == _last_impact.cell and _anim_time - float(_last_impact.time) < 0.5:
		return
	_last_impact = {cell = region, time = _anim_time}
	spawn_impact(GlobeMath.cell_to_dir(region, grid), kind)


## Effet visuel d'un pouvoir : onde de choc et brûlure (shader), gerbe de particules, éclair.
func spawn_impact(dir: Vector3, kind: int) -> void:
	var k := maxi(kind, 0)
	var i := _impact_next
	_impact_next = (_impact_next + 1) % MAX_IMPACTS
	_impacts[i * 5] = dir.x
	_impacts[i * 5 + 1] = dir.y
	_impacts[i * 5 + 2] = dir.z
	_impacts[i * 5 + 3] = _anim_time
	_impacts[i * 5 + 4] = float(k)
	var color: Color = Powers.LIST[k].color if k < Powers.LIST.size() else Color.WHITE
	particles.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT),
			dir * 1.003)
	var pm := particles.process_material as ParticleProcessMaterial
	pm.color = color
	var s := clampf(orbit.altitude, 0.05, 2.0)
	pm.initial_velocity_min = 0.02 * s
	pm.initial_velocity_max = (0.12 if k == 0 else 0.05) * s
	pm.scale_min = 0.004 * s
	pm.scale_max = 0.012 * s
	particles.amount_ratio = 1.0 if k == 0 else 0.5
	particles.restart()
	particles.emitting = true
	if k == 0:
		_flash = 0.35
		_shake = 1.0


func _setup_particles() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 70.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = 0.05
	pm.damping_max = 0.1
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.6, 1.4, 1.1, 1.0))
	ramp.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	pm.color_ramp = tex
	particles.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.vertex_color_use_as_albedo = true
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = qm
	particles.draw_pass_1 = quad
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.emitting = false
	particles.local_coords = false


## Bruit 3D sans raccord pour le shader (nuages, relief fin, humidité) : 128³ texels, un motif tous les
## 8 texels, soit 16 unités de bruit par période. Généré une fois, en tâche de fond par Godot.
func _make_noise() -> NoiseTexture3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	noise.frequency = 1.0 / 8.0
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.seed = 1729
	var tex := NoiseTexture3D.new()
	tex.width = 128
	tex.height = 128
	tex.depth = 128
	tex.seamless = true
	tex.normalize = true
	tex.noise = noise
	return tex


func _make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	return env
