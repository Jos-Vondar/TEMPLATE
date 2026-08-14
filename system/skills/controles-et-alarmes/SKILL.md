---
name: controles-et-alarmes
description: Écrire, modifier ou désarmer un contrôle mécanique ou une alarme, ou mettre un chemin en liste blanche de sauvegarde. Aussi devant un comportement d'outil inexpliqué, une sortie invraisemblable, ou une commande qui peut atteindre deux installations.
---

# Règles — écrire ou modifier un contrôle mécanique ou une alarme, et diagnostiquer une sortie qui ne colle pas

> Fiche situationnelle. Se charge sur déclencheur, jamais par réflexe. Déclencheur : j'écris, je modifie ou je désarme un contrôle de plomberie, un signal de démarrage, une alarme, ou tout code dont la fonction est de détecter un défaut plutôt que de produire un résultat. **Deuxième famille, ajoutée** : je diagnostique un comportement d'outil que la configuration n'explique pas, une sortie invraisemblable, ou je lance une commande qui peut atteindre deux installations.
> Motif d'existence de cette fiche : les règles ci-dessous portent sur du code, et sur des sorties de code, dont la seule fonction est de dire la vérité sur le système. Un défaut y est plus coûteux qu'ailleurs, parce qu'il ne se manifeste pas — il se tait.

## Diagnostiquer avant d'agir — deux règles descendues du règlement

Elles y vivaient et se déclenchent sur un moment observable, pas en permanence : c'est ce qui les fait descendre ici. Elles restent la première chose à lire quand une sortie ne colle pas.

- **Une instruction peut venir de l'outil sans figurer dans la configuration.** Devant un comportement que les fichiers n'expliquent pas, envisager l'outil plutôt que de les déclarer faux — fait instable, propre au poste. *(→ origines)*
- **Quand une commande peut atteindre deux installations, sonder la cible en lecture seule avant d'agir** : un message de succès ne dit pas laquelle a été touchée. *(→ origines)*

## Un contrôle neuf n'est pas vérifié tant qu'il n'a pas échoué exprès

**Tout contrôle nouvellement écrit s'exerce sur son cas positif avant d'être cru** : introduire volontairement le défaut qu'il cherche, et constater qu'il crie. Un contrôle qui n'a jamais crié ne prouve rien, il peut ne regarder rien. Le cas négatif — tout va bien, le contrôle est vert — ne distingue pas un contrôle qui fonctionne d'un contrôle muet.

Le test se fait sur les données réelles ou sur une copie exacte, jamais sur une reformulation privée de la garde : reproduire la logique à côté pour la tester valide la reproduction, pas le contrôle en place. Quand le cas positif est inapplicable au moment de l'écriture — aucun défaut présent à mettre en scène — le dire dans la sortie du contrôle plutôt que de laisser croire qu'il a été exercé.

*(→ origines)*

## Un faux positif diagnostiqué se corrige dans la séance

**Un signal dont on établit en séance qu'il est un faux positif se corrige dans la même séance, ou l'on écrit pourquoi on ne le corrige pas.** Diagnostiquer sans corriger est le pire des trois états possibles : le signal continue de crier, on sait qu'il ne faut pas l'écouter, et on apprend à ignorer la catégorie entière — les vrais signaux compris. Le coût ne se paie pas sur le faux positif, il se paie sur le vrai qu'on manquera ensuite.

**Sous-règle appairée. Une alarme se construit sur l'état courant, jamais sur la trace d'un état passé.** Chercher un mot-clé dans une fenêtre de fin de fichier ne mesure pas un état, cela retrouve un souvenir : le signal survit alors à sa cause, mécaniquement, jusqu'à ce que le volume l'évacue. Faire porter tout verdict sur la dernière opération enregistrée, et savoir distinguer une opération terminée en échec d'une opération interrompue avant son terme.

*(→ origines)*

## Un journal borgne fait mentir le contrôle qui le lit

**Un contrôle qui juge sur un journal n'est vérifié que si ce journal voit toutes les voies d'écriture de ce qu'il enregistre.** Recenser les chemins de sortie du producteur — appel par un hook, lancement à la main, appel depuis un autre script — et constater que chacun laisse sa trace. Un producteur qui n'en journalise qu'un rend le contrôle exact et son verdict faux, et c'est le contrôle qui paraît fautif.

Le geste qui tranche : faire produire l'événement par **chaque** voie, pas par la plus commode. C'est le cas positif de la section précédente étendu au producteur, et plus au seul contrôle.

**Sur pièce, trois fois dans la même semaine.** Le journal de sauvegarde n'était alimenté que par la redirection du hook de fin de session, or le rituel de clôture lance le script à la main : une sauvegarde réussie est restée invisible et l'alarme a crié sur un système sain. Une détection de dérive rendait 28 fantômes faute de lire le fichier d'exclusion, si bien qu'on avait cessé de lire son résultat. Et un garde des secrets sautait tous les fichiers en affichant qu'il avait balayé l'arbre entier.

*(→ origines)*

## Deux pièges déjà payés, à ne pas repayer

- **Une boucle de lecture perd la dernière ligne d'un fichier sans retour à la ligne final.** C'est le rappel le plus récent, donc le seul actif, qui disparaît. Utiliser un outil qui la conserve, ou garder explicitement le reste de tampon. Coût constaté : 23 jours de silence complet.
- **Un seuil défini dans un script ne se recopie pas ailleurs** — application au cas des contrôles de la règle « un fait calculable ne s'écrit pas, il se lit », qui vit dans la compétence `memoire-et-verite` et n'est pas redite ici. Corollaire propre aux contrôles : quand un contrôle change un seuil, chercher qui le cite avant de conclure que c'est fini.

## Une exception vaut pour tous les gardes, pas pour le premier rencontré

**Avant de conclure qu'un chemin est mis en liste blanche, chercher tous les mécanismes qui le gardent.** Plusieurs contrôles indépendants surveillent souvent la même zone par des moyens différents — l'un filtre à la copie, l'autre inspecte ce qui part en file, un troisième lit le contenu. N'en traiter qu'un laisse le blocage entier tout en donnant le sentiment d'avoir agi, et le diagnostic repart de zéro à la tentative suivante.

Méthode : chercher le chemin, le format et le nom du garde dans **tout** le moteur, pas seulement dans le fichier de configuration évident. Une exception se pose ensuite partout d'un coup, chacune commentée par son motif, et se vérifie de bout en bout sur le geste réel — pas sur un essai en bac à sable, qui ne dit rien du chaînage.

*(→ origines)*

## Ce qui bloque et ce qui avertit

Un contrôle qui garde la sauvegarde peut empêcher d'enregistrer du travail. La ligne de partage ne se trace donc pas entre « contenu » et « plomberie », partage trop grossier qui mélange deux choses opposées, mais sur ceci : **est-ce que le défaut désactive quelque chose, ou est-ce qu'il encombre ?**

**Avertit — ce qui encombre.** Un plafond de rangement dépassé (mémoire trop longue, journal au-delà de sa rotation), une reprise manquante, un inventaire incomplet. Rien n'est désactivé, rien n'est perdu, et ça se range à la prochaine clôture. Bloquer là-dessus fait payer un défaut de rangement par la perte d'une journée de travail — ce qui est arrivé deux fois dans ce système.

**Bloque — ce qui désactive en silence.** Une fiche présente mais non routée, ou un chemin cité par une règle et absent du disque : dans les deux cas une règle existe, le système croit l'appliquer, et elle ne se charge jamais. Et toute corruption au sens strict — copie partielle, verrou perdu, secret en partance.

**Le poids de la couche chargée à chaque session avertit** *(→ origines)*. Il figurait dans les blocages au motif qu'un poids excessif ne se manifeste par rien — motif tombé, la plomberie affiche désormais le poids réel à chaque passage, donc il se voit.

Relever un seuil, ou dégrader un blocage en avertissement pour se débloquer, est une décision à prendre et à écrire — jamais un ajustement silencieux.

**Ce qui a fixé cette ligne, sur pièce** : un plafond calibré trop serré a fait tomber la plomberie dès la première dette de sécurité inscrite. La plomberie gardant la sauvegarde, une alerte légitime interdisait d'enregistrer son travail. Deux journées ont été perdues ainsi. Faire payer un défaut de rangement par la perte d'une journée est exactement ce que ce partage existe pour éviter.
