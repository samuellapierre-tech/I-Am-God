extends Camera2D
## Petite caméra de la parcelle : zoom fluide vers le curseur (molette), panoramique (glisser clic
## droit/milieu, flèches), toujours dans les limites de la parcelle. Molette arrière au zoom
## minimal -> exit_requested (la vue parcelle passe alors au globe).

signal exit_requested

const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")

@export var max_zoom_factor := 3.0
@export var zoom_step := 1.15
@export var zoom_smoothing := 10.0
@export var pan_speed := 700.0 ## pixels écran par seconde

var parcel_size := ParcelLogic.PARCEL_SIZE
var target_zoom := 1.0
var _anchor := Vector2.ZERO ## point écran sous lequel le zoom se fait
var _dragging := false
var _shake := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	position_smoothing_enabled = false
	position = parcel_size * 0.5
	target_zoom = min_zoom()
	zoom = Vector2.ONE * target_zoom
	_anchor = get_viewport_rect().size * 0.5


func min_zoom() -> float:
	return ParcelLogic.cover_zoom(get_viewport_rect().size, parcel_size)


func shake(strength: float) -> void:
	_shake = maxf(_shake, strength)


func reset_view() -> void:
	target_zoom = min_zoom()
	zoom = Vector2.ONE * target_zoom
	position = parcel_size * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
		elif mb.pressed and not mb.shift_pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				target_zoom = minf(target_zoom * zoom_step, min_zoom() * max_zoom_factor)
				_anchor = mb.position
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				var r := ParcelLogic.wheel_out(target_zoom, min_zoom(), zoom_step)
				target_zoom = r.zoom
				_anchor = mb.position
				get_viewport().set_input_as_handled()
				# On ne quitte que si la caméra est réellement arrivée au zoom minimal.
				if r.exit and zoom.x <= min_zoom() * 1.01:
					exit_requested.emit()
	elif event is InputEventMouseMotion and _dragging:
		position -= (event as InputEventMouseMotion).relative / zoom.x


func _process(delta: float) -> void:
	var vp := get_viewport_rect().size
	var mz := min_zoom()
	target_zoom = clampf(target_zoom, mz, mz * max_zoom_factor)
	var old := zoom.x
	var z := lerpf(old, target_zoom, 1.0 - exp(-zoom_smoothing * delta))
	if absf(z - target_zoom) < 0.0005:
		z = target_zoom
	if z != old:
		# Le point du monde sous le curseur reste sous le curseur.
		var rel := _anchor - vp * 0.5
		position += rel / old - rel / z
		zoom = Vector2.ONE * z

	var pan := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if pan != Vector2.ZERO:
		position += pan * pan_speed * delta / zoom.x
	position = ParcelLogic.clamp_camera(position, zoom.x, vp, parcel_size)

	if _shake > 0.0:
		offset = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake / zoom.x
		_shake = maxf(0.0, _shake - delta * 40.0)
	elif offset != Vector2.ZERO:
		offset = Vector2.ZERO
