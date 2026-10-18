extends Node2D
## Effets visuels locaux des pouvoirs divins sur la parcelle : éclair, onde de choc, rayons,
## débris. Purement cosmétique ; les conséquences viennent de la simulation.

const Powers := preload("res://src/map/divine_powers.gd")
const ParcelLogic := preload("res://src/parcel/parcel_logic.gd")

var parcel_size := ParcelLogic.PARCEL_SIZE
## Pouvoir sélectionné (pour l'aperçu sous le curseur) et son rayon, en unités monde.
var preview_power := ""
var preview_radius := 0.0

var _effects: Array = []


## radius : rayon de l'effet en unités monde (grand pour une action venue du globe).
func spawn(power_id: String, at: Vector2, radius: float) -> void:
	var p := Powers.get_power(power_id)
	var big := power_id in ["meteor", "ice_age", "flood"]
	_effects.append({
		id = power_id, pos = at, radius = radius, t = 0.0, duration = 2.6 if big else 1.6,
		color = p.get("color", Color.WHITE), seed = hash([power_id, at]),
	})
	set_process(true)


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	for e in _effects:
		e.t += delta
	_effects = _effects.filter(func(e: Dictionary) -> bool: return e.t < e.duration)
	queue_redraw()


func _draw() -> void:
	if preview_power != "":
		var c: Color = Powers.get_power(preview_power).get("color", Color.WHITE)
		var m := get_global_mouse_position()
		draw_arc(m, preview_radius, 0.0, TAU, 64, Color(c, 0.6), 2.0)
		draw_circle(m, 3.0, Color(c, 0.9))
	for e in _effects:
		_draw_effect(e)


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
			draw_rect(Rect2(Vector2.ZERO, parcel_size), Color(1.0, 0.9, 0.7, 0.55 * flash))
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
