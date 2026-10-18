extends RefCounted
## Interface stratégique et branchement dans GameState : textes des cartes et des pistes, création de
## GameState.strategy par new_world, relais des signaux, avancée des manches dans _process.
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const Fmt := preload("res://src/ui/strategy/strategy_format.gd")
const Rules := preload("res://src/strategy/strategy_rules.gd")
const GameStateScript := preload("res://src/core/game_state.gd")


func test_format() -> String:
	var cases := [
		[Fmt.years(1.0), "1 an"], [Fmt.years(850.0), "850 ans"], [Fmt.years(12000.0), "12 000 ans"],
		[Fmt.years(3.4e6), "3,4 Ma"], [Fmt.years(2.0e6), "2 Ma"], [Fmt.years(1.24e9), "1,2 Ga"],
		[Fmt.pips(2, 4), "●●○○"], [Fmt.pips(5, 4), "●●●●●"], [Fmt.pips(0, 3), "○○○"],
	]
	for c in cases:
		if c[0] != c[1]:
			return "obtenu « %s », attendu « %s »" % [c[0], c[1]]
	var t := {title = "Sécheresse", target_name = "Tricératops", state = "pending", strikes_year = 1000.0}
	if Fmt.threat_status(t, 0.0)[0] != "Frappe dans 1 000 ans":
		return "compte à rebours : %s" % Fmt.threat_status(t, 0.0)[0]
	if Fmt.threat_status({state = "pending", strikes_year = -6.0e7, revealed = true}, -6.1e7)[0] != "Frappe dans 1 Ma":
		return "compte à rebours avant J.-C. : %s" % Fmt.threat_status({state = "pending", strikes_year = -6.0e7, revealed = true}, -6.1e7)[0]
	if Fmt.threat_status({state = "pending", revealed = false}, 0.0)[0] != "Manche suivante":
		return "menace de la manche suivante"
	t.state = "countered"
	if Fmt.threat_status(t, 0.0)[0] != "Contrée":
		return "état contrée"
	t.state = "struck"
	if Fmt.threat_status(t, 0.0)[0] != "A frappé":
		return "état frappée"
	if Fmt.threat_target(t) != "Parcelle · Tricératops":
		return "cible : %s" % Fmt.threat_target(t)
	if not Fmt.threat_title({title = "Impact cosmique", cataclysm = true}).begins_with("Cataclysme"):
		return "titre de Cataclysme"
	for id in Rules.DIFFICULTY_ORDER:
		if not Fmt.difficulty_text(id).contains(str(Rules.DIFFICULTIES[id].actions)):
			return "texte de difficulté %s" % id
	return ""


func test_game_state_wiring() -> String:
	var gs: Node = GameStateScript.new()
	var started := []
	var revealed := []
	gs.round_started.connect(func(r): started.append(r.index))
	gs.threat_revealed.connect(func(t): revealed.append(t.id))
	gs.new_world(7)
	if gs.strategy == null:
		gs.free()
		return "new_world ne crée pas GameState.strategy"
	if started != [1] or revealed.is_empty():
		gs.free()
		return "signaux de début de manche non relayés : %s / %s" % [started, revealed]
	gs.configure_strategy("prophet", "apocalypse")
	if gs.strategy.aspect != "prophet" or gs.strategy.actions_per_round != 3:
		gs.free()
		return "configure_strategy sans effet"
	# Contrat : champs et méthodes publics.
	for key in ["collapses", "collapse_limit", "vitality", "works", "deck_left"]:
		if not gs.strategy.tracks.has(key):
			gs.free()
			return "tracks.%s manquant" % key
	for key in ["index", "name", "stage", "starts_year", "ends_year", "threats"]:
		if not gs.strategy.round.has(key):
			gs.free()
			return "round.%s manquant" % key
	var t: Dictionary = gs.strategy.round.threats[0]
	for key in ["id", "kind", "title", "target", "strikes_year", "severity", "countered", "counters"]:
		if not t.has(key):
			gs.free()
			return "carte de menace : %s manquant" % key
	# Les manches avancent dans _process.
	gs.years_per_second = gs.sim.ideal_step_years() * gs.sim.max_substeps * 30.0
	for i in 200:
		gs._process(1.0 / 30.0)
		if gs.strategy.round.index >= 2:
			break
	var idx: int = gs.strategy.round.index
	gs.free()
	if idx < 2:
		return "aucune nouvelle manche après 200 images de _process"
	return ""
