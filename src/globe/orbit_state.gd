extends RefCounted
## État de la caméra orbitale du globe (pur, sans rendu) : point visé (lat, lon), altitude,
## inertie de rotation, centrage animé. globe.gd en tire la transformation de la Camera3D.

const GlobeMath := preload("res://src/globe/globe_math.gd")

## Amortissement de l'inertie (1/s) et de la molette.
const INERTIA_DAMPING := 3.5
const ZOOM_SMOOTHING := 7.0
const FOCUS_SPEED := 4.0
## En deçà, la vitesse d'inertie est annulée (rad/s).
const MIN_SPIN := 0.0005

var lat := deg_to_rad(20.0)
var lon := 0.0
var altitude := 2.2
var target_altitude := 2.2
## Vitesse angulaire (lat, lon) en rad/s, entretenue par le glissement puis amortie.
var velocity := Vector2.ZERO
var dragging := false

var _focusing := false
var _focus := Vector2.ZERO
var _drag_accum := Vector2.ZERO
var _drag_time := 0.0


## Glissement de `rel` pixels : la surface suit le curseur (glisser à droite montre l'ouest).
func drag(rel: Vector2, viewport_height: float, fov_deg: float) -> void:
	dragging = true
	_focusing = false
	var rate := GlobeMath.drag_rate(altitude, viewport_height, fov_deg)
	var d := Vector2(rel.y * rate, -rel.x * rate / maxf(cos(lat), 0.2))
	_set_center(lat + d.x, lon + d.y)
	_drag_accum += d


## Fin du glissement : la vitesse moyenne récente devient l'inertie.
func release() -> void:
	dragging = false
	if _drag_time > 0.0:
		velocity = _drag_accum / maxf(_drag_time, 1.0 / 60.0)
	_drag_accum = Vector2.ZERO
	_drag_time = 0.0


func stop() -> void:
	velocity = Vector2.ZERO
	_drag_accum = Vector2.ZERO


func wheel(notches: float) -> void:
	target_altitude = GlobeMath.wheel_altitude(target_altitude, notches)


func set_altitude(a: float, immediate := false) -> void:
	target_altitude = clampf(a, GlobeMath.MIN_ALTITUDE, GlobeMath.MAX_ALTITUDE)
	if immediate:
		altitude = target_altitude


## Centre doucement la vue sur (lat, lon).
func focus(p_lat: float, p_lon: float) -> void:
	_focusing = true
	velocity = Vector2.ZERO
	_focus = Vector2(clampf(p_lat, -GlobeMath.MAX_VIEW_LAT, GlobeMath.MAX_VIEW_LAT), p_lon)


func jump_to(p_lat: float, p_lon: float) -> void:
	_focusing = false
	velocity = Vector2.ZERO
	_set_center(p_lat, p_lon)


func is_focusing() -> bool:
	return _focusing


## Rotation continue (manette, clavier) en rad/s.
func spin(rate: Vector2, delta: float) -> void:
	if rate == Vector2.ZERO:
		return
	_focusing = false
	velocity = Vector2.ZERO
	_set_center(lat + rate.x * delta, lon + rate.y * delta / maxf(cos(lat), 0.2))


func update(delta: float) -> void:
	if dragging:
		# Seule la dernière fraction de seconde compte pour la vitesse de lancer.
		_drag_time += delta
		if _drag_time > 0.12:
			_drag_accum *= 0.12 / _drag_time
			_drag_time = 0.12
	elif _focusing:
		var k := 1.0 - exp(-FOCUS_SPEED * delta)
		var dl := GlobeMath.wrap_angle(_focus.y - lon)
		_set_center(lerpf(lat, _focus.x, k), lon + dl * k)
		if absf(_focus.x - lat) < 0.0005 and absf(dl) < 0.0005:
			_focusing = false
	elif velocity.length() > MIN_SPIN:
		_set_center(lat + velocity.x * delta, lon + velocity.y * delta)
		velocity *= exp(-INERTIA_DAMPING * delta)
	else:
		velocity = Vector2.ZERO
	var kz := 1.0 - exp(-ZOOM_SMOOTHING * delta)
	altitude = lerpf(altitude, target_altitude, kz)
	if absf(altitude - target_altitude) < 0.0001:
		altitude = target_altitude


func tilt() -> float:
	return GlobeMath.tilt_for_altitude(altitude)


func camera_transform(radius := 1.0) -> Transform3D:
	return GlobeMath.orbit_transform(lat, lon, altitude, tilt(), radius)


func _set_center(p_lat: float, p_lon: float) -> void:
	lat = clampf(p_lat, -GlobeMath.MAX_VIEW_LAT, GlobeMath.MAX_VIEW_LAT)
	lon = GlobeMath.wrap_angle(p_lon)
