extends RefCounted
## Lecture tolérante de l'état global de la planète dans WorldSim, pour les shaders du globe.
## Chaque champ est lu seulement s'il existe (la session Planète en ajoute : ozone, sea_level…),
## avec un repli plausible sinon. Valeurs 0..1 sauf sea_level (unités d'élévation).


static func read(sim: Object) -> Dictionary:
	var out := {oxygen = 1.0, ozone = 1.0, greenhouse = 0.0, land_flora = 1.0, snowball = 0.0,
		sea_level = 0.0}
	if sim == null:
		return out
	out.oxygen = clampf(_num(sim, "oxygen", 1.0), 0.0, 1.5)
	# L'ozone suit l'oxygène tant que la simulation ne le calcule pas elle-même.
	out.ozone = clampf(_num(sim, "ozone", smoothstep(0.02, 0.4, out.oxygen)), 0.0, 1.0)
	var co2 := _num(sim, "co2", _num(sim, "_co2", 0.0))
	var methane := _num(sim, "methane", _num(sim, "_methane", 0.0))
	out.greenhouse = clampf((co2 + 0.15) / 0.65 + methane * 0.3 * (1.0 - smoothstep(0.03, 0.1, out.oxygen)), 0.0, 1.0)
	out.land_flora = clampf(_num(sim, "land_flora", 1.0), 0.0, 1.0)
	out.snowball = 1.0 if _num(sim, "snowball", 0.0) > 0.5 else 0.0
	out.sea_level = _num(sim, "sea_level", 0.0)
	return out


static func _num(sim: Object, field: String, fallback: float) -> float:
	if not field in sim:
		return fallback
	var v = sim.get(field)
	if v is bool:
		return 1.0 if v else 0.0
	if v is float or v is int:
		return float(v)
	return fallback


## Teinte de l'atmosphère (bord du disque) : brume orangée sans oxygène, bleu de Rayleigh avec.
static func atmosphere_color(state: Dictionary) -> Color:
	var ox := smoothstep(0.03, 0.4, float(state.get("oxygen", 1.0)))
	var c := Color(1.0, 0.55, 0.2).lerp(Color(0.3, 0.55, 1.0), ox)
	return c.lerp(Color(1.0, 0.7, 0.45), float(state.get("greenhouse", 0.0)) * 0.35)
