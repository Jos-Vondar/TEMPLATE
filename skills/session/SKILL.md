---
name: session
description: Reprise de contexte, passe mensuelle, proposition du travail du jour. Aussi au moment de LANCER UN SOUS-AGENT (quel modèle, et le libellé qui le nomme) et de PARLER À UNE AUTRE SESSION. Aussi pour savoir OÙ revérifier un fait vivant avant d'agir — `ETAT.md` et son journal d'événements en premier — état d'un déploiement, contenu d'un dossier, statut d'une action externe. Fin de session et clôture → reprise.
---

# Règles — conduite de session

> Fiche situationnelle. Déclencheur : reprise de contexte annoncée, passe mensuelle signalée au démarrage, proposition du travail du jour (bilan de démarrage, « qu'est-ce qu'on fait aujourd'hui », arbitrage de priorités). La fin de session et la fin d'une séance de conception relèvent de `reprise`. Plus deux moments : je lance un sous-agent, et je parle à une autre session.
> Relayer d'emblée les signaux du démarrage vit dans la compétence `demarrage`, que le mod `demarrage-auto` invoque par `/demarrage` au lancement ; quand une séance ouverte depuis plusieurs jours veut son bilan du jour, proposer à l'utilisateur de taper `/demarrage`. Il n'en reste ici que l'application d'un rappel échu, [`PROPOSITION_DU_JOUR.md`](PROPOSITION_DU_JOUR.md).

## Lancer un agent — modèle et libellé

**Sélection du modèle : le plus capable adapté à l'enjeu, qualité avant rapidité, sans figer un modèle par type de tâche.** La session ne choisit pas son propre modèle : cette règle ne sert qu'au lancement d'un agent. Une règle de l'utilisateur qui fixe le modèle d'un geste — une relecture, un audit — prime sur elle ; elle vit dans « Mes règles » du `CLAUDE.md`.

**Quand un modèle ou un effort est fixé, il se pose explicitement** :
- **Agent défini** : son frontmatter porte `model:` — l'identifiant exact, pas l'alias — et `effort:`. `effort` du frontmatter remplace celui de la session *(vérifié le 2026-09-30, code.claude.com/docs/en/sub-agents)* ; un champ mal orthographié est ignoré sans erreur, donc relire l'orthographe.
- **Agent lancé sans définition** (`general-purpose`, ad hoc) : passer `model` et `effort` dans l'appel de l'outil `Agent` ; `model` n'y accepte qu'un alias (`opus`, `sonnet`, `haiku`), jamais un identifiant complet *(vérifié le 2026-11-25, code.claude.com/docs/en/sub-agents ; le paramètre `effort` de l'appel demande Claude Code 2.1.292 ou ultérieur)*.

**Tout libellé d'agent lancé et de tâche suivie nomme son modèle** — « Audit check 3 · Opus » —, pour que la barre des agents dise qui travaille.

## Parler directement à une autre session

**Un geste qui sort de mon périmètre d'écriture et appartient à une autre session, je le lui envoie
moi-même** : `ListAgents` pour la trouver, puis `SendMessage`. Je ne rédige pas une consigne que
l'utilisateur devra recopier. Hors périmètre d'**écriture** ne veut pas dire hors de portée.

- **Le brief part avec tout le contexte**, parce que la session cible ne voit pas la mienne : ce qui
  est déjà fait de mon côté — pour qu'elle ne le refasse pas —, les gestes attendus avec leurs
  chemins, et les pièges.
- **Une session marquée occupée reçoit quand même** : le message s'empile et se traite à son prochain
  tour d'outil.
- **Jamais un geste que mes propres permissions ont refusé.** Le faire exécuter par un pair
  contournerait une décision de l'utilisateur. Un refus se remonte à lui, il ne se sous-traite pas.
- **Le rapport d'un pair se recontrôle comme celui d'un sous-agent** (règlement, socle, « Trois interdits,
  jamais conditionnés »). Réciproquement, un pair qui refuse d'endosser mon tri sans l'avoir vérifié applique
  la règle, il ne résiste pas.

## Avant tout travail de fond

- **Consulter la carte de rappel** (`## Où trouver` d'`ETAT.md`) **et chercher les décisions passées dans le corpus** (document de conception, journal, retours), au lieu de s'en tenir à la chaîne chargée par le routage.

### Faits vivants — où les revérifier

Le règlement garde le principe : *un fait vivant se revérifie à sa source avant toute action conséquente ou irréversible ; écrit sans sa date et sa source, il est à revérifier, pas à croire.* Voici les sources.

| Fait vivant | Source canonique |
| :--- | :--- |
| Ce que contient un dossier, si un fichier existe | le disque **de la machine nommée** — un dossier non synchronisé (`_IGNORE/`, local-only) diffère d'un poste à l'autre, donc « le fichier est là » sans dire *où* ne veut rien dire |
| Dernier point de sauvegarde, retard d'un poste | l'historique du dépôt ; en `GIT=aucun`, il n'y en a pas : la dernière clôture passée se lit à `~/.claude/.claudeos/empreintes/MANIFESTE.json`, qu'elle réécrit |
| État d'un déploiement, version réellement en service | le système déployé lui-même, ou son export |
| Ce qui reste à faire | `etat.py fils --tous` (vue par ancienneté, calculée) ; à défaut, `etat.py vue` du niveau |
| Statut d'une action externe (accès, ticket, PR) | le service concerné |

**Sont durables, et ne demandent pas cette revérification** : identité, préférences, but et positionnement d'un projet.


## Chargement

- **Un niveau qui porte `ETAT.md` se charge par LUI.** `ETAT.md` est court et projeté ; l'histoire est au journal, cherchée au `grep`, jamais chargée.
- **Lire par sections ciblées donne le sentiment complet d'avoir consulté.** Deux gestes l'empêchent : **une compétence qu'on va ÉDITER s'invoque d'abord par l'outil `Skill`**, jamais lue au `grep` ou au `sed` seulement ; **un document qu'un `CLAUDE.md` rend obligatoire avant un geste se lit en entier**, pas à la section cherchée.
- Profondeur selon le poids de la tâche : question rapide → le `CLAUDE.md` local concerné seulement ; travail courant → plus l'`ETAT.md` local ; travail de fond, code ou spec → chaîne complète plus corpus.

## Reprise de contexte

Quand l'utilisateur déclare un contexte de travail (« je reprends <PROJET> ») :

1. **Suivre la cascade de chargement du règlement (socle, « Niveaux ») — elle est la source, et cette fiche ne la recopie pas.**
2. **Lire l'état du niveau.** S'il porte `ETAT.md` : celui-là, puis `grep` dans son `journal/` sur ce qu'on cherche — l'histoire n'est pas dans l'état. Sinon, ce n'est pas encore un niveau : le monter d'abord (compétence `nouveau-projet`).
3. **En régime GitHub, si le poste est en retard sur un dépôt, tirer AVANT de lire les fichiers
   locaux** — sinon on travaille sur des fichiers périmés. Le bilan de démarrage annonce le retard en
   commits ; le geste est `git -C ~/.claude pull --rebase`, et l'équivalent sur chaque dépôt que
   `claudeos_repos` rend. En `GIT=aucun`, un seul poste et aucun dépôt : rien à tirer.

## Passe mensuelle — l'audit du système

Due une fois par mois ; le démarrage la signale passé son seuil, que porte `engine/boot-check.sh`. La
procédure vit dans la compétence `os-audit`, seule autorité : l'invoquer, suivre sa fiche d'hygiène.
La clôture ne rejoue aucun contrôle de la passe (`reprise`) : une passe sautée est un mois sans
vérification. Quand `REGLES_A_FROID=oui`, une règle candidate attend la passe pour se promouvoir :
`skills/memoire-et-verite/SOURCES_DE_VERITE.md`, § « Une règle candidate — cool-down et troc ».

## Proposition du jour

**Avant de proposer le travail du jour, d'arbitrer des priorités ou de traiter un rappel échu, lire
en entier [`PROPOSITION_DU_JOUR.md`](PROPOSITION_DU_JOUR.md)** : filtre du créneau, chiffrage,
rappel échu et reconduit, idées lancées en passant.

## Fin de session, et écriture de reprise

La compétence `reprise` en est seule autorité — quand écrire, où, quoi, les gestes de la clôture.
Ne rien en recopier ici : deux fiches sur la même règle font deux cadences.
