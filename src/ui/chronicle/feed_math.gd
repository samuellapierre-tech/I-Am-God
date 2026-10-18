extends RefCounted
## Fonctions pures du fil de narration : estompage des lignes, taille de l'historique, défilement.
## Testées par tests/test_dilemma_ui.gd.

## Lignes récentes qui restent visibles hors survol (la plus récente en bas).
const VISIBLE_LINES := 4
## Une ligne reste pleinement lisible HOLD secondes, puis s'estompe en FADE secondes…
const HOLD := 12.0
const FADE := 8.0
## … jusqu'à cette opacité (les lignes récentes ne disparaissent jamais tout à fait).
const MIN_RECENT := 0.35
## Atténuation par rang (0 = la plus récente).
const RANK_DIM := 0.18
const MAX_LINES := 200


## Opacité d'une ligne âgée de `age` secondes, de rang `rank` en partant du bas.
## Au survol, tout l'historique redevient lisible.
static func line_alpha(age: float, rank: int, hovered: bool) -> float:
	if hovered:
		return 1.0
	if rank < 0 or rank >= VISIBLE_LINES:
		return 0.0
	var fresh := 1.0 - smoothstep(HOLD, HOLD + FADE, maxf(age, 0.0))
	return lerpf(MIN_RECENT, 1.0, fresh) * (1.0 - RANK_DIM * rank)


## Nombre de lignes les plus anciennes à retirer pour rester sous `max_lines`.
static func overflow(count: int, max_lines: int = MAX_LINES) -> int:
	return maxi(0, count - maxi(max_lines, 1))


## Vrai si la vue est en bas (suivi automatique des nouvelles lignes).
static func is_at_bottom(value: float, max_value: float, page: float, tolerance: float = 8.0) -> bool:
	return value + page >= max_value - tolerance


## Ligne à afficher : texte nettoyé, espaces multiples réduits ; "" si rien à dire.
static func clean_line(text: String) -> String:
	var t := text.strip_edges().replace("\n", " ").replace("\t", " ")
	while t.contains("  "):
		t = t.replace("  ", " ")
	return t
