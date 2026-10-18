# Prompts d'images — I AM GOD (GPT, avant Higgsfield)

Les prompts sont en anglais : les générateurs d'images les suivent mieux. Copie-colle tel quel.
Range les images dans `docs/art/concepts/` avec le numéro du prompt (ex. `P03_cretace.png`).

## Règle de continuité (la plus importante)

Toutes les images de la parcelle montrent **le même terrain, cadré pareil** : vue de haut
(orthographique), une **rivière qui fait un coude en S** de haut à gauche vers bas à droite, et un
**gros rocher plat clair** au tiers gauche. Seul ce qui pousse, vit et se construit dessus change.
C'est ce qui donne l'impression de voir le temps passer au même endroit.

Bloc de style à garder à la fin de chaque prompt de parcelle :

```
STYLE: top-down orthographic view, 16:9, game art for a PC god-simulation game, painterly but crisp, readable silhouettes, soft global lighting from the top-left, rich natural colors, no text, no UI, no perspective tilt. Same composition every time: an S-shaped river from top-left to bottom-right, a large flat pale boulder on the left third.
```

---

## A. Direction artistique

**P01 — Image clé (key art)**
```
Epic key art for a video game titled "I AM GOD": a colossal translucent divine hand of light hovering above planet Earth seen from space, one finger about to touch a tiny glowing patch of land. Around the planet, a spiral of ghostly scenes showing time passing: dinosaurs, mammoths, cave fires, wheat fields, medieval village, factories, a neon cyberpunk megacity. Cinematic, awe-inspiring, deep space blues and golden divine light, 16:9, no text.
```

**P02 — Globe, Crétacé (-66 Ma)**
```
Planet Earth seen from orbit 66 million years ago, late Cretaceous continents (narrow Atlantic, India as an island, shallow inland sea splitting North America), lush green and ochre lands, warm turquoise shallow seas, thin cloud swirls, soft blue atmospheric rim, a bright meteor streak approaching in the distance. Photoreal-stylized game art, 16:9, black space background, no text.
```

## B. La parcelle à travers les âges (même cadrage)

**P03 — Crétacé, les dinosaures règnent**
```
A lush late-Cretaceous floodplain seen from directly above: ferns, cycads, conifers, a herd of duck-billed hadrosaurs grazing near the river, three triceratops at the water, a tyrannosaurus stalking from the forest edge, small feathered raptors in the grass, pterosaur shadows on the ground. [STYLE]
```

**P04 — Juste après l'impact du météore**
```
The same floodplain right after the Chicxulub impact: grey ash covering everything, burnt tree stumps, the river dark and muddy, small fires glowing orange, dead vegetation, a few tiny mammals hiding near the boulder, a dim red-brown light. Desolate but beautiful. [STYLE]
```

**P05 — Cénozoïque, l'âge des mammifères**
```
The same land 30 million years later: open grassland with scattered trees, early horses and large grazing mammals, a group of primates in a tree near the river, birds flocking, golden late-afternoon light. [STYLE]
```

**P06 — Âge glaciaire**
```
The same land during an ice age: snow and permafrost, the river partly frozen, sparse dark pines, a herd of woolly mammoths crossing, a sabre-toothed cat on the boulder, cold blue-white palette. [STYLE]
```

**P07 — Premiers humains, campement**
```
The same land when the first humans arrive: a small camp of hide tents and a campfire next to the boulder, figures carrying spears and baskets, smoke drifting, a few hunted animals, untouched forest around. [STYLE]
```

**P08 — Les premiers champs**
```
The same land at the dawn of agriculture: small irregular wheat and barley fields along the river, a few round mud-brick huts, goats in a wooden pen, footpaths, people working the fields, the boulder used as a gathering spot. [STYLE]
```

**P09 — Village médiéval**
```
The same land as a medieval village: patchwork of fields, a stone bridge over the river, a mill, timber-framed houses, a small chapel built next to the boulder, a dirt road, carts and villagers. [STYLE]
```

**P10 — Ville industrielle**
```
The same land in the industrial age: brick factories with smoking chimneys along the river, a railway line crossing the bridge, rows of worker houses, coal piles, polluted brown water, the boulder now in a small park. [STYLE]
```

**P11 — Ville moderne**
```
The same land as a modern city district: glass office towers, a highway following the river, parks, parking lots, cars, the boulder preserved as a monument in a plaza, dense urban fabric. [STYLE]
```

**P12 — Mégapole cyberpunk**
```
The same land as a cyberpunk megacity at night: enormous neon-lit arcology towers, holographic billboards seen from above, flying vehicles with light trails, the river channelled in a glowing canal, the ancient boulder enclosed in a glass dome as a sacred relic, magenta and cyan lights, rain reflections. [STYLE]
```

**P13 — Ruines et retour de la nature**
```
The same land centuries after humanity's collapse: crumbling concrete towers overgrown with vines and trees, the river reclaiming the streets, deer and wild boars, rusted vehicles under moss, the boulder intact in the middle of a forest clearing. Melancholic, peaceful. [STYLE]
```

**P14 — Histoire alternative : les dinosaures n'ont pas disparu**
```
The same land in an alternate present where dinosaurs were never wiped out: a city built by intelligent feathered dinosaurs, round nest-like buildings on stilts, terraced gardens, domesticated hadrosaurs pulling carts, bridges shaped like bones over the river, warm tropical palette. [STYLE]
```

**P15 — Extinction totale**
```
The same land after total extinction: cracked grey earth, a dry riverbed, no vegetation, a faint toxic haze, only the boulder remains recognizable. Silent and final. [STYLE]
```

## C. Créatures vues de haut (planches de sprites)

Bloc à ajouter à la fin :
```
SPRITE SHEET: top-down view seen from directly above, 4 frames of a walk cycle in a row plus 1 idle and 1 attack/eat frame, consistent scale, plain flat pure-green background (#00FF00) for easy cut-out, game sprite style, clean outlines, no shadow on the background, no text.
```

- **P16** `A tyrannosaurus rex. [SPRITE SHEET]`
- **P17** `A duck-billed hadrosaur (parasaurolophus). [SPRITE SHEET]`
- **P18** `A triceratops. [SPRITE SHEET]`
- **P19** `A small feathered dromaeosaur raptor. [SPRITE SHEET]`
- **P20** `A pterosaur in flight, wings spread. [SPRITE SHEET]`
- **P21** `A woolly mammoth. [SPRITE SHEET]`
- **P22** `A primitive human hunter with a spear. [SPRITE SHEET]`
- **P23** `An intelligent feathered dinosaur citizen wearing simple clothing (alternate-history saurian). [SPRITE SHEET]`

## D. Interface

**P24 — Maquette d'écran de jeu**
```
Video game UI mockup, 16:9, PC god-simulation game "I AM GOD": the main view is a top-down living landscape with dinosaurs. Overlaid, elegant dark translucent panels with golden accents: top bar with year "-65.8 million years" and era "Mesozoic"; right panel "Temperature" with a blue-to-red gauge and a small line chart; right panel "Population" listing species with green up arrows and red down arrows and small bars; bottom bar of divine power icons (meteor, flood, ice age, plague, bless, save); bottom-left a narrator text box. Clean, readable, modern.
```

## E. Steam

**P25 — Capsule principale (460×215, à recadrer)**
```
Steam store capsule art for "I AM GOD": a giant divine hand of light above a split landscape seen from above — left half a Cretaceous jungle with dinosaurs, right half a neon cyberpunk city — the same S-shaped river running through both. Bold readable composition, strong contrast, space at the top for a logo, no text.
```

---

## Préparer Higgsfield (crédits le 20 octobre)

Quand une image GPT te plaît, garde-la comme **référence de style** : Higgsfield pourra animer les
parcelles (P03 → P12 en transitions vidéo), animer les sprites et produire le trailer. Note ici les
numéros retenus pour qu'on monte le plan d'animation à partir d'eux.
