#!/usr/bin/env bash
# =============================================================================
# CLAUDEOS-SESSION — ouvre une session Claude Code dans tmux, au bon dossier, avec le rôle voulu.
# Seule porte d'entrée des sessions. `CLAUDEOS_SESSION_SCOPE=projet`, et lui seul, distingue une
# session de projet de la principale : `boot-check.sh` choisit sa branche dessus.
# tmux : la session survit à la fermeture du terminal et à une coupure SSH, existe partout où le
# dépôt est cloné, et son nom suit les dossiers.
# Racines de domaine : `claudeos_ws_roots()`, jamais une liste en dur. La profondeur est une
# convention d'arborescence : projet à 1 sous la racine, application à 2.
# =============================================================================
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

usage() {
    cat <<'EOF'
claudeos-session.sh — sessions Claude Code dans tmux

  claudeos-session.sh <projet>          ouvre la session PUIS un onglet iTerm2 attaché
                                  dessus ; sans iTerm2, rend la commande d'attache
  claudeos-session.sh --attach <projet> ouvre si besoin PUIS s'attache (occupe le
                                  terminal courant)
  claudeos-session.sh --main [--attach] ouvre la session PRINCIPALE : le global, le bilan
                                  de démarrage, la sauvegarde ; --attach s'y attache
  claudeos-session.sh --prepare         maj de Claude Code + pull des dépôts, SANS
                                  ouvrir de session (appelé par claudeos-boot.sh)
  claudeos-session.sh --list            les sessions ouvertes
  claudeos-session.sh --close <nom>     ferme une session
  claudeos-session.sh --help            ceci

<projet> est un chemin de dossier, ou un nom cherché sous les dossiers de travail
des domaines. La casse est ignorée. Un fragment suffit s'il ne désigne qu'un seul
dossier ; s'il en désigne plusieurs, ils sont listés et rien n'est ouvert —
départager est votre décision, pas la mienne.
EOF
}

# Nom de session tmux : ni point ni deux-points, que tmux emploie dans sa syntaxe de cible
# (`session:fenêtre.panneau`). `-*$` est POSIX : `\+` est lu littéralement par le sed de BSD.
tmux_name() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-' | sed 's/-*$//'; }

# Cherche à profondeur 1 (projet) puis 2 (application). `find -L` : une racine peut être un lien,
# et `find` ne suit pas un lien donné en argument sans lui — le balayage ne trouverait rien.
# `_IGNORE/` exclu : réceptacle du confidentiel, hors sauvegarde ; une session ouverte dedans
# écrirait son état sur la seule machine locale, sans un mot.
find_by_pattern() {
    local pattern=$1 root
    while IFS= read -r root; do
        [ -d "$root" ] || continue
        find -L "$root" -mindepth 1 -maxdepth 2 -type d -iname "$pattern" \
            -not -path '*/_IGNORE' -not -path '*/_IGNORE/*' 2>/dev/null
    done < <(claudeos_ws_roots)
}

# resolve_dir <argument> : émet UN dossier absolu, ou échoue en expliquant. Un chemin existant
# est pris tel quel (forme des appelants scriptés) ; sinon par nom, exact d'abord — un nom
# entier ne doit jamais être noyé par les partiels.
resolve_dir() {
    local needle=$1 matches count

    if [ -d "$needle" ]; then
        (cd "$needle" && pwd)
        return 0
    fi

    matches=$(find_by_pattern "$needle" | sort -u)
    [ -z "$matches" ] && matches=$(find_by_pattern "*${needle}*" | sort -u)

    if [ -z "$matches" ]; then
        echo "Aucun dossier ne correspond à « $needle » sous les domaines." >&2
        echo "Racines balayées :" >&2
        claudeos_ws_roots | sed 's/^/  /' >&2
        return 1
    fi

    count=$(printf '%s\n' "$matches" | wc -l | tr -d ' ')
    if [ "$count" -gt 1 ]; then
        echo "« $needle » désigne $count dossiers — précisez :" >&2
        printf '%s\n' "$matches" | sed "s#^$HOME/#  #" >&2
        return 1
    fi

    printf '%s\n' "$matches"
}

# Commande d'une fenêtre tmux. Sortie propre : la fenêtre se ferme, donc la session. Sortie en
# erreur : la pièce est retenue avec son code, sinon le plantage disparaît sans diagnostic.
# `--name` : nom d'affichage de Claude Code, distinct du nom de session tmux ; passé par `%q`
# (un nom de projet peut porter une espace).
session_cmd() {
    local display=${1:-} nameopt=""
    [ -n "$display" ] && printf -v nameopt -- '--name %q ' "$display"
    printf '%s' "claude ${nameopt}; c=\$?; [ \$c -eq 0 ] && exit 0; printf '\n— Claude Code a quitté avec le code %d. Session retenue pour que tu voies ça : relance « claude », ou Ctrl+D pour fermer.\n\n' \"\$c\"; exec bash"
}

# TEINTE DE LA BARRE tmux, PAR DOMAINE : la barre dit le MONDE, le nom d'onglet le projet. La
# principale garde l'ardoise, en dur : la seule session qui sauvegarde et porte le global ne doit
# pas se confondre avec un onglet de projet.
# LES TEINTES PAR DÉPÔT SE LISENT dans `reglages/COULEURS`, une ligne par dépôt :
#   <DÉPÔT> tmux=bg=colourNN,fg=colourNN rvb=R V B
# Un dépôt absent du fichier prend une teinte TIRÉE DE SON NOM, stable d'une session à l'autre,
# parmi cinq : aucune table à tenir, et un domaine neuf a sa couleur dès sa création.
# LA MÊME TEINTE EN RVB colore l'onglet du terminal, qui se voit sans entrer dans la session : la
# couleur se décide à UN endroit, la ligne de `COULEURS` ou le même index de repli.
#   238 ardoise #444444 · 24 bleu #005f87 · 30 sarcelle #008787 · 97 violet #875faf
#   64 olive #5f8700 · 130 brique #af5f00
_couleur_ligne() {   # $1 dépôt → sa ligne de reglages/COULEURS, ou rien
    local f="${CLAUDEOS_REG:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/reglages}/COULEURS"
    [ -f "$f" ] || return 0
    awk -v d="$1" '$1==d { print; exit }' "$f"
}
_teinte_repli() {    # $1 dépôt → un index de 0 à 4, stable pour un même nom
    local h
    h=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
    echo $(( h % 5 ))
}
domain_style() {
    local v
    case "$1" in ClaudeOS) printf '%s' 'bg=colour238,fg=colour253'; return ;; esac
    v="$(_couleur_ligne "$1" | sed -n 's/.*tmux=\([^ ]*\).*/\1/p')"
    if [ -n "$v" ]; then printf '%s' "$v"; return; fi
    case "$(_teinte_repli "$1")" in
        0) printf '%s' 'bg=colour24,fg=colour255'  ;;  # bleu
        1) printf '%s' 'bg=colour30,fg=colour255'  ;;  # sarcelle
        2) printf '%s' 'bg=colour97,fg=colour255'  ;;  # violet
        3) printf '%s' 'bg=colour64,fg=colour255'  ;;  # olive
        *) printf '%s' 'bg=colour130,fg=colour255' ;;  # brique
    esac
}
domain_rgb() {
    local v
    case "$1" in ClaudeOS) printf '%s' '68 68 68'; return ;; esac
    v="$(_couleur_ligne "$1" | sed -n 's/.*rvb=\([0-9]* [0-9]* [0-9]*\).*/\1/p')"
    if [ -n "$v" ]; then printf '%s' "$v"; return; fi
    case "$(_teinte_repli "$1")" in
        0) printf '%s' '0 95 135'   ;;
        1) printf '%s' '0 135 135'  ;;
        2) printf '%s' '135 95 175' ;;
        3) printf '%s' '95 135 0'   ;;
        *) printf '%s' '175 95 0'   ;;
    esac
}

# La séquence qui colore l'onglet iTerm2. Émise HORS tmux, par le terminal qui s'attache : une
# session créée détachée n'a pas de client à qui parler.
tab_color_seq() {
    set -- $(domain_rgb "$1")
    printf '\033]6;1;bg;red;brightness;%s\a\033]6;1;bg;green;brightness;%s\a\033]6;1;bg;blue;brightness;%s\a' "$1" "$2" "$3"
}

# OUVRIR L'ONGLET, ET PAS SEULEMENT LA SESSION : la forme nue `claudeos-session.sh <projet>` ouvre
# la session PUIS un onglet iTerm2 qui s'y attache, au lieu de rendre une commande à recopier.
# L'onglet relance CE script en `--attach` : un seul chemin de code pose la teinte, depuis le
# terminal qui s'attache. Détection par `pgrep -x iTerm2`, jamais par `$TERM_PROGRAM`, qui vaut
# « tmux » sous tmux. Le nom de PROCESSUS est « iTerm2 », le nom AppleScript « iTerm ».
# ÉCHEC = REPLI, JAMAIS ARRÊT : sans iTerm2 (autre terminal, SSH, poste sans interface), la session
# tmux est ouverte et l'appelant rend la commande d'attache.
open_iterm_tab() {
    local dir=$1 self cmd
    pgrep -x iTerm2 >/dev/null 2>&1 || return 1
    self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/claudeos-session.sh"
    cmd="bash '$self' --attach '$dir'"
    osascript >/dev/null 2>&1 <<APPLESCRIPT || return 1
tell application "iTerm"
    activate
    if (count of windows) = 0 then
        set w to (create window with default profile)
        tell current session of w to write text "$cmd"
    else
        tell current window
            set t to (create tab with default profile)
            tell current session of t to write text "$cmd"
        end tell
    end if
end tell
APPLESCRIPT
}

# Domaine d'un dossier, dérivé des racines déclarées et de rien d'autre.
domain_of() {
    local dir=$1 root
    while IFS= read -r root; do
        case "$dir/" in "$root"/*) basename "$root"; return 0 ;; esac
    done < <(claudeos_ws_roots)
    printf '%s' "inconnu"
}

# Nom lisible d'un niveau : `_APPS` tombe, les tirets bas deviennent des espaces, la casse reste
# (une casse de titre écraserait les sigles : « ABC » deviendrait « Abc »).
display_name() {
    local n=${1%%_APPS}
    printf '%s' "${n//_/ }"
}

# ensure_session <argument> : crée la session si absente, émet son nom sur stdout. Tout le
# bavardage part sur stderr, pour que les appelants capturent le nom sans le filtrer.
ensure_session() {
    local dir name depot
    dir=$(resolve_dir "$1") || return 1
    name=$(tmux_name "$(basename "$dir")")

    # L'absence d'ÉTAT se dit sans bloquer : ce script résout par nom de dossier, il ouvrirait
    # sinon en silence une session sans état ni reprise.
    if [ ! -f "$dir/ETAT.md" ]; then
        echo "⚠ ${dir/#$HOME/$CLAUDEOS_TILDE} n'a pas d'ETAT.md : ce n'est pas encore un niveau, il n'aura ni état ni reprise (compétence nouveau-projet)." >&2
    fi

    if tmux has-session -t "=$name" 2>/dev/null; then
        echo "La session « $name » tourne déjà." >&2
    else
        # LE DÉPÔT DU NIVEAU SE TIRE AVANT LA SESSION, jamais sous une session ouverte ; `sync_repo`
        # refuse seul un dépôt où une autre session travaille. Sans dépôt (`GIT=aucun`), rien.
        if depot=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null); then
            sync_repo "$depot" >&2
        fi
        # `-n` : nom de fenêtre, remonté dans l'en-tête d'onglet par `set-titles-string "#W"` ; la
        # même valeur que le nom d'affichage de Claude Code.
        tmux new-session -d -s "$name" -n "$(display_name "$(basename "$dir")")" \
            -c "$dir" -e CLAUDEOS_SESSION_SCOPE=projet \
            "$(session_cmd "$(display_name "$(basename "$dir")")")" \
            || { echo "tmux n'a pas pu ouvrir la session « $name »." >&2; return 1; }
        # Cible SANS `=` : `set-option -t` le refuse, là où `has-session` et `attach` l'exigent.
        tmux set -t "$name" status-style "$(domain_style "$(domain_of "$dir")")" 2>/dev/null
        echo "Session « $name » ouverte sur ${dir/#$HOME/$CLAUDEOS_TILDE} — domaine $(domain_of "$dir")." >&2
    fi
    printf '%s\n' "$name"
}

# La PRINCIPALE diffère d'un projet par l'absence de `CLAUDEOS_SESSION_SCOPE` (la poser ici la ferait
# passer pour un projet) ; le rôle de porteuse du global reste une consigne. Aucun prompt de
# bilan : le mod `mods/demarrage-auto` soumet `/demarrage` au premier tour de toute session neuve.
# Mise à jour et pull JUSTE AVANT de la créer, jamais sous un Claude qui tourne : une mise à jour
# en cours de session impose le redémarrage que ce geste supprime.
sync_repos() {
    local repo
    for repo in $(claudeos_repos); do
        [ -d "$repo/.git" ] || continue
        sync_repo "$repo"
    done
}

# sync_repo <dépôt> : fetch, verdict, intégration d'UN dépôt. La décision vit dans
# `claudeos_verdict_pull` (config.sh), partagée avec le bilan de démarrage ; l'intégration dans
# `claudeos_integre` (lib_regime.sh), qui ne rebase jamais une fusion et annule un conflit au lieu
# de laisser le dépôt en suspens. Un dépôt modifié que le verdict laisse tirer (`TIRER|autostash`)
# est mis de côté par `git stash` le temps de l'intégration, puis remis : le verdict a vérifié
# qu'aucun fichier modifié ici ne change en amont. Un verdict inconnu ne tire rien.
sync_repo() {
    local repo="$1" nom verdict mis_de_cote=""
    nom="${repo/#$HOME/$CLAUDEOS_TILDE}"
    [ -n "$(git -C "$repo" remote 2>/dev/null)" ] || { echo "[maj] $nom : aucun remote, rien à tirer."; return 0; }
    # Fetch repris une fois : au lancement, le réseau peut ne pas être monté.
    if ! git -C "$repo" fetch -q 2>/dev/null; then
        sleep 3
        git -C "$repo" fetch -q 2>/dev/null \
            || { echo "[maj] WARN : fetch impossible sur $nom (hors ligne ?), rien tiré." >&2; return 0; }
    fi
    verdict=$(claudeos_verdict_pull "$repo")
    case "$verdict" in
        AJOUR)        echo "[maj] $nom à jour."; return 0 ;;
        SANS_AMONT)   echo "[maj] $nom : aucune branche amont, rien à tirer."; return 0 ;;
        ATTENDRE*)    echo "[maj] ⛔ $nom : ${verdict#*|} — rien tiré, à traiter en session." >&2; return 0 ;;
        'TIRER|propre') ;;
        'TIRER|autostash')
            git -C "$repo" stash push -q -m "claudeos-session : mis de côté le temps de tirer" \
                || { echo "[maj] ⛔ $nom : modifications locales impossibles à mettre de côté — rien tiré, à traiter en session." >&2; return 0; }
            mis_de_cote=1 ;;
        *)            echo "[maj] ⛔ $nom : verdict de pull illisible (« $verdict ») — rien tiré." >&2; return 0 ;;
    esac
    claudeos_integre "$repo" "$nom" "[maj]" && echo "[maj] $nom à jour."
    if [ -n "$mis_de_cote" ] && ! git -C "$repo" stash pop -q; then
        echo "[maj] ⛔ $nom : la remise des modifications locales a échoué — elles restent dans « git -C $nom stash list ». À résoudre en session." >&2
    fi
}

# Mise à jour de Claude Code avant lancement, à un seul moment connu, jamais sous une session qui
# travaille ; avec `autoUpdates` à false dans `~/.claude.json`, c'est le seul moment où elle arrive.
# Sortie non avalée (un lanceur muet cache ses pannes) ; le code de retour se garde, sinon un échec
# se lirait « déjà à jour ».
update_claude() {
    local avant apres rc=0
    avant="$(claude --version 2>/dev/null | awk '{print $1}')"
    claude update || rc=$?
    apres="$(claude --version 2>/dev/null | awk '{print $1}')"
    if [ "$rc" -ne 0 ]; then
        echo "[maj] WARN : mise à jour de Claude Code ÉCHOUÉE (code $rc), version $apres conservée — détail ci-dessus." >&2
    elif [ "$avant" != "$apres" ]; then
        echo "[maj] Claude Code : $avant → $apres."
    else
        echo "[maj] Claude Code $apres, déjà à jour."
    fi
}

open_main() {
    if tmux has-session -t '=ClaudeOS' 2>/dev/null; then
        echo "La session principale tourne déjà."
    else
        update_claude
        sync_repos
        tmux new-session -d -s ClaudeOS -n ClaudeOS -c "$HOME" "$(session_cmd ClaudeOS)" \
            || { echo "tmux n'a pas pu ouvrir la session principale." >&2; return 1; }
        tmux set -t ClaudeOS status-style "$(domain_style ClaudeOS)" 2>/dev/null
        echo "Session principale ouverte."
    fi
}

# tmux n'est exigé que des gestes qui ouvrent, attachent, listent ou ferment : `--prepare`, que le
# lanceur `claude` de `claudeos-boot.sh` appelle sur tout poste, et l'aide passent sans lui.
case "${1:-}" in
    ""|--help|-h|--prepare) ;;
    *) command -v tmux >/dev/null 2>&1 || {
           case "$(uname -s)" in Darwin) _geste="brew install tmux" ;; *) _geste="sudo apt install -y tmux" ;; esac
           echo "tmux n'est pas installé : $_geste" >&2; exit 1; } ;;
esac
command -v claude >/dev/null 2>&1 || { echo "le binaire 'claude' est introuvable dans le PATH." >&2; exit 1; }

case "${1:-}" in
    ""|--help|-h)
        usage
        ;;
    --main)
        open_main || exit 1
        if [ "${2:-}" = --attach ]; then
            tab_color_seq ClaudeOS
            exec tmux attach -t '=ClaudeOS'
        fi
        echo "Pour t'y attacher :  tmux attach -t ClaudeOS"
        ;;
    --prepare)
        # Même paire de gestes que `--main`, sans session : un seul endroit décide de ce que
        # « être à jour » veut dire.
        update_claude
        sync_repos
        ;;
    --attach)
        [ -n "${2:-}" ] || { echo "--attach attend un projet." >&2; exit 1; }
        dir=$(resolve_dir "$2") || exit 1
        name=$(ensure_session "$dir") || exit 1
        # LA TEINTE SE POSE ICI ET NULLE PART AILLEURS : seul geste du script qui tourne dans le
        # terminal hôte, hors tmux. Avant `exec`, sinon elle n'est jamais émise.
        tab_color_seq "$(domain_of "$dir")"
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
        # Un argument inconnu n'est jamais ignoré : il passerait pour un nom de projet.
        echo "Argument inconnu : $1" >&2
        usage >&2
        exit 1
        ;;
    *)
        dir=$(resolve_dir "$1") || exit 1
        name=$(ensure_session "$dir") || exit 1
        if open_iterm_tab "$dir"; then
            # L'onglet lancé ne prouve pas l'attache : la constater sur tmux, six essais à 1 s.
            for _ in 1 2 3 4 5 6; do
                tmux list-clients -t "=$name" 2>/dev/null | grep -q . \
                    && { echo "Onglet iTerm2 ouvert, client attaché constaté sur « $name »."; exit 0; }
                sleep 1
            done
            echo "Onglet iTerm2 lancé, AUCUN client attaché à « $name » après 6 s. Pour t'y attacher :  tmux attach -t $name" >&2
            exit 3
        fi
        echo "Pas d'iTerm2 joignable. Pour t'y attacher :  tmux attach -t $name"
        ;;
esac
