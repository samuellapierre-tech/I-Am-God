extends Node2D
## Toutes les créatures de la parcelle : une MultiMeshInstance2D par espèce (un seul appel de
## dessin par espèce), comportements calculés en parallèle (un groupe par tâche de
## WorkerThreadPool) au-delà de THREAD_MIN_AGENTS individus.

const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")
const ParcelAssets := preload("res://src/parcel/parcel_assets.gd")
const CreatureGroup := preload("res://src/parcel/creature_group.gd")
const TrailLayer := preload("res://src/parcel/trail_layer.gd")
const CREATURE_SHADER := preload("res://shaders/parcel_creature.gdshader")

const THREAD_MIN_AGENTS := 96
## Probabilité qu'une proie attrapée s'échappe d'un bond au dernier moment.
const ESCAPE_CHANCE := 0.45

var assets: ParcelAssets
## Positions (monde) des structures habitables : destinations des espèces intelligentes.
var spots := PackedVector2Array()
## Marques au sol (empreintes, poussière) : TrailLayer, optionnel.
var trail: TrailLayer
## 0 (jour) .. 1 (nuit) : les animaux dorment plus la nuit.
var night := 0.0

var _groups := {} ## species_id -> CreatureGroup
var _list: Array = []
var _ctx := {}
var _delta := 0.0
var _quad: ArrayMesh
var _rng := RandomNumberGenerator.new()
var _landmarks := {}
var _river_wet := true


func _ready() -> void:
	_quad = ParcelLogic.unit_quad()
	if assets == null:
		assets = ParcelAssets.new()


func apply_parcel(p: ParcelSim) -> void:
	var seen := {}
	var aquatic := ParcelLogic.submerged(p.land_use) > 0.5
	for f in p.fauna:
		var id := int(f.species_id)
		seen[id] = true
		var g: CreatureGroup = _groups.get(id)
		if g == null:
			g = CreatureGroup.new(id, p.cell)
			_groups[id] = g
			_give_river(g)
		if g.set_species(f, aquatic) or g.mmi == null:
			_refresh_look(g)
		g.set_target(int(f.count))
	for id in _groups:
		if not seen.has(id):
			_groups[id].set_target(0)


## Nouvelle parcelle : on repart de zéro.
func clear() -> void:
	for g in _groups.values():
		if g.mmi:
			g.mmi.queue_free()
	_groups.clear()


## Rivière permanente (ParcelLogic.landmarks) et son état : eau libre ou non (sec, gelé).
func set_landmarks(lm: Dictionary) -> void:
	_landmarks = lm
	for g: CreatureGroup in _groups.values():
		_give_river(g)


func set_river_open(open: bool) -> void:
	if open == _river_wet:
		return
	_river_wet = open
	for g: CreatureGroup in _groups.values():
		g.river_wet = open


func _give_river(g: CreatureGroup) -> void:
	if _landmarks.is_empty():
		return
	g.river = _landmarks.river
	g.river_width = _landmarks.river_width
	g.river_wet = _river_wet


## Centre du groupe d'une espèce (moyenne des individus visibles), INF si absente.
func herd_center_of(species_id: int) -> Vector2:
	var g: CreatureGroup = _groups.get(species_id)
	if g == null or g.pos.is_empty():
		return Vector2(INF, INF)
	var c := Vector2.ZERO
	for p in g.pos:
		c += p
	return c / g.pos.size()


func _process(delta: float) -> void:
	if _groups.is_empty():
		return
	_build_context()
	_list = _groups.values()
	_delta = minf(delta, 0.1)
	var total := 0
	for g: CreatureGroup in _list:
		total += g.pos.size()
	if total >= THREAD_MIN_AGENTS and _list.size() > 1:
		var task := WorkerThreadPool.add_group_task(_step_group, _list.size(), -1, true, "parcel creatures")
		WorkerThreadPool.wait_for_group_task_completion(task)
	else:
		for i in _list.size():
			_step_group(i)
	for g: CreatureGroup in _list:
		g.flush()
		_handle_emits(g)
		if g.is_empty() and g.active_count() == 0:
			if g.mmi:
				g.mmi.queue_free()
			_groups.erase(g.species_id)
	_list = []


func _step_group(i: int) -> void:
	(_list[i] as CreatureGroup).step(_delta, _ctx)


## Instantané en lecture seule partagé par les tâches : proies, chasseurs en action, destinations.
func _build_context() -> void:
	var prey := PackedVector2Array()
	var prey_len := PackedFloat32Array()
	var hunters := PackedVector2Array()
	for g: CreatureGroup in _groups.values():
		var is_prey := g.is_prey()
		for i in g.pos.size():
			if g.leaving[i] == 1 or g.alpha[i] < 0.3:
				continue
			var st := g.state[i]
			if is_prey and st != CreatureGroup.DOWN:
				prey.append(g.pos[i])
				prey_len.append(g.length)
			elif g.role == "carnivore" and g.locomotion != ParcelLogic.Locomotion.FLY and (st == CreatureGroup.RUN or st == CreatureGroup.POUNCE):
				hunters.append(g.pos[i])
	_ctx = {prey = prey, prey_len = prey_len, hunters = hunters, spots = spots, night = night}


## Thread principal : traces au sol et proies attrapées (qui touchent d'autres groupes).
func _handle_emits(g: CreatureGroup) -> void:
	var e := g.emits
	var k := 0
	while k + CreatureGroup.EMIT_STRIDE <= e.size():
		var kind := int(e[k])
		var p := Vector2(e[k + 1], e[k + 2])
		match kind:
			CreatureGroup.EMIT_FOOTPRINT:
				if trail:
					trail.emit(TrailLayer.Kind.FOOTPRINT, p, e[k + 3], e[k + 4])
			CreatureGroup.EMIT_DUST:
				if trail:
					trail.emit(TrailLayer.Kind.DUST, p, e[k + 3], e[k + 4])
			CreatureGroup.EMIT_SPLASH:
				if trail:
					trail.emit(TrailLayer.Kind.SPLASH, p, 0.0, e[k + 4])
			CreatureGroup.EMIT_CATCH:
				_resolve_catch(p)
		k += CreatureGroup.EMIT_STRIDE


func _resolve_catch(p: Vector2) -> void:
	for g: CreatureGroup in _groups.values():
		if not g.is_prey():
			continue
		var i := g.nearest_agent(p, g.length * 0.6 + 30.0)
		if i >= 0:
			g.strike(i, p, _rng.randf() < ESCAPE_CHANCE)
			if trail:
				trail.emit(TrailLayer.Kind.DUST, g.pos[i], 0.0, g.length * 0.8)
			return


func _refresh_look(g: CreatureGroup) -> void:
	if g.mmi == null:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _quad
		g.mmi = MultiMeshInstance2D.new()
		g.mmi.multimesh = mm
		g.mmi.name = "Species%d" % g.species_id
		add_child(g.mmi)
	var tex := assets.creature_texture(g.clade, g.role)
	var mat := ShaderMaterial.new()
	mat.shader = CREATURE_SHADER
	mat.set_shader_parameter("use_texture", tex != null)
	mat.set_shader_parameter("shape", g.shape)
	var swimmer := g.locomotion == ParcelLogic.Locomotion.SWIM
	mat.set_shader_parameter("variant", 1 if swimmer and g.shape in [ParcelLogic.Shape.ARTHROPOD, ParcelLogic.Shape.MOLLUSK] else 0)
	g.mmi.material = mat
	g.mmi.texture = tex
	# Les volants au-dessus, puis les plus gros au-dessus des petits.
	g.mmi.z_index = 3 if g.locomotion == ParcelLogic.Locomotion.FLY else (2 if g.shape == ParcelLogic.Shape.BIRD else 1)
	# Les organismes fixés (tapis, algues, éponges, plantes) restent sous les animaux.
	if g.locomotion == ParcelLogic.Locomotion.SESSILE:
		g.mmi.z_index = 0
	_sort_children()


func _sort_children() -> void:
	var nodes := get_children()
	nodes.sort_custom(func(a: Node, b: Node) -> bool: return _length_of(a) < _length_of(b))
	for k in nodes.size():
		move_child(nodes[k], k)


func _length_of(node: Node) -> float:
	for g: CreatureGroup in _groups.values():
		if g.mmi == node:
			return g.length
	return 0.0
