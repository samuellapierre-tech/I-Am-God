# Architecture — I AM GOD

Moteur : **Godot 4.7** (GDScript, rendu Forward+). Cible : **Steam, Windows + Linux (Steam Deck)**.

## Modules et propriétaires (une branche par module)

| Dossier | Branche | Rôle |
|---|---|---|
| `src/core/` | `main` | `GameState` (autoload) : possède la simulation, relaie les signaux. Contrat partagé. |
| `src/sim/` | `feature/simulation-core` | Monde, espèces, ères, chaîne causale, timelines (fork / projection du futur). CPU multicoeur. |
| `src/map/`, `src/ui/`, `shaders/`, `scenes/` | `feature/world-map` | Planète vue de haut, shaders GPU, caméra, pouvoirs divins, HUD. |
| `src/ai/` | `feature/ai-narrator` | Narrateur : LLM local (Ollama / llama.cpp, GPU) + repli procédural hors-ligne. |
| `docs/` | `docs/game-design` | Game design, roadmap, plan Steam. |

Flux : `develop` intègre les branches `feature/*`, `main` = versions jouables.

## Contrat `WorldSim` (`src/sim/world_sim.gd`)

Grilles `WIDTH x HEIGHT` en tableaux compacts (index `y * WIDTH + x`) pour pouvoir les envoyer
directement au GPU sous forme de texture :

- `elevation`, `temperature`, `population`, `tech` : `PackedFloat32Array`
- `dominant_species` : `PackedInt32Array` (-1 = aucune)
- `species` : `Dictionary` id -> `{name, alive, sapient, population, traits}`
- `year: float` (commence à -3 800 000 000 ; -66 000 000 dans le scénario court, voir § Prologue)

Méthodes :

- `step(years: float) -> Array[Dictionary]` — avance le temps, renvoie les événements.
- `apply_divine_action(action: Dictionary) -> Array[Dictionary]` — renvoie les conséquences immédiates.
- `current_era() -> String`
- `fork() -> WorldSim` — copie indépendante (timelines alternatives).
- `project_future(years: float) -> Dictionary` — simule une copie en avance pour prévisualiser.

## Action divine

```gdscript
{type: String, region: Vector2i, species_id: int, radius: int}
```

Types : `meteor`, `extinct`, `save`, `bless`, `plague`, `uplift`, `flood`, `ice_age`, `spawn_species`,
et (prologue, utilisables à toute époque) `volcano` (éruption : froid passager, l'oxygène baisse, le
CO2 réchauffera plus tard — de quoi sortir d'une boule de neige), `oxygenate` (souffle divin :
+25 % d'oxygène, fin du fer dissous), `soothe` (apaise la Terre : désamorce les trapps qui
préparent la Grande Mourance).

## Événement

```gdscript
{year: float, type: String, region: Vector2i, species_id: int, summary: String, cause_id: int, id: int}
```

`cause_id` pointe vers l'événement (ou l'action divine) qui l'a provoqué : c'est la **chaîne causale**
qui permet d'afficher « pourquoi » le monde est devenu ce qu'il est.

## Narrateur (`Narrator` autoload)

`narrate(context: Dictionary)` -> signal `narration_ready(text: String)` (asynchrone).

---

## La parcelle, seule vue du jeu (contrat d'octobre 2026)

Vision détaillée : [`PARCELLE.md`](PARCELLE.md). Le jeu se regarde **uniquement** sur une parcelle de
terrain grande comme l'écran, suivie de -66 Ma jusqu'à la fin. Pas de globe ni de carte du monde : la
simulation mondiale tourne en fond et façonne la parcelle.

| Dossier / scène | Branche | Rôle |
|---|---|---|
| `src/parcel/`, `scenes/parcel_view.tscn`, `shaders/parcel*.gdshader`, `assets/parcel/` | `feature/parcel-view` | Vue de haut de la parcelle : terrain, végétation, créatures animées, structures. |
| `src/sim/parcel_sim.gd` | `feature/simulation-core` | État local de la parcelle (contrat ci-dessous). |
| `src/ui/stats/`, `scenes/stats_panel.tscn` | `feature/hud-stats` | Statistiques à l'écran : chaleur, populations montantes / descendantes, courbes. |

`scenes/main.tscn` charge les vues **par chemin** (`src/ui/main.gd`) : `parcel_view.tscn` et
`stats_panel.tscn` si elle existe. Une branche de module livre sa scène sans toucher `main`.
Le HUD se branche (`bind_map`) sur `src/ui/parcel_powers.gd`, qui garde l'API de l'ancienne carte
(`power`, `radius`, `target_species`, `set_*`, `apply_power_at`, signaux `state_changed` /
`region_hovered`) et vise toujours la cellule de la parcelle. L'ancienne carte 2D (`src/map/world_map.gd`,
`world_camera.gd`, `scenes/world_map.tscn`, `shaders/planet.gdshader`) n'est plus chargée.

### `GameState` (ajouts)

- `parcel: ParcelSim`, `view_mode: String` (toujours `"parcel"` ; `"globe"` est conservé pour la
  compatibilité mais plus utilisé)
- `select_parcel(cell: Vector2i)`, `set_view_mode(mode: String)`
- signaux `parcel_updated` (≤ 4 Hz), `parcel_changed(cell: Vector2i)`, `view_mode_changed(mode: String)`
- Les événements de parcelle passent aussi par `event_occurred` (type préfixé `parcel_`).

### Contrat `ParcelSim` (`src/sim/parcel_sim.gd`)

`ParcelSim.new(world: WorldSim, cell: Vector2i)` puis `update(world_events: Array) -> Array[Dictionary]`
(événements de parcelle, même format que WorldSim). Déterministe à graine égale.

| Champ | Type | Sens |
|---|---|---|
| `cell` | `Vector2i` | Cellule de la grille WorldSim (≈ 150 km ; l'écran en montre un échantillon représentatif). |
| `year` | `float` | Année du dernier calcul. |
| `biome` | `String` | Nom du biome (`WorldSim.BIOME_NAMES`). |
| `land_use` | `String` | Une valeur de `ParcelSim.LAND_USES` : `ocean, ice, wild, crater, flooded, camp, pasture, farmland, village, town, city, megacity, arcology, ruins, rewild`, et pour le prologue `seabed` (fonds marins peuplés), `microbial_mat` (hauts-fonds à tapis microbiens / stromatolites), `reef` (récif animal), `barren` (terre nue, sans plantes), `swamp_forest` (forêt marécageuse du Carbonifère). `ocean` = mer sans vie ; `ice` couvre aussi la banquise. |
| `temperature_c`, `global_temperature_c` | `float` | °C local et moyenne mondiale. |
| `vegetation`, `water`, `tech` | `float` 0..1 | Couverture végétale, humidité, niveau technologique local. |
| `fauna` | `Array[Dictionary]` | ≤ `MAX_FAUNA` espèces : `{species_id, name, count (0..MAX_VISIBLE individus à dessiner), density, trend (-1/0/1), role ("herbivore"/"carnivore"/"omnivore"/"sapient", et "producer" pour les microbes et algues marins), size (0..1), clade, diet, change, habitat ("marine"/"amphibious"/"land")}`. En mer : vie marine et amphibie ; à terre : vie terrestre et amphibie (les plantes ne sont pas listées, elles font `vegetation`). |
| `structures` | `Array[Dictionary]` | `{kind ("field"/"hut"/"road"/"building"/"tower"/"ruin"), pos: Vector2 0..1, size}` — positions stables d'une frame à l'autre. |
| `history` | `Array[Dictionary]` | ≤ `HISTORY_SIZE` échantillons `{year, temperature_c, global_temperature_c, population_total, population: {species_id: count}, vegetation, development}`, un tous les `HISTORY_STEPS` pas idéaux. |
| `era`, `land_use_label` | `String` | Ère mondiale ; libellé français de l'usage du sol (« Forêt sauvage », « Tapis microbiens », « Mégapole »…). |
| `development`, `target_development` | `float` 0..8 | Développement continu (0 sauvage … 8 arcologie) et sa cible. |
| `sapient_id` | `int` | Peuple conscient présent (-1 : aucun). |
| `crater_level`, `flood_level`, `scorch_level` | `float` 0..1 | Stigmates d'impact, de crue, de cendres. |
| `alerts` | `Array[Dictionary]` | Crises en cours `{kind ("species_collapse"/"heat_drift"/"civilization_threat"), species_id, severity 0..1, summary, cause_id}`, de la plus grave à la moins grave. |

Règles : on peut **ajouter** des champs, jamais en retirer ou en changer le sens sans mettre à jour
ce document et `tests/test_parcel.gd`. La vue n'invente rien : ce qu'elle montre vient de ces champs
(les déplacements des créatures sont cosmétiques, leur nombre et leur rôle ne le sont pas).

---

## Stratégie : manches, menaces, pistes (contrat d'octobre 2026)

Règles : [`STRATEGIE.md`](STRATEGIE.md). Module `src/strategy/` (branche `feature/strategy`), scène
d'interface `scenes/strategy_hud.tscn` chargée par chemin par `main.gd`.

`GameState.strategy` (créé par `new_world`, `null` tant que le module n'est pas fusionné) expose :

- `aspect: String`, `difficulty: String`
- `round: Dictionary` — `{index, name, stage, starts_year, ends_year, threats: Array[Dictionary]}`
- `actions_left: int`, `actions_per_round: int`
- `tracks: Dictionary` — `{collapses: int, collapse_limit: int, vitality: float 0..1, works: {life, land, mind, legacy: bool}, deck_left: int}`
- `func can_act() -> bool`, `func spend_action(kind: String) -> bool`
- `func counters_for(threat: Dictionary) -> Array[String]` (types de pouvoirs qui la contrent)

Carte de menace : `{id, kind, title, target: {region: Vector2i, species_id: int}, strikes_year: float, severity: float, countered: bool, counters: Array[String]}`.

Signaux relayés par `GameState` : `round_started(round)`, `threat_revealed(threat)`,
`threat_resolved(threat, countered: bool)`, `tracks_changed(tracks)`, `game_over(victory: bool, reason: String)`.

Ajouts (implémentation) : `round` porte aussi `act`, `act_name`, `steps`, `recap` (bilan de la manche
précédente) ; une carte porte aussi `state` (`pending`/`countered`/`struck`/`fizzled`), `revealed`,
`target_name`, `cataclysm`, `returning`. `ends_year` et `strikes_year` sont réestimés au rythme courant
(la manche se mesure en pas idéaux de la simulation). `strategy.seal_work(id)`, `works_ready`,
`visible_next_threats()` (Prophète), signal `action_refused(kind)` sur l'instance.
`GameState.configure_strategy(aspect, difficulty)` (écran de lancement). Argument
`-- --strategy-autostart` : pas d'écran de lancement. La racine causale d'une frappe est de type
`threat_<kind>` (et non `divine_*`) : ce n'est pas un geste du joueur.

Tout pouvoir lancé par le joueur passe par `strategy.spend_action()` (refusé si le budget est épuisé).
Les menaces frappent via `WorldSim.apply_divine_action` ou des perturbations de la simulation : la
chaîne causale reste la seule source de vérité.

## Prologue (contrat d'octobre 2026)

La partie commence à **-3 800 000 000** ans. Étapes du prologue (avant `MESOZOIC`) : Archéen, Grande
Oxydation, Terre boule de neige, Explosion cambrienne, Sortie des eaux, Carbonifère, Grande Mourance
(détails dans `STRATEGIE.md` §1). Les indices d'ères existants changent : le code ne doit plus
supposer `MESOZOIC == 0` mais utiliser les constantes de `src/sim/eras.gd` (`ARCHEAN = 0` …
`GREAT_DYING = 6`, `MESOZOIC = 7`, `CENOZOIC = 8`, `FIRST_SAPIENT_ERA = 9`, `LAST_ERA = 16`) ;
`WorldSim.ERAS == Eras.NAMES`.

### Scénarios

`WorldSim.new(seed, generate := true, scenario := WorldSim.SCENARIO_PROLOGUE)`. Le scénario
`SCENARIO_CRETACEOUS` démarre à -66 Ma avec le roster de la fin du Crétacé (tests, partie courte) ;
la végétation y est implicite et l'oxygène vaut 1.

### Les étapes sont des conséquences

Aucune date n'est scriptée : chaque étape s'ouvre quand l'état du monde l'atteint (jamais en
arrière ; une étape peut être sautée). Sans intervention, les dates tombent près de l'histoire réelle.

| Étape | Déclencheur |
|---|---|
| Grande Oxydation | les cyanobactéries ont épuisé le fer dissous (`oxygen` commence à monter) |
| Terre boule de neige | `snowball` : l'oxygène détruit le méthane plus vite que le CO2 ne compense |
| Explosion cambrienne | ≥ 3 espèces animales (complexité ≥ 3), hors boule de neige |
| Sortie des eaux | un tétrapode (complexité ≥ 5) hors de l'eau |
| Carbonifère | un amniote terrestre (complexité 6) |
| Grande Mourance | trapps (aléa croissant après le Carbonifère, désamorcé par `soothe`) ou extinction de masse (45 % des espèces en 2 Ma) |
| Mésozoïque | 2 Ma après la Grande Mourance, ou dès que des dinosaures sont établis |

Les clades naissent par évolution (`Species.TRANSITIONS`, sous conditions d'oxygène, de flore
terrestre, de niches libres) : microbe → algue → éponge → arthropode / mollusque → poisson →
amphibien → reptile / synapside → dinosaure, ptérosaure, mammifère, oiseau, primate ; algue →
plante ; arthropode → insecte.

### Ajouts publics de `WorldSim`

- `scenario: String`, `oxygen: float` (fraction du niveau actuel), `max_complexity: float` 0..6,
  `land_flora`, `land_fauna: float` 0..1 (part des terres couvertes de plantes / d'animaux),
  `snowball: bool`, `era_years: Dictionary` (indice d'ère -> année d'entrée)
- `current_period() -> String` (« Archéen », « Cambrien »… « Trias », « Jurassique », « Crétacé »),
  `is_prologue() -> bool`, `complexity_name() -> String`
- `region_niches(cell)` : chaque niche porte aussi `habitat`
- traits d'espèce : `complexity`, `habitat` ("marine"/"amphibious"/"land"), `anaerobic`,
  `oxygenic` ; régime `"autotrophe"` pour les producteurs
- événements : `clade` (nouvelle lignée), `snowball`, `thaw`, `traps`, `oxygen`, `soothe`

### Rythme

À x1 avec la boucle du HUD (`MapMath.base_years_per_second(ideal_step_years()) × GameState.pace_factor()`),
le prologue dure 10 à 15 minutes (`Eras.IDEAL_DT`) ; à l'entrée au Mésozoïque, le pas idéal est calé
pour qu'on atteigne -66 Ma en ~20 minutes (`WorldSim.MESOZOIC_STEPS`). Voir `tests/test_sim_prologue.gd`.
