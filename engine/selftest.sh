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
# warn : signale sans faire échouer. Pour ce qui doit être vu mais ne doit PAS bloquer la
# sauvegarde (un manque de contenu ne doit jamais empêcher d'enregistrer le travail).
warn() { echo "  ⚠️  $1" >&2; }

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

echo "[selftest] 4. boot-check.sh → JSON valide"
if bash "$SELF/boot-check.sh" 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "hookSpecificOutput" in d' 2>/dev/null; then
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
        warn "machine-todo (cible=$c_b auteur=$c_a après-done=$c_b2 coché=$checked après-purge=$after fail-loud=$_floud)"
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
# `fiches/CONTROLES_ET_ALARMES.md` : il RÉIMPLÉMENTAIT le routage en dur dans le test
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
# de `flock`, une primitive du noyau : elle ne peut pas varier, et le contrôle 2 dit déjà si
# l'outil est présent. Elle coûtait à elle seule plus de deux secondes à chaque passage.
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
# `fiches/CONTROLES_ET_ALARMES.md` : tester une reproduction valide la reproduction, pas la garde
# en place — la vraie logique vit dans `synclib.sh` et un écart entre les deux passait inaperçu.
# CE QUI RESTE : la logique est bien dans la bibliothèque, et `sync.sh` l'appelle.
_m16=0
grep -q 'absent du repo → retiré du live' "$SELF/synclib.sh" || _m16=1
grep -q 'claudeos_mem_restore' "$SELF/sync.sh" || _m16=1
[ "$_m16" = 0 ] && ok "propagation des suppressions câblée (synclib + sync.sh)" || ko "propagation suppression mémoire (#16)"

echo "[selftest] 16. Visibilité des suppressions miroir — câblage (#9)"
# MOITIÉ RETIRÉE le 2026-08-05 : elle vérifiait qu'un essai à blanc de `rsync` liste un fichier
# voué à suppression, en réimplémentant à côté le filtre qui écarte les dossiers. Sémantique de
# l'outil plus reproduction de notre filtre — aucun des deux n'est un comportement de ce système.
# CE QUI RESTE : `sync.sh` annonce-t-il les suppressions en miroir. Un oubli là se voit.
_n9=0
grep -q 'suppression(s) en miroir' "$SELF/sync.sh" || _n9=1
[ "$_n9" = 0 ] && ok "annonce des suppressions en miroir câblée dans sync.sh" || ko "visibilité suppressions miroir (#9)"

echo "[selftest] 17. Alarme binaires (#6)"
# numstat marque un binaire '-\t-\t<path>' : détecté ; le texte ne l'est pas ; câblé dans backup.sh.
_gb=$(mktemp -d); git -C "$_gb" init -q 2>/dev/null
printf 'PK\000\001\002binaire\000avec\000nuls\000' > "$_gb/blob.bin"; printf 'texte\n' > "$_gb/t.md"
git -C "$_gb" add -A 2>/dev/null; _b6=0
_nb=$(git -C "$_gb" diff --cached --numstat --diff-filter=A 2>/dev/null | awk -F'\t' '$1=="-" && $2=="-" {print $3}')
printf '%s\n' "$_nb" | grep -q '^blob.bin$' || _b6=1
printf '%s\n' "$_nb" | grep -q '^t.md$' && _b6=1
grep -q 'ALARME BINAIRE' "$SELF/backup.sh" || _b6=1
grep -q 'FORCE_BINARY' "$SELF/backup.sh" || _b6=1
[ "$_b6" = 0 ] && ok "binaire détecté, texte ignoré, alarme câblée dans backup.sh" || ko "alarme binaires (#6)"
rm -rf "$_gb"

echo "[selftest] 18. Politique secrets — câblage (#4 FORCE dégroupé, whitelist, scan boot)"
_s2=0
for v in FORCE_FRESH FORCE_SELFTEST FORCE_SECRET FORCE_BINARY; do grep -q "$v" "$SELF/backup.sh" || _s2=1; done
grep -q 'system/secrets-shared' "$SELF/backup.sh" || _s2=1
grep -q 'SECURITY_DEBT' "$SELF/boot-check.sh" || _s2=1
[ -d "$HOME/.claude/secrets-shared" ] || _s2=1
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
[ "$_s2" = 0 ] && ok "FORCE dégroupé + whitelist + scan boot + dossier + secrets-shared + alarme nom (#8) + alarme donnée (#9)" || ko "câblage politique secrets"

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
[ "$_w4b" = 0 ] && ok "awk + clean-ads (périmètre dérivé du manifeste) + sonde taille câblés" || warn "Wave 4 boot/hooks (#8/#23/#25)"

echo "[selftest] 21. Couche règlement — alarme de dérive du poids et démarrage"
# Pas de plafond par fichier : c'est le critère d'admission du racine qui arbitre une règle,
# pas un quota au caractère près (un quota trop serré fait rogner de la prose utile pour
# faire entrer une règle légitime). Ce qu'on garde, c'est une ALARME DE DÉRIVE sur le poids
# total payé à chaque session, avec de la marge : elle attrape une réaccumulation silencieuse,
# elle n'arbitre aucune règle. Relever ces seuils est une décision, pas un contournement.
_r=0
_CMD="$HOME/.claude/CLAUDE.md"
_LAYER_MAX=24000   # règlement + RTK + index mémoire
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
# (fiches/CONTROLES_ET_ALARMES.md). 44 000 laisse environ neuf pour cent de marge sur les 40 261
# mesurés le 2026-08-05, soit plusieurs semaines d'écriture de règles avant qu'elle parle.
# Ce n'est pas un contournement du dépassement de 261 caractères constaté ce jour-là : c'est la
# conséquence du changement de nature, et elle est écrite ici pour cette raison.
_SHEETS_GROWTH_MAX=44000  # croissance du corpus des fiches — PAS un coût par session
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
_boot=$(bash "$SELF/boot-check.sh" 2>/dev/null | python3 -c '
import json, sys, re
t = json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]
t = re.sub(r"--- ALERTES ---.*?(?=--- )", "", t, flags=re.S)
print(len(t))
' 2>/dev/null || echo 999999)
_boot_brut=$(bash "$SELF/boot-check.sh" 2>/dev/null | python3 -c 'import json,sys;print(len(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]))' 2>/dev/null || echo 999999)
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
_sheets=$(python3 -c '
import sys, glob
print(sum(len(open(p, encoding="utf-8").read()) for p in sorted(glob.glob(sys.argv[1]))))
' "$HOME/.claude/fiches/*.md" 2>/dev/null || echo 999999)
_session=$(( _layer + _sheets ))
[ "$_boot" -gt "$_BOOT_MAX" ] && { warn "bilan de démarrage hors alertes : $_boot car. > $_BOOT_MAX (le journal complet y est-il reparti ?)"; _r=1; }
[ "$_layer" -gt "$_LAYER_MAX" ] && { warn "couche toujours-chargée (règlement + RTK + index mémoire) : $_layer car. > $_LAYER_MAX — dérive : vérifier ce qui s'y est réaccumulé"; _r=1; }
# SEUIL RETIRÉ le 2026-08-05, sur décision de l'utilisateur. La taille du corpus des fiches
# reste MESURÉE et AFFICHÉE plus bas, elle ne déclenche plus rien. Motif : depuis que les fiches
# ne sont plus chargées au démarrage (2026-08-03), cette grandeur ne facture plus de contexte,
# et le rôle qu'on lui avait assigné — détecter le retour du préchargement — est impossible pour
# un script, qui ne voit pas le contexte injecté dans une session. Une alarme qu'on recalibre
# pour la faire taire sur une grandeur sans coût est du bruit, et le bruit apprend à ignorer la
# catégorie entière. Ce qui reste vrai et non gardé : l'accumulation de règles sans décision.
# Étiquette corrigée le 2026-08-03 : disait « coût réel par session » pour une somme partielle.
# CONSTAT FAIT, 2026-08-05. Le renommage `rules/` → `fiches/` du 2026-08-03 a produit l'effet
# attendu : vérifié le 2026-08-04 puis le 2026-08-05, sur les deux postes, en cherchant le contenu
# d'une fiche dans le contexte d'une session neuve — absent les deux fois. La somme des deux
# assiettes affichée ci-dessous SURESTIME donc ce qu'une session paie d'environ 40 000 caractères :
# elle reste juste comme total de ce que le système écrit en règles, elle ne mesure plus une facture.
# Ce que ce seuil NE PEUT PAS FAIRE, et qui lui était assigné à tort : détecter le retour du
# préchargement. Un script ne voit pas le contexte injecté dans une session, et la taille du dossier
# est identique que l'outil le charge ou non. Le seul détecteur est une ouverture de session où l'on
# cherche une fiche dans le contexte reçu — geste manuel, à refaire après une mise à jour de l'outil
# ou sur un poste neuf. Rôle résiduel de ce seuil : suivre la croissance du corpus. À trancher
# — il dépasse de 261 caractères au 2026-08-05 sans que ce dépassement coûte rien.
[ "$_r" = 0 ] && ok "racine $_size car. ; PAYÉ PAR SESSION : couche $_layer/$_LAYER_MAX (+ démarrage $_boot/$_BOOT_MAX hors alertes, $_boot_brut brut, + injections de l'outil non mesurées) ; NON payé par session : corpus des fiches $_sheets/$_SHEETS_GROWTH_MAX ; total des règles écrites $_session car."

echo "[selftest] 22. Portabilité — aucun chemin propre à un poste dans les fichiers d'instruction"
_p=0
_slug="$(echo "$HOME" | sed 's#/#-#g')"
# Le nom du dossier de mémoire auto dérive du dossier personnel : il diffère d'un poste
# à l'autre. Écrit en dur dans une instruction, il pointe dans le vide ailleurs.
_h=$( { grep -rl -- "$_slug" "$_CMD" "$HOME/.claude/fiches" "$HOME/.claude/skills" 2>/dev/null; \
        find "$HOME/workstations" \( -name CLAUDE.md -o -name DESIGN.md -o -name DESIGN.md \) -print0 2>/dev/null \
          | xargs -0 grep -l -- "$_slug" 2>/dev/null; } | sort -u)
[ -n "$_h" ] && { ko "slug de poste ('$_slug') en dur : $(echo "$_h" | tr '\n' ' ')"; _p=1; }
# Un slug FAUX passerait le test ci-dessus (il ne cherche que le bon). Motif générique :
# tout '-home-…' / '-Users-…' dans une instruction est un nom de dossier de mémoire figé.
_h3=$(grep -rlE -- 'projects/-(home|Users|c|mnt)[A-Za-z0-9_-]*/' "$_CMD" "$HOME/.claude/fiches" "$HOME/.claude/skills" 2>/dev/null | sort -u)
[ -n "$_h3" ] && { ko "nom de dossier de mémoire figé (résoudre le slug, ne pas l'écrire) : $(echo "$_h3" | tr '\n' ' ')"; _p=1; }
# Chemins absolus dans les fichiers du système lui-même (périmètre où l'on est prescriptif).
_h2=$(grep -rlE -- '/home/[a-z_][a-z0-9_-]*/|/Users/[A-Za-z]' "$_CMD" "$HOME/.claude/fiches" "$HOME/.claude/DESIGN.md" 2>/dev/null | sort -u)
[ -n "$_h2" ] && { ko "chemin absolu en dur dans le règlement ou ses fiches : $(echo "$_h2" | tr '\n' ' ')"; _p=1; }
[ "$_p" = 0 ] && ok "règlement, fiches et instructions de workstation sans chemin propre à un poste"

echo "[selftest] 23. Routage — fiches de règles et registre des ratés"
_rt=0
for _f in "$HOME/.claude/fiches"/*.md; do
    [ -e "$_f" ] || continue
    grep -q "$(basename "$_f")" "$_CMD" || { ko "fiche non routée depuis le racine : $(basename "$_f")"; _rt=1; }
done
while read -r _n; do
    [ -z "$_n" ] && continue
    [ -f "$HOME/.claude/fiches/$_n" ] || { ko "fiche citée mais absente : fiches/$_n"; _rt=1; }
done < <(grep -oE 'fiches/[A-Z_]+\.md' "$_CMD" 2>/dev/null | sed 's|fiches/||' | sort -u)
[ -f "$MEM/ROUTING_MISSES.md" ] || { ko "registre des ratés de routage absent ($MEM/ROUTING_MISSES.md)"; _rt=1; }
grep -q 'ROUTING_MISSES' "$HOME/.claude/skills/os-audit/SKILL.md" 2>/dev/null \
    || { ko "l'audit ne lit pas le registre des ratés — la boucle de correction est morte"; _rt=1; }
[ "$_rt" = 0 ] && ok "fiches routées dans les deux sens + registre des ratés lu par l'audit"

echo "[selftest] 24. Durabilité — chemin de sauvegarde mort, plafond du journal, copies de sync"
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
# avec son unité et son motif (règle « un fait calculable ne s'écrit pas », fiches/MEMOIRE).
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
# `~/.claude/fiches/CONTROLES_ET_ALARMES.md` : un défaut de contenu avertit, une corruption de
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
    _claim=$(grep -oiE '\b[0-9]+ (contrôles|tests|fiches|workstations)\b' "$_f" 2>/dev/null | head -3)
    # Les nombres ÉCRITS EN MOTS sont ambigus : « les trois contrôles qui gardent cette zone »
    # désigne un sous-ensemble, pas un total, et le flaguer produirait un faux positif — qu'on
    # apprendrait à ignorer, avec les vrais. On ne les retient donc que pour le seul cas où le
    # total est certain : un compte de fiches sur la même ligne que le dossier qui les contient.
    # C'est la forme exacte des quatre occurrences de « six fiches » trouvées le 2026-07-27.
    # Borne de proximité en NOMBRE DE CARACTÈRES, pas « jusqu'au prochain point » : le chemin
    # du dossier contient lui-même des points (`~/.claude/fiches/`), si bien qu'un motif borné
    # par `[^.]*` ne l'atteignait jamais et le contrôle restait muet sur le cas exact qu'il
    # visait — constaté à l'exercice de son cas positif.
    _claim="$_claim$(grep -oiE '\b(deux|trois|quatre|cinq|six|sept|huit|neuf|dix|onze|douze) fiches\b.{0,60}fiches/' "$_f" 2>/dev/null | head -2)"
    [ -n "$_claim" ] && { warn "inventaire écrit en dur dans $(basename "$_f") ($(echo "$_claim" | tr '\n' ' ')) — il se compte à sa source ; retirer le nombre, ne pas le mettre à jour"; _doc=1; }
done <<EOF
$HOME/.claudeos/README.md
$HOME/.claude/DESIGN.md
$MEM/INDEX.md
EOF
grep -qE '250 lignes' "$HOME/.claude/DESIGN.md" 2>/dev/null \
    && { warn "DESIGN.md déclare encore un plafond en lignes pour le racine — le racine n'a plus de plafond chiffré"; _doc=1; }

# L'ancienne branche « DESIGN.md mentionne-t-il fiches/ ? » était VERTE PAR CONSTRUCTION : la
# chaîne y figure des dizaines de fois, donc le contrôle ne pouvait rien détecter et affichait
# pourtant « DESIGN.md à jour sur la couche des fiches ». C'est pire qu'un contrôle absent : il
# délivrait une assurance fausse. Remplacée le 2026-07-27 par trois vérifications qui peuvent
# échouer — et c'est ce trou qui a laissé l'inventaire des fiches incomplet et deux de ses
# déclencheurs divergents jusqu'à ce qu'un audit les trouve à la main.
_D="$HOME/.claude/DESIGN.md"
# (a) Complétude : toute fiche du dossier est-elle nommée dans DESIGN.md ?
_miss=$(for _f in "$HOME"/.claude/fiches/*.md; do
    [ -f "$_f" ] || continue
    grep -q "\`$(basename "$_f")\`" "$_D" 2>/dev/null || basename "$_f"
done)
[ -n "$_miss" ] && { warn "fiche absente de l'inventaire de DESIGN.md : $(echo "$_miss" | tr '\n' ' ')— la référence de design ignore une couche qui existe"; _doc=1; }
# (b) Sens inverse : une ligne de l'inventaire pointe-t-elle un fichier disparu ?
# Le nombre de colonnes est le discriminant : l'inventaire des fiches en a DEUX depuis le retrait
# de la colonne des déclencheurs, tandis que la table des types de fichiers du même document en a
# quatre et cite `CLAUDE.md`, `MEMORY.md`, `DESIGN.md`… Sans cette borne, le contrôle réclamait
# ces six-là dans le dossier des fiches — faux positif constaté à son premier passage.
_ghost=$(grep -oE '^\| `[A-Z_]+\.md` \| [^|]+ \|$' "$_D" 2>/dev/null | sed -E 's/^\| `([A-Z_]+\.md)`.*/\1/' | while read -r _n; do
    [ -f "$HOME/.claude/fiches/$_n" ] || echo "$_n"
done)
[ -n "$_ghost" ] && { warn "l'inventaire des fiches de DESIGN.md cite un fichier absent de ~/.claude/fiches/ : $(echo "$_ghost" | tr '\n' ' ')"; _doc=1; }
# (c) Anti-régression : la colonne des déclencheurs, retirée le 2026-07-27 parce qu'elle
#     recopiait le racine et avait dérivé, ne doit pas revenir sous une autre forme.
_dup=$(python3 - "$HOME/.claude/CLAUDE.md" "$_D" <<'PY' 2>/dev/null
import re, sys
root = open(sys.argv[1], encoding="utf-8").read()
design = open(sys.argv[2], encoding="utf-8").read()
trig = [m.group(1).strip() for m in
        re.finditer(r'^\|\s*([^|]+?)\s*\|\s*`fiches/[A-Z_]+\.md`', root, re.M)]
print(" · ".join(t for t in trig if len(t) > 20 and t in design))
PY
)
[ -n "$_dup" ] && { warn "déclencheur de fiche recopié dans DESIGN.md ($_dup) — les déclencheurs vivent dans CLAUDE.md §3.3, seule source du routage"; _doc=1; }
[ "$_doc" = 0 ] && ok "aucun inventaire en dur, fiches de DESIGN.md complètes dans les deux sens, aucun déclencheur recopié"

echo "[selftest] 26. Amorçage — le gabarit crée-t-il dans l'arbre sauvegardé ?"
_tpl="$HOME/resources/WORKSTATION_TEMPLATE.md"
if [ ! -f "$_tpl" ]; then ko "gabarit de création de workstation absent ($_tpl)"
elif grep -qE '`~/<Nom' "$_tpl"; then
    ko "le gabarit crée hors de ~/workstations/ — la workstation naîtrait hors du filet, sans que rien n'échoue"
else ok "toutes les destinations du gabarit sont sous ~/workstations/"; fi

echo "[selftest] 27. Chemins morts dans les fichiers d'instruction"
# selftest 7 couvre les références entre scripts ; ici ce sont les chemins cités par les
# RÈGLES et les procédures. C'est ce qui aurait attrapé d'un coup les procédures mortes du 25/07.
_dead=$(python3 - <<'PYEOF' 2>/dev/null
import re, os, glob
H = os.path.expanduser('~')
files = [f'{H}/.claude/CLAUDE.md'] + glob.glob(f'{H}/.claude/fiches/*.md') \
      + glob.glob(f'{H}/workstations/*/CLAUDE.md') + glob.glob(f'{H}/workstations/*/*/CLAUDE.md') \
      + glob.glob(f'{H}/resources/*.md')
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
    ko "chemin cité par une règle mais absent du disque :"; echo "$_dead" | sed 's/^/       /' >&2
else ok "tous les chemins cités par les règles et les procédures existent"; fi

echo "[selftest] 28. Réceptacle des documents client à la racine de chaque projet"
# Décision du 2026-07-25 : le réceptacle vit au niveau PROJET seulement
# (`workstations/<DOMAINE>/<PROJET>`), pas au niveau application. On n'en attend donc
# aucun plus profond, et on n'en réclame pas un aux apps ni aux sous-dossiers.
_noign=$(find "$HOME/workstations" -mindepth 2 -maxdepth 2 -type d \
    -not -name "_IGNORE" \
    2>/dev/null | while read -r d; do [ -d "$d/_IGNORE" ] || echo "${d#$HOME/}"; done)
if [ -n "$_noign" ]; then
    ko "projet sans réceptacle \`_IGNORE/\` à sa racine (le premier document client y atterrirait en zone sauvegardée) :"
    echo "$_noign" | sed 's/^/       /' >&2
else ok "tous les projets ont leur réceptacle à leur racine"; fi

echo "[selftest] 29. Plafonds auto-déclarés des mémoires (avertissement, ne bloque pas)"
# L'UNITÉ se lit, elle ne se suppose pas (corrigé le 2026-07-27). Deux mémoires déclaraient
# « Plafond : 300 mots » ; le contrôle ne lisait que le nombre et le comparait à un nombre de
# LIGNES, si bien qu'un plafond de 300 mots devenait un plafond de 300 lignes — jamais atteint,
# donc ces deux mémoires n'étaient pas surveillées du tout. Une unité ignorée ne produit pas une
# erreur, elle produit un contrôle muet, ce qui est pire.
_over=$(for _m in $(find "$HOME/workstations" -name MEMORY.md 2>/dev/null); do
    # Trois unités reconnues : caractères, mots, lignes. « caractères » est ajoutée le 2026-08-05,
    # jour où l'unité de tous les plafonds de mémoire est passée aux caractères — et le motif est
    # celui-là même que cette section documente déjà : une unité non reconnue ne produit pas une
    # erreur, elle produit un contrôle muet ou un faux positif. Ici c'était un faux positif :
    # « Plafond : 4 000 caractères » était lu « 4 », comparé à un nombre de lignes, et une mémoire
    # de 2 Ko était déclarée en dépassement. Le séparateur de milliers est retiré avant lecture,
    # sans quoi 4 000 devient 4.
    _decl=$(grep -m1 -oE 'Plafond : [0-9][0-9  ]* *(caractères|caracteres|mots|lignes)?' "$_m" 2>/dev/null)
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
if [ -n "$_over" ]; then warn "mémoires à compresser ou à doter d'un plafond :"; echo "$_over" | sed 's/^/       /' >&2
else ok "plafonds des mémoires de domaine respectés et déclarés"; fi

echo "[selftest] 30. Rappel échu : le démarrage le sort-il vraiment ?"
# Motif (2026-07-26) : le bloc de rappels est resté MUET de sa création au 2026-07-26.
# `REMINDERS.md` n'avait pas de retour à la ligne final et `while IFS= read -r` abandonne
# alors sa dernière ligne — qui est, par construction, le rappel le plus récent, donc le
# seul actif. La vérification d'origine (2026-07-03) ne testait que le cas NÉGATIF — un
# rappel à échéance future n'est pas affiché — jamais le cas positif. Ce contrôle teste le
# cas positif, seul capable d'attraper la classe entière (cf. le document de conception).
_r=0
# (a) Anti-régression : la garde de dernière ligne est-elle toujours dans la boucle ?
grep -qF 'read -r rline || [ -n "$rline" ]' "$SELF/boot-check.sh" \
    || { ko "garde de dernière ligne absente de la boucle des rappels (boot-check.sh) — un fichier sans retour à la ligne final reperdrait son rappel le plus récent"; _r=1; }
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
    _seen=$(bash "$SELF/boot-check.sh" 2>/dev/null | python3 -c '
import json, sys
t = json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]
print(t.count("⏰"))
' 2>/dev/null || echo 0)
    [ "${_seen:-0}" -eq 0 ] && { ko "$_due rappel(s) échu(s) dans REMINDERS.md mais AUCUN dans le bilan de démarrage — le bloc est muet"; _r=1; }
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
# ne se recopie pas, il se lit à sa source (`fiches/MEMOIRE_ET_VERITE.md`), et les seuils vivent
# dans ce script et nulle part ailleurs.

echo "[selftest] 32. Toute workstation avec une mémoire a une reprise"
# Motif (2026-07-27) : la règle est écrite dans la référence de design et n'était vérifiée
# nulle part — elle a échoué deux fois sur quatre workstations. Avertissement et non échec :
# une workstation neuve n'a rien à reprendre le jour de sa création, et un manque de contenu
# ne doit jamais empêcher d'enregistrer du travail (cf. commentaire de `warn`). Portée : le
# premier niveau seulement — un projet ou une app n'est pas concerné.
_nohand=$(for _m in "$HOME"/workstations/*/MEMORY.md; do
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
# La tolérance est DÉCLARÉE dans la mémoire de l'app, jamais codée ici — une exception écrite
# dans le script serait invisible à qui ouvre l'app, et deviendrait fausse sans qu'on le voie.
# Marqueurs admis, en tête de la mémoire : « EN SOMMEIL », « EN CONCEPTION », « EN OUVERTURE ».
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
done < <(find "$HOME/workstations" -name 'CLAUDE.md' -type f 2>/dev/null | sort)

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
_i=0
bash "$SELF/impact.sh" --since "zzz-pas-une-date" >/dev/null 2>&1 \
    && { ko "un argument inexploitable est accepté — la sortie vide serait lue comme « rien à signaler »"; _i=1; }
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
        ko "une date est refusée — la passe hebdomadaire ne peut plus appeler la retombée documentaire"; _i=1
    fi
fi
# La garde qui rendait le défaut muet ne doit pas revenir : le diff par référence
# ne s'exécute plus derrière une redirection d'erreur.
grep -q 'diff --name-only "$SINCE" 2>/dev/null' "$SELF/impact.sh" 2>/dev/null \
    && { ko "la redirection d'erreur est revenue sur le diff par référence — l'échec redeviendrait silencieux"; _i=1; }
[ "$_i" -eq 0 ] && ok "argument absurde refusé (code 2), date acceptée et résolue, redirection d'erreur absente"

echo "[selftest] 36. Secret hors de son emplacement autorisé, y compris en zone non sauvegardée (avertissement)"
# Classe de défaut que rien ne gardait, constatée le 2026-08-03 : une valeur de secret vivait
# dans un dossier de compétence. Les alarmes de `backup.sh` (#8, contenu et nom) ne pouvaient
# pas la voir — elles inspectent ce qui est MIS EN FILE pour le dépôt, et la liste blanche
# refusait ce fichier. Un secret mal rangé dans une zone que la sauvegarde ignore est donc
# parfaitement invisible pour elles. Ce n'est pas une fuite, c'est un rangement : rien n'est
# parti, rien n'est désactivé, et ça se corrige quand on le voit. Donc AVERTIT et ne bloque
# pas, par le partage de `fiches/CONTROLES_ET_ALARMES.md` — bloquer ici ferait payer un défaut
# de rangement par l'impossibilité de sauvegarder, la faute que ce partage existe pour éviter.
#
# Motifs : ceux de config.sh, partagés avec backup.sh — jamais recopiés (règle « un seuil
# défini dans un script ne se recopie pas ailleurs »).
#
# Emplacements AUTORISÉS, donc exclus du scan — les deux régimes de `fiches/SECRETS_DETAIL.md` :
#   ~/.claude/secrets-shared/  → faible valeur, synchronisé, seul emplacement autorisé pour
#                                une valeur dans l'arbre sauvegardé.
#   */_IGNORE/*                → haute valeur, local-only strict, hors sauvegarde.
# Exclus aussi : ce que l'outil gère seul (transcriptions, caches, historique, identifiants)
# et le dossier de plugins — ni authorés ni sous notre contrôle, et bruyants par nature.
_r=0
_sec_hits=$(
    for _root in "$HOME/.claude" "$HOME/workstations" "$HOME/resources" "$HOME/docs"; do
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
        case "$(file -b --mime-type "$_f" 2>/dev/null)" in
            text/*|application/json|inode/x-empty) ;;
            *) continue ;;
        esac
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

echo "[selftest] 37. Cascade d'instructions — un terme proscrit par un niveau n'est prescrit par aucun niveau sous lui"
# Classe de défaut que rien ne gardait, constatée le 2026-08-03 : deux niveaux de la cascade se
# contredisaient sur le nom d'une propriété d'écran de chargement (`AutoStart`, le niveau app
# disant `Start` qui n'existe pas), et c'est le niveau LOCAL qui prime — donc le faux gagnait.
# Aucun mécanisme ne regardait la cohérence d'une valeur entre deux niveaux.
#
# Ce que le contrôle exploite : quand un niveau tranche un nom, il l'écrit sous une forme
# négative explicite — « jamais `Start` », « aucune propriété `Start` n'existe ». Cette forme
# est la déclaration de l'interdit, donc elle est lisible par une machine. Le contrôle extrait
# les termes ainsi proscrits, puis vérifie qu'aucun document situé SOUS le niveau qui les
# proscrit ne les prescrit dans du code encadré.
#
# Limite à énoncer, elle est réelle : il ne voit que les interdits écrits sous cette forme.
# Un désaccord entre deux niveaux qu'aucun des deux n'a tranché lui échappe. Il réduit la
# surface, il ne certifie pas la cascade — même réserve que la retombée documentaire (#35).
#
# AVERTIT : une contradiction de cascade fait répondre faux, elle ne désactive ni ne détruit
# rien, et elle se corrige dès qu'on la voit.
_r=0
_casc=$(python3 - "$HOME/workstations" <<'PY' 2>/dev/null
import os, re, sys

root = sys.argv[1]
# Documents prescriptifs de la cascade, du plus général au plus local.
NAMES = ("CLAUDE.md", "DESIGN.md", "DESIGN.md")
# « jamais `X` » / « aucune propriété `X` n'existe » / « `X` n'existe pas » / « pas `X` »
BAN = [
    re.compile(r"jamais\s+`([A-Za-z_][A-Za-z0-9_]*)`"),
    re.compile(r"aucune\s+propri[eé]t[eé]\s+`([A-Za-z_][A-Za-z0-9_]*)`\s+n'existe"),
    re.compile(r"`([A-Za-z_][A-Za-z0-9_]*)`\s*,?\s*(?:propri[eé]t[eé]\s+)?qui\s+n'existe\s+pas"),
]

docs = {}
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in ("_IGNORE", "extracted", ".git")]
    for fn in filenames:
        if fn in NAMES:
            p = os.path.join(dirpath, fn)
            try:
                docs[p] = open(p, encoding="utf-8").read()
            except OSError:
                pass

# Un terme proscrit par le document D vaut pour tout document situé dans un sous-dossier de D.
bans = {}          # terme -> chemin du document qui le proscrit
for p, txt in docs.items():
    for rx in BAN:
        for m in rx.finditer(txt):
            bans.setdefault(m.group(1), os.path.dirname(p))

out = []
for term, ban_dir in bans.items():
    # Prescription = le terme apparaît encadré et suivi d'un signe d'affectation ( : ou = ),
    # forme sous laquelle ces documents énoncent une valeur de propriété.
    presc = re.compile(r"`[^`]*\b" + re.escape(term) + r"\b\s*[:=][^`]*`")
    for p, txt in docs.items():
        d = os.path.dirname(p)
        if not (d == ban_dir or d.startswith(ban_dir + os.sep)):
            continue          # hors de la portée du niveau qui proscrit
        if p.startswith(ban_dir) and os.path.dirname(p) == ban_dir:
            pass              # le niveau qui proscrit peut se citer lui-même
        for m in presc.finditer(txt):
            frag = m.group(0)
            # La ligne qui proscrit cite forcément le terme : on écarte les lignes négatives.
            line_start = txt.rfind("\n", 0, m.start()) + 1
            line_end = txt.find("\n", m.end())
            line = txt[line_start:line_end if line_end != -1 else len(txt)]
            if re.search(r"jamais|n'existe|pas\s+`|proscrit|interdit|Corrig", line):
                continue
            out.append("%s prescrit `%s`, proscrit par %s" % (
                os.path.relpath(p, root), term, os.path.relpath(ban_dir, root) or "."))
            break

for line in sorted(set(out))[:10]:
    print(line)
PY
)
if [ -n "$_casc" ]; then
    warn "contradiction(s) de cascade — le niveau local prime, donc c'est le faux qui gagne :"
    echo "$_casc" | sed 's/^/       /' >&2
    _r=1
fi
[ "$_r" = 0 ] && ok "aucun terme proscrit par un niveau n'est prescrit sous lui"

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
    ok "aucun chemin vivant ne tombe entre les deux listes"
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "[selftest] ✅ Plomberie OK."
else
    echo "[selftest] ❌ Plomberie en défaut — voir ci-dessus." >&2
fi
exit "$FAIL"
