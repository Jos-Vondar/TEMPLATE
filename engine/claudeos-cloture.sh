#!/usr/bin/env bash
# =============================================================================
# claudeos-cloture.sh — le geste de clôture. DEUX DÉPÔTS GIT, plus aucune copie rsync.
#
# Réécrit le 2026-08-22 (étape 4.5). La version du matin déléguait encore à
# `backup.sh` pour `~/.claude` ; ce chemin est coupé : la mémoire a quitté
# `projects/<slug>/memory` pour `~/.claude/memory`, et l'ancienne copie, en régime
# miroir sur ce dossier, aurait recopié un LIEN par-dessus les fiches du dépôt.
#
#   ~/<CLIENT>  → un dépôt par client (les documents de travail), énumérés par `claudeos_repos`
#   ~/.claude   → dépôt CLAUDE        (le système : règles, compétences, moteur, mémoire)
#
# ORDRE IMPOSÉ : vues d'abord (elles s'écrivent DANS le dépôt système), dépôts clients
# ensuite, système en dernier. La sauvegarde clôt l'écriture — son verdict se lit par
# `git log -1`, il ne se recopie dans aucun document.
#
# SANS GIT (`GIT=aucun`) : projections, index et secrets comme ici, puis `cloture-sans-git.sh` au
# lieu des commits — contrôles du crochet sur ce qui a changé, empreintes réécrites, rien ne sort.
#
# CODES : 3 shim absent · 4 alarme sur les documents · 5 alarme sur le système ·
#         6 une autre clôture est déjà en cours (verrou) ·
#         7 un commit a échoué SANS refus d'alarme (identité git, verrou index.lock…).
# À travers `git commit`, git écrase TOUJOURS le code d'un hook par 1 : les codes
# ci-dessus sont ceux de CE script, pas ceux du hook.
#
# ~/.claudeos n'est plus appelé. Il reste le filet, figé au dernier commit, avec le
# tag `bascule-decomplexification` comme point de retour, jusqu'à sa décommission.
# =============================================================================
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

# --- Garde : une seule clôture à la fois --------------------------------------
# REBRANCHÉ le 2026-08-22, sur décision de l'utilisateur, après l'audit contradictoire.
# Le verrou existait dans `config.sh` mais n'avait plus d'appelant depuis que `backup.sh`
# et `sync.sh` sont morts avec la copie rsync — la refonte a supprimé les appelants sans
# décider du sort du garde. Le scénario d'origine nommait le hook `SessionEnd`, retiré le
# 2026-08-22 ; le verrou RESTE, parce que le second scénario suffit à lui seul — deux onglets
# ouverts sur le même poste peuvent lancer cette clôture dans le même moment.
# Il dégrade en avertissement si `flock` manque, il ne bloque jamais par accident.
claudeos_lock cloture || exit 6

HOOK_SRC="$SELF/hooks/pre-commit-alarmes.sh"
SYS="$HOME/.claude"

# --- La liste des dépôts : `claudeos_repos`, depuis le 2026-09-08 (geste 1.10 de la bascule) ---
# Deux dépôts étaient nommés en dur ; il y en a désormais un par client. Un client de plus ne doit
# pas demander d'éditer ce script. La fonction est valide avant ET après la bascule.
# Les DOCUMENTS d'abord, le SYSTÈME en dernier, et c'est délibéré : le dépôt système porte la trace
# de ce que la clôture vient de faire, donc il se committe après ce qu'il décrit.
# PORTABILITÉ, 2026-09-12 : `mapfile` n'existe qu'à partir de bash 4.0, et macOS livre le 3.2.
# Sous lui, `mapfile: command not found` puis `set -u` fait échouer la première lecture du tableau —
# le script ne fait RIEN. L'idiome `while read` ci-dessous est POSIX : il tourne à l'identique sous
# bash 3.2, bash 5 et le WSL. C'est celui que `controle-secrets.sh` l.48 employait déjà.
_DEPOTS=(); while IFS= read -r _d; do [ -n "$_d" ] && _DEPOTS+=("$_d"); done < <(claudeos_repos)
# SANS GIT (`GIT=aucun`), aucun dépôt : la fin de la clôture est `cloture-sans-git.sh`, plus bas.
_SANS_GIT=""; [ "$(claudeos_regime)" = aucun ] && _SANS_GIT=1
if [ "${#_DEPOTS[@]}" -eq 0 ] && [ -z "$_SANS_GIT" ]; then
    echo "[clôture] ⛔ aucun dépôt énuméré — refus plutôt que sauvegarde silencieusement vide." >&2
    exit 1
fi
# `${t[@]+"${t[@]}"}` ET NON `"${t[@]}"`, partout où un tableau peut être vide — sans dossier de
# travail, ou sans git. Sous le bash 3.2 de macOS et `set -u`, un tableau vide est « unbound
# variable » et le script MEURT : mesuré le 2026-10-01, la forme ci-dessus rend zéro mot, sans erreur.
_DOCS=(); for _d in ${_DEPOTS[@]+"${_DEPOTS[@]}"}; do [ "$_d" = "$SYS" ] || _DOCS+=("$_d"); done
_etiq() { printf '%s' "${1/#$HOME/$CLAUDEOS_TILDE}"; }

# --- Garde : un shim ABSENT est MUET -----------------------------------------
# Le dépôt committerait sans aucune alarme, sans que rien ne le dise. Refuser est le
# seul comportement sûr ; l'installateur de poste sait les reposer.
# Le shim écrit `$HOME` en littéral (il est posé par un printf non expansé) ; `$HOME_SRC`
# est un chemin résolu. Comparer les deux échoue toujours — constaté à la première épreuve.
# On teste donc la QUEUE du chemin, commune aux deux formes, ce qui distingue quand même
# l'ancien emplacement du nouveau, la seule confusion à éviter ici.
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
    return 0
}
[ -r "$HOOK_SRC" ] || { echo "[clôture] ⛔ REFUS : $HOOK_SRC introuvable — les shims pointeraient dans le vide." >&2; exit 3; }
# TABLEAU VIDE SOUS BASH 3.2 — corrigé le 2026-10-01, signalé par la session CLAUDE_OS_TEMPLATE.
# Sans aucun dépôt de documents, `_DOCS` est vide, et sous le bash d'Apple avec `set -u` l'expansion
# `"${_DOCS[@]}"` meurt en « unbound variable » — la clôture s'arrêtait avant tout commit. La forme
# `${_DOCS[@]+"${_DOCS[@]}"}` rend zéro mot sans erreur et garde intacts les éléments à espaces ;
# bash 4.4 et plus ne mordent pas. Même forme aux deux autres boucles sur `_DOCS`, plus bas.
for _d in ${_DOCS[@]+"${_DOCS[@]}"}; do _shim_ok "$_d" || exit 3; done
_shim_ok "$SYS" || exit 3

# --- 1. Les vues générées, AVANT le commit système ---------------------------
# Elles s'écrivent dans `~/.claude/memory/`. Les régénérer après le commit les
# laisserait non committées jusqu'à la clôture suivante.
# `build-index.sh` SUPPRIMÉ le 2026-09-08 (geste 2.7) : `memory/INDEX.md` est gelé, sa couche
# curatée est devenue `## Où trouver` d'`ETAT.md`, projeté. L'appel sort avec le script.
# La vue des fils n'est plus un fichier à régénérer : `etat.py fils --tous` la calcule
# à la demande depuis les journaux. `build-threads.sh` retiré le 2026-09-09.

# --- 1 bis. La PROJECTION de chaque niveau passé aux événements ----------------
# Posé le 2026-09-08 (geste 2.4). `ETAT.md` est une projection : si le journal a reçu des
# événements dans la séance et que personne n'a rejoué la projection, le fichier est en retard
# sur son journal — et le contrôle 23 du crochet REFUSE le commit, donc la clôture s'arrête.
# La projeter ici est le geste qui ferme ce trou, au même endroit que les vues générées et pour
# la même raison : ce qui dérive d'autre chose se recalcule avant d'être commité.
# Un niveau sans `journal/` n'est pas concerné et n'est pas touché.
# ÉLARGI À TOUS LES NIVEAUX le 2026-09-17. La boucle ne parcourait que `_DEPOTS`, c'est-à-dire les
# RACINES — jamais les niveaux de PROJET, qui portent pourtant leur `journal/` et leur `ETAT.md`
# depuis la bascule du 2026-09-08. Le trou que ce bloc dit fermer restait donc grand ouvert un cran
# plus bas. MESURÉ : DEUX clôtures refusées le même jour, `CLAUDE_OS_TEMPLATE` puis
# `<APP>`, chaque fois sur un niveau de projet où des événements avaient
# été écrits sans reprojection. `niveaux_tous()` d'`etat.py` est la même énumération que celle de
# `check --tous`, donc aucune liste en dur n'est introduite ici.
# UN ETAT.md RETOUCHÉ HORS PROJECTION SE DIT AVANT D'ÊTRE ÉCRASÉ — AVERTIT, ne bloque pas.
# Arbitrage de l'utilisateur du 2026-10-01, sur une question de la session CLAUDE_OS_TEMPLATE. La
# reprojection ci-dessous écrase un `ETAT.md` édité à la main, et le refus 23 du crochet ne voit donc
# jamais l'édition : elle disparaissait sans un mot. Le DISCRIMINANT est le pied, lu par
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
        _perdu=$(diff <(printf '%s\n' "$_avant_main") "$_d/ETAT.md" | grep -E '^< .*[^[:space:]]' | awk 'NR<=10')
        if [ -n "$_perdu" ]; then
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

# D1 de l'audit du 2026-09-16, posé le 2026-09-17 — UNE REPROJECTION DONT LE SEUL DIFF EST SON
# PIED DE PAGE EST ANNULÉE. `etat.py` réécrit « projeté le AAAA-MM-JJ depuis N événements · M
# caractères » à chaque passage : la date bouge même quand N et M sont identiques, donc le fichier
# paraît modifié sans l'être. DEUX DÉGÂTS, et le second est le vrai. UN, du bruit : six `ETAT.md`
# commités pour une date. DEUX, ET C'EST F-2 : l'alarme de dépôt DORMANT juge sur `git log -1` —
# si chaque clôture commite tous les niveaux, plus aucun dépôt ne paraît jamais dormant, et
# l'alarme ne peut plus se déclencher. RENDU URGENT par l'élargissement de la boucle ci-dessus,
# qui fait passer la reprojection de 5 racines à 31 niveaux.
# Le geste : diff sans la ligne de pied ; s'il ne reste rien, `git checkout` le fichier.
for _d in ${_DEPOTS[@]+"${_DEPOTS[@]}"}; do
    [ -d "$_d/.git" ] || continue
    while IFS= read -r _rel; do
        [ -n "$_rel" ] || continue
        # LA DATE SEULE, JAMAIS LE COMPTE. Le pied porte « projeté le <date> depuis N événements ·
        # M caractères » : la DATE est du bruit, mais N et M sont des FAITS que le contrôle 23
        # compare au journal. Mesuré à l'exercice le 2026-09-17 : une première version annulait
        # aussi un pied dont seul N avait bougé — un `observation` ne se projette pas dans le
        # corps, donc N passe de 463 à 464 sans qu'une ligne change, et le commit suivant était
        # REFUSÉ pour `ETAT.md ≠ projection`. On ne neutralise donc que la date, et on exige que
        # le reste du pied soit identique.
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

# --- 1 ter. L'index de recherche dérivé — avertit, ne bloque pas ---------------
# Posé le 2026-09-23 sur arbitrage de l'utilisateur. `index-fts.py` est le recours après un
# `grep` vide, et rien ne le rebâtissait : il a dormi six jours, 31 fichiers plus récents que
# lui, précisément l'état où il sert le moins. Rebâti APRÈS les projections, pour indexer les
# `ETAT.md` du jour ; environ 1 s mesurée depuis l'élargissement du corpus aux fiches `memory/`
# et aux `CLAUDE.md`, le même jour. L'index vit dans `_IGNORE/`, hors dépôt, donc
# chaque poste bâtit le sien. Un échec n'arrête pas la sauvegarde : l'index est dérivé.
python3 "$SELF/index-fts.py" --reconstruit >/dev/null 2>&1 \
    || echo "[clôture] ⚠ index de recherche NON rebâti — python3 $SELF/index-fts.py --reconstruit, à la main" >&2

# --- 2. Rangement des secrets — avertit, ne bloque pas ------------------------
# Il regarde l'arbre vivant entier, zones hors dépôt comprises : ce qu'aucun hook de
# commit ne peut voir. Un défaut de rangement ne doit pas empêcher de sauvegarder.
bash "$SELF/controle-secrets.sh" || true

# --- 3. Un dépôt : commit s'il y a de quoi, push dès qu'il y a de l'avance ----
# L'AVANCE SE LIT, elle ne se déduit pas d'un geste : un commit fait à la main hors
# clôture restait sinon local indéfiniment, l'arbre propre faisant croire que tout
# était parti (mesuré sur pièce le 2026-08-22).
# La mise de côté des données neuves — ses motifs, et pourquoi ils doivent rester ceux du hook — est
# expliquée dans `_cloture_depot`. Elle est sortie de la fonction le 2026-10-01 pour servir aussi à la
# clôture sans git (`cloture-sans-git.sh`) : une troisième copie des motifs serait une de trop.
_CLOTURE_JOURNAL_RE='(^|/)journal/[0-9]{4}-[0-9]{2}\.jsonl$'
_CLOTURE_CONFIG_RE='(^settings\.json$|(^|/)\.claude/settings\.json$)'
_CLOTURE_TEMPLATE_RE='^(gabarits|installateur)/[^/]+\.json$'
# _donnees_neuves REPO — parmi les chemins NEUFS lus sur l'entrée, ceux à tenir hors de la sauvegarde.
_donnees_neuves() {
    local a
    a="$(grep -Ei -- "$CLAUDEOS_DATA_RE" | grep -v '/extracted/' | grep -vE -- "$_CLOTURE_JOURNAL_RE" | grep -vE -- "$_CLOTURE_CONFIG_RE" || true)"
    # Comme au hook : l'exemption du template ne vaut que dans `~/.claude`.
    if [ "$1" -ef "$HOME/.claude" ]; then
        a="$(printf '%s\n' "$a" | grep -vE -- "$_CLOTURE_TEMPLATE_RE" || true)"
    fi
    printf '%s' "$a"
}
_cloture_depot() {
    local repo="$1" nom="$2" rc_alarme="$3" committed=1 _sortie=""
    [ -d "$repo/.git" ] || return 0
    if [ -n "$(git -C "$repo" status --porcelain)" ]; then
        echo "[clôture] $nom : $(git -C "$repo" status --porcelain | wc -l | tr -d ' ') changement(s)."
        git -C "$repo" add -A
        # ÉPROUVÉ SUR SON CAS POSITIF le 2026-08-24, sur données réelles et non sur une
        # reformulation : `SCHEMA-analyser-json.json` a été tenu hors du commit, nommé dans la
        # sortie, laissé intact sur le disque, et les cinq autres fichiers neufs du même dossier
        # sont partis. Vérifié après coup dans le commit, pas sur la parole du script.
        # MISE DE CÔTÉ DES DONNÉES TEXTE NEUVES — écrit le 2026-08-24, arbitrage de l'utilisateur.
        # On pose ICI la même question que l'alarme du hook, avec le MÊME motif (`config.sh`), et
        # AVANT elle. Les fichiers visés sortent de la file ; ils ne bougent pas du disque et rien
        # ne les déplace. Motif du refus de déplacer automatiquement : `_IGNORE/` est hors
        # sauvegarde, donc un déplacement automatique exilerait un fichier de la sauvegarde en
        # silence et casserait ses renvois — l'inverse du but. Ce que ça règle : la sauvegarde ne
        # bloque plus sur un fichier de données, et la décision reste entière.
        # LES AUTRES ALARMES CONTINUENT DE BLOQUER, et c'est voulu : un secret en partance n'est pas
        # un défaut de rangement, et le laisser non suivi indéfiniment n'est pas le bon geste.
        # FORCE_DATA COURT-CIRCUITE LA MISE DE CÔTÉ, et il le faut : sans ce test, un levier posé
        # pour faire passer un faux positif serait annulé par la mise de côté qui tourne AVANT le
        # hook — l'utilisateur assumerait un fichier qui ne partirait pas quand même, et la sortie
        # dirait « assumé » d'un côté et « tenu dehors » de l'autre. Défaut trouvé le 2026-08-24 sur
        # le premier cas réel, avant sa première exécution.
        # LES DEUX EXEMPTIONS CI-DESSOUS DOIVENT RESTER IDENTIQUES À CELLES DU HOOK
        # `hooks/pre-commit-alarmes.sh`, contrôle 15. Le motif de la contrainte, mesuré le
        # 2026-09-10 : la mise de côté tourne AVANT le hook, donc un fichier que le hook exempte
        # mais que la mise de côté retire est sorti du commit EN SILENCE — la sortie dit « tenus
        # hors du commit, la sauvegarde continue » et le fichier ne part jamais. Deux gardes qui
        # divergent sur le même périmètre ne se contredisent pas à voix haute, ils se contredisent
        # sans un mot. Les commentaires qui justifient chaque motif vivent dans le hook, source
        # unique ; ici on ne recopie que les motifs.
        # L'EXEMPTION DU JOURNAL MANQUAIT ICI depuis l'arbitrage du 2026-09-08, écrite le
        # 2026-09-10 : `journal/2026-10.jsonl` naissant le 2026-10-01, le filtre `A` l'aurait
        # attrapé et la clôture aurait retenu le journal du mois hors du commit.
        # Les trois motifs `_CLOTURE_*_RE` et le filtre `_donnees_neuves` sont posés au-dessus de la
        # fonction : la clôture sans git les emploie aussi.
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
        elif _sortie="$(git -C "$repo" commit -q -m "clôture: $(date '+%Y-%m-%d %H:%M')" 2>&1)"; then
            [ -n "$_sortie" ] && printf '%s\n' "$_sortie" >&2
            committed=0
        else
            # ET UN COMMIT QUI ÉCHOUE N'EST PAS NON PLUS, PAR LUI-MÊME, UN REFUS D'ALARME — corrigé le
            # 2026-10-01, signalé par une session de projet et reproduit dans un HOME d'essai.
            # Cette branche concluait « refusé par les alarmes » sur TOUT échec de `git commit` :
            # identité git absente, `index.lock` laissé par un autre processus — le défaut du test
            # ci-dessus, un cran plus loin. Le code retour ne départage rien, git écrase celui du hook
            # par 1 (en-tête). LE DISCRIMINANT EST DANS LA SORTIE : chaque refus du hook imprime une
            # ligne « [alarmes] ⛔ » (chaque `FAIL=` et l'`exit 13` relus ce jour-là, aucun sans elle),
            # et aucun message de git n'en porte. D'où la sortie capturée, puis réémise telle quelle.
            # Un `case` et non un `grep` : pas de troisième issue « je n'ai pas pu regarder ».
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
    local ahead
    ahead="$(git -C "$repo" rev-list --count @{u}..HEAD 2>/dev/null || echo 0)"
    if [ -z "$(git -C "$repo" remote 2>/dev/null)" ]; then
        echo "[clôture] $nom : aucun remote — les commits restent locaux. $(git -C "$repo" log --oneline -1)"
        return 0
    fi
    if [ "${ahead:-0}" -gt 0 ] || [ "$committed" -eq 0 ]; then
        git -C "$repo" pull --rebase -q 2>/dev/null || echo "[clôture] WARN : pull --rebase impossible sur $nom (hors-ligne ?)." >&2
        if git -C "$repo" push -q 2>/dev/null; then
            echo "[clôture] $nom poussé — $(git -C "$repo" log --oneline -1)"
        else
            echo "[clôture] ⚠ push de $nom ÉCHOUÉ — les commits sont locaux, rien n'est perdu." >&2
        fi
    else
        echo "[clôture] $nom : déjà à jour avec le distant."
    fi
    return 0
}

# UN DÉPÔT NE PREND PLUS L'AUTRE EN OTAGE — corrigé le 2026-08-24, sur un cas réel : l'alarme
# donnée a mordu sur les documents et le dépôt SYSTÈME est resté non sauvegardé, alors qu'il ne
# portait aucun fichier en cause. Les deux dépôts sont désormais traités, et le code de sortie
# rend compte à la fin. L'ordre reste imposé : documents d'abord, système en dernier.
# --- Les sessions de projet ouvertes — INFORME, ne bloque JAMAIS -------------
# Posé le 2026-08-27 sur arbitrage de l'utilisateur, après un dégât mesuré : une
# clôture lancée pendant qu'une session de projet écrivait a capté certains de ses
# fichiers dans leur état final et un autre dans un état intermédiaire. Deux fichiers
# du même commit se contredisaient alors, et c'est la version alarmante qui était fausse.
#
# PLACÉ ICI ET PAS AU DÉBUT, sur remarque d'une session de projet le même jour :
# entre le lancement du script et le commit, il y a les vues et le contrôle des secrets,
# soit une dizaine de secondes pendant lesquelles une session peut écrire. Un état lu au
# démarrage décrit un instant qui n'est plus celui du commit. Le contrôle ne coûte rien,
# autant le faire porter sur l'instant qui compte.
#
# CE N'EST PAS UNE ALARME, et c'est délibéré — la décision « aucun contrôle mécanique
# de plus » (2026-08-17, reconfirmée le 2026-08-22) tient. Pas de seuil, pas de faux
# positif possible, rien à maintenir, aucun code de sortie. Le défaut du 2026-08-27
# n'était pas un oubli de règle : c'était de ne PAS SAVOIR qu'une session écrivait.
# La règle de conduite qui va avec — leur demander si elles ont fini — vit dans la
# compétence `reprise`, seule autorité.
# TMUX ABSENT N'EST PAS « AUCUNE SESSION » — corrigé le 2026-10-01, signalé par une session de
# projet sous un PATH sans Homebrew. La commande introuvable était avalée par le
# `2>/dev/null` : sortie vide, lue comme « personne n'écrit », et le bloc se taisait au lieu de dire
# qu'il n'avait pas pu regarder — une conclusion portée par une branche d'erreur. Un serveur tmux
# ARRÊTÉ, lui, veut bien dire « aucune session » : ce cas reste muet, et c'est juste. CE QUI RESTE
# CONFONDU : un serveur injoignable pour une autre raison (droits du socket), et toute session
# Claude lancée hors de tmux, que ce bloc n'a jamais vue.
if command -v tmux >/dev/null 2>&1; then
    _sessions_projet=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -v '^ClaudeOS$' || true)
else
    _sessions_projet=""
    echo ""
    echo "[clôture] ⓘ tmux absent du PATH : les sessions de projet ouvertes ne sont PAS visibles d'ici."
    echo "[clôture]   Ce n'est pas « aucune session » — leur demander si elles ont fini d'écrire. → compétence \`reprise\`."
fi
if [ -n "$_sessions_projet" ]; then
    echo ""
    echo "[clôture] ⚠ $(printf '%s\n' "$_sessions_projet" | wc -l | tr -d ' ') session(s) de projet ouverte(s) au moment du commit :"
    printf '[clôture]     %s\n' $_sessions_projet
    echo "[clôture]   Leur demander si elles ont fini d'écrire — un commit lancé pendant"
    echo "[clôture]   qu'une session écrit capte des fichiers à moitié écrits, et c'est le"
    echo "[clôture]   fichier de STATUT qui se fait doubler. → compétence \`reprise\`."
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

# CODES DE SORTIE — 4 pour TOUT dépôt de documents, 5 pour le système. Généralisé le 2026-09-08 :
# un code par dépôt était tenable à deux, pas à cinq, et les codes 6+ sont déjà pris ailleurs
# (`claudeos_lock` rend 6). Le dépôt EN CAUSE est nommé en clair dans le message ; c'est le nom qui
# renseigne, pas le numéro. `_ECHECS` porte la liste, parce qu'un seul code ne dirait pas lesquels.
# 7 depuis le 2026-10-01 : un commit échoué SANS refus d'alarme, documents ou système. Chaque dépôt
# en échec est nommé AVEC SA CAUSE ; entre documents, l'alarme l'emporte sur 7 dans le code rendu.
# SANS GIT, la clôture finit là : contrôles du crochet sur ce qui a changé, empreintes réécrites,
# rien ne sort du poste. Le fichier sourcé sort lui-même, 0 ou 5.
[ -n "$_SANS_GIT" ] && . "$SELF/cloture-sans-git.sh"

RC_WS=0; _ECHECS=""
for _d in ${_DOCS[@]+"${_DOCS[@]}"}; do
    _cloture_depot "$_d" "$(_etiq "$_d")" 4; _rc=$?
    case "$_rc" in
        0) ;;
        4) RC_WS=4; _ECHECS="$_ECHECS $(_etiq "$_d") (alarme autre que la donnée)" ;;
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

# D8 de l'audit du 2026-09-16, posé le 2026-09-17 — reconduit depuis le 09-10, « toujours absent ».
# CE QU'IL MESURE, et ce n'est PAS ce que `ECARTES` fait au-dessus : `ECARTES` liste ce que la
# clôture a écarté EXPRÈS ; ceci vérifie, APRÈS coup, que chaque dépôt a bien un arbre PROPRE.
# MOTIF, payé deux fois le 2026-09-17 : la clôture a annoncé un dépôt « poussé » alors que le
# commit avait été refusé plus haut par une alarme — l'annonce et le fait divergeaient, et seul un
# `git status` à la main l'a montré. Un dépôt qu'on croit sauvegardé et qui ne l'est pas est le
# pire des trois états, parce qu'on cesse de le surveiller. Le geste est celui qu'on faisait à la
# main. AVERTIT : à ce stade tout ce qui pouvait être commité l'a été, donc un reste est un fait à
# lire, pas une raison d'échouer une seconde fois.
_SALE=""
for _d in ${_DEPOTS[@]+"${_DEPOTS[@]}"} "$SYS"; do
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
