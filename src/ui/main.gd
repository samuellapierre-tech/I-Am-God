extends Node
## Scène principale : le jeu ne montre que la parcelle suivie, plein écran, qui évolue de -66 Ma
## jusqu'à la fin (pas de globe, pas de carte du monde). La simulation mondiale tourne en fond et
## façonne la parcelle. Les vues sont chargées par chemin : chaque branche de module possède sa scène.
## Les pouvoirs du HUD visent la parcelle (src/ui/parcel_powers.gd).

const PARCEL_SCENE := "res://scenes/parcel_view.tscn"
const STATS_SCENE := "res://scenes/stats_panel.tscn"
## Fil de narration d'Ézéchiel, le compagnon (docs/GENESE.md).
## Couche stratégique : menaces, pistes, actions, écrans de lancement et de fin.
## Menu (src/ui/menu/) : Continuer / Nouvelle planète / Panthéon, fin des temps, réincarnation.
const OVERLAY_SCENES := ["res://scenes/narration_feed.tscn", "res://scenes/main_menu.tscn"]
const ParcelPowers := preload("res://src/ui/parcel_powers.gd")

var parcel_view: Node
var powers: Node

@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	parcel_view = load(PARCEL_SCENE).instantiate()
	add_child(parcel_view)
	move_child(parcel_view, 0)
	for path in [STATS_SCENE] + OVERLAY_SCENES:
		if ResourceLoader.exists(path):
			add_child(load(path).instantiate())
	powers = ParcelPowers.new()
	powers.name = "ParcelPowers"
	add_child(powers)
	hud.bind_map(powers)
	GameState.set_view_mode("parcel")
