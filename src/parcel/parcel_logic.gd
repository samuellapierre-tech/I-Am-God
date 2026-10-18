extends RefCounted
## Fonctions pures de la vue parcelle : aucune dépendance aux autoloads ni à l'arbre de scène,
## pour être testées en isolation (tests/test_parcel_view.gd).

## Taille de la parcelle en unités monde (le terrain occupe exactement ce rectangle).
const PARCEL_SIZE := Vector2(1920, 1080)

const CREATURE_DIR := "res://assets/parcel/creatures/"
const STRUCTURE_DIR := "res://assets/parcel/structures/"

## Types de sol dessinés par shaders/parcel_terrain.gdshader (mêmes indices côté shader).
enum Ground { GRASS, LUSH, DRY, SAND, TUNDRA, SNOW, ROCK, WATER, MUD, CRATER, DIRT, PAVED, URBAN, RUBBLE, TAIGA }

## Silhouettes des créatures de remplacement (mêmes indices dans shaders/parcel_creature.gdshader).
enum Shape { QUADRUPED, BIPED, BIRD, LONG_NECK, REPTILE, HUMANOID }

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
}
## Sol piétiné / labouré (chemins de terre) selon l'usage.
const LAND_USE_WEAR := {"camp": 0.25, "pasture": 0.35, "farmland": 0.55, "village": 0.6}
## Part de parcel.vegetation réellement visible selon le sol, puis selon l'usage.
const GROUND_VEGETATION := {
	Ground.WATER: 0.0, Ground.SNOW: 0.05, Ground.CRATER: 0.0, Ground.ROCK: 0.35, Ground.SAND: 0.15,
	Ground.TUNDRA: 0.35, Ground.MUD: 0.25, Ground.DIRT: 0.5, Ground.PAVED: 0.3, Ground.URBAN: 0.15,
	Ground.RUBBLE: 0.9,
}
const LAND_USE_VEGETATION := {
	"camp": 0.85, "pasture": 0.5, "farmland": 0.4, "village": 0.45, "town": 0.35, "city": 0.25,
	"megacity": 0.15, "arcology": 0.2, "crater": 0.0, "ice": 0.0, "ocean": 0.0, "flooded": 0.4,
}

const ROLE_COLORS := {
	"herbivore": Color("e9d8a6"), "carnivore": Color("d1495b"), "omnivore": Color("edae49"),
	"sapient": Color("8ecae6"),
}

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


static func shape_for(clade: String, role: String, size: float) -> int:
	if role == "sapient":
		return Shape.HUMANOID
	match slug(clade):
		"oiseau", "pterosaure":
			return Shape.BIRD
		"reptile":
			return Shape.REPTILE
		"dinosaure":
			if role == "carnivore" or role == "omnivore":
				return Shape.BIPED
			return Shape.LONG_NECK if size >= 0.9 else Shape.QUADRUPED
	return Shape.QUADRUPED


## Couleur de remplacement : teinte du rôle, légèrement décalée par espèce pour les distinguer.
static func species_color(role: String, species_id: int) -> Color:
	var base: Color = ROLE_COLORS.get(role, Color(0.8, 0.8, 0.8))
	var h := posmod(hash(species_id), 1000) / 1000.0 - 0.5
	return Color.from_hsv(fposmod(base.h + h * 0.08, 1.0), clampf(base.s + h * 0.2, 0.0, 1.0),
		clampf(base.v - absf(h) * 0.25, 0.0, 1.0))


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
