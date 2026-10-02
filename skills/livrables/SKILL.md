---
name: livrables
description: Produire un livrable destiné à un tiers, y avancer un fait chiffré ou sourcé, ou nommer des valeurs d'énumération, libellés d'écran, intitulés de spécification. Aussi quand une échéance devant un tiers approche hors du domaine technique de l'utilisateur.
---

# Règles — produire un livrable

> Fiche situationnelle. Déclencheur : je produis quelque chose destiné à un tiers (mail client, spécification, doc formelle, instructions d'outil), un rendu visuel (deck, one-pager), un livrable structuré à fort enjeu, **ou je nomme les valeurs d'une énumération, les libellés d'un écran ou les intitulés d'une spécification**.
> Rappel du règlement : un livrable pour un tiers suit la rubrique « Périmètre du caractère » du persona. Le fond (rigueur, honnêteté, challenge) ne change pas ; seule la forme module.

## Rédaction

- Prose continue, registre adulte.
- Phrases développées qui s'enchaînent, ponctuation de prose, listes réservées aux données.
- Ne s'applique pas au dialogue avec l'utilisateur, qui garde le ton du persona.
- **Premier jet.** Une fois l'ossature validée : une section rédigée à la qualité finale pour calibrer le ton et le niveau de détail, le reste en squelette. La voix se corrige une fois, pas sur vingt pages.

## Contrôler l'INTERFACE avant de relire le contenu

*Deux occurrences réelles, deux artefacts distincts.*

**Un fond complet et un branchement absent produisent un artefact qui paraît fini.** Une relecture du CONTENU ne peut pas voir un défaut d'INTERFACE : le texte est juste, complet, bien écrit — et il ne reçoit rien, ou n'est lu par personne. **Contrôler les entrées et la sortie AVANT de relire le contenu**, et ne jamais compter sur une relecture de fond pour attraper ça.

- **Les entrées** : le livrable porte-t-il les marqueurs, variables, colonnes, paramètres qui doivent l'alimenter ? Un prompt de 119 Ko, métier juste, ne portait **aucun marqueur de variable**. Un prompt sans marqueur ne reçoit rien, **et un modèle qui ne reçoit rien n'échoue pas** — il fabrique et répond avec aplomb. Aucune erreur, aucun signal.
- **La sortie** : son format est-il celui que le consommateur lit, et un seul ? Le même artefact portait **deux formats de sortie concurrents** là où le flux appelant n'en lit qu'un.

**Corollaire de chaîne** : quand deux artefacts sont chaînés — le contrat de sortie de l'un alimentant l'entrée de l'autre —, une modification du contrat les rend **tous les deux** à recoller, ensemble. N'en recoller qu'un les met en désaccord silencieux : rien ne casse, et les réponses deviennent fausses. Pour que ce soit vérifiable au lieu de dépendre de la mémoire d'une séance, **chaque artefact nomme son amont et son aval**.

## Nommer une distinction

**Un mot ne porte pas une distinction qu'il ne dit pas.** Quand un partage compte — deux niveaux d'exigence, deux statuts, deux natures —, les libellés l'énoncent au lieu de le sous-entendre par deux quasi-synonymes. Vaut pour les énumérations d'un modèle de données, les libellés d'interface et les intitulés d'une spécification. Test : la convention se devine-t-elle sans légende, par quelqu'un qui découvre l'écran ? Si non, allonger le libellé.

## Nommer une portée, une permission, un rôle

**Un nom de portée, de permission ou de rôle se vérifie à sa SOURCE — la documentation de l'éditeur, la console — avant d'être nommé dans une demande.** Le lecteur va le chercher tel quel, et un nom approché lui fait accorder le plus proche qui existe. *(Payé une fois : une demande de privilège minimal aurait accordé un droit d'ÉCRITURE.)*

## Provenance des faits dans un livrable

**Un livrable énonce le fait, pas sa provenance en correspondance privée.** Aucun renvoi à un courriel, un compte rendu, une date d'échange ou une maquette reçue dans un document destiné à un tiers ou à un collègue — le fait s'écrit seul. Deux motifs : la référence fuite du contexte interne hors de son cercle, et elle périme le document dès que la correspondance est oubliée.

**Cette règle porte sur ce que le texte cite, pas sur ce qui a servi à le vérifier** — la confusion entre les deux la rendrait absurde. Un fait établi par un courriel client **entre** dans le livrable, énoncé seul ; la trace de sa provenance reste en mémoire de projet. Ce que le texte peut en revanche citer *comme source* : la documentation de l'éditeur, une décision de conception datée, le métier lui-même. Autrement dit sourcer est une obligation de vérification, avant d'écrire ; citer est un choix d'attribution, dans le texte. L'exigence de vérifier tout chiffre contre une source primaire (§ Livrable sourcé) n'est donc pas contredite : elle s'applique en amont, et le courriel y compte comme source primaire.

## Livrable visuel

- Ne pas générer un `pptx` en aveugle via python-pptx quand le rendu n'est pas vérifiable en session : la qualité visuelle plafonne. Privilégier Claude Design ou un artefact HTML, où le résultat est visible et itérable.
- python-pptx reste admis pour des éditions mécaniques sûres sur une copie — retirer des slides, cloner une slide existante, réécrire du texte — où le format est préservé et le risque visuel nul.

## Livrable structuré à fort enjeu

Deck de comité, spécification, doc client : produire d'abord un plan d'ossature via un agent (structure, message unique, altitude, arbitrages) et itérer sur ce plan. Ne construire le rendu qu'une fois l'ossature validée. Jamais d'itération visuelle sur un rendu bâti sans plan.

## Livrable sourcé à fort enjeu

Mémoire, plan, doc client : tout claim factuel ou chiffré est vérifié contre une source (recherche approfondie ou source primaire) avant d'entrer. Jamais asserté de mémoire. Réserves et limites intégrées au texte, pas reléguées en note.

## Exposition hors domaine de maîtrise

Avant une échéance où l'utilisateur porte devant un tiers un sujet qu'il ne maîtrise pas techniquement : préparer le terrain en amont — vocabulaire juste, formules pour renvoyer une question technique au propriétaire de la plateforme, et les deux ou trois points précis où on le prendrait en défaut. L'équiper avant, pas le rattraper après : il ne doit pas passer pour débutant.
