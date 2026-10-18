extends RefCounted
## Faits réels : époque contemporaine (1945 à aujourd'hui). Format : voir fact_base.gd.

const FACTS := [
	{"t": "En 1945, deux bombes atomiques détruisent Hiroshima et Nagasaki.", "event": ["war", "disaster"], "land_use": ["city"], "min_year": 1945.0},
	{"t": "La pénicilline, découverte en 1928 et produite en masse dans les années 1940, fait de nombreuses infections des maladies que l'on guérit.", "event": ["plague", "discovery"], "min_year": 1945.0},
	{"t": "Les conteneurs standardisés, apparus en 1956, font exploser le commerce maritime mondial.", "land_use": ["city", "megacity", "ocean"], "min_year": 1956.0},
	{"t": "Dans les années 1960, la révolution verte multiplie les rendements de blé et de riz grâce à de nouvelles variétés, aux engrais et à l'irrigation.", "land_use": ["farmland"], "min_year": 1965.0},
	{"t": "En 1969, deux humains marchent sur la Lune ; des centaines de millions de personnes regardent la scène en direct.", "event": ["discovery"], "min_year": 1969.0},
	{"t": "En 1980, la variole est déclarée éradiquée : c'est la première maladie humaine vaincue par la vaccination.", "event": ["plague"], "min_year": 1980.0},
	{"t": "En 1986, l'explosion d'un réacteur à Tchernobyl vide une région entière ; la faune sauvage y revient en l'absence des humains.", "event": ["disaster"], "land_use": ["ruins", "rewild"], "min_year": 1986.0},
	{"t": "En 1989, au CERN, Tim Berners-Lee propose le Web ; Internet relie bientôt le monde entier.", "event": ["discovery"], "min_year": 1989.0},
	{"t": "En 2003, le génome humain est séquencé pour l'essentiel, après treize ans de travail.", "event": ["discovery"], "min_year": 2003.0},
	{"t": "Depuis 2007 environ, plus de la moitié de l'humanité vit en ville.", "land_use": ["city", "megacity"], "min_year": 2007.0},
	{"t": "La population mondiale passe de 2,5 milliards en 1950 à plus de 8 milliards en 2022.", "min_year": 2022.0},
	{"t": "Le téléphone mobile, encore rare au début des années 1990, se retrouve dans presque toutes les poches vingt ans plus tard.", "land_use": ["city", "megacity", "town"], "min_year": 2010.0},
	{"t": "Dans les pays riches, grâce aux machines et aux engrais, quelques pour cent de la population suffisent à nourrir tous les autres.", "land_use": ["farmland"], "min_year": 1980.0},
	{"t": "Plusieurs agglomérations dépassent les vingt millions d'habitants : Tokyo, Delhi, Shanghai…", "land_use": ["megacity", "city"], "min_year": 2000.0},
	{"t": "La Terre s'est réchauffée de plus d'un degré depuis la fin du XIXe siècle, surtout à cause du charbon, du pétrole et du gaz.", "event": ["climate"], "min_year": 2015.0},
	{"t": "Les glaciers de montagne reculent presque partout, et la banquise arctique d'été a perdu une grande partie de sa surface depuis 1979.", "event": ["climate"], "land_use": ["ice"], "min_year": 2000.0},
	{"t": "L'Amazonie a perdu près d'un cinquième de sa forêt en un demi-siècle.", "biome": ["Forêt tropicale"], "land_use": ["farmland", "pasture", "wild"], "min_year": 2015.0},
	{"t": "Les populations d'animaux sauvages suivies par les scientifiques ont chuté en moyenne de plus des deux tiers depuis 1970.", "event": ["extinction"], "min_year": 2020.0},
]
