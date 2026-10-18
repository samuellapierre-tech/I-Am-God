extends RefCounted
## Ouverture lente (GameState.opening_pace). Les durées réelles du prologue et de l'acte des dinosaures
## à x1 (rampe comprise) sont vérifiées par tests/test_sim_prologue.gd.
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const GameStateScript := preload("res://src/core/game_state.gd")


func test_opening_ramp() -> String:
	var a := GameStateScript.opening_pace(0.0)
	var b := GameStateScript.opening_pace(GameStateScript.OPENING_RAMP * 0.5)
	var c := GameStateScript.opening_pace(GameStateScript.OPENING_RAMP * 10.0)
	if not (a < b and b < c):
		return "la rampe ne monte pas : %f %f %f" % [a, b, c]
	if not is_equal_approx(a, GameStateScript.OPENING_PACE_START) or not is_equal_approx(c, GameStateScript.OPENING_PACE):
		return "bornes de la rampe incorrectes"
	return ""

