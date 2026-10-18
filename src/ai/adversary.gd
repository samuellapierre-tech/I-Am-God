extends RefCounted
## La voix de l'adversaire (son nom et sa persona : AiConfig.ADVERSARY_NAME / ADVERSARY_PERSONA).
## Il ne décide RIEN : ses coups viennent de src/strategy/ (signaux samael_move et samael_learned,
## relayés par GameState). Ici, on lui donne seulement la parole, en repli procédural complet :
## provocation en début de manche, satisfaction quand une menace frappe, dépit quand elle est contrée,
## remarques sur les habitudes du joueur, et parfois un échange avec le narrateur.
##
## Coup : {kind: "reveal"|"strike"|"taunt_hook", threat: carte de menace, reason_code}.
## Chaque réplique est {t, min_era?, max_era?} (époques de epoch.gd) et passe le filtre d'anachronismes.
## Déterministe à graine égale.
##
## Deux tons (STRATEGIE.md §10) : "trial" (mode Épreuve, l'accusateur) et "eternity" (mode Éternité,
## un rival doux qui propose des défis facultatifs au lieu d'attaquer).

const Procedural := preload("res://src/ai/procedural_narrator.gd")
const AiConfig := preload("res://src/ai/ai_config.gd")
const Epoch := preload("res://src/ai/epoch.gd")

## Pourquoi la stratégie a joué ce coup (reason_code), tel que l'adversaire peut le dire.
const REASON_CODES := ["random", "max_damage", "habit", "uncounterable", "work", "chain", "oracle", "bluff"]
## Comment il nomme les pouvoirs du joueur (mêmes pouvoirs que strategy_rules.POWER_LABELS).
const POWERS := {
	"flood": "le déluge", "bless": "la bénédiction", "save": "le salut", "plague": "le fléau",
	"ice_age": "l'âge glaciaire", "meteor": "la météorite", "uplift": "l'élévation", "extinct": "l'extinction",
	"spawn_species": "la création", "oracle": "l'Oracle",
}

## Emplacements : {menace} (titre de la carte), {menaces} (« 3 menaces »), {actions} (« 4 actions »),
## {pouvoir}, {narrateur}, {adversaire}.
const ROUND := [
	{"t": "Nouvelle manche : {menaces}, et ce n'est que le début."},
	{"t": "Tu as {actions}. Moi, j'ai toute la pioche."},
	{"t": "Encore une manche à te regarder retenir un monde qui ne demande qu'à tomber."},
	{"t": "Je ne triche pas, je n'en ai pas besoin. {menaces} : à toi."},
	{"t": "Ils te prient, tu les écoutes ; moi, je compte les jours.", "min_era": Epoch.FIRST_SAPIENT},
	{"t": "Tes créatures confient déjà leur sort à leurs machines. Je n'aurai qu'à attendre.", "min_era": Epoch.INFORMATION},
]
const REVEAL := {
	"random": [{"t": "{menace}. Même le hasard joue contre toi."}, {"t": "J'ai pioché les yeux fermés : {menace}. Ça suffira."}],
	"max_damage": [{"t": "{menace}. J'ai choisi ce qui fera le plus mal, tout de suite."}, {"t": "{menace}. Pourquoi attendre ?"}],
	"habit": [{"t": "{menace}. Tu réponds toujours de la même façon ; voyons si tu sais faire autre chose."}, {"t": "{menace}. Celle-là, tes gestes habituels ne la couvrent pas."}],
	"uncounterable": [{"t": "{menace}. Compte tes actions : tu n'en auras pas assez."}, {"t": "{menace}. Tu ne pourras pas tout contrer, et tu le sais."}],
	"work": [{"t": "{menace}. Ton Grand Œuvre est si fragile, encore."}, {"t": "{menace}. Je vise ce que tu construis, pas ce que tu as."}],
	"chain": [{"t": "{menace}. Une pierre tombe, et les autres suivent."}, {"t": "{menace}. Regarde bien ce qui tombera après."}],
	"oracle": [{"t": "J'ai regardé plus loin que toi. {menace}, maintenant ; le reste viendra."}, {"t": "{menace}. Dans quelques manches, tu comprendras pourquoi."}],
	"bluff": [{"t": "Peut-être que je bluffe. Peut-être pas. {menace}."}, {"t": "{menace}. À moins que ce ne soit l'autre carte qui compte."}],
}
const STRIKE := {
	"": [{"t": "{menace} frappe. Je n'ai même pas eu besoin d'insister."}, {"t": "Et voilà : {menace}. Ton monde est plus fragile que tu ne le crois."}, {"t": "{menace}. J'aime le bruit que fait un monde qui cède."}],
	"habit": [{"t": "Tu as fait comme d'habitude, et {menace} est passée à côté."}],
	"uncounterable": [{"t": "{menace}. Je t'avais dit que tu n'aurais pas assez d'actions."}],
	"oracle": [{"t": "{menace} frappe, comme je l'avais vu. Toi, tu regardais ailleurs."}],
	"work": [{"t": "{menace} frappe là où tu bâtissais. Recommence, si tu en as le temps."}],
	"chain": [{"t": "{menace}. Et maintenant, compte ce qui va tomber avec elle."}],
}
const SPITE := [
	{"t": "Contrée. Profite-en : la pioche, elle, ne s'épuise pas pour toi."},
	{"t": "Bien joué. Une fois. Je retiens comment tu as fait."},
	{"t": "Tu as sauvé ce que tu pouvais. Ce n'est jamais tout."},
	{"t": "{menace}, contrée. Je n'aime pas perdre une carte, mais j'en ai d'autres."},
]
const TAUNT := [
	{"t": "Tu crois que ce monde tiendra. C'est touchant."},
	{"t": "Chaque geste te coûte. Chaque manche me rapproche."},
	{"t": "Je ne fais que retourner des cartes. C'est toi qui as voulu ce monde."},
	{"t": "Tes créatures te prient de les sauver ; elles devraient prier pour que je me lasse.", "min_era": Epoch.FIRST_SAPIENT},
]
const HABIT := [
	{"t": "Toujours {pouvoir}… Je commence à te connaître."},
	{"t": "Encore {pouvoir}. Tu es prévisible, et j'en tiendrai compte."},
	{"t": "Tu réponds à tout par {pouvoir}. Je jouerai donc ce que ce geste ne couvre pas."},
]
## Échange (au plus un par manche) : l'adversaire répond au narrateur, ou l'inverse.
const TO_NARRATOR := [
	{"t": "Ton prophète a de belles visions. Les miennes finissent toutes de la même façon."},
	{"t": "{narrateur} écrit ; moi, je rature."},
	{"t": "Écoute ton témoin si tu veux. Il ne fait que raconter ta défaite à l'avance."},
]
const FROM_NARRATOR := [
	{"t": "Il parle beaucoup, pour quelqu'un qui ne fait que retourner des cartes."},
	{"t": "Ne l'écoute pas : {adversaire} ne voit rien que tu ne puisses voir."},
	{"t": "{adversaire} doute de tout, sauf de lui-même. Moi, j'ai vu des mondes tenir."},
]
const FALLBACK := {"t": "Continue. Je regarde."}

# --- Mode Éternité : un rival doux, des paris plutôt que des attaques ---------------------------
## Défis : {espece} est l'espèce la plus visible de la parcelle (needs : "species" ou "sapient").
const CHALLENGES := [
	{"t": "Je parie que {espece} [espece:ne verra|ne verront] pas la prochaine glaciation.", "needs": "species"},
	{"t": "Un pari : {espece} [espece:aura|auront] quitté ta parcelle avant la fin du chapitre.", "needs": "species"},
	{"t": "Garde {espece} en vie jusqu'au prochain chapitre ; je parie que non.", "needs": "species"},
	{"t": "Je parie qu'aucune espèce nouvelle n'apparaîtra sur ta parcelle avant le prochain chapitre."},
	{"t": "Un défi, pour passer le temps : que ta parcelle reste vivante jusqu'au prochain chapitre."},
	{"t": "Je parie que le climat de ta parcelle aura changé avant la fin du chapitre. Tu tiens le pari ?"},
	{"t": "Je parie que ta parcelle n'aura pas de village avant la fin du chapitre.", "min_era": Epoch.FIRST_SAPIENT},
	{"t": "Je parie que {espece} ne [espece:verra|verront] pas l'âge suivant.", "needs": "sapient", "min_era": Epoch.FIRST_SAPIENT},
	{"t": "Je parie qu'aucune bête ne posera la patte sur la terre ferme ici avant longtemps.", "min_era": Epoch.FIRST_ANIMALS, "max_era": Epoch.CAMBRIAN},
]
const REVEAL_ETERNAL := [
	{"t": "{menace} se prépare. Rien ne t'oblige à l'arrêter ; regardons ce qu'il en sortira."},
	{"t": "{menace}, au loin. Un défi de plus, si tu as envie de le relever."},
	{"t": "Je retourne une carte : {menace}. Fais-en ce que tu veux."},
]
const STRIKE_ETERNAL := [
	{"t": "{menace} est passée. Le monde s'en remettra, à sa façon."},
	{"t": "{menace}. Je compte le point pour moi, sans rancune."},
	{"t": "{menace}, et la vie continue. Elle continue toujours, c'est ce qui m'agace."},
]
const SPITE_ETERNAL := [
	{"t": "Joli. Je note le point pour toi."},
	{"t": "Contrée, avec élégance. Je retiens le geste."},
	{"t": "Tu as gagné celle-là. J'en ai d'autres, et tout notre temps."},
]
const HABIT_ETERNAL := [
	{"t": "Toujours {pouvoir}. C'est presque une signature."},
	{"t": "{pouvoir}, encore. Je commence à aimer tes manies."},
]
const TAUNT_ETERNAL := [
	{"t": "Rien ne presse. Le monde a tout son temps, et nous aussi."},
	{"t": "Je regarde avec toi, pour une fois."},
	{"t": "Je ne parie que pour le plaisir de perdre, parfois."},
]
const TO_NARRATOR_ETERNAL := [
	{"t": "Tes chroniques sont belles, {narrateur}. Je parie qu'elles seront très longues."},
	{"t": "Écris, {narrateur}. J'aime t'entendre raconter mes défaites."},
]
const FROM_NARRATOR_ETERNAL := [
	{"t": "{adversaire} parie encore. Laisse-le parier ; le monde décidera."},
	{"t": "Même {adversaire} s'est assis pour regarder. C'est dire si le monde est beau."},
]

## "trial" (Épreuve) ou "eternity" (Éternité : rival doux).
var tone := "trial"
## Mémoire anti-répétition partagée (variety.gd) ; null = sans (il retombe alors sur une réplique neutre).
var variety: RefCounted = null

var rng := RandomNumberGenerator.new()
var _seed := 0
var _count := 0


func _init(p_seed: int = -1) -> void:
	if p_seed >= 0:
		_seed = p_seed
	else:
		rng.randomize()
		_seed = rng.randi()


## Provocation de début de manche. round : {index, threats}, actions : budget (-1 inconnu).
## En mode Éternité, c'est un défi (ctx : contexte du fil, pour nommer l'espèce de la parcelle).
func round_taunt(rd: Dictionary, actions: int, epoch: int, ctx: Dictionary = {}) -> Dictionary:
	if tone == "eternity":
		return challenge(ctx, epoch)
	var n := (rd.get("threats", []) as Array).size()
	return _say("round", ROUND, epoch, {
		"menaces": "%d menace%s" % [n, "s" if n > 1 else ""] if n > 0 else "aucune menace visible",
		"actions": "%d action%s" % [actions, "s" if actions > 1 else ""] if actions >= 0 else "quelques actions",
	})


## Réplique à un coup joué par la stratégie (samael_move).
func move_line(move: Dictionary, epoch: int) -> Dictionary:
	var kind := str(move.get("kind", ""))
	var reason := str(move.get("reason_code", ""))
	var extra := {"menace": _title(move.get("threat", {}))}
	var line: Dictionary
	var eternal := tone == "eternity"
	match kind:
		"reveal":
			line = _say("reveal", REVEAL_ETERNAL if eternal else REVEAL.get(reason, REVEAL["max_damage"]), epoch, extra)
		"strike":
			line = _say("strike", STRIKE_ETERNAL if eternal else STRIKE.get(reason, []) + STRIKE[""], epoch, extra)
		_:
			line = _say("taunt", TAUNT_ETERNAL if eternal else TAUNT, epoch, extra)
	line["reason"] = reason
	return line


## Dépit : une menace vient d'être contrée.
func spite_line(threat: Dictionary, epoch: int) -> Dictionary:
	return _say("spite", SPITE_ETERNAL if tone == "eternity" else SPITE, epoch, {"menace": _title(threat)})


## Satisfaction quand une menace frappe, sans coup de la stratégie pour le dire (repli).
func strike_line(threat: Dictionary, epoch: int) -> Dictionary:
	return _say("strike", STRIKE_ETERNAL if tone == "eternity" else STRIKE[""], epoch, {"menace": _title(threat)})


## Remarque sur une habitude apprise (samael_learned) : {power|counter|kind, count?}.
func habit_line(habit: Dictionary, epoch: int) -> Dictionary:
	var power := str(habit.get("power", habit.get("counter", habit.get("kind", ""))))
	return _say("habit", HABIT_ETERNAL if tone == "eternity" else HABIT, epoch, {"pouvoir": POWERS.get(power, "les mêmes gestes")})


## Échange : l'adversaire répond au narrateur (to_narrator) ou le narrateur à l'adversaire.
func exchange_line(to_narrator: bool, epoch: int) -> Dictionary:
	var pool: Array = (TO_NARRATOR_ETERNAL if to_narrator else FROM_NARRATOR_ETERNAL) if tone == "eternity" else (TO_NARRATOR if to_narrator else FROM_NARRATOR)
	var line := _say("exchange", pool, epoch, {})
	if line.is_empty():
		return line
	line["speaker"] = AiConfig.ADVERSARY_NAME if to_narrator else AiConfig.NARRATOR_NAME
	return line


## Un défi facultatif (mode Éternité) sur l'espèce la plus visible de la parcelle.
func challenge(ctx: Dictionary, epoch: int) -> Dictionary:
	var best := {}
	var sapient := {}
	for f in ctx.get("snapshot", {}).get("fauna", []):
		if str(f.get("name", "")) == "":
			continue
		if best.is_empty() or int(f.get("count", 0)) > int(best.get("count", 0)):
			best = f
		if str(f.get("role", "")) == "sapient":
			sapient = f
	var pool := CHALLENGES.filter(func(c: Dictionary) -> bool: return (str(c.get("needs", "")) != "species" or not best.is_empty()) and (str(c.get("needs", "")) != "sapient" or not sapient.is_empty()))
	var subject: Dictionary = sapient if not sapient.is_empty() and rng.randf() < 0.5 else best
	var phrase := Procedural.species_phrase(str(subject.get("name", ""))) if not subject.is_empty() else {"text": "la vie", "plural": false}
	var line := _say("challenge", pool, epoch, {"espece": phrase["text"]}, phrase["plural"])
	if not line.is_empty():
		line["challenge"] = true
	return line


## L'échange de cette manche a-t-il lieu ? (au plus un par manche, décidé à graine égale)
func wants_exchange(round_index: int) -> bool:
	var r := RandomNumberGenerator.new()
	r.seed = hash([_seed, round_index, "exchange"])
	return r.randf() < 0.4


## Toutes les répliques (pour les tests).
static func all_lines() -> Array:
	var out: Array = ROUND + SPITE + TAUNT + HABIT + TO_NARRATOR + FROM_NARRATOR + [FALLBACK] \
		+ CHALLENGES + REVEAL_ETERNAL + STRIKE_ETERNAL + SPITE_ETERNAL + HABIT_ETERNAL + TAUNT_ETERNAL \
		+ TO_NARRATOR_ETERNAL + FROM_NARRATOR_ETERNAL
	for d in [REVEAL, STRIKE]:
		for k in d:
			out.append_array(d[k])
	return out


static func render(line: Dictionary, extra: Dictionary, plural := true) -> String:
	var slots := {"menace": "cette menace", "menaces": "plusieurs menaces", "actions": "quelques actions",
		"pouvoir": "les mêmes gestes", "narrateur": AiConfig.NARRATOR_NAME, "adversaire": AiConfig.ADVERSARY_NAME,
		"espece": "la vie"}
	slots.merge(extra, true)
	var tpl := Procedural.apply_agreement(str(line["t"]), {"espece": plural})
	return Procedural.polish(Procedural.contract(" " + tpl.format(slots)).strip_edges())


## Choisit une réplique permise à cette époque, propre, et (avec une mémoire de variété) pas dite
## récemment, en commençant par la moins récemment utilisée. Avec une mémoire et rien de neuf à dire,
## il se tait ({}), plutôt que de se répéter.
func _say(kind: String, pool: Array, epoch: int, extra: Dictionary, plural := true) -> Dictionary:
	_count += 1
	rng.seed = hash([_seed, _count, kind])
	var family := "adversary:%s:%s:%d" % [tone, kind, pool.size()]
	var order: Array = range(pool.size())
	if variety != null:
		order = variety.order(family, pool.size(), rng)
	else:
		var start := rng.randi() % maxi(1, pool.size())
		order = order.slice(start) + order.slice(0, start)
	for i in order:
		var l: Dictionary = pool[i]
		if not Epoch.allows(l, epoch):
			continue
		var text := render(l, extra, plural)
		if not Epoch.is_clean(text, epoch) or (variety != null and variety.seen(text)):
			continue
		if variety != null:
			variety.remember(text)
			variety.used(family, i)
		return {"text": text, "kind": kind, "speaker": AiConfig.ADVERSARY_NAME}
	if variety != null:
		return {}
	return {"text": render(FALLBACK, extra), "kind": kind, "speaker": AiConfig.ADVERSARY_NAME}


static func _title(threat: Variant) -> String:
	var t := str(threat.get("title", "")) if threat is Dictionary else ""
	return t if t != "" else "Cette menace"
