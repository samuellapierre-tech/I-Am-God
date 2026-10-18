# Modèle de branches — I AM GOD

Modèle « git-flow allégé » adapté à une petite équipe et à un découpage par module
(voir [`ARCHITECTURE.md`](ARCHITECTURE.md)).

## Branches permanentes

| Branche | Rôle | Qui y pousse | Protection |
|---|---|---|---|
| `main` | **Versions jouables uniquement.** Chaque commit de `main` est un build livrable (démo, EA, patch), tagué. Contient aussi le contrat partagé `src/core/`. | Merge depuis `develop` (ou `hotfix/*`) via PR | Pas de push direct ; tests verts ; 1 relecture (ou auto-relecture différée de 24 h en solo) |
| `develop` | **Intégration.** Les modules s'y rejoignent ; doit toujours se lancer et passer les tests. | Merge des branches de module / `feature/*` via PR | Pas de push direct ; tests verts |

## Branches de module (longue durée)

| Branche | Dossiers possédés | Contenu |
|---|---|---|
| `feature/simulation-core` | `src/sim/` | Monde, espèces, ères, chaîne causale, fork / projection |
| `feature/world-map` | `src/map/`, `src/ui/`, `shaders/`, `scenes/` | Planète, shaders, caméra, pouvoirs, HUD |
| `feature/ai-narrator` | `src/ai/` | Narrateur LLM local + repli procédural |
| `docs/game-design` | `docs/` (sauf `ARCHITECTURE.md`, modifié via PR dédiée) | GDD, roadmap, Steam, ce document |

Règles :
- Une branche de module **ne modifie que ses dossiers**. Changer un contrat (`src/core/`,
  signatures `WorldSim`, format action/événement) = PR dédiée vers `develop` qui met à jour
  `ARCHITECTURE.md` **et** les tests, revue par les propriétaires des modules concernés.
- Les branches de module **se resynchronisent depuis `develop` au moins une fois par semaine**
  (`git merge develop`) pour éviter la dérive.
- Elles sont mergées dans `develop` **souvent** (dès qu'un incrément fonctionne, idéalement chaque
  semaine), pas à la fin.

## Branches courtes

| Préfixe | Depuis | Vers | Exemple |
|---|---|---|---|
| `feature/<module>-<sujet>` | branche de module ou `develop` | idem | `feature/sim-faith-memory`, `feature/map-oracle-overlay` |
| `fix/<sujet>` | `develop` | `develop` | `fix/fork-shares-species-dict` |
| `hotfix/<version>-<sujet>` | `main` | `main` **et** `develop` | `hotfix/0.3.1-save-crash` |
| `release/<version>` | `develop` | `main` (puis merge retour dans `develop`) | `release/0.2.0-nextfest` |
| `docs/<sujet>` | `develop` | `develop` | `docs/steam-ai-disclosure` |
| `exp/<sujet>` | n'importe où | jamais mergée telle quelle | `exp/gdextension-sim-loop` |

Noms : minuscules, mots séparés par des tirets, en anglais pour le code, court et descriptif.

## Flux de merge

```
feature/sim-xxx ─┐
                 ├─► feature/simulation-core ─┐
feature/map-xxx ─┤                            │
                 └─► feature/world-map ───────┼─► develop ─► release/x.y.z ─► main (tag vX.Y.Z)
feature/ai-narrator ──────────────────────────┤        ▲                         │
docs/game-design ─────────────────────────────┘        └──────── hotfix/* ◄──────┘
```

- **Vers `develop`** : merge commit (`--no-ff`) depuis une branche de module, pour garder la trace
  de l'intégration ; squash autorisé pour les petites branches courtes (`fix/*`).
- **Vers `main`** : uniquement via `release/*` ou `hotfix/*`, merge `--no-ff`, puis tag annoté.
- **Pas de rebase** d'une branche partagée déjà poussée. Rebase local autorisé avant la première
  PR.
- Conflits : résolus dans la branche source (merger `develop` dedans), jamais dans `develop`.

## Versions et tags

[SemVer](https://semver.org/lang/fr/) adapté au jeu : `0.x` jusqu'à la 1.0.

| Tag | Jalon (voir `ROADMAP.md`) |
|---|---|
| `v0.1.0` | Prototype / vertical slice |
| `v0.2.0` | Démo Next Fest |
| `v0.5.0` | Early Access |
| `v1.0.0` | 1.0 |

Chaque tag de `main` correspond à un build uploadé sur une branche Steam (`default` pour les
versions publiques, `beta` pour les tests). Tag annoté : `git tag -a v0.2.0 -m "Démo Next Fest"`.

## Messages de commit

- Langue : français ou anglais, mais cohérent dans une même branche.
- Forme : `<portée>: <résumé à l'impératif>` — ex. `sim: ajoute la mémoire divine par civilisation`,
  `map: calque de foi dans le shader planète`, `docs: plan Steam`.
- Un commit = un changement logique. Pas de « wip » sur `develop` / `main`.

## Lancer les tests

```bash
godot --headless --path . -s tests/run_tests.gd
```

- À lancer **avant chaque PR** et dans la CI sur chaque push vers `develop` / `main`.
- Code de sortie non nul = échec.
- Tests attendus au minimum (côté simulation) : déterminisme à graine égale, indépendance d'un
  `fork()`, intégrité des `cause_id` (chaque cause référencée existe), absence de NaN dans les
  grilles, budget de temps de `step()` sur une grille de référence.
- Les tests ne doivent dépendre **ni de Steam, ni d'un LLM** : le narrateur est testé en mode repli
  procédural.

## Checklist de PR

```markdown
- [ ] La branche cible est correcte (module → develop ; release/hotfix → main)
- [ ] Je n'ai modifié que les dossiers de mon module (sinon : justifié ci-dessous)
- [ ] `godot --headless --path . -s tests/run_tests.gd` passe en local
- [ ] Nouveaux tests ajoutés pour la logique ajoutée (simulation : déterminisme préservé)
- [ ] Si un contrat change : ARCHITECTURE.md + tests mis à jour, propriétaires concernés en relecture
- [ ] Le jeu se lance (F5) et la scène principale fonctionne
- [ ] Pas de régression de perf mesurable (step(), FPS) sur la config de référence
- [ ] Testé sur Linux ou Steam Deck si la PR touche rendu / entrées / chemins de fichiers
- [ ] Aucun secret, clé API, chemin absolu local ou fichier de modèle IA commité
- [ ] Textes joueur en FR (et EN si la localisation est active)
- [ ] Description : quoi, pourquoi, comment tester, captures si visuel
```

## Fichiers à ne jamais commiter
`.godot/` (cache), builds exportés, fichiers de modèle (`*.gguf`), `steam_appid.txt` local de dev
si non partagé, identifiants Steamworks / scripts de build contenant des secrets. Gros binaires
(audio source, PSD) : Git LFS.
