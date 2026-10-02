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
- **Plans et spécifications** : `docs/plans/` et `docs/specs/` à la racine des documents du projet ou de l'app. Jamais de niveau intermédiaire portant le nom de l'outil qui a produit le fichier — l'outil changera, le fichier restera. Un plan qui porte sur le **système** vit dans `~/.claude/docs/{plans,specs}/` ; celui propre à un domaine reste chez lui, sous son propre `docs/`. *(`~/.claude/plans/` est un dossier de l'outil, ignoré par la liste noire : un plan qui s'y range sort de la sauvegarde.)*

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

**Et le déplacement se clôt par la chasse aux pointeurs**, comme tout déplacement : `_IGNORE/` étant
hors sauvegarde, un renvoi mort y est invisible au dépôt et ne se verra qu'au moment où quelqu'un
cherche le fichier.

*Forme écartée, à ne pas rejouer : renommer le fichier avec le nom de l'app en préfixe, à plat dans
`_IGNORE/`. Elle garde le nom de l'app aussi, donc les deux formes satisfont la consigne et ont déjà
coexisté dans un même dossier. Le sous-dossier l'emporte : il groupe quand une app porte plusieurs
fichiers, et la racine ne se remplit pas.*

## Suppression dans un `_IGNORE/`

Ce dossier est hors sauvegarde et hors synchronisation : son contenu est le seul exemplaire, sur une seule machine. Une suppression y est définitive.

1. Classer chaque fichier : copie unique / stocké ailleurs / régénérable / public.
2. Faire confirmer par l'utilisateur.
3. Ne jamais supprimer une copie unique sans accord explicite.

## Nettoyer ses propres fichiers d'essai

**Ne supprimer que ce qu'on a créé, nommément.** Un nettoyage d'essai se fait fichier par fichier, jamais en effaçant le dossier qui les contient : ce dossier existait peut-être avant, avec du contenu qui n'est pas à nous. Avant de créer un dossier pour un essai, vérifier qu'il n'existe pas déjà ; s'il existe, y déposer les fichiers d'essai et ne retirer qu'eux.

Corollaire, qui est le vrai motif : un dossier hors sauvegarde (`_IGNORE/`, local-only) ne pardonne pas — l'historique ne rattrape rien, et la suppression est définitive.

## Avant de déplacer un dossier, sonder qui y travaille

Un renommage ou un déplacement coupe toute session dont le dossier de travail porte l'ancien chemin. **L'activité d'un pair est un fait vivant (règlement, socle, « Mémoire et vérité ») : sa source canonique est un relevé pris au moment du geste.** Lister les sessions juste avant d'agir.

Motif, sur pièce : le 2026-08-17, un renommage de domaine validé par l'utilisateur imposait de fermer la session projet dont le dossier portait l'ancien chemin. L'ordre des gestes s'est appuyé sur un relevé lu vingt minutes plus tôt, qui donnait la session au repos — elle ne l'était plus, l'utilisateur était en train de lui parler. Rien n'a été perdu sur disque (dossier déplacé, transcription de 448 tours migrée avec le slug, session relancée sur sa conversation), mais le contexte vivant a sauté et c'est lui qui l'a signalé. La règle générale « avant de supprimer ou d'écraser, regarder la cible » existait déjà, et n'a rien déclenché : « la cible » se lit comme un fichier, pas comme un interlocuteur.

## Un fichier GELÉ ne se supprime, ne se renomme ni ne se déplace

Le contrôle 14 ne lit que `--diff-filter=ACM` : suppression et renommage passent **sans un mot**.
Une archive gelée est souvent le seul exemplaire de faits antérieurs à l'historique git.

## Supprimer, déplacer ou renommer se clôt par la chasse aux pointeurs

Supprimer, fusionner, déplacer ou renommer une capacité — compétence, agent, fichier de référence, script — **n'est fini que quand une recherche de l'ancien nom sur le corpus ne rend plus que le journal**. Chaque pointeur trouvé se corrige dans le même geste, pas à la passe suivante : la carte de rappel, les documents de conception, les compétences qui citaient la capacité, les tables de routage.

**Les gardes mécaniques passent en premier** — `.gitignore`, listes blanches de sauvegarde, motifs de contrôle. Un pointeur mort dans un document envoie dans le vide, ce qui se voit ; un garde qui cite un chemin périmé fait sortir un fichier de la sauvegarde en silence, ce qui ne se voit pas. Une autorisation ancrée sur l'ancienne racine cesse de couvrir le nouveau chemin, et le rapport de fichiers refusés ne le dira pas : un fichier suivi n'est pas « refusé », il n'est simplement plus autorisé.

Motif, sur pièce : le 2026-08-18, le rangement d'un répertoire d'app en `docs/` a déplacé dix fichiers. 24 pointeurs internes corrigés, 2 pointeurs externes remontés — il y en avait 5. Les 3 manquants vivaient dans `.gitignore`, qui autorisait `*.sql` et un fichier nommé en les ancrant sur la racine de l'app. Trois documents suivis au dépôt sortaient de la sauvegarde sans aucun avertissement.

Deux traits à connaître avant de commencer, parce qu'ils décident du geste :

- **Le registre de la session en cours garde l'ancien nom jusqu'au redémarrage.** Une capacité renommée est donc inatteignable d'ici là — un chemin de repli pris en silence à ce moment-là ressemble à un fonctionnement normal.
- **Varier les motifs de recherche**, comme partout : nom court contre nom long, terme partiel, casse. **Et varier les TYPES DE FICHIER, pas seulement les motifs** : un chemin en dur vit aussi dans du **code**, où il est plus dangereux que dans un document — un renvoi mort dans un `.md` égare une session, le même dans un script le fait planter, et seulement à l'exécution, donc peut-être des semaines plus tard sur un autre poste. Chercher sans filtre de type, ou nommer explicitement `*.py`, `*.sh`, `*.ps1`, `*.yaml` en plus des `*.md` *(mesuré le 2026-08-24 : une chasse limitée aux documents a déclaré le rangement fini, et un `Path` composé en dur dans un script Python restait cassé — relevé par une session de projet, pas par moi)*. Corollaire de forme : un chemin **composé** morceau par morceau — `racine / "_IGNORE" / "APP" / "fichier"` — ne contient nulle part la chaîne complète, donc chercher aussi le **dernier segment seul**. Un pointeur qui survit à un seul motif survit à la suppression. **Et compter les occurrences dans chaque fichier touché** : un même document cite volontiers le chemin deux fois, et corriger la première le fait passer pour traité *(mesuré le 2026-08-22, sur un repérage qui n'en avait vu qu'une)*.

Motif, sur pièce : la classe a été nommée quatre fois sans jamais devenir une règle. Le 2026-08-13, trois manifestations le même jour — cinq pointeurs morts dans la carte de rappel issus des fusions de la veille, un document de conception annonçant un agent supprimé dans un paragraphe et décrivant encore son travail dans cinq autres, une section pointant une compétence qui avait cédé la conduite quatre jours plus tôt. Le 2026-08-10, le registre annonçait encore un nom supprimé une heure avant, et c'est l'utilisateur qui l'a relevé. Antécédents : le renommage `rules/` → `fiches/` du 2026-08-03, un agent renommé laissant « deux résidus documentés plutôt que réparés » le 2026-08-09.

*Le corollaire étroit — « quand un contrôle change un seuil, chercher qui le cite », dans `controles-et-alarmes` — reste chez lui : il vise un seuil, celle-ci vise une capacité.*

## Chemins

- **Si `MULTIPOSTE=oui`, aucun chemin propre à un poste dans un fichier suivi ou un script** : la règle est au règlement (« Plusieurs postes »), et le contrôle hebdomadaire 22 la tient.
- La mémoire automatique vit dans `~/.claude/memory`, par `autoMemoryDirectory` de `settings.json` ; les dossiers `projects/<slug>/` gardent un nom propre au poste, donc ne jamais écrire un slug en dur.
