extends Node
## Vitrine de la vue rapprochée : outil de développement, hors jeu et hors suite de tests
## (scène tests/test_parcel_view_showcase.tscn, à lancer avec une fenêtre).
## Pose des espèces INVENTÉES (génomes écrits à la main) sur la parcelle, pour vérifier à l'œil et
## en capture que des traits très différents donnent des créatures très différentes.
##   godot --path . --write-movie out/frame.png --fixed-fps 30 --quit-after 240 \
##         res://tests/test_parcel_view_showcase.tscn -- invented|underwater|abyss|coast|volcano|mountain|flora|gallery|perf
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

const ABYSS := [
	["Tapis de source", {body_plan = "colony", diet = "autotrophe", anaerobic = true, complexity = 0, size = 0.02, habitat = "marine", color = "#e8e4d0"}],
	["Ver des sources", {body_plan = "worm", locomotion = "crawl", color = "#d23b3b", size = 0.3, habitat = "marine", diet = "omnivore", segments = 8}],
	["Crevette pâle", {body_plan = "segmented", locomotion = "swim", limbs = 10, covering = "shell", color = "#f0e6dc", size = 0.12, habitat = "marine", diet = "herbivore"}],
]

const COAST := [
	["Coureur des dunes", {body_plan = "quadruped", covering = "fur", color = "#c9a26b", size = 0.35, diet = "herbivore", pattern = "spots"}],
	["Fusée argentée", {body_plan = "fusiform", locomotion = "swim", fins = 1.0, covering = "scales", color = "#b8c7d6", size = 0.15, habitat = "marine", diet = "omnivore"}],
	["Planeur-voile", {body_plan = "flyer", locomotion = "fly", wings = 1.0, covering = "feathers", color = "#f2f2f2", size = 0.3, diet = "carnivore"}],
]

const FLORA := [
	["Lichen orangé", {diet = "autotrophe", complexity = 1.0, habitat = "land", size = 0.02, pigment = "orange"}],
	["Mousse émeraude", {diet = "autotrophe", complexity = 2.0, habitat = "land", size = 0.08, oxygenic = true}],
	["Prairie rousse", {diet = "autotrophe", complexity = 2.0, habitat = "land", size = 0.3, pigment = "brun"}],
	["Arbre pourpre", {diet = "autotrophe", complexity = 2.0, habitat = "land", size = 0.7, pigment = "pourpre"}],
	["Brouteur rayé", {body_plan = "quadruped", covering = "fur", pattern = "stripes", color = "#e0d0a0", size = 0.5, diet = "herbivore"}],
]

var _traits := {}
var _frames := 0
var _elapsed := 0.0
var _worst := 0.0
var _measuring := false


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
	# Aucune côte ni particularité héritée de la vraie cellule (chaque scénario pose les siennes).
	_cell_info(view, {river = true}, Vector2.ZERO, false)
	match scenario:
		"perf":
			_force(p, "wild", "Forêt tempérée", -50e6, _random_species(40), 0.7)
			_measure.call_deferred()
		"underwater":
			_force(p, "reef", "Océan", -450e6, UNDERWATER, 0.5)
		"abyss":
			_force(p, "ocean", "Abysses", -2.0e9, ABYSS, 0.0)
			p.shore = "sea"
			p.water_depth_m = 3800.0
			_cell_info(view, {vents = true}, Vector2.ZERO, true)
		"coast":
			_force(p, "wild", "Savane", -20e6, COAST, 0.4)
			_cell_info(view, {river = true}, Vector2(-0.85, 0.35), false)
		"volcano":
			_force(p, "barren", "Montagnes", -200e6, [INVENTED[1], INVENTED[5]], 0.05)
			_cell_info(view, {volcanic = true}, Vector2.ZERO, false)
		"mountain":
			_force(p, "wild", "Montagnes", -10e6, [INVENTED[1]], 0.25)
			p.temperature_c = 2.0
		"flora":
			_force(p, "wild", "Forêt tempérée", -300e6, FLORA, 0.75)
		_:
			_force(p, "wild", "Savane", -100e6, INVENTED, 0.35)
	gs.parcel_updated.emit()
	# Pas d'émersion animée héritée de la vraie cellule : l'état forcé s'affiche tout de suite.
	view.terrain.submerged_level = 1.0 if p.shore == "sea" else 0.0


func _cell_info(view: Node, features: Dictionary, coast: Vector2, sea: bool) -> void:
	view._features = features
	view.terrain.set_cell_info(features, coast, sea)
	view.water.set_coast(coast, sea)
	view.creatures.set_coast(coast, sea)
	if not features.get("river", false):
		var lm: Dictionary = view._landmarks.duplicate()
		lm.river = PackedVector2Array()
		view._landmarks = lm
		view.terrain.set_landmarks(lm)
		view.creatures.set_landmarks(lm)


func _force(p, land_use: String, biome: String, year: float, species: Array, veg: float) -> void:
	p.land_use = land_use
	p.biome = biome
	p.year = year
	p.vegetation = veg
	p.water = 0.6
	var sea := land_use in ["ocean", "seabed", "microbial_mat", "reef"]
	p.shore = "sea" if sea else "land"
	p.water_depth_m = 300.0 if sea else -80.0
	p.temperature_c = 24.0
	p.structures.clear()
	p.fauna.clear()
	var id := 5000
	for s in species:
		id += 1
		var t: Dictionary = s[1]
		_traits[id] = t
		var producer: bool = t.get("diet", "") == "autotrophe"
		var count := 8 if species.size() > 20 else (12 if producer else 6)
		p.fauna.append({species_id = id, name = s[0], count = count, density = 0.5, trend = 0,
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


## 40 espèces aux génomes variés (déterministes) pour la mesure de performance.
func _random_species(n: int) -> Array:
	const PLANS := ["worm", "segmented", "fusiform", "quadruped", "biped", "flyer", "bell", "radial", "blob", "shell"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var out := []
	for i in n:
		out.append(["Espèce %d" % i, {body_plan = PLANS[i % PLANS.size()], size = rng.randf_range(0.1, 0.8),
			limbs = rng.randi_range(0, 8), eyes = rng.randi_range(0, 4), color = rng.randf(),
			pattern = ["none", "stripes", "spots", "bands"][i % 4], diet = ["herbivore", "omnivore", "carnivore"][i % 3]}])
	return out


## Mesure : 3 s de mise en route, puis 6 s de mesure (images par seconde moyenne et pire image).
func _measure() -> void:
	await get_tree().create_timer(3.0).timeout
	_measuring = true
	await get_tree().create_timer(6.0).timeout
	_measuring = false
	var view := get_child(0)
	var total := 0
	for g in view.creatures._groups.values():
		total += g.pos.size()
	print("PERF individus=%d especes=%d fps_moyen=%.1f pire_image_ms=%.2f" % [total, view.creatures._groups.size(), _frames / maxf(_elapsed, 0.001), _worst * 1000.0])
	get_tree().quit()


func _process(delta: float) -> void:
	if _measuring:
		_frames += 1
		_elapsed += delta
		_worst = maxf(_worst, delta)
