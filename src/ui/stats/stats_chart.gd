extends Control
## Courbe(s) tracée(s) à partir de parcel.history. Abscisse = ordre des échantillons (temps réel de
## jeu), étiquetée avec l'année de l'échantillon ; ordonnée mise à l'échelle par StatsMath.
## Survol : curseur vertical et lecture des valeurs ; les séries « hover_only » (une par espèce)
## n'apparaissent qu'au survol de la courbe ou de la ligne d'espèce correspondante (highlight_id).
## Mode compact : mini-courbe sans axes ni étiquettes.

const StatsMath := preload("res://src/ui/stats/stats_math.gd")

const LABEL_SIZE := 12
const READOUT_SIZE := 13
const AXIS_HEIGHT := 16.0
const GUTTER := 46.0
const GRID_COLOR := Color(1, 1, 1, 0.07)
const LABEL_COLOR := Color(0.62, 0.66, 0.78)

@export var compact := false
## Écart vertical minimal (évite d'amplifier le bruit d'une courbe presque plate).
@export var min_span := 1.0
@export var include_zero := false

## Formatage des valeurs (étiquettes et lecture au survol).
var value_format: Callable = func(v: float) -> String: return StatsMath.format_decimal(v, 1)
## Espèce mise en avant depuis le panneau (survol d'une ligne), -1 sinon.
var highlight_id := -1:
	set(value):
		if value != highlight_id:
			highlight_id = value
			_target_range = StatsMath.value_range(_visible_values(), min_span, include_zero)
			queue_redraw()

var _years := PackedFloat32Array()
## [{id: int, data: PackedFloat32Array, color: Color, width: float, label: String, hover_only: bool}]
var _series: Array[Dictionary] = []
var _range := Vector2(0, 1)
var _target_range := Vector2(0, 1)
var _has_range := false
var _hover_x := -1.0


func _init() -> void:
	# Pas de découpe : les tracés sont bornés au cadre par scale_points, et la bulle de lecture
	# peut déborder vers le haut (sur les éléments précédents du panneau) quand elle est haute.
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	mouse_exited.connect(_on_mouse_exited)


func set_data(years: PackedFloat32Array, series: Array[Dictionary]) -> void:
	_years = years
	_series = series
	_target_range = StatsMath.value_range(_visible_values(), min_span, include_zero)
	if not _has_range:
		_has_range = true
		_range = _target_range
	queue_redraw()


## Nouvelle parcelle : la prochaine série fixe l'échelle sans transition.
func reset() -> void:
	_has_range = false
	_hover_x = -1.0
	var none: Array[Dictionary] = []
	set_data(PackedFloat32Array(), none)
	_has_range = false


func _process(delta: float) -> void:
	if _range.is_equal_approx(_target_range):
		return
	_range = Vector2(StatsMath.approach(_range.x, _target_range.x, delta, 4.0),
		StatsMath.approach(_range.y, _target_range.y, delta, 4.0))
	if (_range - _target_range).abs().length() < (_target_range.y - _target_range.x) * 0.002:
		_range = _target_range
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not compact:
		_hover_x = (event as InputEventMouseMotion).position.x
		_target_range = StatsMath.value_range(_visible_values(), min_span, include_zero)
		queue_redraw()


func _on_mouse_exited() -> void:
	if _hover_x >= 0.0:
		_hover_x = -1.0
		_target_range = StatsMath.value_range(_visible_values(), min_span, include_zero)
		queue_redraw()


func _plot_rect() -> Rect2:
	if compact:
		return Rect2(Vector2(1, 2), size - Vector2(2, 4))
	return Rect2(Vector2(GUTTER, 4), Vector2(size.x - GUTTER - 2, size.y - AXIS_HEIGHT - 6))


func _is_shown(s: Dictionary) -> bool:
	return not s.get("hover_only", false) or _hover_x >= 0.0 or int(s.get("id", -1)) == highlight_id


func _visible_values() -> Array:
	var out := []
	for s in _series:
		if _is_shown(s):
			out.append(s["data"])
	return out


func _draw() -> void:
	var rect := _plot_rect()
	var font := get_theme_default_font()
	draw_rect(rect, Color(0, 0, 0, 0.22))
	if not compact:
		for k in 3:
			var y := rect.position.y + rect.size.y * k / 2.0
			draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), GRID_COLOR, 1.0)
		draw_string(font, Vector2(0, rect.position.y + LABEL_SIZE), value_format.call(_range.y),
			HORIZONTAL_ALIGNMENT_RIGHT, GUTTER - 6, LABEL_SIZE, LABEL_COLOR)
		draw_string(font, Vector2(0, rect.end.y), value_format.call(_range.x),
			HORIZONTAL_ALIGNMENT_RIGHT, GUTTER - 6, LABEL_SIZE, LABEL_COLOR)
	if _years.is_empty():
		if not compact:
			draw_string(font, Vector2(rect.position.x, rect.get_center().y + 5), "En attente de données…",
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, LABEL_SIZE, LABEL_COLOR)
		return
	# Séries de fond (espèces) d'abord, séries principales par-dessus.
	for pass_hover in [true, false]:
		for s in _series:
			if bool(s.get("hover_only", false)) != pass_hover or not _is_shown(s):
				continue
			var pts := StatsMath.scale_points(s["data"], rect, _range)
			if pts.size() < 2:
				continue
			var color: Color = s.get("color", Color.WHITE)
			var width := float(s.get("width", 2.0))
			if pass_hover and int(s.get("id", -1)) == highlight_id:
				width += 1.0
			elif pass_hover and highlight_id >= 0:
				color.a *= 0.35
			draw_polyline(pts, color, width, true)
	if not compact:
		_draw_time_axis(font, rect)
		if _hover_x >= 0.0:
			_draw_readout(font, rect)


func _draw_time_axis(font: Font, rect: Rect2) -> void:
	var n := _years.size()
	var span := absf(_years[n - 1] - _years[0])
	var y := size.y - 3.0
	var third := rect.size.x / 3.0
	draw_string(font, Vector2(rect.position.x, y), StatsMath.format_axis_year(_years[0], span),
		HORIZONTAL_ALIGNMENT_LEFT, third, LABEL_SIZE, LABEL_COLOR)
	if n > 2:
		draw_string(font, Vector2(rect.position.x + third, y), StatsMath.format_axis_year(_years[n / 2], span),
			HORIZONTAL_ALIGNMENT_CENTER, third, LABEL_SIZE, LABEL_COLOR)
	draw_string(font, Vector2(rect.position.x + third * 2.0, y), StatsMath.format_axis_year(_years[n - 1], span),
		HORIZONTAL_ALIGNMENT_RIGHT, third, LABEL_SIZE, LABEL_COLOR)


func _draw_readout(font: Font, rect: Rect2) -> void:
	var n := _years.size()
	var i := StatsMath.sample_index_at(_hover_x, rect, n)
	var x := rect.position.x + (rect.size.x * i / float(n - 1) if n > 1 else rect.size.x)
	draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(1, 1, 1, 0.45), 1.0)
	var lines: Array[Array] = [[StatsMath.format_axis_year(_years[i], absf(_years[n - 1] - _years[0])), LABEL_COLOR]]
	for s in _series:
		if not _is_shown(s) or i >= s["data"].size():
			continue
		var v: float = s["data"][i]
		if s.get("hover_only", false) and v <= 0.0:
			continue
		var color: Color = s.get("color", Color.WHITE)
		lines.append(["%s : %s" % [s.get("label", ""), value_format.call(v)], color.lightened(0.2)])
		draw_circle(Vector2(x, rect.end.y - StatsMath.bar_ratio(v - _range.x, _range.y - _range.x) * rect.size.y),
			3.0, color)
	var line_h := READOUT_SIZE + 3.0
	var w := 0.0
	for l in lines:
		w = maxf(w, font.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, READOUT_SIZE).x)
	w += 12.0
	var box := Rect2(Vector2(x + 8.0, rect.position.y + 2.0), Vector2(w, line_h * lines.size() + 6.0))
	if box.end.x > rect.end.x:
		box.position.x = x - 8.0 - w
	box.position.x = maxf(box.position.x, 0.0)
	if box.end.y > size.y:
		box.position.y = size.y - box.size.y
	draw_rect(box, Color(0.02, 0.03, 0.06, 0.88))
	for k in lines.size():
		draw_string(font, box.position + Vector2(6, 4 + line_h * (k + 1) - 4), lines[k][0],
			HORIZONTAL_ALIGNMENT_LEFT, -1, READOUT_SIZE, lines[k][1])
