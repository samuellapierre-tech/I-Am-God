extends Node2D
## Vie d'ambiance : petits oiseaux en vol, essaims d'insectes (lucioles la nuit), ombres de
## ptérosaures qui planent. Trois MultiMesh dont les instances sont animées uniquement par le
## shader (shaders/parcel_ambient.gdshader) ; le CPU ne règle que le nombre visible.
## Cosmétique pur : ces animaux ne sont pas des espèces de la simulation.

const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")
const AMBIENT_SHADER := preload("res://shaders/parcel_ambient.gdshader")

const FLOCKS := 3
const BIRDS_PER_FLOCK := 11
const SWARMS := 8
const INSECTS_PER_SWARM := 14
const GLIDERS := 3
const PLANKTON_GROUPS := 6
const PLANKTON_PER_GROUP := 14

var _birds: MultiMeshInstance2D
var _insects: MultiMeshInstance2D
var _gliders: MultiMeshInstance2D
var _plankton: MultiMeshInstance2D


func _ready() -> void:
	_birds = _make(0, FLOCKS, BIRDS_PER_FLOCK)
	_insects = _make(1, SWARMS, INSECTS_PER_SWARM)
	_gliders = _make(2, GLIDERS, 1)
	_plankton = _make(3, PLANKTON_GROUPS, PLANKTON_PER_GROUP)
	_plankton.z_index = 2
	_gliders.z_index = 3
	_birds.z_index = 4
	_insects.z_index = 2


func apply_parcel(p: ParcelSim, swarm_centers: PackedVector2Array, year := 0.0) -> void:
	var c := p.cell
	var seed_off := Vector2(fposmod(c.x * 0.137, 1.0), fposmod(c.y * 0.291, 1.0))
	var counts := ParcelLogic.ambient_counts(p.land_use, p.vegetation, p.water, p.temperature_c, _has_clade(p, "pterosaure"), year)
	_set_visible(_birds, counts.flocks * BIRDS_PER_FLOCK)
	_set_visible(_insects, counts.swarms * INSECTS_PER_SWARM)
	_set_visible(_gliders, counts.gliders)
	_set_visible(_plankton, counts.plankton * PLANKTON_PER_GROUP)
	for mmi in [_birds, _insects, _gliders, _plankton]:
		var mat := mmi.material as ShaderMaterial
		mat.set_shader_parameter("seed_offset", seed_off)
	(_insects.material as ShaderMaterial).set_shader_parameter("swarm_centers", swarm_centers)


func set_night(night: float) -> void:
	for mmi in [_birds, _insects, _gliders, _plankton]:
		(mmi.material as ShaderMaterial).set_shader_parameter("night", night)


func _has_clade(p: ParcelSim, clade: String) -> bool:
	for f in p.fauna:
		if ParcelLogic.slug(String(f.get("clade", ""))) == clade:
			return true
	return false


func _set_visible(mmi: MultiMeshInstance2D, n: int) -> void:
	mmi.multimesh.visible_instance_count = clampi(n, 0, mmi.multimesh.instance_count)


func _make(kind: int, groups: int, members: int) -> MultiMeshInstance2D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.mesh = ParcelLogic.unit_quad()
	mm.instance_count = groups * members
	# Rien n'est déplacé côté CPU : on déclare l'emprise pour éviter tout masquage.
	mm.custom_aabb = AABB(Vector3(-600, -600, -1), Vector3(ParcelLogic.PARCEL_SIZE.x + 1200, ParcelLogic.PARCEL_SIZE.y + 1200, 2))
	for g in groups:
		for m in members:
			var i := g * members + m
			mm.set_instance_transform_2d(i, Transform2D.IDENTITY)
			mm.set_instance_custom_data(i, Color(g, m, 0, 0))
	mm.visible_instance_count = 0
	var mat := ShaderMaterial.new()
	mat.shader = AMBIENT_SHADER
	mat.set_shader_parameter("kind", kind)
	mat.set_shader_parameter("parcel_size", ParcelLogic.PARCEL_SIZE)
	var mmi := MultiMeshInstance2D.new()
	mmi.multimesh = mm
	mmi.material = mat
	add_child(mmi)
	return mmi
