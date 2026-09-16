# Water Wars — jeu de pistolets à eau pour Roblox

Un jeu de tir à l'eau multijoueur **jouable à 20 joueurs**, avec **25 armes** et
**6 terrains**. Tout est généré par le code au lancement : aucune image, aucun
son, aucun modèle à importer sur Roblox. Vous ouvrez le fichier, vous cliquez
sur *Play*, ça tourne.

---

## 1. Importer le jeu dans Roblox Studio

Trois méthodes, de la plus simple à la plus avancée. **La méthode A suffit dans
99 % des cas.**

### Méthode A — ouvrir la place complète (recommandé)

1. Téléchargez le fichier **`build/WaterWars.rbxlx`**.
2. Dans Roblox Studio : **Fichier → Ouvrir depuis le fichier…** puis sélectionnez
   `WaterWars.rbxlx`.
3. Appuyez sur **Play** (F5). C'est tout.
4. Pour publier : **Fichier → Publier sur Roblox sous…**

> ### « Le Workspace est vide, il n'y a aucune map ! »
>
> **C'est normal, et c'est voulu.** Le fichier ne contient que du code : les
> 6 terrains sont **construits par le code au moment où la partie démarre**,
> pas stockés en dur dans le fichier. En mode édition vous ne voyez donc qu'un
> Workspace vide — il n'y a rien à réparer.
>
> Appuyez sur **Play (F5)** : le terrain apparaît en une fraction de seconde,
> et la fenêtre *Output* (Affichage → Output) affiche la confirmation :
>
> ```
> [WaterWars] Serveur pret - 25 armes, 6 maps, 20 joueurs max.
> [WaterWars] Terrain construit : Jardin d'Ete (311 pieces) -> workspace.CurrentMap
> ```
>
> Pendant la partie, le terrain vit dans `workspace.CurrentMap` : vous pouvez
> le voir apparaître dans l'Explorateur. Il est détruit et remplacé à chaque
> changement de terrain, ce qui rend le nettoyage de fin de manche instantané.
>
> C'est ce choix qui permet d'avoir 6 terrains et 1 385 pièces de décor dans
> un fichier de 265 Ko, sans aucun asset à uploader.

### Méthode B — ajouter le jeu à une expérience existante

1. Téléchargez **`build/WaterWars.rbxmx`**.
2. Dans Studio, clic droit sur *Workspace* dans l'Explorateur → **Insert from
   File…** → sélectionnez `WaterWars.rbxmx`.
3. Trois dossiers apparaissent, chacun porte sa destination dans son nom.
   Glissez le **contenu** de chacun à l'endroit indiqué :

   | Dossier inséré | Destination |
   |---|---|
   | `1 - A METTRE DANS ReplicatedStorage` | `ReplicatedStorage` |
   | `2 - A METTRE DANS ServerScriptService` | `ServerScriptService` |
   | `3 - A METTRE DANS StarterPlayer.StarterPlayerScripts` | `StarterPlayer → StarterPlayerScripts` |

4. Supprimez les trois dossiers vides, puis appuyez sur **Play**.

### Méthode C — Rojo (pour développer en dehors de Studio)

```bash
rojo serve          # utilise default.project.json
# puis, dans Studio : plugin Rojo → Connect
```

### Réglages à faire sur le site Roblox

Deux choses ne peuvent pas être mises dans un fichier, il faut les cocher une
fois la place publiée :

- **20 joueurs par serveur** : page de l'expérience → *Paramètres* → *Places* →
  `Max Players = 20`.
- **Sauvegarde des pièces et des armes** : Studio → *Game Settings* → *Security*
  → activer **Enable Studio Access to API Services**. Sans cette option, le jeu
  fonctionne parfaitement mais les achats ne sont pas conservés d'une session à
  l'autre (un message d'avertissement clair s'affiche dans la console).

---

## 2. Les commandes

| Action | Touche |
|---|---|
| Tirer | Clic gauche (maintenir pour les armes automatiques et les armes à charge) |
| Viser | Clic droit |
| Recharger | R |
| Courir | Maj gauche (consomme l'endurance) |
| Boutique / vestiaire | B |
| Tableau des scores | Tab (maintenir) |
| Changer d'arme | 1 et 2 |

Le jeu est jouable au clavier/souris, à la manette et sur mobile (le tir se fait
par appui sur l'écran).

---

## 3. Le déroulé d'une partie

1. **Échauffement** — tout le monde apparaît sur le terrain en cours, les tirs
   sont autorisés mais ne comptent pas au score.
2. **Vote** — trois terrains sont proposés, chacun vote d'un clic (18 s).
3. **Manche** — 5 minutes, ou jusqu'à ce que la limite de score soit atteinte.
4. **Résultats** — classement, versement des pièces, puis on recommence.

Trois modes tournent automatiquement :

| Mode | Principe |
|---|---|
| **Bataille d'équipes** | Deux camps, premier à 60 points. |
| **Roi de la piscine** | Contrôler la zone centrale rapporte des points en continu. |
| **Chacun pour soi** | Tout le monde contre tout le monde, premier à 25 éliminations. |

Pendant la manche : bonus au sol (turbo, haute pression, bouclier, citerne),
stations de recharge d'eau, protection à l'apparition, régénération hors combat,
séries d'éliminations, assistances.

---

## 4. Les 25 armes

Achetées avec les pièces gagnées en jouant, puis équipées en arme principale ou
secondaire depuis la boutique (touche **B**).

| # | Arme | Catégorie | Rareté | Dégâts | Cadence | DPS | Réservoir | Prix |
|---|---|---|---|---|---|---|---|---|
| 1 | **Pistolet Eclaboussure** | Pistolet | Depart | 14 | 4.5 | 63 | 72 | gratuite |
| 2 | **Blaster de Poche** | Pistolet | Commun | 11 | 7.2 | 79 | 60 | 450 |
| 3 | **Drencher .45** | Pistolet | Epique | 13 | 2.4 | 94 | 72 | 2600 |
| 4 | **Tidal SMG** | Mitraillette | Commun | 9 | 11.0 | 99 | 120 | 800 |
| 5 | **Micro-Splash** | Mitraillette | Rare | 8 | 12.0 | 96 | 132 | 1500 |
| 6 | **Hydro Uzi** | Mitraillette | Epique | 8 | 16.0 | 128 | 150 | 2900 |
| 7 | **Fusil a Jet** | Fusil | Depart | 17 | 6.5 | 111 | 110 | gratuite |
| 8 | **Carabine Aqua** | Fusil | Commun | 15 | 8.0 | 120 | 110 | 950 |
| 9 | **Hydro AR** | Fusil | Rare | 16 | 3.2 | 154 | 120 | 2100 |
| 10 | **Repeteur a Impulsion** | Fusil | Epique | 21 | 5.5 | 116 | 100 | 3400 |
| 11 | **Fusil a Eclaboussures** | Pompe | Commun | 8 | 1.2 | 77 | 56 | 1100 |
| 12 | **Lance-Seau** | Pompe | Rare | 7 | 1.0 | 84 | 60 | 2200 |
| 13 | **Brise-Vague** | Pompe | Epique | 9 | 2.4 | 194 | 32 | 3800 |
| 14 | **Goutte de Precision** | Sniper | Commun | 48 | 1.2 | 58 | 36 | 1400 |
| 15 | **Hydro Sniper** | Sniper | Rare | 62 | 0.8 | 53 | 30 | 2500 |
| 16 | **Longue Portee** | Sniper | Legendaire | 55 | 0.6 | 33 | 24 | 5200 |
| 17 | **Minigun Torrent** | Lourde | Epique | 11 | 13.0 | 143 | 260 | 4200 |
| 18 | **Lance a Incendie** | Lourde | Rare | 7 | 20.0 | 140 | 300 | 2700 |
| 19 | **Canon a Pression** | Lourde | Legendaire | 30 | 1.1 | 33 | 60 | 5600 |
| 20 | **Lance-Ballons** | Lanceur | Commun | 18 | 0.9 | 16 | 24 | 1300 |
| 21 | **Bombe-Seau** | Lanceur | Rare | 22 | 0.7 | 15 | 18 | 2400 |
| 22 | **Mortier Geyser** | Lanceur | Legendaire | 20 | 0.5 | 10 | 12 | 6000 |
| 23 | **Rayon Glace** | Speciale | Legendaire | 9 | 9.0 | 81 | 140 | 6500 |
| 24 | **Pulverisateur Arc-en-Ciel** | Speciale | Epique | 11 | 8.0 | 88 | 130 | 3900 |
| 25 | **Souffleur de Vapeur** | Speciale | Rare | 6 | 14.0 | 252 | 180 | 2300 |

*Tableau généré automatiquement depuis `src/ReplicatedStorage/WaterWars/Config/Weapons.luau`.*

Chaque arme possède aussi une portée, une gravité, une dispersion, un nombre de
gouttes par tir, un rayon d'éclaboussure, un ralentissement, un soin, un temps
de charge et un multiplicateur de dégâts à la tête qui lui sont propres.

---

## 5. Les 6 terrains

| Terrain | Ambiance | Ce qui le caractérise |
|---|---|---|
| **Jardin d'Été** | Banlieue ensoleillée | Deux maisons face à face, piscine et plongeoir au centre, toits accessibles. Map d'initiation. |
| **Baie des Éclaboussures** | Plage de sable | Deux pontons sur pilotis, château de sable à trois étages, digue de rochers. Combats à moyenne distance. |
| **Aqua Parc** | Parc aquatique | Deux tours de toboggans, piscine à vagues, passerelles suspendues. La map la plus verticale. |
| **Toits de la Ville** | Ville au crépuscule | Deux étages de jeu : ruelles au sol, réseau de toits et de planches en hauteur. |
| **Temple Englouti** | Ruines dans la jungle | Pyramide à gradins au milieu d'un bassin, galeries à colonnes, cascades. Map de contrôle. |
| **Arène Néon** | Stade futuriste | Arène parfaitement symétrique, anneau central, passerelles de verre. La map compétitive. |

Chaque terrain est **construit par le code au lancement de la manche** (1 385
pièces au total), avec ses propres réglages de lumière, ses points d'apparition
par équipe, ses stations de recharge et sa zone de contrôle.

---

## 6. Régler le jeu

**Tout se règle dans un seul fichier** :
`src/ReplicatedStorage/WaterWars/Config/GameConfig.luau`

Durée des manches, scores à atteindre, vitesse de déplacement, dégâts des bonus,
récompenses en pièces, couleurs de l'interface, touches… aucune valeur n'est
codée en dur ailleurs.

**Ajouter une arme** : ajoutez une entrée dans `Config/Weapons.luau`. Elle hérite
automatiquement des valeurs par défaut de sa catégorie, apparaît dans la
boutique et reçoit son modèle 3D.

**Ajouter un terrain** : créez un module dans `Config/Maps/`, décrivez-le avec
les primitives de `Shared/MapBuilder.luau` (`Block`, `Ramp`, `Building`, `Pool`,
`Bridge`, `Tower`, `Mirror`…), puis ajoutez-le à la liste de `Config/Maps/init.luau`.

---

## 7. Architecture

```
src/
├── ReplicatedStorage/WaterWars/     partagé serveur + client
│   ├── Config/  GameConfig, Weapons (25), Maps (6)
│   └── Shared/  Net, Util, Signal, MapBuilder
├── ServerScriptService/WaterWarsServer/
│   ├── MatchService     manches, vote, scores, récompenses
│   ├── CombatService    projectiles et dégâts (autorité serveur)
│   ├── WeaponService    modèles d'armes, munitions, rechargement
│   ├── PlayerService    apparition, course, régénération, chutes
│   ├── MapService       construction des terrains et ambiance
│   ├── PickupService    bonus au sol
│   ├── DataService      sauvegarde (pièces, armes, statistiques)
│   └── TeamService      équipes et équilibrage
└── StarterPlayer/StarterPlayerScripts/WaterWarsClient/
    ├── WeaponController, EffectsController, SoundController
    └── HudController, ShopController, ScoreboardController, VoteController
```

**Le serveur fait autorité sur tout ce qui compte.** Le client n'envoie qu'une
intention de tir (position de la buse + direction) ; le serveur vérifie la
cadence, le niveau du réservoir et la distance au personnage, puis simule
lui-même chaque goutte d'eau et applique les dégâts. Un client modifié ne peut
donc ni augmenter ses dégâts, ni tirer plus vite, ni tirer sans munitions.

---

## 8. Vérifier le code

Le projet est livré avec sa propre chaîne de validation :

```bash
bash tools/setup_tools.sh   # une fois : télécharge Luau et luau-lsp
bash tools/check.sh
```

Quatre étapes :

1. **luau-compile** — aucune erreur de syntaxe sur les 33 fichiers.
2. **luau-lsp** — typecheck contre l'API Roblox réelle (via `globalTypes.d.luau`),
   avec résolution des `require` entre modules grâce à une sourcemap Rojo.
3. **Passe stricte** — recompile le projet en `--!strict` pour détecter toute
   faute de frappe sur un nom de propriété ou de méthode Roblox.
4. **Cohérence des données** — les 25 armes et les 6 terrains sont réellement
   exécutés sous Luau avec un simulateur d'API Roblox : champs manquants,
   équilibrage aberrant, points d'apparition sous le sol, terrains vides,
   `require` cassés et remotes non déclarés sont refusés.

Pour régénérer les fichiers importables après une modification :

```bash
python3 tools/build_roblox.py
```

Le script relit le XML qu'il vient d'écrire et vérifie que chaque script y est
identique au fichier source.
