extends Node2D
## Voile d'eau du prologue (shaders/parcel_water.gdshader) : parcelle sous la mer, puis terres qui
## émergent. Ne dessine rien quand la parcelle est hors de l'eau.

const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")
const WATER_SHADER := preload("res://shaders/parcel_water.gdshader")

var _mat := ShaderMaterial.new()
var _level := 0.0
var _coast := Vector2.ZERO


func _ready() -> void:
	_mat.shader = WATER_SHADER
	_mat.set_shader_parameter("parcel_size", ParcelLogic.PARCEL_SIZE)
	material = _mat
	visible = false


func set_landmarks(lm: Dictionary) -> void:
	_mat.set_shader_parameter("rock_pos", lm.rock_pos)
	_mat.set_shader_parameter("rock_radii", lm.rock_radii)


## Côte (ParcelLogic.coast_vector) et milieu de la cellule.
func set_coast(coast: Vector2, sea_cell: bool) -> void:
	_coast = coast
	_mat.set_shader_parameter("coast", coast)
	_mat.set_shader_parameter("sea_cell", 1.0 if sea_cell else 0.0)


func set_depth(depth_factor: float) -> void:
	_mat.set_shader_parameter("depth_factor", depth_factor)


## Voile coloré d'algues ou de microbes en suspension (a = intensité).
func set_bloom(bloom: Color) -> void:
	_mat.set_shader_parameter("bloom", Vector4(bloom.r, bloom.g, bloom.b, bloom.a))


func set_cell(cell: Vector2i) -> void:
	_mat.set_shader_parameter("seed_offset", Vector2(fposmod(cell.x * 0.137, 1.0), fposmod(cell.y * 0.291, 1.0)))


## level : 1 sous la mer, 0 émergé ; tint : couleur de l'eau + turbidité (ParcelLogic.sea_tint) ;
## light : lumière ambiante (jour/nuit).
func update_water(level: float, tint: Color, light: Color) -> void:
	_level = level
	visible = level > 0.01 or _coast != Vector2.ZERO
	if not visible:
		return
	_mat.set_shader_parameter("submerged", level)
	_mat.set_shader_parameter("tint", Vector4(tint.r, tint.g, tint.b, tint.a))
	_mat.set_shader_parameter("light", light)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, ParcelLogic.PARCEL_SIZE), Color.WHITE)
