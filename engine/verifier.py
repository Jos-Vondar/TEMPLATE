#!/usr/bin/env python3
"""verifier.py — le code de sortie qui clôt chaque phase de l'agent d'installation.

Écrit le 2026-10-01, plan complet de templating § 1.9, A6 (`d-agent-installateur`). Code PROPRE AU
TEMPLATE. Le prompt fait, le script prouve : l'agent livré joue chaque phase, et AUCUNE ne se déclare
finie sans le code de sortie de sa sous-commande. Il n'écrit rien, nulle part.

Usage :
  verifier.py mode                     le mode de l'agent d'après les traces du poste : installer,
                                       migrer, v3 ou doute ; les traces suivent, une par ligne
  verifier.py inachevee [--message]    les trois tests de l'installation inachevée (§ 1.5) ; rc=1
                                       et les motifs si elle l'est ; --message imprime M-INACHEVEE,
                                       que `boot-check.sh` relaie en tête du démarrage
  verifier.py prerequis [--regime github|aucun]
  verifier.py plomberie
  verifier.py entretien
  verifier.py arrivee                  les cinq faits d'arrivée (§ 3.1)
  verifier.py migration [--etape E]    délègue à `engine/import-v2.py --verifier --etape E` : quarantaine,
                                       import, domaines ou fin (défaut)
  verifier.py mise-a-jour [--version V]
  --racine DOSSIER                     le système examiné, au lieu de ~/.claude

Codes : 0 conforme ; 1 un défaut au moins, chacun nommé ; 2 appel fautif, ou un outil dont la mesure
dépend manque — « je n'ai pas pu regarder » ne se lit jamais comme « il n'y a rien ».

Un fait à l'échelle du poste se lit TOUJOURS sur le système examiné, jamais sur l'emplacement de ce
fichier : lancé depuis l'amorce, `mode` et `prerequis` regardent ~/.claude, que rien n'habite encore.
Les scripts appelés sont ceux du système examiné (`<racine>/engine/`), qui résolvent leur racine
depuis leur propre emplacement. Python 3.8 au moins, bibliothèque standard seule.
"""
import argparse
import glob
import hashlib
import json
import os
import platform
import re
import sqlite3
import subprocess
import sys
from datetime import date

ICI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ICI)
import lib_reponses as L  # noqa: E402

# Les deux seules marques que le gabarit `gabarits/CLAUDE.md` pose. On cherche les marques EXACTES et
# non les mots « à remplir » : une règle de l'installateur peut parler de formulaires à remplir, et
# l'installation se dirait alors inachevée pour toujours.
MARQUES = ('*(réglage : à remplir)*', '*(à remplir)*')
# Claude Code : 2.1.247 pour les astuces en objets et `tipsFile` ; 2.1.281 pour qu'un agent au corps
# VIDE garde le prompt système par défaut (doc `sub-agents`, « An empty prompt requires Claude Code
# v2.1.281 or later », relue le 2026-10-01). Le lanceur livré a un corps vide : la borne est la plus
# haute des deux. Sous elle, la session d'installation tournerait sur un prompt système vide.
CLAUDE_MIN = (2, 1, 281)
PYTHON_MIN = (3, 8)
CONFLIT_RE = re.compile(r'^(<<<<<<<|>>>>>>>) ', re.M)
# Ce que Claude Code range lui-même dans ~/.claude et qui ne se suit jamais (§ 1.1). Le `.gitignore`
# livré en tient la liste complète ; ceux-ci se contrôlent en plus, nommément, parce qu'un seul
# suffit à publier une transcription ou un identifiant.
OUTIL_JAMAIS_SUIVI = ('projects/', 'sessions/', 'shell-snapshots/', 'todos/', 'history.jsonl',
                      '.credentials.json', 'settings.local.json')


class Appel(Exception):
    """L'appel est fautif, ou un outil dont la mesure dépend manque : code 2."""


class Rapport:
    def __init__(self, phase):
        self.phase, self.defauts = phase, []

    def ok(self, msg):
        print('[verifier] %s : ✅ %s' % (self.phase, msg))

    def ko(self, msg):
        self.defauts.append(msg)
        print('[verifier] %s : ⛔ %s' % (self.phase, msg), file=sys.stderr)

    def avert(self, msg):
        print('[verifier] %s : ⚠ %s' % (self.phase, msg))

    def fin(self):
        if self.defauts:
            print('[verifier] %s : %d défaut(s) — la phase N\'EST PAS close.' % (self.phase, len(self.defauts)),
                  file=sys.stderr)
            return 1
        print('[verifier] %s : CONFORME — la phase est close.' % self.phase)
        return 0


# ------------------------------------------------------------------------------------ outils
def lance(cmd, cwd=None, env=None, timeout=120):
    """(rc, sortie, erreur). Un exécutable absent rend 127, comme un shell."""
    try:
        r = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, timeout=timeout,
                           errors='replace')
        return r.returncode, r.stdout, r.stderr
    except FileNotFoundError:
        return 127, '', '%s : introuvable' % cmd[0]
    except subprocess.TimeoutExpired:
        return 124, '', '%s : délai de %d s dépassé' % (cmd[0], timeout)


def dernier(texte):
    lignes = [l for l in (texte or '').strip().splitlines() if l.strip()]
    return lignes[-1].strip() if lignes else ''


def reglages(racine):
    return os.environ.get('CLAUDEOS_REG') or os.path.join(racine, 'reglages')


def lit(chemin):
    try:
        return open(chemin, encoding='utf-8').read()
    except (OSError, UnicodeDecodeError):
        return None


def reponses(racine):
    """(valeurs ou None, défauts) — lues comme le moteur les lit (`lib_reponses`)."""
    return L.lit_reponses(os.path.join(reglages(racine), 'REPONSES'))


def regime_de(racine, valeurs=None):
    """`github` ou `aucun`, d'après GIT ; clé absente : d'après la présence d'un dépôt."""
    if valeurs is None:
        valeurs, _ = reponses(racine)
    g = (valeurs or {}).get('GIT')
    if g in ('par-domaine', 'unique'):
        return 'github'
    if g == 'aucun':
        return 'aucun'
    return 'github' if os.path.isdir(os.path.join(racine, '.git')) else 'aucun'


def git(racine, *args):
    return lance(['git', '-C', racine] + list(args))


def sans_commentaires(texte):
    return re.sub(r'<!--.*?-->', '', texte, flags=re.S)


def marques_de(texte):
    sortie = []
    for n, l in enumerate(texte.splitlines(), 1):
        for m in MARQUES:
            if m in l:
                sortie.append('ligne %d : %s' % (n, m))
    return sortie


def rubriques(texte):
    """[(nom, corps sans commentaire ni ligne vide)] de la section `## Persona` ; None sans section."""
    m = re.search(r'^## Persona[ \t]*\n(.*?)(?=^## |\Z)', texte, re.M | re.S)
    if not m:
        return None
    sortie = []
    for b in re.finditer(r'^### (.+?)[ \t]*\n(.*?)(?=^### |\Z)', m.group(1), re.M | re.S):
        corps = [l for l in sans_commentaires(b.group(2)).splitlines() if l.strip()]
        sortie.append((b.group(1).strip(), corps))
    return sortie


def seance_ecrite(racine):
    """True si le journal du niveau système porte un événement `seance` : la première clôture."""
    for f in sorted(glob.glob(os.path.join(racine, 'journal', '*.jsonl'))):
        try:
            for l in open(f, encoding='utf-8'):
                l = l.strip()
                if not l:
                    continue
                try:
                    if json.loads(l).get('type') == 'seance':
                        return True
                except ValueError:
                    continue
        except OSError:
            continue
    return False


def sauvegarde_poussee(racine):
    """(vrai, motif) : `origin/main` existe et porte `reglages/REPONSES`."""
    if not os.path.isdir(os.path.join(racine, '.git')):
        return False, '%s n\'est pas un dépôt git' % racine
    rc, _, _ = git(racine, 'rev-parse', '--verify', '-q', 'origin/main')
    if rc != 0:
        return False, 'origin/main absent : la première sauvegarde n\'a pas été poussée'
    rc, out, err = git(racine, 'ls-tree', '-r', '--name-only', 'origin/main', '--', 'reglages/REPONSES')
    if rc != 0:
        raise Appel('git ls-tree origin/main a échoué : %s' % dernier(err))
    if 'reglages/REPONSES' not in out.split():
        return False, 'origin/main ne porte pas reglages/REPONSES : la première sauvegarde n\'est pas partie'
    return True, ''


def appliquer_verifier(racine):
    """(rc, dernière ligne) de `appliquer-reponses.py --verifier` du système examiné."""
    script = os.path.join(racine, 'engine', 'appliquer-reponses.py')
    if not os.path.isfile(script):
        raise Appel('%s absent' % script)
    rc, out, err = lance([sys.executable, script, '--verifier'])
    return rc, (err.strip() or out.strip())


def identite_vide(racine):
    """None si l'identité git est remplie, sinon le motif. Le fichier est sourcé par bash : on le lit
    comme une affectation par ligne, sans l'exécuter."""
    texte = lit(os.path.join(reglages(racine), 'IDENTITE_GIT'))
    if texte is None:
        return 'reglages/IDENTITE_GIT absent'
    vals = dict(re.findall(r'^(GIT_NOM|GIT_EMAIL)="?([^"\n]*)"?\s*$', texte, re.M))
    vides = [k for k in ('GIT_NOM', 'GIT_EMAIL') if not vals.get(k, '').strip()]
    return ('reglages/IDENTITE_GIT : %s vide' % ' et '.join(vides)) if vides else None


# -------------------------------------------------------------------------- inachevée (§ 1.5)
def motifs_inachevee(racine):
    """Les motifs, en un mot chacun, dans l'ordre du § 1.5 ; liste vide si l'installation est finie."""
    motifs = []
    valeurs, defauts = reponses(racine)
    contrat = L.lit_contrat(os.path.join(racine, 'engine', 'config', 'REPONSES_CLES'))
    if valeurs is None or any(c['cle'] not in valeurs for c in contrat if c['origine'] == 'entretien'):
        motifs.append('réponses')
    texte = lit(os.path.join(racine, 'CLAUDE.md'))
    regime = regime_de(racine, valeurs)
    marque = texte is None or bool(marques_de(texte))
    if not marque:
        rc, _ = appliquer_verifier(racine)
        marque = rc != 0
    if not marque and regime == 'github':
        marque = identite_vide(racine) is not None
    if marque:
        motifs.append('marques')
    if regime == 'github':
        if not sauvegarde_poussee(racine)[0]:
            motifs.append('sauvegarde')
    elif not seance_ecrite(racine):
        motifs.append('clôture')
    return motifs


def message_inachevee(motifs):
    """M-INACHEVEE (plan V3 § 1.7, motif `clôture` ajouté par le plan complet). Le remède suit ce qui
    manque : quand seule la première sauvegarde ou clôture manque, le règlement est déjà le tien, et
    le dire tourner sur un gabarit serait faux."""
    tete = '⚠ INSTALLATION INACHEVÉE — %s.' % ', '.join(motifs)
    if 'réponses' in motifs or 'marques' in motifs:
        return (tete + ' Lance `/claudeos-onboarding` dans Claude Code. Tant que cette ligne '
                's\'affiche, ce poste tourne avec un règlement de gabarit, pas le tien.')
    if 'sauvegarde' in motifs:
        return (tete + ' Ton règlement est réglé ; il manque la première sauvegarde poussée : '
                'clôture la séance — « on arrête » —, la clôture pousse ton dépôt privé.')
    return (tete + ' Ton règlement est réglé ; il manque la première clôture : dis « on arrête » '
            'en fin de séance, rien ne sort du poste.')


def cmd_inachevee(racine, a):
    motifs = motifs_inachevee(racine)
    if not motifs:
        if not a.message:
            print('[verifier] inachevee : installation achevée — aucun des trois tests ne mord.')
        return 0
    print(message_inachevee(motifs) if a.message else ', '.join(motifs))
    return 1


# ------------------------------------------------------------------------------------- mode
def cmd_mode(racine, a):
    home = os.path.expanduser('~')
    traces_v2, traces_v3 = [], []
    if os.path.isdir(os.path.join(home, '.claudeos')):
        traces_v2.append('~/.claudeos/ existe : le dépôt local d\'une V1 ou d\'une V2')
    if os.path.isfile(os.path.join(racine, 'RULES_CATALOG.md')):
        traces_v2.append('RULES_CATALOG.md dans le système : un fichier du template V2')
    if os.path.isdir(os.path.join(racine, 'fiches')):
        traces_v2.append('fiches/ dans le système : le régime des fiches d\'une V1')
    quarantaine = os.path.isdir(os.path.join(home, '.claudeos-v2-quarantaine'))
    for rel in ('engine/verifier.py', 'noyau/regles/socle.md'):
        if os.path.isfile(os.path.join(racine, rel)):
            traces_v3.append('%s présent' % rel)
    depot = os.path.isdir(os.path.join(racine, '.git'))
    origine = git(racine, 'remote', 'get-url', 'origin')[1].strip() if depot else ''

    v3 = len(traces_v3) == 2
    motifs = motifs_inachevee(racine) if v3 else []
    if quarantaine:
        mode, note = 'migrer', 'une quarantaine V2 existe : une migration est en cours, la reprendre'
    elif traces_v2 and v3:
        mode, note = 'doute', 'des traces V1 ou V2 ET une V3 : demander avant tout geste'
    elif traces_v2:
        mode, note = 'migrer', 'une V1 ou une V2 est installée'
    elif v3 and motifs:
        mode, note = 'installer', 'une V3 posée mais inachevée (%s) : reprendre l\'installation' % ', '.join(motifs)
    elif v3:
        mode, note = 'v3', 'une V3 achevée : mettre à jour, ou rejouer l\'entretien'
    elif traces_v3:
        mode, note = 'doute', 'une V3 partielle (%s seul) : demander' % traces_v3[0]
    else:
        mode, note = 'installer', 'aucun ClaudeOS sur ce poste'
    print('mode=%s' % mode)
    print('motif : %s' % note)
    for t in traces_v2 + traces_v3:
        print('trace : %s' % t)
    if quarantaine:
        print('trace : ~/.claudeos-v2-quarantaine/ existe')
    if depot and mode == 'installer' and not v3:
        print('trace : %s est DÉJÀ un dépôt git%s — ne rien y poser sans avoir demandé'
              % (racine, ' (origin : %s)' % origine if origine else ''))
    if os.path.isfile(os.path.join(racine, 'CLAUDE.md')) and not v3:
        print('trace : un CLAUDE.md existe déjà — la plomberie le copie hors du système (M-CLAUDE-PREEXISTANT)')
    procedure = {'installer': 'installateur/INSTALLER.md', 'migrer': 'installateur/MIGRER.md',
                 'v3': 'installateur/METTRE_A_JOUR.md ou installateur/ENTRETIEN.md, au choix de la personne',
                 'doute': 'aucune avant d\'avoir demandé'}[mode]
    print('procédure : %s' % procedure)
    return 0


def traces_v2(racine):
    """Ce que la V2 a laissé dans ~/.claude, lu par `import-v2.py` — une seule implémentation, chargée
    par son chemin : son nom porte un tiret. Rend None si le script manque."""
    script = os.path.join(ICI, 'import-v2.py')
    if not os.path.isfile(script):
        return None
    import importlib.util
    spec = importlib.util.spec_from_file_location('import_v2', script)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m.traces_dans_claude(racine)


def m_v2_detectee(r, racine):
    """M-V2-DETECTEE : une V1 ou une V2 habite ~/.claude, et aucune quarantaine ne l'en a sortie."""
    traces = traces_v2(racine)
    if traces is None:
        r.avert('import-v2.py absent : les traces d\'une V2 ne sont pas cherchées')
    elif traces:
        r.ko('M-V2-DETECTEE — ce poste porte une V1 ou une V2 de ClaudeOS (%s). Ne continue pas '
             'l\'installation : suis la migration, installateur/MIGRER.md, qui garde ta V2 intacte '
             'jusqu\'au bout. Rien n\'a été écrit.' % ' ; '.join(traces[:4]) + (' …' if len(traces) > 4 else ''))
    else:
        r.ok('aucune trace d\'une V1 ou d\'une V2 dans le système')


# -------------------------------------------------------------------------------- prérequis
def version_claude():
    rc, out, err = lance(['claude', '--version'], timeout=60)
    if rc == 127:
        return None, 'claude introuvable dans le PATH'
    m = re.search(r'(\d+)\.(\d+)\.(\d+)', out + ' ' + err)
    if rc != 0 or not m:
        return None, 'claude --version illisible (rc=%d) : %s' % (rc, dernier(out + err))
    return tuple(int(x) for x in m.groups()), None


def cmd_prerequis(racine, a):
    r = Rapport('prerequis')
    sysname, release = platform.system(), platform.release()
    if sysname == 'Darwin':
        r.ok('plateforme : macOS, éprouvée')
    elif sysname == 'Linux' and 'microsoft' in release.lower():
        r.ok('plateforme : WSL, supportée, non éprouvée — l\'agent adapte une commande qui échoue')
    else:
        r.avert('plateforme : %s %s, non supportée — ClaudeOS vise macOS et WSL ; la suite peut casser'
                % (sysname, release))
    if sys.version_info[:2] >= PYTHON_MIN:
        r.ok('python3 %d.%d' % sys.version_info[:2])
    else:
        r.ko('python3 %d.%d, il faut %d.%d au moins' % (sys.version_info[:2] + PYTHON_MIN))
    try:
        c = sqlite3.connect(':memory:')
        c.execute('create virtual table t using fts5(x)')
        c.close()
        r.ok('python3 ouvre une table FTS5 : l\'index de recherche se bâtira')
    except sqlite3.Error as e:
        r.ko('python3 n\'ouvre pas de table FTS5 (%s) : l\'index de recherche ne se bâtira pas' % e)
    v, err = version_claude()
    if v is None:
        r.ko(err)
    elif v < CLAUDE_MIN:
        r.ko('Claude Code %s, il faut %s au moins : `claude update`'
             % ('.'.join(map(str, v)), '.'.join(map(str, CLAUDE_MIN))))
    else:
        r.ok('Claude Code %s' % '.'.join(map(str, v)))
    rc, _, _ = lance(['curl', '--version'])
    if rc == 0:
        r.ok('curl présent : les compétences optionnelles se composeront')
    else:
        r.avert('curl absent : les compétences optionnelles ne se composeront pas')
    # tmux porte la session par projet (claudeos-session.sh) ; sans lui le système tourne en session
    # unique, donc un avertissement, comme curl (A9, le 2026-10-02 : le § 1.9 l'annonçait depuis A6).
    if lance(['tmux', '-V'])[0] == 0:
        r.ok('tmux présent : une session par projet pourra s\'ouvrir')
    else:
        r.avert('tmux absent : une session par projet ne s\'ouvrira pas — macOS : brew install tmux ; '
                'WSL : sudo apt install tmux')
    regime = a.regime
    if regime is None:
        valeurs, _ = reponses(racine)
        if valeurs and valeurs.get('GIT'):
            regime = regime_de(racine, valeurs)
    g_rc = lance(['git', '--version'])[0]
    h_rc, h_out, h_err = lance(['gh', 'auth', 'status'])
    if regime == 'github':
        (r.ok if g_rc == 0 else r.ko)('git %s' % ('présent' if g_rc == 0 else 'introuvable'))
        if h_rc == 127:
            r.ko('gh introuvable : le régime GitHub crée et contrôle tes dépôts privés par lui')
        elif h_rc != 0:
            r.ko('gh n\'est pas authentifié — lance toi-même : gh auth login')
        else:
            r.ok('gh authentifié')
    elif regime == 'aucun':
        r.ok('régime sans git : ni git ni gh ne sont exigés')
    else:
        r.avert('régime pas encore choisi : git %s, gh %s — exigés seulement si tu choisis GitHub'
                % ('présent' if g_rc == 0 else 'absent',
                   'authentifié' if h_rc == 0 else ('absent' if h_rc == 127 else 'non authentifié')))
    m_v2_detectee(r, racine)
    return r.fin()


# -------------------------------------------------------------------------------- plomberie
def verifie_fusion(r, racine):
    script = os.path.join(racine, 'engine', 'fusionner-reglages.py')
    if not os.path.isfile(script):
        raise Appel('%s absent' % script)
    rc, out, err = lance([sys.executable, script, '--verifier'])
    if rc == 0:
        r.ok('fragment de réglages fusionné dans settings.json, sans doublon')
    elif rc == 1:
        r.ko('settings.json : %s' % (err.strip() or out.strip()).replace('\n', ' · '))
    else:
        raise Appel('fusionner-reglages.py --verifier rc=%d : %s' % (rc, dernier(err or out)))


def verifie_livre(r, racine):
    import regime as R
    try:
        ecarts, n, tenus = R.livre_ecarts(racine)
        arbre = R.livre_arbre_ecarts(racine) if n else []
    except R.Refus as e:
        r.ko('état livré illisible : %s' % e)
        return
    if n == 0:
        r.ko('.claudeos/livre/MANIFESTE absent ou vide : l\'état livré n\'est pas écrit (regime.py pose)')
    elif ecarts:
        r.ko('fichiers livrés qui diffèrent de .claudeos/livre/MANIFESTE : %s'
             % ', '.join('%s (%s)' % e for e in ecarts[:6]) + (' …' if len(ecarts) > 6 else ''))
    else:
        r.ok('les %d fichiers livrés égalent .claudeos/livre/MANIFESTE%s' % (
            n, ', dont %d écart(s) gardé(s) par choix à la mise à jour (GARDES)' % len(tenus) if tenus else ''))
    # La copie livrée est la base de la mise à jour (A8) : fausse, elle ferait montrer un écart faux.
    if arbre:
        r.ko('copie livrée, .claudeos/livre/ARBRE.tar.gz : %s' % ' · '.join(arbre[:4])
             + (' …' if len(arbre) > 4 else ''))


def cmd_plomberie(racine, a):
    r = Rapport('plomberie')
    valeurs, defauts = reponses(racine)
    if valeurs is None:
        r.ko('reglages/REPONSES absent : la plomberie y écrit GIT et PROXY')
        valeurs = {}
    for k, admis in (('GIT', ('par-domaine', 'unique', 'aucun')), ('PROXY', ('oui', 'non'))):
        if valeurs.get(k) in admis:
            r.ok('%s=%s' % (k, valeurs[k]))
        else:
            r.ko('%s absent ou hors contrat dans reglages/REPONSES (%r)' % (k, valeurs.get(k)))
    texte = lit(os.path.join(racine, 'CLAUDE.md'))
    if texte is None:
        r.ko('CLAUDE.md absent : la plomberie le copie depuis gabarits/CLAUDE.md')
    else:
        try:
            L.localise_bloc(texte.splitlines(keepends=True))
            r.ok('CLAUDE.md porte le bloc d\'imports : c\'est le gabarit, pas un fichier d\'avant')
        except ValueError as e:
            r.ko('CLAUDE.md : %s — ce n\'est pas le gabarit de ClaudeOS' % e)
    acc = (lit(os.path.join(reglages(racine), 'ACCUEIL')) or '').strip()
    try:
        date.fromisoformat(acc[:10])
        r.ok('lecture obligée datée du %s' % acc[:10])
    except ValueError:
        r.ko('reglages/ACCUEIL absent ou sans date AAAA-MM-JJ : la lecture obligée n\'est pas consignée')
    # Ce qui existait avant ClaudeOS est copié sous ~/.claude-avant-claudeos/<horodatage>/ : le CLAUDE.md
    # d'avant, et les fichiers qu'un checkout ou une pose refusait d'écraser. Une copie ABSENTE ne se
    # prouve pas d'ici — rien ne dit qu'il y avait quelque chose ; `mode` l'annonçait avant la plomberie.
    avant = os.path.join(os.path.expanduser('~'), '.claude-avant-claudeos')
    copies = sorted(glob.glob(os.path.join(avant, '*', 'CLAUDE.md')))
    if copies:
        r.ok('le CLAUDE.md d\'avant ClaudeOS est copié sous ~/.claude-avant-claudeos/ (%s)'
             % ', '.join(os.path.basename(os.path.dirname(c)) for c in copies))
    verifie_fusion(r, racine)
    m_v2_detectee(r, racine)

    regime = regime_de(racine, valeurs)
    if regime == 'github':
        rc, top, _ = git(racine, 'rev-parse', '--show-toplevel')
        if rc != 0 or os.path.realpath(top.strip()) != os.path.realpath(racine):
            r.ko('%s n\'est pas la racine d\'un dépôt git' % racine)
            return r.fin()
        r.ok('le système est un dépôt git')
        rc, url, _ = git(racine, 'remote', 'get-url', 'origin')
        url = url.strip()
        if rc != 0 or not url:
            r.ko('aucun remote origin')
        elif url.startswith('/') or url.startswith('file://'):
            r.avert('origin est un dépôt local (%s) : visibilité sans objet — dépôt d\'essai' % url)
        else:
            vrc, vis, verr = lance(['gh', 'repo', 'view', url, '--json', 'visibility', '--jq', '.visibility'])
            vis = vis.strip().upper()
            if vrc != 0:
                r.ko('visibilité de origin non contrôlée (gh rc=%d : %s)' % (vrc, dernier(verr)))
            elif vis != 'PRIVATE':
                r.ko('origin %s est %s : il doit être PRIVÉ (M-DEPOT-PUBLIC)' % (url, vis or 'de visibilité inconnue'))
            else:
                r.ok('origin privé')
        rc, up, _ = git(racine, 'remote', 'get-url', 'upstream')
        orig = (lit(os.path.join(racine, 'engine', 'config', 'TEMPLATE_ORIGINE')) or '').strip()
        if rc != 0 or not up.strip():
            r.ko('aucun remote upstream : les versions suivantes n\'arriveraient pas')
        elif orig and up.strip() != orig:
            r.ko('upstream vaut %s, engine/config/TEMPLATE_ORIGINE dit %s' % (up.strip(), orig))
        else:
            r.ok('upstream posé%s' % ('' if orig else ' (TEMPLATE_ORIGINE absent : non comparé)'))
        rc, out, err = git(racine, 'ls-files', '-ci', '--exclude-standard')
        if rc != 0:
            raise Appel('git ls-files a échoué : %s' % dernier(err))
        suivis_ignores = [l for l in out.splitlines() if l.strip()]
        rc, tous, _ = git(racine, 'ls-files')
        outil = [l for l in tous.splitlines() if any(l.startswith(p) if p.endswith('/') else
                                                      (l == p or l.endswith('/' + p))
                                                      for p in OUTIL_JAMAIS_SUIVI)]
        if suivis_ignores or outil:
            r.ko('fichiers de l\'outil suivis par le dépôt : %s' % ', '.join((suivis_ignores + outil)[:6]))
        else:
            r.ok('aucun fichier de l\'outil suivi')
        if 'engine/verifier.py' not in tous.split('\n'):
            r.ko('engine/verifier.py n\'est pas suivi : les chemins du template ne sont pas extraits du dépôt')
        shim = os.path.join(racine, '.git', 'hooks', 'pre-commit')
        if os.access(shim, os.X_OK) and 'pre-commit-alarmes.sh' in (lit(shim) or ''):
            r.ok('crochet de commit posé')
        else:
            r.ko('crochet de commit absent : le dépôt committerait sans aucune alarme — install-poste.sh')
        rc, attr, _ = git(racine, 'config', '--get', 'core.attributesFile')
        attendu = os.path.join(racine, 'engine', 'config', 'gitattributes-journal')
        if rc == 0 and os.path.realpath(os.path.expanduser(attr.strip())) == os.path.realpath(attendu):
            r.ok('pilote de fusion des journaux posé')
        else:
            r.ko('pilote de fusion des journaux absent (core.attributesFile) — install-poste.sh')
        if valeurs.get('GIT') == 'unique':
            excl = lit(os.path.join(racine, '.git', 'info', 'exclude')) or ''
            ref = lit(os.path.join(racine, 'engine', 'config', 'gitignore-documents')) or ''
            manque = [l for l in ref.splitlines() if l.strip() and not l.startswith('#')
                      and l not in excl.splitlines()]
            if manque:
                r.ko('.git/info/exclude ne porte pas la liste noire des dossiers de travail (%d motif(s))' % len(manque))
            else:
                r.ok('liste noire des dossiers de travail posée dans .git/info/exclude')
        if os.path.isfile(os.path.join(reglages(racine), 'IDENTITE_GIT')):
            r.ok('reglages/IDENTITE_GIT posé — l\'entretien le remplit')
        else:
            r.ko('reglages/IDENTITE_GIT absent : copier gabarits/IDENTITE_GIT')
    else:
        if os.path.isdir(os.path.join(racine, '.git')):
            r.ko('GIT=aucun, et le système porte un .git/')
        if os.path.isfile(os.path.join(racine, '.claudeos-racine')):
            r.ok('racine sans git marquée (.claudeos-racine)')
        else:
            r.ko('.claudeos-racine absent — install-poste.sh le pose')
        verifie_livre(r, racine)
        if os.path.isfile(os.path.join(racine, '.claudeos', 'empreintes', 'MANIFESTE.json')):
            r.ok('référence de départ des empreintes posée')
        else:
            r.ko('.claudeos/empreintes/MANIFESTE.json absent — install-poste.sh la pose')
    return r.fin()


# -------------------------------------------------------------------------------- entretien
def verifie_persona(r, texte):
    marques = marques_de(texte)
    if marques:
        r.ko('marque de gabarit encore dans CLAUDE.md : %s' % ', '.join(marques[:4]))
    else:
        r.ok('aucune marque de gabarit dans CLAUDE.md')
    rub = rubriques(texte)
    if rub is None:
        r.ko('CLAUDE.md sans section « ## Persona »')
        return
    noms = [n for n, _ in rub]
    if 'Identité' not in noms:
        r.ko('rubrique « Identité » absente : c\'est la seule qui ne se retire pas')
    vides = [n for n, c in rub if not c]
    if vides:
        r.ko('rubrique(s) sans réglage : %s — une rubrique sans avis se retire, elle ne reste pas vide'
             % ', '.join(vides))
    elif 'Identité' in noms:
        r.ok('persona : %d rubrique(s) réglée(s), Identité comprise' % len(rub))


def verifie_reponses(r, racine):
    valeurs, defauts = reponses(racine)
    contrat = L.lit_contrat(os.path.join(racine, 'engine', 'config', 'REPONSES_CLES'))
    if valeurs is not None:
        defauts = defauts + L.defauts_reponses(contrat, valeurs)
    if valeurs is None or defauts:
        for d in defauts or ['reglages/REPONSES illisible']:
            r.ko(d)
    else:
        r.ok('reglages/REPONSES : les %d clés du contrat, valeurs admises' % len(contrat))
    return valeurs or {}, contrat


def cmd_entretien(racine, a):
    r = Rapport('entretien')
    valeurs, contrat = verifie_reponses(r, racine)
    rc, sortie = appliquer_verifier(racine)
    if rc == 0:
        r.ok('bloc d\'imports et skillOverrides conformes aux réponses')
    elif rc == 1:
        r.ko('appliquer-reponses.py --verifier : %s' % sortie.replace('\n', ' · ')[:400])
    else:
        raise Appel('appliquer-reponses.py --verifier rc=%d : %s' % (rc, dernier(sortie)))
    texte = lit(os.path.join(racine, 'CLAUDE.md'))
    if texte is None:
        r.ko('CLAUDE.md absent')
    else:
        verifie_persona(r, texte)
    options = next((c['valeurs'] for c in contrat if c['cle'] == 'SKILLS_OPTION'), [])
    retenues = set(L.elements(valeurs.get('SKILLS_OPTION', '')))
    for nom in options:
        d = os.path.join(racine, 'skills', nom)
        present = os.path.isfile(os.path.join(d, 'SKILL.md')) and os.path.isfile(os.path.join(d, 'LICENSE.amont'))
        if (nom in retenues) != present:
            r.ko('skills/%s/ %s alors que SKILLS_OPTION %s' % (
                nom, 'présente' if present else 'absente', 'ne la retient pas' if present else 'la retient'))
    sa = os.path.join(racine, 'engine', 'skills-amont.sh')
    rc, out, err = lance(['bash', sa, '--verifier'])
    if rc == 0:
        r.ok('compétences optionnelles : exactement SKILLS_OPTION, compositions intactes')
    elif rc == 3:
        r.avert('compositions non jugées, cache des emprunts absent : %s' % dernier(err or out))
    elif rc == 1:
        r.ko('skills-amont.sh --verifier : %s' % (err or out).strip().replace('\n', ' · ')[:400])
    else:
        raise Appel('skills-amont.sh --verifier rc=%d : %s' % (rc, dernier(err or out)))
    if regime_de(racine, valeurs) == 'github':
        vide = identite_vide(racine)
        (r.ko if vide else r.ok)(vide or 'identité git remplie')
    if valeurs.get('MULTIDOMAINE') == 'oui':
        if os.path.isfile(os.path.join(racine, 'memory', 'ROUTING_MISSES.md')):
            r.ok('registre des ratés de routage posé')
        else:
            r.ko('memory/ROUTING_MISSES.md absent avec MULTIDOMAINE=oui : la règle le fait remplir, et le '
                 'contrôle hebdomadaire 23 échoue sans lui — le copier depuis gabarits/')
    etat = lit(os.path.join(racine, 'ETAT.md'))
    m = re.search(r'^## Où trouver[ \t]*\n(.*?)(?=^## |\Z)', etat or '', re.M | re.S)
    if etat is None:
        r.ko('ETAT.md du niveau système absent : les premiers événements ne sont pas projetés')
    elif not m or not re.search(r'^- ', m.group(1), re.M):
        r.ko('ETAT.md sans pointeur dans « Où trouver » : le contrôle 45 n\'aurait rien à lire')
    else:
        r.ok('premiers événements du niveau système écrits et projetés')
    return r.fin()


# ---------------------------------------------------------------------------------- arrivée
def cmd_arrivee(racine, a):
    r = Rapport('arrivee')
    motifs = motifs_inachevee(racine)
    if motifs:
        r.ko('1. le démarrage dit encore : %s' % message_inachevee(motifs))
    else:
        r.ok('1. aucun M-INACHEVEE au démarrage')
    verifie_reponses(r, racine)
    texte = lit(os.path.join(racine, 'CLAUDE.md'))
    if texte is None:
        r.ko('3. CLAUDE.md absent')
    else:
        verifie_persona(r, texte)
    if regime_de(racine) == 'github':
        ok, motif = sauvegarde_poussee(racine)
        (r.ok if ok else r.ko)('4. %s' % ('première sauvegarde poussée : origin/main porte reglages/REPONSES' if ok else motif))
    else:
        ok = seance_ecrite(racine)
        (r.ok if ok else r.ko)('4. %s' % ('première clôture jouée : un événement seance au journal'
                                          if ok else 'aucun événement seance : la première clôture n\'a pas été jouée'))
    cfg = os.path.join(racine, 'engine', 'config.sh')
    rc, out, err = lance(['bash', '-c', 'source "$1" >/dev/null 2>&1 || exit 2; claudeos_ws_roots', '_', cfg])
    if rc != 0:
        raise Appel('claudeos_ws_roots a échoué (rc=%d) : %s' % (rc, dernier(err)))
    dossiers = [l for l in out.splitlines() if l.strip() and os.path.isdir(l.strip())]
    if dossiers:
        r.ok('5. premier dossier de travail : %s' % dossiers[0])
    else:
        r.ko('5. aucun dossier de travail ne sort de claudeos_ws_roots : la compétence nouveau-domaine')
    return r.fin()


# ------------------------------------------------------------------------- migration, mise à jour
def cmd_migration(racine, a):
    script = os.path.join(racine, 'engine', 'import-v2.py')
    if not os.path.isfile(script):
        raise Appel('%s absent : cette version du template ne sait pas encore vérifier une migration' % script)
    rc, out, err = lance([sys.executable, script, '--verifier', '--etape', a.etape or 'fin'], timeout=600)
    sys.stdout.write(out)
    sys.stderr.write(err)
    return rc


def cmd_mise_a_jour(racine, a):
    r = Rapport('mise-a-jour')
    version = (lit(os.path.join(racine, 'engine', 'VERSION')) or '').strip()
    # Le « v » de tête d'une étiquette git ne compte pas : `--version v3.0.1` vise `3.0.1`.
    if not version:
        r.ko('engine/VERSION absent ou vide')
    elif a.version and version.lstrip('v') != a.version.lstrip('v'):
        r.ko('engine/VERSION vaut %s, la version visée est %s' % (version, a.version))
    else:
        r.ok('engine/VERSION = %s' % version)
    regime = regime_de(racine)
    if regime == 'github':
        rc, out, _ = git(racine, 'diff', '--name-only', '--diff-filter=U')
        if out.strip():
            r.ko('fusion inachevée, fichiers en conflit : %s' % ', '.join(out.split()[:6]))
        if os.path.exists(os.path.join(racine, '.git', 'MERGE_HEAD')):
            r.ko('une fusion est en cours (MERGE_HEAD) : la conclure ou l\'abandonner')
        rc, tous, _ = git(racine, 'ls-files')
        chemins = [l for l in tous.splitlines() if l.strip()]
    else:
        import regime as R
        chemins = sorted(R.livre_lit(racine).keys()) + ['CLAUDE.md']
        if os.path.isdir(reglages(racine)):
            chemins += ['reglages/%s' % f for f in sorted(os.listdir(reglages(racine)))]
    marques = []
    for rel in chemins:
        p = os.path.join(racine, rel)
        if not os.path.isfile(p):
            continue
        t = lit(p)
        if t and CONFLIT_RE.search(t):
            marques.append(rel)
    if marques:
        r.ko('marqueurs de conflit dans : %s' % ', '.join(marques[:6]))
    else:
        r.ok('aucun marqueur de conflit (%d fichier(s) lus)' % len(chemins))
    rc, sortie = appliquer_verifier(racine)
    if rc == 0:
        r.ok('bloc d\'imports et skillOverrides conformes aux réponses')
    elif rc == 1:
        r.ko('appliquer-reponses.py --verifier : %s' % sortie.replace('\n', ' · ')[:400])
    else:
        raise Appel('appliquer-reponses.py --verifier rc=%d : %s' % (rc, dernier(sortie)))
    verifie_fusion(r, racine)
    if regime == 'aucun':
        if os.path.isdir(os.path.join(racine, '.claudeos', 'mise-a-jour')):
            r.ko('une mise à jour est en cours (.claudeos/mise-a-jour/) : mettre-a-jour.py --appliquer la conclut')
        livre_v = (lit(os.path.join(racine, '.claudeos', 'livre', 'VERSION')) or '').strip()
        if version and livre_v != version:
            r.ko('.claudeos/livre/VERSION vaut %r, engine/VERSION %s : l\'état livré n\'est pas réécrit'
                 % (livre_v, version))
        verifie_livre(r, racine)
    return r.fin()


# -------------------------------------------------------------------------------------- main
def main(argv):
    ap = argparse.ArgumentParser(prog='verifier.py')
    ap.add_argument('phase', choices=('mode', 'inachevee', 'prerequis', 'plomberie', 'entretien',
                                      'arrivee', 'migration', 'mise-a-jour'))
    ap.add_argument('--racine', metavar='DOSSIER')
    ap.add_argument('--message', action='store_true')
    ap.add_argument('--regime', choices=('github', 'aucun'))
    ap.add_argument('--version', metavar='V')
    ap.add_argument('--etape', choices=('quarantaine', 'import', 'domaines', 'fin'))
    a = ap.parse_args(argv)
    racine = os.path.realpath(os.path.expanduser(a.racine or '~/.claude'))
    if a.message and a.phase != 'inachevee':
        ap.error('--message ne vaut que pour inachevee')
    if a.regime and a.phase != 'prerequis':
        ap.error('--regime ne vaut que pour prerequis')
    if a.version and a.phase != 'mise-a-jour':
        ap.error('--version ne vaut que pour mise-a-jour')
    if a.etape and a.phase != 'migration':
        ap.error('--etape ne vaut que pour migration')
    phases = {'mode': cmd_mode, 'inachevee': cmd_inachevee, 'prerequis': cmd_prerequis,
              'plomberie': cmd_plomberie, 'entretien': cmd_entretien, 'arrivee': cmd_arrivee,
              'migration': cmd_migration, 'mise-a-jour': cmd_mise_a_jour}
    try:
        return phases[a.phase](racine, a)
    except (Appel, L.Refus) as e:
        print('[verifier] %s : ⛔ NON MESURÉ — %s' % (a.phase, e), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
