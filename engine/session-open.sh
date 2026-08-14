#!/usr/bin/env bash
# =============================================================================
# SESSION-OPEN — ouvre une session Claude Code dans tmux, au bon dossier, avec le
# rôle voulu. C'est `OS_SESSION_SCOPE=projet`, et elle seule, qui distingue une
# session de projet de la principale : le hook `SessionEnd` s'en sert pour ne PAS
# sauvegarder depuis un onglet de projet, `boot-check.sh` pour
# choisir sa branche, et la garde de barre d'état pour n'afficher que le modèle
# et le contexte.
#
# POURQUOI TMUX, ET CE QUE ÇA RÈGLE (2026-08-13). Ouvrir la session au bon dossier
# avec le bon rôle était un geste manuel, refait à chaque fois. Ce script le supprime — l'assistant ouvre la
# session lui-même. Trois gains par-dessus : la session survit à la fermeture du
# terminal et à une coupure SSH, ce qui n'est pas un luxe sur un poste où Claude
# Code tourne au bout d'un SSH ; elle existe partout où le dépôt est cloné, sans
# dépendre d'un éditeur installé ; et le nommage suit les dossiers.
#
# UNE SEULE VÉRITÉ POUR LE LANCEMENT : tout outillage qui veut ouvrir une session
# appelle ce script (`--attach`) au lieu de refaire la logique.
#
# Les racines de workstation dérivent de `claudeos_ws_roots()` : aucune liste en
# dur. La PROFONDEUR, elle, est une convention d'arborescence et
# non une donnée du manifeste — projet à 1 sous la racine, application à 2 —,
# donc elle est figée ici comme chez les autres appelants.
# =============================================================================
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

usage() {
    cat <<'EOF'
session-open.sh — sessions Claude Code dans tmux

  session-open.sh <projet>          ouvre la session, ou rend la commande d'attache
                                  si elle tourne déjà
  session-open.sh --attach <projet> ouvre si besoin PUIS s'attache (occupe le
                                  terminal courant)
  session-open.sh --main            ouvre la session PRINCIPALE : le global, le
                                  bilan de démarrage, la sauvegarde
  session-open.sh --list            les sessions ouvertes
  session-open.sh --close <nom>     ferme une session
  session-open.sh --help            ceci

<projet> est un chemin de dossier, ou un nom cherché sous les workstations du
manifeste. La casse est ignorée. Un fragment suffit s'il ne désigne qu'un seul
dossier ; s'il en désigne plusieurs, ils sont listés et rien n'est ouvert —
départager est votre décision, pas la mienne.
EOF
}

# Un nom de session tmux ne supporte ni point ni deux-points : tmux les emploie
# dans sa propre syntaxe de cible (`session:fenêtre.panneau`).
tmux_name() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-' | sed 's/-\+$//'; }

# Cherche à profondeur 1 (projet) puis 2 (application).
find_by_pattern() {
    local pattern=$1 root
    while IFS= read -r root; do
        [ -d "$root" ] || continue
        find "$root" -mindepth 1 -maxdepth 2 -type d -iname "$pattern" 2>/dev/null
    done < <(claudeos_ws_roots)
}

# resolve_dir <argument> : émet UN dossier absolu, ou échoue en expliquant.
# Un chemin de dossier existant est pris tel quel — c'est la forme qu'un
# appelant outillé passe, sans ambiguïté possible. Sinon on cherche par nom : exact d'abord,
# car un nom entier qui matche ne doit jamais être noyé par les partiels.
resolve_dir() {
    local needle=$1 matches count

    if [ -d "$needle" ]; then
        (cd "$needle" && pwd)
        return 0
    fi

    matches=$(find_by_pattern "$needle" | sort -u)
    [ -z "$matches" ] && matches=$(find_by_pattern "*${needle}*" | sort -u)

    if [ -z "$matches" ]; then
        echo "Aucun dossier ne correspond à « $needle » sous les workstations du manifeste." >&2
        echo "Racines balayées :" >&2
        claudeos_ws_roots | sed 's/^/  /' >&2
        return 1
    fi

    count=$(printf '%s\n' "$matches" | wc -l)
    if [ "$count" -gt 1 ]; then
        echo "« $needle » désigne $count dossiers — précisez :" >&2
        printf '%s\n' "$matches" | sed "s#^$HOME/#  #" >&2
        return 1
    fi

    printf '%s\n' "$matches"
}

# LE SORT DE LA SESSION SUIT LE CODE DE SORTIE, et la distinction est le cœur du
# réglage. tmux ferme la fenêtre quand son processus se termine, et une session
# sans fenêtre disparaît. Sortie propre : c'est exactement ce qu'on veut — fermer
# Claude Code ferme la pièce, sans second geste. Sortie en erreur : on retient la
# pièce et on affiche le code, sinon le plantage disparaît avec la fenêtre et il
# ne reste rien à diagnostiquer. Un relais inconditionnel avait d'abord été posé
# le 2026-08-13, à tort : il forçait un Ctrl+D après chaque fermeture voulue.
session_cmd() {
    local prompt=${1:-}
    printf '%s' "claude $prompt; c=\$?; [ \$c -eq 0 ] && exit 0; printf '\n— Claude Code a quitté avec le code %d. Session retenue pour que tu voies ça : relance « claude », ou Ctrl+D pour fermer.\n\n' \"\$c\"; exec bash"
}

# ensure_session <argument> : crée la session si absente, émet son nom sur stdout.
# Tout le bavardage part sur stderr, pour que les appelants puissent capturer le
# nom sans le filtrer.
ensure_session() {
    local dir name
    dir=$(resolve_dir "$1") || return 1
    name=$(tmux_name "$(basename "$dir")")

    # L'ABSENCE DE MÉMOIRE SE DIT, SANS BLOQUER. Un niveau sans `MEMORY.md` n'a ni mémoire ni
    # reprise, et rien n'échoue — l'oubli de ce fichier est silencieux par nature. Ce
    # script résolvant par nom de dossier, il ouvrirait une session sans mémoire sans
    # rien dire. Un refus serait excessif : on
    # ouvre, et on rend l'oubli BRUYANT, ce qui vaut mieux que les deux.
    if [ ! -f "$dir/MEMORY.md" ]; then
        echo "⚠ ${dir/#$HOME/\~} n'a pas de MEMORY.md : ce niveau n'aura pas de reprise." >&2
    fi

    if tmux has-session -t "=$name" 2>/dev/null; then
        echo "La session « $name » tourne déjà." >&2
    else
        tmux new-session -d -s "$name" -c "$dir" -e OS_SESSION_SCOPE=projet "$(session_cmd Reprise)" \
            || { echo "tmux n'a pas pu ouvrir la session « $name »." >&2; return 1; }
        echo "Session « $name » ouverte sur ${dir/#$HOME/\~}." >&2
    fi
    printf '%s\n' "$name"
}

# La PRINCIPALE diffère d'un projet par deux choses, et deux seulement.
# 1. Pas de `OS_SESSION_SCOPE` : c'est son absence qui l'autorise à sauvegarder et
#    à porter le global. Ne jamais la poser ici.
# 2. Le prompt de bilan est passé EXPLICITEMENT. La fonction `claude()` de
#    `boot-wrapper.sh` qui l'injecte d'ordinaire ne s'applique pas : tmux exécute sa
#    commande par un shell non interactif, qui ne source pas `~/.bashrc`. Sans cet
#    argument, la principale s'ouvrirait muette. Corollaire voulu : une session de
#    projet ne reçoit donc PAS le bilan — le global n'étant pas son affaire.
# Le la conception écarte « aucune tâche pour la principale » sur deux motifs, dont aucun
# ne vise ce cas : la variable n'est pas posée, et ceci n'est pas une entrée d'un
# générateur dérivé du disque mais une sous-commande explicite.
open_main() {
    if tmux has-session -t '=main' 2>/dev/null; then
        echo "La session principale tourne déjà."
    else
        tmux new-session -d -s main -c "$HOME" "$(session_cmd "'tu es à jour ?'")" \
            || { echo "tmux n'a pas pu ouvrir la session principale." >&2; return 1; }
        echo "Session principale ouverte."
    fi
    echo "Pour t'y attacher :  tmux attach -t main"
}

command -v tmux >/dev/null 2>&1 || { echo "tmux n'est pas installé : sudo apt install -y tmux" >&2; exit 1; }
command -v claude >/dev/null 2>&1 || { echo "le binaire 'claude' est introuvable dans le PATH." >&2; exit 1; }

case "${1:-}" in
    ""|--help|-h)
        usage
        ;;
    --main)
        open_main
        ;;
    --attach)
        [ -n "${2:-}" ] || { echo "--attach attend un projet." >&2; exit 1; }
        name=$(ensure_session "$2") || exit 1
        exec tmux attach -t "=$name"
        ;;
    --list|-l)
        tmux ls 2>/dev/null || echo "Aucune session ouverte."
        ;;
    --close)
        [ -n "${2:-}" ] || { echo "--close attend un nom de session." >&2; exit 1; }
        tmux kill-session -t "=$2" 2>/dev/null \
            && echo "Session « $2 » fermée." \
            || { echo "Aucune session « $2 »." >&2; exit 1; }
        ;;
    -*)
        # Un argument inconnu ne doit JAMAIS être ignoré en silence : une option mal
        # tapée passerait pour un nom de projet et ouvrirait autre chose que voulu.
        echo "Argument inconnu : $1" >&2
        usage >&2
        exit 1
        ;;
    *)
        name=$(ensure_session "$1") || exit 1
        echo "Pour t'y attacher :  tmux attach -t $name"
        ;;
esac
