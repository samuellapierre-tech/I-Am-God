extends Control
## Dessin de l'arbre de la vie (mise en page TreeLayout) : un segment par espèce, de sa naissance à
## son extinction (ou au présent), relié à son parent. Vivantes en couleur, éteintes grisées ;
## ◆ doré = semée par le joueur, anneau = touchée par un de ses actes.
## Molette : zoom autour du curseur (Maj : seulement le temps) ; glisser : déplacer ; clic : choisir ;
## double-clic : centrer l'espèce sur le globe.

signal species_clicked(species_id: int)
signal species_double_clicked(species_id: int)

const TreeLayout := preload("res://src/ui/tree/tree_layout.gd")
const StatsMath := preload("res://src/ui/stats/stats_math.gd")
const MapMath := preload("res://src/map/map_math.gd")

const LANE_PX := 14.0
const RANK_PX := 6.0
const AXIS_H := 22.0
const EXTINCT_COLOR := Color(0.45, 0.46, 0.52)
const LINK_COLOR := Color(1, 1, 1, 0.16)
const SOWN_COLOR := Color(1.0, 0.85, 0.35)
const TOUCHED_COLOR := Color(0.85, 0.65, 1.0)
const MAX_LABELS := 160

var layout: Dictionary = {}
## id -> entrée de filiation (TreeLayout.entries_from)
var entries := {}
var sown := {}
var touched := {}
var selected := -1

## Vue : origine en (rang, couloir) et zoom.
var _origin := Vector2.ZERO
var _zoom := 1.0
var _zoom_x := 1.0
var _drag_from := Vector2.INF
var _dragged := false
var _hover := -1
var _pending_fit := false


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func set_data(p_layout: Dictionary, p_entries: Dictionary) -> void:
	layout = p_layout
	entries = p_entries
	queue_redraw()


## Cadre tout l'arbre dans la vue.
func fit_all() -> void:
	if layout.is_empty() or size.x < 100.0 or size.y < 60.0:
		_pending_fit = true  # pas encore mis en page : on cadrera au premier redimensionnement
		return
	_pending_fit = false
	var w := float(layout.width)
	var h := float(maxi(int(layout.lanes), 1))
	# Hauteur : tous les couloirs ; largeur : le temps s'étire (ou se tasse) pour remplir la vue.
	_zoom = clampf((size.y - AXIS_H - 10.0) / (h * LANE_PX), 0.02, 8.0)
	_zoom_x = clampf((size.x - 20.0) / (w * RANK_PX * _zoom), 0.1, 50.0)
	_origin = Vector2(-10.0 / _px_per_rank(), -5.0 / _px_per_lane())
	queue_redraw()


## Centre la vue sur une espèce (zoom lisible).
func focus(id: int) -> void:
	if layout.is_empty() or not layout.nodes.has(id):
		return
	_zoom = maxf(_zoom, 1.0)
	var n: Dictionary = layout.nodes[id]
	_origin = Vector2(n.x0 - size.x * 0.4 / _px_per_rank(), n.lane - (size.y - AXIS_H) * 0.5 / _px_per_lane())
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _pending_fit:
		fit_all()


func _px_per_rank() -> float:
	return RANK_PX * _zoom * _zoom_x


func _px_per_lane() -> float:
	return LANE_PX * _zoom


func _to_screen(rank: float, lane: float) -> Vector2:
	return Vector2((rank - _origin.x) * _px_per_rank(), (lane - _origin.y) * _px_per_lane())


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb:
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_zoom_at(mb.position, 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15, mb.shift_pressed)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_drag_from = mb.position
				_dragged = false
				if mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
					var id := _pick(mb.position)
					if id >= 0:
						species_double_clicked.emit(id)
			else:
				if not _dragged and mb.button_index == MOUSE_BUTTON_LEFT:
					var id := _pick(mb.position)
					if id >= 0:
						selected = id
						species_clicked.emit(id)
						queue_redraw()
				_drag_from = Vector2.INF
			accept_event()
	var mm := event as InputEventMouseMotion
	if mm:
		if _drag_from != Vector2.INF:
			var d := mm.position - _drag_from
			if d.length() > 3.0 or _dragged:
				_dragged = true
				_origin -= Vector2(mm.relative.x / _px_per_rank(), mm.relative.y / _px_per_lane())
				queue_redraw()
		else:
			var h := _pick(mm.position)
			if h != _hover:
				_hover = h
				tooltip_text = str(entries[h].get("name", "")) if h >= 0 and entries.has(h) else ""
				queue_redraw()


func _zoom_at(pos: Vector2, factor: float, time_only: bool) -> void:
	var before := Vector2(pos.x / _px_per_rank(), pos.y / _px_per_lane()) + _origin
	if time_only:
		_zoom_x = clampf(_zoom_x * factor, 0.1, 50.0)
	else:
		_zoom = clampf(_zoom * factor, 0.02, 8.0)
	var after := Vector2(pos.x / _px_per_rank(), pos.y / _px_per_lane()) + _origin
	_origin += before - after
	queue_redraw()


## Espèce sous le point (à 6 px près), -1 sinon.
func _pick(pos: Vector2) -> int:
	if layout.is_empty():
		return -1
	var best := -1
	var best_d := 6.0
	for id in layout.nodes:
		var n: Dictionary = layout.nodes[id]
		var y := _to_screen(0.0, n.lane).y
		if absf(pos.y - y) > best_d:
			continue
		var a := _to_screen(n.x0, n.lane).x
		var b := _to_screen(n.x1, n.lane).x
		var dx := 0.0 if pos.x >= a and pos.x <= b else minf(absf(pos.x - a), absf(pos.x - b))
		var d := maxf(dx, absf(pos.y - y))
		if d < best_d:
			best_d = d
			best = id
	return best


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, 0.6))
	if layout.is_empty() or layout.nodes.is_empty():
		draw_string(get_theme_default_font(), Vector2(0, size.y * 0.5), "Aucune espèce n'est encore née.",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(0.7, 0.72, 0.82))
		return
	var font := get_theme_default_font()
	var view := Rect2(Vector2(-20, -10), size + Vector2(40, 20))
	var lane_px := _px_per_lane()
	var thick := clampf(lane_px * 0.35, 1.0, 5.0)
	var labels := 0
	var show_labels := lane_px >= 11.0
	# Liens parent -> enfant d'abord, segments par-dessus.
	for id in layout.nodes:
		var n: Dictionary = layout.nodes[id]
		if n.parent < 0 or not layout.nodes.has(n.parent):
			continue
		var p: Dictionary = layout.nodes[n.parent]
		var top := _to_screen(n.x0, p.lane)
		var bottom := _to_screen(n.x0, n.lane)
		if maxf(top.y, bottom.y) < view.position.y or minf(top.y, bottom.y) > view.end.y \
				or top.x < view.position.x or top.x > view.end.x:
			continue
		draw_line(top, bottom, LINK_COLOR, 1.0)
	for id in layout.nodes:
		var n: Dictionary = layout.nodes[id]
		var a := _to_screen(n.x0, n.lane)
		var b := _to_screen(n.x1, n.lane)
		if a.y < view.position.y or a.y > view.end.y or b.x < view.position.x or a.x > view.end.x:
			continue
		var e: Dictionary = entries.get(id, {})
		var alive := bool(e.get("alive", not is_finite(float(e.get("extinct_year", NAN)))))
		var color := MapMath.species_color(id) if alive else EXTINCT_COLOR
		if id == selected or id == _hover:
			draw_line(a, b, Color(1, 1, 1, 0.9), thick + 3.0)
		draw_line(a, b, color, thick)
		if sown.has(id) or bool(e.get("sown", false)):
			var r := thick + 3.0
			draw_colored_polygon(PackedVector2Array([a + Vector2(0, -r), a + Vector2(r, 0), a + Vector2(0, r),
				a + Vector2(-r, 0)]), SOWN_COLOR)
		elif touched.has(id) or bool(e.get("touched", false)):
			draw_arc(a, thick + 3.0, 0.0, TAU, 16, TOUCHED_COLOR, 1.5)
		if show_labels and labels < MAX_LABELS and b.x - a.x > 40.0:
			labels += 1
			draw_string(font, a + Vector2(6, -thick - 2), str(e.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT,
				minf(b.x - a.x, 260.0), 12, Color(color.lightened(0.3), 0.9 if alive else 0.6))
	_draw_axis(font)


func _draw_axis(font: Font) -> void:
	var y0 := size.y - AXIS_H
	draw_rect(Rect2(0, y0, size.x, AXIS_H), Color(0.02, 0.03, 0.06, 0.85))
	var ranks: PackedFloat64Array = layout.get("ranks", PackedFloat64Array())
	if ranks.is_empty():
		return
	var step_px := 170.0
	var x := 10.0
	var span := absf(ranks[ranks.size() - 1] - ranks[0])
	while x < size.x - 40.0:
		var rank := _origin.x + x / _px_per_rank()
		if rank >= 0.0 and rank <= float(layout.width):
			var year := TreeLayout.rank_to_year(ranks, rank)
			draw_line(Vector2(x, y0), Vector2(x, y0 + 4), Color(1, 1, 1, 0.4), 1.0)
			draw_string(font, Vector2(x + 3, y0 + 16), StatsMath.format_axis_year(year, span),
				HORIZONTAL_ALIGNMENT_LEFT, step_px - 8.0, 12, Color(0.65, 0.68, 0.8))
		x += step_px
