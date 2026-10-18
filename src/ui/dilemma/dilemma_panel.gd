extends CanvasLayer
## Panneau de dilemme : le Narrateur, maître du jeu, pose un choix au joueur.
## Écoute Narrator.dilemma_ready(dilemma) et répond par Narrator.resolve_dilemma(id, index).
## Panneau solennel au centre-bas (au-dessus de la barre des pouvoirs du HUD) : titre, texte écrit
## progressivement, signature du narrateur (DilemmaMath.speaker_name),
## 2 à 4 options (libellé + indication), barre de temps restant.
## Pendant l'affichage, le temps du monde ralentit fortement (TimeDilation) puis reprend sa vitesse.
## Raccourcis : 1 à 4 (rangée du haut ou pavé numérique), clic, ou manette (croix + A).
## Si le temps s'écoule : option `default_index` du dilemme, sinon -1 (« Dieu se tait »).
## Les dilemmes reçus pendant l'affichage attendent leur tour.

## Émis après la réponse envoyée au Narrateur (index -1 si le temps s'est écoulé sans défaut).
signal dilemma_resolved(dilemma_id: Variant, index: int)

const DilemmaMath := preload("res://src/ui/dilemma/dilemma_math.gd")
const TimeDilation := preload("res://src/ui/dilemma/time_dilation.gd")
const TimeBar := preload("res://src/ui/dilemma/time_bar.gd")

const Layout := preload("res://src/ui/layout.gd")

const PANEL_WIDTH := Layout.DILEMMA.size.x
## Bas du panneau : au-dessus de la barre des pouvoirs et de son indication (Layout.DILEMMA).
const BOTTOM_MARGIN := Layout.REF_SIZE.y - (Layout.DILEMMA.position.y + Layout.DILEMMA.size.y)
const GOLD := Color(1.0, 0.85, 0.5)
const OUTRO := 0.7

var _panel: PanelContainer
var _title: Label
var _text: RichTextLabel
var _signature: Label
var _options_box: HBoxContainer
var _buttons: Array[Button] = []
var _time_bar: TimeBar
var _time_label: Label

var _queue: Array[Dictionary] = []
## Dilemme affiché (normalisé), vide sinon.
var _current: Dictionary = {}
var _elapsed := 0.0
var _remaining := 0.0
var _chosen := -2  # -2 : pas encore tranché
var _outro := 0.0
var _dilation := TimeDilation.new()
var _tween: Tween
## Constantes de ai_config.gd (NARRATOR_NAME), lues une fois.
var _config := {}


func _ready() -> void:
	layer = 12  # au-dessus du HUD (10) et des statistiques (9)
	# Après le HUD, qui réécrit la vitesse du temps à chaque image : on ralentit sa valeur.
	process_priority = 100
	_config = DilemmaMath.load_config_constants()
	_build()
	var narrator := get_node_or_null("/root/Narrator")
	if narrator and narrator.has_signal("dilemma_ready"):
		narrator.connect("dilemma_ready", show_dilemma)
	elif narrator:
		print_verbose("DilemmaPanel : Narrator.dilemma_ready absent (branche narrateur non fusionnée), panneau inactif.")


## Affiche un dilemme (ou le met en file d'attente). Renvoie false s'il est invalide.
func show_dilemma(raw: Variant) -> bool:
	var d := DilemmaMath.normalize(raw)
	var err := DilemmaMath.validate(d)
	if err != "":
		push_warning("DilemmaPanel : dilemme ignoré (%s)." % err)
		return false
	if _current.is_empty():
		_open(d)
	else:
		_queue.append(d)
	return true


func is_open() -> bool:
	return not _current.is_empty()


# --- Construction ---

func _build() -> void:
	var root := Control.new()
	root.name = "DilemmaRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	_panel = PanelContainer.new()
	_panel.name = "DilemmaPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -PANEL_WIDTH * 0.5
	_panel.offset_right = PANEL_WIDTH * 0.5
	_panel.offset_top = -BOTTOM_MARGIN
	_panel.offset_bottom = -BOTTOM_MARGIN
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN  # grandit vers le haut
	_panel.visible = false
	root.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", GOLD)
	box.add_child(_title)
	box.add_child(HSeparator.new())
	_text = RichTextLabel.new()
	_text.bbcode_enabled = false
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(PANEL_WIDTH - 40.0, 0)
	_text.add_theme_font_size_override("normal_font_size", 20)
	_text.add_theme_color_override("default_color", Color(0.92, 0.91, 0.96))
	_text.mouse_filter = Control.MOUSE_FILTER_STOP
	_text.tooltip_text = ""
	_text.gui_input.connect(_on_text_input)
	box.add_child(_text)
	_signature = Label.new()
	_signature.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_signature.add_theme_font_size_override("font_size", 18)
	_signature.add_theme_color_override("font_color", GOLD.darkened(0.1))
	box.add_child(_signature)
	_options_box = HBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 10)
	box.add_child(_options_box)

	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 10)
	box.add_child(time_row)
	_time_bar = TimeBar.new()
	_time_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	time_row.add_child(_time_bar)
	_time_label = Label.new()
	_time_label.custom_minimum_size.x = 80
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.add_theme_font_size_override("font_size", 15)
	_time_label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.82))
	time_row.add_child(_time_label)


func _make_option(index: int, option: Dictionary) -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	var b := Button.new()
	b.text = "%d   %s" % [index + 1, option.label]
	b.custom_minimum_size = Vector2(0, 52)
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = "%s\n%s" % [option.label, option.hint] if option.hint != "" else String(option.label)
	b.pressed.connect(_choose.bind(index))
	column.add_child(b)
	_buttons.append(b)
	if option.hint != "":
		var hint := Label.new()
		hint.text = option.hint
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 14)
		hint.add_theme_color_override("font_color", Color(0.68, 0.7, 0.8))
		column.add_child(hint)
	return column


## Même famille visuelle que hud.gd, en plus solennel : bordure d'or pleine, fond plus sombre.
func _make_theme() -> Theme:
	var t := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.03, 0.03, 0.06, 0.94)
	panel.border_color = Color(0.9, 0.74, 0.38, 0.8)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(10)
	panel.set_content_margin_all(20)
	panel.shadow_color = Color(0, 0, 0, 0.55)
	panel.shadow_size = 18
	t.set_stylebox("panel", "PanelContainer", panel)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.13, 0.2, 0.95)
	normal.border_color = Color(0.85, 0.7, 0.35, 0.4)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(8)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.22, 0.2, 0.3, 0.98)
	hover.border_color = Color(1.0, 0.82, 0.4, 0.9)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.3, 0.24, 0.1, 0.98)
	pressed.border_color = Color(1.0, 0.8, 0.35)
	pressed.set_border_width_all(2)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", hover)
	t.set_stylebox("disabled", "Button", normal)
	t.set_color("font_color", "Button", Color(0.92, 0.92, 0.97))
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_focus_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.56))
	t.set_font_size("font_size", "Button", 19)
	t.set_color("font_color", "Label", Color(0.9, 0.9, 0.95))
	var sep := StyleBoxLine.new()
	sep.color = Color(0.9, 0.74, 0.38, 0.35)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	return t


# --- Cycle de vie ---

func _open(d: Dictionary) -> void:
	_current = d
	_elapsed = 0.0
	_remaining = float(d.timeout_s)
	_chosen = -2
	_outro = 0.0
	_title.text = d.title
	_text.text = d.text
	_text.visible_characters = 0
	_signature.text = DilemmaMath.signature(DilemmaMath.speaker_name(d.speaker, _config))
	_signature.modulate.a = 0.0
	for c in _options_box.get_children():
		_options_box.remove_child(c)
		c.queue_free()
	_buttons.clear()
	var options: Array = d.options
	for i in options.size():
		_options_box.add_child(_make_option(i, options[i]))
	_time_bar.ratio = 1.0
	_time_label.text = DilemmaMath.format_remaining(_remaining)
	_panel.visible = true
	_panel.reset_size()
	_panel.modulate.a = 0.0
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.35)
	if GameState:
		GameState.years_per_second = _dilation.begin(GameState.years_per_second)


func _close() -> void:
	if GameState:
		GameState.years_per_second = _dilation.end(GameState.years_per_second)
	_current = {}
	_panel.visible = false
	for b in _buttons:
		b.release_focus()
	if not _queue.is_empty():
		_open(_queue.pop_front())


func _process(delta: float) -> void:
	if _current.is_empty():
		return
	if _dilation.active and GameState:
		GameState.years_per_second = _dilation.step(GameState.years_per_second)
	_elapsed += delta
	if _chosen != -2:
		_outro += delta
		_panel.modulate.a = clampf(1.0 - (_outro - OUTRO * 0.5) / (OUTRO * 0.5), 0.0, 1.0)
		if _outro >= OUTRO:
			_close()
		return
	var total_chars := _text.get_total_character_count()
	_text.visible_characters = DilemmaMath.visible_chars(_elapsed, total_chars)
	# La signature apparaît une fois le texte écrit.
	if _text.visible_characters >= total_chars:
		_signature.modulate.a = minf(1.0, _signature.modulate.a + delta * 3.0)
	var paused: bool = GameState.paused if GameState else false
	_remaining = DilemmaMath.tick(_remaining, delta, paused)
	_time_bar.ratio = DilemmaMath.time_ratio(_remaining, float(_current.timeout_s))
	_time_label.text = "En pause" if paused else DilemmaMath.format_remaining(_remaining)
	if _remaining <= 0.0:
		_choose(int(_current.default_index), true)


func _input(event: InputEvent) -> void:
	if _current.is_empty() or _chosen != -2:
		return
	# Manette : le focus n'est donné aux boutons qu'à la première action à la manette, pour qu'un
	# Espace (pause du HUD) ne valide jamais une option par accident.
	if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and _focused_button() < 0:
		if not _buttons.is_empty() and (event is InputEventJoypadButton or absf((event as InputEventJoypadMotion).axis_value) > 0.5):
			_buttons[0].grab_focus()
			get_viewport().set_input_as_handled()
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var index := DilemmaMath.key_to_option(k.physical_keycode, _buttons.size())
	if index >= 0:
		# Toujours consommer 1-4 pendant un dilemme : sinon le HUD sélectionnerait un pouvoir.
		get_viewport().set_input_as_handled()
		_choose(index)


func _on_text_input(event: InputEvent) -> void:
	# Un clic sur le texte l'affiche en entier.
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_elapsed = maxf(_elapsed, float(_text.get_total_character_count()) / DilemmaMath.CHARS_PER_SECOND)


func _focused_button() -> int:
	for i in _buttons.size():
		if _buttons[i].has_focus():
			return i
	return -1


func _choose(index: int, timed_out: bool = false) -> void:
	if _current.is_empty() or _chosen != -2:
		return
	if not timed_out and not DilemmaMath.can_choose(_elapsed):
		return
	_chosen = index
	_text.visible_characters = -1
	_signature.modulate.a = 1.0
	# L'option retenue reste allumée (focus doré), les autres s'éteignent.
	for i in _buttons.size():
		_buttons[i].disabled = i != index
	if index >= 0 and index < _buttons.size():
		_buttons[index].grab_focus()
	var narrator := get_node_or_null("/root/Narrator")
	if narrator and narrator.has_method("resolve_dilemma"):
		narrator.call("resolve_dilemma", _current.id, index)
	dilemma_resolved.emit(_current.id, index)
	if timed_out:
		_time_label.text = "Temps écoulé"
