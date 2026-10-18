extends RefCounted
## Défis facultatifs de Samaël en mode Éternité (docs/STRATEGIE.md §10) : un objectif, une échéance
## (fin d'un chapitre), une petite récompense. Échouer ne coûte rien.
## Purs et déterministes (aléa fourni par l'appelant). Zéro anachronisme (§9) : un défi ne nomme que ce
## qui existe déjà (espèces vivantes de la parcelle, peuple conscient présent) et porte min_era /
## max_era comme les cartes de menace.
##
## Défi : {id, kind, title, text, reward ("action"|"work"), reward_text, issued_chapter,
##   deadline_chapter, state ("open"|"won"|"lost"), species_id, species_name, threshold, goal,
##   progress, era_at_issue}

const Eras := preload("res://src/sim/eras.gd")
const Rules := preload("res://src/strategy/strategy_rules.gd")

const KINDS := {
	keep_alive = {title = "Garde-les en vie", reward = "action", needs = "species"},
	vitality = {title = "Terre vivante", reward = "action"},
	counter = {title = "Bouclier", reward = "work"},
	quiet = {title = "Paix divine", reward = "action"},
	new_age = {title = "Un nouvel âge", reward = "work", max_era = Eras.LAST_ERA - 1},
	new_species = {title = "Naissance", reward = "action", needs = "land"},
	civilization = {title = "Qu'elle tienne", reward = "work", min_era = Eras.FIRST_SAPIENT_ERA, needs = "sapient"},
}

const REWARD_TEXT := {action = "+1 action au chapitre suivant", work = "un Grand Œuvre bonus pour ta collection"}


## Défis possibles maintenant. ctx : {era, species: [{species_id, density, role}], sapients: [id],
## names: {id: nom}, vitality, land: bool, budget}.
static func legal_kinds(ctx: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var era := int(ctx.get("era", 0))
	for k in KINDS:
		var def: Dictionary = KINDS[k]
		if era < int(def.get("min_era", -Rules.NO_ERA_LIMIT)) or era > int(def.get("max_era", Rules.NO_ERA_LIMIT)):
			continue
		match String(def.get("needs", "")):
			"species":
				if _wild(ctx).is_empty():
					continue
			"sapient":
				if ctx.get("sapients", []).is_empty():
					continue
			"land":
				if not ctx.get("land", false):
					continue
		if k == "vitality" and float(ctx.get("vitality", 0.0)) < 0.2:
			continue
		out.append(String(k))
	out.sort()
	return out


## Nouveau défi tiré au hasard parmi les défis légaux ({} si aucun).
static func make(rng: RandomNumberGenerator, ctx: Dictionary, chapter: int, id: int) -> Dictionary:
	var kinds := legal_kinds(ctx)
	if kinds.is_empty():
		return {}
	var kind := kinds[rng.randi_range(0, kinds.size() - 1)]
	var def: Dictionary = KINDS[kind]
	var c := {
		id = id, kind = kind, title = def.title, reward = def.reward, reward_text = REWARD_TEXT[def.reward],
		issued_chapter = chapter, deadline_chapter = chapter + 1, state = "open", species_id = -1,
		species_name = "", threshold = 0.0, goal = 0, progress = 0, era_at_issue = int(ctx.get("era", 0)),
	}
	match kind:
		"keep_alive":
			var wild := _wild(ctx)
			var pick: Dictionary = wild[rng.randi_range(0, wild.size() - 1)]
			c.species_id = int(pick.species_id)
			c.species_name = String(ctx.names.get(c.species_id, ""))
			c.text = "Garde les %s en vie jusqu'à la fin du chapitre %d." % [c.species_name, c.deadline_chapter]
		"vitality":
			c.threshold = maxf(0.1, floorf(float(ctx.vitality) * 0.7 * 20.0) / 20.0)
			c.text = "Garde la vitalité de la parcelle au-dessus de %d %% jusqu'à la fin du chapitre %d." % [
				int(round(c.threshold * 100.0)), c.deadline_chapter]
		"counter":
			c.deadline_chapter = chapter
			c.goal = clampi(int(ctx.get("budget", 4)) / 2, 1, 2)
			c.text = "Contre %d menace%s avant la fin de ce chapitre." % [c.goal, "s" if c.goal > 1 else ""]
		"quiet":
			c.deadline_chapter = chapter
			c.text = "Laisse le monde en paix : aucun pouvoir pendant ce chapitre."
		"new_age":
			c.deadline_chapter = chapter + 2
			c.text = "Fais entrer le monde dans un nouvel âge avant la fin du chapitre %d." % c.deadline_chapter
		"new_species":
			c.text = "Qu'une espèce nouvelle apparaisse sur la parcelle avant la fin du chapitre %d." % c.deadline_chapter
		"civilization":
			var best := -1
			for sid in ctx.sapients:
				if best < 0 or int(sid) < best:
					best = int(sid)
			c.species_id = best
			c.species_name = String(ctx.names.get(best, ""))
			c.text = "Garde la civilisation des %s debout jusqu'à la fin du chapitre %d." % [c.species_name, c.deadline_chapter]
	return c


## Évaluation en cours de chapitre : "won", "lost" ou "" (encore ouvert).
## now : {alive: Callable(id) -> bool, sapient: Callable(id) -> bool, vitality, era, counters (contres
## réussis depuis l'émission), powers (pouvoirs lancés depuis l'émission), new_species: bool}
static func check(c: Dictionary, now: Dictionary) -> String:
	match String(c.kind):
		"keep_alive":
			return "lost" if not now.alive.call(int(c.species_id)) else ""
		"civilization":
			return "lost" if not now.sapient.call(int(c.species_id)) else ""
		"vitality":
			return "lost" if float(now.vitality) < float(c.threshold) else ""
		"counter":
			c.progress = int(now.counters)
			return "won" if int(c.progress) >= int(c.goal) else ""
		"quiet":
			return "lost" if int(now.powers) > 0 else ""
		"new_age":
			return "won" if int(now.era) != int(c.era_at_issue) else ""
		"new_species":
			return "won" if now.new_species else ""
	return ""


## À l'échéance (fin du chapitre deadline_chapter) : les défis « tenir jusqu'à » sont gagnés,
## les défis « atteindre » sont perdus.
static func at_deadline(c: Dictionary) -> String:
	return "won" if String(c.kind) in ["keep_alive", "civilization", "vitality", "quiet"] else "lost"


static func _wild(ctx: Dictionary) -> Array:
	var out := []
	for s in ctx.get("species", []):
		if String(s.role) != "sapient" and String(ctx.get("names", {}).get(int(s.species_id), "")) != "":
			out.append(s)
	return out
