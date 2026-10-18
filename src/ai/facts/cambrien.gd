extends RefCounted
## Faits réels : explosion cambrienne, Ordovicien et Silurien (-539 à -419 millions d'années).
## Format : voir fact_base.gd.

const WINDOW := [-539_000_000.0, -419_000_000.0]

const FACTS := [
	{"t": "Il y a environ 540 millions d'années commence l'explosion cambrienne : en quelques dizaines de millions d'années apparaissent presque tous les grands types d'animaux.", "event": ["speciation"]},
	{"t": "Les trilobites, des arthropodes à carapace, comptent parmi les animaux les plus répandus des mers cambriennes.", "clade": ["arthropode"], "land_use": ["ocean"]},
	{"t": "Les yeux des trilobites sont faits de cristaux de calcite : ce sont parmi les plus anciens yeux connus.", "clade": ["arthropode"]},
	{"t": "Anomalocaris, un prédateur muni de deux grands appendices épineux, pouvait dépasser un demi-mètre : un géant pour son époque.", "clade": ["arthropode"], "max_year": -485_000_000.0},
	{"t": "Dans les schistes de Burgess, au Canada, des animaux au corps mou ont été fossilisés avec une précision exceptionnelle.", "max_year": -485_000_000.0},
	{"t": "Pikaia, un petit animal en forme de ruban doté d'une corde dorsale, est un proche cousin des premiers vertébrés.", "clade": ["poisson"], "max_year": -485_000_000.0},
	{"t": "Avec les prédateurs naissent les carapaces, les épines et les coquilles : une course aux armements commence.", "clade": ["arthropode", "mollusque"]},
	{"t": "Les premiers poissons, encore sans mâchoires, apparaissent au Cambrien.", "clade": ["poisson"], "min_year": -520_000_000.0},
	{"t": "Au cours du Cambrien, une journée ne dure qu'environ vingt et une heures."},
	{"t": "À l'Ordovicien, la vie marine se diversifie encore : récifs, nautiloïdes et étoiles de mer se multiplient.", "clade": ["mollusque"], "land_use": ["ocean"], "min_year": -485_000_000.0},
	{"t": "Certains nautiloïdes de l'Ordovicien portent une coquille droite longue de plusieurs mètres.", "clade": ["mollusque"], "min_year": -485_000_000.0, "max_year": -443_000_000.0},
	{"t": "Les premières plantes terrestres, proches des mousses, colonisent les rivages à l'Ordovicien.", "clade": ["plante"], "min_year": -475_000_000.0},
	{"t": "Il y a environ 445 millions d'années, une glaciation provoque la première des cinq grandes extinctions de masse.", "event": ["ice_age", "extinction"], "min_year": -446_000_000.0},
	{"t": "Au Silurien, les poissons à mâchoires se répandent : mordre devient possible.", "clade": ["poisson"], "min_year": -443_000_000.0},
	{"t": "Les euryptérides, ou scorpions de mer, comptent parmi les plus grands arthropodes ayant jamais vécu ; certains atteignent deux mètres.", "clade": ["arthropode"], "min_year": -445_000_000.0},
	{"t": "Les premiers animaux à s'aventurer hors de l'eau sont des arthropodes, comme des mille-pattes, au Silurien.", "clade": ["arthropode", "insecte"], "min_year": -430_000_000.0},
]
