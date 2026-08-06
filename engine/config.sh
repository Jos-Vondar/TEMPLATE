#!/usr/bin/env bash
# =============================================================================
# CONFIG — source unique des chemins & constantes ClaudeOS. À SOURCER, pas exécuter.
# Résout SELF (dossier engine/) et ROOT (racine du dépôt = parent d'engine/),
# charge le manifeste (SYNC_MAP) et expose claudeos_pairs() : l'itérateur unique
# des correspondances live<->repo utilisé par backup / sync / selftest / drift.
# =============================================================================

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../engine
ROOT="$(cd "$SELF/.." && pwd)"                          # .../ (racine dépôt = racine git)
CFG="$SELF/config"

SLUG="$(echo "$HOME" | sed 's#/#-#g')"
MEM="$HOME/.claude/projects/$SLUG/memory"               # mémoire auto (live)
MEM_REPO_SUBDIR="system-memory"                         # ... dans le dépôt

SYNC_MAP="$CFG/SYNC_MAP"
SYNC_IGNORE="$CFG/SYNC_IGNORE"
SYNC_MACHINES="$CFG/SYNC_MACHINES"

# Sous-chaîne d'origin attendue (garde-fou remote), lue depuis un fichier — plus
# jamais codée en dur dans les scripts. Un changement de dépôt = éditer ce fichier.
REMOTE_MATCH="$(cat "$CFG/REMOTE" 2>/dev/null || echo "")"

# Marqueurs d'état système (non-.md) qui voyagent avec la mémoire auto.
SYNC_MEM_MARKERS=(".last_distillation")

# claudeos_require_remote CONTEXTE : refuse d'opérer si origin ne correspond pas.
claudeos_require_remote() {
    local ctx="$1" url
    url="$(git -C "$ROOT" remote get-url origin 2>/dev/null || echo "")"
    if [[ -z "$REMOTE_MATCH" || "$url" != *"$REMOTE_MATCH"* ]]; then
        echo "[$ctx] ERREUR : remote origin inattendu ('$url'). Attendu : *$REMOTE_MATCH*. Abandon." >&2
        return 1
    fi
    return 0
}

# claudeos_lock CONTEXTE : verrou exclusif non-bloquant contre l'exécution
# concurrente (backup manuel + hook SessionEnd, ou double session sur un poste).
# fd 9 relâché à la mort du process → pas de verrou zombie. Sans flock ou si le
# verrou ne peut être créé, dégrade en no-op bruyant plutôt que de bloquer.
claudeos_lock() {
    local ctx="$1" lockfile="$HOME/.claude/.claudeos.lock"
    command -v flock >/dev/null 2>&1 || { echo "[$ctx] WARN : flock absent — verrou de concurrence désactivé." >&2; return 0; }
    # Test d'écriture SCOPÉ (le 2>/dev/null ne porte que sur ce groupe, jamais sur exec :
    # 'exec 9>f 2>/dev/null' détournerait TOUT le stderr du process de façon permanente).
    if ! { : >>"$lockfile"; } 2>/dev/null; then
        echo "[$ctx] WARN : verrou impossible ($lockfile) — on continue sans." >&2
        return 0
    fi
    exec 9>"$lockfile"
    if ! flock -n 9; then
        echo "[$ctx] ERREUR : une autre opération ClaudeOS est en cours (verrou détenu). Abandon." >&2
        return 1
    fi
    return 0
}

# --- Motifs de détection de secret — SOURCE UNIQUE (remontés ici le 2026-08-03).
# Deux mécanismes indépendants regardent les secrets par deux moyens différents : les
# alarmes de `backup.sh` inspectent ce qui est MIS EN FILE pour le dépôt, le contrôle de
# rangement de `selftest.sh` inspecte l'ARBRE VIVANT ENTIER, zones exclues de la sauvegarde
# comprises. Une seule liste de motifs pour les deux : deux copies à deux âges divergent, et
# c'est alors le plus silencieux des deux qui devient muet sans que rien ne le dise.
#
# Le motif visé par la remontée, constaté le 2026-08-03 : une valeur de secret vivait dans un
# dossier de compétence. Elle n'est jamais partie au dépôt — la liste blanche la refusait —
# donc aucune alarme de mise en file ne pouvait la voir. Un secret mal rangé dans une zone
# non sauvegardée est invisible pour un scan qui ne regarde que ce qui part.
#
# FORMES — préfixes imposés par les éditeurs (AWS, GitHub, GitLab, Google, Slack, clé PEM).
# Tous ont une casse EXACTE, donc à comparer SANS l'option d'insensibilité : comparer sans la
# casse ne rattrape aucun secret réel et fait sonner n'importe quel bloc base64 (sur quelques
# centaines de kilo-octets, 'akia' suivi de seize caractères alphanumériques sort par hasard —
# ce qui a bloqué la sauvegarde du 2026-07-27 sur des images intégrées).
CLAUDEOS_SECRET_RE_FORMES='(-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,}|glpat-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]{10,})'
# MOTS — un mot-clé suivi d'une valeur. Ici la casse varie selon qui écrit le fichier, donc
# l'insensibilité est utile et se garde.
CLAUDEOS_SECRET_RE_MOTS='(api[_-]?key|secret|password|passwd|token)[^[:alnum:]]{1,4}[A-Za-z0-9/+_.=-]{20,}'
# NOMS — le nom du fichier annonce un secret, même si aucune ligne ne matche les deux
# précédents (trou par lequel un fichier de clé nue a fui le 2026-07-03).
CLAUDEOS_SECRET_NAME_RE='(secret|passw(or)?d|credential|api[._-]?key|[._-]token)'

# claudeos_pairs : émet une ligne par correspondance — 'live_abs<TAB>repo_abs<TAB>regime'.
# Inclut la mémoire auto en dernier (régime 'memory'). Source de vérité unique de
# « quels dossiers existent et où ils vont » : plus aucune liste codée en dur ailleurs.
claudeos_pairs() {
    local live repo regime line
    while IFS= read -r line; do
        line="${line%%#*}"
        read -r live repo regime <<<"$line"
        [[ -z "${live:-}" ]] && continue
        printf '%s\t%s\t%s\n' "$HOME/$live" "$ROOT/$repo" "${regime:-mirror}"
    done < "$SYNC_MAP"
    printf '%s\t%s\t%s\n' "$MEM" "$ROOT/$MEM_REPO_SUBDIR" "memory"
}
