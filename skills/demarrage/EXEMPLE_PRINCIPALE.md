# Un bilan de session principale réussi

> Exemple aux données inventées, dans la forme d'un rendu réussi. Abrégé là où se trouve `…`.
> **Il donne la forme.** Chaque élément du bilan — fil, ancienneté, date, compte, alerte, choix et
> ordre des propositions — se lit dans le bloc du jour et se compose par le § 3 de `SKILL.md` ; ce
> qui figure ici sans figurer dans le bloc n'entre pas dans le bilan.

## Le bloc reçu, en résumé

Poste `poste-bureau`, croisière J 3/28, synchro à jour par un fetch réutilisé. Dernière principale la
veille à 18:40, PROCHAIN « envoyer la maquette d'accueil ». Une alerte 🔓, aucun ⏰ échu. Créneau du
jeudi ouvert pour ATELIER, 12 fils actifs. Une session de projet ouverte.

## Le rendu

Le bilan s'écrit en markdown, directement dans la réponse, pour que le terminal le mette en forme.
Le bloc de code ci-dessous sert seulement à présenter l'exemple dans ce fichier.

```
**Poste : poste-bureau** · croisière J 3/28
**Synchro :** à jour (fetch réutilisé, fait il y a 12 s).

### 1. À faire aujourd'hui (jeudi, créneau ATELIER)
- **FAIRE** — Envoyer la maquette d'accueil, le PROCHAIN d'hier soir. Elle semble prête : c'est une
  **déduction**, la séance la dit relue sans dire l'envoi fait.
- **FAIRE** — `u-ecran-recherche`, ouvert depuis 30 j : le gabarit a été validé le 2026-10-26, la
  suite du parcours peut reprendre.
- **DÉCIDER** — `u-choix-hebergement`, ouvert depuis 12 j : deux offres comparées, il manque ton choix.
- **RELANCER** — `u-devis-imprimeur`, en attente depuis 9 j.
- Hors proposition : `u-bilan-trimestre` ne se fait pas avant le 2026-12-01.

### 2. Fait depuis ta dernière principale
- **2026-10-28 18:40** · poste-bureau, hier soir. Maquette d'accueil relue … PROCHAIN : envoyer la
  maquette d'accueil.
- Aucune séance de projet écrite depuis.

### 3. Rappels
- 6 rappels lus, aucun ⏰ échu.
- 🔓 Une alarme a été levée aujourd'hui sur `.claude/.git/ALARMES_FORCEES.log`, sans s'être
  déclenchée. Il faut vérifier que son motif tient toujours.

### 4. Fils ouverts
- **👤 À toi** : `u-ecran-recherche` (ATELIER, 30 j), `u-choix-hebergement` (ATELIER, 12 j).
  Ailleurs : INTERNE `u-note-frais` 4 j.
- **🤖 Assistant** : `u-relire-gabarit` (ATELIER, 6 j).
- **⏳ En attente** : `u-devis-imprimeur` (ATELIER, 9 j).
- **Porteurs des fils actifs** : 👤 3 · 🤖 4 · ⏳ 2 · ❔ 3.
- **Autres domaines** : INTERNE 9 · ASSO 6 · système 2.
- **Total** : 41 dus ouverts, dont 12 dormants.
- **Sessions ouvertes** : tmux : atelier.

Comme aucun rappel n'est échu, je n'ai pas de question à te poser. Je t'écoute.
```

## Pourquoi il marche

- **Le PROCHAIN de la dernière séance ouvre la proposition quand il est faisable aujourd'hui** ; ce
  qui ne l'est pas part hors proposition, daté (`u-bilan-trimestre`). C'est ce qui relie la séance à
  la précédente.
- **L'inféré est étiqueté comme tel**, à la ligne où il sert (« c'est une déduction »).
- **L'ancienneté est dite dans l'unité de la vue** (« ouvert depuis 30 j »), avec le dernier fait daté
  du fil quand le bloc le donne.
- **Une ligne attendue qui est vide le dit en une ligne** (« aucun ⏰ échu », « Aucune séance de
  projet ») : le lecteur sait qu'on a regardé. Seul « État hors du vert » se tait quand il est vide
  (`PRINCIPALE.md`).
- **La synchro se dit comme le bloc la mesure** — fetch fait à ce démarrage, ou réutilisé —, jamais
  plus vérifiée qu'elle ne l'est.
- **La fin dit pourquoi aucune question ne suit**, au lieu de s'arrêter sans un mot.
