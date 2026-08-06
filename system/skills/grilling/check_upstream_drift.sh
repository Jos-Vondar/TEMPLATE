#!/usr/bin/env bash
# Vérifie si l'amont (mattpocock/skills · grilling) a divergé du CORPS local du skill.
# - S'auto-limite à une vérification par mois (marqueur .last_upstream_check).
# - Compare uniquement le corps (le frontmatter local est personnalisé FR : ignoré).
# - Fail-silent si hors-ligne (retry au prochain boot).
# - N'ÉCRIT JAMAIS le skill : alerte seulement. L'adoption reste une décision manuelle.
# Usage: check_upstream_drift.sh          -> vérif mensuelle silencieuse (hook boot)
#        check_upstream_drift.sh --force  -> force la vérif maintenant
#        check_upstream_drift.sh --show   -> affiche le diff corps amont/local
set -uo pipefail
SKILL="$HOME/.claude/skills/grilling/SKILL.md"
MARKER="$HOME/.claude/skills/grilling/.last_upstream_check"
URL="https://raw.githubusercontent.com/mattpocock/skills/main/skills/productivity/grilling/SKILL.md"
MONTH=$(date +%Y-%m)
MODE="${1:-}"

# corps = tout ce qui suit le 2e '---' (on saute le frontmatter)
body() { awk 'BEGIN{d=0} /^---[[:space:]]*$/{d++; next} d>=2{print}' "$1"; }

[ "$MODE" != "--force" ] && [ "$MODE" != "--show" ] && \
  [ "$(cat "$MARKER" 2>/dev/null || true)" = "$MONTH" ] && exit 0

TMP=$(mktemp) || exit 0
if ! curl -fsSL --max-time 15 "$URL" -o "$TMP" 2>/dev/null; then
  rm -f "$TMP"; exit 0   # hors-ligne : on retentera au prochain boot
fi
UP=$(body "$TMP"); LOC=$(body "$SKILL")

if [ "$MODE" = "--show" ]; then
  echo "=== amont (mattpocock/skills) ==="; echo "$UP"
  echo; echo "=== local (corps) ==="; echo "$LOC"
  echo; echo "=== diff (amont -> local) ==="
  diff <(printf '%s\n' "$UP") <(printf '%s\n' "$LOC") || true
  rm -f "$TMP"; exit 0
fi

rm -f "$TMP"
echo "$MONTH" > "$MARKER"
if [ "$UP" != "$LOC" ]; then
  echo "⚠️ Skill grill : le corps amont (mattpocock/skills) a divergé du tien. Lance \`bash ~/.claude/skills/grilling/check_upstream_drift.sh --show\` pour voir le diff, puis décide d'adopter (garde ton en-tête FR)."
fi
