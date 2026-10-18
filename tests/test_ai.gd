extends RefCounted
## Tests de la couche IA (aucun réseau requis).

const AiConfig := preload("res://src/ai/ai_config.gd")
const LlmClient := preload("res://src/ai/llm_client.gd")
const Procedural := preload("res://src/ai/procedural_narrator.gd")
const Prompts := preload("res://src/ai/prompt_builder.gd")
const DecisionSchema := preload("res://src/ai/decision_schema.gd")
const NarratorScript := preload("res://src/ai/narrator.gd")
const ParcelNarrator := preload("res://src/ai/parcel_narrator.gd")

const TEST_CFG := "user://test_ai_settings.cfg"


# --- Construction des prompts -------------------------------------------------

func test_prompt_narration_contient_le_contexte() -> String:
	var p := Prompts.build_narration_prompt({
		"era": "Antiquité", "year": -500.0,
		"events": [{"type": "war", "species_name": "Humains", "summary": "Sparte attaque Athènes"}],
		"action": {"type": "plague", "species_id": 2, "region": Vector2i(3, 4)},
	})
	for needle in ["Antiquité", "avant notre ère", "Sparte attaque Athènes", "Humains", "épidémie", "1 à 3 phrases"]:
		if not p.contains(needle):
			return "prompt sans « %s » : %s" % [needle, p]
	return ""


func test_prompt_narration_contexte_vide() -> String:
	var p := Prompts.build_narration_prompt({})
	return "" if p.length() > 20 else "prompt vide"


func test_persona_francais_et_court() -> String:
	var s := Prompts.narration_system()
	if not (s.contains("français") and s.contains("1 à 3 phrases") and s.contains("Dieu")):
		return "persona incomplète"
	return ""


func test_prompt_oracle_et_priere() -> String:
	var o := Prompts.build_oracle_prompt("Et si je sauvais les dinosaures ?", {
		"years": 1_000_000.0, "era": "Cénozoïque", "extinctions": ["Tyrannosaure"],
		"events": [{"summary": "Les sauriens dominent encore"}],
	})
	if not (o.contains("dinosaures") and o.contains("Tyrannosaure") and o.contains("sauriens")):
		return "prompt oracle incomplet : " + o
	var p := Prompts.build_prayer_prompt({"id": 4, "name": "Sylvains", "traits": ["pieux"]}, {"type": "famine", "era": "Moyen Âge"})
	if not (p.contains("Sylvains") and p.contains("famine") and p.contains("Moyen Âge") and p.contains("pieux")):
		return "prompt prière incomplet : " + p
	var d := Prompts.build_decision_prompt({"species_id": 4, "region": Vector2i(1, 2)})
	if not (d.contains("[1,2]") and d.contains("JSON")):
		return "prompt décision incomplet : " + d
	return ""


func test_nettoyage_sortie_llm() -> String:
	var raw := "<think>je réfléchis</think>\n« Seigneur, la mer monte. Les cités tombent. Les hommes prient. Puis tout se tait. »"
	var out := Prompts.sanitize_output(raw, 3)
	if out.contains("think") or out.contains("réfléchis"):
		return "balise think non retirée : " + out
	if out.begins_with("«") or out.contains("Puis tout"):
		return "guillemets ou 4e phrase non retirés : " + out
	if not out.ends_with("prient."):
		return "coupe inattendue : " + out
	return ""


# --- Repli procédural ---------------------------------------------------------

func test_repli_non_vide_pour_chaque_ere_et_type() -> String:
	var gen := Procedural.new(42)
	var eras: Array = Procedural.ERAS + ["ère inconnue", ""]
	for era in eras:
		for etype in Procedural.EVENT_TYPES + ["type_inconnu"]:
			for _i in 3:
				var t := gen.narrate({"type": etype, "era": era, "year": -66_000_000.0, "species_id": 1})
				if t.strip_edges().length() < 10:
					return "narration vide pour %s / %s" % [era, etype]
				if t.contains("{") or t.contains("}"):
					return "emplacement non rempli (%s / %s) : %s" % [era, etype, t]
	return ""


func test_repli_lot_evenements() -> String:
	var gen := Procedural.new(7)
	var t := gen.narrate({"era": "Moderne", "year": 1969.0, "events": [
		{"type": "discovery", "summary": "Premier pas sur la Lune"}, {"type": "war"}, {"type": "climate"},
	]})
	if t.length() < 20 or not t.contains("2 autres"):
		return "narration de lot inattendue : " + t
	return ""


func test_repli_oracle_et_priere() -> String:
	var gen := Procedural.new(3)
	for proj in [{}, {"summary": "Les machines règnent", "years": 500.0}, {"era": "Cyberpunk", "dominant_species": "Humains"}]:
		var p := gen.prophecy("Que deviendra le monde ?", proj)
		if p.length() < 20 or p.contains("{"):
			return "prophétie invalide : " + p
	for era in Procedural.ERAS:
		for sit in Procedural.PRAYER_SITUATIONS + ["inconnue"]:
			var t := gen.prayer({"id": 1, "name": "Humains"}, {"type": sit, "era": era, "enemy": "les Orques"})
			if t.length() < 20 or t.contains("{"):
				return "prière invalide (%s / %s) : %s" % [era, sit, t]
	var choices := Procedural.prayer_choices({"id": 1}, {"type": "war", "region": Vector2i(5, 5)})
	if choices.size() != 3 or not (choices[0]["action"] is Dictionary) or choices[0]["action"].get("type") != "save":
		return "choix de prière invalides : %s" % str(choices)
	return ""


func test_contractions_francaises() -> String:
	var gen := Procedural.new(11)
	for _i in 30:
		var t := gen.narrate({"type": "extinct", "era": "Moderne", "species_name": "les Raptors"})
		if t.contains(" de les ") or t.contains(" à les "):
			return "contraction manquante : " + t
	return ""


# --- Accord singulier / pluriel (noms d'espèces réels de src/sim) -------------

const PLURAL_NAMES := ["Multituberculés", "Euthériens insectivores", "Crocodyliformes kasaris",
	"les premiers primates", "Humains Mivel", "Tyrannosauridés", "Sauriens"]
const SINGULAR_NAMES := ["Verpha moloum", "Kensar tolumensis", "Raxi", "Squamates nuloa"]


func test_detection_nombre_espece() -> String:
	for n in PLURAL_NAMES:
		var ph := Procedural.species_phrase(n)
		if not ph["plural"] or not ph["text"].to_lower().begins_with("les "):
			return "%s devrait être pluriel : %s" % [n, str(ph)]
	for n in SINGULAR_NAMES:
		var ph := Procedural.species_phrase(n)
		if ph["plural"] or ph["text"] != "l'espèce " + n:
			return "%s devrait être singulier : %s" % [n, str(ph)]
	if Procedural.species_phrase("la lignée des ombres")["plural"]:
		return "article singulier ignoré"
	return ""


## Chaque gabarit, pour chaque nom : les marques d'accord doivent toutes être résolues dans le bon nombre.
func test_accord_tous_gabarits() -> String:
	var gen := Procedural.new(5)
	var re := RegEx.new()
	re.compile("\\[(\\w+):([^|\\]]*)\\|([^\\]]*)\\]")
	for etype in Procedural.EVENT_TEMPLATES:
		for tpl in Procedural.EVENT_TEMPLATES[etype]:
			for n in PLURAL_NAMES + SINGULAR_NAMES:
				for lieu in ["les marais fumants", "la toundra sans fin", "le substrat planétaire"]:
					var plural: bool = Procedural.species_phrase(n)["plural"]
					var t := gen.render(tpl, {"era": "Cénozoïque", "year": -3.0e7, "species_name": n, "lieu": lieu})
					for bad in ["[", "]", "{", "}", " de les ", " à les ", " de le "]:
						if t.contains(bad):
							return "« %s » dans : %s" % [bad, t]
					for m in re.search_all(tpl):
						var is_pl: bool = plural if m.get_string(1) == "espece" else lieu.begins_with("les ")
						var want := m.get_string(3) if is_pl else m.get_string(2)
						var wrong := m.get_string(2) if is_pl else m.get_string(3)
						if not t.contains(want):
							return "accord manquant « %s » (%s, %s) : %s" % [want, n, lieu, t]
						if wrong != want and t.contains(" " + wrong + " ") and not want.contains(wrong):
							return "accord faux « %s » (%s, %s) : %s" % [wrong, n, lieu, t]
	return ""


func test_regression_primates_disparait() -> String:
	var gen := Procedural.new(1)
	for _i in 200:
		var t := gen.narrate({"type": "extinction", "era": "Cénozoïque", "year": -3.0e7})
		for bad in ["primates disparaît", "mammifères disparaît", "coureurs disparaît", "fourrure disparaît", "n'a pas survécu"]:
			if t.contains(bad):
				return "accord faux : " + t
	var t2 := gen.render(Procedural.EVENT_TEMPLATES["extinction"][0], {"era": "Cénozoïque", "species_name": "les premiers primates"})
	if not t2.contains("les premiers primates disparaissent"):
		return "pluriel attendu : " + t2
	var t3 := gen.render(Procedural.EVENT_TEMPLATES["save"][1], {"era": "Moderne", "species_name": "Verpha moloum"})
	if not t3.contains("l'espèce Verpha moloum échappe à la fin, protégée"):
		return "singulier féminin attendu : " + t3
	var t4 := gen.render(Procedural.EVENT_TEMPLATES["save"][1], {"era": "Moderne", "species_name": "Multituberculés"})
	if not t4.contains("les Multituberculés échappent à la fin, protégés"):
		return "pluriel masculin attendu : " + t4
	return ""


## Types et résumés tels que les produit src/sim/world_sim.gd.
func test_evenements_reels_de_la_simulation() -> String:
	var gen := Procedural.new(9)
	var events := [
		{"type": "extinction", "summary": "Extinction : les Titanosaures disparaissent", "species_name": "Titanosaures"},
		{"type": "speciation", "summary": "Spéciation : Verpha moloum se sépare des Plésiadapiformes", "species_name": "Verpha moloum"},
		{"type": "sapience", "summary": "Éveil : les Plésiadapiformes (primate) accèdent à la conscience — naissance des Humains", "species_name": "Humains"},
		{"type": "discovery", "summary": "Les Humains maîtrisent le feu", "species_name": "Humains"},
		{"type": "war", "summary": "Guerre : les Humains affrontent les Sauriens", "species_name": "Humains"},
		{"type": "plague", "summary": "Épidémie : une peste ravage les Humains", "species_name": "Humains"},
		{"type": "golden_age", "summary": "Âge d'or : les Humains connaissent une ère de prospérité", "species_name": "Humains"},
		{"type": "decline", "summary": "Décadence : la prospérité des Humains s'effrite", "species_name": "Humains"},
		{"type": "volcanism", "summary": "Supervolcan : une éruption colossale obscurcit le ciel"},
		{"type": "climate", "summary": "Le ciel s'éclaircit : l'hiver d'impact prend fin"},
		{"type": "ice_age_end", "summary": "Fin de la glaciation : les glaces reculent"},
		{"type": "land_bridge", "summary": "Ponts de glace : les mers basses ouvrent des routes de migration"},
		{"type": "immunity", "summary": "Les Humains survivants développent une immunité", "species_name": "Humains"},
		{"type": "radiation", "summary": "Radiation adaptative : Multituberculés se diversifient", "species_name": "Multituberculés"},
		{"type": "fertile_silt", "summary": "Le limon du déluge fertilise les plaines"},
		{"type": "endemic", "summary": "Les Squamates restent cantonnés à leur berceau (3 régions)", "species_name": "Squamates"},
		{"type": "invasion", "summary": "Invasion : les Squamates ont conquis 40 régions", "species_name": "Squamates"},
		{"type": "era_change", "summary": "Le monde entre dans l'ère : Antiquité (portée par les Humains)"},
		{"type": "impact", "summary": "Impact : un astéroïde creuse un cratère de 900 km et embrase le ciel"},
		{"type": "collapse", "summary": "Âge sombre : l'impact plonge les Humains dans le chaos", "species_name": "Humains"},
		{"type": "lazarus", "summary": "Taxon Lazare : les Ptérosaures reviennent d'entre les morts", "species_name": "Ptérosaures"},
		{"type": "protection", "summary": "Les Ptérosaures sont placés sous protection divine", "species_name": "Ptérosaures"},
		{"type": "blessing", "summary": "Bénédiction : la terre devient luxuriante"},
		{"type": "deluge", "summary": "Déluge : les eaux engloutissent les basses terres"},
		{"type": "spawn", "summary": "Création : Dieu façonne les Raxi", "species_name": "Raxi"},
		{"type": "divine_meteor", "summary": "Dieu : un météore fend le ciel"},
	]
	for e in events:
		for era in ["Mésozoïque", "Antiquité", "Cyberpunk"]:
			var ctx: Dictionary = e.duplicate()
			ctx["era"] = era
			ctx["year"] = -1000.0
			for _i in 4:
				var t := gen.narrate(ctx)
				if t.length() < 20 or t.contains("[") or t.contains("{") or t.contains(" de les "):
					return "rendu incorrect (%s) : %s" % [e["type"], t]
				if t.contains(" les Raxi") or t.contains("les Verpha"):
					return "nom singulier mis au pluriel (%s) : %s" % [e["type"], t]
	if Procedural.event_key("divine_meteor") != "meteor" or Procedural.event_key("impact") != "meteor":
		return "types réels non reconnus"
	var w := gen.narrate({"type": "war", "summary": "Guerre : les Humains affrontent les Sauriens", "era": "Antiquité"})
	if not w.contains("les Humains affrontent les Sauriens"):
		return "le résumé de guerre devrait faire foi : " + w
	return ""


func test_nettoyage_resume() -> String:
	var cases := {
		"Guerre : les Humains affrontent les Sauriens": "les Humains affrontent les Sauriens",
		"Les Humains maîtrisent le feu.": "les Humains maîtrisent le feu",
		"Spéciation : Verpha moloum se sépare des Plésiadapiformes": "Verpha moloum se sépare des Plésiadapiformes",
		"Fin de la glaciation : les glaces reculent": "Fin de la glaciation : les glaces reculent",
	}
	for k in cases:
		if Procedural.clean_summary(k) != cases[k]:
			return "%s -> %s" % [k, Procedural.clean_summary(k)]
	return ""


func test_prophetie_format_project_future() -> String:
	var gen := Procedural.new(2)
	var proj := {
		"from_year": -66_000_000.0, "to_year": -65_000_000.0, "era": "Cénozoïque", "era_reached": "Cénozoïque",
		"dominant_species": {"id": 3, "name": "Multituberculés", "clade": "mammifère"},
		"extinct_species": [{"id": 0, "name": "Tyrannosauridés"}, {"id": 9, "name": "Verpha moloum"}],
		"key_events": [{"summary": "Extinction : les Titanosaures disparaissent"}],
	}
	var v := Procedural.projection_visions(proj)
	var joined := " | ".join(v)
	for needle in ["dans 1 million", "la fin des Tyrannosauridés, de l'espèce Verpha moloum", "les Multituberculés régnant", "les Titanosaures disparaissent"]:
		if not joined.contains(needle):
			return "vision sans « %s » : %s" % [needle, joined]
	var empty_dom := Procedural.projection_visions({"dominant_species": {"id": -1, "name": "", "clade": ""}})
	if not empty_dom.is_empty():
		return "espèce dominante vide racontée : %s" % str(empty_dom)
	var p := gen.prophecy("Et si ?", proj)
	return "" if p.length() > 30 and not p.contains(" de les ") else "prophétie invalide : " + p


## Intégration : narre les vrais événements d'une vraie simulation, noms d'espèces compris.
func test_narration_simulation_reelle() -> String:
	var WorldSim: GDScript = load("res://src/sim/world_sim.gd")
	var sim: RefCounted = WorldSim.new(1234)
	var events: Array = []
	events.append_array(sim.apply_divine_action({"type": "meteor", "region": Vector2i(60, 50), "species_id": -1, "radius": 12}))
	var guard := 0
	while events.size() < 40 and guard < 400:
		guard += 1
		events.append_array(sim.step(sim.ideal_step_years() * sim.max_substeps))
	if events.is_empty():
		return "la simulation n'a produit aucun événement"
	var gen := Procedural.new(4)
	for e in events:
		var ctx: Dictionary = e.duplicate()
		ctx["era"] = sim.current_era()
		var sid := int(e.get("species_id", -1))
		if sid >= 0 and sim.species.has(sid):
			ctx["species_name"] = sim.species[sid].name
		var t := gen.narrate(ctx)
		if t.length() < 20 or t.contains("[") or t.contains("{") or t.contains(" de les "):
			return "rendu incorrect pour %s : %s" % [e.get("type"), t]
	return ""


func test_formatage_dates() -> String:
	var cases := {
		-66_000_000.0: "il y a 66 millions d'années",
		-2_500_000.0: "il y a 2,5 millions d'années",
		-12_000.0: "il y a 12 mille ans",
		-500.0: "en l'an 500 avant notre ère",
		2077.0: "en l'an 2077",
	}
	for y in cases:
		if Procedural.format_year(y) != cases[y]:
			return "%s -> %s (attendu %s)" % [y, Procedural.format_year(y), cases[y]]
	return ""


func test_normalisation_ere_et_type() -> String:
	if Procedural.era_key("moyen age") != "Moyen Âge":
		return "ère sans accents non reconnue"
	if Procedural.era_key("Jurassique ?") != "generic":
		return "ère inconnue mal gérée"
	if Procedural.event_key("Battle") != "war" or Procedural.event_key("zzz") != "generic":
		return "alias d'événement mal gérés"
	return ""


# --- Décisions JSON -----------------------------------------------------------

func test_decision_json_valide() -> String:
	var d := DecisionSchema.parse('Voici : ```json\n{"action": "War", "target": "Orques", "reason": "Ils menacent nos frontières."}\n```')
	if d.get("action") != "war" or d.get("target") != "Orques" or d.get("reason", "") == "":
		return "décision valide rejetée : %s" % str(d)
	var d2 := DecisionSchema.parse('{"action": "research", "target": 3, "reason": "Savoir"}')
	if d2.get("target") != "3":
		return "cible numérique mal convertie : %s" % str(d2)
	return ""


func test_decision_json_malforme_repli() -> String:
	for raw in ["", "pas de json", '{"action": "war", "target": ', "[1, 2, 3]"]:
		if not DecisionSchema.parse(raw).is_empty():
			return "JSON malformé accepté : " + raw
	var d := DecisionSchema.decide("{oups", {"faith": 0.9})
	if d.get("source") != "heuristic" or d.get("action") != "worship":
		return "repli heuristique inattendu : %s" % str(d)
	return ""


func test_decision_mauvais_schema_repli() -> String:
	for raw in [
		'{"action": "dance", "target": "x", "reason": "y"}',
		'{"action": "war", "target": "x"}',
		'{"action": "war", "target": {"a": 1}, "reason": "y"}',
		'{"action": 5, "reason": "y"}',
		'{"action": "expand", "reason": "   "}',
	]:
		if not DecisionSchema.parse(raw).is_empty():
			return "mauvais schéma accepté : " + raw
	var d := DecisionSchema.decide('{"action": "nuke"}', {"aggression": 0.9, "population": 0.8, "tech": 0.8,
		"neighbors": [{"name": "Elfes", "strength": 0.9}, {"name": "Gobelins", "strength": 0.2}]})
	if d.get("action") != "war" or d.get("target") != "Gobelins" or d.get("source") != "heuristic":
		return "heuristique de guerre inattendue : %s" % str(d)
	var ok := DecisionSchema.decide('{"action": "expand", "target": "nord", "reason": "Place"}', {})
	if ok.get("source") != "llm":
		return "décision LLM valide non retenue"
	return ""


func test_heuristique_toujours_valide() -> String:
	for ctx in [{}, {"population": 0.9, "resources": 0.1}, {"faith": "beaucoup"}, {"neighbors": "aucun"}]:
		var d := DecisionSchema.fallback(ctx)
		if DecisionSchema.validate(d).is_empty():
			return "heuristique hors schéma pour %s : %s" % [str(ctx), str(d)]
	return ""


# --- Configuration ------------------------------------------------------------

func test_config_defauts() -> String:
	_cleanup()
	var cfg := AiConfig.new(TEST_CFG)
	if cfg.load_config() != ERR_FILE_NOT_FOUND:
		return "fichier inexistant mal signalé"
	if cfg.backend() != "auto" or cfg.model() != "llama3.2:3b" or cfg.ollama_url() != "http://127.0.0.1:11434":
		return "défauts inattendus"
	if cfg.llamacpp_url() != "http://127.0.0.1:8080" or absf(cfg.temperature() - 0.8) > 0.001:
		return "défauts inattendus (llama.cpp / température)"
	return ""


func test_config_sauvegarde_et_rechargement() -> String:
	_cleanup()
	var cfg := AiConfig.new(TEST_CFG)
	cfg.set_value("llm", "backend", "llamacpp")
	cfg.set_value("llm", "model", "qwen2.5:7b")
	cfg.set_value("llm", "num_gpu", 999)
	cfg.set_value("llm", "temperature", 5.0)  # bornée à 2.0
	cfg.set_value("llm", "ollama_url", "http://localhost:11434/")
	if cfg.save_config() != OK:
		return "sauvegarde impossible"
	var cfg2 := AiConfig.new(TEST_CFG)
	if cfg2.load_config() != OK:
		return "rechargement impossible"
	var err := ""
	if cfg2.backend() != "llamacpp" or cfg2.model() != "qwen2.5:7b" or cfg2.get_value("llm", "num_gpu") != 999:
		err = "valeurs non relues"
	elif cfg2.temperature() != 2.0:
		err = "température non bornée"
	elif cfg2.ollama_url() != "http://localhost:11434":
		err = "slash final non retiré"
	_cleanup()
	return err


func test_config_valeurs_invalides() -> String:
	_cleanup()
	var f := ConfigFile.new()
	f.set_value("llm", "backend", "chatgpt")
	f.set_value("llm", "timeout_sec", "abc")
	f.set_value("llm", "max_tokens", "300")
	f.set_value("narrator", "enabled", "oui")
	f.save(TEST_CFG)
	var cfg := AiConfig.new(TEST_CFG)
	cfg.load_config()
	var err := ""
	if cfg.backend() != "auto":
		err = "backend inconnu accepté"
	elif cfg.timeout_sec() != 20.0:
		err = "délai invalide accepté"
	elif cfg.get_value("llm", "max_tokens") != 300:
		err = "entier en texte non converti"
	elif cfg.get_value("narrator", "enabled") != true:
		err = "booléen invalide accepté"
	elif cfg.set_value("llm", "inconnu", 1):
		err = "clé inconnue acceptée"
	_cleanup()
	return err


# --- Client LLM (sans réseau) -------------------------------------------------

func test_corps_requetes_backends() -> String:
	var cfg := AiConfig.new(TEST_CFG)
	cfg.set_value("llm", "num_gpu", 20)
	var client := LlmClient.new()
	client.setup(cfg)
	var err := ""
	var o := client.build_body("ollama", "sys", "salut", {"json": true})
	var l := client.build_body("llamacpp", "sys", "salut", {})
	if client.endpoint_for("ollama") != "http://127.0.0.1:11434/api/chat":
		err = "URL Ollama"
	elif client.endpoint_for("llamacpp") != "http://127.0.0.1:8080/v1/chat/completions":
		err = "URL llama.cpp"
	elif o["model"] != "llama3.2:3b" or o["stream"] != false or o["format"] != "json" or o["options"]["num_gpu"] != 20:
		err = "corps Ollama : %s" % str(o)
	elif o["keep_alive"] != "10m" or o["messages"][1]["content"] != "salut":
		err = "corps Ollama (keep_alive / messages)"
	elif l.has("format") or l["max_tokens"] != 160 or l["messages"][0]["role"] != "system":
		err = "corps llama.cpp : %s" % str(l)
	elif LlmClient.extract_text("ollama", {"message": {"content": "Bonjour"}}) != "Bonjour":
		err = "extraction Ollama"
	elif LlmClient.extract_text("llamacpp", {"choices": [{"message": {"content": "Salut"}}]}) != "Salut":
		err = "extraction llama.cpp"
	elif LlmClient.extract_text("llamacpp", {"erreur": 1}) != "" or LlmClient.extract_text("ollama", null) != "":
		err = "extraction de réponse invalide"
	elif client.is_available():
		err = "client disponible sans détection"
	client.free()
	return err


func test_importance_evenements() -> String:
	if NarratorScript.event_importance({"type": "meteor"}) < 0.9:
		return "météorite pas assez importante"
	if NarratorScript.event_importance({"type": "migration"}) >= 0.4:
		return "migration trop importante"
	if NarratorScript.event_importance({"type": "migration", "importance": 0.95}) != 0.95:
		return "importance explicite ignorée"
	return ""


# --- Chronique de la parcelle (repli procédural uniquement) -------------------

const PARCEL_EVENT_TYPES := ["parcel_land_use", "parcel_arrival", "parcel_departure", "parcel_extinction",
	"parcel_heat", "parcel_cold", "parcel_inconnu"]


func _snap(land_use := "wild", fauna: Array = [], temp := 22.0) -> Dictionary:
	return {"year": -66_000_000.0, "biome": "Forêt tempérée", "land_use": land_use, "temperature_c": temp,
		"global_temperature_c": 18.0, "fauna": fauna, "structures": {}}


func _beast(id: int, name: String, role: String) -> Dictionary:
	return {"species_id": id, "name": name, "role": role, "count": 8, "trend": 0}


static func _sentences(t: String) -> int:
	var n := 0
	for i in t.length():
		if t[i] in [".", "!", "?", "…"] and (i + 1 == t.length() or t[i + 1] == " "):
			n += 1
	return n


## "" si le texte est une narration de parcelle correcte (1 ou 2 phrases, rien de non résolu).
static func _check_parcel_text(t: String) -> String:
	if t.strip_edges().length() < 15:
		return "texte vide ou trop court : « %s »" % t
	for bad in ["{", "}", "[", "]", " de les ", " à les ", " de le ", " que un ", " que une ", " de un ", " de des ", "  ", " ,", " ."]:
		if t.contains(bad):
			return "« %s » dans : %s" % [bad, t]
	var first := t.substr(0, 1)
	if first != first.to_upper() or first == first.to_lower():
		return "pas de majuscule initiale : " + t
	if not (t.ends_with(".") or t.ends_with("!")):
		return "pas de point final : " + t
	var n := _sentences(t)
	if n < 1 or n > 2:
		return "%d phrases au lieu de 1 ou 2 : %s" % [n, t]
	return ""


## Une suite d'événements de parcelle réaliste (dinosaures -> champs -> ville -> ruines), rejouée sur pn.
func _parcel_story(pn: ParcelNarrator) -> PackedStringArray:
	var out := PackedStringArray()
	var herb := _beast(1, "Titanosaures", "herbivore")
	var rex := _beast(2, "Tyrannosauridés", "carnivore")
	var man := _beast(3, "Humains", "sapient")
	pn.reset(_snap("wild", [herb]))
	var steps := [
		[{"type": "parcel_arrival", "species_id": 2, "summary": "Tyrannosauridés arrivent sur la parcelle."}, _snap("wild", [herb, rex]), "Mésozoïque"],
		[{"type": "parcel_departure", "species_id": 1, "species_alive": false}, _snap("wild", [rex]), "Mésozoïque"],
		[{}, _snap("wild", [rex], 28.0), "Cénozoïque"],
		[{"type": "parcel_arrival", "species_id": 3, "species_name": "Humains"}, _snap("wild", [rex, man], 28.0), "Préhistoire"],
		[{"type": "parcel_land_use", "summary": "La parcelle devient : camp."}, _snap("camp", [man], 28.0), "Préhistoire"],
		[{"type": "parcel_land_use", "summary": "La parcelle devient : farmland."}, _snap("farmland", [man], 28.0), "Antiquité"],
		[{}, _snap("village", [man], 28.0), "Moyen Âge"],
		[{"type": "parcel_land_use", "land_use": "city"}, _snap("city", [man], 28.0), "Industriel"],
		[{}, _snap("city", [man], 33.0), "Moderne"],
		[{"type": "parcel_land_use", "land_use": "ruins"}, _snap("ruins", [], 33.0), "Cyberpunk"],
		[{"type": "parcel_land_use", "land_use": "rewild"}, _snap("rewild", [herb], 20.0), "Post-singularité"],
	]
	for s in steps:
		var moments: Array = []
		if s[0].is_empty():
			moments.append_array(pn.observe(s[1]))
		else:
			moments.append(pn.on_event(s[0], s[1]))
		for m in moments:
			if not m.is_empty():
				out.append(pn.narrate(m, s[2], -1000.0))
	return out


func test_parcelle_chaque_evenement_non_vide() -> String:
	var fauna := [_beast(1, "Titanosaures", "herbivore"), _beast(7, "Verpha moloum", "carnivore")]
	for era in Procedural.ERAS + ["ère inconnue", ""]:
		var pn := ParcelNarrator.new(3)
		for etype in PARCEL_EVENT_TYPES:
			for lu in ParcelNarrator.LAND_USES:
				pn.reset(_snap("wild", []))
				var ev := {"type": etype, "species_id": 7, "summary": "La parcelle devient : %s." % lu, "delta_c": 6.0}
				var m := pn.on_event(ev, _snap(lu, fauna, 30.0))
				if lu == "wild" and etype == "parcel_land_use":
					if not m.is_empty():
						return "usage inchangé raconté : %s" % str(m)
					continue
				if m.is_empty():
					return "aucun moment pour %s (%s)" % [etype, lu]
				for _i in 3:
					var t := pn.narrate(m, era, -66_000_000.0)
					var err := _check_parcel_text(t)
					if err != "":
						return "%s / %s / %s : %s" % [era, etype, lu, err]
		var f := pn.focus(_snap("village", fauna))
		var err2 := _check_parcel_text(pn.narrate(f, era))
		if err2 != "":
			return "focus (%s) : %s" % [era, err2]
	return ""


## Tous les passages d'usage (premier ou non, dégel, repousse, émersion, recul) dans toutes les ères.
func test_parcelle_passages_usage_du_sol() -> String:
	var pn := ParcelNarrator.new(8)
	for era in Procedural.ERAS:
		for to in ParcelNarrator.LAND_USES:
			for prev in ParcelNarrator.LAND_USES:
				for first in [true, false]:
					var m := {"kind": "land_use", "type": "parcel_land_use", "land_use": to, "from": prev, "first": first,
						"snapshot": _snap(to, [_beast(3, "Humains", "sapient")])}
					var err := _check_parcel_text(pn.narrate(m, era, 1200.0))
					if err != "":
						return "%s -> %s (%s, premier=%s) : %s" % [prev, to, era, first, err]
	var key := func(to: String, prev: String) -> Array: return ParcelNarrator.templates_for({"kind": "land_use", "land_use": to, "from": prev, "first": true})
	if key.call("wild", "ice") != ParcelNarrator.LAND_USE_TEMPLATES["thaw"]:
		return "dégel non reconnu"
	if key.call("wild", "crater") != ParcelNarrator.LAND_USE_TEMPLATES["regrowth"]:
		return "repousse non reconnue"
	if key.call("village", "city") != ParcelNarrator.LAND_USE_TEMPLATES["shrink"]:
		return "recul ville -> village non reconnu"
	if key.call("village", "farmland") != ParcelNarrator.LAND_USE_FIRST_TEMPLATES["village"]:
		return "premier village non reconnu"
	var shrink := pn.render_template(ParcelNarrator.LAND_USE_TEMPLATES["shrink"][1],
		{"kind": "land_use", "land_use": "farmland", "from": "city", "snapshot": _snap("farmland")}, "Moderne", 1950.0)
	if not shrink.contains("d'une ville à des terres agricoles"):
		return "élision manquante : " + shrink
	return ""


## Chaque gabarit, pour chaque nom réel : marques d'accord résolues dans le bon nombre.
func test_parcelle_accords_tous_gabarits() -> String:
	var pn := ParcelNarrator.new(5)
	var re := RegEx.new()
	re.compile("\\[(\\w+):([^|\\]]*)\\|([^\\]]*)\\]")
	for tpl in ParcelNarrator.all_templates():
		for n in PLURAL_NAMES + SINGULAR_NAMES:
			var plural: bool = Procedural.species_phrase(n)["plural"]
			var m := {"kind": "arrival", "species_id": 1, "species_name": n, "role": "sapient", "land_use": "village",
				"from": "farmland", "delta_c": 5.0, "summary": "les champs brûlent",
				"snapshot": _snap("village", [_beast(1, n, "sapient")])}
			var t := pn.render_template(tpl, m, "Antiquité", -500.0)
			var err := _check_parcel_text(t)
			if err != "":
				return "%s : %s" % [n, err]
			for mt in re.search_all(tpl):
				var want := mt.get_string(3) if plural else mt.get_string(2)
				var wrong := mt.get_string(2) if plural else mt.get_string(3)
				if not t.contains(want):
					return "accord manquant « %s » (%s) : %s" % [want, n, t]
				if wrong != want and t.contains(" " + wrong + " ") and not want.contains(wrong):
					return "accord faux « %s » (%s) : %s" % [wrong, n, t]
	var sing := pn.render_template(ParcelNarrator.DEPARTURE_TEMPLATES[2],
		{"kind": "departure", "species_name": "Verpha moloum", "snapshot": _snap()}, "Mésozoïque")
	if not sing.begins_with("L'espèce Verpha moloum s'en est allée"):
		return "singulier féminin attendu : " + sing
	var plur := pn.render_template(ParcelNarrator.DEPARTURE_TEMPLATES[2],
		{"kind": "departure", "species_name": "Multituberculés", "snapshot": _snap()}, "Mésozoïque")
	if not plur.begins_with("Les Multituberculés s'en sont allés"):
		return "pluriel masculin attendu : " + plur
	var ext := pn.render_template(ParcelNarrator.EXTINCTION_TEMPLATES[2],
		{"kind": "extinction", "species_name": "Tyrannosauridés", "snapshot": _snap()}, "Mésozoïque")
	if not ext.contains("Il ne reste des Tyrannosauridés"):
		return "contraction « de les » attendue : " + ext
	return ""


func test_parcelle_determinisme() -> String:
	var a := _parcel_story(ParcelNarrator.new(42))
	var b := _parcel_story(ParcelNarrator.new(42))
	if a.size() < 8:
		return "histoire trop courte (%d narrations) : %s" % [a.size(), str(a)]
	if a != b:
		return "même graine, textes différents :\n%s\n%s" % [str(a), str(b)]
	for t in a:
		var err := _check_parcel_text(t)
		if err != "":
			return err
	var differs := false
	for s in [1, 7, 99, 1234]:
		if _parcel_story(ParcelNarrator.new(s)) != a:
			differs = true
	return "" if differs else "la graine n'a aucun effet"


## Suivi de l'état : doublons ignorés, retours, extinctions, premières fois, dérive de chaleur.
func test_parcelle_suivi_des_changements() -> String:
	var pn := ParcelNarrator.new(1)
	var herb := _beast(3, "Sauropodes", "herbivore")
	var rex := _beast(4, "Tyrannosauridés", "carnivore")
	pn.reset(_snap("wild", [herb]))
	if not pn.on_event({"type": "parcel_arrival", "species_id": 3}, _snap("wild", [herb])).is_empty():
		return "arrivée d'une espèce déjà présente racontée"
	var m := pn.on_event({"type": "parcel_arrival", "species_id": 4, "summary": "Tyrannosauridés arrivent sur la parcelle."}, _snap("wild", [herb, rex]))
	if m.get("kind") != "arrival" or m.get("role") != "carnivore" or m.get("species_name") != "Tyrannosauridés" or m.get("returning"):
		return "arrivée mal comprise : %s" % str(m)
	if not pn.on_event({"type": "parcel_arrival", "species_id": 4}, _snap("wild", [herb, rex])).is_empty():
		return "arrivée en double racontée"
	m = pn.on_event({"type": "parcel_departure", "species_id": 4, "summary": "Tyrannosauridés ont disparu de la parcelle."}, _snap("wild", [herb]))
	if m.get("kind") != "departure" or m.get("species_name") != "Tyrannosauridés":
		return "départ mal compris : %s" % str(m)
	if not pn.on_event({"type": "parcel_departure", "species_id": 4}, _snap("wild", [herb])).is_empty():
		return "départ en double raconté"
	m = pn.on_event({"type": "parcel_arrival", "species_id": 4}, _snap("wild", [herb, rex]))
	if not m.get("returning", false) or ParcelNarrator.importance(m) >= ParcelNarrator.importance({"kind": "arrival", "role": "carnivore"}):
		return "retour mal compris : %s" % str(m)
	m = pn.on_event({"type": "parcel_departure", "species_id": 4, "species_alive": false}, _snap("wild", [herb]))
	if m.get("kind") != "extinction":
		return "extinction non reconnue : %s" % str(m)
	m = pn.on_event({"type": "parcel_arrival", "species_id": 9, "summary": "Humains arrivent sur la parcelle."}, _snap("wild", [herb]))
	if m.get("species_name") != "Humains":
		return "nom non lu dans le résumé ParcelSim : %s" % str(m)
	# Usage du sol : par événement (résumé ParcelSim), puis par observation, sans doublon.
	m = pn.on_event({"type": "parcel_land_use", "summary": "La parcelle devient : farmland."}, _snap("farmland"))
	if m.get("land_use") != "farmland" or m.get("from") != "wild" or not m.get("first"):
		return "premiers champs mal compris : %s" % str(m)
	if not pn.observe(_snap("farmland")).is_empty():
		return "usage déjà raconté redétecté"
	var obs := pn.observe(_snap("village"))
	if obs.size() != 1 or obs[0].get("land_use") != "village" or not obs[0].get("first"):
		return "premier village non observé : %s" % str(obs)
	pn.observe(_snap("city"))
	obs = pn.observe(_snap("village"))
	if obs.size() != 1 or obs[0].get("first") or ParcelNarrator.templates_for(obs[0]) != ParcelNarrator.LAND_USE_TEMPLATES["shrink"]:
		return "recul de la ville mal compris : %s" % str(obs)
	if not pn.on_event({"type": "parcel_land_use", "land_use": "village"}, _snap("village")).is_empty():
		return "usage inchangé raconté"
	# Chaleur : seuil de dérive, puis nouvelle référence.
	if not pn.observe(_snap("village", [], 25.0)).is_empty():
		return "dérive de 3 °C racontée (seuil 4 °C)"
	obs = pn.observe(_snap("village", [], 27.0))
	if obs.size() != 1 or obs[0].get("kind") != "heat" or absf(float(obs[0].get("delta_c")) - 5.0) > 0.01:
		return "réchauffement non détecté : %s" % str(obs)
	if not pn.observe(_snap("village", [], 27.0)).is_empty():
		return "réchauffement raconté deux fois"
	obs = pn.observe(_snap("village", [], 20.0))
	if obs.size() != 1 or obs[0].get("kind") != "cold":
		return "refroidissement non détecté : %s" % str(obs)
	var t := pn.narrate(obs[0], "Moyen Âge")
	if (t.contains("degrés") or t.contains("°C")) == false:
		return "chaleur sans chiffre : " + t
	return ""


## Rareté : les grands moments de la parcelle passent avant les petits.
func test_parcelle_importance() -> String:
	var imp := func(m: Dictionary) -> float: return ParcelNarrator.importance(m)
	var crater: float = imp.call({"kind": "land_use", "land_use": "crater", "from": "wild"})
	var first_village: float = imp.call({"kind": "land_use", "land_use": "village", "from": "farmland", "first": true})
	var again_village: float = imp.call({"kind": "land_use", "land_use": "village", "from": "farmland", "first": false})
	var pasture: float = imp.call({"kind": "land_use", "land_use": "pasture", "first": true})
	if not (crater > first_village and first_village > again_village and first_village > pasture):
		return "ordre des usages inattendu : %f %f %f %f" % [crater, first_village, again_village, pasture]
	if imp.call({"kind": "extinction"}) <= imp.call({"kind": "departure"}):
		return "extinction moins importante qu'un départ"
	if imp.call({"kind": "arrival", "role": "sapient"}) <= imp.call({"kind": "arrival", "role": "herbivore"}):
		return "arrivée d'une espèce intelligente pas assez importante"
	if imp.call({"kind": "heat", "delta_c": 12.0}) <= imp.call({"kind": "heat", "delta_c": 4.0}):
		return "forte dérive pas plus importante qu'une faible"
	return ""


## Anti-spam : annulations, seuil, un seul usage en attente, taille bornée, péremption, priorité au monde.
func test_parcelle_file_anti_spam() -> String:
	var q: Array[Dictionary] = []
	q = NarratorScript.queue_parcel_moment(q, {"kind": "departure", "species_id": 4, "importance": 0.45}, 0.0, 0.35)
	if q.size() != 1:
		return "départ non mis en file"
	q = NarratorScript.queue_parcel_moment(q, {"kind": "arrival", "species_id": 4, "importance": 0.3, "returning": true}, 1.0, 0.35)
	if not q.is_empty():
		return "aller-retour d'une espèce non annulé : %s" % str(q)
	q = NarratorScript.queue_parcel_moment(q, {"kind": "arrival", "species_id": 5, "importance": 0.3}, 2.0, 0.35)
	if not q.is_empty():
		return "moment sous le seuil mis en file"
	q = NarratorScript.queue_parcel_moment(q, {"kind": "land_use", "land_use": "crater", "importance": 0.95}, 3.0, 0.35)
	q = NarratorScript.queue_parcel_moment(q, {"kind": "land_use", "land_use": "wild", "importance": 0.6}, 4.0, 0.35)
	if q.size() != 2 or q[0].get("land_use") != "crater":
		return "le cratère devrait rester devant la repousse : %s" % str(q)
	q = NarratorScript.queue_parcel_moment(q, {"kind": "land_use", "land_use": "ice", "importance": 0.95}, 5.0, 0.35)
	if q.size() != 1 or q[0].get("land_use") != "ice":
		return "un usage plus récent et aussi rare devrait remplacer les anciens : %s" % str(q)
	q = NarratorScript.queue_parcel_moment(q, {"kind": "heat", "importance": 0.6}, 6.0, 0.35)
	q = NarratorScript.queue_parcel_moment(q, {"kind": "cold", "importance": 0.6}, 7.0, 0.35)
	var temps := q.filter(func(m: Dictionary) -> bool: return m["kind"] in ["heat", "cold"])
	if temps.size() != 1 or temps[0]["kind"] != "cold":
		return "chaleur puis froid : seul le dernier devrait rester : %s" % str(q)
	for i in 20:
		q = NarratorScript.queue_parcel_moment(q, {"kind": "arrival", "species_id": 100 + i, "importance": 0.5}, 8.0, 0.35)
	if q.size() > NarratorScript.PARCEL_QUEUE_SIZE or q[0].get("land_use") != "ice":
		return "file non bornée ou mal triée : %d" % q.size()
	var old: Array[Dictionary] = [{"kind": "arrival", "importance": 0.5, "_t": 0.0}, {"kind": "land_use", "importance": 0.9, "_t": 0.0}]
	var kept := NarratorScript.expire_parcel_moments(old, NarratorScript.PARCEL_MAX_AGE + 1.0)
	if kept.size() != 1 or kept[0]["kind"] != "land_use":
		return "péremption incorrecte : %s" % str(kept)
	if not NarratorScript.expire_parcel_moments(old, NarratorScript.PARCEL_RARE_MAX_AGE + 1.0).is_empty():
		return "un moment rare devrait finir par expirer"
	var cases := [
		[-1.0, 0.5, true, true], [0.9, 0.95, true, false], [1.1, 0.95, true, false], [0.5, 0.75, true, true],
		[0.7, 0.5, true, false], [-1.0, 0.5, false, false], [-1.0, -1.0, true, false],
	]
	for c in cases:
		if NarratorScript.parcel_goes_first(c[0], c[1], c[2]) != c[3]:
			return "priorité monde/parcelle fausse pour %s" % str(c)
	return ""


func test_parcelle_prompt_llm() -> String:
	var s := Prompts.parcel_system()
	for needle in ["français", "1 ou 2 phrases", "deuxième personne", "Dieu"]:
		if not s.contains(needle):
			return "persona parcelle sans « %s »" % needle
	var pn := ParcelNarrator.new(1)
	pn.reset(_snap("farmland"))
	var snap := _snap("village", [_beast(1, "Humains", "sapient"), _beast(2, "Aurochs", "herbivore")], 24.0)
	snap["fauna"][0]["trend"] = 1
	snap["structures"] = {"hut": 6, "field": 3}
	var m := pn.on_event({"type": "parcel_land_use", "summary": "La parcelle devient : village."}, snap)
	var p := Prompts.build_parcel_prompt(m, {"era": "Antiquité", "year": -800.0})
	for needle in ["Antiquité", "avant notre ère", "un village", "des terres agricoles", "première fois",
			"Forêt tempérée", "24 °C", "18 °C", "Humains", "intelligente", "en hausse", "Aurochs", "6 huttes", "3 champs",
			"1 ou 2 phrases", "deuxième personne"]:
		if not p.contains(needle):
			return "prompt parcelle sans « %s » : %s" % [needle, p]
	var arr := ParcelNarrator.describe_moment({"kind": "arrival", "species_name": "Tyrannosauridés", "role": "carnivore"})
	if not arr.contains("Arrivée des Tyrannosauridés (prédateur)"):
		return "fait d'arrivée mal formé : " + arr
	var dep := ParcelNarrator.describe_moment({"kind": "departure", "species_name": "Tyrannosauridés"})
	var dep1 := ParcelNarrator.describe_moment({"kind": "departure", "species_name": "Verpha moloum"})
	if not (dep.contains("les Tyrannosauridés ne vivent plus") and dep1.contains("l'espèce Verpha moloum ne vit plus")):
		return "accord des faits de départ : %s / %s" % [dep, dep1]
	var empty := Prompts.build_parcel_prompt({"kind": "generic"})
	return "" if empty.length() > 20 else "prompt parcelle vide"


func test_parcelle_config() -> String:
	_cleanup()
	var cfg := AiConfig.new(TEST_CFG)
	if cfg.get_value("narrator", "parcel_enabled") != true or cfg.get_value("narrator", "parcel_min_interval_sec") != 15.0:
		return "défauts de parcelle inattendus"
	cfg.set_value("narrator", "parcel_min_importance", 3.0)
	cfg.set_value("narrator", "parcel_heat_drift_c", -2)
	if cfg.get_value("narrator", "parcel_min_importance") != 1.0 or cfg.get_value("narrator", "parcel_heat_drift_c") != 0.5:
		return "bornes de parcelle non appliquées"
	return ""


## Intégration : vraie WorldSim + ParcelSim, météore sur la parcelle, puis des millions d'années.
func test_parcelle_simulation_reelle() -> String:
	var WorldSim: GDScript = load("res://src/sim/world_sim.gd")
	var ParcelSim: GDScript = load("res://src/sim/parcel_sim.gd")
	var sim: RefCounted = WorldSim.new(1234)
	var parcel: RefCounted = ParcelSim.new(sim, Vector2i(70, 40))
	var pn := ParcelNarrator.new(5)
	pn.reset(ParcelNarrator.snapshot(parcel))
	var told := PackedStringArray()
	var action := {"type": "meteor", "region": parcel.cell, "species_id": -1, "radius": 6}
	var world_events: Array = sim.apply_divine_action(action)
	world_events.append({"type": "meteor", "region": parcel.cell})  # comme GameState.apply_divine_action
	for frame in 60:
		if frame > 0:
			world_events = sim.step(sim.ideal_step_years() * sim.max_substeps)
		var moments: Array = []
		for ev in parcel.update(world_events):
			if not str(ev.get("type", "")).begins_with("parcel_"):
				return "événement de parcelle sans préfixe : %s" % str(ev)
			var e: Dictionary = ev.duplicate()
			var sid := int(e.get("species_id", -1))
			if sid >= 0 and sim.species.has(sid):
				e["species_name"] = sim.species[sid].name
				e["species_alive"] = bool(sim.species[sid].get("alive", true))
			moments.append(pn.on_event(e, ParcelNarrator.snapshot(parcel)))
		moments.append_array(pn.observe(ParcelNarrator.snapshot(parcel)))
		for m in moments:
			if m.is_empty():
				continue
			var t := pn.narrate(m, sim.current_era(), sim.year)
			var err := _check_parcel_text(t)
			if err != "":
				return "%s : %s" % [m.get("type"), err]
			told.append(t)
	if told.is_empty():
		return "le météore sur la parcelle n'a rien fait raconter"
	return ""


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))
