extends RefCounted
## Faits réels : révolution industrielle (1760 à 1945 environ). Format : voir fact_base.gd.

const FACTS := [
	{"t": "La machine à vapeur, perfectionnée par James Watt à partir de 1769, change le charbon en force de travail.", "event": ["discovery"], "min_year": 1769.0},
	{"t": "Dans les premières filatures, des machines font tourner des centaines de broches ; des enfants y travaillent souvent plus de douze heures par jour.", "land_use": ["town", "city"], "min_year": 1771.0},
	{"t": "La population mondiale atteint un milliard vers 1800, puis deux milliards vers 1927.", "min_year": 1800.0},
	{"t": "En 1830, la ligne Liverpool-Manchester ouvre l'ère des chemins de fer de voyageurs.", "land_use": ["town", "city"], "min_year": 1830.0},
	{"t": "Les villes industrielles grandissent si vite que les égouts ne suivent pas : le choléra y frappe à plusieurs reprises.", "event": ["plague"], "land_use": ["city", "town"], "min_year": 1830.0},
	{"t": "En 1854, John Snow montre à Londres que le choléra se transmet par l'eau d'une pompe contaminée.", "event": ["plague", "discovery"], "min_year": 1854.0},
	{"t": "La famine irlandaise, de 1845 à 1852, causée par le mildiou de la pomme de terre, tue environ un million de personnes.", "event": ["famine", "disaster"], "land_use": ["farmland"], "min_year": 1845.0},
	{"t": "En 1859, Darwin publie De l'origine des espèces : toutes les espèces descendent d'ancêtres communs.", "event": ["discovery", "speciation"], "min_year": 1859.0},
	{"t": "Un câble télégraphique traverse l'Atlantique dès 1858 ; la liaison devient durable en 1866.", "min_year": 1858.0},
	{"t": "En 1879, la lampe à incandescence d'Edison s'allume ; l'électricité entre peu à peu dans les villes.", "land_use": ["city", "town"], "event": ["discovery"], "min_year": 1879.0},
	{"t": "Le charbon noircit le ciel des villes : à Londres, un brouillard chargé de suie peut stagner pendant des jours.", "land_use": ["city", "megacity"], "min_year": 1800.0},
	{"t": "En 1913, le travail à la chaîne de Ford fait passer l'assemblage d'une voiture d'une douzaine d'heures à environ une heure et demie.", "land_use": ["city"], "min_year": 1913.0},
	{"t": "Le procédé Haber-Bosch, mis au point vers 1910, tire de l'air l'azote des engrais : il nourrit aujourd'hui des milliards de personnes.", "land_use": ["farmland"], "event": ["discovery"], "min_year": 1913.0},
	{"t": "La Première Guerre mondiale, de 1914 à 1918, fait environ vingt millions de morts, militaires et civils.", "event": ["war"], "min_year": 1914.0},
	{"t": "La grippe de 1918 tue plus de monde que la guerre qui s'achève : des dizaines de millions de personnes.", "event": ["plague"], "min_year": 1918.0},
	{"t": "Au XXe siècle, les tracteurs remplacent peu à peu les chevaux dans les champs.", "land_use": ["farmland", "pasture"], "min_year": 1910.0},
	{"t": "La Seconde Guerre mondiale, de 1939 à 1945, fait plus de soixante millions de morts.", "event": ["war"], "min_year": 1939.0},
	{"t": "En brûlant du charbon, l'humanité commence à enrichir l'air en dioxyde de carbone : le réchauffement d'origine humaine est en marche.", "event": ["climate"], "min_year": 1850.0},
]
