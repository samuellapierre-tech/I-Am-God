extends PanelContainer
## Arbre de la vie (touche T, ouvert par le HUD dans Layout.TREE) : généalogie de toutes les espèces
## de la partie (TreeView), et fiche de l'espèce choisie (traits, description, apparition, extinction,
## ancêtres, marques du joueur) avec un bouton pour la centrer sur le globe.
## Les marques « semée » / « touchée » viennent des champs `sown` / `touched` de la filiation
## (session Vie) et, en attendant, des actions du joueur (GameState.divine_action_applied).

## Le joueur demande à voir cette espèce sur le globe (relayé par le HUD).
signal focus_species(species_id: int)

const TreeLayout := preload("res://src/ui/tree/tree_layout.gd")
const TreeView := preload("res://src/ui/tree/tree_view.gd")
const MapMath := preload("res://src/map/map_math.gd")

const REFRESH := 2.0
const MAX_ANCESTORS := 8

var _view: TreeView
var _count_label: Label
var _card: VBoxContainer
var _name: Label
var _status: Label
var _dates: Label
var _desc: Label
var _traits: Label
var _marks: Label
var _ancestors: VBoxContainer
var _anc_title: Label
var _focus_button: Button
var _by_id := {}
var _sown := {}
var _touched := {}
var _signature := ""
var _timer := REFRESH
var _selected := -1
var _fitted := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size.x = 300
	row.add_child(left)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	left.add_child(head)
	var title := Label.new()
	title.text = "Arbre de la vie"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	head.add_child(title)
	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 13)
	_count_label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.82))
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.clip_text = true
	head.add_child(_count_label)
	var fit := Button.new()
	fit.text = "Tout voir"
	fit.focus_mode = Control.FOCUS_NONE
	fit.tooltip_text = "Molette : zoom (Maj : le temps seul) — glisser : déplacer — double-clic : centrer sur le globe"
	fit.pressed.connect(func() -> void: _view.fit_all())
	head.add_child(fit)
	_view = TreeView.new()
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.species_clicked.connect(show_species)
	_view.species_double_clicked.connect(func(id: int) -> void: focus_species.emit(id))
	left.add_child(_view)
	var legend := Label.new()
	legend.text = "◆ semée par toi    ○ touchée par tes actes    gris : éteinte    couleur : vivante"
	legend.add_theme_font_size_override("font_size", 12)
	legend.add_theme_color_override("font_color", Color(0.7, 0.72, 0.82))
	legend.clip_text = true
	left.add_child(legend)

	_card = VBoxContainer.new()
	_card.custom_minimum_size.x = 280
	_card.add_theme_constant_override("separation", 6)
	row.add_child(_card)
	_name = _label(19, Color(1.0, 0.85, 0.5))
	_status = _label(14, Color(0.8, 0.82, 0.9))
	_dates = _label(14, Color(0.75, 0.77, 0.86))
	_traits = _label(14, Color(0.85, 0.86, 0.92))
	_desc = _label(14, Color(0.9, 0.9, 0.95))
	_marks = _label(14, Color(1.0, 0.85, 0.4))
	_anc_title = _label(14, Color(1.0, 0.85, 0.5))
	_anc_title.text = "Ancêtres"
	_ancestors = VBoxContainer.new()
	_ancestors.add_theme_constant_override("separation", 0)
	_card.add_child(_ancestors)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card.add_child(spacer)
	_focus_button = Button.new()
	_focus_button.text = "Centrer sur le globe"
	_focus_button.focus_mode = Control.FOCUS_NONE
	_focus_button.pressed.connect(func() -> void:
		if _selected >= 0:
			focus_species.emit(_selected))
	_card.add_child(_focus_button)
	show_species(-1)

	if GameState and GameState.has_signal("divine_action_applied"):
		GameState.divine_action_applied.connect(_on_divine_action)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_timer += delta
	if _timer >= REFRESH:
		_timer = 0.0
		refresh()


## Recalcule la filiation et la mise en page si des espèces sont nées ou mortes.
func refresh(force := false) -> void:
	var sim = GameState.sim if GameState else null
	var list := TreeLayout.entries_from(sim)
	var alive := 0
	for e in list:
		if e.get("alive", true):
			alive += 1
	var sig := "%d/%d" % [list.size(), alive]
	if sig == _signature and not force:
		return
	_signature = sig
	_by_id.clear()
	for e in list:
		_by_id[int(e.id)] = e
	var now: float = float(sim.year) if sim != null else 0.0
	_view.sown = _sown
	_view.touched = _touched
	_view.set_data(TreeLayout.compute(list, now), _by_id)
	_count_label.text = "%d espèces dans la partie, %d vivantes" % [list.size(), alive]
	if not _fitted:
		_fitted = true
		_view.fit_all.call_deferred()
	if _selected >= 0:
		show_species(_selected)


## Affiche la fiche de l'espèce `id` (-1 : invitation à choisir).
func show_species(id: int) -> void:
	_selected = id
	_view.selected = id
	_view.queue_redraw()
	var e: Dictionary = _by_id.get(id, {})
	var has := not e.is_empty()
	for c in [_status, _dates, _traits, _desc, _marks, _anc_title, _ancestors, _focus_button]:
		c.visible = has
	if not has:
		_name.text = "Choisissez une espèce"
		return
	_name.text = str(e.get("name", "#%d" % id))
	var alive := bool(e.get("alive", true))
	_status.text = "Vivante" if alive else "Éteinte"
	_status.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55) if alive else Color(0.7, 0.7, 0.75))
	var dates := "Apparue : %s" % MapMath.format_year(float(e.get("born_year", 0.0)))
	if not alive and is_finite(float(e.get("extinct_year", NAN))):
		dates += "\nÉteinte : %s" % MapMath.format_year(float(e.extinct_year))
	_dates.text = dates
	var traits: Dictionary = e.get("traits", {}) if e.get("traits") is Dictionary else {}
	_traits.text = _traits_text(traits)
	_desc.text = _description(id, e, traits)
	var marks: Array[String] = []
	if _sown.has(id) or bool(e.get("sown", false)):
		marks.append("◆ Semée par toi")
	if _touched.has(id) or bool(e.get("touched", false)):
		marks.append("○ Touchée par tes actes")
	_marks.text = "\n".join(marks)
	_marks.visible = not marks.is_empty()
	for c in _ancestors.get_children():
		_ancestors.remove_child(c)
		c.queue_free()
	var chain := TreeLayout.ancestors(_by_id, id)
	for i in mini(chain.size(), MAX_ANCESTORS):
		var aid := chain[i]
		var link := LinkButton.new()
		link.text = "%s%s" % ["  ".repeat(mini(i, 6)), str(_by_id[aid].get("name", "#%d" % aid))]
		link.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		link.add_theme_font_size_override("font_size", 13)
		link.pressed.connect(func() -> void:
			show_species(aid)
			_view.focus(aid))
		_ancestors.add_child(link)
	if chain.size() > MAX_ANCESTORS:
		var more := _label(12, Color(0.6, 0.62, 0.7), _ancestors)
		more.text = "… et %d de plus" % (chain.size() - MAX_ANCESTORS)
	if chain.is_empty():
		var root := _label(13, Color(0.6, 0.62, 0.7), _ancestors)
		root.text = "Aucun : lignée fondatrice"


func _description(id: int, e: Dictionary, traits: Dictionary) -> String:
	var sim = GameState.sim if GameState else null
	if sim != null and sim.has_method("describe_species"):
		var d = sim.call("describe_species", id)
		if d is String and d != "":
			return d
	if str(e.get("description", "")) != "":
		return str(e.description)
	return TreeLayout.describe_traits(traits)


func _traits_text(t: Dictionary) -> String:
	if t.is_empty():
		return ""
	var parts: Array[String] = []
	if t.has("size"):
		parts.append("taille %d %%" % int(float(t.size) * 100.0))
	if t.has("intelligence"):
		parts.append("intelligence %d %%" % int(float(t.intelligence) * 100.0))
	if t.has("adaptability"):
		parts.append("adaptabilité %d %%" % int(float(t.adaptability) * 100.0))
	if t.has("aggression"):
		parts.append("agressivité %d %%" % int(float(t.aggression) * 100.0))
	return ", ".join(parts)


func _on_divine_action(action: Dictionary, consequences: Array) -> void:
	var m := TreeLayout.marks(action, consequences)
	for id in m.sown:
		_sown[id] = true
	for id in m.touched:
		_touched[id] = true
	if is_visible_in_tree():
		_view.queue_redraw()


func _label(font_size: int, color: Color, parent: Control = null) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 280
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	(parent if parent else _card).add_child(l)
	return l
