#!/usr/bin/env bash
# =============================================================================
# BUILD INDEX — ClaudeOS
# Génère le SQUELETTE auto-dérivé de memory/INDEX.md (carte de rappel transverse).
# - Couche AUTO (ce script) : extraction mécanique du corpus. Jamais éditée à la main.
# - Couche CURATÉE (## 🧭, maintenue par la distillation) : PRÉSERVÉE par ce script.
# Le script ne réécrit QUE le bloc entre <!-- AUTO:START --> et <!-- AUTO:END -->.
# =============================================================================
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

INDEX="$MEM/INDEX.md"

# Racines de scan = chemins LIVE de toutes les correspondances non-mémoire du
# manifeste (~/.claude + workstations + RESOURCES). Dérivées de claudeos_pairs :
# plus aucune liste codée en dur (corrige l'oubli historique de une workstation et
# RESOURCES). La mémoire auto ($MEM) reste traitée à part pour journal/feedbacks.
ROOTS=()
while IFS=$'\t' read -r live repo regime; do
    [[ "$regime" == "memory" ]] && continue
    ROOTS+=("$live")
done < <(claudeos_pairs)

mkdir -p "$MEM"

relp() { echo "${1/#$HOME/\~}"; }

gen_auto() {
    echo "<!-- AUTO:START — généré par build-index.sh, NE PAS éditer à la main -->"
    echo "## 🗂 Squelette (auto-généré le $(date +%Y-%m-%d))"
    echo

    echo "### Décisions stables — DESIGN.md"
    find "${ROOTS[@]}" -not -path '*/.sync-backups/*' \( -name "DESIGN.md" \) 2>/dev/null | sort | while read -r f; do
        [ -f "$f" ] || continue
        # Jointure par awk et NON par `paste -sd '·'`. Le délimiteur fait deux octets en
        # UTF-8, et certaines implémentations de `paste` traitent chaque OCTET d'un
        # délimiteur multi-octet comme un délimiteur distinct : elles alternent alors entre
        # les deux et produisent des octets de continuation orphelins, invalides seuls.
        # La cascade observée sur un autre poste : carte de rappel corrompue, puis
        # `impact.sh` qui la lit en UTF-8 strict et lève une UnicodeDecodeError non
        # rattrapée — son `except OSError` ne l'attrape pas, l'exception hérite de
        # ValueError —, puis l'autotest en échec, puis TOUTE sauvegarde bloquée, l'autotest
        # étant une porte avant le commit. Un délimiteur d'affichage a fait tomber la
        # clôture. `awk` joint sans regarder les octets du séparateur.
        secs=$(grep -E '^#{2,3} ' "$f" 2>/dev/null | sed -E 's/^#{2,3} //' \
               | awk '{ printf "%s%s", (NR>1 ? "·" : ""), $0 } END { if (NR) print "" }')
        [ -n "$secs" ] && echo "- **$(relp "$f")** \`[$(basename "$(dirname "$f")")]\` — ${secs}"
    done
    echo

    echo "### Journal & archives de session (par date)"
    for jf in "$MEM/SESSION_JOURNAL.md" "$MEM/SESSION_ARCHIVE.md"; do
        [ -f "$jf" ] || continue
        # Chemin neutre au poste, et non `relp` (2026-08-07) : le dossier de mémoire porte un
        # slug dérivé du dossier personnel, donc différent d'une machine à l'autre. `relp` y
        # écrivait le slug du poste générateur, et le fichier se synchronise tel quel — sur
        # l'autre machine le chemin n'existe pas, et un agent qui le suit conclut à l'absence
        # du journal. La convention `<MÉMOIRE>` est celle du règlement la conception
        echo "_<MÉMOIRE>/$(basename "$jf") :_"
        grep -E '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' "$jf" 2>/dev/null | sed -E 's/^## /  - /'
    done
    echo

    echo "### Feedbacks mémorisés"
    for ff in "$MEM"/feedback_*.md; do
        [ -f "$ff" ] || continue
        desc=$(grep -m1 -E '^description:' "$ff" 2>/dev/null | sed -E 's/^description:[[:space:]]*//; s/^"//; s/"$//')
        echo "- \`$(basename "$ff")\` — ${desc:-(sans description)}"
    done
    echo
    echo "<!-- AUTO:END -->"
}

# Scaffold complet si l'index n'existe pas
if [ ! -f "$INDEX" ]; then
    {
        echo "# INDEX — Carte de rappel ClaudeOS"
        echo "> Index de rappel transverse, écrit par l'assistant pour l'assistant. Lire/grep avant tout travail de fond."
        echo "> Deux couches : 🧭 carte thématique (curatée par la distillation) · 🗂 squelette (auto-généré, ne pas éditer)."
        echo
        echo "## 🧭 Carte thématique (curatée)"
        echo "<!-- Entrées sujet → pointeur, en langage naturel. Maintenue par la distillation (rituel + hebdo). -->"
        echo "_(vide — sera enrichie par la boucle de distillation)_"
        echo
        gen_auto
    } > "$INDEX"
    echo "[index] INDEX.md créé : $INDEX"
    exit 0
fi

# Sinon : remplacer uniquement le bloc AUTO, préserver la couche curatée
TMP=$(mktemp)
awk -v block="$(gen_auto)" '
    /<!-- AUTO:START/ {print block; skip=1}
    skip && /<!-- AUTO:END -->/ {skip=0; next}
    !skip {print}
' "$INDEX" > "$TMP" && mv "$TMP" "$INDEX"
echo "[index] Squelette régénéré dans $INDEX"
