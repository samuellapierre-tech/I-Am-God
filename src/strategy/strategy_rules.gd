extends RefCounted
## Règles du jeu stratégique (docs/STRATEGIE.md) : tables explicites, sans état.
## Aspects divins, difficultés, cartes de menace (comment elles frappent, ce qui les contre),
## Grands Œuvres. Toutes les valeurs sont des points de départ à équilibrer en jeu.

const Eras := preload("res://src/sim/eras.gd")

# =============================================================================================
# Aspects (§5) et difficultés (§6)
# =============================================================================================

const ASPECT_ORDER := ["creator", "guardian", "destroyer", "prophet"]
const ASPECTS := {
	creator = {label = "Le Créateur",
		text = "La première Création de chaque manche est gratuite. +1 action quand une espèce naît sur la parcelle."},
	guardian = {label = "Le Gardien",
		text = "Salut et Bénédiction contrent deux menaces à la fois."},
	destroyer = {label = "Le Destructeur",
		text = "Les catastrophes que tu lances libèrent des niches : la vitalité remonte après coup."},
	prophet = {label = "Le Prophète",
		text = "Tu vois les menaces de la manche suivante. L'Oracle ne coûte pas d'action."},
}

const DIFFICULTY_ORDER := ["eveil", "divin", "apocalypse"]
## deck : taille de la pioche (sablier cosmique), cataclysmes compris.
const DIFFICULTIES := {
	eveil = {label = "Éveil", actions = 5, cataclysms = 4, collapse_limit = 10, deck = 96},
	divin = {label = "Divin", actions = 4, cataclysms = 5, collapse_limit = 8, deck = 84},
	apocalypse = {label = "Apocalypse", actions = 3, cataclysms = 6, collapse_limit = 6, deck = 72},
}

const DEFAULT_ASPECT := "guardian"
const DEFAULT_DIFFICULTY := "divin"

## Menaces révélées par manche selon le nombre de Cataclysmes déjà piochés (taux d'infection).
const INTENSITY := [2, 2, 3, 3, 4, 4, 5]
## Une menace qui revient de la défausse frappe plus fort.
const RETURN_SEVERITY := 0.25
const MAX_SEVERITY := 2.0
## Au-delà, la menace frappe deux fois.
const DOUBLE_STRIKE_SEVERITY := 1.25

# =============================================================================================
# Manches
# =============================================================================================

## Durée d'une manche : ce nombre de pas idéaux de la simulation (≈ 30 s à x1 à l'ère sapiente,
## une ère en compte ~1200). Un changement d'ère ouvre aussi une nouvelle manche.
const ROUND_STEPS := 600.0
## Avant toute civilisation, le temps est ralenti (GameState.pace_factor) : manches plus courtes en
## pas (≈ 5 Ma au Mésozoïque, environ une minute à x1 une fois l'ouverture lancée).
const ROUND_STEPS_WILD := 100.0
## Un changement d'ère n'ouvre une manche que si la manche courante a duré au moins cette fraction
## (évite une rafale de manches quand une civilisation oscille entre deux ères).
const MIN_ROUND_FRACTION := 0.2
## Fenêtre des frappes dans la manche (fractions de sa durée).
const STRIKE_FROM := 0.3
const STRIKE_TO := 0.9

const ACT_NAMES := {prologue = "Prologue", act1 = "Acte I", act2 = "Acte II", act3 = "Acte III"}

# =============================================================================================
# Actions divines
# =============================================================================================

## Pouvoirs catastrophiques (aspect du Destructeur).
const CATASTROPHES := ["meteor", "extinct", "plague", "flood", "ice_age"]
## Bonus de vitalité du Destructeur par catastrophe lancée (plafonné), dissipé en une manche.
const DESTROYER_BONUS := 0.12
const DESTROYER_BONUS_MAX := 0.3
## Actions bonus du Créateur par manche (naissances sur la parcelle).
const CREATOR_BONUS_MAX := 2
## Coût pour sceller un Grand Œuvre.
const SEAL_COST := 2

const POWER_LABELS := {
	meteor = "Météorite", extinct = "Extinction", save = "Salut", bless = "Bénédiction",
	plague = "Fléau", uplift = "Élévation", flood = "Déluge", ice_age = "Âge glaciaire",
	spawn_species = "Création", oracle = "Oracle",
}

# =============================================================================================
# Cartes de menace (§3)
# =============================================================================================

## kind -> {
##   title, text,
##   acts : actes où la carte peut être piochée,
##   strike : type d'action divine par lequel la simulation la fait frapper (aucun effet inventé),
##   target : espèce visée ("none", "abundant", "herbivore", "sapient", "collapsing", "native"),
##   radius : rayon de base (multiplié par la gravité),
##   counters : pouvoirs qui la contrent (règle affichée sur la carte),
##   weight : poids de base dans la pioche, major : carte de Cataclysme }
const THREATS := {
	# --- Prologue -------------------------------------------------------------------------------
	oxidation = {title = "Grande Oxydation", text = "L'oxygène empoisonne les lignées anciennes.",
		acts = ["prologue"], strike = "plague", target = "abundant", radius = 10,
		counters = ["save", "bless"], weight = 3.0},
	anoxia = {title = "Anoxie des mers", text = "Les eaux s'asphyxient.",
		acts = ["prologue", "act1"], strike = "plague", target = "abundant", radius = 12,
		counters = ["flood", "bless"], weight = 2.0},
	snowball = {title = "Terre boule de neige", text = "La planète gèle.",
		acts = ["prologue"], strike = "ice_age", target = "none", radius = 30,
		counters = ["bless", "save"], weight = 1.0, major = true},
	# --- Monde sauvage ----------------------------------------------------------------------------
	drought = {title = "Sécheresse", text = "Les pluies cessent, les troupeaux dépérissent.",
		acts = ["act1", "act2", "act3"], strike = "plague", target = "herbivore", radius = 8,
		counters = ["flood", "bless"], weight = 2.0},
	overgrazing = {title = "Surpâturage", text = "Une espèce trop nombreuse ravage la parcelle.",
		acts = ["prologue", "act1", "act2", "act3"], strike = "plague", target = "abundant", radius = 8,
		counters = ["plague", "flood"], weight = 0.5},
	epidemic = {title = "Épidémie", text = "Un mal se répand de proche en proche.",
		acts = ["prologue", "act1", "act2", "act3"], strike = "plague", target = "abundant", radius = 10,
		counters = ["save", "bless"], weight = 2.0},
	invasive = {title = "Espèce invasive", text = "Un envahisseur évince les espèces d'ici.",
		acts = ["prologue", "act1", "act2", "act3"], strike = "plague", target = "native", radius = 8,
		counters = ["plague", "save"], weight = 1.0},
	keystone = {title = "Espèce clé en péril", text = "Si elle tombe, d'autres suivront.",
		acts = ["prologue", "act1", "act2", "act3"], strike = "plague", target = "collapsing", radius = 6,
		counters = ["save", "bless"], weight = 0.0},
	glaciation = {title = "Glaciation", text = "Les glaces avancent.",
		acts = ["act1", "act2", "act3"], strike = "ice_age", target = "none", radius = 30,
		counters = ["bless", "save"], weight = 1.0},
	heatwave = {title = "Dérive du climat", text = "La chaleur monte, les mers aussi.",
		acts = ["prologue", "act1", "act2", "act3"], strike = "flood", target = "none", radius = 10,
		counters = ["ice_age", "bless"], weight = 0.5},
	supervolcano = {title = "Supervolcan", text = "Une caldeira s'éveille sous la parcelle.",
		acts = ["prologue", "act1", "act2", "act3"], strike = "meteor", target = "none", radius = 3,
		counters = ["save", "flood"], weight = 0.0, major = true},
	impact = {title = "Impact cosmique", text = "Un astéroïde croise l'orbite du monde.",
		acts = ["prologue", "act1", "act2", "act3"], strike = "meteor", target = "none", radius = 4,
		counters = ["save", "bless"], weight = 0.0, major = true},
	# --- Civilisations ----------------------------------------------------------------------------
	famine = {title = "Famine", text = "Les récoltes manquent.",
		acts = ["act3"], strike = "plague", target = "sapient", radius = 8,
		counters = ["bless", "flood"], weight = 2.0},
	war = {title = "Guerre", text = "Les peuples prennent les armes.",
		acts = ["act3"], strike = "plague", target = "sapient", radius = 10,
		counters = ["bless", "uplift"], weight = 1.5},
	pollution = {title = "Pollution", text = "Fumées et rejets montent jusqu'au ciel.",
		acts = ["act3"], strike = "flood", target = "none", radius = 12,
		counters = ["uplift", "ice_age"], weight = 0.0},
	hostile_ai = {title = "IA hostile", text = "Une intelligence née des machines se retourne contre ses créateurs.",
		acts = ["act3"], strike = "plague", target = "sapient", radius = 20,
		counters = ["uplift", "save"], weight = 0.0, major = true},
}

## Cataclysme pioché : menace majeure tirée selon l'acte.
const MAJOR_BY_ACT := {
	prologue = ["snowball", "impact", "supervolcano"],
	act1 = ["impact", "supervolcano", "glaciation"],
	act2 = ["glaciation", "supervolcano", "impact"],
	act3 = ["hostile_ai", "supervolcano", "impact"],
}

# =============================================================================================
# Grands Œuvres (§4)
# =============================================================================================

const WORK_ORDER := ["life", "land", "mind", "legacy"]
const WORKS := {
	life = {label = "Vie complexe", text = "Au moins 10 espèces vivantes dans le monde, dont 2 sur la parcelle."},
	land = {label = "Conquête des terres", text = "La parcelle est une terre sauvage et vivante : 3 espèces et de la végétation."},
	mind = {label = "Conscience", text = "Une espèce consciente existe."},
	legacy = {label = "Civilisation pérenne", text = "Une civilisation atteint l'ère moderne."},
}
## Seuil technologique de la Civilisation pérenne (niveau 5 = ère Moderne).
const LEGACY_TECH := 5.0


static func aspect_label(id: String) -> String:
	return String(ASPECTS.get(id, {}).get("label", id))


static func difficulty(id: String) -> Dictionary:
	return DIFFICULTIES.get(id, DIFFICULTIES[DEFAULT_DIFFICULTY])


static func power_label(kind: String) -> String:
	return String(POWER_LABELS.get(kind, kind))


static func intensity(cataclysms: int) -> int:
	return INTENSITY[clampi(cataclysms, 0, INTENSITY.size() - 1)]


## Acte courant d'après l'ère (sans supposer d'indices fixes : constantes de eras.gd).
static func act_for(era_index: int, has_sapient: bool) -> String:
	if era_index < Eras.MESOZOIC:
		return "prologue"
	if has_sapient or era_index >= Eras.FIRST_SAPIENT_ERA:
		return "act3"
	if era_index == Eras.MESOZOIC:
		return "act1"
	return "act2"


## Pouvoirs qui contrent une menace de ce type.
static func counters(kind: String) -> Array[String]:
	var out: Array[String] = []
	for c in THREATS.get(kind, {}).get("counters", []):
		out.append(String(c))
	return out


static func counters_text(kind: String) -> String:
	var names := []
	for c in counters(kind):
		names.append(power_label(c))
	return ", ".join(names)


## Rayon de frappe selon la gravité (les menaces de retour touchent plus large).
static func strike_radius(kind: String, severity: float) -> int:
	var base := int(THREATS.get(kind, {}).get("radius", 8))
	return maxi(1, int(round(base * (0.6 + 0.4 * severity * 2.0))))
