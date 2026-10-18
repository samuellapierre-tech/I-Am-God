extends Node
## Scène principale : deux vues sur le même monde, plus l'interface divine.
## - "globe"  : la planète entière (scenes/globe.tscn, ou la carte 2D historique en attendant).
## - "parcel" : la parcelle suivie, plein écran (scenes/parcel_view.tscn).
## Les vues sont chargées par chemin : chaque branche de module possède sa scène et n'a pas à
## modifier celle-ci. Tab bascule entre les deux vues (GameState.set_view_mode).

const GLOBE_SCENE := "res://scenes/globe.tscn"
const LEGACY_MAP_SCENE := "res://scenes/world_map.tscn"
const PARCEL_SCENE := "res://scenes/parcel_view.tscn"
const STATS_SCENE := "res://scenes/stats_panel.tscn"

var globe: Node
var parcel_view: Node

@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	globe = _instance(GLOBE_SCENE if ResourceLoader.exists(GLOBE_SCENE) else LEGACY_MAP_SCENE)
	parcel_view = _instance(PARCEL_SCENE)
	if ResourceLoader.exists(STATS_SCENE):
		add_child(load(STATS_SCENE).instantiate())
	hud.bind_map(globe)
	GameState.view_mode_changed.connect(_apply_view_mode)
	_apply_view_mode(GameState.view_mode)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_focus_next"):
		GameState.set_view_mode("globe" if GameState.view_mode == "parcel" else "parcel")
		get_viewport().set_input_as_handled()


func _instance(path: String) -> Node:
	var node: Node = load(path).instantiate()
	add_child(node)
	move_child(node, 0)
	return node


## Une seule vue est visible et traite les entrées ; la simulation, elle, ne s'arrête jamais.
func _apply_view_mode(mode: String) -> void:
	for view in [globe, parcel_view]:
		var active: bool = (view == globe) == (mode == "globe")
		view.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		if "visible" in view:
			view.visible = active
		for child in view.get_children():
			if child is Camera2D or child is Camera3D:
				child.current = active
