#!/usr/bin/env bash
# =============================================================================
# install-poste.sh — met un poste en état de marche, et le remet en état après coup.
# IDEMPOTENT : se relance sans risque, à tout moment.
#
# Il fait les gestes qu'un dépôt git ne peut pas faire lui-même, parce que leur objet vit hors
# dépôt ou sous `.git/`, que git ne suit pas :
#   1. vérifier les dépôts (le système, et les dossiers de travail en dépôt par domaine) et leur
#      remote ;
#   2. poser les shims de hooks — un shim absent est MUET, le dépôt committerait sans alarme ;
#   2 bis. poser le pilote de fusion des journaux ; 2 ter. poser la liste noire en dépôt unique ;
#   3. vérifier la mémoire automatique ;
#   4. vérifier la ligne de démarrage du shell, puis 4 bis poser le bloc de titre de `~/.zshrc`
#      quand `reglages/zshrc-claudeos.zsh` en porte un ;
#   5. poser l'identité git ;
#   6. poser les raccourcis `_ign` vers le `_IGNORE/` de chaque projet qui en porte un rempli ;
# et dire ce qu'il n'a pas pu faire, plutôt que de le faire à moitié.
#
# CE QU'IL NE FAIT PAS, volontairement : écraser du travail local ou un réglage déjà en place.
# Un poste qui porte une V1 ou une V2 du template passe par la migration de l'agent livré,
# jamais par ceci.
# SANS GIT (`GIT=aucun`), il n'y a ni dépôt, ni shim, ni pilote de fusion : ces trois étapes
# se sautent en le disant, et la marque de la racine sans git, `.claudeos-racine`, se pose.
# =============================================================================
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# `config.sh` porte la queue du chemin de shim, `$REG` et la lecture des réglages ; sans lui,
# `set -u` arrête le script.
source "$SELF/config.sh"
SYS="$HOME/.claude"
# Les dépôts du poste, selon le régime : la liste vient de `claudeos_repos`.
# `while read` et non `mapfile` : `mapfile` n'existe qu'à partir de bash 4.0, et macOS livre le
# 3.2 — sous lui, le script ne ferait RIEN.
_DEPOTS=(); while IFS= read -r _d; do [ -n "$_d" ] && _DEPOTS+=("$_d"); done < <(claudeos_repos)
HOOK_SRC="$SELF/hooks/pre-commit-alarmes.sh"
SHIM_TAIL="$CLAUDEOS_SHIM_TAIL"   # source unique : config.sh

n=0; w=0
did() { echo "[install] ✅ $1"; n=$((n+1)); }
warn() { echo "[install] ⚠ $1" >&2; w=$((w+1)); }
# Une ligne de SUITE — la commande à lancer, la précision — s'écrit comme un avertissement mais
# ne compte pas : sinon un seul empêchement en annoncerait plusieurs.
suite() { echo "[install] ⚠ $1" >&2; }

_GIT_REGIME="$(claudeos_reponse GIT 2>/dev/null)" || _GIT_REGIME=""
if [ "$_GIT_REGIME" = "aucun" ]; then
    echo "[install] ⏭ régime sans git : aucun dépôt, aucun shim, aucun pilote de fusion à poser."
    # La marque de la racine sans git : `etat.py` et le crochet résolvent par elle les niveaux que
    # git résoudrait (`regime.py`). Un fichier vide, à la racine de ~/.claude.
    if [ ! -f "$SYS/.claudeos-racine" ]; then
        : > "$SYS/.claudeos-racine" && did "racine sans git marquée (~/.claude/.claudeos-racine)"
    fi
    # LA RÉFÉRENCE DE DÉPART des empreintes : l'état LIVRÉ. En régime GitHub, les fichiers du template
    # arrivent DÉJÀ COMMITÉS par le bouton, et le crochet de l'installateur ne les voit jamais comme
    # ajoutés ; sans cette référence, la première clôture sans git les contrôlerait tous comme neufs —
    # et refuserait au nom `controle-secrets.sh` (code 13), qui n'est pas un secret. Posée une fois :
    # réécrite plus tard, elle ferait de l'état présent la référence sans rien en contrôler.
    if [ ! -f "$SYS/.claudeos/empreintes/MANIFESTE.json" ]; then
        _ref="$(python3 "$SELF/regime.py" ecrit "$SYS" 2>&1)" \
            && did "référence de départ des empreintes posée — l'état livré : ${_ref##*: }" \
            || warn "référence de départ des empreintes NON posée : $_ref"
    fi
else
# --- 1. Les dépôts ------------------------------------------------------------
# L'URL de chaque dépôt est celle que git connaît : aucun fichier ne la recopie. Poser le dépôt
# système la première fois est le geste de l'agent d'installation, pas de ce script.
if [ ! -d "$SYS/.git" ]; then
    warn "~/.claude n'est pas un dépôt git — c'est l'agent d'installation qui le pose : bash ~/claudeos-amorce/lancer.sh"
fi
for _d in "${_DEPOTS[@]}"; do
    if [ -d "$_d/.git" ] && [ -z "$(git -C "$_d" remote 2>/dev/null)" ]; then
        warn "le dépôt ${_d/#$HOME/$CLAUDEOS_TILDE} n'a pas de remote — pose-le : git -C $_d remote add origin <url>"
    fi
done

# --- 2. Les shims de hooks ----------------------------------------------------
_shim() {
    local repo="$1" nom="$2" shim="$1/.git/hooks/pre-commit"
    [ -d "$repo/.git" ] || return 0
    [ -r "$HOOK_SRC" ] || { warn "$HOOK_SRC introuvable — shim non posé sur $nom."; return 0; }
    if [ ! -x "$shim" ] || ! grep -qF "$SHIM_TAIL" "$shim" 2>/dev/null; then
        mkdir -p "$(dirname "$shim")"
        printf '#!/usr/bin/env bash\n# Shim pose par install-poste.sh. Un shim ABSENT est MUET.\nexec bash "$HOME/%s"\n' "$SHIM_TAIL" > "$shim"
        chmod +x "$shim" && did "shim pre-commit posé sur $nom (alarmes au goulot)"
    fi
}
_shim "$SYS" "le dépôt système"
for _d in "${_DEPOTS[@]}"; do
    [ "$_d" = "$HOME/.claude" ] && continue
    _shim "$_d" "le dépôt ${_d/#$HOME/$CLAUDEOS_TILDE}"
done

# --- 2 bis. Le pilote de fusion des journaux ----------------------------------
# Même famille que les shims : git ne suit pas `.git/config`, donc ce réglage ne voyage PAS
# avec le clone et doit se reposer sur chaque poste. Le motif, le comportement de `union` et
# pourquoi c'est ici et non dans un fichier suivi : `engine/config/gitattributes-journal`,
# seule source. Ce script ne le recopie pas.
ATTR_SRC="$SELF/config/gitattributes-journal"
_attr() {
    local repo="$1" nom="$2" actuel
    [ -d "$repo/.git" ] || return 0
    [ -r "$ATTR_SRC" ] || { warn "$ATTR_SRC introuvable — pilote de fusion non posé sur $nom."; return 0; }
    actuel="$(git -C "$repo" config --get core.attributesFile 2>/dev/null || true)"
    if [ "$actuel" != "$ATTR_SRC" ]; then
        git -C "$repo" config core.attributesFile "$ATTR_SRC" \
            && did "pilote de fusion posé sur $nom (journal/*.jsonl merge=union)"
    fi
}
_attr "$SYS" "le dépôt système"
for _d in "${_DEPOTS[@]}"; do
    [ "$_d" = "$HOME/.claude" ] && continue
    _attr "$_d" "le dépôt ${_d/#$HOME/$CLAUDEOS_TILDE}"
done

# --- 2 ter. La liste noire en dépôt unique ------------------------------------
# En `GIT=unique`, les dossiers de travail vivent sous `~/.claude/travail/` : aucun `.gitignore`
# de dépôt client ne les garde. La référence part donc dans le `.git/info/exclude` de
# `~/.claude` — non suivi, donc reposé ici sur chaque poste —, et le contrôle 11 du crochet
# l'exige ligne à ligne. On AJOUTE ce qui manque, on ne retire jamais rien.
if [ "$_GIT_REGIME" = "unique" ] && [ -d "$SYS/.git" ]; then
    _EXCL="$SYS/.git/info/exclude"; _ajouts=0
    mkdir -p "$SYS/.git/info"
    while IFS= read -r _l || [ -n "$_l" ]; do   # la dernière ligne compte, saut final ou non
        case "$_l" in ''|'#'*) continue ;; esac
        grep -Fxq -- "$_l" "$_EXCL" 2>/dev/null || { printf '%s\n' "$_l" >> "$_EXCL"; _ajouts=$((_ajouts+1)); }
    done < "$SELF/config/gitignore-documents"
    [ "$_ajouts" -gt 0 ] && did "liste noire posée dans le .git/info/exclude de ~/.claude ($_ajouts motif(s))"
fi
fi

# --- 3. La mémoire automatique ---------------------------------------------
# Aucun lien à poser : `autoMemoryDirectory` dans `settings.json` (suivi par git) envoie la
# mémoire automatique de TOUTE session dans `~/.claude/memory`, quel que soit le dossier de
# travail. Des liens `projects/<slug>/memory` déjà posés restent, inertes.
# On avertit sur un dossier `memory/` RÉEL et non vide sous `projects/` : écrit hors sauvegarde,
# c'est peut-être la seule copie de ses fiches.
grep -q '"autoMemoryDirectory"' "$SYS/settings.json" \
    || warn "settings.json ne porte pas autoMemoryDirectory — la mémoire automatique retombe sous projects/<slug>/, hors sauvegarde."
for _l in "$SYS"/projects/*/memory; do
    [ -d "$_l" ] && [ ! -L "$_l" ] && [ -n "$(ls -A -- "$_l" 2>/dev/null)" ] || continue
    warn "${_l#$SYS/} est un dossier NON VIDE et HORS SAUVEGARDE (projects/ est ignoré en bloc)."
    suite "    Son contenu n'existe que sur ce poste. Verse-le dans $SYS/memory."
done

# --- 4. La ligne de démarrage du shell ---------------------------------------
# Le fichier de démarrage du shell n'est pas dans le dépôt (c'est un fichier du poste) : sans
# cette ligne, la session s'ouvre muette — le contexte est injecté, mais rien ne fait parler
# l'assistant en premier. Le poste n'est pas toujours en bash : on balaie les quatre fichiers
# plausibles, et le message nomme celui du shell COURANT — un `.bashrc` en dur crierait une
# absence fausse sur un `~/.zshrc` bien branché. Le motif est le chemin `/engine/claudeos-boot.sh`
# et non le seul nom du fichier, qu'une ligne qui ne lance rien peut aussi porter.
_claudeos_rc_trouve=""
for _claudeos_rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    if grep -qF '/engine/claudeos-boot.sh' "$_claudeos_rc" 2>/dev/null; then _claudeos_rc_trouve="$_claudeos_rc"; break; fi
done
case "${SHELL:-}" in *zsh) _claudeos_rc_cible="~/.zshrc" ;; *) _claudeos_rc_cible="~/.bashrc" ;; esac
if [ -f "$SELF/claudeos-boot.sh" ] && [ -z "$_claudeos_rc_trouve" ]; then
    warn "$_claudeos_rc_cible ne source pas le démarrage de ClaudeOS. Ajoute cette ligne :"
    suite '    [ -f "$HOME/.claude/engine/claudeos-boot.sh" ] && . "$HOME/.claude/engine/claudeos-boot.sh"'
fi

# --- 4bis. Le bloc de titre de `~/.zshrc` --------------------------------------
# FACULTATIF : sa source est `reglages/zshrc-claudeos.zsh`, à toi ; sans elle, l'étape se tait.
# `~/.zshrc` est un fichier du POSTE, hors dépôt : il ne voyage pas. Ce qui est dû vient de
# `claudeos_poste_ecarts` (config.sh), seule source de l'écart. Le bloc entre
# marqueurs suit sa source : absent, il s'ajoute en fin de fichier ; différent, il se remplace,
# l'ancien fichier gardé à côté. Le reste de `~/.zshrc` ne se touche jamais.
_TITRE='# >>> ClaudeOS — titre de terminal'
_TITRE_FIN='# <<< ClaudeOS — titre de terminal'
if claudeos_poste_ecarts | grep -qx 'zsh-titre'; then
    if ! grep -qF "$_TITRE" "$HOME/.zshrc" 2>/dev/null; then
        claudeos_zshrc_bloc 'titre de terminal' >> "$HOME/.zshrc" \
            && did "bloc de titre de terminal ajouté à ~/.zshrc (rouvrir un shell)"
    elif ! grep -qF "$_TITRE_FIN" "$HOME/.zshrc"; then
        warn "~/.zshrc ouvre le bloc de titre sans le fermer ($_TITRE_FIN) — rien changé, à regarder à la main."
    else
        _bk="$HOME/.zshrc.avant-claudeos-$(date +%Y%m%d-%H%M%S)"
        claudeos_zshrc_bloc 'titre de terminal' > "$HOME/.zshrc.claudeos-bloc" && cp "$HOME/.zshrc" "$_bk" \
            && awk -v f="$HOME/.zshrc.claudeos-bloc" -v o="$_TITRE" -v c="$_TITRE_FIN" '
                index($0, o) == 1 { while ((getline l < f) > 0) print l; skip = 1; next }
                skip && index($0, c) == 1 { skip = 0; next }
                !skip' "$_bk" > "$HOME/.zshrc.claudeos-tmp" \
            && mv "$HOME/.zshrc.claudeos-tmp" "$HOME/.zshrc" \
            && did "bloc de titre de ~/.zshrc remplacé par celui de reglages/ (ancien fichier : $_bk)"
        rm -f "$HOME/.zshrc.claudeos-bloc"
    fi
fi

# --- 5. Identité git ----------------------------------------------------------
# `~/.gitconfig` est un fichier du POSTE, dans aucun dépôt : il ne voyage pas. Sur une
# machine neuve git n'a ni nom ni adresse, et TOUS les commits échouent. La source unique est
# `reglages/IDENTITE_GIT`, suivie par ton dépôt, et l'installateur la POSE. Sa souche vide est
# `gabarits/IDENTITE_GIT`, que l'agent d'installation recopie et fait remplir.
# Il ne recouvre jamais une identité déjà en place : le poste peut légitimement porter
# une autre adresse (compte client), et l'écraser en silence signerait à la mauvaise
# identité. Dans ce cas il se contente de signaler l'écart.
_ID="$REG/IDENTITE_GIT"
if [ "$_GIT_REGIME" = "aucun" ]; then
    :   # sans git, aucune identité de commit à poser
elif [ -f "$_ID" ]; then
    # shellcheck source=/dev/null
    . "$_ID"
    for _champ in name:GIT_NOM email:GIT_EMAIL; do
        _cle="${_champ%%:*}"; eval "_val=\"\${${_champ##*:}:-}\""
        [ -n "$_val" ] || continue
        _actuel="$(git config --global "user.$_cle" 2>/dev/null || true)"
        if [ -z "$_actuel" ]; then
            git config --global "user.$_cle" "$_val" && did "identité git posée (user.$_cle = $_val)"
        elif [ "$_actuel" != "$_val" ]; then
            warn "user.$_cle vaut « $_actuel » sur ce poste, le dépôt dit « $_val » — rien changé."
        fi
    done
else
    warn "$_ID est absent — l'identité git ne peut pas être posée : l'agent d'installation la demande."
fi

# --- 6. Les raccourcis vers le réceptacle confidentiel -----------------------
# Un `_IGNORE/` vit à la racine d'un projet (règle du réceptacle confidentiel), mais le travail
# se fait un cran plus bas, dans les dossiers d'app. Le raccourci évite de remonter, et il
# s'appelle `_ign` et pas `_IGNORE` pour DEUX raisons : le motif `_IGNORE/` du `.gitignore`
# porte un slash, donc il n'attrape pas un lien symbolique — que git voit comme un fichier — et
# un lien portant ce nom ferait voir aux contrôles de réceptacle un réceptacle qui n'existe pas.
# Gitignoré, donc il ne voyage pas : c'est ce script qui le repose sur chaque poste.
# LA CIBLE EST LE SOUS-DOSSIER DE MÊME NOM, jamais la racine du réceptacle : un lien vers
# `../_IGNORE` montrerait les pièces de TOUTES les apps depuis n'importe laquelle. Un `_IGNORE/`
# reproduit le sous-chemin d'origine, donc le sous-dossier EST le périmètre attendu.
# Pas de sous-dossier, pas de lien : on ne crée pas de souche vide pour justifier un raccourci.
# Seulement si `CONFIDENTIEL=oui` : sans documents confidentiels, pas de réceptacle à raccourcir.
[ "$(claudeos_reponse CONFIDENTIEL 2>/dev/null)" = "oui" ] && while IFS= read -r _root; do
    [ -d "$_root" ] || continue
    for _proj in "$_root"/*/; do
        [ -d "$_proj" ] || continue
        [ -d "${_proj}_IGNORE" ] || continue
        for _sub in "$_proj"*/; do
            [ -d "$_sub" ] || continue
            _name="$(basename "$_sub")"
            case "$_name" in _IGNORE|.*) continue ;; esac
            _lnk="${_sub}_ign"
            _want="../_IGNORE/$_name"
            if [ ! -d "${_proj}_IGNORE/$_name" ]; then
                # Le réceptacle n'a rien pour cette app : un lien resté là pointerait dans le vide.
                [ -L "$_lnk" ] && rm -f "$_lnk" && did "raccourci obsolète retiré (${_lnk#$HOME/})"
            elif [ -L "$_lnk" ]; then
                [ "$(readlink "$_lnk")" = "$_want" ] || { ln -sfn "$_want" "$_lnk" && did "raccourci reciblé (${_lnk#$HOME/})"; }
            elif [ -e "$_lnk" ]; then
                warn "${_lnk#$HOME/} existe et n'est PAS un lien — laissé tel quel, à regarder à la main."
            else
                ln -s "$_want" "$_lnk" && did "raccourci posé (${_lnk#$HOME/})"
            fi
        done
    done
done < <(claudeos_ws_roots)

# Le compte des avertissements entre dans le verdict : sans lui, un passage qui n'a rien pu
# faire ET a signalé un empêchement annonçait « le poste est en état ».
if [ "$n" -gt 0 ] || [ "$w" -gt 0 ]; then
    echo "[install] $n geste(s) appliqué(s), $w empêchement(s) signalé(s)."
    [ "$w" -gt 0 ] && exit 1
else
    echo "[install] rien à faire, le poste est en état."
fi
exit 0
