---
name: reprise
description: "Écrire l'état de reprise d'un niveau — bascule annoncée, palier franchi, source de vérité modifiée, décision tranchée, ou clôture de séance. Porte aussi les trois gestes de clôture et l'entrée de journal."
---

## Quand

**Quatre déclencheurs, et eux seuls** : une source de vérité modifiée (`DESIGN.md`,
`CLAUDE.md`, `MEMORY.md`) · une décision que l'utilisateur vient de trancher · une bascule
qu'il annonce (« on fait un aparté », « on passe à autre chose ») · un palier franchi dans un
chantier. Plus le signal de fin, qui déclenche les trois gestes de la dernière section.

**À chacun de ces quatre déclencheurs, trois écritures partent ensemble** : le `HANDOFF.md` du niveau, la trace datée dans son `MEMORY.md`, et l'entrée de journal.
Elles vont ensemble parce qu'écrites tard, elles sont écrites de mémoire. Seule la **sauvegarde**
attend le signal de fin. Ce qui rendait cette cadence coûteuse était le brief à un sous-agent ; il
n'y a plus de sous-agent, donc plus de brief.

Le discriminant est **ce qu'une interruption rendrait coûteux à reconstruire**, et il s'observe
sans jugement. Il remplace « à chaque action significative », formule qui coexistait avec
« palier » et produisait deux cadences selon le modèle qui lisait la fiche. *(→ origines)*

Ce qui **ne** déclenche pas : un tour de conversation, une lecture, une recherche, une
compilation. Un fait déjà écrit sur disque — un plan, une spec — est déjà à l'abri : il n'a
pas besoin d'une seconde trace.

## Écrire en session, pas par agent

**Écrire directement, dans la session qui détient le contexte.** C'est la voie par défaut et
la seule dans presque tous les cas.

**Le critère n'est pas la taille du delta, c'est l'état du contexte de la session** *(corrigé : l'ancienne formule indexait le véhicule sur « ajout contre refonte », et le
nombre de fichiers touchés se lisait comme une refonte — quatre ajouts dans quatre fichiers
restent quatre ajouts)*. Tant que la session a de la place, écrire soi-même coûte une lecture
de fichier ; déléguer coûte un brief qui décrit tout ce que l'exécutant ignore, plus sa
relecture. Le brief est presque toujours le plus cher.

**Déléguer à un sous-agent générique** garde un seul usage : la session est près de sa limite
de contexte et il reste une reprise à écrire. Le brief doit alors porter **tout** — les faits,
leur état de vérification, ce qui est dû, ce qui ne l'est pas — parce que l'exécutant ne voit
pas la séance.

Test opposable, dans les deux sens : **si je peux nommer les éditions, je les fais ; si je dois
décrire un état de fin pour qu'un autre le compose, je délègue.**

## Où

Un `HANDOFF.md` **par niveau touché**, écrasé à chaque écriture :

| Ce sur quoi la séance a porté | Fichier |
| :--- | :--- |
| Travail de workstation | `~/workstations/<WORKSTATION>/HANDOFF.md` |
| Système, méta, configuration | `~/.claude/HANDOFF.md` |
| Séance à plusieurs niveaux | un fichier par niveau, jamais un seul qui les mélange |

Jamais un dossier temporaire — le fichier doit survivre à la machine. Rôles et bornes
d'écrasement : le document de conception, seule autorité.

## Quoi

**L'état complet et frais du niveau**, écrit à partir de la séance et du contenu antérieur du
fichier. Pas un journal des tours de parole : ce qu'il faut savoir pour reprendre demain sans
avoir la conversation.

- **Ce qui est vérifié, et par quoi.** Étiqueter **vérifié** (avec sa source), **inféré**,
  **à confirmer**. Un statut embelli est le seul défaut qu'une reprise ne pardonne pas : elle
  sera lue comme un fait.
- **Ce qui est dû et ne l'est pas.** Nommer ce qui reste, sans le présenter comme entamé.
- **Référencer par chemin**, jamais recopier. Un plan, un `DESIGN.md` vivent ailleurs ;
  deux copies à deux âges se contredisent, et c'est ce fichier qui vieillit le plus vite.
- **Anonymat**, parce que ce fichier part sur le dépôt : aucun identifiant, aucune donnée
  personnelle, aucun verbatim client, projets désignés par leurs codes.
- **Expurger tout secret** : ni clé, ni jeton, ni mot de passe, même partiel.

Ajouter dans un bloc existant quand la séance continue ; **remplacer le fichier entier**
quand on écrit l'état de fin — bloc « séance en cours » et bloc de la séance close antérieure
compris.

## Les trois gestes de la clôture

Sur signal de fin (« on arrête », « c'est tout pour aujourd'hui »), dans cet ordre. Les deux
premiers ont déjà tourné à chaque déclencheur de la séance (§ Quand) ; ce qui change à la clôture
est **jusqu'où ils écrasent**, et que le troisième s'ajoute :

1. **Reprise** — le `HANDOFF.md` de chaque niveau touché, en **état de fin**, donc fichier
   remplacé. La clôture est le dernier passage, pas un régime à part.
2. **Mémoire** — la trace datée dans le `MEMORY.md` du bon niveau, et l'entrée de journal
   complétée, sa mention de séance en cours retirée.
3. **Sauvegarde** — `bash ~/.claudeos/engine/backup.sh`. Lire son rapport de fichiers
   refusés : ce qui n'est pas dans la liste blanche reste sur cette seule machine.

**L'entrée de journal s'ajoute brute, sans travail de rédaction**. Deux
exigences seulement, et elles ne se négocient pas : elle **doit exister**, parce qu'elle porte
la séance pour la distillation hebdomadaire, qui ne relit que ce qui est écrit ; et elle est
**anonyme**, au même titre que le `HANDOFF.md`.

Fin d'une séance de conception (brainstorm, entretien contradictoire) : écrire aussi le
`HANDOFF.md` du niveau concerné, pour permettre la reprise.

**Ne pas rejouer ici ce qui est dû à la passe hebdomadaire** — hygiène des mémoires, plafonds,
distillation, retombée documentaire, ratés de routage, revue des rappels. Elles sont dues
ailleurs (`session`), pas supprimées.
