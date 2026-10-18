extends Node2D
## Le temps qui passe sur la parcelle : heure du jour, saisons, météo (pluie, orage et éclairs,
## brouillard, neige, cendres), et voiles divins temporaires (givre, miasme, rayons dorés).
## Horloge cosmétique propre à la vue : elle tourne même si la simulation est en pause.
## Le voile est dessiné par shaders/parcel_atmosphere.gdshader ; les éclairs par _draw (additif).

signal lightning_struck(at: Vector2)

const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")
const ATMOSPHERE_SHADER := preload("res://shaders/parcel_atmosphere.gdshader")

## Vitesse de fondu d'une météo à l'autre (par seconde).
const WEATHER_FADE := 1.0 / 6.0
## Durée des cendres forcées après un impact de météore.
const ASH_AFTER_METEOR := 120.0

var day_t := 0.32  ## 0 minuit … 0,5 midi
var year_t := 0.35 ## 0 plein hiver … 0,5 plein été
var weather := "clear"

## Valeurs dérivées, lues par la vue chaque image.
var daylight := 1.0
var sky := Color.WHITE
var snow_cover := 0.0
var autumn := 0.0

var _base_temp := 15.0
var _water := 0.3
var _land_use := "wild"
var _cell := Vector2i.ZERO
var _weather_timer := 20.0
var _weather_index := 0
var _forced_ash := 0.0
var _levels := {rain = 0.0, storm = 0.0, fog = 0.0, snow = 0.0, ash = 0.0}
## Voiles divins : valeur courante et vitesse de décroissance.
var _pulses := {frost = 0.0, miasma = 0.0, golden = 0.0}
var _pulse_decay := {frost = 0.04, miasma = 0.07, golden = 0.18}
var _lightning := 0.0
var _next_bolt := 4.0
var _bolt := PackedVector2Array()
var _bolt_life := 0.0
var _rng := RandomNumberGenerator.new()
var _overlay: Node2D
var _mat := ShaderMaterial.new()


func _ready() -> void:
	_mat.shader = ATMOSPHERE_SHADER
	_mat.set_shader_parameter("parcel_size", ParcelLogic.PARCEL_SIZE)
	_overlay = Node2D.new()
	_overlay.material = _mat
	_overlay.draw.connect(func() -> void: _overlay.draw_rect(Rect2(Vector2.ZERO, ParcelLogic.PARCEL_SIZE), Color.WHITE))
	add_child(_overlay)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add
	_overlay.use_parent_material = false


func apply_parcel(p: ParcelSim) -> void:
	_base_temp = p.temperature_c
	_water = p.water
	_land_use = p.land_use
	if p.cell != _cell:
		_cell = p.cell
		_weather_index = 0
		_rng.seed = hash([_cell, _weather_index])


## Météore : cendres pendant ASH_AFTER_METEOR secondes.
func meteor_impact() -> void:
	_forced_ash = ASH_AFTER_METEOR
	_set_weather("ash")


## Voile divin temporaire : "frost", "miasma" ou "golden", centré sur `at`.
func pulse(kind: String, at: Vector2, strength := 1.0) -> void:
	if not _pulses.has(kind):
		return
	_pulses[kind] = maxf(_pulses[kind], strength)
	if kind == "miasma":
		_mat.set_shader_parameter("miasma_center", at)
	elif kind == "golden":
		_mat.set_shader_parameter("golden_center", at)


func pulse_level(kind: String) -> float:
	return float(_pulses.get(kind, 0.0))


func effective_temperature() -> float:
	return _base_temp + ParcelLogic.season_offset_c(year_t, _base_temp)


func _process(delta: float) -> void:
	day_t = fposmod(day_t + delta / ParcelLogic.DAY_LENGTH, 1.0)
	year_t = fposmod(year_t + delta / ParcelLogic.YEAR_LENGTH, 1.0)
	var eff := effective_temperature()
	snow_cover = maxf(ParcelLogic.snow_cover(eff, _water), _levels.snow * 0.6)
	autumn = ParcelLogic.autumn(year_t, _base_temp)

	_forced_ash = maxf(0.0, _forced_ash - delta)
	_weather_timer -= delta
	if _weather_timer <= 0.0 and _forced_ash <= 0.0:
		_weather_index += 1
		_rng.seed = hash([_cell, _weather_index])
		_set_weather(ParcelLogic.pick_weather(_rng.randf(), _water, eff, _land_use))
	for k in _levels:
		var target := 1.0 if k == weather else 0.0
		_levels[k] = move_toward(_levels[k], target, delta * WEATHER_FADE)
	for k in _pulses:
		_pulses[k] = maxf(0.0, _pulses[k] - delta * _pulse_decay[k])

	daylight = ParcelLogic.daylight(day_t)
	var overcast := clampf(_levels.rain * 0.7 + _levels.storm + _levels.ash + _levels.fog * 0.4 + _levels.snow * 0.4, 0.0, 1.0)
	sky = ParcelLogic.sky_color(day_t, overcast)
	_update_lightning(delta)
	_push()


func _set_weather(w: String) -> void:
	weather = w
	_weather_timer = _rng.randf_range(35.0, 70.0)


func _update_lightning(delta: float) -> void:
	_lightning = maxf(0.0, _lightning - delta * 4.0)
	_bolt_life = maxf(0.0, _bolt_life - delta)
	if _levels.storm < 0.5:
		return
	_next_bolt -= delta
	if _next_bolt > 0.0:
		return
	_next_bolt = _rng.randf_range(3.0, 9.0)
	_lightning = 1.0
	# Éclair en zigzag, du bord haut vers un point du sol.
	var target := Vector2(_rng.randf_range(0.1, 0.9), _rng.randf_range(0.3, 0.9)) * ParcelLogic.PARCEL_SIZE
	var start := Vector2(target.x + _rng.randf_range(-300.0, 300.0), -40.0)
	_bolt = PackedVector2Array()
	var steps := 14
	for k in steps + 1:
		var t := float(k) / steps
		var jitter := Vector2(_rng.randf_range(-35.0, 35.0), 0.0) * (1.0 - absf(t - 0.5) * 1.2)
		_bolt.append(start.lerp(target, t) + (jitter if k > 0 and k < steps else Vector2.ZERO))
	_bolt_life = 0.35
	lightning_struck.emit(target)


func _push() -> void:
	_mat.set_shader_parameter("daylight", daylight)
	_mat.set_shader_parameter("wind", Vector2(0.25 + 0.25 * sin(day_t * TAU * 3.0), 0.0))
	_mat.set_shader_parameter("rain", maxf(_levels.rain, _levels.storm))
	_mat.set_shader_parameter("storm", _levels.storm)
	_mat.set_shader_parameter("fog", _levels.fog)
	_mat.set_shader_parameter("snow", _levels.snow)
	_mat.set_shader_parameter("ash", _levels.ash)
	_mat.set_shader_parameter("leaves", autumn * (1.0 - _levels.snow))
	_mat.set_shader_parameter("lightning", _lightning)
	for k in _pulses:
		_mat.set_shader_parameter(k, _pulses[k])
	queue_redraw()


func _draw() -> void:
	if _bolt_life <= 0.0 or _bolt.size() < 2:
		return
	var a := _bolt_life / 0.35
	draw_polyline(_bolt, Color(0.5, 0.6, 1.0, 0.5 * a), 9.0)
	draw_polyline(_bolt, Color(1, 1, 1, a), 3.0)
