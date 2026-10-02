#!/usr/bin/env bash
# =============================================================================
# CLAUDEOS-SESSION — ouvre une session Claude Code dans tmux, au bon dossier, avec le
# rôle voulu. C'est `CLAUDEOS_SESSION_SCOPE=projet`, et elle seule, qui distingue une
# session de projet de la principale : `boot-check.sh` s'en sert pour choisir sa
# branche, et la garde de barre d'état pour n'afficher que le modèle et le contexte.
# Le hook `SessionEnd` en était le troisième lecteur — il est retiré le 2026-08-22
# (doublon de la clôture manuelle) : plus aucune sauvegarde automatique à brider.
#
# POURQUOI TMUX, ET CE QUE ÇA RÈGLE (2026-08-13). L'assistant ouvre la session
# lui-même, supprimant le geste résiduel qu'imposait l'éditeur d'alors. Trois gains
# par-dessus : la session survit à la fermeture du terminal et à une coupure SSH, ce
# qui n'est pas un luxe sur un poste où Claude Code tourne au bout d'un SSH ; elle
# existe partout où le dépôt est cloné, sans dépendre d'un éditeur installé ; et le
# nommage suit les dossiers.
#
# SEULE PORTE D'ENTRÉE DEPUIS LE 2026-08-17, Zed ayant été abandonné avec ses tâches
# et leur générateur `zed-tasks.sh` (DESIGN « Plusieurs sessions à la fois »).
#
# Les racines de domaine dérivent de `claudeos_ws_roots()` : aucune liste en
# dur (invariant §4). La PROFONDEUR, elle, est une convention d'arborescence et
# non une donnée du manifeste — projet à 1 sous la racine, application à 2 —,
# donc elle est figée ici comme chez les autres appelants.
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
  claudeos-session.sh --main            ouvre la session PRINCIPALE : le global, le
                                  bilan de démarrage, la sauvegarde
  claudeos-session.sh --prepare         maj de Claude Code + pull des deux depots,
                                  SANS ouvrir de session (appele par claudeos-boot.sh)
  claudeos-session.sh --list            les sessions ouvertes
  claudeos-session.sh --close <nom>     ferme une session
  claudeos-session.sh --help            ceci

<projet> est un chemin de dossier, ou un nom cherché sous les domaines du
manifeste. La casse est ignorée. Un fragment suffit s'il ne désigne qu'un seul
dossier ; s'il en désigne plusieurs, ils sont listés et rien n'est ouvert —
départager est votre décision, pas la mienne.
EOF
}

# Un nom de session tmux ne supporte ni point ni deux-points : tmux les emploie
# dans sa propre syntaxe de cible (`session:fenêtre.panneau`).
# `-*` ET NON `-\+` — corrigé le 2026-09-22, constat D3 de l'audit de portabilité. `\+` est une
# extension GNU : le sed de BSD le lit comme un `+` littéral, donc le motif ne mord pas et un nom
# de session tmux garde ses tirets finaux. Mesuré le même jour sur `abc---` : sed GNU rend `abc`,
# `/usr/bin/sed` rend `abc---`. `-*$` est POSIX et rend `abc` des deux côtés.
tmux_name() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-' | sed 's/-*$//'; }

# Cherche à profondeur 1 (projet) puis 2 (application).
find_by_pattern() {
    local pattern=$1 root
    while IFS= read -r root; do
        [ -d "$root" ] || continue
# PORTABILITE, 2026-09-12 — `find -L`, ET CE N'EST PAS COSMETIQUE. Depuis la migration sur le Mac,
# les racines de depot sont des LIENS SYMBOLIQUES (`~/<DÉPÔT>` -> un dossier réel ailleurs).
# `find` NE SUIT PAS un lien donne en argument sans `-L` : le balayage rendait ZERO fichier sur 567,
# et le controle concluait au vert. Mesure du jour : 0 contre 567. Un garde qui ne regarde rien
# repond toujours « rien a signaler ». `-L` est POSIX et sans effet quand la racine est un vrai
# dossier, donc neutre sur le PC sous WSL.
# `_IGNORE/` EXCLU — posé le 2026-09-22, tranché par l'utilisateur : ouvrir une session là
# n'a aucun intérêt. `_IGNORE/` est le réceptacle du confidentiel (règlement, § File
# Management) et il est HORS SAUVEGARDE par conception : une session ouverte dedans écrirait
# son état, son journal et ses livrables sur la seule machine locale, sans qu'un mot le dise.
# Relevé le jour même : le fragment « ARC » rendait DEUX candidats, dont
# `<DÉPÔT_A>/_IGNORE/<APP>`. La garde d'ambiguïté a refusé d'ouvrir — mais
# pour AMBIGUÏTÉ, pas pour ce motif : un fragment univoque serait passé.
# LES AUTRES APPELANTS DE `claudeos_ws_roots` ONT ÉTÉ VÉRIFIÉS le même jour, parce qu'une
# exception vaut pour tous les gardes et pas pour le premier rencontré : `controle-secrets.sh`
# et `build-portfolio.sh` (à ses DEUX boucles) excluent déjà ; `install-poste.sh` y descend
# EXPRÈS, c'est lui qui pose les raccourcis `_ign`. Reste `boot-check.sh`, qui cherche des
# fichiers de reprise sans exclure — risque résiduel écrit, non corrigé : ces fichiers sont morts
# depuis le 2026-09-17, donc rien ne les lit plus.
        find -L "$root" -mindepth 1 -maxdepth 2 -type d -iname "$pattern" \
            -not -path '*/_IGNORE' -not -path '*/_IGNORE/*' 2>/dev/null
    done < <(claudeos_ws_roots)
}

# resolve_dir <argument> : émet UN dossier absolu, ou échoue en expliquant.
# Un chemin de dossier existant est pris tel quel — sans ambiguïté possible, et
# c'est la forme que passe tout appelant scripté. Sinon on cherche par nom : exact d'abord,
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
        echo "Aucun dossier ne correspond à « $needle » sous les domaines du manifeste." >&2
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

# LE SORT DE LA SESSION SUIT LE CODE DE SORTIE, et la distinction est le cœur du
# réglage. tmux ferme la fenêtre quand son processus se termine, et une session
# sans fenêtre disparaît. Sortie propre : c'est exactement ce qu'on veut — fermer
# Claude Code ferme la pièce, sans second geste. Sortie en erreur : on retient la
# pièce et on affiche le code, sinon le plantage disparaît avec la fenêtre et il
# ne reste rien à diagnostiquer. Un relais inconditionnel avait d'abord été posé
# le 2026-08-13, à tort : il forçait un Ctrl+D après chaque fermeture voulue.
# LE NOM D'AFFICHAGE est passé à Claude Code par `--name` (ajouté le 2026-08-18, sur
# sa demande). Option vérifiée par `claude --help` le jour même : « Set a display name
# for this session (shown in the prompt box, /resume picker, and terminal title) ».
# Elle est DISTINCTE du nom de session tmux, qui reste en minuscules et continue de
# servir l'adressage `tmux attach` — les deux ne se remplacent pas.
# Le nom passe par `%q`, jamais nu : un nom de projet peut porter une espace.
session_cmd() {
    local prompt=${1:-} display=${2:-} nameopt=""
    [ -n "$display" ] && printf -v nameopt -- '--name %q ' "$display"
    printf '%s' "claude ${nameopt}$prompt; c=\$?; [ \$c -eq 0 ] && exit 0; printf '\n— Claude Code a quitté avec le code %d. Session retenue pour que tu voies ça : relance « claude », ou Ctrl+D pour fermer.\n\n' \"\$c\"; exec bash"
}

# CODE COULEUR DE LA BARRE tmux, par domaine (posé le 2026-08-18, sur sa demande).
# À quoi ça sert : la barre du bas est visible en permanence, même quand Claude Code
# ne tourne pas. La teinte dit le MONDE, le nom d'onglet dit le projet. Avant ceci la
# barre tournait sur les défauts de tmux — `bg=green,fg=black`, vert criard et muet.
#
# LA PRINCIPALE EST LA SEULE EN GRIS, et ce n'est pas un choix esthétique : c'est la
# seule session qui sauvegarde et qui porte le global (DESIGN « Plusieurs sessions à la fois »). Elle ne doit pas
# pouvoir être confondue avec un onglet de projet.
#
# LES TEINTES PAR DÉPÔT SE LISENT dans `reglages/COULEURS`, à toi, une ligne par dépôt :
#   <DÉPÔT> tmux=bg=colourNN,fg=colourNN rvb=R V B
# Un dépôt absent du fichier prend une teinte TIRÉE DE SON NOM, stable d'une session à l'autre,
# parmi cinq — aucune table n'est à tenir pour que ça marche, et un domaine neuf a sa couleur dès
# sa création. La principale garde l'ardoise, en dur : c'est la seule qui ne doit JAMAIS se
# confondre avec un onglet de projet. Les racines, elles, viennent de `claudeos_ws_roots()`.
# LA MÊME TEINTE EN RVB colore l'onglet du terminal : la barre tmux est en bas et ne se lit que
# dans la session ouverte, l'onglet se voit sans entrer. Les deux disent le même monde, donc la
# couleur se décide à UN endroit : la ligne de `COULEURS`, ou le même index de repli.
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

# La séquence qui colore l'onglet iTerm2. Émise HORS tmux — depuis le terminal qui s'attache —
# parce qu'une session créée détachée n'a pas de client à qui parler : émise à la création,
# elle n'atteindrait personne.
tab_color_seq() {
    set -- $(domain_rgb "$1")
    printf '\033]6;1;bg;red;brightness;%s\a\033]6;1;bg;green;brightness;%s\a\033]6;1;bg;blue;brightness;%s\a' "$1" "$2" "$3"
}

# OUVRIR L'ONGLET, ET PAS SEULEMENT LA SESSION (2026-09-18, sur sa demande explicite :
# « quand je te dis d'ouvrir une session, tu lances le tmux ET tu lances le tab »).
# Jusqu'ici la forme nue `claudeos-session.sh <projet>` créait la session DÉTACHÉE et rendait une
# commande d'attache à RECOPIER — le geste s'arrêtait à mi-chemin, et l'assistant relayait la
# commande au lieu d'ouvrir. Conséquence mesurée le 2026-09-18 : `tab_color_seq`, écrite la
# veille sur sa demande, n'était appelée NULLE PART — la teinte d'onglet n'a jamais été émise
# une seule fois depuis sa pose. Une fonction que rien n'appelle est un réglage qui ment.
#
# POURQUOI L'ONGLET RELANCE CE MÊME SCRIPT en `--attach`, au lieu d'un `tmux attach` direct :
# la teinte doit être émise par le terminal QUI S'ATTACHE, donc hors tmux (cf. `tab_color_seq`).
# Passer par `--attach` laisse UN SEUL chemin de code poser la couleur ; un `tmux attach` écrit
# ici en ferait un second, et les deux portes divergeraient au premier changement de teinte.
#
# DÉTECTION PAR `pgrep -x iTerm2`, JAMAIS PAR `$TERM_PROGRAM` : sous tmux cette variable vaut
# « tmux » et non le terminal hôte — mesuré le 2026-09-18, elle aurait fait échouer la détection
# dans le seul cas qui compte, un appel depuis une session déjà ouverte.
# ET LES DEUX NOMS D'ITERM2 DIFFÈRENT, c'est le piège : son nom de PROCESSUS est « iTerm2 »,
# son nom AppleScript est « iTerm ». Les deux sont employés ci-dessous, chacun à sa place.
#
# ÉCHEC = REPLI, JAMAIS ARRÊT. Pas d'iTerm2 (autre terminal, SSH, poste sans interface) : la
# session tmux est ouverte de toute façon, et l'appelant rend la commande d'attache comme avant.
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

# NOM LISIBLE d'un niveau, dérivé du nom de dossier et de rien d'autre — aucune liste
# en dur, aucune table à tenir à jour (invariant §4). Deux gestes seulement : le
# suffixe de convention `_APPS` tombe, les tirets bas deviennent des espaces. La casse
# n'est PAS retouchée : une mise en casse de titre écraserait les sigles du parc
# (un sigle « ABC » deviendrait « Abc »).
display_name() {
    local n=${1%%_APPS}
    printf '%s' "${n//_/ }"
}

# ensure_session <argument> : crée la session si absente, émet son nom sur stdout.
# Tout le bavardage part sur stderr, pour que les appelants puissent capturer le
# nom sans le filtrer.
ensure_session() {
    local dir name
    dir=$(resolve_dir "$1") || return 1
    name=$(tmux_name "$(basename "$dir")")

    # L'ABSENCE DE MÉMOIRE SE DIT, SANS BLOQUER. Un niveau sans `MEMORY.md` n'a ni
    # mémoire ni reprise, et rien n'échoue — l'oubli de ce fichier est silencieux par
    # nature (DESIGN « La reprise »). Ce script résolvant par nom de dossier, il ouvrirait
    # une session sans mémoire sans rien dire. Un refus serait excessif : on ouvre, et
    # on rend l'oubli BRUYANT, ce qui vaut mieux que les deux.
    # BI-RÉGIME depuis le 2026-09-08 (geste 2.4) : `ETAT.md` OU `MEMORY.md` suffit. Un niveau
    # passé aux événements n'a plus de `MEMORY.md` VIVANT — il est gelé —, donc n'avertir que
    # sur `MEMORY.md` ferait crier ce script sur chaque niveau correctement basculé. Un
    # avertissement qui se déclenche sur l'état SAIN apprend à l'ignorer.
    # Depuis le 2026-09-22 un `MEMORY.md` est toujours gelé : seul `ETAT.md` porte l'état vivant.
    if [ ! -f "$dir/ETAT.md" ]; then
        echo "⚠ ${dir/#$HOME/$CLAUDEOS_TILDE} n'a pas d'ETAT.md : ce n'est pas encore un niveau, il n'aura ni état ni reprise (compétence nouveau-projet)." >&2
    fi

    if tmux has-session -t "=$name" 2>/dev/null; then
        echo "La session « $name » tourne déjà." >&2
    else
        # `-n` pose le nom de FENÊTRE, que `set-titles-string "#W"` remonte dans l'en-tête
        # d'onglet du terminal. Même valeur que le nom d'affichage Claude Code : un seul nom
        # lisible par niveau, trois endroits où il s'affiche.
        tmux new-session -d -s "$name" -n "$(display_name "$(basename "$dir")")" \
            -c "$dir" -e CLAUDEOS_SESSION_SCOPE=projet \
            "$(session_cmd Reprise "$(display_name "$(basename "$dir")")")" \
            || { echo "tmux n'a pas pu ouvrir la session « $name »." >&2; return 1; }
        # Cible SANS le préfixe `=` : `set-option -t` le refuse (« no such session: =… »),
        # là où `has-session` et `attach` l'exigent pour la correspondance exacte.
        # Constaté à l'exercice le 2026-08-18, la première écriture employait `=`.
        tmux set -t "$name" status-style "$(domain_style "$(domain_of "$dir")")" 2>/dev/null
        echo "Session « $name » ouverte sur ${dir/#$HOME/$CLAUDEOS_TILDE} — domaine $(domain_of "$dir")." >&2
    fi
    printf '%s\n' "$name"
}

# La PRINCIPALE diffère d'un projet par deux choses, et deux seulement.
# 1. Pas de `CLAUDEOS_SESSION_SCOPE` : c'est son absence qui la désigne comme porteuse du
#    global. Ne jamais la poser ici. Depuis le retrait du hook `SessionEnd` le
#    2026-08-22, cette absence n'AUTORISE plus rien mécaniquement — la clôture est
#    manuelle et n'importe quel onglet peut la lancer. Le rôle reste une consigne.
# 2. Le prompt de bilan est passé EXPLICITEMENT. La fonction `claude()` de
#    `claudeos-boot.sh` qui l'injecte d'ordinaire ne s'applique pas : tmux exécute sa
#    commande par un shell non interactif, qui ne source pas `~/.bashrc`. Sans cet
#    argument, la principale s'ouvrirait muette. Corollaire voulu : une session de
#    projet ne reçoit donc PAS le bilan — le global n'étant pas son affaire.
# Le §9bis écarte « aucune tâche pour la principale » sur deux motifs, dont aucun
# ne vise ce cas : la variable n'est pas posée, et ceci n'est pas une entrée d'un
# générateur dérivé du disque mais une sous-commande explicite.
# MISE À JOUR AVANT LANCEMENT (2026-08-26). Une mise à jour tirée EN COURS de session
# impose de redémarrer Claude Code pour recharger règles et compétences — le geste que
# cette fonction supprime. Elle ne tourne donc QUE juste avant la création de la session
# principale, jamais sur une session déjà ouverte : tirer sous un Claude qui tourne
# reproduirait exactement le défaut. Un dépôt SALE n'est jamais tiré — un rebase sur du
# travail non validé se règle en session, pas dans un lanceur.
sync_repos() {
    local repo nom
    # Liste des dépôts : `claudeos_repos` depuis le 2026-09-08 (geste 1.10), plus de liste en dur.
    for repo in $(claudeos_repos); do
        [ -d "$repo/.git" ] || continue
        nom="${repo/#$HOME/$CLAUDEOS_TILDE}"
        [ -n "$(git -C "$repo" remote 2>/dev/null)" ] || { echo "[maj] $nom : aucun remote, rien à tirer."; continue; }
        if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then
            echo "[maj] $nom : modifications non validées, PAS de pull. À traiter en session." >&2
            continue
        fi
        if git -C "$repo" pull --rebase -q 2>/dev/null; then
            echo "[maj] $nom à jour."
        else
            echo "[maj] WARN : pull --rebase impossible sur $nom (hors-ligne ?)." >&2
        fi
    done
}

# MISE À JOUR DE CLAUDE CODE AVANT LANCEMENT (2026-08-26). C'est l'autre moitié du
# même défaut que sync_repos : une version neuve annoncée EN COURS de session impose
# le redémarrage qu'on cherche à supprimer. L'installation est « native » et
# `autoUpdates` est à false dans ~/.claude.json — c'est VOULU, et c'est ce qui rend ce
# geste propre : la mise à jour arrive à un seul moment connu, juste avant le
# lancement, jamais sous les pieds d'une session qui travaille.
# Sa sortie n'est PAS avalée : un lanceur muet cache ses pannes.
update_claude() {
    local avant apres
    avant="$(claude --version 2>/dev/null | awk '{print $1}')"
    claude update || echo "[maj] WARN : mise à jour de Claude Code impossible (hors-ligne ?)." >&2
    apres="$(claude --version 2>/dev/null | awk '{print $1}')"
    if [ "$avant" != "$apres" ]; then
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
        tmux new-session -d -s ClaudeOS -n ClaudeOS -c "$HOME" "$(session_cmd "'tu es à jour ?'" ClaudeOS)" \
            || { echo "tmux n'a pas pu ouvrir la session principale." >&2; return 1; }
        tmux set -t ClaudeOS status-style "$(domain_style ClaudeOS)" 2>/dev/null
        echo "Session principale ouverte."
    fi
    echo "Pour t'y attacher :  tmux attach -t ClaudeOS"
}

command -v tmux >/dev/null 2>&1 || {
    case "$(uname -s)" in Darwin) _geste="brew install tmux" ;; *) _geste="sudo apt install -y tmux" ;; esac
    echo "tmux n'est pas installé : $_geste" >&2; exit 1; }
command -v claude >/dev/null 2>&1 || { echo "le binaire 'claude' est introuvable dans le PATH." >&2; exit 1; }

case "${1:-}" in
    ""|--help|-h)
        usage
        ;;
    --main)
        open_main
        ;;
    --prepare)
        # PREPARATION SANS SESSION (2026-09-02). Meme paire de gestes que `--main`,
        # sans tmux : c'est ce dont `claudeos-boot.sh` a besoin quand `claude` est tape nu
        # dans un terminal. Extraite ici plutot que recopiee la-bas — un seul endroit
        # decide de ce que « etre a jour » veut dire, sinon les deux portes divergent.
        # Sortie non avalee, comme dans `--main` : un lanceur muet cache ses pannes.
        update_claude
        sync_repos
        ;;
    --attach)
        [ -n "${2:-}" ] || { echo "--attach attend un projet." >&2; exit 1; }
        dir=$(resolve_dir "$2") || exit 1
        name=$(ensure_session "$dir") || exit 1
        # LA TEINTE SE POSE ICI ET NULLE PART AILLEURS — seul endroit du script qui tourne
        # dans le terminal hôte, hors tmux. Avant `exec`, sinon elle n'est jamais émise.
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
        # Un argument inconnu ne doit JAMAIS être ignoré en silence : une option mal
        # tapée passerait pour un nom de projet et ouvrirait autre chose que voulu.
        echo "Argument inconnu : $1" >&2
        usage >&2
        exit 1
        ;;
    *)
        dir=$(resolve_dir "$1") || exit 1
        name=$(ensure_session "$dir") || exit 1
        if open_iterm_tab "$dir"; then
            echo "Onglet iTerm2 ouvert et attaché sur « $name »."
        else
            echo "Pas d'iTerm2 joignable. Pour t'y attacher :  tmux attach -t $name"
        fi
        ;;
esac
