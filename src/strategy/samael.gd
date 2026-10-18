extends RefCounted
## Samaël, l'adversaire (docs/STRATEGIE.md §8) : règles fixes, l'IA ne fait que le faire parler.
##
## À chaque manche, il reçoit une main de cartes de menace légales (tirées de la pioche, filtrées par
## l'époque) et choisit celles qu'il révèle et leur moment de frappe. Il ne crée jamais de carte et ne
## voit que ce que le joueur voit (monde, parcelle, pistes, budget ; l'Oracle comme le joueur).
## Déterministe à graine égale et à suite d'appels égale.
##
## Son intelligence dépend de la difficulté :
## - Éveil : au hasard dans sa main.
## - Divin : la carte qui fait le plus mal tout de suite (vitalité, Grands Œuvres non scellés, risque
##   d'effondrement en chaîne, menaces que le budget ne pourra pas contrer) ; il apprend les contres
##   préférés du joueur et joue ce qu'ils ne couvrent pas.
## - Apocalypse : en plus, il consulte l'Oracle : copie du monde (fork) projetée à basse résolution
##   (comme project_future, mais étalée sur plusieurs images avec un budget de travail par image).

## Une habitude du joueur vient d'être apprise : {power, weight, share}.
signal learned(habit: Dictionary)

const Rules := preload("res://src/strategy/strategy_rules.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")

const LEVEL_BY_DIFFICULTY := {eveil = "random", divin = "greedy", apocalypse = "oracle"}

## Cartes en plus de l'intensité dans la main de Samaël.
const HAND_EXTRA := 3
## Oracle : pas de simulation par projection (basse résolution), projections au plus (dont la
## référence sans frappe). Il tourne sur un thread dédié : l'image ne paie que la relève des
## résultats, sous ORACLE_BUDGET_USEC (budget de temps strict par image).
const ORACLE_SUBSTEPS := 10
const ORACLE_MAX_CANDIDATES := 5
const ORACLE_BUDGET_USEC := 4000
## Horizon de l'Oracle : ce nombre de manches.
const ORACLE_ROUNDS := 2.0
const ORACLE_WEIGHT := 3.0
## Apprentissage : oubli par manche, seuils pour qu'une habitude soit retenue.
const HABIT_DECAY := 0.8
const HABIT_MIN := 1.5
const HABIT_SHARE := 0.4
## Un facteur doit peser au moins autant pour devenir la raison affichée (sinon « max_damage »).
const REASON_MIN := 0.15

var level := "greedy"
## Contres du joueur : pouvoir -> poids (oublié peu à peu).
var habits := {}
## Contre préféré connu de Samaël ("" : aucun).
var favorite := ""
## Mesures du budget de temps de l'Oracle (µs) : dernier appel de think(), maximum observé, et
## attente la plus longue au moment d'un choix (projections pas encore finies, rare).
var last_think_usec := 0
var max_think_usec := 0
var max_wait_usec := 0

var _rng := RandomNumberGenerator.new()
var _thread: Thread = null
## État partagé avec le thread de l'Oracle (le thread ne tient aucune référence à Samaël).
var _shared := OracleState.new()
var _strategy_script: Script = load("res://src/strategy/strategy.gd")
var _oracle := {}
var _base := {}


class OracleState:
	extends RefCounted
	var mutex := Mutex.new()
	var pending := 0
	var cancel := false

	func cancelled() -> bool:
		mutex.lock()
		var c := cancel
		mutex.unlock()
		return c


func _init(p_seed: int, difficulty: String) -> void:
	level = String(LEVEL_BY_DIFFICULTY.get(difficulty, "greedy"))
	_rng.seed = hash("samael:%d:%s" % [p_seed, difficulty])


# =============================================================================================
# Apprentissage
# =============================================================================================

## Le joueur vient de contrer une menace avec ce pouvoir.
func note_counter(power: String) -> void:
	if level == "random":
		return
	habits[power] = float(habits.get(power, 0.0)) + 1.0
	_update_favorite()


## Fin de manche : les habitudes s'estompent.
func end_round() -> void:
	for p in habits.keys():
		habits[p] = float(habits[p]) * HABIT_DECAY
	_update_favorite()


func habit_share(power: String) -> float:
	var total := 0.0
	for p in habits:
		total += float(habits[p])
	return float(habits.get(power, 0.0)) / total if total > 0.0 else 0.0


func _update_favorite() -> void:
	var best := ""
	var best_w := 0.0
	var keys := habits.keys()
	keys.sort()
	for p in keys:
		if float(habits[p]) > best_w:
			best_w = float(habits[p])
			best = p
	if best != "" and (best_w < HABIT_MIN or habit_share(best) < HABIT_SHARE):
		best = ""
	if best != favorite:
		favorite = best
		if best != "":
			learned.emit({power = best, weight = best_w, share = habit_share(best)})


# =============================================================================================
# Oracle (Apocalypse)
# =============================================================================================

## Prépare la consultation de l'Oracle pour une main : référence sans frappe + une projection par
## frappe distincte, calculées sur un thread dédié (l'image n'attend jamais). Le résultat ne dépend
## pas du temps de calcul : choose() attend la fin des projections (elles ont une demi-manche).
func plan(hand: Array, world: RefCounted, cell: Vector2i, horizon_years: float) -> void:
	_join()
	_oracle.clear()
	_base.clear()
	if level != "oracle" or hand.is_empty():
		return
	var jobs := [{key = "", action = {}}]
	var keys := {}
	for t in hand:
		var a := _action_of(t)
		var key := _key(a)
		if keys.has(key) or keys.size() >= ORACLE_MAX_CANDIDATES - 1:
			continue
		keys[key] = true
		jobs.append({key = key, action = a})
	_shared.mutex.lock()
	_shared.pending = jobs.size()
	_shared.cancel = false
	_shared.mutex.unlock()
	_thread = Thread.new()
	_thread.start(_run.bind(world.fork(), jobs, cell, horizon_years, _shared, _strategy_script))


## Projections restant à calculer.
func oracle_pending() -> int:
	_shared.mutex.lock()
	var n := _shared.pending
	_shared.mutex.unlock()
	return n


## Appelée à chaque image : récupère les projections terminées, sans jamais attendre.
func think() -> void:
	var t0 := Time.get_ticks_usec()
	if _thread != null and not _thread.is_alive():
		_join()
	last_think_usec = Time.get_ticks_usec() - t0
	max_think_usec = maxi(max_think_usec, last_think_usec)


## Attend la fin de l'Oracle (avant un choix). Mesure l'attente éventuelle.
func wait_oracle() -> void:
	if _thread == null:
		return
	var t0 := Time.get_ticks_usec()
	_join()
	max_wait_usec = maxi(max_wait_usec, Time.get_ticks_usec() - t0)


func _join() -> void:
	if _thread == null:
		return
	var out: Dictionary = _thread.wait_to_finish()
	_thread = null
	_base = out.get("", {})
	for k in out:
		if k != "" and not _base.is_empty():
			_oracle[k] = damage(_base, out[k])


## Thread de l'Oracle : copies du monde projetées à basse résolution (comme project_future).
static func _run(snapshot: RefCounted, jobs: Array, cell: Vector2i, horizon: float, shared: OracleState,
		strategy_script: Script) -> Dictionary:
	var out := {}
	for job in jobs:
		var f: RefCounted = snapshot.fork()
		f.max_substeps = 1
		var events: Array[Dictionary] = []
		if not job.action.is_empty():
			events.append_array(f.apply_divine_action(job.action))
		var era: int = f.era_index()
		for i in ORACLE_SUBSTEPS:
			if shared.cancelled():
				return out
			events.append_array(f.step(horizon / ORACLE_SUBSTEPS))
			era = maxi(era, f.era_index())
		out[job.key] = measure(f, snapshot, cell, events, era, strategy_script)
		shared.mutex.lock()
		shared.pending -= 1
		shared.mutex.unlock()
	return out


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _thread != null:
		_shared.mutex.lock()
		_shared.cancel = true
		_shared.mutex.unlock()
		_thread.wait_to_finish()


## Dégâts prévus par l'Oracle pour cette carte (0 si la projection n'est pas finie).
func oracle_damage(t: Dictionary) -> float:
	var v = _oracle.get(_key(_action_of(t)), 0.0)
	return float(v) if typeof(v) == TYPE_FLOAT else 0.0


## État d'un futur projeté : vitalité de la parcelle, extinctions, technologie, peuples conscients.
static func measure(fork: RefCounted, origin: RefCounted, cell: Vector2i, events: Array, era_reached: int,
		strategy_script: Script) -> Dictionary:
	var typed: Array[Dictionary] = []
	for e in events:
		typed.append(e)
	var summary: Dictionary = fork.summarize_since(origin, typed, era_reached)
	var parcel := ParcelSim.new(fork, cell)
	parcel.update([])
	var lead := -1.0
	for s in summary.get("sapient_species", []):
		lead = maxf(lead, float(s.tech_level))
	var density := 0.0
	for n in fork.region_niches(cell):
		density += float(n.density)
	return {
		vitality = strategy_script.vitality_of(fork, parcel), density = density, extinct = summary.get("extinct_species", []).size(),
		lead_tech = lead, sapients = summary.get("sapient_species", []).size(),
	}


## Dégâts d'un futur par rapport à la référence (plus grand = pire pour Dieu).
static func damage(base: Dictionary, m: Dictionary) -> float:
	var d := (float(base.vitality) - float(m.vitality)) + 0.5 * (float(base.density) - float(m.density)) 		+ 0.04 * (int(m.extinct) - int(base.extinct))
	if float(base.lead_tech) >= 0.0:
		d += 0.4 * (float(base.lead_tech) - maxf(float(m.lead_tech), 0.0))
		if int(m.sapients) == 0:
			d += 1.0
	return d


## Référence synchrone (tests) : dégâts d'une frappe projetée `substeps` pas plus loin.
static func project_damage(world: RefCounted, cell: Vector2i, action: Dictionary, horizon: float, substeps: int) -> float:
	var res := []
	for with_strike in [false, true]:
		var f: RefCounted = world.fork()
		f.max_substeps = 1
		var events: Array[Dictionary] = []
		if with_strike:
			events.append_array(f.apply_divine_action(action))
		var era: int = f.era_index()
		for i in substeps:
			events.append_array(f.step(horizon / substeps))
			era = maxi(era, f.era_index())
		res.append(measure(f, world, cell, events, era, load("res://src/strategy/strategy.gd")))
	return damage(res[0], res[1])


# =============================================================================================
# Choix
# =============================================================================================

## Choisit `n` cartes de la main et leur moment de frappe (strike_at). Chaque carte choisie reçoit
## `samael = {reason_code, score}`. ctx : voir Strategy._samael_context().
func choose(hand: Array, n: int, ctx: Dictionary) -> Array:
	n = mini(n, hand.size())
	var picked := []
	if level == "random":
		var pool := hand.duplicate()
		for k in n:
			var t: Dictionary = pool.pop_at(_rng.randi_range(0, pool.size() - 1))
			t.samael = {reason_code = "random", score = 0.0}
			picked.append(t)
		_time_random(picked)
		return picked
	if level == "oracle":
		wait_oracle()
	var pool := hand.duplicate()
	for k in n:
		var best: Dictionary = {}
		var best_s := {score = -INF}
		for t in pool:
			var s := score(t, ctx, k)
			if s.score > best_s.score or (s.score == best_s.score and int(t.id) < int(best.id)):
				best = t
				best_s = s
		pool.erase(best)
		best.samael = best_s
		picked.append(best)
	# La plus dangereuse frappe la première : moins de temps pour réagir.
	for i in picked.size():
		picked[i].strike_at = Rules.STRIKE_FROM + (Rules.STRIKE_TO - Rules.STRIKE_FROM) \
			* (i + 0.3 * _rng.randf()) / float(maxi(picked.size(), 1))
	return picked


func _time_random(picked: Array) -> void:
	var n := picked.size()
	for i in n:
		picked[i].strike_at = Rules.STRIKE_FROM + (Rules.STRIKE_TO - Rules.STRIKE_FROM) * (i + _rng.randf()) / float(n)


## Note d'une carte : {score, reason_code}. `k` : cartes déjà choisies cette manche.
func score(t: Dictionary, ctx: Dictionary, k: int) -> Dictionary:
	var parts := {}
	var sid := int(t.target.species_id)
	parts.max_damage = immediate_damage(t, ctx)
	# Grands Œuvres non scellés que la carte met en danger.
	var works: Dictionary = ctx.get("works", {})
	for w in Rules.WORK_ORDER:
		if works.get(w, true) or not _threatens(t, w, ctx):
			continue
		var v := 0.5 + (0.3 if ctx.get("works_ready", {}).get(w, false) else 0.0)
		if v > float(parts.get("targets_work_" + w, 0.0)):
			parts["targets_work_" + w] = v
	if sid >= 0 and sid in ctx.get("collapsing", []):
		parts.chain_risk = 0.6 * (1.0 + float(ctx.get("collapses", 0)) / maxf(float(ctx.get("collapse_limit", 8)), 1.0))
	if k >= int(ctx.get("budget", 4)):
		parts.budget_exhausted = 0.4
	if favorite != "":
		var share := habit_share(favorite)
		if favorite in t.counters:
			parts["habit_covered"] = -0.4 * share
		else:
			parts["exploits_habit_" + favorite] = 0.6 * share
	if level == "oracle":
		parts.oracle_foresees = ORACLE_WEIGHT * oracle_damage(t)
	# Raison affichée : le facteur décisif autre que les dégâts bruts, s'il pèse assez.
	var total := 0.0
	var reason := "max_damage"
	var top := REASON_MIN
	var codes := parts.keys()
	codes.sort()
	for c in codes:
		total += float(parts[c])
		if c != "max_damage" and c != "habit_covered" and float(parts[c]) > top:
			top = float(parts[c])
			reason = c
	return {score = total, reason_code = reason}


## Dégâts immédiats estimés sur la parcelle (mêmes unités que damage()) : densité des espèces tuées,
## vitalité perdue, recul technique. Lu dans ce que le joueur voit.
static func immediate_damage(t: Dictionary, ctx: Dictionary) -> float:
	var sid := int(t.target.species_id)
	var dens := 0.0
	var total := 0.0
	for s in ctx.get("species", []):
		total += float(s.density)
		if int(s.species_id) == sid:
			dens = float(s.density)
	var times := 2.0 if float(t.severity) >= Rules.DOUBLE_STRIKE_SEVERITY else 1.0
	var d := 0.0
	# Coefficients calibrés sur des projections de la simulation : un fléau ne laisse presque pas de
	# trace mesurable (les survivants repeuplent), un impact ou un refroidissement global, si.
	match String(Rules.THREATS[t.kind].strike):
		"plague":
			d = 0.1 * dens + (0.04 if sid in ctx.get("sapients", []) else 0.0)
		"meteor":
			d = 0.5 * total + 0.4
		"flood":
			d = 0.5 * 0.5 * total + 0.1
		_:
			d = 0.5 + 0.4 * total
	return d * times


## La carte menace-t-elle ce Grand Œuvre ? (lecture de ce que le joueur voit)
static func _threatens(t: Dictionary, work: String, ctx: Dictionary) -> bool:
	var strike := String(Rules.THREATS[t.kind].strike)
	var sid := int(t.target.species_id)
	var here: Array = ctx.get("species", [])
	var on_parcel := false
	for s in here:
		on_parcel = on_parcel or int(s.species_id) == sid
	var sapients: Array = ctx.get("sapients", [])
	match work:
		"life":
			return strike == "meteor" or (on_parcel and here.size() <= 3)
		"land":
			return strike in ["meteor", "flood"] or t.kind == "drought"
		"mind":
			if sapients.is_empty():
				return sid >= 0 and sid == int(ctx.get("smartest", -1))
			return sid in sapients or strike == "meteor"
		"legacy":
			return not sapients.is_empty() and (sid in sapients or strike == "meteor")
	return false


static func _action_of(t: Dictionary) -> Dictionary:
	return {type = String(Rules.THREATS[t.kind].strike), region = t.target.region,
		species_id = int(t.target.species_id), radius = Rules.strike_radius(t.kind, float(t.severity))}


static func _key(a: Dictionary) -> String:
	return "%s|%d|%d" % [a.type, a.species_id, a.radius]
