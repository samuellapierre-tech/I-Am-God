extends RefCounted
## Chronique de la parcelle : raconte, à la deuxième personne et en 1 ou 2 phrases, ce qui arrive au
## morceau de terrain que Dieu regarde (dinosaures qui chassent, premiers champs, la ville, les ruines…).
##
## Deux entrées, aucune dépendance à GameState (testable seul) :
## - on_event(event, snapshot) : un événement « parcel_* » de ParcelSim -> un « moment » (ou {} s'il est
##   redondant : espèce déjà annoncée, usage du sol déjà raconté…) ;
## - observe(snapshot) : compare l'état de la parcelle au précédent et produit les moments que la
##   simulation n'annonce pas d'elle-même (dérive de chaleur, changement d'usage non signalé).
## Puis narrate(moment, era, year) rend le texte procédural (déterministe à graine égale) ;
## describe_moment() / describe_snapshot() fournissent les faits au prompt LLM.
##
## Moment : {kind, type ("parcel_<kind>"), importance, snapshot, ...} avec selon le genre :
## land_use/from/first, species_id/species_name/role/returning, delta_c/temperature_c, summary.

const Procedural := preload("res://src/ai/procedural_narrator.gd")
const FactBase := preload("res://src/ai/facts/fact_base.gd")
const Epoch := preload("res://src/ai/epoch.gd")

## Genres de moments racontés.
const KINDS := ["land_use", "arrival", "departure", "extinction", "heat", "cold", "focus", "generic"]

## Usages du sol de ParcelSim.LAND_USES, du plus sauvage au plus artificiel (puis déclin).
const LAND_USES := [
	"ocean", "ice", "wild", "crater", "flooded",
	"camp", "pasture", "farmland", "village", "town", "city", "megacity", "arcology",
	"ruins", "rewild",
]
## Usages façonnés par une espèce intelligente, dans l'ordre de croissance.
const SETTLED_USES := ["camp", "pasture", "farmland", "village", "town", "city", "megacity", "arcology"]

## Libellés (avec article) pour les prompts et les reculs (« de une ville à un village »).
const LAND_USE_LABELS := {
	"ocean": "la mer", "ice": "la glace", "wild": "la nature sauvage", "crater": "un cratère",
	"flooded": "des terres noyées", "camp": "un campement", "pasture": "des pâturages",
	"farmland": "des terres agricoles", "village": "un village", "town": "une bourgade",
	"city": "une ville", "megacity": "une mégapole", "arcology": "une arcologie",
	"ruins": "des ruines", "rewild": "une friche reprise par la forêt",
}

## Importance (0..1) des moments d'usage du sol ; les clés dérivées (thaw, regrowth…) viennent de _land_use_key().
const LAND_USE_IMPORTANCE := {
	"crater": 0.95, "ruins": 0.9, "ice": 0.85, "ocean": 0.85, "arcology": 0.85, "flooded": 0.8,
	"megacity": 0.8, "city": 0.8, "village": 0.75, "farmland": 0.75, "camp": 0.75, "rewild": 0.7,
	"thaw": 0.7, "emerged": 0.7, "shrink": 0.7, "regrowth": 0.6, "town": 0.6, "pasture": 0.55, "wild": 0.5,
}
const ARRIVAL_IMPORTANCE := {"sapient": 0.75, "carnivore": 0.6, "herbivore": 0.5, "omnivore": 0.5}
const RETURN_IMPORTANCE := 0.3
const DEPARTURE_IMPORTANCE := 0.45
const EXTINCTION_IMPORTANCE := 0.8
const FOCUS_IMPORTANCE := 0.7
const GENERIC_IMPORTANCE := 0.4

## Dérive de température locale (°C) à partir de laquelle on la raconte.
const DEFAULT_HEAT_DRIFT_C := 4.0

## Le terrain, selon le biome : toujours un groupe nominal singulier (les gabarits n'accordent rien avec lui).
const BIOME_PHRASES := {
	"Abysses": "ce fond marin", "Océan": "ce bout de rivage", "Glace": "ce champ de glace",
	"Toundra": "ce lambeau de toundra", "Taïga": "cette lisière de taïga", "Steppe": "ce morceau de steppe",
	"Forêt tempérée": "ce coin de forêt", "Désert": "ce carré de désert", "Savane": "ce bout de savane",
	"Forêt tropicale": "ce pan de jungle", "Montagnes": "ce versant de montagne",
}

const OUVERTURES := ["Regarde,", "Sous tes yeux,", "Vois-tu,", "Tiens,", "", ""]

## Ce que Dieu voit en se penchant sur la parcelle (narration « focus »).
const LAND_USE_VIEWS := {
	"ocean": "l'eau y est profonde et calme", "ice": "la glace y règne sans partage",
	"wild": "la vie sauvage y foisonne", "crater": "la terre y fume encore",
	"flooded": "les eaux y stagnent", "camp": "un feu de camp y fume", "pasture": "des troupeaux y paissent",
	"farmland": "des champs y ondulent", "village": "un village y vit sa vie", "town": "une bourgade y bourdonne",
	"city": "une ville y gronde", "megacity": "une mégapole y scintille", "arcology": "une arcologie y respire",
	"ruins": "des ruines s'y effritent", "rewild": "la forêt y avale de vieilles pierres",
}

## Décor par ère. {bati} est toujours pluriel (« des huttes… ») ; {habitants} et les bêtes sont des
## groupes au pluriel qui servent quand la parcelle ne nomme pas l'espèce.
const LEXICON := {
	"Précambrien": {
		"ciel": ["sous un ciel orangé sans oxygène", "au bord d'un océan tiède", "dans la vapeur des sources chaudes"],
		"fin": ["La vie est minuscule, mais elle tient bon.", "Rien ne bouge à l'œil nu, et pourtant tout commence.", "Le monde n'est encore qu'une promesse."],
		"culture": ["des tapis de microbes"], "bati": ["des stromatolites"], "habitants": ["les premières cellules"],
		"herbivore": ["les tapis de microbes"], "carnivore": ["les microbes chasseurs"], "omnivore": ["les cellules vagabondes"],
	},
	"Cambrien": {
		"ciel": ["dans l'eau trouble des lagunes", "au-dessus des récifs", "sous la houle"],
		"fin": ["Chaque carapace est une invention.", "Les mers débordent de formes nouvelles.", "Personne n'a encore marché sur la terre ferme."],
		"culture": ["des algues"], "bati": ["des récifs"], "habitants": ["les premiers esprits"],
		"herbivore": ["les brouteurs des récifs"], "carnivore": ["les chasseurs des récifs"], "omnivore": ["les trilobites"],
	},
	"Paléozoïque": {
		"ciel": ["dans l'eau trouble des lagunes", "sous les fougères géantes", "au bord des marais chauds"],
		"fin": ["La vie apprend à marcher.", "Chaque carapace est une invention.", "Les mers débordent de formes nouvelles."],
		"culture": ["des fougères"], "bati": ["des récifs"], "habitants": ["les premiers esprits"],
		"herbivore": ["les brouteurs des récifs"], "carnivore": ["les scorpions de mer", "les poissons cuirassés"],
		"omnivore": ["les mille-pattes"],
	},
	"Mésozoïque": {
		"ciel": ["sous un ciel lourd et chaud", "dans l'odeur des fougères", "au bord des marais fumants"],
		"fin": ["La Terre est jeune, et elle a faim.", "Les écailles ne savent rien de toi.", "Le règne des géants continue, pour l'instant."],
		"culture": ["des fougères"], "bati": ["des nids de boue"], "habitants": ["les premiers esprits"],
		"herbivore": ["les troupeaux à cornes", "les grands sauropodes"], "carnivore": ["les prédateurs aux dents en lame"],
		"omnivore": ["les petits sauriens"],
	},
	"Cénozoïque": {
		"ciel": ["dans le vent des savanes nouvelles", "sous un soleil plus doux", "dans l'herbe haute"],
		"fin": ["Le sang chaud hérite du monde.", "Rien n'est écrit, sinon par toi.", "Les petits survivants deviennent les maîtres."],
		"culture": ["des graminées sauvages"], "bati": ["des terriers"], "habitants": ["les premiers esprits"],
		"herbivore": ["les troupeaux de brouteurs"], "carnivore": ["les meutes à fourrure"], "omnivore": ["les premiers primates"],
	},
	"Préhistoire": {
		"ciel": ["autour d'un feu qui fume", "dans le froid de l'aube", "sous un ciel immense"],
		"fin": ["Ils lèvent les yeux et te cherchent.", "Le feu garde la mémoire de ce jour.", "Leurs mythes naîtront ici."],
		"culture": ["des épis sauvages", "de l'orge sauvage"], "bati": ["des huttes de branchages", "des abris de peaux"],
		"habitants": ["les clans"], "herbivore": ["les mammouths", "les aurochs"], "carnivore": ["les loups", "les grands félins"],
		"omnivore": ["les ours"],
	},
	"Antiquité": {
		"ciel": ["sous le soleil des moissons", "dans la poussière des routes", "au chant des cigales"],
		"fin": ["Les scribes graveront ce jour dans l'argile.", "Les empires passent ; toi, tu demeures.", "Les oracles y verront ta main."],
		"culture": ["du blé et de l'orge", "des vignes et des oliviers"], "bati": ["des murs de pierre et un temple", "des maisons de brique crue"],
		"habitants": ["les paysans des deltas"], "herbivore": ["les chèvres", "les bœufs"], "carnivore": ["les loups"],
		"omnivore": ["les sangliers"],
	},
	"Moyen Âge": {
		"ciel": ["au son lointain des cloches", "sous un ciel de pluie fine", "dans la brume du matin"],
		"fin": ["Les cloches sonnent pour toi.", "La foi des humbles se fait plus ardente.", "Les moines y verront un signe du Ciel."],
		"culture": ["du seigle et de l'avoine", "du froment"], "bati": ["des remparts et un clocher", "des chaumières serrées"],
		"habitants": ["les paysans"], "herbivore": ["les moutons"], "carnivore": ["les loups"], "omnivore": ["les porcs"],
	},
	"Renaissance": {
		"ciel": ["dans la lumière dorée des ateliers", "sous un ciel que l'on mesure enfin", "au bruit des charrettes"],
		"fin": ["L'homme se croit le centre du monde ; tu souris.", "Les cartes se redessinent sous ton regard.", "La raison s'éveille, mais elle te doit tout."],
		"culture": ["du maïs venu d'outre-mer", "des vergers bien alignés"], "bati": ["des façades ornées et des places pavées", "des moulins et des ateliers"],
		"habitants": ["les bourgeois"], "herbivore": ["les chevaux"], "carnivore": ["les chiens de chasse"], "omnivore": ["les porcs"],
	},
	"Industriel": {
		"ciel": ["sous un ciel de suie", "dans le sifflement des locomotives", "à la lueur des forges"],
		"fin": ["Les cheminées crachent leur prière noire vers toi.", "Le progrès avance, aveugle et bruyant.", "Le monde tourne plus vite, mais toujours dans ta main."],
		"culture": ["des rangs de betteraves", "du blé moissonné à la machine"], "bati": ["des cheminées de brique", "des usines et des cités ouvrières"],
		"habitants": ["les ouvriers"], "herbivore": ["les chevaux de trait"], "carnivore": ["les chiens errants"], "omnivore": ["les rats"],
	},
	"Moderne": {
		"ciel": ["sous le bourdonnement des avions", "dans la lueur des lampadaires", "sous un ciel strié de câbles"],
		"fin": ["Le monde retient son souffle.", "Les écrans ne te voient pas, mais tu les vois.", "Tout va plus vite, sauf ton regard."],
		"culture": ["des monocultures à perte de vue", "des légumes sous serre"], "bati": ["des tours de verre et d'acier", "des immeubles et des échangeurs"],
		"habitants": ["les citadins"], "herbivore": ["les vaches"], "carnivore": ["les renards des villes"], "omnivore": ["les pigeons"],
	},
	"Cyberpunk": {
		"ciel": ["sous la pluie acide", "dans le grésillement des néons", "sous un ciel couleur d'écran mort"],
		"fin": ["Les néons clignotent, comme un signe.", "Les flux de données murmurent ton nom chiffré.", "Même les IA cherchent un sens à tout cela."],
		"culture": ["des algues en cuve", "des protéines de synthèse"], "bati": ["des tours de néon et des passerelles", "des blocs de béton tagués"],
		"habitants": ["les cyborgs"], "herbivore": ["les bêtes clonées"], "carnivore": ["les chiens de garde mécaniques"], "omnivore": ["les rats mutants"],
	},
	"Post-singularité": {
		"ciel": ["dans un silence parfait", "sous un ciel aux nuages programmés", "dans une lumière sans source"],
		"fin": ["Le cercle se referme.", "tes créatures créent à leur tour des mondes.", "Même le temps semble y hésiter."],
		"culture": ["des jardins recomposés atome par atome"], "bati": ["des structures sans fenêtres", "des flèches de matière programmable"],
		"habitants": ["les esprits fusionnés"], "herbivore": ["les bêtes ressuscitées"], "carnivore": ["les prédateurs recréés"], "omnivore": ["les essaims"],
	},
	"generic": {
		"ciel": ["sous ton regard", "dans la lumière du jour", "au fil des saisons"],
		"fin": ["Le monde se souviendra.", "Ce bout de terre garde la mémoire de tout."],
		"culture": ["des graines"], "bati": ["des abris"], "habitants": ["les vivants"],
		"herbivore": ["les brouteurs"], "carnivore": ["les prédateurs"], "omnivore": ["les bêtes"],
	},
}

## Gabarits d'usage du sol. Clés : un usage de LAND_USES ou une clé dérivée (thaw, regrowth, emerged, shrink).
## Emplacements : {ouverture} {date} {terre} {ciel} {fin} {habitants} {culture} {bati} {usage} {ancien}.
## Accord : [hab:singulier|pluriel] suit {habitants}. Une phrase, plus éventuellement {fin}.
const LAND_USE_TEMPLATES := {
	"ocean": [
		"{ouverture} la mer a recouvert {terre} ; les vagues roulent là où l'on marchait. {fin}",
		"{date}, {terre} sombre sous les flots, et il n'en reste qu'un reflet.",
		"Les eaux ont pris {terre} : tu ne vois plus que l'écume. {fin}",
	],
	"ice": [
		"{ouverture} la glace a figé {terre} ; plus rien ne bouge sous le blanc. {fin}",
		"{date}, le froid scelle {terre} sous une banquise sans bruit.",
		"Le givre a tout pris : {terre} n'est plus qu'un désert blanc. {fin}",
	],
	"crater": [
		"{ouverture} le feu du ciel a frappé ici : {terre} n'est plus qu'un cratère fumant. {fin}",
		"{date}, une pierre tombée des étoiles creuse {terre} jusqu'au roc.",
		"Il ne reste de {terre} qu'une plaie de cendres et de verre. {fin}",
	],
	"flooded": [
		"{ouverture} les eaux ont noyé {terre} ; seuls les plus hauts arbres émergent encore.",
		"{date}, le déluge recouvre {terre}, et tout ce qui marchait doit nager ou périr. {fin}",
		"Une mer de boue s'étend sur {terre}, comme tu l'as permis.",
	],
	"wild": [
		"{ouverture} {terre} redevient sauvage {ciel}. {fin}",
		"{date}, plus aucune main ne façonne {terre} : la vie y suit son propre cours.",
		"Les plantes et les bêtes reprennent {terre}, sous ton regard tranquille. {fin}",
	],
	"thaw": [
		"{ouverture} la glace se retire de {terre}, et la terre nue respire à nouveau. {fin}",
		"{date}, le dégel libère {terre} ; les premières pousses percent la boue.",
		"L'eau de fonte ruisselle sur {terre} : sous le blanc, la vie attendait. {fin}",
	],
	"regrowth": [
		"{ouverture} le temps panse la blessure : sur {terre}, la vie revient au bord du cratère. {fin}",
		"Les cendres refroidissent, et {terre} reverdit, lentement.",
	],
	"emerged": [
		"{ouverture} les eaux se retirent et {terre} émerge, luisante de limon. {fin}",
		"{date}, {terre} sort des flots ; la vie n'attend pas pour la reconquérir.",
	],
	"camp": [
		"{ouverture} un feu brûle sur {terre} : {habitants} y [hab:a|ont] dressé un campement. {fin}",
		"{date}, {habitants} [hab:pose|posent] [hab:ses|leurs] abris sur {terre} {ciel}.",
		"Des traces de pas, des cendres, des os rongés : {habitants} [hab:campe|campent] désormais sur {terre}. {fin}",
	],
	"pasture": [
		"{ouverture} {habitants} [hab:mène|mènent] [hab:ses|leurs] bêtes paître sur {terre}. {fin}",
		"{date}, les premiers enclos découpent {terre} ; on y garde des troupeaux.",
		"Sur {terre}, les bergers ont remplacé les chasseurs {ciel}. {fin}",
	],
	"farmland": [
		"{ouverture} des champs couvrent de nouveau {terre}, et l'on y sème {culture}.",
		"{date}, {terre} redevient terre de labour, sous ton regard. {fin}",
		"Les sillons reviennent rayer {terre} {ciel}. {fin}",
	],
	"village": [
		"{ouverture} un village renaît sur {terre} ; {bati} s'y élèvent à nouveau. {fin}",
		"{date}, des familles reviennent habiter {terre}.",
	],
	"town": [
		"{ouverture} le village a grandi : {terre} accueille désormais une bourgade, avec son marché et ses querelles. {fin}",
		"{date}, des routes convergent vers {terre}, où une bourgade prospère.",
		"Sur {terre}, {bati} se serrent autour d'une place de marché. {fin}",
	],
	"city": [
		"{ouverture} la ville reprend {terre}, et {bati} s'y dressent de nouveau. {fin}",
		"{date}, {terre} redevient une ville ; les rues s'emplissent à nouveau.",
	],
	"megacity": [
		"{ouverture} la ville déborde : {terre} n'est plus qu'un fragment de mégapole {ciel}. {fin}",
		"{date}, {bati} engloutissent {terre} ; on n'y voit plus le sol.",
		"La nuit n'existe plus sur {terre} : la mégapole ne dort jamais. {fin}",
	],
	"arcology": [
		"{ouverture} une arcologie couvre {terre}, une seule structure qui respire pour des millions. {fin}",
		"{date}, {terre} disparaît sous une arcologie : la ville est devenue un organisme.",
	],
	"ruins": [
		"{ouverture} de nouvelles ruines s'ajoutent aux anciennes sur {terre}. {fin}",
		"{date}, {terre} se vide une fois encore ; les murs retournent à la poussière.",
	],
	"rewild": [
		"{ouverture} la forêt dévore les ruines de {terre} ; les racines fendent les dernières pierres. {fin}",
		"{date}, les bêtes sauvages reviennent sur {terre}, parmi les vestiges d'un peuple oublié.",
		"La nature reprend {terre}, patiemment, comme si personne n'y avait jamais vécu. {fin}",
	],
	"shrink": [
		"{ouverture} {terre} se dépeuple : là où s'élevait {ancien}, il ne reste que {usage}. {fin}",
		"{date}, {terre} recule d'un âge, de {ancien} à {usage}.",
	],
}

## Première fois sur cette parcelle : les grands seuils (premiers champs, premier village, la ville, les ruines).
const LAND_USE_FIRST_TEMPLATES := {
	"camp": [
		"{ouverture} pour la première fois, un feu brûle sur {terre} : {habitants} y [hab:a|ont] dressé un campement. {fin}",
		"{date}, des êtres qui pensent foulent {terre} pour la première fois : {habitants} y [hab:campe|campent] {ciel}.",
	],
	"pasture": [
		"{ouverture} pour la première fois, {habitants} [hab:mène|mènent] des troupeaux paître sur {terre}. {fin}",
		"{date}, les premiers enclos découpent {terre} : la chasse cède la place à l'élevage.",
	],
	"farmland": [
		"{ouverture} les premiers champs apparaissent sur {terre} : on y sème {culture}. {fin}",
		"{date}, {habitants} [hab:ouvre|ouvrent] le sol de {terre} et y [hab:sème|sèment] {culture}.",
		"Pour la première fois, des sillons rayent {terre} ; la faim recule d'un pas. {fin}",
	],
	"village": [
		"{ouverture} un premier village se dresse sur {terre} : {bati}, des fumées, des enfants. {fin}",
		"{date}, {habitants} [hab:s'installe|s'installent] pour de bon : {terre} porte son premier village.",
		"Les champs ont appelé les maisons : un village est né sur {terre} {ciel}. {fin}",
	],
	"town": [
		"{ouverture} le premier marché s'ouvre sur {terre} : le village est devenu une bourgade. {fin}",
	],
	"city": [
		"{ouverture} la ville est là : {bati} couvrent {terre}, et les champs reculent. {fin}",
		"{date}, {terre} devient une ville ; des milliers de vies s'y croisent sans te voir.",
		"Là où paissaient des troupeaux, {bati} montent vers le ciel : {terre} est une ville. {fin}",
	],
	"megacity": [
		"{ouverture} pour la première fois, la ville ne s'arrête plus : {terre} appartient à une mégapole. {fin}",
	],
	"ruins": [
		"{ouverture} la ville est morte : sur {terre}, il ne reste que des ruines {ciel}. {fin}",
		"{date}, plus personne n'habite {terre} ; les murs s'effondrent un à un.",
		"Le silence a remplacé les voix : {terre} n'est plus qu'un champ de ruines. {fin}",
	],
}

## Arrivées par rôle (ParcelSim.fauna[].role). Accord : [espece:singulier|pluriel].
const ARRIVAL_TEMPLATES := {
	"herbivore": [
		"{ouverture} {espece} [espece:vient|viennent] brouter sur {terre} {ciel}. {fin}",
		"{date}, {espece} [espece:arrive|arrivent] sur {terre} et [espece:tond|tondent] la végétation à ras.",
		"De nouveaux brouteurs foulent {terre} : {espece}. {fin}",
	],
	"carnivore": [
		"{ouverture} {espece} [espece:chasse|chassent] désormais sur {terre} ; les autres bêtes se font discrètes. {fin}",
		"{date}, un prédateur s'installe sur {terre} : {espece}.",
		"Des traces de griffes, du sang sur l'herbe : {espece} [espece:a|ont] fait de {terre} [espece:son|leur] territoire de chasse. {fin}",
	],
	"omnivore": [
		"{ouverture} {espece} [espece:vient|viennent] fouiller {terre} en quête de tout ce qui se mange. {fin}",
		"{date}, {espece} [espece:fait|font] [espece:son|leur] apparition sur {terre}.",
		"Sur {terre}, {espece} [espece:prend|prennent] [espece:ses|leurs] quartiers {ciel}. {fin}",
	],
	"sapient": [
		"{ouverture} {espece} [espece:pose|posent] le pied sur {terre} et [espece:lève|lèvent] les yeux, [espece:comme si elle te cherchait|comme s'ils te cherchaient].",
		"{date}, {espece} [espece:arrive|arrivent] sur {terre} ; rien n'y sera plus comme avant. {fin}",
	],
}
const RETURN_TEMPLATES := [
	"{ouverture} {espece} [espece:revient|reviennent] sur {terre}. {fin}",
	"{date}, {espece} [espece:est de retour|sont de retour] sur {terre} {ciel}.",
]
const DEPARTURE_TEMPLATES := [
	"{ouverture} {espece} [espece:a quitté|ont quitté] {terre} ; [espece:ses|leurs] traces s'effacent déjà. {fin}",
	"{date}, plus aucun représentant de {espece} ne foule {terre}.",
	"{espece} [espece:s'en est allée|s'en sont allés] de {terre}, vers d'autres terres ou vers l'oubli. {fin}",
]
const EXTINCTION_TEMPLATES := [
	"{ouverture} {espece} [espece:a disparu|ont disparu] de {terre}, et du monde avec [espece:elle|eux]. {fin}",
	"{date}, le dernier représentant de {espece} meurt sur {terre} ; il n'y en aura plus jamais.",
	"Il ne reste de {espece} que des os dans le sol de {terre}. {fin}",
]
const HEAT_TEMPLATES := [
	"{ouverture} la chaleur monte sur {terre} : {temp}, {delta} de plus qu'avant. {fin}",
	"{date}, l'air de {terre} se réchauffe de {delta} ; la vie doit suivre ou fuir.",
	"Le sol de {terre} brûle un peu plus chaque saison : déjà {temp}. {fin}",
]
const COLD_TEMPLATES := [
	"{ouverture} le froid gagne {terre} : {temp}, {delta} de moins qu'avant. {fin}",
	"{date}, l'air de {terre} se refroidit de {delta} ; les bêtes cherchent un abri.",
	"Le givre mord chaque matin un peu plus {terre} : plus que {temp}. {fin}",
]
const FOCUS_TEMPLATES := [
	"ton regard se pose sur {terre} : {vue}. {fin}",
	"{date}, tu choisis de veiller sur {terre} ; {vue}.",
	"tu te penches sur {terre} {ciel} : {vue}. {fin}",
]
## Phrase neutre, valable à toute époque, si aucun gabarit ne l'est.
const SAFE_TEMPLATE := "{date}, le temps passe sur ta parcelle."
const GENERIC_TEMPLATES := [
	"{date}, sur {terre} : {resume}.",
	"{ouverture} sur {terre}, {resume}. {fin}",
]

var rng := RandomNumberGenerator.new()
var heat_drift_c := DEFAULT_HEAT_DRIFT_C

var _seed := 0
var _count := 0
var _last_template := ""
var _initialized := false
var _land_use := ""
var _seen_uses := {}
var _heat_ref := 0.0
## species_id -> {present: bool, name, role}
var _species := {}


func _init(p_seed: int = -1) -> void:
	if p_seed >= 0:
		_seed = p_seed
	else:
		rng.randomize()
		_seed = rng.randi()
	# slots_for() tire avec ce générateur sans le réensemencer : il doit partir de la graine.
	rng.seed = _seed


# ---------------------------------------------------------------------------
# Suivi de l'état de la parcelle
# ---------------------------------------------------------------------------

## Instantané sérialisable de GameState.parcel (ParcelSim) ; {} si absent. Tolère les champs manquants.
static func snapshot(parcel: Object) -> Dictionary:
	if parcel == null:
		return {}
	var snap := {}
	for key in ["cell", "year", "biome", "land_use", "temperature_c", "global_temperature_c", "vegetation", "water", "tech"]:
		if key in parcel:
			snap[key] = parcel.get(key)
	var fauna: Array = []
	if "fauna" in parcel and parcel.get("fauna") is Array:
		for f in parcel.get("fauna"):
			if f is Dictionary:
				fauna.append({
					"species_id": int(f.get("species_id", -1)), "name": str(f.get("name", "")),
					"role": str(f.get("role", "")), "count": int(f.get("count", 0)), "trend": int(f.get("trend", 0)),
					"clade": str(f.get("clade", "")),
				})
	snap["fauna"] = fauna
	var kinds := {}
	if "structures" in parcel and parcel.get("structures") is Array:
		for s in parcel.get("structures"):
			if s is Dictionary:
				var k := str(s.get("kind", "?"))
				kinds[k] = int(kinds.get(k, 0)) + 1
	snap["structures"] = kinds
	return snap


## Prend l'état courant comme référence, sans rien raconter (début de partie, nouvelle parcelle).
func reset(snap: Dictionary) -> void:
	_initialized = not snap.is_empty()
	_land_use = str(snap.get("land_use", ""))
	_seen_uses = {}
	if _land_use != "":
		_seen_uses[_land_use] = true
	_heat_ref = float(snap.get("temperature_c", 0.0))
	_species = {}
	for f in snap.get("fauna", []):
		_species[int(f["species_id"])] = {"present": true, "name": str(f["name"]), "role": str(f["role"])}


func is_ready() -> bool:
	return _initialized


## Le joueur suit une nouvelle parcelle : moment « focus », puis l'état devient la référence.
func focus(snap: Dictionary) -> Dictionary:
	reset(snap)
	return _moment("focus", snap, {"land_use": str(snap.get("land_use", ""))})


## Changements marquants que la simulation n'annonce pas forcément : usage du sol, dérive de chaleur.
## Appelé à chaque parcel_updated ; renvoie une liste de moments (souvent vide).
func observe(snap: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if snap.is_empty():
		return out
	if not _initialized:
		reset(snap)
		return out
	var lu := str(snap.get("land_use", ""))
	if lu != "" and lu != _land_use:
		var m := _land_use_moment(lu, snap)
		if not m.is_empty():
			out.append(m)
	if snap.has("temperature_c"):
		var t := float(snap["temperature_c"])
		var delta := t - _heat_ref
		if absf(delta) >= heat_drift_c:
			_heat_ref = t
			out.append(_moment("heat" if delta > 0.0 else "cold", snap, {"delta_c": delta, "temperature_c": t}))
	for f in snap.get("fauna", []):
		var id := int(f["species_id"])
		if _species.has(id):
			_species[id]["name"] = str(f["name"])
			_species[id]["role"] = str(f["role"])
	return out


## Événement « parcel_* » de ParcelSim -> moment, ou {} s'il n'apporte rien de neuf.
## event peut porter species_name (joint par le Narrator), extinct: true ou species_alive: false.
func on_event(event: Dictionary, snap: Dictionary) -> Dictionary:
	if not _initialized:
		reset(snap)
	var kind := str(event.get("type", "")).trim_prefix("parcel_")
	match kind:
		"land_use":
			var lu := str(event.get("land_use", event.get("to", "")))
			if not lu in LAND_USES:
				lu = _land_use_from_summary(str(event.get("summary", "")))
			if not lu in LAND_USES:
				lu = str(snap.get("land_use", ""))
			if lu == "" or lu == _land_use:
				return {}
			return _land_use_moment(lu, snap)
		"arrival":
			return _species_moment(event, snap, true)
		"departure":
			return _species_moment(event, snap, false)
	var extra := {"summary": str(event.get("summary", ""))}
	var mapped := kind if kind in ["heat", "cold", "extinction"] else "generic"
	if mapped == "extinction":
		return _species_moment(event, snap, false)
	if mapped in ["heat", "cold"]:
		extra["temperature_c"] = float(snap.get("temperature_c", event.get("temperature_c", 0.0)))
		extra["delta_c"] = float(event.get("delta_c", 0.0))
		_heat_ref = float(extra["temperature_c"])
	var m := _moment(mapped, snap, extra)
	m["type"] = str(event.get("type", "parcel_generic"))
	return m


func _land_use_moment(lu: String, snap: Dictionary) -> Dictionary:
	var prev_use := _land_use
	var first := not _seen_uses.has(lu)
	_land_use = lu
	_seen_uses[lu] = true
	return _moment("land_use", snap, {"land_use": lu, "from": prev_use, "first": first})


func _species_moment(event: Dictionary, snap: Dictionary, arrival: bool) -> Dictionary:
	var id := int(event.get("species_id", -1))
	var state: Dictionary = _species.get(id, {})
	var known := not state.is_empty()
	var present := bool(state.get("present", false))
	# Anti-scintillement : une espèce déjà annoncée présente (ou partie) ne l'est pas deux fois.
	if id >= 0 and arrival and present:
		return {}
	if id >= 0 and not arrival and known and not present and not _is_extinct(event):
		return {}
	var name := str(event.get("species_name", ""))
	var role := str(state.get("role", ""))
	for f in snap.get("fauna", []):
		if int(f["species_id"]) == id:
			if name == "":
				name = str(f["name"])
			role = str(f["role"])
	if name == "":
		name = str(state.get("name", ""))
	if name == "":
		name = _species_from_summary(str(event.get("summary", "")))
	if id >= 0:
		_species[id] = {"present": arrival, "name": name, "role": role}
	var extra := {"species_id": id, "species_name": name, "role": role}
	if arrival:
		extra["returning"] = known
		return _moment("arrival", snap, extra)
	return _moment("extinction" if _is_extinct(event) else "departure", snap, extra)


static func _is_extinct(event: Dictionary) -> bool:
	return bool(event.get("extinct", false)) or (event.has("species_alive") and not bool(event["species_alive"])) \
		or str(event.get("type", "")) == "parcel_extinction"


## ParcelSim : « La parcelle devient : farmland. »
static func _land_use_from_summary(summary: String) -> String:
	var t := summary.strip_edges().trim_suffix(".")
	var colon := t.rfind(":")
	return t.substr(colon + 1).strip_edges() if colon >= 0 else ""


## ParcelSim : « Humains arrivent sur la parcelle. » / « Humains ont disparu de la parcelle. »
static func _species_from_summary(summary: String) -> String:
	for marker in [" arrivent", " arrive", " ont disparu", " a disparu"]:
		var i := summary.find(marker)
		if i > 0:
			return summary.substr(0, i).strip_edges()
	return ""


func _moment(kind: String, snap: Dictionary, extra: Dictionary) -> Dictionary:
	var m := {"kind": kind, "type": "parcel_" + kind, "snapshot": snap}
	m.merge(extra, true)
	m["importance"] = importance(m)
	return m


# ---------------------------------------------------------------------------
# Importance (rareté) : décide ce qui est raconté quand plusieurs choses arrivent ensemble
# ---------------------------------------------------------------------------

static func importance(m: Dictionary) -> float:
	match str(m.get("kind", "")):
		"land_use":
			var key := _land_use_key(str(m.get("land_use", "")), str(m.get("from", "")))
			var v: float = LAND_USE_IMPORTANCE.get(key, 0.5)
			if key in SETTLED_USES or key == "ruins":
				v += 0.08 if bool(m.get("first", false)) else -0.15
			return clampf(v, 0.0, 0.98)
		"arrival":
			if bool(m.get("returning", false)):
				return RETURN_IMPORTANCE
			return ARRIVAL_IMPORTANCE.get(str(m.get("role", "")), 0.5)
		"departure":
			return DEPARTURE_IMPORTANCE
		"extinction":
			return EXTINCTION_IMPORTANCE
		"heat", "cold":
			return clampf(0.55 + 0.03 * (absf(float(m.get("delta_c", 0.0))) - DEFAULT_HEAT_DRIFT_C), 0.5, 0.8)
		"focus":
			return FOCUS_IMPORTANCE
	return GENERIC_IMPORTANCE


## Clé de gabarit pour un passage d'usage : dégel, repousse, émersion, recul d'une ville…
static func _land_use_key(to: String, prev_use: String) -> String:
	if to == "wild":
		match prev_use:
			"ice": return "thaw"
			"crater": return "regrowth"
			"ocean", "flooded": return "emerged"
	if to in SETTLED_USES and prev_use in SETTLED_USES and SETTLED_USES.find(to) < SETTLED_USES.find(prev_use):
		return "shrink"
	return to


# ---------------------------------------------------------------------------
# Rendu procédural
# ---------------------------------------------------------------------------

## Texte (1 ou 2 phrases, deuxième personne) pour un moment. Déterministe : même graine, même suite
## d'appels -> mêmes textes.
## epoch : époque effective (epoch.gd) ; -1 = déduite de l'ère et de la date. Aucun mot anachronique :
## on essaie les gabarits (et leurs emplacements) jusqu'à un texte propre, sinon une phrase neutre.
func narrate(m: Dictionary, era: Variant = "", year: Variant = null, epoch := -1) -> String:
	_count += 1
	var kind := str(m.get("kind", "generic"))
	var snap: Dictionary = m.get("snapshot", {})
	if year == null:
		year = snap.get("year", null)
	if epoch < 0:
		epoch = Epoch.from_era_year(era, year)
	rng.seed = hash([_seed, _count, kind, str(m.get("land_use", "")), int(m.get("species_id", -1))])
	var e := lexicon_key(era, year)
	var templates := templates_for(m)
	var idx := rng.randi() % templates.size()
	if templates[idx] == _last_template and templates.size() > 1:
		idx = (idx + 1) % templates.size()
	for attempt in templates.size() * 3:
		var tpl: String = templates[(idx + attempt) % templates.size()]
		var text := render(tpl, _slots(e, m, snap, year))
		if Epoch.is_clean(text, epoch):
			_last_template = tpl
			return text
	return render(SAFE_TEMPLATE, _slots(e, m, snap, year)).replace("ce coin de forêt", "ta parcelle")


## Gabarits candidats pour un moment (exposé pour les tests).
static func templates_for(m: Dictionary) -> Array:
	match str(m.get("kind", "")):
		"land_use":
			var lu := str(m.get("land_use", ""))
			var key := _land_use_key(lu, str(m.get("from", "")))
			if key == lu and bool(m.get("first", false)) and LAND_USE_FIRST_TEMPLATES.has(lu):
				return LAND_USE_FIRST_TEMPLATES[lu]
			return LAND_USE_TEMPLATES.get(key, LAND_USE_TEMPLATES["wild"])
		"arrival":
			if bool(m.get("returning", false)):
				return RETURN_TEMPLATES
			return ARRIVAL_TEMPLATES.get(str(m.get("role", "")), ARRIVAL_TEMPLATES["omnivore"])
		"departure":
			return DEPARTURE_TEMPLATES
		"extinction":
			return EXTINCTION_TEMPLATES
		"heat":
			return HEAT_TEMPLATES
		"cold":
			# Le givre n'a de sens que s'il fait vraiment froid.
			var temp := float(m.get("temperature_c", m.get("snapshot", {}).get("temperature_c", 0.0)))
			return COLD_TEMPLATES if temp <= 8.0 else COLD_TEMPLATES.filter(func(t: String) -> bool: return not t.contains("givre"))
		"focus":
			return FOCUS_TEMPLATES
	return GENERIC_TEMPLATES


## Tous les gabarits (pour les tests).
static func all_templates() -> Array:
	var out: Array = []
	for d in [LAND_USE_TEMPLATES, LAND_USE_FIRST_TEMPLATES, ARRIVAL_TEMPLATES]:
		for k in d:
			out.append_array(d[k])
	for arr in [RETURN_TEMPLATES, DEPARTURE_TEMPLATES, EXTINCTION_TEMPLATES, HEAT_TEMPLATES, COLD_TEMPLATES,
			FOCUS_TEMPLATES, GENERIC_TEMPLATES]:
		out.append_array(arr)
	return out


## Emplacements de gabarit pour un moment (partagés avec le fil continu, chronicle.gd).
func slots_for(era: Variant, m: Dictionary, snap: Dictionary, year: Variant) -> Dictionary:
	return _slots(lexicon_key(era, year), m, snap, year)


## Rend un gabarit précis pour un moment (utilisé par les tests pour couvrir chaque gabarit).
func render_template(tpl: String, m: Dictionary, era: Variant = "", year: Variant = null) -> String:
	return render(tpl, _slots(lexicon_key(era, year), m, m.get("snapshot", {}), year))


## Décor à utiliser : avant -66 Ma, l'étape datée (prologue, Trias, Jurassique) ; ensuite, l'ère.
static func lexicon_key(era: Variant, year: Variant) -> String:
	var stage := FactBase.stage_for(era, year)
	if stage in ["Archéen", "Grande Oxydation", "Terre boule de neige"]:
		return "Précambrien"
	if stage == "Explosion cambrienne":
		return "Cambrien"
	if stage in ["Sortie des eaux", "Carbonifère", "Grande Mourance"]:
		return "Paléozoïque"
	if stage in ["Trias", "Jurassique"]:
		return "Mésozoïque"
	return Procedural.era_key(era) if LEXICON.has(Procedural.era_key(era)) else "generic"


## Rend un gabarit avec des emplacements déjà choisis (accords, contractions, majuscules).
static func render(tpl: String, slots: Dictionary) -> String:
	var t := Procedural.apply_agreement(tpl, {
		"espece": bool(slots.get("_espece_pl", true)), "hab": bool(slots.get("_hab_pl", true)),
	})
	t = t.format(slots)
	for pair in [[" que un ", " qu'un "], [" que une ", " qu'une "], [" de un ", " d'un "], [" de une ", " d'une "],
			[" de des ", " de "], [" lorsque il", " lorsqu'il"]]:
		t = t.replace(pair[0], pair[1])
	return Procedural.polish(t)


func _slots(era: String, m: Dictionary, snap: Dictionary, year: Variant) -> Dictionary:
	var lex: Dictionary = LEXICON.get(era, LEXICON["generic"])
	var gen: Dictionary = LEXICON["generic"]
	var pick := func(key: String) -> String:
		var arr: Array = lex.get(key, gen[key])
		return str(arr[rng.randi() % arr.size()])
	var role := str(m.get("role", ""))
	var default_beasts: String = pick.call(role if role in ["herbivore", "carnivore", "omnivore"] else "omnivore")
	if role == "sapient":
		default_beasts = pick.call("habitants")
	var esp := Procedural.species_phrase(str(m.get("species_name", "")) if str(m.get("species_name", "")) != "" else default_beasts)
	var hab := Procedural.species_phrase(_sapient_name(snap) if _sapient_name(snap) != "" else pick.call("habitants"))
	var terre := "ta parcelle"
	var biome := str(snap.get("biome", ""))
	if BIOME_PHRASES.has(biome) and rng.randf() < 0.6:
		terre = BIOME_PHRASES[biome]
	var temp := float(m.get("temperature_c", snap.get("temperature_c", 0.0)))
	var delta := absi(int(round(float(m.get("delta_c", 0.0)))))
	var resume := Procedural.clean_summary(str(m.get("summary", "")))
	var lu := str(m.get("land_use", snap.get("land_use", "")))
	return {
		"ouverture": OUVERTURES[rng.randi() % OUVERTURES.size()],
		"date": Procedural.format_year(float(year)) if typeof(year) in [TYPE_INT, TYPE_FLOAT] else "En ce jour",
		"terre": terre,
		"ciel": pick.call("ciel"),
		"fin": pick.call("fin"),
		"culture": pick.call("culture"),
		"bati": pick.call("bati"),
		"espece": esp["text"], "_espece_pl": esp["plural"],
		"habitants": hab["text"], "_hab_pl": hab["plural"],
		"usage": LAND_USE_LABELS.get(lu, "la nature"),
		"ancien": LAND_USE_LABELS.get(str(m.get("from", "")), "autre chose"),
		"temp": "%d °C" % int(round(temp)),
		"delta": "%d degré%s" % [delta, "s" if delta > 1 else ""],
		"vue": LAND_USE_VIEWS.get(lu, "la vie y suit son cours"),
		"resume": resume if resume != "" else "quelque chose change sous tes yeux",
	}


## Nom de l'espèce intelligente la plus visible sur la parcelle ("" s'il n'y en a pas).
static func _sapient_name(snap: Dictionary) -> String:
	for f in snap.get("fauna", []):
		if str(f.get("role", "")) == "sapient" and str(f.get("name", "")) != "":
			return str(f["name"])
	return ""


# ---------------------------------------------------------------------------
# Faits pour le prompt LLM
# ---------------------------------------------------------------------------

## Le moment en une phrase factuelle (aucune invention).
static func describe_moment(m: Dictionary) -> String:
	var name := str(m.get("species_name", ""))
	var phrase := Procedural.species_phrase(name) if name != "" else {"text": "une espèce", "plural": false}
	var who: String = phrase["text"]
	var agree := func(tpl: String) -> String: return Procedural.contract(Procedural.apply_agreement(tpl, {"espece": phrase["plural"]}))
	match str(m.get("kind", "")):
		"land_use":
			var to: String = LAND_USE_LABELS.get(str(m.get("land_use", "")), str(m.get("land_use", "")))
			var prev_label: String = LAND_USE_LABELS.get(str(m.get("from", "")), "")
			var s: String = ("Usage du sol : %s." % to) if prev_label == "" else ("Usage du sol : avant, %s ; maintenant, %s." % [prev_label, to])
			if bool(m.get("first", false)) and str(m.get("land_use", "")) in SETTLED_USES + ["ruins"]:
				s += " C'est la première fois sur cette parcelle."
			return s
		"arrival":
			var role := str(m.get("role", ""))
			var roles := {"herbivore": "herbivore", "carnivore": "prédateur", "omnivore": "omnivore", "sapient": "espèce intelligente"}
			var r := " (%s)" % roles[role] if roles.has(role) else ""
			return agree.call(("Retour de %s%s sur la parcelle." if bool(m.get("returning", false)) else "Arrivée de %s%s sur la parcelle.") % [who, r])
		"departure":
			return agree.call("Départ : %s [espece:ne vit|ne vivent] plus sur la parcelle." % who)
		"extinction":
			return agree.call("Extinction : %s [espece:a disparu|ont disparu] de la parcelle et du monde." % who)
		"heat", "cold":
			return "La température locale %s de %d °C et atteint %d °C." % [
				"monte" if str(m["kind"]) == "heat" else "baisse",
				absi(int(round(float(m.get("delta_c", 0.0))))), int(round(float(m.get("temperature_c", 0.0))))]
		"focus":
			return "Dieu choisit de suivre cette parcelle."
	var s2 := str(m.get("summary", "")).strip_edges()
	return s2 if s2 != "" else "Quelque chose change sur la parcelle."


## L'état de la parcelle en quelques lignes (biome, usage, chaleur, faune, constructions).
static func describe_snapshot(snap: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	if snap.is_empty():
		return lines
	var lu := str(snap.get("land_use", ""))
	var place := "Biome : %s ; usage du sol : %s." % [str(snap.get("biome", "inconnu")), LAND_USE_LABELS.get(lu, lu)]
	lines.append(place)
	if snap.has("temperature_c"):
		var t := "Température locale : %d °C" % int(round(float(snap["temperature_c"])))
		if snap.has("global_temperature_c"):
			t += " (moyenne mondiale %d °C)" % int(round(float(snap["global_temperature_c"])))
		lines.append(t + ".")
	var fauna: Array = snap.get("fauna", [])
	if not fauna.is_empty():
		var roles := {"herbivore": "herbivore", "carnivore": "prédateur", "omnivore": "omnivore", "sapient": "intelligente"}
		var trends := {-1: "en baisse", 0: "stable", 1: "en hausse"}
		var parts := PackedStringArray()
		for f in fauna:
			parts.append("%s (%s, %d visibles, %s)" % [
				str(f.get("name", "?")), roles.get(str(f.get("role", "")), "?"), int(f.get("count", 0)),
				trends.get(int(f.get("trend", 0)), "stable")])
		lines.append("Espèces présentes : %s." % ", ".join(parts))
	else:
		lines.append("Aucune espèce visible.")
	var st: Dictionary = snap.get("structures", {})
	if not st.is_empty():
		var names := {"field": "champs", "hut": "huttes", "road": "routes", "building": "bâtiments", "tower": "tours", "ruin": "ruines"}
		var parts2 := PackedStringArray()
		for k in st:
			parts2.append("%d %s" % [int(st[k]), names.get(k, str(k))])
		lines.append("Constructions : %s." % ", ".join(parts2))
	return lines
