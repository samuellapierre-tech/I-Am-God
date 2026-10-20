extends RefCounted
## Le narrateur présente chaque espèce marquante à sa naissance (nom, apparence, mode de vie) et écrit
## l'épitaphe d'une espèce éteinte. Tout se déduit des traits (docs/GENESE.md) : rien n'est inventé
## qui contredise la simulation.
##
## Espèce : {id, name, traits: {size 0..1 (échelle log de la masse : 1 = titanosaure), diet, clade,
## intelligence, temp_opt, temp_tol, aggression, adaptability, ...}, born_year, extinct_year, sapient}.
## Génome étendu (session Vie), lu s'il existe, dans traits ou à la racine : body_plan, locomotion,
## covering, colors (noms ou Color), color, habitat | medium, sociality, energy ("photo" | "chemo").
## Si la session Vie fournit une description (sp.description) ou une apparence (sp.appearance), elles
## sont utilisées telles quelles. Déterministe à graine égale ; aucun anachronisme (epoch.gd).

const Procedural := preload("res://src/ai/procedural_narrator.gd")
const ParcelNarrator := preload("res://src/ai/parcel_narrator.gd")
const Epoch := preload("res://src/ai/epoch.gd")
const Explainer := preload("res://src/ai/explainer.gd")

## Taille (trait size) -> ordre de grandeur, formulé sans comparaison anachronique.
const SIZES := [
	[0.02, "de taille microscopique"], [0.035, "de quelques millimètres"], [0.07, "de quelques centimètres"],
	[0.15, "d'une vingtaine de centimètres"], [0.3, "d'un demi-mètre environ"], [0.5, "d'un à deux mètres"],
	[0.7, "de plusieurs mètres"], [0.9, "d'une dizaine de mètres"], [9.0, "de plus de vingt mètres"],
]
## Plan du corps, par plan explicite (génome) ou par lignée. Formes invariables (« au corps… »).
const BODY_PLANS := {
	"unicellular": "à une seule cellule", "colonial": "aux cellules qui vivent en colonie",
	"radial": "au corps rayonnant", "bilateral": "au corps symétrique", "segmented": "au corps fait d'anneaux",
	"vertebrate": "à colonne vertébrale", "sessile": "au pied ancré au fond", "filament": "aux longs filaments",
	"tentacled": "aux bras souples", "shelled": "à l'abri d'une coquille", "winged": "aux ailes déployées",
}
const CLADE_BODIES := {
	"microbe": "à une seule cellule", "algue": "aux filaments chargés de pigments", "éponge": "au corps poreux ancré au fond",
	"arthropode": "au corps articulé", "mollusque": "au corps mou", "poisson": "au corps fuselé",
	"amphibien": "à la peau nue et humide", "reptile": "au corps allongé", "dinosaure": "à la longue queue",
	"oiseau": "au bec corné", "mammifère": "au corps chaud", "primate": "aux mains habiles", "ptérosaure": "aux ailes de peau",
	"insecte": "à six pattes", "plante": "aux tiges dressées", "synapside": "au corps trapu", "chimère": "au corps qui ne ressemble à rien de connu",
}
## Couverture (génome, mots anglais ou français) ou par lignée. Formes invariables.
const COVERINGS := {
	"scales": "sous un manteau d'écailles", "écailles": "sous un manteau d'écailles", "fur": "sous une épaisse fourrure",
	"fourrure": "sous une épaisse fourrure", "feathers": "sous un plumage", "plumes": "sous un plumage",
	"shell": "à l'abri d'une coquille", "coquille": "à l'abri d'une coquille", "chitin": "sous une carapace de chitine",
	"carapace": "sous une carapace", "skin": "à la peau nue", "peau": "à la peau nue", "slime": "sous une couche de mucus",
	"mucus": "sous une couche de mucus", "bark": "sous une écorce", "membrane": "sous une fine membrane",
	"cilia": "aux cils vibrants", "cils": "aux cils vibrants", "plates": "sous des plaques osseuses",
}
const CLADE_COVERINGS := {
	"arthropode": "carapace", "mollusque": "coquille", "poisson": "scales", "amphibien": "skin", "reptile": "scales",
	"dinosaure": "scales", "oiseau": "feathers", "mammifère": "fur", "primate": "fur", "ptérosaure": "membrane",
	"insecte": "chitin", "synapside": "skin", "microbe": "membrane", "algue": "membrane",
}
## Déplacement (génome) : verbe accordé en nombre.
const LOCOMOTIONS := {
	"swim": "[espece:nage|nagent]", "nage": "[espece:nage|nagent]", "walk": "[espece:marche|marchent]",
	"run": "[espece:court|courent]", "fly": "[espece:vole|volent]", "glide": "[espece:plane|planent]",
	"crawl": "[espece:rampe|rampent]", "slither": "[espece:ondule|ondulent]", "burrow": "[espece:creuse|creusent] des galeries",
	"climb": "[espece:grimpe|grimpent]", "hop": "[espece:bondit|bondissent]", "drift": "[espece:dérive|dérivent]",
	"sessile": "[espece:vit|vivent] [espece:fixée|fixés]", "fixed": "[espece:vit|vivent] [espece:fixée|fixés]",
}
const CLADE_LOCOMOTIONS := {
	"microbe": "drift", "algue": "drift", "éponge": "sessile", "arthropode": "crawl", "mollusque": "crawl", "poisson": "swim",
	"amphibien": "hop", "reptile": "crawl", "dinosaure": "walk", "oiseau": "fly", "mammifère": "run", "primate": "climb",
	"ptérosaure": "glide", "insecte": "crawl", "plante": "sessile", "synapside": "walk",
}
## Milieu de vie (génome habitat | medium) ou par lignée.
const HABITATS := {
	"ocean": "dans les mers", "marine": "dans les mers", "sea": "dans les mers", "shallow": "dans les eaux peu profondes",
	"deep": "dans les abysses", "abyss": "dans les abysses", "vents": "près des sources chaudes", "freshwater": "dans les eaux douces",
	"land": "sur la terre ferme", "terrestrial": "sur la terre ferme", "air": "dans les airs", "coast": "sur les rivages",
	"soil": "dans le sol", "ice": "sur les glaces", "amphibious": "entre l'eau et la terre",
}
const CLADE_HABITATS := {
	"microbe": "shallow", "algue": "shallow", "éponge": "ocean", "arthropode": "shallow", "mollusque": "ocean", "poisson": "ocean",
	"amphibien": "coast", "plante": "land", "insecte": "land", "reptile": "land", "dinosaure": "land", "oiseau": "air",
	"mammifère": "land", "primate": "land", "ptérosaure": "air", "synapside": "land",
}
## Teintes par défaut, selon le milieu. Formes invariables (« aux teintes … »).
const DEFAULT_TINTS := {
	"ocean": ["bleutées", "argentées", "translucides"], "shallow": ["vertes", "dorées", "translucides"],
	"deep": ["pâles", "rougeâtres", "noires"], "vents": ["pâles", "orangées"], "land": ["brunes", "ocre", "grises"],
	"air": ["claires", "fauves"], "coast": ["vertes et brunes", "grises"],
}
const COLOR_NAMES := ["rouges", "orangées", "jaunes", "vertes", "turquoise", "bleues", "violettes", "pourpres"]

const PRESENT_TEMPLATES := [
	"Une espèce nouvelle est née : {espece}. [espece:C'est un être|Ce sont des êtres] {taille}, {corps}, {couverture}, aux teintes {teintes}, qui {locomotion} {milieu}. [espece:Elle|Ils] {mode_bas}",
	"Je te présente {espece} : {taille_maj}, {corps}, aux teintes {teintes}. [espece:Elle|Ils] {locomotion} {milieu}, et {mode_bas}",
	"Un nouveau venu parmi les vivants : {espece}. {taille_maj}, {couverture}, [espece:elle|ils] {locomotion} {milieu} ; {mode_bas}",
]
const EPITAPH_TEMPLATES := [
	"Ci-gît {espece}, [espece:apparue|apparus] {naissance}, après {duree} d'existence. {cause}",
	"{espece} [espece:n'est plus|ne sont plus]. [espece:Elle avait|Ils avaient] vécu {duree}, {vie}. {cause}",
	"Une page se ferme : {espece} [espece:disparaît|disparaissent] après {duree}. {cause}",
]
const EPITAPH_NO_DATE := [
	"{espece} [espece:n'est plus|ne sont plus] : {vie}, voilà ce que je garde [espece:d'elle|d'eux]. {cause}",
	"Une page se ferme sur {espece}, [espece:qui vivait|qui vivaient] {milieu}. {cause}",
]
const CAUSES := {
	"climate": "Le climat a changé plus vite [espece:qu'elle ne pouvait|qu'ils ne pouvaient] s'adapter.",
	"predation": "[espece:Ses|Leurs] prédateurs se sont multipliés plus vite que [espece:ses|leurs] petits.",
	"competition": "D'autres, plus habiles à vivre de la même nourriture, [espece:l'ont évincée|les ont évincés].",
	"impact": "Le feu tombé du ciel ne [espece:lui|leur] a laissé aucune chance.",
	"divine": "Tu [espece:l'as effacée|les as effacés] toi-même.",
	"oxygen": "L'oxygène, qui les nourrissait d'énergie ou les empoisonnait, a changé trop vite pour [espece:elle|eux].",
	"unknown": "Nul ne saura tout à fait pourquoi.",
}
const DEEDS := {
	"seed": "Tu [espece:l'avais semée|les avais semés] toi-même.", "bless": "Tu [espece:l'avais bénie|les avais bénis], autrefois.",
	"save": "Tu [espece:l'avais sauvée|les avais sauvés] une fois déjà.", "spawn_species": "Tu [espece:l'avais façonnée|les avais façonnés] de tes mains.",
}

var rng := RandomNumberGenerator.new()
## Mémoire anti-répétition partagée (variety.gd) ; null = sans.
var variety: RefCounted = null
var _seed := 0
var _count := 0


func _init(p_seed: int = -1) -> void:
	if p_seed >= 0:
		_seed = p_seed
	else:
		rng.randomize()
		_seed = rng.randi()


## Présentation d'une espèce à sa naissance (2 à 3 phrases) : {text, kind: "presentation", species_id}.
func present(sp: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	_count += 1
	rng.seed = hash([_seed, _count, int(sp.get("id", -1)), "present"])
	var epoch := Epoch.current(ctx)
	var slots := portrait(sp, epoch)
	var phrase := Procedural.species_phrase(str(sp.get("name", "")) if str(sp.get("name", "")) != "" else "une lignée sans nom")
	slots["espece"] = phrase["text"]
	var desc := str(sp.get("description", "")).strip_edges()
	if desc != "" and Epoch.is_clean(desc, epoch):
		var t := Procedural.polish("Une espèce nouvelle est née : %s. %s" % [phrase["text"], desc])
		return {"text": t, "kind": "presentation", "species_id": int(sp.get("id", -1))}
	var text := _pick(PRESENT_TEMPLATES, slots, phrase["plural"], epoch)
	if text == "":
		# Aucun portrait sans anachronisme (traits improbables pour l'époque) : le nom seul.
		text = Procedural.polish("Une espèce nouvelle est née : %s." % phrase["text"])
	return {"text": text, "kind": "presentation", "species_id": int(sp.get("id", -1))}


## Épitaphe d'une espèce éteinte (2 à 3 phrases). cause : "climate" | "predation" | "competition" |
## "impact" | "divine" | "oxygen" | "" (déduite de l'état réel, voir Explainer.decline_cause).
## deed : geste du joueur sur cette espèce ("seed", "bless", "save", "spawn_species") ou "".
func epitaph(sp: Dictionary, ctx: Dictionary = {}, cause := "", deed := "") -> Dictionary:
	_count += 1
	rng.seed = hash([_seed, _count, int(sp.get("id", -1)), "epitaph"])
	var epoch := Epoch.current(ctx)
	if cause == "":
		cause = Explainer.decline_cause(sp, ctx)
	var slots := portrait(sp, epoch)
	var phrase := Procedural.species_phrase(str(sp.get("name", "")) if str(sp.get("name", "")) != "" else "une lignée sans nom")
	slots["espece"] = phrase["text"]
	slots["cause"] = Procedural.apply_agreement(str(CAUSES.get(cause, CAUSES["unknown"])), {"espece": phrase["plural"]})
	if DEEDS.has(deed):
		slots["cause"] += " " + Procedural.apply_agreement(str(DEEDS[deed]), {"espece": phrase["plural"]})
	var born: Variant = sp.get("born_year", null)
	var end: Variant = sp.get("extinct_year", ctx.get("year", null))
	var dated := typeof(born) in [TYPE_INT, TYPE_FLOAT] and typeof(end) in [TYPE_INT, TYPE_FLOAT] and not is_nan(float(born)) \
		and not is_nan(float(end)) and float(end) > float(born)
	if dated:
		slots["naissance"] = Procedural.format_year(float(born))
		slots["duree"] = Procedural._duration(float(end) - float(born))
	var text := _pick(EPITAPH_TEMPLATES if dated else EPITAPH_NO_DATE, slots, phrase["plural"], epoch)
	if text == "":
		text = Procedural.polish(Procedural.apply_agreement("Une page se ferme : %s [espece:n'est plus|ne sont plus]." % phrase["text"], {"espece": phrase["plural"]}))
	return {"text": text, "kind": "epitaph", "species_id": int(sp.get("id", -1)), "cause": cause}


## Portrait déduit des traits : taille, corps, couverture, teintes, déplacement, milieu, mode de vie.
## (Emplacements de gabarit ; exposé pour les tests et pour le prompt du LLM.)
func portrait(sp: Dictionary, epoch: int) -> Dictionary:
	var traits: Dictionary = sp.get("traits", {})
	var g := func(key: String, fallback_value: Variant = "") -> Variant: return traits.get(key, sp.get(key, fallback_value))
	var clade := str(g.call("clade", sp.get("clade", "chimère")))
	if not CLADE_BODIES.has(clade):
		clade = "chimère"
	var size := float(g.call("size", 0.3))
	var taille: String = SIZES[-1][1]
	for s in SIZES:
		if size < float(s[0]):
			taille = s[1]
			break
	if clade == "microbe" and size < 0.1:
		taille = "de taille microscopique"
	var plan := str(g.call("body_plan", ""))
	var corps: String = BODY_PLANS.get(plan, CLADE_BODIES[clade])
	var cov_key := str(g.call("covering", CLADE_COVERINGS.get(clade, "membrane")))
	var couverture: String = COVERINGS.get(cov_key, COVERINGS.get(str(CLADE_COVERINGS.get(clade, "membrane")), "sous une fine membrane"))
	var habitat_key := str(g.call("habitat", g.call("medium", CLADE_HABITATS.get(clade, "land"))))
	if not HABITATS.has(habitat_key):
		habitat_key = str(CLADE_HABITATS.get(clade, "land"))
	var loco_key := str(g.call("locomotion", CLADE_LOCOMOTIONS.get(clade, "crawl")))
	if not LOCOMOTIONS.has(loco_key):
		loco_key = str(CLADE_LOCOMOTIONS.get(clade, "crawl"))
	var tints := _tints(g.call("colors", g.call("color", null)), habitat_key)
	var mode := lifestyle(sp, epoch)
	var t_maj: String = taille.substr(0, 1).to_upper() + taille.substr(1)
	return {
		"taille": taille, "taille_maj": t_maj, "corps": corps, "couverture": couverture, "teintes": tints,
		"locomotion": LOCOMOTIONS[loco_key], "milieu": HABITATS[habitat_key], "mode": mode,
		"mode_bas": mode.substr(0, 1).to_lower() + mode.substr(1), "vie": _life_summary(sp, habitat_key),
	}


## Mode de vie (une phrase, accords en [espece:…]) : régime, climat, intelligence, sociabilité.
static func lifestyle(sp: Dictionary, epoch: int) -> String:
	var traits: Dictionary = sp.get("traits", {})
	var clade := str(traits.get("clade", sp.get("clade", "")))
	var diet := str(traits.get("diet", sp.get("diet", "")))
	if diet == "":
		# Germes animaux (contrat Planète) : role filter | grazer | hunter.
		diet = str({"filter": "filtreur", "grazer": "herbivore", "hunter": "carnivore"}.get(str(traits.get("role", "")), "omnivore"))
	var energy := str(traits.get("energy", sp.get("energy", "")))
	var parts := PackedStringArray()
	if energy == "chemo":
		parts.append("[espece:tire|tirent] [espece:son|leur] énergie de la chimie des sources chaudes, sans lumière")
	elif energy == "photo" or clade in ["algue", "plante"]:
		parts.append("[espece:se nourrit|se nourrissent] de lumière en rejetant de l'oxygène")
	elif clade == "microbe" and diet == "carnivore":
		parts.append("[espece:dévore|dévorent] d'autres cellules")
	elif diet == "herbivore":
		parts.append("[espece:broute|broutent] %s" % ("les plantes" if epoch >= Epoch.LAND and clade != "microbe" else "les tapis de microbes"))
	elif diet == "carnivore":
		parts.append("[espece:chasse|chassent] d'autres êtres vivants")
	else:
		parts.append("[espece:se nourrit|se nourrissent] de tout ce qui passe à [espece:sa|leur] portée")
	var t := float(traits.get("temp_opt", 0.5))
	if t < 0.3:
		parts.append("[espece:aime|aiment] le froid")
	elif t > 0.72:
		parts.append("[espece:recherche|recherchent] la chaleur")
	var social := str(traits.get("sociality", sp.get("sociality", "")))
	if social in ["herd", "troupeau", "group", "groupe"]:
		parts.append("[espece:vit|vivent] en groupe")
	elif social in ["colony", "colonie"]:
		parts.append("[espece:vit|vivent] en colonies serrées")
	elif social in ["solitary", "solitaire"]:
		parts.append("[espece:préfère|préfèrent] la solitude")
	if bool(sp.get("sapient", false)):
		parts.append("[espece:pense|pensent], et [espece:sait|savent] qu'[espece:elle pense|ils pensent]")
	elif float(traits.get("intelligence", 0.0)) >= 0.5:
		parts.append("[espece:se montre|se montrent] d'une curiosité étonnante")
	if float(traits.get("adaptability", 0.0)) >= 0.75:
		parts.append("[espece:s'accommode|s'accommodent] de presque tout")
	var s := ", ".join(parts.slice(0, parts.size() - 1)) + (" et " if parts.size() > 1 else "") + parts[-1] if parts.size() > 0 else ""
	return s.substr(0, 1).to_upper() + s.substr(1) + "."


static func _life_summary(sp: Dictionary, habitat_key: String) -> String:
	var traits: Dictionary = sp.get("traits", {})
	var diet := str(traits.get("diet", sp.get("diet", "omnivore")))
	var verb: String = {"herbivore": "à brouter", "carnivore": "à chasser"}.get(diet, "à chercher sa vie")
	return "%s %s" % [verb, HABITATS.get(habitat_key, "sur ce monde")]


func _tints(colors: Variant, habitat_key: String) -> String:
	var names := PackedStringArray()
	if colors is Array:
		for c in colors:
			names.append(_color_name(c))
	elif colors != null and str(colors) != "":
		names.append(_color_name(colors))
	names = PackedStringArray(Array(names).filter(func(n: String) -> bool: return n != ""))
	if names.is_empty():
		var pool: Array = DEFAULT_TINTS.get(habitat_key, DEFAULT_TINTS["land"])
		return str(pool[rng.randi() % pool.size()])
	if names.size() == 1:
		return names[0]
	return "%s et %s" % [names[0], names[1]]


static func _color_name(c: Variant) -> String:
	if c is Color:
		var col: Color = c
		if col.s < 0.15:
			return "pâles" if col.v > 0.6 else ("grises" if col.v > 0.25 else "noires")
		return str(COLOR_NAMES[int(floor(col.h * COLOR_NAMES.size())) % COLOR_NAMES.size()])
	var s := str(c).strip_edges().to_lower()
	var fr := {"red": "rouges", "orange": "orangées", "yellow": "jaunes", "green": "vertes", "blue": "bleues", "purple": "pourpres",
		"violet": "violettes", "brown": "brunes", "black": "noires", "white": "blanches", "grey": "grises", "gray": "grises",
		"gold": "dorées", "silver": "argentées", "rouge": "rouges", "vert": "vertes", "bleu": "bleues", "jaune": "jaunes",
		"brun": "brunes", "noir": "noires", "blanc": "blanches", "gris": "grises"}
	return str(fr.get(s, s))


## Le premier gabarit propre à l'époque et pas dit récemment (rotation), rendu avec ses accords.
func _pick(templates: Array, slots: Dictionary, plural: bool, epoch: int) -> String:
	var start := rng.randi() % templates.size()
	var fallback := ""
	for i in templates.size():
		var tpl := Procedural.apply_agreement(str(templates[(start + i) % templates.size()]), {"espece": plural})
		var s := slots.duplicate()
		for k in ["locomotion", "mode", "mode_bas", "cause"]:
			if s.has(k):
				s[k] = Procedural.apply_agreement(str(s[k]), {"espece": plural})
		var text := Procedural.polish(Procedural.contract(" " + tpl.format(s)).strip_edges())
		if not Epoch.is_clean(text, epoch):
			continue
		if fallback == "":
			fallback = text
		if variety == null or not variety.seen(text):
			return text
	return fallback
