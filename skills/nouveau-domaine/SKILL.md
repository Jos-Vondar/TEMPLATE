---
name: nouveau-domaine
description: Monter un domaine d'activité entier — son dépôt git en régime par domaine, son dossier travail/<NOM>/ sinon. Déclencheurs — « nouveau domaine », « nouveau client ». Porte aussi son retrait, qui peut passer par une suppression de dépôt distant. Pour un projet dans un domaine existant → nouveau-projet.
---

# Monter ou retirer un domaine

> Fiche situationnelle. Un domaine est le dossier d'un domaine d'activité — un client, un pan
> du travail. Où il vit dépend de `GIT`, dans `~/.claude/reglages/REPONSES` : en
> `GIT=par-domaine`, un dépôt git privé `~/<NOM>/` ; en `GIT=unique`, un dossier
> `~/.claude/travail/<NOM>/` du dépôt du système ; en `GIT=aucun`, le même dossier, sans dépôt, et
> rien ne sort du poste. Le savoir-faire de métier, commun à plusieurs domaines, vit à part sous
> `~/.claude/domaines/<METIER>/` : malgré le nom du dossier, c'est un savoir-faire, pas un domaine.

## Monter un domaine

1. **Lire les réponses**, puis **demander par `AskUserQuestion`** ce qu'elles ne disent pas : le nom,
   le domaine en une phrase, le nom du premier projet, et si son savoir-faire existe déjà sous
   `~/.claude/domaines/`. Le nom :
   - en `GIT=par-domaine`, il commence par un préfixe de `PREFIXES` ; un préfixe de
     `PREFIXES_CLIENT` en fait un dépôt client, dont le crochet contrôle la liste noire (étape 4) ;
   - en `GIT=unique` ou `GIT=aucun`, aucun préfixe : le nom suit la compétence `fichiers-et-nommage`.
2. **Vérifier que la racine n'existe pas.** En `par-domaine`, `~/<NOM>/` absent et le nom libre côté
   distant (`gh repo list`). En `unique` ou `aucun`, `~/.claude/travail/<NOM>/` absent — aucun appel
   à `gh`, il n'y a pas de distant.
3. **Créer la racine.**
   - `par-domaine` : un dépôt local, avec l'identité lue dans `~/.claude/reglages/IDENTITE_GIT`,
     source unique — jamais recopiée ici. Sans elle, le premier commit échoue.
     ```bash
     D=~/<NOM> && mkdir -p "$D" && git -C "$D" init -b main
     . ~/.claude/reglages/IDENTITE_GIT && git -C "$D" config user.name "$GIT_NOM" && git -C "$D" config user.email "$GIT_EMAIL"
     ```
   - `unique` ou `aucun` : un dossier, sans `git init`.
     ```bash
     D=~/.claude/travail/<NOM> && mkdir -p "$D"
     ```
4. **La liste noire, AVANT le premier `git add`** — l'ordre est le geste : un `git add -A` sans elle
   embarque le `_IGNORE/` et le pousse au distant.
   - `par-domaine` : `cp ~/.claude/engine/config/gitignore-documents "$D/.gitignore"`. Versionnée, et
     non un `core.excludesFile` qui n'arriverait pas avec le clone. Dans un dépôt client, le crochet
     (**code 25**) refuse une copie divergente ou absente.
   - `unique` : rien à copier. La liste noire vit dans le `.git/info/exclude` de `~/.claude`, posée
     par `install-poste.sh`, et le crochet (**code 25**) la contrôle.
   - `aucun` : rien, il n'y a pas de dépôt.
5. **Créer les TROIS fichiers de chaque niveau** — domaine puis projet : le `CLAUDE.md` depuis
   `~/.claude/resources/DOMAINE_TEMPLATE.md`, puis `ETAT.md` et son `journal/` par un événement
   inaugural et une projection, comme l'étape 4 de `nouveau-projet`. **Aucun `MEMORY.md`.** Le
   document de conception naît au premier besoin. Une souche vide fait croire à un système plus
   grand qu'il n'est.
6. **Si `CONFIDENTIEL=oui`, créer le réceptacle `_IGNORE/`, un seul, au niveau qui porte le projet** :
   `mkdir -p "$D/<Projet>/_IGNORE"`. Jamais au niveau d'une app, et le contrôle hebdomadaire 28bis
   refuse un réceptacle sous un autre.
7. **Router le domaine** — une ligne dans la table « Mes domaines » du `CLAUDE.md` racine : ce
   qu'il couvre, son dossier, et en remarque le savoir-faire lié s'il y en a un.
8. **Router le projet** — une ligne dans « Routing Projets » du `CLAUDE.md` du domaine. Un
   projet non routé a des instructions que rien ne charge.
9. **Lier le savoir-faire de métier**, s'il existe — lien symbolique **relatif**, jamais une copie :
   aucun chemin propre au poste dans un fichier suivi, et le lien voyage. D'abord
   `mkdir -p "$D/.claude/rules"`, puis UNE des deux formes :
   - `par-domaine` — trois remontées mènent à `~` :
     `ln -s ../../../.claude/domaines/<METIER>/CLAUDE.md "$D/.claude/rules/<METIER>.md"`
   - `unique` ou `aucun` — quatre remontées mènent à `~/.claude` :
     `ln -s ../../../../domaines/<METIER>/CLAUDE.md "$D/.claude/rules/<METIER>.md"`

   Contrôle : `test -f "$D/.claude/rules/<METIER>.md"` suit le lien jusqu'à sa cible ; en
   `par-domaine`, `git -C "$D" ls-files -s .claude/rules` rend en plus le mode `120000`.
10. **Poser les gardes qui ne voyagent pas** — `bash ~/.claude/engine/install-poste.sh`, idempotent,
    qui boucle sur `claudeos_repos`. En `par-domaine`, les hooks vivent sous `.git/`, que git ne suit
    pas : **un shim absent ne fait pas échouer le commit, il le laisse passer muet.** En `unique` ou
    `aucun`, rien de neuf à poser.
11. **Inscrire le domaine au niveau système, par un événement `pointeur`** — `etat.py add --niveau .
    --type pointeur --op ajoute` depuis `~/.claude`, puis `projette`.
12. **Ce qui sort du poste.**
    - `par-domaine` — **créer le distant et pousser, POINT D'ARRÊT.** Présenter `git ls-files | wc -l`
      et les vingt plus gros fichiers suivis. Sur feu vert seulement, et **privé toujours** — le
      contenu nomme les clients partout :
      `gh repo create "$(gh api user --jq .login)/<NOM>" --private --source="$D" --remote=origin --push`
    - `unique` — rien à créer : le domaine part avec le dépôt du système à la prochaine clôture.
    - `aucun` — rien ne sort : la clôture contrôle sans rien envoyer.
13. **Écrire la reprise** : deux sources de vérité du système viennent de changer (`reprise`).

**Critère de fin.** `claudeos-session.sh <PROJET>` ouvre sans avertissement « n'a pas d'ETAT.md » ;
`weekly-check.sh` rend `rc=0`. Et selon le régime :
- `par-domaine` : `git -C "$D" ls-files` rend les fichiers créés ; le shim est exécutable ;
  `claudeos_repos` rend le dépôt neuf ; si `CONFIDENTIEL=oui`,
  `git -C "$D" check-ignore --no-index -q <Projet>/_IGNORE/temoin` rend `0` — la règle se mesure,
  un `_IGNORE/` vide n'apparaît dans aucun `git status` ;
- `unique` : `claudeos_ws_roots` rend `~/.claude/travail/<NOM>` ; si `CONFIDENTIEL=oui`,
  `git -C ~/.claude check-ignore --no-index -q travail/<NOM>/<Projet>/_IGNORE/temoin` rend `0` ;
- `aucun` : `claudeos_ws_roots` rend `~/.claude/travail/<NOM>`, et rien n'a appelé `git` ni `gh`.

## Un savoir-faire neuf

Un savoir-faire de métier **ne reçoit pas de dépôt** : il vit sous `~/.claude/domaines/<METIER>/`, et
chaque domaine le lie par l'étape 9. Y montent les règles du métier, sa conception, ses références,
ses relecteurs (`agents/`) ; pas une table de routage ni une règle vraie d'un seul domaine — fausse
hors de lui. **Son `ETAT.md` attend le SECOND domaine qui le lie** : avant lui, l'état du métier est
celui du premier.

**Un domaine dont le métier ne sert qu'à lui ne crée aucun dossier de savoir-faire** — le travail
interne d'une entreprise, un domaine personnel. Le crochet (**code 26**) refuse une copie de
relecteur divergente de sa source : un relecteur qui dérive juge sur d'autres règles, sans le dire.

## Retirer un domaine

**Ce qui dicte l'ordre : ce qui ne se rattrape pas vient en dernier, point d'arrêt dur** —
l'utilisateur confirme, l'agent n'anticipe pas. En `par-domaine`, c'est la suppression du dépôt
distant ; en `GIT=aucun`, la suppression du dossier lui-même, qui n'a ni historique ni copie
ailleurs.

1. **Inventorier en ouvrant le dossier** : régénérable, stocké ailleurs, ou exemplaire unique. Le
   `_IGNORE/` n'existe qu'en local, donc **faire confirmer** chacun de ses fichiers.
2. **Sauver avant de supprimer, en nommant la destination.** Outil → `~/.claude/resources/` ;
   savoir-faire → `~/.claude/domaines/<METIER>/` ; conception → les plans et specs du système
   (compétence `fichiers-et-nommage`). Si c'est confidentiel, l'anonymiser avant de le remonter —
   sinon **le dire** au lieu de le supposer sauvé.
3. **Le dernier exemplaire avant de couper.**
   - `par-domaine` : `git clone --mirror ~/<NOM> ~/<NOM>-miroir.git` — c'est le dernier exemplaire de
     l'historique une fois le distant retiré.
   - `unique` : rien à faire, l'historique reste dans le dépôt du système.
   - `aucun` : une archive, `tar -czf ~/<NOM>-<AAAA-MM-JJ>.tgz -C ~/.claude/travail <NOM>` — le seul
     exemplaire après la suppression.
4. **Corriger tout ce qui nomme encore le domaine**, sans se fier à un décompte : la table
   « Mes domaines », les compétences de l'utilisateur — qui citent parfois un artefact par son motif
   de nom sans son chemin, donc hors de portée de tout contrôle —, le document de conception, et les
   pointeurs de l'`ETAT.md` système (`etat.py add --type pointeur --op retire`). **Plans et specs
   exceptés** : traces datées, note de caducité datée. Les compétences livrées par le template ne
   s'éditent pas.
5. **Supprimer le dossier local — en `GIT=aucun`, POINT D'ARRÊT, après avoir montré l'archive** —,
   puis contrôler que `claudeos_ws_roots` ne le rend plus.
6. **`par-domaine` — POINT D'ARRÊT, retirer le distant.** `gh repo delete "$(gh api user --jq .login)/<NOM>"`,
   à ne proposer qu'après avoir montré le miroir et son compte de commits.
7. **Si `MULTIPOSTE=oui`, déposer une consigne pour l'autre poste** — `- [ ]` dans `~/.claude/TODO.md`,
   section du poste. Son dossier local **survit** au retrait fait ici : git ne propage pas la
   disparition d'un clone.
8. **Relancer `weekly-check.sh`** — seule vérification mécanique du trajet.
