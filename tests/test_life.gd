extends RefCounted
## Espèces infinies : génome étendu, contraintes physiques, semences du joueur, noms et
## descriptions procéduraux (src/life/, src/sim/species.gd).
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const Species := preload("res://src/sim/species.gd")
const Genome := preload("res://src/life/genome.gd")
const Naming := preload("res://src/life/naming.gd")
const Phylogeny := preload("res://src/life/phylogeny.gd")

const GERM_ENVS := [{role = "filtreur"}, {role = "brouteur"}, {role = "chasseur"}]
## Créatures façonnées : traits partiels variés, parfois absurdes (le génome doit les rendre cohérents).
const SHAPES := [
	{size = 0.4, locomotion = "vol", diet = "carnivore"},
	{size = 0.9, milieu = "terre", diet = "herbivore", weapons = ["cornes"]},
	{milieu = "abysses", biolum = true, diet = "carnivore", size = 0.3},
	{diet = "autotrophe", covering = "écorce", size = 0.8},
	{covering = "poils", intelligence = 0.6, diet = "omnivore", size = 0.3},
	{locomotion = "nage", size = 0.7, diet = "carnivore", senses = ["électroréception"]},
	{locomotion = "vol", size = 0.05, covering = "carapace"},
	{size = 0.95, skeleton = "aucun", milieu = "terre"},
	{locomotion = "marche", body_plan = "radial", milieu = "air"},
	{locomotion = "téléportation", covering = "cristal", diet = "lumière", size = 5.0},
	{milieu = "eau douce", locomotion = "saut", pattern = "ocellé"},
	{body_plan = "colonial", metabolism = "photosynthèse", milieu = "mer peu profonde"},
	{},
]


func _rng(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


## Toutes les semences possibles (spark, light, spore, germes, créatures façonnées).
func _seeds(rng: RandomNumberGenerator) -> Array:
	var out := []
	for kind in ["spark", "light", "spore"]:
		out.append(Species.seed_template(kind, rng, {temp = rng.randf_range(0.3, 0.8)}))
	for env in GERM_ENVS:
		var e: Dictionary = env.duplicate()
		e.temp = rng.randf_range(0.3, 0.8)
		out.append(Species.seed_template("animal_germ", rng, e))
	for shape in SHAPES:
		out.append(Species.seed_template("shaped", rng, {temp = 0.55, traits = shape}))
	return out


## Évolution simulée : un vivier de lignées (semences + rosters) qui se divisent, avec parfois une
## transition de clade comme dans WorldSim. Renvoie {births, majors, combos, clades, ...}.
func _evolve(generations: int, seed: int, with_transitions := true) -> Dictionary:
	var rng := _rng(seed)
	var pool := _seeds(rng)
	for def in Species.PROLOGUE_ROSTER:
		pool.append(Species.traits_from_def(def))
	for def in Species.ROSTER:
		pool.append(Species.traits_from_def(def))
	var res := {births = [], majors = 0, novel = 0, combos = {}, clades = {}, violations = []}
	for i in generations:
		var k := rng.randi_range(0, pool.size() - 1)
		var parent: Dictionary = pool[k]
		var oxygen := rng.randf_range(0.0, 1.5) if rng.randf() < 0.3 else 1.0
		var child := Species.mutate(parent, rng, rng.randf_range(0.1, 0.9), 1.0 if rng.randf() < 0.1 else 0.0, oxygen)
		if with_transitions and rng.randf() < 0.01:
			var rules := []
			for rule in Species.TRANSITIONS:
				if rule.from == String(parent.get("clade", "")) and oxygen >= float(rule.oxygen):
					rules.append(rule)
			if not rules.is_empty():
				Species.apply_transition(child, rules[rng.randi_range(0, rules.size() - 1)], rng)
		var v := Species.genome_violations(child, oxygen)
		if not v.is_empty() and res.violations.size() < 5:
			res.violations.append("%s (%s) : %s" % [child.clade, child.body_plan, ", ".join(v)])
		for n in child.novelties:
			if Species.is_major_innovation(n):
				res.majors += 1
		if not (child.novelties as Array).is_empty():
			res.novel += 1
		res.combos["%s/%s" % [child.body_plan, child.locomotion]] = true
		res.clades[child.clade] = int(res.clades.get(child.clade, 0)) + 1
		res.births.append(child)
		if pool.size() < 400:
			pool.append(child)
		else:
			pool[rng.randi_range(0, pool.size() - 1)] = child
	return res


# --- Déterminisme ------------------------------------------------------------------------------

func test_life_is_deterministic() -> String:
	var a := _evolve(1500, 11)
	var b := _evolve(1500, 11)
	for i in a.births.size():
		if a.births[i] != b.births[i]:
			return "naissance %d différente d'une exécution à l'autre" % i
		if Species.describe(a.births[i]) != Species.describe(b.births[i]):
			return "description %d non déterministe" % i
		if Species.vernacular_name(a.births[i]) != Species.vernacular_name(b.births[i]):
			return "nom vernaculaire %d non déterministe" % i
	var r1 := _rng(5)
	var r2 := _rng(5)
	for i in 200:
		if Species.make_name("Hadrosaurus albus", r1, i % 3 == 0) != Species.make_name("Hadrosaurus albus", r2, i % 3 == 0):
			return "make_name non déterministe"
	for kind in Genome.SEED_KINDS:
		if Species.seed_template(kind, _rng(9), {traits = {size = 0.3}}) != Species.seed_template(kind, _rng(9), {traits = {size = 0.3}}):
			return "seed_template(%s) non déterministe" % kind
	return ""


## Le génome ne puise jamais dans le générateur partagé : WorldSim garde sa suite de tirages.
func test_genome_does_not_consume_shared_rng() -> String:
	var with_genome := Species.traits_from_def(Species.ROSTER[0])
	var bare := {}
	for key in ["size", "intelligence", "adaptability", "aggression", "diet", "temp_opt", "temp_tol", "clade", "complexity", "habitat", "anaerobic", "oxygenic"]:
		bare[key] = with_genome[key]
	for seed in 50:
		var r1 := _rng(seed)
		var r2 := _rng(seed)
		Species.mutate(with_genome, r1, 0.5, 1.0, 1.0)
		Species.mutate(bare, r2, 0.5, 1.0, 1.0)
		if r1.state != r2.state:
			return "mutate consomme le générateur selon le génome"
	# make_name : exactement les tirages de l'ancien nommage.
	for seed in 50:
		for fresh in [false, true]:
			var r1 := _rng(seed)
			var r2 := _rng(seed)
			Species.make_name("Hadrosaurus albus", r1, fresh)
			if fresh:
				for i in r2.randi_range(2, 3):
					r2.randi_range(0, 19)
			r2.randi_range(0, 19)
			r2.randi_range(0, 19)
			r2.randi_range(0, 7)
			if r1.state != r2.state:
				return "make_name ne tire plus comme avant (fresh=%s)" % fresh
	var r3 := _rng(3)
	var r4 := _rng(3)
	Species.random_traits(r3, 0.5, 6.0, true)
	r4.randf_range(0.05, 0.8)
	r4.randf_range(0.1, 0.4)
	r4.randf_range(0.3, 0.8)
	r4.randf_range(0.1, 0.9)
	r4.randi_range(0, 2)
	r4.randf_range(0.18, 0.32)
	if r3.state != r4.state:
		return "random_traits consomme davantage le générateur"
	return ""


# --- Contraintes ---------------------------------------------------------------------------------

func test_rosters_and_transitions_have_coherent_genomes() -> String:
	for def in Species.PROLOGUE_ROSTER + Species.ROSTER:
		var t := Species.traits_from_def(def)
		var v := Species.genome_violations(t)
		if not v.is_empty():
			return "%s : %s" % [def.name, ", ".join(v)]
		if t.clade != def.clade:
			return "%s : clade changé (%s)" % [def.name, t.clade]
		if not Genome.clade_fits(String(def.clade), t):
			return "%s : génome atypique de son clade" % def.name
	var methano := Species.traits_from_def(Species.PROLOGUE_ROSTER[0])
	if methano.metabolism != "chimiosynthèse" or Species.traits_from_def(Species.PROLOGUE_ROSTER[2]).metabolism != "photosynthèse":
		return "métabolismes du prologue faux"
	var birds := Species.traits_from_def(Species.ROSTER[8])
	if birds.locomotion != "vol" or birds.covering != "plumes" or not birds.warm_blooded:
		return "les Ornithurés devraient voler, emplumés et à sang chaud : %s" % str(birds)
	# Chaque transition de clade donne un corps typique et cohérent.
	var rng := _rng(4)
	var by_clade := {}
	for def in Species.PROLOGUE_ROSTER + Species.ROSTER:
		by_clade[def.clade] = Species.traits_from_def(def)
	for rule in Species.TRANSITIONS:
		if not by_clade.has(rule.from):
			var base := Species.traits_from_def({name = rule.from, size = 0.1, intelligence = 0.02, adaptability = 0.5, aggression = 0.3, diet = "autotrophe" if rule.from in ["algue", "plante", "microbe"] else "herbivore", temp_opt = 0.5, temp_tol = 0.3, clade = rule.from, complexity = 1.0 if rule.from == "algue" else (2.0 if rule.from == "plante" else 3.0), habitat = "land" if rule.from == "plante" else "marine"})
			by_clade[rule.from] = base
		for k in 20:
			var t := Species.mutate(by_clade[rule.from], rng, 0.5, 0.0, 1.0)
			Species.apply_transition(t, rule, rng)
			var v := Species.genome_violations(t)
			if not v.is_empty():
				return "transition %s -> %s : %s" % [rule.from, rule.to, ", ".join(v)]
			if not Genome.clade_fits(String(rule.to), t):
				return "transition %s -> %s : génome hors du clade (%s, %s, %s)" % [rule.from, rule.to, t.body_plan, t.locomotion, t.covering]
			by_clade[rule.to] = t
	return ""


func test_mutations_respect_physical_constraints() -> String:
	var res := _evolve(6000, 21)
	if not res.violations.is_empty():
		return "contraintes violées : %s" % "; ".join(res.violations)
	for t in res.births:
		var size := float(t["size"])
		if t.habitat == "land" and size > 0.25 and t.skeleton != "endosquelette" and t.diet != "autotrophe":
			return "grand animal terrestre sans squelette : %s" % str(t)
		if t.locomotion == "vol" and (not t.wings or size > Genome.FLIGHT_MAX_SIZE):
			return "vol sans ailes ou trop lourd : %s" % str(t)
		if t.warm_blooded and t.skeleton != "endosquelette":
			return "sang chaud sans squelette"
		if t.diet == "autotrophe" and not (t.weapons as Array).filter(func(w): return w != "épines" and w != "venin").is_empty():
			return "producteur armé : %s" % str(t.weapons)
	# Pas de vol quand l'oxygène manque : une lignée volante privée d'air se pose.
	var bird := Species.traits_from_def(Species.ROSTER[8])
	var rng := _rng(8)
	for i in 50:
		var c := Species.mutate(bird, rng, 0.5, 0.0, 0.05)
		if c.locomotion == "vol":
			return "vol malgré un oxygène à 5 %"
	return ""


func test_evolution_is_diverse_and_innovations_rare() -> String:
	var res := _evolve(10000, 33)
	var majors: int = res.majors
	print("  %d combinaisons plan/locomotion, %d clades, %d grandes innovations, %d naissances avec nouveauté" % [
		res.combos.size(), res.clades.size(), majors, res.novel])
	print("  clades : %s" % str(res.clades))
	if res.combos.size() < 12:
		return "trop peu de combinaisons plan/locomotion : %s" % str(res.combos.keys())
	if res.clades.size() < 10:
		return "trop peu de clades : %s" % str(res.clades.keys())
	if majors < 5:
		return "aucune grande innovation en 10 000 générations (%d)" % majors
	if majors > 200:
		return "grandes innovations trop fréquentes : %d sur 10 000" % majors
	# Les plans et locomotions de base existent tous.
	for p in Genome.BODY_PLANS:
		var found := false
		for key in res.combos:
			if String(key).begins_with(p + "/"):
				found = true
		if not found:
			return "plan corporel jamais vu : %s" % p
	for loco in Genome.LOCOMOTIONS:
		var found := false
		for key in res.combos:
			if String(key).ends_with("/" + loco):
				found = true
		if not found:
			return "locomotion jamais vue : %s" % loco
	# Les lignées libres innovent par elles-mêmes : des semences microbiennes deviennent complexes.
	var rng := _rng(77)
	var line := Species.seed_template("light", rng, {temp = 0.5})
	var best := 0.0
	for i in 6000:
		line = Species.mutate(line, rng, 0.5, 0.0, 1.0)
		best = maxf(best, float(line.complexity))
	if best < 2.0:
		return "une lignée libre de cyanobactéries n'a jamais innové (complexité %.0f)" % best
	return ""


# --- Semences ------------------------------------------------------------------------------------

func test_seed_templates_are_valid() -> String:
	var rng := _rng(13)
	for i in 30:
		var env := {temp = rng.randf_range(0.05, 0.95), oxygen = rng.randf_range(0.0, 1.2)}
		var spark := Species.seed_template("spark", rng, env)
		if spark.clade != "microbe" or spark.metabolism != "chimiosynthèse" or not spark.anaerobic or spark.oxygenic:
			return "étincelle incorrecte : %s" % str(spark)
		var light := Species.seed_template("light", rng, env)
		if light.clade != "microbe" or light.metabolism != "photosynthèse" or not light.oxygenic:
			return "lumière incorrecte : %s" % str(light)
		var spore := Species.seed_template("spore", rng, env)
		if spore.clade != "plante" or spore.habitat != "land" or spore.diet != "autotrophe":
			return "spore incorrecte : %s" % str(spore)
		var germs := {}
		for e in GERM_ENVS:
			var ge: Dictionary = e.duplicate()
			ge.merge(env)
			germs[e.role] = Species.seed_template("animal_germ", rng, ge)
		if germs.filtreur.locomotion != "fixe" or germs.filtreur.body_plan == "bilatéral":
			return "le filtreur devrait être fixe et sans symétrie bilatérale"
		if germs.brouteur.diet != "herbivore" or germs.chasseur.diet != "carnivore":
			return "germes : régimes faux"
		for t in [spark, light, spore, germs.filtreur, germs.brouteur, germs.chasseur]:
			var v := Species.genome_violations(t)
			if not v.is_empty():
				return "semence %s : %s" % [t.clade, ", ".join(v)]
			if not bool(t.free_evolution) or not t.has("seed_kind"):
				return "une semence doit être une lignée libre marquée"
	for shape in SHAPES:
		for k in 5:
			var t := Species.seed_template("shaped", rng, {temp = 0.5, traits = shape})
			var v := Species.genome_violations(t)
			if not v.is_empty():
				return "façonnée %s : %s" % [str(shape), ", ".join(v)]
			for key in ["size", "intelligence", "adaptability", "aggression", "diet", "temp_opt", "temp_tol", "clade", "complexity", "habitat"]:
				if not t.has(key):
					return "façonnée sans %s" % key
			if String(t.clade) == "":
				return "façonnée sans clade"
			if float(t.intelligence) >= Species.SAPIENCE_THRESHOLD:
				return "une semence ne naît pas consciente"
	var flyer := Species.seed_template("shaped", rng, {traits = SHAPES[0]})
	if flyer.locomotion != "vol" or not flyer.wings:
		return "la créature façonnée volante ne vole pas : %s" % str(flyer)
	var fur := Species.seed_template("shaped", rng, {traits = SHAPES[4]})
	if fur.covering != "poils" or fur.skeleton != "endosquelette":
		return "la créature à poils devrait être un vertébré à poils"
	var tree := Species.seed_template("shaped", rng, {traits = SHAPES[3]})
	if tree.diet != "autotrophe" or tree.covering != "écorce" or tree.habitat != "land":
		return "l'arbre façonné n'est pas un arbre : %s" % str(tree)
	return ""


# --- Noms et descriptions ------------------------------------------------------------------------

const BAD_PATTERNS := ["  ", " ,", " .", "..", "{", "}", "%", "<null>", " ;;", "::"]
## Élisions et contractions manquées : « de abysses », « ce arpenteur », « à les », « de les »…
const BAD_REGEX := ["\b[Dd]e [aeiouéèêâîôœ]", "\b[Cc]e [aeiouéèêâîôœ]", "\b[Qq]ue [aeiouéèêâîôœ]",
	"\b[Ll]e [aeiouéèêâîôœ]", "\b[Ll]a [aeiouéèêâîôœ]", "\b[àÀ] les?\b", "\b[Dd]e les?\b",
	"\b[Ss]i il", "\bune [a-zé]+ (bleu|vert|noir|brun|blanc|violet|orangé|doré|cuivré|argenté|nacré)\b"]


func _check_text(text: String) -> String:
	if text.strip_edges() == "":
		return "texte vide"
	if text != text.strip_edges():
		return "espaces en trop : « %s »" % text
	if text.substr(0, 1) != text.substr(0, 1).to_upper():
		return "pas de majuscule initiale : « %s »" % text
	for bad in BAD_PATTERNS:
		if text.contains(bad):
			return "« %s » dans « %s »" % [bad, text]
	for pattern in BAD_REGEX:
		var re := RegEx.create_from_string(pattern)
		var m := re.search(text)
		if m != null:
			return "« %s » dans « %s »" % [m.get_string(), text]
	return ""


func test_names_and_descriptions_are_clean_and_varied() -> String:
	var res := _evolve(4000, 55)
	var births: Array = res.births
	var descriptions := {}
	var vernaculars := {}
	var dup_desc := 0
	var dup_vern := 0
	for t in births:
		var d := Species.describe(t)
		var err := _check_text(d)
		if err != "":
			return "description : " + err
		var sentences := d.split(". ", false).size()
		if not d.ends_with(".") or sentences < 2 or sentences > 3:
			return "2 ou 3 phrases attendues : « %s »" % d
		# Accords du sujet : « Cette … » appelle « Elle », « Ce/Cet … » appelle « Il ».
		var second := d.split(". ")[1]
		if d.begins_with("Cette ") and not second.begins_with("Elle "):
			return "accord : « %s »" % d
		if (d.begins_with("Ce ") or d.begins_with("Cet ")) and not second.begins_with("Il "):
			return "accord : « %s »" % d
		if d.begins_with("Ce ") and Naming.starts_with_vowel(d.substr(3)):
			return "élision manquée : « %s »" % d
		if descriptions.has(d):
			dup_desc += 1
		descriptions[d] = true
		var v := Species.vernacular_name(t)
		var vp := Species.vernacular_name(t, true)
		for s in [v, vp]:
			err = _check_text(s)
			if err != "":
				return "nom vernaculaire : " + err
		if v == vp and not v.split(" ")[0].contains("-") and not v.split(" ")[0].ends_with("s") \
				and not v.split(" ")[0].ends_with("x"):
			return "pluriel identique au singulier : %s" % v
		if vernaculars.has(v):
			dup_vern += 1
		vernaculars[v] = true
	print("  %d descriptions, %d doublons ; %d noms vernaculaires, %d doublons" % [births.size(), dup_desc, births.size(), dup_vern])
	print("  ex. : %s — %s" % [Species.vernacular_name(births[0]), Species.describe(births[0])])
	print("  ex. : %s — %s" % [Species.vernacular_name(births[1999]), Species.describe(births[1999])])
	if dup_desc > births.size() / 200:
		return "descriptions répétées : %d sur %d" % [dup_desc, births.size()]
	# Ce vivier est un cas extrême (des centaines de sœurs issues d'une même semence, de même
	# couleur) : quelques homonymes bruts restent, que l'arbre de la vie départage.
	if dup_vern > births.size() * 15 / 100:
		return "noms vernaculaires trop répétés : %d sur %d" % [dup_vern, births.size()]
	var table := {}
	for i in births.size():
		table[i] = {name = "Espèce %d" % i, parent = -1, born_year = float(i), alive = true, traits = births[i]}
	var tree: RefCounted = Phylogeny.new()
	tree.sync(table)
	var canon := {}
	for id in tree.nodes:
		var v: String = tree.nodes[id].vernacular
		if v == "" or canon.has(v):
			return "nom canonique vide ou répété dans l'arbre de la vie : « %s »" % v
		canon[v] = true
	return ""


func test_latin_names_are_latin_and_unique() -> String:
	var rng := _rng(99)
	var used := {}
	var raw := {}
	var raw_dups := 0
	var parent := "Grypania lata"
	var res := _evolve(600, 3, false)
	for i in 5000:
		var t: Dictionary = res.births[i % res.births.size()]
		var fresh := rng.randf() < 0.15
		var name := Species.make_name(parent, rng, fresh, t)
		var parts := name.split(" ")
		if parts.size() != 2 or parts[0].length() < 3 or parts[1].length() < 3:
			return "binôme mal formé : %s" % name
		if parts[0] != parts[0].capitalize() or parts[1] != parts[1].to_lower():
			return "casse du binôme : %s" % name
		for ch in ["é", "è", "à", "ç", " ", "-"]:
			if parts[1].contains(ch):
				return "épithète non latine : %s" % name
		if not fresh and parts[0] != parent.split(" ")[0]:
			return "le genre n'est pas hérité : %s -> %s" % [parent, name]
		if raw.has(name):
			raw_dups += 1
		raw[name] = true
		var unique := Naming.unique(name, used, rng, t)
		if unique == "" or (used.size() != i + 1):
			return "registre de noms incohérent"
		parent = name
	print("  5000 binômes : %d doublons bruts (le registre Naming.unique les écarte)" % raw_dups)
	if raw_dups > 50:
		return "trop de binômes répétés : %d sur 5000" % raw_dups
	# Genres types : les groupes français transmettent un vrai genre latin.
	if not Species.make_name("Tyrannosauridés", _rng(1), false).begins_with("Tyrannosaurus "):
		return "le genre type des Tyrannosauridés est perdu"
	# Accord de l'épithète avec le genre grammatical.
	var g := _rng(4)
	for i in 200:
		var fem := Naming.binomial(g, "Lingula")
		var ep := fem.split(" ")[1]
		if ep.ends_with("us") and not ep.ends_with("ius") and not ep.ends_with("ensis"):
			return "épithète masculine sur un genre féminin : %s" % fem
	return ""


func test_agreement_and_colors() -> String:
	var t := Species.seed_template("shaped", _rng(1), {traits = {size = 0.3, diet = "carnivore", weapons = ["épines"]}})
	t.hue = 0.6
	t.sat = 0.8
	t.val = 0.7
	if Naming.color_adj(t, false, false) != "bleu" or Naming.color_adj(t, true, true) != "bleues" \
			or Naming.color_adj(t, false, true) != "bleus" or Naming.color_adj(t, true, false) != "bleue":
		return "accords de « bleu » faux"
	t.val = 0.2
	if Naming.color_adj(t, true, true) != "bleu sombre":
		return "une couleur nuancée est invariable : %s" % Naming.color_adj(t, true, true)
	t.hue = 0.07
	t.val = 0.8
	t.sat = 0.9
	var o := Naming.color_adj(t, true, true)
	if not (o == "orangées" or o == "cuivrées"):
		return "accord de l'orangé faux : %s" % o
	var parts := {head = "Rampeur", fem = false, pre = "", adj = "tacheté", compl = "à épines bleues", t = t}
	if Naming.assemble(parts, false) != "Rampeur tacheté à épines bleues" or Naming.assemble(parts, true) != "Rampeurs tachetés à épines bleues":
		return "assemblage masculin faux : %s / %s" % [Naming.assemble(parts, false), Naming.assemble(parts, true)]
	parts = {head = "Ombrelle", fem = true, pre = "grand", adj = "lumineux", compl = "des abysses", t = t}
	if Naming.assemble(parts, false) != "Grande ombrelle lumineuse des abysses" or Naming.assemble(parts, true) != "Grandes ombrelles lumineuses des abysses":
		return "assemblage féminin faux : %s / %s" % [Naming.assemble(parts, false), Naming.assemble(parts, true)]
	if Naming.plural_noun("Fuseau") != "Fuseaux" or Naming.plural_noun("Tapis") != "Tapis":
		return "pluriels des noms faux"
	return ""
