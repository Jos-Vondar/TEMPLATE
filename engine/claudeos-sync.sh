#!/usr/bin/env bash
# claudeos-sync.sh — tire les deux dépôts vivants et dit ce qui est rentré.
#
# Usage :  bash ~/.claude/engine/claudeos-sync.sh
#
# Le pendant de `claudeos-cloture.sh`, qui pousse. Celui-ci tire, et rien d'autre :
# il ne committe pas, ne pousse pas, ne résout aucun conflit.
#
# Refuse de tirer un dépôt dont l'arbre est sale : un `pull --rebase` y échouerait
# de toute façon, mais avec un message qui parle de rebase au lieu de dire quoi faire.
#
# Code de sortie : 0 si tout est à jour ou tiré proprement, 1 si un dépôt a été
# refusé ou a échoué. Aucun chemin propre à un poste — tout est ancré sur $HOME.

set -uo pipefail

# SOURCE UNIQUE de la liste des dépôts, depuis le 2026-09-08 (geste 1.10 de la bascule).
# La liste était écrite en dur ici ; il y a désormais un dépôt par client, et un client de plus
# ne doit pas demander d'éditer ce script. `claudeos_repos` est valide avant ET après la bascule.
# Chemin résolu depuis l'emplacement du script, jamais en dur : deux postes.
_CFG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"
if [ ! -r "$_CFG" ]; then
    echo "  ✗  config.sh introuvable ($_CFG) — la liste des dépôts est inconnue, on ne devine pas." >&2
    exit 1
fi
# shellcheck disable=SC1090
source "$_CFG"

# PORTABILITÉ, 2026-09-12 : `mapfile` n'existe qu'à partir de bash 4.0, et macOS livre le 3.2.
# Sous lui, `mapfile: command not found` puis `set -u` fait échouer la première lecture du tableau —
# le script ne fait RIEN. L'idiome `while read` ci-dessous est POSIX : il tourne à l'identique sous
# bash 3.2, bash 5 et le WSL. C'est celui que `controle-secrets.sh` l.48 employait déjà.
DEPOTS=(); while IFS= read -r _d; do [ -n "$_d" ] && DEPOTS+=("$_d"); done < <(claudeos_repos)
ETAT_PY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/etat.py"
JOURNAL_KO=0
# SANS GIT (`GIT=aucun`), ni dépôt ni second poste : rien à tirer, et ce n'est pas une panne.
if [ "$(claudeos_regime)" = aucun ]; then
    echo "  ⏭  sans objet : régime sans git (GIT=aucun), un seul poste — rien à tirer."
    exit 0
fi
if [ "${#DEPOTS[@]}" -eq 0 ]; then
    echo "  ✗  aucun dépôt énuméré — refus plutôt que silence." >&2
    exit 1
fi
RC=0

for D in "${DEPOTS[@]}"; do
    # Étiquette : le chemin RELATIF au dossier personnel, pas le seul nom de base — après la
    # bascule, `${D##*/}` rendait « ~/<DÉPÔT_A> », un chemin qui n'existe pas.
    NOM="${D/#$HOME/$CLAUDEOS_TILDE}"

    if [ ! -d "$D/.git" ]; then
        printf '  ✗  %-28s pas un dépôt git — rien à tirer\n' "$NOM"
        RC=1
        continue
    fi

    # Arbre sale : on refuse AVANT de tenter, pour dire le geste au lieu du symptôme.
    SALE=$(git -C "$D" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [ "$SALE" -gt 0 ]; then
        printf '  ✗  %-28s %s fichier(s) non commité(s) — committe ou remise avant de tirer\n' "$NOM" "$SALE"
        git -C "$D" status --porcelain | sed 's/^/       /'
        RC=1
        continue
    fi

    AVANT=$(git -C "$D" rev-parse HEAD 2>/dev/null)

    if ! SORTIE=$(git -C "$D" pull --rebase 2>&1); then
        printf '  ✗  %-28s le pull a échoué\n' "$NOM"
        printf '%s\n' "$SORTIE" | sed 's/^/       /'
        RC=1
        continue
    fi

    APRES=$(git -C "$D" rev-parse HEAD 2>/dev/null)

    if [ "$AVANT" = "$APRES" ]; then
        printf '  ✓  %-28s déjà à jour\n' "$NOM"
    else
        N=$(git -C "$D" rev-list --count "$AVANT..$APRES" 2>/dev/null || echo '?')
        printf '  ↓  %-28s %s commit(s) — %s..%s\n' "$NOM" "$N" "${AVANT:0:7}" "${APRES:0:7}"
        git -C "$D" diff --stat "$AVANT..$APRES" | sed 's/^/       /'
    fi

    # --- Filet d'après-`pull` (geste 2.3 c, écrit le 2026-09-08) ---------------
    # CE QU'IL FERME, et c'est un trou que le crochet ne peut pas voir : `merge` et `rebase`
    # ne passent PAS par `pre-commit`. Une fusion en `union` sur un journal peut donc avoir
    # fabriqué un doublon d'`id` — et git l'annonce comme un SUCCÈS (mesuré le 2026-09-08 sur
    # deux clones). Sans ce contrôle, le défaut n'apparaîtrait qu'au commit SUIVANT, sur un
    # dépôt déjà fusionné, et personne ne saurait d'où il vient.
    # Il ne tourne que sur un dépôt qui a BOUGÉ : c'est le seul moment où une fusion a eu lieu.
    if [ "$AVANT" != "$APRES" ]; then
        if [ ! -r "$ETAT_PY" ] || ! command -v python3 >/dev/null 2>&1; then
            printf '  ⚠  %-28s journal NON CONTRÔLÉ (etat.py injoignable)\n' "$NOM"
            RC=1; JOURNAL_KO=$((JOURNAL_KO + 1))
        else
            while IFS= read -r NIV; do
                [ -n "$NIV" ] || continue
                if ! OUT=$(python3 "$ETAT_PY" check --niveau "$D/$NIV" 2>&1); then
                    printf '  ⛔ %-28s JOURNAL EN DÉFAUT au niveau %s — ARRÊT\n' "$NOM" "$NIV"
                    printf '%s\n' "$OUT" | sed 's/^/       /'
                    echo "       Le geste : garder l'événement le plus RÉCENT, retirer l'autre par un"
                    echo "       commit qui porte le motif. C'est la seule réécriture licite d'un"
                    echo "       journal, et le crochet la refuse — lève-le en le nommant :"
                    echo "         FORCE_JOURNAL=\"doublon de fusion, id <...>\" git commit …"
                    RC=1; JOURNAL_KO=$((JOURNAL_KO + 1))
                fi
            done < <(git -C "$D" ls-files -- '*.jsonl' \
                | sed -nE 's#(^|.*/)journal/[^/]+\.jsonl$#\1#p' \
                | sed 's#/$##' | awk '{ print ($0 == "" ? "." : $0) }' | sort -u)
        fi
    fi

done

if [ "$JOURNAL_KO" -gt 0 ]; then
    echo
    echo "  $JOURNAL_KO niveau(x) TIRÉS mais dont le journal est en défaut. Répare avant d'écrire :"
    echo "  un événement ajouté par-dessus un doublon le rend plus dur à démêler."
elif [ "$RC" -ne 0 ]; then
    echo
    echo "  Au moins un dépôt n'a pas été tiré. Rien n'a été poussé ni commité."
fi

exit "$RC"
