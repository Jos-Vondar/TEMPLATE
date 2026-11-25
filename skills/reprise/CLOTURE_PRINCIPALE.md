# Clôture de la session principale — la sauvegarde

> Annexe de `reprise`, lue en entier avant de lancer `claudeos-cloture.sh`. Le crochet
> `rappel-fichiers-nommage.sh` refuse une fois le lancement tant qu'elle n'est pas lue.

**La commande** — `bash ~/.claude/engine/claudeos-cloture.sh`. Il projette chaque niveau à
événements, contrôle le rangement des secrets, puis, en régime GitHub, committe et pousse **tous les
dépôts** de `claudeos_repos`. Lire ce qu'il dit : une alarme qui mord arrête tout, et le dépôt
système n'est alors pas sauvegardé. *(Il refuse de tourner si un shim de crochet manque — un shim
absent est muet, le dépôt committerait sans aucune alarme. `bash ~/.claude/engine/install-poste.sh`
les repose.)*

**En `GIT=aucun`, rien ne sort du poste** : la clôture contrôle les fichiers changés depuis la
précédente, réécrit les empreintes de `.claudeos/` si les contrôles passent, et le dit — « RIEN N'EST
SORTI DU POSTE ». Un refus n'y réécrit rien, et son levier `FORCE_…` se pose sur la clôture.

**En régime GitHub, si la séance a touché `engine/`, `CLAUDE.md` ou une compétence du système**,
préfixer la commande : `CLAUDEOS_NATURE="incident: <motif>"` pour une réparation,
`CLAUDEOS_NATURE="chantier: d-<ref> <motif>"` pour un chantier que tranche la décision `d-<ref>` du
journal de `~/.claude`. Sans variable, le commit compte comme chantier et remet à zéro le compteur
de croisière du démarrage ; un incident qui ajoute au moteur plus que `CLAUDEOS_INCIDENT_SOLDE_MAX`
(1 024 octets par défaut) compte aussi comme chantier, et la clôture le dit.

## Avant de la lancer : constater où en sont les sessions ouvertes

`claudeos-session.sh --list` les nomme. La sauvegarde committe l'arbre **tel qu'il est à cet
instant** : lancée pendant qu'une session écrit, elle capte certains de ses fichiers dans leur état
final et d'autres dans un état intermédiaire — deux fichiers du même commit se contredisent, **la
version alarmante étant la fausse**. **Aucun contrôle mécanique n'est à armer pour ça** : c'est un
constat, pas un garde.

Demander à chacune si elle a fini d'écrire, par un message (compétence `session`, § Parler
directement à une autre session), et attendre la réponse.

**`git status` dit qui a écrit, et c'est plus sûr que la question** — sans git,
`python3 ~/.claude/engine/regime.py changes ~/.claude`. Le lot nomme les fichiers modifiés depuis le
dernier commit, ou la dernière clôture, donc les sessions qui ont travaillé. Si le lot ne contient
que les fichiers d'une session qui a confirmé avoir fini, **le risque est nul quel que soit le nombre
de sessions ouvertes**. La question reste utile pour ce qui n'a pas encore touché le disque.

**À trois sessions ou plus, ne pas attendre que TOUTES aient fini — ça peut ne jamais converger.**
Le lot de chacune est propre à un instant ; le lot global ne l'est peut-être jamais. Pousser dès
que celles qui ont des fichiers dans le lot ont répondu, et accepter qu'une session qui reprend
ensuite fournira un second lot.

**Commencer par les fichiers de STATUT, pas par le code** : un fichier de statut est réécrit
**après** le geste qu'il décrit, donc il se stabilise en dernier — donc c'est lui qui mentira.

**La garde réduit le risque, elle ne l'annule pas** : l'état du dépôt se lit AVANT de lancer le
script, qui met ensuite une dizaine de secondes. Après un commit, relire l'état — un fichier qui
redevient modifié aussitôt signale une session encore active. **Et si la coupure a déjà eu lieu** :
recommitter, mais contrôler d'abord fichier par fichier ce qui diffère du dépôt ; une session qui
rapporte « seul tel fichier est à recommitter » se recontrôle, comme tout rapport de vérification.

## Ensuite, en régime GitHub, toujours avant de la lancer : mesurer le retard de chaque dépôt

`git -C <dépôt> fetch`, puis `git -C <dépôt> status -sb`. Un dépôt en retard : montrer à
l'utilisateur ce qui arrive (`git -C <dépôt> log --oneline HEAD..@{u}` et
`git -C <dépôt> diff --stat HEAD...@{u}`) avant la sauvegarde. Un simple `git pull` échoue ici :
l'arbre est modifié par construction, le geste 1 vient d'écrire le journal. `git -C <dépôt> merge
--ff-only @{u}` n'avance que si aucun fichier modifié ici ne l'est aussi là-bas — le journal du mois
l'est presque toujours. Si git refuse : s'arrêter, montrer la sortie, et l'utilisateur tranche entre
laisser `claudeos-cloture.sh` committer puis intégrer le distant (les journaux fusionnent par
`merge=union`, posé par `install-poste.sh` ; tout autre conflit s'annule et l'arrête, code 8) et
remiser à la main.

## Le verdict

**La sauvegarde est le dernier geste : elle clôt l'écriture.** Son verdict se lit par
`git -C <dépôt> log -1`, ou sans git par la sortie de la clôture ; il ne se recopie nulle part :
recopié dans la reprise, il fabrique un changement de plus, qui relance le crochet — deux commits et
deux batteries par clôture.
