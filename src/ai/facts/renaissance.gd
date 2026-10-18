extends RefCounted
## Faits réels : Renaissance et époque moderne (1492 à 1760 environ). Format : voir fact_base.gd.

const FACTS := [
	{"t": "En 1492, Christophe Colomb atteint les Caraïbes en croyant être arrivé en Asie.", "land_use": ["ocean"], "min_year": 1492.0},
	{"t": "Les échanges entre les deux mondes apportent à l'Europe la pomme de terre, le maïs et la tomate, et à l'Amérique le cheval, le blé et la variole.", "land_use": ["farmland"], "min_year": 1493.0},
	{"t": "Les maladies venues d'Europe tuent une très grande partie des peuples autochtones d'Amérique, sans doute la majorité.", "event": ["plague"], "min_year": 1500.0},
	{"t": "L'expédition de Magellan fait le premier tour du monde ; lui-même meurt en route, et un seul navire sur cinq rentre en 1522.", "land_use": ["ocean"], "min_year": 1522.0},
	{"t": "Léonard de Vinci dissèque des corps pour dessiner muscles et os avec une précision inédite.", "event": ["discovery"], "min_year": 1500.0},
	{"t": "En 1543, Copernic place le Soleil au centre du monde ; en 1610, Galilée voit à la lunette des lunes tourner autour de Jupiter.", "event": ["discovery"], "min_year": 1543.0},
	{"t": "En 1569, Mercator invente une projection où les routes à cap constant deviennent des lignes droites : les navigateurs l'adoptent.", "min_year": 1569.0},
	{"t": "En 1602, des marchands néerlandais fondent la Compagnie des Indes orientales, l'une des premières sociétés par actions.", "land_use": ["city", "town"], "min_year": 1602.0},
	{"t": "La guerre de Trente Ans ravage l'Europe centrale de 1618 à 1648 ; certaines régions allemandes perdent un tiers de leur population ou davantage.", "event": ["war"], "min_year": 1618.0},
	{"t": "Le petit âge glaciaire bat son plein : certains hivers, la Tamise gèle et l'on tient des foires sur la glace.", "event": ["climate", "ice_age"], "land_use": ["ice", "city"], "min_year": 1600.0},
	{"t": "La grande peste de Londres en 1665, puis le grand incendie de 1666, dévastent la ville.", "event": ["plague", "disaster"], "land_use": ["city"], "min_year": 1665.0},
	{"t": "En 1676, Van Leeuwenhoek découvre au microscope des êtres minuscules qui grouillent dans une goutte d'eau.", "event": ["discovery"], "min_year": 1676.0},
	{"t": "En 1687, Newton publie ses lois du mouvement et de la gravitation universelle.", "event": ["discovery"], "min_year": 1687.0},
	{"t": "Le café et le chocolat arrivent dans les villes d'Europe ; les cafés deviennent des lieux de débats.", "land_use": ["city", "town"], "min_year": 1650.0},
	{"t": "Londres et Paris approchent ou dépassent le demi-million d'habitants à la fin du XVIIe siècle.", "land_use": ["city"], "min_year": 1680.0},
	{"t": "Les enclosures transforment les campagnes anglaises : les champs ouverts sont entourés de haies et réservés à leurs propriétaires.", "land_use": ["farmland", "pasture"], "min_year": 1500.0},
	{"t": "La traite atlantique arrache des millions d'Africains à leur terre pour les réduire en esclavage dans les plantations d'Amérique.", "land_use": ["farmland"], "min_year": 1520.0},
	{"t": "La pomme de terre, longtemps regardée avec méfiance, finit par nourrir les campagnes européennes au XVIIIe siècle.", "land_use": ["farmland", "village"], "min_year": 1700.0},
]
