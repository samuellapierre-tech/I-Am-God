extends RefCounted
## Description procédurale d'une espèce : deux ou trois phrases en français, accordées, qui
## disent son apparence puis son mode de vie, d'après ses traits. Le sujet est la tête de son nom
## vernaculaire (« Ce rampeur… », « Cette ombrelle… ») ; les variantes viennent de `gseed`.

const Naming := preload("res://src/life/naming.gd")

const NUMBERS := ["aucun", "un", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf",
	"dix", "onze", "douze", "treize", "quatorze", "quinze", "seize", "dix-sept", "dix-huit",
	"dix-neuf", "vingt", "vingt et un", "vingt-deux", "vingt-trois", "vingt-quatre", "vingt-cinq",
	"vingt-six", "vingt-sept", "vingt-huit", "vingt-neuf", "trente"]
## Formes de cellule (accordées à « cellule »).
const CELL_SHAPES := ["ronde", "en bâtonnet", "spiralée", "en virgule", "en chapelet", "étoilée",
	"ovale", "en filament", "à flagelle", "en tonnelet", "anguleuse", "en croissant"]

## Tailles (seuils de `size`) : [masc., fém.] ; tournures valables après « est » comme en apposition.
const SIZES := [
	[0.03, [["minuscule", "minuscule"], ["à peine visible", "à peine visible"], ["gros comme un grain de sable", "grosse comme un grain de sable"]]],
	[0.06, [["de la taille d'un ongle", "de la taille d'un ongle"], ["long comme un doigt", "longue comme un doigt"]]],
	[0.12, [["de la taille d'une main", "de la taille d'une main"], ["long comme la main", "longue comme la main"]]],
	[0.22, [["long comme un bras", "longue comme un bras"], ["de la taille d'un avant-bras", "de la taille d'un avant-bras"]]],
	[0.35, [["de la taille d'un enfant", "de la taille d'un enfant"], ["aussi lourd qu'un rocher", "aussi lourde qu'un rocher"]]],
	[0.5, [["aussi grand qu'un homme", "aussi grande qu'un homme"], ["de la taille d'un homme", "de la taille d'un homme"]]],
	[0.65, [["deux fois plus grand qu'un homme", "deux fois plus grande qu'un homme"], ["lourd comme une charrette chargée", "lourde comme une charrette chargée"]]],
	[0.82, [["haut comme une maison", "haute comme une maison"], ["long comme trois barques", "longue comme trois barques"]]],
	[9.0, [["aussi lourd qu'une colline", "aussi lourde qu'une colline"], ["plus grand que tout ce qui foule le sol", "plus grande que tout ce qui foule le sol"], ["haut comme un arbre", "haute comme un arbre"]]],
]
const PLANT_SIZES := [
	[0.12, ["ras", "rase"]], [0.25, ["haut comme un genou", "haute comme un genou"]],
	[0.4, ["haut comme un homme", "haute comme un homme"]], [0.7, ["haut comme une maison", "haute comme une maison"]],
	[9.0, ["haut comme une tour", "haute comme une tour"]],
]
## Lieux (groupe nominal avec article) selon le milieu.
const PLACES := {
	"abysses": ["les abysses glacés", "les grands fonds obscurs", "la nuit des grands fonds", "les plaines abyssales"],
	"mer peu profonde": ["les eaux tièdes des récifs", "les hauts-fonds", "les lagons", "les eaux claires du rivage", "les herbiers côtiers"],
	"eau douce": ["les marais", "les rivières lentes", "les lacs", "les estuaires vaseux", "les eaux noires des tourbières"],
	"terre_froid": ["les toundras", "les plaines gelées", "les steppes balayées par le vent"],
	"terre": ["les forêts", "les plaines", "les collines", "les vallées humides", "les sous-bois"],
	"terre_chaud": ["les déserts", "les savanes brûlantes", "les forêts chaudes", "les dunes"],
	"sources": ["les cheminées hydrothermales", "les sources chaudes des grands fonds", "les fumerolles sous-marines"],
}


static func _e(fem: bool) -> String:
	return "e" if fem else ""


static func _cap(s: String) -> String:
	return s if s.is_empty() else s.substr(0, 1).to_upper() + s.substr(1)


static func _pick(arr: Array, g: RandomNumberGenerator) -> Variant:
	return arr[g.randi_range(0, arr.size() - 1)]


## « de » + groupe nominal, avec contraction (des, du, de la, de l').
static func de(np: String) -> String:
	if np.begins_with("les "):
		return "des " + np.substr(4)
	if np.begins_with("le "):
		return "du " + np.substr(3)
	return "de " + np


static func _number(n: int, feminine: bool) -> String:
	if n == 1:
		return "une" if feminine else "un"
	return NUMBERS[n] if n < NUMBERS.size() else str(n)


static func _place_np(t: Dictionary, g: RandomNumberGenerator, land_only := false) -> String:
	var m := String(t.get("milieu", "terre"))
	var key := m
	if String(t.get("metabolism", "")) == "chimiosynthèse":
		key = "sources"
	elif m == "terre" or m == "air" or land_only:
		var temp := float(t.get("temp_opt", 0.5))
		key = "terre_froid" if temp < 0.3 else ("terre_chaud" if temp > 0.72 else "terre")
	return _pick(PLACES.get(key, PLACES["terre"]), g)


## Couverture : [groupe nominal indéfini, groupe possessif, féminin, pluriel].
static func _cover_np(t: Dictionary, g: RandomNumberGenerator) -> Array:
	match String(t.get("covering", "")):
		"membrane":
			return ["une membrane", "sa membrane", true, false]
		"carapace":
			if String(t.get("skeleton", "")) == "coquille":
				return ["une coquille", "sa coquille", true, false]
			return ["une carapace", "sa carapace", true, false]
		"écailles":
			return ["des écailles", "ses écailles", true, true]
		"plumes":
			return ["un plumage", "son plumage", false, false] if g.randf() < 0.5 else ["des plumes", "ses plumes", true, true]
		"poils":
			return ["un pelage", "son pelage", false, false] if g.randf() < 0.6 else ["une fourrure", "sa fourrure", true, false]
		"peau nue":
			return ["une peau lisse", "sa peau lisse", true, false] if g.randf() < 0.5 else ["une peau nue", "sa peau nue", true, false]
		"écorce":
			return ["une écorce", "son écorce", true, false]
		"frondes":
			return ["des frondes", "ses frondes", true, true]
	return ["un corps", "son corps", false, false]


## Couleur et motif accordés à un nom (« bleue rayée de noir »).
static func _colored(t: Dictionary, fem: bool, plural: bool) -> String:
	var s := Naming.color_adj(t, fem, plural)
	var pat := String(t.get("pattern", "uni"))
	if pat != "uni":
		s += " " + Naming.agree(Naming.ADJ[pat], fem, plural) + " " + Naming.accent(t)
	return s


static func _size_phrase(t: Dictionary, fem: bool, g: RandomNumberGenerator) -> String:
	var size := float(t.get("size", 0.3))
	for row in SIZES:
		if size < float(row[0]):
			var forms: Array = _pick(row[1], g)
			return forms[1 if fem else 0]
	return ""


static func _plant_size(t: Dictionary, fem: bool) -> String:
	var size := float(t.get("size", 0.3))
	for row in PLANT_SIZES:
		if size < float(row[0]):
			return row[1][1 if fem else 0]
	return ""


## Membres : proposition verbale commençant par « et » (vide si aucun membre à décrire).
static func _limbs_clause(t: Dictionary, g: RandomNumberGenerator) -> String:
	var n := int(t.get("limbs", 0))
	var skel := String(t.get("skeleton", ""))
	var loco := String(t.get("locomotion", ""))
	var p := String(t.get("body_plan", ""))
	if p == "radial":
		return " et déploie %s tentacules" % _number(n, false) if n > 0 else ""
	if p != "bilatéral":
		return ""
	if bool(t.get("wings", false)):
		if skel == "exosquelette":
			return " et bat de quatre ailes translucides" if g.randf() < 0.5 else " et replie deux paires d'ailes sur son dos"
		var w := "emplumées" if String(t.get("covering", "")) == "plumes" else "membraneuses"
		return " et déploie deux ailes %s" % w
	if n == 0:
		if loco == "rampe":
			return " et n'a ni pattes ni nageoires"
		return ""
	if skel == "exosquelette":
		return " et avance sur %s pattes articulées" % _number(n, true)
	if skel == "endosquelette":
		if loco == "nage":
			return " et rame de ses %s nageoires" % _number(n, true)
		if n == 2:
			return " et se tient sur deux pattes"
		return " et se déplace sur %s pattes" % _number(n, true) if loco != "saut" \
			else " et bondit sur de longues pattes arrière"
	return " et agite %s bras souples" % _number(n, false)


## Textures des frondes (féminin pluriel) et formes des tapis végétaux.
const FROND_TEXTURES := ["veloutées", "luisantes", "cassantes", "duveteuses", "gorgées d'eau",
	"cireuses", "fines comme des cheveux", "enroulées en crosse", "dentelées", "translucides"]
## [nom pluriel, féminin ?]
const MATS := [["coussins", false], ["tapis", false], ["plaques", true], ["rosettes", true],
	["croûtes", true], ["touffes", true], ["festons", false]]


## Apparence d'un producteur (mousse, algue, plante, arbre).
static func _producer_look(t: Dictionary, subj: String, s_low: String, fem: bool, g: RandomNumberGenerator) -> String:
	var p := String(t.get("body_plan", ""))
	var cover := _cover_np(t, g)
	var col := _colored(t, bool(cover[2]), bool(cover[3]))
	var col_fp := Naming.color_adj(t, true, true)
	var tex: String = _pick(FROND_TEXTURES, g)
	var head := s_low.split(" ")[s_low.split(" ").size() - 1]
	var mats := MATS.filter(func(m): return not String(m[0]).begins_with(head.substr(0, 4)))
	var mat_row: Array = _pick(mats, g)
	var mat: String = mat_row[0]
	var mat_f := bool(mat_row[1])
	var size := _plant_size(t, fem)
	if p == "colonial" and String(t.get("habitat", "")) == "land":
		match g.randi_range(0, 3):
			0:
				return "%s forme sur la roche nue des %s %s de frondes %s %s." % [subj, mat, "rases" if mat_f else "ras", col_fp, tex]
			1:
				return "%s n'est qu'un feutre de minuscules frondes %s, %s, collé à la pierre." % [subj, col_fp, tex]
			2:
				return "%s étend sur le sol des %s %s de frondes %s, %s d'un doigt." % [subj, mat,
					"spongieuses" if mat_f else "spongieux", col_fp, "épaisses" if mat_f else "épais"]
		return "%s, %s et %s, tapisse la roche de frondes %s %s." % [subj, "rase" if fem else "ras",
			"serrée" if fem else "serré", col_fp, tex]
	if String(t.get("habitat", "")) != "land":
		var form: String = _pick(["souples comme des rubans", "fines comme de la soie", "longues et flottantes",
			"larges comme des mains", "fendues en lanières", "perlées de bulles d'air"], g)
		if bool(cover[3]):
			return "%s étire dans l'eau %s %s, %s." % [subj, cover[0], col, form]
		return "%s étire dans l'eau %s %s, souple et flottante." % [subj, cover[0], col]
	if String(t.get("covering", "")) == "écorce":
		var bark := Naming.color_adj(t, true, false) if float(t.get("val", 0.5)) < 0.5 else String(_pick(["grise", "crevassée", "lisse", "rugueuse", "écailleuse"], g))
		match g.randi_range(0, 2):
			0:
				return "%s, %s, dresse un tronc à l'écorce %s couronné de frondes %s." % [subj, size, bark, col_fp]
			1:
				return "%s élève, %s, un fût à l'écorce %s d'où retombent des frondes %s %s." % [subj, size, bark, col_fp, tex]
		return "Sous son écorce %s, %s, %s, porte une ramure de frondes %s." % [bark, s_low, size, col_fp]
	match g.randi_range(0, 2):
		0:
			return "%s, %s, déploie %s %s autour d'une tige unique." % [subj, size, cover[0], col]
		1:
			return "%s dresse une tige %s chargée de frondes %s %s." % [subj, "souple" if g.randf() < 0.5 else "raide", col_fp, tex]
	return "%s, %s, ouvre en éventail des frondes %s %s." % [subj, size, col_fp, tex]


## Phrase 1 : l'apparence.
static func _appearance(t: Dictionary, subj: String, fem: bool, g: RandomNumberGenerator) -> String:
	var p := String(t.get("body_plan", "bilatéral"))
	var met := String(t.get("metabolism", "hétérotrophe"))
	var col_f := Naming.color_adj(t, true, false)
	var col_fp := Naming.color_adj(t, true, true)
	var s_low := subj.substr(0, 1).to_lower() + subj.substr(1)
	if p == "unicellulaire":
		# Forme et longueur de la cellule (en microns) : la variété vient du génome.
		var shape: String = CELL_SHAPES[posmod(int(t.get("gseed", 0)) >> 7, CELL_SHAPES.size())]
		var microns := clampi(int(round(float(t.get("size", 0.01)) * 500.0)), 1, 30)
		var length := ("longue de %s microns" % _number(microns, false)) if microns > 1 else "longue d'un micron"
		var cell := "cellule %s %s" % [col_f, shape]
		match g.randi_range(0, 4):
			0:
				return "%s n'est qu'une %s, invisible à l'œil nu." % [subj, cell]
			1:
				return "Invisible à l'œil nu, %s est une simple %s, %s." % [s_low, cell, length]
			2:
				return "%s tient %s dans une %s, mais ses milliards de semblables teintent l'eau." % [
					subj, "tout entière" if fem else "tout entier", cell]
			3:
				return "%s est une %s, %s, que seule une loupe révélerait." % [subj, cell, length]
		return "%s se réduit à une %s, %s, enveloppée d'une fine membrane." % [subj, cell, length]
	if met != "hétérotrophe":
		return _producer_look(t, subj, s_low, fem, g)
	var size := _size_phrase(t, fem, g)
	if p == "colonial" or p == "radial":
		var cover := _cover_np(t, g)
		var col := _colored(t, bool(cover[2]), bool(cover[3]))
		var body := "une colonie de cellules %s" % col_fp if p == "colonial" else "un corps mou en forme de cloche %s" % Naming.color_adj(t, false, false)
		if p == "radial" and String(t.get("locomotion", "")) == "fixe":
			body = "un calice charnu %s" % Naming.color_adj(t, false, false)
		return "%s, %s, n'a ni tête ni cerveau : %s n'est qu'%s%s." % [subj, size, "elle" if fem else "il",
			body, _limbs_clause(t, g)]
	var cover := _cover_np(t, g)
	var col := _colored(t, bool(cover[2]), bool(cover[3]))
	var limbs := _limbs_clause(t, g)
	match g.randi_range(0, 2):
		0:
			return "%s, %s, porte %s %s%s." % [subj, size, cover[0], col, limbs]
		1:
			return "%s porte %s %s%s ; %s est %s." % [subj, cover[0], col, limbs, "elle" if fem else "il", size]
	return "On %s reconnaît à %s %s : %s est %s%s." % ["la" if fem else "le", cover[1], col, s_low, size, limbs]


## Proposition « se déplace dans tel lieu ».
static func _moves(t: Dictionary, fem: bool, g: RandomNumberGenerator) -> String:
	var loco := String(t.get("locomotion", ""))
	var water := ["abysses", "mer peu profonde", "eau douce"].has(String(t.get("milieu", "")))
	var place := _place_np(t, g, loco == "vol")
	var prod := String(t.get("metabolism", "")) != "hétérotrophe"
	match loco:
		"nage":
			return _pick(["nage dans %s" % place, "file entre deux eaux dans %s" % place, "patrouille %s" % place], g)
		"rampe":
			if water:
				return _pick(["fouille la vase %s" % de(place), "rampe sur le fond %s" % de(place)], g)
			return _pick(["rampe à travers %s" % place, "se faufile sous les pierres %s" % de(place)], g)
		"marche":
			if water:
				return "arpente le fond %s" % de(place)
			return _pick(["arpente %s" % place, "parcourt %s" % place, "sillonne %s" % place], g)
		"saut":
			return _pick(["bondit à travers %s" % place, "progresse par bonds dans %s" % place], g)
		"vol":
			return _pick(["plane au-dessus %s" % de(place), "sillonne le ciel au-dessus %s" % de(place)], g)
		"dérive":
			return _pick(["dérive dans %s" % place, "flotte au gré des courants %s" % de(place)], g)
	if prod:
		if water:
			return _pick(["s'accroche aux rochers %s" % de(place), "tapisse le fond %s" % de(place)], g)
		return _pick(["pousse dans %s" % place, "couvre le sol %s" % de(place)], g)
	return _pick(["vit ancré%s au fond %s" % [_e(fem), de(place)], "reste fixé%s aux rochers %s" % [_e(fem), de(place)]], g)


## Climat préféré, d'après temp_opt et temp_tol.
static func _climate(t: Dictionary, pr: String) -> String:
	var temp := float(t.get("temp_opt", 0.5))
	var tol := float(t.get("temp_tol", 0.25))
	var where := "le grand froid"
	if temp >= 0.8:
		where = "les chaleurs extrêmes"
	elif temp >= 0.65:
		where = "la chaleur"
	elif temp >= 0.45:
		where = "la tiédeur"
	elif temp >= 0.25:
		where = "la fraîcheur"
	if tol > 0.36:
		return "%s préfère %s mais supporte presque tous les climats." % [pr, where]
	if tol < 0.16:
		return "%s ne supporte que %s et dépérit ailleurs." % [pr, where]
	return "%s recherche %s." % [pr, where]


## Moment d'activité des animaux (incise), tiré de la graine de l'espèce.
static func _when(t: Dictionary) -> String:
	if String(t.get("metabolism", "")) != "hétérotrophe" or String(t.get("body_plan", "")) == "unicellulaire":
		return ""
	return ["", ", surtout la nuit,", ", à l'aube,", ", au crépuscule,", "", ", par tous les temps,",
		", à la belle saison,"][posmod(int(t.get("gseed", 0)) >> 11, 7)]


static func _social(t: Dictionary, g: RandomNumberGenerator) -> String:
	var p := String(t.get("body_plan", ""))
	if p == "unicellulaire" or String(t.get("metabolism", "")) != "hétérotrophe":
		return ""
	var s := float(t.get("sociability", 0.5))
	var loco := String(t.get("locomotion", ""))
	var exo := String(t.get("skeleton", "")) == "exosquelette"
	if p != "bilatéral" or loco == "fixe":
		return " en colonies serrées" if s > 0.6 else ""
	if s < 0.2:
		return " en solitaire"
	if s < 0.45:
		return _pick([" par deux", " en petits groupes"], g)
	var big := s > 0.8
	if loco == "nage":
		return " en immenses bancs" if big else " en bancs"
	if loco == "vol":
		if exo:
			return " en nuées" if big else " en essaims"
		return " en vastes volées" if big else " en volées"
	match String(t.get("diet", "")):
		"herbivore":
			return " en troupeaux immenses" if big else " en hardes"
		"carnivore":
			return " en meutes"
	return " en colonies bruyantes" if big else " en groupes"


static func _diet(t: Dictionary, fem: bool, g: RandomNumberGenerator) -> String:
	var met := String(t.get("metabolism", "hétérotrophe"))
	var pr := "elle" if fem else "il"
	if met == "photosynthèse":
		if bool(t.get("oxygenic", false)):
			return _pick([" et se nourrit de lumière en rejetant de l'oxygène", " et boit la lumière du jour en exhalant de l'oxygène"], g)
		return " et se nourrit de lumière"
	if met == "chimiosynthèse":
		return _pick([" et tire son énergie des minéraux qui jaillissent de la roche", " et se nourrit du soufre et du fer dissous, sans jamais voir le jour"], g)
	var water := ["abysses", "mer peu profonde", "eau douce"].has(String(t.get("milieu", "")))
	var loco := String(t.get("locomotion", ""))
	var w: Array = t.get("weapons", [])
	match String(t.get("diet", "")):
		"herbivore":
			if loco == "fixe" or String(t.get("body_plan", "")) != "bilatéral":
				return " et filtre l'eau pour en retenir le plancton"
			if water:
				return _pick([" et racle les algues", " et broute les tapis de microbes"], g)
			if loco == "vol":
				return " et se nourrit de graines et de pousses"
			return _pick([" et broute les plantes basses", " et se nourrit de feuillage", " et arrache les pousses tendres"], g)
		"carnivore":
			if loco == "fixe" or String(t.get("body_plan", "")) != "bilatéral":
				var still := [" et saisit au passage ce que le courant lui apporte", " et guette ses proies sans jamais bouger"]
				if w.has("venin"):
					still.append(" et foudroie de son venin les imprudents qui l'effleurent")
				return _pick(still, g)
			var opts := [" et chasse à l'affût", " et traque ses proies sans relâche"]
			if w.has("crocs"):
				opts.append(" et déchire ses proies de ses crocs")
			if w.has("venin"):
				opts.append(" et paralyse ses proies de son venin")
			if w.has("pinces"):
				opts.append(" et saisit ses proies entre ses pinces")
			if w.has("griffes"):
				opts.append(" et terrasse ses proies de ses griffes")
			if loco == "vol":
				opts.append(" et fond sur ses proies depuis le ciel")
			return _pick(opts, g)
	return _pick([" et se nourrit de tout ce qu'%s trouve" % pr, " et mange un peu de tout", " et ne dédaigne ni les plantes ni les petites proies"], g)


static func _lifespan_text(years: float, plant: bool) -> String:
	if years < 0.02:
		return "quelques jours"
	if years < 0.1:
		return "quelques semaines"
	if years < 0.6:
		return "une saison à peine"
	if years < 1.5:
		return "à peine un an"
	if years < 4.0:
		return "deux ou trois ans"
	if years < 8.0:
		return "environ cinq ans"
	if years < 15.0:
		return "une dizaine d'années"
	if years < 30.0:
		return "une vingtaine d'années"
	if years < 60.0:
		return "une quarantaine d'années"
	if years < 130.0:
		return "près d'un siècle"
	return "des siècles" if plant else "plus d'un siècle"


## Phrase 3 : un détail marquant (sens, lumière, sang, esprit, longévité, défense).
static func _detail(t: Dictionary, fem: bool, g: RandomNumberGenerator) -> String:
	var pr := "Elle" if fem else "Il"
	var obj := "la" if fem else "le"
	var p := String(t.get("body_plan", ""))
	var met := String(t.get("metabolism", "hétérotrophe"))
	var senses: Array = t.get("senses", [])
	var w: Array = t.get("weapons", [])
	var out := []
	if p == "unicellulaire":
		out.append("%s se divise en deux toutes les quelques heures." % pr)
		out.append(_climate(t, pr))
		if float(t.get("adaptability", 0.5)) > 0.7:
			out.append("Presque rien ne %s tue : ni le froid, ni le sel, ni les années de disette." % obj)
		if bool(t.get("anaerobic", false)):
			out.append("L'oxygène, pour %s, est un poison." % ("elle" if fem else "lui"))
		if bool(t.get("biolum", false)):
			out.append("La nuit, ses colonies font luire l'eau d'une lueur %s." % Naming.color_adj(t, true, false))
		return _pick(out, g)
	if senses.has("écholocation"):
		out.append("Dans le noir, %s se repère à l'écho de ses propres cris." % pr.to_lower())
	if senses.has("électroréception"):
		out.append("%s perçoit les champs électriques de ses proies, même dans l'eau trouble." % pr)
	if p == "bilatéral" and not senses.has("yeux") and met == "hétérotrophe":
		out.append("%s n'a pas d'yeux et se fie au toucher." % pr)
	if bool(t.get("biolum", false)):
		out.append("Son corps luit d'une lueur %s dans l'obscurité." % Naming.color_adj(t, true, false))
	if bool(t.get("warm_blooded", false)):
		out.append("Son sang chaud %s garde %s même par grand froid." % [obj, "active" if fem else "actif"])
	var intel := float(t.get("intelligence", 0.0))
	if intel >= 0.5:
		out.append("Son regard trahit une intelligence troublante.")
	elif intel >= 0.3:
		out.append("%s apprend vite et n'oublie jamais un danger." % pr)
	if w.has("venin") and String(t.get("diet", "")) != "carnivore":
		out.append("Son venin décourage les prédateurs.")
	if w.has("épines"):
		out.append("Ses épines dissuadent quiconque voudrait %s croquer." % obj)
	if w.has("cornes") and met == "hétérotrophe":
		out.append("À la saison des amours, les mâles s'affrontent à coups de cornes.")
	var fert := float(t.get("fertility", 0.5))
	if met == "hétérotrophe" and p == "bilatéral":
		if fert > 0.75 and not bool(t.get("warm_blooded", false)):
			out.append("Chaque ponte compte des milliers d'œufs, dont bien peu survivent.")
		elif fert < 0.3 and bool(t.get("warm_blooded", false)):
			out.append("%s n'élève qu'un petit à la fois, avec un soin jaloux." % pr)
	var plant := met != "hétérotrophe"
	out.append("%s vit %s." % [pr, _lifespan_text(float(t.get("lifespan", 1.0)), plant)])
	out.append(_climate(t, pr))
	if plant:
		var land := String(t.get("habitat", "")) == "land"
		out.append_array([
			"Ses spores voyagent au gré du %s." % ("vent" if land else "courant"),
			"%s reverdit après chaque %s." % [pr, "sécheresse" if land else "tempête"],
			"%s abrite toute une foule de vies minuscules." % pr,
		])
		if land and String(t.get("body_plan", "")) == "radial":
			out.append("Ses racines retiennent la terre et fendent la roche.")
		if bool(t.get("oxygenic", false)):
			out.append("Chaque jour, %s rend au ciel un peu d'oxygène." % pr.to_lower())
	if String(t.get("pattern", "uni")) == "ocellé" and met == "hétérotrophe":
		out.append("Les ocelles de son dos imitent des yeux qui effraient les prédateurs.")
	return _pick(out, g)


## Deux ou trois phrases sur l'apparence et le mode de vie. Déterministe pour une espèce.
static func describe(t: Dictionary) -> String:
	var g := RandomNumberGenerator.new()
	g.seed = hash(["description", int(t.get("gseed", 0))])
	var hn := Naming.head_noun(t)
	var fem := bool(hn.fem)
	var head := String(hn.head)
	var det := "Cette" if fem else ("Cet" if Naming.starts_with_vowel(head) else "Ce")
	var subj := "%s %s" % [det, head]
	var pr := "Elle" if fem else "Il"
	var s1 := _appearance(t, subj, fem, g)
	var s2 := "%s %s%s%s%s." % [pr, _moves(t, fem, g), _social(t, g), _when(t), _diet(t, fem, g)]
	var text := s1 + " " + s2
	# Une fois sur cinq, deux phrases suffisent.
	if g.randf() >= 0.2:
		text += " " + _detail(t, fem, g)
	return text
