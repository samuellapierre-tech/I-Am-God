extends RefCounted
## Couche stratégique (src/strategy/) : déterminisme, budget d'actions, contres, Cataclysmes,
## pistes (effondrements, Grands Œuvres, sablier) et partie accélérée complète.
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const WorldSim := preload("res://src/sim/world_sim.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")
const Strategy := preload("res://src/strategy/strategy.gd")
const Rules := preload("res://src/strategy/strategy_rules.gd")

const SEED := 4242
const CELL := Vector2i(70, 40)


## Monde + parcelle + stratégie, première manche ouverte.
func _setup(seed_value := SEED, aspect := "guardian", difficulty := "divin") -> Dictionary:
	var sim := WorldSim.new(seed_value)
	var parcel := ParcelSim.new(sim, _lively_cell(sim))
	parcel.update([])
	var st := Strategy.new(seed_value, aspect, difficulty)
	st.start(sim, parcel)
	return {sim = sim, parcel = parcel, st = st}


## Terre peuplée la plus proche de CELL (comme la parcelle de départ du jeu : une terre vivante).
static func _lively_cell(sim: RefCounted) -> Vector2i:
	for r in range(0, 64, 2):
		for dy in range(-r, r + 1, 2):
			for dx in range(-r, r + 1, 2):
				var c := Vector2i(posmod(CELL.x + dx, WorldSim.WIDTH), clampi(CELL.y + dy, 0, WorldSim.HEIGHT - 1))
				if sim.elevation[c.y * WorldSim.WIDTH + c.x] > 0.05 and sim.region_niches(c).size() >= 3:
					return c
	return CELL


## Une image de jeu accélérée : pas de simulation, parcelle, stratégie (comme GameState._process).
func _frame(g: Dictionary) -> Array:
	var events: Array = g.sim.step(g.sim.ideal_step_years() * g.sim.max_substeps)
	var strikes: Array = g.st.update(g.sim, g.parcel, events)
	g.parcel.update(events + strikes)
	return strikes


## Avance jusqu'à la manche suivante (ou la fin de partie).
func _next_round(g: Dictionary, max_frames := 4000) -> void:
	var idx: int = g.st.round.index
	for i in max_frames:
		if g.st.over or g.st.round.index != idx:
			return
		_frame(g)


func _signature(st: RefCounted) -> String:
	var parts := ["r%d a%d c%d k%d d%d" % [st.round.index, st.actions_left, st.tracks.collapses, st.cataclysms, st.deck_left()]]
	for t in st.round.threats:
		parts.append("%s/%d/%.0f/%s" % [t.kind, t.target.species_id, t.strikes_year, t.state])
	return " ".join(parts)


func test_deterministic() -> String:
	var sigs := []
	for run in 2:
		var g := _setup()
		var trace := []
		for i in 400:
			_frame(g)
			if i % 25 == 0:
				trace.append(_signature(g.st))
		sigs.append("\n".join(trace))
	if sigs[0] != sigs[1]:
		return "deux parties de même graine divergent :\n%s\n---\n%s" % [sigs[0], sigs[1]]
	var other := _setup(SEED + 1)
	var g2 := _setup()
	if _signature(other.st) == _signature(g2.st) and other.sim.seed == g2.sim.seed:
		return "graine ignorée"
	return ""


func test_budget_respected() -> String:
	var g := _setup()
	var st: RefCounted = g.st
	var n: int = st.actions_per_round
	if n != int(Rules.DIFFICULTIES.divin.actions):
		return "budget Divin attendu %d, obtenu %d" % [Rules.DIFFICULTIES.divin.actions, n]
	for i in n:
		if not st.spend_action("meteor"):
			return "action %d/%d refusée alors que le budget n'est pas épuisé" % [i + 1, n]
	if st.can_act():
		return "can_act() vrai avec un budget épuisé"
	var refused := [false]
	st.action_refused.connect(func(_k): refused[0] = true)
	if st.spend_action("flood"):
		return "action acceptée au-delà du budget"
	if not refused[0]:
		return "action_refused non émis"
	_next_round(g)
	if st.actions_left != n:
		return "budget non rechargé à la manche suivante (%d)" % st.actions_left
	# Aspects : difficulté et gratuités.
	var easy := _setup(SEED, "prophet", "apocalypse")
	if easy.st.actions_per_round != 3:
		return "budget Apocalypse attendu 3"
	if not easy.st.spend_action("oracle") or easy.st.actions_left != 3:
		return "l'Oracle du Prophète devrait être gratuit"
	var creator := _setup(SEED, "creator")
	creator.st.spend_action("spawn_species")
	if creator.st.actions_left != 4:
		return "la première Création du Créateur devrait être gratuite"
	creator.st.spend_action("spawn_species")
	if creator.st.actions_left != 3:
		return "la deuxième Création du Créateur devrait coûter une action"
	return ""


func test_countered_threat_does_not_strike() -> String:
	var g := _setup(SEED, "creator")
	var st: RefCounted = g.st
	var resolved := {}
	st.threat_resolved.connect(func(t, countered): resolved[t.id] = resolved.get(t.id, []) + [countered])
	var target: Dictionary = st.round.threats[0]
	if target.counters.is_empty():
		return "menace sans contre : %s" % target.kind
	if st.counters_for(target) != target.counters:
		return "counters_for() ne correspond pas à la carte"
	if not st.spend_action(target.counters[0]):
		return "contre refusé"
	if target.state != "countered" or not target.countered:
		return "la menace n'est pas marquée contrée (%s)" % target.state
	var kind_root := "threat_" + String(target.kind)
	var same_kind := 0
	for t in st.round.threats:
		if t.kind == target.kind and t.id != target.id:
			same_kind += 1
	var struck_roots := 0
	var idx: int = st.round.index
	while st.round.index == idx and not st.over:
		for ev in _frame(g):
			if ev.type == kind_root:
				struck_roots += 1
	if target.state != "countered":
		return "une menace contrée a changé d'état : %s" % target.state
	if resolved.get(target.id, []) != [true]:
		return "résolution inattendue de la menace contrée : %s" % [resolved.get(target.id, [])]
	var max_roots := same_kind * 2
	if struck_roots > max_roots:
		return "la menace contrée a frappé quand même (%d frappes %s)" % [struck_roots, kind_root]
	# Les autres menaces, non contrées, ont frappé (ou se sont dissipées faute de cible).
	return ""


func test_uncountered_threat_strikes_through_simulation() -> String:
	var g := _setup()
	var st: RefCounted = g.st
	var t: Dictionary = st.round.threats[0]
	var roots := 0
	var idx: int = st.round.index
	while st.round.index == idx and not st.over:
		for ev in _frame(g):
			if String(ev.type).begins_with("threat_"):
				roots += 1
				if not String(ev.summary).begins_with("Menace : "):
					return "racine causale de menace mal nommée : %s" % ev.summary
				if g.sim.get_event(ev.id).is_empty():
					return "la frappe n'est pas dans la chaîne causale de la simulation"
	if not t.state in ["struck", "fizzled"]:
		return "menace non contrée ni frappée en fin de manche : %s" % t.state
	if roots == 0 and t.state == "struck":
		return "frappe sans événement de simulation"
	return ""


func test_cataclysm_increases_intensity() -> String:
	var g := _setup()
	var st: RefCounted = g.st
	var before: int = st.current_intensity()
	# Défausse connue, puis deux Cataclysmes.
	st._discard = [{kind = "drought", severity = 0.5}, {kind = "epidemic", severity = 0.5}] as Array[Dictionary]
	var deck_before: int = st.deck_left()
	st._cataclysm()
	if st.deck_left() != deck_before + 2:
		return "la défausse n'est pas remélangée sur la pioche (%d -> %d)" % [deck_before, st.deck_left()]
	var top: Dictionary = st._deck[st._deck.size() - 1]
	if not top.kind in ["drought", "epidemic"] or float(top.severity) <= 0.5:
		return "la menace de retour n'est pas sur le dessus ni plus forte : %s" % top
	st._cataclysm()
	if st.cataclysms != 2 or st.current_intensity() <= before:
		return "intensité non augmentée (%d -> %d)" % [before, st.current_intensity()]
	# Par le jeu : un Cataclysme sur le dessus est révélé à la manche suivante.
	var g2 := _setup()
	var st2: RefCounted = g2.st
	st2._deck.append({cataclysm = true, kind = "", severity = 1.0})
	st2._hand = st2._draw_hand(g2.sim, g2.parcel)
	st2._committed = false
	var cats := 0
	for t in st2._hand:
		cats += 1 if t.cataclysm else 0
	if cats == 0:
		return "Cataclysme pioché mais absent de la main"
	var expected: int = st2.cataclysms + cats
	_next_round(g2)
	if st2.cataclysms != expected:
		return "Cataclysme révélé sans effet (cataclysms = %d, attendu %d)" % [st2.cataclysms, expected]
	return ""


func test_collapses_lead_to_defeat() -> String:
	var g := _setup()
	var st: RefCounted = g.st
	var sim: RefCounted = g.sim
	var log: RefCounted = sim.causal_log
	# Un geste du joueur n'est pas un effondrement du monde.
	var divine: Dictionary = log.make_root(sim.year, "divine_meteor", CELL, -1, "Dieu : Météorite")
	var ext0: Dictionary = log.make_event(sim.year, "extinction", CELL, -1, "x", divine.id)
	st.update(sim, g.parcel, [ext0])
	if st.tracks.collapses != 0:
		return "une extinction causée par Dieu compte comme effondrement"
	# Une menace qui frappe, puis une extinction qui en découle, puis une autre en cascade.
	var root: Dictionary = log.make_root(sim.year, "threat_epidemic", CELL, -1, "Menace : Épidémie")
	var plague: Dictionary = log.make_event(sim.year, "plague", CELL, -1, "x", root.id)
	var ext1: Dictionary = log.make_event(sim.year, "extinction", CELL, -1, "x", plague.id)
	var ext2: Dictionary = log.make_event(sim.year, "extinction", CELL, -1, "x", plague.id)
	st.update(sim, g.parcel, [ext1, ext2])
	if st.tracks.collapses != 1:
		return "une même crise doit compter une fois (%d)" % st.tracks.collapses
	var ext3: Dictionary = log.make_event(sim.year, "collapse", CELL, -1, "x", ext1.id)
	st.update(sim, g.parcel, [ext3])
	if st.tracks.collapses != 2:
		return "effondrement en cascade non compté (%d)" % st.tracks.collapses
	# Jusqu'au seuil : défaite.
	var ended := []
	st.game_over.connect(func(v, r): ended.append([v, r]))
	var limit: int = st.tracks.collapse_limit
	var parent: Dictionary = ext3
	var guard := 0
	while not st.over and guard < 200:
		guard += 1
		st._chain_this_round = 0  # plafond par manche levé pour le test
		var ev: Dictionary = log.make_event(sim.year, "extinction", CELL, -1, "x", parent.id)
		st.update(sim, g.parcel, [ev])
		parent = ev
	if not st.over or st.victory:
		return "pas de défaite à %d effondrements" % limit
	if st.tracks.collapses != limit or ended.size() != 1 or ended[0][0]:
		return "fin de partie incohérente : %d/%d, %s" % [st.tracks.collapses, limit, ended]
	if st.spend_action("bless") or st.can_act():
		return "on peut encore agir après la défaite"
	return ""


func test_four_works_victory() -> String:
	var g := _setup()
	var st: RefCounted = g.st
	if st.seal_work("legacy") and not Strategy.works_status(g.sim, g.parcel).legacy:
		return "Grand Œuvre scellé sans que la simulation l'ait atteint"
	var ended := []
	st.game_over.connect(func(v, r): ended.append([v, r]))
	for id in Rules.WORK_ORDER:
		st.works_ready[id] = true
		st.actions_left = Rules.SEAL_COST
		if not st.seal_work(id):
			return "impossible de sceller %s" % id
		if st.actions_left != 0:
			return "sceller %s devrait coûter %d actions" % [id, Rules.SEAL_COST]
		if st.seal_work(id):
			return "%s scellé deux fois" % id
	if not st.over or not st.victory or ended.size() != 1 or not ended[0][0]:
		return "pas de victoire après les quatre Grands Œuvres : %s" % [ended]
	return ""


func test_empty_deck_defeat() -> String:
	var g := _setup()
	var st: RefCounted = g.st
	st._deck.clear()
	st.next_threats.clear()
	st._hand.clear()
	var ended := []
	st.game_over.connect(func(v, r): ended.append([v, r]))
	_next_round(g)
	if not st.over or st.victory:
		return "pioche vide sans défaite"
	if ended.size() != 1 or not String(ended[0][1]).contains("sablier"):
		return "raison de la défaite inattendue : %s" % [ended]
	return ""


func test_threats_reflect_world() -> String:
	var g := _setup()
	var st: RefCounted = g.st
	# Chaque carte a une cible cohérente et des contres explicites.
	for t in st.round.threats + st._hand:
		var def: Dictionary = Rules.THREATS[t.kind]
		if not t.act in def.acts and not t.cataclysm:
			return "%s piochée hors de son acte (%s)" % [t.kind, t.act]
		if String(def.target) != "none" and t.target.species_id < 0:
			return "%s sans espèce cible" % t.kind
		if t.counters.is_empty():
			return "%s sans contre" % t.kind
		for c in t.counters:
			if not Rules.POWER_LABELS.has(c):
				return "contre inconnu %s" % c
	# Sans civilisation, pas de menaces de l'acte III.
	var w: Dictionary = st._kind_weights("act1", g.sim, g.parcel)
	for k in ["famine", "war", "pollution", "hostile_ai"]:
		if w.has(k):
			return "%s possible sans civilisation" % k
	return ""


## Joueur automatique simple : contre ce qu'il peut, scelle dès que possible.
func _auto_play(st: RefCounted) -> void:
	for id in Rules.WORK_ORDER:
		if st.works_ready[id] and not st.tracks.works[id] and st.actions_left >= Rules.SEAL_COST:
			st.seal_work(id)
	for t in st.round.threats:
		if t.state == "pending" and st.can_act():
			st.spend_action(t.counters[0])


func _play_full(aspect: String, difficulty: String, active: bool) -> Dictionary:
	var g := _setup(SEED, aspect, difficulty)
	var st: RefCounted = g.st
	var frames := 0
	while not st.over and frames < 6000:
		frames += 1
		_frame(g)
		if active:
			_auto_play(st)
	print("  %d images, %d manches, ère %s, effondrements %d/%d, pioche %d, cataclysmes %d, œuvres %s, fin : %s" % [
		frames, st.round.index, g.sim.current_era(), st.tracks.collapses, st.tracks.collapse_limit,
		st.deck_left(), st.cataclysms, st.tracks.works, st.end_reason if st.over else "aucune"])
	return {st = st, frames = frames}


func test_accelerated_full_game() -> String:
	# Joueur passif : le monde finit par l'emporter (ou la partie court jusqu'au bout sans erreur).
	_play_full("destroyer", "apocalypse", false)
	var res := _play_full("guardian", "eveil", true)
	var st: RefCounted = res.st
	var frames: int = res.frames
	if st.round.index < 3:
		return "trop peu de manches (%d) en %d images" % [st.round.index, frames]
	if not st.over:
		return "partie non terminée en %d images" % frames
	return ""
