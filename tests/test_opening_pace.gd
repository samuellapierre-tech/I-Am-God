extends RefCounted
## Ouverture lente (GameState.opening_pace) : on a le temps de voir vivre les dinosaures.
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const GameStateScript := preload("res://src/core/game_state.gd")
const WorldSim := preload("res://src/sim/world_sim.gd")
const MapMath := preload("res://src/map/map_math.gd")


func test_opening_ramp() -> String:
	var a := GameStateScript.opening_pace(0.0)
	var b := GameStateScript.opening_pace(GameStateScript.OPENING_RAMP * 0.5)
	var c := GameStateScript.opening_pace(GameStateScript.OPENING_RAMP * 10.0)
	if not (a < b and b < c):
		return "la rampe ne monte pas : %f %f %f" % [a, b, c]
	if not is_equal_approx(a, GameStateScript.OPENING_PACE_START) or not is_equal_approx(c, GameStateScript.OPENING_PACE):
		return "bornes de la rampe incorrectes"
	return ""


func test_first_minute_is_watchable() -> String:
	# À x1, la première minute de jeu couvre moins de 2 millions d'années (avant : 60 Ma).
	var sim := WorldSim.new(7)
	var base := MapMath.base_years_per_second(sim.ideal_step_years())
	var years := 0.0
	for s in 60:
		years += base * GameStateScript.opening_pace(float(s))
	if years > 2_000_000.0:
		return "première minute trop rapide : %.0f ans" % years
	return ""
