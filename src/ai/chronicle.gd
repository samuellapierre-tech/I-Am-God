extends RefCounted
## Le fil continu : quand rien de marquant n'arrive, le narrateur écrit une phrase sur la parcelle
## (environ toutes les 8 à 15 s, voir narrator.gd). Fonctions pures : le contexte est fourni par l'appelant.
##
## ctx : {era, year, snapshot (ParcelNarrator.snapshot), species: [{id, name, clade, diet, size,
##        intelligence, sapient, alive}], divine: [{type, year, species_id}], choices: [...], mode: {...}}
## ambient(ctx) -> {text, kind, source: "ambient", ...} ; kind : "scene" (état de la parcelle).
## Le narrateur parle à la première personne (« je ») et tutoie Dieu.

const Procedural := preload("res://src/ai/procedural_narrator.gd")
const ParcelNarrator := preload("res://src/ai/parcel_narrator.gd")
const AiConfig := preload("res://src/ai/ai_config.gd")

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
		"Je compte moins de {espece} qu'hier sur {terre}. Je le note, au cas où.",
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
var _parcel: ParcelNarrator


func _init(p_seed: int = -1) -> void:
	if p_seed >= 0:
		_seed = p_seed
	else:
		rng.randomize()
		_seed = rng.randi()
	_parcel = ParcelNarrator.new(_seed + 1)


## Une phrase pour le fil continu.
func ambient(ctx: Dictionary) -> Dictionary:
	_count += 1
	rng.seed = hash([_seed, _count])
	var line := scene(ctx)
	return _remember(line)


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
	return {"text": text, "kind": "scene", "scene": kind, "source": "ambient", "species_id": m["species_id"]}


## Rend un gabarit choisi au hasard, en évitant de répéter un texte récent.
func _render_avoiding_repeat(templates: Array, m: Dictionary, ctx: Dictionary, extra: Dictionary) -> String:
	var text := ""
	for _attempt in 4:
		var slots := _parcel.slots_for(Procedural.era_key(ctx.get("era", "")), m, m.get("snapshot", {}), ctx.get("year", null))
		slots.merge(extra, true)
		slots["narrateur"] = AiConfig.NARRATOR_NAME
		text = ParcelNarrator.render(templates[rng.randi() % templates.size()], slots)
		if not text in _recent_texts:
			break
	return text


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
