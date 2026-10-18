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
	eveil = {label = "Éveil", actions = 5, cataclysms = 4, collapse_limit = 10, deck = 120,
		samael = "Samaël tire ses menaces au hasard."},
	divin = {label = "Divin", actions = 4, cataclysms = 5, collapse_limit = 8, deck = 108,
		samael = "Samaël joue ce qui fait le plus mal tout de suite, vise tes Grands Œuvres et apprend tes habitudes."},
	apocalypse = {label = "Apocalypse", actions = 3, cataclysms = 6, collapse_limit = 6, deck = 96,
		samael = "Samaël consulte l'Oracle comme toi pour viser ce qui fera le plus mal dans plusieurs manches."},
}

## Modes (§10) : Éternité (par défaut, calme, sans fin) ou Épreuve (victoire ou défaite).
const MODE_ORDER := ["eternity", "trial"]
const DEFAULT_MODE := "eternity"
const MODES := {
	eternity = {label = "Éternité",
		text = "Calme et sans fin. Une défaite ferme un chapitre, puis la vie repart. Samaël propose des défis facultatifs ; ses menaces peuvent passer sans pénalité. Les Grands Œuvres se collectionnent."},
	trial = {label = "Épreuve",
		text = "Toi contre le monde : quatre Grands Œuvres pour gagner ; effondrements, parcelle morte ou sablier vide pour perdre. Samaël joue selon la difficulté."},
}
## Éternité : pourquoi un chapitre se ferme (le texte d'Ézéchiel vient de src/ai/).
const CHAPTER_REASONS := {
	collapses = "Les effondrements se sont enchaînés : un chapitre se ferme, le monde continue.",
	parcel_dead = "La parcelle s'est tue : un chapitre se ferme, la vie reviendra.",
	deck_empty = "Le sablier s'est retourné : un nouveau chapitre commence.",
	works_complete = "Les quatre Grands Œuvres sont accomplis : un chapitre se ferme en beauté.",
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
## Fin de la dernière étape du prologue pour le calcul de sa durée (fin du Trias inférieur).
const PROLOGUE_END_YEAR := -201.0e6
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
		counters = ["save", "bless"], weight = 3.0, max_era = Eras.MESOZOIC - 1},
	anoxia = {title = "Anoxie des mers", text = "Les eaux s'asphyxient.",
		acts = ["prologue", "act1"], strike = "plague", target = "abundant", radius = 12,
		counters = ["flood", "bless"], weight = 2.0, max_era = Eras.MESOZOIC},
	snowball = {title = "Terre boule de neige", text = "La planète gèle.",
		acts = ["prologue"], strike = "ice_age", target = "none", radius = 30,
		counters = ["bless", "save"], weight = 1.0, major = true, max_era = Eras.MESOZOIC - 1},
	# --- Monde sauvage ----------------------------------------------------------------------------
	drought = {title = "Sécheresse", text = "Les pluies cessent, les troupeaux dépérissent.",
		acts = ["act1", "act2", "act3"], strike = "plague", target = "herbivore", radius = 8,
		counters = ["flood", "bless"], weight = 2.0, min_era = Eras.MESOZOIC},
	overgrazing = {title = "Surpâturage", text = "Une espèce trop nombreuse ravage la parcelle.",
		acts = ["act1", "act2", "act3"], strike = "plague", target = "herbivore", radius = 8,
		counters = ["plague", "flood"], weight = 0.5, min_era = Eras.MESOZOIC},
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
		counters = ["bless", "save"], weight = 1.0, min_era = Eras.MESOZOIC},
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
	# Époques (§9) : min_era / max_era (indices de eras.gd), min_tech (civilisation de tête). L'ère
	# sapiente découle du niveau technologique réel : un monde divergent suit sa technique, pas la date.
	famine = {title = "Famine", text = "Les récoltes manquent.",
		acts = ["act3"], strike = "plague", target = "sapient", radius = 8,
		counters = ["bless", "flood"], weight = 2.0, min_era = Eras.FIRST_SAPIENT_ERA + 1, min_tech = 1.0},
	war = {title = "Guerre", text = "Les peuples prennent les armes.",
		acts = ["act3"], strike = "plague", target = "sapient", radius = 10,
		counters = ["bless", "uplift"], weight = 1.5, min_era = Eras.FIRST_SAPIENT_ERA + 1, min_tech = 1.0},
	pollution = {title = "Pollution industrielle", text = "Fumées et rejets montent jusqu'au ciel.",
		acts = ["act3"], strike = "flood", target = "none", radius = 12,
		counters = ["uplift", "ice_age"], weight = 0.0, min_era = Eras.FIRST_SAPIENT_ERA + 4, min_tech = 4.0},
	nuclear_war = {title = "Guerre nucléaire", text = "Les arsenaux de l'atome s'ouvrent.",
		acts = ["act3"], strike = "meteor", target = "none", radius = 3,
		counters = ["bless", "uplift"], weight = 0.0, major = true,
		min_era = Eras.FIRST_SAPIENT_ERA + 5, min_tech = 5.25},
	hostile_ai = {title = "IA hostile", text = "Une intelligence née des machines se retourne contre ses créateurs.",
		acts = ["act3"], strike = "plague", target = "sapient", radius = 20,
		counters = ["uplift", "save"], weight = 0.0, major = true,
		min_era = Eras.FIRST_SAPIENT_ERA + 5, min_tech = AI_TECH},
}

## Cataclysme pioché : menace majeure tirée selon l'acte.
const MAJOR_BY_ACT := {
	prologue = ["snowball", "impact", "supervolcano"],
	act1 = ["impact", "supervolcano", "glaciation"],
	act2 = ["glaciation", "supervolcano", "impact"],
	act3 = ["hostile_ai", "nuclear_war", "supervolcano", "impact"],
}

## Borne d'ère « aucune limite ».
const NO_ERA_LIMIT := 1000000
## Âge de l'information (≈ 2025) : réseaux d'ordinateurs (jalon à 75 % du niveau 5).
const AI_TECH := 5.75
## Pouvoirs divins proposés en contre : intemporels (ce sont des gestes de Dieu), mais la table
## permet de borner un pouvoir à une époque si l'un d'eux devenait anachronique.
const POWER_MIN_ERA := {}

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


## Durée d'une manche en pas idéaux. Prologue : une manche par étape, d'après la durée de
## référence de l'étape (eras.gd, PROLOGUE_REFERENCE_YEARS) au pas idéal de l'ère.
static func round_steps(era: int, act: String) -> float:
	if act == "act3":
		return ROUND_STEPS
	if act == "prologue":
		var refs: Array = Eras.PROLOGUE_REFERENCE_YEARS
		if era >= 0 and era < refs.size():
			var end_year: float = refs[era + 1] if era + 1 < refs.size() else PROLOGUE_END_YEAR
			return clampf((end_year - float(refs[era])) / Eras.ideal_dt(era), ROUND_STEPS_WILD, ROUND_STEPS)
	return ROUND_STEPS_WILD


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


## Pouvoirs qui contrent une menace de ce type (filtrés par époque si `era` est donné).
static func counters(kind: String, era := NO_ERA_LIMIT) -> Array[String]:
	var out: Array[String] = []
	for c in THREATS.get(kind, {}).get("counters", []):
		if era >= int(POWER_MIN_ERA.get(c, -NO_ERA_LIMIT)):
			out.append(String(c))
	return out


## Zéro anachronisme (§9) : la carte est-elle possible à cette ère, avec ce niveau technologique de
## la civilisation de tête (-1 : aucune) ?
static func epoch_ok(kind: String, era: int, lead_tech: float) -> bool:
	var def: Dictionary = THREATS.get(kind, {})
	if def.is_empty():
		return false
	if era < int(def.get("min_era", -NO_ERA_LIMIT)) or era > int(def.get("max_era", NO_ERA_LIMIT)):
		return false
	return not def.has("min_tech") or lead_tech >= float(def.min_tech)


## Types de carte légaux maintenant (acte et époque).
static func legal_kinds(act: String, era: int, lead_tech: float, majors := false) -> Array[String]:
	var out: Array[String] = []
	for k in THREATS:
		var def: Dictionary = THREATS[k]
		if bool(def.get("major", false)) == majors and act in def.acts and epoch_ok(k, era, lead_tech):
			out.append(String(k))
	out.sort()
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
