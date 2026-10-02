#!/usr/bin/env bash
# =============================================================================
# pre-commit-alarmes.sh — les alarmes au goulot unique du commit.
# Écrit le 2026-08-22, étape 3.2 du plan de décomplexification. C'est R5 du
# mandat libre, réalisé au bon endroit : les quatre motifs restent, une seule
# implantation les porte, au lieu des trois d'aujourd'hui (backup.sh:281-311,
# l'ancien script de poussée, l'ancien autotest). Les trois sont mortes depuis.
#
# EMPLACEMENT — le shim `.git/hooks/pre-commit` de chaque dépôt pointe sur CE fichier ;
# `install-poste.sh` le pose, en testant le chemin complet, pas le seul nom. SANS GIT (`GIT=aucun`),
# il n'y a ni dépôt ni shim : la clôture l'appelle elle-même, `--fichiers <liste>` (voir plus bas).
#
# CODES RETOUR : 12 binaire · 13 nom de secret · 14 contenu de secret · 15 donnée ·
#                16 syntaxe bash · 17 JSON invalide · 18 réceptacle _IGNORE en file ·
#                20 cliquet de croissance · 25 liste noire d'un dépôt de travail absente ou divergente ·
#                26 copie d'un relecteur de domaine divergente de sa source ·
#                27 nom de régime mort dans un texte vivant · 28 chemin propre à un poste.
# CODES RÉSERVÉS, PAS ENCORE ÉMIS : 19 plafond de taille, 21 forme des fichiers d'état.
# Les deux contrôles existent et AVERTISSENT ; ils passeront en refus à la fin du palier 1
# du plan de consolidation, quand les fichiers hors règle auront été versés. Le régime et
# son motif sont écrits en tête du bloc des contrôles 8 à 10, plus bas dans ce fichier.
# Les trois derniers sont arrivés le 2026-08-22 (étape 4.3), transplantés de l'autotest :
# ils regardent CE QUI PART, donc leur place est ici. Ils n'ont PAS de levier — un script
# cassé, un JSON illisible ou un réceptacle confidentiel suivi ne sont pas des arbitrages.
# PIÈGE MESURÉ le 2026-08-22 : ces codes ne sont observables qu'en appelant CE
# script directement. À travers `git commit`, git rend TOUJOURS 1 quand un hook
# échoue — il écrase le code du hook. Le plan prescrivait « six codes retour
# attendus » via un commit : c'est inobservable ainsi. Exercer le script, pas le
# commit. Exercé le 2026-08-22 sur sept cas, tous conformes : 12, 13, 14, 15,
# 0 (levier motivé), 0 (texte anodin), et 15 avec un levier VIDE — un levier sans
# motif ne lève rien, c'est voulu. RÉEXERCÉ après le déménagement du 2026-08-22
# sur huit cas : les sept ci-dessus, plus le refus 13 « alarme muette » obtenu en
# rendant les deux config.sh introuvables. Les trois contrôles ajoutés le même jour
# sont exercés sur six cas de plus : 16, 17, 18, et leurs trois négatifs.
# LEVIERS, granulaires et MOTIVÉS (une valeur vide ne lève rien) :
#   FORCE_BINARY="motif"  FORCE_SECRET_NAME="motif"
#   FORCE_SECRET="motif"  FORCE_DATA="motif"  FORCE_CLIQUET="motif"
#   FORCE_JOURNAL="motif" FORCE_GELE="motif"  FORCE_NOMS_MORTS="motif"  FORCE_CHEMIN_POSTE="motif"
# Chaque levée est tracée, datée, dans .git/ALARMES_FORCEES.log du dépôt visé.
# LIMITE CONNUE : le plan voulait la trace DANS le message de commit ; cela
# demanderait un second hook (prepare-commit-msg). Non fait, trace au journal.
# =============================================================================
set -uo pipefail

# --- SANS GIT : `--fichiers LISTE` — `d-regime-sans-git`, plan complet de templating, A3 ----------
# Sans dépôt, la clôture appelle ce crochet ELLE-MÊME, avec la liste des fichiers changés depuis la
# clôture précédente : une ligne `A|M|D<tab>chemin`, rendue par `regime.py changes`. La version « en
# file » est alors le disque, et la dernière clôture tient lieu de `HEAD` par ses empreintes. Les
# fonctions `_git_*` ci-dessous sont les SEULS endroits où les contrôles lisent git : en régime
# GitHub elles rendent mot pour mot ce que rendaient les commandes qu'elles remplacent, et chaque
# contrôle garde le code de la source. Les codes de ce script sont alors lus tels quels — git ne
# s'interpose plus pour les écraser en 1.
_LISTE=""
_REGIME_PY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/regime.py"
if [ "${1:-}" = "--fichiers" ]; then
    if [ -z "${2:-}" ] || [ ! -r "$2" ] || [ ! -r "$_REGIME_PY" ]; then
        echo "[alarmes] ⛔ REFUS : --fichiers attend une liste lisible (« ${2:-} ») et $_REGIME_PY." >&2
        exit 1
    fi
    _LISTE="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
    GIT_ROOT="$(python3 "$_REGIME_PY" racine "$PWD")" || {
        echo "[alarmes] ⛔ REFUS : $PWD n'est sous aucune racine, ni dépôt git ni .claudeos-racine." >&2
        exit 1; }
else
    GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
fi
cd "$GIT_ROOT" || exit 0

# Le statut d'un chemin dans la liste : `A`, `M` ou `D`, vide s'il n'y est pas.
_statut() { awk -F'\t' -v p="$1" '$2 == p { print $1; exit }' "$_LISTE"; }
# `git diff --cached --name-only --diff-filter=FILTRE [-z]`
_git_noms() {
    if [ -z "$_LISTE" ]; then git diff --cached --name-only --diff-filter="$@"; return; fi
    # Le NUL de `-z` par `tr` et non par `awk` : l'awk de BSD coupe une chaîne au premier octet nul.
    awk -F'\t' -v s="$1" '$1 != "" && index(s, $1) { print $2 }' "$_LISTE" \
        | if [ "${2:-}" = "-z" ]; then tr '\n' '\000'; else cat; fi
}
# `git diff --cached --numstat --diff-filter=A` — seule la colonne « - » des binaires compte.
_git_numstat_ajouts() {
    if [ -z "$_LISTE" ]; then git diff --cached --numstat --diff-filter=A; return; fi
    _git_noms A | python3 "$_REGIME_PY" binaires "$GIT_ROOT" | awk '{ printf "-\t-\t%s\n", $0 }'
}
# `git diff --cached -U0 --diff-filter=ACM [-- CHEMIN]` — sans git, les seules lignes `+` : celles
# que la dernière clôture ne portait pas. Un fichier NEUF est lu en bash, sans python : à la première
# clôture tout est neuf, et un appel par fichier coûterait des dizaines de secondes.
_git_diff_ajouts() {
    if [ -z "$_LISTE" ]; then
        if [ -n "${1:-}" ]; then git diff --cached -U0 --diff-filter=ACM -- "$1"
        else git diff --cached -U0 --diff-filter=ACM; fi
        return
    fi
    local f
    if [ -n "${1:-}" ]; then printf '%s\n' "$1"; else _git_noms ACM; fi | while IFS= read -r f; do
        [ -f "$f" ] || continue
        if [ "$(_statut "$f")" = A ]; then
            # binaire = un octet nul dans les 8 000 premiers, la règle de git : aucune ligne alors.
            # `LC_ALL=C` : sous une locale UTF-8, `tr` et `sed` de BSD refusent un octet invalide.
            [ "$(head -c 8000 "$f" | LC_ALL=C tr -d '\000' | wc -c)" = "$(head -c 8000 "$f" | wc -c)" ] \
                && LC_ALL=C sed 's/^/+/' "$f"
        else
            python3 "$_REGIME_PY" ajouts "$GIT_ROOT" "$f" | LC_ALL=C sed 's/^/+/'
        fi
    done
}
# `git show :CHEMIN` — la version en file ; sans git, le disque.
_git_montre() {
    if [ -z "$_LISTE" ]; then git show ":$1"; return; fi
    [ -f "$1" ] && cat "$1"
}
# `git show HEAD:CHEMIN` — SANS GIT, SA SEULE PREMIÈRE LIGNE, celle que la dernière clôture a gardée :
# à n'employer que là où seule la première ligne est lue. rc=1 quand le chemin n'existait pas à la
# référence, comme `git show` sur un fichier neuf.
_git_tete() {
    if [ -z "$_LISTE" ]; then git show "HEAD:$1"; return; fi
    [ "$(_statut "$1")" = A ] && return 1
    python3 "$_REGIME_PY" tete "$GIT_ROOT" "$1"
}
# `git ls-files MOTIF`
_git_suivis() {
    if [ -z "$_LISTE" ]; then git ls-files "$1"; return; fi
    python3 "$_REGIME_PY" suivis "$GIT_ROOT" "$1"
}

# --- Motifs : SOURCE UNIQUE, pas de recopie ---------------------------------
# config.sh les porte déjà (CLAUDEOS_SECRET_*). On le source plutôt que de les
# dupliquer — le doublon est exactement ce que cet audit existe pour retirer.
# Repli embarqué si config.sh disparaît (palier 4), et REFUS si aucun des deux :
# une alarme qui ne sait pas quoi chercher se tait, et une alarme muette est pire
# que pas d'alarme.
# Le moteur vivant, résolu depuis l'emplacement du hook, jamais en dur : deux postes
# aux dossiers personnels différents. Le repli sur l'archive est SUPPRIMÉ le 2026-08-22
# avec `~/.claudeos` lui-même, sur les deux postes (palier 4.7). Il n'y a plus de
# seconde source : si ce fichier manque, l'alarme refuse plus bas, elle ne se tait pas.
_CFG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/config.sh"
if [ -r "$_CFG" ]; then
    # shellcheck disable=SC1090
    source "$_CFG" 2>/dev/null || true
fi
: "${CLAUDEOS_SECRET_RE_FORMES:=}"
: "${CLAUDEOS_SECRET_RE_MOTS:=}"
: "${CLAUDEOS_SECRET_NAME_RE:=}"
if [ -z "$CLAUDEOS_SECRET_RE_FORMES" ] || [ -z "$CLAUDEOS_SECRET_RE_MOTS" ] || [ -z "$CLAUDEOS_SECRET_NAME_RE" ]; then
    echo "[alarmes] ⛔ REFUS : motifs de secrets introuvables (config.sh absent ou muet)." >&2
    echo "[alarmes] Une alarme sans motif est une alarme muette. Commit refusé." >&2
    exit 13
fi

# Extensions de donnée texte : un export, un journal ou une pièce jointe y partirait sans un mot.
# SOURCE UNIQUE : `config.sh` porte le motif depuis le 2026-08-24, parce que `claudeos-cloture.sh`
# le lit aussi. Le repli embarqué ne sert qu'à un poste dont le `config.sh` est en retard —
# il PRÉVIENT au lieu de se taire, sinon un motif divergent passerait inaperçu.
if [ -n "${CLAUDEOS_DATA_RE:-}" ]; then
    _DATA_RE="$CLAUDEOS_DATA_RE"
else
    _DATA_RE='\.(csv|tsv|txt|json|jsonl|xml|eml|msg)$'
    echo "[alarmes] ⚠ CLAUDEOS_DATA_RE absent de config.sh — repli embarqué employé. Ce poste est en retard : tire avant de committer." >&2
fi
# PAS DE WHITELIST ICI — retirée le 2026-08-22 sur objection de l'utilisateur, qui
# a raison. `backup.sh:258` en portait une (un dossier de projet personnel, décidée le
# 2026-07-27) et je l'avais recopiée sans la questionner. Deux défauts : c'est un
# motif de plus à maintenir, et surtout elle est MUETTE — un binaire y passait sans
# laisser de trace. Le levier `FORCE_BINARY="motif"` fait le même travail, à la même
# fréquence (une couverture par saison), et il écrit une ligne datée dans
# .git/ALARMES_FORCEES.log. Le régime du dépôt est la liste noire : ce qui ne doit
# pas être suivi se dit dans .gitignore, pas dans une exception d'alarme.

# Sans git, le journal des levées vit sous `.claudeos/`, à côté des empreintes : il n'y a pas de `.git/`.
if [ -n "$_LISTE" ]; then _TRACE="$GIT_ROOT/.claudeos/ALARMES_FORCEES.log"; mkdir -p "$GIT_ROOT/.claudeos"
else _TRACE="$GIT_ROOT/.git/ALARMES_FORCEES.log"; fi
_trace() { printf '%s\t%s\t%s\n' "$(date +%F' '%T)" "$1" "$2" >> "$_TRACE"; }
_leve()  { [ -n "${2:-}" ] && { echo "[alarmes] ⚠ $1 LEVÉE — motif : $2" >&2; _trace "$1" "$2"; return 0; }; return 1; }

FAIL=0

# --- 1. Binaire ajouté (code 12) --------------------------------------------
# L'alarme secret ne lit que le texte : elle est AVEUGLE au binaire. Un .pdf ou un .docx de
# client passerait par ce trou.
NEW_BIN="$(_git_numstat_ajouts | awk -F'\t' '$1=="-"&&$2=="-"{print $3}' || true)"
if [ -n "$NEW_BIN" ]; then
    if ! _leve "BINAIRE" "${FORCE_BINARY:-}"; then
        echo "[alarmes] ⛔ ALARME BINAIRE — nouveau(x) binaire(s) en file, contenu non scannable :" >&2
        echo "$NEW_BIN" | head -10 | sed 's/^/      /' >&2
        echo "[alarmes] Exclus-le (.gitignore) ou assume : FORCE_BINARY=\"motif\" git commit …" >&2
        FAIL=12
    fi
fi

# --- 2. Nom de fichier suspect (code 13) ------------------------------------
# EXCEPTION `secrets-shared/` — posée le 2026-09-01 sur arbitrage de l'utilisateur.
# DÉFAUT CORRIGÉ, mesuré et non déduit : le motif cherche « secret » dans le CHEMIN
# ENTIER, et le dossier `secrets-shared/` porte ce mot dans son propre nom. L'alarme
# mordait donc sur TOUT ce qu'on y rangeait — `secrets-shared/note_anodine.md` a été
# refusé au banc d'essai — pendant que son message d'aide, six lignes plus bas,
# prescrivait précisément d'y ranger. Le conseil était insuivable : constaté le
# 2026-08-31 sur une vraie clé à ranger, reproduit sur copie du garde le 2026-09-01.
# CE N'EST PAS LA LISTE BLANCHE RETIRÉE LE 2026-08-22 (voir le bloc plus haut). Celle-là
# était MUETTE — c'était l'objection, et elle tenait. Celle-ci TRACE : une ligne à l'écran
# et une ligne datée dans .git/ALARMES_FORCEES.log, par fichier. Elle ne lève QUE le nom :
# l'alarme de CONTENU (code 14) reste armée entière sur ce dossier, et c'est elle qui garde
# la valeur d'un secret. Le régime du dépôt n'est pas changé, un angle mort est fermé.
ALL_NAME="$(_git_noms A | grep -Ei -- "$CLAUDEOS_SECRET_NAME_RE" || true)"
DEPOT_NAME="$(printf '%s' "$ALL_NAME" | grep -E '(^|/)secrets-shared/' || true)"
BAD_NAME="$(printf '%s' "$ALL_NAME" | grep -Ev '(^|/)secrets-shared/' || true)"
if [ -n "$DEPOT_NAME" ]; then
    echo "[alarmes] ⚠ NOM DE SECRET — dossier désigné \`secrets-shared/\`, alarme de NOM levée (le CONTENU reste gardé) :" >&2
    echo "$DEPOT_NAME" | head -10 | sed 's/^/      /' >&2
    while IFS= read -r _d; do
        [ -n "$_d" ] && _trace "SECRET-NOM-DEPOT" "$_d"
    done <<< "$DEPOT_NAME"
fi
if [ -n "$BAD_NAME" ] && [ "$FAIL" -eq 0 ]; then
    if ! _leve "SECRET-NOM" "${FORCE_SECRET_NAME:-}"; then
        echo "[alarmes] ⛔ ALARME NOM DE SECRET — fichier(s) dont le NOM annonce un secret :" >&2
        echo "$BAD_NAME" | head -10 | sed 's/^/      /' >&2
        echo "[alarmes] Range-le dans ~/.claude/secrets-shared/ ou assume : FORCE_SECRET_NAME=\"motif\" git commit …" >&2
        FAIL=13
    fi
fi

# --- 3. Contenu de secret (code 14) -----------------------------------------
DIFF="$(_git_diff_ajouts 2>/dev/null | grep '^+' | grep -v '^+++' || true)"
HIT=""
# Les FORMES se comparent à la casse exacte, les MOTS sans elle : `config.sh` l'exige, et une forme
# comparée sans la casse fait sonner un bloc base64 (audit de la v3.0.0, une clôture refusée).
[ -n "$DIFF" ] && HIT="$( { printf '%s' "$DIFF" | grep -E -- "$CLAUDEOS_SECRET_RE_FORMES"
                            printf '%s' "$DIFF" | grep -Ei -- "$CLAUDEOS_SECRET_RE_MOTS"; } | head -3 || true)"
if [ -n "$HIT" ] && [ "$FAIL" -eq 0 ]; then
    if ! _leve "SECRET-CONTENU" "${FORCE_SECRET:-}"; then
        echo "[alarmes] ⛔ ALARME SECRET — une valeur de secret apparaît dans la file." >&2
        echo "[alarmes] Fichiers concernés (la VALEUR n'est pas affichée) :" >&2
        { _git_noms ACM -z | xargs -0 grep -lE -- "$CLAUDEOS_SECRET_RE_FORMES" 2>/dev/null
          _git_noms ACM -z | xargs -0 grep -lEi -- "$CLAUDEOS_SECRET_RE_MOTS" 2>/dev/null; } \
            | sort -u | head -5 | sed 's/^/      /' >&2
        echo "[alarmes] Un secret exposé est COMPROMIS : régénère-le et consigne-le dans SECURITY_DEBT.md." >&2
        FAIL=14
    fi
fi

# --- 4. Donnée client (code 15) ---------------------------------------------
# EXEMPTION DU JOURNAL D'ÉVÉNEMENTS, sur arbitrage de l'utilisateur du 2026-09-08.
# Le motif : `CLAUDEOS_DATA_RE` nomme `.jsonl`, et le journal EST un `.jsonl` dont un exemplaire
# NEUF naît chaque mois — donc, sans cette exemption, une levée `FORCE_DATA` par mois, douze par
# an, sur la même alarme. Forcer une alarme à date fixe apprend à ignorer sa catégorie entière,
# et ce dépôt l'a déjà payé trois fois.
# ELLE EST ANCRÉE SUR LE CHEMIN, pas sur l'extension : `journal/AAAA-MM.jsonl` et rien d'autre.
# Un `.jsonl` posé ailleurs — ou nommé autrement dans `journal/` — reste refusé.
# CE QUI GARDE LE FICHIER MALGRÉ L'EXEMPTION, et c'est pour ça qu'elle est acceptable : les
# contrôles 13 et 14 (nom de secret, contenu de secret) le balaient toujours, et la règle
# d'anonymat du journal est celle de la compétence `reprise`.
_JOURNAL_RE='(^|/)journal/[0-9]{4}-[0-9]{2}\.jsonl$'
# EXEMPTION DE LA CONFIGURATION DU HARNAIS, sur arbitrage de l'utilisateur du 2026-09-09, écrite le
# 2026-09-10. Même forme et même motif que l'exemption du journal ci-dessus : `CLAUDEOS_DATA_RE`
# nomme `.json`, et `settings.json` EST un `.json` — mais c'est la configuration du harnais, pas une
# donnée client. Sans l'exemption, toute création de ce fichier dans un dépôt neuf lève `FORCE_DATA`
# sur une alarme qui ne dit rien, et une alarme forcée par routine apprend à ignorer sa catégorie.
# ELLE EST ANCRÉE SUR LE CHEMIN, pas sur l'extension, ET SUR LES DEUX FORMES QUE `git` REND
# RÉELLEMENT — c'est le piège de ce motif, mesuré avant de l'écrire :
#   · `settings.json` À LA RACINE, parce que le dépôt `~/.claude` A POUR RACINE `.claude` ;
#   · `.claude/settings.json` À TOUTE PROFONDEUR, la forme des quatre dépôts clients.
# Un motif qui ne dirait que `.claude/settings.json` — la lettre du du `u-controle-15-config-chemin`
# — RATERAIT LE DÉPÔT `~/.claude`, celui où l'écart a été trouvé. Et l'ancrage racine reste étroit :
# un `settings.json` posé en sous-dossier quelconque (`docs/`, `app/`) reste refusé.
# PÉRIMÈTRE VOLONTAIREMENT ÉTROIT : `settings.local.json` N'EST PAS exempté (2026-09-09). Son motif
# d'origine — « hors dépôt par nature » — est faux : un dépôt peut en suivre un. Le périmètre tient
# quand même, pour l'autre raison : ce fichier porte les permissions locales d'un poste et n'a rien
# à faire en zone partagée, donc l'alarme qui se lève dessus DIT quelque chose.
# CE QUI GARDE LE FICHIER MALGRÉ L'EXEMPTION, et c'est pour ça qu'elle est acceptable : les
# contrôles 13 et 14 (nom de secret, contenu de secret) le balaient toujours, et le contrôle 17
# refuse un JSON invalide.
_CONFIG_RE='(^settings\.json$|(^|/)\.claude/settings\.json$)'
# EXEMPTION DE LA CONFIGURATION DU TEMPLATE : trois `.json` livrés — le fragment de réglages, les
# réglages de la session d'installation, les astuces du spinner —, sans aucune donnée. ANCRÉE sur
# `gabarits/` et `installateur/` à la racine de `~/.claude`, à un seul niveau, et DANS CE DÉPÔT
# SEUL : le crochet tourne aussi dans les dépôts de travail, où un `gabarits/x.json` est une donnée
# comme une autre. Un `.json` posé ailleurs reste refusé. Les contrôles 13 et 14 les balaient toujours.
_TEMPLATE_RE='^(gabarits|installateur)/[^/]+\.json$'
NEW_DATA="$(_git_noms A | grep -Ei -- "$_DATA_RE" | grep -v '/extracted/' | grep -vE -- "$_JOURNAL_RE" | grep -vE -- "$_CONFIG_RE" || true)"
if [ "$GIT_ROOT" -ef "$HOME/.claude" ]; then
    NEW_DATA="$(printf '%s\n' "$NEW_DATA" | grep -vE -- "$_TEMPLATE_RE" || true)"
fi
if [ -n "$NEW_DATA" ] && [ "$FAIL" -eq 0 ]; then
    if ! _leve "DONNEE" "${FORCE_DATA:-}"; then
        echo "[alarmes] ⛔ ALARME DONNÉE — fichier(s) de données texte ajouté(s) :" >&2
        echo "$NEW_DATA" | head -10 | sed 's/^/      /' >&2
        echo "[alarmes] Un fichier de données sortirait du poste sans un mot : range-le en _IGNORE/, ou assume :" >&2
        echo "[alarmes]   FORCE_DATA=\"motif\" git commit …" >&2
        FAIL=15
    fi
fi

# --- 5. Syntaxe des scripts en file (code 16) --------------------------------
# Transplanté du contrôle 1 de l'autotest le 2026-08-22 (étape 4.3). L'autotest le passait sur
# TOUS les scripts avant chaque sauvegarde ; ici on ne regarde que ceux qui sont en file, ce qui
# le rend quasi gratuit et le déclenche au bon moment — un script cassé committé est un script
# cassé qui part sur l'autre poste. BLOQUE : un moteur qui ne s'analyse pas est une plomberie
# corrompue, pas un défaut de contenu.
BAD_SH=""
while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    [ -f "$_f" ] || continue
    bash -n "$_f" 2>/dev/null || BAD_SH="$BAD_SH  $_f"$'\n'
done < <(_git_noms ACM | grep -E '\.sh$' || true)
if [ -n "$BAD_SH" ] && [ "$FAIL" -eq 0 ]; then
    echo "[alarmes] ⛔ SYNTAXE — script(s) en file que bash refuse d'analyser :" >&2
    printf '%s' "$BAD_SH" >&2
    echo "[alarmes] Corrige la syntaxe : un script cassé committé part cassé sur l'autre poste." >&2
    FAIL=16
fi

# --- 6. JSON en file (code 17) -----------------------------------------------
# Transplanté du contrôle 4. Un `settings.json` invalide désarme les hooks EN SILENCE —
# l'outil le charge, échoue, et continue sans. BLOQUE, pour la même raison.
BAD_JSON=""
while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    [ -f "$_f" ] || continue
    python3 -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8"))' "$_f" 2>/dev/null \
        || BAD_JSON="$BAD_JSON  $_f"$'\n'
done < <(_git_noms ACM | grep -E '\.json$' || true)
if [ -n "$BAD_JSON" ] && [ "$FAIL" -eq 0 ]; then
    echo "[alarmes] ⛔ JSON INVALIDE — fichier(s) en file que python ne sait pas relire :" >&2
    printf '%s' "$BAD_JSON" >&2
    echo "[alarmes] Un settings.json invalide désarme les hooks en silence." >&2
    FAIL=17
fi

# --- 7. Réceptacle confidentiel suivi (code 18) ------------------------------
# Un `_IGNORE/` est le réceptacle des documents client : il est LOCAL par définition, hors
# dépôt. S'il arrive dans la file, c'est que le `.gitignore` a été contourné ou perdu — et le
# contenu qu'il protège est précisément celui qu'on ne veut pas voir partir. BLOQUE, sans
# levier : ce n'est pas un arbitrage, c'est une erreur de rangement ou de configuration.
IGN="$(_git_noms ACM | grep -E '(^|/)_IGNORE/' || true)"
if [ -n "$IGN" ] && [ "$FAIL" -eq 0 ]; then
    echo "[alarmes] ⛔ RÉCEPTACLE CONFIDENTIEL EN FILE — un _IGNORE/ ne doit JAMAIS être suivi :" >&2
    echo "$IGN" | head -10 | sed 's/^/      /' >&2
    echo "[alarmes] Vérifie que .gitignore porte bien « _IGNORE/ », puis : git rm -r --cached <chemin>" >&2
    FAIL=18
fi


# =============================================================================
# CONTRÔLES 8, 9 et 10 — posés le 2026-09-07.
#
# RÉGIME, arbitré par l'utilisateur le 2026-09-07 CONTRE la lettre du plan, qui les
# voulait tous les trois bloquants. La fiche `controles-et-alarmes` § « Ce qui bloque
# et ce qui avertit » dit qu'un plafond de RANGEMENT avertit, parce que bloquer dessus
# a déjà fait perdre deux journées de travail à ce système. Mesuré le 2026-09-07 avant
# d'écrire : 6 fichiers de reprise sur 22 et 8 MEMORY.md sur 30 dépassaient déjà, et 11 fichiers
# de reprise sur 22 étaient hors forme — un régime bloquant refusait donc 14 fichiers dès la première
# minute, la clôture du jour comprise.
#   · 8  PLAFOND  → AVERTIT. Passe en refus (code 19) à la fin du palier 1, quand les
#                   fichiers seront versés. Le code est réservé, pas encore émis.
#   · 9  CLIQUET  → BLOQUE (code 20), levier `FORCE_CLIQUET="motif"`. Il ne mesure pas
#                   le rangement mais la CROISSANCE, rien ne le dépasse aujourd'hui,
#                   donc son coût du premier jour est nul. C'est le vrai invariant.
#   · 10 FORME    → AVERTIT. Même sort que le 8.
#
# UNITÉ : caractères. `LC_ALL` est forcé pour que le compte ne dépende pas de
# l'environnement dans lequel git lance le hook — mesuré le 2026-09-07 : `wc -m` rend
# 43 784 pour 45 475 octets sur un fichier d'état de l'époque, l'écart étant les accents.
# =============================================================================

# Contenu de la version EN FILE, avec repli sur le disque quand le fichier n'est pas
# indexé. Sépare « je n'ai pas pu regarder » de « il n'y a rien » : sans contenu, on
# ne conclut pas — la fonction rend 1 et l'appelant saute le fichier en le disant.
_contenu() {
    _git_montre "$1" 2>/dev/null && return 0
    [ -f "$1" ] && { cat "$1"; return 0; }
    return 1
}

# Le calcul du plafond vit dans `config.sh` (`claudeos_plafond_de`), lu par ce crochet ET par le
# contrôle 29 de `weekly-check.sh`. Repli si la fonction manque : le contrôle le DIT et se tait,
# il ne devine pas un plafond — une borne inventée est pire qu'une borne absente.
# CLÉ QUALIFIÉE PAR DÉPÔT depuis le 2026-09-08 (geste 1.15) : `git diff --cached` rend un chemin
# relatif à la racine du dépôt, et cinq dépôts portent un `MEMORY.md` à leur racine depuis la
# bascule. Sans le préfixe, la mémoire de `<DÉPÔT_B>` héritait de la borne de `~/.claude`.
# Le préfixe est le NOM DU DOSSIER, pas le chemin absolu : les deux postes diffèrent, le nom non.
if ! declare -F claudeos_plafond_de >/dev/null 2>&1; then
    echo "[alarmes] ⚠ PLAFOND — claudeos_plafond_de absente de config.sh : contrôle 8 NON JOUÉ (ce poste est en retard, tire avant de committer)." >&2
    _plafond_de() { return 1; }
else
    _plafond_de() { claudeos_plafond_de "$(basename "$GIT_ROOT")/$1"; }
fi

ETATS="$(_git_noms ACM | grep -E '(^|/)(ETAT|MEMORY)\.md$' || true)"

# --- 8. Plafond de taille des fichiers d'état (code 19 réservé) — AVERTIT -----
if [ -n "$ETATS" ]; then
    _GROS=""
    while IFS= read -r _f; do
        [ -n "$_f" ] || continue
        _p="$(_plafond_de "$_f")" || continue
        # Compté DIRECTEMENT depuis la source : passer par une variable perd le saut de
        # ligne final, donc sous-comptait d'un caractère de façon systématique (mesuré).
        # Compté par python3 depuis le 2026-09-22 : même valeur que `wc -m`, sans dépendre
        # de la locale ni de quel `wc` le PATH résout dans un hook. Voir plafonds-parc.sh.
        _n="$(_contenu "$_f" | python3 -c "import sys;print(len(sys.stdin.buffer.read().decode('utf-8','surrogateescape')))")" || { echo "[alarmes] ⚠ PLAFOND — $_f illisible en file ET sur le disque : NON MESURÉ, pas « conforme »." >&2; continue; }
        [ "$_n" -gt "$_p" ] && _GROS="$_GROS      $_n car (plafond $_p) — $_f"$'\n'
    done <<< "$ETATS"
    if [ -n "$_GROS" ]; then
        echo "[alarmes] ⚠ PLAFOND DÉPASSÉ — fichier(s) d'état au-dessus de leur borne :" >&2
        printf '%s' "$_GROS" >&2
        echo "[alarmes] AVERTISSEMENT SEULEMENT — le commit passe. Verse le contenu durable." >&2
        echo "[alarmes] Plafonds et exceptions : engine/config.sh, CLAUDEOS_PLAFOND_*." >&2
    fi
fi

# --- 9. Cliquet de croissance (code 20) — BLOQUE ------------------------------
# Dépôt SYSTÈME seulement : les trois valeurs mesurent des objets qui n'existent que là.
# La racine du système est résolue depuis l'emplacement de CE fichier, jamais en dur —
# deux postes aux dossiers personnels différents.
# `pwd -P` ET NON `pwd` : `~/.claude` peut être un LIEN vers un autre dossier.
# `git rev-parse --show-toplevel` rend le chemin PHYSIQUE, `pwd` sans -P rend le chemin LOGIQUE :
# les deux ne pouvaient plus etre egaux, et CE BLOC NE S EXECUTAIT PLUS DU TOUT — le cliquet de
# croissance etait muet depuis quatre jours, sans un mot. Mesure et correction le 2026-09-16.
# Les deux cotes sont resolus, pour rester juste sur un poste sans lien comme avec.
_SYS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd -P)"
_GIT_ROOT_P="$(cd "$GIT_ROOT" 2>/dev/null && pwd -P)"
if [ -n "$_SYS_ROOT" ] && [ "$_GIT_ROOT_P" = "$_SYS_ROOT" ] && [ "$FAIL" -eq 0 ]; then
    # Les trois valeurs viennent de `config.sh`, SOURCE UNIQUE, et de nulle part ailleurs.
    # Elles etaient recopiees ici en repli — 384909 et 27, contre 378244 et 21 au 2026-09-08 :
    # config.sh non source, le crochet laissait passer 6 665 octets de derive EN SILENCE.
    # Un repli chiffre redevient faux au premier changement, donc on REFUSE plutot que de le
    # recopier — meme forme que le refus des motifs de secrets plus haut. (Corrige le 2026-09-16.)
    for _v in CLAUDEOS_CLIQUET_REGLEMENT CLAUDEOS_CLIQUET_INDEX CLAUDEOS_CLIQUET_DESCRIPTIONS CLAUDEOS_CLIQUET_FICHE CLAUDEOS_CLIQUET_CONTROLES; do
        if [ -z "${!_v}" ]; then
            echo "[alarmes] ⛔ REFUS : $_v absent — config.sh non sourcé ou muet." >&2
            echo "[alarmes]    Le cliquet ne peut pas être mesuré ; il ne se devine pas." >&2
            FAIL=1
        fi
    done
    _CLIQ=""
    # a) Règlement racine — MESURE RETIRÉE DE LA COPIE le 2026-10-01 (A6, `u-cliquet-reglement-installateur`).
    #    Le `CLAUDE.md` est celui de l'installateur : son persona, ses domaines, ses règles. Le texte
    #    qui lui est propre n'a aucun cliquet du template (plan complet § 1.3) — Claude Code avertit
    #    lui-même au-delà de sa limite combinée —, et une borne posée sur un fichier neuf aurait figé
    #    « Mes règles » dès sa première ligne. `CLAUDEOS_CLIQUET_REGLEMENT` borne désormais les
    #    seuls fragments du jeu MAX, que l'atelier mesure (`mesure-personnalisation.py taille`).
    # a2) Index de la mémoire automatique, en octets — injecté à chaque session comme le règlement.
    #     Ajouté le 2026-09-22 sur arbitrage de l'utilisateur : il pesait plus que le règlement
    #     et n'avait ni cliquet ni monnaie de troc. Même mesure que (a).
    if _i="$(_contenu memory/MEMORY.md)"; then
        _in="$(printf '%s' "$_i" | wc -c | tr -d ' ')"
        [ "$_in" -gt "$CLAUDEOS_CLIQUET_INDEX" ] \
            && _CLIQ="$_CLIQ      index memory/MEMORY.md : $_in octets > ${CLAUDEOS_CLIQUET_INDEX} (cliquet)"$'\n'
    fi
    # b) Compétences — DEUX mesures, et la somme des corps n'en est plus une. Motif complet en
    #    tête du bloc des cliquets de `config.sh` : un corps ne coûte rien tant que sa fiche ne se
    #    charge pas, et une somme globale laisse financer une fiche par le dégraissage d'une autre.
    #    b1) somme des `description:` — LA SEULE PART PAYÉE À CHAQUE SESSION.
    #    b2) la plus grosse fiche — la dérive du corps se borne par fiche, jamais en somme.
    #    La description est lue dans le frontmatter, première ligne `description:` avant le `---`
    #    de fermeture. Une fiche sans frontmatter compte 0 et n'est PAS une erreur : elle ne se
    #    route pas, et le contrôle 40 du weekly-check est celui qui le dit.
    _sd=0; _sn=0; _smax=0; _smaxf=""
    while IFS= read -r _f; do
        [ -n "$_f" ] || continue
        _blob="$(_git_montre "$_f" 2>/dev/null)" || continue
        _sn=$((_sn + 1))
        _sc="$(printf '%s' "$_blob" | wc -c | tr -d ' ')"
        if [ "$_sc" -gt "$_smax" ]; then _smax="$_sc"; _smaxf="$_f"; fi
        _dl="$(printf '%s\n' "$_blob" | awk 'NR==1&&$0!="---"{exit} NR>1&&$0=="---"{exit} /^description:/{print;exit}')"
        _sd=$((_sd + $(printf '%s' "$_dl" | wc -c)))
    done < <(_git_suivis 'skills/*/SKILL.md')
    if [ "$_sn" -gt 0 ]; then
        [ "$_sd" -gt "$CLAUDEOS_CLIQUET_DESCRIPTIONS" ] \
            && _CLIQ="$_CLIQ      descriptions des compétences : $_sd octets sur $_sn fiches > ${CLAUDEOS_CLIQUET_DESCRIPTIONS} (cliquet)"$'\n'
        [ "$_smax" -gt "$CLAUDEOS_CLIQUET_FICHE" ] \
            && _CLIQ="$_CLIQ      fiche la plus grosse : $_smaxf, $_smax octets > ${CLAUDEOS_CLIQUET_FICHE} (cliquet par fiche)"$'\n'
    else
        echo "[alarmes] ⚠ CLIQUET — aucune fiche skills/*/SKILL.md en file : NON MESURÉ, pas « conforme »." >&2
    fi
    # c) Nombre de contrôles émis par le contrôle hebdomadaire.
    if _w="$(_contenu engine/weekly-check.sh)"; then
        _wn="$(printf '%s' "$_w" | grep -cE '^echo "\[selftest\] [0-9]')"
        [ "$_wn" -gt "$CLAUDEOS_CLIQUET_CONTROLES" ] \
            && _CLIQ="$_CLIQ      contrôles hebdomadaires : $_wn > ${CLAUDEOS_CLIQUET_CONTROLES} (cliquet)"$'\n'
    fi
    if [ -n "$_CLIQ" ]; then
        if ! _leve "CLIQUET" "${FORCE_CLIQUET:-}"; then
            echo "[alarmes] ⛔ CLIQUET — la couche payée à chaque session GROSSIT :" >&2
            printf '%s' "$_CLIQ" >&2
            echo "[alarmes] On ne remonte jamais : pour ajouter, retire. Nomme ce qui sort." >&2
            echo "[alarmes] Sinon assume : FORCE_CLIQUET=\"motif\" git commit … (tracé)" >&2
            echo "[alarmes] Tes budgets — descriptions, index, fiche — se règlent dans reglages/CLIQUETS, une ligne CLE=valeur." >&2
            FAIL=20
        fi
    fi
fi

# --- 10. Forme des fichiers d'état — RETIRÉ le 2026-09-22 -----------------------
# Code 21 libéré. Il gardait la forme des fichiers d'état d'avant le journal à événements, et plus
# aucun niveau vivant n'en porte depuis le 2026-09-22.

# --- 11. Liste noire d'un dépôt de travail professionnel — REFUSE (code 25)
# CE QU'IL FERME : la liste noire vit DANS chaque dépôt de travail, où elle arrive avec le clone —
# un `core.excludesFile` non versionné manquerait à tout poste où l'installation n'a pas tourné, et
# le premier `git add -A` pousserait le `_IGNORE/` confidentiel au dépôt distant. Ce contrôle est le
# prix de la copie : il refuse toute divergence d'avec la référence.
# PÉRIMÈTRE, lu dans `reglages/REPONSES` :
#   · `GIT=par-domaine` — les dépôts dont le dossier racine commence par un préfixe de
#     `PREFIXES_CLIENT` : leur `.gitignore` doit être la référence, à l'octet ;
#   · `GIT=unique` — `~/.claude` lui-même, qui porte les dossiers de travail : son
#     `.git/info/exclude` doit contenir chaque ligne utile de la référence.
# PAS DE LEVIER, volontairement : une liste noire divergente n'est pas un arbitrage, et la
# conséquence — du confidentiel client poussé en ligne — est irréversible.
# Pour modifier la liste : éditer `engine/config/gitignore-documents`, puis la recopier dans chaque
# dépôt de travail. La référence est la source, jamais la copie.
# UN RÉGLAGE ILLISIBLE N'EST PAS « RIEN À GARDER ». `claudeos_reponse` rend rc=1 quand
# `reglages/REPONSES` ou sa clé manque : c'est « je n'ai pas pu regarder ». Hors de `~/.claude`, le
# crochet ne tourne que dans un dépôt que l'installation a réglé, donc le contrôle y REFUSE ; dans
# `~/.claude`, qui committe avant l'entretien, il le DIT et passe. `PREFIXES_CLIENT=` vide, lui,
# est une réponse : aucun dépôt client.
_REF_GI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/config/gitignore-documents"
_C11_MUET=""
_EST_CLIENT=""
if ! _GIT_REGIME="$(claudeos_reponse GIT)"; then
    _GIT_REGIME=""
    _C11_MUET="reglages/REPONSES ne porte pas GIT"
else
    case "$_GIT_REGIME" in
        par-domaine)
            if claudeos_reponse PREFIXES_CLIENT >/dev/null; then
                while IFS= read -r _p; do
                    [ -n "$_p" ] || continue
                    case "$(basename "$GIT_ROOT")" in "$_p"*) _EST_CLIENT=1 ;; esac
                done < <(claudeos_liste PREFIXES_CLIENT)
            else
                _C11_MUET="reglages/REPONSES ne porte pas PREFIXES_CLIENT"
            fi
            ;;
        unique) ;;
        # SANS GIT, aucun dépôt de travail à garder : le périmètre lit la RÉFÉRENCE elle-même
        # (`regime.py`, listes noires), donc aucune copie n'en peut diverger.
        aucun) ;;
        *) _C11_MUET="GIT=$_GIT_REGIME, ni par-domaine, ni unique, ni aucun" ;;
    esac
fi
if [ -n "$_C11_MUET" ]; then
    if [ "$GIT_ROOT" -ef "$HOME/.claude" ]; then
        echo "[alarmes] ⚠ LISTE NOIRE — contrôle 11 non joué : $_C11_MUET (poste non réglé)." >&2
    else
        echo "[alarmes] ⛔ LISTE NOIRE — contrôle 11 injouable dans $(basename "$GIT_ROOT") : $_C11_MUET." >&2
        echo "[alarmes] Sans le régime, rien ne dit si ce dépôt doit porter la liste noire. Répare" >&2
        echo "[alarmes] reglages/REPONSES, puis recommence." >&2
        FAIL=25
    fi
elif [ -n "$_EST_CLIENT" ]; then
    if [ ! -r "$_REF_GI" ]; then
        echo "[alarmes] ⛔ LISTE NOIRE — référence introuvable : $_REF_GI" >&2
        echo "[alarmes] Une alarme qui ne sait pas quoi comparer se tait ; celle-ci refuse." >&2
        FAIL=25
    elif [ ! -f "$GIT_ROOT/.gitignore" ]; then
        echo "[alarmes] ⛔ LISTE NOIRE ABSENTE de $(basename "$GIT_ROOT")." >&2
        echo "[alarmes] Sans elle, _IGNORE/ part au dépôt distant. Repose-la :" >&2
        echo "[alarmes]   cp \"$_REF_GI\" \"$GIT_ROOT/.gitignore\"" >&2
        FAIL=25
    elif ! cmp -s "$_REF_GI" "$GIT_ROOT/.gitignore"; then
        echo "[alarmes] ⛔ LISTE NOIRE DIVERGENTE dans $(basename "$GIT_ROOT") :" >&2
        diff -u "$_REF_GI" "$GIT_ROOT/.gitignore" 2>/dev/null | head -20 | sed 's/^/[alarmes]   /' >&2
        echo "[alarmes] La référence fait foi. Pour changer la règle, édite la RÉFÉRENCE," >&2
        echo "[alarmes] puis recopie-la dans chaque dépôt de travail :" >&2
        echo "[alarmes]   cp \"$_REF_GI\" \"$GIT_ROOT/.gitignore\"" >&2
        FAIL=25
    fi
elif [ "$_GIT_REGIME" = "unique" ] && [ "$GIT_ROOT" -ef "$HOME/.claude" ]; then
    if [ ! -r "$_REF_GI" ]; then
        echo "[alarmes] ⛔ LISTE NOIRE — référence introuvable : $_REF_GI" >&2
        FAIL=25
    else
        # `|| [ -n "$_l" ]` : sans saut final, `read` perdrait la dernière ligne de la référence —
        # et `install-poste.sh`, qui la pose, la perdrait AVEC lui : les deux côtés muets d'accord.
        _MANQ=""
        while IFS= read -r _l || [ -n "$_l" ]; do
            case "$_l" in ''|'#'*) continue ;; esac
            grep -Fxq -- "$_l" "$GIT_ROOT/.git/info/exclude" 2>/dev/null || _MANQ="$_MANQ      $_l"$'\n'
        done < "$_REF_GI"
        if [ -n "$_MANQ" ]; then
            echo "[alarmes] ⛔ LISTE NOIRE INCOMPLÈTE dans .git/info/exclude de ~/.claude (GIT=unique) :" >&2
            printf '%s' "$_MANQ" | head -20 >&2
            echo "[alarmes] Sans elle, un _IGNORE/ de travail/ part au dépôt distant. Repose-la :" >&2
            echo "[alarmes]   bash ~/.claude/engine/install-poste.sh" >&2
            FAIL=25
        fi
    fi
fi

# --- 12. Copies des relecteurs de domaine — REFUSE (code 26)
# Écrit le 2026-09-08, geste 1.6 de la bascule, sur arbitrage de l'utilisateur.
# CE QU'IL FERME : Claude Code n'explore que `~/.claude/agents/` et le `.claude/agents/` du projet
# ouvert — jamais un sous-dossier de `domaines/`. Les trois relecteurs de domaine sont donc RECOPIÉS
# dans le `.claude/agents/` de chaque dépôt qui relève de ce domaine. Ce contrôle est le prix de
# la copie, exactement comme le contrôle 25 l'est pour la liste noire : il refuse toute divergence.
# La SOURCE est `~/.claude/domaines/<DOMAINE>/agents/`. Une copie ne se modifie jamais sur place :
# on édite la source, puis on recopie. Un dépôt sans dossier `.claude/agents/` n'est PAS en faute —
# il ne relève simplement pas d'un domaine qui en porte.
# PAS DE LEVIER : un relecteur qui diverge silencieusement rend un verdict sur d'autres règles que
# celles du domaine, et rien ne le signale.
if [ -d "$GIT_ROOT/.claude/agents" ]; then
    _SRC_AG="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/domaines"
    _AGDIV=""
    for _c in "$GIT_ROOT"/.claude/agents/*.md; do
        [ -e "$_c" ] || continue
        _b="$(basename "$_c")"
        # La source peut vivre sous n'importe quel domaine : on la cherche, on ne la devine pas.
        _s="$(/usr/bin/find "$_SRC_AG" -mindepth 3 -maxdepth 3 -path '*/agents/'"$_b" -type f 2>/dev/null | head -1)"
        if [ -z "$_s" ]; then
            continue   # agent propre au dépôt, sans source de domaine : hors périmètre.
        fi
        cmp -s "$_s" "$_c" || _AGDIV="$_AGDIV      $_b  diffère de  ${_s#"$HOME"/}"$'\n'
    done
    if [ -n "$_AGDIV" ]; then
        echo "[alarmes] ⛔ RELECTEUR DE DOMAINE DIVERGENT dans $(basename "$GIT_ROOT") :" >&2
        printf '%s' "$_AGDIV" >&2
        echo "[alarmes] La source fait foi. Édite la SOURCE, puis recopie :" >&2
        echo "[alarmes]   cp ~/.claude/domaines/<DOMAINE>/agents/<fichier>.md .claude/agents/" >&2
        FAIL=26
    fi
fi

# --- 13. Journal d'événements et projection — REFUSE (codes 22 et 23)
# Écrit le 2026-09-08, geste 2.3. INERTE tant qu'aucun niveau ne porte de `journal/` ni
# d'`ETAT.md` : il ne s'éveille que si le commit en touche un. C'est voulu — le filet est posé
# AVANT la bascule du 2.4, pour qu'il n'y ait pas une fenêtre où l'on écrit sans garde.
# CE QU'IL FERME : un journal s'AJOUTE. Une ligne passée modifiée, ou deux lignes portant le même
# `id`, sont la signature d'une fusion en `union` — et git annonce cette fusion comme un SUCCÈS
# (mesuré le 2026-09-08 sur deux clones). Le dégât est donc muet sans ce contrôle.
# LEVIER SUR LE 22, et c'est un ÉCART qui tranche une contradiction du plan. Son § 2.3 (a) dit
# « refuse, aucun levier » ; son § 2.3 (c) prescrit un message d'après-`pull` où « le crochet la
# refuse — levier documenté dans le message ». Les deux ne tiennent pas ensemble : le RETRAIT du
# doublon qu'une fusion en `union` a fabriqué est la SEULE réécriture licite d'un journal, et sans
# levier elle serait impossible — le dépôt resterait en défaut pour toujours. La consigne nommée
# bat le garde général : `FORCE_JOURNAL="motif"`, tracé, et le message dit son unique usage.
# PAS de levier sur le 23, et pour une autre raison : la projection se REFAIT en une commande,
# donc il n'y a rien à assumer, seulement un geste à jouer.
# La logique n'est PAS recopiée ici : `etat.py check --staged` la porte, et lui seul.
_ETAT_PY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/etat.py"
_NIVEAUX="$(_git_noms ACM \
    | sed -nE 's#(^|.*/)journal/[^/]+\.jsonl$#\1#p; s#(^|.*/)ETAT\.md$#\1#p' \
    | sed 's#/$##' | awk '{ print ($0 == "" ? "." : $0) }' | sort -u)"
if [ -n "$_NIVEAUX" ] && [ "$FAIL" -eq 0 ]; then
    if [ ! -r "$_ETAT_PY" ] || ! command -v python3 >/dev/null 2>&1; then
        # Une alarme qui ne sait pas comment juger se TAIT ; celle-ci refuse. Même doctrine que
        # les motifs de secrets en tête de ce fichier.
        echo "[alarmes] ⛔ REFUS : un journal ou un ETAT.md est en file et etat.py est injoignable." >&2
        echo "[alarmes]   attendu : $_ETAT_PY  (et python3 sur le poste)" >&2
        FAIL=22
    else
        while IFS= read -r _n; do
            [ -n "$_n" ] || continue
            _out="$(python3 "$_ETAT_PY" check --niveau "$GIT_ROOT/$_n" --staged 2>&1)"
            _rc=$?
            if [ "$_rc" -eq 22 ] && _leve "JOURNAL" "${FORCE_JOURNAL:-}"; then
                _rc=0
            fi
            if [ "$_rc" -ne 0 ]; then
                if [ "$_rc" -eq 23 ]; then
                    echo "[alarmes] ⛔ ETAT.md ≠ PROJECTION dans ${_n} :" >&2
                    printf '%s\n' "$_out" | sed 's/^/      /' >&2
                    echo "[alarmes]   Le geste : python3 ~/.claude/engine/etat.py projette --niveau <niveau>" >&2
                else
                    echo "[alarmes] ⛔ JOURNAL RÉÉCRIT dans ${_n} :" >&2
                    printf '%s\n' "$_out" | sed 's/^/      /' >&2
                    echo "[alarmes]   Un journal s'AJOUTE. Le seul retrait licite est le doublon qu'une" >&2
                    echo "[alarmes]   fusion en \`union\` a fabriqué : garder l'événement le plus récent," >&2
                    echo "[alarmes]   retirer l'autre, et le dire dans le message du commit —" >&2
                    echo "[alarmes]     FORCE_JOURNAL=\"doublon de fusion, id <...>\" git commit … (tracé)" >&2
                    echo "[alarmes]   Pour toute AUTRE réécriture il n'y a pas de motif recevable." >&2
                fi
                [ "$FAIL" -eq 0 ] && FAIL="$_rc"
            fi
        done < <(printf '%s\n' "$_NIVEAUX")
    fi
fi

# --- 14. Fichier GELÉ modifié — REFUSE (code 24), levier FORCE_GELE ----------
# Écrit le 2026-09-08, geste 2.3. Le discriminant est l'en-tête de gel EN PREMIÈRE LIGNE de la
# version `HEAD` — pas le nom du fichier, pas une liste. `engine/index-fts.py` emploie le même,
# et un PLAN qui cite cet en-tête plus bas n'est donc pas pris pour une archive.
# CE QU'IL FERME : une archive gelée est le seul exemplaire de faits qui remontent au 2022 —
# l'historique git, lui, ne commence qu'au 2026-08-22. Une ligne ajoutée là est un fait écrit
# dans un fichier que personne ne relit ; une ligne retirée est une perte sans trace.
# DEUX BRANCHES, et la seconde est celle du commit de gel lui-même : si `HEAD` n'est pas encore
# gelé mais la version en file l'est, le commit passe À CONDITION que l'en-tête soit le SEUL
# changement. Sans cette branche, le geste 2.1 n'aurait pas pu être commité par ce contrôle.
# LEVIER assumé : entre les gestes 2.1 et 2.7 la fiche `archivage` prescrit encore d'écrire dans
# une archive. `FORCE_GELE="motif" git commit …` est l'échappatoire, tracée.
# UN FICHIER NEUF QUI NAÎT GELÉ PASSE, posé le 2026-10-01 dans la copie du template (A7) : l'import
# d'une V1 ou d'une V2 verse gelés les MEMORY.md et les fichiers de reprise de chaque niveau, l'en-tête
# en première ligne dès la copie. Aucune archive existante n'est touchée. Avant, la seconde branche
# comparait le corps à un HEAD vide et refusait : un fichier ne pouvait pas naître gelé, et dégelé il
# aurait crié aux noms morts (code 27) — l'import n'avait aucune voie de commit.
_GEL_MARQUE='> **GELÉ'
_GELDIV=""
while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    # SANS GIT, la dernière clôture n'a laissé que la PREMIÈRE ligne et des empreintes : un fichier
    # de la liste a changé par définition, donc gelé à la référence il est en faute ; gelé par ce
    # changement, l'en-tête doit en être le seul ajout, ce que `regime.py egal` compare par empreinte.
    if [ -n "$_LISTE" ]; then
        [ "$(_statut "$_f")" = A ] && continue
        _gtete="$(_git_tete "$_f" 2>/dev/null)" || _gtete=""
        _gfile="$(_git_montre "$_f" 2>/dev/null)" || continue
        case "${_gtete%%$'\n'*}" in
            "$_GEL_MARQUE"*) _GELDIV="$_GELDIV      $_f  — modifié alors qu'il est GELÉ"$'\n' ;;
            *)
                case "${_gfile%%$'\n'*}" in
                    "$_GEL_MARQUE"*)
                        python3 "$_REGIME_PY" egal "$GIT_ROOT" "$_f" 1 \
                            || python3 "$_REGIME_PY" egal "$GIT_ROOT" "$_f" 2 \
                            || _GELDIV="$_GELDIV      $_f  — gel ET autres changements depuis la dernière clôture"$'\n'
                        ;;
                esac
                ;;
        esac
        continue
    fi
    git cat-file -e "HEAD:$_f" 2>/dev/null || continue
    _gtete="$(git show "HEAD:$_f" 2>/dev/null)" || _gtete=""
    _gfile="$(git show ":$_f" 2>/dev/null)" || continue
    # PREMIERE LIGNE PAR EXPANSION, pas par tube — posé le 2026-09-22. `printf … | head -1`
    # pousse le contenu ENTIER dans un tube que `head` referme après une ligne : au-delà du
    # tampon du tube, `printf` prend SIGPIPE et bash l'annonce sur STDERR, c'est-à-dire sur le
    # canal des vraies alarmes. `${v%%$'\n'*}` rend la même valeur — chaîne entière s'il n'y a
    # pas de saut de ligne, vide si la variable est vide — sans tube ni process.
    case "${_gtete%%$'\n'*}" in
        "$_GEL_MARQUE"*)
            [ "$_gtete" = "$_gfile" ] || _GELDIV="$_GELDIV      $_f  — modifié alors qu'il est GELÉ"$'\n'
            ;;
        *)
            case "${_gfile%%$'\n'*}" in
                "$_GEL_MARQUE"*)
                    # Commit de GEL : licite si l'en-tête (plus un saut de ligne éventuel) est
                    # le seul ajout.
                    if [ "$(printf '%s\n' "$_gfile" | tail -n +2)" != "$_gtete" ] \
                    && [ "$(printf '%s\n' "$_gfile" | tail -n +3)" != "$_gtete" ]; then
                        _GELDIV="$_GELDIV      $_f  — gel ET autres changements dans le même commit"$'\n'
                    fi
                    ;;
            esac
            ;;
    esac
done < <(_git_noms ACM | grep -E '\.md$' || true)
if [ -n "$_GELDIV" ] && [ "$FAIL" -eq 0 ]; then
    if ! _leve "GELE" "${FORCE_GELE:-}"; then
        echo "[alarmes] ⛔ FICHIER GELÉ — lecture seule, rien ne s'y ajoute, rien ne s'en retire :" >&2
        printf '%s' "$_GELDIV" >&2
        echo "[alarmes] Un fait daté va au journal du niveau (etat.py add), pas dans l'archive." >&2
        echo "[alarmes] Sinon assume : FORCE_GELE=\"motif\" git commit … (tracé)" >&2
        FAIL=24
    fi
fi

# --- 15 et 16. Nom de régime mort (code 27) · chemin propre à un poste (code 28) — REFUSENT
# Écrits le 2026-09-29.
# CE QU'ILS FERMENT, et pourquoi ils BLOQUENT : un pointeur vers un régime mort ne charge jamais
# rien, et un chemin du dossier personnel d'un poste est faux sur l'autre — les deux défauts
# désactivent EN SILENCE. Cas positif réel du 15 : deux agents d'un projet personnel donnaient
# pour « Racine du projet » l'ancienne racine des dépôts, morte depuis le 2026-09-08 ; trouvés à
# une passe mensuelle, le 2026-09-24. Cas positif réel du 16 : un `settings.json` a porté le
# dossier personnel d'un poste comme dépôt de confiance, réinséré par l'outil le 2026-09-16 sans
# qu'aucun garde au commit ne le voie — le contrôle hebdomadaire AVERTISSAIT, six jours plus tard.
# PÉRIMÈTRE : les lignes AJOUTÉES du diff en file, tout fichier suivi, MOINS les fichiers GELÉS
# (en-tête en première ligne, même discriminant que le 14), les archives et les rapports d'audit,
# les BINAIRES, qui n'ont pas de ligne ajoutée (bloc daté du 2026-10-01 dans la boucle),
# et le `config.sh` qui déclare les motifs (`CLAUDEOS_TEXTES_HORS_GARDE_RE`). Les motifs, leurs
# ancrages mesurés et l'absence voulue d'exemption vivent dans `config.sh`, SOURCE UNIQUE, et
# ne sont pas recopiés ici — ce fichier n'est PAS exclu du périmètre, il ne doit donc pas porter
# un nom mort en clair, sinon il se refuse lui-même au premier commit qui le touche.
# PROVENANCE DATÉE : une ligne qui cite un nom mort ET porte une date RACONTE, elle passe
# (`CLAUDEOS_PROVENANCE_DATEE_RE`) ; sans date elle PRESCRIT, elle est refusée. Observation
# `e-20260924-202354-f1a6` : quatre citations sur cinq étaient de la provenance.
# BARRES ÉCHAPPÉES : `\/` est ramené à `/` avant de comparer — l'intégration iTerm2 réécrit
# `settings.json` ainsi et le motif nu rendait 0 sur dix chemins réels (audit 2026-09-17-mac, M-4).
# `awk 'NR<=3'` et non `head -3` : `head` referme le tube et le producteur prend SIGPIPE, que bash
# annonce sur STDERR — le canal des vraies alarmes. Même leçon que la première ligne du contrôle 14.
# LEVIERS, tracés : FORCE_NOMS_MORTS="motif", FORCE_CHEMIN_POSTE="motif".
for _v in CLAUDEOS_NOMS_MORTS_RE CLAUDEOS_PROVENANCE_DATEE_RE CLAUDEOS_CHEMIN_POSTE_RE CLAUDEOS_TEXTES_HORS_GARDE_RE; do
    if [ -z "${!_v:-}" ] && [ "$FAIL" -eq 0 ]; then
        echo "[alarmes] ⛔ REFUS : $_v absent — config.sh non sourcé ou en retard." >&2
        echo "[alarmes]    Les contrôles 15 et 16 ne savent pas quoi chercher ; une alarme muette est pire que pas d'alarme." >&2
        FAIL=27
    fi
done
_MORTS=""; _POSTE=""
if [ "$FAIL" -eq 0 ]; then
    # BINAIRES SAUTÉS — 2026-10-01. La lecture du gel met le
    # fichier ENTIER dans une variable ; sur un binaire, bash 5 écrit « octet nul ignoré » sur
    # STDERR, le canal des vraies alarmes — à chaque binaire en file, et un binaire MODIFIÉ suffit :
    # l'alarme 12 ne regarde que les ajouts. Un binaire n'a aucune ligne ajoutée : `git diff` le dit
    # « Binary files … differ », avec la même détection que `--numstat`. Le sauter ne change donc
    # aucun verdict. RESTE CONNU : git juge texte un fichier sans octet nul dans ses 8 000 premiers
    # octets (frontière mesurée), et un nul plus loin ferait encore parler ce bloc, le contrôle 14 et
    # un `grep`. Mesuré le 2026-10-01 : aucun des 962 fichiers suivis des cinq dépôts n'est dans ce cas.
    _BIN1516=$'\n'"$(git diff --cached --numstat --diff-filter=ACM | awk -F'\t' '$1=="-"&&$2=="-"{print $3}')"$'\n'
    while IFS= read -r _f; do
        [ -n "$_f" ] || continue
        case "$_BIN1516" in *$'\n'"$_f"$'\n'*) continue ;; esac
        printf '%s\n' "$_f" | /usr/bin/grep -qE -- "$CLAUDEOS_TEXTES_HORS_GARDE_RE" && continue
        # GELÉ : première ligne de HEAD, ou de la version en file pour un fichier neuf.
        _t="$(_git_tete "$_f" 2>/dev/null)" || _t="$(_git_montre "$_f" 2>/dev/null)" || _t=""
        case "${_t%%$'\n'*}" in "$_GEL_MARQUE"*) continue ;; esac
        # Lignes AJOUTÉES seules, sans leur `+`, barres JSON déséchappées.
        _adds="$(_git_diff_ajouts "$_f" | /usr/bin/grep -E '^\+' | /usr/bin/grep -vE '^\+\+\+' | sed -e 's/^+//' -e 's#\\/#/#g')"
        [ -n "$_adds" ] || continue
        _m="$(printf '%s\n' "$_adds" | /usr/bin/grep -E -- "$CLAUDEOS_NOMS_MORTS_RE" | /usr/bin/grep -vE -- "$CLAUDEOS_PROVENANCE_DATEE_RE" | awk 'NR<=3' | cut -c1-140)"
        [ -n "$_m" ] && _MORTS="$_MORTS      $_f"$'\n'"$(printf '%s\n' "$_m" | sed 's/^/          │ /')"$'\n'
        _c="$(printf '%s\n' "$_adds" | /usr/bin/grep -E -- "$CLAUDEOS_CHEMIN_POSTE_RE" | awk 'NR<=3' | cut -c1-140)"
        [ -n "$_c" ] && _POSTE="$_POSTE      $_f"$'\n'"$(printf '%s\n' "$_c" | sed 's/^/          │ /')"$'\n'
    done < <(_git_noms ACM)
fi
if [ -n "$_MORTS" ] && [ "$FAIL" -eq 0 ]; then
    if ! _leve "NOMS-MORTS" "${FORCE_NOMS_MORTS:-}"; then
        echo "[alarmes] ⛔ NOM DE RÉGIME MORT dans un texte vivant — un pointeur vers un régime mort ne charge rien, sans un mot :" >&2
        printf '%s' "$_MORTS" >&2
        echo "[alarmes] Écris la cible VIVANTE. Une ligne de PROVENANCE passe si elle porte sa date." >&2
        echo "[alarmes] La liste : engine/config.sh, CLAUDEOS_NOMS_MORTS_RE. Sinon assume : FORCE_NOMS_MORTS=\"motif\" git commit … (tracé)" >&2
        FAIL=27
    fi
fi
# MONOPOSTE : la règle « aucun chemin propre à un poste » n'entre pas quand MULTIPOSTE=non
# (ENTRETIEN.md) — il n'y a pas d'autre poste où le chemin serait faux. Le contrôle 16 se saute
# alors, comme le contrôle hebdomadaire qui tient la même règle (audit de la v3.0.0).
if [ -n "$_POSTE" ] && [ "$FAIL" -eq 0 ] && [ "$(claudeos_reponse MULTIPOSTE 2>/dev/null)" != non ]; then
    if ! _leve "CHEMIN-POSTE" "${FORCE_CHEMIN_POSTE:-}"; then
        echo "[alarmes] ⛔ CHEMIN PROPRE À UN POSTE dans un fichier suivi — il voyage, et il est faux sur l'autre poste :" >&2
        printf '%s' "$_POSTE" >&2
        echo "[alarmes] Écris ~ ou \$HOME, ou un chemin relatif." >&2
        echo "[alarmes] Le motif : engine/config.sh, CLAUDEOS_CHEMIN_POSTE_RE. Sinon assume : FORCE_CHEMIN_POSTE=\"motif\" git commit … (tracé)" >&2
        FAIL=28
    fi
fi

[ "$FAIL" -ne 0 ] && exit "$FAIL"
exit 0
