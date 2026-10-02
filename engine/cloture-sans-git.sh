#!/usr/bin/env bash
# =============================================================================
# cloture-sans-git.sh — la fin de la clôture quand `GIT=aucun` (`d-regime-sans-git`).
#
# Écrit le 2026-10-01, plan complet de templating § 2, A3, geste 4. Code PROPRE AU TEMPLATE.
# SOURCÉ par `claudeos-cloture.sh` à la place des commits, une fois faits les projections, l'index
# de recherche et le contrôle des secrets : jamais lancé seul. Il emploie `SELF`, `SYS`, `HOOK_SRC`,
# `ECARTES` et `_donnees_neuves` de l'appelant, et sort lui-même : 0, ou 5 comme une alarme sur le
# système en régime GitHub.
#
# SANS DÉPÔT, RIEN NE SORT DU POSTE — le prix dit à l'installateur au choix du régime. Ce qui reste
# du commit, c'est son CROCHET : les contrôles tournent sur les fichiers changés depuis la clôture
# précédente (`regime.py changes`), et une clôture qui les passe réécrit les EMPREINTES qui feront
# référence à la suivante. Un refus ne réécrit RIEN : la clôture suivante recontrôle les mêmes
# changements, comme un commit refusé laisse sa file en place.
# =============================================================================
if [ ! -f "$SYS/.claudeos-racine" ]; then
    echo "[clôture] ⛔ système : ~/.claude ne porte pas .claudeos-racine, la marque d'une racine sans git." >&2
    echo "[clôture]   Sans elle, rien ne résout les niveaux. La poser : bash ~/.claude/engine/install-poste.sh" >&2
    exit 5
fi
# SANS RÉFÉRENCE, RIEN NE DIT CE QUI A CHANGÉ : tout serait « neuf », y compris l'état livré, et le
# verdict ne voudrait rien dire. On refuse en nommant le geste et son prix plutôt que de tout relire.
if [ ! -f "$SYS/.claudeos/empreintes/MANIFESTE.json" ]; then
    echo "[clôture] ⛔ système : aucune empreinte de référence (.claudeos/empreintes/) — rien ne dit ce qui a changé." >&2
    echo "[clôture]   L'installation la pose ; la reposer : bash ~/.claude/engine/install-poste.sh — l'état" >&2
    echo "[clôture]   présent devient alors la référence, sans contrôle de ce qui a changé avant." >&2
    exit 5
fi
_SG_TMP="$(mktemp -d "${TMPDIR:-/tmp}/claudeos-cloture.XXXXXX")" || {
    echo "[clôture] ⛔ système : dossier temporaire impossible — rien n'est contrôlé." >&2; exit 5; }
trap 'rm -rf "$_SG_TMP"' EXIT
_SG_LISTE="$_SG_TMP/fichiers"

if ! python3 "$SELF/regime.py" changes "$SYS" > "$_SG_LISTE"; then
    echo "[clôture] ⛔ système : les changements depuis la dernière clôture n'ont pas pu être établis" >&2
    echo "[clôture]   (cause ci-dessus). Rien n'est contrôlé, les empreintes ne sont pas réécrites." >&2
    exit 5
fi
echo "[clôture] système : $(wc -l < "$_SG_LISTE" | tr -d ' ') changement(s) depuis la dernière clôture."

# Les données texte NEUVES sont tenues HORS DES EMPREINTES, comme elles le sont du commit en régime
# GitHub : la clôture suivante les retrouve neuves, et le rappel revient tant que rien n'est tranché.
_sg_ecart=""
if [ -z "${FORCE_DATA:-}" ]; then
    _sg_ecart="$(awk -F'\t' '$1 == "A" { print $2 }' "$_SG_LISTE" | _donnees_neuves "$SYS")"
fi
printf '%s\n' "$_sg_ecart" > "$_SG_TMP/ecartes"
if [ -n "$_sg_ecart" ]; then
    awk -F'\t' 'NR == FNR { x[$0] = 1; next } !($1 == "A" && ($2 in x))' "$_SG_TMP/ecartes" "$_SG_LISTE" \
        > "$_SG_LISTE.f" && mv "$_SG_LISTE.f" "$_SG_LISTE"
    echo "[clôture] ⚠ système : $(printf '%s\n' "$_sg_ecart" | wc -l | tr -d ' ') fichier(s) de données TENUS HORS DES EMPREINTES (la clôture continue) :" >&2
    printf '%s\n' "$_sg_ecart" | sed 's/^/      /' >&2
    ECARTES="${ECARTES}système\t${_sg_ecart}\n"
fi

( cd "$SYS" && bash "$HOOK_SRC" --fichiers "$_SG_LISTE" ); _sg_rc=$?
if [ "$_sg_rc" -ne 0 ]; then
    echo "[clôture] ⛔ système : contrôles REFUSÉS (code $_sg_rc du crochet, détail ci-dessus). Les empreintes" >&2
    echo "[clôture]   ne sont pas réécrites : la clôture suivante recontrôlera les mêmes changements." >&2
    echo "[clôture]   Sans git, un levier se pose sur la clôture — FORCE_…=\"motif\" bash ~/.claude/engine/claudeos-cloture.sh —" >&2
    echo "[clôture]   là où le message ci-dessus dit « git commit … »." >&2
    exit 5
fi
if ! python3 "$SELF/regime.py" ecrit "$SYS" --sauf "$_SG_TMP/ecartes" >/dev/null; then
    echo "[clôture] ⛔ système : contrôles passés, mais les empreintes n'ont pas pu être réécrites (cause ci-dessus)." >&2
    exit 5
fi
echo "[clôture] système : contrôlé, empreintes réécrites. RIEN N'EST SORTI DU POSTE — régime sans git."

if [ -n "$ECARTES" ]; then
    echo "[clôture] ─────────────────────────────────────────────" >&2
    echo "[clôture] Des fichiers de données restent HORS DES EMPREINTES : aucun contrôle ne les a lus." >&2
    echo "[clôture] Deux gestes, et c'est une décision, pas un réglage :" >&2
    echo "[clôture]   • les ranger dans le _IGNORE/ du PROJET, réceptacle du confidentiel ;" >&2
    echo "[clôture]   • ou les assumer : FORCE_DATA=\"motif\" bash ~/.claude/engine/claudeos-cloture.sh" >&2
    echo "[clôture] Tant que rien n'est tranché, ce rappel revient à chaque clôture — c'est voulu." >&2
fi
exit 0
