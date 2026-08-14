---
name: memoire-et-verite
description: Écrire un fait, un statut ou une décision, ou toucher une source de vérité — MEMORY.md, DESIGN.md, CLAUDE.md. Porte les cas ambigus du tri, l'intégrité des statuts, les plafonds et l'archivage, la relecture contradictoire.
---

# Règles — écrire un fait, un statut, une décision

> Fiche situationnelle. Se charge sur déclencheur, jamais par réflexe. Déclencheur : je vais écrire dans un `MEMORY.md`, un `DESIGN.md`, un document de référence du projet, un `CLAUDE.md`, ou l'utilisateur dit « garde ça en mémoire » / « retiens ça » / « note ça ».
> La règle de tri en trois destinations vit dans le `CLAUDE.md` racine : c'est elle qui décide où va le fait. Cette fiche porte le reste.

## Tri — cas particuliers

- Déclencheur lexical « garde ça en mémoire » et variantes : ne pas écrire dans `MEMORY.md` par réflexe. Appliquer la règle de tri. Cas évident : router et écrire. Cas ambigu : demander où ça va, en une question.
- Si doute entre deux fichiers : probablement les deux. `MEMORY.md` = trace datée ; `DESIGN.md`/le document de référence du projet = fait intemporel.
- Toute entrée `MEMORY.md` de type « comportement voulu » doit pointer sa contrepartie : `→ DESIGN §x`.
- Avant d'ajouter une règle émergente (bug, pattern, comportement découvert en session) dans un `CLAUDE.md` : choisir le bon niveau (racine / workstation / projet / app). Le trancher soi-même ; plus d'agent pour cet arbitrage.
- **Un fait calculable ne s'écrit pas, il se lit.** Nombre de contrôles, taille d'un fichier, liste de dossiers : pointer la source qui le porte au lieu d'en recopier la valeur. Un contrôle qui vérifie la concordance de trois copies est un pansement sur une décision d'écriture évitable (deux occurrences : un compteur de contrôles inscrit en dur dans trois documents, faux le jour même ; puis un plafond du règlement affirmé par la fiche d'audit alors que le règlement l'avait abandonné, qui aurait fait conclure à un dépassement là où le système était conforme).
- **Une procédure vit à un seul endroit.** Cas particulier de « un fait vit en un seul lieu, plus des pointeurs » (`CLAUDE.md` §1), appliqué au geste répété et non au fait. Quand une procédure justifie une fiche de compétence (`~/.claude/skills/`), elle y migre **entière** ; son emplacement d'origine ne garde que le déclencheur et un pointeur vers la fiche — jamais un résumé, un extrait ni « les grandes lignes », qui redeviennent une seconde copie à un autre âge — et son en-tête est réaligné sur ce qu'il porte encore. Déclencheurs de la migration, **les deux réunis** : répétition constatée sur plusieurs séances (une exécution unique ne prouve rien) et procédure outillée et stabilisée — séquence fixe, pièges déjà rencontrés et consignés. Séquence encore mouvante ou jouée une seule fois : elle reste où elle est (origine : une procédure de mise en production, partie du document de conception d'un domaine vers une compétence dédiée).
- **Filtre d'admission en mémoire.** Un fait ne s'écrit que si son oubli ferait refaire une erreur, ou reposer une question déjà tranchée. « Intéressant » ne suffit pas.
- **Quand une correction devient une règle.** Faute qui a coûté du travail, de la crédibilité, ou qui a produit une erreur factuelle → promotion immédiate en règle. Simple préférence de forme → attendre une deuxième occurrence, qui prouve une position et non une humeur du jour.

## Sources de vérité — `DESIGN.md` et le document de référence du projet

- Déclencheurs d'écriture immédiate : confirmation explicite (« oui c'est voulu », « on garde », « validé »), correction sur un comportement du système, réponse tranchée à une clarification.
- **Écrire directement.** Ni agent imposé, ni relecture par un second agent : les deux obligations sont supprimées, avec la relecture après chaque modification de règle. Elles trouvaient de vrais défauts, mais leur coût par séance dépassait ce qu'elles évitaient, et elles rendaient la moindre écriture cérémonieuse. Ce qui les remplace : **un audit du système une fois par semaine**, qui cherche les mêmes défauts en une passe au lieu de les chercher à chaque geste — perte de règle par réécriture, contradiction interne, doublon, statut affirmé sans preuve, chemin devenu faux.
- Ce qui reste dû à chaque écriture, parce que ça ne se rattrape pas : vérifier un statut avant de l'écrire (ci-dessous), et ne pas perdre une règle en réécrivant un passage qui la portait.
- **Relecture contradictoire : proposée, jamais imposée.** Elle reste disponible et se propose quand l'enjeu le mérite, avec le motif en une ligne. Trois cas où je dois la proposer plutôt qu'y penser : quand la réécriture **remplace** un passage qui portait des règles, au lieu d'en ajouter un — c'est là qu'une règle se perd sans bruit ; quand j'ai à la fois décidé et écrit, donc que personne n'a lu le texte avec un autre œil ; et quand le texte fixe un comportement dont un tiers dépendra. Hors de ces cas, écrire et passer. L'utilisateur peut toujours la refuser.
- **Intégrité des statuts** : ne jamais inscrire « implémenté » (ni « livré », « fait ») sur la seule intention de conception. Le code correspondant doit exister et être vérifié au moment où le statut est écrit. Décision conçue mais non codée → « à implémenter ». Au moindre doute sur l'état réel, vérifier le code avant d'écrire le statut.

## Plafonds et archivage

- `MEMORY.md` : **son plafond est déclaré en tête du fichier**, avec son unité et son motif — ne pas le recopier ici, c'est ainsi qu'on se retrouve avec une valeur périmée dans la mauvaise unité. Au dépassement, compresser et déplacer les entrées obsolètes ou terminées dans `ARCHIVE.md`. Relever un plafond se décide et s'écrit dans l'en-tête.
- `CLAUDE.md` racine : **pas de plafond, le critère d'admission arbitre** — il est écrit en tête du règlement lui-même, qui en est la source. Ne pas le recopier ici : c'est par une copie de cette règle qu'une fiche a affirmé un plafond que le règlement avait abandonné.

## Écriture dans un `CLAUDE.md`

- Uniquement des règles. Jamais de narratif, de résumé ni d'explication.
- **Pas d'audit après modification** : supprimé avec le reste de la cérémonie. Une règle modifiée entre en vigueur telle quelle ; l'audit hebdomadaire du système la relira. Motif de la suppression : chaque correctif déclenchait un nouvel audit, qui produisait un correctif, sans terme.
- **Une règle n'entre que si une autre sort.** Le règlement et ses fiches ont grossi de tous les incidents et n'ont jamais rendu une ligne. À l'ajout, nommer ce qui sort — ou dire pourquoi rien ne peut sortir.
- Les `MEMORY.md` ne sont pas relus au fil de l'eau : l'hygiène des mémoires est due à la passe hebdomadaire.
