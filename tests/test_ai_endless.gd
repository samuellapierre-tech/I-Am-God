extends RefCounted
## Tests du futur sans fin, de la mémoire bornée et de la variété sur la durée.
## Mode repli uniquement : aucun LLM. Chaque test renvoie "" si OK, sinon un message.

const AiConfig := preload("res://src/ai/ai_config.gd")
const Epoch := preload("res://src/ai/epoch.gd")
const Variety := preload("res://src/ai/variety.gd")
const Inventor := preload("res://src/ai/inventor.gd")
const Chronicle := preload("res://src/ai/chronicle.gd")
const ParcelNarrator := preload("res://src/ai/parcel_narrator.gd")
const Procedural := preload("res://src/ai/procedural_narrator.gd")

## Aucun texte identique à moins de N lignes d'écart, sur 10 000 narrations simulées.
const N := 50
const SIMULATED := 10_000

const CELL := Vector2i(3, 4)


static func _sentences(t: String) -> int:
	var n := 0
	for i in t.length():
		if t[i] in [".", "!", "?", "…"] and (i + 1 == t.length() or t[i + 1] == " "):
			n += 1
	return n


func _sp(id: int, name: String, clade: String, sapient: bool, tech := 0.0, alive := true) -> Dictionary:
	return {"id": id, "name": name, "clade": clade, "sapient": sapient, "alive": alive, "diet": "omnivore",
		"size": 0.4, "aggression": 0.5, "tech_level": tech, "parent": -1}


func _ctx(era: String, year: float, species: Array, land_use := "wild", divergent := true) -> Dictionary:
	var fauna := []
	for s in species:
		if bool(s.get("alive", true)):
			fauna.append({"species_id": s["id"], "name": s["name"], "role": "sapient" if s["sapient"] else "herbivore",
				"count": 5 + int(s["id"]) % 9, "trend": int(s["id"]) % 3 - 1, "clade": s["clade"]})
	var ctx := {"era": era, "year": year, "species": species, "divine": [], "recent_events": [],
		"snapshot": {"cell": CELL, "year": year, "biome": "Forêt tempérée", "land_use": land_use, "temperature_c": 17.0,
			"global_temperature_c": 15.0, "structures": {}, "fauna": fauna}}
	if divergent:
		ctx["mode"] = {"real": false, "label": "divergent", "reasons": ["le monde a dépassé notre présent"]}
	return ctx


# --- Futur sans fin ------------------------------------------------------------------

## Une civilisation tombe ; une autre naît sur ses ruines et le narrateur s'en souvient, de façon cohérente.
func test_civilisations_successives() -> String:
	var inv := Inventor.new(9)
	var sauriens := _sp(1, "Sauriens", "dinosaure", true, 7.8)
	var ctx := _ctx("Post-singularité", 50_000.0, [sauriens])
	ctx["divine"] = [{"type": "bless"}]
	var a := inv.profile_for(sauriens, ctx)
	var a_endonym: String = a["endonym"]
	var a_deity: String = a["deity"]
	inv.line(ctx)
	# Effondrement : les Sauriens s'éteignent, les Aviens s'éveillent sur leurs ruines.
	var dead := sauriens.duplicate()
	dead["alive"] = false
	var aviens := _sp(2, "Aviens", "oiseau", true, 0.5)
	var later := _ctx("Préhistoire", 900_000.0, [dead, aviens], "ruins")
	inv.observe(later)
	if inv.fallen.is_empty() or inv.fallen[-1]["endonym"] != a_endonym:
		return "la chute des Sauriens n'est pas mémorisée : %s" % str(inv.fallen)
	var b := inv.profile_for(aviens, later)
	var h: Dictionary = b.get("heritage", {})
	if h.get("name") != "Sauriens" or h.get("endonym") != a_endonym:
		return "la nouvelle lignée devrait hériter du souvenir des Sauriens : %s" % str(b)
	if b["deity"] != a_deity and b["deity"] == a_deity:
		return "incohérence du nom divin"
	var mentions := false
	for i in 60:
		var l := inv.line(later)
		if l.is_empty():
			continue
		var t := str(l["text"])
		if t.contains("Sauriens") or t.contains(a_endonym):
			mentions = true
		var q := t.find("« ")
		if q >= 0:
			var nm := t.substr(q + 2, t.find(" »", q) - q - 2)
			if not nm in [b["endonym"], b["place_name"], b["deity"], a_endonym, a_deity]:
				return "nom hors mémoire « %s » : %s" % [nm, t]
	if not mentions:
		return "le narrateur ne se souvient jamais des Sauriens sur leurs ruines"
	if str(inv.profile_for(sauriens, later)["endonym"]) != a_endonym:
		return "le souvenir d'une civilisation tombée a changé"
	return ""


func test_visions_du_futur() -> String:
	var inv := Inventor.new(4)
	var old := _sp(1, "Sauriens", "dinosaure", true, 8.0)
	var ctx := _ctx("Post-singularité", 40_000.0, [old])
	inv.profile_for(old, ctx)
	var kinds := {}
	for i in 30:
		var v := inv.vision(ctx)
		if not v.is_empty():
			kinds[str(v["text"]).substr(0, 20)] = true
			if not Epoch.is_clean(str(v["text"]), Epoch.LAST) or str(v["text"]).contains("{"):
				return "vision incorrecte : " + str(v["text"])
	if kinds.is_empty():
		return "aucune vision à l'ère post-singularité"
	var dead := old.duplicate()
	dead["alive"] = false
	var far := _ctx("Cénozoïque", 400_000_000.0, [dead], "rewild")
	inv.observe(far)
	var sun := false
	var memory := false
	for i in 60:
		var v := inv.vision(far)
		if v.is_empty():
			continue
		var t := str(v["text"])
		if t.contains("Soleil"):
			sun = true
		if t.contains("Sauriens"):
			memory = true
	if not (sun and memory):
		return "futur lointain : Soleil qui vieillit (%s) et souvenir des anciens (%s) attendus" % [sun, memory]
	if not Procedural.format_year(400_000_000.0).begins_with("dans "):
		return "date du futur lointain : " + Procedural.format_year(400_000_000.0)
	return ""


func test_memoire_des_cultures_bornee() -> String:
	var inv := Inventor.new(1)
	var ctx := _ctx("Moderne", 2000.0, [])
	var first := inv.profile_for(_sp(0, "Peuple zéro", "primate", true, 5.0), ctx)
	var first_endonym: String = first["endonym"]
	for i in range(1, 300):
		inv.profile_for(_sp(i, "Peuple %d" % i, ["primate", "oiseau", "dinosaure", "insecte"][i % 4], true, 5.0), ctx)
	if inv.profiles.size() > Inventor.MAX_PROFILES:
		return "profils non bornés : %d" % inv.profiles.size()
	if inv.archive.size() > Inventor.MAX_ARCHIVE or inv.forgotten <= 0:
		return "archive non bornée (%d) ou oubli non compté (%d)" % [inv.archive.size(), inv.forgotten]
	for s in inv.archive:
		if s.has("behaviors") or (s.has("customs") and (s["customs"] as Array).size() > 1):
			return "l'archive devrait résumer les profils : %s" % str(s)
	# Un peuple récemment archivé revient avec les noms qu'on lui avait donnés.
	var archived: Dictionary = inv.archive[-1]
	var back := inv.profile_for(_sp(int(archived["id"]), str(archived["name"]), str(archived["clade"]), true, 5.0), ctx)
	if back["endonym"] != archived["endonym"] or back["deity"] != archived["deity"]:
		return "peuple archivé revenu sous d'autres noms"
	if inv.profiles.has(0) and inv.profiles[0]["endonym"] != first_endonym:
		return "profil modifié"
	return ""


# --- Variété ---------------------------------------------------------------------------

func test_variete_memoire_et_rotation() -> String:
	var v := Variety.new(3)
	for t in ["a", "b", "c"]:
		if not v.accept(t):
			return "texte neuf refusé"
	if v.accept("a"):
		return "texte récent accepté"
	v.remember("d")
	if v.seen("a") or not v.seen("d") or v.size() != 3:
		return "mémoire non bornée à 3"
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var o: Array = v.order("f", 4, rng)
	v.used("f", o[0])
	v.used("f", o[1])
	var o2: Array = v.order("f", 4, rng)
	if o2[2] != o[0] or o2[3] != o[1] or not (o2[0] in [o[2], o[3]]):
		return "rotation : les moins récemment utilisés d'abord (%s puis %s)" % [str(o), str(o2)]
	return ""


## 10 000 narrations simulées (fil, parcelle, monde) avec une mémoire partagée :
## aucun texte identique à moins de N lignes d'écart, et le fil ne se tait pas trop.
func test_aucune_repetition_sur_10000_narrations() -> String:
	var variety := Variety.new(200)
	var chron := Chronicle.new(21)
	chron.variety = variety
	var pn := ParcelNarrator.new(22)
	pn.variety = variety
	var gen := Procedural.new(23)
	gen.variety = variety
	var contexts := [
		_ctx("Mésozoïque", -80_000_000.0, [_sp(1, "Hadrosauridés", "dinosaure", false), _sp(2, "Tyrannosauridés", "dinosaure", false)], "wild", false),
		_ctx("Cénozoïque", -20_000_000.0, [_sp(3, "Multituberculés", "mammifère", false), _sp(4, "Ornithurés", "oiseau", false)], "wild", false),
		_ctx("Antiquité", -500.0, [_sp(5, "Humains", "primate", true, 1.3), _sp(6, "Aurochs", "mammifère", false)], "town", false),
		_ctx("Préhistoire", -30_000_000.0, [_sp(7, "Sauriens", "dinosaure", true, 0.5), _sp(1, "Hadrosauridés", "dinosaure", false)], "camp"),
		_ctx("Cyberpunk", 2300.0, [_sp(5, "Humains", "primate", true, 6.4)], "megacity"),
		_ctx("Post-singularité", 80_000.0, [_sp(8, "Aviens", "oiseau", true, 7.9)], "arcology"),
	]
	var out := PackedStringArray()
	var last_seen := {}
	for i in SIMULATED:
		# On reste longtemps dans le même monde (comme une vraie partie), puis on change d'âge.
		var ctx: Dictionary = contexts[(i / 1700) % contexts.size()]
		var text := ""
		match i % 5:
			0, 1:
				text = str(chron.ambient(ctx).get("text", ""))
			2:
				var f: Array = ctx["snapshot"]["fauna"]
				var m := {"kind": ["arrival", "departure", "heat", "cold", "land_use"][(i / 5) % 5], "land_use": ["village", "wild", "farmland", "ruins"][(i / 25) % 4],
					"from": "wild", "first": (i / 5) % 7 == 0, "role": "herbivore", "species_id": int(f[0]["species_id"]),
					"species_name": str(f[0]["name"]), "delta_c": 5.0, "temperature_c": 20.0, "snapshot": ctx["snapshot"]}
				text = pn.narrate(m, ctx["era"], ctx["year"], Epoch.current(ctx))
			3:
				text = gen.narrate({"type": Procedural.EVENT_TYPES[(i / 5) % Procedural.EVENT_TYPES.size()], "era": ctx["era"],
					"year": ctx["year"], "epoch": Epoch.current(ctx)})
			4:
				text = str(chron.ambient(ctx).get("text", ""))
		if text == "":
			continue
		var k := out.size()
		if last_seen.has(text) and k - int(last_seen[text]) < N:
			return "« %s » répété à %d lignes d'écart (narration %d)" % [text, k - int(last_seen[text]), i]
		last_seen[text] = k
		out.append(text)
	if out.size() < SIMULATED / 4:
		return "le fil se tait trop souvent : %d lignes sur %d" % [out.size(), SIMULATED]
	print("    %d narrations simulées -> %d lignes dites, aucune répétée à moins de %d lignes" % [SIMULATED, out.size(), N])
	return ""
