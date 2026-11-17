# GoldGuardian : robot de trading sur l'or (XAUUSD) pour MetaTrader 5

> ⚠️ **Avertissement.** Aucun robot ne gagne à 100 %. Les bots qui affichent 90 % de trades gagnants ou plus utilisent presque toujours la martingale ou la grille : ils gagnent souvent, puis une seule mauvaise journée vide le compte. Les prop firms interdisent d'ailleurs ces méthodes. GoldGuardian ne cherche pas à maximiser le pourcentage de trades gagnants. Il cherche à **protéger le capital** et à **gagner plus sur les gains qu'il ne perd sur les pertes**. Teste-le **au moins 1 mois en démo** avant d'y mettre de l'argent réel.

---

## 1. Comment ça marche

| Étape | Ce que fait le robot |
|---|---|
| **Biais (H4)** | Il n'achète que si le prix est au-dessus de l'EMA 200 en H4, et ne vend que s'il est en dessous. |
| **Tendance (H1)** | Il faut EMA 50 > EMA 200 avec le prix au-dessus (l'inverse pour vendre), et un ADX > 20 pour confirmer que la tendance est forte. |
| **Entrée (M15)** | Il attend un repli jusqu'à l'EMA 21 suivi d'une bougie de rejet, avec un RSI qui confirme et un prix pas trop éloigné de sa moyenne. |
| **Stop loss** | Il le place derrière le dernier swing ou à 1,5 × ATR, en prenant le plus large des deux. Si ce stop est trop grand, il ne prend pas le trade. |
| **Gestion** | À +1R, il ferme 50 % de la position et met le reste à break-even. Le reste suit un trailing stop ATR jusqu'au TP à 2,5R. |
| **Actualités** | Il utilise le calendrier économique intégré à MT5 et ne trade pas 45 min avant ni 45 min après une news USD forte (NFP, CPI, FOMC…). |
| **Sessions** | Il ne trade qu'entre 8 h et 20 h (heure serveur), c'est-à-dire pendant les sessions de Londres et de New York. |
| **Spread** | Il refuse de trader si le spread dépasse 0,50 $. |
| **Week-end** | Il ferme tout le vendredi soir. |

La prise partielle à 1R fait monter le taux de trades gagnants **sans** sacrifier le ratio risque/rendement.

### Protections (indispensables en prop firm)
- Le risque est fixé en % du compte (0,5 % par défaut), et le lot est calculé automatiquement.
- **Perte journalière max** : quand elle est atteinte, le robot ferme tout et s'arrête jusqu'au lendemain.
- **Drawdown max** : quand il est atteint, le robot ferme tout et arrête de trader.
- **Pré-contrôle** : le robot refuse un trade si son stop loss pourrait faire dépasser la limite du jour.
- Il prend au maximum 3 trades par jour et s'arrête pour la journée après 2 pertes consécutives.
- Pas de martingale, pas de grille, pas de hedging : c'est conforme aux règles des prop firms.

---

## 2. Installation

L'application **MetaTrader 5 sur iPhone ne peut pas faire tourner de robot** : c'est une limite d'Apple et de MetaQuotes. Le robot doit tourner sur MT5 **ordinateur** (Windows) ou sur un **VPS**. L'iPhone sert ensuite à suivre les trades et à recevoir les notifications.

### Étape A : installer le robot (une seule fois, sur un PC Windows)
1. Installe MetaTrader 5 depuis le site de ton broker ou de ta prop firm.
2. Dans MT5, ouvre **Fichier → Ouvrir le dossier des données → MQL5 → Experts**.
3. Copies-y le fichier **`GoldGuardian.mq5`**.
4. Ouvre-le avec **MetaEditor** (touche F4) puis clique sur **Compiler** (F7).
5. Dans MT5, ouvre un graphique **XAUUSD** (le nom peut être `GOLD` ou `XAUUSD.r` selon le broker).
6. Fais glisser **GoldGuardian** depuis le Navigateur sur le graphique, coche **« Autoriser le trading algorithmique »** et règle les paramètres.
7. Active le bouton **Algo Trading** dans la barre d'outils : il doit être vert.

### Étape B : le faire tourner 24h/24 sans laisser ton PC allumé
Le plus simple est le **VPS intégré de MetaQuotes**, à environ 15 $/mois :
- Dans le Navigateur, fais un clic droit sur ton compte puis **« Enregistrer un serveur virtuel »**.
- Choisis **« Migrer les experts et indicateurs »**.
- Une fois la migration terminée, tu peux éteindre ton PC : le robot continue de tourner.

### Étape C : suivre le robot sur ton iPhone
1. Installe **MetaTrader 5** depuis l'App Store.
2. Connecte-toi au **même compte** (même serveur, même login).
3. Dans l'app, va dans **Paramètres → Messages** et note ton **MetaQuotes ID**.
4. Sur MT5 PC, va dans **Outils → Options → Notifications** : colle le MetaQuotes ID et coche « Activer les notifications push ».
5. Tu recevras ensuite sur l'iPhone une notification à chaque ouverture, prise partielle, fermeture ou arrêt de sécurité.

### Comptes démo, réels et prop firm
Le robot fonctionne sur **n'importe quel compte MT5** : il suffit de se connecter au compte puis d'attacher le robot. Le tableau de bord affiche DÉMO ou RÉEL. Si tu fais tourner plusieurs comptes ou plusieurs robots en même temps, change le **numéro magique** de chacun.

---

## 3. Réglages conseillés

| Paramètre | Démo / test | Compte réel | Prop firm (ex. 5 % / 10 %) |
|---|---|---|---|
| Risque par trade | 0,5 % | 0,5 % | **0,25 – 0,5 %** |
| Perte journalière max | 4 % | 3 % | **règle − 1 %** (ex. 4 %) |
| Drawdown max | 8 % | 10 % | **règle − 2 %** (ex. 8 %) |
| Solde initial | 0 (auto) | 0 (auto) | **taille exacte du challenge** (ex. 100000) |
| Arrêt après X % de gain/jour | 0 | 0 | 1,5 – 2 % (règle de régularité) |
| Fermer avant news | non | non | **oui** si ta prop firm interdit le trading pendant les news |

**Heures de session** : elles suivent l'heure du **serveur** du broker, qui est souvent GMT+2 ou GMT+3. Vérifie l'heure affichée dans la fenêtre « Market Watch ».

**Spread** : chez certains brokers l'or est coté avec 3 décimales. Ajuste « Spread max » si le robot affiche trop souvent « Spread trop large ».

---

## 4. Tester avant d'utiliser
1. Dans MT5, ouvre **Affichage → Testeur de stratégie** (Ctrl+R).
2. Choisis l'expert GoldGuardian, le symbole XAUUSD, la période M15 et le modèle **« Chaque tick basé sur des ticks réels »**.
3. Teste au moins **2 ans** de données.
4. Regarde surtout le **drawdown max**, le **profit factor** (il faut > 1,3) et le **nombre de trades**.

⚠️ Le calendrier des news **ne fonctionne pas dans le testeur** : le filtre de news est désactivé automatiquement pendant un backtest. Les résultats en réel peuvent donc être légèrement différents.

---

## 5. Ce que le robot ne fait pas (encore)
- **Analyser des vidéos YouTube ou des articles de presse** : MT5 ne peut pas le faire seul. Ce serait possible plus tard avec un serveur externe et une IA qui analyse le sentiment, mais c'est un gros projet, payant, et son gain réel n'est pas prouvé. Le filtre de news basé sur le calendrier officiel couvre déjà les événements qui font le plus bouger l'or.
- **Garantir un gain** : personne ne peut le faire.
