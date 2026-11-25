#!/usr/bin/env python3
"""Dit si une CRÉATION ou une DESTRUCTION de fichier relevée par `rappel-fichiers-nommage.sh` est
exemptée du refus unique de `fichiers-et-nommage`. SEUL JUGE de l'exemption.

Les règles de la fiche — le nommage, `_IGNORE/`, les pointeurs — ne portent ni sur un fichier
jetable ni sur un ajout à un registre : les refuser là apprendrait à ignorer le refus.

DEUX EXEMPTIONS, ET RIEN D'AUTRE, jugées cible par cible — une seule cible hors exemption suffit
à refuser :
  1. toute cible sous une ZONE JETABLE : `/tmp`, `/var/folders` (`/private` devant ou non), ou le
     scratchpad de session où qu'il soit ;
  2. un ajout `>>` à un fichier régulier qui existe déjà (ajouter n'est pas nommer).
Juger la commande entière ne suffit pas : dès qu'un `/tmp/` y figure, un chemin durable voisin
passerait avec lui (`rm -rf <scratchpad>/banc <chemin durable>`). Les cas attendus vivent dans
`engine/tests/harnais-refus-unique.py`.

Pièges fermés, chacun éprouvé au harnais : une accolade (`{a,/chemin}`) rend la cible illisible ;
une variable se résout À L'INSTANT du geste, pas avec sa dernière valeur ; un `cd` dans une
sous-coquille `( … )` ne survit pas à sa parenthèse. Reste lexical : un lien symbolique posé dans
une zone jetable et pointant au-dehors n'est pas suivi.

CONTRAT DE SORTIE. 0 : exemptée. Tout autre code veut dire « pas exemptée », erreur de lecture
comprise. Une commande illisible, une variable qu'on ne sait pas résoudre, une cible absente :
pas d'exemption, le refus se prononce comme avant (`controles-et-alarmes`, aucune conclusion sur
une branche d'erreur).

Lit la commande BRUTE et non la surface de `surface-commande.py`, qui efface les chaînes citées,
donc les chemins entre guillemets. Les corps de heredoc sont retirés d'abord : ce qui est donnée
n'est pas geste.

Arguments : <outil> <commande ou chemin> [<scratchpad_dir de l'entrée du crochet>] [<cwd>]
"""
import os
import re
import shlex
import sys

JETABLE_RE = re.compile(r'^(/private)?/(tmp|var/folders)/')
HEREDOC = re.compile(r'<<-?[ \t]*(["\']?)([A-Za-z_][A-Za-z0-9_]*)\1')
SEP = {';', '&&', '||', '|', '&', '\n', '(', ')'}
REDIR = {'>', '>>', '>|', '&>', '&>>'}
ASSIGN = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)=(.*)$', re.S)


def sans_heredoc(c):
    out, lignes, i = [], c.split('\n'), 0
    while i < len(lignes):
        ligne = lignes[i]
        out.append(ligne)
        fins = [m.group(2) for m in HEREDOC.finditer(ligne)]
        i += 1
        for fin in fins:
            while i < len(lignes) and lignes[i].strip() != fin:
                i += 1
            i += 1
    return '\n'.join(out)


def dans_scratch(p, scratch):
    """Vrai si `p` est sous une zone jetable (voir l'en-tête), jugé après normalisation des `..`."""
    p = os.path.normpath(p)
    if JETABLE_RE.match(p):
        return True
    if scratch:
        s = os.path.normpath(scratch)
        for a, b in ((p, s), (os.path.realpath(p), os.path.realpath(s))):
            if a == b or a.startswith(b + os.sep):
                return True
    return False


def resout(tok, var):
    if tok.startswith('~'):
        tok = os.path.expanduser(tok)

    def sub(m):
        n = m.group(1) or m.group(2)
        if n in var:
            return var[n]
        if n in os.environ:
            return os.environ[n]
        raise KeyError(n)
    tok = re.sub(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)', sub, tok)
    # Une accolade s'étend en chemins quelconques (`{banc,/ailleurs}`) : illisible. Un joker
    # `* ? [` reste DANS son dossier, donc il se juge par le préfixe normalisé.
    if '$' in tok or '`' in tok or '{' in tok or '}' in tok:
        raise KeyError(tok)
    return tok


DESTR = ('rm', 'rmdir', 'shred', 'unlink', 'mv')


def cibles(cmd, cwd=''):
    """Liste de (chemin, mode) ; mode 'w' écrase ou crée, 'a' ajoute, 'd' détruit (rm, rmdir,
    shred, unlink, source d'un mv). None si illisible. Un chemin relatif se résout contre le
    dernier `cd` de la commande, sinon contre `cwd` (dossier courant de l'entrée du crochet) ;
    sans l'un ni l'autre il reste relatif, donc hors scratchpad, donc pas exempté.
    La commande BRUTE est lue, pas la surface : un chemin cité entre guillemets, relatif ou porté
    par une variable (`B=<scratchpad>/banc; rm -rf "$B"`) se juge comme les autres."""
    lex = shlex.shlex(sans_heredoc(cmd).replace("\n", " ; "), posix=True, punctuation_chars=';&|()<>')
    lex.whitespace_split = True
    lex.whitespace = ' \t'
    toks = list(lex)
    out, var, seg = [], {}, []
    ici = [cwd]
    pile = []  # dossier courant à l'entrée de chaque sous-coquille `(`

    def ajoute(cible, mode):
        # Résolue MAINTENANT : `B=/durable; rm "$B"; B=<scratchpad>` vise /durable.
        out.append((resout_safe(cible, var), mode, ici[0]))

    def ferme(seg):
        mots, i = [], 0
        while i < len(seg):
            t = seg[i]
            if t in REDIR or t in {'>>&'}:
                if i + 1 >= len(seg):
                    return False
                cible = seg[i + 1]
                if not cible.startswith('/dev/') and not cible.isdigit() and cible != '-':
                    ajoute(cible, 'a' if t in {'>>', '&>>'} else 'w')
                i += 2
                continue
            if t in {'>&', '<', '<<', '<<<', '<&'}:
                i += 2
                continue
            mots.append(t)
            i += 1
        while mots and ASSIGN.match(mots[0]):
            n, v = ASSIGN.match(mots[0]).groups()
            try:
                var[n] = resout(v, var)
            except KeyError:
                var[n] = '$' + n  # non résoluble : toute cible qui l'emploie le sera aussi
            mots = mots[1:]
        if mots and mots[0] == 'sudo':
            mots = mots[1:]
        if not mots:
            return True
        nom = os.path.basename(mots[0])
        args = [m for m in mots[1:] if not m.startswith('-')]
        # Un destructeur en position d'argument (`xargs rm`, `git rm`, `find … -exec rm`) a des
        # cibles qu'on ne lit pas : la commande entière devient illisible, donc pas d'exemption.
        if nom not in DESTR and any(os.path.basename(m) in DESTR for m in mots[1:]):
            return False
        if nom == 'cd':
            d = resout_safe(args[0], var) if args else os.path.expanduser('~')
            if d is None:
                ici[0] = ''
            else:
                ici[0] = os.path.normpath(os.path.join(ici[0], d)) if ici[0] or os.path.isabs(d) else ''
        elif nom in ('mkdir', 'touch', 'tee'):
            for a in args:
                ajoute(a, 'w')
        elif nom in ('cp', 'install'):
            if args:
                ajoute(args[-1], 'w')
        elif nom == 'mv':
            if len(args) < 2:
                return False
            for a in args[:-1]:
                ajoute(a, 'd')
            ajoute(args[-1], 'w')
        elif nom in DESTR:
            if not args:
                return False
            for a in args:
                ajoute(a, 'd')
        return True

    for t in toks + ['\n']:
        if t in SEP or set(t) <= set(';&|()') and t:
            if not ferme(seg):
                return None
            seg = []
            for ch in t:
                if ch == '(':
                    pile.append(ici[0])
                elif ch == ')':
                    if not pile:
                        return None
                    ici[0] = pile.pop()
        else:
            seg.append(t)
    res = []
    for p, m, base in out:
        if p is not None and not os.path.isabs(p):
            p = os.path.normpath(os.path.join(base, p)) if base else None
        res.append((p, m))
    return res


def resout_safe(c, var):
    try:
        return resout(c, var)
    except KeyError:
        return None


def main():
    if len(sys.argv) < 3:
        return 2
    outil, cmd = sys.argv[1], sys.argv[2]
    scratch = sys.argv[3] if len(sys.argv) > 3 else ''
    cwd = sys.argv[4] if len(sys.argv) > 4 else ''
    if outil in ('Write', 'NotebookEdit'):
        return 0 if cmd and dans_scratch(os.path.expanduser(cmd), scratch) else 1
    if outil != 'Bash':
        return 1
    try:
        cs = cibles(cmd, cwd)
    except (ValueError, KeyError):
        return 1
    if not cs:
        return 1
    for chemin, mode in cs:
        if chemin is None:
            return 1
        if dans_scratch(chemin, scratch):
            continue
        if mode == 'a' and os.path.isfile(chemin):
            continue
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
