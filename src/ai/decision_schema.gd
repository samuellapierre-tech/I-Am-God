extends RefCounted
## Crochet structuré pour de futures décisions de civilisation pilotées par l'IA.
## Valide la réponse JSON du LLM contre un petit schéma ; sinon, repli sur une heuristique déterministe.

const ACTIONS := ["war", "expand", "research", "worship"]
const MAX_REASON := 200


## Extrait et valide une décision depuis le texte brut du LLM.
## Renvoie {action, target, reason} si valide, sinon {} (l'appelant applique alors fallback()).
static func parse(raw: String) -> Dictionary:
	var text := raw.strip_edges()
	# Tolère du texte autour (ou un bloc ```json) : on isole le premier objet {...}.
	var start := text.find("{")
	var end := text.rfind("}")
	if start == -1 or end <= start:
		return {}
	var json := JSON.new()
	if json.parse(text.substr(start, end - start + 1)) != OK:
		return {}
	return validate(json.data)


## Vérifie le schéma : action ∈ ACTIONS, target chaîne/nombre (facultative), reason chaîne non vide.
static func validate(data: Variant) -> Dictionary:
	if not (data is Dictionary):
		return {}
	var action: Variant = data.get("action", null)
	if not (action is String) or not (String(action).to_lower() in ACTIONS):
		return {}
	var target: Variant = data.get("target", "")
	if target == null:
		target = ""
	if not (typeof(target) in [TYPE_STRING, TYPE_INT, TYPE_FLOAT]):
		return {}
	var reason: Variant = data.get("reason", null)
	if not (reason is String) or String(reason).strip_edges() == "":
		return {}
	var t := str(int(target)) if typeof(target) == TYPE_FLOAT and float(target) == floorf(target) else str(target)
	return {
		"action": String(action).to_lower(),
		"target": t.strip_edges(),
		"reason": String(reason).strip_edges().left(MAX_REASON),
	}


## Heuristique de repli (sans IA). context : {faith, aggression, population, resources, tech, neighbors: [{name|id, strength}]}
## Toutes les valeurs numériques sont attendues entre 0 et 1 ; les absentes valent 0.5.
static func fallback(context: Dictionary) -> Dictionary:
	var faith := _num(context, "faith")
	var aggression := _num(context, "aggression")
	var population := _num(context, "population")
	var resources := _num(context, "resources")
	var tech := _num(context, "tech")
	var neighbors: Array = context.get("neighbors", []) if context.get("neighbors") is Array else []
	var weakest: Variant = null
	var weakest_strength := INF
	for n in neighbors:
		if n is Dictionary:
			var s := float(n.get("strength", 0.5))
			if s < weakest_strength:
				weakest_strength = s
				weakest = n
	var own_strength := population * 0.5 + tech * 0.5
	if weakest != null and aggression > 0.6 and weakest_strength < own_strength:
		var name := str(weakest.get("name", weakest.get("id", "voisin")))
		return {"action": "war", "target": name, "reason": "%s est plus faible que nous : le moment est venu de frapper." % name}
	if faith > 0.65:
		return {"action": "worship", "target": "Dieu", "reason": "Le peuple réclame des temples pour honorer le Très-Haut."}
	if population > 0.6 and resources < 0.4:
		return {"action": "expand", "target": "terres voisines", "reason": "Nos terres ne suffisent plus à nourrir notre peuple."}
	return {"action": "research", "target": "savoir", "reason": "Le savoir est notre meilleure arme pour l'avenir."}


## Décision finale : réponse du LLM validée si possible, sinon heuristique. Ajoute "source".
static func decide(raw: String, context: Dictionary) -> Dictionary:
	var d := parse(raw)
	if d.is_empty():
		d = fallback(context)
		d["source"] = "heuristic"
	else:
		d["source"] = "llm"
	return d


static func _num(context: Dictionary, key: String) -> float:
	var v: Variant = context.get(key, 0.5)
	return clampf(float(v), 0.0, 1.0) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 0.5
