extends RefCounted
## Faits réels : Carbonifère et début du Permien (-359 à -260 millions d'années). Format : voir fact_base.gd.

const WINDOW := [-359_000_000.0, -260_000_000.0]

const FACTS := [
	{"t": "Au Carbonifère, l'air contient bien plus d'oxygène qu'aujourd'hui, peut-être plus de 30 %.", "max_year": -290_000_000.0},
	{"t": "Meganeura, une libellule géante, déploie près de 70 centimètres d'envergure.", "clade": ["insecte"], "min_year": -310_000_000.0, "max_year": -295_000_000.0},
	{"t": "Arthropleura, un mille-pattes de plus de deux mètres, arpente le sol des forêts.", "clade": ["arthropode", "insecte"], "min_year": -345_000_000.0, "max_year": -290_000_000.0},
	{"t": "Les forêts du Carbonifère mêlent prêles et fougères géantes, et des lépidodendrons hauts de plus de trente mètres.", "clade": ["plante"], "biome": ["Forêt tropicale", "Forêt tempérée"], "max_year": -295_000_000.0},
	{"t": "Le bois mort s'entasse dans les marécages sans pourrir complètement : il deviendra le charbon que l'on brûlera bien plus tard.", "clade": ["plante"], "land_use": ["flooded", "wild"], "max_year": -295_000_000.0},
	{"t": "Les amphibiens règnent sur les terres humides ; certains mesurent plusieurs mètres de long.", "clade": ["amphibien"]},
	{"t": "L'œuf amniotique apparaît au Carbonifère : protégé par une coquille, il permet de pondre loin de l'eau.", "clade": ["reptile", "synapside"], "min_year": -320_000_000.0},
	{"t": "Hylonomus, petit animal semblable à un lézard, est l'un des plus anciens reptiles connus ; on l'a retrouvé dans des souches fossiles.", "clade": ["reptile"], "min_year": -315_000_000.0},
	{"t": "Très tôt, les amniotes se séparent en deux lignées : celle des reptiles et des oiseaux, et celle des synapsides, ancêtres des mammifères.", "clade": ["reptile", "synapside"], "min_year": -315_000_000.0},
	{"t": "Il y a environ 305 millions d'années, le climat s'assèche et les grandes forêts tropicales humides s'effondrent.", "event": ["climate", "extinction"], "min_year": -307_000_000.0},
	{"t": "Les continents se rassemblent en un seul supercontinent, la Pangée.", "min_year": -330_000_000.0},
	{"t": "Une longue glaciation recouvre le sud du supercontinent, pendant que des marécages chauds couvrent l'équateur.", "event": ["ice_age"], "land_use": ["ice"]},
	{"t": "Au Permien, Dimetrodon, un synapside à voile dorsale, est l'un des grands prédateurs terrestres.", "clade": ["synapside"], "min_year": -295_000_000.0, "max_year": -272_000_000.0},
	{"t": "Les premiers insectes volants apparaissent : ce sont les premiers animaux à conquérir le ciel.", "clade": ["insecte"]},
	{"t": "Les ancêtres des blattes grouillent déjà dans les litières des forêts.", "clade": ["insecte"], "min_year": -320_000_000.0},
	{"t": "Les champignons capables de digérer complètement le bois ne se répandent qu'ensuite, ce qui explique peut-être l'abondance du charbon.", "clade": ["plante"]},
]
