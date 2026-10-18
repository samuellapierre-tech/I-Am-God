extends CanvasLayer
## Panneau de statistiques de la parcelle suivie, visible dans les deux vues (parcelle et globe) :
## usage du sol et biome, chaleur (locale / mondiale, jauge, tendance, mini-courbe), populations
## (une ligne animée par espèce) et courbes de température et de population tirées de
## parcel.history. Repliable avec la touche S.
##
## Placé en haut de la colonne gauche (la barre du haut du HUD est centrée, le tiroir Chronique s'ouvre
## dessous, y > 664) : ne cache ni le centre de l'écran ni les panneaux de hud.gd.
## L'en-tête tient aussi lieu de fiche de la parcelle (cellule, technologie en infobulle). Ne lit que le contrat ParcelSim
## (GameState.parcel) et se rafraîchit sur GameState.parcel_updated (≤ 4 Hz).

const MapMath := preload("res://src/map/map_math.gd")
const StatsMath := preload("res://src/ui/stats/stats_math.gd")
const StatsChart := preload("res://src/ui/stats/stats_chart.gd")
const SpeciesRow := preload("res://src/ui/stats/species_row.gd")
const TemperatureGauge := preload("res://src/ui/stats/temperature_gauge.gd")
const TrendArrow := preload("res://src/ui/stats/trend_arrow.gd")

const PANEL_POS := Vector2(12, 12)
const PANEL_WIDTH := 360.0
const TOGGLE_KEY := KEY_S
## Échantillons de la mini-courbe de chaleur et fenêtre des tendances.
const SPARK_SAMPLES := 64
const TREND_WINDOW := 16
const TEMP_TREND_THRESHOLD := 0.15
const LOCAL_TEMP_COLOR := Color(1.0, 0.62, 0.3)
const GLOBAL_TEMP_COLOR := Color(0.6, 0.8, 1.0)
const TOTAL_POP_COLOR := Color(1.0, 0.85, 0.5)

var collapsed := false

var _panel: PanelContainer
var _body: VBoxContainer
var _land_label: Label
var _sub_label: Label
var _summary_label: Label
var _toggle_button: Button
var _local_label: Label
var _local_arrow: TrendArrow
var _global_label: Label
var _global_arrow: TrendArrow
var _gauge: TemperatureGauge
var _spark: StatsChart
var _total_label: Label
var _total_arrow: TrendArrow
var _rows_box: VBoxContainer
var _empty_label: Label
var _temp_chart: StatsChart
var _pop_chart: StatsChart
## species_id -> ligne (y compris les lignes d'espèces disparues en train de s'effacer)
var _rows := {}
var _tween: Tween


func _ready() -> void:
	layer = 9  # sous le HUD (10) : ses infobulles et la narration passent devant
	_build()
	GameState.parcel_updated.connect(_refresh)
	GameState.parcel_changed.connect(_on_parcel_changed)
	GameState.era_changed.connect(func(_era: String) -> void: _refresh_header())
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.physical_keycode == TOGGLE_KEY and not (k.ctrl_pressed or k.alt_pressed or k.meta_pressed or k.shift_pressed):
		set_collapsed(not collapsed)
		get_viewport().set_input_as_handled()


func set_collapsed(value: bool) -> void:
	collapsed = value
	_body.visible = not collapsed
	_summary_label.visible = collapsed
	_toggle_button.text = "+" if collapsed else "−"
	_toggle_button.tooltip_text = ("Déplier" if collapsed else "Replier") + " les statistiques (S)"
	if _tween:
		_tween.kill()
	if not collapsed:
		_body.modulate.a = 0.0
		_tween = create_tween()
		_tween.tween_property(_body, "modulate:a", 1.0, 0.2)
	# Le conteneur reprend la hauteur de son contenu.
	_panel.reset_size()
	_panel.call_deferred("reset_size")


# --- Construction ---

func _build() -> void:
	var root := Control.new()
	root.name = "StatsRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	_panel = PanelContainer.new()
	_panel.name = "StatsPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.position = PANEL_POS
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	root.add_child(_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	_panel.add_child(outer)

	# En-tête : usage du sol, biome · ère, bouton replier.
	var header := HBoxContainer.new()
	outer.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", -2)
	header.add_child(titles)
	_land_label = Label.new()
	_land_label.add_theme_font_size_override("font_size", 21)
	_land_label.clip_text = true
	titles.add_child(_land_label)
	_sub_label = Label.new()
	_sub_label.add_theme_font_size_override("font_size", 14)
	_sub_label.add_theme_color_override("font_color", Color(0.65, 0.69, 0.8))
	_sub_label.clip_text = true
	_sub_label.mouse_filter = Control.MOUSE_FILTER_PASS
	titles.add_child(_sub_label)
	_toggle_button = Button.new()
	_toggle_button.focus_mode = Control.FOCUS_NONE
	_toggle_button.custom_minimum_size = Vector2(34, 34)
	_toggle_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_toggle_button.pressed.connect(func() -> void: set_collapsed(not collapsed))
	header.add_child(_toggle_button)

	_summary_label = Label.new()
	_summary_label.add_theme_font_size_override("font_size", 15)
	_summary_label.visible = false
	_summary_label.clip_text = true
	outer.add_child(_summary_label)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 4)
	outer.add_child(_body)
	_build_heat(_body)
	_body.add_child(HSeparator.new())
	_build_populations(_body)
	_body.add_child(HSeparator.new())
	_build_charts(_body)

	set_collapsed(false)


func _build_heat(parent: VBoxContainer) -> void:
	parent.add_child(_title("Chaleur"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	_local_label = Label.new()
	_local_label.add_theme_font_size_override("font_size", 26)
	_local_label.tooltip_text = "Température de la parcelle"
	_local_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_local_label)
	_local_arrow = TrendArrow.new()
	_local_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_local_arrow)
	_spark = StatsChart.new()
	_spark.compact = true
	_spark.min_span = 1.0
	_spark.custom_minimum_size = Vector2(0, 34)
	_spark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_spark.tooltip_text = "Chaleur de la parcelle, échantillons récents"
	row.add_child(_spark)
	var world_box := VBoxContainer.new()
	world_box.add_theme_constant_override("separation", -4)
	row.add_child(world_box)
	var world_title := Label.new()
	world_title.text = "Monde"
	world_title.add_theme_font_size_override("font_size", 12)
	world_title.add_theme_color_override("font_color", Color(0.62, 0.66, 0.78))
	world_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	world_box.add_child(world_title)
	var world_row := HBoxContainer.new()
	world_row.add_theme_constant_override("separation", 4)
	world_box.add_child(world_row)
	_global_label = Label.new()
	_global_label.add_theme_font_size_override("font_size", 17)
	_global_label.add_theme_color_override("font_color", GLOBAL_TEMP_COLOR)
	_global_label.tooltip_text = "Température moyenne de la planète"
	_global_label.mouse_filter = Control.MOUSE_FILTER_PASS
	world_row.add_child(_global_label)
	_global_arrow = TrendArrow.new()
	_global_arrow.custom_minimum_size = Vector2(14, 14)
	_global_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	world_row.add_child(_global_arrow)
	_gauge = TemperatureGauge.new()
	parent.add_child(_gauge)


func _build_populations(parent: VBoxContainer) -> void:
	var title_row := HBoxContainer.new()
	parent.add_child(title_row)
	var title := _title("Populations de la parcelle")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	_total_label = Label.new()
	_total_label.add_theme_font_size_override("font_size", 15)
	_total_label.add_theme_color_override("font_color", TOTAL_POP_COLOR)
	_total_label.tooltip_text = "Total des individus sur la parcelle"
	_total_label.mouse_filter = Control.MOUSE_FILTER_PASS
	title_row.add_child(_total_label)
	_total_arrow = TrendArrow.new()
	_total_arrow.custom_minimum_size = Vector2(14, 14)
	_total_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_total_arrow)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 0)
	parent.add_child(_rows_box)
	_empty_label = Label.new()
	_empty_label.text = "Aucun animal sur la parcelle"
	_empty_label.add_theme_font_size_override("font_size", 14)
	_empty_label.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
	parent.add_child(_empty_label)

	# Légende des pastilles.
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 8)
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(legend)
	for role in ["herbivore", "carnivore", "omnivore", "sapient"]:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 4)
		item.tooltip_text = StatsMath.role_label(role)
		legend.add_child(item)
		var dot := ColorRect.new()
		dot.color = StatsMath.role_color(role)
		dot.custom_minimum_size = Vector2(9, 9)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_PASS
		item.add_child(dot)
		var label := Label.new()
		label.text = "Intelligente" if role == "sapient" else StatsMath.role_label(role)
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", StatsMath.role_color(role))
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		item.add_child(label)


func _build_charts(parent: VBoxContainer) -> void:
	var title_row := HBoxContainer.new()
	parent.add_child(title_row)
	var title := _title("Courbes")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	for pair in [["Parcelle", LOCAL_TEMP_COLOR], ["Monde", GLOBAL_TEMP_COLOR], ["Population", TOTAL_POP_COLOR]]:
		var key := Label.new()
		key.text = "— " + String(pair[0])
		key.add_theme_font_size_override("font_size", 12)
		key.add_theme_color_override("font_color", pair[1])
		title_row.add_child(key)

	_temp_chart = StatsChart.new()
	_temp_chart.min_span = 2.0
	_temp_chart.custom_minimum_size = Vector2(0, 62)
	_temp_chart.value_format = func(v: float) -> String: return StatsMath.format_decimal(v, 1) + "°"
	parent.add_child(_temp_chart)
	_pop_chart = StatsChart.new()
	_pop_chart.min_span = 5.0
	_pop_chart.include_zero = true
	_pop_chart.custom_minimum_size = Vector2(0, 62)
	_pop_chart.value_format = func(v: float) -> String: return StatsMath.format_count(v)
	parent.add_child(_pop_chart)


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	return l


## Même habillage que hud.gd (panneaux sombres bordés d'or).
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
	normal.set_content_margin_all(4)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.2, 0.21, 0.32, 0.95)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", hover)
	t.set_color("font_color", "Label", Color(0.9, 0.9, 0.95))
	t.set_color("font_color", "Button", Color(0.88, 0.88, 0.95))
	t.set_font_size("font_size", "Button", 18)
	var sep := StyleBoxLine.new()
	sep.color = Color(0.85, 0.7, 0.35, 0.18)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 6)
	return t


# --- Mise à jour ---

func _on_parcel_changed(_cell: Vector2i) -> void:
	for id in _rows:
		var row: SpeciesRow = _rows[id]
		_rows_box.remove_child(row)
		row.queue_free()
	_rows.clear()
	_temp_chart.reset()
	_pop_chart.reset()
	_spark.reset()
	_refresh()


func _refresh() -> void:
	var p = GameState.parcel
	if p == null or _panel == null:
		return
	_refresh_header()
	var history: Array = p.history
	var temps := StatsMath.series(history, "temperature_c")
	var globals := StatsMath.series(history, "global_temperature_c")
	var totals := StatsMath.series(history, "population_total")
	var years := StatsMath.series(history, "year")

	# Chaleur.
	var local_c: float = p.temperature_c
	var global_c: float = p.global_temperature_c
	_local_label.text = StatsMath.format_temperature(local_c)
	_local_label.add_theme_color_override("font_color", StatsMath.temperature_color(local_c).lightened(0.15))
	_local_arrow.trend = StatsMath.trend_of(temps, TREND_WINDOW, TEMP_TREND_THRESHOLD)
	_global_label.text = StatsMath.format_temperature(global_c)
	_global_arrow.trend = StatsMath.trend_of(globals, TREND_WINDOW, TEMP_TREND_THRESHOLD)
	_gauge.set_values(local_c, global_c)
	var spark_from := maxi(0, temps.size() - SPARK_SAMPLES)
	var spark: Array[Dictionary] = [{id = -1, data = temps.slice(spark_from),
		color = StatsMath.temperature_color(local_c), width = 2.0, label = "Parcelle"}]
	_spark.set_data(years.slice(spark_from), spark)

	# Populations.
	var fauna: Array = p.fauna
	var total := 0.0
	var max_count := 0.0
	for f in fauna:
		var c := _count_of(f)
		total += c
		max_count = maxf(max_count, c)
	var seen := {}
	for i in fauna.size():
		var f: Dictionary = fauna[i]
		var id := int(f.get("species_id", -1))
		seen[id] = true
		var row: SpeciesRow = _rows.get(id)
		if row == null:
			row = SpeciesRow.new()
			row.hover_changed.connect(_on_row_hover)
			row.faded.connect(_on_row_faded)
			_rows_box.add_child(row)
			_rows[id] = row
		row.set_entry(f, _count_of(f), max_count)
		_rows_box.move_child(row, mini(i, _rows_box.get_child_count() - 1))
	for id in _rows:
		if not seen.has(id) and not _rows[id].gone:
			_rows[id].mark_gone()
			_rows_box.move_child(_rows[id], -1)
	_empty_label.visible = _rows.is_empty()
	_total_label.text = "%s ind." % StatsMath.format_count(total)
	_total_arrow.trend = StatsMath.trend_of(totals, TREND_WINDOW, maxf(1.0, total * 0.05))
	_summary_label.text = "%s   ·   %s individus   ·   monde %s" % [StatsMath.format_temperature(local_c),
		StatsMath.format_count(total), StatsMath.format_temperature(global_c)]
	_summary_label.add_theme_color_override("font_color", StatsMath.temperature_color(local_c).lightened(0.2))

	# Courbes.
	var temp_series: Array[Dictionary] = [
		{id = -2, data = globals, color = GLOBAL_TEMP_COLOR, width = 1.5, label = "Monde"},
		{id = -1, data = temps, color = LOCAL_TEMP_COLOR, width = 2.0, label = "Parcelle"},
	]
	_temp_chart.set_data(years, temp_series)
	var pop_series: Array[Dictionary] = []
	for id in _rows:
		var row: SpeciesRow = _rows[id]
		pop_series.append({id = id, data = StatsMath.species_series(history, id),
			color = MapMath.species_color(id), width = 1.5, label = row.species_name, hover_only = true})
	pop_series.append({id = -1, data = totals, color = TOTAL_POP_COLOR, width = 2.0, label = "Total"})
	_pop_chart.set_data(years, pop_series)
	_panel.call_deferred("reset_size")


func _refresh_header() -> void:
	var p = GameState.parcel
	if p == null:
		return
	var use := String(p.land_use)
	_land_label.text = StatsMath.land_use_label(use, String(p.biome))
	_land_label.add_theme_color_override("font_color", StatsMath.land_use_color(use))
	var era: String = GameState.sim.current_era() if GameState.sim != null else ""
	var parts := PackedStringArray()
	for s in [String(p.biome), era]:
		if s != "":
			parts.append(s)
	_sub_label.text = "  ·  ".join(parts)
	var tip := "Parcelle suivie : cellule (%d, %d)" % [p.cell.x, p.cell.y]
	if "tech" in p:
		tip += "
Technologie locale : %d %%" % int(float(p.tech) * 100.0)
	_sub_label.tooltip_text = tip
	_land_label.tooltip_text = tip


## Effectif affiché : un futur champ `population` (effectif réel) l'emporte sur `count`
## (individus dessinés, 0..MAX_VISIBLE) — le contrat autorise l'ajout de champs.
func _count_of(entry: Dictionary) -> float:
	return float(entry.get("population", entry.get("count", 0)))


func _on_row_hover(species_id: int, hovered: bool) -> void:
	if hovered:
		_pop_chart.highlight_id = species_id
	elif _pop_chart.highlight_id == species_id:
		_pop_chart.highlight_id = -1


func _on_row_faded(species_id: int) -> void:
	var row: SpeciesRow = _rows.get(species_id)
	if row == null:
		return
	_rows.erase(species_id)
	if _pop_chart.highlight_id == species_id:
		_pop_chart.highlight_id = -1
	row.queue_free()
	_empty_label.visible = _rows.is_empty()
	_panel.call_deferred("reset_size")
