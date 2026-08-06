#!/usr/bin/env bash
# =============================================================================
# CLEAN-ADS — supprime les flux ADS Windows (NTFS) parasites sur TOUT le
# périmètre du manifeste (pas seulement ~/workstations). Ces motifs sont exclus
# partout par SYNC_IGNORE ; le nettoyage doit couvrir la même étendue. Dérivé de
# claudeos_pairs (config.sh) — aucune liste en dur .
# Appelé par le hook Stop (settings.json). Suffixes ADS ciblés, pas '*:*' large.
# =============================================================================
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

while IFS=$'\t' read -r live repo regime; do
    [ -d "$live" ] || continue
    find "$live" -type f \( -name '*:Zone.Identifier' -o -name '*:sec.endpointdlp' -o -name '*:OECustomProperty' \) -delete 2>/dev/null
done < <(claudeos_pairs)
exit 0
