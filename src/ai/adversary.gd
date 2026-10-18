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
func round_taunt(rd: Dictionary, actions: int, epoch: int) -> Dictionary:
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
	match kind:
		"reveal":
			line = _say("reveal", REVEAL.get(reason, REVEAL["max_damage"]), epoch, extra)
		"strike":
			line = _say("strike", STRIKE.get(reason, []) + STRIKE[""], epoch, extra)
		_:
			line = _say("taunt", TAUNT, epoch, extra)
	line["reason"] = reason
	return line


## Dépit : une menace vient d'être contrée.
func spite_line(threat: Dictionary, epoch: int) -> Dictionary:
	return _say("spite", SPITE, epoch, {"menace": _title(threat)})


## Satisfaction quand une menace frappe, sans coup de la stratégie pour le dire (repli).
func strike_line(threat: Dictionary, epoch: int) -> Dictionary:
	return _say("strike", STRIKE[""], epoch, {"menace": _title(threat)})


## Remarque sur une habitude apprise (samael_learned) : {power|counter|kind, count?}.
func habit_line(habit: Dictionary, epoch: int) -> Dictionary:
	var power := str(habit.get("power", habit.get("counter", habit.get("kind", ""))))
	return _say("habit", HABIT, epoch, {"pouvoir": POWERS.get(power, "les mêmes gestes")})


## Échange : l'adversaire répond au narrateur (to_narrator) ou le narrateur à l'adversaire.
func exchange_line(to_narrator: bool, epoch: int) -> Dictionary:
	var line := _say("exchange", TO_NARRATOR if to_narrator else FROM_NARRATOR, epoch, {})
	line["speaker"] = AiConfig.ADVERSARY_NAME if to_narrator else AiConfig.NARRATOR_NAME
	return line


## L'échange de cette manche a-t-il lieu ? (au plus un par manche, décidé à graine égale)
func wants_exchange(round_index: int) -> bool:
	var r := RandomNumberGenerator.new()
	r.seed = hash([_seed, round_index, "exchange"])
	return r.randf() < 0.4


## Toutes les répliques (pour les tests).
static func all_lines() -> Array:
	var out: Array = ROUND + SPITE + TAUNT + HABIT + TO_NARRATOR + FROM_NARRATOR + [FALLBACK]
	for d in [REVEAL, STRIKE]:
		for k in d:
			out.append_array(d[k])
	return out


static func render(line: Dictionary, extra: Dictionary) -> String:
	var slots := {"menace": "cette menace", "menaces": "plusieurs menaces", "actions": "quelques actions",
		"pouvoir": "les mêmes gestes", "narrateur": AiConfig.NARRATOR_NAME, "adversaire": AiConfig.ADVERSARY_NAME}
	slots.merge(extra, true)
	return Procedural.polish(Procedural.contract(" " + str(line["t"]).format(slots)).strip_edges())


func _say(kind: String, pool: Array, epoch: int, extra: Dictionary) -> Dictionary:
	_count += 1
	rng.seed = hash([_seed, _count, kind])
	var allowed := pool.filter(func(l: Dictionary) -> bool: return Epoch.allows(l, epoch))
	if not allowed.is_empty():
		var start := rng.randi() % allowed.size()
		for i in allowed.size():
			var text := render(allowed[(start + i) % allowed.size()], extra)
			if Epoch.is_clean(text, epoch):
				return {"text": text, "kind": kind, "speaker": AiConfig.ADVERSARY_NAME}
	return {"text": render(FALLBACK, extra), "kind": kind, "speaker": AiConfig.ADVERSARY_NAME}


static func _title(threat: Variant) -> String:
	var t := str(threat.get("title", "")) if threat is Dictionary else ""
	return t if t != "" else "Cette menace"
