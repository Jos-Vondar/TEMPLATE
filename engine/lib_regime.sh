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

# claudeos_en_suspens DÉPÔT — rend 0 si un rebase ou une fusion y est en cours, ou si HEAD y est
# détachée : un commit fait là n'est sur aucune branche, et rien ne le poussera. Le dossier git
# se prend ABSOLU : `--git-path` rend un chemin relatif au dépôt, que `[ -d ]` lirait ailleurs.
claudeos_en_suspens() {
    local r="$1" gd
    gd="$(git -C "$r" rev-parse --absolute-git-dir 2>/dev/null)" || return 1
    [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ] || [ -f "$gd/MERGE_HEAD" ] && return 0
    git -C "$r" symbolic-ref -q HEAD >/dev/null || return 0
    return 1
}

# claudeos_integre DÉPÔT NOM PRÉFIXE — intègre le distant avant de pousser. Deux appelants : la
# clôture et la préparation de session. Écrit à l'audit de la v3.0.0, qui a trouvé deux défauts au
# même endroit. Un `pull --rebase` en conflit laissait le dépôt en plein rebase, se disait
# « hors-ligne ? » et rendait 0 ; et un rebase APLATIT les fusions, celle d'une mise à jour du
# template comprise, dont il rejoue l'histoire par-dessus la branche, en conflit.
# Donc : rien à intégrer, rien ne bouge ; une histoire locale linéaire se rebase ; une fusion locale
# s'intègre par une fusion ; un échec s'annule et se nomme.
# Codes : 0 intégré, ou rien à intégrer · 1 distant injoignable · 8 conflit ou échec, annulé, rien
# n'est intégré et les commits locaux sont intacts.
claudeos_integre() {
    local r="$1" nom="$2" pre="$3" err amont conflits
    if ! err="$(git -C "$r" fetch -q 2>&1)"; then
        echo "$pre WARN : $nom — distant injoignable, rien n'est intégré : ${err%%$'\n'*}" >&2
        return 1
    fi
    amont="$(git -C "$r" rev-parse -q --verify '@{u}' 2>/dev/null)" || return 0
    git -C "$r" merge-base --is-ancestor "$amont" HEAD && return 0
    if git -C "$r" merge-base --is-ancestor HEAD "$amont"; then
        err="$(git -C "$r" merge -q --ff-only "$amont" 2>&1)" && return 0
    elif [ -n "$(git -C "$r" rev-list --merges "$amont..HEAD")" ]; then
        err="$(git -C "$r" merge -q --no-edit "$amont" 2>&1)" && return 0
    else
        err="$(git -C "$r" rebase -q "$amont" 2>&1)" && return 0
    fi
    conflits="$(git -C "$r" diff --name-only --diff-filter=U 2>/dev/null)"
    local gd; gd="$(git -C "$r" rev-parse --absolute-git-dir)"
    if [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]; then
        git -C "$r" rebase --abort
    elif [ -f "$gd/MERGE_HEAD" ]; then
        git -C "$r" merge --abort
    fi
    if [ -n "$conflits" ]; then
        echo "$pre ⛔ $nom : CONFLIT avec le distant — rien n'est intégré ni poussé, tes commits locaux sont intacts." >&2
        printf '%s\n' "$conflits" | sed "s/^/$pre      /" >&2
        echo "$pre   Un autre poste a poussé des changements aux mêmes fichiers. Résous-les avec git — un" >&2
        echo "$pre   ETAT.md se résout en le reprojetant, etat.py projette --niveau <son dossier> —, puis relance." >&2
    else
        echo "$pre ⛔ $nom : l'intégration du distant a échoué, rien n'est poussé : ${err%%$'\n'*}" >&2
    fi
    return 8
}
