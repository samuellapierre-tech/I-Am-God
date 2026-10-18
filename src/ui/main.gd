extends Node
## Scène principale : le jeu ne montre que la parcelle suivie, plein écran, qui évolue de -66 Ma
## jusqu'à la fin (pas de globe, pas de carte du monde). La simulation mondiale tourne en fond et
## façonne la parcelle. Les vues sont chargées par chemin : chaque branche de module possède sa scène.
## Les pouvoirs du HUD visent la parcelle (src/ui/parcel_powers.gd).

const PARCEL_SCENE := "res://scenes/parcel_view.tscn"
const STATS_SCENE := "res://scenes/stats_panel.tscn"
const ParcelPowers := preload("res://src/ui/parcel_powers.gd")

var parcel_view: Node
var powers: Node

@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	parcel_view = load(PARCEL_SCENE).instantiate()
	add_child(parcel_view)
	move_child(parcel_view, 0)
	if ResourceLoader.exists(STATS_SCENE):
		add_child(load(STATS_SCENE).instantiate())
	powers = ParcelPowers.new()
	powers.name = "ParcelPowers"
	add_child(powers)
	hud.bind_map(powers)
	GameState.set_view_mode("parcel")
