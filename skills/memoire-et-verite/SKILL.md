---
name: memoire-et-verite
description: Écrire un fait, un statut ou une décision, ou toucher une source de vérité — l'index MEMORY.md, un document de conception, un CLAUDE.md, ou un événement du journal projeté dans `ETAT.md`. Porte les cas ambigus du tri, l'intégrité des statuts, la relecture contradictoire. Alléger un fichier trop lourd → os-audit, geste « Hygiène des mémoires ».
---

# Règles — écrire un fait, un statut, une décision

> Fiche situationnelle. Se charge sur déclencheur, jamais par réflexe. Déclencheur : je vais écrire dans l'index `memory/MEMORY.md`, un document de conception, un `CLAUDE.md`, ou l'utilisateur dit « garde ça en mémoire » / « retiens ça » / « note ça ».
> La règle de tri en trois destinations vit dans le règlement (socle, « Mémoire et vérité ») : c'est elle qui décide où va le fait. Cette fiche porte le reste.

## Un ÉVÉNEMENT s'écrit IMMÉDIATEMENT, sans demander

**Ajouter un événement au journal du niveau — `etat.py add` — ne demande aucune confirmation.**
La seule autorisation qui reste due concerne les autres sources : le document de conception et les
`CLAUDE.md` se font valider avant toute modification de fond.

## Tri — cas particuliers

- Déclencheur lexical « garde ça en mémoire » et variantes : ne pas écrire dans `MEMORY.md` par réflexe. Appliquer la règle de tri. Cas évident : router et écrire. Cas ambigu : demander où ça va, en une question.
- Si doute entre deux destinations : probablement les deux. Un événement du journal (`etat.py add`) = trace datée ; le document de conception = fait intemporel.
- Toute entrée `MEMORY.md` de type « comportement voulu » doit pointer sa contrepartie **par le nom de sa section, jamais par un numéro** : `→ <document de conception> « <section> »`. *(Un renvoi par numéro meurt dès que la numérotation bouge.)*
- Avant d'ajouter une règle émergente (bug, pattern, comportement découvert en session) dans un `CLAUDE.md` : choisir le bon niveau (racine / domaine / projet / app). Le trancher soi-même, sans agent.
- **Un fait calculable ne s'écrit pas, il se lit.** Nombre de contrôles, taille d'un fichier, liste de dossiers : pointer la source qui le porte au lieu d'en recopier la valeur. Un contrôle qui vérifie la concordance de trois copies est un pansement sur une décision d'écriture évitable.
- **Une méthode se remonte au geste EXACT exécuté, jamais à sa version résumée.**
 Écrire la commande telle qu'elle a tourné, avec sa sortie, et non « j'ai vérifié que… ». Un geste
 résumé n'est pas rejouable, donc pas réfutable : le lecteur suivant ne peut ni le refaire ni voir
 qu'il portait sur le mauvais périmètre. **Corollaire** : un geste écrit sans avoir été lancé est
 une hypothèse — le lancer d'abord, coller ce qu'il rend.
- **Un fait vit en un seul lieu, plus des pointeurs. Deux copies à deux âges se contredisent.** *(Règle mère ;
 cette fiche en est la source.)*
- **Une décision d'état RENVOIE à une règle de `CLAUDE.md`, elle ne la recopie jamais.** La copie
 vieillit seule, et l'ordre de chargement joue CONTRE le texte juste : on lit le `CLAUDE.md` puis
 l'état, et comme l'état porte le vivant on le croit le plus frais.
- **Une procédure vit à un seul endroit.** Cas particulier de la règle ci-dessus, appliqué au geste répété et non au fait. Quand une procédure justifie une fiche de compétence, elle y migre **entière** ; son emplacement d'origine ne garde que le déclencheur et un pointeur — jamais un résumé ni « les grandes lignes », qui redeviennent une seconde copie à un autre âge. **Les deux déclencheurs réunis** : répétition constatée sur plusieurs séances (une exécution unique ne prouve rien) ET procédure outillée et stabilisée — séquence fixe, pièges consignés. Séquence mouvante ou jouée une seule fois : elle reste où elle est.
- **Une ligne qui s'annonce transverse dans un document de PROJET et qui ne nomme pas sa remontée est un candidat de perte.** Quand on écrit dans le document de conception ou le `CLAUDE.md` d'un projet une leçon qui vaut au-delà de ce projet, la ligne porte sa mention de remontée — « remonté par la session X le <date> », « versé le <date> », « candidate ouverte » — sinon rien ne la ramènera jamais au système. Le niveau où la leçon est écrite ne prédit pas la perte ; **c'est l'absence de mention de remontée dans la ligne elle-même**, et ça, un `grep` le trouve.
- **Filtre d'admission en mémoire.** Un fait ne s'écrit que si son oubli ferait refaire une erreur, ou reposer une question déjà tranchée. « Intéressant » ne suffit pas.
- **Quand une correction devient une règle.** Faute qui a coûté du travail, de la crédibilité, ou qui a produit une erreur factuelle → promotion immédiate en règle. Simple préférence de forme → attendre une deuxième occurrence, qui prouve une position et non une humeur du jour.

## UN SEUL ÉCRIVAIN PAR NIVEAU

**Un niveau a UN chemin d'écriture, jamais deux.** S'il porte `ETAT.md`, c'est `etat.py add` : le
journal est la seule source, `ETAT.md` en est la projection, et l'éditer à la main est refusé au
commit (code 23). **Tout niveau vivant en porte un.**

Aucun niveau n'écrit dans un `MEMORY.md` de niveau : ceux qu'une migration a gardés sont gelés. Le
seul `MEMORY.md` vivant est l'index de la mémoire automatique.

**Ce que le régime à événements règle par construction** : un dû est un `du` ouvert, il sort de
l'état quand il est `fait` ou `abandonne`, et un abandon doit dire son `motif` — donc un retrait
n'est jamais indistinguable d'un oubli.

Cadence des écritures de reprise : compétence `reprise`, seule autorité.

## Écrire dans le document de conception, un `CLAUDE.md` ou une fiche de mémoire

**Avant la première écriture de la séance, lire en entier [`SOURCES_DE_VERITE.md`](SOURCES_DE_VERITE.md)** :
déclencheurs et relecture contradictoire du document de conception, porte d'entrée du règlement et
écriture d'un `CLAUDE.md`, cool-down d'une règle candidate et troc, gabarit d'une fiche de mémoire.
Le crochet refuse une fois la première de ces écritures tant qu'elle n'est pas lue.

## Rectifier sur une prémisse qu'on vient de changer est une écriture neuve

Le mot « correction » désarme la vérification, et c'est ce qui rend le geste insidieux. Rectifier une
ligne existante d'une source de vérité en s'appuyant sur une prémisse qu'on a soi-même changée dans la
même séance : la traiter comme une **écriture neuve**, soumise à la même exigence de preuve.

Signal opposable, et il est observable : **avoir inversé le même fait deux fois dans une séance
interdit d'écrire le troisième état dans une source de vérité avant mesure indépendante.**

Une telle rectification détruit un énoncé exact : le dégât vient de la correction, pas de l'erreur.

## Un chemin écrit est une promesse qu'il existe

Un chemin cité dans un document d'instruction affirme que la chose est là. Le futur (« ira dans
`X` ») et le passé (« `X` a disparu ») n'en dispensent pas : nommer la chose en clair, et n'écrire le
chemin que là où il existe au moment de l'écriture.

Le corollaire de repérage vit dans `fichiers-et-nommage/SUPPRIMER_DEPLACER.md`, § chasse aux pointeurs.

## Un geste interdit remonté par un pair : chercher ce qui le lui a prescrit

Refuser suffit à protéger ce coup-ci, et laisse la cause en place pour le suivant. Quand un pair
remonte un geste qu'une règle interdit, aller lire le document de son niveau : un fichier local peut
prescrire ce qu'une décision amont vient de renverser, et la cascade fait primer le plus spécifique.

Un refus répété sans recherche de cause laisse chaque session qui lit le même document local
reproduire le geste.

## Formes normalisées — le gabarit de chaque chose qu'on écrit

**Un gabarit par type de fichier, et il vit ici seul.** Ce qui n'est pas ci-dessous n'a pas de forme
imposée.

**ÉVÉNEMENT du journal** — pas un gabarit de prose mais le **contrat § 3.1**, transcrit en tête de
`engine/etat.py`, et `etat.py add` **refuse** (code 2) tout événement incomplet en nommant le champ
manquant. Il ne se recopie pas ici : la machine l'applique. Six types : `decision` · `du` ·
`pointeur` · `etat` · `seance` · `observation`. **Avant d'écrire une `decision` ou un `du`, lire
[`EXEMPLES_EVENEMENTS.md`](EXEMPLES_EVENEMENTS.md)** : quatre événements réussis, et pourquoi ils
le sont. Ce que la règle ajoute par-dessus :

- **`source` est un CHEMIN ou une COMMANDE, jamais une valeur.** Une valeur recopiée se périme, un
  chemin non. Le contrat l'exige sur `pointeur` et `observation` ; l'écrire partout où on l'a est
  toujours un gain.
- **`ref` est un identifiant, pas une phrase** — `u-<slug>` pour un dû, `d-<slug>` pour une
  décision, `p-<slug>` pour un pointeur : le sujet et non la date, et il tient dans le motif
  `RE_SLUG` d'`engine/etat.py`, seule autorité — la borne se relit là, elle ne se recopie pas. Un slug
  long tiré d'une question fait sonner l'alarme de secret du crochet.
- **`chantier` groupe ce qui se solde ensemble** : fermer un chantier (`etat --op ferme`) retire de
  l'état projeté ses pointeurs, donc il ne se nomme pas au hasard.
- **Un événement qui affirme l'ÉTAT d'un fichier porte en `source` la commande qui le mesure,
  jouée AVANT l'écriture.**
- **Un retrait dit son `motif`** — `abandonne`, `remplace`, `retire`. Sans lui, un retrait est
  indistinguable d'un oubli, et le contrat le refuse.
- **Un retrait oblige à purger `memory/REMINDERS.md` DANS LA FOULÉE**. Un retrait ne
  purge que le journal ; le démarrage, lui, lit `REMINDERS.md`, qu'`etat.py` ne connaît pas. Donc :
  chercher le rappel qui porte ce fil et le purger avec son bloc de purge, **le même jour**. Geste à
  la main, rien ne croise les deux sources.
- **Un fil s'ouvre pour un geste qui survit à la séance, par trois portes seulement** :
  l'utilisateur le demande ou le valide ; un tiers doit agir et on l'attend ; un geste à moi que la
  séance ne peut pas finir, le texte disant ce qui l'empêche. Ailleurs : un geste faisable se fait,
  avec une `observation` si la trace compte ; une idée ou une amélioration va à
  `memory/IDEES_FROIDES.md` ; une suite non demandée se propose en une ligne et ne s'ouvre que sur un
  oui.
- **Un fil EN ATTENTE PURE d'une date devient un rappel ⏰, pas un dû.** Critère, et il est strict :
  **aucun geste possible ni attendu avant la date** — un rendez-vous pris dont on attend le jour, un
  paiement dont le lien arrive à date. Un relevé quotidien, une routine, un geste faisable dès
  aujourd'hui gardent le dû. Geste : la ligne dans `memory/REMINDERS.md` (session principale), qui
  pointe la ref, puis `du --op abandonne` avec un motif qui nomme le rappel. Une session de projet ne
  touche pas `REMINDERS.md` : elle remonte à la principale. Au doute, le fil reste un dû.

**Texte d'un événement `pointeur`**, projeté dans `## Où trouver` — une **question**, puis la
réponse courte ; la `source` porte les chemins. Jamais un chiffre, une version, une date ni un
statut : c'est une carte de questions, pas un résumé.

```
- **<La question telle qu'on se la pose ?>** → <la réponse en une phrase>. `[<chemin> · <chemin>]`
```

Un chemin cité doit **exister** ; un renvoi de section se met entre parenthèses ou après `§`, jamais
collé au chemin — le contrôle hebdomadaire 45 lit tout ce qui suit le chemin comme faisant partie de lui.

**La borne d'un article projeté est une LIMITE, pas un budget** — `TEXTE_MAX_PROJETE` d'`engine/etat.py`, qui la porte. Un article projeté vise le plus COURT possible ; la borne est le plafond au-delà duquel `etat.py` refuse, pas la cible. La borne ne voit pas le nombre : dix décisions conformes, chacune près de la borne, ajoutent plus de 8 000 caractères à l'état projeté.

**Statut** — daté et sourcé, ou il n'est pas un statut :

```
<ÉTAT> le <AAAA-MM-JJ>, <ce qui l'établit>.
```

Trois états seulement, et ils ne se mélangent pas : **vérifié** (avec sa source), inféré, à
confirmer. Un statut sans date se lit comme vrai aujourd'hui, et c'est ainsi qu'un fait de juillet
gouverne une décision d'août.

**Intégrité des statuts** : ne jamais inscrire « implémenté » (ni « livré », « fait ») sur la seule
intention de conception. Le code correspondant doit exister et être vérifié au moment où le statut
est écrit. Décision conçue mais non codée → « à implémenter ». Au moindre doute sur l'état réel,
vérifier le code avant d'écrire le statut.

## Les archives sont GELÉES

**Une archive ne reçoit plus rien.** Une archive porte un en-tête de gel en première ligne — ce sont
les fichiers qu'une migration depuis une V1 ou une V2 a gelés ; le crochet (**code 24**) refuse toute
modification, levier tracé `FORCE_GELE="motif"`. Elles restent CHERCHÉES au `grep`, jamais chargées.

**Donc un récit qui doit quitter un document vivant ne s'archive plus : il devient un événement
`observation`** du journal du niveau, avec sa `source`. Il survit, il est cherchable, et il
n'encombre aucun état projeté. La procédure vit dans `skills/os-audit/HYGIENE.md`, geste « Hygiène
des mémoires », et elle vaut pour l'index de mémoire et ses fiches, seules mémoires vivantes.

- **Un fait intemporel ne se verse nulle part** — il va dans sa source de vérité, le document de
  conception ou le `CLAUDE.md` du bon niveau.
- **Les plafonds ne sont PAS l'affaire d'une séance.** Ne pas les mesurer, ne pas relayer une mesure, ne pas arbitrer un seuil, ne pas convertir une unité : **la passe mensuelle les compte, et elle seule**. Un pair qui remonte un dépassement reçoit la même réponse. **Seule exception** : le bilan d'une session de projet dit, en une ligne, que l'`ETAT.md` du niveau est au-dessus de son plafond ; le versement reste un dû daté du niveau. Un dépassement avertit, il ne désactive rien. **Et un CLIQUET refuse au commit (code 20)** — il se paie à l'ajout, `controles-et-alarmes` « Ce qui bloque et ce qui avertit ».
