#!/usr/bin/env bash
# =============================================================================
# RESTORE — bootstrap d'un nouveau poste. N'est plus qu'un alias de sync.sh :
# un poste neuf se configure tout seul (sync applique les fichiers PUIS lance la
# checklist SYNC_SETUP.sh — plugin, bannière .bashrc…). Plus aucune logique propre.
# =============================================================================
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sync.sh" "$@"
