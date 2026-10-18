extends RefCounted
## Base de faits RÉELS sur l'histoire de la Terre, racontés tant que le monde suit l'histoire vraie.
## Les faits sont écrits à la main (jamais générés par le LLM, qui peut seulement les reformuler).
##
## Un fichier par ère réelle (src/ai/facts/<ère>.gd) avec const FACTS := [{...}] :
## - t : le fait, 1 à 2 phrases, vrai, dit comme par un conteur ;
## - clade / biome / land_use / event : Array[String] facultatifs, servent à préférer les faits qui
##   parlent de ce que l'on voit sur la parcelle (clades de WorldSim, BIOME_NAMES, ParcelSim.LAND_USES,
##   types d'événements canoniques ou bruts de la simulation) ;
## - min_year / max_year : facultatifs ; hors de cette fenêtre, le fait n'est pas vrai à cette date
##   et n'est jamais choisi. Un fichier peut fixer const WINDOW := [min, max] : fenêtre de tous ses faits.
## Les ères Cyberpunk et Post-singularité n'ont pas de faits : elles appartiennent au futur, inventé.
##
## Étapes : avant -66 Ma, l'étape se lit dans la date (stage_for) : Archéen, Grande Oxydation, Terre
## boule de neige, Explosion cambrienne, Sortie des eaux, Carbonifère, Grande Mourance, Trias,
## Jurassique, puis Mésozoïque (fin du Crétacé). Ensuite, l'ère de la simulation fait foi.

const Archeen := preload("res://src/ai/facts/archeen.gd")
const GrandeOxydation := preload("res://src/ai/facts/grande_oxydation.gd")
const BouleDeNeige := preload("res://src/ai/facts/boule_de_neige.gd")
const Cambrien := preload("res://src/ai/facts/cambrien.gd")
const SortieDesEaux := preload("res://src/ai/facts/sortie_des_eaux.gd")
const Carbonifere := preload("res://src/ai/facts/carbonifere.gd")
const GrandeMourance := preload("res://src/ai/facts/grande_mourance.gd")
const Trias := preload("res://src/ai/facts/trias.gd")
const Jurassique := preload("res://src/ai/facts/jurassique.gd")
const Mesozoique := preload("res://src/ai/facts/mesozoique.gd")
const Cenozoique := preload("res://src/ai/facts/cenozoique.gd")
const Prehistoire := preload("res://src/ai/facts/prehistoire.gd")
const Antiquite := preload("res://src/ai/facts/antiquite.gd")
const MoyenAge := preload("res://src/ai/facts/moyen_age.gd")
const Renaissance := preload("res://src/ai/facts/renaissance.gd")
const Industriel := preload("res://src/ai/facts/industriel.gd")
const Moderne := preload("res://src/ai/facts/moderne.gd")

## Étapes du prologue et de l'acte I, datées : [nom, début (années)]. L'étape court jusqu'au début de la suivante.
const STAGES := [
	["Archéen", -4_600_000_000.0], ["Grande Oxydation", -2_500_000_000.0], ["Terre boule de neige", -800_000_000.0],
	["Explosion cambrienne", -539_000_000.0], ["Sortie des eaux", -419_000_000.0], ["Carbonifère", -359_000_000.0],
	["Grande Mourance", -260_000_000.0], ["Trias", -251_900_000.0], ["Jurassique", -201_300_000.0],
	["Mésozoïque", -145_000_000.0],
]
## Fin des étapes datées : au-delà, l'ère de la simulation fait foi.
const STAGES_END := -66_000_000.0
const PROLOGUE := ["Archéen", "Grande Oxydation", "Terre boule de neige", "Explosion cambrienne", "Sortie des eaux",
	"Carbonifère", "Grande Mourance"]
## Étapes et ères de l'histoire réelle, dans l'ordre (noms de procedural_narrator.gd / WorldSim.current_era()).
const REAL_ERAS := ["Archéen", "Grande Oxydation", "Terre boule de neige", "Explosion cambrienne", "Sortie des eaux",
	"Carbonifère", "Grande Mourance", "Trias", "Jurassique",
	"Mésozoïque", "Cénozoïque", "Préhistoire", "Antiquité", "Moyen Âge", "Renaissance", "Industriel", "Moderne"]
const Procedural := preload("res://src/ai/procedural_narrator.gd")
const Epoch := preload("res://src/ai/epoch.gd")
const TAG_KEYS := ["clade", "biome", "land_use", "event"]
## Poids d'un tag qui correspond à la situation (un fait général vaut 1).
const TAG_WEIGHTS := {"clade": 3.0, "biome": 2.0, "land_use": 3.0, "event": 4.0}


## Étape de l'histoire réelle pour une ère de la simulation et une date : avant -66 Ma, la date fait foi
## (la simulation peut nommer ses ères du prologue autrement) ; ensuite, l'ère (Procedural.era_key).
static func stage_for(era: Variant, year: Variant) -> String:
	if typeof(year) in [TYPE_INT, TYPE_FLOAT] and float(year) < STAGES_END:
		var stage: String = STAGES[0][0]
		for s in STAGES:
			if float(year) >= float(s[1]):
				stage = s[0]
		return stage
	var key := Procedural.era_key(era)
	if key == "generic":
		# Nom d'étape déjà résolu (ou nom d'ère du prologue identique à nos étapes).
		var s := str(era).strip_edges()
		if s in REAL_ERAS:
			return s
	return key


## Faits d'une ère ou d'une étape, chacun complété de son identifiant « ère#indice » et, si le fichier en
## fixe une, de sa fenêtre de dates (resserrée par celle du fait).
static func era_facts(era: String) -> Array:
	var raw: Array = []
	var window: Array = []
	match era:
		"Archéen": raw = Archeen.FACTS; window = Archeen.WINDOW
		"Grande Oxydation": raw = GrandeOxydation.FACTS; window = GrandeOxydation.WINDOW
		"Terre boule de neige": raw = BouleDeNeige.FACTS; window = BouleDeNeige.WINDOW
		"Explosion cambrienne": raw = Cambrien.FACTS; window = Cambrien.WINDOW
		"Sortie des eaux": raw = SortieDesEaux.FACTS; window = SortieDesEaux.WINDOW
		"Carbonifère": raw = Carbonifere.FACTS; window = Carbonifere.WINDOW
		"Grande Mourance": raw = GrandeMourance.FACTS; window = GrandeMourance.WINDOW
		"Trias": raw = Trias.FACTS; window = Trias.WINDOW
		"Jurassique": raw = Jurassique.FACTS; window = Jurassique.WINDOW
		"Mésozoïque": raw = Mesozoique.FACTS; window = Mesozoique.WINDOW
		"Cénozoïque": raw = Cenozoique.FACTS
		"Préhistoire": raw = Prehistoire.FACTS
		"Antiquité": raw = Antiquite.FACTS
		"Moyen Âge": raw = MoyenAge.FACTS
		"Renaissance": raw = Renaissance.FACTS
		"Industriel": raw = Industriel.FACTS
		"Moderne": raw = Moderne.FACTS
	var out := []
	for i in raw.size():
		var f: Dictionary = raw[i].duplicate()
		f["id"] = "%s#%d" % [era, i]
		# Époque explicite (STRATEGIE.md §9) : un fait n'appartient qu'à son étape ou à son ère.
		f["min_era"] = maxi(0, Epoch.index_of(era))
		f["max_era"] = maxi(0, Epoch.index_of(era))
		if window.size() == 2:
			f["min_year"] = maxf(float(window[0]), float(f.get("min_year", -INF)))
			f["max_year"] = minf(float(window[1]), float(f.get("max_year", INF)))
		out.append(f)
	return out


## Le fait est-il vrai à cette date ? (year null = date inconnue : seuls les faits sans fenêtre passent)
static func true_at(fact: Dictionary, year: Variant) -> bool:
	if not (fact.has("min_year") or fact.has("max_year")):
		return true
	if not (typeof(year) in [TYPE_INT, TYPE_FLOAT]):
		return false
	var y := float(year)
	return y >= float(fact.get("min_year", -INF)) and y <= float(fact.get("max_year", INF))


## Faits racontables à cette ère et à cette date.
static func candidates(era: String, year: Variant) -> Array:
	return era_facts(era).filter(func(f: Dictionary) -> bool: return true_at(f, year))


## Pertinence d'un fait pour la situation. situation : {clades: [], biome, land_use, events: []}.
static func score(fact: Dictionary, situation: Dictionary) -> float:
	var s := 1.0
	var wanted := {
		"clade": situation.get("clades", []), "biome": [situation.get("biome", "")],
		"land_use": [situation.get("land_use", "")], "event": situation.get("events", []),
	}
	for key in TAG_KEYS:
		var tags: Array = fact.get(key, [])
		for v in wanted[key]:
			if str(v) != "" and str(v) in tags:
				s += TAG_WEIGHTS[key]
				break
	return s


## Choisit un fait vrai et pertinent, différent des `recent` (identifiants) ; {} s'il n'y en a pas.
static func pick(era: String, year: Variant, situation: Dictionary, recent: Array, rng: RandomNumberGenerator) -> Dictionary:
	var pool := candidates(era, year).filter(func(f: Dictionary) -> bool: return not f["id"] in recent)
	if pool.is_empty():
		return {}
	var total := 0.0
	var weights := []
	for f in pool:
		var w := score(f, situation)
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in pool.size():
		r -= float(weights[i])
		if r <= 0.0:
			return pool[i]
	return pool[-1]
