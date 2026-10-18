extends Node2D
## Toutes les créatures de la parcelle : une MultiMeshInstance2D par espèce (un seul appel de
## dessin par espèce), comportements calculés en parallèle (un groupe par tâche de
## WorkerThreadPool) au-delà de THREAD_MIN_AGENTS individus.

const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")
const ParcelSim := preload("res://src/sim/parcel_sim.gd")
const ParcelAssets := preload("res://src/parcel/parcel_assets.gd")
const CreatureGroup := preload("res://src/parcel/creature_group.gd")
const CREATURE_SHADER := preload("res://shaders/parcel_creature.gdshader")

const THREAD_MIN_AGENTS := 96

var assets: ParcelAssets
## Positions (monde) des structures habitables : destinations des espèces intelligentes.
var spots := PackedVector2Array()

var _groups := {} ## species_id -> CreatureGroup
var _list: Array = []
var _ctx := {}
var _delta := 0.0
var _quad: ArrayMesh


func _ready() -> void:
	_quad = _make_quad()
	if assets == null:
		assets = ParcelAssets.new()


func apply_parcel(p: ParcelSim) -> void:
	var seen := {}
	for f in p.fauna:
		var id := int(f.species_id)
		seen[id] = true
		var g: CreatureGroup = _groups.get(id)
		if g == null:
			g = CreatureGroup.new(id, p.cell)
			_groups[id] = g
		if g.set_species(f) or g.mmi == null:
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
		WorkerThreadPool.wait_group_task_completion(task)
	else:
		for i in _list.size():
			_step_group(i)
	for g: CreatureGroup in _list:
		g.flush()
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
	var hunters := PackedVector2Array()
	for g: CreatureGroup in _groups.values():
		var is_prey := g.role == "herbivore" or g.role == "omnivore"
		for i in g.pos.size():
			if g.leaving[i] == 1 or g.alpha[i] < 0.3:
				continue
			if is_prey:
				prey.append(g.pos[i])
			elif g.role == "carnivore" and g.state[i] == CreatureGroup.RUN:
				hunters.append(g.pos[i])
	_ctx = {prey = prey, hunters = hunters, spots = spots}


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
	g.mmi.material = mat
	g.mmi.texture = tex
	# Les volants au-dessus, puis les plus gros au-dessus des petits.
	g.mmi.z_index = 2 if g.shape == ParcelLogic.Shape.BIRD else 1
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


## Quadrilatère unité centré, UV explicites (image tête vers +x, non retournée).
static func _make_quad() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([
		Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
