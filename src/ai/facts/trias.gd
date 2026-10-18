extends RefCounted
## Faits réels : Trias (-251,9 à -201,3 millions d'années). Format : voir fact_base.gd.

const WINDOW := [-252_000_000.0, -201_000_000.0]

const FACTS := [
	{"t": "Le Trias s'ouvre sur un monde ravagé : la vie met des millions d'années à se remettre de la Grande Mourance.", "max_year": -240_000_000.0},
	{"t": "La Pangée est toujours d'un seul tenant ; son climat est chaud, souvent sec, avec de fortes moussons.", "biome": ["Désert", "Steppe", "Savane"]},
	{"t": "Les premiers dinosaures apparaissent il y a environ 230 millions d'années : ce sont de petits bipèdes agiles.", "clade": ["dinosaure"], "min_year": -235_000_000.0},
	{"t": "Pendant une bonne partie du Trias, les maîtres de la terre ne sont pas les dinosaures mais d'autres archosaures, cousins des crocodiles.", "clade": ["reptile", "dinosaure"]},
	{"t": "Les premiers mammifères, minuscules et nocturnes, apparaissent à la fin du Trias.", "clade": ["mammifère", "synapside"], "min_year": -225_000_000.0},
	{"t": "Les premiers ptérosaures prennent leur envol au Trias : ce sont les premiers vertébrés à voler activement.", "clade": ["ptérosaure"], "min_year": -230_000_000.0},
	{"t": "Dans les mers, les ichtyosaures, reptiles à l'allure de dauphins, deviennent des géants ; certains dépassent quinze mètres.", "clade": ["reptile"], "land_use": ["ocean"], "min_year": -240_000_000.0},
	{"t": "L'une des premières tortues, Odontochelys, n'avait qu'une demi-carapace, sous le ventre.", "clade": ["reptile"], "min_year": -222_000_000.0},
	{"t": "Il y a environ 232 millions d'années, un long épisode très pluvieux bouleverse les écosystèmes et favorise l'essor des dinosaures.", "event": ["climate", "flood"], "clade": ["dinosaure"], "min_year": -235_000_000.0},
	{"t": "Plateosaurus, un herbivore au long cou de plusieurs mètres, compte parmi les premiers grands dinosaures.", "clade": ["dinosaure"], "min_year": -215_000_000.0},
	{"t": "Les conifères et les cycas dominent les forêts du Trias ; il n'y a encore ni fleurs ni herbe.", "clade": ["plante"]},
	{"t": "Les premiers coraux de type moderne bâtissent de nouveaux récifs au cours du Trias.", "land_use": ["ocean"], "min_year": -240_000_000.0},
	{"t": "Les cynodontes, cousins des mammifères, ont des dents différenciées et une mâchoire puissante.", "clade": ["synapside"]},
	{"t": "À la fin du Trias, la Pangée commence à se déchirer : l'Atlantique Nord naîtra de cette fracture.", "min_year": -215_000_000.0},
	{"t": "Il y a environ 201 millions d'années, de nouvelles éruptions géantes provoquent la grande extinction de la fin du Trias.", "event": ["volcanism", "extinction"], "min_year": -203_000_000.0},
	{"t": "L'extinction de la fin du Trias élimine la plupart des rivaux des dinosaures, qui héritent alors des terres.", "clade": ["dinosaure"], "event": ["extinction"], "min_year": -203_000_000.0},
]
