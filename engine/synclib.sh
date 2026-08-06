#!/usr/bin/env bash
# =============================================================================
# SYNCLIB — détection de dérive live<->repo. À SOURCER, pas exécuter.
# Dérive le périmètre du MANIFESTE (claudeos_pairs, config.sh) — plus aucune liste
# codée en dur (corrige le bug historique : une workstation ignoré par la dérive).
# Requiert config.sh déjà sourcé (ROOT, claudeos_pairs, SYNC_IGNORE).
# =============================================================================

# claudeos_drift MISSING DIFFERS : remplit deux tableaux de CHEMINS LIVE ABSOLUS.
#   MISSING = présent dans le miroir repo, ABSENT en live (sync jamais appliqué).
#   DIFFERS = présent des deux côtés, CONTENU différent (édition live non sauvegardée).
#
# Délégué à rsync le 2026-08-06, avec le MÊME fichier d'exclusion que backup/sync.
# Motif : la boucle bash précédente parcourait le repo sans lire SYNC_IGNORE, donc tout
# fichier committé AVANT son exclusion ressortait en DIFFERS à perpétuité — des dizaines de fantômes
# venant de fichiers gelés par une exclusion posée après coup. DIFFERS était devenu inexploitable, au point
# que le post-check de sync.sh avait cessé de le lire : une mesure fausse a désarmé le
# contrôle qu'elle devait servir.
# --checksum compare le CONTENU et pas l'horodatage : la mémoire auto est copiée par cp
# sans -p, son mtime diffère donc toujours des deux côtés sans que rien n'ait bougé.
# Le cas 'dossier live absent' (poste neuf) reste couvert : rsync -n sur une destination
# inexistante rend tout le contenu en +++++++++ sans rien créer. Vérifié sur pièce.
claudeos_drift() {
    local -n _missing="$1" _differs="$2"
    _missing=(); _differs=()
    local live_root repo_root regime code rel line
    while IFS=$'\t' read -r live_root repo_root regime; do
        [[ -d "$repo_root" ]] || continue
        while IFS= read -r line; do
            code="${line%% *}"; rel="${line#* }"
            [[ "$code" == ">f"* ]] || continue          # dossiers et méta ignorés
            if [[ "$code" == ">f+++++++++" ]]; then _missing+=("$live_root/$rel")
            else _differs+=("$live_root/$rel"); fi
        done < <(rsync -rin --dry-run --checksum --exclude-from="$SYNC_IGNORE" \
                       "$repo_root/" "$live_root/" 2>/dev/null)
    done < <(claudeos_pairs)
}

# =============================================================================
# Régime 'memory' — gestion dédiée (extraite de backup.sh / sync.sh). Les deux sens
# font un travail de SÉCURITÉ différent (pas de duplication) : la sauvegarde garde
# contre l'écrasement, la restauration snapshot + propage les suppressions. Requiert
# config.sh sourcé (SYNC_MEM_MARKERS). Ces fonctions restent le seul cas particulier
# du régime memory ; additif/miroir demeurent des one-liners rsync inline.
# =============================================================================

# claudeos_mem_backup LIVE REPO — copie la mémoire auto live -> repo.
# Garde anti-écrasement : refuse de retirer du repo un .md absent en local (poste
# probablement non synchronisé), sauf FORCE_MEM_DELETE=1. Codes de retour :
#   0 ok · 1 échec de copie · 2 anti-écrasement (message émis, abandon requis)
#   3 dossier mémoire live absent (message émis, à ignorer/continuer)
claudeos_mem_backup() {
    local live="$1" repo="$2" repo_f base marker rc=0
    [[ -d "$live" ]] || { echo "[backup] WARN : dossier mémoire auto introuvable ($live)" >&2; return 3; }
    if [[ -d "$repo" ]]; then
        local -a MISSING=()
        for repo_f in "$repo"/*.md; do
            [[ -e "$repo_f" ]] || continue
            base="$(basename "$repo_f")"
            [[ -f "$live/$base" ]] || MISSING+=("$base")
        done
        if [[ ${#MISSING[@]} -gt 0 && "${FORCE_MEM_DELETE:-0}" != "1" ]]; then
            echo "[backup] ERREUR : fichiers mémoire dans le repo mais absents en local :" >&2
            for base in "${MISSING[@]}"; do echo "  - $base" >&2; done
            echo "[backup] Machine probablement non synchronisée. Lance : bash ~/.claudeos/engine/sync.sh" >&2
            echo "[backup] Suppression VOULUE : FORCE_MEM_DELETE=1 bash ~/.claudeos/engine/backup.sh" >&2
            return 2
        fi
    fi
    rm -rf "$repo"; mkdir -p "$repo"
    find "$live" -maxdepth 1 -name "*.md" -exec cp {} "$repo/" \; \
        || { echo "[backup] ERREUR : échec copie mémoire auto ($live)" >&2; rc=1; }
    for marker in "${SYNC_MEM_MARKERS[@]}"; do
        [[ -f "$live/$marker" ]] && { cp "$live/$marker" "$repo/$marker" || rc=1; }
    done
    return $rc
}

# claudeos_mem_restore LIVE REPO BK_DIR — applique la mémoire auto repo -> live.
# Filet : snapshot dans BK_DIR de tout .md live écrasé par une version DIFFÉRENTE ou
# retiré (absent du repo), AVANT le geste — jamais de perte sèche d'un écrit non commité.
# Propage les suppressions (parité avec le miroir). Codes : 0 ok · 1 échec de copie.
claudeos_mem_restore() {
    local live="$1" repo="$2" bk="$3" repo_f live_f base marker rc=0
    mkdir -p "$live"
    for repo_f in "$repo"/*.md; do
        [[ -e "$repo_f" ]] || continue
        base="$(basename "$repo_f")"
        if [[ -f "$live/$base" ]] && ! cmp -s "$repo_f" "$live/$base"; then
            mkdir -p "$bk/$(basename "$live")"
            cp "$live/$base" "$bk/$(basename "$live")/$base"
        fi
    done
    cp "$repo/"*.md "$live/" 2>/dev/null || { echo "[sync] ERREUR : échec mémoire auto" >&2; rc=1; }
    for live_f in "$live"/*.md; do
        [[ -e "$live_f" ]] || continue
        base="$(basename "$live_f")"
        if [[ ! -f "$repo/$base" ]]; then
            mkdir -p "$bk/$(basename "$live")"
            mv "$live_f" "$bk/$(basename "$live")/$base" \
                && echo "[sync] mémoire : '$base' absent du repo → retiré du live (filet : $bk)"
        fi
    done
    for marker in "${SYNC_MEM_MARKERS[@]}"; do
        [[ -f "$repo/$marker" ]] && cp "$repo/$marker" "$live/$marker"
    done
    return $rc
}
