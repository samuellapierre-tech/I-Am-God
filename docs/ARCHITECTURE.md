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
- `year: float` (commence à -66 000 000)

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

Types : `meteor`, `extinct`, `save`, `bless`, `plague`, `uplift`, `flood`, `ice_age`, `spawn_species`.

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
| `land_use` | `String` | Une valeur de `ParcelSim.LAND_USES` : `ocean, ice, wild, crater, flooded, camp, pasture, farmland, village, town, city, megacity, arcology, ruins, rewild`. |
| `temperature_c`, `global_temperature_c` | `float` | °C local et moyenne mondiale. |
| `vegetation`, `water`, `tech` | `float` 0..1 | Couverture végétale, humidité, niveau technologique local. |
| `fauna` | `Array[Dictionary]` | ≤ `MAX_FAUNA` espèces : `{species_id, name, count (0..MAX_VISIBLE individus à dessiner), density, trend (-1/0/1), role ("herbivore"/"carnivore"/"omnivore"/"sapient"), size (0..1), clade}`. |
| `structures` | `Array[Dictionary]` | `{kind ("field"/"hut"/"road"/"building"/"tower"/"ruin"), pos: Vector2 0..1, size}` — positions stables d'une frame à l'autre. |
| `history` | `Array[Dictionary]` | ≤ `HISTORY_SIZE` échantillons `{year, temperature_c, global_temperature_c, population_total, population: {species_id: count}}`. |

Règles : on peut **ajouter** des champs, jamais en retirer ou en changer le sens sans mettre à jour
ce document et `tests/test_parcel.gd`. La vue n'invente rien : ce qu'elle montre vient de ces champs
(les déplacements des créatures sont cosmétiques, leur nombre et leur rôle ne le sont pas).
