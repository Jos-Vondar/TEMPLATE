#!/usr/bin/env bash
# Rappel de journalisation APRÈS chaque AskUserQuestion — crochet PostToolUse.
# Une décision journalisée à la clôture plutôt qu'au moment où elle est rendue manque à la reprise.
# Un PostToolUse livre son `additionalContext` AVEC le résultat de l'outil, donc avec la réponse :
# c'est exactement le moment où la décision existe.
# NE BLOQUE JAMAIS, n'avertit que la session principale ou de projet : dans un sous-agent
# (`agent_id` présent) il se tait. Bruit assumé : il tombe aussi après une question triviale.
IN=$(cat)
AGENT=$(printf '%s' "$IN" | python3 -c "import json,sys;print(json.load(sys.stdin).get('agent_id',''))" 2>/dev/null)
[ -n "$AGENT" ] && exit 0
python3 -c '
import json
print(json.dumps({"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":
 "Si cette réponse tranche une décision, ou ouvre ou solde un dû : etat.py add au niveau concerné avant d'\''agir."}}, ensure_ascii=False))'
