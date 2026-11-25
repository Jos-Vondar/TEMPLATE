#!/usr/bin/env bash
# =============================================================================
# CONFIG — source unique des chemins & constantes du moteur ClaudeOS. À SOURCER.
#
# Le moteur appartient au template : une version neuve le remplace. Ce qui est à
# toi vit dans `reglages/` et ne se touche jamais par une mise à jour.
# =============================================================================

# Sourcé aussi sous zsh, où `BASH_SOURCE` est vide : zsh met dans `$0` le chemin du fichier sourcé
# (`:a` absolu, liens gardés, `:h` parent), sans `cd` qui déclencherait un crochet `chpwd`.
# Même idiome que `claudeos-boot.sh`.
if [ -n "${ZSH_VERSION:-}" ]; then
    SELF=${0:a:h}                                       # .../.claude/engine
    ROOT=${SELF:h}                                      # .../.claude = le système
else
    SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ROOT="$(cd "$SELF/.." && pwd)"
fi

# Références du moteur, livrées avec lui : la liste noire des dépôts de travail et le pilote
# de fusion des journaux. Aucun réglage de poste ne vit ici.
CFG="$SELF/config"

# RÉGLAGES DE L'INSTALLATEUR — `reglages/`, à lui, jamais touché par une version. Lus À L'APPEL,
# jamais au sourçage : un réglage changé vaut aussitôt. `CLAUDEOS_REG` pointe un autre dossier,
# pour les essais (un `REPONSES` d'épreuve) sans toucher au vrai.
REG="${CLAUDEOS_REG:-$ROOT/reglages}"

# claudeos_reponse CLE — la valeur de CLE dans `reglages/REPONSES`, sur la sortie standard.
# Format : une ligne `CLE=valeur`, `#` en tête pour un commentaire, jamais sourcé par un shell.
# rc=1 si le fichier ou la clé manque : l'appelant traite alors le poste comme NON RÉGLÉ, jamais
# comme réglé à une valeur d'usine. Comparaison EXACTE de la clé, jamais une sous-chaîne.
claudeos_reponse() {
    local f="$REG/REPONSES"
    [ -n "${1:-}" ] && [ -f "$f" ] || return 1
    awk -F= -v k="$1" '$1==k { sub(/^[^=]*=/, ""); print; trouve=1; exit } END { exit !trouve }' "$f"
}

# claudeos_liste CLE — les éléments d'une réponse à virgules (`PREFIXES`, `PREFIXES_CLIENT`,
# `SKILLS_OPTION`), un par ligne, espaces rognés. Rien si la clé manque ou est vide.
claudeos_liste() {
    local v
    v="$(claudeos_reponse "${1:-}")" || return 0
    printf '%s\n' "$v" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' || true
}

# La mémoire est canonique ici ; l'outil y écrit directement (`autoMemoryDirectory` de `settings.json`).
MEM="$HOME/.claude/memory"
# Tilde LITTÉRAL pour abréger un chemin à l'affichage : `${d/#$HOME/$CLAUDEOS_TILDE}`. La forme
# `${d/#$HOME/\~}` rend `\~/…` sous le bash 3.2 d'Apple, et un `~` nu est réexpansé en `$HOME`
# par bash 5. Par une variable, les deux rendent `~/…`.
CLAUDEOS_TILDE='~'

# Queue du chemin du shim de hook — SOURCE UNIQUE, lue par `claudeos-cloture.sh` et `install-poste.sh` :
# la copie qu'on oublierait au déménagement du hook accepterait un shim périmé sans rien dire.
CLAUDEOS_SHIM_TAIL='.claude/engine/hooks/pre-commit-alarmes.sh'

# claudeos_epoch_of_date — rend l'époque UNIX de minuit d'une date ISO (AAAA-MM-JJ) sur la sortie
# standard, ou RIEN et un code non nul si elle est illisible.
# `date -d` est une extension GNU, refusée par BSD : un repli `|| echo 0` changerait l'erreur en
# alarme verte par construction (rappel jamais échu, audit jamais dû). L'échec se rend.
# Deux branches exactes, dans cet ordre : `date -d` (GNU, sans coût), puis `python3`, dépendance
# dure du moteur. La forme BSD `date -j -f` est écartée : sur un format sans heure elle complète
# avec l'heure COURANTE, et peut faire basculer un écart en jours d'une unité.
claudeos_epoch_of_date() {
    [ -n "${1:-}" ] || return 1
    date -d "$1" +%s 2>/dev/null && return 0
    python3 -c 'import datetime,sys;print(int(datetime.datetime.strptime(sys.argv[1],"%Y-%m-%d").timestamp()))' "$1" 2>/dev/null && return 0
    return 1
}

# claudeos_hash_file — empreinte d'un fichier, sur la sortie standard, sans le nom.
# `md5sum` est GNU ; macOS livre `md5` et `shasum`. Sans repli, deux empreintes vides se
# compareraient égales : « copies identiques » par construction.
# L'algorithme importe peu, la constance oui : dans une même exécution le premier outil disponible
# gagne partout, donc les empreintes restent comparables entre elles. On ne les conserve jamais.
claudeos_hash_file() {
    [ -f "${1:-}" ] || return 1
    if command -v md5sum >/dev/null 2>&1; then md5sum "$1" | cut -d" " -f1; return 0; fi
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d" " -f1; return 0; fi
    if command -v md5    >/dev/null 2>&1; then md5 -q "$1"; return 0; fi
    return 1
}

# claudeos_lock CONTEXTE : verrou exclusif non-bloquant contre l'exécution
# concurrente (deux onglets qui clôturent en même temps sur un poste).
# fd 9 relâché à la mort du process → pas de verrou zombie. Sans flock ou si le
# verrou ne peut être créé, dégrade en no-op bruyant plutôt que de bloquer.
claudeos_lock() {
    local ctx="$1" lockfile="$HOME/.claude/.claudeos.lock" _flock=""
    # `flock` n'existe pas dans macOS ; il vient de `util-linux`, que Homebrew installe KEG-ONLY,
    # hors du PATH. Ne PAS mettre `util-linux` dans le PATH : il livre aussi `kill`, `nice`,
    # `more`, qui masqueraient ceux du système. Les chemins ci-dessous sont des candidats testés
    # exécutables : Apple Silicon puis Intel. Sans aucun, le no-op bruyant.
    _flock=$(command -v flock 2>/dev/null) || _flock=""
    if [ -z "$_flock" ]; then
        for _c in /opt/homebrew/opt/util-linux/bin/flock /usr/local/opt/util-linux/bin/flock; do
            [ -x "$_c" ] && { _flock="$_c"; break; }
        done
    fi
    [ -n "$_flock" ] || { echo "[$ctx] WARN : flock absent — verrou de concurrence désactivé." >&2; return 0; }
    # Test d'écriture SCOPÉ (le 2>/dev/null ne porte que sur ce groupe, jamais sur exec :
    # 'exec 9>f 2>/dev/null' détournerait TOUT le stderr du process de façon permanente).
    if ! { : >>"$lockfile"; } 2>/dev/null; then
        echo "[$ctx] WARN : verrou impossible ($lockfile) — on continue sans." >&2
        return 0
    fi
    exec 9>"$lockfile"
    if ! "$_flock" -n 9; then
        echo "[$ctx] ERREUR : une autre opération ClaudeOS est en cours (verrou détenu). Abandon." >&2
        return 1
    fi
    return 0
}

# --- Motifs de détection de secret — SOURCE UNIQUE du moteur.
# Deux copies à deux âges divergent, et c'est alors la plus silencieuse qui devient muette sans
# que rien ne le dise.
#
# FORMES — préfixes imposés par les éditeurs (AWS, GitHub, GitLab, Google, Slack, Anthropic, clé PEM).
# Tous ont une casse EXACTE, donc à comparer SANS l'option d'insensibilité : comparer sans la
# casse ne rattrape aucun secret réel et fait sonner n'importe quel bloc base64 (sur quelques
# centaines de kilo-octets, 'akia' suivi de seize caractères alphanumériques sort par hasard).
CLAUDEOS_SECRET_RE_FORMES='(-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,}|glpat-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-ant-[A-Za-z0-9_-]{20,})'
# MOTS — un mot-clé suivi d'une valeur. Ici la casse varie selon qui écrit le fichier, donc
# l'insensibilité est utile et se garde.
CLAUDEOS_SECRET_RE_MOTS='(api[_-]?key|secret|password|passwd|token)[^[:alnum:]]{1,4}[A-Za-z0-9/+_.=-]{20,}'
# NOMS — le nom du fichier annonce un secret, même si aucune ligne ne matche les deux
# précédents : une clé nue, seule dans son fichier, n'a ni mot-clé ni forme connue.
CLAUDEOS_SECRET_NAME_RE='(secret|passw(or)?d|credential|api[._-]?key|[._-]token)'
# DONNÉES TEXTE — un export ou un journal partirait sans un mot. Lues par le hook ET par la
# clôture, qui pose la même question avant de committer pour mettre ces fichiers de côté au lieu
# de laisser l'alarme bloquer la sauvegarde. Deux lecteurs, donc un seul motif. Pas de liste
# blanche : elle serait muette.
CLAUDEOS_DATA_RE='\.(csv|tsv|txt|json|jsonl|xml|eml|msg)$'
# EXEMPTIONS de l'alarme donnée, mêmes deux lecteurs : un fichier que le crochet exempte mais que la
# clôture met de côté sortirait du commit EN SILENCE. Toutes ANCRÉES SUR LE CHEMIN, jamais sur
# l'extension : une alarme forcée par routine apprend à ignorer sa catégorie entière. Les contrôles
# de nom et de contenu de secret balaient toujours les fichiers exemptés.
# Tout chemin qui traverse un dossier `extracted/`.
CLAUDEOS_DATA_EXEMPT_RE='/extracted/'
# Journal d'événements : un `.jsonl` neuf naît chaque mois. `journal/AAAA-MM.jsonl` seulement ; un
# `.jsonl` ailleurs, ou nommé autrement dans `journal/`, reste refusé.
CLAUDEOS_DATA_EXEMPT_RE+='|(^|/)journal/[0-9]{4}-[0-9]{2}\.jsonl$'
# Configuration du harnais, pas une donnée client ; le contrôle 17 du crochet refuse un JSON invalide.
# PIÈGE, les DEUX formes que `git` rend : `settings.json` à la racine (le dépôt `~/.claude` a pour
# racine `.claude`) et `.claude/settings.json` à toute profondeur (dépôts clients). Ne garder que la
# seconde raterait le dépôt système ; un `settings.json` en sous-dossier quelconque reste refusé.
# `settings.local.json` N'EST PAS exempté : permissions locales d'un poste, rien à faire en zone partagée.
CLAUDEOS_DATA_EXEMPT_RE+='|(^settings\.json$|(^|/)\.claude/settings\.json$)'
# EXEMPTION DU DÉPÔT SYSTÈME SEUL, mêmes deux lecteurs, à appliquer quand le dépôt est `~/.claude` :
# les `.json` livrés par le template sous `gabarits/` et `installateur/` (fragment de réglages,
# réglages de la session d'installation, astuces), sans aucune donnée, à un seul niveau, et les trois
# `.json` de déclaration d'un mod sous `mods/<nom>/`. Hors du
# dépôt système, un `gabarits/x.json` est une donnée comme une autre et reste refusé.
CLAUDEOS_DATA_EXEMPT_SYSTEME_RE='^(gabarits|installateur)/[^/]+\.json$|^mods/[^/]+/(\.claude-plugin/plugin|hooks/hooks|tsconfig)\.json$'

# --- Régimes morts et chemins de poste — SOURCE UNIQUE des contrôles 15 et 16 du crochet ------
# CE FICHIER EST EXCLU DU PÉRIMÈTRE des deux contrôles (`CLAUDEOS_TEXTES_HORS_GARDE_RE`, plus
# bas) : il porte les motifs en clair, il se refuserait lui-même.
#
# NOMS MORTS — ce qu'une session fraîche ne doit plus lire comme une INSTRUCTION : les noms du
# régime des V1 et V2 du template, communs à tout poste qui en vient — le fichier de reprise, le
# manifeste de la copie rsync, l'ancienne racine des dossiers de travail (avec sa forme
# `.ancien-…`). Tes propres noms morts s'ajoutent dans `reglages/NOMS_MORTS`, un motif ERE par
# ligne, `#` en tête pour un commentaire : ils rejoignent le motif ci-dessous à chaque sourçage.
# LA PROVENANCE DATÉE PASSE : une ligne qui cite un nom mort ET porte une date raconte ; sans date
# elle prescrit, et le crochet la refuse (code 27). Formes de date : ISO (jour ou mois) et JJ/MM.
# LIMITE ASSUMÉE : une instruction qui porte une date passe ; un récit sans date se lève par
# `FORCE_NOMS_MORTS`, tracé.
CLAUDEOS_NOMS_MORTS_RE='HANDOFF|SYNC_MAP|(~|\$HOME|/Users/[^/ ]+|/home/[^/ ]+)/workstations([^A-Za-z0-9_]|$)'
if [ -f "$REG/NOMS_MORTS" ]; then
    _cos_nm="$(grep -vE '^[[:space:]]*(#|$)' "$REG/NOMS_MORTS" | paste -sd'|' - 2>/dev/null)"
    [ -n "$_cos_nm" ] && CLAUDEOS_NOMS_MORTS_RE="$CLAUDEOS_NOMS_MORTS_RE|$_cos_nm"
    unset _cos_nm
fi
CLAUDEOS_PROVENANCE_DATEE_RE='20[0-9]{2}-[0-9]{2}(-[0-9]{2})?|[0-3][0-9]/[01][0-9](/20[0-9]{2})?'
# CHEMINS DE POSTE — un chemin absolu de dossier personnel dans un fichier SUIVI voyage, et il est
# faux sur un autre poste, dont le `HOME` diffère. Trois formes : macOS, Linux et WSL, et le
# montage d'un disque Windows vu depuis WSL ou d'un Mac vu depuis une machine virtuelle.
#   · Le premier caractère du compte est alphanumérique : les FORMES ANONYMISÉES `/Users/<x>/`,
#     `/Users/…/`, `/Users/.../` passent — ce sont elles qu'on veut lire dans une fiche.
#   · Le crochet DÉSÉCHAPPE `\/` → `/` avant de comparer : un outil qui réécrit `settings.json`
#     peut échapper les barres, et le motif nu n'y verrait rien.
CLAUDEOS_CHEMIN_POSTE_RE='/Users/[A-Za-z0-9_-][A-Za-z0-9._-]*/|/home/[a-z_][a-z0-9_-]*/|/mnt/(c|mac)/'
# HORS PÉRIMÈTRE des deux contrôles, par le CHEMIN relatif à la racine du dépôt : les archives
# (gelées par en-tête, mais nommées ici aussi — un gel manquant ne doit pas faire crier sur du
# passé), les rapports d'audit (ils CITENT le défaut, c'est leur métier), et les trois fichiers du
# template qui nomment l'ancien régime PAR FONCTION : ce fichier, qui porte les motifs ; le script
# d'import d'une V1 ou d'une V2 ; la procédure de migration de l'agent. Les fichiers GELÉS par
# en-tête `> **GELÉ` en première ligne sont exclus par le crochet lui-même.
CLAUDEOS_TEXTES_HORS_GARDE_RE='(^|/)(ARCHIVE|SESSION_ARCHIVE|LEARNING_ARCHIVE)\.md$|(^|/)audits/|^engine/config\.sh$|^engine/import-v2\.py$|^installateur/MIGRER\.md$'

# claudeos_ws_roots : émet un chemin absolu par DOSSIER DE TRAVAIL, lu SUR LE DISQUE, selon `GIT`
# (`reglages/REPONSES`) :
#   · `par-domaine` — pour chaque préfixe de `PREFIXES`, les dossiers `~/<préfixe>*/` qui portent
#     un `CLAUDE.md`. Il faut les DEUX marques : le dossier personnel porte aussi des dossiers qui
#     ne sont pas des dépôts de travail. Un préfixe ne commence pas par un point, donc `~/.claude`
#     et la configuration d'outils ne peuvent pas être ramassés par construction.
#   · `unique` et `aucun` — les dossiers `~/.claude/travail/*/` qui portent un `CLAUDE.md`.
#   · `GIT` absent : RIEN, et une ligne sur la sortie d'erreur — un poste non réglé ne se devine pas.
# CHEMIN ANCRÉ sur le dossier personnel, jamais en dur : deux postes aux noms différents.
claudeos_ws_roots() {
    local g d p
    if ! g="$(claudeos_reponse GIT)"; then
        echo "[claudeos] poste non réglé : reglages/REPONSES ne porte pas GIT — aucun dossier de travail listé." >&2
        return 0
    fi
    case "$g" in
        par-domaine)
            while IFS= read -r p; do
                for d in "$HOME/$p"*/; do
                    [ -d "$d" ] && [ -f "${d}CLAUDE.md" ] || continue
                    printf '%s\n' "${d%/}"
                done
            done < <(claudeos_liste PREFIXES)
            ;;
        unique|aucun)
            for d in "$ROOT"/travail/*/; do
                [ -d "$d" ] && [ -f "${d}CLAUDE.md" ] || continue
                printf '%s\n' "${d%/}"
            done
            ;;
        *)
            echo "[claudeos] GIT=$g inconnu dans reglages/REPONSES — aucun dossier de travail listé." >&2
            ;;
    esac
    return 0
}

# claudeos_repos : émet un chemin absolu par DÉPÔT GIT du système, `~/.claude` en tête.
#   · `aucun` : RIEN — sans git, il n'y a aucun dépôt (tout reste sur le poste).
#   · `unique`, ou `GIT` absent : `~/.claude` seul ; ses dossiers de travail vivent dedans.
#   · `par-domaine` : `~/.claude`, puis chaque dossier de travail qui porte un `.git` — c'est ce qui
#     fait un dépôt, pas le nom du dossier. Il s'appuie sur `claudeos_ws_roots` et ne le double pas.
claudeos_repos() {
    local g d
    g="$(claudeos_reponse GIT)" || g=""
    [ "$g" = "aucun" ] && return 0
    printf '%s\n' "$HOME/.claude"
    [ "$g" = "par-domaine" ] || return 0
    while IFS= read -r d; do
        [ -d "$d/.git" ] || continue
        printf '%s\n' "$d"
    done < <(claudeos_ws_roots)
    # `return 0` explicite : sans lui la fonction hérite du code du dernier test, donc rc=1 dès que
    # le dernier dossier examiné n'est pas un dépôt, et un appelant en `claudeos_repos || …`
    # conclurait à l'échec sur une sortie correcte.
    return 0
}

# --- Sessions ouvertes — SOURCE UNIQUE du bilan, de la clôture et de `claudeos-session.sh --list` ---
# Une session tmux par ligne, préfixée `tmux   `. $1 : session à taire (celle qui pose la question) ;
# $2 : format tmux (`-F`), sinon la ligne de `tmux ls`. Sans tmux, rien, rc 0.
claudeos_sessions() {
    command -v tmux >/dev/null 2>&1 || return 0
    if [ -n "${2:-}" ]; then tmux list-sessions -F "$2" 2>/dev/null; else tmux list-sessions 2>/dev/null; fi \
        | awk -v moi="${1:-}" '$0 != moi {print "tmux   " $0}'
    return 0
}

# --- Poste : le bloc de titre de `~/.zshrc` — SOURCE UNIQUE de ce qui est dû, que pose
# `install-poste.sh` et que tout autre lecteur doit lire ici. FACULTATIF : sa source est
# `reglages/zshrc-claudeos.zsh`, à l'installateur ; sans elle, ou sans bloc dedans, rien n'est dû. Le bloc va de la ligne
# `# >>> ClaudeOS — titre de terminal` à `# <<< ClaudeOS — titre de terminal`, marqueurs compris ;
# le reste de ce fichier ne part pas. Une ligne par écart :
#   zsh-titre   bloc absent de `~/.zshrc`, ou différent de celui de `reglages/zshrc-claudeos.zsh`
CLAUDEOS_ZSHRC_SOUCHE="$REG/zshrc-claudeos.zsh"

# claudeos_zshrc_bloc <nom> [fichier] : le bloc ClaudeOS <nom>, marqueurs compris, de la souche ou du fichier.
claudeos_zshrc_bloc() { sed -n "/^# >>> ClaudeOS — $1/,/^# <<< ClaudeOS — $1/p" "${2:-$CLAUDEOS_ZSHRC_SOUCHE}" 2>/dev/null; }

claudeos_poste_ecarts() {
    local bloc
    [ -f "$CLAUDEOS_ZSHRC_SOUCHE" ] || return 0
    bloc="$(claudeos_zshrc_bloc 'titre de terminal')"
    [ -n "$bloc" ] || return 0
    [ "$(claudeos_zshrc_bloc 'titre de terminal' "$HOME/.zshrc")" = "$bloc" ] || echo 'zsh-titre'
    return 0
}

# rc 0 si un rebase est interrompu dans le dépôt $1.
claudeos_rebase_en_cours() { [ -d "$1/.git/rebase-merge" ] || [ -d "$1/.git/rebase-apply" ]; }

# --- Verdict de pull d'un dépôt — SOURCE UNIQUE ---------------------------------
# Décide pour la préparation de session (`claudeos-session.sh`), explique pour le bilan
# (`boot-check.sh`) : une seule logique, sinon le bilan dirait un motif que le lanceur n'a pas
# appliqué. Ne fetch PAS — les refs distantes sont celles de l'appelant. Lit l'état COURANT, ne
# mute rien.
# Rend UNE ligne : `AJOUR` · `SANS_AMONT` · `TIRER|propre` · `TIRER|autostash` · `ATTENDRE|<motif>`.
# Un dépôt modifié se tire par autostash : « dépôt sale jamais tiré » laisserait le dépôt système,
# presque toujours un peu sale, en retard à chaque lancement. L'autostash n'est sûr que si sa remise
# ne peut pas entrer en conflit : d'où les refus ci-dessous, chacun sur un cas réel ou certain.
# $2 optionnel : sessions tmux à NE PAS compter, séparées par une espace (celle qui pose la
# question sur elle-même).
claudeos_verdict_pull() {
    local repo="$1" moi=" ${2:-} " reel s p n ici amont croise
    git -C "$repo" rev-parse -q --verify '@{u}' >/dev/null 2>&1 || { echo "SANS_AMONT"; return 0; }
    n=$(git -C "$repo" rev-list --count 'HEAD..@{u}' 2>/dev/null)
    [ "${n:-0}" -eq 0 ] && { echo "AJOUR"; return 0; }
    if claudeos_rebase_en_cours "$repo" || [ -f "$repo/.git/MERGE_HEAD" ]; then
        echo "ATTENDRE|opération git déjà en cours (rebase ou fusion)"; return 0
    fi
    # 1. UNE SESSION TMUX TRAVAILLE DANS LE DÉPÔT : un pull rebaserait sous ses pieds.
    # Chemins comparés RÉSOLUS : `~/.claude` et les dossiers de travail peuvent être des liens.
    reel=$(cd "$repo" 2>/dev/null && pwd -P)
    if [ -n "$reel" ] && command -v tmux >/dev/null 2>&1; then
        while IFS='|' read -r s p; do
            [ -z "$s" ] && continue
            case "$moi" in *" $s "*) continue ;; esac
            p=$(cd "$p" 2>/dev/null && pwd -P)
            case "$p/" in "$reel"/*) echo "ATTENDRE|session $s en cours dans le dépôt"; return 0 ;; esac
        done < <(tmux list-panes -a -F '#{session_name}|#{pane_current_path}' 2>/dev/null)
    fi
    ici=$(git -C "$repo" diff --name-only --no-renames HEAD 2>/dev/null)
    [ -z "$ici" ] && [ -z "$(git -C "$repo" ls-files --others --exclude-standard 2>/dev/null)" ] \
        && [ "$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null)" = "0" ] \
        && { echo "TIRER|propre"; return 0; }
    amont=$(git -C "$repo" diff --name-only --no-renames 'HEAD...@{u}' 2>/dev/null)
    # 2. MODIFIÉ ICI ET CHANGÉ EN AMONT — la remise du stash entrerait en conflit.
    croise=$(comm -12 <(printf '%s\n' "$ici" | sort -u) <(printf '%s\n' "$amont" | sort -u) | grep -v '^$' | head -3 | paste -sd ',' -)
    [ -n "$croise" ] && { echo "ATTENDRE|modifié ici ET en amont : ${croise}"; return 0; }
    # 3. NON SUIVI ICI, AJOUTÉ EN AMONT — l'autostash ne range pas les non-suivis, git refuserait
    # de les écraser. Cas certain : `journal/<mois>.jsonl` créé le 1er du mois sur deux postes.
    croise=$(comm -12 <(git -C "$repo" ls-files --others --exclude-standard 2>/dev/null | sort -u) \
        <(git -C "$repo" diff --name-only --no-renames --diff-filter=A 'HEAD...@{u}' 2>/dev/null | sort -u) | head -3 | paste -sd ',' -)
    [ -n "$croise" ] && { echo "ATTENDRE|non suivi ici, ajouté en amont : ${croise}"; return 0; }
    # 4. COMMITS LOCAUX EN CONFLIT avec l'amont — fusion d'essai : elle écrit des objets dans la base,
    # jamais dans une branche, l'index ou la copie de travail.
    if [ "$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null)" != "0" ] \
        && ! git -C "$repo" merge-tree --write-tree HEAD '@{u}' >/dev/null 2>&1; then
        echo "ATTENDRE|commits locaux en conflit avec l'amont"; return 0
    fi
    if [ -n "$ici" ]; then echo "TIRER|autostash"; else echo "TIRER|propre"; fi
    return 0
}

# Le régime git du poste — `claudeos_regime`, `claudeos_racines`, `claudeos_suivis` : code propre
# au template, tenu à part pour que les fichiers reportés de la source changent le moins possible.
# shellcheck source=lib_regime.sh
. "$SELF/lib_regime.sh"

# --- Plafonds de taille et cliquet de croissance — SOURCE UNIQUE ---------------
# Lus par `hooks/pre-commit-alarmes.sh`, contrôles 8 et 9. Un seul endroit : l'en-tête d'un
# fichier borné porte un renvoi, jamais une valeur — deux copies à deux âges se contredisent.
# UNITÉ : caractères (comptés par `python3`), pas octets — les accents comptent double en UTF-8
# et un plafond en octets punirait le français.
CLAUDEOS_PLAFOND_MEMORY=8000
# ETAT.md : il porte ce que portaient la mémoire (8 000) et la reprise (12 000) d'un niveau, plus
# les décisions en vigueur. Un dépassement signale de la VERBOSITÉ plus que de la dette : solder
# des dus fait peu maigrir. Un `ETAT.md` est une PROJECTION, il ne s'allège pas à la main (code 23
# du crochet). Le levier est à l'écriture : `TEXTE_MAX_PROJETE` dans `engine/etat.py` borne par
# type le texte projeté et refuse à l'`add` ; le récit va en `--type observation`, qui ne pèse
# rien sur la projection. Ce plafond est le témoin du RÉSULTAT, il ne dit pas où couper.
CLAUDEOS_PLAFOND_ETAT=25000

# Exceptions NOMMÉES : un plafond propre à un fichier, une ligne `<dépôt>/<chemin relatif>=plafond`,
# en caractères, dans `reglages/PLAFONDS` — à toi, aucune n'est livrée. Le préfixe est le NOM DU
# DOSSIER du dépôt, jamais un chemin absolu : deux postes ont des dossiers personnels différents,
# le nom du dépôt est le même. La comparaison est exacte (`awk $1==k`), jamais une sous-chaîne.
# Une exception RELÈVE un plafond : ne l'écrire qu'après avoir versé et soldé ce qui pouvait l'être.
CLAUDEOS_PLAFOND_EXCEPTIONS=''
[ -f "$REG/PLAFONDS" ] && CLAUDEOS_PLAFOND_EXCEPTIONS="$(grep -vE '^[[:space:]]*(#|$)' "$REG/PLAFONDS")"

# claudeos_plafond_de <depot>/<chemin-relatif-au-depot> : émet le plafond applicable, en caractères.
# L'exception nommée gagne ; sinon le défaut selon le nom de fichier. Rien émis, rc=1, si le
# fichier n'est pas un fichier d'état borné — l'appelant distingue alors « pas borné » de
# « borné à zéro », que la même sortie vide confondrait.
# SOURCE UNIQUE, appelée par `hooks/pre-commit-alarmes.sh` (contrôle 8), `plafonds-parc.sh` et
# `boot-check.sh` : deux implantations du même calcul divergeraient au premier correctif.
# HORS RÉGIME : `.claude/memory/MEMORY.md` est l'INDEX de la mémoire automatique, que l'outil
# borne lui-même (200 lignes ou 25 Ko, documentation de l'éditeur). Un second régime, plus
# serré, crierait pour rien — et un signal qu'on sait devoir ignorer apprend à ignorer la catégorie.
CLAUDEOS_PLAFOND_HORS_REGIME='
.claude/memory/MEMORY.md
'

claudeos_plafond_de() {
    local f="$1" ex
    printf '%s\n' "${CLAUDEOS_PLAFOND_HORS_REGIME:-}" | grep -qxF "$f" && return 1
    ex="$(printf '%s\n' "${CLAUDEOS_PLAFOND_EXCEPTIONS:-}" | awk -F= -v k="$f" '$1==k {print $2; exit}')"
    if [ -n "$ex" ]; then printf '%s' "$ex"; return 0; fi
    case "${f##*/}" in
        MEMORY.md)  printf '%s' "${CLAUDEOS_PLAFOND_MEMORY:-8000}" ;;
        ETAT.md)    printf '%s' "${CLAUDEOS_PLAFOND_ETAT:-25000}" ;;
        *)          return 1 ;;
    esac
}

# CHEMINS NÉS AU PREMIER BESOIN. Les compétences livrées les citent, et une installation neuve ne
# les porte pas encore : le contrôle hebdomadaire 27 les compte à part au lieu de les crier. Trois
# n'existent jamais dans un régime donné : `RTK.md` sans proxy, les empreintes de clôture en régime
# GitHub, l'identité git sans git. Un chemin qui finit par `/` vaut pour tout ce qu'il contient.
CLAUDEOS_CHEMINS_AU_BESOIN='~/.claude.json ~/.claude/audits/ ~/.claude/memory ~/.claude/memory/ ~/.claude/plans/ ~/.claude/TODO.md ~/.claude/domaines/ ~/.claude/secrets-shared/ ~/.claude/reglages/CRENEAUX ~/.claude/RTK.md ~/.claude/.claudeos/empreintes/MANIFESTE.json ~/.claude/reglages/IDENTITE_GIT'

# CLIQUETS — dépôt système seulement. On ne remonte jamais : pour ajouter, il faut retirer.
# Une baisse se réécrit ici ; `git log -p` sur ces lignes montre toute remontée.
CLAUDEOS_CLIQUET_REGLEMENT=7000        # les fragments de noyau/regles/ retenus par le jeu MAX, octets,
                                       # mesurés à l'atelier (mesure-personnalisation.py taille). Il ne
                                       # mesure pas le CLAUDE.md, qui est à l'installateur.
CLAUDEOS_CLIQUET_DESCRIPTIONS=8858     # somme des `description:` de skills/*/SKILL.md en file, octets.
                                       # BAISSÉ de 9777 à 8858 le 2026-09-22 au soir, sur arbitrage de
                                       # l'utilisateur : cinq fiches supprimées, cliquet reposé sur l'état
                                       # atteint. Une baisse se réécrit ICI, datée.
CLAUDEOS_CLIQUET_INDEX=6794            # memory/MEMORY.md, octets — injecté à chaque session, posé le
                                       # 2026-09-22 sur l'état atteint après correction, arbitrage de
                                       # l'utilisateur. Mesuré par le crochet, bloc 9 (a2).
CLAUDEOS_CLIQUET_FICHE=33522           # plafond PAR FICHE, octets — posé sur la plus grosse au
                                       # 2026-09-22, `os-audit`. Il borne la dérive du corps, celle que
                                       # le sondage de déclenchement cherche. Un cliquet ne remonte jamais.
CLAUDEOS_CLIQUET_PERSONNALISATION=75   # pourcent, cliquet INVERSE posé sur la mesure de l'A4 : la
                                       # part des règles des fragments de noyau/regles/ retenus par le
                                       # jeu MAX dont la présence ou la forme dépend d'une réponse, hors
                                       # les trois interdits du socle. Il ne BAISSE jamais, plancher 50
                                       # (d-mesure-perso) ; une montée se réécrit ici. Propriété du
                                       # template, comme les budgets en somme ci-dessous.
                                       # Mesure : python3 engine/mesure-personnalisation.py ratio
# BUDGETS EN SOMME — le code du moteur et la somme des fiches système, en octets lus à l'index du
# dépôt système. Une fiche système peut en financer une autre ; les fiches de métier sont hors
# budget. Propriétés du template, MESURÉES À L'ATELIER sur l'arbre livré de chaque version, qui
# apporte les siennes : `claudeos_somme`, lancée à la racine de l'arbre livré, avec les motifs
# ci-dessous. Le crochet AVERTIT quand ils sont dépassés, il ne refuse pas : chez l'installateur, un
# dépassement vient d'une version gardée à la mise à jour ou d'un correctif local.
CLAUDEOS_MOTEUR_RE='^(engine/.*[.](sh|py)|[^/]+[.]sh|resources/.*[.](sh|py))$'
# Hors budget : les bancs d'essai, et la ligne d'état que Claude Code écrit à la racine, code
# d'amont qui n'est pas du moteur.
CLAUDEOS_MOTEUR_HORS_RE='(^|/)tests/|(^|/)test_|^statusline-command[.]sh$'
CLAUDEOS_FICHES_SYSTEME="reprise memoire-et-verite session controles-et-alarmes carte-complete fichiers-et-nommage os-audit demarrage tri-des-fils pousser-son-dossier secrets-detail nouveau-projet nouveau-domaine claudeos-onboarding"
CLAUDEOS_FICHES_SYSTEME_RE="^skills/(${CLAUDEOS_FICHES_SYSTEME// /|})/.*[.]md\$"
# Mesurés sur l'arbre livré de la v3.1.0 (moteur 689873 octets, fiches 155856 octets), plus 1 %, arrondi au
# millier supérieur : la marge d'une retouche locale gardée (`regime.py garde`, un correctif WSL).
CLAUDEOS_CLIQUET_MOTEUR=697000          # octets
CLAUDEOS_CLIQUET_FICHES_SYSTEME=158000  # octets
CLAUDEOS_INCIDENT_SOLDE_MAX=1024       # octets ajoutés au moteur au-delà desquels « incident: » compte comme chantier

# Somme en octets des fichiers suivis dont le chemin répond à RE et pas à EX : à l'index, ou
# dans l'arbre nommé en troisième argument. Se lance depuis la racine du dépôt.
claudeos_somme() {
    local re="$1" ex="$2" arbre="${3:-}"
    if [ -n "$arbre" ]; then
        git ls-tree -r -l "$arbre" | awk -F'\t' -v re="$re" -v ex="$ex" \
            '$2 ~ re && (ex=="" || $2 !~ ex) {split($1,a," "); s+=a[4]} END {print s+0}'
    else
        git ls-files -s | awk -F'\t' -v re="$re" -v ex="$ex" \
            '$2 ~ re && (ex=="" || $2 !~ ex) {split($1,a," "); print a[2]}' \
            | git cat-file --batch-check='%(objectsize)' | awk '{s+=$1} END {print s+0}'
    fi
}

# CLIQUETS DU POSTE — descriptions, index de mémoire et fiche : les valeurs ci-dessus sont celles du
# template, et elles sont tes BUDGETS DE DÉPART. L'installation n'en remesure aucun : mesurés sur
# un poste neuf, les descriptions n'auraient laissé aucune place à ta première compétence, que rien
# de tien n'aurait pu financer, et l'index, encore absent, se serait figé à rien.
# `reglages/CLIQUETS`, une ligne `CLE=valeur`, fixe ton propre budget et l'emporte alors. La leçon du
# cliquet tient — pour ajouter, retirer d'abord —, mais le budget est le tien : il se baisse après un
# ménage, et se relève aussi, si tu le décides. Le règlement, les budgets en somme et la
# personnalisation sont des propriétés du template et restent ici.
if [ -f "$REG/CLIQUETS" ]; then
    while IFS='=' read -r _cos_k _cos_v; do
        case "$_cos_k" in
            CLAUDEOS_CLIQUET_DESCRIPTIONS|CLAUDEOS_CLIQUET_INDEX|CLAUDEOS_CLIQUET_FICHE)
                case "$_cos_v" in ''|*[!0-9]*) ;; *) printf -v "$_cos_k" '%s' "$_cos_v" ;; esac ;;
        esac
    done < "$REG/CLIQUETS"
    unset _cos_k _cos_v
fi
