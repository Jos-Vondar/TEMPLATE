#!/usr/bin/env python3
"""mettre-a-jour.py — un poste SANS git passe à une version neuve du template.

Écrit le 2026-10-01, plan complet de templating § 2, A8, et § 3.3. Code PROPRE AU TEMPLATE. En
régime GitHub la mise à jour est un `git merge` (`d-upgrade-git`) ; sans git, ce script en tient
lieu. Il se lance DEPUIS L'AMORCE de la version neuve, dont il prend le moteur : la version en
place ne décide pas de ce que fait la suivante. Bibliothèque standard seule, Python 3.8 au moins.

TROIS ÉTATS, comparés à l'empreinte : l'état LIVRÉ de la version en place, sous `.claudeos/livre/`
(le docstring de `regime.py` en donne la forme) ; l'arbre de la version NEUVE, l'amorce ; et le
DISQUE. Chaque chemin que l'une des deux versions livre se classe :
  remplacé    intact sur le disque, changé par la version : le neuf le remplace
  ajouté      neuf dans la version, absent du disque
  retiré      retiré par la version, intact sur le disque : supprimé
  gardé       changé sur le disque, et que la version ne touche pas : il reste, sans question
  à trancher  changé sur le disque ET par la version, sous quatre formes : modifié ; créé à un
              chemin que la version livre désormais ; supprimé ; retiré par la version alors qu'il
              a été modifié. RIEN ne s'y écrit sans une réponse de la personne.
Un fichier déjà égal au neuf n'a rien à faire. Un chemin qu'aucune des deux versions ne livre est
à la personne : jamais lu, jamais touché.

  mettre-a-jour.py <racine> <amorce>                   l'inventaire, LECTURE SEULE
  mettre-a-jour.py <racine> <amorce> --montrer CHEMIN  l'écart d'un fichier à trancher : ce que la
                    personne a changé, ce que la version change, et la fusion proposée quand les
                    deux ne se touchent pas ; les versions s'écrivent sous .claudeos/mise-a-jour/trois/
  mettre-a-jour.py <racine> <amorce> --trancher CHEMIN garder|neuf|fusion [--texte FICHIER]
                    la réponse, enregistrée. `neuf` fait ce que fait la version : remplacer,
                    reprendre ou retirer. `fusion` prend FICHIER, à défaut la fusion proposée
  mettre-a-jour.py <racine> <amorce> --appliquer       TOUT OU RIEN : refuse tant qu'un fichier
                    reste à trancher ou qu'une réponse porte sur un autre état ; sinon écrit tout,
                    puis l'état livré de la version neuve, GARDES compris

LA FUSION PROPOSÉE est une fusion à trois par lignes, depuis la copie livrée : les changements de
la personne et ceux de la version s'appliquent tous, tant qu'aucun ne touche l'autre. Deux
changements qui se recouvrent, ou qui se touchent sans ligne intacte entre eux, ne se fusionnent
pas : la fusion se compose alors à la main, et l'agent la fait valider avant de la passer par
`--texte`. Une réponse enregistrée porte l'empreinte des deux fichiers qu'elle a vus : si l'un
change ensuite, elle ne vaut plus, et `--appliquer` le dit.

Codes : 0 fait, ou lu · 1 refus nommé, rien d'écrit · 2 appel fautif ou état illisible — régime
GitHub, pas d'état livré, amorce sans version, script lancé depuis le poste.
"""
import argparse
import difflib
import hashlib
import json
import os
import re
import shutil
import sys

ICI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ICI)
import regime as R  # noqa: E402

TRAVAIL = os.path.join(R.DOSSIER, 'mise-a-jour')
CONFLIT_RE = re.compile(rb'^(<<<<<<<|>>>>>>>) ', re.M)
DIFF_MAX = 200          # lignes de différence montrées par écart ; le reste se lit dans trois/
CLASSES = ('remplacé', 'ajouté', 'retiré', 'gardé', 'à trancher')
# Les quatre formes d'un fichier à trancher, et ce que fait chaque réponse.
GENRES = {
    'modifie': ('modifié chez toi, et changé par la version',
                {'garder': 'garder le tien', 'neuf': 'prendre le neuf', 'fusion': 'fusionner les deux'}),
    'collision': ('créé chez toi, à un chemin que la version livre désormais',
                  {'garder': 'garder le tien', 'neuf': 'prendre le neuf', 'fusion': 'fusionner les deux'}),
    'supprime': ('supprimé chez toi, et changé par la version',
                 {'garder': 'le laisser supprimé', 'neuf': 'reprendre le neuf'}),
    'retire': ('modifié chez toi, et retiré par la version',
               {'garder': 'le garder : il devient à toi', 'neuf': 'le supprimer, comme la version'}),
}


class Refus(Exception):
    """Rien n'est écrit, et le défaut est nommé : code 1."""


class Appel(Exception):
    """L'appel ou l'état est fautif : code 2."""


def dit(msg):
    print('[mise-a-jour] ' + msg)


def sha_octets(b):
    return hashlib.sha256(b).hexdigest()


def sha_fichier(p):
    h = hashlib.sha256()
    with open(p, 'rb') as fh:
        for bloc in iter(lambda: fh.read(1 << 16), b''):
            h.update(bloc)
    return h.hexdigest()


def lit_octets(p):
    try:
        with open(p, 'rb') as fh:
            return fh.read()
    except FileNotFoundError:
        return None


def lit_texte(p):
    b = lit_octets(p)
    return None if b is None else b.decode('utf-8', 'replace')


def etat_disque(rac, rel):
    """L'empreinte du fichier en place ; None s'il est absent ; 'autre' si le chemin n'est pas un
    fichier ordinaire, ou qu'un de ses parents n'est pas un dossier."""
    p = os.path.join(rac, rel)
    parent = os.path.dirname(p)
    while parent != rac and len(parent) > len(rac):
        if os.path.lexists(parent) and (os.path.islink(parent) or not os.path.isdir(parent)):
            return 'autre'
        parent = os.path.dirname(parent)
    if os.path.islink(p) or (os.path.lexists(p) and not os.path.isfile(p)):
        return 'autre'
    return sha_fichier(p) if os.path.isfile(p) else None


def travail(rac, *parts):
    return os.path.join(rac, TRAVAIL, *parts)


# ----------------------------------------------------------------------------- fusion à trois
def lignes(b):
    return b.splitlines(keepends=True)


def changements(base, autre):
    """Les changements d'`autre` sur `base` : (début, fin, lignes) en lignes de la base."""
    sm = difflib.SequenceMatcher(None, base, autre, autojunk=False)
    return [(i1, i2, autre[j1:j2]) for tag, i1, i2, j1, j2 in sm.get_opcodes() if tag != 'equal']


def applique(base, debut, fin, chgts):
    sortie, k = [], debut
    for i1, i2, rep in chgts:
        sortie += base[k:i1] + rep
        k = i2
    return sortie + base[k:fin]


def fusion_a_trois(base, sien, neuf):
    """(lignes fusionnées, None) si aucun changement ne touche l'autre ; sinon (None, [(de, à)]),
    les plages de la base, numérotées depuis 1, où les deux côtés se touchent."""
    tous = sorted([c + ('sien',) for c in changements(base, sien)]
                  + [c + ('neuf',) for c in changements(base, neuf)], key=lambda c: (c[0], c[1]))
    groupes = []
    for c in tous:
        # Un changement qui commence là où finit le groupe le touche : même groupe, par prudence.
        if groupes and c[0] <= groupes[-1][1]:
            groupes[-1][1] = max(groupes[-1][1], c[1])
            groupes[-1][2].append(c)
        else:
            groupes.append([c[0], c[1], [c]])
    sortie, i, recouvrements = [], 0, []
    for debut, fin, cs in groupes:
        sortie += base[i:debut]
        par_cote = {}
        for c in cs:
            par_cote.setdefault(c[3], []).append(c[:3])
        rendus = [applique(base, debut, fin, v) for v in par_cote.values()]
        if len(rendus) == 1 or rendus[0] == rendus[1]:
            sortie += rendus[0]
        else:
            recouvrements.append((debut + 1, max(fin, debut + 1)))
        i = fin
    sortie += base[i:]
    if recouvrements:
        return None, recouvrements
    # Une ligne sans fin de ligne au milieu du fichier collerait deux lignes : pas de proposition.
    if any(not x.endswith((b'\n', b'\r')) for x in sortie[:-1]):
        return None, [(0, 0)]
    return sortie, None


def diff(a, b, de, vers):
    d = list(difflib.unified_diff([x.decode('utf-8', 'replace') for x in a],
                                  [x.decode('utf-8', 'replace') for x in b], de, vers, n=2))
    if len(d) > DIFF_MAX:
        d = d[:DIFF_MAX] + ['… %d ligne(s) de plus : les versions entières sont sous trois/\n' % (len(d) - DIFF_MAX)]
    return ''.join(x if x.endswith('\n') else x + '\n' for x in d)


# ---------------------------------------------------------------------------------- les états
class Etat:
    """Les trois états, et le classement de chaque chemin livré, lus une fois."""

    def __init__(self, rac, amorce):
        self.rac, self.amorce = rac, amorce
        try:
            self.livre = R.livre_lit(rac)
            arbre = R.livre_arbre(rac)
        except R.Refus as e:
            raise Appel(str(e))
        if not self.livre:
            raise Appel('aucun état livré sous %s : ce poste n\'a pas été posé par regime.py pose'
                        % os.path.join(rac, R.LIVRE))
        self.v_livre = (lit_texte(os.path.join(rac, R.LIVRE, 'VERSION')) or '').strip() or 'inconnue'
        self.v_neuve = (lit_texte(os.path.join(amorce, 'engine', 'VERSION')) or '').strip()
        if not self.v_neuve:
            raise Appel('l\'amorce %s ne porte pas engine/VERSION : ce n\'est pas une version du template'
                        % amorce)
        self.chemins_neufs = R.livres(amorce)
        self.neuf = {rel: sha_fichier(os.path.join(amorce, rel)) for rel in self.chemins_neufs}
        # La base de la fusion : la copie livrée, membre par membre, si elle égale le MANIFESTE.
        self.base, self.base_defaut = {}, None
        if arbre is None:
            self.base_defaut = 'la copie livrée manque (.claudeos/livre/ARBRE.tar.gz)'
        else:
            for rel, h in self.livre.items():
                if rel in arbre and sha_octets(arbre[rel]) == h:
                    self.base[rel] = arbre[rel]
            if len(self.base) < len(self.livre):
                self.base_defaut = '%d fichier(s) de la copie livrée diffèrent du MANIFESTE' % (
                    len(self.livre) - len(self.base))
        self.classes, self.genres, self.disque, self.bloques, self.inchanges = {}, {}, {}, [], 0
        for rel in sorted(set(self.livre) | set(self.neuf)):
            l, n = self.livre.get(rel), self.neuf.get(rel)
            d = etat_disque(rac, rel)
            self.disque[rel] = d
            if d == 'autre':
                self.bloques.append(rel)
            elif d == n:
                self.inchanges += 1
            elif l is None:
                self._classe(rel, 'ajouté' if d is None else 'collision')
            elif n is None:
                self._classe(rel, 'retiré' if d == l else 'retire')
            elif d == l:
                self._classe(rel, 'remplacé')
            elif n == l:
                self._classe(rel, 'gardé')
            else:
                self._classe(rel, 'supprime' if d is None else 'modifie')
        self.decisions, self.perimees = self._decisions()

    def _classe(self, rel, c):
        if c in GENRES:
            self.classes[rel], self.genres[rel] = 'à trancher', c
        else:
            self.classes[rel] = c

    def _decisions(self):
        p = travail(self.rac, 'DECISIONS')
        if not os.path.exists(p):
            return {}, None
        try:
            with open(p, encoding='utf-8') as fh:
                d = json.load(fh)
        except (OSError, ValueError) as e:
            raise Appel('réponses enregistrées illisibles : %s (%s)' % (p, e))
        if d.get('version') != self.v_neuve:
            return {}, d.get('version') or 'inconnue'
        return d.get('decisions') or {}, None

    def a_trancher(self):
        return [rel for rel, c in self.classes.items() if c == 'à trancher']

    def tenue(self, rel):
        """La réponse enregistrée, si elle porte sur l'état présent ou qu'elle est déjà écrite."""
        dec = self.decisions.get(rel)
        if dec and dec.get('neuf') == self.neuf.get(rel) and self.disque[rel] in (dec.get('sien'), dec.get('resultat')):
            return dec
        return None

    def chemin(self, brut):
        """Un chemin donné par l'appel, rendu relatif à la racine."""
        p = os.path.realpath(brut) if os.path.isabs(brut) else None
        rel = os.path.relpath(p, self.rac) if p else os.path.normpath(brut)
        rel = rel.replace(os.sep, '/')
        if rel.startswith('../') or rel == '..':
            raise Appel('%s n\'est pas sous la racine %s' % (brut, self.rac))
        return rel

    def genre(self, rel):
        if rel in self.bloques:
            raise Refus('%s n\'est pas un fichier ordinaire : range-le, puis relance' % rel)
        if self.classes.get(rel) != 'à trancher':
            raise Refus('%s n\'est pas à trancher (%s)' % (
                rel, self.classes.get(rel) or 'inchangé, ou livré par aucune des deux versions'))
        return self.genres[rel]

    def trois(self, rel):
        """(base, sien, neuf) en octets ; None pour ce qui n'existe pas ou ne se sait pas."""
        return (self.base.get(rel), lit_octets(os.path.join(self.rac, rel)),
                lit_octets(os.path.join(self.amorce, rel)))

    def proposee(self, rel):
        """(lignes, None) quand la fusion se fait seule ; (None, motif) sinon ; (None, None) quand
        la fusion n'est pas une réponse possible."""
        if self.genres.get(rel) == 'collision':
            return None, 'aucune version livrée de ce chemin, donc aucune base : la fusion se compose à la main'
        if self.genres.get(rel) != 'modifie':
            return None, None
        base, sien, neuf = self.trois(rel)
        if base is None:
            return None, 'la copie livrée de ce fichier manque : la fusion se compose à la main'
        if any(b'\0' in x[:8000] for x in (base, sien, neuf)):
            return None, 'fichier binaire : pas de fusion par lignes'
        fus, rec = fusion_a_trois(lignes(base), lignes(sien), lignes(neuf))
        if fus is None:
            if rec == [(0, 0)]:
                return None, 'une ligne sans fin de ligne au milieu : la fusion se compose à la main'
            return None, 'les deux changements se touchent, ligne(s) %s de la version livrée' % ', '.join(
                '%d' % a if a == b else '%d à %d' % (a, b) for a, b in rec)
        return fus, None


# ------------------------------------------------------------------------------ les commandes
def inventaire(e):
    dit('version en place %s → version neuve %s · sans git' % (e.v_livre, e.v_neuve))
    if e.base_defaut:
        dit('⚠ %s : un écart se montre contre le neuf seul, et aucune fusion n\'est proposée' % e.base_defaut)
    if e.perimees:
        dit('⚠ des réponses enregistrées visaient la version %s : elles ne valent pas pour %s, à reprendre'
            % (e.perimees, e.v_neuve))
    for c in CLASSES:
        for rel in sorted(r for r, x in e.classes.items() if x == c):
            note = ''
            if c == 'gardé':
                note = ' — %s, inchangé par la version : le tien reste' % (
                    'supprimé chez toi' if e.disque[rel] is None else 'modifié chez toi')
            elif c == 'à trancher':
                note = ' — %s' % GENRES[e.genres[rel]][0]
                dec = e.tenue(rel)
                if dec:
                    note += ' · tranché : %s' % dec['choix']
                elif rel in e.decisions:
                    note += ' · la réponse enregistrée portait sur un autre état : à reprendre'
                elif e.proposee(rel)[0] is not None:
                    note += ' · fusion proposée'
            print('  %-11s %s%s' % (c, rel, note))
    for rel in e.bloques:
        print('  %-11s %s — ce chemin n\'est pas un fichier ordinaire : range-le, puis relance' % ('bloqué', rel))
    compte = ' · '.join('%d %s' % (sum(1 for x in e.classes.values() if x == c), c) for c in CLASSES)
    dit('%s · %d inchangé(s)%s' % (compte, e.inchanges, ' · %d bloqué(s)' % len(e.bloques) if e.bloques else ''))
    reste = [rel for rel in e.a_trancher() if not e.tenue(rel)]
    # Un fichier gardé reste gardé à chaque passe : il ne fait pas, à lui seul, une mise à jour.
    actifs = [rel for rel, c in e.classes.items() if c != 'gardé']
    if e.bloques:
        dit('Rien ne s\'applique tant qu\'un chemin est bloqué.')
    elif reste:
        dit('Reste à trancher : %d. Pour chacun : --montrer CHEMIN, puis --trancher CHEMIN garder|neuf|fusion.'
            % len(reste))
    elif not actifs and e.v_neuve == e.v_livre:
        dit('Déjà à jour : rien à écrire.')
    elif not actifs:
        dit('Rien à écrire. --appliquer réécrit l\'état livré à la version %s.' % e.v_neuve)
    else:
        dit('Tout est tranché : --appliquer écrit la version.')
    return 0


def montre(e, rel):
    g = e.genre(rel)
    base, sien, neuf = e.trois(rel)
    dit('%s — %s' % (rel, GENRES[g][0]))
    for choix, sens in GENRES[g][1].items():
        print('  %-7s %s' % (choix, sens))
    dossier = travail(e.rac, 'trois')
    for suffixe, b in (('livre', base), ('sien', sien), ('neuf', neuf)):
        p = os.path.join(dossier, rel + '.' + suffixe)
        if b is not None:
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, 'wb') as fh:
                fh.write(b)
    texte = all(x is None or b'\0' not in x[:8000] for x in (base, sien, neuf))
    if not texte:
        dit('fichier binaire : l\'écart ne se montre pas en lignes')
    elif base is not None:
        if sien is not None:
            print('--- ce que tu as changé (livré %s → chez toi)' % e.v_livre)
            print(diff(lignes(base), lignes(sien), 'livré', 'chez toi'), end='')
        else:
            print('--- ce que tu as changé : tu l\'as supprimé')
        if neuf is not None:
            print('--- ce que la version change (livré %s → %s)' % (e.v_livre, e.v_neuve))
            print(diff(lignes(base), lignes(neuf), 'livré', e.v_neuve), end='')
        else:
            print('--- ce que la version change : elle le retire')
    elif sien is not None and neuf is not None:
        print('--- chez toi → %s (sans copie livrée : l\'écart entier, tes changements et ceux de la version mêlés)' % e.v_neuve)
        print(diff(lignes(sien), lignes(neuf), 'chez toi', e.v_neuve), end='')
    fus, motif = e.proposee(rel)
    if fus is not None:
        p = os.path.join(dossier, rel + '.proposee')
        with open(p, 'wb') as fh:
            fh.write(b''.join(fus))
        dit('fusion proposée, sans recouvrement : %s — `--trancher %s fusion` la prend telle quelle'
            % (os.path.relpath(p, e.rac), rel))
    elif motif:
        dit('aucune fusion proposée : %s' % motif)
    dit('les versions, pour une fusion : %s/%s.{livre,sien,neuf}' % (os.path.relpath(dossier, e.rac), rel))
    return 0


def tranche(e, rel, choix, texte):
    g = e.genre(rel)
    if choix not in GENRES[g][1]:
        raise Refus('%s : « %s » ne se répond pas à un fichier %s ; réponses : %s'
                    % (rel, choix, GENRES[g][0], ', '.join(GENRES[g][1])))
    if texte is not None and choix != 'fusion':
        raise Appel('--texte ne va qu\'avec fusion')
    disque, neuf = e.disque[rel], e.neuf.get(rel)
    resultat = {'garder': disque, 'neuf': neuf}.get(choix)
    if choix == 'fusion':
        if texte is not None:
            contenu = lit_octets(texte)
            if contenu is None:
                raise Appel('--texte : %s introuvable' % texte)
        else:
            fus, motif = e.proposee(rel)
            if fus is None:
                raise Refus('%s : aucune fusion proposée (%s). Compose-la, fais-la valider, puis '
                            '--trancher %s fusion --texte FICHIER' % (rel, motif, rel))
            contenu = b''.join(fus)
        if CONFLIT_RE.search(contenu):
            raise Refus('%s : la fusion porte encore des marqueurs de conflit' % rel)
        p = travail(e.rac, 'fusion', rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p + '.neuf', 'wb') as fh:
            fh.write(contenu)
        os.replace(p + '.neuf', p)
        resultat = sha_octets(contenu)
    e.decisions[rel] = {'choix': choix, 'sien': disque, 'neuf': neuf, 'resultat': resultat}
    p = travail(e.rac, 'DECISIONS')
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p + '.neuf', 'w', encoding='utf-8') as fh:
        json.dump({'version': e.v_neuve, 'decisions': e.decisions}, fh, ensure_ascii=False, indent=1,
                  sort_keys=True)
    os.replace(p + '.neuf', p)
    dit('réponse enregistrée : %s → %s (%s)' % (rel, choix, GENRES[g][1][choix]))
    reste = [r for r in e.a_trancher() if r != rel and not e.tenue(r)]
    dit('reste à trancher : %d%s' % (len(reste), '' if reste else ' — --appliquer écrit la version'))
    return 0


def applique_tout(e):
    if e.bloques:
        raise Refus('chemin(s) qui ne sont pas des fichiers ordinaires : %s. Range-les, puis relance. '
                    'Rien n\'a été écrit.' % ', '.join(e.bloques))
    manquent, perimees = [], []
    for rel in e.a_trancher():
        if e.tenue(rel):
            continue
        (perimees if rel in e.decisions else manquent).append(rel)
    if manquent or perimees:
        msg = []
        if manquent:
            msg.append('%d fichier(s) sans réponse : %s' % (len(manquent), ', '.join(manquent)))
        if perimees:
            msg.append('%d réponse(s) portant sur un autre état, le fichier ou la version ayant changé depuis : %s'
                       % (len(perimees), ', '.join(perimees)))
        raise Refus(' · '.join(msg) + '. Rien n\'a été écrit.')
    fusions = {}
    for rel in e.a_trancher():
        dec = e.tenue(rel)
        if dec['choix'] == 'fusion' and e.disque[rel] != dec['resultat']:
            contenu = lit_octets(travail(e.rac, 'fusion', rel))
            if contenu is None or sha_octets(contenu) != dec['resultat']:
                raise Refus('%s : la fusion enregistrée manque ou a changé ; tranche-le de nouveau. '
                            'Rien n\'a été écrit.' % rel)
            fusions[rel] = contenu
    # Tout est contrôlé : on écrit. Chaque fichier s'écrit à côté, puis se renomme.
    tmp = travail(e.rac, 'tmp')
    os.makedirs(tmp, exist_ok=True)
    ecrits, retires = [], []

    def pose(rel, contenu=None):
        dst, t = os.path.join(e.rac, rel), os.path.join(tmp, 'f')
        src = os.path.join(e.amorce, rel)
        if contenu is None:
            shutil.copy2(src, t)
        else:
            with open(t, 'wb') as fh:
                fh.write(contenu)
            shutil.copymode(src if os.path.exists(src) else dst, t)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        os.replace(t, dst)
        ecrits.append(rel)

    def retire(rel):
        os.remove(os.path.join(e.rac, rel))
        retires.append(rel)
        d = os.path.dirname(os.path.join(e.rac, rel))
        while len(d) > len(e.rac) and os.path.isdir(d) and not os.listdir(d):
            os.rmdir(d)
            d = os.path.dirname(d)

    for rel, c in sorted(e.classes.items()):
        if c in ('remplacé', 'ajouté'):
            pose(rel)
        elif c == 'retiré':
            retire(rel)
        elif c == 'à trancher':
            dec = e.tenue(rel)
            if e.disque[rel] == dec['resultat']:
                continue                                  # déjà écrite, par une passe coupée
            if dec['choix'] == 'fusion':
                pose(rel, fusions[rel])
            elif dec['choix'] == 'neuf':
                if e.neuf.get(rel) is None:
                    retire(rel)
                else:
                    pose(rel)
    # L'état livré devient celui de la version neuve. GARDES nomme chaque fichier qu'elle livre et
    # que le disque porte autrement, par choix ou parce que la version ne le touchait pas.
    gardes = {}
    for rel, n in e.neuf.items():
        d = etat_disque(e.rac, rel)
        if d != n:
            gardes[rel] = d or 'absent'
    R.ecrit_livre(e.rac, e.amorce, e.chemins_neufs, e.neuf, e.v_neuve, gardes)
    shutil.rmtree(travail(e.rac))
    dit('version %s écrite : %d fichier(s) écrit(s), %d retiré(s), %d écart(s) gardé(s) ; état livré réécrit'
        % (e.v_neuve, len(ecrits), len(retires), len(gardes)))
    dit('Suite : METTRE_A_JOUR.md § 3 — les réglages, le proxy, une clé neuve, appliquer-reponses.py, '
        'skills-amont.sh, install-poste.sh, puis verifier.py mise-a-jour --version %s.' % e.v_neuve)
    return 0


def main(argv):
    ap = argparse.ArgumentParser(prog='mettre-a-jour.py', description=__doc__.split('\n')[0])
    ap.add_argument('racine')
    ap.add_argument('amorce')
    g = ap.add_mutually_exclusive_group()
    g.add_argument('--montrer', metavar='CHEMIN')
    g.add_argument('--trancher', nargs=2, metavar=('CHEMIN', 'CHOIX'))
    g.add_argument('--appliquer', action='store_true')
    ap.add_argument('--texte', metavar='FICHIER')
    a = ap.parse_args(argv)          # une erreur d'argument sort en 2, comme le veut le contrat
    rac, amorce = os.path.realpath(a.racine), os.path.realpath(a.amorce)
    if not os.path.isdir(rac):
        raise Appel('racine introuvable : %s' % a.racine)
    if not os.path.isdir(amorce):
        raise Appel('amorce introuvable : %s' % a.amorce)
    if rac == amorce:
        raise Appel('l\'amorce et la racine sont le même dossier')
    if os.path.realpath(ICI).startswith(rac + os.sep):
        raise Appel('lancé depuis le poste : lance-le depuis l\'amorce de la version neuve, '
                    'python3 %s/engine/mettre-a-jour.py %s %s' % (amorce, rac, amorce))
    if os.path.exists(os.path.join(rac, '.git')):
        raise Appel('%s porte un dépôt git : en régime GitHub, la mise à jour est un git merge '
                    '(METTRE_A_JOUR.md § 2)' % rac)
    if not R.sans_git(rac):
        raise Appel('%s ne porte pas .claudeos-racine : install-poste.sh la pose' % rac)
    if a.texte is not None and not a.trancher:
        raise Appel('--texte ne va qu\'avec --trancher')
    e = Etat(rac, amorce)
    if a.montrer:
        return montre(e, e.chemin(a.montrer))
    if a.trancher:
        return tranche(e, e.chemin(a.trancher[0]), a.trancher[1], a.texte)
    if a.appliquer:
        return applique_tout(e)
    return inventaire(e)


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1:]))
    except Refus as ex:
        print('[mise-a-jour] ⛔ %s' % ex, file=sys.stderr)
        sys.exit(1)
    except Appel as ex:
        print('[mise-a-jour] ⛔ %s' % ex, file=sys.stderr)
        sys.exit(2)
    except OSError as ex:
        print('[mise-a-jour] ⛔ lecture ou écriture interrompue : %s. Relance la même commande : ce '
              'qui est déjà écrit est reconnu, et l\'état livré ne change qu\'en dernier.' % ex, file=sys.stderr)
        sys.exit(2)
