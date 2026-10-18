extends Node2D
## Scène principale : relie la carte du monde (src/map/) et l'interface divine (src/ui/).

@onready var world_map: Node2D = $WorldMap
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	hud.bind_map(world_map)
