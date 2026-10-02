#!/usr/bin/env python3
"""import-v2.py — d'une V1 ou d'une V2 installée à la V3 : l'inventaire, la quarantaine, l'import.

Écrit le 2026-10-01, plan complet de templating § 3.2 et A7 (`d-migration-v3-neuf-import`). Code
PROPRE AU TEMPLATE, et le SEUL du moteur qui nomme légitimement les fichiers de la V1 et de la V2 :
il est hors du périmètre des noms morts du crochet (`CLAUDEOS_TEXTES_HORS_GARDE_RE`, `config.sh`).

La V2 ne se transforme pas en V3. La V3 s'installe à neuf, puis importe ce qui appartient à la
personne. La V2 reste INTACTE jusqu'au retrait : son dépôt local `~/.claudeos`, ses dossiers de
travail `~/workstations`, ses documents `~/docs` et `~/resources`, son dépôt de sauvegarde. Ce qu'elle
a posé dans `~/.claude` part en QUARANTAINE, vérifiée, et revient par `--restaurer`. RIEN NE SE
SUPPRIME, retrait compris : `--retrait` range sous `~/.claudeos-v2-archive/`, il n'efface rien.

L'état de la migration vit dans la quarantaine, `~/.claudeos-v2-quarantaine/<AAAAMMJJ-HHMMSS>/` :
  maison/      les copies, au chemin qu'elles avaient sous le dossier personnel
  MANIFESTE    `<sha256>  maison/<chemin>` de chaque copie, relu par `shasum -a 256 -c` d'ici
  ETAT         une ligne par chemin touché : deplace, copie, modifie (avec l'empreinte d'après),
               dossier, lien
  import/      ce que `--importer` a écrit, les listes à trancher, et DECISIONS, en ajout seul
La version installée se lit sur la V2 elle-même, comparée à `engine/config/V2_EMPREINTES` : une
table d'empreintes des étiquettes v1.1.0 à v2.2.0 du template, sans aucun texte de la V2, que
l'atelier régénère par `outils/reference-v2.py` en faisant tourner l'assembleur de chaque version.

Usage :
  import-v2.py --inventaire               lecture seule : V-1 à V-18, la version, les questions
  import-v2.py --quarantaine [--essai]    ce que la V2 a posé dans ~/.claude, en quarantaine
  import-v2.py --restaurer [--id ID]      la V2 remise comme avant la quarantaine
  import-v2.py --importer [--essai DOSSIER] [--secrets hors-depot|depot]
  import-v2.py --regle N garder|laisser [--texte TEXTE]
  import-v2.py --competence NOM regle|competence|rien
  import-v2.py --ressource NOM [--vers DOSSIER | --hors]
  import-v2.py --domaine D [--vers DOSSIER | --laisser]
  import-v2.py --retrait                  la V2 rangée sous ~/.claudeos-v2-archive/, rien d'effacé
  import-v2.py --verifier [--etape quarantaine|import|domaines|fin] [--id ID]
  --racine DOSSIER                        le système V3, au lieu de ~/.claude

Codes : 0 fait, ou conforme ; 1 refus ou défaut, chacun nommé, et rien n'est écrit ; 2 appel fautif,
ou un outil ou une table dont la mesure dépend manque — « je n'ai pas pu regarder » ne se lit jamais
comme « il n'y a rien ». Python 3.8 au moins, bibliothèque standard seule. Aucune question n'est
posée ici : l'agent confirme chaque geste avant de le lancer.
"""
import argparse
import difflib
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import date, datetime

ICI = os.path.dirname(os.path.abspath(__file__))
RACINE_MODELE = os.path.dirname(ICI)
REFERENCE = os.path.join(ICI, 'config', 'V2_EMPREINTES')
HOME = os.path.expanduser('~')
V2 = os.path.join(HOME, '.claudeos')
WS = os.path.join(HOME, 'workstations')
QUAR = os.path.join(HOME, '.claudeos-v2-quarantaine')
ARCHIVE = os.path.join(HOME, '.claudeos-v2-archive')

# Ce que la V2 accroche à Claude Code : ses crochets visent son moteur ou la dérive de `grilling`.
CROCHETS_V2 = ('/.claudeos/', 'check_upstream_drift.sh')
LIGNE_SHELL_V2 = '.claudeos/engine/boot-wrapper.sh'
SHELLS = ('.bashrc', '.zshrc', '.bash_profile')
MARQUE = '*(réglage : à remplir)*'
MARQUE_TABLE = '*(à remplir)*'
GEL = '> **GELÉ'
BLOC_V3 = '<!-- CLAUDEOS IMPORTS : DEBUT'
# Les douze rubriques de la V1 et de la V2 deviennent neuf (`d-persona-neuf-rubriques`) : une paire
# fusionnée reçoit les deux textes, à reprendre à l'entretien.
FUSION = (('Identité', ('Identité',)),
          ('Contradiction', ('Contradiction', 'Ni complaisance ni opposition systématique')),
          ("Pushback, dosé par l'enjeu", ("Pushback, dosé par l'enjeu", "Mise en cause d'un objectif")),
          ('Initiative', ("Proactivité d'options", 'Anticipation')),
          ('Pédagogie', ('Pédagogie',)),
          ('Franchise', ('Franchise',)),
          ('Périmètre du caractère', ('Périmètre du caractère',)),
          ('Humour', ('Humour',)),
          ('Forme de la voix', ('Forme de la voix',)))
# La mémoire V2 : vivante, elle est copiée ; chronique, elle est gelée ; générée, la V3 la refait.
MEMOIRE_GELEE = ('SESSION_JOURNAL.md', 'ORIGINES_DES_REGLES.md', 'INDEX.md', 'LEARNING_PROPOSALS.md')
MEMOIRE_GENEREE = ('OPEN_THREADS.md', 'PORTFOLIO.md')
# Où le squelette V2 posait chaque chose (`engine/manifest.sh` de chaque étiquette, la carte).
CARTE = (('system/skills/', '.claude/skills/'), ('system/fiches/', '.claude/fiches/'),
         ('system/output-styles/', '.claude/output-styles/'), ('system/DESIGN.md', '.claude/DESIGN.md'),
         ('system/RULES_CATALOG.md', '.claude/RULES_CATALOG.md'), ('resources/', 'resources/'),
         ('engine/', '.claudeos/engine/'))
IGNORES = ('.DS_Store', '__pycache__')


class Refus(Exception):
    """Le poste ne permet pas le geste : code 1, le motif nommé, rien d'écrit."""


class Appel(Exception):
    """L'appel est fautif, ou une table ou un outil manque : code 2."""


def dit(msg, err=False):
    print('[import-v2] ' + msg, file=sys.stderr if err else sys.stdout)


# ------------------------------------------------------------------------------- outils communs
def sha_octets(b):
    return hashlib.sha256(b).hexdigest()


def sha(chemin):
    h = hashlib.sha256()
    with open(chemin, 'rb') as f:
        for bloc in iter(lambda: f.read(65536), b''):
            h.update(bloc)
    return h.hexdigest()


def h16(ligne):
    return sha_octets(ligne.rstrip().encode('utf-8'))[:16]


def lit(chemin):
    try:
        return open(chemin, encoding='utf-8').read()
    except (OSError, UnicodeDecodeError):
        return None


def ecrit(chemin, texte):
    os.makedirs(os.path.dirname(chemin), exist_ok=True)
    neuf = chemin + '.neuf'
    with open(neuf, 'w', encoding='utf-8', newline='') as f:
        f.write(texte)
    if os.path.exists(chemin):
        os.chmod(neuf, os.stat(chemin).st_mode & 0o7777)
    os.replace(neuf, chemin)


def tilde(chemin):
    return '~' + chemin[len(HOME):] if chemin == HOME or chemin.startswith(HOME + os.sep) else chemin


def apostrophes(s):
    return s.replace('’', "'").strip()


def lance(cmd, cwd=None):
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, errors='replace', timeout=300)
        return r.returncode, r.stdout, r.stderr
    except FileNotFoundError:
        return 127, '', '%s : introuvable' % cmd[0]


def fichiers_sous(base):
    """Les fichiers et liens sous `base`, chemins relatifs à `base`, triés ; `base` peut être un fichier."""
    if os.path.islink(base) or os.path.isfile(base):
        return ['']
    sortie = []
    for d, sous, fs in os.walk(base):
        sous[:] = sorted(s for s in sous if s not in IGNORES and not os.path.islink(os.path.join(d, s)))
        for s in os.listdir(d):
            p = os.path.join(d, s)
            if os.path.islink(p):
                sortie.append(os.path.relpath(p, base))
        for f in sorted(fs):
            p = os.path.join(d, f)
            if f in IGNORES or os.path.islink(p):
                continue
            sortie.append(os.path.relpath(p, base))
    return sorted(set(sortie))


def dossiers_sous(base):
    if not os.path.isdir(base) or os.path.islink(base):
        return []
    sortie = []
    for d, sous, _ in os.walk(base):
        sous[:] = sorted(s for s in sous if s not in IGNORES and not os.path.islink(os.path.join(d, s)))
        sortie.append(os.path.relpath(d, base))
    return sorted(sortie)


def motif_config(racine, nom):
    """Un motif de `engine/config.sh`, lu par bash : il n'est jamais recopié ici."""
    cfg = os.path.join(racine, 'engine', 'config.sh')
    if not os.path.isfile(cfg):
        cfg = os.path.join(ICI, 'config.sh')
    rc, out, _ = lance(['bash', '-c', 'source "$1" >/dev/null 2>&1; printf "%s" "${!2}"', '_', cfg, nom])
    return out if rc == 0 and out else None


# ------------------------------------------------------------------------- la table de référence
def lit_reference():
    """La table `V2_EMPREINTES` : versions, fichiers, lignes du gabarit, rubriques du persona."""
    texte = lit(REFERENCE)
    if texte is None:
        raise Appel('table de référence illisible : %s — elle se régénère par outils/reference-v2.py' % REFERENCE)
    ref = {'versions': {}, 'fichiers': {}, 'gabarit': {}, 'persona': {}}
    for n, l in enumerate(texte.splitlines(), 1):
        if not l.strip() or l.startswith('#'):
            continue
        c = l.split(' ')
        try:
            if c[0] == 'version':
                ref['versions'][c[1]] = {'commit': c[2], 'posees': [] if c[3] == '-' else c[3].split(',')}
            elif c[0] == 'fichier':
                for t in c[3].split(','):
                    ref['fichiers'].setdefault(t, {})[c[2]] = c[1]
            elif c[0] == 'gabarit':
                conds = () if c[2] == '-' else tuple(c[2].split('+'))
                for t in c[3].split(','):
                    ref['gabarit'].setdefault(t, []).append((c[1], conds))
            elif c[0] == 'persona':
                for t in c[2].split(','):
                    ref['persona'].setdefault(t, {})[c[1]] = ' '.join(c[3:])
            else:
                raise ValueError(c[0])
        except (IndexError, ValueError):
            raise Appel('table de référence, ligne %d illisible : %r' % (n, l))
    if not ref['versions']:
        raise Appel('table de référence vide : %s' % REFERENCE)
    return ref


def ordre(tag):
    return tuple(int(x) for x in re.findall(r'\d+', tag))


# ------------------------------------------------------------- le règlement V2, lu comme l'assembleur
def sans_marqueurs(l):
    """Le `sed` d'`assemble-rules.sh` sur une ligne gardée : les marqueurs CONDITION et FIN tombent."""
    l = re.sub(r'`<!-- CONDITION [A-Z_]* -->` ', '', l)
    l = re.sub(r'<!-- CONDITION [A-Z_]* --> ', '', l)
    for s in (' `<!-- FIN -->`', '`<!-- FIN -->`', ' <!-- FIN -->', '<!-- FIN -->'):
        l = l.replace(s, '')
    return l


def normalise(texte):
    """Les lignes d'un règlement V1 ou V2 telles que l'assembleur les laisse : marqueurs retirés, notes
    WIZARD retirées, sur une ou plusieurs lignes, comme le font ses deux expressions `sed`. Sous macOS
    sans GNU sed, l'assembleur v2.2.0 échoue à cette étape et LAISSE les notes (mesuré le 2026-10-01) :
    on les retire donc ici, sur le fichier de la personne aussi."""
    sortie, dedans = [], False
    for l in texte.split('\n'):
        l = sans_marqueurs(l.rstrip('\r'))
        if dedans:
            if '-->' in l:
                dedans = False
            continue
        if re.search(r'<!-- WIZARD.*-->', l):
            continue
        if '<!-- WIZARD' in l:
            dedans = True
            continue
        sortie.append(l)
    return [l for l in sortie if l != '> `']


def titre(l):
    m = re.match(r'^(#{1,6})\s+(.*)$', l)
    return (len(m.group(1)), m.group(2).strip()) if m else None


def sections(lignes):
    """[(index, niveau, titre)] des titres, pour situer chaque ligne."""
    return [(i,) + titre(l) for i, l in enumerate(lignes) if titre(l)]


def zone(lignes, debut_re):
    """(i, j) : les lignes sous le premier titre qui correspond, jusqu'au titre suivant de même niveau ou plus haut."""
    for i, l in enumerate(lignes):
        t = titre(l)
        if t and re.match(debut_re, t[1]):
            for j in range(i + 1, len(lignes)):
                u = titre(lignes[j])
                if u and u[0] <= t[0]:
                    return i + 1, j
            return i + 1, len(lignes)
    return None


def rubriques_v2(lignes):
    """[(libellé, première ligne, [suite])] du bloc Persona ; [] sans bloc."""
    z = zone(lignes, r'^Persona$')
    if not z:
        return []
    sortie, courante = [], None
    for l in lignes[z[0]:z[1]]:
        m = re.match(r'^- \*\*(.+?)\*\*\s*:', l)
        if m:
            courante = [apostrophes(m.group(1)), l, []]
            sortie.append(courante)
        elif courante is not None and l.strip() and l[:1] in (' ', '\t'):
            courante[2].append(l)
        elif not l.strip():
            courante = None
    return sortie


def reglage_de(libelle, ligne, suite, empreintes):
    """(texte du réglage, énoncé reconnu). L'énoncé générique du gabarit — v1.1.0 à v2.1.0 sans marque,
    v2.2.0 suivi de la marque — se retire ; ce qui reste est le réglage de la personne. Une ligne égale
    à l'énoncé du gabarit n'a pas été réglée : son texte est vide."""
    if h16(ligne) in empreintes and not suite:
        return '', True
    m = re.match(r'^(- \*\*.+?\*\*\s*:\s*)(.*)$', ligne)
    tete, x = m.group(1), m.group(2)
    texte, reconnu = None, False
    if MARQUE in x:
        avant, apres = x.split(MARQUE, 1)
        reconnu = h16(tete + avant.rstrip() + ' ' + MARQUE) in empreintes
        texte = (avant.strip() + ' ' + apres.strip()).strip() if not reconnu else apres.strip()
    else:
        coupes = [len(x)] + sorted((i for i, c in enumerate(x) if c == ' '), reverse=True)
        for i in coupes:
            p = x[:i].rstrip()
            if h16(tete + p) in empreintes or h16(tete + p + ' ' + MARQUE) in empreintes:
                texte, reconnu = x[i:].strip(), True
                break
        if texte is None:
            texte = x.strip()
    lignes = [texte] if texte else []
    marge = min((len(l) - len(l.lstrip()) for l in suite), default=0)
    lignes += [l[marge:] for l in suite]
    return '\n'.join(lignes).strip(), reconnu


def table_domaines(lignes):
    """[(cellules)] des lignes de la table des domaines (§ 3.1), sans en-tête, séparateur ni marque."""
    z = zone(lignes, r'^3\.1\b')
    if not z:
        return []
    rangs = [l for l in lignes[z[0]:z[1]] if l.lstrip().startswith('|')]
    sortie = []
    for l in rangs[1:]:
        cellules = [c.strip() for c in l.strip().strip('|').split('|')]
        if all(re.fullmatch(r':?-{3,}:?', c) for c in cellules if c):
            continue
        if cellules and cellules[0] == MARQUE_TABLE:
            continue
        sortie.append(cellules)
    return sortie


def blocs_candidats(lignes, union):
    """Les blocs du règlement V2 qui ne viennent d'aucun gabarit : ajoutés ou modifiés par la personne.
    Le Persona et la table des domaines ont leur propre import ; un titre situe, il ne se propose pas."""
    exclus = set()
    for motif in (r'^Persona$',):
        z = zone(lignes, motif)
        if z:
            exclus |= set(range(z[0], z[1]))
    z = zone(lignes, r'^3\.1\b')
    if z:
        exclus |= {i for i in range(z[0], z[1]) if lignes[i].lstrip().startswith('|')}
    pile, blocs, courant = [], [], None
    item = re.compile(r'^\s*([-*+]|\d+\.)\s')
    for i, l in enumerate(lignes):
        t = titre(l)
        if t:
            pile = [p for p in pile if p[0] < t[0]] + [t]
            courant = None
            continue
        # La ligne d'import que `rtk init -g` ajoute au règlement : la V3 la pose dans son bloc d'imports
        # quand PROXY=oui, ce n'est pas une règle de la personne.
        if not l.strip() or i in exclus or l.strip() == '@RTK.md':
            courant = None
            continue
        neuf = h16(l) not in union
        suite = courant is not None and (l[:1] in (' ', '\t') or not (item.match(l) or l.lstrip().startswith(('|', '>'))))
        if suite:
            courant['lignes'].append(l)
            courant['neuf'] = courant['neuf'] or neuf
            continue
        courant = {'section': ' / '.join(p[1] for p in pile), 'lignes': [l], 'neuf': neuf}
        blocs.append(courant)
    return [b for b in blocs if b['neuf']]


# ---------------------------------------------------------------------------- ce que la V2 a posé
def dossiers_memoire(q=None):
    """Les dossiers de mémoire de la V2, chemins sous le dossier personnel. `install.sh` dérivait le sien
    du dossier personnel, `/` devenu `-` ; Claude Code range sa mémoire native sous un nom où tout ce qui
    n'est pas alphanumérique devient `-`. Les deux diffèrent dès que le chemin porte un point ou un trait
    bas, et la V2 a pu écrire dans l'un comme dans l'autre : les deux se lisent, celui de l'installation
    d'abord."""
    sortie = []
    for rel in ('.claude/projects/%s/memory' % HOME.replace('/', '-'),
                '.claude/projects/%s/memory' % re.sub(r'[^A-Za-z0-9]', '-', HOME)):
        if rel not in sortie and os.path.isdir(source(q, rel)):
            sortie.append(rel)
    return sortie


def lit_manifest_install():
    """(version d'en-tête ou None, {chemin du squelette: (sha, chemin sous HOME)}) ; (None, {}) sans fichier."""
    texte = lit(os.path.join(V2, 'engine', 'config', 'MANIFEST_INSTALL'))
    if texte is None:
        return None, {}
    m = re.search(r'après mise à jour vers (\S+?)\.?$', texte, re.M)
    entrees = {}
    for l in texte.splitlines():
        if not l.strip() or l.startswith('#'):
            continue
        c = l.split('  ')
        if len(c) < 3 or not re.fullmatch(r'[0-9a-f]{64}', c[0].strip()):
            continue
        dst = c[2].strip().replace('$HOME/', '').replace('${HOME}/', '')
        entrees[c[1].strip()] = (c[0].strip(), dst)
    return (m.group(1) if m else None), entrees


def vers_maison(rel):
    """Le chemin sous le dossier personnel où la V2 posait un fichier du squelette."""
    for src, dst in CARTE:
        if rel == src or rel.startswith(src):
            return dst + rel[len(src):]
    return None


def version_moteur(ref):
    """(étiquette, comment). L'en-tête de MANIFEST_INSTALL après une mise à jour, sinon ses empreintes
    comparées aux étiquettes, sinon le moteur sur le disque (O5), sinon v1.1.0 (O5)."""
    entete, mi = lit_manifest_install()
    if entete in ref['versions']:
        return entete, 'MANIFEST_INSTALL, en-tête de mise à jour'
    def meilleure(empreintes):
        scores = {}
        for t, fs in ref['fichiers'].items():
            scores[t] = sum(1 for rel, h in empreintes.items() if fs.get(rel) == h)
        t = max(sorted(scores, key=ordre), key=lambda x: scores[x])
        return (t, scores[t]) if scores[t] else (None, 0)
    if mi:
        t, n = meilleure({rel: h for rel, (h, _) in mi.items()})
        if t:
            return t, 'MANIFEST_INSTALL, %d empreinte(s) égales à celles de %s' % (n, t)
    moteur = os.path.join(V2, 'engine')
    if os.path.isdir(moteur):
        disque = {}
        for rel in fichiers_sous(moteur):
            if rel.startswith('config/') or rel.endswith('.log'):
                continue
            p = os.path.join(moteur, rel)
            if os.path.isfile(p) and not os.path.islink(p):
                disque['engine/' + rel] = sha(p)
        t, n = meilleure(disque)
        if t:
            return t, 'aucune empreinte d\'installation : le moteur sur le disque, %d fichier(s) égaux à %s' % (n, t)
    return 'v1.1.0', 'aucune empreinte ni moteur reconnu : traitée comme une v1.1.0 (O5)'


def poses_dans_claude(ref, tag):
    """{chemin sous HOME: sha posé} de ce que la V2 a posé dans ~/.claude et ~/resources."""
    _, mi = lit_manifest_install()
    if mi:
        return {dst: h for rel, (h, dst) in mi.items() if dst.startswith(('.claude/', 'resources/'))}
    sortie = {}
    for rel, h in ref['fichiers'].get(tag, {}).items():
        dst = vers_maison(rel)
        if dst and dst.startswith(('.claude/', 'resources/')):
            sortie[dst] = h
    return sortie


def lit_conditions():
    """L'ensemble des conditions VRAIES, une par ligne ; None si le fichier manque : l'entretien de la
    V2 n'a jamais assemblé de règlement."""
    texte = lit(os.path.join(V2, 'engine', 'config', 'CONDITIONS'))
    if texte is None:
        return None
    return {l.strip() for l in texte.splitlines() if l.strip() and not l.startswith('#')}


def version_entretien(ref, lignes, conds):
    """(étiquette ou None, couverture, comment) : l'entretien qui a écrit CONDITIONS. Une mise à jour
    du moteur ne rejoue pas l'entretien, donc la version du moteur ne dit pas quelles questions ont
    été posées. Le gabarit de chaque étiquette, assemblé avec CONDITIONS, se compare au règlement :
    la couverture la plus haute l'emporte, et une égalité va à la plus ancienne — une clé tenue pour
    posée à tort se lirait « refusée », une clé tenue pour jamais posée se repose seulement."""
    if conds is None:
        return None, 0.0, 'CONDITIONS absent : l\'entretien de la V2 n\'a pas assemblé de règlement'
    reel = set(h16(l) for l in lignes if l.strip())
    candidats = [t for t, v in ref['versions'].items() if conds - {'PROXY'} <= set(v['posees'])]
    if not candidats:
        return None, 0.0, 'CONDITIONS porte des conditions qu\'aucune étiquette ne pose : %s' % ', '.join(sorted(conds))
    persona = {t: set(p) for t, p in ref['persona'].items()}
    scores = {}
    for t in candidats:
        g = {h for h, cs in ref['gabarit'].get(t, []) if all(c in conds for c in cs)} - persona.get(t, set())
        scores[t] = (len(g & reel) / len(g)) if g and reel else 0.0
    t = max(sorted(candidats, key=ordre), key=lambda x: (round(scores[x], 6), -ordre(x)[0], -ordre(x)[1]))
    if not reel:
        t = min(candidats, key=ordre)
        return t, 0.0, 'règlement absent : la plus ancienne étiquette compatible avec CONDITIONS'
    return t, scores[t], 'gabarit de %s assemblé avec CONDITIONS, %.0f %% de ses lignes dans ton règlement' % (t, 100 * scores[t])


# ----------------------------------------------------------------------- quarantaine : où et quoi
def quarantaines():
    """[(id, dossier)] des quarantaines, en place puis archivées, de la plus ancienne à la plus récente."""
    sortie = []
    for base in (QUAR, os.path.join(ARCHIVE, 'quarantaine')):
        if os.path.isdir(base):
            for d in sorted(os.listdir(base)):
                if re.fullmatch(r'\d{8}-\d{6}(-\d+)?', d) and os.path.isfile(os.path.join(base, d, 'ETAT')):
                    sortie.append((d, os.path.join(base, d)))
    return sorted(sortie, key=lambda x: (x[0][:15], int(x[0][16:] or 1)))


def quarantaine(qid=None, exiger=True):
    qs = quarantaines()
    if qid:
        qs = [q for q in qs if q[0] == qid]
    if not qs:
        if exiger:
            raise Refus('aucune quarantaine%s : --quarantaine d\'abord (phase M2)' % (' %s' % qid if qid else ''))
        return None, None
    return qs[-1]


def lit_etat(q):
    sortie = []
    for l in (lit(os.path.join(q, 'ETAT')) or '').splitlines():
        c = l.split('\t')
        if len(c) >= 2:
            sortie.append(c)
    return sortie


def restauree(q):
    return os.path.isfile(os.path.join(q, 'RESTAUREE'))


def source(q, rel):
    """Le fichier V2 : sa copie en quarantaine s'il y est, sinon sa place d'origine."""
    if q:
        p = os.path.join(q, 'maison', rel)
        if os.path.lexists(p):
            return p
    return os.path.join(HOME, rel)


def crochets_v2(objet):
    """Les commandes de crochet de la V2 dans un settings.json."""
    sortie = []
    for evt, groupes in (objet.get('hooks') or {}).items():
        for g in groupes if isinstance(groupes, list) else []:
            for h in (g.get('hooks') or []) if isinstance(g, dict) else []:
                c = h.get('command', '') if isinstance(h, dict) else ''
                if any(m in c for m in CROCHETS_V2):
                    sortie.append('%s : %s' % (evt, c[:90]))
    return sortie


def sans_crochets_v2(objet):
    neuf = json.loads(json.dumps(objet))
    hooks = neuf.get('hooks') or {}
    for evt in list(hooks):
        groupes = []
        for g in hooks[evt] if isinstance(hooks[evt], list) else []:
            if not isinstance(g, dict):
                groupes.append(g)
                continue
            garde = [h for h in g.get('hooks', []) if not (isinstance(h, dict) and any(m in h.get('command', '') for m in CROCHETS_V2))]
            if garde:
                groupes.append(dict(g, hooks=garde))
        if groupes:
            hooks[evt] = groupes
        else:
            del hooks[evt]
    if 'hooks' in neuf:
        if hooks:
            neuf['hooks'] = hooks
        else:
            del neuf['hooks']
    return neuf


def plan_quarantaine(racine):
    """[(geste, chemin sous HOME)] — deplace, copie ou modifie — ce que la V2 a posé dans ~/.claude."""
    rel_c = os.path.relpath(racine, HOME)
    gestes = []
    claude_md = os.path.join(racine, 'CLAUDE.md')
    texte = lit(claude_md)
    if texte is not None and BLOC_V3 in texte:
        raise Refus('%s porte le bloc d\'imports de la V3 : la quarantaine se fait AVANT la plomberie. '
                    'Un retour arrière se fait par --restaurer.' % tilde(claude_md))
    for nom in ('CLAUDE.md', 'DESIGN.md', 'RULES_CATALOG.md', 'fiches'):
        if os.path.lexists(os.path.join(racine, nom)):
            gestes.append(('deplace', os.path.join(rel_c, nom)))
    for parent in ('skills', 'secrets-shared'):
        d = os.path.join(racine, parent)
        if os.path.isdir(d) and not os.path.islink(d):
            for e in sorted(os.listdir(d)):
                if e not in IGNORES:
                    gestes.append(('deplace', os.path.join(rel_c, parent, e)))
    if os.path.lexists(os.path.join(racine, 'output-styles', 'eli5.md')):
        gestes.append(('deplace', os.path.join(rel_c, 'output-styles', 'eli5.md')))
    # La mémoire V2 part en quarantaine : la V3 lit la sienne sous ~/.claude/memory, l'import y verse
    # celle-ci, et restée sous projects/ elle serait un dossier hors sauvegarde que install-poste.sh
    # signalerait à chaque passage (mesuré à la première épreuve, le 2026-10-01).
    for mem in dossiers_memoire():
        gestes.append(('deplace', mem))
    reglages = os.path.join(racine, 'settings.json')
    if os.path.isfile(reglages):
        try:
            objet = json.load(open(reglages, encoding='utf-8'))
        except (OSError, ValueError) as e:
            raise Refus('%s illisible (%s) : rien n\'est écrit' % (tilde(reglages), e))
        if isinstance(objet, dict) and crochets_v2(objet):
            gestes.append(('modifie', os.path.join(rel_c, 'settings.json')))
    for s in SHELLS:
        if LIGNE_SHELL_V2 in (lit(os.path.join(HOME, s)) or ''):
            gestes.append(('modifie', s))
    return gestes


def apres_modification(rel):
    """Le contenu d'un fichier modifié par la quarantaine, octets UTF-8."""
    p = os.path.join(HOME, rel)
    if rel.endswith('settings.json'):
        objet = json.load(open(p, encoding='utf-8'))
        return (json.dumps(sans_crochets_v2(objet), ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    texte = open(p, encoding='utf-8').read()
    lignes = texte.splitlines(keepends=True)
    return ''.join(l for l in lignes if LIGNE_SHELL_V2 not in l).encode('utf-8')


def copie_arbre(src, dst):
    """Copie un fichier, un lien ou un dossier, octet pour octet ; rend les fichiers copiés (relatifs)."""
    if os.path.islink(src):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        os.symlink(os.readlink(src), dst)
        return []
    if os.path.isfile(src):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        return ['']
    copies = []
    for rel in dossiers_sous(src):
        os.makedirs(os.path.join(dst, rel), exist_ok=True)
    for rel in fichiers_sous(src):
        s, d = os.path.join(src, rel), os.path.join(dst, rel)
        os.makedirs(os.path.dirname(d), exist_ok=True)
        if os.path.islink(s):
            os.symlink(os.readlink(s), d)
        else:
            shutil.copy2(s, d)
            copies.append(rel)
    return copies


def egaux(a, b):
    """Deux arbres, fichiers ou liens égaux à l'octet, dossiers compris."""
    if os.path.islink(a) or os.path.islink(b):
        return os.path.islink(a) and os.path.islink(b) and os.readlink(a) == os.readlink(b)
    if os.path.isfile(a) or os.path.isfile(b):
        return os.path.isfile(a) and os.path.isfile(b) and sha(a) == sha(b)
    if not (os.path.isdir(a) and os.path.isdir(b)):
        return False
    if dossiers_sous(a) != dossiers_sous(b) or fichiers_sous(a) != fichiers_sous(b):
        return False
    return all(egaux(os.path.join(a, r), os.path.join(b, r)) for r in fichiers_sous(a))


def traces_dans_claude(racine):
    """Ce que la V2 a laissé dans ~/.claude hors de toute quarantaine : la V3 ne s'y pose pas tant
    qu'il en reste (M-V2-DETECTEE). La V3 ne livre ni RULES_CATALOG.md, ni fiches/, ni DESIGN.md :
    leur présence seule est une trace ; une compétence ou un style ne l'est que si son empreinte
    est celle que la V2 a posée."""
    traces = []
    for nom in ('RULES_CATALOG.md', 'fiches'):
        if os.path.lexists(os.path.join(racine, nom)):
            traces.append('%s/%s' % (tilde(racine), nom))
    try:
        ref = lit_reference()
        tag, _ = version_moteur(ref)
        poses = poses_dans_claude(ref, tag)
    except Appel:
        poses = {}
    rel_c = os.path.relpath(racine, HOME)
    for rel, h in sorted(poses.items()):
        if not rel.startswith('.claude/'):
            continue
        p = os.path.join(racine, rel[len('.claude/'):]) if rel_c == '.claude' else os.path.join(HOME, rel)
        if os.path.isfile(p) and not os.path.islink(p) and sha(p) == h and livre_v3(racine, rel[len('.claude/'):]) != h:
            traces.append(tilde(p))
    texte = lit(os.path.join(racine, 'CLAUDE.md'))
    if texte is not None and BLOC_V3 not in texte and re.search(r'^### 3\.1 Domaines de travail|^## 2\. Voix et conduite', texte, re.M):
        traces.append('%s/CLAUDE.md, le règlement assemblé d\'une V2' % tilde(racine))
    try:
        objet = json.load(open(os.path.join(racine, 'settings.json'), encoding='utf-8'))
        traces += ['crochet de la V2 dans settings.json — %s' % c for c in crochets_v2(objet if isinstance(objet, dict) else {})]
    except (OSError, ValueError):
        pass
    for s in SHELLS:
        if LIGNE_SHELL_V2 in (lit(os.path.join(HOME, s)) or ''):
            traces.append('~/%s source le démarrage de la V2' % s)
    return list(dict.fromkeys(traces))


def livre_v3(racine, rel):
    """L'empreinte du fichier que la V3 livre à ce chemin, ou None. Un fichier de la V2 identique à
    celui de la V3 n'est pas une trace : le style eli5.md, par exemple, est le même dans les deux. Lu
    sur l'amorce quand le script en vient, sinon sur le dépôt ou l'état livré du système."""
    if os.path.realpath(RACINE_MODELE) != os.path.realpath(racine):
        p = os.path.join(RACINE_MODELE, rel)
        return sha(p) if os.path.isfile(p) else None
    if os.path.isdir(os.path.join(racine, '.git')):
        r = subprocess.run(['git', '-C', racine, 'show', 'HEAD:' + rel], capture_output=True)
        return sha_octets(r.stdout) if r.returncode == 0 else None
    for l in (lit(os.path.join(racine, '.claudeos', 'livre', 'MANIFESTE')) or '').splitlines():
        if l.endswith('  ' + rel):
            return l.split('  ', 1)[0]
    return None


# ------------------------------------------------------------------------------------ inventaire
def inventaire(racine, ref, q=None):
    """Le texte de l'inventaire et ses chiffres : ce qui est posé, sa classe, et ce qu'il deviendra."""
    lignes, chiffres = [], {}
    tag, comment = version_moteur(ref)
    conds = lit_conditions()
    v6 = lit(source(q, os.path.join(os.path.relpath(racine, HOME), 'CLAUDE.md')))
    norm = normalise(v6) if v6 is not None else []
    t_ent, couv, c_ent = version_entretien(ref, norm, conds)
    connues = ref['versions'][t_ent]['posees'] if t_ent else []
    chiffres.update(moteur=tag, entretien=t_ent, connues=connues)
    lignes.append('version : moteur %s (%s)' % (tag, comment))
    lignes.append('version : entretien %s (%s)' % (t_ent or 'aucun', c_ent))
    def v(vid, quoi, etat):
        lignes.append('%-5s %-40s %s' % (vid, quoi, etat))
    v('V-1', '~/.claudeos/', 'présent — le dépôt local de la V2 : laissé intact, rangé au retrait (M8)'
      if os.path.isdir(V2) else 'absent')
    if conds is None:
        v('V-2', '~/.claudeos/engine/config/CONDITIONS', 'absent — aucune réponse à importer')
    else:
        v('V-2', '~/.claudeos/engine/config/CONDITIONS', 'présent — %d condition(s) vraie(s) ; %d clé(s) V3 connues de '
          'l\'entretien %s, importées' % (len(conds - {'PROXY'}), len(connues), t_ent))
    entete, mi = lit_manifest_install()
    v('V-3', '~/.claudeos/engine/config/MANIFEST_INSTALL', 'présent — %d empreinte(s), pour le classement' % len(mi)
      if mi else 'absent — classement sur la table des étiquettes (O5)')
    domaines = domaines_v2()
    sm = os.path.join(V2, 'engine', 'config', 'SYNC_MAP')
    v('V-4', '~/.claudeos/engine/config/SYNC_MAP', 'présent — %d domaine(s) sauvegardé(s)' % len(domaines['sauves'])
      if os.path.isfile(sm) else 'absent')
    conf = [f for f in ('REMOTE', 'SYNC_MACHINES', 'TEMPLATE_ORIGIN', 'RETIRES_AMONT')
            if os.path.isfile(os.path.join(V2, 'engine', 'config', f))]
    v('V-5', 'config du moteur V2', ('présent — %s : non importés' % ', '.join(conf)) if conf else 'absent')
    rel_c = os.path.relpath(racine, HOME)
    if v6 is None:
        v('V-6', '~/.claude/CLAUDE.md', 'absent — ni persona, ni domaines, ni règles à importer')
    else:
        rubs = rubriques_v2(norm)
        persona_h = set()
        for t in ref['persona'].values():
            persona_h |= set(t)
        reglees = [lib for lib, l, s in rubs if reglage_de(lib, l, s, persona_h)[0]]
        union = set()
        for t in ref['gabarit'].values():
            union |= {h for h, _ in t}
        cand = blocs_candidats(norm, union)
        chiffres.update(rubriques=len(reglees), candidates=len(cand))
        v('V-6', '~/.claude/CLAUDE.md', 'présent — persona : %d rubrique(s) réglée(s) sur %d ; %d domaine(s) à la '
          'table ; %d règle(s) candidate(s)' % (len(reglees), len(rubs), len(table_domaines(norm)), len(cand)))
    poses = poses_dans_claude(ref, tag)
    for vid, noms in (('V-7', ('DESIGN.md', 'RULES_CATALOG.md')), ('V-9', ('output-styles/eli5.md',))):
        etats = []
        for nom in noms:
            p = source(q, os.path.join(rel_c, nom))
            if os.path.lexists(p):
                h0 = poses.get('.claude/' + nom)
                etats.append('%s %s' % (nom, 'intact' if h0 and os.path.isfile(p) and sha(p) == h0 else 'modifié ou hors manifeste'))
        v(vid, ', '.join(noms), ('présent — %s : quarantaine, non importé, la V3 livre les siens' % ' ; '.join(etats))
          if etats else 'absent')
    classes = classe_competences(racine, ref, tag, q)
    chiffres['competences'] = classes
    resume = ', '.join('%d %s' % (len(classes[k]), k) for k in ('intactes', 'modifiées', 'créées') if classes[k])
    v('V-8', '~/.claude/skills/%s' % (', fiches/' if any(n.startswith('fiches/') for k in classes.values() for n in k) else ''),
      ('présent — %s : quarantaine ; les créées reviennent, les modifiées se tranchent une à une' % resume) if resume else 'absent')
    mems = dossiers_memoire(q)
    nm = sum(len(fichiers_sous(source(q, m))) for m in mems)
    v('V-10', ', '.join('~/%s/' % m for m in mems) or 'mémoire', ('présent — %d fichier(s) : en quarantaine, versés vers '
      'memory/ à l\'import, la chronique gelée' % nm) if nm else 'absent')
    ps = source(q, os.path.join(rel_c, 'secrets-shared'))
    ns = len(fichiers_sous(ps)) if os.path.isdir(ps) else 0
    v('V-11', '~/.claude/secrets-shared/', ('présent — %d fichier(s) : revenus à l\'import, hors du dépôt par défaut (O2)' % ns)
      if ns else 'vide ou absent')
    reglages = source(q, os.path.join(rel_c, 'settings.json'))
    try:
        objet = json.load(open(reglages, encoding='utf-8')) if os.path.isfile(reglages) else {}
    except (OSError, ValueError):
        objet = {}
    cv2 = crochets_v2(objet) if isinstance(objet, dict) else []
    v('V-12', '~/.claude/settings.json', ('%d crochet(s) de la V2 : retirés par la quarantaine, rtk gardé' % len(cv2))
      if cv2 else 'aucun crochet de la V2')
    rtk = shutil.which('rtk')
    v('V-13', 'rtk, ~/.claude/RTK.md', 'rtk %s : PROXY se redétecte à la plomberie' % ('présent' if rtk else 'absent'))
    v('V-14', '~/workstations/', ('présent — %d domaine(s) : %s ; copiés un à un, jamais déplacés (M5)' % (
        len(domaines['tous']), ', '.join(domaines['tous']))) if domaines['tous'] else 'absent ou vide')
    res = ressources_v2(poses)
    v('V-15', '~/docs/, ~/resources/', ('présent — %d entrée(s) : %s ; à trancher une à une (O3)' % (len(res), ', '.join(res)))
      if res else 'absent ou vide')
    sh = [s for s in SHELLS if LIGNE_SHELL_V2 in (lit(os.path.join(HOME, s)) or '')]
    v('V-16', 'amorce du shell', ('ligne V2 dans %s : retirée par la quarantaine, copie gardée' % ', '.join('~/' + s for s in sh))
      if sh else 'aucune ligne V2')
    sp = os.path.isdir(os.path.join(HOME, '.claude', 'plugins')) and any(
        'superpowers' in d.lower() for d, _, _ in os.walk(os.path.join(HOME, '.claude', 'plugins')))
    v('V-17', 'greffon superpowers', 'présent — reste installé, la V3 ne le réinstalle pas' if sp else 'absent')
    url = lance(['git', '-C', V2, 'remote', 'get-url', 'origin'])[1].strip() if os.path.isdir(os.path.join(V2, '.git')) else ''
    v('V-18', 'dépôt de sauvegarde distant', ('%s : laissé intact, archivé au retrait par la personne (M8)' % url) if url else 'aucun origin lu')
    contrat = cles_contrat(racine)
    a_poser = [k for k in contrat if k not in connues]
    chiffres['questions'] = a_poser
    lignes.append('questions : l\'entretien posera %d clé(s) que l\'entretien %s n\'a jamais posées : %s'
                  % (len(a_poser), t_ent or 'de la V2', ', '.join(a_poser)))
    return lignes, chiffres


def cles_contrat(racine):
    """Les clés d'entretien du contrat V3, dans l'ordre (`engine/config/REPONSES_CLES`)."""
    for base in (os.path.join(racine, 'engine'), ICI):
        texte = lit(os.path.join(base, 'config', 'REPONSES_CLES'))
        if texte:
            return [l.split()[0] for l in texte.splitlines()
                    if l.strip() and not l.startswith('#') and len(l.split()) > 1 and l.split()[1] == 'entretien']
    raise Appel('contrat des réponses introuvable (engine/config/REPONSES_CLES)')


def domaines_v2():
    """{'sauves': [domaines du manifeste de sauvegarde], 'tous': [ceux-là plus les dossiers de ~/workstations]}."""
    base = WS if os.path.isdir(WS) else os.path.join(ARCHIVE, 'workstations')
    sauves = []
    for l in (lit(os.path.join(V2 if os.path.isdir(V2) else os.path.join(ARCHIVE, 'claudeos'), 'engine', 'config',
                               'SYNC_MAP')) or '').splitlines():
        c = l.split()
        if len(c) >= 2 and not l.startswith('#'):
            m = re.match(r'^workstations/([^/]+)/?$', c[0])
            if m and m.group(1) not in sauves:
                sauves.append(m.group(1))
    disque = sorted(d for d in os.listdir(base) if os.path.isdir(os.path.join(base, d)) and d not in IGNORES) \
        if os.path.isdir(base) else []
    return {'sauves': sauves, 'tous': sorted(set(sauves) | set(disque)), 'base': base}


def ressources_v2(poses):
    """Les entrées de ~/docs et ~/resources, moins les fichiers du squelette restés intacts."""
    sortie = []
    for parent in ('docs', 'resources'):
        d = os.path.join(HOME, parent)
        if not os.path.isdir(d):
            continue
        for e in sorted(os.listdir(d)):
            if e in IGNORES:
                continue
            rel = '%s/%s' % (parent, e)
            p = os.path.join(d, e)
            if rel in poses and os.path.isfile(p) and sha(p) == poses[rel]:
                continue
            sortie.append(rel)
    return sortie


def classe_competences(racine, ref, tag, q):
    """{'intactes', 'modifiées', 'créées'} : [noms], par dossier de skills/ et par fiche de fiches/."""
    poses = poses_dans_claude(ref, tag)
    rel_c = os.path.relpath(racine, HOME)
    classes = {'intactes': [], 'modifiées': [], 'créées': []}
    d = source(q, os.path.join(rel_c, 'skills'))
    noms = []
    if q:
        noms = sorted({c[1][len(rel_c + '/skills/'):].split('/')[0] for c in lit_etat(q)
                       if c[0] == 'deplace' and c[1].startswith(rel_c + '/skills/')})
    elif os.path.isdir(d):
        noms = sorted(e for e in os.listdir(d) if e not in IGNORES)
    for nom in noms:
        cle = '.claude/skills/%s/' % nom
        attendus = {k[len(cle):]: h for k, h in poses.items() if k.startswith(cle)}
        p = os.path.join(d, nom)
        if not attendus:
            classes['créées'].append(nom)
            continue
        presents = {r: sha(os.path.join(p, r)) for r in fichiers_sous(p) if os.path.isfile(os.path.join(p, r))} \
            if os.path.isdir(p) else {}
        classes['intactes' if presents == attendus else 'modifiées'].append(nom)
    f = source(q, os.path.join(rel_c, 'fiches'))
    if os.path.isdir(f):
        for nom in fichiers_sous(f):
            h0 = poses.get('.claude/fiches/' + nom)
            if not h0:
                classes['créées'].append('fiches/' + nom)
            else:
                classes['intactes' if sha(os.path.join(f, nom)) == h0 else 'modifiées'].append('fiches/' + nom)
    return classes


def cmd_inventaire(racine, a):
    ref = lit_reference()
    qd = quarantaine(exiger=False)[1]
    if not os.path.isdir(V2) and not qd and not os.path.isdir(ARCHIVE):
        dit('aucune V1 ni V2 sur ce poste : ~/.claudeos absent, aucune quarantaine.')
        return 0
    lignes, _ = inventaire(racine, ref, qd)
    for l in lignes:
        print(l)
    if qd:
        print('quarantaine : %s%s' % (tilde(qd), ' — RESTAURÉE' if restauree(qd) else ''))
    return 0


# ------------------------------------------------------------------------------------ quarantaine
def cmd_quarantaine(racine, a):
    ref = lit_reference()
    gestes = plan_quarantaine(racine)
    a_faire = [g for g in gestes if g[0] in ('deplace', 'modifie')]
    if not a_faire:
        raise Refus('rien de la V2 dans %s : déjà en quarantaine, ou jamais posé' % tilde(racine))
    for g, rel in gestes:
        dit('%s %s' % ({'deplace': 'déplacé  ', 'copie': 'copié    ', 'modifie': 'modifié  '}[g], '~/' + rel))
    if a.essai:
        dit('essai : rien n\'est écrit — %d geste(s) prévu(s)' % len(gestes))
        return 0
    base = datetime.now().strftime('%Y%m%d-%H%M%S')
    qid, n = base, 1
    while os.path.exists(os.path.join(QUAR, qid)) or any(x[0] == qid for x in quarantaines()):
        n += 1
        qid = '%s-%d' % (base, n)
    q = os.path.join(QUAR, qid)
    texte_inv = '\n'.join(inventaire(racine, ref)[0]) + '\n'
    os.makedirs(os.path.join(q, 'maison'))
    try:
        etat, manifeste = [], []
        for g, rel in gestes:
            src, dst = os.path.join(HOME, rel), os.path.join(q, 'maison', rel)
            if g == 'modifie':
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copy2(src, dst)
                manifeste.append('%s  maison/%s' % (sha(dst), rel))
                etat.append('modifie\t%s\t%s' % (rel, sha_octets(apres_modification(rel))))
                continue
            copies = copie_arbre(src, dst)
            if os.path.isdir(dst) and not os.path.islink(dst):
                etat += ['dossier\t%s' % os.path.normpath(os.path.join(rel, d)) for d in dossiers_sous(dst)]
                etat += ['lien\t%s\t%s' % (os.path.join(rel, r), os.readlink(os.path.join(dst, r)))
                         for r in fichiers_sous(dst) if os.path.islink(os.path.join(dst, r))]
            elif os.path.islink(dst):
                etat.append('lien\t%s\t%s' % (rel, os.readlink(dst)))
            for c in copies:
                chemin = os.path.normpath(os.path.join(rel, c)) if c else rel
                manifeste.append('%s  maison/%s' % (sha(os.path.join(q, 'maison', chemin)), chemin))
            etat.append('%s\t%s' % (g, rel))
        # La vérification AVANT tout retrait : chaque copie égale à sa source.
        for g, rel in gestes:
            if g != 'modifie' and not egaux(os.path.join(HOME, rel), os.path.join(q, 'maison', rel)):
                raise Refus('copie en quarantaine différente de sa source : ~/%s' % rel)
        ecrit(os.path.join(q, 'MANIFESTE'), '\n'.join(manifeste) + '\n')
        ecrit(os.path.join(q, 'ETAT'), '\n'.join(etat) + '\n')
        ecrit(os.path.join(q, 'INVENTAIRE'), texte_inv)
    except Exception:
        shutil.rmtree(q, ignore_errors=True)   # notre dossier, créé à l'instant : rien d'autre n'y est
        raise
    # Puis seulement : les retraits, et les deux fichiers modifiés en place.
    for g, rel in gestes:
        p = os.path.join(HOME, rel)
        if g == 'deplace':
            if os.path.islink(p) or os.path.isfile(p):
                os.unlink(p)
            else:
                shutil.rmtree(p)
        elif g == 'modifie':
            neuf = apres_modification(rel)
            with open(p + '.neuf', 'wb') as f:
                f.write(neuf)
            os.chmod(p + '.neuf', os.stat(p).st_mode & 0o7777)
            os.replace(p + '.neuf', p)
    dit('quarantaine %s : %d geste(s), %d fichier(s) copiés et vérifiés — %s' % (qid, len(gestes), len(manifeste), tilde(q)))
    dit('retour arrière : python3 %s --restaurer --id %s' % (tilde(os.path.abspath(__file__)), qid))
    return 0


def cmd_restaurer(racine, a):
    qid, q = quarantaine(a.id)
    etat = lit_etat(q)
    conflits = []
    for c in etat:
        g, rel = c[0], c[1]
        p, s = os.path.join(HOME, rel), os.path.join(q, 'maison', rel)
        if g == 'deplace' and os.path.lexists(p) and not egaux(p, s):
            conflits.append('~/%s existe et diffère de la copie en quarantaine' % rel)
        if g == 'modifie' and os.path.isfile(p) and sha(p) != c[2] and sha(p) != sha(s):
            conflits.append('~/%s a changé depuis la quarantaine' % rel)
    if conflits:
        raise Refus('restauration refusée, rien n\'est écrit :\n    - ' + '\n    - '.join(conflits)
                    + '\n    Une V3 posée par-dessus se retire d\'abord ; la quarantaine, elle, reste intacte.')
    # Les éléments d'abord, les dossiers vides ensuite : un dossier recréé en premier ferait passer
    # son contenu pour déjà rendu, et il resterait vide (mesuré à la première épreuve, le 2026-10-01).
    n = 0
    for c in etat:
        g, rel = c[0], c[1]
        p, s = os.path.join(HOME, rel), os.path.join(q, 'maison', rel)
        if g == 'deplace' and not os.path.lexists(p):
            copie_arbre(s, p)
            n += 1
        elif g == 'modifie':
            shutil.copy2(s, p)
            n += 1
    for c in etat:
        if c[0] == 'dossier':
            os.makedirs(os.path.join(HOME, c[1]), exist_ok=True)
    ecrit(os.path.join(q, 'RESTAUREE'), '%s\n' % datetime.now().isoformat(timespec='seconds'))
    dit('quarantaine %s restaurée : %d élément(s) remis en place ; la quarantaine reste, intacte' % (qid, n))
    return 0


# ------------------------------------------------------------------------------------- importer
def entete_gel(jour):
    """La première ligne d'un fichier gelé : le crochet (code 24) le tient alors en lecture seule, et les
    noms morts qu'il cite ne crient pas (codes 27 et 28)."""
    return ('> **GELÉ le %s.** Lecture seule. Rien ne s\'y ajoute, rien ne s\'en retire. Importé de la V2 par '
            'engine/import-v2.py : l\'état vivant est dans journal/*.jsonl. Cherché au grep, jamais chargé.\n\n' % jour)


def lit_reponses(chemin):
    valeurs, ordre_cles = {}, []
    for l in (lit(chemin) or '').split('\n'):
        if l.strip() and not l.startswith('#') and '=' in l:
            k, v = l.split('=', 1)
            if k not in valeurs:
                valeurs[k] = v
                ordre_cles.append(k)
    return valeurs, ordre_cles


def ecrit_reponses(chemin, valeurs, racine):
    contrat = cles_contrat(racine) + ['PROXY']
    lignes = ['%s=%s' % (k, valeurs[k]) for k in contrat if k in valeurs]
    lignes += ['%s=%s' % (k, v) for k, v in valeurs.items() if k not in contrat]
    ecrit(chemin, '\n'.join(lignes) + '\n')


def destination(d, valeurs, racine):
    """Le dossier V3 d'un domaine V2 : sous travail/ en dépôt unique ou sans git ; ~/<PRÉFIXE><D> par domaine."""
    g = valeurs.get('GIT')
    if g == 'par-domaine':
        prefixes = [p.strip() for p in valeurs.get('PREFIXES', '').split(',') if p.strip()]
        nom = d if any(d.startswith(p) for p in prefixes) or not prefixes else prefixes[0] + d
        return os.path.join(HOME, nom)
    return os.path.join(racine, 'travail', d)


def persona_v3(texte_v3, apports):
    """Le CLAUDE.md V3, chaque rubrique encore marquée remplie par son import. Une rubrique déjà
    réglée en V3 ne se touche pas : la différence est rendue, jamais écrasée."""
    notes = []
    def sous(m):
        nom, corps = m.group(1).strip(), m.group(2)
        texte = apports.get(nom)
        if not texte:
            return m.group(0)
        utiles = [l for l in re.sub(r'<!--.*?-->', '', corps, flags=re.S).splitlines() if l.strip()]
        if utiles != [MARQUE]:
            notes.append('rubrique « %s » déjà réglée en V3 : l\'import ne la touche pas ; texte V2 : %s'
                         % (nom, texte.replace('\n', ' ')[:200]))
            return m.group(0)
        return m.group(0).replace(MARQUE, texte, 1)
    m = re.search(r'^## Persona[ \t]*\n(.*?)(?=^## |\Z)', texte_v3, re.M | re.S)
    if not m:
        return texte_v3, (['section « Persona » absente : %d rubrique(s) non importées' % len(apports)] if apports else [])
    section = re.sub(r'^### (.+?)[ \t]*\n(.*?)(?=^### |\Z)', sous, m.group(1), flags=re.M | re.S)
    return texte_v3[:m.start(1)] + section + texte_v3[m.end(1):], notes


def domaines_v3(texte_v3, rangs):
    """« Mes domaines » : la ligne marquée remplacée par les domaines importés ; un dossier déjà
    présent ne se double pas. Sans la section, rien n'est écrit et c'est dit."""
    m = re.search(r'^## Mes domaines[ \t]*\n(.*?)(?=^## |\Z)', texte_v3, re.M | re.S)
    if not m:
        return texte_v3, (['section « Mes domaines » absente : %d domaine(s) non routés' % len(rangs)] if rangs else [])
    section = m.group(1)
    neufs = [r for r in rangs if r.split('|')[2].strip() not in section]
    if not neufs:
        return texte_v3, []
    if '| %s | | |' % MARQUE_TABLE in section:
        section2 = section.replace('| %s | | |\n' % MARQUE_TABLE, ''.join(r + '\n' for r in neufs), 1)
    else:
        lignes = section.split('\n')
        sep = max((i for i, l in enumerate(lignes) if re.match(r'^\|\s*:?-{3,}', l)), default=None)
        if sep is None:
            return texte_v3, ['« Mes domaines » sans table lisible : %d domaine(s) non routés' % len(neufs)]
        k = sep + 1
        while k < len(lignes) and lignes[k].startswith('|'):
            k += 1
        lignes[k:k] = neufs
        section2 = '\n'.join(lignes)
    return texte_v3[:m.start(1)] + section2 + texte_v3[m.end(1):], []


def noms_morts(racine, texte):
    """Les lignes qu'un crochet V3 refuserait au commit : un nom mort sans date (code 27), un chemin de poste (28)."""
    sortie = []
    nm = motif_config(racine, 'CLAUDEOS_NOMS_MORTS_RE')
    dt = motif_config(racine, 'CLAUDEOS_PROVENANCE_DATEE_RE')
    cp = motif_config(racine, 'CLAUDEOS_CHEMIN_POSTE_RE')
    for l in texte.splitlines():
        if nm and re.search(nm, l) and not (dt and re.search(dt, l)):
            sortie.append('nom mort sans date : ' + l.strip()[:160])
        elif cp and re.search(cp, l):
            sortie.append('chemin de poste : ' + l.strip()[:160])
    return sortie


def original_dans_historique(rel_home, h):
    """Le contenu d'origine d'un fichier posé par la V2, retrouvé dans l'historique du dépôt local
    (`~/.claudeos/system/` est la copie de `~/.claude/`) par son empreinte d'installation."""
    depot = V2 if os.path.isdir(V2) else os.path.join(ARCHIVE, 'claudeos')
    if not os.path.isdir(os.path.join(depot, '.git')) or not rel_home.startswith('.claude/'):
        return None
    chemin = 'system/' + rel_home[len('.claude/'):]
    rc, out, _ = lance(['git', '-C', depot, 'log', '--all', '--format=%H', '--', chemin])
    for c in out.split()[:200] if rc == 0 else []:
        r = subprocess.run(['git', '-C', depot, 'show', '%s:%s' % (c, chemin)], capture_output=True)
        if r.returncode == 0 and sha_octets(r.stdout) == h:
            return r.stdout
    return None


def rapport_competences(racine, ref, tag, q, classes):
    """COMPETENCES_MODIFIEES.md : pour chaque compétence ou fiche modifiée, ses fichiers et la différence."""
    poses = poses_dans_claude(ref, tag)
    rel_c = os.path.relpath(racine, HOME)
    sortie = ['# Compétences de la V2 que tu as modifiées — à trancher une à une', '',
              '> Écrit par engine/import-v2.py le %s. La V3 livre sa propre version de chacune. Pour '
              'chacune : en tirer une règle à toi, une compétence à toi, ou rien —' % date.today().isoformat(),
              '> `import-v2.py --competence NOM regle|competence|rien`.', '']
    for nom in classes['modifiées']:
        base = '.claude/%s' % nom if nom.startswith('fiches/') else '.claude/skills/%s' % nom
        sortie.append('## %s' % nom)
        attendus = {k: h for k, h in poses.items() if k == base or k.startswith(base + '/')}
        p_base = source(q, os.path.join(rel_c, base[len('.claude/'):]))
        presents = {}
        if os.path.isdir(p_base):
            presents = {base + '/' + r: os.path.join(p_base, r) for r in fichiers_sous(p_base)}
        elif os.path.isfile(p_base):
            presents = {base: p_base}
        for k in sorted(set(attendus) | set(presents)):
            if k not in presents:
                sortie.append('- `%s` : retiré par toi' % k)
                continue
            if k not in attendus:
                sortie.append('- `%s` : ajouté par toi' % k)
                continue
            if sha(presents[k]) == attendus[k]:
                continue
            orig = original_dans_historique(k, attendus[k])
            if orig is None:
                sortie.append('- `%s` : modifié — l\'original ne se retrouve pas dans l\'historique de ~/.claudeos ; '
                              'il est celui de la %s du template' % (k, tag))
                continue
            neuf = open(presents[k], encoding='utf-8', errors='replace').read().splitlines()
            diff = list(difflib.unified_diff(orig.decode('utf-8', 'replace').splitlines(), neuf,
                                             'original %s' % tag, 'le tien', lineterm=''))
            sortie += ['- `%s` : modifié' % k, '', '```diff'] + diff[:200] + ['```', '']
        sortie.append('')
    return '\n'.join(sortie) + '\n'


def evenement(racine, niveau, *args):
    """Un événement par l'`etat.py` du système V3 ; Refus si le contrat le refuse."""
    script = os.path.join(racine, 'engine', 'etat.py')
    rc, out, err = lance([sys.executable, script, 'add', '--niveau', niveau] + list(args))
    if rc != 0:
        raise Refus('etat.py add a refusé (rc=%d) : %s' % (rc, (err or out).strip()[:300]))


def cmd_importer(racine, a):
    ref = lit_reference()
    qid, q = quarantaine()
    if restauree(q):
        raise Refus('la quarantaine %s a été restaurée : la V2 est revenue, il n\'y a rien à importer' % qid)
    rel_c = os.path.relpath(racine, HOME)
    f_rep = os.path.join(racine, 'reglages', 'REPONSES')
    valeurs, _ = lit_reponses(f_rep)
    if valeurs.get('GIT') not in ('par-domaine', 'unique', 'aucun'):
        raise Refus('reglages/REPONSES ne porte pas GIT : la plomberie d\'abord (phase M3)')
    texte_v3 = lit(os.path.join(racine, 'CLAUDE.md'))
    if texte_v3 is None or BLOC_V3 not in texte_v3:
        if not a.essai:
            raise Refus('%s n\'est pas le CLAUDE.md de la V3 : la plomberie le copie depuis gabarits/ (phase M3)'
                        % tilde(os.path.join(racine, 'CLAUDE.md')))
        texte_v3 = lit(os.path.join(RACINE_MODELE, 'gabarits', 'CLAUDE.md'))
    tag, _ = version_moteur(ref)
    v6 = lit(source(q, os.path.join(rel_c, 'CLAUDE.md')))
    norm = normalise(v6) if v6 is not None else []
    conds = lit_conditions()
    t_ent, couv, c_ent = version_entretien(ref, norm, conds)
    connues = ref['versions'][t_ent]['posees'] if t_ent else []
    notes, ecrits = [], []
    # 1. Les réponses : les clés que l'entretien V2 a posées, présentes → oui, absentes → non.
    importees = {}
    for k in connues:
        importees[k] = 'oui' if k in (conds or set()) else 'non'
    if valeurs.get('GIT') == 'aucun' and importees.get('MULTIPOSTE') == 'oui':
        importees['MULTIPOSTE'] = 'non'
        notes.append('MULTIPOSTE valait oui en V2 : forcé à non, rien ne synchronise deux postes sans git')
    fusion = dict(valeurs)
    for k, v in importees.items():
        if k in valeurs and valeurs[k] != v:
            notes.append('%s vaut déjà %s en V3, la V2 disait %s : gardé tel quel' % (k, valeurs[k], v))
        else:
            fusion[k] = v
    # 2. Le persona : chaque rubrique V2 réglée, vers sa rubrique V3.
    persona_h = set()
    for t in ref['persona'].values():
        persona_h |= set(t)
    reglages_v2 = {}
    for lib, l, s in rubriques_v2(norm):
        texte, reconnu = reglage_de(lib, l, s, persona_h)
        if texte:
            reglages_v2[lib] = texte
            if not reconnu:
                notes.append('rubrique « %s » : énoncé du gabarit non reconnu, le texte entier est importé' % lib)
    connus = {apostrophes(x) for _, xs in FUSION for x in xs}
    for lib in reglages_v2:
        if lib not in connus:
            notes.append('rubrique V2 « %s » inconnue : proposée en règle candidate' % lib)
    apports = {}
    for v3, v2s in FUSION:
        textes = [(x, reglages_v2[apostrophes(x)]) for x in v2s if reglages_v2.get(apostrophes(x))]
        if not textes:
            continue
        if len(textes) == 1:
            apports[v3] = textes[0][1]
        else:
            apports[v3] = ('<!-- importé de la V2 : « %s » puis « %s », deux réglages à fondre en un -->\n'
                           % (textes[0][0], textes[1][0])) + '\n\n'.join(t for _, t in textes)
    neuf, n_p = persona_v3(texte_v3, apports)
    notes += n_p
    # 3. Les domaines : chaque ligne de la table, vers la destination V3 de son domaine.
    rangs = []
    for cellules in table_domaines(norm):
        m = re.search(r'workstations/([^/`\s|]+)', cellules[1] if len(cellules) > 1 else '')
        if not m:
            notes.append('ligne de la table des domaines sans dossier ~/workstations/ : %s' % ' | '.join(cellules))
            continue
        dest = destination(m.group(1), fusion, racine)
        rem = cellules[2] if len(cellules) > 2 else ''
        if re.fullmatch(r'`?CLAUDE\.md`?\s*\+\s*`?MEMORY\.md`?\s+du dossier', rem):
            rem = ''
        rangs.append('| %s | `%s/` | %s |' % (cellules[0], tilde(dest), rem))
    neuf, n_d = domaines_v3(neuf, rangs)
    notes += n_d
    for l in noms_morts(racine, '\n'.join(apports.values()) + '\n' + '\n'.join(rangs)):
        notes.append('CLAUDE.md, ligne importée que le crochet refuserait au commit — %s' % l)
    # 4. Les règles candidates.
    union = set()
    for t in ref['gabarit'].values():
        union |= {h for h, _ in t}
    cand = blocs_candidats(norm, union)
    inconnues = [(lib, l, s) for lib, l, s in rubriques_v2(norm) if lib not in connus]
    texte_c = ['# Règles candidates de la V2 — à trancher une à une', '',
               '> Écrit par engine/import-v2.py le %s. Chacune est un bloc de ton ancien règlement qu\'aucun '
               'gabarit de la V1 ni de la V2 ne porte : tu l\'as ajouté ou modifié. Garder la recopie à la fin '
               'de « ## Mes règles » ; laisser la met de côté —' % date.today().isoformat(),
               '> `import-v2.py --regle N garder|laisser`.', '']
    n = 0
    for b in cand:
        n += 1
        texte_c += ['## %d — sous « %s »' % (n, b['section'] or 'tête du règlement'), ''] + b['lignes'] + ['']
    for lib, l, s in inconnues:
        n += 1
        texte_c += ['## %d — rubrique de persona inconnue de la V3' % n, '', l] + s + ['']
    # 5. Les compétences et les ressources.
    classes = classe_competences(racine, ref, tag, q)
    texte_m = rapport_competences(racine, ref, tag, q, classes)
    res = ressources_v2(poses_dans_claude(ref, tag))
    doms = domaines_v2()
    # 6. La mémoire, les secrets, les créneaux : ce qui sera copié.
    copies_mem = []
    for m in dossiers_memoire(q):
        base = source(q, m)
        for r in fichiers_sous(base):
            if os.path.basename(r) not in MEMOIRE_GENEREE:
                copies_mem.append((base, r))
    sec_src = os.path.join(q, 'maison', rel_c, 'secrets-shared')
    secrets = fichiers_sous(sec_src) if os.path.isdir(sec_src) else []
    choix_secrets = a.secrets or 'hors-depot'
    cren = lit(os.path.join(V2, 'engine', 'config', 'CRENEAUX')) or ''
    cren = '\n'.join(l for l in cren.splitlines() if l.strip() and not l.startswith('#'))

    rapport = ['import V2 → V3 : moteur %s, entretien %s (%s)' % (tag, t_ent or 'aucun', c_ent),
               'réponses : %d clé(s) importées — %s' % (len(importees), ', '.join('%s=%s' % kv for kv in sorted(importees.items()))),
               'persona : %d rubrique(s) V3 remplies depuis %d rubrique(s) V2 réglées' % (len(apports), len(reglages_v2)),
               'domaines : %d ligne(s) routées vers « Mes domaines »' % len(rangs),
               'règles candidates : %d, à trancher une à une' % n,
               'compétences : %d modifiée(s) à trancher, %d créée(s) par toi qui reviennent' % (
                   len(classes['modifiées']), len(classes['créées'])),
               'mémoire : %d fichier(s) copiés vers memory/, dont la chronique gelée' % len(copies_mem),
               'secrets de faible valeur : %d fichier(s), %s' % (len(secrets), 'hors du dépôt (O2)'
                                                                 if choix_secrets == 'hors-depot' else 'suivis au dépôt'),
               'ressources : %d entrée(s) de ~/docs et ~/resources à trancher (O3)' % len(res),
               'dossiers de travail : %d domaine(s) à copier un à un, --domaine (M5)' % len(doms['tous'])]
    rapport += ['remarque : ' + x for x in notes]
    if a.essai:
        d = os.path.abspath(a.essai)
        os.makedirs(d, exist_ok=True)
        ecrit_reponses(os.path.join(d, 'REPONSES'), fusion, racine)
        ecrit(os.path.join(d, 'CLAUDE.md'), neuf)
        ecrit(os.path.join(d, 'REGLES_CANDIDATES.md'), '\n'.join(texte_c) + '\n')
        ecrit(os.path.join(d, 'COMPETENCES_MODIFIEES.md'), texte_m)
        ecrit(os.path.join(d, 'RAPPORT'), '\n'.join(rapport) + '\n')
        for l in rapport:
            dit(l)
        dit('essai : écrit sous %s, et rien d\'autre — ni ~/.claude, ni la quarantaine' % tilde(d))
        return 0

    # --- pour de vrai
    imp = os.path.join(q, 'import')
    os.makedirs(imp, exist_ok=True)
    ecrit_reponses(f_rep, fusion, racine)
    ecrits.append('reglages/REPONSES')
    if neuf != texte_v3:
        ecrit(os.path.join(racine, 'CLAUDE.md'), neuf)
        ecrits.append('CLAUDE.md')
    # La mémoire : vivante copiée si absente, chronique gelée, collision rangée sous memory/v2/.
    mem_dst = os.path.join(racine, 'memory')
    jour = date.today().isoformat()
    for mem_src, r in copies_mem:
        s, nom = os.path.join(mem_src, r), os.path.basename(r)
        contenu = open(s, 'rb').read()
        if nom in MEMOIRE_GELEE and os.path.dirname(r) == '':
            corps = contenu.decode('utf-8', 'replace')
            if not corps.startswith(GEL):
                contenu = (entete_gel(jour) + corps).encode('utf-8')
        d = os.path.join(mem_dst, r)
        if os.path.exists(d):
            if open(d, 'rb').read() == contenu:
                continue
            if nom == 'MEMORY.md' and os.path.dirname(r) == '':
                actuel = open(d, encoding='utf-8').read()
                ajouts = [l for l in contenu.decode('utf-8', 'replace').splitlines()
                          if l.startswith('- ') and l not in actuel.splitlines()]
                if ajouts:
                    ecrit(d, actuel.rstrip('\n') + '\n' + '\n'.join(ajouts) + '\n')
                    ecrits.append('memory/MEMORY.md (%d ligne(s) d\'index de la V2 ajoutées)' % len(ajouts))
                continue
            if nom == 'ROUTING_MISSES.md' and os.path.dirname(r) == '':
                actuel = open(d, encoding='utf-8').read()
                ajouts = [l for l in contenu.decode('utf-8', 'replace').splitlines()
                          if re.match(r'^-?\s*\d{4}-\d{2}-\d{2}', l) and l not in actuel.splitlines()]
                if ajouts:
                    ecrit(d, actuel.rstrip('\n') + '\n' + '\n'.join(ajouts) + '\n')
                    ecrits.append('memory/ROUTING_MISSES.md (%d raté(s) de la V2 ajoutés)' % len(ajouts))
                continue
            d = os.path.join(mem_dst, 'v2', r)
            notes.append('memory/%s existe déjà et diffère : la version V2 va sous memory/v2/' % r)
        os.makedirs(os.path.dirname(d), exist_ok=True)
        with open(d, 'wb') as f:
            f.write(contenu)
        ecrits.append(os.path.relpath(d, racine))
    # Les compétences créées par la personne reviennent ; un nom pris par la V3 se tranche.
    conflits_nom, revenus = [], []
    for nom in classes['créées']:
        if nom.startswith('fiches/'):
            continue
        s, d = os.path.join(q, 'maison', rel_c, 'skills', nom), os.path.join(racine, 'skills', nom)
        if os.path.lexists(d):
            if not egaux(s, d):
                conflits_nom.append(nom)
            continue
        copie_arbre(s, d)
        ecrits.append('skills/%s/' % nom)
        revenus.append(os.path.join(rel_c, 'skills', nom))
    # Les secrets : revenus, et hors du dépôt par défaut (O2).
    for r in secrets:
        d = os.path.join(racine, 'secrets-shared', r)
        if not os.path.lexists(d):
            copie_arbre(os.path.join(sec_src, r), d)
        revenus.append(os.path.join(rel_c, 'secrets-shared', r))
    if secrets:
        ecrits.append('secrets-shared/ (%d fichier(s))' % len(secrets))
        if choix_secrets == 'hors-depot' and fusion.get('GIT') in ('par-domaine', 'unique'):
            excl = os.path.join(racine, '.git', 'info', 'exclude')
            actuel = lit(excl) or ''
            if '/secrets-shared/' not in actuel.splitlines():
                ecrit(excl, actuel.rstrip('\n') + ('\n' if actuel.strip() else '')
                      + '# Secrets de faible valeur importés de la V2 : hors du dépôt, comme en V2 (O2).\n/secrets-shared/\n')
                ecrits.append('.git/info/exclude (/secrets-shared/)')
    # Les créneaux.
    f_cren = os.path.join(racine, 'reglages', 'CRENEAUX')
    if cren and not os.path.exists(f_cren):
        ecrit(f_cren, '# Créneaux importés de la V2 le %s — <domaine>  <jours>\n%s\n' % (jour, cren))
        ecrits.append('reglages/CRENEAUX')
    # Les listes à trancher, et le journal de l'import.
    mod = list(classes['modifiées']) + ['%s (nom pris par la V3)' % x for x in conflits_nom]
    ecrit(os.path.join(imp, 'REGLES_CANDIDATES.md'), '\n'.join(texte_c) + '\n')
    ecrit(os.path.join(imp, 'COMPETENCES_MODIFIEES.md'), texte_m + ''.join(
        '\n## %s — compétence créée par toi, dont la V3 porte le nom\n' % x for x in conflits_nom))
    ecrit(os.path.join(imp, 'A_TRANCHER'), ''.join('regle\t%d\n' % i for i in range(1, n + 1))
          + ''.join('competence\t%s\n' % x for x in list(classes['modifiées']) + conflits_nom)
          + ''.join('ressource\t%s\n' % x for x in res)
          + ''.join('domaine\t%s\n' % x for x in doms['tous']))
    ecrit(os.path.join(imp, 'JOURNAL'), json.dumps({
        'date': datetime.now().isoformat(timespec='seconds'), 'moteur': tag, 'entretien': t_ent,
        'cles': sorted(importees), 'rubriques': sorted(apports), 'candidates': n, 'secrets': choix_secrets,
        'ecrits': ecrits, 'revenus': revenus, 'remarques': notes}, ensure_ascii=False, indent=1) + '\n')
    if not os.path.exists(os.path.join(imp, 'DECISIONS')):
        ecrit(os.path.join(imp, 'DECISIONS'), '')
    # Au journal du système : ce que l'import a fait, et les propositions de la V2 à trier.
    evenement(racine, racine, '--type', 'observation', '--ref', 'o-import-v2', '--source',
              'python3 engine/import-v2.py --verifier',
              '--texte', 'MIGRATION DEPUIS UNE V2 : moteur %s, entretien %s. %d cle(s) importee(s), %d rubrique(s) '
              'du persona remplie(s), %d domaine(s) route(s), %d regle(s) candidate(s) et %d competence(s) modifiee(s) '
              'a trancher, %d fichier(s) de memoire copie(s). Quarantaine %s.' % (
                  tag, t_ent or 'aucun', len(importees), len(apports), len(rangs), n, len(mod), len(copies_mem), qid))
    lps = [os.path.join(source(q, m), 'LEARNING_PROPOSALS.md') for m in dossiers_memoire(q)]
    if any(os.path.isfile(lp) and len([l for l in open(lp, encoding='utf-8', errors='replace') if l.strip()]) > 3 for lp in lps):
        evenement(racine, racine, '--type', 'du', '--op', 'ouvre', '--ref', 'u-propositions-v2', '--chantier',
                  'regles-candidates', '--texte', 'LES REGLES CANDIDATES DE LA V2 ATTENDENT LEUR TRI : '
                  'memory/LEARNING_PROPOSALS.md, gele a l import ; chacune se promeut dans Mes regles du '
                  'CLAUDE.md, ou se laisse.')
    for l in rapport:
        dit(l)
    for x in conflits_nom:
        dit('compétence « %s » créée par toi : la V3 porte ce nom, elle n\'est pas revenue — à trancher' % x)
    dit('écrit : %s' % ', '.join(ecrits))
    dit('à trancher : %d règle(s), %d compétence(s), %d ressource(s), %d domaine(s) — %s'
        % (n, len(mod), len(res), len(doms['tous']), tilde(os.path.join(imp, 'A_TRANCHER'))))
    return 0


# ------------------------------------------------------------------------------------ décisions
def a_trancher(q):
    imp = os.path.join(q, 'import')
    items = [tuple(l.split('\t', 1)) for l in (lit(os.path.join(imp, 'A_TRANCHER')) or '').splitlines() if '\t' in l]
    faits = {}
    for l in (lit(os.path.join(imp, 'DECISIONS')) or '').splitlines():
        c = l.split('\t')
        if len(c) >= 4:
            faits[(c[1], c[2])] = c[3:]
    return items, faits


def tranchable(q, objet, nom):
    """Refus si l'objet n'est pas à trancher, ou l'est déjà : la décision se prend une fois."""
    items, faits = a_trancher(q)
    if (objet, nom) not in items:
        raise Refus('%s « %s » n\'est pas à trancher : %s' % (objet, nom, ', '.join(n for o, n in items if o == objet) or 'aucun'))
    if (objet, nom) in faits:
        raise Refus('%s « %s » est déjà tranché : %s' % (objet, nom, ' '.join(faits[(objet, nom)])))


def decide(q, objet, nom, *issue):
    tranchable(q, objet, nom)
    with open(os.path.join(q, 'import', 'DECISIONS'), 'a', encoding='utf-8') as f:
        f.write('\t'.join((datetime.now().isoformat(timespec='seconds'), objet, nom) + issue) + '\n')


def textes_a_reecrire(racine, base):
    """Les lignes des fichiers texte copiés sous `base` que le crochet V3 refuserait au commit : un nom
    mort sans date, un chemin de poste. Un fichier gelé ne compte pas, un réceptacle `_IGNORE/` non plus,
    puisque rien de ce qu'il contient n'est jamais suivi."""
    sortie = []
    for d, sous, fs in os.walk(base):
        sous[:] = sorted(s for s in sous if s not in ('_IGNORE', '.git') and s not in IGNORES)
        for f in sorted(fs):
            p = os.path.join(d, f)
            if f in IGNORES or os.path.islink(p):
                continue
            try:
                t = open(p, encoding='utf-8').read()
            except (OSError, UnicodeDecodeError):
                continue
            if t.startswith(GEL):
                continue
            sortie += ['%s : %s' % (tilde(p), l) for l in noms_morts(racine, t)]
    return sortie


def candidate(q, n):
    texte = lit(os.path.join(q, 'import', 'REGLES_CANDIDATES.md')) or ''
    m = re.search(r'^## %d — [^\n]*\n\n(.*?)(?=^## \d+ — |\Z)' % n, texte, re.M | re.S)
    if not m:
        raise Refus('règle candidate %d introuvable dans REGLES_CANDIDATES.md' % n)
    return m.group(1).strip('\n')


def cmd_regle(racine, a):
    _, q = quarantaine()
    n, issue = a.regle
    if issue not in ('garder', 'laisser'):
        raise Appel('--regle N garder|laisser')
    tranchable(q, 'regle', n)
    if issue == 'garder':
        texte = a.texte if a.texte else candidate(q, int(n))
        morts = noms_morts(racine, texte)
        if morts:
            raise Refus('la règle %s cite ce que le crochet refusera au commit — %s. Réécris-la, puis '
                        '--regle %s garder --texte "…"' % (n, '; '.join(morts), n))
        f = os.path.join(racine, 'CLAUDE.md')
        t = lit(f) or ''
        m = re.search(r'^## Mes règles[ \t]*\n(.*?)(?=^## |\Z)', t, re.M | re.S)
        if not m:
            raise Refus('%s n\'a pas de section « ## Mes règles »' % tilde(f))
        corps = m.group(1).rstrip('\n')
        neuf = t[:m.start(1)] + corps + '\n\n' + texte.strip('\n') + '\n' + ('\n' if m.end(1) < len(t) else '') + t[m.end(1):]
        ecrit(f, neuf)
        decide(q, 'regle', n, 'gardee' + (' (réécrite)' if a.texte else ''))
        dit('règle %s gardée : ajoutée à la fin de « ## Mes règles »' % n)
    else:
        decide(q, 'regle', n, 'laissee')
        dit('règle %s laissée : elle reste lisible dans la quarantaine' % n)
    return 0


def cmd_competence(racine, a):
    _, q = quarantaine()
    nom, issue = a.competence
    if issue not in ('regle', 'competence', 'rien'):
        raise Appel('--competence NOM regle|competence|rien')
    decide(q, 'competence', nom, issue)
    dit('compétence %s : %s' % (nom, {'regle': 'une règle à toi, écrite dans « Mes règles »',
                                       'competence': 'une compétence à toi, sous un nom neuf',
                                       'rien': 'rien, la version de la V3 suffit'}[issue]))
    return 0


def cmd_ressource(racine, a):
    _, q = quarantaine()
    nom = a.ressource.strip('/')
    if a.hors:
        decide(q, 'ressource', nom, 'hors', 'laissée en place, hors du système')
        dit('ressource %s : laissée en place, hors de ClaudeOS' % nom)
        return 0
    s = os.path.join(HOME, nom)
    d = os.path.abspath(os.path.expanduser(a.vers)) if a.vers else os.path.join(racine, 'resources', os.path.basename(nom))
    if not os.path.lexists(s):
        raise Refus('~/%s introuvable' % nom)
    if os.path.lexists(d):
        raise Refus('%s existe déjà : rien n\'est écrasé — une autre destination, --vers' % tilde(d))
    tranchable(q, 'ressource', nom)
    copie_arbre(s, d)
    if not egaux(s, d):
        raise Refus('copie de ~/%s différente de sa source : %s à examiner' % (nom, tilde(d)))
    decide(q, 'ressource', nom, 'copiee', tilde(d))
    dit('ressource %s copiée vers %s ; l\'original reste en place' % (nom, tilde(d)))
    return 0


def niveaux_de(base):
    """Les dossiers d'un domaine qui portent un fichier de niveau, hors des réceptacles."""
    sortie = []
    for d, sous, fs in os.walk(base):
        sous[:] = sorted(s for s in sous if s != '_IGNORE' and s not in IGNORES and not s.startswith('.'))
        if {'CLAUDE.md', 'MEMORY.md', 'HANDOFF.md'} & set(fs):
            sortie.append(os.path.relpath(d, base))
    return sortie


def recepteurs(base):
    return {os.path.relpath(d, base): len(fichiers_sous(d)) for d, sous, _ in os.walk(base)
            if os.path.basename(d) == '_IGNORE'}


def resume_reprise(texte):
    """Le premier état d'un niveau, tiré de son fichier de reprise V2 : sans accent grave, sur une ligne."""
    lignes = [l.strip() for l in texte.splitlines() if l.strip() and not l.startswith(GEL)]
    t = ' · '.join(lignes).replace('`', '')
    t = 'REPRISE IMPORTEE DE LA V2 : ' + t if t else 'REPRISE IMPORTEE DE LA V2 : aucune reprise en cours.'
    return t if len(t) <= 1100 else t[:1090].rstrip() + ' … (suite gelée)'


def cmd_domaine(racine, a):
    _, q = quarantaine()
    d = a.domaine.strip('/')
    tranchable(q, 'domaine', d)
    if a.laisser:
        decide(q, 'domaine', d, 'laisse', 'non copié, reste dans ~/workstations jusqu\'au retrait')
        dit('domaine %s laissé : non copié' % d)
        return 0
    valeurs, _ = lit_reponses(os.path.join(racine, 'reglages', 'REPONSES'))
    g = valeurs.get('GIT')
    src = os.path.join(domaines_v2()['base'], d)
    if not os.path.isdir(src):
        raise Refus('%s introuvable' % tilde(src))
    if g == 'par-domaine' and not a.vers:
        raise Refus('GIT=par-domaine : --vers ~/<NOM>, le dépôt créé par nouveau-domaine, étapes 3 et 4')
    dst = os.path.abspath(os.path.expanduser(a.vers)) if a.vers else os.path.join(racine, 'travail', d)
    if g in ('unique', 'aucun') and os.path.dirname(dst) != os.path.join(racine, 'travail'):
        raise Refus('GIT=%s : un dossier de travail vit sous %s/, où claudeos_ws_roots le trouve'
                    % (g, tilde(os.path.join(racine, 'travail'))))
    if os.path.isdir(dst) and set(os.listdir(dst)) - {'.git', '.gitignore', '.DS_Store'}:
        raise Refus('%s n\'est pas vide : rien n\'est écrasé' % tilde(dst))
    if os.path.exists(dst) and not os.path.isdir(dst):
        raise Refus('%s existe et n\'est pas un dossier' % tilde(dst))
    # La liste noire AVANT la copie : un _IGNORE/ copié dans un dépôt qui ne l'ignore pas partirait au distant.
    if g in ('par-domaine', 'unique'):
        depot = dst if g == 'par-domaine' else racine
        if not os.path.isdir(os.path.join(depot, '.git')):
            raise Refus('%s n\'est pas un dépôt git : nouveau-domaine, étapes 3 et 4, d\'abord' % tilde(depot))
        temoin = os.path.relpath(os.path.join(dst, '_IGNORE', 'temoin'), depot)
        if lance(['git', '-C', depot, 'check-ignore', '--no-index', '-q', temoin])[0] != 0:
            raise Refus('%s n\'ignore pas _IGNORE/ : la liste noire d\'abord (nouveau-domaine, étape 4)' % tilde(depot))
    if g == 'par-domaine':
        prefixes = [p.strip() for p in valeurs.get('PREFIXES', '').split(',') if p.strip()]
        if not any(os.path.basename(dst).startswith(p) for p in prefixes):
            raise Refus('%s ne commence par aucun préfixe de PREFIXES (%s)' % (os.path.basename(dst), ', '.join(prefixes)))
    os.makedirs(dst, exist_ok=True)
    for e in sorted(os.listdir(src)):
        if e not in IGNORES:
            copie_arbre(os.path.join(src, e), os.path.join(dst, e))
    for e in sorted(os.listdir(src)):
        if e not in IGNORES and not egaux(os.path.join(src, e), os.path.join(dst, e)):
            raise Refus('copie de %s différente de sa source : %s' % (e, tilde(dst)))
    jour = date.today().isoformat()
    niveaux = niveaux_de(dst)
    for n in niveaux:
        lv = os.path.normpath(os.path.join(dst, n))
        for f in ('MEMORY.md', 'HANDOFF.md'):
            p = os.path.join(lv, f)
            if os.path.isfile(p):
                t = open(p, encoding='utf-8', errors='replace').read()
                if not t.startswith(GEL):
                    ecrit(p, entete_gel(jour) + t)
        if not os.path.isfile(os.path.join(lv, 'CLAUDE.md')):
            ecrit(os.path.join(lv, 'CLAUDE.md'), '# CLAUDE.md — %s\n' % os.path.basename(lv))
        evenement(racine, lv, '--type', 'observation', '--ref', 'o-import-v2', '--source', 'CLAUDE.md', '--texte',
                  'NIVEAU IMPORTE DE LA V2 le %s depuis %s : MEMORY.md et le fichier de reprise y sont geles, cherches '
                  'au grep, jamais charges.' % (jour, tilde(os.path.normpath(os.path.join(src, n)))))
        rep = os.path.join(lv, 'HANDOFF.md')
        evenement(racine, lv, '--type', 'etat', '--op', 'avance', '--chantier', 'reprise-v2', '--texte',
                  resume_reprise(open(rep, encoding='utf-8', errors='replace').read()) if os.path.isfile(rep)
                  else 'REPRISE IMPORTEE DE LA V2 : aucun fichier de reprise a ce niveau.')
        rc, out, err = lance([sys.executable, os.path.join(racine, 'engine', 'etat.py'), 'projette', '--niveau', lv])
        if rc != 0:
            raise Refus('etat.py projette a refusé (rc=%d) : %s' % (rc, (err or out).strip()[:300]))
    r_src, r_dst = recepteurs(src), recepteurs(dst)
    if r_src != r_dst:
        raise Refus('réceptacles _IGNORE/ : %s à la source, %s à la destination' % (r_src, r_dst))
    a_reecrire = textes_a_reecrire(racine, dst)
    nom = os.path.basename(dst)
    # Les créneaux et la table suivent un renommage.
    f_cren = os.path.join(racine, 'reglages', 'CRENEAUX')
    if nom != d and os.path.isfile(f_cren):
        t = lit(f_cren)
        t2 = re.sub(r'^%s(\s)' % re.escape(d), nom + r'\1', t, flags=re.M)
        if t2 != t:
            ecrit(f_cren, t2)
    f_c = os.path.join(racine, 'CLAUDE.md')
    t = lit(f_c) or ''
    attendu = tilde(destination(d, valeurs, racine))
    if attendu != tilde(dst) and '`%s/`' % attendu in t:
        ecrit(f_c, t.replace('`%s/`' % attendu, '`%s/`' % tilde(dst)))
    decide(q, 'domaine', d, 'copie', tilde(dst))
    if a_reecrire:
        ecrit(os.path.join(q, 'import', 'A_REECRIRE-%s' % d), '\n'.join(a_reecrire) + '\n')
    dit('domaine %s copié vers %s : %d niveau(x), %d réceptacle(s) _IGNORE/ à l\'identique ; la source reste en place'
        % (d, tilde(dst), len(niveaux), len(r_dst)))
    for l in a_reecrire:
        dit('à réécrire avant la première clôture — %s' % l)
    return 0


# --------------------------------------------------------------------------------------- retrait
def seance_depuis(racine, depuis):
    for f in sorted(os.listdir(os.path.join(racine, 'journal'))) if os.path.isdir(os.path.join(racine, 'journal')) else []:
        for l in open(os.path.join(racine, 'journal', f), encoding='utf-8'):
            try:
                ev = json.loads(l)
            except ValueError:
                continue
            if ev.get('type') == 'seance' and ev.get('ts', '') >= depuis:
                return True
    return False


def cmd_retrait(racine, a):
    qid, q = quarantaine()
    if not q.startswith(QUAR + os.sep):
        raise Refus('la V2 est déjà rangée sous %s' % tilde(ARCHIVE))
    r = verifie(racine, 'domaines', qid)
    if r:
        raise Refus('la migration n\'est pas close (--verifier --etape domaines) :\n    - ' + '\n    - '.join(r))
    j = json.loads(lit(os.path.join(q, 'import', 'JOURNAL')) or '{}')
    if not seance_depuis(racine, j.get('date', '')[:10]):
        raise Refus('aucune séance complète sur la V3 depuis l\'import : la double sécurité (M7) d\'abord')
    if os.path.exists(ARCHIVE):
        raise Refus('%s existe déjà : rien n\'est écrasé' % tilde(ARCHIVE))
    os.makedirs(ARCHIVE)
    faits = []
    try:
        for src, nom in ((V2, 'claudeos'), (WS, 'workstations'), (QUAR, 'quarantaine')):
            if os.path.isdir(src):
                os.rename(src, os.path.join(ARCHIVE, nom))
                faits.append((src, os.path.join(ARCHIVE, nom)))
    except OSError as e:
        for src, dst in reversed(faits):
            os.rename(dst, src)
        os.rmdir(ARCHIVE)
        raise Refus('rangement impossible (%s) : tout est remis en place' % e)
    ecrit(os.path.join(ARCHIVE, 'LISEZMOI'), 'La V2 de ClaudeOS, rangée le %s par engine/import-v2.py --retrait.\n'
          'Rien n\'a été effacé : claudeos/ est l\'ancien ~/.claudeos, workstations/ l\'ancien ~/workstations, '
          'quarantaine/ ce que la V2 avait posé dans ~/.claude.\nSupprimer ce dossier est ta décision : '
          'un _IGNORE/ y est peut-être le seul exemplaire d\'un document.\n' % date.today().isoformat())
    for src, dst in faits:
        dit('rangé : %s → %s' % (tilde(src), tilde(dst)))
    dit('le dépôt de sauvegarde de la V2 reste sur GitHub : l\'archiver est une écriture externe, à confirmer')
    return 0


# -------------------------------------------------------------------------------------- vérifier
def verifie(racine, etape, qid=None):
    """Les défauts de la migration jusqu'à l'étape donnée ; [] si elle est conforme."""
    d = []
    try:
        qid, q = quarantaine(qid)
    except Refus as e:
        return [str(e)]
    if restauree(q):
        return ['la quarantaine %s a été restaurée : la V2 est revenue, la migration est abandonnée' % qid]
    for l in (lit(os.path.join(q, 'MANIFESTE')) or '').splitlines():
        if '  ' not in l:
            continue
        h, rel = l.split('  ', 1)
        p = os.path.join(q, rel)
        if not os.path.isfile(p):
            d.append('quarantaine : %s manque' % rel)
        elif sha(p) != h:
            d.append('quarantaine : %s a changé depuis la mise en quarantaine' % rel)
    # Une copie revenue par l'import, ou identique à ce que la V3 livre, n'est pas une V2 restée en place.
    j0 = json.loads(lit(os.path.join(q, 'import', 'JOURNAL')) or '{}')
    revenus = set(j0.get('revenus', []))
    rel_c = os.path.relpath(racine, HOME)
    for c in lit_etat(q):
        if c[0] == 'deplace' and c[1] not in revenus:
            p = os.path.join(HOME, c[1])
            if os.path.lexists(p) and egaux(p, os.path.join(q, 'maison', c[1])):
                v3 = livre_v3(racine, c[1][len(rel_c) + 1:]) if c[1].startswith(rel_c + '/') and os.path.isfile(p) else None
                if v3 is None or v3 != sha(p):
                    d.append('la V2 est encore en place : ~/%s' % c[1])
    reglages = os.path.join(racine, 'settings.json')
    if os.path.isfile(reglages):
        try:
            objet = json.load(open(reglages, encoding='utf-8'))
            d += ['crochet de la V2 dans settings.json — %s' % x for x in crochets_v2(objet if isinstance(objet, dict) else {})]
        except (OSError, ValueError):
            d.append('settings.json illisible')
    for s in SHELLS:
        if LIGNE_SHELL_V2 in (lit(os.path.join(HOME, s)) or ''):
            d.append('~/%s source encore le démarrage de la V2' % s)
    if etape == 'quarantaine':
        return d
    imp = os.path.join(q, 'import')
    j = lit(os.path.join(imp, 'JOURNAL'))
    if j is None:
        return d + ['import non joué : --importer (phase M4)']
    j = json.loads(j)
    valeurs, _ = lit_reponses(os.path.join(racine, 'reglages', 'REPONSES'))
    d += ['reglages/REPONSES : la clé importée %s manque' % k for k in j.get('cles', []) if k not in valeurs]
    if j.get('secrets') == 'hors-depot' and valeurs.get('GIT') in ('par-domaine', 'unique') \
            and os.path.isdir(os.path.join(racine, 'secrets-shared')) and fichiers_sous(os.path.join(racine, 'secrets-shared')):
        if '/secrets-shared/' not in (lit(os.path.join(racine, '.git', 'info', 'exclude')) or '').splitlines():
            d.append('secrets-shared/ devait rester hors du dépôt : /secrets-shared/ manque à .git/info/exclude')
    texte = lit(os.path.join(racine, 'CLAUDE.md')) or ''
    d += ['CLAUDE.md, à réécrire avant la première clôture — %s' % l for l in noms_morts(racine, texte)]
    if os.path.isdir(os.path.join(racine, 'memory')):
        d += ['mémoire copiée, à réécrire avant la première clôture — %s' % l
              for l in textes_a_reecrire(racine, os.path.join(racine, 'memory'))]
    items, faits = a_trancher(q)
    etapes = {'import': ('regle', 'competence', 'ressource'), 'domaines': ('regle', 'competence', 'ressource', 'domaine'),
              'fin': ('regle', 'competence', 'ressource', 'domaine')}[etape]
    for o, n in items:
        if o in etapes and (o, n) not in faits:
            d.append('à trancher : %s %s' % (o, n))
    if etape in ('domaines', 'fin'):
        for (o, n), issue in faits.items():
            if o != 'domaine' or issue[0] != 'copie':
                continue
            dst = os.path.expanduser(issue[1])
            if not os.path.isfile(os.path.join(dst, 'CLAUDE.md')):
                d.append('domaine %s : %s sans CLAUDE.md, aucun routage ne le trouverait' % (n, issue[1]))
                continue
            for lv in niveaux_de(dst):
                p = os.path.join(dst, lv)
                for f in ('MEMORY.md', 'HANDOFF.md'):
                    if os.path.isfile(os.path.join(p, f)) and not (lit(os.path.join(p, f)) or '').startswith(GEL):
                        d.append('domaine %s : %s/%s n\'est pas gelé' % (n, tilde(p), f))
                if not os.path.isfile(os.path.join(p, 'ETAT.md')):
                    d.append('domaine %s : %s sans ETAT.md' % (n, tilde(p)))
            d += ['domaine %s, à réécrire avant la première clôture — %s' % (n, l) for l in textes_a_reecrire(racine, dst)]
            src = os.path.join(domaines_v2()['base'], n)
            if os.path.isdir(src) and recepteurs(src) != recepteurs(dst):
                d.append('domaine %s : les réceptacles _IGNORE/ diffèrent de la source' % n)
    if etape == 'fin':
        if os.path.isdir(V2):
            d.append('~/.claudeos est encore en place : --retrait (phase M8)')
        if not q.startswith(os.path.join(ARCHIVE, '')):
            d.append('la quarantaine n\'est pas rangée sous ~/.claudeos-v2-archive : --retrait (phase M8)')
    return d


def cmd_verifier(racine, a):
    defauts = verifie(racine, a.etape, a.id)
    for x in defauts:
        dit('⛔ ' + x, err=True)
    if defauts:
        dit('migration, étape %s : %d défaut(s) — la phase N\'EST PAS close.' % (a.etape, len(defauts)), err=True)
        return 1
    dit('migration, étape %s : CONFORME — la phase est close.' % a.etape)
    return 0


# ------------------------------------------------------------------------------------------ main
def main(argv):
    ap = argparse.ArgumentParser(prog='import-v2.py', description='Migration d\'une V1 ou d\'une V2 vers la V3.')
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument('--inventaire', action='store_true')
    g.add_argument('--quarantaine', action='store_true')
    g.add_argument('--restaurer', action='store_true')
    g.add_argument('--importer', action='store_true')
    g.add_argument('--regle', nargs=2, metavar=('N', 'ISSUE'))
    g.add_argument('--competence', nargs=2, metavar=('NOM', 'ISSUE'))
    g.add_argument('--ressource', metavar='NOM')
    g.add_argument('--domaine', metavar='D')
    g.add_argument('--retrait', action='store_true')
    g.add_argument('--verifier', action='store_true')
    ap.add_argument('--essai', nargs='?', const=True, metavar='DOSSIER')
    ap.add_argument('--secrets', choices=('hors-depot', 'depot'))
    ap.add_argument('--texte')
    ap.add_argument('--vers', metavar='DOSSIER')
    ap.add_argument('--hors', action='store_true')
    ap.add_argument('--laisser', action='store_true')
    ap.add_argument('--etape', choices=('quarantaine', 'import', 'domaines', 'fin'), default='fin')
    ap.add_argument('--id', metavar='ID')
    ap.add_argument('--racine', metavar='DOSSIER')
    a = ap.parse_args(argv)
    racine = os.path.realpath(os.path.expanduser(a.racine or '~/.claude'))
    if a.essai is not None and not (a.quarantaine or a.importer):
        ap.error('--essai ne vaut que pour --quarantaine et --importer')
    if a.importer and a.essai is True:
        ap.error('--importer --essai DOSSIER : le dossier où écrire')
    if a.quarantaine and a.essai not in (None, True):
        ap.error('--quarantaine --essai ne prend pas de dossier')
    if a.secrets and not a.importer:
        ap.error('--secrets ne vaut que pour --importer')
    if a.texte and not a.regle:
        ap.error('--texte ne vaut que pour --regle')
    if (a.vers or a.hors) and not (a.ressource or a.domaine):
        ap.error('--vers et --hors valent pour --ressource et --domaine')
    if a.laisser and not a.domaine:
        ap.error('--laisser ne vaut que pour --domaine')
    commandes = (('inventaire', cmd_inventaire), ('quarantaine', cmd_quarantaine), ('restaurer', cmd_restaurer),
                 ('importer', cmd_importer), ('regle', cmd_regle), ('competence', cmd_competence),
                 ('ressource', cmd_ressource), ('domaine', cmd_domaine), ('retrait', cmd_retrait),
                 ('verifier', cmd_verifier))
    try:
        for nom, f in commandes:
            if getattr(a, nom):
                return f(racine, a)
    except Refus as e:
        dit('⛔ %s' % e, err=True)
        return 1
    except Appel as e:
        dit('⛔ NON MESURÉ — %s' % e, err=True)
        return 2
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
