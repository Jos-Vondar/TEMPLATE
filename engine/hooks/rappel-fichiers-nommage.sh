#!/usr/bin/env bash
# Garde de geste — fait charger une compétence AU MOMENT DU GESTE qu'elle couvre.
#
# Un geste de création, de destruction ou d'écriture d'une source de vérité ne marque aucune
# pause où la liste des compétences serait relue : une règle écrite n'y suffit pas, d'où ce garde.
# Compétences gardées : `fichiers-et-nommage`, `memoire-et-verite`, `controles-et-alarmes`,
# `session`, `reprise` — chacune par un bloc plus bas ; certaines annexes de compétence aussi
# (bloc « LE REFUS UNIQUE »).
#
# DEUX NATURES, partage « bloque / avertit » de `controles-et-alarmes` :
#   - compétence non chargée : REFUS UNIQUE par compétence et par session, puis tout passe
#     (bloc « LE REFUS UNIQUE » en queue). Un défaut de rangement encombre, il ne désactive rien.
#   - `--no-verify` et ses équivalents : REFUS à chaque fois. Le drapeau désactive en silence tout
#     le crochet de commit — projection, gel, détection de secret.
# Le garde `--no-verify` vit ici et pas dans un crochet neuf : il réutilise la lecture de commande
# (surface sans heredocs ni chaînes citées), seule partie difficile, qu'une copie ferait dériver.
#
# HORS PÉRIMÈTRE : un `PreToolUse` ne voit que les commandes de l'agent. Un `--no-verify` tapé par
# l'utilisateur dans son terminal ne passe par aucun crochet.

set -uo pipefail

IN=$(cat)
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/claudeos"

# Une lecture de fichier hors `skills/` ne pose aucun marqueur : sortie sans lancer python.
case "$IN" in *'"tool_name":"Read"'*|*'"tool_name": "Read"'*)
    case "$IN" in *'/skills/'*) ;; *) exit 0 ;; esac ;;
esac

# --- UNE SEULE LECTURE DE L'ENTRÉE : un python par appel, la surface de commande comprise.
# Le crochet tourne à chaque appel d'outil gardé : chaque python de plus s'y paie en latence.
# Champs séparés par NUL, `read -d ''` les relit : une commande peut porter des sauts de ligne.
# Le programme est entre apostrophes et n'en contient aucune.
# `SURFACE_OK` porte le fait qu'on a su lire la commande : aucun REFUS ne se prononce sur une
# lecture ratée ; les gestes de nommage peuvent tourner sur le repli brut.
_LIT='
import json, sys, importlib.util
try:
    d = json.loads(sys.stdin.read())
except Exception:
    sys.exit(1)
if not isinstance(d, dict):
    sys.exit(1)
ti = d.get("tool_input") or {}
if not isinstance(ti, dict):
    ti = {}
cmd = ti.get("command") or ti.get("file_path") or ti.get("notebook_path") or ""
nom = ti.get("skill") or d.get("command_name") or ""
surf, ok = cmd, "0"
if d.get("tool_name") == "Bash":
    try:
        spec = importlib.util.spec_from_file_location("surface_commande", sys.argv[1])
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        surf, ok = m.surface(cmd), "1"
    except Exception:
        pass
champs = [d.get("hook_event_name"), d.get("tool_name"), d.get("session_id", "nosess"),
          d.get("agent_id"), d.get("source"), d.get("scratchpad_dir"), d.get("cwd"), nom, ok, cmd, surf]
sys.stdout.write("".join(("" if c is None else str(c)) + "\0" for c in champs))
'
EVT="" TOOL="" SESS="" AGENT="" SOURCE="" SCRATCH="" CWD="" NOM="" SURFACE_OK=0 CMD="" SURFACE=""
{ IFS= read -r -d '' EVT; IFS= read -r -d '' TOOL; IFS= read -r -d '' SESS; IFS= read -r -d '' AGENT
  IFS= read -r -d '' SOURCE; IFS= read -r -d '' SCRATCH; IFS= read -r -d '' CWD; IFS= read -r -d '' NOM
  IFS= read -r -d '' SURFACE_OK; IFS= read -r -d '' CMD; IFS= read -r -d '' SURFACE; } \
    < <(printf '%s' "$IN" | python3 -c "$_LIT" "$(dirname "$0")/surface-commande.py" 2>/dev/null)

# --- MARQUEURS, HORS PreToolUse. `charge-<clé>-<session>` dit « chargée dans cette session » :
# posé quand l'outil Skill a tourné (PostToolUse, matcher Skill), qu'un `/nom` a été tapé
# (UserPromptExpansion), ou qu'une ANNEXE de compétence a été lue (PostToolUse, matcher Read :
# `skills/<fiche>/<ANNEXE>.md`, nom en majuscules, clé `<fiche>+<ANNEXE>`). Jamais par un
# sous-agent, qui partage la session sans partager le contexte. `refus-<clé>-<session>` dit
# « déjà demandée ». Une compaction sort les fiches du contexte sans changer de session : le
# `SessionStart` de matcher `compact` efface les deux, et une fiche réinjectée se redemande une
# fois — l'erreur tombe côté refus.
case "$EVT" in
  PostToolUse|UserPromptExpansion)
    [ -n "$AGENT" ] && exit 0
    if [ "$TOOL" = Read ]; then
        case "$CMD" in */skills/*/*.md) ;; *) exit 0 ;; esac
        _f=${CMD%/*}; _f=${_f##*/}; _a=${CMD##*/}; _a=${_a%.md}
        case "$_a" in ''|*[![:upper:][:digit:]_]*) exit 0 ;; esac
        NOM="$_f+$_a"
    else
        NOM=${NOM#*:}
    fi
    case "$NOM" in ''|*/*|*' '*) exit 0 ;; esac
    [ -n "$SESS" ] && [ "$SESS" != nosess ] && mkdir -p "$CACHE" 2>/dev/null && : > "$CACHE/charge-$NOM-$SESS"
    exit 0 ;;
  SessionStart)
    [ "$SOURCE" = compact ] && [ -n "$SESS" ] && [ "$SESS" != nosess ] \
        && rm -f "$CACHE"/refus-*-"$SESS" "$CACHE"/charge-*-"$SESS"
    exit 0 ;;
esac

KIND=""
case "$TOOL" in
  # Seul un chemin NEUF est une création : réécrire un fichier existant ne nomme rien, et Edit
  # (modifier un existant) n'a pas de branche, KIND reste vide.
  Write|NotebookEdit) if [ -n "$CMD" ] && [ -e "$CMD" ]; then KIND=""; else KIND="creation"; fi ;;
  Bash)
    # LA SURFACE, PAS LA CHAÎNE ENTIÈRE : un motif lancé sur toute la commande tombe sur les
    # heredocs et les chaînes citées (une variable Python `mv`, un `mv a b` cité dans un texte
    # d'événement). On cherche sur la surface, sans corps de heredoc ni chaînes citées : ce qui
    # est donnée n'est pas geste.
    # Le programme vit dans son propre fichier, `surface-commande.py` (motif et contrat dans son
    # en-tête), chargé par la lecture d'entrée ci-dessus.
    # --- GARDE `--no-verify` — REFUSE. Motif et périmètre : en-tête. ----------------------
    # Cherché sur SURFACE : un message de commit qui NOMME `--no-verify` ne doit pas être refusé.
    # Levier tracé : `FORCE_NO_VERIFY="motif"` devant la commande, qui reste dans l'historique.
    # Cinq formes sautent le crochet : `--no-verify`, son abréviation que git accepte (`--no-veri`,
    # le plus court préfixe sans ambiguïté), `git commit -n`, une grappe courte qui porte `n`
    # (`-nm`, `-anm`), et `-c core.hooksPath=…`. Lecture PAR SEGMENT et PAR SOUS-COMMANDE : `-n`
    # est `--dry-run` pour `push`, et un `grep -n` voisin ne compte pas. En awk et non en python :
    # le crochet tourne à chaque geste, et chaque python de plus s'y paie en latence.
    _saute_crochet() {
        printf '%s\n' "$1" | tr ';|&' '\n\n\n' | awk '
          {
            n = split($0, w, /[[:space:]]+/); g = 0; sc = ""
            for (i = 1; i <= n; i++) {
              if (w[i] == "") continue
              if (!g) { if (w[i] ~ /(^|\/)git$/) g = 1; continue }
              if (sc == "") {
                if (tolower(w[i]) ~ /^(--config-env=)?core\.hookspath/) hit = 1
                if (w[i] == "-c" || w[i] == "-C") { i++; if (tolower(w[i]) ~ /^core\.hookspath/) hit = 1; continue }
                if (w[i] ~ /^-/) continue
                sc = w[i]; continue
              }
              if (sc == "commit" && (w[i] ~ /^--no-veri/ || w[i] ~ /^-[A-Za-z]*n[A-Za-z]*$/)) hit = 1
              if (sc == "push" && w[i] ~ /^--no-veri/) hit = 1
            }
          }
          END { exit hit ? 0 : 1 }'
    }
    if [ "$SURFACE_OK" = 1 ] \
       && printf '%s' "$SURFACE" | grep -qE 'git([[:space:]]+[^[:space:]]+)*[[:space:]]+(commit|push)' \
       && _saute_crochet "$SURFACE" \
       && ! printf '%s' "$SURFACE" | grep -qE 'FORCE_NO_VERIFY='; then
        python3 -c '
import json
print(json.dumps({"hookSpecificOutput":{
  "hookEventName":"PreToolUse",
  "permissionDecision":"deny",
  "permissionDecisionReason":(
    "REFUS — `--no-verify`, `-n` ou un core.hooksPath detourne desactivent TOUT le crochet de commit en silence : le refus 23 sur une "
    "projection desynchronisee, le 24 sur un fichier gele, et la detection de secret. Ce que le "
    "crochet allait refuser ne se sait pas en le contournant. Geste attendu : relancer SANS le "
    "drapeau, lire ce qui est refuse, et traiter la cause. Si le contournement est assume, le "
    "levier trace est FORCE_NO_VERIFY=\"motif\" devant la commande."
  )}}))
'
        exit 0
    fi

    # `git rm` et `git mv` comptent : ils retirent le fichier du disque comme du suivi.
    # L'argument exigé ne commence pas par `=` : `mv a b` est un geste, `mv = …` une variable.
    if printf '%s' "$SURFACE" | grep -qE '(^|[;&|]|&&|\|\|)[[:space:]]*(sudo[[:space:]]+)?(git[[:space:]]+)?(rm|rmdir|shred|mv)([[:space:]]+[^=[:space:]]|$)'; then
      KIND="destruction"
    elif printf '%s' "$SURFACE" | grep -qE '(^|[;&|]|&&|\|\|)[[:space:]]*(sudo[[:space:]]+)?(mkdir|touch|cp|install|tee)([[:space:]]+[^=[:space:]]|$)'; then
      KIND="creation"
    else
      # CRÉATION PAR REDIRECTION (`cat > f`, `echo > f`). Un `>` brut matcherait `2>/dev/null`,
      # présent presque partout : le refus unique tirerait sur la première commande de chaque
      # séance et on apprendrait à l'ignorer. On retire d'abord les redirections qui ne créent
      # pas de fichier nommé — vers /dev/*, duplications de descripteur (`2>&1`, `>&-`) ; ce qui
      # reste écrit vers un chemin.
      _red=$(printf '%s' "$SURFACE" | sed -E 's#[0-9]*>>?[[:space:]]*/dev/[a-zA-Z0-9]+##g; s#[0-9]*>&[0-9-]##g')
      if printf '%s' "$_red" | grep -qE '>>?[[:space:]]*[^[:space:]&|>]'; then
        KIND="creation"
      fi
    fi
    ;;
esac

# --- CRÉATION ET DESTRUCTION EXEMPTÉES : ZONE JETABLE, AJOUT `>>` À UN FICHIER EXISTANT -------
# Les règles de `fichiers-et-nommage` ne concernent ni un fichier jetable (scratchpad, `/tmp`,
# `/var/folders`) ni un ajout à un registre. `creation-exemptee.py` en est SEUL JUGE, cible par
# cible (motif et contrat : son en-tête) ; il reçoit aussi le dossier courant de l'entrée. Un
# chemin durable cité à côté d'un chemin jetable n'est donc jamais exempté avec lui.
# Tout code autre que 0, erreur comprise, laisse KIND intact : on ne conclut rien d'une lecture ratée.
if { [ "$KIND" = creation ] || [ "$KIND" = destruction ]; } \
   && python3 "$(dirname "$0")/creation-exemptee.py" "$TOOL" "$CMD" "$SCRATCH" "$CWD"; then
    KIND=""
fi

# --- ÉCRITURE D'UNE SOURCE DE VÉRITÉ -----------------------------------------------------------
# Un `etat.py add`, ou un Write/Edit sur DESIGN.md, CLAUDE.md, MEMORY.md, une fiche de mémoire
# (`memory/<prefixe>_<sujet>.md`) ou un nom de `reglages/SOURCES_VERITE` : le moment du danger de
# `memoire-et-verite`. Sauf `MEMORY.md` et `etat.py add`, ces écritures exigent AUSSI son annexe
# `SOURCES_DE_VERITE`.
# Les réglages du poste se lisent directement, sans sourcer `config.sh` : ce crochet tourne à
# CHAQUE geste d'outil. `CLAUDEOS_REG` pointe un autre dossier, pour les essais.
_REG="${CLAUDEOS_REG:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/reglages}"
VERITE=0 A_VERITE=""
case "$TOOL" in
  Write|Edit|NotebookEdit)
    _b="$(basename -- "$CMD")"
    case "$_b" in
      MEMORY.md) VERITE=1 ;;
      DESIGN.md|CLAUDE.md) VERITE=1 A_VERITE=SOURCES_DE_VERITE ;;
      *)
        # Les sources de vérité propres au poste : `reglages/SOURCES_VERITE`, un motif de nom de
        # fichier par ligne (un document de référence de métier, par exemple), facultatif.
        # `|| [ -n "$_m" ]` : sans saut final, `read` perdrait la dernière ligne.
        if [ -f "$_REG/SOURCES_VERITE" ]; then
            while IFS= read -r _m || [ -n "$_m" ]; do
                case "$_m" in ''|'#'*) continue ;; esac
                case "$_b" in $_m) VERITE=1 A_VERITE=SOURCES_DE_VERITE; break ;; esac
            done < "$_REG/SOURCES_VERITE"
        fi ;;
    esac
    case "$CMD" in */memory/[a-z]*_*.md) VERITE=1 A_VERITE=SOURCES_DE_VERITE ;; esac ;;
  Bash)
    # Une consultation d'aide n'écrit rien. Jugé PAR SEGMENT : un seul `etat.py add` sans drapeau
    # d'aide suffit à exiger la fiche, même si un autre segment n'est qu'une consultation.
    # Un segment qui porte une substitution `$(` ou un accent grave exige la fiche quel que soit son
    # drapeau : `add --id d-x $(echo t --help )` écrit bel et bien.
    _add=$(printf '%s\n' "${SURFACE:-}" | tr ';&|' '\n\n\n' | grep -E 'etat\.py[[:space:]]+add')
    if [ -n "$_add" ] && { printf '%s\n' "$_add" | grep -qE '\$\(|`' \
         || printf '%s\n' "$_add" | grep -qvE '(^|[[:space:]])(-h|--help)([[:space:]]|$)'; }; then
        VERITE=1
    fi ;;
esac

# --- MODIFICATION D'UN CONTRÔLE ----------------------------------------------------------------
# Un Write/Edit sur un `.sh` ou `.py` sous un dossier `engine/` : le moment du danger de
# `controles-et-alarmes`. PAS ANCRÉ SUR `.claude/` : une copie du moteur hors de `~/.claude`
# doit tomber sous le garde.
# CE QU'IL NE COUVRE PAS : une écriture par Bash (`sed -i`, `cp`, redirection) — la surface
# d'une commande efface les chemins cités, et mieux la lire rouvrirait la source de faux positifs.
CONTROLE=0
case "$TOOL" in
  Write|Edit|NotebookEdit)
    printf '%s' "$CMD" | grep -qE '(^|/)engine/.+\.(sh|py)$' && CONTROLE=1 ;;
esac

# --- DOCUMENT QU'UN AGENT LIT -------------------------------------------------------------------
# Le moment du danger de `writing-for-agents`, compétence OPTIONNELLE (`SKILLS_OPTION`) : le garde ne
# vaut que si elle est installée. `Write` sur une fiche, un agent, un plan ou une spec ; `Edit` sur
# un SKILL.md seulement — un plan ou une spec retouchés ne paient pas la fiche.
# CE QU'IL NE COUVRE PAS : une écriture par Bash.
REDAC=0
if [ -f "$HOME/.claude/skills/writing-for-agents/SKILL.md" ]; then
  case "$TOOL" in
    Write|NotebookEdit)
      case "$CMD" in */SKILL.md|*/docs/specs/*|*/docs/plans/*) REDAC=1 ;; esac
      printf '%s' "$CMD" | grep -qE '/agents/[^/]+\.md$' && REDAC=1 ;;
    Edit)
      case "$CMD" in */SKILL.md) REDAC=1 ;; esac ;;
  esac
fi

# --- LANCER UN AGENT, OU PARLER À UNE AUTRE SESSION ---------------------------------------------
# Le moment du danger de `session` : le modèle et le libellé d'un agent se choisissent à son
# lancement, et un message à une autre session part avec ce qu'il porte.
SESSION=0
case "$TOOL" in
  Agent|SendMessage) SESSION=1 ;;
esac

# --- SAUVEGARDE ET FERMETURE DE SESSION : annexes de `reprise` ----------------------------------
# `claudeos-cloture.sh` lancé exige `CLOTURE_PRINCIPALE` ; une fermeture de session tmux
# (`fermer-projet.sh`, `kill-session`) exige `FERMETURE_PROJET`. Lus sur la surface ; le bloc de
# fermeture et un chemin de clôture cité cachent leurs mots dans des chaînes, d'où un second test
# sur la commande brute, qui ne vaut que si la surface montre l'interprète qui les exécute — sans
# lui, un texte qui NOMME ces gestes (heredoc, message) ferait refuser.
CLOTURE=0 FERMETURE=0
case "$TOOL:$CMD" in Bash:*cloture*|Bash:*kill*|Bash:*fermer-projet*)
    _seg=$(printf '%s\n' "$SURFACE" | tr ';&|' '\n\n\n')
    _aff="^[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|\"\"|'')[[:space:]]+)*"
    printf '%s\n' "$_seg" | grep -qE "${_aff}((bash|sh|zsh|exec|command)[[:space:]]+)?[^[:space:]]*cloture\.sh([[:space:]]|\$)" \
        && CLOTURE=1
    printf '%s\n' "$_seg" | grep -qE "${_aff}(bash|sh|zsh)[[:space:]]+\"\"" \
        && printf '%s' "$CMD" | grep -qE 'cloture\.sh' && CLOTURE=1
    # Le script de fermeture se reconnaît LANCÉ, en tête de segment.
    printf '%s\n' "$_seg" | grep -qE "${_aff}((bash|sh|zsh|exec|command)[[:space:]]+)?[^[:space:]]*fermer-projet\.sh([[:space:]]|\$)" \
        && FERMETURE=1
    _fer='kill-session'
    printf '%s' "$SURFACE" | grep -qE "$_fer" && FERMETURE=1
    printf '%s' "$SURFACE" | grep -qE 'run-shell' \
        && printf '%s' "$CMD" | grep -qE "$_fer" && FERMETURE=1 ;;
esac
[ -z "$KIND" ] && [ "$VERITE" = 0 ] && [ "$CONTROLE" = 0 ] && [ "$REDAC" = 0 ] \
    && [ "$SESSION" = 0 ] && [ "$CLOTURE" = 0 ] && [ "$FERMETURE" = 0 ] && exit 0

# --- LE REFUS UNIQUE ---------------------------------------------------------------------------
# POURQUOI : un `additionalContext` de PreToolUse arrive AVEC le résultat de l'outil, donc APRÈS
# le geste (doc hooks.md, « PreToolUse decision control ») ; seul `permissionDecision: deny`
# parle à Claude AVANT.
# LE GESTE : compétence non chargée dans la session → REFUSER UNE FOIS (« charge-la, puis
# relance ») ; au second essai le geste passe, chargée ou non. Le marqueur tient le compte, pas
# la transcription : écrite en différé (« may lag ») et de format interne, s'y fier ferait
# refuser en boucle une compétence chargée à l'instant.
# RIEN NE SE REFUSE SUR UNE LECTURE RATÉE : session sans identifiant, ou geste DANS UN
# SOUS-AGENT (`agent_id` présent — il n'a pas forcément l'outil Skill) → rappel simple.
# UNE ANNEXE (`skills/<fiche>/<ANNEXE>.md`) se garde comme une compétence, clé `<fiche>+<ANNEXE>` :
# lue par Read, elle n'est reconnue que si le PostToolUse de matcher Read appelle ce crochet ;
# sinon elle se refuse une fois par session, même déjà lue. Fiche ET annexe absentes : un seul
# refus nomme les deux et compte pour les deux.
charge() {  # rc 0 = chargée ; 1 = absente ; 2 = on n'a pas pu lire
    [ -n "$SESS" ] && [ "$SESS" != nosess ] || return 2
    [ -f "$CACHE/charge-$1-$SESS" ]
}
_sortie() {  # $1 deny | ctx, $2 texte
    python3 -c '
import json,sys
o={"hookEventName":"PreToolUse"}
if sys.argv[1]=="deny": o.update(permissionDecision="deny",permissionDecisionReason=sys.argv[2])
else: o["additionalContext"]=sys.argv[2]
print(json.dumps({"hookSpecificOutput":o}))
' "$1" "$2"
    exit 0
}
rappel() {  # $1 compétence, $2 libellé, $3 annexe facultative
    local a=""
    [ -n "${3:-}" ] && a=" Lire aussi en entier son annexe ~/.claude/skills/$1/$3.md."
    _sortie ctx "Geste couvert par la compétence \`$1\` ($2). La charger par l'outil Skill si elle n'est pas en contexte.$a"
}
refus() {   # $1 compétence, $2 libellé, $3 annexe facultative
    local a="${3:-}"
    mkdir -p "$CACHE" 2>/dev/null; : > "$CACHE/refus-$1${a:++$a}-${SESS}"
    [ -z "$a" ] && _sortie deny "REFUS UNIQUE, pas une erreur — geste de $2 sans la compétence \`$1\` chargée dans cette session. La charger par l'outil Skill, PUIS relancer exactement le même geste : il passera. Ce refus n'arrive qu'une fois par compétence et par session."
    charge "$1" && _sortie deny "REFUS UNIQUE, pas une erreur — geste de $2 sans l'annexe \`$1/$a.md\` lue dans cette session. La lire en entier par l'outil Read (~/.claude/skills/$1/$a.md), PUIS relancer exactement le même geste : il passera. Ce refus n'arrive qu'une fois par annexe et par session."
    : > "$CACHE/refus-$1-${SESS}"
    _sortie deny "REFUS UNIQUE, pas une erreur — geste de $2 sans la compétence \`$1\` chargée dans cette session, ni son annexe ~/.claude/skills/$1/$a.md lue. Charger la compétence par l'outil Skill, lire l'annexe en entier par l'outil Read, PUIS relancer exactement le même geste : il passera. Ce refus n'arrive qu'une fois par geste gardé et par session."
}
exige() {   # $1 compétence, $2 libellé du geste, $3 annexe à lire (nom sans .md), facultative
    # Une annexe absente du disque ne s'exige pas : refuser en renvoyant vers un fichier
    # introuvable serait une impasse.
    set -- "$1" "$2" "${3:-}"
    [ -n "$3" ] && [ ! -f "$HOME/.claude/skills/$1/$3.md" ] && set -- "$1" "$2" ""
    local k="$1${3:++$3}" c
    [ -f "$CACHE/refus-$k-${SESS}" ] && return 0
    [ -n "$AGENT" ] && rappel "$1" "$2" "${3:-}"
    charge "$1"; c=$?
    [ -n "${3:-}" ] && [ "$c" = 0 ] && { charge "$k"; c=$?; }
    case $c in
        0) mkdir -p "$CACHE" 2>/dev/null; : > "$CACHE/refus-$k-${SESS}"; return 0 ;;
        2) rappel "$1" "$2" "${3:-}" ;;
        *) refus "$1" "$2" "${3:-}" ;;
    esac
}

A_KIND=""; [ "$KIND" = destruction ] && A_KIND=SUPPRIMER_DEPLACER
[ "$VERITE" = 1 ] && exige memoire-et-verite "écriture d'une source de vérité" "$A_VERITE"
[ -n "$KIND" ] && exige fichiers-et-nommage "$KIND de fichier" "$A_KIND"
[ "$CLOTURE" = 1 ] && exige reprise "sauvegarde par claudeos-cloture.sh" CLOTURE_PRINCIPALE
[ "$FERMETURE" = 1 ] && exige reprise "fermeture d'une session" FERMETURE_PROJET
[ "$REDAC" = 1 ] && exige writing-for-agents "écriture d'un document qu'un agent lit"
[ "$CONTROLE" = 1 ] && exige controles-et-alarmes "modification d'un contrôle ou d'une alarme"
[ "$SESSION" = 1 ] && exige session "lancement d'un agent ou message à une autre session"
exit 0
