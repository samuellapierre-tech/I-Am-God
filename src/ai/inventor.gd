extends RefCounted
## Invention du futur et des histoires alternatives : dès que le monde quitte l'histoire réelle
## (divergence.gd), le narrateur invente les mœurs des bêtes et la culture des peuples à partir de
## l'état réel de la simulation (traits, climat, usage du sol, technologie, gestes divins passés).
##
## Cohérence : ce qui est inventé pour une espèce (nom qu'elle se donne, nom qu'elle te donne,
## coutumes, comportements…) est tiré UNE fois, de façon déterministe, puis mémorisé dans `profiles`
## et réutilisé ensuite. Le LLM peut l'enrichir (enrich_from_llm), jamais le réécrire.
##
## Repli procédural combinatoire : gabarits × traits (clade, régime, taille, agressivité, climat).
##
## Futur sans fin (STRATEGIE.md §10) : quand une civilisation tombe (espèce éteinte ou technologie
## effondrée), elle rejoint les civilisations disparues ; une nouvelle lignée consciente hérite de leur
## souvenir (ruines, parfois le nom qu'elles te donnaient). vision() : ce que le narrateur « voit » des
## âges inventés (exode, cycles, ruines, Soleil qui vieillit), cohérent avec cette mémoire.
## Mémoire BORNÉE : au-delà de MAX_PROFILES, les profils les moins récemment utilisés sont résumés dans
## `archive` (bornée elle aussi ; au-delà, on ne garde que le compte des peuples oubliés).

const Procedural := preload("res://src/ai/procedural_narrator.gd")
const ParcelNarrator := preload("res://src/ai/parcel_narrator.gd")
const Epoch := preload("res://src/ai/epoch.gd")

## Sons par lignée, pour les noms que les peuples se donnent (et donnent à leurs lieux).
const PHONEMES := {
	"dinosaure": ["kra", "zor", "tak", "rhu", "sa", "gra", "ok", "dra", "um"],
	"oiseau": ["li", "ri", "tsi", "pi", "el", "wi", "ou", "lia", "fi"],
	"mammifère": ["mo", "na", "bru", "ul", "ha", "dun", "ro", "ma", "go"],
	"primate": ["a", "ka", "mi", "to", "ra", "en", "sa", "lo", "ni"],
	"reptile": ["sil", "ha", "ix", "sa", "thé", "ssa", "ké", "zi"],
	"ptérosaure": ["aé", "ki", "ra", "ou", "li", "ka", "sé", "vi"],
	"chimère": ["xo", "va", "nyr", "é", "qa", "zu", "il", "or"],
	"arthropode": ["krik", "tsa", "ch", "ki", "rr", "ak", "zi", "tek"],
	"insecte": ["zz", "ri", "ka", "zi", "vé", "tch", "ik", "a"],
	"mollusque": ["lu", "mo", "ou", "ol", "la", "mu", "on", "é"],
	"poisson": ["bu", "lo", "ou", "pa", "ul", "oa", "mé", "lou"],
	"amphibien": ["kro", "a", "ba", "lu", "ok", "rib", "é", "ta"],
	"synapside": ["gor", "na", "dim", "ta", "ro", "ul", "ka", "mé"],
	"microbe": ["i", "ou", "é", "si", "ti", "a", "li"],
	"algue": ["ve", "lu", "ia", "na", "ou", "la", "mé"],
	"éponge": ["po", "ou", "lu", "mo", "é", "fa"],
	"plante": ["ver", "fo", "li", "an", "ra", "sé", "mu"],
}

## Comment un peuple nomme Dieu, selon le premier geste divin dont il se souvient.
const DEITY_NAMES := {
	"meteor": "Celui-qui-fit-tomber-le-ciel", "bless": "la Main-qui-donne", "plague": "le Souffle-mauvais",
	"flood": "l'Eau-qui-juge", "ice_age": "le Grand-Froid", "save": "le Gardien", "uplift": "l'Éveilleur",
	"extinct": "l'Effaceur", "spawn_species": "le Façonneur", "": "le Silencieux",
}
const DEITY_CAUSES := {
	"meteor": "le jour où le ciel est tombé", "bless": "ta première bénédiction", "plague": "la grande maladie",
	"flood": "le déluge", "ice_age": "le grand froid", "save": "le jour où tu les as sauvés",
	"uplift": "le jour où tu les as éveillés", "extinct": "le jour où tu as effacé une lignée entière",
	"spawn_species": "le jour où tu les as façonnés", "": "toujours, faute de signe",
}

## Coutumes (peuples intelligents), par trait. Propositions complètes, sans majuscule ni point.
const CUSTOMS := {
	"carnivore": ["chaque jeune doit rapporter seul sa première proie avant de recevoir un nom", "la chasse se partage selon les blessures reçues, pas selon le rang", "les os des grandes proies sont gardés et gravés comme des archives"],
	"herbivore": ["on chante aux plantes avant de les cueillir", "les querelles se règlent autour d'un repas de feuilles amères", "on plante un arbre pour chaque naissance"],
	"omnivore": ["on ne mange jamais seul : un repas solitaire est un affront", "chaque fin de saison, un festin mêle tout ce que la terre a donné", "les enfants apprennent à goûter de tout avant d'apprendre à parler"],
	"large": ["les assemblées se tiennent en plein air, car aucun toit ne contient tout le monde", "on bâtit lentement, pour des siècles"],
	"small": ["on vit serrés par centaines dans des galeries chaudes", "on se méfie de tout ce qui est grand, y compris des idées"],
	"fierce": ["les duels rituels remplacent souvent la guerre", "l'honneur se mesure aux cicatrices"],
	"gentle": ["un étranger reçoit à manger avant qu'on lui demande son nom", "la colère en public est la pire des hontes"],
	"cold": ["le feu commun reste allumé tout l'hiver, et le laisser mourir est un crime", "on se raconte les étés passés pendant les longues nuits"],
	"hot": ["on vit la nuit et l'on dort aux heures brûlantes", "l'eau se partage avant la nourriture"],
	"mild": ["les fêtes suivent le retour des pluies", "on mesure le temps aux floraisons"],
	"dinosaure": ["les œufs sont couvés par tout le village, à tour de rôle", "les anciens se reconnaissent aux couleurs de leurs plumes"],
	"oiseau": ["les lois se transmettent en chants, et un chant faux vaut un mensonge", "chaque famille garde un nid ancestral qu'on ne quitte jamais"],
	"mammifère": ["les petits sont élevés en commun dans de vastes terriers", "on se salue en se flairant longuement"],
	"primate": ["le meilleur conteur est écouté comme un chef", "on se tresse les poils pour dire son clan"],
	"reptile": ["toute décision attend que le soleil du matin ait réchauffé l'assemblée", "on garde ses mues comme d'autres gardent des portraits"],
	"ptérosaure": ["les morts sont confiés au vent du haut des falaises", "on lit l'avenir dans les courants chauds"],
	"chimère": ["nul ne sait d'où ils viennent, pas même eux, et ils en ont fait une religion", "chacun change de nom à chaque saison"],
	"arthropode": ["chaque mue est une fête, et l'on garde l'ancienne carapace comme un portrait", "les lois sont gravées en vibrations sur les parois des terriers"],
	"insecte": ["les décisions se prennent en essaim, et nul ne parle en son seul nom", "chaque reine est vénérée, puis oubliée dès qu'elle meurt"],
	"mollusque": ["on parle en changeant de couleur, et mentir se voit sur la peau", "les morts sont rendus à la mer avec leur coquille"],
	"poisson": ["les bancs votent en tournant ensemble, et la direction choisie fait loi", "personne ne dort jamais tout à fait, par prudence"],
	"amphibien": ["on chante la nuit au bord de l'eau, et le plus beau chant fixe les lois", "les enfants naissent dans l'eau et n'ont un nom qu'à leur sortie"],
	"synapside": ["on se tient chaud en dormant serrés, et dormir seul est une punition", "les anciens enseignent en grondant doucement"],
	"microbe": ["on partage ses gènes avec les voisins comme d'autres partagent le pain", "nul n'est vraiment seul : chacun est une colonie"],
	"algue": ["on vit au rythme de la lumière, et la nuit est un temps sacré", "on se tourne ensemble vers le soleil avant de parler"],
	"éponge": ["on filtre l'eau en silence, et le bruit est une offense", "chacun se reconstruit après une blessure, et l'on en fait une vertu"],
	"plante": ["on ne se déplace jamais : on attend que le monde vienne à soi", "les conversations durent une saison entière"],
}
## Ce que les peuples bâtissent et manient, selon l'ère atteinte.
const MATERIALS := {
	"Préhistoire": "la pierre taillée et le feu", "Antiquité": "le bronze et l'argile", "Moyen Âge": "le fer et le bois",
	"Renaissance": "l'imprimerie et la boussole", "Industriel": "la vapeur et l'acier", "Moderne": "l'électricité et les réseaux",
	"Cyberpunk": "les implants et les néons", "Post-singularité": "la matière programmable", "generic": "ce qu'ils trouvent",
}

## Comportements inventés (bêtes non intelligentes), à l'infinitif.
const BEHAVIORS := {
	"carnivore": ["chasser en meute à la tombée du jour", "rabattre [espece:ses|leurs] proies vers l'eau avant de frapper", "guetter, [espece:immobile|immobiles], pendant des heures au bord des pistes", "marquer [espece:son|leur] territoire de longues griffures sur les troncs"],
	"herbivore": ["se relayer pour monter la garde pendant que le troupeau mange", "suivre chaque saison les mêmes chemins de migration", "garder les petits au centre du troupeau", "défricher en piétinant de larges clairières"],
	"omnivore": ["piller les nids des autres espèces", "cacher des provisions pour la mauvaise saison", "suivre les grands prédateurs pour finir leurs restes"],
	"dinosaure": ["couver [espece:ses|leurs] œufs à plusieurs dans des nids communs", "pousser des appels graves qui portent sur des kilomètres"],
	"oiseau": ["chanter à l'aube des chants de plus en plus compliqués", "bâtir des nids collectifs gros comme des cabanes"],
	"mammifère": ["creuser des terriers à plusieurs entrées", "se toiletter mutuellement pendant des heures"],
	"primate": ["casser des noix avec des cailloux choisis avec soin", "se disputer bruyamment la meilleure branche"],
	"reptile": ["se chauffer au soleil en rangs serrés chaque matin", "attendre sous l'eau, seuls les yeux dépassant"],
	"ptérosaure": ["planer des heures dans les courants chauds", "pêcher en rasant la surface de l'eau"],
	"chimère": ["changer de couleur quand on [espece:l'approche|les approche]", "dormir debout, en cercle, la tête vers l'extérieur"],
	"arthropode": ["muer tous ensemble à la même lune", "creuser des galeries qui forment de véritables cités"],
	"insecte": ["bâtir des nids collectifs hauts comme des arbres", "voler en nuées si denses qu'elles cachent le soleil"],
	"mollusque": ["changer de couleur pour se parler", "dériver en longues files au gré des courants"],
	"poisson": ["nager en bancs qui tournent comme un seul corps", "remonter les rivières bien plus loin qu'on ne l'aurait cru"],
	"amphibien": ["chanter toute la nuit au bord des mares", "passer la saison sèche enfouis dans la boue"],
	"synapside": ["se serrer les uns contre les autres pour garder leur chaleur", "creuser de vastes terriers pour fuir la chaleur du jour"],
	"microbe": ["bâtir des tapis de plus en plus épais sur les rochers", "s'unir en colonies qui se comportent comme un seul être"],
	"algue": ["couvrir les eaux de tapis verts au moindre rayon de soleil", "se laisser porter par les vagues jusqu'aux rivages"],
	"éponge": ["filtrer l'eau des récifs jour et nuit", "repousser entières à partir d'un simple fragment"],
	"plante": ["s'étendre en forêts qui gagnent chaque année sur les rivages", "tourner leurs feuilles vers le soleil comme un seul champ"],
	"large": ["faire trembler le sol à chacun de leurs pas"],
	"small": ["se faufiler partout, en bandes nombreuses"],
}

## Gabarits des lignes inventées (peuples intelligents). Emplacements : {peuple} (accord espece),
## {endonyme}, {dieu}, {cause}, {coutume}, {lieu_nom}, {materiau}, {terre}, {ciel}, {aveu}.
const PEOPLE_TEMPLATES := [
	"Chez {peuple}, {coutume}. {aveu}",
	"{peuple} [espece:se nomme elle-même|se nomment eux-mêmes] « {endonyme} » ; je l'inscris dans mon registre.",
	"{peuple} [espece:t'appelle|t'appellent] « {dieu} », depuis {cause}. Le nom te va plutôt bien.",
	"Sur {terre}, que {peuple} [espece:appelle|appellent] « {lieu_nom} », {coutume}.",
	"Je note une coutume de {peuple} : {coutume}.",
	"{peuple} [espece:travaille|travaillent] avec {materiau} ; et chez [espece:elle|eux], {coutume}.",
]
## Gabarits des lignes inventées (bêtes). Emplacements : {espece} {comportement} {terre} {ciel} {aveu} {raison}.
const BEAST_TEMPLATES := [
	"Sur {terre}, {espece} [espece:a appris|ont appris] à {comportement}. {aveu}",
	"Je surprends {espece} à {comportement} ; aucune de mes visions ne m'y avait préparé.",
	"Dans ce monde où {raison}, {espece} [espece:passe|passent] [espece:ses|leurs] journées à {comportement}.",
]
## Bascule vers l'invention, dite une fois.
const DIVERGENCE_TEMPLATES := [
	"À partir d'ici, ton monde quitte l'histoire que j'ai vue : {raison}. Je vais devoir inventer avec toi.",
	"Mes visions se troublent, car {raison}. Ce qui suit, je le découvre en même temps que toi.",
]
## Lignées nées sur les ruines d'une civilisation disparue. {ancien} : groupe nominal de l'ancienne
## espèce ; {ancien_endonyme}, {ancien_dieu} : ce qu'on en a retenu.
const HERITAGE_TEMPLATES := [
	"{peuple} [espece:bâtit|bâtissent] sur les ruines de {ancien}, qui se nommaient « {ancien_endonyme} » ; moi, je m'en souviens.",
	"Dans les ruines de {ancien}, {peuple} [espece:a retrouvé|ont retrouvé] le nom qu'on te donnait : « {ancien_dieu} ».",
	"{peuple} [espece:ignore|ignorent] tout de {ancien}. Moi, je n'ai rien oublié de leurs coutumes : {ancienne_coutume}.",
]
## Visions des âges inventés (le futur sans fin). Emplacements : {terre}, {ancien}, {ancien_endonyme},
## {ancien_dieu}, {peuple}, {oublies}. needs : "fallen" (une civilisation disparue), "exodus"
## (civilisation au sommet de la technologie), "far" (futur lointain), "cycles", "forgotten".
const VISIONS := [
	{"t": "Je vois des vaisseaux quitter le ciel de {terre} ; certains reviendront, d'autres jamais.", "needs": "exodus", "min_era": 16},
	{"t": "Mes visions se troublent : une partie de {peuple} part vers les étoiles, l'autre reste garder les ruines.", "needs": "exodus", "min_era": 16},
	{"t": "Je me souviens de {ancien} : ils te nommaient « {ancien_dieu} ». Leurs pierres s'effacent peu à peu.", "needs": "fallen"},
	{"t": "Mes visions gardent la trace de {ancien}, qui se nommaient « {ancien_endonyme} » ; personne d'autre ne s'en souvient.", "needs": "fallen"},
	{"t": "Là où {ancien} comptaient les saisons, la nature revient, sans se presser.", "needs": "fallen"},
	{"t": "Les continents ont dérivé depuis l'époque de {ancien} ; même les montagnes ont changé de place.", "needs": "far_fallen"},
	{"t": "Le Soleil a vieilli ; il chauffe un peu plus à chaque âge. Dans mes visions les plus lointaines, la Terre devient trop chaude pour la vie complexe.", "needs": "far"},
	{"t": "Un âge s'achève, un autre commence ; je cesse de compter les cycles, pas de les écrire.", "needs": "cycles"},
	{"t": "J'ai oublié le nom de {oublies} ; mes visions ne retiennent que les plus récents.", "needs": "forgotten"},
]
## Au-delà de cette date (années), le futur est « lointain » : continents, Soleil qui vieillit.
const FAR_FUTURE_YEAR := 100_000_000.0
## Au-delà de cette date, les âges inventés se succèdent : cycles.
const CYCLES_YEAR := 100_000.0
## Profils retenus en entier ; résumés au-delà (archive), elle-même bornée.
const MAX_PROFILES := 24
const MAX_ARCHIVE := 64
const MAX_FALLEN := 16
## Une civilisation dont la technologie retombe d'autant (niveaux) est tombée.
const FALL_DROP := 1.5

const AVEUX := [
	"Je ne l'avais vu dans aucune vision : je le découvre avec toi.", "Ma vision se brouille, mais c'est bien ce que je vois.",
	"Je l'écris, mais j'avoue que ça me surprend.", "Les images me viennent troubles, comme à travers l'eau.", "",
]

var rng := RandomNumberGenerator.new()
## species_id -> profil inventé (voir profile_for).
var profiles := {}
## Profils résumés (les plus anciens), du plus ancien au plus récent : [{id, name, endonym, deity, ...}].
var archive: Array[Dictionary] = []
## Nombre de peuples dont même le résumé a été oublié.
var forgotten := 0
## Civilisations disparues, de la plus ancienne à la plus récente (résumés).
var fallen: Array[Dictionary] = []
## Mémoire anti-répétition partagée (variety.gd) ; null = sans.
var variety: RefCounted = null
## Suivi hors profil (pour que le profil, lui, ne change jamais) : id -> {used, max_tech, fallen}.
var _lives := {}
var _seed := 0
var _count := 0
var _parcel: ParcelNarrator


func _init(p_seed: int = -1) -> void:
	if p_seed >= 0:
		_seed = p_seed
	else:
		rng.randomize()
		_seed = rng.randi()
	_parcel = ParcelNarrator.new(_seed + 2)


## Profil mémorisé d'une espèce ({id, name, clade, diet, size, aggression, sapient, ...}) ; créé au premier appel,
## identique ensuite (même si le contexte a changé : c'est la mémoire de ce qui a été raconté).
func profile_for(sp: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var id := int(sp.get("id", sp.get("species_id", -1)))
	_count += 1
	_life(id)["used"] = _count
	if profiles.has(id):
		var known: Dictionary = profiles[id]
		# Une espèce devenue intelligente a désormais une culture : on la complète, sans rien effacer.
		if bool(sp.get("sapient", false)) and not known.has("customs"):
			known.merge(_culture(sp, ctx, _profile_rng(id, str(sp.get("name", "")) + "#culture")))
			_inherit(known, id, _profile_rng(id, "heritage"))
		known["name"] = str(sp.get("name", known.get("name", "")))
		return known
	var prng := _profile_rng(id, str(sp.get("name", "")))
	var p := {"id": id, "name": str(sp.get("name", "")), "clade": _clade(sp), "behaviors": _pick_n(_behavior_pool(sp), 3, prng)}
	# Un peuple résumé dans l'archive revient avec ce qu'on en avait retenu (noms, dieu, une coutume).
	for i in range(archive.size() - 1, -1, -1):
		if int(archive[i].get("id", -2)) == id:
			for k in ["endonym", "place_name", "deity", "deity_cause", "deity_origin", "customs", "heritage"]:
				if archive[i].has(k):
					p[k] = archive[i][k]
			archive.remove_at(i)
			break
	if bool(sp.get("sapient", false)) and not p.has("customs"):
		p.merge(_culture(sp, ctx, prng))
		_inherit(p, id, _profile_rng(id, "heritage"))
	profiles[id] = p
	_bound_memory()
	return p


## Une nouvelle lignée consciente hérite du souvenir de la dernière civilisation disparue.
func _inherit(p: Dictionary, id: int, prng: RandomNumberGenerator) -> void:
	for i in range(fallen.size() - 1, -1, -1):
		var f: Dictionary = fallen[i]
		if int(f.get("id", -2)) == id:
			continue
		p["heritage"] = f.duplicate()
		# Parfois, ils retrouvent dans les ruines le nom que l'ancien peuple te donnait.
		if prng.randf() < 0.5 and str(f.get("deity", "")) != "":
			p["deity"] = f["deity"]
			p["deity_cause"] = "le jour où ils ont trouvé les ruines de " + Procedural.species_phrase(str(f.get("name", "")))["text"]
		return


## Résumé compact d'un profil (ce que la mémoire garde d'un peuple ancien).
static func summarize(p: Dictionary) -> Dictionary:
	var s := {"id": int(p.get("id", -1)), "name": str(p.get("name", "")), "clade": str(p.get("clade", ""))}
	for k in ["endonym", "place_name", "deity", "deity_cause", "deity_origin"]:
		if p.has(k):
			s[k] = p[k]
	if p.has("customs"):
		s["customs"] = (p["customs"] as Array).slice(0, 1)
	if p.has("heritage"):
		var h: Dictionary = p["heritage"]
		s["heritage"] = {"name": str(h.get("name", "")), "endonym": str(h.get("endonym", ""))}
	return s


## Mémoire bornée : les profils les moins récemment utilisés sont résumés dans l'archive.
func _bound_memory() -> void:
	while profiles.size() > MAX_PROFILES:
		var oldest := -1
		var oldest_use := 1 << 62
		for id in profiles:
			var u := int(_life(id).get("used", 0))
			if u < oldest_use:
				oldest_use = u
				oldest = id
		archive.append(summarize(profiles[oldest]))
		profiles.erase(oldest)
	while archive.size() > MAX_ARCHIVE:
		archive.pop_front()
		forgotten += 1
	if _lives.size() > MAX_PROFILES + MAX_ARCHIVE + MAX_FALLEN:
		for id in _lives.keys():
			if not profiles.has(id):
				_lives.erase(id)
				if _lives.size() <= MAX_PROFILES + MAX_ARCHIVE:
					break


## Suit les peuples : une espèce intelligente éteinte, ou dont la technologie s'effondre, est tombée.
func observe(ctx: Dictionary) -> void:
	for sp in ctx.get("species", []):
		if not (sp is Dictionary) or not bool(sp.get("sapient", false)):
			continue
		var id := int(sp.get("id", -1))
		var life := _life(id)
		var tech := float(sp.get("tech_level", 0.0))
		life["max_tech"] = maxf(float(life.get("max_tech", tech)), tech)
		var fell := not bool(sp.get("alive", true)) or tech < float(life["max_tech"]) - FALL_DROP
		if fell and not bool(life.get("fallen", false)):
			life["fallen"] = true
			var p := profile_for(sp, ctx)
			var s := summarize(p)
			s["epoch"] = Epoch.current({"species": [{"sapient": true, "alive": true, "tech_level": life["max_tech"]}]})
			fallen.append(s)
			while fallen.size() > MAX_FALLEN:
				fallen.pop_front()
		elif not fell and bool(life.get("fallen", false)) and bool(sp.get("alive", true)):
			# Une civilisation qui se relève redevient vivante (sans effacer le souvenir de sa chute).
			life["fallen"] = false
			life["max_tech"] = tech


## Une vision des âges inventés, cohérente avec la mémoire ; {} si rien ne s'applique.
func vision(ctx: Dictionary) -> Dictionary:
	_count += 1
	rng.seed = hash([_seed, _count, "vision"])
	var epoch := Epoch.current(ctx)
	var year: Variant = ctx.get("year", null)
	var y := float(year) if typeof(year) in [TYPE_INT, TYPE_FLOAT] else 0.0
	var top := {}
	for sp in ctx.get("species", []):
		if sp is Dictionary and bool(sp.get("sapient", false)) and bool(sp.get("alive", true)) \
				and (top.is_empty() or float(sp.get("tech_level", 0.0)) > float(top.get("tech_level", 0.0))):
			top = sp
	var has := {
		"exodus": not top.is_empty() and float(top.get("tech_level", 0.0)) >= 7.5,
		"fallen": not fallen.is_empty(),
		"far": y >= FAR_FUTURE_YEAR,
		"far_fallen": y >= FAR_FUTURE_YEAR and not fallen.is_empty(),
		"cycles": y >= CYCLES_YEAR or not fallen.is_empty(),
		"forgotten": forgotten > 0,
	}
	var old: Dictionary = fallen[rng.randi() % fallen.size()] if not fallen.is_empty() else {}
	var slots := _base_slots(top if not top.is_empty() else {"name": ""}, ctx)
	slots["peuple"] = Procedural.species_phrase(str(top.get("name", "")))["text"] if not top.is_empty() else "les vivants"
	slots["ancien"] = Procedural.species_phrase(str(old.get("name", "")))["text"] if not old.is_empty() else "les anciens"
	slots["ancien_endonyme"] = str(old.get("endonym", "les Anciens"))
	slots["ancien_dieu"] = str(old.get("deity", "le Silencieux"))
	slots["oublies"] = "%d peuple%s" % [forgotten, "s" if forgotten > 1 else ""]
	var order: Array = range(VISIONS.size())
	if variety != null:
		order = variety.order("vision", VISIONS.size(), rng)
	else:
		var start := rng.randi() % VISIONS.size()
		order = order.slice(start) + order.slice(0, start)
	for i in order:
		var v: Dictionary = VISIONS[i]
		if not bool(has.get(str(v.get("needs", "")), false)) or not Epoch.allows(v, epoch):
			continue
		var text := ParcelNarrator.render(str(v["t"]), slots)
		if not Epoch.is_clean(text, epoch) or (variety != null and variety.seen(text)):
			continue
		if variety != null:
			variety.used("vision", i)
		return {"text": text, "kind": "vision", "source": "ambient"}
	return {}


func _life(id: int) -> Dictionary:
	if not _lives.has(id):
		_lives[id] = {}
	return _lives[id]


## Ajoute ce que le LLM a inventé pour un peuple (JSON {coutumes: [..], croyance, fete}) ; false si invalide.
func enrich_from_llm(species_id: int, raw: String) -> bool:
	if not profiles.has(species_id):
		return false
	var data: Variant = JSON.parse_string(_json_block(raw))
	if not (data is Dictionary):
		return false
	var added := []
	for c in data.get("coutumes", []):
		var s := str(c).strip_edges().trim_suffix(".")
		if s.length() >= 12 and s.length() <= 160 and not s.contains("{") and not s.contains("\n"):
			added.append(s.substr(0, 1).to_lower() + s.substr(1))
	if added.is_empty():
		return false
	var p: Dictionary = profiles[species_id]
	var custom: Array = p.get("llm_customs", [])
	for s in added.slice(0, 3):
		if not s in custom:
			custom.append(s)
	p["llm_customs"] = custom.slice(0, 6)
	for key in ["croyance", "fete"]:
		var v := str(data.get(key, "")).strip_edges()
		if v.length() >= 8 and v.length() <= 200 and not p.has("llm_" + key):
			p["llm_" + key] = v
	return true


## Une ligne inventée pour le fil continu ; ctx : contexte du fil (mode compris).
func line(ctx: Dictionary) -> Dictionary:
	_count += 1
	rng.seed = hash([_seed, _count, "line"])
	var mode: Dictionary = ctx.get("mode", {})
	observe(ctx)
	if bool(mode.get("just_diverged", false)):
		return divergence_line(ctx)
	var subject := pick_subject(ctx)
	if subject.is_empty():
		return {}
	var p := profile_for(subject, ctx)
	if p.has("customs"):
		return _people_line(p, subject, ctx)
	return _beast_line(p, subject, ctx)


## Annonce de la bascule vers l'invention.
func divergence_line(ctx: Dictionary) -> Dictionary:
	var reasons: Array = ctx.get("mode", {}).get("reasons", [])
	var raison := str(reasons[0]) if not reasons.is_empty() else "le monde a pris un autre chemin"
	var tpl: String = DIVERGENCE_TEMPLATES[rng.randi() % DIVERGENCE_TEMPLATES.size()]
	return {"text": Procedural.polish(tpl.format({"raison": raison})), "kind": "divergence", "source": "ambient"}


## Sujet de l'invention : un peuple intelligent sur la parcelle, sinon ailleurs, sinon une bête de la parcelle.
func pick_subject(ctx: Dictionary) -> Dictionary:
	var by_id := {}
	for sp in ctx.get("species", []):
		by_id[int(sp.get("id", -1))] = sp
	var snap: Dictionary = ctx.get("snapshot", {})
	var local := []
	var local_sapient := []
	for f in snap.get("fauna", []):
		var id := int(f.get("species_id", -1))
		var sp: Dictionary = by_id.get(id, {"id": id, "name": str(f.get("name", "")), "clade": str(f.get("clade", "")),
			"diet": str(f.get("role", "omnivore")), "sapient": str(f.get("role", "")) == "sapient", "size": 0.3})
		local.append(sp)
		if bool(sp.get("sapient", false)):
			local_sapient.append(sp)
	if not local_sapient.is_empty() and rng.randf() < 0.7:
		return local_sapient[rng.randi() % local_sapient.size()]
	var world_sapient: Array = ctx.get("species", []).filter(func(s): return bool(s.get("sapient", false)) and bool(s.get("alive", true)))
	if not world_sapient.is_empty() and (local.is_empty() or rng.randf() < 0.5):
		return world_sapient[rng.randi() % world_sapient.size()]
	if not local.is_empty():
		return local[rng.randi() % local.size()]
	return {}


## Une ligne sur un peuple ; {} si aucune n'est possible sans anachronisme à cette époque.
func _people_line(p: Dictionary, sp: Dictionary, ctx: Dictionary) -> Dictionary:
	var customs: Array = p["customs"] + p.get("llm_customs", [])
	var epoch := Epoch.current(ctx)
	var templates: Array = PEOPLE_TEMPLATES.duplicate()
	if p.has("heritage"):
		templates.append_array(HERITAGE_TEMPLATES)
	var tries := 24 if variety != null else 10
	for _attempt in tries:
		var slots := _base_slots(sp, ctx)
		slots["peuple"] = slots["espece"]
		slots["endonyme"] = p["endonym"]
		slots["dieu"] = p["deity"]
		slots["cause"] = p["deity_cause"]
		slots["coutume"] = Procedural.apply_agreement(str(customs[rng.randi() % customs.size()]), {"espece": slots["_espece_pl"]})
		slots["lieu_nom"] = p["place_name"]
		slots["materiau"] = MATERIALS.get(Epoch.NAMES[epoch], MATERIALS["generic"])
		var h: Dictionary = p.get("heritage", {})
		slots["ancien"] = Procedural.species_phrase(str(h.get("name", "")))["text"] if not h.is_empty() else "les anciens"
		slots["ancien_endonyme"] = str(h.get("endonym", "les Anciens"))
		slots["ancien_dieu"] = str(h.get("deity", p["deity"]))
		var hc: Array = h.get("customs", [])
		slots["ancienne_coutume"] = str(hc[0]) if not hc.is_empty() else str(customs[0])
		var tpl: String = templates[rng.randi() % templates.size()]
		var text := ParcelNarrator.render(tpl, slots)
		if Epoch.is_clean(text, epoch) and (variety == null or not variety.seen(text)):
			return {"text": text, "kind": "invention", "source": "ambient", "species_id": int(p["id"]), "profile": p}
	return {}


## Une ligne sur une bête ; {} si aucune n'est possible sans anachronisme à cette époque.
func _beast_line(p: Dictionary, sp: Dictionary, ctx: Dictionary) -> Dictionary:
	var behaviors: Array = p["behaviors"]
	var reasons: Array = ctx.get("mode", {}).get("reasons", [])
	var epoch := Epoch.current(ctx)
	for _attempt in (24 if variety != null else 10):
		var slots := _base_slots(sp, ctx)
		slots["comportement"] = Procedural.apply_agreement(str(behaviors[rng.randi() % behaviors.size()]), {"espece": slots["_espece_pl"]})
		slots["raison"] = str(reasons[0]) if not reasons.is_empty() else "tout a pris un autre chemin"
		var tpl: String = BEAST_TEMPLATES[rng.randi() % BEAST_TEMPLATES.size()]
		var text := ParcelNarrator.render(tpl, slots)
		if Epoch.is_clean(text, epoch) and (variety == null or not variety.seen(text)):
			return {"text": text, "kind": "invention", "source": "ambient", "species_id": int(p["id"]), "profile": p}
	return {}


func _base_slots(sp: Dictionary, ctx: Dictionary) -> Dictionary:
	var snap: Dictionary = ctx.get("snapshot", {})
	var m := {"kind": "invention", "species_name": str(sp.get("name", "")), "role": "sapient" if bool(sp.get("sapient", false)) else str(sp.get("diet", "")), "snapshot": snap}
	var slots := _parcel.slots_for(ctx.get("era", ""), m, snap, ctx.get("year", null))
	slots["aveu"] = AVEUX[rng.randi() % AVEUX.size()]
	return slots


# ---------------------------------------------------------------------------
# Génération des profils (déterministe : graine × espèce)
# ---------------------------------------------------------------------------

func _profile_rng(id: int, name: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([_seed, id, name])
	return r


func _culture(sp: Dictionary, ctx: Dictionary, prng: RandomNumberGenerator) -> Dictionary:
	var clade := _clade(sp)
	var first_act := ""
	for act in ctx.get("divine", []):
		var t := str(act.get("type", "")) if act is Dictionary else str(act)
		if DEITY_NAMES.has(t):
			first_act = t
			break
	# La mémoire ne retient que des coutumes possibles à l'époque où on les invente.
	var epoch := Epoch.current(ctx)
	var pool := _custom_pool(sp, ctx).filter(func(c: String) -> bool: return Epoch.is_clean(c, epoch))
	return {
		"endonym": _word(clade, prng, 2 + prng.randi() % 2),
		"place_name": _word(clade, prng, 2),
		"deity": DEITY_NAMES[first_act], "deity_cause": DEITY_CAUSES[first_act], "deity_origin": first_act,
		"customs": _pick_n(pool if not pool.is_empty() else ["on se tait quand le ciel change"], 3, prng),
	}


func _custom_pool(sp: Dictionary, ctx: Dictionary) -> Array:
	var pool := []
	pool.append_array(CUSTOMS.get(str(sp.get("diet", "omnivore")), CUSTOMS["omnivore"]))
	pool.append_array(CUSTOMS["large"] if float(sp.get("size", 0.3)) >= 0.5 else CUSTOMS["small"])
	pool.append_array(CUSTOMS["fierce"] if float(sp.get("aggression", 0.5)) >= 0.6 else CUSTOMS["gentle"])
	var t := float(ctx.get("snapshot", {}).get("temperature_c", 15.0))
	pool.append_array(CUSTOMS["cold"] if t < 5.0 else (CUSTOMS["hot"] if t > 27.0 else CUSTOMS["mild"]))
	pool.append_array(CUSTOMS.get(_clade(sp), CUSTOMS["chimère"]))
	return pool


func _behavior_pool(sp: Dictionary) -> Array:
	var pool := []
	pool.append_array(BEHAVIORS.get(str(sp.get("diet", "omnivore")), BEHAVIORS["omnivore"]))
	pool.append_array(BEHAVIORS.get(_clade(sp), BEHAVIORS["chimère"]))
	pool.append_array(BEHAVIORS["large"] if float(sp.get("size", 0.3)) >= 0.5 else BEHAVIORS["small"])
	return pool


static func _clade(sp: Dictionary) -> String:
	var c := str(sp.get("clade", ""))
	return c if PHONEMES.has(c) else "chimère"


static func _pick_n(pool: Array, n: int, prng: RandomNumberGenerator) -> Array:
	var bag := pool.duplicate()
	var out := []
	while out.size() < n and not bag.is_empty():
		out.append(bag.pop_at(prng.randi() % bag.size()))
	return out


static func _word(clade: String, prng: RandomNumberGenerator, syllables: int) -> String:
	var ph: Array = PHONEMES.get(clade, PHONEMES["chimère"])
	var w := ""
	for i in syllables:
		w += str(ph[prng.randi() % ph.size()])
	return w.substr(0, 1).to_upper() + w.substr(1)


static func _json_block(raw: String) -> String:
	var a := raw.find("{")
	var b := raw.rfind("}")
	return raw.substr(a, b - a + 1) if a >= 0 and b > a else ""
