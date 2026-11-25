# === ClaudeOS · wrapper de démarrage ===
# Sourcé par `~/.zshrc` (macOS) ou `~/.bashrc` (WSL) ; vit dans le dépôt de config, donc voyage
# entre postes — seul le `source` reste manuel par poste. Ne bloque JAMAIS le lancement (|| true).
# `claude` nu prépare (mise à jour et pull) puis lance Claude Code SANS argument : le bilan part du
# mod `mods/demarrage-auto`, que `settings.json` charge par `CLAUDE_CODE_PLUGIN_DIRS` et qui soumet
# `/demarrage` au premier tour d'une session interactive neuve. Un crochet SessionStart ne le peut
# pas : il n'ajoute que du contexte, et son `initialUserMessage` n'agit qu'en `-p` (doc des hooks).

# Dossier du moteur, SANS `cd` : sous zsh, un `cd`, même dans `$(…)`, déclenche les crochets
# `chpwd` du shell de l'utilisateur. zsh met dans `$0` le chemin du fichier sourcé (`:a` : absolu,
# liens gardés) ; bash, lui, n'a pas de `chpwd`, et son `$0` vaudrait `-bash`, d'où `BASH_SOURCE`.
# Jamais de chemin en dur.
if [ -n "${ZSH_VERSION:-}" ]; then
    _CLAUDEOS_ENGINE_DIR=${0:a:h}
else
    _CLAUDEOS_ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# --- .NET SDK dans le PATH ---
# Un greffon peut porter un crochet qui lance `dotnet`, installé sous `~/.dotnet`, hors PATH par
# défaut ; ici plutôt que dans le fichier de shell, qui n'est pas sauvegardé. La garde teste
# l'EXÉCUTABLE : sous macOS, `~/.dotnet` existe sans SDK quand .NET vient de l'installeur officiel
# (caches et `tools/`), et un `DOTNET_ROOT` vers lui fait mourir tout outil .NET sur « You must
# install .NET to run this application » (Microsoft Learn, « Troubleshoot app launch failures »).
# Les ajouts au PATH ne se répètent pas quand le fichier est re-sourcé.
if [ -x "$HOME/.dotnet/dotnet" ]; then
    export DOTNET_ROOT="$HOME/.dotnet"
    case ":$PATH:" in *":$DOTNET_ROOT:"*) ;; *) export PATH="$DOTNET_ROOT:$PATH" ;; esac
elif [ "${DOTNET_ROOT:-}" = "$HOME/.dotnet" ]; then
    # La même valeur périmée, HÉRITÉE (un serveur tmux la transmet) : elle seule se retire.
    unset DOTNET_ROOT
fi
# Outils globaux .NET : `/etc/paths.d/dotnet-cli-tools` porte un tilde non développé.
if [ -d "$HOME/.dotnet/tools" ]; then
    case ":$PATH:" in *":$HOME/.dotnet/tools:"*) ;; *) export PATH="$PATH:$HOME/.dotnet/tools" ;; esac
fi

# --- tmux : pointeur local vers la config du dépôt ---
# `~/.tmux.conf` n'est suivi par aucun dépôt : il est régénéré en une ligne vers `reglages/tmux.conf`,
# à toi et FACULTATIF (absent, rien ne s'écrit), et seulement s'il diffère.
_claudeos_tmux_cfg="${_CLAUDEOS_ENGINE_DIR%/*}/reglages/tmux.conf"
if [ -f "$_claudeos_tmux_cfg" ]; then
    _claudeos_tmux_line="source-file $_claudeos_tmux_cfg"
    if [ "$(cat "$HOME/.tmux.conf" 2>/dev/null)" != "$_claudeos_tmux_line" ]; then
        printf '%s\n' "$_claudeos_tmux_line" > "$HOME/.tmux.conf" || true
    fi
    unset _claudeos_tmux_line
fi
unset _claudeos_tmux_cfg

# --- Préparation avant lancement : maj de Claude Code + pull des dépôts ---
# La paire de gestes vit dans `claudeos-session.sh --prepare`, seul endroit qui décide de ce que
# « être à jour » veut dire. Trois gardes : `$CLAUDECODE` posé = DÉJÀ dans Claude Code, tirer
# sous la session hôte imposerait son redémarrage ; `timeout`, car `claude update` peut pendre
# hors ligne (sans coreutils, on lance sans) ; `|| true`, la préparation ne bloque jamais.

# PAS DE PRÉFIXE `_` sur les fonctions que `claude()` appelle : le snapshot de shell de Claude
# Code ne recopie pas les fonctions `_*`.
claudeos_prepare() {
    local sess="$_CLAUDEOS_ENGINE_DIR/claudeos-session.sh"
    [ -f "$sess" ] || return 0
    [ -z "${CLAUDECODE:-}" ] || return 0
    printf '\n\033[2m— preparation ClaudeOS —\033[0m\n'
    if command -v timeout >/dev/null 2>&1; then
        timeout 180 bash "$sess" --prepare || true
    else
        bash "$sess" --prepare || true
    fi
    printf '\033[2m—\033[0m\n\n'
    return 0
}

# Le binaire nu : `command` atteint toujours l'exécutable, jamais la fonction `claude`
# ci-dessous (pas de récursion). Fonction et non alias : un alias passerait avant `claude`.
claudeos_claude_nu() {
    command claude "$@"
}

claude() {
    # Mode headless (claude -p / --print) : pas de préparation, sortie potentiellement pipée.
    case " $* " in
        *" -p "*|*" --print "*) claudeos_claude_nu "$@"; return ;;
    esac
    # `claude` NU seulement : ni `--resume` ni `claude "question"`, reprendre une session pendant
    # qu'on tire le dépôt est le défaut que `claudeos-session.sh` évite.
    if [ $# -eq 0 ] && [ -t 1 ]; then
        # DÉJÀ dans tmux ou dans Claude Code : on ne s'emboîte pas, on lance sur place.
        if [ -n "${TMUX:-}" ] || [ -n "${CLAUDECODE:-}" ]; then
            claudeos_prepare
            claudeos_claude_nu
            return
        fi
        # PORTE UNIQUE : hors de tmux, `claude` nu ouvre la session tmux PRINCIPALE et s'y attache,
        # pour qu'elle survive à la fermeture du terminal ; `--main` fait déjà la mise à jour et le
        # pull. Pas d'`exec` : remplacer le shell interactif fermerait le terminal au détachement.
        local _claudeos_sess="$_CLAUDEOS_ENGINE_DIR/claudeos-session.sh"
        if [ -f "$_claudeos_sess" ] && command -v tmux >/dev/null 2>&1; then
            bash "$_claudeos_sess" --main && tmux attach -t '=ClaudeOS'
            return
        fi
        # Repli : ni tmux ni le script — on lance quand même.
        claudeos_prepare
        claudeos_claude_nu
        return
    fi
    # Tout le reste (sous-commandes, resume, args explicites) : inchangé.
    claudeos_claude_nu "$@"
}
