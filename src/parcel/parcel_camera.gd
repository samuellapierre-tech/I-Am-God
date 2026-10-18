extends Camera2D
## Petite caméra de la parcelle : zoom fluide vers le curseur (molette), panoramique (glisser clic
## droit/milieu, flèches), toujours dans les limites de la parcelle (le jeu ne montre qu'elle).
## focus() : zoom doux sur un événement, pause, puis retour au cadrage du joueur. Toute action
## du joueur sur la caméra annule le focus.

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

enum Focus { NONE, GOING, HOLD, RETURNING }
var _focus := Focus.NONE
var _focus_point := Vector2.ZERO
var _focus_zoom := 1.0
var _focus_hold := 0.0
var _saved_pos := Vector2.ZERO
var _saved_zoom := 1.0


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


## Zoom doux sur `point` (facteur relatif au zoom minimal), maintenu `hold` secondes, puis retour.
func focus(point: Vector2, zoom_factor := 1.4, hold := 2.5) -> void:
	# Le cadrage du joueur n'est mémorisé qu'au premier focus (pas pendant un retour).
	if _focus == Focus.NONE:
		_saved_pos = position
		_saved_zoom = target_zoom
	_focus = Focus.GOING
	_focus_point = point
	_focus_zoom = clampf(min_zoom() * zoom_factor, min_zoom(), min_zoom() * max_zoom_factor)
	_focus_hold = hold


func is_focusing() -> bool:
	return _focus != Focus.NONE


func _cancel_focus() -> void:
	_focus = Focus.NONE


func reset_view() -> void:
	_focus = Focus.NONE
	target_zoom = min_zoom()
	zoom = Vector2.ONE * target_zoom
	position = parcel_size * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
			_cancel_focus()
		elif mb.pressed and not mb.shift_pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_cancel_focus()
				target_zoom = minf(target_zoom * zoom_step, min_zoom() * max_zoom_factor)
				_anchor = mb.position
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_cancel_focus()
				target_zoom = ParcelLogic.wheel_out(target_zoom, min_zoom(), zoom_step)
				_anchor = mb.position
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		position -= (event as InputEventMouseMotion).relative / zoom.x


func _process(delta: float) -> void:
	var vp := get_viewport_rect().size
	var mz := min_zoom()
	_update_focus(delta, vp)
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
		_cancel_focus()
		position += pan * pan_speed * delta / zoom.x
	position = ParcelLogic.clamp_camera(position, zoom.x, vp, parcel_size)

	if _shake > 0.0:
		offset = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake / zoom.x
		_shake = maxf(0.0, _shake - delta * 40.0)
	elif offset != Vector2.ZERO:
		offset = Vector2.ZERO


func _update_focus(delta: float, vp: Vector2) -> void:
	if _focus == Focus.NONE:
		return
	_anchor = vp * 0.5 # zoom centré pendant le focus
	var k := 1.0 - exp(-delta * 2.5)
	match _focus:
		Focus.GOING, Focus.HOLD:
			target_zoom = _focus_zoom
			# Cible atteignable : un point au bord reste cadré dans la parcelle.
			var goal := ParcelLogic.clamp_camera(_focus_point, zoom.x, vp, parcel_size)
			position = position.lerp(goal, k)
			if _focus == Focus.GOING and position.distance_to(goal) < 20.0 and absf(zoom.x - _focus_zoom) < 0.02:
				_focus = Focus.HOLD
			if _focus == Focus.HOLD:
				_focus_hold -= delta
				if _focus_hold <= 0.0:
					_focus = Focus.RETURNING
		Focus.RETURNING:
			target_zoom = _saved_zoom
			position = position.lerp(_saved_pos, k)
			if position.distance_to(_saved_pos) < 4.0 and absf(zoom.x - _saved_zoom) < 0.01:
				_focus = Focus.NONE
