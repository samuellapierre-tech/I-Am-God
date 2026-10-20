extends RefCounted
## Simulation du monde : planète, espèces, ères, chaîne causale, timelines.
## Le contrat public (champs + méthodes du squelette) est fixé par docs/ARCHITECTURE.md :
## la carte (feature/world-map) et le narrateur (feature/ai-narrator) codent contre lui.
##
## Vue d'ensemble :
## - world_gen.gd : génération déterministe (altitude, température, humidité, biomes).
## - ecosystem.gd : dynamique régionale multicoeur (populations, compétition, colonisation).
## - species.gd   : roster initial, traits, mutation, nommage.
## - eras.gd      : ères, compression du temps, croissance technologique.
## - causality.gd : journal borné + conséquences différées (effet papillon).
##
## Aucune espèce n'est « destinée » à la sapience : n'importe quelle lignée qui franchit le seuil
## d'intelligence fonde une civilisation. Sans météore, les dinosaures peuvent y parvenir.
## Le météore de Chicxulub n'est PAS automatique : c'est au joueur (Dieu) de le lancer… ou non.
##
## Genèse (scénario par défaut) : une planète vierge à -4 Ga — roche, océans, atmosphère primitive
## (CO2, méthane, pas d'oxygène), aucune vie ; le joueur sème (action « seed »), la tectonique fait
## dériver les continents (tectonics.gd). Prologue : départ à -3,8 Ga avec des microbes marins. Oxygène,
## climat (soleil jeune, méthane, CO2, Terre boule de neige), complexité du vivant et conquête des
## terres évoluent d'eux-mêmes ; les étapes (Eras.ARCHEAN .. Eras.GREAT_DYING) se déclenchent
## quand l'état du monde les atteint (_prologue_stage). Le scénario « cretaceous » démarre
## directement à -66 Ma avec le roster de la fin du Crétacé (tests, partie courte).

const Eras := preload("res://src/sim/eras.gd")
const Species := preload("res://src/sim/species.gd")
const WorldGen := preload("res://src/sim/world_gen.gd")
const Causality := preload("res://src/sim/causality.gd")
const Ecosystem := preload("res://src/sim/ecosystem.gd")
const Tectonics := preload("res://src/sim/tectonics.gd")

## La géographie (relief, biomes, côtes) a été recalculée : la carte re-téléverse ses textures.
signal geography_changed(version: int)

const WIDTH := 256
const HEIGHT := 128

const ERAS := Eras.NAMES

## Scénarios de départ (troisième argument du constructeur).
const SCENARIO_GENESIS := "genesis"
const SCENARIO_PROLOGUE := "prologue"
const SCENARIO_CRETACEOUS := "cretaceous"
const GENESIS_START_YEAR := -4.0e9
const PROLOGUE_START_YEAR := -3.8e9
## Paramètres de planète par défaut (proches de la Terre) ; la réincarnation en tire d'autres.
const DEFAULT_PLANET := {ocean_fraction = 0.64, axial_tilt = 23.4, star_luminosity = 1.0, plates = 10}
## Tectonique : intervalle (années) et sous-pas minimaux entre deux recalculs de la géographie ;
## le calcul tourne sur un fil de travail, rejoint GEO_JOIN_SUBSTEPS sous-pas plus tard.
const GEO_INTERVAL := 2.0e6
const GEO_JOIN_SUBSTEPS := 12
## Retard maximal (années simulées) de la géographie : au-delà, le calcul est rejoint aussitôt
## (les grands pas du temps profond ne laissent pas les plaques se traverser).
const GEO_MAX_LAG := 6.0e6
## Bruit de fond des fonds océaniques (relief des abysses).
const OCEAN_NOISE := 0.08
## Semences : densité de départ dans les régions visées.
const SEED_POPULATION := 0.2
## Ozone : temps de cicatrisation (unités d'ère) et dégâts des gestes et de l'industrie.
const OZONE_DAMAGE_VOLCANO := 0.15
const OZONE_DAMAGE_METEOR := 0.3
## Soleil : luminosité relative par milliard d'années, et effet sur l'échelle de température
## (direct, puis emballement de la vapeur d'eau au-delà de la luminosité actuelle).
const SUN_BRIGHTENING_PER_GA := 0.087
const SUN_TEMPERATURE_GAIN := 0.66
const SUN_RUNAWAY_GAIN := 2.6
## Évaporation des océans (luminosité relative) : début, fin.
const OCEAN_LOSS := Vector2(1.2, 1.4)
## Statistiques planétaires : un échantillon tous les PLANET_SAMPLE_STEPS pas idéaux, au plus N.
const PLANET_SAMPLE_STEPS := 3.0
const PLANET_HISTORY_SIZE := 512
const CRETACEOUS_START_YEAR := -66.0e6

const BIOME_NAMES := WorldGen.BIOME_NAMES

## Dérive d'intelligence (par million d'années) d'une lignée prospère et généraliste.
const INTELLIGENCE_DRIFT := 0.008
## Échelle (années) de la pression vers la complexité : x2 après ce délai sans sapience.
const COMPLEXITY_PRESSURE_YEARS := 20.0e6
## Taux de spéciation de base (par an).
const SPECIATION_RATE := 1.0 / 2500000.0
## Diversité visée : la spéciation ralentit à l'approche de ce nombre d'espèces vivantes.
const DIVERSITY_TARGET := 64
## Nombre de pas idéaux par ère sapiente, et pas idéaux par seconde à vitesse x1 (=> ~1 min/ère).
const STEPS_PER_ERA := 1200.0
const PACING_STEPS_PER_SECOND := 20.0
## Nombre maximal de pas internes pour une projection du futur.
const MAX_PROJECTION_SUBSTEPS := 600
## Au-delà, les espèces éteintes les plus anciennes sont retirées du dictionnaire `species`.
const MAX_SPECIES_RECORDS := 2048

## Types d'événements considérés comme marquants (résumés de projection).
const KEY_EVENT_WEIGHT := {
	"sapience": 10, "era_change": 9, "impact": 8, "extinction": 5, "collapse": 7, "war": 4,
	"plague": 4, "golden_age": 4, "ice_age": 6, "deluge": 5, "invasion": 3, "radiation": 3,
	"discovery": 2, "lazarus": 6, "uplift": 6, "volcanism": 3, "decline": 3,
	"clade": 5, "snowball": 7, "thaw": 5, "traps": 8, "oxygen": 4,
	"seeding": 7, "supercontinent": 6, "breakup": 6, "orogeny": 3, "vicariance": 4, "drift": 3,
	"end_of_times": 10,
}

# --- Prologue : oxygène, climat, conquête des terres -----------------------------------------
## Productivité oxygénique des mers : part des mers occupée par des cyanobactéries, par des algues
## (indépendant du nombre d'espèces : c'est la couverture qui compte ; pleine dès COVER_FULL).
const COVER_FULL := 0.35
const CYANO_PRODUCTIVITY := 1.6
const ALGAE_PRODUCTIVITY := 5.9
## Fer dissous et gaz réducteurs : absorbent l'oxygène tant qu'il en reste (consommés par la
## productivité ; ~1,4 Ga de cyanobactéries par défaut -> Grande Oxydation vers -2,4 Ga).
const IRON_DRAW := 1.0 / 2.15e9
## Puits profonds (océans sulfureux) : tiennent l'oxygène bas pendant le « milliard ennuyeux »,
## oxydés peu à peu par l'oxygène lui-même.
const SINK_GAIN := 23.0
const SINK_DRAW := 1.0 / 60.0e6
## Oxygène d'équilibre (fraction du niveau actuel) par unité de productivité, et apport des forêts.
const OXYGEN_GAIN := 0.06
const OXYGEN_LAND := 0.35
const OXYGEN_TAU := 40.0e6
## Climat du prologue (décalage de la grille de température 0..1).
const FAINT_SUN := -0.22
const METHANE_MAX := 0.4
const CO2_TAU := 250.0e6
const SNOWBALL_IN := -0.12
const SNOWBALL_OUT := 0.06
const SNOWBALL_ALBEDO := -0.55
## Accumulation volcanique du CO2 pendant la boule de neige (rien ne l'absorbe sous la glace).
const SNOWBALL_CO2_RATE := 0.24 / 85.0e6
## Trapps (Grande Mourance) : aléa croissant après l'entrée au Carbonifère (loi de Rayleigh).
const TRAPS_TAU := 38.0e6
## Diversité visée au prologue : globale (la table compte Ecosystem.MAXS espèces vivantes), et par
## clade et niveau de complexité (les microbes ne monopolisent pas la table ; les vertébrés
## terrestres, plus tardifs, ont plus de place).
const PROLOGUE_DIVERSITY := 128
const CLADE_DIVERSITY := 8
const TETRAPOD_DIVERSITY := 12
## Plancher du facteur de diversité globale au prologue : l'évolution ne gèle jamais tout à fait.
const MIN_DIVERSITY := 0.2
## Une extinction de masse (cette part des espèces en moins de 2 Ma) ouvre la Grande Mourance.
const MASS_EXTINCTION_SHARE := 0.45
## Probabilité de transition de clade par spéciation (x poids de la règle).
const CLADE_TRANSITION_RATE := 0.01
const RADIATION_TRANSITION_BOOST := 6.0
## Pression évolutive : une transition possible devient de plus en plus probable avec le temps
## écoulé depuis que ses conditions sont réunies (x(1 + (t/RAMP)²)) ; resserre les dates.
const TRANSITION_RAMP := 35.0e6
## Maturation des cerveaux d'amniotes (prologue) : la dérive d'intelligence est multipliée par
## (âge des amniotes / BRAIN_YEARS)³ ; à la spéciation, l'intelligence est rappelée vers
## BRAIN_BASELINE (un cerveau coûte cher). Sans cela, 300 Ma d'évolution rendraient conscients
## tous les reptiles du Trias.
const BRAIN_YEARS := 280.0e6
const BRAIN_BASELINE := 0.15
const BRAIN_RECALL := 0.05

## Rythme de l'acte I : à l'entrée au Mésozoïque, le pas idéal est calé pour que le monde atteigne
## la fin du Crétacé de référence en MESOZOIC_STEPS pas idéaux (~20 min à x1 avec l'ouverture
## lente), quelle que soit la date de la Grande Mourance. Comme pour les ères sapientes, c'est le
## rythme de présentation qui s'adapte, pas la simulation.
const MESOZOIC_STEPS := 2650.0
const MESOZOIC_DT_MIN := 40000.0
const MESOZOIC_DT_MAX := 110000.0

# --- Mode Éternité et futur lointain ---------------------------------------------------------
## Exode : une civilisation post-singularité finit par quitter la Terre (taux par an).
const EXODUS_RATE := 1.0 / 1500.0
## Effondrements tardifs (mode Éternité) : occurrences par durée de niveau technologique, à partir
## du niveau EXHAUSTION_LEVEL (ère moderne).
const EXHAUSTION_LEVEL := 5.0
const EXHAUSTION_RATE := 0.08
## Plafond de la pression vers la complexité (sinon, dans un futur lointain, chaque lignée
## deviendrait consciente sitôt la précédente partie).
const MAX_COMPLEXITY_PRESSURE := 4.0
## Soleil vieillissant : décalage de température par milliard d'années après l'an 0, et seuils où
## la vie complexe commence / finit de suffoquer.
const SUN_WARMING_PER_GA := 0.3
const SUN_COMPLEX_LIMIT := Vector2(0.18, 0.4)
## Glaciations naturelles après le prologue (taux par an) et leur refroidissement.
const NATURAL_ICE_AGE_RATE := 1.0 / 60.0e6
const NATURAL_ICE_AGE_COLD := -0.12
## Sans aucune vie, la vie renaît (sources chaudes) après ce délai (mode Éternité).
const ABIOGENESIS_YEARS := 20.0e6
## Niveau marin (élévation 0..1, prologue) : les continents émergent lentement (« franc-bord »),
## jusqu'à LAND_EMERGENCE_YEAR ; le climat s'y ajoute (glaciations basses, mondes chauds hauts).
const SEA_FREEBOARD := 0.05
const SEA_FREEBOARD_POWER := 0.2
const LAND_EMERGENCE_YEAR := -450.0e6
const SEA_CLIMATE_GAIN := 0.15
## Les calottes mettent des millions d'années à croître ou fondre : le niveau marin suit le climat
## avec ce temps de réponse (les chocs brefs ne font pas battre les rivages).
const SEA_LEVEL_TAU := 5.0e6

const STAGE_TEXT := {
	Eras.GREAT_OXIDATION: "les cyanobactéries saturent l'atmosphère d'oxygène et empoisonnent la vie ancienne",
	Eras.SNOWBALL: "le méthane disparaît, la glace gagne l'équateur",
	Eras.CAMBRIAN: "yeux, carapaces et prédateurs envahissent les mers",
	Eras.LAND_CONQUEST: "des poissons à pattes rampent sur des rivages verdis",
	Eras.CARBONIFEROUS: "forêts-charbon, insectes géants et premiers œufs à coquille",
	Eras.GREAT_DYING: "la planète suffoque, la plupart des espèces disparaissent",
	Eras.MESOZOIC: "les survivants héritent d'un monde vide",
}


@warning_ignore("shadowed_global_identifier")
var seed: int
var year: float = -66_000_000.0
## Grilles WIDTH*HEIGHT, indexées par y * WIDTH + x.
var elevation := PackedFloat32Array()   # -1 (abysses) .. 1 (montagnes)
var temperature := PackedFloat32Array() # 0 (glacial) .. 1 (torride)
var population := PackedFloat32Array()  # 0 .. 1 densité de l'espèce dominante
var tech := PackedFloat32Array()        # 0 .. 1 niveau technologique local
var dominant_species := PackedInt32Array() # -1 = aucune
## id -> {name, alive, sapient, population, traits}
## (+ clade, parent, born_year, extinct_year, tech_level, regions)
var species := {}

# --- Ajouts publics (compatibles avec le contrat) ---
var moisture := PackedFloat32Array()    # 0 (aride) .. 1 (humide)
var biome := PackedByteArray()          # indice dans BIOME_NAMES
## "prologue" (départ à -3,8 Ga, microbes) ou "cretaceous" (départ à -66 Ma, roster du Crétacé).
var scenario := SCENARIO_GENESIS
## Paramètres de la planète (DEFAULT_PLANET complété par ceux passés au constructeur).
var planet := {}
## Plaque de chaque cellule et frontières (0 aucune, 1 divergente, 2 convergente, 3 coulissante).
var plate_id := PackedInt32Array()
var plate_boundary := PackedByteArray()
## Incrémenté à chaque recalcul de la géographie (voir le signal geography_changed).
var geography_version := 0
## Part des terres dans la plus grande masse connexe (supercontinent si ≥ ~0,7).
var supercontinent_fraction := 0.0
## Couche d'ozone (0..1), luminosité du Soleil (1 = actuelle), habitabilité (0..1).
var ozone := 1.0
var sun_luminosity := 1.0
var habitability := 1.0
var ice_cover := 0.0
## Fin des temps : la planète est stérile et inhabitable (événement end_of_times émis une fois).
var end_of_times := false
## Statistiques planétaires échantillonnées en temps simulé (≤ PLANET_HISTORY_SIZE).
var planet_history: Array[Dictionary] = []
## Oxygène atmosphérique, en fraction du niveau actuel (0 à l'Archéen, ~1 au Mésozoïque).
var oxygen := 1.0
## Complexité maximale du vivant (0..6, Species.COMPLEXITY_NAMES).
var max_complexity := 6.0
## Part des terres couvertes de plantes (0..1) et part des régions abritant de la vie animale
## terrestre (0..1).
var land_flora := 1.0
var land_fauna := 1.0
## La planète est-elle une boule de neige ?
var snowball := false
## Année d'entrée dans chaque ère atteinte : {indice d'ère: année}.
var era_years := {}
## Mode Éternité (par défaut) : exode des civilisations accomplies, effondrements tardifs, vie qui
## renaît d'elle-même. false = mode Épreuve (piloté par la stratégie), voir set_endless().
var endless := true
## Niveau de la mer, en unités d'altitude (0 = rivage de la carte). Varie au prologue et avec le
## climat ; toujours 0 dans le scénario du Crétacé.
var sea_level := 0.0
## Cycles de civilisation achevés (chute ou départ de toute civilisation) et renaissances de la vie.
var cycles := 0
var rebirths := 0
## Journal causal (history, get_event, chain).
var causal_log: RefCounted
## Nombre maximal de pas internes par appel à step() (borne le coût d'une image).
var max_substeps := 4
## Durée du dernier appel à step(), en microsecondes.
var last_step_usec := 0
## Nombre de pas internes du dernier appel à step().
var last_substeps := 0

# --- État privé ---
var _eco: RefCounted
var _rng := RandomNumberGenerator.new()
var _base_temp := PackedFloat32Array()
## id -> données d'exécution (indice de table, protections, causes, modificateurs…).
var _rt := {}
var _alive: Array[int] = []
var _next_species_id := 0
var _era_idx := 0
var _left_mesozoic := false
var _step_count := 0
var _seed_hash := 0
var _climate_anom := 0.0
var _climate_tau := 1.0
var _climate_cause := -1
var _climate_cause_until := -INF
var _goff_written := 1e9
var _biome_goff := 0.0
var _regional_active := false
var _mig_mult := 1.0
var _mig_until := -INF
var _last_dino_extinction := -1
var _era_cause := -1
var _iron := 0.0
var _sink := 0.0
var _co2 := 0.0
var _proto := 0.0
var _methane := 0.0
var _trap_clock := 0.0
var _great_dying_year := NAN
var _amniote_year := -1.0e9
var _dino_ruled := false
var _recent_ext: Array[float] = []
var _groups := {}
## Indice de règle de transition -> année où ses conditions ont été réunies pour la première fois.
var _rule_ready := {}
var _land_regions := 1
var _sea_regions := 1
var _planet_cause := -1
## Froid imposé par Dieu (âge glaciaire) : seul refroidissement passager qui puisse geler la
## planète entière (les supervolcans n'y suffisent pas). Décroît comme _climate_anom.
var _ice_push := 0.0
var _meso_dt := 0.0
var _tect: Tectonics = null
var _temp_lat := PackedFloat32Array()
var _moist_lat := PackedFloat32Array()
var _ocean_noise := PackedFloat32Array()
var _coast_dist := PackedFloat32Array()
var _geo_task := -1
var _geo_result := {}
var _geo_substeps := 0
var _next_geo := 0.0
var _craters: Array[Dictionary] = []
var _ozone_damage := 0.0
var _evaporation := 0.0
var _ext_years: Array[float] = []
var _next_planet_sample := -INF
var _last_geo_year := 0.0
var _peak_complexity := 0.0
var _lifeless_since := NAN
var _had_civilization := false


## p_planet : ocean_fraction, axial_tilt (degrés), star_luminosity (1 = Soleil), plates (nombre).
func _init(p_seed: int, p_generate := true, p_scenario := SCENARIO_GENESIS, p_planet := {}) -> void:
	seed = p_seed
	scenario = p_scenario
	planet = DEFAULT_PLANET.duplicate()
	planet.merge(p_planet, true)
	var n := WIDTH * HEIGHT
	for a in [elevation, temperature, population, tech, moisture, _base_temp, _temp_lat, _moist_lat,
			_ocean_noise, _coast_dist]:
		a.resize(n)
	plate_id.resize(n)
	plate_boundary.resize(n)
	biome.resize(n)
	dominant_species.resize(n)
	dominant_species.fill(-1)
	_seed_hash = hash(p_seed) & 0x7fffffff
	_rng.seed = hash("I AM GOD:%d" % p_seed)
	causal_log = Causality.new()
	_eco = Ecosystem.new()
	if not p_generate:
		return
	WorldGen.generate(seed, WIDTH, HEIGHT, elevation, _base_temp, moisture, biome,
		{land_fraction = 1.0 - float(planet.ocean_fraction), axial_tilt = float(planet.axial_tilt)},
		_temp_lat, _moist_lat)
	for i in n:
		_ocean_noise[i] = clampf(-elevation[i] - 0.5, -1.0, 1.0) if elevation[i] < 0.0 else 0.0
	_eco.bind_grids(self)
	_eco.build_static()
	_land_regions = 0
	for r in Ecosystem.NR:
		if _eco.r_land[r] > 0.0:
			_land_regions += 1
	_land_regions = maxi(_land_regions, 1)
	_sea_regions = 0
	for r in Ecosystem.NR:
		if _eco.r_sea[r] > 0.0:
			_sea_regions += 1
	_sea_regions = maxi(_sea_regions, 1)
	if scenario == SCENARIO_GENESIS:
		year = GENESIS_START_YEAR
		_era_idx = Eras.ARCHEAN
		oxygen = 0.0
		max_complexity = 0.0
		land_flora = 0.0
		land_fauna = 0.0
		_iron = 1.0
		_sink = 1.0
		_amniote_year = INF
		_eco.explicit_flora = 1
		var none: Array[Dictionary] = []
		_climate_step(0.0, none)
		_update_sea_level(0.0)
		_tect = Tectonics.new()
		_tect.setup(seed, elevation, int(planet.plates), year)
		_last_geo_year = year
		_apply_geography(_geo_work(_tect.snapshot(), sea_level, []), none)
		_next_geo = year + GEO_INTERVAL
	elif scenario == SCENARIO_PROLOGUE:
		year = PROLOGUE_START_YEAR
		_era_idx = Eras.ARCHEAN
		oxygen = 0.0
		max_complexity = 0.0
		land_flora = 0.0
		land_fauna = 0.0
		_iron = 1.0
		_sink = 1.0
		_amniote_year = INF
		_eco.explicit_flora = 1
		_seed_prologue()
		_methane = 2.0 / 3.0
		var none: Array[Dictionary] = []
		_climate_step(0.0, none)
		_update_sea_level(0.0)
	else:
		year = CRETACEOUS_START_YEAR
		_era_idx = Eras.MESOZOIC
		_dino_ruled = true
		_seed_roster()
	era_years[_era_idx] = year
	var none0: Array[Dictionary] = []
	_eco.set_oxygen(oxygen, Species.OXYGEN_NEED, _complex_room(), _land_room())
	_refresh_view()
	_update_planet_state(0.0, none0)
	_record_planet()


# =============================================================================================
# Contrat public
# =============================================================================================

## Avance le temps de `years` années (valeur arbitrairement grande) en sous-pas adaptatifs :
## dt idéal selon l'ère, au plus `max_substeps` sous-pas (le dt grossit alors, le modèle restant
## stable pour tout dt). Renvoie les événements survenus.
func step(years: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	last_substeps = 0
	if not (years > 0.0) or is_inf(years):
		return out
	var t0 := Time.get_ticks_usec()
	var remaining := years
	while remaining > 0.0:
		var ideal := ideal_step_years()
		var left := max_substeps - last_substeps
		var dt := minf(remaining, ideal)
		if left <= 1:
			dt = remaining
		elif remaining > ideal * left:
			dt = remaining / left
		_substep(dt, out)
		remaining -= dt
		last_substeps += 1
	last_step_usec = Time.get_ticks_usec() - t0
	return out


## action : {type: String, region: Vector2i, species_id: int, radius: int}
## Renvoie [événement racine de l'action divine, conséquences immédiates...]. Les conséquences
## différées sont planifiées et apparaîtront plus tard dans step(), avec cause_id remontant ici.
func apply_divine_action(action: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var type := String(action.get("type", ""))
	@warning_ignore("integer_division")
	var cell: Vector2i = action.get("region", Vector2i(WIDTH / 2, HEIGHT / 2))
	cell = Vector2i(posmod(cell.x, WIDTH), clampi(cell.y, 0, HEIGHT - 1))
	var radius := maxi(1, int(action.get("radius", 8)))
	var a := {
		type = type, cell = cell, r = _eco.region_of_cell(cell), radius = radius,
		rrad = maxi(1, ceili(radius / float(Ecosystem.RS))),
		target = _target_species(action, cell),
	}
	var root: Dictionary = causal_log.make_root(year, "divine_" + type, cell, a.target,
		"Dieu : %s" % _action_label(type, a.target))
	out.append(root)
	match type:
		"meteor": _act_meteor(a, root, out)
		"extinct": _act_extinct(a, root, out)
		"save": _act_save(a, root, out)
		"bless": _act_bless(a, root, out)
		"plague": _act_plague(a, root, out)
		"uplift": _act_uplift(a, root, out)
		"flood": _act_flood(a, root, out)
		"ice_age": _act_ice_age(a, root, out)
		"spawn_species": _act_spawn(a, root, out)
		"volcano": _act_volcano(a, root, out)
		"oxygenate": _act_oxygenate(a, root, out)
		"soothe": _act_soothe(a, root, out)
		"seed": _act_seed(a, action, root, out)
		"drift": _act_drift(a, action, root, out)
		_: root.summary = "Dieu fait un geste que le monde ne comprend pas (%s)" % type
	_refresh_view(out)
	_update_era(out)
	return out


func current_era() -> String:
	return ERAS[_era_idx]


## Copie profonde et indépendante (timeline alternative). Même graine, même état, même aléa.
func fork() -> RefCounted:
	var f: RefCounted = get_script().new(seed, false)
	f.year = year
	f.elevation = elevation.duplicate()
	f.temperature = temperature.duplicate()
	f.population = population.duplicate()
	f.tech = tech.duplicate()
	f.dominant_species = dominant_species.duplicate()
	f.moisture = moisture.duplicate()
	f.biome = biome.duplicate()
	f._base_temp = _base_temp.duplicate()
	f.species = species.duplicate(true)
	f._rt = _rt.duplicate(true)
	f._alive = _alive.duplicate()
	f.causal_log = causal_log.copy()
	f._eco = _eco.copy()
	f._eco.bind_grids(f)
	f._rng.seed = _rng.seed
	f._rng.state = _rng.state
	for prop in ["max_substeps", "_next_species_id", "_era_idx", "_left_mesozoic", "_step_count",
			"_seed_hash", "_climate_anom", "_climate_tau", "_climate_cause", "_climate_cause_until",
			"_goff_written", "_biome_goff", "_regional_active", "_mig_mult", "_mig_until",
			"_last_dino_extinction", "_era_cause"]:
		f.set(prop, get(prop))
	for prop in ["scenario", "oxygen", "max_complexity", "land_flora", "land_fauna", "snowball",
			"_iron", "_sink", "_co2", "_proto", "_methane", "_trap_clock", "_great_dying_year",
			"_amniote_year", "_dino_ruled", "_land_regions", "_sea_regions", "_planet_cause", "_ice_push", "_meso_dt", "endless", "sea_level", "cycles", "rebirths",
			"_peak_complexity", "_lifeless_since", "_had_civilization", "geography_version",
			"supercontinent_fraction", "ozone", "sun_luminosity", "habitability", "ice_cover",
			"end_of_times", "_geo_substeps", "_next_geo", "_ozone_damage", "_evaporation",
			"_next_planet_sample", "_last_geo_year"]:
		f.set(prop, get(prop))
	f.era_years = era_years.duplicate()
	f.planet = planet.duplicate()
	for prop in ["plate_id", "plate_boundary", "_temp_lat", "_moist_lat", "_ocean_noise", "_coast_dist"]:
		f.set(prop, get(prop).duplicate())
	f._craters = _craters.duplicate(true)
	f._ext_years = _ext_years.duplicate()
	f.planet_history = planet_history.duplicate(true)
	if _tect != null:
		# Le calcul en cours est terminé (pur) avant la copie : les deux mondes le rejoindront au même sous-pas.
		if _geo_task >= 0:
			WorkerThreadPool.wait_for_task_completion(_geo_task)
			_geo_task = -2
		f._tect = _tect.copy()
		f._geo_result = _geo_result.duplicate(true)
		f._geo_task = _geo_task
	f._recent_ext = _recent_ext.duplicate()
	f._groups = _groups.duplicate()
	f._rule_ready = _rule_ready.duplicate()
	return f


## Simule une copie `years` années en avance et résume ce futur possible, sans toucher à ce monde.
## {from_year, to_year, era, era_index, era_reached, dominant_species: {id, name, clade},
##  sapient_species: [{id, name, clade, tech_level}], extinct_species: [{id, name, clade}],
##  new_species: int, events_count: int, key_events: Array[Dictionary]}
func project_future(years: float) -> Dictionary:
	var f: RefCounted = fork()
	var target := year + maxf(years, 0.0)
	var events: Array[Dictionary] = []
	var budget := MAX_PROJECTION_SUBSTEPS
	var era_reached := _era_idx
	while f.year < target and budget > 0:
		var rem: float = target - f.year
		var chunk: float = minf(rem, f.ideal_step_years() * f.max_substeps)
		# Budget borné : le pas grossit si la projection est très longue.
		chunk = maxf(chunk, rem * f.max_substeps / float(budget))
		if rem - chunk < 1e-6 * absf(target):
			chunk = rem
		events.append_array(f.step(chunk))
		budget -= f.last_substeps
		era_reached = maxi(era_reached, f.era_index())
	if f.year < target:
		events.append_array(f.step(target - f.year))
		era_reached = maxi(era_reached, f.era_index())
	return f.summarize_since(self, events, era_reached)


# =============================================================================================
# Ajouts publics
# =============================================================================================

func era_index() -> int:
	return _era_idx


## Sous-période géologique (« Archéen » … « Trias », « Jurassique », « Crétacé ») tant qu'aucune
## espèce n'est consciente ; "" ensuite.
func current_period() -> String:
	if _era_idx >= Eras.FIRST_SAPIENT_ERA:
		return ""
	return Eras.period_for_year(year)


func is_prologue() -> bool:
	return Eras.is_prologue(_era_idx)


## Mode Éternité (true, par défaut) ou Épreuve (false) : en Épreuve, les civilisations ne partent
## pas d'elles-mêmes vers les étoiles, ne s'épuisent pas spontanément et la vie ne renaît pas d'un
## monde stérile — la partie peut donc finir.
func set_endless(on: bool) -> void:
	endless = on


## Fermeture propre : attend le recalcul de géographie en vol (il lit ce monde depuis un fil de
## travail). Le résultat reste à appliquer au même sous-pas qu'avant : le déterminisme est intact.
func shutdown() -> void:
	if _geo_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_geo_task)
		_geo_task = -2


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _geo_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_geo_task)
		_geo_task = -2


## Sauvegarde : à appeler avant de lire l'état par réflexion. Termine le recalcul de géographie en
## cours (il reste à appliquer, comme sans sauvegarde : son résultat est dans _geo_result).
func prepare_save() -> void:
	if _geo_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_geo_task)
		_geo_task = -2


## Après un chargement par réflexion : rebranche les grilles partagées de l'écosystème et oublie
## l'identifiant de tâche (volatil).
func post_load() -> void:
	_eco.bind_grids(self)
	if _geo_task != -1:
		_geo_task = -2 if not _geo_result.is_empty() else -1


## Statistiques planétaires pour l'interface (lecture seule).
func planet_stats() -> Dictionary:
	var biomass := 0.0
	for id in _alive:
		biomass += float(species[id].population)
	var window := Eras.time_unit(_era_idx) * 5.0
	var recent := 0
	for y in _ext_years:
		if year - y <= window:
			recent += 1
	return {
		year = year, global_temperature_c = global_temperature_c(), ozone = ozone, oxygen = oxygen,
		co2 = co2_ppm(), methane = methane_ppm(), sea_level = sea_level, sea_level_m = sea_level * 6000.0,
		ice_cover = ice_cover, biomass = biomass, biodiversity = _alive.size(),
		recent_extinctions = recent, sun_luminosity = sun_luminosity, habitability = habitability,
		supercontinent_fraction = supercontinent_fraction,
	}


## Température moyenne (°C) de la grille (échantillonnée).
func global_temperature_c() -> float:
	var s := 0.0
	var k := 0
	for i in range(0, temperature.size(), 37):
		s += temperature[i]
		k += 1
	return -30.0 + 75.0 * s / maxf(1.0, k)


## Effet de serre exprimé en concentrations (ordres de grandeur plausibles, pour l'affichage).
func co2_ppm() -> float:
	return 280.0 * pow(2.0, clampf(_co2, -0.15, 0.5) / 0.03) if _deep_time() else 280.0


func methane_ppm() -> float:
	if not _deep_time():
		return 0.7
	var ch4 := METHANE_MAX * maxf(_methane, 0.6 * smoothstep(0.1, 0.25, _sink) * _life_present()) * (1.0 - smoothstep(0.03, 0.08, oxygen))
	return minf(0.7 * pow(2.0, ch4 / 0.02), 5000.0)


## Ancre de croûte d'une cellule : la parcelle la suit quand les plaques bougent (anchor_cell).
func make_anchor(cell: Vector2i) -> Dictionary:
	var c := Vector2i(posmod(cell.x, WIDTH), clampi(cell.y, 0, HEIGHT - 1))
	if _tect == null:
		return {cell = c}
	return _tect.make_anchor(c, plate_id[c.y * WIDTH + c.x])


func anchor_cell(anchor: Dictionary) -> Vector2i:
	if _tect == null or not anchor.has("plate"):
		return anchor.get("cell", Vector2i.ZERO)
	return _tect.anchor_cell(anchor)


## Où se trouve, `years` années plus tard au rythme actuel des plaques, la croûte qui est en `cell` ?
func track_cell(cell: Vector2i, years: float) -> Vector2i:
	if _tect == null:
		return cell
	var a := make_anchor(cell)
	var k: int = a.plate
	var dm := years / 1.0e6
	var p := _tect.plate_position(k, float(a.ox), float(a.oy)) + Vector2(_tect.p_vx[k], _tect.p_vy[k]) * dm
	return Vector2i(posmod(int(round(p.x)), WIDTH), clampi(int(round(p.y)), 0, HEIGHT - 1))


## Profondeur d'eau (unités d'altitude, > 0 sous la mer) d'une cellule, niveau marin compris.
func water_depth(i: int) -> float:
	return -elevation[i] if _tect != null else sea_level - elevation[i]


## Altitude de la croûte au-dessus du niveau marin de référence (0), quel que soit le niveau actuel.
func crust_elevation(i: int) -> float:
	return elevation[i] + (sea_level if _tect != null else 0.0)


func tectonics_phase() -> String:
	return _tect.phase if _tect != null else ""


## Tailles des structures qui croissent avec la partie (mémoire bornée).
func memory_report() -> Dictionary:
	var r: Dictionary = causal_log.size_report()
	r.species_records = species.size()
	r.alive = _alive.size()
	r.runtime_records = _rt.size()
	r.planet_history = planet_history.size()
	r.craters = _craters.size()
	return r


## Nom du niveau de complexité atteint (« microbes », « animaux », « amniotes »…).
func complexity_name() -> String:
	return Species.COMPLEXITY_NAMES[clampi(int(max_complexity), 0, Species.COMPLEXITY_NAMES.size() - 1)]


## Pas de temps idéal (années) pour l'ère courante : utile pour régler la vitesse de jeu.
## Avant la sapience : pas fixe de l'ère géologique. Ensuite, le rythme suit la technologie :
## le temps que met la civilisation de tête à franchir son niveau actuel, divisé par
## STEPS_PER_ERA. Une ère dure donc toujours environ STEPS_PER_ERA pas idéaux, quelle que soit
## l'année du calendrier (un monde sans civilisation en 2000 reste au rythme géologique).
func ideal_step_years() -> float:
	var lead := _leading_species()
	if lead < 0:
		if _era_idx == Eras.MESOZOIC and _meso_dt > 0.0:
			return _meso_dt
		if _era_idx == Eras.AFTERMATH and max_complexity < 3.0:
			return Eras.ideal_dt(Eras.CAMBRIAN)  # la vie repart des microbes : temps géologique
		return Eras.ideal_dt(_era_idx)
	var level: float = species[lead].tech_level
	if level >= Eras.MAX_TECH:
		return 1.0  # Post-singularité achevée : l'histoire continue à un rythme posé.
	var era_years := Eras.level_years(level) / maxf(_tech_speed(lead), 0.05)
	return clampf(era_years / STEPS_PER_ERA, 0.005, Eras.ideal_dt(Eras.CENOZOIC))


## Années par seconde réelle pour qu'une ère dure environ une minute à vitesse x1.
func pacing_years_per_second() -> float:
	return ideal_step_years() * PACING_STEPS_PER_SECOND


## Vitesse de progression technologique d'un peuple (multiplicateur des LEVEL_YEARS).
func _tech_speed(id: int) -> float:
	var sp: Dictionary = species[id]
	var mods := 1.0
	for m in _rt[id].mods:
		if m.until >= year:
			mods *= m.factor
	mods = clampf(mods, 0.3, 2.5)
	var popf := clampf(sqrt(float(sp.regions) / 120.0), 0.15, 1.6)
	return popf * mods * (0.8 + 0.5 * float(sp.traits.intelligence))


func get_event(event_id: int) -> Dictionary:
	return causal_log.get_event(event_id)


## Chaîne causale : [événement, sa cause, la cause de sa cause, ...] jusqu'à la racine
## (action divine ou fait naturel). Exemple : extinction <- impact <- divine_meteor.
func get_causal_chain(event_id: int) -> Array[Dictionary]:
	return causal_log.chain(event_id)


## Derniers événements du journal (ordre chronologique).
func get_history(count := 64) -> Array[Dictionary]:
	var h: Array[Dictionary] = causal_log.history
	return h.slice(maxi(0, h.size() - count))


## Espèce dominant le plus de régions (id public, -1 si aucune).
func get_dominant_species() -> int:
	var counts := {}
	var best := -1
	var best_n := 0
	var marine_only := _land_life_count() == 0
	for r in Ecosystem.NR:
		var idx: int = _eco.r_dom[r]
		if idx < 0 and marine_only:
			idx = _eco.r_mdom[r]  # avant la conquête des terres, la vie est marine
		if idx < 0:
			continue
		var n: int = counts.get(idx, 0) + 1
		counts[idx] = n
		if n > best_n or (n == best_n and idx < best):
			best_n = n
			best = idx
	return _eco.t_id[best] if best >= 0 else -1


func get_sapient_species() -> Array[int]:
	var out: Array[int] = []
	for id in _alive:
		if species[id].sapient:
			out.append(id)
	return out


func get_alive_species() -> Array[int]:
	return _alive.duplicate()


## Niches de la région écologique (RS x RS cellules) contenant `cell`, en lecture seule :
## [{species_id, density}] pour chaque espèce vivante qui y est établie (≤ Ecosystem.K).
## Utilisé par ParcelSim pour peupler la parcelle au-delà de la seule espèce dominante.
func region_niches(cell: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var base: int = _eco.region_of_cell(cell) * Ecosystem.K
	for k in Ecosystem.K:
		var idx: int = _eco.cur_sp[base + k]
		if idx >= 0 and _eco.t_alive[idx] == 1:
			out.append({species_id = int(_eco.t_id[idx]), density = float(_eco.cur_pop[base + k]),
				habitat = Species.HABITATS[_eco.t_hab[idx]]})
	return out


## Résumé de cette timeline depuis `origin` (utilisé par project_future).
func summarize_since(origin: RefCounted, events: Array[Dictionary], era_reached: int) -> Dictionary:
	var dom := get_dominant_species()
	var extinct := []
	for id in origin.get_alive_species():
		if species.has(id) and not species[id].alive:
			extinct.append({id = id, name = species[id].name, clade = species[id].traits.clade})
	var sapients := []
	for id in get_sapient_species():
		sapients.append({id = id, name = species[id].name, clade = species[id].traits.clade,
			tech_level = species[id].tech_level})
	var new_count := 0
	for ev in events:
		if ev.type == "speciation" or ev.type == "spawn":
			new_count += 1
	var keyed := []
	for ev in events:
		var w: int = KEY_EVENT_WEIGHT.get(ev.type, 0)
		if w > 0:
			keyed.append([w, ev])
	keyed.sort_custom(func(x, y): return x[0] > y[0] or (x[0] == y[0] and x[1].year < y[1].year))
	var key_events: Array[Dictionary] = []
	for i in mini(12, keyed.size()):
		key_events.append(keyed[i][1])
	key_events.sort_custom(func(x, y): return x.year < y.year)
	return {
		from_year = origin.year, to_year = year, era = current_era(), era_index = _era_idx,
		era_reached = ERAS[era_reached],
		dominant_species = {id = dom, name = species[dom].name if dom >= 0 else "",
			clade = species[dom].traits.clade if dom >= 0 else ""},
		sapient_species = sapients, extinct_species = extinct, new_species = new_count,
		events_count = events.size(), key_events = key_events,
	}


## Mesure (moyenne en ms) d'un pas à la vitesse par défaut, sur une copie : n'altère pas ce monde.
func benchmark(steps := 60, years_per_step := 1_000_000.0 / 60.0, threaded := true) -> float:
	var f: RefCounted = fork()
	f._eco.threaded = threaded
	f.step(years_per_step)
	var t0 := Time.get_ticks_usec()
	for i in steps:
		f.step(years_per_step)
	return (Time.get_ticks_usec() - t0) / 1000.0 / float(steps)


# =============================================================================================
# Création du monde
# =============================================================================================

func _seed_roster() -> void:
	var ids: Array[int] = []
	for def in Species.ROSTER:
		ids.append(_create_species(def.name, Species.traits_from_def(def), -1, -1))
	# Répartition initiale : chaque région garde les K espèces les mieux adaptées (tirage pondéré).
	var goff := _global_offset()
	for r in Ecosystem.NR:
		if _eco.r_land[r] <= 0.0:
			continue
		var scored := []
		for id in ids:
			var idx: int = _rt[id].idx
			var suit: float = _eco.suitability(idx, r, goff)
			if suit > 0.15:
				scored.append([suit * _rng.randf_range(0.4, 1.0), idx, suit])
		scored.sort_custom(func(x, y): return x[0] > y[0])
		var cap: float = _eco.r_land[r] * _eco.r_fert[r]
		for k in mini(Ecosystem.K, scored.size()):
			_eco.cur_sp[r * Ecosystem.K + k] = scored[k][1]
			_eco.cur_pop[r * Ecosystem.K + k] = cap * scored[k][2] * 0.4


## Prologue : les trois lignées microbiennes peuplent toutes les mers.
func _seed_prologue() -> void:
	var ids: Array[int] = []
	for def in Species.PROLOGUE_ROSTER:
		ids.append(_create_species(def.name, Species.traits_from_def(def), -1, -1))
	var goff := _global_offset()
	for r in Ecosystem.NR:
		var sea: float = _eco.r_sea[r]
		if sea <= 0.0:
			continue
		var k := 0
		for id in ids:
			var idx: int = _rt[id].idx
			var suit: float = _eco.suitability(idx, r, goff)
			# Les cyanobactéries ne sont d'abord qu'une lignée discrète parmi d'autres.
			var share := 0.15 if Species.PROLOGUE_ROSTER[k].oxygenic else 0.4
			_eco.cur_sp[r * Ecosystem.K + k] = idx
			_eco.cur_pop[r * Ecosystem.K + k] = maxf(sea * suit * share, Ecosystem.EXTINCT_EPS * 3.0)
			k += 1


func _land_life_count() -> int:
	for id in _alive:
		if species[id].traits.get("habitat", "land") != "marine":
			return 1
	return 0


## Crée une espèce. Renvoie son id public (-1 si la table des espèces vivantes est pleine).
func _create_species(p_name: String, traits: Dictionary, parent_id: int, origin_event: int) -> int:
	var idx: int = _eco.alloc_index()
	if idx < 0:
		return -1
	var id := _next_species_id
	_next_species_id += 1
	species[id] = {
		name = p_name, alive = true, sapient = false, population = 0.0, traits = traits,
		clade = traits.clade, parent = parent_id, born_year = year, extinct_year = NAN,
		tech_level = 0.0, regions = 0,
	}
	var prt: Dictionary = _rt.get(parent_id, {})
	_rt[id] = {
		idx = idx, protect_until = -INF, radiation_until = prt.get("radiation_until", -INF),
		radiation_cause = prt.get("radiation_cause", -1), harm_cause = -1, harm_until = -INF,
		lineage_cause = prt.get("lineage_cause", -1), origin_event = origin_event,
		tech_cause = -1, last_event = -1, last_event_year = -INF, mods = [], milestone = 0,
		sample = -1, last_region = -1, ov_tech = 0.0, scientific_name = p_name,
	}
	_eco.t_alive[idx] = 1
	_eco.t_id[idx] = id
	_eco.t_protect[idx] = 0
	_alive.append(id)
	_refresh_species(id)
	_prune_records()
	return id


func _prune_records() -> void:
	if species.size() <= MAX_SPECIES_RECORDS:
		return
	for id in species.keys():
		@warning_ignore("integer_division")
		if species.size() <= MAX_SPECIES_RECORDS * 3 / 4:
			break
		if not species[id].alive:
			species.erase(id)
			_rt.erase(id)


## Recalcule les tables compactes d'une espèce (traits, technologie) et sa ligne de chevauchement.
func _refresh_species(id: int) -> void:
	var sp: Dictionary = species[id]
	var t: Dictionary = sp.traits
	var rt: Dictionary = _rt[id]
	var idx: int = rt.idx
	var sap: bool = sp.sapient
	var level: float = sp.tech_level
	_eco.t_diet[idx] = Species.diet_index(t)
	_eco.t_hab[idx] = Species.habitat_index(t)
	_eco.t_cx[idx] = float(t.get("complexity", 6.0))
	_eco.t_anaer[idx] = 1 if bool(t.get("anaerobic", false)) else 0
	_eco.t_topt[idx] = t.temp_opt
	_eco.t_tol[idx] = t.temp_tol + ((0.06 + 0.03 * level) if sap else 0.0)
	var c := Species.competitiveness(t, level, sap)
	_eco.t_comp[idx] = c
	_eco.t_icomp[idx] = 1.0 / c
	_eco.t_growth[idx] = Species.growth_rate(t, sap)
	_eco.t_disp[idx] = Species.dispersal_rate(t, level, sap)
	_eco.t_vis[idx] = (0.3 + float(t["size"])) * ((6.0 + level) if sap else 1.0) \
		* (0.15 if Species.is_autotroph(t) else 1.0)
	_eco.t_tech[idx] = (0.05 + level / Eras.MAX_TECH * 0.95) if sap else 0.0
	_eco.t_capmul[idx] = (1.0 + 0.12 * level) if sap else 1.0
	rt.ov_tech = level
	var m := Ecosystem.MAXS
	for other in _alive:
		var j: int = _rt[other].idx
		var o_sp: Dictionary = species[other]
		var ov := Species.overlap(t, o_sp.traits)
		# t_ov[a * MAXS + b] = pression exercée SUR a PAR b. Un peuple sapient presse toutes les
		# espèces (chasse, défrichage) sans subir en retour la pression des animaux.
		var ov_ij := ov
		var ov_ji := ov
		if sap:
			ov_ji = maxf(ov_ji, 0.1 + 0.02 * level)
		if o_sp.sapient:
			ov_ij = maxf(ov_ij, 0.1 + 0.02 * float(o_sp.tech_level))
		_eco.t_ov[idx * m + j] = ov_ij
		_eco.t_ov[j * m + idx] = ov_ji
	_eco.set_oxygen(oxygen, Species.OXYGEN_NEED)


# =============================================================================================
# Pas de simulation
# =============================================================================================

## Luminosité relative du Soleil (1 = aujourd'hui) : ~0,65 à -4 Ga, +8,7 % par milliard d'années.
func _luminosity() -> float:
	return float(planet.get("star_luminosity", 1.0)) * (1.0 + SUN_BRIGHTENING_PER_GA * year / 1.0e9)


## Effet du Soleil sur l'échelle de température : direct, et emballement au-delà de la
## luminosité actuelle (vapeur d'eau). Vaut -0,22 à -3,8 Ga (soleil jeune et pâle).
func _sun_term() -> float:
	var dl := _luminosity() - 1.0
	return SUN_TEMPERATURE_GAIN * dl + SUN_RUNAWAY_GAIN * maxf(0.0, dl)


func _global_offset() -> float:
	# Refroidissement du Cénozoïque (+0.06 au Crétacé -> 0 à -3 Ma) + réchauffement industriel.
	var baseline := clampf((-3.0e6 - year) / 63.0e6, 0.0, 1.0) * 0.06
	var lead := _leading_tech()
	var warming := clampf((lead - 4.0) * 0.03, 0.0, 0.09)
	return baseline + warming + _climate_anom + _proto + _sun_warming()


## Le Soleil vieillit : après l'an 0, la Terre se réchauffe (~0,3 de l'échelle de température par
## milliard d'années) ; vers +1 Ga, la vie complexe n'y tient plus.
func _sun_warming() -> float:
	if _deep_time():
		return 0.0  # déjà compté dans le climat du temps profond (_climate_step)
	return maxf(0.0, _sun_term())


func _complex_room() -> float:
	return 1.0 - smoothstep(SUN_COMPLEX_LIMIT.x, SUN_COMPLEX_LIMIT.y, maxf(0.0, _sun_term()))


## Part des terres encore habitables : couche d'ozone (UV) et eau (océans qui s'évaporent).
func _land_room() -> float:
	var shield := ozone if _deep_time() else 1.0
	return shield * (1.0 - _evaporation)


## Niveau marin : émergence lente des continents puis climat (glaciations basses, serre haute).
func _update_sea_level(dt: float) -> void:
	var start := GENESIS_START_YEAR if scenario == SCENARIO_GENESIS else PROLOGUE_START_YEAR
	var frac := clampf((LAND_EMERGENCE_YEAR - year) / (LAND_EMERGENCE_YEAR - start), 0.0, 1.0)
	var freeboard := SEA_FREEBOARD * pow(frac, SEA_FREEBOARD_POWER)
	var climate := clampf(_global_offset() - 0.06, -0.3, 0.15) * SEA_CLIMATE_GAIN
	# Tectonique : un supercontinent laisse peu de dorsales jeunes (mers basses), une dispersion
	# beaucoup (mers hautes). Puis les océans s'évaporent sous le vieux Soleil.
	var tect := 0.0
	if _tect != null:
		tect = -0.01 if _tect.phase == "supercontinent" else (0.008 if _tect.phase == "dispersal" else 0.0)
	var target := freeboard + climate + tect - _evaporation * 1.2
	sea_level = target if dt <= 0.0 else target + (sea_level - target) * exp(-dt / SEA_LEVEL_TAU)


func _substep(dt: float, out: Array[Dictionary]) -> void:
	_step_count += 1
	year += dt
	if year > _mig_until:
		_mig_mult = 1.0
	_eco.set_oxygen(oxygen, Species.OXYGEN_NEED, _complex_room(), _land_room())
	_eco.prepare(dt, _mig_mult)
	_run_ecosystem()
	_update_species_stats(out)
	if _deep_time():
		_planet_step(dt, out)
		_update_sea_level(dt)
	_update_planet_state(dt, out)
	if _tect != null:
		_geo_step(dt, out)
	_life_cycle_step(dt, out)
	_evolve(dt, out)
	_advance_civilisations(dt, out)
	_natural_events(dt, out)
	_process_scheduled(out)
	_decay(dt)
	_update_era(out)
	_record_planet()


## 1 s'il existe de la vie (les méthanogènes cachés des eaux profondes en font partie), 0 sinon.
func _life_present() -> float:
	return 0.0 if _alive.is_empty() else 1.0


func _deep_time() -> bool:
	return scenario != SCENARIO_CRETACEOUS


func _run_ecosystem() -> void:
	var goff := _global_offset()
	# Réécriture de la grille de température seulement si le climat a bougé (coûteux : 32k cellules) ;
	# les anomalies régionales qui s'estompent sont rafraîchies un sous-pas sur quatre.
	var temp_dirty := absf(goff - _goff_written) > 0.004 or (_regional_active and _step_count % 4 == 0)
	var biome_dirty := temp_dirty and absf(goff - _biome_goff) > 0.04
	_eco.run(_step_count, _seed_hash, goff, temp_dirty, biome_dirty)
	if temp_dirty:
		_goff_written = goff
	if biome_dirty:
		_biome_goff = goff
	_eco.flush_free()


## Repasse le noyau avec dt = 0 : purge les niches mortes, met à jour les grilles et les stats
## immédiatement après une action divine (pas d'évolution du temps).
func _refresh_view(out: Variant = null) -> void:
	_eco.prepare(0.0, 1.0)
	_goff_written = 1e9
	_run_ecosystem()
	var sink: Array[Dictionary] = []
	_update_species_stats(out if out != null else sink)


func _update_species_stats(out: Array[Dictionary]) -> void:
	for id in _alive.duplicate():
		var sp: Dictionary = species[id]
		var rt: Dictionary = _rt[id]
		var idx: int = rt.idx
		_eco.reduce_stats(idx, _step_count + id)
		sp.population = _eco.stat_pop
		sp.regions = _eco.stat_cnt
		rt.sample = _eco.stat_sample
		if _eco.stat_sample >= 0:
			rt.last_region = _eco.stat_sample
		var protected: bool = rt.protect_until >= year
		_eco.t_protect[idx] = 1 if protected else 0
		if _eco.stat_cnt == 0 or _eco.stat_pop < Ecosystem.EXTINCT_EPS * 2.0:
			if protected and rt.last_region >= 0:
				# Une espèce protégée par Dieu survit en population relique.
				_eco.place_species(idx, rt.last_region, 0, 0.05)
				continue
			_extinguish(id, _harm_cause(id), out)


func _harm_cause(id: int) -> int:
	var rt: Dictionary = _rt[id]
	if rt.harm_until >= year and rt.harm_cause > 0:
		return rt.harm_cause
	if _climate_cause_until >= year and _climate_cause > 0:
		return _climate_cause
	# Une espèce toute jeune qui s'éteint : c'est sa naissance (spéciation, création) qui a échoué.
	if year - float(species[id].born_year) < Eras.time_unit(_era_idx) * 2.0 and rt.origin_event > 0:
		return rt.origin_event
	# Exclusion compétitive : la cause est l'apparition de l'espèce qui domine son dernier refuge.
	if rt.last_region >= 0:
		var dom_idx: int = _eco.r_dom[rt.last_region]
		if dom_idx >= 0:
			var cid: int = _eco.t_id[dom_idx]
			if cid != id and _rt.has(cid):
				var crt: Dictionary = _rt[cid]
				if species[cid].sapient and crt.tech_cause > 0:
					return crt.tech_cause
				return crt.origin_event
	return -1


func _extinguish(id: int, cause: int, out: Array[Dictionary], how := "") -> Dictionary:
	var sp: Dictionary = species[id]
	var rt: Dictionary = _rt[id]
	sp.alive = false
	sp.extinct_year = year
	sp.population = 0.0
	sp.regions = 0
	_eco.release_index(rt.idx)
	_alive.erase(id)
	_recent_ext.append(year)
	_ext_years.append(year)
	if _ext_years.size() > 256:
		_ext_years = _ext_years.slice(_ext_years.size() - 256)
	var text := "Extinction : les %s disparaissent" % sp.name
	if how != "":
		text += " (%s)" % how
	if sp.sapient:
		text = "Effondrement total : la civilisation des %s s'éteint" % sp.name
	var ev := _event("extinction", _cell_of(rt.last_region), id, text, cause, out)
	if sp.traits.clade == "dinosaure":
		_last_dino_extinction = ev.id
	return ev


func _evolve(dt: float, out: Array[Dictionary]) -> void:
	var n_alive := _alive.size()
	var diversity := clampf(1.0 - float(n_alive) / DIVERSITY_TARGET, 0.0, 1.0)
	var per_clade := {}
	if _deep_time():
		diversity = clampf(1.0 - float(n_alive) / PROLOGUE_DIVERSITY, MIN_DIVERSITY, 1.0)
		for id in _alive:
			var key := _niche_key(species[id].traits)
			per_clade[key] = int(per_clade.get(key, 0)) + 1
	# Pression vers la complexité : tant qu'aucun esprit n'a émergé, elle croît avec le temps
	# (convergence évolutive). Garantit qu'une civilisation finit par naître, quelle que soit la graine.
	var pressure := 1.0
	# Avant le tout premier esprit seulement : ensuite, la nature a le temps de se reconstituer
	# entre deux civilisations.
	if _leading_species() < 0 and not _had_civilization:
		pressure = minf(MAX_COMPLEXITY_PRESSURE, 1.0 + maxf(0.0, year + 66.0e6) / COMPLEXITY_PRESSURE_YEARS)
	for id in _alive.duplicate():
		if not species.has(id) or not species[id].alive:
			continue
		var sp: Dictionary = species[id]
		var t: Dictionary = sp.traits
		var rt: Dictionary = _rt[id]
		if sp.sapient:
			continue
		var success := 0.3 + 0.7 * minf(1.0, float(sp.regions) / 60.0)
		# Dérive d'intelligence : généralistes de taille moyenne et prospères.
		var bias: float = (1.0 if t.diet == "omnivore" else 0.45) * (0.4 + t.adaptability) \
			* clampf(1.0 - absf(float(t["size"]) - 0.35) * 1.6, 0.1, 1.0)
		var i0: float = t.intelligence
		var cap := _brain_cap(t)
		# Linéaire en dt : le résultat ne dépend pas du découpage en sous-pas.
		var di: float = dt / 1.0e6 * INTELLIGENCE_DRIFT * bias * success * pressure * (1.0 if i0 > 0.2 else 0.3) 			* _brain_maturity()
		if Species.is_autotroph(t):
			di = 0.0
		t.intelligence = i0 if i0 >= cap else minf(cap, i0 + di)
		if t.intelligence >= Species.SAPIENCE_THRESHOLD and sp.regions >= 3:
			_become_sapient(id, out)
			continue
		# Spéciation.
		var rad := 4.0 if rt.radiation_until >= year else 1.0
		# Un clade saturé ne se divise plus qu'en fondant un nouveau clade (voir _speciate).
		var room := 1.0
		if not per_clade.is_empty():
			room = clampf(1.0 - float(per_clade.get(_niche_key(t), 0)) / _key_cap(float(t.complexity)), 0.0, 1.0)
		var p: float = dt * SPECIATION_RATE * (0.4 + t.adaptability) * minf(1.0, sp.regions / 12.0) * rad * diversity
		# Nombre de spéciations proportionnel à dt (jusqu'à 3 par sous-pas) : l'évolution ne
		# dépend pas du découpage du temps, même avec les grands pas du prologue.
		var n := mini(3, int(floorf(p)) + (1 if _rng.randf() < p - floorf(p) else 0))
		for k in n:
			if _speciate(id, out, room, per_clade) < 0:
				break


func _speciate(parent_id: int, out: Array[Dictionary], room := 1.0, crowd := {}) -> int:
	var psp: Dictionary = species[parent_id]
	var prt: Dictionary = _rt[parent_id]
	var founder: int = prt.sample
	if founder < 0 or _eco.capacity_left() <= 0:
		return -1
	# Une lignée qui ne trouve plus de quoi vivre ne se divise plus (sinon des espèces fantômes
	# renaîtraient à chaque pas d'un monde devenu inhabitable).
	var goff0 := _global_offset()
	if _eco.habitat_base(prt.idx, founder) * _eco.suitability(prt.idx, founder, goff0) <= 0.002:
		return -1
	var radiating: bool = prt.radiation_until >= year
	var ftemp: float = _eco.region_temperature(founder, _global_offset())
	var traits := Species.mutate(psp.traits, _rng, ftemp, 1.0 if radiating else 0.0, oxygen)
	var rule := _pick_transition(psp.traits, radiating, crowd)
	if rule.is_empty() and room < 1.0 and _rng.randf() >= room:
		return -1
	var child_name := ""
	if not rule.is_empty():
		Species.apply_transition(traits, rule, _rng)
		child_name = _group_name(rule)
	if _deep_time():
		traits.intelligence = lerpf(float(traits.intelligence), BRAIN_BASELINE, BRAIN_RECALL)
	traits.intelligence = minf(float(traits.intelligence), maxf(_brain_cap(traits), float(psp.traits.intelligence)))
	if child_name == "":
		var new_genus := Species.divergence(psp.traits, traits) > 0.3 or _rng.randf() < 0.15
		child_name = Species.make_name(prt.scientific_name, _rng, new_genus)
	var cause: int = prt.radiation_cause if radiating and prt.radiation_cause > 0 else prt.origin_event
	if prt.lineage_cause > 0 and not radiating:
		cause = prt.lineage_cause
	var child := _create_species(child_name, traits, parent_id, -1)
	if child < 0:
		return -1
	if not crowd.is_empty():
		var key := _niche_key(traits)
		crowd[key] = int(crowd.get(key, 0)) + 1
	var ev: Dictionary
	if rule.is_empty():
		ev = _event("speciation", _cell_of(founder), child,
			"Spéciation : %s se sépare des %s" % [child_name, psp.name], cause, out)
	else:
		ev = _event("clade", _cell_of(founder), child, "%s : les %s (%s) naissent des %s" % [
			_clade_headline(traits), child_name, traits.clade, psp.name], cause, out)
	_rt[child].origin_event = ev.id
	var cidx: int = _rt[child].idx
	if traits.habitat != psp.traits.get("habitat", "land"):
		# Changement de milieu : la lignée naît sur le rivage le plus proche.
		founder = _nearest_coast(founder)
	if _eco.place_species(cidx, founder, 2, 0.1, prt.idx) == 0:
		if _eco.place_species(cidx, founder, 0, 0.1) == 0:
			_eco.place_species(cidx, founder, 2, 0.1)
	return child


## Clé de diversité : un clade à un niveau de complexité (les algues multicellulaires ne
## disputent pas leur place aux unicellulaires).
func _niche_key(t: Dictionary) -> String:
	return "%s%d" % [t.get("clade", ""), int(t.get("complexity", 6.0))]


func _key_cap(complexity: float) -> int:
	return TETRAPOD_DIVERSITY if complexity >= 5.0 else CLADE_DIVERSITY


func _nearest_coast(r: int) -> int:
	for rad in range(0, 9):
		for rr in _eco.regions_in_radius(r, rad):
			if _eco.r_land[rr] > 0.0 and _eco.r_sea[rr] > 0.0:
				return rr
	return r


## Une transition de clade (Species.TRANSITIONS) tentée à la spéciation, selon l'état du monde.
func _pick_transition(parent: Dictionary, radiating: bool, crowd := {}) -> Dictionary:
	# Le scénario du Crétacé part de son roster cible : ses lignées ne fondent pas de clades,
	# sauf après une renaissance de la vie.
	if scenario == SCENARIO_CRETACEOUS and rebirths == 0:
		return {}
	var clade := String(parent.get("clade", ""))
	var c := float(parent.get("complexity", 6.0))
	for k in Species.TRANSITIONS.size():
		var rule: Dictionary = Species.TRANSITIONS[k]
		if rule.from != clade or c < float(rule.get("min_c", -1.0)) or c > float(rule.get("max_c", 99.0)):
			continue
		if oxygen < float(rule.oxygen) or land_flora < float(rule.get("flora", 0.0)):
			continue
		if int(crowd.get("%s%d" % [rule.to, int(rule.complexity)], 0)) >= _key_cap(float(rule.complexity)):
			continue
		if not _rule_ready.has(k):
			_rule_ready[k] = year
		var chance := CLADE_TRANSITION_RATE * float(rule.weight)
		if rule.to != rule.from:
			var waited := (year - float(_rule_ready[k])) / TRANSITION_RAMP
			chance *= 1.0 + waited * waited
		if bool(rule.get("radiation", false)):
			chance *= RADIATION_TRANSITION_BOOST if radiating else 0.4
		elif radiating:
			chance *= 2.0
		if _rng.randf() < chance:
			return rule
	return {}


## Nom de groupe du nouveau clade (Species.GROUP_NAMES dans l'ordre), "" quand la liste est épuisée.
func _group_name(rule: Dictionary) -> String:
	if rule.has("name") and not _groups.has(rule.name):
		_groups[rule.name] = 1
		return rule.name
	var names: Array = Species.GROUP_NAMES.get(rule.to, [])
	var n: int = _groups.get(rule.to, 0)
	if n >= names.size():
		return ""
	_groups[rule.to] = n + 1
	return names[n]


func _clade_headline(t: Dictionary) -> String:
	match String(t.habitat):
		"land":
			return "Conquête des terres" if float(t.complexity) < 6.0 else "Nouvelle lignée"
		"amphibious":
			return "Sortie des eaux"
	return "Nouvelle lignée"


## Plafond d'intelligence : la vie simple n'a pas de cerveau, poissons et amphibiens guère.
func _brain_cap(t: Dictionary) -> float:
	var c := float(t.get("complexity", 6.0))
	if Species.is_autotroph(t) or c < 4.0:
		return 0.05 + 0.02 * c
	if c < 6.0:
		return 0.25
	return 1.0


## 0..1 : maturité des cerveaux d'amniotes (1 dans le scénario du Crétacé).
func _brain_maturity() -> float:
	if not _deep_time():
		return 1.0
	var m := clampf((year - _amniote_year) / BRAIN_YEARS, 0.0, 1.0)
	return m * m * m


func _become_sapient(id: int, out: Array[Dictionary]) -> void:
	var sp: Dictionary = species[id]
	var rt: Dictionary = _rt[id]
	var old_name: String = sp.name
	var title := Species.sapient_title(sp.traits)
	for other in species:
		if species[other].sapient and species[other].name == title:
			title += " " + Species.make_name(old_name, _rng, false).split(" ")[1].capitalize()
			break
	sp.sapient = true
	sp.tech_level = 0.0
	sp.name = title
	_had_civilization = true
	# Cause de l'éveil : ce qui a façonné la lignée (geste divin), sinon la catastrophe dont elle a
	# profité (radiation adaptative), sinon sa naissance.
	var cause: int = rt.lineage_cause
	if cause <= 0:
		cause = rt.radiation_cause if rt.radiation_cause > 0 else rt.origin_event
	var ev := _event("sapience", _cell_of(rt.last_region), id,
		"Éveil : les %s (%s) accèdent à la conscience — naissance des %s" % [old_name, sp.traits.clade, title],
		cause, out)
	rt.tech_cause = ev.id
	rt.milestone = 0
	_refresh_species(id)


func _leading_species() -> int:
	var best := -1
	var best_l := -1.0
	for id in _alive:
		var sp: Dictionary = species[id]
		if sp.sapient and sp.tech_level > best_l:
			best_l = sp.tech_level
			best = id
	return best


func _leading_tech() -> float:
	var lead := _leading_species()
	return species[lead].tech_level if lead >= 0 else 0.0


func _advance_civilisations(dt: float, out: Array[Dictionary]) -> void:
	for id in _alive.duplicate():
		if not species.has(id) or not species[id].alive or not species[id].sapient:
			continue
		var sp: Dictionary = species[id]
		var rt: Dictionary = _rt[id]
		var t: Dictionary = sp.traits
		var kept := []
		for m in rt.mods:
			if m.until >= year:
				kept.append(m)
		rt.mods = kept
		var speed := _tech_speed(id)
		var level: float = sp.tech_level
		# Au plus un tiers de niveau par sous-pas : même un pas géant traverse les ères une à une,
		# avec leurs jalons et leurs événements, au lieu de sauter directement au futur.
		level = minf(Eras.integrate_tech(level, dt, speed), level + 0.34)
		sp.tech_level = level
		_check_milestones(id, out)
		if absf(level - rt.ov_tech) >= 0.25:
			_refresh_species(id)
		_civ_random_events(id, dt, out)


func _check_milestones(id: int, out: Array[Dictionary]) -> void:
	var sp: Dictionary = species[id]
	var rt: Dictionary = _rt[id]
	var guard := 0
	while guard < 32:
		guard += 1
		var m: int = rt.milestone
		@warning_ignore("integer_division")
		var lvl := m / 3
		if lvl >= Eras.MILESTONES.size():
			return
		var value := float(lvl) + float(m % 3 + 1) * 0.25
		if sp.tech_level < value:
			return
		var ev := _event("discovery", _cell_of(rt.last_region), id,
			"Les %s %s" % [sp.name, Eras.MILESTONES[lvl][m % 3]], rt.tech_cause, out)
		rt.tech_cause = ev.id
		rt.milestone = m + 1


## Guerres, épidémies, âges d'or, découvertes : taux exprimés en occurrences par niveau technologique.
func _civ_random_events(id: int, dt: float, out: Array[Dictionary]) -> void:
	var sp: Dictionary = species[id]
	var rt: Dictionary = _rt[id]
	var t: Dictionary = sp.traits
	var level: float = sp.tech_level
	var span := Eras.level_years(level)
	var unit := Eras.time_unit(_era_idx)
	# Cause d'un événement spontané : le dernier événement subi récemment par ce peuple.
	var recent: int = rt.last_event if year - float(rt.last_event_year) < unit * 3.0 else -1
	var region := _cell_of(rt.sample)
	if _chance(dt, 2.5 * (0.4 + float(t.aggression)) / span):
		var foe := -1
		for other in get_sapient_species():
			if other != id:
				foe = other
				break
		var text := "Guerre : les %s se déchirent en conflits fratricides" % sp.name
		if foe >= 0:
			text = "Guerre : les %s affrontent les %s" % [sp.name, species[foe].name]
		var ev := _event("war", region, id, text, recent, out)
		var hit: Dictionary = _eco.kill_area(rt.sample, 3, 0.4)
		_mark_harm(hit, ev.id, unit * 2.0)
		if foe >= 0:
			_eco.kill_area(_rt[foe].sample, 3, 0.5, _rt[foe].idx)
			_note(foe, ev.id)
		if _rng.randf() < 0.45:
			sp.tech_level = minf(Eras.MAX_TECH, level + 0.05)
			rt.tech_cause = ev.id
		else:
			sp.tech_level = maxf(0.0, level - 0.04)
		_note(id, ev.id)
	if level >= 0.75 and _chance(dt, 1.2 * clampf(sp.population / 200.0, 0.2, 1.5) / span):
		var ev := _event("plague", region, id, "Épidémie : une peste ravage les %s" % sp.name, recent, out)
		_eco.scale_species(rt.idx, 0.7)
		sp.tech_level = maxf(0.0, sp.tech_level - 0.03)
		_note(id, ev.id)
		causal_log.schedule(year + unit * 2.0, "plague_wave", ev.id, region, id, 0.4)
	if _chance(dt, 1.0 * (1.2 - float(t.aggression)) / span):
		var ev := _event("golden_age", region, id, "Âge d'or : les %s connaissent une ère de prospérité" % sp.name, recent, out)
		rt.mods.append({factor = 1.8, until = year + 0.15 * span, cause = ev.id})
		rt.tech_cause = ev.id
		_note(id, ev.id)
		causal_log.schedule(year + 0.15 * span, "decline", ev.id, region, id, 0.35)
	if endless and level >= EXHAUSTION_LEVEL and _chance(dt, EXHAUSTION_RATE / span):
		# Les civilisations accomplies s'épuisent : ressources, guerres, effondrement.
		var ev := _event("collapse", region, id, "Effondrement : la civilisation des %s s'écroule sous son propre poids" % sp.name, recent, out)
		sp.tech_level = maxf(0.0, level - _rng.randf_range(1.0, 2.0))
		_eco.scale_species(rt.idx, 0.5)
		_mark_harm({rt.idx: true}, ev.id, unit * 2.0)
		rt.tech_cause = ev.id
		_note(id, ev.id)
		return
	if endless and level >= Eras.MAX_TECH and _chance(dt, EXODUS_RATE):
		_exodus(id, out)
		return
	if _chance(dt, 1.0 / span):
		var ev := _event("discovery", region, id, "Percée : un génie des %s fait faire un bond au savoir" % sp.name, rt.tech_cause, out)
		sp.tech_level = minf(Eras.MAX_TECH, sp.tech_level + 0.08)
		rt.tech_cause = ev.id
		_note(id, ev.id)


## Exode : la civilisation accomplie quitte la Terre ; ses villes deviennent des ruines que la
## nature reprendra. L'espèce n'est pas éteinte : elle est partie (departed = true).
func _exodus(id: int, out: Array[Dictionary]) -> void:
	var sp: Dictionary = species[id]
	var rt: Dictionary = _rt[id]
	var ev := _event("exodus", _cell_of(rt.last_region), id,
		"Exode : les %s quittent la Terre pour les étoiles et laissent leurs villes au silence" % sp.name, rt.tech_cause, out)
	sp.alive = false
	sp.departed = true
	sp.extinct_year = year
	sp.population = 0.0
	sp.regions = 0
	_eco.scale_species(rt.idx, 0.0)
	_eco.release_index(rt.idx)
	_alive.erase(id)
	_planet_cause = ev.id


## Ozone, glaces, Soleil, habitabilité, fin des temps.
func _update_planet_state(dt: float, out: Array[Dictionary]) -> void:
	sun_luminosity = _luminosity()
	_evaporation = smoothstep(OCEAN_LOSS.x, OCEAN_LOSS.y, sun_luminosity)
	if _deep_time():
		# L'oxygène fait l'ozone ; les UV d'un Soleil vieilli et l'industrie l'abîment.
		var heal := exp(-dt / maxf(Eras.time_unit(_era_idx), 1.0))
		_ozone_damage *= heal
		var lead := _leading_tech()
		if lead >= 5.0:
			_ozone_damage = maxf(_ozone_damage, 0.15 * (lead - 5.0))
		_ozone_damage = maxf(_ozone_damage, 0.6 * smoothstep(1.15, 1.35, sun_luminosity))
		ozone = smoothstep(0.08, 0.3, oxygen) * (1.0 - clampf(_ozone_damage, 0.0, 1.0))
	else:
		ozone = 1.0
	var iced := 0
	var k := 0
	for i in range(0, temperature.size(), 23):
		k += 1
		if temperature[i] < (0.08 if elevation[i] < 0.0 else 0.12):
			iced += 1
	ice_cover = float(iced) / maxf(1.0, k)
	habitability = clampf(0.6 * _complex_room() + 0.4 * (1.0 - _evaporation), 0.0, 1.0)
	if _evaporation >= 0.999:
		habitability = 0.0
	if not end_of_times and habitability <= 0.0 and _alive.is_empty() and dt > 0.0:
		end_of_times = true
		_event("end_of_times", Vector2i(-1, -1), -1,
			"Fin des temps : les océans se sont évaporés sous le vieux Soleil ; la planète est stérile à jamais",
			_planet_cause, out)


func _record_planet() -> void:
	if year < _next_planet_sample and not planet_history.is_empty():
		return
	var st := planet_stats()
	planet_history.append({year = year, global_temperature_c = st.global_temperature_c, ozone = ozone,
		oxygen = oxygen, co2 = st.co2, sea_level = sea_level, ice_cover = ice_cover, biomass = st.biomass,
		biodiversity = st.biodiversity})
	if planet_history.size() > PLANET_HISTORY_SIZE:
		planet_history.pop_front()
	_next_planet_sample = year + ideal_step_years() * PLANET_SAMPLE_STEPS


# =============================================================================================
# Tectonique
# =============================================================================================

## Fait avancer les plaques ; lance le recalcul de la géographie sur un fil de travail et le
## rejoint GEO_JOIN_SUBSTEPS sous-pas plus tard (déterministe : les points de rendez-vous ne
## dépendent que du nombre de sous-pas).
func _geo_step(dt: float, out: Array[Dictionary]) -> void:
	for change in _tect.advance(dt, year):
		_tectonic_event(change, out)
	_geo_substeps += 1
	var lagging := year - _last_geo_year >= GEO_MAX_LAG
	if _geo_task != -1 and (_geo_substeps >= GEO_JOIN_SUBSTEPS or lagging):
		_join_geography(out)
	if _geo_task == -1 and year >= _next_geo and (_geo_substeps >= GEO_JOIN_SUBSTEPS or lagging):
		_next_geo = year + GEO_INTERVAL
		_geo_substeps = 0
		var snap: Dictionary = _tect.snapshot()
		snap.erosion = exp(-(year - _last_geo_year) / Tectonics.EROSION_YEARS)
		_last_geo_year = year
		var craters := _crater_list()
		var sl := sea_level
		if _eco.threaded:
			_geo_result = {}
			_geo_task = WorkerThreadPool.add_task(func(): _geo_result = _geo_work(snap, sl, craters), false, "WorldSim.tectonique")
		else:
			_geo_result = _geo_work(snap, sl, craters)
			_geo_task = -2


func _join_geography(out: Array[Dictionary]) -> void:
	if _geo_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_geo_task)
	_geo_task = -1
	if not _geo_result.is_empty():
		_apply_geography(_geo_result, out)
	_geo_result = {}


## Calcul pur (fil de travail) : relief, climat de base, biomes, agrégats de l'écosystème.
func _geo_work(snap: Dictionary, sl: float, craters: Array) -> Dictionary:
	var res: Dictionary = _tect.raster(snap, _ocean_noise, sl, craters)
	var count := WIDTH * HEIGHT
	var bt := PackedFloat32Array()
	var mo := PackedFloat32Array()
	var bi := PackedByteArray()
	bt.resize(count)
	mo.resize(count)
	bi.resize(count)
	WorldGen.derive_climate(res.elevation, _temp_lat, _moist_lat, res.coast_dist, bt, mo, bi)
	res.base_temp = bt
	res.moisture = mo
	res.biome = bi
	res.eco = Ecosystem.compute_static(res.elevation, bt, bi)
	return res


func _apply_geography(res: Dictionary, out: Array[Dictionary]) -> void:
	elevation = res.elevation
	_base_temp = res.base_temp
	moisture = res.moisture
	biome = res.biome
	plate_id = res.plate_id
	plate_boundary = res.boundary
	_coast_dist = res.coast_dist
	_eco.apply_static(res.eco)
	_eco.bind_grids(self)
	_land_regions = 0
	_sea_regions = 0
	for r in Ecosystem.NR:
		if _eco.r_land[r] > 0.0:
			_land_regions += 1
		if _eco.r_sea[r] > 0.0:
			_sea_regions += 1
	_land_regions = maxi(_land_regions, 1)
	_sea_regions = maxi(_sea_regions, 1)
	_goff_written = 1e9
	_biome_goff = 1e9
	supercontinent_fraction = res.supercontinent_fraction
	_tect.supercontinent_fraction = supercontinent_fraction
	_tect.crust_fraction = float(res.crust_fraction)
	var sutures := _tect.apply_contacts(res.contacts, year)
	if not sutures.is_empty():
		# Une seule annonce par recalcul, même si plusieurs plaques se soudent à la fois.
		var cause := -1
		for c in sutures:
			cause = maxi(cause, maxi(int(_tect.p_cause[c.a]), int(_tect.p_cause[c.b])))
		var first: Dictionary = sutures[0]
		var mid := _tect.plate_position(first.a, 0.0, 0.0).lerp(_tect.plate_position(first.b, 0.0, 0.0), 0.5)
		var ev := _event("orogeny", Vector2i(int(mid.x), int(mid.y)), -1,
			"Collision : des continents se soudent, une chaîne de montagnes se soulève" if sutures.size() == 1
			else "Collisions : %d continents se soudent, des chaînes de montagnes se soulèvent" % (sutures.size() + 1), cause, out)
		for c in sutures:
			_tect.p_cause[c.a] = ev.id
			_tect.p_cause[c.b] = ev.id
	geography_version += 1
	geography_changed.emit(geography_version)


func _tectonic_event(change: Dictionary, out: Array[Dictionary]) -> void:
	match String(change.kind):
		"supercontinent":
			_event("supercontinent", Vector2i(int(_tect.target.x), int(_tect.target.y)), -1,
				"Supercontinent : toutes les terres se soudent en une seule, %s" % change.name, _max_plate_cause(), out)
		"breakup":
			var ev := _event("breakup", Vector2i(int(_tect.target.x), int(_tect.target.y)), -1,
				"Fracture : %s se déchire, un océan nouveau s'ouvre entre ses morceaux" % change.name, _max_plate_cause(), out)
			for k in _tect.n:
				_tect.p_cause[k] = ev.id
			# Les terres séparées font diverger leurs espèces (spéciation par isolement).
			causal_log.schedule(year + 20.0e6, "vicariance", ev.id, ev.region, -1, 1.0)


func _max_plate_cause() -> int:
	var best := -1
	for k in _tect.n:
		best = maxi(best, int(_tect.p_cause[k]))
	return best


func _crater_list() -> Array:
	var keep: Array[Dictionary] = []
	var out := []
	for c in _craters:
		var age := year - float(c.year)
		if age > Tectonics.CRATER_FADE_YEARS:
			continue
		keep.append(c)
		out.append({cell = anchor_cell(c.anchor), radius = int(c.radius), fade = 1.0 - age / Tectonics.CRATER_FADE_YEARS})
	_craters = keep
	return out


## Spéciation par isolement : sur chaque plaque séparée, les espèces terrestres largement
## répandues donnent une espèce sœur (bornée : quelques espèces par fracture).
func _vicariance(cause: int, out: Array[Dictionary]) -> void:
	# Une passe sur les niches : régions de chaque espèce terrestre, rangées par plaque.
	var by_species := {}
	for r in Ecosystem.NR:
		var c: Vector2i = _eco.region_center_cell(r)
		var p: int = plate_id[c.y * WIDTH + c.x]
		for kk in Ecosystem.K:
			var idx: int = _eco.cur_sp[r * Ecosystem.K + kk]
			if idx < 0 or _eco.t_hab[idx] == 0:
				continue
			if not by_species.has(idx):
				by_species[idx] = {}
			var plates: Dictionary = by_species[idx]
			if not plates.has(p):
				plates[p] = []
			plates[p].append(r)
	var made := 0
	var keys := by_species.keys()
	keys.sort()
	for idx in keys:
		if made >= 6:
			break
		var id: int = _eco.t_id[idx]
		if not species.has(id) or not species[id].alive or species[id].sapient:
			continue
		var by_plate: Dictionary = by_species[idx]
		if by_plate.size() < 2:
			continue
		var plates := by_plate.keys()
		plates.sort_custom(func(a, b): return by_plate[a].size() > by_plate[b].size() or (by_plate[a].size() == by_plate[b].size() and a < b))
		var regions: Array = by_plate[plates[1]]
		if regions.size() < 3:
			continue
		var t: Dictionary = species[id].traits
		var traits := Species.mutate(t, _rng, _eco.region_temperature(regions[0], _global_offset()), 0.5, oxygen)
		var child_name := Species.make_name(_rt[id].scientific_name, _rng, false)
		var child := _create_species(child_name, traits, id, -1)
		if child < 0:
			break
		var ev := _event("vicariance", _cell_of(regions[0]), child,
			"Isolement : séparés par l'océan, les %s d'un continent deviennent les %s" % [species[id].name, child_name], cause, out)
		_rt[child].origin_event = ev.id
		var cidx: int = _rt[child].idx
		for r in regions:
			_eco.place_species(cidx, r, 0, 0.1, idx)
		made += 1


## Semence (geste divin) : une forme de vie déposée dans la région visée. La simulation juge si
## elle prend : une spore sans ozone, un germe d'animal sans oxygène dépérissent d'eux-mêmes.
## Les traits viennent de Species.seed_template(kind, rng, env) quand la session Vie l'aura écrite,
## sinon d'un repli local (_seed_fallback).
func _act_seed(a: Dictionary, action: Dictionary, root: Dictionary, out: Array[Dictionary]) -> void:
	var kind := String(action.get("kind", "spark"))
	var custom: Dictionary = action.get("traits", {})
	var region_temp: float = _eco.region_temperature(a.r, _global_offset())
	# Rôle d'un germe d'animal : la Vie attend filtreur / brouteur / chasseur.
	var role := String(custom.get("role", action.get("role", "brouteur")))
	role = {"filter": "filtreur", "grazer": "brouteur", "hunter": "chasseur"}.get(role, role)
	var env := {oxygen = oxygen, ozone = ozone, year = year, max_complexity = max_complexity,
		temp = region_temp, temperature = region_temp, land = _eco.r_land[a.r] > 0.5,
		role = role, traits = custom}
	var tpl := {}
	var life: Script = Species
	for m in life.get_script_method_list():
		if m.name == "seed_template":
			tpl = life.call("seed_template", kind, _rng, env)
			break
	if tpl.is_empty():
		tpl = _seed_fallback(kind, env)
	var traits: Dictionary = tpl.get("traits", tpl)
	var defaults := Species.traits_from_def({size = 0.05, intelligence = 0.0, adaptability = 0.6,
		aggression = 0.3, diet = "autotrophe", temp_opt = float(env.temperature), temp_tol = 0.35,
		clade = "microbe", complexity = 0.0, habitat = "marine"})
	for key in defaults:
		if not traits.has(key):
			traits[key] = defaults[key]
	var p_name := String(tpl.get("name", traits.get("name", "")))
	traits.erase("name")
	if p_name == "":
		var named := false
		for m in life.get_script_method_list():
			if m.name == "seed_name":
				p_name = String(life.call("seed_name", traits, _rng))
				named = true
				break
		if not named or p_name == "":
			p_name = Species.make_name("", _rng, true)
	var id := _create_species(p_name, traits, -1, -1)
	if id < 0:
		root.summary = "Dieu sème, mais la vie déborde déjà de toutes parts"
		return
	var ev := _event("seeding", a.cell, id, "Semence : les %s sont déposés %s" % [p_name,
		"dans les eaux" if traits.habitat == "marine" else "sur les terres"], root.id, out)
	_rt[id].origin_event = ev.id
	_rt[id].lineage_cause = ev.id
	var idx: int = _rt[id].idx
	var placed: int = _eco.place_species(idx, a.r, a.rrad, SEED_POPULATION)
	if placed == 0:
		# Pas de milieu adéquat ici : la semence dérive jusqu'au plus proche (côte, mer, terre).
		for rad in range(1, 6):
			placed = _eco.place_species(idx, a.r, a.rrad + rad, SEED_POPULATION)
			if placed > 0:
				break
	max_complexity = maxf(max_complexity, float(traits.complexity))
	if traits.complexity >= 6.0 and is_inf(_amniote_year):
		_amniote_year = year
	_eco.set_oxygen(oxygen, Species.OXYGEN_NEED, _complex_room(), _land_room())


func _seed_fallback(kind: String, env: Dictionary) -> Dictionary:
	var t: float = env.temperature
	match kind:
		"spark":
			return {name = "Archées des sources", traits = {size = 0.01, adaptability = 0.75, aggression = 0.2,
				diet = "autotrophe", temp_opt = clampf(t + 0.1, 0.4, 0.95), temp_tol = 0.42, clade = "microbe",
				complexity = 0.0, habitat = "marine", anaerobic = true, oxygenic = false}}
		"light":
			return {name = "Cyanobactéries", traits = {size = 0.011, adaptability = 0.7, aggression = 0.3,
				diet = "autotrophe", temp_opt = clampf(t, 0.3, 0.9), temp_tol = 0.38, clade = "microbe",
				complexity = 0.0, habitat = "marine", anaerobic = false, oxygenic = true}}
		"spore":
			return {name = "Mousses pionnières", traits = {size = 0.2, adaptability = 0.7, aggression = 0.2,
				diet = "autotrophe", temp_opt = clampf(t, 0.2, 0.85), temp_tol = 0.32, clade = "plante",
				complexity = 2.0, habitat = "land", oxygenic = true}}
		"animal_germ":
			var role := String(env.get("role", "brouteur"))
			role = {"filtreur": "filter", "brouteur": "grazer", "chasseur": "hunter"}.get(role, role)
			var spec: Array = {"filter": ["Éponges primordiales", "éponge", "herbivore", 0.08],
				"grazer": ["Brouteurs primordiaux", "mollusque", "herbivore", 0.12],
				"hunter": ["Chasseurs primordiaux", "arthropode", "carnivore", 0.15]}.get(role, ["Éponges primordiales", "éponge", "herbivore", 0.08])
			return {name = spec[0], traits = {size = spec[3], adaptability = 0.6, aggression = 0.4 if spec[2] == "carnivore" else 0.2,
				diet = spec[2], temp_opt = clampf(t, 0.3, 0.9), temp_tol = 0.3, clade = spec[1], complexity = 3.0,
				habitat = "marine"}}
	# « shaped » : les traits du joueur sur un socle d'animal marin simple.
	var base := {size = 0.2, intelligence = 0.05, adaptability = 0.6, aggression = 0.4, diet = "omnivore",
		temp_opt = clampf(t, 0.2, 0.9), temp_tol = 0.3, clade = "chimère", complexity = 3.0, habitat = "marine"}
	var custom: Dictionary = env.traits
	for key in custom:
		if key != "role":
			base[key] = custom[key]
	return {name = String(custom.get("name", "")), traits = base}


## Pousser une plaque (geste divin) : vers `target` si l'action en donne une, sinon elle se
## détache de sa masse soudée (rift) ou file vers la croûte la plus proche.
func _act_drift(a: Dictionary, action: Dictionary, root: Dictionary, out: Array[Dictionary]) -> void:
	if _tect == null:
		root.summary = "Dieu pousse la croûte, mais ce monde-ci n'a pas de plaques mobiles"
		return
	var k: int = plate_id[a.cell.y * WIDTH + a.cell.x]
	var here: Vector2 = _tect.plate_position(k, 0.0, 0.0)
	var dir := Vector2.ZERO
	var sutured := false
	for o in _tect.n:
		if o != k and _tect.group_of(o) == _tect.group_of(k):
			sutured = true
	if action.has("target"):
		var tgt: Vector2i = action.target
		dir = Vector2(Tectonics._wrap_dx(float(tgt.x) - here.x), float(tgt.y) - here.y)
	else:
		var c: Vector2 = _tect._crust_centroid(-1)
		dir = Vector2(Tectonics._wrap_dx(here.x - c.x), here.y - c.y) * (1.0 if sutured else -1.0)
	var ev := _event("drift", a.cell, -1, ("Rift : Dieu fend la croûte, une plaque se détache de son continent"
		if sutured else "Dérive : Dieu pousse une plaque à travers l'océan"), root.id, out)
	_tect.push(k, dir, 0.25, ev.id, year)


## Cycles de la vie (après le prologue) : fin d'un cycle de civilisation, glaciations naturelles,
## renaissance depuis les microbes après la mort de la vie complexe, vie qui renaît d'un monde
## stérile (mode Éternité).
func _life_cycle_step(dt: float, out: Array[Dictionary]) -> void:
	var cmax := 0.0
	for id in _alive:
		cmax = maxf(cmax, float(species[id].traits.get("complexity", 6.0)))
	if not _deep_time():
		max_complexity = cmax
	if cmax >= 4.0:
		_peak_complexity = maxf(_peak_complexity, cmax)
	elif _peak_complexity >= 4.0 and cmax <= 2.0 and not _alive.is_empty():
		# La vie complexe a disparu : les survivants recommencent l'histoire, sans dates héritées.
		_peak_complexity = cmax
		_rule_ready.clear()
		rebirths += 1
		var ev := _event("rebirth", Vector2i(-1, -1), -1,
			"Renaissance : la vie complexe a disparu, les microbes survivants recommencent l'histoire", _planet_cause, out)
		_planet_cause = ev.id
	if _alive.is_empty():
		if is_nan(_lifeless_since):
			_lifeless_since = year
		elif endless and scenario == SCENARIO_PROLOGUE and year - _lifeless_since >= ABIOGENESIS_YEARS:
			_lifeless_since = NAN
			_rule_ready.clear()
			rebirths += 1
			_eco.explicit_flora = 1
			var ev := _event("rebirth", Vector2i(-1, -1), -1,
				"Genèse : dans les sources chaudes des abysses, la vie apparaît de nouveau", _planet_cause, out)
			_planet_cause = ev.id
			_seed_prologue()
		return
	_lifeless_since = NAN
	if _era_idx >= Eras.MESOZOIC and (_deep_time() or _had_civilization) 			and _chance(dt, NATURAL_ICE_AGE_RATE):
		var unit := Eras.time_unit(_era_idx)
		var ev := _event("ice_age", Vector2i(-1, -1), -1, "Glaciation : les calottes polaires s'étendent", -1, out)
		_add_climate_shock(NATURAL_ICE_AGE_COLD, unit * 3.0, ev.id)
		_note_all(ev.id)


func _natural_events(dt: float, out: Array[Dictionary]) -> void:
	# Supervolcans : rares, refroidissement local et global.
	if _chance(dt, 1.0 / 4.0e6):
		var r := _random_land_region()
		if r >= 0:
			var ev := _event("volcanism", _eco.region_center_cell(r), -1,
				"Supervolcan : une éruption colossale obscurcit le ciel", -1, out)
			_mark_harm(_eco.kill_area(r, 3, 0.6), ev.id, Eras.time_unit(_era_idx))
			_eco.add_anomaly(r, 5, -0.12)
			_regional_active = true
			_add_climate_shock(-0.04, Eras.time_unit(_era_idx), ev.id)


func _process_scheduled(out: Array[Dictionary]) -> void:
	for e in causal_log.pop_due(year):
		if _rng.randf() > float(e.chance):
			continue
		var sid: int = e.species_id
		var alive_target: bool = species.has(sid) and species[sid].alive
		var rt: Dictionary = _rt.get(sid, {})
		var unit := Eras.time_unit(_era_idx)
		match e.kind:
			"impact_winter_end":
				_event("climate", e.region, -1, "Le ciel s'éclaircit : l'hiver d'impact prend fin", e.cause_id, out)
			"radiation":
				_radiation(e.cause_id, e.region, out)
			"ice_age_end":
				_event("ice_age_end", e.region, -1, "Fin de la glaciation : les glaces reculent", e.cause_id, out)
			"land_bridge":
				var ev := _event("land_bridge", e.region, -1,
					"Ponts de glace : les mers basses ouvrent des routes de migration", e.cause_id, out)
				_mig_mult = 3.0
				_mig_until = year + unit * 4.0
				_note_all(ev.id)
			"plague_wave":
				if alive_target:
					var ev := _event("plague", e.region, sid, "Nouvelle vague d'épidémie chez les %s" % species[sid].name, e.cause_id, out)
					_eco.scale_species(rt.idx, 0.75)
					_mark_harm({rt.idx: true}, ev.id, unit * 2.0)
					_note(sid, ev.id)
					if species[sid].sapient:
						species[sid].tech_level = maxf(0.0, species[sid].tech_level - 0.04)
					causal_log.schedule(year + unit * 2.0, "plague_wave", ev.id, e.region, sid, 0.45)
					causal_log.schedule(year + unit * 3.0, "immunity", ev.id, e.region, sid, 0.6)
			"immunity":
				if alive_target:
					var t: Dictionary = species[sid].traits
					t.adaptability = minf(1.0, t.adaptability + 0.05)
					var ev := _event("immunity", e.region, sid, "Les %s survivants développent une immunité" % species[sid].name, e.cause_id, out)
					_note(sid, ev.id)
					_refresh_species(sid)
			"decline":
				if alive_target and species[sid].sapient:
					var ev := _event("decline", e.region, sid, "Décadence : la prospérité des %s s'effrite" % species[sid].name, e.cause_id, out)
					species[sid].tech_level = maxf(0.0, species[sid].tech_level - 0.06)
					_note(sid, ev.id)
			"golden_age":
				if alive_target and species[sid].sapient:
					var span := Eras.level_years(species[sid].tech_level)
					var ev := _event("golden_age", e.region, sid, "Âge d'or : sous le regard de Dieu, les %s prospèrent" % species[sid].name, e.cause_id, out)
					rt.mods.append({factor = 2.0, until = year + 0.2 * span, cause = ev.id})
					rt.tech_cause = ev.id
					_note(sid, ev.id)
					causal_log.schedule(year + 0.2 * span, "decline", ev.id, e.region, sid, 0.4)
			"resurgence":
				if alive_target:
					var ev := _event("radiation", e.region, sid, "Résurgence : les %s, épargnés, reconquièrent leur monde" % species[sid].name, e.cause_id, out)
					rt.radiation_until = year + unit * 6.0
					rt.radiation_cause = ev.id
					_eco.place_species(rt.idx, maxi(rt.sample, 0), 2, 0.2)
					_note(sid, ev.id)
			"awakening":
				if alive_target and not species[sid].sapient:
					var t: Dictionary = species[sid].traits
					t.intelligence = minf(1.0, t.intelligence + 0.08)
					var ev := _event("uplift", e.region, sid, "L'étincelle divine grandit chez les %s" % species[sid].name, e.cause_id, out)
					rt.lineage_cause = ev.id
					_note(sid, ev.id)
					if t.intelligence >= Species.SAPIENCE_THRESHOLD:
						_become_sapient(sid, out)
			"fertile_silt":
				var ev := _event("fertile_silt", e.region, -1, "Le limon du déluge fertilise les plaines", e.cause_id, out)
				_eco.add_bless(_eco.region_of_cell(e.region), int(e.data.get("rrad", 2)), 0.35)
				_regional_active = true
				for id in _species_near(_eco.region_of_cell(e.region), int(e.data.get("rrad", 2))):
					if species[id].sapient:
						causal_log.schedule(year + unit * 0.5, "golden_age", ev.id, e.region, id, 0.5)
			"flood_myth":
				if alive_target and species[sid].sapient:
					var ev := _event("discovery", e.region, sid, "Les %s gravent le mythe du Déluge : naissance d'une religion" % species[sid].name, e.cause_id, out)
					species[sid].tech_level = minf(Eras.MAX_TECH, species[sid].tech_level + 0.05)
					rt.tech_cause = ev.id
					_note(sid, ev.id)
			"invasion":
				if alive_target and species[sid].regions < int(e.data.get("threshold", 10)):
					var ev := _event("endemic", e.region, sid, "Les %s restent cantonnés à leur berceau (%d régions)" % [species[sid].name, species[sid].regions], e.cause_id, out)
					_note(sid, ev.id)
				elif alive_target:
					var ev := _event("invasion", e.region, sid, "Invasion : les %s ont conquis %d régions" % [species[sid].name, species[sid].regions], e.cause_id, out)
					_note(sid, ev.id)
					for id in _species_near(maxi(rt.sample, 0), 4):
						if id != sid:
							_rt[id].harm_cause = ev.id
							_rt[id].harm_until = year + unit * 4.0
			"vicariance":
				_vicariance(e.cause_id, out)
			"niche_freed":
				_radiation(e.cause_id, e.region, out, int(e.data.get("near", -1)))


## Radiation adaptative : les survivants les plus répandus se diversifient.
func _radiation(cause_id: int, cell: Vector2i, out: Array[Dictionary], favour := -1) -> void:
	var ranked := []
	for id in _alive:
		if not species[id].sapient:
			var bonus := 1000 if id == favour else 0
			ranked.append([species[id].regions + bonus, id])
	ranked.sort_custom(func(x, y): return x[0] > y[0] or (x[0] == y[0] and x[1] < y[1]))
	if ranked.is_empty():
		return
	var names := []
	for i in mini(3, ranked.size()):
		names.append(species[ranked[i][1]].name)
	var ev := _event("radiation", cell, ranked[0][1],
		"Radiation adaptative : %s se diversifient dans les niches laissées vides" % ", ".join(names), cause_id, out)
	var unit := Eras.time_unit(_era_idx)
	for i in mini(3, ranked.size()):
		var rt: Dictionary = _rt[ranked[i][1]]
		rt.radiation_until = year + unit * 8.0
		rt.radiation_cause = ev.id
		if i == 0:
			_speciate(ranked[i][1], out)


func _decay(dt: float) -> void:
	if _ice_push != 0.0:
		_ice_push *= exp(-dt / maxf(_climate_tau, 1e-3))
		if absf(_ice_push) < 1e-3:
			_ice_push = 0.0
	if _climate_anom != 0.0:
		_climate_anom *= exp(-dt / maxf(_climate_tau, 1e-3))
		if absf(_climate_anom) < 1e-3:
			_climate_anom = 0.0
	if _regional_active:
		_regional_active = _eco.decay_modifiers(exp(-dt / (Eras.time_unit(_era_idx) * 2.0)))
		if not _regional_active:
			_goff_written = 1e9


func _update_era(out: Array[Dictionary]) -> void:
	var lead := _leading_species()
	var idx := 0
	var cause := -1
	if lead >= 0:
		idx = Eras.era_for_tech(species[lead].tech_level)
		cause = _rt[lead].tech_cause
	elif _era_idx < Eras.MESOZOIC:
		idx = _prologue_stage()
		cause = _planet_cause
	elif _had_civilization:
		# Plus aucun peuple conscient : l'âge des héritiers, jusqu'au prochain éveil.
		idx = Eras.AFTERMATH
		cause = _planet_cause
	else:
		# Avant toute sapience : Mésozoïque tant que les dinosaures règnent (poids écologique),
		# Cénozoïque une fois leur règne fini.
		var dino := 0.0
		var total := 0.0
		for id in _alive:
			var sp: Dictionary = species[id]
			if Species.is_autotroph(sp.traits) or sp.traits.get("habitat", "land") == "marine":
				continue
			var w: float = sp.regions * (0.3 + float(sp.traits["size"]))
			total += w
			if sp.traits.clade == "dinosaure":
				dino += w
		var share := dino / total if total > 0.0 else 0.0
		if share >= 0.3:
			_dino_ruled = true
		idx = Eras.MESOZOIC
		if _left_mesozoic or (_dino_ruled and share < 0.3):
			_left_mesozoic = true
			idx = Eras.CENOZOIC
		cause = _last_dino_extinction
	if idx == _era_idx:
		return
	var new_cycle := _era_idx == Eras.AFTERMATH and lead >= 0
	if idx == Eras.AFTERMATH:
		cycles += 1
	var rising := idx > _era_idx or new_cycle
	_era_idx = idx
	if not era_years.has(idx):
		era_years[idx] = year
	if idx == Eras.MESOZOIC and _deep_time() and _meso_dt <= 0.0:
		_meso_dt = clampf((Eras.CRETACEOUS_END - year) / MESOZOIC_STEPS, MESOZOIC_DT_MIN, MESOZOIC_DT_MAX)
	var text := "Le monde entre dans l'ère : %s" % ERAS[idx]
	if lead < 0 and STAGE_TEXT.has(idx):
		text = "%s : %s" % [ERAS[idx], STAGE_TEXT[idx]]
	if idx == Eras.AFTERMATH:
		text = "%s : plus aucun peuple conscient, la Terre attend de nouveaux esprits" % ERAS[idx]
	if lead >= 0:
		text += " (portée par les %s)" % species[lead].name
		if new_cycle:
			text = "Nouveau cycle : les %s s'éveillent, le monde entre dans l'ère : %s" % [species[lead].name, ERAS[idx]]
		elif not rising:
			text = "Recul : la civilisation retombe à l'ère %s" % ERAS[idx]
	var ev := _event("era_change", _cell_of(_rt[lead].last_region) if lead >= 0 else Vector2i(-1, -1),
		lead, text, cause, out)
	_era_cause = ev.id
	_planet_cause = ev.id


# =============================================================================================
# Prologue : planète vivante
# =============================================================================================

## Étape du prologue déduite de l'état du monde (jamais en arrière ; une étape peut être sautée).
func _prologue_stage() -> int:
	var idx := _era_idx
	var animals := 0
	var tetrapod := false
	var amniote := false
	var dinos := 0
	for id in _alive:
		var t: Dictionary = species[id].traits
		var c := float(t.get("complexity", 6.0))
		if c >= 3.0 and not Species.is_autotroph(t):
			animals += 1
		if c >= 5.0 and t.get("habitat", "land") != "marine":
			tetrapod = true
		if c >= 6.0 and t.get("habitat", "land") == "land":
			amniote = true
		if t.clade == "dinosaure" and int(species[id].regions) >= 6:
			dinos += 1
	var reached := [
		true,
		_iron <= 0.0,
		snowball and _iron <= 0.0,
		animals >= 3 and not snowball,
		tetrapod,
		amniote,
		not is_nan(_great_dying_year),
		(not is_nan(_great_dying_year) and year - _great_dying_year >= 2.0e6) or dinos >= 2,
	]
	for k in range(_era_idx + 1, Eras.MESOZOIC + 1):
		if reached[k]:
			idx = k
	return idx


## Oxygène, climat, flore terrestre, trapps : un pas de la planète du prologue.
func _planet_step(dt: float, out: Array[Dictionary]) -> void:
	var cyano_regions := 0
	var algae_regions := 0
	var meth := 0.0
	var prod := 0.0
	var flora_regions := 0
	var fauna_regions := 0
	var cmax := 0.0
	for id in _alive:
		var sp: Dictionary = species[id]
		var t: Dictionary = sp.traits
		var pop: float = sp.population
		cmax = maxf(cmax, float(t.get("complexity", 6.0)))
		if Species.is_autotroph(t):
			prod += pop
			if bool(t.get("oxygenic", false)) and t.get("habitat", "") != "land":
				if t.clade == "microbe":
					cyano_regions += int(sp.regions)
				else:
					algae_regions += int(sp.regions)
			if bool(t.get("anaerobic", false)):
				meth += pop
			if t.get("habitat", "") == "land":
				flora_regions += int(sp.regions)
		elif t.get("habitat", "") != "marine":
			fauna_regions += int(sp.regions)
	max_complexity = cmax
	if cmax >= 6.0 and is_inf(_amniote_year):
		_amniote_year = year
	land_flora = clampf(float(flora_regions) / float(_land_regions), 0.0, 1.0)
	land_fauna = clampf(float(fauna_regions) / float(_land_regions), 0.0, 1.0)
	var productivity := CYANO_PRODUCTIVITY * minf(1.0, float(cyano_regions) / (_sea_regions * COVER_FULL)) 		+ ALGAE_PRODUCTIVITY * minf(1.0, float(algae_regions) / (_sea_regions * COVER_FULL))
	_methane = meth / prod if prod > 0.0 else 0.0
	# Oxygène : d'abord absorbé par le fer et les gaz réducteurs, puis tenu bas par les puits
	# profonds, enfin à l'équilibre entre production (mers + forêts) et altération.
	var target := 0.0005
	if _iron > 0.0:
		_iron = maxf(0.0, _iron - dt * IRON_DRAW * productivity)
	else:
		target = (OXYGEN_GAIN * productivity + OXYGEN_LAND * land_flora) / (1.0 + SINK_GAIN * _sink)
		_sink = maxf(0.0, _sink - dt * SINK_DRAW * oxygen)
	var before := oxygen
	oxygen = target + (oxygen - target) * exp(-dt / OXYGEN_TAU)
	if before <= 0.0005 and _iron <= 0.0:
		_planet_cause = _oxygenic_origin()
	_climate_step(dt, out)
	_traps_step(dt, out)
	# Fenêtre des extinctions récentes (2 Ma) : une hécatombe ouvre la Grande Mourance.
	while not _recent_ext.is_empty() and _recent_ext[0] < year - 2.0e6:
		_recent_ext.pop_front()
	if _era_idx >= Eras.CARBONIFEROUS and is_nan(_great_dying_year):
		var n := _recent_ext.size()
		if n >= 6 and float(n) / float(n + _alive.size()) >= MASS_EXTINCTION_SHARE:
			_great_dying_year = year
			_planet_cause = causal_log.history[-1].id if not causal_log.history.is_empty() else -1


## Id de l'événement d'origine du principal producteur d'oxygène (cause de la Grande Oxydation).
func _oxygenic_origin() -> int:
	var best := -1
	var best_pop := 0.0
	for id in _alive:
		var t: Dictionary = species[id].traits
		if bool(t.get("oxygenic", false)) and float(species[id].population) > best_pop:
			best_pop = species[id].population
			best = id
	return int(_rt[best].origin_event) if best >= 0 else -1


## Climat du prologue : soleil jeune et pâle, effet de serre du méthane (détruit par l'oxygène),
## thermostat lent du CO2 (altération des roches, accélérée par les plantes), Terre boule de
## neige quand le froid l'emporte, dégel quand les volcans ont rechargé l'air en CO2.
func _climate_step(dt: float, out: Array[Dictionary]) -> void:
	var sun := _sun_term()
	# Les méthanogènes survivent dans les eaux profondes sans oxygène tant que les puits tiennent.
	var ch4 := METHANE_MAX * maxf(_methane, 0.6 * smoothstep(0.1, 0.25, _sink) * _life_present()) * (1.0 - smoothstep(0.03, 0.08, oxygen))
	var forcing := sun + ch4
	var co2_eq := clampf(-0.85 * forcing - 0.02 * land_flora, -0.15, 0.4)
	if dt <= 0.0 and _co2 == 0.0 and not snowball:
		_co2 = co2_eq
	if snowball:
		_co2 += dt * SNOWBALL_CO2_RATE
		if forcing + _co2 + _ice_push > SNOWBALL_OUT:
			snowball = false
			var ev := _event("thaw", Vector2i(-1, -1), -1,
				"Dégel : le CO2 des volcans a fini par fondre la glace, les mers se rouvrent", _planet_cause, out)
			_planet_cause = ev.id
	else:
		_co2 = co2_eq + (_co2 - co2_eq) * exp(-dt / CO2_TAU)
		if dt > 0.0 and forcing + _co2 + _ice_push < SNOWBALL_IN:
			snowball = true
			var ev := _event("snowball", Vector2i(-1, -1), -1,
				"Terre boule de neige : la glace avance jusqu'aux tropiques", _planet_cause, out)
			_planet_cause = ev.id
	_proto = forcing + _co2 + (SNOWBALL_ALBEDO if snowball else 0.0)


## Trapps : après l'entrée au Carbonifère, un épanchement de lave colossal devient de plus en
## plus probable. Apaiser la Terre (action « soothe ») remet l'horloge à zéro.
func _traps_step(dt: float, out: Array[Dictionary]) -> void:
	if _era_idx < Eras.CARBONIFEROUS or not is_nan(_great_dying_year) or dt <= 0.0:
		return
	if _trap_clock == 0.0:
		_trap_clock = float(era_years.get(Eras.CARBONIFEROUS, year))
	var age := maxf(0.0, year - _trap_clock)
	if _chance(dt, age / (TRAPS_TAU * TRAPS_TAU)):
		_great_dying(-1, out)


## La Grande Mourance : réchauffement brutal, océans sans oxygène, hécatombe.
func _great_dying(cause: int, out: Array[Dictionary]) -> void:
	var r := _random_land_region()
	var ev := _event("traps", _eco.region_center_cell(r) if r >= 0 else Vector2i(-1, -1), -1,
		"Trapps : des millions de km³ de lave noient un continent, le ciel s'empoisonne", cause, out)
	_great_dying_year = year
	_planet_cause = ev.id
	_add_climate_shock(0.1, 4.0e6, ev.id)
	oxygen *= 0.7
	var unit := Eras.time_unit(_era_idx)
	for id in _alive.duplicate():
		var sp: Dictionary = species[id]
		var t: Dictionary = sp.traits
		var rt: Dictionary = _rt[id]
		var v := 0.85 if t.get("habitat", "land") == "marine" else 0.65
		if Species.is_autotroph(t):
			v = 0.35
		v *= 1.1 - 0.5 * float(t.adaptability)
		if rt.protect_until >= year:
			v *= 0.1
		rt.harm_cause = ev.id
		rt.harm_until = year + unit * 3.0
		if _rng.randf() < v * 0.75:
			_extinguish(id, ev.id, out, "Grande Mourance")
		else:
			_eco.scale_species(rt.idx, 1.0 - v)
			rt.radiation_until = year + unit * 10.0
			rt.radiation_cause = ev.id
	causal_log.schedule(year + unit * 2.0, "radiation", ev.id, Vector2i(-1, -1), -1)


# =============================================================================================
# Actions divines
# =============================================================================================

func _act_meteor(a: Dictionary, root: Dictionary, out: Array[Dictionary]) -> void:
	var sev := clampf(a.radius / 12.0, 0.3, 1.6)
	var unit := Eras.time_unit(_era_idx)
	var impact := _event("impact", a.cell, -1,
		"Impact : un astéroïde creuse un cratère de %d km et embrase le ciel" % (a.radius * 75), root.id, out)
	_carve_crater(a.cell, a.radius)
	_mark_harm(_eco.kill_area(a.r, a.rrad, 1.0), impact.id, unit * 3.0)
	_mark_harm(_eco.kill_area(a.r, a.rrad * 3, 0.5), impact.id, unit * 3.0)
	# Hiver d'impact planétaire : mortalité selon la taille, la lignée et l'adaptabilité.
	for id in _alive.duplicate():
		var sp: Dictionary = species[id]
		var rt: Dictionary = _rt[id]
		var v := Species.impact_vulnerability(sp.traits, sev)
		if rt.protect_until >= year:
			v *= 0.1
		rt.harm_cause = impact.id
		rt.harm_until = year + unit * 3.0
		if v >= 0.97:
			_extinguish(id, impact.id, out, "hiver d'impact")
		else:
			_eco.scale_species(rt.idx, 1.0 - v)
			rt.radiation_until = year + unit * 10.0
			rt.radiation_cause = impact.id
			if sp.sapient:
				sp.tech_level = maxf(0.0, sp.tech_level - 0.6 * sev)
				var ev := _event("collapse", a.cell, id, "Âge sombre : l'impact plonge les %s dans le chaos" % sp.name, impact.id, out)
				_note(id, ev.id)
	_add_climate_shock(-0.3 * sev, unit * 1.5, impact.id)
	_ozone_damage = maxf(_ozone_damage, OZONE_DAMAGE_METEOR * sev)
	_climate_cause_until = year + unit * 4.0
	causal_log.schedule(year + unit * 3.0, "impact_winter_end", impact.id, a.cell, -1)
	causal_log.schedule(year + unit * 2.0, "radiation", impact.id, a.cell, -1)


func _act_extinct(a: Dictionary, root: Dictionary, out: Array[Dictionary]) -> void:
	var id: int = a.target
	if id < 0:
		root.summary = "Dieu cherche une espèce à anéantir, mais la région est vide"
		return
	var near := _most_overlapping(id)
	var ev := _extinguish(id, root.id, out, "volonté divine")
	_eco.scale_species(_rt[id].idx, 0.0)
	causal_log.schedule(year + Eras.time_unit(_era_idx) * 0.5, "niche_freed", ev.id, a.cell, -1, 1.0, {near = near})


func _act_save(a: Dictionary, root: Dictionary, out: Array[Dictionary]) -> void:
	var id: int = a.target
	if id < 0:
		# Taxon Lazare : ressusciter la dernière espèce éteinte dans cette région.
		id = _last_extinct_near(a.r)
		if id < 0:
			root.summary = "Dieu tend la main, mais il n'y a rien à sauver ici"
			return
	var unit := Eras.time_unit(_era_idx)
	if not species[id].alive:
		if _revive(id, a.r, a.rrad) < 0:
			root.summary = "Dieu tente une résurrection, mais le monde est trop plein"
			return
		var lz := _event("lazarus", a.cell, id, "Taxon Lazare : les %s reviennent d'entre les morts" % species[id].name, root.id, out)
		_rt[id].origin_event = lz.id
		_rt[id].lineage_cause = lz.id
	var rt: Dictionary = _rt[id]
	rt.protect_until = year + unit * 4.0
	_eco.t_protect[rt.idx] = 1
	var ev := _event("protection", a.cell, id, "Les %s sont placés sous protection divine" % species[id].name, root.id, out)
	_note(id, ev.id)
	if rt.lineage_cause <= 0:
		rt.lineage_cause = ev.id
	causal_log.schedule(year + unit * 2.0, "resurgence", ev.id, a.cell, id, 0.8)


func _act_bless(a: Dictionary, root: Dictionary, out: Array[Dictionary]) -> void:
	var unit := Eras.time_unit(_era_idx)
	var ev := _event("blessing", a.cell, a.target, "Bénédiction : la terre devient luxuriante", root.id, out)
	_eco.add_bless(a.r, a.rrad, 0.5)
	_regional_active = true
	for id in _species_near(a.r, a.rrad):
		_note(id, ev.id)
		if species[id].sapient:
			causal_log.schedule(year + unit * 0.1, "golden_age", ev.id, a.cell, id, 1.0)
		else:
			_rt[id].radiation_until = year + unit * 3.0
			_rt[id].radiation_cause = ev.id


func _act_plague(a: Dictionary, root: Dictionary, out: Array[Dictionary]) -> void:
	var id: int = a.target
	if id < 0:
		root.summary = "Dieu répand la peste, mais nul ne l'attrape"
		return
	var unit := Eras.time_unit(_era_idx)
	var rt: Dictionary = _rt[id]
	var ev := _event("plague", a.cell, id, "Épidémie divine : un fléau s'abat sur les %s" % species[id].name, root.id, out)
	_eco.kill_area(a.r, a.rrad * 2, 0.6, rt.idx)
	_eco.scale_species(rt.idx, 0.8 if rt.protect_until < year else 0.97)
	_mark_harm({rt.idx: true}, ev.id, unit * 3.0)
	_note(id, ev.id)
	if species[id].sapient:
		species[id].tech_level = maxf(0.0, species[id].tech_level - 0.1)
	causal_log.schedule(year + unit, "plague_wave", ev.id, a.cell, id, 1.0)


func _act_uplift(a: Dictionary, root: Dictionary, out: Array[Dictionary]) -> void:
	var id: int = a.target
	if id < 0:
		root.summary = "Dieu offre l'étincelle, mais personne n'est là pour la recevoir"
		return
	var sp: Dictionary = species[id]
	var rt: Dictionary = _rt[id]
	var unit := Eras.time_unit(_era_idx)
	if sp.sapient:
		var rev := _event("discovery", a.cell, id, "Révélation : Dieu souffle aux %s un savoir interdit" % sp.name, root.id, out)
		sp.tech_level = minf(Eras.MAX_TECH, sp.tech_level + 0.5)
		rt.tech_cause = rev.id
		_note(id, rev.id)
		return
	var t: Dictionary = sp.traits
	t.intelligence = minf(1.0, t.intelligence + 0.2)
	t.adaptability = minf(1.0, t.adaptability + 0.05)
	var ev := _event("uplift", a.cell, id, "Élévation : Dieu éveille l'esprit des %s" % sp.name, root.id, out)
	rt.lineage_cause = ev.id
	_note(id, ev.id)
	_refresh_species(id)
	if t.intelligence >= Species.SAPIENCE_THRESHOLD:
		_become_sapient(id, out)
	else:
		causal_log.schedule(year + unit, "awakening", ev.id, a.cell, id, 1.0)


func _act_flood(a: Dictionary, root: Dictionary, out: Array[Dictionary]) -> void:
	var unit := Eras.time_unit(_era_idx)
	var ev := _event("deluge", a.cell, -1, "Déluge : les eaux engloutissent les basses terres", root.id, out)
	var near := _species_near(a.r, a.rrad)
	_mark_harm(_eco.kill_area(a.r, a.rrad, 0.8, -1, true, -INF, 0.3), ev.id, unit * 2.0)
	for id in near:
		_note(id, ev.id)
		if species[id].sapient:
			causal_log.schedule(year + unit * 0.5, "flood_myth", ev.id, a.cell, id, 0.7)
	causal_log.schedule(year + unit * 0.3, "fertile_silt", ev.id, a.cell, -1, 1.0, {rrad = a.rrad})


func _act_ice_age(a: Dictionary, root: Dictionary, out: Array[Dictionary]) -> void:
	var unit := Eras.time_unit(_era_idx)
	var ev := _event("ice_age", a.cell, -1, "Glaciation : les calottes polaires avancent sur le monde", root.id, out)
	_add_climate_shock(-0.22, unit * 3.0, ev.id)
	_ice_push -= 0.22
	_climate_cause_until = year + unit * 5.0
	_note_all(ev.id)
	causal_log.schedule(year + unit * 1.0, "land_bridge", ev.id, a.cell, -1, 0.8)
	causal_log.schedule(year + unit * 5.0, "ice_age_end", ev.id, a.cell, -1)
	causal_log.schedule(year + unit * 1.5, "radiation", ev.id, a.cell, -1, 0.7)


## Éruption : cendres et froid passagers, gaz réducteurs qui mangent l'oxygène, CO2 qui
## réchauffera le monde à long terme (de quoi sortir d'une boule de neige).
func _act_volcano(a: Dictionary, root: Dictionary, out: Array[Dictionary]) -> void:
	var unit := Eras.time_unit(_era_idx)
	var ev := _event("volcanism", a.cell, -1, "Volcanisme : des gaz étouffants montent des fissures", root.id, out)
	_mark_harm(_eco.kill_area(a.r, a.rrad, 0.5), ev.id, unit)
	_eco.add_anomaly(a.r, a.rrad + 2, -0.08)
	_regional_active = true
	_add_climate_shock(-0.03, unit, ev.id)
	oxygen *= 0.6
	if _iron > 0.0 or oxygen < 0.01:
		_iron = minf(1.0, _iron + 0.1)
	_sink = minf(1.0, _sink + 0.15)
	_co2 = minf(0.5, _co2 + 0.06)
	_ozone_damage = maxf(_ozone_damage, OZONE_DAMAGE_VOLCANO)
	_planet_cause = ev.id


## Souffle divin : l'oxygène monte d'un coup (les puits ne le reprendront que lentement).
func _act_oxygenate(a: Dictionary, root: Dictionary, out: Array[Dictionary]) -> void:
	var before := oxygen
	oxygen = minf(2.0, oxygen + 0.25)
	_iron = 0.0
	var ev := _event("oxygen", a.cell, -1, "Souffle divin : l'oxygène gonfle l'atmosphère (%.0f %% → %.0f %% du niveau actuel)" % [
		before * 100.0, oxygen * 100.0], root.id, out)
	_planet_cause = ev.id
	_eco.add_bless(a.r, a.rrad, 0.3)
	_regional_active = true


## Apaiser la Terre : les trapps qui couvaient sont désamorcés pour un temps.
func _act_soothe(a: Dictionary, root: Dictionary, out: Array[Dictionary]) -> void:
	_trap_clock = year
	_event("soothe", a.cell, -1, "La Terre s'apaise : le magma redescend dans les profondeurs", root.id, out)


func _act_spawn(a: Dictionary, root: Dictionary, out: Array[Dictionary]) -> void:
	var parent: int = int(a.get("target", -1))
	var temp: float = _eco.region_temperature(a.r, _global_offset())
	var traits: Dictionary
	var p_name := "Chimère"
	if parent >= 0 and species.has(parent):
		traits = Species.mutate(species[parent].traits, _rng, temp, 1.0, oxygen)
		p_name = _rt[parent].scientific_name if _rt.has(parent) else species[parent].name
	else:
		parent = -1
		traits = Species.random_traits(_rng, temp, max_complexity, _eco.land_open > 0.5)
	var id := _create_species(Species.make_name(p_name, _rng, parent < 0), traits, parent, -1)
	if id < 0:
		root.summary = "Dieu veut créer la vie, mais le monde est saturé d'espèces"
		return
	var unit := Eras.time_unit(_era_idx)
	var ev := _event("spawn", a.cell, id, "Création : Dieu façonne les %s" % species[id].name, root.id, out)
	_rt[id].origin_event = ev.id
	_rt[id].lineage_cause = ev.id
	_rt[id].protect_until = year + unit * 0.5
	_eco.t_protect[_rt[id].idx] = 1
	_eco.place_species(_rt[id].idx, a.r, a.rrad, 0.3)
	causal_log.schedule(year + unit * 2.0, "invasion", ev.id, a.cell, id, 1.0, {threshold = 10})


# =============================================================================================
# Utilitaires
# =============================================================================================

func _event(type: String, cell: Vector2i, species_id: int, summary: String, cause_id: int, out: Array[Dictionary]) -> Dictionary:
	var ev: Dictionary = causal_log.make_event(year, type, cell, species_id, summary, cause_id)
	out.append(ev)
	return ev


func _note(id: int, event_id: int) -> void:
	if _rt.has(id):
		_rt[id].last_event = event_id
		_rt[id].last_event_year = year


func _note_all(event_id: int) -> void:
	for id in _alive:
		_note(id, event_id)


func _mark_harm(hit: Dictionary, event_id: int, duration: float) -> void:
	for idx in hit:
		var id: int = _eco.t_id[idx]
		if _rt.has(id):
			_rt[id].harm_cause = event_id
			_rt[id].harm_until = year + duration


func _add_climate_shock(amount: float, tau: float, cause_id: int) -> void:
	# Le choc le plus récent impose sa constante de temps (l'ancien est déjà en partie résorbé).
	_climate_anom += amount
	_climate_tau = tau
	_climate_cause = cause_id
	_climate_cause_until = maxf(_climate_cause_until, year + tau * 2.0)


func _chance(dt: float, rate_per_year: float) -> bool:
	return _rng.randf() < 1.0 - exp(-maxf(rate_per_year, 0.0) * dt)


func _cell_of(r: int) -> Vector2i:
	return _eco.region_center_cell(r) if r >= 0 else Vector2i(-1, -1)


func _random_land_region() -> int:
	for i in 32:
		var r := _rng.randi_range(0, Ecosystem.NR - 1)
		if _eco.r_land[r] > 0.3:
			return r
	return -1


func _species_near(r: int, rad: int) -> Array[int]:
	var seen := {}
	for rr in _eco.regions_in_radius(r, rad):
		for k in Ecosystem.K:
			var idx: int = _eco.cur_sp[rr * Ecosystem.K + k]
			if idx >= 0 and _eco.t_alive[idx] == 1:
				seen[_eco.t_id[idx]] = true
	var out: Array[int] = []
	for id in seen:
		out.append(id)
	out.sort()
	return out


func _target_species(action: Dictionary, cell: Vector2i) -> int:
	var id := int(action.get("species_id", -1))
	if id >= 0 and species.has(id):
		if species[id].alive or action.get("type", "") in ["save", "spawn_species"]:
			return id
	var d := dominant_species[cell.y * WIDTH + cell.x]
	if d >= 0 and species.has(d) and species[d].alive:
		return d
	# Région vide : l'espèce la plus présente dans les environs.
	var near := _species_near(_eco.region_of_cell(cell), 2)
	return near[0] if not near.is_empty() and action.get("type", "") != "save" else -1


func _most_overlapping(id: int) -> int:
	var best := -1
	var best_ov := -1.0
	for other in _alive:
		if other == id:
			continue
		var ov := Species.overlap(species[id].traits, species[other].traits)
		if ov > best_ov:
			best_ov = ov
			best = other
	return best


func _last_extinct_near(r: int) -> int:
	var best := -1
	var best_year := -INF
	for id in species:
		var sp: Dictionary = species[id]
		if sp.alive or not _rt.has(id):
			continue
		var lr: int = _rt[id].last_region
		if lr < 0:
			continue
		var dx := absi((lr % Ecosystem.RW) - (r % Ecosystem.RW))
		dx = mini(dx, Ecosystem.RW - dx)
		@warning_ignore("integer_division")
		var dy := absi(lr / Ecosystem.RW - r / Ecosystem.RW)
		if dx <= 6 and dy <= 6 and sp.extinct_year > best_year:
			best_year = sp.extinct_year
			best = id
	return best


func _revive(id: int, r: int, rrad: int) -> int:
	var idx: int = _eco.alloc_index()
	if idx < 0:
		return -1
	var sp: Dictionary = species[id]
	sp.alive = true
	sp.extinct_year = NAN
	_rt[id].idx = idx
	_eco.t_alive[idx] = 1
	_eco.t_id[idx] = id
	_alive.append(id)
	_refresh_species(id)
	_eco.place_species(idx, r, rrad, 0.2)
	return idx


func _carve_crater(cell: Vector2i, radius: int) -> void:
	if _tect != null:
		_craters.append({anchor = make_anchor(cell), radius = mini(radius, 24), year = year})
		if _craters.size() > 32:
			_craters.pop_front()
	var rc := mini(radius, 24)
	for dy in range(-rc, rc + 1):
		var y := cell.y + dy
		if y < 0 or y >= HEIGHT:
			continue
		for dx in range(-rc, rc + 1):
			var d2 := float(dx * dx + dy * dy) / float(rc * rc)
			if d2 > 1.0:
				continue
			var i := y * WIDTH + posmod(cell.x + dx, WIDTH)
			var e := elevation[i] - 0.25 * (1.0 - d2) + (0.15 if d2 > 0.7 else 0.0) * (1.0 - d2)
			# Le cratère ne transforme pas les terres en mer (masque terre/mer statique).
			elevation[i] = maxf(e, 0.01) if elevation[i] >= 0.0 else minf(e, -0.01)


func _action_label(type: String, target: int) -> String:
	var who: String = species[target].name if target >= 0 and species.has(target) else ""
	match type:
		"meteor": return "un météore fend le ciel"
		"extinct": return "anéantissement des %s" % who if who != "" else "anéantissement"
		"save": return "protection des %s" % who if who != "" else "protection"
		"bless": return "bénédiction de la terre"
		"plague": return "fléau sur les %s" % who if who != "" else "fléau"
		"uplift": return "élévation des %s" % who if who != "" else "élévation"
		"flood": return "déluge"
		"ice_age": return "âge de glace"
		"spawn_species": return "création d'une espèce"
		"volcano": return "les volcans s'éveillent"
		"oxygenate": return "souffle d'oxygène"
		"soothe": return "apaisement de la Terre"
		"seed": return "une semence de vie"
		"drift": return "la croûte se déplace"
	return type
