#!/usr/bin/env python3
"""mesure-personnalisation.py — ce qui, dans le règlement du template, dépend d'une réponse.

Écrit le 2026-10-01, plan complet de templating § 1.3, A4 (`d-mesure-perso`). Code PROPRE AU
TEMPLATE. `differentiel` et `invariant` écrits le 2026-10-02, A9 (garanties 1 et 2).

  ratio  [--reponses F]   la part des règles retenues par F dont la présence ou la forme dépend
                          d'une réponse ;
  taille [--reponses F]   la taille, en octets, des fragments que F retient ;
  differentiel [--base F] [--contre G]
                          ce que chaque réponse change dans les SORTIES DU MOTEUR (garantie 1) ;
  invariant               les fichiers livrés, par classe de PERIMETRE_TEMPLATE (garantie 2).
  Défaut de F : gabarits/reponses/MAX.REPONSES ; de G : gabarits/reponses/MIN.REPONSES.

LE DIFFÉRENTIEL NE COMPTE QUE DES SORTIES RÉELLES, jamais une relecture du code : pour un jeu de
réponses, sept sorties produites par le moteur lui-même, dans un dossier jetable — le `CLAUDE.md` et
les `skillOverrides` d'`appliquer-reponses.py --essai`, la liste de `skills-amont.sh --liste`,
`claudeos_ws_roots` et `claudeos_repos` sur un `HOME` garni d'un dépôt par préfixe, le démarrage
(`boot-check.sh`), et le crochet d'alarmes joué dans chacun de ces dépôts. Les chemins jetables sont
remplacés par des jetons, et chaque sortie est produite deux fois : une sortie instable rend 2, car
elle ferait diverger toutes les clés. Puis, PAR CLÉ, le jeu de base où cette seule clé prend une
autre valeur, tirée du contrat : un choix prend la première autre valeur, une liste ou une clé libre
perd son dernier élément, ou reçoit `ESSAI_` si elle est vide. Une bascule que le contrat refuse
SEULE s'accompagne des clés qui la SUIVENT au contrat, ramenées une à une à leur valeur du jeu contre
jusqu'à ce qu'il l'accepte — `GIT=unique` vide les préfixes ; la divergence se mesure alors contre
la base ainsi accompagnée, pour n'attribuer à la clé que son propre effet. Une clé qui PRÉCÈDE ne
bouge jamais : sous `GIT=aucun`, un préfixe ou `MULTIPOSTE=oui` restent SANS OBJET, et nommés.
Une clé d'entretien qui ne change aucune sortie rend 1 : elle sort du fichier ou elle se branche
(§ 1.2). Une sortie qui demande git est omise, et dite, sur un poste sans git.

L'INVARIANT lit `engine/PERIMETRE_TEMPLATE` : chaque fichier sous la racine est compté dans la
classe de la PREMIÈRE ligne dont le motif `fnmatch` le prend ; une ligne `manque:` sans motif rend 1.

UNE RÈGLE est un item de liste de premier niveau d'un fragment (`- ` en colonne 0) : un sous-item en
fait partie, une citation ou un titre n'en est pas une. Le ratio vaut conditionnelles /
(conditionnelles + fixes) : les conditionnelles sont les règles des fragments `<cle>-<valeur>.md`, les
fixes celles du socle HORS sa section « Trois interdits, jamais conditionnés ». Ces trois-là sont
fixes par nature — leur absence laisse passer un geste irréversible — et ne comptent donc pas
contre la personnalisation (plan V3, lot 2, geste 8).

POURQUOI LE JEU MAX, ET PAS TOUS LES FRAGMENTS. Une règle dont la forme dépend d'une réponse a une
ligne dans CHAQUE variante (§ 1.3) : `git-par-domaine`, `git-unique` et `git-aucun` portent la même
règle sous trois formes, et les compter toutes la compterait trois fois. MAX retient une variante
par clé et toutes les valeurs qui portent des règles : c'est le règlement le plus complet qu'une
installation reçoive, et chaque règle y est comptée une fois.

LES CLIQUETS se lisent dans `config.sh`, jamais recopiés ici, et sa valeur du TEMPLATE : les
fragments appartiennent au template, `reglages/CLIQUETS` ne les concerne pas.
- `CLAUDEOS_CLIQUET_PERSONNALISATION` — cliquet INVERSE : le ratio ne baisse jamais, il ne peut que
  monter, et le plancher est 50 (`d-mesure-perso`). Une montée se réécrit dans `config.sh`, datée.
- `CLAUDEOS_CLIQUET_REGLEMENT` — la taille des fragments retenus, en octets, au plus.
Codes : 0 ; 1 ratio sous le plancher ou le cliquet, taille au-dessus, clé sans divergence, ou
`manque:` sans motif ; 2 appel ou template fautif, ou sortie instable.
"""
import argparse
import difflib
import fnmatch
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib_reponses as L  # noqa: E402

PLANCHER = 50
TITRE_INTERDITS = '## Trois interdits, jamais conditionnés'
CONFIG = os.path.join(L.ICI, 'config.sh')
JEU_MAX = os.path.join(L.RACINE, 'gabarits', 'reponses', 'MAX.REPONSES')
JEU_MIN = os.path.join(L.RACINE, 'gabarits', 'reponses', 'MIN.REPONSES')
PERIMETRE = os.path.join(L.ICI, 'PERIMETRE_TEMPLATE')
IGNORES = {'.git', '__pycache__', '.DS_Store'}


def dit(msg, err=False):
    print('[perso] ' + msg, file=sys.stderr if err else sys.stdout)


def constante(nom):
    """La valeur d'une constante entière de config.sh, ou None si elle n'y est pas posée."""
    m = re.search(r'^%s=(\d+)\b' % re.escape(nom), open(CONFIG, encoding='utf-8').read(), re.M)
    return int(m.group(1)) if m else None


def regles(chemin):
    """(règles, interdits) : les items de premier niveau, et ceux de la section des trois interdits."""
    total = interdits = 0
    dans = False
    for l in open(chemin, encoding='utf-8').read().splitlines():
        if l.startswith('#'):
            dans = l.rstrip() == TITRE_INTERDITS
        elif l.startswith('- '):
            total += 1
            interdits += dans
    return total, interdits


def retenus(f_rep):
    contrat = L.lit_contrat()
    orph = L.orphelins(contrat)
    if orph:
        raise L.Refus('fragment orphelin, jamais importé : ' + ', '.join(orph))
    valeurs, defauts = L.lit_reponses(f_rep)
    if valeurs is not None:
        defauts += L.defauts_reponses(contrat, valeurs)
    if defauts:
        raise L.Refus('jeu %s non conforme : %s' % (f_rep, ' ; '.join(defauts)))
    return L.fragments_retenus(contrat, valeurs)


def ratio(f_rep):
    frags = retenus(f_rep)
    socle, interdits = regles(os.path.join(L.REGLES, L.SOCLE))
    if not interdits:
        raise L.Refus('le socle n\'a pas de section « %s » : les trois interdits ne se comptent pas'
                      % TITRE_INTERDITS[3:])
    fixes = socle - interdits
    cond = sum(regles(os.path.join(L.REGLES, f))[0] for f in frags[1:])
    if cond + fixes == 0:
        raise L.Refus('aucune règle hors des trois interdits : rien à mesurer')
    r = cond * 100 // (cond + fixes)
    cliquet = constante('CLAUDEOS_CLIQUET_PERSONNALISATION')
    dit('%s : %d fragments, %d règles — %d interdits du socle hors compte, %d fixes, %d conditionnelles'
        % (os.path.basename(f_rep), len(frags), socle + cond, interdits, fixes, cond))
    dit('ratio : %d %% des règles hors interdits dépendent d\'une réponse (%d / %d, arrondi par défaut)'
        % (r, cond, cond + fixes))
    if cliquet is None:
        dit('⛔ CLAUDEOS_CLIQUET_PERSONNALISATION absent de %s : le cliquet ne se devine pas — le poser '
            'à la valeur mesurée' % CONFIG, err=True)
        return 2
    if r < PLANCHER:
        dit('⛔ sous le plancher de %d %% : conditionner des règles fixes, ou en sortir vers une compétence'
            % PLANCHER, err=True)
        return 1
    if r < cliquet:
        dit('⛔ sous le cliquet inverse, %d %% : le ratio ne baisse jamais — pour ajouter une règle fixe, '
            'en conditionner une autre' % cliquet, err=True)
        return 1
    dit('✅ plancher %d %%, cliquet %d %%%s' % (PLANCHER, cliquet, '' if r == cliquet else
        ' — il peut monter à %d %%, une montée se réécrit dans config.sh, datée' % r))
    return 0


def taille(f_rep):
    frags = retenus(f_rep)
    octets = sum(os.path.getsize(os.path.join(L.REGLES, f)) for f in frags)
    borne = constante('CLAUDEOS_CLIQUET_REGLEMENT')
    dit('%s : %d fragments, %d octets' % (os.path.basename(f_rep), len(frags), octets))
    if borne is None:
        dit('⛔ CLAUDEOS_CLIQUET_REGLEMENT absent de %s' % CONFIG, err=True)
        return 2
    if octets > borne:
        dit('⛔ au-dessus du cliquet du règlement, %d octets : pour ajouter, retirer d\'abord' % borne, err=True)
        return 1
    dit('✅ sous le cliquet du règlement, %d octets — marge %d' % (borne, borne - octets))
    return 0


# --- Le différentiel ------------------------------------------------------------------------------

def valeurs_de(f_rep):
    contrat = L.lit_contrat()
    valeurs, defauts = L.lit_reponses(f_rep)
    if valeurs is not None:
        defauts += L.defauts_reponses(contrat, valeurs)
    if defauts:
        raise L.Refus('jeu %s non conforme : %s' % (f_rep, ' ; '.join(defauts)))
    return contrat, valeurs


def alternatives(c, v):
    """Les autres valeurs à essayer pour la clé c, dans l'ordre : la première que le contrat accepte sert."""
    if c['type'] == 'choix':
        return [x for x in c['valeurs'] if x != v]
    e = L.elements(v)
    if not e:
        return [c['valeurs'][0]] if c['type'] == 'liste' else ['ESSAI_']
    return [','.join(e[:-1])] + ([''] if len(e) > 2 else [])


def texte_reponses(contrat, valeurs):
    return ''.join('%s=%s\n' % (c['cle'], valeurs[c['cle']]) for c in contrat if c['cle'] in valeurs)


class Atelier:
    """Un dossier jetable : un HOME garni d'un dépôt par préfixe, et un dossier par variante."""

    def __init__(self, prefixes):
        self.tmp = os.path.realpath(tempfile.mkdtemp(prefix='mesure-perso-'))
        self.home = os.path.join(self.tmp, 'home')
        self.git = shutil.which('git')
        self.depots = []
        for p in sorted(set(prefixes)):
            d = os.path.join(self.home, p + 'ESSAI')
            os.makedirs(d)
            open(os.path.join(d, 'CLAUDE.md'), 'w').write('# essai\n')
            if self.git:
                subprocess.run([self.git, 'init', '-q', d], check=True, stdout=subprocess.DEVNULL)
                subprocess.run([self.git, '-C', d, 'add', 'CLAUDE.md'], check=True)
            self.depots.append(d)
        self.n = 0

    def fermer(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def neutre(self, texte, var):
        return texte.replace(var, '<ESSAI>').replace(self.home, '<HOME>').replace(self.tmp, '<TMP>')

    def lance(self, cmd, var, cwd=None):
        env = dict(os.environ, HOME=self.home, CLAUDEOS_REG=var)
        r = subprocess.run(cmd, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        return self.neutre('rc=%d\n' % r.returncode + r.stdout.decode('utf-8', 'replace'), var)

    def sorties(self, texte):
        """Les sept sorties du moteur sous ce jeu de réponses : {nom: texte}."""
        self.n += 1
        var = os.path.join(self.tmp, 'v%d' % self.n)
        os.makedirs(var)
        open(os.path.join(var, 'REPONSES'), 'w', encoding='utf-8').write(texte)
        s = {}
        a = self.lance([sys.executable, os.path.join(L.ICI, 'appliquer-reponses.py'), '--essai', var,
                        '--reponses', os.path.join(var, 'REPONSES')], var)
        for f in ('CLAUDE.md', 'settings.overrides.json'):
            p = os.path.join(var, f)
            s[f] = open(p, encoding='utf-8').read() if os.path.exists(p) else a
        s['skills-amont.sh --liste'] = self.lance(['bash', os.path.join(L.ICI, 'skills-amont.sh'), '--liste'], var)
        cfg = os.path.join(L.ICI, 'config.sh')
        for fn in ('claudeos_ws_roots', 'claudeos_repos'):
            s[fn] = self.lance(['bash', '-c', '. "$1" && %s' % fn, '_', cfg], var)
        s['boot-check.sh'] = self.lance(['bash', os.path.join(L.ICI, 'boot-check.sh')], var)
        if self.git:
            crochet = os.path.join(L.ICI, 'hooks', 'pre-commit-alarmes.sh')
            s['crochet d\'alarmes'] = ''.join('== %s\n%s' % (os.path.basename(d), self.lance(['bash', crochet], var, cwd=d))
                                              for d in self.depots)
        shutil.rmtree(var, ignore_errors=True)
        return s


def ecarts(a, b):
    """[(sortie, lignes différentes)] entre deux jeux de sorties."""
    r = []
    for k in a:
        if a[k] != b.get(k):
            la, lb = a[k].splitlines(), b.get(k, '').splitlines()
            n = sum(max(i2 - i1, j2 - j1) for t, i1, i2, j1, j2 in
                    difflib.SequenceMatcher(None, la, lb, autojunk=False).get_opcodes() if t != 'equal')
            r.append((k, n))
    return r


def differentiel(f_base, f_contre):
    contrat, base = valeurs_de(f_base)
    _, contre = valeurs_de(f_contre)
    prefixes = ['ESSAI_']
    for v in (base, contre):
        prefixes += L.elements(v.get('PREFIXES', '')) + L.elements(v.get('PREFIXES_CLIENT', ''))
    at = Atelier(prefixes)
    try:
        s_base = at.sorties(texte_reponses(contrat, base))
        instables = [k for k, n in ecarts(s_base, at.sorties(texte_reponses(contrat, base)))]
        if instables:
            raise L.Refus('sortie instable d\'un appel à l\'autre, même jeu : %s — elle ferait diverger '
                          'toutes les clés' % ', '.join(instables))
        dit('%s contre %s : %d sorties du moteur comparées%s' % (
            os.path.basename(f_base), os.path.basename(f_contre), len(s_base),
            '' if at.git else ' — git absent : le crochet d\'alarmes n\'est pas joué'))
        glob = ecarts(s_base, at.sorties(texte_reponses(contrat, contre)))
        dit('jeu contre jeu : %d sorties sur %d diffèrent, %d lignes en tout' % (
            len(glob), len(s_base), sum(n for _, n in glob)))
        for k, n in glob:
            dit('  %-26s %d lignes' % (k, n))
        muettes, sans_objet = [], []
        ordre = [c['cle'] for c in contrat]
        for i, c in enumerate(contrat):
            k = c['cle']
            essai = None
            for alt in alternatives(c, base[k]):
                ref, compagnes = dict(base), []
                for suivante in [None] + ordre[i + 1:]:
                    if suivante is not None:
                        if ref[suivante] == contre[suivante]:
                            continue
                        ref[suivante] = contre[suivante]
                        compagnes.append(suivante)
                    v = dict(ref, **{k: alt})
                    if not L.defauts_reponses(contrat, v) and not L.defauts_reponses(contrat, ref):
                        essai = (alt, ref, v, compagnes)
                        break
                if essai:
                    break
            if essai is None:
                sans_objet.append(k)
                dit('  %-17s sans objet sous %s : le contrat refuse toute autre valeur' % (k, os.path.basename(f_base)))
                continue
            alt, ref, v, compagnes = essai
            s_ref = s_base if not compagnes else at.sorties(texte_reponses(contrat, ref))
            e = ecarts(s_ref, at.sorties(texte_reponses(contrat, v)))
            if not e and c['origine'] == 'entretien':
                muettes.append(k)
            dit('  %s %-17s %s → %s%s : %s' % (
                '✅' if e else ('⛔' if c['origine'] == 'entretien' else '·'), k, base[k] or '(vide)', alt or '(vide)',
                ' (avec %s du jeu contre)' % ', '.join(compagnes) if compagnes else '',
                ', '.join('%s %d lignes' % x for x in e) if e else 'aucune sortie ne change'))
    finally:
        at.fermer()
    if muettes:
        dit('⛔ %d clé(s) d\'entretien sans divergence sous %s : %s — la brancher sur une sortie, ou la '
            'sortir du contrat (§ 1.2)' % (len(muettes), os.path.basename(f_base), ', '.join(muettes)), err=True)
        return 1
    dit('✅ chaque clé d\'entretien mesurable change au moins une sortie du moteur (%d sans objet)' % len(sans_objet))
    return 0


# --- L'invariant ---------------------------------------------------------------------------------

def invariant():
    if not os.path.exists(PERIMETRE):
        raise L.Refus('%s absent' % PERIMETRE)
    lignes, mauvaises = [], []
    for n, l in enumerate(open(PERIMETRE, encoding='utf-8'), 1):
        l = l.strip()
        if not l or l.startswith('#'):
            continue
        g, _, cl = l.partition(' ')
        cl = cl.strip()
        if not (cl in ('nature', 'conditionnel') or re.match(r'manque:\s*\S', cl)):
            mauvaises.append('ligne %d : %r' % (n, l))
        lignes.append((g, 'manque' if cl.startswith('manque') else cl, cl))
    comptes, vides = {}, {g for g, _, _ in lignes}
    for d, sous, fichiers in os.walk(L.RACINE):
        sous[:] = [x for x in sous if x not in IGNORES]
        for f in fichiers:
            if f in IGNORES:
                continue
            rel = os.path.relpath(os.path.join(d, f), L.RACINE)
            for g, cl, _ in lignes:
                if fnmatch.fnmatch(rel, g):
                    n, o = comptes.get(cl, (0, 0))
                    comptes[cl] = (n + 1, o + os.path.getsize(os.path.join(d, f)))
                    vides.discard(g)
                    break
    for cl in ('nature', 'conditionnel', 'manque'):
        n, o = comptes.get(cl, (0, 0))
        dit('%-12s %4d fichiers, %8d octets' % (cl, n, o))
    for g, cl, brut in lignes:
        if cl == 'manque':
            dit('  manque — %s : %s' % (g, brut[len('manque:'):].strip()))
    for g in sorted(vides):
        dit('  ⚠ motif qui ne prend aucun fichier : %s' % g)
    if mauvaises:
        dit('⛔ classe invalide, ou manque sans motif : %s' % ' ; '.join(mauvaises), err=True)
        return 1
    return 0


def main(argv):
    ap = argparse.ArgumentParser(prog='mesure-personnalisation.py')
    ap.add_argument('mesure', choices=('ratio', 'taille', 'differentiel', 'invariant'))
    ap.add_argument('--reponses', metavar='FICHIER', default=JEU_MAX)
    ap.add_argument('--base', metavar='FICHIER', default=JEU_MAX)
    ap.add_argument('--contre', metavar='FICHIER', default=JEU_MIN)
    a = ap.parse_args(argv)
    try:
        if a.mesure == 'differentiel':
            return differentiel(a.base, a.contre)
        if a.mesure == 'invariant':
            return invariant()
        return (ratio if a.mesure == 'ratio' else taille)(a.reponses)
    except (L.Refus, OSError, UnicodeDecodeError, subprocess.CalledProcessError) as e:
        dit('⛔ %s' % e, err=True)
        return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
