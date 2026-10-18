extends RefCounted
## Les individus visibles d'une espèce sur la parcelle : positions, états, fondus.
## Les déplacements sont cosmétiques ; le NOMBRE d'individus suit exactement parcel.fauna[].count
## (les partants s'effacent en fondu, ils ne comptent plus).
##
## step() ne touche qu'aux données de ce groupe et lit un contexte partagé en lecture seule :
## il peut tourner sur un thread de WorkerThreadPool. flush() (thread principal) envoie le
## tampon préparé à la MultiMesh en un seul appel.

const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")

const WANDER := 0
const GRAZE := 1
const SLEEP := 2
const RUN := 3   ## chasse (carnivore) ou fuite (proie)
const EAT := 4
const VISIT := 5 ## espèce intelligente : marche vers une structure

const FADE_TIME := 1.6
const FLEE_RADIUS := 170.0
const HUNT_GIVE_UP := 9.0
## Flottants par instance dans MultiMesh.buffer : transform 2D (8) + couleur (4) + custom (4).
const STRIDE := 16

var species_id := -1
var role := ""
var clade := ""
var size := 0.3
var length := 30.0
var shape := 0
var color := Color.WHITE
var mmi: MultiMeshInstance2D

var pos := PackedVector2Array()
var vel := PackedVector2Array()
var goal := PackedVector2Array()
var heading := PackedFloat32Array()
var alpha := PackedFloat32Array()
var timer := PackedFloat32Array()
var phase := PackedFloat32Array()
var state := PackedInt32Array()
var leaving := PackedByteArray()

var herd_center := Vector2.ZERO
var herd_goal := Vector2.ZERO
var herd_timer := 0.0
var bounds := Rect2(Vector2.ZERO, ParcelLogic.PARCEL_SIZE)
var capacity := 0
var buffer := PackedFloat32Array()

var _rng := RandomNumberGenerator.new()


func _init(p_species_id: int, cell: Vector2i) -> void:
	species_id = p_species_id
	_rng.seed = hash([cell, p_species_id])
	herd_center = _random_point(0.15)
	herd_goal = herd_center


## Met à jour l'apparence depuis une entrée de parcel.fauna. Renvoie true si elle a changé
## (texture / silhouette à recharger).
func set_species(f: Dictionary) -> bool:
	var new_role := String(f.get("role", "omnivore"))
	var new_clade := String(f.get("clade", ""))
	var new_size := float(f.get("size", 0.3))
	var changed := new_role != role or new_clade != clade or absf(new_size - size) > 0.02
	if not changed:
		return false
	role = new_role
	clade = new_clade
	size = new_size
	length = ParcelLogic.creature_length(size)
	shape = ParcelLogic.shape_for(clade, role, size)
	color = ParcelLogic.species_color(role, species_id)
	return true


func active_count() -> int:
	return leaving.count(0)


func leaving_count() -> int:
	return leaving.size() - leaving.count(0)


## Aligne le nombre d'individus visibles sur `count`, sans saut (fondus).
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
	i = pos.size() - 1
	while retire > 0 and i >= 0:
		if leaving[i] == 0:
			leaving[i] = 1
			retire -= 1
		i -= 1


func is_empty() -> bool:
	return pos.is_empty()


func _spawn() -> void:
	var p: Vector2
	if role == "carnivore":
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
	state.append(GRAZE)
	leaving.append(0)


# --- Simulation cosmétique (thread-safe : ne lit que ctx, n'écrit que ce groupe) ---

## ctx : {prey: PackedVector2Array, hunters: PackedVector2Array, spots: PackedVector2Array}
func step(delta: float, ctx: Dictionary) -> void:
	var prey: PackedVector2Array = ctx.prey
	var hunters: PackedVector2Array = ctx.hunters
	var spots: PackedVector2Array = ctx.spots
	_update_herd(delta, spots)

	var walk := 18.0 + 22.0 * size
	var run := (95.0 if role == "carnivore" else 80.0) + 65.0 * size
	var is_prey := role == "herbivore" or role == "omnivore"
	var sep := length * 0.8
	var n := pos.size()
	for i in n:
		alpha[i] = clampf(alpha[i] + (-delta if leaving[i] == 1 else delta) / FADE_TIME, 0.0, 1.0)
		timer[i] -= delta
		var p := pos[i]
		var st := state[i]
		var desired := Vector2.ZERO

		# Les proies fuient les chasseurs proches (et se réveillent).
		if is_prey:
			var threat := _nearest(hunters, p, FLEE_RADIUS)
			if threat.x < INF:
				st = RUN
				timer[i] = 1.2
				goal[i] = p + (p - threat).normalized() * 120.0

		if timer[i] <= 0.0 and st != RUN:
			st = _decide(i, prey, spots)
		elif timer[i] <= 0.0 and st == RUN:
			st = GRAZE
			timer[i] = _rng.randf_range(2.0, 5.0)

		match st:
			WANDER, VISIT:
				var to := goal[i] - p
				if to.length() < 6.0:
					# Arrivé : broute, se repose ou (espèce intelligente) travaille sur place.
					timer[i] = _rng.randf_range(3.0, 7.0) if st == VISIT else _rng.randf_range(2.0, 6.0)
					st = GRAZE
				else:
					desired = to.normalized() * (walk * 1.3 if role == "sapient" else walk)
			RUN:
				if role == "carnivore":
					var target := _nearest(prey, goal[i], 220.0)
					if target.x == INF:
						st = WANDER
						goal[i] = _clamp(p + _random_in_circle(250.0))
					else:
						goal[i] = target
						var d := target - p
						if d.length() < length * 0.45 + 4.0:
							st = EAT
							timer[i] = _rng.randf_range(4.0, 7.0)
						else:
							desired = d.normalized() * run
				else:
					desired = (goal[i] - p).normalized() * run

		# Séparation : pas d'empilement dans un troupeau.
		var push := Vector2.ZERO
		for j in n:
			if j == i:
				continue
			var d := p - pos[j]
			var dl := d.length()
			if dl < sep and dl > 0.001:
				push += d / dl * (sep - dl)
		desired += push * 2.0

		var k := 1.0 - exp(-delta * (6.0 if st == RUN else 3.0))
		var v := vel[i].lerp(desired, k)
		vel[i] = v
		pos[i] = _clamp(p + v * delta)
		var speed := v.length()
		if speed > 2.0:
			heading[i] = lerp_angle(heading[i], v.angle(), 1.0 - exp(-delta * 7.0))
		phase[i] = fposmod(phase[i] + delta * speed / maxf(length * 0.5, 6.0), 1.0)
		state[i] = st
	_compact()
	_fill_buffer(run)


func _decide(i: int, prey: PackedVector2Array, spots: PackedVector2Array) -> int:
	var r := _rng.randf()
	var p := pos[i]
	match role:
		"carnivore":
			if not prey.is_empty() and r < 0.4:
				var t := _nearest(prey, p, 700.0)
				goal[i] = t if t.x < INF else prey[_rng.randi() % prey.size()]
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
			if r < 0.93:
				timer[i] = _rng.randf_range(6.0, 12.0)
				return SLEEP
		_:
			if r < 0.12:
				timer[i] = _rng.randf_range(8.0, 18.0)
				return SLEEP
			if r < 0.55:
				timer[i] = _rng.randf_range(3.0, 8.0)
				return GRAZE
	goal[i] = _clamp(herd_center + _random_in_circle(_herd_radius()))
	timer[i] = _rng.randf_range(6.0, 12.0)
	return WANDER


func _update_herd(delta: float, spots: PackedVector2Array) -> void:
	herd_timer -= delta
	if role == "sapient" and not spots.is_empty():
		var c := Vector2.ZERO
		for s in spots:
			c += s
		herd_goal = c / spots.size()
	elif herd_timer <= 0.0:
		herd_goal = _random_point(0.15)
		herd_timer = _rng.randf_range(20.0, 45.0)
	herd_center = herd_center.move_toward(herd_goal, 10.0 * delta)


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
			state.remove_at(i)
			leaving.remove_at(i)


## Prépare MultiMesh.buffer (format TRANSFORM_2D + couleurs + données perso).
func _fill_buffer(run_speed: float) -> void:
	var n := pos.size()
	if n > capacity:
		capacity = maxi(16, nearest_po2(n))
	if buffer.size() != capacity * STRIDE:
		buffer.resize(capacity * STRIDE)
	buffer.fill(0.0)
	var quad := length * 1.35 # carré englobant queue, ailes et ombre
	for i in n:
		var c := cos(heading[i]) * quad
		var s := sin(heading[i]) * quad
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
		var st := state[i]
		buffer[o + 12] = phase[i]
		buffer[o + 13] = 1.0 if st == GRAZE or st == EAT else (2.0 if st == SLEEP else (3.0 if st == RUN else 0.0))
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


func _random_point(inset: float) -> Vector2:
	return bounds.position + bounds.size * Vector2(_rng.randf_range(inset, 1.0 - inset), _rng.randf_range(inset, 1.0 - inset))


func _random_in_circle(r: float) -> Vector2:
	return Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * r


func _clamp(p: Vector2) -> Vector2:
	var m := length * 0.5 + 8.0
	return Vector2(clampf(p.x, bounds.position.x + m, bounds.end.x - m), clampf(p.y, bounds.position.y + m, bounds.end.y - m))
