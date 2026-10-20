extends RefCounted
## Tests du compagnon (docs/GENESE.md) : explications par phénomène, présentation et épitaphe des espèces,
## réactions aux semences, fin des temps et réincarnation, zéro anachronisme, déterminisme.
## Mode repli uniquement : aucun LLM. Chaque test renvoie "" si OK, sinon un message.

const Epoch := preload("res://src/ai/epoch.gd")
const Prompts := preload("res://src/ai/prompt_builder.gd")
const Phenomena := preload("res://src/ai/facts/phenomena.gd")
const Explainer := preload("res://src/ai/explainer.gd")
const Bestiary := preload("res://src/ai/bestiary.gd")
const Seeds := preload("res://src/ai/seeds.gd")
const Worlds := preload("res://src/ai/worlds.gd")
const Chronicle := preload("res://src/ai/chronicle.gd")

## Phénomènes que docs/GENESE.md demande explicitement d'expliquer.
const REQUIRED_PHENOMENA := ["oxygen_rise", "ozone", "land_colonization", "island_speciation", "continental_split",
	"decline_predation", "decline_climate", "decline_competition", "greenhouse", "sun_aging"]
const CLADES := ["microbe", "algue", "éponge", "arthropode", "mollusque", "poisson", "amphibien", "reptile", "dinosaure",
	"oiseau", "mammifère", "primate", "ptérosaure", "insecte", "plante", "synapside", "chimère", "inconnu", ""]
const DIETS := ["herbivore", "carnivore", "omnivore", "photosynthèse", "filtreur", "détritivore", "", "???"]
const NAMES := ["Trilobites", "Grand Rampant", "les Fileuses", "Hadrosauridés", "Vélocérapteur des sables", "Oo", "Ébène", "L'Aube"]


## Un contexte dont l'époque effective (Epoch.current) vaut `epoch`.
func _ctx_at(epoch: int) -> Dictionary:
	var ctx := {"divine": [], "species": [], "snapshot": {"biome": "Forêt tempérée", "land_use": "wild",
		"temperature_c": 18.0, "global_temperature_c": 15.0, "structures": {}, "fauna": []}}
	if epoch >= Epoch.FIRST_SAPIENT:
		ctx["era"] = Epoch.NAMES[epoch]
		ctx["year"] = 1000.0
		ctx["species"] = [{"id": 1, "name": "Humains", "clade": "primate", "sapient": true, "alive": true,
			"tech_level": float(epoch - Epoch.FIRST_SAPIENT) + 0.5}]
	elif epoch >= Epoch.MESOZOIC:
		ctx["era"] = Epoch.NAMES[epoch]
		ctx["year"] = -100_000_000.0 if epoch == Epoch.MESOZOIC else -10_000_000.0
	else:
		ctx["era"] = "Prologue"
		ctx["year"] = float(Epoch.STAGES[epoch][1]) + 1_000_000.0
	return ctx


static func _well_formed(t: String) -> String:
	if t.strip_edges() == "":
		return "texte vide"
	for bad in ["{", "}", "[", "]", "  ", " ,", " .", "..", "  "]:
		if t.contains(bad):
			return "« %s » dans : %s" % [bad, t]
	if not t.right(1) in [".", "!", "?", "…", "»"]:
		return "pas de ponctuation finale : " + t
	if t.substr(0, 1) != t.substr(0, 1).to_upper():
		return "pas de majuscule initiale : " + t
	return ""


## Espèce aux traits arbitraires (génome étendu une fois sur deux).
static func _random_species(rng: RandomNumberGenerator, id: int) -> Dictionary:
	var traits := {"size": rng.randf(), "intelligence": rng.randf(), "aggression": rng.randf(), "adaptability": rng.randf(),
		"diet": DIETS[rng.randi() % DIETS.size()], "temp_opt": rng.randf(), "temp_tol": rng.randf(),
		"clade": CLADES[rng.randi() % CLADES.size()]}
	if rng.randf() < 0.5:
		traits["body_plan"] = ["radial", "bilateral", "segmented", "colonial", "blob", "???"][rng.randi() % 6]
		traits["locomotion"] = ["swim", "crawl", "walk", "fly", "sessile", "burrow", "glide", "??"][rng.randi() % 8]
		traits["covering"] = ["scales", "fur", "feathers", "shell", "skin", "plumes", "écailles", "??"][rng.randi() % 8]
		traits["colors"] = [Color(rng.randf(), rng.randf(), rng.randf()), "bleu", "doré"].slice(0, 1 + rng.randi() % 3)
		traits["habitat"] = ["ocean", "land", "air", "freshwater", "vents", "??"][rng.randi() % 6]
	var sp := {"id": id, "name": NAMES[rng.randi() % NAMES.size()], "traits": traits, "alive": true,
		"sapient": rng.randf() < 0.1, "born_year": -500_000_000.0 + rng.randf() * 1e8}
	if rng.randf() < 0.5:
		sp["extinct_year"] = float(sp["born_year"]) + rng.randf() * 5e7
	if rng.randf() < 0.2:
		sp["born_year"] = NAN
	return sp


func test_aucune_trace_de_dilemme_ni_de_samael() -> String:
	var files := []
	for dir in ["res://src/ai", "res://src/ai/facts"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				files.append(dir + "/" + f)
	var re := RegEx.create_from_string("(?i)dilemm|sama[eë]l|adversary|game_master|strategy|stratégi|dilemma_ready")
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		var m := re.search(text)
		if m != null:
			return "trace de « %s » dans %s" % [m.get_string(), path]
	var narrator: Node = load("res://src/ai/narrator.gd").new()
	var bad := ""
	for sig in ["dilemma_ready", "dilemma_resolved", "adversary_spoke"]:
		if narrator.has_signal(sig):
			bad = sig
	for sig in ["species_presented", "epitaph_written", "seed_reaction", "world_ended", "world_reborn"]:
		if not narrator.has_signal(sig):
			bad = "manque " + sig
	narrator.free()
	return "" if bad == "" else "signaux du narrateur : " + bad


func test_chaque_phenomene_a_ses_explications() -> String:
	for p in REQUIRED_PHENOMENA:
		if not p in Phenomena.ids():
			return "phénomène demandé absent : " + p
	var ex := Explainer.new(11)
	for p in Phenomena.ids():
		var facts := Phenomena.facts_of(p)
		if facts.size() < 3:
			return "%s : %d faits (3 au moins)" % [p, facts.size()]
		for f in facts:
			var err := _well_formed(str(f["t"]))
			if err != "":
				return "%s : %s" % [p, err]
		var seen := {}
		for i in facts.size():
			var line := ex.explain(p, _ctx_at(Epoch.LAST))
			if line.is_empty():
				return "%s : explication %d manquante" % [p, i + 1]
			if seen.has(line["fact_id"]):
				return "%s : fait répété avant d'avoir tout dit" % p
			seen[line["fact_id"]] = true
	return ""


func test_lecture_des_statistiques() -> String:
	var s := Explainer.normalize({"o2": 21.0, "o3": 300.0, "co2": 280.0})
	if absf(float(s.get("oxygen", 0.0)) - 0.21) > 0.001:
		return "oxygène en pourcent mal lu : %s" % [s]
	var before := {"oxygen": 0.001, "ozone": 0.1, "co2_ppm": 400.0, "temperature_c": 12.0, "year": -600e6}
	var now := {"oxygen": 0.05, "ozone": 0.7, "co2_ppm": 900.0, "temperature_c": 20.0, "year": -400e6}
	var found := Explainer.detect(before, now)
	for p in ["oxygen_rise", "ozone", "land_colonization", "greenhouse"]:
		if not p in found:
			return "%s non reconnu dans %s" % [p, found]
	if not Explainer.detect(now, now).is_empty():
		return "phénomène inventé sans changement : %s" % [Explainer.detect(now, now)]
	var line := Explainer.new(3).stats_line(now, [before], _ctx_at(Epoch.LAND))
	if line.is_empty() or _well_formed(str(line["text"])) != "":
		return "commentaire chiffré absent ou mal formé : %s" % [line]
	var cold := {"snapshot": {"temperature_c": -25.0, "fauna": []}}
	if Explainer.decline_cause({"temp_opt": 0.8, "temp_tol": 0.1}, cold) != "climate":
		return "déclin par le climat non reconnu"
	var hunted := {"snapshot": {"temperature_c": 15.0, "fauna": [{"name": "Raptors", "role": "carnivore", "trend": 1}]}}
	if Explainer.decline_cause({"name": "Proies", "temp_opt": 0.6, "temp_tol": 0.3}, hunted) != "predation":
		return "déclin par les prédateurs non reconnu"
	if Explainer.decline_cause({"name": "Proies"}, {"snapshot": {"fauna": []}}) != "competition":
		return "déclin par la concurrence non reconnu"
	return ""


func test_le_fil_explique() -> String:
	var chron := Chronicle.new(5)
	var ctx := _ctx_at(Epoch.LAND)
	ctx["planet"] = {"oxygen": 0.1, "ozone": 0.6, "co2_ppm": 2000.0, "temperature_c": 22.0, "year": ctx["year"]}
	ctx["planet_history"] = [{"oxygen": 0.02, "ozone": 0.2, "co2_ppm": 4000.0, "temperature_c": 30.0, "year": float(ctx["year"]) - 5e7}]
	ctx["phenomena"] = ["ozone", "land_colonization"]
	var kinds := {}
	for i in 60:
		var line := chron.ambient(ctx)
		if not line.is_empty():
			kinds[str(line["kind"])] = true
	for k in ["explanation", "stats"]:
		if not kinds.has(k):
			return "le fil ne produit jamais « %s » : %s" % [k, kinds.keys()]
	return ""


func test_semences_reussite_et_echec_avec_raison() -> String:
	var planets := [
		{"oxygen": 0.0, "ozone": 0.0, "temperature_c": 25.0, "biomass": 0.0},
		{"oxygen": 0.21, "ozone": 1.0, "temperature_c": 15.0, "biomass": 1.0},
		{"oxygen": 0.21, "ozone": 1.0, "temperature_c": 90.0},
		{"oxygen": 0.21, "ozone": 1.0, "temperature_c": -40.0, "ice_cover": 0.95},
	]
	for kind in Seeds.KINDS:
		for planet in planets:
			for success in [true, false]:
				var cons := [{"type": "spawn", "species_id": 7}] if success else []
				var r := Seeds.react({"type": "seed", "kind": kind}, cons, planet, _ctx_at(Epoch.CAMBRIAN))
				if bool(r["success"]) != success:
					return "%s : verdict inversé" % kind
				if not str(r["reason_code"]) in Seeds.reason_codes(success):
					return "%s : raison %s inconnue" % [kind, r["reason_code"]]
				var err := _well_formed(str(r["text"]))
				if err != "":
					return "%s : %s" % [kind, err]
				if not str(r["text"]).contains(":"):
					return "%s : la raison n'est pas dite : %s" % [kind, r["text"]]
		# Chaque raison fournie par la simulation est dite telle quelle.
		for success in [true, false]:
			for code in Seeds.reason_codes(success):
				var r := Seeds.react({"type": "seed", "kind": kind}, [{"success": success, "reason_code": code}])
				if str(r["reason_code"]) != code:
					return "%s : raison %s remplacée par %s" % [kind, code, r["reason_code"]]
				var err := _well_formed(str(r["text"]))
				if err != "":
					return "%s/%s : %s" % [kind, code, err]
	var spores := Seeds.react({"type": "seed", "kind": "spore"}, [], {"ozone": 0.05, "oxygen": 0.01})
	if str(spores["reason_code"]) != "no_ozone" or not str(spores["text"]).contains("ozone"):
		return "spores sans ozone : " + str(spores)
	var germs := Seeds.react({"type": "seed", "kind": "animal_germ"}, [], {"ozone": 1.0, "oxygen": 0.001})
	if str(germs["reason_code"]) != "low_oxygen":
		return "germes sans oxygène : " + str(germs)
	return ""


func test_presentation_et_epitaphe_de_traits_arbitraires() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var b := Bestiary.new(9)
	for i in 400:
		var sp := _random_species(rng, i)
		var ctx := _ctx_at(rng.randi() % (Epoch.LAST + 1))
		var name := str(sp["name"])
		for line in [b.present(sp, ctx), b.epitaph(sp, ctx, ["", "climate", "predation", "competition", "impact", "divine", "oxygen", "???"][i % 8],
				["", "seed", "bless", "save", "spawn_species"][i % 5])]:
			var t := str(line["text"])
			var err := _well_formed(t)
			if err != "":
				return "%s : %s (traits %s)" % [line["kind"], err, sp["traits"]]
			if not t.to_lower().contains(name.to_lower().trim_prefix("les ").trim_prefix("l'")):
				return "%s sans le nom « %s » : %s" % [line["kind"], name, t]
			if int(line["species_id"]) != i:
				return "species_id perdu"
	var described := b.present({"id": 1, "name": "Fileuses", "description": "Elles tissent des voiles de soie entre les rochers."}, _ctx_at(Epoch.LAND))
	if not str(described["text"]).contains("voiles de soie"):
		return "description procédurale de la session Vie ignorée : " + str(described["text"])
	var prompt := Prompts.build_species_prompt({"name": "Fileuses", "traits": {"size": 0.2}}, _ctx_at(Epoch.LAND), "Base.", "presentation")
	if not prompt.contains("Fileuses") or Prompts.species_system().strip_edges() == "":
		return "prompt d'espèce incomplet"
	return ""


func test_determinisme() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var species := []
	for i in 30:
		species.append(_random_species(rng, i))
	var runs := []
	for k in 2:
		var b := Bestiary.new(4)
		var ex := Explainer.new(4)
		var w := Worlds.new(4)
		var out := PackedStringArray()
		for sp in species:
			out.append(str(b.present(sp, _ctx_at(Epoch.CENOZOIC))["text"]))
			out.append(str(b.epitaph(sp, _ctx_at(Epoch.CENOZOIC))["text"]))
		for p in Phenomena.ids():
			out.append(str(ex.explain(p, _ctx_at(Epoch.LAST)).get("text", "")))
		for kind in Seeds.KINDS:
			out.append(str(Seeds.react({"type": "seed", "kind": kind}, [], {"ozone": 0.1})["text"]))
		w.note_species("Trilobites", true)
		out.append(w.end_of_times("sun", 5e9))
		out.append(w.reincarnation({"size": 0.6}))
		runs.append("\n".join(out))
	return "" if runs[0] == runs[1] else "sorties différentes à graine égale"


func test_zero_anachronisme() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var b := Bestiary.new(2)
	var ex := Explainer.new(2)
	for e in range(Epoch.LAST + 1):
		var ctx := _ctx_at(e)
		for i in 40:
			var sp := _random_species(rng, i)
			for t in [str(b.present(sp, ctx)["text"]), str(b.epitaph(sp, ctx)["text"])]:
				if not Epoch.is_clean(t, e):
					return "%s : anachronisme %s dans : %s" % [Epoch.NAMES[e], Epoch.violations(t, e), t]
		for p in Phenomena.ids():
			var t := str(ex.explain(p, ctx).get("text", ""))
			if not Epoch.is_clean(t, e):
				return "%s : explication anachronique : %s" % [Epoch.NAMES[e], t]
		for kind in Seeds.KINDS:
			for success in [true, false]:
				for code in Seeds.reason_codes(success):
					var t := str(Seeds.react({"type": "seed", "kind": kind}, [{"success": success, "reason_code": code}], {}, ctx)["text"])
					if not Epoch.is_clean(t, e):
						return "%s : semence anachronique : %s" % [Epoch.NAMES[e], t]
	return ""


func test_fin_des_temps_et_reincarnation() -> String:
	var w := Worlds.new(1)
	var first := w.reincarnation()
	if not first.contains("aucun autre monde"):
		return "premier monde avec des souvenirs : " + first
	w.note_year(-4e9)
	for n in ["Cyanobactéries", "Trilobites", "Hadrosauridés"]:
		w.note_species(n, true)
	w.note_civilization("Humains")
	w.note_seed()
	for end in Worlds.ENDS:
		var w2 := Worlds.new(2)
		w2.note_species("Trilobites", true)
		var t := w2.end_of_times(end, 5e9)
		if _well_formed(t) != "":
			return "fin « %s » : %s" % [end, _well_formed(t)]
	var end_text := w.end_of_times("sun", 5e9)
	if not end_text.contains("Soleil") or not end_text.contains("Humains"):
		return "fin des temps sans bilan : " + end_text
	var rebirth := w.reincarnation({"size": 0.5, "ocean_fraction": 0.9})
	if not rebirth.contains("souviens") or not rebirth.contains("Humains") or _well_formed(rebirth) != "":
		return "réincarnation sans mémoire : " + rebirth
	var copy := Worlds.new(1)
	copy.restore(w.snapshot())
	if copy.past.size() != 1 or str(copy.past[0]["civilizations"][0]) != "Humains":
		return "sauvegarde des mondes perdue"
	for i in 30:
		w.end_of_times("frozen", 1e9)
	if w.past.size() > Worlds.MAX_WORLDS or w.forgotten <= 0:
		return "mémoire des mondes non bornée"
	if not w.reincarnation().contains("vie de dieu"):
		return "les vies passées ne sont pas comptées"
	return ""


func test_contrats_planete_et_sauvegarde() -> String:
	var N: GDScript = load("res://src/ai/narrator.gd")
	if absf(float(N._air_oxygen({"oxygen": 1.0})["oxygen"]) - 0.21) > 0.001:
		return "oxygène de planet_stats (niveau actuel) mal converti"
	var cases := {"Le Soleil a englouti la Terre": "sun", "oceans_boiled": "oceans", "player": "player", "": ""}
	for summary in cases:
		if N.end_cause({"summary": summary}) != cases[summary]:
			return "cause de fin des temps « %s » mal lue : %s" % [summary, N.end_cause({"summary": summary})]
	var narrator: Node = N.new()
	var ok := narrator.has_method("save_state") and narrator.has_method("load_state")
	narrator.free()
	return "" if ok else "save_state / load_state absents"


func test_sauvegarde_et_bilan_du_narrateur() -> String:
	var n: Node = load("res://src/ai/narrator.gd").new()
	n._build_memory()
	var err := _check_narrator_memory(n)
	n.free()
	return err


func _check_narrator_memory(n: Node) -> String:
	n.chronicle.inventor.forgotten = 3
	n.worlds.note_species("Trilobites", true)
	n._divine_history.append({"type": "seed", "year": -5e8, "species_id": 4})
	n._deeds[4] = "seed"
	var saved: Dictionary = bytes_to_var(var_to_bytes(n.save_state()))
	n.chronicle.inventor.forgotten = 0
	n._divine_history.clear()
	n._deeds.clear()
	n.worlds.current = Worlds._blank()
	n.load_state(saved)
	if n.chronicle.inventor.forgotten != 3 or n._divine_history.size() != 1 or str(n._deeds.get(4, "")) != "seed" \
			or not "Trilobites" in n.worlds.current["notable"]:
		return "mémoire perdue au rechargement"
	if var_to_bytes(n.save_state()) != var_to_bytes(saved):
		return "sauvegarde différente après rechargement"
	n.load_state({"inventor": {"profiles": 5, "archive": "x"}, "inconnu": 1, "variety": {"_ring": [1, 2]}})
	n.load_state({})
	var texts := []
	var grab := func(t: String) -> void: texts.append(t)
	n.world_ended.connect(grab)
	n.world_reborn.connect(grab)
	n._ended = false
	n._on_end_of_times_signal({"world_name": "Gaïa", "species_total": 40, "cause": "Le Soleil a grossi",
		"notable": [{"name": "Fileuses", "sapient": true}]})
	n._on_end_of_times({"type": "end_of_times", "summary": "sun"})
	n._on_reincarnation({"world_name": "Thalassa", "world_index": 2, "params": {"ocean_fraction": 0.9, "star_luminosity": 0.7}})
	n.world_ended.disconnect(grab)
	n.world_reborn.disconnect(grab)
	if texts.size() != 2:
		return "fin des temps racontée %d fois : %s" % [texts.size(), texts]
	if not (str(texts[0]).contains("Gaïa") and str(texts[0]).contains("40 espèces") and str(texts[0]).contains("Fileuses")):
		return "bilan ignoré : " + str(texts[0])
	if not (str(texts[1]).contains("Thalassa") and str(texts[1]).contains("pâle") and str(texts[1]).contains("Fileuses")):
		return "nouvelle planète mal décrite : " + str(texts[1])
	return ""
