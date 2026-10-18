extends RefCounted
## Samaël, l'adversaire (src/strategy/samael.gd) et zéro anachronisme (docs/STRATEGIE.md §8 et §9) :
## déterminisme, Éveil < Divin < Apocalypse en dégâts, l'habitude apprise change le choix, aucune carte
## au-dessus de son époque, budget de temps de l'Oracle.
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const WorldSim := preload("res://src/sim/world_sim.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")
const Eras := preload("res://src/sim/eras.gd")
const Strategy := preload("res://src/strategy/strategy.gd")
const Samael := preload("res://src/strategy/samael.gd")
const Rules := preload("res://src/strategy/strategy_rules.gd")
const Base := preload("res://tests/test_strategy.gd")

const RANK_SEEDS := [11, 23, 37, 58, 71, 94]
## Poids d'un effondrement en chaîne dans les dégâts de référence.
const COLLAPSE_DAMAGE := 0.6


func _setup(seed_value: int, difficulty: String, aspect := "guardian", scenario := "") -> Dictionary:
	return Base.new()._setup(seed_value, aspect, difficulty, "trial", scenario)


func _frame(g: Dictionary) -> Array:
	return Base.new()._frame(g)


func test_samael_deterministic() -> String:
	var traces := []
	for run in 2:
		var g := _setup(77, "apocalypse")
		var moves := []
		g.st.samael_move.connect(func(m): moves.append("%s:%s:%s" % [m.kind, m.threat.get("kind", ""), m.reason_code]))
		for i in 300:
			_frame(g)
			if i % 40 == 0 and g.st.round.threats.size() > 0:
				g.st.spend_action(g.st.round.threats[0].counters[0])
		traces.append(",".join(moves))
	if traces[0] != traces[1]:
		return "Samaël diverge à graine égale :\n%s\n---\n%s" % [traces[0], traces[1]]
	if traces[0] == "":
		return "aucun coup de Samaël"
	return ""


## Dégâts de référence d'un choix : dégâts réels juste après la frappe (un dixième de manche)
## + dégâts projetés sur l'horizon de l'Oracle (« ce qui fera le plus mal dans plusieurs manches »).
## Règle du jeu comprise : frapper une espèce déjà en chute ajoute un effondrement en chaîne.
func _reference_damage(chosen: Array, world: RefCounted, cell: Vector2i, horizon: float, cache: Dictionary,
		collapsing := []) -> float:
	var total := 0.0
	for t in chosen:
		if int(t.target.species_id) in collapsing:
			total += COLLAPSE_DAMAGE
		var a := Samael._action_of(t)
		var key := Samael._key(a)
		if not cache.has(key):
			cache[key] = Samael.project_damage(world, cell, a, horizon * 0.05, Samael.ORACLE_SUBSTEPS) 				+ Samael.project_damage(world, cell, a, horizon, Samael.ORACLE_SUBSTEPS)
		total += float(cache[key])
	return total


## Instantané d'une partie (copie du monde) et une main de Samaël tirée à cet instant.
func _hand_point(g: Dictionary, seed_value: int) -> Dictionary:
	var sim: RefCounted = g.sim.fork()
	var parcel := ParcelSim.new(sim, g.parcel.cell)
	parcel.update([])
	var st := Strategy.new(seed_value, "guardian", "divin", "trial")
	st.start(sim, parcel)
	var copy := {sim = sim, parcel = parcel, st = st}
	return {seed = seed_value, g = copy, hand = st._draw_hand(sim, parcel).filter(func(t): return not t.cataclysm)}


func test_levels_are_ranked() -> String:
	var sums := {random = 0.0, greedy = 0.0, oracle = 0.0}
	var samples := 0
	# Mains prises à trois moments de chaque partie : prologue, Mésozoïque, Antiquité ; la moitié des
	# graines part du prologue (-3,8 Ga), l'autre du scénario Crétacé (-66 Ma).
	var points := []
	for si in RANK_SEEDS.size():
		var s: int = RANK_SEEDS[si]
		var g := _setup(s, "eveil", "guardian", "" if si % 2 == 0 else WorldSim.SCENARIO_CRETACEOUS)
		var player := Base.new()
		var marks := [func(): return g.sim.era_index() >= 1,
			func(): return g.sim.era_index() >= Eras.MESOZOIC,
			func(): return g.sim.era_index() >= Eras.FIRST_SAPIENT_ERA + 1]
		var m := 0
		for i in 2500:
			if m >= marks.size() or g.st.over:
				break
			_frame(g)
			player._auto_play(g.st)
			if marks[m].call():
				points.append(_hand_point(g, s))
				m += 1
	for p in points:
		if p.is_empty():
			continue
		var s: int = p.seed
		var g: Dictionary = p.g
		var st: RefCounted = g.st
		var hand: Array = p.hand
		if hand.size() < 3:
			continue
		var n := 2
		var ctx: Dictionary = st._samael_context(g.sim, g.parcel)
		# On mesure l'intelligence de destruction seule : Grands Œuvres hors jeu (testés à part).
		ctx.works = {life = true, land = true, mind = true, legacy = true}
		var horizon: float = Samael.ORACLE_ROUNDS * float(st.round.steps) * g.sim.ideal_step_years()
		var cache := {}
		for difficulty in ["eveil", "divin", "apocalypse"]:
			var sam := Samael.new(s, difficulty)
			var copy := hand.duplicate(true)
			if sam.level == "oracle":
				sam.plan(copy, g.sim, g.parcel.cell, horizon)
			var dmg := 0.0
			if sam.level == "random":
				# Éveil : moyenne sur plusieurs tirages (le hasard est son seul talent).
				for k in 4:
					var r := Samael.new(s * 31 + k, difficulty)
					dmg += _reference_damage(r.choose(hand.duplicate(true), n, ctx), g.sim, g.parcel.cell, horizon, cache, ctx.collapsing) / 4.0
			else:
				dmg = _reference_damage(sam.choose(copy, n, ctx), g.sim, g.parcel.cell, horizon, cache, ctx.collapsing)
			sums[sam.level] += dmg
		samples += 1
	if samples < 6:
		return "trop peu d'échantillons (%d)" % samples
	print("  dégâts moyens sur %d mains : Éveil %.3f, Divin %.3f, Apocalypse %.3f" % [
		samples, sums.random / samples, sums.greedy / samples, sums.oracle / samples])
	if not (sums.oracle > sums.greedy and sums.greedy > sums.random):
		return "ordre attendu Apocalypse > Divin > Éveil : %.3f / %.3f / %.3f" % [sums.oracle, sums.greedy, sums.random]
	return ""


func test_learned_habit_changes_choice() -> String:
	var sam := Samael.new(5, "divin")
	var learned := []
	sam.learned.connect(func(h): learned.append(h))
	var target := {region = Vector2i(10, 10), species_id = 3}
	var a := {id = 1, kind = "drought", severity = 0.5, target = target.duplicate(), counters = ["flood", "bless"]}
	var b := {id = 2, kind = "epidemic", severity = 0.5, target = target.duplicate(), counters = ["save", "bless"]}
	var ctx := {species = [{species_id = 3, density = 0.5, role = "herbivore"}], sapients = [], smartest = -1,
		collapsing = [], collapses = 0, collapse_limit = 8,
		works = {life = true, land = true, mind = true, legacy = true}, works_ready = {}, budget = 4}
	var first: Array = sam.choose([a.duplicate(true), b.duplicate(true)], 1, ctx)
	if first[0].kind != "drought":
		return "sans habitude, la carte attendue est la sécheresse (obtenu %s)" % first[0].kind
	for i in 3:
		sam.note_counter("flood")
	if sam.favorite != "flood" or learned.is_empty() or learned[0].power != "flood":
		return "habitude « déluge » non apprise : %s / %s" % [sam.favorite, learned]
	var second: Array = sam.choose([a.duplicate(true), b.duplicate(true)], 1, ctx)
	if second[0].kind != "epidemic":
		return "l'habitude n'a pas changé le choix (%s)" % second[0].kind
	if second[0].samael.reason_code != "exploits_habit_flood":
		return "raison attendue exploits_habit_flood, obtenue %s" % second[0].samael.reason_code
	# Éveil n'apprend pas.
	var dumb := Samael.new(5, "eveil")
	for i in 3:
		dumb.note_counter("flood")
	if dumb.favorite != "":
		return "Samaël Éveil ne devrait pas apprendre"
	return ""


## Niveau technologique typique de la civilisation de tête à chaque ère (aucune avant la sapience).
static func _lead_for(era: int, fraction: float) -> float:
	return -1.0 if era < Eras.FIRST_SAPIENT_ERA else float(era - Eras.FIRST_SAPIENT_ERA) + fraction


func test_no_anachronism_each_era() -> String:
	for era in range(0, Eras.LAST_ERA + 1):
		for fraction in [0.0, 0.5, 0.99]:
			var lead := _lead_for(era, fraction)
			var act := Rules.act_for(era, lead >= 0.0)
			for majors in [false, true]:
				for k in Rules.legal_kinds(act, era, lead, majors):
					var def: Dictionary = Rules.THREATS[k]
					if era < int(def.get("min_era", -Rules.NO_ERA_LIMIT)) or era > int(def.get("max_era", Rules.NO_ERA_LIMIT)):
						return "%s légale à l'ère %d hors de ses bornes" % [k, era]
					if def.has("min_tech") and lead < float(def.min_tech):
						return "%s légale avec la technique %.2f < %.2f" % [k, lead, def.min_tech]
					for c in Rules.counters(k, era):
						if not Rules.POWER_LABELS.has(c):
							return "contre inconnu %s" % c
	# Règles explicites de §9.
	var modern := Eras.FIRST_SAPIENT_ERA + 5
	var checks := [
		["hostile_ai", modern, 5.2, false], ["hostile_ai", modern, Rules.AI_TECH, true],
		["hostile_ai", Eras.FIRST_SAPIENT_ERA + 2, 2.5, false],
		["nuclear_war", Eras.FIRST_SAPIENT_ERA + 4, 4.9, false],
		["pollution", Eras.FIRST_SAPIENT_ERA + 3, 3.5, false], ["pollution", Eras.FIRST_SAPIENT_ERA + 4, 4.1, true],
		["famine", Eras.FIRST_SAPIENT_ERA, 0.5, false], ["famine", Eras.FIRST_SAPIENT_ERA + 1, 1.2, true],
		["war", Eras.FIRST_SAPIENT_ERA, 0.9, false], ["overgrazing", Eras.MESOZOIC - 1, -1.0, false],
		["oxidation", Eras.MESOZOIC, -1.0, false], ["drought", Eras.MESOZOIC, -1.0, true],
	]
	for c in checks:
		if Rules.epoch_ok(c[0], c[1], c[2]) != c[3]:
			return "epoch_ok(%s, ère %d, technique %.2f) devrait valoir %s" % c
	# En partie : aucune carte révélée ni tenue en main au-dessus de l'époque réelle.
	var g := _setup(4242, "eveil")
	var player := Base.new()
	var bad := []
	var check := func(t):
		if not Rules.epoch_ok(t.kind, g.sim.era_index(), Strategy._leading_tech(g.sim)):
			bad.append("%s (ère %s)" % [t.kind, g.sim.current_era()])
	g.st.threat_revealed.connect(check)
	var eras_seen := {}
	for i in 1400:
		_frame(g)
		player._auto_play(g.st)
		eras_seen[g.sim.era_index()] = true
		for t in g.st._hand:
			check.call(t)
		if g.st.over:
			break
	g.st.threat_revealed.disconnect(check)
	if not bad.is_empty():
		return "cartes anachroniques : %s" % ", ".join(bad.slice(0, 5))
	if eras_seen.size() < 3:
		return "trop peu d'ères traversées (%d)" % eras_seen.size()
	return ""


func test_apocalypse_time_budget() -> String:
	# Départ au prologue (pas idéaux énormes) et scénario Crétacé.
	for scenario in ["", WorldSim.SCENARIO_CRETACEOUS]:
		var g := _setup(31, "apocalypse", "guardian", scenario)
		var st: RefCounted = g.st
		var finished := false
		for i in 400:
			_frame(g)
			finished = finished or (not st.samael._oracle.is_empty())
			if st.over:
				break
		var max_ms: float = st.samael.max_think_usec / 1000.0
		print("  Oracle de Samaël (%s) : %.2f ms au plus par image (budget %.1f ms), attente au choix %.1f ms" % [
			"prologue" if scenario == "" else scenario, max_ms, Samael.ORACLE_BUDGET_USEC / 1000.0,
			st.samael.max_wait_usec / 1000.0])
		if st.samael.max_think_usec > Samael.ORACLE_BUDGET_USEC:
			return "budget de temps dépassé : %.2f ms" % max_ms
		if not finished:
			return "l'Oracle n'a jamais terminé de projection (%s)" % scenario
	# Divin ne consulte jamais l'Oracle.
	var d := _setup(31, "divin")
	for i in 60:
		_frame(d)
	if d.st.samael.max_think_usec > 200 or d.st.samael.oracle_pending() > 0:
		return "Samaël Divin consulte l'Oracle"
	return ""


## Passage prologue → Mésozoïque avec des Cataclysmes : les cartes déjà en circulation (pioche,
## défausse remélangée, main de Samaël, menaces engagées) ne survivent pas à leur époque.
func test_epoch_change_purges_cards_in_circulation() -> String:
	var g := _setup(4242, "eveil")
	var st: RefCounted = g.st
	var player := Base.new()
	# Cartes du prologue en circulation, et des Cataclysmes pour remélanger souvent la défausse.
	for i in 8:
		st._discard.append({kind = "oxidation", severity = 0.5})
		st._deck.insert(st._deck.size() - 1 - i * 3, {cataclysm = i % 2 == 0, kind = "oxidation" if i % 2 else "", severity = 0.75})
	var bad := []
	var seen := {}
	var check_all := func():
		var era: int = g.sim.era_index()
		var lead: float = Strategy._leading_tech(g.sim)
		var cards := []
		for t in st._hand + st.next_threats:
			cards.append(["main", t.kind])
		for c in st._deck + st._discard:
			if String(c.kind) != "":
				cards.append(["pioche", c.kind])
		for c in cards:
			if not Rules.epoch_ok(c[1], era, lead):
				bad.append("%s %s (ère %s)" % [c[0], c[1], g.sim.current_era()])
	var on_reveal := func(t):
		if not Rules.epoch_ok(t.kind, g.sim.era_index(), Strategy._leading_tech(g.sim)):
			bad.append("révélée %s (ère %s)" % [t.kind, g.sim.current_era()])
	st.threat_revealed.connect(on_reveal)
	var mesozoic_frames := 0
	for i in 2500:
		_frame(g)
		player._auto_play(st)
		check_all.call()
		seen[g.sim.era_index()] = true
		if g.sim.era_index() >= Eras.MESOZOIC:
			mesozoic_frames += 1
		if mesozoic_frames > 150 or st.over or not bad.is_empty():
			break
	st.threat_revealed.disconnect(on_reveal)
	print("  ères traversées : %s, cataclysmes %d" % [seen.keys(), st.cataclysms])
	if not bad.is_empty():
		return "cartes anachroniques en circulation : %s" % ", ".join(bad.slice(0, 5))
	if mesozoic_frames == 0:
		return "le Mésozoïque n'a pas été atteint (%s)" % [seen.keys()]
	if st.cataclysms < 2:
		return "trop peu de Cataclysmes pour éprouver le remélange (%d)" % st.cataclysms
	return ""
