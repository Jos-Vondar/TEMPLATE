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
- Toute entrée `MEMORY.md` de type « comportement voulu » doit pointer sa contrepartie **par le nom de sa section, jamais par un numéro** : `→ <document de conception> « <section> »`. *(Un renvoi par numéro meurt à la première renumérotation : 28 renvois d'un coup, payés une fois.)*
- Avant d'ajouter une règle émergente (bug, pattern, comportement découvert en session) dans un `CLAUDE.md` : choisir le bon niveau (racine / domaine / projet / app). Le trancher soi-même, sans agent.
- **Un fait calculable ne s'écrit pas, il se lit.** Nombre de contrôles, taille d'un fichier, liste de dossiers : pointer la source qui le porte au lieu d'en recopier la valeur. Un contrôle qui vérifie la concordance de trois copies est un pansement sur une décision d'écriture évitable (promue le 2026-07-25 ; deux occurrences : un compteur de contrôles inscrit en dur dans trois documents, faux le jour même ; puis un plafond du règlement affirmé par la fiche d'audit alors que le règlement l'avait abandonné, qui aurait fait conclure à un dépassement là où le système était conforme).
- **Une méthode se remonte au geste EXACT exécuté, jamais à sa version résumée** *(2026-09-09)*.
 Écrire la commande telle qu'elle a tourné, avec sa sortie, et non « j'ai vérifié que… ». Un geste
 résumé n'est pas rejouable, donc pas réfutable : le lecteur suivant ne peut ni le refaire ni voir
 qu'il portait sur le mauvais périmètre. **Corollaire** : un geste écrit sans avoir été lancé est
 une hypothèse — le lancer d'abord, coller ce qu'il rend.
- **Un fait vit en un seul lieu, plus des pointeurs. Deux copies à deux âges se contredisent.**
 *(Règle mère : elle se convoque au moment d'écrire un fait, donc par cette fiche, et n'a pas à être
 payée à chaque session. Cette fiche en est la source.)*
- **Une décision d'état RENVOIE à une règle de `CLAUDE.md`, elle ne la recopie jamais.** La copie
 vieillit seule, et l'ordre de chargement joue CONTRE le texte juste : on lit le `CLAUDE.md` puis
 l'état, et comme l'état porte le vivant on le croit le plus frais. *(Sur pièce : deux textes de la
 MÊME date, une décision disait l'inverse du `CLAUDE.md` de son niveau sur qui écrit où.)*
- **Une procédure vit à un seul endroit.** Cas particulier de la règle ci-dessus, appliqué au geste répété et non au fait. Quand une procédure justifie une fiche de compétence, elle y migre **entière** ; son emplacement d'origine ne garde que le déclencheur et un pointeur — jamais un résumé ni « les grandes lignes », qui redeviennent une seconde copie à un autre âge. **Les deux déclencheurs réunis** : répétition constatée sur plusieurs séances (une exécution unique ne prouve rien) ET procédure outillée et stabilisée — séquence fixe, pièges consignés. Séquence mouvante ou jouée une seule fois : elle reste où elle est.
- **Une ligne qui s'annonce transverse dans un document de PROJET et qui ne nomme pas sa remontée est un candidat de perte.** Quand on écrit dans le document de conception ou le `CLAUDE.md` d'un projet une leçon qui vaut au-delà de ce projet, la ligne porte sa mention de remontée — « remonté par la session X le <date> », « versé le <date> », « candidate ouverte » — sinon rien ne la ramènera jamais au système. Le niveau où la leçon est écrite ne prédit pas la perte ; **c'est l'absence de mention de remontée dans la ligne elle-même**, et ça, un `grep` le trouve. *(Mesuré sur 5 affirmations transverses d'un même domaine, suivies au bout : **4 arrivées, 1 perdue**, les 4 arrivées portant leur mention. L'énoncé a été affaibli deux fois par la mesure. Réserve : 5 cas d'un seul domaine.)*
- **Filtre d'admission en mémoire.** Un fait ne s'écrit que si son oubli ferait refaire une erreur, ou reposer une question déjà tranchée. « Intéressant » ne suffit pas.
- **Quand une correction devient une règle.** Faute qui a coûté du travail, de la crédibilité, ou qui a produit une erreur factuelle → promotion immédiate en règle. Simple préférence de forme → attendre une deuxième occurrence, qui prouve une position et non une humeur du jour.

## UN SEUL ÉCRIVAIN PAR NIVEAU

**Un niveau a UN chemin d'écriture, jamais deux.** S'il porte `ETAT.md`, c'est `etat.py add` : le
journal est la seule source, `ETAT.md` en est la projection, et l'éditer à la main est refusé au
commit (code 23). **Tout niveau vivant en porte un.**

**Ce que le régime à événements règle par construction** : un dû est un `du` ouvert, il sort de
l'état quand il est `fait` ou `abandonne`, et un abandon doit dire son `motif` — donc un retrait
n'est jamais indistinguable d'un oubli.

Cadence des écritures de reprise : compétence `reprise`, seule autorité.

## Sources de vérité — le document de conception

- Déclencheurs d'écriture immédiate : confirmation explicite (« oui c'est voulu », « on garde », « validé »), correction sur un comportement du système, réponse tranchée à une clarification.
- **Écrire directement.** Ni agent imposé, ni relecture par un second agent : elles trouvent de vrais défauts, mais leur coût par séance dépasse ce qu'elles évitent, et elles rendent la moindre écriture cérémonieuse. Ce qui les remplace : `weekly-check.sh` et la passe mensuelle `os-audit`. **Cette passe ne cherche pas ces défauts dans les documents du système** — perte de règle par réécriture, contradiction interne, doublon, statut sans preuve — sauf quand une friction vécue les révèle, ou qu'ils touchent le travail : perte assumée.
- Ce qui reste dû à chaque écriture, parce que ça ne se rattrape pas : vérifier un statut avant de l'écrire (ci-dessous), et ne pas perdre une règle en réécrivant un passage qui la portait.
- **Relecture contradictoire : proposée, jamais imposée.** Elle reste disponible et se propose quand l'enjeu le mérite, avec le motif en une ligne. Trois cas où je dois la proposer plutôt qu'y penser : quand la réécriture **remplace** un passage qui portait des règles, au lieu d'en ajouter un — c'est là qu'une règle se perd sans bruit ; quand j'ai à la fois décidé et écrit, donc que personne n'a lu le texte avec un autre œil ; et quand le texte fixe un comportement dont un tiers dépendra. Hors de ces cas, écrire et passer. L'utilisateur peut toujours la refuser.
- **Intégrité des statuts** : ne jamais inscrire « implémenté » (ni « livré », « fait ») sur la seule intention de conception. Le code correspondant doit exister et être vérifié au moment où le statut est écrit. Décision conçue mais non codée → « à implémenter ». Au moindre doute sur l'état réel, vérifier le code avant d'écrire le statut.

## Rectifier sur une prémisse qu'on vient de changer est une écriture neuve

Le mot « correction » désarme la vérification, et c'est ce qui rend le geste insidieux. Rectifier une
ligne existante d'une source de vérité en s'appuyant sur une prémisse qu'on a soi-même changée dans la
même séance : la traiter comme une **écriture neuve**, soumise à la même exigence de preuve.

Signal opposable, et il est observable : **avoir inversé le même fait deux fois dans une séance
interdit d'écrire le troisième état dans une source de vérité avant mesure indépendante.**

Motif, sur pièce : un pair a inversé le même fait deux fois en une séance, chaque fois en invoquant une
mesure de l'utilisateur et chaque fois avec assurance. Sa rectification a détruit un énoncé exact vieux
de onze jours — le dégât est venu de la correction, pas de l'erreur.

## Un chemin écrit est une promesse qu'il existe

Un chemin cité dans un document d'instruction affirme que la chose est là. Le futur (« ira dans
`X` ») et le passé (« `X` a disparu ») n'en dispensent pas : nommer la chose en clair, et n'écrire le
chemin que là où il existe au moment de l'écriture.

Motif, sur pièce : le 2026-08-22, trois fois le même jour, relevé chaque fois par le contrôle hebdomadaire 27 de
l'autotest — une destination annoncée pour un déplacement à venir, un document citant deux fois un
dossier déjà déplacé dont mon premier repérage n'avait vu qu'une occurrence, et une règle réécrite
pour dire qu'une copie avait disparu. Le troisième cas est celui qui fait la règle : le récit au
passé sonne comme les deux autres, et le contrôle sonne pareil.

*Le contrôle hebdomadaire 27 attrape le défaut, mais après l'écriture et en fin de sauvegarde ; la
règle évite l'aller-retour. Le corollaire de repérage vit dans `fichiers-et-nommage`, § chasse aux
pointeurs.*

## Un geste interdit remonté par un pair : chercher ce qui le lui a prescrit

Refuser suffit à protéger ce coup-ci, et laisse la cause en place pour le suivant. Quand un pair
remonte un geste qu'une règle interdit, aller lire le document de son niveau : un fichier local peut
prescrire ce qu'une décision amont vient de renverser, et la cascade fait primer le plus spécifique.

Motif, sur pièce : deux sessions ont remonté le même geste interdit le même jour, chacune obéissant
correctement au pied de commentaire du document de son niveau, qui le prescrivait à trois endroits et
avait été périmé quelques heures plus tôt par une décision prise ailleurs. Un refus répété sans
recherche de cause a produit deux occurrences au lieu d'une.

## Formes normalisées — le gabarit de chaque chose qu'on écrit

*(Elle vit ici et non dans une compétence à part : le déclencheur de la question « comment garantir
que ce qui s'écrit est normalisé » EST celui de cette fiche, et une fiche de plus dédoublerait un
déclencheur.)*

**Un gabarit par type de fichier, et il vit ici seul.** Ce qui n'est pas ci-dessous n'a pas de forme
imposée. Le contrôle 29bis de `weekly-check.sh` balaie ces formes une fois par semaine.

**ÉVÉNEMENT du journal** — pas un gabarit de prose mais le **contrat § 3.1**, transcrit en tête de
`engine/etat.py`, et `etat.py add` **refuse** (code 2) tout événement incomplet en nommant le champ
manquant. Il ne se recopie pas ici : la machine l'applique. Six types : `decision` · `du` ·
`pointeur` · `etat` · `seance` · `observation`. Ce que la règle ajoute par-dessus :

- **`source` est un CHEMIN ou une COMMANDE, jamais une valeur.** Une valeur recopiée se périme, un
  chemin non. Le contrat l'exige sur `pointeur` et `observation` ; l'écrire partout où on l'a est
  toujours un gain.
- **`ref` est un identifiant, pas une phrase** : le sujet et non la date, et il tient dans le motif
  `RE_SLUG` d'`engine/etat.py`, seule autorité — la borne se relit là, elle ne se recopie pas. Un
  slug long tiré d'une question a déjà fait sonner l'alarme de secret du crochet.
- **`chantier` groupe ce qui se solde ensemble** : fermer un chantier (`etat --op ferme`) retire de
  l'état projeté ses pointeurs, donc il ne se nomme pas au hasard.
- **Un événement qui affirme l'ÉTAT d'un fichier porte en `source` la commande qui le mesure,
  jouée AVANT l'écriture.** Le 2026-09-09, deux pointeurs annonçaient « GELÉ » sur des archives
  qui ne l'étaient pas.
- **Un retrait dit son `motif`** — `abandonne`, `remplace`, `retire`. Sans lui, un retrait est
  indistinguable d'un oubli, et le contrat le refuse.
- **Un retrait oblige à purger `memory/REMINDERS.md` DANS LA FOULÉE** *(2026-09-16)*. Un retrait ne
  purge que le journal ; le démarrage, lui, lit `REMINDERS.md`, qu'`etat.py` ne connaît pas. Donc :
  chercher le rappel qui porte ce fil et le purger avec son bloc de purge, **le même jour**. Geste à
  la main, rien ne croise les deux sources.

**Fiche de mémoire automatique** (`memory/<prefixe>_<sujet>.md`) — le préfixe du nom et le `type`
du frontmatter disent **la même chose**, sinon l'un des deux ment :

| Préfixe | `type:` | Ce que la fiche porte |
| :--- | :--- | :--- |
| `user_` | `user` | qui est l'utilisateur — rôle, préférences, matériel |
| `proj_` | `project` | un chantier en cours, ses contraintes, son état |
| `env_` | `reference` | comment marche une pièce de l'environnement |
| `ref_` | `reference` | un pointeur vers une ressource externe |

```
---
name: <slug-en-minuscules-avec-tirets>
description: "<une ligne : ce que la fiche répond, pas ce qu'elle contient>"
metadata:
 node_type: memory
 type: <user|project|reference>
---
```

**Texte d'un événement `pointeur`**, projeté dans `## Où trouver` — une **question**, puis la
réponse courte ; la `source` porte les chemins. Jamais un chiffre, une version, une date ni un
statut : c'est une carte de questions, pas un résumé.

```
- **<La question telle qu'on se la pose ?>** → <la réponse en une phrase>. `[<chemin> · <chemin>]`
```

Un chemin cité doit **exister** ; un renvoi de section se met entre parenthèses ou après `§`, jamais
collé au chemin — le contrôle hebdomadaire 45 lit tout ce qui suit le chemin comme faisant partie de lui.

**La borne d'un article projeté est une LIMITE, pas un budget** — `TEXTE_MAX_PROJETE` d'`engine/etat.py`, qui la porte. Un article projeté vise le plus COURT possible ; la borne est le plafond au-delà duquel `etat.py` refuse, pas la cible. Mesure qui l'a imposé : dix décisions écrites près de la borne en six jours, toutes conformes, **+8 387 caractères** — la borne ne voit pas le nombre.

**Statut** — daté et sourcé, ou il n'est pas un statut :

```
<ÉTAT> le <AAAA-MM-JJ>, <ce qui l'établit>.
```

Trois états seulement, et ils ne se mélangent pas : **vérifié** (avec sa source), inféré, à
confirmer. Un statut sans date se lit comme vrai aujourd'hui, et c'est ainsi qu'un fait de juillet
gouverne une décision d'août.

## Les archives sont GELÉES

**Une archive ne reçoit plus rien.** Une archive porte un en-tête de gel en première ligne — ce sont
les fichiers qu'une migration depuis une V1 ou une V2 a gelés ; le crochet (**code 24**) refuse toute
modification, levier tracé `FORCE_GELE="motif"`. Elles restent CHERCHÉES — au
`grep`, et par `engine/index-fts.py` qui indexe les fichiers gelés — jamais chargées.

**Donc un récit qui doit quitter un document vivant ne s'archive plus : il devient un événement
`observation`** du journal du niveau, avec sa `source`. Il survit, il est cherchable, et il
n'encombre aucun état projeté. La procédure vit dans `skills/os-audit/HYGIENE.md`, geste « Hygiène
des mémoires », et elle vaut pour l'index de mémoire et ses fiches, seules mémoires vivantes.

- **Un fait intemporel ne se verse nulle part** — il va dans sa source de vérité, le document de
  conception ou le `CLAUDE.md` du bon niveau.
- **Les plafonds ne sont PAS l'affaire d'une séance.** Ne pas les mesurer, ne pas relayer une mesure, ne pas arbitrer un seuil, ne pas convertir une unité : **la passe mensuelle les compte, et elle seule**. Un pair qui remonte un dépassement reçoit la même réponse. Un dépassement avertit, il ne désactive rien. **Exception : un CLIQUET refuse au commit (code 20)** — il se paie à l'ajout, `controles-et-alarmes` « Ce qui bloque et ce qui avertit ».

## Écriture dans un `CLAUDE.md`

- **Au niveau racine, une règle de l'utilisateur s'écrit dans « Mes règles », HORS du bloc d'imports.** Le bloc est réécrit par `engine/appliquer-reponses.py`, et les fragments qu'il importe appartiennent au template : ni l'un ni les autres ne reçoivent une règle à la main. Persona et « Mes domaines » sont à l'utilisateur, eux aussi hors du bloc.
- Uniquement des règles. Jamais de narratif, de résumé ni d'explication. **UNE EXCEPTION, et elle est étroite** : une **parenthèse de récit datée** qui PROUVE la règle qu'elle suit est admise — elle empêche de la rejouer à l'envers. Elle reste une parenthèse, après la règle, jamais à sa place.
- **Pas d'audit après modification.** Une règle modifiée entre en vigueur telle quelle. Motif : chaque correctif déclenchait un nouvel audit, qui produisait un correctif, sans terme.
- Quand `REGLES_A_FROID=oui`, le troc se paie **dans la monnaie de la couche cible** : énoncé dans le fragment `regles-a-froid-oui` du règlement, geste par couche dans `skills/os-audit/HYGIENE.md`, geste « Règles candidates ». Ne pas le recopier ici : l'appliquer à l'ajout.
- L'index de mémoire n'est pas relu au fil de l'eau : l'hygiène des mémoires est due à la passe mensuelle.
