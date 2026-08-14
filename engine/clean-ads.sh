#!/usr/bin/env bash
# =============================================================================
# CLEAN-ADS — supprime les flux ADS Windows (NTFS) parasites sur TOUT le
# périmètre du manifeste (pas seulement ~/workstations). Ces motifs sont exclus
# partout par SYNC_IGNORE ; le nettoyage doit couvrir la même étendue. Dérivé de
# claudeos_pairs (config.sh) — aucune liste en dur .
# Appelé par `backup.sh`, avant les rsync de capture (2026-08-09). Il l'était par le
# déclencheur `Stop` de settings.json, donc à chaque tour d'assistant : le seul dégât qu'un
# flux ADS produit est un dépôt non clonable, ce qui ne peut arriver qu'au moment où le
# contenu part au dépôt. Une fois par sauvegarde suffit. Suffixes ADS ciblés, pas '*:*' large.
# =============================================================================
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

while IFS=$'\t' read -r live repo regime; do
    [ -d "$live" ] || continue
    find "$live" -type f \( -name '*:Zone.Identifier' -o -name '*:sec.endpointdlp' -o -name '*:OECustomProperty' \) -delete 2>/dev/null
done < <(claudeos_pairs)
exit 0
