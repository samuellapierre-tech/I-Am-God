extends RefCounted
## Le monde suit-il encore l'histoire réelle de la Terre ? Tant que oui, le narrateur raconte des faits
## vrais (facts/) ; dès qu'il diverge, il invente (inventor.gd). La divergence est définitive.
##
## Critères (assess) :
## - dinosaurs_survived : des dinosaures non aviens ou des ptérosaures vivent encore après la fin du Crétacé ;
## - non_human_sapient : une espèce intelligente qui n'est pas issue des primates ;
## - early_sapience : une espèce intelligente bien avant l'apparition du genre humain ;
## - divine_creation : Dieu a éveillé ou créé une espèce (uplift, spawn_species) ;
## - era_out_of_time : l'ère atteinte ne correspond pas du tout à la date (civilisation en avance ou en retard) ;
## - future : la date dépasse notre présent, ou le monde est entré dans une ère future.

const PRESENT_YEAR := 2026.0
## Au-delà, des dinosaures non aviens vivants sont une anomalie (l'impact a eu lieu il y a 66 Ma).
const DINOSAUR_CUTOFF := -65_000_000.0
## Le genre humain apparaît vers -2,8 Ma : une sapience plus ancienne n'a rien de réel.
const EARLY_SAPIENCE_YEAR := -2_500_000.0
const NON_AVIAN_CLADES := ["dinosaure", "ptérosaure"]
const HUMAN_CLADES := ["primate"]
const DIVERGENT_ACTS := ["uplift", "spawn_species", "spawn"]
const FUTURE_ERAS := ["Cyberpunk", "Post-singularité"]
## Fenêtres (larges) où chaque ère est plausible dans l'histoire réelle.
const ERA_WINDOWS := {
	"Mésozoïque": [-1.0e9, -65_000_000.0],
	"Cénozoïque": [-66_500_000.0, PRESENT_YEAR],
	"Préhistoire": [-2_500_000.0, -1_500.0],
	"Antiquité": [-10_000.0, 1_000.0],
	"Moyen Âge": [0.0, 1_700.0],
	"Renaissance": [1_100.0, 1_900.0],
	"Industriel": [1_500.0, PRESENT_YEAR],
	"Moderne": [1_800.0, PRESENT_YEAR],
}

## Raisons lisibles, pour le narrateur et pour le prompt LLM.
const REASON_TEXTS := {
	"dinosaurs_survived": "les dinosaures ont survécu à la fin du Crétacé",
	"non_human_sapient": "une espèce intelligente non humaine est apparue",
	"early_sapience": "l'intelligence est apparue des millions d'années trop tôt",
	"divine_creation": "tu as toi-même éveillé ou façonné une espèce",
	"era_out_of_time": "la civilisation ne suit plus le calendrier de la vraie Terre",
	"future": "le monde a dépassé notre présent",
}

var divergent := false
var criteria: Array[String] = []
var since_year: Variant = null
var _announced := false


## Critères de divergence vérifiés par ce contexte ({era, year, species: [{clade, sapient, alive, name}], divine: [{type}]}).
static func assess(ctx: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var year: Variant = ctx.get("year", null)
	var has_year := typeof(year) in [TYPE_INT, TYPE_FLOAT]
	var y := float(year) if has_year else 0.0
	var era := str(ctx.get("era", ""))
	for sp in ctx.get("species", []):
		if not bool(sp.get("alive", true)):
			continue
		var clade := str(sp.get("clade", ""))
		if has_year and y > DINOSAUR_CUTOFF and clade in NON_AVIAN_CLADES and not "dinosaurs_survived" in out:
			out.append("dinosaurs_survived")
		if bool(sp.get("sapient", false)):
			if not clade in HUMAN_CLADES and not "non_human_sapient" in out:
				out.append("non_human_sapient")
			if has_year and y < EARLY_SAPIENCE_YEAR and not "early_sapience" in out:
				out.append("early_sapience")
	for act in ctx.get("divine", []):
		var t := str(act.get("type", "")) if act is Dictionary else str(act)
		if t in DIVERGENT_ACTS and not "divine_creation" in out:
			out.append("divine_creation")
	if era in FUTURE_ERAS or (has_year and y > PRESENT_YEAR):
		out.append("future")
	elif has_year and ERA_WINDOWS.has(era):
		var w: Array = ERA_WINDOWS[era]
		if y < float(w[0]) or y > float(w[1]):
			out.append("era_out_of_time")
	return out


## Met à jour l'état (définitif une fois divergent) et renvoie le mode à joindre au contexte :
## {real: bool, label: "réel"|"divergent", criteria: [...], reasons: [textes], just_diverged: bool, since_year}.
func update(ctx: Dictionary) -> Dictionary:
	for c in assess(ctx):
		if not c in criteria:
			criteria.append(c)
	if not criteria.is_empty() and not divergent:
		divergent = true
		since_year = ctx.get("year", null)
	var just := divergent and not _announced
	if just:
		_announced = true
	return mode(just)


func mode(just_diverged := false) -> Dictionary:
	var reasons := []
	for c in criteria:
		reasons.append(REASON_TEXTS.get(c, c))
	return {
		"real": not divergent, "label": "divergent" if divergent else "réel", "criteria": criteria.duplicate(),
		"reasons": reasons, "just_diverged": just_diverged, "since_year": since_year,
	}
