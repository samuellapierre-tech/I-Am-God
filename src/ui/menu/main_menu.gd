extends CanvasLayer
## Menu sobre (docs/GENESE.md) :
## - au lancement : Continuer (dernière sauvegarde), Nouvelle planète, Panthéon ;
## - en jeu (bouton « Menu » dans le coin haut droit, ou F10) : Reprendre, Sauvegarder, Reprendre la dernière
##   sauvegarde, Panthéon, Renaître… (avec confirmation), Quitter ;
## - Panthéon : les espèces marquantes des mondes passés, consultables ; « Ressemer » pose l'espèce
##   choisie sur la parcelle comme semence façonnée ;
## - Fin des temps : un écran calme avec le bilan de la planète (Ézéchiel le raconte), « Contempler
##   encore » ou « Renaître ».
## Le monde est en pause tant qu'un écran est ouvert. Argument `-- --no-menu` : pas de menu au lancement.

const SaveStore := preload("res://src/save/save_store.gd")
const Layout := preload("res://src/ui/layout.gd")
const Pantheon := preload("res://src/save/pantheon.gd")

const GOLD := Color(1.0, 0.85, 0.5)
const TEXT := Color(0.92, 0.93, 0.96)
const DIM := Color(0.62, 0.66, 0.75)
const MENU_KEY := KEY_F10
const HOLD_KEY := "menu"

var _dim: ColorRect
var _start: Control
var _continue_btn: Button
var _continue_info: Label
var _ingame: Control
var _pantheon: Control
var _pantheon_list: ItemList
var _pantheon_detail: Label
var _reseed_btn: Button
var _pantheon_entries: Array = []
var _confirm: Control
var _end: Control
var _end_title: Label
var _end_text: Label
var _toast: Label
var _toast_timer := 0.0
var _menu_button: Button
var _in_game := false


func _ready() -> void:
	layer = 20
	_build()
	GameState.end_of_times.connect(_on_end_of_times)
	GameState.world_reborn.connect(_on_world_reborn)
	GameState.game_saved.connect(func(slot): _show_toast("Sauvegardé (%s)" % _slot_label(slot)))
	if "--no-menu" in OS.get_cmdline_user_args():
		_in_game = true
	else:
		_open(_start)


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		_toast.modulate.a = clampf(_toast_timer, 0.0, 1.0)
		_toast.visible = _toast_timer > 0.0


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.physical_keycode == MENU_KEY and _in_game:
		if _screen_open():
			_close_all()
		else:
			_open(_ingame)
		get_viewport().set_input_as_handled()


# =============================================================================================
# Construction
# =============================================================================================

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.03, 0.78)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	root.add_child(_dim)
	# Bouton discret dans le coin haut droit (zone Layout.MENU_BUTTON).
	_menu_button = Button.new()
	_menu_button.text = "Menu"
	_menu_button.tooltip_text = "Menu (F10) : sauvegarder, Panthéon, renaître"
	_menu_button.focus_mode = Control.FOCUS_NONE
	_menu_button.add_theme_font_size_override("font_size", 16)
	Layout.place(_menu_button, Layout.MENU_BUTTON, Vector2(1.0, 0.0))
	_menu_button.modulate.a = 0.75
	_menu_button.pressed.connect(func(): _open(_ingame))
	root.add_child(_menu_button)
	_build_start(root)
	_build_ingame(root)
	_build_pantheon(root)
	_build_confirm(root)
	_build_end(root)
	_toast = _label("", 18, GOLD)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.offset_top = 120
	_toast.offset_bottom = 150
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.visible = false
	root.add_child(_toast)


func _build_start(root: Control) -> void:
	var box := _box(root, Vector2(560, 470))
	_start = box.get_parent()
	box.add_child(_title("I AM GOD"))
	box.add_child(_label("Une planète t'attend.", 18, DIM, true, true))
	_continue_btn = _button("Continuer", _on_continue)
	box.add_child(_continue_btn)
	_continue_info = _label("", 15, DIM, true, true)
	box.add_child(_continue_info)
	box.add_child(_button("Nouvelle planète", _on_new_planet))
	box.add_child(_button("Panthéon", func(): _open_pantheon(false)))
	box.add_child(_button("Quitter", _on_quit))


func _build_ingame(root: Control) -> void:
	var box := _box(root, Vector2(520, 560))
	_ingame = box.get_parent()
	box.add_child(_title("Pause"))
	box.add_child(_button("Reprendre", _close_all))
	box.add_child(_button("Sauvegarder", func(): GameState.save_game("quick")))
	box.add_child(_button("Reprendre la dernière sauvegarde", _on_continue))
	box.add_child(_button("Panthéon", func(): _open_pantheon(true)))
	box.add_child(_button("Renaître…", func(): _open(_confirm)))
	box.add_child(_button("Quitter", _on_quit))


func _build_pantheon(root: Control) -> void:
	var box := _box(root, Vector2(1040, 700))
	_pantheon = box.get_parent()
	box.add_child(_title("Panthéon"))
	box.add_child(_label("Les espèces marquantes de tes mondes passés. Elles survivent à chaque réincarnation.", 16, DIM, true, true))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	_pantheon_list = ItemList.new()
	_pantheon_list.custom_minimum_size = Vector2(400, 0)
	_pantheon_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pantheon_list.add_theme_font_size_override("font_size", 17)
	_pantheon_list.item_selected.connect(_on_pantheon_selected)
	row.add_child(_pantheon_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	_pantheon_detail = _label("", 17, TEXT, true)
	_pantheon_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_pantheon_detail)
	_reseed_btn = _button("Ressemer sur la parcelle", _on_reseed)
	_reseed_btn.tooltip_text = "Pose cette espèce sur la parcelle suivie, comme une semence façonnée."
	right.add_child(_reseed_btn)
	box.add_child(_button("Fermer", _back_from_pantheon))


func _build_confirm(root: Control) -> void:
	var box := _box(root, Vector2(620, 330))
	_confirm = box.get_parent()
	box.add_child(_title("Renaître ?"))
	box.add_child(_label("Ce monde s'achève pour toi. Ses espèces marquantes rejoindront ton Panthéon, et tu renaîtras devant une planète vierge, différente.", 17, TEXT, true, true))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	row.add_child(_button("Renaître", _on_reincarnate))
	row.add_child(_button("Annuler", func(): _open(_ingame)))


func _build_end(root: Control) -> void:
	var box := _box(root, Vector2(760, 560))
	_end = box.get_parent()
	_end_title = _title("La fin des temps")
	box.add_child(_end_title)
	_end_text = _label("", 18, TEXT, true)
	_end_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_end_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	row.add_child(_button("Contempler encore", _close_all))
	row.add_child(_button("Renaître", _on_reincarnate))


# =============================================================================================
# Actions
# =============================================================================================

func _open(screen: Control) -> void:
	for s in [_start, _ingame, _pantheon, _confirm, _end]:
		s.visible = s == screen
	_dim.visible = true
	_menu_button.visible = false
	if screen == _start:
		_refresh_continue()
	# Le monde est suspendu tant qu'un écran est ouvert (sans toucher à la vitesse du HUD).
	GameState.hold_time(HOLD_KEY, true)


func _close_all() -> void:
	for s in [_start, _ingame, _pantheon, _confirm, _end]:
		s.visible = false
	_dim.visible = false
	_in_game = true
	_menu_button.visible = true
	GameState.hold_time(HOLD_KEY, false)


func _screen_open() -> bool:
	return _dim != null and _dim.visible


func _refresh_continue() -> void:
	var slots := SaveStore.list_slots(GameState.saver.dir if GameState.saver != null else SaveStore.DIR)
	_continue_btn.disabled = slots.is_empty()
	if slots.is_empty():
		_continue_info.text = "Aucune sauvegarde."
		return
	var m: Dictionary = slots[0].meta
	_continue_info.text = "%s — %s, %d espèces vivantes" % [m.get("world_name", "?"), m.get("era", ""), int(m.get("species_alive", 0))]


func _on_continue() -> void:
	var slots := SaveStore.list_slots(GameState.saver.dir)
	if slots.is_empty():
		return
	var err := GameState.load_game(String(slots[0].slot))
	if err != "":
		_show_toast("Sauvegarde illisible (%s)" % err)
		return
	_close_all()
	_show_toast("Reprise : %s" % GameState.world_name)


func _on_new_planet() -> void:
	_close_all()
	_show_toast("Planète %s" % GameState.world_name)


func _on_reincarnate() -> void:
	var info := GameState.reincarnate()
	_close_all()
	_show_toast("Tu renais devant %s — ta vie n° %d" % [info.world_name, info.world_index])


func _on_quit() -> void:
	if GameState.saver != null and GameState.saver.autosave:
		GameState.save_game(GameState.SaveService.AUTO_SLOT)
	get_tree().quit()


var _pantheon_from_game := false


func _open_pantheon(from_game: bool) -> void:
	_pantheon_from_game = from_game
	_pantheon_list.clear()
	_pantheon_entries = GameState.pantheon.entries.duplicate() if GameState.pantheon != null else []
	_pantheon_entries.reverse()  # les plus récentes d'abord
	for e in _pantheon_entries:
		_pantheon_list.add_item("%s%s — %s" % ["✦ " if e.sapient else "", e.name, e.world_name])
	_pantheon_detail.text = "Ton Panthéon est encore vide : il se remplit à chaque réincarnation." if _pantheon_entries.is_empty() \
		else "Choisis une espèce."
	_reseed_btn.disabled = true
	_reseed_btn.visible = from_game
	_open(_pantheon)


func _on_pantheon_selected(i: int) -> void:
	var e: Dictionary = _pantheon_entries[i]
	var reasons := {"conscience": "Elle s'éveilla à la conscience.", "création": "Tu l'as créée.", "règne": "Elle régna sur son monde."}
	_pantheon_detail.text = "%s\n\n%s\n\n%s\nMonde d'origine : %s (vie n° %d)" % [e.name, e.description,
		reasons.get(e.reason, ""), e.world_name, int(e.world_index)]
	_reseed_btn.disabled = false


func _on_reseed() -> void:
	var sel := _pantheon_list.get_selected_items()
	if sel.is_empty() or GameState.parcel == null:
		return
	var e: Dictionary = _pantheon_entries[sel[0]]
	GameState.reseed_from_pantheon(e, GameState.parcel.cell)
	_close_all()
	_show_toast("%s renaît sur la parcelle" % e.name)


func _back_from_pantheon() -> void:
	if _pantheon_from_game:
		_open(_ingame)
	elif not _in_game:
		_open(_start)
	else:
		_close_all()


func _on_end_of_times(summary: Dictionary) -> void:
	var names := []
	for n in summary.get("notable", []):
		names.append(n.name)
	_end_text.text = "%s s'achève.\n\n%d espèces sont nées sur ce monde ; %d se sont éteintes ; %d se sont éveillées à la conscience.\n\nTu te souviendras de : %s." % [
		summary.get("world_name", "Ce monde"), int(summary.get("species_total", 0)), int(summary.get("extinctions", 0)),
		int(summary.get("civilizations", 0)), ", ".join(names) if not names.is_empty() else "presque rien"]
	_open(_end)


func _on_world_reborn(_info: Dictionary) -> void:
	pass


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_timer = 3.0


static func _slot_label(slot: String) -> String:
	return {"auto": "automatique", "quick": "rapide"}.get(slot, slot)


# =============================================================================================
# Utilitaires
# =============================================================================================

func _box(root: Control, size: Vector2) -> VBoxContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.96)
	sb.border_color = Color(1.0, 0.85, 0.5, 0.3)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	p.add_theme_stylebox_override("panel", sb)
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = -size.x / 2.0
	p.offset_right = size.x / 2.0
	p.offset_top = -size.y / 2.0
	p.offset_bottom = size.y / 2.0
	p.visible = false
	root.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	p.add_child(box)
	return box


static func _title(text: String) -> Label:
	var l := _label(text, 34, GOLD, false, true)
	return l


static func _label(text: String, size: int, color: Color, wrap := false, center := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 50)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 20)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(cb)
	return b
