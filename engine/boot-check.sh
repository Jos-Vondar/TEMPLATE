#!/usr/bin/env bash
# =============================================================================
# BOOT CHECK — ClaudeOS (hook SessionStart + bannière de terminal)
# LECTURE SEULE : détecte les écarts, n'agit jamais (pas de pull/install/écriture).
# L'utilisateur décide.
# Deux modes, une seule source de vérité pour les vérifs :
#   (défaut)  émet le JSON additionalContext attendu par le hook SessionStart
#             → injecté dans le contexte du modèle (invisible à l'écran).
#   --human   affiche une bannière de boot animée dans le terminal
#             → pour les yeux de l'utilisateur (appelée par le wrapper boot-wrapper.sh).
# =============================================================================
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/synclib.sh"

MODE="${1:-}"
OUT=""

# --- Flags pour le rendu humain (le mode JSON n'utilise que OUT) ---
BEHIND=0; DIRTY=0; PROP_N=0; DISTILL_DUE=0; SEC_N=0
GIT_OK=1; BACKUP_ERR=0; SYNC_INCOMPLETE=0; JOURNAL_STALE=0; JDATE=""; JDAYS=-1
INDEX_BAD=0; SKILLS_MISSING=""; IDAYS=-1

# --- Écart git du repo de config ---
if [ -d "$ROOT/.git" ]; then
    # Fetch réseau seulement en mode JSON (hook). En --human on s'appuie sur la dernière
    # ref connue → bannière instantanée ; le hook rafraîchit live juste après le lancement.
    [ "$MODE" = "--human" ] || git -C "$ROOT" fetch --quiet 2>/dev/null
    BEHIND=$(git -C "$ROOT" rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
    DIRTY=$(git -C "$ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    [ "$BEHIND" -gt 0 ] && OUT="${OUT}⚠️ Config en retard de ${BEHIND} commit(s) — lance: bash ~/.claudeos/engine/sync.sh"$'\n'
    [ "$DIRTY" -gt 0 ] && OUT="${OUT}• ${DIRTY} fichier(s) non commités dans le repo config"$'\n'
    # #25 : croissance non bornée du dépôt (format lourd échappant à SYNC_IGNORE) ?
    PACK_KB=$(du -sk "$ROOT/.git" 2>/dev/null | cut -f1)
    [ "${PACK_KB:-0}" -gt 204800 ] && OUT="${OUT}⚠️ Dépôt config .git > 200 Mo — un format lourd échappe probablement à SYNC_IGNORE"$'\n'
fi

# --- Flag propositions d'apprentissage ---
LP="$MEM/LEARNING_PROPOSALS.md"
if [ -f "$LP" ]; then
    PROP_N=$(awk '/^## /{n++} END{print n+0}' "$LP" 2>/dev/null || echo 0)   # #8 : toujours numérique, toujours rc 0
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
# rappel échu en début de séance, avant de dérouler la demande (fiches/SESSION.md).
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
# fils reconduits — voir fiches/SESSION.md), et cet audit COMPLET en éventail, cher, dont le
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
    BK_VERDICT=none; BK_LINE=0; BK_PROG=0
    IFS=' ' read -r BK_VERDICT BK_LINE BK_PROG <<< "$(awk '
        /ERREUR|ALARME/                                        { v="err"; vl=NR; next }
        /Sauvegarde terminée|Aucun changement à sauvegarder/    { v="ok";  vl=NR; next }
        /Pull --rebase|^\[main |^To |main -> main|files? changed|^ *create mode/ { prog=NR }
        END { printf "%s %d %d", (v==""?"none":v), vl+0, prog+0 }
    ' "$LOG" 2>/dev/null)"
    : "${BK_VERDICT:=none}" "${BK_LINE:=0}" "${BK_PROG:=0}"
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

# #7 : dernier backup fait HORS-LIGNE ? (garde-fou de fraîcheur évalué sur ref périmée)
[ -f "$SELF/.last-offline-backup" ] && OUT="${OUT}⚠️ Dernier backup fait HORS-LIGNE (fraîcheur non garantie) — vérifie le retard: bash ~/.claudeos/engine/sync.sh"$'\n'

# Journal de session périmé ? (rituel de clôture qui ne tourne plus)
JDATE=$(grep -m1 -oE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' "$MEM/SESSION_JOURNAL.md" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
if [ -n "$JDATE" ]; then
    DAYS=$(( ( $(date +%s) - $(date -d "$JDATE" +%s 2>/dev/null || echo "$(date +%s)") ) / 86400 ))
    JDAYS=$DAYS
    if [ "$DAYS" -gt 10 ]; then
        JOURNAL_STALE=1
        OUT="${OUT}⚠️ Journal périmé (dernière entrée ${JDATE}, il y a ${DAYS}j) — le rituel de clôture ne tourne peut-être plus"$'\n'
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
    OUT="${OUT}⚠️ Bannière de démarrage absente de ~/.bashrc — ajouter à ~/.bashrc la ligne : source ~/.claudeos/engine/boot-wrapper.sh"$'\n'
fi
if ! find "$HOME/.claude/plugins" -maxdepth 3 -iname '*superpowers*' 2>/dev/null | grep -q .; then
    OUT="${OUT}⚠️ Plugin superpowers absent — lance: bash ~/.claudeos/engine/sync.sh"$'\n'
fi

# Index de rappel absent ou périmé ?
IDX="$MEM/INDEX.md"
if [ ! -f "$IDX" ]; then
    INDEX_BAD=1
    OUT="${OUT}⚠️ Index de rappel absent (memory/INDEX.md) — sera régénéré au prochain backup"$'\n'
else
    IDATE=$(grep -m1 -oE 'auto-généré le [0-9]{4}-[0-9]{2}-[0-9]{2}' "$IDX" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
    if [ -n "$IDATE" ]; then
        ID=$(( ( $(date +%s) - $(date -d "$IDATE" +%s 2>/dev/null || echo "$(date +%s)") ) / 86400 ))
        IDAYS=$ID
        if [ "$ID" -gt 10 ]; then
            INDEX_BAD=1
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
THREADS=$(python3 - "$MEM" 2>/dev/null <<'PYEOF'
import re, sys, os
MEM = sys.argv[1]
def out(s): print(s.rstrip())
p = f'{MEM}/OPEN_THREADS.md'
if os.path.exists(p):
    t = open(p, encoding='utf-8').read()
    ech = re.search(r'^## Échéances dépassées\n(.*?)(?=^## |\Z)', t, re.M | re.S)
    tab = re.findall(r'^\| (\d+) j \| (\d{4}-\d{2}-\d{2}) \| ([^|]*) \| ([^|]*) \| ([^|]*) \|$', t, re.M)
    if ech and ech.group(1).strip():
        out('Échéances dépassées :')
        for l in ech.group(1).strip().splitlines()[:3]:
            out('  ' + l.strip()[:170])
    if tab:
        out('Fils ouverts, par ancienneté :')
        for a, d, rec, g, txt in tab[:5]:
            r = f", reconduit {rec.strip()}" if rec.strip() not in ('—', '') else ''
            out(f'  - [{a} j{r}] {g.strip()} : ' + re.sub(r'\s+', ' ', txt).strip()[:150])
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

# --- Tableau d'état commun (bannière --human + contexte JSON) ---
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
    # CATCH-UP (file de rattrapage manuel par poste — le document de conception, conditionnel)
    if [ -z "$ME" ]; then echo "CATCH-UP|POSTE NON ENREGISTRÉ|crit"
    elif [ "${PEND:-0}" -gt 0 ]; then echo "CATCH-UP|${PEND} À RATTRAPER (machine-todo.sh pending)|warn"; fi
}
DASH_ROWS=$(build_dashboard)

# =============================================================================
# MODE HUMAIN — bannière de boot animée (terminal)
# =============================================================================
if [ "$MODE" = "--human" ]; then
    ESC=$'\033'
    if [ -t 1 ]; then
        B="${ESC}[1m"; D="${ESC}[2m"; G="${ESC}[32m"; Y="${ESC}[33m"; R="${ESC}[31m"; C="${ESC}[36m"; X="${ESC}[0m"
    else
        B=""; D=""; G=""; Y=""; R=""; C=""; X=""
    fi
    # Les pauses d'affichage sont RETIRÉES le 2026-08-05 : la fonction est inerte, ses neuf
    # appels restent en place pour dire où le bandeau respirait. Mesuré avant retrait :
    # 1,150 s de temps réel pour 0,196 s de temps processeur, soit environ 0,95 s passée à
    # attendre, à chaque ouverture de terminal. Le tableau d'état s'affiche sans elles.
    nap() { : "$1"; }
    sub() { # $1 label  $2 statut  $3 couleur
        printf "  %s▸%s %s%-17s%s %s%s%s\n" "$C" "$X" "$D" "$1" "$X" "$3" "$2" "$X"
        nap 0.10
    }

    printf "\n"
    printf "  %s  ██████  %s\n"                              "$C" "$X"; nap 0.05
    printf "  %s ██    ██ %s   %sassistant%s\n"                   "$C" "$X" "$B" "$X"; nap 0.05
    printf "  %s ██    ██ %s   %sClaudeOS · second brain%s\n" "$C" "$X" "$D" "$X"; nap 0.05
    printf "  %s ██    ██ %s\n"                                   "$C" "$X"; nap 0.05
    printf "  %s  ██████  %s\n"                               "$C" "$X"; nap 0.12

    # Tableau d'état — consomme les rows calculées en zone commune (build_dashboard)
    while IFS='|' read -r lbl st sev; do
        [ -z "$lbl" ] && continue
        case "$sev" in ok) col="$G";; warn) col="$Y";; crit) col="$R";; *) col="$X";; esac
        sub "$lbl" "$st" "$col"
    done <<< "$DASH_ROWS"

    # Rappel de la dernière session (JLINE calculé en zone commune)
    printf "  %s────────────────────────────────────────%s\n" "$D" "$X"; nap 0.10
    [ -n "$JLINE" ] && { printf "  %sDernière session%s · %s\n" "$D" "$X" "$JLINE"; nap 0.06; }

    # Punchline — contextuelle si alerte, sinon pool aléatoire
    if [ "$BACKUP_ERR" = "1" ]; then
        LINE="Dernière sauvegarde en erreur."
    elif [ "$BEHIND" -gt 0 ]; then
        LINE="Configuration en retard sur le dépôt. Lance sync.sh."
    elif [ "$DISTILL_DUE" = "1" ]; then
        LINE="Distillation en attente : des règles candidates attendent une décision."
    elif [ "$JOURNAL_STALE" = "1" ]; then
        LINE="Journal périmé : la dernière clôture de séance remonte à loin."
    elif [ "$PROP_N" -gt 0 ] || [ "$GIT_OK" = "0" ] || [ -n "$SKILLS_MISSING" ] || [ "$INDEX_BAD" = "1" ]; then
        LINE="Signaux au démarrage, détaillés ci-dessus."
    else
        POOL=(
            "Système prêt."
            "Démarrage terminé, aucun signal."
            "En ligne. Rien à signaler."
            "État nominal."
        )
        IDX2=$(( RANDOM % ${#POOL[@]} ))
        LINE="${POOL[$IDX2]}"
    fi
    printf "\n  %sOS>%s %s%s%s\n\n" "$B$C" "$X" "$D" "$LINE" "$X"
    exit 0
fi

# =============================================================================
# MODE JSON — contexte du hook SessionStart
# =============================================================================
# Consigne cachée : force le modèle à ouvrir sa 1re réponse par le bilan.
DIRECTIVE="⟦CONSIGNE DE DÉMARRAGE — ne pas recopier telle quelle à l'écran⟧
Question implicite de lancement : « tu es à jour ? »
Ouvre ta TOUTE PREMIÈRE réponse de la session par ce bilan, AVANT de traiter la demande de l'utilisateur, dans cet ordre :
1) État du poste courant : à jour, ou en retard de N commit(s). Si en retard, PROPOSE « bash ~/.claudeos/engine/sync.sh » sans le lancer toi-même (le démarrage n'agit jamais seul).
2) Tableau d'état (bloc TABLEAU D'ÉTAT ci-dessous).
3) Dernière session : poste + résumé (bloc DERNIÈRE SESSION).
4) Signaux actionnables s'il y en a (rappels ⏰, dette 🔐, distillation 🧪, audit 🔍 — bloc ALERTES).
5) TERMINE PAR UNE PROPOSITION, pas par un état : à partir du bloc CE QUI RESTE À FAIRE, dis ce que
   tu ferais aujourd'hui et dans quel ordre, en 2 ou 3 lignes. Distingue ce qui se FAIT, ce qui
   demande une DÉCISION de lui, et ce qui n'attend que la RELANCE d'un tiers — ne propose jamais
   comme travail du jour ce qui est bloqué ailleurs. Nomme l'ancienneté quand elle est parlante
   (« reconduit 9 fois depuis 15 jours » vaut mieux que « en retard »). Ta proposition n'est pas
   un ordre : il connaît un contexte que ces fichiers ignorent, il tranche.
Puis enchaîne sur la demande de l'utilisateur.
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

python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": sys.argv[1]}}))
' "$CTX_FULL"
