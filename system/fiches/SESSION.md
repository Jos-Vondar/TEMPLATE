# Règles — conduite de session

> Fiche situationnelle. Déclencheur : reprise de contexte annoncée, distillation d'apprentissage signalée au démarrage, **proposition du travail du jour** (bilan de démarrage, « qu'est-ce qu'on fait aujourd'hui », arbitrage de priorités), fin de session, ou fin d'une séance de conception.
> Restent dans le `CLAUDE.md` racine parce qu'elles doivent se déclencher sans qu'on aille les chercher : relayer d'emblée les signaux du démarrage, consulter la carte de rappel avant tout travail de fond, et la distinction entre fait durable et fait vivant.

## Chargement

- Les `MEMORY.md` de workstation, projet et app se chargent via le routage, dès qu'une demande correspond à leur domaine.
- Profondeur selon le poids de la tâche : question rapide → le `CLAUDE.md` local concerné seulement ; travail courant → plus le `MEMORY.md` local ; travail de fond, code ou spec → chaîne complète plus corpus.

## Reprise de contexte

Quand l'utilisateur déclare un contexte de travail (« je reprends tel projet ») :

1. Charger la chaîne complète : workstation → projet → app, `CLAUDE.md` et `MEMORY.md` à chaque niveau.
2. Lire le journal de session pour reprendre le fil.
3. Si la machine courante diffère de celle de la session précédente (le journal l'indique) : faire lancer la synchronisation avant de lire les fichiers locaux, sinon on travaille sur des fichiers périmés.
4. Rappel du racine (§6), qui en est la source : jamais de sauvegarde depuis un poste non synchronisé.

## Passe hebdomadaire — l'audit du système

Due une fois par semaine ; le démarrage la signale au-delà de sept jours. Elle porte **tout ce qui a quitté la clôture** — hygiène des mémoires, plafonds, journal, distillation, retombée documentaire, carte de rappel, ratés de routage, revue des fils — plus les contrôles d'audit qu'elle faisait déjà.

**La procédure vit dans la fiche `os-audit`, seule autorité.** Ne pas la recopier ici : deux copies à deux âges se contredisent, et c'est déjà arrivé sur cette liste. Invoquer la fiche, la suivre.

Ce que cette fiche-ci porte, et qu'`os-audit` ne dit pas : rien n'est fait à la clôture, donc **ce qui n'est pas fait à la passe n'est fait nulle part**. Une passe sautée n'est pas un retard de rangement, c'est une semaine sans vérification.

## Proposition du jour

- **Filtrer sur le créneau.** Les créneaux hebdomadaires sont déclarés dans son profil (`<MÉMOIRE>/user_profile.md`), source unique — ne pas les recopier ici, ils changeront avec le contexte. Ne jamais proposer comme travail du jour ce qui est impossible dans le créneau courant — un travail de créneau extérieur un jour d'interne n'existe pas. Un engagement pris envers un tiers passe devant le travail interne, mais dans la limite de son créneau. L'ancienneté d'un fil rattaché à un créneau hebdomadaire se compte en créneaux manqués, pas en jours calendaires.
- **Chiffrer, c'est rapporter au créneau.** Pas de durée abstraite : ça rentre dans ce qui reste de la journée, ça demande une journée entière, ou ça attend le prochain créneau.
- **Préparer le créneau rare avant qu'il s'ouvre.** La veille d'un créneau rare, monter ce qui s'y jouera : ce qui est en retard, ce qui est prêt à être fait, ce qui attend un tiers, et les vérifications faisables à l'avance. Un créneau rare ne s'agrandit pas ; seul le temps de mise en route se récupère.
- **Un rappel qui désigne une source la nomme comme hypothèse, pas comme fait.** Quand un rappel daté ou un fil ouvert renvoie à une source à consulter, l'écrire comme une piste : « à confirmer ; piste envisagée, tel document, non vérifiée » — et non « reste à confirmer sur tel document », qui se lit comme un fait établi. Corollaire, à appliquer avant de reconduire : vérifier que la source désignée porte bien la réponse. Motif, sur pièce : un rappel a été reconduit cinq fois sur trois semaines en désignant un guide de licences qui ne contenait aucune des deux réponses attendues — pas une seule occurrence du terme cherché, aucun ordre de consommation énoncé. La reconduction n'a pas seulement retardé le travail, elle a **protégé l'erreur**, chaque report reconfirmant un pointeur que personne n'ouvrait. *(→ origines)*
- **Un rappel échu = une question, en début de séance.** Le démarrage les liste. Pour **chacun**, poser une question via `AskUserQuestion` avant de dérouler sa demande — pas un résumé en prose, pas un lot regroupé : un rappel, une question, trois issues (tenir maintenant · replanifier à une date · abandonner). Puis appliquer : replanifier réécrit la ligne de `REMINDERS.md` avec la nouvelle échéance ; abandonner purge la ligne et en laisse la trace au journal ; tenir purge la ligne une fois le travail fait. Motif : un rappel qui se réaffiche sans qu'on tranche a cessé d'être un rappel, et c'est le fait de devoir répondre qui le fait bouger, pas la façon de l'afficher.
- **Rappel ou fil reconduit trois fois : attaquer l'obstacle, pas le rappel.** À la troisième reconduction, arrêter de répéter et chercher pourquoi il ne part pas, puis proposer de retirer le frottement — premier pas plus petit, liste de contrôle, outil qui réduit le coût du geste. Un rappel ne change rien à un blocage qu'on n'a pas nommé. Les paliers d'ancienneté et le plafond de reports sont supprimés : un retard se dit en clair, il n'a pas besoin d'une graduation.
- **Idées lancées en passant** : capturées dans `IDEES_FROIDES.md` du dossier de mémoire automatique, jamais mêlées aux fils ouverts — sinon la vue du matin noie les engagements sous les envies. Relues sur demande, ou quand un sujet les rend pertinentes.

## Fin de session

Trois gestes, rien d'autre. Toute vérification est due à la passe hebdomadaire, pas ici.

- **Écriture au fil de l'eau, avant le signal de fin.** L'état de reprise et l'entrée de journal de la séance s'écrivent par incréments pendant la séance. Déclencheurs : un palier franchi dans un chantier, et le signal de bascule de l'utilisateur (« on fait un aparté », « on passe à autre chose »). Motif : ce qui fait perdre le fil n'est pas la longueur du travail mais l'interruption non annoncée — poste qui s'éteint, ou bascule sans clôture. L'écriture se délègue à l'agent de clôture incrémentale, qui reçoit un brief rédigé par la session : elle seule détient le contexte, l'agent fait la chirurgie de fichier. En cas d'échec, écrire l'incrément à la main dans la forme qu'il prescrit — ne pas remettre à la session suivante.
- Signal de fin (« on arrête », « c'est tout pour aujourd'hui ») → **reprise, mémoire, sauvegarde**, dans cet ordre :
  1. **Reprise** : le `HANDOFF.md` de chaque projet touché, plus celui du niveau système. Il est déjà écrit si des incréments ont eu lieu ; il reste alors à le confirmer.
  2. **Mémoire** : la trace datée de la séance dans le `MEMORY.md` du bon niveau, et l'entrée de journal complétée, sa mention de séance en cours retirée.
  3. **Sauvegarde** : `bash ~/.claudeos/engine/backup.sh`. Lire son rapport de fichiers refusés : ce qui n'est pas dans la liste blanche ne part pas, et resterait sur cette seule machine.
- **L'entrée de journal s'ajoute brute, sans travail de rédaction**. Pas de digest à composer, pas de rotation vers l'archive : compression et rotation sont dues à la passe hebdomadaire. Deux exigences seulement survivent, et elles ne se négocient pas. L'entrée **doit exister** — c'est elle qui porte la séance pour la distillation hebdomadaire, qui ne relit que ce qui est écrit. Et elle est **anonyme** : le journal part sur le dépôt, donc aucun identifiant, aucune donnée personnelle, aucun verbatim client, projets désignés par leurs codes.
- Fin d'une séance de conception (brainstorm, entretien contradictoire) : écrire aussi le `HANDOFF.md` du niveau concerné, pour permettre la reprise.
- **Ne pas rejouer ici ce qui est parti à l'hebdomadaire** — hygiène des mémoires, plafonds, distillation, retombée documentaire, ratés de routage, revue des rappels. Ne pas non plus les tenir pour faites : elles sont dues ailleurs, pas supprimées.
