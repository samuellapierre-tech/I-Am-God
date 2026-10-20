extends CanvasLayer
## Interface propre au globe : barre des calques (bas gauche, F1…F7), liste des lieux épinglés
## (P pour épingler, bouton pour la liste), bulle d'informations de la région cliquée.
## Les positions sont données dans la résolution de référence 1920×1080 (étirement canvas_items).

signal layer_pressed(index: int)
signal pin_requested
signal pin_go(index: int)
signal pin_remove(index: int)

const BAR := Rect2(12, 1016, 500, 52)
const PINS_PANEL := Rect2(12, 640, 320, 368)
const INFO_SIZE := Vector2(330, 0)

var _layer_buttons: Array[Button] = []
var _pins_button: Button
var _pins_panel: PanelContainer
var _pins_list: VBoxContainer
var _info: PanelContainer
var _info_label: Label
var _info_timer := 0.0
var _toast: Label
var _toast_timer := 0.0


func _ready() -> void:
	layer = 5


func build(layer_names: Array) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	add_child(root)

	var bar := PanelContainer.new()
	_place(bar, BAR, Vector2(0, 1))
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	bar.add_child(row)
	var group := ButtonGroup.new()
	for i in layer_names.size():
		var b := Button.new()
		b.text = String(layer_names[i])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Calque %s (F%d)" % [layer_names[i], i + 1]
		b.pressed.connect(func() -> void: layer_pressed.emit(i))
		row.add_child(b)
		_layer_buttons.append(b)
	_pins_button = Button.new()
	_pins_button.text = "Lieux"
	_pins_button.toggle_mode = true
	_pins_button.focus_mode = Control.FOCUS_NONE
	_pins_button.tooltip_text = "Lieux épinglés (P : épingler le centre de la vue)"
	_pins_button.toggled.connect(func(on: bool) -> void: _pins_panel.visible = on)
	row.add_child(_pins_button)

	_pins_panel = PanelContainer.new()
	_place(_pins_panel, PINS_PANEL, Vector2(0, 1))
	_pins_panel.visible = false
	root.add_child(_pins_panel)
	var box := VBoxContainer.new()
	_pins_panel.add_child(box)
	var title := Label.new()
	title.text = "Lieux épinglés"
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	box.add_child(title)
	var add := Button.new()
	add.text = "Épingler le centre de la vue (P)"
	add.focus_mode = Control.FOCUS_NONE
	add.pressed.connect(pin_requested.emit)
	box.add_child(add)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_pins_list = VBoxContainer.new()
	_pins_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_pins_list)

	_info = PanelContainer.new()
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.visible = false
	_info.custom_minimum_size = INFO_SIZE
	root.add_child(_info)
	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_size_override("font_size", 14)
	_info.add_child(_info_label)

	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_toast.position = Vector2(560, 900)
	_toast.size = Vector2(800, 40)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast)


func select_layer(index: int) -> void:
	for i in _layer_buttons.size():
		_layer_buttons[i].set_pressed_no_signal(i == index)


func set_pins(pins: Array[Dictionary]) -> void:
	for c in _pins_list.get_children():
		c.queue_free()
	if pins.is_empty():
		var l := Label.new()
		l.text = "Aucun lieu épinglé."
		l.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
		_pins_list.add_child(l)
	for i in pins.size():
		var r := HBoxContainer.new()
		var go := Button.new()
		go.text = String(pins[i].name)
		go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		go.alignment = HORIZONTAL_ALIGNMENT_LEFT
		go.clip_text = true
		go.focus_mode = Control.FOCUS_NONE
		go.tooltip_text = "Y aller"
		go.pressed.connect(func() -> void: pin_go.emit(i))
		r.add_child(go)
		var rm := Button.new()
		rm.text = "×"
		rm.focus_mode = Control.FOCUS_NONE
		rm.tooltip_text = "Retirer"
		rm.pressed.connect(func() -> void: pin_remove.emit(i))
		r.add_child(rm)
		_pins_list.add_child(r)


func show_info(text: String, at: Vector2) -> void:
	_info_label.text = text
	_info.visible = true
	_info.reset_size()
	var vp := Vector2(1920, 1080)
	if get_viewport() != null:
		vp = get_viewport().get_visible_rect().size
	var pos := at + Vector2(18, 18)
	var sz := _info.get_combined_minimum_size()
	pos.x = minf(pos.x, vp.x - sz.x - 12.0)
	pos.y = minf(pos.y, vp.y - sz.y - 90.0)
	_info.position = pos
	_info_timer = 7.0


func hide_info() -> void:
	if _info != null:
		_info.visible = false


func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast_timer = 2.5


func _process(delta: float) -> void:
	if _info_timer > 0.0:
		_info_timer -= delta
		if _info_timer <= 0.0:
			hide_info()
	if _toast_timer > 0.0:
		_toast_timer -= delta
		_toast.modulate.a = clampf(_toast_timer / 0.8, 0.0, 1.0)


func _place(c: Control, rect: Rect2, anchor: Vector2) -> void:
	# Ancré au coin `anchor` de l'écran (0/1 par axe), décalages relatifs à la résolution de référence.
	var ref := Vector2(1920, 1080)
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = rect.position.x - anchor.x * ref.x
	c.offset_right = rect.end.x - anchor.x * ref.x
	c.offset_top = rect.position.y - anchor.y * ref.y
	c.offset_bottom = rect.end.y - anchor.y * ref.y


func _theme() -> Theme:
	var t := Theme.new()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.04, 0.05, 0.09, 0.82)
	panel.border_color = Color(0.85, 0.7, 0.35, 0.35)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(8)
	panel.set_content_margin_all(8)
	t.set_stylebox("panel", "PanelContainer", panel)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.13, 0.2, 0.9)
	normal.set_corner_radius_all(6)
	normal.set_content_margin_all(5)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.2, 0.21, 0.32, 0.95)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.3, 0.24, 0.1, 0.95)
	pressed.border_color = Color(1.0, 0.8, 0.35)
	pressed.set_border_width_all(2)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_color("font_color", "Label", Color(0.9, 0.9, 0.95))
	t.set_color("font_color", "Button", Color(0.88, 0.88, 0.95))
	t.set_font_size("font_size", "Button", 13)
	return t
