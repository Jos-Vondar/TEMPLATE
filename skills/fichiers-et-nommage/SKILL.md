---
name: fichiers-et-nommage
description: Créer, nommer, déplacer ou supprimer un fichier ou un dossier. Porte les conventions de nommage, les réceptacles `_IGNORE/`, la suppression en zone hors sauvegarde.
---

# Règles — créer, nommer, déplacer, supprimer un fichier ou un dossier

> Fiche situationnelle. Déclencheur : je crée, nomme, déplace ou supprime un fichier ou un dossier.

## Nommage

- Fichiers `.md` libres (créés par Claude) : MAJUSCULES_UNDERSCORES. Exemple : `DOMAINE_TEMPLATE.md`.
- Exceptions — noms fixes, non soumis au nommage libre et non traités comme dérogation de casse : `CLAUDE.md`, `MEMORY.md`, `SKILL.md` (réservés par l'outil), le document de conception d'un niveau (son nom est fixé par `~/.claude/resources/DOMAINE_TEMPLATE.md`), fichiers horodatés générés (`rapport-AAAA-MM-JJ.md`, plans et specs sous `docs/`).

## Création d'un dossier projet ou app

- **Si `CONFIDENTIEL=oui`** (`reglages/REPONSES`), scaffolder un `_IGNORE/` à la racine de tout dossier **projet** (`<racine du domaine>/<PROJET>/`) à sa création, y compris hors de la procédure de création de domaine. Sans lui, le premier document confidentiel atterrit en zone sauvegardée.
- Une **application** n'en reçoit pas, ni aucun sous-dossier d'un projet : un seul réceptacle par projet, à sa racine. Le confidentiel des documents d'une app va dans le `_IGNORE/` de son projet.
- Un **projet imbriqué** dans un autre — dossier portant ses propres règles et sa mémoire sous un projet parent — n'en reçoit pas non plus : il dépend du réceptacle de son parent.
- **Plans et spécifications** : `docs/plans/` et `docs/specs/` à la racine des documents du projet ou de l'app. Jamais de niveau intermédiaire portant le nom de l'outil qui a produit le fichier — l'outil changera, le fichier restera. Un plan qui porte sur le **système**, ou propre à un domaine sans être d'un projet, va où le dit `carte-complete` § « Plans et specs », **seule autorité de ces emplacements** : ils ne se recopient pas ici.

## Ranger dans un `_IGNORE/` — un sous-dossier par app ou par projet

Quand `CONFIDENTIEL=oui`. Un `_IGNORE/` vit à la racine du **projet**, jamais au niveau d'une app :
c'est le règlement (« Documents confidentiels »), et un `_IGNORE/` mal placé envoie du confidentiel
en zone sauvegardée. Ce qui se décide ici est ce qu'on
range **dedans**.

**Un sous-dossier par app, portant le nom exact du dossier d'app.** Le fichier garde son nom. Ce qui
sert à tout le projet et non à une app va dans un dossier de rôle — `RESOURCES/` pour les gabarits et
les chartes.

**Avant de déplacer, établir l'app propriétaire, jamais la deviner.** Le nom du fichier suffit quand il
porte déjà le nom de l'app ; sinon, chercher qui le cite, sur plusieurs motifs. Un fichier dont aucun
document ne parle n'a pas d'app établie — demander, ne pas trancher.

**Et le déplacement se clôt par la chasse aux pointeurs** ([`SUPPRIMER_DEPLACER.md`](SUPPRIMER_DEPLACER.md)) : `_IGNORE/` étant
hors sauvegarde, un renvoi mort y est invisible au dépôt et ne se verra qu'au moment où quelqu'un
cherche le fichier.

*Le préfixe au nom de l'app, à plat dans `_IGNORE/`, garde lui aussi le nom de l'app ; le
sous-dossier l'emporte, parce qu'il groupe quand une app porte plusieurs fichiers et que la racine ne
se remplit pas.*

## Supprimer, déplacer, renommer

**Avant toute suppression, tout déplacement ou tout renommage hors zone jetable, lire en entier
[`SUPPRIMER_DEPLACER.md`](SUPPRIMER_DEPLACER.md)** : suppression dans un `_IGNORE/`, nettoyage de
ses propres essais, sessions qui travaillent dans un dossier à déplacer, fichiers gelés, chasse aux
pointeurs. Le crochet refuse une fois le premier geste de destruction tant qu'elle n'est pas lue.

## Chemins

- **Si `MULTIPOSTE=oui`, aucun chemin propre à un poste dans un fichier suivi ou un script** : la règle est au règlement (« Plusieurs postes »), et le contrôle hebdomadaire 22 la tient.
- La mémoire automatique vit dans `~/.claude/memory`, par `autoMemoryDirectory` de `settings.json` ; les dossiers `projects/<slug>/` gardent un nom propre au poste, donc ne jamais écrire un slug en dur.
