extends Node2D
## Constructions de la parcelle (parcel.structures) : champs, huttes, routes, bâtiments, tours,
## ruines, à leurs positions `pos` (0..1) stables. Image assets/parcel/structures/<kind>.png si
## elle existe, sinon dessin de remplacement. Apparitions / disparitions en fondu.

const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")
const ParcelAssets := preload("res://src/parcel/parcel_assets.gd")

const FADE_TIME := 2.0
## Ordre de dessin : le sol construit d'abord, les volumes ensuite.
const LAYER := {"road": 0, "field": 1, "ruin": 2, "hut": 3, "building": 3, "tower": 4}
## Usages où les structures sont éclairées au néon.
const NEON_USES := ["megacity", "arcology"]

var assets: ParcelAssets
var parcel_size := ParcelLogic.PARCEL_SIZE

var _items := {} ## key -> {data, alpha, present}
var _land_use := ""
var _animating := false
var _time := 0.0


func _ready() -> void:
	if assets == null:
		assets = ParcelAssets.new()


func apply_parcel(p: ParcelSim) -> void:
	_land_use = p.land_use
	for item in _items.values():
		item.present = false
	for s in p.structures:
		var key := ParcelLogic.structure_key(s)
		if _items.has(key):
			_items[key].present = true
			_items[key].data = s
		else:
			_items[key] = {data = s, alpha = 0.0, present = true}
	_animating = true
	queue_redraw()


func clear() -> void:
	_items.clear()
	queue_redraw()


## Positions monde des structures où vont et viennent les espèces intelligentes.
func spots() -> PackedVector2Array:
	var out := PackedVector2Array()
	for item in _items.values():
		var s: Dictionary = item.data
		if item.present and String(s.get("kind", "")) in ["hut", "building", "tower", "field"]:
			out.append(_center(s))
	return out


func _process(delta: float) -> void:
	_time += delta
	if not _animating and not _land_use in NEON_USES:
		return
	var still := false
	for key in _items.keys():
		var item: Dictionary = _items[key]
		var target := 1.0 if item.present else 0.0
		item.alpha = move_toward(item.alpha, target, delta / FADE_TIME)
		if item.alpha != target:
			still = true
		elif not item.present:
			_items.erase(key)
	_animating = still
	queue_redraw()


func _draw() -> void:
	var list := _items.values()
	list.sort_custom(_draw_order)
	for item in list:
		if item.alpha > 0.0:
			_draw_structure(item.data, item.alpha)


func _draw_order(a: Dictionary, b: Dictionary) -> bool:
	var la: int = LAYER.get(a.data.get("kind", ""), 3)
	var lb: int = LAYER.get(b.data.get("kind", ""), 3)
	if la != lb:
		return la < lb
	return _center(a.data).y < _center(b.data).y


func _center(s: Dictionary) -> Vector2:
	var p: Vector2 = s.get("pos", Vector2(0.5, 0.5))
	return p * parcel_size


func _draw_structure(s: Dictionary, a: float) -> void:
	var kind := String(s.get("kind", ""))
	var center := _center(s)
	var side := float(s.get("size", 0.05)) * parcel_size.y
	var h := hash(ParcelLogic.structure_key(s))
	var angle := 0.0 if kind == "road" else (float(h % 4) * PI * 0.5 + (float(h % 100) / 100.0 - 0.5) * 0.25)
	var tex := assets.structure_texture(kind, _land_use)
	if kind == "road":
		_draw_road(center, side, tex, a)
		return
	draw_set_transform(center, angle)
	if tex:
		var r := Rect2(Vector2(-side, -side) * 0.5, Vector2(side, side))
		draw_texture_rect(tex, r.grow(side * 0.05), false, Color(1, 1, 1, a))
	else:
		match kind:
			"field": _draw_field(side, h, a)
			"hut": _draw_hut(side, a)
			"building": _draw_building(side, h, a)
			"tower": _draw_tower(side, h, a)
			"ruin": _draw_ruin(side, h, a)
			_: draw_rect(Rect2(Vector2(-side, -side) * 0.5, Vector2(side, side)), Color(0.4, 0.4, 0.4, a))
	draw_set_transform(Vector2.ZERO)


# --- Placeholders (vus de haut) ---

func _draw_field(side: float, h: int, a: float) -> void:
	var crops := [Color("c9b458"), Color("8fae4a"), Color("b5a04a"), Color("6f9a3e")]
	var col: Color = crops[h % crops.size()]
	var r := Rect2(Vector2(-side, -side * 0.7) * 0.5, Vector2(side, side * 0.7))
	draw_rect(r, Color(col, a))
	var furrow := Color(col.darkened(0.3), a * 0.8)
	var y := r.position.y + 4.0
	while y < r.end.y - 2.0:
		draw_line(Vector2(r.position.x + 2.0, y), Vector2(r.end.x - 2.0, y), furrow, 1.5)
		y += 7.0
	draw_rect(r, Color(0.3, 0.25, 0.15, a * 0.6), false, 2.0)


func _draw_hut(side: float, a: float) -> void:
	var r := side * 0.5
	draw_circle(Vector2(r * 0.25, r * 0.3), r, Color(0, 0, 0, 0.3 * a))
	draw_circle(Vector2.ZERO, r, Color(0.55, 0.42, 0.24, a))
	draw_circle(Vector2.ZERO, r * 0.7, Color(0.64, 0.5, 0.3, a))
	for k in 8:
		var d := Vector2.from_angle(k * TAU / 8.0)
		draw_line(d * r * 0.15, d * r, Color(0.42, 0.31, 0.17, a), 1.5)
	draw_circle(Vector2.ZERO, r * 0.15, Color(0.25, 0.2, 0.15, a))


func _draw_building(side: float, h: int, a: float) -> void:
	var size := Vector2(side, side * (0.6 + float(h % 30) / 100.0))
	var r := Rect2(-size * 0.5, size)
	var town := _land_use in ["village", "town"]
	var roof := Color("a5523a") if town else Color("6c6f78")
	draw_rect(Rect2(r.position + Vector2(side * 0.12, side * 0.16), size), Color(0, 0, 0, 0.3 * a))
	draw_rect(r, Color(roof, a))
	# Faîtage : deux pans de toit.
	draw_rect(Rect2(r.position, Vector2(size.x, size.y * 0.5)), Color(roof.lightened(0.15), a))
	draw_line(Vector2(r.position.x, 0), Vector2(r.end.x, 0), Color(roof.darkened(0.35), a), 2.0)
	draw_rect(r, Color(roof.darkened(0.4), a), false, 1.5)


func _draw_tower(side: float, h: int, a: float) -> void:
	var r := Rect2(Vector2(-side, -side) * 0.5, Vector2(side, side))
	# Ombre longue : la tour est haute.
	draw_rect(Rect2(r.position + Vector2(side * 0.35, side * 0.5), r.size), Color(0, 0, 0, 0.35 * a))
	var neon := _land_use in NEON_USES
	var body := Color("2a2c3a") if neon else Color("7a7f8a")
	draw_rect(r, Color(body, a))
	var cells := 4
	var cell := side / cells
	for ix in cells:
		for iy in cells:
			if (h >> (ix * cells + iy)) & 1:
				var lit := Color("ffe9a8") if not neon else (Color("3ff2ff") if (ix + iy) % 2 else Color("ff4fd8"))
				var w := Rect2(r.position + Vector2(ix, iy) * cell + Vector2.ONE * cell * 0.25, Vector2.ONE * cell * 0.5)
				draw_rect(w, Color(lit, a * (0.5 if not neon else 0.6 + 0.4 * sin(_time * 3.0 + ix + iy * 2.0))))
	if neon:
		var glow := Color(0.25, 0.95, 1.0, a * (0.5 + 0.3 * sin(_time * 2.0 + float(h % 10))))
		draw_rect(r, glow, false, 2.5)
	else:
		draw_rect(r, Color(0.3, 0.3, 0.35, a), false, 1.5)


func _draw_ruin(side: float, h: int, a: float) -> void:
	var r := Rect2(Vector2(-side, -side) * 0.5, Vector2(side, side))
	var wall := Color(0.55, 0.52, 0.46, a)
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for k in 4:
		if (h >> k) & 1 or k == 0:
			var from: Vector2 = corners[k]
			var to: Vector2 = corners[(k + 1) % 4]
			# Mur effondré : seul un morceau tient encore.
			draw_line(from, from.lerp(to, 0.45 + float((h >> (k + 4)) % 50) / 100.0), wall, 3.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	for k in 6:
		var p := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
		draw_circle(p, rng.randf_range(1.5, side * 0.08), Color(0.45, 0.42, 0.38, a))
	draw_circle(Vector2(side * 0.1, -side * 0.15), side * 0.18, Color(0.24, 0.42, 0.2, 0.6 * a)) # mousse


## Routes : deux axes qui se croisent en `center`, sur `side` (size * hauteur de la parcelle).
func _draw_road(center: Vector2, side: float, tex: Texture2D, a: float) -> void:
	var paved := not _land_use in ["village", "camp", "pasture", "farmland"]
	var width := 30.0 if paved else 16.0
	var half := maxf(side, parcel_size.x) * 0.5
	var rects := [
		Rect2(center.x - half, center.y - width * 0.5, half * 2.0, width),
		Rect2(center.x - width * 0.5, center.y - half, width, half * 2.0),
	]
	for r: Rect2 in rects:
		if tex:
			draw_texture_rect(tex, r, true, Color(1, 1, 1, a))
			continue
		var col := Color("3b3d42") if paved else Color("8a7350")
		draw_rect(r.grow(2.0), Color(col.darkened(0.3), a * 0.7))
		draw_rect(r, Color(col, a))
		if paved:
			var horizontal := r.size.x > r.size.y
			var dash := Color(0.95, 0.85, 0.4, a * 0.8)
			var length := r.size.x if horizontal else r.size.y
			var t := 0.0
			while t < length:
				if horizontal:
					draw_line(Vector2(r.position.x + t, center.y), Vector2(r.position.x + t + 14.0, center.y), dash, 2.0)
				else:
					draw_line(Vector2(center.x, r.position.y + t), Vector2(center.x, r.position.y + t + 14.0), dash, 2.0)
				t += 30.0
