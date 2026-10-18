extends Node2D
## Effets visuels locaux des pouvoirs divins sur la parcelle : éclair, ondes, rayons, débris,
## onde de choc qui déforme l'image, gerbes d'étincelles. Le météore arrive d'abord en traînée
## enflammée ; `impact` est émis au moment où il touche le sol (tout de suite pour les autres
## pouvoirs) : la vue y branche secousse, cratère fumant, cendres, givre, etc.
## Purement cosmétique ; les conséquences viennent de la simulation.

signal impact(power_id: String, at: Vector2, radius: float)

const Powers := preload("res://src/map/divine_powers.gd")
const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")
const ParcelParticles := preload("res://src/parcel/parcel_particles.gd")
const SHOCKWAVE_SHADER := preload("res://shaders/parcel_shockwave.gdshader")

## Durée d'approche du météore avant l'impact (s).
const METEOR_APPROACH := 0.9
const SHOCKWAVE_TIME := 1.1

var parcel_size := ParcelLogic.PARCEL_SIZE
## Pouvoir sélectionné (pour l'aperçu sous le curseur) et son rayon, en unités monde.
var preview_power := ""
var preview_radius := 0.0

var _effects: Array = []
var _waves: Array = [] ## [{node, t, duration}]


## radius : rayon de l'effet en unités monde (plus grand pour une action qui englobe la parcelle).
func spawn(power_id: String, at: Vector2, radius: float) -> void:
	var p := Powers.get_power(power_id)
	var big := power_id in ["meteor", "ice_age", "flood"]
	var delay := METEOR_APPROACH if power_id == "meteor" else 0.0
	var e := {
		id = power_id, pos = at, radius = radius, t = -delay, duration = 2.6 if big else 1.6,
		color = p.get("color", Color.WHITE), seed = hash([power_id, at]), landed = false,
	}
	_effects.append(e)
	if delay == 0.0:
		_land(e)


func _process(delta: float) -> void:
	for e in _effects:
		e.t += delta
		if not e.landed and e.t >= 0.0:
			_land(e)
	_effects = _effects.filter(func(e: Dictionary) -> bool: return e.t < e.duration)
	for w in _waves:
		w.t += delta
		var k: float = w.t / w.duration
		(w.node.material as ShaderMaterial).set_shader_parameter("progress", minf(k, 1.0))
		if k >= 1.0:
			w.node.queue_free()
	_waves = _waves.filter(func(w: Dictionary) -> bool: return w.t < w.duration)
	queue_redraw()


## Le pouvoir touche le sol : onde de choc, étincelles, signal pour la vue.
func _land(e: Dictionary) -> void:
	e.landed = true
	var id := String(e.id)
	var r: float = e.radius
	var at: Vector2 = e.pos
	var color: Color = e.color
	if id in ["meteor", "extinct", "flood", "ice_age", "uplift"]:
		_shockwave(at, r * (2.4 if id == "meteor" else 1.3), color, 40.0 if id == "meteor" else 18.0)
	if id in ["meteor", "extinct", "spawn_species", "bless"]:
		var sparks := ParcelParticles.make_sparks(r * (1.2 if id == "meteor" else 0.6), color)
		sparks.position = at
		sparks.emitting = true
		add_child(sparks)
		get_tree().create_timer(2.5).timeout.connect(sparks.queue_free)
	impact.emit(id, at, r)


func _shockwave(at: Vector2, radius: float, color: Color, strength: float) -> void:
	var node := Node2D.new()
	var mat := ShaderMaterial.new()
	mat.shader = SHOCKWAVE_SHADER
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("tint", color)
	node.material = mat
	node.position = at
	node.draw.connect(func() -> void: node.draw_rect(Rect2(-Vector2.ONE * radius, Vector2.ONE * radius * 2.0), Color.WHITE))
	add_child(node)
	_waves.append({node = node, t = 0.0, duration = SHOCKWAVE_TIME})


func _draw() -> void:
	if preview_power != "":
		var c: Color = Powers.get_power(preview_power).get("color", Color.WHITE)
		var m := get_global_mouse_position()
		draw_arc(m, preview_radius, 0.0, TAU, 64, Color(c, 0.6), 2.0)
		draw_circle(m, 3.0, Color(c, 0.9))
	for e in _effects:
		if e.t < 0.0:
			_draw_meteor_approach(e)
		else:
			_draw_effect(e)


## Traînée enflammée qui plonge du coin haut-gauche vers le point d'impact.
func _draw_meteor_approach(e: Dictionary) -> void:
	var k: float = 1.0 + e.t / METEOR_APPROACH # 0 -> 1
	var target: Vector2 = e.pos
	var from := target + Vector2(-1100.0, -900.0)
	var head := from.lerp(target, k * k)
	var dir := (target - from).normalized()
	for i in 12:
		var f := float(i) / 12.0
		var p := head - dir * f * 380.0
		draw_circle(p, lerpf(26.0, 4.0, f), Color(1.0, lerpf(0.85, 0.3, f), lerpf(0.5, 0.05, f), (1.0 - f) * 0.7))
	draw_circle(head, 30.0, Color(1.0, 0.95, 0.8, 0.9))
	# Ombre du météore qui grandit au sol.
	draw_circle(target, 20.0 + 60.0 * k, Color(0, 0, 0, 0.25 * k))


func _draw_effect(e: Dictionary) -> void:
	var k: float = e.t / e.duration
	var col: Color = e.color
	var pos: Vector2 = e.pos
	var r: float = e.radius
	# Éclair initial.
	var flash := 1.0 - smoothstep(0.0, 0.25, k)
	if flash > 0.0:
		draw_circle(pos, r * (0.3 + 0.5 * k), Color(col.lightened(0.5), 0.75 * flash))
		if e.id == "meteor":
			draw_rect(Rect2(Vector2.ZERO, parcel_size), Color(1.0, 0.9, 0.7, 0.7 * flash))
	# Ondes concentriques.
	for ring in 3:
		var rk := k - ring * 0.12
		if rk <= 0.0 or rk >= 1.0:
			continue
		var rr := r * ease(rk, 0.4) * (1.0 + ring * 0.15)
		draw_arc(pos, rr, 0.0, TAU, 72, Color(col, (1.0 - rk) * 0.8), 6.0 * (1.0 - rk) + 1.0)
	# Rayons (bénédiction, élévation, salut) ou débris (météorite, extinction).
	var rng := RandomNumberGenerator.new()
	rng.seed = e.seed
	match String(e.id):
		"bless", "uplift", "save", "spawn_species":
			for i in 12:
				var d := Vector2.from_angle(i * TAU / 12.0 + k * 0.8)
				draw_line(pos + d * r * 0.1, pos + d * r * (0.3 + 0.7 * k), Color(col, 0.6 * (1.0 - k)), 3.0)
			if e.id == "uplift":
				# Spirale violette : l'étincelle de l'intelligence.
				var pts := PackedVector2Array()
				for i in 40:
					pts.append(pos + Vector2.from_angle(i * 0.45 + k * 6.0) * (i * r * 0.02))
				draw_polyline(pts, Color(col, 0.8 * (1.0 - k)), 3.0)
		"meteor", "extinct":
			for i in 24:
				var d := Vector2.from_angle(rng.randf() * TAU)
				var dist := r * rng.randf_range(0.3, 1.2) * ease(k, 0.3)
				draw_circle(pos + d * dist, rng.randf_range(2.0, 6.0) * (1.0 - k), Color(col.darkened(0.3), 1.0 - k))
		"plague":
			for i in 18:
				var p := pos + Vector2.from_angle(rng.randf() * TAU) * r * sqrt(rng.randf())
				draw_circle(p, rng.randf_range(4.0, 12.0) * k, Color(col, 0.5 * (1.0 - k)))
		"flood", "ice_age":
			draw_circle(pos, r * ease(k, 0.5), Color(col, 0.25 * (1.0 - k)))
