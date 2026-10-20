extends RefCounted
## Statistiques planétaires : définition des mesures, formatage à la française, lecture tolérante
## des données de la simulation, filtres de la liste des espèces. Pur ; testé par tests/test_calm_ui.gd.
##
## Format attendu de la session Planète (lu via has_method / « in », tout est facultatif) :
##   sim.planet_stats() -> {
##     temperature_c: float (moyenne mondiale, °C), ozone: float (0..1, 1 = couche actuelle),
##     oxygen: float (fraction du niveau actuel, 1 = 21 % de l'atmosphère), co2_ppm: float,
##     methane_ppm: float, sea_level_m: float (écart au niveau de départ), ice_fraction: float (0..1),
##     biomass: float (0..1), biodiversity: int (espèces vivantes), extinctions_recent: int,
##     sun_luminosity: float (1 = Soleil actuel), habitability: float (0..1) }
##   sim.planet_history() -> Array[Dictionary] : mêmes clés + year, du plus ancien au plus récent.
## À défaut, les valeurs connues aujourd'hui sont reprises (sim.oxygen, espèces vivantes, chaleur de la
## parcelle) et le panneau tient lui-même un historique.

const StatsMath := preload("res://src/ui/stats/stats_math.gd")
const MapMath := preload("res://src/map/map_math.gd")

## Part d'oxygène dans l'air actuel (1 « niveau actuel » = 20,95 %).
const O2_PRESENT_PERCENT := 20.95
const HISTORY_SIZE := 512

## Mesures dans l'ordre d'affichage. fmt : nom du formatage (format_metric) ; span : écart minimal
## des courbes ; trend : seuil de tendance.
const METRICS := [
	{key = "temperature_c", label = "Chaleur mondiale", fmt = "celsius", span = 2.0, trend = 0.15, color = Color(1.0, 0.62, 0.3)},
	{key = "local_temperature_c", label = "Chaleur locale", fmt = "celsius", span = 2.0, trend = 0.15, color = Color(1.0, 0.8, 0.45)},
	{key = "ozone", label = "Couche d'ozone", fmt = "percent", span = 0.1, trend = 0.01, color = Color(0.55, 0.75, 1.0)},
	{key = "oxygen", label = "Oxygène (O₂)", fmt = "o2", span = 0.05, trend = 0.005, color = Color(0.5, 0.9, 1.0)},
	{key = "co2_ppm", label = "Dioxyde de carbone (CO₂)", fmt = "ppm", span = 50.0, trend = 5.0, color = Color(0.85, 0.75, 0.6)},
	{key = "methane_ppm", label = "Méthane (CH₄)", fmt = "ppm", span = 0.5, trend = 0.05, color = Color(0.8, 0.9, 0.5)},
	{key = "sea_level_m", label = "Niveau des mers", fmt = "meters", span = 10.0, trend = 0.5, color = Color(0.35, 0.6, 1.0)},
	{key = "ice_fraction", label = "Glace", fmt = "percent", span = 0.05, trend = 0.005, color = Color(0.85, 0.95, 1.0)},
	{key = "biomass", label = "Biomasse", fmt = "percent", span = 0.05, trend = 0.005, color = Color(0.5, 0.85, 0.4)},
	{key = "biodiversity", label = "Biodiversité", fmt = "species", span = 5.0, trend = 0.5, color = Color(0.7, 1.0, 0.6)},
	{key = "extinctions_recent", label = "Extinctions récentes", fmt = "count", span = 3.0, trend = 0.5, color = Color(1.0, 0.45, 0.4)},
	{key = "sun_luminosity", label = "Luminosité du Soleil", fmt = "sun", span = 0.02, trend = 0.001, color = Color(1.0, 0.9, 0.45)},
	{key = "habitability", label = "Habitabilité", fmt = "percent", span = 0.1, trend = 0.005, color = Color(0.6, 1.0, 0.75)},
]

const HABITAT_FILTERS := {all = "Tous milieux", marine = "Mer", amphibious = "Rivage", land = "Terre"}
const DIET_FILTERS := {all = "Tous régimes", autotrophe = "Producteurs", herbivore = "Herbivores",
	omnivore = "Omnivores", carnivore = "Carnivores"}
const SIZE_FILTERS := {all = "Toutes tailles", micro = "Microscopiques", small = "Petites",
	medium = "Moyennes", large = "Grandes"}


static func metric(key: String) -> Dictionary:
	for m in METRICS:
		if m.key == key:
			return m
	return {}


## Valeur lisible d'une mesure : « 14,8 °C », « 62 % », « 20,9 % », « 280 ppm », « +12 m »…
static func format_metric(key: String, value: Variant) -> String:
	if not (value is float or value is int) or not is_finite(float(value)):
		return "—"
	var v := float(value)
	match str(metric(key).get("fmt", "")):
		"celsius":
			return StatsMath.format_temperature(v)
		"percent":
			return format_percent(v)
		"o2":
			return StatsMath.format_decimal(v * O2_PRESENT_PERCENT, 1) + " %"
		"ppm":
			return (StatsMath.format_decimal(v, 1) if v < 10.0 else MapMath.group_thousands(int(roundf(v)))) + " ppm"
		"meters":
			var m := int(roundf(v))
			return ("+" if m > 0 else "") + MapMath.group_thousands(m) + " m"
		"species":
			var n := maxi(int(roundf(v)), 0)
			return "%s espèce%s" % [MapMath.group_thousands(n), "s" if n > 1 else ""]
		"count":
			return MapMath.group_thousands(maxi(int(roundf(v)), 0))
		"sun":
			return format_percent(v) + " de l'actuel"
	return StatsMath.format_decimal(v, 2)


## 0,62 -> « 62 % » ; sous 10 %, une décimale (« 4,5 % »).
static func format_percent(fraction: float) -> String:
	var p := fraction * 100.0
	if absf(p) < 10.0 and absf(p) >= 0.05:
		return StatsMath.format_decimal(p, 1) + " %"
	return MapMath.group_thousands(int(roundf(p))) + " %"


## Statistiques courantes : planet_stats() si la simulation l'expose, complétées par ce que l'on sait
## déjà (oxygène, espèces vivantes, chaleur de la parcelle). `parcel` peut être null.
static func read_stats(sim: Object, parcel: Object) -> Dictionary:
	var out := {}
	if sim == null:
		return out
	if sim.has_method("planet_stats"):
		var s = sim.call("planet_stats")
		if s is Dictionary:
			out = (s as Dictionary).duplicate()
	if not out.has("oxygen") and "oxygen" in sim:
		out.oxygen = float(sim.get("oxygen"))
	if not out.has("biodiversity") and sim.has_method("get_alive_species"):
		out.biodiversity = (sim.call("get_alive_species") as Array).size()
	if parcel != null:
		if not out.has("temperature_c") and "global_temperature_c" in parcel:
			out.temperature_c = float(parcel.get("global_temperature_c"))
		if not out.has("local_temperature_c") and "temperature_c" in parcel:
			out.local_temperature_c = float(parcel.get("temperature_c"))
	return out


## Historique planétaire : planet_history() si disponible, sinon [] (le panneau tient le sien).
static func read_history(sim: Object) -> Array:
	if sim != null and sim.has_method("planet_history"):
		var h = sim.call("planet_history")
		if h is Array:
			return h
	return []


## Ajoute un échantillon à un historique borné (le plus ancien sort en premier).
static func push_sample(history: Array, sample: Dictionary, max_size: int = HISTORY_SIZE) -> void:
	if not history.is_empty() and history[-1].get("year") == sample.get("year"):
		history[-1] = sample
	else:
		history.append(sample)
	while history.size() > maxi(max_size, 1):
		history.pop_front()


# --- Espèces : filtres ---

## Classe de taille (traits.size, échelle 0..1).
static func size_class(size: float) -> String:
	if size < 0.03:
		return "micro"
	if size < 0.2:
		return "small"
	if size < 0.55:
		return "medium"
	return "large"


## L'espèce `info` (WorldSim.species[id]) passe-t-elle les filtres ? ("all" = sans filtre)
static func species_matches(info: Dictionary, habitat: String, diet: String, size: String) -> bool:
	var t: Dictionary = info.get("traits", {}) if info.get("traits") is Dictionary else {}
	if habitat != "all" and str(t.get("habitat", "")) != habitat:
		return false
	if diet != "all" and str(t.get("diet", "")) != diet:
		return false
	if size != "all" and size_class(float(t.get("size", 0.3))) != size:
		return false
	return true


## Tendance d'une population entre deux relevés : 1 (▲), -1 (▼) ou 0 sous `relative` d'écart.
static func population_trend(previous: float, current: float, relative: float = 0.05) -> int:
	if previous <= 0.0:
		return 1 if current > 0.0 else 0
	var change := (current - previous) / previous
	if change > relative:
		return 1
	if change < -relative:
		return -1
	return 0
