#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# SYNC — ClaudeOS (modèle séquentiel : jamais deux PC en même temps).
# Sens repo -> live, idempotent. Applique TOUT selon le manifeste (config.sh) :
# régime additif (~/.claude, jamais de --delete), miroir (workstations, --delete),
# mémoire auto. Puis checklist de config auto (SYNC_SETUP.sh). Source unique de
# l'application ; un poste neuf se configure d'une seule commande.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

claudeos_require_remote sync || exit 1

# --- Verrou de concurrence (double session, ou sync pendant un backup) ---
claudeos_lock sync || exit 1

git -C "$ROOT" fetch --quiet 2>/dev/null || echo "[sync] WARN : fetch impossible (hors-ligne ?) — réapplication du repo local sur la base de la dernière ref connue." >&2

LOCAL=$(git -C "$ROOT" rev-parse HEAD)
REMOTE=$(git -C "$ROOT" rev-parse "@{u}" 2>/dev/null || echo "$LOCAL")

if [[ "$LOCAL" != "$REMOTE" ]]; then
    echo "[sync] Mise à jour disponible — pull en cours..."
    git -C "$ROOT" pull --ff-only
    # Auto-mise à jour : si le pull a modifié le moteur LUI-MÊME, relancer la version
    # fraîche (sinon on appliquerait avec l'ancienne logique). Garde anti-boucle.
    if [[ "${CLAUDEOS_REEXEC:-0}" != "1" ]] \
       && git -C "$ROOT" diff --name-only "$LOCAL" HEAD 2>/dev/null \
          | grep -qE '^engine/(sync\.sh|synclib\.sh|config\.sh|config/SYNC_MAP|config/SYNC_IGNORE)$'; then
        echo "[sync] Moteur mis à jour par le pull — relance de la version courante."
        CLAUDEOS_REEXEC=1 exec bash "$SELF/sync.sh" "$@"
    fi
else
    echo "[sync] Git déjà à jour ($(git -C "$ROOT" log -1 --format='%h %s')) — réapplication du repo sur le live."
fi

# L'application s'exécute TOUJOURS, même si git est à jour : « HEAD à jour » n'implique
# pas « live à jour » (un poste peut avoir avancé HEAD sans avoir restauré l'arbre).

BK_DIR="$HOME/.claude/.sync-backups/$(date +%Y%m%d-%H%M%S)"
# Filet : rsync --backup copie dans BK_DIR tout fichier écrasé OU supprimé.
RSYNC_BASE=(-a --backup --backup-dir="$BK_DIR" --exclude-from="$SYNC_IGNORE")

# Sentinelle de complétude : ce qui manque en live et va être restauré.
source "$SELF/synclib.sh"
declare -a DRIFT_MISSING DRIFT_DIFFERS
claudeos_drift DRIFT_MISSING DRIFT_DIFFERS
[[ ${#DRIFT_MISSING[@]} -gt 0 ]] && echo "[sync] ${#DRIFT_MISSING[@]} fichier(s) du repo absent(s) en live → restauration."

# --- Application repo -> live, pilotée par le manifeste ---
# Compteur d'échecs : « Synchronisé » ne s'affiche que si l'application est complète.
SYNC_ERRS=0
MIRROR_FORCED=0     # trace du levier anti-vidage, reportée au bilan (2026-08-09)
while IFS=$'\t' read -r live repo regime; do
    [[ -d "$repo" ]] || continue
    case "$regime" in
        memory)
            # Régime mémoire : snapshot filet + copie + propagation des suppressions
            # (voir claudeos_mem_restore dans synclib.sh).
            echo "[sync] Application mémoire auto..."
            claudeos_mem_restore "$live" "$repo" "$BK_DIR" || SYNC_ERRS=$((SYNC_ERRS+1))
            ;;
        additive)
            # ~/.claude : co-habité par le runtime Claude Code → JAMAIS de --delete.
            echo "[sync] Application $(basename "$live") (additif)..."
            mkdir -p "$live"
            rsync "${RSYNC_BASE[@]}" "$repo/" "$live/" \
                || { echo "[sync] ERREUR : échec $live" >&2; SYNC_ERRS=$((SYNC_ERRS+1)); }
            ;;
        *)
            # miroir : contenu 100% authoré → propage suppressions/renommages.
            echo "[sync] Application $(basename "$live") (miroir)..."
            mkdir -p "$live"
            # #9 : visibilité — lister en dry-run les FICHIERS que --delete va supprimer,
            # AVANT de le faire (le filet --backup-dir les sauve, mais la suppression était
            # muette). On filtre les dossiers (dont les dossiers local-only non supprimables
            # qui, sinon, sonneraient à chaque sync).
            # `|| true` : sous `set -euo pipefail`, un miroir SANS suppression fait sortir
            # `grep -v` en code 1 (aucun match) → la substitution avorterait tout le sync.
            _del_all=$(rsync -ain --delete --exclude-from="$SYNC_IGNORE" "$repo/" "$live/" 2>/dev/null \
                   | sed -n 's/^\*deleting  *//p' | grep -v '/$') || true
            _ndel=$(printf '%s\n' "$_del_all" | grep -c . || true)
            _del=$(printf '%s\n' "$_del_all" | head -20)
            if [[ -n "$_del_all" ]]; then
                echo "[sync]   ↳ ${_ndel} suppression(s) en miroir (filet : $BK_DIR) :"
                printf '%s\n' "$_del" | sed 's/^/      - /'
                [[ "$_ndel" -gt 20 ]] && echo "      … et $((_ndel - 20)) autre(s)"
            fi
            # --- GARDE ANTI-VIDAGE DU MIROIR (2026-08-09) ------------------------------------
            # Un miroir propage les suppressions par conception : c'est ce qui fait voyager un
            # renommage. Mais la même mécanique vide un dossier vivant entier si le côté dépôt
            # a perdu son contenu — capture ratée, mauvaise branche, arbre partiel. Le filet
            # `--backup-dir` le sauve, oui, mais il est PURGÉ à 30 jours : passé ce délai, la
            # perte est définitive et personne n'aura rien vu passer.
            # Deux conditions ENSEMBLE, jamais une seule : plus de 20 % des fichiers du dossier
            # vivant ET plus de dix fichiers. Le pourcentage seul crie sur un petit dossier où
            # trois suppressions font la moitié ; le compte seul crie sur un gros dossier
            # réorganisé légitimement. Une alarme qui crie sur du travail ordinaire apprend à
            # ignorer la catégorie entière.
            # BLOQUE ce miroir-ci et rien d'autre : les autres régimes s'appliquent, et le bilan
            # sort INCOMPLET — c'est de la destruction, pas de l'encombrement.
            _nlive=$(find "$live" -type f 2>/dev/null | wc -l | tr -d ' ')
            if [[ "$_ndel" -gt 10 ]] && [[ "${_nlive:-0}" -gt 0 ]] \
               && (( _ndel * 100 > _nlive * 20 )); then
                if [[ "${FORCE_MIRROR_DELETE:-0}" == "1" ]]; then
                    echo "[sync] 🔓 GARDE ANTI-VIDAGE LEVÉE (FORCE_MIRROR_DELETE=1) sur $(basename "$live") : ${_ndel} suppression(s) sur ${_nlive} fichier(s)." >&2
                    MIRROR_FORCED=1
                else
                    echo "[sync] ⛔ REFUS : l'application en miroir de $(basename "$live") supprimerait ${_ndel} fichier(s) sur ${_nlive} en local (plus de 20 %)." >&2
                    echo "[sync]    Cause probable : le côté dépôt a perdu son contenu (capture ratée, branche, arbre partiel) — vérifier le dépôt AVANT de forcer." >&2
                    echo "[sync]    Si la suppression est voulue : FORCE_MIRROR_DELETE=1 bash $SELF/sync.sh" >&2
                    SYNC_ERRS=$((SYNC_ERRS+1))
                    continue
                fi
            fi
            rsync "${RSYNC_BASE[@]}" --delete "$repo/" "$live/" \
                || { echo "[sync] ERREUR : échec $live" >&2; SYNC_ERRS=$((SYNC_ERRS+1)); }
            ;;
    esac
done < <(claudeos_pairs)

[[ -d "$BK_DIR" ]] && echo "[sync] Filet : fichiers écrasés/supprimés sauvegardés → $BK_DIR"

# #15 : rétention du filet — purge les snapshots de plus de 30 jours (croissance sinon
# non bornée). Un fichier vraiment perdu se retrouve dans l'historique git ; le
# snapshot ne couvre que l'écrit-jamais-committé, dont la valeur décroît vite.
find "$HOME/.claude/.sync-backups" -mindepth 1 -maxdepth 1 -type d -mtime +30 -exec rm -rf {} + 2>/dev/null || true

# --- Post-check de complétude : le live doit refléter le repo après application ---
# La sentinelle de pré-check (plus haut) dit ce qui MANQUAIT ; ici on revérifie qu'il
# ne manque plus rien. Un rsync/cp avalé en silence est ainsi rattrapé dans la même
# exécution, pas au prochain boot.
claudeos_drift DRIFT_MISSING DRIFT_DIFFERS
if [[ ${#DRIFT_MISSING[@]} -gt 0 ]]; then
    echo "[sync] ⛔ POST-CHECK : ${#DRIFT_MISSING[@]} fichier(s) du repo toujours ABSENT(S) en live après application :" >&2
    for m in "${DRIFT_MISSING[@]:0:8}"; do echo "    ${m#"$HOME"/}" >&2; done
    SYNC_ERRS=$((SYNC_ERRS+1))
fi
# DIFFERS n'était pas lu ici tant que la mesure était polluée par les exclusions (cf.
# synclib.sh, 2026-08-06). Elle est fiable depuis : on le signale, sans bloquer — un
# contenu qui diverge après application demande un arbitrage humain (quel côté a raison),
# pas un refus de synchro qui empêcherait d'enregistrer le travail.
if [[ ${#DRIFT_DIFFERS[@]} -gt 0 ]]; then
    echo "[sync] ⚠️  POST-CHECK : ${#DRIFT_DIFFERS[@]} fichier(s) au contenu DIFFÉRENT du repo après application :" >&2
    for m in "${DRIFT_DIFFERS[@]:0:8}"; do echo "    ${m#"$HOME"/}" >&2; done
fi

# --- Bilan : trace pour le boot + « Synchronisé » seulement si complet ---
# Ce fichier est un VERROU D'ÉTAT, pas une horloge : boot-check.sh n'y cherche que le mot
# INCOMPLET. La date sert au débogage humain et ne mesure pas la fraîcheur du poste — la
# fraîcheur se lit au retard en commits et à git log. Libellé explicite depuis le 2026-08-06,
# après une lecture erronée en séance.
if [[ "$SYNC_ERRS" -gt 0 ]]; then
    printf '[sync] INCOMPLET %s (%s échec(s)) — dernière application dépôt→local. Pas la date de sauvegarde : voir git log.\n' "$(date '+%Y-%m-%d %H:%M')" "$SYNC_ERRS" > "$SELF/sync-last.log"
    echo "[sync] ⛔ INCOMPLET : $SYNC_ERRS étape(s) en échec — le live n'est PAS entièrement à jour. Voir les ERREUR ci-dessus." >&2
    exit 1
fi
# Le levier anti-vidage LEVÉ est reporté dans la trace : `sync.sh` n'a pas de journal de
# verdict comme `backup.sh`, donc sans cette mention un vidage décidé ne laisserait aucune
# trace persistante. `boot-check.sh` n'y lit que le mot INCOMPLET, l'ajout ne le perturbe pas.
printf '[sync] OK %s%s — dernière application dépôt→local. Pas la date de sauvegarde : voir git log.\n' "$(date '+%Y-%m-%d %H:%M')" "$([[ "$MIRROR_FORCED" == 1 ]] && printf ' overrides=FORCE_MIRROR_DELETE')" > "$SELF/sync-last.log"
echo "[sync] Synchronisé — $(git -C "$ROOT" log -1 --format='%h %s')"

# --- Checklist de configuration AUTO (idempotente) ---
[ -f "$SELF/SYNC_SETUP.sh" ] && bash "$SELF/SYNC_SETUP.sh"

# --- File de rattrapage MANUEL (ce qui ne peut pas être automatisé depuis ce poste) ---
if [ -x "$SELF/machine-todo.sh" ]; then
    # #20 : distinguer « 0 en attente » de « poste non résolu » (fail-loud). count
    # renvoie non-zéro si le hostname n'est pas dans SYNC_MACHINES — ne PAS le masquer en 0.
    if PEND="$("$SELF/machine-todo.sh" count 2>/dev/null)"; then
        if [ "${PEND:-0}" -gt 0 ]; then
            echo ""
            echo "[sync] ⚠ $PEND tâche(s) de RATTRAPAGE MANUEL pour ce poste :"
            "$SELF/machine-todo.sh" pending
            echo "[sync] Une fois une tâche faite : bash $SELF/machine-todo.sh done <N>"
        fi
    else
        echo "[sync] ⚠ Poste non résolu dans SYNC_MACHINES — rattrapage manuel AVEUGLE. Ajoute ce poste au registre." >&2
    fi
fi
