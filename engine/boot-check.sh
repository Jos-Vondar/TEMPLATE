#!/usr/bin/env bash
# =============================================================================
# BOOT CHECK — ClaudeOS (hook SessionStart)
# LECTURE SEULE : détecte les écarts, n'agit jamais (pas de pull/install/écriture).
# L'utilisateur décide.
# UN SEUL MODE : émet le JSON `additionalContext` attendu par le hook SessionStart, donc
# injecté dans le contexte du modèle et invisible à l'écran. DONNÉES SEULEMENT : la conduite du
# bilan vit dans la compétence `demarrage`, que le mod `mods/demarrage-auto` invoque par `/demarrage`.
# Deux motifs, doc des hooks : un `additionalContext` au-delà de 10 000 caractères n'arrive au
# modèle qu'en aperçu de 2 000, et un texte formulé en ordres système peut déclencher les défenses
# contre l'injection — d'où des ÉNONCÉS FACTUELS ici, et un budget sous 9 000 caractères.
# DEUX EXCEPTIONS, voulues :
#  - les garde-fous d'une session de PROJET restent ici, écrits en faits, parce qu'un skill invoqué
#    peut sortir du contexte à la compaction (doc des skills, « Skill content lifecycle ») et qu'un
#    périmètre d'écriture ne doit jamais en sortir ;
#  - `BILAN_DEMARRAGE=non` (`reglages/REPONSES`) : le mod ne lance pas `/demarrage` en session
#    principale, et ce script n'y rend que les gardes qui ne se déclinent pas (bloc dédié plus bas).
#    `CLAUDEOS_BILAN_DEMANDE=1` passe outre : c'est le rejeu d'un `/demarrage` tapé à la main.
# =============================================================================
set -uo pipefail

# --- Refus des arguments inconnus ---
# Ce script ne prend AUCUN argument. Un drapeau hérité d'une note ancienne serait sinon IGNORÉ EN
# SILENCE, et la personne conclurait à une panne. Politique du moteur : un drapeau inconnu se
# refuse, il ne se subit pas.
if [ "$#" -gt 0 ]; then
    echo "[boot-check] ERREUR : argument inattendu ('$*'). Ce script ne prend aucun argument." >&2
    echo "[boot-check] Il émet le JSON du déclencheur SessionStart, et rien d'autre : le bilan est" >&2
    echo "[boot-check] rendu par le modèle, compétence demarrage." >&2
    exit 2
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

OUT=""

# --- Émission du JSON du hook : une seule fonction, deux sorties possibles ---
_emet() {
    # Un bloc vide laisse des lignes blanches en série : resserrées à une seule.
    python3 -c '
import json, re, sys
c = re.sub(r"\n\s*\n(\s*\n)+", "\n\n", sys.argv[1]).strip()
# Borne d injection : au-delà de 10 000 caractères le hook ne passe qu un aperçu. Le dire EN TÊTE,
# là où l aperçu le garde. (Pas d apostrophe ici : ce code est entre apostrophes shell.)
if len(c) > 9500:
    c = f"⚠️ BLOC DE DÉMARRAGE À {len(c)} CARACTÈRES — au-delà de 10 000, il ne passe plus en entier.\n" + c
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": c}}))
' "$1"
}

# --- Source du déclenchement : startup, resume, clear, compact ou fork ---
# Le hook reçoit son entrée en JSON sur stdin, champ `source` (doc des hooks). Lu seulement si
# stdin n'est pas un terminal, et borné à 2 s par `select`, sans `timeout`, que macOS n'a pas :
# `weekly-check.sh` lance ce script à la main, et une lecture sans garde l'aurait suspendu. Sans
# entrée lisible, on se comporte comme au démarrage.
HOOK_SOURCE="startup"
if [ ! -t 0 ]; then
    _s=$(python3 -c '
import json, os, select, sys, time
fin, buf = time.time() + 2, b""
while True:
    reste = fin - time.time()
    if reste <= 0 or not select.select([0], [], [], reste)[0]:
        break
    b = os.read(0, 65536)
    if not b:
        break
    buf += b
try:
    print(json.loads(buf or b"{}").get("source", ""))
except Exception:
    pass' 2>/dev/null || true)
    [ -n "$_s" ] && HOOK_SOURCE="$_s"
fi
# La session tmux qui pose la question n'est pas « une autre session dans le dépôt ».
MOI_TMUX=""
[ -n "${TMUX:-}" ] && MOI_TMUX=$(tmux display-message -p '#S' 2>/dev/null || true)
MOI="$MOI_TMUX"

# --- Session de PROJET : niveau et garde-fous, calculés AVANT tout le reste ---
# Ils servent à deux sorties : le démarrage complet et la compaction, où rien d'autre n'est
# rejoué. Une session de projet porte `CLAUDEOS_SESSION_SCOPE=projet`, posé par
# `claudeos-session.sh` à la création. Sans la variable, c'est la principale.
# Niveau déduit du dossier de DÉMARRAGE, jamais écrit en dur : plusieurs postes, et le dossier
# personnel diffère. LE DOSSIER DE DÉMARRAGE, PAS LE DOSSIER COURANT : le SessionStart se relance
# au compactage, et un hook tourne dans le dossier COURANT de Claude, qui suit ses `cd`.
# `CLAUDE_PROJECT_DIR` est « the project root where the session started » ; `PWD` n'est qu'un repli.
# Sans la variable — un rejeu à la main depuis l'outil Bash, qui ne la pose pas —, le dossier
# courant peut être un sous-dossier du niveau : remonter au premier ancêtre qui porte `ETAT.md`.
_proj="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$_proj" ]; then
    _proj="$PWD"; _d="$PWD"
    while [ "$_d" != "/" ] && [ "$_d" != "$HOME" ]; do
        if [ -f "$_d/ETAT.md" ]; then _proj="$_d"; break; fi
        _d=$(dirname "$_d")
    done
fi
_lvl="${_proj#"$HOME"/}"
# Nommé depuis sa RACINE (dépôt, ou racine marquée sans git), comme `etat.py fils --json` : un
# chemin réel faisait d'un dossier parent un mot du libellé, que le filtre des rappels lisait sur
# tous les niveaux.
_lvl_d=$(python3 -c 'import os,sys;sys.path.insert(0,sys.argv[2]);import etat;d=etat.racine_depot(sys.argv[1]);r=os.path.relpath(os.path.realpath(sys.argv[1]),d);print(os.path.basename(d)+("" if r=="." else "/"+r))' "$_proj" "$SELF" 2>/dev/null) && [ -n "$_lvl_d" ] && _lvl="$_lvl_d"
[ "$_lvl" = "$_proj" ] && _lvl="$_proj"
# Discriminant : le niveau porte `ETAT.md` → il s'écrit par événements ; il n'en porte pas → ce
# n'est pas encore un niveau. Les compétences à charger sont NOMMÉES : sans elles, le crochet
# `rappel-fichiers-nommage.sh` refuse le premier appel de la séance. Écrits en faits, pas en
# ordres (doc des hooks : un ordre système peut être pris pour une injection).
if [ "$(claudeos_regime)" = aucun ]; then
    _POUSSE="- Sans git, rien ne se pousse ; la clôture reste à la session principale."
else
    _POUSSE="- Cette session pousse son dossier elle-même par la compétence \`pousser-son-dossier\` ; la clôture reste à la principale."
    [ "$(claudeos_reponse MULTIPOSTE 2>/dev/null)" = "non" ] || _POUSSE="${_POUSSE}
- Une reprise écrite et non poussée disparaît au prochain travail fait depuis un autre poste."
fi
if [ -f "$_proj/ETAT.md" ]; then
    GARDEFOUS="Garde-fous de cette session de projet :
- Niveau de cette session : ${_proj}. Son périmètre d'écriture est \`python3 ~/.claude/engine/etat.py add --niveau <niveau>\`, puis \`etat.py projette --niveau <niveau>\`. Son ETAT.md est une projection : le crochet de commit \`pre-commit-alarmes.sh\` en refuse l'édition à la main (code 23). Son MEMORY.md, s'il existe, est gelé (même crochet, code 24).
- Le crochet \`rappel-fichiers-nommage.sh\` refuse le premier \`etat.py add\` (sa seule consultation \`--help\` exceptée) tant que la compétence \`memoire-et-verite\` n'est pas chargée. La forme d'un événement de séance est dans la compétence \`reprise\`.
- Le global — règlement racine, mémoire racine, REMINDERS.md, sauvegarde, journal du système — appartient à la session principale. Une remontée lui parvient par \`ListAgents\` puis \`SendMessage\` ; le crochet refuse le premier \`SendMessage\` tant que la compétence \`session\` n'est pas chargée.
${_POUSSE}"
else
    # Aucun niveau vivant n'est sans `ETAT.md` : un dossier qui n'en porte pas n'est pas encore un niveau.
    GARDEFOUS="Garde-fous de cette session de projet :
- ${_proj} ne porte pas d'ETAT.md : ce n'est pas encore un niveau du système. La compétence \`nouveau-projet\` le monte et crée son ETAT.md ; rien ne s'y écrit avant.
- Le global appartient à la session principale ; une remontée lui parvient par \`ListAgents\` puis \`SendMessage\`, après chargement de la compétence \`session\`."
fi

# --- Compaction : seuls les garde-fous reviennent, sans fetch ---
# Le passage complet coûte un fetch par dépôt et réinjecterait le bilan au milieu d'une séance.
# Ce qui doit survivre à une compaction, c'est le périmètre.
if [ "$HOOK_SOURCE" = "compact" ]; then
    if [ "${CLAUDEOS_SESSION_SCOPE:-}" = "projet" ]; then
        _emet "=== ClaudeOS — session de PROJET ${_lvl}, après compaction ===
${GARDEFOUS}"
    else
        _emet "=== ClaudeOS — session PRINCIPALE, après compaction ($(date '+%Y-%m-%d %H:%M')) ===
Les données de démarrage ne sont pas rejouées à la compaction ; \`/demarrage\` rejoue le bilan."
    fi
    exit 0
fi

# --- L'installation inachevée, EN TÊTE, dans les deux portées ---
# Les trois tests se CALCULENT à chaque démarrage, jamais stockés : `verifier.py inachevee` les
# porte avec le texte du message, ce script ne fait que le relayer. Un échec du vérificateur se DIT :
# un état d'installation non mesuré ne se lit pas comme une installation finie.
_inach="$(python3 "$SELF/verifier.py" inachevee --message 2>&1)"; _rc_inach=$?
case "$_rc_inach" in
    0) _inach="" ;;
    1) ;;
    *) _inach="⚠ État de l'installation NON MESURÉ — engine/verifier.py inachevee a rendu ${_rc_inach} : $(printf '%s\n' "$_inach" | tail -n 1)" ;;
esac
INACH=""
[ -n "$_inach" ] && INACH="Installation : l'utilisateur veut ce message dit en premier, tel quel, avant toute autre ligne —
${_inach}
"

# Paliers d'ancienneté, en jours : < T_WARN vert · T_WARN..T_CRIT jaune · > T_CRIT rouge.
# Définis en tête, avant leur première utilisation (`set -u`) : un seul seuil par grandeur.
T_WARN=7; T_CRIT=14

SEC_N=0; JDATE=""; JDAYS=-1; CRUISE_D=-1

# --- Poste ---
# Le nom que le journal écrit dans le champ `poste` de ses événements : `lib_poste.nom_poste` quand
# le moteur le porte, le nom réseau à défaut. Jamais déduit d'un chemin ni de la dernière séance.
POSTE_LIGNE=$(python3 - "$SELF" 2>/dev/null <<'PYPOSTE'
import socket, sys
sys.path.insert(0, sys.argv[1])
try:
    from lib_poste import nom_poste
    print(nom_poste())
except Exception:
    print(socket.gethostname())
PYPOSTE
)
[ -n "$POSTE_LIGNE" ] || POSTE_LIGNE="illisible"

# --- Écart git de chaque dépôt ---
# « En retard » veut dire : des commits distants que ce poste n'a pas encore tirés.
BEHIND=0
# État de synchro PAR DÉPÔT, lu par l'en-tête du bilan : lignes `chemin|état|provenance du fetch`,
# provenance vide quand le fetch est celui de ce démarrage.
SYNC_DEPOTS=""
# MULTIPOSTE=non (`reglages/REPONSES`) : un seul poste écrit ces dépôts, la sonde de retard n'a rien
# à trouver et coûte un `fetch` réseau par dépôt à chaque démarrage. Elle se saute, et la ligne de
# synchro le dit. Clé absente : elle tourne, poste non réglé.
_SONDE_RETARD=1
[ "$(claudeos_reponse MULTIPOSTE 2>/dev/null)" = "non" ] && _SONDE_RETARD=0
# FETCH RÉCENT RÉUTILISÉ : le lanceur (`claudeos-session.sh`, avant d'ouvrir la session) fetch juste
# avant. Un `FETCH_HEAD` NON VIDE de moins de FETCH_FRAIS_S secondes tient lieu de fetch, et son âge
# se dit dans la ligne de synchro. NON VIDE : un fetch en échec vide ce fichier tout en le datant,
# son âge passerait pour une mesure.
FETCH_FRAIS_S=300
_fetch_age() {
    local f="$1/.git/FETCH_HEAD" m
    [ -s "$f" ] || return 1
    # `stat -c` est GNU, `stat -f %m` BSD : le premier qui rend un entier gagne.
    m=$(stat -c %Y "$f" 2>/dev/null) || m=$(stat -f %m "$f" 2>/dev/null) || return 1
    case "$m" in ''|*[!0-9]*) return 1 ;; esac
    echo $(( $(date +%s) - m ))
}
# LE RETARD SE MESURE OU SE DIT NON MESURÉ : hors ligne, jeton expiré, HEAD détachée ou rebase
# interrompu, un dépôt qu'on n'a PAS PU regarder ne s'affiche jamais « à jour » — pas de
# conclusion portée par une branche d'erreur (`controles-et-alarmes`).
# _ecart <dépôt> <étiquette> <code du fetch, ou « - » sonde sautée> <provenance> : verdict d'UN dépôt.
_ecart() {
    local repo="$1" nom="$2" rc="$3" pv="$4" behind dirty v
    if [ "$rc" = "-" ]; then
        :
    elif [ "$rc" -ne 0 ]; then
        OUT="${OUT}⚠️ Dépôt ${nom} : distant injoignable (hors ligne ou accès refusé) — son retard N'A PAS été mesuré ; ne clôture pas d'ici avant d'avoir tiré."$'\n'
        SYNC_DEPOTS="${SYNC_DEPOTS}${repo}|${nom} : retard non mesuré (fetch impossible)|${pv}"$'\n'
    elif behind=$(git -C "$repo" rev-list --count HEAD..@{u} 2>/dev/null); then
        BEHIND=$(( BEHIND + behind ))
        if [ "$behind" -gt 0 ]; then
            # Le motif vient de la fonction qui a décidé au lancement : le bilan ne recopie pas
            # sa logique, il la rappelle sur l'état courant.
            v=$(claudeos_verdict_pull "$repo" "$MOI")
            case "$v" in
                TIRER*) OUT="${OUT}⚠️ Dépôt ${nom} en retard de ${behind} commit(s), non tiré par le lanceur ; il se tire sans risque par : git -C ${repo/#$HOME/$CLAUDEOS_TILDE} pull --rebase --autostash"$'\n'
                        SYNC_DEPOTS="${SYNC_DEPOTS}${repo}|${nom} : en retard de ${behind}, tirable sans risque|${pv}"$'\n' ;;
                *)      OUT="${OUT}⛔ Dépôt ${nom} en retard de ${behind} commit(s), non tiré : ${v#*|}."$'\n'
                        SYNC_DEPOTS="${SYNC_DEPOTS}${repo}|${nom} : en retard de ${behind}, non tiré — ${v#*|}|${pv}"$'\n' ;;
            esac
        else
            SYNC_DEPOTS="${SYNC_DEPOTS}${repo}|${nom} : à jour|${pv}"$'\n'
        fi
    else
        OUT="${OUT}⚠️ Dépôt ${nom} : retard illisible — HEAD détachée, rebase interrompu ou branche sans amont. Regarder : git -C ${repo/#$HOME/$CLAUDEOS_TILDE} status"$'\n'
        SYNC_DEPOTS="${SYNC_DEPOTS}${repo}|${nom} : retard illisible|${pv}"$'\n'
    fi
    dirty=$(git -C "$repo" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    [ "$dirty" -gt 0 ] && OUT="${OUT}• ${dirty} fichier(s) non commité(s) dans le dépôt ${nom}"$'\n'
    return 0
}
# La liste vient de `claudeos_repos`, vide sans git. Étiquette : « système » pour `~/.claude`, le
# chemin abrégé par le tilde pour les autres. LES FETCH PARTENT ENSEMBLE, les verdicts se rendent
# ensuite dans l'ordre de la liste : en série, les fetch additionnent leurs allers-retours réseau.
# En portée projet, seul le dépôt qui porte le niveau est regardé, le seul que son bilan rend ;
# chemins comparés résolus, les racines peuvent être des liens.
_rp=$(cd "$_proj" 2>/dev/null && pwd -P)
_DR=(); _DN=(); _DP=(); _DV=(); _FN=0; _FR=0; _FAMAX=0
while IFS= read -r _d; do
    [ -n "$_d" ] && [ -d "$_d/.git" ] || continue
    [ -n "$(git -C "$_d" remote 2>/dev/null)" ] || continue
    if [ "${CLAUDEOS_SESSION_SCOPE:-}" = "projet" ]; then
        _rr=$(cd "$_d" 2>/dev/null && pwd -P)
        case "$_rp/" in "$_rr"/*) ;; *) continue ;; esac
    fi
    _DR+=("$_d")
    if [ "$_d" = "$HOME/.claude" ]; then _DN+=("système"); else _DN+=("${_d/#$HOME/$CLAUDEOS_TILDE}"); fi
    if [ "$_SONDE_RETARD" = 0 ]; then
        _DP+=("-"); _DV+=("")
    elif _a=$(_fetch_age "$_d") && [ "$_a" -le "$FETCH_FRAIS_S" ]; then
        _DP+=(""); _DV+=("fetch réutilisé, fait il y a ${_a} s")
        _FR=$((_FR + 1)); [ "$_a" -gt "$_FAMAX" ] && _FAMAX=$_a
    else
        git -C "$_d" fetch --quiet 2>/dev/null &
        _DP+=("$!"); _DV+=(""); _FN=$((_FN + 1))
    fi
done < <(claudeos_repos)
_i=0
while [ "$_i" -lt "${#_DR[@]}" ]; do
    _rc=0
    case "${_DP[$_i]}" in
        -)  _rc="-" ;;
        "") ;;
        *)  wait "${_DP[$_i]}"; _rc=$? ;;
    esac
    _ecart "${_DR[$_i]}" "${_DN[$_i]}" "$_rc" "${_DV[$_i]}"
    _i=$((_i + 1))
done
# Poste en retard = fichiers vivants périmés. Les signaux actionnables composés plus bas
# sont lus sur ces fichiers, donc possiblement déjà traités sur l'autre poste — les marquer
# non fiables SANS les taire. La dette de sécurité n'est pas atténuée : elle sort toujours.
[ "$BEHIND" -gt 0 ] && OUT="${OUT}   ↳ NON synchronisé : les signaux ci-dessous sont lus sur des fichiers en retard, ils peuvent déjà être traités sur un autre poste ; la dette de sécurité vaut dans tous les cas."$'\n'

# --- Dette de sécurité : secrets compromis / à régénérer (jamais de valeur — compétence secrets-detail) ---
SECDEBT="$MEM/SECURITY_DEBT.md"
if [ -f "$SECDEBT" ]; then
    SEC_N=$(awk '/^## /{n++} END{print n+0}' "$SECDEBT" 2>/dev/null || echo 0)
    [ "$SEC_N" -gt 0 ] && OUT="${OUT}🔐 ${SEC_N} secret(s) compromis / à régénérer en attente ($SECDEBT)"$'\n'
fi

# --- Rappels datés (échéances déclenchées à date — REMINDERS.md) ---
# Lignes actives : "- YYYY-MM-DD | texte". Surfacée quand la date d'échéance est atteinte
# (aujourd'hui ou passée). LECTURE SEULE : l'assistant purge la ligne une fois traitée.
# Pas de paliers d'ancienneté : le retard est dit en clair, et c'est la CONDUITE qui traite le
# rappel (compétence `demarrage`).
REMINDERS="$MEM/REMINDERS.md"
REMINDER_N=0
# Rappels échus en clair, `date|retard|texte` par ligne : la session de projet n'affiche que ceux
# dont l'étiquette nomme son niveau.
REM_ECHUS=""
# LIGNE TOUJOURS PRÉSENTE : « N lus, M échus » distingue « aucun rappel échu » de « fichier non lu ».
# Une ligne DATÉE hors format crie. Un fichier absent se dit sans alarme : il naît au premier rappel
# posé, et une installation qui n'en a jamais posé n'a rien à lire.
REM_LUS=0
REM_HORS=""
REM_LIGNE=""
if [ ! -f "$REMINDERS" ]; then
    REM_LIGNE="Rappels : aucun — ${REMINDERS/#$HOME/~} n'existe pas encore."
else
    NOW_TS=$(date +%s)
    _rn=0
    # `|| [ -n "$rline" ]` : sans lui, un fichier sans retour à la ligne final perd sa
    # DERNIÈRE ligne — donc le rappel le plus récemment ajouté.
    while IFS= read -r rline || [ -n "$rline" ]; do
        _rn=$((_rn + 1))
        rdate=$(printf '%s' "$rline" | grep -oE '^- [0-9]{4}-[0-9]{2}-[0-9]{2}' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
        if [ -z "$rdate" ]; then
            # Une ligne qui RESSEMBLE à un rappel — puce, case, gras ou retrait devant une date — et
            # que le format strict refuse. Les citations (`>`) et les titres n'en sont pas.
            if printf '%s' "$rline" | grep -qE '^[[:space:]]*([-*+]|[0-9]{1,2}[/.])?[[:space:]]*(\[.\][[:space:]]*)?\**[[:space:]]*([0-9]{4}[-/][0-9]{2}[-/][0-9]{2}|[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4})'; then
                REM_HORS="${REM_HORS}${REM_HORS:+, }${_rn}"
            fi
            continue
        fi
        REM_LUS=$((REM_LUS + 1))
        # Voir claudeos_epoch_of_date dans config.sh : un échec de conversion se DIT, il ne rend
        # pas 0 en escamotant le rappel.
        rts=$(claudeos_epoch_of_date "$rdate" || true)
        if [ -z "$rts" ]; then
            OUT="${OUT}⚠️ Rappel du ${rdate} NON ÉVALUÉ — date illisible par \`date -d\` comme par python3. Le rappel existe et n'est PAS affiché ci-dessus."$'\n'
            continue
        fi
        if [ "$rts" -gt 0 ] && [ "$rts" -le "$NOW_TS" ]; then
            rtext=$(printf '%s' "$rline" | sed -E 's/^- [0-9]{4}-[0-9]{2}-[0-9]{2} *\| *//')
            # Borne d'affichage : le texte entier reste dans le fichier, le bloc n'en porte que le
            # début — dix rappels longs dépassaient à eux seuls la borne d'injection.
            [ "${#rtext}" -gt 300 ] && rtext="${rtext:0:297}… (suite dans REMINDERS.md)"
            rlate=$(( (NOW_TS - rts) / 86400 ))
            REMINDER_N=$((REMINDER_N + 1))
            OUT="${OUT}⏰ Rappel du ${rdate}"
            [ "$rlate" -gt 0 ] && OUT="${OUT} (en retard de ${rlate} j)"
            OUT="${OUT} — ${rtext}"$'\n'
            REM_ECHUS="${REM_ECHUS}${rdate}|${rlate}|${rtext}"$'\n'
        fi
    done < "$REMINDERS"
    [ -n "$REM_HORS" ] && OUT="${OUT}⚠️ REMINDERS.md : ligne(s) ${REM_HORS} datée(s) hors du format « - AAAA-MM-JJ | texte », NON évaluées."$'\n'
    REM_LIGNE="Rappels : ${REM_LUS} lu(s), ${REMINDER_N} échu(s)."
fi

# _seances <mode> <args> : la SEULE lecture des événements `seance` d'un journal, trois vues.
#   systeme <racine>        date la plus récente, puis la dernière principale DE CE POSTE (ligne,
#                           PROCHAIN, horodatage), puis les principales des autres postes après elle
#   projets <engine> <ts> <CRENEAUX> <jour>  par niveau : séances après <ts>, ou dernière séance de
#                           moins de 7 j d'un niveau proposable aujourd'hui ; huit au plus
#   niveau <dossier>        dernière séance du niveau, avec son âge, puis son PROCHAIN
# Le « PROCHAIN : » est EXTRAIT sur sa dernière occurrence, et coupé à 300 caractères (250 par
# niveau de projet) : la règle d'écriture, `reprise`, le veut en une phrase sous 250.
_seances() {
    python3 - "$@" 2>/dev/null <<'PYSEANCES'
import datetime, glob, json, os, re, socket, sys

def seances(niv):
    for f in sorted(glob.glob(os.path.join(niv, "journal", "*.jsonl"))):
        try:
            fh = open(f, encoding="utf-8")
        except OSError:
            continue
        with fh:
            for l in fh:
                try:
                    e = json.loads(l)
                except ValueError:
                    continue
                if isinstance(e, dict) and e.get("type") == "seance" and len(str(e.get("ts", ""))) >= 10:
                    e["ts"] = str(e["ts"])
                    yield e

def parts(e):
    # La DERNIÈRE occurrence : un « PROCHAIN : » cité en cours de récit avalait tout ce qui suit.
    t = " ".join(str(e.get("texte", "")).split())
    ms = list(re.finditer(r"PROCHAIN\s*:\s*", t))
    return (t[:ms[-1].start()].strip(), t[ms[-1].end():].strip()) if ms else (t, "")

def coupe(s, n):
    return s[:n - 3].rsplit(" ", 1)[0] + "…" if len(s) > n else s

def quand(e):
    return f"{e['ts'][:16].replace('T', ' ')} · {e.get('poste', '?')}"

mode = sys.argv[1]
if mode == "systeme":
    # Ligne 1, la date la plus récente TOUS POSTES : elle mesure seule l'âge du journal. Lignes 2 à
    # 4, la dernière principale de CE POSTE — sur plusieurs postes, la dernière tout court est
    # souvent celle d'un autre, et cacherait la séance d'ici. Au-delà, les principales des autres
    # postes écrites après elle, une ligne chacune. Le poste se nomme comme le journal l'écrit.
    evs = list(seances(sys.argv[2]))
    if evs:
        sys.path.insert(0, os.path.join(sys.argv[2], "engine"))
        try:
            from lib_poste import nom_poste
            ici = nom_poste()
        except Exception:
            ici = socket.gethostname()
        g = max(evs, key=lambda e: e["ts"])
        mien = [e for e in evs if e.get("poste") == ici]
        e = max(mien, key=lambda e: e["ts"]) if mien else g
        t, p = parts(e)
        print(g["ts"][:10]); print(f"{quand(e)} — {coupe(t, 400)}"); print(coupe(p, 300)); print(e["ts"])
        for o in sorted((x for x in evs if x["ts"] > e["ts"]), key=lambda x: x["ts"]):
            t2, p2 = parts(o)
            print(f"  {quand(o)} — " + (f"PROCHAIN : {coupe(p2, 300)}" if p2 else coupe(t2, 300)))
elif mode == "niveau":
    evs = list(seances(sys.argv[2]))
    if evs:
        e = max(evs, key=lambda e: e["ts"])
        t, p = parts(e)
        try:
            age = (datetime.date.today() - datetime.date.fromisoformat(e["ts"][:10])).days
        except ValueError:
            age = -1
        print(f"{quand(e)} · il y a {age} j — {coupe(t, 400)}")
        print(f"PROCHAIN : {coupe(p, 250)}" if p
              else "PROCHAIN : non écrit dans l'entrée de séance.")
elif mode == "projets":
    # Deux raisons d'entrer, une ligne par niveau : une séance écrite APRÈS l'ancre (la dernière
    # principale de ce poste), ou un niveau PROPOSABLE aujourd'hui dont la dernière séance a moins de
    # 7 jours. La première seule était vide par construction : la principale clôt la journée.
    sys.path.insert(0, sys.argv[2]); jts = sys.argv[3]
    import etat
    from lib_creneaux import parse_creneaux
    cren = parse_creneaux(sys.argv[4]) if len(sys.argv) > 5 else {}
    dow = int(sys.argv[5]) - 1 if len(sys.argv) > 5 else -1
    ouverts = {w for w, d in cren.items() if dow in d}
    fermes = {w for w in cren if w not in ouverts}
    racine_sys = os.path.realpath(os.path.expanduser("~/.claude"))
    borne = (datetime.date.today() - datetime.timedelta(days=7)).isoformat()
    lignes = []
    for niv in etat.niveaux_tous():
        if os.path.realpath(niv) == racine_sys:
            continue
        dom = os.path.basename(etat.racine_depot(niv))
        propo = (dom in ouverts) if ouverts else (dom not in fermes)
        tout = list(seances(niv))
        if not tout:
            continue
        d = max(tout, key=lambda e: e["ts"])
        apres = [e for e in tout if e["ts"] > jts]
        if not apres and not (propo and d["ts"][:10] >= borne):
            continue
        t, p = parts(d)
        r = ("PROCHAIN : " + coupe(p, 250)) if p else coupe(t, 200)
        n = f" ×{len(apres)} depuis" if len(apres) > 1 else ""
        lignes.append((d["ts"], f"  {os.path.basename(niv)}{n} — {d['ts'][:16].replace('T', ' ')} ({d.get('poste', '?')}) : {r}"))
    lignes.sort(reverse=True)
    for _, l in lignes[:8]:
        print(l)
    if len(lignes) > 8:
        print(f"  … et {len(lignes) - 8} autre(s) niveau(x).")
    # Sentinelle : une sortie VIDE ne peut plus vouloir dire « aucune » — elle veut dire panne.
    if not lignes:
        print("AUCUNE")
PYSEANCES
}

HEURE=$(date '+%Y-%m-%d %H:%M')

# =============================================================================
# SORTIE D'UNE SESSION DE PROJET — rendue ici, avant ce que seule la principale affiche
# =============================================================================
# Le bilan de projet ne porte ni les alertes, ni la croisière, ni les fils des autres niveaux :
# tout ce qui suit ce bloc ne sert qu'à la principale. Les consignes de rendu, des deux portées,
# sont dans `skills/demarrage/SKILL.md`. `BILAN_DEMARRAGE` ne la touche pas : la question de
# l'entretien porte sur la session principale.
if [ "${CLAUDEOS_SESSION_SCOPE:-}" = "projet" ]; then
    _SEC=""
    [ "$SEC_N" -gt 0 ] && _SEC="🔐 ${SEC_N} secret(s) compromis ou à régénérer en attente (dette de sécurité du système, ${SECDEBT})."
    # Synchro du SEUL dépôt qui porte le niveau : la boucle des écarts n'a regardé que lui.
    SYNC_NIV=""
    while IFS='|' read -r _r _st _pv; do
        [ -n "$_r" ] && SYNC_NIV="${_st}${_pv:+ (${_pv})}"
    done <<< "$SYNC_DEPOTS"
    if [ -z "$SYNC_NIV" ]; then
        if [ "$(claudeos_regime)" = aucun ]; then SYNC_NIV="sans objet, régime sans git"
        elif [ "$_SONDE_RETARD" = 0 ]; then SYNC_NIV="retard non sondé, un seul poste (MULTIPOSTE=non)"
        fi
    fi
    # Dernière séance DU NIVEAU, avec son âge : la compétence pose « qu'est-ce qui a bougé ? » au-delà
    # de sept jours seulement : une reprise plus récente est rarement périmée.
    SEANCE_NIV=$(_seances niveau "$_proj")
    # Rappels échus dont l'ÉTIQUETTE nomme le niveau : chaque mot de l'étiquette (avant le premier
    # « — ») doit figurer dans le chemin du niveau. « ATELIER » → <DOMAINE>/ATELIER ; « <DOMAINE>
    # ATELIER » → le même niveau, plus étroitement ; « SYSTÈME » → aucun niveau de projet.
    REM_NIV=$(python3 - "$_lvl" "$REM_ECHUS" 2>/dev/null <<'PYREM'
import sys
lvl = sys.argv[1].upper()
for l in sys.argv[2].splitlines():
    try:
        date, retard, texte = l.split("|", 2)
    except ValueError:
        continue
    mots = texte.split(" — ", 1)[0].replace("*", "").split()
    if mots and all(m.upper() in lvl for m in mots):
        print(f"⏰ Rappel du {date}" + (f" (en retard de {retard} j)" if retard != "0" else "") + f" — {texte}")
PYREM
)
    # Composés ICI et non coupés au caractère : une coupe brute perdait le pied — comptes et
    # porteurs — et les fils les plus récents. Pied d'abord, puis 👤, l'assistant, sans porteur,
    # par âge ; les ⏳ sur une ligne ; coupe par fil entier, qui dit combien restent. Les marqueurs
    # viennent de `etat.PORTEURS`, jamais recopiés ici.
    # Un rappel que la principale ne sait pas lire ne se tait pas non plus ici.
    REM_ALERTE=$(printf '%s' "$OUT" | grep -E '^⚠️ (Rappel|REMINDERS)' || true)
    FILS_NIV=$(python3 - "$_proj" 2>/dev/null <<'PYFILS'
import json, os, re, subprocess, sys
E = os.path.expanduser("~/.claude/engine/etat.py")
sys.path.insert(0, os.path.dirname(E))
try:
    from etat import PORTEURS
    M = dict(PORTEURS)
except Exception:
    M = {"utilisateur": "👤", "tiers": "⏳"}
niv = sys.argv[1]
j = subprocess.run([sys.executable, E, "fils", "--niveau", niv, "--json"], capture_output=True, text=True)
t = subprocess.run([sys.executable, E, "fils", "--niveau", niv], capture_output=True, text=True)
dus = json.loads(j.stdout) if j.returncode == 0 and j.stdout.strip() else None
if not isinstance(dus, list):
    sys.exit(1)
textes = {}
L = t.stdout.splitlines()
for i, l in enumerate(L):
    m = re.match(r"^\[([^\]]+)\] (\S+) · (.*?) · (\S+)$", l)
    if m and i + 1 < len(L) and L[i + 1].startswith("    "):
        textes[m.group(4)] = (m.group(1), L[i + 1].strip())
actifs = [d for d in dus if not d.get("dormant")]
if not dus:
    print("Aucun dû ouvert.")
    sys.exit(0)
c = {}
for d in actifs:
    c[d.get("porteur")] = c.get(d.get("porteur"), 0) + 1
print(f"{len(dus)} dû(s) ouvert(s), {len(actifs)} actif(s) — "
      + " · ".join(f"{M.get(k, '❔')} {c[k]}" for k in [*M, None] if c.get(k))
      + (f" ; {len(dus) - len(actifs)} dormant(s), etat.py fils --niveau <niveau> --dormants" if len(dus) > len(actifs) else ""))
def rang(p):
    return 0 if p == "utilisateur" else (1 if p in M else 2)
vifs = sorted((d for d in actifs if d.get("porteur") != "tiers"),
              key=lambda d: (rang(d.get("porteur")), -d["age"]))
taille, n = 0, 0
for d in vifs:
    age, txt = textes.get(d["ref"], (f"{d['age']} j", ""))
    l = f"  [{age}] {d['ref']} — {txt[:150]}" if txt else f"  [{age}] {d['ref']} {M.get(d.get('porteur'), '❔')}"
    if taille + len(l) > 2800:
        break
    print(l); taille += len(l); n += 1
if n < len(vifs):
    print(f"  … et {len(vifs) - n} autre(s) — etat.py fils --niveau <niveau>")
att = sorted((d for d in actifs if d.get("porteur") == "tiers"), key=lambda d: -d["age"])
if att:
    print(f"  ⏳ en attente ({len(att)}) : " + ", ".join(f"{d['ref']} ({textes.get(d['ref'], (str(d['age']) + ' j',))[0]})" for d in att))
PYFILS
)
    # Échéance du tri hebdomadaire des fils. Le calcul et son seuil vivent dans engine/lib_tri.py,
    # source unique lue aussi par la passe mensuelle ; la compétence `tri-des-fils` écrit les
    # événements qu'il lit. Toute erreur se dit dans la ligne, jamais en vert.
    TRI_NIV=$(python3 - "$_proj" 2>&1 <<'PYTRI'
import os, subprocess, sys, json
sys.path.insert(0, os.path.expanduser("~/.claude/engine"))
try:
    from lib_tri import SEUIL_TRI_JOURS, SEUIL_RECONDUIT, derniers, age, reconduits
    niv = sys.argv[1]
    if not os.path.isfile(os.path.join(niv, "ETAT.md")):
        print("Tri des fils : sans objet, ce dossier ne porte pas d'ETAT.md.")
        sys.exit()
    tri, rep = derniers(niv)
    r = subprocess.run([sys.executable, os.path.expanduser("~/.claude/engine/etat.py"),
                        "fils", "--niveau", niv, "--json"], capture_output=True, text=True, timeout=30)
    dus = json.loads(r.stdout) if r.returncode == 0 else None
    if not isinstance(dus, list):
        print(f"Tri des fils : comptage des dus indisponible (etat.py fils rc={r.returncode} : {r.stderr.strip()[:160]}).")
        sys.exit()
    dorm = sum(1 for d in dus if d.get("dormant"))
    ref = max(x for x in (tri, rep, "") if x is not None) or None   # un report repousse aussi l'échéance
    quand = (f"dernier tri le {tri}" if tri else "aucun tri complet consigné") \
        + (f", report le {rep}" if rep and (not tri or rep > tri) else "")
    if not dus:
        print(f"Tri des fils : rien à trier, aucun dû ouvert ({quand}).")
    elif ref is None or age(ref) > SEUIL_TRI_JOURS:
        print(f"Tri des fils : DÛ — {quand} ; {len(dus)} dû(s) ouvert(s), dont {dorm} dormant(s). Compétence `tri-des-fils`.")
    else:
        print(f"Tri des fils : à jour — {quand}, il y a {age(ref)} j.")
    rec = reconduits(niv)
    trop = sorted(d["ref"] for d in dus if rec.get(d.get("ref"), 0) >= SEUIL_RECONDUIT)
    if trop:   # un fil tenu à trois tris : on attaque l'obstacle
        print(f"Fils tenus à {SEUIL_RECONDUIT} tris ou plus : {', '.join(trop)} — nommer l'obstacle, compétence `session`.")
except Exception as exc:   # jamais de faux vert : l'échec se dit, avec sa cause
    print(f"Tri des fils : échéance non mesurée ({type(exc).__name__} : {str(exc)[:160]}).")
PYTRI
)
    # Plafond de l'état du niveau : UNE ligne, sans chiffre ni consigne, et seulement au-dessus.
    # Même borne que plafonds-parc.sh et le crochet (claudeos_plafond_de, config.sh), même mesure
    # nette (commentaires HTML exclus). La principale ne l'affiche pas. Un échec de mesure se dit,
    # il ne se tait pas. La racine se résout par `etat.racine_depot`, avec ou sans git.
    PLAF_NIV=$(
        _f="$_proj/ETAT.md"
        [ -f "$_f" ] || exit 0
        _rel="$(python3 -c 'import os,sys;sys.path.insert(0,sys.argv[3]);import etat;r=os.path.realpath(etat.racine_depot(sys.argv[1]));f=os.path.realpath(sys.argv[2]);print(os.path.basename(r)+"/"+os.path.relpath(f,r))' "$_proj" "$_f" "$SELF" 2>/dev/null)" \
            || { echo "Plafond de l'état : non mesuré (racine du niveau introuvable)."; exit 0; }
        _p="$(claudeos_plafond_de "$_rel")" || exit 0   # hors régime : pas de plafond, rien à dire
        _net="$(python3 -c "import re,sys;print(len(re.sub(r'<!--.*?-->','',open(sys.argv[1],encoding='utf-8').read(),flags=re.S)))" "$_f")" \
            || { echo "Plafond de l'état : non mesuré (ETAT.md illisible)."; exit 0; }
        [ "$_net" -gt "$_p" ] && echo "Plafond de l'état : ETAT.md au-dessus de son plafond (bash ~/.claude/engine/plafonds-parc.sh)."
        exit 0
    )
    _emet "${INACH}=== ClaudeOS — démarrage d'une session de PROJET : ${_lvl} · ${HEURE} ===
Données mesurées à cette heure. Le bilan se rend par la compétence \`/demarrage\`.
Poste : ${POSTE_LIGNE}
Synchro du dépôt du niveau : ${SYNC_NIV:-non mesurée}
${_SEC}
--- FAIT LA DERNIÈRE FOIS ---
${SEANCE_NIV:-Aucune séance consignée au journal du niveau.}

--- RAPPELS ÉCHUS QUI NOMMENT CE NIVEAU ---
${REM_NIV:-aucun}
${REM_ALERTE}
(REMINDERS.md appartient à la principale : ces rappels s'affichent ici et se traitent là-bas.)

--- FILS OUVERTS DU NIVEAU ---
${FILS_NIV:-Fils : vue indisponible — python3 ~/.claude/engine/etat.py fils --niveau ${_proj}}
${TRI_NIV:-Tri des fils : échéance non mesurée.}
${PLAF_NIV}

--- GARDE-FOUS ---
${GARDEFOUS}
Reprise du niveau : son ETAT.md et son journal \`journal/*.jsonl\`."
    exit 0
fi

# --- Compteur de convergence. LECTURE SEULE. ---
# Croisière = 28 jours consécutifs sans chantier moteur ni chantier de règles. Le compteur
# rend la condition d'arrêt VISIBLE : sans lui, « le système est-il fini ? » ne se pose
# jamais, et l'amélioration devient indéfinie.
# Périmètre : `engine/`, `CLAUDE.md` et les fiches système (`CLAUDEOS_FICHES_SYSTEME`, config.sh).
# `--invert-grep` écarte les réparations : un message commençant par `incident:` ne remet pas le
# compteur à zéro, c'est ce qui distingue un système qui se répare d'un système qu'on refait.
if [ -d "$ROOT/.git" ]; then
    _FICHES=""
    for _fs in ${CLAUDEOS_FICHES_SYSTEME:-}; do _FICHES="${_FICHES} skills/${_fs}"; done
    # shellcheck disable=SC2086
    CRUISE_TS=$(git -C "$ROOT" log -1 --format='%ct' --invert-grep --regexp-ignore-case \
        --grep='^incident:' -- engine CLAUDE.md ${_FICHES} 2>/dev/null)
    if [ -n "${CRUISE_TS:-}" ] && [ "$CRUISE_TS" -gt 0 ] 2>/dev/null; then
        CRUISE_D=$(( ( $(date +%s) - CRUISE_TS ) / 86400 ))
    fi
fi

# --- Audit du système dû ? (cadence mensuelle, lecture seule) ---
# Le CONTENU du système n'est vérifié que par la passe mensuelle `os-audit`, sans déclencheur
# propre : sans ce rappel elle ne tournerait jamais.
AUDIT_DIR="$HOME/.claude/audits"
# LA DATE SEULE, jamais un suffixe (`os-audit-AAAA-MM-JJ-<poste>.md`) : un suffixe trie en dernier et
# ne se convertit pas. Une ligne sans date ISO est ignorée plutôt que mal mesurée.
AUDIT_LAST=$(ls -1 "$AUDIT_DIR"/os-audit-*.md 2>/dev/null \
    | sed -nE 's/.*os-audit-([0-9]{4}-[0-9]{2}-[0-9]{2}).*\.md$/\1/p' | sort | tail -1)
if [ -z "$AUDIT_LAST" ]; then
    OUT="${OUT}🔍 Audit du système jamais lancé — « os audit » pour vérifier que la carte dit encore vrai."$'\n'
else
    # Un repli `|| date +%s` rendrait 0 jour : l'audit ne serait jamais dû sur un poste sans `date -d`.
    _audit_ts=$(claudeos_epoch_of_date "$AUDIT_LAST" || true)
    if [ -z "$_audit_ts" ]; then
        AUDIT_DAYS=-1
        OUT="${OUT}⚠️ Ancienneté de l'audit NON MESURÉE — date « ${AUDIT_LAST} » illisible. Ne pas lire l'absence d'alerte d'audit comme un audit récent."$'\n'
    else
        AUDIT_DAYS=$(( ( $(date +%s) - _audit_ts ) / 86400 ))
    fi
    # Seuil à 30 jours : un rappel toujours allumé est un rappel éteint. Le message dit
    # l'ANCIENNETÉ dans son unité, pas « en retard ».
    if [ "$AUDIT_DAYS" -gt 30 ]; then
        OUT="${OUT}🔍 Audit du système non lancé depuis ${AUDIT_DAYS} j (dernier : ${AUDIT_LAST}) — « os audit »."$'\n'
    fi
fi

# --- Auto-diagnostic de la plomberie (« fail loud ») ---
# Le système doit signaler quand SA PROPRE machinerie casse, plutôt que d'échouer en silence.
# L'état se lit directement dans git, qui est la source et non une trace laissée par un script.

# Dépendance dure : git. Sans lui, tout ce qui précède est muet. EN RÉGIME GITHUB SEULEMENT : sans
# git (`GIT=aucun`), son absence est le choix de l'installateur, pas une panne à signaler.
if [ "$(claudeos_regime)" != aucun ] && ! command -v git >/dev/null 2>&1; then
    OUT="${OUT}⚠️ git introuvable — la sauvegarde et la détection d'écart sont désactivées"$'\n'
fi

# Verdict de sauvegarde = l'état réel de chaque dépôt, pas le récit d'un journal.
# Trois choses peuvent clocher, et chacune se mesure : des commits jamais poussés, un
# arbre sale, un dépôt sans nouveau commit depuis longtemps (la clôture ne tourne plus).
_verdict_depot() {
    local repo="$1" nom="$2" ahead age ts
    [ -d "$repo/.git" ] || return 0
    # UN REBASE OU UNE FUSION EN COURS, OU UNE HEAD DÉTACHÉE, SE DISENT (`claudeos_en_suspens`,
    # lib_regime.sh) : `rev-list @{u}..HEAD` y rend 128, qu'un `|| echo 0` changerait en « rien à
    # pousser » — « sauvegardé » d'un dépôt qui ne pousse plus rien.
    if claudeos_en_suspens "$repo"; then
        OUT="${OUT}⛔ Dépôt ${nom} : un rebase ou une fusion est en cours, ou HEAD est détachée — rien de ce poste n'est poussé. git -C ${repo/#$HOME/$CLAUDEOS_TILDE} status, puis termine-le ou annule-le."$'\n'
    elif [ -n "$(git -C "$repo" remote 2>/dev/null)" ]; then
        if ahead="$(git -C "$repo" rev-list --count @{u}..HEAD 2>/dev/null)"; then
            if [ "$ahead" -gt 0 ]; then
                OUT="${OUT}⚠️ Dépôt ${nom} : ${ahead} commit(s) JAMAIS POUSSÉ(S) — ils n'existent que sur ce poste ; la clôture (bash ~/.claude/engine/claudeos-cloture.sh) les pousse."$'\n'
            fi
        else
            OUT="${OUT}⚠️ Dépôt ${nom} : avance sur le distant illisible (branche sans amont ?) — la sauvegarde n'a pas pu être vérifiée."$'\n'
        fi
    fi
    # L'ÂGE NE SONNE QUE SUR UN ARBRE SALE : un dépôt propre et poussé n'a rien à sauvegarder, même
    # inactif depuis des semaines. Ce que l'âge cherche — une clôture qui ne tourne plus — laisse
    # des changements non commités, et c'est là seulement qu'il mord.
    ts="$(git -C "$repo" log -1 --format=%ct 2>/dev/null || echo 0)"
    if [ "${ts:-0}" -gt 0 ]; then
        age=$(( ( $(date +%s) - ts ) / 86400 ))
        if [ "$age" -gt 7 ] && [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then
            OUT="${OUT}⚠️ Dépôt ${nom} : des changements non commités, et aucun commit depuis ${age}j — clôture oubliée ? bash ~/.claude/engine/claudeos-cloture.sh"$'\n'
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
# sinon une levée sur un dépôt de domaine ne serait jamais rapportée au démarrage.
# Sans git, le crochet l'écrit sous le `.claudeos/` de la racine : il n'y a pas de `.git/`.
for _alog in $(claudeos_repos | sed 's|$|/.git/ALARMES_FORCEES.log|') "$ROOT/.claudeos/ALARMES_FORCEES.log"; do
    [ -s "$_alog" ] || continue
    _aday="$(tail -1 "$_alog" | cut -d' ' -f1)"
    [ "$_aday" = "$(date '+%Y-%m-%d')" ] || continue
    OUT="${OUT}🔓 Alarme(s) levée(s) aujourd'hui sur ${_alog#$HOME/} — l'alarme correspondante ne s'est pas exprimée. Vérifier que le motif tient toujours."$'\n'
done

# Journal de session périmé ? Date MAXIMALE des événements `seance` de journal/*.jsonl, quel que
# soit l'ordre d'insertion. JLINE sort du même événement : deux sources afficheraient la date
# d'une séance et le résumé d'une autre.
_JRAW=$(_seances systeme "$ROOT" || true)
JDATE=$(printf '%s\n' "$_JRAW" | sed -n 1p)
JLINE=$(printf '%s\n' "$_JRAW" | sed -n 2p)
JPROCHAIN=$(printf '%s\n' "$_JRAW" | sed -n 3p)
JTS=$(printf '%s\n' "$_JRAW" | sed -n 4p)
JAUTRES=$(printf '%s\n' "$_JRAW" | sed -n '5,$p')
if [ -n "$JDATE" ]; then
    # Même règle que l'audit : une date illisible se dit, elle ne rend pas 0 jour.
    _j_ts=$(claudeos_epoch_of_date "$JDATE" || true)
    if [ -z "$_j_ts" ]; then
        DAYS=-1
        OUT="${OUT}⚠️ Ancienneté du journal NON MESURÉE — date « ${JDATE} » illisible. Ne pas lire l'absence d'alerte comme un journal frais."$'\n'
    else
        DAYS=$(( ( $(date +%s) - _j_ts ) / 86400 ))
    fi
    JDAYS=$DAYS
    if [ "$DAYS" -gt "$T_CRIT" ]; then
        OUT="${OUT}⚠️ Journal périmé (dernière entrée ${JDATE}, il y a ${DAYS}j > ${T_CRIT}) — le rituel de clôture ne tourne peut-être plus"$'\n'
    fi
fi

# --- Séance non clôturée ? (filet) ---
# Question posée à git, qui est la source et non une trace : si le dernier commit du dépôt
# système est POSTÉRIEUR à la dernière entrée de journal, une séance a travaillé et enregistré
# sans se refermer.
# LECTURE SEULE, dans le bloc ALERTES : alerte datée, bornée, qui disparaît quand on la traite.
if [ -n "$JDATE" ] && [ -d "$ROOT/.git" ]; then
    AMDATE=$(git -C "$ROOT" log -1 --format=%cd --date=short 2>/dev/null || true)
    if [ -n "$AMDATE" ] && [[ "$AMDATE" > "$JDATE" ]]; then
        AM_INCR=""
        # ÉCHAPPATOIRE : une séance écrite au journal d'un niveau a consigné son état ; crier
        # serait du bruit. La preuve est un événement `seance` portant la date du commit, cherchée
        # au `grep` (présence d'une date sur une ligne de type « seance »), pas par un parseur.
        while IFS= read -r _lv; do
            [ -n "$_lv" ] || continue
            for _j in "$_lv"/journal/*.jsonl; do
                [ -e "$_j" ] || continue
                grep '"type": *"seance"' "$_j" 2>/dev/null | grep -qF "$AMDATE" \
                    && { AM_INCR=1; break 2; }
            done
        done < <(claudeos_repos)
        if [ -z "$AM_INCR" ]; then
            OUT="${OUT}📌 Séance du ${AMDATE} non clôturée (journal arrêté au ${JDATE}) — elle a touché :"$'\n'
            # Substitution de PROCESSUS et non tuyau : un `while read` en bout de tuyau tourne
            # dans un sous-shell, et les ajouts à OUT y meurent avec lui — l'alerte s'afficherait
            # sans sa liste, sans rien signaler.
            while IFS= read -r _af || [ -n "$_af" ]; do
                [ -n "$_af" ] && OUT="${OUT}      ↳ ${_af}"$'\n'
            done < <(git -C "$ROOT" show --name-only --format= HEAD 2>/dev/null | head -10)
            OUT="${OUT}      ↳ aucune entrée de journal ne couvre encore cette séance."$'\n'
        fi
    fi
fi

# Amorçage auto-détectable par la machine : la ligne du wrapper de démarrage dans le fichier de
# shell. Sans elle, `claude` nu ne tire pas les dépôts avant de lancer et n'ouvre pas la session
# principale ; le bilan, lui, part du mod. Le poste n'est pas toujours en bash : sous macOS le shell
# de connexion est zsh, `~/.bashrc` n'y existe même pas. On cherche la ligne dans les fichiers de
# démarrage plausibles, et le message nomme celui du shell COURANT. La ligne à ajouter est dans le
# message, mot pour mot.
_claudeos_rc_trouve=""
for _claudeos_rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    if grep -qF '/engine/claudeos-boot.sh' "$_claudeos_rc" 2>/dev/null; then _claudeos_rc_trouve="$_claudeos_rc"; break; fi
done
case "${SHELL:-}" in *zsh) _claudeos_rc_cible="~/.zshrc" ;; *) _claudeos_rc_cible="~/.bashrc" ;; esac
if [ -f "$SELF/claudeos-boot.sh" ] && [ -z "$_claudeos_rc_trouve" ]; then
    OUT="${OUT}⚠️ Wrapper de démarrage ClaudeOS absent de '"$_claudeos_rc_cible"' (\`claude\` nu ne tire pas les dépôts et n'ouvre pas la session principale) — la ligne à y ajouter : [ -f ~/.claude/engine/claudeos-boot.sh ] && . ~/.claude/engine/claudeos-boot.sh"$'\n'
fi
# Le reste du poste — le bloc de titre de `~/.zshrc`, facultatif — se lit dans `claudeos_poste_ecarts`
# (config.sh), la source qu'applique `install-poste.sh`.
_CLAUDEOS_DU=""
while IFS='|' read -r _e _a; do
    case "$_e" in
        zsh-titre) _CLAUDEOS_DU="${_CLAUDEOS_DU}, bloc de titre de ~/.zshrc absent ou périmé" ;;
    esac
done < <(claudeos_poste_ecarts)
[ -n "$_CLAUDEOS_DU" ] && OUT="${OUT}⚠️ install-poste dû (${_CLAUDEOS_DU#, }) — bash ~/.claude/engine/install-poste.sh"$'\n'

# =============================================================================
# BILAN_DEMARRAGE=non (`reglages/REPONSES`) — bilan d'ouverture décliné à l'entretien
# =============================================================================
# Le mod `demarrage-auto` ne lance pas `/demarrage`, et la session principale ne reçoit ni les
# fils, ni les séances, ni les rappels. La DETTE DE SÉCURITÉ et ce qui menace la sauvegarde
# restent — un dépôt qui ne pousse plus, un retard, un distant injoignable : une garde ne se
# décline pas. Clé absente : le bilan reste, poste non réglé, jamais une valeur d'usine.
# `CLAUDEOS_BILAN_DEMANDE=1` (le rejeu d'un `/demarrage` tapé à la main) rend le bilan complet.
if [ "${CLAUDEOS_BILAN_DEMANDE:-}" != 1 ] && [ "$(claudeos_reponse BILAN_DEMARRAGE 2>/dev/null)" = "non" ]; then
    # Ancré sur le début de ligne et sur « Dépôt » : un rappel en retard porte aussi « en retard de ».
    _gardes="$(printf '%s\n' "${OUT:-}" | grep -E '^(🔐|⛔ Dépôt|⚠️ Dépôt .*(JAMAIS POUSSÉ|en retard de|distant injoignable|illisible))' || true)"
    # Le titre hors de `${…:+…}` : une apostrophe dans ce mot y ouvre une chaîne, sous bash.
    _titre_gardes="Gardes de la sécurité et de la sauvegarde, qui ne se déclinent pas — l'utilisateur les veut signalées, une ligne chacune, avant la première réponse :"
    _emet "${INACH}=== ClaudeOS — démarrage de la session PRINCIPALE · ${HEURE} ===
Bilan d'ouverture décliné à l'installation (BILAN_DEMARRAGE=non) : aucun bilan ne s'ouvre de lui-même ; \`/demarrage\` le rend à la demande.
${_gardes:+${_titre_gardes}
${_gardes}}"
    exit 0
fi

THREADS=$(python3 - "$MEM" "$REG/CRENEAUX" "$(date +%u)" "$SELF" 2>/dev/null <<'PYEOF'
import re, sys, os, subprocess
MEM, CRENEAUX, DOW = sys.argv[1], sys.argv[2], int(sys.argv[3]) - 1
sys.path.insert(0, sys.argv[4])
from lib_creneaux import DAYS, parse_creneaux   # source unique du format
def out(s): print(s.rstrip())

creneaux = parse_creneaux(CRENEAUX)
ouverts = sorted(w for w, d in creneaux.items() if DOW in d)
fermes = sorted(w for w in creneaux if w not in ouverts)

# Les fils viennent de `etat.py fils`. L'ancienneté d'un dû part du `ts` de son événement `ouvre`.
# La dormance n'a rien à câbler ici : `etat.py fils` la calcule (`DORMANT_JOURS`), et un dormant
# reste compté à chaque démarrage. Les marqueurs de porteur viennent de `etat.PORTEURS`.
import json
try:
    from etat import PORTEURS
    _M = dict(PORTEURS)
except Exception:
    _M = {"utilisateur": "👤", "tiers": "⏳"}
if creneaux:
    out(f"Créneau du jour ({DAYS[DOW]}) : "
        + (f"ouvert pour {', '.join(ouverts)}" if ouverts else "aucun domaine à créneau n'est ouvert")
        + (f" ; hors créneau : {', '.join(fermes)}." if fermes else "."))
# CRÉNEAU D'ABORD, LE RESTE EN COMPTES : la liste entière des fils actifs dépasse les 10 000
# caractères qu'un hook peut injecter en entier, et le bilan serait rendu sur un aperçu tronqué,
# en silence. Deux lectures de la MÊME commande : `--json` pour le domaine et la dormance, le
# texte pour l'intitulé — aucune recopie du calcul d'âge.
_etat = f'{os.path.expanduser("~")}/.claude/engine/etat.py'
_j = subprocess.run([sys.executable, _etat, 'fils', '--tous', '--json'], capture_output=True, text=True)
_t = subprocess.run([sys.executable, _etat, 'fils', '--tous'], capture_output=True, text=True)
try:
    items = json.loads(_j.stdout)
except ValueError:
    items = None
if items is None or _t.returncode != 0:
    # Une sortie vide ici est un DÉFAUT, pas une absence de fils : le dire, plutôt que de laisser
    # un blanc qui se lit « rien à faire ».
    out("Fils : vue indisponible — python3 ~/.claude/engine/etat.py fils --tous")
    sys.exit(0)
textes = {}
_l = _t.stdout.splitlines()
for i, l in enumerate(_l):
    m = re.match(r'^\[([^\]]+)\] (\S+) · (.*?) · (\S+)$', l)
    if m and i + 1 < len(_l) and _l[i + 1].startswith('    '):
        textes[(m.group(2), m.group(4))] = (m.group(1), _l[i + 1].strip())
dom = lambda n: n.split('/')[0]
court = lambda x: x['niveau'].rsplit('/', 1)[-1]
actifs = [x for x in items if not x.get('dormant')]
# TROIS SORTES DE DOMAINES : ouvert aujourd'hui, à créneau mais FERMÉ aujourd'hui, et LIBRE (sans
# créneau, proposable tous les jours). Un jour sans créneau ouvert propose les libres et laisse les
# fermés en comptes ; un jour à créneau propose le seul créneau.
def rang(d):
    return 0 if d in ouverts else (2 if d in fermes else 1)
sel = [x for x in actifs if (dom(x['niveau']) in ouverts if ouverts else rang(dom(x['niveau'])) == 1)]
sel.sort(key=lambda x: -x['age'])
def texte(x, n):
    age, txt = textes.get((court(x), x['ref']), (f"{x['age']} j", ''))
    return age, (txt[2:].strip()[:n] if txt else '')
# À TA CHARGE, TOUS DOMAINES. Ce qu'on PROPOSE est listé EN ENTIER, en forme courte : couper par âge
# faisait sauter les plus récents, le travail de la veille. Le reste se dit par domaine, nommé
# quand il y en a un ou deux : un bloc vide se dit, il ne se tait pas.
moi = sorted((x for x in actifs if x.get('porteur') == 'utilisateur'),
             key=lambda x: (rang(dom(x['niveau'])), -x['age']))
prop = [x for x in moi if x in sel]
ailleurs = [x for x in moi if x not in sel]
MAXP = 15
out(f"À ta charge (👤), tous domaines : {len(moi)} actif(s)"
    + (f", dont {len(prop)} proposable(s) aujourd'hui :" if prop else "."))
for x in prop[:MAXP]:
    age, t = texte(x, 90)
    out(f"  [{age}] {court(x)} · {x['ref']}" + (f" — {t}" if t else ""))
if len(prop) > MAXP:
    out(f"  … et {len(prop) - MAXP} autre(s) — etat.py fils --tous")
if ailleurs:
    par = {}
    for x in ailleurs:
        par.setdefault(dom(x['niveau']), []).append(x)
    def _d(d, xs):
        tag = " (hors créneau)" if d in fermes else ""
        if len(xs) <= 2:
            return f"{d}{tag} " + ", ".join(f"{x['ref']} {texte(x, 0)[0]}" for x in xs)
        return f"{d}{tag} {len(xs)}, le plus ancien {xs[0]['ref']} {texte(xs[0], 0)[0]}"
    out("  Ailleurs : " + " · ".join(_d(d, xs) for d, xs in sorted(par.items())))
# LE RESTE DE CE QU'ON PROPOSE : à l'assistant ou sans porteur, les plus anciens. Le filtre passe
# AVANT la coupe — couper d'abord rendait deux fils pour cinq places. Les ⏳ ne s'y proposent pas :
# ils nourrissent RELANCER, sur une ligne à part.
_cp = {}
for x in sel:
    _cp[x.get('porteur')] = _cp.get(x.get('porteur'), 0) + 1
detail = " · ".join(f"{_M.get(k, '❔')} {_cp[k]}" for k in [*_M, None] if _cp.get(k))
autres_p = [x for x in sel if x.get('porteur') not in ('utilisateur', 'tiers')]
titre = (f"Fils du créneau ({', '.join(ouverts)})" if ouverts else "Fils des domaines libres")
out(f"{titre} : {len(sel)} actif(s)" + (f" — {detail}" if detail else "")
    + (" ; à l'assistant ou sans porteur, les plus anciens :" if autres_p else "."))
for x in autres_p[:5]:
    age, t = texte(x, 160)
    out(f"  [{age}] {court(x)} · {x['chantier']} · {x['ref']}")
    if t:
        out(f"    {_M.get(x.get('porteur'), '❔')} {t}")
attente = [x for x in sel if x.get('porteur') == 'tiers']
if attente:
    out(f"  ⏳ en attente ({len(attente)}), les plus longues : "
        + " · ".join(f"{x['ref']} ({court(x)}, {texte(x, 0)[0]})" for x in attente[:3]))
autres = {}
for x in actifs:
    if x not in sel:
        d = dom(x['niveau']) + (" (hors créneau)" if dom(x['niveau']) in fermes else "")
        autres[d] = autres.get(d, 0) + 1
if autres:
    out("Autres fils actifs, par domaine : " + " · ".join(f"{k} {v}" for k, v in sorted(autres.items())))
_c = {}
for x in actifs:
    _c[x.get('porteur')] = _c.get(x.get('porteur'), 0) + 1
out("Porteurs des fils actifs : " + " · ".join(
    f"{_M.get(k, '❔')} {k or 'sans porteur'} {_c[k]}" for k in [*_M, None] if _c.get(k)) + ".")
out(f"Total : {len(items)} dû(s) ouvert(s), dont {len(items) - len(actifs)} dormant(s) — etat.py fils --tous --dormants.")
PYEOF
)

# --- Séances de projet depuis la dernière séance principale --------------------------------
# La principale sert de tour de contrôle des remontées de sous-sessions. Une ligne par niveau
# touché, sa dernière séance et son PROCHAIN, huit au plus. Les niveaux viennent de
# `etat.niveaux_tous()`, la même découverte que les fils.
PROCHAIN_ABSENT="non écrit dans l'entrée de séance."
# La lecture rend « AUCUNE » quand il n'y en a pas : une sortie VIDE est donc une panne, et se dit
# en alerte.
SEANCES_PROJ=""
if [ -n "$JTS" ]; then
    SEANCES_PROJ=$(_seances projets "$SELF" "$JTS" "$REG/CRENEAUX" "$(date +%u)")
    if [ -z "$SEANCES_PROJ" ]; then
        OUT="${OUT}⚠️ Séances de projet NON LUES — la lecture des journaux a échoué. Rejouer : bash ~/.claude/engine/boot-check.sh </dev/null"$'\n'
        SEANCES_PROJ="  non lues, voir les alertes."
    elif [ "$SEANCES_PROJ" = "AUCUNE" ]; then
        SEANCES_PROJ="  aucune."
    fi
fi

# --- Tableau d'état : le poste, la croisière, et ce que nulle alerte ne dit ---
# Dépôts, sauvegarde, secrets et journal périmé ont chacun leur alerte : le tableau ne les redit pas.
# Il ne garde, sous « État hors du vert », que le journal absent ou qui vieillit (T_WARN..T_CRIT).
# LA CROISIÈRE RESTE EN TÊTE, verte ou non : elle rend la condition d'arrêt VISIBLE. Jamais une
# alerte : être en chantier n'est pas un défaut. Muette sans historique.
CROISIERE_LIGNE=""
[ "$CRUISE_D" -ge 0 ] && CROISIERE_LIGNE="J ${CRUISE_D}/28 (tout chantier remet à zéro ; commit « incident: » non)"
DASH_PLAIN=""
if [ -z "$JDATE" ]; then DASH_PLAIN="▸ SESSION JOURNAL   absent"$'\n'
elif [ "$JDAYS" -gt "$T_WARN" ] && [ "$JDAYS" -le "$T_CRIT" ]; then DASH_PLAIN="▸ SESSION JOURNAL   vieillit (${JDATE})"$'\n'; fi

# =============================================================================
# SORTIE — les données du bilan, rendues par la compétence `demarrage`
# =============================================================================
# Les consignes de démarrage sont dans `skills/demarrage/SKILL.md`. Un texte de lancement ne défait
# pas une consigne injectée : ce script n'injecte donc aucun ordre.
ALERTS="${OUT:-}"
[ -z "$ALERTS" ] && ALERTS="aucune alerte."$'\n'
_KO=$(printf '%s' "$SYNC_DEPOTS" | awk -F'|' 'NF > 1 && $2 !~ / : à jour$/ {print "  " $2 ($3 != "" ? " (" $3 ")" : "")}')
if [ "$(claudeos_regime)" = aucun ]; then
    SYNC_TXT="Synchro : sans objet — régime sans git, rien ne se tire."
elif [ "${#_DR[@]}" -eq 0 ]; then
    SYNC_TXT="Synchro : aucun dépôt n'a de distant, rien à tirer."
elif [ "$_SONDE_RETARD" = 0 ]; then
    SYNC_TXT="Synchro : retard non sondé — un seul poste écrit ces dépôts (MULTIPOSTE=non)."
elif [ -z "$_KO" ]; then
    if [ "$_FR" -eq 0 ]; then _MESURE="mesuré par fetch à ce démarrage"
    elif [ "$_FN" -eq 0 ]; then _MESURE="fetch réutilisé, fait il y a ${_FAMAX} s au plus"
    else _MESURE="fetch à ce démarrage, ou réutilisé, fait il y a ${_FAMAX} s au plus"; fi
    SYNC_TXT="Synchro : tous les dépôts sont à jour (${_MESURE})."
else
    SYNC_TXT="Synchro : dépôts pas à jour —"$'\n'"${_KO}"
fi
# Les autres sessions ouvertes : `claudeos_sessions` (config.sh). La session qui pose la question se tait.
SESSIONS_TMUX=$(claudeos_sessions "${MOI_TMUX:-}" '#{session_name}' | sed -n 's/^tmux   //p' | paste -sd ',' - | sed 's/,/, /g')
CTX_FULL="${INACH}=== ClaudeOS — démarrage de la session PRINCIPALE · ${HEURE} ===
Données mesurées à cette heure. Le bilan se rend par la compétence \`/demarrage\`.
Poste : ${POSTE_LIGNE}
${CROISIERE_LIGNE:+Croisière : ${CROISIERE_LIGNE}}
${SYNC_TXT}
${DASH_PLAIN:+État hors du vert :
${DASH_PLAIN}}
--- FAIT DEPUIS LA DERNIÈRE PRINCIPALE ---
Dernière séance principale : ${JLINE:-(journal indisponible)}
${JTS:+PROCHAIN : ${JPROCHAIN:-$PROCHAIN_ABSENT}}
${JAUTRES:+Puis, sur un autre poste :
${JAUTRES}}
${JTS:+Séances de projet, écrites depuis ou récentes (7 j) au créneau du jour :
${SEANCES_PROJ}}

--- ALERTES ET RAPPELS ---
${REM_LIGNE}
${ALERTS}
--- FILS ET DUS ---
${THREADS:-Fils : vue indisponible — python3 ~/.claude/engine/etat.py fils --tous}
Sessions ouvertes : ${SESSIONS_TMUX:+tmux : ${SESSIONS_TMUX}}${SESSIONS_TMUX:-aucune autre}"
_emet "$CTX_FULL"
