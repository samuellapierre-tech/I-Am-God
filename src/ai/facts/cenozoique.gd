extends RefCounted
## Faits réels : Cénozoïque, de l'impact (-66 Ma) à l'aube de l'humanité. Format : voir fact_base.gd.
## Beaucoup de faits ont une fenêtre de dates : ils ne sont racontés qu'à la bonne époque.

const FACTS := [
	{"t": "L'astéroïde de Chicxulub mesurait une dizaine de kilomètres ; il a creusé un cratère de près de 180 kilomètres de large.", "event": ["meteor", "impact"], "max_year": -65_000_000.0},
	{"t": "Après l'impact, la suie et les poussières ont obscurci le ciel pendant des mois : la photosynthèse s'est presque arrêtée, et les chaînes alimentaires avec elle.", "event": ["meteor", "impact", "climate"], "max_year": -65_000_000.0},
	{"t": "Environ trois espèces sur quatre ont disparu à la fin du Crétacé ; des dinosaures, seuls les oiseaux s'en sont sortis.", "event": ["extinction", "meteor"], "max_year": -64_000_000.0},
	{"t": "Sur les terres dévastées, les fougères repoussent les premières : les géologues appellent cela le « pic de fougères ».", "max_year": -65_000_000.0, "land_use": ["crater", "wild"]},
	{"t": "Dans le million d'années qui suit l'extinction, les mammifères grossissent et se diversifient vite pour occuper les places laissées vides.", "clade": ["mammifère"], "max_year": -60_000_000.0},
	{"t": "Il y a 56 millions d'années, une brusque libération de carbone réchauffe la planète de 5 à 8 °C : c'est le maximum thermique du Paléocène-Éocène.", "event": ["climate"], "min_year": -58_000_000.0, "max_year": -53_000_000.0},
	{"t": "À l'Éocène, des forêts tempérées poussent jusque dans l'Arctique, où vivent des cousins des tapirs et des alligators.", "biome": ["Forêt tempérée", "Taïga", "Toundra"], "min_year": -56_000_000.0, "max_year": -34_000_000.0},
	{"t": "Les premiers vrais primates sont petits et agiles ; leurs yeux tournés vers l'avant jugent les distances d'une branche à l'autre.", "clade": ["primate"], "min_year": -57_000_000.0, "max_year": -40_000_000.0},
	{"t": "De grands oiseaux coureurs incapables de voler, comme Gastornis, arpentent les forêts d'Europe et d'Amérique du Nord.", "clade": ["oiseau"], "min_year": -57_000_000.0, "max_year": -45_000_000.0},
	{"t": "Des mammifères à quatre pattes retournent à la mer : en une dizaine de millions d'années, ils deviennent les baleines.", "land_use": ["ocean"], "min_year": -52_000_000.0, "max_year": -34_000_000.0},
	{"t": "Il y a environ 34 millions d'années, la Terre se refroidit et une calotte de glace commence à recouvrir l'Antarctique.", "event": ["climate", "ice_age"], "land_use": ["ice"], "min_year": -36_000_000.0, "max_year": -25_000_000.0},
	{"t": "Les ancêtres des chevaux, d'abord grands comme des renards et habitants des forêts, deviennent peu à peu des coureurs des plaines.", "clade": ["mammifère"], "min_year": -50_000_000.0},
	{"t": "Les prairies s'étendent : l'herbe, chargée de silice, use les dents, et les herbivores se dotent de dents hautes qui s'usent lentement.", "biome": ["Steppe", "Savane"], "clade": ["mammifère"], "min_year": -25_000_000.0},
	{"t": "Il y a quelques millions d'années, de nouvelles herbes, plus résistantes à la chaleur et à la sécheresse, envahissent les savanes.", "biome": ["Savane", "Steppe", "Désert"], "min_year": -9_000_000.0},
	{"t": "Il y a une vingtaine de millions d'années, les premiers grands singes, sans queue, vivent dans les forêts d'Afrique de l'Est.", "clade": ["primate"], "biome": ["Forêt tropicale"], "min_year": -23_000_000.0, "max_year": -14_000_000.0},
	{"t": "Il y a environ 19 millions d'années, l'Afrique rejoint l'Asie : les ancêtres des éléphants, des gomphothères, partent à la conquête de l'Eurasie.", "clade": ["mammifère"], "event": ["migration", "land_bridge"], "min_year": -20_000_000.0, "max_year": -10_000_000.0},
	{"t": "Dans les océans chasse le mégalodon, un requin d'une quinzaine de mètres qui s'attaque aux baleines.", "land_use": ["ocean"], "min_year": -23_000_000.0, "max_year": -3_600_000.0},
	{"t": "L'Inde s'enfonce sous l'Asie depuis des dizaines de millions d'années : l'Himalaya s'élève, et avec lui le régime des moussons.", "biome": ["Montagnes"], "min_year": -40_000_000.0},
	{"t": "Les oiseaux, seuls héritiers des dinosaures, se diversifient en milliers d'espèces, du colibri à l'autruche.", "clade": ["oiseau"]},
	{"t": "En Afrique, une lignée de grands singes commence à se tenir debout : c'est le début de la branche humaine.", "clade": ["primate"], "min_year": -7_000_000.0, "max_year": -4_000_000.0},
	{"t": "Les mammouths apparaissent en Afrique il y a environ cinq millions d'années, avant de gagner l'Eurasie puis l'Amérique.", "clade": ["mammifère"], "min_year": -5_000_000.0},
	{"t": "Il y a environ trois millions d'années, l'isthme de Panama relie les deux Amériques : les animaux du Nord et du Sud se rencontrent.", "event": ["migration", "land_bridge"], "min_year": -3_500_000.0},
	{"t": "Lucy, une australopithèque, marchait debout il y a 3,2 millions d'années ; son cerveau n'était guère plus gros que celui d'un chimpanzé.", "clade": ["primate"], "min_year": -3_200_000.0},
	{"t": "Depuis 2,6 millions d'années, les glaciations reviennent par cycles : les glaces avancent, reculent, puis reviennent.", "event": ["ice_age", "climate"], "land_use": ["ice"], "min_year": -2_600_000.0},
	{"t": "Les grands carnivores d'aujourd'hui, félins et canidés, descendent de petits ancêtres qui grimpaient aux arbres.", "clade": ["mammifère"], "min_year": -45_000_000.0},
]
