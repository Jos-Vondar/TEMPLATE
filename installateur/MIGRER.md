# Migrer — d'une V1 ou d'une V2 vers la V3

Procédure de l'agent, mode `migrer` (`LANCEMENT.md`). La V3 ne se pose pas par-dessus une V1 ou une
V2. Elle s'installe à neuf, puis importe ce qui appartient à la personne (`d-migration-v3-neuf-import`).

- **Les deux régimes n'ont aucun chemin commun.** Le moteur V2 vit sous `~/.claudeos/`, clone d'un
  dépôt de sauvegarde séparé et alimenté par rsync. En V3, `~/.claude` est le système lui-même.
- **La V2 reste intacte jusqu'au bout.** Ce qu'elle a posé dans `~/.claude` part en quarantaine,
  sous `~/.claudeos-v2-quarantaine/`. Son dépôt local, ses dossiers de travail et son dépôt de
  sauvegarde ne sont jamais touchés avant le retrait. **Rien ne se supprime**, retrait compris.

Le script est `engine/import-v2.py`. Avant la plomberie, il se lance depuis
`~/claudeos-amorce/engine/` ; après, depuis `~/.claude/engine/`, qui porte le même fichier. Il ne pose
aucune question : tu confirmes chaque geste avant de le lancer. Chaque phase se clôt sur
`python3 engine/verifier.py migration --etape <étape>`, qui délègue à `import-v2.py --verifier`.
Les questions, les confirmations et les bornes sont celles de `LANCEMENT.md`.

**Reprendre une migration interrompue** : `verifier.py mode` rend `migrer` tant qu'une quarantaine
existe. `import-v2.py --verifier` nomme alors ce qui manque. Reprends à la première phase qu'il
nomme.

## M0 — Les préalables

- **Une dernière sauvegarde V2.** La personne la lance avec son outil V2,
  `bash ~/.claudeos/engine/backup.sh`, et tu lis la sortie avec elle. C'est aussi ce qui permet de
  montrer, plus loin, ce qu'elle a changé dans une compétence.
- **Toutes les sessions Claude Code fermées**, sauf celle-ci.
- **Dis le coût** : une séance, plus une seconde avant le retrait. La V2 reste utilisable jusqu'à la
  quarantaine (M2).

## M1 — L'amorce et le lancement

L'amorce est posée et l'agent lancé, comme pour une installation (`INSTALLER.md`, I0 et I1).
`verifier.py mode` a rendu `migrer` : montre-lui les traces. Puis I2, la lecture obligée
(`ACCUEIL.md`).

## M2 — L'inventaire et la quarantaine

1. **L'inventaire** : `python3 ~/claudeos-amorce/engine/import-v2.py --inventaire`. Il est en
   lecture seule. Montre-le en entier. Il donne :
   - les deux versions, celle du moteur et celle de l'entretien, qui peuvent différer : une mise à
     jour V2 ne rejouait pas l'entretien ;
   - chaque élément V-1 à V-18 et ce qu'il deviendra ;
   - les questions que l'entretien d'origine n'a jamais posées.
2. **La quarantaine.** Montre d'abord `--quarantaine --essai`, qui liste les gestes sans rien
   écrire. Puis, sur confirmation, `--quarantaine`, qui :
   - copie et vérifie, puis retire de `~/.claude` le règlement, les documents, les compétences et
     fiches, le style, la mémoire et les secrets de la V2 ;
   - retire de `settings.json` les crochets de la V2, et du shell sa ligne de démarrage. Une copie
     de chaque fichier est gardée.
3. **Fin** : `verifier.py migration --etape quarantaine` rend `0`.
4. **Le retour arrière** : `--restaurer` remet la V2 à l'octet. Il refuse tant qu'une V3 occupe
   `~/.claude` : la plomberie se défait d'abord.

## M3 — La plomberie

`INSTALLER.md`, I3 à I5. À I3, `verifier.py prerequis` ne doit plus dire **M-V2-DETECTEE** ; s'il
le dit, une trace de la V2 est restée dans `~/.claude`, et il la nomme.
- **Le régime** : propose `GIT=unique`, puisque la V2 était un seul dépôt. `aucun` est permis, un
  dépôt par domaine aussi.
- **Le dépôt est neuf** : celui de la V3 vient du bouton. L'ancien dépôt de sauvegarde V2 ne se
  réutilise pas ; il s'archive au retrait.
- **`rtk`** : la V2 l'a souvent installé, et `RTK.md` est resté en place (V-13). PROXY se détecte
  comme pour une installation.

## M4 — L'import et l'entretien

1. **En régime par domaine seulement**, pose d'abord `ENTRETIEN.md` § 1, `PREFIXES` et
   `PREFIXES_CLIENT`, et écris-les dans `reglages/REPONSES`. L'import en tire le nom de chaque
   domaine.
2. **L'import à blanc** : `python3 ~/.claude/engine/import-v2.py --importer --essai ~/claudeos-amorce/essai-import`.
   Montre `RAPPORT`, puis ce qu'il écrirait :
   - `REPONSES` : les clés que l'entretien d'origine a posées, `oui` ou `non`, rien d'autre ;
   - dans `CLAUDE.md`, « Persona » : les douze rubriques de la V1 et de la V2 deviennent neuf. Une
     rubrique fusionnée qui reçoit deux réglages porte la note « deux réglages à fondre en un ».
     L'énoncé générique du gabarit tombe ; une rubrique égale à cet énoncé n'a jamais été réglée,
     et garde sa marque ;
   - dans `CLAUDE.md`, « Mes domaines », chaque dossier réécrit vers sa destination V3 ;
   - `REGLES_CANDIDATES.md` et `COMPETENCES_MODIFIEES.md`.
3. **Les secrets de faible valeur** (V-11), s'il y en a : hors du dépôt par défaut, comme en V2
   (O2). La personne peut les vouloir suivis : `--secrets depot`.
4. **L'import**, sur confirmation : `--importer`. Il verse la mémoire sous `memory/`, la chronique
   gelée, et fait revenir les compétences créées par la personne, les secrets et les créneaux.
5. **Les règles candidates, une à une**, chacune dans le `preview` de sa question :
   `--regle N garder` la recopie à la fin de « Mes règles », `--regle N laisser` la met de côté. Une
   règle qui cite un nom de la V2 est refusée : réécris-la avec la personne, puis
   `--regle N garder --texte "…"`.
6. **Les compétences V2 modifiées, une à une**, la différence montrée : `--competence NOM regle`
   (tu écris la règle avec elle dans « Mes règles »), `competence` (tu copies sa version sous un nom
   neuf), ou `rien`.
7. **Les ressources** (V-15), une à une : `--ressource NOM` copie vers `~/.claude/resources/`
   (O3) ; `--vers` ailleurs ; `--hors` les laisse hors de ClaudeOS. L'original reste.
8. **`ENTRETIEN.md`, réduit à ce qui manque.**
   - Les clés : seulement celles que l'inventaire a nommées. **Une clé jamais demandée se pose, et
     ne prend jamais « non » par défaut** : sinon « jamais demandé » se lirait « refusé ».
   - Les rubriques encore marquées, et les deux réglages d'une rubrique fusionnée, à fondre avec
     la personne.
   - « Mes domaines » est déjà rempli : ne le double pas.
9. **Dis ce qui change** : la sauvegarde n'a plus lieu qu'à la clôture. Le crochet de fin de session
   de la V2 a disparu.
10. **Fin** : `verifier.py migration --etape import`, puis `verifier.py entretien`, à `0`.

## M5 — Les domaines

Un domaine à la fois, chacun confirmé, dans l'ordre de l'inventaire. Un domaine est **copié, pas
déplacé** :
- **`GIT=unique` ou `GIT=aucun`** : `--domaine <D>`, vers `~/.claude/travail/<D>/` ;
- **`GIT=par-domaine`** : d'abord `nouveau-domaine`, étapes 3 et 4, sur `~/<NOM>/`, pour le
  dépôt, l'identité et la liste noire. Ensuite `--domaine <D> --vers ~/<NOM>`, puis les étapes 10 à
  12, dont le dépôt GitHub privé, créé après confirmation.

Pour chaque niveau :
- `MEMORY.md` et le fichier de reprise sont copiés gelés ;
- la reprise devient le premier état du niveau ;
- `_IGNORE/` est copié à l'identique, et ignoré du dépôt avant la copie.

Le script nomme les lignes copiées qui citent un nom de la V2 sans date. **Réécris-les avec la
personne avant la première clôture** : le crochet de commit les refuserait. Un domaine dont elle ne
veut plus : `--domaine <D> --laisser`.

**Fin** : `verifier.py migration --etape domaines` rend `0`.

## M6 — La première clôture

`INSTALLER.md`, I8 : une vraie fin de séance, puis une vraie reprise.

## M7 — La double sécurité

Au moins une séance complète sur la V3 avant le retrait. La V2 attend, intacte. `--retrait` refuse
tant qu'aucun événement `seance` n'est daté après l'import.

## M8 — Le retrait

Chaque geste se confirme à part :
- **`--retrait`** range sous `~/.claudeos-v2-archive/` le dépôt local, les dossiers de travail et la
  quarantaine de la V2. Rien n'est effacé, et supprimer cette archive reste la décision de la
  personne, plus tard : un `_IGNORE/` y est peut-être le seul exemplaire d'un document ;
- **le dépôt de sauvegarde V2**, archivé par `gh repo archive <dépôt>`, une écriture externe.

**Fin** : `verifier.py migration`, puis `verifier.py arrivee`, à `0` tous les deux. Puis
**M-FIN-INSTALL** (`INSTALLER.md`).
