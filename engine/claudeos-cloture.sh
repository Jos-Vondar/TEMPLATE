#!/usr/bin/env bash
# =============================================================================
# claudeos-cloture.sh — le geste de clôture : commit et push de chaque dépôt git du système.
#
#   ~/<CLIENT>  → un dépôt par client (les documents de travail), énumérés par `claudeos_repos`
#   ~/.claude   → dépôt CLAUDE        (le système : règles, compétences, moteur, mémoire)
#
# ORDRE IMPOSÉ : projections d'abord (elles s'écrivent DANS les dépôts), dépôts clients
# ensuite, système en dernier. La sauvegarde clôt l'écriture — son verdict se lit par
# `git log -1`, il ne se recopie dans aucun document.
#
# SANS GIT (`GIT=aucun`) : projections et secrets comme ici, puis `cloture-sans-git.sh` au lieu
# des commits — contrôles du crochet sur ce qui a changé, empreintes réécrites, rien ne sort.
#
# CODES : 3 shim absent · 4 alarme sur les documents · 5 alarme sur le système ·
#         6 une autre clôture est déjà en cours (verrou) ·
#         7 un commit a échoué SANS refus d'alarme (identité git, verrou index.lock…) ·
#         8 rien d'un dépôt n'est poussé : en suspens (rebase, fusion, HEAD détachée), conflit
#           avec le distant (annulé), avance illisible ou push échoué.
# À travers `git commit`, git écrase TOUJOURS le code d'un hook par 1 : les codes
# ci-dessus sont ceux de CE script, pas ceux du hook.
# =============================================================================
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

# --- Garde : une seule clôture à la fois --------------------------------------
# Deux onglets ouverts sur le même poste peuvent lancer cette clôture dans le même moment.
# Il dégrade en avertissement si `flock` manque, il ne bloque jamais par accident.
claudeos_lock cloture || exit 6

HOOK_SRC="$SELF/hooks/pre-commit-alarmes.sh"
SYS="$HOME/.claude"

# --- La liste des dépôts : `claudeos_repos` ---
# Un client de plus ne demande pas d'éditer ce script. `_DEPOTS` contient AUSSI le dépôt système.
# Les DOCUMENTS d'abord, le SYSTÈME en dernier, et c'est délibéré : le dépôt système porte la trace
# de ce que la clôture vient de faire, donc il se committe après ce qu'il décrit.
# PORTABILITÉ : pas de `mapfile`, absent du bash 3.2 de macOS (sous `set -u` le script ne ferait
# RIEN). L'idiome `while read` ci-dessous tourne à l'identique sous bash 3.2 et bash 5.
_DEPOTS=(); while IFS= read -r _d; do [ -n "$_d" ] && _DEPOTS+=("$_d"); done < <(claudeos_repos)
# SANS GIT (`GIT=aucun`), aucun dépôt : la fin de la clôture est `cloture-sans-git.sh`, plus bas.
_SANS_GIT=""; [ "$(claudeos_regime)" = aucun ] && _SANS_GIT=1
if [ "${#_DEPOTS[@]}" -eq 0 ] && [ -z "$_SANS_GIT" ]; then
    echo "[clôture] ⛔ aucun dépôt énuméré — refus plutôt que sauvegarde silencieusement vide." >&2
    exit 1
fi
# `${t[@]+"${t[@]}"}` ET NON `"${t[@]}"`, partout où un tableau peut être vide — sans dossier de
# travail, ou sans git. Sous le bash 3.2 de macOS et `set -u`, un tableau vide est « unbound
# variable » et le script MEURT avant tout commit ; la forme ci-dessus rend zéro mot, sans erreur,
# et garde intacts les éléments à espaces.
_DOCS=(); for _d in ${_DEPOTS[@]+"${_DEPOTS[@]}"}; do [ "$_d" = "$SYS" ] || _DOCS+=("$_d"); done
_etiq() { printf '%s' "${1/#$HOME/$CLAUDEOS_TILDE}"; }

# --- Garde : un shim ABSENT est MUET -----------------------------------------
# Le dépôt committerait sans aucune alarme, sans que rien ne le dise. Refuser est le
# seul comportement sûr ; l'installateur de poste sait les reposer.
# Le shim écrit `$HOME` en littéral (il est posé par un printf non expansé) ; comparé à un
# chemin résolu, il échouerait toujours. On teste donc la QUEUE du chemin, commune aux deux formes, ce qui distingue quand même
# un ancien emplacement du nouveau, la seule confusion à éviter ici.
_SHIM_TAIL="$CLAUDEOS_SHIM_TAIL"   # source unique : config.sh
_shim_ok() {
    local repo="$1" shim="$1/.git/hooks/pre-commit"
    [ -d "$repo/.git" ] || return 0
    if [ ! -x "$shim" ] || ! grep -qF "$_SHIM_TAIL" "$shim" 2>/dev/null; then
        echo "[clôture] ⛔ REFUS : le shim pre-commit de $repo est absent ou pointe ailleurs." >&2
        echo "[clôture] Un shim absent est muet — le dépôt committerait sans alarme." >&2
        echo "[clôture] Répare : bash \"\$HOME/.claude/engine/install-poste.sh\"" >&2
        return 1
    fi
    # Un `core.hooksPath`, local ou global, envoie git chercher ses crochets AILLEURS : le shim est
    # là et ne tourne jamais, et un secret partirait sans alarme.
    local hp; hp="$(git -C "$repo" config --get core.hooksPath 2>/dev/null)" || hp=""
    if [ -n "$hp" ]; then
        case "$hp" in "~"*) hp="$HOME${hp#\~}" ;; /*) ;; *) hp="$repo/$hp" ;; esac
        if [ "$(cd "$hp" 2>/dev/null && pwd -P)" != "$(cd "$repo/.git/hooks" && pwd -P)" ]; then
            echo "[clôture] ⛔ REFUS : core.hooksPath vaut « $(git -C "$repo" config --get core.hooksPath) » pour $repo —" >&2
            echo "[clôture] git y cherche ses crochets, et celui de ClaudeOS ne tourne pas : le dépôt committerait sans alarme." >&2
            echo "[clôture] Retire-le (git config --global --unset core.hooksPath, ou sans --global s'il est local), puis relance." >&2
            return 1
        fi
    fi
    return 0
}
[ -r "$HOOK_SRC" ] || { echo "[clôture] ⛔ REFUS : $HOOK_SRC introuvable — les shims pointeraient dans le vide." >&2; exit 3; }
for _d in ${_DOCS[@]+"${_DOCS[@]}"}; do _shim_ok "$_d" || exit 3; done
_shim_ok "$SYS" || exit 3

# --- 1. La PROJECTION de chaque niveau passé aux événements, AVANT les commits ----
# `ETAT.md` est une projection : si le journal a reçu des événements dans la séance et que
# personne n'a rejoué la projection, le fichier est en retard sur son journal — et le contrôle 23
# du crochet REFUSE le commit, donc la clôture s'arrête. Ce qui dérive d'autre chose se recalcule
# avant d'être commité. Un niveau sans `journal/` n'est pas touché.
# TOUS LES NIVEAUX, projets compris, pas seulement les racines des dépôts : `niveaux_tous()`
# d'`etat.py`, la même énumération que `check --tous`, sans liste en dur.
# UN ETAT.md RETOUCHÉ HORS PROJECTION SE DIT AVANT D'ÊTRE ÉCRASÉ — AVERTIT, ne bloque pas. La
# reprojection écrase un `ETAT.md` édité à la main, et le refus 23 du crochet ne voit donc
# jamais l'édition. Le DISCRIMINANT est le pied, lu par
# `pied_conforme` d'`etat.py` — le motif n'est pas recopié ici : un corps qui ne fait plus les M
# caractères que son pied annonce a été touché hors projection, à la main ou par une fusion ; un
# fichier seulement EN RETARD sur son journal garde un pied exact, et ne crie pas. Ce qui disparaît
# est montré, dix lignes au plus : la sortie de la clôture est le seul endroit où il survit.
if ! _HORS=$(python3 -c "
import os, sys; sys.path.insert(0, '$SELF')
from etat import niveaux_tous, pied_conforme
for n in niveaux_tous():
    f = os.path.join(n, 'ETAT.md')
    if os.path.isdir(os.path.join(n, 'journal')) and os.path.isfile(f):
        r = pied_conforme(open(f, encoding='utf-8').read())
        if r: print(n + '\t' + r)
" 2>&1); then
    echo "[clôture] ⚠ IMPOSSIBLE de vérifier les ETAT.md retouchés à la main — une édition écrasée ne serait pas signalée :" >&2
    printf '%s\n' "$_HORS" | sed 's/^/          /' >&2
    _HORS=""
fi
while IFS= read -r _d; do
    [ -n "$_d" ] && [ -d "$_d/journal" ] || continue
    _raison=$(printf '%s\n' "$_HORS" | awk -F'\t' -v d="$_d" '$1 == d { print $2 }')
    _avant_main=""; [ -n "$_raison" ] && _avant_main=$(cat "$_d/ETAT.md")
    if ! _out=$(python3 "$SELF/etat.py" projette --niveau "$_d" 2>&1); then
        echo "[clôture] WARN : la projection de ${_d/#$HOME/$CLAUDEOS_TILDE} a échoué :" >&2
        printf '%s\n' "$_out" | sed 's/^/          /' >&2
    elif [ -n "$_raison" ]; then
        echo "[clôture] ⚠ ${_d/#$HOME/$CLAUDEOS_TILDE}/ETAT.md était RETOUCHÉ HORS PROJECTION ($_raison) — la reprojection l'a ÉCRASÉ." >&2
        # Deux fichiers ordinaires : un bac à sable peut refuser à diff un tube ou /dev/fd. Et diff
        # rend 2 quand il n'a pas pu comparer : ce n'est pas « rien d'ajouté ».
        _diff="" _rc_diff=2
        if _tmp_main=$(mktemp "${TMPDIR:-/tmp}/cloture-etat.XXXXXX"); then
            printf '%s\n' "$_avant_main" > "$_tmp_main"
            _diff=$(diff "$_tmp_main" "$_d/ETAT.md"); _rc_diff=$?
            rm -f "$_tmp_main"
        fi
        _perdu=$(printf '%s\n' "$_diff" | grep -E '^< .*[^[:space:]]' | awk 'NR<=10')
        if [ "$_rc_diff" -gt 1 ]; then
            echo "[clôture]   Comparaison IMPOSSIBLE (diff rc=$_rc_diff) : ce qu'il portait en propre n'est pas montré." >&2
        elif [ -n "$_perdu" ]; then
            echo "[clôture]   Ce qu'il portait en propre, perdu désormais (dix lignes au plus) :" >&2
            printf '%s\n' "$_perdu" | sed 's/^< /          │ /' >&2
        else
            echo "[clôture]   Rien ne s'y était AJOUTÉ : la retouche retirait ou déplaçait des lignes, la projection les a remises." >&2
        fi
        echo "[clôture]   Un fait à garder passe par etat.py add : ETAT.md n'est qu'une projection du journal." >&2
    fi
done < <(python3 -c "
import sys; sys.path.insert(0, '$SELF')
from etat import niveaux_tous
print('\n'.join(niveaux_tous()))
" 2>/dev/null)

# UNE REPROJECTION DONT LE SEUL DIFF EST LA DATE DE SON PIED EST ANNULÉE. `etat.py` réécrit
# « projeté le AAAA-MM-JJ depuis N événements · M caractères » à chaque passage : la date bouge
# même quand N et M sont identiques. Commiter ces fichiers ferait du bruit, et surtout l'alarme de
# dépôt DORMANT, qui juge sur `git log -1`, ne pourrait plus jamais se déclencher.
# Le geste : diff sans la ligne de pied ; s'il ne reste rien, `git checkout` le fichier.
for _d in ${_DEPOTS[@]+"${_DEPOTS[@]}"}; do
    [ -d "$_d/.git" ] || continue
    while IFS= read -r _rel; do
        [ -n "$_rel" ] || continue
        # LA DATE SEULE, JAMAIS LE COMPTE : N et M sont des FAITS que le contrôle 23 compare au
        # journal. Un `observation` ne se projette pas dans le corps mais fait bouger N : annuler ce
        # pied ferait refuser le commit suivant pour `ETAT.md ≠ projection`. On ne neutralise que la
        # date, et on exige que le reste du pied soit identique.
        _av=$(git -C "$_d" show "HEAD:$_rel" 2>/dev/null | grep -oE '\*projeté le [^*]*\*' | sed 's/projeté le [0-9-]* //')
        _ap=$(grep -oE '\*projeté le [^*]*\*' "$_d/$_rel" 2>/dev/null | sed 's/projeté le [0-9-]* //')
        if [ "$_av" = "$_ap" ] && [ -z "$(git -C "$_d" diff -U0 -- "$_rel" \
                   | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' \
                   | grep -vE '^[+-]\*projeté le ')" ]; then
            git -C "$_d" checkout -- "$_rel" 2>/dev/null
        fi
    done < <(git -C "$_d" diff --name-only -- '*ETAT.md' 2>/dev/null)
done

ECARTES=""   # fichiers tenus hors du commit, rapportés en fin de clôture

# --- 2. Rangement des secrets — avertit, ne bloque pas ------------------------
# Il regarde l'arbre vivant entier, zones hors dépôt comprises : ce qu'aucun hook de
# commit ne peut voir. Un défaut de rangement ne doit pas empêcher de sauvegarder.
bash "$SELF/controle-secrets.sh" || true

# Étiquette du commit système : CLAUDEOS_NATURE="incident: <motif>" ou "chantier: d-<ref> <motif>".
# Retenue seulement justifiée — solde moteur sous le seuil, décision présente au journal — sinon
# « clôture: », que le compteur de croisière du démarrage compte comme chantier. La clôture
# étiquette, elle ne refuse jamais : un oubli ne coûte pas la sauvegarde. Sans les budgets de
# `config.sh` (`claudeos_somme`, `CLAUDEOS_MOTEUR_RE`), le solde n'est pas mesuré : un incident
# déclaré compte alors comme chantier, et la clôture le dit.
_message_commit() {
    local repo="$1" nom="$2" nat="${CLAUDEOS_NATURE:-}" defaut a="" b="" ref
    local max="${CLAUDEOS_INCIDENT_SOLDE_MAX:-1024}"   # octets ajoutés au moteur
    defaut="clôture: $(date '+%Y-%m-%d %H:%M')"
    if [ "$nom" != "système" ] || [ -z "$nat" ]; then printf '%s' "$defaut"; return; fi
    case "$nat" in
        incident:*)
            if declare -F claudeos_somme >/dev/null && [ -n "${CLAUDEOS_MOTEUR_RE:-}" ]; then
                a=$(cd "$repo" && claudeos_somme "$CLAUDEOS_MOTEUR_RE" "${CLAUDEOS_MOTEUR_HORS_RE:-}")
                b=$(cd "$repo" && claudeos_somme "$CLAUDEOS_MOTEUR_RE" "${CLAUDEOS_MOTEUR_HORS_RE:-}" HEAD)
            fi
            case "$a" in ""|0|*[!0-9]*) b=x ;; esac; case "$b" in ""|0|*[!0-9]*) b=x ;; esac
            [ "$b" != x ] && [ $((a - b)) -le "$max" ] && { printf '%s' "$nat"; return; }
            echo "[clôture] ⚠ incident déclaré, solde moteur ${a:-?}-${b:-?} non mesuré ou > $max octets : compté comme chantier." >&2 ;;
        "chantier: d-"*)
            ref="${nat#chantier: }"; ref="${ref%% *}"
            cat "$repo"/journal/*.jsonl 2>/dev/null | grep -F "\"ref\": \"$ref\"" | grep -qF '"type": "decision"' \
                && { printf '%s' "$nat"; return; }
            echo "[clôture] ⚠ chantier déclaré sans décision $ref au journal : message par défaut." >&2 ;;
        *) echo "[clôture] ⚠ CLAUDEOS_NATURE non reconnu (incident: … ou chantier: d-… …) : message par défaut." >&2 ;;
    esac
    printf '%s' "$defaut"
}

# --- 3. Un dépôt : commit s'il y a de quoi, push dès qu'il y a de l'avance ----
# L'AVANCE SE LIT, elle ne se déduit pas d'un geste : un commit fait à la main hors
# clôture resterait sinon local indéfiniment, l'arbre propre faisant croire que tout
# était parti.
# _donnees_neuves REPO — parmi les chemins NEUFS lus sur l'entrée, les données texte à tenir hors de
# la sauvegarde. Hors de `_cloture_depot` : la clôture sans git (`cloture-sans-git.sh`) l'emploie
# aussi. Exemptions de `config.sh`, la même source que le crochet : `CLAUDEOS_DATA_EXEMPT_RE` partout,
# `CLAUDEOS_DATA_EXEMPT_SYSTEME_RE` (la configuration du gabarit) dans `~/.claude` seulement. Une
# exemption vide n'exempte rien : passé tel quel à `grep -v`, un motif vide écarterait TOUT.
_donnees_neuves() {
    local a ex="${CLAUDEOS_DATA_EXEMPT_RE:-}" sys="${CLAUDEOS_DATA_EXEMPT_SYSTEME_RE:-}"
    a="$(grep -Ei -- "$CLAUDEOS_DATA_RE" || true)"
    [ -n "$ex" ] && a="$(printf '%s\n' "$a" | grep -vE -- "$ex" || true)"
    if [ -n "$sys" ] && [ "$1" -ef "$HOME/.claude" ]; then
        a="$(printf '%s\n' "$a" | grep -vE -- "$sys" || true)"
    fi
    printf '%s' "$a"
}
_cloture_depot() {
    local repo="$1" nom="$2" rc_alarme="$3" committed=1 _sortie=""
    [ -d "$repo/.git" ] || return 0
    # UN DÉPÔT EN SUSPENS NE SE CLÔT PAS — rebase ou fusion en cours, HEAD détachée : un commit fait
    # là n'est sur aucune branche, rien ne le pousserait, et le démarrage suivant ne le compterait
    # pas. `claudeos_en_suspens` (lib_regime.sh). Code 8 : « rien n'est poussé », la cause est dite.
    if claudeos_en_suspens "$repo"; then
        echo "[clôture] ⛔ $nom : un rebase ou une fusion est en cours, ou HEAD est détachée — rien n'est committé ni poussé." >&2
        echo "[clôture]    Regarder : git -C ${repo/#$HOME/$CLAUDEOS_TILDE} status, puis terminer (git rebase --continue, git merge --continue) ou annuler (git rebase --abort, git merge --abort), et relancer." >&2
        return 8
    fi
    if [ -n "$(git -C "$repo" status --porcelain)" ]; then
        echo "[clôture] $nom : $(git -C "$repo" status --porcelain | wc -l | tr -d ' ') changement(s)."
        git -C "$repo" add -A
        # MISE DE CÔTÉ DES DONNÉES TEXTE NEUVES. On pose ICI la même question que l'alarme du hook,
        # avec le MÊME motif (`config.sh`), et AVANT elle. Les fichiers visés sortent de la file ;
        # ils ne bougent pas du disque. Jamais de déplacement automatique : `_IGNORE/` est hors
        # sauvegarde, il exilerait le fichier en silence et casserait ses renvois. La sauvegarde ne
        # bloque pas, la décision reste entière.
        # LES AUTRES ALARMES CONTINUENT DE BLOQUER : un secret en partance n'est pas un défaut de
        # rangement.
        # FORCE_DATA COURT-CIRCUITE LA MISE DE CÔTÉ : sans ce test, le levier posé pour un faux
        # positif serait annulé par la mise de côté qui tourne AVANT le hook.
        # Le filtre et ses exemptions : `_donnees_neuves`, au-dessus.
        local a_ecarter=""
        if [ -z "${FORCE_DATA:-}" ]; then
            a_ecarter="$(git -C "$repo" diff --cached --name-only --diff-filter=A | _donnees_neuves "$repo")"
        fi
        if [ -n "$a_ecarter" ]; then
            while IFS= read -r f; do
                [ -n "$f" ] && git -C "$repo" reset -q -- "$f"
            done <<< "$a_ecarter"
            echo "[clôture] ⚠ $nom : $(printf '%s\n' "$a_ecarter" | wc -l | tr -d ' ') fichier(s) de données TENUS HORS DU COMMIT (la sauvegarde continue) :" >&2
            printf '%s\n' "$a_ecarter" | sed 's/^/      /' >&2
            ECARTES="${ECARTES}${nom}\t${a_ecarter}\n"
        fi
        # UNE FILE VIDE N'EST PAS UN REFUS D'ALARME. Sans ce test, `git commit` rendrait un code non
        # nul faute de rien à committer, et la branche d'erreur ci-dessous conclurait « refusé par
        # les alarmes » — une conclusion portée par une branche d'erreur, exactement le défaut que
        # la compétence `controles-et-alarmes` interdit.
        if git -C "$repo" diff --cached --quiet; then
            echo "[clôture] $nom : rien ne reste à committer après la mise de côté."
        elif _sortie="$(git -C "$repo" commit -q -m "$(_message_commit "$repo" "$nom")" 2>&1)"; then
            [ -n "$_sortie" ] && printf '%s\n' "$_sortie" >&2
            committed=0
        else
            # UN COMMIT QUI ÉCHOUE N'EST PAS, PAR LUI-MÊME, UN REFUS D'ALARME : identité git absente,
            # `index.lock` laissé par un autre processus… Le code retour ne départage rien, git
            # écrase celui du hook par 1 (en-tête). LE DISCRIMINANT EST DANS LA SORTIE : chaque refus
            # du hook imprime une ligne « [alarmes] ⛔ », et aucun message de git n'en porte. D'où la
            # sortie capturée, puis réémise telle quelle. Un `case` et non un `grep` : pas de
            # troisième issue « je n'ai pas pu regarder ».
            [ -n "$_sortie" ] && printf '%s\n' "$_sortie" >&2
            case "$_sortie" in
                *'[alarmes] ⛔'*)
                    echo "[clôture] ⛔ commit de $nom REFUSÉ par les alarmes (détail ci-dessus)." >&2
                    echo "[clôture] Traite la cause, ou assume avec un levier motivé : FORCE_…=\"motif\"." >&2
                    return "$rc_alarme"
                    ;;
            esac
            echo "[clôture] ⛔ commit de $nom ÉCHOUÉ SANS REFUS D'ALARME — aucune ligne « [alarmes] ⛔ » ci-dessus." >&2
            echo "[clôture] La cause est le message qui précède — git (identité, verrou .git/index.lock…) ou un" >&2
            echo "[clôture] crochet qui a planté sans conclure. Aucun levier FORCE_… ne la lève." >&2
            return 7
        fi
    else
        echo "[clôture] $nom : rien à committer."
    fi
    if [ -z "$(git -C "$repo" remote 2>/dev/null)" ]; then
        echo "[clôture] $nom : aucun remote — les commits restent locaux. $(git -C "$repo" log --oneline -1)"
        return 0
    fi
    # L'AVANCE SE LIT, OU LA CLÔTURE DIT QU'ELLE N'A PAS PU : jamais de `|| echo 0` qui changerait
    # une erreur de `rev-list` en « rien à pousser ». L'intégration du distant : `claudeos_integre`
    # (lib_regime.sh), qui ne rebase jamais une fusion ; un conflit s'y annule, commits locaux
    # intacts, et rend 8. Un push échoué rend 8 aussi : le code de sortie dit ce que disent les messages.
    local ahead
    if ! ahead="$(git -C "$repo" rev-list --count @{u}..HEAD 2>/dev/null)"; then
        echo "[clôture] ⛔ $nom : avance sur le distant illisible (branche sans amont ?) — rien n'est poussé." >&2
        return 8
    fi
    if [ "$ahead" -gt 0 ] || [ "$committed" -eq 0 ]; then
        claudeos_integre "$repo" "$nom" "[clôture]"
        [ "$?" -eq 8 ] && return 8
        if _sortie="$(git -C "$repo" push -q 2>&1)"; then
            echo "[clôture] $nom poussé — $(git -C "$repo" log --oneline -1)"
        else
            echo "[clôture] ⛔ push de $nom ÉCHOUÉ — les commits sont locaux, rien n'est perdu, mais RIEN n'est sauvegardé à distance : ${_sortie%%$'\n'*}" >&2
            return 8
        fi
    else
        echo "[clôture] $nom : déjà à jour avec le distant."
    fi
    return 0
}

# --- Les sessions ouvertes — INFORME, ne bloque JAMAIS ----------------------
# Un commit lancé pendant qu'une session écrit capte des fichiers à moitié écrits, et c'est le
# fichier de STATUT, réécrit en dernier, qui se fait doubler. Lu ICI, juste avant le commit, et
# pas au lancement : les projections et le contrôle des secrets prennent une dizaine de secondes.
# Pas une alarme (aucun contrôle mécanique de plus) : la conduite vit dans `reprise`.
# tmux absent se dit « pas visible », jamais « aucune session ». tmux ARRÊTÉ, lui, veut bien dire
# aucune ; la principale, la session tmux `ClaudeOS`, est tue. Une session lancée hors de tmux
# n'est pas vue d'ici.
if command -v tmux >/dev/null 2>&1; then
    _sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -v '^ClaudeOS$' || true)
else
    _sessions=""
    echo ""
    echo "[clôture] ⓘ tmux absent du PATH : les sessions ouvertes ne sont PAS visibles d'ici."
    echo "[clôture]   Ce n'est pas « aucune session » — leur demander si elles ont fini d'écrire. → compétence \`reprise\`."
fi
if [ -n "$_sessions" ]; then
    echo ""
    echo "[clôture] ⚠ session(s) tmux ouverte(s) au moment du commit :"
    printf '%s\n' "$_sessions" | sed '/^$/d; s/^/[clôture]     /'
    echo "[clôture]   Avant ce commit, leur demander si elles ont fini d'écrire ; n'attendre que celles"
    echo "[clôture]   qui ont des fichiers dans le lot. → compétence \`reprise\`."
    echo "[clôture]   Ce qui va être committé, à l'instant :"
    for _d in ${_DOCS[@]+"${_DOCS[@]}"}; do
        git -C "$_d" status --porcelain 2>/dev/null | sed "s|^|[clôture]     $(_etiq "$_d")  |"
    done
    if [ -n "$_SANS_GIT" ]; then   # sans git : ce qui va être CONTRÔLÉ, depuis la dernière clôture
        python3 "$SELF/regime.py" changes "$SYS" 2>&1 | sed 's/^/[clôture]     système    /'
    else
        git -C "$SYS" status --porcelain 2>/dev/null | sed 's/^/[clôture]     système    /'
    fi
    echo ""
fi

# SANS GIT, la clôture finit là : contrôles du crochet sur ce qui a changé, empreintes réécrites,
# rien ne sort du poste. Le fichier sourcé sort lui-même, 0 ou 5.
[ -n "$_SANS_GIT" ] && . "$SELF/cloture-sans-git.sh"

# UN DÉPÔT NE PREND PAS LES AUTRES EN OTAGE : chacun est traité, même après l'échec d'un autre,
# et le code de sortie rend compte à la fin.
# CODES DE SORTIE — 4 pour TOUT dépôt de documents, 5 pour le système (`claudeos_lock` rend 6). Le
# dépôt EN CAUSE est nommé en clair dans le message ; c'est le nom qui renseigne, pas le numéro.
# `_ECHECS` porte la liste, parce qu'un seul code ne dirait pas lesquels.
# 7 : un commit échoué SANS refus d'alarme, documents ou système. Chaque dépôt en échec est nommé
# AVEC SA CAUSE ; entre documents, l'alarme l'emporte sur 7 dans le code rendu.
# 8 : RIEN N'EST POUSSÉ — dépôt en suspens (rebase, fusion, HEAD détachée), conflit avec le
# distant, avance illisible ou push échoué. Les commits éventuels restent locaux.
RC_WS=0; _ECHECS=""
for _d in ${_DOCS[@]+"${_DOCS[@]}"}; do
    _cloture_depot "$_d" "$(_etiq "$_d")" 4; _rc=$?
    case "$_rc" in
        0) ;;
        4) RC_WS=4; _ECHECS="$_ECHECS $(_etiq "$_d") (alarme autre que la donnée)" ;;
        8) [ "$RC_WS" -eq 4 ] || RC_WS=8; _ECHECS="$_ECHECS $(_etiq "$_d") (NON poussé, cause ci-dessus)" ;;
        *) [ "$RC_WS" -eq 4 ] || RC_WS=$_rc; _ECHECS="$_ECHECS $(_etiq "$_d") (échec de git, sans alarme)" ;;
    esac
done
_cloture_depot "$SYS" "système" 5; RC_SYS=$?

if [ -n "$ECARTES" ]; then
    echo "[clôture] ─────────────────────────────────────────────" >&2
    echo "[clôture] Des fichiers de données sont restés HORS SAUVEGARDE, sur le disque et non suivis." >&2
    echo "[clôture] Deux gestes, et c'est une décision, pas un réglage :" >&2
    echo "[clôture]   • les ranger dans le _IGNORE/ du PROJET (hors sauvegarde, définitif) ;" >&2
    echo "[clôture]   • ou les assumer : FORCE_DATA=\"motif\" git commit … dans le dépôt visé." >&2
    echo "[clôture] Tant que rien n'est tranché, ce rappel revient à chaque clôture — c'est voulu." >&2
fi

# ARBRE PROPRE APRÈS COUP. `ECARTES` liste ce que la clôture a écarté EXPRÈS ; ceci vérifie que
# chaque dépôt a bien un arbre PROPRE. Un dépôt qu'on croit sauvegardé et qui ne l'est pas est le
# pire des états, parce qu'on cesse de le surveiller. AVERTIT : tout ce qui pouvait être commité
# l'a été, un reste est un fait à lire, pas une raison d'échouer une seconde fois.
# `_DEPOTS` contient déjà `$SYS` : ne pas l'ajouter, il sortirait deux fois.
_SALE=""
for _d in ${_DEPOTS[@]+"${_DEPOTS[@]}"}; do
    [ -d "$_d/.git" ] || continue
    _n=$(git -C "$_d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    [ "$_n" -gt 0 ] && _SALE="$_SALE\n       ${_d/#$HOME/$CLAUDEOS_TILDE} : $_n fichier(s) encore non commité(s)"
done
if [ -n "$_SALE" ]; then
    echo "[clôture] ⚠ ARBRE ENCORE SALE APRÈS LA CLÔTURE — ce qui suit n'est PAS sauvegardé :" >&2
    printf '%b\n' "$_SALE" >&2
    echo "       Lire la cause plus haut (alarme, échec de git, fichier écarté), puis relancer la clôture." >&2
fi

if [ "$RC_WS" -ne 0 ]; then
    echo "[clôture] ⛔ Dépôt(s) de documents NON sauvegardé(s) :$_ECHECS" >&2
    echo "[clôture] Les autres dépôts de documents, eux, sont passés — la liste ci-dessus est exhaustive." >&2
    [ "$RC_SYS" -eq 0 ] && echo "[clôture] Le système, lui, EST sauvegardé : il ne portait rien en cause." >&2
    exit "$RC_WS"
fi
[ "$RC_SYS" -ne 0 ] && exit "$RC_SYS"
exit 0
