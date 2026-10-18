extends Node2D
## Vue parcelle (provisoire) : le terrain suivi, plein écran, vu de haut.
## Version minimale du contrat : sol coloré selon l'usage, structures et un point par individu.
## La branche feature/parcel-view la remplace (terrain, créatures animées, transitions).

const GROUND := {
	"ocean": Color("1d4e7a"), "ice": Color("dfe9f0"), "wild": Color("4f7a3a"), "crater": Color("4a3a33"),
	"flooded": Color("3f6f86"), "camp": Color("5a7d3c"), "pasture": Color("7f9a4a"),
	"farmland": Color("a39a52"), "village": Color("8e8a5c"), "town": Color("7c7a6e"),
	"city": Color("6b6b70"), "megacity": Color("4c4d58"), "arcology": Color("2c2a3e"),
	"ruins": Color("6a6150"), "rewild": Color("44703c"),
}
const ROLE_COLORS := {
	"herbivore": Color("e9d8a6"), "carnivore": Color("d1495b"), "omnivore": Color("edae49"),
	"sapient": Color("8ecae6"),
}

@onready var camera: Camera2D = $Camera


func _ready() -> void:
	GameState.parcel_updated.connect(queue_redraw)


func _draw() -> void:
	var p = GameState.parcel
	if p == null:
		return
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), GROUND.get(p.land_use, Color.DIM_GRAY))
	for s in p.structures:
		var r: float = s.size * size.y
		draw_rect(Rect2(s.pos * size - Vector2(r, r) * 0.5, Vector2(r, r)), Color(0, 0, 0, 0.35))
	for f in p.fauna:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([p.cell, f.species_id])
		for k in f.count:
			var pos := Vector2(rng.randf(), rng.randf()) * size
			draw_circle(pos, 4.0 + 14.0 * f.size, ROLE_COLORS.get(f.role, Color.WHITE))
