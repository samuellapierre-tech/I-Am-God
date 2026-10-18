# La parcelle — vision (octobre 2026)

> Complète [`GAME_DESIGN.md`](GAME_DESIGN.md). En cas de conflit, ce document l'emporte sur la
> présentation (vues, caméra, HUD) ; les piliers et la simulation causale ne changent pas.

## L'idée

On suit **un seul morceau de terrain, grand comme l'écran**, de -66 millions d'années jusqu'à la fin
de l'histoire. Au départ, des dinosaures y passent, broutent, chassent. Des millions d'années plus
tard, ce même sol est peut-être une prairie à mammouths, puis un campement, des champs, un village,
une ville, une mégapole cyberpunk… ou un cratère, une banquise, des ruines envahies par la forêt.

Le joueur **voit le monde évoluer sous ses yeux, au même endroit**. C'est ce qui rend chaque choix
lisible : si on laisse vivre les dinosaures, ce sont eux qu'on verra construire sur cette parcelle.

## Une seule vue : la parcelle

Le jeu ne montre **que la parcelle** : le terrain suivi, plein écran, vu de haut (créatures animées,
végétation, constructions, météo). Pas de globe ni de carte du monde : la planète entière est simulée
en fond et ne se voit qu'à travers ce qu'elle fait à la parcelle (climat, migrations, impacts…).

Contrôles : choisir un pouvoir (1-9 ou barre du bas), clic sur la parcelle pour l'appliquer ;
`[` `]` ou Maj+molette pour le rayon (les pouvoirs à grande échelle — météore, glaciation — touchent
aussi les alentours, qui se répercutent sur la parcelle). La parcelle suivie est choisie au lancement
(`GameState.DEFAULT_PARCEL`, première terre trouvée).

## Statistiques à l'écran

Toujours visibles (mais discrètes) par-dessus la parcelle :

- **Chaleur** : température locale et moyenne mondiale en °C, avec courbe et tendance.
- **Populations** : pour chaque espèce présente sur la parcelle, effectif avec flèche ▲ montante /
  ▼ descendante, couleur par rôle (herbivore, prédateur, omnivore, espèce intelligente).
- **Courbes** : historique température + population totale sur la fenêtre récente.
- Année, ère, usage du sol (« Forêt sauvage », « Terres agricoles », « Mégapole »…).

## Les choix à long terme

Le jeu doit **pousser** le joueur à décider, pas seulement l'occuper :

1. **Le météore** (début de partie) : le lancer ou non. C'est le premier grand choix.
2. **Les crises** : quand une espèce de la parcelle s'effondre (▼ rouge prolongé), quand la chaleur
   dérive, quand une civilisation prie — le temps ralentit et le jeu propose d'agir.
3. **Pas de retour arrière** : l'Oracle montre un futur possible, jamais une certitude.

## Fins

La parcelle finit dans un état : ville florissante, ruines, désert, glace, retour à la nature, ou
**extinction** totale. La Chronique raconte comment ce bout de terre en est arrivé là.

## Terre réelle

Le joueur veut une **planète Terre**. Étape 1 (maintenant) : la planète procédurale de la simulation,
invisible, qui fait évoluer la parcelle. Étape 2 : relief réel de la Terre (cartes du domaine public, p. ex. NASA /
NOAA ETOPO) et continents de la fin du Crétacé qui dérivent vers ceux d'aujourd'hui. Demande un
téléchargement de données à valider.

## Ézéchiel, le narrateur maître du jeu

Un **prophète qui a des visions** : il voit les âges qu'il raconte et s'adresse à Dieu (le joueur)
en le tutoyant, avec respect mais franc-parler. Érudit, curieux, un peu ironique face aux caprices
divins ; il se souvient de tous les choix du joueur et les lui rappelle. Narration **écrite
uniquement**, en continu.

- **Apprendre en jouant** : tant que le monde suit l'histoire réelle, Ézéchiel décrit l'époque
  (climat, faune, mœurs, vie quotidienne) à partir d'une **base de faits vérifiés**, jamais inventés
  par l'IA.
- **Inventer le futur** : dès que le monde diverge (dinosaures survivants, civilisation non humaine,
  ères futures), l'IA locale invente mœurs, cultures et croyances à partir de l'état réel de la
  simulation, et s'en souvient. Ses « visions se troublent ».
- **Dilemmes** : de temps en temps, Ézéchiel met le joueur face à un choix important (2 à 4 options,
  dont « Ne rien faire »). Les options sont des actions divines réelles décidées par le code ; l'IA
  ne fait que les mettre en scène. Le temps ralentit pendant le choix ; sans réponse, rien n'est fait.

Le nom est configurable en un seul endroit (`src/ai/ai_config.gd`).

## Retour de la carte du monde (octobre 2026)

Le créateur veut aussi **voir toute la planète vivre** :

- **Carte du monde** plein écran : molette pour zoomer / dézoomer, glisser pour déplacer (défilement
  gauche-droite sans fin, la planète boucle), clic pour agir. Zoom maximal sur la parcelle → on entre
  dans la vue parcelle ; dézoom depuis la parcelle → retour à la carte. **Tab** bascule aussi.
- **Les continents bougent** : un supercontinent qui se forme puis se fracture (Pangée), des océans
  qui s'ouvrent, des montagnes qui se soulèvent. La dérive est **simulée** (plaques), déterministe,
  et façonne le climat et la vie. La parcelle voyage avec sa plaque.
- **Tout se voit en temps réel** : biomes, glaces, espèces (vie terrestre **et** marine), villes,
  cratères, conséquences des actes divins.

## Des choix déchirants

Le jeu doit **toujours** pousser vers des choix qui coûtent :

- **Aucune option gratuite.** Chaque dilemme oppose des choses auxquelles le joueur tient : sauver une
  espèce en condamne une autre, protéger une civilisation en affame une voisine, arrêter une
  glaciation empêche une lignée de devenir consciente. « Ne rien faire » a aussi un prix, visible.
- **Le prix est montré**, pas caché : une vision de l'Oracle esquisse ce que chaque option coûtera.
- **Personnel** : les dilemmes visent ce que le joueur a protégé, nommé ou fait naître.
- **Rythme** : au moins un grand dilemme par chapitre, plus lors des grands tournants (Pangée qui se
  fracture, météore, première conscience, première ville, première guerre mondiale, IA…).
- Pas de retour en arrière : chaque choix réécrit l'avenir pour toujours.
