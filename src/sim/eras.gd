extends RefCounted
## Ères et compression du temps.
##
## Les deux premières ères (Mésozoïque, Cénozoïque) précèdent toute sapience. Ensuite, l'ère
## courante est dictée par le niveau technologique L (flottant, 0..MAX_TECH) de l'espèce
## sapiente la plus avancée : ère = 2 + floor(L).

const MESOZOIC := 0
const CENOZOIC := 1
const FIRST_SAPIENT_ERA := 2
const LAST_ERA := 9
const MAX_TECH := 8.0

## Pas de temps idéal (années) par ère : des dizaines de milliers d'années au début,
## une fraction d'année à la fin.
const IDEAL_DT: Array[float] = [50000.0, 50000.0, 500.0, 10.0, 5.0, 2.0, 1.0, 0.5, 0.25, 0.25]

## Durée « naturelle » (années) pour franchir le niveau technologique L -> L+1
## avec une population pleinement étendue et sans modificateurs.
const LEVEL_YEARS: Array[float] = [250000.0, 4000.0, 1000.0, 300.0, 150.0, 70.0, 50.0, 60.0]

## Jalons franchis à 25 %, 50 % et 75 % de chaque niveau (texte : « Les <espèce> <jalon> »,
## d'où les verbes au pluriel).
const MILESTONES := [
	["maîtrisent le feu", "développent un langage articulé", "inventent l'agriculture"],
	["inventent l'écriture", "forgent le bronze", "fondent les premières cités-États"],
	["érigent des forteresses", "inventent le moulin", "fondent des universités"],
	["inventent l'imprimerie", "cartographient le globe", "formulent la méthode scientifique"],
	["domptent la vapeur", "électrifient leurs villes", "inventent le moteur à explosion"],
	["fissionnent l'atome", "envoient un satellite en orbite", "mettent en réseau leurs ordinateurs"],
	["greffent des implants neuronaux", "bâtissent des mégapoles verticales", "éveillent une IA générale"],
	["fusionnent esprit et machine", "colonisent le système stellaire", "transcendent la matière"],
]


static func era_for_tech(level: float) -> int:
	return clampi(FIRST_SAPIENT_ERA + int(floorf(level)), FIRST_SAPIENT_ERA, LAST_ERA)


static func ideal_dt(era_index: int) -> float:
	return IDEAL_DT[clampi(era_index, 0, LAST_ERA)]


## Durée de référence d'une ère, utilisée pour dimensionner les conséquences différées
## (une glaciation dure des millions d'années au Mésozoïque, quelques décennies à l'ère moderne).
static func time_unit(era_index: int) -> float:
	return ideal_dt(era_index) * 20.0


static func level_years(level: float) -> float:
	return LEVEL_YEARS[clampi(int(floorf(level)), 0, LEVEL_YEARS.size() - 1)]


## Intègre la croissance technologique sur `dt` années de façon robuste (dt arbitrairement grand) :
## le taux change à chaque niveau franchi. `speed` = multiplicateur (population, modificateurs).
static func integrate_tech(level: float, dt: float, speed: float) -> float:
	if speed <= 0.0:
		return level
	var remaining := dt
	var guard := 0
	while remaining > 0.0 and level < MAX_TECH and guard < 16:
		guard += 1
		var rate := speed / level_years(level)
		var next_level := floorf(level) + 1.0
		var t_next := (next_level - level) / rate
		if t_next >= remaining:
			level += rate * remaining
			remaining = 0.0
		else:
			level = next_level
			remaining -= t_next
	return minf(level, MAX_TECH)
