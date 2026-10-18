extends Control
## Jauge de chaleur : dégradé bleu -> rouge de -30 à 45 °C, curseur pour la température locale,
## trait fin pour la moyenne mondiale. Les curseurs glissent en douceur vers leur nouvelle valeur.

const StatsMath := preload("res://src/ui/stats/stats_math.gd")

const BAR_HEIGHT := 10.0
const SEGMENTS := 48

var local_c := 15.0
var global_c := 15.0

var _shown_local := NAN
var _shown_global := NAN


func _init() -> void:
	custom_minimum_size = Vector2(0, 22)
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_values(p_local: float, p_global: float) -> void:
	local_c = p_local
	global_c = p_global
	if is_nan(_shown_local):
		_shown_local = local_c
		_shown_global = global_c
	tooltip_text = "Échelle de -30 à 45 °C\nParcelle : %s\nMoyenne mondiale : %s" % [
		StatsMath.format_temperature(local_c), StatsMath.format_temperature(global_c)]
	queue_redraw()


func _process(delta: float) -> void:
	if is_nan(_shown_local):
		return
	var l := StatsMath.approach(_shown_local, local_c, delta, 5.0)
	var g := StatsMath.approach(_shown_global, global_c, delta, 5.0)
	if absf(l - _shown_local) > 0.001 or absf(g - _shown_global) > 0.001:
		_shown_local = l
		_shown_global = g
		queue_redraw()


func _draw() -> void:
	var bar := Rect2(Vector2(0, (size.y - BAR_HEIGHT) * 0.5), Vector2(size.x, BAR_HEIGHT))
	var seg_w := bar.size.x / SEGMENTS
	for k in SEGMENTS:
		var c := StatsMath.TEMP_MIN + (StatsMath.TEMP_MAX - StatsMath.TEMP_MIN) * (k + 0.5) / SEGMENTS
		var color := StatsMath.temperature_color(c)
		color.a = 0.85
		draw_rect(Rect2(bar.position.x + seg_w * k, bar.position.y, seg_w + 0.5, bar.size.y), color)
	draw_rect(bar, Color(0, 0, 0, 0.5), false, 1.0)
	# Repère 0 °C.
	var zero_x := bar.position.x + StatsMath.temperature_ratio(0.0) * bar.size.x
	draw_line(Vector2(zero_x, bar.position.y), Vector2(zero_x, bar.end.y), Color(0, 0, 0, 0.35), 1.0)
	if is_nan(_shown_local):
		return
	# Moyenne mondiale : trait clair.
	var gx := bar.position.x + StatsMath.temperature_ratio(_shown_global) * bar.size.x
	draw_line(Vector2(gx, 1), Vector2(gx, size.y - 1), Color(1, 1, 1, 0.75), 2.0)
	# Parcelle : curseur en losange de la couleur de sa température.
	var lx := bar.position.x + StatsMath.temperature_ratio(_shown_local) * bar.size.x
	var cy := size.y * 0.5
	var r := size.y * 0.5 - 1.0
	var diamond := PackedVector2Array([Vector2(lx, cy - r), Vector2(lx + r * 0.7, cy),
		Vector2(lx, cy + r), Vector2(lx - r * 0.7, cy)])
	draw_colored_polygon(diamond, StatsMath.temperature_color(_shown_local))
	diamond.append(diamond[0])
	draw_polyline(diamond, Color(1, 1, 1, 0.95), 1.5, true)
