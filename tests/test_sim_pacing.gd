extends RefCounted
## Régression : en jeu réel (boucle du HUD, vitesse x5, 60 images/s, rythme fourni par la
## simulation), une civilisation doit émerger et atteindre l'Antiquité pour toute graine,
## avec ou sans météore, en un nombre d'images borné.

const WorldSim := preload("res://src/sim/world_sim.gd")
const MapMath := preload("res://src/map/map_math.gd")

const FPS := 60.0
const SPEED := 5.0
const METEOR_FRAME := 30
## ~66 s de jeu à x5 : Mésozoïque/Cénozoïque (~10-15 s) + Préhistoire (~12 s) + marge.
const MAX_FRAMES := 4000
const SEEDS := [17, 2024, 987654]


## Renvoie {sapience_frame, sapience_year, clade, antiquity_frame, antiquity_year} (-1 si jamais).
func _play(seed_value: int, meteor: bool) -> Dictionary:
	var sim := WorldSim.new(seed_value)
	var res := {sapience_frame = -1, sapience_year = 0.0, clade = "", antiquity_frame = -1, antiquity_year = 0.0}
	for frame in MAX_FRAMES:
		if meteor and frame == METEOR_FRAME:
			sim.apply_divine_action({type = "meteor", region = Vector2i(60, 50), species_id = -1, radius = 12})
		# Exactement ce que font hud.gd (_process) puis GameState._process.
		var years_per_second := MapMath.base_years_per_second(sim.ideal_step_years()) * SPEED
		for ev in sim.step(years_per_second / FPS):
			if ev.type == "sapience" and res.sapience_frame < 0:
				res.sapience_frame = frame
				res.sapience_year = ev.year
				res.clade = sim.species[ev.species_id].traits.clade
		if sim.era_index() >= 3:
			res.antiquity_frame = frame
			res.antiquity_year = sim.year
			break
	return res


func test_civilisation_emerges_in_real_play() -> String:
	for s in SEEDS:
		for meteor in [false, true]:
			var r := _play(s, meteor)
			print("  graine %d %s : sapience image %d (%.1f Ma, %s), Antiquité image %d (an %d)" % [
				s, "avec météore" if meteor else "sans météore", r.sapience_frame, r.sapience_year / 1e6,
				r.clade, r.antiquity_frame, r.antiquity_year])
			if r.sapience_frame < 0:
				return "graine %d (météore %s) : aucune sapience en %d images" % [s, meteor, MAX_FRAMES]
			if r.antiquity_frame < 0:
				return "graine %d (météore %s) : Antiquité non atteinte en %d images" % [s, meteor, MAX_FRAMES]
			if meteor and r.clade == "dinosaure":
				return "graine %d : sapience dinosaurienne malgré le météore" % s
	return ""


func test_sapient_eras_last_about_a_minute() -> String:
	# À x1, une ère sapiente doit durer de l'ordre d'une minute (20 pas idéaux/s, 1200 pas/ère).
	var sim := WorldSim.new(17)
	var guard := 0
	while sim.era_index() < 2 and guard < 5000:
		guard += 1
		sim.step(sim.ideal_step_years() * sim.max_substeps)
	if sim.era_index() < 2:
		return "pas de sapience"
	var era := sim.era_index()
	var seconds := 0.0
	while sim.era_index() == era and seconds < 600.0:
		# Pas d'une demi-seconde de jeu à x1 (10 pas idéaux), pour rester rapide.
		sim.step(MapMath.base_years_per_second(sim.ideal_step_years()) * 0.5)
		seconds += 0.5
	print("  ère %s : %.0f s de jeu à x1" % [WorldSim.ERAS[era], seconds])
	if seconds < 20.0 or seconds > 180.0:
		return "durée d'ère hors cible : %.0f s" % seconds
	return ""
