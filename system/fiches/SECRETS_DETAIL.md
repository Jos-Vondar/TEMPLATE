# Règles — secrets, détail des régimes

> Fiche situationnelle. Déclencheur : un secret doit être stocké quelque part, ou la sauvegarde refuse un fichier.
> Les trois interdits absolus vivent dans le `CLAUDE.md` racine et ne sont pas répétés ici : jamais de valeur dans l'arbre sauvegardé, classification toujours demandée à l'utilisateur, secret exposé en séance à régénérer et consigner. Cette fiche ne porte que le détail des emplacements et la conduite devant un refus de sauvegarde.

## Régime selon la valeur

- **Haute valeur** : local-only strict. Hors de l'arbre sauvegardé, ou dossier gitignoré et exclu de la synchronisation. Jamais synchronisé, jamais committé.
- **Faible valeur / opérationnel** (clé API de test, identifiants de bac à sable) : peut vivre dans l'emplacement dédié `~/.claude/secrets-shared/`, qui est **local à chaque machine et ne voyage pas** — le verrou l'exclut nommément. Contrepartie assumée : ces clés se reposent sur chaque poste. L'alarme secret de la sauvegarde ne s'applique pas à cet emplacement, et les deux vont ensemble : c'est parce que rien n'en sort qu'on peut y déposer sans faire crier l'alarme.
- Toujours privilégier un jeton à privilège minimal : lecture seule, granulaire, portée réduite.

## Sauvegarde refusée par une alarme

Motifs possibles : fichier binaire, secret détecté par son nom ou son contenu, donnée client. Ne jamais répondre par un contournement global.

1. Présenter à l'utilisateur chaque fichier signalé.
2. Trois options par fichier : garder (faux positif), déplacer dans le `_IGNORE/` de son app (document client), supprimer.
3. Appliquer, puis relancer la sauvegarde.
