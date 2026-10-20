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
| `shore`, `water_depth_m` | `String`, `float` | Rivage : `"sea"`, `"intertidal"` (estran découvert à marée basse ; `land_use_label` devient « Estran à stromatolites »…) ou `"land"`, d'après `WorldSim.sea_level` ; profondeur d'eau en mètres (négative = altitude). Le passage d'un état à l'autre émet `parcel_shore`. |
| `alerts` | `Array[Dictionary]` | Crises en cours `{kind ("species_collapse"/"heat_drift"/"civilization_threat"), species_id, severity 0..1, summary, cause_id}`, de la plus grave à la moins grave. |

Règles : on peut **ajouter** des champs, jamais en retirer ou en changer le sens sans mettre à jour
ce document et `tests/test_parcel.gd`. La vue n'invente rien : ce qu'elle montre vient de ces champs
(les déplacements des créatures sont cosmétiques, leur nombre et leur rôle ne le sont pas).

---

## Stratégie : manches, menaces, pistes (contrat d'octobre 2026)

Règles : [`STRATEGIE.md`](STRATEGIE.md). Module `src/strategy/` (branche `feature/strategy`), scène
d'interface `scenes/strategy_hud.tscn` chargée par chemin par `main.gd`.

`GameState.strategy` (créé par `new_world`, `null` tant que le module n'est pas fusionné) expose :

- `aspect: String`, `difficulty: String`, `mode: String` — `"eternity"` (par défaut) | `"trial"` (§10)
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

### Samaël, l'adversaire (`src/strategy/samael.gd`, STRATEGIE.md §8)

`strategy.samael` : à chaque manche, Samaël reçoit une **main** (intensité + `HAND_EXTRA` cartes
légales tirées de la pioche ; les Cataclysmes sont révélés d'office) et choisit les cartes révélées et
leur moment de frappe ; les autres retournent sous la pioche. La main de la manche suivante est tirée
en début de manche et engagée à `COMMIT_AT` (mi-manche) dans `next_threats` (le Prophète les voit
alors). Il ne crée aucune carte et ne lit que ce que le joueur voit. Niveau selon la difficulté :
`eveil` → `random`, `divin` → `greedy` (dégâts immédiats, Grands Œuvres non scellés, risque
d'effondrement, budget du joueur, habitudes apprises), `apocalypse` → `oracle` (en plus : `fork()` +
projection basse résolution façon `project_future()`, sur un thread dédié : l'image ne paie que la
relève des résultats, sous `ORACLE_BUDGET_USEC` ; le choix attend la fin des projections, qui ont une
demi-manche, pour rester déterministe). Déterministe à graine égale et
à suite d'appels égale.

- Carte choisie : champ `samael: {reason_code: String, score: float}`.
- Signaux (instance et relais `GameState`) : `samael_move(move)` avec
  `move = {kind: "reveal"|"strike"|"taunt_hook", threat: Dictionary, reason_code: String}` et
  `samael_learned(habit)` avec `habit = {power, weight, share}`.
- `reason_code` stables (le texte vient de `src/ai/` ; `src/ui/strategy/strategy_format.gd` en a une
  version courte pour les cartes) : `random`, `max_damage`, `targets_work_<life|land|mind|legacy>`,
  `chain_risk`, `budget_exhausted`, `exploits_habit_<pouvoir>`, `oracle_foresees`, `cataclysm`,
  `fallback`. Accroches `taunt_hook` : `round_open`, `habit_known_<pouvoir>`, `collapse_near`,
  `work_within_reach_<œuvre>`.

### Zéro anachronisme (STRATEGIE.md §9)

Chaque type de carte (`strategy_rules.gd`, `THREATS`) peut porter `min_era`, `max_era` (constantes de
`eras.gd`) et `min_tech` (niveau de la civilisation de tête, donc la technique réelle d'un monde
divergent, pas la date). `Rules.epoch_ok(kind, era, lead_tech)` filtre la pioche, la main de Samaël,
les Cataclysmes et les contres (`Rules.counters(kind, era)`, table `POWER_MIN_ERA`) ; une carte devenue
anachronique (recul d'une civilisation) est remplacée à la révélation et se dissipe si elle n'a pas
encore frappé. Ex. : `famine`/`war` Antiquité, `pollution` Industriel, `nuclear_war` atome (5,25),
`hostile_ai` âge de l'information (`AI_TECH` = 5,75).

### Deux modes : Éternité (par défaut) et Épreuve (STRATEGIE.md §10)

`GameState.strategy_mode` (`"eternity"` par défaut), choisi à l'écran de lancement :
`GameState.configure_strategy(aspect, difficulty, mode)`. `new_world` appelle
`sim.set_endless(mode == "eternity")` si la simulation l'expose (`has_method`).

- **Épreuve** (`trial`) : règles ci-dessus, inchangées (victoire, défaite, `game_over`).
- **Éternité** (`eternity`) : jamais de `game_over`. Une condition de défaite (effondrements au seuil,
  parcelle morte, sablier vide) ou les quatre Grands Œuvres **ferment un chapitre** : signal
  `chapter_closed(chapter)` (instance et relais `GameState`) avec
  `chapter = {index, reason_code: "collapses"|"parcel_dead"|"deck_empty"|"works_complete", reason, collected}`
  (le bilan d'Ézéchiel vient de `src/ai/`). Les menaces restantes se dissipent, les pistes repartent
  (effondrements à 0, Grands Œuvres du cycle à sceller de nouveau, pioche reformée, intensité de départ)
  et un nouveau chapitre commence (`round.name` = « Chapitre N »).
  - Les menaces laissées passer ne comptent pas dans les effondrements (seules les cascades naturelles
    comptent) ; Samaël y est un rival doux (choix au hasard, pas d'apprentissage).
  - `strategy.collection: Array[{work, label, chapter}]` : Grands Œuvres collectionnés sans limite
    (`work = "samael"` : bonus d'un défi) ; `tracks.collected` en donne le nombre.
  - **Défis de Samaël** (`src/strategy/challenges.gd`) : un défi facultatif ouvert à la fois,
    `strategy.challenge = {id, kind, title, text, reward: "action"|"work", reward_text, issued_chapter,
    deadline_chapter, state: "open"|"won"|"lost", species_id, species_name, threshold, goal, progress,
    era_at_issue}` ; `strategy.challenges_done` (20 derniers). `kind` : `keep_alive`, `vitality`,
    `counter`, `quiet`, `new_age`, `new_species`, `civilization` (bornes d'époque comme les cartes ; un
    défi ne nomme que des espèces vivantes). Récompense : +1 action au chapitre suivant ou un Grand
    Œuvre bonus ; un échec ne coûte rien. `samael_move` porte aussi `kind = "challenge"`,
    `"challenge_won"`, `"challenge_lost"` avec `challenge` et `reason_code = "challenge_<kind>"`.

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

### Parcelle de départ

`ParcelSim.pick_start_cell(world)` (appelé par `GameState._liveliest_cell` tant qu'aucune plante n'a
gagné les terres) choisit un haut-fond tiède sur la côte d'un vaste continent : tapis microbiens sous
une eau peu profonde, estran quand la mer recule, terre ferme vers -500 Ma, puis plantes et, plus
tard, dinosaures. `WorldSim.sea_level` (unités d'altitude) suit l'émergence lente des continents et
le climat (bas pendant les glaciations et la boule de neige, haut quand il fait chaud), avec un temps
de réponse de 5 Ma ; il vaut 0 dans le scénario du Crétacé.

## Mode Éternité et futur sans fin (contrat d'octobre 2026)

`WorldSim.endless` (défaut `true`) / `set_endless(on: bool)` : en mode Éternité, la simulation ne
s'arrête jamais ; en mode Épreuve (`false`, piloté par la stratégie), pas d'exode, pas
d'effondrement spontané des civilisations accomplies, pas de renaissance d'un monde stérile.

- Ère `Eras.AFTERMATH` (17, « Âge des héritiers ») : plus aucun peuple conscient après au moins une
  civilisation. Un nouvel éveil ramène à `FIRST_SAPIENT_ERA` (événement `era_change` « Nouveau
  cycle »). `WorldSim.cycles` compte les cycles, `rebirths` les renaissances de la vie.
- Événements : `exodus` (une civilisation post-singularité quitte la Terre : `species[id].departed =
  true`, ses villes deviennent des ruines), `collapse` (effondrement tardif, à partir de l'ère
  moderne), `rebirth` (la vie complexe a disparu, ou la vie renaît d'un monde stérile), `ice_age`
  (glaciations naturelles après le prologue).
- Horizon : le Soleil vieillit après l'an 0 (+0,3 sur l'échelle de température par milliard
  d'années) ; vers +1 Ga, la vie complexe suffoque, microbes et algues survivent.
- Mémoire bornée : `memory_report() -> {history, pinned, indexed, scheduled, species_records, alive,
  runtime_records}` ; journal ≤ 4096 (+512) événements, ≤ 1024 actions divines épinglées, ≤ 2048
  fiches d'espèces, ≤ 128 espèces vivantes, historique de parcelle ≤ 512.

### Sauvegarde (voir la section « Sauvegarde, fin des temps et réincarnation »)

Tout l'état est fait de types simples (tableaux compacts, dictionnaires, nombres) ; aucune
référence circulaire. `WorldSim.fork()` énumère exactement ce qu'il faut sauver :
`seed`, `scenario`, `year`, les grilles (`elevation`, `temperature`, `population`, `tech`,
`dominant_species`, `moisture`, `biome`, `_base_temp`), `species`, `_rt`, `_alive`, l'état de
l'aléa (`_rng.seed`, `_rng.state`), `causal_log` (`next_id`, `history`, `_pinned`, `scheduled`),
les tableaux de l'écosystème (`Ecosystem.copy()` les liste ; `band_cells` se recalcule avec
`build_static()`), et les scalaires listés dans `fork()` (oxygène, climat, niveau marin, cycles…).
`ParcelSim` ne référence que son monde : sauver `cell` et ses champs (publics et privés, tous
simples) ; le recréer par `ParcelSim.new(world, cell)` puis réappliquer ces champs.


## Sauvegarde, fin des temps et réincarnation (contrat d'octobre 2026, `src/save/`)

Branche `feature/save`. Vision : [`GENESE.md`](GENESE.md).

### Ce qui est sauvé

`src/save/serializer.gd` relit par réflexion **toutes les variables de script** de `WorldSim`,
`ParcelSim` et de leurs sous-objets (`Ecosystem`, `Causality`, tout `RefCounted` à script). Un champ
ajouté est sauvé sans rien changer ; un champ disparu est ignoré au chargement ; un champ nouveau
garde sa valeur par défaut ; un type changé est converti si possible. L'identité des objets est
gardée (la parcelle pointe vers le même monde). `RandomNumberGenerator` : graine et état exacts.
Adaptateurs (`src/save/adapters.gd`) :

- champs jamais sauvés : `WorldSim.last_step_usec`, `last_substeps` (mesures), `Ecosystem.g_*`
  (grilles partagées, rebranchées par `bind_grids`), `Causality._by_id` (index reconstruit) ;
- construction : arguments de `_init` passés **par nom** (préfixe `p_` accepté) depuis les champs
  sauvés ; `WorldSim` est construit avec `generate = false` ;
- avant lecture, un objet peut exposer `prepare_save()` (ex. `WorldSim` termine son recalcul de
  géographie sur fil de travail) ; après chargement, `post_load()` (ex. `WorldSim` rebranche
  l'écosystème et remet à zéro `_geo_task`) — appelées si elles existent.

Garantie testée (`tests/test_save*.gd`) : sauver, recharger et avancer de N pas donne **exactement**
le même état, octet pour octet, que sans sauvegarde (prologue et `SCENARIO_CRETACEOUS`, monde seul ou
partie complète via `GameState`).

Instantané d'une partie (`src/save/save_service.gd`, nœud `GameState/Saver`) :
`{world: graphe {sim, parcel}, game: {play_time, world_name, world_index, planet, peaks, created,
parcel_timer, pending_events}, narrator, participants}`.

- **Ézéchiel** : si l'autoload `Narrator` expose `save_state() -> Dictionary` et
  `load_state(state)`, ils sont utilisés (types `var_to_bytes` seulement, clés absentes tolérées) ;
  sinon repli par réflexion sur `chronicle`, `lens`, `variety`, `_divine_history`, `_recent_events`,
  `_last_era`, `_last_stage`.
- **Épingles, statistiques, tout autre état d'interface** : un nœud du groupe `save_state` qui expose
  `save_state() -> Dictionary` et `load_state(state)` est sauvé sous son `name`.

### Fichiers

`user://saves/<emplacement>.igsave` (emplacements `auto`, `quick`, `slot_1`…`slot_3`) : enveloppe
`{magic, version, created_unix, meta, check, payload}` compressée en zstd, écriture **atomique**
(`.tmp` relu et vérifié, puis renommé ; l'ancien fichier sert de secours `.bak` pendant le
remplacement). `<emplacement>.igsave.meta` (JSON) : métadonnées pour le menu. Chargement : refus
propre d'un fichier corrompu (`check`) ou d'une version future, migration des versions anciennes
(`SaveStore.migrate()`, `SaveStore.VERSION`). Sauvegarde automatique toutes les 5 minutes et à la fermeture
(`-- --no-autosave` pour la couper).

### `GameState` (ajouts)

- `save_game(slot := "quick") -> String`, `load_game(slot := "auto") -> String` ("" = réussi).
- `world_name`, `world_index` (n-ième vie du joueur), `planet_params`, `saver`, `pantheon`.
- `new_world(seed, params := {})` : `params` (réincarnation) passés à `WorldSim._init` dans son
  dictionnaire `planet` (`{ocean_fraction, axial_tilt, star_luminosity, plates}`, clés absentes =
  `WorldSim.DEFAULT_PLANET`) ; à défaut d'argument `planet`, chacun par nom ; le reste à
  `configure_planet(params)` s'il existe (`src/save/planet.gd`).
- `adopt_world(sim, parcel, info)` : remplace le monde courant (reprise d'une sauvegarde).
- `reincarnate(params := {}) -> info` : les espèces marquantes rejoignent le Panthéon, puis nouvelle
  planète vierge (paramètres tirés au hasard si `params` est vide).
- `reseed_from_pantheon(entry, cell)` : ressème une espèce du Panthéon comme semence « façonnée » ;
  utilise `WorldSim.sow(action)` s'il existe (action `{type: "spawn_species", kind: "shaped",
  region, radius, traits, name, shaped: true}`), sinon le pouvoir Création, dont l'espèce reçoit le
  nom et les traits.
- Signaux :
  - `end_of_times(summary)` : sur l'événement `end_of_times` de la simulation (une fois par
    planète). `summary = {world_name, world_index, year, age_years, species_total,
    species_max_alive, extinctions, civilizations, notable: [{name, description, clade, sapient}],
    cause}` : **Ézéchiel le raconte**.
  - `world_reborn(info)` : `info = {world_name, world_index, params, previous}`.
  - `game_saved(slot)`, `game_loaded(slot)`.

### Panthéon (`src/save/pantheon.gd`)

`user://pantheon/pantheon.igsave`, à part des sauvegardes : il survit à toutes les réincarnations.
`entries: [{key, name, description, clade, traits, sapient, created_by_god, reason
("conscience"|"création"|"règne"), world_name, world_index, born_year, extinct_year,
peak_regions}]`, `worlds`, `lives`. Retenues à la réincarnation : les peuples conscients, les espèces
créées par Dieu, les 6 plus répandues à leur apogée. Borné à 300 espèces et 100 mondes.

### Menu (`src/ui/menu/`, `scenes/main_menu.tscn`)

Au lancement : Continuer / Nouvelle planète / Panthéon (`-- --no-menu` pour l'éviter). En jeu :
bouton « Menu » en bas à gauche ou F10 (Reprendre, Sauvegarder, Reprendre la dernière sauvegarde,
Panthéon avec « Ressemer », Renaître… avec confirmation, Quitter). Écran calme de fin des temps
(« Contempler encore » ou « Renaître »).
