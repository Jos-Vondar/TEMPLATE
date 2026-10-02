---
name: controles-et-alarmes
description: Écrire, modifier ou désarmer un contrôle mécanique ou une alarme, ou modifier un `.gitignore` (ajouter ou élargir une exclusion). Aussi devant un comportement d'outil inexpliqué ou une sortie invraisemblable.
---

# Règles — écrire ou modifier un contrôle mécanique ou une alarme, et diagnostiquer une sortie qui ne colle pas

> Fiche situationnelle. Se charge sur déclencheur, jamais par réflexe. Déclencheur : j'écris, je modifie ou je désarme un contrôle de plomberie, un signal de démarrage, une alarme, ou tout code dont la fonction est de détecter un défaut plutôt que de produire un résultat. Deuxième famille : je diagnostique un comportement d'outil que la configuration n'explique pas, une sortie invraisemblable, ou je lance une commande qui peut atteindre deux installations.
> Motif d'existence de cette fiche : les règles ci-dessous portent sur du code, et sur des sorties de code, dont la seule fonction est de dire la vérité sur le système. Un défaut y est plus coûteux qu'ailleurs, parce qu'il ne se manifeste pas — il se tait.

## D'ABORD : ne pas ajouter de contrôle

**Un contrôle de plus se paie sur toutes les sessions.** Écrire un contrôle mécanique de plus se paie sur **toutes** les sessions, pas seulement sur celles qu'il protège : la plomberie tourne à chaque sauvegarde, donc à chaque fin de séance. Devant un défaut qu'un contrôle attraperait, l'ordre est celui-ci :

1. **Une règle écrite** dans la fiche dont le déclencheur est le moment du danger — c'est presque toujours la bonne réponse, et elle coûte zéro par session.
2. **Un chemin ajouté à un contrôle existant** — ce n'en est pas un neuf.
3. **Un contrôle neuf** : seulement sur un fait nouveau, et en le faisant trancher par l'utilisateur.

*(Cet interdit vit ici, la fiche qui agit, et pas dans `os-audit`, la fiche qui constate : une règle placée sur un déclencheur qui n'est pas le moment du danger ne tire jamais.)*

## Diagnostiquer avant d'agir

Ces règles se déclenchent sur un moment observable : elles sont la première chose à lire quand une sortie ne colle pas.

- **Changer d'objet observé plutôt que raisonner une troisième fois.** Deux raisonnements sourcés qui se contredisent signalent une prémisse manquante ; une tâche ambiguë sur l'intention s'arrête et se demande, elle ne se devine pas. Une capture, ou le rendu ouvert, tranche en secondes ce que la lecture du source ne tranche pas : **le défaut peut être une valeur ABSENTE, invisible au texte**. Les changements d'objet qui paient : de la formule au rendu, de la fiche au code qu'elle décrit, du document à la sortie du garde qu'il prétend décrire.
- **Les réglages de l'outil comptent parmi les objets à regarder** : devant une demande de configuration, ils disent souvent le besoin mieux que la demande elle-même.
- **Une instruction peut venir de l'outil sans figurer dans la configuration.** Devant un comportement que les fichiers n'expliquent pas, envisager l'outil plutôt que de les déclarer faux — fait instable, propre au poste.
- **Quand une commande peut atteindre deux installations, sonder la cible en lecture seule avant d'agir** : un message de succès ne dit pas laquelle a été touchée.

## Un contrôle neuf n'est pas vérifié tant qu'il n'a pas échoué exprès

**Tout contrôle nouvellement écrit s'exerce sur son cas positif avant d'être cru** : introduire volontairement le défaut qu'il cherche, et constater qu'il crie. Un contrôle qui n'a jamais crié ne prouve rien, il peut ne regarder rien. Le cas négatif — tout va bien, le contrôle est vert — ne distingue pas un contrôle qui fonctionne d'un contrôle muet.

Le test se fait sur les données réelles ou sur une copie exacte, jamais sur une reformulation privée de la garde : reproduire la logique à côté pour la tester valide la reproduction, pas le contrôle en place.

**Et « à côté » inclut le shell interactif, même avec le code recopié à l'identique.** Dans le shell de l'outil, `grep` peut être une fonction ou un alias — un `ugrep`, qui tolère ce que GNU grep refuse : un garde neuf combinait `-E` et `-P`, **drapeaux exclusifs** — GNU grep répond « conflicting matchers specified » et rend `rc=2`, que le `2>/dev/null` du garde convertissait en « rien trouvé ». Testé à la main il passait ; posé dans le script il était **muet**, le défaut même qu'il traquait. Deux gestes opposables : lancer le garde **par son script**, et ne pas rediriger l'erreur d'un test dont on lit le code retour. Quand le cas positif est inapplicable au moment de l'écriture — aucun défaut présent à mettre en scène — le dire dans la sortie du contrôle plutôt que de laisser croire qu'il a été exercé.

### Un garde-fou mesure le CODE, pas les commentaires

**Une recherche de motif lancée sur tout un fichier tombe sur la prose qui explique ce motif** — donc
le contrôle rend un faux positif sur le code même qu'il est censé exercer. Un garde-fou se borne à ce
qu'il garde : retirer les commentaires avant de mesurer, ou ancrer le motif sur ce que seul le code
porte.

### Et le témoin positif se PREND dans les données, il ne se fabrique pas

**Tout contrôle qui conclut d'une absence porte un témoin positif tiré des données réelles, joué dans le même geste. Sans lui, on ne distingue pas « rien à signaler » de « rien regardé ».** Un contrôle peut échouer de trois façons différentes et rendre la même chose — **rien** —, or « rien » se lit comme un succès. Le témoin se prend dans le corpus par un `sort -u`, jamais dans les hypothèses de celui qui écrit le motif : sinon il partage le défaut du contrôle et ne teste rien.

**Ce que ça ajoute à la règle du cas positif ci-dessus, et c'est l'argument pour l'écrire** : la règle a été respectée les trois fois et n'a rien attrapé, parce que le cas positif était construit par la même main que le motif. Le manque est précis, c'est la **provenance** du témoin.

**Trois occurrences le 2026-08-26 dans la même matinée**, chacune avec dégât mesuré, aucune trouvée par le système. **La plus instructive est INVERSÉE** : un contrôle cassé rendait par hasard la bonne réponse — indétectable par son résultat, démasqué par le seul témoin.

**Deux formes voisines, même symptôme, remèdes différents — ne pas les fondre :**

- **Contrôle circulaire sur soi.** Un contrôle de conformité qui lit le corpus doit **exclure le fichier en cours d'écriture**, ou être interrogé AVANT l'écriture ; sinon il compte l'écriture comme sa propre preuve. Mesuré avec dégât réel : 17 propriétés annoncées « prouvées au corpus », dont `Tooltip` — et son unique porteur était **sa propre ligne**, dans le fichier qu'il validait. Le compilateur l'a rejetée. Rejoué en s'excluant : 0 porteur ailleurs, les 16 autres en ont de 3 à 67.
- **Témoin dérivé du motif.** Le cas de test partage les hypothèses du contrôle qu'il teste — c'est le défaut des trois occurrences ci-dessus.

**Et la même chose vaut hors des contrôles, sur un composant ordinaire : un scénario qui réussit valide la SORTIE, jamais le mécanisme.** Tant que le cas qui doit faire échouer un composant n'a pas été joué, ce composant n'est pas éprouvé — et un premier succès rend l'épreuve moins probable, parce qu'il donne le sentiment que c'est fait. Mesuré le 2026-08-24 : un filtre bâti sur une recherche de sous-chaîne comparait un libellé qui est le **préfixe d'un autre** ; le premier scénario passait sur ses quatre critères sans rien dire du filtre.

*Réserve conservée : les trois occurrences tiennent dans une seule matinée et deux sont de moi ; c'est peut-être un motif de séance. Ce qui a emporté l'écriture : les trois ont un dégât mesuré — une conclusion fausse écrite dans une source de vérité, une propriété non compilable livrée, un état de dépôt lu à l'envers — et aucune n'a été trouvée par le système.*

## Une mesure comparative se change des deux côtés

Quand un contrôle compare deux états — une dérive, un différentiel, un avant/après —, son périmètre
se change **des deux côtés ou d'aucun**. Changer un seul côté transforme la mesure d'évolution en
mesure de périmètre : l'écart s'installe à demeure dans le résultat, et l'alarme se tait au lieu de
crier. Après avoir touché une mesure comparative, relire l'autre branche du calcul avant de fermer.

Motif, sur pièce : une mesure de dérive dont un seul côté du périmètre avait été corrigé annonçait
−1739 caractères pour −784 réels — faux négatif constant de 955 sur un seuil de 2 500, soit
38 % de la marge offerts en silence, contrôle vert.

## Un contrôle ne fait jamais porter une conclusion à une branche d'erreur

**Séparer « je n'ai pas pu regarder » de « il n'y a rien ».** Une commande qui échoue à analyser ses arguments rend un code de sortie non nul — indiscernable de celui que rend « l'objet est absent ». Tout contrôle de la forme `commande || conclusion` confond donc les deux, et rend un verdict positif sur une erreur d'exécution. Tester l'exécution d'abord, le résultat ensuite.

C'est le cran au-dessus de la borne du règlement (socle, « Recherche et preuve ») — une sortie vide n'autorise pas à conclure —, qui vise une commande ayant tourné.

Motif, sur pièce : une suppression qui n'avait pas eu lieu, annoncée comme faite.

## Un faux positif diagnostiqué se corrige dans la séance

**Un signal dont on établit en séance qu'il est un faux positif se corrige dans la même séance, ou l'on écrit pourquoi on ne le corrige pas.** Diagnostiquer sans corriger est le pire des trois états possibles : le signal continue de crier, on sait qu'il ne faut pas l'écouter, et on apprend à ignorer la catégorie entière — les vrais signaux compris. Le coût ne se paie pas sur le faux positif, il se paie sur le vrai qu'on manquera ensuite.

**Sous-règle appairée. Une alarme se construit sur l'état courant, jamais sur la trace d'un état passé.** Chercher un mot-clé dans une fenêtre de fin de fichier ne mesure pas un état, cela retrouve un souvenir : le signal survit alors à sa cause, mécaniquement, jusqu'à ce que le volume l'évacue. Faire porter tout verdict sur la dernière opération enregistrée, et savoir distinguer une opération terminée en échec d'une opération interrompue avant son terme.

## Un journal borgne fait mentir le contrôle qui le lit

**Un contrôle qui juge sur un journal n'est vérifié que si ce journal voit toutes les voies d'écriture de ce qu'il enregistre.** Recenser les chemins de sortie du producteur — appel par un hook, lancement à la main, appel depuis un autre script — et constater que chacun laisse sa trace. Un producteur qui n'en journalise qu'un rend le contrôle exact et son verdict faux, et c'est le contrôle qui paraît fautif.

Le geste qui tranche : faire produire l'événement par **chaque** voie, pas par la plus commode. C'est le cas positif de la section précédente étendu au producteur, et plus au seul contrôle.

*(Trois occurrences en une semaine.)*

## Deux pièges déjà payés, à ne pas repayer

- **Une boucle de lecture perd la dernière ligne d'un fichier sans retour à la ligne final.** C'est le rappel le plus récent, donc le seul actif, qui disparaît. Utiliser un outil qui la conserve, ou garder explicitement le reste de tampon. Coût constaté : 23 jours de silence complet.
- **Un seuil défini dans un script ne se recopie pas ailleurs** — application au cas des contrôles de la règle « un fait calculable ne s'écrit pas, il se lit », qui vit dans la compétence `memoire-et-verite` et n'est pas redite ici. Corollaire propre aux contrôles : quand un contrôle change un seuil, chercher qui le cite avant de conclure que c'est fini.

## Une exception vaut pour tous les gardes, pas pour le premier rencontré

**Avant de conclure qu'un chemin est mis en liste blanche, chercher tous les mécanismes qui le gardent.** Plusieurs contrôles indépendants surveillent souvent la même zone par des moyens différents — l'un filtre à la copie, l'autre inspecte ce qui part en file, un troisième lit le contenu. N'en traiter qu'un laisse le blocage entier tout en donnant le sentiment d'avoir agi, et le diagnostic repart de zéro à la tentative suivante.

Méthode : chercher le chemin, le format et le nom du garde dans **tout** le moteur, pas seulement dans le fichier de configuration évident. Une exception se pose ensuite partout d'un coup, chacune commentée par son motif, et se vérifie de bout en bout sur le geste réel — pas sur un essai en bac à sable, qui ne dit rien du chaînage.

## Retirer un garde et ce qu'il gardait dans le même geste laisse le geste sans témoin

**Quand un geste retire un contrôle, tout ce que ce contrôle mesurait s'exerce À LA MAIN avant de
clore le geste.** Sinon le geste s'auto-valide : le seul mécanisme qui aurait vu son défaut vient
d'être supprimé par lui. **Et `bash -n` ne remplace rien** — il voit la syntaxe, pas un bloc avalé
ni un contenu manquant ; un fichier amputé de moitié reste syntaxiquement valide.

*2026-09-08 : en retirant un bloc de `boot-check.sh`, ma borne a avalé le bloc VOISIN — et le
contrôle hebdomadaire 21, seul à mesurer le texte de démarrage, partait dans le MÊME geste.*

## Après avoir touché un garde, vérifier ce qui est passé — pas qu'il est remis

**Un garde se teste sur une copie, jamais en le modifiant.** Le modifier pour voir, même restauré dans la foulée, ouvre une fenêtre réelle pendant laquelle il ne garde plus rien.

**Et surtout, ce qui contredit le réflexe : après tout contact avec un garde, la vérification porte sur ce qui EST PASSÉ pendant la fenêtre, pas sur l'état du garde restauré.** Un garde remis à l'identique ne prouve rien sur ce qui a franchi pendant qu'il était ouvert. Le cas mécanique qui le montre : git ne désuit pas un fichier quand on retire son motif d'exclusion — un fichier indexé pendant la fenêtre y reste, et un `git diff` sur le garde lui-même est donc **vert par construction dans le cas exact qu'il devrait attraper**. Contrôler l'objet potentiellement passé — le fichier est-il suivi, figure-t-il dans un commit —, jamais le garde seul.

**Et la même exigence vaut au premier jour d'un garde : il ne vaut rien tant que sa sortie n'a pas été COMPTÉE et comparée à un attendu posé d'avance.** La relecture ne suffit pas — pour une exclusion, `git status --porcelain --untracked-files=all | wc -l` avant tout `git add`. Sur pièce, 2026-08-22 : une liste noire neuve, soignée et commentée, n'excluait **rien** — git ne reconnaît le dièse qu'en TÊTE de ligne, un commentaire écrit après le motif fait partie du motif. 1 175 fichiers passaient, transcripts compris ; un comptage l'a montré en une commande, la lecture ne le pouvait pas.

*Élargissement de la règle mère ci-dessus, pas une quatrième règle.*

## Une autorisation de sauvegarde se mesure sur son cas négatif

**Toute vérification d'une autorisation passe par `git check-ignore --no-index -q`, et s'exerce sur un cas qui doit être refusé.** Sans `--no-index`, la commande rend « autorisé » pour tout fichier suivi, qui échappe au `.gitignore` par construction : elle mesure alors l'état d'indexation, pas la règle. Un contrôle qui ne rend jamais « refusé » sur un cas qui doit l'être ne mesure rien.

**ET `-v` DÉTRUIT LE CODE RETOUR — ne jamais s'en servir pour décider** *(signalé par une session de projet qui a failli conclure au refus sur une autorisation valide)*. Mesuré sur pièce :

| | `-q` | `-v` |
|---|---|---|
| chemin **autorisé** | `rc=1` | `rc=0` |
| chemin **refusé** | `rc=0` | `rc=0` |

Avec `-v` le code retour vaut **0 dans les deux cas** : il ne distingue plus rien, et une construction `check-ignore -v … && echo REFUSÉ || echo AUTORISÉ` répond donc « refusé » **même sur une autorisation**. La raison est que `-v` réussit dès qu'il a une règle à montrer, y compris une règle de **négation** — et une ligne `!chemin/**` affichée se lit comme un refus alors qu'elle est l'autorisation elle-même. **Décider avec `-q`, lire avec `-v`** : le drapeau bavard sert à savoir QUELLE règle a tranché, jamais à savoir LAQUELLE des deux issues.

*Cette précision est le geste opposable qui manquait : la règle ci-dessus a d'abord été écrite sans elle, et la session hôte a elle-même employé `-v` dans un test ce jour-là — sans conclure faux, mais par chance seulement, le chemin testé étant réellement refusé.*

Motif, sur pièce : ce piège était consigné en mémoire, et il a été repayé sur un rangement de dossier. Savoir qu'il existe ne suffit donc pas — il manquait le geste opposable, et c'est le drapeau qui le porte.

*Seconde occurrence du même piège, ce qui l'étaye.*

## Un fichier témoin s'écrit sur un chemin vérifié vide

Symétrique de la section précédente, côté objet de test et non côté garde : **un geste de test porte la même charge destructrice qu'un geste réel.** Le chemin d'un fichier témoin se vérifie inexistant avant l'écriture — par `ls` ou `git ls-files` —, jamais supposé libre parce qu'il est plausible. Le doute se lève avant, pas dans la sortie du test.

Motif, sur pièce : un témoin écrit sur l'archive d'une autre application, écrasée puis supprimée.

La règle générale « avant de supprimer ou d'écraser, regarder la cible » existait déjà et n'a rien déclenché : le geste de test se dispense mentalement des précautions du geste réel.

## Ce qui bloque et ce qui avertit

Un contrôle qui garde la sauvegarde peut empêcher d'enregistrer du travail. La ligne de partage ne se trace donc pas entre « contenu » et « plomberie », partage trop grossier qui mélange deux choses opposées, mais sur ceci : **est-ce que le défaut désactive quelque chose, ou est-ce qu'il encombre ?**

**Avertit — ce qui encombre.** Un plafond de rangement dépassé (mémoire trop longue, journal au-delà de sa rotation), une reprise manquante, un inventaire incomplet. Rien n'est désactivé, rien n'est perdu, et ça se range à la prochaine clôture. Bloquer là-dessus fait payer un défaut de rangement par la perte d'une journée de travail — ce qui est arrivé deux fois dans ce système.

**Bloque — ce qui désactive en silence.** Une fiche présente mais non routée, ou un chemin cité par une règle et absent du disque : dans les deux cas une règle existe, le système croit l'appliquer, et elle ne se charge jamais. Et toute corruption au sens strict — copie partielle, verrou perdu, secret en partance.

**Un plafond de rangement avertit ; un CLIQUET refuse** — code 20 de `engine/hooks/pre-commit-alarmes.sh`, valeurs dans `engine/config.sh` (`CLAUDEOS_CLIQUET_*`). Un refus 20 n'est pas un faux positif : il se lève en finançant l'ajout dans la même monnaie, jamais par `FORCE_CLIQUET` sans l'avoir dit à l'utilisateur.

Relever un seuil, ou dégrader un blocage en avertissement pour se débloquer, est une décision à prendre et à écrire — jamais un ajustement silencieux.

Ce qui a fixé cette ligne, sur pièce : un plafond calibré trop serré a fait tomber la plomberie dès la première dette de sécurité inscrite. La plomberie gardant la sauvegarde, une alerte légitime interdisait d'enregistrer son travail. Deux journées ont été perdues ainsi. Faire payer un défaut de rangement par la perte d'une journée est exactement ce que ce partage existe pour éviter.
