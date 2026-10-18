extends Node2D
## Carte du monde : planète rendue entièrement par shaders/planet.gdshader.
## Les grilles de la simulation sont empaquetées dans deux textures GPU (mises à jour à cadence limitée),
## le reste (biomes, océans, nuages, jour/nuit, lumières, effets) est calculé par pixel sur le GPU.
## Source de vérité de l'état de jeu côté joueur : pouvoir sélectionné, rayon, couche, espèce ciblée.

const MapMath := preload("res://src/map/map_math.gd")
const Packer := preload("res://src/map/world_texture_packer.gd")
const Powers := preload("res://src/map/divine_powers.gd")
const PLANET_SHADER := preload("res://shaders/planet.gdshader")

## Couches de carte (index envoyé au shader).
const LAYERS := ["Biomes", "Espèces", "Technologie", "Température"]
const MAX_IMPACTS := 8
const IMPACT_DURATION := 4.0
const ANIM_TIME_WRAP := 3600.0

## Émis quand le pouvoir, le rayon, la couche ou l'espèce ciblée change.
signal state_changed
## Émis quand la souris survole une nouvelle cellule.
signal region_hovered(region: Vector2i)

@export var cell_size := 8.0
## Intervalle minimal entre deux envois des grilles au GPU (secondes).
@export var pack_interval := 0.1
## Durée d'un jour (rotation complète du terminateur), en secondes réelles.
@export var day_length := 60.0
@export var era_transition := 2.5

var power := ""
var radius := 8
var layer := 0
var target_species := -1

var grid := Vector2i(256, 128)
var world_size := Vector2(2048, 1024)

var _packer := Packer.new()
var _material := ShaderMaterial.new()
var _dirty := true
var _pack_timer := 0.0
var _anim_time := 0.0
var _impacts := PackedFloat32Array()
var _impact_next := 0
var _flash := 0.0
var _era_from := 0
var _era_to := 0
var _era_t := 1.0
var _hover := Vector2i(-1, -1)
var _mouse_over_map := true

@onready var camera: Camera2D = $Camera
@onready var particles: GPUParticles2D = $ImpactParticles


func _ready() -> void:
	_material.shader = PLANET_SHADER
	material = _material
	_impacts.resize(MAX_IMPACTS * 4)
	for i in MAX_IMPACTS:
		_impacts[i * 4 + 3] = -1.0
	_setup_particles()

	GameState.world_updated.connect(_on_world_updated)
	GameState.era_changed.connect(_on_era_changed)
	GameState.divine_action_applied.connect(_on_divine_action_applied)
	camera.wrapped.connect(_on_camera_wrapped)

	if GameState.sim != null:
		grid = Packer.grid_size(GameState.sim)
		_era_to = MapMath.era_index(GameState.sim.current_era())
		_era_from = _era_to
	world_size = Vector2(grid) * cell_size
	camera.set_world_size(world_size)
	_pack_now()


# --- État piloté par le HUD ---

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
	if i != layer:
		layer = i
		state_changed.emit()


func set_target_species(id: int) -> void:
	if id != target_species:
		target_species = id
		state_changed.emit()


## Centre la caméra sur une région (ex. clic sur une entrée de la chronique).
func focus_region(region: Vector2i) -> void:
	camera.focus_on(MapMath.region_to_world(region, cell_size, grid.x, camera.position.x))


## Région de la grille sous une position écran.
func screen_to_region(screen_pos: Vector2) -> Vector2i:
	return MapMath.screen_to_region(screen_pos, get_canvas_transform(), cell_size, grid.x, grid.y)


func dominant_species_at(region: Vector2i) -> int:
	var sim = GameState.sim
	if sim == null:
		return -1
	var i := region.y * grid.x + region.x
	return sim.dominant_species[i] if i >= 0 and i < sim.dominant_species.size() else -1


## Applique le pouvoir sélectionné sur une région, via GameState (contrat d'action divine).
func apply_power_at(region: Vector2i) -> void:
	if power == "" or GameState.sim == null:
		return
	var p := Powers.get_power(power)
	var species_id := target_species
	if p.get("needs_species", false) and species_id < 0:
		species_id = dominant_species_at(region)
	elif not p.get("needs_species", false) and power != "spawn_species":
		species_id = -1
	GameState.apply_divine_action(Powers.make_action(power, region, species_id, radius))


# --- Entrées ---

func _input(event: InputEvent) -> void:
	# Remis à vrai dans _unhandled_input si l'interface n'a pas consommé le mouvement.
	if event is InputEventMouseMotion:
		_mouse_over_map = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_over_map = true
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and power != "":
			apply_power_at(screen_to_region(mb.position))
			get_viewport().set_input_as_handled()
		elif mb.shift_pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_radius(radius + 1)
			get_viewport().set_input_as_handled()
		elif mb.shift_pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_radius(radius - 1)
			get_viewport().set_input_as_handled()


# --- Boucle ---

func _process(delta: float) -> void:
	_anim_time += delta
	if _anim_time > ANIM_TIME_WRAP:
		_anim_time -= ANIM_TIME_WRAP
		for i in MAX_IMPACTS:
			_impacts[i * 4 + 2] -= ANIM_TIME_WRAP

	_pack_timer += delta
	if _dirty and _pack_timer >= pack_interval:
		_pack_now()

	if _era_t < 1.0:
		_era_t = minf(_era_t + delta / era_transition, 1.0)
	_flash = maxf(_flash - delta * 2.5, 0.0)

	var mouse_world := get_global_mouse_position()
	var region := MapMath.world_to_region(mouse_world, cell_size, grid.x, grid.y)
	if region != _hover and _mouse_over_map:
		_hover = region
		region_hovered.emit(region)
	var cursor_world := MapMath.region_to_world(region, cell_size, grid.x, mouse_world.x)

	var m := _material
	m.set_shader_parameter("anim_time", _anim_time)
	m.set_shader_parameter("sun_lon", fposmod(-_anim_time / day_length, 1.0))
	m.set_shader_parameter("season", sin(_anim_time / (day_length * 6.0) * TAU))
	m.set_shader_parameter("zoom", camera.zoom.x)
	m.set_shader_parameter("layer", layer)
	m.set_shader_parameter("era_from", _era_from)
	m.set_shader_parameter("era_to", _era_to)
	m.set_shader_parameter("era_t", _era_t)
	m.set_shader_parameter("selected_species", target_species)
	m.set_shader_parameter("cursor_pos", cursor_world)
	m.set_shader_parameter("cursor_radius", radius * cell_size)
	m.set_shader_parameter("cursor_visible", 1.0 if power != "" and _mouse_over_map else 0.0)
	var pc: Color = Powers.get_power(power).get("color", Color.WHITE)
	m.set_shader_parameter("cursor_color", pc)
	m.set_shader_parameter("impact_data", _impacts)
	m.set_shader_parameter("flash", _flash)
	queue_redraw()


func _draw() -> void:
	# Un seul rectangle couvrant la vue : le shader calcule tout à partir de la position monde,
	# ce qui donne le bouclage horizontal gratuitement.
	var vp := get_viewport_rect().size
	var half := vp * 0.5 / camera.zoom
	var center := camera.get_screen_center_position()
	var rect := Rect2(center - half, half * 2.0).grow(cell_size * 4.0 + 64.0 / camera.zoom.x)
	draw_rect(rect, Color.WHITE)


func _pack_now() -> void:
	_pack_timer = 0.0
	if GameState.sim == null or not _packer.pack(GameState.sim):
		return
	_dirty = false
	if grid != Vector2i(_packer.width, _packer.height):
		grid = Vector2i(_packer.width, _packer.height)
		world_size = Vector2(grid) * cell_size
		camera.set_world_size(world_size)
	_material.set_shader_parameter("data_tex", _packer.data_texture)
	_material.set_shader_parameter("species_tex", _packer.species_texture)
	_material.set_shader_parameter("grid_size", Vector2(grid))
	_material.set_shader_parameter("cell_size", cell_size)


# --- Signaux de GameState ---

func _on_world_updated() -> void:
	_dirty = true


func _on_era_changed(era: String) -> void:
	var idx := MapMath.era_index(era)
	if idx == _era_to:
		return
	_era_from = _era_to if _era_t >= 0.5 else _era_from
	_era_to = idx
	_era_t = 0.0


func _on_divine_action_applied(action: Dictionary, _consequences: Array) -> void:
	var kind := Powers.index_of(str(action.get("type", "")))
	var region: Vector2i = action.get("region", Vector2i.ZERO)
	var pos := MapMath.region_to_world(region, cell_size, grid.x, camera.position.x)
	spawn_impact(pos, kind)


## Effet visuel d'un pouvoir : onde de choc (shader), gerbe de particules, éclair et tremblement.
func spawn_impact(pos: Vector2, kind: int) -> void:
	var i := _impact_next
	_impact_next = (_impact_next + 1) % MAX_IMPACTS
	_impacts[i * 4] = pos.x
	_impacts[i * 4 + 1] = pos.y
	_impacts[i * 4 + 2] = _anim_time
	_impacts[i * 4 + 3] = float(maxi(kind, 0))
	var color: Color = Powers.LIST[maxi(kind, 0)].color
	particles.position = pos
	var pm := particles.process_material as ParticleProcessMaterial
	pm.color = color
	if kind == 0:
		pm.initial_velocity_min = 120.0
		pm.initial_velocity_max = 380.0
		particles.amount_ratio = 1.0
		_flash = 0.55
		camera.shake(18.0)
	else:
		pm.initial_velocity_min = 30.0
		pm.initial_velocity_max = 140.0
		particles.amount_ratio = 0.5
	particles.restart()
	particles.emitting = true


func _setup_particles() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 180.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = 80.0
	pm.damping_max = 160.0
	pm.scale_min = 1.5
	pm.scale_max = 4.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.6, 1.4, 1.1, 1.0))
	ramp.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	var tex := GradientTexture1D.new()
	tex.gradient = ramp
	pm.color_ramp = tex
	particles.process_material = pm
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.emitting = false


func _on_camera_wrapped(shift_x: float) -> void:
	particles.position.x += shift_x
	for i in MAX_IMPACTS:
		_impacts[i * 4] += shift_x
