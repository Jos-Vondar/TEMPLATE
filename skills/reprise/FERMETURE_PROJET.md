# Fermer une session de projet en fin de clôture

> Annexe de `reprise`, lue en entier avant le dernier appel d'outil d'une clôture de projet. Le
> crochet `rappel-fichiers-nommage.sh` refuse une fois toute fermeture de session tant qu'elle
> n'est pas lue.

**Session de PROJET : la clôture finit en fermant sa session.** Deux conditions :
`CLAUDEOS_SESSION_SCOPE` vaut `projet`, et chaque geste précédent de la clôture a réussi — sur un
échec, la session reste ouverte pour qu'on le voie. **La principale ne se ferme jamais.**

Écrire d'abord le message de fin, puis lancer, en dernier appel d'outil et seul dans son appel Bash :

    bash ~/.claude/engine/fermer-projet.sh

Le script ferme la session tmux après 5 s, le temps que le message s'affiche ; hors tmux, il la
laisse ouverte et le dit, et hors d'une session de projet il refuse. **Fin** : cet appel est le
dernier de la séance, et rien ne s'écrit après lui.
