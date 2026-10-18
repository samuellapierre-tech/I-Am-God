extends RefCounted
## Tests de l'interface du Narrateur maître du jeu : validation des dilemmes, barre de temps,
## ralentissement puis restauration exacte de la vitesse, estompage du fil de narration.
## Chaque test renvoie "" en cas de succès, sinon un message d'erreur.

const DilemmaMath := preload("res://src/ui/dilemma/dilemma_math.gd")
const TimeDilation := preload("res://src/ui/dilemma/time_dilation.gd")
const FeedMath := preload("res://src/ui/chronicle/feed_math.gd")


func _expect(got, want, what: String) -> String:
	if got != want:
		return "%s : obtenu %s, attendu %s" % [what, str(got), str(want)]
	return ""


func _near(got: float, want: float, what: String, eps: float = 1e-4) -> String:
	if absf(got - want) > eps:
		return "%s : obtenu %f, attendu %f" % [what, got, want]
	return ""


func _first_error(errors: Array) -> String:
	for e in errors:
		if e != "":
			return e
	return ""


func _sample() -> Dictionary:
	return {
		id = 7, title = "Le feu des Aviens", text = "Les Aviens ont découvert le feu. Que faites-vous ?",
		options = [
			{label = "Bénir le feu", hint = "La tribu prospère", action = {type = "bless"}},
			{label = "Éteindre", hint = "Pluie divine", action = {type = "flood"}},
			{label = "Laisser faire", hint = "", action = {}},
		],
		timeout_s = 20,
	}


## Validation après normalisation, comme le fait le panneau.
func _check(raw: Variant) -> String:
	return DilemmaMath.validate(DilemmaMath.normalize(raw))


func test_valid_dilemma() -> String:
	var d := DilemmaMath.normalize(_sample())
	return _first_error([
		_expect(DilemmaMath.validate(d), "", "dilemme valide"),
		_expect(d.title, "Le feu des Aviens", "titre"),
		_expect(d.options.size(), 3, "options"),
		_expect(d.options[0].label, "Bénir le feu", "libellé"),
		_expect(d.options[2].hint, "", "indication facultative"),
		_near(d.timeout_s, 20.0, "délai"),
		_expect(d.default_index, -1, "pas d'option par défaut"),
	])


func test_dilemma_defaults() -> String:
	var raw := _sample()
	raw.erase("title")
	raw.erase("timeout_s")
	var d := DilemmaMath.normalize(raw)
	var err := _first_error([
		_expect(d.title, DilemmaMath.DEFAULT_TITLE, "titre par défaut"),
		_near(d.timeout_s, DilemmaMath.DEFAULT_TIMEOUT, "délai par défaut"),
		_expect(DilemmaMath.validate(d), "", "valide sans titre ni délai"),
	])
	if err != "":
		return err
	for pair in [[1, DilemmaMath.MIN_TIMEOUT], [9999.0, DilemmaMath.MAX_TIMEOUT], ["vite", DilemmaMath.DEFAULT_TIMEOUT],
			[-4, DilemmaMath.DEFAULT_TIMEOUT]]:
		raw.timeout_s = pair[0]
		err = _near(DilemmaMath.normalize(raw).timeout_s, pair[1], "délai %s" % str(pair[0]))
		if err != "":
			return err
	return ""


func test_invalid_dilemmas() -> String:
	if _check(42) == "" or _check(null) == "":
		return "un dilemme qui n'est pas un dictionnaire devrait être refusé"
	var no_id := _sample()
	no_id.erase("id")
	var empty_id := _sample()
	empty_id.id = ""
	var no_text := _sample()
	no_text.text = "   "
	var one_option := _sample()
	one_option.options = [{label = "Seul choix"}]
	var unlabeled := _sample()
	unlabeled.options = [{label = "Oui"}, {hint = "sans libellé"}]
	var bad_options := _sample()
	bad_options.options = "oui/non"
	for case in [[no_id, "sans id"], [empty_id, "id vide"], [no_text, "texte vide"],
			[one_option, "une seule option"], [unlabeled, "option sans libellé"], [bad_options, "options non listées"]]:
		if _check(case[0]) == "":
			return "dilemme accepté à tort : " + case[1]
	return ""


func test_options_are_limited_and_flexible() -> String:
	var many := _sample()
	many.options = [{label = "A"}, {label = "B"}, {label = "C"}, {label = "D"}, {label = "E"}]
	var d := DilemmaMath.normalize(many)
	var strings := _sample()
	strings.options = ["Oui", "Non"]
	var s := DilemmaMath.normalize(strings)
	return _first_error([
		_expect(d.options.size(), DilemmaMath.MAX_OPTIONS, "au plus 4 options"),
		_expect(DilemmaMath.validate(d), "", "5 options tronquées restent valides"),
		_expect(DilemmaMath.validate(s), "", "options données comme simples textes"),
		_expect(s.options[1].label, "Non", "libellé texte"),
		_expect(DilemmaMath.validate(DilemmaMath.normalize({id = "crise-3", text = "?", options = ["a", "b"]})), "",
			"identifiant texte"),
	])


func test_default_index() -> String:
	var raw := _sample()
	raw.default_index = 1
	var kept: int = DilemmaMath.normalize(raw).default_index
	raw.default_index = 5
	var out_of_range: int = DilemmaMath.normalize(raw).default_index
	raw.default_index = "deux"
	var wrong_type: int = DilemmaMath.normalize(raw).default_index
	return _first_error([
		_expect(kept, 1, "option par défaut"),
		_expect(out_of_range, -1, "option par défaut hors bornes"),
		_expect(wrong_type, -1, "option par défaut mal typée"),
	])


func test_time_bar() -> String:
	return _first_error([
		_near(DilemmaMath.time_ratio(15.0, 30.0), 0.5, "moitié"),
		_near(DilemmaMath.time_ratio(-1.0, 30.0), 0.0, "écoulé"),
		_near(DilemmaMath.time_ratio(40.0, 30.0), 1.0, "plein"),
		_near(DilemmaMath.time_ratio(5.0, 0.0), 0.0, "délai nul"),
		_near(DilemmaMath.tick(10.0, 0.5, false), 9.5, "décompte"),
		_near(DilemmaMath.tick(10.0, 0.5, true), 10.0, "figé en pause"),
		_near(DilemmaMath.tick(0.2, 1.0, false), 0.0, "jamais négatif"),
		_near(DilemmaMath.tick(3.0, -1.0, false), 3.0, "delta négatif ignoré"),
		_expect(DilemmaMath.time_color(1.0), Color(1.0, 0.82, 0.4), "or quand il reste du temps"),
		_expect(DilemmaMath.time_color(0.2), Color(1.0, 0.55, 0.2), "orange à 20 %"),
		"" if DilemmaMath.time_color(0.0).g < 0.3 else "rouge quand le temps est écoulé",
		_expect(DilemmaMath.format_remaining(12.2), "13 s", "secondes arrondies au-dessus"),
		_expect(DilemmaMath.format_remaining(0.0), "0 s", "zéro"),
		_expect(DilemmaMath.format_remaining(65.0), "1 min 05", "minutes"),
	])


func test_typewriter_and_keys() -> String:
	return _first_error([
		_expect(DilemmaMath.visible_chars(0.0, 100), 0, "début"),
		_expect(DilemmaMath.visible_chars(1.0, 100, 55.0), 55, "une seconde"),
		_expect(DilemmaMath.visible_chars(10.0, 100), 100, "texte complet"),
		_expect(DilemmaMath.visible_chars(1.0, 100, 0.0), 100, "vitesse nulle : tout de suite"),
		_expect(DilemmaMath.can_choose(0.1), false, "trop tôt pour choisir"),
		_expect(DilemmaMath.can_choose(DilemmaMath.ARM_DELAY), true, "choix armé"),
		_expect(DilemmaMath.key_to_option(KEY_1, 3), 0, "touche 1"),
		_expect(DilemmaMath.key_to_option(KEY_KP_4, 4), 3, "pavé numérique 4"),
		_expect(DilemmaMath.key_to_option(KEY_4, 3), -1, "option inexistante"),
		_expect(DilemmaMath.key_to_option(KEY_A, 4), -1, "autre touche"),
	])


func test_time_dilation_restores_exactly() -> String:
	var t := TimeDilation.new(25.0)
	var slowed := t.begin(1_000_000.0)
	var err := _first_error([
		_near(slowed, 40_000.0, "ralenti x25"),
		_near(t.step(slowed), 40_000.0, "stable d'une image à l'autre"),
	])
	if err != "":
		return err
	var restored := t.end(slowed)
	if restored != 1_000_000.0:
		return "vitesse restaurée inexacte : %f" % restored
	# Valeur « difficile » : la restauration ne passe pas par une multiplication.
	var odd := 123_456.789
	var t2 := TimeDilation.new(25.0)
	if t2.end(t2.step(t2.begin(odd))) != odd:
		return "restauration inexacte pour %f" % odd
	if t.active or t2.active:
		return "le ralentissement devrait être terminé"
	return _expect(t.end(500.0), 500.0, "fin sans début : vitesse inchangée")


func test_time_dilation_follows_hud_speed_changes() -> String:
	# Le HUD réécrit la vitesse de base à chaque image (x1..x5) : on suit la nouvelle base.
	var t := TimeDilation.new(25.0)
	var rate := t.begin(1_000_000.0)
	rate = t.step(1_000_000.0)  # le HUD a réécrit la même base : ralentie à nouveau
	var err := _near(rate, 40_000.0, "base réécrite à l'identique")
	if err != "":
		return err
	rate = t.step(2_000_000.0)  # le joueur passe en x2 pendant le dilemme
	err = _near(rate, 80_000.0, "nouvelle base ralentie")
	if err != "":
		return err
	if t.end(rate) != 2_000_000.0:
		return "la nouvelle base devrait être restaurée"
	# Quelqu'un change la vitesse juste avant la fin : sa valeur l'emporte.
	var t2 := TimeDilation.new(25.0)
	t2.begin(1_000_000.0)
	err = _expect(t2.end(3_000_000.0), 3_000_000.0, "changement extérieur conservé")
	if err != "":
		return err
	# Deux débuts de suite (file de dilemmes) : la base d'origine n'est pas perdue.
	var t3 := TimeDilation.new(25.0)
	var r3 := t3.begin(1_000_000.0)
	r3 = t3.begin(r3)
	if t3.end(r3) != 1_000_000.0:
		return "double début : base perdue"
	return _near(TimeDilation.new(0.1).begin(10.0), 10.0, "facteur < 1 ramené à 1")


func test_feed_fading() -> String:
	var a5 := FeedMath.line_alpha(5.0, 0, false)
	var a15 := FeedMath.line_alpha(15.0, 0, false)
	var a25 := FeedMath.line_alpha(25.0, 0, false)
	if not (a5 >= a15 and a15 >= a25):
		return "l'opacité devrait décroître avec l'âge : %f %f %f" % [a5, a15, a25]
	return _first_error([
		_near(FeedMath.line_alpha(0.0, 0, false), 1.0, "ligne neuve"),
		_near(FeedMath.line_alpha(100.0, 0, false), FeedMath.MIN_RECENT, "ligne récente estompée mais visible"),
		_near(FeedMath.line_alpha(0.0, 1, false), 1.0 - FeedMath.RANK_DIM, "deuxième ligne"),
		_near(FeedMath.line_alpha(0.0, FeedMath.VISIBLE_LINES, false), 0.0, "ancienne ligne cachée"),
		_near(FeedMath.line_alpha(100.0, 50, true), 1.0, "tout l'historique au survol"),
		_expect(FeedMath.overflow(250), 50, "historique borné"),
		_expect(FeedMath.overflow(10), 0, "historique court"),
		_expect(FeedMath.is_at_bottom(900.0, 1000.0, 100.0), true, "en bas"),
		_expect(FeedMath.is_at_bottom(500.0, 1000.0, 100.0), false, "remonté dans l'historique"),
		_expect(FeedMath.clean_line("  Les Aviens\n  prient.  "), "Les Aviens prient.", "texte nettoyé"),
		_expect(FeedMath.clean_line(" \n "), "", "texte vide"),
		_expect(FeedMath.is_clipped(120.0, 150.0), true, "ligne rognée par le haut"),
		_expect(FeedMath.is_clipped(150.0, 150.0), false, "ligne pile en haut de la vue"),
		_expect(FeedMath.is_clipped(400.0, 150.0), false, "ligne entièrement visible"),
		_near(FeedMath.header_y(100.0, 400.0, 26.0, false), 370.0, "en-tête posé sur les lignes"),
		_near(FeedMath.header_y(100.0, 400.0, 26.0, true), 100.0, "en-tête en haut au survol"),
		_near(FeedMath.header_y(100.0, 110.0, 26.0, false), 100.0, "en-tête jamais hors du panneau"),
		_near(FeedMath.header_y(100.0, INF, 26.0, false), 100.0, "aucune ligne"),
	])


func test_speaker_name() -> String:
	var raw := _sample()
	raw.speaker = "  Ézéchiel le Prophète "
	var signed: String = DilemmaMath.normalize(raw).speaker
	var unsigned: String = DilemmaMath.normalize(_sample()).speaker
	return _first_error([
		_expect(signed, "Ézéchiel le Prophète", "speaker du dilemme"),
		_expect(unsigned, "", "dilemme sans speaker"),
		_expect(DilemmaMath.speaker_name(signed, {NARRATOR_NAME = "Autre"}), "Ézéchiel le Prophète",
			"le dilemme l'emporte sur ai_config"),
		_expect(DilemmaMath.speaker_name("", {NARRATOR_NAME = "Nom de config"}), "Nom de config",
			"repli sur NARRATOR_NAME"),
		_expect(DilemmaMath.speaker_name(null, {}), DilemmaMath.DEFAULT_SPEAKER, "nom par défaut"),
		_expect(DilemmaMath.DEFAULT_SPEAKER, "Ézéchiel", "le narrateur s'appelle Ézéchiel"),
		_expect(DilemmaMath.signature("Ézéchiel"), "— Ézéchiel", "signature"),
		"" if DilemmaMath.load_config_constants() is Dictionary else "constantes de ai_config illisibles",
	])
