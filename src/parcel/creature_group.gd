extends RefCounted
## Les individus visibles d'une espèce sur la parcelle : positions, états, fondus.
## Les déplacements sont cosmétiques ; le NOMBRE d'individus suit exactement parcel.fauna[].count
## (les partants s'effacent en fondu, ils ne comptent plus).
##
## step() ne touche qu'aux données de ce groupe et lit un contexte partagé en lecture seule :
## il peut tourner sur un thread de WorkerThreadPool. Ce qui concerne les autres (empreintes,
## poussière, proie attrapée) est noté dans `emits` et traité ensuite par le thread principal.
## flush() (thread principal) envoie le tampon préparé à la MultiMesh en un seul appel.

const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")
const Appearance := preload("res://src/parcel/appearance.gd")

const WANDER := 0
const GRAZE := 1
const SLEEP := 2
const RUN := 3    ## chasse (carnivore) ou fuite (proie)
const EAT := 4
const VISIT := 5  ## espèce intelligente : marche vers une structure
const POUNCE := 6 ## bond final du prédateur
const DOWN := 7   ## proie à terre (se relève, ou s'efface si l'effectif baisse)
const DRINK := 8  ## marche vers la berge pour boire

## Types d'émissions (enregistrements de EMIT_STRIDE flottants : type, x, y, angle, taille).
const EMIT_FOOTPRINT := 0
const EMIT_DUST := 1
const EMIT_SPLASH := 2
const EMIT_CATCH := 9
const EMIT_STRIDE := 5

const FADE_TIME := 1.6
const FLEE_RADIUS := 170.0
const HUNT_GIVE_UP := 9.0
## Un prédateur ne chasse pas une proie beaucoup plus grosse que lui.
const PREY_SIZE_RATIO := 1.3
## Flottants par instance dans MultiMesh.buffer : transform 2D (8) + couleur (4) + custom (4).
const STRIDE := 16

var species_id := -1
var role := ""
var clade := ""
var size := 0.3
var length := 30.0
## Apparence procédurale (Appearance.generate) : forme, couleurs, déplacement.
var app := {}
var _signature := 0
## ParcelLogic.Locomotion : marche, nage en banc, fixé, rampe, vole.
var locomotion := 0
## La parcelle est sous l'eau (prologue).
var aquatic := false
var color := Color.WHITE
var mmi: MultiMeshInstance2D

var pos := PackedVector2Array()
var vel := PackedVector2Array()
var goal := PackedVector2Array()
var heading := PackedFloat32Array()
var alpha := PackedFloat32Array()
var timer := PackedFloat32Array()
var phase := PackedFloat32Array()
var stride := PackedFloat32Array() ## distance parcourue depuis le dernier pas posé
var state := PackedInt32Array()
var leaving := PackedByteArray()
var foot := PackedByteArray() ## pied gauche / droit (empreintes alternées)

var herd_center := Vector2.ZERO
var herd_goal := Vector2.ZERO
var herd_timer := 0.0
var bounds := Rect2(Vector2.ZERO, ParcelLogic.PARCEL_SIZE)
var capacity := 0
var buffer := PackedFloat32Array()
## Remplie par step(), vidée par le thread principal.
var emits := PackedFloat32Array()
## Rivière (repère permanent) : les petits la contournent, les gros la traversent à gué ;
## les troupeaux viennent y boire. Vide = pas de rivière.
var river := PackedVector2Array()
var river_width := 44.0
var river_wet := true ## eau libre (ni à sec, ni gelée)
## Côte (ParcelLogic.coast_vector) : les marcheurs restent à terre, les nageurs dans l'eau.
var coast := Vector2.ZERO
var sea_cell := false

var _rng := RandomNumberGenerator.new()


func _init(p_species_id: int, cell: Vector2i) -> void:
	species_id = p_species_id
	_rng.seed = hash([cell, p_species_id])
	herd_center = _random_point(0.15)
	herd_goal = herd_center


## Met à jour l'apparence depuis une entrée de parcel.fauna. Renvoie true si elle a changé
## (texture / silhouette à recharger).
## traits : traits de l'espèce (génome de la simulation) ; absents => valeurs déduites.
func set_species(f: Dictionary, p_aquatic := false, traits := {}) -> bool:
	var new_size := float(f.get("size", traits.get("size", 0.3)))
	var sig := hash([f.get("role", ""), f.get("clade", ""), f.get("habitat", ""), f.get("diet", ""),
		roundi(new_size * 50.0), p_aquatic, traits])
	if sig == _signature and not app.is_empty():
		return false
	_signature = sig
	role = String(f.get("role", "omnivore"))
	clade = String(f.get("clade", traits.get("clade", "")))
	size = new_size
	aquatic = p_aquatic
	length = ParcelLogic.creature_length(size)
	app = Appearance.generate(traits, f, species_id)
	locomotion = int(app.locomotion)
	color = app.color
	return true


func flies() -> bool:
	return locomotion == ParcelLogic.Locomotion.FLY or int(app.get("limb_kind", 0)) == Appearance.Limb.WING


func active_count() -> int:
	return leaving.count(0)


func leaving_count() -> int:
	return leaving.size() - leaving.count(0)


func is_prey() -> bool:
	return (role == "herbivore" or role == "omnivore") and locomotion != ParcelLogic.Locomotion.SESSILE


## Aligne le nombre d'individus visibles sur `count`, sans saut (fondus). Quand l'effectif baisse,
## ceux qui sont à terre partent en premier : la chasse « explique » la baisse.
func set_target(count: int) -> void:
	var r := ParcelLogic.reconcile(active_count(), leaving_count(), count)
	var revive: int = r.revive
	var i := pos.size() - 1
	while revive > 0 and i >= 0:
		if leaving[i] == 1:
			leaving[i] = 0
			revive -= 1
		i -= 1
	for k in int(r.spawn):
		_spawn()
	var retire: int = r.retire
	for pass_down in [true, false]:
		i = pos.size() - 1
		while retire > 0 and i >= 0:
			if leaving[i] == 0 and (state[i] == DOWN) == pass_down:
				leaving[i] = 1
				retire -= 1
			i -= 1


func is_empty() -> bool:
	return pos.is_empty()


## Individu actif le plus proche de `p` (à moins de max_dist), -1 sinon.
func nearest_agent(p: Vector2, max_dist: float) -> int:
	var best := -1
	var best_d := max_dist * max_dist
	for i in pos.size():
		if leaving[i] == 1 or state[i] == DOWN:
			continue
		var d := pos[i].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


## Thread principal : la proie i est attrapée (à terre) ou s'échappe d'un bond.
func strike(i: int, from: Vector2, escapes: bool) -> void:
	if escapes:
		state[i] = RUN
		timer[i] = 2.0
		goal[i] = _clamp(pos[i] + (pos[i] - from).normalized() * 220.0)
		vel[i] = (pos[i] - from).normalized() * 160.0
	else:
		state[i] = DOWN
		timer[i] = _rng.randf_range(8.0, 14.0)
		vel[i] = Vector2.ZERO


func _spawn() -> void:
	var p: Vector2
	if locomotion == ParcelLogic.Locomotion.SESSILE:
		# Colonies, algues, éponges, plantes : en taches éparses autour du centre de la colonie.
		p = _clamp(herd_center + _random_in_circle(_herd_radius() * 2.2))
	elif role == "carnivore" or locomotion == ParcelLogic.Locomotion.FLY:
		p = _random_point(0.08)
	else:
		p = _clamp(herd_center + _random_in_circle(_herd_radius()))
	pos.append(p)
	vel.append(Vector2.ZERO)
	goal.append(p)
	heading.append(_rng.randf() * TAU)
	alpha.append(0.0)
	timer.append(_rng.randf_range(0.0, 2.0))
	phase.append(_rng.randf())
	stride.append(0.0)
	state.append(GRAZE)
	leaving.append(0)
	foot.append(0)


# --- Simulation cosmétique (thread-safe : ne lit que ctx, n'écrit que ce groupe) ---

## ctx : {prey, prey_len: PackedFloat32Array, hunters, spots: PackedVector2Array, night: float}
func step(delta: float, ctx: Dictionary) -> void:
	emits.clear()
	var prey: PackedVector2Array = ctx.prey
	var prey_len: PackedFloat32Array = ctx.prey_len
	var hunters: PackedVector2Array = ctx.hunters
	var spots: PackedVector2Array = ctx.spots
	var night: float = ctx.get("night", 0.0)
	_update_herd(delta, spots)

	var walk := 18.0 + 22.0 * size
	match locomotion:
		ParcelLogic.Locomotion.CRAWL:
			walk *= 0.45
		ParcelLogic.Locomotion.SWIM:
			walk *= 1.5
	var run := (95.0 if role == "carnivore" else 80.0) + 65.0 * size
	var prey_role := is_prey()
	var sep := length * 0.8
	var max_prey_len := length * PREY_SIZE_RATIO
	var n := pos.size()
	for i in n:
		alpha[i] = clampf(alpha[i] + (-delta if leaving[i] == 1 else delta) / FADE_TIME, 0.0, 1.0)
		timer[i] -= delta
		var p := pos[i]
		var st := state[i]
		var desired := Vector2.ZERO
		if locomotion == ParcelLogic.Locomotion.SESSILE:
			# Fixé : seule l'ondulation (phase lente) anime la forme.
			phase[i] = fposmod(phase[i] + delta * 0.15, 1.0)
			state[i] = GRAZE
			continue

		# Les proies fuient les chasseurs proches (et se réveillent), sauf celles à terre.
		if prey_role and st != DOWN:
			var threat := _nearest(hunters, p, FLEE_RADIUS)
			if threat.x < INF:
				st = RUN
				timer[i] = 1.2
				goal[i] = _clamp(p + (p - threat).normalized() * 140.0)

		if locomotion == ParcelLogic.Locomotion.FLY:
			# Vol en zigzag d'un point à l'autre, brefs vols stationnaires.
			if timer[i] <= 0.0 or p.distance_to(goal[i]) < 12.0:
				goal[i] = _random_point(0.06)
				timer[i] = _rng.randf_range(1.5, 4.5)
			var to_goal := (goal[i] - p).normalized()
			var zig := Vector2(-to_goal.y, to_goal.x) * sin(phase[i] * TAU * 3.0) * 0.6
			desired = (to_goal + zig) * (110.0 + 60.0 * size)
			st = RUN
		elif locomotion == ParcelLogic.Locomotion.SWIM and role != "carnivore" and st != RUN:
			# Banc : cohésion, alignement, cap commun vers le centre du banc qui se déplace.
			desired = _school(i, n, walk)
			st = WANDER
		elif timer[i] <= 0.0:
			if st == RUN or st == POUNCE or st == DOWN:
				st = GRAZE # essoufflé, ou se relève
				timer[i] = _rng.randf_range(2.0, 5.0)
			else:
				st = _decide(i, prey, prey_len, max_prey_len, spots, night)

		# Volants et bancs sont déjà pilotés ci-dessus ; les autres suivent leur état.
		var steered := locomotion == ParcelLogic.Locomotion.FLY or (locomotion == ParcelLogic.Locomotion.SWIM and role != "carnivore" and st == WANDER)
		if not steered:
			match st:
				WANDER, VISIT, DRINK:
					var to := goal[i] - p
					if to.length() < 6.0:
						# Arrivé : broute, boit, se repose ou (espèce intelligente) travaille sur place.
						timer[i] = _rng.randf_range(2.0, 6.0) if st == WANDER else _rng.randf_range(4.0, 8.0)
						if st == DRINK and not river.is_empty():
							heading[i] = (ParcelLogic.nearest_on_polyline(p, river) - p).angle()
						st = GRAZE
					else:
						desired = to.normalized() * (walk * 1.3 if role == "sapient" else walk)
				RUN:
					if role == "carnivore":
						var target := _nearest_prey(prey, prey_len, goal[i], 220.0, max_prey_len)
						if target.x == INF:
							st = WANDER
							goal[i] = _clamp(p + _random_in_circle(250.0))
						else:
							goal[i] = target
							var d := target - p
							if d.length() < length * 1.6:
								st = POUNCE # bond final
								timer[i] = 0.7
							desired = d.normalized() * run
					else:
						desired = (goal[i] - p).normalized() * run
				POUNCE:
					var d := goal[i] - p
					desired = d.normalized() * run * 1.8
					if d.length() < length * 0.45 + 4.0:
						_emit(EMIT_CATCH, goal[i], 0.0, 0.0)
						st = EAT
						timer[i] = _rng.randf_range(5.0, 8.0)
						desired = Vector2.ZERO

		# Séparation : pas d'empilement dans un troupeau.
		if st != POUNCE:
			var push := Vector2.ZERO
			for j in n:
				if j == i:
					continue
				var d := p - pos[j]
				var dl := d.length()
				if dl < sep and dl > 0.001:
					push += d / dl * (sep - dl)
			desired += push * 2.0

		var k := 1.0 - exp(-delta * (8.0 if st == POUNCE else (6.0 if st == RUN else 3.0)))
		var v := vel[i].lerp(desired, k)
		vel[i] = v
		var np := _clamp(p + v * delta)
		pos[i] = np
		var speed := v.length()
		if speed > 2.0:
			heading[i] = lerp_angle(heading[i], v.angle(), 1.0 - exp(-delta * 7.0))
		phase[i] = fposmod(phase[i] + delta * speed / maxf(length * 0.5, 6.0), 1.0)
		state[i] = st
		_footsteps(i, np, speed * delta, speed, walk, st)
	_compact()
	_fill_buffer(run)


## Empreintes alternées gauche/droite et poussière sous les gros (ou ceux qui courent).
func _footsteps(i: int, p: Vector2, moved: float, speed: float, walk: float, st: int) -> void:
	if flies() or alpha[i] < 0.5 or aquatic or locomotion != ParcelLogic.Locomotion.WALK:
		return
	stride[i] += moved
	var step_len := length * 0.4
	if stride[i] < step_len:
		return
	stride[i] = 0.0
	var fwd := Vector2.from_angle(heading[i])
	var side := Vector2(-fwd.y, fwd.x) * (1.0 if foot[i] == 0 else -1.0)
	foot[i] = 1 - foot[i]
	if river_wet and not river.is_empty() and ParcelLogic.distance_to_polyline(p, river) < river_width * 0.5:
		_emit(EMIT_SPLASH, p + side * length * 0.15, 0.0, length * 0.5) # traversée à gué
		return
	if size >= 0.25:
		_emit(EMIT_FOOTPRINT, p + side * length * 0.12, heading[i], length * 0.22)
	var running := st == RUN or st == POUNCE
	if (size >= 0.65 and speed > walk * 0.5) or (running and size >= 0.35):
		_emit(EMIT_DUST, p - fwd * length * 0.3 + side * length * 0.1, _rng.randf() * TAU, length * (0.5 if running else 0.4))


func _emit(kind: int, p: Vector2, angle: float, s: float) -> void:
	emits.append(kind)
	emits.append(p.x)
	emits.append(p.y)
	emits.append(angle)
	emits.append(s)


func _decide(i: int, prey: PackedVector2Array, prey_len: PackedFloat32Array, max_prey_len: float,
		spots: PackedVector2Array, night: float) -> int:
	var r := _rng.randf()
	var p := pos[i]
	# La nuit, presque tout le monde dort (sauf les espèces intelligentes, qui veillent un peu).
	if role != "sapient" and _rng.randf() < night * 0.7:
		timer[i] = _rng.randf_range(10.0, 25.0)
		return SLEEP
	match role:
		"carnivore":
			if r < 0.4:
				var t := _nearest_prey(prey, prey_len, p, 700.0, max_prey_len)
				if t.x < INF:
					goal[i] = t
					timer[i] = HUNT_GIVE_UP
					return RUN
			if r < 0.6:
				timer[i] = _rng.randf_range(10.0, 20.0)
				return SLEEP
			if r < 0.75:
				timer[i] = _rng.randf_range(3.0, 6.0)
				return GRAZE
			goal[i] = _clamp(p + _random_in_circle(320.0))
			timer[i] = _rng.randf_range(8.0, 14.0)
			return WANDER
		"sapient":
			if not spots.is_empty() and r < 0.7:
				goal[i] = _clamp(spots[_rng.randi() % spots.size()] + _random_in_circle(20.0))
				timer[i] = 25.0
				return VISIT
			if r < 0.85:
				timer[i] = _rng.randf_range(3.0, 7.0)
				return GRAZE
			if r < 0.93 or night > 0.6:
				timer[i] = _rng.randf_range(6.0, 12.0)
				return SLEEP
		_:
			if r < 0.12:
				timer[i] = _rng.randf_range(8.0, 18.0)
				return SLEEP
			if r < 0.55:
				timer[i] = _rng.randf_range(3.0, 8.0)
				return GRAZE
			if r < 0.7 and _can_drink():
				goal[i] = _clamp(ParcelLogic.drinking_spot(p, river, river_width, length * 0.45))
				timer[i] = 20.0
				return DRINK
	goal[i] = _clamp(herd_center + _random_in_circle(_herd_radius()))
	timer[i] = _rng.randf_range(6.0, 12.0)
	return WANDER


## Pilotage d'un poisson dans son banc.
func _school(i: int, n: int, speed: float) -> Vector2:
	var p := pos[i]
	var coh := Vector2.ZERO
	var ali := Vector2.ZERO
	var count := 0
	var r2 := (length * 5.0) ** 2
	for j in n:
		if j != i and pos[j].distance_squared_to(p) < r2:
			coh += pos[j]
			ali += vel[j]
			count += 1
	var steer := (herd_center - p).normalized() * speed * 0.7
	if count > 0:
		steer += (coh / count - p) * 0.6 + ali / count * 0.7
	return steer.limit_length(speed)


func _update_herd(delta: float, spots: PackedVector2Array) -> void:
	herd_timer -= delta
	if role == "sapient" and not spots.is_empty():
		var c := Vector2.ZERO
		for s in spots:
			c += s
		herd_goal = c / spots.size()
	elif herd_timer <= 0.0:
		herd_goal = _random_point(0.15)
		# Le troupeau descend régulièrement boire à la rivière.
		if is_prey() and _can_drink() and _rng.randf() < 0.35:
			herd_goal = _clamp(ParcelLogic.drinking_spot(herd_center, river, river_width, _herd_radius() * 0.6))
		herd_timer = _rng.randf_range(20.0, 45.0)
		if locomotion == ParcelLogic.Locomotion.SWIM:
			herd_timer = _rng.randf_range(7.0, 15.0) # les bancs changent souvent de cap
	var herd_speed := 30.0 if locomotion == ParcelLogic.Locomotion.SWIM else 10.0
	herd_center = herd_center.move_toward(herd_goal, herd_speed * delta)


func _herd_radius() -> float:
	return 50.0 + sqrt(float(maxi(active_count(), 1))) * length * 0.9


## Retire les individus complètement effacés.
func _compact() -> void:
	for i in range(pos.size() - 1, -1, -1):
		if leaving[i] == 1 and alpha[i] <= 0.0:
			pos.remove_at(i)
			vel.remove_at(i)
			goal.remove_at(i)
			heading.remove_at(i)
			alpha.remove_at(i)
			timer.remove_at(i)
			phase.remove_at(i)
			stride.remove_at(i)
			state.remove_at(i)
			leaving.remove_at(i)
			foot.remove_at(i)


## Prépare MultiMesh.buffer (format TRANSFORM_2D + couleurs + données perso).
func _fill_buffer(run_speed: float) -> void:
	var n := pos.size()
	if n > capacity:
		capacity = maxi(16, nearest_po2(n))
	if buffer.size() != capacity * STRIDE:
		buffer.resize(capacity * STRIDE)
	buffer.fill(0.0)
	# Carré englobant corps, queue, ailes, tentacules et ombre.
	var quad := length * 1.2 * Appearance.quad_scale(app)
	if int(app.colony) > 0:
		quad *= ParcelLogic.MICROBE_SCALE
	for i in n:
		var st := state[i]
		var q := quad * (1.18 if st == POUNCE else 1.0)
		var c := cos(heading[i]) * q
		var s := sin(heading[i]) * q
		var o := i * STRIDE
		buffer[o] = c
		buffer[o + 1] = -s
		buffer[o + 3] = pos[i].x
		buffer[o + 4] = s
		buffer[o + 5] = c
		buffer[o + 7] = pos[i].y
		buffer[o + 8] = color.r
		buffer[o + 9] = color.g
		buffer[o + 10] = color.b
		buffer[o + 11] = alpha[i]
		buffer[o + 12] = phase[i]
		buffer[o + 13] = ParcelLogic.visual_state(st)
		buffer[o + 14] = clampf(vel[i].length() / maxf(run_speed, 1.0), 0.0, 1.0)


## Thread principal : envoie le tampon à la MultiMesh.
func flush() -> void:
	if mmi == null:
		return
	var mm := mmi.multimesh
	if mm.instance_count != capacity:
		mm.instance_count = capacity
	if capacity > 0:
		mm.buffer = buffer
	mm.visible_instance_count = pos.size()


func _nearest(points: PackedVector2Array, from: Vector2, max_dist: float) -> Vector2:
	var best := Vector2(INF, INF)
	var best_d := max_dist * max_dist
	for q in points:
		var d := q.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = q
	return best


func _nearest_prey(points: PackedVector2Array, lens: PackedFloat32Array, from: Vector2,
		max_dist: float, max_len: float) -> Vector2:
	var best := Vector2(INF, INF)
	var best_d := max_dist * max_dist
	for k in points.size():
		if lens[k] > max_len:
			continue
		var d := points[k].distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = points[k]
	return best


func _can_drink() -> bool:
	return river_wet and not river.is_empty() and role != "sapient"


## Les petits animaux ne traversent pas la rivière (eau libre) : on les garde sur la berge.
func _wades() -> bool:
	return size >= 0.6 or flies() or aquatic or locomotion == ParcelLogic.Locomotion.FLY or locomotion == ParcelLogic.Locomotion.SWIM


func _random_point(inset: float) -> Vector2:
	return bounds.position + bounds.size * Vector2(_rng.randf_range(inset, 1.0 - inset), _rng.randf_range(inset, 1.0 - inset))


func _random_in_circle(r: float) -> Vector2:
	return Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * r


func _clamp(p: Vector2) -> Vector2:
	var m := length * 0.5 + 8.0
	p = Vector2(clampf(p.x, bounds.position.x + m, bounds.end.x - m), clampf(p.y, bounds.position.y + m, bounds.end.y - m))
	if river_wet and river.size() >= 2 and not _wades():
		var q := ParcelLogic.nearest_on_polyline(p, river)
		var keep := river_width * 0.5 + length * 0.3
		var d := q.distance_to(p)
		if d < keep:
			p = q + ((p - q) / d if d > 0.01 else Vector2.LEFT) * keep
	if coast != Vector2.ZERO and locomotion != ParcelLogic.Locomotion.FLY:
		p = _coast_side(p)
		p = Vector2(clampf(p.x, bounds.position.x + m, bounds.end.x - m), clampf(p.y, bounds.position.y + m, bounds.end.y - m))
	return p


## Garde chacun de son côté du rivage : dans l'eau ce qui nage (et ce qui vit fixé en mer),
## sur la terre ce qui marche ou rampe.
func _coast_side(p: Vector2) -> Vector2:
	var marine: bool = locomotion == ParcelLogic.Locomotion.SWIM or str(app.get("habitat", "")) == "marine"
	var uv := p / ParcelLogic.PARCEL_SIZE
	if ParcelLogic.coast_is_water(uv, coast, sea_cell) == marine:
		return p
	var n := coast.normalized()
	var s := (uv - Vector2(0.5, 0.5)).dot(n)
	var edge := 0.5 - coast.length() * 0.38
	# Côté eau : au-delà du rivage (cellule de terre) ou en deçà (cellule de mer).
	var water_beyond := not sea_cell
	var want_beyond: bool = marine == water_beyond
	var target := edge + (0.04 if want_beyond else -0.04)
	return p + n * (target - s) * ParcelLogic.PARCEL_SIZE
