---
name: session
description: Reprise de contexte, passe mensuelle, proposition du travail du jour, fin de session. Aussi au moment de LANCER UN SOUS-AGENT (quel modèle, et le libellé qui le nomme) et de PARLER À UNE AUTRE SESSION. Aussi pour savoir OÙ revérifier un fait vivant avant d'agir — `ETAT.md` et son journal d'événements en premier — état d'un déploiement, contenu d'un dossier, statut d'une action externe.
---

# Règles — conduite de session

> Fiche situationnelle. Déclencheur : reprise de contexte annoncée, passe mensuelle signalée au démarrage, proposition du travail du jour (bilan de démarrage, « qu'est-ce qu'on fait aujourd'hui », arbitrage de priorités), fin de session, ou fin d'une séance de conception. Plus deux moments : je lance un sous-agent, et je parle à une autre session.
> Cette fiche porte une règle que le règlement ne contient pas : consulter la carte de rappel avant tout travail de fond.

## Lancer un agent — modèle et libellé

**Sélection du modèle : le plus capable adapté à l'enjeu, qualité avant rapidité, sans figer un modèle par type de tâche.** La session ne choisit pas son propre modèle : cette règle ne sert qu'au lancement d'un agent. Une règle de l'utilisateur qui fixe le modèle d'un geste — une relecture, un audit — prime sur elle ; elle vit dans « Mes règles » du `CLAUDE.md`.

**Quand un modèle ou un effort est fixé, il se pose explicitement** :
- **Agent défini** : son frontmatter porte `model:` — l'identifiant exact, pas l'alias — et `effort:`. `effort` du frontmatter remplace celui de la session *(vérifié le 2026-09-30, code.claude.com/docs/en/sub-agents)* ; un champ mal orthographié est ignoré sans erreur, donc relire l'orthographe.
- **Agent lancé sans définition** (`general-purpose`, ad hoc) : il hérite de l'effort de la session. **Avant de le lancer, si la session n'est pas à l'effort voulu, demander à l'utilisateur de le changer par `/effort`.** `max` ne s'enregistre pas dans `settings.json` *(vérifié le 2026-09-30, `effortLevel` n'accepte que `low` à `xhigh`, docs settings-reference)*, donc aucune session ne démarre en `max` et la question se repose à chaque session.

**Tout libellé d'agent lancé et de tâche suivie nomme son modèle** — « Audit check 3 · Fable » —, pour que la barre des agents dise qui travaille.

## Parler directement à une autre session

**Un geste qui sort de mon périmètre d'écriture et appartient à une autre session, je le lui envoie
moi-même** : `ListAgents` pour la trouver, puis `SendMessage`. Je ne rédige pas une consigne que
l'utilisateur devra recopier. Hors périmètre d'**écriture** ne veut pas dire hors de portée.

- **Le brief part avec tout le contexte**, parce que la session cible ne voit pas la mienne : ce qui
  est déjà fait de mon côté — pour qu'elle ne le refasse pas —, les gestes attendus avec leurs
  chemins, et les pièges.
- **Une session marquée occupée reçoit quand même** : le message s'empile et se traite à son prochain
  tour d'outil.
- **Jamais un geste que mes propres permissions ont refusé.** Le faire exécuter par un pair
  contournerait une décision de l'utilisateur. Un refus se remonte à lui, il ne se sous-traite pas.
- **Le rapport d'un pair se recontrôle comme celui d'un sous-agent** (règlement, socle, « Trois interdits,
  jamais conditionnés »). Réciproquement, un pair qui refuse d'endosser mon tri sans l'avoir vérifié applique
  la règle, il ne résiste pas.

## Avant tout travail de fond

- **Consulter la carte de rappel** (`## Où trouver` d'`ETAT.md`) **et chercher les décisions passées dans le corpus** (document de conception, journal, retours), au lieu de s'en tenir à la chaîne chargée par le routage.

### Faits vivants — où les revérifier

Le règlement garde le principe : *un fait vivant se revérifie à sa source avant toute action conséquente ou irréversible ; écrit sans sa date et sa source, il est à revérifier, pas à croire.* Voici les sources.

| Fait vivant | Source canonique |
| :--- | :--- |
| Ce que contient un dossier, si un fichier existe | le disque **de la machine nommée** — un dossier non synchronisé (`_IGNORE/`, local-only) diffère d'un poste à l'autre, donc « le fichier est là » sans dire *où* ne veut rien dire |
| Dernier point de sauvegarde, retard d'un poste | l'historique du dépôt ; en `GIT=aucun`, il n'y en a pas : la dernière clôture passée se lit à `~/.claude/.claudeos/empreintes/MANIFESTE.json`, qu'elle réécrit |
| État d'un déploiement, version réellement en service | le système déployé lui-même, ou son export |
| Ce qui reste à faire | `etat.py fils --tous` (vue par ancienneté, calculée) ; à défaut, `etat.py vue` du niveau |
| Statut d'une action externe (accès, ticket, PR) | le service concerné |

**Sont durables, et ne demandent pas cette revérification** : identité, préférences, but et positionnement d'un projet.


## Chargement

- **Un niveau qui porte `ETAT.md` se charge par LUI.** `ETAT.md` est court et projeté ; l'histoire est au journal, cherchée au `grep`, jamais chargée.
- **Lire par sections ciblées donne le sentiment complet d'avoir consulté.** Deux gestes l'empêchent : **une compétence qu'on va ÉDITER s'invoque d'abord par l'outil `Skill`**, jamais lue au `grep` ou au `sed` seulement ; **un document qu'un `CLAUDE.md` rend obligatoire avant un geste se lit en entier**, pas à la section cherchée. *(Payé deux fois le même jour : une règle fausse écrite et poussée dans une compétence lue au `sed`, qui portait déjà la forme juste ; un document de conception lu par sections avant d'écrire du code.)*
- Profondeur selon le poids de la tâche : question rapide → le `CLAUDE.md` local concerné seulement ; travail courant → plus l'`ETAT.md` local ; travail de fond, code ou spec → chaîne complète plus corpus.

## Reprise de contexte

Quand l'utilisateur déclare un contexte de travail (« je reprends <PROJET> ») :

1. **Suivre la cascade de chargement du règlement (socle, « Niveaux ») — elle est la source, et cette fiche ne la recopie pas.**
2. **Lire l'état du niveau.** S'il porte `ETAT.md` : celui-là, puis `grep` dans son `journal/` sur ce qu'on cherche — l'histoire n'est pas dans l'état. Sinon, ce n'est pas encore un niveau : le monter d'abord (compétence `nouveau-projet`).
3. **En régime GitHub, si le poste est en retard sur un dépôt, tirer AVANT de lire les fichiers
   locaux** — sinon on travaille sur des fichiers périmés. Le bilan de démarrage annonce le retard en
   commits ; le geste est `git -C ~/.claude pull --rebase`, et l'équivalent sur chaque dépôt que
   `claudeos_repos` rend. En `GIT=aucun`, un seul poste et aucun dépôt : rien à tirer.

## Passe mensuelle — l'audit du système

Due une fois par mois ; le démarrage la signale passé son seuil, que porte `engine/boot-check.sh`. Elle porte l'hygiène des mémoires, les plafonds, le journal, la carte de rappel, les ratés de routage et la revue des fils, plus ses propres contrôles.

La procédure vit dans la compétence `os-audit`, seule autorité. Ne pas la recopier ici : deux copies à deux âges se contredisent. Invoquer la compétence, suivre sa fiche d'hygiène.

Ce que cette fiche-ci porte : **rien ne se mesure ni ne se vérifie à la clôture.** La conséquence : une passe sautée est un mois sans vérification.

### Règles candidates — la promotion se fait à la passe

**Quand `REGLES_A_FROID=oui`**, le règlement porte les deux règles de la boucle d'apprentissage
(fragment `regles-a-froid-oui`) : une règle née en séance devient un dû du chantier
`regles-candidates` au lieu de s'écrire à chaud, et une règle n'entre que si une autre sort. À
`non`, ce paragraphe est sans objet.

Ce qui n'est qu'à cette fiche : la promotion d'une candidate se fait **à la passe, à froid** — au
même moment où se pose la question du troc, « laquelle sort ». Le geste et la monnaie du troc par
couche vivent dans `skills/os-audit/HYGIENE.md`, geste « Règles candidates », **seule autorité — ne
pas le recopier ici**. Et l'exception d'irréversibilité se lit strictement — une perte de données,
un envoi à un tiers, une fuite ; une règle de conduite, une préférence de forme, une heuristique de
jugement n'en relèvent jamais, quelle que soit leur évidence sur le moment.

## Proposition du jour

- **Filtrer sur le créneau, si l'utilisateur en a déclaré.** La déclaration machine est `~/.claude/reglages/CRENEAUX`, facultative, source unique du **quel domaine, quels jours** — ne pas la recopier ici, elle changera de mission. Le profil de l'utilisateur, en mémoire, porte le rythme en prose, comme fait durable ; un changement de rythme se pose d'abord dans `CRENEAUX`, que les scripts lisent. Ne jamais proposer comme travail du jour ce qui est impossible dans le créneau courant — un domaine hors de son jour n'existe pas ce jour-là. L'engagement extérieur passe devant l'interne, mais dans la limite de son créneau. L'ancienneté d'un fil rattaché à un créneau se compte en créneaux manqués, pas en jours calendaires ; le démarrage la donne déjà dans cette unité et marque « HORS CRÉNEAU » ce qui n'est pas faisable aujourd'hui.
- **Chiffrer, c'est rapporter au créneau.** Pas de durée abstraite : ça rentre dans ce qui reste de la journée, ça demande une journée entière, ou ça attend vendredi.
- **Préparer le créneau rare avant qu'il s'ouvre**, la veille : ce qui est en retard, ce qui est prêt, ce qui attend un tiers, et les vérifications faisables à l'avance. Quels créneaux sont rares se lit dans `reglages/CRENEAUX`, jamais ici. Un créneau d'un jour par semaine ne s'agrandit pas ; seul le temps de mise en route se récupère.
- **Un rappel qui désigne une source la nomme comme hypothèse, pas comme fait.** Quand un rappel daté ou un fil ouvert renvoie à une source à consulter, l'écrire comme une piste : « à confirmer ; piste envisagée, tel document, non vérifiée » — et non « reste à confirmer sur tel document », qui se lit comme un fait établi. Corollaire, à appliquer avant de reconduire : vérifier que la source désignée porte bien la réponse. **La reconduction ne retarde pas le travail, elle protège l'erreur** — chaque report reconfirme un pointeur que personne n'ouvre. *(Payé une fois : cinq reconductions sur trois semaines.)*
- **Un rappel échu = une question, en début de séance.** Le démarrage les liste. Pour **chacun**, poser une question via `AskUserQuestion` avant de dérouler sa demande — pas un résumé en prose, pas un lot regroupé : un rappel, une question, trois issues (tenir maintenant · replanifier à une date · abandonner). Puis appliquer : replanifier réécrit la ligne de `memory/REMINDERS.md` avec la nouvelle échéance ; abandonner purge la ligne et en laisse la trace au journal ; tenir purge la ligne une fois le travail fait. Motif : un rappel qui se réaffiche sans qu'on tranche a cessé d'être un rappel, et c'est le fait de devoir répondre qui le fait bouger, pas la façon de l'afficher.
- **Rappel ou fil reconduit trois fois : attaquer l'obstacle, pas le rappel.** **RIEN NE COMPTE LES RECONDUCTIONS, et ce seuil se tient donc à la main** : une ligne de `REMINDERS.md` est `- AAAA-MM-JJ | texte`, replanifier RÉÉCRIT la date sans rien incrémenter, et `etat.py` n'a pas d'op `reconduit`. Le compte se retrouve au `grep` dans le journal, ou il se perd — un chiffre de reconduction lu quelque part est une estimation, jamais une mesure. À la troisième reconduction, arrêter de répéter et chercher pourquoi il ne part pas, puis proposer de retirer le frottement — premier pas plus petit, liste de contrôle, outil qui réduit le coût du geste. Un rappel ne change rien à un blocage qu'on n'a pas nommé.
- **Idées lancées en passant** : capturées dans `IDEES_FROIDES.md` du dossier de mémoire automatique, jamais mêlées aux fils ouverts — sinon la vue du matin noie les engagements sous les envies. Relues sur demande, ou quand un sujet les rend pertinentes.

## Fin de session, et écriture de reprise

La compétence `reprise` en est la seule autorité — quand écrire, où, quoi, et les trois gestes de
la clôture. Deux fiches qui disent la même chose sous deux angles font naître deux cadences pour
une seule règle.

Ce qui reste ici, parce que c'est une règle de conduite de séance et non une procédure
d'écriture : **rien n'est vérifié à la clôture.** Toute vérification est due à la passe
mensuelle ci-dessus. Une clôture qui se met à contrôler devient une cérémonie.
