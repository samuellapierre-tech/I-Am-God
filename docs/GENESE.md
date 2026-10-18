# Genèse — la vision définitive (octobre 2026)

> **Ce document remplace** la direction de [`PARCELLE.md`](PARCELLE.md) et de
> [`STRATEGIE.md`](STRATEGIE.md) partout où ils divergent. Le créateur a donné carte blanche sur la
> réalisation ; les choix ci-dessous en découlent.

## En une phrase

Tu es Dieu devant une **planète vierge**. Tu choisis ce que tu y **sèmes**, puis tu regardes ce que
ça engendre, sur un **globe que tu tournes et zoomes**, de la première cellule **jusqu'à la fin des
temps — et au-delà**. Un compagnon, **Ézéchiel**, t'explique tout, tout le long.

## Les principes

1. **Un jeu calme, sans but imposé.** Pas de victoire, pas de défaite, pas de score, pas de budget
   d'actions, pas de compte à rebours. On joue pour passer le temps et regarder vivre son monde.
2. **Aucune proposition imposée.** Le jeu ne pose plus de dilemmes et Samaël se retire : c'est le
   joueur qui décide quand agir, ou s'il agit. (La couche stratégie, Samaël et les dilemmes sont retirés
   du jeu ; leur code reste dans l'historique Git, tag `strategie-pandemic`, si on veut un jour un mode
   défi optionnel.)
3. **Des possibilités infinies.** Rien n'est écrit : pas de dinosaures garantis, pas d'humains
   garantis. Ce qui naît dépend de ce que le joueur a semé, de la planète, du hasard et de ses actes.
4. **Une vraie simulation terrestre.** Plaques, climat, atmosphère, océans, biomes, évolution :
   des règles simples qui se combinent et produisent l'histoire.
5. **Toujours accompagné.** Ézéchiel commente en continu, explique ce qui se passe et pourquoi,
   apprend au joueur la science réelle quand elle s'applique, et invente avec cohérence quand le monde
   s'en écarte.

## La boucle de jeu

```
Planète vierge (roche, océans, atmosphère primitive)
  → Le joueur SÈME : une ou plusieurs formes de vie, où il veut, quand il veut
  → La simulation fait vivre, muter, se répandre, s'éteindre
  → Le joueur regarde, zoome, lit Ézéchiel, consulte les statistiques
  → Quand il en a envie : il sème encore, tue une espèce, en sauve une autre, provoque ou apaise
     un cataclysme, pousse une lignée vers l'intelligence…
  → … jusqu'à la fin des temps, puis la réincarnation.
```

### Semer la vie

Le joueur ouvre une **palette de semences** et pose ce qu'il veut sur le globe :

| Semence | Ce qu'elle fait | Disponible |
|---|---|---|
| **Étincelle** (chimiosynthèse) | Microbes autour des sources hydrothermales ; ne dépend pas du soleil | Dès le début |
| **Lumière** (photosynthèse) | Cyanobactéries : produisent l'oxygène, changent le ciel | Dès le début |
| **Spore** | Colonisatrices des terres nues (lichens, mousses) | Quand l'ozone protège les terres |
| **Germe d'animal** | Une lignée animale simple (filtreur, brouteur, chasseur) | Quand l'oxygène suffit |
| **Créature façonnée** | Le joueur règle quelques traits (taille, régime, milieu, intelligence…) et la pose | Plus tard, coûteux en temps de recharge |

Le reste naît **par évolution** : mutations, spéciation, isolement par la dérive des continents,
radiations après les extinctions. Chaque espèce reçoit un **nom**, une **apparence** et une
**description** générés de façon procédurale à partir de ses traits (et enrichis par l'IA locale si
elle est présente).

### Les pouvoirs (toujours libres, jamais imposés)

Tuer une espèce, en sauver une, bénir une région, météore, volcan, glaciation, réchauffement, déluge,
pousser une plaque, élever une lignée vers l'intelligence, apaiser une catastrophe. Pas de coût en
actions : un simple **temps de recharge** par pouvoir pour garder du poids à chaque geste.

## Le globe

- **Globe 3D** : glisser pour tourner (avec inertie), molette pour zoomer, double-clic pour centrer.
- **Du ciel au sol, sans écran de chargement** :
  - **Orbite** : continents, océans, glaces, nuages, villes la nuit, aurores, atmosphère.
  - **Région** : biomes détaillés, fleuves, forêts, troupeaux visibles comme des taches mouvantes.
  - **Sol** : en zoomant au maximum **n'importe où**, on descend dans une **vue rapprochée** de ce
    lieu, avec ses créatures animées (l'actuelle vue parcelle devient ce niveau de zoom, disponible
    partout, plus seulement sur une parcelle fixe).
- **Plusieurs écosystèmes** côte à côte : récifs, forêts, déserts, toundras, abysses… chacun avec sa
  faune.
- **Calques** : vie, température, ozone, plaques, espèces, civilisations.
- On peut **épingler des lieux** préférés et y revenir en un clic.

## La planète simulée

| Système | Ce qui est simulé | Ce que le joueur voit |
|---|---|---|
| Tectonique | Plaques, supercontinents qui se forment et se fracturent, montagnes, volcans | Les continents bougent |
| Atmosphère | O₂, CO₂, méthane, **couche d'ozone** | Couleur du ciel et de la mer, statistiques |
| Climat | **Température** moyenne et locale, glaciations, effet de serre, niveau des mers | Glaces, déserts, côtes qui changent |
| Océans | Mers peu profondes, abysses, anoxie | Couleur, vie marine |
| Vie | Espèces, populations, chaînes alimentaires, évolution, extinctions | Taches de vie, créatures au sol |
| Civilisations | Si une espèce devient consciente : technologie, villes, guerres, exode | Lumières, villes, routes |
| Soleil | Il vieillit et chauffe lentement la planète | L'horizon lointain |

## Les statistiques

Un panneau toujours disponible, comme aujourd'hui pour les espèces :

- **Chaleur** (moyenne mondiale et locale), **couche d'ozone**, **oxygène**, **CO₂**, **niveau des
  mers**, **couverture de glace** — avec courbes sur la durée.
- **Biomasse**, **biodiversité** (nombre d'espèces vivantes), **extinctions** récentes.
- **Espèces** : population ▲▼ de chacune, filtrable par milieu, régime, taille.
- **Arbre de la vie** : la généalogie de toutes les espèces de la partie, zoomable, qu'on parcourt
  pour retrouver d'où vient une lignée (et ce que le joueur y a changé).

## La fin des temps et la réincarnation

- Le Soleil vieillit : dans environ un milliard d'années de jeu, la planète devient trop chaude pour la
  vie complexe ; plus tard, les océans s'évaporent. C'est la **fin des temps** de cette planète.
- **Réincarnation** : le joueur renaît devant une **nouvelle planète vierge**, différente (taille,
  océans, étoile, inclinaison, graine). Il emporte la **mémoire** de ses mondes passés : un
  **Panthéon** des espèces qu'il a vues naître, consultable, et la possibilité d'en ressemer une.
- Le joueur peut aussi provoquer une fin plus tôt, ou recommencer quand il veut.
- **Sauvegarde automatique** : on reprend son monde des semaines plus tard.

## Ézéchiel

- Compagnon et conteur, **jamais adversaire**, jamais de proposition imposée.
- Il **explique** : pourquoi l'oxygène monte, pourquoi une espèce disparaît, ce qu'est l'ozone, comment
  une île crée de nouvelles espèces… avec des **faits vrais** tant que la planète suit les règles
  connues.
- Il **invente avec cohérence** les mœurs, les cultures et les croyances des espèces conscientes, et
  s'en souvient.
- Il raconte les ères, présente chaque espèce marquante à sa naissance, rédige les épitaphes des
  espèces éteintes, et tient le **grand livre** de la planète.
- **Zéro anachronisme** : il ne parle que de ce qui existe dans le monde à ce moment-là.

## L'IA locale (décision)

**Oui, en option, jamais obligatoire.**

- Le jeu est **complet sans IA** : noms, apparences, descriptions et narration sont générés de façon
  procédurale (gabarits riches, combinatoires, sans répétition).
- Si une IA locale est présente (Ollama aujourd'hui ; un modèle léger intégré via llama.cpp plus tard,
  en téléchargement optionnel), elle **enrichit le texte** : descriptions d'espèces, voix d'Ézéchiel,
  cultures inventées. Elle ne décide **jamais** de ce qui arrive dans le monde : la simulation décide.
- Elle tourne **en arrière-plan** (jamais de gel de l'image), avec un délai maximal et un repli
  immédiat.

## Ce qu'on garde, ce qu'on retire

| Garder et faire évoluer | Retirer du jeu |
|---|---|
| Simulation (prologue, oxygène, CO₂, évolution, futur sans fin) | Couche stratégie (manches, cartes, pistes, Grands Œuvres) |
| Vue parcelle → vue rapprochée au zoom maximal, partout | Samaël |
| Ézéchiel (faits vrais, invention, mémoire, variété) | Dilemmes imposés |
| Statistiques → élargies à la planète | Parcelle fixe unique |
| Pouvoirs → sans budget, avec recharge | Budget d'actions |

## Chantiers (une session par ligne)

| # | Chantier | Dossiers |
|---|---|---|
| 1 | **Globe 3D** : rotation, zoom continu de l'orbite au sol, calques, épingles, vue rapprochée partout | `src/globe/`, `scenes/globe.tscn`, `src/parcel/`, `src/ui/main.gd` |
| 2 | **Planète** : planète vierge, semences, tectonique, ozone, niveau des mers, Soleil vieillissant | `src/sim/` |
| 3 | **Espèces infinies** : génome de traits, noms, apparences procédurales, arbre de la vie | `src/sim/species*`, `src/life/` |
| 4 | **Ézéchiel compagnon** : explications continues, présentations et épitaphes, retrait des dilemmes et de Samaël | `src/ai/` |
| 5 | **Interface calme** : palette de semences, pouvoirs avec recharge, statistiques planétaires, retrait de la stratégie | `src/ui/` |
| 6 | **Fin des temps, réincarnation, sauvegarde** (après 2 et 3) | `src/core/`, `src/save/` |
