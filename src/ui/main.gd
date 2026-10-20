extends Node
## Scène principale (docs/GENESE.md) : deux vues sur le même monde, du ciel jusqu'au sol.
## - "globe"  : la planète 3D (scenes/globe.tscn) ;
## - "ground" : la vue rapprochée du lieu suivi (scenes/parcel_view.tscn), pouvoirs via ParcelPowers.
## Zoom maximal sur le globe -> on descend au sol à cet endroit (GameState.select_parcel puis
## "ground") ; dézoom au minimum au sol -> on remonte au globe. Tab bascule aussi. Fondu entre les deux.
## Une seule vue est active et traite les entrées (src/globe/view_router.gd) ; le HUD suit la vue
## active (bind_map) et l'outil choisi la suit, sans jamais être appliqué deux fois.

const GLOBE_SCENE := "res://scenes/globe.tscn"
const PARCEL_SCENE := "res://scenes/parcel_view.tscn"
const STATS_SCENE := "res://scenes/stats_panel.tscn"
## Fil de narration d'Ézéchiel, le compagnon.
const OVERLAY_SCENES := ["res://scenes/narration_feed.tscn"]
const ParcelPowers := preload("res://src/ui/parcel_powers.gd")
const ViewRouter := preload("res://src/globe/view_router.gd")

const FADE_OUT := 0.22
const FADE_IN := 0.45

var globe: Node
var parcel_view: Node
var powers: Node

var _fade: ColorRect
var _switching := false

@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	parcel_view = _instance(PARCEL_SCENE)
	if ResourceLoader.exists(GLOBE_SCENE):
		globe = _instance(GLOBE_SCENE)
		if globe.has_signal("descend_requested"):
			globe.descend_requested.connect(func(cell: Vector2i) -> void: switch_to(ViewRouter.GROUND, cell))
	for path in [STATS_SCENE] + OVERLAY_SCENES:
		if ResourceLoader.exists(path):
			add_child(load(path).instantiate())
	powers = ParcelPowers.new()
	powers.name = "ParcelPowers"
	add_child(powers)

	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 50
	add_child(fade_layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade)

	GameState.view_mode_changed.connect(_apply_view_mode)
	if globe == null:
		GameState.set_view_mode(ViewRouter.GROUND)
	_apply_view_mode(GameState.view_mode)


func _instance(path: String) -> Node:
	var node: Node = load(path).instantiate()
	add_child(node)
	move_child(node, 0)
	return node


func _views() -> Dictionary:
	return {
		ViewRouter.GLOBE: [globe] if globe != null else [],
		ViewRouter.GROUND: [powers, parcel_view],
	}


## Bascule vers `mode` avec un fondu ; `cell` (facultatif) : le lieu où descendre.
func switch_to(mode: String, cell := Vector2i(-1, -1)) -> void:
	if _switching or not ViewRouter.is_valid(mode) or mode == GameState.view_mode:
		return
	if mode == ViewRouter.GLOBE and globe == null:
		return
	_switching = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, FADE_OUT).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		if cell.x >= 0 and (GameState.parcel == null or GameState.parcel.cell != cell):
			GameState.select_parcel(cell)
		if mode == ViewRouter.GLOBE and GameState.parcel != null and globe.has_method("arrive_from_ground"):
			globe.arrive_from_ground(GameState.parcel.cell)
		GameState.set_view_mode(mode))
	tw.tween_property(_fade, "color:a", 0.0, FADE_IN).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _switching = false)


func _apply_view_mode(mode: String) -> void:
	var views := _views()
	ViewRouter.apply(mode, views)
	var owner := ViewRouter.input_owner(mode, views)
	ViewRouter.transfer_power_state(hud.map, owner)
	_bind_hud(owner)


## Le HUD pilote l'outil de la vue active ; une vue déjà reliée n'est pas reconnectée.
func _bind_hud(owner: Node) -> void:
	if owner == null or not owner.has_signal("state_changed"):
		return
	var sync := Callable(hud, "_sync_from_map")
	if owner.is_connected("state_changed", sync):
		hud.map = owner
		sync.call()
	else:
		hud.bind_map(owner)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.physical_keycode == KEY_TAB:
		switch_to(ViewRouter.toggled(GameState.view_mode))
		get_viewport().set_input_as_handled()


## Dézoom au minimum dans la vue rapprochée : on remonte au globe. Lu avant la caméra de la parcelle,
## qui consomme la molette.
func _input(event: InputEvent) -> void:
	if GameState.view_mode != ViewRouter.GROUND or _switching or globe == null:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.shift_pressed or mb.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		return
	if get_viewport().gui_get_hovered_control() != null:
		return
	var cam = parcel_view.get_node_or_null("Camera")
	if cam == null or not cam.has_method("min_zoom") or not "target_zoom" in cam:
		return
	if ViewRouter.should_ascend(float(cam.get("target_zoom")), cam.zoom.x, float(cam.call("min_zoom"))):
		switch_to(ViewRouter.GLOBE)
		get_viewport().set_input_as_handled()
