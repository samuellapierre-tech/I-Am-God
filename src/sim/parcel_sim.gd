extends RefCounted
## Parcelle suivie par le joueur : un morceau de terrain grand comme l'écran, au cœur d'une cellule
## de la grille WorldSim. Tout le jeu se regarde là : les dinosaures qui passent, la forêt qui
## recule, les premiers champs, la ville, les ruines… ou rien.
##
## CONTRAT (voir docs/ARCHITECTURE.md § Parcelle) : les champs documentés gardent leur nom, leur
## type et leur sens ; les champs marqués « ajout » les complètent.
##
## Modèle local, entièrement déduit de l'état du monde (rien n'est scripté) :
## - Faune : les niches écologiques de la région de la parcelle et de ses voisines
##   (WorldSim.region_niches), modulées par l'habitat local (végétation, urbanisation, catastrophes).
##   Les effectifs sont lissés en temps simulé ; la tendance ▲/▼ compare une moyenne rapide à une
##   moyenne lente, avec seuils d'entrée/sortie et durée minimale (pas de clignotement).
## - Développement : un niveau continu 0 (sauvage) .. 8 (arcologie) qui tend vers une cible
##   déduite de l'espèce sapiente présente (densité locale, niveau technologique, épreuves subies).
##   L'usage du sol en découle par paliers avec hystérésis ; le bâti décroît lentement après un
##   déclin (ruines, puis retour à la nature).
## - Prologue : la mer nue, puis tapis microbiens et récifs ; des terres nues jusqu'à l'arrivée des
##   plantes (densité locale des producteurs terrestres), forêts marécageuses quand l'oxygène abonde.
## - Catastrophes : cratère (l'altitude de la cellule a été creusée par un impact), déluge, cendres
##   volcaniques, glaces (température locale), épidémies et guerres du peuple local.
## Toutes les constantes de temps sont exprimées en « pas idéaux » de WorldSim (une ère sapiente
## en compte environ 1200) : le rythme reste lisible quelle que soit l'ère, et le résultat ne
## dépend pas de la cadence d'appel de update(). Aucun aléa : déterministe à graine égale.

const WorldSim := preload("res://src/sim/world_sim.gd")
const WorldGen := preload("res://src/sim/world_gen.gd")
const Ecosystem := preload("res://src/sim/ecosystem.gd")
const Text := preload("res://src/sim/parcel_text.gd")

## Usages du sol, du plus sauvage au plus artificiel (puis déclin).
const LAND_USES := [
	"ocean", "ice", "wild", "crater", "flooded",
	"camp", "pasture", "farmland", "village", "town", "city", "megacity", "arcology",
	"ruins", "rewild",
	# Prologue (ajouts) : mer et terres avant la vie complexe.
	"seabed", "microbial_mat", "reef", "barren", "swamp_forest",
]
## Usages naturels (ni bâti ni catastrophe) entre lesquels la vie fait passer la parcelle.
const NATURAL_USES := ["ocean", "seabed", "microbial_mat", "reef", "barren", "wild", "swamp_forest"]
const MAX_FAUNA := 6
const MAX_VISIBLE := 40
## ≈ 1,7 ère sapiente à un échantillon tous les HISTORY_STEPS pas idéaux.
const HISTORY_SIZE := 512
## Rayon (en régions écologiques de Ecosystem.RS cellules) d'où viennent les espèces de passage.
const NEIGHBOR_RADIUS := 1
## Poids des régions voisines par rapport à celle de la parcelle.
const RING_WEIGHT := 0.3

## Paliers de développement (indice = niveau entier de `development`).
const DEV_USES := ["wild", "camp", "pasture", "farmland", "village", "town", "city", "megacity", "arcology"]
## Niveau de développement visé selon le niveau technologique du peuple (Eras : 0 = feu, 0,75 =
## agriculture, 1 = Antiquité, 4 = Industriel, 6 = Cyberpunk…), pour une parcelle pleinement peuplée.
const DEV_CURVE := [[0.0, 1.5], [0.6, 2.4], [0.75, 3.3], [1.5, 4.3], [2.5, 5.4], [4.0, 6.4],
	[5.5, 7.3], [6.5, 8.3], [8.0, 8.6]]
## Hystérésis : on entre au palier k à development ≥ k + UP, on en sort sous k - DOWN.
const LEVEL_UP_MARGIN := 0.1
const LEVEL_DOWN_MARGIN := 0.3
## Couverture végétale relative selon le développement (0..8).
const COVER := [1.0, 0.95, 0.8, 0.6, 0.5, 0.38, 0.24, 0.12, 0.2]

# Constantes de temps (pas idéaux de WorldSim).
const TAU_DEV_UP := 25.0
const TAU_DEV_DOWN := 12.0
const TAU_RUINS := 220.0
const TAU_CRATER := 140.0
const TAU_FLOOD := 30.0
const TAU_SCORCH := 30.0
const TAU_HARDSHIP := 80.0
const TAU_VEG_UP := 20.0
const TAU_VEG_DOWN := 3.0
const TAU_WATER := 5.0
const TAU_FAUNA := 4.0
const TAU_FAUNA_SLOW := 20.0
const TAU_PEAK := 150.0
const TAU_HEAT_FAST := 8.0
const TAU_HEAT_SLOW := 500.0

## Tendance : écart relatif moyenne rapide / lente pour afficher ▲/▼, pour revenir à 0, et durée
## minimale (pas idéaux) avant de changer d'avis.
const TREND_ENTER := 0.06
const TREND_EXIT := 0.02
const TREND_HOLD := 6.0
## Densité locale lissée à partir de laquelle une espèce est présente / n'est plus présente.
const PRESENT_IN := 0.03
const PRESENT_OUT := 0.01
## Pic de densité locale sous lequel l'effondrement d'une espèce ne déclenche pas d'alerte.
const COLLAPSE_MIN_PEAK := 0.04
## Prologue : densité de vie marine qui peuple les fonds, densité locale de plantes sous laquelle
## la terre est nue (entrée / sortie), oxygène des forêts marécageuses (entrée / sortie).
const MARINE_LIFE_MIN := 0.02
const BARREN_IN := 0.03
const BARREN_OUT := 0.06
const SWAMP_OXYGEN_IN := 1.15
const SWAMP_OXYGEN_OUT := 1.05
const SHALLOW_SEA := -0.35
## Rivage (prologue) : marnage (en unités d'altitude, autour de WorldSim.sea_level) et marge
## d'hystérésis ; au-delà, mer ou terre ferme. Mètres par unité d'altitude (affichage).
const TIDE := 0.006
const SHORE_MARGIN := 0.003
const METERS_PER_UNIT := 6000.0
## Parcelle de départ du prologue : un haut-fond qui émergera (bande d'altitude), tiède, sur une
## côte d'un continent assez vaste pour porter plus tard des dinosaures.
const START_ELEVATION := Vector2(0.026, 0.035)
const START_TEMPERATURE := 0.68
## Banquise sur la mer (température de grille, entrée / sortie).
const SEA_ICE_IN := 0.07
const SEA_ICE_OUT := 0.1
## Densité régionale d'un peuple qui vaut une parcelle pleinement occupée.
const FULL_PRESENCE := 0.35

## Ruines : bâti minimal (en niveaux) pour laisser des ruines, puis seuils de retour à la nature.
const RUINS_MIN := 3.0
const RUINS_OUT := 2.2
const REWILD_OUT := 0.6
## Glaces : température de grille (0..1) d'entrée et de sortie ; une mégapole se chauffe.
const ICE_IN := 0.11
const ICE_OUT := 0.14
const ICE_IMMUNE_LEVEL := 7
## Un événement catastrophique n'est plus affiché comme usage du sol sous ce niveau.
const CATASTROPHE_OUT := 0.3
## Baisse d'altitude (grille WorldSim) qui signe un cratère d'impact sur la cellule.
const CRATER_DROP := 0.004
## Portées (en cellules) des événements mondiaux qui touchent la parcelle.
const BLAST_RADIUS := 24.0
const FLOOD_RADIUS := 14.0
const FLOOD_MAX_ELEVATION := 0.35
const VOLCANO_RADIUS := 14.0
const WAR_RADIUS := 14.0
const PLAGUE_RADIUS := 16.0
## Îlot de chaleur urbain maximal (°C) d'une mégapole.
const HEAT_ISLAND_C := 2.5
## Dérive thermique (°C, moyenne rapide - moyenne lente) qui déclenche / éteint l'alerte.
const HEAT_ALERT_IN := 1.5
const HEAT_ALERT_OUT := 0.8

## Historique : un échantillon tous les HISTORY_STEPS pas idéaux, au plus N par appel
## (les échantillons manqués entre deux appels sont interpolés).
const HISTORY_STEPS := 3.0
const MAX_SAMPLES_PER_UPDATE := 64

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
##   trend (-1, 0, 1), role ("herbivore"|"carnivore"|"omnivore"|"sapient"), size (0..1), clade,
##   diet (ajout), change (ajout : écart relatif moyenne rapide / lente, -1..+∞),
##   habitat (ajout : "marine"|"amphibious"|"land")}]
## role vaut aussi "producer" (ajout) pour les microbes et algues marins ; les plantes terrestres
## ne sont pas listées : elles font la végétation.
## Espèce sapiente en tête, puis par effectif décroissant.
var fauna: Array[Dictionary] = []
## [{kind: "field"|"hut"|"road"|"building"|"tower"|"ruin", pos: Vector2 (0..1), size: float}]
## La k-ième structure d'un type garde toujours la même position.
var structures: Array[Dictionary] = []
## Échantillons pour les statistiques à l'écran, du plus ancien au plus récent :
## [{year, temperature_c, global_temperature_c, population_total, population: {species_id: count},
##   vegetation (ajout), development (ajout)}]
var history: Array[Dictionary] = []

# --- Ajouts au contrat ---
## Ère mondiale (WorldSim.current_era()).
var era := ""
## Libellé français de l'usage du sol (« Forêt sauvage », « Terres agricoles », « Mégapole »…).
var land_use_label := ""
## Développement continu 0 (sauvage) .. 8 (arcologie) et sa cible actuelle.
var development := 0.0
var target_development := 0.0
## Peuple sapient présent sur la parcelle (-1 : aucun).
var sapient_id := -1
## Intensité 0..1 des stigmates : cratère (1 juste après l'impact), inondation, cendres.
var crater_level := 0.0
var flood_level := 0.0
var scorch_level := 0.0
## Crises en cours, de la plus grave à la moins grave :
## [{kind ("species_collapse"|"heat_drift"|"civilization_threat"), species_id, severity 0..1,
##   summary, cause_id}]
var alerts: Array[Dictionary] = []
## Rivage : "sea" (sous l'eau), "intertidal" (estran, découvert à marée basse) ou "land".
## Suit le niveau de la mer (WorldSim.sea_level) : la parcelle peut émerger ou être noyée.
var shore := "land"
## Profondeur d'eau (m) : positive sous la mer, négative au-dessus (altitude par rapport à la mer).
var water_depth_m := 0.0

var _fresh := true
var _ideal := 1.0
var _prev_ideal := 0.0
var _level := 0
var _peak_level := 0
var _base_use := "wild"
var _built := 0.0
var _hardship := 0.0
var _iced := false
var _elev := NAN
var _veg_pot := 0.0
var _presence := 0.0
var _last_sapient := -1
## Prologue : complexité maximale de la vie marine locale, densité locale des plantes, vie marine.
var _marine_cx := -1.0
var _flora_local := 0.0
var _barren := false
var _swamp := false
var _sea_iced := false
var _shore_changed := ""
## Ancre de croûte (WorldSim.make_anchor) : la parcelle suit son terrain quand les plaques bougent.
var _anchor := {}
var _geo_seen := -1
## id -> densité régionale pondérée (niches de la région et de ses voisines).
var _regional := {}
## id -> {fast, slow, peak, trend, hold, present, cause}
var _track := {}
var _heat_fast := 0.0
var _heat_slow := 0.0
var _alert_on := {}
var _civ_cause := -1
var _harm_cause := -1
var _cold_cause := -1
var _impact_cause := -1
var _flood_cause := -1
## Dernier état mesuré, pour interpoler l'historique : {year, temperature_c, ...}.
var _snap := {}
var _next_sample := 0.0


func _init(p_world: WorldSim, p_cell: Vector2i) -> void:
	world = p_world
	cell = Vector2i(posmod(p_cell.x, WorldSim.WIDTH), clampi(p_cell.y, 0, WorldSim.HEIGHT - 1))
	update([])


static func to_celsius(t: float) -> float:
	return -30.0 + 75.0 * t


## Niveau de développement visé par un peuple de niveau technologique `level` (0..Eras.MAX_TECH).
static func development_for_tech(level: float) -> float:
	if level <= DEV_CURVE[0][0]:
		return DEV_CURVE[0][1]
	for k in range(1, DEV_CURVE.size()):
		var a: Array = DEV_CURVE[k - 1]
		var b: Array = DEV_CURVE[k]
		if level <= b[0]:
			return lerpf(a[1], b[1], (level - a[0]) / (b[0] - a[0]))
	return DEV_CURVE[-1][1]


## Palier (indice de DEV_USES) après hystérésis, depuis le palier `current`.
static func step_level(d: float, current: int) -> int:
	var lv := clampi(current, 0, DEV_USES.size() - 1)
	while lv < DEV_USES.size() - 1 and d >= lv + 1 + LEVEL_UP_MARGIN:
		lv += 1
	while lv > 0 and d < lv - LEVEL_DOWN_MARGIN:
		lv -= 1
	return lv


## Recalcule l'état de la parcelle après un ou plusieurs pas de WorldSim. Renvoie les événements
## propres à la parcelle (même format que WorldSim : {year, type, region, species_id, summary,
## cause_id, id}, type préfixé « parcel_ », id = -1 car hors du journal causal). Les événements
## qui changent l'usage du sol portent aussi land_use et previous_land_use.
func update(world_events: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_follow_crust()
	var i := _index(cell)
	_ideal = maxf(world.ideal_step_years(), 1e-6)
	var dt := 0.0
	if not _fresh:
		# Pas idéaux écoulés. Si le rythme a changé pendant l'intervalle (éveil d'un peuple),
		# le plus lent des deux évite de compter des milliers de pas fictifs.
		dt = maxf(0.0, world.year - year) / maxf(_ideal, _prev_ideal)
	_prev_ideal = _ideal
	year = world.year
	era = world.current_era()
	biome = WorldSim.BIOME_NAMES[world.biome[i]]
	tech = world.tech[i]
	_decay(dt)
	_update_shore(i)
	_scan_niches()
	var impact := _read_events(world_events, i, out)
	_detect_impact(i, impact, out)
	_update_development(i, dt)
	_update_land_use(i, out)
	_update_cover(i, dt)
	_update_fauna(dt, out)
	_update_alerts(dt, out)
	_update_structures()
	_record()
	_fresh = false
	return out


## La croûte dérive : la parcelle reste sur le même terrain (mêmes repères), donc sa cellule
## change avec la géographie. Le relief de référence (cratères) est alors relu sans fausse alerte.
func _follow_crust() -> void:
	if _fresh or _anchor.is_empty():
		_anchor = world.make_anchor(cell)
		_geo_seen = world.geography_version
		return
	if world.geography_version == _geo_seen:
		return
	_geo_seen = world.geography_version
	var moved: Vector2i = world.anchor_cell(_anchor)
	if moved != cell:
		cell = moved
	_elev = NAN


func _index(c: Vector2i) -> int:
	return c.y * WorldSim.WIDTH + c.x


func _relax(cur: float, target: float, dt: float, tau: float) -> float:
	if _fresh:
		return target
	return target + (cur - target) * exp(-dt / tau)


## Rivage : mer, estran ou terre selon la profondeur sous le niveau marin (hystérésis).
func _update_shore(i: int) -> void:
	var tide := TIDE if world.scenario != WorldSim.SCENARIO_CRETACEOUS else 0.0
	var margin := SHORE_MARGIN if tide > 0.0 else 0.0
	var depth: float = world.water_depth(i)
	water_depth_m = depth * METERS_PER_UNIT
	var old := shore
	var now := old
	if _fresh:
		now = "sea" if depth > tide else ("land" if depth <= -tide else "intertidal")
		if tide == 0.0:
			now = "sea" if world.elevation[i] < 0.0 else "land"
	elif tide == 0.0:
		now = "sea" if world.elevation[i] < 0.0 else "land"
	else:
		match old:
			"sea":
				if depth < tide - margin:
					now = "intertidal"
			"land":
				if depth > -tide + margin:
					now = "intertidal"
			_:
				if depth > tide + margin:
					now = "sea"
				elif depth < -tide - margin:
					now = "land"
	shore = now
	_shore_changed = "" if now == old or _fresh else old


func _at_sea() -> bool:
	return shore != "land"


## Parcelle de départ du prologue : un haut-fond tiède et peu profond (tapis microbiens,
## stromatolites) que le retrait de la mer fera émerger, sur la côte d'un continent assez vaste
## pour porter plus tard forêts et dinosaures. Déterministe ; repli : la première terre venue.
static func pick_start_cell(w: WorldSim) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score := -1.0
	var W := WorldSim.WIDTH
	for y in range(8, WorldSim.HEIGHT - 8):
		for x in W:
			var i := y * W + x
			var e: float = w.crust_elevation(i)
			if e < START_ELEVATION.x or e > START_ELEVATION.y:
				continue
			var t: float = w.temperature[i]
			var climate := 1.0 - absf(t - START_TEMPERATURE) * 3.0
			if climate <= 0.0:
				continue
			var coast := false
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if w.crust_elevation((y + dy) * W + posmod(x + dx, W)) < 0.0:
						coast = true
			if not coast:
				continue
			var land := 0
			var total := 0
			for dy in range(-6, 7, 2):
				for dx in range(-6, 7, 2):
					var yy := clampi(y + dy, 0, WorldSim.HEIGHT - 1)
					total += 1
					if w.crust_elevation(yy * W + posmod(x + dx, W)) >= 0.0:
						land += 1
			var share := float(land) / float(total)
			if share < 0.6:
				continue
			var depth_fit := 1.0 - absf(e - 0.03) / 0.01
			var score := maxf(depth_fit, 0.05) * climate * share * (0.5 + w.moisture[i])
			if score > best_score:
				best_score = score
				best = Vector2i(x, y)
	if best.x >= 0:
		return best
	for i in w.elevation.size():
		if w.elevation[i] >= 0.0:
			return Vector2i(i % W, i / W)
	return Vector2i.ZERO


## Distance (cellules, la carte se raccordant en x) entre la parcelle et la région d'un événement.
func _distance(region: Variant) -> float:
	if typeof(region) != TYPE_VECTOR2I:
		return INF
	var c: Vector2i = region
	if c.x < 0 or c.y < 0:
		return INF
	var dx := absi(posmod(c.x, WorldSim.WIDTH) - cell.x)
	dx = mini(dx, WorldSim.WIDTH - dx)
	var dy := c.y - cell.y
	return sqrt(float(dx * dx + dy * dy))


func _global_temperature() -> float:
	var t := world.temperature
	var s := 0.0
	var step := 37  # échantillonnage : la moyenne exacte n'apporte rien à l'affichage
	var n := 0
	for k in range(0, t.size(), step):
		s += t[k]
		n += 1
	return to_celsius(s / maxf(1.0, n))


# =============================================================================================
# Monde -> parcelle
# =============================================================================================

func _decay(dt: float) -> void:
	# Un climat favorable cicatrise plus vite (la végétation recouvre cendres et cratère).
	var heal := 0.3 + 0.7 * _veg_pot
	crater_level = _cut(crater_level * exp(-dt * heal / TAU_CRATER))
	flood_level = _cut(flood_level * exp(-dt / TAU_FLOOD))
	scorch_level = _cut(scorch_level * exp(-dt * heal / TAU_SCORCH))
	_hardship = _cut(_hardship * exp(-dt / TAU_HARDSHIP))


func _cut(v: float) -> float:
	return v if v >= 0.01 else 0.0


## Espèces établies dans la région de la parcelle et ses voisines (densité pondérée par la distance).
func _scan_niches() -> void:
	_regional.clear()
	var rs := Ecosystem.RS
	for dy in range(-NEIGHBOR_RADIUS, NEIGHBOR_RADIUS + 1):
		var y := cell.y + dy * rs
		if y < 0 or y >= WorldSim.HEIGHT:
			continue
		for dx in range(-NEIGHBOR_RADIUS, NEIGHBOR_RADIUS + 1):
			var w := 1.0 if dx == 0 and dy == 0 else RING_WEIGHT
			for n in world.region_niches(Vector2i(cell.x + dx * rs, y)):
				var id: int = n.species_id
				var d: float = float(n.density) * w
				if d > float(_regional.get(id, 0.0)):
					_regional[id] = d
	sapient_id = -1
	var best := 0.0
	for id in _regional:
		var sp: Dictionary = world.species.get(id, {})
		if bool(sp.get("sapient", false)) and bool(sp.get("alive", false)):
			var d: float = _regional[id]
			if d > best or (d == best and id < sapient_id):
				best = d
				sapient_id = id
	_presence = clampf(best / FULL_PRESENCE, 0.0, 1.0)
	if sapient_id >= 0:
		_last_sapient = sapient_id
	_marine_cx = -1.0
	_flora_local = 0.0
	for id in _regional:
		var t: Dictionary = world.species.get(id, {}).get("traits", {})
		var d: float = _regional[id]
		var hab := String(t.get("habitat", "land"))
		if hab != "land" and d >= MARINE_LIFE_MIN:
			_marine_cx = maxf(_marine_cx, float(t.get("complexity", 6.0)))
		if hab == "land" and String(t.get("diet", "")) == "autotrophe":
			_flora_local = maxf(_flora_local, d)


## Applique les événements mondiaux qui concernent la parcelle. Renvoie l'impact de météore le
## plus proche ({} si aucun) : {id, dist}.
func _read_events(world_events: Array, i: int, out: Array[Dictionary]) -> Dictionary:
	var impact := {}
	var flood := {}
	var land := not _at_sea()
	var plague_cause := -2
	var war_cause := -2
	for e in world_events:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var type := String(e.get("type", ""))
		var eid := int(e.get("id", -1))
		var sid := int(e.get("species_id", -1))
		var dist := _distance(e.get("region", Vector2i(-1, -1)))
		if sid >= 0 and eid > 0 and _track.has(sid):
			_track[sid].cause = eid
		var local_people := sid >= 0 and sid == sapient_id
		match type:
			"impact", "divine_meteor", "meteor":
				impact = _closest(impact, eid, ["impact", "divine_meteor", "meteor"].find(type), dist)
				if eid > 0:
					_cold_cause = eid
			"deluge", "divine_flood", "flood":
				var radius := float(e.get("radius", FLOOD_RADIUS))
				if land and dist <= radius and world.elevation[i] <= FLOOD_MAX_ELEVATION:
					flood = _closest(flood, eid, ["deluge", "divine_flood", "flood"].find(type), dist)
					flood.radius = radius
			"volcanism":
				if eid > 0:
					_cold_cause = eid
				if land and dist <= VOLCANO_RADIUS:
					scorch_level = maxf(scorch_level, 0.7 * (1.0 - dist / (VOLCANO_RADIUS + 1.0)))
					_harm_cause = eid
					out.append(_event("volcano", "Les cendres d'un supervolcan recouvrent la parcelle.", -1, eid))
			"ice_age", "divine_ice_age":
				if eid > 0:
					_cold_cause = eid
			"plague":
				if local_people:
					# Une épidémie frappe tout le peuple ; plus durement près de son foyer.
					_hardship = minf(1.0, _hardship + (0.35 if dist <= PLAGUE_RADIUS else 0.15))
					_harm_cause = eid
					plague_cause = eid
			"war":
				if local_people and dist <= WAR_RADIUS:
					_hardship = minf(1.0, _hardship + 0.3)
					development = maxf(0.0, development - 0.4)
					_harm_cause = eid
					war_cause = eid
			"collapse":
				if local_people:
					_hardship = minf(1.0, _hardship + 0.5)
					_harm_cause = eid
			"decline":
				if local_people:
					_hardship = minf(1.0, _hardship + 0.15)
					_harm_cause = eid
			"golden_age":
				if local_people:
					_hardship = maxf(0.0, _hardship - 0.2)
					_civ_cause = eid
			"discovery", "era_change":
				if local_people:
					_civ_cause = eid
			"sapience":
				if local_people or _track.has(sid):
					_civ_cause = eid
					out.append(_event("sapience", Text.about(_name(sid),
						"Sur cette parcelle même, %s s'éveille à la conscience.",
						"Sur cette parcelle même, %s s'éveillent à la conscience."), sid, eid))
			"extinction":
				if sid >= 0 and sid == _last_sapient:
					_harm_cause = eid
				if _track.has(sid):
					var tr: Dictionary = _track[sid]
					if tr.present and not _fresh:
						out.append(_event("extinction", Text.about(_name(sid),
							"%s ne foule plus cette terre : l'espèce s'est éteinte.",
							"%s ne foulent plus cette terre : l'espèce s'est éteinte."), sid, eid))
					_track.erase(sid)
	if not flood.is_empty():
		var s := 1.0 - 0.5 * float(flood.dist) / (float(flood.radius) + 1.0)
		flood_level = maxf(flood_level, s)
		_flood_cause = flood.id
		if development < 6.0:
			development = maxf(0.0, development - 0.8 * s)
	var who := _name(sapient_id)
	if plague_cause > -2 and _presence > 0.2 and _level >= 1:
		out.append(_event("plague", Text.about(who,
			"L'épidémie atteint la parcelle : %s y est décimée.",
			"L'épidémie atteint la parcelle : %s y sont décimés."), sapient_id, plague_cause))
	if war_cause > -2 and _presence > 0.2 and _level >= 1:
		out.append(_event("war", "La guerre ravage la parcelle : incendies et champs piétinés.", sapient_id, war_cause))
	return impact


## Garde le meilleur candidat : un événement du journal (id > 0) prime, puis le type préféré (rang).
func _closest(cur: Dictionary, eid: int, rank: int, dist: float) -> Dictionary:
	if cur.is_empty():
		return {id = eid, rank = rank, dist = dist}
	var better := (eid > 0 and int(cur.id) <= 0) or ((eid > 0) == (int(cur.id) > 0) and rank < int(cur.rank))
	if better:
		return {id = eid, rank = rank, dist = minf(dist, float(cur.dist))}
	cur.dist = minf(dist, float(cur.dist))
	return cur


## Un impact se lit dans le relief : WorldSim creuse l'altitude des cellules du cratère.
func _detect_impact(i: int, impact: Dictionary, out: Array[Dictionary]) -> void:
	var e_now: float = world.elevation[i]
	var drop := 0.0 if is_nan(_elev) else _elev - e_now
	_elev = e_now
	var cause: int = int(impact.get("id", -1))
	if drop > CRATER_DROP:
		crater_level = 1.0
		scorch_level = 1.0
		_impact_cause = cause
		_harm_cause = cause
		# Toute vie est anéantie ; le bâti est pulvérisé (ni ruines ni champs).
		development = 0.0
		_built = 0.0
		_level = 0
		_peak_level = 0
		_base_use = "wild"
		vegetation = 0.0
		_track.clear()
	elif not impact.is_empty() and float(impact.dist) <= BLAST_RADIUS and not _at_sea():
		var s := 1.0 - float(impact.dist) / (BLAST_RADIUS + 1.0)
		scorch_level = maxf(scorch_level, s)
		development = maxf(0.0, development - 1.5 * s)
		for id in _track:
			_track[id].fast *= 1.0 - 0.6 * s
		out.append(_event("blast", "Le souffle de l'impact embrase la parcelle.", -1, cause))


## Fertilité du sol pour un peuple (0,35..1) et part du terrain encore vivable après les
## catastrophes (0..1).
func _fertility(i: int) -> float:
	return clampf(0.35 + WorldGen.BIOME_FERTILITY[world.biome[i]], 0.35, 1.0)


func _hazard() -> float:
	return (1.0 - crater_level) * (1.0 - 0.5 * flood_level) * (0.1 if _iced else 1.0)


func _update_development(i: int, dt: float) -> void:
	var target := 0.0
	if sapient_id >= 0 and not _at_sea():
		var settle := smoothstep(0.0, 0.25, _presence)
		var level := float(world.species[sapient_id].get("tech_level", 0.0))
		var hazard := _hazard()
		var intensity := sqrt(clampf(_presence * _fertility(i) * hazard * (1.0 - 0.6 * _hardship), 0.0, 1.0))
		target = settle * hazard * (1.5 + (development_for_tech(level) - 1.5) * intensity)
	target_development = target
	development = _relax(development, target, dt, TAU_DEV_UP if target > development else TAU_DEV_DOWN)
	if development >= _built:
		_built = development
	else:
		_built = development + (_built - development) * exp(-dt / TAU_RUINS)


# =============================================================================================
# Usage du sol
# =============================================================================================

func _update_land_use(i: int, out: Array[Dictionary]) -> void:
	var old := land_use
	_level = step_level(development, _level)
	_peak_level = maxi(_peak_level, _level)
	var base := "wild"
	if _level > 0:
		base = DEV_USES[_level]
	elif _base_use == "ruins":
		base = "ruins" if _built >= RUINS_OUT else ("rewild" if _built >= REWILD_OUT else "wild")
	elif _base_use == "rewild":
		base = "rewild" if _built >= REWILD_OUT else "wild"
	elif _base_use != "wild" and _built >= RUINS_MIN and _peak_level >= 4:
		base = "ruins"
	if base == "wild":
		_peak_level = 0
	_base_use = base

	var land := not _at_sea()
	var t: float = world.temperature[i]
	if not land:
		_iced = false
		_sea_iced = t < (SEA_ICE_OUT if _sea_iced else SEA_ICE_IN)
	elif _iced:
		_iced = t < ICE_OUT
	else:
		_iced = t < ICE_IN and _level < ICE_IMMUNE_LEVEL
	if base == "wild" and _explicit_flora():
		# Avant les plantes, la terre est nue ; les forêts-charbon exigent oxygène et humidité.
		_barren = _flora_local < (BARREN_OUT if _barren else BARREN_IN)
		var oxy_ok: bool = world.oxygen >= (SWAMP_OXYGEN_OUT if _swamp else SWAMP_OXYGEN_IN)
		_swamp = not _barren and oxy_ok and world.moisture[i] >= 0.45 and t >= 0.4
		if _barren:
			base = "barren"
		elif _swamp:
			base = "swamp_forest"
	var use := base
	if not land:
		if _sea_iced:
			use = "ice"
		elif _marine_cx < 0.0:
			use = "barren" if shore == "intertidal" else "ocean"
		elif world.water_depth(i) > -SHALLOW_SEA:
			use = "seabed"
		else:
			use = "reef" if _marine_cx >= 3.0 else "microbial_mat"
	elif crater_level > CATASTROPHE_OUT:
		use = "crater"
	elif flood_level > CATASTROPHE_OUT:
		use = "flooded"
	elif _iced:
		use = "ice"
	land_use = use
	land_use_label = Text.use_label(use, biome)
	if shore == "intertidal":
		land_use_label = {"microbial_mat": "Estran à stromatolites", "reef": "Estran rocheux",
			"barren": "Estran nu", "ice": "Estran gelé"}.get(use, land_use_label)
	if _fresh:
		return
	if _shore_changed != "":
		var sev := _event("shore", _shore_text(_shore_changed, shore), -1, -1)
		sev.land_use = use
		sev.previous_land_use = old
		sev.shore = shore
		out.append(sev)
		return
	if use == old:
		return
	var ev: Dictionary
	match use:
		"crater":
			ev = _event("impact", "Un astéroïde frappe la parcelle : il ne reste qu'un cratère fumant.", -1, _impact_cause)
		"flooded":
			ev = _event("flood", "Les eaux du Déluge submergent la parcelle.", -1, _flood_cause)
		"ice":
			ev = _event("ice", "Les glaces recouvrent la parcelle.", -1, _cold_cause)
		_:
			match old:
				"crater":
					ev = _event("recolonized", "La vie reconquiert le cratère : herbes et fougères recouvrent les cendres.", -1, -1)
				"flooded":
					ev = _event("flood_end", "Les eaux se retirent et laissent un limon fertile.", -1, _flood_cause)
				"ice":
					ev = _event("thaw", "Les glaces reculent : la terre réapparaît.", -1, -1)
				_:
					ev = _transition(old, use)
	ev.land_use = use
	ev.previous_land_use = old
	out.append(ev)


## Événement d'un changement d'usage « ordinaire » (développement, déclin, ruines, nature).
func _transition(old: String, to_use: String) -> Dictionary:
	if to_use in NATURAL_USES and (old in NATURAL_USES or old == "ice"):
		return _event("land_use", _nature_text(old, to_use), -1, -1)
	var oi := DEV_USES.find(old)
	var ni := DEV_USES.find(to_use)
	if ni >= 1 and (oi < 0 or ni > oi):
		return _event("land_use", _rise_text(old, to_use), sapient_id, _civ_cause)
	if ni >= 1:
		return _event("land_use", "Déclin : %s à %s." % [Text.use_subject(old, "se réduit", "se réduisent"),
			Text.INDEFINITE.get(to_use, to_use)], _last_sapient, _harm_cause)
	match to_use:
		"ruins":
			var peak: String = DEV_USES[clampi(_peak_level, 4, DEV_USES.size() - 1)]
			return _event("land_use", "Abandon : %s." % Text.use_subject(peak, "n'est plus que ruines",
				"ne sont plus que ruines"), _last_sapient, _harm_cause)
		"rewild":
			return _event("land_use", "La végétation envahit les ruines.", -1, -1)
	if old in ["ruins", "rewild"]:
		return _event("land_use", "Les dernières ruines disparaissent sous la végétation.", -1, -1)
	return _event("land_use", "La parcelle est abandonnée : la nature reprend ses droits.", _last_sapient, _harm_cause)


func _shore_text(from: String, to: String) -> String:
	match to:
		"intertidal":
			if from == "sea":
				return "La mer se retire : la parcelle devient un estran que chaque marée découvre."
			return "La mer remonte : la parcelle redevient un estran battu par les marées."
		"land":
			return "La parcelle émerge pour de bon : une terre neuve s'offre à la vie."
	return "Les eaux recouvrent l'estran : la parcelle repasse sous la mer."


func _explicit_flora() -> bool:
	return world.scenario != WorldSim.SCENARIO_CRETACEOUS


## La vie (et non un peuple) change la parcelle : mers peuplées, terres conquises.
func _nature_text(old: String, to_use: String) -> String:
	match to_use:
		"microbial_mat":
			return "Des tapis microbiens tapissent les hauts-fonds : la vie colonise la parcelle."
		"reef":
			return "Un récif grouillant d'animaux se forme dans les eaux claires."
		"seabed":
			return "La vie gagne les fonds marins de la parcelle."
		"ocean":
			return "Les eaux de la parcelle se vident de toute vie."
		"barren":
			return "La végétation disparaît : il ne reste que la roche nue."
		"swamp_forest":
			return "Une forêt marécageuse s'étend : fougères géantes et insectes énormes."
		"wild":
			if old == "barren":
				return "Les plantes conquièrent la parcelle : la terre nue verdit."
			if old == "swamp_forest":
				return "La forêt marécageuse s'assèche et laisse place à %s." % Text.use_label("wild", biome).to_lower()
	return "La parcelle change : %s." % Text.use_label(to_use, biome).to_lower()


func _rise_text(old: String, to_use: String) -> String:
	var who := _name(sapient_id)
	match to_use:
		"camp":
			if old in ["ruins", "rewild"]:
				return Text.about(who, "%s réinvestit les ruines et y dresse un campement.",
					"%s réinvestissent les ruines et y dressent un campement.")
			return Text.about(who, "%s installe un campement sur la parcelle.",
				"%s installent un campement sur la parcelle.")
		"pasture":
			return Text.about(who, "%s fait paître ses troupeaux sur la parcelle.",
				"%s font paître leurs troupeaux sur la parcelle.")
		"farmland":
			return "Les premiers champs remplacent %s." % Text.CLEARED.get(biome, "la végétation sauvage")
		"village":
			return "Un village se forme autour des champs."
		"town":
			return "Le village grandit : c'est désormais une petite ville."
		"city":
			return "La petite ville devient une ville : rues pavées, ateliers et cheminées."
		"megacity":
			return "La ville s'étend en mégapole ; la nature recule devant le béton."
		"arcology":
			return "Une arcologie s'élève : la cité entière tient dans une seule structure."
	return "La parcelle change : %s." % Text.use_label(to_use, biome).to_lower()


# =============================================================================================
# Végétation, eau, température
# =============================================================================================

func _cover_for(d: float) -> float:
	var x := clampf(d, 0.0, COVER.size() - 1.0)
	var k := mini(int(x), COVER.size() - 2)
	return lerpf(COVER[k], COVER[k + 1], x - k)


func _update_cover(i: int, dt: float) -> void:
	var t: float = world.temperature[i]
	var m: float = world.moisture[i]
	var land := not _at_sea()
	var fert: float = WorldGen.BIOME_FERTILITY[world.biome[i]]
	var temp_ok := smoothstep(0.06, 0.3, t) * (1.0 - 0.5 * smoothstep(0.85, 1.0, t))
	_veg_pot = clampf(0.5 * fert + 0.5 * temp_ok * smoothstep(0.1, 0.6, m), 0.0, 1.0) if land else 0.0
	if _explicit_flora():
		_veg_pot *= smoothstep(0.0, 0.25, _flora_local)
	# Les champs remplacent la forêt, la ville la réduit ; les ruines se couvrent peu à peu.
	var cover := _cover_for(development) * (1.0 - 0.06 * maxf(0.0, _built - development))
	var veg := _veg_pot * cover * (1.0 - crater_level) * (1.0 - 0.85 * scorch_level) * (1.0 - 0.7 * flood_level)
	if _iced:
		veg *= 0.05
	vegetation = _relax(vegetation, veg, dt, TAU_VEG_UP if veg > vegetation else TAU_VEG_DOWN)

	var w := 1.0
	if land:
		# Irrigation des campagnes, sols imperméables des villes, lac de cratère, crue.
		w = m + 0.12 * smoothstep(1.5, 3.0, development) * (1.0 - smoothstep(5.0, 7.0, development)) \
			- 0.15 * smoothstep(5.0, 8.0, development) + 0.25 * crater_level
		w = maxf(w, flood_level)
		if _iced:
			w *= 0.4
	water = _relax(water, clampf(w, 0.0, 1.0), dt, TAU_WATER)
	temperature_c = to_celsius(t) + HEAT_ISLAND_C * smoothstep(5.0, 8.0, development)
	global_temperature_c = _global_temperature()


# =============================================================================================
# Faune
# =============================================================================================

func _update_fauna(dt: float, out: Array[Dictionary]) -> void:
	var targets := {}
	var at_sea := _at_sea()
	if not _regional.is_empty():
		var veg_ratio := clampf(vegetation / maxf(_veg_pot, 0.15), 0.0, 1.0)
		var urban := clampf((development - 1.0) / 6.0, 0.0, 0.95)
		var hazard := (1.0 - crater_level) * (1.0 - 0.7 * flood_level) * (1.0 - 0.6 * scorch_level) \
			* (0.2 if _iced else 1.0)
		for id in _regional:
			var sp: Dictionary = world.species.get(id, {})
			if not bool(sp.get("alive", false)):
				continue
			var tr0: Dictionary = sp.get("traits", {})
			var hab := String(tr0.get("habitat", "land"))
			# En mer, la vie marine et amphibie ; à terre, la vie terrestre et amphibie, sans les
			# plantes (elles font la végétation).
			if (at_sea and hab == "land") or (not at_sea and hab == "marine"):
				continue
			if hab == "land" and String(tr0.get("diet", "")) == "autotrophe":
				continue
			var f: float
			if hab == "marine":
				f = 1.0
			elif bool(sp.get("sapient", false)):
				f = 0.4 + 0.6 * clampf(development / 6.0, 0.0, 1.0)
			else:
				var traits: Dictionary = sp.get("traits", {})
				var size := float(traits.get("size", 0.3))
				var floor_h := 0.35 if String(traits.get("diet", "")) == "herbivore" else 0.5
				# Les herbivores suivent la végétation ; les gros animaux fuient champs et villes,
				# les petits (oiseaux, rongeurs) s'en accommodent.
				f = lerpf(floor_h, 1.0, veg_ratio) * (1.0 - urban * (0.35 + 0.65 * size))
			targets[id] = clampf(float(_regional[id]) * f * hazard, 0.0, 1.0)
	for id in targets:
		if not _track.has(id) and targets[id] >= PRESENT_OUT:
			_track[id] = {fast = 0.0, slow = 0.0, peak = 0.0, trend = 0, hold = 0.0, present = false, cause = -1}
	var gone := []
	for id in _track:
		var tr: Dictionary = _track[id]
		var target: float = targets.get(id, 0.0)
		if _fresh:
			tr.fast = target
			tr.slow = target
			tr.peak = target
		else:
			tr.fast = target + (float(tr.fast) - target) * exp(-dt / TAU_FAUNA)
			tr.slow = tr.fast + (float(tr.slow) - tr.fast) * exp(-dt / TAU_FAUNA_SLOW)
			tr.peak = maxf(tr.slow, float(tr.peak) * exp(-dt / TAU_PEAK))
		_update_trend(tr, dt)
		var was: bool = tr.present
		tr.present = float(tr.fast) >= (PRESENT_OUT if was else PRESENT_IN)
		if was != tr.present and not _fresh:
			if tr.present:
				out.append(_event("arrival", Text.about(_name(id), "%s arrive sur la parcelle.",
					"%s arrivent sur la parcelle."), id, int(tr.cause)))
			else:
				out.append(_event("departure", Text.about(_name(id), "%s quitte la parcelle.",
					"%s quittent la parcelle."), id, int(tr.cause)))
		if not tr.present and target <= 0.0 and float(tr.fast) < 0.002:
			gone.append(id)
	for id in gone:
		_track.erase(id)

	var rows: Array[Dictionary] = []
	for id in _track:
		var tr: Dictionary = _track[id]
		if not tr.present or not world.species.has(id):
			continue
		var sp: Dictionary = world.species[id]
		var traits: Dictionary = sp.get("traits", {})
		var size := float(traits.get("size", 0.3))
		var sapient := bool(sp.get("sapient", false))
		# Peu de titanosaures tiennent dans l'écran, beaucoup de musaraignes.
		var cap := MAX_VISIBLE * (1.0 - 0.75 * size)
		var diet := String(traits.get("diet", "omnivore"))
		rows.append({
			species_id = id, name = String(sp.get("name", "?")),
			count = clampi(int(round(float(tr.fast) * cap)), 1, MAX_VISIBLE),
			density = clampf(float(tr.fast), 0.0, 1.0), trend = int(tr.trend),
			role = "sapient" if sapient else ("producer" if diet == "autotrophe" else diet),
			habitat = String(traits.get("habitat", "land")),
			size = size, clade = String(traits.get("clade", "")), diet = String(traits.get("diet", "omnivore")),
			change = (float(tr.fast) - float(tr.slow)) / maxf(float(tr.slow), 0.03),
		})
	rows.sort_custom(_fauna_before)
	fauna.clear()
	for k in mini(MAX_FAUNA, rows.size()):
		fauna.append(rows[k])


## Peuple sapient en tête, puis effectif décroissant (ordre total : déterministe).
func _fauna_before(a: Dictionary, b: Dictionary) -> bool:
	if (a.role == "sapient") != (b.role == "sapient"):
		return a.role == "sapient"
	if a.count != b.count:
		return a.count > b.count
	return a.species_id < b.species_id


## ▲/▼ : écart entre moyennes rapide et lente, seuils d'entrée/sortie, durée minimale d'affichage.
func _update_trend(tr: Dictionary, dt: float) -> void:
	if _fresh:
		tr.trend = 0
		return
	tr.hold = maxf(0.0, float(tr.hold) - dt)
	var rel := (float(tr.fast) - float(tr.slow)) / maxf(float(tr.slow), 0.03)
	var cur: int = tr.trend
	var want := cur
	if rel > TREND_ENTER:
		want = 1
	elif rel < -TREND_ENTER:
		want = -1
	elif (cur == 1 and rel < TREND_EXIT) or (cur == -1 and rel > -TREND_EXIT):
		want = 0
	if want != cur and float(tr.hold) <= 0.0:
		tr.trend = want
		tr.hold = TREND_HOLD


# =============================================================================================
# Crises
# =============================================================================================

func _update_alerts(dt: float, out: Array[Dictionary]) -> void:
	var on := {}
	var list: Array[Dictionary] = []
	# 1) Espèces qui s'effondrent (le peuple sapient relève de la menace sur la civilisation).
	for id in _track:
		var tr: Dictionary = _track[id]
		if not tr.present or float(tr.peak) < COLLAPSE_MIN_PEAK or id == sapient_id:
			continue
		var drop := 1.0 - float(tr.fast) / float(tr.peak)
		var key := "collapse:%d" % id
		if _hysteresis(key, drop, 0.5, 0.35, on):
			var pct := int(round(drop * 100.0))
			list.append(_alert("species_collapse", id, drop, Text.about(_name(id),
				"%s s'effondre sur la parcelle (-" + str(pct) + " %%).",
				"%s s'effondrent sur la parcelle (-" + str(pct) + " %%)."), int(tr.cause)))
	# 2) Dérive de la chaleur mondiale par rapport au climat récent.
	_heat_fast = _relax(_heat_fast, global_temperature_c, dt, TAU_HEAT_FAST)
	_heat_slow = _relax(_heat_slow, global_temperature_c, dt, TAU_HEAT_SLOW)
	var drift := _heat_fast - _heat_slow
	if _hysteresis("heat", absf(drift), HEAT_ALERT_IN, HEAT_ALERT_OUT, on):
		var text := ("La chaleur monte : %s °C par rapport au climat récent." if drift > 0.0
			else "Le froid s'installe : %s °C par rapport au climat récent.") % Text.signed_decimal(drift)
		list.append(_alert("heat_drift", -1, clampf(absf(drift) / 8.0, 0.0, 1.0), text,
			_cold_cause if drift < 0.0 else -1))
	# 3) Civilisation menacée : épreuves, déclin du bâti, effondrement du peuple.
	var people := sapient_id if sapient_id >= 0 else (_last_sapient if _level >= 1 else -1)
	if people >= 0:
		var threat := _hardship
		if _level >= 1:
			threat = maxf(threat, clampf((development - target_development) / 2.5, 0.0, 1.0))
		if _track.has(people) and float(_track[people].peak) >= COLLAPSE_MIN_PEAK:
			threat = maxf(threat, 1.0 - float(_track[people].fast) / float(_track[people].peak))
		if _hysteresis("civ", threat, 0.35, 0.2, on):
			list.append(_alert("civilization_threat", people, clampf(threat, 0.0, 1.0),
				"La civilisation %s est menacée sur la parcelle." % Text.of_species(_name(people)), _harm_cause))
	list.sort_custom(_alert_before)
	if not _fresh:
		for a in list:
			var key := _alert_key(a)
			if not _alert_on.has(key):
				out.append(_event("crisis", a.summary, a.species_id, a.cause_id))
	_alert_on = on
	alerts = list


func _alert_before(a: Dictionary, b: Dictionary) -> bool:
	if a.severity != b.severity:
		return a.severity > b.severity
	if a.kind != b.kind:
		return a.kind < b.kind
	return a.species_id < b.species_id


## Seuils d'entrée/sortie : une alerte active le reste tant que `value` ne passe pas sous `exit`.
func _hysteresis(key: String, value: float, enter: float, exit: float, on: Dictionary) -> bool:
	var active := value >= (exit if _alert_on.has(key) else enter)
	if active:
		on[key] = true
	return active


func _alert_key(a: Dictionary) -> String:
	match String(a.kind):
		"species_collapse":
			return "collapse:%d" % int(a.species_id)
		"heat_drift":
			return "heat"
	return "civ"


func _alert(kind: String, species_id: int, severity: float, summary: String, cause_id: int) -> Dictionary:
	return {kind = kind, species_id = species_id, severity = clampf(severity, 0.0, 1.0),
		summary = summary, cause_id = cause_id}


# =============================================================================================
# Structures et historique
# =============================================================================================

func _update_structures() -> void:
	structures.clear()
	if land_use in ["ocean", "crater", "ice", "seabed", "microbial_mat", "reef", "barren"]:
		return
	var d := development
	var fields := int(round(clampf((d - 1.6) * 2.5, 0.0, 9.0) * (1.0 - smoothstep(5.0, 7.5, d))))
	if land_use == "flooded":
		fields = 0
	var huts := int(round(clampf((d - 0.8) * 2.5, 0.0, 10.0) * (1.0 - smoothstep(4.5, 6.0, d))))
	var buildings := int(round(clampf((d - 4.2) * 4.0, 0.0, 14.0) * (1.0 - 0.5 * smoothstep(6.8, 8.0, d))))
	var towers := int(round(clampf((d - 6.6) * 5.0, 0.0, 10.0)))
	var roads := clampi(int(floor(d - 3.0)), 0, 4)
	var ruins := int(round(clampf((_built - d - 0.8) * 1.5, 0.0, 12.0)))
	for k in fields:
		structures.append({kind = "field", pos = _spot(1, k), size = 0.12})
	for k in roads:
		structures.append({kind = "road", pos = _spot(2, k), size = 1.0})
	for k in huts:
		structures.append({kind = "hut", pos = _spot(3, k), size = 0.025})
	for k in buildings:
		structures.append({kind = "building", pos = _spot(4, k), size = 0.04})
	for k in towers:
		structures.append({kind = "tower", pos = _spot(5, k), size = 0.05})
	for k in ruins:
		structures.append({kind = "ruin", pos = _spot(6, k), size = 0.03 + 0.005 * minf(_built, 8.0)})


## Position stable (0.1..0.9) de la k-ième structure d'un type : ne saute pas d'une frame à l'autre.
func _spot(kind: int, k: int) -> Vector2:
	var h := hash([world.seed, cell, kind, k])
	return Vector2(float(h & 0xFFFF) / 65535.0, float((h >> 16) & 0xFFFF) / 65535.0) * 0.8 + Vector2(0.1, 0.1)


## Échantillonne l'historique en temps simulé : un point tous les HISTORY_STEPS pas idéaux, les
## points tombés entre deux appels étant interpolés (la courbe ne dépend pas de la cadence).
func _record() -> void:
	var pop := {}
	for f in fauna:
		pop[f.species_id] = f.count
	var cur := {
		year = year, temperature_c = temperature_c, global_temperature_c = global_temperature_c,
		population = pop, vegetation = vegetation, development = development,
	}
	var interval := _ideal * HISTORY_STEPS
	if history.is_empty():
		history.append(_sample(cur, cur, year, 1.0))
		_next_sample = year + interval
		_snap = cur
		return
	var y0: float = _snap.year
	if year >= _next_sample and year > y0:
		var n := int(floor((year - _next_sample) / interval)) + 1
		var ts := _next_sample
		if n > MAX_SAMPLES_PER_UPDATE:
			ts += float(n - MAX_SAMPLES_PER_UPDATE) * interval
			n = MAX_SAMPLES_PER_UPDATE
		for k in n:
			history.append(_sample(_snap, cur, ts, clampf((ts - y0) / (year - y0), 0.0, 1.0)))
			ts += interval
		_next_sample = ts
		while history.size() > HISTORY_SIZE:
			history.pop_front()
	_snap = cur


func _sample(a: Dictionary, b: Dictionary, at_year: float, f: float) -> Dictionary:
	var pop := {}
	var total := 0
	var pa: Dictionary = a.population
	var pb: Dictionary = b.population
	for id in pb:
		var c := int(round(lerpf(float(pa.get(id, 0)), float(pb[id]), f)))
		if c > 0:
			pop[id] = c
			total += c
	for id in pa:
		if not pb.has(id):
			var c := int(round(float(pa[id]) * (1.0 - f)))
			if c > 0:
				pop[id] = c
				total += c
	return {
		year = at_year,
		temperature_c = lerpf(a.temperature_c, b.temperature_c, f),
		global_temperature_c = lerpf(a.global_temperature_c, b.global_temperature_c, f),
		population_total = total, population = pop,
		vegetation = lerpf(a.vegetation, b.vegetation, f),
		development = lerpf(a.development, b.development, f),
	}


func _name(id: int) -> String:
	if id >= 0 and world.species.has(id):
		return String(world.species[id].get("name", ""))
	return ""


func _event(type: String, summary: String, species_id := -1, cause_id := -1) -> Dictionary:
	return {year = year, type = "parcel_" + type, region = cell, species_id = species_id,
		summary = summary, cause_id = cause_id, id = -1}
