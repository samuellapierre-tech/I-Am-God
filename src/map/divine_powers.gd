extends RefCounted
## Catalogue des pouvoirs divins (contrat docs/ARCHITECTURE.md : types d'action divine).
## Partagé par la carte (application, couleurs d'effet) et le HUD (barre de pouvoirs, raccourcis).

## id : type d'action envoyé à GameState.apply_divine_action
## key : raccourci clavier (touche physique, donc 1..9 aussi en AZERTY sans Maj)
## needs_species : l'action vise une espèce (cible sélectionnée, sinon l'espèce dominante de la région)
const LIST := [
	{id = "meteor", label = "Météorite", key = KEY_1, radius = 8, needs_species = false,
		color = Color(1.0, 0.55, 0.15), hint = "Impact cataclysmique : onde de choc, hiver d'impact."},
	{id = "extinct", label = "Extinction", key = KEY_2, radius = 12, needs_species = true,
		color = Color(0.85, 0.05, 0.12), hint = "Efface une espèce de la région (ou du monde)."},
	{id = "save", label = "Salut", key = KEY_3, radius = 10, needs_species = true,
		color = Color(0.9, 0.95, 1.0), hint = "Protège une espèce menacée de l'extinction."},
	{id = "bless", label = "Bénédiction", key = KEY_4, radius = 8, needs_species = true,
		color = Color(1.0, 0.85, 0.3), hint = "Prospérité : la population croît."},
	{id = "plague", label = "Fléau", key = KEY_5, radius = 10, needs_species = true,
		color = Color(0.45, 0.9, 0.15), hint = "Une épidémie frappe l'espèce ciblée."},
	{id = "uplift", label = "Élévation", key = KEY_6, radius = 6, needs_species = true,
		color = Color(0.7, 0.4, 1.0), hint = "Accorde l'étincelle de l'intelligence et du progrès."},
	{id = "flood", label = "Déluge", key = KEY_7, radius = 14, needs_species = false,
		color = Color(0.15, 0.5, 1.0), hint = "Les eaux montent et engloutissent les terres basses."},
	{id = "ice_age", label = "Âge glaciaire", key = KEY_8, radius = 30, needs_species = false,
		color = Color(0.65, 0.95, 1.0), hint = "Refroidissement brutal : la banquise avance."},
	{id = "spawn_species", label = "Création", key = KEY_9, radius = 4, needs_species = false,
		color = Color(0.4, 1.0, 0.6), hint = "Fait naître une nouvelle espèce."},
]

const MIN_RADIUS := 0
const MAX_RADIUS := 64


static func index_of(power_id: String) -> int:
	for i in LIST.size():
		if LIST[i].id == power_id:
			return i
	return -1


static func get_power(power_id: String) -> Dictionary:
	var i := index_of(power_id)
	return LIST[i] if i >= 0 else {}


## Construit l'action divine au format du contrat.
static func make_action(power_id: String, region: Vector2i, species_id: int, radius: int) -> Dictionary:
	return {type = power_id, region = region, species_id = species_id, radius = radius}
