---
name: reprise
description: "Écrire l'état de reprise d'un niveau — bascule annoncée, palier franchi, source de vérité modifiée, décision tranchée, ou clôture de séance. Porte aussi les trois gestes de clôture, l'entrée de journal, et l'écriture d'un événement `etat.py add` sur un niveau à `ETAT.md`."
---

> Un niveau qui porte `ETAT.md` n'écrit pas de fichier d'état : il ajoute des ÉVÉNEMENTS à son
> journal, et `ETAT.md` en est la projection.

## Quand

**Quatre déclencheurs, et eux seuls** : une source de vérité modifiée (le document de
conception, un `CLAUDE.md`, l'index `memory/MEMORY.md`) · une décision que l'utilisateur vient de trancher · une bascule
qu'il annonce (« on fait un aparté », « on passe à autre chose ») · un palier franchi dans un
chantier. Plus le signal de fin, qui déclenche les trois gestes de la dernière section.

**LE DISCRIMINANT, à trancher avant d'écrire quoi que ce soit** : le niveau porte `ETAT.md` →
**un seul geste, `etat.py add`** ; il n'en porte pas → ce n'est pas encore un niveau : le monter
d'abord (`nouveau-projet`).

**Niveau à `ETAT.md` — UN SEUL ÉCRIVAIN.** À chaque déclencheur, un
événement et rien d'autre : `decision` pour ce que l'utilisateur vient de trancher, `du` pour ce
qui s'ouvre ou se solde, `etat --op avance` pour un palier, `pointeur` pour où retrouver une
chose, `observation` pour un récit qui doit survivre sans encombrer l'état. **Ne jamais écrire
`ETAT.md` à la main** : c'est une projection, et le crochet refuse le commit (code 23).

⚠️ **Le texte d'un événement ne porte JAMAIS d'accent grave** *(2026-09-09)*. Entre guillemets, le
shell y voit une substitution : la commande citée **s'exécute** et sa sortie entre dans l'événement.
Le journal est append-only, donc la faute est permanente. Citer sans délimiteur. La borne `TEXTE_MAX`
d'`etat.py` est un filet, pas la protection : le shell a déjà substitué quand elle refuse.

Seule la **sauvegarde** attend le signal de fin.

Le discriminant est **ce qu'une interruption rendrait coûteux à reconstruire**, et il s'observe
sans jugement. Il remplace « à chaque action significative », formule qui coexistait avec
« palier » et produisait deux cadences selon le modèle qui lisait la fiche.

Ce qui **ne** déclenche pas : un tour de conversation, une lecture, une recherche, une
compilation. Un fait déjà écrit sur disque — un plan, une spec — est déjà à l'abri : il n'a
pas besoin d'une seconde trace.

## Écrire en session, pas par agent

**Écrire directement, dans la session qui détient le contexte.** Voie par défaut, et la seule
dans presque tous les cas.

**Le critère n'est pas la taille du delta, c'est l'état du contexte de la session.** Tant qu'elle
a de la place, écrire soi-même coûte une lecture ; déléguer coûte un brief qui décrit tout ce que
l'exécutant ignore, plus sa relecture — presque toujours le plus cher. **Déléguer** garde un seul
usage : la session est près de sa limite et il reste une reprise à écrire ; le brief porte alors
**tout**, faits, état de vérification, ce qui est dû et ce qui ne l'est pas.

Test opposable, dans les deux sens : **si je peux nommer les éditions, je les fais ; si je dois
décrire un état de fin pour qu'un autre le compose, je délègue.**

## Où

Un ÉVÉNEMENT au journal du niveau touché :

| Ce sur quoi la séance a porté | Où ça s'écrit |
| :--- | :--- |
| Système, méta, configuration | `etat.py add --niveau ~/.claude` |
| Travail d'un domaine | `etat.py add --niveau <dossier du niveau>` — sous `~/<NOM>` en `GIT=par-domaine`, sous `~/.claude/travail/<NOM>` en `GIT=unique` ou `GIT=aucun` |
| Séance à plusieurs niveaux | un par niveau, jamais un seul qui les mélange |

Jamais un dossier temporaire : le journal du niveau est le seul lieu qui survit à la session.
Cette fiche est la seule autorité de la forme de ces écritures.

## Quoi

**L'état complet et frais du niveau.** Pas un journal des tours de parole : ce qu'il faut savoir
pour reprendre demain sans avoir la conversation. **Le texte d'un événement doit les
règles ci-dessous.**

- **Ce qui est vérifié, et par quoi.** Étiqueter vérifié (avec sa source), inféré,
  à confirmer. Un statut embelli est le seul défaut qu'une reprise ne pardonne pas : elle
  sera lue comme un fait.
- **RÉÉMETTRE SANS REMESURER, C'EST AFFIRMER** *(2026-09-10, payé deux fois en deux jours)*. Deux
  formes, une seule mécanique : **relayer** un fait non mesuré à un lecteur le transforme en fait
  ÉTABLI — c'est le relais qui le rend faux, pas la source ; et **reconduire** un statut dans un
  état neuf **REMET SA DATE À NEUF**, donc le statut périmé cesse de vieillir et cesse de paraître
  suspect. Un faux de la veille se démasque ; un faux redaté d'aujourd'hui ne se démasque plus.
  **Donc chaque statut reconduit se recontrôle, pas seulement le fait neuf qu'on ajoute.**
- **Ce qui est dû et ne l'est pas.** Nommer ce qui reste, sans le présenter comme entamé.
- **Une décision arbitrée entre dans la liste de travail, ou elle n'existe pas** *(2026-09-09)*.
  Elle devient un `du` ou une `decision` **dans le geste où elle est rendue**, jamais plus tard :
  laissée dans la conversation, elle meurt au prochain contexte.
- **Une décision retournée dans la même séance ne laisse qu'UNE entrée** *(2026-09-09)*. `--op
  remplace --remplace <ancienne ref>` le fait seul — deux entrées contradictoires du même jour font
  relire la mauvaise une fois sur deux.
- **Référencer par chemin**, jamais recopier. Un plan, un document de conception vivent ailleurs ;
  deux copies à deux âges se contredisent, et c'est ce fichier qui vieillit le plus vite.
- **Et ne rien y CRÉER de réutilisable non plus.** La clause ci-dessus interdit de copier ici ce qui
  vit ailleurs ; celle-ci interdit d'y écrire ce qui devrait vivre ailleurs — une procédure, un piège
  d'outil, une convention. **La projection `ETAT.md` est réécrite à chaque
  projection, et relue à la seule reprise de son niveau. Un savoir qu'on y dépose disparaît au prochain
  remplacement, ou survit sans jamais être relu — dans les deux cas il est perdu pour le reste du
  système. Il va dans la source de vérité du niveau, ou dans une compétence ; la reprise n'en garde
  que le pointeur. *(Trois occurrences, toutes sur un seul niveau : la réserve reste.)*
- **Anonymat**, parce que le journal part au dépôt en régime GitHub : aucun identifiant, aucune donnée
  personnelle, aucun verbatim client, projets désignés par leurs codes.
- **Expurger tout secret** : ni clé, ni jeton, ni mot de passe, même partiel.

### L'identifiant de fil

**Un fil qui va durer plus d'une séance porte un identifiant** : le `--ref` de son événement —
`u-<slug>` pour un dû, `d-<slug>` pour une décision, `p-<slug>` pour un pointeur —, obligatoire par
contrat. Le même fil garde le même identifiant d'une séance à l'autre, **quelle que soit sa
reformulation** : sans lui, un fil reformulé repart à zéro et perd son ancienneté. **Court** — un
identifiant, pas une phrase ; la borne se relit dans `RE_SLUG` d'`engine/etat.py`.

## Les trois gestes de la clôture

Sur signal de fin (« on arrête », « c'est tout pour aujourd'hui »), dans cet ordre. Les deux
premiers ont déjà tourné à chaque déclencheur (§ Quand) ; ce qui change à la clôture est **jusqu'où
ils écrasent**, et que le troisième s'ajoute.

**1.** un événement `seance` : le récit, plus **`manque_reprise` et
`manque_declencheur`**, entiers ≥ 0, ou la chaîne `non relu` pour une séance dont on n'a pas relu
les gestes — **jamais 0 pour dire qu'on n'a pas regardé**. Un manque de reprise nomme la chose
demandée et le fichier qui aurait dû la porter ; un manque de DÉCLENCHEUR nomme la compétence, le
geste qu'elle couvrait, ce qui a été fait à la place, et donne une ligne à
`memory/ROUTING_MISSES.md`. **2.** `etat.py projette --niveau <niveau>`. **3.** la sauvegarde.

**3. Sauvegarde** — `bash ~/.claude/engine/claudeos-cloture.sh`. Il projette chaque
niveau à événements, contrôle le rangement des secrets, puis, en régime GitHub, committe et pousse
**tous les dépôts** de `claudeos_repos`. Lire ce qu'il dit : une alarme qui mord arrête tout, et le
dépôt système n'est alors pas sauvegardé. *(Il refuse de tourner si un shim de crochet manque — un
shim absent est muet, le dépôt committerait sans aucune alarme. `bash ~/.claude/engine/install-poste.sh`
les repose.)* **En `GIT=aucun`, rien ne sort du poste** : la clôture contrôle les fichiers changés
depuis la précédente, réécrit les empreintes de `.claudeos/` si les contrôles passent, et le dit —
« RIEN N'EST SORTI DU POSTE ». Un refus n'y réécrit rien, et son levier `FORCE_…` se pose sur la
clôture.

**AVANT le troisième geste : demander aux sessions de projet ouvertes si elles ont fini d'écrire.**
`claudeos-session.sh --list`, puis un message à chacune, et attendre la réponse. La sauvegarde committe
l'arbre **tel qu'il est à cet instant** : lancée pendant qu'une session écrit, elle capte certains
de ses fichiers dans leur état final et d'autres dans un état intermédiaire — le dépôt porte alors
deux fichiers du même commit qui se contredisent, **la version alarmante étant la fausse**. **Aucun
contrôle mécanique n'est à armer pour ça** : c'est une question à poser, pas un garde.

**`git status` dit qui a écrit, et c'est plus sûr que la question** — sans git,
`python3 ~/.claude/engine/regime.py changes ~/.claude`. Le lot nomme les fichiers modifiés depuis
le dernier commit, ou la dernière clôture, donc les sessions qui ont travaillé. Si le lot ne contient que
les fichiers d'une session qui a confirmé avoir fini, **le risque est nul quel que soit le nombre de
sessions ouvertes**. La question reste utile pour ce qui n'a pas encore touché le disque.

**À trois sessions ou plus, ne pas attendre que TOUTES aient fini — ça peut ne jamais converger.**
Le lot de chacune est propre à un instant ; le lot global ne l'est peut-être jamais. Demander à
toutes, pousser dès que celles qui ont des fichiers dans le lot ont répondu, et accepter qu'une
session qui reprend ensuite fournira un second lot.

**Commencer par les fichiers de STATUT, pas par le code** : un fichier de statut est réécrit
**après** le geste qu'il décrit, donc il se stabilise en dernier — donc c'est lui qui mentira.

**La garde réduit le risque, elle ne l'annule pas** : l'état du dépôt se lit AVANT de lancer le
script, qui met ensuite une dizaine de secondes. Après un commit, relire l'état — un fichier qui
redevient modifié aussitôt signale une session encore active. **Et si la coupure a déjà eu lieu** :
recommitter, mais contrôler d'abord fichier par fichier ce qui diffère du dépôt ; une session qui
rapporte « seul tel fichier est à recommitter » se recontrôle, comme tout rapport de vérification.

**La sauvegarde est le dernier geste : elle clôt l'écriture.** Son verdict se lit par
`git -C <dépôt> log -1`, ou sans git par la sortie de la clôture ; il ne se recopie nulle part — recopié dans la reprise, il fabriquait un
changement de plus et relançait le crochet, donc deux commits et deux batteries par clôture.

**Le récit de séance s'écrit brut, sans travail de rédaction** *(2026-07-27)*. Il doit exister, et
il est anonyme au même titre que le reste.

Fin d'une séance de conception (brainstorm, entretien contradictoire) : écrire aussi l'état du
niveau concerné, pour permettre la reprise.

**Ne pas rejouer ici ce qui est dû à la passe mensuelle** — hygiène des mémoires, plafonds,
ratés de routage, revue des rappels. Dues ailleurs (`session`), pas supprimées.
