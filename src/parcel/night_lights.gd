extends Node2D
## Lumières de la nuit, en mélange additif dans un calque non assombri : feux de camp, lueur des
## huttes, fenêtres des villes, réverbères, néons de l'ère cyberpunk. Intensité selon la nuit
## (et l'orage). Dessin groupé avec une seule texture de halo radial.

const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")

const NEON := [Color(0.25, 0.95, 1.0), Color(1.0, 0.3, 0.85), Color(0.6, 0.4, 1.0)]

## 0 (jour) .. 1 (pleine nuit).
var intensity := 0.0
var land_use := "wild"
## [{pos: Vector2, kind: String, size: float, alpha: float}] (StructureLayer.light_sources()).
var sources: Array = []
## Feu de camp (usage "camp") : position stable choisie par la vue.
var campfire := Vector2(-1, -1)
var roads := PackedVector2Array() ## centres des croisements de routes

var _halo: GradientTexture2D
var _time := 0.0


func _ready() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.35))
	_halo = GradientTexture2D.new()
	_halo.gradient = g
	_halo.fill = GradientTexture2D.FILL_RADIAL
	_halo.fill_from = Vector2(0.5, 0.5)
	_halo.fill_to = Vector2(1.0, 0.5)
	_halo.width = 128
	_halo.height = 128


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _glow(at: Vector2, radius: float, color: Color) -> void:
	if color.a <= 0.003:
		return
	draw_texture_rect(_halo, Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), false, color)


func _flicker(ph: float) -> float:
	return 0.8 + 0.12 * sin(_time * 9.0 + ph) + 0.08 * sin(_time * 23.0 + ph * 3.0)


func _draw() -> void:
	var neon := land_use in ["megacity", "arcology"]
	# Le feu de camp se voit aussi de jour, faiblement.
	if land_use == "camp" and campfire.x >= 0.0:
		var f := _flicker(1.0)
		_glow(campfire, 90.0 * f, Color(1.0, 0.55, 0.2, (0.25 + 0.6 * intensity) * f))
		_glow(campfire, 18.0, Color(1.0, 0.85, 0.4, 0.9 * f))
	if intensity <= 0.01:
		return
	for s in sources:
		var a: float = s.alpha * intensity
		var p: Vector2 = s.pos
		var size: float = s.size
		var ph := p.x * 0.013 + p.y * 0.007
		match String(s.kind):
			"hut":
				var f := _flicker(ph)
				_glow(p, size * 2.2 * f, Color(1.0, 0.55, 0.22, 0.55 * a * f))
			"building":
				_glow(p, size * 1.6, Color(1.0, 0.82, 0.5, 0.45 * a))
			"tower":
				if neon:
					var c: Color = NEON[int(absf(ph * 100.0)) % NEON.size()]
					var pulse := 0.7 + 0.3 * sin(_time * 2.5 + ph * 10.0)
					_glow(p, size * 2.4, Color(c, 0.6 * a * pulse))
				else:
					_glow(p, size * 1.8, Color(1.0, 0.9, 0.65, 0.4 * a))
			"field":
				pass
	# Réverbères le long des routes (villes), néons au sol (mégapoles).
	if land_use in ["town", "city", "megacity", "arcology"]:
		var lamp := Color(0.4, 0.95, 1.0) if neon else Color(1.0, 0.78, 0.45)
		for c in roads:
			var x := 40.0
			while x < ParcelLogic.PARCEL_SIZE.x:
				_glow(Vector2(x, c.y - 22.0), 34.0, Color(lamp, 0.35 * intensity))
				x += 120.0
			var y := 40.0
			while y < ParcelLogic.PARCEL_SIZE.y:
				_glow(Vector2(c.x + 22.0, y), 34.0, Color(lamp, 0.35 * intensity))
				y += 120.0
