extends RefCounted
## Fonctions pures de la vue parcelle : aucune dépendance aux autoloads ni à l'arbre de scène,
## pour être testées en isolation (tests/test_parcel_view.gd).

## Taille de la parcelle en unités monde (le terrain occupe exactement ce rectangle).
const PARCEL_SIZE := Vector2(1920, 1080)

const CREATURE_DIR := "res://assets/parcel/creatures/"
const STRUCTURE_DIR := "res://assets/parcel/structures/"

## Types de sol dessinés par shaders/parcel_terrain.gdshader (mêmes indices côté shader).
## Les cinq derniers servent au prologue (de la première cellule aux premiers dinosaures).
enum Ground { GRASS, LUSH, DRY, SAND, TUNDRA, SNOW, ROCK, WATER, MUD, CRATER, DIRT, PAVED, URBAN, RUBBLE, TAIGA,
	SEABED, MAT, REEF, BARREN, SWAMP }

## Façons de bouger : marcher, nager en banc, rester fixé (colonies, algues, éponges, plantes),
## ramper sur le fond, voler en zigzag.
enum Locomotion { WALK, SWIM, SESSILE, CRAWL, FLY }

## Usages du sol sous la mer (prologue) : la parcelle est vue à travers l'eau.
const SUBMERGED_USES := ["seabed", "microbial_mat", "reef"]

const BIOME_GROUND := {
	"Abysses": Ground.WATER, "Océan": Ground.WATER, "Glace": Ground.SNOW, "Toundra": Ground.TUNDRA,
	"Taïga": Ground.TAIGA, "Steppe": Ground.DRY, "Forêt tempérée": Ground.GRASS, "Désert": Ground.SAND,
	"Savane": Ground.DRY, "Forêt tropicale": Ground.LUSH, "Montagnes": Ground.ROCK,
}
## L'usage du sol l'emporte sur le biome pour ces valeurs.
const LAND_USE_GROUND := {
	"ocean": Ground.WATER, "ice": Ground.SNOW, "crater": Ground.CRATER, "flooded": Ground.MUD,
	"town": Ground.PAVED, "city": Ground.PAVED, "megacity": Ground.URBAN, "arcology": Ground.URBAN,
	"ruins": Ground.RUBBLE,
	"seabed": Ground.SEABED, "microbial_mat": Ground.MAT, "reef": Ground.REEF, "barren": Ground.BARREN,
	"swamp_forest": Ground.SWAMP,
}
## Sol piétiné / labouré (chemins de terre) selon l'usage.
const LAND_USE_WEAR := {"camp": 0.25, "pasture": 0.35, "farmland": 0.55, "village": 0.6}
## Part de parcel.vegetation réellement visible selon le sol, puis selon l'usage.
const GROUND_VEGETATION := {
	Ground.WATER: 0.0, Ground.SNOW: 0.05, Ground.CRATER: 0.0, Ground.ROCK: 0.35, Ground.SAND: 0.15,
	Ground.TUNDRA: 0.35, Ground.MUD: 0.25, Ground.DIRT: 0.5, Ground.PAVED: 0.3, Ground.URBAN: 0.15,
	Ground.RUBBLE: 0.9, Ground.SEABED: 0.3, Ground.MAT: 0.0, Ground.REEF: 0.35, Ground.BARREN: 0.04,
	Ground.SWAMP: 1.0,
}
const LAND_USE_VEGETATION := {
	"camp": 0.85, "pasture": 0.5, "farmland": 0.4, "village": 0.45, "town": 0.35, "city": 0.25,
	"megacity": 0.15, "arcology": 0.2, "crater": 0.0, "ice": 0.0, "ocean": 0.0, "flooded": 0.4,
}

## Les colonies microbiennes sont minuscules : on les dessine en taches plus grandes que nature.
const MICROBE_SCALE := 3.0

const MIN_CREATURE_LENGTH := 14.0
const MAX_CREATURE_LENGTH := 110.0


# --- Terrain ---

static func ground_kind(land_use: String, biome: String) -> int:
	if LAND_USE_GROUND.has(land_use):
		return LAND_USE_GROUND[land_use]
	return BIOME_GROUND.get(biome, Ground.GRASS)


## État de sol transmis au shader : (type, usure, part de végétation visible).
static func ground_state(land_use: String, biome: String) -> Vector3:
	var kind := ground_kind(land_use, biome)
	var veg: float = GROUND_VEGETATION.get(kind, 1.0) * LAND_USE_VEGETATION.get(land_use, 1.0)
	return Vector3(kind, LAND_USE_WEAR.get(land_use, 0.0), veg)


## Transition de sol en fondu : renvoie [état_a, état_b, blend]. Le shader affiche
## mix(a, b, blend) ; blend avance de 0 à 1 en quelques secondes.
static func next_transition(a: Vector3, b: Vector3, blend: float, target: Vector3) -> Array:
	if target == b:
		return [a, b, blend]
	if blend < 1.0 and target == a:
		# Retour vers l'état de départ : on rembobine le fondu au lieu de sauter.
		return [b, a, 1.0 - blend]
	# Nouvelle cible : on repart de l'état le plus visible à l'écran.
	return [b if blend >= 0.5 else a, target, 0.0]


# --- Créatures ---

## Réconciliation du nombre d'individus affichés avec parcel.fauna[].count.
## active : individus visibles qui restent ; leaving : individus en train de disparaître (fondu).
## Renvoie {revive, spawn, retire} : on ranime d'abord les partants, puis on fait naître,
## ou on fait partir l'excédent. Après application : active == target.
static func reconcile(active: int, leaving: int, target: int) -> Dictionary:
	target = maxi(target, 0)
	var missing := maxi(0, target - active)
	var revive := mini(missing, maxi(leaving, 0))
	return {revive = revive, spawn = missing - revive, retire = maxi(0, active - target)}


static func creature_length(size: float) -> float:
	return lerpf(MIN_CREATURE_LENGTH, MAX_CREATURE_LENGTH, clampf(size, 0.0, 1.0))


## 1 si la parcelle est sous la mer (prologue), 0 sinon.
static func submerged(land_use: String) -> float:
	return 1.0 if land_use in SUBMERGED_USES else 0.0


## Teinte et turbidité de l'eau selon l'âge : rouge-orangé trouble avant la Grande Oxydation
## (océan riche en fer, sans oxygène), puis bleue et claire. Renvoie Color(r, g, b, turbidité).
static func sea_tint(year: float) -> Color:
	var oxygen := smoothstep(-2.5e9, -1.8e9, year)
	var anoxic := Color(0.6, 0.34, 0.16, 0.7)
	var modern := Color(0.07, 0.36, 0.5, 0.28)
	return anoxic.lerp(modern, oxygen)


## État affiché par shaders/parcel_creature.gdshader (0 marche, 1 broute, 2 dort, 3 court,
## 4 à terre) pour un état de CreatureGroup (WANDER 0, GRAZE 1, SLEEP 2, RUN 3, EAT 4, VISIT 5,
## POUNCE 6, DOWN 7, DRINK 8).
static func visual_state(group_state: int) -> float:
	match group_state:
		1, 4:
			return 1.0
		2:
			return 2.0
		3, 6:
			return 3.0
		7:
			return 4.0
	return 0.0


## Couleur de remplacement : teinte du rôle, légèrement décalée par espèce pour les distinguer.
## Vie d'ambiance (purement décorative) : nombre de vols d'oiseaux, d'essaims, d'ombres de
## ptérosaures. Rien dans un cratère, peu en ville, pas d'insectes dans le froid.
## Les oiseaux n'existent qu'après -150 Ma, les insectes volants après -400 Ma ; sous la mer,
## seulement du plancton.
static func ambient_counts(land_use: String, vegetation: float, water: float, temperature_c: float,
		pterosaurs: bool, year := 0.0) -> Dictionary:
	if land_use in SUBMERGED_USES:
		return {flocks = 0, swarms = 0, gliders = 0, plankton = 6}
	var hostile := land_use in ["ocean", "crater", "ice", "barren"] or temperature_c < -5.0
	var flocks := 0
	if land_use != "crater" and year > -150e6:
		flocks = clampi(roundi(vegetation * 3.0) + (1 if water > 0.5 else 0), 0 if hostile else 1, 3)
	var swarms := 0
	if not hostile and temperature_c >= 4.0 and year > -400e6:
		swarms = clampi(roundi((vegetation * 0.6 + water * 0.4) * 8.0), 0, 8)
		if land_use in ["city", "megacity", "arcology"]:
			swarms = mini(swarms, 2)
	return {flocks = flocks, swarms = swarms, gliders = 3 if pterosaurs and land_use != "crater" else 0,
		plankton = 0}


## Centres des essaims d'insectes : stables pour une parcelle, de préférence au bord de l'eau
## (`water_pts` : points de la rivière, peut être vide).
static func swarm_centers(cell: Vector2i, count: int, water_pts: PackedVector2Array) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([cell, "swarms"])
	var out := PackedVector2Array()
	for k in count:
		var p := Vector2(rng.randf_range(0.1, 0.9), rng.randf_range(0.1, 0.9)) * PARCEL_SIZE
		if not water_pts.is_empty() and k % 2 == 0:
			p = water_pts[rng.randi() % water_pts.size()] + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(50.0, 90.0)
		out.append(p.clamp(Vector2(40, 40), PARCEL_SIZE - Vector2(40, 40)))
	return out


# --- Repères permanents (règle de continuité, docs/art/PROMPTS_GPT.md) ---
# Une rivière en S du haut-gauche vers le bas-droite et un gros rocher plat clair au tiers
# gauche, toujours au même endroit pendant toute la partie (dérivés de la graine et de la cellule).

const RIVER_POINTS := 24


static func landmarks(seed_value: int, cell: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, cell, "landmarks"])
	var start := Vector2(rng.randf_range(0.12, 0.24), -0.06) * PARCEL_SIZE
	var end := Vector2(rng.randf_range(0.76, 0.9), 1.06) * PARCEL_SIZE
	var amp := rng.randf_range(0.13, 0.18) * PARCEL_SIZE.y
	var perp := (end - start).orthogonal().normalized()
	var river := PackedVector2Array()
	for k in RIVER_POINTS:
		var t := float(k) / (RIVER_POINTS - 1)
		river.append(start.lerp(end, t) + perp * amp * sin(t * TAU))
	var width := rng.randf_range(38.0, 50.0)
	var radii := Vector2(rng.randf_range(90.0, 115.0), rng.randf_range(62.0, 78.0))
	var rock := Vector2(rng.randf_range(0.2, 0.3), rng.randf_range(0.55, 0.72)) * PARCEL_SIZE
	# Le rocher ne touche jamais la rivière : on l'écarte vers la gauche si besoin.
	while distance_to_polyline(rock, river) < width * 0.5 + radii.x + 50.0 and rock.x > radii.x + 20.0:
		rock.x -= 20.0
	return {river = river, river_width = width, rock_pos = rock, rock_radii = radii,
		rock_angle = rng.randf_range(-0.5, 0.5)}


static func nearest_on_polyline(p: Vector2, pts: PackedVector2Array) -> Vector2:
	var best := Vector2(INF, INF)
	var best_d := INF
	for k in pts.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1])
		var d := q.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = q
	return best


static func distance_to_polyline(p: Vector2, pts: PackedVector2Array) -> float:
	if pts.size() < 2:
		return INF
	return nearest_on_polyline(p, pts).distance_to(p)


## Écarte une structure (centre `p`, demi-taille `half`) de la rivière et du rocher.
## Fonction de la seule position : le résultat reste stable d'une image à l'autre.
static func avoid_landmarks(p: Vector2, half: float, lm: Dictionary) -> Vector2:
	if lm.is_empty():
		return p
	var river: PackedVector2Array = lm.river
	var clear := float(lm.river_width) * 0.5 + half + 8.0
	for i in 2:
		var q := nearest_on_polyline(p, river)
		var d := q.distance_to(p)
		if d < clear:
			var n := (p - q).normalized() if d > 0.01 else Vector2.LEFT
			p = q + n * clear
		var rock: Vector2 = lm.rock_pos
		var r: float = Vector2(lm.rock_radii).x + half + 10.0
		if p.distance_to(rock) < r:
			p = rock + (p - rock).normalized() * r if p != rock else rock + Vector2(0, r)
	return p.clamp(Vector2(half, half), PARCEL_SIZE - Vector2(half, half))


## État de la rivière pour le shader : (eau 0..1, gel 0..1, canal 0..1, pollution 0..1).
static func river_state(land_use: String, water: float, snow: float) -> Vector4:
	var wet := smoothstep(0.08, 0.3, water)
	if land_use in ["flooded", "ocean"]:
		wet = 1.0
	var frozen := 1.0 if land_use == "ice" else smoothstep(0.6, 0.9, snow)
	var canal := 1.0 if land_use in ["town", "city", "megacity", "arcology"] else 0.0
	var polluted: float = {"town": 0.25, "city": 0.6, "megacity": 0.35, "arcology": 0.1, "crater": 0.7}.get(land_use, 0.0)
	return Vector4(wet, frozen, canal, polluted)


## Feu de camp des premiers sapients : à côté du rocher (lieu de rassemblement).
static func campfire_near(lm: Dictionary) -> Vector2:
	var r: Vector2 = lm.rock_radii
	return Vector2(lm.rock_pos) + Vector2(r.x + 45.0, r.y * 0.3)


## Point de berge où boire, du côté de `from`, à `margin` du bord de l'eau.
static func drinking_spot(from: Vector2, river: PackedVector2Array, river_width: float, margin: float) -> Vector2:
	var q := nearest_on_polyline(from, river)
	var n := (from - q).normalized() if from.distance_to(q) > 0.01 else Vector2.LEFT
	return q + n * (river_width * 0.5 + margin)


# --- Temps qui passe (cosmétique : horloge propre à la vue, indépendante de la simulation) ---

## Durées réelles (s) d'une journée et d'une année de la parcelle.
const DAY_LENGTH := 150.0
const YEAR_LENGTH := 600.0
const WEATHERS := ["clear", "rain", "storm", "fog", "snow", "ash"]


## Lumière du jour, 0 (nuit) .. 1 (plein jour). day_t : 0 minuit, 0,25 aube, 0,5 midi, 0,75 crépuscule.
static func daylight(day_t: float) -> float:
	var sun := sin((day_t - 0.25) * TAU)
	return smoothstep(-0.15, 0.25, sun)


## Teinte de la lumière ambiante : bleu nuit, orangé à l'aube et au crépuscule, blanc à midi ;
## grisée par temps couvert (overcast 0..1).
static func sky_color(day_t: float, overcast: float) -> Color:
	var sun := sin((day_t - 0.25) * TAU)
	var light := daylight(day_t)
	var c := Color(0.28, 0.34, 0.58).lerp(Color.WHITE, light)
	var golden := (1.0 - smoothstep(0.0, 0.35, absf(sun))) * light
	c = c.lerp(Color(1.0, 0.78, 0.6), golden * 0.55)
	var grey := c.get_luminance()
	c = c.lerp(Color(grey, grey, grey * 1.05), overcast * 0.5)
	return c.darkened(overcast * 0.22)


## Écart saisonnier de température (°C) : fort en zone tempérée, faible sous les tropiques.
## year_t : 0 plein hiver, 0,5 plein été.
static func season_offset_c(year_t: float, base_c: float) -> float:
	var amp := lerpf(9.0, 2.0, smoothstep(18.0, 28.0, base_c))
	return -amp * cos(year_t * TAU)


## Couverture neigeuse 0..1 selon la température ressentie et l'humidité (pas de neige au désert).
static func snow_cover(effective_c: float, water: float) -> float:
	return (1.0 - smoothstep(-6.0, 2.0, effective_c)) * clampf(0.2 + water * 1.6, 0.0, 1.0)


## Feuillage d'automne 0..1 (zones tempérées, après l'été).
static func autumn(year_t: float, base_c: float) -> float:
	var temperate := smoothstep(-2.0, 4.0, base_c) * (1.0 - smoothstep(20.0, 26.0, base_c))
	return smoothstep(0.58, 0.7, year_t) * (1.0 - smoothstep(0.86, 0.96, year_t)) * temperate


## Météo suivante, tirée selon le climat local. r : aléa 0..1 (déterministe côté appelant).
static func pick_weather(r: float, water: float, effective_c: float, land_use: String) -> String:
	var w := {clear = 3.0, rain = 0.0, storm = 0.0, fog = water * 1.2, snow = 0.0, ash = 0.0}
	if land_use == "crater":
		w.ash = 6.0
	if effective_c < 0.0:
		w.snow = water * 4.0
	else:
		w.rain = water * 3.0
		if water > 0.55 and effective_c > 14.0:
			w.storm = 1.2
	var total := 0.0
	for k in WEATHERS:
		total += w[k]
	var x := clampf(r, 0.0, 0.9999) * total
	for k in WEATHERS:
		x -= w[k]
		if x < 0.0:
			return k
	return "clear"


# --- Assets ---

## Nom de fichier normalisé : minuscules, sans accents, espaces et tirets -> « _ ».
static func slug(text: String) -> String:
	const ACCENTS := {
		"à": "a", "â": "a", "ä": "a", "é": "e", "è": "e", "ê": "e", "ë": "e", "î": "i", "ï": "i",
		"ô": "o", "ö": "o", "ù": "u", "û": "u", "ü": "u", "ç": "c", "æ": "ae", "œ": "oe",
	}
	var out := ""
	for ch in text.strip_edges().to_lower():
		var c: String = ACCENTS.get(ch, ch)
		if c == " " or c == "-":
			out += "_"
		elif (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c.length() > 1:
			out += c
	return out


## Fichiers essayés, du plus précis au plus générique, pour une créature.
static func creature_asset_candidates(clade: String, role: String) -> PackedStringArray:
	var c := slug(clade)
	var out := PackedStringArray()
	if c == "":
		return out
	if role != "":
		out.append(CREATURE_DIR + c + "_" + slug(role) + ".png")
	out.append(CREATURE_DIR + c + ".png")
	return out


## Fichiers essayés pour une structure : variante par usage du sol, puis générique.
static func structure_asset_candidates(kind: String, land_use: String) -> PackedStringArray:
	var k := slug(kind)
	var out := PackedStringArray()
	if k == "":
		return out
	if land_use != "":
		out.append(STRUCTURE_DIR + k + "_" + slug(land_use) + ".png")
	out.append(STRUCTURE_DIR + k + ".png")
	return out


## Premier candidat existant (exists : Callable(path) -> bool), sinon "" (placeholder).
static func resolve_asset(candidates: PackedStringArray, exists: Callable) -> String:
	for path in candidates:
		if exists.call(path):
			return path
	return ""


static func structure_key(s: Dictionary) -> String:
	var p: Vector2 = s.get("pos", Vector2.ZERO)
	return "%s@%d,%d" % [s.get("kind", "?"), roundi(p.x * 10000.0), roundi(p.y * 10000.0)]


# --- Caméra et pouvoirs ---

## Zoom minimal : la parcelle couvre tout l'écran.
static func cover_zoom(viewport: Vector2, parcel: Vector2) -> float:
	return maxf(viewport.x / parcel.x, viewport.y / parcel.y)


## Molette vers l'arrière : zoom suivant, jamais en dessous du zoom de couverture.
static func wheel_out(target_zoom: float, min_zoom: float, step: float) -> float:
	return maxf(target_zoom / step, min_zoom)


## Centre de caméra gardant la vue à l'intérieur de la parcelle.
static func clamp_camera(center: Vector2, zoom: float, viewport: Vector2, parcel: Vector2) -> Vector2:
	var half := viewport * 0.5 / maxf(zoom, 0.0001)
	var out := center
	for axis in 2:
		if half[axis] * 2.0 >= parcel[axis]:
			out[axis] = parcel[axis] * 0.5
		else:
			out[axis] = clampf(center[axis], half[axis], parcel[axis] - half[axis])
	return out


## Une action divine (région + rayon) touche-t-elle la parcelle suivie ? (bouclage en x)
static func region_hits_parcel(region: Vector2i, radius: int, cell: Vector2i, width: int) -> bool:
	var dx := absi(region.x - cell.x)
	if width > 0:
		dx = mini(dx, width - dx)
	var dy := region.y - cell.y
	return dx * dx + dy * dy <= radius * radius


# --- Rendu ---

## Quadrilatère unité centré, UV explicites (image tête vers +x, non retournée), pour les MultiMesh.
static func unit_quad() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([
		Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
