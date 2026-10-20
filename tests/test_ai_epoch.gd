extends RefCounted
## Tests du zéro anachronisme (epoch.gd) dans tout ce que le narrateur écrit (repli, sans LLM).
## Chaque test renvoie "" si OK, sinon un message.

const Epoch := preload("res://src/ai/epoch.gd")
const Prompts := preload("res://src/ai/prompt_builder.gd")
const Procedural := preload("res://src/ai/procedural_narrator.gd")
const ParcelNarrator := preload("res://src/ai/parcel_narrator.gd")
const Chronicle := preload("res://src/ai/chronicle.gd")
const Inventor := preload("res://src/ai/inventor.gd")

const CELL := Vector2i(5, 6)


## Tests de l'adversaire (adversary.gd) et du zéro anachronisme (epoch.gd) dans tout ce que l'IA écrit.
## Mode repli uniquement : aucun LLM. Chaque test renvoie "" si OK, sinon un message.
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
