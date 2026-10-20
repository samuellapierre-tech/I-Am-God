extends VBoxContainer
## Corps du panneau de gauche en vue GLOBE : la planète entière.
## Chaleur mondiale (jauge, tendance, mini-courbe), ozone, O₂, biomasse, biodiversité, espèces de la
## planète avec ▲▼, courbes tirées de planet_history. Sur une planète vierge : un accueil qui invite
## à semer, sans courbes vides. Données lues via PlanetMath (tolérant aux clés absentes).

const PlanetMath := preload("res://src/ui/stats/planet_math.gd")
const StatsMath := preload("res://src/ui/stats/stats_math.gd")
const StatsChart := preload("res://src/ui/stats/stats_chart.gd")
const SpeciesRow := preload("res://src/ui/stats/species_row.gd")
const TemperatureGauge := preload("res://src/ui/stats/temperature_gauge.gd")
const TrendArrow := preload("res://src/ui/stats/trend_arrow.gd")
const MapMath := preload("res://src/map/map_math.gd")

const MAX_SPECIES := 6
const TILE_METRICS := ["ozone", "oxygen", "biomass", "biodiversity"]
const WELCOME := "Aucune vie. Choisis une semence en bas et clique sur une côte."

## Planète sans vie (pas d'espèce vivante) au dernier rafraîchissement.
var barren := true
## Résumé d'une ligne pour le panneau replié.
var summary := ""

var _temp_label: Label
var _temp_arrow: TrendArrow
var _spark: StatsChart
var _gauge: TemperatureGauge
var _tiles := {}  # key -> {value: Label, arrow: TrendArrow}
var _welcome: Label
var _life_box: VBoxContainer
var _total_label: Label
var _rows_box: VBoxContainer
var _rows := {}  # species_id -> SpeciesRow
var _charts_box: VBoxContainer
var _temp_chart: StatsChart
var _life_chart: StatsChart
var _last_pop := {}
var _trends := {}


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	add_child(_title("Chaleur mondiale"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	_temp_label = Label.new()
	_temp_label.add_theme_font_size_override("font_size", 26)
	row.add_child(_temp_label)
	_temp_arrow = TrendArrow.new()
	_temp_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_temp_arrow)
	_spark = StatsChart.new()
	_spark.compact = true
	_spark.min_span = 1.0
	_spark.custom_minimum_size = Vector2(0, 34)
	_spark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_spark.tooltip_text = "Chaleur mondiale, échantillons récents"
	row.add_child(_spark)
	_gauge = TemperatureGauge.new()
	add_child(_gauge)

	# Atmosphère et vie : quatre tuiles.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	add_child(grid)
	for key in TILE_METRICS:
		var m := PlanetMath.metric(key)
		var tile := HBoxContainer.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.add_theme_constant_override("separation", 4)
		grid.add_child(tile)
		var caption := Label.new()
		caption.text = _short_label(key)
		caption.add_theme_font_size_override("font_size", 13)
		caption.add_theme_color_override("font_color", Color(0.65, 0.69, 0.8))
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.tooltip_text = str(m.get("label", key))
		caption.mouse_filter = Control.MOUSE_FILTER_PASS
		tile.add_child(caption)
		var value := Label.new()
		value.add_theme_font_size_override("font_size", 15)
		value.add_theme_color_override("font_color", m.get("color", Color.WHITE))
		tile.add_child(value)
		var arrow := TrendArrow.new()
		arrow.custom_minimum_size = Vector2(12, 12)
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tile.add_child(arrow)
		_tiles[key] = {value = value, arrow = arrow}

	add_child(HSeparator.new())
	_welcome = Label.new()
	_welcome.text = WELCOME
	_welcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_welcome.custom_minimum_size.x = 320
	_welcome.add_theme_font_size_override("font_size", 17)
	_welcome.add_theme_color_override("font_color", Color(1.0, 0.88, 0.6))
	add_child(_welcome)

	_life_box = VBoxContainer.new()
	_life_box.add_theme_constant_override("separation", 4)
	add_child(_life_box)
	var title_row := HBoxContainer.new()
	_life_box.add_child(title_row)
	var t := _title("Espèces de la planète")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(t)
	_total_label = Label.new()
	_total_label.add_theme_font_size_override("font_size", 15)
	_total_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	title_row.add_child(_total_label)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 0)
	_life_box.add_child(_rows_box)

	_charts_box = VBoxContainer.new()
	_charts_box.add_theme_constant_override("separation", 4)
	_life_box.add_child(_charts_box)
	_charts_box.add_child(HSeparator.new())
	var charts_title := HBoxContainer.new()
	_charts_box.add_child(charts_title)
	var ct := _title("Courbes de la planète")
	ct.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	charts_title.add_child(ct)
	for pair in [["— Chaleur", Color(1.0, 0.62, 0.3)], ["— Espèces vivantes", Color(0.7, 1.0, 0.6)]]:
		var key := Label.new()
		key.text = pair[0]
		key.add_theme_font_size_override("font_size", 12)
		key.add_theme_color_override("font_color", pair[1])
		charts_title.add_child(key)
	_temp_chart = StatsChart.new()
	_temp_chart.min_span = 2.0
	_temp_chart.custom_minimum_size = Vector2(0, 62)
	_temp_chart.value_format = func(v: float) -> String: return StatsMath.format_decimal(v, 1) + "°"
	_charts_box.add_child(_temp_chart)
	_life_chart = StatsChart.new()
	_life_chart.min_span = 5.0
	_life_chart.include_zero = true
	_life_chart.custom_minimum_size = Vector2(0, 62)
	_life_chart.value_format = func(v: float) -> String: return MapMath.group_thousands(int(roundf(v)))
	_charts_box.add_child(_life_chart)


## Met le corps à jour depuis la simulation (appelé par le panneau, ≤ 4 fois par seconde).
func refresh(sim: Object) -> void:
	if sim == null or _temp_label == null:
		return
	var stats := PlanetMath.read_stats(sim, null)
	var history := PlanetMath.read_history(sim)
	var temps := StatsMath.series(history, "temperature_c")
	var years := StatsMath.series(history, "year")
	var t := float(stats.get("temperature_c", NAN))
	_temp_label.text = StatsMath.format_temperature(t) if is_finite(t) else "—"
	_temp_label.add_theme_color_override("font_color", StatsMath.temperature_color(t).lightened(0.15))
	_temp_arrow.trend = StatsMath.trend_of(temps, 16, 0.15)
	if is_finite(t):
		_gauge.set_values(t, t)
	var from := maxi(0, temps.size() - 64)
	var spark: Array[Dictionary] = [{id = -1, data = temps.slice(from), color = StatsMath.temperature_color(t),
		width = 2.0, label = "Monde"}]
	_spark.set_data(years.slice(from), spark)
	_spark.visible = temps.size() >= 2
	for key in TILE_METRICS:
		var tile: Dictionary = _tiles[key]
		tile.value.text = PlanetMath.format_metric(key, stats.get(key))
		tile.arrow.trend = StatsMath.trend_of(StatsMath.series(history, key), 16,
			float(PlanetMath.metric(key).get("trend", 0.0)))

	var alive := _alive_species(sim)
	barren = alive.is_empty()
	_welcome.visible = barren
	_life_box.visible = not barren
	summary = "%s   ·   %s   ·   O₂ %s" % [_temp_label.text,
		"aucune vie" if barren else PlanetMath.format_metric("biodiversity", alive.size()),
		PlanetMath.format_metric("oxygen", stats.get("oxygen"))]
	if barren:
		_clear_rows()
		return
	_refresh_species(alive)
	# Courbes seulement s'il y a de quoi tracer (au moins deux échantillons).
	_charts_box.visible = history.size() >= 2
	if _charts_box.visible:
		var temp_series: Array[Dictionary] = [{id = -1, data = temps, color = Color(1.0, 0.62, 0.3), width = 2.0,
			label = "Chaleur mondiale"}]
		_temp_chart.set_data(years, temp_series)
		var life_series: Array[Dictionary] = [{id = -1, data = StatsMath.series(history, "biodiversity"),
			color = Color(0.7, 1.0, 0.6), width = 2.0, label = "Espèces vivantes"}]
		_life_chart.set_data(years, life_series)


func _alive_species(sim: Object) -> Array:
	var out := []
	if not "species" in sim:
		return out
	var species: Dictionary = sim.get("species")
	for id in species:
		var info = species[id]
		if info is Dictionary and info.get("alive", true):
			out.append([int(id), info])
	out.sort_custom(func(a, b): return float(a[1].get("population", 0)) > float(b[1].get("population", 0)))
	return out


func _refresh_species(alive: Array) -> void:
	var total := 0.0
	for r in alive:
		var pop := float(r[1].get("population", 0.0))
		total += pop
		var id: int = r[0]
		_trends[id] = PlanetMath.population_trend(float(_last_pop.get(id, pop)), pop) if _last_pop.has(id) else 0
		_last_pop[id] = pop
	_total_label.text = PlanetMath.format_metric("biodiversity", alive.size())
	var top := alive.slice(0, MAX_SPECIES)
	var max_pop := 0.0
	for r in top:
		max_pop = maxf(max_pop, float(r[1].get("population", 0.0)))
	var seen := {}
	for i in top.size():
		var id: int = top[i][0]
		var info: Dictionary = top[i][1]
		seen[id] = true
		var row: SpeciesRow = _rows.get(id)
		if row == null:
			row = SpeciesRow.new()
			row.faded.connect(_on_row_faded)
			_rows_box.add_child(row)
			_rows[id] = row
		var traits: Dictionary = info.get("traits", {}) if info.get("traits") is Dictionary else {}
		var entry := {species_id = id, name = str(info.get("name", "#%d" % id)), trend = int(_trends.get(id, 0)),
			role = "sapient" if info.get("sapient", false) else str(traits.get("diet", "omnivore")),
			clade = str(traits.get("clade", info.get("clade", "")))}
		row.set_entry(entry, float(info.get("population", 0.0)), max_pop)
		_rows_box.move_child(row, mini(i, _rows_box.get_child_count() - 1))
	for id in _rows:
		if not seen.has(id) and not _rows[id].gone:
			_rows[id].mark_gone()
			_rows_box.move_child(_rows[id], -1)


func _on_row_faded(id: int) -> void:
	var row: SpeciesRow = _rows.get(id)
	if row:
		_rows.erase(id)
		row.queue_free()


func _clear_rows() -> void:
	for id in _rows:
		var row: SpeciesRow = _rows[id]
		_rows_box.remove_child(row)
		row.queue_free()
	_rows.clear()


func _short_label(key: String) -> String:
	match key:
		"ozone":
			return "Ozone"
		"oxygen":
			return "O₂"
		"biomass":
			return "Biomasse"
		"biodiversity":
			return "Espèces"
	return key


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	return l
