---
name: carte-complete
description: Recherche infructueuse — un fichier annoncé reste introuvable, ou je ne sais pas où vit un artefact du système. Porte les corollaires de recherche (axes de variation, sorties tronquées, contenants) et le raté de routage.
---

# Carte complète — queue d'inventaire

> Fiche situationnelle. Déclencheur : la table « Mes domaines » du `CLAUDE.md` racine n'a pas suffi à trouver quelque chose.
> Invariant du système : tout ce qui existe est sur une carte. Le `CLAUDE.md` racine porte ce qui sert au quotidien ; cette fiche porte le reste.

## Chercher sans conclure faux

Le règlement garde les règles mères (socle, « Recherche et preuve ») : *une recherche qui ne trouve rien ne prouve rien tant qu'on n'a pas varié le motif et établi le périmètre*. Les cas particuliers vivent ici.

- Axes de variation : nom court contre nom long, casse, synonyme. Et l'axe compte autant que le nombre — **un usage se cherche par la formulation qui l'appelle, pas par le nom de l'outil** : un nom officiel change, la façon dont on demande la chose, non.
- **Dire sur quelle fraction de la sortie on conclut — la troncature a DEUX origines.** **SUBIE** : l'outil coupe sans le dire, la sortie ressemble à une sortie complète — la rouvrir entière, ou découper la recherche pour qu'elle tienne à l'écran. **CHOISIE** : `| head -N`, `| tail -N`, `--max-count`, un `[:300]` en Python — **compter d'abord** (`grep -c`, `wc -l`), et ne conclure une absence que sur un compte. Le second cas est le plus retors : on a posé la borne soi-même quelques secondes plus tôt, on l'oublie, et la sortie qu'on relit a l'air entière. *Payé une fois : une session de projet a listé les sections d'un document par `grep | head -60`, conclu qu'il s'arrêtait deux versions trop tôt, et ouvert un fil de dette sur cette prémisse — le `head` coupait avant les trois sections qui existaient.*
- **Le PÉRIMÈTRE avant la technique, et l'étoile avant le stemmer.** `délég*` trouve ce que `déléguer` manque ; et restreindre le corpus aux descriptions de compétences bat toute technique de recherche, sémantique comprise. **Vide sur plusieurs motifs → escalader** : `python3 ~/.claude/engine/index-fts.py --reconstruit` puis `--requete '<mots>'` ; il applique l'étoile lui-même et dit son périmètre.
- **Une recherche muette sur un fichier jugé binaire est un refus, pas un résultat.**
- **Sur un format structuré, JSON ou YAML, le périmètre est le NŒUD, jamais une distance en
  caractères.** Une fenêtre autour d'un motif rend vide quand la cible vit dans un nœud frère, et
  ce vide se lit comme une absence. Parcourir l'arbre, ou nommer le nœud. *(Payé une fois : une
  propriété cherchée dans les 20 000 caractères suivant le nom de son élément a rendu vide ; elle
  vivait dans un nœud frère.)*
- **Un contenant se vérifie ouvert, pas listé de l'extérieur.**
- **Un périmé se cherche sur le CONTENU, jamais sur les renvois de la correction.** Quand un document corrige une partie de lui-même, contrôler « les sections que la correction nomme » ne trouve que ce qu'elle savait déjà : une section périmée qu'elle ne cite pas reste invisible, et elle continue d'affirmer au présent une solution morte. Le motif fiable est *toute section qui affirme au présent ce qui vient d'être abandonné* — il se joue sur le texte, pas sur la table des renvois. *(Payé une fois : trois sections nommées par une correction contrôlées, le fichier déclaré propre ; une quatrième, non citée, annonçait toujours l'architecture abandonnée.)*
- **L'appartenance d'un fichier à l'index d'un dépôt ne date rien.** Là où une sauvegarde automatique commite en cours de séance, l'index ne distingue pas « créé avant » de « commité avant mon commit ». Pour dater une création, lire l'historique du fichier — `git log --diff-filter=A -- <chemin>` — jamais sa présence.

## Une option se vérifie avant qu'on s'y fie

**Vérifier qu'une option existe avant de s'y fier, un mode de simulation surtout — essai à blanc, aperçu.** Un drapeau inconnu peut être ignoré en silence, et l'action se produire pour de bon. Le geste : lire l'aide ou le code du script visé, jamais supposer la parité avec un outil voisin.

## Raté de recherche = trou de routage

**Si je ne trouve pas ce qui existe, ou si l'utilisateur m'apprend que c'était là**, le geste n'est pas de s'excuser : retracer où j'ai cherché, nommer ce qui manquait dans la carte, le corriger. **Si `MULTIDOMAINE=oui`** — le règlement le porte alors (« Plusieurs domaines ») —, consigner aussi une ligne dans `<MÉMOIRE>/ROUTING_MISSES.md` : date · cherché · où j'ai cherché · où c'était · correctif. L'audit lit et purge ce registre. **Jamais s'excuser à la place.**

## Pourquoi cette compétence existe

Le règlement ne porte aucune table d'artefacts : *où va* un fait, une règle ou une décision d'architecture est dit par la règle de tri (socle, « Mémoire et vérité »), et une table de chemins n'apprend rien qu'un `ls` ne dise — elle se périme. Le reste de la carte est ici.

Au doute sur le nom d'un dossier de l'outil sous `~/.claude/projects/`, le lister plutôt que de composer le chemin. L'interdit d'écrire un chemin propre à un poste est gardé mécaniquement par la plomberie : elle refuse `/home/<nom>/` et `/Users/<Nom>` dans le règlement, le design et les compétences.

## Dépôt et arbre vivant

**Le régime git décide de l'arbre** — `GIT`, dans `~/.claude/reglages/REPONSES` :

| Régime | Dépôts | Où vit le travail |
|---|---|---|
| `par-domaine` | `~/.claude`, plus un dépôt privé par domaine | `~/<NOM>/` |
| `unique` | `~/.claude` seul | `~/.claude/travail/<NOM>/` |
| `aucun` | aucun — rien ne sort du poste | `~/.claude/travail/<NOM>/` |

**Les listes se LISENT, elles ne se recopient pas** — `source ~/.claude/engine/config.sh` puis
`claudeos_repos` pour les dépôts, `claudeos_ws_roots` pour les dossiers de travail.

**En régime GitHub, la sauvegarde est en liste noire** : tout part sauf exclusion, donc l'oubli coûte une **fuite**, plus une perte. Ce qui ne doit pas voyager se déclare dans le `.gitignore` du dépôt concerné ; les alarmes du crochet sont un mécanisme distinct, et lever l'une ne lève pas l'autre (`controles-et-alarmes`).

**L'état du niveau système vit dans `ETAT.md`, projection de `journal/*.jsonl`.** Tous les niveaux sont au même régime — leur liste se lit par `niveaux_tous()` d'`engine/etat.py`, elle ne s'écrit pas ici.

**Le dossier personnel de la session n'est pas toujours celui de la machine** — un conteneur, une machine virtuelle, un second compte. Le geste qui vaut partout : **lister les montages réels avant de conclure à une absence**, jamais présumer lequel existe.

## Fichiers du dossier racine de configuration

`~/.claude/` mélange ce que livre le template, ce qu'écrit l'utilisateur et ce que l'outil gère seul.

**La règle qui tranche pour ce que les listes ci-dessous ne nomment pas encore** : ce que nous écrivons voyage, ce que l'outil écrit lui-même reste sur sa machine. Mnémo — *« si c'est Claude Code qui l'écrit, pas moi, ça ne voyage pas. »*

**Livré par le template, remplacé à chaque version — ne pas l'éditer** : `engine/` (le moteur ; `engine/config/` porte ses références), `noyau/regles/` (les fragments du règlement), `gabarits/`, `installateur/`, les compétences livrées de `skills/`, `resources/`, `output-styles/`, `README.md`, `LICENSE`, `.gitignore`.

**À l'utilisateur, jamais touché par une version** : `CLAUDE.md` (persona, « Mes domaines », « Mes règles » — seul le bloc d'imports est écrit par `engine/appliquer-reponses.py`), `reglages/` (réponses et réglages du poste), `memory/`, `journal/` et `ETAT.md`, `travail/` (en `GIT=unique` ou `GIT=aucun`), `docs/` (plans et specs du système), `audits/`, `secrets-shared/`, et `settings.json`, écrit par l'outil, où le fragment de ClaudeOS est fusionné.

**Généré** : les compétences optionnelles de `skills/`, composées par `engine/skills-amont.sh` et marquées par leur `LICENSE.amont` ; sans git, `.claudeos/` (l'état livré, les empreintes de la dernière clôture). `RTK.md` est posé par l'outil `rtk` et importé par le bloc quand `PROXY=oui` — ce qu'il faut en savoir vit dans la compétence `rtk-depannage`.

**Les définitions de sous-agents** vivent dans le `.claude/agents/` du domaine ou du projet qui les emploie, jamais à la racine du système. La source commune d'un domaine, `~/.claude/domaines/<D>/agents/`, **n'est pas** un `.claude/agents/` : l'outil ne la charge pas, ce sont les copies de dépôt qui sont chargées, et le crochet (code 26) garde leur concordance. **Les découvrir, ne pas les recopier ici** : `source ~/.claude/engine/config.sh; claudeos_ws_roots | while IFS= read -r d; do find "$d/" -maxdepth 3 -type d -path '*/.claude/agents'; done` — **la barre oblique finale est la commande, pas de la ponctuation** : sans elle une racine qui est un lien n'est pas déréférencée, et la sortie est VIDE, rc=0.

Réglages, trois fichiers et trois régimes — celui du milieu et celui du bas ne voyagent pas, et il faut savoir lequel se refait à la main :

- `settings.json` (déclencheurs, permissions, variables) — **sauvegardé** en régime GitHub, voyage entre les postes.
- `settings.local.json` (surcharges propres au poste) — **exclu**, et c'est voulu : son contenu n'a de sens que sur sa machine.
- `policy-limits.json` (restrictions imposées par la politique du compte, marquages de conformité, avis de surveillance, valeurs par défaut) — **exclu**, et **rien à refaire à la main** : l'outil le réécrit depuis la politique du compte. Sur un poste neuf il apparaît seul. Ne pas l'éditer, ne pas s'étonner de son absence au dépôt, et ne jamais y voir une source de vérité authorée. C'est en revanche là que se lit ce que le compte interdit.

Géré par l'outil, ne pas y toucher ni s'y fier comme source : `projects/` (transcriptions, un dossier par répertoire de travail), `plugins/`, `cache/`, `sessions/`, `shell-snapshots/`, `file-history/`, `paste-cache/`, `session-env/`, `tasks/`, `jobs/`, `daemon/`, `downloads/`, `backups/`, `plans/`, `ide/` (jeton de liaison avec l'éditeur, réécrit à chaque session), `history.jsonl`, `.credentials.json`. Le fichier `~/.claude.json`, hors de ce dossier, relève du même régime : compteurs d'usage, identifiants de machine, caches d'expérimentation.

**Porte de sortie — quand on a besoin de ces données quand même.** Compteurs d'usage, transcriptions de session, historique de commandes : les lire est permis, mais aucun de ces emplacements n'est sauvegardé, donc toute conclusion qu'on en tire est **propre à la machine courante** et doit se nommer comme telle avant d'être énoncée. Un compteur à zéro ici ne dit rien d'un autre poste. Ne jamais en tirer un verdict d'abandon, de désuétude ou de non-usage sans avoir dit quelle machine on a mesurée. *(Payé deux fois : un rapport d'agent a cru disparues trois pièces présentes sur l'autre poste ; un diagnostic d'installation a conclu à l'abandon d'une extension qui servait ailleurs.)*

## Compétences qui ne se déclenchent jamais seules

**Aucune parmi les compétences livrées.** Une compétence de l'utilisateur qui porte `disable-model-invocation: true` n'est visible d'aucun document chargé : la nommer dans le `CLAUDE.md` du niveau qui l'emploie, sinon son existence ne tient qu'à la mémoire de l'utilisateur.

## Machinerie

`~/.claude/engine/` porte les scripts : bilan de démarrage, clôture, contrôles hebdomadaires, contrôle des secrets, journal d'état et sa projection, index de recherche, registre des livrables, installation d'un poste, ouverture de session, bloc d'imports du règlement (`appliquer-reponses.py`), composition des compétences optionnelles (`skills-amont.sh`). Le crochet d'alarmes est sous `engine/hooks/`. Les réglages du poste sont dans `~/.claude/reglages/`, jamais dans `engine/`, qui appartient au template.

`~/.claude/resources/` porte le gabarit de création de domaine.

## Artefacts de mémoire à faible fréquence

**`<MÉMOIRE>` = `~/.claude/memory/`**, l'emplacement que `autoMemoryDirectory` donne à l'outil. Écrire par ce chemin ; un dossier `~/.claude/projects/<slug>/` porte un nom propre au poste — **ne jamais l'écrire en dur ; au moindre doute, lister `~/.claude/projects/`.**

- `<MÉMOIRE>/PORTFOLIO.md` — ce qu'on a produit, fil du temps par projet. Généré, ne pas éditer ; régénéré **à la demande** par `engine/build-portfolio.sh`. Y aller sur « qu'a-t-on livré », « où en est ce projet depuis le début ».
- `<MÉMOIRE>/IDEES_FROIDES.md` — idées lancées en passant, hors des chantiers engagés. Y aller quand l'utilisateur lance une idée hors sujet, ou demande une revue d'idées.
- `~/.claude/audits/` — rapports de la passe mensuelle : audit lancé, **lire le précédent d'abord**.

### Le reste de la carte

La table « Mes domaines » reste au `CLAUDE.md` racine et ne descend pas ici : une compétence de routage ne peut se convoquer que si l'on sait déjà qu'on est dans un domaine, ce qui est précisément ce que cette table apprend.

- **Le document de conception du niveau** — son nom est fixé par `~/.claude/resources/DOMAINE_TEMPLATE.md`. Y aller sur tout travail de fond portant sur cet objet. La règle de tri du socle dit déjà qu'une décision d'architecture stable va là ; ceci n'en donne que le lieu.
- `python3 ~/.claude/engine/etat.py fils --tous` — ce qui reste à faire, par ancienneté, calculé depuis les journaux. Y aller pour proposer le travail du jour ou arbitrer des priorités.
- **Les fichiers GELÉS** — ceux qu'une migration depuis une V1 ou une V2 a gelés, en-tête de gel en première ligne. Ils sont en lecture seule et **rien ne les régénère** : le crochet refuse toute écriture. Ils portent l'histoire d'avant la migration et **se cherchent au `grep`**, jamais en s'y fiant pour l'état courant. Ce qu'ils portaient de vivant a déménagé : la carte de rappel est `## Où trouver` d'`ETAT.md`, le récit d'une séance est un événement `seance`, une règle candidate est un `du` du chantier `regles-candidates`.
- `<MÉMOIRE>/REMINDERS.md` et `<MÉMOIRE>/SECURITY_DEBT.md` — rappels datés et dette de sécurité. Relayés au démarrage, purgés au traitement. Jamais de valeur de secret dans le second : identité, emplacement, statut.
- **Plans et specs** — `~/.claude/docs/{plans,specs}/` pour le système · le `docs/` du domaine pour un plan qui lui est propre · `<projet ou app>/docs/{plans,specs}/` sinon (compétence `fichiers-et-nommage`). Y aller à l'exécution d'un plan écrit.

## Une mémoire de session par répertoire de travail

Le dossier `~/.claude/projects/` contient un sous-dossier par répertoire depuis lequel une session a été ouverte, nommé d'après ce chemin ; il porte ses transcriptions. Conséquence : déplacer un projet orpheline son historique de session. Un tel dossier orphelin n'est pas supprimé sans accord de l'utilisateur.
