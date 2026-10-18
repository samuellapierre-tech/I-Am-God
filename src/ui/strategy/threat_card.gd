extends PanelContainer
## Carte de menace : titre, cible, compte à rebours (ou état contrée / frappée), contres possibles.
## Cliquer un contre arme ce pouvoir (signal counter_chosen).

signal counter_chosen(power: String)

const Fmt := preload("res://src/ui/strategy/strategy_format.gd")
const Rules := preload("res://src/strategy/strategy_rules.gd")

var threat: Dictionary = {}

var _style: StyleBoxFlat
var _title: Label
var _target: Label
var _status: Label
var _counters: HFlowContainer
var _samael: Label
var _state := ""


func _ready() -> void:
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.1, 0.1, 0.14, 0.9)
	_style.set_border_width_all(0)
	_style.border_width_left = 4
	_style.set_corner_radius_all(4)
	_style.content_margin_left = 8
	_style.content_margin_right = 6
	_style.content_margin_top = 4
	_style.content_margin_bottom = 5
	add_theme_stylebox_override("panel", _style)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tooltip_text = String(threat.get("text", ""))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	add_child(col)
	_title = _line(18, Fmt.TEXT)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)
	_target = _line(15, Fmt.DIM)
	_target.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_target)
	_status = _line(16, Fmt.GOLD)
	col.add_child(_status)
	# Ligne discrète : pourquoi Samaël a choisi cette carte.
	_samael = _line(14, Fmt.SAMAEL)
	_samael.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var reason := Fmt.samael_reason(String(threat.get("samael", {}).get("reason_code", "")))
	_samael.text = "Samaël : " + reason
	_samael.visible = reason != ""
	col.add_child(_samael)
	_counters = HFlowContainer.new()
	_counters.add_theme_constant_override("h_separation", 4)
	_counters.add_theme_constant_override("v_separation", 2)
	col.add_child(_counters)
	var lead := _line(15, Fmt.DIM)
	lead.text = "Contres :"
	_counters.add_child(lead)
	for c in threat.get("counters", []):
		var b := Button.new()
		b.text = Rules.power_label(c)
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_color", Fmt.SAFE)
		b.tooltip_text = "Armer %s (puis clic sur la parcelle)" % Rules.power_label(c)
		b.pressed.connect(counter_chosen.emit.bind(String(c)))
		_counters.add_child(b)
	refresh(GameState.sim.year if GameState.sim != null else 0.0)


func refresh(now_year: float) -> void:
	if _title == null:
		return
	_title.text = Fmt.threat_title(threat)
	_target.text = Fmt.threat_target(threat)
	var mode: String = GameState.strategy.mode if GameState.strategy != null else "trial"
	var st: Array = Fmt.threat_status(threat, now_year, mode)
	_status.text = st[0]
	_status.add_theme_color_override("font_color", st[1])
	var state := String(threat.get("state", "pending"))
	if state == _state:
		return
	_state = state
	var accent: Color = Fmt.DANGER if threat.get("cataclysm", false) else Fmt.GOLD
	match state:
		"countered":
			accent = Fmt.SAFE
		"struck":
			accent = Fmt.DANGER
		"fizzled":
			accent = Fmt.DIM
	_style.border_color = accent
	_title.add_theme_color_override("font_color", Fmt.TEXT if state == "pending" else Fmt.DIM)
	_counters.visible = state == "pending"
	modulate.a = 1.0 if state == "pending" else 0.75


static func _line(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
