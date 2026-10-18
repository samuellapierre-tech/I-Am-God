extends RefCounted
## Fonctions pures de la carte (sans dépendance au moteur de rendu ni aux autoloads) :
## formatage des années, conversion écran -> région avec bouclage horizontal, ères, couleurs d'espèces.
## Testées par tests/test_map.gd.

## Noms d'ères connus (contrat WorldSim.ERAS) -> index utilisé par le shader pour l'étalonnage.
const ERA_NAMES := [
	"Mésozoïque", "Cénozoïque", "Préhistoire", "Antiquité",
	"Moyen Âge", "Renaissance", "Industriel", "Moderne", "Cyberpunk", "Post-singularité",
]
## Mots-clés de repli si la simulation renomme légèrement une ère.
const ERA_KEYWORDS := [
	["méso", "meso", "dino", "crétac"], ["céno", "ceno", "mammif"], ["préhist", "prehist", "pierre"],
	["antiq"], ["moyen"], ["renais"], ["indus"], ["modern"], ["cyber"], ["singular", "post"],
]
const ERA_CYBERPUNK := 8


## Formate une année de façon lisible : « 66 M av. J.-C. », « 12 500 av. J.-C. », « 1 250 apr. J.-C. ».
static func format_year(year: float) -> String:
	var suffix := "av. J.-C." if year < 0.0 else "apr. J.-C."
	var a := absf(year)
	if a >= 1_000_000_000.0:
		return "%s Md %s" % [_format_decimal(a / 1_000_000_000.0), suffix]
	if a >= 1_000_000.0:
		return "%s M %s" % [_format_decimal(a / 1_000_000.0), suffix]
	var y := maxi(int(roundf(a)), 1) # pas d'an zéro dans le calendrier grégorien
	return "%s %s" % [group_thousands(y), suffix]


## « 1250 » -> « 1 250 » (espace comme séparateur de milliers, à la française).
static func group_thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = " " + out
		out = s[i] + out
		count += 1
	return ("-" + out) if n < 0 else out


## Un chiffre après la virgule (virgule française), supprimé s'il est nul : 66,0 -> « 66 », 1,5 -> « 1,5 ».
static func _format_decimal(v: float) -> String:
	var tenths := int(roundf(v * 10.0))
	var whole := tenths / 10
	var frac := tenths % 10
	if frac == 0:
		return group_thousands(whole)
	return "%s,%d" % [group_thousands(whole), frac]


## Ramène x dans [0, width[ (modulo positif).
static func wrap_x(x: int, width: int) -> int:
	return posmod(x, width)


## Position monde (pixels) -> cellule de grille. Bouclage horizontal, bornage vertical.
static func world_to_region(world_pos: Vector2, cell_size: float, width: int, height: int) -> Vector2i:
	var cx := int(floorf(world_pos.x / cell_size))
	var cy := int(floorf(world_pos.y / cell_size))
	return Vector2i(posmod(cx, width), clampi(cy, 0, height - 1))


## Position écran -> cellule, à partir de la transformation canvas (ex. get_canvas_transform()).
static func screen_to_region(screen_pos: Vector2, canvas_xform: Transform2D, cell_size: float,
		width: int, height: int) -> Vector2i:
	return world_to_region(canvas_xform.affine_inverse() * screen_pos, cell_size, width, height)


## Centre (en pixels monde) d'une cellule, recopié au plus près de near_x pour le bouclage.
static func region_to_world(region: Vector2i, cell_size: float, width: int, near_x: float = INF) -> Vector2:
	var p := Vector2((region.x + 0.5) * cell_size, (region.y + 0.5) * cell_size)
	if near_x != INF:
		p.x = nearest_wrapped_x(p.x, near_x, width * cell_size)
	return p


## Renvoie la copie de x (modulo period) la plus proche de ref.
static func nearest_wrapped_x(x: float, ref: float, period: float) -> float:
	return x + roundf((ref - x) / period) * period


## Nom d'ère -> index 0..9 (repli par mots-clés, 0 si inconnu).
static func era_index(era: String) -> int:
	var i := ERA_NAMES.find(era)
	if i >= 0:
		return i
	var low := era.to_lower()
	for k in ERA_KEYWORDS.size():
		for word in ERA_KEYWORDS[k]:
			if low.contains(word):
				return k
	return 0


## Pas idéaux de simulation par seconde à vitesse x1.
## Doit rester égal à WorldSim.PACING_STEPS_PER_SECOND (=> une ère dure environ une minute).
const SIM_STEPS_PER_SECOND := 20.0


## Années simulées par seconde à vitesse x1, à partir du pas idéal de la simulation
## (sim.ideal_step_years()) : c'est la simulation qui rythme le temps selon l'ère et la technologie,
## pas l'année du calendrier. ~1 Ma/s au temps des dinosaures, quelques années/s à l'ère moderne.
static func base_years_per_second(ideal_step_years: float) -> float:
	return maxf(ideal_step_years, 0.0) * SIM_STEPS_PER_SECOND


## Couleur d'une espèce : teinte dérivée de l'id par le nombre d'or.
## DOIT rester identique à species_color() dans shaders/planet.gdshader.
static func species_hue(species_id: int) -> float:
	return fposmod(float(species_id) * 0.618034 + 0.13, 1.0)


static func species_color(species_id: int) -> Color:
	if species_id < 0:
		return Color(0.5, 0.5, 0.5)
	return Color.from_hsv(species_hue(species_id), 0.75, 0.95)
