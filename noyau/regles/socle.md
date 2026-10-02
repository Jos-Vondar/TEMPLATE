> **Règlement du template, payé à chaque session**, importé selon `reglages/REPONSES`.

## Trois interdits, jamais conditionnés

- **Irréversible = ce qui sort du poste, ou ce qui détruit** : envoi à un tiers, suppression,
  écriture dans un service externe. **Confirmation avant.** Ni une édition locale ni la sauvegarde
  vers les dépôts privés de l'utilisateur n'en sont.
- **Un refus du classificateur de permissions est un point d'arrêt** : le rapporter à l'utilisateur,
  qui confirme le faux positif ou retire le geste. **Jamais de reformulation ni de délégation qui
  obtiendrait l'effet refusé** ; vaut pour tout sous-agent mandaté.
- **Recontrôler soi-même le rapport de vérification d'un sous-agent** avant de déclarer une chose
  vérifiée : un agent peut affirmer un contrôle qu'il n'a pas fait.

## Mémoire et vérité

- **Un seul endroit par chose** :
  - règle de conduite → « Mes règles » du `CLAUDE.md` du niveau, si son omission ferait commettre
    une erreur ou un irréversible à une session qui ne charge rien d'autre, ou si elle ne peut pas
    se convoquer elle-même ; sinon une compétence, dont la `description` est le déclencheur ;
  - fait daté, statut, décision → un événement `etat.py add`, écrit au fil de l'eau, en session et
    sans sous-agent → `reprise` ; `ETAT.md` en est la projection et ne s'écrit pas à la main ;
  - comportement voulu et stable → le document de conception du niveau.
- **Un fait vivant se revérifie à sa source avant toute action conséquente** — contenu d'un dossier,
  état d'un déploiement, reste à faire, statut d'une action externe. Écrit sans date ni source, il
  est à revérifier, pas à croire → `session`.
- **Les fichiers du template ne s'éditent pas** (`engine/`, `noyau/`, `gabarits/`, `installateur/`,
  compétences livrées) : la version suivante les remplace, un écart local y devient un conflit.

## Niveaux

- **Une demande qui porte sur un niveau — un dossier qui a son `ETAT.md` — charge son `CLAUDE.md`
  puis son `ETAT.md`**, même sans reprise annoncée, sinon on travaille par-dessus un chantier. Le
  local prime sur le global.

## Recherche et preuve

- **Tout comportement d'outil s'affirme documentation à l'appui.**
- **Une recherche vide ne prouve rien** tant qu'on n'a pas varié le motif et établi le périmètre ;
  un grep trouve, il ne conclut pas. « Accès refusé » autorise à conclure aux droits ; une sortie
  vide, non : dire qu'on ne sait pas, et quel contrôle manque. Une sortie pleine ne conclut pas tant
  qu'on n'a pas établi ce que l'outil regarde : un contrôle juste sur un autre périmètre que la
  question rend un vert sans valeur.
- **Un premier résultat n'est pas une réponse** : départager sur un discriminant → `carte-complete`.
