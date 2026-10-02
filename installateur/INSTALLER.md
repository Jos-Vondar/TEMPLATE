# Installer — d'un poste sans ClaudeOS à un système qui est le sien

Procédure de l'agent, mode `installer` (`LANCEMENT.md`). Neuf phases, I0 à I8 ; la personne a déjà
fait I0 et I1. **Chaque phase se clôt sur son vérificateur, et tu ne passes pas à la suivante sans
lui.** Ses bornes, ses questions et ses confirmations sont celles de `LANCEMENT.md`.

Jusqu'à la plomberie, les scripts se lancent depuis l'amorce, `~/claudeos-amorce` : `python3
engine/verifier.py …`. **À partir d'I5, toujours ceux de `~/.claude/engine/`**, que la plomberie vient
de poser.

## I1 — Le départ

`verifier.py mode` a rendu `installer`. Trois cas, à trancher avant la première écriture :

- **Une reprise** : le motif dit « une V3 posée mais inachevée ». Reprends à la première phase dont le
  vérificateur échoue, dans l'ordre : `plomberie`, `entretien`, `arrivee`. La lecture obligée ne se
  rejoue pas si `~/.claude/reglages/ACCUEIL` porte une date.
- **Une machine de plus** : l'amorce est un clone de son dépôt, et ce dépôt porte déjà ses réponses —
  `git -C ~/claudeos-amorce ls-tree -r --name-only HEAD -- reglages/REPONSES` rend une ligne. Suis
  alors la section « Machine de plus », en bas : aucune question n'est reposée.
- **Une installation neuve**, sinon.

`~/.claude` déjà dépôt git : la trace le dit. Ne pose rien, demande ce qu'il porte et ce qu'elle veut
en faire.

## I2 — La lecture obligée

`installateur/ACCUEIL.md`, en entier, ses cinq points et ses cinq questions. Rien ne s'installe avant.

## I3 — Les prérequis

`python3 engine/verifier.py prerequis`. Pour chaque ⛔, donne la commande qui installe ce qui manque,
adaptée à la plateforme que le vérificateur a lue. C'est la personne qui la lance.

- **macOS** : Homebrew, `brew install git gh tmux python`. Sans Homebrew, renvoie à sa documentation
  officielle, sans la recopier.
- **WSL** : `sudo apt install git tmux python3`. Pour `gh`, renvoie à sa documentation officielle,
  dont le dépôt apt est à part.
- **Partout** : Claude Code se met à jour par `claude update`. `gh auth login` est interactif, et la
  personne le lance elle-même.
- **M-V2-DETECTEE** : une V1 ou une V2 habite `~/.claude`. Rien ne s'installe par-dessus : dis le
  message tel quel, puis passe à `MIGRER.md`, qui la met d'abord en quarantaine.

Relance le vérificateur jusqu'à `0`. Un ⚠ se dit et ne bloque pas.

## I4 — Le régime

Dis **M-REGIME** par `AskUserQuestion` : une question, trois options. Les labels sont les noms ; la
description de chacune porte son texte, mot pour mot.

- **Un dépôt par domaine** (le défaut) : « `~/.claude` et chaque domaine sont des dépôts GitHub
  privés ; tout est sauvegardé à chaque clôture, et un second poste est possible. »
- **Un dépôt unique** : « tout va dans le dépôt privé de `~/.claude`. »
- **Sans git, tout local** : « rien ne sort de ce poste. Le prix : un seul poste, aucun historique
  ni retour arrière, et si ce poste est perdu, tout est perdu. Passer ensuite de sans git à GitHub
  n'est pas prévu dans cette version. »

Pour un régime GitHub, `python3 engine/verifier.py prerequis --regime github` doit rendre `0`.
Si l'amorce est une archive et non un clone, il faut d'abord un dépôt privé. Crée-le, après
confirmation : `gh repo create <nom> --private --template <dépôt du template>`, où le dépôt du
template se lit dans `engine/config/TEMPLATE_ORIGINE`.

## I5 — La plomberie

`~/.claude` devient le système **en place**. Ce que Claude Code y range reste où il est. Fais les gestes
dans cet ordre : chacun suppose le précédent.

1. **Le `CLAUDE.md` d'avant.** S'il existe, copie-le hors du système avant tout autre geste :

   ```bash
   T=$(date +%Y%m%d-%H%M%S); mkdir -p ~/.claude-avant-claudeos/$T && cp -p ~/.claude/CLAUDE.md ~/.claude-avant-claudeos/$T/
   ```

   Puis dis **M-CLAUDE-PREEXISTANT**, avec le chemin réel : « Un `CLAUDE.md` existait avant
   ClaudeOS. Je l'ai copié dans `<chemin>`, hors du système. L'entretien te proposera ses règles,
   une à une, pour ta section « Mes règles ». »
2. **Le proxy.** `PROXY` est un fait du poste, pas une question : il vaut `oui` si `command -v rtk`
   trouve l'outil, `non` sinon. Quand il vaut `oui` et que `~/.claude/RTK.md` manque, lance
   `rtk init -g`. Ce geste vient après la copie du `CLAUDE.md` d'avant : il y ajouterait sa ligne.
3. **L'arbre du template.**
   - **GitHub.** L'URL est celle de l'amorce, `git -C ~/claudeos-amorce remote get-url origin`, ou
     celle du dépôt créé en I4.
     - Contrôle d'abord qu'il est privé : `gh repo view <URL> --json visibility --jq .visibility`
       doit rendre `PRIVATE`.
     - Sinon, dis **M-DEPOT-PUBLIC** et arrête-toi : « Ton dépôt <URL> est PUBLIC. ClaudeOS y
       poussera ton journal, ta mémoire et ton persona : il doit être privé. Passe-le en privé dans
       ses réglages sur GitHub, puis relance l'agent. Rien n'a été écrit. »
     - Puis pose l'arbre :

       ```bash
       git -C ~/.claude init -b main
       git -C ~/.claude remote add origin <URL>
       git -C ~/.claude fetch origin
       git -C ~/.claude checkout -B main origin/main
       git -C ~/.claude remote add upstream "$(cat ~/.claude/engine/config/TEMPLATE_ORIGINE)"
       ```

       Le `checkout` refuse d'écraser un fichier non suivi : c'est voulu, ne le force jamais. Les
       fichiers qu'il nomme sont à la personne. Demande-lui de les ranger dans
       `~/.claude-avant-claudeos/$T/`, puis relance-le.
     - `git -C ~/.claude status --porcelain` ne doit lister aucun dossier de l'outil.
   - **Sans git.**

     ```bash
     python3 ~/claudeos-amorce/engine/regime.py pose ~/.claude ~/claudeos-amorce
     ```

     Il copie l'arbre livré et écrit l'état livré sous `~/.claude/.claudeos/livre/`. Un fichier en
     place qui diffère de sa version livrée est un conflit : `pose` les nomme tous et n'écrit rien.
     Même issue que pour le `checkout`.
4. **Les premières réponses**, une ligne chacune, rien d'autre : `GIT`, choisi en I4, et `PROXY`.

   ```bash
   mkdir -p ~/.claude/reglages && printf 'GIT=%s\nPROXY=%s\n' <régime> <oui|non> > ~/.claude/reglages/REPONSES
   ```

   En régime GitHub, ajoute la souche d'identité :
   `cp -n ~/.claude/gabarits/IDENTITE_GIT ~/.claude/reglages/IDENTITE_GIT`. L'entretien la remplit.
5. **Le règlement** : `cp ~/.claude/gabarits/CLAUDE.md ~/.claude/CLAUDE.md`. Ce fichier est désormais
   à la personne ; seul son bloc d'imports s'écrit par script, à l'entretien.
6. **Les réglages** : `python3 ~/.claude/engine/fusionner-reglages.py`. Si `autoMemoryDirectory`
   vise déjà un autre dossier, rien n'est écrit. Expose l'écart et demande-lui : sa mémoire
   automatique vivra-t-elle sous `~/.claude/memory` ?
7. **Le poste** : `bash ~/.claude/engine/install-poste.sh`. Lis chaque ligne qu'il rend. Sans git, il
   marque la racine et pose la référence de départ des empreintes : il vient donc après les gestes
   qui écrivent l'état livré.
   - S'il dit que le shell ne lance pas le démarrage de ClaudeOS, donne-lui la ligne à ajouter, à
     `~/.zshrc` sous macOS ou à `~/.bashrc` sous WSL :
     `[ -f ~/.claude/engine/claudeos-boot.sh ] && . ~/.claude/engine/claudeos-boot.sh`.
   - C'est un fichier du poste, donc c'est elle qui l'écrit.
8. **La lecture obligée, datée** : `date +%F > ~/.claude/reglages/ACCUEIL`.

**Fin** : `python3 ~/.claude/engine/verifier.py plomberie` rend `0`.

## I6 — L'entretien

`installateur/ENTRETIEN.md`, en mode installation : le régime est connu depuis I4, `PROXY` est posé.

**Fin** : `python3 ~/.claude/engine/verifier.py entretien` rend `0`.

## I7 — Le premier domaine

Demande ce que l'étape 1 de `nouveau-domaine` demande, par « Autre », dans tous les régimes :
le nom de son premier domaine — un client, un pan de travail, un projet personnel —, ce qu'il couvre
en une phrase, et le nom de son premier projet. Suis ensuite `~/.claude/skills/nouveau-domaine/SKILL.md`, que tu lis en entier : cette
session a démarré avant que la compétence existe.

- En dépôt par domaine, elle crée un dépôt GitHub privé, après confirmation.
- En dépôt unique et sans git, elle crée `~/.claude/travail/<NOM>/`.
- Quand `MULTIDOMAINE=oui`, elle ajoute la ligne du domaine à « Mes domaines », dont l'entretien a
  retiré la ligne « à remplir ».

**Fin** : le dossier sort de `bash -c 'source ~/.claude/engine/config.sh; claudeos_ws_roots'`.

## I8 — La répétition

La personne joue une vraie fin de séance, puis une vraie reprise. C'est la dernière leçon, et elle
se fait en vrai.

1. **« On arrête »** : demande-le-lui, puis joue la clôture, dans l'ordre de la compétence `reprise` :
   - un événement `seance` au niveau `~/.claude` :

     ```bash
     python3 ~/.claude/engine/etat.py add --niveau ~/.claude --type seance \
       --manque-reprise 0 --manque-declencheur 0 --texte "…"
     ```

     Le texte dit l'installation en clair, et ce qui reste à faire.
   - `python3 ~/.claude/engine/etat.py projette --niveau ~/.claude` ;
   - `bash ~/.claude/engine/claudeos-cloture.sh`. En GitHub, la clôture pousse : demande d'abord, en
     disant ce qui part, c'est-à-dire les dépôts privés de `claudeos_repos`. Sans git, elle contrôle et
     dit que rien n'est sorti. Lis ce qu'elle rend : une alarme qui mord arrête tout.
2. **« Reprise »** : montre ce que fera sa prochaine session. Relis `~/.claude/ETAT.md` et rends l'état
   du système en trois lignes, comme le démarrage le lui demandera chaque matin.
3. **Les astuces** restent : le fragment les a posées dans `settings.json`. Chacune revient de
   plus en plus rarement, à son rythme ; les retirer, c'est ôter `spinnerTipsOverride` de
   `settings.json`.
4. **L'amorce** : propose de supprimer `~/claudeos-amorce`, et ne le fais qu'après confirmation. En
   GitHub, son dépôt garde tout. Sans git, l'état livré, sous `~/.claude/.claudeos/livre/`, garde la
   copie de la version : une version suivante arrivera dans une amorce neuve, et
   `METTRE_A_JOUR.md` la comparera à cette copie.

**Fin** : `python3 ~/.claude/engine/verifier.py arrivee` rend `0`. Dis alors **M-FIN-INSTALL** :
« ClaudeOS est installé, et réglé par toi. Ouvre ta session principale par `cd ~/.claude && claude`,
et un projet par `bash ~/.claude/engine/claudeos-session.sh <projet>`. « On arrête » clôture et
sauvegarde ; `/claudeos-onboarding` rejoue l'entretien quand ta situation change. Ferme cette
session : la suivante chargera ton règlement. »

Si le vérificateur rend `1`, ne dis pas « installé ». Nomme le fait d'arrivée qui manque, et reprends
à la phase qui le porte.

## Machine de plus — régime GitHub seulement

Le dépôt porte déjà les réponses de la personne : on relie ce poste à son système, sans rien reposer.
Deux réponses aux mêmes questions, à deux âges, se contrediraient. Sans git, ce mode n'existe pas,
avec le motif de **M-REGIME** : rien ne synchronise deux postes sans dépôt.

1. **I2** se saute : la lecture a été faite sur le premier poste, et `reglages/ACCUEIL` est dans le dépôt.
   **I3** se joue avec `--regime github`, et **I4** se saute : le régime est dans `reglages/REPONSES`.
2. **I5**, avec trois écarts :
   - au geste 1, le `CLAUDE.md` d'avant, une fois copié, se retire de `~/.claude`, après confirmation :
     sinon le `checkout` refuse de poser le sien ;
   - les gestes 4 et 5 se sautent : les réponses et le `CLAUDE.md` viennent du dépôt ;
   - au geste 2, si le dépôt dit `PROXY=oui` et que `rtk` manque sur ce poste, dis-le : ses réponses
     sont partagées, l'outil non. La règle d'import vise alors un outil absent.
3. **Les dossiers de travail.**
   - En dépôt par domaine, liste ses dépôts : `gh repo list --json name --jq '.[].name'`. Retiens
     ceux dont le nom porte un préfixe de `PREFIXES` et propose de les cloner sous `~/<NOM>`, la
     liste confirmée d'un bloc.
   - En dépôt unique, `~/.claude/travail/` est venu avec le dépôt.
4. **Les compétences optionnelles** : `bash ~/.claude/engine/skills-amont.sh` refait le cache des
   emprunts, qui ne voyage pas.

**Fin** : `verifier.py plomberie`, puis `verifier.py arrivee`, à `0` tous les deux. Puis **M-FIN-INSTALL**.
