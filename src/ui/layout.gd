extends RefCounted
## Plan de l'écran : zones réservées à chaque élément d'interface, dans la résolution de référence
## 1920×1080 (le projet étire « canvas_items » : 1280×800 sur Steam Deck garde ces proportions).
## Seule source de vérité de la disposition : chaque scène d'interface se place avec place().
## Testé par tests/test_layout.gd (pas de chevauchement au repos, ≤ 30 % de l'écran couvert).
##
## Interface calme (docs/GENESE.md) : au repos, seulement la barre du haut, les statistiques de la
## parcelle (repliables, S), le fil d'Ézéchiel et la barre d'outils. Le reste s'ouvre à la demande.
##
##   ┌──────────┬──────── TOP_BAR ────────┬─────────────────┐
##   │  STATS   │                         │  WORLD_DRAWER   │ (Monde : planète + espèces, E)
##   │ (S)      │   TREE (arbre, T)       │                 │
##   │          │   s'ouvre au centre     ├─────────────────┤
##   ├──────────┤                         │      FEED       │
##   │CHRONICLE │      TOOL_EDITOR        │  fil d'Ézéchiel │
##   │(tiroir C)│       TOOL_BAR          │                 │
##   └──────────┴─────────────────────────┴─────────────────┘

const REF_SIZE := Vector2(1920, 1080)

## Fine barre du haut (hud.gd) : année, ère, vitesse, tiroirs. Centrée, largeur selon le contenu.
const TOP_BAR := Rect2(500, 8, 920, 46)
## Statistiques de la parcelle (src/ui/stats/), repliables avec S. Hauteur avec 6 espèces ; elle
## peut atteindre STATS_MAX_BOTTOM le temps qu'une espèce disparue s'efface.
const STATS := Rect2(12, 12, 360, 560)
const STATS_MAX_BOTTOM := 652.0
## Fil de narration d'Ézéchiel (src/ui/chronicle/).
const FEED := Rect2(1568, 596, 340, 400)
## Barre d'outils (hud.gd) : onglets Semer / Agir et leurs boutons, centrée en bas.
const TOOL_BAR := Rect2(528, 1012, 1000, 60)
## Réglages de l'outil sélectionné (src/ui/seeds/seed_editor.gd), juste au-dessus ; n'apparaît
## que lorsqu'un outil est choisi.
const TOOL_EDITOR := Rect2(528, 852, 1000, 152)
## Tiroirs fermés par défaut (hud.gd), ouverts par-dessus le reste.
const CHRONICLE_DRAWER := Rect2(12, 664, 500, 332)
const WORLD_DRAWER := Rect2(1528, 64, 380, 524)
## Arbre de la vie (src/ui/tree/), ouvert avec T.
const TREE := Rect2(528, 64, 992, 780)

## Zones visibles au repos (tiroirs fermés, aucun outil choisi).
const REST_ZONES := {
	top_bar = TOP_BAR, stats = STATS, feed = FEED, tool_bar = TOOL_BAR,
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
