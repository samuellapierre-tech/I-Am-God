extends RefCounted
## Textes de la parcelle (src/sim/parcel_sim.gd) : libellés d'usage du sol et accords en nombre.
## Même règle d'accord que le narrateur (src/ai/procedural_narrator.gd, species_phrase) :
## « Multituberculés », « Humains » -> pluriel (« les X ») ; binôme latin « Verpha moloum » ->
## singulier (« l'espèce X »).

const USE_LABELS := {
	"ocean": "Océan", "ice": "Glaces", "wild": "Terres sauvages", "crater": "Cratère d'impact",
	"flooded": "Terres inondées", "camp": "Campement", "pasture": "Pâturages",
	"farmland": "Terres agricoles", "village": "Village", "town": "Petite ville", "city": "Ville",
	"megacity": "Mégapole", "arcology": "Arcologie", "ruins": "Ruines", "rewild": "Retour à la nature",
}
## Libellé de « wild » selon le biome (WorldSim.BIOME_NAMES).
const WILD_LABELS := {
	"Forêt tempérée": "Forêt sauvage", "Taïga": "Taïga sauvage", "Forêt tropicale": "Jungle",
	"Steppe": "Steppe sauvage", "Savane": "Savane sauvage", "Désert": "Désert",
	"Toundra": "Toundra", "Montagnes": "Montagnes sauvages", "Glace": "Terres glacées",
}
## Ce que les premiers champs remplacent, selon le biome.
const CLEARED := {
	"Forêt tempérée": "la forêt", "Taïga": "la taïga", "Forêt tropicale": "la jungle",
	"Steppe": "la steppe", "Savane": "la savane", "Désert": "les broussailles",
	"Toundra": "la lande", "Montagnes": "les prairies d'altitude",
}
## Groupe nominal défini (sujet) et indéfini (attribut) de chaque usage habité.
const DEFINITE := {
	"camp": "le campement", "pasture": "les pâturages", "farmland": "les terres agricoles",
	"village": "le village", "town": "la petite ville", "city": "la ville",
	"megacity": "la mégapole", "arcology": "l'arcologie",
}
const INDEFINITE := {
	"camp": "un campement", "pasture": "des pâturages", "farmland": "des terres agricoles",
	"village": "un village", "town": "une petite ville", "city": "une ville",
	"megacity": "une mégapole", "arcology": "une arcologie",
}
const PLURAL_USES := ["pasture", "farmland"]


static func use_label(use: String, biome_name: String) -> String:
	if use == "wild":
		return WILD_LABELS.get(biome_name, USE_LABELS.wild)
	return USE_LABELS.get(use, use)


## {text: « les X » | « l'espèce X », plural: bool}
static func species_phrase(name: String) -> Dictionary:
	var n := name.strip_edges()
	if n == "":
		return {text = "une espèce inconnue", plural = false}
	var words := n.split(" ", false)
	var plural: bool = words[0].length() > 2 and words[0].right(1).to_lower() in ["s", "x"]
	for w in words.slice(1):
		var first := w.substr(0, 1)
		if first == first.to_lower() and first != first.to_upper() and not (w.right(1) in ["s", "x"]):
			plural = false
	return {text = ("les " if plural else "l'espèce ") + n, plural = plural}


static func is_plural(name: String) -> bool:
	return bool(species_phrase(name).plural)


## Phrase dont le sujet est l'espèce : `singular` / `plural` contiennent un %s pour le sujet.
## La majuscule initiale est ajoutée si la phrase commence par le sujet.
static func about(name: String, singular: String, plural: String) -> String:
	var p := species_phrase(name)
	return capitalize_first((plural if p.plural else singular) % p.text)


## « des Humains » / « de l'espèce Verpha moloum »
static func of_species(name: String) -> String:
	var p := species_phrase(name)
	return ("des " + name.strip_edges()) if p.plural else ("de " + String(p.text))


static func capitalize_first(s: String) -> String:
	if s == "":
		return s
	return s.substr(0, 1).to_upper() + s.substr(1)


## Nombre décimal à la française, signe explicite : « +2,4 », « -12,0 ».
static func signed_decimal(v: float) -> String:
	return ("%+.1f" % v).replace(".", ",")


## Usage habité en sujet d'une phrase (sans majuscule), avec le verbe accordé :
## « la ville se réduit », « les pâturages se réduisent ».
static func use_subject(use: String, singular_verb: String, plural_verb: String) -> String:
	var subject := String(DEFINITE.get(use, "la parcelle"))
	return "%s %s" % [subject, plural_verb if use in PLURAL_USES else singular_verb]
