---
name: reprise
description: "Savoir QUAND écrire l'état de reprise d'un niveau — bascule annoncée, palier franchi, source de vérité modifiée, décision tranchée — et clôturer une séance : les trois gestes, l'entrée de séance, la sauvegarde. La forme d'un événement `etat.py add` relève de `memoire-et-verite`, pas d'ici."
---

## Quand

**Quatre déclencheurs, et eux seuls** : une source de vérité modifiée (le document de
conception, un `CLAUDE.md`, l'index `memory/MEMORY.md`) · une décision que l'utilisateur vient de trancher · une bascule
qu'il annonce (« on fait un aparté », « on passe à autre chose ») · un palier franchi dans un
chantier. Plus le signal de fin, qui déclenche les trois gestes de la dernière section.

**LE DISCRIMINANT, à trancher avant d'écrire quoi que ce soit** : le niveau porte `ETAT.md` →
**un seul geste, `etat.py add`** ; il n'en porte pas → ce n'est pas encore un niveau : le monter
d'abord (`nouveau-projet`).

**Niveau à `ETAT.md` — UN SEUL ÉCRIVAIN** (`memoire-et-verite`). À chaque déclencheur, un
événement et rien d'autre : `decision` pour ce que l'utilisateur vient de trancher, `du` pour ce
qui s'ouvre ou se solde, `etat --op avance` pour un palier, `pointeur` pour où retrouver une
chose, `observation` pour un récit qui doit survivre sans encombrer l'état.

**Avant le premier `etat.py add` de la séance, charger AUSSI `memoire-et-verite`** : elle porte la
forme d'un événement et l'intégrité des statuts, et le crochet refuse l'écriture sans elle. Cette
fiche dit quand et où écrire, l'autre comment l'écrire juste.

⚠️ **Le texte d'un événement ne porte JAMAIS d'accent grave**. Entre guillemets, le
shell y voit une substitution : la commande citée **s'exécute** et sa sortie entre dans l'événement.
Le journal est append-only, donc la faute est permanente. Citer sans délimiteur. La borne `TEXTE_MAX`
d'`etat.py` est un filet, pas la protection : le shell a déjà substitué quand elle refuse.

Seule la **sauvegarde** attend le signal de fin.

Le discriminant est **ce qu'une interruption rendrait coûteux à reconstruire**, et il s'observe
sans jugement.

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

## Quoi

**L'état complet et frais du niveau.** Pas un journal des tours de parole : ce qu'il faut savoir
pour reprendre demain sans avoir la conversation. **Le texte d'un événement doit les
règles ci-dessous.**

- **Ce qui est vérifié, et par quoi**, étiqueté selon les trois états de `memoire-et-verite`,
  § Formes normalisées. Un statut embelli est le seul défaut qu'une reprise ne pardonne pas : elle
  sera lue comme un fait.
- **RÉÉMETTRE SANS REMESURER, C'EST AFFIRMER**. Deux
  formes, une seule mécanique : **relayer** un fait non mesuré à un lecteur le transforme en fait
  ÉTABLI — c'est le relais qui le rend faux, pas la source ; et **reconduire** un statut dans un
  état neuf **REMET SA DATE À NEUF**, donc le statut périmé cesse de vieillir et cesse de paraître
  suspect. Un faux de la veille se démasque ; un faux redaté d'aujourd'hui ne se démasque plus.
  **Donc chaque statut reconduit se recontrôle, pas seulement le fait neuf qu'on ajoute.**
- **Ce qui est dû et ne l'est pas.** Nommer ce qui reste, sans le présenter comme entamé.
- **Un `du` est un engagement : il nomme son prochain geste et qui le fait** — moi, l'utilisateur,
  ou un tiers dont on attend la réponse, alors écrit « attente de ». Sinon il va ailleurs : une idée
  dans `IDEES_FROIDES.md`, un constat en `observation`, un renvoi en `pointeur`.
  **Ce « qui » se pose aussi en champ : `--porteur utilisateur|assistant|tiers`** sur tout `ouvre`
  ou `remplace`, celui du PROCHAIN geste, un seul. C'est lui, et non le texte, qui range le fil dans
  le groupe « À toi » du bilan. Quand le geste passe d'une main à l'autre, reformuler avec le nouveau
  porteur ; une reformulation qui l'omet garde le dernier connu.
- **Une décision arbitrée entre dans la liste de travail, ou elle n'existe pas**.
  Elle devient un `du` ou une `decision` **dans le geste où elle est rendue**, jamais plus tard :
  laissée dans la conversation, elle meurt au prochain contexte.
- **Une décision retournée dans la même séance ne laisse qu'UNE entrée**. `--op
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
  que le pointeur.
- **Anonymat**, parce que le journal part au dépôt en régime GitHub : aucun identifiant, aucune donnée
  personnelle, aucun verbatim client, projets désignés par leurs codes.
- **Expurger tout secret** : ni clé, ni jeton, ni mot de passe, même partiel.

### L'identifiant de fil

**Un fil qui va durer plus d'une séance garde le même `--ref` d'une séance à l'autre, quelle que
soit sa reformulation** : sans lui, un fil reformulé repart à zéro et perd son ancienneté. La forme
de la ref vit dans `memoire-et-verite`, § Formes normalisées.

## Les trois gestes de la clôture

Sur signal de fin (« on arrête », « c'est tout pour aujourd'hui »), dans cet ordre. Les deux
premiers ont déjà tourné à chaque déclencheur (§ Quand) ; ce qui change à la clôture est **jusqu'où
ils écrasent**, et que le troisième s'ajoute.

**1.** un événement `seance` : le récit, **terminé par `PROCHAIN : <geste>`**, une phrase sous
250 caractères — le démarrage suivant l'extrait pour ouvrir « À faire aujourd'hui » ; sans geste
engagé, `PROCHAIN : aucun engagé` —, plus **`manque_reprise` et `manque_declencheur`**, entiers
≥ 0, ou la chaîne `non relu` pour une séance dont on n'a pas relu les gestes — **jamais 0 pour
dire qu'on n'a pas regardé**. Un manque de reprise nomme la chose
demandée et le fichier qui aurait dû la porter ; un manque de DÉCLENCHEUR nomme la compétence, le
geste qu'elle couvrait, ce qui a été fait à la place, et donne une ligne à
`memory/ROUTING_MISSES.md`, en `MULTIDOMAINE=oui`, **seulement s'il n'a pas été rattrapé par le
refus unique du crochet** — un raté rattrapé se compte dans la `seance` et nulle part ailleurs, il
ne se remonte pas à la principale. **Avant de l'écrire, lire [`EXEMPLE_SEANCE.md`](EXEMPLE_SEANCE.md)** :
la forme d'une séance réussie, et pourquoi elle l'est. **2.** `etat.py projette --niveau <niveau>`.
**3.** la sauvegarde, `bash ~/.claude/engine/claudeos-cloture.sh`, geste de la session principale.
**Avant de la lancer, lire en entier [`CLOTURE_PRINCIPALE.md`](CLOTURE_PRINCIPALE.md)** : régime
sans git, préfixe `CLAUDEOS_NATURE`, constat des sessions ouvertes, retard des dépôts, lecture du
verdict. Le crochet refuse une fois le lancement tant qu'elle n'est pas lue.

**Session de PROJET : la clôture finit en fermant sa session**, la principale jamais. **Avant ce
dernier appel d'outil, lire en entier [`FERMETURE_PROJET.md`](FERMETURE_PROJET.md)** : ses deux
conditions et la commande à lancer. Le crochet refuse une fois toute fermeture de session tant
qu'elle n'est pas lue.

**Le récit de séance s'écrit brut, sans travail de rédaction**. Il doit exister, et
il est anonyme au même titre que le reste.

Fin d'une séance de conception (brainstorm, entretien contradictoire) : écrire aussi l'état du
niveau concerné, pour permettre la reprise.

**Ne pas rejouer ici ce qui est dû à la passe mensuelle** — hygiène des mémoires, plafonds,
ratés de routage, revue des rappels. Dues à la passe mensuelle (`os-audit`), pas supprimées : **la
clôture ne rejoue aucun contrôle de la passe**. Une clôture qui se met à contrôler devient une cérémonie.
