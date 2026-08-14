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
# Un chemin présent dans l'empreinte et ABSENT de la nouvelle version a été retiré en
# amont. Même règle, pas une plus expéditive : constater, expliquer, proposer — et sans
# réponse, conserver. Ce qui est conservé est consigné (config/RETIRES_AMONT) et reconduit
# dans l'empreinte, pour que le constat survive aux mises à jour suivantes au lieu de
# laisser un fichier que plus rien ne nomme.
#
# Ce qui n'est PAS touché, jamais : le règlement assemblé à l'entretien, la mémoire, les
# dossiers de travail. Une mise à jour porte sur le moteur, les compétences et les
# styles de sortie — ce qui vient du squelette.
#
# Options :
#   --dry-run   n'écrit rien, dit ce qui serait fait — à lancer en premier, toujours
#   --ref <r>   version visée (étiquette, branche ou commit) ; par défaut la dernière
# =============================================================================
set -uo pipefail

# CE SCRIPT EST DANS LE PÉRIMÈTRE QU'IL MET À JOUR. Exécuté depuis sa place, il se
# recopiait sur lui-même en pleine boucle de copie ; bash, qui lit un script au fil de
# l'eau, reprenait sa lecture dans le fichier remplacé, à un décalage devenu faux —
# erreur de syntaxe et arrêt net AVANT le bilan des retirés, le résumé et la remise à
# jour des empreintes. Exercé sur pièce (v1.1.0 → v2.0.0 : « syntax error near
# unexpected token », sortie 2, empreintes laissées à l'ancienne version). L'essai à
# blanc, qui n'écrit rien, ne montrait rien. On s'exécute donc depuis une copie
# jetable : l'original redevient un fichier du périmètre comme les autres.
if [ -z "${UPDATE_COPIE:-}" ]; then
    _copie="$(mktemp)" || { echo "[update] ⛔ copie de travail impossible." >&2; exit 1; }
    cp "${BASH_SOURCE[0]}" "$_copie" || { echo "[update] ⛔ copie de travail impossible." >&2; exit 1; }
    UPDATE_COPIE="$_copie" UPDATE_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" \
        exec bash "$_copie" "$@"
fi
SELF="${UPDATE_SELF:?}"
DEPOT="$(dirname "$SELF")"
CONF="$SELF/config"
MANIFEST="$CONF/MANIFEST_INSTALL"
ORIGINE_F="$CONF/TEMPLATE_ORIGIN"
REGISTRE_RETIRES="$CONF/RETIRES_AMONT"
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

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP" "$UPDATE_COPIE"' EXIT
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
# Les retirés en amont encore à trancher, et les conservés à reconduire dans l'empreinte.
declare -a A_RETIRES=()
declare -a RETENUS=()

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

# --- Retirés en amont ---------------------------------------------------------------
# Ce qui a DISPARU de la nouvelle version n'est JAMAIS supprimé en silence : un fichier
# retiré en amont peut très bien être devenu le point d'appui de quelqu'un ici. On
# recense d'abord ; la proposition — et le choix, conserver par défaut — vient après le
# résumé, au même rang que l'arbitrage des fichiers modifiés.
while read -r _h rel dst_brut; do
    case "$_h" in ''|'#'*) continue ;; esac
    [ -f "$NEUF/$rel" ] && continue
    dst="$(eval echo "$dst_brut")"
    if [ ! -e "$dst" ]; then
        # Déjà parti localement : la ligne de registre, s'il y en a une, ment — on la purge.
        if [ "$DRY" != 1 ] && [ -f "$REGISTRE_RETIRES" ] && grep -qF "  $rel  " "$REGISTRE_RETIRES"; then
            grep -vF "  $rel  " "$REGISTRE_RETIRES" > "$REGISTRE_RETIRES.tmp" \
                && mv "$REGISTRE_RETIRES.tmp" "$REGISTRE_RETIRES"
        fi
        continue
    fi
    ABSENTS=$((ABSENTS+1))
    if [ -f "$REGISTRE_RETIRES" ] && grep -qF "  $rel  " "$REGISTRE_RETIRES"; then
        # Déjà tranché à un passage précédent : on le rappelle en une ligne, sans
        # redemander — le choix est consigné, il reste révocable à la main.
        echo "  ? $dst  (retiré en amont, conservé par ton choix — consigné dans $REGISTRE_RETIRES)"
        RETENUS+=("$_h  $rel  $dst_brut")
        continue
    fi
    echo "  ? $dst  (retiré en amont — à trancher plus bas, conservé par défaut)"
    A_RETIRES+=("$_h|$rel|$dst_brut")
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
        # 2>/dev/null AVANT </dev/tty : les redirections s'appliquent de gauche à droite,
        # et c'est la première qui doit avaler l'erreur « pas de terminal » de la seconde.
        read -r rep 2>/dev/null </dev/tty || rep=""
        case "$rep" in
            o|O|oui|Oui) cp "$NEUF/$rel" "$dst"; ECRITS+=("$rel"); echo "  → remplacé" ;;
            *) echo "  → conservé (ta version)" ;;
        esac
    done
fi

# Consigner un conservé : le registre est ce qui empêche le demi-état muet. Il dit ce qui
# reste, pourquoi c'est resté, et que plus rien ne le route — lisible à tout moment, purgé
# de lui-même quand le fichier disparaît.
_consigne_conserve() {  # $1 = chemin squelette, $2 = chemin installé
    if [ ! -f "$REGISTRE_RETIRES" ]; then
        {
            echo "# RETIRES_AMONT — fichiers que le squelette ne livre plus, conservés ici par choix."
            echo "# Une ligne par fichier : <date>  <chemin squelette>  <chemin installé>  <retiré en>"
            echo "# Écrit par update.sh. Ces fichiers n'évoluent plus avec les mises à jour et plus"
            echo "# rien ne les route dans le squelette : ils ne servent que si tu y as construit"
            echo "# quelque chose. Supprimer le fichier suffit pour sortir d'ici — la mise à jour"
            echo "# suivante purge la ligne d'elle-même."
        } > "$REGISTRE_RETIRES"
    fi
    grep -qF "  $1  " "$REGISTRE_RETIRES" \
        || printf '%s  %s  %s  %s\n' "$(date +%F)" "$1" "$2" "$REF" >> "$REGISTRE_RETIRES"
}

# Supprimer un retiré : LES DEUX EXEMPLAIRES PARTENT ENSEMBLE. Le dossier de configuration
# est sauvegardé en régime additif : la sauvegarde ne propage jamais une suppression.
# Retirer le seul exemplaire vivant laisse le miroir du dépôt en place, et le contrôle de
# dérive (« fichier du dépôt absent en live ») bloque la sauvegarde suivante — même leçon
# que l'assembleur de règles, payée sur pièce. Le miroir se retire donc ici, et la
# prochaine sauvegarde committe la disparition.
_supprime_retire() {  # $1 = chemin squelette, $2 = chemin installé
    rm -f "$2"
    local rel_home="${2#"$HOME"/}" miroir="" loc repo regime _reste
    if [ -f "$CONF/SYNC_MAP" ]; then
        while read -r loc repo regime _reste; do
            case "$loc" in ''|'#'*) continue ;; esac
            [ "$regime" = "additive" ] || continue
            case "$rel_home" in "$loc"/*) miroir="$DEPOT/$repo/${rel_home#"$loc"/}"; break ;; esac
        done < "$CONF/SYNC_MAP"
    fi
    [ -n "$miroir" ] && [ -f "$miroir" ] && rm -f "$miroir"
    # Le dossier parent, s'il ne reste que lui : un dossier vide que plus rien ne remplit
    # est le même demi-état qu'un fichier orphelin, en plus discret.
    rmdir "$(dirname "$2")" 2>/dev/null || true
    [ -n "$miroir" ] && { rmdir "$(dirname "$miroir")" 2>/dev/null || true; }
    if [ -f "$REGISTRE_RETIRES" ] && grep -qF "  $1  " "$REGISTRE_RETIRES"; then
        grep -vF "  $1  " "$REGISTRE_RETIRES" > "$REGISTRE_RETIRES.tmp" \
            && mv "$REGISTRE_RETIRES.tmp" "$REGISTRE_RETIRES"
    fi
}

if [ "${#A_RETIRES[@]}" -gt 0 ]; then
    echo
    echo "[update] Fichiers que ta version installée avait posés et que la version $REF ne livre plus."
    echo "         Le squelette ne les route plus : si tu n'y as rien construit, ils ne servent"
    echo "         plus à rien. RIEN N'EST SUPPRIMÉ SANS TON ACCORD — sans réponse, le fichier est"
    echo "         conservé, et ce choix est consigné dans :"
    echo "           $REGISTRE_RETIRES"
    for entree in "${A_RETIRES[@]}"; do
        h_anc="${entree%%|*}"; reste="${entree#*|}"
        rel="${reste%%|*}"; dst_brut="${reste#*|}"
        dst="$(eval echo "$dst_brut")"
        echo
        echo "──────── $dst"
        echo "  Posé par ta version installée ($rel) · retiré de la version $REF."
        # Si le règlement personnel — jamais touché par une mise à jour — cite encore ce
        # fichier ou son dossier, le supprimer laisse un chemin mort : l'autotest le
        # signalera et la sauvegarde sera refusée jusqu'à la remise à jour du règlement.
        # La personne doit le savoir AVANT de répondre, pas le découvrir au refus.
        _dossier_tilde="~${dst#"$HOME"}"; _dossier_tilde="${_dossier_tilde%/*}/"
        _fin_chemin="$(basename "$(dirname "$dst")")/$(basename "$dst")"
        if [ -f "$HOME/.claude/CLAUDE.md" ] \
           && grep -qF -e "$_fin_chemin" -e "$_dossier_tilde" "$HOME/.claude/CLAUDE.md"; then
            echo "  ⚠ Ton règlement (~/.claude/CLAUDE.md) cite encore ce fichier ou son dossier."
            echo "    Supprimé, ce chemin devient mort : l'autotest le signalera et la sauvegarde"
            echo "    sera refusée tant que le règlement n'est pas remis à jour (une session de"
            echo "    l'assistant sait faire cette retouche). Conserver ne coûte rien."
        fi
        if [ "$DRY" = 1 ]; then
            echo "  (essai à blanc — la question sera posée au passage réel ; défaut : conserver)"
            continue
        fi
        printf '  Supprimer ce fichier, et son miroir dans le dépôt de sauvegarde ? [o/N] '
        # Même ordre de redirections que l'arbitrage : l'erreur « pas de terminal » se tait,
        # et l'absence de réponse CONSERVE.
        read -r rep 2>/dev/null </dev/tty || rep=""
        case "$rep" in
            o|O|oui|Oui) _supprime_retire "$rel" "$dst"; echo "  → supprimé, miroir de sauvegarde compris" ;;
            *) _consigne_conserve "$rel" "$dst"
               RETENUS+=("$h_anc  $rel  $dst_brut")
               echo "  → conservé, consigné au registre" ;;
        esac
    done
fi

# Les artefacts de configuration que seule l'installation posait — fichier des créneaux,
# lignes de liste blanche apparues avec une version. La NOUVELLE version les décrit en un
# seul lieu, engine/provision-config.sh, appelé ici comme install.sh l'appelle : sans ce
# rattrapage, une mise à jour laissait l'autotest en défaut (chemin cité par une règle
# mais jamais posé) et la sauvegarde refusée. Exercé sur pièce (v1.1.0 → v2.0.0).
# Idempotent : il ne crée que ce qui manque, il n'écrase aucune décision locale.
if [ -f "$NEUF/engine/provision-config.sh" ]; then
    if [ "$DRY" = 1 ]; then
        echo
        echo "[update] (essai à blanc — le rattrapage de configuration tournerait ici : engine/provision-config.sh)"
    else
        bash "$NEUF/engine/provision-config.sh" \
            || echo "[update] ⚠ rattrapage de configuration en échec — l'autotest dira ce qui manque." >&2
    fi
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
    # Les retirés en amont CONSERVÉS sont reconduits, avec leur empreinte d'origine. Sans
    # cette reconduction, ils sortaient de l'empreinte au premier passage et le signalement
    # ne survivait qu'une fois : dès la mise à jour suivante, plus rien ne nommait ces
    # fichiers — un demi-état muet, précisément ce que tout ce bloc combat. Reconduits, ils
    # sont re-signalés à chaque passage (une ligne, sans re-question), et si une version
    # future les fait revenir, la comparaison à trois points reprend ses droits.
    for entree in "${RETENUS[@]:-}"; do
        [ -n "$entree" ] || continue
        printf '%s\n' "$entree"
    done
} > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"

echo "[update] Empreintes remises à jour."
echo "[update] Relance l'autotest avant de sauvegarder :  bash $SELF/selftest.sh"
