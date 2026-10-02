#!/usr/bin/env bash
# Les trois indicateurs de la passe mensuelle `os-audit`.
# Lecture seule. Usage : bash ~/.claude/engine/indicateurs-audit.sh [AAAA-MM]  (défaut : mois courant)
#   I1 frictions par séance du mois — manque_reprise + manque_declencheur des événements `seance`
#      de tous les journaux du parc ; cible : baisse.
#   I2 octets chargés à chaque session — règlement, RTK.md, index mémoire, lignes `description:`,
#      sortie du démarrage ; cible : baisse ou stabilité.
#   I3 octets suivis du système vivant — skills/, engine/, domaines/, DESIGN.md ; cible : baisse.
# La première passe pose la base ; ensuite, la base est le condensé de la passe précédente.
# LES JOURNAUX DU PARC se lisent sous `~/.claude` et sous chaque dossier de travail que rend
# `claudeos_ws_roots` — jamais sous des noms de dépôt écrits en dur.
set -u
MOIS="${1:-$(date +%Y-%m)}"
cd "$HOME/.claude/" || exit 1
# shellcheck source=/dev/null
source "$HOME/.claude/engine/config.sh"
CLAUDEOS_RACINES="$(printf '%s\n' "$HOME/.claude"; claudeos_ws_roots 2>/dev/null)"
export CLAUDEOS_RACINES

python3 - "$MOIS" <<'EOF'
import json, glob, os, sys
mois = sys.argv[1]
racines = [r for r in os.environ.get('CLAUDEOS_RACINES', '').split('\n') if r]
fs = {os.path.realpath(f) for r in racines
      for f in glob.glob(r + '/**/journal/*.jsonl', recursive=True)}
def entier(x):
    try: return int(x)
    except (TypeError, ValueError): return 0   # « non relu » ou texte : compté 0, signalé ci-dessous
n = r = d = nr = 0
for f in fs:
    for l in open(f):
        try: e = json.loads(l)
        except ValueError: continue
        if e.get('type') == 'seance' and e.get('ts', '').startswith(mois):
            n += 1
            for k in ('manque_reprise', 'manque_declencheur'):
                if not isinstance(e.get(k), int): nr += 1
            r += entier(e.get('manque_reprise')); d += entier(e.get('manque_declencheur'))
if n == 0:   # zéro séance = pas de mesure, jamais « zéro friction »
    print(f"I1 {mois} : NON MESURABLE, aucune seance au journal ({len(fs)} journaux lus)")
else:
    print(f"I1 {mois} : {(r + d) / n:.2f} frictions/seance  ({n} seances, reprise {r}, declencheur {d}, {nr} champs non entiers, {len(fs)} journaux)")
EOF

a=$(cat CLAUDE.md RTK.md memory/MEMORY.md 2>/dev/null | wc -c | tr -d ' ')
b=$(/usr/bin/grep -h '^description:' skills/*/SKILL.md | wc -c | tr -d ' ')
c=$(bash engine/boot-check.sh 2>/dev/null | wc -c | tr -d ' ')
echo "I2 : $((a + b + c)) octets charges a chaque session  (regles+index $a, descriptions $b, demarrage $c)"

# Sans git (`GIT=aucun`), les fichiers suivis sont ceux du périmètre (`claudeos_suivis`, `lib_regime.sh`).
if [ -e .git ]; then s=$(git ls-files -z skills engine domaines DESIGN.md | xargs -0 cat | wc -c | tr -d ' ')
else s=$(claudeos_suivis . skills engine domaines DESIGN.md | tr '\n' '\000' | xargs -0 cat | wc -c | tr -d ' '); fi
echo "I3 : $s octets suivis  (skills, engine, domaines, DESIGN.md)"
