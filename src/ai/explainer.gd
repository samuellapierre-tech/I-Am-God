extends RefCounted
## Le narrateur explique (docs/GENESE.md) : il lit les statistiques de la planète, reconnaît les
## phénomènes en cours (l'oxygène monte, l'ozone se forme, un continent se fracture, une espèce décline,
## l'effet de serre s'emballe, le Soleil vieillit…) et les explique avec des faits vrais (facts/phenomena.gd).
##
## Statistiques : la session Planète expose `planet_stats()` (et `planet_history`) ; leurs clés exactes ne
## sont pas encore figées, donc normalize() accepte plusieurs noms et unités. Clés normalisées :
## oxygen (fraction de l'air, 0..1), co2_ppm, methane, ozone (0..1, 1 = protection pleine),
## temperature_c (moyenne mondiale), sea_level_m, ice_cover (0..1), biomass, biodiversity (espèces vivantes),
## extinctions (récentes), sun_luminosity (1 = le Soleil actuel), year.
## Fonctions pures et déterministes à graine égale.

const Phenomena := preload("res://src/ai/facts/phenomena.gd")
const Procedural := preload("res://src/ai/procedural_narrator.gd")
const Epoch := preload("res://src/ai/epoch.gd")

## Noms acceptés pour chaque statistique (le premier présent l'emporte).
const SYNONYMS := {
	"oxygen": ["oxygen", "o2", "oxygen_fraction", "oxygen_pct", "o2_percent", "o2_pct"],
	"co2_ppm": ["co2_ppm", "co2", "carbon_dioxide", "co2_pp"],
	"methane": ["methane", "methane_ppm", "ch4"],
	"ozone": ["ozone", "ozone_layer", "o3", "ozone_shield"],
	"temperature_c": ["temperature_c", "mean_temperature_c", "global_temperature_c", "temp_c", "temperature"],
	"sea_level_m": ["sea_level_m", "sea_level"],
	"ice_cover": ["ice_cover", "ice_fraction", "ice"],
	"biomass": ["biomass", "total_biomass"],
	"biodiversity": ["biodiversity", "species_alive", "species_count", "alive_species"],
	"extinctions": ["extinctions_recent", "recent_extinctions", "extinctions"],
	"sun_luminosity": ["sun_luminosity", "solar_luminosity", "luminosity", "sun"],
	"year": ["year", "time"],
}
## Seuils : l'ozone protège les terres au-delà de OZONE_SHIELD ; l'oxygène suffit aux animaux au-delà de
## OXYGEN_ANIMALS (fraction de l'air, ~10 % de l'actuel sur la Terre, donc 0,02).
const OZONE_SHIELD := 0.5
const OXYGEN_ANIMALS := 0.02
## Types d'événements de la simulation -> phénomènes à expliquer (tolérant : sous-chaînes).
const EVENT_PHENOMENA := {
	"oxygen": ["oxygen_rise"], "ozone": ["ozone", "land_colonization"], "snowball": ["ice_age"], "thaw": ["carbon_cycle"],
	"traps": ["greenhouse", "mass_extinction"], "volcan": ["greenhouse"], "ice_age": ["ice_age"], "rift": ["continental_split"],
	"split": ["continental_split"], "drift": ["plate_tectonics"], "collision": ["plate_tectonics", "continental_split"],
	"island": ["island_speciation"], "isolation": ["island_speciation"], "vicariance": ["continental_split"],
	"speciation": ["natural_selection"], "radiation": ["adaptive_radiation"], "clade": ["multicellularity"],
	"sapience": ["sapience"], "extinction": ["decline_competition"], "end_of_times": ["sun_aging"],
	"sea_level": ["sea_level"], "land_bridge": ["sea_level"], "greenhouse": ["greenhouse"], "warming": ["greenhouse"],
	"impact": ["mass_extinction"], "meteor": ["mass_extinction"], "eukaryote": ["endosymbiosis"],
}
## Commentaires chiffrés des statistiques. {valeur} {avant} {duree} {sens}.
const STAT_TEMPLATES := {
	"oxygen": ["L'oxygène forme maintenant {valeur} de l'air ; il en formait {avant} il y a {duree}.", "Je mesure {valeur} d'oxygène dans l'air, contre {avant} il y a {duree}."],
	"co2_ppm": ["Le dioxyde de carbone de l'air est passé de {avant} à {valeur} en {duree}.", "L'air contient {valeur} de dioxyde de carbone ; il y a {duree}, il en contenait {avant}."],
	"ozone": ["La couche d'ozone atteint {valeur} de la protection que connaît la Terre d'aujourd'hui, contre {avant} il y a {duree}."],
	"temperature_c": ["La planète a {sens} : {valeur} en moyenne, contre {avant} il y a {duree}.", "Il fait en moyenne {valeur} sur ce monde ; il y a {duree}, il faisait {avant}."],
	"sea_level_m": ["Le niveau des mers {sens} : il est à {valeur} de la référence, contre {avant} il y a {duree}."],
	"ice_cover": ["Les glaces couvrent {valeur} de la planète, contre {avant} il y a {duree}."],
	"biodiversity": ["Je compte {valeur} espèces vivantes ; il y a {duree}, il y en avait {avant}.", "{valeur} espèces vivent en ce moment sur ce monde, contre {avant} il y a {duree}."],
	"sun_luminosity": ["Le Soleil brille à {valeur} de son éclat actuel sur la Terre, contre {avant} il y a {duree}."],
}
## Changement relatif (ou absolu pour les fractions) à partir duquel une statistique mérite un commentaire.
const NOTABLE := {"oxygen": 0.01, "co2_ppm": 0.25, "ozone": 0.1, "temperature_c": 3.0, "sea_level_m": 20.0, "ice_cover": 0.1, "biodiversity": 0.3, "sun_luminosity": 0.03}
## Délai minimal (en lignes d'explication) avant de réexpliquer un même phénomène.
const PHENOMENON_MEMORY := 6

var rng := RandomNumberGenerator.new()
## Mémoire anti-répétition partagée (variety.gd) ; null = sans.
var variety: RefCounted = null
var _seed := 0
var _count := 0
var _recent_facts: Array[String] = []
var _recent_phenomena: Array[String] = []


func _init(p_seed: int = -1) -> void:
	if p_seed >= 0:
		_seed = p_seed
	else:
		rng.randomize()
		_seed = rng.randi()


## Statistiques normalisées à partir de ce qu'expose la planète (tolère noms et unités).
static func normalize(raw: Dictionary) -> Dictionary:
	var out := {}
	for key in SYNONYMS:
		for name in SYNONYMS[key]:
			if raw.has(name) and typeof(raw[name]) in [TYPE_INT, TYPE_FLOAT]:
				out[key] = float(raw[name])
				break
	# Unités : un pourcentage d'oxygène (21) devient une fraction (0,21) ; une couche d'ozone en unités
	# Dobson (~300 aujourd'hui sur la Terre) devient une fraction de la protection actuelle.
	if out.has("oxygen") and out["oxygen"] > 1.0:
		out["oxygen"] /= 100.0
	if out.has("ozone") and out["ozone"] > 1.5:
		out["ozone"] = out["ozone"] / 300.0
	if out.has("ice_cover") and out["ice_cover"] > 1.0:
		out["ice_cover"] /= 100.0
	return out


## Phénomènes à expliquer d'après l'évolution des statistiques (avant -> maintenant), par ordre d'intérêt.
static func detect(before: Dictionary, now: Dictionary) -> Array:
	var out := []
	var d := func(k: String) -> float: return float(now.get(k, 0.0)) - float(before.get(k, 0.0)) if now.has(k) and before.has(k) else 0.0
	if d.call("oxygen") >= 0.005 or (now.get("oxygen", 0.0) >= OXYGEN_ANIMALS and before.get("oxygen", 0.0) < OXYGEN_ANIMALS and before.has("oxygen")):
		out.append("oxygen_rise")
	if now.has("ozone") and before.has("ozone"):
		if now["ozone"] >= OZONE_SHIELD and before["ozone"] < OZONE_SHIELD:
			out.append("land_colonization")
			out.append("ozone")
		elif d.call("ozone") >= 0.08:
			out.append("ozone")
	if d.call("co2_ppm") > 0.0 and d.call("temperature_c") >= 2.0:
		out.append("greenhouse")
	elif d.call("co2_ppm") < 0.0 and d.call("temperature_c") <= -2.0:
		out.append("carbon_cycle")
	if now.get("ice_cover", 0.0) >= 0.25 and d.call("ice_cover") >= 0.08:
		out.append("ice_age")
	if absf(d.call("sea_level_m")) >= 20.0:
		out.append("sea_level")
	if d.call("sun_luminosity") >= 0.02 or now.get("year", 0.0) >= 500_000_000.0:
		out.append("sun_aging")
	if now.get("extinctions", 0.0) >= 5.0 and now.get("extinctions", 0.0) > before.get("extinctions", 0.0) * 2.0:
		out.append("mass_extinction")
	if now.has("biodiversity") and before.has("biodiversity") and before["biodiversity"] > 0.0 and now["biodiversity"] >= before["biodiversity"] * 1.5 + 3.0:
		out.append("adaptive_radiation")
	return out


## Phénomènes qu'un événement de la simulation invite à expliquer (types tolérants : sous-chaînes).
static func phenomena_for_event(event: Dictionary) -> Array:
	var t := str(event.get("type", "")).to_lower()
	var out := []
	for key in EVENT_PHENOMENA:
		if t.contains(key):
			for p in EVENT_PHENOMENA[key]:
				if not p in out:
					out.append(p)
	return out


## Pourquoi une espèce décline (heuristique documentée, d'après l'état réel) : "climate" si la planète
## s'est éloignée de sa température préférée, "predation" si un prédateur proche prospère, sinon
## "competition". sp : {temp_opt (0..1, échelle de WorldSim), diet}, ctx : contexte du fil.
static func decline_cause(sp: Dictionary, ctx: Dictionary) -> String:
	var traits: Dictionary = sp.get("traits", sp)
	var snap: Dictionary = ctx.get("snapshot", {})
	if traits.has("temp_opt") and snap.has("temperature_c"):
		var t01 := (float(snap["temperature_c"]) + 30.0) / 75.0
		if absf(t01 - float(traits["temp_opt"])) > float(traits.get("temp_tol", 0.2)):
			return "climate"
	for f in snap.get("fauna", []):
		if str(f.get("role", "")) == "carnivore" and int(f.get("trend", 0)) > 0 and str(f.get("name", "")) != str(sp.get("name", "")):
			return "predation"
	return "competition"


## Une explication d'un phénomène (fait vrai, propre à l'époque, pas dit récemment) ; {} si aucune.
func explain(phenomenon: String, ctx: Dictionary) -> Dictionary:
	_count += 1
	rng.seed = hash([_seed, _count, phenomenon])
	var epoch := Epoch.current(ctx)
	var facts := Phenomena.facts_of(phenomenon)
	if facts.is_empty():
		return {}
	var start := rng.randi() % facts.size()
	for i in facts.size():
		var f: Dictionary = facts[(start + i) % facts.size()]
		var t := str(f["t"])
		if str(f["id"]) in _recent_facts or not Epoch.is_clean(t, epoch) or (variety != null and variety.seen(t)):
			continue
		_recent_facts.append(str(f["id"]))
		while _recent_facts.size() > 40:
			_recent_facts.pop_front()
		_recent_phenomena.append(phenomenon)
		while _recent_phenomena.size() > PHENOMENON_MEMORY:
			_recent_phenomena.pop_front()
		return {"text": t, "kind": "explanation", "phenomenon": phenomenon, "fact_id": str(f["id"]), "source": "ambient"}
	return {}


## Le premier phénomène de la liste qui n'a pas été expliqué récemment (sinon le premier).
func choose(phenomena: Array) -> String:
	for p in phenomena:
		if not str(p) in _recent_phenomena:
			return str(p)
	return str(phenomena[0]) if not phenomena.is_empty() else ""


## Phénomènes que l'état du monde rend toujours d'actualité (quand rien de neuf n'arrive).
static func background_phenomena(now: Dictionary, ctx: Dictionary) -> Array:
	var out := []
	var o := float(now.get("oxygen", -1.0))
	if o >= 0.0 and o < OXYGEN_ANIMALS:
		out.append_array(["chemosynthesis", "photosynthesis", "oxygen_rise"])
	if now.has("ozone") and float(now["ozone"]) < OZONE_SHIELD:
		out.append("ozone")
	elif now.has("ozone"):
		out.append("land_colonization")
	if now.has("co2_ppm") or now.has("temperature_c"):
		out.append_array(["greenhouse", "carbon_cycle"])
	var sapient := false
	for sp in ctx.get("species", []):
		if bool(sp.get("sapient", false)) and bool(sp.get("alive", true)):
			sapient = true
	out.append_array(["natural_selection", "food_chain", "plate_tectonics"])
	if sapient:
		out.append("sapience")
	if float(now.get("year", 0.0)) > 100_000_000.0:
		out.append("sun_aging")
	return out


## Commentaire chiffré d'une statistique qui a nettement changé depuis l'échantillon le plus ancien de
## l'historique ; {} s'il n'y a rien de notable.
func stats_line(now: Dictionary, history: Array, ctx: Dictionary) -> Dictionary:
	if history.is_empty():
		return {}
	_count += 1
	rng.seed = hash([_seed, _count, "stats"])
	var epoch := Epoch.current(ctx)
	var old: Dictionary = normalize(history[0]) if history[0] is Dictionary else {}
	var dt := float(now.get("year", 0.0)) - float(old.get("year", now.get("year", 0.0)))
	if dt <= 0.0:
		return {}
	var keys := STAT_TEMPLATES.keys()
	var start := rng.randi() % keys.size()
	for i in keys.size():
		var k: String = keys[(start + i) % keys.size()]
		if not (now.has(k) and old.has(k)):
			continue
		var a := float(old[k])
		var b := float(now[k])
		var change := absf(b - a) if k in ["oxygen", "ozone", "ice_cover", "temperature_c", "sea_level_m", "sun_luminosity"] else absf(b - a) / maxf(absf(a), 1e-6)
		if change < float(NOTABLE[k]):
			continue
		var slots := {"valeur": _fmt(k, b), "avant": _fmt(k, a), "duree": Procedural._duration(dt),
			"sens": ("s'est élevé" if k == "sea_level_m" else "chauffé") if b > a else ("a baissé" if k == "sea_level_m" else "refroidi")}
		var tpls: Array = STAT_TEMPLATES[k]
		var t := Procedural.polish(str(tpls[rng.randi() % tpls.size()]).format(slots))
		if Epoch.is_clean(t, epoch) and (variety == null or not variety.seen(t)):
			return {"text": t, "kind": "stats", "stat": k, "source": "ambient"}
	return {}


static func _fmt(k: String, v: float) -> String:
	match k:
		"oxygen", "ozone", "ice_cover", "sun_luminosity":
			var pct := v * 100.0
			return ("%s %%" % String.num(pct, 1).replace(".", ",").trim_suffix(",0")) if pct < 10.0 else "%d %%" % int(round(pct))
		"co2_ppm":
			return "%d ppm" % int(round(v))
		"temperature_c":
			return "%d °C" % int(round(v))
		"sea_level_m":
			return ("+" if v >= 0.0 else "-") + "%d mètres" % absi(int(round(v)))
		"biodiversity":
			return "%d" % int(round(v))
	return String.num(v, 2)
