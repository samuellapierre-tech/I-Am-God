extends CanvasLayer
## Interface calme (docs/GENESE.md) : le monde occupe l'écran, l'interface se fait discrète.
## - en haut, au centre : fine barre (année, ère, vitesse du temps, tiroirs) ;
## - en bas, au centre : barre d'outils à deux onglets, « Semer » (palette de semences) et « Agir »
##   (pouvoirs), chaque bouton montrant sa recharge ; au-dessus, les réglages de l'outil choisi ;
## - tiroirs fermés par défaut, ouverts à la demande et jamais imposés :
##   « Monde » (E : statistiques planétaires et espèces), « Arbre de la vie » (T), « Chronique » (C).
## Ailleurs, hors de ce fichier : statistiques de la parcelle à gauche (S), fil d'Ézéchiel à droite.
## Zones : src/ui/layout.gd. Outil et recharges : src/ui/tools/tool_state.gd (ToolState.shared).
## L'état des pouvoirs de la vue (pouvoir, rayon, cible) reste synchronisé via bind_map().

## Le joueur veut voir cette espèce sur le globe (arbre de la vie : bouton ou double-clic).
signal focus_species(species_id: int)

const MapMath := preload("res://src/map/map_math.gd")
const Powers := preload("res://src/map/divine_powers.gd")
const Layout := preload("res://src/ui/layout.gd")
const ToolState := preload("res://src/ui/tools/tool_state.gd")
const ToolButton := preload("res://src/ui/tools/tool_button.gd")
const SeedCatalog := preload("res://src/ui/seeds/seed_catalog.gd")
const SeedEditor := preload("res://src/ui/seeds/seed_editor.gd")
const PlanetPanel := preload("res://src/ui/stats/planet_panel.gd")
const TreePanel := preload("res://src/ui/tree/tree_panel.gd")

## Multiplicateurs de vitesse x1..x5 (appliqués à MapMath.base_years_per_second()).
const SPEEDS := [1.0, 2.0, 3.0, 4.0, 5.0]
const MAX_LOG_LINES := 200
const WORLD_KEY := KEY_E
const TREE_KEY := KEY_T
const CHRONICLE_KEY := KEY_C
const TOOL_TAB_KEY := KEY_G
const GOLD := Color(1.0, 0.85, 0.5)
const DIM := Color(0.62, 0.66, 0.78)

## Le HUD demande une narration au Narrateur lors des grands moments (changement d'ère, action divine).
## Désactivé par défaut : le Narrateur écoute déjà GameState et raconte ces moments lui-même.
@export var request_narration := false

var map: Node = null
var tools: Node = null
## 0 = pause, 1..5 = vitesse.
var speed_level := 1
## "seed" (Semer) ou "power" (Agir).
var tool_tab := "seed"

var _year_label: Label
var _era_label: Label
var _rate_label: Label
var _speed_buttons: Array[Button] = []
var _tab_buttons := {}
var _seed_row: HBoxContainer
var _power_row: HBoxContainer
var _tool_buttons: Array[Button] = []
var _editor: Control
var _world_drawer: PanelContainer
var _world_toggle: Button
var _planet: Control
var _tree_panel: Control
var _tree_toggle: Button
var _chronicle_drawer: PanelContainer
var _chronicle_toggle: Button
var _log: RichTextLabel
var _log_lines := 0
var _syncing := false


func _ready() -> void:
	layer = 10
	tools = ToolState.shared(get_tree())
	_build()
	tools.tool_changed.connect(func(_t: Dictionary) -> void: _sync_from_tools())
	GameState.event_occurred.connect(_on_event)
	GameState.era_changed.connect(_on_era_changed)
	GameState.divine_action_applied.connect(_on_divine_action)
	if GameState.sim != null:
		_era_label.text = GameState.sim.current_era()
	_set_speed(1)
	_set_tool_tab("seed")
	_add_log_line("[color=#e8c66a]Que la lumière soit.[/color] Une planète vierge attend ce que tu y sèmeras.")


## Relie le HUD à l'état des pouvoirs de la vue (pouvoir, rayon, cible), tenu en phase avec ToolState.
func bind_map(world_map: Node) -> void:
	map = world_map
	if map.has_signal("state_changed"):
		map.state_changed.connect(_sync_from_map)
	_sync_from_map()


func _process(_delta: float) -> void:
	var sim = GameState.sim
	if sim == null:
		return
	_year_label.text = MapMath.format_year(sim.year)
	if speed_level > 0:
		GameState.years_per_second = MapMath.base_years_per_second(sim.ideal_step_years()) \
				* SPEEDS[speed_level - 1] * GameState.pace_factor()
	_rate_label.text = "%s ans/s" % MapMath.group_thousands(int(GameState.years_per_second)) \
			if speed_level > 0 else "Temps suspendu"


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
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			if tools.has_tool():
				var r := int(tools.selected_tool().params.get("radius", 4))
				tools.set_param("radius", r + (1 if key == KEY_BRACKETRIGHT else -1))
		KEY_ESCAPE:
			if _world_drawer.visible or _chronicle_drawer.visible or _tree_panel.visible:
				_close_drawers()
			else:
				tools.clear()
		WORLD_KEY:
			_set_drawer(_world_drawer, _world_toggle, not _world_drawer.visible)
		TREE_KEY:
			_set_drawer(_tree_panel, _tree_toggle, not _tree_panel.visible)
		CHRONICLE_KEY:
			_set_drawer(_chronicle_drawer, _chronicle_toggle, not _chronicle_drawer.visible)
		TOOL_TAB_KEY:
			_set_tool_tab("power" if tool_tab == "seed" else "seed")
		_:
			handled = _select_by_key(key)
	if handled:
		get_viewport().set_input_as_handled()


## 1..9 : outil de l'onglet courant (semence ou pouvoir).
func _select_by_key(key: int) -> bool:
	var list: Array = SeedCatalog.SEEDS if tool_tab == "seed" else Powers.LIST
	for item in list:
		if key == item.key:
			_toggle_tool(tool_tab, item.id)
			return true
	return false


# --- Construction de l'interface ---

func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_top_bar(root)
	_build_tool_bar(root)
	_editor = SeedEditor.new()
	_editor.tool_state = tools
	_editor.target_name = _target_name
	_editor.theme_type_variation = &"CompactPanel"
	Layout.place(_editor, Layout.TOOL_EDITOR, Vector2(0.5, 1))
	root.add_child(_editor)
	_build_world_drawer(root)
	_tree_panel = TreePanel.new()
	_tree_panel.visible = false
	Layout.place(_tree_panel, Layout.TREE, Vector2(0.5, 0))
	_tree_panel.focus_species.connect(func(id: int) -> void: focus_species.emit(id))
	root.add_child(_tree_panel)
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
	_world_toggle = _drawer_button("Monde  E", "Statistiques de la planète et espèces vivantes (E)")
	_world_toggle.toggled.connect(func(on: bool) -> void: _set_drawer(_world_drawer, _world_toggle, on))
	row.add_child(_world_toggle)
	_tree_toggle = _drawer_button("Arbre  T", "Arbre de la vie : la généalogie de toutes les espèces (T)")
	_tree_toggle.toggled.connect(func(on: bool) -> void: _set_drawer(_tree_panel, _tree_toggle, on))
	row.add_child(_tree_toggle)
	_chronicle_toggle = _drawer_button("Chronique  C", "Chronique des événements du monde (C)")
	_chronicle_toggle.toggled.connect(func(on: bool) -> void: _set_drawer(_chronicle_drawer, _chronicle_toggle, on))
	row.add_child(_chronicle_toggle)


## Barre d'outils : onglets « Semer » / « Agir », puis les boutons de l'onglet (avec recharge).
func _build_tool_bar(root: Control) -> void:
	var bar := _panel(root)
	bar.theme_type_variation = &"CompactPanel"
	var bottom := Layout.TOOL_BAR.end.y - Layout.REF_SIZE.y
	_place(bar, Vector4(0.5, 1, 0.5, 1), Vector4(0, bottom, 0, bottom))
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	bar.add_child(row)
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	row.add_child(tabs)
	var tab_group := ButtonGroup.new()
	for tab in [["seed", "Semer"], ["power", "Agir"]]:
		var b := _toggle_button(tab[1], tab_group)
		b.custom_minimum_size = Vector2(76, 24)
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = "Semer la vie ou agir sur le monde (G pour alterner)"
		b.pressed.connect(_set_tool_tab.bind(tab[0]))
		tabs.add_child(b)
		_tab_buttons[tab[0]] = b
	row.add_child(VSeparator.new())
	_seed_row = HBoxContainer.new()
	_seed_row.add_theme_constant_override("separation", 4)
	row.add_child(_seed_row)
	for s in SeedCatalog.SEEDS:
		_seed_row.add_child(_tool_button("seed", s, 128))
	_power_row = HBoxContainer.new()
	_power_row.add_theme_constant_override("separation", 4)
	row.add_child(_power_row)
	for p in Powers.LIST:
		_power_row.add_child(_tool_button("power", p, 92))


func _tool_button(kind: String, item: Dictionary, width: float) -> Button:
	var b := ToolButton.new()
	b.tool = {kind = kind, id = item.id}
	b.tool_state = tools
	b.accent = item.color
	b.text = "%s\n%s" % [OS.get_keycode_string(item.key), item.label]
	b.custom_minimum_size = Vector2(width, 50)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_pressed_color", item.color)
	b.add_theme_color_override("font_hover_pressed_color", item.color.lightened(0.3))
	b.tooltip_text = "%s — %s\nRecharge : %s" % [item.label, item.hint,
		ToolState.Cooldowns.format_remaining(ToolState.cooldown_of({kind = kind, id = item.id}))]
	b.pressed.connect(_toggle_tool.bind(kind, item.id))
	_tool_buttons.append(b)
	return b


## Tiroir « Monde » : statistiques planétaires et espèces (cible des pouvoirs).
func _build_world_drawer(root: Control) -> void:
	_world_drawer = _panel(root)
	Layout.place(_world_drawer, Layout.WORLD_DRAWER, Vector2(1, 0))
	_world_drawer.visible = false
	_planet = PlanetPanel.new()
	_planet.species_selected.connect(_on_species_selected)
	_planet.target_cleared.connect(func() -> void: _set_target(-1))
	_world_drawer.add_child(_planet)


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
	var tab_panel := StyleBoxFlat.new()
	tab_panel.bg_color = Color(0, 0, 0, 0)
	tab_panel.set_content_margin_all(4)
	t.set_stylebox("panel", "TabContainer", tab_panel)
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
	if open and drawer == _tree_panel:
		_tree_panel.refresh(true)


func _close_drawers() -> void:
	_set_drawer(_world_drawer, _world_toggle, false)
	_set_drawer(_chronicle_drawer, _chronicle_toggle, false)
	_set_drawer(_tree_panel, _tree_toggle, false)


# --- Vitesse du temps ---

func _set_speed(level: int) -> void:
	speed_level = clampi(level, 0, SPEEDS.size())
	GameState.paused = speed_level == 0
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(i == speed_level)


# --- Outils (semences et pouvoirs) ---

func _set_tool_tab(tab: String) -> void:
	tool_tab = tab
	_seed_row.visible = tab == "seed"
	_power_row.visible = tab == "power"
	for t in _tab_buttons:
		_tab_buttons[t].set_pressed_no_signal(t == tab)


## Choisit l'outil (ou le repose s'il est déjà choisi). Un pouvoir en recharge ne se choisit pas.
func _toggle_tool(kind: String, id: String) -> void:
	if tools.is_selected(kind, id):
		tools.clear()
		return
	if kind == "power" and not tools.can_use({kind = kind, id = id}):
		_sync_from_tools()  # le bouton reste levé : rien à viser pendant la recharge
		return
	if kind == "seed":
		tools.select_seed(id)
	else:
		tools.select_power(id, map.target_species if map and "target_species" in map else -1)
	_set_tool_tab(kind)


## ToolState -> boutons et état des pouvoirs de la vue.
func _sync_from_tools() -> void:
	var tool: Dictionary = tools.selected_tool()
	for b in _tool_buttons:
		b.set_pressed_no_signal(not tool.is_empty() and b.tool.kind == tool.kind and b.tool.id == tool.id)
	if map == null or _syncing:
		return
	_syncing = true
	var power: String = tool.id if not tool.is_empty() and tool.kind == "power" else ""
	if map.power != power:
		map.set_power(power)
	if power != "" and map.has_method("set_radius"):
		map.set_radius(int(tool.params.get("radius", map.radius)))
	_syncing = false


## État des pouvoirs de la vue -> ToolState (p. ex. Échap géré par la vue).
func _sync_from_map() -> void:
	if map == null or _syncing:
		return
	_syncing = true
	var tool: Dictionary = tools.selected_tool()
	var power := str(map.power) if "power" in map else ""
	if power != "" and not tools.is_selected("power", power):
		tools.select_power(power, int(map.target_species) if "target_species" in map else -1)
	elif power == "" and not tool.is_empty() and tool.kind == "power":
		tools.clear()
	elif power != "" and "radius" in map and int(tool.params.get("radius", -1)) != int(map.radius):
		tools.set_param("radius", int(map.radius))
	var target := int(map.target_species) if "target_species" in map else -1
	_planet.set_target(target, _target_name())
	_syncing = false


func _on_species_selected(id: int) -> void:
	_set_target(id)


func _set_target(id: int) -> void:
	if map and map.has_method("set_target_species"):
		map.set_target_species(id)
	if tools.has_tool() and tools.selected_tool().kind == "power":
		tools.set_param("species_id", id)
	_planet.set_target(id, _target_name())


func _target_name() -> String:
	var id: int = int(map.target_species) if map and "target_species" in map else -1
	if id < 0:
		return "espèce dominante"
	var info = GameState.sim.species.get(id) if GameState.sim else null
	return str(info.get("name", "#%d" % id)) if info is Dictionary else "#%d" % id


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
	# Recharge de l'outil, même si l'action a été appliquée ailleurs (vue, globe) ; l'outil se repose.
	var used: Dictionary = tools.notify_applied(action)
	if not used.is_empty() and tools.is_selected(str(used.kind), str(used.id)):
		tools.clear()
	var type := str(action.get("type", ""))
	var label := type
	var color := Color.WHITE
	if type == "seed":
		var s := SeedCatalog.get_seed(str(action.get("kind", "")))
		label = "Semence : %s" % s.get("label", action.get("kind", "?"))
		color = s.get("color", Color.WHITE)
	else:
		var p := Powers.get_power(type)
		label = p.get("label", type)
		color = p.get("color", Color.WHITE)
	_add_log_line("[color=#%s]» %s[/color]" % [color.to_html(false), _escape(label)])
	if request_narration:
		var summary := "Dieu déchaîne le pouvoir « %s »." % label
		if not consequences.is_empty() and consequences[0] is Dictionary:
			summary = str(consequences[0].get("summary", summary))
		Narrator.narrate({summary = summary, action = action, consequences = consequences,
				era = GameState.sim.current_era() if GameState.sim else "",
				year = GameState.sim.year if GameState.sim else 0.0})


func _escape(s: String) -> String:
	return s.replace("[", "[lb]")
