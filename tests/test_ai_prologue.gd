extends RefCounted
## Tests du prologue : faits vrais datés, étapes, décors (repli, sans LLM).
## Chaque test renvoie "" si OK, sinon un message.

const FactBase := preload("res://src/ai/facts/fact_base.gd")
const Procedural := preload("res://src/ai/procedural_narrator.gd")
const ParcelNarrator := preload("res://src/ai/parcel_narrator.gd")

const CELL := Vector2i(12, 34)
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
