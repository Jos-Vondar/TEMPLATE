#!/usr/bin/env bash
# =============================================================================
# controle-secrets.sh — « un secret hors de son emplacement autorisé ».
#
# Transplanté le 2026-08-22 (étape 4.3/4.5) depuis `selftest.sh` contrôle 36, dont
# il garde le bandeau `[selftest] 36.` pour rester retrouvable. Il ne va PAS au hook
# pre-commit, sur décision de l'utilisateur : il regarde l'ARBRE VIVANT ENTIER, zones
# hors dépôt comprises, ce qu'un hook ne voit jamais. Il reste au rythme de la clôture,
# ~1 s mesurée le 2026-08-22 (l'en-tête annonçait « ~20 s assumées », faux d'un facteur 20 —
# c'est ce chiffre qui avait servi à arbitrer l'emplacement de ce contrôle). L'arbitrage tient
# quand même : le scan porte sur l'arbre entier, y compris hors dépôt, ce que le hook ne voit pas.
#
# Classe de défaut, constatée le 2026-08-03 : une valeur de secret vivait dans un
# dossier de compétence. Les alarmes du commit ne peuvent pas la voir — elles
# inspectent ce qui est MIS EN FILE. Un secret mal rangé dans une zone que le dépôt
# ignore est parfaitement invisible pour elles.
#
# AVERTIT, ne bloque pas. Ce n'est pas une fuite, c'est un rangement : rien n'est parti,
# rien n'est désactivé, et ça se corrige quand on le voit. Bloquer ferait payer un défaut
# de rangement par l'impossibilité de sauvegarder.
#
# Code retour : 0 rien à signaler · 1 au moins un fichier à classer.
#
# Emplacements AUTORISÉS, donc exclus — les deux régimes de `secrets-detail` :
#   ~/.claude/secrets-shared/  faible valeur, suivi au dépôt système ;
#   */_IGNORE/*                haute valeur, local strict, hors dépôt.
# Exclus aussi : ce que l'outil gère seul (transcripts, caches, historique, identifiants)
# et les greffons — ni écrits par nous ni sous notre contrôle, et bruyants par nature.
# Et CE SCRIPT LUI-MÊME, nommément : son nom porte le mot que la branche (b) cherche, et
# ses motifs sont des chaînes longues sans espace, donc il s'attrape tout seul. Exclusion
# d'un fichier connu et versionné, écrite ici plutôt que contournée par un renommage —
# renommer le garde pour échapper au garde cacherait le contournement.
# =============================================================================
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

# Ce script s'exclut lui-même : son nom porte le mot qu'il cherche, et il contient les motifs.
# CORRIGÉ le 2026-08-22. L'exclusion valait `-not -path "${BASH_SOURCE[0]}"` — le chemin TEL
# QU'APPELÉ, donc relatif quand on lance `bash engine/controle-secrets.sh`, alors que `find`
# produit toujours l'absolu. L'exclusion ne mordait que lorsque l'appelant employait la forme
# absolue, ce que fait la clôture — le défaut était donc invisible depuis le seul chemin qui
# compte, et le contrôle s'accusait lui-même dès qu'on le lançait à la main.
# DEUXIÈME FORME DU MÊME DÉFAUT, corrigée le 2026-09-22 — l'exclusion par CHEMIN ne mord pas
# depuis la migration sur Mac. `$SELF` est le chemin RÉSOLU
# (`~/Documents/ClaudeOS/.claude/engine`), tandis que `find -L "$HOME/.claude"` rend le chemin
# PAR LE LIEN (`~/.claude/engine`). Deux chaînes différentes pour le même fichier : `-not -path`
# ne pouvait donc jamais s'appliquer, et le contrôle s'accusait lui-même à CHAQUE clôture —
# un avertissement permanent, c'est-à-dire un avertissement qu'on apprend à ignorer.
# La correction du 2026-08-22 visait déjà ce défaut sous sa forme « relatif contre absolu » ;
# les liens du Mac en ont ouvert une seconde. On exclut donc par NOM DE BASE, qui ne dépend ni
# du poste, ni des liens, ni de la façon dont l'appelant a écrit le chemin.
# COMPROMIS ASSUMÉ : un fichier homonyme ailleurs dans l'arbre serait ignoré lui aussi. Ce ne
# pourrait être qu'une copie de ce script, donc sans secret propre à signaler.
_MOI_NOM="$(basename "${BASH_SOURCE[0]}")"

echo "[selftest] 36. Secret hors de son emplacement autorisé, y compris en zone non sauvegardée (avertissement)"

_WS=()
while IFS= read -r _w; do [ -n "$_w" ] && _WS+=("$_w"); done < <(claudeos_ws_roots)

# PORTABILITÉ, 2026-09-12 : ce balayage vivait DANS un `_hits=$( … )`, et il porte un `case` dont
# le motif `*.md)` referme, aux yeux du parseur de bash 3.2, la substitution ouverte par `$(`. Sous le
# bash d'Apple le fichier ne s'analysait même plus : bandeau affiché, puis mort — et l'échec était
# avalé par le `|| true` de la clôture, donc le contrôle 36 disparaissait sans un mot. Le corps d'une
# FONCTION échappe à ce balayage de parenthèses. Rien d'autre ne change, et l'idiome vaut pour bash 5
# comme pour le 3.2 : le PC sous WSL exécute le même fichier.
_claudeos_scan_secrets() {
    # `$HOME/workstations/docs` est SORTI le 2026-09-08 : le monodépôt de travail est découpé, et
    # le `docs/` de chaque client est déjà couvert par sa racine dans `_WS`.
    # TABLEAU VIDE SOUS BASH 3.2 — corrigé le 2026-10-01, signalé par la session CLAUDE_OS_TEMPLATE.
    # Sans aucun dossier de travail, `"${_WS[@]}"` mourait en « unbound variable » sous le bash d'Apple
    # avec `set -u` : le sous-shell de `_hits=$( … )` s'arrêtait avant même `~/.claude`, et le contrôle
    # concluait « ✅ aucune valeur de secret » sur une ERREUR. La forme ci-dessous rend zéro mot sans
    # erreur et garde intacts les éléments à espaces.
    for _root in "$HOME/.claude" ${_WS[@]+"${_WS[@]}"}; do
        [ -d "$_root" ] || continue
# PORTABILITE, 2026-09-12 — `find -L`, ET CE N'EST PAS COSMETIQUE. Depuis la migration sur le Mac,
# les racines de depot sont des LIENS SYMBOLIQUES (`~/<DÉPÔT>` -> un dossier réel ailleurs).
# `find` NE SUIT PAS un lien donne en argument sans `-L` : le balayage rendait ZERO fichier sur 567,
# et le controle concluait au vert. Mesure du jour : 0 contre 567. Un garde qui ne regarde rien
# repond toujours « rien a signaler ». `-L` est POSIX et sans effet quand la racine est un vrai
# dossier, donc neutre sur le PC sous WSL.
        find -L "$_root" -type f \
            -not -path "*/_IGNORE/*" \
            -not -path "$HOME/.claude/secrets-shared/*" \
            -not -name "$_MOI_NOM" \
            -not -path "$HOME/.claude/.git/*" \
            -not -path "*/.git/*" \
            -not -path "$HOME/.claude/projects/*" \
            -not -path "$HOME/.claude/plugins/*" \
            -not -path "$HOME/.claude/cache/*" \
            -not -path "$HOME/.claude/sessions/*" \
            -not -path "$HOME/.claude/shell-snapshots/*" \
            -not -path "$HOME/.claude/file-history/*" \
            -not -path "$HOME/.claude/paste-cache/*" \
            -not -path "$HOME/.claude/session-env/*" \
            -not -path "$HOME/.claude/tasks/*" \
            -not -path "$HOME/.claude/jobs/*" \
            -not -path "$HOME/.claude/daemon/*" \
            -not -path "$HOME/.claude/downloads/*" \
            -not -path "$HOME/.claude/backups/*" \
            -not -path "$HOME/.claude/telemetry/*" \
            -not -path "$HOME/.claude/.sync-backups/*" \
            -not -path "$HOME/.claude/ide/*" \
            -not -name ".credentials.json" \
            -not -name "history.jsonl" \
            2>/dev/null
    done | while IFS= read -r _f; do
        # Fichiers texte seulement. `grep -I` et non `file` : `file` n'est pas installé sur
        # ce poste, son mime vide tombait dans la branche par défaut, et TOUS les fichiers
        # étaient sautés — un garde de secrets qui ne gardait rien, sans jamais le dire.
        if [ -s "$_f" ] && ! grep -Iq . "$_f" 2>/dev/null; then continue; fi
        # (a) le CONTENU porte une forme d'éditeur (casse exacte) ou un mot-clé suivi d'une valeur
        if grep -lE  "$CLAUDEOS_SECRET_RE_FORMES" "$_f" >/dev/null 2>&1 \
        || grep -liE "$CLAUDEOS_SECRET_RE_MOTS"   "$_f" >/dev/null 2>&1; then
            echo "${_f#$HOME/} : contenu"
            continue
        fi
        # (b) le NOM annonce un secret, ET le fichier porte une valeur PLAUSIBLE (une ligne non
        # commentée d'au moins 20 caractères sans espace). Les `.md` sont exclus de ce second
        # motif : un document SUR les secrets n'en porte pas la valeur. Le motif de contenu,
        # lui, continue de s'appliquer aux `.md`.
        case "$_f" in
            *.md) ;;
            *) printf '%s\n' "$_f" | grep -qiE "$CLAUDEOS_SECRET_NAME_RE" \
                 && grep -vE '^\s*#|^\s*$' "$_f" 2>/dev/null | grep -qE '[^[:space:]]{20,}' \
                 && echo "${_f#$HOME/} : nom + valeur plausible" ;;
        esac
    done | head -10
}
_hits=$(_claudeos_scan_secrets)

if [ -n "$_hits" ]; then
    echo "[selftest] ⚠ secret(s) hors emplacement autorisé — à classer, pas à ignorer :" >&2
    echo "$_hits" | sed 's/^/       /' >&2
    echo "       Faible valeur → ~/.claude/secrets-shared/ ; haute valeur → un _IGNORE/ ou hors arbre." >&2
    echo "       Faux positif ? Ce contrôle avertit et ne bloque rien : la clôture continue." >&2
    exit 1
fi
echo "[selftest] ✅ aucune valeur de secret hors de secrets-shared/ et des _IGNORE/ (arbre entier, zones non sauvegardées comprises)"
exit 0
