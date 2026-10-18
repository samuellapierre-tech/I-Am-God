extends RefCounted
## Tests du prologue (faits, étapes, dilemmes) et de la mise en scène de la stratégie par le narrateur.
## Mode repli uniquement : aucun LLM. Chaque test renvoie "" si OK, sinon un message.

const Procedural := preload("res://src/ai/procedural_narrator.gd")
const FactBase := preload("res://src/ai/facts/fact_base.gd")
const ParcelNarrator := preload("res://src/ai/parcel_narrator.gd")
const GameMaster := preload("res://src/ai/game_master.gd")
const Divergence := preload("res://src/ai/divergence.gd")
const StrategyNarrator := preload("res://src/ai/strategy_narrator.gd")

const CELL := Vector2i(12, 34)
## Une date par étape du prologue (et de l'acte I) et le minimum de faits vrais attendus à cette date.
const STAGE_DATES := {
	"Archéen": [-3_800_000_000.0, 15], "Grande Oxydation": [-1_000_000_000.0, 15],
	"Terre boule de neige": [-700_000_000.0, 8], "Explosion cambrienne": [-430_000_000.0, 10],
	"Sortie des eaux": [-370_000_000.0, 12], "Carbonifère": [-300_000_000.0, 14],
	"Grande Mourance": [-252_000_000.0, 15], "Trias": [-210_000_000.0, 12], "Jurassique": [-150_000_000.0, 15],
}
const NEW_CLADES := ["microbe", "algue", "éponge", "arthropode", "mollusque", "poisson", "plante", "amphibien",
	"insecte", "synapside", "reptile"]


static func _sentences(t: String) -> int:
	var n := 0
	for i in t.length():
		if t[i] in [".", "!", "?", "…"] and (i + 1 == t.length() or t[i + 1] == " "):
			n += 1
	return n


func _ctx() -> Dictionary:
	var fauna := []
	var species := []
	var defs := [
		[10, "Trilobites", "arthropode", "herbivore"], [11, "Nautiloïdes", "mollusque", "carnivore"],
		[12, "Placodermes", "poisson", "carnivore"], [13, "Méganeures", "insecte", "carnivore"],
		[14, "Archaeopteris", "plante", "herbivore"], [15, "Gorgonopsiens", "synapside", "carnivore"],
		[16, "Archosaures", "reptile", "carnivore"], [17, "Cyanobactéries", "microbe", "herbivore"],
	]
	for d in defs:
		fauna.append({"species_id": d[0], "name": d[1], "role": d[3], "count": 20 - int(d[0]) % 7, "trend": 0, "clade": d[2]})
		species.append({"id": d[0], "name": d[1], "clade": d[2], "sapient": false, "alive": true, "diet": d[3], "intelligence": 0.1, "parent": -1})
	return {"era": "Prologue", "year": -400_000_000.0, "divine": [], "choices": [], "species": species,
		"snapshot": {"cell": CELL, "year": -400_000_000.0, "biome": "Océan", "land_use": "ocean", "temperature_c": 26.0,
			"global_temperature_c": 22.0, "structures": {}, "fauna": fauna}}


# --- Faits du prologue ---------------------------------------------------------

func test_faits_du_prologue() -> String:
	for stage in FactBase.PROLOGUE + ["Trias", "Jurassique"]:
		var facts := FactBase.era_facts(stage)
		if facts.size() < 15:
			return "%s : seulement %d faits" % [stage, facts.size()]
		for f in facts:
			var t := str(f["t"])
			if t.length() < 20 or t.contains("{") or _sentences(t) < 1 or _sentences(t) > 2:
				return "%s : fait mal formé : %s" % [stage, t]
			if not f.has("min_year") or not f.has("max_year") or float(f["min_year"]) > float(f["max_year"]):
				return "%s : fenêtre de dates absente ou inversée : %s" % [stage, f["id"]]
		var year: float = STAGE_DATES[stage][0]
		var n := FactBase.candidates(stage, year).size()
		if n < int(STAGE_DATES[stage][1]):
			return "%s en %d : seulement %d faits vrais" % [stage, int(year), n]
	var seen := {}
	for stage in FactBase.REAL_ERAS:
		for f in FactBase.era_facts(stage):
			for c in f.get("clade", []):
				seen[c] = true
	for c in NEW_CLADES:
		if not seen.has(c):
			return "aucun fait sur le clade « %s »" % c
	# Le tyrannosaure n'est pas raconté au Trias.
	for f in FactBase.candidates("Mésozoïque", -230_000_000.0):
		return "fait de la fin du Crétacé vrai au Trias : " + str(f["t"])
	return ""


func test_etapes_datees() -> String:
	var cases := [
		["Prologue", -3_800_000_000.0, "Archéen"], ["?", -2_000_000_000.0, "Grande Oxydation"],
		["?", -700_000_000.0, "Terre boule de neige"], ["?", -500_000_000.0, "Explosion cambrienne"],
		["?", -380_000_000.0, "Sortie des eaux"], ["?", -300_000_000.0, "Carbonifère"],
		["?", -255_000_000.0, "Grande Mourance"], ["Mésozoïque", -230_000_000.0, "Trias"],
		["Mésozoïque", -170_000_000.0, "Jurassique"], ["Mésozoïque", -68_000_000.0, "Mésozoïque"],
		["Cénozoïque", -10_000_000.0, "Cénozoïque"], ["Moderne", 2000.0, "Moderne"], ["Antiquité", null, "Antiquité"],
	]
	for c in cases:
		var got := FactBase.stage_for(c[0], c[1])
		if got != c[2]:
			return "%s en %s : « %s » au lieu de « %s »" % [c[0], str(c[1]), got, c[2]]
	if ParcelNarrator.lexicon_key("?", -3_000_000_000.0) != "Précambrien" or ParcelNarrator.lexicon_key("?", -300_000_000.0) != "Paléozoïque" \
			or ParcelNarrator.lexicon_key("Mésozoïque", -200_000_000.0) != "Mésozoïque":
		return "décor du prologue mal choisi"
	for y in [[-3_800_000_000.0, "il y a 3,8 milliards d'années"], [-1_000_000_000.0, "il y a 1 milliard d'années"]]:
		if Procedural.format_year(y[0]) != y[1]:
			return "date : %s au lieu de %s" % [Procedural.format_year(y[0]), y[1]]
	return ""


## Le fil du prologue raconte des faits vrais, avec le bon décor, sans rien de non résolu.
func test_fil_du_prologue() -> String:
	var Chronicle: GDScript = load("res://src/ai/chronicle.gd")
	var chron: RefCounted = Chronicle.new(8)
	var facts := 0
	for stage in STAGE_DATES:
		var ctx := _ctx()
		ctx["year"] = STAGE_DATES[stage][0]
		ctx["snapshot"]["year"] = ctx["year"]
		for i in 10:
			var line: Dictionary = chron.ambient(ctx)
			var t := str(line["text"])
			if t.contains("{") or t.contains("[") or _sentences(t) < 1 or _sentences(t) > 2:
				return "%s : ligne incorrecte : %s" % [stage, t]
			if line["kind"] == "fact":
				facts += 1
				if not str(line["fact_id"]).begins_with(stage + "#"):
					return "%s : fait d'une autre étape (%s)" % [stage, line["fact_id"]]
	return "" if facts > 20 else "trop peu de faits racontés au prologue : %d" % facts


# --- Dilemmes du prologue --------------------------------------------------------

func test_dilemmes_du_prologue() -> String:
	var ctx := _ctx()
	var gm := GameMaster.new(3)
	for stage in GameMaster.STAGE_TRIGGERS:
		var trig := GameMaster.stage_trigger(stage, ctx)
		if trig.is_empty() or trig["kind"] != GameMaster.STAGE_TRIGGERS[stage]:
			return "%s : déclencheur absent" % stage
		var d := gm.build(trig, ctx)
		var err := GameMaster.validate(d)
		if err != "":
			return "%s : %s" % [stage, err]
		var n := _sentences(str(d["text"]))
		if n < 2 or n > 4:
			return "%s : %d phrases : %s" % [stage, n, d["text"]]
		for o in d["options"]:
			var a: Dictionary = o["action"]
			if not a.is_empty() and a["region"] != CELL:
				return "%s : action hors de la parcelle" % stage
			for bad in ["{", "[", " de les "]:
				if str(o["label"]).contains(bad) or str(o["hint"]).contains(bad):
					return "%s : libellé non résolu : %s" % [stage, o["label"]]
	if GameMaster.stage_trigger("Trias", ctx) != {}:
		return "le Trias n'a pas de grand choix"
	var origin := GameMaster.option_specs(GameMaster.stage_trigger("Archéen", ctx), ctx)
	if origin != [["spawn_species", -1, "hydrothermal"], ["spawn_species", -1, "tidal_pool"], ["", -1]]:
		return "origine de la vie : source chaude / mare côtière / rien attendu : %s" % str(origin)
	var cambrian := GameMaster.option_specs(GameMaster.stage_trigger("Explosion cambrienne", ctx), ctx)
	if cambrian != [["bless", 10, "favor"], ["bless", 11, "favor"], ["bless", 12, "favor"], ["", -1]]:
		return "Cambrien : arthropodes / mollusques / poissons attendus : %s" % str(cambrian)
	var dying := GameMaster.option_specs(GameMaster.stage_trigger("Grande Mourance", ctx), ctx)
	if dying != [["ice_age", -1, "prevent"], ["save", 15], ["save", 16], ["", -1]]:
		return "Grande Mourance : empêcher / synapsides / reptiles attendus : %s" % str(dying)
	return ""


## Un choix du prologue est raconté, mémorisé et, s'il contredit l'histoire, fait diverger le monde.
func test_choix_du_prologue_et_divergence() -> String:
	var ctx := _ctx()
	var gm := GameMaster.new(4)
	gm.meteor_delay = 0.0
	gm.min_interval = 0.0
	gm.consider(GameMaster.stage_trigger("Grande Mourance", ctx))
	var d := gm.open_dilemma(gm.tick(1.0)["open"], ctx)
	var res := gm.resolve(int(d["id"]), 0, false, ctx)
	if res["action"].get("variant") != "prevent" or not str(res["text"]).contains("empêché la Grande Mourance"):
		return "choix mal raconté : %s" % str(res)
	var line := GameMaster.memory_line(gm.choices[0])
	if not line.contains("tu avais empêché la Grande Mourance"):
		return "souvenir inattendu : " + line
	var assess_ctx := {"era": "Trias", "year": -240_000_000.0, "species": [], "choices": gm.choices}
	if not "no_great_dying" in Divergence.assess(assess_ctx):
		return "empêcher la Grande Mourance devrait faire diverger le monde"
	for v in ["hydrothermal", "tidal_pool", "warm", "favor", "first_ashore", "dry"]:
		var c := {"era": "?", "year": -400_000_000.0, "species": [], "choices": [{"trigger": "x", "variant": v, "action_type": "bless"}]}
		if not Divergence.assess(c).is_empty():
			return "le choix « %s » ne contredit pas l'histoire réelle" % v
	if not "anaerobic_world" in Divergence.assess({"year": -2e9, "choices": [{"variant": "slow_oxygen"}]}):
		return "freiner l'oxygène devrait faire diverger le monde"
	# Le météore n'est proposé qu'à la fin du Crétacé, plus au Trias.
	if GameMaster.meteor_due({"era": "Mésozoïque", "year": -230_000_000.0}, 60.0, 5.0):
		return "météore proposé au Trias"
	if not GameMaster.meteor_due({"era": "Mésozoïque", "year": -67_000_000.0}, 60.0, 5.0):
		return "météore non proposé à la fin du Crétacé"
	return ""


# --- Stratégie -------------------------------------------------------------------

func test_annonce_de_manche() -> String:
	var rd := {"index": 3, "name": "Explosion cambrienne", "threats": [
		{"id": 1, "title": "Anoxie des mers"}, {"id": 2, "title": "Glaciation"}, {"id": 3, "title": "Prédateurs invasifs"}]}
	var t := StrategyNarrator.round_line(rd, 4)
	for needle in ["Manche 3 : Explosion cambrienne.", "3 menaces se lèvent : Anoxie des mers, Glaciation et Prédateurs invasifs.", "Tu disposes de 4 actions."]:
		if not t.contains(needle):
			return "annonce sans « %s » : %s" % [needle, t]
	var one := StrategyNarrator.round_line({"index": 1, "name": "Archéen", "threats": [{"title": "Volcanisme"}]}, 1)
	if not (one.contains("Une menace se lève : Volcanisme.") and one.contains("1 action.")):
		return "annonce d'une menace : " + one
	var none := StrategyNarrator.round_line({"index": 2, "name": "Trias", "threats": []})
	if none.contains("action") or not none.contains("aucune menace"):
		return "manche sans menace ni budget connu : " + none
	return ""


func test_menaces_racontees_sans_invention() -> String:
	var threat := {"id": 7, "title": "Sécheresse", "strikes_year": -399_000_000.0, "counters": ["flood", "bless", "flood"]}
	var t := StrategyNarrator.threat_line(threat, -400_000_000.0)
	if not (t.contains("Nouvelle menace : Sécheresse, qui frappera dans environ 1 million d'années.") and t.contains("un déluge ou une bénédiction")):
		return "menace mal racontée : " + t
	var bare := StrategyNarrator.threat_line({"title": "Épidémie"})
	if bare.contains("contre") or bare.contains("frappera"):
		return "correspondance ou date inventée : " + bare
	var hit := StrategyNarrator.resolved_line({"title": "La sécheresse"}, false, "Trilobites")
	if not hit.contains("Rien ne l'a arrêtée : la sécheresse frappe les Trilobites."):
		return "menace qui frappe : " + hit
	var saved := StrategyNarrator.resolved_line({"title": "Sécheresse"}, true)
	if not saved.begins_with("Contrée : Sécheresse."):
		return "menace contrée : " + saved
	return ""


func test_pistes_et_alarmes() -> String:
	var base := {"collapses": 5, "collapse_limit": 8, "vitality": 0.6, "works": {"life": false, "land": false, "mind": false, "legacy": false}, "deck_left": 10}
	if not StrategyNarrator.tracks_lines(base, base).is_empty():
		return "rien n'a changé, rien ne doit être dit"
	var after := base.duplicate(true)
	after["collapses"] = 6
	var l := StrategyNarrator.tracks_lines(base, after)
	if l.size() != 1 or not str(l[0]).contains("6 sur 8") or not str(l[0]).contains("Encore 2"):
		return "alarme des effondrements : %s" % str(l)
	var before7 := after.duplicate(true)
	after["collapses"] = 7
	if not str(StrategyNarrator.tracks_lines(before7, after)[0]).contains("Un seul de plus"):
		return "dernier avertissement absent"
	if not str(StrategyNarrator.tracks_lines(base, after)[0]).begins_with("2 effondrements en chaîne de plus : 7 sur 8."):
		return "saut de deux effondrements mal dit : %s" % str(StrategyNarrator.tracks_lines(base, after))
	var v := base.duplicate(true)
	v["vitality"] = 0.25
	if not str(StrategyNarrator.tracks_lines(base, v)[0]).contains("25 %"):
		return "vitalité non signalée"
	var w := base.duplicate(true)
	w["works"]["life"] = true
	if not str(StrategyNarrator.tracks_lines(base, w)[0]).contains("Grand Œuvre accompli : Vie complexe. 1 sur 4."):
		return "Grand Œuvre non célébré : %s" % str(StrategyNarrator.tracks_lines(base, w))
	var deck := base.duplicate(true)
	deck["deck_left"] = 3
	var dl := StrategyNarrator.tracks_lines(base, deck)
	if dl.is_empty() or not str(dl[0]).contains("plus que 3 menaces"):
		return "sablier non signalé : %s" % str(dl)
	return ""


func test_epilogues() -> String:
	var memory := "Je n'oublie rien : au Mésozoïque, tu avais lancé la pierre."
	var win := StrategyNarrator.epilogue(true, "Les quatre œuvres sont scellées", memory)
	var lose := StrategyNarrator.epilogue(false, "Effondrements en chaîne : 8 sur 8")
	for t in [win, lose]:
		var n := _sentences(t)
		if n < 2 or n > 4 or t.contains("{"):
			return "épilogue mal formé (%d phrases) : %s" % [n, t]
	if not (win.contains("Grands Œuvres") and win.contains("tu avais lancé la pierre")):
		return "épilogue de victoire : " + win
	if not lose.begins_with("Effondrements en chaîne : 8 sur 8."):
		return "épilogue de défaite : " + lose
	return ""
