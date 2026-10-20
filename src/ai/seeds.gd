extends RefCounted
## Le narrateur réagit aux SEMENCES du joueur (action divine `seed`, docs/GENESE.md) : réussite ou échec,
## et TOUJOURS la raison (« Pas encore d'ozone : tes spores ont brûlé sous les ultraviolets »).
## La simulation décide ; on ne fait que lire son verdict et l'expliquer.
##
## Action : {type: "seed", kind: "spark" | "light" | "spore" | "animal_germ" | "shaped", region, traits?}.
## Verdict (dans cet ordre) :
## 1. explicite : une conséquence {success|ok: bool, reason_code|reason} (ou un type contenant "seed") ;
## 2. sinon déduit : une conséquence qui fait naître une espèce (spawn, speciation, seeded, new_species…)
##    = réussite ; aucune = échec ;
## 3. raison : reason_code fourni, sinon déduite des conditions de la planète (Explainer.normalize) :
##    no_ozone, low_oxygen, no_water, no_land, no_light, no_food, too_cold, too_hot, competition,
##    maladapted, unknown (échecs) ; vents, light_and_water, ozone_shield, oxygen_enough, adapted (réussites).

const Procedural := preload("res://src/ai/procedural_narrator.gd")
const Epoch := preload("res://src/ai/epoch.gd")
const Explainer := preload("res://src/ai/explainer.gd")

const KINDS := ["spark", "light", "spore", "animal_germ", "shaped"]
## Nom de la semence, tel que le narrateur en parle au joueur.
const NOUNS := {
	"spark": "ton étincelle de vie", "light": "tes semences de lumière", "spore": "tes spores",
	"animal_germ": "tes germes de vie animale", "shaped": "ta créature façonnée",
}
## Nombre et genre du nom ci-dessus (pour accorder verbes et participes : {e} féminin, {s} pluriel).
const PLURAL := {"spark": false, "light": true, "spore": true, "animal_germ": true, "shaped": false}
const FEMININE := {"spark": true, "light": true, "spore": true, "animal_germ": false, "shaped": true}
## Types de conséquences qui signifient qu'une vie est née.
const BIRTH_TYPES := ["spawn", "speciation", "seeded", "new_species", "seed_success", "seed_took", "clade", "life"]
## Raisons des échecs : la phrase commence par la cause, puis ce qui est arrivé à la semence ({semence}).
const FAILURES := {
	"no_ozone": "Pas encore d'ozone : {semence} [n:a brûlé|ont brûlé] sous les ultraviolets.",
	"low_oxygen": "Trop peu d'oxygène dans l'air : {semence} [n:a suffoqué|ont suffoqué] avant de se diviser.",
	"no_water": "Pas d'eau liquide là où tu as semé : {semence} [n:s'est|se sont] desséché{e}{s} aussitôt.",
	"no_land": "Aucune terre ferme où s'accrocher : {semence} [n:s'est|se sont] perdu{e}{s} dans les vagues.",
	"no_light": "La lumière n'arrive pas jusque-là : {semence} [n:s'est|se sont] éteint{e}{s} dans le noir.",
	"no_food": "Rien à manger : aucune vie ne fabrique encore de quoi nourrir {semence}.",
	"too_cold": "Trop froid : {semence} [n:a gelé|ont gelé] avant de prendre.",
	"too_hot": "Trop chaud : {semence} [n:a cuit|ont cuit] dans l'eau brûlante.",
	"competition": "La place est déjà prise : d'autres vies, mieux installées, ont étouffé {semence}.",
	"maladapted": "Ses traits ne conviennent pas à ce milieu : {semence} n'[n:a|ont] pas tenu.",
	"unknown": "Je ne vois pas la cause : {semence} n'[n:a|ont] pas pris, et la planète ne m'en dit pas plus.",
}
const SUCCESSES := {
	"vents": "{semence} a pris : près des sources chaudes, la chimie des roches suffit à vivre, sans soleil.",
	"light_and_water": "{semence} [n:a pris|ont pris] : de l'eau, de la lumière, et la vie fabrique sa propre nourriture.",
	"ozone_shield": "{semence} [n:a pris|ont pris] : l'ozone protège désormais les terres des ultraviolets.",
	"oxygen_enough": "{semence} [n:a pris|ont pris] : l'air contient assez d'oxygène pour brûler la nourriture.",
	"adapted": "{semence} a pris : ses traits conviennent à ce milieu.",
}
## Phénomène à expliquer ensuite, selon la raison (facts/phenomena.gd).
const REASON_PHENOMENA := {
	"no_ozone": "ozone", "ozone_shield": "land_colonization", "low_oxygen": "oxygen_rise", "oxygen_enough": "oxygen_rise",
	"vents": "chemosynthesis", "light_and_water": "photosynthesis", "no_food": "food_chain", "competition": "decline_competition",
	"too_cold": "ice_age", "too_hot": "greenhouse",
}


## Réaction à une semence : {text, success, reason_code, kind, phenomenon}.
## planet : statistiques brutes ou normalisées de la planète ; ctx : contexte du fil (époque…).
static func react(action: Dictionary, consequences: Array, planet: Dictionary = {}, ctx: Dictionary = {}) -> Dictionary:
	var kind := str(action.get("kind", action.get("seed", "spark")))
	if not kind in KINDS:
		kind = "shaped"
	var verdict := verdict_of(consequences)
	var stats := Explainer.normalize(planet)
	var success: bool = verdict.get("success", false)
	var reason := str(verdict.get("reason_code", ""))
	if reason == "" or not (FAILURES.has(reason) or SUCCESSES.has(reason)):
		reason = infer_reason(kind, success, stats, action)
	# Une raison d'échec pour une réussite (ou l'inverse) : on se fie au verdict.
	if success and not SUCCESSES.has(reason):
		reason = infer_reason(kind, true, stats, action)
	elif not success and not FAILURES.has(reason):
		reason = infer_reason(kind, false, stats, action)
	var tpl: String = (SUCCESSES if success else FAILURES)[reason]
	var text := Procedural.apply_agreement(tpl, {"n": PLURAL[kind]}).format({"semence": NOUNS[kind],
		"e": "e" if FEMININE[kind] else "", "s": "s" if PLURAL[kind] else ""})
	text = Procedural.polish(text)
	return {"text": text, "success": success, "reason_code": reason, "kind": kind, "phenomenon": REASON_PHENOMENA.get(reason, "")}


## Verdict de la simulation : {success, reason_code?} (voir l'ordre dans l'en-tête).
static func verdict_of(consequences: Array) -> Dictionary:
	for c in consequences:
		if not (c is Dictionary):
			continue
		for key in ["success", "ok", "took"]:
			if c.has(key):
				return {"success": bool(c[key]), "reason_code": str(c.get("reason_code", c.get("reason", "")))}
		var t := str(c.get("type", "")).to_lower()
		if t.contains("seed") and (t.contains("fail") or t.contains("died") or t.contains("echec")):
			return {"success": false, "reason_code": str(c.get("reason_code", c.get("reason", "")))}
	for c in consequences:
		if c is Dictionary:
			var t := str(c.get("type", "")).to_lower()
			for b in BIRTH_TYPES:
				if t.contains(b):
					return {"success": true, "reason_code": str(c.get("reason_code", ""))}
	return {"success": false, "reason_code": ""}


## Raison la plus probable d'après les conditions de la planète (heuristique documentée dans l'en-tête).
static func infer_reason(kind: String, success: bool, s: Dictionary, action: Dictionary = {}) -> String:
	var t := float(s.get("temperature_c", 15.0))
	var oxygen := float(s.get("oxygen", 0.21))
	var ozone := float(s.get("ozone", 1.0))
	var ice := float(s.get("ice_cover", 0.0))
	var biomass := float(s.get("biomass", 1.0))
	if success:
		match kind:
			"spark": return "vents"
			"light": return "light_and_water"
			"spore": return "ozone_shield"
			"animal_germ": return "oxygen_enough"
		return "adapted"
	if t >= 70.0:
		return "too_hot"
	if t <= -20.0 or ice >= 0.85:
		return "no_light" if kind == "light" and ice >= 0.85 else "too_cold"
	match kind:
		"spark":
			# Sans vie concurrente, une étincelle échoue faute d'eau liquide (et de sources chaudes).
			return "competition" if biomass > 0.5 else "no_water"
		"light":
			return "competition" if biomass > 0.5 else "no_water"
		"spore":
			return "no_ozone" if ozone < Explainer.OZONE_SHIELD else ("no_land" if str(action.get("medium", "")) == "ocean" else "competition")
		"animal_germ":
			if oxygen < Explainer.OXYGEN_ANIMALS:
				return "low_oxygen"
			return "no_food" if biomass < 0.05 else "competition"
	var traits: Dictionary = action.get("traits", {})
	var medium := str(traits.get("habitat", traits.get("medium", "")))
	if medium in ["land", "terrestrial", "air"] and ozone < Explainer.OZONE_SHIELD:
		return "no_ozone"
	if oxygen < Explainer.OXYGEN_ANIMALS and str(traits.get("energy", "")) == "":
		return "low_oxygen"
	return "maladapted"


## Tous les codes de raison (pour les tests).
static func reason_codes(success: bool) -> Array:
	return (SUCCESSES if success else FAILURES).keys()
