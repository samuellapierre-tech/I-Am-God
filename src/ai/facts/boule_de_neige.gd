extends RefCounted
## Faits réels : Terre boule de neige et Édiacarien (-800 à -539 millions d'années). Format : voir fact_base.gd.

const WINDOW := [-800_000_000.0, -539_000_000.0]

const FACTS := [
	{"t": "Il y a environ 720 millions d'années, la glace s'étend des pôles jusqu'aux tropiques : c'est la Terre boule de neige.", "event": ["ice_age", "climate"], "land_use": ["ice"], "max_year": -630_000_000.0},
	{"t": "Une fois blanche, la Terre renvoie la lumière du Soleil vers l'espace, ce qui la refroidit encore davantage.", "land_use": ["ice"], "max_year": -630_000_000.0},
	{"t": "Les volcans continuent de cracher du dioxyde de carbone ; sans pluie ni roche nue pour l'absorber, il s'accumule jusqu'à faire fondre la glace.", "event": ["volcanism", "climate"], "max_year": -630_000_000.0},
	{"t": "La première grande glaciation, dite sturtienne, dure environ 50 millions d'années.", "event": ["ice_age"], "max_year": -630_000_000.0},
	{"t": "Une seconde glaciation, la marinoenne, prend fin il y a environ 635 millions d'années.", "event": ["ice_age", "ice_age_end"], "max_year": -600_000_000.0},
	{"t": "La vie survit sous la glace, près des volcans et des sources chaudes, ou dans des eaux restées libres.", "clade": ["microbe", "algue"], "max_year": -630_000_000.0},
	{"t": "À la fonte, des rivières chargées de minéraux se déversent dans la mer et nourrissent sans doute une prolifération d'algues.", "clade": ["algue"], "event": ["ice_age_end", "climate"]},
	{"t": "Les éponges comptent parmi les plus anciens animaux ; leurs traces chimiques remontent peut-être à plus de 635 millions d'années.", "clade": ["éponge"]},
	{"t": "Après les glaciations, l'oxygène augmente de nouveau dans l'air et dans les océans.", "min_year": -640_000_000.0},
	{"t": "À l'Édiacarien, il y a environ 570 millions d'années, apparaissent d'étranges êtres mous en forme de frondes, de disques ou de matelas.", "clade": ["éponge", "mollusque"], "min_year": -580_000_000.0},
	{"t": "Dickinsonia, un être ovale et plat de l'Édiacarien, était bien un animal : ses fossiles ont gardé des traces de cholestérol.", "min_year": -580_000_000.0},
	{"t": "Les êtres de l'Édiacarien n'ont ni yeux, ni pattes, ni carapace : ils broutent les tapis microbiens ou filtrent l'eau.", "clade": ["éponge", "microbe"], "min_year": -580_000_000.0},
	{"t": "Rodinia se disloque pendant cette période et de nouveaux océans s'ouvrent entre ses morceaux.", "land_use": ["ocean"]},
	{"t": "Les premières traces de reptation laissées dans la vase datent de la fin de l'Édiacarien : quelque chose commence à se déplacer.", "min_year": -565_000_000.0},
	{"t": "Kimberella, un petit animal de l'Édiacarien, raclait peut-être les tapis microbiens à la façon des mollusques.", "clade": ["mollusque"], "min_year": -560_000_000.0},
	{"t": "Juste avant le Cambrien, de petits animaux comme Cloudina bâtissent les premiers tubes de calcaire.", "clade": ["éponge", "mollusque"], "min_year": -555_000_000.0},
]
