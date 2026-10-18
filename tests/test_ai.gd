extends RefCounted
## Tests de la couche IA (aucun réseau requis).

const AiConfig := preload("res://src/ai/ai_config.gd")
const LlmClient := preload("res://src/ai/llm_client.gd")
const Procedural := preload("res://src/ai/procedural_narrator.gd")
const Prompts := preload("res://src/ai/prompt_builder.gd")
const DecisionSchema := preload("res://src/ai/decision_schema.gd")
const NarratorScript := preload("res://src/ai/narrator.gd")

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


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CFG))
