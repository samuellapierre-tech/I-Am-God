extends RefCounted
## Espèces : roster initial (fin du Crétacé), traits, mutation, nommage, interactions.
##
## Traits (dictionnaire `traits` de chaque espèce, valeurs 0..1 sauf mention) :
## - size : taille (échelle log de la masse ; 1 = titanosaure, 0.05 = musaraigne)
## - intelligence : la sapience émerge au-delà de SAPIENCE_THRESHOLD, quelle que soit l'espèce
## - adaptability : généralisme, résistance aux catastrophes, vitesse de spéciation
## - aggression : force compétitive, propension à la guerre une fois sapiente
## - diet : "herbivore" | "omnivore" | "carnivore"
## - temp_opt / temp_tol : température préférée et tolérance (même échelle que `temperature`)
## - clade : lignée (dinosaure, oiseau, mammifère, primate, reptile, ptérosaure, ...)

const SAPIENCE_THRESHOLD := 0.78

const DIETS := ["herbivore", "omnivore", "carnivore"]

## Clades frappés de plein fouet par un impact (ni terriers ni graines pour survivre).
const IMPACT_VULNERABLE_CLADES := ["dinosaure", "ptérosaure"]

const ROSTER := [
	{name = "Tyrannosauridés", clade = "dinosaure", size = 0.95, intelligence = 0.25, adaptability = 0.30, aggression = 0.95, diet = "carnivore", temp_opt = 0.66, temp_tol = 0.22},
	{name = "Hadrosauridés", clade = "dinosaure", size = 0.80, intelligence = 0.15, adaptability = 0.45, aggression = 0.20, diet = "herbivore", temp_opt = 0.62, temp_tol = 0.26},
	{name = "Cératopsidés", clade = "dinosaure", size = 0.85, intelligence = 0.12, adaptability = 0.35, aggression = 0.50, diet = "herbivore", temp_opt = 0.68, temp_tol = 0.21},
	{name = "Titanosaures", clade = "dinosaure", size = 1.00, intelligence = 0.08, adaptability = 0.30, aggression = 0.20, diet = "herbivore", temp_opt = 0.76, temp_tol = 0.18},
	{name = "Ankylosauridés", clade = "dinosaure", size = 0.75, intelligence = 0.10, adaptability = 0.35, aggression = 0.40, diet = "herbivore", temp_opt = 0.58, temp_tol = 0.24},
	{name = "Dromæosauridés", clade = "dinosaure", size = 0.35, intelligence = 0.36, adaptability = 0.55, aggression = 0.85, diet = "carnivore", temp_opt = 0.60, temp_tol = 0.26},
	{name = "Troodontidés", clade = "dinosaure", size = 0.30, intelligence = 0.46, adaptability = 0.60, aggression = 0.50, diet = "omnivore", temp_opt = 0.55, temp_tol = 0.29},
	{name = "Ptérosaures", clade = "ptérosaure", size = 0.50, intelligence = 0.20, adaptability = 0.35, aggression = 0.50, diet = "carnivore", temp_opt = 0.70, temp_tol = 0.20},
	{name = "Ornithurés", clade = "oiseau", size = 0.12, intelligence = 0.24, adaptability = 0.70, aggression = 0.30, diet = "omnivore", temp_opt = 0.52, temp_tol = 0.34},
	{name = "Crocodyliformes", clade = "reptile", size = 0.60, intelligence = 0.12, adaptability = 0.50, aggression = 0.80, diet = "carnivore", temp_opt = 0.76, temp_tol = 0.15},
	{name = "Squamates", clade = "reptile", size = 0.05, intelligence = 0.10, adaptability = 0.70, aggression = 0.40, diet = "carnivore", temp_opt = 0.74, temp_tol = 0.25},
	{name = "Multituberculés", clade = "mammifère", size = 0.06, intelligence = 0.20, adaptability = 0.70, aggression = 0.20, diet = "herbivore", temp_opt = 0.50, temp_tol = 0.35},
	{name = "Euthériens insectivores", clade = "mammifère", size = 0.05, intelligence = 0.22, adaptability = 0.75, aggression = 0.30, diet = "carnivore", temp_opt = 0.48, temp_tol = 0.38},
	{name = "Plésiadapiformes", clade = "primate", size = 0.08, intelligence = 0.34, adaptability = 0.65, aggression = 0.20, diet = "omnivore", temp_opt = 0.68, temp_tol = 0.22},
]

const _SYLLABLES := ["ra", "to", "ken", "lu", "mi", "sar", "do", "vel", "xi", "pha", "gor", "nu", "the", "ka", "lo", "ver", "bra", "zan", "ti", "mo"]
const _EPITHET_ENDS := ["us", "is", "a", "um", "ensis", "oides", "ianus", "ops"]
const _SAPIENT_NAMES := {
	"dinosaure": "Sauriens", "oiseau": "Aviens", "primate": "Humains", "mammifère": "Thériens",
	"reptile": "Squamiens", "ptérosaure": "Ptérosiens",
}


static func diet_index(traits: Dictionary) -> int:
	return maxi(0, DIETS.find(traits.get("diet", "omnivore")))


static func traits_from_def(def: Dictionary) -> Dictionary:
	return {
		size = float(def["size"]), intelligence = float(def.intelligence),
		adaptability = float(def.adaptability), aggression = float(def.aggression),
		diet = String(def.diet), temp_opt = float(def.temp_opt), temp_tol = float(def.temp_tol),
		clade = String(def.clade),
	}


## Traits aléatoires adaptés au climat local (espèce créée ex nihilo par spawn_species).
static func random_traits(rng: RandomNumberGenerator, local_temp: float) -> Dictionary:
	return {
		size = rng.randf_range(0.05, 0.8), intelligence = rng.randf_range(0.1, 0.4),
		adaptability = rng.randf_range(0.3, 0.8), aggression = rng.randf_range(0.1, 0.9),
		diet = DIETS[rng.randi_range(0, 2)], temp_opt = clampf(local_temp, 0.05, 0.95),
		temp_tol = rng.randf_range(0.18, 0.32), clade = "chimère",
	}


## Mutation à la spéciation. `radiation` > 0 : niches vides, la taille dérive vers le haut ;
## `founder_temp` : la population fondatrice s'adapte au climat où elle s'isole.
static func mutate(parent: Dictionary, rng: RandomNumberGenerator, founder_temp: float, radiation: float) -> Dictionary:
	var t := parent.duplicate()
	t["size"] = clampf(t["size"] + rng.randfn(0.012 * radiation, 0.07), 0.03, 1.0)
	# Pression de sélection douce vers l'intelligence chez les généralistes.
	var brain_bias := 0.006 if t.diet == "omnivore" else 0.0
	t.intelligence = clampf(t.intelligence + rng.randfn(brain_bias, 0.035), 0.02, 1.0)
	t.adaptability = clampf(t.adaptability + rng.randfn(0.0, 0.05), 0.05, 1.0)
	t.aggression = clampf(t.aggression + rng.randfn(0.0, 0.07), 0.0, 1.0)
	t.temp_opt = clampf(lerpf(t.temp_opt, founder_temp, 0.35) + rng.randfn(0.0, 0.03), 0.02, 0.98)
	t.temp_tol = clampf(t.temp_tol + rng.randfn(0.0, 0.025), 0.1, 0.45)
	if rng.randf() < 0.05:
		t.diet = DIETS[rng.randi_range(0, 2)]
	return t


## Distance entre deux jeux de traits (sert à décider d'un nouveau genre).
static func divergence(a: Dictionary, b: Dictionary) -> float:
	return absf(a["size"] - b["size"]) + absf(a.intelligence - b.intelligence) * 2.0 \
		+ absf(a.temp_opt - b.temp_opt) + (0.3 if a.diet != b.diet else 0.0)


static func _word(rng: RandomNumberGenerator, n: int) -> String:
	var s := ""
	for i in n:
		s += _SYLLABLES[rng.randi_range(0, _SYLLABLES.size() - 1)]
	return s


## Nom binomial : le genre est hérité tant que la lignée ne diverge pas trop.
static func make_name(parent_name: String, rng: RandomNumberGenerator, new_genus: bool) -> String:
	var genus := parent_name.split(" ")[0]
	if new_genus or genus.length() < 3:
		genus = _word(rng, rng.randi_range(2, 3)).capitalize()
	return "%s %s%s" % [genus, _word(rng, 2), _EPITHET_ENDS[rng.randi_range(0, _EPITHET_ENDS.size() - 1)]]


static func sapient_title(traits: Dictionary) -> String:
	return _SAPIENT_NAMES.get(traits.get("clade", ""), "Conscients")


## Chevauchement de niche (0..1) : régime alimentaire similaire et tailles voisines.
static func overlap(a: Dictionary, b: Dictionary) -> float:
	var da := diet_index(a)
	var db := diet_index(b)
	var diet_sim := 1.0 if da == db else (0.45 if absi(da - db) == 1 else 0.08)
	return diet_sim * exp(-absf(a["size"] - b["size"]) * 4.0)


## Force compétitive à niche égale. Les sapients écrasent tout à mesure que leur technologie croît.
static func competitiveness(t: Dictionary, tech_level: float, sapient: bool) -> float:
	var c: float = (0.6 + 0.4 * t.aggression) * (0.7 + 0.6 * t.intelligence) * (0.7 + 0.6 * t.adaptability)
	if sapient:
		c *= 1.2 + 0.15 * tech_level
	return c


## Taux de dispersion (colonisations par an vers une région voisine).
static func dispersal_rate(t: Dictionary, tech_level: float, sapient: bool) -> float:
	if sapient:
		return (1.0 + tech_level) / 400.0
	return (0.4 + t.adaptability) * (0.5 + t["size"]) / 40000.0


## Vitesse de retour à l'équilibre démographique (1/an) : les petites espèces rebondissent vite.
static func growth_rate(t: Dictionary, sapient: bool) -> float:
	var g: float = 0.02 + 0.2 * (1.0 - t["size"])
	return g * (2.0 if sapient else 1.0)


## Probabilité (0..1) de mourir lors d'un impact majeur, avant protection divine.
static func impact_vulnerability(t: Dictionary, severity: float) -> float:
	var v: float = 0.3 + t["size"] * 1.6 - 0.35 - t.adaptability * 0.3
	if IMPACT_VULNERABLE_CLADES.has(t.clade):
		v += 0.9
	return clampf(maxf(v, 0.25) * severity, 0.0, 1.0)
