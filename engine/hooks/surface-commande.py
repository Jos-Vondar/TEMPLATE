#!/usr/bin/env python3
"""Rend la SURFACE d'une commande shell : le geste, sans la donnée.

Sorti de `rappel-fichiers-nommage.sh` le 2026-09-22, et c'est la RAISON du fichier séparé.
Le programme y vivait dans une chaîne bash entre guillemets doubles alors qu'il contient
lui-même des guillemets doubles : bash refermait la chaîne au milieu, python recevait un
programme tronqué (`SyntaxError: '(' was never closed`), un `2>/dev/null` avalait l'erreur,
et le repli reprenait la commande BRUTE. Le nettoyage n'a donc jamais tourné depuis sa pose
du 2026-09-16. Un heredoc quoté réglait l'échappement mais bash 3.2 — celui que macOS livre —
refuse un heredoc dans une substitution de commande. Un fichier à part n'a aucun des deux
problèmes : rien n'est interprété deux fois.

Ce qu'il retire, et pourquoi : un motif lancé sur la commande entière tombe sur les documents
en ligne et les chaînes citées. Trois faux positifs mesurés — une variable Python nommée `mv`,
un `mv a b` cité dans le TEXTE d'un événement, et un message de commit qui NOMMAIT
`--no-verify`. Ce qui est donnée n'est pas geste.

LECTURE CARACTÈRE PAR CARACTÈRE DEPUIS LE 2026-10-01, et c'est le défaut inverse des trois
faux positifs : un FAUX NÉGATIF sur un garde BLOQUANT. Les chaînes citées s'effaçaient par une
expression, `'[^']*'`, qui ignorait les commentaires shell. Une APOSTROPHE dans un commentaire —
`# mise en place d'un essai`, et en français il y en a partout — ouvrait une fausse chaîne
jusqu'à l'apostrophe suivante, et tout ce qui se trouvait entre les deux sortait de la surface :
reproduit sur le crochet installé, un `git commit --no-verify` précédé d'un tel commentaire
passait le refus, un `rm -rf` perdait son rappel. Même défaut pour un `<<EOF` cité dans un
commentaire, pris pour un heredoc. Le parcours ci-dessous sait où il est — code, chaîne simple,
chaîne double, `$'…'`, commentaire, corps de heredoc — et n'efface que ce qui est donnée.
Un `#` ne commente qu'en DÉBUT DE MOT, comme dans le shell : `${#tab}` et `a#b` restent du code.

Sort en 0 avec la surface sur stdout ; tout autre code veut dire « je n'ai pas su lire »,
et l'appelant ne doit alors prononcer aucun refus.
"""
import re
import sys

_META = set(' \t\n;&|()<>')
_HEREDOC = re.compile(r'<<(-?)[ \t]*(["\']?)([A-Za-z_][A-Za-z0-9_]*)\2')


def surface(c: str) -> str:
    out = []
    i, n = 0, len(c)
    debut_mot = True   # un `#` ne commente qu'en début de mot
    attente = []       # heredocs ouverts sur la ligne en cours : (marqueur, tabulations retirées)
    while i < n:
        ch = c[i]
        if ch == '\n':
            out.append(ch)
            i += 1
            debut_mot = True
            for marq, tabs in attente:   # corps des heredocs, dans l'ordre d'ouverture
                while i < n:
                    j = c.find('\n', i)
                    fin = n if j < 0 else j
                    ligne = c[i:fin]
                    saut = '\n' if j >= 0 else ''
                    i = fin + 1 if j >= 0 else n
                    if (ligne.lstrip('\t') if tabs else ligne).strip() == marq:
                        out.append(ligne + saut)
                        break
                    out.append(' ' * len(ligne) + saut)
            attente = []
            continue
        if ch == '\\' and i + 1 < n:
            out.append(c[i:i + 2])
            i += 2
            debut_mot = False
            continue
        if ch == "'":
            if i > 0 and c[i - 1] == '$':   # $'…' : les échappements y comptent
                j = i + 1
                while j < n and c[j] != "'":
                    j += 2 if c[j] == '\\' else 1
            else:
                j = c.find("'", i + 1)
                if j < 0:
                    j = n
            out.append(" '' ")
            i = j + 1
            debut_mot = False
            continue
        if ch == '"':
            j = i + 1
            while j < n and c[j] != '"':
                j += 2 if c[j] == '\\' else 1
            out.append(' "" ')
            i = j + 1
            debut_mot = False
            continue
        if ch == '#' and debut_mot:
            j = c.find('\n', i)
            if j < 0:
                j = n
            out.append(' ' * (j - i))
            i = j
            continue
        if c.startswith('<<<', i):   # here-string : pas un heredoc
            out.append('<<<')
            i += 3
            debut_mot = True
            continue
        if c.startswith('<<', i):
            m = _HEREDOC.match(c, i)
            if m:
                attente.append((m.group(3), m.group(1) == '-'))
                out.append(m.group(0))
                i = m.end()
                debut_mot = False
                continue
        out.append(ch)
        i += 1
        debut_mot = ch in _META
    return ''.join(out)


if __name__ == "__main__":
    print(surface(sys.argv[1] if len(sys.argv) > 1 else ""))
