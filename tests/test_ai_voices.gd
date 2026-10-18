extends RefCounted
## Tests de l'adversaire (adversary.gd) et du zéro anachronisme (epoch.gd) dans tout ce que l'IA écrit.
## Mode repli uniquement : aucun LLM. Chaque test renvoie "" si OK, sinon un message.

const AiConfig := preload("res://src/ai/ai_config.gd")
const Epoch := preload("res://src/ai/epoch.gd")
const Adversary := preload("res://src/ai/adversary.gd")
const Prompts := preload("res://src/ai/prompt_builder.gd")
const Procedural := preload("res://src/ai/procedural_narrator.gd")
const ParcelNarrator := preload("res://src/ai/parcel_narrator.gd")
const Chronicle := preload("res://src/ai/chronicle.gd")
const Inventor := preload("res://src/ai/inventor.gd")
const GameMaster := preload("res://src/ai/game_master.gd")

const CELL := Vector2i(5, 6)
const KINDS := ["reveal", "strike", "taunt_hook"]


## Un contexte dont l'époque effective (Epoch.current) vaut `epoch`.
func _ctx_at(epoch: int) -> Dictionary:
	var ctx := {"divine": [], "choices": [], "species": [], "snapshot": {"cell": CELL, "biome": "Forêt tempérée",
		"land_use": "wild", "temperature_c": 18.0, "global_temperature_c": 15.0, "structures": {}, "fauna": []}}
	var fauna := []
	if epoch >= Epoch.FIRST_SAPIENT:
		ctx["era"] = Epoch.NAMES[epoch]
		ctx["year"] = 1000.0
		ctx["species"] = [{"id": 1, "name": "Humains", "clade": "primate", "sapient": true, "alive": true, "diet": "omnivore",
			"size": 0.4, "aggression": 0.5, "tech_level": float(epoch - Epoch.FIRST_SAPIENT) + 0.5, "parent": -1},
			{"id": 2, "name": "Aurochs", "clade": "mammifère", "sapient": false, "alive": true, "diet": "herbivore", "size": 0.6}]
		fauna = [{"species_id": 1, "name": "Humains", "role": "sapient", "count": 9, "trend": 0, "clade": "primate"},
			{"species_id": 2, "name": "Aurochs", "role": "herbivore", "count": 6, "trend": -1, "clade": "mammifère"}]
		ctx["snapshot"]["land_use"] = "village"
	elif epoch >= Epoch.MESOZOIC:
		ctx["era"] = Epoch.NAMES[epoch]
		ctx["year"] = -100_000_000.0 if epoch == Epoch.MESOZOIC else -10_000_000.0
		ctx["species"] = [{"id": 3, "name": "Hadrosauridés", "clade": "dinosaure", "sapient": false, "alive": true, "diet": "herbivore", "size": 0.8}]
		fauna = [{"species_id": 3, "name": "Hadrosauridés", "role": "herbivore", "count": 7, "trend": 1, "clade": "dinosaure"}]
	else:
		ctx["era"] = "Prologue"
		ctx["year"] = float(Epoch.STAGES[epoch][1]) + 1_000_000.0
		ctx["species"] = [{"id": 4, "name": "Cyanobactéries", "clade": "microbe", "sapient": false, "alive": true, "diet": "herbivore", "size": 0.05},
			{"id": 5, "name": "Prédateurs unicellulaires", "clade": "microbe", "sapient": false, "alive": true, "diet": "carnivore", "size": 0.05}]
		fauna = [{"species_id": 4, "name": "Cyanobactéries", "role": "herbivore", "count": 30, "trend": 1, "clade": "microbe"},
			{"species_id": 5, "name": "Prédateurs unicellulaires", "role": "carnivore", "count": 12, "trend": 0, "clade": "microbe"}]
		ctx["snapshot"]["land_use"] = "ocean"
	ctx["snapshot"]["fauna"] = fauna
	ctx["snapshot"]["year"] = ctx["year"]
	return ctx


static func _sentences(t: String) -> int:
	var n := 0
	for i in t.length():
		if t[i] in [".", "!", "?", "…"] and (i + 1 == t.length() or t[i + 1] == " "):
			n += 1
	return n


func test_epoque_effective() -> String:
	for e in range(Epoch.LAST + 1):
		var got := Epoch.current(_ctx_at(e))
		if got != e:
			return "époque %d (%s) lue comme %d" % [e, Epoch.NAMES[e], got]
	# Monde divergent : le niveau technologique réel compte, pas la date du calendrier.
	var saur := {"era": "Préhistoire", "year": -40_000_000.0, "species": [{"sapient": true, "alive": true, "tech_level": 5.2}]}
	if Epoch.current(saur) != Epoch.INFORMATION:
		return "civilisation non humaine à -40 Ma : la technologie réelle devrait compter"
	if Epoch.current({"era": "Moderne", "year": 2020.0, "species": []}) > Epoch.CENOZOIC:
		return "sans espèce intelligente, pas d'époque technologique"
	return ""


# --- L'adversaire -----------------------------------------------------------------

func test_adversaire_repond_a_chaque_reason_code() -> String:
	var adv := Adversary.new(7)
	for code in Adversary.REASON_CODES + ["code_inconnu", ""]:
		for kind in KINDS:
			for epoch in [0, 7, 10, 14, 16]:
				var line := adv.move_line({"kind": kind, "reason_code": code, "threat": {"title": "Sécheresse"}}, epoch)
				var t := str(line.get("text", ""))
				if t.length() < 10 or t.contains("{") or _sentences(t) < 1 or _sentences(t) > 3:
					return "%s/%s (%d) : réplique mal formée : %s" % [kind, code, epoch, t]
				if line.get("speaker") != AiConfig.ADVERSARY_NAME:
					return "orateur manquant : %s" % str(line)
				if not Epoch.is_clean(t, epoch):
					return "%s/%s : anachronisme à l'époque %d : %s" % [kind, code, epoch, t]
				if kind == "reveal" and code in Adversary.REASON_CODES and not t.contains("Sécheresse"):
					return "révélation sans la menace (%s) : %s" % [code, t]
	return ""


func test_adversaire_depit_habitudes_et_echanges() -> String:
	var adv := Adversary.new(2)
	var spite := adv.spite_line({"title": "Épidémie"}, 10)
	var habit := adv.habit_line({"power": "flood", "count": 3}, 10)
	var taunt := adv.round_taunt({"index": 2, "threats": [{}, {}, {}]}, 4, 10)
	for l in [spite, habit, taunt]:
		if str(l["text"]).length() < 10 or l["speaker"] != AiConfig.ADVERSARY_NAME:
			return "réplique invalide : %s" % str(l)
	if not str(habit["text"]).contains("le déluge"):
		return "habitude non nommée : " + str(habit["text"])
	var to_n := adv.exchange_line(true, 10)
	var from_n := adv.exchange_line(false, 10)
	if to_n["speaker"] != AiConfig.ADVERSARY_NAME or from_n["speaker"] != AiConfig.NARRATOR_NAME:
		return "orateurs de l'échange inversés"
	var seen := 0
	for r in 50:
		if adv.wants_exchange(r):
			seen += 1
	if seen == 0 or seen == 50:
		return "l'échange devrait avoir lieu parfois, pas toujours (%d/50)" % seen
	return ""


func test_adversaire_deterministe() -> String:
	var run := func(s: int) -> PackedStringArray:
		var adv := Adversary.new(s)
		var out := PackedStringArray()
		for code in Adversary.REASON_CODES:
			for kind in KINDS:
				out.append(adv.move_line({"kind": kind, "reason_code": code, "threat": {"title": "Glaciation"}}, 12)["text"])
		out.append(adv.spite_line({"title": "Glaciation"}, 12)["text"])
		out.append(adv.round_taunt({"threats": []}, 3, 12)["text"])
		return out
	var a: PackedStringArray = run.call(11)
	if a != run.call(11):
		return "même graine, répliques différentes"
	if a == run.call(12):
		return "la graine n'a aucun effet"
	return ""


## Chaque réplique est propre à partir de l'époque où elle est permise (sinon son min_era est faux).
func test_aucune_replique_anachronique() -> String:
	for l in Adversary.all_lines():
		var text := Adversary.render(l, {"menace": "Sécheresse"})
		var e := int(l.get("min_era", 0))
		if not Epoch.is_clean(text, e):
			return "réplique permise dès l'époque %d mais anachronique : %s (%s)" % [e, text, str(Epoch.violations(text, e))]
	var adv := Adversary.new(4)
	for e in range(Epoch.LAST + 1):
		for i in 6:
			for l in [adv.round_taunt({"threats": [{}]}, 2, e), adv.spite_line({}, e), adv.habit_line({"power": "bless"}, e),
					adv.exchange_line(i % 2 == 0, e), adv.move_line({"kind": "taunt_hook"}, e)]:
				if not Epoch.is_clean(str(l["text"]), e):
					return "époque %d : %s" % [e, l["text"]]
	return ""


# --- Zéro anachronisme --------------------------------------------------------------

func test_filtre_rejette_texte_llm_anachronique() -> String:
	var bad := "Les Humains confient la décision à une IA, qui calcule tout sur ses ordinateurs."
	if Prompts.vet_output(bad, 2, Epoch.ANTIQUITY) != "":
		return "texte LLM anachronique accepté en Antiquité"
	if Prompts.vet_output(bad, 2, Epoch.CYBERPUNK) == "":
		return "texte légitime refusé à l'ère cyberpunk"
	for case in [["Les dinosaures broutent sous un ciel lourd.", Epoch.ARCHEAN], ["La famine ravage le village.", Epoch.CENOZOIC],
			["Les usines crachent leur fumée.", Epoch.RENAISSANCE], ["Un troupeau traverse la plaine.", Epoch.ARCHEAN]]:
		if Prompts.vet_output(case[0], 2, case[1]) != "":
			return "anachronisme accepté (%s) : %s" % [Epoch.NAMES[case[1]], case[0]]
	var rules := Prompts.epoch_rules(Epoch.ANTIQUITY)
	for needle in ["Antiquité", "INTERDIT", "IA", "ordinateur", "électricité"]:
		if not rules.contains(needle):
			return "consigne d'époque sans « %s » : %s" % [needle, rules]
	if Prompts.epoch_rules(Epoch.LAST).contains("INTERDIT"):
		return "rien ne devrait être interdit à la dernière ère"
	var d := {"id": 1, "title": "Le choix", "text": "Deux phrases ici. Que fais-tu ?", "timeout_s": 30.0, "speaker": "x",
		"options": [{"label": "Bénir", "hint": "Peut-être.", "action": {"type": "bless", "region": CELL, "species_id": 1, "radius": 4}},
			{"label": "Ne rien faire", "hint": "Rien.", "action": {}}]}
	var merged := Prompts.merge_dilemma_text(d, JSON.stringify({"title": "Le conseil des IA",
		"text": "Confie la décision à une IA. Elle saura mieux que toi.", "options": [{"label": "Demander à l'ordinateur", "hint": "Il calcule."}, {"label": "x", "hint": "y"}]}), Epoch.MIDDLE_AGES)
	if str(merged).contains("IA") or str(merged).contains("ordinateur"):
		return "dilemme LLM anachronique fusionné : %s" % str(merged)
	return ""


func test_aucune_option_de_dilemme_anachronique() -> String:
	var gm := GameMaster.new(5)
	for e in range(Epoch.LAST + 1):
		var ctx := _ctx_at(e)
		for kind in GameMaster.TRIGGERS:
			var trig := {"kind": kind, "species_id": 1 if e >= Epoch.FIRST_SAPIENT else int(ctx["species"][0]["id"]),
				"species_name": str(ctx["species"][0]["name"]), "region": CELL, "summary": "", "hot": true}
			if not GameMaster.allowed_now(trig, ctx):
				continue
			var d := gm.build(trig, ctx)
			if int(d.get("min_era", 0)) > e or int(d.get("max_era", Epoch.LAST)) < e:
				return "%s à l'époque %d hors de ses bornes" % [kind, e]
			var all := PackedStringArray([str(d["title"]), str(d["text"])])
			for o in d["options"]:
				all.append(str(o["label"]))
				all.append(str(o["hint"]))
			for s in all:
				if not Epoch.is_clean(s, e):
					return "%s (%s) : anachronisme %s dans « %s »" % [kind, Epoch.NAMES[e], str(Epoch.violations(s, e)), s]
	for e in range(Epoch.ANTIQUITY):
		if GameMaster.allowed_now({"kind": "war"}, _ctx_at(e)):
			return "dilemme de guerre permis avant l'Antiquité (%s)" % Epoch.NAMES[e]
	for e in range(Epoch.INFORMATION):
		if GameMaster.allowed_now({"kind": "strong_ai"}, _ctx_at(e)):
			return "dilemme d'IA permis avant l'âge de l'information (%s)" % Epoch.NAMES[e]
	for e in range(Epoch.LAST + 1):
		if GameMaster.allowed_now({"kind": "meteor_decision"}, _ctx_at(e)) != (e == Epoch.MESOZOIC):
			return "météore permis à la mauvaise époque (%s)" % Epoch.NAMES[e]
	return ""


func test_aucun_fait_ni_gabarit_anachronique() -> String:
	var pn := ParcelNarrator.new(3)
	var gen := Procedural.new(5)
	for e in range(Epoch.LAST + 1):
		var ctx := _ctx_at(e)
		var chron := Chronicle.new(e + 1)
		for i in 15:
			var line := chron.ambient(ctx)
			var t := str(line["text"])
			if line["kind"] == "fact":
				var stage := str(line["fact_id"]).split("#")[0]
				var se := Epoch.index_of(stage)
				if se != e:
					return "fait d'une autre époque (%s) à l'époque %s" % [line["fact_id"], Epoch.NAMES[e]]
			elif not Epoch.is_clean(t, e):
				return "fil (%s, %s) : %s %s" % [Epoch.NAMES[e], line["kind"], t, str(Epoch.violations(t, e))]
		for lu in ParcelNarrator.LAND_USES:
			for kind in ["land_use", "arrival", "departure", "extinction", "heat", "cold", "focus"]:
				for role in ["herbivore", "carnivore", "sapient"]:
					var m := {"kind": kind, "land_use": lu, "from": "wild", "first": true, "role": role, "species_id": 4,
						"species_name": str(ctx["species"][0]["name"]), "delta_c": 6.0, "temperature_c": 25.0, "snapshot": ctx["snapshot"]}
					var t := pn.narrate(m, ctx["era"], ctx["year"], e)
					if not Epoch.is_clean(t, e):
						return "parcelle (%s, %s, %s) : %s" % [Epoch.NAMES[e], kind, lu, t]
		for etype in Procedural.EVENT_TYPES:
			var t := gen.narrate({"type": etype, "era": ctx["era"], "year": ctx["year"], "epoch": e, "species_name": str(ctx["species"][0]["name"])})
			if not Epoch.is_clean(t, e):
				return "monde (%s, %s) : %s %s" % [Epoch.NAMES[e], etype, t, str(Epoch.violations(t, e))]
		var inv := Inventor.new(e)
		var dctx := ctx.duplicate(true)
		dctx["mode"] = {"real": false, "label": "divergent", "reasons": ["le monde a pris un autre chemin"]}
		for i in 8:
			var l := inv.line(dctx)
			if not l.is_empty() and not Epoch.is_clean(str(l["text"]), e):
				return "invention (%s) : %s" % [Epoch.NAMES[e], l["text"]]
	return ""


func test_noms_definis_a_un_seul_endroit() -> String:
	for name in [AiConfig.NARRATOR_NAME, AiConfig.ADVERSARY_NAME]:
		for dir_path in ["res://src/ai", "res://src/ai/facts"]:
			for file in DirAccess.get_files_at(dir_path):
				if file.ends_with(".gd") and file != "ai_config.gd" and FileAccess.get_file_as_string(dir_path + "/" + file).contains(name):
					return "« %s » codé en dur dans %s/%s" % [name, dir_path, file]
	if not Prompts.adversary_system().contains(AiConfig.ADVERSARY_NAME):
		return "persona de l'adversaire absente du prompt"
	return ""
