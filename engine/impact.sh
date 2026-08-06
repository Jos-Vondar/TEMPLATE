#!/usr/bin/env bash
# =============================================================================
# IMPACT — « qu'est-ce que je viens de changer, et quels documents en parlent ? »
#
# Défaut visé, constaté par l'audit du 2026-07-25 : le code bouge et les documents qui
# le décrivent restent, DANS LA MÊME SESSION. Aucune cadence d'audit n'y répond : elle
# laisse passer, entre deux passages, tout le temps pendant lequel le système affirme du faux. Ce script ferme la
# boucle à la clôture : il liste les fichiers touchés par la session, puis les documents
# qui les mentionnent, pour qu'on les relise pendant qu'on a encore le contexte en tête.
# Complément, pas doublon : le contrôle hebdomadaire léger attrape la dérive lente, l'audit
# complet la dérive de fond, celui-ci la dérive née de la session même.
#
# TRI (2026-07-27). La première version rendait « quels documents nomment ce fichier »,
# avec un compteur : `DESIGN.md ×74`. Inexploitable comme liste de relecture — un nom de
# script cité 74 fois est une table des matières, pas une affirmation qui devient fausse.
# Elle rend désormais la SECTION qui porte chaque mention, et sépare :
#   ● CHAUD — la section nomme le fichier ET contient un identifiant réellement modifié
#             dans le diff. C'est là qu'un document peut décrire du faux.
#   ○ froid — la section nomme le fichier sans parler de ce qui a bougé.
# Rien n'est supprimé : les mentions froides restent comptées et leurs sections nommées.
# Un tri qui cache est pire que pas de tri, et c'est le mode de défaillance à éviter ici.
#
# GARDE ANTI-CÉCITÉ. Rendre un contrôle plus silencieux peut le rendre aveugle. Quand
# aucun identifiant n'est extractible du diff d'un fichier (fichier binaire, renommage
# pur, diff vide, fichier non suivi illisible), le tri est IMPOSSIBLE et non « négatif » :
# tout est alors remonté en chaud, avec le motif affiché. Le contrôle dit qu'il ne sait
# pas, il ne conclut pas que tout va bien.
#
# LECTURE SEULE. Il ne corrige rien et ne juge rien : il dit où regarder.
#
# Usage :
#   bash impact.sh                # travail du jour (commits du jour + non commités)
#   bash impact.sh --since <ref>  # depuis une référence git précise
# =============================================================================
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

SINCE=""
case "${1:-}" in
    --since) SINCE="${2:?--since attend une référence git ou une date}" ;;
    "") ;;
    *) echo "[impact] ERREUR : argument inattendu ('$1'). Usage : impact.sh [--since <ref|date>]" >&2; exit 2 ;;
esac

# --- Résolution de l'argument, avant tout travail ----------------------------
# Défaut trouvé par l'audit du 2026-07-31 : une DATE n'est pas une référence git.
# `git diff 2026-07-27` échoue fatalement, l'erreur était avalée par une redirection,
# et le script annonçait « aucun document ne nomme ce qui a changé ». La fiche de la
# passe hebdomadaire prescrivant justement d'appeler avec la date de la dernière passe,
# le contrôle était muet précisément dans son usage prévu — 84 sections attendaient.
# Deux corrections : on accepte désormais une date en la résolvant en commit, et on
# REFUSE de continuer si l'argument est inexploitable, au lieu de rendre une liste vide.
if [ -n "$SINCE" ]; then
    if git -C "$ROOT" rev-parse --verify --quiet "${SINCE}^{commit}" >/dev/null 2>&1; then
        :                                  # déjà une référence git valide
    # Piège mesuré en exerçant le cas positif le 2026-07-31 : `git rev-list --before`
    # n'échoue PAS sur une date illisible, il ignore le filtre et rend HEAD. Un argument
    # absurde produisait donc un résultat plausible et presque vide — pire que l'erreur
    # d'origine, parce que crédible. La date est donc validée par `date -d` AVANT git.
    elif date -d "$SINCE" +%s >/dev/null 2>&1 \
         && _ref=$(git -C "$ROOT" rev-list -1 --before="$SINCE" HEAD 2>/dev/null) \
         && [ -n "$_ref" ]; then
        echo "[impact] '$SINCE' lu comme une date → dernier commit antérieur : $(echo "$_ref" | cut -c1-9)" >&2
        SINCE="$_ref"
    elif date -d "$SINCE" +%s >/dev/null 2>&1; then
        echo "[impact] ERREUR : '$SINCE' est une date lisible, mais aucun commit ne la précède." >&2
        echo "[impact] Le dépôt commence après cette date — choisis une date plus récente." >&2
        exit 2
    else
        echo "[impact] ERREUR : '$SINCE' n'est ni une référence git ni une date lisible." >&2
        echo "[impact] Refus de continuer : une sortie vide serait lue comme « rien à signaler »." >&2
        exit 2
    fi
fi

CHANGED="${TMPDIR:-/tmp}/impact-changed.$$"
PAIRS="${TMPDIR:-/tmp}/impact-pairs.$$"
PATCH="${TMPDIR:-/tmp}/impact-patch.$$"
UNTRACKED="${TMPDIR:-/tmp}/impact-untracked.$$"
trap 'rm -f "$CHANGED" "$PAIRS" "$PATCH" "$UNTRACKED"' EXIT

# --- Fichiers touchés (chemins relatifs au dépôt) -----------------------------
{
    git -C "$ROOT" status --porcelain 2>/dev/null | awk '{print $NF}'
    if [ -n "$SINCE" ]; then
        # Pas de redirection d'erreur ici : l'argument est validé plus haut, donc un
        # échec à ce stade est un vrai défaut et doit se voir.
        git -C "$ROOT" diff --name-only "$SINCE"
    else
        git -C "$ROOT" log --since=midnight --name-only --pretty=format: 2>/dev/null
    fi
} | sed '/^$/d' | sort -u > "$CHANGED"

# --- Contenu des modifications, pour savoir CE QUI a bougé dans chaque fichier -
# Un seul flux de patch, attribué par fichier côté python via les en-têtes `diff --git`.
{
    git -C "$ROOT" diff -U0 2>/dev/null
    git -C "$ROOT" diff -U0 --cached 2>/dev/null
    if [ -n "$SINCE" ]; then
        git -C "$ROOT" diff -U0 "$SINCE"
    else
        git -C "$ROOT" log -p -U0 --since=midnight --pretty=format: 2>/dev/null
    fi
} > "$PATCH"

# Les fichiers non suivis n'ont pas de diff : leur contenu entier est la nouveauté.
git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null > "$UNTRACKED"

# --- Correspondances dépôt→vivant, dérivées du manifeste ---------------------
claudeos_pairs > "$PAIRS"

python3 - "$CHANGED" "$PAIRS" "$ROOT" "$PATCH" "$UNTRACKED" <<'PYEOF'
import os, re, sys, glob
from collections import defaultdict

changed_f, pairs_f, root, patch_f, untracked_f = sys.argv[1:6]
H = os.path.expanduser('~')

# repo_subdir -> live_abs, le plus long préfixe d'abord (system-memory avant system)
pairs = []
for line in open(pairs_f, encoding='utf-8'):
    parts = line.rstrip('\n').split('\t')
    if len(parts) >= 2:
        live, repo = parts[0], parts[1]
        pairs.append((os.path.relpath(repo, root), live))
pairs.sort(key=lambda p: -len(p[0]))

def to_live(rel):
    for repo_sub, live in pairs:
        if rel == repo_sub or rel.startswith(repo_sub + '/'):
            return os.path.join(live, os.path.relpath(rel, repo_sub))
    return os.path.join(root, rel)          # engine/, README.md… vivent dans le dépôt

# Noms trop génériques pour servir de clé : on remonte d'un cran de chemin.
GENERIC = {'CLAUDE.md','MEMORY.md','DESIGN.md','DESIGN.md','HANDOFF.md','ARCHIVE.md',
           'INDEX.md','README.md','SKILL.md','SYSTEME.md','settings.json'}

def key_for(live):
    base = os.path.basename(live)
    if base in GENERIC:
        parts = live.rstrip('/').split(os.sep)
        return os.sep.join(parts[-3:-1] + [base]) if len(parts) >= 3 else base
    return base

# ---------------------------------------------------------------------------
# 1. Ce qui a bougé dans chaque fichier : les identifiants du diff
# ---------------------------------------------------------------------------
# Pure syntaxe de shell ou de balisage : présente partout, ne désigne aucun sujet.
# Le reste du bruit (mots courants, français compris) est écarté par le filtre de
# fréquence plus bas, qui n'a pas de liste à tenir à jour.
SYNTAX = {
    'echo','printf','local','return','exit','then','else','elif','done','case','esac',
    'while','until','function','export','source','shift','unset','eval','read','true',
    'false','null','none','import','print','from','with','pass','continue','break',
    'and','not','for','def','set','get','sys','str','int','len','sort','uniq','sed',
    'awk','cat','grep','head','tail','wcl','bash','sh','git','python3','python',
    'https','http','www','com','org','md','txt','sh','py','json','yaml',
}
TOKEN = re.compile(r'[A-Za-z_][A-Za-z0-9_.-]{3,}|\b\d{2,}\b')

# A la FORME d'une chose nommée : clé de configuration, fonction, constante, nom de
# fichier, seuil chiffré. Sert uniquement à PONDÉRER une correspondance — un nom pèse
# plus lourd qu'un mot de prose de même rareté. N'écarte rien à l'entrée : voir juste
# en dessous pourquoi ce filtre a été retiré du chemin d'extraction.
def is_named_thing(t):
    if '_' in t or any(ch.isdigit() for ch in t):
        return True
    if t.isupper() and len(t) >= 3:
        return True
    if any(ch.isupper() for ch in t[1:]):          # camelCase, PascalCase, AKIA, AIza
        return True
    if re.search(r'\.(sh|py|md|json|txt|yaml|yml|ics|html|pdf|dbml|jsonl)$', t):
        return True
    if '-' in t and not t.startswith('-'):         # boot-check, sync-backups
        return True
    return False

# Aucun filtre de forme à l'entrée. Il a été essayé et il est faux dans les deux sens :
# sur un document, le contenu EST de la prose et n'en garder que les noms techniques
# revient à tout jeter ; sur un script, il rejette les identifiants tout en bas de casse
# (`reminders`, `pending`) qui sont précisément le sujet du changement. C'est la RARETÉ
# dans le corpus qui discrimine — un mot présent dans deux sections localise un sujet,
# qu'il soit nom de fonction ou mot de métier. La forme ne sert plus qu'à pondérer.
def tokens_from(text):
    out = set()
    for m in TOKEN.finditer(text):
        t = m.group(0).strip('.-_')
        if len(t) < 4 or t.lower() in SYNTAX:
            continue
        out.add(t)
    return out

# Attribution du patch par fichier. `diff --git a/X b/Y` ouvre un fichier ; on ne
# retient que les lignes ajoutées ou retirées, jamais le contexte.
diff_tokens = defaultdict(set)
cur = None
for line in open(patch_f, encoding='utf-8', errors='replace'):
    if line.startswith('diff --git '):
        m = re.match(r'diff --git a/(.*?) b/(.*)$', line.rstrip('\n'))
        cur = m.group(2) if m else None
        continue
    if cur is None or line.startswith(('+++', '---', '@@', 'index ', 'similarity ',
                                       'rename ', 'new file', 'deleted file',
                                       'old mode', 'new mode', 'Binary files')):
        continue
    if line.startswith(('+', '-')):
        diff_tokens[cur] |= tokens_from(line[1:])

# Fichiers non suivis : tout leur contenu est nouveau.
for rel in (l.strip() for l in open(untracked_f, encoding='utf-8') if l.strip()):
    p = os.path.join(root, rel)
    try:
        with open(p, encoding='utf-8', errors='replace') as fh:
            diff_tokens[rel] |= tokens_from(fh.read())
    except OSError:
        pass

# ---------------------------------------------------------------------------
# 2. Corpus documentaire, découpé en sections
# ---------------------------------------------------------------------------
# Ce qui DÉCRIT le système, donc ce qui peut le décrire faux.
corpus = ([f'{H}/.claude/CLAUDE.md', f'{H}/.claude/DESIGN.md', f'{H}/.claude/MEMORY.md',
           f'{H}/.claude/HANDOFF.md', f'{H}/.claudeos/README.md']
          + glob.glob(f'{H}/.claude/fiches/*.md')
          + glob.glob(f'{H}/.claude/skills/*/SKILL.md')
          + glob.glob(f'{H}/resources/*.md')
          + glob.glob(f'{H}/workstations/*/CLAUDE.md') + glob.glob(f'{H}/workstations/*/MEMORY.md')
          + glob.glob(f'{H}/workstations/*/*/CLAUDE.md') + glob.glob(f'{H}/workstations/*/*/MEMORY.md')
          + glob.glob(f'{H}/workstations/*/*/*/CLAUDE.md') + glob.glob(f'{H}/workstations/*/*/*/MEMORY.md')
          + glob.glob(f'{H}/workstations/*/*/DESIGN.md') + glob.glob(f'{H}/workstations/*/*/*/DESIGN.md'))
mem = None
for repo_sub, live in pairs:
    if repo_sub == 'system-memory':
        mem = live
if mem:
    corpus += [f'{mem}/INDEX.md', f'{mem}/MEMORY.md']

HEADING = re.compile(r'^(#{1,6})\s+(.*?)\s*$')

def sections_of(text):
    """[(titre, ligne_de_départ, corps)] — le corps inclut le titre."""
    out, title, start, buf = [], '(préambule)', 1, []
    for i, line in enumerate(text.splitlines(), start=1):
        m = HEADING.match(line)
        if m:
            if buf or out or title != '(préambule)':
                out.append((title, start, '\n'.join(buf)))
            title, start, buf = m.group(2).strip(), i, [line]
        else:
            buf.append(line)
    out.append((title, start, '\n'.join(buf)))
    return [s for s in out if s[2].strip()]

docs = {}
for c in sorted(set(corpus)):
    if '.sync-backups' in c:
        continue
    try:
        docs[c] = sections_of(open(c, encoding='utf-8').read())
    except OSError:
        pass

# Filtre de fréquence, second étage après le filtre de forme : un identifiant présent
# dans plus de 5 % des sections du corpus ne localise plus rien, même s'il a la forme
# d'un nom (« 2026 », qui date la moitié des entrées). Auto-réglé, donc aucune liste de
# mots courants à maintenir.
total_sections = sum(len(v) for v in docs.values()) or 1
doc_freq = defaultdict(int)
for secs in docs.values():
    for _, _, body in secs:
        for t in set(TOKEN.findall(body)):
            t = t.strip('.-_')
            if len(t) >= 4:
                doc_freq[t] += 1
# Seuil unique : un mot présent dans plus de 2 % des sections du corpus ne localise
# plus rien, qu'il soit identifiant ou mot de prose.
COMMON = total_sections * 0.02

# ---------------------------------------------------------------------------
# 3. Croisement
# ---------------------------------------------------------------------------
changed = [l.strip() for l in open(changed_f, encoding='utf-8') if l.strip()]
# Hors champ. Traces datées (journal, archives, rapports d'audit) : elles doivent rester
# telles quelles. Vues GÉNÉRÉES (fils ouverts, portfolio) : leur contenu est dérivé et
# rejoué en entier à chaque sauvegarde, donc aucun document ne le décrit — ils décrivent
# leur rôle, qui ne change pas. Les garder inondait le tri de centaines d'identifiants.
SKIP = re.compile(r'\.sync-backups/'
                  r'|^system-memory/SESSION_(JOURNAL|ARCHIVE)\.md$'
                  r'|^system-memory/(OPEN_THREADS|PORTFOLIO)\.md$'
                  r'|^system/audits/')

hits, seen = [], set()
for rel in changed:
    if SKIP.search(rel):
        continue
    live = to_live(rel)
    k = key_for(live)
    if k in seen:
        continue
    seen.add(k)

    raw = diff_tokens.get(rel, set())
    disc = sorted(t for t in raw if doc_freq.get(t, 0) <= COMMON)
    # Garde anti-cécité : sans identifiant discriminant, on ne sait pas trier.
    blind = None
    if not raw:
        blind = "aucun contenu de diff exploitable (binaire, renommage, ou hors fenêtre)"
    elif not disc:
        blind = f"{len(raw)} identifiant(s) au diff, tous trop communs pour discriminer"

    # Force de la correspondance. Un identifiant rare dans le corpus localise
    # précisément (`AKIA` ne vit que là où l'on parle de détection de clés) ; un
    # identifiant répandu ne fait que situer le quartier. Une seule correspondance
    # répandue ne suffit donc pas à réclamer une relecture : le diff d'un script
    # mentionne des noms de configuration dans ses commentaires sans que rien de
    # cette configuration ait bougé.
    def weight(t):
        if doc_freq.get(t, 0) <= 3:
            return 3                      # nom quasi unique : localise à lui seul
        return 2 if is_named_thing(t) else 1

    matchers = [] if blind else [(t, re.compile(r'\b' + re.escape(t) + r'\b')) for t in disc]

    hot, maybe, cold = [], [], []
    for c, secs in docs.items():
        if os.path.abspath(c) == os.path.abspath(live):
            continue                      # se citer soi-même n'est pas un signal
        rc = os.path.relpath(c, H)
        for title, start, body in secs:
            n = body.count(k)
            if not n:
                continue
            if blind:
                hot.append((rc, title, start, n, [], 0))
                continue
            why = [t for t, rx in matchers if rx.search(body)]
            score = sum(weight(t) for t in why)
            why.sort(key=lambda t: (doc_freq.get(t, 0), t))     # le plus précis d'abord
            row = (rc, title, start, n, why, score)
            (hot if score >= 3 else maybe if score else cold).append(row)
    if hot or maybe or cold:
        hits.append((rel, k, blind, len(disc), hot, maybe, cold))

# Les éléments qui ont du chaud d'abord, puis par volume de chaud décroissant.
hits.sort(key=lambda h: (-len(h[4]), -len(h[5]), h[0]))

# ---------------------------------------------------------------------------
# 4. Rendu
# ---------------------------------------------------------------------------
def trunc(s, n=68):
    s = re.sub(r'\s+', ' ', s).strip()
    return s if len(s) <= n else s[:n - 1] + '…'

def render_tier(rows, mark, label, detail):
    """detail=True : une ligne par section, avec les identifiants qui l'ont désignée."""
    per = defaultdict(list)
    for rc, title, start, n, why, score in rows:
        per[rc].append((start, title, n, why, score))
    for rc in sorted(per):
        # Les sections les plus fortement désignées d'abord : c'est l'ordre de lecture.
        items = sorted(per[rc], key=lambda i: (-i[4], i[0])) if detail else sorted(per[rc])
        tot = sum(i[2] for i in items)
        head = f"    {mark} {label}  {rc}"
        if not detail:
            head += f" — {tot} mention(s) dans {len(items)} section(s) :"
        print(head)
        for start, title, n, why, score in items:
            suffix = f"   ×{n}" if n > 1 else ""
            print(f"          l.{start}  {trunc(title)}{suffix}")
            if detail and why:
                shown = ', '.join(why[:5]) + ('…' if len(why) > 5 else '')
                print(f"                  ↳ parle de : {shown}"
                      + (f"  ({len(why)} au total)" if len(why) > 5 else ""))

if not hits:
    print("=== Retombée documentaire : aucun document ne nomme ce qui a changé ===")
else:
    n_hot = sum(1 for h in hits if h[4])
    n_sec = sum(len(h[4]) for h in hits)
    print(f"=== Retombée documentaire — {len(hits)} élément(s) modifié(s) nommé(s) ailleurs ===")
    print(f"    À relire en priorité : {n_sec} section(s), sur {n_hot} élément(s).")
    print()
    # Sommaire d'entrée : par quoi commencer. Ce n'est pas un plafond — la liste
    # complète suit, élément par élément, et rien n'en est retiré.
    flat = sorted(((sc, rc, ti, st, rel) for rel, k, b, nd, hot, mb, cd in hits
                   for rc, ti, st, n, why, sc in hot),
                  key=lambda x: (-x[0], x[1], x[3]))
    if len(flat) > 10:
        print(f"    Par quoi commencer — les 10 sections les plus fortement désignées "
              f"sur {len(flat)} :")
        for sc, rc, ti, st, rel in flat[:10]:
            print(f"      {rc}  l.{st}  {trunc(ti, 52)}   ← {os.path.basename(rel)}")
        print()
    for rel, k, blind, ndisc, hot, maybe, cold in hits:
        head = f"▸ {rel}   (recherché : {k}"
        head += f" · TRI IMPOSSIBLE : {blind}" if blind else f" · {ndisc} identifiant(s) du diff"
        print(head + ")")
        if hot:
            render_tier(hot, '●', 'À RELIRE', True)
        if maybe:
            render_tier(maybe, '◐', 'à survoler', True)
        if cold:
            render_tier(cold, '○', 'froid     ', False)
        print()

print("● à relire : la section nomme le fichier ET parle de ce qui a bougé.")
print("◐ à survoler : correspondance unique et sur un nom répandu — souvent le quartier,")
print("  pas le sujet. ○ froid : la section nomme le fichier sans parler du changement.")
print("Les froides restent listées parce qu'un tri qui cache est pire que pas de tri ;")
print("elles ne se relisent simplement pas systématiquement. Un « TRI IMPOSSIBLE » n'est")
print("pas un feu vert : c'est le contrôle qui dit ne pas savoir, et tout passe en ●.")
print("Limite inchangée : une liste vide ne vaut pas quitus — un document peut décrire un")
print("comportement sans nommer le fichier qui le porte. Le journal, les archives de")
print("session et les rapports d'audit sont volontairement hors du champ (ce sont des")
print("traces datées : elles doivent rester telles quelles).")
PYEOF
