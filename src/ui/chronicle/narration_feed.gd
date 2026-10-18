extends CanvasLayer
## Fil de narration : l'histoire racontée en continu par le Narrateur (Narrator.narration_ready).
## Le plus récent en bas ; les dernières lignes restent visibles puis s'estompent (FeedMath).
## Au survol (ou PageUp / PageDown) le fond apparaît et tout l'historique se relit à la molette.
##
## Placé dans la colonne droite, entre le panneau « Espèces vivantes » du HUD (y < 540) et ses
## infos de région (y > 860) : ne masque ni le centre de la parcelle ni les statistiques (à gauche).
## Les clics traversent le fil (MOUSE_FILTER_PASS) : seule la molette lui est réservée.

const FeedMath := preload("res://src/ui/chronicle/feed_math.gd")
const StatsMath := preload("res://src/ui/stats/stats_math.gd")

const PANEL_LEFT := -312.0
const PANEL_RIGHT := -12.0
const PANEL_TOP := 552.0
const PANEL_BOTTOM := 848.0
const TEXT_SIZE := 18
const YEAR_SIZE := 13
## Durée (s) pendant laquelle PageUp / PageDown laissent l'historique affiché.
const PEEK_DURATION := 4.0

var _panel: PanelContainer
var _header: HBoxContainer
var _scroll: ScrollContainer
var _lines: VBoxContainer
var _latest_button: Button
var _following := true
var _scroll_frames := 0
var _hovered := false
var _peek := 0.0


func _ready() -> void:
	layer = 9
	_build()
	var narrator := get_node_or_null("/root/Narrator")
	if narrator and narrator.has_signal("narration_ready"):
		narrator.connect("narration_ready", add_line)


## Ajoute une ligne au fil (année courante en préfixe). Ignore les textes vides.
func add_line(text: String) -> void:
	var t := FeedMath.clean_line(text)
	if t == "":
		return
	var entry := RichTextLabel.new()
	entry.bbcode_enabled = true
	entry.fit_content = true
	entry.scroll_active = false
	entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.mouse_filter = Control.MOUSE_FILTER_PASS
	entry.add_theme_font_size_override("normal_font_size", TEXT_SIZE)
	entry.add_theme_color_override("default_color", Color(0.93, 0.92, 0.97))
	var year := ""
	if GameState and GameState.sim != null:
		year = "[color=#8a93a8][font_size=%d]%s[/font_size][/color]  " % [YEAR_SIZE,
			StatsMath.format_axis_year(GameState.sim.year)]
	entry.text = year + t.replace("[", "[lb]")
	entry.set_meta("born", _now())
	entry.modulate.a = 0.0
	_lines.add_child(entry)
	for i in FeedMath.overflow(_lines.get_child_count()):
		var old := _lines.get_child(0)
		_lines.remove_child(old)
		old.queue_free()
	if _following:
		_scroll_frames = 2


func _build() -> void:
	var root := Control.new()
	root.name = "FeedRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.name = "NarrationFeed"
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = PANEL_LEFT
	_panel.offset_right = PANEL_RIGHT
	_panel.offset_top = PANEL_TOP
	_panel.offset_bottom = PANEL_BOTTOM
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.09, 0.82)
	style.border_color = Color(0.85, 0.7, 0.35, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.self_modulate.a = 0.0  # fond invisible hors survol ; le texte, lui, reste
	root.add_child(_panel)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	_panel.add_child(box)
	_header = HBoxContainer.new()
	_header.modulate.a = 0.0
	box.add_child(_header)
	var title := Label.new()
	title.text = "Récit"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	_header.add_child(title)
	_latest_button = Button.new()
	_latest_button.text = "Récent ↓"
	_latest_button.focus_mode = Control.FOCUS_NONE
	_latest_button.flat = true
	_latest_button.add_theme_font_size_override("font_size", 14)
	_latest_button.visible = false
	_latest_button.pressed.connect(_jump_to_latest)
	_header.add_child(_latest_button)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_scroll)
	_lines = VBoxContainer.new()
	_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lines.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lines.alignment = BoxContainer.ALIGNMENT_END  # peu de lignes : collées en bas
	_lines.add_theme_constant_override("separation", 6)
	_lines.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_lines)
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)


func _process(delta: float) -> void:
	_peek = maxf(0.0, _peek - delta)
	var mouse_over := _panel.get_global_rect().has_point(_panel.get_global_mouse_position())
	var hovered := (mouse_over or _peek > 0.0) and _lines.get_child_count() > 0
	if hovered != _hovered:
		_hovered = hovered
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if hovered \
				else ScrollContainer.SCROLL_MODE_SHOW_NEVER
		if not hovered:
			_jump_to_latest()  # hors survol, on revient toujours aux lignes récentes
	var bg := 1.0 if _hovered else 0.0
	_panel.self_modulate.a = move_toward(_panel.self_modulate.a, bg, delta * 5.0)
	_header.modulate.a = _panel.self_modulate.a
	if _scroll_frames > 0:
		_scroll_frames -= 1
		var bar := _scroll.get_v_scroll_bar()
		bar.value = bar.max_value
	# Estompage, de la plus récente (rang 0) à la plus ancienne.
	var now := _now()
	var count := _lines.get_child_count()
	for rank in count:
		var entry := _lines.get_child(count - 1 - rank) as Control
		var target := FeedMath.line_alpha(now - float(entry.get_meta("born", now)), rank, _hovered)
		# Apparition en fondu rapide, estompage doux.
		var speed := 4.0 if target > entry.modulate.a else 1.5
		entry.modulate.a = move_toward(entry.modulate.a, target, delta * speed)
		if not _hovered and rank >= FeedMath.VISIBLE_LINES and entry.modulate.a <= 0.0:
			break  # les plus anciennes sont déjà invisibles


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	var bar := _scroll.get_v_scroll_bar()
	match k.physical_keycode:
		KEY_PAGEUP:
			bar.value -= _scroll.size.y * 0.8
		KEY_PAGEDOWN:
			bar.value += _scroll.size.y * 0.8
		_:
			return
	_peek = PEEK_DURATION
	get_viewport().set_input_as_handled()


func _on_scrolled(value: float) -> void:
	var bar := _scroll.get_v_scroll_bar()
	_following = FeedMath.is_at_bottom(value, bar.max_value, bar.page)
	_latest_button.visible = not _following


func _jump_to_latest() -> void:
	_following = true
	_latest_button.visible = false
	_scroll_frames = 2


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
