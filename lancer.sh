#!/usr/bin/env bash
# lancer.sh — lance l'agent d'installation et de mise à jour de ClaudeOS depuis le dossier qui porte
# ce fichier : ~/claudeos-amorce pour une installation ou une mise à jour sans git, ~/.claude ensuite.
# L'agent reconnaît lui-même le mode : installation, mise à jour ou entretien rejoué.
#
#   bash ~/.claude/lancer.sh [effort]
#
# effort : low, medium, high, xhigh ou max ; high par défaut. Il ne vaut que pour cette session et
# ne change aucun réglage ; /effort, tapé dans la session, le modifie en cours de route.
# Codes : celui de Claude Code ; 2 pour un appel fautif ou Claude Code introuvable.
set -eu

EFFORT="${1:-high}"
case "$EFFORT" in
    low|medium|high|xhigh|max) ;;
    *) echo "lancer.sh : niveau d'effort inconnu « $EFFORT » — low, medium, high, xhigh ou max." >&2
       exit 2 ;;
esac
command -v claude >/dev/null 2>&1 || {
    echo "lancer.sh : la commande claude est introuvable. Installez Claude Code d'abord (README, Prérequis)." >&2
    exit 2; }

cd "$(dirname "$0")"
exec claude --settings installateur/settings.installation.json --permission-mode auto \
    --effort "$EFFORT" --agent claudeos-installateur
