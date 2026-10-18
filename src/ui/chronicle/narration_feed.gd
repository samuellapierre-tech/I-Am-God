extends CanvasLayer
## Fil de narration : l'histoire racontée en continu par le Narrateur (Narrator.narration_ready).
## Le plus récent en bas ; les dernières lignes restent visibles puis s'estompent (FeedMath).
## Au survol (ou PageUp / PageDown) le fond apparaît et tout l'historique se relit à la molette.
## En tête : le nom du narrateur (DilemmaMath.speaker_name : NARRATOR_NAME de ai_config.gd, sinon
## le nom par défaut), visible dès qu'il a parlé.
##
## Placé dans le bas de la colonne droite, sous le tiroir « Espèces vivantes » du HUD (y < 540) :
## ne masque ni le centre de la parcelle ni les statistiques (à gauche).
## Hors survol, une ligne que le défilement rogne par le haut est masquée : le texte ne passe jamais
## sous l'en-tête.
## Les clics traversent le fil (MOUSE_FILTER_PASS) : seule la molette lui est réservée.

const FeedMath := preload("res://src/ui/chronicle/feed_math.gd")
const StatsMath := preload("res://src/ui/stats/stats_math.gd")
const DilemmaMath := preload("res://src/ui/dilemma/dilemma_math.gd")

const Layout := preload("res://src/ui/layout.gd")
const TEXT_SIZE := 18
const YEAR_SIZE := 13
## Durée (s) pendant laquelle PageUp / PageDown laissent l'historique affiché.
const PEEK_DURATION := 4.0

var _panel: PanelContainer
var _header: HBoxContainer
var _header_placed := false
var _speaker_label: Label
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
	Layout.place(_panel, Layout.FEED, Vector2(1, 1))  # ancré au coin bas-droit
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
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	# L'en-tête flotte hors du conteneur : au repos il se pose juste au-dessus des lignes visibles
	# (collées en bas), au survol il remonte en haut du panneau. Une cale lui réserve la place.
	var header_slot := Control.new()
	header_slot.custom_minimum_size.y = 26
	header_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(header_slot)
	_header = HBoxContainer.new()
	_header.modulate.a = 0.0
	root.add_child(_header)
	_speaker_label = Label.new()
	_speaker_label.text = DilemmaMath.speaker_name(null, DilemmaMath.load_config_constants())
	_speaker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speaker_label.add_theme_font_size_override("font_size", 17)
	_speaker_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	_speaker_label.tooltip_text = "Le narrateur, maître du jeu"
	_speaker_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_header.add_child(_speaker_label)
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
	# Le nom du narrateur reste lisible dès qu'il a parlé ; le reste de l'en-tête suit le fond.
	var has_lines := _lines.get_child_count() > 0
	_header.modulate.a = maxf(_panel.self_modulate.a, 0.75 if has_lines else 0.0)
	_latest_button.visible = _hovered and not _following
	if _scroll_frames > 0:
		_scroll_frames -= 1
		var bar := _scroll.get_v_scroll_bar()
		bar.value = bar.max_value
	# Estompage, de la plus récente (rang 0) à la plus ancienne.
	var first_line_top := INF
	var now := _now()
	var count := _lines.get_child_count()
	for rank in count:
		var entry := _lines.get_child(count - 1 - rank) as Control
		var target := FeedMath.line_alpha(now - float(entry.get_meta("born", now)), rank, _hovered)
		if not _hovered and FeedMath.is_clipped(entry.position.y, _scroll.scroll_vertical):
			entry.modulate.a = 0.0  # rognée par le haut : jamais à moitié sous l'en-tête
			continue
		# Apparition en fondu rapide, estompage doux.
		var speed := 4.0 if target > entry.modulate.a else 1.5
		entry.modulate.a = move_toward(entry.modulate.a, target, delta * speed)
		if entry.modulate.a > 0.02:
			first_line_top = minf(first_line_top, entry.global_position.y)
		if not _hovered and rank >= FeedMath.VISIBLE_LINES and entry.modulate.a <= 0.0:
			break  # les plus anciennes sont déjà invisibles
	_place_header(delta, first_line_top)


func _place_header(delta: float, first_line_top: float) -> void:
	var inner := _panel.get_global_rect().grow(-10.0)
	_header.size = Vector2(inner.size.x, _header.get_combined_minimum_size().y)
	_header.global_position.x = inner.position.x
	var y := FeedMath.header_y(inner.position.y, first_line_top, _header.size.y, _hovered)
	if not _header_placed:
		_header_placed = true
		_header.global_position.y = y
	else:
		_header.global_position.y = move_toward(_header.global_position.y, y, delta * 900.0)


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


func _jump_to_latest() -> void:
	_following = true
	_scroll_frames = 2


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
