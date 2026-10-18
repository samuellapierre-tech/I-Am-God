# Game Design — I AM GOD

> Document vivant, branche `docs/game-design`. Les contrats techniques (API `WorldSim`, format des
> actions et événements) font foi dans [`ARCHITECTURE.md`](ARCHITECTURE.md) ; ce document les
> utilise sans les redéfinir.

---

## 1. Vision

**Pitch en une phrase :** vous êtes Dieu, au-dessus d'une planète vue de haut, de -66 millions
d'années jusqu'à un futur cyberpunk ; chaque geste — sauver un dinosaure, noyer un continent,
souffler une idée à des pieuvres — se propage à travers les âges et réécrit l'histoire.

**La question qui vend le jeu :** *« Et si on avait laissé vivre les dinosaures ? »* Le joueur
ne lit pas la réponse : il la provoque, la regarde se dérouler, puis partage l'arbre causal qui
l'explique.

**Le météore est un choix, jamais un script.** La partie commence à la limite Crétacé-Paléogène et
rien n'arrive tout seul : c'est au joueur de décider s'il lance l'impact de Chicxulub. Sans lui,
les dinosaures continuent de régner et une civilisation saurienne peut naître ; avec lui,
l'histoire des mammifères — la nôtre, ou une autre — devient possible. C'est le premier grand
choix du jeu et le cœur de sa promesse.

### Piliers (ordre de priorité en cas d'arbitrage)

| # | Pilier | Ce que ça veut dire concrètement | Ce qu'on refuse |
|---|---|---|---|
| 1 | **Chaque geste compte** | Toute action divine crée un nœud dans la chaîne causale, visible et traçable jusqu'à la fin. | Des actions « cosmétiques » sans conséquence. |
| 2 | **Lisibilité du « pourquoi »** | Le joueur peut toujours cliquer sur un fait du monde et remonter à sa cause. | Une boîte noire « l'IA a décidé ». |
| 3 | **Surprise systémique** | Les conséquences émergent de règles simples qui se combinent, pas d'un script. | Des embranchements écrits à la main pour chaque cas. |
| 4 | **Histoires partageables** | Chaque partie produit une Chronique exportable (image + texte). | Des parties qui ne laissent aucune trace. |
| 5 | **Dieu, pas gestionnaire** | Peu d'actions, mais énormes. Pas de micro-gestion de villes. | Des menus de construction, des files de production. |

---

## 2. L'idée de design centrale : on ne simule pas « toutes les possibilités »

Le pitch dit : *« simuler les possibilités puis construire un jeu »*. Il faut être honnête : **au
sens littéral, c'est impossible**, et c'est une bonne nouvelle pour le design.

### Pourquoi c'est impossible

- Une partie dure ~66 Ma, découpée en milliers de pas de simulation.
- À chaque pas, le joueur peut faire ~9 types d'actions × des centaines de régions × des dizaines
  d'espèces, ou ne rien faire.
- Même avec seulement 10 choix possibles toutes les 1 000 ans de jeu, on obtient 10^66 000 futurs.
  Il n'y a pas assez d'atomes dans l'univers pour les stocker, ni de temps pour les calculer.
- Pré-écrire les futurs (arbre narratif) se heurte au même mur : un studio AAA écrit quelques
  dizaines de fins, pas 10^66 000.

### Ce qu'on fait à la place : trois couches

| Couche | Rôle | Où (cf. ARCHITECTURE) | Propriétés |
|---|---|---|---|
| **1. Simulation causale systémique** | Calcule *ce qui arrive* à partir de règles : traits des espèces, climat, géographie, technologie, foi. Chaque événement porte un `cause_id`. | `src/sim/` (CPU, `WorkerThreadPool`) | Déterministe à graine égale, rapide, explicable. |
| **2. Oracle (timelines forkées)** | Prévisualise *un* futur plausible à la demande : `fork()` + `project_future(years)` sur une copie. | `src/sim/` | On ne calcule que les futurs que le joueur demande à voir. |
| **3. Narrateur IA locale** | Raconte *ce qui est arrivé* avec style : chroniques, prières, mythes des civilisations. | `src/ai/` (Ollama / llama.cpp + repli procédural) | N'influence **jamais** la simulation. Purement expressif. |

### Pourquoi c'est mieux que « tout simuler à l'avance »

1. **Émergence réelle.** Des règles qui se combinent produisent des situations que personne n'a
   écrites (des sauriens marins qui inventent la navigation avant le feu, parce que leur
   continent est un archipel). C'est ce que le joueur appelle « intelligent ».
2. **Explicabilité.** Chaque fait a une cause traçable. Un LLM qui « décide » l'histoire serait
   incohérent d'une partie à l'autre et impossible à déboguer ou équilibrer.
3. **Coût maîtrisé.** On ne paie le calcul que pour le présent + les futurs explicitement demandés
   à l'Oracle.
4. **Fonctionne sans IA.** Si le LLM est absent ou lent, le jeu reste complet : le repli
   procédural produit des textes à partir de gabarits. L'IA est un bonus d'ambiance, pas une
   dépendance de gameplay.
5. **Rejouabilité.** Mêmes règles + graine différente + choix différents = histoire différente,
   sans contenu supplémentaire à produire.

> **Règle d'or :** la simulation décide, l'IA raconte. Le LLM reçoit un résumé structuré
> (événements + chaîne causale) et renvoie du texte ; il ne renvoie jamais d'état de jeu.

### Ce que le joueur ressent de l'Oracle

« Si je détourne la météorite, à quoi ressemblera le monde dans 60 Ma ? » → l'Oracle forke la
timeline, simule en accéléré en arrière-plan (quelques secondes), et affiche une **vision** :
carte fantôme du futur + 3 faits marquants + une phrase de narration. La vision est
**probabiliste** : l'Oracle utilise une sous-graine différente, donc le futur réel peut diverger.
C'est voulu — Dieu voit des possibles, pas une certitude. Coût en énergie divine (voir §8).

---

## 3. Boucle de jeu

### Boucle courte (30 s – 2 min)

```
Observer la carte (filtres : espèces, climat, foi, tech)
   → Repérer une tension (espèce menacée, civilisation qui stagne, prière)
   → (Optionnel) Consulter l'Oracle sur une action envisagée
   → Agir (pouvoir divin, coûte de l'énergie)
   → Voir les conséquences immédiates (VFX + événements)
   → Le temps reprend
```

### Boucle moyenne (une ère, 10 – 25 min)

Le temps s'accélère entre les événements marquants. À chaque **jalon** (apparition d'une espèce
sapiente, découverte du feu, première ville, première guerre mondiale…), le jeu ralentit, le
narrateur commente, et le joueur peut intervenir. Fin d'ère = écran de transition avec un résumé
narratif et le nouvel état du monde.

### Boucle longue (une partie, 2 – 5 h)

Mésozoïque → Post-singularité. Fin = **Chronique** : l'arbre causal complet de la partie, à
partager. Puis : nouvelle graine, nouveau défi, ou mode bac à sable.

### Contrôle du temps

| Vitesse | Échelle | Usage |
|---|---|---|
| Pause | — | Planifier, consulter l'Oracle, inspecter. Toujours disponible. |
| ×1 | Variable selon l'ère (voir §4) | Observer. |
| ×10 / ×100 | | Avancer jusqu'au prochain jalon. |
| « Jusqu'au prochain événement » | | Saute au prochain événement de priorité ≥ seuil choisi. |

L'échelle de temps est **logarithmique** : au Mésozoïque un pas = ~100 000 ans, à l'ère moderne
un pas = ~1 an. Sans ça, 99,9 % de la partie se passerait avant l'apparition des civilisations.

---

## 4. Les ères

L'ère est **déterminée par l'état du monde, pas par la date** (`current_era()`). Si aucune espèce
ne devient sapiente, on reste dans les ères biologiques ; si les dinosaures sapients développent
l'industrie à -20 Ma, l'ère industrielle commence à -20 Ma.

| Ère | Déclencheur | Pas de temps typique | Ce qui est simulé | Ce qui change pour le joueur |
|---|---|---|---|---|
| **Mésozoïque** | Départ (-66 Ma) | 100 000 ans | Espèces, climat, dérive, niches écologiques | Pouvoirs biologiques et géologiques. La météorite de Chicxulub arrive : la laisser, la dévier, l'amplifier. |
| **Cénozoïque** | Fin de la crise K-Pg (ou son évitement après ~1 Ma) | 50 000 ans | Radiations évolutives, glaciations, migrations | `uplift` débloqué : pousser une lignée vers l'intelligence. |
| **Éveil** | Première espèce `sapient` | 1 000 ans | Outils, feu, langage, foi naissante | La **foi** apparaît : les espèces sapientes vous perçoivent. Premières prières. |
| **Antiquité** | Agriculture + villes | 100 ans | Cités, religions, guerres, routes commerciales | Les miracles deviennent des mythes. Les religions se forment autour de vos actes. |
| **Âge industriel** | Énergie fossile / équivalent | 10 ans | Industrie, pollution, démographie, climat anthropique | Les actions divines laissent des traces mesurables : la science commence à douter de vous (ou à vous prouver). |
| **Âge de l'information** | Réseaux mondiaux | 1 an | Numérique, IA naissante, crises globales | Prières en masse, sectes, lanceurs d'alerte. Risque d'auto-destruction (guerre, climat). |
| **Cyberpunk** | IA forte + mégacités | 1 an | Corporations, augmentations, inégalités | Des civilisations tentent de **vous contacter, vous imiter ou vous pirater**. |
| **Post-singularité** | IA ≥ Dieu en « puissance de calcul » ou expansion spatiale | 1 an | Expansion, transcendance, effondrement | Fin de partie : l'espèce dominante vous rejoint, vous remplace, vous oublie, ou s'éteint. |

Chaque ère a un **profil de simulation** différent (quels sous-systèmes tournent, à quelle
résolution) : pas de calcul diplomatique au Mésozoïque, pas de dérive des continents
significative à l'âge de l'information. C'est aussi un levier de performance.

---

## 5. Pouvoirs divins

Types issus du contrat `apply_divine_action` : `meteor`, `extinct`, `save`, `bless`, `plague`,
`uplift`, `flood`, `ice_age`, `spawn_species`. Chaque pouvoir a un effet **immédiat** (VFX, morts,
changement de grille) et des effets **différés** qui passent par la simulation (jamais scriptés).

| Pouvoir | Coût | Court terme | Long terme (exemples émergents) | Disponible |
|---|---|---|---|---|
| `meteor` | Très élevé | Cratère, extinction locale, hiver d'impact | Libère des niches → radiation évolutive ; vu par des sapients = mythe d'apocalypse, peur ou dévotion | Toutes ères |
| `extinct` | Élevé | Une espèce disparaît (région ou monde) | Ses proies explosent, ses prédateurs s'effondrent ; sur une sapiente : trauma des survivants, foi en un dieu vengeur | Toutes ères |
| `save` | Moyen | Protège une espèce d'une extinction en cours | Une espèce « relique » qui n'aurait pas dû survivre ; peut devenir dominante plus tard | Toutes ères |
| `bless` | Faible | +fertilité / +rendement / +santé dans une région | Explosion démographique → expansion, puis possible famine ou guerre ; foi locale ↑ | Toutes ères |
| `plague` | Moyen | Maladie qui cible une espèce | Immunités, effondrements, réorganisations sociales (cf. peste noire) ; chez des sapients, médecine accélérée | Toutes ères |
| `uplift` | Élevé | +intelligence d'une lignée | Sapience précoce, mais traits inadaptés (pas de mains → outils différents) | Cénozoïque+ |
| `flood` | Moyen | Inonde une région | Migrations, isolement → spéciation ; mythes du déluge | Toutes ères |
| `ice_age` | Très élevé | Refroidissement global | Sélection pour la fourrure, migrations, ponts terrestres ; supprimer une glaciation change tout (voir §6) | Toutes ères |
| `spawn_species` | Très élevé | Crée une espèce à partir d'un gabarit ou de traits choisis | Compétition avec les natives ; peut être un « chef-d'œuvre » ou une espèce invasive | Cénozoïque+ (sandbox : toujours) |

### Règles de design des pouvoirs

- **Peu de pouvoirs, beaucoup de paramètres** (région, rayon, espèce). On n'ajoute un pouvoir que
  s'il crée des conséquences longues qu'aucun autre ne crée.
- **Pas d'annulation.** Pas de Ctrl+Z divin. L'Oracle est le seul moyen de « tester » — c'est ce qui
  donne du poids aux choix. (Exception : sauvegardes manuelles en mode bac à sable.)
- **Les pouvoirs sont vus.** Toute action dans le champ de perception d'une espèce sapiente crée un
  souvenir (voir §7).
- Pouvoirs post-lancement envisagés (seulement si la simulation les supporte) : `inspire`
  (souffler une idée/technologie), `dream` (message à un prophète), `volcano`, `drift`
  (déplacer un continent).

---

## 6. Histoires alternatives (exemples cibles)

Ce sont des **objectifs de validation de la simulation** : si les règles ne peuvent pas produire
ces scénarios de façon plausible, elles sont insuffisantes. Aucun n'est scripté.

| Intervention | Chaîne causale attendue (plausible, pas garantie) | Monde au XXIᵉ siècle-équivalent |
|---|---|---|
| **Météorite déviée** (-66 Ma) | Les dinosaures gardent les grandes niches → les mammifères restent petits et nocturnes → pression sur les petits théropodes à gros cerveau (type troodontidés) → sapience lente, sociale, à plumes | **Civilisation saurienne** : cités sur pilotis dans les régions chaudes, architecture adaptée aux queues, technologie thermique (sang chaud partiel), hiérarchies fondées sur la parade. Pas d'humains. |
| **Météorite détournée + `uplift` sur des hadrosaures** | Herbivores grégaires intelligents → sociétés pacifiques massives, agriculture précoce, conflits avec les théropodes | Empire agricole continental, guerres « inter-espèces » contre des prédateurs semi-sapients. |
| **Cétacés élevés** (`uplift` Cénozoïque) | Intelligence sans mains ni feu → culture orale/sonore, pas de métallurgie → alliance (ou domestication) avec une espèce terrestre à mains | **Civilisation océanique** : chants comme mémoire, technologie biologique, éventuellement contact avec des primates « outils ». Âge industriel très tardif ou absent. |
| **Céphalopodes élevés** + `save` contre leur courte durée de vie | Problème de transmission culturelle (meurent jeunes) → l'élévation seule ne suffit pas ; il faut aussi agir sur la longévité | Cités récifales, écriture chromatique (peau), technologie sous-marine ; l'industrie bloque sur le feu → voie géothermique. |
| **Pas de glaciations** (annuler les `ice_age` naturels du Pléistocène) | Pas de ponts terrestres → pas de migration vers l'Amérique, mégafaune intacte, forêts plus étendues → les primates restent arboricoles plus longtemps | Hominidés tardifs, ou sapience portée par une autre lignée. Niveaux marins plus hauts, côtes différentes. |
| **Peste ciblée sur les hominidés anciens** | Libère la niche → un autre groupe (ours ? corvidés ?) occupe la place | Civilisation de corvidés : petite taille, villes verticales, vol comme avantage logistique. |
| **`bless` massif sur une seule civilisation** | Domination précoce → monoculture → fragilité face à une `plague` ou à un choc climatique | Empire mondial unique, puis effondrement ou stagnation. |
| **Ne rien faire** | La simulation suit à peu près l'histoire terrestre | Une Terre reconnaissable mais jamais identique — sert de **référence** pour l'Oracle (« Écart avec l'histoire réelle : 73 % »). |

Les traits d'espèce (`traits` dans `species`) sont ce qui rend ces récits possibles. Liste
minimale proposée pour la simulation : `size`, `diet`, `metabolism`, `habitat` (terre/mer/air),
`manipulators` (mains, tentacules, bec, aucun), `brain`, `sociality`, `lifespan`, `fertility`,
`cold_tolerance`, `heat_tolerance`. La sapience et la progression technologique en dépendent :
pas de `manipulators` → arbre technologique différent, pas « bloqué ».

---

## 7. Foi, prière et morale

### Pas de bien ni de mal imposés

Le jeu ne juge pas. Il n'y a **pas de jauge Bien/Mal** à la Black & White. Ce sont les
**civilisations** qui jugent, chacune selon ce qu'elle a vécu.

### Mémoire divine

Chaque civilisation sapiente garde une **mémoire** des actes divins perçus (stockée comme liste
d'événements avec `cause_id` vers l'action). Cette mémoire :

- décline avec le temps et se déforme (un `flood` local devient « le Déluge universel » 2 000 ans
  plus tard) ;
- se transmet par contact culturel (conquête, commerce) ;
- détermine la **perception de Dieu** de cette civilisation sur 3 axes :

| Axe | Pôle A | Pôle B | Alimenté par |
|---|---|---|---|
| Bienveillance | Protecteur | Destructeur | `bless`, `save` vs `meteor`, `plague`, `extinct` sur eux |
| Présence | Interventionniste | Absent | Fréquence des actes perçus |
| Prévisibilité | Juste (actes suivant des prières/fautes) | Capricieux | Corrélation entre prières et réponses |

### Prières

À partir de l'Éveil, les civilisations **prient** : demandes concrètes générées par la simulation
(sécheresse → pluie ; invasion → protection ; épidémie → guérison). Elles apparaissent comme des
lueurs sur la carte. Le narrateur IA donne une voix à la prière.

- **Exaucer** : énergie dépensée, foi ↑, prévisibilité ↑.
- **Ignorer** : rien ne se passe — la simulation suit son cours ; la civilisation interprète.
- **Punir/contredire** : possible, avec des conséquences culturelles.

### Ce que la foi change

- **Énergie divine** : la foi totale est la principale source de régénération d'énergie (§8).
- **Comportement** : une civilisation qui croit en un Dieu destructeur devient plus militariste ou
  plus fataliste ; un Dieu absent favorise la science et la sécularisation.
- **Fin de partie** : aux ères Cyberpunk et Post-singularité, les civilisations agissent en
  fonction de leur perception (prier, vous ignorer, vous étudier, vous combattre — voir §9).

Le dilemme intéressant : **plus vous intervenez, plus vous êtes vu ; plus vous êtes vu, plus vous
êtes jugé.** Un Dieu discret peut façonner l'histoire sans laisser de religion.

---

## 8. Ressource : énergie divine

Une seule ressource. Lisible, avec une jauge.

| Source | Ères | Commentaire |
|---|---|---|
| Régénération de base (biomasse totale) | Toutes | Une planète vivante nourrit Dieu. Tuer la vie = s'affaiblir. |
| Foi (somme sur les civilisations) | Éveil+ | Devient dominante à partir de l'Antiquité. |
| Prières exaucées | Éveil+ | Bonus ponctuel + foi. |
| Jalons « inédits » (première espèce sapiente, premier vol spatial…) | Toutes | Récompense la curiosité et les histoires étranges. |

| Dépense | Coût relatif |
|---|---|
| `bless` | 1 |
| `save`, `flood`, `plague` | 3 |
| `extinct`, `uplift` | 6 |
| `meteor`, `ice_age`, `spawn_species` | 10 |
| Vision de l'Oracle (par tranche de futur) | 1 à 4 selon la distance projetée |

Coût **multiplié par le rayon** pour les pouvoirs régionaux. Valeurs initiales indicatives, à
équilibrer en playtest.

Effet voulu : au Mésozoïque, Dieu est pauvre (biomasse seulement) → gestes rares et décisifs.
Plus tard, la foi enrichit Dieu → mais chaque geste est vu et jugé.

---

## 9. Fins de partie et mode bac à sable

### Mode Histoire (par défaut)

La partie se termine quand une **condition de fin** est atteinte. Aucune n'est « la bonne ».

| Fin | Condition | Ton |
|---|---|---|
| **Apothéose** | Une civilisation atteint la post-singularité *et* vous perçoit comme bienveillant | Elle vous rejoint, devient divine à son tour. |
| **Usurpation** | Une IA ou civilisation post-singulière vous perçoit comme destructeur/capricieux | Elle vous détrône ou vous enferme. Le joueur perd ses pouvoirs. |
| **Oubli** | Post-singularité atteinte avec Présence ≈ 0 | Ils ne savent pas que vous existez. Fin mélancolique. |
| **Exode** | Expansion interstellaire | L'histoire quitte votre planète. |
| **Planète silencieuse** | Plus aucune vie complexe | Fin. La Chronique raconte comment. |
| **Auto-destruction** | Une civilisation sapiente détruit la vie (guerre, climat) | Fin, avec option « intervenir au dernier moment » (gros coût). |
| **Limite de temps** | +1 000 ans d'ère Post-singularité sans autre fin | Bilan neutre. |

### Mode Bac à sable

- Énergie illimitée (ou réglable), tous les pouvoirs dès le départ.
- Sauvegardes libres, retour arrière autorisé.
- Choix de l'ère et du monde de départ (Terre réaliste, Pangée, monde-océan, graine aléatoire).
- Éditeur d'espèces (traits) → partageable via Steam Workshop (voir `STEAM.md`).
- Succès Steam désactivés (ou séparés) pour ne pas trivialiser les défis.

---

## 10. La Chronique (récapitulatif causal)

**Fonctionnalité marketing n°1.** C'est ce que les streamers montrent à la fin et ce que les
joueurs partagent sur les réseaux.

### Contenu

- **Arbre causal** de la partie : racines = actions divines, nœuds = événements majeurs, feuilles =
  état final du monde. Construit directement à partir des `cause_id`.
- Élagage automatique : on ne garde que les événements de priorité haute et les chemins qui mènent
  à des issues marquantes (lisible en un écran, ~15-30 nœuds ; vue complète zoomable).
- **Titre généré** de la partie (« L'Âge des Plumes de Bronze ») par le narrateur, avec repli
  procédural.
- Statistiques : écart avec l'histoire réelle, espèces sapientes apparues, actes divins, foi finale
  par civilisation, fin obtenue.
- Graine + liste d'actions → **rejouable** par un autre joueur (code de partage court).

### Formats d'export

| Format | Usage |
|---|---|
| Image PNG verticale (1080×1920) | TikTok, Shorts, stories |
| Image PNG horizontale (1920×1080) | Twitter/X, Reddit, captures Steam |
| Texte (Markdown) | Forums, Discord |
| Code de partage (graine + actions) | « Essaie de battre ma partie » |

### Exemple de chaîne lisible

```
[-66 Ma] Dieu dévie la météorite
  └─ [-40 Ma] Les troodontidés occupent la niche des chasseurs nocturnes
       └─ [-3 Ma] Premiers outils sauriens (archipel du Nord)
            └─ [-8 000] Agriculture des fougères géantes
                 └─ [+1 900] Révolution industrielle géothermique
                      └─ [+2 150] Premier saurien en orbite  ★ Défi « Dinosaures dans l'espace »
```

Mode **streamer** : grosse typo, chaîne animée nœud par nœud avec narration, durée ~60 s, pensé
pour être capturé tel quel.

---

## 11. Difficulté

La difficulté ne change pas les règles de la simulation (sinon les récits deviennent incohérents) ;
elle change **les moyens de Dieu et l'information disponible**.

| Paramètre | Contemplatif | Normal | Exigeant | Dieu fatigué (défi) |
|---|---|---|---|---|
| Régénération d'énergie | ×2 | ×1 | ×0,6 | ×0,3 |
| Précision de l'Oracle | Haute (même sous-graine) | Moyenne | Faible | Désactivé |
| Volatilité des civilisations (guerres, effondrements) | Basse | Normale | Haute | Haute |
| Catastrophes naturelles | Rares | Normales | Fréquentes | Fréquentes |
| Succès | Oui | Oui | Oui (+ succès dédiés) | Oui (+ succès dédiés) |

---

## 12. Rejouabilité

- **Graines** : la planète (relief, continents, climat de départ, espèces initiales) est générée
  depuis une graine, ou « Terre réaliste » fixe.
- **Défis** (objectifs facultatifs, chacun un succès Steam) :

| Défi | Description |
|---|---|
| Dinosaures dans l'espace | Une espèce de dinosaure atteint l'orbite. |
| Océan pensant | Une civilisation 100 % marine atteint l'âge industriel. |
| Dieu caché | Atteindre la post-singularité sans qu'aucune civilisation ne vous ait perçu. |
| Main de fer | Atteindre l'ère Cyberpunk en n'ayant utilisé que des pouvoirs destructeurs. |
| Arche | Plus de 50 % des espèces du Mésozoïque encore en vie à la fin. |
| Monde sans hommes | Aucun primate sapient ; une autre lignée y arrive. |
| Pacifiste | Aucune guerre mondiale dans toute l'histoire. |
| Hérésie | Une civilisation invente une religion qui vous décrit à l'opposé de vos actes. |

- **Défi hebdomadaire** (post-1.0) : même graine pour tous, classement sur un critère (vitesse
  d'atteinte d'un jalon, écart avec l'histoire réelle).
- **Codes de partage** : rejouer la partie d'un autre et dévier à un point choisi.

---

## 13. UX de la carte vue de haut

| Élément | Décision |
|---|---|
| Vue | Planète projetée (equirectangulaire) en vue de haut, zoom continu de la planète entière jusqu'à la région (~1 cellule de grille ≈ quelques pixels). Option globe 3D pour la Chronique et les transitions d'ère seulement. |
| Caméra | Déplacement WASD / bord d'écran / clic molette ; zoom molette ; défilement horizontal **cyclique** (la planète boucle). |
| Filtres (calques shader) | Relief, Température, Espèce dominante, Population, Technologie, Foi, Prières. Touches 1-7. Chaque calque = une texture GPU depuis les grilles `WorldSim`. |
| Inspection | Clic sur une cellule → panneau : espèce dominante, traits, population, et **« Pourquoi ? »** qui remonte la chaîne causale. |
| Pouvoirs | Barre radiale (clic droit) ou barre du bas ; ciblage avec aperçu de zone et coût affiché avant validation. |
| Événements | Fil à droite, filtrable par priorité ; clic = centrer la caméra. Jalons = pause automatique (désactivable). |
| Oracle | Bouton dédié ; vision affichée en surimpression « fantôme » avec curseur avant/après. |
| Manette / Steam Deck | Curseur virtuel au stick gauche, caméra au stick droit, roue de pouvoirs sur gâchette, filtres sur croix directionnelle. Texte ≥ 12 px à 1280×800. Vérifié dès le prototype. |
| Accessibilité | Palettes daltonisme pour tous les calques, taille de texte réglable, pas d'information portée uniquement par la couleur (motifs sur les calques). |

---

## 14. Direction artistique par ère

Principe : **une seule planète, un seul shader**, dont la palette, le grain et les surimpressions
évoluent par ère. Pas de changement de moteur visuel, des transitions fondues.

| Ère | Palette | Rendu de la vie | Signature visuelle |
|---|---|---|---|
| Mésozoïque | Verts saturés, ocres, mers turquoise | Taches de couleur par espèce, troupeaux en particules | Brume chaude, volcans lumineux |
| Cénozoïque | Verts plus froids, steppes dorées, blancs glaciaires | Migrations en flux de particules | Calottes de glace qui pulsent |
| Éveil | Terre + premiers points de feu orange | Points de feu, fumée | Nuit : quelques braises sur la face sombre |
| Antiquité | Tons parchemin en surimpression | Cités = glyphes, routes = traits fins | Style carte ancienne enluminée sur les frontières |
| Industriel | Gris, sépia, ciel brunâtre | Réseau ferré, fumées | Pollution visible en calque |
| Information | Bleu froid, lumières blanches | Réseaux lumineux entre villes | Face nocturne illuminée |
| Cyberpunk | Néons magenta/cyan sur fond sombre | Mégacités pulsantes | Glitchs légers, interfaces holographiques du HUD |
| Post-singularité | Monochrome lumineux, géométrie | Structures orbitales, anneaux | La planète devient partiellement artificielle |

L'UI suit : HUD minéral (pierre gravée) → parchemin → laiton → écran CRT → hologramme. Les
éléments essentiels (énergie, temps, filtres) gardent la même position à toutes les ères.

---

## 15. Direction audio

| Couche | Décision |
|---|---|
| Musique | **Adaptative par ère** : un thème principal décliné (Mésozoïque : percussions, cordes graves, chœurs lointains → Antiquité : instruments modaux → Industriel : cuivres → Cyberpunk : synthés). Superposition de stems selon la tension (catastrophe, guerre, prière). |
| Ambiance | Lit sonore lié au zoom : de loin, « souffle » de la planète ; de près, faune / foule / machines selon la région. |
| Pouvoirs | Sons lourds, graves, avec retard d'impact (la météorite se fait attendre). Chaque pouvoir a une signature reconnaissable. |
| Prières | Murmures dans une langue inventée propre à chaque civilisation (générés procéduralement à partir de syllabes) ; texte affiché par le narrateur. Pas de TTS IA au lancement (risque qualité/licence). |
| Narrateur | Texte à l'écran. Voix enregistrée envisageable pour les transitions d'ère uniquement (budget). |
| Fin / Chronique | Thème complet, version selon la fin obtenue. |

---

## 16. Narrateur IA : périmètre de design

| Le narrateur fait | Le narrateur ne fait pas |
|---|---|
| Résumer un événement ou une ère à partir du contexte structuré | Modifier l'état de la simulation |
| Donner une voix aux prières et aux mythes | Inventer des événements absents de la chaîne causale |
| Titrer la Chronique | Bloquer le jeu (timeout → texte procédural) |
| Varier le style selon l'ère (épique, chronique, rapport, log système) | Générer des images ou de l'audio |

Contraintes : modèle petit (classe 1-4 B paramètres quantifié), contexte court, réponse en ≤ 3 s
visées, sinon repli procédural immédiat et remplacement silencieux si la réponse arrive plus
tard. Le joueur peut désactiver l'IA dans les options. Détails de distribution : voir
`ROADMAP.md` (risques) et `STEAM.md` (déclaration de contenu IA).

---

## 17. Hors périmètre (décisions explicites)

- Pas de multijoueur avant la 1.0.
- Pas de contrôle direct d'unités, de villes ou de personnages.
- Pas de vue au sol / 3D détaillée.
- Pas de LLM décidant du gameplay.
- Pas de génération d'images par IA dans le jeu.
