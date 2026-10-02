#!/usr/bin/env bash
# =============================================================================
# skills-amont.sh — compose les compétences optionnelles retenues : la surcouche du template, puis
# le corps amont au commit épinglé. Écrit le 2026-10-01, A5 du plan complet de templating (plan V3,
# lot 3, geste 3). Code PROPRE AU TEMPLATE. Bash 3.2 : c'est celui de macOS.
#
# Pour chaque nom de SKILLS_OPTION (`reglages/REPONSES`), la ligne de `engine/config/SKILLS_AMONT`
# donne le dépôt, le commit, le corps, les voisins et la licence. `skills/<nom>/SKILL.md` vaut
# `gabarits/skills/<nom>/SURCOUCHE.md`, une ligne vide, puis le corps amont sans son frontmatter.
# Les voisins sont copiés tels quels, la licence en `LICENSE.amont`, qui est aussi la MARQUE d'un
# dossier composé. La composition se fait à part, puis prend la place de l'ancienne d'un bloc : un
# échec n'écrit rien sous `skills/<nom>/` (M-AMONT-ECHEC), et les autres noms continuent.
#
# Un dossier d'une optionnelle NON retenue est retiré s'il porte la marque : il est généré, pas
# possédé. Sans la marque, il n'a pas été composé ici : il n'est ni retiré ni remplacé, et c'est dit.
#
# Usage :
#   skills-amont.sh                   compose sous `skills/` du système, retire les non retenues
#   skills-amont.sh --essai DOSSIER   compose sous DOSSIER/skills/, cache sous DOSSIER/cache/,
#                                     ne retire rien
#   skills-amont.sh --liste           imprime les dossiers qui existeraient, sans aucun appel réseau
#   skills-amont.sh --verifier [--essai DOSSIER]
#                                     n'écrit rien et n'appelle pas le réseau : recompose depuis le
#                                     cache dans un dossier temporaire et compare à `skills/<nom>/` ;
#                                     dit une optionnelle retenue absente, une non retenue présente,
#                                     un dossier sans marque, une composition retouchée sur place
#   --sans-cache                      retélécharge tout. Par défaut, un fichier présent sous
#                                     `cache/skills-amont/<commit>/` sert sans réseau : un commit
#                                     épinglé ne change jamais, donc ce cache ne se périme pas.
#
# Codes : 0 ; 1 poste non réglé ou non conforme (SKILLS_OPTION absent ou hors de la table, un
# dossier sans marque occupe une place ; à --verifier, au moins un défaut) ; 2 appel ou template
# fautif (argument, table illisible, surcouche absente, table et contrat discordants, mode réel hors
# de ~/.claude) ; 3 à --verifier, aucun défaut mais au moins une compétence NON JUGÉE, son cache
# manquant ; 4 au moins une compétence non récupérée (M-AMONT-ECHEC), les autres composées.
# =============================================================================
set -uo pipefail
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "$SELF/config.sh"
TABLE="$CFG/SKILLS_AMONT"
CONTRAT="$CFG/REPONSES_CLES"
SURCOUCHES="$ROOT/gabarits/skills"
MARQUE="LICENSE.amont"

dit() { echo "[amont] $*"; }
crie() { echo "[amont] $*" >&2; }

MODE=vrai; CIBLE="$ROOT"; AVEC_CACHE=1; HORS_RESEAU=0; VERIF=0; LISTE=0; ESSAI=0
while [ $# -gt 0 ]; do
    case "$1" in
        --essai)
            [ $# -ge 2 ] && [ -n "$2" ] || { crie "⛔ --essai demande un dossier"; exit 2; }
            ESSAI=1; CIBLE="$2"; shift 2 ;;
        --liste) LISTE=1; shift ;;
        --verifier) VERIF=1; shift ;;
        --sans-cache) AVEC_CACHE=0; shift ;;
        -h|--help)
            awk '/^# =+$/ { n++; next } n == 1 { sub(/^# ?/, ""); print } n >= 2 { exit }' "${BASH_SOURCE[0]}"
            exit 0 ;;
        *) crie "⛔ argument inconnu : $1"; exit 2 ;;
    esac
done
if [ "$LISTE" = 1 ]; then
    [ "$ESSAI" = 0 ] && [ "$VERIF" = 0 ] || { crie "⛔ --liste ne se combine ni avec --essai ni avec --verifier"; exit 2; }
    MODE=liste
elif [ "$VERIF" = 1 ]; then
    [ "$AVEC_CACHE" = 1 ] || { crie "⛔ --verifier ne lit que le cache : --sans-cache n'y a pas de sens"; exit 2; }
    MODE=verifier; HORS_RESEAU=1
elif [ "$ESSAI" = 1 ]; then
    MODE=essai
fi

# --- La table : six colonnes, un commit de 40 hexadécimaux, aucun chemin hors du dépôt ----------
[ -r "$TABLE" ] || { crie "⛔ template : $TABLE illisible"; exit 2; }
_defauts="$(awk -v marque="$MARQUE" '
    /^[[:space:]]*(#|$)/ { next }
    {
        n++
        if (NF != 6) { printf "ligne %d : %d colonnes, 6 attendues\n", NR, NF; next }
        if ($1 !~ /^[a-z0-9][a-z0-9-]*$/) printf "ligne %d : nom illisible, %s\n", NR, $1
        if (vu[$1]++) printf "ligne %d : %s en double\n", NR, $1
        if ($2 !~ /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/) printf "ligne %d : dépôt illisible, %s\n", NR, $2
        if (length($3) != 40 || $3 !~ /^[0-9a-f]+$/) printf "ligne %d : commit de 40 hexadécimaux attendu, %s\n", NR, $3
        for (i = 4; i <= 6; i++)
            if ($i ~ /(^|[\/,])\.\.([\/,]|$)/ || $i ~ /^\//) printf "ligne %d : chemin hors du dépôt, %s\n", NR, $i
        if ($4 !~ /(^|\/)SKILL\.md$/) printf "ligne %d : le corps doit être un SKILL.md, %s\n", NR, $4
        if ($5 != "-" && $5 !~ /^[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+)*$/) printf "ligne %d : voisins illisibles, %s\n", NR, $5
        k = split($5, v, ",")
        for (i = 1; i <= k; i++)
            if (v[i] == "SKILL.md" || v[i] == marque) printf "ligne %d : le voisin %s écraserait la composition\n", NR, v[i]
    }
    END { if (!n) print "aucune ligne" }' "$TABLE")"
if [ -n "$_defauts" ]; then
    crie "⛔ template : $TABLE fautif"
    printf '%s\n' "$_defauts" | sed 's/^/    - /' >&2
    exit 2
fi
ORDRE="$(awk '!/^[[:space:]]*(#|$)/ { print $1 }' "$TABLE")"

# La table et le contrat des réponses nomment les mêmes optionnelles : une valeur permise sans ligne
# ne se composerait jamais, une ligne sans valeur permise ne serait jamais retenue.
_permis="$(awk '$1 == "SKILLS_OPTION" { print $4; exit }' "$CONTRAT" 2>/dev/null | tr ',' '\n' | sort)"
_table="$(printf '%s\n' "$ORDRE" | sort)"
if [ -z "$_permis" ] || [ "$_permis" != "$_table" ]; then
    crie "⛔ template : la table $TABLE et les valeurs permises de SKILLS_OPTION dans $CONTRAT diffèrent —" \
         "table : $(printf '%s ' $_table); contrat : $(printf '%s ' $_permis)"
    exit 2
fi

# Chaque surcouche ouvre sur un frontmatter fermé, dont le `name:` est celui de son dossier.
fm_nom() {
    awk 'NR == 1 { if ($0 !~ /^---[[:space:]]*$/) exit; next }
         /^---[[:space:]]*$/ { if (nom != "") print nom; exit }
         /^name:/ { nom = $0; sub(/^name:[[:space:]]*/, "", nom); sub(/[[:space:]]*$/, "", nom) }' "$1" 2>/dev/null
}
for nom in $ORDRE; do
    if [ "$(fm_nom "$SURCOUCHES/$nom/SURCOUCHE.md")" != "$nom" ]; then
        crie "⛔ template : $SURCOUCHES/$nom/SURCOUCHE.md absente, ou sans frontmatter fermé qui porte name: $nom"
        exit 2
    fi
done

# --- Le mode réel n'écrit que dans le système d'un poste ----------------------------------------
# Depuis l'atelier, la racine est la copie du template : y composer écrirait des corps empruntés
# dans ce qui s'exporte, alors que le dépôt public n'en porte aucun (`d-skills-amont`).
if [ "$MODE" = vrai ]; then
    _ici="$(cd "$ROOT" && pwd -P)"
    _sys="$(cd "$HOME/.claude" 2>/dev/null && pwd -P)" || _sys=""
    if [ "$_ici" != "$_sys" ]; then
        crie "⛔ mode réel hors de ~/.claude (racine $ROOT) : composer en essai, --essai DOSSIER"
        exit 2
    fi
fi

# --- Les noms retenus ----------------------------------------------------------------------------
if ! claudeos_reponse SKILLS_OPTION > /dev/null; then
    crie "⛔ poste non réglé : $REG/REPONSES ne porte pas SKILLS_OPTION"
    exit 1
fi
RETENUS="$(claudeos_liste SKILLS_OPTION)"
est_retenu() { printf '%s\n' "$RETENUS" | grep -qx -- "$1"; }
_hors=""
for nom in $RETENUS; do
    printf '%s\n' "$ORDRE" | grep -qx -- "$nom" || _hors="$_hors $nom"
done
if [ -n "$_hors" ]; then
    crie "⛔ SKILLS_OPTION nomme ce que la table ne porte pas :$_hors"
    exit 1
fi

if [ "$MODE" = liste ]; then
    for nom in $ORDRE; do est_retenu "$nom" && echo "skills/$nom"; done
    exit 0
fi

# --- La composition ------------------------------------------------------------------------------
SKILLS="$CIBLE/skills"; CACHE="$CIBLE/cache/skills-amont"

# M-AMONT-ECHEC, mot pour mot (plan V3 § 1.7, gardé par le plan complet § 1.7).
echec() {  # echec NOM DÉPÔT COMMIT ERREUR
    crie "La compétence $1 n'a pas pu être récupérée depuis $2 au commit ${3:0:7} : $4. Elle est optionnelle, ton système est complet sans elle. Trois issues : réessayer avec le réseau ; la retirer de \`SKILLS_OPTION\` dans \`reglages/REPONSES\` puis relancer l'assemblage ; si le dépôt amont a disparu, le signaler sur le dépôt du template. Rien n'a été écrit sous \`skills/$1/\`."
}

# Les lignes vides de tête et de queue retirées : la jointure entre surcouche et corps est
# exactement une ligne vide, quelle que soit la forme des deux bords.
sans_vides_bords() { awk 'NF { p = 1 } p { a[++n] = $0; if (NF) d = n } END { for (i = 1; i <= d; i++) print a[i] }'; }

# lit_ligne NOM — pose DEPOT, COMMIT, CORPS, VOISINS et LICENCE depuis la table, validée plus haut.
lit_ligne() {
    local l
    l="$(awk -v n="$1" '!/^[[:space:]]*(#|$)/ && $1 == n { print; exit }' "$TABLE")"
    set -- $l
    DEPOT="$2"; COMMIT="$3"; CORPS="$4"; VOISINS="$5"; LICENCE="$6"
}

# recupere CHEMIN DEST — le fichier CHEMIN du dépôt amont, au commit COMMIT, copié dans DEST. Rend
# 0 ; 1 en échec, l'erreur sur la sortie standard ; 5 hors réseau, quand le cache ne le porte pas.
recupere() {
    local c="$CACHE/$COMMIT/$1" e
    if [ "$AVEC_CACHE" = 1 ] && [ -s "$c" ]; then
        cp "$c" "$2" && return 0
    fi
    if [ "$HORS_RESEAU" = 1 ]; then
        echo "absent du cache de la composition, $1"
        return 5
    fi
    command -v curl > /dev/null 2>&1 || { echo "curl introuvable"; return 1; }
    if ! e="$(curl -fsSL --max-time 30 "https://raw.githubusercontent.com/$DEPOT/$COMMIT/$1" -o "$2" 2>&1)"; then
        printf '%s\n' "${e:-curl a échoué sans message}" | tail -n 1
        return 1
    fi
    [ -s "$2" ] || { echo "fichier amont vide : $1"; return 1; }
    # Le cache s'écrit d'un bloc : un fichier tronqué servirait ensuite sans réseau, donc sans contrôle.
    mkdir -p "$(dirname "$c")" && cp "$2" "$c.$$" && mv "$c.$$" "$c"
    return 0
}

# prepare NOM DOSSIER — compose NOM dans DOSSIER/neuf, et nulle part ailleurs ; lit_ligne d'abord.
# Rend 0 ; 4, ou 5 hors réseau quand le cache manque, l'erreur dans ERR.
prepare() {
    local nom="$1" t="$2" v r
    mkdir -p "$t/neuf" || { ERR="dossier $t/neuf non créé"; return 4; }
    ERR="$(recupere "$CORPS" "$t/corps.md")"; r=$?
    [ "$r" -eq 0 ] || { [ "$r" -eq 5 ] && return 5; return 4; }
    if [ "$VOISINS" != "-" ]; then
        for v in $(printf '%s' "$VOISINS" | tr ',' ' '); do
            ERR="$(recupere "$(dirname "$CORPS")/$v" "$t/neuf/$v")"; r=$?
            [ "$r" -eq 0 ] || { [ "$r" -eq 5 ] && return 5; return 4; }
        done
    fi
    ERR="$(recupere "$LICENCE" "$t/neuf/$MARQUE")"; r=$?
    [ "$r" -eq 0 ] || { [ "$r" -eq 5 ] && return 5; return 4; }
    # Le corps sans son frontmatter : les deux premiers `---`, le premier ouvrant le fichier — la
    # fonction body() de l'emprunt d'origine, qu'une règle horizontale du corps ne trompe pas.
    awk 'NR == 1 && /^---[[:space:]]*$/ { fm = 1; next } fm == 1 && /^---[[:space:]]*$/ { fm = 2; next } fm != 1 { print }' \
        "$t/corps.md" | sans_vides_bords > "$t/corps-nu.md"
    [ -s "$t/corps-nu.md" ] || { ERR="corps vide une fois son frontmatter retiré"; return 4; }
    { sans_vides_bords < "$SURCOUCHES/$nom/SURCOUCHE.md"; echo; cat "$t/corps-nu.md"; } > "$t/neuf/SKILL.md"
    return 0
}

# compose NOM → 0 composé ; 4 non récupéré ; 1 la place est prise par un dossier sans marque.
compose() {
    local nom="$1" dest="$SKILLS/$1" tmp
    lit_ligne "$nom"
    if [ -e "$dest" ] && [ ! -f "$dest/$MARQUE" ]; then
        crie "⚠ skills/$nom/ existe sans $MARQUE : il n'a pas été composé par ce script, il n'est pas remplacé. Le déplacer, puis relancer."
        return 1
    fi
    if ! tmp="$(mktemp -d "$CIBLE/cache/.compose.XXXXXX")"; then
        echec "$nom" "$DEPOT" "$COMMIT" "dossier temporaire non créé sous $CIBLE/cache"
        return 4
    fi
    if ! prepare "$nom" "$tmp"; then
        echec "$nom" "$DEPOT" "$COMMIT" "$ERR"; rm -rf "$tmp"; return 4
    fi
    # La place : l'ancienne composition s'écarte, la neuve la prend d'un bloc.
    if [ -e "$dest" ] && ! mv "$dest" "$tmp/ancien"; then
        crie "⛔ skills/$nom/ : l'ancienne composition ne s'écarte pas, rien n'est changé"; rm -rf "$tmp"; return 4
    fi
    if ! mv "$tmp/neuf" "$dest"; then
        [ -e "$tmp/ancien" ] && mv "$tmp/ancien" "$dest"
        crie "⛔ skills/$nom/ : la composition neuve ne prend pas sa place, l'ancienne est remise"; rm -rf "$tmp"; return 4
    fi
    rm -rf "$tmp"
    dit "✅ skills/$nom/ — $DEPOT au commit ${COMMIT:0:7}$([ "$VOISINS" != - ] && printf ', voisins %s' "$VOISINS")"
    return 0
}

# verifie NOM → 0 conforme ; 1 défaut, dit ; 3 non jugé, dit. N'écrit que dans un dossier temporaire.
verifie() {
    local nom="$1" dest="$SKILLS/$1" tmp r ecarts
    lit_ligne "$nom"
    if ! est_retenu "$nom"; then
        [ -e "$dest" ] || return 0
        if [ -f "$dest/$MARQUE" ]; then
            crie "⛔ skills/$nom/ composée, mais SKILLS_OPTION ne la retient pas : bash ~/.claude/engine/skills-amont.sh la retire"
        else
            crie "⛔ skills/$nom/ porte le nom d'une optionnelle non retenue, sans $MARQUE : à déplacer"
        fi
        return 1
    fi
    if [ ! -d "$dest" ]; then
        crie "⛔ skills/$nom/ absente, alors que SKILLS_OPTION la retient : bash ~/.claude/engine/skills-amont.sh"
        return 1
    fi
    if [ ! -f "$dest/$MARQUE" ]; then
        crie "⛔ skills/$nom/ sans $MARQUE : elle n'a pas été composée par ce script"
        return 1
    fi
    if ! tmp="$(mktemp -d "${TMPDIR:-/tmp}/skills-amont-verif.XXXXXX")"; then
        crie "⚠ skills/$nom/ NON JUGÉE : dossier temporaire non créé"
        return 3
    fi
    prepare "$nom" "$tmp"; r=$?
    if [ "$r" -ne 0 ]; then
        crie "⚠ skills/$nom/ NON JUGÉE : $ERR — une composition avec le réseau reposerait le cache"
        rm -rf "$tmp"; return 3
    fi
    ecarts="$(diff -rq "$tmp/neuf" "$dest" 2>&1 | grep -v '\.DS_Store' || true)"
    rm -rf "$tmp"
    if [ -n "$ecarts" ]; then
        crie "⛔ skills/$nom/ diffère de sa composition au commit ${COMMIT:0:7} — retouchée sur place, elle se perdra à la recomposition :"
        printf '%s\n' "$ecarts" | sed "s#$tmp/neuf#composition#g; s#$dest#skills/$nom#g; s/^/    /" >&2
        return 1
    fi
    return 0
}

if [ "$MODE" = verifier ]; then
    RC=0
    for nom in $ORDRE; do
        verifie "$nom"; r=$?
        case "$r" in
            0) ;;
            1) RC=1 ;;
            *) [ "$RC" -eq 0 ] && RC=3 ;;
        esac
    done
    case "$RC" in
        0) dit "✅ conforme — optionnelles retenues : $([ -n "$RETENUS" ] && printf '%s ' $RETENUS || printf 'aucune')" ;;
        3) crie "⚠ aucun défaut, mais au moins une compétence n'a pas été jugée — ce n'est pas un vert" ;;
    esac
    exit "$RC"
fi

mkdir -p "$SKILLS" "$CIBLE/cache" || { crie "⛔ $SKILLS ou $CIBLE/cache non créé"; exit 2; }
RC=0; FAITES=""; ECHECS=""
for nom in $ORDRE; do
    est_retenu "$nom" || continue
    compose "$nom"; r=$?
    case "$r" in
        0) FAITES="$FAITES $nom" ;;
        4) ECHECS="$ECHECS $nom"; RC=4 ;;
        *) [ "$RC" -eq 0 ] && RC=1 ;;
    esac
done

if [ "$MODE" = vrai ]; then
    for nom in $ORDRE; do
        est_retenu "$nom" && continue
        d="$SKILLS/$nom"
        [ -e "$d" ] || continue
        if [ -f "$d/$MARQUE" ]; then
            if rm -rf "$d"; then
                dit "retiré : skills/$nom/, absent de SKILLS_OPTION"
            else
                crie "⚠ skills/$nom/ non retiré"; [ "$RC" -eq 0 ] && RC=1
            fi
        else
            crie "⚠ skills/$nom/ laissé en place : sans $MARQUE, il n'a pas été composé par ce script"
            [ "$RC" -eq 0 ] && RC=1
        fi
    done
fi

if [ -z "$RETENUS" ]; then
    dit "aucune compétence optionnelle retenue"
else
    dit "composées :${FAITES:- aucune}${ECHECS:+ ; non récupérées :$ECHECS}"
fi
exit "$RC"
