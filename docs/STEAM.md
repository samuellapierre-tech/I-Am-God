# Plan Steam — I AM GOD

> Les règles Steamworks évoluent. Tout ce qui est marqué **(à vérifier)** doit être confirmé dans la
> documentation Steamworks officielle (partner.steamgames.com/doc) au moment de l'action. Les
> chiffres marketing (wishlists, conversion) sont des **ordres de grandeur communautaires**, pas des
> règles de Valve.

---

## 1. Étapes Steamworks (chronologie)

| # | Étape | Quand | Notes |
|---|---|---|---|
| 1 | Créer un compte partenaire Steamworks | Fin M0 | Informations fiscales (formulaire type W-8BEN pour un résident français) et bancaires, vérification d'identité. |
| 2 | Payer le **Steam Direct fee : 100 $ par jeu** | Fin M0 / début M1 | Récupérable une fois le jeu passé à 1 000 $ de revenus bruts ajustés (à vérifier). Délai d'attente obligatoire entre le paiement et la sortie, ~30 jours (à vérifier). |
| 3 | Obtenir l'AppID, configurer les dépôts (Windows, Linux) | M1 | Un dépôt par OS ; SteamPipe pour les uploads (`steamcmd` + scripts VDF). |
| 4 | Remplir la page boutique + questionnaire de contenu (dont **IA**, voir §6) | M1 | Revue de Valve de quelques jours ouvrés (à vérifier). |
| 5 | Publier la page **« Coming Soon »** | M1, le plus tôt possible | Doit être visible au moins 2 semaines avant la sortie (à vérifier) ; viser 6-12 mois en pratique pour accumuler des wishlists. |
| 6 | Démo (app de démo séparée liée au jeu) | M1 | Passe aussi par la revue de build. |
| 7 | Inscription **Steam Next Fest** | Selon l'édition | Voir §5. |
| 8 | Revue de build du jeu complet + page Early Access | M2 | Questions spécifiques à l'Early Access sur la page (ce qui est prévu, durée estimée, prix). |
| 9 | Sortie EA, puis 1.0 | M2, M3 | La sortie 1.0 est un événement de visibilité à part entière. |

---

## 2. Page boutique

### Assets graphiques

Dimensions courantes à la date de rédaction — **à vérifier** dans le gabarit Steamworks, Valve les
a déjà modifiées (notamment en 2024).

| Asset | Taille (px) | Priorité |
|---|---|---|
| Header capsule | 920×430 | Critique |
| Small capsule | 462×174 | Critique (lisible minuscule : le titre doit tenir) |
| Main capsule | 1232×706 | Critique |
| Vertical capsule | 748×896 | Haute |
| Page background | 1438×810 | Moyenne |
| Library capsule | 600×900 | Haute |
| Library hero | 3840×1240 | Moyenne |
| Library logo | 1280×720 (PNG transparent) | Moyenne |
| Captures d'écran | 1920×1080, **5 minimum** | Critique |

### Direction de la capsule

- Un seul message visuel : **une main divine (ou un œil) au-dessus d'une planète coupée en deux
  moitiés** — à gauche dinosaures/jungle, à droite néons cyberpunk. Ça dit « des dinosaures au
  cyberpunk » en une image.
- Titre **I AM GOD** énorme, lisible sur la small capsule.
- Faire réaliser la capsule par un·e illustrateur·rice professionnel·le. **Pas de capsule générée
  par IA** : risque de rejet par le public et obligation de déclaration (§6).

### Captures (ordre)
1. Avant/après : même région au Mésozoïque et à l'ère Cyberpunk d'une même partie.
2. Une Chronique (arbre causal) — la fonctionnalité unique.
3. La météorite (moment iconique).
4. Une civilisation saurienne (calque espèces + villes).
5. L'Oracle (vision fantôme du futur).
6. Une prière avec texte du narrateur.

### Trailer (60-90 s)
- 0-5 s : accroche « Et si la météorite n'avait jamais frappé ? »
- 5-40 s : le joueur dévie la météorite → accéléré sur les ères → des sauriens en ville.
- 40-60 s : montage rapide de pouvoirs et d'histoires alternatives (cétacés, monde sans glace).
- 60-80 s : la Chronique se déroule ; titre ; « Ajoutez à votre liste de souhaits ».
- Images de gameplay réel uniquement. Pas de logo de studio de 10 s au début.

### Description courte (proposition)
> Vous êtes Dieu. Des dinosaures au cyberpunk, sauvez, anéantissez ou élevez des espèces entières —
> et regardez chaque geste réécrire l'histoire de la planète.

### Tags suggérés

Steam limite le nombre de tags (20 à la date de rédaction, à vérifier) ; les premiers comptent le
plus.

| Priorité | Tags |
|---|---|
| Cœur | God Game, Simulation, Sandbox, Strategy, Singleplayer |
| Thème | Dinosaurs, Alternate History, Cyberpunk, Evolution, Sci-fi, Futuristic |
| Ressenti | Replay Value, Procedural Generation, Choices Matter, Relaxing |
| Format | Top-Down, Early Access (automatique), Indie, Atmospheric, Colorful |

Vérifier que chaque tag existe exactement sous ce nom dans la liste Steam.

---

## 3. Stratégie de wishlists

Les wishlists déterminent la visibilité au lancement (algorithme de découverte, emails aux
wishlisters à la sortie et lors des promotions).

| Levier | Action concrète |
|---|---|
| Page tôt | Page publiée dès M1, même avec des assets provisoires de qualité correcte. |
| Chronique virale | Bouton « Partager » en fin de partie → image avec le titre du jeu + « Wishlist sur Steam ». |
| Clips courts | 1-2 clips/semaine (TikTok, Shorts, Reddit) : « J'ai sauvé les dinosaures, voici la Terre en 2025 ». Le format « et si…? » est l'accroche. |
| Communautés | r/godgames, r/dinosaurs, r/AlternateHistory, r/godot, r/IndieGaming ; respecter les règles d'autopromotion de chaque sub. |
| Streamers | Cibler les chaînes god game / simulation / « what if ». Clés de démo avant Next Fest. |
| Festivals | Next Fest (principal), festivals thématiques Steam (simulation, stratégie, sci-fi) si éligible. |
| Devlog | Toutes les 2 semaines sur Steam (événements) + Discord. |

Ordres de grandeur souvent cités par les développeurs (non officiels) : ~7 000 wishlists avant
Next Fest pour une bonne visibilité, ~10 000+ au lancement pour espérer apparaître dans les
listes « Populaires à venir ». À traiter comme repères, pas comme objectifs garantis.

---

## 4. Intégration GodotSteam

[GodotSteam](https://godotsteam.com) expose l'API Steamworks à GDScript. Utiliser la version
**GDExtension** compatible Godot 4.3 (plus simple que recompiler l'éditeur) ; vérifier la
version exacte compatible au moment de l'intégration.

| Fonction | API / approche | Jalon |
|---|---|---|
| Initialisation | `Steam.steamInitEx()` au démarrage, dans un autoload `SteamService` isolé ; le jeu doit **fonctionner sans Steam** (builds de dev, tests headless). | M1 |
| Succès | Définis dans Steamworks ; `Steam.setAchievement()` + `Steam.storeStats()`. Un succès par défi du GDD (§12) + fins de partie. | M1 (basiques), M2 (complets) |
| Statistiques | Stats Steam (espèces sapientes créées, météorites lancées) pour succès progressifs. | M2 |
| Steam Cloud | **Auto-Cloud** configuré dans Steamworks sur le dossier `user://saves/` (pas de code) ; passer à l'API Remote Storage seulement si besoin. Sauvegardes compactes : graine + journal des actions + snapshot. | M2 |
| Workshop | API UGC (`createItem`, `submitItemUpdate`, souscriptions). Contenus : **espèces** (fichier JSON de traits + icône) et **scénarios** (monde de départ, graine, objectifs). Validation stricte des fichiers au chargement (schéma, bornes des valeurs) : jamais de script exécutable. | EA+2 / 1.0 |
| Rich Presence | « Ère : Antiquité — 3 civilisations ». | M2 |
| Overlay / Deck | Clavier virtuel pour nommer espèces et parties sur Steam Deck. | M2 |

Contrainte d'architecture : tout l'accès Steam passe par `SteamService` ; `src/sim/` n'en dépend
jamais (les tests headless doivent passer sans Steam).

---

## 5. Steam Next Fest

- Événement de démos plusieurs fois par an (février, juin, octobre historiquement — vérifier les
  dates de l'édition visée).
- Conditions (à vérifier pour chaque édition) : jeu non sorti, page Coming Soon publiée, démo
  jouable soumise avant la date limite, inscription dans Steamworks. Un jeu ne peut participer
  qu'à **une seule** Next Fest (à vérifier) : ne pas la gaspiller sur une démo faible.
- Préparer : démo stable de 30-45 min, livestream préenregistré ou en direct pendant le festival,
  page à jour, trailer final.
- Après le festival : analyser le taux de complétion de la démo et les wishlists gagnées pour
  décider de la date d'EA.

---

## 6. Contenu généré par IA : déclaration Steam

Depuis début 2024, Valve demande de déclarer l'usage d'IA générative dans le questionnaire de
contenu (formulation et détails **à vérifier** dans la version actuelle). Deux catégories :

| Catégorie | Concerne I AM GOD ? | Que déclarer |
|---|---|---|
| **Contenu pré-généré** (assets créés avec l'IA pendant le développement) | À éviter (art, musique, capsule faits à la main). Si du code ou du texte assisté par IA est livré, se renseigner sur ce qui doit être déclaré (à vérifier). | Description de l'usage. |
| **Contenu généré en direct** (pendant le jeu) | **Oui** : narration par LLM local. | Ce qui est généré (texte de narration uniquement), et les **garde-fous** empêchant la génération de contenu illégal. |

Garde-fous à décrire (et à implémenter) :
- Le LLM ne reçoit qu'un contexte structuré produit par la simulation (pas de texte libre du
  joueur au lancement — les noms d'espèces saisis par le joueur sont filtrés).
- Prompt système contraint, longueur de sortie limitée, filtre de mots en sortie.
- Repli procédural en cas de rejet du filtre.
- Option pour désactiver l'IA.
- Steam propose aux joueurs de signaler le contenu IA illégal via l'overlay (à vérifier) ; prévoir
  aussi un bouton « signaler ce texte » en jeu qui journalise le prompt et la sortie.

La page boutique affichera la déclaration IA. Être transparent dans la description : « La narration
peut être générée localement par une IA sur votre machine ; aucune donnée n'est envoyée en ligne.
Désactivable. »

### Distribution du modèle
- **Licence** du modèle (Llama, Qwen, Mistral, Gemma…) : vérifier qu'elle autorise la
  redistribution dans un produit commercial et ses obligations (mention, conditions d'usage).
- Taille : ne pas alourdir le jeu de base. Options : (a) le joueur installe Ollama lui-même
  (documenté, zéro poids), (b) DLC gratuit ou dépôt optionnel contenant le modèle GGUF +
  llama.cpp (faisabilité et règles à vérifier). Recommandation : (a) pour la démo, (b) à évaluer
  pour l'EA.

---

## 7. Prix

| Phase | Prix suggéré (USD) | Justification |
|---|---|---|
| Early Access | 14,99 $ | Contenu partiel, communauté à construire ; zone d'achat impulsif. |
| 1.0 | 19,99 $ | Comparable aux god games / simulations indé de taille moyenne. |
| Remise de lancement | 10-15 % | Courant et efficace sans dévaloriser. |

Utiliser les prix régionaux recommandés par Steam. Annoncer dès l'EA que le prix augmentera à la
1.0 (incite à acheter tôt, honnête).

---

## 8. Configuration matérielle

Priorité **GPU** pour le LLM (VRAM) et les shaders de la planète ; **CPU multicœur** pour la
simulation.

| | Minimum (sans IA) | Recommandé (avec IA locale) |
|---|---|---|
| OS | Windows 10 64 bits / SteamOS / Linux récent | Windows 10/11 64 bits / Linux récent |
| CPU | 4 cœurs / 4 threads, ~2017 (ex. Ryzen 3 1200, i5-7400) | 6 cœurs / 12 threads (ex. Ryzen 5 3600, i5-10400) |
| RAM | 8 Go | 16 Go |
| GPU | Compatible **Vulkan** (Forward+), 2 Go VRAM (ex. GTX 1050, RX 560, Steam Deck) | **6-8 Go VRAM** (ex. RTX 3060, RX 6600) — le modèle 3B quantifié + le jeu doivent tenir en VRAM |
| Stockage | ~1 Go (à mesurer) | + 2-5 Go pour le modèle IA |
| IA | Désactivée → narration procédurale | Ollama ou llama.cpp sur GPU ; CPU possible mais lent |

Remarques :
- Rendu Godot 4 Forward+ = Vulkan obligatoire ; prévoir un repli **Compatibility (OpenGL)** si
  la base de joueurs sur vieux GPU le justifie (à évaluer avec la télémétrie de la démo).
- **Steam Deck** : cible jouable sans IA (la VRAM partagée de 16 Go est tentante, mais
  l'autonomie et la chauffe en pâtissent). IA activable en option « expérimentale ».
- Valeurs à valider par benchmark sur machines réelles avant de les publier sur la page.
