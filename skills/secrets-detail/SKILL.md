---
name: secrets-detail
description: Stocker un secret, ou comprendre pourquoi la sauvegarde refuse un fichier. Porte les régimes haute valeur et faible valeur, le jeton à privilège minimal, le triage par document devant une alarme.
---

# Règles — secrets, détail des régimes

> Fiche situationnelle. Déclencheur : un secret doit être stocké quelque part, ou la sauvegarde refuse un fichier.
> **Les trois interdits absolus vivent ICI, et cette fiche en est la seule autorité** : jamais de valeur de secret dans l'arbre sauvegardé — ni directement, ni en la faisant saisir dans un fichier que la session écrit ou édite ; classification toujours demandée à l'utilisateur dès qu'un secret apparaît ; secret exposé en séance — collé, ou affiché par une commande — **égale compromis**, donc à régénérer et à consigner.
>
> *Le règlement ne les porte pas : ils se convoquent au moment où un secret apparaît, par cette fiche. Contrepartie assumée : une session qui ne la charge pas n'a aucune règle sur les secrets — seul le crochet refuse un secret reconnu, code 14, au commit comme à la clôture sans git.*
>
> Le reste de la fiche porte le détail des emplacements et la conduite devant un refus de sauvegarde.

## Régime selon la valeur

- **Haute valeur** : local-only strict. Hors de l'arbre sauvegardé, ou dossier gitignoré et exclu de la synchronisation. Jamais synchronisé, jamais committé.
- **Faible valeur / opérationnel** (clé API de test, identifiants de bac à sable) : peut vivre dans l'emplacement synchronisé dédié `~/.claude/secrets-shared/`, pour être disponible sur tous les postes. Risque résiduel assumé : dépôt privé et faible valeur. L'alarme de nom de secret du crochet est levée sur ce seul emplacement (`engine/hooks/pre-commit-alarmes.sh`), et `engine/controle-secrets.sh` l'exclut de son balayage. En `GIT=aucun`, rien ne se synchronise : l'emplacement ne sert qu'à ranger.
- Toujours privilégier un jeton à privilège minimal : lecture seule, granulaire, portée réduite.

## Sauvegarde refusée par une alarme

Motifs possibles : fichier binaire, secret détecté par son nom ou son contenu, donnée client. Ne jamais répondre par un contournement global.

1. Présenter à l'utilisateur chaque fichier signalé.
2. Trois options par fichier : garder (faux positif), déplacer dans le `_IGNORE/` de son projet (document client), supprimer.
3. Appliquer, puis relancer la sauvegarde : le crochet nomme le motif de chaque refus.
