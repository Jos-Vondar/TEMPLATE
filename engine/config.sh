#!/usr/bin/env bash
# =============================================================================
# CONFIG — source unique des chemins & constantes du moteur ClaudeOS. À SOURCER.
#
# Le moteur appartient au template : une version neuve le remplace. Ce qui est à
# toi vit dans `reglages/` et ne se touche jamais par une mise à jour.
# =============================================================================

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # .../.claude/engine
ROOT="$(cd "$SELF/.." && pwd)"                          # .../.claude = le système

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

# La mémoire est CANONIQUE ici depuis le 2026-08-22. Depuis le 2026-09-24 l'outil y écrit
# directement, par `autoMemoryDirectory` dans `settings.json` : plus de slug à calculer.
MEM="$HOME/.claude/memory"
# Tilde LITTÉRAL pour abréger un chemin à l'affichage : `${d/#$HOME/$CLAUDEOS_TILDE}`. La forme
# `${d/#$HOME/\~}` rend `\~/…` sous le bash 3.2 d'Apple — constat K1 de l'audit de portabilité,
# corrigé le 2026-09-23 ; un `~` nu serait réexpansé en `$HOME` par bash 5. Par une variable,
# les deux rendent `~/…` : VÉRIFIÉ sous 3.2.57 et 5.3.
CLAUDEOS_TILDE='~'

# Queue du chemin du shim de hook — SOURCE UNIQUE. Elle était écrite deux fois, dans
# `claudeos-cloture.sh` et `install-poste.sh` : déménager le hook demandait d'éditer deux scripts,
# et celui qu'on oubliait aurait accepté un shim périmé sans rien dire.
CLAUDEOS_SHIM_TAIL='.claude/engine/hooks/pre-commit-alarmes.sh'

# `claudeos_require_remote` et sa variable `REMOTE_MATCH` SUPPRIMÉES le 2026-08-22, sur
# décision de l'utilisateur, après l'audit contradictoire. La fonction refusait d'opérer si
# l'origin de `$ROOT` ne correspondait pas. Deux motifs : elle n'avait plus d'appelant depuis
# la mort de `backup.sh`, et surtout elle ne connaissait qu'UN dépôt — le système — alors que
# la clôture en pousse deux. Un garde qui ne couvre que la moitié de ce qu'il prétend garder
# ment sur sa portée. L'URL du dépôt système est celle que git connaît
# (`git remote get-url origin`) : aucun fichier ne la recopie.

# claudeos_epoch_of_date — rend l'époque UNIX de minuit d'une date ISO (AAAA-MM-JJ) sur la sortie
# standard, ou RIEN et un code non nul si elle est illisible. Posé le 2026-09-12.
#
# POURQUOI. Trois lignes de `boot-check.sh` appelaient `date -d`, qui est une EXTENSION GNU : BSD
# répond `illegal option -- d`. Chacune portait un repli `2>/dev/null || echo 0`, donc l'erreur
# était avalée et la sonde rendait 0 — rappels échus jamais affichés, audit jamais signalé dû,
# journal jamais signalé périmé. Trois alarmes VERTES PAR CONSTRUCTION, sans un mot : exactement ce
# que le système dit refuser. Mesuré le 2026-09-12 sous PATH système : 0 là où la vérité était 42 j.
#
# DEUX BRANCHES, toutes deux EXACTES, et dans cet ordre. `date -d` d'abord : c'est le chemin du PC
# sous WSL et d'un Mac dont le PATH porte les coreutils GNU, sans coût de démarrage. `python3`
# ensuite, déjà dépendance dure du moteur (`etat.py`), et déterministe. La forme BSD `date -j -f`
# est ÉCARTÉE VOLONTAIREMENT : sur un format sans heure elle complète avec l'heure COURANTE, ce qui
# décale l'époque dans la journée et peut faire basculer un écart en jours d'une unité.
claudeos_epoch_of_date() {
    [ -n "${1:-}" ] || return 1
    date -d "$1" +%s 2>/dev/null && return 0
    python3 -c 'import datetime,sys;print(int(datetime.datetime.strptime(sys.argv[1],"%Y-%m-%d").timestamp()))' "$1" 2>/dev/null && return 0
    return 1
}

# claudeos_hash_file — empreinte d'un fichier, sur la sortie standard, sans le nom. Posé le 2026-09-12.
#
# POURQUOI. `md5sum` est un outil GNU : macOS livre `md5` (syntaxe différente) et `shasum`. Le
# contrôle 27ter de `weekly-check.sh` comparait des copies de scripts par `md5sum` — sur un Mac les
# deux côtés de la comparaison rendaient une chaîne VIDE, donc `"" = ""`, donc « copies identiques ».
# Un vert par construction sur le garde qui surveille la dérive entre `domaines/` et les dépôts de travail.
#
# L'ALGORITHME IMPORTE PEU, LA CONSTANCE OUI : dans une même exécution le premier outil disponible
# gagne partout, donc les empreintes restent comparables entre elles. On ne les conserve jamais.
claudeos_hash_file() {
    [ -f "${1:-}" ] || return 1
    if command -v md5sum >/dev/null 2>&1; then md5sum "$1" | cut -d" " -f1; return 0; fi
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d" " -f1; return 0; fi
    if command -v md5    >/dev/null 2>&1; then md5 -q "$1"; return 0; fi
    return 1
}

# claudeos_lock CONTEXTE : verrou exclusif non-bloquant contre l'exécution
# concurrente (deux onglets qui clôturent en même temps sur un poste). Le hook SessionEnd,
# second scénario d'origine, est retiré le 2026-08-22 ; le premier suffit à garder le verrou.
# fd 9 relâché à la mort du process → pas de verrou zombie. Sans flock ou si le
# verrou ne peut être créé, dégrade en no-op bruyant plutôt que de bloquer.
claudeos_lock() {
    local ctx="$1" lockfile="$HOME/.claude/.claudeos.lock" _flock=""
    # REPLI HOMEBREW, posé le 2026-09-22. `flock` n'existe pas dans macOS ; il vient de
    # `util-linux`, que Homebrew installe KEG-ONLY — donc hors du PATH, et `command -v` ne le
    # voyait pas même une fois le paquet posé. Ne PAS corriger en mettant `util-linux` dans le
    # PATH : il livre aussi `kill`, `nice`, `more`, qui masqueraient ceux du système ; c'est la
    # raison même du keg-only. Les chemins ci-dessous sont des CANDIDATS testés exécutables,
    # jamais des promesses : Apple Silicon puis Intel. Sans aucun, le no-op bruyant d'origine.
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

# --- Motifs de détection de secret — SOURCE UNIQUE du moteur vivant.
# Un seul consommateur désormais : le hook `pre-commit-alarmes.sh`, au goulot du
# commit des deux dépôts. Deux copies à deux âges divergent, et c'est alors le plus
# silencieux des deux qui devient muet sans que rien ne le dise.
#
# FORMES — préfixes imposés par les éditeurs (AWS, GitHub, GitLab, Google, Slack, Anthropic, clé PEM).
# Tous ont une casse EXACTE, donc à comparer SANS l'option d'insensibilité : comparer sans la
# casse ne rattrape aucun secret réel et fait sonner n'importe quel bloc base64 (sur quelques
# centaines de kilo-octets, 'akia' suivi de seize caractères alphanumériques sort par hasard —
# ce qui a bloqué la sauvegarde du 2026-07-27 sur des images intégrées).
CLAUDEOS_SECRET_RE_FORMES='(-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,}|glpat-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-ant-[A-Za-z0-9_-]{20,})'
# MOTS — un mot-clé suivi d'une valeur. Ici la casse varie selon qui écrit le fichier, donc
# l'insensibilité est utile et se garde.
CLAUDEOS_SECRET_RE_MOTS='(api[_-]?key|secret|password|passwd|token)[^[:alnum:]]{1,4}[A-Za-z0-9/+_.=-]{20,}'
# NOMS — le nom du fichier annonce un secret, même si aucune ligne ne matche les deux
# précédents : une clé nue, seule dans son fichier, n'a ni mot-clé ni forme connue.
CLAUDEOS_SECRET_NAME_RE='(secret|passw(or)?d|credential|api[._-]?key|[._-]token)'
# DONNÉES TEXTE — un export ou un journal partirait sans un mot. Remonté ici du hook le 2026-08-24 :
# la clôture pose désormais la MÊME question avant de committer, pour mettre ces fichiers de
# côté au lieu de laisser l'alarme bloquer la sauvegarde. Deux lecteurs, donc un seul motif.
# Pas de liste blanche : elle serait muette, et c'est ce qui a fait entrer un binaire en 2026-08.
CLAUDEOS_DATA_RE='\.(csv|tsv|txt|json|jsonl|xml|eml|msg)$'

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
#     avec les barres échappées ferait sinon passer ses chemins.
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
    # conclurait à l'échec sur une sortie parfaitement correcte.
    return 0
}

# Le régime git du poste — `claudeos_regime`, `claudeos_racines`, `claudeos_suivis` : code propre
# au template, tenu à part pour que les fichiers reportés de la source changent le moins possible.
# shellcheck source=lib_regime.sh
. "$SELF/lib_regime.sh"

# --- Plafonds de taille et cliquet de croissance — SOURCE UNIQUE ---------------
# Posés le 2026-09-07.
# Lus par `hooks/pre-commit-alarmes.sh`, contrôles 8, 9 et 10. Un seul endroit :
# `DESIGN.md` § « Plafonds » renvoie ICI et ne porte aucun chiffre, et l'en-tête d'un
# fichier borné porte un renvoi, jamais une valeur — deux copies à deux âges se
# contredisent, et c'est arrivé (un plafond du règlement affirmé par la fiche d'audit
# alors que le règlement l'avait abandonné).
#
# UNITÉ : caractères (comptés par `python3`, plus par `wc -m` depuis le 2026-09-22), pas octets — les accents comptent double en UTF-8 et
# un plafond en octets punirait le français.
CLAUDEOS_PLAFOND_MEMORY=8000
# ETAT.md — POSÉ le 2026-09-09 à la passe de ménage, sur arbitrage de l'utilisateur. Motif :
# après la bascule de la phase 3, les MEMORY.md et HANDOFF.md du parc sont GELÉS et les `ETAT.md`
# sont les seuls fichiers d'état vivants — or aucun plafond ne les connaissait. Mesuré ce jour-là :
# le contrôle du parc ne mesurait plus qu'UN fichier sur 52. La borne du système n'était donc plus
# gardée par rien, et `~/.claude/ETAT.md` était à 40 032 caractères, lu à chaque démarrage.
# VALEUR : 25 000, dérivée du parc et non inventée — un `ETAT.md` porte ce que portaient la mémoire
# (8 000) et la reprise (12 000) du même niveau, plus les décisions en vigueur. Les quatre plus gros
# au 2026-09-09 : système 40 032, puis trois niveaux de projet à 22 189, 21 978 et 18 374.
# CE QU'IL FAUT SAVOIR AVANT DE LE VOIR CRIER : un `ETAT.md` est une PROJECTION, il NE S'ALLÈGE PAS
# à la main — le crochet refuse l'édition (code 23). Il maigrit de deux façons : en SOLDANT des dus
# et en FERMANT des chantiers, et en écrivant PLUS COURT.
#
# DEUX PHRASES DE CE COMMENTAIRE ÉTAIENT FAUSSES, retirées le 2026-09-10 après mesure. Elles sont
# nommées ici parce qu'elles ont orienté un geste vers la mauvaise cible, et que le savoir seul
# empêche de les réécrire.
#   1. « Un dépassement est un signal de dette ouverte. » NON — c'est un signal de VERBOSITÉ. Mesuré
#      sur les deux fichiers au-dessus : un cinquième à un tiers des articles portait les deux tiers
#      du poids. Solder des dus ne guérit pas ça, et le geste C4 du plan de correction du 2026-09-10
#      l'a payé — il a soldé six dus pour 1 885 caractères sur un dépassement de 25 000.
#      LE GESTE QUI LE REMESURE, jamais un chiffre recopié : parcourir `journal/*.jsonl` du niveau,
#      ne garder que ce que `projette` retient (decision pose/remplace, du ouvre/remplace, pointeur
#      ajoute, etat avance non remplacé), et compter les textes au-delà de leur borne.
#   2. « Lu à chaque démarrage. » NON — `boot-check.sh` n'en extrait que QUATRE lignes d'« État
#      courant », TRONQUÉES À 120 CARACTÈRES, plus deux lignes de comptes : environ 600 caractères
#      quelle que soit la taille du fichier. Le coût réel est ailleurs, et il est vrai : le règlement
#      §3 fait charger le fichier ENTIER à chaque reprise de niveau.
#      Conséquence que ça révèle : les lignes d'« État courant » les plus longues étaient écrites
#      pour un lecteur qui en lit 120.
#
# LE LEVIER N'EST DONC PAS ICI, il est à l'écriture : `TEXTE_MAX_PROJETE` dans `engine/etat.py`
# borne par type le texte des quatre opérations projetées, et refuse à l'`add`. Le récit, la méthode
# et la preuve vont en `--type observation`, qui ne pèse RIEN sur la projection. Ce plafond-ci reste
# le témoin du RÉSULTAT ; il ne dit pas où couper, et ne doit plus être lu comme s'il le disait.
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
# SOURCE UNIQUE, appelée par `hooks/pre-commit-alarmes.sh` (son contrôle 8) ET par
# `plafonds-parc.sh`. *(Elle citait « le contrôle 29 de weekly-check.sh » : ce contrôle est RETIRÉ
# depuis le 2026-09-08, seul `29bis` subsiste et il regarde autre chose — corrigé le 2026-09-10.)* Deux implantations du même calcul auraient divergé au premier correctif
# porté sur une seule — c'est exactement ce qui est arrivé au motif de secret avant sa remontée ici.
# CHEMINS HORS RÉGIME — ce ne sont pas des fichiers d'état de niveau, malgré leur nom.
# `.claude/memory/MEMORY.md` est l'INDEX de la mémoire automatique, écrit et lu par l'outil, qui lui
# impose déjà ses propres bornes (200 lignes ou 25 Ko, documentation de l'éditeur, vérifiée le
# 2026-09-07). Deux régimes sur un même fichier, c'est deux vérités concurrentes — et le nôtre
# serait le plus serré, donc celui qui crie pour rien. FAUX POSITIF CONSTATÉ le 2026-09-07 sur
# le commit `ed7b65d`, corrigé dans la même séance : un signal qu'on sait devoir ignorer apprend
# à ignorer la catégorie entière, y compris les vrais.
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

# CHEMINS NÉS AU PREMIER BESOIN — copie du template, A6, 2026-10-01. Les compétences livrées les
# citent, et une installation neuve ne les porte pas encore : le contrôle hebdomadaire 27 les compte à
# part au lieu de les crier. Trois n'existent jamais dans un régime donné : `RTK.md` sans proxy, les
# empreintes de clôture en régime GitHub, l'identité git sans git. Un chemin qui finit par `/` vaut pour
# tout ce qu'il contient. Mesuré sur trois installations d'essai.
CLAUDEOS_CHEMINS_AU_BESOIN='~/.claude.json ~/.claude/audits/ ~/.claude/memory ~/.claude/memory/ ~/.claude/plans/ ~/.claude/TODO.md ~/.claude/domaines/ ~/.claude/secrets-shared/ ~/.claude/reglages/CRENEAUX ~/.claude/RTK.md ~/.claude/.claudeos/empreintes/MANIFESTE.json ~/.claude/reglages/IDENTITE_GIT'

# CLIQUET — trois valeurs figées à leur mesure du 2026-09-07, dépôt système seulement.
# ON NE REMONTE JAMAIS : pour ajouter, il faut retirer. Motif mesuré : le corpus des
# compétences est passé de 296 430 à 384 909 octets en quatorze jours (+29 %) APRÈS un
# chantier de décomplexification déclaré terminé le 2026-08-22. Une cure sans cliquet
# sur l'état atteint se repaie.
# Toute baisse se réécrit ici avec sa date ; `git log -p` sur ces lignes montre
# toute remontée, et le contrôle hebdomadaire la lit.
CLAUDEOS_CLIQUET_REGLEMENT=7000        # les fragments de noyau/regles/ retenus par le jeu MAX, octets,
                                       # mesurés à l'atelier (mesure-personnalisation.py taille). Il ne
                                       # mesure plus le CLAUDE.md, qui est à l'installateur (A6, 2026-10-01).
# LE CLIQUET SUR LA SOMME DES CORPS EST RETIRÉ LE 2026-09-22, à l'audit, sur arbitrage de
# l'utilisateur. Il a été mesuré incohérent : il plafonnait 378 244 octets de FICHIERS ENTIERS,
# frontmatter compris — et non « 377 652 octets de corps », chiffre écrit ici le 2026-09-22 qui ne
# correspondait à AUCUNE mesure et nommait la mauvaise grandeur, relevé à la passe du soir. Dont
# 9777 seulement — 2,6 % — sont payés à chaque session. Un corps ne coûte rien tant que sa
# fiche ne se charge pas, et il s'en charge trois ou quatre par séance. Ce qui est réellement
# payé à chaque tour est la liste des DESCRIPTIONS, que rien ne plafonnait.
# SECOND DÉFAUT, et c'est lui qui a emporté la décision : une SOMME globale laisse financer
# une fiche par le dégraissage d'une AUTRE, sans rapport — mesuré le jour même, quatre règles
# financées sur deux compétences personnelles. Ça passe le contrôle et ça ne protège
# rien. La dérive que le sondage d'audit traque est un CORPS QUI GROSSIT : elle se plafonne
# par fiche, jamais en somme.
# CE QUI EST ASSUMÉ : la somme totale n'est plus bornée par rien. Le pari « à réfuter si le
# corpus enfle sans qu'aucune fiche ne dépasse » a été RÉFUTÉ à l'audit du 2026-09-22 au soir
# (+5 394 octets en 9 h), puis ASSUMÉ par l'utilisateur le même soir : la croissance était
# décidée, pas une dérive. L'audit suit la TENDANCE, rien ne la borne.
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
CLAUDEOS_CLIQUET_CONTROLES=20          # contrôles émis par engine/weekly-check.sh — BAISSÉ de 21 à 20
                                       # le 2026-09-22 : contrôle 32 retiré, vert par construction une fois
                                       # les HANDOFF supprimés (toutes les racines portent ETAT.md). Avant :
                                       # BAISSÉ de 23 à 21
                                       # le 2026-09-08 (geste 2.7) : les contrôles 5, 21, 24 et 29 sont
                                       # retirés, chacun remplacé (décision D-G). Un cliquet ne remonte
                                       # jamais, et une baisse se réécrit ICI avec sa date.
CLAUDEOS_CLIQUET_PERSONNALISATION=75   # pourcent, cliquet INVERSE posé le 2026-10-01 sur la mesure
                                       # de l'A4 : la part des règles des fragments de noyau/regles/
                                       # retenus par le jeu MAX dont la présence ou la forme dépend
                                       # d'une réponse, hors les trois interdits du socle. Il ne BAISSE
                                       # jamais, plancher 50 (d-mesure-perso) ; une montée se réécrit
                                       # ici, datée. Propriété du template, comme le compte de
                                       # contrôles. Mesure : python3 engine/mesure-personnalisation.py ratio
# CLIQUETS DU POSTE — descriptions, index de mémoire et fiche : les valeurs ci-dessus sont celles du
# template, et elles sont tes BUDGETS DE DÉPART. L'installation n'en remesure aucun (A6, 2026-10-01) :
# mesurés sur un poste neuf, les descriptions n'auraient laissé aucune place à ta première compétence,
# que rien de tien n'aurait pu financer, et l'index, encore absent, se serait figé à rien.
# `reglages/CLIQUETS`, une ligne `CLE=valeur`, fixe ton propre budget et l'emporte alors. La leçon du
# cliquet tient — pour ajouter, retirer d'abord —, mais le budget est le tien : il se baisse après un
# ménage, et se relève aussi, si tu le décides. Le règlement, le compte de contrôles et la
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
# ⚠ Le plan du 2026-09-05 annonçait 30 contrôles. FAUX, mesuré : le motif
# `grep -c '^echo "\[selftest\] [0-9]'` rend 27, et les numéros émis vont de 2 à 48 avec
# des bis/ter et des trous — le compte n'est pas le plus grand numéro.
