extends RefCounted
## Plan de l'écran : zones réservées à chaque élément d'interface, dans la résolution de référence
## 1920×1080 (le projet étire « canvas_items » : 1280×800 sur Steam Deck garde ces proportions).
## Seule source de vérité de la disposition : chaque scène d'interface se place avec place().
## Testé par tests/test_layout.gd (pas de chevauchement au repos, ≤ 30 % de l'écran couvert).
##
##   ┌──────────┬──────── TOP_BAR ────────┬─────────────────┐
##   │  STATS   │   STRATEGY_TRACKS       │ STRATEGY_THREATS│  (SPECIES_DRAWER s'ouvre par-dessus)
##   │ (S)      │                         │  240 px         │
##   │          │       la parcelle       │                 │
##   ├──────────┤                         ├─────────────────┤
##   │CHRONICLE │                         │      FEED       │
##   │(tiroir C)│  (DILEMMA au centre-bas)│  fil d'Ézéchiel │
##   └──────────┴────── POWER_BAR ────────┴─────────────────┘

const REF_SIZE := Vector2(1920, 1080)

## Fine barre du haut (hud.gd) : année, ère, vitesse, tiroirs. Centrée, largeur selon le contenu.
const TOP_BAR := Rect2(500, 8, 920, 46)
## Couche stratégie (scenes/strategy_hud.tscn) : pistes (effondrements x/8, vitalité, 4 Grands
## Œuvres, pioche) et pastilles d'actions restantes, en bande sous la barre du haut.
const STRATEGY_TRACKS := Rect2(500, 60, 920, 44)
## Couche stratégie : cartes de menace de la manche, colonne de 240 px en haut à droite.
const STRATEGY_THREATS := Rect2(1668, 12, 240, 480)
## Statistiques de la parcelle (src/ui/stats/), repliables avec S. Hauteur avec 6 espèces ; elle
## peut atteindre STATS_MAX_BOTTOM le temps qu'une espèce disparue s'efface.
const STATS := Rect2(12, 12, 360, 560)
const STATS_MAX_BOTTOM := 652.0
## Fil de narration d'Ézéchiel (src/ui/chronicle/).
const FEED := Rect2(1568, 596, 340, 400)
## Barre des pouvoirs compacte (hud.gd), centrée en bas ; l'indication de rayon flotte au-dessus.
const POWER_BAR := Rect2(520, 1012, 880, 60)
const POWER_HINT := Rect2(520, 960, 880, 40)
## Dilemme d'Ézéchiel (src/ui/dilemma/), centre-bas, au-dessus de l'indication de pouvoir.
const DILEMMA := Rect2(540, 600, 840, 340)
## Tiroirs fermés par défaut (hud.gd), ouverts par-dessus le reste.
const CHRONICLE_DRAWER := Rect2(12, 664, 500, 332)
const SPECIES_DRAWER := Rect2(1588, 64, 320, 476)

## Zones visibles au repos (tiroirs fermés, pas de dilemme, pas de pouvoir armé).
const REST_ZONES := {
	top_bar = TOP_BAR, strategy_tracks = STRATEGY_TRACKS, strategy_threats = STRATEGY_THREATS,
	stats = STATS, feed = FEED, power_bar = POWER_BAR,
}
const MAX_REST_COVERAGE := 0.30


## Place `c` sur la zone `zone`, ancré au point `anchor` de l'écran (0 = gauche/haut, 0,5 = centre,
## 1 = droite/bas) : si la taille réelle de l'écran diffère de la référence, la zone suit son bord.
static func place(c: Control, zone: Rect2, anchor: Vector2) -> void:
	var origin := REF_SIZE * anchor
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = zone.position.x - origin.x
	c.offset_top = zone.position.y - origin.y
	c.offset_right = zone.end.x - origin.x
	c.offset_bottom = zone.end.y - origin.y


## Part de l'écran couverte par des zones (les chevauchements comptent deux fois : borne haute).
static func coverage(zones: Array) -> float:
	var area := 0.0
	for z in zones:
		area += (z as Rect2).get_area()
	return area / (REF_SIZE.x * REF_SIZE.y)


## Paires de zones qui se chevauchent : [[nom_a, nom_b], …].
static func overlaps(zones: Dictionary) -> Array:
	var out := []
	var names := zones.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			if (zones[names[i]] as Rect2).intersects(zones[names[j]]):
				out.append([names[i], names[j]])
	return out
