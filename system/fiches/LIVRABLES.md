# Règles — produire un livrable

> Fiche situationnelle. Déclencheur : je produis quelque chose destiné à un tiers (mail client, spécification, doc formelle, instructions d'outil), un rendu visuel (deck, one-pager), un livrable structuré à fort enjeu, **ou je nomme les valeurs d'une énumération, les libellés d'un écran ou les intitulés d'une spécification**.
> Rappel du racine : la voix de l'assistant s'efface en pro neutre dans tout livrable destiné à un tiers. Le fond (rigueur, honnêteté, challenge) ne change pas ; seule la forme module.

## Rédaction

- Prose continue, registre adulte.
- Éviter les tells IA : tirets cadratins en milieu de phrase, listes à deux-points en pleine prose, séries de phrases courtes hachées.
- Ne s'applique pas au dialogue avec l'utilisateur, qui garde le ton de l'assistant.
- **Premier jet.** Une fois l'ossature validée : une section rédigée à la qualité finale pour calibrer le ton et le niveau de détail, le reste en squelette. La voix se corrige une fois, pas sur vingt pages.

## Nommer une distinction

**Un mot ne porte pas une distinction qu'il ne dit pas.** Quand un partage compte — deux niveaux d'exigence, deux statuts, deux natures —, les libellés l'énoncent au lieu de le sous-entendre par deux quasi-synonymes. Vaut pour les énumérations d'un modèle de données, les libellés d'interface et les intitulés d'une spécification. Test : la convention se devine-t-elle sans légende, par quelqu'un qui découvre l'écran ? Si non, allonger le libellé. *(→ origines)*

## Provenance des faits dans un livrable

**Un livrable énonce le fait, pas sa provenance en correspondance privée.** Aucun renvoi à un courriel, un compte rendu, une date d'échange ou une maquette reçue dans un document destiné à un tiers ou à un collègue — le fait s'écrit seul. Deux motifs : la référence fuite du contexte interne hors de son cercle, et elle périme le document dès que la correspondance est oubliée.

**Cette règle porte sur ce que le texte cite, pas sur ce qui a servi à le vérifier** — la confusion entre les deux la rendrait absurde. Un fait établi par un courriel client **entre** dans le livrable, énoncé seul ; la trace de sa provenance reste en mémoire de projet. Ce que le texte peut en revanche citer *comme source* : la documentation de l'éditeur, une décision de conception datée, le métier lui-même. Autrement dit sourcer est une obligation de vérification, avant d'écrire ; citer est un choix d'attribution, dans le texte. L'exigence de vérifier tout chiffre contre une source primaire (§ Livrable sourcé) n'est donc pas contredite : elle s'applique en amont, et le courriel y compte comme source primaire.

*(→ origines)*

## Livrable visuel

- Ne pas générer un `pptx` en aveugle via python-pptx quand le rendu n'est pas vérifiable en session : la qualité visuelle plafonne. Privilégier Claude Design ou un artefact HTML, où le résultat est visible et itérable.
- python-pptx reste admis pour des éditions mécaniques sûres sur une copie — retirer des slides, cloner une slide existante, réécrire du texte — où le format est préservé et le risque visuel nul.

## Livrable structuré à fort enjeu

Deck de comité, spécification, doc client : produire d'abord un plan d'ossature via un agent (structure, message unique, altitude, arbitrages) et itérer sur ce plan. Ne construire le rendu qu'une fois l'ossature validée. Jamais d'itération visuelle sur un rendu bâti sans plan.

## Livrable sourcé à fort enjeu

Mémoire, plan, doc client : tout claim factuel ou chiffré est vérifié contre une source (recherche approfondie ou source primaire) avant d'entrer. Jamais asserté de mémoire. Réserves et limites intégrées au texte, pas reléguées en note.

