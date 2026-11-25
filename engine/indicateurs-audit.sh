#!/usr/bin/env bash
# Les trois indicateurs de la passe mensuelle `os-audit`.
# Lecture seule. Usage : bash ~/.claude/engine/indicateurs-audit.sh [AAAA-MM]  (défaut : mois courant)
#   I1 frictions par séance du mois — manque_reprise + manque_declencheur des événements `seance`
#      de tous les journaux du parc ; cible : baisse.
#   I2 octets chargés à chaque session — règlement, RTK.md, index mémoire, lignes `description:`
#      des compétences maison ET synchronisées de claude.ai (`skills/synced/`), sortie du
#      démarrage ; cible : baisse ou stabilité.
#   I3 octets d'INSTRUCTIONS suivies — les .md de skills/, engine/, domaines/, plus DESIGN.md ;
#      cible : baisse. Le code s'affiche à côté ; tests et journal ne comptent pas, sans quoi
#      supprimer un test se lirait comme un progrès. Base passée, sur un dépôt git seulement :
#      bash <ce script> --i3 <commit>.
# La première passe pose la base ; ensuite, la base est le condensé de la passe précédente.
# LES JOURNAUX DU PARC se lisent sous `~/.claude` et sous chaque dossier de travail que rend
# `claudeos_ws_roots` — jamais sous des noms de dépôt écrits en dur.
set -u
cd "$HOME/.claude/" || exit 1
# shellcheck source=/dev/null
source "$HOME/.claude/engine/config.sh"
CLAUDEOS_RACINES="$(printf '%s\n' "$HOME/.claude"; claudeos_ws_roots 2>/dev/null)"
export CLAUDEOS_RACINES

# I3 — une seule implantation, pour l'arbre de travail comme pour un commit passé : une mesure
# comparative se change des deux côtés ou d'aucun (`controles-et-alarmes`).
i3() {  # i3 [commit] — sans argument : l'arbre de travail
    # Sans git (`GIT=aucun`), l'arbre suivi est le périmètre de `claudeos_suivis` (`lib_regime.sh`).
    local suivis=""
    [ -n "${1:-}" ] || [ -e .git ] || suivis="$(claudeos_suivis . skills engine domaines DESIGN.md)"
    CLAUDEOS_SUIVIS="$suivis" python3 - "${1:-}" <<'EOF'
import os, subprocess, sys
rev = sys.argv[1]
if rev and not os.path.exists('.git'):
    sys.exit("I3 @" + rev + " : la mesure à un commit passé demande un dépôt git, ce poste est en GIT=aucun")
if rev:
    out = subprocess.run(['git', 'ls-tree', '-r', '-l', rev, '--', 'skills', 'engine', 'domaines',
                          'DESIGN.md'], capture_output=True, text=True, check=True).stdout
    taille = {l.split('\t', 1)[1]: int(l.split()[3]) for l in out.splitlines() if l.split()[1] == 'blob'}
else:
    if os.path.exists('.git'):
        noms = subprocess.run(['git', 'ls-files', '-z', 'skills', 'engine', 'domaines', 'DESIGN.md'],
                              capture_output=True, text=True, check=True).stdout.split('\0')
    else:
        noms = os.environ.get('CLAUDEOS_SUIVIS', '').split('\n')
    taille = {p: os.path.getsize(p) for p in noms if p and os.path.isfile(p)}
md = code = tests = jour = 0
for p, s in taille.items():
    if '/journal/' in p: jour += s
    elif '/tests/' in p or os.path.basename(p).startswith('test_'): tests += s
    elif p.endswith('.md'): md += s
    else: code += s
print(f"I3{' @' + rev if rev else ''} : {md} octets d'instructions .md  (code {code} ; "
      f"hors compte : tests {tests}, journal {jour})")
EOF
}
if [ "${1:-}" = "--i3" ]; then i3 "${2:?commit attendu}"; exit $?; fi
MOIS="${1:-$(date +%Y-%m)}"

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
b=$(/usr/bin/grep -h '^description:' skills/*/SKILL.md skills/synced/*/*/SKILL.md 2>/dev/null | wc -c | tr -d ' ')
c=$(bash engine/boot-check.sh 2>/dev/null | wc -c | tr -d ' ')
echo "I2 : $((a + b + c)) octets charges a chaque session  (regles+index $a, descriptions $b, demarrage $c)"

i3
