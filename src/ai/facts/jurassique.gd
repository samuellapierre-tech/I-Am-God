extends RefCounted
## Faits réels : Jurassique (-201,3 à -145 millions d'années). Format : voir fact_base.gd.

const WINDOW := [-201_500_000.0, -145_000_000.0]

const FACTS := [
	{"t": "Au Jurassique, la Pangée se disloque : l'océan Atlantique commence à s'ouvrir.", "land_use": ["ocean"]},
	{"t": "Le climat jurassique est chaud et humide, sans calotte de glace, et les forêts s'étendent loin vers les pôles.", "biome": ["Forêt tempérée", "Forêt tropicale"]},
	{"t": "Les sauropodes deviennent des géants : Brachiosaurus pouvait brouter à plus de dix mètres de hauteur.", "clade": ["dinosaure"], "min_year": -160_000_000.0},
	{"t": "Diplodocus mesurait environ 25 mètres de long, dont une bonne partie de cou et de queue.", "clade": ["dinosaure"], "min_year": -160_000_000.0},
	{"t": "Allosaurus, long d'environ neuf mètres, est l'un des grands prédateurs de la fin du Jurassique.", "clade": ["dinosaure"], "min_year": -160_000_000.0},
	{"t": "Le stégosaure porte de grandes plaques sur le dos et quatre pointes au bout de la queue ; son cerveau était étonnamment petit.", "clade": ["dinosaure"], "min_year": -160_000_000.0},
	{"t": "Archaeopteryx, il y a environ 150 millions d'années, a des plumes et des ailes, mais aussi des dents et une longue queue osseuse.", "clade": ["oiseau", "dinosaure"], "min_year": -152_000_000.0},
	{"t": "Les oiseaux descendent de petits dinosaures carnivores à plumes du Jurassique.", "clade": ["oiseau", "dinosaure"]},
	{"t": "Dans les mers, les plésiosaures au long cou et les ichtyosaures chassent les ammonites et les bélemnites.", "clade": ["reptile", "mollusque"], "land_use": ["ocean"]},
	{"t": "Les mammifères restent petits mais se diversifient déjà : certains nagent, d'autres creusent ou planent.", "clade": ["mammifère"]},
	{"t": "Conifères, cycas et fougères forment l'essentiel des forêts ; les plantes à fleurs n'ont pas encore conquis le monde.", "clade": ["plante"]},
	{"t": "La formation de Morrison, en Amérique du Nord, a livré des squelettes de dinosaures par centaines.", "clade": ["dinosaure"], "min_year": -156_000_000.0},
	{"t": "Rhamphorhynchus, un ptérosaure à longue queue terminée par une palette, pêche au-dessus des lagunes.", "clade": ["ptérosaure"], "land_use": ["flooded", "ocean"], "min_year": -152_000_000.0},
	{"t": "Certains dinosaures herbivores avalent des pierres qui les aidaient peut-être à broyer leur nourriture.", "clade": ["dinosaure"]},
	{"t": "Les grands sauropodes pondent leurs œufs au sol et ne s'occupent probablement pas de leurs petits.", "clade": ["dinosaure"]},
	{"t": "Dans les lagunes de Solnhofen, en Allemagne, un calcaire très fin a conservé des empreintes de plumes et de méduses.", "land_use": ["flooded"], "min_year": -152_000_000.0},
]
