---
name: tri-des-fils
description: Trier ou nettoyer les fils d'un niveau ; le bilan dit « Tri des fils : DÛ ».
---

# Trier les fils d'un niveau

> L'échéance, son seuil et le filet mensuel se calculent dans `engine/lib_tri.py`, seule source ; le
> bilan de session de projet l'affiche, la passe mensuelle la lit (`skills/os-audit/HYGIENE.md`).

**Périmètre : le niveau de la session et ses dus ouverts, dormants compris.** Une session de projet
trie son niveau ; la principale trie un niveau qu'on lui nomme. Un niveau racine de dépôt ne trie que
ses propres dus, pas ceux de ses projets. L'hygiène des décisions, des pointeurs et des documents
trop chargés relève d'`os-audit`, geste « Hygiène des mémoires ».

## 1. Entrer

- **Par le bilan** (« Tri des fils : DÛ ») : une question `AskUserQuestion`, trois issues — trier
  maintenant · plus tard dans la séance · pas cette semaine.
  - *Maintenant* → étape 2.
  - *Plus tard* → rien ne s'écrit ; la question se repose avant la clôture de la séance.
  - *Pas cette semaine* → étape 6, forme « report » : l'échéance repart du jour du report.
- **Par la demande de l'utilisateur** → étape 2 directement.

**Fini quand** l'issue est connue.

## 2. Lire les fils et balayer la péremption

```bash
python3 ~/.claude/engine/etat.py fils --niveau <niveau>              # les actifs
python3 ~/.claude/engine/etat.py fils --niveau <niveau> --dormants   # les dormants, que la première vue retire
python3 ~/.claude/engine/peremption.py <niveau>                      # refs fermées, renvois gelés, échéances passées
```

Pour chaque fil, son dernier texte dans `<niveau>/ETAT.md`, et la source qu'il cite quand le verdict
en dépend. Un fil qui se dit fait se revérifie à sa source — fichier, commit, état de l'app — avant
d'être proposé soldé. Un fil qui attend un tiers dont la date est passée le dit dans son avis.

**Borne de la séance : 16 fils**, dormants les plus vieux d'abord, puis les actifs les plus vieux. Ce
qui dépasse reste au tri suivant.

Aucun dû ouvert : étape 3, puis la séance s'arrête là, sans événement.

**Fini quand** chaque fil retenu dans la borne a été lu, que la somme des deux vues égale le « N du(s)
ouvert(s) » de la ligne du bilan ou du pied `[etat]`, et que la sortie de `peremption.py` est en main.

## 3. Juger le niveau

Trois jugements, ceux de l'étape 4 d'`os-audit`, portés sur ce seul niveau. Trois à cinq faits en tout :

- **Un pointeur résout mais ne répond plus** : ouvrir la source de trois entrées de `## Où trouver`
  du niveau, en commençant par celles que le tri précédent n'a pas vues (son texte les nomme), et
  vérifier qu'elle répond encore à la question.
- **Un fait vivant contre sa source** : une version, un statut, une règle affirmés dans le document
  de conception ou un autre document vivant du niveau, confrontés à l'export, au journal ou au code.
- **Deux sources d'un même fait qui se contredisent**, y compris un constat de `peremption.py` dont la
  ligne contredit l'`ETAT.md`.

Chaque constat, de `peremption.py` ou du jugement, se relit à sa ligne avant d'être retenu : le script
est un motif, il signale aussi des lignes de provenance.

**Fini quand** chaque ligne de `peremption.py` est retenue ou écartée avec sa raison, et que les trois
jugements ont chacun au moins un fait regardé, même s'il ne révèle rien.

## 4. Un avis par fil et par constat, tranché par lot

Cinq verdicts pour un fil ; je recommande l'un d'eux. Chaque geste ajoute `--chantier <chantier du
fil>` et un `--texte`, la forme étant celle de `memoire-et-verite`, chargée avant le premier `add`.

| Verdict | Quand | Geste `etat.py add --niveau <niveau> --type du --ref <ref>` |
| :--- | :--- | :--- |
| **tenir** | prochain geste et porteur encore justes | aucun ; la ref entre dans le texte de l'étape 6 |
| **reformuler** | le geste, le porteur ou l'intitulé a changé | `--op ouvre --porteur <utilisateur\|assistant\|tiers>` : le dernier gagne, l'âge du fil est gardé |
| **fusionner** | deux fils pour un seul engagement | `--op ouvre` sur celui qui reste, reformulé ; puis `--op abandonne --motif "fusionné dans <ref>"` sur l'autre |
| **solder** | le geste est fait, preuve en main | `--op fait --source <preuve>` |
| **abandonner** | ni geste ni porteur : une idée, un constat, une surveillance sans déclencheur | `--op abandonne --motif …` |

Un fil **dormant** a déjà traversé plusieurs semaines sans avancer : l'avis nomme l'obstacle et
recommande reformuler, fusionner ou abandonner. Un fil **sans porteur** se reformule avec le sien.

Pour un constat de l'étape 3, trois issues : corriger maintenant · ouvrir un dû · écarter. Corriger le
document de conception ou un `CLAUDE.md` est une modification de fond, déjà validée par cette réponse.

**Les questions** : `AskUserQuestion`, au plus quatre par appel, un fil ou un constat par question. Le
texte de la question porte la ref, l'ancienneté dans l'unité de la vue et le fil en une phrase. Mon
verdict vient en première option, marqué « (Recommandé) », sa description porte le motif ; une à trois
autres options suivent, seulement celles qui sont plausibles. Une réponse « Autre » s'applique telle
que l'utilisateur la donne ; ambiguë, elle se redemande.

**Fini quand** chaque fil retenu à l'étape 2 et chaque constat retenu à l'étape 3 a sa réponse.

## 5. Appliquer

Un événement par verdict autre que « tenir », écrit dans le geste où le lot est rendu ; les corrections
de constat, faites ou ouvertes en dû. Ce qui sort du niveau suit son propriétaire :

- **une idée** d'un fil abandonné va dans `~/.claude/memory/IDEES_FROIDES.md`, **un rappel** qui
  portait le fil se purge de `~/.claude/memory/REMINDERS.md` (`memoire-et-verite`, retrait) : en
  session de projet, les deux partent à la principale par `SendMessage` ; en principale, s'écrivent
  directement ;
- **un constat** d'un fil abandonné devient un événement `observation` du niveau, avec sa `source`.

```bash
python3 ~/.claude/engine/etat.py projette --niveau <niveau>
python3 ~/.claude/engine/etat.py fils --niveau <niveau> --json    # contrôle
```

**Fini quand** `projette` a tourné sans erreur ; que la sortie JSON ne contient plus aucune ref
soldée, fusionnée ou abandonnée, et porte le porteur neuf de chaque fil reformulé ; et que chaque
idée, rappel, observation et correction prescrits sont écrits ou envoyés.

## 6. Dater le tri

Seul un tri **complet** se date : chaque dû ouvert du niveau a eu son verdict, dans cette séance ou
depuis le dernier tri daté. Un tri **partiel** — borne atteinte, séance interrompue — n'écrit rien :
le bilan suivant redit DÛ, et les verdicts déjà appliqués ont fait fondre le niveau.

```bash
python3 ~/.claude/engine/etat.py add --niveau <niveau> --type observation --chantier tri-fils \
  --ref o-tri-fils --source "etat.py fils --niveau ." \
  --texte "TRI DES FILS DU <AAAA-MM-JJ> : <n> lus ; <r> reformulés, <f> fusionnés, <s> soldés, <a> abandonnés ; tenus : <refs> ; constats : <c> retenus ; pointeurs vus : <refs p->."
```

Forme **report**, depuis l'étape 1 : `--ref o-tri-fils-reporte`, texte « TRI DES FILS REPORTÉ le
<AAAA-MM-JJ> par l'utilisateur, <n> dus ouverts ». Il fait repartir l'échéance du bilan ; il ne compte
pas comme un tri pour le filet mensuel.

**Si `MULTIPOSTE=oui`**, l'événement voyage avec le dossier à sa prochaine poussée
(`pousser-son-dossier`) ; d'ici là, l'autre poste redit DÛ.

**Fini quand** `add` a rendu sa ligne `[etat] e-… → journal/…`.
