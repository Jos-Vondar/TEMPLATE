#!/usr/bin/env bash
# Garde de geste sur fichier — rappelle la compétence `fichiers-et-nommage` AU MOMENT DU GESTE.
#
# MOTIF, et il est mesuré : la fiche a été ratée ONZE fois entre le 2026-09-10 et le 2026-09-16,
# par la session principale comme par les sessions de projet. Le diagnostic est posé quatre fois au
# registre `memory/ROUTING_MISSES.md` et il tient : le geste de création comme celui de suppression
# ne déclenchent AUCUNE pause où la liste des compétences serait relue. Une règle écrite ne peut
# donc pas corriger ce défaut — c'est précisément ce qui a échoué onze fois.
#
# AUTORISÉ PAR L'UTILISATEUR le 2026-09-16, contre l'interdit « pas de nouveau contrôle » du
# 2026-08-17, qui réserve le contrôle neuf à un arbitrage rendu par lui. Les deux autres issues
# qu'il a écartées : retirer l'attente du registre, ou remonter les règles au règlement racine.
#
# DEUX NATURES DEPUIS LE 2026-09-22, et ce fichier disait « IL NE BLOQUE JAMAIS » jusque-là.
# Partage « bloque / avertit » de `controles-et-alarmes`, appliqué cas par cas :
#   - NOMMAGE (création, destruction) : AVERTIT. Une convention non appliquée ENCOMBRE, elle ne
#     désactive rien. Bloquer ferait payer un défaut de rangement par la perte du geste.
#   - `--no-verify` : BLOQUE. Ce drapeau DÉSACTIVE EN SILENCE tout le crochet de commit — le refus
#     23 sur une projection désynchronisée, le 24 sur un fichier gelé, la détection de secret. Le
#     partage range explicitement « ce qui désactive en silence » du côté du blocage.
# POURQUOI ICI ET PAS DANS UN CROCHET NEUF : la lecture de commande ci-dessous (retrait des
# heredocs et des chaînes citées) a déjà coûté DEUX faux positifs le 2026-09-16. La dupliquer
# créerait deux copies à deux âges de la seule partie difficile. Chemin ajouté à un contrôle
# existant — marche 2 de `controles-et-alarmes`, la moins chère.
# ARBITRÉ PAR L'UTILISATEUR le 2026-09-22, dû `u-garde-no-verify-absent-2`.
#
# CE QUE CE GARDE NE COUVRE PAS, et il ne faut pas le lire comme une fermeture complète : un
# `PreToolUse` n'intercepte que les commandes lancées PAR L'AGENT. Un `--no-verify` tapé par
# l'utilisateur dans son propre terminal ne passe par aucun crochet et reste possible.
#
# DEPUIS LE 2026-09-24, UN REFUS UNIQUE AU LIEU DU RAPPEL (`d-refus-unique-declencheur`) : le
# rappel `additionalContext` arrivait APRÈS le geste. Geste de création ou de destruction sans
# `fichiers-et-nommage` chargée, ou écriture d'une source de vérité sans `memoire-et-verite` :
# refusé UNE fois par compétence et par session, puis tout passe. Détail en queue de fichier.
# Troisième compétence gardée depuis le 2026-10-01 : `controles-et-alarmes`, à la modification
# d'un contrôle (bloc « MODIFICATION D'UN CONTRÔLE » plus bas).

#
# FAUX POSITIF CORRIGE LE 2026-09-16, LE JOUR MEME DE L ARMEMENT : le garde lit TOUTE la chaine de
# commande, corps de document en ligne compris. Une variable Python nommee `mv` en debut de ligne
# dans un heredoc a donc declenche le rappel destructeur. Les motifs exigent desormais que le mot
# soit suivi d un argument qui ne commence pas par `=` : `mv a b` passe, `mv = re.search(...)` non.
# C est le cousin de la regle « un garde-fou mesure le CODE, pas les commentaires » de
# `controles-et-alarmes` : ici le garde mesurait la charge utile en plus des commandes.

set -uo pipefail

IN=$(cat)
J() { printf '%s' "$IN" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('$1','') if '.' not in '$1' else '')" 2>/dev/null; }

TOOL=$(printf '%s' "$IN" | python3 -c "import json,sys;print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)
SESS=$(printf '%s' "$IN" | python3 -c "import json,sys;print(json.load(sys.stdin).get('session_id','nosess'))" 2>/dev/null)
CMD=$(printf '%s' "$IN" | python3 -c "
import json,sys
d=json.load(sys.stdin).get('tool_input',{}) or {}
print(d.get('command','') or d.get('file_path','') or '')
" 2>/dev/null)

KIND=""
case "$TOOL" in
  Write|NotebookEdit) KIND="creation" ;;
  Edit)               KIND="" ;;   # modifier un fichier existant ne nomme rien : pas de rappel
  Bash)
    # LA SURFACE, PAS LA CHAINE ENTIERE. Un motif lance sur toute la commande tombe sur les
    # documents en ligne et les chaines citees — deux faux positifs le 2026-09-16, le jour de
    # l armement : une variable Python nommee `mv`, puis un `mv a b` cite dans le TEXTE d un
    # evenement. On retire donc d abord les corps de heredoc et les chaines citees, puis on
    # cherche. C est la regle « un garde-fou mesure le CODE, pas les commentaires » appliquee a
    # une commande : ce qui est donnee n est pas geste.
    # PROGRAMME DANS SON PROPRE FICHIER — CORRIGÉ LE 2026-09-22. Il vivait ici dans une chaîne
    # bash entre guillemets doubles et contenait lui-même des guillemets doubles : bash refermait
    # la chaîne au milieu, python recevait un programme tronqué, et le `2>/dev/null` avalait la
    # `SyntaxError`. Le repli reprenait la commande BRUTE — donc ce nettoyage n'avait JAMAIS
    # tourné depuis sa pose du 2026-09-16, et la protection contre les faux positifs écrite ce
    # jour-là était morte à la naissance. Un heredoc quoté réglait l'échappement mais bash 3.2,
    # celui que macOS livre, refuse un heredoc dans une substitution de commande. Motif complet
    # et contrat de sortie : en-tête de `surface-commande.py`.
    # `SURFACE_OK` PORTE LE FAIT QU'ON A SU LIRE — « un contrôle ne fait jamais porter une
    # conclusion à une branche d'erreur » (`controles-et-alarmes`). Aucun REFUS ne se prononce
    # sur une lecture qui a échoué ; les rappels de nommage, eux, ne font qu'AVERTIR et peuvent
    # tourner sur le repli sans rien coûter.
    SURFACE_OK=1
    SURFACE=$(python3 "$(dirname "$0")/surface-commande.py" "$CMD") \
        || { SURFACE="$CMD"; SURFACE_OK=0; }
    # --- GARDE `--no-verify` — REFUSE. Voir l'en-tête pour le motif et le périmètre. -------
    # Cherché sur SURFACE et non sur la commande brute : sans ça, un message de commit ou un
    # texte d'événement qui NOMME `--no-verify` déclencherait le refus. Ce cas n'est pas
    # théorique, il s'est produit le jour même de la pose.
    # LEVIER TRACÉ, sur le modèle de `FORCE_GELE` : préfixer la commande de
    # `FORCE_NO_VERIFY="motif"` lève le refus et laisse le motif dans l'historique du shell.
    if [ "$SURFACE_OK" = 1 ] \
       && printf '%s' "$SURFACE" | grep -qE 'git([[:space:]]+[^[:space:]]+)*[[:space:]]+(commit|push)' \
       && printf '%s' "$SURFACE" | grep -qE '(^|[[:space:]])(--no-verify)([[:space:]]|$)' \
       && ! printf '%s' "$SURFACE" | grep -qE 'FORCE_NO_VERIFY='; then
        python3 -c '
import json
print(json.dumps({"hookSpecificOutput":{
  "hookEventName":"PreToolUse",
  "permissionDecision":"deny",
  "permissionDecisionReason":(
    "REFUS — `--no-verify` desactive TOUT le crochet de commit en silence : le refus 23 sur une "
    "projection desynchronisee, le 24 sur un fichier gele, et la detection de secret. Ce que le "
    "crochet allait refuser ne se sait pas en le contournant. Geste attendu : relancer SANS le "
    "drapeau, lire ce qui est refuse, et traiter la cause. Si le contournement est assume, le "
    "levier trace est FORCE_NO_VERIFY=\"motif\" devant la commande."
  )}}))
'
        exit 0
    fi

    # `git rm` et `git mv` AJOUTÉS le 2026-09-17 : trou mesuré sur pièce le jour même — la session
    # principale a supprimé TROIS fichiers suivis au `git rm` (geste C6 de l'audit du 2026-09-16)
    # et le garde n'a rien dit, le motif exigeant `rm` en TÊTE de commande. Un `git rm` retire le
    # fichier du disque comme du suivi : c'est la même destruction, avec l'historique en filet.
    # Chemin ajouté à un garde existant, pas un garde neuf (`controles-et-alarmes`, marche 2).
    if printf '%s' "$SURFACE" | grep -qE '(^|[;&|]|&&|\|\|)[[:space:]]*(sudo[[:space:]]+)?(git[[:space:]]+)?(rm|rmdir|shred|mv)([[:space:]]+[^=[:space:]]|$)'; then
      KIND="destruction"
    elif printf '%s' "$SURFACE" | grep -qE '(^|[;&|]|&&|\|\|)[[:space:]]*(sudo[[:space:]]+)?(mkdir|touch|cp|install|tee)([[:space:]]+[^=[:space:]]|$)'; then
      KIND="creation"
    else
      # CREATION PAR REDIRECTION — trou mesure a l'audit du 2026-09-22. L'en-tete annoncait
      # couvrir la « truncature par > » depuis le 2026-09-16 ; aucun des deux motifs ne la
      # cherchait. `cat > f`, `echo > f`, `python3 -c "open(...,'w')"` passaient sans un mot.
      #
      # LE MOTIF NAIF EST PIRE QUE LE TROU, et c'est pourquoi on nettoie d'abord : un `>` brut
      # matche `2>/dev/null`, present dans presque toute commande. Le rappel de creation ne
      # tirant qu'UNE fois par session, il tirerait sur la premiere commande de CHAQUE seance —
      # on apprendrait a l'ignorer, ce que `controles-et-alarmes` range comme le vrai cout.
      # On retire donc les redirections qui ne CREENT PAS de fichier nomme : vers /dev/*, et
      # les duplications de descripteur (`2>&1`, `>&-`). Ce qui reste est une ecriture vers un
      # chemin, donc un nommage.
      _red=$(printf '%s' "$SURFACE" | sed -E 's#[0-9]*>>?[[:space:]]*/dev/[a-zA-Z0-9]+##g; s#[0-9]*>&[0-9-]##g')
      if printf '%s' "$_red" | grep -qE '>>?[[:space:]]*[^[:space:]&|>]'; then
        KIND="creation"
      fi
    fi
    ;;
esac

# --- ÉCRITURE D'UNE SOURCE DE VÉRITÉ — AJOUTÉ LE 2026-09-24 (passe mensuelle, option 3) ------
# Un `etat.py add`, ou un Write/Edit sur DESIGN.md, CLAUDE.md, MEMORY.md ou un nom de `reglages/SOURCES_VERITE` :
# le moment du danger de `memoire-et-verite`, la fiche la plus ratée du registre avec
# `fichiers-et-nommage`.
# Les réglages du poste se lisent directement, sans sourcer `config.sh` : ce crochet tourne à
# CHAQUE geste d'outil. `CLAUDEOS_REG` pointe un autre dossier, pour les essais.
_REG="${CLAUDEOS_REG:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/reglages}"
VERITE=0
case "$TOOL" in
  Write|Edit|NotebookEdit)
    _b="$(basename -- "$CMD")"
    case "$_b" in
      DESIGN.md|CLAUDE.md|MEMORY.md) VERITE=1 ;;
      *)
        # Les sources de vérité propres au poste : `reglages/SOURCES_VERITE`, un motif de nom de
        # fichier par ligne (un document de référence de métier, par exemple), facultatif.
        if [ -f "$_REG/SOURCES_VERITE" ]; then
            while IFS= read -r _m; do
                case "$_m" in ''|'#'*) continue ;; esac
                case "$_b" in $_m) VERITE=1; break ;; esac
            done < "$_REG/SOURCES_VERITE"
        fi ;;
    esac ;;
  Bash)
    printf '%s' "${SURFACE:-}" | grep -qE 'etat\.py[[:space:]]+add' && VERITE=1 ;;
esac

# --- MODIFICATION D'UN CONTRÔLE — AJOUTÉ LE 2026-10-01, arbitrage de l'utilisateur ------------
# Un Write/Edit sur un fichier de `engine/hooks/`, sur `weekly-check.sh` ou sur `boot-check.sh` :
# le moment du danger de `controles-et-alarmes`. COÛT MESURÉ du raté du 2026-09-30 : QUATRE
# défauts réels dans des pièces de contrôle écrites sans elle, trouvés le lendemain en les relisant
# contre elle. Chemin ajouté à ce garde, pas un garde neuf — marche 2 de la compétence.
# PAS ANCRÉ SUR `.claude/` : le raté a eu lieu dans une copie du moteur hors de `~/.claude`,
# qu'un ancrage aurait laissée hors du garde.
# CE QU'IL NE COUVRE PAS : une écriture par Bash — `sed -i`, `cp`, redirection. Même périmètre que
# la source de vérité ci-dessus, et pour la même raison : la surface d'une commande efface les
# chemins cités, et mieux la lire reprendrait la partie qui a coûté trois faux positifs.
CONTROLE=0
case "$TOOL" in
  Write|Edit|NotebookEdit)
    printf '%s' "$CMD" | grep -qE '(^|/)engine/(hooks/.+|weekly-check\.sh|boot-check\.sh)$' && CONTROLE=1 ;;
esac
# Zone jetable : un geste qui ne vise QUE /tmp ou le scratchpad ne nomme rien de durable.
if [ -n "$KIND" ]; then
    _cible="$CMD"; [ "$TOOL" = Bash ] && _cible="${SURFACE:-$CMD}"
    # Ce qui rend un geste durable même s'il touche /tmp : `~/.claude`, le dossier personnel, et
    # tout dépôt de travail, reconnu à un préfixe de `PREFIXES`.
    _DURABLE='\.claude/|\$HOME|~/'
    if [ -f "$_REG/REPONSES" ]; then
        while IFS= read -r _p; do
            [ -n "$_p" ] && _DURABLE="$_DURABLE|$_p"
        done < <(awk -F= '$1=="PREFIXES" { sub(/^[^=]*=/, ""); print; exit }' "$_REG/REPONSES" | tr ',' '\n' | sed 's/[[:space:]]//g')
    fi
    if printf '%s' "$_cible" | grep -qE '(^|[[:space:]"'\''])(/private)?/tmp/|/var/folders/' \
       && ! printf '%s' "$_cible" | grep -qE "$_DURABLE"; then
        KIND=""
    fi
fi
[ -z "$KIND" ] && [ "$VERITE" = 0 ] && [ "$CONTROLE" = 0 ] && exit 0

# --- LE REFUS UNIQUE — REMPLACE LE RAPPEL LE 2026-09-24 (`d-refus-unique-declencheur`) ------
# POURQUOI : un `additionalContext` de PreToolUse arrive AVEC le résultat de l'outil, donc APRÈS
# le geste (doc officielle hooks.md, « PreToolUse decision control » ; relevé dans les
# transcriptions le 2026-09-22). Seul `permissionDecision: deny` parle à Claude AVANT. Mesure qui
# l'a imposé : 46 séances sur 67 avec un manque de déclencheur en septembre, le rappel en place.
# LE GESTE : si la compétence n'a pas été chargée dans la session, REFUSER UNE FOIS, raison =
# « charge-la, puis relance ». Au second essai le geste passe, chargée ou non : le marqueur tient
# le compte, pas la transcription — celle-ci est écrite en différé (doc : « may lag »), et s'y
# fier seule ferait refuser en boucle une compétence chargée à l'instant.
# LA TRANSCRIPTION NE SERT QU'À ÉPARGNER LE REFUS quand la compétence est déjà chargée.
# ET RIEN NE SE REFUSE SUR UNE LECTURE RATÉE (`controles-et-alarmes`) : transcription illisible,
# ou geste DANS UN SOUS-AGENT (`agent_id` présent — il n'a pas forcément l'outil Skill, un refus
# le bloquerait), on revient au rappel simple.
AGENT=$(printf '%s' "$IN" | python3 -c "import json,sys;print(json.load(sys.stdin).get('agent_id',''))" 2>/dev/null)
TRANS=$(printf '%s' "$IN" | python3 -c "import json,sys;print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null)
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/claudeos"

charge() {  # rc 0 = chargée ; 1 = absente ; 2 = on n'a pas pu lire
    [ -n "$TRANS" ] && [ -r "$TRANS" ] || return 2
    grep -qE "\"name\":\"Skill\",\"input\":\{\"skill\":\"$1\"|<command-name>/?$1</command-name>" "$TRANS" && return 0
    return 1
}
rappel() {
    python3 -c '
import json,sys
print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":sys.argv[1]}}))
' "Geste couvert par la compétence \`$1\` ($2). La charger par l'outil Skill si elle n'est pas en contexte."
    exit 0
}
refus() {
    mkdir -p "$CACHE" 2>/dev/null; : > "$CACHE/refus-$1-${SESS}"
    python3 -c '
import json,sys
print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
  "permissionDecisionReason":sys.argv[1]}}))
' "REFUS UNIQUE, pas une erreur — geste de $2 sans la compétence \`$1\` chargée dans cette session. La charger par l'outil Skill, PUIS relancer exactement le même geste : il passera. Ce refus n'arrive qu'une fois par compétence et par session."
    exit 0
}
exige() {   # $1 compétence, $2 libellé du geste
    [ -f "$CACHE/refus-$1-${SESS}" ] && return 0
    [ -n "$AGENT" ] && rappel "$1" "$2"
    charge "$1"; case $? in
        0) mkdir -p "$CACHE" 2>/dev/null; : > "$CACHE/refus-$1-${SESS}"; return 0 ;;
        2) rappel "$1" "$2" ;;
        *) refus "$1" "$2" ;;
    esac
}

[ "$VERITE" = 1 ] && exige memoire-et-verite "écriture d'une source de vérité"
[ -n "$KIND" ] && exige fichiers-et-nommage "$KIND de fichier"
[ "$CONTROLE" = 1 ] && exige controles-et-alarmes "modification d'un contrôle ou d'une alarme"
exit 0
