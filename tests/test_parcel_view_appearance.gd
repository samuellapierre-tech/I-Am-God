extends RefCounted
## Tests du générateur d'apparences procédurales (src/parcel/appearance.gd).
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const Appearance := preload("res://src/parcel/appearance.gd")
const CREATURE_SHADER := preload("res://shaders/parcel_creature.gdshader")

const PLANS := ["blob", "worm", "segmented", "shell", "fusiform", "quadruped", "biped", "flyer", "bell", "radial", "frond", "vase", "colony"]
const LOCOS := ["swim", "walk", "fly", "crawl", "sessile"]
const COVERS := ["skin", "scales", "feathers", "fur", "shell", "gel"]
const PATTERNS := ["none", "stripes", "spots", "bands", "mottled"]
const HABITATS := ["marine", "amphibious", "land"]
const DIETS := ["herbivore", "omnivore", "carnivore"]
const NUMERIC := ["size", "temp_opt", "aggression", "adaptability", "intelligence", "horns", "fins", "wings", "tail", "elongation"]
const CATEGORICAL := ["body_plan", "locomotion", "covering", "pattern", "habitat", "diet"]


func _random_traits(rng: RandomNumberGenerator) -> Dictionary:
	var t := {}
	for k in NUMERIC:
		t[k] = rng.randf()
	t.body_plan = PLANS[rng.randi() % PLANS.size()]
	t.locomotion = LOCOS[rng.randi() % LOCOS.size()]
	t.covering = COVERS[rng.randi() % COVERS.size()]
	t.pattern = PATTERNS[rng.randi() % PATTERNS.size()]
	t.habitat = HABITATS[rng.randi() % HABITATS.size()]
	t.diet = DIETS[rng.randi() % DIETS.size()]
	t.limbs = rng.randi_range(0, 8)
	t.eyes = rng.randi_range(0, 6)
	t.complexity = 4.0
	return t


## Mutation d'ampleur m (0 : identique, 1 : lignée lointaine).
func _mutate(t: Dictionary, m: float, rng: RandomNumberGenerator) -> Dictionary:
	var out := t.duplicate()
	for k in NUMERIC:
		out[k] = clampf(float(t[k]) + rng.randf_range(-m, m) * 0.6, 0.0, 1.0)
	var lists := {body_plan = PLANS, locomotion = LOCOS, covering = COVERS, pattern = PATTERNS,
		habitat = HABITATS, diet = DIETS}
	for k in CATEGORICAL:
		if rng.randf() < m * 0.7:
			var l: Array = lists[k]
			out[k] = l[rng.randi() % l.size()]
	if rng.randf() < m:
		out.limbs = clampi(int(t.limbs) + rng.randi_range(-4, 4), 0, 8)
	if rng.randf() < m:
		out.eyes = clampi(int(t.eyes) + rng.randi_range(-3, 3), 0, 6)
	return out


func _trait_distance(a: Dictionary, b: Dictionary) -> float:
	var d := 0.0
	for k in NUMERIC:
		d += absf(float(a[k]) - float(b[k]))
	for k in CATEGORICAL:
		d += 0.0 if a[k] == b[k] else 1.0
	d += absf(int(a.limbs) - int(b.limbs)) / 4.0 + absf(int(a.eyes) - int(b.eyes)) / 3.0
	return d


func test_deterministic() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	for i in 30:
		var t := _random_traits(rng)
		var a := Appearance.generate(t, {}, 42)
		var b := Appearance.generate(t.duplicate(true), {}, 42)
		if Appearance.shape_vector(a) != Appearance.shape_vector(b) or a.color != b.color:
			return "apparence non déterministe pour %s" % str(t)
	return ""


func test_missing_or_odd_traits() -> String:
	var cases := [
		{}, {size = "0.4"}, {size = null, clade = null}, {clade = "zorglub"}, {limbs = -5, eyes = 99},
		{body_plan = "inconnu", locomotion = "téléportation", covering = 3, pattern = []},
		{color = [1, 0, 0]}, {color = "#33cc55"}, {color = 0.6}, {color = "pas une couleur"},
		{diet = "autotrophe"}, {complexity = 0}, {habitat = "marine", complexity = 5},
		{plan_corporel = "méduse", symetrie = "radiale", membres = 6, couverture = "gelée"},
	]
	for t in cases:
		var app := Appearance.generate(t)
		var v := Appearance.shape_vector(app)
		for x in v:
			if is_nan(x) or is_inf(x):
				return "valeur non finie pour %s" % str(t)
		if Appearance.quad_scale(app) < 1.0:
			return "carré trop petit pour %s" % str(t)
	return ""


## Des traits proches donnent des formes proches ; la distance de forme suit la distance de traits.
func test_similar_traits_similar_shapes() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var sister := 0.0
	var distant := 0.0
	for i in 160:
		var base := _random_traits(rng)
		var m := rng.randf()
		var other := _mutate(base, m, rng)
		xs.append(_trait_distance(base, other))
		ys.append(Appearance.distance(Appearance.generate(base, {}, 1), Appearance.generate(other, {}, 2)))
		var sib := _mutate(base, 0.04, rng)
		sister += Appearance.distance(Appearance.generate(base, {}, 1), Appearance.generate(sib, {}, 3))
		distant += Appearance.distance(Appearance.generate(base, {}, 1), Appearance.generate(_random_traits(rng), {}, 4))
	var r := _pearson(xs, ys)
	if r < 0.5:
		return "corrélation trop faible entre distances de traits et de formes : %.2f" % r
	if sister * 4.0 > distant:
		return "espèces sœurs pas assez semblables (%.2f) face aux lignées lointaines (%.2f)" % [sister / 160.0, distant / 160.0]
	print("corrélation traits/forme r = %.2f ; sœurs %.3f, lointaines %.3f" % [r, sister / 160.0, distant / 160.0])
	return ""


func _pearson(xs: PackedFloat32Array, ys: PackedFloat32Array) -> float:
	var n := float(xs.size())
	var mx := 0.0
	var my := 0.0
	for i in xs.size():
		mx += xs[i]
		my += ys[i]
	mx /= n
	my /= n
	var sxy := 0.0
	var sxx := 0.0
	var syy := 0.0
	for i in xs.size():
		sxy += (xs[i] - mx) * (ys[i] - my)
		sxx += (xs[i] - mx) ** 2
		syy += (ys[i] - my) ** 2
	return sxy / sqrt(maxf(sxx * syy, 1e-9))


## Valeurs par défaut sensées pour les lignées actuelles quand le génome est réduit.
func test_current_lineages() -> String:
	var L: Dictionary = Appearance.Loco
	var cases := [
		[{clade = "poisson", habitat = "marine"}, "fusiform", L.SWIM],
		[{clade = "microbe", diet = "autotrophe", complexity = 0}, "colony", L.SESSILE],
		[{clade = "plante", diet = "autotrophe", habitat = "land"}, "frond", L.SESSILE],
		[{clade = "dinosaure", diet = "carnivore", size = 0.9}, "biped", L.WALK],
		[{clade = "dinosaure", diet = "herbivore", size = 0.8}, "quadruped", L.WALK],
		[{clade = "ptérosaure"}, "flyer", L.FLY],
		[{clade = "méduse"}, "bell", L.SWIM],
		[{clade = "arthropode"}, "segmented", L.CRAWL],
		[{clade = "inconnu", habitat = "marine", complexity = 4}, "fusiform", L.SWIM],
		[{clade = "inconnu", habitat = "land", complexity = 6}, "quadruped", L.WALK],
	]
	for c in cases:
		var app := Appearance.generate(c[0])
		if app.body_plan != c[1] or app.locomotion != c[2]:
			return "%s : plan %s / déplacement %d, attendu %s / %d" % [str(c[0]), app.body_plan, app.locomotion, c[1], c[2]]
	var titan := Appearance.generate({clade = "dinosaure", diet = "herbivore", size = 1.0})
	if titan.neck <= 0.0:
		return "un titanosaure a un long cou"
	var green := Appearance.generate({clade = "algue", diet = "autotrophe", oxygenic = true}).color as Color
	if green.g < green.r or green.g < green.b:
		return "une algue oxygénique est verte : %s" % str(green)
	var purple := Appearance.generate({clade = "microbe", diet = "autotrophe", anaerobic = true, complexity = 0}).color as Color
	if purple.g > purple.r:
		return "un microbe anaérobie est pourpre : %s" % str(purple)
	return ""


func test_lineages_look_different() -> String:
	var kinds := [{clade = "poisson"}, {clade = "méduse"}, {clade = "arthropode"}, {clade = "mammifère"},
		{clade = "oiseau"}, {clade = "microbe", complexity = 0, diet = "autotrophe"}, {clade = "plante", diet = "autotrophe"}]
	for i in kinds.size():
		for j in range(i + 1, kinds.size()):
			var d := Appearance.distance(Appearance.generate(kinds[i]), Appearance.generate(kinds[j]))
			if d < 0.35:
				return "%s et %s se ressemblent trop (%.2f)" % [kinds[i].clade, kinds[j].clade, d]
	return ""


func test_material_parameters() -> String:
	var mat := ShaderMaterial.new()
	mat.shader = CREATURE_SHADER
	var app := Appearance.generate({body_plan = "quadruped", limbs = 6, horns = 0.8, eyes = 4, pattern = "stripes"})
	Appearance.to_material(mat, app)
	var limbs: Vector4 = mat.get_shader_parameter("limbs")
	var extras: Vector4 = mat.get_shader_parameter("extras")
	if int(limbs.x) != 3 or extras.z != 4.0 or extras.x < 0.79:
		return "paramètres de forme mal transmis : %s %s" % [str(limbs), str(extras)]
	return ""
