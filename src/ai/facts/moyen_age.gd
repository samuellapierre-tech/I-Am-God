extends RefCounted
## Faits réels : Moyen Âge (476 à 1492). Format : voir fact_base.gd.

const FACTS := [
	{"t": "Au Moyen Âge, neuf personnes sur dix vivent à la campagne et travaillent la terre.", "land_use": ["farmland", "village", "pasture"]},
	{"t": "La rotation triennale alterne blé d'hiver, céréales de printemps et jachère : chaque champ se repose une année sur trois.", "land_use": ["farmland"]},
	{"t": "La charrue à versoir, tirée par des bœufs ou par des chevaux munis du collier d'épaule, retourne enfin les lourdes terres du Nord.", "land_use": ["farmland"]},
	{"t": "Les moulins à eau se multiplient : en 1086, le Domesday Book en recense plus de cinq mille en Angleterre.", "land_use": ["village", "farmland"], "min_year": 1086.0},
	{"t": "Le paysan vit d'abord de pain, souvent de seigle ou d'orge, avec une soupe de légumes et un peu de lard quand il y en a.", "land_use": ["farmland", "village"]},
	{"t": "À l'automne, on mène les porcs en forêt à la glandée : ils s'engraissent de glands et de faînes.", "land_use": ["pasture", "wild", "village"], "biome": ["Forêt tempérée"]},
	{"t": "Les premiers châteaux sont des mottes de terre surmontées d'une tour de bois ; on les rebâtit en pierre au fil des siècles.", "land_use": ["village", "town"], "event": ["war"]},
	{"t": "Le monastère est à la fois une ferme, une école et une bibliothèque : les moines y recopient les livres à la main.", "land_use": ["village", "farmland"]},
	{"t": "Au IXe siècle, Bagdad est l'une des plus grandes villes du monde ; on y traduit Aristote et al-Khwârizmî y fonde l'algèbre.", "land_use": ["city", "town"], "event": ["discovery"], "min_year": 762.0},
	{"t": "Les chiffres que l'on dit arabes viennent de l'Inde ; ils gagnent l'Europe au XIIIe siècle, notamment grâce à Fibonacci.", "event": ["discovery"], "min_year": 1202.0},
	{"t": "Vers l'an 1000, des Vikings atteignent l'Amérique et fondent un petit établissement à Terre-Neuve.", "min_year": 1000.0},
	{"t": "Entre 950 et 1250, un climat plus doux permet de défricher et de cultiver plus haut et plus au nord.", "event": ["climate"], "land_use": ["farmland"], "min_year": 950.0},
	{"t": "Grâce aux arcs-boutants, les cathédrales gothiques montent vers le ciel et s'ouvrent d'immenses vitraux.", "land_use": ["town", "city"], "min_year": 1140.0},
	{"t": "Les foires de Champagne attirent marchands italiens et flamands : on y échange draps, épices et lettres de change.", "land_use": ["town", "village"], "min_year": 1150.0},
	{"t": "À partir du XIIe siècle naissent les universités : Bologne, Paris, Oxford.", "land_use": ["town", "city"], "min_year": 1088.0},
	{"t": "Au XIIIe siècle, Gengis Khan et ses héritiers bâtissent le plus vaste empire d'un seul tenant de l'histoire.", "event": ["war", "invasion"], "min_year": 1206.0},
	{"t": "La grande famine de 1315 à 1317 frappe l'Europe du Nord après des étés pourris : les récoltes pourrissent sur pied.", "event": ["disaster", "famine", "climate"], "min_year": 1315.0},
	{"t": "La peste noire, entre 1347 et 1352, tue entre un tiers et la moitié des Européens.", "event": ["plague"], "min_year": 1347.0},
	{"t": "Vers 1450, l'imprimerie de Gutenberg produit en quelques semaines ce qu'un copiste mettait des années à écrire.", "event": ["discovery"], "min_year": 1450.0},
	{"t": "À la fin du Moyen Âge, les hivers se durcissent : c'est le début du petit âge glaciaire, et les récoltes deviennent incertaines.", "event": ["climate", "ice_age"], "min_year": 1300.0},
]
