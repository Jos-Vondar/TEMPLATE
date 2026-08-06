# Gabarit — créer un domaine de travail

> Un « domaine » est un contexte de travail qui a ses propres règles, sa propre mémoire et sa propre reprise : un client, un employeur, un champ personnel. Le créer, c'est cinq gestes et **une ligne au manifeste** — celle qu'on oublie, et dont l'oubli ne se manifeste par rien.

## Les cinq gestes

```bash
DOMAINE=NOM_DU_DOMAINE          # majuscules et traits bas
D="$HOME/workstations/$DOMAINE"

mkdir -p "$D/_IGNORE"           # réceptacle confidentiel, à la racine du domaine
touch "$D/CLAUDE.md"            # règles locales, prioritaires sur les globales
touch "$D/MEMORY.md"            # faits datés de ce domaine
touch "$D/HANDOFF.md"           # état de reprise
```

Puis, et c'est le geste qui compte :

```bash
echo "workstations/$DOMAINE  workstations/$DOMAINE  mirror" >> ~/.claudeos/engine/config/SYNC_MAP
```

**Sans cette ligne, le dossier existe, on y travaille, et il n'est jamais sauvegardé.** Rien ne le dira : ni la sauvegarde, qui ne connaît que le manifeste, ni la synchronisation, qui en dérive son périmètre.

Enfin, ajouter une ligne à la table de routage du fichier de règles racine, la conception — sinon l'assistant ne saura pas que ce domaine existe ni quelles instructions y charger.

## Ce que chaque fichier porte

| Fichier | Ce qu'il porte | Ce qu'il ne porte pas |
| :--- | :--- | :--- |
| `CLAUDE.md` | Les règles propres au domaine : conventions, vocabulaire, interdits. Elles priment sur les règles globales. | Des faits, des statuts, des dates. |
| `MEMORY.md` | Les faits datés, les décisions, les états. Écrit au fil de l'eau. | Des règles de comportement. |
| `HANDOFF.md` | Où on en est, ce qui reste à faire, ce qui attend un tiers. Écrasé à chaque clôture. | Un historique — il vit dans le journal. |
| `_IGNORE/` | Les documents qu'on ne peut pas versionner. Hors sauvegarde, **seul exemplaire**. | Rien qu'on ne puisse se permettre de perdre. |

## Vérifier

```bash
bash ~/.claudeos/engine/selftest.sh
```

Il contrôle notamment que tout dossier annoncé par une table de routage existe sur le disque, et que tout domaine doté d'une mémoire a sa reprise.

## Retirer un domaine

Retirer la ligne du manifeste **et** la ligne de la table de routage — les deux moitiés partent ensemble. Une entrée de routage sans dossier promet ce qui n'existe pas ; un dossier hors manifeste travaille sans filet.
