# Des événements réussis — deux décisions, deux dus

> Événements écrits pour montrer la forme, sur un projet imaginaire ; la commande ajoute `--niveau`.
> Chaque `--texte` tient sur UNE ligne : il est coupé ici pour la lecture. **Ils donnent la forme.**
> La ref, le chantier, la source, la commande, les chemins et les dates viennent du fait en cours.
> Le contrat des champs reste en tête d'`engine/etat.py`.

## Décision — 172 caractères

```
--type decision --op pose --ref d-export-csv-ecarte
--texte "L'export CSV quotidien est ÉCARTÉ, à l'usage : le tableur du service le relit mal et personne
ne l'ouvre. Le rapport part en PDF hebdomadaire, produit par la même commande."
```

Pourquoi elle marche :
- **Le verdict tombe dans la première proposition** (ÉCARTÉ), le motif tient dans la suivante.
- **Elle dit ce qui le remplace**, donc on ne rouvre pas la question en cherchant une alternative.
- Aucun récit de la séance : il irait dans `seance` ou dans une `observation`.

## Décision qui ferme une question — 201 caractères

```
--type decision --op pose --ref d-etiquettes-gardees --chantier rangement
--texte "LES TROIS ÉTIQUETTES brouillon, a-relire et archive SONT GARDÉES, bien qu'elles ne passent pas
la règle de tri des étiquettes — tranché par l'utilisateur le 2026-03-12. Ne plus les proposer au
retrait."
```

Pourquoi elle marche :
- **Elle dit qui a tranché et quand.**
- **Sa dernière phrase est la consigne pour la suite** (« Ne plus les proposer »). C'est elle qui
  empêche de reposer une question déjà tranchée.

## Dû dont le prochain geste est à moi — 299 caractères

```
--type du --op ouvre --ref u-sauvegarde-base-a-planifier --chantier exploitation --porteur assistant
--source scripts/sauvegarde.sh
--texte "PLANIFIER LA SAUVEGARDE NOCTURNE de la base, depuis le dossier du projet : bash
scripts/sauvegarde.sh --installer pose la tâche planifiée, que crontab -l doit ensuite montrer. Tant
que ce n'est pas fait, la seule copie de la base est celle du jour, et une fausse manœuvre perd tout
depuis la veille."
```

Pourquoi il marche :
- **Il s'ouvre sur le verbe du prochain geste**, et dit où le faire (« depuis le dossier du projet »).
- **Le geste est rejouable** : la commande exacte, et celle qui constate qu'il est fait.
- **Il dit ce que coûte le retard**, ce qui permet de le classer sans rouvrir le contexte.
- **`--porteur` dit qui fait le prochain geste** : moi (`assistant`), l'utilisateur, ou un tiers
  qu'on attend.

## Dû dont le prochain geste est à l'utilisateur — 332 caractères

```
--type du --op ouvre --ref u-acces-prestataire-a-confirmer --chantier exploitation --porteur utilisateur
--source docs/ACCES.md
--texte "CONFIRMER L'ACCÈS DU PRESTATAIRE AU DÉPÔT. VÉRIFIÉ le 2026-03-14 vers 10 h : son invitation
figure parmi les invitations en attente du dépôt (gh api repos/<propriétaire>/<dépôt>/invitations).
Reste, geste de l'utilisateur : relancer le prestataire, puis constater qu'il figure parmi les
collaborateurs et qu'il a poussé une branche."
```

Pourquoi il marche :
- **Il sépare le fait du reste** : VÉRIFIÉ, avec la date et la commande ; puis « Reste ».
- **Il nomme qui fait le prochain geste** (l'utilisateur) et à quoi on reconnaît que c'est fait.
- Piège : une date antérieure au jour, écrite dans le texte d'un dû, en recule la naissance et fausse
  son ancienneté dans le bilan. Ici elle est du jour même. Sinon, poser `--origine <date du jour>`.
