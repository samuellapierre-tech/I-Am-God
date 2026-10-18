extends Node2D
## Sol de la parcelle : un rectangle plein écran dessiné par shaders/parcel_terrain.gdshader.
## Les changements d'usage du sol ou de biome se font en fondu (TRANSITION_TIME secondes) ;
## végétation, humidité, température et technologie glissent en douceur vers leur valeur.

const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")

const TRANSITION_TIME := 4.0
## Constante de temps (s) du lissage des valeurs continues.
const SMOOTHING := 1.5

var parcel_size := ParcelLogic.PARCEL_SIZE

var _state_a := Vector3.ZERO
var _state_b := Vector3.ZERO
var _blend := 1.0
var _targets := {vegetation = 0.5, water = 0.3, temperature_c = 20.0, tech = 0.0}
var _values := {vegetation = 0.5, water = 0.3, temperature_c = 20.0, tech = 0.0}
var _has_state := false
var _mat: ShaderMaterial


func _ready() -> void:
	_mat = material as ShaderMaterial
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/parcel_terrain.gdshader")
		material = _mat
	_mat.set_shader_parameter("parcel_size", parcel_size)
	_push()


## snap : nouvelle parcelle, pas de fondu depuis l'ancienne.
func apply_parcel(p: ParcelSim, snap := false) -> void:
	var target := ParcelLogic.ground_state(p.land_use, p.biome)
	snap = snap or not _has_state
	if snap:
		_state_a = target
		_state_b = target
		_blend = 1.0
		_has_state = true
	else:
		var tr := ParcelLogic.next_transition(_state_a, _state_b, _blend, target)
		_state_a = tr[0]
		_state_b = tr[1]
		_blend = tr[2]
	_targets = {vegetation = p.vegetation, water = p.water, temperature_c = p.temperature_c, tech = p.tech}
	if snap:
		_values = _targets.duplicate()
	var c := p.cell
	_mat.set_shader_parameter("seed_offset", Vector2(fposmod(c.x * 0.137, 1.0), fposmod(c.y * 0.291, 1.0)))
	_push()


## Saisons (Atmosphere) : neige au sol et feuillage d'automne.
func set_season(snow_cover: float, autumn: float) -> void:
	if _mat:
		_mat.set_shader_parameter("snow_cover", snow_cover)
		_mat.set_shader_parameter("autumn", autumn)


func _process(delta: float) -> void:
	_blend = minf(1.0, _blend + delta / TRANSITION_TIME)
	var k := 1.0 - exp(-delta / SMOOTHING)
	for key in _values:
		_values[key] = lerpf(_values[key], _targets[key], k)
	_push()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, parcel_size), Color.WHITE)


func _push() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("kind_a", int(_state_a.x))
	_mat.set_shader_parameter("kind_b", int(_state_b.x))
	_mat.set_shader_parameter("wear_a", _state_a.y)
	_mat.set_shader_parameter("wear_b", _state_b.y)
	_mat.set_shader_parameter("veg_a", _state_a.z)
	_mat.set_shader_parameter("veg_b", _state_b.z)
	_mat.set_shader_parameter("blend", _blend)
	for key in _values:
		_mat.set_shader_parameter(key, _values[key])
