extends RefCounted
## Catalogue des semences de la Genèse (docs/GENESE.md « Semer la vie ») et règles pures :
## construction et validation de l'action, indice « conditions réunies ? » lu dans les
## statistiques planétaires. Testé par tests/test_calm_ui.gd.
##
## Action envoyée à GameState.apply_divine_action :
##   {type: "seed", kind, traits: Dictionary, region: Vector2i, radius: int}
## traits selon kind :
##   spark, light, spore : {}
##   animal_germ : {role: "filter" | "grazer" | "hunter"}
##   shaped : {size 0..1, diet ∈ DIETS, habitat ∈ HABITATS, intelligence 0..1,
##             covering ∈ COVERINGS, color: Color}
## Les conditions ne sont qu'un indice : la simulation tranche (une semence peut échouer).

const KINDS := ["spark", "light", "spore", "animal_germ", "shaped"]
const ROLES := ["filter", "grazer", "hunter"]
const DIETS := ["herbivore", "omnivore", "carnivore"]
const HABITATS := ["marine", "amphibious", "land"]
const COVERINGS := ["skin", "scales", "shell", "feathers", "fur"]
const MIN_RADIUS := 1
const MAX_RADIUS := 32

const SEEDS := [
	{id = "spark", label = "Étincelle", key = KEY_1, radius = 4, cooldown = 6.0,
		color = Color(1.0, 0.55, 0.25),
		hint = "Microbes chimiosynthétiques autour des sources hydrothermales. Pas besoin de soleil."},
	{id = "light", label = "Lumière", key = KEY_2, radius = 6, cooldown = 6.0,
		color = Color(0.45, 0.95, 0.55),
		hint = "Cyanobactéries : elles captent la lumière et libèrent l'oxygène, qui change le ciel."},
	{id = "spore", label = "Spore", key = KEY_3, radius = 6, cooldown = 15.0,
		color = Color(0.75, 0.85, 0.35),
		hint = "Lichens et mousses qui colonisent les terres nues, une fois l'ozone en place."},
	{id = "animal_germ", label = "Germe d'animal", key = KEY_4, radius = 4, cooldown = 30.0,
		color = Color(0.95, 0.7, 0.4),
		hint = "Une lignée animale simple : filtreur, brouteur ou chasseur. Il lui faut de l'oxygène."},
	{id = "shaped", label = "Créature façonnée", key = KEY_5, radius = 3, cooldown = 120.0,
		color = Color(0.8, 0.6, 1.0),
		hint = "Réglez ses traits puis posez-la. Longue recharge."},
]

const ROLE_LABELS := {filter = "Filtreur", grazer = "Brouteur", hunter = "Chasseur"}
const DIET_LABELS := {herbivore = "Herbivore", omnivore = "Omnivore", carnivore = "Carnivore"}
const HABITAT_LABELS := {marine = "Mer", amphibious = "Rivage", land = "Terre"}
const COVERING_LABELS := {skin = "Peau nue", scales = "Écailles", shell = "Carapace",
	feathers = "Plumes", fur = "Fourrure"}

## Seuils indicatifs (statistiques planétaires, voir conditions()).
## oxygen : fraction du niveau actuel (1 = 21 % de l'atmosphère) ; ozone : 0..1 (1 = couche actuelle).
const REQUIREMENTS := {
	spark = {},
	light = {},
	spore = {ozone = 0.3},
	animal_germ = {oxygen = 0.1},
	shaped = {oxygen = 0.15, ozone = 0.3},
}


static func get_seed(kind: String) -> Dictionary:
	for s in SEEDS:
		if s.id == kind:
			return s
	return {}


## Traits par défaut d'une semence (à modifier dans l'éditeur pour « shaped »).
static func default_traits(kind: String) -> Dictionary:
	match kind:
		"animal_germ":
			return {role = "grazer"}
		"shaped":
			return {size = 0.3, diet = "herbivore", habitat = "land", intelligence = 0.2,
				covering = "scales", color = Color(0.55, 0.75, 0.45)}
	return {}


static func make_action(kind: String, traits: Dictionary, region: Vector2i, radius: int) -> Dictionary:
	return {type = "seed", kind = kind, traits = traits.duplicate(), region = region, radius = radius}


## "" si l'action de semence est valide, sinon la raison.
static func validate_action(a: Variant) -> String:
	if not a is Dictionary:
		return "l'action n'est pas un dictionnaire"
	var d: Dictionary = a
	if str(d.get("type", "")) != "seed":
		return "type différent de « seed »"
	var kind := str(d.get("kind", ""))
	if not kind in KINDS:
		return "semence inconnue : %s" % kind
	if not d.get("region") is Vector2i:
		return "région manquante"
	var r = d.get("radius")
	if not r is int or r < MIN_RADIUS or r > MAX_RADIUS:
		return "rayon hors bornes (%d à %d)" % [MIN_RADIUS, MAX_RADIUS]
	var traits = d.get("traits", {})
	if not traits is Dictionary:
		return "traits invalides"
	return validate_traits(kind, traits)


static func validate_traits(kind: String, t: Dictionary) -> String:
	match kind:
		"animal_germ":
			if not str(t.get("role", "")) in ROLES:
				return "rôle du germe : filtreur, brouteur ou chasseur"
		"shaped":
			for k in ["size", "intelligence"]:
				var v = t.get(k)
				if not (v is float or v is int) or float(v) < 0.0 or float(v) > 1.0:
					return "trait %s hors de 0..1" % k
			if not str(t.get("diet", "")) in DIETS:
				return "régime inconnu"
			if not str(t.get("habitat", "")) in HABITATS:
				return "milieu inconnu"
			if not str(t.get("covering", "")) in COVERINGS:
				return "couverture inconnue"
			if not t.get("color") is Color:
				return "couleur manquante"
	return ""


## Indice pour l'interface : {state: "ok" | "risky" | "unknown", text}.
## `stats` vient de planet_stats() (clés oxygen, ozone) ; une clé absente rend l'indice « unknown ».
static func conditions(kind: String, stats: Dictionary) -> Dictionary:
	var req: Dictionary = REQUIREMENTS.get(kind, {})
	if req.is_empty():
		return {state = "ok", text = "Conditions favorables partout où il y a de l'eau."}
	var missing: Array[String] = []
	var unknown := false
	for key in req:
		if not stats.has(key) or not (stats[key] is float or stats[key] is int):
			unknown = true
			continue
		if float(stats[key]) < float(req[key]):
			missing.append(key)
	if not missing.is_empty():
		var parts: Array[String] = []
		for k in missing:
			parts.append("trop peu d'oxygène" if k == "oxygen" else "couche d'ozone trop mince")
		return {state = "risky", text = "Conditions difficiles : %s. La vie pourrait ne pas prendre." % ", ".join(parts)}
	if unknown:
		return {state = "unknown", text = "Conditions inconnues : la planète ne renseigne pas encore ces mesures."}
	return {state = "ok", text = "Les conditions semblent réunies."}
