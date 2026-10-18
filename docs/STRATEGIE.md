# Stratégie — toi contre le monde (octobre 2026)

> Complète [`PARCELLE.md`](PARCELLE.md) et [`GAME_DESIGN.md`](GAME_DESIGN.md). Inspiration : les jeux
> de plateau coopératifs à la *Pandemic*, où les joueurs affrontent **le jeu lui-même**. Ici, en solo :
> **Dieu contre l'entropie du monde**. Choix validés par le créateur : solo, temps réel découpé en
> manches, prologue de 10 à 15 minutes depuis les microbes.

## 1. La partie entière : de la première cellule à la fin

| Acte | Période | Durée visée à x1 | Sur la parcelle |
|---|---|---|---|
| **Prologue** | -3,8 Ga → -252 Ma | 10 à 15 min | Mer chaude et tapis microbiens → stromatolites → explosion cambrienne → poissons → sortie des eaux → forêts du Carbonifère → reptiles |
| **Acte I : dinosaures** | Trias → Crétacé (-252 → -66 Ma) | 15 à 25 min | Premiers dinosaures, puis géants, puis le choix du météore |
| **Acte II : après** | -66 Ma → apparition d'une conscience | 10 à 20 min | Mammifères, ou dinosaures qui continuent, glaciations… |
| **Acte III : civilisations** | Éveil → Post-singularité | 60 à 120 min | Camp → champs → village → ville → mégapole… ou ruines |

### Le prologue (étapes et grands choix)

Chaque étape est une **manche** (voir §2). La simulation suit l'histoire réelle si le joueur ne fait
rien ; chaque acte peut la faire bifurquer pour toujours.

| Étape | Âge | Ce qu'on voit | Grand choix possible (dilemme d'Ézéchiel) |
|---|---|---|---|
| Archéen | -3,8 Ga | Océan, volcans sous-marins, tapis microbiens | Où allumer la vie (source chaude ou mare côtière) |
| Grande Oxydation | -2,4 Ga | Les cyanobactéries empoisonnent le monde à l'oxygène | Laisser faire (vie complexe plus tard possible) ou freiner (monde anaérobie) |
| Terre boule de neige | -720 Ma | La planète gèle | Réchauffer (volcans) ou laisser le froid sélectionner |
| Explosion cambrienne | -540 Ma | Yeux, carapaces, prédateurs | Favoriser une lignée : arthropodes, mollusques ou vertébrés |
| Sortie des eaux | -375 Ma | Poissons à pattes, premières forêts | Qui sort de l'eau en premier |
| Carbonifère | -300 Ma | Insectes géants, forêts-charbon | Oxygène élevé maintenu (géants) ou non |
| Grande Mourance | -252 Ma | 90 % des espèces meurent | Empêcher, atténuer ou laisser faire. Décide qui hérite du monde : dinosaures ou ancêtres des mammifères |

## 2. Les manches

Le monde vit **en temps réel** sur la parcelle. Le temps est découpé en **manches** : une étape du
prologue, une ère, ou un jalon (première ville, première guerre mondiale…). Chaque manche se déroule
ainsi :

1. **Révélation** : le jeu retourne ses **cartes de menace** de la manche (§3), visibles dès le début.
   Le joueur sait ce qui arrive, comme dans Pandemic : la tension vient de ce qu'on ne peut pas tout
   empêcher.
2. **Actions divines** : le joueur dispose d'un **budget de N actions** pour la manche (4 au départ).
   Une action = un pouvoir lancé, une vision de l'Oracle, ou une réponse à un dilemme.
   On peut agir à tout moment pendant la manche, en pause ou non.
3. **Résolution** : les menaces non contrées frappent au moment indiqué sur leur carte ; la
   simulation calcule les conséquences (rien n'est scripté).
4. **Bilan d'Ézéchiel** : résumé de la manche, mise à jour des pistes (§4).

## 3. Les cartes de menace (le jeu contre toi)

Le jeu tient une **pioche de menaces** propre à chaque acte : sécheresse, éruption de supervolcan,
épidémie, espèce invasive, glaciation, dérive du climat, famine, guerre, pollution, IA hostile…
Chaque carte vise une région, une espèce ou le monde, et indique **quand** elle frappe dans la manche.

- **Intensité** : à chaque **Cataclysme** pioché (l'équivalent des cartes Épidémie), le nombre de
  menaces révélées par manche augmente et les menaces déjà passées reviennent plus fortes (on
  remélange la défausse sur le dessus de la pioche, comme dans Pandemic).
- **Contrer** : un pouvoir divin bien placé annule ou atténue une menace (déluge contre sécheresse,
  bénédiction contre famine…). Les correspondances sont des règles explicites, affichées sur la carte.
- Les menaces sont **générées à partir de l'état réel de la simulation** (une espèce trop nombreuse
  déclenche « Surpâturage », une civilisation industrielle « Pollution ») : la pioche reflète le monde.

## 4. Les pistes (conditions de victoire et de défaite)

| Piste | Rôle | Fin de partie |
|---|---|---|
| **Effondrements en chaîne** (comme les éclosions) | +1 quand une crise non contrée en provoque une autre (une espèce clé disparaît et entraîne ses prédateurs, une région s'effondre et ses voisines suivent) | 8 → **défaite** : le monde échappe à Dieu |
| **Vitalité de la parcelle** | Biomasse, diversité et population de la parcelle | 0 → **défaite** : la parcelle est morte |
| **Grands Œuvres** (comme les remèdes) | 4 objectifs à accomplir dans la partie : **Vie complexe**, **Conquête des terres**, **Conscience**, **Civilisation pérenne** | Les 4 → **victoire** |
| **Sablier cosmique** | La pioche de menaces s'épuise | Pioche vide avant les 4 Grands Œuvres → **défaite** |

Un Grand Œuvre s'accomplit quand la simulation atteint la condition (par ex. une espèce consciente
pour **Conscience**) **et** que le joueur y consacre des actions au bon moment (« sceller » l'œuvre).
Les fins narratives du GDD (Apothéose, Usurpation, Oubli, Exode…) restent les épilogues possibles
d'une victoire ou d'une défaite.

## 5. Les aspects divins (comme les rôles)

Au lancement, le joueur choisit **un aspect**, qui change son style de jeu :

| Aspect | Pouvoir propre |
|---|---|
| **Le Créateur** | Création d'espèce moins chère ; +1 action quand une espèce naît sur la parcelle |
| **Le Gardien** | Salut et bénédiction contrent deux menaces à la fois |
| **Le Destructeur** | Les catastrophes qu'il lance libèrent des niches : +vitalité après coup |
| **Le Prophète** | Voit les menaces de la manche suivante ; l'Oracle ne coûte pas d'action |

## 6. Difficulté

| Niveau | Actions par manche | Cataclysmes dans la pioche | Seuil d'effondrements |
|---|---|---|---|
| Éveil | 5 | 4 | 10 |
| Divin | 4 | 5 | 8 |
| Apocalypse | 3 | 6 | 6 |

## 7. Ce qui ne change pas

- **La simulation décide, l'IA raconte.** Les cartes, les pistes et les budgets sont des règles du
  jeu ; Ézéchiel les met en scène, il ne les invente pas.
- **Pas de retour arrière.** Chaque acte compte pour toujours.
- Toutes les valeurs ci-dessus sont des **points de départ** à équilibrer en jeu.

## 8. Samaël, l'adversaire (maître de jeu IA)

Choix validés par le créateur : **un adversaire distinct**, nommé **Samaël** (l'accusateur, celui qui
éprouve Dieu) ; **règles fixes, IA pour parler**.

- **Il joue la pioche.** À chaque manche, Samaël reçoit une **main de cartes de menace légales**
  (tirées de la pioche de l'acte, filtrées par l'époque, §9) et choisit celles qu'il révèle et quand
  elles frappent. Il ne crée jamais de carte, ne voit rien que le joueur ne puisse voir, et ses choix
  sont **déterministes à graine égale** (testables, rejouables).
- **Il vise ton plan.** Ses choix sont notés par un algorithme : dégâts prévus sur la vitalité de la
  parcelle et sur les Grands Œuvres en cours, risque d'effondrement en chaîne, menaces que le joueur
  ne peut pas contrer avec le budget qui lui reste.
- **Il apprend tes habitudes.** Il retient les contres que tu utilises le plus et joue ensuite les
  menaces qu'ils ne couvrent pas (« Tu réponds toujours à la sécheresse par le déluge… »).
- **La difficulté, c'est son intelligence :**

| Niveau | Comment Samaël choisit |
|---|---|
| Éveil | Au hasard dans sa main |
| Divin | La carte qui fait le plus mal tout de suite, et il apprend tes habitudes |
| Apocalypse | Il consulte l'Oracle comme toi (`fork()` + `project_future()` à basse résolution) pour viser ce qui fera le plus mal dans plusieurs manches |

- **Il parle.** L'IA locale ne lui sert qu'à s'exprimer : provocations au début de la manche,
  satisfaction quand une menace frappe, dépit quand tu la contres, bluff. Avec un repli procédural
  complet. Ézéchiel et lui se répondent parfois : le prophète témoin, l'accusateur qui doute de Dieu.

## 9. Zéro anachronisme

Rien ne peut apparaître avant son époque : **cartes de menace, options de dilemme, faits racontés,
paroles d'Ézéchiel et de Samaël**.

- Chaque élément porte `min_era` (constante de `src/sim/eras.gd`) et, si besoin, `min_tech`
  (niveau technologique de la civilisation de tête) ; éventuellement `max_era`.
  - Exemples : « IA hostile » et toute décision confiée à une IA → âge de l'information (≈ 2025)
    minimum ; « guerre nucléaire », « pollution industrielle » → âge industriel ; « famine »,
    « guerre » → Antiquité ; « surpâturage » → dès qu'il y a de grands herbivores.
- Les prompts LLM reçoivent l'époque et la liste de ce qui est **interdit** de mentionner ; le texte
  généré est vérifié (liste de mots par époque) et remplacé par le repli procédural s'il dérape.
- Dans un monde divergent (civilisation non humaine), la règle suit **le niveau technologique réel**
  de la simulation, pas la date du calendrier.
- Tests : pour chaque ère, aucune carte, option ou fait au-dessus de son époque n'est disponible.
