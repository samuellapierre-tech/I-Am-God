# Images de la parcelle

La vue parcelle (`src/parcel/`) dessine des **placeholders** procéduraux (formes et couleurs par
rôle et par clade). Dès qu'une image existe au bon chemin, elle la remplace, sans changer de code.
Résolution : `src/parcel/parcel_logic.gd` (`creature_asset_candidates`, `structure_asset_candidates`).

## Noms de fichiers

Les noms sont « slugifiés » : minuscules, **sans accents**, espaces et tirets remplacés par `_`
(`Ptérosaure` → `pterosaure`, `Forêt tempérée` → `foret_temperee`).
Le premier fichier trouvé gagne, du plus précis au plus générique.

### Créatures — `creatures/`

| Ordre | Fichier | Exemple |
|---|---|---|
| 1 | `<clade>_<role>.png` | `dinosaure_carnivore.png`, `primate_sapient.png` |
| 2 | `<clade>.png` | `dinosaure.png`, `oiseau.png`, `mammifere.png` |

Clades actuels (`src/sim/species.gd`) : `dinosaure`, `oiseau`, `pterosaure`, `reptile`, `mammifere`,
`primate`, `chimere`. Prologue (de la première cellule au Trias) : `microbe`, `algue`, `eponge`,
`arthropode`, `mollusque`, `poisson`, `plante`, `amphibien`, `insecte`, `synapside` (et `meduse` /
`cnidaire`). Rôles : `herbivore`, `carnivore`, `omnivore`, `sapient`.

Un clade inconnu ne plante jamais : il reçoit une silhouette générique tant que son image manque.
Les organismes fixés (`microbe`, `algue`, `eponge`, `plante`) sont dessinés en colonies immobiles qui
ondulent ; les nageurs (`poisson`, `meduse`, grands `arthropode` / `mollusque` chasseurs) en bancs.
Pour un même clade, l'image peut différer sous l'eau et à terre via `<clade>_<role>.png`
(ex. `arthropode_carnivore.png` pour l'anomalocaris, `arthropode_herbivore.png` pour le trilobite).

- **Vue de dessus**, **tête vers la droite** (+x), créature centrée, fond transparent.
- Image **carrée**, 256×256 conseillé (512×512 max). La créature occupe ~75 % de la largeur
  (le carré affiché fait 1,35 × la longueur de la créature, pour laisser la place à la queue).
- Pas d'ombre dans l'image : la vue ajoute une ombre portée et une légère teinte d'espèce.
- La taille à l'écran vient de `size` (0..1) : de 14 à 110 px de long (`creature_length`).

### Structures — `structures/`

| Ordre | Fichier | Exemple |
|---|---|---|
| 1 | `<kind>_<land_use>.png` | `building_megacity.png`, `hut_camp.png` |
| 2 | `<kind>.png` | `field.png`, `hut.png`, `road.png`, `building.png`, `tower.png`, `ruin.png` |

Usages du sol : `ocean, ice, wild, crater, flooded, camp, pasture, farmland, village, town, city,
megacity, arcology, ruins, rewild`.

- **Vue de dessus**, image **carrée**, fond transparent, 256×256 conseillé.
- Affichée dans un carré de côté `size × 1080` px, centré sur `pos`, avec une rotation stable
  (quart de tour + quelques degrés) : l'image doit rester lisible quelle que soit l'orientation.
- `road` est **répétée en mosaïque** le long des deux axes (largeur 16 à 30 px) : image raccordable
  (*tileable*), 64×64 conseillé.

## Production

Les images définitives viendront de GPT puis Higgsfield. Déposer le PNG au bon chemin suffit :
importé par l'éditeur, il est chargé normalement ; un PNG brut non encore importé est aussi lu
(pratique pendant la production, mais seul l'import compte pour un export Steam).
Le sol reste procédural (`shaders/parcel_terrain.gdshader`) ; un éventuel dossier `terrain/`
de textures de détail est une évolution possible, pas encore branchée.
