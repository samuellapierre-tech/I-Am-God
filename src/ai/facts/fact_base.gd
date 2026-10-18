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
##   et n'est jamais choisi.
## Les ères Cyberpunk et Post-singularité n'ont pas de faits : elles appartiennent au futur, inventé.

const Mesozoique := preload("res://src/ai/facts/mesozoique.gd")
const Cenozoique := preload("res://src/ai/facts/cenozoique.gd")
const Prehistoire := preload("res://src/ai/facts/prehistoire.gd")
const Antiquite := preload("res://src/ai/facts/antiquite.gd")
const MoyenAge := preload("res://src/ai/facts/moyen_age.gd")
const Renaissance := preload("res://src/ai/facts/renaissance.gd")
const Industriel := preload("res://src/ai/facts/industriel.gd")
const Moderne := preload("res://src/ai/facts/moderne.gd")

## Ères de l'histoire réelle, dans l'ordre (noms de procedural_narrator.gd / WorldSim.current_era()).
const REAL_ERAS := ["Mésozoïque", "Cénozoïque", "Préhistoire", "Antiquité", "Moyen Âge", "Renaissance", "Industriel", "Moderne"]
const TAG_KEYS := ["clade", "biome", "land_use", "event"]
## Poids d'un tag qui correspond à la situation (un fait général vaut 1).
const TAG_WEIGHTS := {"clade": 3.0, "biome": 2.0, "land_use": 3.0, "event": 4.0}


## Faits d'une ère (clé de Procedural.era_key), chacun complété de son identifiant « ère#indice ».
static func era_facts(era: String) -> Array:
	var raw: Array = []
	match era:
		"Mésozoïque": raw = Mesozoique.FACTS
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
