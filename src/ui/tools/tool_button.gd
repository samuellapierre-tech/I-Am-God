extends Button
## Bouton d'outil (semence ou pouvoir) : bascule de sélection, et recharge dessinée par-dessus
## (voile qui se retire de bas en haut, secondes restantes). Lit ToolState à chaque image tant
## qu'une recharge est en cours.

const Cooldowns := preload("res://src/ui/tools/cooldowns.gd")

## Outil représenté ({kind, id}) et état partagé.
var tool: Dictionary = {}
var tool_state: Node = null
var accent := Color(1, 1, 1)

var _ratio := 0.0
var _remaining := 0.0


func _init() -> void:
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	clip_text = true


func _process(_delta: float) -> void:
	if tool_state == null:
		return
	var r: float = tool_state.recharge_ratio(tool)
	var rem: float = tool_state.remaining(tool)
	if not is_equal_approx(r, _ratio) or int(ceilf(rem)) != int(ceilf(_remaining)):
		_ratio = r
		_remaining = rem
		queue_redraw()


func _draw() -> void:
	if _ratio <= 0.0:
		return
	var h := size.y * _ratio
	draw_rect(Rect2(Vector2(0, size.y - h), Vector2(size.x, h)), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(Vector2(0, size.y - 3), Vector2(size.x * (1.0 - _ratio), 3)), Color(accent, 0.9))
	var font := get_theme_default_font()
	var text := Cooldowns.format_remaining(_remaining)
	draw_string(font, Vector2(0, 14), text, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5, 12, Color(1, 1, 1, 0.9))
