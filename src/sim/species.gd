extends RefCounted
## Espèces : rosters initiaux (microbes de l'Archéen ; fin du Crétacé pour le scénario court),
## traits, mutation, transitions entre clades, nommage, interactions.
##
## Traits (dictionnaire `traits` de chaque espèce, valeurs 0..1 sauf mention) :
## - size : taille (échelle log de la masse ; 1 = titanosaure, 0.05 = musaraigne)
## - intelligence : la sapience émerge au-delà de SAPIENCE_THRESHOLD, quelle que soit l'espèce
## - adaptability : généralisme, résistance aux catastrophes, vitesse de spéciation
## - aggression : force compétitive, propension à la guerre une fois sapiente
## - diet : "herbivore" | "omnivore" | "carnivore"
## - temp_opt / temp_tol : température préférée et tolérance (même échelle que `temperature`)
## - clade : lignée (microbe, algue, éponge, arthropode, mollusque, poisson, plante, insecte,
##   amphibien, reptile, synapside, dinosaure, ptérosaure, oiseau, mammifère, primate, …)
## - complexity : 0 microbes, 1 eucaryotes, 2 multicellulaires, 3 animaux, 4 vertébrés,
##   5 tétrapodes, 6 amniotes (COMPLEXITY_NAMES) ; ne change qu'aux transitions de clade
## - habitat : "marine" | "amphibious" | "land"
## - anaerobic : l'oxygène l'empoisonne ; oxygenic : produit de l'oxygène (photosynthèse)
## Les dinosaures, les ancêtres des mammifères, etc. naissent par transitions de clade à la
## spéciation (TRANSITIONS), sous conditions d'oxygène, de flore terrestre et de niches libres.
##
## Génome étendu (src/life/genome.gd) : plan corporel, squelette, membres, locomotion, milieu,
## couverture, métabolisme, sens, armes, mœurs, couleurs… sous des clés plates de `traits`.
## Chaque espèce en reçoit un (rosters compris) ; il mute à chaque spéciation dans le respect des
## contraintes physiques. Les lignées semées par le joueur (seed_template) et les chimères ont
## `free_evolution` : leurs grandes innovations naissent du génome, et leur clade en est déduit.
## Ces calculs utilisent un générateur local dérivé de l'état du générateur partagé, sans jamais
## y puiser : la suite des tirages de la simulation est inchangée.
## Noms (binômes latins, noms vernaculaires) : src/life/naming.gd ; descriptions :
## src/life/description.gd ; arbre de la vie : src/life/phylogeny.gd.

const Genome := preload("res://src/life/genome.gd")
const Naming := preload("res://src/life/naming.gd")
const Description := preload("res://src/life/description.gd")

const SAPIENCE_THRESHOLD := 0.78

## Régimes : les trois premiers sont animaux ; « autotrophe » = producteur (microbes,
## algues, plantes), nourriture des herbivores, proie de personne pour les carnivores.
const DIETS := ["herbivore", "omnivore", "carnivore", "autotrophe"]
const ANIMAL_DIETS := ["herbivore", "omnivore", "carnivore"]
const AUTOTROPH := 3
const HABITATS := ["marine", "amphibious", "land"]

const COMPLEXITY_NAMES := ["microbes", "eucaryotes", "multicellulaires", "animaux", "vertébrés",
	"tétrapodes", "amniotes"]
## Oxygène atmosphérique (fraction du niveau actuel) nécessaire à chaque niveau de complexité.
const OXYGEN_NEED: Array[float] = [0.0, 0.002, 0.012, 0.08, 0.15, 0.25, 0.3]

## Roster de départ du prologue (-3,8 Ga) : la vie n'est que microbienne et marine.
const PROLOGUE_ROSTER := [
	{name = "Archées méthanogènes", metabolism = "chimiosynthèse", clade = "microbe", size = 0.01, intelligence = 0.0, adaptability = 0.75, aggression = 0.2, diet = "autotrophe", temp_opt = 0.72, temp_tol = 0.4, complexity = 0.0, habitat = "marine", anaerobic = true, oxygenic = false},
	{name = "Bactéries pourpres", metabolism = "photosynthèse", clade = "microbe", size = 0.012, intelligence = 0.0, adaptability = 0.7, aggression = 0.2, diet = "autotrophe", temp_opt = 0.62, temp_tol = 0.4, complexity = 0.0, habitat = "marine", anaerobic = true, oxygenic = false},
	{name = "Cyanobactéries", clade = "microbe", size = 0.011, intelligence = 0.0, adaptability = 0.7, aggression = 0.3, diet = "autotrophe", temp_opt = 0.6, temp_tol = 0.38, complexity = 0.0, habitat = "marine", anaerobic = false, oxygenic = true},
]

## Transitions de clade possibles à la spéciation. `oxygen` : oxygène minimal ; `flora` : part
## minimale des terres couvertes de plantes ; `radiation` : bien plus probable quand la lignée
## mère profite de niches libérées (après une extinction de masse) ; `weight` : probabilité
## relative. `min_c` / `max_c` : bornes de complexité de la lignée mère.
const TRANSITIONS := [
	{from = "microbe", to = "algue", complexity = 1.0, habitat = "marine", diet = "autotrophe", oxygen = 0.002, weight = 1.0},
	{from = "algue", to = "algue", complexity = 2.0, max_c = 1.5, habitat = "marine", diet = "autotrophe", oxygen = 0.012, weight = 1.0, name = "Algues multicellulaires"},
	{from = "algue", to = "éponge", complexity = 3.0, min_c = 2.0, habitat = "marine", diet = "herbivore", oxygen = 0.08, weight = 1.0},
	{from = "algue", to = "plante", complexity = 2.0, min_c = 2.0, habitat = "land", diet = "autotrophe", oxygen = 0.3, weight = 0.15},
	{from = "plante", to = "plante", complexity = 2.0, habitat = "land", diet = "autotrophe", oxygen = 0.25, weight = 0.3},
	{from = "éponge", to = "arthropode", complexity = 3.0, habitat = "marine", diet = "carnivore", oxygen = 0.1, weight = 1.0},
	{from = "éponge", to = "mollusque", complexity = 3.0, habitat = "marine", diet = "herbivore", oxygen = 0.1, weight = 1.0},
	{from = "mollusque", to = "poisson", complexity = 4.0, habitat = "marine", diet = "carnivore", oxygen = 0.15, weight = 0.7},
	{from = "arthropode", to = "poisson", complexity = 4.0, habitat = "marine", diet = "omnivore", oxygen = 0.15, weight = 0.3},
	{from = "arthropode", to = "insecte", complexity = 3.0, habitat = "land", diet = "herbivore", oxygen = 0.25, flora = 0.15, weight = 0.8},
	{from = "poisson", to = "amphibien", complexity = 5.0, habitat = "amphibious", diet = "carnivore", oxygen = 0.3, flora = 0.25, weight = 0.6},
	{from = "amphibien", to = "reptile", complexity = 6.0, habitat = "land", diet = "carnivore", oxygen = 0.35, flora = 0.3, weight = 0.8},
	{from = "amphibien", to = "synapside", complexity = 6.0, habitat = "land", diet = "herbivore", oxygen = 0.35, flora = 0.3, weight = 0.8},
	{from = "reptile", to = "dinosaure", complexity = 6.0, habitat = "land", diet = "carnivore", oxygen = 0.3, radiation = true, weight = 1.0},
	{from = "reptile", to = "ptérosaure", complexity = 6.0, habitat = "land", diet = "carnivore", oxygen = 0.3, radiation = true, weight = 0.4},
	{from = "synapside", to = "mammifère", complexity = 6.0, habitat = "land", diet = "omnivore", oxygen = 0.3, radiation = true, weight = 0.8},
	{from = "dinosaure", to = "dinosaure", complexity = 6.0, habitat = "land", diet = "herbivore", oxygen = 0.3, weight = 0.6},
	{from = "dinosaure", to = "oiseau", complexity = 6.0, habitat = "land", diet = "omnivore", oxygen = 0.3, weight = 0.25},
	{from = "mammifère", to = "primate", complexity = 6.0, habitat = "land", diet = "omnivore", oxygen = 0.3, weight = 0.2},
]
## [taille typique, minimum, maximum] par clade (la mutation reste dans ces bornes).
const CLADE_SIZE := {
	"microbe": [0.01, 0.004, 0.02], "algue": [0.03, 0.01, 0.1], "plante": [0.3, 0.1, 0.6],
	"éponge": [0.08, 0.02, 0.25], "arthropode": [0.12, 0.02, 0.45], "mollusque": [0.12, 0.02, 0.5],
	"poisson": [0.25, 0.05, 0.75], "insecte": [0.04, 0.01, 0.2], "amphibien": [0.3, 0.05, 0.6],
	"reptile": [0.3, 0.05, 0.75], "synapside": [0.35, 0.05, 0.7], "dinosaure": [0.45, 0.15, 1.0],
	"ptérosaure": [0.35, 0.1, 0.7], "oiseau": [0.12, 0.03, 0.5], "mammifère": [0.08, 0.03, 0.9],
	"primate": [0.1, 0.04, 0.6],
}
## Vigueur compétitive héritée par les dinosaures nés de l'évolution (trait `vigour`, absent du
## roster du Crétacé qui les fait déjà dominer) : sans elle, nés après la Grande Mourance dans des
## niches déjà reprises par les synapsides, ils resteraient cantonnés à quelques régions.
const DINOSAUR_VIGOUR := 1.4
## Climat typique (température préférée, tolérance minimale) des clades qui doivent peupler de
## vastes régions (le roster du Crétacé en est la cible) : une lignée fondée dans un recoin froid
## ne condamne pas les dinosaures à la toundra.
const CLADE_CLIMATE := {
	"dinosaure": [0.66, 0.24], "ptérosaure": [0.68, 0.2], "reptile": [0.68, 0.2],
	"synapside": [0.6, 0.24], "mammifère": [0.5, 0.32], "oiseau": [0.52, 0.32], "primate": [0.66, 0.22],
}
## Noms des groupes fondés par chaque transition de clade, dans l'ordre (puis noms binomiaux).
const GROUP_NAMES := {
	"algue": ["Protistes", "Algues vertes", "Algues rouges"],
	"plante": ["Mousses", "Lycophytes", "Fougères", "Prêles", "Conifères", "Cycadales", "Angiospermes"],
	"éponge": ["Éponges", "Cnidaires", "Ediacariens"],
	"arthropode": ["Trilobites", "Euryptérides", "Crustacés"],
	"mollusque": ["Brachiopodes", "Nautiloïdes", "Ammonites"],
	"poisson": ["Agnathes", "Placodermes", "Requins", "Sarcoptérygiens"],
	"insecte": ["Insectes primitifs", "Méganeuridés", "Blattoptères"],
	"amphibien": ["Tétrapodes", "Temnospondyles", "Lissamphibiens"],
	"reptile": ["Sauropsidés", "Archosauriens", "Crocodyliformes", "Squamates"],
	"synapside": ["Pélycosaures", "Thérapsides", "Cynodontes"],
	"dinosaure": ["Dinosauriformes", "Théropodes", "Sauropodomorphes", "Ornithischiens", "Tyrannosauridés", "Hadrosauridés", "Cératopsidés"],
	"ptérosaure": ["Ptérosaures"],
	"oiseau": ["Ornithurés"],
	"mammifère": ["Mammaliaformes", "Multituberculés", "Euthériens"],
	"primate": ["Plésiadapiformes"],
}

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
	"reptile": "Squamiens", "ptérosaure": "Ptérosiens", "synapside": "Thérapsiens",
	"amphibien": "Batraciens", "poisson": "Ichtyens", "mollusque": "Céphaliens",
	"arthropode": "Arthropiens", "insecte": "Insectiens",
}


static func diet_index(traits: Dictionary) -> int:
	return maxi(0, DIETS.find(traits.get("diet", "omnivore")))


static func habitat_index(traits: Dictionary) -> int:
	return maxi(0, HABITATS.find(traits.get("habitat", "land")))


static func is_autotroph(traits: Dictionary) -> bool:
	return traits.get("diet", "") == "autotrophe"


## Sans précision (roster du Crétacé), une espèce est un amniote terrestre aérobie.
static func traits_from_def(def: Dictionary) -> Dictionary:
	var t := {
		size = float(def["size"]), intelligence = float(def.intelligence),
		adaptability = float(def.adaptability), aggression = float(def.aggression),
		diet = String(def.diet), temp_opt = float(def.temp_opt), temp_tol = float(def.temp_tol),
		clade = String(def.clade), complexity = float(def.get("complexity", 6.0)),
		habitat = String(def.get("habitat", "land")), anaerobic = bool(def.get("anaerobic", false)),
		oxygenic = bool(def.get("oxygenic", false)),
	}
	# Génome typique du clade, tiré d'une graine propre au nom (déterministe).
	var g := RandomNumberGenerator.new()
	g.seed = hash(["genome", String(def.get("name", def.clade))])
	var keep := {}
	for key in Genome.GENOME_KEYS:
		if def.has(key):
			keep[key] = def[key]
	Genome.fill(t, g, 1.0, keep)
	return t


## Traits aléatoires adaptés au climat local (espèce créée ex nihilo par spawn_species).
## `complexity` : niveau du vivant le plus complexe du moment ; `land` : les terres sont
## habitables (sinon la créature naît dans la mer).
static func random_traits(rng: RandomNumberGenerator, local_temp: float, complexity := 6.0, land := true) -> Dictionary:
	var animal := complexity >= 3.0
	var t := {
		size = rng.randf_range(0.05, 0.8) if animal else rng.randf_range(0.005, 0.05),
		intelligence = rng.randf_range(0.1, 0.4) if complexity >= 6.0 else rng.randf_range(0.0, 0.1),
		adaptability = rng.randf_range(0.3, 0.8), aggression = rng.randf_range(0.1, 0.9),
		diet = ANIMAL_DIETS[rng.randi_range(0, 2)] if animal else "autotrophe",
		temp_opt = clampf(local_temp, 0.05, 0.95),
		temp_tol = rng.randf_range(0.18, 0.32), clade = "chimère", complexity = floorf(complexity),
		habitat = "land" if land and complexity >= 5.0 else "marine", anaerobic = false,
		oxygenic = not animal, free_evolution = true,
	}
	# Une chimère est une lignée libre ; son génome est tiré sans puiser dans `rng`.
	Genome.fill(t, _local_rng(rng, "chimère"), 1.0)
	return t


## Générateur local dérivé de l'état d'un générateur, sans le faire avancer.
static func _local_rng(rng: RandomNumberGenerator, salt: Variant) -> RandomNumberGenerator:
	var g := RandomNumberGenerator.new()
	g.seed = hash([rng.state, salt])
	return g


## Applique une transition de clade (TRANSITIONS) à des traits fraîchement mutés.
static func apply_transition(t: Dictionary, rule: Dictionary, rng: RandomNumberGenerator) -> void:
	var to: String = rule.to
	t.clade = to
	t.complexity = float(rule.complexity)
	t.habitat = String(rule.habitat)
	t.diet = String(rule.diet)
	t.anaerobic = false
	t.oxygenic = t.diet == "autotrophe"
	var sz: Array = CLADE_SIZE.get(to, [t["size"], 0.01, 1.0])
	t["size"] = clampf(lerpf(float(t["size"]), float(sz[0]), 0.7) + rng.randfn(0.0, 0.03), float(sz[1]), float(sz[2]))
	if t.complexity < 6.0:
		t.intelligence = minf(float(t.intelligence), 0.05 + 0.02 * t.complexity)
	if t.habitat == "land":
		t.temp_tol = clampf(float(t.temp_tol) - 0.04, 0.12, 0.45)
	if to == "dinosaure":
		# Avantage des archosaures (posture dressée, sacs aériens) : la cible est le roster du
		# Crétacé, où les dinosaures dominent les terres.
		t.aggression = maxf(float(t.aggression), 0.6)
		t.adaptability = minf(1.0, float(t.adaptability) + 0.1)
		t["size"] = maxf(float(t["size"]), 0.5)
		t.vigour = DINOSAUR_VIGOUR
	if CLADE_CLIMATE.has(to):
		var c: Array = CLADE_CLIMATE[to]
		t.temp_opt = lerpf(float(t.temp_opt), float(c[0]), 0.7)
		t.temp_tol = maxf(float(t.temp_tol), float(c[1]))
	# Le nouveau clade remodèle le corps (plan, squelette, milieu, couverture…).
	Genome.conform_to_clade(t, _local_rng(rng, ["transition", to, int(t.get("gseed", 0))]))


## Mutation à la spéciation. `radiation` > 0 : niches vides, la taille dérive vers le haut ;
## `founder_temp` : la population fondatrice s'adapte au climat où elle s'isole.
static func mutate(parent: Dictionary, rng: RandomNumberGenerator, founder_temp: float, radiation: float, oxygen := 1.0) -> Dictionary:
	var t := parent.duplicate()
	var defaults := traits_from_def({size = 0.3, intelligence = 0.0, adaptability = 0.5, aggression = 0.5,
		diet = "omnivore", temp_opt = 0.5, temp_tol = 0.2, clade = ""})
	for key in ["complexity", "habitat", "anaerobic", "oxygenic"]:
		if not t.has(key):
			t[key] = defaults[key]
	var sz: Array = CLADE_SIZE.get(t.clade, [0.3, 0.03, 1.0])
	# Les microbes ne changent guère de taille ; les animaux dérivent (vers le haut en radiation).
	var sigma := 0.07 if t.complexity >= 3.0 else 0.003
	t["size"] = clampf(t["size"] + rng.randfn(0.012 * radiation * sigma / 0.07, sigma), float(sz[1]), float(sz[2]))
	# Pression de sélection douce vers l'intelligence chez les généralistes.
	var brain_bias := 0.006 if t.diet == "omnivore" else 0.0
	t.intelligence = clampf(t.intelligence + rng.randfn(brain_bias, 0.035), 0.02, 1.0)
	t.adaptability = clampf(t.adaptability + rng.randfn(0.0, 0.05), 0.05, 1.0)
	t.aggression = clampf(t.aggression + rng.randfn(0.0, 0.07), 0.0, 1.0)
	t.temp_opt = clampf(lerpf(t.temp_opt, founder_temp, 0.35) + rng.randfn(0.0, 0.03), 0.02, 0.98)
	t.temp_tol = clampf(t.temp_tol + rng.randfn(0.0, 0.025), 0.1, 0.45)
	if t.diet != "autotrophe" and rng.randf() < 0.05:
		t.diet = ANIMAL_DIETS[rng.randi_range(0, 2)]
	if t.clade == "microbe":
		# Métabolismes microbiens : la photosynthèse oxygénique peut réapparaître (rarement),
		# la respiration aérobie s'impose quand l'oxygène est là.
		if not t.oxygenic and rng.randf() < 0.004:
			t.oxygenic = true
			t.anaerobic = false
		if t.anaerobic and rng.randf() < 0.15 * clampf(oxygen / 0.01, 0.0, 1.0):
			t.anaerobic = false
	# Génome : petites mutations à chaque naissance, grandes innovations rares (lignées libres).
	Genome.evolve(t, parent, _local_rng(rng, ["mutation", int(parent.get("gseed", 0))]), oxygen)
	if t.complexity < 4.0:
		t.intelligence = minf(t.intelligence, 0.05 + 0.02 * t.complexity)
	return t


## Distance entre deux jeux de traits (sert à décider d'un nouveau genre).
static func divergence(a: Dictionary, b: Dictionary) -> float:
	return absf(a["size"] - b["size"]) + absf(a.intelligence - b.intelligence) * 2.0 \
		+ absf(a.temp_opt - b.temp_opt) + (0.3 if a.diet != b.diet else 0.0) \
		+ (1.0 if a.get("clade", "") != b.get("clade", "") else 0.0)


static func _word(rng: RandomNumberGenerator, n: int) -> String:
	var s := ""
	for i in n:
		s += _SYLLABLES[rng.randi_range(0, _SYLLABLES.size() - 1)]
	return s


## Nom binomial latinisé : le genre est hérité tant que la lignée ne diverge pas trop (les espèces
## sœurs le partagent), l'épithète s'accorde au genre grammatical du nom de genre. Un groupe nommé
## en français (« Tyrannosauridés ») transmet son genre type (« Tyrannosaurus »). `traits`
## (facultatif) rend les racines parlantes (Bathy- pour les abysses, -spinus pour les épines…).
## Les tirages dans `rng` sont exactement ceux de l'ancien nommage : la simulation n'en dévie pas.
static func make_name(parent_name: String, rng: RandomNumberGenerator, new_genus: bool, traits := {}) -> String:
	var genus := parent_name.split(" ")[0]
	var draws := [parent_name]
	var fresh := new_genus or genus.length() < 3
	if fresh:
		var n := rng.randi_range(2, 3)
		for i in n:
			draws.append(rng.randi_range(0, _SYLLABLES.size() - 1))
	for i in 2:
		draws.append(rng.randi_range(0, _SYLLABLES.size() - 1))
	draws.append(rng.randi_range(0, _EPITHET_ENDS.size() - 1))
	var g := RandomNumberGenerator.new()
	g.seed = hash(draws)
	var latin := "" if fresh else Naming.genus_of(parent_name)
	if latin == "":
		latin = Naming.latin_genus(g, traits)
	return Naming.binomial(g, latin, traits)


# =============================================================================================
# Génome, semences, noms et descriptions (chantier « Espèces infinies »)
# =============================================================================================

## Traits complets d'une semence du joueur : "spark" (microbe chimiosynthétique), "light"
## (cyanobactérie), "spore" (colonisatrice des terres), "animal_germ" (env.role : "filtreur",
## "brouteur" ou "chasseur"), "shaped" (env.traits : traits partiels complétés avec cohérence).
## env : {temp, oxygen, role, traits}. Consomme `rng`. La lignée est libre (free_evolution).
static func seed_template(kind: String, rng: RandomNumberGenerator, env: Dictionary) -> Dictionary:
	return Genome.seed_template(kind, rng, env)


## Binôme latin d'une lignée fondée par le joueur (nouveau genre, racines tirées des traits).
static func seed_name(traits: Dictionary, rng: RandomNumberGenerator) -> String:
	return Naming.binomial(rng, "", traits)


## Complète sur place le génome d'une espèce qui n'en a pas (anciennes sauvegardes).
static func ensure_genome(traits: Dictionary) -> void:
	if Genome.has_genome(traits):
		return
	var g := RandomNumberGenerator.new()
	g.seed = hash(["genome", String(traits.get("clade", "")), float(traits.get("size", 0.0)),
		float(traits.get("temp_opt", 0.0)), float(traits.get("aggression", 0.0))])
	Genome.fill(traits, g, 1.0)


static func _with_genome(traits: Dictionary) -> Dictionary:
	if Genome.has_genome(traits):
		return traits
	var t := traits.duplicate(true)
	ensure_genome(t)
	return t


## Deux ou trois phrases (apparence, mode de vie) tirées des traits.
static func describe(traits: Dictionary) -> String:
	return Description.describe(_with_genome(traits))


## Nom vernaculaire français (« Rampeur à épines bleues ») ; `plural` : « Rampeurs à épines bleues ».
static func vernacular_name(traits: Dictionary, plural := false) -> String:
	return Naming.vernacular(_with_genome(traits), plural)


## Clade déduit du génome (« inédit » si aucune lignée connue ne lui ressemble).
static func derive_clade(traits: Dictionary) -> String:
	return Genome.derive_clade(_with_genome(traits), String(traits.get("clade", "")))


## Contraintes physiques violées par un génome (vide s'il est cohérent).
static func genome_violations(traits: Dictionary, oxygen := 1.0) -> Array:
	return Genome.violations(traits, oxygen)


## Innovations apparues entre deux jeux de traits (ex. ["sortie des eaux"]).
static func innovations_between(parent: Dictionary, child: Dictionary) -> Array:
	return Genome.innovations_between(parent, child)


static func is_major_innovation(innovation: String) -> bool:
	return Genome.is_major(innovation)


## Couleur de base de l'espèce (la vue rapprochée peut teinter ses créatures avec).
static func color_of(traits: Dictionary) -> Color:
	var t := _with_genome(traits)
	return Color.from_hsv(float(t.hue), float(t.sat), float(t.val))


## Nom de la couleur de base (« bleu sombre »).
static func color_name(traits: Dictionary) -> String:
	return Naming.color_name(_with_genome(traits))


static func sapient_title(traits: Dictionary) -> String:
	return _SAPIENT_NAMES.get(traits.get("clade", ""), "Conscients")


## Chevauchement de niche (0..1) : régime alimentaire similaire et tailles voisines.
## Des milieux différents (mer / terre) ne se concurrencent pas ; producteurs et animaux non plus.
static func overlap(a: Dictionary, b: Dictionary) -> float:
	var ha := habitat_index(a)
	var hb := habitat_index(b)
	var hab_sim := 1.0 if ha == hb else (0.5 if absi(ha - hb) == 1 else 0.0)
	if hab_sim <= 0.0:
		return 0.0
	var da := diet_index(a)
	var db := diet_index(b)
	var diet_sim: float
	if da == AUTOTROPH or db == AUTOTROPH:
		if da != db:
			diet_sim = 0.03
		else:
			# Bactéries et eucaryotes, anaérobies et aérobies se partagent les niches.
			diet_sim = 0.5 if bool(a.get("anaerobic", false)) != bool(b.get("anaerobic", false)) else 1.0
			if a.get("clade", "") != b.get("clade", ""):
				diet_sim *= 0.4
	else:
		diet_sim = 1.0 if da == db else (0.45 if absi(da - db) == 1 else 0.08)
	return hab_sim * diet_sim * exp(-absf(a["size"] - b["size"]) * 4.0)


## Force compétitive à niche égale. Les sapients écrasent tout à mesure que leur technologie croît.
static func competitiveness(t: Dictionary, tech_level: float, sapient: bool) -> float:
	var c: float = (0.6 + 0.4 * t.aggression) * (0.7 + 0.6 * t.intelligence) * (0.7 + 0.6 * t.adaptability) 		* float(t.get("vigour", 1.0))
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
		# Un impact majeur n'épargne aucun dinosaure non avien, petit ou grand (limite K-Pg).
		if severity >= 0.6:
			return 1.0
		v += 0.9
	v = maxf(v, 0.25)
	if float(t.get("complexity", 6.0)) < 3.0:
		v *= 0.3  # microbes, algues : spores, kystes, profondeurs
	return clampf(v * severity, 0.0, 1.0)
