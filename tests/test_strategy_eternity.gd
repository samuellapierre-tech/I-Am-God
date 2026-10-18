extends RefCounted
## Mode Éternité (docs/STRATEGIE.md §10) : une défaite ferme un chapitre et la partie continue, les
## menaces passent sans pénalité de piste, les Grands Œuvres se collectionnent sans limite, les défis
## de Samaël sont légaux, sans anachronisme et déterministes.
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const Eras := preload("res://src/sim/eras.gd")
const Strategy := preload("res://src/strategy/strategy.gd")
const Rules := preload("res://src/strategy/strategy_rules.gd")
const Challenges := preload("res://src/strategy/challenges.gd")
const Base := preload("res://tests/test_strategy.gd")

const CELL := Vector2i(70, 40)


func _setup(seed_value := 4242, difficulty := "divin") -> Dictionary:
	return Base.new()._setup(seed_value, "guardian", difficulty, "eternity")


func _frame(g: Dictionary) -> Array:
	return Base.new()._frame(g)


func test_defeat_opens_a_new_chapter() -> String:
	var g := _setup()
	var st: RefCounted = g.st
	var sim: RefCounted = g.sim
	if st.mode != "eternity" or not String(st.round.name).begins_with("Chapitre"):
		return "mode ou nom de chapitre inattendu : %s / %s" % [st.mode, st.round.name]
	var closed := []
	var ended := []
	st.chapter_closed.connect(func(c): closed.append(c))
	st.game_over.connect(func(v, r): ended.append(r))
	# 1) Effondrements en chaîne naturels jusqu'au seuil.
	var log: RefCounted = sim.causal_log
	var parent: Dictionary = log.make_event(sim.year, "extinction", CELL, -1, "x", -1)
	var idx: int = st.round.index
	var guard := 0
	while closed.is_empty() and guard < 100:
		guard += 1
		st._chain_this_round = 0
		var ev: Dictionary = log.make_event(sim.year, "extinction", CELL, -1, "x", parent.id)
		st.update(sim, g.parcel, [ev])
		parent = ev
	if closed.is_empty() or closed[0].reason_code != "collapses":
		return "le seuil d'effondrements n'a pas fermé de chapitre : %s" % [closed]
	if st.over or not ended.is_empty():
		return "la partie s'est terminée en Éternité"
	if st.round.index != idx + 1 or st.tracks.collapses != 0:
		return "pas de nouveau chapitre ou pistes non remises à zéro (chapitre %d, effondrements %d)" % [
			st.round.index, st.tracks.collapses]
	# 2) Parcelle morte.
	st._vitality_peak = 1.0
	st._dead_for = 1.0
	st.tracks.vitality = 0.0
	st._check_end()
	st.update(sim, g.parcel, [])
	if closed.size() < 2 or closed[1].reason_code != "parcel_dead":
		return "la mort de la parcelle n'a pas fermé de chapitre : %s" % [closed]
	# 3) Sablier vide : la pioche se reforme.
	st._deck.clear()
	st._hand.clear()
	st.next_threats.clear()
	Base.new()._next_round(g)
	if st.over or closed.back().reason_code != "deck_empty" or st.deck_left() == 0:
		return "sablier vide : %s, pioche %d" % [closed.back(), st.deck_left()]
	# 4) La partie continue : des chapitres s'enchaînent sans fin.
	for i in 300:
		_frame(g)
	if st.over or not ended.is_empty() or st.can_act() == false and st.actions_left > 0:
		return "la partie ne continue pas"
	return ""


func test_threats_pass_without_penalty() -> String:
	var g := _setup()
	var st: RefCounted = g.st
	var log: RefCounted = g.sim.causal_log
	var root: Dictionary = log.make_root(g.sim.year, "threat_epidemic", CELL, -1, "Menace : Épidémie")
	var plague: Dictionary = log.make_event(g.sim.year, "plague", CELL, -1, "x", root.id)
	var ext: Dictionary = log.make_event(g.sim.year, "extinction", CELL, -1, "x", plague.id)
	st.update(g.sim, g.parcel, [ext])
	if st.tracks.collapses != 0:
		return "une menace laissée passer coûte un effondrement en Éternité"
	# Même scène en Épreuve : la piste bouge (règle inchangée).
	var t := Base.new()._setup(4242, "guardian", "divin", "trial")
	var log2: RefCounted = t.sim.causal_log
	var root2: Dictionary = log2.make_root(t.sim.year, "threat_epidemic", CELL, -1, "Menace : Épidémie")
	var ext2: Dictionary = log2.make_event(t.sim.year, "extinction", CELL, -1, "x", root2.id)
	t.st.update(t.sim, t.parcel, [ext2])
	if t.st.tracks.collapses != 1:
		return "l'Épreuve a changé : effondrement non compté"
	return ""


func test_works_collected_without_limit() -> String:
	var g := _setup()
	var st: RefCounted = g.st
	var closed := []
	st.chapter_closed.connect(func(c): closed.append(c))
	for cycle in 2:
		for id in Rules.WORK_ORDER:
			st.works_ready[id] = true
			st.actions_left = Rules.SEAL_COST
			if not st.seal_work(id):
				return "cycle %d : impossible de sceller %s" % [cycle, id]
		st.update(g.sim, g.parcel, [])
		if st.over:
			return "victoire de fin de partie en Éternité"
		if closed.size() != cycle + 1 or closed[cycle].reason_code != "works_complete":
			return "cycle %d : les quatre Grands Œuvres n'ont pas fermé le chapitre : %s" % [cycle, closed]
		for id in Rules.WORK_ORDER:
			if st.tracks.works[id]:
				return "cycle %d : %s reste scellé dans le nouveau chapitre" % [cycle, id]
	if st.collection.size() != 8 or st.tracks.collected != 8:
		return "collection attendue 8, obtenue %d" % st.collection.size()
	return ""


## Joue une partie Éternité accélérée et relève les défis proposés (vérifiés à l'émission).
func _challenge_run(seed_value: int) -> Dictionary:
	var g := _setup(seed_value, "eveil")
	var st: RefCounted = g.st
	var player := Base.new()
	var trace := []
	var errors := []
	var settled := [0]
	var on_move := func(m):
		if m.kind == "challenge":
			var c: Dictionary = m.challenge
			var ctx: Dictionary = st._challenge_context(g.sim, g.parcel)
			if not c.kind in Challenges.legal_kinds(ctx):
				errors.append("défi illégal %s à l'ère %s" % [c.kind, g.sim.current_era()])
			if c.kind == "civilization" and g.sim.era_index() < Eras.FIRST_SAPIENT_ERA:
				errors.append("défi de civilisation avant toute civilisation")
			if c.species_id >= 0 and not Strategy._alive(g.sim, c.species_id):
				errors.append("défi sur une espèce absente : %s" % c.text)
			if c.species_name != "" and not c.text.contains(c.species_name):
				errors.append("texte incohérent : %s" % c.text)
			if not c.reward in ["action", "work"] or c.deadline_chapter < c.issued_chapter:
				errors.append("défi mal formé : %s" % c)
			trace.append("%d:%s:%s" % [c.issued_chapter, c.kind, c.text])
		elif m.kind in ["challenge_won", "challenge_lost"]:
			settled[0] += 1
			trace.append("%s:%d" % [m.kind, m.challenge.id])
	st.samael_move.connect(on_move)
	for i in 1500:
		_frame(g)
		player._auto_play(st)
	st.samael_move.disconnect(on_move)
	return {trace = trace, errors = errors, settled = settled[0], st = st, era = g.sim.era_index()}


func test_challenges_are_legal_and_deterministic() -> String:
	var a := _challenge_run(91)
	var b := _challenge_run(91)
	if not a.errors.is_empty():
		return "; ".join(a.errors.slice(0, 4))
	if a.trace != b.trace:
		return "défis non déterministes :\n%s\n---\n%s" % ["\n".join(a.trace), "\n".join(b.trace)]
	var issued := 0
	for line in a.trace:
		if not String(line).begins_with("challenge_"):
			issued += 1
	print("  %d défis proposés, %d tranchés, ère atteinte %d, collection %d" % [issued, a.settled, a.era, a.st.collection.size()])
	if issued < 3 or a.settled < 2:
		return "trop peu de défis (%d proposés, %d tranchés)" % [issued, a.settled]
	if a.st.over:
		return "la partie Éternité s'est terminée"
	return ""


func test_challenge_reward_and_no_penalty() -> String:
	var g := _setup()
	var st: RefCounted = g.st
	var base: int = st.actions_per_round
	# Défi « paix divine » relevé : +1 action au chapitre suivant.
	st.challenge = {id = 99, kind = "quiet", title = "Paix divine", text = "", reward = "action",
		reward_text = "", issued_chapter = st.round.index, deadline_chapter = st.round.index, state = "open",
		species_id = -1, species_name = "", threshold = 0.0, goal = 0, progress = 0, era_at_issue = 0}
	st._challenge_powers = 0
	Base.new()._next_round(g)
	if st.challenges_done.is_empty() or st.challenges_done.back().state != "won":
		return "défi de paix non gagné : %s" % [st.challenges_done]
	if st.actions_left != base + 1:
		return "récompense non accordée : %d actions (attendu %d)" % [st.actions_left, base + 1]
	# Défi perdu : aucune pénalité.
	var tracks_before: Dictionary = st.tracks.duplicate(true)
	st.challenge = {id = 100, kind = "quiet", title = "Paix divine", text = "", reward = "work",
		reward_text = "", issued_chapter = st.round.index, deadline_chapter = st.round.index, state = "open",
		species_id = -1, species_name = "", threshold = 0.0, goal = 0, progress = 0, era_at_issue = 0}
	st._challenge_powers = 0
	st.spend_action("bless")
	st.update(g.sim, g.parcel, [])
	if st.challenges_done.back().state != "lost":
		return "défi de paix non perdu après un pouvoir"
	if st.tracks.collapses != tracks_before.collapses or st.collection.size() != 0:
		return "un défi perdu a eu un effet sur les pistes"
	return ""
