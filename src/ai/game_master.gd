extends RefCounted
## Le narrateur maître du jeu : de temps en temps, il pousse Dieu à trancher (« dilemme »).
##
## Le CODE décide : quels déclencheurs (alertes de la parcelle, grands événements, prières), quand
## (au plus un dilemme toutes les min_interval secondes, jamais deux à la fois) et quelles options
## (règles par déclencheur, actions divines valides du contrat). Le LLM ne fait que rédiger titre,
## texte, libellés et indices (narrator.gd) ; ce fichier fournit un repli procédural complet.
##
## Dilemme (contrat avec l'interface) :
## {id: int, title, text (2 à 4 phrases), options: [{label, hint, action}], timeout_s: float, speaker,
##  trigger: String, species_id: int}
## action : {type, region: Vector2i, species_id: int, radius: int} ou {} pour « Ne rien faire ».
## Toujours 2 à 4 options, dont exactement une « Ne rien faire ».
##
## Déclencheur : {kind (voir TRIGGERS), species_id, species_name, rival_id, rival_name, region,
##  severity, summary, hot (crise climatique), situation (prière)}.

const Procedural := preload("res://src/ai/procedural_narrator.gd")
const AiConfig := preload("res://src/ai/ai_config.gd")

const TRIGGERS := ["meteor_decision", "first_sapient", "first_city", "war", "climate_crisis", "strong_ai",
	"species_collapse", "famine", "alert", "prayer"]
## Déclencheurs qui ne se présentent qu'une fois par partie.
const ONCE := ["meteor_decision", "first_sapient", "first_city", "strong_ai"]
## Priorité quand plusieurs déclencheurs attendent (le plus grand d'abord).
const PRIORITY := {
	"meteor_decision": 10, "first_sapient": 9, "strong_ai": 9, "first_city": 8, "climate_crisis": 7,
	"war": 6, "species_collapse": 6, "prayer": 5, "famine": 5, "alert": 3,
}
## Actions divines du contrat (docs/ARCHITECTURE.md).
const ACTION_TYPES := ["meteor", "extinct", "save", "bless", "plague", "uplift", "flood", "ice_age", "spawn_species"]
const NOTHING_LABEL := "Ne rien faire"
## Rayon (en cellules) par type d'action, à l'échelle de la parcelle.
const RADIUS := {"meteor": 8, "ice_age": 20, "flood": 4, "plague": 4, "bless": 4, "save": 6, "uplift": 4, "extinct": 4, "spawn_species": 2}
## Un même déclencheur répétable (même genre, même espèce) n'est pas reproposé avant ce délai (s).
const REPEAT_COOLDOWN := 600.0
## Un déclencheur en attente est oublié au bout de ce délai (s) au-delà de min_interval, sauf la
## décision du météore (il attend toujours son tour).
const QUEUE_MAX_AGE := 120.0

const TITLES := {
	"meteor_decision": ["La pierre au-dessus du monde", "Le dernier jour du Crétacé ?"],
	"first_sapient": ["Une pensée s'éveille", "Ils lèvent les yeux"],
	"first_city": ["La première ville", "Des murs sur ta parcelle"],
	"war": ["Le sang appelle le sang", "La guerre"],
	"climate_crisis": ["La fièvre du monde", "Le climat bascule"],
	"strong_ai": ["Une autre intelligence", "La machine qui pense"],
	"species_collapse": ["Une lignée vacille", "Le dernier troupeau ?"],
	"famine": ["La faim", "Les greniers vides"],
	"alert": ["Un signe sur ta parcelle", "Quelque chose ne va pas"],
	"prayer": ["Une prière monte vers toi", "On t'appelle"],
}
## Texte : 2 à 4 phrases. Emplacements : {espece} (accord espece), {rival}, {terre}, {resume}, {ere}.
const TEXTS := {
	"meteor_decision": [
		"Une pierre de dix kilomètres croise au-dessus du monde, et les géants ne lèvent même pas la tête. Dans la vraie histoire, elle tombe, et les petits mammifères héritent de la Terre. À toi de voir si l'histoire doit être vraie.",
		"Je connais la suite, enfin, je crois la connaître : la pierre tombe, les dinosaures s'éteignent, l'herbe et les mammifères prennent le monde. Mais rien ne t'oblige à suivre mes livres.",
	],
	"first_sapient": [
		"{espece} [espece:vient|viennent] de penser pour la première fois. [espece:Elle ignore|Ils ignorent] encore tout de toi, mais ça ne durera pas. Que fais-tu de cette étincelle ?",
		"Une pensée est née chez {espece}. Je n'ai jamais assisté à ça d'aussi près, et je te soupçonne d'être aussi curieux que moi.",
	],
	"first_city": [
		"Sur {terre}, {espece} [espece:a bâti|ont bâti] une ville. Des milliers de vies serrées, des greniers, des querelles, et déjà des temples. Tu laisses grandir ?",
		"La première ville s'élève sur {terre}. C'est beau, c'est fragile, et ça ne s'arrêtera plus tout seul.",
	],
	"war": [
		"{resume}. Le sang coule, et chaque camp prie pour ta faveur. Tu choisis un camp, ou tu regardes ?",
		"La guerre a éclaté : {resume}. Je n'aime pas écrire ces pages, mais je les écrirai quoi que tu fasses.",
	],
	"climate_crisis": [
		"Le climat de {terre} s'emballe. Les bêtes migrent, les plantes souffrent, et ceux qui pensent commencent à avoir peur. Tu interviens ?",
		"La fièvre gagne le monde, et {terre} la sent en premier. Je note les degrés ; toi, tu peux faire mieux que noter.",
	],
	"strong_ai": [
		"{espece} [espece:vient|viennent] d'éveiller une intelligence qui n'est pas la [espece:sienne|leur]. Elle pense plus vite que tous les scribes réunis, moi compris. Que décides-tu ?",
		"Une machine pense, quelque part chez {espece}. Pour la première fois, je ne suis plus le seul à tout retenir. Ça m'inquiète un peu, je l'avoue.",
	],
	"species_collapse": [
		"{espece} [espece:s'effondre|s'effondrent] sur {terre}. Encore quelques saisons comme celle-ci, et je devrai écrire [espece:son|leur] épitaphe. Tu tends la main ?",
		"{espece} [espece:se fait|se font] de plus en plus [espece:rare|rares] sur {terre}. La nature fait son œuvre, ou c'est à toi de la faire ?",
	],
	"famine": [
		"La faim s'installe sur {terre}. {espece} [espece:gratte|grattent] la terre et [espece:ne trouve|ne trouvent] rien. Tu nourris, tu éprouves, ou tu laisses faire ?",
	],
	"alert": [
		"Quelque chose se dérègle sur {terre} : {resume}. Ce n'est peut-être rien. Ce n'est peut-être pas rien.",
	],
	"prayer": [
		"{espece} [espece:t'adresse|t'adressent] une prière. Je la transmets mot pour mot, comme toujours. Que réponds-tu ?",
		"Une prière monte de chez {espece}. On t'a déjà prié, mais rarement avec autant d'espoir.",
	],
}
const LABELS := {
	"meteor": "Lancer le météore", "bless": "Bénir {cible}", "plague": "Envoyer la peste sur {cible}",
	"save": "Protéger {cible}", "uplift": "Éveiller {cible}", "flood": "Ouvrir les eaux", "ice_age": "Refroidir le monde",
	"extinct": "Effacer {cible}", "spawn_species": "Façonner une espèce nouvelle",
}
const HINTS := {
	"meteor": "Tout peut recommencer… ou finir.", "bless": "Ils prospéreront, sans doute aux dépens d'autres.",
	"plague": "Les plus faibles tomberont ; les survivants s'endurciront peut-être.", "save": "Ils survivront. Rien n'est gratuit.",
	"uplift": "Une autre pensée s'éveillera. Rivale ou alliée ?", "flood": "Les eaux lavent tout, y compris ce que tu aimais.",
	"ice_age": "Le froid calme la fièvre du monde, et pas seulement elle.", "extinct": "Ce qui est effacé ne revient pas.",
	"spawn_species": "Une vie nouvelle, des équilibres anciens bousculés.", "": "Le monde suivra sa pente. C'est aussi un choix.",
}
## Ce que le narrateur dit du choix, au moment où il est fait, puis plus tard (mémoire).
const CHOICE_NOW := {
	"meteor": "Tu as lancé la pierre.", "bless": "Tu as béni {cible}.", "plague": "Tu as frappé {cible} de la peste.",
	"save": "Tu as protégé {cible}.", "uplift": "Tu as éveillé {cible}.", "flood": "Tu as ouvert les eaux.",
	"ice_age": "Tu as appelé le froid.", "extinct": "Tu as effacé {cible}.", "spawn_species": "Tu as façonné une vie nouvelle.",
	"": "Tu as choisi de ne rien faire. C'est noté, et ce n'est pas rien.",
}
const CHOICE_PAST := {
	"meteor": "tu avais lancé la pierre", "bless": "tu avais béni {cible}", "plague": "tu avais frappé {cible} de la peste",
	"save": "tu avais protégé {cible}", "uplift": "tu avais éveillé {cible}", "flood": "tu avais ouvert les eaux",
	"ice_age": "tu avais appelé le froid", "extinct": "tu avais effacé {cible}", "spawn_species": "tu avais façonné une vie nouvelle",
	"": "tu avais laissé faire",
}
const TIMEOUT_TEXT := "Tu n'as rien répondu : le monde a décidé seul. Je le note aussi."

var min_interval := 180.0
var timeout_s := 45.0
## Délai (s) avant de proposer la décision du météore en début de partie.
var meteor_delay := 5.0
## Choix passés, du plus ancien au plus récent : [{id, trigger, species_id, species_name, action_type,
## label, era, year, timed_out}]. Nourrit la suite du récit.
var choices: Array[Dictionary] = []
## Dilemme ouvert ({} sinon) ; deadline < 0 tant que l'interface ne l'a pas affiché.
var active := {}

var rng := RandomNumberGenerator.new()
var _seed := 0
var _clock := 0.0
var _last_open := -INF
var _deadline := -1.0
var _next_id := 1
var _queue: Array[Dictionary] = []
var _fired := {}


func _init(p_seed: int = -1) -> void:
	if p_seed >= 0:
		_seed = p_seed
	else:
		rng.randomize()
		_seed = rng.randi()


# ---------------------------------------------------------------------------
# Déclencheurs (décidés par le code)
# ---------------------------------------------------------------------------

## Déclencheur pour un événement de la simulation (WorldSim, ParcelSim ou moment de parcelle), ou {}.
static func trigger_from_event(event: Dictionary, ctx: Dictionary) -> Dictionary:
	var t := str(event.get("type", "")).trim_prefix("divine_")
	var sid := int(event.get("species_id", -1))
	var summary := str(event.get("summary", ""))
	match t:
		"sapience":
			return _trigger("first_sapient", ctx, sid, summary)
		"war":
			var trig := _trigger("war", ctx, sid, summary)
			var foe := _foe_from_summary(summary, ctx, sid)
			if not foe.is_empty():
				trig["rival_id"] = int(foe["id"])
				trig["rival_name"] = str(foe["name"])
			return trig
		"discovery":
			if summary.contains("IA "):
				return _trigger("strong_ai", ctx, sid, summary)
		"volcanism":
			# Un supervolcan obscurcit le ciel : le monde se refroidit.
			return _trigger("climate_crisis", ctx, sid, summary, {"hot": false})
		"land_use", "parcel_land_use":
			if str(event.get("land_use", "")) == "city" and bool(event.get("first", false)):
				return _trigger("first_city", ctx, _sapient_on_parcel(ctx), summary)
		"heat", "cold", "parcel_heat", "parcel_cold":
			if absf(float(event.get("delta_c", 0.0))) >= 8.0:
				return _trigger("climate_crisis", ctx, -1, summary, {"hot": t.ends_with("heat")})
	return {}


## Alerte de GameState.parcel.alerts ({kind, species_id, severity 0..1, summary}), ou {} si trop faible.
static func trigger_from_alert(alert: Dictionary, ctx: Dictionary) -> Dictionary:
	var severity := float(alert.get("severity", 0.0))
	if severity < 0.5:
		return {}
	var kind := str(alert.get("kind", "")).to_lower()
	var sid := int(alert.get("species_id", -1))
	var summary := str(alert.get("summary", ""))
	var extra := {"severity": severity, "alert_kind": kind}
	for k in ["collapse", "decline", "crash", "extinct", "endanger", "population"]:
		if kind.contains(k) and sid >= 0:
			return _trigger("species_collapse", ctx, sid, summary, extra)
	for k in ["heat", "warm", "hot", "cold", "freez", "ice", "climate", "temperature", "drought"]:
		if kind.contains(k):
			extra["hot"] = not (kind.contains("cold") or kind.contains("freez") or kind.contains("ice"))
			return _trigger("climate_crisis", ctx, sid, summary, extra)
	for k in ["famine", "hunger", "starv", "overpop", "food"]:
		if kind.contains(k):
			return _trigger("famine", ctx, sid if sid >= 0 else _sapient_on_parcel(ctx), summary, extra)
	return _trigger("alert", ctx, sid, summary, extra)


## Prière d'un peuple (Narrator.generate_prayer) : species {id, name}, situation {type, summary, enemy_id…}.
static func trigger_from_prayer(species: Dictionary, situation: Dictionary, ctx: Dictionary) -> Dictionary:
	var trig := _trigger("prayer", ctx, int(species.get("id", -1)), str(situation.get("summary", "")))
	if str(trig["species_name"]) == "":
		trig["species_name"] = str(species.get("name", ""))
	trig["situation"] = situation.duplicate()
	return trig


## Déclencheur « la pierre au-dessus du monde » (fin du Crétacé).
static func meteor_trigger(ctx: Dictionary) -> Dictionary:
	return _trigger("meteor_decision", ctx, -1, "")


## La fin du Crétacé : proposer de lancer le météore ? (tant qu'il n'est pas tombé)
static func meteor_due(ctx: Dictionary, elapsed: float, delay: float) -> bool:
	if elapsed < delay or Procedural.era_key(ctx.get("era", "")) != "Mésozoïque":
		return false
	for act in ctx.get("divine", []):
		if str(act.get("type", "")) == "meteor":
			return false
	return true


static func _trigger(kind: String, ctx: Dictionary, sid: int, summary: String, extra: Dictionary = {}) -> Dictionary:
	var trig := {"kind": kind, "species_id": sid, "species_name": _name_of(ctx, sid), "summary": summary,
		"region": ctx.get("snapshot", {}).get("cell", Vector2i.ZERO)}
	trig.merge(extra, true)
	return trig


# ---------------------------------------------------------------------------
# Cadence : au plus un dilemme toutes les min_interval secondes, jamais deux à la fois
# ---------------------------------------------------------------------------

## Propose un déclencheur ; il attend son tour si un dilemme est ouvert ou trop récent.
## Renvoie false s'il est écarté (déjà vu, déclencheur inconnu…).
func consider(trigger: Dictionary) -> bool:
	if trigger.is_empty() or not str(trigger.get("kind", "")) in TRIGGERS:
		return false
	var key := _key(trigger)
	if _fired.has(key) and (str(trigger["kind"]) in ONCE or _clock - float(_fired[key]) < REPEAT_COOLDOWN):
		return false
	for q in _queue:
		if _key(q) == key:
			return false
	var t := trigger.duplicate()
	t["_t"] = _clock
	_queue.append(t)
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(PRIORITY.get(a["kind"], 0)) > int(PRIORITY.get(b["kind"], 0)))
	if _queue.size() > 4:
		_queue.resize(4)
	return true


func can_open() -> bool:
	return active.is_empty() and _clock - _last_open >= min_interval


## Avance l'horloge. Renvoie {"open": trigger} quand un dilemme peut s'ouvrir (le narrateur le construit
## avec open_dilemma), {"timeout": {id, option_index}} quand le délai de réponse est écoulé, sinon {}.
func tick(delta: float) -> Dictionary:
	_clock += delta
	if not active.is_empty():
		if _deadline >= 0.0 and _clock >= _deadline:
			return {"timeout": {"id": int(active["id"]), "option_index": nothing_index(active)}}
		return {}
	var kept: Array[Dictionary] = []
	var max_age := min_interval + QUEUE_MAX_AGE
	for q in _queue:
		if str(q["kind"]) == "meteor_decision" or _clock - float(q["_t"]) <= max_age:
			kept.append(q)
	_queue = kept
	if _queue.is_empty() or not can_open():
		return {}
	return {"open": _queue.pop_front()}


## Construit et ouvre un dilemme pour ce déclencheur (procédural) ; {} si impossible.
func open_dilemma(trigger: Dictionary, ctx: Dictionary) -> Dictionary:
	if not active.is_empty():
		return {}
	var d := build(trigger, ctx)
	if validate(d) != "":
		return {}
	_fired[_key(trigger)] = _clock
	_last_open = _clock
	_deadline = -1.0
	active = d
	return d


## L'interface affiche le dilemme : le délai de réponse commence.
func mark_shown(id: int) -> void:
	if not active.is_empty() and int(active["id"]) == id and _deadline < 0.0:
		_deadline = _clock + float(active.get("timeout_s", timeout_s))


## Applique le choix au registre. Renvoie {ok, action, text (phrase du narrateur), record} ; ok = false
## si l'identifiant ou l'option sont invalides. L'appelant applique l'action (GameState).
func resolve(id: int, option_index: int, timed_out := false, ctx: Dictionary = {}) -> Dictionary:
	if active.is_empty() or int(active["id"]) != id:
		return {"ok": false}
	var options: Array = active["options"]
	if option_index < 0 or option_index >= options.size():
		return {"ok": false}
	var opt: Dictionary = options[option_index]
	var action: Dictionary = opt["action"]
	var t := str(action.get("type", ""))
	var target_id := int(action.get("species_id", -1)) if not action.is_empty() else int(active.get("species_id", -1))
	var target_name := _name_of(ctx, target_id) if target_id >= 0 else ""
	if target_name == "" and target_id == int(active.get("species_id", -2)):
		target_name = str(active.get("species_name", ""))
	var record := {
		"id": id, "trigger": str(active.get("trigger", "")), "species_id": target_id, "species_name": target_name,
		"action_type": t, "label": str(opt["label"]), "era": str(ctx.get("era", "")), "year": ctx.get("year", null),
		"timed_out": timed_out,
	}
	choices.append(record)
	var text := TIMEOUT_TEXT if timed_out else _sentence(CHOICE_NOW.get(t, CHOICE_NOW[""]), target_name) + " Je l'inscris au registre."
	active = {}
	_deadline = -1.0
	return {"ok": true, "action": action.duplicate(), "text": Procedural.polish(text), "record": record}


static func nothing_index(d: Dictionary) -> int:
	var options: Array = d.get("options", [])
	for i in options.size():
		if (options[i]["action"] as Dictionary).is_empty():
			return i
	return -1


# ---------------------------------------------------------------------------
# Construction (règles + repli procédural)
# ---------------------------------------------------------------------------

## Dilemme complet pour un déclencheur (déterministe : graine × numéro du dilemme).
func build(trigger: Dictionary, ctx: Dictionary) -> Dictionary:
	var id := _next_id
	_next_id += 1
	rng.seed = hash([_seed, id, str(trigger.get("kind", ""))])
	var kind := str(trigger.get("kind", "alert"))
	var region: Vector2i = trigger.get("region", Vector2i.ZERO) if trigger.get("region") is Vector2i else Vector2i.ZERO
	var options := []
	for spec in option_specs(trigger, ctx):
		var a := {}
		if str(spec[0]) != "":
			a = {"type": str(spec[0]), "region": region, "species_id": int(spec[1]), "radius": int(RADIUS.get(spec[0], 4))}
		options.append({
			"label": _label(str(spec[0]), _name_of(ctx, int(spec[1])) if int(spec[1]) >= 0 else str(trigger.get("species_name", ""))),
			"hint": HINTS.get(str(spec[0]), HINTS[""]), "action": a,
		})
	var name := str(trigger.get("species_name", ""))
	var phrase := Procedural.species_phrase(name) if name != "" else {"text": "les vivants", "plural": true}
	var texts: Array = TEXTS.get(kind, TEXTS["alert"])
	var tpl: String = texts[rng.randi() % texts.size()]
	tpl = Procedural.apply_agreement(tpl, {"espece": phrase["plural"]})
	var resume := Procedural.clean_summary(str(trigger.get("summary", "")))
	var text := tpl.format({
		"espece": phrase["text"], "rival": str(trigger.get("rival_name", "l'ennemi")),
		"terre": "ta parcelle", "resume": resume if resume != "" else "rien de clair, et c'est bien ce qui m'inquiète",
		"ere": Procedural.era_with_article(ctx.get("era", "")),
	})
	var memory := callback(trigger, ctx)
	if memory != "" and _sentences(text) < 4:
		text += " Souviens-toi : %s." % memory
	var titles: Array = TITLES.get(kind, TITLES["alert"])
	return {
		"id": id, "title": str(titles[rng.randi() % titles.size()]), "text": Procedural.polish(Procedural.contract(text)),
		"options": options, "timeout_s": timeout_s, "speaker": AiConfig.NARRATOR_NAME,
		"trigger": kind, "species_id": int(trigger.get("species_id", -1)),
	}


## Options par règles : [[type d'action ("" = ne rien faire), species_id], ...], 2 à 4, « rien » en dernier.
static func option_specs(trigger: Dictionary, ctx: Dictionary) -> Array:
	var sid := int(trigger.get("species_id", -1))
	var out := []
	match str(trigger.get("kind", "")):
		"meteor_decision":
			out = [["meteor", -1], ["bless", _top_species(ctx, ["dinosaure", "ptérosaure"])]]
		"first_sapient":
			out = [["bless", sid], ["plague", sid]]
			var rival := _rival(ctx, sid)
			if rival >= 0:
				out.append(["uplift", rival])
		"first_city":
			out = [["bless", sid], ["flood", -1], ["plague", sid]]
		"war":
			var foe := int(trigger.get("rival_id", -1))
			out = [["save", foe if foe >= 0 else sid], ["plague", sid]]
		"climate_crisis":
			if bool(trigger.get("hot", true)):
				out = [["ice_age", -1], ["save", sid if sid >= 0 else _sapient_on_parcel(ctx)]]
			else:
				out = [["bless", sid if sid >= 0 else _sapient_on_parcel(ctx)]]
		"strong_ai":
			out = [["bless", sid], ["plague", sid], ["meteor", -1]]
		"species_collapse":
			out = [["save", sid]]
			var predator := _predator_of(ctx, sid)
			out.append(["plague", predator] if predator >= 0 else ["bless", sid])
		"famine":
			out = [["bless", sid], ["plague", sid]]
		"prayer":
			for c in Procedural.prayer_choices({"id": sid}, trigger.get("situation", {})):
				var a: Dictionary = c["action"]
				if not a.is_empty() and str(a.get("type", "")) in ACTION_TYPES:
					out.append([str(a["type"]), int(a.get("species_id", sid))])
		_:
			if sid >= 0:
				out = [["save", sid]]
			else:
				out = [["bless", _sapient_on_parcel(ctx)]]
	# Une action qui vise une espèce n'a pas de sens sans espèce.
	out = out.filter(func(s: Array) -> bool: return not (str(s[0]) in ["save", "plague", "uplift", "extinct"] and int(s[1]) < 0))
	if out.is_empty():
		out = [["bless", -1]]
	out = out.slice(0, 3)
	out.append(["", -1])
	return out


## Une phrase de mémoire si un choix passé concerne cette espèce ou ses ancêtres ("" sinon).
static func callback(trigger: Dictionary, ctx: Dictionary) -> String:
	var sid := int(trigger.get("species_id", -1))
	if sid < 0:
		return ""
	var lineage := _ancestors(ctx, sid)
	var past: Array = ctx.get("choices", [])
	for i in range(past.size() - 1, -1, -1):
		var c: Dictionary = past[i]
		var cid := int(c.get("species_id", -1))
		if cid == sid:
			return _sentence(CHOICE_PAST.get(str(c.get("action_type", "")), CHOICE_PAST[""]), str(c.get("species_name", ""))).trim_suffix(".")
		if cid in lineage:
			return _sentence(CHOICE_PAST.get(str(c.get("action_type", "")), CHOICE_PAST[""]), "leurs ancêtres, " + Procedural.species_phrase(str(c.get("species_name", "")))["text"]).trim_suffix(".")
	return ""


## Phrase de mémoire pour le fil continu (« Je n'oublie rien : au Mésozoïque, tu avais… »), ou "".
static func memory_line(record: Dictionary) -> String:
	var past := _sentence(CHOICE_PAST.get(str(record.get("action_type", "")), CHOICE_PAST[""]), str(record.get("species_name", "")))
	var when := ""
	if str(record.get("era", "")) != "":
		when = "à %s, " % Procedural.era_with_article(record["era"])
	return Procedural.polish(Procedural.contract("Je n'oublie rien : %s%s." % [when, past.trim_suffix(".")]))


## Le dilemme respecte-t-il le contrat ? "" si oui, sinon la raison.
static func validate(d: Dictionary) -> String:
	for k in ["id", "title", "text", "options", "timeout_s", "speaker"]:
		if not d.has(k):
			return "champ manquant : " + k
	if str(d["title"]).strip_edges() == "" or str(d["text"]).strip_edges() == "":
		return "titre ou texte vide"
	var options: Array = d["options"]
	if options.size() < 2 or options.size() > 4:
		return "%d options" % options.size()
	var empties := 0
	for o in options:
		if not (o is Dictionary and o.has("label") and o.has("hint") and o.get("action") is Dictionary):
			return "option mal formée : %s" % str(o)
		if str(o["label"]).strip_edges() == "" or str(o["label"]).contains("{"):
			return "libellé vide ou non rempli : %s" % str(o["label"])
		var a: Dictionary = o["action"]
		if a.is_empty():
			empties += 1
			continue
		if not str(a.get("type", "")) in ACTION_TYPES or not (a.get("region") is Vector2i) \
				or typeof(a.get("species_id")) != TYPE_INT or typeof(a.get("radius")) != TYPE_INT:
			return "action invalide : %s" % str(a)
	if empties != 1:
		return "%d options « ne rien faire »" % empties
	return ""


# ---------------------------------------------------------------------------
# Utilitaires
# ---------------------------------------------------------------------------

static func _label(action_type: String, target: String) -> String:
	if action_type == "":
		return NOTHING_LABEL
	var cible: String = Procedural.species_phrase(target)["text"] if target != "" else "les vivants"
	return Procedural.contract(" " + str(LABELS.get(action_type, action_type)).format({"cible": cible})).strip_edges()


static func _sentence(tpl: String, target: String) -> String:
	var cible: String = Procedural.species_phrase(target)["text"] if target != "" else "les vivants"
	if target.begins_with("leurs "):
		cible = target
	return Procedural.contract(" " + tpl.format({"cible": cible})).strip_edges()


static func _sentences(t: String) -> int:
	var n := 0
	for i in t.length():
		if t[i] in [".", "!", "?", "…"] and (i + 1 == t.length() or t[i + 1] == " "):
			n += 1
	return n


static func _key(trigger: Dictionary) -> String:
	var kind := str(trigger.get("kind", ""))
	return kind if kind in ONCE else "%s:%d" % [kind, int(trigger.get("species_id", -1))]


static func _species_by_id(ctx: Dictionary) -> Dictionary:
	var out := {}
	for s in ctx.get("species", []):
		out[int(s.get("id", -1))] = s
	return out


static func _name_of(ctx: Dictionary, sid: int) -> String:
	if sid < 0:
		return ""
	var s: Variant = _species_by_id(ctx).get(sid, null)
	if s is Dictionary:
		return str(s.get("name", ""))
	for f in ctx.get("snapshot", {}).get("fauna", []):
		if int(f.get("species_id", -1)) == sid:
			return str(f.get("name", ""))
	return ""


static func _sapient_on_parcel(ctx: Dictionary) -> int:
	for f in ctx.get("snapshot", {}).get("fauna", []):
		if str(f.get("role", "")) == "sapient":
			return int(f.get("species_id", -1))
	for s in ctx.get("species", []):
		if bool(s.get("sapient", false)) and bool(s.get("alive", true)):
			return int(s.get("id", -1))
	return -1


## Espèce non intelligente la plus capable de penser à son tour (rivale potentielle), ou -1.
static func _rival(ctx: Dictionary, sid: int) -> int:
	var best := -1
	var best_iq := -1.0
	for s in ctx.get("species", []):
		var id := int(s.get("id", -1))
		if id != sid and bool(s.get("alive", true)) and not bool(s.get("sapient", false)) and float(s.get("intelligence", 0.0)) > best_iq:
			best = id
			best_iq = float(s.get("intelligence", 0.0))
	return best


## Prédateur de la parcelle (autre espèce carnivore), ou -1.
static func _predator_of(ctx: Dictionary, sid: int) -> int:
	for f in ctx.get("snapshot", {}).get("fauna", []):
		if int(f.get("species_id", -1)) != sid and str(f.get("role", "")) == "carnivore":
			return int(f.get("species_id", -1))
	return -1


## Espèce la plus visible de la parcelle parmi ces clades, ou -1.
static func _top_species(ctx: Dictionary, clades: Array) -> int:
	var by_id := _species_by_id(ctx)
	var best := -1
	var best_count := -1
	for f in ctx.get("snapshot", {}).get("fauna", []):
		var id := int(f.get("species_id", -1))
		var clade := str(f.get("clade", by_id.get(id, {}).get("clade", "")))
		if clade in clades and int(f.get("count", 0)) > best_count:
			best = id
			best_count = int(f.get("count", 0))
	return best


static func _ancestors(ctx: Dictionary, sid: int) -> Array:
	var by_id := _species_by_id(ctx)
	var out := []
	var cur: Variant = by_id.get(sid, {}).get("parent", -1)
	while typeof(cur) in [TYPE_INT, TYPE_FLOAT] and int(cur) >= 0 and not int(cur) in out and out.size() < 64:
		out.append(int(cur))
		cur = by_id.get(int(cur), {}).get("parent", -1)
	return out


## Adversaire nommé dans un résumé de guerre (« les X affrontent les Y »), ou {}.
static func _foe_from_summary(summary: String, ctx: Dictionary, sid: int) -> Dictionary:
	for s in ctx.get("species", []):
		if int(s.get("id", -1)) != sid and str(s.get("name", "")) != "" and summary.contains(str(s["name"])):
			return s
	return {}
