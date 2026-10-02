#!/usr/bin/env bash
# =============================================================================
# lib_regime.sh — le régime git du poste, lu par le moteur. SOURCÉ par `config.sh`, jamais lancé.
#
# Écrit le 2026-10-01, plan complet de templating § 2, A3 (`d-regime-sans-git`). Code PROPRE AU
# TEMPLATE : le moteur reporté de la source suppose git, et ce que le régime `GIT=aucun` demande
# en plus vit ici et dans `regime.py`, pour que les fichiers reportés ne changent que de quelques
# lignes et que la passe de report reste un diff.
# =============================================================================

# claudeos_regime — `github` ou `aucun`, d'après `GIT` dans `reglages/REPONSES`. Une clé absente
# garde le régime historique du moteur, `github` : c'est le seul qu'un poste non réglé puisse
# avoir, puisque rien d'autre n'a posé la marque d'une racine sans git (`.claudeos-racine`).
claudeos_regime() {
    local g
    g="$(claudeos_reponse GIT)" || g=""
    if [ "$g" = "aucun" ]; then echo aucun; else echo github; fi
}

# claudeos_racines — les RACINES des niveaux, que la clôture projette et que `etat.py` contrôle :
# les dépôts en régime GitHub (`claudeos_repos`), `~/.claude` seul sans git — ses dossiers de
# travail vivent sous `travail/`. `claudeos_repos` garde son sens, « les dépôts à committer », et
# rend RIEN sans git : c'est la différence entre les deux fonctions.
claudeos_racines() {
    if [ "$(claudeos_regime)" = aucun ]; then
        printf '%s\n' "$HOME/.claude"
        return 0
    fi
    claudeos_repos
}

# claudeos_suivis RACINE MOTIF… — les fichiers suivis qu'un motif désigne, un par ligne, relatifs à
# la racine : `git ls-files` dans un dépôt, le périmètre de `regime.py` sans git. Mêmes motifs
# dans les deux cas — `*` franchit `/`, un nom de dossier vaut tout ce qu'il contient.
claudeos_suivis() {
    local r="$1"; shift
    if [ -e "$r/.git" ]; then
        git -C "$r" ls-files -- "$@"
    else
        python3 "$SELF/regime.py" suivis "$r" "$@"
    fi
}
