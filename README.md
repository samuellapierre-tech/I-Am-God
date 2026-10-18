# I AM GOD

> Vous êtes Dieu. Tuez, sauvez, anéantissez ou élevez des espèces entières.
> Chaque geste se répercute à travers les âges — des dinosaures jusqu'au cyberpunk.

Jeu PC (Steam) de simulation divine vue de haut, construit avec **Godot 4.3**.

- `docs/ARCHITECTURE.md` — modules, contrats d'API, branches
- `docs/GAME_DESIGN.md` — vision et mécaniques (branche `docs/game-design`)

## Lancer

1. Installer [Godot 4.3](https://godotengine.org/download).
2. Ouvrir `project.godot`, puis F5.
3. (Optionnel) Narrateur IA local : installer [Ollama](https://ollama.com) puis `ollama pull llama3.2:3b`.

## Tests

```bash
godot --headless --path . -s tests/run_tests.gd
```
