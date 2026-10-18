extends RefCounted
## Faits réels : Antiquité (de l'écriture, vers -3300, à 476). Format : voir fact_base.gd.

const FACTS := [
	{"t": "L'écriture naît en Mésopotamie vers 3300 avant notre ère : des comptables y notent des sacs d'orge et des têtes de bétail sur des tablettes d'argile.", "land_use": ["town", "city"], "event": ["discovery"]},
	{"t": "En Égypte, la crue annuelle du Nil dépose un limon noir et fertile ; les paysans sèment dès que l'eau se retire.", "land_use": ["farmland", "flooded"], "event": ["flood"]},
	{"t": "La grande pyramide de Khéops, élevée vers 2560 avant notre ère, restera la plus haute construction humaine pendant près de quatre mille ans.", "min_year": -2_600.0},
	{"t": "Les bâtisseurs des pyramides n'étaient pas des esclaves : c'étaient des ouvriers organisés en équipes, logés et nourris de pain et de bière.", "min_year": -2_600.0},
	{"t": "Le bronze, alliage de cuivre et d'étain, oblige à commercer loin : l'étain est rare, et les routes marchandes s'allongent."},
	{"t": "Vers 1750 avant notre ère, le roi Hammurabi fait graver ses lois sur une stèle de basalte, à la vue de tous.", "land_use": ["city", "town"], "min_year": -1_750.0},
	{"t": "Vers 1200 avant notre ère, plusieurs grandes civilisations de Méditerranée orientale s'effondrent presque en même temps ; le fer se répand ensuite.", "event": ["collapse", "war", "disaster"], "min_year": -1_200.0},
	{"t": "Les Phéniciens diffusent un alphabet de vingt-deux signes ; les Grecs l'adoptent et y ajoutent les voyelles.", "min_year": -1_000.0},
	{"t": "À Athènes, au Ve siècle avant notre ère, les citoyens votent eux-mêmes les lois ; les femmes, les esclaves et les étrangers en sont exclus.", "land_use": ["city", "town"], "min_year": -508.0},
	{"t": "Ératosthène mesure la circonférence de la Terre avec des ombres et un puits, et tombe remarquablement juste.", "min_year": -240.0},
	{"t": "En 221 avant notre ère, la dynastie Qin unifie la Chine et y impose une même écriture, de mêmes poids et de mêmes mesures.", "min_year": -221.0},
	{"t": "Les Romains bâtissent plus de 80 000 kilomètres de routes pavées ; certaines servent encore aujourd'hui.", "land_use": ["town", "city", "village"], "min_year": -312.0},
	{"t": "Le béton romain, à base de chaux et de cendre volcanique, durcit même sous l'eau : les ports de l'Empire en profitent.", "land_use": ["city", "town"], "min_year": -200.0},
	{"t": "Dans les campagnes antiques, l'immense majorité des gens sont paysans ; l'araire tirée par des bœufs gratte la terre sans la retourner.", "land_use": ["farmland", "village", "pasture"]},
	{"t": "Autour de la Méditerranée, on vit de blé, de vin et d'huile d'olive ; la viande reste un luxe des jours de fête.", "land_use": ["farmland", "village"]},
	{"t": "Par les routes de la soie, l'étoffe chinoise atteint Rome, où les moralistes s'inquiètent de tout l'or qui part vers l'Orient.", "min_year": -100.0},
	{"t": "Rome compte sans doute près d'un million d'habitants au Ier siècle, une taille jamais vue jusque-là.", "land_use": ["city", "megacity"], "min_year": -50.0},
	{"t": "En l'an 79, le Vésuve ensevelit Pompéi sous les cendres, figeant pour toujours la vie d'une ville romaine.", "event": ["volcanism", "disaster"], "min_year": 79.0},
	{"t": "La tradition chinoise attribue l'invention du papier à Cai Lun, vers l'an 105.", "event": ["discovery"], "min_year": 105.0},
	{"t": "Au IIe siècle, la peste antonine, probablement une variole, tue des millions d'habitants de l'Empire romain.", "event": ["plague"], "min_year": 165.0},
]
