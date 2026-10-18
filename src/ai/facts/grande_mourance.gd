extends RefCounted
## Faits réels : fin du Permien et Grande Mourance (-260 à -251 millions d'années). Format : voir fact_base.gd.

const WINDOW := [-260_000_000.0, -251_000_000.0]

const FACTS := [
	{"t": "Il y a environ 252 millions d'années, la plus grande extinction de l'histoire emporte autour de 90 % des espèces marines.", "event": ["extinction"], "land_use": ["ocean"]},
	{"t": "Sur la terre ferme, environ 70 % des espèces de vertébrés disparaissent aussi.", "event": ["extinction"]},
	{"t": "En Sibérie, les trapps volcaniques déversent des millions de kilomètres cubes de lave pendant des centaines de milliers d'années.", "event": ["volcanism", "disaster"]},
	{"t": "Les éruptions sibériennes libèrent d'énormes quantités de dioxyde de carbone et réchauffent brutalement la planète.", "event": ["volcanism", "climate"]},
	{"t": "Les océans se réchauffent, s'acidifient et perdent leur oxygène : la vie marine suffoque.", "land_use": ["ocean"], "event": ["climate", "extinction"]},
	{"t": "Au plus fort de la crise, la température des mers tropicales dépasse peut-être 40 °C.", "land_use": ["ocean"], "event": ["climate"]},
	{"t": "Les trilobites, présents depuis le Cambrien, disparaissent pour toujours.", "clade": ["arthropode"], "event": ["extinction"]},
	{"t": "C'est la seule extinction de masse connue qui ait durement frappé les insectes.", "clade": ["insecte"], "event": ["extinction"]},
	{"t": "Les gorgonopsiens, de grands synapsides prédateurs aux canines en sabre, disparaissent avec la crise.", "clade": ["synapside"], "event": ["extinction"]},
	{"t": "Lystrosaurus, un synapside trapu au bec corné, survit et devient l'animal terrestre le plus commun du début du Trias.", "clade": ["synapside"]},
	{"t": "Après la crise, il faut des millions d'années pour que les récifs coralliens réapparaissent.", "land_use": ["ocean"]},
	{"t": "Des plantes pionnières, comme certaines fougères, colonisent les terres dévastées ; les forêts mettront des millions d'années à revenir.", "clade": ["plante"]},
	{"t": "Les synapsides dominaient les terres du Permien ; la crise rebat les cartes au profit de la lignée des reptiles, d'où sortiront les dinosaures.", "clade": ["synapside", "reptile"]},
	{"t": "La Pangée est si vaste que son intérieur est un immense désert, brûlant l'été et glacial l'hiver.", "biome": ["Désert", "Steppe"]},
	{"t": "Les géologues appellent cette crise l'extinction Permien-Trias ; on la surnomme aussi la Grande Mourance.", "event": ["extinction"]},
	{"t": "Certains ancêtres des mammifères, les cynodontes, traversent la crise ; ils portaient peut-être déjà des poils.", "clade": ["synapside"]},
]
