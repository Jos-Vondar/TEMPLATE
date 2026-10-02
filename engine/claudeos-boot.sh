# === ClaudeOS · wrapper de démarrage ===
# Lancement `claude` sans argument → injecte le prompt « tu es à jour ? » pour que
# l'assistant produise le bilan de démarrage comme PREMIER message de la session.
# (Un hook de démarrage ne peut qu'injecter du contexte, pas déclencher un tour ;
#  seul un prompt soumis au lancement fait parler l'assistant en premier.)
# PORTABILITÉ, 2026-09-12. `BASH_SOURCE` N'EXISTE PAS EN ZSH, et ce fichier est SOURCÉ par
# `~/.zshrc` sur le Mac. `dirname ""` rend `.`, donc les deux chemins résolus plus bas valaient le
# DOSSIER COURANT du shell qui démarre au lieu de `~/.claude/engine` : `~/.tmux.conf` n'était jamais
# écrit, et `_claudeos_prepare` se taisait — `claude` tapé nu ne tirait plus rien, ce que le wrapper existe
# précisément pour faire. Le repli `:-$0` couvre les deux shells : bash renseigne `BASH_SOURCE`, et
# zsh met dans `$0` le chemin du fichier sourcé. Ne pas remplacer par un chemin en dur : le PC sous
# WSL source le MÊME fichier depuis bash, où `$0` vaudrait `-bash`.
# Sourcé depuis ~/.bashrc. Lecture seule, ne bloque JAMAIS le lancement (|| true).
# Vit dans le repo de config → synchronisé entre machines ; seul le `source` dans
# ~/.bashrc reste manuel par machine.

# --- .NET SDK dans le PATH ---
# Un greffon peut porter un crochet qui lance `dotnet`. Le SDK s'installe sous
# ~/.dotnet, hors PATH par défaut : sans ce bloc, chaque prompt échouerait sur
# « dotnet: not found » (constaté le 2026-08-12). Ici plutôt que dans ~/.bashrc,
# qui n'est pas sauvegardé.
# Garde d'existence : un poste peut ne pas avoir .NET, le lancement ne doit pas casser.
# LA GARDE TESTE L'EXÉCUTABLE, PLUS LE DOSSIER — corrigé le 2026-10-01. Sous macOS, `~/.dotnet`
# existe SANS SDK quand .NET vient de l'installeur officiel : le CLI y range ses caches et `tools/`, le
# runtime vit sous `/usr/local/share/dotnet`. `DOTNET_ROOT` pointait donc un dossier vide de runtime,
# et tout outil .NET mourait sur « You must install .NET to run this application » : la variable fait
# sauter l'emplacement par défaut (Microsoft Learn, « Troubleshoot app launch failures »). Les deux
# ajouts au PATH ne se répètent pas quand le fichier est re-sourcé.
if [ -x "$HOME/.dotnet/dotnet" ]; then
    export DOTNET_ROOT="$HOME/.dotnet"
    case ":$PATH:" in *":$DOTNET_ROOT:"*) ;; *) export PATH="$DOTNET_ROOT:$PATH" ;; esac
elif [ "${DOTNET_ROOT:-}" = "$HOME/.dotnet" ]; then
    # La même valeur périmée, HÉRITÉE : un serveur tmux démarré avant la correction la transmet à
    # chaque fenêtre. Elle seule se retire — un `DOTNET_ROOT` posé ailleurs n'est pas touché.
    unset DOTNET_ROOT
fi
# Outils globaux .NET. L'installeur de macOS écrit `~/.dotnet/tools` TEL QUEL dans
# `/etc/paths.d/dotnet-cli-tools`, et le tilde n'y est pas développé : on l'ajoute ici, en absolu,
# sans toucher à ce fichier système.
if [ -d "$HOME/.dotnet/tools" ]; then
    case ":$PATH:" in *":$HOME/.dotnet/tools:"*) ;; *) export PATH="$PATH:$HOME/.dotnet/tools" ;; esac
fi

# --- tmux : pointeur local vers la config du dépôt ---
# Les sessions de projet vivent dans tmux, et leur config doit voyager. Or
# `~/.tmux.conf` n'est suivi par aucun dépôt, comme `~/.bashrc` : un réglage écrit
# dedans serait perdu d'un poste à l'autre. Ce bloc régénère donc un pointeur d'une
# ligne vers `reglages/tmux.conf`, à toi et FACULTATIF : absent, rien ne s'écrit.
# Écrit seulement s'il diffère, pour ne pas réécrire le fichier à chaque ouverture
# de shell. Résolu depuis l'emplacement de CE fichier, jamais un chemin de poste.
_claudeos_tmux_cfg="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)/reglages/tmux.conf"
if [ -f "$_claudeos_tmux_cfg" ]; then
    _claudeos_tmux_line="source-file $_claudeos_tmux_cfg"
    if [ "$(cat "$HOME/.tmux.conf" 2>/dev/null)" != "$_claudeos_tmux_line" ]; then
        printf '%s\n' "$_claudeos_tmux_line" > "$HOME/.tmux.conf" || true
    fi
    unset _claudeos_tmux_line
fi
unset _claudeos_tmux_cfg

# --- Lancement du binaire, variables SSH_* retirées ---
# Demandé le 2026-08-15. Ce conteneur OrbStack expose SSH_CONNECTION=::1 — une
# boucle locale, pas une vraie session distante ; le binaire s'y croit pourtant en
# SSH. Ce helper retire les trois variables avant de lancer.
# Ici plutôt qu'en `alias claude=...` dans ~/.bashrc, qui était la première idée :
# un alias passe AVANT une fonction, donc il court-circuiterait la fonction
# `claude` ci-dessous et supprimerait l'injection du prompt de bilan (mesuré, pas
# supposé). Et ~/.bashrc n'est pas au manifeste de sauvegarde, donc le réglage ne
# voyagerait pas entre postes ; ce fichier-ci, si.
# Pas de récursion : `env` résout `claude` dans le PATH et ne voit pas les
# fonctions du shell, donc il atteint toujours le binaire, jamais ce wrapper.
# --- Preparation avant lancement : maj de Claude Code + pull des deux depots ---
# Demande le 2026-09-02. Le profil VS Code « ClaudeOS » faisait deja ces deux gestes,
# via `claudeos-session.sh --main` ; taper `claude` dans un terminal ne les faisait PAS, donc
# le bilan de demarrage annoncait 40 commits de retard que rien ne tirait. La paire de
# gestes n'est pas recopiee ici : elle vit dans `claudeos-session.sh --prepare`, seul endroit
# qui decide de ce que « etre a jour » veut dire.
#
# TROIS GARDES, chacune pour un defaut mesurable :
#  1. `$CLAUDECODE` pose = on est DEJA dans une session Claude Code (shell d'agent,
#     sous-session). Tirer le depot sous les pieds de la session hote imposerait le
#     redemarrage que tout ce mecanisme existe pour supprimer.
#  2. `timeout` : hors-ligne ou reseau lent, `claude update` peut pendre. Le lancement
#     ne doit jamais attendre indefiniment. Garde d'existence : un poste peut ne pas
#     avoir coreutils, on lance alors sans timeout plutot que de ne rien lancer.
#  3. `|| true` : conformement a la doctrine de ce fichier, la preparation ne BLOQUE
#     JAMAIS le lancement. Un depot sale, un pull refuse, une maj impossible : ca se
#     dit a l'ecran et la session s'ouvre quand meme.
#
# Un pull qui modifie CE fichier n'a pas d'effet sur la session en cours (la fonction
# est deja en memoire), mais bien sur le binaire lance ensuite, qui relit tout le
# dossier de config. C'est l'ordre voulu : preparer, PUIS lancer.
_CLAUDEOS_ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

_claudeos_prepare() {
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

_claudeos_claude() {
    env -u SSH_CLIENT -u SSH_CONNECTION -u SSH_TTY claude "$@"
}

claude() {
    # Mode headless (claude -p / --print) : pas d'injection, sortie potentiellement pipée.
    case " $* " in
        *" -p "*|*" --print "*) _claudeos_claude "$@"; return ;;
    esac
    # Lancement interactif sans argument : injecter le prompt de bilan.
    # La garde qui sautait cette injection quand le bilan avait été DÉCLINÉ à l'entretien
    # d'installation est retirée le 2026-08-22 (palier 5), avec la chaîne d'export qui était
    # le seul producteur du fichier de réponses. Fichier absent = conditions toutes vraies,
    # donc cette branche ne pouvait déjà plus être prise ici.
    if [ $# -eq 0 ] && [ -t 1 ]; then
        # Perimetre tranche le 2026-09-02 : `claude` NU seulement. Ni `--resume`,
        # ni `claude "une question"` : reprendre une session pendant qu'on tire le
        # depot est exactement le defaut que `claudeos-session.sh` documente et evite.
        # PORTE UNIQUE, 2026-09-12 : `claude` nu ouvre la session tmux PRINCIPALE et s'y
        # attache, au lieu de lancer Claude Code dans le terminal courant. Motif — la session
        # survit a la fermeture du terminal et a une coupure SSH, ce qui est exactement le
        # gain que `claudeos-session.sh` documente ; le faire passer par une seconde commande
        # revenait a ne jamais en profiter.
        #
        # DEUX GARDES. Deja DANS tmux ou DANS Claude Code : on ne s'emboite pas, on lance sur
        # place. Et pas d'`exec` : cette fonction vit dans le shell INTERACTIF, donc `exec`
        # remplacerait ce shell et fermerait le terminal au detachement de tmux.
        if [ -n "${TMUX:-}" ] || [ -n "${CLAUDECODE:-}" ]; then
            _claudeos_prepare
            _claudeos_claude "tu es à jour ?"
            return
        fi
        local _claudeos_sess="$_CLAUDEOS_ENGINE_DIR/claudeos-session.sh"
        if [ -f "$_claudeos_sess" ] && command -v tmux >/dev/null 2>&1; then
            # `--main` fait deja la mise a jour de Claude Code et le pull des depots :
            # `_claudeos_prepare` ferait double emploi. Un seul endroit decide de « etre a jour ».
            bash "$_claudeos_sess" --main && tmux attach -t ClaudeOS
            return
        fi
        # Repli : ni tmux ni le script — on ne reste pas muet, on lance quand meme.
        _claudeos_prepare
        _claudeos_claude "tu es à jour ?"
        return
    fi
    # Tout le reste (sous-commandes, resume, args explicites) : inchangé.
    _claudeos_claude "$@"
}
