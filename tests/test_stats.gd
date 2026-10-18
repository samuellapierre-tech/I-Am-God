extends RefCounted
## Tests du panneau de statistiques (src/ui/stats/stats_math.gd) : formatage à la française,
## libellés de l'usage du sol, tendances, extraction de parcel.history et mise à l'échelle des courbes.
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const StatsMath := preload("res://src/ui/stats/stats_math.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")


func _expect(got, want, what: String) -> String:
	if got != want:
		return "%s : obtenu %s, attendu %s" % [what, str(got), str(want)]
	return ""


func _near(got: float, want: float, what: String, eps: float = 1e-4) -> String:
	if absf(got - want) > eps:
		return "%s : obtenu %f, attendu %f" % [what, got, want]
	return ""


func _near_v(got: Vector2, want: Vector2, what: String) -> String:
	if absf(got.x - want.x) > 1e-3 or absf(got.y - want.y) > 1e-3:
		return "%s : obtenu %s, attendu %s" % [what, str(got), str(want)]
	return ""


func _first_error(errors: Array) -> String:
	for e in errors:
		if e != "":
			return e
	return ""


func _history() -> Array[Dictionary]:
	return [
		{year = -66_000_000.0, temperature_c = 20.0, global_temperature_c = 14.0, population_total = 5,
			population = {3: 5}},
		{year = -65_000_000.0, temperature_c = 21.5, global_temperature_c = 14.5, population_total = 7,
			population = {3: 4, 7: 3}},
	]


func test_format_decimal() -> String:
	return _first_error([
		_expect(StatsMath.format_decimal(23.44), "23,4", "23,44"),
		_expect(StatsMath.format_decimal(-65.2), "-65,2", "-65,2"),
		_expect(StatsMath.format_decimal(1234.5), "1 234,5", "milliers"),
		_expect(StatsMath.format_decimal(-0.04), "0,0", "pas de « -0,0 »"),
		_expect(StatsMath.format_decimal(3.0, 0), "3", "sans décimale"),
		_expect(StatsMath.format_decimal(0.05, 2), "0,05", "zéros de tête"),
		_expect(StatsMath.format_decimal(NAN), "—", "valeur invalide"),
	])


func test_format_temperature() -> String:
	return _first_error([
		_expect(StatsMath.format_temperature(23.44), "23,4 °C", "température"),
		_expect(StatsMath.format_temperature(-12.0), "-12,0 °C", "température négative"),
		_expect(StatsMath.format_temperature_delta(1.24), "+1,2 °C", "écart positif"),
		_expect(StatsMath.format_temperature_delta(-0.4), "-0,4 °C", "écart négatif"),
		_expect(StatsMath.format_temperature_delta(0.02), "0,0 °C", "écart nul"),
	])


func test_format_axis_year() -> String:
	return _first_error([
		_expect(StatsMath.format_axis_year(-65_200_000.0), "-65,2 Ma", "temps profond"),
		_expect(StatsMath.format_axis_year(-66_000_000.0), "-66,0 Ma", "début de partie"),
		_expect(StatsMath.format_axis_year(-65_234_000.0, 100_000.0), "-65,23 Ma", "fenêtre étroite"),
		_expect(StatsMath.format_axis_year(-65_234_400.0, 10_000.0), "-65,234 Ma", "fenêtre très étroite"),
		_expect(StatsMath.format_axis_year(-1240.0), "1 240 av. J.-C.", "avant notre ère"),
		_expect(StatsMath.format_axis_year(-12_500.0), "12 500 av. J.-C.", "préhistoire"),
		_expect(StatsMath.format_axis_year(2087.0), "2 087", "notre ère"),
		_expect(StatsMath.format_axis_year(-0.2), "1 av. J.-C.", "pas d'an zéro (avant)"),
		_expect(StatsMath.format_axis_year(0.3), "1", "pas d'an zéro (après)"),
	])


func test_format_count() -> String:
	return _first_error([
		_expect(StatsMath.format_count(0.0), "0", "zéro"),
		_expect(StatsMath.format_count(-3.0), "0", "négatif"),
		_expect(StatsMath.format_count(57.4), "57", "petit effectif"),
		_expect(StatsMath.format_count(12_400.0), "12 400", "milliers"),
		_expect(StatsMath.format_count(3_200_000.0), "3,2 M", "millions"),
		_expect(StatsMath.format_count(1_500_000_000.0), "1,5 Md", "milliards"),
	])


func test_land_use_labels() -> String:
	for use in ParcelSim.LAND_USES:
		if not StatsMath.LAND_USE_LABELS.has(use):
			return "usage du sol sans libellé français : " + use
	return _first_error([
		_expect(StatsMath.land_use_label("wild", "Forêt tempérée"), "Forêt sauvage", "forêt"),
		_expect(StatsMath.land_use_label("wild", "Taïga"), "Forêt sauvage", "taïga"),
		_expect(StatsMath.land_use_label("wild", "Désert"), "Désert", "désert"),
		_expect(StatsMath.land_use_label("wild", ""), "Nature sauvage", "sauvage sans biome"),
		_expect(StatsMath.land_use_label("farmland"), "Terres agricoles", "champs"),
		_expect(StatsMath.land_use_label("megacity"), "Mégapole", "mégapole"),
		_expect(StatsMath.land_use_label(""), "Terre inconnue", "vide"),
		_expect(StatsMath.land_use_label("space_port"), "Space Port", "valeur future inconnue"),
	])


func test_roles_and_trend_colors() -> String:
	var colors := []
	for role in ["herbivore", "carnivore", "omnivore", "sapient"]:
		var c := StatsMath.role_color(role)
		for other in colors:
			if c.is_equal_approx(other):
				return "deux rôles partagent la couleur %s" % c
		colors.append(c)
	if StatsMath.trend_color(1).is_equal_approx(StatsMath.trend_color(-1)):
		return "hausse et baisse de même couleur"
	if StatsMath.trend_color(1).g <= StatsMath.trend_color(1).r:
		return "la hausse devrait être verte"
	if StatsMath.trend_color(-1).r <= StatsMath.trend_color(-1).g:
		return "la baisse devrait être rouge"
	return _first_error([
		_expect(StatsMath.role_label("carnivore"), "Prédateur", "libellé prédateur"),
		_expect(StatsMath.role_label("sapient"), "Espèce intelligente", "libellé sapient"),
		_expect(StatsMath.trend_symbol(1), "▲", "symbole hausse"),
		_expect(StatsMath.trend_symbol(-1), "▼", "symbole baisse"),
		_expect(StatsMath.trend_symbol(0), "=", "symbole stable"),
	])


func test_trend_of() -> String:
	return _first_error([
		_expect(StatsMath.trend_of(PackedFloat32Array([1, 2, 3, 4]), 16, 0.1), 1, "hausse"),
		_expect(StatsMath.trend_of(PackedFloat32Array([4, 3, 2, 1]), 16, 0.1), -1, "baisse"),
		_expect(StatsMath.trend_of(PackedFloat32Array([5, 5, 5, 5.05]), 16, 0.1), 0, "bruit sous le seuil"),
		_expect(StatsMath.trend_of(PackedFloat32Array([1, 2, 3]), 16, 0.0), 1, "nombre impair"),
		_expect(StatsMath.trend_of(PackedFloat32Array([10, 10, 10, 10, 1, 2, 3, 4]), 4, 0.1), 1,
			"seule la fenêtre récente compte"),
		_expect(StatsMath.trend_of(PackedFloat32Array([7]), 16, 0.0), 0, "un seul échantillon"),
		_expect(StatsMath.trend_of(PackedFloat32Array(), 16, 0.0), 0, "aucun échantillon"),
	])


func test_temperature_scale_and_color() -> String:
	var err := _first_error([
		_near(StatsMath.temperature_ratio(StatsMath.TEMP_MIN), 0.0, "bas de jauge"),
		_near(StatsMath.temperature_ratio(StatsMath.TEMP_MAX), 1.0, "haut de jauge"),
		_near(StatsMath.temperature_ratio(7.5), 0.5, "milieu de jauge"),
		_near(StatsMath.temperature_ratio(-100.0), 0.0, "borné en bas"),
		_near(StatsMath.temperature_ratio(100.0), 1.0, "borné en haut"),
	])
	if err != "":
		return err
	var cold := StatsMath.temperature_color(-30.0)
	var hot := StatsMath.temperature_color(45.0)
	if cold.b <= cold.r:
		return "le froid devrait être bleu : %s" % cold
	if hot.r <= hot.b:
		return "le chaud devrait être rouge : %s" % hot
	if not StatsMath.temperature_color(0.0).is_equal_approx(Color(0.45, 0.8, 1.0)):
		return "0 °C devrait tomber sur l'étape du dégradé : %s" % StatsMath.temperature_color(0.0)
	if StatsMath.temperature_color(40.0).r < StatsMath.temperature_color(-10.0).r:
		return "le rouge devrait croître avec la chaleur"
	return ""


func test_history_series() -> String:
	var h := _history()
	var temps := StatsMath.series(h, "temperature_c")
	var totals := StatsMath.series(h, "population_total")
	var missing := StatsMath.series(h, "inexistant")
	var sp7 := StatsMath.species_series(h, 7)
	var sp3 := StatsMath.species_series(h, 3)
	if temps.size() != 2 or sp7.size() != 2:
		return "taille des séries : %d / %d" % [temps.size(), sp7.size()]
	return _first_error([
		_near(temps[1], 21.5, "température"),
		_near(totals[0], 5.0, "population totale"),
		_near(missing[0], 0.0, "colonne absente"),
		_near(sp7[0], 0.0, "espèce absente du premier échantillon"),
		_near(sp7[1], 3.0, "espèce arrivée"),
		_near(sp3[1], 4.0, "espèce présente"),
		_expect(StatsMath.series([], "year").size(), 0, "historique vide"),
	])


func test_value_range() -> String:
	return _first_error([
		_near_v(StatsMath.value_range([PackedFloat32Array([0, 10])], 1.0), Vector2(-0.8, 10.8), "marge de 8 %"),
		_near_v(StatsMath.value_range([PackedFloat32Array([5, 10])], 1.0, true), Vector2(0, 10.8), "ancré à 0"),
		_near_v(StatsMath.value_range([PackedFloat32Array([20, 20])], 2.0), Vector2(19, 21), "courbe plate centrée"),
		_near_v(StatsMath.value_range([PackedFloat32Array([0, 0])], 5.0, true), Vector2(0, 5), "effectifs nuls"),
		_near_v(StatsMath.value_range([], 5.0, true), Vector2(0, 5), "aucune série (effectifs)"),
		_near_v(StatsMath.value_range([], 5.0), Vector2(-2.5, 2.5), "aucune série"),
		_near_v(StatsMath.value_range([PackedFloat32Array([1, NAN, 3])], 0.5), Vector2(0.84, 3.16),
			"valeurs invalides ignorées"),
		_near_v(StatsMath.value_range([PackedFloat32Array([2]), PackedFloat32Array([12])], 1.0), Vector2(1.2, 12.8),
			"plusieurs séries"),
	])


func test_scale_points() -> String:
	var rect := Rect2(10, 20, 100, 50)
	var pts := StatsMath.scale_points(PackedFloat32Array([0, 5, 10]), rect, Vector2(0, 10))
	if pts.size() != 3:
		return "nombre de points : %d" % pts.size()
	var err := _first_error([
		_near_v(pts[0], Vector2(10, 70), "premier point (bas gauche)"),
		_near_v(pts[1], Vector2(60, 45), "point central"),
		_near_v(pts[2], Vector2(110, 20), "dernier point (haut droite)"),
	])
	if err != "":
		return err
	var one := StatsMath.scale_points(PackedFloat32Array([5]), rect, Vector2(0, 10))
	if one.size() != 2:
		return "un échantillon devrait donner un trait : %d points" % one.size()
	var clamped := StatsMath.scale_points(PackedFloat32Array([20, -5]), rect, Vector2(0, 10))
	var flat := StatsMath.scale_points(PackedFloat32Array([3, 3]), rect, Vector2(3, 3))
	return _first_error([
		_near_v(one[0], Vector2(10, 45), "trait plat (gauche)"),
		_near_v(one[1], Vector2(110, 45), "trait plat (droite)"),
		_near(clamped[0].y, 20.0, "borné en haut"),
		_near(clamped[1].y, 70.0, "borné en bas"),
		"" if is_finite(flat[0].y) else "écart nul : division par zéro",
		_expect(StatsMath.scale_points(PackedFloat32Array(), rect, Vector2(0, 1)).size(), 0, "série vide"),
	])


func test_sample_index_at() -> String:
	var rect := Rect2(10, 20, 100, 50)
	return _first_error([
		_expect(StatsMath.sample_index_at(10.0, rect, 11), 0, "bord gauche"),
		_expect(StatsMath.sample_index_at(110.0, rect, 11), 10, "bord droit"),
		_expect(StatsMath.sample_index_at(60.0, rect, 11), 5, "milieu"),
		_expect(StatsMath.sample_index_at(-50.0, rect, 11), 0, "hors cadre à gauche"),
		_expect(StatsMath.sample_index_at(500.0, rect, 11), 10, "hors cadre à droite"),
		_expect(StatsMath.sample_index_at(60.0, rect, 1), 0, "un seul échantillon"),
	])


func test_bar_ratio_and_approach() -> String:
	var one_step := StatsMath.approach(0.0, 10.0, 0.1, 6.0)
	var two_steps := StatsMath.approach(StatsMath.approach(0.0, 10.0, 0.05, 6.0), 10.0, 0.05, 6.0)
	if one_step <= 0.0 or one_step >= 10.0:
		return "le lissage devrait avancer sans dépasser : %f" % one_step
	return _first_error([
		_near(StatsMath.bar_ratio(5.0, 10.0), 0.5, "moitié"),
		_near(StatsMath.bar_ratio(20.0, 10.0), 1.0, "borné à 1"),
		_near(StatsMath.bar_ratio(3.0, 0.0), 0.0, "maximum nul"),
		_near(StatsMath.approach(0.0, 10.0, 0.0), 0.0, "delta nul"),
		_near(StatsMath.approach(0.0, 10.0, 100.0), 10.0, "convergence"),
		_near(one_step, two_steps, "indépendant de la cadence d'images"),
	])
