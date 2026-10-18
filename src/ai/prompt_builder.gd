extends RefCounted
## Construction des prompts envoyés au LLM local et nettoyage de ses réponses.
## Fonctions statiques pures : testables sans réseau.

const Procedural := preload("res://src/ai/procedural_narrator.gd")
const ParcelNarrator := preload("res://src/ai/parcel_narrator.gd")
const AiConfig := preload("res://src/ai/ai_config.gd")

## Contraintes communes à tout ce que le narrateur écrit.
const STYLE_RULES := "Réponds TOUJOURS en français correct. Pas de liste, pas de titre, pas de guillemets, pas de méta-commentaire, ne te présente pas."

const PERSONA_ORACLE := "Tu es l'Oracle des dieux. Dieu (le joueur) t'interroge sur un futur possible ; tu as entrevu ce futur grâce à une simulation. Réponds en français, en 2 ou 3 phrases, sous forme de prophétie mystérieuse mais fidèle aux faits fournis. Tutoie Dieu avec révérence. Pas de liste, pas de titre."

const PERSONA_PRIERE := "Tu écris la prière qu'un peuple adresse à son Dieu (le joueur). Écris en français, à la première personne du pluriel (« nous »), en 2 ou 3 phrases, dans le style et le vocabulaire de l'époque indiquée. La prière doit exprimer la détresse ou la gratitude du peuple et formuler une demande qui place Dieu devant un choix moral (aider ce peuple a un prix pour d'autres). Pas de liste, pas de titre."

const PERSONA_INVENTION := "Tu inventes la culture d'un peuple imaginaire dans un jeu où Dieu (le joueur) façonne un monde qui a quitté l'histoire réelle de la Terre. Réponds UNIQUEMENT par un objet JSON valide, sans texte autour, de la forme {\"coutumes\": [\"...\", \"...\"], \"croyance\": \"...\", \"fete\": \"...\"}, en français, chaque valeur en une proposition courte, sans majuscule initiale ni point final, cohérente avec les traits et la mémoire fournis."

const PERSONA_DECISION := "Tu es le conseil dirigeant d'une civilisation dans un jeu de simulation. Tu choisis la prochaine grande décision. Réponds UNIQUEMENT par un objet JSON valide, sans texte autour, de la forme {\"action\": \"war\"|\"expand\"|\"research\"|\"worship\", \"target\": \"...\", \"reason\": \"...\"}. La raison est une courte phrase en français."


## Narration des événements du monde (persona de AiConfig).
static func narration_system() -> String:
	return "%s Tu racontes à Dieu l'histoire du monde qu'il façonne, des dinosaures jusqu'au cyberpunk, en 1 à 3 phrases, sur un ton vivant et concret. N'invente pas de faits contraires au contexte. %s" % [AiConfig.persona_text(), STYLE_RULES]


## Narration de la parcelle suivie (un morceau de terrain grand comme l'écran).
static func parcel_system() -> String:
	return "%s Dieu regarde un seul morceau de terrain, grand comme l'écran, qu'il suit des dinosaures jusqu'à la fin des temps. Raconte-lui ce qui vient d'arriver sur CE terrain, à la deuxième personne (« tu », « ta parcelle »), en 1 ou 2 phrases courtes, concrètes et évocatrices, dans le vocabulaire de l'époque. N'invente aucun fait absent du contexte (pas d'espèce, de ville ni de catastrophe non mentionnées). %s" % [AiConfig.persona_text(), STYLE_RULES]


## context : {type, era, year, summary, species_name|species|species_id, events: Array, action: Dictionary}
static func build_narration_prompt(context: Dictionary) -> String:
	var lines := PackedStringArray()
	var era := str(context.get("era", ""))
	if era != "":
		lines.append("Époque : %s." % era)
	if typeof(context.get("year")) in [TYPE_INT, TYPE_FLOAT]:
		lines.append("Date : %s (année %d)." % [Procedural.format_year(float(context["year"])), int(context["year"])])
	var action: Variant = context.get("action", null)
	if action is Dictionary and not action.is_empty():
		lines.append("Geste divin de Dieu : %s." % describe_action(action))
	var events: Variant = context.get("events", [])
	if events is Array and not events.is_empty():
		lines.append("Événements récents (du plus important au moins important) :")
		for e in events:
			lines.append("- " + describe_event(e if e is Dictionary else {"summary": str(e)}))
	elif context.has("type") or context.has("summary"):
		lines.append("Événement : " + describe_event(context))
	if lines.is_empty():
		lines.append("Rien de notable ne s'est produit ; décris l'état du monde.")
	lines.append("")
	lines.append("Raconte ce moment à Dieu en 1 à 3 phrases.")
	return "\n".join(lines)


## Fil continu : une phrase d'ambiance quand rien de marquant n'arrive.
static func ambient_system() -> String:
	return "%s Tu tiens un fil continu, écrit, de l'histoire de la parcelle que Dieu regarde : une seule phrase courte (deux au plus), à la première personne (« je ») et en tutoyant Dieu. %s" % [AiConfig.persona_text(), STYLE_RULES]


## line : sortie de Chronicle.ambient() ; ctx : contexte du fil (era, year, snapshot…).
static func build_ambient_prompt(line: Dictionary, ctx: Dictionary) -> String:
	var lines := PackedStringArray()
	var era := str(ctx.get("era", ""))
	if era != "":
		lines.append("Époque : %s." % era)
	if typeof(ctx.get("year")) in [TYPE_INT, TYPE_FLOAT]:
		lines.append("Date : %s." % Procedural.format_year(float(ctx["year"])))
	var snap: Dictionary = ctx.get("snapshot", {})
	if not snap.is_empty():
		lines.append("État de la parcelle :")
		for l in ParcelNarrator.describe_snapshot(snap):
			lines.append("- " + l)
	lines.append("")
	if str(line.get("kind", "")) == "fact":
		lines.append("Fait historique VRAI à transmettre : " + str(line.get("text", "")))
		lines.append("Reformule-le à ta manière, en conteur, sans changer ni ajouter aucune date, aucun chiffre, aucun nom, aucun fait. Une phrase, deux au plus.")
	else:
		lines.append("Observation à transmettre (vraie, n'ajoute aucun fait) : " + str(line.get("text", "")))
		lines.append("Reformule-la à ta manière en une phrase, deux au plus.")
	return "\n".join(lines)


## Monde divergent : le LLM invente un détail à partir de l'état réel de la simulation et de la mémoire.
static func build_invention_prompt(line: Dictionary, ctx: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(_world_header(ctx))
	var p: Variant = line.get("profile", null)
	if p is Dictionary:
		var sp := {}
		for s in ctx.get("species", []):
			if int(s.get("id", -2)) == int(p.get("id", -1)):
				sp = s
		lines.append("Espèce (traits réels de la simulation, JSON) : " + JSON.stringify(_jsonable(sp)))
		var memory := {}
		for k in p:
			if not str(k).begins_with("llm_requested"):
				memory[k] = p[k]
		lines.append("Ce qui a déjà été raconté sur elle (mémoire à respecter, ne rien contredire, réutiliser les noms) : " + JSON.stringify(_jsonable(memory)))
	lines.append("")
	lines.append("Proposition de base (tu peux la garder ou l'enrichir) : " + str(line.get("text", "")))
	lines.append("Invente UN détail concret de mœurs, de culture ou de vie quotidienne, cohérent avec ces traits, ce climat, cet usage du sol, cette technologie et la mémoire. Tu avoues découvrir ce monde avec Dieu. Une phrase, deux au plus.")
	return "\n".join(lines)


## Demande d'enrichissement (JSON) d'un peuple inventé ; la réponse passe par Inventor.enrich_from_llm.
static func build_enrich_prompt(profile: Dictionary, ctx: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(_world_header(ctx))
	lines.append("Peuple (mémoire, JSON) : " + JSON.stringify(_jsonable(profile)))
	lines.append("Propose 2 nouvelles coutumes, une croyance et une fête pour ce peuple, cohérentes avec sa mémoire. Réponds uniquement en JSON.")
	return "\n".join(lines)


## En-tête de contexte commun aux prompts d'invention : époque, mode du monde, parcelle, gestes divins.
static func _world_header(ctx: Dictionary) -> String:
	var lines := PackedStringArray()
	var mode: Dictionary = ctx.get("mode", {})
	lines.append("Monde : %s%s." % [str(mode.get("label", "réel")),
		(" (" + ", ".join(PackedStringArray(mode.get("reasons", []))) + ")") if not mode.get("reasons", []).is_empty() else ""])
	if str(ctx.get("era", "")) != "":
		lines.append("Ère atteinte : %s." % str(ctx["era"]))
	if typeof(ctx.get("year")) in [TYPE_INT, TYPE_FLOAT]:
		lines.append("Date : %s." % Procedural.format_year(float(ctx["year"])))
	var snap: Dictionary = ctx.get("snapshot", {})
	for l in ParcelNarrator.describe_snapshot(snap):
		lines.append(l)
	var acts := PackedStringArray()
	for a in ctx.get("divine", []):
		acts.append(str(a.get("type", "")) if a is Dictionary else str(a))
	if not acts.is_empty():
		lines.append("Gestes divins passés : %s." % ", ".join(acts))
	return "\n".join(lines)


## Narration d'un moment de la parcelle (ParcelNarrator) : le fait, puis l'état du terrain.
## context : {era, year}
static func build_parcel_prompt(moment: Dictionary, context: Dictionary = {}) -> String:
	var lines := PackedStringArray()
	var era := str(context.get("era", ""))
	if era != "":
		lines.append("Époque : %s." % era)
	var year: Variant = context.get("year", moment.get("snapshot", {}).get("year", null))
	if typeof(year) in [TYPE_INT, TYPE_FLOAT]:
		lines.append("Date : %s." % Procedural.format_year(float(year)))
	lines.append("Ce qui vient d'arriver sur la parcelle : " + ParcelNarrator.describe_moment(moment))
	var snap: Dictionary = moment.get("snapshot", {})
	if not snap.is_empty():
		lines.append("État actuel de la parcelle :")
		for l in ParcelNarrator.describe_snapshot(snap):
			lines.append("- " + l)
	lines.append("")
	lines.append("Raconte ce moment à Dieu en 1 ou 2 phrases, à la deuxième personne, centrées sur cette parcelle.")
	return "
".join(lines)


static func build_oracle_prompt(question: String, projection: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("Question de Dieu : « %s »" % question.strip_edges())
	var visions := Procedural.projection_visions(projection)
	if visions.is_empty():
		lines.append("La simulation du futur n'a rien révélé de net.")
	else:
		lines.append("Ce que la simulation du futur a révélé :")
		for v in visions:
			lines.append("- " + v)
	lines.append("")
	lines.append("Réponds par une prophétie en 2 ou 3 phrases.")
	return "\n".join(lines)


static func build_prayer_prompt(species: Dictionary, situation: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("Peuple : %s." % str(species.get("name", "un peuple sans nom")))
	var traits: Variant = species.get("traits", null)
	if traits is Array and not traits.is_empty():
		lines.append("Traits : %s." % ", ".join(traits.map(func(t): return str(t))))
	elif traits is Dictionary and not traits.is_empty():
		lines.append("Traits : %s." % ", ".join(traits.keys().map(func(k): return "%s=%s" % [k, traits[k]])))
	if species.has("population"):
		lines.append("Population : %s." % str(species["population"]))
	var era := str(situation.get("era", species.get("era", "")))
	if era != "":
		lines.append("Époque : %s." % era)
	lines.append("Situation : %s." % str(situation.get("type", "inconnue")))
	if situation.has("enemy") or situation.has("enemy_name"):
		lines.append("Ennemi : %s." % str(situation.get("enemy", situation.get("enemy_name"))))
	if situation.get("summary", "") != "":
		lines.append("Détails : %s" % str(situation["summary"]))
	lines.append("")
	lines.append("Écris leur prière à Dieu.")
	return "\n".join(lines)


static func build_decision_prompt(context: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("État de la civilisation (JSON) :")
	lines.append(JSON.stringify(_jsonable(context)))
	lines.append("")
	lines.append("Choisis une action parmi war, expand, research, worship. Réponds uniquement en JSON.")
	return "\n".join(lines)


static func describe_action(action: Dictionary) -> String:
	var names := {
		"meteor": "une météorite", "extinct": "l'extinction d'une espèce", "save": "le sauvetage d'une espèce",
		"bless": "une bénédiction", "plague": "une épidémie", "uplift": "l'éveil de l'intelligence",
		"flood": "un déluge", "ice_age": "un âge glaciaire", "spawn_species": "la création d'une espèce",
	}
	var t := str(action.get("type", ""))
	var s: String = names.get(t, t if t != "" else "un geste mystérieux")
	if typeof(action.get("species_id")) in [TYPE_INT, TYPE_FLOAT] and int(action["species_id"]) >= 0:
		s += " (espèce n°%d)" % int(action["species_id"])
	if action.get("region") is Vector2i:
		s += " en %s" % str(action["region"])
	return s


static func describe_event(e: Dictionary) -> String:
	var parts := PackedStringArray()
	var t := str(e.get("type", ""))
	if t != "":
		parts.append("[%s]" % t)
	var sp := Procedural.species_name(e)
	if sp != "":
		parts.append(sp + " :")
	var summary := str(e.get("summary", "")).strip_edges()
	parts.append(summary if summary != "" else "(sans description)")
	return " ".join(parts)


## Nettoie la sortie d'un LLM : balises de raisonnement, guillemets, préfixes, longueur.
static func sanitize_output(text: String, max_sentences: int = 3, max_chars: int = 600) -> String:
	var t := text
	# Modèles « raisonneurs » (qwen3, deepseek-r1...) : on retire le bloc <think>.
	var re := RegEx.new()
	re.compile("(?s)<think>.*?</think>")
	t = re.sub(t, "", true)
	t = t.replace("<think>", "").replace("</think>", "")
	t = t.strip_edges()
	for prefix in ["Chroniqueur :", "Le Chroniqueur :", "Oracle :", "L'Oracle :", "Prière :", "Narrateur :"]:
		if t.begins_with(prefix):
			t = t.substr(prefix.length()).strip_edges()
	t = t.replace("\r", " ").replace("\n", " ").replace("*", "").replace("#", "")
	while t.contains("  "):
		t = t.replace("  ", " ")
	for q in [["\"", "\""], ["« ", " »"], ["«", "»"], ["“", "”"]]:
		if t.begins_with(q[0]) and t.ends_with(q[1]) and t.length() > 2:
			t = t.substr(q[0].length(), t.length() - q[0].length() - q[1].length()).strip_edges()
	# Coupe au nombre maximal de phrases.
	var count := 0
	for i in t.length():
		if t[i] in [".", "!", "?", "…"] and (i + 1 == t.length() or t[i + 1] == " "):
			count += 1
			if count >= max_sentences:
				t = t.substr(0, i + 1)
				break
	if t.length() > max_chars:
		var cut := t.substr(0, max_chars)
		var last := maxi(cut.rfind(". "), maxi(cut.rfind("! "), cut.rfind("? ")))
		t = cut.substr(0, last + 1) if last > 40 else cut.strip_edges() + "…"
	return t.strip_edges()


## Convertit les types Godot (Vector2i...) en valeurs sérialisables en JSON.
static func _jsonable(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[str(k)] = _jsonable(v[k])
			return d
		TYPE_ARRAY:
			return v.map(func(x): return _jsonable(x))
		TYPE_VECTOR2I, TYPE_VECTOR2:
			return [v.x, v.y]
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return Array(v)
		TYPE_OBJECT:
			return str(v)
	return v
