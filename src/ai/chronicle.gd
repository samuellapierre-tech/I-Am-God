extends RefCounted
## Le fil continu : quand rien de marquant n'arrive, le narrateur écrit une phrase sur la parcelle
## (environ toutes les 8 à 15 s, voir narrator.gd). Fonctions pures : le contexte est fourni par l'appelant.
##
## ctx : {era, year, snapshot (ParcelNarrator.snapshot), species: [{id, name, clade, diet, size,
##        intelligence, sapient, alive}], divine: [{type, year, species_id}], choices: [...], mode: {...}}
## ambient(ctx) -> {text, kind, source: "ambient", ...} ; kind : "fact" (fait réel, facts/), "scene"
## (état de la parcelle), "invention" (monde divergent, inventor.gd), "divergence" (la bascule, dite une fois),
## "memory" (rappel d'un choix passé de Dieu, ctx.choices de game_master.gd).
## ctx.mode (divergence.gd) : {real, label, reasons, just_diverged…} ; absent = monde réel.
## ctx.recent_events : types d'événements récents (bruts et canoniques), pour choisir des faits à propos.
## Le narrateur parle à la première personne (« je ») et tutoie Dieu.

const Procedural := preload("res://src/ai/procedural_narrator.gd")
const ParcelNarrator := preload("res://src/ai/parcel_narrator.gd")
const AiConfig := preload("res://src/ai/ai_config.gd")
const FactBase := preload("res://src/ai/facts/fact_base.gd")
const Inventor := preload("res://src/ai/inventor.gd")
const GameMaster := preload("res://src/ai/game_master.gd")
const Epoch := preload("res://src/ai/epoch.gd")

## Part des phrases d'ambiance consacrées aux visions des âges inventés (monde divergent, futur sans fin).
const VISION_SHARE := 0.3
## Part des phrases d'ambiance qui rappellent un choix passé de Dieu (quand il y en a).
const MEMORY_SHARE := 0.12

## Part des phrases d'ambiance consacrées aux faits réels quand il y en a (le reste : scènes).
const FACT_SHARE := 0.65
## Part des phrases d'ambiance inventées quand le monde a divergé (le reste : scènes).
const INVENTION_SHARE := 0.6
## Nombre de faits récents qu'on ne répète pas.
const FACT_MEMORY := 12

## Scènes de la parcelle. Emplacements de ParcelNarrator ({terre}, {ciel}, {espece}, {fin}…) plus
## {nombre}, {global}, {narrateur}. Accord : [espece:singulier|pluriel].
const SCENE_TEMPLATES := {
	"herbivore": [
		"Sur {terre}, {espece} [espece:broute|broutent] sans hâte ; je compte {nombre} silhouettes.",
		"{espece} [espece:mène|mènent] [espece:sa|leur] vie tranquille sur {terre} {ciel}.",
		"Je regarde {espece} paître sur {terre} : rien ne presse, pour l'instant.",
	],
	"carnivore": [
		"{espece} [espece:rôde|rôdent] sur {terre} ; les autres bêtes ne [espece:la|les] quittent pas des yeux.",
		"J'observe {espece} : [espece:elle guette|ils guettent] la moindre proie sur {terre}.",
		"Sur {terre}, {espece} [espece:chasse|chassent] {ciel} ; je compte {nombre} silhouettes.",
	],
	"omnivore": [
		"{espece} [espece:fouille|fouillent] {terre} en quête de tout ce qui se mange.",
		"Sur {terre}, {espece} [espece:grignote|grignotent] ce qui se présente {ciel}.",
	],
	"sapient": [
		"{espece} [espece:vaque|vaquent] à [espece:ses|leurs] affaires sur {terre} ; [espece:elle ne sait|ils ne savent] pas que tu regardes.",
		"Je note dans mon registre : {nombre} silhouettes de {espece} sur {terre} aujourd'hui.",
		"Sur {terre}, {espece} [espece:travaille|travaillent] {ciel}, sans lever les yeux vers toi.",
	],
	"rising": [
		"{espece} [espece:prospère|prospèrent] sur {terre} : chaque saison, [espece:elle gagne|ils gagnent] du terrain.",
		"Je vois de plus en plus de silhouettes de {espece} sur {terre}.",
	],
	"falling": [
		"{espece} [espece:se fait|se font] plus [espece:rare|rares] sur {terre} ; je ne sais pas encore si c'est passager.",
		"Chez {espece}, je compte moins de silhouettes qu'hier sur {terre}. Je le note, au cas où.",
	],
	"empty": [
		"Rien ne bouge sur {terre} ; même le vent semble attendre.",
		"Pas une bête en vue sur {terre}. Je garde la plume levée.",
	],
	"climate": [
		"Il fait {temp} sur {terre}, {global}.",
		"Je relève {temp} sur {terre} {ciel}, {global}.",
	],
	"view": [
		"Je regarde {terre} : {vue}.",
		"Rien de neuf sur {terre} : {vue}, et je l'écris quand même.",
	],
}

var rng := RandomNumberGenerator.new()
var _seed := 0
var _count := 0
var _recent_texts: Array[String] = []
var _recent_facts: Array[String] = []
## Mémoire anti-répétition partagée (variety.gd), posée par le narrateur ; null = sans. Avec elle,
## une phrase déjà dite récemment n'est jamais redite : on essaie une autre sorte de phrase, sinon on se tait.
var variety: RefCounted = null
## Époque effective de la phrase en cours (epoch.gd) : rien d'anachronique.
var _epoch := Epoch.LAST
var _parcel: ParcelNarrator
## Mémoire des inventions (profils des espèces et des peuples), partagée avec le narrateur.
var inventor: Inventor


func _init(p_seed: int = -1) -> void:
	if p_seed >= 0:
		_seed = p_seed
	else:
		rng.randomize()
		_seed = rng.randi()
	_parcel = ParcelNarrator.new(_seed + 1)
	inventor = Inventor.new(_seed + 3)


## Une phrase pour le fil continu.
func ambient(ctx: Dictionary) -> Dictionary:
	_count += 1
	rng.seed = hash([_seed, _count])
	_epoch = Epoch.current(ctx)
	var mode: Dictionary = ctx.get("mode", {})
	inventor.variety = variety
	var real := bool(mode.get("real", true))
	var past: Array = ctx.get("choices", [])
	# Sortes de phrases à essayer, la préférée d'abord, puis les autres en repli.
	var kinds := []
	if bool(mode.get("just_diverged", false)):
		kinds = ["divergence"]
	else:
		if not past.is_empty() and rng.randf() < MEMORY_SHARE:
			kinds.append("memory")
		if not real:
			if rng.randf() < VISION_SHARE:
				kinds.append("vision")
			if rng.randf() < INVENTION_SHARE:
				kinds.append("invention")
		elif rng.randf() < FACT_SHARE:
			kinds.append("fact")
		kinds.append("scene")
		if variety != null:
			# Repli : toutes les autres sortes, plutôt qu'une redite.
			for k in (["vision", "invention"] if not real else ["fact"]) + ["memory", "scene"]:
				if not k in kinds:
					kinds.append(k)
	var line := {}
	for k in kinds:
		match k:
			"divergence", "invention":
				line = inventor.line(ctx)
			"vision":
				line = inventor.vision(ctx)
			"memory":
				if not past.is_empty():
					var c: Dictionary = past[rng.randi() % past.size()]
					line = {"text": GameMaster.memory_line(c), "kind": "memory", "source": "ambient", "species_id": int(c.get("species_id", -1))}
			"fact":
				line = fact(ctx)
			"scene":
				line = scene(ctx)
		var text := str(line.get("text", ""))
		if text != "" and (variety == null or not variety.seen(text)):
			break
		line = {}
	if line.is_empty():
		return {}
	if variety != null:
		variety.remember(str(line["text"]))
	line["world_mode"] = str(mode.get("label", "réel"))
	return _remember(line)


## Un fait réel de l'époque, vrai à cette date et si possible lié à ce qu'on voit ; {} s'il n'y en a pas.
func fact(ctx: Dictionary) -> Dictionary:
	var era := FactBase.stage_for(ctx.get("era", ""), ctx.get("year", null))
	# Avec une mémoire de variété, un fait dit récemment (même il y a longtemps dans la partie) attend son tour.
	var seen_ids := []
	if variety != null:
		for f in FactBase.candidates(era, ctx.get("year", null)):
			if variety.seen(str(f["t"])):
				seen_ids.append(f["id"])
	# On ne répète aucun des derniers faits ; s'il y en a peu de vrais à cette date, la mémoire se
	# réduit d'autant, sans jamais redire le tout dernier.
	var available := FactBase.candidates(era, ctx.get("year", null)).size()
	var keep := maxi(1, mini(FACT_MEMORY, available - 1))
	var recent := _recent_facts.slice(maxi(0, _recent_facts.size() - keep))
	var f := FactBase.pick(era, ctx.get("year", null), situation(ctx), recent + seen_ids, rng)
	if f.is_empty():
		return {}
	_recent_facts.append(str(f["id"]))
	while _recent_facts.size() > FACT_MEMORY:
		_recent_facts.pop_front()
	return {"text": str(f["t"]), "kind": "fact", "fact_id": str(f["id"]), "source": "ambient"}


## Ce que l'on voit, pour choisir les faits : clades présents, biome, usage du sol, événements récents.
static func situation(ctx: Dictionary) -> Dictionary:
	var snap: Dictionary = ctx.get("snapshot", {})
	var clades := []
	for f in snap.get("fauna", []):
		if str(f.get("clade", "")) != "":
			clades.append(str(f["clade"]))
	return {
		"clades": clades, "biome": str(snap.get("biome", "")), "land_use": str(snap.get("land_use", "")),
		"events": ctx.get("recent_events", []),
	}


## Une scène tirée de l'état de la parcelle (faune, tendance, chaleur, usage du sol).
func scene(ctx: Dictionary) -> Dictionary:
	var snap: Dictionary = ctx.get("snapshot", {})
	var fauna: Array = snap.get("fauna", [])
	var kinds := ["view", "climate"]
	var subject := {}
	if fauna.is_empty():
		kinds.append("empty")
	else:
		subject = fauna[rng.randi() % fauna.size()]
		var role := str(subject.get("role", "omnivore"))
		kinds.append(role if SCENE_TEMPLATES.has(role) else "omnivore")
		kinds.append(role if SCENE_TEMPLATES.has(role) else "omnivore")  # la faune d'abord
		match int(subject.get("trend", 0)):
			1: kinds.append("rising")
			-1: kinds.append("falling")
	var kind: String = kinds[rng.randi() % kinds.size()]
	var m := {"kind": "scene", "species_id": int(subject.get("species_id", -1)),
		"species_name": str(subject.get("name", "")), "role": str(subject.get("role", "")), "snapshot": snap}
	var text := _render_avoiding_repeat(SCENE_TEMPLATES[kind], m, ctx, {
		"nombre": str(int(subject.get("count", 0))),
		"global": _compare_global(snap),
	})
	if text == "":
		return {}
	return {"text": text, "kind": "scene", "scene": kind, "source": "ambient", "species_id": m["species_id"]}


## Rend un gabarit choisi au hasard, en évitant de répéter un texte récent.
func _render_avoiding_repeat(templates: Array, m: Dictionary, ctx: Dictionary, extra: Dictionary) -> String:
	var text := ""
	var fallback := ""
	var family := "scene:%d:%s" % [templates.size(), str(templates[0]).substr(0, 24)]
	var order: Array = variety.order(family, templates.size(), rng) if variety != null else []
	for attempt in (templates.size() * 4 if variety != null else 10):
		var slots := _parcel.slots_for(ctx.get("era", ""), m, m.get("snapshot", {}), ctx.get("year", null))
		slots.merge(extra, true)
		slots["narrateur"] = AiConfig.NARRATOR_NAME
		var i: int = order[attempt % order.size()] if variety != null else rng.randi() % templates.size()
		text = ParcelNarrator.render(templates[i], slots)
		if not Epoch.is_clean(text, _epoch):
			continue
		if variety != null:
			if variety.seen(text):
				continue
			variety.used(family, i)
			return text
		fallback = text
		if not text in _recent_texts:
			return text
	if variety != null:
		return ""
	return fallback if fallback != "" else ParcelNarrator.render(ParcelNarrator.SAFE_TEMPLATE, _parcel.slots_for(ctx.get("era", ""), m, m.get("snapshot", {}), ctx.get("year", null)))


static func _compare_global(snap: Dictionary) -> String:
	if not (snap.has("temperature_c") and snap.has("global_temperature_c")):
		return "comme ailleurs"
	var local := float(snap["temperature_c"])
	var world := float(snap["global_temperature_c"])
	if local > world + 3.0:
		return "plus chaud que la moyenne du monde (%d °C)" % int(round(world))
	if local < world - 3.0:
		return "plus froid que la moyenne du monde (%d °C)" % int(round(world))
	return "à peu près la moyenne du monde"


func _remember(line: Dictionary) -> Dictionary:
	_recent_texts.append(str(line.get("text", "")))
	if _recent_texts.size() > 12:
		_recent_texts.pop_front()
	return line
