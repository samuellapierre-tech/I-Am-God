extends Node
## Vitrine de la vue rapprochée (hors suite de tests automatiques : à lancer avec une fenêtre).
## Pose des espèces INVENTÉES (génomes écrits à la main) sur la parcelle, pour vérifier à l'œil et
## en capture que des traits très différents donnent des créatures très différentes.
##   godot --path . --write-movie out/frame.png --fixed-fps 30 --quit-after 240 \
##         res://tests/test_parcel_view_showcase.tscn -- invented|underwater|biomes
## Arguments : scénario (défaut : invented).

const INVENTED := [
	["Glissombre", {body_plan = "worm", locomotion = "crawl", segments = 10, covering = "skin", pattern = "bands", color = "#6b3fa0", eyes = 0, size = 0.35, diet = "carnivore"}],
	["Tricorne bleu", {body_plan = "quadruped", horns = 1.0, covering = "scales", pattern = "stripes", color = "#2f6fd6", limbs = 4, size = 0.8, diet = "herbivore", tail = 0.6}],
	["Étoile-filet", {body_plan = "radial", symmetry = "radial", locomotion = "crawl", limbs = 7, covering = "shell", pattern = "spots", color = "#f08a24", size = 0.3, diet = "carnivore"}],
	["Planeur-voile", {body_plan = "flyer", locomotion = "fly", wings = 1.0, covering = "feathers", color = "#f2d43a", limbs = 4, size = 0.35, diet = "omnivore", tail = 0.4}],
	["Hexapode cuirassé", {body_plan = "segmented", limbs = 12, covering = "shell", pattern = "mottled", color = "#c0392b", eyes = 6, size = 0.45, segments = 5, diet = "herbivore"}],
	["Bipède à crête", {body_plan = "biped", sail = 1.0, covering = "fur", pattern = "spots", color = "#3fa34d", eyes = 2, size = 0.55, diet = "carnivore", tail = 0.9, aggression = 0.9}],
	["Colonie pourpre", {body_plan = "colony", diet = "autotrophe", anaerobic = true, complexity = 0, size = 0.02}],
	["Rampeur à six yeux", {body_plan = "blob", locomotion = "walk", limbs = 8, eyes = 6, covering = "gel", color = "#58d0c4", size = 0.25, diet = "omnivore"}],
]

const UNDERWATER := [
	["Fusée argentée", {body_plan = "fusiform", locomotion = "swim", fins = 1.0, covering = "scales", color = "#b8c7d6", pattern = "bands", size = 0.15, habitat = "marine", diet = "omnivore"}],
	["Fusée orange", {body_plan = "fusiform", locomotion = "swim", fins = 0.8, covering = "scales", color = "#ff8c2a", pattern = "stripes", size = 0.12, habitat = "marine", diet = "herbivore"}],
	["Cloche-lampe", {body_plan = "bell", locomotion = "swim", limbs = 10, covering = "gel", color = "#7fe6ff", size = 0.25, habitat = "marine", diet = "carnivore"}],
	["Crabe-bouclier", {body_plan = "segmented", locomotion = "crawl", limbs = 10, covering = "shell", color = "#b5462e", horns = 0.7, size = 0.3, habitat = "marine", diet = "carnivore"}],
	["Forêt de varech", {body_plan = "frond", diet = "autotrophe", limbs = 8, color = "#7a8a2a", size = 0.5, habitat = "marine"}],
	["Éponge vase", {body_plan = "vase", diet = "herbivore", color = "#e7a34a", size = 0.2, habitat = "marine"}],
	["Prédateur ruban", {body_plan = "worm", locomotion = "swim", segments = 12, color = "#2a3d8f", pattern = "spots", size = 0.6, habitat = "marine", diet = "carnivore", aggression = 0.9}],
]

var _traits := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var scenario: String = args[0] if args.size() > 0 else "invented"
	if scenario == "gallery":
		_gallery(INVENTED + UNDERWATER)
		return
	var view: Node = load("res://scenes/parcel_view.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	var gs: Node = get_node("/root/GameState")
	gs.paused = true
	var p = gs.parcel
	view.creatures.traits_of = func(id: int) -> Dictionary: return _traits.get(id, {})
	match scenario:
		"underwater":
			_force(p, "reef", "Océan", -450e6, UNDERWATER, 0.5)
		_:
			_force(p, "wild", "Savane", -100e6, INVENTED, 0.35)
	gs.parcel_updated.emit()


func _force(p, land_use: String, biome: String, year: float, species: Array, veg: float) -> void:
	p.land_use = land_use
	p.biome = biome
	p.year = year
	p.vegetation = veg
	p.water = 0.6
	p.temperature_c = 24.0
	p.structures.clear()
	p.fauna.clear()
	var id := 5000
	for s in species:
		id += 1
		var t: Dictionary = s[1]
		_traits[id] = t
		var producer: bool = t.get("diet", "") == "autotrophe"
		p.fauna.append({species_id = id, name = s[0], count = 12 if producer else 6, density = 0.5, trend = 0,
			role = "producer" if producer else String(t.get("diet", "omnivore")),
			habitat = String(t.get("habitat", "land")), size = float(t.get("size", 0.3)), clade = "", diet = String(t.get("diet", "omnivore"))})


## Galerie : chaque espèce en grand, côte à côte, sur fond neutre (silhouettes et motifs lisibles).
func _gallery(species: Array) -> void:
	const Appearance := preload("res://src/parcel/appearance.gd")
	const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")
	var bg := ColorRect.new()
	bg.color = Color(0.55, 0.58, 0.45)
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	var cols := 5
	var cell := Vector2(1920.0 / cols, 1080.0 / ceilf(species.size() / float(cols)))
	for i in species.size():
		var app := Appearance.generate(species[i][1], {}, i)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = ParcelLogic.unit_quad()
		mm.instance_count = 1
		var side := minf(cell.x, cell.y) * 0.8
		var center := Vector2((i % cols + 0.5) * cell.x, (i / cols + 0.45) * cell.y)
		mm.set_instance_transform_2d(0, Transform2D(-0.6, Vector2(side, side), 0.0, center))
		mm.set_instance_color(0, app.color)
		mm.set_instance_custom_data(0, Color(0.1 * i, 0.0, 0.6, 0.0))
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/parcel_creature.gdshader")
		Appearance.to_material(mat, app)
		var mmi := MultiMeshInstance2D.new()
		mmi.multimesh = mm
		mmi.material = mat
		add_child(mmi)
		var label := Label.new()
		label.text = species[i][0]
		label.position = center + Vector2(-cell.x * 0.45, cell.y * 0.38)
		label.add_theme_color_override("font_color", Color.BLACK)
		add_child(label)
