extends RefCounted
## Faits réels : Grande Oxydation et « milliard ennuyeux » (-2,5 milliards à -800 millions d'années).
## Format : voir fact_base.gd.

const WINDOW := [-2_500_000_000.0, -800_000_000.0]

const FACTS := [
	{"t": "Il y a environ 2,4 milliards d'années, l'oxygène rejeté par les cyanobactéries commence à s'accumuler dans l'air : c'est la Grande Oxydation.", "clade": ["microbe", "algue"]},
	{"t": "Pour la plupart des microbes de l'époque, l'oxygène est un poison : beaucoup disparaissent ou se réfugient dans les vases privées d'air.", "clade": ["microbe"], "event": ["extinction"]},
	{"t": "L'oxygène réagit avec le fer dissous dans la mer : le fer rouillé se dépose au fond en couches rouges et grises, les fers rubanés.", "land_use": ["ocean"]},
	{"t": "L'essentiel du minerai de fer exploité aujourd'hui provient de ces anciens fonds marins rouillés."},
	{"t": "L'oxygène détruit une partie du méthane de l'air ; privée de cette couverture, la Terre connaît l'une de ses premières grandes glaciations.", "event": ["ice_age", "climate"], "land_use": ["ice"]},
	{"t": "Dans la haute atmosphère, l'oxygène forme peu à peu une couche d'ozone qui filtre les rayons ultraviolets du Soleil."},
	{"t": "Il y a environ deux milliards d'années apparaissent les eucaryotes, des cellules plus grandes qui abritent un noyau.", "clade": ["microbe", "algue"]},
	{"t": "Les mitochondries, centrales énergétiques de nos cellules, sont d'anciennes bactéries avalées par une autre cellule et jamais digérées.", "clade": ["microbe"]},
	{"t": "De la même façon, les chloroplastes des plantes descendent de cyanobactéries capturées par une cellule plus grande.", "clade": ["algue", "plante"]},
	{"t": "Entre 1,8 milliard et 800 millions d'années, le climat et la chimie des océans changent si peu que les géologues parlent du « milliard ennuyeux ».", "min_year": -1_800_000_000.0},
	{"t": "Les plus anciens fossiles probables d'algues faites de plusieurs cellules ont plus d'un milliard d'années.", "clade": ["algue"], "min_year": -1_600_000_000.0},
	{"t": "La reproduction sexuée apparaît chez les eucaryotes il y a plus d'un milliard d'années : les gènes de deux parents se mêlent.", "clade": ["algue", "microbe"], "min_year": -1_200_000_000.0},
	{"t": "Malgré tout cet oxygène, l'air n'en contient encore qu'une petite fraction de la teneur actuelle."},
	{"t": "Les océans profonds restent longtemps privés d'oxygène, parfois chargés de soufre, tandis que les eaux de surface s'oxygènent.", "land_use": ["ocean"]},
	{"t": "Un supercontinent, Columbia, se forme puis se disloque entre environ 1,8 et 1,3 milliard d'années.", "min_year": -1_900_000_000.0},
	{"t": "Vers un milliard d'années, un autre supercontinent, Rodinia, rassemble presque toutes les terres.", "min_year": -1_200_000_000.0},
]
