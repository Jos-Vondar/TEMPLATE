# Un système d'exploitation pour Claude Code

Ce dépôt est un **squelette**. Il installe une configuration Claude Code qui se souvient, se sauvegarde, se vérifie et se corrige — puis il t'interroge pour la rendre tienne.

Ce n'est pas la configuration de quelqu'un d'autre livrée telle quelle. Le contenu personnel en a été retiré : pas de nom de client, pas de projet, pas de métier, pas de persona. Ce qui reste, c'est la mécanique, et les règles qui ont une raison d'exister chez plus d'une personne.

## Ce que ça fait

- **Sauvegarde** ta configuration et ton travail dans un dépôt git privé, à chaque fin de session, sans que tu y penses.
- **Synchronise** tes machines par ce même dépôt.
- **Refuse** de laisser partir ce qui ne doit pas partir : documents confidentiels, secrets, fichiers de données. Liste blanche, pas liste noire — tout est refusé par défaut, on autorise nommément.
- **Se vérifie** avant chaque sauvegarde : une trentaine de contrôles mécaniques, qui bloquent quand un défaut se désactiverait en silence et se contentent d'avertir quand il ne fait qu'encombrer.
- **Se souvient** : mémoire par niveau, carte de rappel, journal de séances, fils ouverts, rappels datés — et un bilan de l'état du système injecté à l'ouverture de chaque session.
- **Apprend** : une passe hebdomadaire relit ce qui s'est passé et propose des règles. Proposition, validation, écriture — jamais d'auto-règle.

## Installer

**Prérequis** : `git`, `rsync`, `curl`, `python3`, Claude Code, une identité git configurée, et **un dépôt git privé vide** qui servira de sauvegarde.

```bash
git clone <ce-dépôt> claudeos-squelette
cd claudeos-squelette
bash install.sh
```

Le script demande l'URL de ton dépôt de sauvegarde, vérifie qu'il est clonable **et inscriptible** avant d'écrire quoi que ce soit, pose la machinerie, câble les déclencheurs de Claude Code, calibre ses alarmes sur ton corpus réel, et lance son autotest. Il s'arrête à la première étape qui échoue : un demi-système installé est pire qu'aucun, il a l'air de marcher.

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

Ton fichier de règles, ta mémoire et tes dossiers de travail ne sont jamais touchés. Une mise à jour porte sur le moteur, les fiches et les compétences — ce qui vient de ce dépôt, pas ce que tu as écrit.

Un fichier que tu as choisi de garder reste marqué comme tien : on te le redemandera à la prochaine version au lieu de l'écraser en te croyant d'accord.

`--ref v1.2.3` vise une version précise. Sans elle, c'est la dernière publiée — pas la pointe de la branche, qui peut porter du travail en cours.

## Ce qu'il y a dedans

| | |
| :--- | :--- |
| `install.sh` | L'amorçage. Déterministe, idempotent, s'arrête bruyamment. |
| `engine/` | La machinerie : sauvegarde, synchronisation, autotest, bilan de démarrage, générateurs de mémoire. |
| `system/CLAUDE.md` | Le règlement, livré en gabarit. L'entretien en retire les règles sans objet. |
| `system/RULES_CATALOG.md` | Pour chaque règle : son énoncé, **le motif qui l'a fait naître**, et la condition sous laquelle elle mérite d'exister. |
| `system/DESIGN.md` | Comment le système marche et pourquoi il marche ainsi. |
| `system/fiches/` | Les règles situationnelles, chargées sur déclencheur et pas à chaque session. |
| `system/skills/` | L'entretien d'installation, l'audit périodique, et une compétence d'interrogatoire empruntée. |

## Trois choses à savoir avant de t'en servir

**Tu hérites de règles que tu n'as pas méritées.** Chacune est née d'un incident précis, arrivé à quelqu'un d'autre. Une règle abstraite se respecte moins bien qu'un cas vécu : celles-ci tiendront mécaniquement moins bien chez toi. Le catalogue donne le motif de chaque règle — **une règle dont le motif ne te parle pas est une règle à retirer**, pas à subir. Le vrai remède est que tes propres incidents produisent tes propres règles.

**Le corpus enseigne une voix.** Même vidé de son contenu, il est écrit dans un style dense et tranchant. Ton assistant en sera teinté quoi qu'il arrive. On ne peut pas l'éviter, on peut le savoir.

**Ne saute pas la première sauvegarde.** Une installation qui n'a pas prouvé qu'elle sait sauvegarder n'est pas une installation, c'est une promesse.

## Entretenir

Une fois par semaine, dans Claude Code : `os audit`. Il relit le système, confronte ce qu'il affirme à ce qui existe, et rend une liste de correctifs par lots. Il ne corrige rien de lui-même.

Le reste tourne sans toi : la sauvegarde à chaque fin de session, l'autotest avant chaque sauvegarde, le bilan à chaque ouverture.

---

*Squelette extrait d'un système en service. Le contenu personnel a été retiré par un générateur qui contrôle sa propre sortie — noms propres, chemins de machine, liens vers des documents absents. Ce qui reste est de la mécanique et des règles ; ce qui te concerne, tu l'écriras toi-même.*
