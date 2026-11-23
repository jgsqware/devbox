---
name: rex-tidy
description: Faire le ménage dans les sessions Rex de TOUS les hôtes (local, iba, wk, gaming1, dev…) — fermer les sessions au nom générique (adjectif-nom auto, ex. `cosmic-lagoon`) où rien ne tourne, et renommer d'après leur contenu celles où un programme tourne. Utilise sur `/rex-tidy`, « nettoie mes sessions rex », « ferme les sessions vides », « renomme mes sessions rex ».
---

# rex-tidy — ménage des sessions Rex

## 1. Inventaire (lecture seule)

```bash
bash ~/.claude/skills/rex-tidy/inventory.sh            # local + hôtes de l'app Rex
bash ~/.claude/skills/rex-tidy/inventory.sh dev iba    # hôtes choisis
```

TSV : `host  session_id  label  blocks  busy  detail`. `busy=1` = un bloc a autre
chose qu'un shell au premier plan (`claude`, `flw`, `vim`…). Un hôte `INJOIGNABLE`
est signalé et sauté, jamais retenté en boucle.

## 2. Décider, session par session

| Label | busy | Action |
|---|---|---|
| **générique** | 0 (shell inactif, 0 bloc, ou blocs fantômes) | 🗑️ `rex [-S host] kill <session_id>` |
| **générique** | 1 | ✏️ `rex [-S host] session rename <session_id> <nom>` |
| **descriptif** | peu importe | ➖ ne pas toucher |

- **Générique** = étiquette auto de Rex, `adjectif-nom` aléatoire (`amber-harbour`,
  `quiet-delta`, `drifting-meadow`), ou `claude` / `session` / `shell`. Un nom de
  projet ou de dossier (`devbox`, `gitlab`, `pt-ci-ansible`) est **descriptif**.
- **Nouveau nom** : 2 à 4 mots minuscules reliés par des tirets, tirés du titre des
  blocs Claude et du dossier (`~/Work/jgsqware/mind` + Claude → `mind-…`). Plusieurs
  tâches différentes dans la même session → combiner (`forticlient-okr`).
- **Ta propre session** (`$REX_SESSION`) : ne jamais la fermer ; la renommer si son
  label ne décrit plus le travail en cours.

## 3. Garde-fous

- **Revérifier juste avant chaque `kill`** (`rex block call -b <id> process`) : le
  premier plan a pu changer depuis l'inventaire.
- Un bloc listé par `block ls` mais « not found » au `block call` est **fantôme**
  → compte comme vide.
- Ne jamais redémarrer ni arrêter un serveur Rex (`rex server stop`) : sur dev,
  un serveur lancé à la main remplace le `rex.service` systemd qui ouvre `:7297`,
  et l'hôte disparaît du tailnet.
- Utiliser les `session_id` complets, jamais les labels, dans `kill` / `rename`.

## 4. Report (français, visuel)

Verdict en tête (`N fermées · M renommées`), puis un tableau par action :
🗑️ fermées (hôte, session, contenu), ✏️ renommées (hôte, avant → après, ce qui
tourne), et la liste des sessions restantes par hôte.
