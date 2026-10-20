extends RefCounted
## Apparences procédurales infinies : n'importe quel dictionnaire de traits d'espèce devient une
## silhouette paramétrique (dessinée en SDF par shaders/parcel_creature.gdshader), des couleurs, un
## motif et une façon de bouger.
##
## Règles :
## - Déterministe : mêmes traits => même apparence (species_id ne sert qu'à départager deux espèces
##   aux traits strictement identiques, par une nuance infime).
## - Continu : des traits proches donnent des formes proches (espèces sœurs), des lignées lointaines
##   diffèrent. Rien ne dépend d'un hachage aléatoire de l'identifiant.
## - Tolérant : tout trait absent prend une valeur sensée, d'abord d'après la lignée (`clade`) si elle
##   est connue, sinon d'après la complexité, le milieu, le régime et la taille.
##
## Traits lus (tous optionnels ; noms anglais ou français) :
##   size, diet, habitat ("marine" | "amphibious" | "land"), clade, complexity (0..6),
##   temp_opt, adaptability, aggression, intelligence, oxygenic, anaerobic,
##   body_plan / plan_corporel : colony, frond, vase, bell, radial, worm, segmented, shell,
##     fusiform, quadruped, biped, flyer, blob
##   symmetry / symetrie : radial | bilateral | none
##   limbs / membres : nombre de membres (pattes, nageoires paires, tentacules, frondes)
##   locomotion : swim | walk | fly | crawl | sessile (ou nage, marche, vol, rampe, fixe)
##   covering / couverture : skin, scales, feathers, fur, shell, gel (peau, écailles, plumes, poils,
##     carapace, gelée)
##   color / couleur : Color, [r, g, b], "#rrggbb" ou teinte 0..1 ; pattern / motif : none, stripes,
##     spots, bands, mottled (rayures, taches, bandes, marbré)
##   eyes / yeux, horns / cornes, fins / nageoires, wings / ailes, tail / queue, segments,
##   neck / cou, sail / voile, elongation, pigment (producteurs)

enum Loco { WALK, SWIM, SESSILE, CRAWL, FLY } ## mêmes valeurs que ParcelLogic.Locomotion
enum Cover { SKIN, SCALES, FEATHERS, FUR, SHELL, GEL }
enum Pattern { NONE, STRIPES, SPOTS, BANDS, MOTTLED }
enum Limb { LEG, FIN, WING }

const PLANS := ["blob", "colony", "frond", "vase", "bell", "radial", "worm", "segmented", "shell",
	"fusiform", "quadruped", "biped", "flyer"]

const SYNONYMS := {
	# locomotion
	"nage": "swim", "nager": "swim", "marche": "walk", "marcher": "walk", "vol": "fly", "voler": "fly",
	"rampe": "crawl", "ramper": "crawl", "fixe": "sessile", "fixed": "sessile",
	# couverture
	"peau": "skin", "nue": "skin", "peau_nue": "skin", "ecailles": "scales", "plumes": "feathers",
	"poils": "fur", "fourrure": "fur", "carapace": "shell", "coquille": "shell", "gelee": "gel",
	# motif
	"rayures": "stripes", "taches": "spots", "bandes": "bands", "marbre": "mottled", "aucun": "none",
	# symétrie
	"radiale": "radial", "bilaterale": "bilateral", "aucune": "none",
	# plans
	"colonie": "colony", "fronde": "frond", "cloche": "bell", "ver": "worm", "segmente": "segmented",
	"coquillage": "shell", "fuselé": "fusiform", "fusele": "fusiform", "quadrupede": "quadruped",
	"bipede": "biped", "volant": "flyer",
}

## Traits implicites par lignée connue (seulement pour les traits absents).
const ARCHETYPES := {
	"microbe": {body_plan = "colony", locomotion = "sessile", covering = "gel", limbs = 0},
	"bacterie": {body_plan = "colony", locomotion = "sessile", covering = "gel", limbs = 0},
	"algue": {body_plan = "frond", locomotion = "sessile", limbs = 6},
	"plante": {body_plan = "frond", locomotion = "sessile", limbs = 8},
	"eponge": {body_plan = "vase", locomotion = "sessile", pattern = "spots", limbs = 0},
	"cnidaire": {body_plan = "bell", locomotion = "swim", covering = "gel", limbs = 8},
	"meduse": {body_plan = "bell", locomotion = "swim", covering = "gel", limbs = 8},
	"arthropode": {body_plan = "segmented", locomotion = "crawl", covering = "shell", limbs = 8, segments = 7, horns = 0.5},
	"insecte": {body_plan = "segmented", locomotion = "fly", covering = "shell", limbs = 6, segments = 3, wings = 1.0, horns = 0.4},
	"mollusque": {body_plan = "shell", locomotion = "crawl", covering = "shell", limbs = 0},
	"poisson": {body_plan = "fusiform", locomotion = "swim", covering = "scales", fins = 1.0, limbs = 2},
	"amphibien": {body_plan = "quadruped", locomotion = "walk", covering = "skin", limbs = 4, tail = 0.5, pattern = "spots"},
	"reptile": {body_plan = "quadruped", locomotion = "walk", covering = "scales", limbs = 4, tail = 0.8},
	"synapside": {body_plan = "quadruped", locomotion = "walk", covering = "scales", limbs = 4, tail = 0.6, sail = 1.0},
	"dinosaure": {body_plan = "quadruped", locomotion = "walk", covering = "scales", limbs = 4, tail = 0.9},
	"pterosaure": {body_plan = "flyer", locomotion = "fly", covering = "fur", limbs = 4, wings = 1.0, tail = 0.2},
	"oiseau": {body_plan = "flyer", locomotion = "walk", covering = "feathers", limbs = 4, wings = 0.6, tail = 0.3},
	"mammifere": {body_plan = "quadruped", locomotion = "walk", covering = "fur", limbs = 4, tail = 0.5},
	"primate": {body_plan = "quadruped", locomotion = "walk", covering = "fur", limbs = 4, tail = 0.4},
	"chimere": {body_plan = "quadruped", locomotion = "walk", covering = "skin", limbs = 6, horns = 0.6, pattern = "mottled"},
}

## Proportions de base par plan corporel : demi-longueur, demi-largeur, tête, queue, membres.
const PLAN_SHAPES := {
	"blob": [0.45, 0.32, 0.16, 0.1, 0.25],
	"colony": [0.2, 0.2, 0.0, 0.0, 0.0],
	"frond": [0.1, 0.1, 0.0, 0.0, 0.0],
	"vase": [0.42, 0.42, 0.0, 0.0, 0.0],
	"bell": [0.36, 0.38, 0.0, 0.0, 0.0],
	"radial": [0.18, 0.18, 0.0, 0.0, 0.0],
	"worm": [0.82, 0.09, 0.08, 0.0, 0.12],
	"segmented": [0.55, 0.26, 0.11, 0.05, 0.3],
	"shell": [0.42, 0.38, 0.12, 0.0, 0.0],
	"fusiform": [0.48, 0.16, 0.0, 0.32, 0.22],
	"quadruped": [0.38, 0.19, 0.14, 0.4, 0.3],
	"biped": [0.33, 0.17, 0.15, 0.48, 0.3],
	"flyer": [0.28, 0.12, 0.1, 0.15, 0.62],
}


# --- Lecture tolérante des traits ---

static func _slug(text: String) -> String:
	const ACCENTS := {"à": "a", "â": "a", "é": "e", "è": "e", "ê": "e", "ë": "e", "î": "i", "ï": "i",
		"ô": "o", "ù": "u", "û": "u", "ü": "u", "ç": "c", "æ": "ae", "œ": "oe"}
	var out := ""
	for ch in text.strip_edges().to_lower():
		var c: String = ACCENTS.get(ch, ch)
		out += "_" if c == " " or c == "-" else c
	return out


static func _word(v) -> String:
	var s := _slug(str(v))
	return SYNONYMS.get(s, s)


static func _pick(traits: Dictionary, keys: Array, fallback):
	for k in keys:
		if traits.has(k) and traits[k] != null:
			return traits[k]
	return fallback


static func _num(traits: Dictionary, keys: Array, fallback: float) -> float:
	var v = _pick(traits, keys, fallback)
	if typeof(v) == TYPE_BOOL:
		return 1.0 if v else 0.0
	if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
		return float(v)
	if typeof(v) == TYPE_STRING and String(v).is_valid_float():
		return float(v)
	return fallback


## Traits complets : ceux fournis, complétés par l'archétype de la lignée puis par déduction.
## `row` : entrée de parcel.fauna (role, habitat, size, clade, diet), utilisée si les traits manquent.
static func complete(traits: Dictionary, row := {}) -> Dictionary:
	var t := {}
	for k in row:
		t[k] = row[k]
	for k in traits:
		t[k] = traits[k]
	var clade := _slug(str(t.get("clade", "")) if t.get("clade") != null else "")
	var arch: Dictionary = ARCHETYPES.get(clade, {})
	var diet := _word(t.get("diet", "omnivore"))
	var habitat := _word(t.get("habitat", "land"))
	var producer := diet == "autotrophe" or str(t.get("role", "")) == "producer"
	var complexity := _num(t, ["complexity", "complexite"], 3.0 if not producer else 1.0)
	var out := {
		clade = clade, diet = diet, habitat = habitat, producer = producer, complexity = complexity,
		size = clampf(_num(t, ["size", "taille"], 0.3), 0.0, 1.0),
		temp_opt = clampf(_num(t, ["temp_opt"], 0.6), 0.0, 1.0),
		adaptability = clampf(_num(t, ["adaptability"], 0.5), 0.0, 1.0),
		aggression = clampf(_num(t, ["aggression"], 0.4), 0.0, 1.0),
		intelligence = clampf(_num(t, ["intelligence"], 0.2), 0.0, 1.0),
		oxygenic = _num(t, ["oxygenic"], 1.0 if producer and complexity >= 1.0 else 0.0) > 0.5,
		anaerobic = _num(t, ["anaerobic"], 0.0) > 0.5,
		sapient = str(t.get("role", "")) == "sapient",
	}
	# Plan corporel et déplacement : trait explicite, sinon archétype, sinon déduction.
	var plan := _word(_pick(t, ["body_plan", "plan_corporel", "plan"], arch.get("body_plan", "")))
	if not plan in PLANS:
		plan = _infer_plan(producer, complexity, habitat, diet, out["size"])
	if out.sapient and plan in ["quadruped", "blob"]:
		plan = "biped"
	if clade == "dinosaure" and diet != "herbivore" and plan == "quadruped":
		plan = "biped"
	out.body_plan = plan
	var loco := _word(_pick(t, ["locomotion"], arch.get("locomotion", "")))
	if not loco in ["swim", "walk", "fly", "crawl", "sessile"]:
		loco = _infer_loco(plan, habitat)
	out.locomotion = loco
	out.symmetry = _word(_pick(t, ["symmetry", "symetrie"], "radial" if plan in ["frond", "vase", "bell", "radial", "colony"] else "bilateral"))
	out.covering = _word(_pick(t, ["covering", "couverture"], arch.get("covering", _infer_cover(plan, habitat, complexity))))
	out.pattern = _word(_pick(t, ["pattern", "motif"], arch.get("pattern", _infer_pattern(diet, out.aggression, out["size"]))))
	var default_limbs: int = {"quadruped": 4, "biped": 4, "flyer": 4, "segmented": 6, "fusiform": 2,
		"bell": 8, "frond": 7, "radial": 5, "worm": 0}.get(plan, 0)
	out.limbs = int(clampf(_num(t, ["limbs", "membres", "legs", "pattes"], arch.get("limbs", default_limbs)), 0, 12))
	out.eyes = int(clampf(_num(t, ["eyes", "yeux"], 0.0 if producer or plan in ["colony", "frond", "vase"] else 2.0), 0, 8))
	out.horns = clampf(_num(t, ["horns", "cornes"], arch.get("horns", 0.6 if diet == "herbivore" and out.aggression > 0.45 and out["size"] > 0.5 else 0.0)), 0.0, 1.0)
	out.fins = clampf(_num(t, ["fins", "nageoires"], arch.get("fins", 1.0 if loco == "swim" and plan == "fusiform" else 0.0)), 0.0, 1.0)
	out.wings = clampf(_num(t, ["wings", "ailes"], arch.get("wings", 1.0 if loco == "fly" else 0.0)), 0.0, 1.0)
	out.tail = clampf(_num(t, ["tail", "queue"], arch.get("tail", PLAN_SHAPES.get(plan, PLAN_SHAPES.blob)[3] / 0.48)), 0.0, 1.0)
	out.segments = clampf(_num(t, ["segments"], arch.get("segments", 9.0 if plan == "worm" else 0.0)), 0.0, 12.0)
	out.neck = clampf(_num(t, ["neck", "cou"], 0.8 if clade == "dinosaure" and diet == "herbivore" and out["size"] >= 0.9 else 0.0), 0.0, 1.0)
	out.sail = clampf(_num(t, ["sail", "voile"], arch.get("sail", 0.0)), 0.0, 1.0)
	out.elongation = clampf(_num(t, ["elongation"], 0.5), 0.0, 1.0)
	out.color = _pick(t, ["color", "couleur"], null)
	out.pigment = _pick(t, ["pigment"], null)
	return out


static func _infer_plan(producer: bool, complexity: float, habitat: String, diet: String, size: float) -> String:
	if complexity < 1.0:
		return "colony"
	if producer:
		return "frond"
	if complexity < 3.0:
		return "vase" if habitat == "marine" else "blob"
	if habitat == "marine":
		return "fusiform" if complexity >= 4.0 else ("segmented" if diet == "carnivore" else "shell")
	if complexity < 4.0:
		return "segmented"
	return "quadruped"


static func _infer_loco(plan: String, habitat: String) -> String:
	match plan:
		"colony", "frond", "vase":
			return "sessile"
		"bell", "fusiform":
			return "swim"
		"worm", "segmented", "shell", "radial":
			return "crawl"
		"flyer":
			return "fly"
	return "swim" if habitat == "marine" else "walk"


static func _infer_cover(plan: String, habitat: String, complexity: float) -> String:
	if plan in ["colony", "bell"]:
		return "gel"
	if plan in ["segmented", "shell"]:
		return "shell"
	if plan == "fusiform":
		return "scales"
	if plan == "flyer":
		return "feathers"
	if complexity >= 6.0:
		return "scales" if habitat != "land" else "fur"
	return "skin"


static func _infer_pattern(diet: String, aggression: float, size: float) -> String:
	if diet == "carnivore" and aggression > 0.6:
		return "stripes"
	if diet == "herbivore" and size < 0.4:
		return "spots"
	if size > 0.7:
		return "bands"
	return "none"


# --- Apparence ---

## Apparence complète d'une espèce. Les nombres sont prêts pour le shader (voir to_material()).
static func generate(traits: Dictionary, row := {}, species_id := -1) -> Dictionary:
	var t := complete(traits, row)
	var plan: String = t.body_plan
	var base: Array = PLAN_SHAPES.get(plan, PLAN_SHAPES.blob)
	var size: float = t["size"]
	# Proportions : plan corporel, puis petites variations continues selon les traits.
	var half_len: float = base[0] * lerpf(0.85, 1.15, t.elongation)
	var half_wid: float = base[1] * lerpf(1.15, 0.85, t.elongation) * (0.9 + 0.25 * size)
	var head: float = base[2] * (0.85 + 0.5 * t.intelligence) * (1.0 if plan != "worm" else 1.2)
	var tail: float = 0.48 * t.tail * (0.85 + 0.3 * t.aggression)
	var limb_len: float = base[4] * (0.75 + 0.5 * (1.0 - size)) * (1.0 + 0.25 * t.adaptability)
	var limb_kind := Limb.LEG
	var limb_pairs := int(ceil(t.limbs / 2.0))
	if t.locomotion == "swim" or plan == "fusiform":
		limb_kind = Limb.FIN
	if t.wings > 0.3:
		limb_kind = Limb.WING
	var arms := 0
	var arm_len := 0.0
	var arm_trail := 0.0
	var colony := 0
	if t.symmetry == "radial" or plan in ["frond", "bell", "radial"]:
		arms = clampi(t.limbs, 0 if plan == "vase" else 3, 10)
		arm_len = {"frond": 0.8, "bell": 0.85, "radial": 0.6}.get(plan, 0.4) * (0.8 + 0.3 * size)
		arm_trail = 1.0 if plan == "bell" else 0.0
		limb_pairs = 0
	if plan == "colony":
		colony = clampi(4 + roundi(t.adaptability * 4.0), 3, 8)
		limb_pairs = 0
	if plan == "vase":
		limb_pairs = 0
	var biped: bool = plan == "biped" or bool(t.sapient)
	var app := {
		body_plan = plan, locomotion = _loco_index(t.locomotion), habitat = t.habitat,
		producer = t.producer, size = size,
		half_len = half_len, half_wid = half_wid, head = head, neck = t.neck * 0.4,
		tail = tail, fin = t.fins * (0.18 + 0.1 * size), segments = t.segments, sail = t.sail,
		limb_pairs = clampi(limb_pairs, 0, 6), limb_len = limb_len, limb_kind = limb_kind,
		biped = biped, arms = arms, arm_len = arm_len, arm_trail = arm_trail, colony = colony,
		horns = t.horns, shell = 1.0 if plan == "shell" else 0.0, eyes = t.eyes,
		bell = 1.0 if plan == "bell" else 0.0, ring = 1.0 if plan == "vase" else 0.0,
		covering = _cover_index(t.covering), pattern = _pattern_index(t.pattern),
		pattern_scale = lerpf(3.0, 9.0, 1.0 - size),
		translucency = 0.45 if t.covering == "gel" else 0.0,
	}
	var colors := _colors(t, species_id)
	app.color = colors[0]
	app.color2 = colors[1]
	return app


static func _loco_index(s: String) -> int:
	return {"walk": Loco.WALK, "swim": Loco.SWIM, "sessile": Loco.SESSILE, "crawl": Loco.CRAWL, "fly": Loco.FLY}.get(s, Loco.WALK)


static func _cover_index(s: String) -> int:
	return {"skin": Cover.SKIN, "scales": Cover.SCALES, "feathers": Cover.FEATHERS, "fur": Cover.FUR,
		"shell": Cover.SHELL, "gel": Cover.GEL}.get(s, Cover.SKIN)


static func _pattern_index(s: String) -> int:
	return {"none": Pattern.NONE, "stripes": Pattern.STRIPES, "spots": Pattern.SPOTS, "bands": Pattern.BANDS,
		"mottled": Pattern.MOTTLED}.get(s, Pattern.NONE)


## Couleur principale et couleur du motif. Explicite si fournie ; sinon dérivée des traits :
## milieu et climat pour la teinte, régime et taille pour la saturation et la valeur ; les
## producteurs prennent la couleur de leur pigment (vert chlorophylle, pourpre des anaérobies…).
static func _colors(t: Dictionary, species_id: int) -> Array:
	var c := Color()
	var given = t.color
	if given is Color:
		c = given
	elif given is Array and given.size() >= 3:
		c = Color(float(given[0]), float(given[1]), float(given[2]))
	elif given is String and Color.html_is_valid(given):
		c = Color.html(given)
	elif typeof(given) in [TYPE_FLOAT, TYPE_INT]:
		c = Color.from_hsv(fposmod(float(given), 1.0), 0.55, 0.75)
	else:
		var hue := 0.0
		var sat := 0.0
		var val := 0.0
		if t.producer:
			var pig = t.pigment
			if pig is String:
				hue = {"chlorophylle": 0.3, "chlorophyll": 0.3, "rouge": 0.97, "red": 0.97, "pourpre": 0.82,
					"purple": 0.82, "brun": 0.08, "brown": 0.08, "orange": 0.07, "bleu": 0.55, "blue": 0.55}.get(_slug(pig), 0.3)
			elif t.anaerobic:
				hue = 0.84 + 0.1 * t.temp_opt
			elif t.oxygenic:
				hue = 0.27 + 0.12 * (1.0 - t.temp_opt)
			else:
				hue = 0.5
			sat = 0.45 + 0.3 * t.adaptability
			val = 0.5 + 0.2 * (1.0 - t["size"])
		else:
			# Mer : bleus-verts ; terre : bruns-ocres ; amphibie : verts. Le chaud tire vers le rouge.
			var by_habitat := {"marine": 0.52, "amphibious": 0.3, "land": 0.09}
			hue = float(by_habitat.get(t.habitat, 0.09)) - 0.14 * (t.temp_opt - 0.5)
			hue += {"carnivore": -0.05, "herbivore": 0.05}.get(t.diet, 0.0)
			hue += 0.04 * (t.complexity - 3.0) / 3.0
			sat = 0.3 + 0.45 * t.aggression * (1.0 - 0.4 * t["size"]) + 0.15 * t.adaptability
			val = 0.82 - 0.3 * t["size"] + 0.08 * t.intelligence
		# Deux espèces aux traits identiques ne sont pas confondues : nuance minime par identifiant.
		if species_id >= 0:
			hue += (float(posmod(species_id * 7919, 1000)) / 1000.0 - 0.5) * 0.012
		c = Color.from_hsv(fposmod(hue, 1.0), clampf(sat, 0.05, 1.0), clampf(val, 0.15, 1.0))
	var c2 := Color.from_hsv(fposmod(c.h + 0.06, 1.0), clampf(c.s + 0.15, 0.0, 1.0), clampf(c.v * 0.55, 0.0, 1.0))
	if t.pattern == "spots" or t.pattern == "mottled":
		c2 = Color.from_hsv(fposmod(c.h - 0.04, 1.0), clampf(c.s * 0.6, 0.0, 1.0), clampf(c.v * 1.25, 0.0, 1.0))
	return [c, c2]


# --- Comparaison (tests, arbre de la vie) ---

## Vecteur de forme normalisé ; la distance euclidienne entre deux vecteurs mesure la ressemblance.
static func shape_vector(app: Dictionary) -> PackedFloat32Array:
	var v := PackedFloat32Array([
		app.half_len, app.half_wid * 2.0, app.head * 2.0, app.neck, app.tail, app.fin * 2.0,
		app.segments / 12.0, app.sail * 0.5, app.limb_pairs / 6.0, app.limb_len, app.arms / 10.0,
		app.arm_len * 0.5, app.arm_trail * 0.5, app.colony / 8.0, app.horns * 0.5, app.shell * 0.5,
		app.bell * 0.5, app.ring * 0.5, app.eyes / 8.0, app.translucency,
		app["size"] * 0.5,
	])
	for k in 5: # déplacement
		v.append(0.35 if app.locomotion == k else 0.0)
	for k in 3: # type de membre
		v.append(0.25 if app.limb_kind == k and app.limb_pairs > 0 else 0.0)
	for k in 6: # couverture
		v.append(0.2 if app.covering == k else 0.0)
	var c: Color = app.color
	v.append(cos(c.h * TAU) * c.s * 0.4)
	v.append(sin(c.h * TAU) * c.s * 0.4)
	v.append(c.v * 0.3)
	return v


static func distance(a: Dictionary, b: Dictionary) -> float:
	var va := shape_vector(a)
	var vb := shape_vector(b)
	var s := 0.0
	for i in va.size():
		s += (va[i] - vb[i]) ** 2
	return sqrt(s)


# --- Rendu ---

## Règle les paramètres de forme d'un ShaderMaterial de shaders/parcel_creature.gdshader.
static func to_material(mat: ShaderMaterial, app: Dictionary) -> void:
	mat.set_shader_parameter("locomotion", int(app.locomotion))
	mat.set_shader_parameter("body", Vector4(app.half_len, app.half_wid, app.head, app.neck))
	mat.set_shader_parameter("tailp", Vector4(app.tail, app.fin, app.segments, app.sail))
	mat.set_shader_parameter("limbs", Vector4(app.limb_pairs, app.limb_len, app.limb_kind, 1.0 if app.biped else 0.0))
	mat.set_shader_parameter("radial", Vector4(app.arms, app.arm_len, app.arm_trail, app.colony))
	mat.set_shader_parameter("extras", Vector4(app.horns, app.shell, app.eyes, app.bell))
	mat.set_shader_parameter("look", Vector4(app.covering, app.pattern, app.pattern_scale, app.translucency))
	mat.set_shader_parameter("ring", app.ring)
	var c2: Color = app.color2
	mat.set_shader_parameter("color2", Vector4(c2.r, c2.g, c2.b, 1.0))


## Taille du carré affiché, relative à la longueur de la créature : les longues queues, les ailes
## et les tentacules débordent du corps.
static func quad_scale(app: Dictionary) -> float:
	var reach := maxf(app.half_len + app.tail + app.head + app.neck, app.arm_len + app.half_wid)
	reach = maxf(reach, app.half_wid + app.limb_len * (1.6 if app.limb_kind == Limb.WING else 1.0))
	return clampf(reach * 1.25, 1.0, 2.2)
