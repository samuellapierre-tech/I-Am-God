# IA locale — Narrateur, Oracle, Prières

Toute l'IA de **I AM GOD** tourne **en local**, sur la machine du joueur, accélérée par le GPU.
Elle est **facultative** : sans serveur LLM, un narrateur procédural (gabarits français variés par ère
et par type d'événement) prend le relais et le jeu reste entièrement jouable.

## Architecture (`src/ai/`)

| Fichier | Rôle |
|---|---|
| `narrator.gd` | Autoload `Narrator` : écoute `GameState`, regroupe les événements, choisit LLM ou repli. |
| `llm_client.gd` | Client HTTP non bloquant (Ollama / llama.cpp), file d'attente, délais, détection auto. |
| `ai_config.gd` | Réglages persistés dans `user://ai_settings.cfg`. |
| `prompt_builder.gd` | Personas, construction des prompts, nettoyage des réponses. |
| `procedural_narrator.gd` | Repli hors-ligne : narration, prophéties, prières, choix moraux. |
| `decision_schema.gd` | Décisions de civilisation en JSON validé + heuristique de repli. |

### API de l'autoload `Narrator`

```gdscript
# Contrat historique : émission toujours asynchrone.
Narrator.narrate(context: Dictionary)                 # -> narration_ready(text: String)
# Oracle « et si ? » à partir de WorldSim.project_future().
Narrator.ask_oracle(question: String, projection: Dictionary)  # -> oracle_answered(text: String)
# Prière d'une espèce sapiente, et choix moraux associés pour l'UI.
Narrator.generate_prayer(species: Dictionary, situation: Dictionary)  # -> prayer_received(species_id: int, text: String)
Narrator.get_prayer_choices(species, situation) -> Array  # [{label, action}] ; action au format « action divine », {} = ne rien faire
# Crochet décisions IA : renvoie tout de suite l'heuristique, puis decision_ready(species_id, decision).
Narrator.suggest_civilization_decision(context: Dictionary) -> Dictionary  # {action, target, reason, source}
Narrator.is_ai_available() -> bool
Narrator.get_backend() -> String      # "ollama" | "llamacpp" | "none"  (+ signal backend_changed)
Narrator.reload_config()              # relit user://ai_settings.cfg et relance la détection
Narrator.auto_narrate = false         # coupe la narration automatique
```

- `context` de narration : `{type, era, year, summary, species_name | species_id, events: Array, action: Dictionary}`.
- `situation` de prière : `{type: "famine"|"war"|"plague"|"disaster"|"cold"|"flood"|"decline"|"prosperity", era, enemy, enemy_id, region, summary}`.
- Décision : `action ∈ {war, expand, research, worship}`, `target` (texte), `reason` (phrase).
  Toute réponse du LLM hors schéma (JSON cassé, action inconnue, raison absente…) est remplacée par l'heuristique.

### Narration automatique

Le narrateur se connecte (défensivement) à `GameState.event_occurred`, `era_changed` et
`divine_action_applied`. Chaque événement reçoit une importance (0..1, ou la clé `importance` fournie par
la simulation) ; ceux sous `min_importance` sont ignorés. Les autres sont mis en lot et racontés au plus
une fois toutes les `min_interval_sec` secondes, les plus importants d'abord. Un geste divin est raconté
presque immédiatement, et ses conséquences sont fondues dans le même récit.

## Installer Ollama (recommandé)

1. Télécharger Ollama : <https://ollama.com/download> (Windows, Linux, macOS). Sous Linux :
   `curl -fsSL https://ollama.com/install.sh | sh`
2. Télécharger un modèle : `ollama pull llama3.2:3b`
3. Lancer le jeu. Le journal affiche `[IA] Backend local détecté : ollama`.

Ollama détecte seul le GPU (CUDA pour NVIDIA, ROCm pour AMD, Metal sur Mac). Le jeu sonde
`http://127.0.0.1:11434/api/tags` au démarrage (délai de 2 s), puis utilise `/api/chat` (`stream: false`).
S'il ne trouve rien, il essaie llama.cpp ; puis il réessaie toutes les 30 s quand une narration est demandée :
on peut donc lancer Ollama en cours de partie.

### Alternative : serveur llama.cpp

```bash
llama-server -m modeles/Llama-3.2-3B-Instruct-Q4_K_M.gguf --port 8080 -ngl 99 -c 2048
```

`-ngl 99` décharge toutes les couches sur le GPU. Le jeu utilise l'API compatible OpenAI
(`/v1/models` pour la détection, `/v1/chat/completions` pour la génération).

## Modèles recommandés selon la VRAM

Le jeu partage le GPU avec le rendu de la planète : comptez **~1 Go de VRAM** pour le jeu lui-même.

| VRAM | Modèle conseillé | Remarque |
|---|---|---|
| Pas de GPU / iGPU | `llama3.2:1b`, `qwen2.5:1.5b` | Tourne sur CPU, réponses en quelques secondes. Ou repli procédural. |
| 4 Go | `llama3.2:3b` (défaut), `qwen2.5:3b`, `gemma2:2b` | Q4, ~2-2,5 Go. Bon français pour 1 à 3 phrases. |
| 8 Go | `qwen2.5:7b`, `mistral:7b`, `llama3.1:8b` | Q4, ~4,5-5 Go. Nettement plus littéraire. |
| 12 Go et + | `mistral-nemo:12b`, `gemma2:9b`, `qwen2.5:14b` | Q4, 7-9 Go. Meilleure qualité narrative en français. |

Les modèles « raisonneurs » (qwen3, deepseek-r1) fonctionnent : le bloc `<think>` est retiré
automatiquement, mais ils sont plus lents pour un gain faible sur des textes courts.

## Réglages (`user://ai_settings.cfg`)

Créé au premier lancement avec les valeurs par défaut. Emplacement de `user://` :
Windows `%APPDATA%\Godot\app_userdata\I AM GOD\`, Linux `~/.local/share/godot/app_userdata/I AM GOD/`.

```ini
[llm]
backend="auto"            ; auto | ollama | llamacpp | off (procédural seul)
ollama_url="http://127.0.0.1:11434"
llamacpp_url="http://127.0.0.1:8080"
model="llama3.2:3b"
temperature=0.8
timeout_sec=20.0          ; au-delà : repli procédural pour cette requête
num_gpu=-1                ; couches sur le GPU (Ollama) : -1 = auto, 0 = CPU seul, 999 = tout sur GPU
keep_alive="10m"          ; durée de maintien du modèle en VRAM entre deux requêtes ("0" = libérer aussitôt)
num_ctx=2048              ; contexte : les prompts du jeu sont courts, inutile d'augmenter (économise la VRAM)
max_tokens=160
max_concurrent=1          ; requêtes simultanées : 1 suffit sur un GPU grand public
max_queue=8               ; au-delà, les narrations les plus anciennes passent en procédural

[narrator]
enabled=true
min_interval_sec=6.0
max_batch=5
min_importance=0.4
```

### Déchargement GPU

- **Tout sur GPU** (le plus rapide) : `num_gpu=999` si le modèle tient dans la VRAM libre.
- **VRAM juste** : laisser `-1`, Ollama répartit seul GPU/CPU ; ou fixer un nombre de couches
  (un 7B en a ~32 : `num_gpu=20` en garde 12 sur CPU).
- **Pas de saccades de rendu** : préférer un modèle plus petit entièrement sur GPU plutôt qu'un gros modèle
  partagé avec le CPU, qui ralentit aussi la simulation (multicoeur).
- `keep_alive` évite de recharger le modèle à chaque narration (premier appel plus lent : chargement en VRAM).

## Distribution Steam

Objectif : le jeu de base reste léger et jouable sans IA ; l'IA est un bonus.

1. **Option A — « apportez votre Ollama »** (la plus simple) : rien n'est fourni, le jeu détecte Ollama
   s'il est installé. Un bouton dans les options peut ouvrir la page d'Ollama et afficher la commande `ollama pull`.
2. **Option B — DLC gratuit / contenu optionnel « Chroniqueur IA »** : un dépôt Steam séparé contenant
   le binaire `llama-server` (llama.cpp, builds CUDA / Vulkan / CPU) et un petit GGUF (ex. Llama 3.2 3B Q4_K_M,
   ~2 Go). Le jeu le lance comme processus enfant (`OS.create_process`) sur `127.0.0.1:8080` avec `-ngl 99`,
   et l'arrête en quittant. Les joueurs qui ne veulent pas de l'IA ne téléchargent rien.
   Le build **Vulkan** de llama.cpp couvre NVIDIA, AMD et Intel (y compris le Steam Deck) sans dépendre de CUDA.
3. **Option C — téléchargement à la demande** du modèle depuis les options (Hugging Face), avec
   somme de contrôle SHA-256 et barre de progression (à éviter si l'on veut rester 100 % hors-ligne).

### Licences (à vérifier par un juriste avant publication)

- **llama.cpp** : licence MIT — redistribution libre, conserver la notice.
- **Ollama** : licence MIT ; on ne le redistribue pas, on l'utilise s'il est présent.
- **Modèles** : chacun a sa licence.
  - Llama 3.x : *Llama Community License* — redistribution autorisée avec la mention « Built with Llama »,
    respect de la politique d'usage acceptable, seuil de 700 M d'utilisateurs mensuels.
  - Qwen 2.5 (la plupart des tailles), Mistral 7B / Nemo : Apache 2.0 — la plus simple à embarquer.
  - Gemma : *Gemma Terms of Use* — redistribution permise avec conditions et restrictions d'usage.
- Steam exige de déclarer l'usage d'IA générative (formulaire « contenu généré par IA ») : préciser qu'il
  s'agit de **génération en direct**, locale, de textes, avec garde-fous (persona, longueur, repli).

## Vie privée

- **Tout est local** : les requêtes ne partent que vers `127.0.0.1` (Ollama ou llama.cpp sur la machine du joueur).
- Aucune télémétrie, aucun compte, aucune clé d'API, aucune donnée envoyée sur Internet par le jeu.
- Les prompts ne contiennent que l'état de la partie (ères, événements, espèces), jamais de données personnelles.
- Changer `ollama_url` vers une autre machine est possible (serveur maison) mais relève du choix du joueur.

## Tests

`tests/test_ai.gd` (aucun réseau requis) : prompts, repli non vide pour chaque ère et chaque type
d'événement, prières et prophéties, validation JSON des décisions (valide, malformé, mauvais schéma),
configuration (défauts, sauvegarde, valeurs invalides), corps de requêtes Ollama / llama.cpp.

```bash
godot --headless --path . -s tests/run_tests.gd
```
