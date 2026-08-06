#!/usr/bin/env bash
# =============================================================================
# UPDATE — passer à une nouvelle version du squelette sans réinstaller.
#
# Trois points de comparaison par fichier, et c'est tout le mécanisme :
#   1. l'empreinte prise à l'installation (ce que la version précédente avait posé),
#   2. le fichier local d'aujourd'hui,
#   3. le fichier de la nouvelle version.
#
#   local == empreinte  → personne n'y a touché : on remplace, sans rien demander.
#   local != empreinte  → la personne l'a modifié : on montre le diff et on demande,
#                         et SANS RÉPONSE ON GARDE SA VERSION. Le défaut ne détruit jamais.
#
# Ce qui n'est PAS touché, jamais : le règlement assemblé à l'entretien, la mémoire, les
# dossiers de travail. Une mise à jour porte sur le moteur, les fiches et les compétences.
#
# Options :
#   --dry-run   n'écrit rien, dit ce qui serait fait — à lancer en premier, toujours
#   --ref <r>   version visée (étiquette, branche ou commit) ; par défaut la dernière
# =============================================================================
set -uo pipefail
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SELF/config"
MANIFEST="$CONF/MANIFEST_INSTALL"
ORIGINE_F="$CONF/TEMPLATE_ORIGIN"
DRY=0; REF=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY=1; shift ;;
        --ref) REF="${2-}"; shift 2 ;;
        # Aucun argument inconnu n'est toléré : une option mal tapée qui serait ignorée en
        # silence ferait croire à un essai à blanc alors que l'écriture aurait bien lieu.
        *) echo "update.sh : argument inconnu « $1 ». Options : --dry-run, --ref <version>" >&2; exit 2 ;;
    esac
done

mort() { echo "[update] ⛔ $*" >&2; exit 1; }

[ -f "$MANIFEST" ] || mort "aucune empreinte d'installation ($MANIFEST).
     Cette installation est antérieure au mécanisme de mise à jour. Sans empreinte, on ne
     peut pas distinguer tes modifications de celles de la version précédente, et une mise
     à jour écraserait ton travail sans le savoir. Relance install.sh une fois : il pose
     l'empreinte sans rien changer d'autre."
[ -f "$ORIGINE_F" ] || mort "dépôt d'origine du squelette inconnu ($ORIGINE_F)."
ORIGINE="$(grep -v '^#' "$ORIGINE_F" | head -1)"
[ -n "$ORIGINE" ] || mort "dépôt d'origine vide dans $ORIGINE_F."

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "[update] Récupération de $ORIGINE${REF:+ (version $REF)}..."
git clone --quiet "$ORIGINE" "$TMP/neuf" 2>/dev/null || mort "clonage impossible depuis $ORIGINE."
if [ -n "$REF" ]; then
    git -C "$TMP/neuf" checkout --quiet "$REF" 2>/dev/null || mort "version « $REF » introuvable dans $ORIGINE."
else
    # La dernière ÉTIQUETTE, pas la pointe de la branche : la pointe peut porter du travail
    # en cours. Une mise à jour vise une version publiée. À défaut d'étiquette, la branche.
    _tag="$(git -C "$TMP/neuf" tag --sort=-v:refname | head -1)"
    [ -n "$_tag" ] && { git -C "$TMP/neuf" checkout --quiet "$_tag"; REF="$_tag"; } || REF="(branche par défaut)"
fi
echo "[update] Version visée : $REF"

NEUF="$TMP/neuf"
[ -f "$NEUF/engine/manifest.sh" ] || mort "le dépôt récupéré ne ressemble pas au squelette."

# Empreintes de la NOUVELLE version, calculées sur son propre arbre.
bash "$NEUF/engine/manifest.sh" "$NEUF" "$TMP/manifest-neuf" >/dev/null 2>&1 \
    || mort "impossible de calculer les empreintes de la nouvelle version."

INTACTS=0; MODIFIES=0; NOUVEAUX=0; IDENTIQUES=0; ABSENTS=0
declare -a A_ARBITRER=()
# La liste de ce qu'on a RÉELLEMENT écrit. Elle seule décide quelles empreintes bougent à la
# fin — voir le commentaire du bloc de réécriture, qui explique pourquoi c'est là que se joue
# la correction du second passage.
declare -a ECRITS=()

while read -r h_neuf rel dst_brut; do
    case "$h_neuf" in ''|'#'*) continue ;; esac
    dst="$(eval echo "$dst_brut")"
    src="$NEUF/$rel"
    h_pose="$(grep -F "  $rel  " "$MANIFEST" 2>/dev/null | head -1 | cut -d' ' -f1)"

    if [ ! -e "$dst" ]; then
        NOUVEAUX=$((NOUVEAUX+1))
        echo "  + $dst  (nouveau dans cette version)"
        [ "$DRY" = 1 ] || { mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"; ECRITS+=("$rel"); }
        continue
    fi
    h_local="$(sha256sum "$dst" | cut -d' ' -f1)"
    [ "$h_local" = "$h_neuf" ] && { IDENTIQUES=$((IDENTIQUES+1)); continue; }

    if [ -n "$h_pose" ] && [ "$h_local" = "$h_pose" ]; then
        # Intact depuis l'installation : la personne n'y a jamais touché, rien à arbitrer.
        INTACTS=$((INTACTS+1))
        echo "  ↑ $dst"
        [ "$DRY" = 1 ] || { cp "$src" "$dst"; ECRITS+=("$rel"); }
    else
        # Modifié à la main — ou posé par une version encore antérieure au manifeste. Dans
        # les deux cas on ne sait pas, et quand on ne sait pas on ne détruit pas.
        MODIFIES=$((MODIFIES+1))
        A_ARBITRER+=("$rel|$dst")
    fi
done < "$TMP/manifest-neuf"

# Ce qui a DISPARU de la nouvelle version est signalé et jamais supprimé : un fichier retiré
# en amont peut très bien être devenu le point d'appui de quelqu'un ici.
while read -r _h rel dst_brut; do
    case "$_h" in ''|'#'*) continue ;; esac
    [ -f "$NEUF/$rel" ] && continue
    dst="$(eval echo "$dst_brut")"
    [ -e "$dst" ] && { ABSENTS=$((ABSENTS+1)); echo "  ? $dst  (retiré en amont, conservé ici)"; }
done < "$MANIFEST"

echo
echo "[update] $IDENTIQUES inchangé(s) · $INTACTS mis à jour · $NOUVEAUX ajouté(s) · ${#A_ARBITRER[@]} à arbitrer · $ABSENTS retiré(s) en amont"

if [ "${#A_ARBITRER[@]}" -gt 0 ]; then
    echo
    echo "[update] Fichiers que tu as modifiés et que la nouvelle version modifie aussi."
    echo "         Ta version est conservée par défaut — répondre « o » pour prendre la neuve."
    for entree in "${A_ARBITRER[@]}"; do
        rel="${entree%%|*}"; dst="${entree#*|}"
        echo
        echo "──────── $dst"
        diff -u --label "à toi : $dst" --label "version $REF" "$dst" "$NEUF/$rel" | head -60
        if [ "$DRY" = 1 ]; then
            echo "  (essai à blanc — rien n'est écrit)"
            continue
        fi
        printf '  Remplacer par la version %s ? [o/N] ' "$REF"
        read -r rep </dev/tty 2>/dev/null || rep=""
        case "$rep" in
            o|O|oui|Oui) cp "$NEUF/$rel" "$dst"; ECRITS+=("$rel"); echo "  → remplacé" ;;
            *) echo "  → conservé (ta version)" ;;
        esac
    done
fi

if [ "$DRY" = 1 ]; then
    echo
    echo "[update] Essai à blanc — rien n'a été écrit. Relance sans --dry-run pour appliquer."
    exit 0
fi

# L'EMPREINTE N'EST MISE À JOUR QUE POUR LES FICHIERS RÉELLEMENT ÉCRITS, et c'est le point
# le plus facile à rater de tout ce script. La version évidente — relire l'état local et tout
# ré-empreindre — est fausse au SECOND passage : un fichier que la personne a choisi de
# garder verrait son empreinte devenir sa propre version, donc « local == empreinte », donc
# « intact », donc écrasé sans un mot à la mise à jour suivante. Son choix ne survivrait
# qu'une fois. On conserve donc l'empreinte D'ORIGINE pour tout ce qu'on n'a pas écrit :
# c'est elle qui porte l'information « cette personne a divergé », et elle doit durer.
{
    echo "# Empreintes de l'état installé, après mise à jour vers $REF."
    echo "# <sha256>  <chemin dans le squelette>  <chemin installé>"
    echo "# Un fichier conservé par choix garde l'empreinte de la version qui l'a posé :"
    echo "# c'est ce qui fait qu'on le redemandera au lieu de l'écraser."
    while read -r _h rel dst_brut; do
        case "$_h" in ''|'#'*) continue ;; esac
        dst="$(eval echo "$dst_brut")"
        [ -f "$dst" ] || continue
        if printf '%s\n' "${ECRITS[@]:-}" | grep -qxF -- "$rel"; then
            printf '%s  %s  %s\n' "$(sha256sum "$dst" | cut -d' ' -f1)" "$rel" "$dst_brut"
        else
            _anc="$(grep -F "  $rel  " "$MANIFEST" 2>/dev/null | head -1 | cut -d' ' -f1)"
            printf '%s  %s  %s\n' "${_anc:-inconnue}" "$rel" "$dst_brut"
        fi
    done < "$TMP/manifest-neuf"
} > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"

echo "[update] Empreintes remises à jour."
echo "[update] Relance l'autotest avant de sauvegarder :  bash $SELF/selftest.sh"
