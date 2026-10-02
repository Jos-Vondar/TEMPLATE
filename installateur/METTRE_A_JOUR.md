# Mettre à jour — une version neuve du template

Procédure de l'agent, mode `v3`, quand la personne veut la version suivante (`LANCEMENT.md`).

- **Ce que le template possède change** : le moteur, les fragments, les compétences livrées, les
  gabarits.
- **Ce qui est à elle ne bouge pas** : son `CLAUDE.md`, hors du bloc d'imports, ses réglages, ses
  journaux, sa mémoire, ses dossiers de travail.

**Fin** : `python3 ~/.claude/engine/verifier.py mise-a-jour --version <V>` rend `0`.

## 1. Avant

- **Une clôture faite.**
  - En GitHub, `git -C ~/.claude status --porcelain` est vide ; sinon, clôture d'abord.
  - Sans git, la dernière séance s'est close par « on arrête ».
- **Toutes les autres sessions fermées.**
- **La version visée.**
  - **GitHub** : `git -C ~/.claude fetch upstream --tags`, puis
    `git -C ~/.claude tag -l 'v*' --sort=-v:refname`. La plus haute, sauf si elle en nomme une autre.
  - **Sans git** : elle extrait l'archive de la version dans une amorce neuve, `~/claudeos-amorce`,
    et la version se lit dans son `engine/VERSION`. Ce fichier doit être à
    `~/claudeos-amorce/engine/VERSION`, et non dans un sous-dossier que l'archive aurait créé.
    **Si `~/claudeos-amorce` existe déjà**, renomme-le d'abord :
    `mv ~/claudeos-amorce ~/claudeos-amorce-<sa version>`. Extraite par-dessus, l'archive y
    laisserait les fichiers que la version retire, et ils passeraient pour livrés.

## 2. Appliquer la version

### En GitHub

1. **L'ascendance, une seule fois.** Le dépôt venu du bouton n'a aucun ancêtre commun avec le
   template. Fusionné sans elle, chaque fichier que la version change sortirait en conflit, ceux
   qu'elle n'a jamais touchés compris. La version installée se lit dans `~/.claude/engine/VERSION`.
   Si `git -C ~/.claude merge-base --is-ancestor v<installée> HEAD` rend `1`, pose son étiquette
   comme ancêtre, sans changer aucun fichier :

   ```bash
   git -C ~/.claude merge -s ours --allow-unrelated-histories --no-edit \
     -m "ClaudeOS : ascendance du template v<installée>" v<installée>
   ```

   Contrôle : `git -C ~/.claude diff --stat HEAD~1 HEAD` ne rend rien. Si `merge-base --is-ancestor`
   rend `0`, l'ascendance est déjà posée : passe au geste 2.
2. **La version** :

   ```bash
   git -C ~/.claude merge v<visée>
   ```

- **Un conflit ne porte que sur un fichier qu'elle a touché.** Résous-le avec elle, fichier par
  fichier, les deux versions montrées. Ne prends jamais la version neuve en bloc.
- **Un conflit sur un fichier du template** est une retouche locale, par exemple un correctif WSL.
  Montre-la, et propose de la signaler au dépôt du template.
- **Des conflits sur des fichiers qu'elle n'a jamais touchés** sont un défaut de la version. Arrête la
  fusion par `git -C ~/.claude merge --abort`, et dis-le.

### Sans git

Le script se lance **depuis l'amorce neuve** : c'est la version qui arrive qui décide de ce qu'elle
remplace. Lancé depuis `~/.claude`, il refuse.

1. **L'inventaire**, en lecture seule :

   ```bash
   python3 ~/claudeos-amorce/engine/mettre-a-jour.py ~/.claude ~/claudeos-amorce
   ```

   Il compare trois états : l'état livré de la version en place (`~/.claude/.claudeos/livre/`, avec
   la copie de l'arbre livré), les fichiers de la version neuve, et le disque. Chaque fichier que
   l'une des deux versions livre se classe :
   - **remplacé** : intact chez elle, changé par la version ;
   - **ajouté** : neuf ;
   - **retiré** : retiré par la version, intact chez elle ;
   - **gardé** : changé chez elle, et que la version ne touche pas. Il reste tel quel, sans question ;
   - **à trancher** : changé chez elle ET par la version. Il a été modifié, supprimé, créé à un
     chemin que la version livre désormais, ou modifié alors que la version le retire.

   Relaie-lui le compte.
2. **Chaque fichier à trancher, un par un.**

   ```bash
   python3 ~/claudeos-amorce/engine/mettre-a-jour.py ~/.claude ~/claudeos-amorce --montrer <chemin>
   ```

   - Montre-lui ce qu'elle a changé et ce que la version change, puis demande par `AskUserQuestion` :
     garder le sien, prendre le neuf, ou fusionner.
   - Quand le script propose une fusion, les deux changements ne se touchent pas. Mets-la dans le
     `preview` de l'option.
   - Sans proposition, compose la fusion à partir des trois versions qu'il a écrites sous
     `~/.claude/.claudeos/mise-a-jour/trois/`. Écris-la à côté d'elles, `<chemin>.fusion`, et
     fais-la valider de même.

   Puis enregistre sa réponse :

   ```bash
   python3 ~/claudeos-amorce/engine/mettre-a-jour.py ~/.claude ~/claudeos-amorce --trancher <chemin> garder|neuf|fusion
   ```

   - Ajoute `--texte <le fichier .fusion>` pour une fusion composée à la main.
   - `neuf` fait ce que fait la version : remplacer, reprendre un fichier qu'elle a supprimé, ou
     retirer.
   - Une réponse vaut pour l'état qu'elle a vu. Si le fichier change ensuite, la question se repose.
3. **Appliquer, tout ou rien** :

   ```bash
   python3 ~/claudeos-amorce/engine/mettre-a-jour.py ~/.claude ~/claudeos-amorce --appliquer
   ```

   - Il refuse tant qu'un fichier reste à trancher, et n'écrit alors rien.
   - Sinon il écrit la version, puis l'état livré de la version neuve. Ce dernier comprend `GARDES` :
     les fichiers qu'elle a gardés différents, que le vérificateur accepte désormais.
   - Une coupure se rattrape en relançant la même commande.

## 3. Après, dans les deux régimes

1. **Les réglages** : `python3 ~/.claude/engine/fusionner-reglages.py`. Une version peut changer un
   crochet du moteur ; les tiens restent.
2. **Le proxy, redétecté** : `PROXY` est un fait du poste.
   - Si `command -v rtk` ne dit plus ce que porte `reglages/REPONSES`, réécris la seule ligne
     `PROXY`.
   - Si `rtk` est apparu et que `~/.claude/RTK.md` manque, lance `rtk init -g`. Retire ensuite la
     ligne `@RTK.md` qu'il aurait ajoutée hors du bloc d'imports.
3. **Une clé neuve** : si `engine/config/REPONSES_CLES` nomme une clé que `reglages/REPONSES` n'a pas,
   pose sa question, celle d'`ENTRETIEN.md`. Elle ne prend jamais « non » par défaut.
4. **Les réponses et les emprunts, appliqués** :

   ```bash
   python3 ~/.claude/engine/appliquer-reponses.py
   bash ~/.claude/engine/skills-amont.sh
   ```

   - Un fragment neuf entre au bloc d'imports.
   - Un commit épinglé neuf recompose son emprunt.
   - Relaie les deux comptes rendus.
5. **Le poste** : `bash ~/.claude/engine/install-poste.sh`.
6. **Fin** : `python3 ~/.claude/engine/verifier.py mise-a-jour --version <V>` rend `0`. Puis la
   clôture sauvegarde la mise à jour (`INSTALLER.md`, I8, geste 1). En GitHub, demande avant de
   pousser.
7. **Sans git, l'amorce** : propose de supprimer `~/claudeos-amorce`, et l'ancienne si tu l'as
   renommée. Ne le fais qu'après confirmation. L'état livré porte désormais la copie de la version.
