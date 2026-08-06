# Règles — créer, nommer, déplacer, supprimer un fichier ou un dossier

> Fiche situationnelle. Déclencheur : je crée, nomme, déplace ou supprime un fichier ou un dossier.

## Nommage

- Fichiers `.md` libres (créés par Claude) : MAJUSCULES_UNDERSCORES. Exemple : `WORKSTATION_TEMPLATE.md`, le document de référence du projet.
- Exceptions — noms fixes, non soumis au nommage libre et non traités comme dérogation de casse : `CLAUDE.md`, `MEMORY.md`, `SKILL.md` (réservés par l'outil), `DESIGN.md`, `ARCHIVE.md` (conventions internes établies), fichiers horodatés générés (`rapport-AAAA-MM-JJ.md`, plans et specs sous `docs/`).

## Création d'un dossier projet ou app

- Scaffolder un `_IGNORE/` à la racine de tout dossier **projet** (`~/workstations/<DOMAINE>/<PROJET>/`) à sa création, y compris hors de la procédure de création de workstation. Sans lui, le premier document client sensible atterrit en zone sauvegardée.
- Une **application** n'en reçoit pas, ni aucun sous-dossier d'un projet : un seul réceptacle par projet, à sa racine. Le confidentiel des documents d'une app va dans le `_IGNORE/` de son projet.
- Un **projet imbriqué** dans un autre — dossier portant ses propres règles et sa mémoire sous un projet parent — n'en reçoit pas non plus : il dépend du réceptacle de son parent.
- **Plans et spécifications** : `docs/plans/` et `docs/specs/` à la racine des documents du projet ou de l'app. Jamais de niveau intermédiaire portant le nom de l'outil qui a produit le fichier — l'outil changera, le fichier restera. Un plan qui porte sur le système lui-même vit dans `~/docs/{plans,specs}/` (décision, trois formes locales divergentes ramenées à une).

## Suppression dans un `_IGNORE/`

Ce dossier est hors sauvegarde et hors synchronisation : son contenu est le seul exemplaire, sur une seule machine. Une suppression y est définitive.

1. Classer chaque fichier : copie unique / stocké ailleurs / régénérable / public.
2. Faire confirmer par l'utilisateur.
3. Ne jamais supprimer une copie unique sans accord explicite.

## Nettoyer ses propres fichiers d'essai

**Ne supprimer que ce qu'on a créé, nommément.** Un nettoyage d'essai se fait fichier par fichier, jamais en effaçant le dossier qui les contient : ce dossier existait peut-être avant, avec du contenu qui n'est pas à nous. Avant de créer un dossier pour un essai, vérifier qu'il n'existe pas déjà ; s'il existe, y déposer les fichiers d'essai et ne retirer qu'eux.

Corollaire, qui est le vrai motif : un dossier hors sauvegarde (`_IGNORE/`, local-only) ne pardonne pas — l'historique ne rattrape rien, et la suppression est définitive.

*(→ origines)*

## Chemins

- Rappel du racine (§4), qui en est la source : aucun chemin propre à un poste dans un fichier suivi ou un script.
- Le dossier de mémoire automatique porte un nom dérivé du dossier personnel — il diffère d'un poste à l'autre. Ne jamais l'écrire en dur : le résoudre (voir la carte de routage du `CLAUDE.md` racine).
