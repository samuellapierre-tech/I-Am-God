extends RefCounted
## Faits VRAIS de la science, classés par PHÉNOMÈNE (et non par ère) : la planète ne suit plus forcément
## l'histoire de la Terre, mais les lois qui la gouvernent restent celles qu'on connaît. Le narrateur s'en
## sert pour expliquer ce qui se passe sous les yeux du joueur. Chaque fait : 1 à 2 phrases, dit comme
## par un conteur ; le LLM peut le reformuler, jamais l'inventer.
##
## PHENOMENA : id -> {title, facts: [String]}. Les exemples terrestres sont donnés comme tels (« sur la
## Terre… ») ; le filtre d'anachronisme (epoch.gd) écarte un fait qui nommerait ce qui n'existe pas encore.

const PHENOMENA := {
	"photosynthesis": {"title": "la photosynthèse", "facts": [
		"La photosynthèse capte la lumière pour fabriquer des sucres à partir d'eau et de dioxyde de carbone ; l'oxygène n'en est qu'un déchet.",
		"Les cyanobactéries sont les premières à avoir su casser la molécule d'eau avec la lumière : c'est de là que vient l'oxygène de l'air.",
		"Presque toute l'énergie du vivant, sur une planète éclairée, passe d'abord par la photosynthèse.",
		"La couleur verte des êtres photosynthétiques vient de la chlorophylle, qui absorbe le rouge et le bleu et renvoie le vert.",
	]},
	"chemosynthesis": {"title": "la chimiosynthèse", "facts": [
		"Autour des sources hydrothermales, des microbes tirent leur énergie de gaz comme l'hydrogène sulfuré, sans aucune lumière : c'est la chimiosynthèse.",
		"La chimiosynthèse ne dépend pas du soleil : une vie fondée sur elle peut prospérer dans le noir complet des abysses.",
		"Sur la Terre, des écosystèmes entiers, vers géants et crevettes aveugles compris, vivent autour des sources chaudes grâce aux microbes chimiosynthétiques.",
		"Beaucoup de biologistes pensent que les premières cellules vivaient ainsi, de la chimie des roches et de l'eau chaude.",
	]},
	"oxygen_rise": {"title": "la montée de l'oxygène", "facts": [
		"L'oxygène monte parce que les êtres photosynthétiques en rejettent plus que les roches, les volcans et la respiration n'en consomment.",
		"Au début, l'oxygène rejeté rouille le fer dissous dans les océans : il ne s'accumule dans l'air qu'une fois ce fer épuisé.",
		"Sur la Terre, l'oxygène a commencé à s'accumuler il y a environ 2,4 milliards d'années : les géologues appellent cela la Grande Oxydation.",
		"Pour les microbes habitués à un monde sans oxygène, ce gaz est un poison : sa montée a été la première grande crise écologique.",
		"Plus d'oxygène, c'est plus d'énergie disponible : la respiration aérobie tire bien plus de chaque sucre que la fermentation.",
	]},
	"ozone": {"title": "la couche d'ozone", "facts": [
		"L'ozone est une forme d'oxygène à trois atomes ; il se forme en haute altitude quand les ultraviolets du soleil cassent les molécules d'oxygène.",
		"La couche d'ozone absorbe la plus grande partie des ultraviolets les plus durs, ceux qui brisent l'ADN.",
		"Sans ozone, la surface des terres est stérilisée par les ultraviolets : la vie reste à l'abri sous l'eau, qui les filtre.",
		"Il faut déjà beaucoup d'oxygène dans l'air pour qu'une couche d'ozone protectrice se forme.",
	]},
	"land_colonization": {"title": "la conquête des terres", "facts": [
		"La vie peut enfin sortir de l'eau quand la couche d'ozone protège les terres des ultraviolets.",
		"Sur la terre ferme, le danger n'est plus seulement la lumière mais la sécheresse : il faut une enveloppe qui retienne l'eau.",
		"Les premiers colonisateurs des terres sont des tapis de microbes, puis des mousses et des lichens qui fabriquent les premiers sols.",
		"Sur la Terre, les plantes ont gagné les terres il y a environ 470 millions d'années, avant les animaux à quatre pattes.",
		"En se décomposant, les premières plantes terrestres ont créé des sols où d'autres vies ont pu s'installer.",
	]},
	"island_speciation": {"title": "la naissance des espèces sur une île", "facts": [
		"Quand une population se retrouve isolée sur une île, elle ne se mélange plus avec le continent : avec le temps, elle devient une espèce à part.",
		"Sur une île, les animaux de grande taille ont tendance à rapetisser et les petits à grandir : c'est la règle insulaire.",
		"Les pinsons des Galápagos, venus d'un seul ancêtre, ont donné plus d'une douzaine d'espèces aux becs différents, chacune adaptée à une nourriture.",
		"Les îles isolées comptent beaucoup d'espèces qui n'existent nulle part ailleurs : les biologistes les appellent endémiques.",
		"Sans prédateurs sur leur île, certains oiseaux ont perdu l'usage du vol.",
	]},
	"continental_split": {"title": "la séparation des continents", "facts": [
		"Quand un continent se fracture, les populations qui le peuplaient sont coupées en deux : chaque moitié évolue désormais seule.",
		"La séparation des terres multiplie les espèces : une même lignée donne des cousins différents de part et d'autre d'un océan nouveau.",
		"Les marsupiaux d'Australie se sont diversifiés seuls pendant des dizaines de millions d'années, après que leur continent s'est isolé.",
		"Quand deux continents se rejoignent, c'est l'inverse : des faunes qui ne se connaissaient pas se rencontrent, et certaines espèces en évincent d'autres.",
	]},
	"plate_tectonics": {"title": "la tectonique des plaques", "facts": [
		"La surface d'une planète rocheuse comme la Terre est faite de plaques qui glissent de quelques centimètres par an sur un manteau chaud.",
		"Là où deux plaques se heurtent, les montagnes s'élèvent ; là où elles s'écartent, un océan naît.",
		"Les volcans et les séismes se concentrent le long des frontières des plaques.",
		"Les continents de la Terre se sont rassemblés plusieurs fois en un seul supercontinent, puis séparés : c'est le cycle des supercontinents.",
	]},
	"decline_predation": {"title": "le déclin par la prédation", "facts": [
		"Quand les prédateurs se multiplient plus vite que leurs proies ne se reproduisent, les proies déclinent, puis les prédateurs, faute de nourriture.",
		"Les populations de proies et de prédateurs montent et descendent souvent en cycles décalés, comme les lièvres et les lynx du Grand Nord.",
		"Un prédateur nouveau venu, contre lequel les proies n'ont aucune défense, peut en éteindre plusieurs espèces en peu de temps.",
		"Une espèce qui grandit lentement et n'a que peu de petits résiste mal à une forte prédation.",
	]},
	"decline_climate": {"title": "le déclin par le climat", "facts": [
		"Chaque espèce vit dans une plage de températures ; si le climat sort de cette plage plus vite qu'elle ne s'adapte, elle décline.",
		"Quand le climat change, les espèces migrent vers les conditions qui leur conviennent, si un chemin existe ; sinon, elles reculent.",
		"Les grands animaux, qui se reproduisent lentement, souffrent souvent plus des changements rapides de climat que les petits.",
		"Un refroidissement fait aussi baisser le niveau des mers et assèche les terres : ce sont souvent ces effets qui tuent, plus que le froid lui-même.",
	]},
	"decline_competition": {"title": "le déclin par la concurrence", "facts": [
		"Deux espèces qui mangent la même chose au même endroit ne peuvent pas cohabiter longtemps : l'une finit par évincer l'autre.",
		"Les biologistes appellent cela le principe d'exclusion compétitive.",
		"Pour éviter la concurrence, des espèces voisines se partagent souvent les ressources : l'une mange en hauteur, l'autre au sol, ou à d'autres heures.",
		"Une espèce généraliste, qui mange de tout, l'emporte souvent quand les ressources se raréfient.",
	]},
	"greenhouse": {"title": "l'effet de serre", "facts": [
		"Le sol chauffé par le soleil renvoie de la chaleur sous forme d'infrarouges ; des gaz comme le dioxyde de carbone, la vapeur d'eau et le méthane en retiennent une partie : c'est l'effet de serre.",
		"Sans effet de serre, la Terre aurait une température moyenne d'environ -18 °C au lieu d'environ +15 °C.",
		"Plus il y a de dioxyde de carbone dans l'air, plus la planète retient de chaleur ; les volcans en rejettent, les roches et la vie en absorbent.",
		"Le méthane retient beaucoup plus de chaleur que le dioxyde de carbone, mais il disparaît plus vite de l'air.",
		"Un effet de serre qui s'emballe peut rendre une planète invivable : Vénus, étouffée par le dioxyde de carbone, dépasse 450 °C.",
	]},
	"carbon_cycle": {"title": "le thermostat du carbone", "facts": [
		"La pluie dissout lentement les roches et entraîne le dioxyde de carbone de l'air vers le fond des océans : c'est ainsi qu'une planète se refroidit.",
		"Quand il fait chaud, les roches s'altèrent plus vite et retirent plus de carbone de l'air ; quand il fait froid, moins : ce thermostat agit sur des millions d'années.",
		"Les volcans rendent à l'air le carbone que les roches ont enfoui, et bouclent le cycle.",
		"Les coquilles et les squelettes calcaires des êtres marins enferment du carbone au fond des mers pour très longtemps.",
	]},
	"ice_age": {"title": "les glaciations", "facts": [
		"La glace renvoie la lumière du soleil vers l'espace : plus il y a de glace, plus la planète se refroidit, et plus la glace s'étend.",
		"Sur la Terre, de petites variations de l'orbite et de l'inclinaison de l'axe rythment les glaciations, tous les 100 000 ans environ.",
		"Pendant une glaciation, l'eau prise dans les glaces fait baisser le niveau des mers de plus de cent mètres.",
		"Une planète peut geler presque entièrement si sa glace descend jusqu'aux tropiques : c'est ce qu'on appelle une Terre boule de neige.",
		"Les volcans finissent par sauver une planète gelée : leur dioxyde de carbone s'accumule jusqu'à faire fondre la glace.",
	]},
	"sea_level": {"title": "le niveau des mers", "facts": [
		"Le niveau des mers monte quand les glaces fondent et quand l'eau se réchauffe, car l'eau chaude prend plus de place.",
		"Quand la mer monte, elle noie les plaines côtières et crée des mers peu profondes, très riches en vie.",
		"Quand la mer baisse, des ponts de terre apparaissent entre les continents, et les espèces terrestres les traversent.",
	]},
	"sun_aging": {"title": "le vieillissement du Soleil", "facts": [
		"Une étoile comme le Soleil brûle de l'hydrogène en son cœur ; à mesure que de l'hélium s'y accumule, le cœur se contracte, chauffe, et l'étoile brille davantage.",
		"Le Soleil gagne environ 1 % de luminosité tous les cent millions d'années.",
		"Il y a 4,6 milliards d'années, le jeune Soleil brillait environ 30 % moins qu'aujourd'hui.",
		"Dans environ un milliard d'années, le Soleil chauffera assez la Terre pour faire disparaître ses océans et la vie complexe.",
		"Dans environ cinq milliards d'années, le Soleil enflera en géante rouge, avant de finir en naine blanche.",
	]},
	"mass_extinction": {"title": "les extinctions de masse", "facts": [
		"Une extinction de masse survient quand le milieu change trop vite pour que la plupart des espèces s'adaptent : volcanisme géant, impact, effondrement du climat.",
		"La Terre a connu cinq grandes extinctions ; la plus grave, il y a 252 millions d'années, a emporté autour de neuf espèces marines sur dix.",
		"Après chaque extinction de masse, les survivants se diversifient vite pour occuper les places laissées vides.",
		"Les espèces généralistes, petites et nombreuses, traversent mieux les crises que les géants spécialisés.",
	]},
	"adaptive_radiation": {"title": "les radiations évolutives", "facts": [
		"Quand une lignée trouve un monde sans concurrents, elle se diversifie en peu de temps en une foule d'espèces : c'est une radiation évolutive.",
		"Les mammifères se sont diversifiés très vite après la disparition des dinosaures non aviens.",
		"Une innovation, comme la mâchoire, l'œuf à coquille ou le vol, ouvre souvent la voie à une radiation.",
	]},
	"natural_selection": {"title": "la sélection naturelle", "facts": [
		"Les individus d'une espèce diffèrent un peu les uns des autres ; ceux dont les traits conviennent le mieux au milieu laissent plus de descendants.",
		"Les mutations, des erreurs de copie de l'ADN, apportent les nouveautés ; la sélection trie celles qui restent.",
		"L'évolution n'a pas de but : elle répond au milieu du moment, génération après génération.",
		"Des lignées sans parenté peuvent finir par se ressembler si elles vivent de la même façon : c'est la convergence, comme les ailes des oiseaux et des chauves-souris.",
	]},
	"food_chain": {"title": "la chaîne alimentaire", "facts": [
		"À chaque maillon de la chaîne alimentaire, environ un dixième seulement de l'énergie passe au suivant : c'est pourquoi les grands prédateurs sont rares.",
		"Les producteurs, qui fabriquent leur matière à partir de la lumière ou de la chimie, nourrissent tous les autres.",
		"Les décomposeurs, microbes et champignons, recyclent la matière morte et rendent ses éléments au sol et à l'eau.",
	]},
	"endosymbiosis": {"title": "les cellules à noyau", "facts": [
		"Les cellules complexes, à noyau, sont nées d'une association : une grande cellule a gardé en elle une bactérie qui est devenue sa centrale énergétique.",
		"Les mitochondries ont encore leur propre petit ADN, souvenir de leur passé de bactéries libres.",
		"Les chloroplastes des plantes descendent eux aussi de cyanobactéries capturées.",
	]},
	"multicellularity": {"title": "la vie à plusieurs cellules", "facts": [
		"Les êtres à plusieurs cellules sont nés de cellules qui restaient collées après s'être divisées, puis se sont partagé le travail.",
		"La vie à plusieurs cellules est apparue plusieurs fois, de façon indépendante, chez les algues, les champignons et les animaux.",
		"Un corps fait de nombreuses cellules peut grandir, se spécialiser et vivre plus longtemps qu'une cellule seule.",
	]},
	"sapience": {"title": "l'intelligence", "facts": [
		"Un grand cerveau coûte cher : il consomme beaucoup d'énergie, et seules les espèces qui en tirent un gros avantage le gardent.",
		"La vie en groupe, où il faut se souvenir des alliés et des rivaux, est l'une des forces qui poussent vers l'intelligence.",
		"Sur la Terre, l'intelligence est apparue plusieurs fois à des degrés divers : chez les primates, les corvidés, les pieuvres ou les dauphins.",
		"Le langage permet de transmettre ce qu'on a appris sans attendre les gènes : la culture évolue alors bien plus vite que le corps.",
	]},
}


## Identifiants des phénomènes.
static func ids() -> Array:
	return PHENOMENA.keys()


## Faits d'un phénomène, avec un identifiant « id#indice ».
static func facts_of(id: String) -> Array:
	var out := []
	var raw: Array = PHENOMENA.get(id, {}).get("facts", [])
	for i in raw.size():
		out.append({"id": "%s#%d" % [id, i], "t": str(raw[i]), "phenomenon": id})
	return out
