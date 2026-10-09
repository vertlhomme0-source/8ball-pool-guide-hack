# Suivi des heures des employés ⏱

Petite application web pour **saisir les heures de chaque employé** et **recevoir
automatiquement un rapport journalier par e-mail** (HTML + fichier CSV pour Excel).

## Fonctionnalités

- **Employés** : ajout (nom, poste, taux horaire), désactivation sans perte d'historique.
- **Saisie des heures** : arrivée, départ, pause, notes ; plusieurs quarts par jour ;
  quarts de nuit (22:00 → 06:00) gérés automatiquement ; validations (pause trop longue,
  quart > 16 h, heures identiques…).
- **Suivi** : total du jour, total de la semaine par employé, alerte heures sup.
  (> 8 h/jour, > 40 h/semaine), employés sans pointage, coût estimé.
- **Historique** : tableau employés × jours sur la période choisie.
- **Rapport journalier par e-mail** :
  - envoyé **automatiquement chaque jour** à l'heure choisie (`REPORT_TIME`) ;
  - si l'application était éteinte à cette heure, il part dès le redémarrage ;
  - jamais envoyé deux fois ; nouvel essai toutes les 15 min en cas d'échec SMTP ;
  - journal des envois visible dans la page *Rapport* (avec bouton « Envoyer maintenant »).

## Installation

```bash
cd heures-employes
python -m venv .venv
source .venv/bin/activate          # Windows : .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env               # puis éditer .env
```

### Configurer l'e-mail (Gmail)

1. Activer la validation en 2 étapes sur votre compte Google.
2. Créer un **mot de passe d'application** : https://myaccount.google.com/apppasswords
3. Dans `.env` :

```ini
REPORT_RECIPIENTS=votre.adresse@gmail.com
REPORT_TIME=18:00
TIMEZONE=America/Toronto
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=votre.adresse@gmail.com
SMTP_PASSWORD=le mot de passe d'application (16 lettres)
```

(Outlook/Hotmail : `smtp-mail.outlook.com`, port 587.)

## Utilisation

```bash
python app.py demo      # (optionnel) ajoute 4 employés et quelques jours d'heures d'exemple
python app.py           # démarre l'application sur http://localhost:5000
```

Tant que `python app.py` tourne, le rapport part tout seul chaque jour à `REPORT_TIME`.

Envoyer un rapport à la main (ex. pour tester la configuration e-mail) :

```bash
python app.py envoyer-rapport              # rapport d'aujourd'hui
python app.py envoyer-rapport 2026-10-08   # une date précise
```

### Alternative : envoi via cron / Planificateur de tâches

Si l'application n'est pas allumée en permanence, mettez `SCHEDULER_ENABLED=false`
et planifiez la commande ci-dessus :

```cron
# Linux/macOS (crontab -e) : tous les jours à 18 h
0 18 * * * cd /chemin/heures-employes && .venv/bin/python app.py envoyer-rapport
```

Sous Windows : *Planificateur de tâches* → action `python app.py envoyer-rapport`.

## Tests

```bash
python -m pytest -q
```

## Structure

| Fichier | Rôle |
|---|---|
| `app.py` | Pages web (Flask) et commandes en ligne |
| `database.py` | Base SQLite : employés, pointages, journal des envois, validations |
| `report.py` | Calcul du rapport (totaux, semaine, heures sup.) et rendu HTML / texte / CSV |
| `mailer.py` | Envoi SMTP avec pièce jointe |
| `scheduler.py` | Envoi automatique quotidien (thread, rattrapage, anti-doublon, réessai) |
| `config.py` | Lecture de la configuration `.env` |

> ⚠️ L'application n'a pas de connexion par mot de passe : utilisez-la sur votre réseau
> local, ou ajoutez une authentification avant de l'exposer sur Internet.
