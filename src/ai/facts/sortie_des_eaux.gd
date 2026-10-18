extends RefCounted
## Faits réels : Dévonien, la sortie des eaux (-419 à -359 millions d'années). Format : voir fact_base.gd.

const WINDOW := [-419_000_000.0, -359_000_000.0]

const FACTS := [
	{"t": "Le Dévonien est surnommé l'âge des poissons : requins primitifs, poissons cuirassés et poissons à nageoires charnues se partagent les mers.", "clade": ["poisson"], "land_use": ["ocean"]},
	{"t": "Dunkleosteus, un poisson cuirassé de plusieurs mètres, tranche ses proies avec des plaques osseuses en guise de dents.", "clade": ["poisson"], "min_year": -385_000_000.0},
	{"t": "Tiktaalik, un poisson à nageoires charnues, a un cou, des poumons et des nageoires assez solides pour le soutenir en eau peu profonde.", "clade": ["poisson", "amphibien"], "min_year": -380_000_000.0},
	{"t": "Il y a environ 375 millions d'années, des poissons comme Tiktaalik s'aventurent dans les eaux peu profondes des rivages.", "clade": ["poisson", "amphibien"], "land_use": ["flooded"], "min_year": -380_000_000.0},
	{"t": "Acanthostega a déjà quatre membres et huit doigts à chaque patte avant, mais il vit surtout dans l'eau.", "clade": ["amphibien"], "min_year": -368_000_000.0},
	{"t": "Ichthyostega, l'un des premiers tétrapodes, se hisse sur les berges grâce à de puissantes pattes avant.", "clade": ["amphibien"], "min_year": -368_000_000.0},
	{"t": "Les premiers arbres apparaissent : Archaeopteris forme de vraies forêts à la fin du Dévonien.", "clade": ["plante"], "biome": ["Forêt tempérée", "Forêt tropicale"], "min_year": -385_000_000.0},
	{"t": "Les racines des premiers arbres fendent les roches et fabriquent les premiers vrais sols.", "clade": ["plante"], "min_year": -385_000_000.0},
	{"t": "Les premières graines apparaissent à la fin du Dévonien : les plantes dépendent moins de l'eau pour se reproduire.", "clade": ["plante"], "min_year": -370_000_000.0},
	{"t": "Les plus anciens insectes connus vivent au Dévonien, il y a environ 400 millions d'années.", "clade": ["insecte"], "min_year": -405_000_000.0},
	{"t": "Arachnides et mille-pattes sont parmi les premiers habitants des terres, bien avant les vertébrés.", "clade": ["arthropode", "insecte"]},
	{"t": "À la fin du Dévonien, une série de crises frappe surtout les récifs et les mers chaudes : c'est la deuxième grande extinction.", "event": ["extinction", "climate"], "min_year": -375_000_000.0},
	{"t": "Les ammonites apparaissent au Dévonien ; leurs descendantes nageront dans les mers jusqu'à la fin des dinosaures.", "clade": ["mollusque"], "min_year": -410_000_000.0},
	{"t": "Les requins se diversifient au Dévonien ; leur lignée a survécu à toutes les grandes extinctions depuis.", "clade": ["poisson"]},
	{"t": "Prototaxites, une colonne de plusieurs mètres de haut qui se dresse sur les terres nues, était probablement un champignon géant.", "clade": ["plante"], "max_year": -380_000_000.0},
	{"t": "Les poissons à poumons, qui respirent l'air quand l'eau s'appauvrit, existent déjà au Dévonien et vivent encore aujourd'hui.", "clade": ["poisson"]},
]
