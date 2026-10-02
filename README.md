# ClaudeOS

![ClaudeOS : une décision prise en séance, retrouvée le lendemain](.github/media/claudeos.gif)

ClaudeOS est un système de travail pour Claude Code. Il donne à ton assistant un règlement que tu
choisis, une mémoire qui survit d'une session à l'autre, un état par projet qui se reprend le
lendemain sans relire la conversation, et une clôture qui sauvegarde le tout. Ce dépôt est un
modèle : il ne contient la configuration de personne. L'installation te pose des questions, et ce
que tu réponds décide du règlement que ton assistant chargera. Deux installations aux réponses
différentes ne se ressemblent pas.

L'installation et la mise à jour sont menées par Claude Code lui-même, sur ton poste, par un agent
livré avec le modèle. Elles consomment donc ton usage de Claude Code, comme n'importe quelle session.

- [Partie 1 — Installer](#partie-1--installer)
- [Partie 2 — Mettre à jour](#partie-2--mettre-à-jour)

---

## Partie 1 — Installer

### Ce qu'il te faut

ClaudeOS vise macOS et WSL. Il est éprouvé sous macOS. Sous WSL, il est supporté mais non éprouvé :
l'agent d'installation lit la plateforme et adapte une commande qui échoue sur ton poste. Les autres
systèmes ne sont pas supportés.

Toutes les installations demandent les outils suivants. La commande de droite dit si ton poste les a.

| Outil | Pourquoi | Contrôle |
| :--- | :--- | :--- |
| Claude Code 2.1.281 ou plus récent | l'agent d'installation en a besoin | `claude --version` |
| `python3` 3.8 ou plus récent, avec FTS5 | le moteur, et l'index de recherche | `python3 -c "import sqlite3; sqlite3.connect(':memory:').execute('create virtual table t using fts5(x)')"` |
| `tmux` | une session par projet | `tmux -V` |
| `curl` | télécharger les compétences optionnelles | `curl --version` |

Si tu gardes ton système sur GitHub (voir ci-dessous), il te faut aussi :

| Outil | Pourquoi | Contrôle |
| :--- | :--- | :--- |
| un compte GitHub | tes dépôts privés | — |
| `git` | l'historique et la sauvegarde | `git --version` |
| `gh`, authentifié | créer et contrôler tes dépôts privés | `gh auth status` |

Tu n'as rien à installer d'avance. L'agent fait ce contrôle au début, avec
`python3 engine/verifier.py prerequis`, et te donne la commande qui installe ce qui manque. Tu peux
aussi suivre la documentation officielle de chaque outil :
[Claude Code](https://code.claude.com/docs/en/setup),
[GitHub CLI](https://github.com/cli/cli#installation),
[git](https://git-scm.com/downloads), [tmux](https://github.com/tmux/tmux/wiki/Installing),
[Python](https://www.python.org/downloads/).

> **Tu as déjà une V1 ou une V2 ?** Ne suis pas cette partie : va à la
> [Partie 2](#depuis-une-v1-ou-une-v2), qui garde ta version actuelle intacte jusqu'au bout.

### Trois façons de garder ton système

L'agent te demande laquelle tu veux, pendant l'installation.

- **Un dépôt par domaine**, le choix par défaut : `~/.claude` et chacun de tes domaines de travail
  sont des dépôts GitHub privés. Tout est sauvegardé à chaque clôture, et un second poste est
  possible.
- **Un dépôt unique** : tout va dans le dépôt privé de `~/.claude`, tes domaines compris.
- **Sans git, tout local** : rien ne sort de ton poste. Le prix est un seul poste, aucun historique
  ni retour arrière, et la perte du poste perd tout. Passer ensuite de ce régime à GitHub n'est pas
  prévu dans cette version.

### Récupérer le modèle

Pour un régime GitHub, clique sur « Use this template », crée le dépôt en **privé**, puis clone-le :

```
gh repo clone <ton-compte>/<ton-depot> ~/claudeos-amorce
```

Pour le régime sans git, ou si tu préfères laisser l'agent créer ton dépôt privé, prends l'archive
d'une version, listée sur la [page des versions](https://github.com/Jos-Vondar/TEMPLATE/tags), et
extrais-la :

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

En mode auto, un classificateur de Claude Code juge à ta place les gestes de l'agent, et
`installateur/settings.installation.json` autorise d'avance les scripts du moteur qu'il enchaîne. Il
peut encore t'interrompre une ou deux fois, surtout pour une écriture dans `~/.claude`, que Claude Code
n'approuve jamais de lui-même : accepte-la, c'est là que l'agent installe le système.

À la plomberie, l'agent te donne une ligne à ajouter à ton `~/.zshrc`, ou à ton `~/.bashrc` sous
WSL : c'est elle qui lance le démarrage de ClaudeOS à chaque session. C'est toi qui l'ajoutes.

L'agent commence par cinq points à connaître pour se servir du système : la clôture, la reprise,
une session par projet, le contexte et `/compact`, ce qui sort de ton poste. Chacun se termine par
une question, et rien ne s'installe tant que les cinq ne sont pas passés. Ensuite viennent les
prérequis, le choix du régime, puis la plomberie : `~/.claude` devient ton système en place, sans
que soit touché ce que Claude Code y range lui-même. Un `CLAUDE.md` qui existait avant est copié à
l'écart, et ses règles te seront proposées. L'agent confirme avec toi chaque écriture qui sort de ton
poste, comme une création de dépôt ou un envoi, et chaque suppression.

**L'entretien** vient ensuite, souvent dans une seconde séance. L'agent y pose les questions qui
font ton règlement : jusqu'où ton assistant te contredit, s'il demande avant d'agir, la forme de ses
réponses, tes domaines de travail. Il écrit ton persona avec toi. Une rubrique sur laquelle tu n'as
pas d'avis est retirée, et non remplie par défaut. L'installation se termine par un premier domaine
de travail, une vraie clôture, puis une vraie reprise.

**Tant que tout n'est pas réglé, l'installation se déclare inachevée.** Chaque démarrage de session
le dit en tête, et nomme ce qui manque : une réponse, une marque « à remplir » restée dans ton
`CLAUDE.md`, ou la première sauvegarde (la première clôture, en régime sans git). Relance l'agent
pour reprendre là où tu t'étais arrêté.

### La sauvegarde se fait à la clôture

Rien n'est sauvegardé en fin de session. La sauvegarde a lieu quand tu clos ta séance dans la
session principale (« on arrête »). Celle-ci demande d'abord aux sessions de projet ouvertes si
elles ont fini d'écrire, puis projette l'état de chaque niveau, passe ses contrôles et, en régime
GitHub, envoie chaque dépôt. Une séance close sans clôture reste sur ton poste, non sauvegardée.

### Une machine de plus

En régime GitHub, clone ton dépôt privé dans `~/claudeos-amorce` sur la nouvelle machine, puis lance
l'agent comme ci-dessus. Il reconnaît un dépôt qui porte déjà tes réponses et ne te repose aucune
question. Le régime sans git ne permet qu'un poste.

### Une limite connue : Cowork

Dans l'application de bureau, une session Cowork saute tout import d'un fichier utilisateur qui
sort de son dossier de travail. Le règlement que ton `~/.claude/CLAUDE.md` importe n'y est donc pas
chargé. Claude Code en terminal le charge.

---

## Partie 2 — Mettre à jour

### Ce qu'une version touche, et ce qu'elle ne touche jamais

Le modèle possède ce qu'une version change : `engine/`, `noyau/`, `gabarits/`, `installateur/`, les
compétences livrées sous `skills/`, ce fichier et la licence. Ne les modifie pas : la version
suivante les remplace, et une modification locale y devient un conflit. La liste exacte, fichier par
fichier, est dans `engine/PERIMETRE_TEMPLATE`.

Tout le reste est à toi, et aucune version n'y touche : ton `CLAUDE.md` (sauf le bloc d'imports
entre ses deux marqueurs, que le moteur réécrit depuis tes réponses), tes réponses et réglages sous
`reglages/`, ta mémoire sous `memory/`, ton journal et ton état, tes dossiers de travail. Tes
propres règles vont dans la section « Mes règles » de ton `CLAUDE.md`.

### Depuis une V3

Les versions sont des étiquettes de ce dépôt. Pour passer à une version neuve, relance l'agent : il
lit ton régime et mène la mise à jour.

- **En régime GitHub**, depuis ton système : `cd ~/.claude && claude --permission-mode auto --agent claudeos-installateur`.
  L'agent fusionne la version par git depuis ce dépôt, posé comme `upstream` à l'installation, et
  résout avec toi un conflit sur un fichier que tu as modifié.
- **Sans git**, extrais l'archive de la nouvelle version dans une amorce neuve, comme dans
  « Récupérer le modèle », et lance l'agent depuis elle. Il compare chaque fichier livré à ce qui
  avait été livré : un fichier que tu n'as pas touché est remplacé, un fichier que tu as modifié
  t'est montré, et rien n'est écrasé sans ta réponse.

### Depuis une V1 ou une V2

Ne lance pas l'`update.sh` de ta version : la version 3 n'a aucun chemin en commun avec les
précédentes, et ce script refusera de la poser. Le passage se fait par une installation neuve, que
l'agent mène en mode migration.

1. Fais une dernière sauvegarde de ta version actuelle, puis ferme toutes tes sessions Claude Code.
2. Récupère la version 3 dans `~/claudeos-amorce` et lance l'agent, comme dans la Partie 1.
3. L'agent reconnaît ta version. Il la met en quarantaine intacte dans `~/.claudeos-v2-quarantaine/`
   et peut l'y restaurer à l'octet tant que la version 3 n'est pas posée. Puis il installe la
   version 3, reprend tes réponses, ton persona, ton routage et ta mémoire, et ne te pose que les
   questions que ta version ne connaissait pas.
4. Tes règles ajoutées à la main, tes compétences modifiées et tes domaines te sont proposés un par
   un. Rien n'est repris sans ton accord.
5. Ton ancienne version et son dépôt de sauvegarde ne sont rangés en archive qu'à la fin, après au
   moins une séance complète sur la version 3, et chacun sur ta confirmation. Rien n'est supprimé.

---

**Compétences empruntées.** Trois compétences sont proposées en option à l'entretien :
`writing-for-agents`, `grilling` et `domain-modeling`. Elles viennent du dépôt
[mattpocock/skills](https://github.com/mattpocock/skills), sous licence MIT. Ce dépôt ne les
redistribue pas : elles sont téléchargées à l'installation, à un commit fixé dans
`engine/config/SKILLS_AMONT`, avec leur licence, puis complétées par une surcouche propre à
ClaudeOS. Les choisir demande donc un accès au réseau.

**Licence.** MIT, voir `LICENSE`. Elle couvre le code de ce dépôt et les surcouches ClaudeOS des
compétences empruntées ; le corps de ces compétences reste sous la licence de son dépôt d'origine.
