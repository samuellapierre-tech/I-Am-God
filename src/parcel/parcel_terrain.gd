extends Node2D
## Sol de la parcelle : un rectangle plein écran dessiné par shaders/parcel_terrain.gdshader.
## Les changements d'usage du sol ou de biome se font en fondu (TRANSITION_TIME secondes) ;
## végétation, humidité, température et technologie glissent en douceur vers leur valeur.

const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")

const ParcelParticles := preload("res://src/parcel/parcel_particles.gd")

const TRANSITION_TIME := 4.0
## Constante de temps (s) du lissage des valeurs continues ; la végétation repousse lentement.
const SMOOTHING := 1.5
const REGROW_SMOOTHING := 7.0
## Une chute brutale de végétation (par mise à jour) déclenche un incendie visible.
const FIRE_DROP := 0.1
const FIRE_TIME := 10.0
const SCORCH_TIME := 60.0

var parcel_size := ParcelLogic.PARCEL_SIZE

var _state_a := Vector3.ZERO
var _state_b := Vector3.ZERO
var _blend := 1.0
var _targets := {vegetation = 0.5, water = 0.3, temperature_c = 20.0, tech = 0.0}
var _values := {vegetation = 0.5, water = 0.3, temperature_c = 20.0, tech = 0.0}
var _has_state := false
var _land_use := "wild"
var _river := Vector4(1, 0, 0, 0)
var _river_target := Vector4(1, 0, 0, 0)
var _mat: ShaderMaterial
var _burn := 0.0
var _burn_density := 0.0
var _scorch := 0.0
var _smoke: GPUParticles2D
var _flood := 0.0
var _flood_hold := 0.0


func _ready() -> void:
	_mat = material as ShaderMaterial
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/parcel_terrain.gdshader")
		material = _mat
	_mat.set_shader_parameter("parcel_size", parcel_size)
	_smoke = ParcelParticles.make_smoke(parcel_size * 0.5, 140)
	_smoke.position = parcel_size * 0.5
	_smoke.emitting = false
	_smoke.z_index = 6
	add_child(_smoke)
	_push()


## Déluge divin : les eaux montent vite, tiennent quelques secondes, puis refluent
## (sauf si la simulation déclare la parcelle inondée).
func flood_pulse() -> void:
	_flood_hold = 8.0


## Incendie : la couverture `from_vegetation` part en fumée (front de braises, puis brûlis).
func ignite(from_vegetation: float) -> void:
	_burn_density = maxf(from_vegetation, _burn_density if _burn > 0.0 else 0.0)
	_burn = 1.0
	_scorch = 1.0
	_smoke.emitting = true


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
	if not snap and (p.vegetation < _targets.vegetation - FIRE_DROP or (p.land_use == "crater" and _land_use != "crater")):
		ignite(_values.vegetation)
	_land_use = p.land_use
	_targets = {vegetation = p.vegetation, water = p.water, temperature_c = p.temperature_c, tech = p.tech}
	if snap:
		_values = _targets.duplicate()
	var c := p.cell
	_mat.set_shader_parameter("seed_offset", Vector2(fposmod(c.x * 0.137, 1.0), fposmod(c.y * 0.291, 1.0)))
	_push()


## Repères permanents (ParcelLogic.landmarks) : rivière en S et rocher.
func set_landmarks(lm: Dictionary) -> void:
	_mat.set_shader_parameter("river_pts", lm.river)
	_mat.set_shader_parameter("river_width", lm.river_width)
	_mat.set_shader_parameter("rock_pos", lm.rock_pos)
	_mat.set_shader_parameter("rock_radii", lm.rock_radii)
	_mat.set_shader_parameter("rock_angle", lm.rock_angle)


## Saisons (Atmosphere) : neige au sol, feuillage d'automne, rivière gelée.
func set_season(snow_cover: float, autumn: float) -> void:
	if _mat:
		_mat.set_shader_parameter("snow_cover", snow_cover)
		_mat.set_shader_parameter("autumn", autumn)
	_river_target = ParcelLogic.river_state(_land_use, _targets.water, snow_cover)


func _process(delta: float) -> void:
	_blend = minf(1.0, _blend + delta / TRANSITION_TIME)
	var k := 1.0 - exp(-delta / SMOOTHING)
	for key in _values:
		var kk := k
		if key == "vegetation" and _targets[key] > _values[key]:
			kk = 1.0 - exp(-delta / REGROW_SMOOTHING)
		_values[key] = lerpf(_values[key], _targets[key], kk)
	_flood_hold = maxf(0.0, _flood_hold - delta)
	var flood_target := 1.0 if _flood_hold > 0.0 else (0.55 if _land_use == "flooded" else 0.0)
	_flood = lerpf(_flood, flood_target, 1.0 - exp(-delta / (2.0 if flood_target > _flood else 8.0)))
	_burn = maxf(0.0, _burn - delta / FIRE_TIME)
	_scorch = maxf(0.0, _scorch - delta / SCORCH_TIME)
	if _smoke.emitting and _burn < 0.25:
		_smoke.emitting = false
	_river = _river.lerp(_river_target, 1.0 - exp(-delta / TRANSITION_TIME))
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
	_mat.set_shader_parameter("river_state", _river)
	_mat.set_shader_parameter("burn", _burn)
	_mat.set_shader_parameter("burn_density", _burn_density)
	_mat.set_shader_parameter("scorch", _scorch)
	_mat.set_shader_parameter("flood", _flood)
	_mat.set_shader_parameter("grow", clampf((_targets.vegetation - _values.vegetation) * 6.0, 0.0, 1.0))
	for key in _values:
		_mat.set_shader_parameter(key, _values[key])
