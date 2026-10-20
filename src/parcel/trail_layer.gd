extends Node2D
## Marques au sol éphémères : empreintes, poussière, brûlures, éclaboussures. Une seule
## MultiMeshInstance2D en anneau de CAPACITY instances ; le CPU n'écrit qu'à la naissance d'une
## marque, le shader (shaders/parcel_trail.gdshader) gère âge et fondu.

const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")
const TRAIL_SHADER := preload("res://shaders/parcel_trail.gdshader")

const CAPACITY := 1536
## Les données d'instance 2D sont des demi-flottants : les dates sont stockées modulo WRAP
## (précision ~0,06 s). Toute durée de vie doit rester < WRAP.
const WRAP := 128.0
enum Kind { FOOTPRINT, DUST, SCORCH, SPLASH }

## Teinte des empreintes selon le sol (plus visibles et plus durables dans la neige).
var footprint_color := Color(0.25, 0.18, 0.1)
var footprint_life := 10.0
var dust_color := Color(0.78, 0.68, 0.5)

var _mm := MultiMesh.new()
var _mat := ShaderMaterial.new()
var _next := 0
var _now := 0.0


func _ready() -> void:
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = ParcelLogic.unit_quad()
	_mm.instance_count = CAPACITY
	for i in CAPACITY:
		# Type -1 : emplacement vide, invisible tant qu'il n'est pas réécrit.
		_mm.set_instance_custom_data(i, Color(0, -1, 0, 0))
		_mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO, 0.0, Vector2.ZERO))
	_mm.custom_aabb = AABB(Vector3(-200, -200, -1), Vector3(ParcelLogic.PARCEL_SIZE.x + 400, ParcelLogic.PARCEL_SIZE.y + 400, 2))
	var mmi := MultiMeshInstance2D.new()
	mmi.multimesh = _mm
	_mat.shader = TRAIL_SHADER
	mmi.material = _mat
	add_child(mmi)


## Adapte les marques au sol courant (type ParcelLogic.Ground).
func set_ground(kind: int) -> void:
	match kind:
		ParcelLogic.Ground.SNOW, ParcelLogic.Ground.TUNDRA:
			footprint_color = Color(0.45, 0.55, 0.7)
			footprint_life = 25.0
			dust_color = Color(0.95, 0.97, 1.0)
		ParcelLogic.Ground.SAND, ParcelLogic.Ground.DRY:
			footprint_color = Color(0.5, 0.38, 0.22)
			footprint_life = 14.0
			dust_color = Color(0.86, 0.74, 0.52)
		ParcelLogic.Ground.MUD, ParcelLogic.Ground.CRATER:
			footprint_color = Color(0.15, 0.1, 0.06)
			footprint_life = 18.0
			dust_color = Color(0.45, 0.4, 0.38)
		_:
			footprint_color = Color(0.22, 0.17, 0.1)
			footprint_life = 9.0
			dust_color = Color(0.72, 0.64, 0.48)


## Nouvelle cellule : on efface toutes les marques.
func clear() -> void:
	for i in CAPACITY:
		_mm.set_instance_custom_data(i, Color(0, -1, 0, 0))
	_next = 0


func emit(kind: int, pos: Vector2, angle: float, size: float, life := -1.0) -> void:
	var color := Color.WHITE
	match kind:
		Kind.FOOTPRINT:
			color = footprint_color
			if life < 0.0:
				life = footprint_life
		Kind.DUST:
			color = dust_color
			if life < 0.0:
				life = 1.4
		Kind.SCORCH:
			if life < 0.0:
				life = 90.0
		Kind.SPLASH:
			color = Color(0.85, 0.92, 1.0)
			if life < 0.0:
				life = 0.9
	var i := _next
	_next = (_next + 1) % CAPACITY
	_mm.set_instance_transform_2d(i, Transform2D(angle, Vector2(size, size), 0.0, pos))
	_mm.set_instance_color(i, color)
	_mm.set_instance_custom_data(i, Color(_now, kind, minf(life, WRAP - 1.0), 0))


func _process(delta: float) -> void:
	_now = fmod(_now + delta, WRAP)
	_mat.set_shader_parameter("now", _now)
