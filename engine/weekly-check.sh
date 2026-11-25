#!/usr/bin/env bash
# GARDE D'ANALYSE — en tête à dessein. Bash 3.2, celui de macOS, apparie les accents graves
# jusque dans un heredoc quoté placé dans une substitution `$( … )` : les blocs Python vivent donc
# dans des fonctions `_claudeos_py_*`, dont le corps échappe à ce balayage. Bash exécute commande
# par commande : un bloc fautif ajouté plus tard ferait mourir le script à mi-parcours, sans
# verdict, et une passe partielle se lirait comme complète. Le crochet de commit analyse avec le
# bash 5 du poste et ne le voit pas : le bash qui EXÉCUTE analyse donc d'abord le fichier entier.
# RÈGLE pour tout bloc neuf : un programme Python se met dans une fonction, jamais dans un `$( … )`.
if ! "${BASH:-bash}" -n "${BASH_SOURCE[0]}" 2>/dev/null; then
    echo "[weekly] ⛔ REFUS — ce fichier ne s'analyse pas sous bash ${BASH_VERSION:-inconnu}." >&2
    echo "[weekly] Il mourrait à mi-parcours SANS rendre de verdict : RIEN n'a été contrôlé." >&2
    echo "[weekly] Cause probable : un bloc Python dans un \$( … ) — le mettre dans une fonction." >&2
    exit 1
fi
# =============================================================================
# WEEKLY-CHECK — les contrôles de CONTENU du système ClaudeOS.
#
# Chaque contrôle vit là où il répond à la vitesse voulue :
#   • ce qui regarde CE QUI PART           → `hooks/pre-commit-alarmes.sh`, au commit ;
#   • ce qui regarde L'ARBRE VIVANT         → `controle-secrets.sh`, à la clôture ;
#   • ce qui regarde LES DOCUMENTS          → ICI, à la passe hebdomadaire.
#
# Un contrôle de contenu ne coûte jamais le droit d'enregistrer son travail : un document qui
# ment se corrige, il ne se perd pas (compétence `controles-et-alarmes` — un défaut de contenu
# avertit, une corruption de plomberie bloque). Ici, presque tout avertit.
#
# APPELANT : la fiche d'hygiène de la compétence `os-audit`. Lançable à la main :
#   bash ~/.claude/engine/weekly-check.sh
#
# CODE RETOUR : 0 si rien de bloquant, 1 sinon. Les avertissements ne changent pas
# le code — ils se lisent.
# =============================================================================
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

FAIL=0
ok() { echo "  ✅ $1"; }
ko() { echo "  ❌ $1" >&2; FAIL=1; }
# warn : signale sans faire échouer. `ko` est réservé à ce dont le passage cause une PERTE
# IRRÉVERSIBLE, une FUITE, ou le DÉSARMEMENT SILENCIEUX d'une garde ; tout le reste avertit.
warn() { echo "  ⚠️  $1" >&2; }
# sans_objet CLE [partie] — vrai quand la réponse CLE vaut `non` : la règle que le contrôle garde
# n'est pas entrée chez l'installateur, donc il se SAUTE, et il le dit — jamais un vert muet.
# Une clé ABSENTE n'est pas `non` : le contrôle joue, un poste non réglé ne se devine pas.
sans_objet() {
    local v
    v="$(claudeos_reponse "$1")" || return 1
    [ "$v" = non ] || return 1
    echo "  ⏭  sans objet : $1=non${2:+ — $2}"
}

# Racines des DOSSIERS DE TRAVAIL, lues sur le disque par `claudeos_ws_roots` selon `GIT` : sous le
# dossier personnel par préfixe en `par-domaine`, sous `~/.claude/travail/` sinon. Leur discriminant
# est un `CLAUDE.md` à la racine. La profondeur se fixe chez chaque appelant.
_WS=()
while IFS= read -r _r0; do
    [ -n "$_r0" ] && [ -d "$_r0" ] && _WS+=("$_r0")
done < <(claudeos_ws_roots)
if [ "${#_WS[@]}" -eq 0 ]; then
    echo "  ⏭  aucun dépôt client sur le disque : les contrôles à ce périmètre sont sans objet."
    echo "     Un dossier de travail porte un CLAUDE.md à sa racine (claudeos_ws_roots, selon GIT)."
fi
# DOCUMENTS DE RÉFÉRENCE de l'installateur, balayés en plus de `CLAUDE.md` et `DESIGN.md` : un motif
# de nom par ligne dans `reglages/DOCS_REFERENCE` (`SPEC_*.md`, `REFERENCE.md`…), `#` en tête pour
# un commentaire. Facultatif : absent, seuls les noms du template sont balayés.
_DOCS_REF=""
[ -f "$REG/DOCS_REFERENCE" ] && _DOCS_REF="$(grep -vE '^[[:space:]]*(#|$)' "$REG/DOCS_REFERENCE")"
_DOCS_FIND=(-name CLAUDE.md -o -name DESIGN.md)
while IFS= read -r _dr; do [ -n "$_dr" ] && _DOCS_FIND+=(-o -name "$_dr"); done <<< "$_DOCS_REF"

# CAPTURE UNIQUE de `boot-check.sh`, partagée par les contrôles qui lisent sa sortie : il est en
# lecture seule et déterministe à l'échelle d'une passe, et l'appeler plusieurs fois refait ses
# scans et ses `git fetch`. Une capture ratée laisse la variable vide, et ces contrôles échouent.
_BOOTOUT="$(CLAUDEOS_BILAN_DEMANDE=1 bash "$SELF/boot-check.sh" </dev/null 2>/dev/null)"

# CORPUS DES RÈGLES SITUATIONNELLES — partagé par les contrôles 23, 25 et 27. Discriminant
# intrinsèque au corps, pas une liste de slugs (un inventaire recopié est ce que le contrôle 25
# refuse) : chaque règle situationnelle ouvre sur une ligne « > Fiche situationnelle ».
# L'ANCRE DE DÉBUT DE LIGNE EST PORTEUSE : sans elle, `os-audit` entre au corpus parce qu'il nomme
# cette formule en prose, et l'assiette double presque.
_SITU="$(grep -rlE '^> Fiche situationnelle' "$HOME/.claude/skills"/*/SKILL.md 2>/dev/null | sort)"
# Un corpus VIDE est une mesure ratée, pas un petit corpus : il désarmerait trois contrôles sans
# rien dire. Il bloque.
[ -n "$_SITU" ] || ko "aucune règle situationnelle trouvée dans ~/.claude/skills/ (motif '^> Fiche situationnelle') — les contrôles 23, 25 et 27 seraient muets"

echo "[selftest] 2. Dépendances dures"
# git n'est une dépendance qu'en régime GitHub : sans git (`GIT=aucun`), son absence est le choix.
_deps="python3 git"; [ "$(claudeos_regime)" = aucun ] && { _deps="python3"; echo "  ⏭  sans objet : git — régime sans git (GIT=aucun)"; }
for dep in $_deps; do
    if command -v "$dep" >/dev/null 2>&1; then ok "$dep présent"; else ko "$dep MANQUANT"; fi
done

# `_CMD` — le règlement racine, lu par plusieurs contrôles.
_CMD="$HOME/.claude/CLAUDE.md"

echo "[selftest] 22. Portabilité — aucun chemin propre à un poste dans les fichiers d'instruction"
# Lit MULTIPOSTE dans `reglages/REPONSES`, par `sans_objet` : à `non`, la règle qu'il garde (« aucun
# chemin propre à un poste ») n'est pas entrée chez l'installateur, et le contrôle se saute en le
# disant. Une clé absente le fait jouer.
# AVERTIT : un chemin propre à un poste est un défaut DOCUMENTAIRE, le contrôle 27 attrape ce
# qui pointe dans le vide ; bloquer ici ferait payer une erreur de carte par une interdiction de
# sauvegarder.
# Corps NON réindenté sous le `if` : un commit de la source se reporte ainsi tel quel (passe de
# report).
if ! sans_objet MULTIPOSTE; then
_p=0
# Motif générique : tout '-home-…' / '-Users-…' dans une instruction est un nom de dossier de
# mémoire figé — le slug se résout, il ne s'écrit pas.
_h3=$(grep -rlE -- 'projects/-(home|Users|c|mnt)[A-Za-z0-9_-]*/' "$_CMD" "$HOME/.claude/skills" 2>/dev/null | sort -u)
[ -n "$_h3" ] && { warn "nom de dossier de mémoire figé (résoudre le slug, ne pas l'écrire) : $(echo "$_h3" | tr '\n' ' ')"; _p=1; }
# Chemins absolus dans les fichiers d'instruction : règlement, TOUTES les compétences, DESIGN.md,
# `settings.json`, les `CLAUDE.md` des dossiers de travail et leurs documents de référence
# (`reglages/DOCS_REFERENCE`). Le motif seul ne suffit pas, c'est le PÉRIMÈTRE qui laisse passer :
# un chemin de poste dans un fichier non regardé fait conclure à tort sur un autre poste.
# `settings.json` est SUIVI, donc il voyage : un chemin de dossier personnel y est un défaut d'où
# qu'il vienne, et crie sur chaque poste. `settings.local.json` ne voyage pas et reste dehors.
# `$_SITU` n'est PAS élargi ici : il sert aux contrôles 23, 25 et 27, dont la sémantique porte
# sur les seules règles situationnelles.
_h2f=$(ls "$HOME"/.claude/skills/*/SKILL.md 2>/dev/null; echo "$_CMD"; echo "$HOME/.claude/DESIGN.md"; \
       echo "$HOME/.claude/settings.json"; \
       [ "${#_WS[@]}" -gt 0 ] && find -L "${_WS[@]}" \( "${_DOCS_FIND[@]}" \) 2>/dev/null)
# Le motif tolère une barre ÉCHAPPÉE `\/` : un sérialiseur JSON peut réécrire `settings.json`
# en échappant les `/`, et le motif nu rendrait 0 sur un fichier qui porte des chemins de poste.
_h2=$(printf '%s\n' "$_h2f" | sed '/^$/d' | xargs grep -lE -- '\\?/home\\?/[a-z_][a-z0-9_-]*|\\?/Users\\?/[A-Za-z]' 2>/dev/null | sort -u)
[ -n "$_h2" ] && { warn "chemin absolu en dur dans le règlement, une règle situationnelle ou une instruction de domaine : $(echo "$_h2" | tr '\n' ' ')"; _p=1; }
# SCRIPTS DU MOTEUR : la règle « aucun chemin propre à un poste » y est tenue par la machine. Le
# périmètre ci-dessus ne voit aucun script, et le contrôle 27 ne verrait un chemin d'un autre
# poste que là où il est mort.
# Les lignes de COMMENTAIRE sont écartées : elles citent des chemins d'un autre poste à dessein.
_h2s=""
for _f in "$HOME"/.claude/engine/*.sh "$HOME"/.claude/engine/hooks/*.sh; do
    [ -f "$_f" ] || continue
    if grep -vE '^[[:space:]]*#' -- "$_f" | grep -qE -- '/home/[a-z_][a-z0-9_-]*/|/Users/[A-Za-z]'; then
        _h2s="$_h2s $(basename "$_f")"
    fi
done
[ -n "$_h2s" ] && { warn "chemin absolu en dur dans un script du moteur, hors commentaires :$_h2s"; _p=1; }
# `find` SANS `-L` partant d'une racine liée : quand `~/.claude` ou un dossier de travail
# `~/<PRÉFIXE>*` est un LIEN, un `find` qui part de lui sans `-L` rend ZÉRO avec rc=0 — un
# contrôle muet rend un vert. Commentaires écartés, même motif qu'au-dessus.
# SEUL LE POINT DE DÉPART COMPTE : `find` suit les composants intermédiaires d'un chemin de
# départ, seul le dernier n'est pas suivi s'il est un lien. Le motif ne vise donc que les départs
# qui SONT une racine liée.
# PAS DE `grep -P` : le grep de macOS le refuse (rc=2), et avec un `2>/dev/null` le `if` passerait
# au vert sans rien lire. D'où deux `grep -E` en chaîne, et aucune sortie d'erreur masquée.
# Un garde se teste DANS son script : un shell interactif peut router `grep` vers `ugrep`, qui tolère.
# Les départs sous `"$HOME"/<PRÉFIXE>` se lisent dans `PREFIXES`, échappés pour l'ERE.
_h2Lre='"\$HOME/\.claude"|\$\{_WS\[@\]\}|claudeos_ws_roots|claudeos_repos'
while IFS= read -r _px; do
    [ -n "$_px" ] && _h2Lre="$_h2Lre|\"\\\$HOME\"/$(printf '%s' "$_px" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
done < <(claudeos_liste PREFIXES)
_h2L=""
for _f in "$HOME"/.claude/engine/*.sh "$HOME"/.claude/engine/hooks/*.sh; do
    [ -f "$_f" ] || continue
    if grep -vE '^[[:space:]]*#' -- "$_f" \
       | grep -E "find[[:space:]]+[^|;&]*($_h2Lre)" \
       | grep -vqE 'find[[:space:]]+-L'; then
        _h2L="$_h2L $(basename "$_f")"
    fi
done
[ -n "$_h2L" ] && { warn "\`find\` SANS \`-L\` partant d'une racine liée — muet, donc vert à tort :$_h2L"; _p=1; }
[ "$_p" = 0 ] && ok "règlement, règles situationnelles et instructions de domaine sans chemin propre à un poste"
fi

echo "[selftest] 23. Routage — règles situationnelles et registre des ratés"
# Trois moitiés, toutes BLOQUANTES (`controles-et-alarmes` : une règle existe, le système croit
# l'appliquer, elle ne se charge jamais) :
#   (a) toute règle situationnelle porte une `description` non vide — elle seule la route ;
#   (b) toute compétence citée par une instruction du système existe sur le disque ;
#   (c) tout dossier de `skills/` porte un `SKILL.md` au nom EXACT (la casse compte) : un dossier
#       resté sans lui, après une suppression en deux temps, n'échoue nulle part et ressemble à
#       une compétence.
# `synced` est EXCLU : le harnais y dépose les compétences synchronisées du compte, sous un
# dossier à UUID, un cran plus bas — ce n'est pas une compétence maison amputée.
_rt=0
while IFS= read -r _d; do
    [ -n "$_d" ] || continue
    [ -f "$_d/SKILL.md" ] || { ko "dossier de compétence SANS SKILL.md exact : skills/$(basename "$_d") — l'outil ne le charge pas, et rien d'autre ne le dit"; _rt=1; }
done < <(/usr/bin/find -L "$HOME/.claude/skills" -mindepth 1 -maxdepth 1 -type d -not -name synced 2>/dev/null)
while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    grep -qE '^description: *[^[:space:]]' "$_f" \
        || { ko "règle situationnelle sans description — donc sans déclencheur : $(basename "$(dirname "$_f")")"; _rt=1; }
done <<< "$_SITU"
# (b) MOTIF : « compétence `slug` » en toutes lettres, forme sous laquelle les instructions du
# système nomment une compétence. Ni slug nu entre guillemets obliques (trop courant pour
# discriminer), ni « fiche `slug` » (la même forme désigne aussi des non-compétences).
while read -r _n; do
    [ -z "$_n" ] && continue
    [ -f "$HOME/.claude/skills/$_n/SKILL.md" ] \
        || { ko "compétence citée par une instruction mais absente du disque : $_n"; _rt=1; }
# LES FICHIERS GELÉS SORTENT DU PÉRIMÈTRE : leur métier est de raconter le passé, donc de nommer
# des compétences supprimées. Le filtre est l'en-tête de gel en PREMIÈRE ligne, jamais une liste
# de noms.
done < <(for _gf in "$_CMD" "$HOME/.claude/DESIGN.md" \
                    "$HOME/.claude/MEMORY.md" "$HOME/.claude/skills"/*/SKILL.md \
                    "$HOME/.claude/skills"/*/*.md "$HOME/.claude/agents"/*.md; do
             [ -f "$_gf" ] || continue
             head -1 "$_gf" | grep -qF '> **GELÉ' && continue
             printf '%s\n' "$_gf"
         done | xargs -r grep -rhoE 'compétences? `[a-z][a-z0-9-]+`' 2>/dev/null \
           | grep -oE '`[a-z][a-z0-9-]+`' | tr -d '`' | sort -u)
# LIMITE : seule la forme « compétence `slug` » est vue ; une compétence désignée sans slug reste
# invisible à tout motif — cette classe se ferme à l'écriture, pas au contrôle.
# Le registre des ratés n'est exigé que si la règle qui l'alimente existe. Lit MULTIDOMAINE dans
# `reglages/REPONSES`, par `sans_objet` : à `non`, la règle n'est pas entrée chez l'installateur,
# et la partie du registre se saute en le disant. Une clé absente le fait jouer.
_rt_reg=""
if ! sans_objet MULTIDOMAINE "registre des ratés de routage"; then
    [ -f "$MEM/ROUTING_MISSES.md" ] || { ko "registre des ratés de routage absent ($MEM/ROUTING_MISSES.md)"; _rt=1; }
    grep -q 'ROUTING_MISSES' "$HOME/.claude/skills/os-audit/SKILL.md" 2>/dev/null \
        || { ko "l'audit ne lit pas le registre des ratés — la boucle de correction est morte"; _rt=1; }
    _rt_reg=", registre des ratés lu par l'audit"
fi
[ "$_rt" = 0 ] && ok "règles situationnelles toutes routées par leur description, compétences citées toutes présentes$_rt_reg"

echo "[selftest] 25. La documentation suit-elle le code ?"
# Le code bouge, les documents qui le décrivent restent : on garde des affirmations vérifiables
# mécaniquement plutôt que d'espérer une relecture.
_doc=0
# Le bandeau `[selftest] N.` est gardé pour que chaque contrôle reste retrouvable par son numéro.
# Un nombre calculable depuis le disque ne s'écrit pas ailleurs : la copie se périme. On refuse
# donc tout compteur en dur, au lieu de tenir les copies en phase.
while IFS= read -r _f; do
    [ -f "$_f" ] || continue
    # Tout inventaire dont le compte se dérive du disque est visé. Le motif cible des noms
    # d'inventaire précis, pas « un nombre suivi d'un mot » : les nombres qui documentent une
    # décision (un seuil, une durée) restent légitimes.
    _claim=$(grep -oiE '\b[0-9]+ (contrôles|tests|fiches|compétences|domaines)\b' "$_f" 2>/dev/null | head -3)
    # Les nombres ÉCRITS EN MOTS sont ambigus (« les trois contrôles qui gardent cette zone » est
    # un sous-ensemble) : on ne les retient que là où le total est certain, un compte de règles
    # sur la même ligne que le dossier qui les contient. Deux formes : `fiches` près de `fiches/`
    # (un document qui raconte l'avant-conversion) et `compétences` près de `skills/`.
    # Borne de proximité en CARACTÈRES, pas « jusqu'au prochain point » : le chemin du dossier
    # contient des points, et un motif borné par `[^.]*` ne l'atteindrait jamais.
    _claim="$_claim$(grep -oiE '\b(deux|trois|quatre|cinq|six|sept|huit|neuf|dix|onze|douze) (fiches\b.{0,60}fiches/|compétences\b.{0,60}skills/)' "$_f" 2>/dev/null | head -2)"
    [ -n "$_claim" ] && { warn "inventaire écrit en dur dans $(basename "$_f") ($(echo "$_claim" | tr '\n' ' ')) — il se compte à sa source ; retirer le nombre, ne pas le mettre à jour"; _doc=1; }
done <<EOF
$HOME/.claude/DESIGN.md
EOF
_D="$HOME/.claude/DESIGN.md"
# Anti-régression : le déclencheur d'une règle situationnelle vit dans la `description` de son
# frontmatter. Un inventaire de DESIGN.md qui en recopierait l'ouverture en ferait une seconde
# source du routage.
_claudeos_py_dup() {
python3 - "$_D" $_SITU <<'PYDUP' 2>/dev/null
import os, re, sys
design = open(sys.argv[1], encoding="utf-8").read()
out = []
for p in sys.argv[2:]:
    txt = open(p, encoding="utf-8").read()
    m = re.search(r'^description: *(.+)$', txt, re.M)
    if not m:
        continue
    # Fragment SUFFISAMMENT LONG pour ne pas coïncider par hasard : une description
    # entière ne serait jamais recopiée mot pour mot, c'est son ouverture qui migre.
    frag = m.group(1).strip()[:60]
    if len(frag) > 40 and frag in design:
        out.append(os.path.basename(os.path.dirname(p)))
print(" · ".join(out))
PYDUP
}
_dup=$(_claudeos_py_dup)
[ -n "$_dup" ] && { warn "déclencheur de règle situationnelle recopié dans DESIGN.md ($_dup) — il vit dans la description de la compétence, seule source du routage"; _doc=1; }
[ "$_doc" = 0 ] && ok "aucun inventaire en dur, inventaire situationnel de DESIGN.md complet dans les deux sens, aucun déclencheur recopié"

echo "[selftest] 27. Chemins morts dans les fichiers d'instruction"
# Chemins cités par les RÈGLES et les procédures : règlement, règles situationnelles passées par
# `$_SITU`, `resources/*.md`, `CLAUDE.md` des dossiers de travail. Élargir à tout `skills/` est une
# décision à part.
# Les racines de dépôt passent par l'ENVIRONNEMENT et non par argv : `$_SITU` y est volontairement
# non quoté (un fichier par mot), et y mêler des racines rendrait argv ambigu.
_claudeos_py_dead() {
CLAUDEOS_WS_ROOTS="$(printf '%s\n' ${_WS[@]+"${_WS[@]}"})" CLAUDEOS_DOCS_REF="$_DOCS_REF" \
    CLAUDEOS_AU_BESOIN="${CLAUDEOS_CHEMINS_AU_BESOIN:-}" python3 - $_SITU <<'PYEOF' 2>/dev/null
import re, os, glob, sys
H = os.path.expanduser('~')
files = [f'{H}/.claude/CLAUDE.md'] + sys.argv[1:] + glob.glob(f'{H}/.claude/resources/*.md')
for _root in os.environ.get('CLAUDEOS_WS_ROOTS', '').splitlines():
    if not _root.strip(): continue
    files += glob.glob(f'{_root}/CLAUDE.md') + glob.glob(f'{_root}/*/CLAUDE.md')
skip = re.compile(r'[<>*{}]|MÉMOIRE|slug')       # gabarits et jokers : pas des chemins réels
out = []

# EXTENSION : mémoires thématiques, scripts du moteur et documents de référence des dossiers de
# travail, à leur racine (`reglages/DOCS_REFERENCE`). Ils n'entrent PAS dans `files` : trois
# filtres les bornent, sans quoi le contrôle déverse l'histoire.
#   (i)   vivant seulement — un en-tête de gel ou `ARCHIVE` dans le nom sort le fichier ;
#   (ii)  chemins qui DOIVENT exister sur ce poste — sous `~/.claude/` ou sous un dossier de
#         travail ; un chemin distant (un serveur, un autre poste) n'est pas un chemin mort ;
#   (iii) pour les scripts, hors lignes de commentaire — elles racontent des chemins morts à dessein.
# Les filtres ne s'appliquent qu'à l'extension : les étendre au périmètre d'origine éteindrait en
# silence des alertes qu'il rend déjà.
_racines = [f'{H}/.claude'] + [r.strip() for r in os.environ.get('CLAUDEOS_WS_ROOTS', '').splitlines() if r.strip()]
extra = glob.glob(f'{H}/.claude/memory/*.md') + glob.glob(f'{H}/.claude/engine/*.sh')
for _root in _racines:
    for _m in os.environ.get('CLAUDEOS_DOCS_REF', '').splitlines():
        if _m.strip():
            extra += glob.glob(f'{_root}/{_m.strip()}')

def _vivant(path):
    if 'ARCHIVE' in os.path.basename(path).upper(): return False
    try:
        with open(path, encoding='utf-8') as fh:
            for line in fh:
                if not line.strip(): continue
                return not line.startswith('> **GELÉ')
    except OSError:
        return False
    return True

def _sous_racine(p):
    a = os.path.realpath(os.path.expanduser(p.rstrip('.,;:')))
    return any(a == r or a.startswith(r + '/') for r in (os.path.realpath(x) for x in _racines))

for f in sorted(set(extra)):
    if not _vivant(f): continue
    _code_seul = f.endswith('.sh')
    try: lignes = open(f, encoding='utf-8').read().splitlines()
    except OSError: continue
    for line in lignes:
        if _code_seul and line.lstrip().startswith('#'): continue
        for m in re.finditer(r'`(~/[^`\s]+)`', line):
            p = m.group(1)
            if skip.search(p): continue
            if not _sous_racine(p): continue
            if not os.path.exists(os.path.expanduser(p.rstrip('.,;:'))):
                out.append(f"{os.path.relpath(f, H)} → {p}")

for f in files:
    try: txt = open(f, encoding='utf-8').read()
    except OSError: continue
    for m in re.finditer(r'`(~/[^`\s]+)`', txt):
        p = m.group(1)
        if skip.search(p): continue
        if not os.path.exists(os.path.expanduser(p.rstrip('.,;:'))):
            out.append(f"{os.path.relpath(f, H)} → {p}")
# LES CHEMINS NÉS AU PREMIER BESOIN : une installation neuve ne
# les porte pas encore, et certains n'existent jamais dans un régime — `RTK.md` sans proxy, les
# empreintes de clôture en régime GitHub. Les crier ferait une fausse alarme PERMANENTE, qui éteint
# sa catégorie : ils sont comptés à part, et le compte s'affiche. Liste : `config.sh`.
_besoin = set(os.environ.get('CLAUDEOS_AU_BESOIN', '').split())
def _au_besoin(p):
    p = p.rstrip('.,;:')
    return any(p == b or (b.endswith('/') and p.startswith(b)) for b in _besoin)
_vus = sorted(set(out))
print('\n'.join(l for l in _vus if not _au_besoin(l.split(' → ', 1)[1])))
print('#AU_BESOIN %d' % sum(1 for l in _vus if _au_besoin(l.split(' → ', 1)[1])))
PYEOF
}
_dead_tout=$(_claudeos_py_dead)
_dead=$(printf '%s\n' "$_dead_tout" | grep -v '^#AU_BESOIN ' | grep -v '^[[:space:]]*$')
_au_besoin=$(printf '%s\n' "$_dead_tout" | sed -n 's/^#AU_BESOIN //p')
[ "${_au_besoin:-0}" -gt 0 ] 2>/dev/null \
    && echo "  ⏭  ${_au_besoin} chemin(s) cité(s) qui naissent au premier besoin, encore absents — non comptés (CLAUDEOS_CHEMINS_AU_BESOIN)"
if [ -n "$_dead" ]; then
    # AVERTIT : un pointeur mort envoie la session dans le vide, il ne désactive ni ne détruit rien.
    warn "chemin cité par une règle mais absent du disque :"; echo "$_dead" | sed 's/^/       /' >&2
else ok "tous les chemins cités par les règles et les procédures existent"; fi

echo "[selftest] 27bis. Chemins DÉCHUS — cités par une instruction vivante alors que leur autorité est morte"
# Le contrôle 27 teste `os.path.exists` : une autorité MORTE mais présente sur le disque (une
# ancienne installation laissée en place) y passe au vert. Pire qu'un vide : la session y trouve
# un fichier plausible et le suit. Celui-ci cherche donc les renvois vers une autorité déchue.
# PÉRIMÈTRE plus large que le 27, volontairement : toutes les compétences, `agents/` et
# `resources/*.md` — dont le gabarit `DOMAINE_TEMPLATE.md`, qui ne doit nommer aucun dossier mort.
# ÉCHAPPATOIRE : une ligne qui porte `[archive]` est passée — on parle de l'archive en connaissance
# de cause. AVERTIT, ne bloque pas : même classe que le 27 et le 45.
_claudeos_py_27bis() {
python3 - <<'PYEOF' 2>/dev/null
import re, os, glob
H = os.path.expanduser('~')
files = [f'{H}/.claude/CLAUDE.md', f'{H}/.claude/DESIGN.md']
for pat in ('skills/*/*.md', 'resources/*.md', 'agents/*.md'):
    files += glob.glob(f'{H}/.claude/{pat}')
# Trois classes : l'ancienne installation V2, `~/.claudeos`, et son dossier de travail
# `~/workstations/` (`~/workstations.ancien-*`), racine des V1 et V2 morte le 2026-09-08 — des autorités mortes après l'import
# (`import-v2.py`), même présentes sur le disque ; les fichiers d'état GELÉS du niveau système,
# dont une instruction vivante ne doit plus faire une destination d'écriture.
# Pour les gelés, le discriminant est CE QUE LA LIGNE DIT : nommer un fichier gelé pour dire
# qu'il est gelé est voulu, donc une ligne qui porte « gel » passe. Sans cette nuance, le
# contrôle crierait sur chaque pointeur correct.
DECHU = re.compile(r'~/\.claudeos[^\s`)"\']*'
                   r'|~/workstations(?:\.ancien-[0-9-]+)?(?:/[^\s`)"\']*)?')   # morts le 2026-09-08
# ANCRÉ SUR LE CHEMIN SYSTÈME : `MEMORY.md` et `HANDOFF.md` (mort le 2026-09-17) nus peuvent désigner des fichiers
# vivants d'un dossier de travail ; seuls ceux du niveau système sont gelés.
SECRET4 = re.compile(r'CLAUDE\.md\s*§\s*4\b[^\n]{0,40}secret|secret[^\n]{0,60}CLAUDE\.md\s*§\s*4\b', re.I)
MORT_CODE = re.compile(r'HANDOFF\.md')   # mort le 2026-09-17, remplacé par ETAT.md
GELES = re.compile(r'~/\.claude/(?:MEMORY|HANDOFF)\.md'   # gelés le 2026-09-08, niveau système
                   r'|~/\.claude/memory/(?:INDEX|LEARNING_PROPOSALS)\.md')
out = []
for f in sorted(set(files)):
    try: txt = open(f, encoding='utf-8').read()
    except OSError: continue
    gele_lui_meme = txt.startswith('> **GELÉ')
    for i, l in enumerate(txt.splitlines(), 1):
        if '[archive]' in l: continue
        for m in DECHU.finditer(l):
            out.append(f"{os.path.relpath(f, H)}:{i} → {m.group(0)[:70]}")
        if gele_lui_meme:
            continue                      # un fichier gelé parle du passé, c'est son métier
        bas = l.lower()
        if 'gel' in bas or 'gelé' in bas:
            continue
        for m in GELES.finditer(l):
            out.append(f"{os.path.relpath(f, H)}:{i} → {m.group(0)} (GELÉ — dis-le, ou pointe ETAT.md)")
        for m in SECRET4.finditer(l):
            out.append(f"{os.path.relpath(f, H)}:{i} → renvoi au règlement §4 pour les secrets (MORT — compétence secrets-detail)")
# NOMS MORTS DANS LE CODE DU MOTEUR : le texte qu'un script INJECTE gagne sur toute fiche. Lignes
# de CODE seulement — un commentaire raconte le passé, c'est son métier.
for f in sorted(glob.glob(f'{H}/.claude/engine/*.sh') + glob.glob(f'{H}/.claude/engine/hooks/*.sh')):
    try: lignes = open(f, encoding='utf-8').read().splitlines()
    except OSError: continue
    for i, l in enumerate(lignes, 1):
        if l.lstrip().startswith('#'): continue
        if MORT_CODE.search(l):
            out.append(f"{os.path.relpath(f, H)}:{i} → nom MORT dans le code : {l.strip()[:70]}")
print('\n'.join(out))
PYEOF
}
_dechu=$(_claudeos_py_27bis)
if [ -n "$_dechu" ]; then
    warn "instruction vivante qui renvoie à l'archive figée ($(printf '%s\n' "$_dechu" | wc -l | tr -d ' ') citation(s)) — réécrire sur le régime vivant, ou marquer la ligne \`[archive]\` :"
    printf '%s\n' "$_dechu" | sed 's/^/       /' >&2
else ok "aucune instruction vivante ne renvoie à l'archive figée"; fi

echo "[selftest] 27ter. Copies de script entre compétences — ont-elles divergé ?"
# La duplication d'un fichier entre compétences est ASSUMÉE (une compétence doit être
# auto-portante), mais une correction portée sur une seule copie la ferait diverger en silence.
# Ce contrôle ne demande pas de dédoublonner, il demande que les copies restent égales, et il
# découvre les doublons de nom à chaque passage. Périmètre, et SOURCE qui fait foi :
#   - scripts `.py` des compétences ;
#   - définitions d'agents : `domaines/<D>/agents/` fait foi, les copies des dossiers de travail
#     sont diffusées ;
#   - outils : `resources/tools/` fait foi sur les copies `tools/` des dossiers de travail.
# Les `<dossier>/.claude/rules/*.md` liés vers `domaines/` ne comptent pas : un lien ne diverge pas,
# et un `md5` y rend l'empreinte de la cible — un doublon ne s'établit pas sans tester `[ -L ]`.
# EXISTENCE AVANT LECTURE : chaque racine est testée avant `find`, et rien n'est masqué — absente,
# elle se tait ; présente mais illisible, elle parle. Les deux listes ci-dessous gardent le MÊME
# périmètre et changent ensemble.
# Les dossiers `tests/` sortent des deux côtés : un test est propre à sa compétence, et des noms
# communs y ont un contenu voulu différent.
# `_rac27`, parce que `_rt` est déjà pris plus haut.
_div=""
while IFS= read -r _n; do
    _c=(); while IFS= read -r _cf; do [ -n "$_cf" ] && _c+=("$_cf"); done < <( { [ -d "$HOME/.claude/skills" ] && find -L "$HOME/.claude/skills" -name "$_n" -type f -not -path '*/synced/*' -not -path '*/tests/*'
                         [ -d "$HOME/.claude/domaines" ] && find -L "$HOME/.claude/domaines" -path '*/agents/*' -name "$_n" -type f
                         [ "${#_WS[@]}" -gt 0 ] && for _rac27 in "${_WS[@]}"; do [ -d "$_rac27" ] && find -L "$_rac27" -path '*/.claude/agents/*' -name "$_n" -type f; done
                         [ -d "$HOME/.claude/resources/tools" ] && find -L "$HOME/.claude/resources/tools" -name "$_n" -type f
                         [ "${#_WS[@]}" -gt 0 ] && for _rac27 in "${_WS[@]}"; do [ -d "$_rac27" ] && find -L "$_rac27" -path '*/tools/*' -name "$_n" -type f; done
                       } | sort -u )
    [ "${#_c[@]}" -lt 2 ] && continue
    # Hachage portable par `claudeos_hash_file` (`md5sum` est GNU) : sans hacheur, les deux côtés
    # rendraient vide, donc « identiques » — d'où la garde ci-dessous.
    _ref=$(claudeos_hash_file "${_c[0]}" || true)
    if [ -z "$_ref" ]; then
        warn "27ter : AUCUN HACHEUR DISPONIBLE (md5sum, shasum, md5) — la comparaison des copies n'a PAS eu lieu. Ne pas lire ce contrôle comme vert."
    else
    for _f in "${_c[@]:1}"; do
        [ "$(claudeos_hash_file "$_f" || true)" = "$_ref" ] || _div="$_div$_n : ${_c[0]#$HOME/} ≠ ${_f#$HOME/}\n"
    done
    fi
done < <( { [ -d "$HOME/.claude/skills" ] && find -L "$HOME/.claude/skills" -name "*.py" -type f -not -path '*/synced/*' -not -path '*/tests/*' | sed 's#.*/##'
            [ -d "$HOME/.claude/domaines" ] && find -L "$HOME/.claude/domaines" -path '*/agents/*' -name "*.md" -type f | sed 's#.*/##'
            [ "${#_WS[@]}" -gt 0 ] && for _rac27 in "${_WS[@]}"; do [ -d "$_rac27" ] && find -L "$_rac27" -path '*/.claude/agents/*' -name "*.md" -type f; done | sed 's#.*/##'
            [ -d "$HOME/.claude/resources/tools" ] && find -L "$HOME/.claude/resources/tools" -name "*.py" -type f | sed 's#.*/##'
            [ "${#_WS[@]}" -gt 0 ] && for _rac27 in "${_WS[@]}"; do [ -d "$_rac27" ] && find -L "$_rac27" -path '*/tools/*' -name "*.py" -type f; done | sed 's#.*/##'
          } | sort | uniq -d )
if [ -n "$_div" ]; then
    warn "copies divergentes (script de compétence, ou définition d'agent) — les réaligner sur la SOURCE :"
    echo "       pour un agent, la source est \`~/.claude/domaines/<D>/agents/\`." >&2
    printf '%b' "$_div" | sed 's/^/       /' >&2
else ok "les scripts présents en plusieurs exemplaires sont identiques entre eux"; fi

echo "[selftest] 28. Réceptacle des documents client à la racine de chaque projet"
# Le réceptacle vit à la racine du PROJET, jamais au niveau d'une app : on n'en réclame pas aux
# apps ni aux sous-dossiers.
# Lit CONFIDENTIEL dans `reglages/REPONSES`, par `sans_objet` : à `non`, la règle qu'il garde n'est pas
# entrée chez l'installateur, et le contrôle se saute en le disant. Une clé absente le fait jouer.
if sans_objet CONFIDENTIEL "réceptacle confidentiel"; then
    :
elif [ "${#_WS[@]}" -eq 0 ]; then
    # Sans cette branche, `find` sur un ensemble vide balaierait le dossier courant.
    echo "  ⏭  sans objet : aucun dossier de travail sur le disque (dit en tête de la passe)"
else
# Dossiers cachés exclus (outillage d'éditeur) et `journal/` exclu (n'y vivent que les `.jsonl`
# d'`etat.py`) : ni l'un ni l'autre n'est un projet.
# LE DISCRIMINANT N'EST PAS LA PROFONDEUR, qui change avec la forme de l'arbre : un dossier a
# besoin de SON réceptacle seulement si aucun ancêtre, racine du dépôt comprise, n'en porte un.
_noign=$(find -L "${_WS[@]}" -mindepth 1 -maxdepth 1 -type d \
    -not -name "_IGNORE" \
    -not -name "journal" \
    -not -name ".*" \
    2>/dev/null | while read -r d; do
        [ -d "$d/_IGNORE" ] && continue
        _p=$(dirname "$d"); _cv=0
        # La remontée s'arrête aussi à `~/.claude` : en dépôt unique et sans git, les dossiers de
        # travail vivent sous `travail/`, et un `_IGNORE/` à la racine du système couvrirait alors
        # tous les projets.
        while [ "$_p" != "$HOME" ] && [ "$_p" != "/" ] && [ "$_p" != "$HOME/.claude" ]; do
            [ -d "$_p/_IGNORE" ] && { _cv=1; break; }
            _p=$(dirname "$_p")
        done
        [ "$_cv" = "0" ] && echo "${d#$HOME/}"
      done)
if [ -n "$_noign" ]; then
    # AVERTIT : un réceptacle manquant est un défaut de rangement, pas une fuite.
    warn "projet sans réceptacle \`_IGNORE/\` à sa racine (le premier document client y atterrirait en zone sauvegardée) :"
    echo "$_noign" | sed 's/^/       /' >&2
else ok "tous les projets ont leur réceptacle à leur racine"; fi
fi

echo "[selftest] 28bis. Réceptacle confidentiel REDONDANT sous un autre (avertissement)"
# INVERSE du 28 : le 28 vérifie qu'un réceptacle EXISTE à la racine de chaque projet, celui-ci
# qu'il n'en existe pas un REDONDANT plus bas. Un `_IGNORE/` est hors sauvegarde : un document
# client rangé sous un réceptacle déjà couvert est au mauvais endroit, en seul exemplaire local,
# invisible depuis un autre poste et perdu avec la machine.
# AVERTIT, jamais ne bloque : c'est un défaut de rangement, pas une désactivation.
# LE CRITÈRE est UN RÉCEPTACLE SOUS UN AUTRE, pas la profondeur : des sous-projets nichés, avec
# leur `CLAUDE.md`, portent légitimement le leur quand rien au-dessus n'en porte.
# Lit CONFIDENTIEL dans `reglages/REPONSES`, par `sans_objet` : à `non`, la règle qu'il garde n'est pas
# entrée chez l'installateur, et le contrôle se saute en le disant. Une clé absente le fait jouer.
if sans_objet CONFIDENTIEL "réceptacle confidentiel"; then
    :
elif [ "${#_WS[@]}" -eq 0 ]; then
    echo "  ⏭  sans objet : aucun dossier de travail sur le disque (dit en tête de la passe)"
else
# Le compte de fichiers est donné parce qu'un dossier VIDE mal placé et un dossier PEUPLÉ mal
# placé ne se traitent pas pareil : le premier se supprime, le second se déménage après
# classement — et rien ne se supprime dans un `_IGNORE/` sans classement.
_misign=$(find -L "${_WS[@]}" -mindepth 2 -type d -name "_IGNORE" 2>/dev/null | while read -r d; do
        # un réceptacle au-dessus de celui-ci ? On remonte de parent en parent jusqu'au
        # domaine : `find` seul ne sait pas exprimer « sous un autre dossier de même nom ».
        _p=$(dirname "$d"); _couvert=0
        # La remontée s'arrête AU dépôt, jamais à `~/` : un `~/_IGNORE` hors dépôt ferait déclarer
        # « déjà couvert » tous les réceptacles du parc.
        while [ "$_p" != "$HOME" ] && [ "$_p" != "/" ]; do
            _p=$(dirname "$_p")
            { [ "$_p" = "$HOME" ] || [ "$_p" = "$HOME/.claude" ]; } && break   # même borne qu'au 28
            [ -d "$_p/_IGNORE" ] && { _couvert=1; break; }
        done
        [ "$_couvert" = "1" ] && echo "${d#$HOME/} ($(find -L "$d" -type f 2>/dev/null | wc -l | tr -d ' ') fichier(s), déjà couvert par ${_p#$HOME/}/_IGNORE)"
      done)
if [ -n "$_misign" ]; then
    warn "réceptacle \`_IGNORE/\` REDONDANT — un autre existe au-dessus, donc un document déposé ici est au mauvais endroit et en seul exemplaire local :"
    echo "$_misign" | sed 's/^/       /' >&2
else ok "aucun réceptacle confidentiel redondant sous un autre"; fi
fi

echo "[selftest] 29bis. Formes normalisées des fiches de mémoire automatique"
# Ce que `memoire-et-verite/SOURCES_DE_VERITE.md` § « Formes normalisées » prescrit, mesuré une fois
# par semaine — l'autre moitié de la garantie est le gabarit au moment d'écrire.
# LE CONTRÔLE NE RECOPIE PAS LA TABLE préfixe↔type : il la LIT dans la fiche, sinon c'est la
# copie que personne ne relit qui gagnerait. Fiche ou table disparue : il le DIT, pas de vert.
# AVERTIT : une fiche mal formée se corrige, elle ne perd rien.
_FICHE="$HOME/.claude/skills/memoire-et-verite/SOURCES_DE_VERITE.md"
_map=$(grep -oE '^\| `[a-z]+_` \| `[a-z]+` \|' "$_FICHE" 2>/dev/null | tr -d '`|' | awk '{print $1" "$2}')
if [ -z "$_map" ]; then
    warn "table préfixe↔type introuvable dans memoire-et-verite/SOURCES_DE_VERITE.md — ce contrôle est muet (fiche déplacée, ou table reformatée)"
else
    _f29=0
    for _m in "$MEM"/*.md; do
        _b="$(basename "$_m")"
        case "$_b" in user_*|proj_*|env_*|ref_*) ;; *) continue ;; esac
        _pre="${_b%%_*}_"
        _att=$(printf '%s\n' "$_map" | awk -v p="$_pre" '$1==p {print $2; exit}')
        [ -n "$_att" ] || continue
        _got=$(grep -m1 -E '^[[:space:]]+type:' "$_m" 2>/dev/null | sed 's/.*type:[[:space:]]*//' | tr -d ' \r')
        if [ -z "$_got" ]; then
            warn "fiche de mémoire sans \`type:\` dans son frontmatter : ${_m#$HOME/}"; _f29=1
        elif [ "$_got" != "$_att" ]; then
            warn "fiche de mémoire dont le NOM et le TYPE se contredisent : ${_m#$HOME/} — le préfixe \`$_pre\` annonce \`$_att\`, le frontmatter dit \`$_got\`"; _f29=1
        fi
        grep -qE '^description:' "$_m" 2>/dev/null || { warn "fiche de mémoire sans \`description:\` — elle ne sera rappelée par rien : ${_m#$HOME/}"; _f29=1; }
    done
    [ "$_f29" = 0 ] && ok "toute fiche de mémoire automatique porte une description, et son type s'accorde à son préfixe"
fi

echo "[selftest] 30. Rappel échu : le démarrage le sort-il vraiment ?"
# PIÈGE : `while IFS= read -r` abandonne la dernière ligne d'un fichier sans retour à la ligne
# final — dans `REMINDERS.md`, c'est le rappel le plus récent, donc le seul actif. Ce contrôle
# exerce le CAS POSITIF (un rappel échu sort-il ?), seul capable d'attraper la classe.
# AVERTIT : un rappel muet encombre, il ne désarme pas une garde de sauvegarde.
_r=0
# (a) Anti-régression : la garde de dernière ligne est-elle toujours dans la boucle ?
grep -qF 'read -r rline || [ -n "$rline" ]' "$SELF/boot-check.sh" \
    || { warn "garde de dernière ligne absente de la boucle des rappels (boot-check.sh) — un fichier sans retour à la ligne final reperdrait son rappel le plus récent"; _r=1; }
# (b) Cas positif, sur données réelles : tout rappel dont l'échéance est atteinte doit
#     apparaître dans le bilan injecté. Sans rappel échu au moment du contrôle, (b) est
#     inapplicable — on le dit, on ne le maquille pas en succès.
_claudeos_py_due() {
python3 - "$MEM/REMINDERS.md" <<'PY' 2>/dev/null || echo 0
import re, sys, datetime
try: t = open(sys.argv[1], encoding="utf-8").read()
except OSError: print(0); raise SystemExit
today = datetime.date.today()
n = sum(1 for d in re.findall(r"^- (\d{4}-\d{2}-\d{2}) *\|", t, re.M)
        if datetime.date.fromisoformat(d) <= today)
print(n)
PY
}
_due=$(_claudeos_py_due)
if [ "${_due:-0}" -gt 0 ]; then
    # On ne compte que les ⏰ en DÉBUT DE LIGNE, forme des alertes : la consigne de démarrage cite
    # « ⏰ rappels » en prose, et un compte sur tout le texte vaudrait 1 en permanence — contrôle
    # muet par construction. Rien du libellé de boot-check n'est recopié.
    _seen=$(printf '%s' "$_BOOTOUT" | python3 -c '
import json, sys
t = json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]
print(sum(1 for l in t.splitlines() if l.startswith("⏰")))
' 2>/dev/null || echo 0)
    [ "${_seen:-0}" -eq 0 ] && { warn "$_due rappel(s) échu(s) dans REMINDERS.md mais AUCUN dans le bilan de démarrage — le bloc est muet"; _r=1; }
    [ "$_r" = 0 ] && ok "garde de dernière ligne en place + $_due rappel(s) échu(s) effectivement sorti(s) au démarrage"
else
    [ "$_r" = 0 ] && ok "garde de dernière ligne en place (aucun rappel échu à ce jour — cas positif non exercé)"
fi
# (c) BUDGET DU BILAN : au-delà de 10 000 caractères, un `additionalContext` n'arrive au modèle
#     qu'en aperçu de 2 000 (doc des hooks) — bilan tronqué sans un mot. Plafond posé à 9 000 sur
#     les DEUX portées ; la portée projet se mesure sur le niveau qui porte le plus de fils actifs.
#     Un niveau se nomme comme dans `etat.py fils --json` : « systeme/… » est sous `~/.claude`
#     (dossiers de travail sous `travail/`), un autre nom est sous le dossier personnel. Aucun fil
#     actif hors du système : la portée projet est sans objet, et le contrôle le dit.
#     Le vert ne cite pas les tailles : elles varient avec l'environnement du bilan, la sortie de
#     la passe doit rester comparable d'un shell à l'autre, et I2 (`indicateurs-audit.sh`) les
#     mesure déjà. Seuls le dépassement et la mesure ratée les nomment.
_boot_len() { python3 -c 'import json,sys; print(len(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]))' 2>/dev/null || echo -1; }
_lp=$(printf '%s' "$_BOOTOUT" | _boot_len)
_niv_max=$(python3 "$SELF/etat.py" fils --tous --json 2>/dev/null | python3 -c '
import json, os, sys, collections
c = collections.Counter(x["niveau"] for x in json.load(sys.stdin) if not x.get("dormant") and x["niveau"] != "systeme")
n = c.most_common(1)[0][0] if c else ""
H = os.path.expanduser("~")
print(os.path.join(H, ".claude", n[len("systeme/"):]) if n.startswith("systeme/") else os.path.join(H, n) if n else "")' 2>/dev/null)
_lj=-1
[ -n "$_niv_max" ] && _lj=$(CLAUDEOS_SESSION_SCOPE=projet CLAUDE_PROJECT_DIR="$_niv_max" bash "$SELF/boot-check.sh" </dev/null 2>/dev/null | _boot_len)
if [ "$_lp" -lt 0 ] || { [ -n "$_niv_max" ] && [ "$_lj" -lt 0 ]; }; then
    warn "budget du bilan NON MESURÉ — principale ${_lp}, projet ${_lj} (${_niv_max:-aucun niveau}) : sortie de boot-check illisible"
elif [ "$_lp" -ge 9000 ] || [ "$_lj" -ge 9000 ]; then
    warn "bilan de démarrage au-delà du budget de 9 000 caractères — principale ${_lp}, projet ${_lj} (${_niv_max##*/}) : au-delà de 10 000 le modèle n'en reçoit qu'un aperçu"
elif [ -z "$_niv_max" ]; then
    ok "bilan de démarrage sous le budget de 9 000 caractères en session principale ; portée projet sans objet, aucun fil actif hors du système"
else
    ok "bilan de démarrage sous le budget de 9 000 caractères, en session principale et en session de projet (${_niv_max##*/})"
fi

echo "[selftest] 33. Tout dossier routé par un CLAUDE.md local existe sur le disque"
# La liste auditée est la table de ROUTAGE de chaque `CLAUDE.md` local, pas le disque : c'est le
# routage qui promet qu'un dossier est traitable, donc lui qui crée la dette. Aucune exception :
# la seule question est « le dossier existe-t-il ».
# Convention lue : une table de routage écrit sa cible entre guillemets obliques avec une barre
# oblique finale (`NOM_DU_DOSSIER/`) — la barre distingue un dossier d'une donnée homonyme, les
# guillemets excluent la prose.
_ghost=""
_routes=0
# Noms de CONVENTION, pas de routage : les citer ne promet pas qu'ils existent. `_IGNORE/` a son
# propre contrôle (28) — le compter ici ferait crier deux contrôles pour un défaut.
_conventions="_IGNORE docs scripts specs plans extracted src tools assets rapports"
while IFS= read -r _cm; do
    _dir="$(dirname "$_cm")"
    # SEULEMENT les lignes de TABLEAU : c'est la table qui promet, pas la prose. En prose, des
    # exemples de convention de nommage (`2023-2024/`) et des auto-références sortaient en faux.
    for _t in $(grep -E '^[[:space:]]*\|' "$_cm" 2>/dev/null \
                | grep -oE '`[A-Za-z0-9_.-]+/`' | tr -d '`/' | sort -u); do
        case " $_conventions " in *" $_t "*) continue ;; esac
        _routes=$((_routes+1))
        [ -d "$_dir/$_t" ] || _ghost="${_ghost}${_dir#"$HOME"/}/$_t"$'\n'
    done
done < <([ "${#_WS[@]}" -gt 0 ] && find -L "${_WS[@]}" -name 'CLAUDE.md' -type f 2>/dev/null | sort)

if [ -n "$_ghost" ]; then
    # Avertissement et non échec : un dossier manquant est un vrai défaut de routage, mais
    # interdire d'enregistrer son travail pour autant ferait payer une erreur de carte par
    # une perte de travail.
    warn "dossier routé depuis un \`CLAUDE.md\` local mais ABSENT du disque — le routage promet ce qui n'existe pas :"
    printf '%s' "$_ghost" | sed 's/^/       /' >&2
else
    ok "$_routes dossier(s) routé(s) vérifié(s) sur l'ensemble des dépôts clients"
fi

echo "[selftest] 37. Cascade d'instructions — un terme proscrit par un niveau n'est prescrit par aucun niveau sous lui"
# Deux niveaux de la cascade qui se contredisent sur un nom : c'est le niveau LOCAL qui prime,
# donc le faux gagne. Quand un niveau tranche un nom, il l'écrit sous une forme négative
# explicite — « jamais `Start` », « aucune propriété `Start` n'existe » — lisible par une
# machine. Le contrôle extrait ces termes proscrits, puis vérifie qu'aucun document SOUS le
# niveau qui les proscrit ne les prescrit dans du code encadré.
# LIMITE : il ne voit que les interdits écrits sous cette forme ; il réduit la surface, il ne
# certifie pas la cascade.
# AVERTIT : une contradiction fait répondre faux, elle ne désactive ni ne détruit rien.
_r=0
_claudeos_py_casc() {
CLAUDEOS_DOCS_REF="$_DOCS_REF" python3 - ${_WS[@]+"${_WS[@]}"} <<'PY' 2>/dev/null
import os, re, sys

roots = sys.argv[1:]     # racines des dossiers de travail (`claudeos_ws_roots`)
# Les chemins rapportés sont relatifs au dossier personnel et non à « la » racine : il y en a
# désormais plusieurs, et une variable de boucle qui fuit aurait daté le message de la dernière.
H = os.path.expanduser("~")
# Documents prescriptifs de la cascade, du plus général au plus local : `CLAUDE.md`, plus les
# motifs de `reglages/DOCS_REFERENCE` que le shell passe par `CLAUDEOS_DOCS_REF`. Un dossier d'app
# peut porter plusieurs documents de référence suffixés par son nom : un motif à joker les couvre
# tous — un garde qui perd sa couverture ne crie pas, il se tait.
import fnmatch
MOTIFS = ["CLAUDE.md"] + [m.strip() for m in os.environ.get("CLAUDEOS_DOCS_REF", "").splitlines() if m.strip()]
# « jamais `X` » / « aucune propriété `X` n'existe » / « `X` n'existe pas » / « pas `X` »
BAN = [
    re.compile(r"jamais\s+`([A-Za-z_][A-Za-z0-9_]*)`"),
    re.compile(r"aucune\s+propri[eé]t[eé]\s+`([A-Za-z_][A-Za-z0-9_]*)`\s+n'existe"),
    re.compile(r"`([A-Za-z_][A-Za-z0-9_]*)`\s*,?\s*(?:propri[eé]t[eé]\s+)?qui\s+n'existe\s+pas"),
]

docs = {}
for root in roots:
  for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in ("_IGNORE", "extracted", ".git")]
    for fn in filenames:
        if any(fnmatch.fnmatch(fn, m) for m in MOTIFS):
            p = os.path.join(dirpath, fn)
            try:
                docs[p] = open(p, encoding="utf-8").read()
            except OSError:
                pass

# Un terme proscrit par le document D vaut pour tout document situé dans un sous-dossier de D.
bans = {}          # terme -> (dossier du document qui le proscrit, chemin de ce document)
for p, txt in docs.items():
    for rx in BAN:
        for m in rx.finditer(txt):
            bans.setdefault(m.group(1), (os.path.dirname(p), p))

# HOMONYMES : un même mot peut désigner deux objets (`Value` propriété de sortie proscrite,
# `Value` nom de colonne prescrit). Si le document QUI PROSCRIT prescrit lui-même le terme dans
# une ligne non négative, l'interdit n'est pas global : on l'écarte, en le disant.
def prescrit_dans(txt, term):
    rx = re.compile(r"`[^`]*\b" + re.escape(term) + r"\b\s*[:=][^`]*`")
    for m in rx.finditer(txt):
        ls = txt.rfind("\n", 0, m.start()) + 1
        le = txt.find("\n", m.end())
        line = txt[ls:le if le != -1 else len(txt)]
        if not re.search(r"jamais|n'existe|pas\s+`|proscrit|interdit|Corrig", line):
            return True
    return False

homonymes = []
for term in list(bans):
    _, ban_file = bans[term]
    if prescrit_dans(docs.get(ban_file, ""), term):
        homonymes.append((term, os.path.relpath(ban_file, H)))
        del bans[term]

out = []
for term, (ban_dir, _bf) in bans.items():
    # Prescription = le terme apparaît encadré et suivi d'un signe d'affectation ( : ou = ),
    # forme sous laquelle ces documents énoncent une valeur de propriété.
    presc = re.compile(r"`[^`]*\b" + re.escape(term) + r"\b\s*[:=][^`]*`")
    for p, txt in docs.items():
        d = os.path.dirname(p)
        if not (d == ban_dir or d.startswith(ban_dir + os.sep)):
            continue          # hors de la portée du niveau qui proscrit
        for m in presc.finditer(txt):
            frag = m.group(0)
            # La ligne qui proscrit cite forcément le terme : on écarte les lignes négatives.
            line_start = txt.rfind("\n", 0, m.start()) + 1
            line_end = txt.find("\n", m.end())
            line = txt[line_start:line_end if line_end != -1 else len(txt)]
            if re.search(r"jamais|n'existe|pas\s+`|proscrit|interdit|Corrig", line):
                continue
            out.append("%s prescrit `%s`, proscrit par %s" % (
                os.path.relpath(p, H), term, os.path.relpath(ban_dir, H) or "."))
            break

for line in sorted(set(out))[:10]:
    print(line)
for term, f in sorted(set(homonymes)):
    print("HOMONYME\t%s\t%s" % (term, f))
PY
}
_casc=$(_claudeos_py_casc)
_homo="$(printf '%s\n' "$_casc" | sed -n 's/^HOMONYME\t//p')"
_casc="$(printf '%s\n' "$_casc" | grep -v '^HOMONYME' | sed '/^$/d')"
if [ -n "$_casc" ]; then
    warn "contradiction(s) de cascade — le niveau local prime, donc c'est le faux qui gagne :"
    echo "$_casc" | sed 's/^/       /' >&2
    _r=1
fi
if [ -n "$_homo" ]; then
    echo "  ℹ️  terme(s) écartés comme homonymes — proscrits et prescrits par le même document,"
    echo "$_homo" | awk -F'\t' '{printf "       `%s` dans %s\n", $1, $2}'
    echo "       donc l'interdit n'est pas global. Non compté comme contradiction."
fi
[ "$_r" = 0 ] && ok "aucun terme proscrit par un niveau n'est prescrit sous lui"

echo "[selftest] 40. Capacité déclarée opérante mais non invocable"
# BLOQUANT : une règle existe, le système croit l'appliquer, elle ne se charge jamais — rien
# n'échoue, donc seul un blocage l'attrape (`controles-et-alarmes`).
# La classe : une compétence que la conception ou une fiche désigne comme porteuse d'un geste,
# alors que son frontmatter porte `disable-model-invocation: true` et qu'aucune fiche ne dit de
# la proposer. Issues légitimes : une fiche dit de la proposer (le geste est cherché, pas le nom),
# l'interdiction d'auto-invocation est retirée, ou le document cesse de lui donner le rôle.
# Les trois sont des décisions ; seul est interdit de laisser les trois en l'état.
_c40=""
for _sk in "$HOME"/.claude/skills/*/SKILL.md; do
    [ -f "$_sk" ] || continue
    grep -q '^disable-model-invocation: *true' "$_sk" || continue
    _n="$(basename "$(dirname "$_sk")")"
    # Cité comme opérant par la conception ou une fiche ?
    # `--exclude-dir` : sans lui, le grep trouve la compétence dans son propre corps et la
    # déclare citée — vert par construction.
    _cite="$(grep -rl --exclude-dir="$_n" -- "$_n" "$HOME/.claude/DESIGN.md" "$HOME/.claude/skills/" 2>/dev/null | tr '\n' ' ')"
    [ -n "$_cite" ] || continue
    # Échappatoire légitime : une fiche dit de la PROPOSER à l'utilisateur. On cherche le
    # geste, pas le nom — un nom cité peut n'être qu'une mention.
    grep -rqE --exclude-dir="$_n" "(proposer|inviter|lancer|invoquer).{0,80}$_n|/$_n" "$HOME/.claude/skills/" 2>/dev/null && continue
    _c40="$_c40$_n (cité par : $_cite)"$'\n'
done
if [ -n "$(printf '%s' "$_c40" | tr -d '[:space:]')" ]; then
    ko "compétence(s) déclarées opérantes mais non invocables — le système croit la capacité active :"
    printf '%s' "$_c40" | sed '/^$/d; s/^/       /' >&2
    echo "       → soit une fiche dit de la proposer, soit retirer disable-model-invocation," >&2
    echo "         soit retirer son rôle du document qui la cite. Ne pas laisser les trois en l'état." >&2
else
    ok "aucune capacité déclarée opérante sans chemin d'invocation"
fi

echo "[selftest] 41. Fraîcheur des places de marché de greffons"
# AVERTIT — un greffon en retard encombre, il ne désactive rien. La cadence de rafraîchissement
# peut mourir pour une seule place de marché : on compare les places de marché ENTRE ELLES, pas
# à une date absolue, ce qui distingue « personne ne s'est rafraîchi » (normal hors ligne) de
# « un seul a décroché » (le défaut).
_MKT_LAG_DAYS=14
_km="$HOME/.claude/plugins/known_marketplaces.json"
if [ ! -f "$_km" ]; then
    ok "aucune place de marché déclarée (rien à contrôler)"
else
    _claudeos_py_c41() {
python3 - "$_km" "$_MKT_LAG_DAYS" <<'PY' 2>/dev/null
import json, sys, datetime
p, lag = sys.argv[1], int(sys.argv[2])
try:
    d = json.load(open(p, encoding="utf-8"))
except Exception:
    sys.exit(0)
items = d.get("marketplaces", d) if isinstance(d, dict) else {}
dates = {}
for name, v in (items.items() if isinstance(items, dict) else []):
    if not isinstance(v, dict):
        continue
    raw = v.get("lastUpdated")
    if raw is None:
        continue
    try:
        ts = float(raw)
        dt = datetime.datetime.fromtimestamp(ts / 1000 if ts > 1e11 else ts)
    except (TypeError, ValueError):
        try:
            dt = datetime.datetime.fromisoformat(str(raw).replace("Z", "+00:00")).replace(tzinfo=None)
        except ValueError:
            continue
    dates[name] = dt
if len(dates) < 2:
    sys.exit(0)
newest = max(dates.values())
for name, dt in sorted(dates.items()):
    behind = (newest - dt).days
    if behind >= lag:
        print(f"{name} : {behind} j derrière la plus fraîche ({dt:%Y-%m-%d})")
PY
    }
    _c41="$(_claudeos_py_c41)"
    if [ -n "$_c41" ]; then
        warn "place(s) de marché décrochée(s) de plus de $_MKT_LAG_DAYS jours sur les autres :"
        printf '%s\n' "$_c41" | sed 's/^/       /' >&2
        echo "       → rafraîchir le clone, ou diagnostiquer pourquoi lui seul ne se rafraîchit pas." >&2
    else
        ok "places de marché de greffons alignées entre elles"
    fi
fi

# --- 41 suite. LE CACHE QUI SERT CONTRE LA COPIE TIRÉE, PAR LE CONTENU ET NON PAR LA VERSION.
# Seconde mesure à l'intérieur du 41, d'où l'intitulé non numéroté : le 41 demande « le clone se
# rafraîchit-il », celle-ci « le rafraîchissement arrive-t-il jusqu'à ce qui est chargé ».
# Un greffon vit en DEUX exemplaires : `plugins/marketplaces/…`, tiré par `autoUpdate`, et
# `plugins/cache/<place>/<greffon>/<clé>/`, celui qui est CHARGÉ (marqueur `.in_use`).
#   - clé = EMPREINTE (12 hexa) : un contenu qui bouge produit une clé neuve. Rien à surveiller.
#   - clé = NUMÉRO DE VERSION : si l'amont livre du contenu sans monter sa version, le cache reste
#     figé pour toujours. `claude plugin update` ne le voit pas, il compare les numéros.
# L'AMONT SE RÉSOUT PAR LE NOM DÉCLARÉ dans `plugin.json`, jamais par le nom de dossier : ils
# peuvent différer, et un greffon peut être la racine même de sa place de marché.
# CE QU'IL NE PEUT PAS JUGER, il le DIT : un greffon servi d'ailleurs n'a aucune copie amont sur
# le disque, et taire l'étendue de ce qu'on ignore laisserait croire à une couverture totale.
echo "[selftest]  · 41 suite — le cache qui sert, contre la copie tirée, par le contenu"
_claudeos_py_c41b() {
python3 - <<'PY' 2>/dev/null
import json, os, glob, re, subprocess
R = os.path.expanduser("~/.claude/plugins")
SHA = re.compile(r"^[0-9a-f]{12}$")
amont = {}
for pj in glob.glob(R + "/marketplaces/*/**/.claude-plugin/plugin.json", recursive=True):
    try:
        nom = json.load(open(pj, encoding="utf-8")).get("name")
    except Exception:
        continue
    if nom:
        amont.setdefault(nom, os.path.dirname(os.path.dirname(pj)))
ecarts, muets, juges = [], [], 0
for d in sorted(glob.glob(R + "/cache/*/*/*/")):
    if not os.path.exists(os.path.join(d, ".in_use")):
        continue
    # `.orphaned_at` : une version REMPLACÉE garde son `.in_use` mais n'est plus servie.
    if os.path.exists(os.path.join(d, ".orphaned_at")):
        continue
    cle = os.path.basename(d.rstrip("/"))
    if SHA.match(cle):
        continue                      # clé par empreinte : se réextrait seule
    try:
        nom = json.load(open(os.path.join(d, ".claude-plugin", "plugin.json"),
                             encoding="utf-8")).get("name")
    except Exception:
        nom = None
    src = amont.get(nom)
    if not src:
        muets.append("%s (%s) : aucune copie amont sur le disque" % (nom or "?", cle))
        continue
    juges += 1
    r = subprocess.run(["diff", "-rq", d.rstrip("/"), src], capture_output=True, text=True)
    lignes = [l for l in r.stdout.splitlines()
              if ".in_use" not in l and "/.git" not in l and not l.endswith(": .git")]
    if lignes:
        ecarts.append("%s (%s) : %d ecart(s) de contenu a version identique" % (nom, cle, len(lignes)))
for e in ecarts:
    print("ECART " + e)
for m in muets:
    print("MUET " + m)
print("BILAN %d juge(s), %d non jugeable(s)" % (juges, len(muets)))
PY
}
_c41b="$(_claudeos_py_c41b)"
if ! printf '%s' "$_c41b" | grep -q '^BILAN'; then
    warn "contrôle du cache de greffons : mesure RATÉE, aucun bilan rendu — ne pas lire comme un vert"
elif printf '%s' "$_c41b" | grep -q '^ECART'; then
    warn "greffon servi PÉRIMÉ — le cache diffère de la copie tirée à version identique :"
    printf '%s\n' "$_c41b" | grep '^ECART' | sed 's/^ECART /       /' >&2
    echo "       → recopier l'amont par-dessus le cache en préservant .in_use. \`claude plugin" >&2
    echo "         update\` NE SUFFIT PAS : il compare les numéros de version, pas le contenu." >&2
    printf '%s\n' "$_c41b" | grep '^MUET' | sed 's/^MUET /       non jugeable : /' >&2
else
    ok "$(printf '%s' "$_c41b" | grep '^BILAN' | sed 's/^BILAN /caches de greffons alignés sur leur amont — /')"
    printf '%s' "$_c41b" | grep '^MUET' | sed 's/^MUET /       non jugeable : /' >&2 || true
fi

echo "[selftest] 42. Compétences empruntées — origine épinglée et composition intacte"
# L'origine d'un emprunt est sa ligne de `engine/config/SKILLS_AMONT` — dépôt et commit épinglé —,
# et `engine/skills-amont.sh` le compose : la dérive de l'amont n'atteint pas le poste, qui ne suit
# jamais `main`, et rien ne se mesure ici par le réseau. AVERTIT. Deux moitiés :
# (a) toute compétence qui se dit empruntée a sa ligne dans la table — sinon rien ne dit d'où vient
#     son corps, et rien ne le recompose ;
# (b) chaque optionnelle retenue est présente et égale à sa composition, recomposée depuis le cache
#     par `skills-amont.sh --verifier`, seule implémentation de la composition. Un cache absent rend
#     la compétence NON JUGÉE, dit comme tel : ce n'est pas un vert.
_c42=""
_T42="$SELF/config/SKILLS_AMONT"
for _sk in "$HOME"/.claude/skills/*/SKILL.md; do
    [ -f "$_sk" ] || continue
    _d42="$(dirname "$_sk")"; _n="$(basename "$_d42")"
    [ "$_n" = "os-audit" ] && continue   # parle des emprunts sans en être un
    grep -qE '\*\*Emprunt|\*\*Adaptation ClaudeOS' "$_sk" || [ -f "$_d42/LICENSE.amont" ] || continue
    awk -v n="$_n" '!/^[[:space:]]*(#|$)/ && $1 == n { t = 1 } END { exit !t }' "$_T42" 2>/dev/null \
        || _c42="$_c42$_n : emprunt sans ligne dans engine/config/SKILLS_AMONT"$'\n'
done
_v42="$(bash "$SELF/skills-amont.sh" --verifier 2>&1)"; _r42=$?
case "$_r42" in
    0) ;;
    1|3) _c42="$_c42$(printf '%s\n' "$_v42" | grep -E '⛔|⚠' | sed 's/^\[amont\] //')"$'\n' ;;
    *) _c42="${_c42}skills-amont.sh --verifier : mesure RATÉE (rc=$_r42) — $(printf '%s' "$_v42" | tail -n 1)"$'\n' ;;
esac
if [ -n "$(printf '%s' "$_c42" | tr -d '[:space:]')" ]; then
    warn "compétences empruntées :"
    printf '%s' "$_c42" | sed '/^$/d; s/^/       /' >&2
else
    ok "emprunts épinglés dans SKILLS_AMONT, compositions égales à leur commit"
fi

echo "[selftest] 45. Pointeurs de la carte — ETAT.md « Où trouver » (avertissement, ne bloque pas)"
# Cette couche est la carte que le règlement fait consulter AVANT tout travail de fond : un
# pointeur mort n'y fait échouer aucun script, il envoie la session dans le vide. La classe revient
# à chaque réorganisation, d'où un contrôle plutôt qu'un rappel.
# AVERTIT : un pointeur mort encombre la carte, il ne désactive aucune règle (une règle non
# routée, elle, bloque — voir contrôle 23).
# CE QU'IL JUGE : les compétences citées existent dans `~/.claude/skills/`, les chemins cités se
# résolvent. CE QU'IL NE JUGE PAS : renvois de section, repères de journal, notes d'un coffre de
# notes (préfixe `wiki `, hors de l'arbre sauvegardé), noms nus — et il AFFICHE le compte des
# non-jugés : un contrôle qui tairait l'étendue de ce qu'il ignore laisserait croire à une
# couverture totale.
# Le calcul vit dans `engine/resolveur_pointeurs.py`, importé aussi par `etat.py` qui refuse à
# l'écriture un pointeur qui ne résout pas : deux implantations du même calcul dériveraient.
_ptr=$(python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolveur_pointeurs.py" "$HOME/.claude/ETAT.md" "$MEM" 2>/dev/null)
_bilan=$(printf '%s\n' "$_ptr" | grep -m1 '^#')
_ptr_ko=$(printf '%s\n' "$_ptr" | grep -v '^#' | grep -v '^[[:space:]]*$')
if [ -z "$_bilan" ] || [ "$_bilan" = "#VIDE" ]; then
    warn "pointeurs de la carte : AUCUNE citation lue dans ~/.claude/ETAT.md « Où trouver » — mesure ratée, ce contrôle est muet (fichier absent, couche 🧭 vidée, ou forme des citations changée)"
elif [ -n "$_ptr_ko" ]; then
    warn "pointeurs de la carte d'ETAT.md qui ne résolvent pas — ${_bilan#\#BILAN } :"
    printf '%s\n' "$_ptr_ko" | sed 's/^/       /' >&2
else
    ok "tous les pointeurs de la carte résolvent — ${_bilan#\#BILAN }"
fi

echo "[selftest] 47. Personnalisation — le règlement porte-t-il encore des marques de gabarit ? (avertissement)"
# POURQUOI CE CONTRÔLE EXISTE. Le squelette `gabarits/CLAUDE.md` livre les rubriques du persona et
# la table « Mes domaines » marquées « à remplir » ; une V1 ou une V2 importée peut porter encore
# des notes `<!-- WIZARD -->`. Rien d'autre ne vérifie que la PERSONNALISATION a eu lieu : on peut
# vivre des mois avec des rubriques génériques et une table « *(à remplir)* » sans qu'aucun
# contrôle ne bronche. Un règlement sans ces marques le rend vert et muet.
# AVERTISSEMENT, jamais ko : une dette de personnalisation n'est ni une perte irréversible, ni
# une fuite, ni le désarmement silencieux d'une garde (critère de warn(), en tête de fichier) —
# elle encombre, elle ne désactive rien, et bloquer la sauvegarde dessus ferait payer un
# entretien remis à plus tard par la perte du travail du jour.
_R47="$HOME/.claude/CLAUDE.md"
if [ ! -f "$_R47" ]; then
    warn "règlement introuvable ($_R47) — rien à contrôler ici, d'autres contrôles le diront"
else
    _m47="$(grep -n "<!-- WIZARD\|à remplir" "$_R47" | head -6)"
    if [ -n "$_m47" ]; then
        warn "le règlement porte encore des marques de gabarit — entretien non joué, ou persona/table de routage laissées en l'état :"
        printf '%s\n' "$_m47" | sed 's/^/       /' >&2
        echo "       Le remède : rejouer l'entretien — compétence claudeos-onboarding, ou l'agent livré. Une" >&2
        echo "       rubrique s'y règle, ou se retire quand l'utilisateur n'a rien de particulier à y mettre ;" >&2
        echo "       Identité reste. La ligne « à remplir » de « Mes domaines » cède au premier domaine." >&2
    else
        ok "aucune marque de gabarit dans le règlement"
    fi
fi
# Et les réponses : une clé d'entretien du contrat absente de `reglages/REPONSES` laisse le moteur la
# traiter en poste non réglé. Le démarrage le dit aussi (M-INACHEVEE, test a) ; ici, la passe
# mensuelle nomme chaque clé. Une clé vide est une réponse, pas un manque.
_c47="$CFG/REPONSES_CLES"
if [ -r "$_c47" ]; then
    _manq47=""
    while read -r _k47 _o47 _reste47; do
        case "$_k47" in ''|\#*) continue ;; esac
        [ "$_o47" = entretien ] || continue
        claudeos_reponse "$_k47" >/dev/null || _manq47="$_manq47 $_k47"
    done < "$_c47"
    if [ -n "$_manq47" ]; then
        warn "reglages/REPONSES ne porte pas ces clés d'entretien :$_manq47 — rejouer l'entretien (claudeos-onboarding, ou l'agent livré)"
    else
        ok "chaque clé d'entretien du contrat est dans reglages/REPONSES"
    fi
else
    warn "contrat des réponses illisible ($_c47) — les clés ne se comptent pas"
fi

# =============================================================================
echo "[selftest] 48. Renvois au règlement — la section citée porte-t-elle encore le CONTENU ? (avertissement)"
# Un renvoi « racine §N » peut survivre au retrait de la règle qu'il cite : le chemin existe, la
# section existe, le contrôle 27 est vert — seul le CONTENU à l'arrivée manque.
#
# CE QU'IL MESURE, volontairement ÉTROIT : pour chaque renvoi « racine §N » / « règlement §N »
# d'une règle vivante, la section §N existe-t-elle, ET porte-t-elle au moins un mot significatif
# de la phrase qui la cite ?
# SA LIMITE : un seul mot commun suffit, donc un renvoi orphelin dont la phrase emploie un mot
# générique passe. Exiger deux mots monterait le rappel et les faux positifs ensemble.
# IL AVERTIT ET NE BLOQUE PAS, par décision : heuristique, il ne distingue pas un renvoi mort
# d'une cible reformulée, et un faux positif bloquerait une journée sur du vocabulaire.
_claudeos_py_renvois_muets() {
python3 - "$HOME/.claude/CLAUDE.md" <<'PY'
import re, sys, os, glob
regl = open(sys.argv[1], encoding='utf-8').read()
sections = {}
ms = list(re.finditer(r'^## (\d+)\.\s*([^\n]*)$', regl, re.M))
for i, m in enumerate(ms):
    fin = ms[i+1].start() if i+1 < len(ms) else len(regl)
    sections[m.group(1)] = (m.group(2), regl[m.start():fin].lower())
STOP = set("dans pour avec sans sous cette celui celle leurs elles quand donc mais alors ainsi comme entre selon aussi encore toujours jamais chaque tout tous toute toutes autre autres même plus moins bien très fait faire vivent vivait vivre porte portent portait règle règles racine règlement section niveau déjà charge chargé chargée voir depuis avant après celles ceux".split())
def mots(t):
    t = re.sub(r'`[^`]*`', ' ', t.lower())
    return {w for w in re.findall(r"[a-zà-ÿ]{5,}", t) if w not in STOP}
HOME = os.path.expanduser('~')
# La COUCHE DOMAINE est au corpus : un renvoi muet au règlement y coûte autant qu'ailleurs.
_cl = [os.path.join(HOME, d) for d in sorted(os.listdir(HOME))
       if not d.startswith('.') and os.path.isfile(os.path.join(HOME, d, 'CLAUDE.md'))]
corpus = ([HOME + '/.claude/DESIGN.md']
          + sorted(glob.glob(HOME + '/.claude/skills/*/SKILL.md'))
          + sorted(glob.glob(HOME + '/.claude/domaines/*/CLAUDE.md'))
          + sorted(glob.glob(HOME + '/.claude/domaines/*/DESIGN.md'))
          + [f for c in _cl for f in sorted(glob.glob(c + '/CLAUDE.md'))]
          + [f for c in _cl for f in sorted(glob.glob(c + '/*/CLAUDE.md'))]
          + [f for c in _cl for f in sorted(glob.glob(c + '/DESIGN.md'))])
PAT = re.compile(r'(?:racine|règlement)[^.\n]{0,25}?§\s?(\d+)(?:\.\d+)*')
for f in corpus:
    if not os.path.exists(f): continue
    # PHRASES, PAS LIGNES : le corpus est enroulé à ~100 colonnes, une phrase tient sur plusieurs
    # lignes physiques, et lire ligne par ligne mesurerait un fragment (date ratée, mots tronqués).
    # On lit le texte entier et on retrouve le numéro de ligne par le décalage du caractère.
    txt = open(f, encoding='utf-8').read()
    rel = f.replace(HOME + '/', '')
    def ligne_de(pos): return txt.count('\n', 0, pos) + 1
    # Une phrase court d'un point/point-virgule/fin de paragraphe au suivant. LE POINT D'UN
    # NUMÉRO DE SECTION N'EST PAS UNE FIN DE PHRASE : « (§3.2) le … » se couperait sur « 3.2 ».
    for ph in re.finditer(r'[^.;\n][^.;]*?(?:(?<!\d)[.;](?!\d)|\n\n|$)', txt, re.S):
        phrase = ph.group(0)
        m = PAT.search(phrase)
        if not m: continue
        num = m.group(1)
        n = ligne_de(ph.start() + m.start())
        if num not in sections:
            print(rel + ":" + str(n) + " → §" + num + " N'EXISTE PAS dans le règlement"); continue
        # Un renvoi daté est un récit, pas un renvoi vivant. Deux pistes pour aller plus loin sont
        # mesurées et écartées — ne pas les rejouer : élargir la recherche de date au paragraphe
        # retire plus de la moitié du périmètre ; filtrer sur un verbe à l'imparfait n'attrape rien.
        if re.search(r'20\d\d-\d\d-\d\d', phrase): continue
        titre, corps = sections[num]
        cles = mots(phrase)
        if not cles: continue
        if not (cles & mots(corps)):
            ap = ' '.join(sorted(cles)[:4])
            print(rel + ":" + str(n) + " → §" + num + " « " + titre + " » ne porte AUCUN mot du renvoi (" + ap + "…)")
PY
}
# UNE ANALYSE QUI MEURT N'EST PAS UN VERT : le code retour est lu. Sans lui, un Python mort rend
# une sortie vide, et le contrôle concluait « tout renvoi résout » sur la branche d'erreur.
if ! _renvois_muets=$(_claudeos_py_renvois_muets); then
    warn "renvois au règlement : analyse en échec (cause ci-dessus) — mesure RATÉE, ne pas lire comme un vert"
elif [ -n "$_renvois_muets" ]; then
    warn "renvoi(s) au règlement dont la section citée ne porte plus le sujet :"
    printf '%s\n' "$_renvois_muets" | sed 's/^/       /' >&2
    echo "       Heuristique : un renvoi vers une cible REFORMULÉE sort ici aussi. Ouvrir la section avant de conclure." >&2
else
    ok "tout renvoi « racine §N » résout vers une section qui porte encore son sujet"
fi

# =============================================================================
echo
if [ "$FAIL" = 0 ]; then
    echo "[weekly] ✅ contrôles de contenu passés (les avertissements ci-dessus, s'il y en a, sont à traiter)."
else
    echo "[weekly] ❌ au moins un contrôle bloquant a échoué." >&2
fi
exit "$FAIL"
