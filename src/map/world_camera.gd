extends Camera2D
## Caméra vue de haut : déplacement (glisser clic droit/milieu, ZQSD/WASD, flèches),
## zoom fluide à la molette centré sur le curseur, bouclage horizontal du monde.

## Émis quand la caméra saute d'une largeur de monde (bouclage) : les effets suivent.
signal wrapped(shift_x: float)

@export var pan_speed := 900.0 ## pixels écran par seconde
@export var max_zoom := 10.0
@export var zoom_step := 1.15
@export var zoom_smoothing := 12.0

var world_size := Vector2(2048, 1024)
var target_zoom := 1.0
var _dragging := false
var _shake := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	position_smoothing_enabled = false
	target_zoom = zoom.x


func set_world_size(size: Vector2) -> void:
	world_size = size
	position = size * 0.5
	target_zoom = clampf(maxf(target_zoom, min_zoom()), min_zoom(), max_zoom)
	zoom = Vector2.ONE * target_zoom


## Zoom minimal : la hauteur du monde remplit à peu près l'écran.
func min_zoom() -> float:
	var vp := get_viewport_rect().size
	return clampf(vp.y / (world_size.y * 1.1), 0.05, 1.0)


func focus_on(world_pos: Vector2) -> void:
	position = world_pos
	_clamp_and_wrap()


func shake(strength: float) -> void:
	_shake = maxf(_shake, strength)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
		elif mb.pressed and not mb.shift_pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				target_zoom = minf(target_zoom * zoom_step, max_zoom)
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				target_zoom = maxf(target_zoom / zoom_step, min_zoom())
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		position -= (event as InputEventMouseMotion).relative / zoom.x
		_clamp_and_wrap()


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	# Touches physiques : WASD en QWERTY = ZQSD en AZERTY.
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		position += dir.normalized() * pan_speed * delta / zoom.x

	# Zoom fluide, ancré sur le point du monde sous la souris.
	if absf(zoom.x - target_zoom) > 0.0005:
		var mouse_screen := get_viewport().get_mouse_position()
		var before := _screen_to_world(mouse_screen)
		var z := lerpf(zoom.x, target_zoom, 1.0 - exp(-zoom_smoothing * delta))
		zoom = Vector2(z, z)
		var after := _screen_to_world(mouse_screen)
		position += before - after

	# Tremblement (impact de météorite).
	if _shake > 0.01:
		offset = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake / zoom.x
		_shake = lerpf(_shake, 0.0, 1.0 - exp(-6.0 * delta))
	else:
		offset = Vector2.ZERO
	_clamp_and_wrap()


func _screen_to_world(screen: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	return position + (screen - vp * 0.5) / zoom.x


func _clamp_and_wrap() -> void:
	if position.x < 0.0 or position.x >= world_size.x:
		var shift := floorf(position.x / world_size.x) * world_size.x
		position.x -= shift
		wrapped.emit(-shift)
	var half_h := get_viewport_rect().size.y * 0.5 / zoom.x
	var margin := world_size.y * 0.05
	if half_h * 2.0 >= world_size.y + margin * 2.0:
		position.y = world_size.y * 0.5
	else:
		position.y = clampf(position.y, half_h - margin, world_size.y - half_h + margin)
