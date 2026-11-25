# Écrire dans le document de conception, un CLAUDE.md ou une fiche de mémoire

> Annexe de `memoire-et-verite`, lue en entier avant la première écriture d'un de ces fichiers
> dans la séance. Le crochet `rappel-fichiers-nommage.sh` refuse une fois l'écriture tant qu'elle
> n'est pas lue. Un événement `etat.py add` et l'index `MEMORY.md` n'en relèvent pas.

## Le document de conception

- Déclencheurs d'écriture immédiate : confirmation explicite (« oui c'est voulu », « on garde », « validé »), correction sur un comportement du système, réponse tranchée à une clarification.
- **Écrire directement.** Ni agent imposé, ni relecture par un second agent : leur coût par séance dépasse ce qu'elles évitent. Ce qui les remplace : `weekly-check.sh` et la passe mensuelle `os-audit`. **Cette passe ne cherche pas ces défauts dans les documents du système** — perte de règle par réécriture, contradiction interne, doublon, statut sans preuve — sauf quand une friction vécue les révèle, ou qu'ils touchent le travail : perte assumée.
- Ce qui reste dû à chaque écriture, parce que ça ne se rattrape pas : vérifier un statut avant de l'écrire (fiche, § Statut), et ne pas perdre une règle en réécrivant un passage qui la portait.
- **Relecture contradictoire : proposée, jamais imposée.** Elle reste disponible et se propose quand l'enjeu le mérite, avec le motif en une ligne. Trois cas où je dois la proposer plutôt qu'y penser : quand la réécriture **remplace** un passage qui portait des règles, au lieu d'en ajouter un — c'est là qu'une règle se perd sans bruit ; quand j'ai à la fois décidé et écrit, donc que personne n'a lu le texte avec un autre œil ; et quand le texte fixe un comportement dont un tiers dépendra. Hors de ces cas, écrire et passer. L'utilisateur peut toujours la refuser.

## Écriture dans un `CLAUDE.md`

- **Le règlement racine est payé à chaque session** : une règle n'y entre que par une des deux
  portes du socle (« Mémoire et vérité »). Sinon elle va dans une compétence de `~/.claude/skills/`,
  **une par déclencheur** : écrire sa `description`, qui EST ce déclencheur, fait partie de
  l'écriture de la règle.
- **Au niveau racine, une règle de l'utilisateur s'écrit dans « Mes règles », HORS du bloc d'imports.** Le bloc est réécrit par `engine/appliquer-reponses.py`, et les fragments qu'il importe appartiennent au template : ni l'un ni les autres ne reçoivent une règle à la main. Persona et « Mes domaines » sont à l'utilisateur, eux aussi hors du bloc.
- Uniquement des règles. Jamais de narratif, de résumé ni d'explication. **Une exception, étroite** : une **contre-indication d'une ligne, au présent et sans date**, qui dit ce que la règle casse si on l'inverse. Elle suit la règle, jamais à sa place ; le récit daté qui la prouve va en `observation` au journal du niveau.
- **Pas d'audit après modification** : une règle modifiée entre en vigueur telle quelle. Sinon chaque correctif déclenche un audit qui produit un correctif, sans terme.
- L'index de mémoire n'est pas relu au fil de l'eau : l'hygiène des mémoires est due à la passe mensuelle.

## Une règle candidate — cool-down et troc

**Quand `REGLES_A_FROID=oui`**, le règlement porte la boucle d'apprentissage (fragment
`regles-a-froid-oui`) : une règle née en séance devient un dû du chantier `regles-candidates` au
lieu de s'écrire à chaud, et une règle n'entre que si une autre sort. À `non`, cette section est sans
objet. Ce qui n'est qu'ici vaut pour toute couche — règlement, compétence situationnelle, document de
conception :

- **La promotion d'une candidate se fait à la passe mensuelle, à froid** — au moment où se pose la
  question du troc, « laquelle sort ».
- **L'exception d'irréversibilité se lit strictement** : une perte de données, un envoi à un tiers,
  une fuite. Une règle de conduite, une préférence de forme, une heuristique de jugement n'en
  relèvent jamais, quelle que soit leur évidence sur le moment.
- **Le troc se paie DANS LA MONNAIE DE LA COUCHE CIBLE** : à l'ajout, nommer ce qui paie, ou dire
  pourquoi rien n'a à sortir. Le geste par couche vit dans `skills/os-audit/HYGIENE.md`, geste
  « Règles candidates », seule autorité.

## Fiche de mémoire automatique

`memory/<prefixe>_<sujet>.md` — le préfixe du nom et le `type` du frontmatter disent **la même
chose**, sinon l'un des deux ment :

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
