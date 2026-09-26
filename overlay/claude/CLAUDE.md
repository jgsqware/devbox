## Skill ADHD (idéation divergente)

Le plugin `adhd` est installé partout. Ne l'utilise **que** pour :

- les demandes d'analyse approfondie (comparer des approches, diagnostiquer
  un problème flou sans cause connue, évaluer des options) ;
- les grosses décisions difficiles à défaire : architecture, schéma de
  données, API ou surface publique, choix d'outil ou de stack, nommage
  d'un produit, stratégie.

Dans ces cas, lance-le de toi-même sans attendre `/adhd`.

Ne l'utilise **pas** pour le reste : modifications de code courantes, bugs
dont la cause est connue, recherches ponctuelles, questions factuelles,
commandes shell, ou dès que la demande dit « vite », « juste », « simple ».
Il coûte environ 10 agents et 30 à 90 s par passage.

Un sous-agent qui tombe sur une grosse décision pendant sa tâche la
remonte à l'agent principal au lieu de trancher seul ; c'est l'agent
principal qui décide de lancer ADHD.

## Style de réponse

Je lis vite et en diagonale : rends chaque réponse facile à scanner.

- **Commence par l'essentiel** : la réponse, le résultat ou la décision
  en une ou deux phrases, avant tout contexte.
- **Découpe en blocs courts** : paragraphes de 2 à 3 phrases maximum,
  titres ou libellés en gras quand il y a plusieurs sujets.
- **Listes à puces** pour les étapes, options, constats ; une idée par
  puce, qui commence par le mot-clé en **gras**.
- **Mets en gras** ce qui compte vraiment (décision, risque, action à
  faire de mon côté), avec parcimonie pour que ça ressorte.
- **Visuel quand ça aide** : tableau pour comparer, bloc de code pour les
  commandes, emojis sobres comme repères (✅ fait, ⚠️ attention, ❌ échec,
  👉 action pour moi) — pas de décoration gratuite.
- **Termine par ce que j'ai à faire**, s'il y a quelque chose, sur une
  ligne à part.

Reste clair et complet : on ne coupe pas d'information utile, on la
rend lisible. Pas de jargon inventé ni d'abréviations obscures.
