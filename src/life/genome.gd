extends RefCounted
## Génome étendu des espèces (chantier « Espèces infinies », docs/GENESE.md).
##
## Le génome vit dans le dictionnaire `traits` de chaque espèce, à côté des traits de la
## simulation (size, diet, habitat, complexity…), sous des clés plates que la vue rapprochée, le
## narrateur et l'interface lisent directement :
## - body_plan : "unicellulaire" | "colonial" | "radial" | "bilatéral"
## - skeleton : "aucun" | "hydrostatique" | "coquille" | "exosquelette" | "endosquelette"
## - limbs : nombre de membres (pattes, nageoires, bras ou tentacules) ; wings : ailes
## - locomotion : "fixe" | "dérive" | "nage" | "rampe" | "marche" | "saut" | "vol"
## - milieu : "abysses" | "mer peu profonde" | "eau douce" | "terre" | "air"
## - covering : "membrane" | "carapace" | "écailles" | "plumes" | "poils" | "peau nue" | "écorce" | "frondes"
## - metabolism : "chimiosynthèse" | "photosynthèse" | "hétérotrophe" ; warm_blooded : sang chaud
## - senses : sous-ensemble de SENSES ; weapons : sous-ensemble de WEAPONS
## - sociability, fertility : 0..1 ; lifespan : durée de vie en années
## - hue, sat, val : couleur de base (HSV 0..1) ; pattern : "uni" | "rayé" | "tacheté" | "ocellé"
## - biolum : bioluminescence
## - gseed : graine propre à l'espèce (noms, descriptions, variations d'apparence)
## - free_evolution : lignée semée par le joueur ou façonnée (chimère) : ses grandes innovations
##   (multicellularité, squelette, sortie des eaux…) naissent du génome lui-même, et son clade
##   en est déduit. Les autres lignées suivent Species.TRANSITIONS pour ces grandes étapes.
## - innovations : innovations cumulées de la lignée ; novelties : celles apparues à la naissance
##   de l'espèce (vide le plus souvent : les grandes innovations sont rares et marquantes)
##
## Les contraintes sont physiques (violations()) : pas de vol sans ailes ni oxygène, pas de grande
## taille terrestre sans squelette, pas de poils sans amniote, etc. Ce script ne consomme jamais le
## générateur partagé de WorldSim : les appelants lui passent un générateur local.

const BODY_PLANS := ["unicellulaire", "colonial", "radial", "bilatéral"]
const SKELETONS := ["aucun", "hydrostatique", "coquille", "exosquelette", "endosquelette"]
const LOCOMOTIONS := ["fixe", "dérive", "nage", "rampe", "marche", "saut", "vol"]
const MILIEUX := ["abysses", "mer peu profonde", "eau douce", "terre", "air"]
const COVERINGS := ["membrane", "carapace", "écailles", "plumes", "poils", "peau nue", "écorce", "frondes"]
const METABOLISMS := ["chimiosynthèse", "photosynthèse", "hétérotrophe"]
const SENSES := ["yeux", "électroréception", "écholocation"]
const WEAPONS := ["cornes", "crocs", "venin", "épines", "pinces", "griffes"]
const PATTERNS := ["uni", "rayé", "tacheté", "ocellé"]

const GENOME_KEYS := ["body_plan", "skeleton", "limbs", "wings", "locomotion", "milieu", "covering",
	"metabolism", "warm_blooded", "senses", "weapons", "sociability", "lifespan", "fertility", "hue",
	"sat", "val", "pattern", "biolum", "gseed"]

const HABITAT_MILIEUX := {
	"marine": ["mer peu profonde", "abysses"], "amphibious": ["eau douce", "mer peu profonde"],
	"land": ["terre", "air"],
}
const MILIEU_HABITAT := {
	"abysses": "marine", "mer peu profonde": "marine", "eau douce": "amphibious", "terre": "land",
	"air": "land",
}
const AQUATIC := ["abysses", "mer peu profonde", "eau douce"]

## Tailles maximales (échelle de `size`) selon le soutien du corps, sur terre et dans l'eau :
## l'eau porte les corps mous, la terre exige un squelette.
const LAND_SIZE := {"aucun": 0.12, "hydrostatique": 0.12, "coquille": 0.15, "exosquelette": 0.2, "endosquelette": 1.0}
const WATER_SIZE := {"aucun": 0.5, "hydrostatique": 0.5, "coquille": 0.55, "exosquelette": 0.45, "endosquelette": 1.0}
const UNICELL_MAX_SIZE := 0.1
const COLONY_MAX_SIZE := 0.25
## Producteurs terrestres : au-delà, il faut un tronc (écorce).
const SOFT_PLANT_MAX_SIZE := 0.3
const FLIGHT_MAX_SIZE := 0.7
## Oxygène (fraction du niveau actuel) nécessaire au vol et au sang chaud.
const FLIGHT_OXYGEN := 0.15
const WARM_OXYGEN := 0.2

## Les grandes innovations (rares, marquantes) ; les autres sont des nouveautés mineures.
const MAJOR_INNOVATIONS := ["cellule à noyau", "multicellularité", "symétrie bilatérale",
	"exosquelette", "squelette", "sortie des eaux", "œuf amniotique", "sang chaud", "vol",
	"intelligence", "photosynthèse"]
const MAX_INNOVATIONS := 16
## Seuil d'intelligence où le narrateur parle d'une innovation (bien avant la sapience).
const INTELLIGENCE_MARK := 0.5

## Génome typique de chaque clade connu : valeurs permises (la première est la plus courante).
## `prod` : 0 animal, 1 producteur, 2 l'un ou l'autre ; `cx` : complexité permise ; `hab` : milieux
## de la simulation. Les lignées de ces clades mutent dans ces bornes (le clade reste vrai).
const CLADE_GENOME := {
	"microbe": {prod = 2, cx = [0, 1], hab = ["marine", "amphibious"], plan = ["unicellulaire"], skel = ["aucun"], loco = ["dérive", "nage", "fixe"], cover = ["membrane"], warm = [false], wings = [false]},
	"algue": {prod = 1, cx = [1, 2], hab = ["marine", "amphibious"], plan = ["unicellulaire", "colonial", "radial"], skel = ["aucun"], loco = ["dérive", "fixe"], cover = ["membrane", "frondes"], warm = [false], wings = [false]},
	"plante": {prod = 1, cx = [2, 2], hab = ["land", "amphibious"], plan = ["colonial", "radial"], skel = ["aucun"], loco = ["fixe"], cover = ["frondes", "écorce"], warm = [false], wings = [false]},
	"éponge": {prod = 0, cx = [2, 3], hab = ["marine", "amphibious"], plan = ["colonial", "radial"], skel = ["aucun", "hydrostatique"], loco = ["fixe", "dérive", "nage"], cover = ["peau nue", "membrane"], warm = [false], wings = [false]},
	"arthropode": {limbs = [6, 14], prod = 0, cx = [3, 3], hab = ["marine", "amphibious"], plan = ["bilatéral"], skel = ["exosquelette"], loco = ["rampe", "marche", "nage"], cover = ["carapace"], warm = [false], wings = [false]},
	"mollusque": {prod = 0, cx = [3, 3], hab = ["marine", "amphibious"], plan = ["bilatéral"], skel = ["coquille", "hydrostatique", "aucun"], loco = ["rampe", "nage", "fixe"], cover = ["carapace", "peau nue"], warm = [false], wings = [false]},
	"poisson": {prod = 0, cx = [4, 4], hab = ["marine", "amphibious"], plan = ["bilatéral"], skel = ["endosquelette"], loco = ["nage"], cover = ["écailles", "peau nue", "carapace"], warm = [false], wings = [false]},
	"insecte": {limbs = [6, 6], prod = 0, cx = [3, 3], hab = ["land"], plan = ["bilatéral"], skel = ["exosquelette"], loco = ["marche", "vol", "saut", "rampe"], cover = ["carapace"], warm = [false], wings = [true, false]},
	"amphibien": {prod = 0, cx = [5, 5], hab = ["amphibious"], plan = ["bilatéral"], skel = ["endosquelette"], loco = ["marche", "nage", "saut", "rampe"], cover = ["peau nue"], warm = [false], wings = [false]},
	"reptile": {prod = 0, cx = [6, 6], hab = ["land"], plan = ["bilatéral"], skel = ["endosquelette"], loco = ["marche", "rampe"], cover = ["écailles", "carapace"], warm = [false], wings = [false]},
	"synapside": {limbs = [4, 4], prod = 0, cx = [6, 6], hab = ["land"], plan = ["bilatéral"], skel = ["endosquelette"], loco = ["marche", "rampe"], cover = ["peau nue", "écailles", "poils"], warm = [false, true], wings = [false]},
	"dinosaure": {limbs = [4, 4], prod = 0, cx = [6, 6], hab = ["land"], plan = ["bilatéral"], skel = ["endosquelette"], loco = ["marche", "saut"], cover = ["écailles", "plumes"], warm = [true, false], wings = [false]},
	"ptérosaure": {limbs = [4, 4], prod = 0, cx = [6, 6], hab = ["land"], plan = ["bilatéral"], skel = ["endosquelette"], loco = ["vol", "marche"], cover = ["poils", "peau nue"], warm = [true], wings = [true]},
	"oiseau": {limbs = [4, 4], prod = 0, cx = [6, 6], hab = ["land"], plan = ["bilatéral"], skel = ["endosquelette"], loco = ["vol", "marche", "saut"], cover = ["plumes"], warm = [true], wings = [true]},
	"mammifère": {prod = 0, cx = [6, 6], hab = ["land"], plan = ["bilatéral"], skel = ["endosquelette"], loco = ["marche", "saut", "rampe", "vol"], cover = ["poils", "peau nue"], warm = [true], wings = [false, true]},
	"primate": {limbs = [4, 4], prod = 0, cx = [6, 6], hab = ["land"], plan = ["bilatéral"], skel = ["endosquelette"], loco = ["marche", "saut"], cover = ["poils"], warm = [true], wings = [false]},
}


# =============================================================================================
# Lecture
# =============================================================================================

static func is_producer(t: Dictionary) -> bool:
	return String(t.get("diet", "")) == "autotrophe"


static func cx(t: Dictionary) -> float:
	return float(t.get("complexity", 6.0))


static func habitat(t: Dictionary) -> String:
	return String(t.get("habitat", "land"))


static func plan(t: Dictionary) -> String:
	return String(t.get("body_plan", "bilatéral"))


static func skeleton(t: Dictionary) -> String:
	return String(t.get("skeleton", "aucun"))


static func is_aquatic(t: Dictionary) -> bool:
	return AQUATIC.has(String(t.get("milieu", ""))) if t.has("milieu") else habitat(t) != "land"


static func is_free(t: Dictionary) -> bool:
	return bool(t.get("free_evolution", false))


static func has_genome(t: Dictionary) -> bool:
	return t.has("body_plan") and t.has("locomotion") and t.has("gseed")


## Le clade borne-t-il les mutations du génome ? (lignées non libres d'un clade connu)
static func _limited(t: Dictionary) -> bool:
	return not is_free(t) and CLADE_GENOME.has(String(t.get("clade", "")))


# =============================================================================================
# Valeurs permises par la physique (et par le clade pour les lignées non libres)
# =============================================================================================

static func allowed_plans(t: Dictionary) -> Array:
	var c := cx(t)
	if c < 1.0:
		return ["unicellulaire"]
	if c < 2.0:
		return ["unicellulaire", "colonial"]
	if is_producer(t):
		if habitat(t) == "land" and float(t.get("size", 0.0)) > SOFT_PLANT_MAX_SIZE:
			return ["radial"]
		return ["colonial", "radial"]
	if c < 3.0:
		return ["colonial", "radial"]
	if c < 4.0:
		if habitat(t) == "land":
			return ["bilatéral"]
		return ["bilatéral", "radial", "colonial"]
	return ["bilatéral"]


static func allowed_skeletons(t: Dictionary) -> Array:
	var p := plan(t)
	if p == "unicellulaire" or p == "colonial" or is_producer(t):
		return ["aucun"]
	if p == "radial":
		return ["aucun", "hydrostatique"]
	if cx(t) >= 4.0:
		return ["endosquelette"]
	return ["hydrostatique", "aucun", "coquille", "exosquelette"]


## [min, max] du nombre de membres ; `even` : par paires.
static func limb_range(t: Dictionary) -> Array:
	var p := plan(t)
	if p == "unicellulaire" or p == "colonial" or is_producer(t):
		return [0, 0]
	if p == "radial":
		return [0, 12]
	var lr := [0, 10]
	match skeleton(t):
		"exosquelette":
			lr = [6, 14]
		"endosquelette":
			lr = [0, 4]
	if _limited(t) and CLADE_GENOME[String(t.clade)].has("limbs"):
		var cl: Array = CLADE_GENOME[String(t.clade)].limbs
		if int(cl[0]) >= int(lr[0]) and int(cl[1]) <= int(lr[1]):
			lr = cl
	return lr


static func limbs_paired(t: Dictionary) -> bool:
	var s := skeleton(t)
	return plan(t) == "bilatéral" and (s == "exosquelette" or s == "endosquelette")


static func wings_allowed(t: Dictionary) -> bool:
	if is_producer(t) or plan(t) != "bilatéral" or habitat(t) != "land":
		return false
	var s := skeleton(t)
	var limbs := int(t.get("limbs", 0))
	if s == "endosquelette":
		return limbs >= 4
	return s == "exosquelette" and limbs >= 6


static func allowed_milieux(t: Dictionary) -> Array:
	return HABITAT_MILIEUX.get(habitat(t), ["mer peu profonde"])


static func flight_possible(t: Dictionary, oxygen: float) -> bool:
	if not bool(t.get("wings", false)) or not wings_allowed(t):
		return false
	if float(t.get("size", 0.0)) > FLIGHT_MAX_SIZE or oxygen < FLIGHT_OXYGEN:
		return false
	if skeleton(t) == "endosquelette" and not bool(t.get("warm_blooded", false)):
		return false
	return float(t.get("size", 0.0)) <= LAND_SIZE[skeleton(t)]


static func allowed_locos(t: Dictionary, oxygen := 1.0) -> Array:
	var p := plan(t)
	var water := habitat(t) != "land" and String(t.get("milieu", "mer peu profonde")) != "terre"
	if habitat(t) == "land":
		water = false
	if is_producer(t):
		if water and (p == "unicellulaire" or p == "colonial"):
			return ["dérive", "fixe"]
		return ["fixe"]
	if p == "unicellulaire":
		return ["dérive", "nage", "fixe"] if water else ["fixe"]
	if p == "colonial":
		return ["fixe", "dérive"] if water else ["fixe"]
	if p == "radial":
		return ["fixe", "dérive", "nage"] if water else ["fixe"]
	var s := skeleton(t)
	var limbs := int(t.get("limbs", 0))
	var legged := (s == "exosquelette" and limbs >= 6) or (s == "endosquelette" and limbs >= 2) \
		or (s != "endosquelette" and s != "exosquelette" and limbs >= 6)
	var out := []
	if water:
		out.append("nage")
		out.append("rampe")
		if legged:
			out.append("marche")
		if s == "coquille" or s == "exosquelette" or s == "hydrostatique":
			out.append("fixe")
		return out
	out.append("rampe")
	if legged and (s == "endosquelette" or s == "exosquelette"):
		out.append("marche")
		if limbs >= 4:
			out.append("saut")
	if flight_possible(t, oxygen):
		out.append("vol")
	return out


static func allowed_covers(t: Dictionary) -> Array:
	var p := plan(t)
	if is_producer(t):
		if p == "unicellulaire":
			return ["membrane"]
		if p == "colonial":
			return ["frondes", "membrane"]
		if habitat(t) == "land":
			return ["écorce"] if float(t.get("size", 0.0)) > SOFT_PLANT_MAX_SIZE else ["frondes", "écorce"]
		return ["frondes"]
	if p == "unicellulaire":
		return ["membrane"]
	if p == "colonial":
		return ["membrane", "peau nue"]
	if p == "radial":
		return ["peau nue", "membrane"]
	match skeleton(t):
		"exosquelette":
			return ["carapace"]
		"coquille":
			return ["carapace", "peau nue"]
		"endosquelette":
			var out := ["écailles", "peau nue", "carapace"]
			if habitat(t) == "land":
				out.append("plumes")
			if cx(t) >= 6.0:
				out.append("poils")
			return out
	return ["peau nue"]


static func allowed_senses(t: Dictionary) -> Array:
	var p := plan(t)
	if is_producer(t) or p == "unicellulaire" or p == "colonial":
		return []
	if p == "radial":
		return ["yeux"]
	var out := ["yeux"]
	if skeleton(t) == "endosquelette":
		if habitat(t) != "land":
			out.append("électroréception")
		if bool(t.get("warm_blooded", false)):
			out.append("écholocation")
	return out


static func allowed_weapons(t: Dictionary) -> Array:
	var p := plan(t)
	if p == "unicellulaire":
		return []
	if is_producer(t) or p != "bilatéral":
		return ["épines", "venin"]
	var s := skeleton(t)
	var out := ["venin", "épines"]
	if s == "exosquelette":
		out.append("pinces")
	if s == "endosquelette":
		out.append("crocs")
		if int(t.get("limbs", 0)) >= 2 and habitat(t) != "marine":
			out.append("griffes")
	if habitat(t) == "land" and (s == "endosquelette" or s == "exosquelette"):
		out.append("cornes")
	return out


static func warm_allowed(t: Dictionary) -> bool:
	return not is_producer(t) and skeleton(t) == "endosquelette" and cx(t) >= 6.0


static func size_limit(t: Dictionary) -> float:
	var p := plan(t)
	var lim := 1.0
	if p == "unicellulaire":
		lim = UNICELL_MAX_SIZE
	elif is_producer(t):
		if p == "colonial":
			lim = SOFT_PLANT_MAX_SIZE
		elif habitat(t) == "land":
			lim = 1.0 if String(t.get("covering", "")) == "écorce" else SOFT_PLANT_MAX_SIZE
		else:
			lim = 0.5
	elif p == "colonial":
		lim = COLONY_MAX_SIZE
	elif p == "radial":
		lim = 0.5
	else:
		lim = float((LAND_SIZE if habitat(t) == "land" else WATER_SIZE).get(skeleton(t), 1.0))
	if String(t.get("locomotion", "")) == "vol":
		lim = minf(lim, FLIGHT_MAX_SIZE)
	return lim


## Intersection avec les valeurs du clade (lignées non libres) si elle n'est pas vide.
static func _clade_filter(t: Dictionary, key: String, values: Array) -> Array:
	if not _limited(t):
		return values
	var allowed: Array = CLADE_GENOME[String(t.clade)].get(key, [])
	if allowed.is_empty():
		return values
	var out := []
	for v in allowed:
		if values.has(v):
			out.append(v)
	return out if not out.is_empty() else values


# =============================================================================================
# Contraintes
# =============================================================================================

## Liste des contraintes violées (vide si le génome est cohérent). `oxygen` : niveau du moment.
static func violations(t: Dictionary, oxygen := 1.0) -> Array:
	var v := []
	for key in GENOME_KEYS:
		if not t.has(key):
			v.append("clé manquante : " + key)
	if not v.is_empty():
		return v
	var prod := is_producer(t)
	var met := String(t.metabolism)
	if not METABOLISMS.has(met):
		v.append("métabolisme inconnu")
	elif prod == (met == "hétérotrophe"):
		v.append("métabolisme incohérent avec le régime")
	if bool(t.get("oxygenic", false)) and met != "photosynthèse":
		v.append("oxygénique sans photosynthèse")
	if not allowed_plans(t).has(plan(t)):
		v.append("plan corporel %s impossible à ce niveau de complexité" % plan(t))
	if not allowed_skeletons(t).has(skeleton(t)):
		v.append("squelette %s impossible pour ce plan" % skeleton(t))
	var lr := limb_range(t)
	var limbs := int(t.limbs)
	if limbs < int(lr[0]) or limbs > int(lr[1]):
		v.append("nombre de membres %d hors de [%d, %d]" % [limbs, lr[0], lr[1]])
	if limbs_paired(t) and limbs % 2 != 0:
		v.append("membres impairs")
	if bool(t.wings) and not wings_allowed(t):
		v.append("ailes sans membres ni squelette adaptés")
	var milieu := String(t.milieu)
	if not allowed_milieux(t).has(milieu):
		v.append("milieu %s incompatible avec l'habitat %s" % [milieu, habitat(t)])
	var loco := String(t.locomotion)
	if (milieu == "air") != (loco == "vol"):
		v.append("milieu aérien sans vol, ou vol hors des airs")
	if loco == "vol" and not flight_possible(t, oxygen):
		v.append("vol impossible (ailes, taille, oxygène ou sang)")
	if not allowed_locos(t, oxygen).has(loco):
		v.append("locomotion %s impossible" % loco)
	if not allowed_covers(t).has(String(t.covering)):
		v.append("couverture %s impossible" % t.covering)
	if bool(t.warm_blooded) and not warm_allowed(t):
		v.append("sang chaud sans squelette d'amniote")
	var senses: Array = allowed_senses(t)
	for s in t.senses:
		if not senses.has(s):
			v.append("sens impossible : %s" % s)
	var weapons: Array = allowed_weapons(t)
	for w in t.weapons:
		if not weapons.has(w):
			v.append("arme impossible : %s" % w)
	if float(t.get("size", 0.0)) > size_limit(t) + 1e-6:
		v.append("taille %.2f au-delà de %.2f pour ce corps et ce milieu" % [float(t.size), size_limit(t)])
	if not prod and plan(t) != "bilatéral" and plan(t) != "unicellulaire" and habitat(t) == "land":
		v.append("animal sans symétrie bilatérale hors de l'eau")
	for key in ["sociability", "fertility", "hue", "sat", "val"]:
		var x := float(t[key])
		if x < 0.0 or x > 1.0:
			v.append("%s hors de 0..1" % key)
	if not (float(t.lifespan) > 0.0):
		v.append("durée de vie nulle")
	if not PATTERNS.has(String(t.pattern)):
		v.append("motif inconnu")
	return v


static func _pick(arr: Array, g: RandomNumberGenerator) -> Variant:
	if arr.is_empty():
		return null
	# Le premier choix est le plus courant.
	if g.randf() < 0.45:
		return arr[0]
	return arr[g.randi_range(0, arr.size() - 1)]


static func _even_clamp(n: int, lr: Array, paired: bool) -> int:
	n = clampi(n, int(lr[0]), int(lr[1]))
	if paired and n % 2 != 0:
		n = n - 1 if n - 1 >= int(lr[0]) else n + 1
	return n


## Répare un génome pour qu'il respecte les contraintes. Les traits de la simulation (taille,
## habitat…) ne sont touchés que pour les lignées libres ; les autres adaptent le génome.
static func enforce(t: Dictionary, g: RandomNumberGenerator, oxygen := 1.0) -> void:
	var prod := is_producer(t)
	# Métabolisme : le régime de la simulation fait foi.
	if prod:
		if bool(t.get("oxygenic", false)):
			t.metabolism = "photosynthèse"
		elif String(t.get("metabolism", "")) != "photosynthèse":
			t.metabolism = "chimiosynthèse"
	else:
		t.metabolism = "hétérotrophe"
		t.oxygenic = false
	if is_free(t) and not prod and habitat(t) == "land" and int(cx(t)) < 3:
		t.habitat = "marine"
	var plans := allowed_plans(t)
	if not plans.has(plan(t)):
		t.body_plan = _clade_filter(t, "plan", plans)[0]
	if is_free(t) and not prod and plan(t) != "bilatéral" and plan(t) != "unicellulaire" and habitat(t) == "land":
		t.habitat = "marine"
	var skels := allowed_skeletons(t)
	if not skels.has(skeleton(t)):
		t.skeleton = _clade_filter(t, "skel", skels)[0]
	var lr := limb_range(t)
	var limbs := int(t.get("limbs", lr[0]))
	if skeleton(t) == "endosquelette" and limbs == 0 and int(t.get("limbs", -1)) < 0:
		limbs = 4
	t.limbs = _even_clamp(limbs, lr, limbs_paired(t))
	if bool(t.get("wings", false)) and not wings_allowed(t):
		t.wings = false
	elif not t.has("wings"):
		t.wings = false
	var mil := allowed_milieux(t)
	var milieu := String(t.get("milieu", ""))
	if not mil.has(milieu) or milieu == "air":
		t.milieu = "terre" if habitat(t) == "land" else mil[0]
		if milieu == "abysses" and mil.has("abysses"):
			t.milieu = "abysses"
	if not warm_allowed(t):
		t.warm_blooded = false
	elif not t.has("warm_blooded"):
		t.warm_blooded = false
	var locos := allowed_locos(t, oxygen)
	var loco := String(t.get("locomotion", ""))
	if loco == "vol" and flight_possible(t, oxygen):
		pass
	elif not locos.has(loco):
		var choices := _clade_filter(t, "loco", locos)
		if choices.has("vol") and not bool(t.get("wings", false)):
			choices.erase("vol")
		t.locomotion = choices[0] if not choices.is_empty() else locos[0]
	if String(t.locomotion) == "vol":
		t.milieu = "air"
	if is_free(t):
		t["size"] = minf(float(t.get("size", 0.1)), size_limit(t))
		if float(t["size"]) > size_limit(t):
			t["size"] = size_limit(t)
	var covers := allowed_covers(t)
	if not covers.has(String(t.get("covering", ""))):
		var c := _clade_filter(t, "cover", covers)
		var pick: String = c[0]
		if bool(t.warm_blooded):
			if bool(t.wings) and c.has("plumes"):
				pick = "plumes"
			elif c.has("poils"):
				pick = "poils"
		t.covering = pick
	# Une plante qui a grandi sans tronc se dote d'écorce (sinon la taille, libre, est bornée).
	if is_free(t):
		t["size"] = minf(float(t["size"]), size_limit(t))
	var senses := []
	var allowed_s := allowed_senses(t)
	for s in t.get("senses", []):
		if allowed_s.has(s) and not senses.has(s):
			senses.append(s)
	t.senses = senses
	var weapons := []
	var allowed_w := allowed_weapons(t)
	for w in t.get("weapons", []):
		if allowed_w.has(w) and not weapons.has(w):
			weapons.append(w)
	t.weapons = weapons
	for key in ["sociability", "fertility", "sat", "val"]:
		t[key] = clampf(float(t.get(key, 0.5)), 0.0, 1.0)
	t.hue = fposmod(float(t.get("hue", 0.3)), 1.0)
	t.lifespan = maxf(float(t.get("lifespan", base_lifespan(t))), 0.001)
	if not PATTERNS.has(String(t.get("pattern", ""))):
		t.pattern = "uni"
	t.biolum = bool(t.get("biolum", false))
	if not t.has("gseed"):
		t.gseed = g.randi()


# =============================================================================================
# Génération
# =============================================================================================

## Durée de vie typique (années) d'après la taille et le métabolisme.
static func base_lifespan(t: Dictionary) -> float:
	var s := float(t.get("size", 0.1))
	if plan(t) == "unicellulaire":
		return 0.002 + s * 0.2
	var l := 0.6 * pow(150.0, s)
	if bool(t.get("warm_blooded", false)):
		l *= 1.4
	if is_producer(t):
		l *= 4.0 if String(t.get("covering", "")) == "écorce" else 1.5
	return l


static func base_fertility(t: Dictionary) -> float:
	var f := 0.9 - 0.75 * float(t.get("size", 0.1))
	if bool(t.get("warm_blooded", false)):
		f -= 0.15
	return clampf(f, 0.05, 1.0)


static func _base_sociability(t: Dictionary, g: RandomNumberGenerator) -> float:
	var p := plan(t)
	if p == "unicellulaire" or p == "colonial":
		return g.randf_range(0.75, 1.0)
	var s := g.randf_range(0.1, 0.8)
	if String(t.get("diet", "")) == "herbivore":
		s += 0.15
	return clampf(s, 0.0, 1.0)


## Couleur de base plausible selon le mode de vie.
static func _base_color(t: Dictionary, g: RandomNumberGenerator) -> Array:
	var met := String(t.get("metabolism", ""))
	var milieu := String(t.get("milieu", ""))
	var h := g.randf()
	var s := g.randf_range(0.35, 0.9)
	var v := g.randf_range(0.35, 0.9)
	if met == "photosynthèse":
		h = g.randf_range(0.22, 0.5) if g.randf() < 0.8 else g.randf_range(0.8, 1.0)
	elif met == "chimiosynthèse":
		h = g.randf_range(0.0, 0.12) if g.randf() < 0.5 else g.randf_range(0.72, 0.92)
	elif milieu == "abysses":
		if g.randf() < 0.5:
			h = g.randf_range(0.95, 1.05)
		else:
			s = g.randf_range(0.0, 0.25)
		v = g.randf_range(0.15, 0.95)
	elif milieu == "terre" and g.randf() < 0.5:
		h = g.randf_range(0.02, 0.14)  # ocres, bruns, fauves : le camouflage domine sur terre
		s = g.randf_range(0.3, 0.8)
		v = g.randf_range(0.25, 0.75)
	return [fposmod(h, 1.0), s, v]


static func _random_senses(t: Dictionary, g: RandomNumberGenerator) -> Array:
	var out := []
	for s in allowed_senses(t):
		var p := 0.0
		match s:
			"yeux":
				p = 0.35 if String(t.get("milieu", "")) == "abysses" else 0.85
			"électroréception":
				p = 0.3
			"écholocation":
				p = 0.12
		if g.randf() < p:
			out.append(s)
	return out


static func _random_weapons(t: Dictionary, g: RandomNumberGenerator) -> Array:
	var out := []
	var diet := String(t.get("diet", ""))
	for w in allowed_weapons(t):
		var p := 0.12
		match w:
			"crocs":
				p = 0.65 if diet == "carnivore" else 0.2
			"griffes":
				p = 0.4 if diet == "carnivore" else 0.15
			"pinces":
				p = 0.45
			"cornes":
				p = 0.25 if diet == "herbivore" else 0.08
			"épines":
				p = 0.2
			"venin":
				p = 0.15
		if g.randf() < p:
			out.append(w)
	return out


## Complète les clés de génome absentes, en restant dans les contraintes (et dans le clade pour
## les lignées non libres). `keep` : valeurs imposées (semence façonnée), gardées si possibles.
static func fill(t: Dictionary, g: RandomNumberGenerator, oxygen := 1.0, keep := {}) -> void:
	for key in keep:
		if GENOME_KEYS.has(key) or key == "complexity":
			var val: Variant = keep[key]
			t[key] = val.duplicate() if val is Array else val
	if not t.has("metabolism"):
		t.metabolism = ("photosynthèse" if bool(t.get("oxygenic", false)) else "chimiosynthèse") \
			if is_producer(t) else "hétérotrophe"
	if not t.has("body_plan"):
		t.body_plan = _pick(_clade_filter(t, "plan", allowed_plans(t)), g)
	if not t.has("skeleton"):
		t.skeleton = _pick(_clade_filter(t, "skel", allowed_skeletons(t)), g)
	if not t.has("limbs"):
		var lr := limb_range(t)
		var n := 0
		match skeleton(t):
			"exosquelette":
				n = [6, 6, 8, 10, 6, 14][g.randi_range(0, 5)]
			"endosquelette":
				n = 4 if g.randf() < 0.9 else [0, 2][g.randi_range(0, 1)]
			_:
				if plan(t) == "radial":
					n = [0, 5, 8, 10, 12][g.randi_range(0, 4)]
				elif plan(t) == "bilatéral":
					n = [0, 0, 8, 10][g.randi_range(0, 3)]
		t.limbs = _even_clamp(n, lr, limbs_paired(t))
	if not t.has("milieu"):
		var mil := allowed_milieux(t).duplicate()
		mil.erase("air")
		t.milieu = _pick(mil, g)
	if not t.has("warm_blooded"):
		var warms: Array = _clade_filter(t, "warm", [false, true] if warm_allowed(t) else [false])
		t.warm_blooded = bool(warms[0])
	if not t.has("wings"):
		var ws: Array = _clade_filter(t, "wings", [false, true] if wings_allowed(t) else [false])
		t.wings = bool(ws[0]) and wings_allowed(t)
	if not t.has("locomotion"):
		var locos := _clade_filter(t, "loco", allowed_locos(t, oxygen))
		if bool(t.wings) and locos.has("vol") and g.randf() < 0.85:
			t.locomotion = "vol"
		else:
			locos = locos.duplicate()
			locos.erase("vol")
			t.locomotion = _pick(locos, g) if not locos.is_empty() else allowed_locos(t, oxygen)[0]
		if String(t.locomotion) == "vol":
			t.milieu = "air"
	if not t.has("covering"):
		var covers := _clade_filter(t, "cover", allowed_covers(t))
		var c: String = _pick(covers, g)
		if bool(t.warm_blooded):
			if bool(t.wings) and covers.has("plumes") and not covers.has("poils"):
				c = "plumes"
			elif covers.has("poils") and g.randf() < 0.8:
				c = "poils"
			elif covers.has("plumes") and (not covers.has("écailles") or g.randf() < 0.5):
				c = "plumes"
		t.covering = c
	if not t.has("senses"):
		t.senses = _random_senses(t, g)
	if not t.has("weapons"):
		t.weapons = _random_weapons(t, g)
	if not t.has("hue"):
		var col := _base_color(t, g)
		t.hue = col[0]
		t.sat = col[1]
		t.val = col[2]
	if not t.has("sat"):
		t.sat = g.randf_range(0.35, 0.9)
	if not t.has("val"):
		t.val = g.randf_range(0.35, 0.9)
	if not t.has("pattern"):
		var r := g.randf()
		t.pattern = "uni" if r < 0.4 else ("rayé" if r < 0.6 else ("tacheté" if r < 0.8 else "ocellé"))
		if plan(t) == "unicellulaire":
			t.pattern = "uni"
	if not t.has("biolum"):
		var pb := 0.01
		match String(t.milieu):
			"abysses":
				pb = 0.45
			"mer peu profonde":
				pb = 0.05
		t.biolum = g.randf() < pb
	if not t.has("sociability"):
		t.sociability = _base_sociability(t, g)
	if not t.has("fertility"):
		t.fertility = clampf(base_fertility(t) + g.randfn(0.0, 0.08), 0.02, 1.0)
	if not t.has("lifespan"):
		t.lifespan = base_lifespan(t) * exp(g.randfn(0.0, 0.3))
	if not t.has("gseed"):
		t.gseed = g.randi()
	if not t.has("innovations"):
		t.innovations = []
	if not t.has("novelties"):
		t.novelties = []
	enforce(t, g, oxygen)


## Génome d'une espèce qui n'en a pas (rosters, anciennes sauvegardes) : typique de son clade.
static func ensure(t: Dictionary, g: RandomNumberGenerator, oxygen := 1.0) -> void:
	if has_genome(t):
		return
	fill(t, g, oxygen)


## Une transition de clade (Species.TRANSITIONS) remodèle le corps : plan, squelette, milieu,
## locomotion et couverture sont redessinés pour le nouveau clade ; couleurs et mœurs héritées.
static func conform_to_clade(t: Dictionary, g: RandomNumberGenerator, oxygen := 1.0) -> void:
	var before := t.duplicate(true)
	# Même une lignée libre prend ici le corps typique du clade qu'elle fonde.
	var free := is_free(t)
	t.free_evolution = false
	for key in ["body_plan", "skeleton", "limbs", "wings", "locomotion", "milieu", "covering",
			"metabolism", "warm_blooded"]:
		t.erase(key)
	t.erase("lifespan")
	t.erase("fertility")
	var senses: Array = before.get("senses", [])
	var weapons: Array = before.get("weapons", [])
	t.erase("senses")
	t.erase("weapons")
	fill(t, g, oxygen)
	# Les sens et armes hérités restent quand le nouveau corps les permet.
	var s: Array = t.senses.duplicate()
	for x in senses:
		if allowed_senses(t).has(x) and not s.has(x):
			s.append(x)
	t.senses = s
	var w: Array = t.weapons.duplicate()
	for x in weapons:
		if allowed_weapons(t).has(x) and not w.has(x) and g.randf() < 0.6:
			w.append(x)
	t.weapons = w
	enforce(t, g, oxygen)
	if free:
		t.free_evolution = true
	else:
		t.erase("free_evolution")
	_record_novelties(t, before, true)


# =============================================================================================
# Évolution
# =============================================================================================

## Fait évoluer le génome d'une espèce fille `t` (déjà copiée du parent et mutée par
## Species.mutate pour les traits de la simulation). `g` : générateur local.
static func evolve(t: Dictionary, parent: Dictionary, g: RandomNumberGenerator, oxygen := 1.0) -> void:
	ensure(t, g, oxygen)
	t.erase("seed_kind")
	t.senses = (t.senses as Array).duplicate()
	t.weapons = (t.weapons as Array).duplicate()
	t.innovations = (t.get("innovations", []) as Array).duplicate()
	var before := t.duplicate(true)
	if not has_genome(parent):
		before = t.duplicate(true)
	else:
		for key in GENOME_KEYS:
			before[key] = parent.get(key, t.get(key))
		before.intelligence = parent.get("intelligence", t.get("intelligence", 0.0))
		before.habitat = parent.get("habitat", t.get("habitat", "land"))
		before.complexity = parent.get("complexity", t.get("complexity", 6.0))
	if is_free(t):
		_major_innovation(t, g, oxygen)
	_body_innovation(t, g, oxygen)
	_drift(t, g, oxygen)
	enforce(t, g, oxygen)
	if is_free(t):
		t.clade = derive_clade(t, String(parent.get("clade", "")))
	t.gseed = g.randi()
	_record_novelties(t, before)


static func _record_novelties(t: Dictionary, before: Dictionary, append := false) -> void:
	var nov := innovations_between(before, t)
	if append:
		var all: Array = (t.get("novelties", []) as Array).duplicate()
		for n in nov:
			if not all.has(n):
				all.append(n)
		nov = all
	t.novelties = nov
	var inn: Array = (t.get("innovations", []) as Array).duplicate()
	for n in nov:
		if not inn.has(n):
			inn.append(n)
	if inn.size() > MAX_INNOVATIONS:
		inn = inn.slice(inn.size() - MAX_INNOVATIONS)
	t.innovations = inn


## Grandes innovations des lignées libres (elles changent la complexité ou le milieu : les autres
## lignées les reçoivent par les transitions de clade de la simulation). Au plus une par naissance.
static func _major_innovation(t: Dictionary, g: RandomNumberGenerator, oxygen: float) -> void:
	var c := cx(t)
	var p := plan(t)
	var prod := is_producer(t)
	var s := skeleton(t)
	var hab := habitat(t)
	var r := g.randf()
	if p == "unicellulaire":
		if c < 1.0 and oxygen >= 0.002 and r < 0.004:
			t.complexity = 1.0
		elif c >= 1.0 and oxygen >= 0.012 and r < 0.004:
			t.complexity = 2.0
			t.body_plan = "colonial"
			t.locomotion = "fixe" if prod else "dérive"
			if prod:
				t.covering = "frondes"
		return
	if prod:
		if hab != "land" and oxygen >= 0.2 and r < 0.003:
			t.habitat = "land"
			t.milieu = "terre"
			t.locomotion = "fixe"
			t.covering = "frondes"
			t["size"] = minf(float(t["size"]), SOFT_PLANT_MAX_SIZE)
		elif p == "colonial" and r < 0.006:
			t.body_plan = "radial"
		return
	if p == "colonial":
		if oxygen >= 0.08 and r < 0.003:
			t.complexity = 3.0
			t.body_plan = "radial" if g.randf() < 0.5 else "bilatéral"
			t.skeleton = "aucun"
		return
	if p == "radial":
		if oxygen >= 0.08 and r < 0.003:
			t.complexity = 3.0
			t.body_plan = "bilatéral"
			t.skeleton = "hydrostatique"
			t.locomotion = "rampe"
			t.limbs = 0
		return
	# Bilatériens.
	if c < 4.0:
		if (s == "aucun" or s == "hydrostatique") and oxygen >= 0.08 and r < 0.004:
			if g.randf() < 0.55:
				t.skeleton = "exosquelette"
				t.limbs = 6 + 2 * g.randi_range(0, 3)
				t.covering = "carapace"
			else:
				t.skeleton = "coquille"
				t.covering = "carapace"
		elif s != "exosquelette" and hab != "land" and oxygen >= 0.15 and r < 0.0055:
			t.skeleton = "endosquelette"
			t.complexity = 4.0
			t.limbs = 4
			t.covering = "écailles"
			t.locomotion = "nage"
		elif s == "exosquelette" and hab != "land" and oxygen >= 0.25 and float(t["size"]) <= LAND_SIZE["exosquelette"] \
				and r < 0.0065:
			t.habitat = "land"
			t.milieu = "terre"
			t.locomotion = "marche"
		return
	if hab == "marine" and oxygen >= 0.25 and r < 0.002:
		t.habitat = "amphibious"
		t.milieu = "eau douce"
		t.complexity = 5.0
		t.limbs = 4
		t.covering = "peau nue"
		t.locomotion = "marche"
	elif hab == "amphibious" and c >= 5.0 and oxygen >= 0.3 and r < 0.003:
		t.habitat = "land"
		t.milieu = "terre"
		t.complexity = 6.0
		t.covering = "écailles"
		t.locomotion = "marche"
	elif c >= 5.0 and float(t.get("intelligence", 0.0)) < 0.6 and r > 1.0 - 0.002:
		t.intelligence = minf(0.7, float(t.get("intelligence", 0.0)) + 0.12)


## Innovations corporelles qui ne changent pas la simulation : sang chaud, vol, sens, lumière.
static func _body_innovation(t: Dictionary, g: RandomNumberGenerator, oxygen: float) -> void:
	var limited := _limited(t)
	var spec: Dictionary = CLADE_GENOME.get(String(t.get("clade", "")), {})
	if not bool(t.get("warm_blooded", false)) and warm_allowed(t) and oxygen >= WARM_OXYGEN \
			and (not limited or (spec.warm as Array).has(true)) and g.randf() < 0.003:
		t.warm_blooded = true
		var covers := _clade_filter(t, "cover", allowed_covers(t))
		if covers.has("poils") and g.randf() < 0.6:
			t.covering = "poils"
		elif covers.has("plumes"):
			t.covering = "plumes"
	if String(t.get("locomotion", "")) != "vol" and g.randf() < 0.003 \
			and (not limited or (spec.loco as Array).has("vol")):
		var had: bool = t.wings
		t.wings = true
		if flight_possible(t, oxygen):
			t.locomotion = "vol"
			t.milieu = "air"
		else:
			t.wings = had
	var senses: Array = t.senses
	for s in allowed_senses(t):
		if senses.has(s):
			continue
		var p := 0.01 if s == "yeux" else (0.004 if s == "électroréception" else 0.003)
		if g.randf() < p:
			senses.append(s)
	if not bool(t.get("biolum", false)) and g.randf() < (0.01 if String(t.get("milieu", "")) == "abysses" else 0.002):
		t.biolum = true


## Petites mutations de chaque naissance : allure, milieu, couverture, membres, couleurs, mœurs.
static func _drift(t: Dictionary, g: RandomNumberGenerator, oxygen: float) -> void:
	if g.randf() < 0.04:
		var locos := _clade_filter(t, "loco", allowed_locos(t, oxygen)).duplicate()
		if not bool(t.wings):
			locos.erase("vol")
		if not locos.is_empty():
			t.locomotion = locos[g.randi_range(0, locos.size() - 1)]
			t.milieu = "air" if String(t.locomotion) == "vol" else ("terre" if String(t.milieu) == "air" else t.milieu)
	if String(t.locomotion) != "vol" and g.randf() < 0.025:
		var mil := allowed_milieux(t).duplicate()
		mil.erase("air")
		t.milieu = mil[g.randi_range(0, mil.size() - 1)]
	if g.randf() < 0.02:
		var covers := _clade_filter(t, "cover", allowed_covers(t))
		t.covering = covers[g.randi_range(0, covers.size() - 1)]
	if g.randf() < 0.025:
		var lr := limb_range(t)
		var paired := limbs_paired(t)
		var step := 2 if paired else 1
		if skeleton(t) != "endosquelette" or g.randf() < 0.3:
			t.limbs = _even_clamp(int(t.limbs) + (step if g.randf() < 0.5 else -step), lr, paired)
	var senses: Array = t.senses
	for s in senses.duplicate():
		var loss := 0.02 if (s == "yeux" and String(t.milieu) == "abysses") else 0.004
		if g.randf() < loss:
			senses.erase(s)
	var weapons: Array = t.weapons
	if g.randf() < 0.02:
		var aw := allowed_weapons(t)
		if not aw.is_empty():
			var w: String = aw[g.randi_range(0, aw.size() - 1)]
			if not weapons.has(w):
				weapons.append(w)
	if not weapons.is_empty() and g.randf() < 0.015:
		weapons.remove_at(g.randi_range(0, weapons.size() - 1))
	if g.randf() < 0.035 and plan(t) != "unicellulaire":
		t.pattern = PATTERNS[g.randi_range(0, PATTERNS.size() - 1)]
	t.hue = fposmod(float(t.hue) + g.randfn(0.0, 0.012) + (g.randfn(0.0, 0.18) if g.randf() < 0.03 else 0.0), 1.0)
	t.sat = clampf(float(t.sat) + g.randfn(0.0, 0.03), 0.0, 1.0)
	t.val = clampf(float(t.val) + g.randfn(0.0, 0.03), 0.05, 1.0)
	if bool(t.biolum) and g.randf() < 0.004:
		t.biolum = false
	t.sociability = clampf(float(t.sociability) + g.randfn(0.0, 0.04), 0.0, 1.0)
	t.fertility = clampf(lerpf(float(t.fertility), base_fertility(t), 0.1) + g.randfn(0.0, 0.03), 0.02, 1.0)
	var life := maxf(float(t.lifespan), 0.001)
	t.lifespan = exp(lerpf(log(life), log(base_lifespan(t)), 0.15) + g.randfn(0.0, 0.08))


## Innovations apparues entre deux génomes (parent -> enfant), dans l'ordre de l'histoire du vivant.
static func innovations_between(a: Dictionary, b: Dictionary) -> Array:
	var out := []
	if a.is_empty() or b.is_empty():
		return out
	if cx(a) < 1.0 and cx(b) >= 1.0:
		out.append("cellule à noyau")
	if plan(a) == "unicellulaire" and plan(b) != "unicellulaire":
		out.append("multicellularité")
	if plan(a) != "bilatéral" and plan(b) == "bilatéral" and not is_producer(b):
		out.append("symétrie bilatérale")
	if skeleton(a) != "exosquelette" and skeleton(b) == "exosquelette":
		out.append("exosquelette")
	if skeleton(a) != "coquille" and skeleton(b) == "coquille":
		out.append("coquille")
	if skeleton(a) != "endosquelette" and skeleton(b) == "endosquelette":
		out.append("squelette")
	if habitat(a) == "marine" and habitat(b) != "marine":
		out.append("sortie des eaux")
	if habitat(a) == "amphibious" and habitat(b) == "land" and skeleton(b) == "endosquelette":
		out.append("œuf amniotique")
	if not bool(a.get("warm_blooded", false)) and bool(b.get("warm_blooded", false)):
		out.append("sang chaud")
	if String(a.get("locomotion", "")) != "vol" and String(b.get("locomotion", "")) == "vol" \
			and not bool(a.get("wings", false)):
		out.append("vol")
	if String(a.get("metabolism", "")) != "photosynthèse" and String(b.get("metabolism", "")) == "photosynthèse" \
			and is_producer(a):
		out.append("photosynthèse")
	if float(a.get("intelligence", 0.0)) < INTELLIGENCE_MARK and float(b.get("intelligence", 0.0)) >= INTELLIGENCE_MARK:
		out.append("intelligence")
	var sa: Array = a.get("senses", [])
	for s in b.get("senses", []):
		if not sa.has(s):
			out.append(s)
	if not bool(a.get("biolum", false)) and bool(b.get("biolum", false)):
		out.append("bioluminescence")
	if not (a.get("weapons", []) as Array).has("venin") and (b.get("weapons", []) as Array).has("venin"):
		out.append("venin")
	return out


static func is_major(innovation: String) -> bool:
	return MAJOR_INNOVATIONS.has(innovation)


# =============================================================================================
# Clade
# =============================================================================================

## Le génome correspond-il encore au clade ?
static func clade_fits(clade: String, t: Dictionary) -> bool:
	if not CLADE_GENOME.has(clade):
		return false
	var spec: Dictionary = CLADE_GENOME[clade]
	var prod := is_producer(t)
	if (spec.prod == 0 and prod) or (spec.prod == 1 and not prod):
		return false
	var c := cx(t)
	if c < float(spec.cx[0]) or c > float(spec.cx[1]):
		return false
	if not (spec.hab as Array).has(habitat(t)):
		return false
	return (spec.plan as Array).has(plan(t)) and (spec.skel as Array).has(skeleton(t)) \
		and (spec.cover as Array).has(String(t.get("covering", ""))) \
		and (spec.loco as Array).has(String(t.get("locomotion", ""))) \
		and (spec.warm as Array).has(bool(t.get("warm_blooded", false))) \
		and (spec.wings as Array).has(bool(t.get("wings", false)))


## Clade déduit du génome ; `previous` est gardé tant qu'il correspond. « inédit » quand aucune
## lignée connue ne ressemble à ce corps.
static func derive_clade(t: Dictionary, previous := "") -> String:
	if previous != "" and clade_fits(previous, t):
		return previous
	var c := cx(t)
	var p := plan(t)
	var hab := habitat(t)
	var guess := "inédit"
	if is_producer(t):
		if c < 1.0:
			guess = "microbe"
		elif hab == "land":
			guess = "plante"
		else:
			guess = "algue"
	elif p == "unicellulaire":
		guess = "microbe"
	elif p == "colonial" or p == "radial":
		guess = "éponge" if hab != "land" else "inédit"
	else:
		var s := skeleton(t)
		var warm := bool(t.get("warm_blooded", false))
		var cover := String(t.get("covering", ""))
		match s:
			"exosquelette":
				guess = "insecte" if hab == "land" else "arthropode"
			"endosquelette":
				if hab == "marine":
					guess = "poisson"
				elif hab == "amphibious":
					guess = "amphibien" if c >= 5.0 else "poisson"
				elif cover == "plumes":
					guess = "oiseau" if bool(t.get("wings", false)) else "dinosaure"
				elif bool(t.get("wings", false)) and String(t.get("locomotion", "")) == "vol":
					guess = "mammifère" if cover == "poils" and previous == "mammifère" else "ptérosaure"
				elif warm and cover == "poils":
					guess = "primate" if previous == "primate" else "mammifère"
				elif cover == "poils" or (warm and cover == "peau nue"):
					guess = "synapside"
				elif cover == "écailles" and float(t.get("size", 0.0)) >= 0.45 and warm:
					guess = "dinosaure"
				else:
					guess = "reptile"
			_:
				guess = "mollusque" if hab != "land" else "inédit"
	if guess != "inédit" and not clade_fits(guess, t):
		# Ressemblance imparfaite (ex. un poisson à sang chaud) : la lignée est nouvelle.
		guess = "inédit" if not _close_enough(guess, t) else guess
	return guess


## Tolérance : le clade le plus proche reste juste si plan, squelette et milieu concordent.
static func _close_enough(clade: String, t: Dictionary) -> bool:
	var spec: Dictionary = CLADE_GENOME.get(clade, {})
	if spec.is_empty():
		return false
	return (spec.plan as Array).has(plan(t)) and (spec.skel as Array).has(skeleton(t)) \
		and (spec.hab as Array).has(habitat(t))


# =============================================================================================
# Semences du joueur
# =============================================================================================

const SEED_KINDS := ["spark", "light", "spore", "animal_germ", "shaped"]
const GERM_ROLES := ["filtreur", "brouteur", "chasseur"]


## Traits complets (simulation + génome) d'une semence posée par le joueur.
## env : {temp (température locale 0..1), oxygen, role (animal_germ), traits (shaped)}.
static func seed_template(kind: String, rng: RandomNumberGenerator, env: Dictionary) -> Dictionary:
	var temp := clampf(float(env.get("temp", 0.6)), 0.05, 0.95)
	var oxygen := float(env.get("oxygen", 1.0))
	var t := {
		size = 0.01, intelligence = 0.0, adaptability = clampf(0.75 + rng.randfn(0.0, 0.04), 0.4, 0.95),
		aggression = clampf(0.2 + rng.randfn(0.0, 0.05), 0.0, 1.0), diet = "autotrophe",
		temp_opt = temp, temp_tol = clampf(0.38 + rng.randfn(0.0, 0.02), 0.2, 0.45), clade = "microbe",
		complexity = 0.0, habitat = "marine", anaerobic = false, oxygenic = false, free_evolution = true,
	}
	var keep := {}
	match kind:
		"spark":
			t.size = clampf(0.01 + rng.randfn(0.0, 0.001), 0.005, 0.02)
			t.anaerobic = true
			# Les sources hydrothermales : chaudes, quel que soit le climat de surface.
			t.temp_opt = clampf(maxf(temp, 0.65) + rng.randfn(0.0, 0.02), 0.05, 0.95)
			keep = {metabolism = "chimiosynthèse", body_plan = "unicellulaire", milieu = "abysses", locomotion = "fixe"}
		"light":
			t.size = clampf(0.011 + rng.randfn(0.0, 0.001), 0.005, 0.02)
			t.oxygenic = true
			t.aggression = clampf(0.3 + rng.randfn(0.0, 0.05), 0.0, 1.0)
			keep = {metabolism = "photosynthèse", body_plan = "unicellulaire", milieu = "mer peu profonde", locomotion = "dérive"}
		"spore":
			t.size = clampf(0.1 + rng.randfn(0.0, 0.01), 0.1, 0.15)
			t.clade = "plante"
			t.complexity = 2.0
			t.habitat = "land"
			t.oxygenic = true
			t.adaptability = clampf(0.8 + rng.randfn(0.0, 0.04), 0.5, 0.95)
			t.temp_tol = clampf(0.32 + rng.randfn(0.0, 0.02), 0.2, 0.45)
			keep = {metabolism = "photosynthèse", body_plan = "colonial", milieu = "terre", covering = "frondes", locomotion = "fixe"}
		"animal_germ":
			var role := String(env.get("role", "brouteur"))
			if not GERM_ROLES.has(role):
				role = "brouteur"
			t.complexity = 3.0
			t.adaptability = clampf(0.6 + rng.randfn(0.0, 0.05), 0.3, 0.9)
			t.temp_tol = clampf(0.28 + rng.randfn(0.0, 0.02), 0.15, 0.45)
			t.intelligence = 0.02
			match role:
				"filtreur":
					t.diet = "herbivore"
					t.size = clampf(0.06 + rng.randfn(0.0, 0.01), 0.03, 0.12)
					t.aggression = clampf(0.1 + rng.randfn(0.0, 0.03), 0.0, 1.0)
					keep = {body_plan = "radial", skeleton = "aucun", locomotion = "fixe", milieu = "mer peu profonde", covering = "peau nue"}
				"chasseur":
					t.diet = "carnivore"
					t.size = clampf(0.08 + rng.randfn(0.0, 0.01), 0.04, 0.15)
					t.aggression = clampf(0.65 + rng.randfn(0.0, 0.05), 0.0, 1.0)
					keep = {body_plan = "bilatéral", skeleton = "exosquelette", limbs = 10, locomotion = "nage", milieu = "mer peu profonde", covering = "carapace", weapons = ["pinces"], senses = ["yeux"]}
				_:
					t.diet = "herbivore"
					t.size = clampf(0.05 + rng.randfn(0.0, 0.01), 0.02, 0.1)
					t.aggression = clampf(0.2 + rng.randfn(0.0, 0.04), 0.0, 1.0)
					keep = {body_plan = "bilatéral", skeleton = "hydrostatique", limbs = 0, locomotion = "rampe", milieu = "mer peu profonde", covering = "peau nue"}
		"shaped":
			keep = _shape(t, env.get("traits", {}), rng, temp)
		_:
			push_warning("seed_template : semence inconnue « %s », étincelle par défaut" % kind)
			return seed_template("spark", rng, env)
	fill(t, rng, oxygen, keep)
	enforce(t, rng, oxygen)
	t.clade = derive_clade(t, String(t.clade))
	t.novelties = []
	t.innovations = []
	# Marque la fondatrice semée (l'arbre de la vie s'en sert) ; ses descendantes ne l'héritent pas.
	t.seed_kind = kind
	return t


## Créature façonnée : traits partiels du joueur, complétés de façon cohérente. Renvoie les clés de
## génome à imposer à fill() ; règle sur place les traits de la simulation.
static func _shape(t: Dictionary, p: Dictionary, rng: RandomNumberGenerator, temp: float) -> Dictionary:
	var keep := {}
	for key in GENOME_KEYS:
		if p.has(key) and key != "gseed":
			keep[key] = p[key]
	if keep.has("milieu") and not MILIEUX.has(String(keep.milieu)):
		keep.erase("milieu")
	if keep.has("locomotion") and not LOCOMOTIONS.has(String(keep.locomotion)):
		keep.erase("locomotion")
	var tables := {body_plan = BODY_PLANS, skeleton = SKELETONS, covering = COVERINGS,
		metabolism = METABOLISMS, pattern = PATTERNS}
	for key in tables:
		var table: Array = tables[key]
		if keep.has(key) and not table.has(String(keep[key])):
			keep.erase(key)
	var loco := String(keep.get("locomotion", ""))
	var met := String(keep.get("metabolism", ""))
	var diet := String(p.get("diet", ""))
	if not ["herbivore", "omnivore", "carnivore", "autotrophe"].has(diet):
		diet = "autotrophe" if met == "photosynthèse" or met == "chimiosynthèse" \
			or ["écorce", "frondes"].has(String(keep.get("covering", ""))) else "omnivore"
	t.diet = diet
	var prod := diet == "autotrophe"
	if prod:
		for key in ["locomotion", "wings", "warm_blooded", "senses", "weapons", "skeleton", "limbs"]:
			keep.erase(key)
		loco = ""
		if not ["photosynthèse", "chimiosynthèse"].has(met):
			keep.metabolism = "photosynthèse"
	else:
		keep.metabolism = "hétérotrophe"
	# Milieu -> habitat de la simulation.
	var hab := String(p.get("habitat", ""))
	if keep.has("milieu"):
		hab = MILIEU_HABITAT[String(keep.milieu)]
	elif loco == "vol" or loco == "marche" or loco == "saut":
		hab = "land"
	elif loco == "nage" or loco == "dérive":
		hab = "marine"
	if not ["marine", "amphibious", "land"].has(hab):
		hab = "land" if prod and String(keep.get("covering", "")) == "écorce" else ("marine" if prod else "land")
	t.habitat = hab
	if loco == "vol":
		keep.wings = true
		keep.milieu = "air"
	var size := clampf(float(p.get("size", rng.randf_range(0.05, 0.5) if not prod else 0.2)), 0.005, 1.0)
	if loco == "vol":
		size = minf(size, FLIGHT_MAX_SIZE)
	t.size = size
	# Plan corporel et squelette.
	var bp := String(keep.get("body_plan", ""))
	if bp == "":
		if prod:
			bp = "radial" if hab == "land" and size > 0.12 else ("unicellulaire" if size < 0.03 else "colonial")
		elif loco == "fixe" or loco == "dérive" or size < 0.012:
			bp = "unicellulaire" if size < 0.012 else "radial"
		else:
			bp = "bilatéral"
	if not prod and bp != "bilatéral" and bp != "unicellulaire" and hab == "land":
		bp = "bilatéral"
	keep.body_plan = bp
	var sk := String(keep.get("skeleton", ""))
	var cover := String(keep.get("covering", ""))
	if not prod and bp == "bilatéral":
		var needs_endo := float(p.get("intelligence", 0.0)) > 0.2 or bool(p.get("warm_blooded", false)) \
			or ["écailles", "plumes", "poils"].has(cover) or (hab == "land" and size > LAND_SIZE["exosquelette"]) \
			or size > WATER_SIZE["coquille"] or (loco == "vol" and size > LAND_SIZE["exosquelette"])
		if sk == "" or (needs_endo and sk != "endosquelette"):
			if needs_endo:
				sk = "endosquelette"
			elif cover == "carapace" or loco == "vol" or loco == "marche" or loco == "saut":
				sk = "exosquelette"
			else:
				sk = "hydrostatique"
		if (loco == "marche" or loco == "saut") and sk != "endosquelette":
			sk = "exosquelette"
		keep.skeleton = sk
		# Un vertébré volant a le sang chaud (comme les oiseaux et les ptérosaures).
		if loco == "vol" and sk == "endosquelette":
			keep.warm_blooded = true
	# Complexité déduite du corps.
	var c := 0.0
	if prod:
		c = 0.0 if bp == "unicellulaire" else 2.0
	elif bp == "unicellulaire":
		c = 0.0
	elif bp == "colonial":
		c = 2.0
	elif bp == "radial" or sk != "endosquelette":
		c = 3.0
	else:
		c = 4.0 if hab == "marine" else (5.0 if hab == "amphibious" else 6.0)
	if (bool(keep.get("warm_blooded", false)) or cover == "poils" or cover == "plumes") and sk == "endosquelette":
		c = 6.0
		if hab != "land":
			hab = "land"
			t.habitat = "land"
			keep.erase("milieu")
	t.complexity = c
	if not prod and bp != "bilatéral" and bp != "unicellulaire":
		t.habitat = "marine"
	t.intelligence = clampf(float(p.get("intelligence", 0.05)), 0.0, 0.7)
	if c < 4.0:
		t.intelligence = minf(float(t.intelligence), 0.05 + 0.02 * c)
	t.aggression = clampf(float(p.get("aggression", 0.7 if diet == "carnivore" else 0.3)), 0.0, 1.0)
	t.adaptability = clampf(float(p.get("adaptability", 0.6)), 0.05, 1.0)
	t.temp_opt = clampf(float(p.get("temp_opt", temp)), 0.02, 0.98)
	t.temp_tol = clampf(float(p.get("temp_tol", 0.28)), 0.1, 0.45)
	t.oxygenic = prod and String(keep.get("metabolism", "")) == "photosynthèse"
	t.anaerobic = prod and String(keep.get("metabolism", "")) == "chimiosynthèse"
	t.clade = ""
	return keep
