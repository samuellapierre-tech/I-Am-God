extends TabContainer
## Tiroir « Monde » (touche E) : deux onglets.
## - Planète : chaleur mondiale et locale, ozone, O₂, CO₂, méthane, niveau des mers, glace, biomasse,
##   biodiversité, extinctions récentes, Soleil, habitabilité ; un clic sur une mesure affiche sa courbe.
## - Espèces : toutes les espèces vivantes, population et tendance ▲▼, filtrables par milieu, régime
##   et taille ; un clic choisit la cible des pouvoirs.
## Données lues via PlanetMath (has_method / « in ») : seules les mesures disponibles s'affichent.

signal species_selected(species_id: int)
signal target_cleared

const PlanetMath := preload("res://src/ui/stats/planet_math.gd")
const StatsMath := preload("res://src/ui/stats/stats_math.gd")
const StatsChart := preload("res://src/ui/stats/stats_chart.gd")
const TrendArrow := preload("res://src/ui/stats/trend_arrow.gd")
const MapMath := preload("res://src/map/map_math.gd")

const REFRESH := 1.0

var _metric_box: VBoxContainer
var _metric_rows := {}  # key -> {value: Label, arrow: TrendArrow, button: Button}
var _chart: StatsChart
var _chart_title: Label
var _selected_metric := "temperature_c"
var _history: Array = []  # historique tenu par le panneau si la simulation n'en fournit pas

var _filters := {habitat = "all", diet = "all", size = "all"}
var _species_list: ItemList
var _species_ids: Array[int] = []
var _last_population := {}
var _trends := {}
var _target_button: Button
var _target_id := -1
var _trend_icons := {}
var _timer := REFRESH


func _ready() -> void:
	_trend_icons = {1: _triangle_icon(1), -1: _triangle_icon(-1), 0: _triangle_icon(0)}
	_build_planet_tab()
	_build_species_tab()


func _build_planet_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Planète"
	tab.add_theme_constant_override("separation", 2)
	add_child(tab)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)
	_metric_box = VBoxContainer.new()
	_metric_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_metric_box.add_theme_constant_override("separation", 0)
	scroll.add_child(_metric_box)
	_chart_title = Label.new()
	_chart_title.add_theme_font_size_override("font_size", 14)
	_chart_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	tab.add_child(_chart_title)
	_chart = StatsChart.new()
	_chart.custom_minimum_size = Vector2(0, 110)
	tab.add_child(_chart)


func _build_species_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Espèces"
	add_child(tab)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 4)
	tab.add_child(filters)
	filters.add_child(_filter("habitat", PlanetMath.HABITAT_FILTERS))
	filters.add_child(_filter("diet", PlanetMath.DIET_FILTERS))
	filters.add_child(_filter("size", PlanetMath.SIZE_FILTERS))
	_species_list = ItemList.new()
	_species_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_species_list.focus_mode = Control.FOCUS_NONE
	_species_list.item_selected.connect(func(i: int) -> void:
		if i < _species_ids.size():
			species_selected.emit(_species_ids[i]))
	tab.add_child(_species_list)
	# Un seul élément pour la cible : il l'affiche et, cliqué, revient à l'espèce dominante.
	_target_button = Button.new()
	_target_button.focus_mode = Control.FOCUS_NONE
	_target_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_target_button.add_theme_font_size_override("font_size", 14)
	_target_button.pressed.connect(func() -> void: target_cleared.emit())
	tab.add_child(_target_button)
	set_target(-1, "")


func _filter(key: String, options: Dictionary) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.add_theme_font_size_override("font_size", 13)
	o.fit_to_longest_item = false
	var ids := options.keys()
	for id in ids:
		o.add_item(str(options[id]))
	o.item_selected.connect(func(i: int) -> void:
		_filters[key] = str(ids[i])
		_refresh_species())
	return o


## Affiche la cible des pouvoirs (-1 = espèce dominante).
func set_target(id: int, name: String) -> void:
	_target_id = id
	_target_button.text = "Cible : %s" % (name if id >= 0 else "espèce dominante")
	_target_button.disabled = id < 0
	_target_button.tooltip_text = "Cliquer pour revenir à l'espèce dominante." if id >= 0 \
			else "Choisissez une espèce dans la liste pour la viser ; sinon les pouvoirs visent l'espèce dominante."
	var idx := _species_ids.find(id)
	if idx >= 0:
		_species_list.select(idx)
	else:
		_species_list.deselect_all()


func _process(delta: float) -> void:
	_timer += delta
	if _timer < REFRESH or GameState == null or GameState.sim == null:
		return
	_timer = 0.0
	var stats := PlanetMath.read_stats(GameState.sim, GameState.parcel)
	var sample := stats.duplicate()
	sample.year = float(GameState.sim.year)
	PlanetMath.push_sample(_history, sample)
	_track_populations()
	if not is_visible_in_tree():
		return
	_refresh_metrics(stats)
	_refresh_species()


# --- Planète ---

func _refresh_metrics(stats: Dictionary) -> void:
	var history := PlanetMath.read_history(GameState.sim)
	if history.is_empty():
		history = _history
	for m in PlanetMath.METRICS:
		var key: String = m.key
		if not stats.has(key):
			if _metric_rows.has(key):
				_metric_rows[key].row.visible = false
			continue
		if not _metric_rows.has(key):
			_add_metric_row(m)
		var row: Dictionary = _metric_rows[key]
		row.row.visible = true
		row.value.text = PlanetMath.format_metric(key, stats[key])
		row.arrow.trend = StatsMath.trend_of(StatsMath.series(history, key), 16, float(m.trend))
		row.button.set_pressed_no_signal(key == _selected_metric)
	if not stats.has(_selected_metric) and not stats.is_empty():
		for m in PlanetMath.METRICS:
			if stats.has(m.key):
				_selected_metric = m.key
				break
	var meta := PlanetMath.metric(_selected_metric)
	_chart_title.text = "%s — sur la durée" % meta.get("label", _selected_metric)
	_chart.min_span = float(meta.get("span", 1.0))
	var key := _selected_metric
	_chart.value_format = func(v: float) -> String: return PlanetMath.format_metric(key, v)
	var series: Array[Dictionary] = [{id = -1, data = StatsMath.series(history, key),
		color = meta.get("color", Color.WHITE), width = 2.0, label = meta.get("label", key)}]
	_chart.set_data(StatsMath.series(history, "year"), series)


func _add_metric_row(m: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_metric_box.add_child(row)
	# Garder l'ordre de METRICS même si une mesure apparaît plus tard.
	var order := 0
	for other in PlanetMath.METRICS:
		if other.key == m.key:
			break
		if _metric_rows.has(other.key):
			order += 1
	_metric_box.move_child(row, order)
	var b := Button.new()
	b.text = m.label
	b.flat = true
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Color(0.82, 0.84, 0.92))
	b.add_theme_color_override("font_pressed_color", m.color)
	b.tooltip_text = "Afficher la courbe de cette mesure"
	b.pressed.connect(func() -> void:
		_selected_metric = m.key
		_timer = REFRESH)
	row.add_child(b)
	var value := Label.new()
	value.add_theme_font_size_override("font_size", 15)
	value.add_theme_color_override("font_color", m.color)
	row.add_child(value)
	var arrow := TrendArrow.new()
	arrow.custom_minimum_size = Vector2(14, 14)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(arrow)
	_metric_rows[m.key] = {row = row, value = value, arrow = arrow, button = b}


# --- Espèces ---

func _track_populations() -> void:
	var sim = GameState.sim
	for id in sim.species:
		var info = sim.species[id]
		if not info is Dictionary or not info.get("alive", true):
			_last_population.erase(id)
			_trends.erase(id)
			continue
		var pop := float(info.get("population", 0.0))
		if _last_population.has(id):
			_trends[id] = PlanetMath.population_trend(float(_last_population[id]), pop)
		_last_population[id] = pop


func _refresh_species() -> void:
	var sim = GameState.sim if GameState else null
	if sim == null:
		return
	var rows := []
	for id in sim.species:
		var info = sim.species[id]
		if not info is Dictionary or not info.get("alive", true):
			continue
		if not PlanetMath.species_matches(info, _filters.habitat, _filters.diet, _filters.size):
			continue
		rows.append([int(id), info])
	rows.sort_custom(func(a, b): return float(a[1].get("population", 0)) > float(b[1].get("population", 0)))
	_species_list.clear()
	_species_ids.clear()
	for r in rows:
		var info: Dictionary = r[1]
		var trend := int(_trends.get(r[0], 0))
		var label := "%s   pop. %s" % [str(info.get("name", "#%d" % r[0])),
			StatsMath.format_count(float(info.get("population", 0.0)))]
		if info.get("sapient", false):
			label += "  (consciente)"
		var idx := _species_list.add_item(label, _trend_icons[trend])
		_species_list.set_item_custom_fg_color(idx, MapMath.species_color(r[0]).lightened(0.35))
		_species_list.set_item_tooltip(idx, "%s — %s" % [str(info.get("name", "")),
			"en hausse" if trend > 0 else ("en baisse" if trend < 0 else "stable")])
		_species_ids.append(r[0])
	if rows.is_empty():
		_species_list.add_item("Aucune espèce ne correspond")
		_species_list.set_item_disabled(0, true)
		_species_list.set_item_selectable(0, false)
	var idx := _species_ids.find(_target_id)
	if idx >= 0:
		_species_list.select(idx)


## Petite flèche ▲ / ▼ / = dessinée (indépendante de la police).
func _triangle_icon(trend: int) -> Texture2D:
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := StatsMath.trend_color(trend)
	for y in 12:
		for x in 12:
			var inside := false
			if trend > 0:
				inside = y >= 2 and y <= 10 and absf(x - 5.5) <= (y - 2) * 0.6
			elif trend < 0:
				inside = y >= 1 and y <= 9 and absf(x - 5.5) <= (9 - y) * 0.6
			else:
				inside = x >= 1 and x <= 10 and (y == 3 or y == 4 or y == 7 or y == 8)
			if inside:
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
