extends CanvasLayer
## Interface divine : année et ère, vitesse du temps, couches de carte, barre de pouvoirs,
## panneau des espèces (choix de la cible), chronique des événements et boîte du narrateur.
## Construite en code pour rester lisible et sans dépendance à des ressources externes.
## L'état joueur (pouvoir, rayon, couche, cible) vit dans la carte : voir bind_map().

const MapMath := preload("res://src/map/map_math.gd")
const Powers := preload("res://src/map/divine_powers.gd")

## Multiplicateurs de vitesse x1..x5 (appliqués à MapMath.base_years_per_second()).
const SPEEDS := [1.0, 2.0, 3.0, 4.0, 5.0]
const MAX_LOG_LINES := 200
const NARRATION_DURATION := 14.0

## Le HUD demande une narration au Narrateur lors des grands moments (changement d'ère, action divine).
## Désactivé par défaut : le Narrateur écoute déjà GameState et raconte ces moments lui-même.
@export var request_narration := false

var map: Node = null
## 0 = pause, 1..5 = vitesse.
var speed_level := 1

var _year_label: Label
var _era_label: Label
var _rate_label: Label
var _speed_buttons: Array[Button] = []
var _layer_buttons: Array[Button] = []
var _power_buttons: Array[Button] = []
var _radius_label: Label
var _target_label: Label
var _species_list: ItemList
var _species_ids: Array[int] = []
var _species_signature := ""
var _species_timer := 0.0
var _log: RichTextLabel
var _log_lines := 0
var _narration_panel: PanelContainer
var _narration_label: RichTextLabel
var _narration_timer := 0.0
var _info_label: Label
var _swatches := {}
var _syncing := false


func _ready() -> void:
	layer = 10
	_build()
	GameState.event_occurred.connect(_on_event)
	GameState.era_changed.connect(_on_era_changed)
	GameState.divine_action_applied.connect(_on_divine_action)
	Narrator.narration_ready.connect(_on_narration)
	if GameState.sim != null:
		_era_label.text = GameState.sim.current_era()
	_set_speed(1)
	_refresh_species(true)
	_add_log_line("[color=#e8c66a]Que la lumière soit.[/color] Vous veillez sur un monde jeune.")


## Relie le HUD à la carte (source de vérité du pouvoir, du rayon, de la couche et de la cible).
func bind_map(world_map: Node) -> void:
	map = world_map
	map.state_changed.connect(_sync_from_map)
	map.region_hovered.connect(_on_region_hovered)
	_sync_from_map()


func _process(delta: float) -> void:
	var sim = GameState.sim
	if sim == null:
		return
	_year_label.text = MapMath.format_year(sim.year)
	if speed_level > 0:
		GameState.years_per_second = MapMath.base_years_per_second(sim.ideal_step_years()) * SPEEDS[speed_level - 1]
	_rate_label.text = "%s ans/s" % MapMath.group_thousands(int(GameState.years_per_second)) \
			if speed_level > 0 else "Temps suspendu"
	_species_timer += delta
	if _species_timer >= 1.0:
		_species_timer = 0.0
		_refresh_species(false)
	if _narration_timer > 0.0:
		_narration_timer -= delta
		_narration_panel.modulate.a = clampf(_narration_timer / 1.5, 0.0, 1.0)
		_narration_panel.visible = _narration_timer > 0.0


# --- Raccourcis clavier ---

func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var handled := true
	var key := k.physical_keycode
	match key:
		KEY_SPACE:
			_set_speed(0 if speed_level > 0 else 1)
		KEY_EQUAL, KEY_KP_ADD:
			_set_speed(clampi(speed_level + 1, 1, SPEEDS.size()))
		KEY_MINUS, KEY_KP_SUBTRACT:
			_set_speed(maxi(speed_level - 1, 1))
		KEY_F1, KEY_F2, KEY_F3, KEY_F4:
			if map: map.set_layer(key - KEY_F1)
		KEY_TAB:
			if map: map.set_layer((map.layer + 1) % map.LAYERS.size())
		KEY_BRACKETLEFT:
			if map: map.set_radius(map.radius - 1)
		KEY_BRACKETRIGHT:
			if map: map.set_radius(map.radius + 1)
		KEY_ESCAPE:
			if map: map.set_power("")
		_:
			handled = false
			for p in Powers.LIST:
				if key == p.key and map:
					map.set_power("" if map.power == p.id else p.id)
					handled = true
	if handled:
		get_viewport().set_input_as_handled()


# --- Construction de l'interface ---

func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	# Barre du haut : année, ère, couches, vitesse.
	var top := _panel(root)
	_place(top, Vector4(0, 0, 1, 0), Vector4(12, 12, -12, 88))
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 18)
	top.add_child(top_row)

	var time_box := VBoxContainer.new()
	time_box.add_theme_constant_override("separation", -4)
	top_row.add_child(time_box)
	_year_label = Label.new()
	_year_label.add_theme_font_size_override("font_size", 32)
	_year_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_year_label.custom_minimum_size.x = 320
	time_box.add_child(_year_label)
	var era_row := HBoxContainer.new()
	time_box.add_child(era_row)
	_era_label = Label.new()
	_era_label.add_theme_font_size_override("font_size", 18)
	era_row.add_child(_era_label)
	_rate_label = Label.new()
	_rate_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	_rate_label.add_theme_font_size_override("font_size", 14)
	era_row.add_child(_rate_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(spacer)

	var layers_box := HBoxContainer.new()
	top_row.add_child(layers_box)
	var layer_group := ButtonGroup.new()
	var layer_names := ["Biomes", "Espèces", "Technologie", "Température"]
	for i in layer_names.size():
		var b := _toggle_button(layer_names[i], layer_group)
		b.tooltip_text = "Couche de carte (F%d, Tab pour alterner)" % (i + 1)
		b.pressed.connect(_on_layer_pressed.bind(i))
		layers_box.add_child(b)
		_layer_buttons.append(b)

	top_row.add_child(VSeparator.new())

	var speed_box := HBoxContainer.new()
	top_row.add_child(speed_box)
	var speed_group := ButtonGroup.new()
	for i in SPEEDS.size() + 1:
		var b := _toggle_button("Pause" if i == 0 else "x%d" % i, speed_group)
		b.tooltip_text = "Espace : pause / reprise — +/- : vitesse"
		b.pressed.connect(_set_speed.bind(i))
		speed_box.add_child(b)
		_speed_buttons.append(b)

	# Boîte du narrateur, sous la barre du haut.
	_narration_panel = _panel(root)
	_place(_narration_panel, Vector4(0.5, 0, 0.5, 0), Vector4(-380, 100, 380, 140))
	_narration_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_narration_panel.visible = false
	_narration_label = RichTextLabel.new()
	_narration_label.bbcode_enabled = true
	_narration_label.fit_content = true
	_narration_label.scroll_active = false
	_narration_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_narration_label.add_theme_font_size_override("italics_font_size", 19)
	_narration_label.add_theme_font_size_override("normal_font_size", 19)
	_narration_panel.add_child(_narration_label)

	# Panneau des espèces (droite).
	var species_panel := _panel(root)
	_place(species_panel, Vector4(1, 0, 1, 0), Vector4(-312, 100, -12, 540))
	var sp_box := VBoxContainer.new()
	species_panel.add_child(sp_box)
	sp_box.add_child(_title("Espèces vivantes"))
	_species_list = ItemList.new()
	_species_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_species_list.custom_minimum_size = Vector2(0, 300)
	_species_list.focus_mode = Control.FOCUS_NONE
	_species_list.item_selected.connect(_on_species_selected)
	sp_box.add_child(_species_list)
	_target_label = Label.new()
	_target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_target_label.add_theme_font_size_override("font_size", 13)
	sp_box.add_child(_target_label)
	var clear := Button.new()
	clear.text = "Cible : espèce dominante locale"
	clear.focus_mode = Control.FOCUS_NONE
	clear.tooltip_text = "Sans cible, les pouvoirs visent l'espèce dominante de la région cliquée."
	clear.pressed.connect(_on_clear_target)
	sp_box.add_child(clear)

	# Chronique (bas gauche).
	var log_panel := _panel(root)
	_place(log_panel, Vector4(0, 1, 0, 1), Vector4(12, -420, 492, -140))
	var log_box := VBoxContainer.new()
	log_panel.add_child(log_box)
	log_box.add_child(_title("Chronique"))
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 14)
	_log.meta_clicked.connect(_on_log_meta)
	log_box.add_child(_log)

	# Barre des pouvoirs (bas).
	var bar := _panel(root)
	_place(bar, Vector4(0.5, 1, 0.5, 1), Vector4(-540, -128, 540, -12))
	var bar_box := VBoxContainer.new()
	bar.add_child(bar_box)
	var power_row := HBoxContainer.new()
	power_row.add_theme_constant_override("separation", 6)
	bar_box.add_child(power_row)
	var power_group := ButtonGroup.new()
	power_group.allow_unpress = true
	for p in Powers.LIST:
		var b := _toggle_button("%s\n%s" % [OS.get_keycode_string(p.key), p.label], power_group)
		b.custom_minimum_size = Vector2(108, 56)
		b.tooltip_text = "%s — %s" % [p.label, p.hint]
		b.add_theme_color_override("font_pressed_color", p.color)
		b.add_theme_color_override("font_hover_pressed_color", p.color.lightened(0.3))
		b.toggled.connect(_on_power_toggled.bind(p.id))
		power_row.add_child(b)
		_power_buttons.append(b)
	var radius_row := HBoxContainer.new()
	radius_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bar_box.add_child(radius_row)
	var minus := Button.new()
	minus.text = " − "
	minus.focus_mode = Control.FOCUS_NONE
	minus.pressed.connect(_step_radius.bind(-1))
	radius_row.add_child(minus)
	_radius_label = Label.new()
	_radius_label.custom_minimum_size.x = 420
	_radius_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	radius_row.add_child(_radius_label)
	var plus := Button.new()
	plus.text = " + "
	plus.focus_mode = Control.FOCUS_NONE
	plus.pressed.connect(_step_radius.bind(1))
	radius_row.add_child(plus)

	# Infos de la région survolée (bas droite).
	var info_panel := _panel(root)
	_place(info_panel, Vector4(1, 1, 1, 1), Vector4(-312, -220, -12, -140))
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 14)
	_info_label.custom_minimum_size.x = 288
	info_panel.add_child(_info_label)


func _make_theme() -> Theme:
	var t := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.04, 0.05, 0.09, 0.82)
	panel.border_color = Color(0.85, 0.7, 0.35, 0.35)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(8)
	panel.set_content_margin_all(10)
	t.set_stylebox("panel", "PanelContainer", panel)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.13, 0.2, 0.9)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(6)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.2, 0.21, 0.32, 0.95)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.3, 0.24, 0.1, 0.95)
	pressed.border_color = Color(1.0, 0.8, 0.35)
	pressed.set_border_width_all(2)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_color("font_color", "Label", Color(0.9, 0.9, 0.95))
	t.set_color("font_color", "Button", Color(0.88, 0.88, 0.95))
	t.set_font_size("font_size", "Button", 15)
	var list_bg := StyleBoxFlat.new()
	list_bg.bg_color = Color(0, 0, 0, 0.25)
	list_bg.set_corner_radius_all(4)
	t.set_stylebox("panel", "ItemList", list_bg)
	return t


## Ancres (gauche, haut, droite, bas) et marges en pixels.
func _place(c: Control, anchors: Vector4, offsets: Vector4) -> void:
	c.anchor_left = anchors.x
	c.anchor_top = anchors.y
	c.anchor_right = anchors.z
	c.anchor_bottom = anchors.w
	c.offset_left = offsets.x
	c.offset_top = offsets.y
	c.offset_right = offsets.z
	c.offset_bottom = offsets.w


func _panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(p)
	return p


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	return l


func _toggle_button(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	return b


func _swatch(color: Color) -> Texture2D:
	var key := color.to_html(false)
	if not _swatches.has(key):
		var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
		img.fill(color)
		_swatches[key] = ImageTexture.create_from_image(img)
	return _swatches[key]


func _on_layer_pressed(i: int) -> void:
	if map and not _syncing:
		map.set_layer(i)


func _on_clear_target() -> void:
	if map:
		map.set_target_species(-1)


func _step_radius(step: int) -> void:
	if map:
		map.set_radius(map.radius + step)


# --- Vitesse du temps ---

func _set_speed(level: int) -> void:
	speed_level = clampi(level, 0, SPEEDS.size())
	GameState.paused = speed_level == 0
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(i == speed_level)


# --- Synchronisation avec la carte ---

func _sync_from_map() -> void:
	if map == null:
		return
	_syncing = true
	for i in _layer_buttons.size():
		_layer_buttons[i].set_pressed_no_signal(i == map.layer)
	for i in _power_buttons.size():
		_power_buttons[i].set_pressed_no_signal(Powers.LIST[i].id == map.power)
	var p := Powers.get_power(map.power)
	if p.is_empty():
		_radius_label.text = "Choisissez un pouvoir (1-9) puis cliquez sur la carte"
	else:
		_radius_label.text = "%s — rayon %d  ([ ] ou Maj+molette, Échap pour annuler)" % [p.label, map.radius]
	_update_target_label()
	_syncing = false


func _on_power_toggled(on: bool, power_id: String) -> void:
	if map == null or _syncing:
		return
	if on:
		map.set_power(power_id)
	elif map.power == power_id:
		map.set_power("")


func _update_target_label() -> void:
	var id: int = map.target_species if map else -1
	if id < 0:
		_target_label.text = "Cible : espèce dominante de la région cliquée"
		_species_list.deselect_all()
		return
	var info = GameState.sim.species.get(id) if GameState.sim else null
	var sp_name := str(info.get("name", "#%d" % id)) if info is Dictionary else "#%d" % id
	_target_label.text = "Cible : %s" % sp_name
	var idx := _species_ids.find(id)
	if idx >= 0:
		_species_list.select(idx)


# --- Espèces ---

func _refresh_species(force: bool) -> void:
	var sim = GameState.sim
	if sim == null:
		return
	var rows := []
	for id in sim.species:
		var info = sim.species[id]
		if not (info is Dictionary) or not info.get("alive", true):
			continue
		rows.append([int(id), info])
	rows.sort_custom(func(a, b): return float(a[1].get("population", 0)) > float(b[1].get("population", 0)))
	var sig := ""
	for r in rows:
		sig += "%d," % r[0]
	if force or sig != _species_signature:
		_species_signature = sig
		_species_list.clear()
		_species_ids.clear()
		for r in rows:
			var idx := _species_list.add_item("", _swatch(MapMath.species_color(r[0])))
			_species_list.set_item_metadata(idx, r[0])
			_species_ids.append(r[0])
	for i in rows.size():
		var info: Dictionary = rows[i][1]
		var label := str(info.get("name", "Espèce #%d" % rows[i][0]))
		if info.get("sapient", false):
			label += "  (sapiente)"
		label += "\n   pop. %s" % _format_population(float(info.get("population", 0)))
		_species_list.set_item_text(i, label)
		_species_list.set_item_tooltip(i, _traits_text(info))
	if rows.is_empty() and _species_list.item_count == 0:
		_species_list.add_item("Aucune espèce vivante")
		_species_list.set_item_disabled(0, true)
		_species_list.set_item_selectable(0, false)
	if map:
		_update_target_label()


func _format_population(p: float) -> String:
	if p >= 1_000_000_000.0:
		return "%.1f Md" % (p / 1_000_000_000.0)
	if p >= 1_000_000.0:
		return "%.1f M" % (p / 1_000_000.0)
	if p > 0.0 and p < 1.0:
		return "%d %%" % int(p * 100.0)
	return MapMath.group_thousands(int(p))


func _traits_text(info: Dictionary) -> String:
	var traits = info.get("traits", {})
	if traits is Dictionary and not traits.is_empty():
		var parts := []
		for k in traits:
			parts.append("%s : %s" % [k, str(traits[k])])
		return ", ".join(parts)
	if traits is Array and not traits.is_empty():
		return ", ".join(traits.map(func(x): return str(x)))
	return str(info.get("name", ""))


func _on_species_selected(index: int) -> void:
	if map == null or index >= _species_ids.size():
		return
	map.set_target_species(_species_ids[index])


# --- Survol ---

func _on_region_hovered(region: Vector2i) -> void:
	var sim = GameState.sim
	if sim == null or map == null:
		return
	var i: int = region.y * map.grid.x + region.x
	if i < 0 or i >= sim.elevation.size():
		return
	var elev: float = sim.elevation[i]
	var text := "Région (%d, %d) — %s\n" % [region.x, region.y, "océan" if elev < 0.0 else "terres"]
	text += "Température %d %%   Tech %d %%\n" % [int(sim.temperature[i] * 100.0), int(sim.tech[i] * 100.0)]
	var sid: int = sim.dominant_species[i]
	if sid >= 0:
		var info = sim.species.get(sid)
		var sp_name := str(info.get("name", "#%d" % sid)) if info is Dictionary else "#%d" % sid
		text += "%s (densité %d %%)" % [sp_name, int(sim.population[i] * 100.0)]
	else:
		text += "Aucune espèce dominante"
	_info_label.text = text


# --- Chronique et narration ---

func _on_event(event: Dictionary) -> void:
	var summary := str(event.get("summary", event.get("type", "?")))
	var year := MapMath.format_year(float(event.get("year", GameState.sim.year if GameState.sim else 0.0)))
	var line := "[color=#8a93a8]%s[/color]  %s" % [year, _escape(summary)]
	var region = event.get("region")
	if region is Vector2i:
		line = "[url=%d,%d]%s[/url]" % [region.x, region.y, line]
	_add_log_line(line)


func _add_log_line(bbcode: String) -> void:
	if _log_lines > 0:
		_log.append_text("\n")
	_log.append_text(bbcode)
	_log_lines += 1
	while _log_lines > MAX_LOG_LINES:
		_log.remove_paragraph(0)
		_log_lines -= 1


func _on_log_meta(meta) -> void:
	var parts := str(meta).split(",")
	if parts.size() == 2 and map:
		map.focus_region(Vector2i(int(parts[0]), int(parts[1])))


func _on_era_changed(era: String) -> void:
	_era_label.text = era
	_add_log_line("[color=#e8c66a]Une nouvelle ère commence : %s[/color]" % _escape(era))
	if request_narration:
		Narrator.narrate({summary = "Une nouvelle ère commence : %s." % era, era = era,
				year = GameState.sim.year if GameState.sim else 0.0})


func _on_divine_action(action: Dictionary, consequences: Array) -> void:
	var p := Powers.get_power(str(action.get("type", "")))
	var label: String = p.get("label", str(action.get("type", "?")))
	var region: Vector2i = action.get("region", Vector2i.ZERO)
	_add_log_line("[url=%d,%d][color=#%s]» %s[/color] en (%d, %d)[/url]" % [region.x, region.y,
			p.get("color", Color.WHITE).to_html(false), label, region.x, region.y])
	if request_narration:
		var summary := "Dieu déchaîne le pouvoir « %s »." % label
		if not consequences.is_empty() and consequences[0] is Dictionary:
			summary = str(consequences[0].get("summary", summary))
		Narrator.narrate({summary = summary, action = action, consequences = consequences,
				era = GameState.sim.current_era() if GameState.sim else "",
				year = GameState.sim.year if GameState.sim else 0.0})


func _on_narration(text: String) -> void:
	if text.strip_edges() == "":
		return
	_narration_label.text = "[center][i]%s[/i][/center]" % _escape(text)
	_narration_panel.visible = true
	_narration_panel.modulate.a = 1.0
	_narration_timer = NARRATION_DURATION


func _escape(s: String) -> String:
	return s.replace("[", "[lb]")
