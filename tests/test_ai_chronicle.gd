extends RefCounted
## Tests du fil continu (chronicle.gd), des faits réels (facts/), de la divergence et de l'invention.
## Mode repli uniquement : aucun LLM, aucun réseau. Chaque test renvoie "" si OK, sinon un message.

const AiConfig := preload("res://src/ai/ai_config.gd")
const Procedural := preload("res://src/ai/procedural_narrator.gd")
const Prompts := preload("res://src/ai/prompt_builder.gd")
const NarratorScript := preload("res://src/ai/narrator.gd")
const Chronicle := preload("res://src/ai/chronicle.gd")
const FactBase := preload("res://src/ai/facts/fact_base.gd")
const Divergence := preload("res://src/ai/divergence.gd")
const Inventor := preload("res://src/ai/inventor.gd")

const PLURAL_NAMES := ["Sauriens", "Aviens", "Humains", "Multituberculés", "Tyrannosauridés"]
const SINGULAR_NAMES := ["Verpha moloum", "Raxi", "Kensar tolumensis"]
## Une date représentative de chaque ère réelle, et le minimum de faits vrais attendus à cette date.
const ERA_DATES := {
	"Mésozoïque": [-66_000_000.0, 15], "Cénozoïque": [-20_000_000.0, 6], "Préhistoire": [-9_000.0, 12],
	"Antiquité": [200.0, 15], "Moyen Âge": [1400.0, 15], "Renaissance": [1700.0, 14],
	"Industriel": [1930.0, 14], "Moderne": [2024.0, 15],
}


static func _sentences(t: String) -> int:
	var n := 0
	for i in t.length():
		if t[i] in [".", "!", "?", "…"] and (i + 1 == t.length() or t[i + 1] == " "):
			n += 1
	return n


## "" si le texte est une ligne correcte du fil (1 ou 2 phrases, rien de non résolu).
static func _check_line(t: String) -> String:
	if t.strip_edges().length() < 15:
		return "texte vide ou trop court : « %s »" % t
	for bad in ["{", "}", "[", "]", " de les ", " à les ", " de le ", " que un ", " de un ", "  ", " ,", " ."]:
		if t.contains(bad):
			return "« %s » dans : %s" % [bad, t]
	var first := t.substr(0, 1)
	if first != first.to_upper() or first == first.to_lower():
		return "pas de majuscule initiale : " + t
	if not (t.ends_with(".") or t.ends_with("!") or t.ends_with("…")):
		return "pas de ponctuation finale : " + t
	var n := _sentences(t)
	if n < 1 or n > 2:
		return "%d phrases au lieu de 1 ou 2 : %s" % [n, t]
	return ""


func _beast(id: int, name: String, role: String, clade: String) -> Dictionary:
	return {"species_id": id, "name": name, "role": role, "count": 9, "trend": 0, "clade": clade}


func _species(id: int, name: String, clade: String, sapient: bool, diet := "omnivore", size := 0.4) -> Dictionary:
	return {"id": id, "name": name, "clade": clade, "sapient": sapient, "alive": true, "diet": diet, "size": size,
		"intelligence": 0.9 if sapient else 0.2, "aggression": 0.5, "tech_level": 1.0}


func _ctx(era: String, year: float, fauna: Array = [], species: Array = [], temp := 22.0) -> Dictionary:
	return {
		"era": era, "year": year, "species": species, "divine": [], "recent_events": [],
		"snapshot": {"year": year, "biome": "Forêt tempérée", "land_use": "wild", "temperature_c": temp,
			"global_temperature_c": 16.0, "fauna": fauna, "structures": {}},
	}


# --- Faits réels -------------------------------------------------------------

func test_faits_assez_nombreux_et_bien_formes() -> String:
	var ids := {}
	for era in FactBase.REAL_ERAS:
		var facts := FactBase.era_facts(era)
		if facts.size() < 15:
			return "%s : seulement %d faits" % [era, facts.size()]
		for f in facts:
			var err := _check_line(str(f.get("t", "")))
			if err != "":
				return "%s : %s" % [f["id"], err]
			if ids.has(f["id"]) or ids.has(f["t"]):
				return "fait en double : %s" % f["id"]
			ids[f["id"]] = true
			ids[f["t"]] = true
			for k in f:
				if not k in ["t", "id", "min_year", "max_year"] + FactBase.TAG_KEYS:
					return "%s : clé inconnue « %s »" % [f["id"], k]
			for k in FactBase.TAG_KEYS:
				if f.has(k) and not (f[k] is Array and not f[k].is_empty()):
					return "%s : tag « %s » vide ou mal typé" % [f["id"], k]
			if float(f.get("min_year", -INF)) > float(f.get("max_year", INF)):
				return "%s : fenêtre de dates inversée" % f["id"]
	for era in ["Cyberpunk", "Post-singularité"]:
		if not FactBase.era_facts(era).is_empty():
			return "l'ère future %s ne doit pas avoir de faits réels" % era
	return ""


## Un fait n'est raconté qu'à une date où il est vrai, et chaque ère a de quoi raconter à sa date.
func test_faits_vrais_a_la_date() -> String:
	for era in ERA_DATES:
		var year: float = ERA_DATES[era][0]
		var n := FactBase.candidates(era, year).size()
		if n < int(ERA_DATES[era][1]):
			return "%s en %d : seulement %d faits vrais" % [era, int(year), n]
		for f in FactBase.candidates(era, year):
			if not FactBase.true_at(f, year):
				return "fait hors de sa fenêtre : " + str(f["id"])
	var lucy := FactBase.candidates("Cénozoïque", -66_000_000.0).filter(func(f): return str(f["t"]).contains("Lucy"))
	if not lucy.is_empty():
		return "Lucy racontée au Crétacé"
	var impact := FactBase.candidates("Cénozoïque", -10_000_000.0).filter(func(f): return str(f["t"]).contains("Chicxulub"))
	if not impact.is_empty():
		return "l'impact raconté 56 millions d'années trop tard"
	if not FactBase.candidates("Antiquité", null).all(func(f): return not (f.has("min_year") or f.has("max_year"))):
		return "date inconnue : seuls les faits sans fenêtre devraient passer"
	return ""


func test_faits_pertinents_d_abord() -> String:
	var farm := {"t": "x", "land_use": ["farmland"]}
	var plain := {"t": "y"}
	var situation := {"clades": ["dinosaure"], "biome": "Savane", "land_use": "farmland", "events": ["plague"]}
	if FactBase.score(farm, situation) <= FactBase.score(plain, situation):
		return "un fait sur ce qu'on voit devrait peser plus"
	return ""


func test_pas_deux_fois_le_meme_fait_de_suite() -> String:
	for era in ERA_DATES:
		var chron := Chronicle.new(4)
		var ctx := _ctx(era, ERA_DATES[era][0], [_beast(1, "Hadrosauridés", "herbivore", "dinosaure")])
		var last := ""
		var window: Array[String] = []
		for i in 80:
			var line := chron.fact(ctx)
			if line.is_empty():
				return "%s : plus aucun fait disponible au tour %d" % [era, i]
			var id := str(line["fact_id"])
			if id == last:
				return "%s : même fait deux fois de suite (%s)" % [era, id]
			if id in window:
				return "%s : fait répété trop tôt (%s)" % [era, id]
			window.append(id)
			if window.size() > mini(Chronicle.FACT_MEMORY, FactBase.candidates(era, ERA_DATES[era][0]).size() - 1):
				window.pop_front()
			last = id
	return ""


# --- Fil continu -------------------------------------------------------------

func test_fil_continu_lignes_correctes() -> String:
	var fauna := [_beast(1, "Hadrosauridés", "herbivore", "dinosaure"), _beast(2, "Verpha moloum", "carnivore", "reptile")]
	for era in Procedural.ERAS:
		var chron := Chronicle.new(2)
		for trend in [-1, 0, 1]:
			for f in fauna:
				f["trend"] = trend
			for fa in [fauna, []]:
				for i in 6:
					var line := chron.ambient(_ctx(era, 1200.0, fa))
					var err := _check_line(str(line.get("text", "")))
					if err != "":
						return "%s (%s) : %s" % [era, line.get("kind"), err]
					if line.get("source") != "ambient":
						return "source manquante : %s" % str(line)
	return ""


func test_fil_continu_rythme() -> String:
	var cfg := AiConfig.new("user://test_ai_chronicle.cfg")
	var lo := float(cfg.get_value("narrator", "ambient_min_sec"))
	var hi := float(cfg.get_value("narrator", "ambient_max_sec"))
	if lo != 8.0 or hi != 15.0:
		return "rythme par défaut inattendu : %f..%f" % [lo, hi]
	if float(cfg.get_value("narrator", "min_interval_sec")) > 4.0:
		return "les événements doivent passer presque aussitôt"
	if NarratorScript.ambient_due(7.9, 8.0, true, true) or not NarratorScript.ambient_due(8.0, 8.0, true, true):
		return "seuil d'ambiance mal appliqué"
	if NarratorScript.ambient_due(30.0, 8.0, false, true) or NarratorScript.ambient_due(30.0, 8.0, true, false):
		return "ambiance émise alors qu'elle est coupée ou sans monde"
	return ""


func test_fil_determinisme() -> String:
	var run := func(s: int) -> PackedStringArray:
		var chron := Chronicle.new(s)
		var lens := Divergence.new()
		var out := PackedStringArray()
		var sauriens := _species(5, "Sauriens", "dinosaure", true, "carnivore", 0.6)
		for i in 30:
			var year := -66_000_000.0 + i * 400_000.0
			var ctx := _ctx("Cénozoïque" if i > 2 else "Mésozoïque", year, [_beast(5, "Sauriens", "sapient", "dinosaure")] if i > 10 else [_beast(1, "Hadrosauridés", "herbivore", "dinosaure")],
				[sauriens] if i > 10 else [_species(1, "Hadrosauridés", "dinosaure", false, "herbivore", 0.8)])
			ctx["mode"] = lens.update(ctx)
			out.append(chron.ambient(ctx)["text"])
		return out
	var a: PackedStringArray = run.call(42)
	if a != run.call(42):
		return "même graine, fil différent"
	if a == run.call(43):
		return "la graine n'a aucun effet"
	return ""


# --- Réel / divergent ----------------------------------------------------------

func test_criteres_de_divergence() -> String:
	var dino := _species(1, "Tyrannosauridés", "dinosaure", false, "carnivore", 0.9)
	var humans := _species(2, "Humains", "primate", true)
	var cases := [
		[{"era": "Mésozoïque", "year": -66_000_000.0, "species": [dino]}, []],
		[{"era": "Cénozoïque", "year": -60_000_000.0, "species": [dino]}, ["dinosaurs_survived"]],
		[{"era": "Préhistoire", "year": -100_000.0, "species": [humans]}, []],
		[{"era": "Antiquité", "year": -500.0, "species": [humans]}, []],
		[{"era": "Moderne", "year": 2020.0, "species": [humans]}, []],
		[{"era": "Préhistoire", "year": -30_000_000.0, "species": [humans]}, ["early_sapience", "era_out_of_time"]],
		[{"era": "Antiquité", "year": -500.0, "species": [_species(3, "Sauriens", "dinosaure", true)]}, ["non_human_sapient"]],
		[{"era": "Industriel", "year": 300.0, "species": [humans]}, ["era_out_of_time"]],
		[{"era": "Moderne", "year": 2100.0, "species": [humans]}, ["future"]],
		[{"era": "Cyberpunk", "year": 2020.0, "species": [humans]}, ["future"]],
		[{"era": "Antiquité", "year": -500.0, "species": [humans], "divine": [{"type": "uplift"}]}, ["divine_creation"]],
	]
	for c in cases:
		var got := Divergence.assess(c[0])
		for want in c[1]:
			if not want in got:
				return "critère « %s » attendu pour %s, obtenu %s" % [want, str(c[0]), str(got)]
		if c[1].is_empty() and not got.is_empty():
			return "monde réel jugé divergent (%s) : %s" % [str(got), str(c[0])]
	return ""


## Réel -> divergent : bascule annoncée une fois, puis invention ; plus aucun fait réel ensuite.
func test_bascule_reel_vers_divergent() -> String:
	var chron := Chronicle.new(7)
	var lens := Divergence.new()
	var dino := _species(1, "Hadrosauridés", "dinosaure", false, "herbivore", 0.8)
	var fauna := [_beast(1, "Hadrosauridés", "herbivore", "dinosaure")]
	var ctx := _ctx("Mésozoïque", -66_000_000.0, fauna, [dino])
	ctx["mode"] = lens.update(ctx)
	if not ctx["mode"]["real"]:
		return "fin du Crétacé jugée divergente"
	var kinds := {}
	for i in 30:
		var line := chron.ambient(ctx)
		kinds[line["kind"]] = true
		if line.get("world_mode") != "réel":
			return "mode non transmis : %s" % str(line)
	if not kinds.has("fact"):
		return "aucun fait réel raconté dans un monde réel : %s" % str(kinds)
	if kinds.has("invention"):
		return "invention dans un monde réel"
	ctx = _ctx("Cénozoïque", -60_000_000.0, fauna, [dino])
	ctx["mode"] = lens.update(ctx)
	if ctx["mode"]["real"] or not ctx["mode"]["just_diverged"] or not "dinosaurs_survived" in ctx["mode"]["criteria"]:
		return "bascule non détectée : %s" % str(ctx["mode"])
	var first := chron.ambient(ctx)
	if first["kind"] != "divergence" or not str(first["text"]).contains("dinosaures"):
		return "bascule non annoncée : %s" % str(first)
	kinds = {}
	for i in 40:
		ctx = _ctx("Cénozoïque", -60_000_000.0 + i * 1000.0, fauna, [dino])
		ctx["mode"] = lens.update(ctx)
		if ctx["mode"]["just_diverged"]:
			return "bascule annoncée deux fois"
		var line := chron.ambient(ctx)
		kinds[line["kind"]] = true
		var err := _check_line(str(line["text"]))
		if err != "":
			return err
	if kinds.has("fact"):
		return "fait réel raconté dans un monde divergent"
	if not kinds.has("invention"):
		return "aucune invention dans un monde divergent : %s" % str(kinds)
	# Définitif : même si les dinosaures disparaissent ensuite.
	ctx = _ctx("Cénozoïque", -50_000_000.0, [], [])
	if lens.update(ctx)["real"]:
		return "la divergence doit être définitive"
	return ""


# --- Invention et mémoire --------------------------------------------------------

func test_memoire_civilisation_stable() -> String:
	var inv := Inventor.new(11)
	var sauriens := _species(5, "Sauriens", "dinosaure", true, "carnivore", 0.7)
	var ctx := _ctx("Antiquité", -60_000_000.0, [_beast(5, "Sauriens", "sapient", "dinosaure")], [sauriens], 35.0)
	ctx["divine"] = [{"type": "meteor"}, {"type": "bless"}]
	ctx["mode"] = {"real": false, "label": "divergent", "reasons": ["une espèce intelligente non humaine est apparue"]}
	var p := inv.profile_for(sauriens, ctx)
	var frozen := str(p)
	if p["deity"] != Inventor.DEITY_NAMES["meteor"]:
		return "le nom donné à Dieu devrait venir du premier geste (météore) : %s" % p["deity"]
	for k in ["endonym", "place_name", "deity", "customs", "behaviors"]:
		if not p.has(k) or str(p[k]) == "":
			return "profil incomplet (%s) : %s" % [k, frozen]
	# Le contexte change (climat, ère, nouveaux gestes) : la mémoire, elle, ne bouge pas.
	var later := _ctx("Moyen Âge", -50_000_000.0, [_beast(5, "Sauriens", "sapient", "dinosaure")], [sauriens], -5.0)
	later["divine"] = [{"type": "plague"}]
	later["mode"] = ctx["mode"]
	for i in 40:
		var line := inv.line(later)
		var err := _check_line(str(line.get("text", "")))
		if err != "":
			return err
		var text := str(line["text"])
		var quoted := text.find("« ")
		if quoted >= 0:
			var name := text.substr(quoted + 2, text.find(" »", quoted) - quoted - 2)
			if not name in [p["endonym"], p["place_name"], p["deity"]]:
				return "nom inventé hors mémoire « %s » : %s" % [name, text]
	if str(inv.profile_for(sauriens, later)) != frozen:
		return "profil modifié par le nouveau contexte"
	var twin := Inventor.new(11)
	if str(twin.profile_for(sauriens, ctx)) != frozen:
		return "même graine, peuple inventé différemment"
	var other := Inventor.new(12)
	if other.profile_for(sauriens, ctx)["endonym"] == p["endonym"] and other.profile_for(sauriens, ctx)["customs"] == p["customs"]:
		return "la graine n'a aucun effet sur l'invention"
	return ""


func test_invention_tous_clades_et_accords() -> String:
	var inv := Inventor.new(3)
	var id := 0
	for clade in Inventor.PHONEMES.keys() + ["inconnu"]:
		for diet in ["herbivore", "carnivore", "omnivore"]:
			for sapient in [true, false]:
				for n in PLURAL_NAMES + SINGULAR_NAMES:
					id += 1
					var sp := _species(id, n, clade, sapient, diet, 0.2 + 0.1 * (id % 7))
					var ctx := _ctx("Cyberpunk", 2300.0, [_beast(id, n, "sapient" if sapient else diet, clade)], [sp], [-10.0, 18.0, 35.0][id % 3])
					ctx["mode"] = {"real": false, "label": "divergent", "reasons": ["le monde a dépassé notre présent"]}
					for i in 4:
						var line := inv.line(ctx)
						var t := str(line.get("text", ""))
						var err := _check_line(t)
						if err != "":
							return "%s/%s/%s : %s" % [clade, diet, n, err]
						var plural: bool = Procedural.species_phrase(n)["plural"]
						for bad in (["ont appris", "t'appellent", "se nomment", "travaillent", "passent leurs"] if not plural else ["a appris", "t'appelle ", "se nomme ", "travaille ", "passe ses"]):
							if t.contains(bad):
								return "accord faux « %s » (%s) : %s" % [bad, n, t]
	return ""


func test_enrichissement_llm_valide() -> String:
	var inv := Inventor.new(1)
	var sp := _species(9, "Aviens", "oiseau", true)
	var p := inv.profile_for(sp, _ctx("Antiquité", -40_000_000.0))
	var endonym: String = p["endonym"]
	if inv.enrich_from_llm(9, "pas du json") or inv.enrich_from_llm(9, "{\"coutumes\": []}") or inv.enrich_from_llm(77, "{\"coutumes\": [\"on danse sous la pluie chaque matin\"]}"):
		return "réponse invalide acceptée"
	if not inv.enrich_from_llm(9, "Voici : {\"coutumes\": [\"On danse sous la pluie chaque matin.\", \"x\"], \"croyance\": \"le vent porte les âmes des anciens\"}"):
		return "réponse valide refusée"
	if not "on danse sous la pluie chaque matin" in p["llm_customs"] or "x" in p["llm_customs"]:
		return "coutumes mal filtrées : %s" % str(p["llm_customs"])
	if p["endonym"] != endonym or not p.has("llm_croyance"):
		return "l'enrichissement doit compléter la mémoire sans la réécrire"
	return ""


## Intégration : sans météore, les dinosaures survivent au Crétacé et le narrateur bascule vers l'invention.
func test_divergence_simulation_reelle() -> String:
	var WorldSim: GDScript = load("res://src/sim/world_sim.gd")
	var sim: RefCounted = WorldSim.new(77)
	var lens := Divergence.new()
	var chron := Chronicle.new(5)
	var guard := 0
	while sim.year <= -64_900_000.0 and guard < 2000:
		guard += 1
		sim.step(sim.ideal_step_years() * sim.max_substeps)
	var species := []
	for id in sim.species:
		var s: Dictionary = sim.species[id]
		species.append({"id": id, "name": s.name, "alive": s.alive, "sapient": s.sapient, "clade": s.traits.clade,
			"diet": s.traits.diet, "size": s.traits.size, "aggression": s.traits.aggression})
	var ctx := _ctx(sim.current_era(), sim.year, [], species)
	ctx["mode"] = lens.update(ctx)
	var dinos_alive := species.any(func(s): return s.alive and s.clade in Divergence.NON_AVIAN_CLADES)
	if sim.year > Divergence.DINOSAUR_CUTOFF and dinos_alive and ctx["mode"]["real"]:
		return "dinosaures vivants en %d sans divergence" % int(sim.year)
	for i in 10:
		var err := _check_line(str(chron.ambient(ctx)["text"]))
		if err != "":
			return err
		ctx["mode"] = lens.update(ctx)
	return ""


# --- Le personnage -----------------------------------------------------------------

func test_personnage_defini_a_un_seul_endroit() -> String:
	var name := AiConfig.NARRATOR_NAME
	if name == "" or AiConfig.PERSONA.get("name") != name:
		return "nom du narrateur absent de la persona"
	for s in [Prompts.narration_system(), Prompts.parcel_system(), Prompts.ambient_system()]:
		if not s.contains(name):
			return "prompt sans le nom du narrateur : " + s.substr(0, 80)
	for dir_path in ["res://src/ai", "res://src/ai/facts"]:
		for file in DirAccess.get_files_at(dir_path):
			if not file.ends_with(".gd") or file == "ai_config.gd":
				continue
			var text := FileAccess.get_file_as_string(dir_path + "/" + file)
			if text.contains(name):
				return "nom du narrateur codé en dur dans %s/%s" % [dir_path, file]
	return ""
