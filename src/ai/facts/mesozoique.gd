extends RefCounted
## Faits réels : fin du Crétacé (la partie commence il y a 66 millions d'années).
## Format : {t: texte (1 à 2 phrases, vrai), clade, biome, land_use, event: Array[String] (facultatifs),
## min_year / max_year (facultatifs : le fait n'est vrai qu'entre ces dates)}. Voir fact_base.gd.

const FACTS := [
	{"t": "En cette fin du Crétacé, le climat est chaud : il n'y a pas de grande calotte de glace aux pôles, et des forêts poussent jusqu'aux hautes latitudes."},
	{"t": "Les mers sont bien plus hautes qu'aujourd'hui et noient de vastes plaines côtières sous des eaux tièdes et peu profondes.", "land_use": ["ocean", "flooded"]},
	{"t": "Le tyrannosaure a l'une des morsures les plus puissantes jamais estimées chez un animal terrestre : il broie les os de ses proies.", "clade": ["dinosaure"]},
	{"t": "Un tyrannosaure adulte pèse autour de huit tonnes ; ses jeunes, fins et rapides, chassaient probablement d'autres proies que leurs parents.", "clade": ["dinosaure"]},
	{"t": "Les hadrosaures, ces dinosaures à bec de canard, vivent en troupeaux et broient les plantes avec des centaines de dents serrées en batterie.", "clade": ["dinosaure"]},
	{"t": "Chez certains hadrosaures, une crête creuse prolonge le crâne : l'air qui y circulait leur permettait sans doute de pousser des appels graves.", "clade": ["dinosaure"]},
	{"t": "Beaucoup de dinosaures pondent dans des nids creusés au sol, regroupés en colonies, et certains s'occupent de leurs petits après l'éclosion.", "clade": ["dinosaure"]},
	{"t": "Le tricératops, plusieurs tonnes de muscles, porte trois cornes et une large collerette osseuse ; il vit à la toute fin du Crétacé.", "clade": ["dinosaure"], "biome": ["Forêt tempérée", "Savane", "Steppe"]},
	{"t": "L'ankylosaure est couvert de plaques osseuses et se défend avec une massue au bout de la queue.", "clade": ["dinosaure"]},
	{"t": "Les titanosaures sont les derniers géants à long cou ; leurs œufs, gros comme un pamplemousse, sont pondus par dizaines dans de vastes sites de ponte.", "clade": ["dinosaure"]},
	{"t": "Beaucoup de petits dinosaures carnivores portent des plumes ; le vélociraptor, par exemple, avait à peu près la taille d'un grand dindon.", "clade": ["dinosaure", "oiseau"]},
	{"t": "Les troodontidés ont, pour des dinosaures, un gros cerveau et de grands yeux, peut-être pour chasser au crépuscule.", "clade": ["dinosaure"]},
	{"t": "Dans le ciel plane Quetzalcoatlus, un ptérosaure de plus de dix mètres d'envergure ; au sol, il chassait sans doute à pied, comme une cigogne géante.", "clade": ["ptérosaure"]},
	{"t": "De vrais oiseaux volent déjà parmi les dinosaures : ce sont leurs descendants, et eux seuls, qui survivront à la fin de ce monde.", "clade": ["oiseau", "dinosaure"]},
	{"t": "Les mammifères de ce temps sont petits, souvent nocturnes, rarement plus gros qu'un blaireau : ils vivent dans l'ombre des dinosaures.", "clade": ["mammifère", "primate"]},
	{"t": "Les plantes à fleurs ont déjà conquis le monde : des magnolias et des ancêtres des platanes poussent parmi les conifères et les fougères.", "biome": ["Forêt tempérée", "Forêt tropicale"]},
	{"t": "Dans les mers règnent les mosasaures, de grands reptiles marins apparentés aux lézards, dont certains dépassent dix mètres.", "land_use": ["ocean", "flooded"], "clade": ["reptile"]},
	{"t": "En Inde, d'immenses coulées de lave, les traps du Deccan, se répandent déjà sur des centaines de milliers de kilomètres carrés et troublent le climat.", "event": ["volcanism", "disaster", "climate"]},
	{"t": "Les crocodiliens de ce temps sont des survivants : leur lignée traversera la catastrophe qui vient.", "clade": ["reptile"]},
	{"t": "Les insectes pollinisateurs, abeilles comprises, butinent déjà les fleurs de ce monde de géants."},
]
