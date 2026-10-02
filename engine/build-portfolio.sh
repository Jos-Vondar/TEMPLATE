#!/usr/bin/env bash
# À LA DEMANDE SEULEMENT depuis le 2026-08-22 — retiré de la passe hebdomadaire (geste 9
# d'`HYGIENE.md`), décision de l'utilisateur après l'audit contradictoire. Motif : aucun script
# ne lit sa sortie, et le fichier n'avait été ouvert qu'une fois sur un mois. Le lancer quand la
# question « qu'a-t-on livré » se pose, pas par calendrier.
# =============================================================================
# BUILD PORTFOLIO — ClaudeOS
# Génère `memory/PORTFOLIO.md` : ce qu'on a PRODUIT, et le fil du temps par projet.
#
# Pourquoi ce fichier existe : le reste du système indexe les décisions et les règles.
# Rien n'indexait les livrables. À la question « qu'est-ce qu'on a fait sur ce projet »,
# il fallait relire cinquante-huit digests de session et fouiller les dossiers.
#
# INTÉGRALEMENT GÉNÉRÉ, jamais édité à la main : tout est dérivé des noms de fichiers,
# des titres et du journal de session. Un registre tenu à la main ne serait pas tenu.
# Régénéré à la passe hebdomadaire, par la fiche d'hygiène (geste 9) — plus à chaque
# sauvegarde depuis le 2026-08-05. Commentaire corrigé le 2026-08-22 : il affirmait l'ancienne cadence.
# =============================================================================
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

OUT="$MEM/PORTFOLIO.md"

python3 - "$MEM" "$(claudeos_ws_roots)" "$OUT" "$(date +%Y-%m-%d)" "$REG" <<'PYEOF'
import os, re, sys, glob, collections, fnmatch

MEM, OUT, TODAY, REG = sys.argv[1], sys.argv[3], sys.argv[4], sys.argv[5]
# Racines des dossiers de travail : `claudeos_ws_roots`, une par ligne, jamais en dur — un
# dossier déclaré ailleurs serait sauvegardé sans jamais entrer au portfolio, sans un mot.
ROOTS = [r for r in sys.argv[2].splitlines() if r.strip()]

def lignes(nom):
    """Les lignes utiles d'un réglage de `reglages/`, facultatif : [] s'il manque."""
    try:
        with open(os.path.join(REG, nom), encoding='utf-8') as f:
            return [l.strip() for l in f if l.strip() and not l.lstrip().startswith('#')]
    except OSError:
        return []

# Les documents de référence de métier : `reglages/DOCS_REFERENCE`, un nom ou un motif par
# ligne. Ils portent leur version en tête, pas une date dans leur nom.
REFERENCES = lignes('DOCS_REFERENCE')
def est_reference(name):
    return any(fnmatch.fnmatch(name, m) for m in REFERENCES)
H = os.path.expanduser('~')

# ---------------------------------------------------------------- livrables --
# Heuristique de propriété : un livrable QU'ON A PRODUIT porte une date en tête de nom
# (convention du système) ou vit dans un emplacement de production connu. Les pièces
# fournies PAR le client ne suivent pas cette convention — c'est ce qui les distingue.
DATED   = re.compile(r'(\d{4}-\d{2}-\d{2})[-_.]')
REPORT  = re.compile(r'rapport-(\d{4}-\d{2}-\d{2})')

def kind(path, name):
    p = path.lower()
    n0 = ' ' + name.lower().replace('_', ' ') + ' '
    if name.startswith(('CR_', 'CR-')) or ' cr ' in n0: return 'compte rendu de réunion'
    if name.startswith(('NOTES_', 'NOTES-')): return 'notes de travail'
    if '/specs/' in p or name.lower().startswith('spec'): return 'spécification'
    if '/plans/' in p: return "plan d'implémentation"
    if '/rapports/' in p or REPORT.search(name): return 'rapport périodique'
    if est_reference(name): return 'document de référence'
    if name in ('DESIGN.md', 'SYSTEM_DESIGN.md'): return 'référence de conception'
    n = name.lower()
    if 'feasibility' in n or 'faisabilite' in n: return 'note de faisabilité'
    if n.startswith('rfc'): return 'RFC'
    if 'brief' in n: return 'brief'
    if 'prompt' in n: return 'prompt de production'
    if 'cadrage' in n: return 'note de cadrage'
    if 'memoire' in n: return 'mémoire'
    if n.endswith(('.ps1', '.py')): return 'script'
    if n.endswith(('.pptx', '.pdf')): return 'support'
    return 'note'

def title_of(path, name):
    if path.endswith('.md'):
        try:
            for line in open(path, encoding='utf-8'):
                if line.startswith('# '):
                    return re.sub(r'\s+', ' ', line[2:]).strip()[:110]
        except OSError:
            pass
    return name

def scope(path, root):
    """(domaine, projet) déduits de l'arborescence. Le domaine EST le nom de la racine."""
    rel = os.path.relpath(path, root).split(os.sep)
    dom = os.path.basename(root)
    proj = rel[0] if len(rel) > 1 else ''
    return dom, proj

items = []
for root in ROOTS:
  for path in glob.glob(f'{root}/**/*', recursive=True):
    if not os.path.isfile(path): continue
    if '/_IGNORE/' in path or '/extracted/' in path or '/scaffold/' in path: continue
    if '/__pycache__/' in path or '/source/' in path: continue
    name = os.path.basename(path)
    m = DATED.search(name) or REPORT.search(name)
    if m:
        date = m.group(1)
    elif est_reference(name):
        date = ''                       # daté par son en-tête de version, pas par son nom
    else:
        continue
    dom, proj = scope(path, root)
    items.append({'date': date, 'dom': dom, 'proj': proj, 'kind': kind(path, name),
                  'title': title_of(path, name), 'path': os.path.relpath(path, H),
                  'scope': f'{dom}/{proj}' if proj else dom})

# Les documents de référence n'ont pas de date de nom : on prend la version de leur en-tête.
VER = re.compile(r'V?(\d+\.\d+(?:\.\d+)?)')
for it in items:
    if it['kind'] == 'document de référence':
        try:
            head = open(os.path.join(H, it['path']), encoding='utf-8').readline()
        except OSError:
            head = ''
        v = VER.search(head)
        it['title'] = f"{it['proj']} — version {v.group(1)}" if v else it['proj']

dated   = sorted([i for i in items if i['date']], key=lambda i: i['date'], reverse=True)
undated = sorted([i for i in items if not i['date']], key=lambda i: (i['dom'], i['proj']))

# ------------------------------------------------------------- fil du temps --
# Projets = dossiers réels de niveau 2, plus les sujets qui vivent ailleurs qu'en dossier.
projects = {}
for root in ROOTS:
    for d in sorted(glob.glob(f'{root}/*')):
        if os.path.isdir(d) and not os.path.basename(d).startswith('_'):
            projects[f'{os.path.basename(root)}/{os.path.basename(d)}'] = [os.path.basename(d)]
# LES ALIAS se lisent dans `reglages/ALIAS`, une ligne `<clé>: alias1, alias2` : ils rattachent
# à un projet des sessions qui le nomment autrement. La clé est calculée comme plus haut,
# `basename(racine)/basename(dossier)` — une clé qui n'existe pas créerait un projet fantôme.
ALIAS = {}
for l in lignes('ALIAS'):
    cle, _, reste = l.partition(':')
    if cle.strip() and reste.strip():
        ALIAS[cle.strip()] = [a.strip() for a in reste.split(',') if a.strip()]
for k, v in ALIAS.items():
    projects.setdefault(k, []).extend(v)

sessions = []
for f in (f'{MEM}/SESSION_JOURNAL.md', f'{MEM}/SESSION_ARCHIVE.md'):
    try: txt = open(f, encoding='utf-8').read()
    except OSError: continue
    for m in re.finditer(r'^## (\d{4}-\d{2}-\d{2})([^\n]*)\n(.*?)(?=^## |\Z)', txt, re.M | re.S):
        head = m.group(2).split('|')
        label = head[-1].strip() if len(head) > 1 else ''
        sessions.append((m.group(1), label, m.group(3)))
sessions.sort(key=lambda s: s[0], reverse=True)

MAX = 12   # par projet : au-delà, on compte le reste plutôt que de tout dérouler

# ------------------------------------------------------------------- sortie --
L = ['# PORTFOLIO — ce qu\'on a produit, et quand',
     '',
     f'> **Snapshot au {TODAY}, par `engine/build-portfolio.sh`. Ne pas éditer à la main** —',
     "> tout est dérivé des noms de fichiers, des titres et du journal de session ; une",
     "> édition manuelle serait perdue à la régénération. Il ne se régénère PAS tout seul —",
     "> aucun script ne l'appelle, le geste a quitté la passe hebdomadaire le 2026-08-22 :",
     '> le relancer à la demande, quand la question se pose.',
     '>',
     "> Ce que ce fichier répond : « qu'est-ce qu'on a produit », « où on en est sur ce projet",
     "> depuis le début ». Ce qu'il ne répond pas : la valeur ou l'état de validité d'un livrable —",
     '> pour ça, ouvrir le document. Les pièces fournies par un client ne sont pas listées :',
     "> seuls les artefacts qu'on a produits le sont (reconnus à leur date en tête de nom).",
     '']

L += ['## Registre des livrables', '',
      f'{len(dated)} artefacts datés, du {dated[-1]["date"] if dated else "—"} au {dated[0]["date"] if dated else "—"}.', '',
      '| Date | Domaine · projet | Type | Titre | Chemin |', '| :--- | :--- | :--- | :--- | :--- |']
for i in dated:
    where = f'{i["dom"]}' + (f' · {i["proj"]}' if i['proj'] else '')
    L.append(f'| {i["date"]} | {where} | {i["kind"]} | {i["title"]} | `{i["path"]}` |')

if undated:
    L += ['', '### Sources de vérité vivantes (versionnées, pas datées)', '',
          '| Domaine · projet | Type | État | Chemin |', '| :--- | :--- | :--- | :--- |']
    for i in undated:
        where = f'{i["dom"]}' + (f' · {i["proj"]}' if i['proj'] else '')
        L.append(f'| {where} | {i["kind"]} | {i["title"]} | `{i["path"]}` |')

L += ['', '## Fil du temps par projet', '',
      "Sessions où le projet apparaît, du plus récent au plus ancien, et les livrables produits.",
      'La source est le digest de session : il dit ce qui a été fait, pas ce qui reste vrai.', '']

for proj, keys in sorted(projects.items()):
    pat = re.compile('|'.join(re.escape(k) for k in keys), re.I)
    # Chercher le projet dans TOUT le corps attrape les mentions de passage : une session
    # « refonte du système » qui cite un projet en aparté n'est pas une session de ce projet.
    # L'intitulé, lui, dit de quoi la session traitait. On liste sur l'intitulé, et on compte
    # à part les sessions qui ne font que mentionner — l'information reste, sans noyer la vue.
    mine = [(d, lab) for d, lab, body in sessions if pat.search(lab)]
    aside = len([1 for d, lab, body in sessions if not pat.search(lab) and pat.search(body)])
    # Appariement sur le PÉRIMÈTRE calculé (domaine/projet), et non sur un `workstations/`
    # cherché dans le chemin : depuis le 2026-08-09 la racine vient du manifeste et n'a plus
    # à s'appeler ainsi. Le périmètre s'arrête au niveau projet, donc un livrable niché sous
    # une application porte le périmètre de son projet et l'égalité suffit.
    livr = [i for i in dated if i['scope'] == proj]
    if not mine and not livr and not aside: continue
    L.append(f'### {proj}')
    L.append('')
    if livr:
        L.append(f'**Livrables ({len(livr)})** — ' + ' · '.join(
            f'{i["date"]} {i["kind"]}' for i in livr[:8]) + (' …' if len(livr) > 8 else ''))
        L.append('')
    if mine:
        L.append(f'**Sessions ({len(mine)})**, de {mine[-1][0]} à {mine[0][0]} :')
        L.append('')
        for d, lab in mine[:MAX]:
            L.append(f'- {d} — {lab or "(sans intitulé)"}')
        if len(mine) > MAX:
            L.append(f'- … et {len(mine) - MAX} sessions plus anciennes (voir `SESSION_ARCHIVE.md`)')
        L.append('')
    if aside:
        L.append(f'Mentionné en aparté dans {aside} autre(s) session(s), sans en être le sujet.')
        L.append('')

open(OUT, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
print(f"[portfolio] {len(dated)} livrables datés, {len(undated)} sources vivantes, "
      f"{len([p for p in projects])} projets balayés → {os.path.relpath(OUT, H)}")
PYEOF
