extends RefCounted
## Couche stratégique (docs/STRATEGIE.md, contrat docs/ARCHITECTURE.md « Stratégie ») :
## Dieu contre l'entropie du monde, à la Pandemic.
##
## - Manches : une ère (ou étape du prologue) ou ROUND_STEPS pas idéaux de la simulation.
## - Budget d'actions par manche : chaque pouvoir lancé passe par spend_action().
## - Pioche de menaces : chaque carte est tirée d'après l'état réel du monde et de la parcelle ;
##   les Cataclysmes augmentent l'intensité et remélangent la défausse sur le dessus.
## - Une menace non contrée frappe à son strikes_year via WorldSim.apply_divine_action : la chaîne
##   causale reste la seule source de vérité (aucun effet inventé ici).
## - Pistes : effondrements en chaîne (lus dans la chaîne causale), vitalité de la parcelle,
##   4 Grands Œuvres à sceller, sablier (pioche).
##
## - Samaël (samael.gd), l'adversaire, reçoit chaque manche une main de cartes légales et choisit
##   celles qu'il révèle et quand elles frappent (§8). Rien n'apparaît avant son époque (§9).
##
## - Deux modes (§10) : « eternity » (par défaut : pas de fin de partie, une défaite ferme un
##   chapitre et les pistes repartent, Samaël est un rival doux qui propose des défis facultatifs, les
##   Grands Œuvres se collectionnent sans limite) et « trial » (victoire ou défaite).
##
## Pur et déterministe à graine égale : aucun accès à GameState ni à l'arbre de scènes.
## Utilisation : start(world, parcel) puis update(world, parcel, events) à chaque image (renvoie les
## événements produits par les frappes, à relayer comme ceux de WorldSim.step).

signal round_started(round: Dictionary)
signal threat_revealed(threat: Dictionary)
signal threat_resolved(threat: Dictionary, countered: bool)
signal tracks_changed(tracks: Dictionary)
signal game_over(victory: bool, reason: String)
## Un pouvoir a été refusé : budget épuisé ou partie terminée.
signal action_refused(kind: String)
## Le nombre d'actions restantes a changé.
signal actions_changed(actions_left: int)
## Samaël agit : {kind: "reveal"|"strike"|"taunt_hook", threat: Dictionary, reason_code: String}.
signal samael_move(move: Dictionary)
## Samaël a appris une habitude du joueur : {power, weight, share}.
signal samael_learned(habit: Dictionary)
## Éternité : un chapitre se ferme sur une « défaite » (ou les quatre Grands Œuvres) et le monde
## continue : {index, reason_code, reason, collected}. reason_code : "collapses", "parcel_dead",
## "deck_empty", "works_complete".
signal chapter_closed(chapter: Dictionary)

const Rules := preload("res://src/strategy/strategy_rules.gd")
const Samael := preload("res://src/strategy/samael.gd")
const Challenges := preload("res://src/strategy/challenges.gd")

## Samaël engage ses cartes de la manche suivante à cette fraction de la manche (le Prophète les
## voit alors) ; l'Oracle d'Apocalypse travaille entre le début de manche et ce moment.
const COMMIT_AT := 0.5

## Types d'événements de WorldSim qui forment une crise (maillon d'un effondrement en chaîne).
const CHAIN_TYPES := ["extinction", "collapse"]
## Profondeur maximale de remontée de la chaîne causale.
const CHAIN_DEPTH := 8
## Effondrements en chaîne comptés au plus par manche (une hécatombe ne fait pas perdre d'un coup).
const MAX_CHAIN_PER_ROUND := 3
## Vitalité en dessous de laquelle la parcelle est morte.
const VITALITY_DEAD := 0.02
## La parcelle doit avoir été vivante (au moins ce niveau) pour pouvoir mourir.
const VITALITY_ALIVE := 0.15
## La parcelle doit rester morte pendant cette fraction de manche (un cratère peut se recoloniser).
const DEAD_ROUNDS := 0.5
## Couverture végétale minimale de la Conquête des terres.
const LAND_VEGETATION := 0.08
## Espèces de la parcelle pour une diversité pleine.
const FULL_DIVERSITY := 4.0

var aspect := Rules.DEFAULT_ASPECT
var difficulty := Rules.DEFAULT_DIFFICULTY
## "eternity" (par défaut) | "trial".
var mode := Rules.DEFAULT_MODE
## Éternité : Grands Œuvres collectionnés, sans limite : [{work, label, chapter}] (work "samael" :
## Grand Œuvre bonus d'un défi relevé).
var collection: Array[Dictionary] = []
## Éternité : défi de Samaël en cours ({} : aucun) et derniers défis tranchés.
var challenge: Dictionary = {}
var challenges_done: Array[Dictionary] = []
## {index, name, stage, act, act_name, starts_year, ends_year, steps, threats: Array[Dictionary], recap}
## ends_year et strikes_year sont réestimés à chaque mise à jour au rythme courant de la simulation.
@warning_ignore("shadowed_global_identifier")
var round := {}
var actions_left := 0
var actions_per_round := 4
## {collapses, collapse_limit, vitality, works: {life, land, mind, legacy: bool}, deck_left}
var tracks := {}
## Grands Œuvres dont la condition est remplie dans la simulation (scellables).
var works_ready := {life = false, land = false, mind = false, legacy = false}
## Menaces de la manche suivante, une fois choisies par Samaël (visibles seulement pour le Prophète).
var next_threats: Array[Dictionary] = []
## L'adversaire (son intelligence dépend de la difficulté).
var samael: Samael
## Cataclysmes piochés (intensité).
var cataclysms := 0
var over := false
var victory := false
var end_reason := ""
var started := false

var _rng := RandomNumberGenerator.new()
## Pioche : le dessus est la fin du tableau. Carte : {cataclysm: bool, kind: String, severity: float}.
var _deck: Array[Dictionary] = []
var _discard: Array[Dictionary] = []
var _next_id := 1
var _round_era := -1
var _chained := {}
var _chain_this_round := 0
var _vitality_peak := 0.0
var _vitality_bonus := 0.0
var _last_year := 0.0
## Avancée de la manche (0..1, en pas idéaux de la simulation).
var _progress := 0.0
## Durée (en manches) pendant laquelle la parcelle est restée morte.
var _dead_for := 0.0
var _creator_free := true
var _creator_bonus := 0
var _seen_fauna := {}
var _round_stats := {countered = 0, struck = 0, collapses = 0}
## Main de Samaël pour la manche suivante (privée) ; engagée dans next_threats à COMMIT_AT.
var _hand: Array[Dictionary] = []
var _committed := false
var _close_request := {}
var _bonus_next := 0
var _challenge_rng := RandomNumberGenerator.new()
var _next_challenge_id := 1
var _challenge_counters := 0
var _challenge_powers := 0
var _challenge_new_species := false
var _deck_size := 0
var _deck_cats := 0


func _init(p_seed: int, p_aspect := Rules.DEFAULT_ASPECT, p_difficulty := Rules.DEFAULT_DIFFICULTY,
		p_mode := Rules.DEFAULT_MODE) -> void:
	aspect = p_aspect if Rules.ASPECTS.has(p_aspect) else Rules.DEFAULT_ASPECT
	difficulty = p_difficulty if Rules.DIFFICULTIES.has(p_difficulty) else Rules.DEFAULT_DIFFICULTY
	mode = p_mode if p_mode in Rules.MODE_ORDER else Rules.DEFAULT_MODE
	_rng.seed = hash("%d:%s:%s" % [p_seed, aspect, difficulty]) if mode == "trial" \
		else hash("%d:%s:%s:%s" % [p_seed, aspect, difficulty, mode])
	_challenge_rng.seed = hash("challenges:%d" % p_seed)
	var d := Rules.difficulty(difficulty)
	actions_per_round = int(d.actions)
	_deck_size = int(d.deck)
	_deck_cats = int(d.cataclysms)
	_build_deck(_deck_size, _deck_cats)
	# En Éternité, Samaël est un rival doux : il tire ses menaces au hasard et n'apprend rien.
	samael = Samael.new(p_seed, difficulty if mode == "trial" else "eveil")
	samael.learned.connect(samael_learned.emit)
	tracks = {
		collapses = 0, collapse_limit = int(d.collapse_limit), vitality = 1.0,
		works = {life = false, land = false, mind = false, legacy = false}, deck_left = _deck.size(),
		collected = 0,
	}


# =============================================================================================
# Contrat public
# =============================================================================================

## Ouvre la première manche.
func start(world: RefCounted, parcel: RefCounted) -> void:
	if started:
		return
	started = true
	_round_era = world.era_index()
	_last_year = world.year
	_note_fauna(parcel, true)
	_refresh_tracks(world, parcel)
	_hand = _draw_hand(world, parcel)
	_commit(world, parcel)
	_start_round(world, parcel, "")


## À appeler après chaque pas de simulation. `events` : événements de WorldSim (et de la parcelle).
## Renvoie les événements produits par les menaces qui frappent.
func update(world: RefCounted, parcel: RefCounted, events: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not started:
		start(world, parcel)
	if over:
		return out
	_note_fauna(parcel, false)
	_detect_chains(world, events)
	# Avancée de la manche, en pas idéaux : le rythme de la simulation change (éveil d'un peuple),
	# la durée ressentie d'une manche non.
	var ideal: float = maxf(world.ideal_step_years(), 1e-6)
	var before := _progress
	_progress += maxf(0.0, world.year - _last_year) / ideal / float(round.steps)
	_last_year = world.year
	# Frappes arrivées à échéance.
	for t in round.threats:
		if t.state == "pending" and _progress >= float(t.strike_at):
			out.append_array(_strike(t, world, parcel))
	_detect_chains(world, out)
	_update_years(world)
	# Samaël prépare la manche suivante : Oracle (Apocalypse), puis choix engagé.
	if not _committed:
		if _progress >= COMMIT_AT:
			_commit(world, parcel)
		else:
			samael.think()
	# Le bonus du Destructeur se dissipe en une manche ; la parcelle doit rester morte une demi-manche.
	_vitality_bonus = maxf(0.0, _vitality_bonus - Rules.DESTROYER_BONUS_MAX * (_progress - before))
	_dead_for = _dead_for + (_progress - before) if float(tracks.vitality) <= VITALITY_DEAD else 0.0
	# Fin de manche : durée atteinte, ou changement d'ère après une durée minimale.
	var era: int = world.era_index()
	if _progress >= 1.0 or (era != _round_era and _progress >= Rules.MIN_ROUND_FRACTION):
		out.append_array(_end_round(world, parcel))
	_refresh_tracks(world, parcel)
	_check_end()
	if mode == "eternity":
		_check_challenge(world)
		if not _close_request.is_empty():
			_close_chapter(world, parcel)
	return out


## Années estimées (au rythme actuel) de la fin de manche et des frappes en attente.
func _update_years(world: RefCounted) -> void:
	var span: float = float(round.steps) * world.ideal_step_years()
	round.ends_year = world.year + maxf(0.0, 1.0 - _progress) * span
	for t in round.threats:
		if t.state == "pending":
			t.strikes_year = world.year + maxf(0.0, float(t.strike_at) - _progress) * span


func can_act() -> bool:
	return started and not over and actions_left > 0


## Coût d'une action pour cet aspect (0 : gratuite).
func action_cost(kind: String) -> int:
	if kind == "oracle" and aspect == "prophet":
		return 0
	if kind == "spawn_species" and aspect == "creator" and _creator_free:
		return 0
	if kind.begins_with("seal_"):
		return Rules.SEAL_COST
	return 1


## Dépense une action. Refusée (false) si le budget est épuisé ou la partie finie.
## Un pouvoir qui figure dans les contres d'une menace en attente la contre (la plus proche).
func spend_action(kind: String) -> bool:
	var cost := action_cost(kind)
	if over or not started or cost > actions_left:
		action_refused.emit(kind)
		return false
	actions_left -= cost
	if not kind.begins_with("seal_"):
		_challenge_powers += 1
	if kind == "spawn_species" and aspect == "creator":
		_creator_free = false
	if aspect == "destroyer" and kind in Rules.CATASTROPHES:
		_vitality_bonus = minf(Rules.DESTROYER_BONUS_MAX, _vitality_bonus + Rules.DESTROYER_BONUS)
	var n := 2 if aspect == "guardian" and kind in ["save", "bless"] else 1
	for t in _pending_by_time():
		if n <= 0:
			break
		if kind in t.counters:
			_resolve(t, true)
			samael.note_counter(kind)
			_challenge_counters += 1
			n -= 1
	if cost != 0:
		actions_changed.emit(actions_left)
	return true


## Types de pouvoirs qui contrent cette menace (filtrés par époque à la création de la carte).
func counters_for(threat: Dictionary) -> Array[String]:
	if threat.has("counters"):
		var out: Array[String] = []
		for c in threat.counters:
			out.append(String(c))
		return out
	return Rules.counters(String(threat.get("kind", "")))


## Scelle un Grand Œuvre dont la condition est remplie (coûte Rules.SEAL_COST actions).
func seal_work(id: String) -> bool:
	if not works_ready.get(id, false) or tracks.works.get(id, true):
		return false
	if not spend_action("seal_" + id):
		return false
	tracks.works[id] = true
	collection.append({work = id, label = String(Rules.WORKS[id].label), chapter = int(round.get("index", 0))})
	tracks.collected = collection.size()
	tracks_changed.emit(tracks)
	_check_end()
	return true


## Menaces de la manche suivante visibles par le joueur (Prophète seulement).
func visible_next_threats() -> Array[Dictionary]:
	return next_threats if aspect == "prophet" else ([] as Array[Dictionary])


func deck_left() -> int:
	return _deck.size()


func current_intensity() -> int:
	return Rules.intensity(cataclysms)


# =============================================================================================
# Pioche
# =============================================================================================

## Pioche de `size` cartes dont `cats` Cataclysmes : la pioche est coupée en `cats` tas, un
## Cataclysme mélangé dans chacun, puis les tas sont empilés (comme Pandemic).
func _build_deck(size: int, cats: int) -> void:
	_deck.clear()
	var normal := maxi(0, size - cats)
	var piles: Array = []
	for p in cats:
		piles.append([])
	for i in normal:
		if cats > 0:
			piles[i % cats].append({cataclysm = false, kind = "", severity = 0.5})
		else:
			_deck.append({cataclysm = false, kind = "", severity = 0.5})
	# Dessus de la pioche = fin du tableau : le premier tas pioché est le dernier empilé.
	for pile in piles:
		pile.insert(_rng.randi_range(0, pile.size()), {cataclysm = true, kind = "", severity = 1.0})
		for c in pile:
			_deck.append(c)


## Pioche la main de Samaël : intensité + HAND_EXTRA cartes. Les Cataclysmes s'ajoutent (ne comptent
## pas) et seront révélés d'office.
func _draw_hand(world: RefCounted, parcel: RefCounted) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := Rules.intensity(cataclysms) + Samael.HAND_EXTRA
	var drawn := 0
	while drawn < n and not _deck.is_empty():
		var card: Dictionary = _deck.pop_back()
		var t := _make_threat(card, world, parcel)
		if t.is_empty():
			continue
		out.append(t)
		if not card.cataclysm:
			drawn += 1
	return out


func _make_threat(card: Dictionary, world: RefCounted, parcel: RefCounted) -> Dictionary:
	var act := Rules.act_for(world.era_index(), not world.get_sapient_species().is_empty())
	var era: int = world.era_index()
	var lead := _leading_tech(world)
	var kind := String(card.kind)
	var severity := float(card.severity)
	if card.cataclysm:
		var majors := []
		for k in Rules.MAJOR_BY_ACT.get(act, Rules.MAJOR_BY_ACT.act1):
			if Rules.epoch_ok(k, era, lead):
				majors.append(k)
		kind = String(majors[_rng.randi_range(0, majors.size() - 1)]) if not majors.is_empty() else "impact"
	elif kind == "" or not act in Rules.THREATS[kind].acts or not Rules.epoch_ok(kind, era, lead):
		kind = _pick_kind(act, world, parcel)
	if kind == "":
		kind = "heatwave"  # toujours possible : vise la parcelle, pas une espèce
	var def: Dictionary = Rules.THREATS[kind]
	var sid := _target_for(String(def.target), world, parcel)
	var t := {
		id = _next_id, kind = kind, title = def.title, text = def.text,
		target = {region = _cell(parcel), species_id = sid}, target_name = _species_name(world, sid),
		strikes_year = 0.0, strike_at = 1.0, revealed = false, severity = severity, countered = false, counters = Rules.counters(kind, era),
		state = "pending", action = def.strike, cataclysm = bool(card.cataclysm),
		returning = card.kind != "" and not card.cataclysm, act = act,
	}
	_next_id += 1
	return t


## Choix pondéré d'un type de menace d'après l'état réel du monde et de la parcelle (§3).
func _pick_kind(act: String, world: RefCounted, parcel: RefCounted) -> String:
	var w := _kind_weights(act, world, parcel)
	var total := 0.0
	var kinds := w.keys()
	kinds.sort()  # ordre stable : déterminisme
	for k in kinds:
		total += float(w[k])
	if total <= 0.0:
		return ""
	var r := _rng.randf() * total
	for k in kinds:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return kinds[kinds.size() - 1]


func _kind_weights(act: String, world: RefCounted, parcel: RefCounted) -> Dictionary:
	var w := {}
	for k in Rules.THREATS:
		var def: Dictionary = Rules.THREATS[k]
		if act in def.acts and not def.get("major", false) and Rules.epoch_ok(k, world.era_index(), _leading_tech(world)):
			w[k] = float(def.weight)
	var fauna := _parcel_species(world, parcel)
	var ocean: bool = parcel != null and parcel.land_use == "ocean"
	if parcel != null:
		for a in parcel.alerts:
			match String(a.kind):
				"species_collapse":
					_bump(w, "keystone", 4.0)
				"heat_drift":
					_bump(w, "heatwave" if _warming(parcel) else "glaciation", 3.0)
				"civilization_threat":
					_bump(w, "famine", 2.0)
					_bump(w, "war", 2.0)
		if parcel.temperature_c > 24.0 or parcel.water < 0.25:
			_bump(w, "drought", 2.0)
	if not fauna.is_empty() and float(fauna[0].density) >= 0.5:
		_bump(w, "overgrazing", 2.5)
	if fauna.size() >= 4:
		_bump(w, "invasive", 1.0)
	var lead := _leading_tech(world)
	if lead >= 2.0:
		_bump(w, "epidemic", 1.0)
	if lead >= 4.0:
		_bump(w, "pollution", 3.0)
	if ocean:
		w.erase("drought")
		_bump(w, "anoxia", 1.0)
	# Pas de cible possible : la carte ne peut pas être tirée.
	for k in w.keys():
		var target := String(Rules.THREATS[k].target)
		if target != "none" and _target_for(target, world, parcel) < 0:
			w.erase(k)
	return w


static func _bump(w: Dictionary, kind: String, amount: float) -> void:
	if w.has(kind):
		w[kind] = float(w[kind]) + amount


## Cataclysme : intensité +1, la défausse remélangée revient sur le dessus, plus forte.
func _cataclysm() -> void:
	cataclysms += 1
	var back := _discard.duplicate()
	_discard.clear()
	for i in range(back.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Dictionary = back[i]
		back[i] = back[j]
		back[j] = tmp
	for c in back:
		_deck.append({cataclysm = false, kind = c.kind,
			severity = minf(Rules.MAX_SEVERITY, float(c.severity) + Rules.RETURN_SEVERITY)})


# =============================================================================================
# Manches
# =============================================================================================

func _start_round(world: RefCounted, parcel: RefCounted, recap: String) -> void:
	if not _committed:
		_commit(world, parcel)
	var cards := next_threats
	next_threats = []
	if cards.is_empty() and _deck.is_empty() and mode == "eternity":
		# Le sablier se retourne : un chapitre se ferme, la pioche se reforme.
		_reset_cycle()
		chapter_closed.emit({index = int(round.get("index", 0)), reason_code = "deck_empty",
			reason = Rules.CHAPTER_REASONS.deck_empty, collected = collection.size()})
		_hand = _draw_hand(world, parcel)
		_commit(world, parcel)
		cards = next_threats
		next_threats = []
	if cards.is_empty() and _deck.is_empty():
		_finish(false, "Le sablier cosmique est vide : la pioche de menaces s'est épuisée avant les quatre Grands Œuvres.")
		return
	var idx := int(round.get("index", 0)) + 1
	var act := Rules.act_for(world.era_index(), not world.get_sapient_species().is_empty())
	var steps: float = Rules.round_steps(world.era_index(), act)
	round = {
		index = idx, name = ("Chapitre %d" if mode == "eternity" else "Manche %d") % idx, stage = world.current_era(), act = act,
		act_name = Rules.ACT_NAMES.get(act, act), starts_year = world.year, ends_year = world.year,
		steps = steps, threats = [] as Array[Dictionary], recap = recap,
	}
	_round_era = world.era_index()
	_progress = 0.0
	actions_left = actions_per_round + _bonus_next
	_bonus_next = 0
	_creator_free = true
	_creator_bonus = 0
	_chain_this_round = 0
	_round_stats = {countered = 0, struck = 0, collapses = 0}
	# Cartes de la manche : les Cataclysmes prennent effet à leur révélation. Une carte devenue
	# anachronique (la civilisation a reculé) est remplacée par une carte légale de même gravité.
	var era: int = world.era_index()
	var lead := _leading_tech(world)
	for t in cards:
		if t.cataclysm:
			_cataclysm()
		if not Rules.epoch_ok(t.kind, era, lead):
			var fresh := _make_threat({cataclysm = false, kind = "", severity = t.severity}, world, parcel)
			for key in ["kind", "title", "text", "target", "target_name", "counters", "action", "act"]:
				t[key] = fresh[key]
			t.samael = {reason_code = "fallback", score = 0.0}
		if t.target.species_id >= 0 and not _alive(world, t.target.species_id):
			_retarget(t, world, parcel)
		t.target.region = _cell(parcel)
		t.revealed = true
		round.threats.append(t)
	_update_years(world)
	# Main de la manche suivante : Samaël la travaille (Oracle) jusqu'à COMMIT_AT.
	_hand = _draw_hand(world, parcel)
	_committed = false
	var normal := _hand.filter(func(t): return not t.cataclysm)
	samael.plan(normal, world, _cell(parcel), Samael.ORACLE_ROUNDS * float(round.steps) * world.ideal_step_years())
	_refresh_tracks(world, parcel)
	round_started.emit(round)
	samael_move.emit({kind = "taunt_hook", threat = {}, reason_code = _taunt_code()})
	if mode == "eternity" and challenge.is_empty():
		_propose_challenge(world, parcel)
	for t in round.threats:
		threat_revealed.emit(t)
		samael_move.emit({kind = "reveal", threat = t, reason_code = String(t.get("samael", {}).get("reason_code", "random"))})
	actions_changed.emit(actions_left)


## Samaël choisit dans sa main les cartes de la manche suivante ; les autres retournent sous la pioche.
func _commit(world: RefCounted, parcel: RefCounted) -> void:
	_committed = true
	var forced: Array[Dictionary] = []
	var normal: Array = []
	for t in _hand:
		if t.cataclysm:
			forced.append(t)
		else:
			normal.append(t)
	_hand = []
	var chosen: Array = samael.choose(normal, Rules.intensity(cataclysms), _samael_context(world, parcel))
	for t in normal:
		if not t in chosen:
			_deck.insert(0, {cataclysm = false, kind = "", severity = t.severity})
	for t in forced:
		t.samael = {reason_code = "cataclysm", score = 0.0}
		t.strike_at = Rules.STRIKE_FROM + (Rules.STRIKE_TO - Rules.STRIKE_FROM) * _rng.randf()
	next_threats = forced
	for t in chosen:
		next_threats.append(t)
	next_threats.sort_custom(func(a, b): return float(a.strike_at) < float(b.strike_at))


## Ce que Samaël voit (rien de plus que le joueur) : parcelle, peuples, alertes, pistes, budget.
func _samael_context(world: RefCounted, parcel: RefCounted) -> Dictionary:
	var here := _parcel_species(world, parcel)
	var smartest := -1
	var best := -1.0
	for s in here:
		var sp: Dictionary = world.species[s.species_id]
		if not sp.sapient and float(sp.traits.intelligence) > best:
			best = float(sp.traits.intelligence)
			smartest = int(s.species_id)
	var collapsing := []
	if parcel != null:
		for a in parcel.alerts:
			if a.kind == "species_collapse":
				collapsing.append(int(a.species_id))
	return {
		species = here, sapients = world.get_sapient_species(), smartest = smartest, collapsing = collapsing,
		collapses = tracks.collapses, collapse_limit = tracks.collapse_limit, works = tracks.works,
		works_ready = works_ready, budget = actions_per_round,
	}


## Accroche pour la parole de Samaël en début de manche (le texte vient de src/ai/).
func _taunt_code() -> String:
	if samael.favorite != "":
		return "habit_known_" + samael.favorite
	if int(tracks.collapses) >= int(tracks.collapse_limit) - 2:
		return "collapse_near"
	for id in Rules.WORK_ORDER:
		if works_ready.get(id, false) and not tracks.works[id]:
			return "work_within_reach_" + id
	return "round_open"


func _end_round(world: RefCounted, parcel: RefCounted) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in round.threats:
		if t.state == "pending":
			out.append_array(_strike(t, world, parcel))
	_detect_chains(world, out)
	samael.end_round()
	if mode == "eternity" and not challenge.is_empty() and int(challenge.deadline_chapter) <= int(round.index):
		_settle_challenge(Challenges.at_deadline(challenge))
	var recap := "%s : %d menace(s) contrée(s), %d frappée(s)" % [round.name, _round_stats.countered, _round_stats.struck]
	if _round_stats.collapses > 0:
		recap += ", %d effondrement(s) en chaîne" % _round_stats.collapses
	recap += "."
	_refresh_tracks(world, parcel)
	_check_end()
	if not over:
		_start_round(world, parcel, recap)
	return out


func _pending_by_time() -> Array:
	var list := []
	for t in round.get("threats", []):
		if t.state == "pending":
			list.append(t)
	list.sort_custom(func(a, b): return float(a.strikes_year) < float(b.strikes_year) \
		or (float(a.strikes_year) == float(b.strikes_year) and int(a.id) < int(b.id)))
	return list


func _resolve(t: Dictionary, was_countered: bool) -> void:
	t.countered = was_countered
	if was_countered:
		t.state = "countered"
		_round_stats.countered += 1
	_discard.append({kind = t.kind, severity = t.severity})
	threat_resolved.emit(t, was_countered)


# =============================================================================================
# Frappes
# =============================================================================================

## La menace frappe : action divine du type de la carte, appliquée par la simulation.
## La racine causale est renommée (« threat_<kind> ») : ce n'est pas un geste du joueur.
func _strike(t: Dictionary, world: RefCounted, parcel: RefCounted) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var def: Dictionary = Rules.THREATS[t.kind]
	# Devenue anachronique (recul de la civilisation) : la menace se dissipe.
	if not Rules.epoch_ok(t.kind, world.era_index(), _leading_tech(world)):
		t.state = "fizzled"
		_resolve(t, false)
		return out
	if String(def.target) != "none" and not _alive(world, t.target.species_id):
		_retarget(t, world, parcel)
		if not _alive(world, t.target.species_id):
			t.state = "fizzled"
			_resolve(t, false)
			return out
	var collapsing := _is_collapsing(parcel, int(t.target.species_id))
	var action := {type = String(def.strike), region = _cell(parcel),
		species_id = int(t.target.species_id), radius = Rules.strike_radius(t.kind, float(t.severity))}
	var times := 2 if float(t.severity) >= Rules.DOUBLE_STRIKE_SEVERITY else 1
	for i in times:
		var evs: Array = world.apply_divine_action(action)
		if not evs.is_empty():
			var root: Dictionary = evs[0]
			root.type = "threat_" + String(t.kind)
			root.summary = "Menace : %s%s" % [t.title, (" (%s)" % t.target_name) if t.target_name != "" else ""]
		for ev in evs:
			out.append(ev)
	t.state = "struck"
	_round_stats.struck += 1
	_resolve(t, false)
	samael_move.emit({kind = "strike", threat = t, reason_code = String(t.get("samael", {}).get("reason_code", "random"))})
	# Une crise non contrée qui frappe une espèce déjà en chute : effondrement en chaîne (Épreuve).
	if collapsing and mode == "trial":
		_add_collapse()
	return out


func _retarget(t: Dictionary, world: RefCounted, parcel: RefCounted) -> void:
	var sid := _target_for(String(Rules.THREATS[t.kind].target), world, parcel)
	t.target.species_id = sid
	t.target_name = _species_name(world, sid)


# =============================================================================================
# Pistes
# =============================================================================================

## Effondrements en chaîne : un événement d'extinction ou d'effondrement dont la chaîne causale
## remonte à une crise (menace qui a frappé, autre extinction ou effondrement). Une même crise ne
## compte qu'une fois ; les gestes du joueur arrêtent la remontée (ce n'est pas le monde qui échappe).
func _detect_chains(world: RefCounted, events: Array) -> void:
	for ev in events:
		if over or not String(ev.get("type", "")) in CHAIN_TYPES:
			continue
		var cause := int(ev.get("cause_id", -1))
		if cause <= 0:
			continue
		var chain: Array = world.get_causal_chain(cause)
		for i in mini(chain.size(), CHAIN_DEPTH):
			var anc: Dictionary = chain[i]
			var type := String(anc.type)
			if type.begins_with("divine_"):
				break
			# Éternité : laisser passer une menace ne coûte rien sur les pistes.
			if type.begins_with("threat_") and mode == "eternity":
				break
			if type.begins_with("threat_") or type in CHAIN_TYPES:
				if not _chained.has(anc.id):
					_chained[anc.id] = true
					_add_collapse()
				break


func _add_collapse() -> void:
	if _chain_this_round >= MAX_CHAIN_PER_ROUND or over:
		return
	_chain_this_round += 1
	_round_stats.collapses += 1
	tracks.collapses = int(tracks.collapses) + 1
	tracks_changed.emit(tracks)
	_check_end()


## Vitalité 0..1 : biomasse, diversité et abondance de la parcelle (+ bonus du Destructeur).
static func vitality_of(world: RefCounted, parcel: RefCounted) -> float:
	if parcel == null:
		return 1.0
	var ocean: bool = parcel.land_use == "ocean"
	var biomass: float = clampf(parcel.water, 0.0, 1.0) * 0.7 if ocean else clampf(parcel.vegetation, 0.0, 1.0)
	var list := _parcel_species(world, parcel)
	var abundance := 0.0
	for s in list:
		abundance += float(s.density)
	var diversity := clampf(list.size() / FULL_DIVERSITY, 0.0, 1.0)
	return clampf(0.4 * biomass + 0.35 * diversity + 0.25 * clampf(abundance, 0.0, 1.0), 0.0, 1.0)


## Conditions des Grands Œuvres dans la simulation.
static func works_status(world: RefCounted, parcel: RefCounted) -> Dictionary:
	var here := _parcel_species(world, parcel)
	var land := false
	if parcel != null:
		land = not parcel.land_use in ["ocean", "ice", "crater", "flooded"] \
			and parcel.fauna.size() >= 3 and parcel.vegetation >= LAND_VEGETATION
	return {
		life = world.get_alive_species().size() >= 10 and here.size() >= 2,
		land = land,
		mind = not world.get_sapient_species().is_empty(),
		legacy = _leading_tech(world) >= Rules.LEGACY_TECH,
	}


func _refresh_tracks(world: RefCounted, parcel: RefCounted) -> void:
	var v := clampf(vitality_of(world, parcel) + _vitality_bonus, 0.0, 1.0)
	_vitality_peak = maxf(_vitality_peak, v)
	works_ready = works_status(world, parcel)
	var changed := absf(v - float(tracks.vitality)) >= 0.01 or int(tracks.deck_left) != _deck.size()
	tracks.vitality = v
	tracks.deck_left = _deck.size()
	if changed:
		tracks_changed.emit(tracks)


func _check_end() -> void:
	if over:
		return
	var all := true
	for id in Rules.WORK_ORDER:
		all = all and bool(tracks.works[id])
	if mode == "eternity":
		# Pas de fin de partie : la condition ferme le chapitre (traité en fin d'update).
		if not _close_request.is_empty():
			return
		if all:
			_close_request = {code = "works_complete"}
		elif int(tracks.collapses) >= int(tracks.collapse_limit):
			_close_request = {code = "collapses"}
		elif _dead_for >= DEAD_ROUNDS and _vitality_peak >= VITALITY_ALIVE:
			_close_request = {code = "parcel_dead"}
		return
	if all:
		_finish(true, "Les quatre Grands Œuvres sont scellés : le monde porte ta marque pour toujours.")
	elif int(tracks.collapses) >= int(tracks.collapse_limit):
		_finish(false, "Effondrements en chaîne (%d/%d) : le monde échappe à Dieu." % [tracks.collapses, tracks.collapse_limit])
	elif _dead_for >= DEAD_ROUNDS and _vitality_peak >= VITALITY_ALIVE:
		_finish(false, "La parcelle est morte : plus rien n'y vit.")


# =============================================================================================
# Éternité : chapitres et défis
# =============================================================================================

## Ferme le chapitre en cours (Éternité) : les menaces restantes se dissipent, les pistes repartent,
## un nouveau chapitre commence. La collection de Grands Œuvres est conservée.
func _close_chapter(world: RefCounted, parcel: RefCounted) -> void:
	var code := String(_close_request.code)
	_close_request = {}
	for t in round.get("threats", []):
		if t.state == "pending":
			t.state = "fizzled"
			_resolve(t, false)
	# Un défi dont l'échéance tombe ici est tranché ; les autres continuent au chapitre suivant.
	if not challenge.is_empty() and int(challenge.deadline_chapter) <= int(round.index):
		_settle_challenge(Challenges.at_deadline(challenge))
	var info := {index = int(round.get("index", 0)), reason_code = code, reason = String(Rules.CHAPTER_REASONS[code]),
		collected = collection.size()}
	_reset_cycle()
	_vitality_peak = 0.0
	_dead_for = 0.0
	chapter_closed.emit(info)
	_hand = _draw_hand(world, parcel)
	_commit(world, parcel)
	_start_round(world, parcel, info.reason)


## Les pistes repartent : effondrements à zéro, Grands Œuvres du cycle à sceller de nouveau,
## pioche reformée, intensité de départ.
func _reset_cycle() -> void:
	tracks.collapses = 0
	for id in Rules.WORK_ORDER:
		tracks.works[id] = false
	_discard.clear()
	cataclysms = 0
	_build_deck(_deck_size, _deck_cats)
	_hand.clear()
	next_threats.clear()
	_committed = false
	_chain_this_round = 0
	tracks.deck_left = _deck.size()
	tracks_changed.emit(tracks)


func _challenge_context(world: RefCounted, parcel: RefCounted) -> Dictionary:
	var here := _parcel_species(world, parcel)
	var names := {}
	for s in here:
		names[int(s.species_id)] = _species_name(world, int(s.species_id))
	var sapients: Array = world.get_sapient_species()
	for id in sapients:
		names[int(id)] = _species_name(world, int(id))
	return {
		era = world.era_index(), species = here, sapients = sapients, names = names,
		vitality = float(tracks.vitality), budget = actions_per_round,
		land = parcel != null and not parcel.land_use in ["ocean", "ice"],
	}


func _propose_challenge(world: RefCounted, parcel: RefCounted) -> void:
	var c := Challenges.make(_challenge_rng, _challenge_context(world, parcel), int(round.index), _next_challenge_id)
	if c.is_empty():
		return
	_next_challenge_id += 1
	challenge = c
	_challenge_counters = 0
	_challenge_powers = 0
	_challenge_new_species = false
	samael_move.emit({kind = "challenge", threat = {}, challenge = c, reason_code = "challenge_" + String(c.kind)})


func _check_challenge(world: RefCounted) -> void:
	if challenge.is_empty():
		return
	var res := Challenges.check(challenge, {
		alive = func(id): return _alive(world, id),
		sapient = func(id): return _alive(world, id) and bool(world.species[id].sapient),
		vitality = float(tracks.vitality), era = world.era_index(), counters = _challenge_counters,
		powers = _challenge_powers, new_species = _challenge_new_species,
	})
	if res != "":
		_settle_challenge(res)


## Tranche le défi en cours ("open" : abandonné sans suite, le chapitre ayant été fermé avant).
func _settle_challenge(res: String) -> void:
	var c := challenge
	challenge = {}
	if res == "open":
		return
	c.state = res
	if res == "won":
		if c.reward == "action":
			_bonus_next += 1
		else:
			collection.append({work = "samael", label = "Défi relevé : %s" % c.title, chapter = int(round.get("index", 0))})
			tracks.collected = collection.size()
			tracks_changed.emit(tracks)
	challenges_done.append(c)
	if challenges_done.size() > 20:
		challenges_done.pop_front()
	samael_move.emit({kind = "challenge_won" if res == "won" else "challenge_lost", threat = {}, challenge = c,
		reason_code = "challenge_" + String(c.kind)})


func _finish(win: bool, reason: String) -> void:
	if over:
		return
	over = true
	victory = win
	end_reason = reason
	actions_left = 0
	game_over.emit(win, reason)


# =============================================================================================
# Aspects
# =============================================================================================

## Créateur : +1 action quand une espèce nouvelle apparaît sur la parcelle.
func _note_fauna(parcel: RefCounted, silent: bool) -> void:
	if parcel == null:
		return
	for f in parcel.fauna:
		var id := int(f.species_id)
		if _seen_fauna.has(id):
			continue
		_seen_fauna[id] = true
		if not silent:
			_challenge_new_species = true
		if not silent and aspect == "creator" and not over and _creator_bonus < Rules.CREATOR_BONUS_MAX:
			_creator_bonus += 1
			actions_left += 1
			actions_changed.emit(actions_left)


# =============================================================================================
# Lecture de l'état du monde
# =============================================================================================

## Espèces de la parcelle, de la plus dense à la moins dense : [{species_id, density, role}].
## Sur terre : la faune de ParcelSim ; en mer (pas de faune dessinée) : les niches de la région.
static func _parcel_species(world: RefCounted, parcel: RefCounted) -> Array:
	var out := []
	if parcel == null:
		return out
	if parcel.land_use != "ocean" and not parcel.fauna.is_empty():
		for f in parcel.fauna:
			if world.species.has(int(f.species_id)) and world.species[int(f.species_id)].alive:
				out.append({species_id = int(f.species_id), density = float(f.density), role = String(f.role)})
	else:
		for n in world.region_niches(parcel.cell):
			out.append({species_id = int(n.species_id), density = float(n.density),
				role = "sapient" if world.species[int(n.species_id)].sapient else ""})
	out.sort_custom(func(a, b): return a.density > b.density or (a.density == b.density and a.species_id < b.species_id))
	return out


func _target_for(mode: String, world: RefCounted, parcel: RefCounted) -> int:
	var list := _parcel_species(world, parcel)
	var wild := list.filter(func(s): return s.role != "sapient")
	match mode:
		"none":
			return -1
		"abundant":
			return int(wild[0].species_id) if not wild.is_empty() else -1
		"herbivore":
			for s in wild:
				if s.role == "herbivore":
					return int(s.species_id)
			return int(wild[0].species_id) if not wild.is_empty() else -1
		"native":
			return int(wild[1].species_id) if wild.size() >= 2 else -1
		"collapsing":
			if parcel != null:
				for a in parcel.alerts:
					if a.kind == "species_collapse" and _alive(world, int(a.species_id)):
						return int(a.species_id)
			return -1
		"sapient":
			if parcel != null and _alive(world, int(parcel.sapient_id)):
				return int(parcel.sapient_id)
			var best := -1
			var best_tech := -1.0
			for id in world.get_sapient_species():
				if float(world.species[id].tech_level) > best_tech:
					best_tech = float(world.species[id].tech_level)
					best = id
			return best
	return -1


static func _leading_tech(world: RefCounted) -> float:
	var best := -1.0
	for id in world.get_sapient_species():
		best = maxf(best, float(world.species[id].tech_level))
	return best


static func _alive(world: RefCounted, id: int) -> bool:
	return id >= 0 and world.species.has(id) and bool(world.species[id].alive)


static func _species_name(world: RefCounted, id: int) -> String:
	return String(world.species[id].name) if id >= 0 and world.species.has(id) else ""


static func _is_collapsing(parcel: RefCounted, id: int) -> bool:
	if parcel == null or id < 0:
		return false
	for a in parcel.alerts:
		if a.kind == "species_collapse" and int(a.species_id) == id:
			return true
	return false


## La chaleur mondiale monte-t-elle (fenêtre récente de l'historique de la parcelle) ?
static func _warming(parcel: RefCounted) -> bool:
	var h: Array = parcel.history
	if h.size() < 2:
		return true
	var older: Dictionary = h[maxi(0, h.size() - 16)]
	return parcel.global_temperature_c >= float(older.global_temperature_c)


static func _cell(parcel: RefCounted) -> Vector2i:
	return parcel.cell if parcel != null else Vector2i(-1, -1)
