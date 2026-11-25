---
name: demarrage
description: Bilan de début de séance, rendu depuis les données du hook — invoqué au lancement (`/demarrage`), ou à la main pour le rejouer.
disable-model-invocation: true
---

# Démarrage de séance — rendre le bilan

> Premier message de chaque séance interactive neuve, posé par le mod `mods/demarrage-auto` ; se tape
> aussi à la main. Le hook `engine/boot-check.sh` a déjà injecté les **données** ; cette compétence
> dit comment les **rendre**.

## 1. Portée et fraîcheur

Le bloc injecté s'ouvre sur `=== ClaudeOS — démarrage de la session PRINCIPALE · <date heure> ===`
ou `=== ClaudeOS — démarrage d'une session de PROJET : <niveau> · <date heure> ===`. Sa portée
choisit la branche du § 2.

Bloc absent, daté d'un autre jour qu'aujourd'hui — séance ouverte depuis plusieurs jours, la
principale l'est souvent —, ou qui dit le bilan d'ouverture décliné (`BILAN_DEMARRAGE=non`) : rejouer
`CLAUDEOS_BILAN_DEMANDE=1 bash ~/.claude/engine/boot-check.sh </dev/null`, qui ne fait que lire, et
rendre depuis le champ `additionalContext` de sa sortie. Le dire en une ligne.

**Fini quand** la portée est connue et que les données sont du jour, bilan complet compris.

## 2. Rendre la branche de sa portée

**Lire en entier le fichier de la branche, puis rendre selon lui** : [`PRINCIPALE.md`](PRINCIPALE.md)
pour une session principale, [`PROJET.md`](PROJET.md) pour une session de projet.

**Fini quand** le fichier de la branche a été lu dans cette séance et que son propre critère de fin
est tenu.

## 3. Composer « À faire aujourd'hui »

- Ranger chaque proposition en **FAIRE**, **DÉCIDER** (sa décision), **RELANCER** (un tiers) ou
  **INTENDANCE** : un ou deux fils dont l'assistant est porteur, que je solde seul en séance, sur
  son accord.
- Proposer le faisable du jour : les fils 👤 que le bloc dit « proposables aujourd'hui », et ceux de
  l'assistant ou sans porteur qu'il liste ensuite. RELANCER se tire de sa ligne « ⏳ en attente ». Ce qui est
  bloqué ailleurs, ce qu'il range sous « Ailleurs » et ce qu'il marque « (hors créneau) » se cite,
  daté, hors de la proposition.
- Un dépassement de plafond appartient à l'audit : la proposition le laisse de côté, mesure comprise.
- L'ancienneté se dit dans l'unité de la vue — « ouvert depuis 49 j », « reconduit 9 fois depuis
  15 jours » — et jamais « en retard ».
- La proposition éclaire, elle ne commande pas : l'utilisateur connaît un contexte que ces fichiers
  ignorent, et il tranche.

## 4. Ensuite

Enchaîner sur sa demande, s'il en a fait une. Le détail des séances passées se lit dans le journal
seulement quand il déclare un contexte de travail ou demande l'historique.
