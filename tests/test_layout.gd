extends RefCounted
## Tests du plan de l'écran (src/ui/layout.gd) : zones au repos sans chevauchement, interface
## au repos ≤ 30 % de l'écran, places réservées à la couche stratégie, ancrage.
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const Layout := preload("res://src/ui/layout.gd")

const SCREEN := Rect2(Vector2.ZERO, Layout.REF_SIZE)


func test_rest_zones_do_not_overlap() -> String:
	var clashes := Layout.overlaps(Layout.REST_ZONES)
	if not clashes.is_empty():
		return "zones qui se chevauchent au repos : %s" % str(clashes)
	for name in Layout.REST_ZONES:
		if not SCREEN.encloses(Layout.REST_ZONES[name]):
			return "zone hors de l'écran : %s" % name
	return ""


func test_rest_coverage_at_most_30_percent() -> String:
	var c := Layout.coverage(Layout.REST_ZONES.values())
	if c > Layout.MAX_REST_COVERAGE:
		return "l'interface au repos couvre %d %% de l'écran" % int(c * 100.0)
	return ""


func test_screen_centre_is_free() -> String:
	# Le cœur de la parcelle (un tiers central de l'écran) reste dégagé au repos.
	var centre := Rect2(Layout.REF_SIZE / 3.0, Layout.REF_SIZE / 3.0)
	for name in Layout.REST_ZONES:
		if (Layout.REST_ZONES[name] as Rect2).intersects(centre):
			return "le centre de l'écran est masqué par : %s" % name
	return ""


func test_strategy_reservations() -> String:
	if Layout.STRATEGY_THREATS.size.x < 240.0:
		return "les cartes de menace ont besoin de 240 px de large"
	var others := {stats = Layout.STATS, feed = Layout.FEED, dilemma = Layout.DILEMMA,
		power_hint = Layout.POWER_HINT, chronicle = Layout.CHRONICLE_DRAWER, top_bar = Layout.TOP_BAR}
	for zone in [Layout.STRATEGY_TRACKS, Layout.STRATEGY_THREATS]:
		for name in others:
			if (zone as Rect2).intersects(others[name]):
				return "zone stratégie chevauchant %s" % name
	if Layout.STATS_MAX_BOTTOM > Layout.CHRONICLE_DRAWER.position.y:
		return "les statistiques déborderaient sur le tiroir Chronique"
	return ""


func test_place_anchors_to_screen_edges() -> String:
	var c := Control.new()
	Layout.place(c, Rect2(1568, 596, 340, 400), Vector2(1, 1))
	var err := ""
	if c.anchor_left != 1.0 or c.anchor_bottom != 1.0:
		err = "ancres : %f %f" % [c.anchor_left, c.anchor_bottom]
	elif not is_equal_approx(c.offset_left, -352.0) or not is_equal_approx(c.offset_bottom, -84.0):
		err = "marges : %f %f" % [c.offset_left, c.offset_bottom]
	Layout.place(c, Rect2(500, 60, 920, 44), Vector2(0.5, 0))
	if err == "" and (not is_equal_approx(c.offset_left, -460.0) or not is_equal_approx(c.offset_right, 460.0)):
		err = "zone centrée : %f %f" % [c.offset_left, c.offset_right]
	c.free()
	return err
