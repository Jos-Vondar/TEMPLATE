#!/usr/bin/env bash
# =============================================================================
# BOOT CHECK — ClaudeOS (hook SessionStart)
# LECTURE SEULE (D6) : détecte les écarts, n'agit jamais (pas de pull/install/écriture).
# L'utilisateur décide.
# UN SEUL MODE : émet le JSON `additionalContext` attendu par le hook SessionStart, donc
# injecté dans le contexte du modèle et invisible à l'écran. C'est le MODÈLE qui rend le
# bilan, en première réponse, poussé par la consigne de démarrage du bloc DIRECTIVE plus
# bas — une consigne technique injectée au contexte et qu'on n'affiche pas telle quelle,
# pas une dissimulation. Elle est DÉCLINABLE à l'entretien d'installation (condition
# BILAN_DEMARRAGE, bloc dédié plus bas) ; la dette de sécurité sort dans tous les cas.
#
# LA BANNIÈRE SHELL A ÉTÉ RETIRÉE le 2026-08-09. Un mode `--human` dessinait un bandeau
# coloré dans le terminal ; son unique appelant était le wrapper `claudeos-boot.sh`, qui a cessé de
# l'appeler pour injecter le prompt « tu es à jour ? » à la place — un hook de démarrage ne
# peut qu'ajouter du contexte, il ne peut pas faire parler l'assistant en premier. La branche
# n'avait donc plus d'appelant, et personne ne l'aurait vu : du code mort qui ne casse jamais.
# Ce qui a SURVÉCU au retrait, et qui n'est pas de la bannière : `build_dashboard`, qui
# fabrique le tableau d'état. Il servait les deux modes ; il sert désormais le seul restant.
# =============================================================================
set -uo pipefail

# --- Refus des arguments inconnus ---
# Ce script ne prend AUCUN argument depuis le retrait de la bannière. Un `--human` hérité d'un
# raccourci ou d'une note ancienne serait sinon IGNORÉ EN SILENCE : la personne croirait avoir
# demandé un bandeau, verrait passer du JSON, et conclurait à une panne. Politique du moteur,
# la même que `backup.sh` et `calibrate.sh` — un drapeau inconnu se refuse, il ne se subit pas.
if [ "$#" -gt 0 ]; then
    echo "[boot-check] ERREUR : argument inattendu ('$*'). Ce script ne prend aucun argument." >&2
    echo "[boot-check] Il émet le JSON du déclencheur SessionStart, et rien d'autre. La bannière" >&2
    echo "[boot-check] de terminal a été retirée le 2026-08-09 : le bilan est rendu par le modèle." >&2
    exit 2
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

OUT=""

# Paliers d'ancienneté, en jours : < T_WARN vert · T_WARN..T_CRIT jaune · > T_CRIT rouge.
# REMONTÉS ICI le 2026-08-22, avant leur première utilisation. Ils vivaient au milieu du
# fichier, après deux blocs qui comparaient à un `10` écrit en dur — donc TROIS seuils pour
# une seule grandeur, dont deux invisibles. `set -u` interdit de simplement déplacer l'usage :
# c'est la définition qui monte.
T_WARN=7; T_CRIT=14

# --- Flags de gravité, consommés par le tableau d'état (build_dashboard) ---
BEHIND=0; DIRTY=0; PROP_N=0; DISTILL_DUE=0; SEC_N=0
GIT_OK=1; BACKUP_ERR=0; JDATE=""; JDAYS=-1
IDAYS=-1
CRUISE_D=-1

# --- Écart git des DEUX dépôts (réécrit le 2026-08-22, étape 4.5) ---
# Le système et les documents vivent chacun dans leur dépôt ; il n'y a plus de copie
# rsync ni de « poste en retard » au sens du manifeste. « En retard » veut maintenant
# dire : des commits distants que ce poste n'a pas encore tirés.
BEHIND=0; DIRTY=0
# MULTIPOSTE=non (`reglages/REPONSES`) : un seul poste écrit ces dépôts, la sonde de retard n'a rien
# à trouver et coûte un `fetch` réseau par dépôt à chaque démarrage. Elle se saute, et le tableau le
# dit (plan V3, lot 5, geste 3 ; A6, 2026-10-01). Clé absente : elle tourne, poste non réglé.
_SONDE_RETARD=1
[ "$(claudeos_reponse MULTIPOSTE 2>/dev/null)" = "non" ] && _SONDE_RETARD=0
_ecart() {
    local repo="$1" nom="$2" behind=0 dirty
    [ -d "$repo/.git" ] || return 0
    [ -n "$(git -C "$repo" remote 2>/dev/null)" ] || return 0
    if [ "$_SONDE_RETARD" = 1 ]; then
        # Un `fetch` en échec ne dit rien du retard : hors ligne ou jeton expiré, les références
        # locales sont périmées, et les compter rendrait « à jour » (audit de la v3.0.0).
        if git -C "$repo" fetch --quiet 2>/dev/null; then
            behind=$(git -C "$repo" rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
        else
            OUT="${OUT}⚠️ Dépôt ${nom} : distant injoignable, le retard N'EST PAS mesuré — ne clôture pas d'ici avant d'avoir tiré."$'\n'
        fi
    fi
    dirty=$(git -C "$repo" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    BEHIND=$(( BEHIND + behind )); DIRTY=$(( DIRTY + dirty ))
    [ "$behind" -gt 0 ] && OUT="${OUT}⚠️ Dépôt ${nom} en retard de ${behind} commit(s) — lance: git -C ${repo/#$HOME/$CLAUDEOS_TILDE} pull --rebase"$'\n'
    [ "$dirty" -gt 0 ] && OUT="${OUT}• ${dirty} fichier(s) non commité(s) dans le dépôt ${nom}"$'\n'
    return 0
}
# Un dépôt par client depuis le 2026-09-08 (geste 1.10) : la liste vient de `claudeos_repos`,
# elle n'est plus écrite en dur. Étiquette : « système » pour `~/.claude`, le chemin relatif au
# dossier personnel pour les autres — « ~/<DÉPÔT_A> » aurait nommé un dossier inexistant.
while IFS= read -r _d; do
    [ -n "$_d" ] || continue
    if [ "$_d" = "$HOME/.claude" ]; then _ecart "$_d" "système"
    else _ecart "$_d" "${_d/#$HOME/$CLAUDEOS_TILDE}"; fi
done < <(claudeos_repos)
# Poste en retard = fichiers vivants périmés. Les signaux actionnables composés plus bas
# sont lus sur ces fichiers, donc possiblement déjà traités sur l'autre poste — les marquer
# non fiables SANS les taire. La dette de sécurité n'est pas atténuée : elle sort toujours.
[ "$BEHIND" -gt 0 ] && OUT="${OUT}   ↳ NON synchronisé : les signaux actionnables ci-dessous peuvent déjà être traités ailleurs — à revérifier APRÈS synchro, ne pas exécuter tels quels (la dette de sécurité, elle, vaut dans tous les cas)."$'\n'

# --- Compteur de convergence. LECTURE SEULE. ---
# Croisière = 28 jours consécutifs sans chantier moteur ni chantier de règles. Le compteur
# rend la condition d'arrêt VISIBLE : sans lui, « le système est-il fini ? » ne se pose
# jamais, et l'amélioration indéfinie est ce qui a produit l'usine à gaz du 2026-07-27.
# Périmètre : `engine/` et `CLAUDE.md` du dépôt système. `--invert-grep` écarte les
# réparations : un message commençant par `incident:` ne remet pas le compteur à zéro,
# c'est ce qui distingue un système qui se répare d'un système qu'on refait.
if [ -d "$ROOT/.git" ]; then
    CRUISE_TS=$(git -C "$ROOT" log -1 --format='%ct' --invert-grep --regexp-ignore-case \
        --grep='^incident:' -- engine CLAUDE.md 2>/dev/null)
    if [ -n "${CRUISE_TS:-}" ] && [ "$CRUISE_TS" -gt 0 ] 2>/dev/null; then
        CRUISE_D=$(( ( $(date +%s) - CRUISE_TS ) / 86400 ))
    fi
fi

# --- Flag propositions d'apprentissage (D5) ---
LP="$MEM/LEARNING_PROPOSALS.md"
if [ -f "$LP" ]; then
    # Un titre BARRÉ (`## ~~`) est une proposition déjà traitée, conservée pour que la
    # distillation voie ce qu'elle a produit : elle ne se compte pas. Corrigé le 2026-08-12 —
    # le compteur annonçait 2 en attente là où une seule l'était, l'autre étant barrée depuis
    # le 2026-08-10. Une alarme se construit sur l'état courant, jamais sur la trace d'un état
    # passé : compter un titre barré, c'est retrouver un souvenir. Le motif `awk '/^## /` reste
    # littéral en tête. La contrainte « cherché au caractère près par le contrôle 20 » est TOMBÉE le
    # 2026-08-22 : ce contrôle de câblage est mort avec la copie. Le littéral reste parce qu'il est
    # lisible, pas parce qu'un garde l'exige.
    PROP_N=$(awk '/^## /{ if ($0 !~ /^## *~~/) n++ } END{print n+0}' "$LP" 2>/dev/null || echo 0)   # #8 : toujours numérique, toujours rc 0
    # SIGNAL 🧠 RETIRÉ le 2026-09-08 (geste 2.4) : `LEARNING_PROPOSALS.md` est gelé, ses
    # candidates sont des `du` du journal. `PROP_N` reste calculé, il n'alerte plus.
fi

# --- Dette de sécurité : secrets compromis / à régénérer (jamais de valeur — compétence secrets-detail) ---
SECDEBT="$MEM/SECURITY_DEBT.md"
if [ -f "$SECDEBT" ]; then
    SEC_N=$(awk '/^## /{n++} END{print n+0}' "$SECDEBT" 2>/dev/null || echo 0)   # #8 : awk robuste
    [ "$SEC_N" -gt 0 ] && OUT="${OUT}🔐 ${SEC_N} secret(s) compromis / à régénérer en attente ($SECDEBT)"$'\n'
fi

# --- Rappels datés (échéances déclenchées à date — REMINDERS.md) ---
# Lignes actives : "- YYYY-MM-DD | texte". Surfacée quand la date d'échéance est atteinte
# (aujourd'hui ou passée). LECTURE SEULE : l'assistant purge la ligne une fois traitée.
#
# Plus de paliers d'ancienneté (supprimés le 2026-07-27, avec le compteur de reports et
# le plafond à trois). Ils graduaient l'affichage d'un rappel que personne ne traitait,
# ce qui ajoutait de la mécanique sans changer l'issue. Le retard est simplement dit en
# clair, et c'est la CONDUITE qui traite le rappel : l'assistant pose une question par
# rappel échu en début de séance, avant de dérouler la demande (compétence `session`).
REMINDERS="$MEM/REMINDERS.md"
REMINDER_N=0
if [ -f "$REMINDERS" ]; then
    NOW_TS=$(date +%s)
    # `|| [ -n "$rline" ]` : sans lui, un fichier sans retour à la ligne final perd sa
    # DERNIÈRE ligne — donc le rappel le plus récemment ajouté. Cause du silence du bloc
    # entre sa création et le 2026-07-26 : le seul rappel actif était la dernière ligne.
    while IFS= read -r rline || [ -n "$rline" ]; do
        rdate=$(printf '%s' "$rline" | grep -oE '^- [0-9]{4}-[0-9]{2}-[0-9]{2}' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
        [ -z "$rdate" ] && continue
        # PORTABILITÉ 2026-09-12 : voir claudeos_epoch_of_date dans config.sh. Un échec de
        # conversion se DIT désormais, au lieu de rendre 0 et d'escamoter le rappel en silence.
        rts=$(claudeos_epoch_of_date "$rdate" || true)
        if [ -z "$rts" ]; then
            OUT="${OUT}⚠️ Rappel du ${rdate} NON ÉVALUÉ — date illisible par \`date -d\` comme par python3. Le rappel existe et n'est PAS affiché ci-dessus."$'\n'
            continue
        fi
        if [ "$rts" -gt 0 ] && [ "$rts" -le "$NOW_TS" ]; then
            rtext=$(printf '%s' "$rline" | sed -E 's/^- [0-9]{4}-[0-9]{2}-[0-9]{2} *\| *//')
            rlate=$(( (NOW_TS - rts) / 86400 ))
            REMINDER_N=$((REMINDER_N + 1))
            OUT="${OUT}⏰ Rappel du ${rdate}"
            [ "$rlate" -gt 0 ] && OUT="${OUT} (en retard de ${rlate} j)"
            OUT="${OUT} — ${rtext}"$'\n'
        fi
    done < "$REMINDERS"
    if [ "$REMINDER_N" -gt 0 ]; then
        OUT="${OUT}      ↳ ${REMINDER_N} rappel(s) : poser UNE question par rappel en début de séance (tenir · replanifier · abandonner), avant de dérouler la demande."$'\n'
    fi
fi

# --- LE RITUEL DE DISTILLATION EST MORT le 2026-09-08, geste 2.4 (décision D-E du plan).
# Ce qu'il y avait ici : un bloc 🧪 qui lisait `memory/.last_distillation` et réclamait une
# distillation passé sept jours. Il sort avec son marqueur, et le marqueur est SUPPRIMÉ.
# LE MOTIF, et il n'est pas la simplification : la distillation existait pour faire remonter
# ce que les fichiers d'état laissaient tomber. Avec un journal append-only il n'y a plus rien
# à faire remonter — une candidate est un `du` ouvert du niveau, visible dans « Ce qui reste »
# jusqu'à ce qu'on la tranche. Un rappel périodique pour relire un fichier qui ne perd plus
# rien est un rituel qui coûte sans rendre.
# `DISTILL_DUE` reste initialisé à 0 en tête de ce script : le tableau d'état le lisait.

# --- Audit du système dû ? (cadence mensuelle, lecture seule) ---
# La plomberie est testée à chaque sauvegarde ; le CONTENU (la carte dit-elle encore vrai ?)
# n'est vérifié que par l'audit, qui n'a pas de déclencheur propre. Sans rappel, il ne
# tourne qu'à la demande — donc jamais.
# Deux niveaux depuis le 2026-07-25 : un contrôle de contenu LÉGER greffé sur la distillation
# hebdomadaire (avertissements du filet, trois sondages dans la carte, registre des ratés,
# fils reconduits — voir la compétence `session`), et cet audit COMPLET en éventail, cher, dont le
# Depuis le 2026-07-27 l'audit est HEBDOMADAIRE : il a reçu tout ce qui a quitté la
# clôture (hygiène, distillation, ratés de routage, contrôles de documents), donc son seuil
# passe de 90 à 7 jours.
AUDIT_DIR="$HOME/.claude/audits"
# LA DATE SEULE, JAMAIS LE SUFFIXE DE POSTE — corrigé le 2026-09-22. Un rapport peut s'appeler
# `os-audit-2026-09-17-mac.md` ; l'ancien découpage rendait `2026-09-17-mac`, que le tri plaçait
# EN DERNIER et qu'aucune conversion de date ne sait lire. `AUDIT_DAYS` tombait donc à -1 et le
# démarrage annonçait « ancienneté NON MESURÉE » — l'alarme d'audit était aveugle depuis le
# 2026-09-17, et elle l'aurait été de nouveau au prochain audit nommé de la même façon.
# Ce `sed` ne retient que les dix caractères de la date ISO et IGNORE une ligne qui n'en porte
# pas : mieux vaut ne pas voir un rapport mal nommé que rendre une ancienneté fausse.
AUDIT_LAST=$(ls -1 "$AUDIT_DIR"/os-audit-*.md 2>/dev/null \
    | sed -nE 's/.*os-audit-([0-9]{4}-[0-9]{2}-[0-9]{2}).*\.md$/\1/p' | sort | tail -1)
if [ -z "$AUDIT_LAST" ]; then
    OUT="${OUT}🔍 Audit du système jamais lancé — « os audit » pour vérifier que la carte dit encore vrai."$'\n'
else
    # PORTABILITÉ 2026-09-12 : idem. L'ancien repli `|| date +%s` rendait 0 jour, donc l'audit
    # n'était JAMAIS signalé dû sur un poste sans `date -d`.
    _audit_ts=$(claudeos_epoch_of_date "$AUDIT_LAST" || true)
    if [ -z "$_audit_ts" ]; then
        AUDIT_DAYS=-1
        OUT="${OUT}⚠️ Ancienneté de l'audit NON MESURÉE — date « ${AUDIT_LAST} » illisible. Ne pas lire l'absence d'alerte d'audit comme un audit récent."$'\n'
    else
        AUDIT_DAYS=$(( ( $(date +%s) - _audit_ts ) / 86400 ))
    fi
    # SEUIL PORTÉ DE 7 À 30 JOURS le 2026-09-08, décision D-K du plan. Motif : à sept jours le
    # rappel était dû presque en permanence, donc il ne signalait plus rien — un rappel toujours
    # allumé est un rappel éteint. Le message dit l'ANCIENNETÉ dans son unité, pas « en retard ».
    if [ "$AUDIT_DAYS" -gt 30 ]; then
        OUT="${OUT}🔍 Audit du système non lancé depuis ${AUDIT_DAYS} j (dernier : ${AUDIT_LAST}) — « os audit »."$'\n'
    fi
fi

# --- Auto-diagnostic de la plomberie (« fail loud ») ---
# Le second brain doit signaler quand SA PROPRE machinerie casse, plutôt que d'échouer en
# silence. RÉÉCRIT le 2026-08-22 (étape 4.5) : la copie rsync est morte, et avec elle le
# journal de sauvegarde, le verrou de sync incomplet, la dérive dépôt↔live et le rapport
# des fichiers refusés par la liste blanche. Ce que ces sondes disaient se lit maintenant
# directement dans git, qui est la source et non une trace laissée par un script.

# Dépendance dure : git. Sans lui, tout ce qui précède est muet. EN RÉGIME GITHUB SEULEMENT : sans
# git (`GIT=aucun`), son absence est le choix de l'installateur, pas une panne à signaler.
if [ "$(claudeos_regime)" != aucun ] && ! command -v git >/dev/null 2>&1; then
    GIT_OK=0
    OUT="${OUT}⚠️ git introuvable — la sauvegarde et la détection d'écart sont désactivées"$'\n'
fi

# Verdict de sauvegarde = l'état réel des deux dépôts, pas le récit d'un journal.
# Trois choses peuvent clocher, et chacune se mesure : des commits jamais poussés, un
# arbre sale, un dépôt sans nouveau commit depuis longtemps (la clôture ne tourne plus).
_verdict_depot() {
    local repo="$1" nom="$2" ahead age ts
    [ -d "$repo/.git" ] || return 0
    # En suspens, le compte ci-dessous échoue et rendait 0 : rien n'était dit d'un dépôt qui ne
    # pousse plus rien (audit de la v3.0.0).
    if claudeos_en_suspens "$repo"; then
        BACKUP_ERR=1
        OUT="${OUT}⛔ Dépôt ${nom} : un rebase ou une fusion est en cours, ou HEAD est détachée — rien de ce poste n'est poussé. git -C ${repo/#$HOME/$CLAUDEOS_TILDE} status, puis termine-le ou annule-le."$'\n'
    fi
    ahead="$(git -C "$repo" rev-list --count @{u}..HEAD 2>/dev/null || echo 0)"
    if [ "${ahead:-0}" -gt 0 ]; then
        BACKUP_ERR=1
        OUT="${OUT}⚠️ Dépôt ${nom} : ${ahead} commit(s) JAMAIS POUSSÉ(S) — ils n'existent que sur ce poste. Relance la clôture : bash ~/.claude/engine/claudeos-cloture.sh"$'\n'
    fi
    ts="$(git -C "$repo" log -1 --format=%ct 2>/dev/null || echo 0)"
    if [ "${ts:-0}" -gt 0 ]; then
        age=$(( ( $(date +%s) - ts ) / 86400 ))
        # L'ÂGE NE SONNE QUE SUR UN ARBRE SALE — reporté de la source le 2026-10-02. Un dépôt propre et
        # poussé n'a rien à sauvegarder : il sonnait sur tout domaine inactif depuis une semaine. Ce que
        # l'âge cherche, une clôture qui ne tourne plus, laisse des changements non commités.
        if [ "$age" -gt 7 ] && [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then
            BACKUP_ERR=1
            OUT="${OUT}⚠️ Dépôt ${nom} sans nouveau commit depuis ${age}j — clôture oubliée ? bash ~/.claude/engine/claudeos-cloture.sh"$'\n'
        fi
    fi
    return 0
}
while IFS= read -r _d; do
    [ -n "$_d" ] || continue
    if [ "$_d" = "$HOME/.claude" ]; then _verdict_depot "$_d" "système"
    else _verdict_depot "$_d" "${_d/#$HOME/$CLAUDEOS_TILDE}"; fi
done < <(claudeos_repos)

# Gardes levés à la dernière sauvegarde. Une alarme levée est légitime ; l'oublier ne l'est
# pas. Le hook trace chaque levée, datée, dans le journal du dépôt visé.
# Le journal des levées vit dans le `.git/` de CHAQUE dépôt : la liste suit `claudeos_repos`,
# sinon une levée sur un dépôt client ne serait jamais rapportée au démarrage.
# Sans git, le crochet l'écrit sous le `.claudeos/` de la racine : il n'y a pas de `.git/`.
for _alog in $(claudeos_repos | sed 's|$|/.git/ALARMES_FORCEES.log|') "$ROOT/.claudeos/ALARMES_FORCEES.log"; do
    [ -s "$_alog" ] || continue
    _aday="$(tail -1 "$_alog" | cut -d' ' -f1)"
    [ "$_aday" = "$(date '+%Y-%m-%d')" ] || continue
    OUT="${OUT}🔓 Alarme(s) levée(s) aujourd'hui sur ${_alog#$HOME/} — l'alarme correspondante ne s'est pas exprimée. Vérifier que le motif tient toujours."$'\n'
done

# Le relais des avertissements du gros autotest a disparu ici le 2026-08-22 : il lisait un
# marqueur écrit par la sauvegarde rsync, mécanisme supprimé. Les contrôles qui survivent
# sont ailleurs — les alarmes de contenu au hook de commit, le rangement des secrets au
# wrapper de clôture, les contrôles de documents à la passe hebdomadaire.

# Journal de session périmé ? (rituel de clôture qui ne tourne plus)
# ORDRE DU FICHIER NON PRÉSUMÉ (2026-09-04). Cette ligne lisait la PREMIÈRE date (`grep -m1`).
# Quatre séances écrites en fin de journal ont donc fait annoncer « journal arrêté au 2026-09-02 »
# et une FAUSSE alerte de séance non clôturée, treize jours durant — un faux qui est même entré
# dans le brief de l'audit du jour. Le sens d'insertion est en tête (compétence `reprise`), mais
# un lecteur ne doit pas dépendre d'un geste humain : on prend la date MAXIMALE, quel que soit l'ordre.
#
# REPOINTÉ SUR LE JOURNAL D'ÉVÉNEMENTS le 2026-09-09 (plan de correction de l'audit, lot 5).
# `memory/SESSION_JOURNAL.md` est GELÉ : la chronique des séances du niveau système vit désormais
# dans `journal/*.jsonl`, événements de type `seance`. Lire le fichier gelé figerait la date à
# celle du gel et produirait « journal périmé » puis « séance non clôturée » à CHAQUE démarrage,
# donc une fausse alarme permanente — et une fausse alarme permanente éteint sa catégorie entière.
# Le repli sur le fichier reste, pour le cas où le journal d'événements manque, et IL SE DIT :
# un repli muet se lit comme une mesure faite. `CLAUDEOS_BOOT_SANS_JOURNAL=1` force le repli,
# pour exercer cette branche sans éditer quoi que ce soit.
# JLINE (la ligne « dernière session » du bilan) sort du MÊME événement, ici et non plus 180
# lignes plus bas : deux lectures de deux sources pourraient afficher une date et le résumé
# d'une autre séance.
JLINE=""
if [ "${CLAUDEOS_BOOT_SANS_JOURNAL:-0}" != "1" ]; then
    _JRAW=$(python3 - "$ROOT" <<'PYEOF' 2>/dev/null || true
import glob, json, os, sys
root = sys.argv[1]
best = None
for f in sorted(glob.glob(os.path.join(root, 'journal', '*.jsonl'))):
    try:
        fh = open(f, encoding='utf-8')
    except OSError:
        continue
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if e.get('type') != 'seance':
                continue
            ts = str(e.get('ts', ''))
            if len(ts) < 10:
                continue
            if best is None or ts > best[0]:
                best = (ts, e)
if best:
    ts, e = best
    txt = ' '.join(str(e.get('texte', '')).split())
    if len(txt) > 240:
        txt = txt[:237].rsplit(' ', 1)[0] + '…'
    print(ts[:10])
    print(txt)
PYEOF
)
    JDATE=$(printf '%s\n' "$_JRAW" | sed -n 1p)
    JLINE=$(printf '%s\n' "$_JRAW" | sed -n 2p)
fi
if [ -z "$JDATE" ]; then
    JDATE=$(grep -oE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' "$MEM/SESSION_JOURNAL.md" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort -r | head -1)
    JLINE=$(grep -E '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' "$MEM/SESSION_JOURNAL.md" 2>/dev/null | sort -r | head -1 | sed 's/^##[[:space:]]*//')
    [ -n "$JDATE" ] && OUT="${OUT}⚠️ Chronique des séances lue en REPLI sur memory/SESSION_JOURNAL.md (gelé) — aucun événement \`seance\` dans ${ROOT}/journal/*.jsonl. La date ci-dessous peut être figée."$'\n'
fi
if [ -n "$JDATE" ]; then
    # PORTABILITÉ 2026-09-12 : idem. L'ancien repli rendait 0 jour, donc le journal n'était
    # JAMAIS signalé périmé sur un poste sans `date -d`.
    _j_ts=$(claudeos_epoch_of_date "$JDATE" || true)
    if [ -z "$_j_ts" ]; then
        DAYS=-1
        OUT="${OUT}⚠️ Ancienneté du journal NON MESURÉE — date « ${JDATE} » illisible. Ne pas lire l'absence d'alerte comme un journal frais."$'\n'
    else
        DAYS=$(( ( $(date +%s) - _j_ts ) / 86400 ))
    fi
    JDAYS=$DAYS
    if [ "$DAYS" -gt "$T_CRIT" ]; then
        # `JOURNAL_STALE` retiré le 2026-08-09 : son unique lecteur était la réplique de la
        # bannière. L ancienneté du journal reste dite ici, et graduée par le tableau d état.
        OUT="${OUT}⚠️ Journal périmé (dernière entrée ${JDATE}, il y a ${DAYS}j > ${T_CRIT}) — le rituel de clôture ne tourne peut-être plus"$'\n'
    fi
fi

# --- Séance non clôturée ? (filet, réécrit le 2026-08-22) ---
# Il reposait sur un marqueur que `backup.sh` déposait à chaque passage ; la copie rsync est
# morte, donc le marqueur ne s'écrit plus. La même question se pose maintenant à git, qui est
# la source et non une trace : si le dernier commit du dépôt système est POSTÉRIEUR à la
# dernière entrée de journal, une séance a travaillé et enregistré sans se refermer.
# LECTURE SEULE, dans le bloc ALERTES : alerte datée, bornée, qui disparaît quand on la traite.
# ÉCHAPPATOIRE nécessaire : une séance qui a laissé un bloc « Séance en cours » daté dans une
# reprise a bien consigné son état — la clôture reste à faire, mais rien n'est perdu, et crier
# serait du bruit.
if [ -n "$JDATE" ] && [ -d "$ROOT/.git" ]; then
    AMDATE=$(git -C "$ROOT" log -1 --format=%cd --date=short 2>/dev/null || true)
    if [ -n "$AMDATE" ] && [[ "$AMDATE" > "$JDATE" ]]; then
        AM_INCR=""
        # BI-RÉGIME depuis le 2026-09-08 (geste 2.4). Un niveau qui porte `ETAT.md` a un
        # fichier de reprise GELÉ : il ne dira plus jamais « séance en cours », donc le lire ici
        # allumerait cette alerte à CHAQUE session qui suit un commit — une fausse alarme
        # permanente, et une fausse alarme permanente éteint sa catégorie entière.
        # Pour ces niveaux la preuve d'une séance écrite est un événement `seance` du journal
        # portant la date du commit. Cherché au `grep` sur le journal, pas par un parseur : on
        # ne teste que la présence d'une date sur une ligne de type « seance ».
        while IFS= read -r _lv; do
            [ -n "$_lv" ] || continue
            for _j in "$_lv"/journal/*.jsonl; do
                [ -e "$_j" ] || continue
                grep '"type": *"seance"' "$_j" 2>/dev/null | grep -qF "$AMDATE" \
                    && { AM_INCR=1; break 2; }
            done
        done < <(claudeos_repos)
        # Le repli sur un bloc « Séance en cours » d'un `HANDOFF.md` est RETIRÉ le 2026-09-22 : les
        # fichiers de reprise sont supprimés, la seule preuve d'une séance écrite est l'événement `seance`.
        if [ -z "$AM_INCR" ]; then
            OUT="${OUT}📌 Séance du ${AMDATE} non clôturée (journal arrêté au ${JDATE}) — elle a touché :"$'\n'
            # Substitution de PROCESSUS et non tuyau : un `while read` en bout de tuyau tourne
            # dans un sous-shell, et les ajouts à OUT y meurent avec lui — l'alerte s'afficherait
            # sans sa liste, sans rien signaler.
            while IFS= read -r _af || [ -n "$_af" ]; do
                [ -n "$_af" ] && OUT="${OUT}      ↳ ${_af}"$'\n'
            done < <(git -C "$ROOT" show --name-only --format= HEAD 2>/dev/null | head -10)
            OUT="${OUT}      ↳ écrire l'entrée de journal de cette séance avant d'ouvrir la suivante."$'\n'
        fi
    fi
fi

# Le contrôle « compétence présente au dépôt mais absente en local » a disparu le
# 2026-08-22 : le dépôt système EST `~/.claude`, il n'y a plus deux copies à comparer.
# Ce qu'une compétence manquante signifie désormais, c'est un `git pull` non fait — dit
# par le bloc d'écart plus haut.

# Amorçage auto-détectable par la machine (donc PAS dans le changelog) : la ligne de démarrage
# ClaudeOS dans le fichier de shell. Le greffon superpowers n'est PAS un prérequis du template :
# son contrôle, propre au poste de l'auteur, n'est pas livré (A5, 2026-10-01).
# Quel fichier de shell porte la ligne ? Le poste n'est pas toujours en bash : sur macOS
# le shell de connexion est zsh, `~/.bashrc` n'y existe même pas, et ce garde criait donc
# une absence FAUSSE à chaque démarrage alors que `~/.zshrc` était correctement branché
# (constaté le 2026-09-12 à la migration sur le Mac). On balaie les quatre fichiers
# plausibles, et le message nomme celui du shell COURANT plutôt qu'un `.bashrc` en dur.
_claudeos_rc_trouve=""
for _claudeos_rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    if grep -qF 'claudeos-boot.sh' "$_claudeos_rc" 2>/dev/null; then _claudeos_rc_trouve="$_claudeos_rc"; break; fi
done
case "${SHELL:-}" in *zsh) _claudeos_rc_cible="~/.zshrc" ;; *) _claudeos_rc_cible="~/.bashrc" ;; esac
if [ -f "$SELF/claudeos-boot.sh" ] && [ -z "$_claudeos_rc_trouve" ]; then
    # Le mot « bannière » est tombé le 2026-08-09 avec la bannière : ce que `~/.bashrc` doit
    # sourcer est le WRAPPER, dont le métier est d'injecter le prompt de bilan au lancement.
    # Sans lui, la session démarre muette — le contexte est bien injecté, mais rien ne fait
    # parler l'assistant en premier. Le message porte la ligne elle-même : il renvoyait à une
    # fiche de remise à niveau que le template ne livre pas, et dont la section citée ne la
    # portait pas (A5, 2026-10-01).
    OUT="${OUT}⚠️ Wrapper de démarrage ClaudeOS absent de '"$_claudeos_rc_cible"' (le bilan ne s'ouvrira pas tout seul) — la ligne à y ajouter : [ -f ~/.claude/engine/claudeos-boot.sh ] && . ~/.claude/engine/claudeos-boot.sh"$'\n'
fi

# L'INDEX DE RAPPEL N'A PLUS D'ÂGE, et ce bloc sort le 2026-09-08 (geste 2.7).
# Ce qu'il y avait ici : l'absence et la péremption de `memory/INDEX.md`, plus la ligne
# MEMORY CORE du tableau d'état, graduée sur son ancienneté. `INDEX.md` est GELÉ et
# `build-index.sh` est SUPPRIMÉ : il n'y a plus de générateur, donc plus rien à périmer, et
# une ligne d'état sur l'âge d'un fichier figé aurait vieilli sans jamais rien signaler.
# Ce qui le remplace est déjà affiché plus bas : « État du système — N caractères ».
IDAYS=-1

# --- L'ETAT DU NIVEAU SYSTEME VIENT DE `ETAT.md` depuis le 2026-09-08 (geste 2.4) ------
# RESTAURÉ le 2026-09-08 : le retrait du bloc de l'index ci-dessus avait pris `THREADS=` pour
# borne et avalé CE bloc avec lui. `bash -n` ne l'a pas vu — il vérifie la syntaxe, pas une
# variable non liée —, et le contrôle 21, qui mesurait ce texte, venait d'être retiré au même
# geste. Deux gardes absents au même moment sur le même fichier : c'est ce qui a laissé passer.
# BI-RÉGIME, et le discriminant est nommé : un niveau qui porte `ETAT.md` parle par lui ; un
# BI-REGIME CLOS le 2026-09-09 : les 29 niveaux portent un `ETAT.md`, tous parlent par lui.
ETAT_SYS="$HOME/.claude/ETAT.md"
ETAT_TXT=""
if [ -f "$ETAT_SYS" ]; then
    ETAT_TXT=$(python3 - "$ETAT_SYS" 2>/dev/null <<'PYETAT'
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()

def section(nom):
    m = re.search(r"^## " + re.escape(nom) + r"\n(.*?)(?=^## |^---$|\Z)", t, re.M | re.S)
    return [l for l in (m.group(1).splitlines() if m else []) if l.strip()]

def court(l):
    return re.sub(r"\s+", " ", l).strip()[:120]

print(f"État du système — {len(t)} caractères, projeté depuis le journal :")
for l in section("État courant")[:4]:
    print("  " + court(l))
compte = {}
chantier = "?"
for l in section("Ce qui reste"):
    if l.startswith("### "):
        chantier = l[4:].strip()
    elif l.startswith("- "):
        compte[chantier] = compte.get(chantier, 0) + 1
if compte:
    total = sum(compte.values())
    detail = " · ".join(f"{k} {v}" for k, v in sorted(compte.items()))
    print(f"Dus ouverts du système ({total}) : {detail}")
    print("  → le détail : python3 ~/.claude/engine/etat.py vue --tous")
PYETAT
)
fi

THREADS=$(python3 - "$MEM" "$REG/CRENEAUX" "$(date +%u)" "$SELF" 2>/dev/null <<'PYEOF'
import re, sys, os, subprocess
MEM, CRENEAUX, DOW = sys.argv[1], sys.argv[2], int(sys.argv[3]) - 1
sys.path.insert(0, sys.argv[4])
from lib_creneaux import DAYS, parse_creneaux   # source unique du format (2026-08-22)
def out(s): print(s.rstrip())

creneaux = parse_creneaux(CRENEAUX)
ouverts = sorted(w for w, d in creneaux.items() if DOW in d)
fermes = sorted(w for w in creneaux if w not in ouverts)

# LES FILS VIENNENT DE `etat.py fils`, plus de `OPEN_THREADS.md` — bascule du 2026-09-09.
# Ce fichier était produit par `build-threads.sh`, qui ratissait des TITRES dans les fichiers de reprise ;
# depuis la phase 3 toutes les reprises sont gelées, le générateur ne voyait plus rien, et le
# fichier lui-même est GELÉ depuis le 2026-09-08 — le démarrage affichait donc une vue FIGÉE.
# L'ANCIENNETÉ REPART DU JOUR DE LA BASCULE et c'est une perte assumée : le `ts` d'un événement
# `ouvre` est celui de son écriture, et le report a tout daté du 2026-09-08 ou du 09. Les
# anciennetés d'avant vivent dans `memory/OPEN_THREADS.md`, gelé, cherchées au `grep`.
# LA DORMANCE N'A RIEN À CÂBLER ICI (2026-09-15) : `etat.py fils` retire lui-même les dus non
# touchés depuis `DORMANT_JOURS` et en imprime le COMPTE en pied, sur une ligne `[etat]` que la
# boucle ci-dessous relaie déjà comme les autres. Un dormant n'est donc jamais perdu de vue — il
# est compté à chaque démarrage — et `ETAT.md` n'a pas bougé : la dormance est une règle de
# LECTURE, motivée en tête d'`etat.py` à `DORMANT_JOURS`.
if creneaux:
    out(f"Créneau du jour ({DAYS[DOW]}) : "
        + (f"ouvert pour {', '.join(ouverts)}" if ouverts else "aucun domaine à créneau n'est ouvert")
        + (f" ; hors créneau : {', '.join(fermes)}." if fermes else "."))
_fils = subprocess.run([sys.executable, f'{os.path.expanduser("~")}/.claude/engine/etat.py',
                        'fils', '--tous', '--limite', '5'],
                       capture_output=True, text=True)
if _fils.returncode == 0 and _fils.stdout.strip():
    out('Fils ouverts, par ancienneté :')
    for l in _fils.stdout.strip().splitlines():
        if l.startswith('[') or l.startswith('    '):
            out('  ' + l.strip()[:170])
        elif l.startswith('[etat]'):
            out('  ' + l.strip())
else:
    # Une sortie vide ici est un DÉFAUT, pas une absence de fils : `etat.py fils` rend une ligne
    # même quand il n'y en a aucun. Le dire, plutôt que de laisser un blanc qui se lit « rien à faire ».
    out("  (vue des fils indisponible — jouer : python3 ~/.claude/engine/etat.py fils --tous)")
PYEOF
)
# JLINE EST CALCULÉE EN TÊTE, avec JDATE (2026-09-09, lot 5). Elle se lisait ici, sur
# `memory/SESSION_JOURNAL.md`, par un second `grep` indépendant : deux lectures de deux
# sources auraient pu afficher la date d'une séance et le résumé d'une autre. Une seule
# mesure, un seul événement.

# --- Tableau d'état, consommé par le contexte JSON ---
# Il servait aussi la bannière de terminal, retirée le 2026-08-09 ; c'est la moitié VIVANTE
# de ce qui était partagé, et la raison pour laquelle le retrait s'est arrêté à la bannière.
# Émet des lignes LABEL|STATUT|GRAVITE (gravite = ok, warn ou crit).
_DEP_NOTE=""
[ "$_SONDE_RETARD" = 0 ] && _DEP_NOTE=" — un seul poste, retard non sondé"
build_dashboard() {
    # DÉPÔTS
    if [ "$GIT_OK" = "0" ]; then echo "DÉPÔTS|GIT ABSENT|crit"
    elif [ "$BEHIND" -gt 0 ]; then echo "DÉPÔTS|EN RETARD ${BEHIND} — git pull --rebase|warn"
    elif [ "$DIRTY" -gt 0 ]; then echo "DÉPÔTS|OK (${DIRTY} non commité)${_DEP_NOTE}|ok"
    else echo "DÉPÔTS|OK${_DEP_NOTE}|ok"; fi
    # MEMORY CORE — RETIRÉE le 2026-09-08 (geste 2.7). Elle graduait l'âge de `memory/INDEX.md`,
    # gelé et sans générateur : la ligne aurait vieilli sans jamais rien signaler. La taille de
    # l'état projeté est affichée dans « CE QUI RESTE À FAIRE », qui est un fait, pas un âge.
    if [ -f "$HOME/.claude/ETAT.md" ]; then echo "ÉTAT SYSTÈME|projeté|ok"; fi
    # LEARNING LOOP — RETIRÉE le 2026-09-08 avec le rituel (geste 2.4, D-E). Elle comptait les
    # titres de `LEARNING_PROPOSALS.md`, qui est GELÉ : ses candidates sont devenues des `du`
    # ouverts du niveau, donc elles s'affichent dans « Ce qui reste ». Garder la ligne aurait
    # affiché le MÊME travail deux fois, depuis deux fichiers d'âges différents.
    # SECURITY (dette de rotation de secrets) — seulement si dette
    [ "$SEC_N" -gt 0 ] && echo "SECURITY|${SEC_N} SECRET(S) À RÉGÉNÉRER|crit"
    # SESSION JOURNAL — paliers d'ancienneté
    if [ -z "$JDATE" ]; then echo "SESSION JOURNAL|absent|warn"
    elif [ "$JDAYS" -gt "$T_CRIT" ]; then echo "SESSION JOURNAL|PÉRIMÉ (${JDATE}, ${JDAYS}j)|crit"
    elif [ "$JDAYS" -gt "$T_WARN" ]; then echo "SESSION JOURNAL|vieillit (${JDATE})|warn"
    else echo "SESSION JOURNAL|${JDATE}|ok"; fi
    # PLUMBING
    if [ "$BACKUP_ERR" = "1" ]; then echo "PLUMBING|SAUVEGARDE À VÉRIFIER|crit"
    else echo "PLUMBING|OK|ok"; fi
    # CROISIÈRE (compteur de convergence — DESIGN « Ce que ClaudeOS est »). Jamais `warn` : ce n'est pas un défaut
    # d'être en chantier, c'est un fait à voir. Muet si le dépôt n'a pas d'historique lisible.
    [ "$CRUISE_D" -ge 0 ] && echo "CROISIÈRE|J ${CRUISE_D}/28 (tout chantier remet à zéro ; commit « incident: » non)|ok"
    # CATCH-UP (file de rattrapage manuel par poste — DESIGN « la file de rattrapage », conditionnel)
    [ "${PEND:-0}" -gt 0 ] && echo "À RATTRAPER|${PEND} entrée(s) — ~/.claude/TODO.md|warn"
}
DASH_ROWS=$(build_dashboard)

# =============================================================================
# MODE JSON — contexte du hook SessionStart
# =============================================================================
# Consigne technique de démarrage — injectée au contexte, jamais affichée telle quelle :
# elle fait ouvrir la 1re réponse par le bilan. Déclinable à l'entretien d'installation :
# voir le bloc BILAN_DEMARRAGE plus bas, qui la retire avec le bilan qu'elle ordonne.
DIRECTIVE="⟦CONSIGNE DE DÉMARRAGE — ne pas recopier telle quelle à l'écran⟧
Question implicite de lancement : « tu es à jour ? »
Ouvre ta TOUTE PREMIÈRE réponse par ce bilan, AVANT la demande de l'utilisateur, dans cet ordre :
1) Poste : à jour, ou en retard de N commit(s). Si en retard, PROPOSE « git -C <dépôt> pull --rebase » sur chacun des dépôts en retard, nommés un par un, sans le lancer — le démarrage n'agit jamais seul.
2) Tableau d'état (bloc ci-dessous).
3) Dernière session : poste + résumé.
4) Signaux actionnables s'il y en a (⏰ rappels, 🔐 dette, 🔍 audit — bloc ALERTES).
5) TERMINE PAR UNE PROPOSITION, pas par un état : depuis CE QUI RESTE À FAIRE, dis en 2 ou 3 lignes
   ce que tu ferais aujourd'hui et dans quel ordre. Distingue ce qui se FAIT, ce qui demande sa
   DÉCISION, ce qui n'attend que la RELANCE d'un tiers. Ne propose jamais ce qui est bloqué
   ailleurs ni ce qui est marqué HORS CRÉNEAU : listé et daté, jamais proposé. Un dépassement de
   plafond appartient à l'audit : ni proposé, ni sa mesure relayée — fil ou autotest, même règle.
   Nomme l'ancienneté dans l'unité de la vue (« reconduit 9 fois depuis 15 jours », pas « en retard »). Ta proposition
   n'est pas un ordre : il connaît un contexte que ces fichiers ignorent, il tranche.
Puis enchaîne sur sa demande.
"

# Tableau d'état en texte simple (mêmes lignes que la bannière, sans couleur).
DASH_PLAIN=""
while IFS='|' read -r lbl st sev; do
    [ -z "$lbl" ] && continue
    DASH_PLAIN="${DASH_PLAIN}$(printf '▸ %-17s %s' "$lbl" "$st")"$'\n'
done <<< "$DASH_ROWS"

# Dernière session.
LASTSESS="${JLINE:-(journal indisponible)}"

ALERTS="${OUT:-}"
[ -z "$ALERTS" ] && ALERTS="aucune alerte."

CTX_FULL="=== ClaudeOS boot ===
${DIRECTIVE}
--- TABLEAU D'ÉTAT ---
${DASH_PLAIN}
--- DERNIÈRE SESSION ---
${LASTSESS}

--- ALERTES ---
${ALERTS}

--- CE QUI RESTE À FAIRE ---
${ETAT_TXT}
${THREADS:-(aucun fil ouvert consigné)}

--- POUR ALLER PLUS LOIN ---
Détail des sessions passées : événements \`seance\` de ${ROOT}/journal/*.jsonl
Ne les lire que si l'utilisateur déclare un contexte de travail ou demande l'historique."

# BILAN_DEMARRAGE=non (`reglages/REPONSES`) — l'installateur a décliné le bilan d'ouverture à
# l'entretien. La consigne et le tableau sortent ; la DETTE DE SÉCURITÉ reste : une garde ne se
# décline pas (plan V3, lot 5, geste 3 ; rétabli dans la copie le 2026-10-01, A6). Clé absente :
# le bilan reste, poste non réglé, jamais une valeur d'usine.
if [ "$(claudeos_reponse BILAN_DEMARRAGE 2>/dev/null)" = "non" ]; then
    # Un dépôt qui ne pousse plus rien, un retard ou un distant injoignable sont des gardes au même
    # titre que la dette : ils restent (audit de la v3.0.0, où le bilan décliné les taisait).
    _dette="$(printf '%s\n' "${OUT:-}" | grep -E '🔐|⛔ Dépôt|JAMAIS POUSSÉ|en retard de|distant injoignable' || true)"
    CTX_FULL="=== ClaudeOS boot ===
⟦CONSIGNE DE DÉMARRAGE — ne pas recopier telle quelle à l'écran⟧
Bilan d'ouverture décliné à l'entretien (BILAN_DEMARRAGE=non) : réponds directement à la demande."
    [ -n "$_dette" ] && CTX_FULL="${CTX_FULL}
Seules la dette de sécurité et les gardes de la sauvegarde se signalent, une ligne chacune, avant la réponse :
${_dette}"
fi

# --- Session de PROJET : contexte réduit (2026-08-12) ---------------------------
# Une session de projet porte `CLAUDEOS_SESSION_SCOPE=projet`, posé par tmux à la création
# (`claudeos-session.sh`). Sans la variable, rien ne change : le bilan complet ci-dessus
# reste le défaut.
#
# POURQUOI CETTE BRANCHE EXISTE, mesuré au premier essai réel. Le rôle de la session
# était dit dans le texte de lancement de l'onglet, et ça n'a pas suffi : la consigne
# du hook ORDONNE d'ouvrir par le bilan système, et cet ordre a gagné. La sous-session
# a donc rendu le tableau d'état, proposé `sync.sh` et relayé les signaux racine —
# exactement ce qu'elle ne doit pas faire. Un texte de lancement ne peut pas défaire
# une consigne injectée : c'est la consigne injectée qu'il faut changer.
if [ "${CLAUDEOS_SESSION_SCOPE:-}" = "projet" ]; then
    # Niveau déduit du dossier de DÉMARRAGE, jamais écrit en dur : plusieurs postes, et
    # le dossier personnel diffère. Les dépôts sont sous `~/` depuis le 2026-09-08 ; hors du
    # dossier personnel, on retombe sur le chemin nu.
    # LE DOSSIER DE DÉMARRAGE, PAS LE DOSSIER COURANT — corrigé le 2026-10-01, constaté par une
    # session de projet. Le SessionStart se relance au compactage (matcher `compact`), et
    # un hook tourne dans le dossier COURANT de Claude, qui suit ses `cd` (doc des hooks, vérifiée ce
    # jour-là). Ce bloc lisait donc le niveau d'un sous-dossier : « pas d'ETAT.md », et l'ordre de
    # monter un niveau DANS LE MOTEUR EXPORTÉ du gabarit. Dérivé vers un AUTRE niveau, il en aurait
    # donné le périmètre d'écriture sans un signe. `CLAUDE_PROJECT_DIR` est « the project root where
    # the session started » et « stays put » ; `PWD` ne sert plus que de repli s'il manque.
    _proj="${CLAUDE_PROJECT_DIR:-$PWD}"
    _lvl="${_proj#"$HOME"/}"
    [ "$_lvl" = "$_proj" ] && _lvl="$_proj"
    # BI-RÉGIME, posé le 2026-09-08 (geste 2.4). Le discriminant est NOMMÉ et il est
    # observable : le niveau porte `ETAT.md` → il s'écrit par événements ; il n'en porte pas →
    # il garde ses anciens fichiers d'état. Dire le mauvais périmètre d'écriture à une session
    # de projet la fait écrire dans un fichier que le contrôle 24 refusera au commit.
    # LA CIBLE DE LA REPRISE SUIT LE MÊME DISCRIMINANT QUE LE PÉRIMÈTRE D'ÉCRITURE, et elle doit :
    # jusqu'au 2026-09-10 le bloc `CTX_FULL` plus bas écrivait EN DUR « tu remplis ${_hoff} et
    # ${PWD}/MEMORY.md », sans condition, à douze lignes de ce `if` qui branche correctement. Une
    # session de projet à `ETAT.md` recevait donc les DEUX consignes dans le même texte : son
    # périmètre juste, puis l'ordre de remplir deux fichiers gelés. Le fichier se contredisait dans
    # le même souffle. RAPPORTÉ SUR PIÈCE le 2026-09-10 par la session <APP>,
    # qui s'en est sortie en DÉSOBÉISSANT au texte — pas parce que le texte était juste. Une session
    # moins avertie écrit dans un gelé, se fait refuser au commit par le contrôle 14, et lève
    # peut-être FORCE_GELE en croyant corriger un faux positif.
    # Aucun des six contrôles de l'audit du 2026-09-10 n'avait ce fichier dans son périmètre : ils
    # balaient les documents que l'agent lit, pas le texte qu'un script lui INJECTE.
    if [ -f "$_proj/ETAT.md" ]; then
        _ecrit="ton périmètre d'écriture est \`python3 ~/.claude/engine/etat.py add --niveau $_proj\`,
et rien d'autre : ${_proj}/ETAT.md est une PROJECTION, l'éditer est refusé au commit (contrôle 23)."
        _reprise_cible="tu écris tes événements par \`etat.py add\`, puis tu lances
\`python3 ~/.claude/engine/etat.py projette --niveau $_proj\`. ${_proj}/MEMORY.md, s'il existe, est
GELÉ : lecture seule, jamais écrit — le contrôle 14 refuse le commit."
        _rep="${_proj}/ETAT.md et son journal \`journal/*.jsonl\`"
    else
        # PLUS AUCUN niveau vivant sans `ETAT.md` depuis le 2026-09-22 : un
        # dossier qui n'en porte pas n'est pas encore un niveau. On le dit, on ne prescrit plus
        # d'écrire un `MEMORY.md`.
        _ecrit="Ce dossier ne porte PAS d'ETAT.md : ce n'est pas encore un niveau du système. Avant
d'y écrire quoi que ce soit, le monter par la compétence \`nouveau-projet\`, qui crée son ETAT.md."
        _reprise_cible="rien tant que le niveau n'est pas monté."
        _rep="(aucune — ${_proj}/ETAT.md absent)"
    fi

    CTX_FULL="=== ClaudeOS boot — session de PROJET ===
⟦CONSIGNE DE DÉMARRAGE — ne pas recopier telle quelle à l'écran⟧
Tu es la session dédiée à ${_lvl}. Il n'y a pas de bilan système ici : ouvre ta première
réponse par l'état de CE niveau, trois lignes au plus, depuis sa reprise.
${_ecrit}
Le global appartient à la session principale — règlement racine, mémoire racine,
DESIGN.md, sauvegarde, synchronisation, boucle d'apprentissage, journal de session.
Ce qui relève d'elle, remonte-le lui en une ligne ; elle l'écrit, pas toi.
Tu lui parles pour de vrai, ce n'est pas une note laissée sur un coin de table :
\`ListAgents\` donne son nom, \`SendMessage\` lui porte le message.
Tu POUSSES ton dossier toi-même, compétence \`pousser-son-dossier\` ; la CLÔTURE — contrôles,
projection de tous les niveaux, synchronisation — reste à la session principale.
Ta reprise : ${_reprise_cible} Puis tu pousses ton dossier. Une reprise écrite et non poussée
disparaît au prochain travail fait depuis un autre poste.
Puis enchaîne sur sa demande.

--- NIVEAU ---
${_lvl}
Reprise : ${_rep}

--- POUR ALLER PLUS LOIN ---
État système, fils ouverts de tous les projets, clôture : session principale."
fi

# --- L'installation inachevée (M-INACHEVEE), EN TÊTE, dans les deux portées ------------------
# Plan complet de templating § 1.5, A6 (2026-10-01). Les trois tests se CALCULENT à chaque
# démarrage, jamais stockés : `verifier.py inachevee` les porte avec le texte du message, ce bloc ne
# fait que le relayer. Code propre au template, appelé en quelques lignes (A3, geste 7). Un échec du
# vérificateur se DIT : un état d'installation non mesuré ne se lit pas comme une installation finie.
_inach="$(python3 "$SELF/verifier.py" inachevee --message 2>&1)"; _rc_inach=$?
case "$_rc_inach" in
    0) _inach="" ;;
    1) ;;
    *) _inach="⚠ État de l'installation NON MESURÉ — engine/verifier.py inachevee a rendu ${_rc_inach} : $(printf '%s\n' "$_inach" | tail -n 1)" ;;
esac
[ -n "$_inach" ] && CTX_FULL="⟦À DIRE EN PREMIER, telle quelle, avant toute autre ligne⟧
${_inach}

${CTX_FULL}"

python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": sys.argv[1]}}))
' "$CTX_FULL"
