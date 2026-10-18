extends RefCounted
## Zéro anachronisme (docs/STRATEGIE.md §9) : l'époque effective du monde et ce qu'on n'a pas le droit
## d'y mentionner. Aucune dépendance : utilisable par tous les fichiers de src/ai/.
##
## Indices d'époque (alignés sur src/sim/eras.gd avec le prologue) :
## 0 Archéen, 1 Grande Oxydation, 2 Terre boule de neige, 3 Explosion cambrienne, 4 Sortie des eaux,
## 5 Carbonifère, 6 Grande Mourance, 7 Mésozoïque (Trias, Jurassique, Crétacé), 8 Cénozoïque,
## 9 Préhistoire, 10 Antiquité, 11 Moyen Âge, 12 Renaissance, 13 Industriel, 14 Moderne (âge de
## l'information), 15 Cyberpunk, 16 Post-singularité.
##
## Époque effective (current) : s'il existe une espèce intelligente, son niveau technologique RÉEL
## (9 + niveau, comme Eras.era_for_tech) — y compris dans un monde divergent ; sinon la date (prologue)
## ou l'ère de la simulation.

const NAMES := [
	"Archéen", "Grande Oxydation", "Terre boule de neige", "Explosion cambrienne", "Sortie des eaux",
	"Carbonifère", "Grande Mourance", "Mésozoïque", "Cénozoïque", "Préhistoire", "Antiquité", "Moyen Âge",
	"Renaissance", "Industriel", "Moderne", "Cyberpunk", "Post-singularité",
]
const ARCHEAN := 0
const FIRST_ANIMALS := 2
const CAMBRIAN := 3
const LAND := 4
const MESOZOIC := 7
const CENOZOIC := 8
const FIRST_SAPIENT := 9
const ANTIQUITY := 10
const MIDDLE_AGES := 11
const RENAISSANCE := 12
const INDUSTRIAL := 13
const INFORMATION := 14
const CYBERPUNK := 15
const LAST := 16

## Étapes datées avant -66 Ma : [nom, début (années), époque].
const STAGES := [
	["Archéen", -4_600_000_000.0, 0], ["Grande Oxydation", -2_500_000_000.0, 1], ["Terre boule de neige", -800_000_000.0, 2],
	["Explosion cambrienne", -539_000_000.0, 3], ["Sortie des eaux", -419_000_000.0, 4], ["Carbonifère", -359_000_000.0, 5],
	["Grande Mourance", -260_000_000.0, 6], ["Trias", -251_900_000.0, 7], ["Jurassique", -201_300_000.0, 7],
	["Mésozoïque", -145_000_000.0, 7],
]
const STAGES_END := -66_000_000.0
## Sous-étapes et synonymes -> époque.
const ALIASES := {"Trias": 7, "Jurassique": 7, "Crétacé": 7, "Industrielle": 13, "Post-singularite": 16}

## Mots interdits avant une époque : [motif d'expression régulière (insensible à la casse), époque minimale, libellé].
## Les faits réels (facts/) n'y passent pas : ils sont vrais à leur date. Le texte du narrateur, de
## l'adversaire, des dilemmes et du LLM, si.
const WORDS := [
	# Âge de l'information.
	["\\bIA\\b", INFORMATION, "IA"], ["intelligences? artificielles?", INFORMATION, "intelligence artificielle"],
	["ordinateur", INFORMATION, "ordinateur"], ["informati", INFORMATION, "informatique"], ["internet", INFORMATION, "Internet"],
	["numérique", INFORMATION, "numérique"], ["\\brobot", INFORMATION, "robot"], ["satellite", INFORMATION, "satellite"],
	["écrans?\\b", INFORMATION, "écran"], ["algorithme", INFORMATION, "algorithme"], ["\\bdonnées? numériques", INFORMATION, "données"],
	["flux de données", INFORMATION, "flux de données"], ["nucléaire", INFORMATION, "nucléaire"], ["atomique", INFORMATION, "atomique"],
	["plastique", INFORMATION, "plastique"], ["fusée", INFORMATION, "fusée"],
	["cyborg", CYBERPUNK, "cyborg"], ["implants?\\b", CYBERPUNK, "implant"], ["arcologie", CYBERPUNK, "arcologie"],
	# Âge industriel.
	["électri", INDUSTRIAL, "électricité"], ["\\busines?\\b", INDUSTRIAL, "usine"], ["locomotive", INDUSTRIAL, "locomotive"],
	["chemins? de fer", INDUSTRIAL, "chemin de fer"], ["automobile", INDUSTRIAL, "automobile"], ["\\bvoitures?\\b", INDUSTRIAL, "voiture"],
	["\\bavions?\\b", INDUSTRIAL, "avion"], ["téléphone", INDUSTRIAL, "téléphone"], ["pétrole", INDUSTRIAL, "pétrole"],
	["pollution", INDUSTRIAL, "pollution"], ["\\bmoteurs?\\b", INDUSTRIAL, "moteur"], ["machine à vapeur", INDUSTRIAL, "machine à vapeur"],
	["\\bmachines?\\b", INDUSTRIAL, "machine"], ["néons?\\b", INDUSTRIAL, "néon"], ["mégapole", INDUSTRIAL, "mégapole"],
	["\\bbombes?\\b", INDUSTRIAL, "bombe"],
	# Renaissance et Moyen Âge.
	["\\bfusils?\\b", RENAISSANCE, "fusil"], ["lunette astronomique", RENAISSANCE, "lunette astronomique"],
	["imprim", MIDDLE_AGES, "imprimerie"], ["\\bcanons?\\b", MIDDLE_AGES, "canon"], ["boussole", MIDDLE_AGES, "boussole"],
	["cathédrale", MIDDLE_AGES, "cathédrale"], ["chevalier", MIDDLE_AGES, "chevalier"],
	# Antiquité (« famine », « guerre » : STRATEGIE.md §9).
	["\\bguerres?\\b", ANTIQUITY, "guerre"], ["\\bfamines?\\b", ANTIQUITY, "famine"], ["\\brois?\\b", ANTIQUITY, "roi"],
	["\\bempires?\\b", ANTIQUITY, "empire"], ["écriture", ANTIQUITY, "écriture"], ["monnaie", ANTIQUITY, "monnaie"],
	["\\bbronze\\b", ANTIQUITY, "bronze"], ["\\bforges?\\b", ANTIQUITY, "forge"], ["\\bsoldats?\\b", ANTIQUITY, "soldat"],
	["\\bépées?\\b", ANTIQUITY, "épée"], ["\\blégions?\\b", ANTIQUITY, "légion"],
	# Premiers peuples.
	["\\bvillages?\\b", FIRST_SAPIENT, "village"], ["\\bvilles?\\b", FIRST_SAPIENT, "ville"], ["greniers?", FIRST_SAPIENT, "grenier"],
	["récoltes?", FIRST_SAPIENT, "récolte"], ["\\bbergers?\\b", FIRST_SAPIENT, "berger"], ["\\bpeuples?\\b", FIRST_SAPIENT, "peuple"],
	["\\bprières?\\b", FIRST_SAPIENT, "prière"], ["\\bprient\\b", FIRST_SAPIENT, "prier"], ["\\btemples?\\b", FIRST_SAPIENT, "temple"],
	# La vie : rien avant son apparition.
	["\\bherbes?\\b", CENOZOIC, "herbe"], ["\\bmammifères?\\b", MESOZOIC, "mammifère"], ["dinosaure", MESOZOIC, "dinosaure"],
	["\\boiseaux?\\b", MESOZOIC, "oiseau"], ["\\bfleurs?\\b", MESOZOIC, "fleur"], ["\\bplumes?\\b", MESOZOIC, "plume"],
	["fourrure", MESOZOIC, "fourrure"], ["\\bforêts?\\b", LAND, "forêt"], ["\\barbres?\\b", LAND, "arbre"],
	["fougères?", LAND, "fougère"], ["\\binsectes?\\b", LAND, "insecte"], ["\\bpoissons?\\b", CAMBRIAN, "poisson"],
	["carapace", CAMBRIAN, "carapace"], ["\\bgriffes?\\b", CAMBRIAN, "griffe"], ["\\bcrocs?\\b", CAMBRIAN, "croc"],
	["\\bsang\\b", CAMBRIAN, "sang"], ["\\bbêtes?\\b", FIRST_ANIMALS, "bête"], ["\\banimaux\\b|\\banimal\\b", FIRST_ANIMALS, "animal"],
	["troupeaux?", FIRST_ANIMALS, "troupeau"], ["coquille", FIRST_ANIMALS, "coquille"],
]


## Époque d'un nom d'ère ou d'étape (-1 si inconnu).
static func index_of(name: Variant) -> int:
	var s := _fold(str(name))
	for i in NAMES.size():
		if _fold(NAMES[i]) == s:
			return i
	for k in ALIASES:
		if _fold(k) == s:
			return int(ALIASES[k])
	return -1


## Étape datée (nom) pour une date avant -66 Ma, sinon "".
static func stage_from_year(year: Variant) -> String:
	if not (typeof(year) in [TYPE_INT, TYPE_FLOAT]) or float(year) >= STAGES_END:
		return ""
	var stage: String = STAGES[0][0]
	for s in STAGES:
		if float(year) >= float(s[1]):
			stage = s[0]
	return stage


## Époque d'après l'ère et la date seulement (sans connaître les espèces).
static func from_era_year(era: Variant, year: Variant) -> int:
	var stage := stage_from_year(year)
	if stage != "":
		return index_of(stage)
	var i := index_of(era)
	if i >= 0:
		return i
	return CENOZOIC if typeof(year) in [TYPE_INT, TYPE_FLOAT] else LAST


## Époque effective d'un contexte {era, year, species: [{sapient, alive, tech_level}]} : le niveau
## technologique réel de la civilisation de tête s'il y en a une, sinon l'ère et la date.
static func current(ctx: Dictionary) -> int:
	var best := -1.0
	for sp in ctx.get("species", []):
		if sp is Dictionary and bool(sp.get("sapient", false)) and bool(sp.get("alive", true)):
			best = maxf(best, float(sp.get("tech_level", 0.0)))
	if best >= 0.0:
		return clampi(FIRST_SAPIENT + int(floorf(best)), FIRST_SAPIENT, LAST)
	return mini(from_era_year(ctx.get("era", ""), ctx.get("year", null)), CENOZOIC) \
		if typeof(ctx.get("year")) in [TYPE_INT, TYPE_FLOAT] else from_era_year(ctx.get("era", ""), null)


## Mots du texte interdits à cette époque (libellés), [] si le texte est propre.
static func violations(text: String, epoch: int) -> Array:
	var out := []
	for w in WORDS:
		if epoch >= int(w[1]):
			continue
		var re := RegEx.create_from_string("(?i)" + str(w[0]))
		if re != null and re.search(text) != null and not w[2] in out:
			out.append(w[2])
	return out


static func is_clean(text: String, epoch: int) -> bool:
	return violations(text, epoch).is_empty()


## Ce qu'on n'a pas le droit de mentionner à cette époque (pour les prompts du LLM).
static func forbidden_labels(epoch: int) -> Array:
	var out := []
	for w in WORDS:
		if epoch < int(w[1]) and not w[2] in out:
			out.append(w[2])
	return out


## L'élément ({min_era, max_era, min_tech}) est-il permis à cette époque ? tech : niveau réel (-1 inconnu).
static func allows(item: Dictionary, epoch: int, tech := -1.0) -> bool:
	if item.has("min_era") and epoch < int(item["min_era"]):
		return false
	if item.has("max_era") and epoch > int(item["max_era"]):
		return false
	if item.has("min_tech") and tech >= 0.0 and tech < float(item["min_tech"]):
		return false
	return true


static func _fold(s: String) -> String:
	var t := s.strip_edges().to_lower()
	for pair in [["é", "e"], ["è", "e"], ["ê", "e"], ["ë", "e"], ["â", "a"], ["à", "a"], ["ï", "i"], ["î", "i"], ["ô", "o"], ["ù", "u"], ["û", "u"], ["ç", "c"], ["-", " "], ["_", " "]]:
		t = t.replace(pair[0], pair[1])
	return t
