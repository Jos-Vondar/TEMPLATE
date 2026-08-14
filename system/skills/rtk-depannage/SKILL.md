---
name: rtk-depannage
description: Une commande passée par le proxy économe échoue, rend un résultat de travers, `rtk` est introuvable, ou l'on veut mesurer ses gains.
---

# Le proxy économe en jetons (rtk) — mesure et dépannage

> Fiche situationnelle. Déclencheur : une commande passée par le proxy échoue, se comporte de travers, `rtk` semble absent alors qu'il devrait être là, ou l'on veut mesurer ce que le proxy fait gagner.

## Ce qu'il est, et les commandes de mesure

Rust Token Killer. Il économise 60 à 90 % des jetons sur les opérations de développement, et le déclencheur d'avant-appel réécrit pour moi les commandes prises en charge (`git status` → `rtk git status`) : rien à retenir en travail courant.

Les commandes de mesure s'appellent toujours **directement**, le proxy ne les réécrit pas : `rtk gain` (gains mesurés), `rtk gain --history` (historique d'usage), `rtk discover` (occasions manquées, d'après l'historique de session). Rappel de la carte complète : ces compteurs sont propres à la machine courante et hors sauvegarde — un chiffre lu ici ne dit rien de l'autre poste.
> En travail courant il n'y a rien à savoir : le déclencheur d'avant-appel réécrit les commandes prises en charge, sans coût. Cette fiche ne sert qu'au moment où ça casse.

## Mettre à jour — et le piège qui va avec

```bash
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
rtk init -g      # remet le déclencheur à jour
```

**`rtk init -g` ÉCRASE `~/.claude/RTK.md`** par la version que l'outil livre — la version longue de l'outil, en anglais.

**Décision : on garde la version de l'outil.** Elle porte deux rappels que la nôtre n'avait pas — la collision de nom et les commandes de vérification d'installation — et le plafond absolu de la couche par session a été retiré, donc l'écart de poids ne bloque plus rien. **Il n'y a donc plus rien à restaurer après une montée de version** : laisser `rtk init -g` faire son travail.

Ce qu'il faut quand même faire après toute montée :

```bash
bash ~/.claudeos/engine/selftest.sh | grep -i couche   # la dérive 7 j reste surveillée
```

Redémarrer Claude Code ensuite : le déclencheur ne reprend qu'au lancement suivant.

**Ce que cette décision a remplacé, pour ne pas le rejouer.** La consigne précédente était l'inverse — restaurer une version courte maison après chaque montée. Motif d'alors : lors d'une montée de version, la reprise du fichier livré avait fait passer la couche toujours-chargée **au-dessus de son seuil**, et l'alarme de poids l'avait signalé dans la minute. Le motif est tombé avec le seuil, pas avec le fait : le fichier livré est toujours cinq fois plus lourd, et c'est une dépense assumée.

## Vérifier l'installation

```bash
rtk --version   # doit afficher : rtk X.Y.Z
rtk gain        # doit fonctionner, et non « command not found »
which rtk       # confirmer que c'est le bon binaire
```

## Collision de nom, la panne la plus trompeuse

Si `rtk gain` échoue alors que `rtk --version` répond, c'est probablement **un autre outil du même nom** qui est installé. L'outil voulu est **Rust Token Killer**. L'homonyme est **Rust Type Kit**, dépôt `reachingforthejack/rtk`, qui ne connaît pas la commande de gains. Le symptôme ressemble à une installation cassée alors que le binaire est simplement le mauvais. Contrôler avec `which rtk` avant toute réinstallation.

## Contourner le proxy pour un diagnostic

`rtk proxy <commande>` exécute la commande brute, sans filtrage. Utile pour savoir si un comportement inattendu vient du proxy ou de la commande elle-même.

## Liste complète des commandes prises en charge

`rtk --help`. Ne jamais la recopier dans un document : elle change avec l'outil.

## Défaut connu, mesuré

Le proxy corrompt les redirections et les séparateurs du terminal, mais la fréquence est marginale — trois incidents sur 693 commandes sur une fenêtre de treize jours, constat corrigé après une première estimation trop alarmante. Ne pas en faire un motif de désactivation sans nouvelle mesure.

## Second défaut, plus grave : une liste rendue tronquée sans le dire

**Ne jamais établir un inventaire à travers le proxy.** Il condense les sorties de liste et n'annonce pas qu'il l'a fait : la sortie paraît complète et il en manque la moitié. Mesuré sur l'énumération des fichiers modifiés dans une journée de dépôt — 70 fichiers par l'exécutable direct, 35 par la même commande passée par le proxy.

Conséquence, qui est le motif de cette entrée : toute conclusion tirée d'une telle sortie est fausse en silence, et c'est l'absence qu'elle fabrique le plus volontiers. Le cas rencontré était une conclusion d'absence — « ce script n'a pas été modifié aujourd'hui » — tirée d'une liste amputée, alors qu'il l'avait été. C'est le mode de défaillance que le règlement interdit déjà de façon générale : une sortie tronquée n'est pas une preuve d'absence, et une recherche ne conclut rien tant qu'on n'a pas varié le motif.

Conduite à tenir, dès que la sortie d'une commande **est** la donnée et non un résumé pour l'œil — énumérer des fichiers, compter des occurrences, vérifier qu'une chose est absente, comparer deux états :

```bash
/usr/bin/git ...        # l'exécutable par son chemin, non réécrit
rtk proxy <commande>    # ou le contournement explicite du proxy
```

Le confort du proxy vaut pour la lecture courante. Il ne vaut pas pour un contrôle dont le verdict dépend de l'exhaustivité de la sortie.
