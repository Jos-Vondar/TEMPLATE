#!/usr/bin/env bash
set -uo pipefail

# =============================================================================
# MACHINE TODO — consignes manuelles inter-machines (cf. le document de conception)
# Remplace l'ancien sync-changelog.sh : modèle minimal à cases à cocher, adapté
# au modèle séquentiel strict (jamais deux postes actifs à la fois).
#
# Fichier : engine/config/MACHINE_TODO.md — sections '## <id>' par poste, lignes
#   '- [ ] tâche' (ouverte) / '- [x] tâche · <date>' (faite, purgée à la clôture).
# Identité : SYNC_MACHINES mappe hostname -> id. Hostname inconnu = fail-loud
#   (jamais un faux « 0 à rattraper » qui masquerait une tâche due — ex-#20).
#
# Commandes :
#   add "<titre>" [--for <id>|all]  ajoute une case sous chaque poste ciblé
#                                   (défaut : tous les postes SAUF l'auteur)
#   pending                         liste numérotée des cases ouvertes de CE poste
#   done <N>                        coche la Nᵉ case ouverte de CE poste
#   count                           nb de cases ouvertes de CE poste (boot + sync)
#   purge                           supprime les lignes '- [x]' (rituel de clôture)
#
# Overrides de test (bac à sable) : MACHINE_TODO_FILE, SYNC_MACHINES_FILE, SYNC_MACHINE.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

TODO="${MACHINE_TODO_FILE:-$CFG/MACHINE_TODO.md}"
REGISTRY="${SYNC_MACHINES_FILE:-$SYNC_MACHINES}"

usage() { echo "usage: machine-todo.sh {pending|count|done <N>|purge|add \"<titre>\" [--for <id>|all]}" >&2; }

# --- Identité de poste : hostname -> id via le registre (fail-loud) -----------
resolve_me() {
    if [ -n "${SYNC_MACHINE:-}" ]; then printf '%s' "$SYNC_MACHINE"; return 0; fi
    local host id
    host="$(hostname)"
    [ -f "$REGISTRY" ] || { echo "[todo] ERREUR : registre $REGISTRY introuvable." >&2; return 2; }
    id="$(awk -v h="$host" '!/^[[:space:]]*#/ && NF>=2 && $1==h {print $2; exit}' "$REGISTRY")"
    [ -n "$id" ] || { echo "[todo] ERREUR : poste '$host' absent du registre $REGISTRY. Ajoute : $host <id> <label>" >&2; return 2; }
    printf '%s' "$id"
}

ensure() {
    [ -f "$TODO" ] && return 0
    {
        printf '# Machine TODO — consignes manuelles inter-machines\n\n'
        printf '> Cases `- [ ]` = à faire sur le poste de la section. `done` coche, la clôture purge les `- [x]`.\n'
        printf '> Écrit par machine-todo.sh (add/done). Identité de poste via SYNC_MACHINES.\n'
    } > "$TODO"
}

# id présent dans le registre ?
valid_id() { awk -v x="$1" '!/^[[:space:]]*#/ && NF>=2 && $2==x {f=1} END{exit !f}' "$REGISTRY"; }

# titres des cases OUVERTES de la section du poste $1
open_lines() {
    awk -v sec="## $1" '
        $0==sec {inseg=1; next}
        /^## / {inseg=0}
        inseg && /^- \[ \] / { sub(/^- \[ \] /,""); print }
    ' "$TODO"
}

# --- git : commit BORNÉ au seul fichier TODO (jamais l'index ambiant). Ne commite
# rien si le fichier vit hors du dépôt (bac à sable selftest via MACHINE_TODO_FILE).
git_commit() {
    git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || return 0
    case "$TODO" in "$ROOT"/*) : ;; *) return 0 ;; esac
    git -C "$ROOT" add -- "$TODO" 2>/dev/null || true
    git -C "$ROOT" commit -q -m "$1" -- "$TODO" 2>/dev/null || true
}

cmd_pending() {
    ensure; local ME; ME="$(resolve_me)" || return 2
    local n=0 line
    while IFS= read -r line; do n=$((n+1)); printf '  %d. %s\n' "$n" "$line"; done < <(open_lines "$ME")
    [ "$n" -eq 0 ] && echo "  (rien à rattraper pour '$ME')"
    return 0
}

cmd_count() {
    ensure; local ME; ME="$(resolve_me)" || return 2
    open_lines "$ME" | wc -l | tr -d ' '
}

# insère '- [ ] <titre>' juste sous l'en-tête '## <id>' (crée la section si absente)
add_line() {
    local id="$1" title="$2"
    if grep -q "^## $id\$" "$TODO"; then
        awk -v sec="## $id" -v ln="- [ ] $title" '{print} $0==sec {print ln}' "$TODO" > "$TODO.tmp" && mv "$TODO.tmp" "$TODO"
    else
        printf '\n## %s\n- [ ] %s\n' "$id" "$title" >> "$TODO"
    fi
}

cmd_add() {
    ensure; local ME; ME="$(resolve_me)" || return 2
    local title="$1" fors="${2:-}" targets="" t
    [ -n "$title" ] || { usage; return 1; }
    if [ "$fors" = "all" ]; then
        targets="$(awk '!/^[[:space:]]*#/ && NF>=2 {print $2}' "$REGISTRY")"
    elif [ -z "$fors" ]; then
        targets="$(awk -v me="$ME" '!/^[[:space:]]*#/ && NF>=2 && $2!=me {print $2}' "$REGISTRY")"
    else
        valid_id "$fors" || { echo "[todo] ERREUR : id de poste '$fors' absent du registre." >&2; return 2; }
        targets="$fors"
    fi
    [ -n "$targets" ] || { echo "[todo] ERREUR : aucune cible (registre vide ?)." >&2; return 2; }
    for t in $targets; do add_line "$t" "$title"; done
    echo "[todo] ajouté « $title » pour : $(echo $targets | tr '\n' ' ')"
    git_commit "todo: + '$title' (pour $(echo $targets | tr '\n' ' '))"
}

cmd_done() {
    ensure; local ME; ME="$(resolve_me)" || return 2
    local n="${1:-}" stamp
    [[ "$n" =~ ^[0-9]+$ ]] || { echo "[todo] usage: done <N> (numéro vu dans 'pending')" >&2; return 1; }
    stamp="$(date '+%Y-%m-%d')"
    awk -v sec="## $ME" -v target="$n" -v stamp="$stamp" '
        $0==sec {inseg=1; print; next}
        /^## / {inseg=0; print; next}
        inseg && /^- \[ \] / {
            k++
            if (k==target) { sub(/^- \[ \] /,""); print "- [x] " $0 " · " stamp; hit=1; next }
        }
        {print}
        END { if (!hit) exit 3 }
    ' "$TODO" > "$TODO.tmp"
    if [ $? -ne 0 ]; then rm -f "$TODO.tmp"; echo "[todo] ERREUR : pas de case ouverte n°$n pour '$ME'." >&2; return 1; fi
    mv "$TODO.tmp" "$TODO"
    echo "[todo] coché n°$n pour '$ME'."
    git_commit "todo: '$ME' a fait la tâche n°$n"
}

cmd_purge() {
    ensure
    awk '!/^- \[x\] /' "$TODO" > "$TODO.tmp" && mv "$TODO.tmp" "$TODO"
    awk 'NF==0{b++; if(b>1) next} NF{b=0} {print}' "$TODO" > "$TODO.tmp" && mv "$TODO.tmp" "$TODO"
    echo "[todo] purge des tâches faites."
    git_commit "todo: purge des tâches faites"
}

case "${1:-}" in
    pending) cmd_pending ;;
    count)   cmd_count ;;
    done)    shift; cmd_done "${1:-}" ;;
    purge)   cmd_purge ;;
    add)
        shift; [ $# -ge 1 ] || { usage; exit 1; }
        TITLE=""; FOR=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --for) shift; FOR="${1:-}";;
                *) TITLE="${TITLE:+$TITLE }$1";;
            esac
            shift
        done
        [ -n "$TITLE" ] || { usage; exit 1; }
        cmd_add "$TITLE" "$FOR"
        ;;
    *) usage; exit 1 ;;
esac
