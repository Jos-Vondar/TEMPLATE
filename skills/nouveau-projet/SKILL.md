---
name: nouveau-projet
description: Monter un projet neuf DANS un domaine existant et lui ouvrir sa session. Déclencheurs — « nouveau projet », « crée un projet dans <domaine> ». Pas pour un domaine neuf, c'est-à-dire un domaine entier → nouveau-domaine. Pas pour reprendre un projet existant → claudeos-session.sh.
---

# Monter un projet neuf et lui ouvrir sa session

> Fiche situationnelle. Se charge sur déclencheur. Elle existe parce que la compétence `nouveau-domaine` ne
> couvre que le domaine entier : le cas courant — un projet de plus dans un domaine
> déjà en place — n'avait aucune procédure, et se faisait donc de mémoire, différemment
> chaque fois.

## Ce qui rend ce montage particulier

**Un projet neuf naît au régime à ÉVÉNEMENTS : `ETAT.md` projeté depuis `journal/`, jamais de
`MEMORY.md`.** Le journal est la seule source de l'état du niveau, `ETAT.md` en est la projection.

**C'est `ETAT.md` qui fait exister la session.** `claudeos-session.sh` avertit quand il manque
(`ensure_session`), et ouvre quand même : l'oubli ampute le niveau sans rien casser.

## Selon le régime git

`GIT`, dans `reglages/REPONSES`, décide où vit le domaine ; le montage du projet, lui, ne
change pas.

- **`GIT=par-domaine`** : le domaine est un dépôt sous `~/`. Le projet est un dossier de ce dépôt
  et n'en crée aucun ; il part avec lui à la sauvegarde.
- **`GIT=unique`** : le domaine est un dossier `~/.claude/travail/<NOM>/` du dépôt du système.
- **`GIT=aucun`** : le domaine est un dossier `~/.claude/travail/<NOM>/`, sans dépôt. Rien ne se
  pousse ; la clôture contrôle sans rien envoyer, et le projet reste sur ce poste.

## Étapes

1. **Établir le domaine et le nom du projet.** Manquants → `AskUserQuestion`, la
   domaine d'abord, le nom ensuite. Les domaines sont ceux de la table « Mes
   domaines » du `CLAUDE.md` racine, et `claudeos_ws_roots` (`engine/config.sh`) en donne les
   dossiers ; les proposer telles quelles, ne pas les deviner. Le nom du dossier suit les
   conventions de la compétence `fichiers-et-nommage`.

2. **Vérifier que le dossier n'existe pas.** S'il existe, s'arrêter et demander : c'est
   probablement une reprise de projet, pas un montage — auquel cas ouvrir sa session suffit :
   `bash ~/.claude/engine/claudeos-session.sh <nom>`.

3. **Créer le dossier, son `CLAUDE.md` et son `journal/`.** Le `CLAUDE.md` vient du stub
   « Stub : CLAUDE.md projet » de `~/.claude/resources/DOMAINE_TEMPLATE.md`, marqueurs remplacés
   par les valeurs réelles. `mkdir -p <NomProjet>/journal`.

4. **Écrire l'événement inaugural, puis projeter.** Depuis le dossier du domaine :

   ```bash
   python3 ~/.claude/engine/etat.py add --niveau <NomProjet> --type etat --op avance \
     --chantier statut --ref e-projet-monte --source "<NomProjet>/CLAUDE.md" --texte "…"
   python3 ~/.claude/engine/etat.py projette --niveau <NomProjet>
   ```

   Le texte dit ce qui est monté, ce qui **n'est pas** construit, et ce que la première séance doit
   établir. `projette` engendre `ETAT.md` : il ne s'écrit jamais à la main, le crochet le refuse
   au commit (code 23).

   **Un projet neuf porte TROIS fichiers, pas plus** : `CLAUDE.md`, `ETAT.md`, et le `journal/` qui
   l'alimente. Le document de conception naît au premier besoin ; aucune archive ne naît, un récit
   soldé est un événement `observation`. Une souche jamais remplie fait croire à un système plus
   grand qu'il n'est.

5. **Si `CONFIDENTIEL=oui`** (`reglages/REPONSES`), **créer le réceptacle `_IGNORE/`** à la racine
   du projet, avant qu'un document confidentiel n'ait la moindre chance d'atterrir ailleurs. À
   `non`, rien.

6. **Router le projet dans son domaine** — une ligne dans la table « §0. Routing Projets »
   du `CLAUDE.md` du domaine, au format des lignes voisines. Un projet non routé a des
   instructions locales que rien ne charge jamais.

7. **Inscrire le projet au niveau du domaine, par un événement `pointeur`** : c'est la
   carte « Où trouver » de son `ETAT.md` qui le fait retrouver.

   ```bash
   python3 ~/.claude/engine/etat.py add --niveau . --type pointeur --op ajoute \
     --chantier statut --ref p-projet-<nom> --source "<NomProjet>/ETAT.md" --texte "Où vit … ?"
   python3 ~/.claude/engine/etat.py projette --niveau .
   ```

   **Trois refus à connaître** : l'`op` d'un `pointeur` est `ajoute` ou `retire`, jamais `pose` ;
   son `texte` a une borne, `TEXTE_MAX_PROJETE` d'`engine/etat.py`, et le récit va dans un
   `observation` séparé ; sa `source` est **un seul chemin qui résout**, pas une liste.

8. **Vérifier que le nom du projet résout** : `bash ~/.claude/engine/claudeos-session.sh <PROJET>`.
   Il n'y a rien à régénérer — les racines dérivent de `claudeos_ws_roots` à chaque appel. Ce qui
   se vérifie ici est que le fragment ne désigne qu'un seul dossier : s'il en désigne plusieurs,
   le script les liste et n'ouvre rien, et c'est au montage de choisir un nom discriminant.
   **Un avertissement « n'a pas d'ETAT.md » à cette étape est un défaut** — il veut dire que
   l'étape 4 n'a pas projeté l'`ETAT.md`.

9. **Rendre à l'utilisateur la commande d'attache exacte**, telle que le script la sort :
   `tmux attach -t <nom_de_session>`. Rappeler le geste de sortie sans fermeture, `Ctrl+b`
   puis `d` — une session détachée survit à la fermeture du terminal et à une coupure SSH.

10. **Écrire la reprise de la session principale** — un projet monté est un palier franchi, et
   deux sources de vérité du domaine viennent de changer. Procédure : compétence
   `reprise`.

## Ce qu'on ne touche pas, et pourquoi

**La table « Mes domaines » du `CLAUDE.md` racine reste inchangée.** Elle route les *domaines*,
pas les projets : le domaine y figure déjà, et c'est son propre `CLAUDE.md` qui route ses
projets (étape 6). Y ajouter une ligne par projet gonflerait la couche payée à chaque session pour
un routage que le niveau du dessous fait mieux.

## Critère de fin

**Les artefacts, nommés un par un ; il en manque un, le montage n'est pas fini.**

1. `<NomProjet>/CLAUDE.md` — écrit depuis le stub, marqueurs remplacés.
2. `<NomProjet>/journal/` — non vide : il porte l'événement inaugural.
3. `<NomProjet>/ETAT.md` — engendré par `etat.py projette`, jamais à la main.
4. `<NomProjet>/_IGNORE/` — si `CONFIDENTIEL=oui` ; à `non`, absent.
5. Une ligne du projet dans la table « §0. Routing Projets » du `CLAUDE.md` du domaine.
6. Un événement `pointeur` du niveau domaine qui nomme le projet, et sa projection passée.

**Puis `claudeos-session.sh <nom>` ouvre la session sans aucun avertissement**, elle démarre dans le
dossier du projet, et la reprise du niveau système porte le palier.
