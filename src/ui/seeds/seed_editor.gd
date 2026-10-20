extends PanelContainer
## Réglages de l'outil sélectionné, au-dessus de la barre d'outils (Layout.TOOL_EDITOR) :
## description, indice de conditions (oxygène, ozone), rayon, état de la recharge, et selon l'outil :
## rôle du germe d'animal, petit éditeur de traits de la créature façonnée, espèce visée par un pouvoir.
## N'écrit que dans ToolState (set_param) ; la simulation tranche au moment de semer.

const SeedCatalog := preload("res://src/ui/seeds/seed_catalog.gd")
const Powers := preload("res://src/map/divine_powers.gd")
const PlanetMath := preload("res://src/ui/stats/planet_math.gd")
const Cooldowns := preload("res://src/ui/tools/cooldowns.gd")

const STATE_COLORS := {ok = Color(0.55, 0.95, 0.55), risky = Color(1.0, 0.65, 0.35), unknown = Color(0.7, 0.72, 0.82)}

var tool_state: Node
## () -> String : nom de l'espèce visée par les pouvoirs (fourni par le HUD).
var target_name: Callable = func() -> String: return "espèce dominante"

var _title: Label
var _hint: Label
var _conditions: Label
var _radius: Label
var _status: Label
var _roles_row: HBoxContainer
var _role_buttons := {}
var _shaped_grid: GridContainer
var _size_slider: HSlider
var _intel_slider: HSlider
var _diet: OptionButton
var _habitat: OptionButton
var _covering: OptionButton
var _color: ColorPickerButton
var _syncing := false
var _cond_timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 17)
	_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	head.add_child(_title)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(0.75, 0.77, 0.86))
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.clip_text = true
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_hint)
	var minus := _small_button(" − ", "Réduire le rayon ( [ )")
	minus.pressed.connect(_step_radius.bind(-1))
	head.add_child(minus)
	_radius = Label.new()
	_radius.add_theme_font_size_override("font_size", 14)
	_radius.custom_minimum_size.x = 70
	_radius.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_radius)
	var plus := _small_button(" + ", "Agrandir le rayon ( ] )")
	plus.pressed.connect(_step_radius.bind(1))
	head.add_child(plus)

	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 16)
	box.add_child(info)
	_conditions = Label.new()
	_conditions.add_theme_font_size_override("font_size", 14)
	_conditions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_conditions.clip_text = true
	_conditions.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(_conditions)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 14)
	info.add_child(_status)

	# Germe d'animal : rôle.
	_roles_row = HBoxContainer.new()
	_roles_row.add_theme_constant_override("separation", 6)
	box.add_child(_roles_row)
	var role_group := ButtonGroup.new()
	for role in SeedCatalog.ROLES:
		var b := Button.new()
		b.text = SeedCatalog.ROLE_LABELS[role]
		b.toggle_mode = true
		b.button_group = role_group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(120, 30)
		b.pressed.connect(_set_trait.bind("role", role))
		_roles_row.add_child(b)
		_role_buttons[role] = b

	# Créature façonnée : traits.
	_shaped_grid = GridContainer.new()
	_shaped_grid.columns = 6
	_shaped_grid.add_theme_constant_override("h_separation", 8)
	_shaped_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(_shaped_grid)
	_size_slider = _slider("Taille", "size")
	_diet = _options("Régime", "diet", SeedCatalog.DIETS, SeedCatalog.DIET_LABELS)
	_habitat = _options("Milieu", "habitat", SeedCatalog.HABITATS, SeedCatalog.HABITAT_LABELS)
	_intel_slider = _slider("Intelligence", "intelligence")
	_covering = _options("Couverture", "covering", SeedCatalog.COVERINGS, SeedCatalog.COVERING_LABELS)
	_shaped_grid.add_child(_label("Couleur"))
	_color = ColorPickerButton.new()
	_color.custom_minimum_size = Vector2(120, 28)
	_color.edit_alpha = false
	_color.focus_mode = Control.FOCUS_NONE
	_color.color_changed.connect(func(c: Color) -> void: _set_trait("color", c))
	_shaped_grid.add_child(_color)

	if tool_state:
		tool_state.tool_changed.connect(func(_t: Dictionary) -> void: _sync())
	_sync()


func _process(delta: float) -> void:
	if not visible or tool_state == null:
		return
	var tool: Dictionary = tool_state.selected_tool()
	var rem: float = tool_state.remaining(tool)
	_status.text = "Recharge : %s" % Cooldowns.format_remaining(rem) if rem > 0.0 \
			else "Prêt : cliquez sur le monde pour l'utiliser"
	_status.add_theme_color_override("font_color", Color(1.0, 0.7, 0.45) if rem > 0.0 else Color(0.6, 0.95, 0.6))
	_cond_timer += delta
	if _cond_timer >= 1.0:
		_cond_timer = 0.0
		_update_conditions(tool)


## Remet l'éditeur en phase avec l'outil sélectionné (visible seulement s'il y en a un).
func _sync() -> void:
	if tool_state == null:
		visible = false
		return
	var tool: Dictionary = tool_state.selected_tool()
	visible = not tool.is_empty()
	if tool.is_empty():
		return
	_syncing = true
	var is_seed: bool = tool.kind == "seed"
	var info := SeedCatalog.get_seed(tool.id) if is_seed else Powers.get_power(tool.id)
	_title.text = str(info.get("label", tool.id))
	_hint.text = str(info.get("hint", ""))
	_radius.text = "rayon %d" % int(tool.params.get("radius", 0))
	var traits: Dictionary = tool.params.get("traits", {})
	_roles_row.visible = is_seed and tool.id == "animal_germ"
	if _roles_row.visible:
		var role := str(traits.get("role", "grazer"))
		for r in _role_buttons:
			_role_buttons[r].set_pressed_no_signal(r == role)
	_shaped_grid.visible = is_seed and tool.id == "shaped"
	if _shaped_grid.visible:
		_size_slider.set_value_no_signal(float(traits.get("size", 0.3)))
		_intel_slider.set_value_no_signal(float(traits.get("intelligence", 0.2)))
		_select(_diet, SeedCatalog.DIETS, str(traits.get("diet", "herbivore")))
		_select(_habitat, SeedCatalog.HABITATS, str(traits.get("habitat", "land")))
		_select(_covering, SeedCatalog.COVERINGS, str(traits.get("covering", "scales")))
		if traits.get("color") is Color:
			_color.color = traits.color
	_update_conditions(tool)
	_syncing = false
	# Le panneau grandit vers le haut depuis le bas de sa zone.
	offset_top = offset_bottom - get_combined_minimum_size().y


func _update_conditions(tool: Dictionary) -> void:
	if tool.is_empty():
		return
	if tool.kind == "seed":
		var stats := PlanetMath.read_stats(GameState.sim, GameState.parcel) if GameState else {}
		var c := SeedCatalog.conditions(str(tool.id), stats)
		_conditions.text = str(c.text)
		_conditions.add_theme_color_override("font_color", STATE_COLORS.get(c.state, Color.WHITE))
		_conditions.tooltip_text = "Un indice seulement : la simulation décide si la vie prend."
	else:
		var p := Powers.get_power(str(tool.id))
		_conditions.text = "Vise : %s" % target_name.call() if p.get("needs_species", false) \
				else "Agit sur la zone choisie."
		_conditions.add_theme_color_override("font_color", STATE_COLORS.unknown)
		_conditions.tooltip_text = ""


func _set_trait(key: String, value: Variant) -> void:
	if _syncing or tool_state == null:
		return
	var tool: Dictionary = tool_state.selected_tool()
	if tool.is_empty() or tool.kind != "seed":
		return
	var traits: Dictionary = (tool.params.get("traits", {}) as Dictionary).duplicate()
	traits[key] = value
	tool_state.set_param("traits", traits)


func _step_radius(step: int) -> void:
	if tool_state and tool_state.has_tool():
		tool_state.set_param("radius", int(tool_state.selected_tool().params.get("radius", 4)) + step)


func _slider(label: String, key: String) -> HSlider:
	_shaped_grid.add_child(_label(label))
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.custom_minimum_size = Vector2(120, 24)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(func(v: float) -> void: _set_trait(key, v))
	_shaped_grid.add_child(s)
	return s


func _options(label: String, key: String, ids: Array, labels: Dictionary) -> OptionButton:
	_shaped_grid.add_child(_label(label))
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.custom_minimum_size = Vector2(120, 28)
	for id in ids:
		o.add_item(str(labels.get(id, id)))
	o.item_selected.connect(func(i: int) -> void: _set_trait(key, ids[i]))
	_shaped_grid.add_child(o)
	return o


func _select(o: OptionButton, ids: Array, id: String) -> void:
	var i := ids.find(id)
	if i >= 0:
		o.select(i)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.75, 0.77, 0.86))
	return l


func _small_button(text: String, tooltip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tooltip
	return b
