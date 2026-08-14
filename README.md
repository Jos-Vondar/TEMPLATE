# Un système d'exploitation pour Claude Code

Ce dépôt est un **squelette**. Il installe une configuration Claude Code qui se souvient, se sauvegarde, se vérifie et se corrige — puis il t'interroge pour la rendre tienne.

Ce n'est pas la configuration de quelqu'un d'autre livrée telle quelle. Le contenu personnel en a été retiré : pas de nom de client, pas de projet, pas de métier, pas de persona. Ce qui reste, c'est la mécanique, et les règles qui ont une raison d'exister chez plus d'une personne.

## Ce que ça fait

- **Sauvegarde** ta configuration et ton travail dans un dépôt git privé, à chaque fin de session, sans que tu y penses.
- **Synchronise** tes machines par ce même dépôt.
- **Refuse** de laisser partir ce qui ne doit pas partir : documents confidentiels, secrets, fichiers de données. Liste blanche, pas liste noire — tout est refusé par défaut, on autorise nommément.
- **Se vérifie** avant chaque sauvegarde : 39 contrôles mécaniques, qui bloquent quand un défaut se désactiverait en silence et se contentent d'avertir quand il ne fait qu'encombrer.
- **Se souvient** : mémoire par niveau, carte de rappel, journal de séances, fils ouverts, rappels datés — et un bilan de l'état du système injecté à l'ouverture de chaque session.
- **Apprend** : une passe hebdomadaire relit ce qui s'est passé et propose des règles. Proposition, validation, écriture — jamais d'auto-règle.

## Installer

**Prérequis** : `git`, `rsync`, `curl`, `python3`, Claude Code, une identité git configurée, et **un dépôt git privé vide** qui servira de sauvegarde. Facultatif mais recommandé : `tmux`, pour les sessions de projet — section plus bas, rien d'autre n'en dépend.

```bash
git clone <ce-dépôt> claudeos-squelette
cd claudeos-squelette
bash install.sh
```

Le script demande l'URL de ton dépôt de sauvegarde, vérifie qu'il est clonable **et inscriptible** avant d'écrire quoi que ce soit, pose la machinerie, câble les déclencheurs de Claude Code, calibre ses alarmes sur ton corpus réel, et lance son autotest. Il s'arrête à la première étape qui échoue : un demi-système installé est pire qu'aucun, il a l'air de marcher.

**Il installe aussi un outil tiers : `rtk`** ([github.com/rtk-ai/rtk](https://github.com/rtk-ai/rtk)), un proxy qui compresse la sortie des commandes courantes pour réduire le coût en jetons des sessions. Il vient de son dépôt à lui, par son script d'installation officiel (`curl | sh`), et il pose un déclencheur qui réécrit les commandes Bash prises en charge (`git status` devient `rtk git status`) avant exécution. Si l'installation échoue, tout le reste marche sans lui, à un coût plus élevé ; si tu n'en veux pas, retire de `~/.claude/settings.json` le hook dont la commande est `rtk hook claude`, et supprime le binaire. Il écrit aussi `~/.claude/RTK.md`, son propre fichier d'instruction, dans ton dossier de configuration — compté dans la couche chargée à chaque session, et réécrit à chaque mise à jour de l'outil. Si tu retires l'outil, retire ce fichier avec lui.

Puis, dans Claude Code :

```
/plugin marketplace add anthropics/claude-plugins-official
/plugin install superpowers@claude-plugins-official
/claudeos-onboarding
```

L'entretien te demande qui tu es, sur quoi tu travailles et quel assistant tu veux. **C'est la moitié qui compte** : un script ne peut pas savoir qui il a en face. Il assemble ensuite ton fichier de règles en ne gardant que celles dont la condition est vraie chez toi, et finit par une première sauvegarde complète.

### Une machine de plus

Sur la nouvelle machine, le même `install.sh`, avec **la même URL de dépôt**. Il reconnaît un dépôt déjà habité et bascule seul : il récupère ta configuration au lieu d'en créer une. Il ne repose aucune question — les réponses sont dans le dépôt, et en produire une deuxième série créerait deux réponses à deux âges.

### Passer à une nouvelle version

Sans réinstaller, et sans perdre ce que tu as adapté :

```bash
bash ~/.claudeos/engine/update.sh --dry-run   # dit ce qu'il ferait, n'écrit rien
bash ~/.claudeos/engine/update.sh             # applique
```

L'installation a enregistré une empreinte de chaque fichier qu'elle a posé. La mise à jour compare trois choses par fichier — cette empreinte, ton fichier d'aujourd'hui, celui de la nouvelle version — et c'est ce troisième point de comparaison qui rend l'opération sûre :

- **tu n'y as jamais touché** → le fichier est remplacé, sans rien te demander ;
- **tu l'as modifié** → tu vois le diff, tu décides, et **sans réponse ta version est conservée**.

Ton fichier de règles, ta mémoire et tes dossiers de travail ne sont jamais touchés. Une mise à jour porte sur le moteur, les compétences et les styles de sortie — ce qui vient de ce dépôt, pas ce que tu as écrit.

Un fichier que tu as choisi de garder reste marqué comme tien : on te le redemandera à la prochaine version au lieu de l'écraser en te croyant d'accord.

Un fichier que la nouvelle version ne livre plus n'est **jamais supprimé sans ton accord** : la mise à jour te le montre, te propose la suppression, et sans réponse le conserve — en le consignant dans `~/.claudeos/engine/config/RETIRES_AMONT`, pour que tu saches ce que tu gardes et que plus rien ne route.

**Si tu viens de la v1.1.0** : le premier passage réel s'interrompt sur une erreur de syntaxe après avoir copié les fichiers — c'est l'ancien `update.sh` qui se fait remplacer pendant qu'il tourne, un défaut de la v1.1.0 que la v2 corrige mais ne peut pas corriger rétroactivement. **Relance simplement la même commande** : le second passage, exécuté par le `update.sh` neuf, termine tout proprement — bilan, fichiers retirés, empreintes. L'essai à blanc ne montre pas cette interruption, puisqu'il n'écrit rien.

`--ref v1.2.3` vise une version précise. Sans elle, c'est la dernière publiée — pas la pointe de la branche, qui peut porter du travail en cours.

## Ce qu'il y a dedans

| | |
| :--- | :--- |
| `install.sh` | L'amorçage. Déterministe, idempotent, s'arrête bruyamment. |
| `engine/` | La machinerie : sauvegarde, synchronisation, autotest, bilan de démarrage, générateurs de mémoire. |
| `system/CLAUDE.md` | Le règlement, livré en gabarit. L'entretien en retire les règles sans objet. |
| `system/RULES_CATALOG.md` | Pour chaque règle : son énoncé, **le motif qui l'a fait naître**, et la condition sous laquelle elle mérite d'exister. |
| `system/DESIGN.md` | Comment le système marche et pourquoi il marche ainsi. |
| `system/skills/` | Les règles situationnelles en compétences — chargées sur déclencheur, pas à chaque session —, l'entretien d'installation, l'audit périodique, et une compétence d'interrogatoire empruntée. |
| `system/output-styles/` | Un style de sortie en option, posé mais jamais activé d'office. |
| `system-memory/` | Les registres de la mémoire, livrés vides avec leur mode d'emploi en tête : règles candidates, origines des règles, ratés de recherche, idées froides. |
| `resources/` | Le gabarit de création d'un domaine de travail, cité par les règles. |

## Trois choses à savoir avant de t'en servir

**Tu hérites de règles que tu n'as pas méritées.** Chacune est née d'un incident précis, arrivé à quelqu'un d'autre. Une règle abstraite se respecte moins bien qu'un cas vécu : celles-ci tiendront mécaniquement moins bien chez toi. Le catalogue donne le motif de chaque règle — **une règle dont le motif ne te parle pas est une règle à retirer**, pas à subir. Le vrai remède est que tes propres incidents produisent tes propres règles.

**Le corpus enseigne une voix.** Même vidé de son contenu, il est écrit dans un style dense et tranchant. Ton assistant en sera teinté quoi qu'il arrive. On ne peut pas l'éviter, on peut le savoir.

**Ne saute pas la première sauvegarde.** Une installation qui n'a pas prouvé qu'elle sait sauvegarder n'est pas une installation, c'est une promesse.

## Ce qui agit tout seul

Trois comportements du même genre que l'installation de `rtk` : décidés pour toi, utiles, et faciles à manquer. Les voici, avec la sortie.

- **Un lancement `claude` habillé.** La synchronisation ajoute à ton `~/.bashrc` une ligne qui source `engine/boot-wrapper.sh`, et ce wrapper définit une fonction `claude()` : taper `claude` sans argument ne lance plus l'outil nu, ça soumet d'office la question du bilan de démarrage. Les autres formes — `claude -p`, sous-commandes, arguments explicites — passent inchangées. Pour t'en défaire : retirer la ligne de `~/.bashrc` **et** l'étape 1 de `engine/SYNC_SETUP.sh`, sinon la prochaine synchronisation la repose.
- **Une sortie réseau mensuelle au démarrage.** Un déclencheur de début de session lance `check_upstream_drift.sh`, qui interroge une fois par mois `raw.githubusercontent.com` pour comparer la compétence d'interrogatoire empruntée à son dépôt d'origine. Lecture seule, silencieux hors ligne, n'écrit jamais la compétence : il alerte, l'adoption reste ta décision. Pour t'en défaire : retirer ce déclencheur de `~/.claude/settings.json`.
- **Un greffon réinstallé s'il manque.** À chaque synchronisation, si le greffon `superpowers` est absent, l'étape 2 de `engine/SYNC_SETUP.sh` le réinstalle d'elle-même — un appel réseau vers sa place de marché. C'est ce qui remet un poste en retard en état sans liste de gestes manuels. Si tu n'en veux pas, retirer cette étape en plus du greffon, sinon elle gagnera.

## Un style de sortie en option : ELI5

L'installation pose `~/.claude/output-styles/eli5.md` et n'y touche plus. Il n'est **pas activé** : ce squelette ne te livre pas la configuration de quelqu'un d'autre, et une voix imposée serait exactement ça. Il est fourni parce qu'il rend service — les jours où tu n'as plus la tête à lire des réponses d'ingénieur.

Activé, il fait répondre Claude en mots simples et phrases courtes : ce qui a été fait, si ça a marché, ce que tu dois faire — chemins de fichiers et commandes exacts, le reste élagué. Le comportement de codage, lui, ne change pas.

Pour l'allumer : `/config` dans Claude Code, choisir **Output style**, sélectionner **ELI5**. Ce menu écrit le choix dans `.claude/settings.local.json` du projet courant ; pour l'avoir partout, pose plutôt `"outputStyle": "ELI5"` dans `~/.claude/settings.json`. Effet au prochain `/clear` ou à la prochaine session, pas avant. Retour en arrière : le style **Default**, au même endroit.

## Les sessions de projet vivent dans tmux

tmux fait tourner des terminaux **à l'intérieur** d'un terminal : tu fermes la fenêtre, la session continue de tourner, tu la retrouves intacte en te rattachant. C'est tout ce qu'il faut savoir pour s'en servir ici.

Ce système s'en sert pour les sessions Claude Code de projet : une session par projet, nommée d'après son dossier, qui survit à la fermeture du terminal et à une coupure SSH — et que l'assistant peut ouvrir lui-même, sans dépendre d'un éditeur installé.

```bash
bash ~/.claudeos/engine/session-open.sh <projet>   # ouvre la session du projet (nom, fragment ou chemin)
bash ~/.claudeos/engine/session-open.sh --main     # la session principale : bilan de démarrage, sauvegarde
bash ~/.claudeos/engine/session-open.sh --list     # ce qui tourne
bash ~/.claudeos/engine/session-open.sh --close <nom>
tmux attach -t <nom>                               # s'attacher ; se détacher : Ctrl+b puis d
```

Une session de projet ne sauvegarde pas et ne porte pas le global : c'est le rôle de la principale, et c'est voulu — une seule session écrit, les autres travaillent. Sans tmux installé, rien de tout ça n'existe et rien d'autre ne casse.

## Entretenir

Une fois par semaine, dans Claude Code : `os audit`. Il relit le système, confronte ce qu'il affirme à ce qui existe, et rend une liste de correctifs par lots. Il ne corrige rien de lui-même.

Le reste tourne sans toi : la sauvegarde à chaque fin de session, l'autotest avant chaque sauvegarde, le bilan à chaque ouverture.

---

*Squelette extrait d'un système en service. Le contenu personnel a été retiré par un générateur qui contrôle sa propre sortie — noms propres, chemins de machine, liens vers des documents absents. Ce qui reste est de la mécanique et des règles ; ce qui te concerne, tu l'écriras toi-même.*
