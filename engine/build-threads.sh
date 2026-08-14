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

python3 - "$MEM" "$HOME" "$(date +%Y-%m-%d)" "$CFG/CRENEAUX" "$(claudeos_ws_roots)" <<'PYEOF'
import os, re, sys, glob, datetime

MEM, H, TODAY, CRENEAUX = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
today = datetime.date.fromisoformat(TODAY)

# Racines des workstations dérivées du MANIFESTE depuis le 2026-08-09 (claudeos_ws_roots) :
# `$HOME/workstations` en dur ici aurait rendu invisible la reprise d'une workstation
# déclarée ailleurs — un fichier bien écrit que rien ne ratisse, le défaut silencieux déjà
# payé le 2026-08-05 sur le niveau application.
WS_ROOTS = {os.path.basename(r): r for r in sys.argv[5].splitlines() if r.strip()}

def age(d):
    try: return (today - datetime.date.fromisoformat(d)).days
    except Exception: return None

# ------------------------------------------------------- créneaux hebdomadaires --
# Ajouté le 2026-08-09 (le document de conception, conçu le 2026-07-25). L'ancienneté d'un fil
# rattaché à un créneau se mesure en CRÉNEAUX MANQUÉS, pas en jours calendaires :
# « trois créneaux sans avancer » est un fait, « dix-neuf jours de retard » est un
# artefact d'unité, qui fait passer un calendrier pour de la négligence.
#
# L'attribution d'un fil à un domaine se fait sur les noms DÉCLARÉS — le nom de la
# workstation et celui de ses projets, lus sur le disque — et jamais par inférence de
# sujet. Limite assumée, à ne pas prendre pour un bug : un fil qui ne nomme ni son
# domaine ni son projet (le projet sans son domaine) reste en jours calendaires.
# Sur-attribuer serait pire que sous-attribuer : un fil rangé dans le mauvais créneau
# cesse d'être proposé les jours où il est justement faisable.
DAYS = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim']
DAYNAME = {'lun': 'lundi', 'mar': 'mardi', 'mer': 'mercredi', 'jeu': 'jeudi',
           'ven': 'vendredi', 'sam': 'samedi', 'dim': 'dimanche'}

creneaux = {}     # workstation -> [indices de jours de la semaine, 0 = lundi]
try:
    for line in open(CRENEAUX, encoding='utf-8'):
        line = line.split('#', 1)[0].strip()
        if not line: continue
        f = line.split()
        if len(f) < 2: continue
        idx = sorted({DAYS.index(j) for j in f[1].split(',') if j in DAYS})
        if idx: creneaux[f[0]] = idx
except OSError:
    pass

# Mots qui rattachent un fil à un domaine : le nom de la workstation (avec ses
# variantes de séparateur) et le nom de chacun de ses PROJETS. On s'arrête au niveau
# projet : les dossiers d'application portent déjà le nom du projet en préfixe, et
# descendre plus bas n'ajoute que des motifs longs sans nouveau discriminant.
attrib = {}       # motif en minuscules -> workstation
for ws in creneaux:
    base = ws.lower()
    for v in {base, base.replace('_', ' '), base.replace('_', '-')}:
        attrib[v] = ws
    try:
        root = WS_ROOTS[ws]
        for p in sorted(os.listdir(root)):
            if os.path.isdir(f'{root}/{p}') and len(p) >= 4:
                attrib[p.lower()] = ws
    except (OSError, KeyError):
        pass
ATTRIB_RE = [(re.compile(r'(?<![a-z0-9])' + re.escape(k) + r'(?![a-z0-9])', re.I), w)
             for k, w in sorted(attrib.items(), key=lambda kv: -len(kv[0]))]

def domain(text):
    """Workstation à créneau que ce fil nomme, ou None."""
    for rx, ws in ATTRIB_RE:
        if rx.search(text): return ws
    return None

def missed(since, days):
    """Jours de créneau écoulés entre l'ouverture du fil et aujourd'hui, tous deux exclus.

    Le jour d'ouverture n'est pas manqué (le fil y est né), et aujourd'hui ne l'est pas
    encore — c'est l'occasion en cours. Sans ces deux bornes, la vue annonce un créneau
    manqué le jour même où le travail est faisable.
    """
    try: d = datetime.date.fromisoformat(since) + datetime.timedelta(days=1)
    except Exception: return None
    n = 0
    while d < today:
        if d.weekday() in days: n += 1
        d += datetime.timedelta(days=1)
    return n

def creneau_cell(ws, since):
    """« DOMAINE · 3 créneaux » — le domaine, puis l'ancienneté dans son unité."""
    days = creneaux[ws]
    n = missed(since, days)
    if n is None: return ws
    if len(days) == 1:
        unit = DAYNAME[DAYS[days[0]]] + ('s' if n != 1 else '')
    else:
        unit = 'créneaux' if n != 1 else 'créneau'
    return f'{ws} · {n} {unit}'

# ------------------------------------------------------------- récolte brute --
# Phrases-méta : tournures que le journal écrit DANS son paragraphe de fils ouverts pour dire
# que rien n'a bougé, ou pour renvoyer ailleurs. Ce ne sont pas des sujets, donc first_seen()
# ne doit pas leur donner d'âge — le recouvrement de vocabulaire les appariait de séance en
# séance et rendait un « fil de 37 jours » qui n'avait aucun objet (constaté le 2026-08-09,
# corrigé à la passe du 2026-08-10). Le vieillissement était le symptôme ; la cause est
# qu'une phrase d'état de la liste était comptée comme un élément de la liste.
#
# Ancré au DÉBUT de l'élément, et sur des tournures nommées une par une : un motif large
# écarterait des fils réels. Ce filtre est un poste de perte silencieuse — tout ajout ici se
# vérifie sur un fil réel qui doit survivre, pas seulement sur l'artefact qui doit tomber.
# Le journal l'écrit à la fin de son paragraphe et l'accole au fil précédent par un POINT,
# pas par un point-virgule : elle n'est donc jamais un élément à part, et un filtre ancré au
# début de l'élément ne la voit pas. Elle se retire par la queue — de son ouverture de phrase
# jusqu'au bout de l'élément. Constaté sur jeu d'essai le 2026-08-10, la première version du
# filtre laissant l'artefact intact.
META_QUEUE = re.compile(r'(?:(?<=\.)|(?<=\.\s)|^)\s*'
                        r'(?:fils?\s+(?:ouverts?\s+)?ant[ée]rieurs?\b'
                        r'|(?:la\s+)?passe\s+hebdo(?:madaire)?\s+(?:est\s+)?due\b)'
                        r'.*$', re.I | re.S)

def strip_meta(p):
    """Élément privé de sa queue de phrase-méta, chaîne vide s'il n'en restait que ça.

    Une phrase d'ÉTAT de la liste (« fils antérieurs inchangés », « passe hebdomadaire due »)
    n'est pas un élément de la liste. Laissée en place, first_seen() l'apparie de séance en
    séance par recouvrement de vocabulaire et vieillit le fil qui la porte : c'est ce qui a
    produit le « fil de 37 jours » sans objet du 2026-08-09.

    Poste de perte silencieuse : tout ajout de motif ici se vérifie sur un fil réel qui doit
    SURVIVRE, jamais seulement sur l'artefact qui doit tomber.
    """
    return META_QUEUE.sub('', p).strip(' .;—-')

def prose_items(block):
    """Items d'un paragraphe de fils ouverts rédigé en prose, séparés par des points-virgules."""
    txt = re.sub(r'\s+', ' ', ' '.join(l.strip() for l in block.splitlines() if l.strip())).strip()
    if not txt: return []
    out = []
    for p in re.split(r'\s*;\s*', txt):
        p = re.sub(r'^(?:et|puis|enfin|ainsi que)\s+', '', p.strip(' .'), flags=re.I)
        p = strip_meta(p)
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
    items = [s for s in (strip_meta(b) for b in out) if len(s) > 20]
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
# ÉLARGI le 2026-08-12, sur mesure. Le motif ne reconnaissait que ces deux titres exacts, et
# huit reprises sur seize en portaient d'autres — donc invisibles dans la vue du matin. Le pire
# cas mesuré : un projet tenait CINQ sections « Fil ouvert » au SINGULIER, dont une
# marquée PRIORITAIRE avec rappel au démarrage. Une lettre de différence, cinq fils perdus.
# Ce qui entre : le singulier des deux familles, « À faire », « Points ouverts », « À trancher ».
# Ce qui N'ENTRE PAS, et c'est délibéré : la liste des synonymes n'est pas énumérable — on ne
# devinera jamais toutes les façons d'écrire « à faire », et l'élargir sans fin ferait entrer du
# faux (le balayage de mesure a déjà pris « Deux outils du greffon découverts » pour un fil).
# C'est pourquoi l'élargissement va de pair avec le contrôle #26 de `selftest.sh`, qui AVERTIT
# quand une reprise porte une section d'allure « fils ouverts » non reconnue. Le motif attrape le
# courant, l'alarme rattrape le reste : sans elle, le défaut redevient silencieux au premier
# titre inventé.
# LA LIGNE À NE PAS FRANCHIR, pour que l'élargissement ne devienne pas une pente. On accepte
# les VARIANTES GRAMMATICALES d'une même phrase — singulier/pluriel, et la tête relative
# « Ce qui » que le français met devant (« Ce qui reste à faire » est la même phrase que
# « Reste à faire », pas une autre). On n'accepte PAS de nouveau synonyme : « À confirmer »,
# « En attente », « Ouvert / non tranché » désignent la même chose dans une autre langue, et
# les admettre relance l'énumération sans fin. Ces cas-là se RENOMMENT, et c'est le contrôle
# #26 de `selftest.sh` qui les nomme un par un.
FILS = re.compile(r'^\*{0,2}#{0,3}\s*(?:Ce qui )?'
                  r'(?:Fils? ouverts?|Reste à faire|À faire|Points? ouverts?|À trancher)'
                  r'\b[^\n]*?(?:\*{0,2}\s*:\s*|$)(.*?)'
                  r'(?=^\*\*[A-ZÀ-Ü]|^#{2,3} |\Z)', re.M | re.S | re.I)

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
_hf = [(f'{H}/.claude/HANDOFF.md', None)]
for _ws, _root in WS_ROOTS.items():
    for _pat in ('HANDOFF.md', '*/HANDOFF.md', '*/*/HANDOFF.md'):
        _hf += [(f, _ws) for f in glob.glob(f'{_root}/{_pat}')]
for f, ws in sorted(_hf, key=lambda t: t[0]):
    if '.sync-backups' in f: continue
    try: txt = open(f, encoding='utf-8').read()
    except OSError: continue
    maj = re.search(r'Derni[èe]re (?:MAJ|mise à jour)\s*:\s*(\d{4}-\d{2}-\d{2})', txt)
    lvl = os.path.relpath(os.path.dirname(f), H).replace('.claude', 'système')
    for fm in FILS.finditer(txt):
        for b in bullets(fm.group(1)):
            handoffs.append({'level': lvl, 'ws': ws, 'text': b,
                             'maj': maj.group(1) if maj else None})

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
        ws = domain(s['text'])
        items.append({'text': s['text'], 'since': since, 'age': age(since),
                      'recur': rec, 'gest': gesture(s['text']), 'tk': tk,
                      'cren': creneau_cell(ws, since) if ws else None})
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
     '> pas un jugement : elle sert à ne pas proposer comme travail du jour ce qui attend un tiers.',
     '>',
     "> La colonne **Créneau** nomme le domaine à créneau hebdomadaire que le fil cite, et son",
     "> ancienneté dans l'unité de ce créneau (« 3 créneaux »). Elle est vide quand le fil ne",
     '> nomme aucun domaine à créneau : son âge reste alors en jours calendaires. Un fil hors',
     "> créneau reste listé et daté — c'est le démarrage qui écarte de la PROPOSITION du jour ce",
     '> qui est impossible aujourd’hui, en relisant `engine/config/CRENEAUX`.', '']

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
      '| Âge | Depuis | Reconduit | Créneau | Geste | Fil |',
      '| ---: | :--- | ---: | :--- | :--- | :--- |']
for i in items:
    txt = re.sub(r'\s+', ' ', i['text'])[:190]
    rec = f"{i['recur']}×" if i['recur'] > 1 else '—'
    L.append(f"| {i['age']} j | {i['since']} | {rec} | {i['cren'] or '—'} | {i['gest']} | {txt} |")
L.append('')

if handoffs:
    L += ['## Par niveau, selon les fichiers de reprise', '']
    cur = None
    for h in handoffs:
        if h['level'] != cur:
            cur = h['level']
            m = f" (reprise écrite le {h['maj']})" if h['maj'] else ''
            # Le créneau se lit ici de la WORKSTATION du fichier, pas du texte du fil :
            # l'attribution est certaine et n'a pas à être devinée.
            c = f" · créneau {','.join(DAYS[d] for d in creneaux[h['ws']])}" \
                if h['ws'] in creneaux else ''
            L += ['', f'**{cur}**{m}{c}', '']
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
             f"(ouvert depuis {i['age']} j{', ' + i['cren'] if i['cren'] else ''})")
for i in relance:
    L.append(f"- **Relancer** (la balle n'est pas chez toi) — {re.sub(chr(92)+'s+',' ',i['text'])[:160]} "
             f"(depuis {i['age']} j{', ' + i['cren'] if i['cren'] else ''})")
if not top and not relance:
    L.append('- Rien d\'ancien en attente.')

open(f'{MEM}/OPEN_THREADS.md', 'w', encoding='utf-8').write('\n'.join(L) + '\n')
print(f"[threads] {len(items)} fils vivants, {len(due)} échéance(s) dépassée(s), "
      f"{len(pending)} à venir, "
      f"{len(handoffs)} entrée(s) de reprise, {len(misses)} raté(s) → memory/OPEN_THREADS.md")
PYEOF
