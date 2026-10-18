extends RefCounted
## Ralentissement du temps pendant un dilemme, puis restauration exacte de la vitesse.
## Pur (aucun accès à GameState) : le panneau lit et écrit GameState.years_per_second avec.
##
## Le HUD réécrit years_per_second à chaque image selon sa vitesse x1..x5. On ne garde donc pas une
## vitesse figée : à chaque image, si la valeur courante n'est plus celle qu'on a écrite, quelqu'un
## a choisi une nouvelle vitesse de base ; on la mémorise et on la ralentit à son tour.
## À la fin, on rend la vitesse de base telle quelle (pas de multiplication : pas d'erreur d'arrondi).

## Facteur de ralentissement par défaut (le temps passe 25 fois moins vite).
const DEFAULT_FACTOR := 25.0

var factor := DEFAULT_FACTOR
var active := false
## Vitesse de base (années/s) à restaurer.
var base_rate := 0.0
## Dernière vitesse ralentie écrite (pour détecter les changements extérieurs).
var written_rate := 0.0


func _init(p_factor: float = DEFAULT_FACTOR) -> void:
	factor = maxf(p_factor, 1.0)


static func slowed(rate: float, p_factor: float) -> float:
	return rate / maxf(p_factor, 1.0)


## Début du dilemme : renvoie la vitesse ralentie à écrire. Sans effet si déjà actif.
func begin(current_rate: float) -> float:
	if active:
		return step(current_rate)
	active = true
	base_rate = current_rate
	written_rate = slowed(base_rate, factor)
	return written_rate


## À chaque image : renvoie la vitesse à écrire (suit une nouvelle base choisie entre-temps).
func step(current_rate: float) -> float:
	if not active:
		return current_rate
	if current_rate != written_rate:
		base_rate = current_rate
		written_rate = slowed(base_rate, factor)
	return written_rate


## Fin du dilemme : renvoie la vitesse à rétablir.
func end(current_rate: float) -> float:
	if not active:
		return current_rate
	active = false
	return base_rate if current_rate == written_rate else current_rate
