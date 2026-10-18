# Architecture — I AM GOD

Moteur : **Godot 4.3** (GDScript, rendu Forward+). Cible : **Steam, Windows + Linux (Steam Deck)**.

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
