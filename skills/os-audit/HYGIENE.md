# Hygiène de la passe mensuelle

> **Seule autorité** sur les deux gestes que `session` et `memoire-et-verite` citent par leur nom :
> « Hygiène des mémoires » et « Règles candidates ».

Ces gestes **alimentent le menu** de l'étape 5 de `SKILL.md` ; aucun ne s'exécute hors du choix de
l'utilisateur, sauf mention.

## Ce qui entre au menu

- **Règles candidates** — voir ci-dessous.
- **Les trois fils les plus vieux** de `etat.py fils --tous` : pour chacun, tenir, replanifier ou
  abandonner. Rien ne compte les reconductions : un fil qui revient à la troisième passe, chercher
  l'obstacle au lieu de le reconduire.
- **Rangement**, seulement si la détection n'est pas vide : fichier sans maison, reste de séance,
  fichier vide ou en double, nom non devinable. C'est le seul geste qui déplace : validé avant d'agir,
  **supprimé par `git -C <dépôt> rm`**, jamais rien dans un `_IGNORE/` sans classer et faire
  confirmer — hors sauvegarde, c'est l'unique exemplaire.
- **Une fiche au-dessus de son plafond** (`plafonds-parc.sh`, étape 1) : l'allègement, par le geste
  qui suit.

## Hygiène des mémoires

Sur une fiche de mémoire, un `ETAT.md` ou un document trop chargé. **Les seules mémoires vivantes sont
l'index `memory/MEMORY.md` et ses fiches** ; un niveau ne porte pas de `MEMORY.md`, et celui qu'une
migration a gelé ne reçoit plus rien. Un `ETAT.md`
s'allège en soldant des dus, jamais à la main.

**Trier avant d'écrire.** Un fait **intemporel** va dans sa source de vérité (le document de conception,
le `CLAUDE.md` du bon niveau). Un **doublon** déjà mot pour mot dans un document vivant se **retire**, en
laissant un pointeur. Seul un **récit soldé** devient un événement `observation`
(`etat.py add --type observation`), le document gardant un renvoi `→ journal/AAAA-MM.jsonl [date]`.
Un fichier trop gros porte parfois ce qu'un AUTRE document aurait dû porter : le déplacement est alors
une décision à faire trancher.

**Écrire l'événement, le contrôler, PUIS alléger le vivant** — l'inverse ouvre une fenêtre où le
contenu n'est nulle part. **Vérifier la contrepartie AVANT d'alléger** : un récit ne sort que si sa
leçon est écrite ailleurs, vérifié en OUVRANT le document cible, sur plusieurs motifs. Contrôle
d'intégrité : `grep -c '<fragment distinctif>' <niveau>/journal/*.jsonl` rend `1` sur trois ou quatre
fragments. Ce qui **reste** : le fait, sa conséquence, son statut, le renvoi. **L'explication du
retrait va dans l'événement, jamais dans le fichier qu'on allège.**

La mesure des plafonds **se lance**, elle ne se refait pas de tête : `bash ~/.claude/engine/plafonds-parc.sh`
— elle exclut les commentaires HTML, sans quoi trois verdicts du parc s'inversent.

## Règles candidates

Ce sont les `du --chantier regles-candidates` des niveaux, ouverts quand `REGLES_A_FROID=oui` ; à
`non`, ce geste est sans objet. **Les trancher ICI, à froid**, une option du menu par candidate.

**Où va une règle promue.** Au niveau racine, dans la section **« Mes règles » du `CLAUDE.md`, HORS du
bloc d'imports** : le bloc est réécrit à chaque application des réponses, et les fragments qu'il
importe appartiennent au template, comme les compétences livrées — ni l'un ni les autres ne
reçoivent une règle de l'utilisateur. Une règle qui se convoque sur un déclencheur va dans une
compétence de l'utilisateur. Aux autres niveaux, le `CLAUDE.md` du niveau.

Le troc se paie **DANS LA MONNAIE DE LA COUCHE CIBLE**, valeurs dans `engine/config.sh`,
`CLAUDEOS_CLIQUET_*`. « Mes règles » → ses octets, qu'aucun cliquet ne borne : le `CLAUDE.md` est à toi,
et seul ce troc le tient. Index `memory/MEMORY.md` → octets de l'index.
`description` → octets des descriptions. Corps d'une fiche → **rien tant que CETTE fiche reste sous
son plafond, et ce qui sort se prend DANS LA MÊME FICHE, jamais dans une autre**. *(Énoncé du
refroidissement et du troc : le fragment `regles-a-froid-oui` du règlement ; ce geste-ci est la
promotion.)*
