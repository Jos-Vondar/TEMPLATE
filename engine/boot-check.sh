#!/usr/bin/env bash
# =============================================================================
# BOOT CHECK — ClaudeOS (hook SessionStart)
# LECTURE SEULE : détecte les écarts, n'agit jamais (pas de pull/install/écriture).
# L'utilisateur décide.
# UN SEUL MODE : émet le JSON `additionalContext` attendu par le hook SessionStart, donc
# injecté dans le contexte du modèle et invisible à l'écran. C'est le MODÈLE qui rend le
# bilan, en première réponse, poussé par la consigne cachée du bloc DIRECTIVE plus bas.
#
# LA BANNIÈRE SHELL A ÉTÉ RETIRÉE le 2026-08-09. Un mode `--human` dessinait un bandeau
# coloré dans le terminal ; son unique appelant était le wrapper `boot-wrapper.sh`, qui a cessé de
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
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/synclib.sh"

OUT=""

# --- Flags de gravité, consommés par le tableau d'état (build_dashboard) ---
BEHIND=0; DIRTY=0; PROP_N=0; DISTILL_DUE=0; SEC_N=0
GIT_OK=1; BACKUP_ERR=0; SYNC_INCOMPLETE=0; JDATE=""; JDAYS=-1
SKILLS_MISSING=""; IDAYS=-1
CRUISE_D=-1

# --- Écart git du repo de config ---
if [ -d "$ROOT/.git" ]; then
    # Fetch réseau INCONDITIONNEL depuis le 2026-08-09. Il était sauté dans le mode bannière,
    # pour un bandeau instantané, au prix d'un retard évalué sur la dernière ref connue. Ce
    # mode n'existe plus : le seul appelant restant est le déclencheur, où la mesure doit être
    # juste — c'est elle qui décide si le poste est annoncé à jour ou en retard.
    git -C "$ROOT" fetch --quiet 2>/dev/null
    BEHIND=$(git -C "$ROOT" rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
    DIRTY=$(git -C "$ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    [ "$BEHIND" -gt 0 ] && OUT="${OUT}⚠️ Config en retard de ${BEHIND} commit(s) — lance: bash ~/.claudeos/engine/sync.sh"$'\n'
    [ "$DIRTY" -gt 0 ] && OUT="${OUT}• ${DIRTY} fichier(s) non commités dans le repo config"$'\n'
    # #25 : croissance non bornée du dépôt (format lourd échappant à SYNC_IGNORE) ?
    PACK_KB=$(du -sk "$ROOT/.git" 2>/dev/null | cut -f1)
    [ "${PACK_KB:-0}" -gt 204800 ] && OUT="${OUT}⚠️ Dépôt config .git > 200 Mo — un format lourd échappe probablement à SYNC_IGNORE"$'\n'

    # --- Compteur de convergence (2026-08-09, le document de conception). LECTURE SEULE. ---
    # Croisière = 28 jours consécutifs sans chantier moteur ni chantier de règles. Le compteur
    # rend la condition d'arrêt VISIBLE : sans lui, « le système est-il fini ? » ne se pose
    # jamais, et l'amélioration indéfinie est ce qui a produit l'usine à gaz du 2026-07-27.
    # Périmètre du chantier : `engine/` et `system/CLAUDE.md` — le moteur et le règlement.
    # `--invert-grep` écarte les réparations : un enregistrement dont le message commence par
    # `incident:` ne remet pas le compteur à zéro, c'est ce qui distingue un système qui se
    # répare d'un système qu'on refait. La convention est écrite DANS le message du compteur,
    # pas seulement ici : personne ne vient lire un script pour savoir comment nommer un commit.
    # `MACHINE_TODO.md` est EXCLU du périmètre, constaté en exerçant le compteur le jour de son
    # écriture : il vit sous `engine/` et `machine-todo.sh` l'enregistre tout seul, si bien que
    # la moindre consigne inter-machines remettait le compteur à zéro. Une file d'attente n'est
    # pas un chantier — sans cette exclusion, le compteur n'aurait jamais dépassé quelques jours
    # et aurait fini par ne rien mesurer du tout.
    CRUISE_TS=$(git -C "$ROOT" log -1 --format='%ct' --invert-grep --regexp-ignore-case \
        --grep='^incident:' -- engine system/CLAUDE.md ':!engine/config/MACHINE_TODO.md' 2>/dev/null)
    if [ -n "${CRUISE_TS:-}" ] && [ "$CRUISE_TS" -gt 0 ] 2>/dev/null; then
        CRUISE_D=$(( ( $(date +%s) - CRUISE_TS ) / 86400 ))
    fi
fi

# --- Flag propositions d'apprentissage ---
LP="$MEM/LEARNING_PROPOSALS.md"
if [ -f "$LP" ]; then
    # Un titre BARRÉ (`## ~~`) est une proposition déjà traitée, conservée pour que la
    # distillation voie ce qu'elle a produit : elle ne se compte pas. Corrigé le 2026-08-12 —
    # le compteur annonçait 2 en attente là où une seule l'était, l'autre étant barrée depuis
    # le 2026-08-10. Une alarme se construit sur l'état courant, jamais sur la trace d'un état
    # passé : compter un titre barré, c'est retrouver un souvenir. Le motif `awk '/^## /` reste
    # littéral en tête, car `selftest.sh` § 20 le cherche au caractère près.
    PROP_N=$(awk '/^## /{ if ($0 !~ /^## *~~/) n++ } END{print n+0}' "$LP" 2>/dev/null || echo 0)   # #8 : toujours numérique, toujours rc 0
    [ "$PROP_N" -gt 0 ] && OUT="${OUT}🧠 ${PROP_N} proposition(s) d'apprentissage en attente de validation ($LP)"$'\n'
fi

# --- Dette de sécurité : secrets compromis / à régénérer (jamais de valeur — CLAUDE.md §4) ---
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
        rts=$(date -d "$rdate" +%s 2>/dev/null || echo 0)
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

# --- Distillation hebdo due ? (déclenchée à l'ouverture de session) ---
# Marqueur = semaine ISO de la dernière distillation. Si la semaine courante diffère,
# la distillation est due. LECTURE SEULE ici : c'est l'assistant qui la lance et met à
# jour le marqueur (cf. CLAUDE.md §6 / le document de conception).
WEEK=$(date +%G-W%V)
MARKER="$MEM/.last_distillation"
if [ "$(cat "$MARKER" 2>/dev/null || echo "")" != "$WEEK" ]; then
    DISTILL_DUE=1
    OUT="${OUT}🧪 Distillation d'apprentissage DUE (semaine ${WEEK}) — relire 7j de HANDOFF/JOURNAL/feedback, proposer des promotions, puis écrire ${WEEK} dans ${MARKER}."$'\n'
fi

# --- Audit du système dû ? (cadence mensuelle, lecture seule) ---
# La plomberie est testée à chaque sauvegarde ; le CONTENU (la carte dit-elle encore vrai ?)
# n'est vérifié que par l'audit, qui n'a pas de déclencheur propre. Sans rappel, il ne
# tourne qu'à la demande — donc jamais.
# Deux niveaux depuis le 2026-07-25 : un contrôle de contenu LÉGER greffé sur la distillation
# hebdomadaire (avertissements du filet, trois sondages dans la carte, registre des ratés,
# fils reconduits — voir la compétence `session`), et cet audit COMPLET en éventail, cher, dont le
# Depuis le 2026-07-27 l'audit est HEBDOMADAIRE : il a reçu tout ce qui a quitté la
# clôture (hygiène, retombée documentaire, distillation, ratés de routage), donc son seuil
# passe de 90 à 7 jours.
AUDIT_DIR="$HOME/.claude/audits"
AUDIT_LAST=$(ls -1 "$AUDIT_DIR"/os-audit-*.md 2>/dev/null | sed 's/.*os-audit-//;s/\.md$//' | sort | tail -1)
if [ -z "$AUDIT_LAST" ]; then
    OUT="${OUT}🔍 Audit du système jamais lancé — « os audit » pour vérifier que la carte dit encore vrai."$'\n'
else
    AUDIT_DAYS=$(( ( $(date +%s) - $(date -d "$AUDIT_LAST" +%s 2>/dev/null || date +%s) ) / 86400 ))
    if [ "$AUDIT_DAYS" -gt 7 ]; then
        OUT="${OUT}🔍 Audit du système DÛ (dernier : ${AUDIT_LAST}, il y a ${AUDIT_DAYS} j) — « os audit »."$'\n'
    fi
fi

# --- Auto-diagnostic de la plomberie (« fail loud ») ---
# Le second brain doit signaler quand SA PROPRE machinerie casse, plutôt que d'échouer en silence.

# Dépendance dure : git (sinon la détection d'écart ci-dessus est muette)
if ! command -v git >/dev/null 2>&1; then
    GIT_OK=0
    OUT="${OUT}⚠️ git introuvable — détection d'écart de config désactivée"$'\n'
fi

# Dépendance dure : rsync (sinon backup.sh refuse de tourner). Détectable => sondé
# ici, jamais porté dans le changelog manuel.
if ! command -v rsync >/dev/null 2>&1; then
    OUT="${OUT}⚠️ rsync introuvable — dépendance dure du backup : installe-le (sudo apt-get install -y rsync)"$'\n'
fi

# Dernier backup auto en échec / interrompu / muet ? (le hook SessionEnd log ici, personne ne le lit)
# Trois cas, pas seulement "ERREUR" : (a) refus explicite, (b) exécution ni réussie ni en
# erreur nette = interrompue (timeout SessionEnd tué en plein push), (c) log périmé = hook muet.
#
# Le verdict porte sur la DERNIÈRE opération enregistrée, jamais sur la présence du mot
# "ERREUR" dans une fenêtre de fin de fichier (corrigé le 2026-07-27). Motif, constaté sur
# pièce : une erreur de verrou suivie de quatre sauvegardes propres alarmait encore, parce
# qu'elle tenait la cinquième ligne depuis la fin et que le test lisait `tail -5`. Une alarme
# qui survit à sa cause devient du bruit qu'on apprend à ignorer, et elle apprend à ignorer
# aussi les vraies. On repère donc la dernière ligne de VERDICT (ERREUR/ALARME contre
# "Sauvegarde terminée"/"Aucun changement"), les lignes de conseil qui suivent un échec ne
# portant aucun verdict ; puis on vérifie qu'aucune ligne de progression n'apparaît APRÈS
# elle, ce qui signerait un passage suivant jamais arrivé à son terme.
LOG="$SELF/backup-hook.log"
if [ -f "$LOG" ]; then
    LOG_AGE=$(( ( $(date +%s) - $(stat -c %Y "$LOG" 2>/dev/null || date +%s) ) / 86400 ))
    # awk plutôt qu'une boucle `read` : celle-ci perd la dernière ligne d'un fichier sans
    # retour à la ligne final, défaut déjà payé une fois sur le relais des rappels datés.
    BK_VERDICT=none; BK_LINE=0; BK_PROG=0; BK_OV="-"
    IFS=' ' read -r BK_VERDICT BK_LINE BK_PROG BK_OV <<< "$(awk '
        # `ov` = gardes levés portés par la ligne de verdict (backup.sh, 2026-08-09). Il se
        # réarme à CHAQUE ligne de verdict, y compris les lignes en prose qui n en portent
        # jamais : sans ce réarmement, un override lu tôt survivrait à des passages propres
        # plus récents — l alarme survivant à sa cause, défaut déjà payé sur ce même bloc.
        function grab_ov(l) {
            if (match(l, /overrides=[A-Z_,]+/)) return substr(l, RSTART+10, RLENGTH-10)
            return ""
        }
        # Journal structuré depuis le 2026-08-08 : backup.sh écrit lui-même sa classe,
        # quelle que soit la voie d appel. Contrat des classes : voir backup.sh (verdict()).
        /VERDICT=refus-retard/                                  { v="late"; vl=NR; ov=grab_ov($0); next }
        /VERDICT=(err|refus-garde)/                             { v="err";  vl=NR; ov=grab_ov($0); next }
        /VERDICT=ok/                                            { v="ok";   vl=NR; ov=grab_ov($0); next }
        # Lignes en prose, antérieures au journal structuré : on continue de les lire pour
        # ne pas perdre le verdict sur un journal existant. Le refus pour retard passe
        # AVANT le motif générique — sa ligne porte le mot ERREUR sans être une panne.
        /en retard de [0-9]+ commit/                            { v="late"; vl=NR; ov=""; next }
        /ERREUR|ALARME/                                        { v="err"; vl=NR; ov=""; next }
        /Sauvegarde terminée|Aucun changement à sauvegarder/    { v="ok";  vl=NR; ov=""; next }
        /Pull --rebase|^\[main |^To |main -> main|files? changed|^ *create mode/ { prog=NR }
        END { printf "%s %d %d %s", (v==""?"none":v), vl+0, prog+0, (ov==""?"-":ov) }
    ' "$LOG" 2>/dev/null)"
    : "${BK_VERDICT:=none}" "${BK_LINE:=0}" "${BK_PROG:=0}" "${BK_OV:=-}"
    if [ "$BK_VERDICT" = "none" ] && [ -s "$LOG" ]; then
        BACKUP_ERR=1
        OUT="${OUT}⚠️ Journal de backup sans verdict lisible (ni réussite ni erreur) — voir $LOG"$'\n'
    elif [ "$BK_PROG" -gt "$BK_LINE" ]; then
        BACKUP_ERR=1
        OUT="${OUT}⚠️ Dernier backup auto ni réussi ni en erreur nette (interrompu ? timeout SessionEnd ?) — voir $LOG"$'\n'
    elif [ "$BK_VERDICT" = "err" ]; then
        BACKUP_ERR=1
        OUT="${OUT}⚠️ Dernier backup automatique en ERREUR — voir $LOG"$'\n'
    elif [ "$LOG_AGE" -gt 7 ]; then
        BACKUP_ERR=1
        OUT="${OUT}⚠️ Backup auto sans trace depuis ${LOG_AGE}j — le hook SessionEnd tourne-t-il encore ? ($LOG)"$'\n'
    elif [ "$BK_VERDICT" = "late" ] && [ "$BEHIND" -gt 0 ]; then
        # Refus pour cause de poste non synchronisé : un garde-fou en bon état, pas une
        # panne — donc PAS de BACKUP_ERR, la plomberie reste verte (décision du 2026-08-08,
        # écrite en DESIGN). L état courant du retard vient de git ligne 30, jamais du
        # journal : si le retard a disparu, ce refus n a plus d objet et on se taît.
        # La limite qui vivait ici est TOMBÉE avec la bannière (2026-08-09) : le retard
        # s évaluait sans fetch dans le mode terminal, si bien qu un retard apparu depuis
        # pouvait faire taire ce rappel d une session. Il n y a plus qu un mode, et il fetche.
        OUT="${OUT}⚠️ Dernière sauvegarde REFUSÉE : poste en retard de ${BEHIND} commit(s). Synchronise puis relance: bash ~/.claudeos/engine/sync.sh"$'\n'
    fi
    # Garde levé au dernier passage (2026-08-09). INDÉPENDANT de la chaîne ci-dessus, qui est
    # exclusive : le cas qui coûte est justement `VERDICT=ok` avec un levier levé — la
    # plomberie paraît verte alors qu'une alarme s'est tue par décision. On rappelle la
    # décision, on ne la conteste pas : lever un levier est légitime, l'oublier ne l'est pas.
    if [ "$BK_OV" != "-" ]; then
        OUT="${OUT}🔓 Dernière sauvegarde passée avec garde levé : ${BK_OV} — l'alarme correspondante ne s'est pas exprimée. Vérifier que le motif tient toujours, ou relancer sans le levier."$'\n'
    fi
fi

# Dernier sync INCOMPLET ? (application repo->live partielle, cf. sync.sh #14)
# NB : ce fichier est un verrou d'état, pas une horloge — seul le mot INCOMPLET est lu.
# Sa date ne mesure PAS la fraîcheur du poste (retard en commits et git log s'en chargent).
SLOG="$SELF/sync-last.log"
if [ -f "$SLOG" ] && grep -q "INCOMPLET" "$SLOG" 2>/dev/null; then
    SYNC_INCOMPLETE=1
    OUT="${OUT}⚠️ Dernier sync INCOMPLET (application repo→live partielle) — relance: bash ~/.claudeos/engine/sync.sh"$'\n'
fi

# Dérive live<->repo à l'ÉTAT COURANT (ajouté 2026-08-06).
# Motif : le verrou ci-dessus ne fait que rejouer le verdict laissé par le dernier sync —
# une trace d'un état passé, ce que la fiche des contrôles interdit comme seule base d'alarme.
# Une dérive apparue APRÈS un sync réussi (backup échoué, fichier écrasé hors session)
# n'était vue par rien jusqu'au sync suivant. Mesure directe, ~0,4 s.
# Avertit, ne bloque pas : c'est un écart à arbitrer, pas une désactivation silencieuse.
claudeos_drift BOOT_DRIFT_MISSING BOOT_DRIFT_DIFFERS
if [ "${#BOOT_DRIFT_MISSING[@]}" -gt 0 ]; then
    OUT="${OUT}⚠️ ${#BOOT_DRIFT_MISSING[@]} fichier(s) du dépôt ABSENT(S) en local (sync jamais appliqué) — bash ~/.claudeos/engine/sync.sh"$'\n'
fi
if [ "${#BOOT_DRIFT_DIFFERS[@]}" -gt 0 ]; then
    OUT="${OUT}⚠️ ${#BOOT_DRIFT_DIFFERS[@]} fichier(s) local/dépôt au contenu DIVERGENT (ex. ${BOOT_DRIFT_DIFFERS[0]#"$HOME"/}) — travail non sauvegardé, ou dernier backup en échec"$'\n'
fi

# La liste blanche cesse d'être silencieuse (2026-08-09). LECTURE SEULE.
# Motif : le verrou de `.gitignore` refuse tout fichier NEUF, et ce refus n'était annoncé que
# par `backup.sh` — en fin de séance, dans une sortie que le hook redirige vers un journal que
# personne ne lit. Un fichier refusé n'existe plus que sur un poste : c'est la perte de
# continuité la plus sournoise du système, et deux victimes l'ont prouvé (la spec de la vague
# elle-même, et un résidu de rappel de voix refusé à chaque sauvegarde depuis le 2026-08-05).
# La logique n'est pas recopiée ici : elle vit dans `synclib.sh`, appelée par les deux.
# Une ligne par fichier, dans le bloc ALERTES — donc exclu du calcul du contrôle de poids
# (#21), comme toute alerte datée : elle est bornée par construction et disparaît quand on
# la traite. On ne bloque pas, on nomme ; c'est l'utilisateur qui décide d'autoriser ou non.
BOOT_REFUSES=$(claudeos_refused_by_lock)
if [ -n "$BOOT_REFUSES" ]; then
    OUT="${OUT}📵 $(printf '%s\n' "$BOOT_REFUSES" | wc -l | tr -d ' ') fichier(s) refusé(s) par la liste blanche — ils n'existent que sur ce poste :"$'\n'
    while IFS= read -r _rf || [ -n "$_rf" ]; do
        [ -z "$_rf" ] && continue
        OUT="${OUT}      ↳ ${_rf}"$'\n'
    done <<< "$BOOT_REFUSES"
    OUT="${OUT}      ↳ décider pour chacun : autorisation \`!<chemin>\` après le verrou de ~/.claudeos/.gitignore, ou déplacement hors zone sauvegardée."$'\n'
fi

# #7 : dernier backup fait HORS-LIGNE ? (garde-fou de fraîcheur évalué sur ref périmée)
[ -f "$SELF/.last-offline-backup" ] && OUT="${OUT}⚠️ Dernier backup fait HORS-LIGNE (fraîcheur non garantie) — vérifie le retard: bash ~/.claudeos/engine/sync.sh"$'\n'

# --- Avertissements du dernier autotest (2026-08-14) --------------------------
# La sauvegarde les enregistre (synclib.sh, claudeos_selftest_warns_record) ; ici on les
# relaie au réveil, comme les autres marqueurs — sans ce relais, ils n'existaient que
# dans une sortie que le hook redirige vers un journal que personne ne lit. Anti-bruit :
# le DÉTAIL le jour où l'ensemble change, une seule ligne — compte + ancienneté — ensuite.
# L'ancienneté affichée dit d'elle-même qu'un avertissement traîne ; le traiter fait
# disparaître la ligne à la sauvegarde suivante. LECTURE SEULE, comme tout ce script :
# l'état appartient à backup.sh. Bloc ALERTES, donc hors du calcul de poids (#21).
ST_BILAN="$(claudeos_selftest_warns_bilan)"
if [ -n "$ST_BILAN" ]; then
    ST_TETE="$(printf '%s\n' "$ST_BILAN" | head -1)"
    ST_DEPUIS="${ST_TETE%%$'\t'*}"; ST_N="${ST_TETE##*$'\t'}"
    if [ "$ST_DEPUIS" = "$(date '+%Y-%m-%d')" ]; then
        OUT="${OUT}⚠️ ${ST_N} avertissement(s) à l'autotest de plomberie — ensemble nouveau ou modifié aujourd'hui :"$'\n'
        while IFS= read -r _sw || [ -n "$_sw" ]; do
            [ -z "$_sw" ] && continue
            OUT="${OUT}      ↳ ${_sw}"$'\n'
        done < <(printf '%s\n' "$ST_BILAN" | tail -n +2)
    else
        OUT="${OUT}⚠️ ${ST_N} avertissement(s) d'autotest, inchangés depuis ${ST_DEPUIS} — détail : bash ~/.claudeos/engine/selftest.sh"$'\n'
    fi
fi

# Journal de session périmé ? (rituel de clôture qui ne tourne plus)
JDATE=$(grep -m1 -oE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' "$MEM/SESSION_JOURNAL.md" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
if [ -n "$JDATE" ]; then
    DAYS=$(( ( $(date +%s) - $(date -d "$JDATE" +%s 2>/dev/null || echo "$(date +%s)") ) / 86400 ))
    JDAYS=$DAYS
    if [ "$DAYS" -gt 10 ]; then
        # `JOURNAL_STALE` retiré le 2026-08-09 : son unique lecteur était la réplique de la
        # bannière. L ancienneté du journal reste dite ici, et graduée par le tableau d état.
        OUT="${OUT}⚠️ Journal périmé (dernière entrée ${JDATE}, il y a ${DAYS}j) — le rituel de clôture ne tourne peut-être plus"$'\n'
    fi
fi

# --- Séance non clôturée ? (filet dernière-activité, 2026-08-09) ---
# `backup.sh` laisse un marqueur local à chaque passage : sa date, et les fichiers qu'il a mis
# en file. Si ce marqueur est POSTÉRIEUR à la dernière entrée de journal, une séance a travaillé
# et enregistré sans se refermer — le rituel de clôture n'a pas tourné. L'interruption non
# annoncée cesse d'être aveugle : on ne peut pas compter sur un signal de fin que l'utilisateur
# ne donne pas toujours (le poste s'éteint, ou il passe à autre chose).
# LECTURE SEULE, et dans le bloc ALERTES : c'est une alerte datée, bornée, qui disparaît quand
# on la traite — donc exclue du calcul du contrôle de poids (#21), comme les autres.
# ÉCHAPPATOIRE, et elle est nécessaire : l'écriture de reprise en séance laisse un bloc « Séance en cours »
# daté dans la reprise du niveau. S'il en existe un du même jour, la séance a bien laissé son
# état — la clôture reste à faire, mais rien n'est perdu, et crier serait du bruit.
ACTMARK="$SELF/.derniere-activite"
if [ -f "$ACTMARK" ] && [ -n "$JDATE" ]; then
    AMDATE=$(head -1 "$ACTMARK" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
    if [ -n "$AMDATE" ] && [[ "$AMDATE" > "$JDATE" ]]; then
        AM_INCR=""
        while IFS= read -r _hf; do
            grep -qF "Séance en cours" "$_hf" 2>/dev/null \
                && grep -qF "$AMDATE" "$_hf" 2>/dev/null && { AM_INCR=1; break; }
        done < <( { echo "$HOME/.claude/HANDOFF.md"
                    while IFS= read -r _wr; do
                        find "$_wr" -maxdepth 3 -name HANDOFF.md -type f 2>/dev/null
                    done < <(claudeos_ws_roots); } )
        if [ -z "$AM_INCR" ]; then
            OUT="${OUT}📌 Séance du ${AMDATE} non clôturée (journal arrêté au ${JDATE}) — elle a touché :"$'\n'
            # Substitution de PROCESSUS et non tuyau : un `while read` en bout de tuyau tourne
            # dans un sous-shell, et les ajouts à OUT y meurent avec lui — l'alerte s'afficherait
            # sans sa liste, sans rien signaler.
            while IFS= read -r _af || [ -n "$_af" ]; do
                [ -n "$_af" ] && OUT="${OUT}      ↳ ${_af}"$'\n'
            done < <(tail -n +2 "$ACTMARK" | head -10)
            OUT="${OUT}      ↳ écrire l'entrée de journal de cette séance avant d'ouvrir la suivante."$'\n'
        fi
    fi
fi

# Skills attendus (repo = source de vérité) absents en local ?
REPO_SK="$ROOT/system/skills"; LOCAL_SK="$HOME/.claude/skills"
if [ -d "$REPO_SK" ]; then
    for d in "$REPO_SK"/*/; do
        [ -d "$d" ] || continue
        n=$(basename "$d")
        [ -d "$LOCAL_SK/$n" ] || SKILLS_MISSING="${SKILLS_MISSING} ${n}"
    done
    [ -n "$SKILLS_MISSING" ] && OUT="${OUT}⚠️ Skill(s) manquant(s) en local (présents dans le repo) :${SKILLS_MISSING} — lance: bash ~/.claudeos/engine/sync.sh"$'\n'
fi

# Amorçages auto-détectables par la machine (donc PAS dans le changelog) :
# la ligne bannière de démarrage dans ~/.bashrc et le plugin superpowers.
if [ -f "$SELF/boot-wrapper.sh" ] && ! grep -qF 'boot-wrapper.sh' "$HOME/.bashrc" 2>/dev/null; then
    # Le mot « bannière » est tombé le 2026-08-09 avec la bannière : ce que `~/.bashrc` doit
    # sourcer est le WRAPPER, dont le métier est d'injecter le prompt de bilan au lancement.
    # Sans lui, la session démarre muette — le contexte est bien injecté, mais rien ne fait
    # parler l'assistant en premier. Le renvoi de document est conservé mot pour mot : la
    # chaîne d'export le réécrit par substitution littérale.
    OUT="${OUT}⚠️ Wrapper de démarrage absent de ~/.bashrc (le bilan ne s'ouvrira pas tout seul) — ajouter à ~/.bashrc la ligne : source ~/.claudeos/engine/boot-wrapper.sh"$'\n'
fi
if ! find "$HOME/.claude/plugins" -maxdepth 3 -iname '*superpowers*' 2>/dev/null | grep -q .; then
    OUT="${OUT}⚠️ Plugin superpowers absent — lance: bash ~/.claudeos/engine/sync.sh"$'\n'
fi

# Index de rappel absent ou périmé ?
IDX="$MEM/INDEX.md"
if [ ! -f "$IDX" ]; then
    # `INDEX_BAD` retiré le 2026-08-09, même motif que `JOURNAL_STALE` ci-dessus : lu par la
    # seule bannière. Le tableau d état porte déjà l état de la carte de rappel, gradué.
    OUT="${OUT}⚠️ Index de rappel absent (memory/INDEX.md) — sera régénéré au prochain backup"$'\n'
else
    IDATE=$(grep -m1 -oE 'auto-généré le [0-9]{4}-[0-9]{2}-[0-9]{2}' "$IDX" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
    if [ -n "$IDATE" ]; then
        ID=$(( ( $(date +%s) - $(date -d "$IDATE" +%s 2>/dev/null || echo "$(date +%s)") ) / 86400 ))
        IDAYS=$ID
        if [ "$ID" -gt 10 ]; then
            OUT="${OUT}⚠️ Index de rappel périmé (généré ${IDATE}, il y a ${ID}j) — relance backup.sh"$'\n'
        fi
    fi
fi

# --- Identité de poste + file de rattrapage manuel (modèle ciblé par poste) ---
# Résout hostname -> id via le registre. Inconnu = fail-loud (jamais un faux « rien
# à rattraper »). Si connu : remonte le nombre d'entrées qui ciblent CE poste — dans
# OUT, donc visible AUSSI dans le contexte du modèle (pas seulement la bannière).
ME=""; PEND=0
REG="$SYNC_MACHINES"
if [ -f "$REG" ]; then
    ME=$(awk -v h="$(hostname)" '!/^[[:space:]]*#/ && NF>=2 && $1==h {print $2; exit}' "$REG")
    if [ -z "$ME" ]; then
        OUT="${OUT}⚠️ Poste '$(hostname)' absent du registre SYNC_MACHINES — ajoute-le (sinon le rattrapage par poste est aveugle)"$'\n'
    elif [ -x "$SELF/machine-todo.sh" ]; then
        PEND=$(SYNC_MACHINE="$ME" "$SELF/machine-todo.sh" count 2>/dev/null || echo 0)
        [ "${PEND:-0}" -gt 0 ] && OUT="${OUT}📋 ${PEND} rattrapage(s) manuel(s) pour ce poste (${ME}) — bash ~/.claudeos/engine/machine-todo.sh pending"$'\n'
    fi
fi

T_WARN=7; T_CRIT=14   # paliers d'ancienneté (jours) : <T_WARN vert, T_WARN..T_CRIT jaune, >T_CRIT rouge

# --- Rappel des dernières sessions ---
# Ce qui reste à faire, vu par ancienneté et non par dernière session : la vue agrégée
# (engine/build-threads.sh, régénérée à chaque sauvegarde) porte l'âge de première apparition
# et le nombre de reconductions — c'est ça qui permet de PROPOSER au lieu de rapporter. Repli
# sur les fils de la dernière session si le fichier n'existe pas encore (poste neuf).
# Le créneau du jour (2026-08-09, le document de conception) : la déclaration est relue ICI et non
# recopiée depuis la vue, parce que la vue est régénérée à la SAUVEGARDE — donc la veille au
# soir — et qu'un créneau est une propriété d'aujourd'hui. La vue apporte l'attribution d'un
# fil à un domaine, ce démarrage apporte la date. Aucun fil n'est masqué : le hors-créneau est
# marqué, et c'est la consigne de démarrage qui l'écarte de la PROPOSITION.
THREADS=$(python3 - "$MEM" "$CFG/CRENEAUX" "$(date +%u)" 2>/dev/null <<'PYEOF'
import re, sys, os
MEM, CRENEAUX, DOW = sys.argv[1], sys.argv[2], int(sys.argv[3]) - 1
def out(s): print(s.rstrip())

DAYS = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim']
creneaux = {}
try:
    for line in open(CRENEAUX, encoding='utf-8'):
        line = line.split('#', 1)[0].strip()
        f = line.split()
        if len(f) < 2: continue
        idx = sorted({DAYS.index(j) for j in f[1].split(',') if j in DAYS})
        if idx: creneaux[f[0]] = idx
except OSError:
    pass
ouverts = sorted(w for w, d in creneaux.items() if DOW in d)
fermes = sorted(w for w in creneaux if w not in ouverts)

p = f'{MEM}/OPEN_THREADS.md'
if os.path.exists(p):
    t = open(p, encoding='utf-8').read()
    ech = re.search(r'^## Échéances dépassées\n(.*?)(?=^## |\Z)', t, re.M | re.S)
    # 6 colonnes depuis le 2026-08-09 : `Créneau` s'est insérée entre `Reconduit` et `Geste`.
    tab = re.findall(r'^\| (\d+) j \| (\d{4}-\d{2}-\d{2}) \| ([^|]*) \| ([^|]*) \| ([^|]*) \| ([^|]*) \|$',
                     t, re.M)
    if creneaux:
        out(f"Créneau du jour ({DAYS[DOW]}) : "
            + (f"ouvert pour {', '.join(ouverts)}" if ouverts else "aucun domaine à créneau n'est ouvert")
            + (f" ; hors créneau : {', '.join(fermes)}." if fermes else "."))
    if ech and ech.group(1).strip():
        out('Échéances dépassées :')
        for l in ech.group(1).strip().splitlines()[:3]:
            out('  ' + l.strip()[:170])
    if tab:
        out('Fils ouverts, par ancienneté :')
        for a, d, rec, cren, g, txt in tab[:5]:
            r = f", reconduit {rec.strip()}" if rec.strip() not in ('—', '') else ''
            c = cren.strip()
            ws = c.split('·')[0].strip()
            k = ''
            if ws in creneaux:
                k = f", {c.split('·',1)[1].strip()}" if '·' in c else ''
                if ws not in ouverts: k += ' — HORS CRÉNEAU aujourd’hui'
            out(f'  - [{a} j{r}{k}] {g.strip()} : ' + re.sub(r'\s+', ' ', txt).strip()[:150])
else:
    j = f'{MEM}/SESSION_JOURNAL.md'
    try: t = open(j, encoding='utf-8').read()
    except OSError: sys.exit(0)
    m = re.search(r'^## .*?(?=^## |\Z)', t, re.M | re.S)
    if m:
        f = re.search(r'^\*\*Fils ouverts\*\*.*?(?=^\*\*|^---|\Z)', m.group(0), re.M | re.S)
        if f: out(f.group(0).strip())
PYEOF
)
JLINE=$(grep -m1 '^## ' "$MEM/SESSION_JOURNAL.md" 2>/dev/null | sed 's/^##[[:space:]]*//')

# --- Tableau d'état, consommé par le contexte JSON ---
# Il servait aussi la bannière de terminal, retirée le 2026-08-09 ; c'est la moitié VIVANTE
# de ce qui était partagé, et la raison pour laquelle le retrait s'est arrêté à la bannière.
# Émet des lignes LABEL|STATUT|GRAVITE (gravite = ok, warn ou crit).
build_dashboard() {
    # CONFIG SYNC
    if [ "$GIT_OK" = "0" ]; then echo "CONFIG SYNC|GIT ABSENT|crit"
    elif [ "$BEHIND" -gt 0 ]; then echo "CONFIG SYNC|EN RETARD ${BEHIND} — sync.sh|warn"
    elif [ "$DIRTY" -gt 0 ]; then echo "CONFIG SYNC|OK (${DIRTY} non commit)|ok"
    else echo "CONFIG SYNC|OK|ok"; fi
    # MEMORY CORE (index de rappel) — paliers d'ancienneté
    if [ ! -f "$IDX" ]; then echo "MEMORY CORE|INDEX À RÉGÉNÉRER|warn"
    elif [ "$IDAYS" -gt "$T_CRIT" ]; then echo "MEMORY CORE|INDEX PÉRIMÉ (${IDAYS}j)|crit"
    elif [ "$IDAYS" -gt "$T_WARN" ]; then echo "MEMORY CORE|index vieillit (${IDAYS}j)|warn"
    else echo "MEMORY CORE|OK|ok"; fi
    # LEARNING LOOP
    if [ "$DISTILL_DUE" = "1" ]; then echo "LEARNING LOOP|DISTILLATION DUE|warn"
    elif [ "$PROP_N" -gt 0 ]; then echo "LEARNING LOOP|${PROP_N} PROPOSITION(S)|warn"
    else echo "LEARNING LOOP|idle|ok"; fi
    # SECURITY (dette de rotation de secrets) — seulement si dette
    [ "$SEC_N" -gt 0 ] && echo "SECURITY|${SEC_N} SECRET(S) À RÉGÉNÉRER|crit"
    # SESSION JOURNAL — paliers d'ancienneté
    if [ -z "$JDATE" ]; then echo "SESSION JOURNAL|absent|warn"
    elif [ "$JDAYS" -gt "$T_CRIT" ]; then echo "SESSION JOURNAL|PÉRIMÉ (${JDATE}, ${JDAYS}j)|crit"
    elif [ "$JDAYS" -gt "$T_WARN" ]; then echo "SESSION JOURNAL|vieillit (${JDATE})|warn"
    else echo "SESSION JOURNAL|${JDATE}|ok"; fi
    # PLUMBING
    if [ "$BACKUP_ERR" = "1" ]; then echo "PLUMBING|BACKUP EN ERREUR|crit"
    elif [ "$SYNC_INCOMPLETE" = "1" ]; then echo "PLUMBING|SYNC INCOMPLET|crit"
    elif [ -n "$SKILLS_MISSING" ]; then echo "PLUMBING|SKILL(S) MANQUANT(S)|warn"
    else echo "PLUMBING|OK|ok"; fi
    # CROISIÈRE (compteur de convergence — le document de conception). Jamais `warn` : ce n'est pas un défaut
    # d'être en chantier, c'est un fait à voir. Muet si le dépôt n'a pas d'historique lisible.
    [ "$CRUISE_D" -ge 0 ] && echo "CROISIÈRE|J ${CRUISE_D}/28 (tout chantier remet à zéro ; commit « incident: » non)|ok"
    # CATCH-UP (file de rattrapage manuel par poste — le document de conception, conditionnel)
    if [ -z "$ME" ]; then echo "CATCH-UP|POSTE NON ENREGISTRÉ|crit"
    elif [ "${PEND:-0}" -gt 0 ]; then echo "CATCH-UP|${PEND} À RATTRAPER (machine-todo.sh pending)|warn"; fi
}
DASH_ROWS=$(build_dashboard)

# =============================================================================
# MODE JSON — contexte du hook SessionStart
# =============================================================================
# Consigne cachée : force le modèle à ouvrir sa 1re réponse par le bilan.
DIRECTIVE="⟦CONSIGNE DE DÉMARRAGE — ne pas recopier telle quelle à l'écran⟧
Question implicite de lancement : « tu es à jour ? »
Ouvre ta TOUTE PREMIÈRE réponse par ce bilan, AVANT la demande de l'utilisateur, dans cet ordre :
1) Poste : à jour, ou en retard de N commit(s). Si en retard, PROPOSE « bash ~/.claudeos/engine/sync.sh » sans le lancer — le démarrage n'agit jamais seul.
2) Tableau d'état (bloc ci-dessous).
3) Dernière session : poste + résumé.
4) Signaux actionnables s'il y en a (⏰ rappels, 🔐 dette, 🧪 distillation, 🔍 audit — bloc ALERTES).
5) TERMINE PAR UNE PROPOSITION, pas par un état : depuis CE QUI RESTE À FAIRE, dis en 2 ou 3 lignes
   ce que tu ferais aujourd'hui et dans quel ordre. Distingue ce qui se FAIT, ce qui demande sa
   DÉCISION, ce qui n'attend que la RELANCE d'un tiers. Ne propose jamais ce qui est bloqué
   ailleurs ni ce qui est marqué HORS CRÉNEAU : listé et daté, jamais proposé. Nomme l'ancienneté
   dans l'unité de la vue (« reconduit 9 fois depuis 15 jours », pas « en retard »). Ta proposition
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
${THREADS:-(aucun fil ouvert consigné)}

--- POUR ALLER PLUS LOIN ---
Détail des sessions passées : ${MEM}/SESSION_JOURNAL.md
Ne le lire que si l'utilisateur déclare un contexte de travail ou demande l'historique."

# --- Session de PROJET : contexte réduit (2026-08-12) ---------------------------
# Une session lancée par session-open.sh porte `OS_SESSION_SCOPE=projet`. Sans la
# variable, rien ne change : le bilan complet ci-dessus reste le défaut.
#
# POURQUOI CETTE BRANCHE EXISTE, mesuré au premier essai réel. Le rôle de la session
# était dit dans le texte de lancement de l'onglet, et ça n'a pas suffi : la consigne
# du hook ORDONNE d'ouvrir par le bilan système, et cet ordre a gagné. La sous-session
# a donc rendu le tableau d'état, proposé `sync.sh` et relayé les signaux racine —
# exactement ce qu'elle ne doit pas faire. Un texte de lancement ne peut pas défaire
# une consigne injectée : c'est la consigne injectée qu'il faut changer.
if [ "${OS_SESSION_SCOPE:-}" = "projet" ]; then
    # Niveau déduit du dossier courant, jamais écrit en dur : plusieurs postes, et
    # le dossier personnel diffère. Hors `workstations/`, on retombe sur le chemin nu.
    _lvl="${PWD#"$HOME"/workstations/}"
    [ "$_lvl" = "$PWD" ] && _lvl="$PWD"
    _hoff="$PWD/HANDOFF.md"
    [ -f "$_hoff" ] && _hoff_st="présente" || _hoff_st="à créer au premier palier"

    CTX_FULL="=== ClaudeOS boot — session de PROJET ===
⟦CONSIGNE DE DÉMARRAGE — ne pas recopier telle quelle à l'écran⟧
Tu es la session dédiée à ${_lvl}. Il n'y a pas de bilan système ici : ouvre ta première
réponse par l'état de CE niveau, trois lignes au plus, depuis sa reprise.
Ton périmètre d'écriture est ce dossier : ${_hoff} et ${PWD}/MEMORY.md.
Le global appartient à la session principale — règlement racine, mémoire racine,
DESIGN.md, sauvegarde, synchronisation, boucle d'apprentissage, journal de session.
Ce qui relève d'elle, remonte-le lui en une ligne ; elle l'écrit, pas toi.
La sauvegarde et la synchronisation se lancent depuis la session principale seulement :
deux sauvegardes concurrentes écrivent l'une par-dessus l'autre.
Puis enchaîne sur sa demande.

--- NIVEAU ---
${_lvl}
Reprise : ${_hoff} (${_hoff_st})

--- POUR ALLER PLUS LOIN ---
État système, fils ouverts de tous les projets, sauvegarde : session principale."
fi

python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": sys.argv[1]}}))
' "$CTX_FULL"
