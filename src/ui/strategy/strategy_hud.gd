extends CanvasLayer
## Interface de la couche stratégique (docs/STRATEGIE.md) :
## - bande des pistes sous la barre du haut : manche, pastilles d'actions, effondrements x/N,
##   vitalité, 4 Grands Œuvres (bouton « sceller » quand la simulation les a atteints), pioche ;
## - colonne des cartes de menace en haut à droite (titre, cible, compte à rebours, contres,
##   état contrée/frappée ; menaces de la manche suivante pour le Prophète) ;
## - annonce de début de manche (avec le bilan de la précédente) ;
## - écran de lancement (aspect divin, difficulté) et écran de fin (victoire/défaite, raison).
## Lit GameState.strategy (contrat docs/ARCHITECTURE.md) ; n'invente aucune règle.
## Lancement sans écran de choix : argument utilisateur `--strategy-autostart`.

const Fmt := preload("res://src/ui/strategy/strategy_format.gd")
const Rules := preload("res://src/strategy/strategy_rules.gd")
const ThreatCard := preload("res://src/ui/strategy/threat_card.gd")
const Layout := preload("res://src/ui/layout.gd")

## Zones de l'écran de référence (src/ui/layout.gd) ; l'annonce de manche est transitoire.
const TRACKS_ZONE := Layout.STRATEGY_TRACKS
const THREATS_ZONE := Layout.STRATEGY_THREATS
const BANNER_ZONE := Rect2(610, 116, 700, 96)
const BANNER_TIME := 6.0
const REFRESH := 0.2

var _bound: RefCounted = null
var _tracks_panel: PanelContainer
var _pips: Label
var _collapses: Label
var _vitality_bar: ProgressBar
var _vitality_label: Label
var _work_buttons := {}
var _deck_label: Label
var _collection_label: Label
var _challenge_panel: PanelContainer
var _challenge_title: Label
var _challenge_text: Label
var _challenge_state: Label
var _mode_buttons := {}
var _mode_text: Label
var _chosen_mode := Rules.DEFAULT_MODE
var _threats_panel: PanelContainer
var _threats_header: Label
var _cards_box: VBoxContainer
var _next_box: VBoxContainer
var _next_header: Label
var _cards := {}
var _banner: PanelContainer
var _banner_title: Label
var _banner_text: Label
var _banner_timer := 0.0
var _launch: Control
var _aspect_buttons := {}
var _difficulty_buttons := {}
var _aspect_text: Label
var _difficulty_text: Label
var _end: Control
var _end_title: Label
var _end_text: Label
var _refresh_timer := 0.0
var _chosen_aspect := Rules.DEFAULT_ASPECT
var _chosen_difficulty := Rules.DEFAULT_DIFFICULTY


func _ready() -> void:
	layer = 11
	_build()
	GameState.round_started.connect(_on_round_started)
	GameState.threat_resolved.connect(func(_t, _c): _refresh())
	GameState.tracks_changed.connect(func(_t): _refresh())
	GameState.game_over.connect(_on_game_over)
	GameState.chapter_closed.connect(_on_chapter_closed)
	GameState.samael_move.connect(_on_samael_move)
	_bind()
	if "--strategy-autostart" in OS.get_cmdline_user_args():
		_launch.visible = false
	else:
		_open_launch()


func _process(delta: float) -> void:
	if GameState.strategy != _bound:
		_bind()
	if _launch.visible:
		GameState.paused = true  # le monde attend le choix de l'aspect
	_refresh_timer += delta
	if _refresh_timer >= REFRESH:
		_refresh()
	if _banner_timer > 0.0:
		_banner_timer -= delta
		_banner.modulate.a = clampf(_banner_timer / 1.0, 0.0, 1.0)
		_banner.visible = _banner_timer > 0.0


# =============================================================================================
# Construction
# =============================================================================================

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_tracks(root)
	_build_threats(root)
	_build_banner(root)
	_build_launch(root)
	_build_end(root)


func _build_tracks(root: Control) -> void:
	_tracks_panel = _panel(0.78)
	_place(_tracks_panel, TRACKS_ZONE, Vector2(0.5, 0.0))
	root.add_child(_tracks_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tracks_panel.add_child(row)
	_pips = _label("", 22, Fmt.GOLD)
	_pips.tooltip_text = "Actions divines restantes cette manche (un pouvoir = une action)"
	_pips.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_pips)
	_collapses = _label("", 17, Fmt.TEXT)
	_collapses.tooltip_text = "Effondrements en chaîne : une crise non contrée en provoque une autre. Au seuil, le monde échappe à Dieu."
	_collapses.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_collapses)
	var vit := HBoxContainer.new()
	vit.add_theme_constant_override("separation", 4)
	vit.tooltip_text = "Vitalité de la parcelle : biomasse, diversité, abondance. À zéro, la parcelle est morte."
	row.add_child(vit)
	vit.add_child(_label("Vitalité", 17, Fmt.TEXT))
	_vitality_bar = ProgressBar.new()
	_vitality_bar.custom_minimum_size = Vector2(56, 14)
	_vitality_bar.show_percentage = false
	_vitality_bar.max_value = 1.0
	_vitality_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_vitality_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vit.add_child(_vitality_bar)
	_vitality_label = _label("", 17, Fmt.TEXT)
	vit.add_child(_vitality_label)
	var works := HBoxContainer.new()
	works.add_theme_constant_override("separation", 3)
	row.add_child(works)
	for id in Rules.WORK_ORDER:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_on_seal.bind(id))
		works.add_child(b)
		_work_buttons[id] = b
	_deck_label = _label("", 17, Fmt.TEXT)
	_deck_label.tooltip_text = "Sablier cosmique : cartes restantes dans la pioche de menaces. Vide avant les quatre Grands Œuvres : défaite."
	_deck_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_deck_label)
	_collection_label = _label("", 17, Fmt.GOLD)
	_collection_label.tooltip_text = "Éternité : Grands Œuvres collectionnés depuis le début, sans limite (défis relevés compris)."
	_collection_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_collection_label)


func _build_threats(root: Control) -> void:
	_threats_panel = _panel(0.78)
	_place(_threats_panel, THREATS_ZONE, Vector2(1.0, 0.0))
	root.add_child(_threats_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_threats_panel.add_child(col)
	_threats_header = _label("Menaces", 17, Fmt.GOLD)
	_threats_header.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(_threats_header)
	# Éternité : le défi facultatif de Samaël, au-dessus des cartes.
	_challenge_panel = PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.14, 0.08, 0.18, 0.9)
	cs.border_color = Fmt.SAMAEL
	cs.border_width_left = 4
	cs.set_corner_radius_all(4)
	cs.content_margin_left = 8
	cs.content_margin_right = 6
	cs.content_margin_top = 4
	cs.content_margin_bottom = 5
	_challenge_panel.add_theme_stylebox_override("panel", cs)
	var ccol := VBoxContainer.new()
	ccol.add_theme_constant_override("separation", 1)
	_challenge_panel.add_child(ccol)
	_challenge_title = _label("", 15, Fmt.SAMAEL, true)
	ccol.add_child(_challenge_title)
	_challenge_text = _label("", 15, Fmt.TEXT, true)
	ccol.add_child(_challenge_text)
	_challenge_state = _label("", 14, Fmt.DIM, true)
	ccol.add_child(_challenge_state)
	_challenge_panel.visible = false
	col.add_child(_challenge_panel)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 6)
	scroll.add_child(inner)
	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 6)
	inner.add_child(_cards_box)
	_next_header = _label("Manche suivante (vision du Prophète)", 14, Fmt.DIM)
	_next_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(_next_header)
	_next_box = VBoxContainer.new()
	_next_box.add_theme_constant_override("separation", 6)
	_next_box.modulate = Color(1, 1, 1, 0.7)
	inner.add_child(_next_box)


func _build_banner(root: Control) -> void:
	_banner = _panel(0.88)
	_place(_banner, BANNER_ZONE, Vector2(0.5, 0.0))
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	root.add_child(_banner)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_banner.add_child(col)
	_banner_title = _label("", 24, Fmt.GOLD)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_banner_title)
	_banner_text = _label("", 16, Fmt.TEXT)
	_banner_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_banner_text)


func _build_launch(root: Control) -> void:
	_launch = _modal(root)
	var box := _modal_box(_launch, Vector2(880, 780))
	box.add_child(_title_label("Quel dieu seras-tu ?"))
	box.add_child(_label("Mode", 18, Fmt.GOLD))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 10)
	box.add_child(modes)
	var mgroup := ButtonGroup.new()
	for id in Rules.MODE_ORDER:
		var b := _toggle(String(Rules.MODES[id].label), mgroup)
		# Éternité, le mode par défaut, est mis en avant.
		b.custom_minimum_size = Vector2(500, 56) if id == Rules.DEFAULT_MODE else Vector2(330, 56)
		b.add_theme_font_size_override("font_size", 22 if id == Rules.DEFAULT_MODE else 18)
		if id == Rules.DEFAULT_MODE:
			b.add_theme_color_override("font_color", Fmt.GOLD)
			b.add_theme_color_override("font_pressed_color", Fmt.GOLD)
			b.text += " (recommandé)"
		b.pressed.connect(_choose_mode.bind(id))
		modes.add_child(b)
		_mode_buttons[id] = b
	_mode_text = _label("", 16, Fmt.TEXT, true)
	_mode_text.custom_minimum_size.y = 48
	box.add_child(_mode_text)
	box.add_child(_label("Aspect divin", 18, Fmt.GOLD))
	var aspects := GridContainer.new()
	aspects.columns = 4
	aspects.add_theme_constant_override("h_separation", 8)
	box.add_child(aspects)
	var group := ButtonGroup.new()
	for id in Rules.ASPECT_ORDER:
		var b := _toggle(Rules.aspect_label(id), group)
		b.custom_minimum_size = Vector2(196, 44)
		b.pressed.connect(_choose_aspect.bind(id))
		aspects.add_child(b)
		_aspect_buttons[id] = b
	_aspect_text = _label("", 16, Fmt.TEXT, true)
	_aspect_text.custom_minimum_size.y = 48
	box.add_child(_aspect_text)
	box.add_child(_label("Difficulté", 18, Fmt.GOLD))
	var diffs := HBoxContainer.new()
	diffs.add_theme_constant_override("separation", 8)
	box.add_child(diffs)
	var dgroup := ButtonGroup.new()
	for id in Rules.DIFFICULTY_ORDER:
		var b := _toggle(String(Rules.DIFFICULTIES[id].label), dgroup)
		b.custom_minimum_size = Vector2(200, 44)
		b.pressed.connect(_choose_difficulty.bind(id))
		diffs.add_child(b)
		_difficulty_buttons[id] = b
	_difficulty_text = _label("", 16, Fmt.TEXT, true)
	box.add_child(_difficulty_text)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var start := Button.new()
	start.text = "Que la lumière soit"
	start.custom_minimum_size = Vector2(280, 52)
	start.add_theme_font_size_override("font_size", 20)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.pressed.connect(_on_launch)
	box.add_child(start)


func _build_end(root: Control) -> void:
	_end = _modal(root)
	_end.visible = false
	var box := _modal_box(_end, Vector2(720, 380))
	_end_title = _title_label("")
	box.add_child(_end_title)
	_end_text = _label("", 18, Fmt.TEXT, true)
	_end_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_end_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var watch := Button.new()
	watch.text = "Contempler le monde"
	watch.custom_minimum_size = Vector2(240, 48)
	watch.add_theme_font_size_override("font_size", 18)
	watch.pressed.connect(_on_watch)
	row.add_child(watch)
	var again := Button.new()
	again.text = "Nouvelle partie"
	again.custom_minimum_size = Vector2(240, 48)
	again.add_theme_font_size_override("font_size", 18)
	again.pressed.connect(_on_new_game)
	row.add_child(again)


# =============================================================================================
# Mise à jour
# =============================================================================================

## Se branche sur l'instance de stratégie courante (recréée à chaque partie / choix d'aspect).
func _bind() -> void:
	if _bound != null and is_instance_valid(_bound) and _bound.action_refused.is_connected(_on_refused):
		_bound.action_refused.disconnect(_on_refused)
	_bound = GameState.strategy
	if _bound != null:
		_bound.action_refused.connect(_on_refused)
	_rebuild_cards()


func _refresh() -> void:
	_refresh_timer = 0.0
	var st: RefCounted = GameState.strategy
	var visible_ui := st != null
	_tracks_panel.visible = visible_ui
	_threats_panel.visible = visible_ui
	if st == null:
		return
	var tr: Dictionary = st.tracks
	var calm: bool = st.mode == "eternity"
	_collection_label.visible = calm
	_collection_label.text = "Collection %d" % int(tr.get("collected", 0))
	_challenge_panel.visible = calm and not st.challenge.is_empty()
	if _challenge_panel.visible:
		var lines: Array = Fmt.challenge_lines(st.challenge)
		_challenge_title.text = lines[0]
		_challenge_text.text = lines[1]
		_challenge_state.text = lines[2]
	_pips.text = Fmt.pips(st.actions_left, st.actions_per_round)
	_pips.add_theme_color_override("font_color", Fmt.GOLD if st.actions_left > 0 else Fmt.DIM)
	_collapses.text = "Effondrements %d/%d" % [tr.collapses, tr.collapse_limit]
	_collapses.add_theme_color_override("font_color",
		Fmt.DANGER if int(tr.collapses) >= int(tr.collapse_limit) - 2 and not calm else Fmt.TEXT)
	_vitality_bar.value = float(tr.vitality)
	_vitality_label.text = "%d %%" % int(round(float(tr.vitality) * 100.0))
	_vitality_bar.modulate = Fmt.DANGER if float(tr.vitality) < 0.2 and not calm else Fmt.SAFE
	for id in Rules.WORK_ORDER:
		var b: Button = _work_buttons[id]
		var sealed: bool = tr.works[id]
		var ready: bool = st.works_ready.get(id, false)
		var label: String = Fmt.WORK_SHORT[id]
		b.text = ("✔ " + label) if sealed else (("★ " + label) if ready else label)
		b.disabled = sealed or not ready or st.actions_left < Rules.SEAL_COST or st.over
		b.modulate = Fmt.GOLD if sealed else (Color.WHITE if ready else Fmt.DIM)
		b.tooltip_text = "%s — %s\n%s" % [Rules.WORKS[id].label, Rules.WORKS[id].text,
			"Scellé." if sealed else ("★ Atteint : clique pour sceller (%d actions)." % Rules.SEAL_COST if ready else "Pas encore atteint dans la simulation.")]
	_deck_label.text = "Pioche %d" % int(tr.deck_left)
	_deck_label.add_theme_color_override("font_color", Fmt.DANGER if int(tr.deck_left) <= 10 and not calm else Fmt.TEXT)
	_threats_header.text = "%s · intensité %d" % [st.round.get("name", ""), st.current_intensity()]
	_threats_header.tooltip_text = Fmt.round_title(st.round)
	var now: float = GameState.sim.year if GameState.sim != null else 0.0
	for id in _cards:
		_cards[id].refresh(now)
	if _cards.size() != st.round.get("threats", []).size() + st.visible_next_threats().size():
		_rebuild_cards()


func _rebuild_cards() -> void:
	_cards.clear()
	for box in [_cards_box, _next_box]:
		for c in box.get_children():
			c.queue_free()
	var st: RefCounted = GameState.strategy
	if st == null:
		return
	for t in st.round.get("threats", []):
		_add_card(_cards_box, t)
	var next: Array = st.visible_next_threats()
	for t in next:
		_add_card(_next_box, t)
	_next_header.visible = not next.is_empty()


func _add_card(box: VBoxContainer, t: Dictionary) -> void:
	var card := ThreatCard.new()
	card.threat = t
	card.counter_chosen.connect(_on_counter_chosen)
	box.add_child(card)
	_cards[t.id] = card


func _on_round_started(r: Dictionary) -> void:
	_rebuild_cards()
	_refresh()
	var n: int = r.get("threats", []).size()
	var st: RefCounted = GameState.strategy
	var recap := String(r.get("recap", ""))
	if recap != "" and not recap.ends_with("."):
		recap += "."
	var body := "%d menace%s révélée%s. %d actions." % [n, "s" if n > 1 else "", "s" if n > 1 else "", st.actions_left]
	if st.mode == "eternity":
		body = "%d événement%s à venir. %d actions, rien ne presse." % [n, "s" if n > 1 else "", st.actions_left]
	_show_banner("%s — %s" % [r.get("name", ""), r.get("stage", "")], (recap + " " if recap != "" else "") + body)


## Éternité : une « défaite » ferme doucement le chapitre ; le monde continue.
func _on_chapter_closed(c: Dictionary) -> void:
	_show_banner("Fin du chapitre %d" % int(c.get("index", 0)), String(c.get("reason", "")))


func _on_samael_move(m: Dictionary) -> void:
	var c: Dictionary = m.get("challenge", {})
	match String(m.get("kind", "")):
		"challenge":
			_refresh()
		"challenge_won":
			_show_banner("Défi relevé", "%s — %s" % [c.get("title", ""), c.get("reward_text", "")])
		"challenge_lost":
			_show_banner("Défi manqué", "%s — sans conséquence. Samaël sourit." % c.get("title", ""))


func _show_banner(title: String, text: String) -> void:
	_banner_title.text = title
	_banner_text.text = text
	_banner.visible = true
	_banner.modulate.a = 1.0
	_banner_timer = BANNER_TIME


func _on_refused(kind: String) -> void:
	var st: RefCounted = GameState.strategy
	if st != null and st.over:
		return
	_show_banner("Plus d'action cette manche", "%s refusé : attends la manche suivante." % Rules.power_label(kind))
	_banner_timer = 2.5


func _on_seal(id: String) -> void:
	var st: RefCounted = GameState.strategy
	if st != null and st.seal_work(id):
		_show_banner("Grand Œuvre scellé", String(Rules.WORKS[id].label))
	_refresh()


## Un contre cliqué sur une carte arme ce pouvoir (il reste à cliquer sur la parcelle).
func _on_counter_chosen(power: String) -> void:
	var powers := get_parent().get_node_or_null("ParcelPowers")
	if powers != null and powers.has_method("set_power"):
		powers.set_power(power)


func _on_game_over(victory: bool, reason: String) -> void:
	_refresh()
	var st: RefCounted = GameState.strategy
	_end_title.text = "Victoire" if victory else "Défaite"
	_end_title.add_theme_color_override("font_color", Fmt.GOLD if victory else Fmt.DANGER)
	var sealed := []
	for id in Rules.WORK_ORDER:
		if st != null and st.tracks.works[id]:
			sealed.append(Rules.WORKS[id].label)
	_end_text.text = "%s\n\n%s · %s · %s\nGrands Œuvres : %s" % [reason,
		st.round.get("name", "") if st != null else "", Rules.aspect_label(GameState.strategy_aspect),
		Rules.difficulty(GameState.strategy_difficulty).label,
		", ".join(sealed) if not sealed.is_empty() else "aucun"]
	_end.visible = true
	GameState.paused = true


# =============================================================================================
# Lancement
# =============================================================================================

func _open_launch() -> void:
	_chosen_aspect = GameState.strategy_aspect
	_chosen_difficulty = GameState.strategy_difficulty
	_chosen_mode = GameState.strategy_mode
	_mode_buttons[_chosen_mode].button_pressed = true
	_aspect_buttons[_chosen_aspect].button_pressed = true
	_difficulty_buttons[_chosen_difficulty].button_pressed = true
	_refresh_launch()
	_launch.visible = true
	GameState.paused = true


func _choose_aspect(id: String) -> void:
	_chosen_aspect = id
	_refresh_launch()


func _choose_mode(id: String) -> void:
	_chosen_mode = id
	_refresh_launch()


func _choose_difficulty(id: String) -> void:
	_chosen_difficulty = id
	_refresh_launch()


func _on_watch() -> void:
	_end.visible = false
	GameState.paused = false


func _refresh_launch() -> void:
	_aspect_text.text = String(Rules.ASPECTS[_chosen_aspect].text)
	_mode_text.text = Fmt.mode_text(_chosen_mode)
	var diff := Fmt.difficulty_text(_chosen_difficulty)
	if _chosen_mode == "eternity":
		# En Éternité, Samaël est un rival doux quelle que soit la difficulté.
		diff = diff.get_slice("\n", 0).replace(" · défaite à", " · chapitre clos à").replace("par manche", "par chapitre") + "\nSamaël, rival doux, propose des défis facultatifs."
	_difficulty_text.text = diff


func _on_launch() -> void:
	GameState.configure_strategy(_chosen_aspect, _chosen_difficulty, _chosen_mode)
	_launch.visible = false
	GameState.paused = false
	_bind()
	_on_round_started(GameState.strategy.round)


func _on_new_game() -> void:
	_end.visible = false
	GameState.new_world(randi())
	_bind()
	_open_launch()


# =============================================================================================
# Utilitaires
# =============================================================================================

static func _place(c: Control, zone: Rect2, anchor: Vector2) -> void:
	Layout.place(c, zone, anchor)


static func _panel(alpha: float) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, alpha)
	sb.border_color = Color(1.0, 0.85, 0.5, 0.25)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	return p


static func _label(text: String, size: int, color: Color, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func _title_label(text: String) -> Label:
	var l := _label(text, 32, Fmt.GOLD)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func _toggle(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	return b


## Fond assombri plein écran qui bloque la souris (écrans de lancement et de fin).
static func _modal(root: Control) -> Control:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	return dim


static func _modal_box(parent: Control, size: Vector2) -> VBoxContainer:
	var p := _panel(0.95)
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = -size.x / 2.0
	p.offset_right = size.x / 2.0
	p.offset_top = -size.y / 2.0
	p.offset_bottom = size.y / 2.0
	parent.add_child(p)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	p.add_child(box)
	return box
