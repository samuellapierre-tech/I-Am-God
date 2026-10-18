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

const Procedural := preload("res://src/ai/procedural_narrator.gd")
const ParcelNarrator := preload("res://src/ai/parcel_narrator.gd")

## Sons par lignée, pour les noms que les peuples se donnent (et donnent à leurs lieux).
const PHONEMES := {
	"dinosaure": ["kra", "zor", "tak", "rhu", "sa", "gra", "ok", "dra", "um"],
	"oiseau": ["li", "ri", "tsi", "pi", "el", "wi", "ou", "lia", "fi"],
	"mammifère": ["mo", "na", "bru", "ul", "ha", "dun", "ro", "ma", "go"],
	"primate": ["a", "ka", "mi", "to", "ra", "en", "sa", "lo", "ni"],
	"reptile": ["sil", "ha", "ix", "sa", "thé", "ssa", "ké", "zi"],
	"ptérosaure": ["aé", "ki", "ra", "ou", "li", "ka", "sé", "vi"],
	"chimère": ["xo", "va", "nyr", "é", "qa", "zu", "il", "or"],
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
const AVEUX := [
	"Je ne l'avais vu dans aucune vision : je le découvre avec toi.", "Ma vision se brouille, mais c'est bien ce que je vois.",
	"Je l'écris, mais j'avoue que ça me surprend.", "Les images me viennent troubles, comme à travers l'eau.", "",
]

var rng := RandomNumberGenerator.new()
## species_id -> profil inventé (voir profile_for).
var profiles := {}
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
	if profiles.has(id):
		var known: Dictionary = profiles[id]
		# Une espèce devenue intelligente a désormais une culture : on la complète, sans rien effacer.
		if bool(sp.get("sapient", false)) and not known.has("customs"):
			known.merge(_culture(sp, ctx, _profile_rng(id, str(sp.get("name", "")) + "#culture")))
		known["name"] = str(sp.get("name", known.get("name", "")))
		return known
	var prng := _profile_rng(id, str(sp.get("name", "")))
	var p := {"id": id, "name": str(sp.get("name", "")), "clade": _clade(sp), "behaviors": _pick_n(_behavior_pool(sp), 3, prng)}
	if bool(sp.get("sapient", false)):
		p.merge(_culture(sp, ctx, prng))
	profiles[id] = p
	return p


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


func _people_line(p: Dictionary, sp: Dictionary, ctx: Dictionary) -> Dictionary:
	var customs: Array = p["customs"] + p.get("llm_customs", [])
	var slots := _base_slots(sp, ctx)
	slots["peuple"] = slots["espece"]
	slots["endonyme"] = p["endonym"]
	slots["dieu"] = p["deity"]
	slots["cause"] = p["deity_cause"]
	slots["coutume"] = Procedural.apply_agreement(str(customs[rng.randi() % customs.size()]), {"espece": slots["_espece_pl"]})
	slots["lieu_nom"] = p["place_name"]
	slots["materiau"] = MATERIALS.get(Procedural.era_key(ctx.get("era", "")), MATERIALS["generic"])
	var tpl: String = PEOPLE_TEMPLATES[rng.randi() % PEOPLE_TEMPLATES.size()]
	return {"text": ParcelNarrator.render(tpl, slots), "kind": "invention", "source": "ambient",
		"species_id": int(p["id"]), "profile": p}


func _beast_line(p: Dictionary, sp: Dictionary, ctx: Dictionary) -> Dictionary:
	var slots := _base_slots(sp, ctx)
	var behaviors: Array = p["behaviors"]
	slots["comportement"] = Procedural.apply_agreement(str(behaviors[rng.randi() % behaviors.size()]), {"espece": slots["_espece_pl"]})
	var reasons: Array = ctx.get("mode", {}).get("reasons", [])
	slots["raison"] = str(reasons[0]) if not reasons.is_empty() else "tout a pris un autre chemin"
	var tpl: String = BEAST_TEMPLATES[rng.randi() % BEAST_TEMPLATES.size()]
	return {"text": ParcelNarrator.render(tpl, slots), "kind": "invention", "source": "ambient",
		"species_id": int(p["id"]), "profile": p}


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
	return {
		"endonym": _word(clade, prng, 2 + prng.randi() % 2),
		"place_name": _word(clade, prng, 2),
		"deity": DEITY_NAMES[first_act], "deity_cause": DEITY_CAUSES[first_act], "deity_origin": first_act,
		"customs": _pick_n(_custom_pool(sp, ctx), 3, prng),
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
