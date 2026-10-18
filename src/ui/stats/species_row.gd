extends Control
## Une ligne de population : pastille de rôle, nom, effectif, flèche de tendance et barre
## proportionnelle. L'effectif et la barre glissent vers leur nouvelle valeur ; une ligne apparaît
## en fondu. Quand l'espèce quitte la parcelle, la ligne est barrée puis s'efface (signal `faded`).

signal hover_changed(species_id: int, hovered: bool)
## La ligne d'une espèce disparue a fini de s'effacer : le panneau peut la libérer.
signal faded(species_id: int)

const StatsMath := preload("res://src/ui/stats/stats_math.gd")
const TrendArrow := preload("res://src/ui/stats/trend_arrow.gd")

const ROW_HEIGHT := 28.0
const NAME_SIZE := 16
const COUNT_SIZE := 16
const FADE_IN := 0.4
const FADE_OUT := 1.8
const COUNT_WIDTH := 64.0
const ARROW_WIDTH := 18.0

var species_id := -1
var species_name := ""
var role := "omnivore"
var clade := ""
var trend := 0
## Effectif cible et part de la barre (0..1), atteints en douceur.
var target_count := 0.0
var target_ratio := 0.0
var gone := false

var _count := 0.0
var _ratio := 0.0
var _alpha := 0.0
var _gone_time := 0.0
var _strike := 0.0
var _hovered := false
var _fit_key := ""
var _fit_text := ""


func _init() -> void:
	custom_minimum_size = Vector2(0, ROW_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))


## Met à jour la ligne depuis une entrée de parcel.fauna. `max_count` dimensionne la barre.
func set_entry(entry: Dictionary, count: float, max_count: float) -> void:
	var first := species_id < 0
	species_id = int(entry.get("species_id", -1))
	species_name = String(entry.get("name", "?"))
	role = String(entry.get("role", "omnivore"))
	clade = String(entry.get("clade", ""))
	trend = int(entry.get("trend", 0))
	target_count = count
	target_ratio = StatsMath.bar_ratio(count, max_count)
	if gone:
		gone = false  # l'espèce revient avant la fin du fondu
		_gone_time = 0.0
	if first:
		_count = count
		_ratio = 0.0  # la barre pousse depuis la gauche à l'apparition
	tooltip_text = "%s — %s%s\nEffectif : %s (%s)" % [species_name, StatsMath.role_label(role),
		(" (%s)" % clade) if clade != "" else "", StatsMath.format_count(count),
		TrendArrow._tooltip(trend).to_lower()]
	queue_redraw()


## L'espèce a quitté la parcelle : ligne barrée qui s'efface.
func mark_gone() -> void:
	if gone:
		return
	gone = true
	_gone_time = 0.0
	trend = -1
	target_ratio = 0.0
	tooltip_text = "%s — a disparu de la parcelle" % species_name


func _process(delta: float) -> void:
	var before := Vector4(_count, _ratio, _alpha, _strike)
	_count = StatsMath.approach(_count, target_count, delta, 5.0)
	_ratio = StatsMath.approach(_ratio, target_ratio, delta, 5.0)
	if gone:
		_gone_time += delta
		_strike = minf(1.0, _strike + delta / 0.35)
		_alpha = clampf(1.0 - (_gone_time - 0.5) / (FADE_OUT - 0.5), 0.0, 1.0)
		if _gone_time >= FADE_OUT:
			set_process(false)
			faded.emit(species_id)
			return
	else:
		_strike = maxf(0.0, _strike - delta / 0.25)
		_alpha = minf(1.0, _alpha + delta / FADE_IN)
	if not before.is_equal_approx(Vector4(_count, _ratio, _alpha, _strike)):
		queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var w := size.x
	var a := _alpha
	if _hovered:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.06 * a))
	var role_color := StatsMath.role_color(role)
	var text_color := Color(0.92, 0.92, 0.96, a) if not gone else Color(0.6, 0.6, 0.65, a)
	var base := 18.0
	# Pastille de rôle.
	draw_circle(Vector2(9, base - 5), 5.0, Color(role_color, a))
	# Nom (tronqué si besoin) et effectif aligné à droite.
	var name_x := 20.0
	var name_w := w - name_x - COUNT_WIDTH - ARROW_WIDTH - 8.0
	draw_string(font, Vector2(name_x, base), _fit(font, species_name, name_w), HORIZONTAL_ALIGNMENT_LEFT, -1,
		NAME_SIZE, text_color)
	var count_x := w - ARROW_WIDTH - 6.0 - COUNT_WIDTH
	draw_string(font, Vector2(count_x, base), StatsMath.format_count(_count), HORIZONTAL_ALIGNMENT_RIGHT,
		COUNT_WIDTH, COUNT_SIZE, text_color)
	TrendArrow.draw_arrow(self, Rect2(Vector2(w - ARROW_WIDTH - 2.0, base - 15.0), Vector2(ARROW_WIDTH, 16)),
		trend, a)
	# Barre proportionnelle.
	var bar := Rect2(Vector2(name_x, ROW_HEIGHT - 7.0), Vector2(w - name_x - 4.0, 4.0))
	draw_rect(bar, Color(1, 1, 1, 0.06 * a))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * _ratio, bar.size.y)), Color(role_color, 0.75 * a))
	# Barré : le trait progresse de gauche à droite.
	if _strike > 0.0:
		var name_len := minf(font.get_string_size(species_name, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x, name_w)
		var end_x := lerpf(name_x, w - ARROW_WIDTH - 6.0, _strike)
		draw_line(Vector2(name_x - 2.0, base - 6.0), Vector2(maxf(end_x, name_x + name_len * _strike), base - 6.0),
			Color(1.0, 0.45, 0.4, 0.9 * a), 2.0)


## Nom raccourci avec « … » s'il dépasse la largeur disponible (mis en cache).
func _fit(font: Font, text: String, width: float) -> String:
	var key := "%s|%d" % [text, int(width)]
	if key == _fit_key:
		return _fit_text
	_fit_key = key
	_fit_text = text
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x > width:
		var n := text.length()
		while n > 1 and font.get_string_size(text.left(n) + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE).x > width:
			n -= 1
		_fit_text = text.left(n).strip_edges() + "…"
	return _fit_text


func _set_hovered(on: bool) -> void:
	_hovered = on
	hover_changed.emit(species_id, on)
	queue_redraw()
