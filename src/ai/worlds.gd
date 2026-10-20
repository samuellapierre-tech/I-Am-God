extends RefCounted
## La fin des temps d'une planète et la réincarnation (docs/GENESE.md) : le narrateur referme le grand livre
## d'un monde, puis en ouvre un autre, en se souvenant des mondes passés.
##
## Mémoire d'un monde (record) : {species_born, notable: [noms], civilizations: [noms], seeds,
## first_year, last_year, end ("sun" | "player" | ...)}. Le narrateur la tient à jour (note_*), puis
## remember() la range parmi les mondes passés, bornés à MAX_WORLDS (les plus anciens sont oubliés,
## seul leur nombre reste). snapshot() / restore() servent à la sauvegarde.
## Déterministe à graine égale.

const Procedural := preload("res://src/ai/procedural_narrator.gd")

const MAX_WORLDS := 12
const MAX_NOTABLE := 8
const MAX_CIVS := 6
## Causes de la fin des temps et ce que le narrateur en dit.
const ENDS := {
	"sun": "Le Soleil a trop vieilli : il chauffe ce monde jusqu'à faire bouillir ses océans.",
	"oceans": "Les océans se sont évaporés ; il ne reste que la roche et le vent.",
	"player": "Tu as décidé que ce monde s'arrêtait ici.",
	"impact": "Une collision a fondu la surface de ce monde.",
	"frozen": "Le froid a tout pris, jusqu'au fond des mers.",
	"": "Ce monde s'éteint, comme s'éteignent les étoiles.",
}
const END_TEMPLATES := [
	"{fin} {bilan} Je referme le grand livre de ce monde.",
	"{fin} {bilan} J'ai tout écrit ; il n'y a plus rien à ajouter.",
]
const REBIRTH_TEMPLATES := [
	"Une planète nouvelle, vierge{traits}. {souvenir} Tout est à recommencer, et rien n'est écrit.",
	"Un autre monde s'ouvre devant toi{traits}. {souvenir} Je prends une page blanche.",
]

## Mondes passés, du plus ancien au plus récent (records résumés).
var past: Array[Dictionary] = []
## Nombre de mondes dont même le résumé a été oublié.
var forgotten := 0
## Le monde en cours.
var current := {}
var rng := RandomNumberGenerator.new()
var _seed := 0
var _count := 0


func _init(p_seed: int = -1) -> void:
	if p_seed >= 0:
		_seed = p_seed
	else:
		rng.randomize()
		_seed = rng.randi()
	current = _blank()


static func _blank() -> Dictionary:
	return {"species_born": 0, "notable": [], "civilizations": [], "seeds": 0, "first_year": null, "last_year": null, "end": ""}


## Tient la mémoire du monde en cours.
func note_year(year: Variant) -> void:
	if typeof(year) in [TYPE_INT, TYPE_FLOAT]:
		if current["first_year"] == null:
			current["first_year"] = float(year)
		current["last_year"] = float(year)


func note_species(name: String, notable := false) -> void:
	current["species_born"] = int(current["species_born"]) + 1
	if notable and name != "" and not name in current["notable"]:
		current["notable"].append(name)
		while (current["notable"] as Array).size() > MAX_NOTABLE:
			(current["notable"] as Array).pop_front()


func note_civilization(name: String) -> void:
	if name != "" and not name in current["civilizations"]:
		current["civilizations"].append(name)
		while (current["civilizations"] as Array).size() > MAX_CIVS:
			(current["civilizations"] as Array).pop_front()


func note_seed() -> void:
	current["seeds"] = int(current["seeds"]) + 1


## La fin des temps : 2 à 4 phrases ; le monde en cours rejoint les mondes passés.
func end_of_times(end := "", year: Variant = null) -> String:
	_count += 1
	rng.seed = hash([_seed, _count, "end"])
	note_year(year)
	current["end"] = end
	var text := Procedural.polish(str(END_TEMPLATES[rng.randi() % END_TEMPLATES.size()]).format({
		"fin": ENDS.get(end, ENDS[""]), "bilan": summary(current)}))
	remember(current)
	current = _blank()
	return text


## La réincarnation : une planète nouvelle, et le souvenir du (ou des) monde(s) passé(s).
## planet : ce qu'on sait du nouveau monde, {size, ocean_fraction, star, tilt, name} (facultatif).
func reincarnation(planet: Dictionary = {}) -> String:
	_count += 1
	rng.seed = hash([_seed, _count, "rebirth"])
	var last: Dictionary = past[-1] if not past.is_empty() else {}
	var souvenir := "Je n'ai le souvenir d'aucun autre monde."
	if not last.is_empty():
		var names: Array = last.get("notable", [])
		var civs: Array = last.get("civilizations", [])
		if not civs.is_empty():
			souvenir = "Je me souviens du monde d'avant, et de %s qui y pensaient." % Procedural.species_phrase(str(civs[-1]))["text"]
		elif not names.is_empty():
			souvenir = "Je me souviens du monde d'avant, et de %s." % Procedural.species_phrase(str(names[-1]))["text"]
		else:
			souvenir = "Je me souviens du monde d'avant, même s'il n'y a pas eu grand-chose à écrire."
		if past.size() + forgotten > 1:
			souvenir += " C'est ta %s vie de dieu." % _ordinal(past.size() + forgotten + 1)
	var text := str(REBIRTH_TEMPLATES[rng.randi() % REBIRTH_TEMPLATES.size()]).format({
		"traits": _planet_traits(planet), "souvenir": souvenir})
	return Procedural.polish(Procedural.contract(" " + text).strip_edges())


## Bilan d'un monde, en une ou deux phrases.
static func summary(record: Dictionary) -> String:
	var n := int(record.get("species_born", 0))
	var parts := PackedStringArray()
	if n <= 0:
		parts.append("Aucune vie n'y a pris racine.")
	else:
		var s := "%d espèce%s y %s vécu" % [n, "s" if n > 1 else "", "ont" if n > 1 else "a"]
		var names: Array = record.get("notable", [])
		if names.size() >= 2:
			s += ", de %s à %s" % [Procedural.species_phrase(str(names[0]))["text"], Procedural.species_phrase(str(names[-1]))["text"]]
		parts.append(Procedural.contract(" " + s).strip_edges() + ".")
	var civs: Array = record.get("civilizations", [])
	if not civs.is_empty():
		var civ := Procedural.species_phrase(str(civs[-1]))
		var line := "%s y [n:a|ont] pensé, et je m'en souviens." % civ["text"]
		parts.append(Procedural.apply_agreement(line, {"n": civ["plural"]}))
	return " ".join(parts)


## Range un monde parmi les mondes passés (borné).
func remember(record: Dictionary) -> void:
	past.append(record.duplicate(true))
	while past.size() > MAX_WORLDS:
		past.pop_front()
		forgotten += 1


## Pour la sauvegarde : tout ce que le narrateur sait des mondes.
func snapshot() -> Dictionary:
	return {"past": past.duplicate(true), "forgotten": forgotten, "current": current.duplicate(true)}


func restore(data: Dictionary) -> void:
	past.clear()
	for r in data.get("past", []):
		if r is Dictionary:
			past.append(r)
	forgotten = int(data.get("forgotten", 0))
	current = data.get("current", _blank()) if data.get("current") is Dictionary else _blank()


static func _planet_traits(planet: Dictionary) -> String:
	var bits := PackedStringArray()
	var size := float(planet.get("size", 1.0))
	if size < 0.8:
		bits.append("plus petite que la précédente")
	elif size > 1.25:
		bits.append("plus grande que la précédente")
	var ocean := float(planet.get("ocean_fraction", -1.0))
	if ocean >= 0.85:
		bits.append("presque toute couverte d'eau")
	elif ocean >= 0.0 and ocean <= 0.4:
		bits.append("aux océans rares")
	var star := str(planet.get("star", ""))
	if star != "":
		bits.append("autour d'une étoile %s" % star)
	return (", " + ", ".join(bits.slice(0, 2))) if not bits.is_empty() else ""


static func _ordinal(n: int) -> String:
	var names := ["", "première", "deuxième", "troisième", "quatrième", "cinquième", "sixième", "septième", "huitième", "neuvième", "dixième"]
	return names[n] if n < names.size() else "%de" % n
