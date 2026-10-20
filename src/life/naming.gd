extends RefCounted
## Noms des espèces : binômes latinisés (un genre partagé par les espèces sœurs, une épithète
## accordée au genre du nom latin), noms vernaculaires français évocateurs tirés des traits
## (« Rampeur à épines bleues ») et noms des couleurs, accordés en genre et en nombre.
## Tout est déterministe : les choix viennent de la graine de l'espèce (`gseed`) ou d'un
## générateur local, jamais du générateur partagé de la simulation.

# --- Latin ------------------------------------------------------------------------------------

## Préfixes de genre (forme de combinaison, voyelle finale élidée devant une voyelle).
const PREFIXES := ["Acantho", "Allo", "Ambly", "Anchi", "Archaeo", "Argo", "Aulaco", "Brachy",
	"Calo", "Campto", "Cteno", "Dasy", "Deino", "Dicho", "Echino", "Eo", "Eu", "Glypto", "Gnatho",
	"Halo", "Hespero", "Lepto", "Lopho", "Macro", "Mega", "Meso", "Micro", "Nano", "Neo", "Noto",
	"Nycto", "Oligo", "Ortho", "Pachy", "Palaeo", "Para", "Platy", "Pleuro", "Poly", "Proto",
	"Pseudo", "Rhino", "Sclero", "Spheno", "Stego", "Steno", "Strepto", "Tachy", "Tele",
	"Thalasso", "Trachy", "Tri", "Xeno", "Zygo", "Cerato", "Ptilo", "Lampro", "Myrmeco", "Callo",
	"Diplo", "Haplo", "Hetero", "Homo", "Iso", "Mono", "Ophio", "Sauro", "Hylo", "Petro", "Psammo",
	"Ammo", "Oxy", "Baro", "Chalco", "Crypto", "Eury", "Gyro", "Hemi", "Hypo", "Kyrto", "Megalo"]
## Préfixes selon les traits (couleur, taille, milieu, métabolisme, armes, lumière).
const TRAIT_PREFIXES := {
	"rouge": ["Erythro", "Rhodo", "Pyro"], "orange": ["Pyrrho", "Chalco"], "jaune": ["Chryso", "Xantho"],
	"vert": ["Chloro", "Prasino"], "bleu": ["Cyano", "Glauco"], "violet": ["Porphyro", "Iantho"],
	"noir": ["Melano", "Phaeo"], "blanc": ["Leuco", "Argyro"], "grand": ["Mega", "Titano", "Macro"],
	"petit": ["Micro", "Nano", "Lepto"], "abysses": ["Bathy", "Abysso", "Bentho"], "air": ["Aero", "Ptero", "Anemo"],
	"eau douce": ["Limno", "Potamo", "Helo"], "froid": ["Cryo", "Psychro"], "chaud": ["Thermo", "Pyro"],
	"chimiosynthèse": ["Thermo", "Litho", "Methano", "Thio"], "photosynthèse": ["Helio", "Photo", "Chloro"],
	"épines": ["Acantho", "Echino", "Spino"], "cornes": ["Cerato", "Cerau"], "crocs": ["Deino", "Odonto"],
	"lumière": ["Lampro", "Photo", "Lychno"], "venin": ["Toxo", "Io"],
}
## Terminaisons de genre : [forme, genre grammatical latin m/f/n].
const ENDINGS := {
	"microbe": [["coccus", "m"], ["bacter", "m"], ["monas", "f"], ["cystis", "f"], ["zoon", "n"], ["spira", "f"], ["thrix", "f"], ["bium", "n"], ["phaera", "f"]],
	"producteur": [["phyton", "n"], ["phyllum", "n"], ["dendron", "n"], ["thallus", "m"], ["cladia", "f"], ["sperma", "n"], ["phycus", "m"], ["nema", "n"], ["pteris", "f"], ["carpus", "m"]],
	"aquatique": [["caris", "f"], ["aspis", "f"], ["ichthys", "m"], ["cetus", "m"], ["conus", "m"], ["stoma", "n"], ["lepis", "f"], ["nectes", "m"], ["branchus", "m"], ["medusa", "f"], ["ceras", "n"], ["opsis", "f"]],
	"terrestre": [["saurus", "m"], ["therium", "n"], ["mys", "m"], ["odon", "m"], ["suchus", "m"], ["cyon", "m"], ["ops", "m"], ["pus", "m"], ["gnathus", "m"], ["cephalus", "m"], ["urus", "m"], ["dactylus", "m"], ["ophis", "m"], ["chelys", "f"], ["lophus", "m"]],
	"aérien": [["pteryx", "f"], ["ornis", "f"], ["pteron", "n"], ["dactylus", "m"], ["nyx", "f"], ["petes", "m"]],
	"articulé": [["caris", "f"], ["pteron", "n"], ["pus", "m"], ["opsis", "f"], ["lepis", "f"], ["merus", "m"], ["scorpius", "m"]],
}
const GENERIC_ENDINGS := [["us", "m"], ["a", "f"], ["ia", "f"], ["ella", "f"], ["um", "n"], ["ium", "n"], ["ops", "m"], ["ites", "m"], ["is", "f"]]
const MIDDLES := ["cten", "gyr", "morph", "stich", "thec", "phor", "pleur", "cerc", "rhyn", "branch",
	"derm", "plac", "sclero", "lith", "phyl", "chir", "glyph", "trem", "zyg", "stegan"]

## Épithètes régulières (première classe : -us, -a, -um).
const ROOTS_1 := ["alb", "flav", "fusc", "caerule", "purpure", "aurat", "argentat", "magn", "parv",
	"long", "lat", "angust", "spinos", "cornut", "dentat", "squamat", "pennat", "pilos", "nud",
	"lucid", "obscur", "profund", "silvatic", "montan", "gregari", "solitari", "venenos", "armat",
	"maculat", "striat", "ocellat", "pict", "robust", "rapid", "mir", "ignot", "antiqu", "primitiv",
	"tropic", "vari", "elongat", "crassicaud", "hirsut", "glab", "sanguine", "rose", "nigrescent", "erect"]
## Troisième classe : -is, -is, -e.
const ROOTS_3 := ["brev", "gracil", "abyssal", "boreal", "austral", "fluvial", "lacustr", "littoral",
	"insign", "mirabil", "terribil", "nobil", "silvestr", "campestr", "glacial", "agil", "viridis", "humil", "orientalis", "occidentalis"]
## Invariables.
const INVARIABLE := ["ferox", "elegans", "ardens", "lucens", "velox", "simplex", "abyssicola",
	"limicola", "saxicola", "arenicola", "silvicola", "rupicola", "nubicola", "thermophila",
	"draconoides", "serpentoides", "spinifer", "lucifer", "vorax", "audax", "fugax", "tenax", "rapax"]
## Composés : forme de combinaison + partie du corps, accordée (spinus, -a, -um…).
const COMBINING := ["rubri", "albi", "nigri", "flavi", "caeruli", "viridi", "magni", "parvi", "longi",
	"brevi", "lati", "multi", "pauci", "tri", "quadri", "grandi", "tenui", "crassi", "acuti", "lenti",
	"atri", "aureo", "argenti", "versi", "hirti", "levi", "macro", "micro", "angusti", "curvi"]
## [racine, classe] : 1 => -us/-a/-um ; 3 => -is/-is/-e.
const BODY_PARTS := [["spin", 1], ["corn", 3], ["pinn", 3], ["caud", 1], ["rostr", 3], ["ocul", 1],
	["dactyl", 1], ["ped", 1], ["cephal", 1], ["branchi", 1], ["dent", 1], ["lob", 1], ["plum", 1],
	["squam", 1], ["ungu", 1], ["lamin", 1], ["costat", 1], ["fili", 1], ["ram", 1], ["cer", 1], ["pter", 1], ["gnath", 1]]
const SYLLABLES := ["ra", "to", "ken", "lu", "mi", "sar", "do", "vel", "xi", "pha", "gor", "nu",
	"the", "ka", "lo", "ver", "bra", "zan", "ti", "mo", "qua", "ri", "sel", "and", "om", "ur",
	"phe", "tal", "vor", "ny", "es", "il", "cor", "dra", "len", "mar"]

## Genres types des groupes nommés en français par la simulation (rosters, GROUP_NAMES).
const TYPE_GENERA := {
	"Tyrannosauridés": "Tyrannosaurus", "Hadrosauridés": "Hadrosaurus", "Cératopsidés": "Ceratops",
	"Titanosaures": "Titanosaurus", "Ankylosauridés": "Ankylosaurus", "Dromæosauridés": "Dromaeosaurus",
	"Troodontidés": "Troodon", "Ptérosaures": "Pteranodon", "Ornithurés": "Ornithurus",
	"Crocodyliformes": "Crocodylus", "Squamates": "Lacerta", "Multituberculés": "Ptilodus",
	"Euthériens insectivores": "Eomaia", "Plésiadapiformes": "Plesiadapis",
	"Archées méthanogènes": "Methanococcus", "Bactéries pourpres": "Rhodobacter",
	"Cyanobactéries": "Synechococcus", "Protistes": "Protozoon", "Algues vertes": "Chlorella",
	"Algues rouges": "Rhodophycus", "Algues multicellulaires": "Grypania", "Mousses": "Bryum",
	"Lycophytes": "Lycopodium", "Fougères": "Pteris", "Prêles": "Equisetum", "Conifères": "Araucaria",
	"Cycadales": "Cycas", "Angiospermes": "Archaefructus", "Éponges": "Spongia", "Cnidaires": "Medusa",
	"Ediacariens": "Dickinsonia", "Trilobites": "Olenellus", "Euryptérides": "Eurypterus",
	"Crustacés": "Carcinus", "Brachiopodes": "Lingula", "Nautiloïdes": "Nautilus", "Ammonites": "Ammonites",
	"Agnathes": "Haikouichthys", "Placodermes": "Dunkleosteus", "Requins": "Cladoselache",
	"Sarcoptérygiens": "Eusthenopteron", "Insectes primitifs": "Rhyniognatha", "Méganeuridés": "Meganeura",
	"Blattoptères": "Archimylacris", "Tétrapodes": "Ichthyostega", "Temnospondyles": "Eryops",
	"Lissamphibiens": "Triadobatrachus", "Sauropsidés": "Hylonomus", "Archosauriens": "Euparkeria",
	"Pélycosaures": "Dimetrodon", "Thérapsides": "Lycaenops", "Cynodontes": "Thrinaxodon",
	"Dinosauriformes": "Marasuchus", "Théropodes": "Coelophysis", "Sauropodomorphes": "Plateosaurus",
	"Ornithischiens": "Pisanosaurus", "Mammaliaformes": "Morganucodon", "Euthériens": "Juramaia",
	"Chimère": "Chimaera",
}


## Genre grammatical (m, f, n) d'un nom de genre latin, d'après sa terminaison.
const _GENUS_GENDERS := [["odon", "m"], ["don", "m"], ["ops", "m"], ["ax", "m"], ["us", "m"],
	["ites", "m"], ["ichthys", "m"], ["mys", "m"], ["cyon", "m"], ["ophis", "m"], ["es", "m"],
	["bacter", "m"], ["er", "m"], ["ceras", "n"], ["ma", "n"], ["um", "n"], ["on", "n"],
	["opsis", "f"], ["a", "f"], ["is", "f"], ["ys", "f"], ["yx", "f"], ["ix", "f"], ["nyx", "f"],
	["as", "f"], ["thrix", "f"]]


static func _gender_of(genus: String) -> String:
	var g := genus.to_lower()
	for pair in _GENUS_GENDERS:
		if g.ends_with(String(pair[0])):
			return String(pair[1])
	return "m"


static func _cap(s: String) -> String:
	return s if s.is_empty() else s.substr(0, 1).to_upper() + s.substr(1)


static func _elide(prefix: String, ending: String) -> String:
	var vowels := "aeiouy"
	if ending.length() > 0 and vowels.contains(ending[0]) and prefix.length() > 2 \
			and "aoe".contains(prefix[prefix.length() - 1]):
		return prefix.substr(0, prefix.length() - 1)
	return prefix


static func _category(t: Dictionary) -> String:
	if t.is_empty():
		return ""
	var p := String(t.get("body_plan", ""))
	if String(t.get("diet", "")) == "autotrophe":
		return "microbe" if p == "unicellulaire" else "producteur"
	if p == "unicellulaire":
		return "microbe"
	if String(t.get("locomotion", "")) == "vol":
		return "aérien"
	if String(t.get("skeleton", "")) == "exosquelette":
		return "articulé"
	return "terrestre" if String(t.get("habitat", "marine")) == "land" else "aquatique"


## Mots-clés des traits pour choisir des racines parlantes.
static func trait_keys(t: Dictionary) -> Array:
	var keys := []
	if t.is_empty():
		return keys
	var fam := color_family(t)
	if fam != "":
		keys.append(fam)
	var s := float(t.get("size", 0.3))
	if s > 0.7:
		keys.append("grand")
	elif s < 0.05 and String(t.get("body_plan", "")) != "unicellulaire":
		keys.append("petit")
	var m := String(t.get("milieu", ""))
	if m == "abysses" or m == "air" or m == "eau douce":
		keys.append(m)
	var temp := float(t.get("temp_opt", 0.5))
	if temp < 0.3:
		keys.append("froid")
	elif temp > 0.75:
		keys.append("chaud")
	var met := String(t.get("metabolism", ""))
	if met == "chimiosynthèse" or met == "photosynthèse":
		keys.append(met)
	for w in t.get("weapons", []):
		if TRAIT_PREFIXES.has(w):
			keys.append(w)
	if bool(t.get("biolum", false)):
		keys.append("lumière")
	return keys


## Genre latin nouveau, parlant si les traits sont connus.
static func latin_genus(g: RandomNumberGenerator, t := {}) -> String:
	var keys := trait_keys(t)
	var prefix: String
	if not keys.is_empty() and g.randf() < 0.6:
		var pool: Array = TRAIT_PREFIXES[keys[g.randi_range(0, keys.size() - 1)]]
		prefix = pool[g.randi_range(0, pool.size() - 1)]
	else:
		prefix = PREFIXES[g.randi_range(0, PREFIXES.size() - 1)]
	var cat := _category(t)
	var ending: Array
	if cat != "" and g.randf() < 0.75:
		var pool: Array = ENDINGS[cat]
		ending = pool[g.randi_range(0, pool.size() - 1)]
	else:
		var all: Array = ENDINGS.values()
		if g.randf() < 0.35:
			ending = GENERIC_ENDINGS[g.randi_range(0, GENERIC_ENDINGS.size() - 1)]
		else:
			var pool: Array = all[g.randi_range(0, all.size() - 1)]
			ending = pool[g.randi_range(0, pool.size() - 1)]
	var middle := ""
	if g.randf() < 0.3:
		middle = MIDDLES[g.randi_range(0, MIDDLES.size() - 1)] + ("o" if not "aeiou".contains(String(ending[0])[0]) else "")
	var word := (_elide(prefix, middle) + middle) if middle != "" else prefix
	word = _elide(word, String(ending[0])) + String(ending[0])
	# Pas de voyelle doublée à la jointure (Scleroophaera -> Sclerophaera).
	return _cap(word.replace("oo", "o").replace("aa", "a"))


static func _decline(root: String, cls: int, gender: String) -> String:
	if cls == 3:
		return root + ("e" if gender == "n" else "is") if not root.ends_with("is") else \
			(root.substr(0, root.length() - 2) + "e" if gender == "n" else root)
	return root + {"m": "us", "f": "a", "n": "um"}[gender]


static func _trait_roots(t: Dictionary) -> Array:
	var out := []
	if t.is_empty():
		return out
	match color_family(t):
		"rouge":
			out.append_array([["sanguine", 1], ["rubri", 0]])
		"jaune":
			out.append_array([["flav", 1], ["aurat", 1]])
		"vert":
			out.append_array([["viridis", 3]])
		"bleu":
			out.append_array([["caerule", 1]])
		"violet":
			out.append_array([["purpure", 1]])
		"noir":
			out.append_array([["nigrescent", 1], ["fusc", 1]])
		"blanc":
			out.append_array([["alb", 1], ["argentat", 1]])
	var w: Array = t.get("weapons", [])
	if w.has("épines"):
		out.append(["spinos", 1])
	if w.has("cornes"):
		out.append(["cornut", 1])
	if w.has("venin"):
		out.append(["venenos", 1])
	match String(t.get("pattern", "")):
		"rayé":
			out.append(["striat", 1])
		"tacheté":
			out.append(["maculat", 1])
		"ocellé":
			out.append(["ocellat", 1])
	match String(t.get("milieu", "")):
		"abysses":
			out.append_array([["abyssal", 3], ["abyssicola", 0], ["profund", 1]])
		"eau douce":
			out.append_array([["fluvial", 3], ["limicola", 0], ["lacustr", 3]])
		"air":
			out.append(["nubicola", 0])
	if float(t.get("size", 0.3)) > 0.7:
		out.append(["magn", 1])
	if bool(t.get("biolum", false)):
		out.append_array([["lucens", 0], ["lucifer", 0]])
	if String(t.get("covering", "")) == "poils":
		out.append(["hirsut", 1])
	if String(t.get("metabolism", "")) == "chimiosynthèse":
		out.append(["thermophila", 0])
	return out


## Formes de combinaison et parties du corps tirées des traits (rubri-, -spinus…).
const TRAIT_COMBINING := {
	"rouge": ["rubri", "sanguini"], "orange": ["fulvi", "croceo"], "jaune": ["flavi", "aureo"],
	"vert": ["viridi", "chloro"], "bleu": ["caeruli", "glauco"], "violet": ["purpureo", "ianthi"],
	"noir": ["nigri", "atri"], "blanc": ["albi", "argenti"], "grand": ["magni", "grandi"],
	"petit": ["parvi", "minuti"],
}
const TRAIT_PARTS := {
	"épines": ["spin", 1], "cornes": ["corn", 3], "crocs": ["dent", 1], "griffes": ["ungu", 1],
	"pinces": ["chel", 1], "plumes": ["plum", 1], "écailles": ["squam", 1], "ailes": ["pter", 1],
	"yeux": ["ocul", 1], "frondes": ["foli", 1],
}


static func _trait_compound(g: RandomNumberGenerator, gender: String, t: Dictionary) -> String:
	var combs := []
	var fam := color_family(t)
	if TRAIT_COMBINING.has(fam):
		combs.append_array(TRAIT_COMBINING[fam])
	var s := float(t.get("size", 0.3))
	if s > 0.7:
		combs.append_array(TRAIT_COMBINING["grand"])
	elif s < 0.05:
		combs.append_array(TRAIT_COMBINING["petit"])
	var parts := []
	for w in t.get("weapons", []):
		if TRAIT_PARTS.has(w):
			parts.append(TRAIT_PARTS[w])
	var cover := String(t.get("covering", ""))
	if TRAIT_PARTS.has(cover):
		parts.append(TRAIT_PARTS[cover])
	if bool(t.get("wings", false)):
		parts.append(TRAIT_PARTS["ailes"])
	if (t.get("senses", []) as Array).has("yeux") and g.randf() < 0.3:
		parts.append(TRAIT_PARTS["yeux"])
	if combs.is_empty() and parts.is_empty():
		return ""
	var comb: String = COMBINING[g.randi_range(0, COMBINING.size() - 1)]
	if not combs.is_empty() and (parts.is_empty() or g.randf() < 0.6):
		comb = combs[g.randi_range(0, combs.size() - 1)]
	var bp: Array = _body_part(g, t)
	if not parts.is_empty() and (combs.is_empty() or g.randf() < 0.6):
		bp = parts[g.randi_range(0, parts.size() - 1)]
	return comb + _decline(String(bp[0]), int(bp[1]), gender)


## Parties du corps des producteurs et des microbes (pas de « rostris » pour un arbre).
const PLANT_PARTS := [["foli", 1], ["caul", 3], ["phyll", 1], ["carp", 1], ["flor", 1], ["spor", 1],
	["ram", 1], ["cortic", 1], ["radic", 1], ["thall", 1]]
const MICRO_PARTS := [["cocc", 1], ["bacill", 1], ["fil", 1], ["spir", 1], ["cyst", 1], ["flagell", 1], ["granul", 1]]


static func _body_part(g: RandomNumberGenerator, t: Dictionary) -> Array:
	var pool: Array = BODY_PARTS
	match _category(t):
		"microbe":
			pool = MICRO_PARTS
		"producteur":
			pool = PLANT_PARTS
	return pool[g.randi_range(0, pool.size() - 1)]


## Épithète accordée au genre grammatical du genre latin : souvent parlante (couleur, armes,
## milieu), parfois générique ou inventée, pour que les espèces sœurs ne se confondent pas.
static func latin_epithet(g: RandomNumberGenerator, gender: String, t := {}) -> String:
	var r := g.randf()
	if r < 0.2 and not t.is_empty():
		var c := _trait_compound(g, gender, t)
		if c != "":
			return c
	var tr := _trait_roots(t)
	if r >= 0.2 and r < 0.26 and not tr.is_empty():
		var pick: Array = tr[g.randi_range(0, tr.size() - 1)]
		if int(pick[1]) == 0:
			if String(pick[0]).ends_with("i"):
				var bp: Array = _body_part(g, t)
				return String(pick[0]) + _decline(String(bp[0]), int(bp[1]), gender)
			return String(pick[0])
		return _decline(String(pick[0]), int(pick[1]), gender)
	if r < 0.6:
		var bp: Array = _body_part(g, t)
		return COMBINING[g.randi_range(0, COMBINING.size() - 1)] + _decline(String(bp[0]), int(bp[1]), gender)
	if r < 0.7:
		var k := g.randi_range(0, ROOTS_1.size() + ROOTS_3.size() + INVARIABLE.size() - 1)
		if k < ROOTS_1.size():
			return _decline(ROOTS_1[k], 1, gender)
		k -= ROOTS_1.size()
		if k < ROOTS_3.size():
			return _decline(ROOTS_3[k], 3, gender)
		return INVARIABLE[k - ROOTS_3.size()]
	# Racine inventée.
	var root := ""
	for i in g.randi_range(2, 3):
		root += SYLLABLES[g.randi_range(0, SYLLABLES.size() - 1)]
	if g.randf() < 0.25:
		return root + ("i" if root.ends_with("i") else "ii")
	return _decline(root, 1 if g.randf() < 0.7 else 3, gender)


## Genre latin d'un nom existant : premier mot latin, ou genre type d'un groupe nommé en français.
static func genus_of(name: String) -> String:
	if TYPE_GENERA.has(name):
		return TYPE_GENERA[name]
	var first := name.split(" ")[0]
	if first.length() < 3:
		return ""
	# Un nom français (accents, pluriel en -s/-és) n'est pas un genre latin.
	for ch in ["é", "è", "ê", "à", "ç", "æ", "ï", "ô", "É"]:
		if first.contains(ch):
			return ""
	if name.split(" ").size() < 2 and first.ends_with("s") and not (first.ends_with("us") or first.ends_with("is") \
			or first.ends_with("ys") or first.ends_with("ops") or first.ends_with("ites") or first.ends_with("as")):
		return ""
	return first


## Binôme latin. `genus` : genre imposé (vide => nouveau genre tiré de g et des traits).
static func binomial(g: RandomNumberGenerator, genus := "", t := {}) -> String:
	if genus == "":
		genus = latin_genus(g, t)
	return "%s %s" % [genus, latin_epithet(g, _gender_of(genus), t)]


## Garantit l'unicité d'un nom dans un registre {nom: true} (suffixe d'épithète, puis variante).
static func unique(name: String, used: Dictionary, g: RandomNumberGenerator, t := {}) -> String:
	var n := name
	var tries := 0
	while used.has(n) and tries < 32:
		tries += 1
		var parts := name.split(" ")
		if parts.size() >= 2 and tries < 24:
			n = binomial(g, parts[0], t)
		else:
			n = "%s %s" % [name, ["minor", "major", "alter", "novus", "secundus", "tertius"][tries % 6]]
	used[n] = true
	return n


# --- Couleurs ---------------------------------------------------------------------------------

## [masc. sing., fém. sing., masc. plur., fém. plur.]
const COLOR_FORMS := {
	"rouge": ["rouge", "rouge", "rouges", "rouges"], "écarlate": ["écarlate", "écarlate", "écarlates", "écarlates"],
	"vermillon": ["vermillon", "vermillon", "vermillon", "vermillon"], "grenat": ["grenat", "grenat", "grenat", "grenat"],
	"orangé": ["orangé", "orangée", "orangés", "orangées"], "cuivré": ["cuivré", "cuivrée", "cuivrés", "cuivrées"],
	"fauve": ["fauve", "fauve", "fauves", "fauves"], "brun": ["brun", "brune", "bruns", "brunes"],
	"ocre": ["ocre", "ocre", "ocre", "ocre"], "jaune": ["jaune", "jaune", "jaunes", "jaunes"],
	"doré": ["doré", "dorée", "dorés", "dorées"], "olive": ["olive", "olive", "olive", "olive"],
	"vert": ["vert", "verte", "verts", "vertes"], "émeraude": ["émeraude", "émeraude", "émeraude", "émeraude"],
	"turquoise": ["turquoise", "turquoise", "turquoise", "turquoise"], "bleu": ["bleu", "bleue", "bleus", "bleues"],
	"azur": ["azur", "azur", "azur", "azur"], "indigo": ["indigo", "indigo", "indigo", "indigo"],
	"violet": ["violet", "violette", "violets", "violettes"], "pourpre": ["pourpre", "pourpre", "pourpres", "pourpres"],
	"mauve": ["mauve", "mauve", "mauves", "mauves"], "rose": ["rose", "rose", "roses", "roses"],
	"noir": ["noir", "noire", "noirs", "noires"], "gris": ["gris", "grise", "gris", "grises"],
	"blanc": ["blanc", "blanche", "blancs", "blanches"], "argenté": ["argenté", "argentée", "argentés", "argentées"],
	"nacré": ["nacré", "nacrée", "nacrés", "nacrées"], "translucide": ["translucide", "translucide", "translucides", "translucides"],
}
## Familles de couleur (pour les racines parlantes) des noms de COLOR_FORMS.
const COLOR_FAMILY := {
	"rouge": "rouge", "écarlate": "rouge", "vermillon": "rouge", "grenat": "rouge", "orangé": "orange",
	"cuivré": "orange", "fauve": "orange", "brun": "orange", "ocre": "orange", "jaune": "jaune",
	"doré": "jaune", "olive": "vert", "vert": "vert", "émeraude": "vert", "turquoise": "bleu",
	"bleu": "bleu", "azur": "bleu", "indigo": "bleu", "violet": "violet", "pourpre": "violet",
	"mauve": "violet", "rose": "rouge", "noir": "noir", "gris": "noir", "blanc": "blanc",
	"argenté": "blanc", "nacré": "blanc", "translucide": "blanc",
}


static func _syn(options: Array, seed: int) -> String:
	return options[posmod(seed, options.size())]


## Nom de base (clé de COLOR_FORMS) et nuance ("", "sombre", "pâle") de la couleur d'une espèce.
static func color_key(t: Dictionary) -> Array:
	var h := fposmod(float(t.get("hue", 0.3)), 1.0)
	var s := float(t.get("sat", 0.6))
	var v := float(t.get("val", 0.6))
	var seed := int(t.get("gseed", 0)) >> 3
	var key := ""
	var shade := ""
	if s < 0.18:
		if v < 0.22:
			return ["noir", ""]
		if v < 0.55:
			return ["gris", "sombre" if v < 0.35 else ""]
		if v < 0.8:
			return [_syn(["gris", "argenté"], seed), ""]
		if String(t.get("covering", "")) == "membrane":
			return ["translucide", ""]
		return [_syn(["blanc", "nacré", "blanc"], seed), ""]
	if h < 0.035 or h >= 0.96:
		key = "grenat" if v < 0.4 else _syn(["rouge", "écarlate", "vermillon", "rouge"], seed)
	elif h < 0.09:
		key = "brun" if v < 0.45 else _syn(["orangé", "cuivré", "orangé"], seed)
	elif h < 0.14:
		key = _syn(["brun", "fauve"], seed) if v < 0.55 else _syn(["ocre", "fauve", "doré"], seed)
	elif h < 0.19:
		key = "olive" if v < 0.5 else _syn(["jaune", "doré", "jaune"], seed)
	elif h < 0.45:
		key = "olive" if v < 0.4 else ("émeraude" if h > 0.36 and s > 0.7 else "vert")
	elif h < 0.53:
		key = "turquoise"
	elif h < 0.66:
		key = "azur" if v > 0.85 and s < 0.6 else "bleu"
	elif h < 0.76:
		key = "indigo" if v < 0.6 else "violet"
	elif h < 0.88:
		key = "mauve" if s < 0.4 else _syn(["violet", "pourpre"], seed)
	else:
		key = "rose" if v > 0.7 and s < 0.6 else "pourpre"
	if v < 0.3 and key != "grenat" and key != "brun" and key != "olive" and key != "indigo":
		shade = "sombre"
	elif v > 0.9 and s < 0.45:
		shade = "pâle"
	return [key, shade]


static func color_family(t: Dictionary) -> String:
	if not t.has("hue"):
		return ""
	return COLOR_FAMILY.get(color_key(t)[0], "")


## Adjectif de couleur accordé. Une couleur nuancée (« bleu sombre ») est invariable.
static func color_adj(t: Dictionary, feminine: bool, plural: bool) -> String:
	var ck := color_key(t)
	var forms: Array = COLOR_FORMS[ck[0]]
	if String(ck[1]) != "":
		return "%s %s" % [forms[0], ck[1]]
	return forms[(1 if feminine else 0) + (2 if plural else 0)]


## Nom de couleur pour l'interface (« bleu sombre »).
static func color_name(t: Dictionary) -> String:
	return color_adj(t, false, false)


## Couleur de contraste pour les motifs (« rayé de noir », « tacheté d'or »).
static func accent(t: Dictionary) -> String:
	var v := float(t.get("val", 0.6))
	var seed := int(t.get("gseed", 0)) >> 5
	if v > 0.5:
		return _syn(["de noir", "de brun", "de pourpre", "de noir", "de vert sombre", "de bleu nuit"], seed)
	return _syn(["de blanc", "d'or", "de jaune", "d'argent", "de rouge", "de blanc"], seed)


# --- Accords ----------------------------------------------------------------------------------

## Adjectif régulier accordé : [m. s., f. s., m. pl., f. pl.].
static func agree(forms: Array, feminine: bool, plural: bool) -> String:
	return forms[(1 if feminine else 0) + (2 if plural else 0)]


static func plural_noun(word: String) -> String:
	if word.ends_with("s") or word.ends_with("x") or word.ends_with("z"):
		return word
	if word.ends_with("eau") or word.ends_with("au"):
		return word + "x"
	if word.ends_with("al") and word != "carnaval":
		return word.substr(0, word.length() - 2) + "aux"
	return word + "s"


static func starts_with_vowel(word: String) -> bool:
	if word.is_empty():
		return false
	var c := word.substr(0, 1).to_lower()
	return "aeiouyéèêàâîôûœh".contains(c) and not word.to_lower().begins_with("hu") \
		and not word.to_lower().begins_with("ha") and not word.to_lower().begins_with("ho")


# --- Noms vernaculaires -----------------------------------------------------------------------

## Têtes de nom : [mot, féminin ?] par catégorie de vie.
const HEADS := {
	"chimio": [["Perle", true], ["Grain", false], ["Voile", false], ["Braise", true], ["Poussière", true], ["Croûte", true], ["Givre", false], ["Rouille", true], ["Suie", true], ["Gangue", true], ["Limon", false], ["Tison", false]],
	"photo_micro": [["Voile", false], ["Nappe", true], ["Écume", true], ["Tapis", false], ["Poudre", true], ["Fleur d'eau", true], ["Brume", true], ["Buée", true], ["Moire", true], ["Gaze", true], ["Lueur", true], ["Teinte", true]],
	"micro": [["Errant", false], ["Grain", false], ["Rôdeuse", true], ["Goutte", true], ["Tourbillon", false], ["Vrille", true], ["Fouet", false], ["Toupie", true], ["Flocon", false], ["Rôdeur", false]],
	"algue": [["Ruban", false], ["Chevelure", true], ["Frange", true], ["Lame", true], ["Nappe", true], ["Dentelle", true], ["Crinière", true], ["Écharpe", true], ["Toison", true], ["Guirlande", true], ["Plumeau", false], ["Fil", false]],
	"mousse": [["Mousse", true], ["Croûte", true], ["Tapis", false], ["Coussin", false], ["Velours", false], ["Feutre", false], ["Gazon", false], ["Pelouse", true]],
	"plante": [["Plumet", false], ["Hampe", true], ["Ombrelle", true], ["Colonne", true], ["Panache", false], ["Éventail", false], ["Candélabre", false]],
	"arbre": [["Pilier", false], ["Tour", true], ["Arbre", false], ["Géant", false], ["Cathédrale", true]],
	"filtreur": [["Corbeille", true], ["Coupe", true], ["Éventail", false], ["Calice", false], ["Tamis", false], ["Urne", true], ["Buisson", false], ["Vase", false], ["Gorgone", true], ["Chandelier", false], ["Grenier de mer", false], ["Fleur de pierre", true], ["Panier", false], ["Ruche de mer", true]],
	"dérive": [["Cloche", true], ["Ombrelle", true], ["Voilier", false], ["Lanterne", true], ["Bulle", true], ["Méduse", true], ["Montgolfière", true], ["Parasol", false], ["Cœur de verre", false], ["Robe", true]],
	"nage": [["Nageur", false], ["Fuseau", false], ["Flèche", true], ["Plongeur", false], ["Glisseur", false], ["Lame", true], ["Torpille", true]],
	"rampe": [["Rampeur", false], ["Fouisseur", false], ["Traîneur", false], ["Fileuse", true], ["Laboureur", false], ["Rôdeuse", true], ["Ondoyant", false], ["Glisseuse", true], ["Tisseuse", true], ["Fileur", false]],
	"marche": [["Marcheur", false], ["Arpenteur", false], ["Coureur", false], ["Trotteur", false], ["Errant", false], ["Pas-de-velours", false], ["Vagabond", false], ["Promeneuse", true], ["Pèlerin", false], ["Batteur", false], ["Sentinelle", true]],
	"grand": [["Colosse", false], ["Titan", false], ["Mastodonte", false], ["Montagne", true], ["Béhémoth", false]],
	"saut": [["Sauteur", false], ["Bondisseur", false], ["Ressort", false], ["Gambadeur", false], ["Bondissante", true]],
	"vol": [["Voilier", false], ["Planeur", false], ["Aile", true], ["Virevolteur", false], ["Flèche", true], ["Danseuse", true]],
	"fixe": [["Ancre", true], ["Bouche", true], ["Guetteur", false], ["Tourelle", true]],
	"carnivore": [["Chasseur", false], ["Traqueur", false], ["Croqueur", false], ["Guetteur", false], ["Faucheuse", true], ["Rôdeur", false]],
	"herbivore": [["Brouteur", false], ["Glaneur", false], ["Cueilleur", false], ["Râpeur", false], ["Paisible", false], ["Tondeuse", true], ["Mâchonneur", false], ["Ruminant", false], ["Effeuilleuse", true]],
	"omnivore": [["Fouineur", false], ["Glaneur", false], ["Chapardeur", false], ["Fureteur", false], ["Grappilleuse", true], ["Picoreur", false], ["Maraudeur", false], ["Bricoleuse", true]],
}
## Traits saillants : [nom de la partie, féminin ?, pluriel ?] ; la couleur s'y accorde.
const FEATURES := {
	"épines": ["épines", true, true], "cornes": ["cornes", true, true], "crocs": ["crocs", false, true],
	"pinces": ["pinces", true, true], "griffes": ["griffes", true, true], "venin": ["dard", false, false],
	"écailles": ["écailles", true, true], "plumes": ["plumes", true, true], "poils": ["pelage", false, false],
	"carapace": ["carapace", true, false], "peau nue": ["peau", true, false], "écorce": ["écorce", true, false],
	"frondes": ["frondes", true, true], "membrane": ["membrane", true, false], "yeux": ["yeux", false, true],
	"ailes": ["ailes", true, true], "nageoires": ["nageoires", true, true], "tentacules": ["tentacules", false, true],
}
const PLACES := {
	"abysses": ["des abysses", "des grands fonds", "des sources noires", "de l'abîme", "des plaines abyssales", "des eaux sans lumière"],
	"mer peu profonde": ["des récifs", "des lagons", "des hauts-fonds", "des rivages", "des herbiers", "des estrans", "des baies tièdes", "des écueils", "de la haute mer"],
	"eau douce": ["des marais", "des rivières", "des lacs", "des estuaires", "des tourbières"],
	"terre_froid": ["des toundras", "des glaces", "des steppes froides", "des neiges"],
	"terre": ["des plaines", "des forêts", "des collines", "des falaises", "des vallées", "des bois"],
	"terre_chaud": ["des déserts", "des sables", "des savanes", "des forêts chaudes"],
	"air": ["des cimes", "des nuées", "des vents", "des falaises", "du ciel"],
	"sources": ["des sources chaudes", "des fumerolles", "des cheminées sous-marines", "des failles brûlantes", "des évents noirs", "des roches fumantes"],
}
const ADJ := {
	"géant": ["géant", "géante", "géants", "géantes"], "nain": ["nain", "naine", "nains", "naines"],
	"lumineux": ["lumineux", "lumineuse", "lumineux", "lumineuses"],
	"venimeux": ["venimeux", "venimeuse", "venimeux", "venimeuses"],
	"aveugle": ["aveugle", "aveugle", "aveugles", "aveugles"],
	"grégaire": ["grégaire", "grégaire", "grégaires", "grégaires"],
	"solitaire": ["solitaire", "solitaire", "solitaires", "solitaires"],
	"cornu": ["cornu", "cornue", "cornus", "cornues"], "épineux": ["épineux", "épineuse", "épineux", "épineuses"],
	"cuirassé": ["cuirassé", "cuirassée", "cuirassés", "cuirassées"], "velu": ["velu", "velue", "velus", "velues"],
	"ailé": ["ailé", "ailée", "ailés", "ailées"], "furtif": ["furtif", "furtive", "furtifs", "furtives"],
	"agile": ["agile", "agile", "agiles", "agiles"], "lent": ["lent", "lente", "lents", "lentes"],
	"colossal": ["colossal", "colossale", "colossaux", "colossales"],
	"rayé": ["rayé", "rayée", "rayés", "rayées"], "tacheté": ["tacheté", "tachetée", "tachetés", "tachetées"],
	"ocellé": ["ocellé", "ocellée", "ocellés", "ocellées"], "uni": ["uni", "unie", "unis", "unies"],
	"nocturne": ["nocturne", "nocturne", "nocturnes", "nocturnes"],
	"ardent": ["ardent", "ardente", "ardents", "ardentes"],
	"discret": ["discret", "discrète", "discrets", "discrètes"], "farouche": ["farouche", "farouche", "farouches", "farouches"],
	"tranquille": ["tranquille", "tranquille", "tranquilles", "tranquilles"], "vorace": ["vorace", "vorace", "voraces", "voraces"],
	"chanteur": ["chanteur", "chanteuse", "chanteurs", "chanteuses"], "fouisseur": ["fouisseur", "fouisseuse", "fouisseurs", "fouisseuses"],
	"grand": ["Grand", "Grande", "Grands", "Grandes"], "petit": ["Petit", "Petite", "Petits", "Petites"],
	"filamenteux": ["filamenteux", "filamenteuse", "filamenteux", "filamenteuses"],
	"spiralé": ["spiralé", "spiralée", "spiralés", "spiralées"], "visqueux": ["visqueux", "visqueuse", "visqueux", "visqueuses"],
	"tenace": ["tenace", "tenace", "tenaces", "tenaces"], "frémissant": ["frémissant", "frémissante", "frémissants", "frémissantes"],
	"granuleux": ["granuleux", "granuleuse", "granuleux", "granuleuses"], "soyeux": ["soyeux", "soyeuse", "soyeux", "soyeuses"],
	"vagabond": ["vagabond", "vagabonde", "vagabonds", "vagabondes"], "patient": ["patient", "patiente", "patients", "patientes"],
	"rouillé": ["rouillé", "rouillée", "rouillés", "rouillées"], "perlé": ["perlé", "perlée", "perlés", "perlées"],
	"poreux": ["poreux", "poreuse", "poreux", "poreuses"], "frangé": ["frangé", "frangée", "frangés", "frangées"],
	"ondulant": ["ondulant", "ondulante", "ondulants", "ondulantes"], "dentelé": ["dentelé", "dentelée", "dentelés", "dentelées"],
	"ancien": ["ancien", "ancienne", "anciens", "anciennes"], "infatigable": ["infatigable", "infatigable", "infatigables", "infatigables"],
}
const MICRO_ADJ_KEYS := ["filamenteux", "spiralé", "visqueux", "tenace", "frémissant", "granuleux",
	"soyeux", "vagabond", "patient", "rouillé", "perlé", "ancien", "infatigable"]


## Catégorie du nom vernaculaire (clé de HEADS).
static func head_category(t: Dictionary, g: RandomNumberGenerator) -> String:
	var p := String(t.get("body_plan", "bilatéral"))
	var met := String(t.get("metabolism", "hétérotrophe"))
	if met == "chimiosynthèse":
		return "chimio"
	if met == "photosynthèse":
		if p == "unicellulaire":
			return "photo_micro"
		if String(t.get("habitat", "")) != "land":
			return "algue"
		if String(t.get("covering", "")) == "écorce":
			return "arbre"
		return "mousse" if p == "colonial" else "plante"
	if p == "unicellulaire":
		return "micro"
	var loco := String(t.get("locomotion", ""))
	if p != "bilatéral":
		return "filtreur" if loco == "fixe" else "dérive"
	if float(t.get("size", 0.3)) > 0.75 and loco != "vol" and g.randf() < 0.6:
		return "grand"
	if g.randf() < 0.35:
		return String(t.get("diet", "omnivore"))
	if HEADS.has(loco):
		return loco
	return String(t.get("diet", "omnivore"))


static func _place(t: Dictionary, g: RandomNumberGenerator) -> String:
	var m := String(t.get("milieu", "terre"))
	var key := m
	if String(t.get("metabolism", "")) == "chimiosynthèse":
		key = "sources"
	elif m == "terre":
		var temp := float(t.get("temp_opt", 0.5))
		key = "terre_froid" if temp < 0.3 else ("terre_chaud" if temp > 0.72 else "terre")
	var pool: Array = PLACES.get(key, PLACES["terre"])
	return pool[g.randi_range(0, pool.size() - 1)]


## Partie saillante du corps : [nom, féminin, pluriel], ou [] s'il n'y en a pas.
static func salient_feature(t: Dictionary, g: RandomNumberGenerator) -> Array:
	var opts := []
	for w in t.get("weapons", []):
		opts.append(FEATURES[w])
		opts.append(FEATURES[w])
	var cover := String(t.get("covering", ""))
	if FEATURES.has(cover) and cover != "membrane":
		opts.append(FEATURES[cover])
	if bool(t.get("wings", false)):
		opts.append(FEATURES["ailes"])
	if String(t.get("body_plan", "")) == "radial" and int(t.get("limbs", 0)) > 0:
		opts.append(FEATURES["tentacules"])
	if opts.is_empty():
		return []
	return opts[g.randi_range(0, opts.size() - 1)]


## Adjectifs possibles pour la tête du nom (clés de ADJ, ou "couleur").
static func _head_adjectives(t: Dictionary) -> Array:
	var out := ["couleur", "couleur"]
	var pat := String(t.get("pattern", "uni"))
	if pat != "uni":
		out.append(pat)
	if bool(t.get("biolum", false)):
		out.append_array(["lumineux", "lumineux"])
	if String(t.get("body_plan", "")) == "unicellulaire" or String(t.get("body_plan", "")) == "colonial":
		out.append_array(MICRO_ADJ_KEYS)
	elif String(t.get("body_plan", "")) == "radial":
		out.append_array(["poreux", "frangé", "ondulant", "dentelé", "patient", "perlé", "soyeux"])
	var w: Array = t.get("weapons", [])
	if w.has("venin"):
		out.append("venimeux")
	if w.has("épines"):
		out.append("épineux")
	if w.has("cornes"):
		out.append("cornu")
	var p := String(t.get("body_plan", ""))
	if p == "bilatéral" and not (t.get("senses", []) as Array).has("yeux"):
		out.append("aveugle")
	var s := float(t.get("sociability", 0.5))
	if p != "unicellulaire" and p != "colonial":
		if s > 0.8:
			out.append("grégaire")
		elif s < 0.15:
			out.append("solitaire")
	if String(t.get("covering", "")) == "carapace":
		out.append("cuirassé")
	if String(t.get("covering", "")) == "poils":
		out.append("velu")
	if String(t.get("metabolism", "")) == "hétérotrophe":
		if float(t.get("aggression", 0.5)) > 0.8:
			out.append_array(["vorace", "farouche"])
		elif float(t.get("aggression", 0.5)) < 0.2:
			out.append_array(["tranquille", "discret"])
		if String(t.get("locomotion", "")) == "rampe" and String(t.get("milieu", "")) == "terre":
			out.append("fouisseur")
		if bool(t.get("warm_blooded", false)) and String(t.get("covering", "")) == "plumes":
			out.append("chanteur")
	if float(t.get("temp_opt", 0.5)) > 0.8:
		out.append("ardent")
	var size := float(t.get("size", 0.3))
	if p == "bilatéral":
		if size > 0.85:
			out.append("colossal")
		elif size > 0.65:
			out.append("géant")
		elif size < 0.04:
			out.append("nain")
	return out


## Adjectif accordé ; "couleur" => couleur de l'espèce.
static func _adj_text(key: String, t: Dictionary, fem: bool, plural: bool) -> String:
	if key == "couleur":
		return color_adj(t, fem, plural)
	return agree(ADJ[key], fem, plural)


## Nom vernaculaire français (« Rampeur à épines bleues », « Voilier pourpre des cimes »).
## `plural` : forme plurielle (« Rampeurs à épines bleues »). Déterministe pour une espèce.
static func vernacular(t: Dictionary, plural := false) -> String:
	var parts := vernacular_parts(t)
	return assemble(parts, plural)


## Structure du nom vernaculaire : {head, fem, pre, adj, compl}, accordable au singulier/pluriel.
static func vernacular_parts(t: Dictionary) -> Dictionary:
	var g := RandomNumberGenerator.new()
	g.seed = hash(["vernaculaire", int(t.get("gseed", 0))])
	var cat := head_category(t, g)
	var heads: Array = HEADS.get(cat, HEADS["omnivore"])
	var head: Array = heads[g.randi_range(0, heads.size() - 1)]
	var fem := bool(head[1])
	var adjs := _head_adjectives(t)
	var feature := salient_feature(t, g)
	var form := g.randi_range(0, 7)
	var parts := {head = String(head[0]), fem = fem, pre = "", adj = "", compl = ""}
	# Pas de redite entre la tête, l'adjectif et le complément (« Colosse colossal », « épineux à épines »).
	var redundant := {"épines": "épineux", "cornes": "cornu", "dard": "venimeux", "pelage": "velu",
		"carapace": "cuirassé", "ailes": "ailé"}
	if not feature.is_empty() and redundant.has(String(feature[0])):
		adjs.erase(redundant[String(feature[0])])
	if cat == "grand":
		adjs.erase("géant")
		adjs.erase("colossal")
	var adj_key: String = adjs[g.randi_range(0, adjs.size() - 1)]
	var size := float(t.get("size", 0.3))
	var compl := ""
	if not feature.is_empty():
		# La couleur s'accorde avec la partie du corps : « à épines bleues », « au pelage roux ».
		var fnoun: String = feature[0]
		var col := color_adj(t, bool(feature[1]), bool(feature[2]))
		if fnoun == "pelage" or fnoun == "dard":
			compl = "au %s %s" % [fnoun, col]
		elif fnoun == "yeux":
			compl = "aux yeux %s" % col
		else:
			compl = "à %s %s" % [fnoun, col]
		if adj_key == "couleur":
			var others := adjs.filter(func(a): return a != "couleur")
			adj_key = others[g.randi_range(0, others.size() - 1)] if not others.is_empty() else ""
	var place := _place(t, g)
	if compl == "" and g.randf() < 0.35:
		compl = "aux reflets %s" % color_adj(t, false, true)
		if adj_key == "couleur":
			var others := adjs.filter(func(a): return a != "couleur")
			adj_key = others[g.randi_range(0, others.size() - 1)] if not others.is_empty() else ""
	match form:
		0, 1:
			parts.adj = adj_key
			parts.compl = compl if compl != "" else place
		2:
			parts.compl = (compl + " " + place).strip_edges() if compl != "" and g.randf() < 0.5 else (compl if compl != "" else place)
			if compl == "":
				parts.adj = adj_key
		3:
			parts.adj = adj_key
			parts.compl = place
		4:
			parts.compl = compl if compl != "" else place
			parts.adj = ("couleur" if compl == "" else adj_key)
		5:
			parts.adj = adj_key
			parts.compl = place
		_:
			# Nom en trois parties : « Corbeille grégaire à peau bleue des lagons ».
			parts.adj = adj_key
			parts.compl = ((compl + " ") if compl != "" else "") + place
	if String(parts.adj) == "" and String(parts.compl) == "":
		parts.compl = place
	# « Grand » / « Petit » devant la tête, pour les tailles marquées.
	if cat != "grand" and String(t.get("body_plan", "")) == "bilatéral" and g.randf() < 0.3 \
			and not ["géant", "colossal", "nain"].has(String(parts.adj)):
		if size > 0.6:
			parts.pre = "grand"
		elif size < 0.06:
			parts.pre = "petit"
	parts.t = t
	return parts


static func assemble(parts: Dictionary, plural := false) -> String:
	var t: Dictionary = parts.get("t", {})
	var fem := bool(parts.fem)
	var head := String(parts.head)
	# Seul le nom principal prend la marque du pluriel (« Fleurs d'eau ») ; les noms composés à
	# trait d'union (Pas-de-velours) sont invariables.
	if plural and not head.contains("-"):
		var words := head.split(" ")
		words[0] = plural_noun(words[0])
		head = " ".join(words)
	var s := head
	if String(parts.pre) != "":
		s = agree(ADJ[String(parts.pre)], fem, plural) + " " + head.substr(0, 1).to_lower() + head.substr(1)
	if String(parts.adj) != "":
		s += " " + _adj_text(String(parts.adj), t, fem, plural)
	if String(parts.compl) != "":
		s += " " + String(parts.compl)
	return _cap(s)


## Genre et nombre de la tête du nom vernaculaire : {head (minuscule), fem}.
static func head_noun(t: Dictionary) -> Dictionary:
	var parts := vernacular_parts(t)
	var h := String(parts.head)
	return {head = h.substr(0, 1).to_lower() + h.substr(1), fem = bool(parts.fem)}
