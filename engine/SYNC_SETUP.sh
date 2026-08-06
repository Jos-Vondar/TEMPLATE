#!/usr/bin/env bash
# =============================================================================
# SYNC_SETUP — checklist de configuration IDEMPOTENTE, exécutée à la fin de
# chaque sync. Chaque étape : « est-ce déjà fait ? » → sinon, le fait. Sûr à
# relancer autant de fois qu'on veut (no-op quand c'est satisfait).
#
# C'EST ICI qu'on déclare toute action de config qu'un poste en retard doit subir
# automatiquement (ligne shell, install de plugin, config git…). Ajouter un besoin
# = ajouter une étape idempotente ici. Étant versionné, ça s'applique seul sur
# TOUS les postes à leur prochain sync — pas de "à faire à la main", pas de mémoire.
#
# Réservé à MACHINE_TODO.md (machine-todo.sh) : uniquement ce qui ne peut PAS être
# automatisé depuis ce poste (ex. une action qui n'existe que dans l'interface graphique d'une autre machine).
# =============================================================================
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
done_n=0
did() { echo "  ✚ $1"; done_n=$((done_n+1)); }

# 1. Ligne d'amorçage de la bannière de démarrage dans ~/.bashrc (local, instantané).
if [ -f "$REPO/boot-wrapper.sh" ] && ! grep -qF 'boot-wrapper.sh' "$HOME/.bashrc" 2>/dev/null; then
    echo '[ -f "$HOME/.claudeos/engine/boot-wrapper.sh" ] && . "$HOME/.claudeos/engine/boot-wrapper.sh"' >> "$HOME/.bashrc" \
        && did "bannière de démarrage ajoutée à ~/.bashrc (effet au prochain terminal)"
fi

# 2. Plugin superpowers (réseau ; ne tourne que s'il manque vraiment).
if ! find "$HOME/.claude/plugins" -maxdepth 3 -iname '*superpowers*' 2>/dev/null | grep -q .; then
    # #11 : résoudre le binaire même en shell non-interactif (cron : PATH restreint).
    CLAUDE_BIN="$(command -v claude 2>/dev/null || true)"
    [ -z "$CLAUDE_BIN" ] && for c in "$HOME/.local/bin/claude" "$HOME/.claude/local/claude"; do
        [ -x "$c" ] && { CLAUDE_BIN="$c"; break; }
    done
    if [ -n "$CLAUDE_BIN" ] && "$CLAUDE_BIN" plugin install superpowers@claude-plugins-official >/dev/null 2>&1; then
        did "plugin superpowers installé"
    else
        echo "  ⚠ superpowers manquant et install auto impossible — manuel : claude plugin install superpowers@claude-plugins-official" >&2
    fi
fi


# 3. Réceptacle `_IGNORE/` dans chaque dossier PROJET (niveau `workstations/<DOMAINE>/<PROJET>`).
# Ces dossiers sont exclus de la synchronisation (c'est leur raison d'être), donc ils ne
# voyagent PAS d'un poste à l'autre : un poste neuf ou remis à niveau reçoit l'arborescence
# des workstations sans eux. Constat de l'audit du 2026-07-25 : 20 dossiers sur 22 en étaient
# dépourvus sur un poste alors qu'ils existaient sur l'autre. Sans réceptacle, le premier
# document client sensible atterrit en zone sauvegardée. On les recrée donc à chaque sync.
# Décision du 2026-07-25 : UN SEUL réceptacle par projet, à sa racine. Les applications et
# sous-dossiers (niveau 3 et au-delà) n'en reçoivent pas — le confidentiel d'une app va dans
# le réceptacle de son projet. D'où la profondeur figée à 2 : elle rend inutile la liste de
# sous-dossiers à exclure qui vivait ici (docs, extracted, rapports…).
if [ -d "$HOME/workstations" ]; then
    _ign_n=0
    while IFS= read -r d; do
        [ -d "$d/_IGNORE" ] || { mkdir -p "$d/_IGNORE" && _ign_n=$((_ign_n+1)); }
    done < <(find "$HOME/workstations" -mindepth 2 -maxdepth 2 -type d \
        -not -name "_IGNORE" 2>/dev/null)
    [ "$_ign_n" -gt 0 ] && did "$_ign_n réceptacle(s) _IGNORE/ créé(s) à la racine des projets"
fi

# 4. (futures étapes idempotentes ici — ex. config git d'un repo annexe, etc.)

[ "$done_n" -gt 0 ] && echo "[setup] $done_n action(s) de config appliquée(s)." || true
exit 0
