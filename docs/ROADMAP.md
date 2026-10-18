# Roadmap — I AM GOD

Hypothèse : **dev solo ou équipe de 2-3**, temps plein ou équivalent. Les durées sont des
estimations ; elles glissent toujours. La règle : **on coupe des fonctionnalités, pas des
jalons.** Chaque jalon doit livrer un build jouable.

Références : [`GAME_DESIGN.md`](GAME_DESIGN.md), [`ARCHITECTURE.md`](ARCHITECTURE.md),
[`STEAM.md`](STEAM.md), [`BRANCHING.md`](BRANCHING.md).

## Vue d'ensemble

| Jalon | Durée indicative | Cumul | Objectif | Critère de sortie |
|---|---|---|---|---|
| **M0 — Prototype / vertical slice** | 3-4 mois | ~4 mois | Prouver que « agir au Mésozoïque change le futur » est fun et lisible | 10 testeurs externes jouent 30 min ; ≥ 7 comprennent pourquoi le monde a changé |
| **M1 — Page Steam + démo Next Fest** | 3-4 mois | ~8 mois | Wishlists | Page publiée, démo stable, objectif ≥ 7 000 wishlists avant Next Fest (indicatif) |
| **M2 — Early Access** | 4-6 mois | ~14 mois | Vendre, apprendre, construire la communauté | Partie complète Mésozoïque → Post-singularité jouable, sans crash bloquant |
| **M3 — 1.0** | 6-12 mois | ~20-26 mois | Version complète | Toutes les ères équilibrées, Workshop, localisation, Steam Deck Verified visé |

---

## M0 — Prototype (vertical slice)

**Question unique à laquelle répondre :** *voir sa décision se propager sur des millions d'années
est-il satisfaisant ?* Tout le reste est secondaire.

### Contenu

| Domaine | Branche | Inclus | Exclu |
|---|---|---|---|
| Simulation | `feature/simulation-core` | Grille 256×128, ~20 espèces avec traits, climat simple (température par latitude + événements), chaîne causale (`cause_id`), `step`, `fork`, `project_future`, déterminisme par graine, `WorkerThreadPool` sur les grilles | Tech, foi, civilisations détaillées |
| Ères | `feature/simulation-core` | Mésozoïque → Cénozoïque → Éveil (la sapience apparaît) | Ères au-delà de l'Éveil |
| Carte | `feature/world-map` | Shader planète (relief + calques espèce/température), caméra, zoom, défilement cyclique | Globe 3D, VFX élaborés |
| Pouvoirs | `feature/world-map` | `meteor`, `extinct`, `save`, `ice_age` | Les autres |
| Oracle | les deux | Vision à +10 Ma en surimpression | Curseur avant/après |
| Narration | `feature/ai-narrator` | Repli procédural (gabarits) **d'abord** ; Ollama optionnel si installé par le testeur | LLM embarqué |
| UX | `feature/world-map` | Fil d'événements, panneau « Pourquoi ? » | Prières, filtres avancés |
| Chronique | — | Liste textuelle des chaînes causales principales | Arbre graphique, export |
| Tests | tous | `tests/run_tests.gd` : déterminisme, fork indépendant, intégrité des `cause_id` | — |

### Livrables
- Build Windows + Linux, testé sur Steam Deck (même hors Steam).
- 3 scénarios de validation du §6 du GDD reproduits de façon plausible : météorite déviée,
  pas de glaciation, extinction ciblée.
- Rapport de playtest (même informel).

**Go / no-go :** si les testeurs ne perçoivent pas le lien cause → effet, on retravaille la
lisibilité (panneau « Pourquoi ? », Oracle) **avant** d'ajouter des ères.

---

## M1 — Page Steam + démo Next Fest

### Fonctionnalités jeu
- Ères jusqu'à l'**Antiquité** (civilisations, villes, foi, prières).
- Pouvoirs : les 9 types du contrat.
- Énergie divine (biomasse + foi).
- Foi et mémoire divine (axes Bienveillance / Présence / Prévisibilité, version simple).
- Narrateur : client Ollama/llama.cpp robuste (timeout, repli), prompts par ère.
- **Chronique v1** : arbre graphique + export PNG. Indispensable pour le marketing.
- Direction artistique : Mésozoïque, Cénozoïque, Éveil, Antiquité finalisés.
- Audio : thème principal + 2 déclinaisons.
- Support manette / Steam Deck.
- Sauvegarde / chargement.

### Démo
- Limitée à Mésozoïque → Éveil (ou ~45 min), fin sur une Chronique partageable et un appel à
  wishlister.
- **Démo sans LLM par défaut** (repli procédural) ; IA locale activable si Ollama détecté. Évite
  un téléchargement lourd et les problèmes matériels pendant le festival.

### Steam / marketing (détails dans `STEAM.md`)
- App Steamworks payée, page publiée **au moins 3-6 mois avant** Next Fest (à vérifier selon les
  règles d'éligibilité de l'édition visée).
- Capsules, 5+ captures, trailer 60-90 s centré sur une chaîne causale.
- GodotSteam intégré : succès basiques, overlay.
- Discord + devlog toutes les 2 semaines, clips courts des Chroniques.

---

## M2 — Early Access

### Fonctionnalités
- Toutes les ères jusqu'à **Post-singularité**, avec fins de partie (§9 du GDD).
- Tech par traits (arbres différents selon `manipulators`, `habitat`).
- Mode bac à sable (sans éditeur d'espèces).
- Difficultés.
- 15-20 succès Steam, Steam Cloud.
- Narrateur IA : choix du modèle, téléchargement optionnel (voir risques) ; textes de repli
  étoffés pour toutes les ères.
- Oracle complet (curseur, coût par distance).
- Chronique v2 : mode streamer, export vertical, code de partage (graine + actions).
- Localisation FR + EN (les deux dès l'EA ; FR est la langue de travail).
- Télémétrie **opt-in** (durée des parties, fins obtenues, crashs) pour équilibrer.

### Plan de mises à jour EA (indicatif)
| Mise à jour | Contenu |
|---|---|
| EA+1 (~6 sem.) | Corrections, équilibrage énergie, retours sur la lisibilité |
| EA+2 | Éditeur d'espèces + Workshop (espèces) |
| EA+3 | Scénarios Workshop (monde de départ + objectifs), défis supplémentaires |
| EA+4 | Polish des ères tardives (Cyberpunk, Post-singularité) |

---

## M3 — 1.0

- Équilibrage complet, tous les défis, fins illustrées.
- Workshop : espèces + scénarios.
- Défi hebdomadaire (graine commune).
- Localisation : + DE, ES, PT-BR, ZH-CN, JA (selon données de wishlist par pays).
- Steam Deck Verified (soumission à Valve).
- Accessibilité complète (palettes, tailles de texte, remappage).
- Trailer de lancement, mise à jour de la page.

---

## Risques et mitigations

| Risque | Probabilité | Impact | Mitigation |
|---|---|---|---|
| **Dérive du périmètre** (« Dieu peut tout faire » invite à tout ajouter) | Très haute | Critique | Piliers du GDD comme filtre ; liste « Hors périmètre » ; une nouvelle fonctionnalité doit remplacer une autre de même coût ; jalons à date fixe, on coupe le contenu. |
| **Simulation pas lisible** (le joueur ne voit pas les causes) | Haute | Critique | Go/no-go M0 sur ce seul critère ; panneau « Pourquoi ? » et Chronique prioritaires sur le contenu. |
| **Simulation trop chaotique ou trop convergente** (tous les futurs se ressemblent) | Haute | Haute | Scénarios du §6 comme tests de régression ; métrique « écart avec l'histoire réelle » suivie automatiquement sur N graines en CI. |
| **Taille du modèle IA** (un modèle 3B quantifié pèse ~2 Go ; plusieurs Go pour plus gros) | Haute | Moyenne | Jeu complet sans IA ; modèle **non inclus** dans le build de base : soit Ollama installé par le joueur, soit DLC gratuit / téléchargement optionnel (options à vérifier côté Steam) ; modèle petit par défaut (1-3B). Vérifier la licence du modèle choisi pour la redistribution commerciale. |
| **IA lente / matériel faible / Steam Deck** | Haute | Moyenne | Génération asynchrone, timeout ~3 s, repli procédural immédiat ; IA désactivée par défaut sur Steam Deck et configs sous la spec recommandée ; option CPU. |
| **Contenu IA problématique** (texte offensant, hors sujet) | Moyenne | Haute | Prompts contraints, contexte structuré uniquement, filtre de mots, longueur maximale, déclaration Steam (voir `STEAM.md`), bouton « signaler ce texte ». |
| **Performance de la simulation** (aux ères tardives, beaucoup d'entités) | Haute | Haute | Grilles compactes (`PackedFloat32Array`), `WorkerThreadPool`, profils de simulation par ère, Oracle en tâche de fond à résolution réduite ; budget : `step` ≤ 8 ms au ×1 sur la spec minimale ; benchmark automatisé dès M0. Si GDScript ne suffit pas : portage ciblé de la boucle chaude en GDExtension (C++), pas avant d'avoir mesuré. |
| **Performance GPU** (shaders planète + calques) | Moyenne | Moyenne | Calques en textures de la taille de la grille, upscalés au shader ; qualité réglable ; test Steam Deck à chaque jalon. |
| **Déterminisme cassé par le multithreading** | Moyenne | Haute | Chaque tâche écrit dans des tranches disjointes ; RNG par cellule dérivé de (graine, pas, index) ; test de déterminisme en CI. |
| **Visibilité nulle au lancement** | Haute | Critique | Page Steam tôt, Chronique partageable comme moteur viral, démo Next Fest, contacts streamers/YouTubeurs « god game » et « alternate history ». |
| **Épuisement (solo)** | Haute | Critique | Jalons courts, builds jouables fréquents, pas de crunch avant les festivals ; externaliser musique et capsule art. |

---

## Ce qu'on ne fera pas avant la 1.0
Multijoueur, version console, mobile, voix IA, génération d'images IA, support macOS (à
réévaluer selon la demande — Godot l'exporte, mais tests et signature ont un coût).
