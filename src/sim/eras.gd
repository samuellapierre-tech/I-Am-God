extends RefCounted
## Ères et compression du temps.
##
## Prologue (avant toute vie sur les terres puis jusqu'à la Grande Mourance) : sept étapes
## déclenchées par l'état du monde (oxygène, complexité du vivant, conquête des terres, climat),
## voir WorldSim._update_prologue. Puis Mésozoïque et Cénozoïque, qui précèdent toute sapience.
## Ensuite, l'ère courante est dictée par le niveau technologique L (flottant, 0..MAX_TECH) de
## l'espèce sapiente la plus avancée : ère = FIRST_SAPIENT_ERA + floor(L).
## Le code ne suppose jamais un indice : il utilise ces constantes.

const ARCHEAN := 0
const GREAT_OXIDATION := 1
const SNOWBALL := 2
const CAMBRIAN := 3
const LAND_CONQUEST := 4
const CARBONIFEROUS := 5
const GREAT_DYING := 6
const MESOZOIC := 7
const CENOZOIC := 8
const FIRST_SAPIENT_ERA := 9
const LAST_ERA := 16
## Après la chute ou le départ de toute civilisation : l'âge des héritiers (mode Éternité), d'où
## une nouvelle lignée peut s'éveiller (retour à FIRST_SAPIENT_ERA : un nouveau cycle).
const AFTERMATH := 17
const MAX_TECH := 8.0

## Noms des ères (WorldSim.ERAS), dans l'ordre des indices ci-dessus.
const NAMES := [
	"Archéen", "Grande Oxydation", "Terre boule de neige", "Explosion cambrienne",
	"Sortie des eaux", "Carbonifère", "Grande Mourance",
	"Mésozoïque", "Cénozoïque", "Préhistoire", "Antiquité",
	"Moyen Âge", "Renaissance", "Industriel", "Moderne", "Cyberpunk", "Post-singularité",
	"Âge des héritiers",
]
## Dates de référence (années) des étapes du prologue dans l'histoire réelle : la simulation les
## retrouve à peu près sans intervention, mais ce sont des conséquences, pas des déclencheurs.
const PROLOGUE_REFERENCE_YEARS := [-3.8e9, -2.4e9, -720.0e6, -540.0e6, -375.0e6, -300.0e6, -252.0e6]

## Pas de temps idéal (années) par ère. Prologue : réglé pour 10 à 15 minutes à x1 avec
## l'ouverture lente de GameState (voir tests/test_sim_prologue.gd) ; Mésozoïque : 15 à 25 min ;
## ensuite des dizaines de milliers d'années, puis une fraction d'année à la fin.
const IDEAL_DT: Array[float] = [
	12.0e6, 5.5e6, 1.0e6, 550000.0, 380000.0, 260000.0, 120000.0,
	70000.0, 50000.0, 500.0, 10.0, 5.0, 2.0, 1.0, 0.5, 0.25, 0.25,
	50000.0,
]
## Fin du Crétacé de référence (rythme de l'acte I, voir WorldSim.MESOZOIC_STEPS).
const CRETACEOUS_END := -66.0e6
## Plafond de l'unité de temps des conséquences (années) : un hiver d'impact dure quelques
## millions d'années, même quand le pas idéal du prologue en couvre davantage.
const MAX_TIME_UNIT := 2.0e6

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
	return IDEAL_DT[clampi(era_index, 0, IDEAL_DT.size() - 1)]


## Durée de référence d'une ère, utilisée pour dimensionner les conséquences différées
## (une glaciation dure des millions d'années au Mésozoïque, quelques décennies à l'ère moderne).
static func time_unit(era_index: int) -> float:
	return minf(ideal_dt(era_index) * 20.0, MAX_TIME_UNIT)


static func is_prologue(era_index: int) -> bool:
	return era_index < MESOZOIC


## Sous-période géologique (« Trias », « Jurassique », « Crétacé »…) d'une année du Mésozoïque ou
## du prologue ; "" ensuite.
static func period_for_year(y: float) -> String:
	if y < -2.5e9:
		return "Archéen"
	if y < -541.0e6:
		return "Protérozoïque"
	if y < -485.0e6:
		return "Cambrien"
	if y < -443.0e6:
		return "Ordovicien"
	if y < -419.0e6:
		return "Silurien"
	if y < -359.0e6:
		return "Dévonien"
	if y < -299.0e6:
		return "Carbonifère"
	if y < -252.0e6:
		return "Permien"
	if y < -201.0e6:
		return "Trias"
	if y < -145.0e6:
		return "Jurassique"
	if y < -66.0e6:
		return "Crétacé"
	return ""


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
