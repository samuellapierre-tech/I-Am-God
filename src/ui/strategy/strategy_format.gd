extends RefCounted
## Textes de l'interface stratégique (purs, testés par tests/test_strategy_ui.gd).

const Rules := preload("res://src/strategy/strategy_rules.gd")

const GOLD := Color(1.0, 0.85, 0.5)
const DANGER := Color(1.0, 0.45, 0.38)
const SAFE := Color(0.55, 0.95, 0.62)
const DIM := Color(0.62, 0.66, 0.75)
const TEXT := Color(0.92, 0.93, 0.96)

const SAMAEL := Color(0.86, 0.5, 0.95)

## Libellés courts des Grands Œuvres pour la bande des pistes.
const WORK_SHORT := {life = "Vie", land = "Terres", mind = "Esprit", legacy = "Cité"}


## Durée lisible : « 850 ans », « 12 000 ans », « 3,4 Ma », « 1,2 Ga ».
static func years(y: float) -> String:
	y = maxf(y, 0.0)
	if y >= 1.0e9:
		return "%s Ga" % _decimal(y / 1.0e9)
	if y >= 1.0e6:
		return "%s Ma" % _decimal(y / 1.0e6)
	if y >= 1000.0:
		return "%s ans" % group(int(round(y)))
	return "%d an%s" % [int(ceil(y)), "s" if ceil(y) > 1.0 else ""]


static func _decimal(v: float) -> String:
	return ("%.1f" % v).replace(".", ",").trim_suffix(",0")


## 12345 -> « 12 345 » (espace fine insécable).
static func group(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## État d'une menace : texte et couleur.
static func threat_status(t: Dictionary, now_year: float) -> Array:
	match String(t.get("state", "pending")):
		"countered":
			return ["Contrée", SAFE]
		"struck":
			return ["A frappé", DANGER]
		"fizzled":
			return ["Dissipée", DIM]
	if not t.get("revealed", true):
		return ["Manche suivante", DIM]
	return ["Frappe dans %s" % years(float(t.strikes_year) - now_year), GOLD]


static func threat_target(t: Dictionary) -> String:
	var name := String(t.get("target_name", ""))
	return "Parcelle · %s" % name if name != "" else "Parcelle et alentours"


static func threat_title(t: Dictionary) -> String:
	var title := String(t.get("title", "?"))
	if t.get("cataclysm", false):
		title = "Cataclysme : " + title
	elif t.get("returning", false):
		title += " (retour)"
	return title


## Pastilles d'actions : « ●●●○ » (pleines = restantes).
static func pips(left: int, per_round: int) -> String:
	var n := maxi(per_round, left)
	return "●".repeat(clampi(left, 0, n)) + "○".repeat(maxi(0, n - left))


static func round_title(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	return "%s · %s · %s" % [r.get("name", ""), r.get("act_name", ""), r.get("stage", "")]


static func difficulty_text(id: String) -> String:
	var d := Rules.difficulty(id)
	return "%d actions par manche · %d Cataclysmes · défaite à %d effondrements
%s" % [
		d.actions, d.cataclysms, d.collapse_limit, d.samael]


## Raison de Samaël en clair (reason_code stable, voir samael.gd) ; "" si la carte n'est pas de lui.
static func samael_reason(code: String) -> String:
	if code.begins_with("targets_work_"):
		var w := code.trim_prefix("targets_work_")
		return "vise ton Grand Œuvre %s" % String(Rules.WORKS.get(w, {}).get("label", w))
	if code.begins_with("exploits_habit_"):
		return "tu contres toujours par %s : il l'esquive" % Rules.power_label(code.trim_prefix("exploits_habit_"))
	match code:
		"random":
			return "tirée au hasard"
		"max_damage":
			return "ce qui te fera le plus mal"
		"chain_risk":
			return "frappe une espèce déjà en chute"
		"budget_exhausted":
			return "tu n'auras plus d'action pour la contrer"
		"oracle_foresees":
			return "il a lu ce futur dans l'Oracle"
		"cataclysm":
			return "imposée par la pioche"
		"fallback":
			return "carte remplacée (époque)"
	return ""
