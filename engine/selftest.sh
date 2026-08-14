#!/usr/bin/env bash
# =============================================================================
# SELFTEST — ClaudeOS. Smoke-test de la plomberie (« fail before you ship »).
# Exit 0 si tout est OK, 1 sinon. Lançable à la main + appelé en tête de backup.sh.
# Pas de framework : bash brut, portable, zéro dépendance de test.
# =============================================================================
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

FAIL=0
ok() { echo "  ✅ $1"; }
ko() { echo "  ❌ $1" >&2; FAIL=1; }
# warn : signale sans faire échouer. Critère d'arbitrage, généralisé le 2026-08-14 : `ko`
# est réservé à ce dont le passage cause une PERTE IRRÉVERSIBLE, une FUITE, ou le
# DÉSARMEMENT SILENCIEUX d'une garde ; tout le reste avertit — un défaut de contenu ou de
# carte ne doit jamais empêcher d'enregistrer le travail. Ce reclassement n'a été possible
# que parce que les ⚠ sont désormais VUS : la sauvegarde les enregistre et les relaie, le
# démarrage aussi (synclib.sh, claudeos_selftest_warns_record) — avant ça, backup.sh jetait
# toute cette sortie, et passer un contrôle en avertissement revenait à l'éteindre.
warn() { echo "  ⚠️  $1" >&2; }

# Racines des workstations — dérivées du MANIFESTE (claudeos_ws_roots), plus jamais écrites en
# dur (2026-08-09, chantier 8 de la vague post-grill). Une douzaine de contrôles ci-dessous
# balayaient `$HOME/workstations` : une workstation déclarée dans `SYNC_MAP` et rangée ailleurs
# aurait été sauvegardée sans être contrôlée par aucun d'eux, et rien n'aurait échoué. C'est la
# reprise du bug historique que `claudeos_pairs()` devait fermer. La PROFONDEUR reste figée chez
# chaque appelant : projet à 1 sous la racine, application à 2.
_WS=(); _WS_MANQUANTES=()
while IFS= read -r _r0; do
    [ -n "$_r0" ] || continue
    if [ -d "$_r0" ]; then _WS+=("$_r0"); else _WS_MANQUANTES+=("$_r0"); fi
done < <(claudeos_ws_roots)
# Deux ensembles vides, deux sens (séparés le 2026-08-14 — la confusion bloquait la première
# sauvegarde de toute installation du squelette exporté, dont le manifeste ne déclare aucun
# domaine au départ). Un domaine DÉCLARÉ au manifeste mais introuvable sur le disque : panne,
# le manifeste promet ce que le disque dément — ça bloque, domaine par domaine. AUCUN domaine
# déclaré : état légitime (installation neuve, usage mono-domaine) — les contrôles qui balaient
# les workstations n'ont rien à contrôler, et on le DIT avec le fichier à éditer, même forme
# que le saut du contrôle 10 : un contrôle silencieusement sans objet est indistinguable d'un
# contrôle oublié.
for _r0 in ${_WS_MANQUANTES[@]+"${_WS_MANQUANTES[@]}"}; do
    ko "domaine déclaré au manifeste ($SYNC_MAP) mais introuvable sur le disque : $_r0"
done
if [ "${#_WS[@]}" -eq 0 ] && [ "${#_WS_MANQUANTES[@]}" -eq 0 ]; then
    echo "  ⏭  aucun domaine déclaré au manifeste : sans objet pour les contrôles 28, 29, 32, 33 et la part workstation de 22 et 27. Pour en déclarer un : une ligne « workstations/<DOMAINE>  workstations/<DOMAINE>  mirror » dans $SYNC_MAP."
fi

echo "[selftest] 1. Syntaxe des scripts"
for s in "$SELF"/*.sh; do
    if bash -n "$s" 2>/dev/null; then ok "$(basename "$s")"; else ko "syntaxe $(basename "$s")"; fi
done

echo "[selftest] 2. Dépendances dures"
for dep in python3 git rsync; do
    if command -v "$dep" >/dev/null 2>&1; then ok "$dep présent"; else ko "$dep MANQUANT"; fi
done

# CONTRÔLE 3 RETIRÉ le 2026-08-05 — il vérifiait que l'origin du dépôt vivant est le bon.
# Trois gardes portaient la même chose : le contrôle 12 exerce la FONCTION sur un faux dépôt
# (mauvais origin refusé, bon accepté), et `backup.sh` comme `sync.sh` appellent la garde en
# tête d'exécution, donc un mauvais origin échoue bruyamment avant tout transfert. Celui-ci
# n'ajoutait qu'une troisième lecture du même fait.

# CAPTURE UNIQUE DE `boot-check.sh` (2026-08-07). Il était exécuté quatre fois — contrôles 4,
# 21 deux fois, et 30 — et chaque exécution refait un scan de dérive et un `du -sk` sur le
# dépôt. C'était une part notable des quinze secondes payées avant CHAQUE sauvegarde. Une seule
# sortie partagée rend exactement les mêmes verdicts : le script est en lecture seule et
# déterministe à l'échelle d'un passage. Si la capture échoue, la variable est vide et les
# contrôles qui la lisent échouent comme avant — le mode de défaillance ne change pas.
_BOOTOUT="$(bash "$SELF/boot-check.sh" 2>/dev/null)"

echo "[selftest] 4. boot-check.sh → JSON valide"
if printf '%s' "$_BOOTOUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "hookSpecificOutput" in d' 2>/dev/null; then
    ok "boot-check produit un JSON valide"
else
    ko "boot-check : sortie JSON invalide"
fi

echo "[selftest] 5. INDEX.md à 2 couches — la couche curatée survit-elle ?"
# Ce contrôle LANÇAIT build-index.sh puis vérifiait que INDEX.md existait — alors que
# backup.sh le relance dix lignes plus loin (backup.sh:74). Un test qui écrit dans un
# artefact de mémoire, puis constate la présence du fichier qu'il vient de créer : le
# premier terme ne pouvait échouer que sur un plantage du script, ce que le contrôle 1
# (bash -n) et le `|| echo WARN` de backup.sh signalent déjà. Retiré le 2026-08-05.
# Ce qui restait vivant, et qui est tout ce qui reste ici : la couche curatée 🧭 est
# hors des balises AUTO et le générateur ne doit jamais l'emporter — régression réelle,
# déjà rencontrée (le marqueur d'ouverture vit AVANT le titre du squelette, le document de conception).
if [ -f "$MEM/INDEX.md" ] \
   && grep -q "## 🧭" "$MEM/INDEX.md" && grep -q "AUTO:START" "$MEM/INDEX.md"; then
    ok "INDEX.md à 2 couches (curatée 🧭 préservée + squelette AUTO)"
else
    warn "INDEX.md absent ou incomplet — la couche curatée a-t-elle été emportée ?"
fi

echo "[selftest] 6. Dérive live↔repo (sentinelle du bug « live périmé »)"
# Tout fichier présent dans le miroir repo doit exister en live. Un manquant = sync
# jamais appliqué (le bug des 16 fichiers). On échoue → backup refusé → « sync d'abord ».
# On NE bloque PAS sur les fichiers seulement divergents (éditions live légitimes à
# capturer par le backup en cours) — uniquement sur les ABSENTS.
if [ -f "$SELF/synclib.sh" ]; then
    source "$SELF/synclib.sh"
    declare -a _MISS _DIFF
    claudeos_drift _MISS _DIFF
    if [ "${#_MISS[@]}" -eq 0 ]; then
        ok "live complet (aucun fichier du repo absent en live)"
    else
        ko "${#_MISS[@]} fichier(s) du repo ABSENT(S) en live."
        for m in "${_MISS[@]:0:8}"; do echo "    manque: ${m#"$HOME"/}" >&2; done
        [ "${#_MISS[@]}" -gt 8 ] && echo "    … (+$(( ${#_MISS[@]} - 8 )) autres)" >&2
        echo "    → si poste en retard : bash $SELF/sync.sh (restaure)." >&2
        echo "    → si suppression/renommage VOULU : git -C $ROOT rm <chemin-repo> puis relance backup." >&2
    fi
else
    ko "synclib.sh introuvable"
fi

# CONTRÔLE 7 RETIRÉ le 2026-08-05 — il cherchait un appel de sync/backup/restore avec un
# drapeau, aucun de ces scripts n'en acceptant. Il a attrapé un `--bootstrap` oublié une fois.
# La classe est désormais structurellement fermée : ces scripts refusent tout argument inconnu,
# et `restore.sh` n'a plus de logique propre. Un contrôle qui garde une classe fermée ne peut
# plus rien attraper, il encombre le diagnostic.

echo "[selftest] 8. Machine TODO — cases par poste (add/count/done/purge + fail-loud)"
# Cycle complet en bac à sable isolé (overrides) : add ciblé -> count correct par
# poste -> done coche la case -> purge retire les faites -> count fail-loud si poste
# hors registre (jamais un faux "0" qui masquerait une tâche due, ex-#20).
if [ -x "$SELF/machine-todo.sh" ] && [ -f "$SYNC_MACHINES" ]; then
    SB="$(mktemp -d)"
    MT() { MACHINE_TODO_FILE="$SB/TODO.md" SYNC_MACHINES_FILE="$SB/M" SYNC_MACHINE="$1" bash "$SELF/machine-todo.sh" "${@:2}"; }
    printf 'hostA a Poste A\nhostB b Poste B\n' > "$SB/M"
    MT a add "test" --for b >/dev/null 2>&1
    c_b=$(MT b count); c_a=$(MT a count)
    MT b done 1 >/dev/null 2>&1; c_b2=$(MT b count)
    checked=$(grep -c '^- \[x\] ' "$SB/TODO.md" 2>/dev/null || true)
    MT b purge >/dev/null 2>&1; after=$(grep -c '^- \[x\] ' "$SB/TODO.md" 2>/dev/null || true)
    # #20 : poste non résolu (SYNC_MACHINE absent + hostname hors registre) => count
    # DOIT échouer (rc≠0), jamais renvoyer un faux "0".
    _floud=0
    env -u SYNC_MACHINE MACHINE_TODO_FILE="$SB/TODO.md" SYNC_MACHINES_FILE="$SB/M" \
        bash "$SELF/machine-todo.sh" count >/dev/null 2>&1 || _floud=1
    if [ "$c_b" = "1" ] && [ "$c_a" = "0" ] && [ "$c_b2" = "0" ] && [ "$checked" = "1" ] && [ "$after" = "0" ] && [ "$_floud" = "1" ]; then
        ok "add/count par poste + done coche + purge + count fail-loud si poste non résolu (#20)"
    else
        # BLOQUANT depuis le 2026-08-07, sur décision de l'utilisateur. Ce contrôle existe parce
        # qu'un faux « zéro tâche » a masqué une consigne due sans que rien ne le dise : c'est de
        # la désactivation silencieuse, que la fiche des contrôles réserve au blocage. Il tourne
        # en bac à sable déterministe, sans donnée vivante, donc un faux positif y est improbable.
        ko "machine-todo (cible=$c_b auteur=$c_a après-done=$c_b2 coché=$checked après-purge=$after fail-loud=$_floud)"
    fi
    rm -rf "$SB"
else
    warn "machine-todo.sh ou SYNC_MACHINES introuvable"
fi

# CONTRÔLE 9 RETIRÉ le 2026-08-05 — il créait deux dossiers temporaires pour vérifier que
# `rsync --delete` supprime et que `rsync` sans le drapeau conserve. C'est la sémantique d'un
# outil, pas un comportement de ce système : elle ne peut pas varier d'un poste à l'autre, et
# le contrôle 2 dit déjà si `rsync` est présent. Ce qui garde réellement le choix du régime est
# la vérification de câblage : le manifeste porte une colonne de régime et les scripts la lisent.

# CONDITIONS DE L'ENTRETIEN. Un contrôle qui exige une fonction que la personne a
# explicitement déclinée n'est pas sévère, il est faux — et il bloque sa sauvegarde pour un
# défaut qui n'en est pas un. L'entretien écrit ses réponses ; on les lit ici.
# Fichier absent = toutes vraies. C'est le défaut sûr, et il vaut pour toute installation
# antérieure à ce mécanisme, celle de l'auteur comprise : elle continue de tout contrôler.
_CONDITIONS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config/CONDITIONS"
condition_vraie() {
    [ -f "$_CONDITIONS" ] || return 0
    grep -qx -- "$1" "$_CONDITIONS" 2>/dev/null
}

echo "[selftest] 10. Exclusions confidentielles (*.eml / *.msg / _IGNORE/)"
if ! condition_vraie CONFIDENTIEL; then
    # Sauté, et DIT — un contrôle silencieusement absent est indistinguable d'un contrôle
    # oublié. La ligne rappelle aussi comment revenir en arrière : la condition se change.
    echo "  ⏭  sauté : la condition CONFIDENTIEL est fausse dans $_CONDITIONS"
else
_s10=$(mktemp -d); _d10=$(mktemp -d); echo x >"$_s10/a.md"; echo x >"$_s10/m.eml"; mkdir -p "$_s10/_IGNORE"; echo x >"$_s10/_IGNORE/s.txt"
rsync -a --exclude-from="$SYNC_IGNORE" "$_s10/" "$_d10/"
if [ -f "$_d10/a.md" ] && [ ! -f "$_d10/m.eml" ] && [ ! -d "$_d10/_IGNORE" ]; then ok "*.eml et _IGNORE/ exclus, .md conservé"; else ko "exclusions confidentielles"; fi
rm -rf "$_s10" "$_d10"
fi

# CONTRÔLE 11 RETIRÉ le 2026-08-05 — il copiait le dépôt vers un faux dossier personnel pour
# vérifier que chaque régime atterrit au bon endroit. Défaut de méthode, nommé par
# compétence `controles-et-alarmes` : il RÉIMPLÉMENTAIT le routage en dur dans le test
# (`system` → `.claude`, `system-memory`, `resources`) au lieu d'exercer celui de `sync.sh`.
# Reproduire la logique à côté pour la tester valide la reproduction, pas le contrôle en place —
# le routage réel se lit dans le manifeste, seule source, et un écart entre les deux passait
# inaperçu. Le contrôle 6 attrape la vraie conséquence : un fichier du dépôt absent en live.

echo "[selftest] 12. Garde-fou remote — refuse un mauvais origin (fonction réelle)"
_g=$(mktemp -d); git -C "$_g" init -q 2>/dev/null; git -C "$_g" remote add origin git@github.com:evil/wrong.git 2>/dev/null
_bad=1; ( ROOT="$_g"; claudeos_require_remote t >/dev/null 2>&1 ) && _bad=0
git -C "$_g" remote set-url origin "git@github.com:$REMOTE_MATCH.git" 2>/dev/null
_good=0; ( ROOT="$_g"; claudeos_require_remote t >/dev/null 2>&1 ) && _good=1
if [ "$_bad" = 1 ] && [ "$_good" = 1 ]; then ok "bloque un mauvais origin, accepte le bon"; else ko "garde-fou remote (mauvais_bloqué=$_bad bon_accepté=$_good)"; fi
rm -rf "$_g"

echo "[selftest] 13. Verrou de concurrence — câblage dans backup et sync"
# MOITIÉ RETIRÉE le 2026-08-05 : elle tenait un verrou pendant deux secondes pour constater
# qu'une seconde prise non bloquante échoue, puis réussit après libération. C'est la sémantique
# de `flock`, une primitive du noyau : elle ne peut pas varier. Son absence éventuelle est
# rattrapée par `claudeos_lock` (`config.sh`), qui échoue bruyamment plutôt que de continuer
# sans verrou — le contrôle 2, lui, ne teste que python3, git et rsync, contrairement à ce que
# cette ligne affirmait jusqu'au 2026-08-07. Le test retiré coûtait plus de deux secondes par
# passage.
# CE QUI RESTE, et qui est le vrai mode de défaillance : un script qui cesse d'appeler le verrou.
_lk13=0
grep -q 'claudeos_lock' "$SELF/backup.sh" || _lk13=1
grep -q 'claudeos_lock' "$SELF/sync.sh" || _lk13=1
[ "$_lk13" = 0 ] && ok "verrou câblé dans backup et sync" || ko "verrou non câblé dans backup ou sync"

echo "[selftest] 14. Garde-fous d'intégrité — câblage du refus d'état partiel"
# MOITIÉ RETIRÉE le 2026-08-05 : le terme (a) définissait une fonction jetable pour vérifier
# qu'un compteur incrémenté rend un code de retour non nul. C'est l'arithmétique de `bash`.
# CE QUI RESTE : les scripts réels câblent-ils le refus et le bilan, et `sync.sh` vérifie-t-il
# la dérive deux fois, avant et après. C'est là qu'un oubli de mise à jour se voit.
_ierr=0
grep -q 'COPY_ERRS' "$SELF/backup.sh" || _ierr=1
grep -q 'Backup refusé' "$SELF/backup.sh" || _ierr=1
grep -q 'SYNC_ERRS' "$SELF/sync.sh" || _ierr=1
_dc=$(grep -c 'claudeos_drift' "$SELF/sync.sh" 2>/dev/null || echo 0)
[ "${_dc:-0}" -ge 2 ] || _ierr=1
[ "$_ierr" = 0 ] && ok "refus d'état partiel + garde-fous câblés (backup+sync) + post-check drift" || ko "garde-fou d'intégrité backup/sync (post-check drift 2×=$_dc)"

echo "[selftest] 15. Mémoire : propagation des suppressions avec filet — câblage (#16)"
# MOITIÉ RETIRÉE le 2026-08-05 : elle recréait trois dossiers temporaires et RÉIMPLÉMENTAIT la
# boucle de retrait des orphelins pour la tester. Antipatron nommé par
# compétence `controles-et-alarmes` : tester une reproduction valide la reproduction, pas la garde
# en place — la vraie logique vit dans `synclib.sh` et un écart entre les deux passait inaperçu.
# CE QUI RESTE : la logique est bien dans la bibliothèque, et `sync.sh` l'appelle.
_m16=0
grep -q 'absent du repo → retiré du live' "$SELF/synclib.sh" || _m16=1
grep -q 'claudeos_mem_restore' "$SELF/sync.sh" || _m16=1
# AVERTIT depuis le 2026-08-14 (arbitrage global bloquant/avertissement) : le défaut gardé
# est qu'une note supprimée REVIENNE, jamais qu'elle soit détruite — ni perte irréversible,
# ni fuite, ni désarmement d'une garde de sauvegarde.
[ "$_m16" = 0 ] && ok "propagation des suppressions câblée (synclib + sync.sh)" || warn "propagation suppression mémoire (#16) — câblage à revérifier"

echo "[selftest] 16. Visibilité des suppressions miroir — câblage (#9)"
# MOITIÉ RETIRÉE le 2026-08-05 : elle vérifiait qu'un essai à blanc de `rsync` liste un fichier
# voué à suppression, en réimplémentant à côté le filtre qui écarte les dossiers. Sémantique de
# l'outil plus reproduction de notre filtre — aucun des deux n'est un comportement de ce système.
# CE QUI RESTE : `sync.sh` annonce-t-il les suppressions en miroir. Un oubli là se voit.
_n9=0
grep -q 'suppression(s) en miroir' "$SELF/sync.sh" || _n9=1
# AVERTIT depuis le 2026-08-14 : la suppression en miroir est VOULUE par le dépôt, qui en
# garde l'historique — un défaut d'annonce encombre, il ne détruit rien.
[ "$_n9" = 0 ] && ok "annonce des suppressions en miroir câblée dans sync.sh" || warn "visibilité suppressions miroir (#9) — câblage à revérifier"

echo "[selftest] 17. Alarme binaires (#6)"
# MOITIÉ RETIRÉE le 2026-08-07 : elle montait un dépôt jetable pour vérifier que `git numstat`
# marque un binaire `-\t-`. Double faute, chacune ayant déjà motivé un retrait le 2026-08-05 —
# c'est la sémantique de git, invariante, ET une reproduction : le bac à sable refaisait le
# pipeline `numstat + awk` à côté au lieu d'exercer celui de `backup.sh`, si bien qu'une dérive
# du filtre réel l'aurait laissé vert. Ce qui garde encore la classe : l'alarme réelle de
# `backup.sh`, bloquante et annoncée, au moment où un binaire est mis en file.
# CE QUI RESTE ICI : les deux scripts appellent-ils encore l'alarme et son échappatoire.
_b6=0
grep -q 'ALARME BINAIRE' "$SELF/backup.sh" || _b6=1
grep -q 'FORCE_BINARY' "$SELF/backup.sh" || _b6=1
[ "$_b6" = 0 ] && ok "alarme binaires et son override câblées dans backup.sh" || ko "alarme binaires (#6)"

echo "[selftest] 18. Politique secrets — câblage (#4 FORCE dégroupé, whitelist, scan boot)"
_s2=0
for v in FORCE_FRESH FORCE_SELFTEST FORCE_SECRET FORCE_BINARY; do grep -q "$v" "$SELF/backup.sh" || _s2=1; done
grep -q 'system/secrets-shared' "$SELF/backup.sh" || _s2=1
grep -q 'SECURITY_DEBT' "$SELF/boot-check.sh" || _s2=1
# Terme DÉGROUPÉ le 2026-08-14 : la présence du dossier n'est pas un câblage d'alarme, et
# groupée elle produisait le même refus qu'une alarme secret décâblée. Elle avertit seule ;
# les autres termes du contrôle — le câblage anti-fuite réel — restent bloquants.
[ -d "$HOME/.claude/secrets-shared" ] || warn "dossier ~/.claude/secrets-shared/ absent — à créer (mkdir) ; les alarmes secret, elles, restent câblées et bloquantes"
# Régression : un secret dans secrets-shared/ DOIT être synchronisé (ne pas être ré-exclu
# par un motif SYNC_IGNORE sans slash, cf. le trou service_api_key.txt attrapé le 02/07).
_ss=$(mktemp -d); _sd=$(mktemp -d); mkdir -p "$_ss/secrets-shared"; echo k > "$_ss/secrets-shared/service_api_key.txt"
rsync -a --exclude-from="$SYNC_IGNORE" "$_ss/" "$_sd/" 2>/dev/null
[ -f "$_sd/secrets-shared/service_api_key.txt" ] || _s2=1
rm -rf "$_ss" "$_sd"
# #8 : alarme secret par NOM (jumeau alarme binaire) — câblage + comportement du motif.
grep -q 'SECRET_NAME_RE' "$SELF/backup.sh" || _s2=1
grep -q "':!\*.md'" "$SELF/backup.sh" || _s2=1
_snr='(secret|passw(or)?d|credential|api[._-]?key|[._-]token)'
printf 'service_api_key.txt\n' | grep -qEi "$_snr" || _s2=1          # nom évocateur → doit matcher
if printf 'ecran_saisie.yaml\n' | grep -qEi "$_snr"; then _s2=1; fi  # nom anodin → ne doit pas matcher
# #9 : alarme donnée client — câblage + comportement (data-texte sonne, .md non).
grep -q 'FORCE_DATA' "$SELF/backup.sh" || _s2=1
grep -q 'ALARME DONNÉE' "$SELF/backup.sh" || _s2=1
_dre='\.(csv|tsv|txt|json|xml|eml|msg)$'
printf 'table_export.csv\n' | grep -qEi "$_dre" || _s2=1              # donnée texte → doit matcher
printf 'compte_rendu.TXT\n'  | grep -qEi "$_dre" || _s2=1              # casse majuscule → doit matcher
if printf 'design.md\n' | grep -qEi "$_dre"; then _s2=1; fi            # .md (base de connaissance) → ne doit pas matcher
[ "$_s2" = 0 ] && ok "FORCE dégroupé + whitelist + scan boot + secrets-shared + alarme nom (#8) + alarme donnée (#9)" || ko "câblage politique secrets"

echo "[selftest] 19. Wave 4 backup/sync — câblage (#15 purge filet, #7 marqueur hors-ligne, #10 msg rebase)"
# MOITIÉ RETIRÉE le 2026-08-05 : elle datait un dossier de quarante jours pour vérifier que
# `find -mtime +30` le trouve. Sémantique de l'outil. CE QUI RESTE : les quatre vérifications de
# câblage, qui attrapent le mode de défaillance réel — un script mis à jour, l'autre oublié.
_w4=0
grep -q 'mtime +30' "$SELF/sync.sh" || _w4=1
grep -q '.last-offline-backup' "$SELF/backup.sh" || _w4=1
grep -q '.last-offline-backup' "$SELF/boot-check.sh" || _w4=1
grep -q 'PAS poussé' "$SELF/backup.sh" || _w4=1
[ "$_w4" = 0 ] && ok "purge >30j + marqueur hors-ligne câblés (backup+boot) + msg post-abort" || warn "Wave 4 backup/sync (#15/#7/#10)"

echo "[selftest] 20. Wave 4 boot/hooks — câblage (#8 awk robuste, #23 clean-ads, #25 sonde taille)"
# MOITIÉ RETIRÉE le 2026-08-05 : elle vérifiait qu'`awk` compte, qu'`awk` sur un fichier absent
# rend zéro, et que `find -delete` supprime. Sémantique d'outils, invariante. CE QUI RESTE : les
# trois vérifications de câblage, plus le fait que le nettoyage des flux Windows dérive bien son
# périmètre du manifeste au lieu de le recopier.
_w4b=0
grep -q "awk '/^## /" "$SELF/boot-check.sh" || _w4b=1
{ [ -x "$SELF/clean-ads.sh" ] && grep -q 'claudeos_pairs' "$SELF/clean-ads.sh"; } || _w4b=1
grep -q 'du -sk' "$SELF/boot-check.sh" || _w4b=1
# APPELANT de clean-ads, ajouté le 2026-08-09 avec le déplacement du balayage. Il tournait au
# déclencheur `Stop` de settings.json, donc à chaque tour d'assistant ; il est désormais appelé
# par `backup.sh`, avant la capture. Le déplacement lui laisse UN SEUL appelant, à l'intérieur
# d'un script — et rien ne remarquerait sa disparition : le nettoyage cesserait, le dépôt
# redeviendrait non clonable sur git Windows natif, et cela ne se verrait que sur l'autre poste.
# C'est le mode de défaillance exact que ce contrôle garde pour le reste de sa famille.
grep -q 'clean-ads.sh' "$SELF/backup.sh" || _w4b=1
[ "$_w4b" = 0 ] && ok "awk + clean-ads (périmètre dérivé du manifeste, appelé par backup.sh) + sonde taille câblés" || warn "Wave 4 boot/hooks (#8/#23/#25)"

# CORPUS DES RÈGLES SITUATIONNELLES — DÉRIVÉ DU DISQUE, JAMAIS LISTÉ (2026-08-09).
# Les huit fiches de `~/.claude/fiches/` sont devenues des compétences de `~/.claude/skills/`
# : le mécanisme de chargement paresseux passe d'un comportement d'outil non
# documenté à celui, documenté, des compétences. Trois contrôles ci-dessous (#21 assiette de
# poids, #22 portabilité, #23 routage) avaient le chemin `fiches/` en dur ; un glob sur le
# dossier supprimé aurait rendu zéro, c'est-à-dire trois contrôles muets d'un coup.
# Discriminant INTRINSÈQUE au corps, pour ne pas écrire ici une liste de slugs — un inventaire
# recopié est exactement ce que le contrôle #25 refuse : chaque règle situationnelle ouvre sur
# une ligne de citation « > Fiche situationnelle », formule que la conversion a conservée avec
# les corps déplacés tels quels.
# L'ANCRE DE DÉBUT DE LIGNE EST LOAD-BEARING : sans elle, la compétence `os-audit` entre dans
# le corpus parce qu'elle nomme cette formule en prose pour dire comment reconnaître une règle
# situationnelle — constaté en calibrant, l'assiette passait de 44 000 à 80 000 caractères.
_SITU="$(grep -rlE '^> Fiche situationnelle' "$HOME/.claude/skills"/*/SKILL.md 2>/dev/null | sort)"
# Un corpus VIDE est une mesure ratée, pas un petit corpus : il désarmerait #21, #22 et #23
# sans rien dire. Il bloque, parce qu'il désactive trois gardes en silence.
[ -n "$_SITU" ] || ko "aucune règle situationnelle trouvée dans ~/.claude/skills/ (motif '^> Fiche situationnelle') — les contrôles 21, 22 et 23 seraient muets"

echo "[selftest] 21. Couche règlement — alarme de dérive du poids et démarrage"
# Pas de plafond par fichier : c'est le critère d'admission du racine qui arbitre une règle,
# pas un quota au caractère près (un quota trop serré fait rogner de la prose utile pour
# faire entrer une règle légitime). Ce qu'on garde, c'est une ALARME DE DÉRIVE sur le poids
# total payé à chaque session, avec de la marge : elle attrape une réaccumulation silencieuse,
# elle n'arbitre aucune règle. Relever ces seuils est une décision, pas un contournement.
_r=0
_CMD="$HOME/.claude/CLAUDE.md"
# `_LAYER_MAX` retiré le 2026-08-07 avec la comparaison qu'il servait : la couche n'a plus de
# plafond absolu, seulement une dérive sur sept jours (voir plus bas). Une variable qu'aucun
# test ne lit est le début d'un contrôle muet — c'est ce qui est arrivé au seuil des fiches,
# désarmé en silence le 2026-08-05 par un renommage et rétabli le même jour que ce retrait.
_BOOT_MAX=3500     # bilan injecté au démarrage
# Les trois seuils de cette section sont CALIBRÉS SUR UN CORPUS PRÉCIS — celui de cette
# installation. Ils ne veulent rien dire sur un corpus d'une autre taille : trop hauts,
# l'alarme de dérive ne parle jamais ; trop bas, elle crie sur du travail ordinaire et
# apprend à ignorer la catégorie entière. Le point de reprise est posé plus bas, après
# le troisième seuil : si `config/SEUILS` existe, il gagne.
# Ce seuil a CHANGÉ DE NATURE le 2026-08-05, sur décision de l'utilisateur, et sa calibration
# a changé avec elle. Historique en deux temps :
#   - Jusqu'au 2026-08-03 il bornait une FACTURE : les fiches étaient injectées à chaque session,
#     donc leur poids se payait. Un seuil serré était juste — il valait 40 000 pour une assiette
#     de 39 358, soit environ six cents caractères de marge.
#   - Depuis le 2026-08-03 les fiches ne sont plus chargées (constaté 08-04 et 08-05). Leur poids
#     ne se paie plus. Ce seuil borne désormais la CROISSANCE DU CORPUS de règles, ce qui reste
#     un risque réel — l'accumulation sans décision est ce qui a produit l'usine à gaz dégonflée
#     le 2026-07-27 — mais un risque qui ne coûte plus de contexte.
# D'où le recalibrage : une alarme de croissance qui crie sur du travail ordinaire est du bruit,
# et un signal dont on sait qu'il ne veut rien dire apprend à ignorer la catégorie entière
# (compétence `controles-et-alarmes`). 44 000 laisse environ neuf pour cent de marge sur les 40 261
# mesurés le 2026-08-05, soit plusieurs semaines d'écriture de règles avant qu'elle parle.
# Ce n'est pas un contournement du dépassement de 261 caractères constaté ce jour-là : c'est la
# conséquence du changement de nature, et elle est écrite ici pour cette raison.
_SHEETS_GROWTH_MAX=44000  # croissance du corpus situationnel — PAS un coût par session
# Reprise de calibration, annoncée plus haut. Écrit par `calibrate.sh` : il mesure
# l'assiette réelle et ajoute une marge. Absent, les trois valeurs ci-dessus tiennent —
# comportement inchangé pour l'installation qui les a méritées.
_SEUILS="$(dirname "${BASH_SOURCE[0]}")/config/SEUILS"
# shellcheck source=/dev/null
[ -f "$_SEUILS" ] && . "$_SEUILS"
# Le RAPPEL DE VOIX a été RETIRÉ le 2026-08-05, sur décision de l'utilisateur, et sa mesure avec.
# Ce qu'il était : un fichier réinjecté à CHAQUE TOUR par un déclencheur UserPromptSubmit, mesuré
# et affiché à part parce qu'il n'était jamais additionnable aux assiettes par session — 1 525
# caractères par tour, soit plus que le règlement entier sur une séance de vingt échanges.
# Motif du retrait : ses sept points reprenaient un par un la section « voix » du règlement, qui
# est chargée à chaque session et reste la source. La conception l'écrivait elle-même — « un
# condensé de rappel, pas une source ». Perte assumée et immédiate : plus rien ne rattrape la
# dérive de ton en séance longue. L'assertion de câblage qui vivait ici est partie avec.
_size=$(python3 -c 'import sys;print(len(open(sys.argv[1],encoding="utf-8").read()))' "$_CMD" 2>/dev/null || echo 999999)
# Le bloc ALERTES est EXCLU du calcul (décision du 2026-07-26). Motif : ce plafond surveille
# la partie permanente du bilan — consigne, tableau d'état, dernière séance, fils ouverts —
# et sert à empêcher le journal complet d'y revenir. Une alerte datée n'est pas de la dérive :
# elle est bornée par construction, elle disparaît quand on la traite. Calibré alertes comprises,
# le plafond n'avait que six caractères de marge, si bien que la première dette de sécurité
# inscrite faisait tomber la plomberie et, celle-ci gardant la sauvegarde, interdisait de
# sauvegarder son travail — l'inverse du principe déjà retenu pour les plafonds de mémoire,
# volontairement en avertissement pour cette raison exacte.
_boot=$(printf '%s' "$_BOOTOUT" | python3 -c '
import json, sys, re
t = json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]
t = re.sub(r"--- ALERTES ---.*?(?=--- )", "", t, flags=re.S)
print(len(t))
' 2>/dev/null || echo 999999)
_boot_brut=$(printf '%s' "$_BOOTOUT" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]))' 2>/dev/null || echo 999999)
# Un fichier ABSENT est sauté, il ne fait pas tomber la mesure. Motif : le fichier du proxy
# n'existe que si le proxy est installé, et il est facultatif. Sans ce saut, son absence
# faisait échouer la somme entière, la mesure valait la sentinelle d'erreur, et l'alarme de
# poids criait en permanence — sur un chiffre qui ne mesurait rien. Une alarme dont on sait
# qu'elle ne veut rien dire apprend à ignorer la catégorie entière.
_layer=$(python3 -c '
import os, sys
print(sum(len(open(p, encoding="utf-8").read()) for p in sys.argv[1:] if os.path.exists(p)))
' "$_CMD" "$HOME/.claude/RTK.md" "$MEM/MEMORY.md" 2>/dev/null || echo 999999)
# Constaté le 2026-07-31 : les fiches étaient injectées AU DÉMARRAGE, étiquetées comme
# instructions globales au même titre que le règlement — alors que la conception les annonce
# chargées sur déclencheur. Aucun import ni hook ne les chargeait : le comportement venait de
# l'outil, qui balayait le dossier au seul motif de son nom (`rules`).
# Conséquence mesurée à l'époque : le poids réel par session valait 2,7 fois celui surveillé
# ici, et la doctrine « une règle du règlement se finance par une extraction vers une fiche »
# n'économisait rien.
# RÉPARÉ le 2026-08-03 par renommage du dossier en `fiches/`. Constaté le 2026-08-04, reconstaté
# le 2026-08-05, sur les deux postes : les fiches ne sont plus dans le contexte d'une session
# neuve. La mesure ci-dessous reste donc utile comme suivi de la croissance du corpus, mais elle
# ne représente PLUS un coût par session — voir le message d'avertissement et le document de conception
# Leur seuil est arbitré par l'utilisateur, jamais déduit.
# Même mesure que `calibrate.sh`, qui écrit le seuil : les deux doivent bouger ensemble,
# sinon le seuil calibré ne borne plus ce qui est mesuré.
_sheets=$(printf '%s\n' "$_SITU" | python3 -c '
import sys
tot = 0
for p in sys.stdin.read().split():
    tot += len(open(p, encoding="utf-8").read())
print(tot)
' 2>/dev/null || echo 999999)
_session=$(( _layer + _sheets ))
[ "$_boot" -gt "$_BOOT_MAX" ] && { warn "bilan de démarrage hors alertes : $_boot car. > $_BOOT_MAX (le journal complet y est-il reparti ?)"; _r=1; }
# Le PLAFOND ABSOLU de la couche ne déclenche plus rien depuis le 2026-08-07, sur décision de
# l'utilisateur. Motif, arithmétique : 20 000 caractères font environ 6 000 jetons pour une
# fenêtre d'un million. On optimisait 0,6 %. Les dégâts réels de ce système ne viennent pas du
# volume mais de la CONTRADICTION — une rotation déclarée due à deux endroits opposés, un rituel
# renvoyant à des étapes supprimées, un pointeur vers un fichier fantôme. Aucun n'aurait été
# évité par un fichier plus court, et deux ont été CRÉÉS par un dégraissage.
# Ce qui reste vrai, et qu'on garde : l'accumulation sans décision. Une couche qui grossit
# semaine après semaine sans qu'une règle en sorte est un symptôme de discipline, pas de coût.
# On mesure donc une DÉRIVE, contre la même couche sept jours plus tôt, et non une taille.
_LAYER_GROWTH_MAX=2500   # croissance sur 7 jours ; ce n'est pas une taille
_ref=$(git -C "$ROOT" rev-list -1 --before='7 days ago' HEAD 2>/dev/null)
if [ -n "$_ref" ]; then
    _layer_avant=0
    for _f in system/CLAUDE.md system/RTK.md system-memory/MEMORY.md; do
        _n=$(git -C "$ROOT" show "$_ref:$_f" 2>/dev/null | wc -m)
        _layer_avant=$(( _layer_avant + _n ))
    done
    if [ "$_layer_avant" -gt 0 ]; then
        _croissance=$(( _layer - _layer_avant ))
        if [ "$_croissance" -gt "$_LAYER_GROWTH_MAX" ]; then
            warn "couche toujours-chargée : +$_croissance car. en 7 jours (> $_LAYER_GROWTH_MAX) — accumulation sans extraction ; nommer la règle qui sort, ou dire pourquoi aucune ne peut sortir"
            _r=1
        fi
    fi
fi

# L'alarme du corpus des fiches a été DÉSARMÉE EN SILENCE le 2026-08-05 : la comparaison
# existait sous le nom `_SHEETS_MAX`, le renommage en `_SHEETS_GROWTH_MAX` a emporté le test
# sans emporter le seuil ni l'affichage. Le chiffre restait montré « x/44000 » sans que rien
# ne le lise, et le commentaire du jour promettait pourtant qu'il « parle ». Rétablie le
# 2026-08-07. Elle AVERTIT — c'est de l'accumulation, donc de l'encombrement, et la fiche
# des contrôles réserve le blocage à ce qui désactive en silence.
[ "$_sheets" -gt "$_SHEETS_GROWTH_MAX" ] && { warn "corpus des règles situationnelles : $_sheets car. > $_SHEETS_GROWTH_MAX — croissance des règles sans extraction ; ce n'est pas un coût par session, c'est une accumulation sans décision"; _r=1; }
# LES MESURES S'AFFICHENT TOUJOURS, verdict ou pas *(découplé le 2026-08-09)*. Défaut corrigé :
# la ligne récapitulative était gardée par `[ "$_r" = 0 ]`, donc dès qu'un avertissement tirait,
# les trois grandeurs — couche par session, bilan de démarrage, corpus situationnel — quittaient
# la sortie. Le contrôle devenait muet exactement le jour où l'on avait besoin de ses chiffres
# pour arbitrer, et il ne restait qu'un dépassement sans son contexte. Un contrôle de dérive dont
# la mesure ne paraît qu'en l'absence de dérive n'informe personne.
_mesures="racine $_size car. ; PAYÉ PAR SESSION : couche $_layer (mesure, sans plafond ; dérive 7 j surveillée) (+ démarrage $_boot/$_BOOT_MAX hors alertes, $_boot_brut brut, + injections de l'outil non mesurées) ; NON payé par session : corpus situationnel $_sheets/$_SHEETS_GROWTH_MAX ; total des règles écrites $_session car."
if [ "$_r" = 0 ]; then
    ok "$_mesures"
else
    # Même flux que `ok` (stdout) et non celui de `warn` : les chiffres sont un constat, pas
    # une alerte, et ils doivent survivre à une lecture qui écarte la sortie d'erreur.
    echo "  ℹ️  mesures (l'avertissement ci-dessus ne les masque plus) : $_mesures"
fi

echo "[selftest] 22. Portabilité — aucun chemin propre à un poste dans les fichiers d'instruction"
# Rattaché à MULTIPOSTE le 2026-08-14 : la règle qu'il garde (« aucun chemin propre à un
# poste ») est retirée du règlement quand la condition est fausse. Exiger alors des
# instructions portables, c'est bloquer la sauvegarde pour un défaut que la personne a
# explicitement décliné — même faute que celle corrigée au contrôle 10.
if ! condition_vraie MULTIPOSTE; then
    echo "  ⏭  sauté : la condition MULTIPOSTE est fausse dans $_CONDITIONS"
else
# AVERTIT depuis le 2026-08-14 : un chemin propre à un poste est un défaut DOCUMENTAIRE —
# le contrôle 27 attrape ce qui pointe dans le vide. Bloquer ici faisait payer une erreur
# de carte par une interdiction de sauvegarder.
_p=0
_slug="$(echo "$HOME" | sed 's#/#-#g')"
# Le nom du dossier de mémoire auto dérive du dossier personnel : il diffère d'un poste
# à l'autre. Écrit en dur dans une instruction, il pointe dans le vide ailleurs.
# Le `find` n'est lancé que si des workstations existent : sur un ensemble vide, il
# balaierait le dossier courant par défaut — un contrôle qui lit hors de son périmètre.
_h=$( { grep -rl -- "$_slug" "$_CMD" "$HOME/.claude/skills" 2>/dev/null; \
        [ "${#_WS[@]}" -gt 0 ] && find "${_WS[@]}" \( -name CLAUDE.md -o -name DESIGN.md \) -print0 2>/dev/null \
          | xargs -0 grep -l -- "$_slug" 2>/dev/null; } | sort -u)
[ -n "$_h" ] && { warn "slug de poste ('$_slug') en dur : $(echo "$_h" | tr '\n' ' ')"; _p=1; }
# Un slug FAUX passerait le test ci-dessus (il ne cherche que le bon). Motif générique :
# tout '-home-…' / '-Users-…' dans une instruction est un nom de dossier de mémoire figé.
_h3=$(grep -rlE -- 'projects/-(home|Users|c|mnt)[A-Za-z0-9_-]*/' "$_CMD" "$HOME/.claude/skills" 2>/dev/null | sort -u)
[ -n "$_h3" ] && { warn "nom de dossier de mémoire figé (résoudre le slug, ne pas l'écrire) : $(echo "$_h3" | tr '\n' ' ')"; _p=1; }
# Chemins absolus dans les fichiers du système lui-même (périmètre où l'on est prescriptif).
# PÉRIMÈTRE INCHANGÉ AU 2026-08-09, volontairement : la conversion des fiches en compétences
# remplace `~/.claude/fiches` par les seules compétences SITUATIONNELLES ($_SITU), pas par
# tout `skills/`. Élargir à tout le dossier ferait entrer les compétences empruntées et celles
# qui documentent un chemin de conteneur, donc un blocage neuf sur du
# préexistant sous couvert de recâblage. Cet élargissement est une décision à part.
_h2=$(printf '%s\n' "$_SITU" | xargs grep -lE -- '/home/[a-z_][a-z0-9_-]*/|/Users/[A-Za-z]' "$_CMD" "$HOME/.claude/DESIGN.md" 2>/dev/null | sort -u)
[ -n "$_h2" ] && { warn "chemin absolu en dur dans le règlement ou une règle situationnelle : $(echo "$_h2" | tr '\n' ' ')"; _p=1; }
[ "$_p" = 0 ] && ok "règlement, règles situationnelles et instructions de workstation sans chemin propre à un poste"
fi

echo "[selftest] 23. Routage — règles situationnelles et registre des ratés"
# RECÂBLÉ le 2026-08-09 (conversion des fiches en compétences, le document de conception).
# Ce que ce contrôle gardait avant : une fiche présente dans `~/.claude/fiches/` mais absente
# de la table `CLAUDE.md` §3.3 (orpheline, jamais chargée), et une fiche citée par la table
# mais absente du disque (pointeur mort). La table n'existe plus : le déclencheur EST la
# `description` du frontmatter, et c'est l'outil qui la charge. Les deux moitiés deviennent :
#   (a) toute règle situationnelle porte une `description` non vide — elle seule la route ;
#       une description absente est une règle qui ne se charge jamais, et rien ne le dirait ;
#   (b) toute compétence citée par une instruction du système existe sur le disque.
# BLOQUE dans les deux cas, par le partage de la compétence `controles-et-alarmes` : dans les
# deux, une règle existe, le système croit l'appliquer, et elle ne se charge jamais.
_rt=0
while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    grep -qE '^description: *[^[:space:]]' "$_f" \
        || { ko "règle situationnelle sans description — donc sans déclencheur : $(basename "$(dirname "$_f")")"; _rt=1; }
done <<< "$_SITU"
# (b) MOTIF : la forme sous laquelle les instructions de ce système nomment une compétence —
# « compétence `slug` » en toutes lettres. On ne cherche PAS un slug nu entre guillemets
# obliques : trop courant pour discriminer, et le faux positif apprendrait à ignorer la
# catégorie entière. On ne cherche pas non plus « fiche `slug` » : la même forme désigne
# aussi des non-compétences dans ce corpus (`fiche pending` en le document de conception), donc le motif
# crierait sur du texte juste. Les pointeurs de cette forme ont été réécrits en
# « compétence » le 2026-08-09 pour tomber sous ce motif.
while read -r _n; do
    [ -z "$_n" ] && continue
    # Compétences CONDITIONNELLES : leur retrait est un choix de l'entretien, pas un
    # pointeur mort — un contrôle qui exige un artefact dont l'existence dépend d'une
    # condition lit cette condition (2026-08-14, même classe que les contrôles 10, 22, 28).
    # La paire compétence↔condition reflète celle d'assemble-rules.sh (chaîne d'export),
    # seul autre endroit qui la connaît : les deux se corrigent ensemble.
    case "$_n" in
        livrables)     condition_vraie LIVRABLE || continue ;;
        rtk-depannage) condition_vraie PROXY    || continue ;;
    esac
    [ -f "$HOME/.claude/skills/$_n/SKILL.md" ] \
        || { ko "compétence citée par une instruction mais absente du disque : $_n"; _rt=1; }
done < <(grep -rhoE 'compétences? `[a-z][a-z0-9-]+`' \
             "$_CMD" "$HOME/.claude/DESIGN.md" "$HOME/.claude/HANDOFF.md" "$HOME/.claude/MEMORY.md" \
             "$HOME/.claude/skills"/*/SKILL.md "$HOME/.claude/skills"/*/*.md "$HOME/.claude/agents"/*.md 2>/dev/null \
           | grep -oE '`[a-z][a-z0-9-]+`' | tr -d '`' | sort -u)
# Le registre des ratés n'est exigé que si la règle qui l'alimente existe : elle est
# retirée du règlement quand MULTIDOMAINE est fausse (rattaché le 2026-08-14, même
# faute que celle corrigée au contrôle 10 — exiger ce qui a été décliné).
if ! condition_vraie MULTIDOMAINE; then
    echo "  ⏭  registre des ratés non exigé : la condition MULTIDOMAINE est fausse dans $_CONDITIONS"
else
    [ -f "$MEM/ROUTING_MISSES.md" ] || { ko "registre des ratés de routage absent ($MEM/ROUTING_MISSES.md)"; _rt=1; }
    grep -q 'ROUTING_MISSES' "$HOME/.claude/skills/os-audit/SKILL.md" 2>/dev/null \
        || { ko "l'audit ne lit pas le registre des ratés — la boucle de correction est morte"; _rt=1; }
fi
[ "$_rt" = 0 ] && ok "règles situationnelles toutes routées par leur description, compétences citées toutes présentes, registre des ratés lu par l'audit"

echo "[selftest] 24. Durabilité — plafond du journal, copies de sync exclues du scan d'index"
_d=0
# PREMIER TERME RETIRÉ le 2026-08-05 : il guettait la réapparition de la chaîne littérale
# 'claude-config-backup', chemin de sauvegarde abandonné avant le 2026-07-03. Elle ne peut
# revenir que si quelqu'un la retape de mémoire. Ce qui garde réellement la destination de la
# sauvegarde est la garde d'origin, exercée sur fonction réelle par le contrôle 12 et appelée
# en tête de `backup.sh` et `sync.sh`. Les deux autres termes de ce contrôle restent.
# Compte des JOURS DISTINCTS et non des séances, depuis le 2026-08-05 : plusieurs séances
# tombent le même jour — jusqu'à quatre — donc un plafond en séances était franchi par
# construction dès le troisième jour et son avertissement criait en permanence. Le plafond
# lui-même est LU dans l'en-tête du journal, jamais recopié ici : c'est là qu'il est déclaré,
# avec son unité et son motif (règle « un fait calculable ne s'écrit pas », `memoire-et-verite`).
_js=$(grep -oE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' "$MEM/SESSION_JOURNAL.md" 2>/dev/null | sort -u | wc -l)
_jmax=$(grep -oE '\*\*[0-9]+ jours max\*\*' "$MEM/SESSION_JOURNAL.md" 2>/dev/null | grep -oE '[0-9]+' | head -1)
_jmax=${_jmax:-7}
# Avertissement et NON échec (2026-07-27). Motif, payé sur pièce le jour même : l'écriture
# incrémentale du journal en cours de séance crée mécaniquement une 7e entrée, alors que la
# rotation vers l'archive appartient au seul rituel de clôture. Codé en échec, ce contrôle
# refusait donc la sauvegarde de toute séance qui n'était pas encore close — soit toutes celles
# où le mécanisme d'incrément fait son travail. C'est la DEUXIÈME fois que ce système fait payer
# un dépassement de contenu par une interdiction de sauvegarder : la première était le plafond
# du bilan de démarrage, calibré si serré que la première dette de sécurité inscrite faisait
# tomber la plomberie (voir contrôle 21). La règle est désormais écrite dans
# compétence `controles-et-alarmes` : un défaut de contenu avertit, une corruption de
# plomberie bloque. Un journal trop long est un défaut de contenu — il se voit, il se range à la
# clôture, et il ne doit jamais coûter le travail d'une matinée.
[ "${_js:-0}" -gt "$_jmax" ] && warn "journal de session : $_js jours > $_jmax (plafond déclaré en tête du fichier) — rotation due à la prochaine passe hebdomadaire"
grep -q 'sync-backups' "$SELF/build-index.sh" \
    || { warn "build-index n'exclut plus .sync-backups/ — l'index référencera des copies périmées"; _d=1; }
[ "$_d" = 0 ] && ok "journal à ${_js}/${_jmax} jours, copies de sync exclues du scan d'index"

echo "[selftest] 25. La documentation suit-elle le code ?"
# L'audit du 25/07 a montré le motif : le code bouge, les documents qui le décrivent restent.
# On garde deux affirmations mécaniquement vérifiables plutôt que d'espérer une relecture.
_doc=0
_real=$(grep -c '^echo "\[selftest\] [0-9]' "$SELF/selftest.sh")
# Le nombre de contrôles est CALCULABLE depuis ce script : l'écrire ailleurs crée une copie
# qui se périme (trois documents divergents constatés le 25/07). Le correctif n'est pas de
# tenir les copies en phase, c'est de ne plus en écrire. On refuse donc tout compteur en dur.
while IFS= read -r _f; do
    [ -f "$_f" ] || continue
    # Motif élargi le 2026-07-27 : il ne voyait que les contrôles, et laissait donc passer
    # « six fiches », inscrit à QUATRE endroits de DESIGN.md et faux depuis la création de la
    # septième. Tout inventaire dont le compte se dérive du disque est concerné, pas seulement
    # celui des contrôles. Les nombres qui documentent une DÉCISION (un seuil choisi, une durée
    # retenue) restent légitimes : c'est pourquoi le motif cible des noms d'inventaire précis
    # et non « un nombre suivi d'un mot ».
    # Un compteur en CHIFFRES devant un nom d'inventaire annonce presque toujours un total.
    # `compétences` ajouté le 2026-08-09 avec la conversion des fiches : le nom de
    # l'inventaire a changé, le défaut qu'il guette non.
    _claim=$(grep -oiE '\b[0-9]+ (contrôles|tests|fiches|compétences|workstations)\b' "$_f" 2>/dev/null | head -3)
    # Les nombres ÉCRITS EN MOTS sont ambigus : « les trois contrôles qui gardent cette zone »
    # désigne un sous-ensemble, pas un total, et le flaguer produirait un faux positif — qu'on
    # apprendrait à ignorer, avec les vrais. On ne les retient donc que pour le seul cas où le
    # total est certain : un compte de règles sur la même ligne que le dossier qui les contient.
    # C'est la forme exacte des quatre occurrences de « six fiches » trouvées le 2026-07-27.
    # Borne de proximité en NOMBRE DE CARACTÈRES, pas « jusqu'au prochain point » : le chemin
    # du dossier contient lui-même des points (`~/.claude/skills/`), si bien qu'un motif borné
    # par `[^.]*` ne l'atteignait jamais et le contrôle restait muet sur le cas exact qu'il
    # visait — constaté à l'exercice de son cas positif.
    # DEUX FORMES DEPUIS LE 2026-08-09 : l'ancienne (`fiches` près de `fiches/`) reste, parce
    # qu'un document peut encore raconter l'état d'avant la conversion et y remettre un compte ;
    # la neuve (`compétences` près de `skills/`) est celle qui garde l'état courant.
    _claim="$_claim$(grep -oiE '\b(deux|trois|quatre|cinq|six|sept|huit|neuf|dix|onze|douze) (fiches\b.{0,60}fiches/|compétences\b.{0,60}skills/)' "$_f" 2>/dev/null | head -2)"
    [ -n "$_claim" ] && { warn "inventaire écrit en dur dans $(basename "$_f") ($(echo "$_claim" | tr '\n' ' ')) — il se compte à sa source ; retirer le nombre, ne pas le mettre à jour"; _doc=1; }
done <<EOF
$HOME/.claudeos/README.md
$HOME/.claude/DESIGN.md
$MEM/INDEX.md
EOF
# BRANCHE RETIRÉE le 2026-08-07 : elle cherchait la chaîne littérale « 250 lignes » dans la
# conception. « plafond de deux cent cinquante lignes » la désarmait. C'est exactement la classe
# du contrôle 31, retiré le 2026-08-05 avec ce motif écrit : « il gardait UN incident daté sous
# une forme littérale que toute reformulation désarme ». Ce qui garde encore : la branche
# générique des inventaires ci-dessous, et l'audit sur la véracité de la conception. Au retour
# du défaut, c'est une dérive documentaire de classe avertissement, rattrapée à l'audit suivant.

# L'ancienne branche « DESIGN.md mentionne-t-il fiches/ ? » était VERTE PAR CONSTRUCTION : la
# chaîne y figure des dizaines de fois, donc le contrôle ne pouvait rien détecter et affichait
# pourtant « DESIGN.md à jour sur la couche des fiches ». C'est pire qu'un contrôle absent : il
# délivrait une assurance fausse. Remplacée le 2026-07-27 par trois vérifications qui peuvent
# échouer — et c'est ce trou qui a laissé l'inventaire des fiches incomplet et deux de ses
# déclencheurs divergents jusqu'à ce qu'un audit les trouve à la main.
_D="$HOME/.claude/DESIGN.md"
# RECÂBLÉ le 2026-08-09 : l'inventaire de le document de conception nomme des COMPÉTENCES par leur slug
# (`memoire-et-verite`) là où il nommait des fichiers de fiche par leur ancien nom.
# Sans ce recâblage, (a) bouclait sur un dossier supprimé — donc muet — et (b) cherchait un
# motif `[A-Z_]+\.md` que l'inventaire neuf ne porte plus — donc muet aussi.
# (a) Complétude : toute règle situationnelle est-elle nommée dans DESIGN.md ?
_miss=$(while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    _s="$(basename "$(dirname "$_f")")"
    grep -q "\`$_s\`" "$_D" 2>/dev/null || echo "$_s"
done <<< "$_SITU")
[ -n "$_miss" ] && { warn "règle situationnelle absente de l'inventaire de DESIGN.md : $(echo "$_miss" | tr '\n' ' ')— la référence de design ignore une couche qui existe"; _doc=1; }
# (b) Sens inverse : une ligne de l'inventaire pointe-t-elle une compétence disparue ?
# Le nombre de colonnes reste le discriminant : l'inventaire situationnel en a DEUX depuis le
# retrait de la colonne des déclencheurs, tandis que la table des types de fichiers du même
# document en a quatre. Sans cette borne, le contrôle réclamait `CLAUDE.md`, `MEMORY.md` et
# consorts dans le dossier des règles — faux positif constaté à son premier passage.
# Le slug en minuscules est le second discriminant : aucune autre table à deux colonnes du
# document n'ouvre sur un mot en kebab-case entre guillemets obliques (vérifié au 2026-08-09).
_ghost=$(grep -oE '^\| `[a-z][a-z0-9-]+` \| [^|]+ \|$' "$_D" 2>/dev/null | sed -E 's/^\| `([a-z][a-z0-9-]+)`.*/\1/' | while read -r _n; do
    [ -f "$HOME/.claude/skills/$_n/SKILL.md" ] || echo "$_n"
done)
[ -n "$_ghost" ] && { warn "l'inventaire de DESIGN.md cite une compétence absente de ~/.claude/skills/ : $(echo "$_ghost" | tr '\n' ' ')"; _doc=1; }
# (c) Anti-régression, RECIBLÉE le 2026-08-09. Elle guettait le retour de la colonne des
#     déclencheurs, retirée le 2026-07-27 parce qu'elle recopiait la table du racine. Cette
#     table n'existe plus : le déclencheur vit dans la `description` du frontmatter, et c'est
#     désormais ELLE qu'un inventaire pourrait recopier — même défaut, nouvelle source.
_dup=$(python3 - "$_D" $_SITU <<'PYDUP' 2>/dev/null
import os, re, sys
design = open(sys.argv[1], encoding="utf-8").read()
out = []
for p in sys.argv[2:]:
    txt = open(p, encoding="utf-8").read()
    m = re.search(r'^description: *(.+)$', txt, re.M)
    if not m:
        continue
    # Fragment SUFFISAMMENT LONG pour ne pas coïncider par hasard : une description
    # entière ne serait jamais recopiée mot pour mot, c'est son ouverture qui migre.
    frag = m.group(1).strip()[:60]
    if len(frag) > 40 and frag in design:
        out.append(os.path.basename(os.path.dirname(p)))
print(" · ".join(out))
PYDUP
)
[ -n "$_dup" ] && { warn "déclencheur de règle situationnelle recopié dans DESIGN.md ($_dup) — il vit dans la description de la compétence, seule source du routage"; _doc=1; }
[ "$_doc" = 0 ] && ok "aucun inventaire en dur, inventaire situationnel de DESIGN.md complet dans les deux sens, aucun déclencheur recopié"

echo "[selftest] 26. Amorçage — le gabarit crée-t-il dans l'arbre sauvegardé ?"
# L'EXISTENCE DU GABARIT N'EST PLUS TESTÉE ICI (2026-08-07) : le contrôle 27 vérifie déjà, en
# bloquant, que tous les chemins cités par les règles existent — et le racine cite ce gabarit
# entre guillemets obliques, forme exacte qu'il balaie. Deux gardes pour le même défaut.
# CE QUI RESTE, et qui est unique : le gabarit crée-t-il DANS l'arbre sauvegardé.
_tpl="$HOME/resources/WORKSTATION_TEMPLATE.md"
if [ ! -f "$_tpl" ]; then ok "⏭ sauté : gabarit absent — son existence est gardée par le contrôle 27"
elif grep -qE '`~/<Nom' "$_tpl"; then
    # AVERTIT depuis le 2026-08-14 : ce qui met un domaine dans le filet est sa ligne au
    # manifeste, pas son emplacement — un gabarit déviant se corrige, il ne perd rien.
    warn "le gabarit crée hors de ~/workstations/ — la workstation naîtrait hors du filet, sans que rien n'échoue"
else ok "toutes les destinations du gabarit sont sous ~/workstations/"; fi

echo "[selftest] 27. Chemins morts dans les fichiers d'instruction"
# selftest 7 couvre les références entre scripts ; ici ce sont les chemins cités par les
# RÈGLES et les procédures. C'est ce qui aurait attrapé d'un coup les procédures mortes du 25/07.
# PÉRIMÈTRE RECÂBLÉ le 2026-08-09 : les fiches sont devenues des compétences, et les seules
# règles SITUATIONNELLES entrent ici — passées en arguments depuis `$_SITU`. Élargir à tout
# `skills/` ferait entrer les compétences empruntées et celles qui documentent des chemins de
# conteneur, donc un blocage neuf sur du préexistant sous couvert de recâblage. Cet
# élargissement est une décision à part, pas un effet de bord de la conversion.
# Les racines de workstation passent par l'ENVIRONNEMENT et non par argv : `$_SITU` y est
# volontairement non quoté (un fichier par mot), et y mêler des racines rendrait argv ambigu.
_dead=$(CLAUDEOS_WS_ROOTS="$(printf '%s\n' "${_WS[@]}")" python3 - $_SITU <<'PYEOF' 2>/dev/null
import re, os, glob, sys
H = os.path.expanduser('~')
files = [f'{H}/.claude/CLAUDE.md'] + sys.argv[1:] + glob.glob(f'{H}/resources/*.md')
for _root in os.environ.get('CLAUDEOS_WS_ROOTS', '').splitlines():
    if not _root.strip(): continue
    files += glob.glob(f'{_root}/CLAUDE.md') + glob.glob(f'{_root}/*/CLAUDE.md')
skip = re.compile(r'[<>*{}]|MÉMOIRE|slug')       # gabarits et jokers : pas des chemins réels
out = []
for f in files:
    try: txt = open(f, encoding='utf-8').read()
    except OSError: continue
    for m in re.finditer(r'`(~/[^`\s]+)`', txt):
        p = m.group(1)
        if skip.search(p): continue
        if not os.path.exists(os.path.expanduser(p.rstrip('.,;:'))):
            out.append(f"{os.path.relpath(f, H)} → {p}")
print('\n'.join(sorted(set(out))))
PYEOF
)
if [ -n "$_dead" ]; then
    # AVERTIT depuis le 2026-08-14 : un pointeur mort envoie la session dans le vide, il ne
    # désactive ni ne détruit rien — même classe que le contrôle 45. C'est ce contrôle qui a
    # refusé une première sauvegarde le jour de l'arbitrage.
    warn "chemin cité par une règle mais absent du disque :"; echo "$_dead" | sed 's/^/       /' >&2
else ok "tous les chemins cités par les règles et les procédures existent"; fi

echo "[selftest] 28. Réceptacle des documents client à la racine de chaque projet"
# Décision du 2026-07-25 : le réceptacle vit au niveau PROJET seulement
# (`workstations/<DOMAINE>/<PROJET>`), pas au niveau application. On n'en attend donc
# aucun plus profond, et on n'en réclame pas un aux apps ni aux sous-dossiers.
# Rattaché à CONFIDENTIEL le 2026-08-14 : le réceptacle est la fonction que cette
# condition fait entrer, et l'exiger de qui l'a déclinée bloquait sa sauvegarde —
# même faute que celle corrigée au contrôle 10, il ne lisait pas la condition.
if ! condition_vraie CONFIDENTIEL; then
    echo "  ⏭  sauté : la condition CONFIDENTIEL est fausse dans $_CONDITIONS"
elif [ "${#_WS[@]}" -eq 0 ]; then
    # Sans cette branche, `find` sur un ensemble vide balaierait le dossier courant.
    echo "  ⏭  sans objet : aucun domaine déclaré au manifeste (dit en tête de l'autotest)"
else
_noign=$(find "${_WS[@]}" -mindepth 1 -maxdepth 1 -type d \
    -not -name "_IGNORE" \
    2>/dev/null | while read -r d; do [ -d "$d/_IGNORE" ] || echo "${d#$HOME/}"; done)
if [ -n "$_noign" ]; then
    # AVERTIT depuis le 2026-08-14 : la fuite elle-même est gardée par le contrôle 10 et par
    # les alarmes de backup.sh — ici c'est un réceptacle manquant, défaut de rangement.
    warn "projet sans réceptacle \`_IGNORE/\` à sa racine (le premier document client y atterrirait en zone sauvegardée) :"
    echo "$_noign" | sed 's/^/       /' >&2
else ok "tous les projets ont leur réceptacle à leur racine"; fi
fi

echo "[selftest] 29. Plafonds auto-déclarés des mémoires (avertissement, ne bloque pas)"
# MOTIF DE DÉCLARATION UNIQUE, extrait le 2026-08-09 en élargissant le périmètre à la mémoire
# automatique : deux boucles lisent désormais la même déclaration, et deux copies d'un motif
# aussi subtil (classe de chiffres tolérant un séparateur de milliers, unité facultative)
# auraient divergé au premier correctif porté sur une seule.
_PLAF_RE='Plafond : [0-9][0-9  ]* *(caractères|caracteres|mots|lignes)?'
# L'UNITÉ se lit, elle ne se suppose pas (corrigé le 2026-07-27). Deux mémoires déclaraient
# « Plafond : 300 mots » ; le contrôle ne lisait que le nombre et le comparait à un nombre de
# LIGNES, si bien qu'un plafond de 300 mots devenait un plafond de 300 lignes — jamais atteint,
# donc ces deux mémoires n'étaient pas surveillées du tout. Une unité ignorée ne produit pas une
# erreur, elle produit un contrôle muet, ce qui est pire.
# Ensemble vide : pas de `find` sans chemin (il balaierait le dossier courant).
_over=$([ "${#_WS[@]}" -gt 0 ] && for _m in $(find "${_WS[@]}" -name MEMORY.md 2>/dev/null); do
    # Trois unités reconnues : caractères, mots, lignes. « caractères » est ajoutée le 2026-08-05,
    # jour où l'unité de tous les plafonds de mémoire est passée aux caractères — et le motif est
    # celui-là même que cette section documente déjà : une unité non reconnue ne produit pas une
    # erreur, elle produit un contrôle muet ou un faux positif. Ici c'était un faux positif :
    # « Plafond : 4 000 caractères » était lu « 4 », comparé à un nombre de lignes, et une mémoire
    # de 2 Ko était déclarée en dépassement. Le séparateur de milliers est retiré avant lecture,
    # sans quoi 4 000 devient 4.
    _decl=$(grep -m1 -oE "$_PLAF_RE" "$_m" 2>/dev/null)
    # `tr -cd '0-9'` : on ne garde QUE les chiffres, ce qui absorbe n'importe quel séparateur de
    # milliers — espace ordinaire, insécable, fine. Écrit d'abord en `tr -d` avec une liste de
    # caractères échappés, ce qui a supprimé les chiffres 0 et 2 : `tr` ne connaît pas `\xNN` et
    # traitait chaque lettre de l'échappement comme un caractère à retirer. « 40 » devenait « 4 »,
    # et deux mémoires conformes étaient déclarées en dépassement. Faux positif né du correctif.
    _lim=$(printf '%s' "$_decl" | tr -cd '0-9')
    if [ -z "$_lim" ]; then echo "${_m#$HOME/} : aucun plafond déclaré"; continue; fi
    # Les commentaires HTML sont EXCLUS de la mesure (2026-07-27). Le plafond borne le CONTENU ;
    # or la note qui déclare le plafond et justifie son niveau est elle-même dans un commentaire,
    # si bien qu'expliquer un plafond le faisait dépasser — le fichier se condamnait en se
    # documentant. Même correction que celle du 26/07 sur le bilan de démarrage, où le bloc
    # d'alertes gonflait la mesure qu'il n'était pas censé alimenter (contrôle 21).
    _body=$(python3 -c '
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
sys.stdout.write(re.sub(r"<!--.*?-->", "", t, flags=re.S))
' "$_m" 2>/dev/null || cat "$_m")
    case "$_decl" in
        *caract*) _n=$(printf '%s' "$_body" | wc -m); _u=caractères ;;
        *mots*)   _n=$(printf '%s' "$_body" | wc -w); _u=mots ;;
        *)        _n=$(printf '%s\n' "$_body" | grep -c ''); _u=lignes ;;   # défaut historique : lignes
    esac
    [ "$_n" -gt "$_lim" ] && echo "${_m#$HOME/} : $_n/$_lim $_u"
done)
# PÉRIMÈTRE ÉLARGI À LA MÉMOIRE AUTOMATIQUE le 2026-08-09. Le balayage ci-dessus ne voyait que
# les `MEMORY.md` des workstations, si bien qu'`ORIGINES_DES_REGLES.md` déclarait un plafond en
# en-tête que rien ne lisait : un plafond que personne ne mesure n'existe pas, et celui-là borne
# le fichier de récits, c'est-à-dire le plus enclin à grossir de tout le corpus.
# DIFFÉRENCE DE RÉGIME, VOULUE : ici on ne signale QUE les fichiers qui déclarent un plafond.
# Une mémoire de workstation sans plafond est un oubli, et la boucle du haut le dit ; un fichier
# de la mémoire automatique sans plafond est le cas normal — les vues générées, le journal, les
# retours mémorisés n'en veulent pas — donc en réclamer un produirait une liste permanente qu'on
# apprendrait à ignorer, et avec elle la catégorie entière.
_over_mem=$(for _f in "$MEM"/*.md; do
    [ -f "$_f" ] || continue
    _decl=$(grep -m1 -oE "$_PLAF_RE" "$_f" 2>/dev/null)
    [ -n "$_decl" ] || continue
    _lim=$(printf '%s' "$_decl" | tr -cd '0-9')
    [ -n "$_lim" ] || continue
    _body=$(python3 -c '
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
sys.stdout.write(re.sub(r"<!--.*?-->", "", t, flags=re.S))
' "$_f" 2>/dev/null || cat "$_f")
    # AUCUN REPLI SUR LES LIGNES ICI, contrairement à la boucle du haut. Ce repli y est un
    # héritage daté d'une époque où tous les plafonds de mémoire étaient en lignes ; appliqué à
    # ce dossier, il fabriquerait un faux positif au premier plafond exprimé dans une unité que
    # ce contrôle ne mesure pas — le journal en déclare un en JOURS, lu par le contrôle 24. Une
    # unité illisible se dit donc, au lieu d'être devinée.
    case "$_decl" in
        *caract*) _n=$(printf '%s' "$_body" | wc -m); _u=caractères ;;
        *mots*)   _n=$(printf '%s' "$_body" | wc -w); _u=mots ;;
        *lignes*) _n=$(printf '%s\n' "$_body" | grep -c ''); _u=lignes ;;
        *) echo "${_f#$HOME/} : plafond $_lim déclaré sans unité que ce contrôle sache mesurer"; continue ;;
    esac
    [ "$_n" -gt "$_lim" ] && echo "${_f#$HOME/} : $_n/$_lim $_u"
done)
_over_all=$(printf '%s\n%s\n' "$_over" "$_over_mem" | grep -v '^[[:space:]]*$')
if [ -n "$_over_all" ]; then warn "mémoires à compresser ou à doter d'un plafond :"; echo "$_over_all" | sed 's/^/       /' >&2
else ok "plafonds respectés et déclarés — mémoires de domaine, plus les fichiers à plafond de la mémoire automatique"; fi

echo "[selftest] 30. Rappel échu : le démarrage le sort-il vraiment ?"
# Motif (2026-07-26) : le bloc de rappels est resté MUET de sa création au 2026-07-26.
# `REMINDERS.md` n'avait pas de retour à la ligne final et `while IFS= read -r` abandonne
# alors sa dernière ligne — qui est, par construction, le rappel le plus récent, donc le
# seul actif. La vérification d'origine (2026-07-03) ne testait que le cas NÉGATIF — un
# rappel à échéance future n'est pas affiché — jamais le cas positif. Ce contrôle teste le
# cas positif, seul capable d'attraper la classe entière (cf. le document de conception).
# AVERTIT depuis le 2026-08-14, arbitré par l'utilisateur : la dette de sécurité a son
# propre bloc, et le contrôle 4 garde le bilan de démarrage lui-même — un rappel muet
# encombre, il ne désarme pas une garde de sauvegarde.
_r=0
# (a) Anti-régression : la garde de dernière ligne est-elle toujours dans la boucle ?
grep -qF 'read -r rline || [ -n "$rline" ]' "$SELF/boot-check.sh" \
    || { warn "garde de dernière ligne absente de la boucle des rappels (boot-check.sh) — un fichier sans retour à la ligne final reperdrait son rappel le plus récent"; _r=1; }
# (b) Cas positif, sur données réelles : tout rappel dont l'échéance est atteinte doit
#     apparaître dans le bilan injecté. Sans rappel échu au moment du contrôle, (b) est
#     inapplicable — on le dit, on ne le maquille pas en succès.
_due=$(python3 - "$MEM/REMINDERS.md" <<'PY' 2>/dev/null || echo 0
import re, sys, datetime
try: t = open(sys.argv[1], encoding="utf-8").read()
except OSError: print(0); raise SystemExit
today = datetime.date.today()
n = sum(1 for d in re.findall(r"^- (\d{4}-\d{2}-\d{2}) *\|", t, re.M)
        if datetime.date.fromisoformat(d) <= today)
print(n)
PY
)
if [ "${_due:-0}" -gt 0 ]; then
    _seen=$(printf '%s' "$_BOOTOUT" | python3 -c '
import json, sys
t = json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]
print(t.count("⏰"))
' 2>/dev/null || echo 0)
    [ "${_seen:-0}" -eq 0 ] && { warn "$_due rappel(s) échu(s) dans REMINDERS.md mais AUCUN dans le bilan de démarrage — le bloc est muet"; _r=1; }
    [ "$_r" = 0 ] && ok "garde de dernière ligne en place + $_due rappel(s) échu(s) effectivement sorti(s) au démarrage"
else
    [ "$_r" = 0 ] && ok "garde de dernière ligne en place (aucun rappel échu à ce jour — cas positif non exercé)"
fi

# CONTRÔLE 31 RETIRÉ le 2026-08-05 — il cherchait un plafond du règlement racine codé en dur
# dans une fiche de compétence. Motif d'origine réel : la fiche d'audit affirmait 14 000
# caractères pour un règlement qui avait abandonné tout plafond, et aurait fait conclure à un
# dépassement là où le système était conforme. Retiré parce qu'il gardait UN incident daté sous
# une forme littérale — quatre chiffres sur la même ligne qu'un mot parmi trois — que toute
# reformulation désarme. Ce qui protège vraiment de cette classe reste écrit : un fait calculable
# ne se recopie pas, il se lit à sa source (compétence `memoire-et-verite`), et les seuils vivent
# dans ce script et nulle part ailleurs.

echo "[selftest] 32. Toute workstation avec une mémoire a une reprise"
# Motif (2026-07-27) : la règle est écrite dans la référence de design et n'était vérifiée
# nulle part — elle a échoué deux fois sur quatre workstations. Avertissement et non échec :
# une workstation neuve n'a rien à reprendre le jour de sa création, et un manque de contenu
# ne doit jamais empêcher d'enregistrer du travail (cf. commentaire de `warn`). Portée : le
# premier niveau seulement — un projet ou une app n'est pas concerné.
_nohand=$(for _r0 in "${_WS[@]}"; do
    _m="$_r0/MEMORY.md"
    [ -f "$_m" ] || continue
    _d=$(dirname "$_m")
    [ -f "$_d/HANDOFF.md" ] || echo "${_d#$HOME/}"
done)
if [ -n "$_nohand" ]; then
    warn "workstation avec mémoire mais sans reprise (\`HANDOFF.md\`) — un fil suspendu y serait invisible :"
    echo "$_nohand" | sed 's/^/       /' >&2
else ok "toute workstation dotée d'une mémoire a sa reprise"; fi

echo "[selftest] 33. Tout dossier routé par un CLAUDE.md local existe sur le disque"
# Motif (2026-07-27) : les instructions d'un domaine posaient un document de référence comme
# obligatoire pour tout projet, et deux projets routés n'en avaient pas. La
# liste auditée est celle de la table de ROUTAGE du projet, pas celle du disque : c'est le
# routage qui promet qu'une app est traitable, donc c'est lui qui crée la dette.
# CE QUE CE CONTRÔLE NE FAIT PLUS, et le paragraphe qui l'affirmait était faux jusqu'au
# 2026-08-07 : il ne lit AUCUN marqueur de tolérance. Il a porté un mécanisme d'exception
# déclarée en tête de la mémoire d'une app — « EN SOMMEIL », « EN CONCEPTION », « EN OUVERTURE » —
# emporté par la réécriture du 2026-08-06 avec l'exigence de document de référence qu'il gardait.
# Ce qui reste ici est la seule question « le dossier existe-t-il », et elle n'admet pas
# d'exception. Une mémoire qui déclare encore un de ces marqueurs ne se fait donc tolérer par
# personne : c'est l'audit qui porte cette classe depuis, pas ce contrôle.
# GÉNÉRALISÉ le 2026-08-06, à la demande de l'utilisateur. Le contrôle ne visait qu'un seul
# projet client : partout ailleurs, un routage pouvait promettre un dossier inexistant sans que
# rien ne le dise. Le motif d'origine s'appuyait sur la convention de nommage de ce projet ;
# le motif générique s'appuie sur la CONVENTION D'ÉCRITURE, vérifiée sur pièce avant réécriture —
# une table de routage écrit sa cible entre guillemets obliques avec une barre oblique finale
# (`NOM_DU_DOSSIER/`). C'est un meilleur discriminant que l'ancien, pas un moins bon :
# la barre oblique reste ce qui distingue un dossier d'une liste de données homonyme, et les
# guillemets excluent la prose. Portée : 24 fichiers de routage au lieu d'un.
_ghost=""
_routes=0
# Noms de dossiers qui relèvent de la CONVENTION et non du routage : les citer n'est pas
# promettre qu'ils existent. `_IGNORE/` a déjà son propre contrôle (#28) — le compter ici
# ferait crier deux contrôles pour un seul défaut.
_conventions="_IGNORE docs scripts specs plans extracted src tools assets rapports base-documentaire"
while IFS= read -r _cm; do
    _dir="$(dirname "$_cm")"
    # SEULEMENT les lignes de TABLEAU. Première version : tout dossier entre guillemets
    # obliques, où qu'il soit. Elle a rendu cinq défauts dont quatre faux — des exemples de
    # convention de nommage cités en prose (`2023-2024/`) et une auto-référence d'un fichier
    # à son propre dossier. Le motif d'origine ne tenait pas grâce à la barre oblique seule,
    # mais parce qu'il lisait une TABLE DE ROUTAGE : c'est la table qui promet, pas la prose.
    for _t in $(grep -E '^[[:space:]]*\|' "$_cm" 2>/dev/null \
                | grep -oE '`[A-Za-z0-9_.-]+/`' | tr -d '`/' | sort -u); do
        case " $_conventions " in *" $_t "*) continue ;; esac
        _routes=$((_routes+1))
        [ -d "$_dir/$_t" ] || _ghost="${_ghost}${_dir#"$HOME"/}/$_t"$'\n'
    done
done < <([ "${#_WS[@]}" -gt 0 ] && find "${_WS[@]}" -name 'CLAUDE.md' -type f 2>/dev/null | sort)

if [ -n "$_ghost" ]; then
    # Avertissement et non échec : un dossier manquant est un vrai défaut de routage, mais
    # interdire d'enregistrer son travail pour autant ferait payer une erreur de carte par
    # une perte de travail.
    warn "dossier routé depuis un \`CLAUDE.md\` local mais ABSENT du disque — le routage promet ce qui n'existe pas :"
    printf '%s' "$_ghost" | sed 's/^/       /' >&2
else
    ok "$_routes dossier(s) routé(s) vérifié(s) sur l'ensemble des workstations"
fi

# La moitié « toute app routée porte son document de référence » a été retirée le 2026-08-05 :
# c'était de la dette documentaire métier. Conséquence toujours vraie et à connaître : la mention
# « EN CONCEPTION » que porte la mémoire d'une app, et qui affirme que « le contrôle qui l'exige
# lit cette ligne », ne sert plus de tolérance à rien — plus personne ne la lit.

echo "[selftest] 34. Liste blanche de sauvegarde — verrou en place et refus annoncé"
# BLOQUANT. Le verrou décide de ce qui part sur le dépôt, et son échec ne se manifeste par
# rien : un fichier neuf cesserait simplement d'être enregistré, en silence, sur une seule
# machine. Trois moitiés à vérifier ensemble, aucune ne suffisant seule — le verrou lui-même,
# la descente dans les dossiers sans laquelle aucune autorisation ne peut viser un fichier
# niché, et le rapport de la sauvegarde sans lequel le refus serait muet.
_wl="$ROOT/.gitignore"
_w=0
if [ ! -f "$_wl" ]; then
    ko "fichier de liste blanche absent ($_wl) — rien ne retiendrait plus un document déposé"; _w=1
else
    # Le verrou est la ligne `*` seule, pas une occurrence de `*` dans un motif : ancrer.
    grep -qE '^\*$' "$_wl" || { ko "verrou absent : la ligne \`*\` qui refuse tout fichier neuf n'est plus dans $_wl"; _w=1; }
    grep -qE '^!\*/$' "$_wl" || { ko "descente dans les dossiers absente (\`!*/\`) — une autorisation ne pourrait plus viser un fichier niché"; _w=1; }
    # L'ordre décide : le dernier motif qui correspond gagne. Un `!` d'autorisation placé
    # AVANT le verrou serait annulé par lui, et l'autorisation paraîtrait pourtant écrite.
    _lock_ln=$(grep -nE '^\*$' "$_wl" | head -1 | cut -d: -f1)
    if [ -n "$_lock_ln" ]; then
        _early=$(awk -v L="$_lock_ln" 'NR<L && /^!/ && $0 != "!*/" {print NR": "$0}' "$_wl")
        [ -n "$_early" ] && { ko "autorisation écrite AVANT le verrou, donc annulée par lui :"; printf '%s\n' "$_early" | sed 's/^/       /' >&2; _w=1; }
    fi
fi
# Le rapport de refus, dans backup.sh : sans lui le verrou est muet.
grep -q 'NON sauvegardé' "$SELF/backup.sh" 2>/dev/null \
    || { ko "la sauvegarde n'annonce plus les fichiers refusés — le verrou deviendrait silencieux"; _w=1; }
# Cas positif, exercé pour de vrai : un fichier neuf doit être refusé par le verrou lui-même.
_probe="$ROOT/.selftest-liste-blanche-$$.md"
: > "$_probe"
_rule=$(git -C "$ROOT" check-ignore -v -- "$_probe" 2>/dev/null | awk -F'\t' '{print $1}')
rm -f "$_probe"
case "$_rule" in
    *:\*) : ;;                     # refusé par le verrou : comportement attendu
    "")   ko "un fichier neuf N'EST PAS refusé — le verrou ne s'applique pas (exercé sur un fichier d'essai)"; _w=1 ;;
    *)    warn "fichier neuf refusé, mais par « $_rule » et non par le verrou — vérifier l'ordre des motifs" ;;
esac
[ "$_w" -eq 0 ] && ok "verrou en place, autorisations après lui, refus annoncé par la sauvegarde, cas positif exercé"

echo "[selftest] 35. Retombée documentaire — refuse-t-elle un argument inexploitable ?"
# Défaut du 2026-07-31 : appelée avec une DATE, comme la fiche de la passe hebdomadaire le
# prescrit, elle rendait « aucun document ne nomme ce qui a changé » — l'erreur git étant
# avalée par une redirection. Quatre jours de réécriture n'avaient donc été confrontés à
# aucun document. Ce contrôle exerce les deux cas positifs : l'argument absurde doit crier,
# et la date doit fonctionner. Le cas négatif seul ne distinguerait pas un outil muet.
# AVERTIT depuis le 2026-08-14 : impact.sh est un outil de compte rendu — muet, il fait
# rater une relecture, pas un fichier.
_i=0
bash "$SELF/impact.sh" --since "zzz-pas-une-date" >/dev/null 2>&1 \
    && { warn "un argument inexploitable est accepté — la sortie vide serait lue comme « rien à signaler »"; _i=1; }
# La date d'essai se dérive de l'HISTOIRE RÉELLE du dépôt, et non d'une fenêtre fixe.
# Motif (2026-08-06, trouvé en installant le système à neuf) : sur un dépôt créé aujourd'hui,
# aucun commit ne peut précéder une date d'il y a sept jours. L'outil refusait donc à juste
# titre — c'est sa règle, une sortie vide ne doit jamais se lire « rien à signaler » — et le
# contrôle criait sur un système parfaitement sain. Un contrôle infaisable la première semaine
# n'est pas un contrôle, c'est un faux positif à date de péremption.
_prem="$(git -C "$ROOT" log --reverse --format=%cs 2>/dev/null | head -1)"
if [ -z "$_prem" ]; then
    warn "retombée documentaire : dépôt sans historique, cas positif de la date NON exercé"
else
    _cible="$(date -d '7 days ago' +%Y-%m-%d)"
    # Si le dépôt est plus jeune que la fenêtre, on prend sa propre date de naissance :
    # le contrôle reste exercé, sur une fenêtre plus étroite, et on le dit.
    [ "$_prem" \> "$_cible" ] && { _cible="$_prem"; warn "retombée documentaire exercée sur une fenêtre réduite (dépôt né le $_prem)"; }
    if ! bash "$SELF/impact.sh" --since "$_cible" >/dev/null 2>&1; then
        warn "une date est refusée — la passe hebdomadaire ne peut plus appeler la retombée documentaire"; _i=1
    fi
fi
# La garde qui rendait le défaut muet ne doit pas revenir : le diff par référence
# ne s'exécute plus derrière une redirection d'erreur.
grep -q 'diff --name-only "$SINCE" 2>/dev/null' "$SELF/impact.sh" 2>/dev/null \
    && { warn "la redirection d'erreur est revenue sur le diff par référence — l'échec redeviendrait silencieux"; _i=1; }
[ "$_i" -eq 0 ] && ok "argument absurde refusé (code 2), date acceptée et résolue, redirection d'erreur absente"

echo "[selftest] 36. Secret hors de son emplacement autorisé, y compris en zone non sauvegardée (avertissement)"
# Classe de défaut que rien ne gardait, constatée le 2026-08-03 : une valeur de secret vivait
# dans un dossier de compétence. Les alarmes de `backup.sh` (#8, contenu et nom) ne pouvaient
# pas la voir — elles inspectent ce qui est MIS EN FILE pour le dépôt, et la liste blanche
# refusait ce fichier. Un secret mal rangé dans une zone que la sauvegarde ignore est donc
# parfaitement invisible pour elles. Ce n'est pas une fuite, c'est un rangement : rien n'est
# parti, rien n'est désactivé, et ça se corrige quand on le voit. Donc AVERTIT et ne bloque
# pas, par le partage de la compétence `controles-et-alarmes` — bloquer ici ferait payer un défaut
# de rangement par l'impossibilité de sauvegarder, la faute que ce partage existe pour éviter.
#
# Motifs : ceux de config.sh, partagés avec backup.sh — jamais recopiés (règle « un seuil
# défini dans un script ne se recopie pas ailleurs »).
#
# Emplacements AUTORISÉS, donc exclus du scan — les deux régimes de `secrets-detail` :
#   ~/.claude/secrets-shared/  → faible valeur, synchronisé, seul emplacement autorisé pour
#                                une valeur dans l'arbre sauvegardé.
#   */_IGNORE/*                → haute valeur, local-only strict, hors sauvegarde.
# Exclus aussi : ce que l'outil gère seul (transcriptions, caches, historique, identifiants)
# et le dossier de plugins — ni authorés ni sous notre contrôle, et bruyants par nature.
_r=0
_sec_hits=$(
    for _root in "$HOME/.claude" "${_WS[@]}" "$HOME/resources" "$HOME/docs"; do
        [ -d "$_root" ] || continue
        find "$_root" -type f \
            -not -path "*/_IGNORE/*" \
            -not -path "$HOME/.claude/secrets-shared/*" \
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
            -not -path "$HOME/.claude/.sync-backups/*" \
            -not -path "$HOME/.claude/ide/*" \
            -not -name ".credentials.json" \
            -not -name "history.jsonl" \
            2>/dev/null
    done | while IFS= read -r _f; do
        # Fichiers texte seulement : un binaire produirait du bruit sans information.
        # `grep -I` et non `file` (2026-08-07). Motif, et il est grave : `file` n'est pas
        # installé sur ce poste et n'est dans aucune dépendance dure. Son mime vide tombait
        # dans la branche par défaut, donc `continue` — TOUS les fichiers étaient sautés, et
        # le contrôle affichait vert en affirmant « arbre entier, zones non sauvegardées
        # comprises ». Un garde de secrets qui ne gardait rien, sans jamais le dire.
        # `grep -I` porte la même distinction texte/binaire, il est dans coreutils, et il est
        # déjà employé deux lignes plus bas — la dépendance était donc gratuite.
        if [ -s "$_f" ] && ! grep -Iq . "$_f" 2>/dev/null; then continue; fi
        # (a) le CONTENU porte une forme d'éditeur (casse exacte) ou un mot-clé suivi d'une valeur
        if grep -lE  "$CLAUDEOS_SECRET_RE_FORMES" "$_f" >/dev/null 2>&1 \
        || grep -liE "$CLAUDEOS_SECRET_RE_MOTS"   "$_f" >/dev/null 2>&1; then
            echo "${_f#$HOME/} : contenu"
            continue
        fi
        # (b) le NOM annonce un secret — filet derrière (a), qui rate une valeur nue dont le
        # mot-clé vit sur une autre ligne. Les `.md` sont exclus de ce second motif seulement :
        # un document SUR les secrets n'en porte pas la valeur, et la mémoire de projet en
        # parle constamment (« credentials dans _IGNORE/… »). Le motif de contenu, lui,
        # continue de s'appliquer aux `.md` — c'est lui qui attraperait une vraie valeur.
        #
        # ET le fichier doit porter une valeur PLAUSIBLE : au moins une ligne non commentée
        # contenant une chaîne d'au moins 20 caractères sans espace. Ajouté le 2026-08-03 après
        # un faux positif diagnostiqué dans la séance — un fichier `service_api_key.txt` dont
        # la ligne utile est un gabarit « colle ta clé ici », résidu d'une régénération, la
        # vraie clé vivant depuis dans `secrets-shared/`. Sans cette condition, la branche par
        # nom sonne sur tout gabarit et on apprend à ignorer la catégorie entière. Le seuil de
        # 20 est celui du motif MOTS de `config.sh`, pas un second chiffre : une clé d'éditeur
        # est plus longue, et le trou du 2026-07-03 était une valeur nue de 40 caractères.
        # Contrepartie assumée : une clé plus courte que 20 caractères dans un fichier au nom
        # évocateur mais sans mot-clé de contenu échapperait aux deux branches.
        case "$_f" in
            *.md) ;;
            *) printf '%s\n' "$_f" | grep -qiE "$CLAUDEOS_SECRET_NAME_RE" \
                 && grep -vE '^\s*#|^\s*$' "$_f" 2>/dev/null | grep -qE '[^[:space:]]{20,}' \
                 && echo "${_f#$HOME/} : nom + valeur plausible" ;;
        esac
    done | head -10
)
if [ -n "$_sec_hits" ]; then
    warn "secret(s) hors emplacement autorisé — à classer, pas à ignorer :"
    echo "$_sec_hits" | sed 's/^/       /' >&2
    echo "       Faible valeur → ~/.claude/secrets-shared/ ; haute valeur → un _IGNORE/ ou hors arbre." >&2
    echo "       Faux positif ? Ce contrôle avertit et ne bloque rien : la sauvegarde tourne." >&2
    _r=1
fi
[ "$_r" = 0 ] && ok "aucune valeur de secret hors de secrets-shared/ et des _IGNORE/ (arbre entier, zones non sauvegardées comprises)"

echo "[selftest] 38. Ce que la copie dépose et que le verrou refuse — texte seulement"
# BLOQUANT, et c'est le contrôle d'une CLASSE, pas d'un cas. Le manifeste et le verrou sont
# deux fichiers écrits séparément : le premier décide de ce qui est COPIÉ vers le dépôt, le
# second de ce qui y est ENREGISTRÉ. Rien ne les apparie. Un dossier présent dans l'un et
# absent de l'autre produit le pire défaut de ce système : la copie dépose fidèlement, git
# refuse en silence, et personne ne s'en aperçoit — sur la machine où le fichier existe
# localement, tout a l'air normal. Deux instances déjà payées, les dossiers de travail puis
# les gabarits, la seconde découverte seulement en installant une deuxième machine.
# Limité aux `.md` volontairement : le reste (binaires, tableurs, exports) est refusé
# EXPRÈS, et la sauvegarde annonce déjà ces refus-là. Le texte, lui, doit toujours passer.
_orph=""
while IFS=$'\t' read -r _live _sub _reg; do
    case "$_live" in ''|'#'*) continue ;; esac
    [ -n "$_sub" ] || continue
    [ -d "$ROOT/$_sub" ] || continue
    _f=$(git -C "$ROOT" ls-files --others --ignored --exclude-standard -- "$_sub" 2>/dev/null | grep '\.md$' | head -5)
    [ -n "$_f" ] && _orph="$_orph$_f"$'\n'
done < <(tr -s ' ' '\t' < "$SYNC_MAP" 2>/dev/null)
if [ -n "$(printf '%s' "$_orph" | tr -d '[:space:]')" ]; then
    ko "fichiers texte déposés dans le dépôt et refusés par le verrou — jamais sauvegardés, en silence :"
    printf '%s' "$_orph" | sed '/^$/d; s/^/       /' >&2
    echo "       → ajouter l'autorisation correspondante dans $ROOT/.gitignore" >&2
else
    ok "tout fichier texte déposé par la copie est accepté par le verrou"
fi

echo "[selftest] 39. Chemins vivants qu'aucune des deux listes n'a tranchés"
# BLOQUANT. Le 38 ci-dessus regarde ce qui est DÉJÀ dans le dépôt, et seulement les `.md`,
# au motif que « le reste est refusé exprès ». Cette limite reposait sur une hypothèse :
# que la liste d'exclusions soit complète. Elle ne l'était pas, et c'est ce qui a coûté le
# plus cher — sur une installation tierce, dix-neuf chemins recopiés dans l'arbre du dépôt
# et refusés au commit, dont le fichier d'identifiants OAuth de l'outil. Ils étaient bien
# annoncés à chaque clôture, sans plafond ; c'est justement le problème : un avertissement
# qu'on lit tous les jours cesse d'être lu. Il fallait une porte, pas une ligne de plus.
#
# Le raisonnement tient en une phrase : entre les deux listes, l'attrape-tout n'est PAS une
# décision. Un chemin doit être exclu nommément de la copie, ou autorisé nommément par le
# verrou. Tomber sur `*` signifie que personne n'a tranché, et un chemin non tranché peut
# être n'importe quoi — un cache de trois giga-octets comme un jeton d'authentification.
#
# On n'imite ni rsync ni git : on les interroge. `rsync --dry-run` dit ce que la copie
# emporterait ; `git check-ignore -v` dit par QUELLE règle le verrou le refuse, et c'est la
# règle citée qui discrimine. Mesuré à un peu plus d'une seconde sur une installation
# complète, parce que ce qui est exclu de la copie n'est jamais énuméré.
_TMP39="$(mktemp -d)"; _nontranches=""
while IFS=$'\t' read -r _live _sub _reg; do
    case "$_live" in ''|'#'*) continue ;; esac
    [ -n "$_sub" ] || continue
    [ -d "$HOME/$_live" ] || continue
    while IFS= read -r _e; do
        [ -n "$_e" ] || continue
        _rg="$(git -C "$ROOT" check-ignore -v -- "$_sub/$_e" 2>/dev/null | awk -F'\t' '{print $1}')"
        [ -n "$_rg" ] || continue
        case "$_rg" in *:\*) ;; *) continue ;; esac
        _nontranches="$_nontranches$_sub/$_e"$'\n'
    # FICHIERS SEULEMENT — rsync émet aussi les dossiers, terminés par `/`, et un dossier
    # « refusé » ne prouve rien : le verrou refuse tous les dossiers par principe puis
    # réautorise leurs fichiers nommément. Juger un contenant à la place de son contenu
    # faisait échouer ce contrôle sur une installation parfaitement saine, ce qui est la
    # façon la plus rapide de faire désarmer un contrôle neuf.
    done < <(rsync -rn --exclude-from="$SYNC_IGNORE" --out-format='%n' "$HOME/$_live/" "$_TMP39/" 2>/dev/null \
             | grep -v '/$' | sort -u | head -40)
done < <(tr -s ' ' '\t' < "$SYNC_MAP" 2>/dev/null)
rm -rf "$_TMP39"
if [ -n "$(printf '%s' "$_nontranches" | tr -d '[:space:]')" ]; then
    ko "chemins qu'aucune des deux listes n'a tranchés — copiés par la synchro, refusés par l'attrape-tout :"
    printf '%s' "$_nontranches" | sed '/^$/d; s/^/       /' | head -20 >&2
    echo "       → décider pour chacun : exclusion nommée dans $SYNC_IGNORE," >&2
    echo "         ou autorisation nommée dans $ROOT/.gitignore. L'attrape-tout n'est pas une décision." >&2
else
    # L'échantillonnage s'annonce (2026-08-07) : ce contrôle ne sonde que les 40 premiers
    # fichiers copiables de chaque entrée du manifeste, borne de coût sur un chemin qui garde la
    # sauvegarde. Un plafond silencieux se lit comme une couverture complète — la règle du
    # système interdit de tronquer sans le dire.
    ok "aucun chemin vivant ne tombe entre les deux listes (sondage borné aux 40 premiers fichiers par entrée du manifeste)"
fi

echo "[selftest] 40. Capacité déclarée opérante mais non invocable"
# BLOQUANT. C'est la classe que la fiche des contrôles range explicitement dans les blocages :
# une règle existe, le système croit l'appliquer, elle ne se charge jamais — rien n'échoue, donc
# seul un blocage l'attrape. Écrit en avertissement le 2026-08-07 le temps que son unique
# instance soit arbitrée, puis passé bloquant le même soir dès qu'elle l'a été.
#
# La classe : une compétence que la référence de design ou une fiche désigne comme porteuse
# d'un geste, alors que son frontmatter porte `disable-model-invocation: true` et qu'aucune
# fiche ne dit à l'assistant de la proposer. Les deux côtés sont cohérents, rien n'échoue, et
# la capacité n'est jamais atteinte. Trois défauts de cette famille ont été trouvés dans le
# seul audit du 2026-08-07, tous nés de la réduction du rituel de clôture du 2026-07-27, et
# aucun par balayage — un par une question de l'utilisateur, deux par hasard.
#
# Ce qui débloque légitimement : soit une fiche dit de proposer la compétence à l'utilisateur
# (le geste est alors cherché, pas le nom — un nom cité peut n'être qu'une mention), soit
# l'interdiction d'auto-invocation est retirée, soit le document cesse de lui donner le rôle.
# Les trois sont des décisions ; la seule chose interdite est de laisser les trois en l'état.
_c40=""
for _sk in "$HOME"/.claude/skills/*/SKILL.md; do
    [ -f "$_sk" ] || continue
    grep -q '^disable-model-invocation: *true' "$_sk" || continue
    _n="$(basename "$(dirname "$_sk")")"
    # Cité comme opérant par la conception ou une fiche ?
    # `--exclude-dir` : sans lui, le grep trouve la compétence dans SON PROPRE corps et
    # déclare toute compétence « citée », ce qui rend le contrôle vert par construction
    # (2026-08-09, avec le déplacement du périmètre des fiches vers les compétences).
    _cite="$(grep -rl --exclude-dir="$_n" -- "$_n" "$HOME/.claude/DESIGN.md" "$HOME/.claude/skills/" 2>/dev/null | tr '\n' ' ')"
    [ -n "$_cite" ] || continue
    # Échappatoire légitime : une fiche dit de la PROPOSER à l'utilisateur. On cherche le
    # geste, pas le nom — un nom cité peut n'être qu'une mention.
    grep -rqE --exclude-dir="$_n" "(proposer|inviter|lancer|invoquer).{0,80}$_n|/$_n" "$HOME/.claude/skills/" 2>/dev/null && continue
    _c40="$_c40$_n (cité par : $_cite)"$'\n'
done
if [ -n "$(printf '%s' "$_c40" | tr -d '[:space:]')" ]; then
    ko "compétence(s) déclarées opérantes mais non invocables — le système croit la capacité active :"
    printf '%s' "$_c40" | sed '/^$/d; s/^/       /' >&2
    echo "       → soit une fiche dit de la proposer, soit retirer disable-model-invocation," >&2
    echo "         soit retirer son rôle du document qui la cite. Ne pas laisser les trois en l'état." >&2
else
    ok "aucune capacité déclarée opérante sans chemin d'invocation"
fi


echo "[selftest] 45. Pointeurs de la couche curatée d'INDEX.md (avertissement, ne bloque pas)"
# ÉCRIT LE 2026-08-09, sur le défaut du jour : la couche curatée pointait quinze fois vers
# `~/.claude/fiches/`, supprimé le matin même par la conversion des règles situationnelles en
# compétences. Or cette couche est la carte que le règlement fait consulter AVANT tout travail de
# fond : ses pointeurs morts n'ont fait échouer aucun script, ils ont simplement envoyé la
# session dans le vide. La classe se reproduira à chaque réorganisation — c'est ce qui la rend
# mécanisable, et c'est pour ça que le contrôle existe plutôt qu'un rappel dans une procédure.
# AVERTIT : un pointeur mort encombre la carte, il ne désactive aucune règle (une règle non
# routée, elle, bloque — voir contrôle 23).
# CE QU'IL JUGE, et rien d'autre : les compétences citées (`compétence <slug>` / `skill <slug>` /
# `skills/<slug>`) doivent exister dans `~/.claude/skills/`, et les chemins cités doivent se
# résoudre. CE QU'IL NE JUGE PAS, et le dit en clair dans sa sortie : les renvois de section
# (`le document de conception`), les repères de journal (`JOURNAL 2026-06-28`), les notes d'un coffre de notes externe
# (un préfixe convenu, hors de l'arbre sauvegardé) et les noms
# nus sans chemin ni extension. Le compte des non-jugés est AFFICHÉ : un contrôle qui tairait
# l'étendue de ce qu'il ignore laisserait croire à une couverture totale.
_ptr=$(python3 - "$MEM/INDEX.md" "$MEM" <<'PY' 2>/dev/null
import os, re, sys, fnmatch

idx, MEM = sys.argv[1], sys.argv[2]
HOME = os.path.expanduser("~")
try:
    txt = open(idx, encoding="utf-8").read()
except OSError:
    raise SystemExit(0)          # pas de sortie => mesure ratée, le bash le dit
curated = txt.split("<!-- AUTO:START", 1)[0]

# Ancres possibles d'un chemin cité, du plus explicite au plus court.
ANCHORS = [HOME, os.path.join(HOME, ".claude"), os.path.join(HOME, ".claudeos"), MEM]
# Arbre balayé pour les citations relatives au projet (`<PROJET>/DESIGN.md`) : on retient
# tous les chemins et on accepte une correspondance par la FIN. Les dossiers sautés sont du
# runtime ou du transcript, jamais une cible de pointeur.
ROOTS = [os.path.join(HOME, p) for p in ("workstations", ".claude", ".claudeos", "resources", "docs")] + [MEM]
SKIP = {".git", "node_modules", "__pycache__", ".sync-backups", "plugins",
        "todos", "shell-snapshots", "statsig", "ide", "projects", ".venv"}
PATHS = set()
for r in ROOTS:
    if not os.path.isdir(r):
        continue
    for dp, dns, fns in os.walk(r):
        dns[:] = [d for d in dns if d not in SKIP]
        for n in list(dns) + fns:
            PATHS.add(os.path.join(dp, n))

EXT = (".md", ".sh", ".json", ".yaml", ".yml", ".ps1", ".py", ".txt")

def resolves(c):
    c = c.strip().rstrip("/")
    if c.startswith("~/"):
        c = c[2:]
    if c.startswith("<mémoire>/"):
        return os.path.exists(os.path.join(MEM, c.split("/", 1)[1]))
    cands = [c]
    # Un agent se cite par son slug (`agents/<slug>`) là où une compétence se cite
    # par son dossier : compléter en `.md` est la même convention, pas une indulgence.
    if not c.endswith(EXT):
        cands.append(c + ".md")
    for x in cands:
        if "*" in x:
            if any(fnmatch.filter(PATHS, os.path.join(a, x)) for a in ANCHORS):
                return True
            if any(fnmatch.fnmatch(p, "*/" + x) for p in PATHS):
                return True
            continue
        if any(os.path.exists(os.path.join(a, x)) for a in ANCHORS):
            return True
        if any(p.endswith(os.sep + x) for p in PATHS):
            return True
    return False

judged, skipped, bad = 0, 0, []
for block in re.findall(r"`\[([^\]]+)\]`", curated):
    for item in block.split("·"):
        item = item.split(",")[0]                       # prose après une virgule
        item = re.sub(r"\s*\([^)]*\)", "", item)        # parenthèse d'aparté
        item = re.sub(r"\s*§.*$", "", item).strip()     # renvoi de section
        if not item or item.startswith("wiki "):
            skipped += 1
            continue
        m = re.match(r"^(?:compétence|skill)\s+([a-z0-9-]+)$", item)
        if m:
            judged += 1
            if not os.path.isdir(os.path.join(HOME, ".claude", "skills", m.group(1))):
                bad.append("compétence citée absente de ~/.claude/skills/ : " + m.group(1))
            continue
        if "/" in item or item.endswith(EXT):
            judged += 1
            if not resolves(item):
                bad.append("chemin cité introuvable : " + item)
            continue
        skipped += 1
for b in bad:
    print(b)
# Un corpus de citations VIDE est une mesure ratée, pas une carte propre.
print("#BILAN %d pointeur(s) jugé(s), %d non jugé(s)" % (judged, skipped) if judged else "#VIDE")
PY
)
_bilan=$(printf '%s\n' "$_ptr" | grep -m1 '^#')
_ptr_ko=$(printf '%s\n' "$_ptr" | grep -v '^#' | grep -v '^[[:space:]]*$')
if [ -z "$_bilan" ] || [ "$_bilan" = "#VIDE" ]; then
    warn "pointeurs de la couche curatée : AUCUNE citation lue dans $MEM/INDEX.md — mesure ratée, ce contrôle est muet (fichier absent, couche 🧭 vidée, ou forme des citations changée)"
elif [ -n "$_ptr_ko" ]; then
    warn "pointeurs de la couche curatée d'INDEX.md qui ne résolvent pas — ${_bilan#\#BILAN } :"
    printf '%s\n' "$_ptr_ko" | sed 's/^/       /' >&2
else
    ok "tous les pointeurs de la couche curatée résolvent — ${_bilan#\#BILAN }"
fi

# CONTRÔLE 44 RETIRÉ le 2026-08-07, le soir même de son écriture. Il mesurait ce que le 21 ne
# comptait pas — descriptions de compétences et corps chargés d'office — et il avait raison sur
# le fait : le coût réel était d'environ 35 000 caractères contre 21 000 affichés. Mais la
# décision prise le même soir rend la mesure sans emploi : on ne borne plus un volume, on
# surveille une accumulation sans décision. Un chiffre qu'on n'arbitre plus est du bruit, et il
# invitait à des dégraissages qui déplacent le texte d'un fichier chargé vers un autre au lieu
# de le supprimer. Le fait qu'il a établi reste écrit dans le rapport d'audit du 2026-08-07.
echo "[selftest] 46. Reprises — sections de fils ouverts qu'aucun titre reconnu ne ratisse (#26)"
# POURQUOI CE CONTRÔLE EXISTE. `build-threads.sh` ne ratisse que des titres nommés, et son propre
# commentaire l'avoue depuis toujours : « défaut silencieux par construction : rien ne signale
# qu'un fichier bien écrit n'est pas ratissé ». Mesuré le 2026-08-12 : huit reprises sur seize
# portaient des titres non reconnus, et onze fils n'apparaissaient dans aucune vue du matin — dont
# cinq sections « Fil ouvert » au SINGULIER dans un projet, une marquée PRIORITAIRE. Élargir le motif
# ne suffit pas : la liste des façons d'écrire « à faire » n'est pas énumérable. C'est l'alarme qui
# ferme le trou, pas le motif.
#
# ASYMÉTRIE ASSUMÉE. L'heuristique ci-dessous est VOLONTAIREMENT plus large que le motif du
# générateur : un faux positif ici coûte un avertissement qu'on renomme ou qu'on ignore, un faux
# négatif là-bas coûte un fil invisible pendant des semaines. On règle donc le bruit du bon côté.
#
# La liste des titres reconnus est DÉRIVÉE de `build-threads.sh`, jamais recopiée : deux listes à
# deux âges se contrediraient, et c'est précisément ce genre d'écart qui a caché les onze fils.
python3 - "$SELF/build-threads.sh" "$HOME" <<'PY'
import glob, os, re, sys

src, home = sys.argv[1], sys.argv[2]
try:
    bt = open(src, encoding='utf-8').read()
except OSError:
    print("  ⚠️  build-threads.sh illisible — ce contrôle est MUET", file=sys.stderr); raise SystemExit

# Le motif du générateur n'est pas RE-DÉRIVÉ mais ÉVALUÉ tel quel : on extrait l'expression
# `FILS = re.compile(...)` de build-threads.sh et on l'exécute. Une première version ne reprenait
# que la liste des titres, et elle a sur-signalé dès le premier élargissement du générateur —
# la divergence que ce contrôle existe pour empêcher, reproduite dans le contrôle lui-même.
m = re.search(r"^FILS = (re\.compile\(.*?\))\n(?=\S|\n)", bt, re.M | re.S)
if not m:
    print("  ⚠️  expression FILS introuvable dans build-threads.sh — ce contrôle est MUET, "
          "la forme de l'affectation a changé et il faut le rebrancher", file=sys.stderr)
    raise SystemExit
try:
    reconnus = eval(m.group(1), {'re': re})
except Exception as e:
    print(f"  ⚠️  expression FILS non évaluable ({e}) — ce contrôle est MUET", file=sys.stderr)
    raise SystemExit
# Plus large que le générateur, exprès (voir asymétrie ci-dessus).
suspect = re.compile(r'^#{1,4} +.*?(fils? ouverts?|reste à faire|à faire|points? ouverts?'
                     r'|à trancher|à décider|non tranché|en attente|à confirmer)', re.I)

fichiers = [f'{home}/.claude/HANDOFF.md']
for pat in ('HANDOFF.md', '*/HANDOFF.md', '*/*/HANDOFF.md', '*/*/*/HANDOFF.md'):
    fichiers += glob.glob(f'{home}/workstations/{pat}')

ko = []
for f in sorted(set(fichiers)):
    if '.sync-backups' in f:
        continue
    try:
        txt = open(f, encoding='utf-8').read()
    except OSError:
        continue
    for ligne in txt.splitlines():
        if suspect.match(ligne) and not reconnus.match(ligne):
            ko.append(f"{os.path.relpath(f, home)}  →  {ligne.strip()[:88]}")

if ko:
    print(f"  ⚠️  {len(ko)} section(s) de reprise à l'allure « fils ouverts » qu'aucun titre "
          f"reconnu ne ratisse — leurs fils ne remontent dans aucune vue :", file=sys.stderr)
    for k in ko:
        print(f"       {k}", file=sys.stderr)
    print("       Corriger en renommant le titre en « Fils ouverts » ou « Reste à faire », "
          "ou en élargissant le motif de build-threads.sh si le titre est légitime.", file=sys.stderr)
else:
    print(f"  ✅ toutes les sections de fils ouverts des reprises sont ratissées "
          f"({len(fichiers)} reprise(s) balayée(s))")
PY

echo
if [ "$FAIL" -eq 0 ]; then
    echo "[selftest] ✅ Plomberie OK."
else
    echo "[selftest] ❌ Plomberie en défaut — voir ci-dessus." >&2
fi
exit "$FAIL"
