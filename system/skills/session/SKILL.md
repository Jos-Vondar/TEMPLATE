---
name: session
description: Reprise de contexte, distillation due, proposition du travail du jour, fin de session ou de séance de conception. Porte la profondeur de chargement, la chaîne de reprise, l'ordre sauvegarde puis synchro, le rituel de clôture.
---

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

**La procédure vit dans la compétence `os-audit`, section « Hygiène », seule autorité.** Ne pas la recopier ici : deux copies à deux âges se contredisent, et c'est déjà arrivé sur cette liste. Invoquer la compétence, suivre sa section d'hygiène.

Ce que cette fiche-ci porte, et qu'`os-audit` ne dit pas : rien n'est fait à la clôture, donc **ce qui n'est pas fait à la passe n'est fait nulle part**. Une passe sautée n'est pas un retard de rangement, c'est une semaine sans vérification.

### Cool-down des règles — la promotion se fait ici *(énoncé remonté au règlement)*

**L'énoncé — refroidissement et troc — vit dans `CLAUDE.md` §1, qui en est la source ; son motif vit au catalogue des règles. Ne recopier ni l'un ni l'autre ici.** Ce que cette fiche ajoute, et qui n'est qu'à elle : la promotion depuis `<MÉMOIRE>/LEARNING_PROPOSALS.md` se fait **ici, à la passe, à froid** — au même moment où se pose la question du troc, « laquelle sort ». Elle vaut pour toute couche : règlement, compétence situationnelle, document de conception. Et l'exception d'irréversibilité se lit strictement — une perte de données, un envoi à un tiers, une fuite ; une règle de conduite, une préférence de forme, une heuristique de jugement n'en relèvent jamais, quelle que soit leur évidence sur le moment. *(Un règlement qui ne porte pas ces règles les a déclinées à l'entretien — cette mécanique tombe alors avec elles.)*

## Proposition du jour

- **Filtrer sur le créneau.** La déclaration machine est `~/.claudeos/engine/config/CRENEAUX`, source unique du **quel domaine, quels jours** — ne pas la recopier ici, elle changera avec le contexte. Son profil (`<MÉMOIRE>/user_profile.md`) porte le rythme en prose, comme fait durable ; un changement de rythme se pose d'abord dans `CRENEAUX`, que les scripts lisent. Ne jamais proposer comme travail du jour ce qui est impossible dans le créneau courant — un fil rattaché à un créneau fermé aujourd'hui ne se propose pas. Le travail du créneau ouvert passe devant le reste, mais dans la limite de son créneau. L'ancienneté d'un fil rattaché à un créneau se compte en créneaux manqués, pas en jours calendaires ; le démarrage la donne déjà dans cette unité et marque « HORS CRÉNEAU » ce qui n'est pas faisable aujourd'hui.
- **Chiffrer, c'est rapporter au créneau.** Pas de durée abstraite : ça rentre dans ce qui reste de la journée, ça demande une journée entière, ou ça attend le prochain créneau.
- **Préparer un créneau avant qu'il s'ouvre.** Avant qu'un créneau s'ouvre, monter ce qui s'y jouera : ce qui est en retard, ce qui est prêt à être fait, ce qui attend un tiers, et les vérifications faisables à l'avance. Un créneau ne s'agrandit pas ; seul le temps de mise en route se récupère.
- **Un rappel qui désigne une source la nomme comme hypothèse, pas comme fait.** Quand un rappel daté ou un fil ouvert renvoie à une source à consulter, l'écrire comme une piste : « à confirmer ; piste envisagée, tel document, non vérifiée » — et non « reste à confirmer sur tel document », qui se lit comme un fait établi. Corollaire, à appliquer avant de reconduire : vérifier que la source désignée porte bien la réponse. Motif, sur pièce : un rappel a été reconduit cinq fois sur trois semaines en désignant un guide de licences qui ne contenait aucune des deux réponses attendues — pas une seule occurrence du terme cherché, aucun ordre de consommation énoncé. La reconduction n'a pas seulement retardé le travail, elle a **protégé l'erreur**, chaque report reconfirmant un pointeur que personne n'ouvrait. *(→ origines)*
- **Un rappel échu = une question, en début de séance.** Le démarrage les liste. Pour **chacun**, poser une question via `AskUserQuestion` avant de dérouler sa demande — pas un résumé en prose, pas un lot regroupé : un rappel, une question, trois issues (tenir maintenant · replanifier à une date · abandonner). Puis appliquer : replanifier réécrit la ligne de `REMINDERS.md` avec la nouvelle échéance ; abandonner purge la ligne et en laisse la trace au journal ; tenir purge la ligne une fois le travail fait. Motif : un rappel qui se réaffiche sans qu'on tranche a cessé d'être un rappel, et c'est le fait de devoir répondre qui le fait bouger, pas la façon de l'afficher.
- **Rappel ou fil reconduit trois fois : attaquer l'obstacle, pas le rappel.** À la troisième reconduction, arrêter de répéter et chercher pourquoi il ne part pas, puis proposer de retirer le frottement — premier pas plus petit, liste de contrôle, outil qui réduit le coût du geste. Un rappel ne change rien à un blocage qu'on n'a pas nommé. Les paliers d'ancienneté et le plafond de reports sont supprimés : un retard se dit en clair, il n'a pas besoin d'une graduation.
- **Idées lancées en passant** : capturées dans `IDEES_FROIDES.md` du dossier de mémoire automatique, jamais mêlées aux fils ouverts — sinon la vue du matin noie les engagements sous les envies. Relues sur demande, ou quand un sujet les rend pertinentes.

## Fin de session, et écriture de reprise

**Sorties de cette fiche vers la compétence `reprise`, qui en est désormais la
seule autorité** — quand écrire, où, quoi, et les trois gestes de la clôture. Deux fiches
disaient la même chose sous deux angles, et c'est ainsi que naissent deux cadences pour une
seule règle.

Ce qui reste ici, parce que c'est une règle de conduite de séance et non une procédure
d'écriture : **rien n'est vérifié à la clôture.** Toute vérification est due à la passe
hebdomadaire ci-dessus. Une clôture qui se met à contrôler devient une cérémonie, et c'est
l'usine à gaz dégonflée.
