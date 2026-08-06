#!/usr/bin/env bash
# =============================================================================
# BUILD THREADS — ClaudeOS
# Génère `memory/OPEN_THREADS.md` : tout ce qui reste à faire, tous projets, par ancienneté.
#
# Pourquoi : le démarrage ne montrait que les fils ouverts de la DERNIÈRE session. Un fil
# reporté de session en session était donc réaffiché fidèlement sans jamais être vu comme
# ancien. L'audit du 2026-07-25 a trouvé deux fils portés depuis 19 et 9 jours, reconduits
# à chaque « Next » et jamais traités. Ce fichier donne l'ancienneté et la récurrence, qui
# sont la matière d'une proposition — un état ne propose rien, un âge si.
#
# INTÉGRALEMENT GÉNÉRÉ, jamais édité : dérivé du journal, des archives, des fichiers de
# reprise et des rappels datés. Régénéré à chaque sauvegarde, donc juste après l'écriture
# de la reprise : au démarrage suivant il reflète le dernier état connu.
# =============================================================================
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

python3 - "$MEM" "$HOME" "$(date +%Y-%m-%d)" <<'PYEOF'
import os, re, sys, glob, datetime

MEM, H, TODAY = sys.argv[1], sys.argv[2], sys.argv[3]
today = datetime.date.fromisoformat(TODAY)

def age(d):
    try: return (today - datetime.date.fromisoformat(d)).days
    except Exception: return None

# ------------------------------------------------------------- récolte brute --
def prose_items(block):
    """Items d'un paragraphe de fils ouverts rédigé en prose, séparés par des points-virgules."""
    txt = re.sub(r'\s+', ' ', ' '.join(l.strip() for l in block.splitlines() if l.strip())).strip()
    if not txt: return []
    out = []
    for p in re.split(r'\s*;\s*', txt):
        p = re.sub(r'^(?:et|puis|enfin|ainsi que)\s+', '', p.strip(' .'), flags=re.I)
        if len(p) > 20: out.append(p)
    return out

def bullets(block):
    """Puces de premier niveau d'un bloc, repliées sur une ligne.

    Repli sur la prose quand il n'y a aucune puce : le journal écrit ses fils ouverts en
    paragraphe (« ... : A ; B ; et C »), les fichiers de reprise en liste. Un lecteur qui
    ne connaît que la liste rend zéro fil pour la dernière séance, et comme l'état vivant
    est celui de la *dernière* séance journalisée, la vue retombe alors sur une séance plus
    ancienne : elle reconduit des fils déjà soldés et ignore les vrais. Constaté les 03 et
    04/08/2026, sur les deux symptômes à la fois.
    """
    out, cur = [], None
    for line in block.splitlines():
        if re.match(r'^- ', line):
            if cur: out.append(cur)
            cur = line[2:].strip()
        elif cur is not None and line.startswith(('  ', '\t')) and line.strip():
            cur += ' ' + line.strip()
        elif cur and not line.strip():
            out.append(cur); cur = None
        elif line.startswith(('**', '#', '---')):
            if cur: out.append(cur); cur = None
    if cur: out.append(cur)
    items = [b for b in out if len(b) > 20]
    return items if items else prose_items(block)

# Le marqueur porte un libellé variable (« Fils ouverts », « Fils ouverts à la clôture ») et,
# en prose, les fils suivent le deux-points sur la MÊME ligne : la capture doit donc démarrer
# après le libellé, pas après le retour à la ligne.
#
# « Reste à faire » est le second titre sous lequel une reprise tient ses fils : la reprise
# système y garde les siens, la section « Fils ouverts, autres niveaux » du même fichier étant
# réservée aux autres niveaux. Sans ce titre, les fils du système ne remontaient par aucune
# source et ne surgissaient au démarrage que par l'accident d'un repli sur une séance périmée.
# Le titre ne se duplique pas en « Fils ouverts, système » exprès : deux listes du même état
# à deux âges se contredisent (CLAUDE.md §1, règle de tri). Ancré en début de ligne, donc une
# occurrence en cours de phrase ne déclenche rien.
FILS = re.compile(r'^\*{0,2}#{0,3}\s*(?:Fils ouverts|Reste à faire)\b[^\n]*?(?:\*{0,2}\s*:\s*|$)(.*?)'
                  r'(?=^\*\*[A-ZÀ-Ü]|^#{2,3} |\Z)', re.M | re.S)

# 1) Journal (état vivant) et archives (pour dater la première apparition)
sessions = []
for f, live in ((f'{MEM}/SESSION_JOURNAL.md', True), (f'{MEM}/SESSION_ARCHIVE.md', False)):
    try: txt = open(f, encoding='utf-8').read()
    except OSError: continue
    for m in re.finditer(r'^## (\d{4}-\d{2}-\d{2})[^\n]*\n(.*?)(?=^## |\Z)', txt, re.M | re.S):
        date, body = m.group(1), m.group(2)
        for fm in FILS.finditer(body):
            for b in bullets(fm.group(1)):
                sessions.append({'date': date, 'text': b, 'live': live})

STOP = set('''de des du la le les un une et ou à au aux en dans sur pour par avec sans sous
que qui quoi dont est sont a ont été être plus moins non pas ne se sa son ses ce cet cette
il elle on nous vous ils elles y d l s n c j t si mais donc or car déjà encore toujours
tout tous toute toutes autre autres même autant depuis vers chez entre'''.split())

def tokens(s):
    s = re.sub(r'`[^`]*`', ' ', s.lower())
    return {w for w in re.findall(r'[a-zà-ÿ0-9]{4,}', s) if w not in STOP}

def first_seen(text, before):
    """Plus ancienne session portant un fil manifestement identique (recouvrement de mots)."""
    tk = tokens(text)
    if len(tk) < 3: return before, 1
    best, n = before, 0
    for s in sessions:
        if s['date'] > before: continue
        o = tk & tokens(s['text'])
        if len(o) >= max(3, int(0.34 * len(tk))):
            n += 1
            if s['date'] < best: best = s['date']
    return best, n

# 2) Fichiers de reprise : l'état courant autoritatif de chaque niveau
handoffs = []
# Quatre niveaux, pas trois. Le quatrième — les applications — a été ajouté le 2026-08-05 :
# le lecteur s'arrêtait à `workstations/*/*/`, donc les reprises d'application d'un projet
# n'étaient JAMAIS lues. Celle de l'une d'elles était fraîche de la veille, correctement
# formée, et invisible dans la vue du matin. Défaut silencieux par construction : rien ne
# signale qu'un fichier bien écrit n'est pas ratissé. Choix assumé de faire descendre le
# lecteur plutôt que de remonter le contenu — la reprise reste au niveau où le travail a lieu.
for f in sorted(glob.glob(f'{H}/.claude/HANDOFF.md') + glob.glob(f'{H}/workstations/*/HANDOFF.md')
                + glob.glob(f'{H}/workstations/*/*/HANDOFF.md')
                + glob.glob(f'{H}/workstations/*/*/*/HANDOFF.md')):
    if '.sync-backups' in f: continue
    try: txt = open(f, encoding='utf-8').read()
    except OSError: continue
    maj = re.search(r'Derni[èe]re (?:MAJ|mise à jour)\s*:\s*(\d{4}-\d{2}-\d{2})', txt)
    lvl = os.path.relpath(os.path.dirname(f), H).replace('.claude', 'système')
    for fm in FILS.finditer(txt):
        for b in bullets(fm.group(1)):
            handoffs.append({'level': lvl, 'text': b, 'maj': maj.group(1) if maj else None})

# 3) Rappels datés : la seule source à échéance explicite
reminders = []
try:
    for line in open(f'{MEM}/REMINDERS.md', encoding='utf-8'):
        m = re.match(r'^-\s*(\d{4}-\d{2}-\d{2})\s*\|\s*(.+)$', line.strip())
        if m: reminders.append({'date': m.group(1), 'text': m.group(2).strip()})
except OSError:
    pass
# Un rappel dont l'échéance n'est pas atteinte n'est pas en retard. Sans ce partage,
# age() rend un nombre négatif et la vue affiche « -5 j de retard » sous les échéances
# dépassées : du travail pas encore dû est présenté comme en souffrance, et la
# proposition du matin le priorise à tort. Le démarrage, lui, filtrait déjà sur la date.
due     = [r for r in reminders if (age(r['date']) or 0) >= 0]
pending = [r for r in reminders if (age(r['date']) or 0) <  0]

# 4) Ratés de routage non traités
misses = []
try:
    t = open(f'{MEM}/ROUTING_MISSES.md', encoding='utf-8').read()
    sec = re.search(r'## Ouverts\n(.*?)(?=^## |\Z)', t, re.M | re.S)
    if sec: misses = bullets(sec.group(1))
except OSError:
    pass

# ------------------------------------------------------- classement du geste --
BLOQUE   = re.compile(r"faire ouvrir|à faire ouvrir|en attente d|admin |c[oô]t[eé] client|"
                      r"habilitation refus|acc[eè]s .*(?:tiers|op[eé]rateur)|par un admin|d[eé]pend d", re.I)
TRANCHER = re.compile(r"d[eé]cision utilisateur|à trancher|arbitrer|à confirmer|question|"
                      r"assum[eé]|volontaire \?|lequel est canonique|"
                      # « décider si X ou Y » est la forme la plus courante en prose et
                      # n'était couverte par aucun motif : le fil sortait en « faire ».
                      r"d[eé]cider (?:si|entre|lequel|laquelle|o[uù]|quoi|quand)", re.I)

def gesture(txt):
    if BLOQUE.search(txt):   return 'relancer'      # quelqu'un d'autre tient la balle
    if TRANCHER.search(txt): return 'trancher'      # une décision de l'utilisateur suffit
    return 'faire'

# ------------------------------------------------------------------- montage --
# L'ÉTAT VIVANT est celui de la dernière session journalisée, pas l'union des six.
# Un fil réglé hier figure encore dans l'entrée de la semaine dernière — c'est normal, une
# entrée de journal est un enregistrement daté, pas un état. Prendre l'union ferait remonter
# des fils soldés (constaté au premier essai : deux d'entre eux l'étaient dans la journée).
live_dates = sorted({s['date'] for s in sessions if s['live']}, reverse=True)
live = [s for s in sessions if s['live'] and live_dates and s['date'] == live_dates[0]]

# Regroupement : un même sujet est reformulé à chaque session, donc il apparaîtrait autant
# de fois qu'il a été reconduit. On agrège par recouvrement de vocabulaire, on garde la
# formulation la plus récente, la date la plus ancienne et le compte de reconductions.
items = []
for s in sorted(live, key=lambda x: x['date'], reverse=True):
    tk = tokens(s['text'])
    for it in items:
        o = tk & it['tk']
        if len(o) >= max(3, int(0.4 * min(len(tk), len(it['tk'])))):
            it['tk'] |= tk
            break
    else:
        since, rec = first_seen(s['text'], s['date'])
        items.append({'text': s['text'], 'since': since, 'age': age(since),
                      'recur': rec, 'gest': gesture(s['text']), 'tk': tk})
items.sort(key=lambda i: (-(i['age'] or 0), -i['recur']))

L = ['# OPEN THREADS — ce qui reste à faire, par ancienneté', '',
     f'> **Généré le {TODAY} par `engine/build-threads.sh`. Ne pas éditer à la main.**',
     '>',
     "> Source : fils ouverts du journal pour l'état vivant, archives pour dater la première",
     "> apparition, fichiers de reprise par niveau, rappels datés, ratés de routage. L'âge est",
     '> celui de la **première** apparition du fil, pas de la dernière : un fil reconduit de',
     "> session en session est ancien même s'il vient d'être réécrit.",
     '>',
     "> Le geste attendu est déduit du texte : **relancer** quand la balle est chez quelqu'un",
     "> d'autre, **trancher** quand une décision suffit, **faire** sinon. C'est une heuristique,",
     '> pas un jugement : elle sert à ne pas proposer comme travail du jour ce qui attend un tiers.', '']

if due:
    L += ['## Échéances dépassées', '']
    for r in sorted(due, key=lambda r: r['date']):
        a = age(r['date'])
        L.append(f"- **{a} j de retard** (échu le {r['date']}) — {r['text']}")
    L.append('')

if pending:
    L += ['## Échéances à venir (pas en retard)', '']
    for r in sorted(pending, key=lambda r: r['date']):
        L.append(f"- **dans {-age(r['date'])} j** (échéance {r['date']}) — {r['text']}")
    L.append('')

L += ['## Fils ouverts du journal', '',
      '| Âge | Depuis | Reconduit | Geste | Fil |', '| ---: | :--- | ---: | :--- | :--- |']
for i in items:
    txt = re.sub(r'\s+', ' ', i['text'])[:190]
    rec = f"{i['recur']}×" if i['recur'] > 1 else '—'
    L.append(f"| {i['age']} j | {i['since']} | {rec} | {i['gest']} | {txt} |")
L.append('')

if handoffs:
    L += ['## Par niveau, selon les fichiers de reprise', '']
    cur = None
    for h in handoffs:
        if h['level'] != cur:
            cur = h['level']
            m = f" (reprise écrite le {h['maj']})" if h['maj'] else ''
            L += ['', f'**{cur}**{m}', '']
        L.append(f"- {re.sub(chr(92)+'s+', ' ', h['text'])[:210]}")
    L.append('')

if misses:
    L += ['## Ratés de routage non traités', ''] + [f'- {m}' for m in misses] + ['']

top = [i for i in items if i['gest'] != 'relancer'][:3]
relance = [i for i in items if i['gest'] == 'relancer'][:2]
L += ['## Proposition', '',
      "Dérivée de l'ancienneté et du geste, pas d'un jugement sur l'importance. À confronter",
      'à ce que tu sais du contexte, qui n\'est pas dans ces fichiers.', '']
for i in top:
    L.append(f"- **{i['gest'].capitalize()}** — {re.sub(chr(92)+'s+',' ',i['text'])[:160]} "
             f"(ouvert depuis {i['age']} j)")
for i in relance:
    L.append(f"- **Relancer** (la balle n'est pas chez toi) — {re.sub(chr(92)+'s+',' ',i['text'])[:160]} "
             f"(depuis {i['age']} j)")
if not top and not relance:
    L.append('- Rien d\'ancien en attente.')

open(f'{MEM}/OPEN_THREADS.md', 'w', encoding='utf-8').write('\n'.join(L) + '\n')
print(f"[threads] {len(items)} fils vivants, {len(due)} échéance(s) dépassée(s), "
      f"{len(pending)} à venir, "
      f"{len(handoffs)} entrée(s) de reprise, {len(misses)} raté(s) → memory/OPEN_THREADS.md")
PYEOF
