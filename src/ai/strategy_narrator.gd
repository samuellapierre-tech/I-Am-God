extends RefCounted
## Le narrateur met en scène la stratégie (docs/STRATEGIE.md, module src/strategy/) : manches, cartes de
## menace, pistes et fin de partie. Il RACONTE les règles, il ne les invente pas : chaque chiffre, titre
## ou correspondance vient des dictionnaires fournis par la stratégie (contrat de docs/ARCHITECTURE.md).
## Fonctions pures, déterministes (aucun hasard) : testables sans GameState.
##
## round (rd) : {index, name, stage, starts_year, ends_year, threats: [carte]}
## carte : {id, kind, title, target: {region, species_id}, strikes_year, severity, countered, counters: [types]}
## tracks : {collapses, collapse_limit, vitality 0..1, works: {life, land, mind, legacy: bool}, deck_left}

const Procedural := preload("res://src/ai/procedural_narrator.gd")

## Comment on nomme chaque pouvoir quand il contre une menace.
const POWER_NAMES := {
	"meteor": "un météore", "extinct": "une extinction", "save": "le salut", "bless": "une bénédiction",
	"plague": "une épidémie", "uplift": "un éveil", "flood": "un déluge", "ice_age": "un âge glaciaire",
	"spawn_species": "une création d'espèce",
}
const WORK_NAMES := {"life": "Vie complexe", "land": "Conquête des terres", "mind": "Conscience", "legacy": "Civilisation pérenne"}
## En dessous, la vitalité de la parcelle inquiète, puis alarme.
const VITALITY_WARN := 0.3
const VITALITY_CRITICAL := 0.1
## Effondrements restants à partir desquels le narrateur s'alarme.
const COLLAPSE_WARN := 2
## Menaces restantes dans la pioche à partir desquelles il parle du sablier.
const DECK_WARN := 3


## Annonce d'une manche et de ses menaces. actions : budget de la manche (-1 si inconnu).
static func round_line(rd: Dictionary, actions := -1) -> String:
	var parts := PackedStringArray()
	var name := str(rd.get("name", "")).strip_edges()
	var index := int(rd.get("index", 0))
	if name != "":
		parts.append("Manche %d : %s." % [index, name] if index > 0 else "%s commence." % name)
	elif index > 0:
		parts.append("Manche %d." % index)
	var titles := PackedStringArray()
	for t in rd.get("threats", []):
		if t is Dictionary and str(t.get("title", "")) != "":
			titles.append(str(t["title"]))
	match titles.size():
		0:
			parts.append("Je ne vois aucune menace se lever, pour l'instant.")
		1:
			parts.append("Une menace se lève : %s." % titles[0])
		_:
			parts.append("%d menaces se lèvent : %s et %s." % [titles.size(), ", ".join(titles.slice(0, titles.size() - 1)), titles[-1]])
	if actions >= 0:
		parts.append("Tu disposes de %d action%s." % [actions, "s" if actions > 1 else ""])
	return Procedural.polish(" ".join(parts))


## Une menace révélée en cours de manche. year : date actuelle (null si inconnue).
static func threat_line(threat: Dictionary, year: Variant = null) -> String:
	var text := "Nouvelle menace : %s" % str(threat.get("title", "un danger sans nom"))
	var when := strikes_in(threat, year)
	text += (", qui frappera %s." % when) if when != "" else "."
	var counters := counters_phrase(threat.get("counters", []))
	if counters != "":
		text += " Elle se contre par %s." % counters
	return Procedural.polish(text)


## Une menace contrée ou qui frappe. target_name : nom de l'espèce visée ("" : la parcelle ou le monde).
static func resolved_line(threat: Dictionary, countered: bool, target_name := "") -> String:
	var title := str(threat.get("title", "la menace"))
	if countered:
		return Procedural.polish("Contrée : %s. Je raye la carte de mon registre." % title)
	var cible: String = Procedural.species_phrase(target_name)["text"] if target_name != "" else "ta parcelle"
	# En milieu de phrase, « La sécheresse » devient « la sécheresse » (un titre sans article reste tel quel).
	for art in ["Le ", "La ", "Les ", "L'", "Une ", "Un "]:
		if title.begins_with(art):
			title = title.substr(0, 1).to_lower() + title.substr(1)
	return Procedural.polish(Procedural.contract(" Rien ne l'a arrêtée : %s frappe %s." % [title, cible]).strip_edges())


## Ce qui mérite d'être dit quand les pistes changent (liste de phrases, la plus grave d'abord).
static func tracks_lines(before: Dictionary, after: Dictionary) -> Array:
	var out := []
	var c0 := int(before.get("collapses", 0))
	var c1 := int(after.get("collapses", c0))
	var limit := int(after.get("collapse_limit", before.get("collapse_limit", 8)))
	if c1 > c0:
		var left := limit - c1
		var s := ("Un effondrement en chaîne de plus : %d sur %d." % [c1, limit]) if c1 - c0 == 1 			else ("%d effondrements en chaîne de plus : %d sur %d." % [c1 - c0, c1, limit])
		if left <= 0:
			s = "Le dernier effondrement est tombé : %d sur %d." % [c1, limit]
		elif left == 1:
			s += " Un seul de plus, et le monde t'échappe."
		elif left <= COLLAPSE_WARN:
			s += " Encore %d, et le monde t'échappe." % left
		out.append(s)
	var v0 := float(before.get("vitality", 1.0))
	var v1 := float(after.get("vitality", v0))
	if v1 <= VITALITY_CRITICAL and v0 > VITALITY_CRITICAL:
		out.append("La vie de ta parcelle ne tient plus qu'à un fil : il en reste à peine %d %%." % int(round(v1 * 100.0)))
	elif v1 <= VITALITY_WARN and v0 > VITALITY_WARN:
		out.append("La vitalité de ta parcelle s'effondre : %d %%." % int(round(v1 * 100.0)))
	var w0: Dictionary = before.get("works", {})
	var w1: Dictionary = after.get("works", {})
	var done := 0
	for k in WORK_NAMES:
		if bool(w1.get(k, false)):
			done += 1
	for k in WORK_NAMES:
		if bool(w1.get(k, false)) and not bool(w0.get(k, false)):
			out.append("Grand Œuvre accompli : %s. %d sur 4." % [WORK_NAMES[k], done])
	if after.has("deck_left"):
		var d0 := int(before.get("deck_left", 999))
		var d1 := int(after["deck_left"])
		if d1 < d0 and d1 <= DECK_WARN:
			out.append("Le sablier cosmique se vide : plus que %d menace%s dans la pioche." % [d1, "s" if d1 > 1 else ""] if d1 > 0 else "Le sablier cosmique est vide : il n'y a plus de menace à piocher.")
	return out


## Épilogue (2 à 4 phrases). last_choice : phrase de souvenir déjà formée (GameMaster.memory_line) ou "".
static func epilogue(victory: bool, reason: String, last_choice := "") -> String:
	# La raison vient des règles : on la reprend telle quelle (sans retirer « Effondrements : »…).
	var r := reason.strip_edges().trim_suffix(".").strip_edges()
	var parts := PackedStringArray()
	if victory:
		parts.append("Les quatre Grands Œuvres sont accomplis.")
		if r != "":
			parts.append(r.substr(0, 1).to_upper() + r.substr(1) + ".")
		parts.append("Je referme mon registre : ce monde t'a obéi jusqu'au bout, et je n'aurais pas parié dessus.")
	else:
		parts.append((r.substr(0, 1).to_upper() + r.substr(1) + ".") if r != "" else "Le monde t'a échappé.")
		parts.append("Je referme mon registre ; il reste mes visions, et ce que tu en as fait.")
	if last_choice != "":
		parts.append(last_choice)
	return Procedural.polish(" ".join(parts.slice(0, 4)))


## « dans environ 3 millions d'années », « dans environ 40 ans » ; "" si la date est inconnue.
static func strikes_in(threat: Dictionary, year: Variant) -> String:
	if not (typeof(threat.get("strikes_year")) in [TYPE_INT, TYPE_FLOAT]) or not (typeof(year) in [TYPE_INT, TYPE_FLOAT]):
		return ""
	var dt := float(threat["strikes_year"]) - float(year)
	if dt <= 0.0:
		return "d'un instant à l'autre"
	return "dans environ " + Procedural._duration(dt)


## « un déluge ou une bénédiction » ; "" si aucune correspondance n'est fournie.
static func counters_phrase(counters: Variant) -> String:
	var names := PackedStringArray()
	if counters is Array:
		for c in counters:
			var n: String = POWER_NAMES.get(str(c), "")
			if n != "" and not n in names:
				names.append(n)
	if names.is_empty():
		return ""
	if names.size() == 1:
		return names[0]
	return ", ".join(names.slice(0, names.size() - 1)) + " ou " + names[-1]
