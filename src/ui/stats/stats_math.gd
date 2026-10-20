extends RefCounted
## Fonctions pures du panneau de statistiques (sans nœud ni autoload) : formatage à la française,
## libellés de l'usage du sol, couleurs, tendances, lissage et mise à l'échelle des courbes.
## Testées par tests/test_stats.gd.

const MapMath := preload("res://src/map/map_math.gd")

## Bornes de la jauge de chaleur (mêmes bornes que ParcelSim.to_celsius : -30 .. 45 °C).
const TEMP_MIN := -30.0
const TEMP_MAX := 45.0
## Dégradé de la jauge, du glacial au torride : [°C, couleur].
const TEMP_STOPS := [
	[-30.0, Color(0.22, 0.42, 1.0)],
	[0.0, Color(0.45, 0.8, 1.0)],
	[15.0, Color(0.95, 0.92, 0.6)],
	[28.0, Color(1.0, 0.62, 0.25)],
	[45.0, Color(1.0, 0.22, 0.18)],
]

const LAND_USE_LABELS := {
	ocean = "Océan",
	ice = "Banquise",
	wild = "Nature sauvage",
	crater = "Cratère d'impact",
	flooded = "Terres inondées",
	camp = "Campement",
	pasture = "Pâturages",
	farmland = "Terres agricoles",
	village = "Village",
	town = "Bourg",
	city = "Ville",
	megacity = "Mégapole",
	arcology = "Arcologie",
	ruins = "Ruines",
	rewild = "Retour à la nature",
	seabed = "Fonds marins",
	microbial_mat = "Tapis microbiens",
	reef = "Récif",
	barren = "Terres nues",
	swamp_forest = "Forêt marécageuse",
}
## Usages du sol façonnés par une espèce intelligente (teinte dorée dans l'en-tête).
const CIVILIZED_USES := ["camp", "pasture", "farmland", "village", "town", "city", "megacity", "arcology"]
## Usages issus d'une catastrophe ou d'un déclin (teinte grise).
const SCARRED_USES := ["crater", "flooded", "ruins"]

const ROLE_LABELS := {
	herbivore = "Herbivore",
	carnivore = "Prédateur",
	omnivore = "Omnivore",
	sapient = "Espèce intelligente",
	autotrophe = "Producteur",
}
const ROLE_COLORS := {
	herbivore = Color(0.55, 0.85, 0.35),
	carnivore = Color(0.95, 0.38, 0.5),
	omnivore = Color(0.98, 0.72, 0.3),
	sapient = Color(0.68, 0.58, 1.0),
	autotrophe = Color(0.35, 0.8, 0.7),
}

const TREND_UP_COLOR := Color(0.4, 0.9, 0.45)
const TREND_DOWN_COLOR := Color(1.0, 0.35, 0.3)
const TREND_FLAT_COLOR := Color(0.65, 0.68, 0.78)


# --- Formatage ---

## Nombre décimal à la française : virgule, espace entre milliers. -0,0 s'écrit « 0,0 ».
static func format_decimal(v: float, digits: int = 1) -> String:
	if not is_finite(v):
		return "—"
	digits = clampi(digits, 0, 6)
	var scale := int(pow(10.0, digits))
	var n := int(roundf(absf(v) * scale))
	var whole := n / scale
	var text := MapMath.group_thousands(whole)
	if digits > 0:
		text += "," + str(n % scale).pad_zeros(digits)
	return ("-" + text) if v < 0.0 and n != 0 else text


## « 23,4 °C »
static func format_temperature(celsius: float, digits: int = 1) -> String:
	return format_decimal(celsius, digits) + " °C"


## Écart signé : « +1,2 °C », « -0,4 °C », « 0,0 °C ».
static func format_temperature_delta(delta: float) -> String:
	var text := format_temperature(delta)
	return ("+" + text) if not text.begins_with("-") and not text.begins_with("0,0") else text


## Effectif lisible : « 57 », « 12 400 », « 3,2 M », « 1,5 Md ».
static func format_count(n: float) -> String:
	if not is_finite(n) or n <= 0.0:
		return "0"
	if n >= 1_000_000_000.0:
		return format_decimal(n / 1_000_000_000.0, 1) + " Md"
	if n >= 1_000_000.0:
		return format_decimal(n / 1_000_000.0, 1) + " M"
	return MapMath.group_thousands(int(roundf(n)))


## Année courte pour l'axe du temps des courbes : « -65,2 Ma », « 1 240 av. J.-C. », « 2 087 ».
## `span` (années couvertes par la courbe) ajoute des décimales aux Ma quand la fenêtre est étroite,
## pour que deux graduations voisines ne portent pas la même étiquette.
static func format_axis_year(year: float, span: float = 0.0) -> String:
	if not is_finite(year):
		return "—"
	if absf(year) >= 1_000_000.0:
		var digits := 1
		if span > 0.0 and span < 300_000.0:
			digits = 2
		if span > 0.0 and span < 30_000.0:
			digits = 3
		return format_decimal(year / 1_000_000.0, digits) + " Ma"
	var y := maxi(int(roundf(absf(year))), 1)  # pas d'an zéro
	if year < 0.0:
		return "%s av. J.-C." % MapMath.group_thousands(y)
	return MapMath.group_thousands(y)


## Usage du sol en français. « wild » dépend du biome : « Forêt sauvage » sous les arbres.
static func land_use_label(land_use: String, biome: String = "") -> String:
	if land_use == "wild":
		var b := biome.to_lower()
		if b.contains("forêt") or b.contains("taïga"):
			return "Forêt sauvage"
		if b.contains("savane") or b.contains("steppe"):
			return "Plaines sauvages"
		if b.contains("désert"):
			return "Désert"
		if b.contains("toundra") or b.contains("glace"):
			return "Toundra sauvage"
		if b.contains("montagne"):
			return "Montagnes sauvages"
	if LAND_USE_LABELS.has(land_use):
		return LAND_USE_LABELS[land_use]
	if land_use == "":
		return "Terre inconnue"
	return land_use.capitalize()


static func land_use_color(land_use: String) -> Color:
	if land_use in CIVILIZED_USES:
		return Color(1.0, 0.85, 0.5)
	if land_use in SCARRED_USES:
		return Color(0.75, 0.72, 0.7)
	if land_use in ["ocean", "ice"]:
		return Color(0.6, 0.82, 1.0)
	return Color(0.62, 0.9, 0.55)


static func role_label(role: String) -> String:
	return ROLE_LABELS.get(role, role.capitalize())


static func role_color(role: String) -> Color:
	return ROLE_COLORS.get(role, Color(0.7, 0.7, 0.75))


static func trend_color(trend: int) -> Color:
	if trend > 0:
		return TREND_UP_COLOR
	if trend < 0:
		return TREND_DOWN_COLOR
	return TREND_FLAT_COLOR


## Version texte de la flèche (infobulles) ; le panneau dessine la sienne pour ne pas dépendre
## des glyphes de la police.
static func trend_symbol(trend: int) -> String:
	if trend > 0:
		return "▲"
	if trend < 0:
		return "▼"
	return "="


# --- Chaleur ---

## Position 0..1 de la température sur la jauge.
static func temperature_ratio(celsius: float) -> float:
	return clampf((celsius - TEMP_MIN) / (TEMP_MAX - TEMP_MIN), 0.0, 1.0)


## Couleur de la jauge pour une température (bleu glacial -> rouge torride).
static func temperature_color(celsius: float) -> Color:
	if not is_finite(celsius) or celsius <= TEMP_STOPS[0][0]:
		return TEMP_STOPS[0][1]
	for k in range(1, TEMP_STOPS.size()):
		var hi: Array = TEMP_STOPS[k]
		if celsius <= hi[0]:
			var lo: Array = TEMP_STOPS[k - 1]
			return (lo[1] as Color).lerp(hi[1], (celsius - lo[0]) / (hi[0] - lo[0]))
	return TEMP_STOPS[-1][1]


# --- Tendances et séries ---

## Tendance des `window` derniers échantillons : moyenne de la seconde moitié contre celle de la
## première. Renvoie 1 (hausse), -1 (baisse) ou 0 si l'écart ne dépasse pas `threshold`.
static func trend_of(values: PackedFloat32Array, window: int = 16, threshold: float = 0.0) -> int:
	var n := mini(values.size(), maxi(window, 2))
	if n < 2:
		return 0
	var start := values.size() - n
	var half := n / 2
	var first := 0.0
	var second := 0.0
	for i in half:
		first += values[start + i]
	for i in range(half, n):
		second += values[start + i]
	var diff := second / float(n - half) - first / float(half)
	if diff > threshold:
		return 1
	if diff < -threshold:
		return -1
	return 0


## Extrait une colonne numérique de parcel.history ({year, temperature_c, population_total…}).
static func series(history: Array, key: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(history.size())
	for i in history.size():
		var sample = history[i]
		out[i] = float(sample.get(key, 0.0)) if sample is Dictionary else 0.0
	return out


## Effectif d'une espèce dans chaque échantillon (0 quand elle était absente de la parcelle).
static func species_series(history: Array, species_id: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(history.size())
	for i in history.size():
		var sample = history[i]
		var pop = sample.get("population", {}) if sample is Dictionary else {}
		out[i] = float(pop.get(species_id, 0.0)) if pop is Dictionary else 0.0
	return out


# --- Courbes ---

## Bornes verticales (x = min, y = max) couvrant toutes les séries, avec une marge de 8 %.
## L'écart n'est jamais inférieur à `min_span` (une courbe plate reste centrée).
## `include_zero` ancre le bas à 0 (effectifs).
static func value_range(all_series: Array, min_span: float = 1.0, include_zero: bool = false) -> Vector2:
	var lo := INF
	var hi := -INF
	for s in all_series:
		for v in s:
			if is_finite(v):
				lo = minf(lo, v)
				hi = maxf(hi, v)
	if lo > hi:
		return Vector2(0.0, maxf(min_span, 1e-6)) if include_zero else Vector2(-min_span * 0.5, min_span * 0.5)
	if include_zero:
		lo = minf(lo, 0.0)
	var pad := (hi - lo) * 0.08
	hi += pad
	if not include_zero:
		lo -= pad
	if hi - lo < min_span:
		if include_zero and lo >= 0.0:
			hi = lo + min_span
		else:
			var mid := (lo + hi) * 0.5
			lo = mid - min_span * 0.5
			hi = mid + min_span * 0.5
	return Vector2(lo, hi)


## Points d'une courbe dans `rect` : échantillons régulièrement espacés de gauche à droite,
## valeurs projetées entre `y_range.x` (bas) et `y_range.y` (haut), bornées au cadre.
## Un seul échantillon donne un trait plat sur toute la largeur.
static func scale_points(values: PackedFloat32Array, rect: Rect2, y_range: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := values.size()
	if n == 0:
		return pts
	var span := y_range.y - y_range.x
	if absf(span) < 1e-9:
		span = 1.0
	var bottom := rect.position.y + rect.size.y
	if n == 1:
		var y := bottom - clampf((values[0] - y_range.x) / span, 0.0, 1.0) * rect.size.y
		pts.append(Vector2(rect.position.x, y))
		pts.append(Vector2(rect.position.x + rect.size.x, y))
		return pts
	pts.resize(n)
	for i in n:
		var t := clampf((values[i] - y_range.x) / span, 0.0, 1.0) if is_finite(values[i]) else 0.0
		pts[i] = Vector2(rect.position.x + rect.size.x * float(i) / float(n - 1), bottom - t * rect.size.y)
	return pts


## Indice de l'échantillon sous l'abscisse `x` (survol de la courbe).
static func sample_index_at(x: float, rect: Rect2, count: int) -> int:
	if count <= 1 or rect.size.x <= 0.0:
		return 0
	var t := clampf((x - rect.position.x) / rect.size.x, 0.0, 1.0)
	return clampi(int(roundf(t * float(count - 1))), 0, count - 1)


## Part d'une barre proportionnelle (0..1).
static func bar_ratio(value: float, max_value: float) -> float:
	if max_value <= 0.0 or not is_finite(value):
		return 0.0
	return clampf(value / max_value, 0.0, 1.0)


## Lissage exponentiel indépendant de la cadence d'images : `rate` = vitesse (1/s).
static func approach(current: float, target: float, delta: float, rate: float = 6.0) -> float:
	if delta <= 0.0:
		return current
	return target + (current - target) * exp(-rate * delta)
