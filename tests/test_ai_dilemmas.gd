extends RefCounted
## Tests du narrateur maître du jeu (game_master.gd) : dilemmes, cadence, délai, mémoire, déterminisme.
## Mode repli uniquement : aucun LLM. Chaque test renvoie "" si OK, sinon un message.

const AiConfig := preload("res://src/ai/ai_config.gd")
const GameMaster := preload("res://src/ai/game_master.gd")
const Chronicle := preload("res://src/ai/chronicle.gd")
const Prompts := preload("res://src/ai/prompt_builder.gd")

const CELL := Vector2i(70, 40)


func _ctx() -> Dictionary:
	return {
		"era": "Antiquité", "year": -500.0, "divine": [], "choices": [],
		"species": [
			{"id": 1, "name": "Humains", "clade": "primate", "sapient": true, "alive": true, "diet": "omnivore", "intelligence": 0.9, "parent": 4},
			{"id": 2, "name": "Sauriens", "clade": "dinosaure", "sapient": true, "alive": true, "diet": "carnivore", "intelligence": 0.85, "parent": -1},
			{"id": 3, "name": "Hadrosauridés", "clade": "dinosaure", "sapient": false, "alive": true, "diet": "herbivore", "intelligence": 0.2, "parent": -1},
			{"id": 4, "name": "Plésiadapiformes", "clade": "primate", "sapient": false, "alive": false, "diet": "omnivore", "intelligence": 0.4, "parent": -1},
			{"id": 5, "name": "Verpha moloum", "clade": "reptile", "sapient": false, "alive": true, "diet": "carnivore", "intelligence": 0.3, "parent": -1},
		],
		"snapshot": {"cell": CELL, "year": -500.0, "biome": "Savane", "land_use": "village", "temperature_c": 31.0,
			"global_temperature_c": 18.0, "structures": {}, "fauna": [
				{"species_id": 1, "name": "Humains", "role": "sapient", "count": 12, "trend": 0, "clade": "primate"},
				{"species_id": 3, "name": "Hadrosauridés", "role": "herbivore", "count": 8, "trend": -1, "clade": "dinosaure"},
				{"species_id": 5, "name": "Verpha moloum", "role": "carnivore", "count": 4, "trend": 1, "clade": "reptile"},
			]},
	}


## Un déclencheur de chaque type, construit comme le fait le narrateur.
func _all_triggers(ctx: Dictionary) -> Array:
	return [
		GameMaster.meteor_trigger(ctx),
		GameMaster.trigger_from_event({"type": "sapience", "species_id": 2, "summary": "Éveil : les Troodontidés accèdent à la conscience — naissance des Sauriens"}, ctx),
		GameMaster.trigger_from_event({"type": "parcel_land_use", "land_use": "city", "first": true}, ctx),
		GameMaster.trigger_from_event({"type": "war", "species_id": 1, "summary": "Guerre : les Humains affrontent les Sauriens"}, ctx),
		GameMaster.trigger_from_event({"type": "parcel_heat", "delta_c": 9.0}, ctx),
		GameMaster.trigger_from_event({"type": "volcanism", "summary": "Supervolcan : une éruption colossale obscurcit le ciel"}, ctx),
		GameMaster.trigger_from_event({"type": "discovery", "species_id": 1, "summary": "Les Humains éveillent une IA générale"}, ctx),
		GameMaster.trigger_from_alert({"kind": "population_collapse", "species_id": 3, "severity": 0.8, "summary": "Les Hadrosauridés s'effondrent"}, ctx),
		GameMaster.trigger_from_alert({"kind": "cold_snap", "severity": 0.7, "summary": "Le froid gagne"}, ctx),
		GameMaster.trigger_from_alert({"kind": "famine", "severity": 0.9, "summary": "Les greniers sont vides"}, ctx),
		GameMaster.trigger_from_alert({"kind": "mystère", "severity": 0.6, "summary": "Les oiseaux se taisent"}, ctx),
		GameMaster.trigger_from_prayer({"id": 1, "name": "Humains"}, {"type": "war", "enemy": "les Sauriens", "enemy_id": 2}, ctx),
		GameMaster.trigger_from_prayer({"id": 1, "name": "Humains"}, {"type": "famine"}, ctx),
	]


static func _sentences(t: String) -> int:
	var n := 0
	for i in t.length():
		if t[i] in [".", "!", "?", "…"] and (i + 1 == t.length() or t[i + 1] == " "):
			n += 1
	return n


func test_chaque_declencheur_produit_un_dilemme_valide() -> String:
	var ctx := _ctx()
	var kinds := {}
	var gm := GameMaster.new(1)
	gm.meteor_delay = 0.0  # pas de délai de début de partie dans ce test
	for trig in _all_triggers(ctx):
		if trig.is_empty():
			return "déclencheur non reconnu (voir _all_triggers)"
		kinds[trig["kind"]] = true
		var d := gm.build(trig, ctx)
		var err := GameMaster.validate(d)
		if err != "":
			return "%s : %s" % [trig["kind"], err]
		if d["speaker"] != AiConfig.NARRATOR_NAME:
			return "orateur manquant"
		var n := _sentences(str(d["text"]))
		if n < 2 or n > 4:
			return "%s : %d phrases de mise en scène : %s" % [trig["kind"], n, d["text"]]
		for bad in ["{", "[", " de les ", "  "]:
			if str(d["text"]).contains(bad) or str(d["title"]).contains(bad):
				return "%s : « %s » dans %s" % [trig["kind"], bad, d["text"]]
		var nothing := GameMaster.nothing_index(d)
		if nothing < 0 or d["options"][nothing]["label"] != GameMaster.NOTHING_LABEL:
			return "%s : pas d'option « Ne rien faire »" % trig["kind"]
		for o in d["options"]:
			var a: Dictionary = o["action"]
			if not a.is_empty() and a["region"] != CELL:
				return "%s : action hors de la parcelle : %s" % [trig["kind"], str(a)]
			if str(o["hint"]) == "":
				return "%s : indice vide" % trig["kind"]
	for k in GameMaster.TRIGGERS:
		# Les grands choix du prologue sont couverts par tests/test_ai_strategy.gd.
		if not kinds.has(k) and not k in GameMaster.PROLOGUE_TRIGGERS:
			return "type de déclencheur non couvert : " + k
	var weak := GameMaster.trigger_from_alert({"kind": "famine", "severity": 0.2}, ctx)
	if not weak.is_empty():
		return "alerte faible retenue"
	return ""


## Les options suivent les règles du déclencheur (le LLM ne les choisit jamais).
func test_options_par_regles() -> String:
	var ctx := _ctx()
	var collapse := GameMaster.option_specs(GameMaster.trigger_from_alert({"kind": "decline", "species_id": 3, "severity": 0.9}, ctx), ctx)
	if collapse != [["save", 3], ["plague", 5], ["", -1]]:
		return "effondrement : sauver / peste sur le prédateur / rien attendu : %s" % str(collapse)
	var war := GameMaster.option_specs(GameMaster.trigger_from_event({"type": "war", "species_id": 1, "summary": "Guerre : les Humains affrontent les Sauriens"}, ctx), ctx)
	if war[0] != ["save", 2] or war[-1] != ["", -1]:
		return "guerre : protéger l'adversaire attendu : %s" % str(war)
	var meteor := GameMaster.option_specs(GameMaster.meteor_trigger(ctx), ctx)
	if meteor[0][0] != "meteor":
		return "fin du Crétacé : lancer le météore attendu : %s" % str(meteor)
	var no_species := GameMaster.option_specs({"kind": "species_collapse", "species_id": -1}, ctx)
	for s in no_species:
		if str(s[0]) in ["save", "plague", "uplift", "extinct"] and int(s[1]) < 0:
			return "action ciblée sans espèce : %s" % str(no_species)
	return ""


func test_cadence_un_seul_dilemme_a_la_fois() -> String:
	var ctx := _ctx()
	var gm := GameMaster.new(2)
	gm.meteor_delay = 0.0  # pas de délai de début de partie dans ce test
	gm.min_interval = 180.0
	gm.consider(GameMaster.trigger_from_event({"type": "sapience", "species_id": 2}, ctx))
	gm.consider(GameMaster.trigger_from_alert({"kind": "famine", "severity": 0.9}, ctx))
	var r := gm.tick(1.0)
	if not r.has("open") or r["open"]["kind"] != "first_sapient":
		return "le déclencheur prioritaire devrait s'ouvrir : %s" % str(r)
	var d := gm.open_dilemma(r["open"], ctx)
	if d.is_empty():
		return "dilemme non ouvert"
	for i in 400:
		r = gm.tick(1.0)
		if r.has("open"):
			return "deux dilemmes à la fois"
	if not gm.resolve(int(d["id"]), 0, false, ctx)["ok"]:
		return "résolution refusée"
	r = gm.tick(1.0)
	if r.has("open"):
		# Ouvert il y a 402 s (> 180 s) : la famine, encore en file, peut sortir… si elle n'a pas expiré.
		if r["open"]["kind"] != "famine":
			return "déclencheur inattendu : %s" % str(r)
	# Nouveau déclencheur juste après une ouverture : il doit attendre min_interval.
	var gm2 := GameMaster.new(3)
	gm2.meteor_delay = 0.0  # pas de délai de début de partie dans ce test
	gm2.min_interval = 180.0
	gm2.consider(GameMaster.trigger_from_alert({"kind": "decline", "species_id": 3, "severity": 0.9}, ctx))
	var o := gm2.tick(1.0)
	var d2 := gm2.open_dilemma(o["open"], ctx)
	gm2.resolve(int(d2["id"]), 1, false, ctx)
	gm2.consider(GameMaster.trigger_from_alert({"kind": "famine", "severity": 0.9}, ctx))
	for i in 170:
		if gm2.tick(1.0).has("open"):
			return "dilemme rouvert avant min_interval (%d s)" % (i + 2)
	var opened := false
	for i in 20:
		if gm2.tick(1.0).has("open"):
			opened = true
			break
	if not opened:
		return "dilemme jamais rouvert après min_interval"
	# Les déclencheurs uniques ne reviennent pas.
	if gm.consider(GameMaster.trigger_from_event({"type": "sapience", "species_id": 2}, ctx)):
		return "première sapience proposée deux fois"
	return ""


func test_sans_reponse_ne_rien_faire() -> String:
	var ctx := _ctx()
	var gm := GameMaster.new(4)
	gm.meteor_delay = 0.0  # pas de délai de début de partie dans ce test
	gm.timeout_s = 30.0
	gm.consider(GameMaster.meteor_trigger(ctx))
	var d := gm.open_dilemma(gm.tick(1.0)["open"], ctx)
	for i in 100:
		if gm.tick(1.0).has("timeout"):
			return "délai écoulé avant l'affichage"
	gm.mark_shown(int(d["id"]))
	var r := {}
	for i in 40:
		r = gm.tick(1.0)
		if r.has("timeout"):
			break
		if i < 28 and r.has("timeout"):
			return "délai trop court"
	if not r.has("timeout"):
		return "aucun délai écoulé"
	var idx := int(r["timeout"]["option_index"])
	if idx != GameMaster.nothing_index(d):
		return "le délai doit choisir « Ne rien faire »"
	var res := gm.resolve(int(d["id"]), idx, true, ctx)
	if not res["ok"] or not (res["action"] as Dictionary).is_empty() or not res["record"]["timed_out"]:
		return "résolution par délai incorrecte : %s" % str(res)
	if not gm.active.is_empty():
		return "dilemme encore ouvert"
	if gm.resolve(int(d["id"]), 0, false, ctx)["ok"]:
		return "un dilemme fermé ne doit pas être tranché deux fois"
	return ""


func test_choix_memorises_et_rappeles() -> String:
	var ctx := _ctx()
	var gm := GameMaster.new(5)
	gm.meteor_delay = 0.0  # pas de délai de début de partie dans ce test
	gm.min_interval = 0.0
	gm.consider(GameMaster.trigger_from_alert({"kind": "decline", "species_id": 4, "severity": 0.9}, ctx))
	var d := gm.open_dilemma(gm.tick(1.0)["open"], ctx)
	var res := gm.resolve(int(d["id"]), 0, false, ctx)
	if res["action"]["type"] != "save" or not str(res["text"]).contains("Plésiadapiformes"):
		return "choix mal raconté : %s" % str(res)
	if gm.choices.size() != 1 or gm.choices[0]["action_type"] != "save":
		return "choix non mémorisé"
	# Plus tard, un dilemme sur leurs descendants (Humains, parent 4) rappelle ce choix.
	ctx["choices"] = gm.choices.duplicate()
	var later := gm.build(GameMaster.trigger_from_event({"type": "parcel_land_use", "land_use": "city", "first": true}, ctx), ctx)
	if not str(later["text"]).contains("Souviens-toi : tu avais protégé leurs ancêtres, les Plésiadapiformes"):
		return "rappel du choix absent : " + str(later["text"])
	var line := GameMaster.memory_line(gm.choices[0])
	if not line.begins_with("Je n'oublie rien : à l'Antiquité, tu avais protégé les Plésiadapiformes"):
		return "phrase de mémoire inattendue : " + line
	var chron := Chronicle.new(3)
	var seen := false
	for i in 80:
		var amb := chron.ambient(ctx)
		if amb["kind"] == "memory":
			seen = true
			break
	return "" if seen else "le fil ne rappelle jamais les choix passés"


func test_determinisme_dilemmes() -> String:
	var ctx := _ctx()
	var a := GameMaster.new(42)
	var b := GameMaster.new(42)
	for trig in _all_triggers(ctx):
		if str(a.build(trig, ctx)) != str(b.build(trig, ctx)):
			return "même graine, dilemme différent (%s)" % trig["kind"]
	var c := GameMaster.new(43)
	var differs := false
	for trig in _all_triggers(ctx):
		if str(GameMaster.new(42).build(trig, ctx)) != str(c.build(trig, ctx)):
			differs = true
	return "" if differs else "la graine n'a aucun effet"


## Le premier choix de la partie est celui du météore : aucun autre dilemme ne s'ouvre avant.
func test_rien_avant_le_meteore() -> String:
	var ctx := _ctx()
	var gm := GameMaster.new(9)
	gm.meteor_delay = 5.0
	gm.consider(GameMaster.trigger_from_alert({"kind": "famine", "severity": 0.9}, ctx))
	for i in 5:
		if gm.tick(1.0).has("open"):
			return "dilemme ouvert avant la décision du météore (%d s)" % (i + 1)
	gm.consider(GameMaster.meteor_trigger(ctx))
	var r := gm.tick(1.0)
	if not r.has("open") or r["open"]["kind"] != "meteor_decision":
		return "le météore devrait passer en premier : %s" % str(r)
	return ""


func test_meteore_propose_seulement_au_cretace() -> String:
	var ctx := _ctx()
	ctx["era"] = "Mésozoïque"
	if not GameMaster.meteor_due(ctx, 10.0, 5.0):
		return "météore non proposé à la fin du Crétacé"
	if GameMaster.meteor_due(ctx, 1.0, 5.0):
		return "météore proposé trop tôt"
	ctx["divine"] = [{"type": "meteor"}]
	if GameMaster.meteor_due(ctx, 10.0, 5.0):
		return "météore proposé alors qu'il est déjà tombé"
	ctx["divine"] = []
	ctx["era"] = "Cénozoïque"
	if GameMaster.meteor_due(ctx, 10.0, 5.0):
		return "météore proposé après le Crétacé"
	return ""


## Le LLM ne réécrit que les textes : options, actions et « Ne rien faire » restent ceux des règles.
func test_fusion_texte_llm() -> String:
	var ctx := _ctx()
	var d := GameMaster.new(6).build(GameMaster.trigger_from_alert({"kind": "decline", "species_id": 3, "severity": 0.9}, ctx), ctx)
	var raw := JSON.stringify({"title": "Les géants tombent", "text": "Les hadrosaures déclinent. Leurs troupeaux fondent. Que fais-tu ?",
		"options": [{"label": "Les sauver", "hint": "Peut-être."}, {"label": "Frapper le prédateur", "hint": "Qui sait."}, {"label": "Laisser faire", "hint": "Le monde suit sa pente."}]})
	var m := Prompts.merge_dilemma_text(d, raw)
	if m["title"] != "Les géants tombent" or m["options"][0]["label"] != "Les sauver":
		return "texte du LLM ignoré : %s" % str(m)
	if m["options"][-1]["label"] != GameMaster.NOTHING_LABEL:
		return "« Ne rien faire » réécrit"
	if str(m["options"][0]["action"]) != str(d["options"][0]["action"]) or GameMaster.validate(m) != "":
		return "actions modifiées par le LLM"
	var bad := Prompts.merge_dilemma_text(d, "{\"title\": \"x\", \"text\": \"Une seule phrase.\", \"options\": [{\"label\": \"a\"}]}")
	if bad["text"] != d["text"] or bad["options"][0]["label"] != d["options"][0]["label"]:
		return "réponse invalide fusionnée : %s" % str(bad)
	if str(Prompts.merge_dilemma_text(d, "n'importe quoi")) != str(d):
		return "réponse non JSON fusionnée"
	return ""
