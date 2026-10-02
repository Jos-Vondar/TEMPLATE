---
name: writing-for-agents
description: "Grille d'écriture de tout document qu'un agent lit — CLAUDE.md, MEMORY.md, document de conception, SKILL.md maison, définitions d'agents, texte de démarrage, plans et specs. À charger AUSSI avant de mandater un sous-agent pour en écrire un : il n'a pas l'outil Skill, la grille doit être recopiée dans son brief."
---

> **Emprunt ClaudeOS.** Corps repris de `mattpocock/skills · skills/productivity/writing-for-agents`, avec son voisin `SKILL-MECHANICS.md`, au commit épinglé dans `engine/config/SKILLS_AMONT`, licence MIT en `LICENSE.amont`. Le frontmatter et cette bannière sont à ClaudeOS, le corps est à l'amont : `engine/skills-amont.sh` le recompose à chaque passe, une retouche du corps s'y perd.
>
> Deux écarts volontaires. Le `description` est élargi aux types de fichiers ci-dessous : la règle vit dans le déclencheur, pas dans le règlement, qui la paierait à chaque session. Et la portée ci-dessous est ajoutée dans cette bannière, jamais dans le corps : le corps ne porte rien de maison, c'est ce qui le garde comparable à l'amont.
>
> **Une description empruntée garde sa langue d'origine**, même dans un système écrit en français ; seul son élargissement de périmètre, quand il est utile, est à nous.
>
> ### Portée ClaudeOS
>
> **S'applique à** — `CLAUDE.md` et `MEMORY.md` de tous niveaux ; le document de conception d'un niveau ; les `SKILL.md` maison, compétences situationnelles de `~/.claude/skills/` comprises ; les définitions d'agents (`domaines/<D>/agents/` fait foi, ses copies `<dépôt>/.claude/agents/` suivent) ; la carte `## Où trouver` d'`ETAT.md` ; le texte injecté au démarrage par `boot-check.sh` ; les plans et specs, au moment de leur rédaction seulement, jamais en réécriture rétroactive d'archives.
>
> **Démarcation avec `superpowers:writing-skills`**, quand ce greffon est installé : les deux descriptions revendiquent « creating or editing skills ». **Celle-ci prime au moment d'écrire une compétence de ce système** : elle couvre aussi les règles situationnelles, les mémoires, les reprises et la conception. Le greffon reste utile sur ce qu'il sait faire de mieux — la mécanique d'un greffon, ses commandes, son empaquetage. La démarcation ne peut vivre que de ce côté : le greffon n'est pas modifiable.
>
> **Nuance sur les mémoires** — sur un `MEMORY.md`, la grille porte sur la **structure** : source unique, pointeurs plutôt que copies. Jamais sur le fond daté. Élaguer un fait daté d'un registre en détruit la preuve.
>
> **Ne s'applique pas** —
>
> - **`ETAT.md` et les journaux `journal/*.jsonl`** : `ETAT.md` est une PROJECTION, écrite par `etat.py` — la corriger à la main est refusé au commit, et la grille n'a donc aucune prise dessus. Un ÉVÉNEMENT, lui, obéit à son contrat § 3.1, que la machine applique ; ce que l'écriture y ajoute vit dans `memoire-et-verite`, § Formes normalisées.
> - **Compétences empruntées à un amont** (celles qui portent une bannière « Emprunt », celle-ci comprise) : leur corps est recomposé depuis l'amont par `engine/skills-amont.sh`. Le frontmatter et la bannière sont à nous, le corps est à l'amont.
> - **Fichiers générés par script** — `memory/PORTFOLIO.md` : le script écrase la correction au premier passage. **Et les GELÉS** : le contrôle 14 refuse le commit.
> - **Livrables destinés à un tiers** : audience humaine, donc la compétence `livrables` quand elle est active.
>
> ### Les règles maison
>
> Elles vivent dans cette bannière : le corps est un emprunt, recomposé à chaque passe.
>
> ### Une consigne NOMMÉE bat un garde formulé en général
>
> **Dans une consigne destinée à un exécutant, une consigne nommée — une permission explicite, ou une forme imposée — l'emporte sur un garde formulé en général, où qu'ils soient l'un et l'autre dans le texte.** Ce qu'on veut interdire se nomme item par item, avec son motif ; une recommandation de prudence (« dans le doute tu gardes ») ne le remplace pas.
>
> **Corollaire de relecture** : chercher d'abord les verbes qui AUTORISENT — *écarte, ignore, exclus, retiens seulement* —, avant ceux qui protègent.
>
> **Corollaire du gabarit** : *tout gabarit obligatoire porte sa variante dégradée. Une case obligatoire sans variante vide est une fabrication programmée* — le modèle a une forme à remplir et rien à y mettre. C'est le remède supérieur quand une forme peut être donnée, et il rejoint la clause du corps : « A prohibition earns its place only as a hard guardrail you cannot phrase positively; even then, pair it with the positive target ». Les deux remèdes ne s'opposent pas, ils répondent à deux défauts distincts — forme obligatoire sans issue → fournir la variante manquante, en entier ; garde générique face à une consigne nommée → énumérer ce sur quoi il est interdit de trancher.
>
> **CINQ occurrences mesurées, avec dégât réel** — deux formes : une permission nommée qui bat un garde générique, et un gabarit impératif sans variante vide, qui a fait **inventer** un produit inexistant. La cinquième est sur un artefact distinct et d'une autre main : le motif n'est lié ni à un chantier ni à une famille d'artefacts.

> ### Tout nombre écrit nomme son unité
>
> **Un plafond, un quota, une limite, une valeur numérique nomme son UNITÉ dans la phrase qui le pose.** Sans elle le nombre est obéi à la lettre sur la mauvaise grandeur, et **le défaut est invisible à la relecture** : il n'y a ni erreur, ni écart de conduite, ni trace. Il ne se voit qu'en demandant « trois **quoi** ».
>
> **Corollaire, et c'est lui qui mord le plus** : ni le préfixe, ni le nom, ni le libellé d'un champ ne disent son unité. Un préfixe de colonne ne dit pas « euros ». Et **un modèle qui reçoit un nombre sans unité répond quand même**, avec aplomb.
>
> **Cinq occurrences, quatre niveaux, aucune du même domaine.**
> 1. Un prompt disait « trois au maximum » en comptant des **produits** quand l'unité voulue était le **montage** — l'utilisateur ne voyait que deux propositions, et le modèle obéissait parfaitement.
> 2. L'en-tête du `MEMORY.md` d'une app justifiait son plafond en **mots** quand la mesure est en **caractères** : une justification entière calibrée sur la mauvaise grandeur.
> 3. Trois en-têtes voisins du même parc portaient le même défaut.
> 4. **L'audit lui-même l'a payé** : trois nombres ont circulé pour un seul fichier — 131 310 (octets), 126 701 (caractères), 123 704 (caractères hors commentaires HTML, le seul que le contrôle mesure). Un sous-agent a annoncé des octets en les appelant caractères, dans la passe dont la grille nomme ce piège.
> 5. **Avec dégât métier, celle-là** : une colonne de base de données était en **milliers d'euros** et aucun des sept prompts de la chaîne ne le disait — les écrans affichaient un montant mille fois trop petit, et ce facteur faussait une éligibilité qui en dépendait.
>
> **L'objection « trop évidente pour être écrite » est examinée et écartée** : la règle a été payée cinq fois malgré son évidence, dont trois fois par ce système sur ses propres plafonds et une fois par l'audit chargé de la traquer.

> ### Un libellé qui dit croire savoir empêche de regarder
>
> *Elle réunit deux règles qui se reconduisaient séparément d'audit en audit — le défaut même que la seconde décrit.*
>
> **Un intitulé est lu comme un diagnostic, à chaque relecture. Nommé sur la cause supposée plutôt que sur le symptôme observé, il fait chercher au mauvais endroit aussi longtemps qu'il reste ouvert — et chaque relecture reconfirme le mauvais terme.** La reconduction ne retarde pas le travail : **elle protège l'erreur**.
>
> **Deux formes, un seul mécanisme.**
> - **Un fil, une dette, un rappel** se nomme sur le **symptôme**, et sa cause supposée vit dans le corps, **marquée comme hypothèse**. Exiger les deux : un intitulé purement symptomatique est plus dur à retrouver.
> - **Une mention « hors périmètre »** — « ajouté par un tiers », « configuré côté client », « alimenté par le flux » — dit **ce que le tiers ajoute ET que ça doit exister à la livraison**. Sinon le bloc échappe au contrôle, y compris à un relecteur automatique qui a pourtant chargé la fiche.
>
> **Trois occurrences, trois niveaux.** Un fil accusait la division d'un calcul d'ancienneté ; la division était juste, c'était l'unité de la fonction de date — **7 jours** ouvert sur le mauvais terme. Une fiche de format rangeait un tableau hors périmètre en le donnant pour « ajouté par un tiers » : le document est parti sans lui, ni la session ni son relecteur ne l'ont vu manquer. Et un rappel a été **reconduit cinq fois sur trois semaines** en désignant un guide de licences qui ne portait aucune des deux réponses attendues.

> ### Le décalage entre deux prompts d'une chaîne ne casse rien et rend faux
>
> **Le contrat de sortie de l'étape N est le contrat d'entrée de N+1, et rien ne le vérifie.** Un décalage de forme, de champ, d'unité ou de casse ne lève aucune erreur : l'étape suivante interprète et rend du plausible. **Le défaut n'existe que dans l'écart** — relire chaque prompt isolément ne peut pas le trouver, et les deux autres règles maison ci-dessus visent au contraire un défaut INTERNE à un artefact.
>
> **Le geste** : écrire le contrat de passage à un seul endroit, cité par les deux étapes. À défaut, relire les deux prompts **en vis-à-vis**.
>
> **La paire de prompts n'est qu'un cas.** *Tout transport entre deux REPRÉSENTATIONS porte un
> contrat que rien ne vérifie.* Une formule recopiée d'un fichier source vers l'éditeur visuel qui
> la ressaisit se convertit DEUX fois — séparateur décimal de la locale, et signe égal de tête
> retiré — et rien ne le signale. Chercher la classe sur toute paire de représentations, pas
> seulement sur deux prompts. *(Deux défauts dans la même séance, relevés tous deux par
> l'utilisateur.)*

> ### Un critère plus étroit que son étape
>
> *Le § « Steps and completion criteria » du corps pose la clarté et l'exigence, jamais la
> COUVERTURE.*
>
> **Le critère nomme chaque artefact que l'étape prescrit, et toute clause conditionnelle — « X se
> crée le jour où Y existe » — porte son propre critère ou saute.** Un critère court ne rate rien :
> l'exécutant fait ce qu'il mesure et le reste part sans trace. Six des douze écarts d'un audit en
> venaient.
