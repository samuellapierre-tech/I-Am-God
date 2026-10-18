extends RefCounted
## Parcelle suivie par le joueur : un morceau de terrain grand comme l'écran, au cœur d'une cellule
## de la grille WorldSim. Tout le jeu se regarde là : les dinosaures qui passent, la forêt qui
## recule, les premiers champs, la ville, les ruines… ou rien.
##
## CONTRAT (voir docs/ARCHITECTURE.md § Parcelle). Cette version est une implémentation minimale
## dérivée des grilles de WorldSim, pour que la vue parcelle et le HUD puissent avancer.
## La branche feature/simulation-core la remplace par une vraie simulation locale
## (même API, champs en plus autorisés, jamais en moins).

const WorldSim := preload("res://src/sim/world_sim.gd")

## Usages du sol, du plus sauvage au plus artificiel (puis déclin).
const LAND_USES := [
	"ocean", "ice", "wild", "crater", "flooded",
	"camp", "pasture", "farmland", "village", "town", "city", "megacity", "arcology",
	"ruins", "rewild",
]
const MAX_FAUNA := 6
const MAX_VISIBLE := 40
const HISTORY_SIZE := 512
## Rayon (en cellules) dans lequel on cherche les espèces qui passent par la parcelle.
const NEIGHBOR_RADIUS := 3

var world: WorldSim
var cell := Vector2i.ZERO
var year := 0.0

var biome := ""
var land_use := "wild"
## Température locale et moyenne mondiale, en °C.
var temperature_c := 0.0
var global_temperature_c := 0.0
## 0 .. 1
var vegetation := 0.0
var water := 0.0
var tech := 0.0
## [{species_id, name, count (individus visibles 0..MAX_VISIBLE), density (0..1),
##   trend (-1, 0, 1), role ("herbivore"|"carnivore"|"omnivore"|"sapient"), size (0..1), clade}]
var fauna: Array[Dictionary] = []
## [{kind: "field"|"hut"|"road"|"building"|"tower"|"ruin", pos: Vector2 (0..1), size: float}]
var structures: Array[Dictionary] = []
## Échantillons pour les statistiques à l'écran, du plus ancien au plus récent :
## [{year, temperature_c, global_temperature_c, population_total, population: {species_id: count}}]
var history: Array[Dictionary] = []

var _prev_counts := {}


func _init(p_world: WorldSim, p_cell: Vector2i) -> void:
	world = p_world
	cell = Vector2i(posmod(p_cell.x, WorldSim.WIDTH), clampi(p_cell.y, 0, WorldSim.HEIGHT - 1))
	update([])


static func to_celsius(t: float) -> float:
	return -30.0 + 75.0 * t


## Recalcule l'état de la parcelle après un pas de WorldSim. Renvoie les événements propres à la
## parcelle (même format que WorldSim : {year, type, region, species_id, summary, cause_id, id}).
func update(world_events: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	year = world.year
	var i := _index(cell)
	biome = WorldSim.BIOME_NAMES[world.biome[i]] if world.biome.size() > i else ""
	temperature_c = to_celsius(world.temperature[i])
	global_temperature_c = _global_temperature()
	water = clampf(world.moisture[i], 0.0, 1.0) if world.moisture.size() > i else 0.0
	tech = world.tech[i]
	vegetation = clampf(water * (1.0 - absf(world.temperature[i] - 0.6) * 1.6), 0.0, 1.0)

	var old_use := land_use
	land_use = _land_use(i, world_events)
	if land_use != old_use:
		out.append(_event("land_use", "La parcelle devient : %s." % land_use))

	_update_fauna(out)
	_update_structures()
	_record()
	return out


func _index(c: Vector2i) -> int:
	return c.y * WorldSim.WIDTH + c.x


func _global_temperature() -> float:
	var t := world.temperature
	var s := 0.0
	var step := 37  # échantillonnage : la moyenne exacte n'apporte rien à l'affichage
	var n := 0
	for k in range(0, t.size(), step):
		s += t[k]
		n += 1
	return to_celsius(s / maxf(1.0, n))


func _land_use(i: int, world_events: Array) -> String:
	for e in world_events:
		if e.get("region", Vector2i(-999, -999)) == cell:
			match String(e.get("type", "")):
				"meteor":
					return "crater"
				"flood":
					return "flooded"
	if world.elevation[i] < 0.0:
		return "ocean"
	if world.temperature[i] < 0.08:
		return "ice"
	var t := world.tech[i]
	var sapient := _cell_sapient(i)
	if not sapient:
		return "rewild" if land_use in ["ruins", "rewild"] else ("ruins" if t > 0.15 else "wild")
	if t < 0.05:
		return "camp"
	if t < 0.12:
		return "pasture"
	if t < 0.25:
		return "farmland"
	if t < 0.4:
		return "village"
	if t < 0.55:
		return "town"
	if t < 0.75:
		return "city"
	if t < 0.92:
		return "megacity"
	return "arcology"


func _cell_sapient(i: int) -> bool:
	var id: int = world.dominant_species[i]
	return id >= 0 and world.species.has(id) and bool(world.species[id].get("sapient", false))


func _update_fauna(out: Array[Dictionary]) -> void:
	var density := {}
	for dy in range(-NEIGHBOR_RADIUS, NEIGHBOR_RADIUS + 1):
		for dx in range(-NEIGHBOR_RADIUS, NEIGHBOR_RADIUS + 1):
			var c := Vector2i(posmod(cell.x + dx, WorldSim.WIDTH), clampi(cell.y + dy, 0, WorldSim.HEIGHT - 1))
			var j := _index(c)
			var id: int = world.dominant_species[j]
			if id < 0:
				continue
			var falloff := 1.0 / (1.0 + float(absi(dx) + absi(dy)))
			density[id] = maxf(float(density.get(id, 0.0)), world.population[j] * falloff)
	var ids := density.keys()
	ids.sort_custom(func(a, b): return density[a] > density[b] or (density[a] == density[b] and a < b))
	fauna.clear()
	var counts := {}
	for id in ids.slice(0, MAX_FAUNA):
		var info: Dictionary = world.species[id]
		var traits: Dictionary = info.get("traits", {})
		var d: float = density[id]
		var count := int(round(d * MAX_VISIBLE))
		if count <= 0:
			continue
		var prev: int = _prev_counts.get(id, count)
		var trend := 0 if absi(count - prev) <= 1 else signi(count - prev)
		if not _prev_counts.has(id) and not history.is_empty():
			out.append(_event("arrival", "%s arrivent sur la parcelle." % info.get("name", "?"), id))
		counts[id] = count
		fauna.append({
			species_id = id, name = String(info.get("name", "?")), count = count, density = d,
			trend = trend, size = float(traits.get("size", 0.3)), clade = String(traits.get("clade", "")),
			role = "sapient" if bool(info.get("sapient", false)) else String(traits.get("diet", "omnivore")),
		})
	for id in _prev_counts:
		if not counts.has(id):
			var name := String(world.species[id].get("name", "?")) if world.species.has(id) else "?"
			out.append(_event("departure", "%s ont disparu de la parcelle." % name, id))
	_prev_counts = counts


func _update_structures() -> void:
	structures.clear()
	var level := LAND_USES.find(land_use)
	if land_use == "ruins":
		for k in 6:
			structures.append({kind = "ruin", pos = _spot(k), size = 0.05})
		return
	if level < LAND_USES.find("pasture") or level > LAND_USES.find("arcology"):
		return
	var fields := clampi(level - 5, 1, 6)
	for k in fields:
		structures.append({kind = "field", pos = _spot(k), size = 0.12})
	var kind := "hut" if level <= LAND_USES.find("village") else ("building" if level <= LAND_USES.find("city") else "tower")
	for k in (level - 5) * 3:
		structures.append({kind = kind, pos = _spot(100 + k), size = 0.03 + 0.01 * (level - 5)})
	if level >= LAND_USES.find("village"):
		structures.append({kind = "road", pos = Vector2(0.5, 0.5), size = 1.0})


## Position stable (0..1) pour la k-ième structure : ne saute pas d'une frame à l'autre.
func _spot(k: int) -> Vector2:
	var h := hash([world.seed, cell, k])
	return Vector2(float(h & 0xFFFF) / 65535.0, float((h >> 16) & 0xFFFF) / 65535.0) * 0.8 + Vector2(0.1, 0.1)


func _record() -> void:
	if not history.is_empty() and history[-1].year == year:
		return
	var pop := {}
	var total := 0
	for f in fauna:
		pop[f.species_id] = f.count
		total += f.count
	history.append({
		year = year, temperature_c = temperature_c, global_temperature_c = global_temperature_c,
		population_total = total, population = pop,
	})
	if history.size() > HISTORY_SIZE:
		history.pop_front()


func _event(type: String, summary: String, species_id := -1) -> Dictionary:
	return {year = year, type = "parcel_" + type, region = cell, species_id = species_id,
		summary = summary, cause_id = -1, id = -1}
