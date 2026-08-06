#!/usr/bin/env bash
# =============================================================================
# MANIFEST — empreinte de ce qu'une version a posé, et où.
#
# Sans ce fichier, une mise à jour ne peut pas distinguer « ce fichier a été modifié par
# l'utilisateur » de « ce fichier a été modifié par la version précédente ». Les deux se
# présentent pareil : un fichier local qui diffère de la nouvelle version. Confondre les
# deux, c'est soit écraser du travail, soit ne jamais rien mettre à jour.
#
# L'empreinte prise À L'INSTALLATION est le troisième point de comparaison qui lève
# l'ambiguïté : local == empreinte → intact, on remplace ; local != empreinte → touché par
# la personne, on demande.
#
# Usage : manifest.sh <racine-du-squelette> <fichier-de-sortie>
# =============================================================================
set -uo pipefail
RACINE="${1:?racine du squelette attendue}"
SORTIE="${2:?fichier de sortie attendu}"

# LA CARTE, source unique du périmètre géré. Format : <chemin dans le squelette>|<destination>
# Ce qui n'y figure pas n'est jamais touché par une mise à jour — en particulier le règlement
# assemblé et la mémoire, qui appartiennent à la personne et à elle seule. Les y inclure
# ferait d'une mise à jour une réinstallation, ce qu'on cherche précisément à éviter.
carte() {
    printf '%s\n' \
        "engine|\$HOME/.claudeos/engine" \
        "system/fiches|\$HOME/.claude/fiches" \
        "system/skills|\$HOME/.claude/skills" \
        "resources|\$HOME/resources"
    # Les documents de racine, un par un : `CLAUDE.md` est EXCLU volontairement, c'est le
    # règlement assemblé à l'entretien. L'écraser rendrait à la personne les règles de
    # quelqu'un d'autre, ce que toute la conception s'emploie à éviter.
    for f in DESIGN.md RULES_CATALOG.md RTK.md; do
        [ -f "$RACINE/system/$f" ] && printf 'system/%s|$HOME/.claude/%s\n' "$f" "$f"
    done
}

{
    echo "# Empreintes de la version installée. Une ligne par fichier :"
    echo "# <sha256>  <chemin dans le squelette>  <chemin installé>"
    echo "# Lu par update.sh pour distinguer un fichier intact d'un fichier modifié à la main."
    carte | while IFS='|' read -r src dst; do
        [ -n "$src" ] || continue
        if [ -d "$RACINE/$src" ]; then
            find "$RACINE/$src" -type f | sort | while read -r f; do
                rel="${f#$RACINE/}"
                printf '%s  %s  %s\n' "$(sha256sum "$f" | cut -d' ' -f1)" "$rel" "$dst/${f#$RACINE/$src/}"
            done
        elif [ -f "$RACINE/$src" ]; then
            printf '%s  %s  %s\n' "$(sha256sum "$RACINE/$src" | cut -d' ' -f1)" "$src" "$dst"
        fi
    done
} > "$SORTIE"

echo "[manifest] $(grep -vc '^#' "$SORTIE") empreinte(s) écrite(s) dans $SORTIE"
