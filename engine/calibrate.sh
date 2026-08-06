#!/usr/bin/env bash
# =============================================================================
# CALIBRATE — écrit `config/SEUILS`, les bornes des alarmes de dérive de poids.
#
# Motif. Les trois seuils de `selftest.sh` sont des constantes calibrées sur UN
# corpus. Portés tels quels sur un corpus d'une autre taille, ils ne mesurent
# plus rien : trop hauts, l'alarme ne parle jamais ; trop bas, elle crie sur du
# travail ordinaire, et un signal dont on sait qu'il ne veut rien dire apprend à
# ignorer la catégorie entière.
#
# Ce script mesure l'assiette RÉELLE et ajoute une marge. Il ne surveille rien :
# il pose le point zéro à partir duquel la dérive se voit.
#
# À lancer : après l'installation, après l'assemblage du règlement, et après
# toute réorganisation qui change la taille du corpus de façon voulue. Jamais
# pour faire taire une alarme — relever un seuil parce qu'il sonne est un
# contournement, et le sonnerait à nouveau au double.
#
#   calibrate.sh            écrit config/SEUILS
#   calibrate.sh --montrer  mesure et affiche, n'écrit rien
# =============================================================================
set -uo pipefail
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF/config.sh"

ECRIRE=1
case "${1:-}" in
    "")         ;;
    --montrer)  ECRIRE=0 ;;
    *) echo "calibrate : argument inconnu '$1'. Attendu : rien, ou --montrer." >&2; exit 2 ;;
esac

# Marge de 25 %. Assez pour absorber plusieurs semaines d'écriture ordinaire,
# assez serrée pour qu'un doublement se voie. Un arrondi au millier supérieur
# évite les seuils à six chiffres significatifs, qui donnent l'illusion d'une
# précision que la mesure n'a pas.
marge() { python3 -c 'import sys,math;print(int(math.ceil(int(sys.argv[1])*1.25/1000.0))*1000)' "$1"; }

# Les trois mesures reproduisent EXACTEMENT celles de selftest.sh. Si l'une des
# deux dérive de l'autre, le seuil ne borne plus ce qu'il croit borner — c'est le
# défaut classique d'un seuil recopié d'une mesure voisine.
_layer=$(python3 -c '
import os, sys
print(sum(len(open(p, encoding="utf-8").read()) for p in sys.argv[1:] if os.path.exists(p)))
' "$HOME/.claude/CLAUDE.md" "$HOME/.claude/RTK.md" "$MEM/MEMORY.md" 2>/dev/null || echo 0)
_boot=$(bash "$SELF/boot-check.sh" 2>/dev/null | python3 -c '
import json, sys, re
t = json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]
t = re.sub(r"--- ALERTES ---.*?(?=--- )", "", t, flags=re.S)
print(len(t))
' 2>/dev/null || echo 0)
_sheets=$(python3 -c '
import sys, glob
print(sum(len(open(p, encoding="utf-8").read()) for p in sorted(glob.glob(sys.argv[1]))))
' "$HOME/.claude/fiches/*.md" 2>/dev/null || echo 0)

# Une mesure nulle n'est pas une petite mesure : c'est une mesure ratée. Écrire un
# seuil dessus désarmerait l'alarme en silence, ce qui est exactement le mode de
# panne que ce système refuse.
for _n in _layer _boot _sheets; do
    if [ "${!_n}" -le 0 ]; then
        echo "[calibrate] ⛔ mesure nulle pour ${_n#_} — rien n'est écrit." >&2
        echo "[calibrate]    Une mesure à zéro est une mesure ratée, pas un petit corpus." >&2
        exit 1
    fi
done

L=$(marge "$_layer"); B=$(marge "$_boot"); S=$(marge "$_sheets")

printf '[calibrate] couche par session : %s car. → seuil %s\n' "$_layer" "$L"
printf '[calibrate] bilan de démarrage : %s car. → seuil %s\n' "$_boot" "$B"
printf '[calibrate] corpus des fiches  : %s car. → seuil %s\n' "$_sheets" "$S"

[ "$ECRIRE" = 1 ] || { echo "[calibrate] --montrer : rien n'a été écrit."; exit 0; }

mkdir -p "$SELF/config"
cat > "$SELF/config/SEUILS" <<SEUILS
# Bornes des alarmes de dérive de poids. Écrit par calibrate.sh, lu par selftest.sh.
# Mesure + 25 %. Ce ne sont pas des quotas : ils attrapent une réaccumulation
# silencieuse, ils n'arbitrent aucune règle. Les relever est une décision.
_LAYER_MAX=$L
_BOOT_MAX=$B
_SHEETS_GROWTH_MAX=$S
SEUILS
echo "[calibrate] ✅ config/SEUILS écrit."
