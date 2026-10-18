extends CanvasLayer
## Interface divine, disposition sobre : la parcelle et ses créatures occupent le centre.
## - en haut, au centre : fine barre (année, ère, vitesse du temps, tiroirs) ;
## - en bas, au centre : barre des pouvoirs compacte (+ indication flottante quand un pouvoir est armé) ;
## - tiroirs fermés par défaut : « Espèces vivantes » du monde (touche E, choix de la cible) à droite,
##   « Chronique » du monde (touche C) en bas à gauche.
## Zones : src/ui/layout.gd (dont la bande et la colonne réservées à la couche stratégie).
## Ailleurs, et hors de ce fichier : statistiques de la parcelle à gauche (S), fil d'Ézéchiel à droite,
## dilemmes au centre-bas. La narration n'est affichée que par le fil (src/ui/chronicle/).
## Construite en code pour rester lisible et sans dépendance à des ressources externes.
## L'état joueur (pouvoir, rayon, cible) vit dans src/ui/parcel_powers.gd : voir bind_map().

const MapMath := preload("res://src/map/map_math.gd")
const Powers := preload("res://src/map/divine_powers.gd")
const Layout := preload("res://src/ui/layout.gd")

## Multiplicateurs de vitesse x1..x5 (appliqués à MapMath.base_years_per_second()).
const SPEEDS := [1.0, 2.0, 3.0, 4.0, 5.0]
const MAX_LOG_LINES := 200
const SPECIES_KEY := KEY_E
const CHRONICLE_KEY := KEY_C
const GOLD := Color(1.0, 0.85, 0.5)
const DIM := Color(0.62, 0.66, 0.78)

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
var _power_buttons: Array[Button] = []
var _hint_panel: PanelContainer
var _hint_label: Label
var _species_drawer: PanelContainer
var _species_toggle: Button
var _species_list: ItemList
var _species_ids: Array[int] = []
var _species_signature := ""
var _species_timer := 0.0
var _target_button: Button
var _chronicle_drawer: PanelContainer
var _chronicle_toggle: Button
var _log: RichTextLabel
var _log_lines := 0
var _swatches := {}
var _syncing := false


func _ready() -> void:
	layer = 10
	_build()
	GameState.event_occurred.connect(_on_event)
	GameState.era_changed.connect(_on_era_changed)
	GameState.divine_action_applied.connect(_on_divine_action)
	if GameState.sim != null:
		_era_label.text = GameState.sim.current_era()
	_set_speed(1)
	_refresh_species(true)
	_add_log_line("[color=#e8c66a]Que la lumière soit.[/color] Vous veillez sur un monde jeune.")


## Relie le HUD à l'état des pouvoirs (source de vérité du pouvoir, du rayon et de la cible).
func bind_map(world_map: Node) -> void:
	map = world_map
	map.state_changed.connect(_sync_from_map)
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
	# La liste mondiale n'est tenue à jour que tiroir ouvert.
	_species_timer += delta
	if _species_drawer.visible and _species_timer >= 1.0:
		_species_timer = 0.0
		_refresh_species(false)


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
		KEY_BRACKETLEFT:
			if map: map.set_radius(map.radius - 1)
		KEY_BRACKETRIGHT:
			if map: map.set_radius(map.radius + 1)
		KEY_ESCAPE:
			if _species_drawer.visible or _chronicle_drawer.visible:
				_set_drawer(_species_drawer, _species_toggle, false)
				_set_drawer(_chronicle_drawer, _chronicle_toggle, false)
			elif map:
				map.set_power("")
		SPECIES_KEY:
			_set_drawer(_species_drawer, _species_toggle, not _species_drawer.visible)
		CHRONICLE_KEY:
			_set_drawer(_chronicle_drawer, _chronicle_toggle, not _chronicle_drawer.visible)
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
	_build_top_bar(root)
	_build_power_bar(root)
	_build_species_drawer(root)
	_build_chronicle_drawer(root)


## Fine barre du haut, centrée, à la largeur de son contenu.
func _build_top_bar(root: Control) -> void:
	var top := _panel(root)
	top.theme_type_variation = &"CompactPanel"
	_place(top, Vector4(0.5, 0, 0.5, 0), Vector4(0, Layout.TOP_BAR.position.y, 0, Layout.TOP_BAR.position.y))
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	top.add_child(row)

	_year_label = Label.new()
	_year_label.add_theme_font_size_override("font_size", 26)
	_year_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_year_label.custom_minimum_size.x = 220
	_year_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_year_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_year_label)
	var era_box := VBoxContainer.new()
	era_box.add_theme_constant_override("separation", -5)
	era_box.alignment = BoxContainer.ALIGNMENT_CENTER
	era_box.custom_minimum_size.x = 150
	row.add_child(era_box)
	_era_label = Label.new()
	_era_label.add_theme_font_size_override("font_size", 17)
	era_box.add_child(_era_label)
	_rate_label = Label.new()
	_rate_label.add_theme_color_override("font_color", DIM)
	_rate_label.add_theme_font_size_override("font_size", 13)
	era_box.add_child(_rate_label)

	row.add_child(VSeparator.new())
	var speed_box := HBoxContainer.new()
	speed_box.add_theme_constant_override("separation", 3)
	row.add_child(speed_box)
	var speed_group := ButtonGroup.new()
	for i in SPEEDS.size() + 1:
		var b := _toggle_button("Pause" if i == 0 else "x%d" % i, speed_group)
		b.custom_minimum_size = Vector2(40 if i > 0 else 62, 36)
		b.tooltip_text = "Espace : pause / reprise — +/- : vitesse"
		b.pressed.connect(_set_speed.bind(i))
		speed_box.add_child(b)
		_speed_buttons.append(b)

	row.add_child(VSeparator.new())
	_species_toggle = _drawer_button("Espèces  E", "Espèces vivantes du monde et cible des pouvoirs (E)")
	_species_toggle.toggled.connect(func(on: bool) -> void: _set_drawer(_species_drawer, _species_toggle, on))
	row.add_child(_species_toggle)
	_chronicle_toggle = _drawer_button("Chronique  C", "Chronique des événements du monde (C)")
	_chronicle_toggle.toggled.connect(func(on: bool) -> void: _set_drawer(_chronicle_drawer, _chronicle_toggle, on))
	row.add_child(_chronicle_toggle)


## Barre des pouvoirs compacte (une rangée) ; l'indication de rayon ne s'affiche que pouvoir armé.
func _build_power_bar(root: Control) -> void:
	var bar := _panel(root)
	bar.theme_type_variation = &"CompactPanel"
	var bar_bottom := Layout.POWER_BAR.end.y - Layout.REF_SIZE.y
	_place(bar, Vector4(0.5, 1, 0.5, 1), Vector4(0, bar_bottom, 0, bar_bottom))
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var power_row := HBoxContainer.new()
	power_row.add_theme_constant_override("separation", 4)
	bar.add_child(power_row)
	var power_group := ButtonGroup.new()
	power_group.allow_unpress = true
	for p in Powers.LIST:
		var b := _toggle_button("%s\n%s" % [OS.get_keycode_string(p.key), p.label], power_group)
		b.custom_minimum_size = Vector2(92, 50)
		b.add_theme_font_size_override("font_size", 14)
		b.tooltip_text = "%s — %s\nTouche %s, puis clic sur la parcelle." % [p.label, p.hint, OS.get_keycode_string(p.key)]
		b.add_theme_color_override("font_pressed_color", p.color)
		b.add_theme_color_override("font_hover_pressed_color", p.color.lightened(0.3))
		b.toggled.connect(_on_power_toggled.bind(p.id))
		power_row.add_child(b)
		_power_buttons.append(b)

	_hint_panel = _panel(root)
	_hint_panel.theme_type_variation = &"CompactPanel"
	var hint_bottom := Layout.POWER_HINT.end.y - Layout.REF_SIZE.y
	_place(_hint_panel, Vector4(0.5, 1, 0.5, 1), Vector4(0, hint_bottom, 0, hint_bottom))
	_hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint_panel.visible = false
	var hint_row := HBoxContainer.new()
	hint_row.add_theme_constant_override("separation", 8)
	_hint_panel.add_child(hint_row)
	var minus := Button.new()
	minus.text = " − "
	minus.focus_mode = Control.FOCUS_NONE
	minus.tooltip_text = "Réduire le rayon ( [ )"
	minus.pressed.connect(_step_radius.bind(-1))
	hint_row.add_child(minus)
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 15)
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_row.add_child(_hint_label)
	var plus := Button.new()
	plus.text = " + "
	plus.focus_mode = Control.FOCUS_NONE
	plus.tooltip_text = "Agrandir le rayon ( ] )"
	plus.pressed.connect(_step_radius.bind(1))
	hint_row.add_child(plus)


## Tiroir « Espèces vivantes » (monde entier) : choix de la cible des pouvoirs. Fermé par défaut.
func _build_species_drawer(root: Control) -> void:
	_species_drawer = _panel(root)
	Layout.place(_species_drawer, Layout.SPECIES_DRAWER, Vector2(1, 0))
	_species_drawer.visible = false
	var box := VBoxContainer.new()
	_species_drawer.add_child(box)
	box.add_child(_title("Espèces vivantes — monde"))
	_species_list = ItemList.new()
	_species_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_species_list.focus_mode = Control.FOCUS_NONE
	_species_list.item_selected.connect(_on_species_selected)
	box.add_child(_species_list)
	# Un seul élément pour la cible : il l'affiche et, cliqué, revient à l'espèce dominante.
	_target_button = Button.new()
	_target_button.focus_mode = Control.FOCUS_NONE
	_target_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_target_button.add_theme_font_size_override("font_size", 14)
	_target_button.pressed.connect(_on_clear_target)
	box.add_child(_target_button)


## Tiroir « Chronique » (journal du monde), en bas à gauche, sous les statistiques. Fermé par défaut.
func _build_chronicle_drawer(root: Control) -> void:
	_chronicle_drawer = _panel(root)
	Layout.place(_chronicle_drawer, Layout.CHRONICLE_DRAWER, Vector2(0, 1))
	_chronicle_drawer.visible = false
	var box := VBoxContainer.new()
	_chronicle_drawer.add_child(box)
	box.add_child(_title("Chronique du monde"))
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 15)
	box.add_child(_log)


func _make_theme() -> Theme:
	var t := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.04, 0.05, 0.09, 0.82)
	panel.border_color = Color(0.85, 0.7, 0.35, 0.35)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(8)
	panel.set_content_margin_all(10)
	t.set_stylebox("panel", "PanelContainer", panel)
	var compact := panel.duplicate() as StyleBoxFlat
	compact.set_content_margin_all(5)
	compact.content_margin_left = 10
	compact.content_margin_right = 10
	t.set_type_variation(&"CompactPanel", &"PanelContainer")
	t.set_stylebox("panel", &"CompactPanel", compact)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.13, 0.2, 0.9)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(4)
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
	t.set_stylebox("disabled", "Button", normal)
	t.set_color("font_color", "Label", Color(0.9, 0.9, 0.95))
	t.set_color("font_color", "Button", Color(0.88, 0.88, 0.95))
	t.set_color("font_disabled_color", "Button", DIM)
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
	l.add_theme_color_override("font_color", GOLD)
	return l


func _toggle_button(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	return b


func _drawer_button(text: String, tooltip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 36
	b.add_theme_font_size_override("font_size", 14)
	b.tooltip_text = tooltip
	return b


## Ouvre / ferme un tiroir et garde son bouton de la barre du haut synchronisé.
func _set_drawer(drawer: Control, toggle: Button, open: bool) -> void:
	drawer.visible = open
	toggle.set_pressed_no_signal(open)
	if open and drawer == _species_drawer:
		_species_timer = 0.0
		_refresh_species(true)


func _swatch(color: Color) -> Texture2D:
	var key := color.to_html(false)
	if not _swatches.has(key):
		var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
		img.fill(color)
		_swatches[key] = ImageTexture.create_from_image(img)
	return _swatches[key]


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


# --- Synchronisation avec l'état des pouvoirs ---

func _sync_from_map() -> void:
	if map == null:
		return
	_syncing = true
	for i in _power_buttons.size():
		_power_buttons[i].set_pressed_no_signal(Powers.LIST[i].id == map.power)
	var p := Powers.get_power(map.power)
	_hint_panel.visible = not p.is_empty()
	if not p.is_empty():
		var text := "%s — rayon %d" % [p.label, map.radius]
		if p.get("needs_species", false):
			text += " — vise : %s" % _target_name()
		_hint_label.text = text + "   ([ ] ou Maj+molette, Échap pour annuler)"
		# Recentre à la largeur du nouveau texte (grow_horizontal = BOTH depuis l'ancre centrale).
		_hint_panel.offset_left = 0.0
		_hint_panel.offset_right = 0.0
	_update_target_button()
	_syncing = false


func _on_power_toggled(on: bool, power_id: String) -> void:
	if map == null or _syncing:
		return
	if on:
		map.set_power(power_id)
	elif map.power == power_id:
		map.set_power("")


func _target_name() -> String:
	var id: int = map.target_species if map else -1
	if id < 0:
		return "espèce dominante de la parcelle"
	var info = GameState.sim.species.get(id) if GameState.sim else null
	return str(info.get("name", "#%d" % id)) if info is Dictionary else "#%d" % id


func _update_target_button() -> void:
	var id: int = map.target_species if map else -1
	_target_button.text = "Cible : %s" % _target_name()
	_target_button.disabled = id < 0
	_target_button.tooltip_text = "Cliquer pour revenir à l'espèce dominante de la parcelle." if id >= 0 \
			else "Choisissez une espèce dans la liste pour la viser ; sinon les pouvoirs visent l'espèce dominante de la parcelle."
	var idx := _species_ids.find(id)
	if idx >= 0:
		_species_list.select(idx)
	else:
		_species_list.deselect_all()


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
		label += "   pop. %s" % _format_population(float(info.get("population", 0)))
		_species_list.set_item_text(i, label)
		_species_list.set_item_tooltip(i, _traits_text(info))
	if rows.is_empty() and _species_list.item_count == 0:
		_species_list.add_item("Aucune espèce vivante")
		_species_list.set_item_disabled(0, true)
		_species_list.set_item_selectable(0, false)
	if map:
		_update_target_button()


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


# --- Chronique ---

func _on_event(event: Dictionary) -> void:
	var summary := str(event.get("summary", event.get("type", "?")))
	var year := MapMath.format_year(float(event.get("year", GameState.sim.year if GameState.sim else 0.0)))
	_add_log_line("[color=#8a93a8]%s[/color]  %s" % [year, _escape(summary)])


func _add_log_line(bbcode: String) -> void:
	if _log_lines > 0:
		_log.append_text("\n")
	_log.append_text(bbcode)
	_log_lines += 1
	while _log_lines > MAX_LOG_LINES:
		_log.remove_paragraph(0)
		_log_lines -= 1


func _on_era_changed(era: String) -> void:
	_era_label.text = era
	_add_log_line("[color=#e8c66a]Une nouvelle ère commence : %s[/color]" % _escape(era))
	if request_narration:
		Narrator.narrate({summary = "Une nouvelle ère commence : %s." % era, era = era,
				year = GameState.sim.year if GameState.sim else 0.0})


func _on_divine_action(action: Dictionary, consequences: Array) -> void:
	var p := Powers.get_power(str(action.get("type", "")))
	var label: String = p.get("label", str(action.get("type", "?")))
	_add_log_line("[color=#%s]» %s[/color] sur la parcelle" % [p.get("color", Color.WHITE).to_html(false), label])
	if request_narration:
		var summary := "Dieu déchaîne le pouvoir « %s »." % label
		if not consequences.is_empty() and consequences[0] is Dictionary:
			summary = str(consequences[0].get("summary", summary))
		Narrator.narrate({summary = summary, action = action, consequences = consequences,
				era = GameState.sim.current_era() if GameState.sim else "",
				year = GameState.sim.year if GameState.sim else 0.0})


func _escape(s: String) -> String:
	return s.replace("[", "[lb]")
