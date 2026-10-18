extends RefCounted
## Faits réels : Archéen (-4 à -2,5 milliards d'années), l'origine de la vie. Format : voir fact_base.gd.

const WINDOW := [-4_000_000_000.0, -2_500_000_000.0]

const FACTS := [
	{"t": "Il y a 3,8 milliards d'années, la Terre est couverte d'un océan chaud, sous un ciel sans oxygène, et le jeune Soleil brille moins fort qu'aujourd'hui.", "land_use": ["ocean"]},
	{"t": "La Lune est bien plus proche qu'aujourd'hui : les marées sont plus fortes et les jours bien plus courts.", "land_use": ["ocean", "flooded"]},
	{"t": "Les plus anciennes traces de vie bien établies ont environ 3,5 milliards d'années : des microbes qui vivent sans oxygène.", "clade": ["microbe"]},
	{"t": "Les stromatolites sont des monticules de roche bâtis couche après couche par des tapis de microbes ; il en pousse encore aujourd'hui en Australie.", "clade": ["microbe", "algue"]},
	{"t": "Au fond des océans, des sources hydrothermales crachent une eau brûlante chargée de minéraux : certains chercheurs pensent que la vie y est née.", "clade": ["microbe"], "land_use": ["ocean"]},
	{"t": "D'autres chercheurs penchent pour des mares côtières, qui s'assèchent et se remplissent au gré des marées et des pluies.", "clade": ["microbe"], "land_use": ["flooded", "wild"]},
	{"t": "Tous les êtres vivants actuels descendent d'un même ancêtre, une cellule que les biologistes surnomment LUCA.", "clade": ["microbe"]},
	{"t": "L'air de l'Archéen est fait surtout d'azote, de dioxyde de carbone et de vapeur d'eau : un humain y étoufferait en quelques minutes."},
	{"t": "Les premiers microbes tirent sans doute leur énergie de la chimie des roches et des gaz volcaniques, sans aucune lumière.", "clade": ["microbe"]},
	{"t": "Certains microbes, les méthanogènes, rejettent du méthane : ce gaz à effet de serre aidait peut-être la jeune Terre à rester au chaud.", "clade": ["microbe"], "event": ["climate"]},
	{"t": "Les continents sont encore petits et rares ; l'essentiel de la surface est un océan semé d'îles volcaniques.", "land_use": ["ocean"]},
	{"t": "Les plus anciennes roches connues, au Canada, ont environ quatre milliards d'années."},
	{"t": "Des cristaux de zircon d'Australie, vieux de 4,4 milliards d'années, suggèrent qu'il existait déjà de l'eau liquide très tôt."},
	{"t": "Il y a plus de 3 milliards d'années, des microbes inventent une photosynthèse qui ne produit pas encore d'oxygène.", "clade": ["microbe"]},
	{"t": "Pendant plus de deux milliards d'années, la vie reste faite de cellules isolées ; seuls ses tapis et ses monticules se voient à l'œil nu.", "clade": ["microbe"]},
	{"t": "À la fin de l'Archéen, les cyanobactéries produisent déjà de l'oxygène, mais le fer des océans et les gaz des volcans l'absorbent aussitôt.", "clade": ["microbe", "algue"]},
]
