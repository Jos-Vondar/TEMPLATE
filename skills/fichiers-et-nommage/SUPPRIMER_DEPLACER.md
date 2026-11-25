# Supprimer, déplacer ou renommer un fichier ou un dossier

> Annexe de `fichiers-et-nommage`, lue en entier avant toute suppression, tout déplacement, tout
> renommage hors zone jetable. Le crochet `rappel-fichiers-nommage.sh` l'exige au premier geste.

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

La règle « avant de supprimer ou d'écraser, regarder la cible » ne suffit pas : « la cible » se lit comme un fichier, pas comme un interlocuteur, et un relevé vieux de vingt minutes peut donner au repos une session à qui l'utilisateur parle.

## Un fichier GELÉ ne se supprime, ne se renomme ni ne se déplace

Le contrôle 14 ne lit que `--diff-filter=ACM` : suppression et renommage passent **sans un mot**.
Une archive gelée est souvent le seul exemplaire de faits antérieurs à l'historique git.

## Supprimer, déplacer ou renommer se clôt par la chasse aux pointeurs

Supprimer, fusionner, déplacer ou renommer une capacité — compétence, agent, fichier de référence, script — **n'est fini que quand une recherche de l'ancien nom sur le corpus ne rend plus que le journal et les fichiers gelés**. Chaque pointeur trouvé se corrige dans le même geste, pas à la passe suivante : la carte de rappel, les documents de conception, les compétences qui citaient la capacité, les tables de routage.

**Les gardes mécaniques passent en premier** — `.gitignore`, listes blanches de sauvegarde, motifs de contrôle. Un pointeur mort dans un document envoie dans le vide, ce qui se voit ; un garde qui cite un chemin périmé fait sortir un fichier de la sauvegarde en silence, ce qui ne se voit pas. Une autorisation ancrée sur l'ancienne racine cesse de couvrir le nouveau chemin, et le rapport de fichiers refusés ne le dira pas : un fichier suivi n'est pas « refusé », il n'est simplement plus autorisé. *(Mesuré : sur dix fichiers déplacés, 3 des 5 pointeurs externes vivaient dans `.gitignore`.)*

Deux traits à connaître avant de commencer, parce qu'ils décident du geste :

- **Le registre de la session en cours suit un renommage avec retard.** Une compétence créée en séance peut rester introuvable à l'appel quelques dizaines de secondes, et n'apparaître à la liste qu'au bout de quelques minutes ; une compétence supprimée y reste un moment. Après un renommage, appeler le nouveau nom seulement quand il figure à la liste : un chemin de repli pris en silence entre-temps ressemble à un fonctionnement normal.
- **Varier les motifs de recherche**, comme partout : nom court contre nom long, terme partiel, casse. **Et varier les TYPES DE FICHIER, pas seulement les motifs** : un chemin en dur vit aussi dans du **code**, où il est plus dangereux que dans un document — un renvoi mort dans un `.md` égare une session, le même dans un script le fait planter, et seulement à l'exécution, donc peut-être des semaines plus tard sur un autre poste. Chercher sans filtre de type, ou nommer explicitement `*.py`, `*.sh`, `*.ps1`, `*.yaml` en plus des `*.md`. Corollaire de forme : un chemin **composé** morceau par morceau — `racine / "_IGNORE" / "APP" / "fichier"` — ne contient nulle part la chaîne complète, donc chercher aussi le **dernier segment seul**. Un pointeur qui survit à un seul motif survit à la suppression. **Et compter les occurrences dans chaque fichier touché** : un même document cite volontiers le chemin deux fois, et corriger la première le fait passer pour traité.
