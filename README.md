# ClaudeOS

![ClaudeOS : une décision prise en séance, retrouvée le lendemain](.github/media/claudeos.gif)

ClaudeOS est un système de travail pour Claude Code. Il dote l'assistant d'un règlement que vous
choisissez, d'une mémoire qui persiste d'une session à l'autre, d'un état par projet qui permet de
reprendre le travail le lendemain sans relire la conversation, et d'une clôture qui sauvegarde
l'ensemble. Ce dépôt est un modèle : il ne contient aucune configuration personnelle. L'installation
vous pose des questions, et vos réponses déterminent le règlement que l'assistant chargera. Deux
installations aux réponses différentes produisent donc deux systèmes distincts.

L'installation et la mise à jour sont conduites par Claude Code lui-même, sur votre poste, au moyen
d'un agent livré avec le modèle. Elles consomment votre usage de Claude Code, comme toute autre
session.

- [Partie 1 — Installer](#partie-1--installer)
- [Partie 2 — Mettre à jour](#partie-2--mettre-à-jour)

---

## Partie 1 — Installer

### Prérequis

ClaudeOS cible macOS et WSL. Il a été éprouvé sous macOS. Sous WSL, il est pris en charge sans avoir
été éprouvé : l'agent d'installation détecte la plateforme et adapte toute commande qui échoue sur
le poste. Les autres systèmes ne sont pas pris en charge.

Toute installation requiert les outils suivants. La colonne « Contrôle » donne la commande qui
vérifie leur présence.

| Outil | Rôle | Contrôle |
| :--- | :--- | :--- |
| Claude Code 2.1.281 ou ultérieur | exécution de l'agent d'installation | `claude --version` |
| `python3` 3.8 ou ultérieur, avec FTS5 | le moteur, et l'index de recherche | `python3 -c "import sqlite3; sqlite3.connect(':memory:').execute('create virtual table t using fts5(x)')"` |
| `tmux` | une session par projet | `tmux -V` |
| `curl` | téléchargement des compétences optionnelles | `curl --version` |

Si vous conservez votre système sur GitHub (voir ci-dessous), les éléments suivants sont également
requis :

| Outil | Rôle | Contrôle |
| :--- | :--- | :--- |
| un compte GitHub | hébergement de vos dépôts privés | — |
| `git` | historique et sauvegarde | `git --version` |
| `gh`, authentifié | création et contrôle de vos dépôts privés | `gh auth status` |

Aucune installation préalable n'est nécessaire. L'agent effectue ce contrôle au démarrage, avec
`python3 engine/verifier.py prerequis`, et fournit la commande qui installe ce qui manque. La
documentation officielle de chaque outil reste disponible :
[Claude Code](https://code.claude.com/docs/en/setup),
[GitHub CLI](https://github.com/cli/cli#installation),
[git](https://git-scm.com/downloads), [tmux](https://github.com/tmux/tmux/wiki/Installing),
[Python](https://www.python.org/downloads/).

> **Une V1 ou une V2 est déjà installée ?** Ne suivez pas cette partie : reportez-vous à la
> [Partie 2](#depuis-une-v1-ou-une-v2), qui conserve votre version actuelle intacte jusqu'au terme
> de la migration.

### Trois façons de conserver votre système

L'agent vous demande votre choix au cours de l'installation.

- **Un dépôt par domaine**, le choix par défaut : `~/.claude` et chacun de vos domaines de travail
  sont des dépôts GitHub privés. L'ensemble est sauvegardé à chaque clôture, et un second poste est
  possible.
- **Un dépôt unique** : tout est versé dans le dépôt privé de `~/.claude`, domaines compris.
- **Sans git, entièrement local** : rien ne quitte votre poste. Ce régime a pour contreparties un
  poste unique, l'absence d'historique et de retour arrière, et la perte de tout le système avec
  celle du poste. Le passage ultérieur de ce régime à GitHub n'est pas prévu dans cette version.

### Récupérer le modèle

Pour un régime GitHub, cliquez sur « Use this template », créez le dépôt en **privé**, puis
clonez-le :

```
gh repo clone <votre-compte>/<votre-depot> ~/claudeos-amorce
```

Pour le régime sans git, ou pour laisser l'agent créer votre dépôt privé, téléchargez l'archive
d'une version, listée sur la [page des versions](https://github.com/Jos-Vondar/TEMPLATE/tags), et
extrayez-la :

```
mkdir ~/claudeos-amorce
curl -L https://github.com/Jos-Vondar/TEMPLATE/archive/refs/tags/<version>.tar.gz \
  | tar -xz --strip-components=1 -C ~/claudeos-amorce
```

### Lancer l'agent

```
cd ~/claudeos-amorce
claude --settings installateur/settings.installation.json --permission-mode auto --agent claudeos-installateur
```

En mode auto, un classificateur de Claude Code évalue les actions de l'agent, et
`installateur/settings.installation.json` autorise par avance les scripts du moteur qu'il exécute.
Quelques demandes de confirmation peuvent néanmoins apparaître, en particulier pour une écriture
dans `~/.claude`, que Claude Code n'approuve jamais de lui-même. Elles sont à accepter : c'est dans
ce dossier que l'agent installe le système. Si votre organisation a désactivé le mode auto, ou si
votre modèle ne le prend pas en charge, Claude Code démarre en mode Manual : chaque commande demande
alors votre accord.

Au moment de la plomberie, l'agent vous communique une ligne à ajouter à votre `~/.zshrc`, ou à
votre `~/.bashrc` sous WSL : c'est elle qui déclenche le démarrage de ClaudeOS à chaque session. Cet
ajout vous revient.

L'agent commence par présenter cinq notions nécessaires à l'usage du système : la clôture, la
reprise, une session par projet, le contexte et `/compact`, et ce qui quitte votre poste. Chacune se
conclut par une question, et rien n'est installé tant que les cinq n'ont pas été validées. Viennent
ensuite les prérequis, le choix du régime, puis la plomberie : `~/.claude` devient votre système en
place, sans que soit modifié ce que Claude Code y range lui-même. Un `CLAUDE.md` préexistant est
copié à l'écart, et ses règles vous sont proposées. L'agent vous demande confirmation avant toute
écriture qui sort de votre poste, comme une création de dépôt ou un envoi, et avant toute
suppression.

**L'entretien** suit, souvent lors d'une seconde séance. L'agent y pose les questions qui
constituent votre règlement : le degré de contradiction de l'assistant, la nécessité de demander
avant d'agir, la forme de ses réponses, vos domaines de travail. Il rédige votre persona avec vous.
Une rubrique sur laquelle vous n'exprimez pas de préférence est retirée, et non remplie par défaut.
L'installation s'achève par la création d'un premier domaine de travail, une clôture réelle, puis
une reprise réelle.

**Tant que l'installation n'est pas complète, elle se déclare inachevée.** Chaque démarrage de
session l'indique en tête et nomme l'élément manquant : une réponse, une marque « à remplir »
restée dans votre `CLAUDE.md`, ou la première sauvegarde (la première clôture, en régime sans git).
Relancez l'agent pour reprendre là où l'installation s'est arrêtée : depuis l'amorce, ou, si vous
l'avez supprimée, depuis votre système :

```
cd ~/.claude
claude --settings installateur/settings.installation.json --permission-mode auto --agent claudeos-installateur
```

### La sauvegarde a lieu à la clôture

Aucune sauvegarde n'a lieu en fin de session. Elle intervient lorsque vous clôturez la séance dans
la session principale (« on arrête »). Celle-ci demande d'abord aux sessions de projet ouvertes si
elles ont terminé leurs écritures, puis projette l'état de chaque niveau, passe les alarmes du
crochet de commit et, en régime GitHub, envoie chaque dépôt. Une séance terminée sans clôture reste sur votre poste, non
sauvegardée.

### Un poste supplémentaire

En régime GitHub, clonez votre dépôt privé dans `~/claudeos-amorce` sur le nouveau poste, puis
lancez l'agent comme indiqué ci-dessus. Il reconnaît un dépôt qui porte déjà vos réponses et ne vous
repose aucune question. Le régime sans git ne permet qu'un seul poste.

### Une limite connue : Cowork

Dans l'application de bureau, une session Cowork ignore tout import d'un fichier utilisateur situé
hors de son dossier de travail. Le règlement importé par votre `~/.claude/CLAUDE.md` n'y est donc
pas chargé. Claude Code en terminal le charge normalement.

---

## Partie 2 — Mettre à jour

### Ce qu'une version modifie, et ce qu'elle ne modifie jamais

Le modèle possède ce qu'une version modifie : `engine/`, `noyau/`, `gabarits/`, `installateur/`,
`resources/`, `output-styles/`, `.claude/agents/`, les compétences livrées sous `skills/`,
`.gitignore`, ce fichier et la licence. Ces fichiers ne doivent pas être modifiés : la version
suivante les remplace, et une modification locale y devient un conflit. La liste exacte, fichier par
fichier, figure dans `engine/PERIMETRE_TEMPLATE`.

Tout le reste vous appartient, et aucune version n'y touche : votre `CLAUDE.md` (à l'exception du
bloc d'imports situé entre ses deux marqueurs, que le moteur réécrit à partir de vos réponses), vos
réponses et réglages sous `reglages/`, votre mémoire sous `memory/`, votre journal et votre état,
vos dossiers de travail. Vos propres règles se placent dans la section « Mes règles » de votre
`CLAUDE.md`. Les budgets de taille que le crochet de commit fait respecter, pour les descriptions
des compétences, l'index de mémoire et la plus grosse fiche, partent des valeurs du modèle et se
règlent dans `reglages/CLIQUETS`, une ligne `CLE=valeur` par budget (`engine/config.sh` les nomme).

### Depuis une V3

Les versions sont des étiquettes de ce dépôt. Pour passer à une nouvelle version, relancez l'agent :
il identifie votre régime et conduit la mise à jour.

- **En régime GitHub**, depuis votre système :
  `cd ~/.claude && claude --settings installateur/settings.installation.json --permission-mode auto --agent claudeos-installateur`.
  L'agent fusionne la version par git depuis ce dépôt, déclaré comme `upstream` à l'installation, et
  résout avec vous tout conflit portant sur un fichier que vous avez modifié.
- **Sans git**, extrayez l'archive de la nouvelle version dans une amorce neuve, comme décrit dans
  « Récupérer le modèle », et lancez l'agent depuis celle-ci. Si `~/claudeos-amorce` existe encore,
  renommez-la d'abord, par exemple `mv ~/claudeos-amorce ~/claudeos-amorce-ancienne` : extraite
  par-dessus, l'archive y laisserait les fichiers que la version retire. Il compare chaque fichier livré à la
  version précédemment livrée : un fichier que vous n'avez pas modifié est remplacé, un fichier que
  vous avez modifié vous est présenté, et rien n'est écrasé sans votre accord.

### Depuis une V1 ou une V2

Ne lancez pas l'`update.sh` de votre version : la version 3 n'a aucun chemin en commun avec les
précédentes, et ce script refusera de l'installer. Le passage se fait par une installation neuve,
que l'agent conduit en mode migration.

1. Effectuez une dernière sauvegarde de votre version actuelle, puis fermez toutes vos sessions
   Claude Code.
2. Récupérez la version 3 dans `~/claudeos-amorce` et lancez l'agent, comme décrit dans la Partie 1.
3. L'agent reconnaît votre version. Il la place intacte en quarantaine dans
   `~/.claudeos-v2-quarantaine/` et peut la restaurer à l'identique tant que la version 3 n'est pas
   installée. Il installe ensuite la version 3, reprend vos réponses, votre persona, votre routage
   et votre mémoire, et ne vous pose que les questions que votre version ne connaissait pas.
4. Les règles ajoutées à la main, les compétences modifiées et vos domaines vous sont proposés un
   par un. Rien n'est repris sans votre accord.
5. L'ancienne version et son dépôt de sauvegarde ne sont archivés qu'en fin de parcours, après au
   moins une séance complète sur la version 3, et chacun sur votre confirmation. Rien n'est
   supprimé.

---

**Compétences empruntées.** Trois compétences sont proposées en option lors de l'entretien :
`writing-for-agents`, `grilling` et `domain-modeling`. Elles proviennent du dépôt
[mattpocock/skills](https://github.com/mattpocock/skills), sous licence MIT. Ce dépôt ne les
redistribue pas : elles sont téléchargées à l'installation, à un commit fixé dans
`engine/config/SKILLS_AMONT`, avec leur licence, puis complétées par une surcouche propre à
ClaudeOS. Leur choix nécessite donc un accès au réseau.

**Licence.** MIT, voir `LICENSE`. Elle couvre le code de ce dépôt et les surcouches ClaudeOS des
compétences empruntées ; le corps de ces compétences reste sous la licence de son dépôt d'origine.
