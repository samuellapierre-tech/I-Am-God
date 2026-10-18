extends Control
## Barre de temps restant du dilemme : se vide de droite à gauche, passe de l'or au rouge.

const DilemmaMath := preload("res://src/ui/dilemma/dilemma_math.gd")

var ratio := 1.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if not is_equal_approx(value, ratio):
			ratio = value
			queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(0, 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(1, 1, 1, 0.08))
	var fill := Rect2(r.position, Vector2(r.size.x * ratio, r.size.y))
	var color := DilemmaMath.time_color(ratio)
	draw_rect(fill, color)
	# Liseré clair sur le bord qui avance.
	if ratio > 0.0:
		draw_rect(Rect2(Vector2(fill.end.x - 2.0, 0), Vector2(2, r.size.y)), color.lightened(0.5))
