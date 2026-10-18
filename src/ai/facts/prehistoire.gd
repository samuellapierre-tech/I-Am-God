extends RefCounted
## Faits réels : Préhistoire humaine (d'Homo sapiens à l'écriture). Format : voir fact_base.gd.

const FACTS := [
	{"t": "Homo sapiens apparaît en Afrique il y a environ 300 000 ans ; ses premiers représentants ont déjà un visage presque moderne.", "clade": ["primate"], "min_year": -300_000.0},
	{"t": "Le feu est maîtrisé depuis des centaines de milliers d'années : il cuit la viande, éloigne les fauves et rassemble le groupe le soir.", "land_use": ["camp"]},
	{"t": "Les chasseurs-cueilleurs vivent en petites bandes de quelques dizaines de personnes et se déplacent au fil des saisons, suivant le gibier et les fruits.", "land_use": ["camp", "wild"]},
	{"t": "Pendant la dernière glaciation, la mer est si basse qu'on peut marcher à pied sec de la Sibérie à l'Alaska.", "event": ["ice_age", "migration", "land_bridge"], "min_year": -100_000.0, "max_year": -11_000.0},
	{"t": "Le mammouth laineux a une épaisse toison et de petites oreilles qui limitent les pertes de chaleur ; on le chasse pour sa viande, ses os et son ivoire.", "biome": ["Toundra", "Steppe", "Taïga", "Glace"], "max_year": -10_000.0},
	{"t": "Dans les steppes glacées, on construit parfois des huttes avec des os de mammouth recouverts de peaux.", "biome": ["Toundra", "Steppe"], "land_use": ["camp"], "min_year": -30_000.0, "max_year": -12_000.0},
	{"t": "Homo sapiens n'est pas seul : les Néandertaliens peuplent l'Europe, et les deux humanités se croisent ; un peu de leur ADN coule encore en nous.", "clade": ["primate"], "min_year": -100_000.0, "max_year": -40_000.0},
	{"t": "Il y a environ 36 000 ans, des artistes peignent lions, chevaux et rhinocéros sur les parois de la grotte Chauvet, à la lueur des torches.", "min_year": -40_000.0},
	{"t": "Le propulseur, un simple bâton à crochet, permet de lancer une sagaie bien plus loin et plus fort qu'à la main.", "land_use": ["camp", "wild"], "min_year": -30_000.0},
	{"t": "Le loup devient chien : il y a au moins 15 000 ans, il chasse et dort déjà aux côtés des humains.", "land_use": ["camp", "pasture"], "min_year": -15_000.0},
	{"t": "Les plus anciennes poteries connues sont cuites en Asie de l'Est il y a près de 20 000 ans, bien avant l'agriculture.", "min_year": -20_000.0},
	{"t": "Il y a environ 12 000 ans, la dernière glaciation s'achève : les glaciers fondent et la mer remonte de plus de cent mètres.", "event": ["climate", "ice_age_end", "flood"], "min_year": -13_000.0},
	{"t": "À la fin de la dernière glaciation, mammouths, rhinocéros laineux et paresseux géants disparaissent presque partout, sous l'effet du climat et de la chasse.", "event": ["extinction"], "min_year": -13_000.0},
	{"t": "Avant même l'agriculture, certains cueilleurs du Levant, les Natoufiens, vivent déjà dans des villages de maisons rondes.", "land_use": ["village", "camp"], "min_year": -15_000.0},
	{"t": "À Göbekli Tepe, il y a plus de 11 000 ans, des chasseurs-cueilleurs dressent des piliers de pierre sculptés de renards, de serpents et de vautours.", "min_year": -11_500.0},
	{"t": "Il y a environ 11 500 ans, au Proche-Orient, des villageois commencent à semer du blé et de l'orge : l'agriculture est née.", "land_use": ["farmland", "village"], "min_year": -11_500.0},
	{"t": "La chèvre, le mouton, le porc et la vache sont domestiqués au Proche-Orient il y a 10 000 à 11 000 ans.", "land_use": ["pasture", "farmland"], "min_year": -11_000.0},
	{"t": "À Çatal Höyük, vers 7 000 ans avant notre ère, des milliers de personnes vivent dans des maisons collées les unes aux autres, où l'on entre par le toit.", "land_use": ["village", "town"], "min_year": -7_500.0},
	{"t": "Vers 5 000 ans avant notre ère, on commence à fondre le cuivre ; la pierre polie reste pourtant l'outil de tous les jours.", "min_year": -5_500.0},
	{"t": "Ötzi, l'homme des glaces, est mort dans les Alpes il y a 5 300 ans, avec sa hache de cuivre, un arc inachevé et des chaussures garnies d'herbe.", "biome": ["Montagnes", "Glace"], "min_year": -3_400.0},
]
