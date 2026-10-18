extends RefCounted
## Narrateur procédural hors-ligne : grammaire à gabarits, variée par ère et par type d'événement.
## Garantit que le jeu reste entièrement jouable sans aucune IA installée.
## Les gabarits utilisent des emplacements {nom} remplis à partir du contexte et des lexiques d'ère.

const ERAS := [
	"Mésozoïque", "Cénozoïque", "Préhistoire", "Antiquité",
	"Moyen Âge", "Renaissance", "Industriel", "Moderne", "Cyberpunk", "Post-singularité",
]

## Nom de chaque ère précédé de son article, pour des phrases correctes.
const ERA_ARTICLES := {
	"Mésozoïque": "le Mésozoïque", "Cénozoïque": "le Cénozoïque", "Préhistoire": "la Préhistoire",
	"Antiquité": "l'Antiquité", "Moyen Âge": "le Moyen Âge", "Renaissance": "la Renaissance",
	"Industriel": "l'ère industrielle", "Moderne": "l'ère moderne", "Cyberpunk": "l'ère cyberpunk",
	"Post-singularité": "la post-singularité", "generic": "un nouvel âge",
}

## Types d'événements reconnus (actions divines du contrat + événements de la simulation).
const EVENT_TYPES := [
	"meteor", "extinct", "save", "bless", "plague", "uplift", "flood", "ice_age", "spawn_species",
	"extinction", "speciation", "migration", "war", "discovery", "civilization", "disaster",
	"climate", "era_change", "sapience", "golden_age", "decline", "lazarus", "generic",
]

## Types produits par la simulation (src/sim/world_sim.gd) ou synonymes -> type canonique.
## Les événements racines d'action divine sont préfixés « divine_ » (préfixe retiré avant la recherche).
const EVENT_ALIASES := {
	"impact": "meteor", "asteroid": "meteor", "deluge": "flood", "blessing": "bless", "spawn": "spawn_species",
	"protection": "save", "collapse": "disaster", "volcanism": "disaster", "ice_age_end": "climate",
	"land_bridge": "migration", "invasion": "migration", "radiation": "speciation",
	"new_species": "speciation", "evolution": "speciation", "mutation": "speciation",
	"species_extinct": "extinction", "die_off": "extinction",
	"battle": "war", "conquest": "war",
	"invention": "discovery", "tech": "discovery", "research": "discovery", "breakthrough": "discovery",
	"city": "civilization", "empire": "civilization", "founding": "civilization", "expand": "civilization",
	"earthquake": "disaster", "volcano": "disaster", "famine": "disaster", "tsunami": "disaster",
	"drought": "climate", "warming": "climate", "cooling": "climate",
	"epidemic": "plague", "pandemic": "plague", "worship": "civilization",
	"era": "era_change", "awakening": "sapience", "prosperity": "golden_age", "resurrection": "lazarus",
}

## Types dont les gabarits inventeraient des faits : si la simulation fournit un résumé, on raconte ce résumé.
const SUMMARY_TYPES := ["discovery", "war", "civilization", "generic"]

## Lexique par ère : décor, acteurs anonymes, nature du savoir, du conflit, et ton de la conclusion.
const ERA_LEXICON := {
	"Mésozoïque": {
		"lieu": ["les forêts de fougères géantes", "les marais fumants", "les plaines de cycas", "les rivages de la mer intérieure"],
		"acteurs": ["les grands sauriens", "les troupeaux à cornes", "les prédateurs aux dents en lame", "les ptérosaures"],
		"savoir": ["un nouvel instinct", "une ruse de chasse inédite"],
		"conflit": ["une lutte de crocs et d'écailles", "un affrontement de titans"],
		"fin": ["La Terre est jeune, et elle a faim.", "Les écailles ne savent rien de Toi, mais elles T'obéissent.", "Le règne des géants vacille."],
	},
	"Cénozoïque": {
		"lieu": ["les savanes nouvelles", "les forêts tempérées", "les steppes balayées de vent", "les vallées encore tièdes"],
		"acteurs": ["les mammifères", "les meutes à fourrure", "les premiers primates", "les oiseaux coureurs"],
		"savoir": ["un geste inédit", "une façon nouvelle de survivre"],
		"conflit": ["une guerre de territoires", "une rivalité de meutes"],
		"fin": ["Le sang chaud hérite du monde.", "Les petits survivants deviennent les maîtres.", "Rien n'est écrit, sinon par Toi."],
	},
	"Préhistoire": {
		"lieu": ["les cavernes ornées", "les campements autour du feu", "la toundra sans fin", "les rives des grands lacs"],
		"acteurs": ["les clans", "les chasseurs-cueilleurs", "les tailleurs de pierre", "les conteurs du feu"],
		"savoir": ["la maîtrise du feu", "un outil de silex plus tranchant", "les premiers signes peints"],
		"conflit": ["une guerre de clans", "une querelle pour les terres de chasse"],
		"fin": ["Ils lèvent les yeux vers le ciel et Te cherchent.", "Leurs mythes naîtront de ce jour.", "Le feu garde la mémoire de Ton geste."],
	},
	"Antiquité": {
		"lieu": ["les cités de pierre", "les deltas fertiles", "les temples de marbre", "les routes des caravanes"],
		"acteurs": ["les rois-prêtres", "les légions", "les scribes", "les marchands des ports"],
		"savoir": ["l'écriture", "la géométrie", "le travail du bronze"],
		"conflit": ["une guerre d'empires", "un siège interminable"],
		"fin": ["Les scribes graveront Ton nom dans l'argile.", "Les oracles débattent de Ta volonté.", "Les empires passent ; Toi, Tu demeures."],
	},
	"Moyen Âge": {
		"lieu": ["les royaumes fortifiés", "les monastères isolés", "les champs de seigle", "les bourgs fortifiés"],
		"acteurs": ["les seigneurs", "les moines copistes", "les paysans", "les chevaliers"],
		"savoir": ["le moulin à eau", "l'art des cathédrales", "les chiffres venus d'Orient"],
		"conflit": ["une croisade", "une guerre de succession"],
		"fin": ["Les cloches sonnent pour Toi.", "Les chroniqueurs y verront un signe du Ciel.", "La foi des humbles se fait plus ardente."],
	},
	"Renaissance": {
		"lieu": ["les cités marchandes", "les ateliers des maîtres", "les ports ouverts sur l'océan", "les universités"],
		"acteurs": ["les savants", "les navigateurs", "les banquiers", "les artistes"],
		"savoir": ["l'imprimerie", "la lunette astronomique", "l'anatomie"],
		"conflit": ["une guerre de religion", "une rivalité de cités-États"],
		"fin": ["L'homme se croit le centre du monde ; Tu souris.", "Les cartes se redessinent sous Ton regard.", "La raison s'éveille, mais elle Te doit tout."],
	},
	"Industriel": {
		"lieu": ["les villes de brique et de suie", "les mines profondes", "les voies ferrées", "les usines fumantes"],
		"acteurs": ["les ouvriers", "les ingénieurs", "les capitaines d'industrie", "les syndicats"],
		"savoir": ["la machine à vapeur", "l'électricité", "l'acier en masse"],
		"conflit": ["une guerre mécanisée", "une révolte ouvrière"],
		"fin": ["Les cheminées crachent leur prière noire vers Toi.", "Le progrès avance, aveugle et bruyant.", "Le monde tourne plus vite, mais toujours dans Ta main."],
	},
	"Moderne": {
		"lieu": ["les mégapoles", "les réseaux du monde entier", "les laboratoires", "les rivages bétonnés"],
		"acteurs": ["les nations", "les chercheurs", "les foules connectées", "les gouvernements"],
		"savoir": ["l'atome", "l'informatique", "le décodage du génome"],
		"conflit": ["une guerre mondiale", "une crise entre superpuissances"],
		"fin": ["Les écrans retransmettent Ton œuvre en direct.", "L'humanité se demande si elle est seule ; elle ne l'est pas.", "Le monde retient son souffle."],
	},
	"Cyberpunk": {
		"lieu": ["les arcologies néon", "les bas-fonds sous la pluie acide", "les fermes de serveurs", "les zones franches des mégacorpos"],
		"acteurs": ["les mégacorporations", "les hackers", "les cyborgs", "les IA de contrôle"],
		"savoir": ["l'implant neuronal", "la conscience téléchargée", "la fusion compacte"],
		"conflit": ["une guerre de corporations", "une insurrection des réseaux"],
		"fin": ["Les flux de données murmurent Ton nom chiffré.", "Les néons clignotent, comme un signe.", "Même les IA cherchent un sens à Ton geste."],
	},
	"Post-singularité": {
		"lieu": ["la sphère de calcul", "les mondes simulés", "les orbites peuplées", "le substrat planétaire"],
		"acteurs": ["les esprits fusionnés", "les intelligences ascendantes", "les derniers biologiques", "les essaims de machines"],
		"savoir": ["la réécriture de la matière", "la simulation de mondes entiers"],
		"conflit": ["une guerre d'algorithmes", "un schisme entre esprits"],
		"fin": ["Tes créatures frappent désormais à la porte de Ton royaume.", "Elles commencent, elles aussi, à créer des mondes.", "Le cercle se referme."],
	},
	"generic": {
		"lieu": ["les terres du monde", "les confins de la planète", "les vallées et les mers"],
		"acteurs": ["les vivants", "les créatures du monde", "les peuples"],
		"savoir": ["un savoir nouveau"],
		"conflit": ["une grande lutte"],
		"fin": ["Le monde se souviendra.", "Ton geste se répercute à travers les âges."],
	},
}

const OUVERTURES := [
	"Ô Toi qui veilles,", "Seigneur,", "Écoute, Créateur :", "Ô Toi dont la main façonne les âges,",
	"Sache-le, Très-Haut :", "",
]

## Gabarits par type d'événement. Emplacements : {ouverture} {lieu} {acteurs} {espece} {date} {savoir}
## {conflit} {fin} {ere} {resume}.
## Accord en nombre : [espece:singulier|pluriel] et [lieu:singulier|pluriel] sont choisis selon que
## l'espèce (ou le lieu) est au singulier ou au pluriel. Une espèce au singulier est toujours
## « l'espèce X » (féminin) ; au pluriel, « les X » (masculin par défaut). {acteurs} est toujours pluriel.
const EVENT_TEMPLATES := {
	"meteor": [
		"{ouverture} Ton feu est tombé du ciel sur {lieu}. {fin}",
		"{date}, une pierre céleste frappe {lieu} ; {acteurs} ne verront pas l'aube. {fin}",
		"{ouverture} le ciel s'est ouvert, et {lieu} [lieu:n'est plus que cendres|ne sont plus que cendres]. {fin}",
	],
	"extinct": [
		"{ouverture} d'un mot, Tu as effacé {espece} du livre de la vie. {fin}",
		"{date}, {espece} [espece:s'éteint|s'éteignent] par Ta volonté ; {lieu} [lieu:se tait|se taisent]. {fin}",
		"Il ne reste de {espece} que des os et du silence. {fin}",
	],
	"extinction": [
		"{date}, {espece} [espece:disparaît|disparaissent] à jamais de {lieu}. {fin}",
		"{ouverture} {espece} n'[espece:a|ont] pas survécu ; le monde compte un vide de plus. {fin}",
		"Le dernier représentant de {espece} s'est couché dans {lieu}. {fin}",
	],
	"save": [
		"{ouverture} Ta main a retenu {espece} au bord de l'abîme. {fin}",
		"{date}, {espece} [espece:échappe|échappent] à la fin, [espece:protégée|protégés] par Ta grâce. {fin}",
		"Là où tout devait finir, {espece} [espece:respire|respirent] encore. {fin}",
	],
	"bless": [
		"{ouverture} Ta bénédiction se répand sur {lieu}, et {acteurs} prospèrent. {fin}",
		"{date}, {espece} [espece:reçoit|reçoivent] Ta faveur ; [espece:ses|leurs] enfants seront nombreux. {fin}",
		"Une lumière douce baigne {lieu}. {fin}",
	],
	"plague": [
		"{ouverture} un mal invisible ravage {lieu}. {fin}",
		"{date}, la peste frappe {espece} ; les survivants Te maudissent ou Te prient. {fin}",
		"La fièvre court chez {espece}, et nul remède ne l'arrête. {fin}",
	],
	"uplift": [
		"{ouverture} Tu as allumé l'étincelle de l'esprit chez {espece}. {fin}",
		"{date}, {espece} [espece:lève|lèvent] les yeux et, pour la première fois, [espece:se demande|se demandent] pourquoi. {fin}",
		"Une pensée neuve naît dans {lieu} : {espece} [espece:vient|viennent] de s'éveiller. {fin}",
	],
	"flood": [
		"{ouverture} les eaux montent et engloutissent {lieu}. {fin}",
		"{date}, le déluge recouvre {lieu} ; {acteurs} fuient vers les hauteurs. {fin}",
		"La mer reprend {lieu}, comme Tu l'as voulu. {fin}",
	],
	"ice_age": [
		"{ouverture} le froid descend sur le monde, et {lieu} [lieu:blanchit|blanchissent]. {fin}",
		"{date}, les glaces avancent ; {acteurs} doivent s'adapter ou périr. {fin}",
		"Un long hiver commence, que Toi seul as décidé. {fin}",
	],
	"spawn_species": [
		"{ouverture} {espece} [espece:foule|foulent] pour la première fois {lieu}. {fin}",
		"{date}, Tu as façonné {espece} de Tes mains. {fin}",
		"Le monde compte de nouveaux habitants : {espece}. {fin}",
	],
	"speciation": [
		"{date}, une lignée nouvelle se détache des autres dans {lieu} : {espece}. {fin}",
		"{ouverture} la vie bifurque : {espece} [espece:apparaît|apparaissent]. {fin}",
		"Dans {lieu}, l'évolution a tranché, et {espece} [espece:est née|sont nés]. {fin}",
	],
	"migration": [
		"{date}, {acteurs} quittent {lieu} en quête de terres nouvelles. {fin}",
		"{ouverture} {espece} [espece:traverse|traversent] le monde, [espece:poussée|poussés] par la faim et l'espoir. {fin}",
		"Une grande migration s'ébranle ; {lieu} [lieu:se vide|se vident]. {fin}",
	],
	"war": [
		"{date}, {conflit} embrase {lieu}. {fin}",
		"{ouverture} {acteurs} s'entre-déchirent ; le sang coule dans {lieu}. {fin}",
		"Le fracas de {conflit} monte jusqu'à Toi. {fin}",
	],
	"discovery": [
		"{date}, {acteurs} découvrent {savoir}. {fin}",
		"{ouverture} dans {lieu}, une idée change tout : {savoir}. {fin}",
		"{savoir_maj} transforme la vie de {acteurs}. {fin}",
	],
	"civilization": [
		"{date}, {acteurs} fondent un ordre nouveau dans {lieu}. {fin}",
		"{ouverture} {espece} [espece:bâtit, compte et se souvient|bâtissent, comptent et se souviennent] : une civilisation est née. {fin}",
		"Des murs s'élèvent dans {lieu} ; {acteurs} se croient éternels. {fin}",
	],
	"disaster": [
		"{date}, la terre gronde et {lieu} [lieu:s'effondre|s'effondrent]. {fin}",
		"{ouverture} la catastrophe frappe {lieu} ; {acteurs} pleurent leurs morts. {fin}",
		"Le monde tremble sous {lieu}. {fin}",
	],
	"climate": [
		"{date}, le climat bascule et {lieu} [lieu:change|changent] de visage. {fin}",
		"{ouverture} les saisons se dérèglent ; {acteurs} doivent s'adapter. {fin}",
		"L'air lui-même change sur {lieu}. {fin}",
	],
	"era_change": [
		"{ouverture} un âge s'achève ; voici venir {ere}. {fin}",
		"{date}, le monde entre dans {ere}. {fin}",
		"Les chroniques tournent une page : {ere} commence. {fin}",
	],
	"sapience": [
		"{ouverture} {espece} [espece:prend|prennent] conscience d'[espece:elle-même|eux-mêmes] ; une pensée est née dans {lieu}. {fin}",
		"{date}, {espece} [espece:lève|lèvent] les yeux vers le ciel et Te [espece:devine|devinent]. {fin}",
		"Pour la première fois, au sein de {espece}, quelqu'un se demande qui Tu es. {fin}",
	],
	"golden_age": [
		"{date}, {espece} [espece:connaît|connaissent] un âge d'or dans {lieu}. {fin}",
		"{ouverture} la prospérité sourit à {espece}. {fin}",
		"Les greniers débordent et les arts fleurissent chez {espece}. {fin}",
	],
	"decline": [
		"{date}, la grandeur de {espece} s'effrite. {fin}",
		"{ouverture} {espece} [espece:oublie|oublient] peu à peu [espece:sa|leur] gloire passée. {fin}",
		"Les monuments de {espece} se lézardent sous Ton regard. {fin}",
	],
	"lazarus": [
		"{ouverture} {espece}, que l'on [espece:croyait perdue|croyait perdus], [espece:revient|reviennent] d'entre les morts. {fin}",
		"{date}, Ta main ramène {espece} du néant. {fin}",
		"Ce qui était éteint renaît : {espece} [espece:foule|foulent] de nouveau {lieu}. {fin}",
	],
	"generic": [
		"{date}, quelque chose change dans {lieu}. {fin}",
		"{ouverture} {acteurs} poursuivent leur route sous Ton regard. {fin}",
		"Le monde suit son cours, mais Ton ombre plane sur {lieu}. {fin}",
	],
}

## Gabarits utilisés quand la simulation fournit un résumé factuel ({resume}).
const SUMMARY_TEMPLATES := [
	"{date}, {resume}. {fin}",
	"{ouverture} {resume}. {fin}",
	"Les chroniques retiennent ceci : {resume}. {fin}",
]


## Situations de prière reconnues.
const PRAYER_SITUATIONS := ["famine", "war", "plague", "disaster", "cold", "flood", "decline", "prosperity", "generic"]

## Comment chaque ère s'adresse à Dieu.
const INVOCATIONS := {
	"Mésozoïque": "Ô Grande Ombre du ciel",
	"Cénozoïque": "Ô Souffle qui fait pousser l'herbe",
	"Préhistoire": "Ô Grand Esprit au-delà des nuages",
	"Antiquité": "Ô Père des dieux",
	"Moyen Âge": "Seigneur tout-puissant",
	"Renaissance": "Ô Grand Architecte",
	"Industriel": "Ô Providence",
	"Moderne": "Dieu, si Tu existes",
	"Cyberpunk": "Ô Administrateur Suprême du réseau",
	"Post-singularité": "Ô Programmeur originel",
	"generic": "Ô Toi qui nous as faits",
}

const PRAYER_TEMPLATES := {
	"famine": ["nos greniers sont vides et nos enfants ont faim.", "la terre ne nourrit plus notre peuple."],
	"war": ["{ennemi} marche contre nous et nos défenses cèdent.", "notre peuple se meurt sous les coups de {ennemi}."],
	"plague": ["une maladie nous dévore, et nos guérisseurs sont impuissants.", "la fièvre emporte les nôtres par milliers."],
	"disaster": ["la terre s'est ouverte sous nos maisons.", "le feu et les pierres sont tombés sur nos villes."],
	"cold": ["le froid gagne nos terres et rien ne pousse plus.", "les glaces dévorent nos champs."],
	"flood": ["les eaux ont englouti nos foyers.", "la mer avance et nous n'avons plus où fuir."],
	"decline": ["notre peuple s'amenuise et oublie qui il était.", "nous sommes de moins en moins nombreux, et le monde nous oublie."],
	"prosperity": ["nous prospérons, et nous Te rendons grâce.", "nos champs débordent et nos cités grandissent grâce à Toi."],
	"generic": ["nous ne savons pas ce que Tu attends de nous.", "nous, {nom}, cherchons un signe de Ta part."],
}

const PRAYER_REQUESTS := {
	"famine": ["Donne-nous de quoi survivre, même si d'autres doivent en manquer.", "Fais pleuvoir sur nos champs, ou prends nos voisins à notre place."],
	"war": ["Écrase {ennemi}, ou accorde-nous au moins la paix.", "Donne-nous la victoire, quel qu'en soit le prix pour {ennemi}."],
	"plague": ["Guéris-nous, ou dis-nous quelle faute nous expions.", "Épargne nos enfants, et nous Te servirons pour toujours."],
	"disaster": ["Apaise la colère du monde, ou conduis-nous vers une terre plus sûre.", "Relève nos murs, et nous bâtirons un temple à Ta gloire."],
	"cold": ["Rends-nous le soleil, ou donne-nous la force d'endurer l'hiver.", "Réchauffe le monde, même si les glaces abritaient d'autres vies."],
	"flood": ["Retiens les eaux, ou montre-nous les hauteurs.", "Assèche la terre, et nous ne T'oublierons jamais."],
	"decline": ["Rends-nous notre grandeur, ou laisse-nous disparaître en paix.", "Élève-nous au-dessus des autres peuples."],
	"prosperity": ["Accorde-nous de dominer le monde, comme Tu l'as voulu.", "Garde-nous dans Ta faveur, nous et nos descendants."],
	"generic": ["Parle-nous, ou laisse-nous choisir seuls notre chemin.", "Montre-nous la voie."],
}

## Choix moraux proposés au joueur face à une prière (action divine au format du contrat, ou null = ne rien faire).
const PRAYER_CHOICES := {
	"famine": [["Exaucer : bénir leurs terres", "bless"], ["Ignorer leur prière", ""], ["Les éprouver : envoyer la peste", "plague"]],
	"war": [["Protéger ce peuple", "save"], ["Laisser la guerre décider", ""], ["Élever leurs ennemis", "uplift"]],
	"plague": [["Les guérir", "save"], ["Laisser le mal suivre son cours", ""], ["Bénir les survivants", "bless"]],
	"disaster": [["Les sauver", "save"], ["Ne rien faire", ""], ["Achever l'œuvre du destin", "meteor"]],
	"cold": [["Bénir leurs foyers", "bless"], ["Laisser l'hiver les endurcir", ""], ["Prolonger l'âge glaciaire", "ice_age"]],
	"flood": [["Les sauver des eaux", "save"], ["Laisser les eaux monter", ""], ["Achever le déluge", "flood"]],
	"decline": [["Élever leur esprit", "uplift"], ["Les laisser s'éteindre", ""], ["Les effacer", "extinct"]],
	"prosperity": [["Bénir encore", "bless"], ["Rester silencieux", ""], ["Rappeler leur humilité : une épidémie", "plague"]],
	"generic": [["Bénir", "bless"], ["Garder le silence", ""], ["Éprouver leur foi", "plague"]],
}

const ORACLE_OUVERTURES := [
	"Les fils du temps se sont écartés devant moi, Seigneur.",
	"J'ai regardé dans le puits des âges.",
	"Voici ce que murmurent les siècles à venir.",
	"Le futur est une fumée, mais j'y lis des formes.",
]
const ORACLE_VAGUES := [
	"Je ne vois que brume : rien n'est encore décidé, et tout dépend de Toi.",
	"Le futur se tait, comme s'il attendait Ton prochain geste.",
	"Les présages sont muets ; peut-être le monde retient-il son souffle.",
]
const ORACLE_FINS := [
	"Mais ce qui est prédit n'est pas écrit : Ta main peut tout changer.",
	"Ainsi parle le temps, si Tu le laisses parler.",
	"Agis, ou laisse faire : dans les deux cas, ce sera Ton choix.",
]

var rng := RandomNumberGenerator.new()


func _init(p_seed: int = -1) -> void:
	if p_seed >= 0:
		rng.seed = p_seed
	else:
		rng.randomize()


# ---------------------------------------------------------------------------
# Utilitaires publics (partagés avec le constructeur de prompts)
# ---------------------------------------------------------------------------

## Ramène un nom d'ère quelconque à une clé du lexique ("generic" si inconnue).
static func era_key(era: Variant) -> String:
	var s := str(era).strip_edges()
	if ERA_LEXICON.has(s):
		return s
	var n := _fold(s)
	for e in ERAS:
		if _fold(e) == n:
			return e
	if typeof(era) == TYPE_INT and era >= 0 and era < ERAS.size():
		return ERAS[era]
	return "generic"


static func era_with_article(era: Variant) -> String:
	return ERA_ARTICLES[era_key(era)]


## Ramène un type d'événement à un type canonique ("generic" si inconnu).
static func event_key(event_type: Variant) -> String:
	var s := str(event_type).strip_edges().to_lower().trim_prefix("divine_")
	if s in EVENT_TYPES:
		return s
	return EVENT_ALIASES.get(s, "generic")


## Date lisible en français à partir de l'année de la simulation.
static func format_year(year: float) -> String:
	if year <= -1_000_000.0:
		var m := -year / 1_000_000.0
		if m >= 10.0:
			return "il y a %d millions d'années" % int(round(m))
		return "il y a %s millions d'années" % String.num(m, 1).replace(".", ",")
	if year <= -10_000.0:
		return "il y a %d mille ans" % int(round(-year / 1000.0))
	if year < 0.0:
		return "en l'an %d avant notre ère" % int(round(-year))
	return "en l'an %d" % int(round(year))


## Nom d'espèce lisible à partir du contexte (species_name, species.name, ou espèce n°id).
static func species_name(context: Dictionary, default_name: String = "") -> String:
	if context.get("species_name", "") is String and context.get("species_name", "") != "":
		return context["species_name"]
	var sp: Variant = context.get("species", null)
	if sp is Dictionary and sp.get("name", "") is String and sp.get("name", "") != "":
		return sp["name"]
	if default_name != "":
		return default_name
	var sid: Variant = context.get("species_id", -1)
	if typeof(sid) in [TYPE_INT, TYPE_FLOAT] and int(sid) >= 0:
		return "l'espèce n°%d" % int(sid)
	return ""


## Groupe nominal accordable pour un nom d'espèce : {text, plural}.
## - déjà muni d'un article (« les premiers primates », « la lignée ») : conservé tel quel ;
## - nom de groupe dont le premier mot finit par -s/-x (« Multituberculés », « Euthériens insectivores »,
##   « Humains Mivel ») : pluriel, « les X » — sauf si une épithète en minuscule ne finit pas par -s/-x
##   (binôme hérité d'un genre au pluriel, ex. « Squamates nuloa ») ;
## - sinon (binôme latin « Verpha moloum », nom unique) : singulier, « l'espèce X ».
static func species_phrase(name: String) -> Dictionary:
	var n := name.strip_edges()
	if n == "":
		return {"text": "", "plural": false}
	var low := n.to_lower()
	for art in ["les ", "des ", "ces ", "leurs ", "nos "]:
		if low.begins_with(art):
			return {"text": art + n.substr(art.length()), "plural": true}
	for art in ["le ", "la ", "l'", "l’", "un ", "une ", "cette ", "ce "]:
		if low.begins_with(art):
			return {"text": art + n.substr(art.length()), "plural": false}
	var words := n.split(" ", false)
	var plural: bool = words[0].length() > 2 and words[0].right(1).to_lower() in ["s", "x"]
	for w in words.slice(1):
		var first := w.substr(0, 1)
		if first == first.to_lower() and first != first.to_upper() and not (w.right(1) in ["s", "x"]):
			plural = false
	if plural:
		return {"text": "les " + n, "plural": true}
	return {"text": "l'espèce " + n, "plural": false}


## Le lieu (« les marais », « la toundra ») est-il au pluriel ?
static func is_plural_phrase(phrase: String) -> bool:
	var low := phrase.strip_edges().to_lower()
	return low.begins_with("les ") or low.begins_with("des ")


## Résout les marques d'accord [cle:singulier|pluriel] selon plurals[cle] (pluriel si la clé est inconnue).
static func apply_agreement(tpl: String, plurals: Dictionary) -> String:
	var re := RegEx.new()
	re.compile("\\[(\\w+):([^|\\]]*)\\|([^\\]]*)\\]")
	var out := tpl
	for m in re.search_all(tpl):
		var plural: bool = plurals.get(m.get_string(1), true)
		out = out.replace(m.get_string(0), m.get_string(3) if plural else m.get_string(2))
	return out


## Résumé de la simulation rendu narrable : sans préfixe court (« Guerre : », « Dieu : »), sans point final,
## article initial en minuscule (« Les Humains... » -> « les Humains... »).
static func clean_summary(summary: String) -> String:
	var t := summary.strip_edges().trim_suffix(".").strip_edges()
	var colon := t.find(" : ")
	if colon > 0 and t.substr(0, colon).split(" ").size() <= 3 and t.length() > colon + 3:
		t = t.substr(colon + 3).strip_edges()
	var first := t.split(" ")[0]
	if first in ["Les", "Le", "La", "Un", "Une", "Des", "Une", "Nouvelle", "Nouveau"] or t.begins_with("L'"):
		t = t.substr(0, 1).to_lower() + t.substr(1)
	return t


# ---------------------------------------------------------------------------
# Génération
# ---------------------------------------------------------------------------

## Narration d'un événement ou d'un lot d'événements.
## context : {type, era, year, species_name|species|species_id, summary, events: Array[Dictionary]}
func narrate(context: Dictionary) -> String:
	var events: Variant = context.get("events", [])
	if events is Array and not events.is_empty():
		return _narrate_batch(context, events)
	return _narrate_one(context)


func _narrate_batch(context: Dictionary, events: Array) -> String:
	# Le premier événement (le plus important) est raconté en entier, le suivant en écho.
	var first: Dictionary = events[0] if events[0] is Dictionary else {"summary": str(events[0])}
	var ctx := first.duplicate()
	for k in ["era", "year"]:
		if not ctx.has(k) and context.has(k):
			ctx[k] = context[k]
	var text := _narrate_one(ctx)
	if events.size() > 1:
		var others := events.size() - 1
		var echo := [
			"Et ce n'est pas tout : %d autre%s bouleversement%s secoue%s le monde." % [others, _s(others), _s(others), "nt" if others > 1 else ""],
			"Ailleurs, %d autre%s signe%s de Ta présence se manifeste%s." % [others, _s(others), _s(others), "nt" if others > 1 else ""],
		]
		text += " " + echo[rng.randi() % echo.size()]
	return text


func _narrate_one(context: Dictionary) -> String:
	var era := era_key(context.get("era", ""))
	var etype := event_key(context.get("type", "generic"))
	var lex: Dictionary = ERA_LEXICON[era]
	var slots := _era_slots(lex, context)
	slots["ere"] = era_with_article(era)
	# Pour les types où un gabarit inventerait des faits, le résumé de la simulation fait foi.
	var resume := clean_summary(str(context.get("summary", "")))
	var templates: Array = EVENT_TEMPLATES[etype]
	if resume != "" and etype in SUMMARY_TYPES:
		templates = SUMMARY_TEMPLATES
		slots["resume"] = resume
	return _render(templates[rng.randi() % templates.size()], slots)


## Rend un gabarit précis pour un contexte (utilisé par les tests pour couvrir chaque gabarit).
func render(tpl: String, context: Dictionary) -> String:
	var era := era_key(context.get("era", ""))
	var slots := _era_slots(ERA_LEXICON[era], context)
	slots["ere"] = era_with_article(era)
	slots["resume"] = clean_summary(str(context.get("summary", "")))
	if context.has("lieu"):
		slots["lieu"] = context["lieu"]
	return _render(tpl, slots)


func _render(tpl: String, slots: Dictionary) -> String:
	var t := apply_agreement(tpl, {"espece": slots["_espece_pl"], "lieu": is_plural_phrase(slots["lieu"]), "acteurs": true})
	return _polish(_fill(t, slots))


## Prière d'une espèce sapiente. species : {id, name, ...} ; situation : {type, enemy, ...}
func prayer(species: Dictionary, situation: Dictionary) -> String:
	var era := era_key(situation.get("era", species.get("era", "")))
	var kind := prayer_key(situation.get("type", "generic"))
	var nom := str(species.get("name", "")).strip_edges()
	if nom == "":
		nom = "Tes enfants"
	var ennemi := str(situation.get("enemy", situation.get("enemy_name", ""))).strip_edges()
	if ennemi == "":
		ennemi = "l'ennemi"
	var slots := {"nom": nom, "ennemi": ennemi}
	var plaintes: Array = PRAYER_TEMPLATES[kind]
	var demandes: Array = PRAYER_REQUESTS[kind]
	var text := "%s, %s %s" % [
		INVOCATIONS[era],
		_fill(plaintes[rng.randi() % plaintes.size()], slots),
		_fill(demandes[rng.randi() % demandes.size()], slots),
	]
	return _polish(text)


static func prayer_key(situation_type: Variant) -> String:
	var s := str(situation_type).strip_edges().to_lower()
	if s in PRAYER_SITUATIONS:
		return s
	match s:
		"hunger", "drought": return "famine"
		"invasion", "battle", "conquest": return "war"
		"epidemic", "disease", "pandemic": return "plague"
		"meteor", "earthquake", "volcano": return "disaster"
		"ice_age", "winter": return "cold"
		"extinction", "decay": return "decline"
		"bless", "growth", "golden_age": return "prosperity"
	return "generic"


## Choix moraux associés à une prière : [{label, action}] ; action = {} pour « ne rien faire ».
static func prayer_choices(species: Dictionary, situation: Dictionary) -> Array:
	var out := []
	var region: Variant = situation.get("region", Vector2i.ZERO)
	var sid := int(species.get("id", situation.get("species_id", -1)))
	var enemy_id := int(situation.get("enemy_id", sid))
	for c in PRAYER_CHOICES[prayer_key(situation.get("type", "generic"))]:
		var action := {}
		if c[1] != "":
			action = {
				"type": c[1], "region": region, "radius": 8,
				"species_id": enemy_id if c[1] == "uplift" and situation.has("enemy_id") else sid,
			}
		out.append({"label": c[0], "action": action})
	return out


## Prophétie à partir d'une projection du futur (WorldSim.project_future()).
func prophecy(question: String, projection: Dictionary) -> String:
	var visions := projection_visions(projection)
	var parts := [ORACLE_OUVERTURES[rng.randi() % ORACLE_OUVERTURES.size()]]
	var q := question.strip_edges()
	if q != "" and rng.randf() < 0.5:
		parts[0] = "Tu demandes « %s ». %s" % [q.trim_suffix("?").strip_edges(), parts[0]]
	if visions.is_empty():
		parts.append(ORACLE_VAGUES[rng.randi() % ORACLE_VAGUES.size()])
	else:
		var shown := visions.slice(0, 2)
		parts.append("Je vois " + " ; puis ".join(shown) + ".")
		parts.append(ORACLE_FINS[rng.randi() % ORACLE_FINS.size()])
	return _polish(" ".join(parts))


## Transforme une projection (format libre) en courtes visions lisibles. Tolère un dictionnaire vide.
static func projection_visions(projection: Dictionary) -> Array:
	var out := []
	var years: Variant = projection.get("years", projection.get("horizon", null))
	if years == null and typeof(projection.get("to_year")) in [TYPE_INT, TYPE_FLOAT] and typeof(projection.get("from_year")) in [TYPE_INT, TYPE_FLOAT]:
		years = float(projection["to_year"]) - float(projection["from_year"])
	var prefix := ""
	if typeof(years) in [TYPE_INT, TYPE_FLOAT] and float(years) > 0.0:
		prefix = "dans %s, " % _duration(float(years))
	if projection.get("summary", "") is String and projection.get("summary", "") != "":
		out.append(prefix + clean_summary(str(projection["summary"])))
		prefix = ""
	var era: Variant = projection.get("era", projection.get("era_reached", projection.get("final_era", null)))
	if era is String and era != "":
		out.append(prefix + "le monde entré dans %s" % era_with_article(era))
		prefix = ""
	for key in ["extinctions", "extinct_species", "extinct"]:
		var ex: Variant = projection.get(key, null)
		if ex is Array and not ex.is_empty():
			var names: Array = ex.slice(0, 3).map(func(e): return _label(e)).filter(func(l): return l != "")
			if not names.is_empty():
				out.append("%sla fin de %s" % [prefix, ", de ".join(names)])
				prefix = ""
			break
	var dom: Variant = projection.get("dominant_species", projection.get("dominant", null))
	var dom_label := _label(dom) if dom != null else ""
	if dom_label != "":
		out.append("%s%s régnant sur le monde" % [prefix, dom_label])
		prefix = ""
	var evs: Variant = projection.get("key_events", projection.get("events", null))
	if evs is Array:
		for e in evs.slice(0, 3):
			var s := clean_summary(str(e.get("summary", "")) if e is Dictionary else str(e))
			if s != "":
				out.append(prefix + s)
				prefix = ""
	return out.map(func(v): return contract(String(v).strip_edges()))


# ---------------------------------------------------------------------------
# Interne
# ---------------------------------------------------------------------------

func _era_slots(lex: Dictionary, context: Dictionary) -> Dictionary:
	var acteurs := _pick(lex["acteurs"])
	var savoir := _pick(lex["savoir"])
	# Espèce inconnue : les acteurs de l'ère (toujours au pluriel) en tiennent lieu.
	var esp := species_phrase(species_name(context, acteurs))
	var date := format_year(float(context["year"])) if typeof(context.get("year")) in [TYPE_INT, TYPE_FLOAT] else "En ce jour"
	return {
		"ouverture": _pick(OUVERTURES),
		"lieu": _pick(lex["lieu"]),
		"acteurs": acteurs,
		"espece": esp["text"],
		"_espece_pl": esp["plural"],
		"date": date,
		"savoir": savoir,
		"savoir_maj": savoir.substr(0, 1).to_upper() + savoir.substr(1),
		"conflit": _pick(lex["conflit"]),
		"fin": _pick(lex["fin"]),
	}


func _pick(arr: Array) -> String:
	return arr[rng.randi() % arr.size()]


static func _fill(tpl: String, slots: Dictionary) -> String:
	return tpl.format(slots)


## Nettoie espaces et majuscules en début de phrase.
static func _polish(text: String) -> String:
	var t := text.strip_edges()
	while t.contains("  "):
		t = t.replace("  ", " ")
	t = t.replace(" .", ".").replace(" ,", ",").replace("..", ".")
	t = contract(t)
	if t.length() > 0:
		t = t.substr(0, 1).to_upper() + t.substr(1)
	# Majuscule après chaque fin de phrase.
	for sep in [". ", "? ", "! "]:
		var idx: int = t.find(sep)
		while idx != -1 and idx + sep.length() < t.length():
			var p: int = idx + sep.length()
			t = t.substr(0, p) + t.substr(p, 1).to_upper() + t.substr(p + 1)
			idx = t.find(sep, p)
	return t


## Contractions françaises produites par l'assemblage des gabarits (« de les » -> « des »...).
static func contract(text: String) -> String:
	var t := text
	for pair in [[" de les ", " des "], [" de le ", " du "], [" à les ", " aux "], [" à le ", " au "]]:
		t = t.replace(pair[0], pair[1])
	if t.begins_with("De les "):
		t = "Des " + t.substr(7)
	elif t.begins_with("de les "):
		t = "des " + t.substr(7)
	return t


static func _fold(s: String) -> String:
	var t := s.to_lower()
	for pair in [["é", "e"], ["è", "e"], ["ê", "e"], ["ë", "e"], ["â", "a"], ["à", "a"], ["ï", "i"], ["î", "i"], ["ô", "o"], ["ö", "o"], ["ù", "u"], ["û", "u"], ["ü", "u"], ["ç", "c"], ["-", " "], ["_", " "]]:
		t = t.replace(pair[0], pair[1])
	return t.strip_edges()


## Groupe nominal d'une espèce donnée par son nom, son dictionnaire {id, name} ou son id ("" si inconnue).
static func _label(v: Variant) -> String:
	if v is Dictionary:
		var name := str(v.get("name", "")).strip_edges()
		if name != "":
			return species_phrase(name)["text"]
		v = v.get("id", -1)
	if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
		return "l'espèce n°%d" % int(v) if int(v) >= 0 else ""
	if str(v).is_valid_int():
		return _label(int(str(v)))
	return species_phrase(str(v))["text"]


static func _duration(n: float) -> String:
	if n >= 1_000_000.0:
		return "%s millions d'années" % String.num(n / 1_000_000.0, 1).replace(".", ",").trim_suffix(",0")
	if n >= 1000.0:
		return "%d mille ans" % int(round(n / 1000.0))
	return "%d ans" % int(round(n))


static func _s(n: int) -> String:
	return "s" if n > 1 else ""
