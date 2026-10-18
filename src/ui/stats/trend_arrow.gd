extends Control
## Flèche de tendance dessinée (▲ verte, ▼ rouge, = grise) : ne dépend d'aucun glyphe de police,
## donc reste nette sur toutes les machines (Windows, Steam Deck).

const StatsMath := preload("res://src/ui/stats/stats_math.gd")

var trend := 0:
	set(value):
		if value != trend:
			trend = value
			tooltip_text = _tooltip(value)
			queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(16, 16)
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = _tooltip(0)


func _draw() -> void:
	draw_arrow(self, Rect2(Vector2.ZERO, size), trend)


static func draw_arrow(ci: CanvasItem, rect: Rect2, value: int, alpha: float = 1.0) -> void:
	var color := StatsMath.trend_color(value)
	color.a *= alpha
	var s := minf(rect.size.x, rect.size.y) * 0.8
	var c := rect.get_center()
	if value > 0:
		ci.draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -s * 0.5), c + Vector2(s * 0.5, s * 0.4), c + Vector2(-s * 0.5, s * 0.4)]), color)
	elif value < 0:
		ci.draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, s * 0.5), c + Vector2(-s * 0.5, -s * 0.4), c + Vector2(s * 0.5, -s * 0.4)]), color)
	else:
		var w := maxf(2.0, s * 0.16)
		ci.draw_rect(Rect2(c + Vector2(-s * 0.42, -s * 0.24), Vector2(s * 0.84, w)), color)
		ci.draw_rect(Rect2(c + Vector2(-s * 0.42, s * 0.24 - w), Vector2(s * 0.84, w)), color)


static func _tooltip(value: int) -> String:
	if value > 0:
		return "En hausse"
	if value < 0:
		return "En baisse"
	return "Stable"
