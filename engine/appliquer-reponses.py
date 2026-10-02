#!/usr/bin/env python3
"""appliquer-reponses.py — le bloc d'imports du CLAUDE.md et les skillOverrides, écrits depuis les réponses.

Écrit le 2026-10-01, plan complet de templating § 1.3, A4 (`d-reglement-imports`). Code PROPRE AU
TEMPLATE ; il remplace `assemble-rules.sh` de v2.2.0, qui réécrivait le règlement entier.

IL N'ÉCRIT QUE DEUX CHOSES. Dans `CLAUDE.md`, les lignes entre les deux marqueurs CLAUDEOS IMPORTS :
le reste du fichier appartient à l'installateur — persona, domaines, « Mes règles » — et ressort
octet pour octet tel qu'il est entré. Dans `settings.json`, les trois entrées de `skillOverrides`
que les réponses gouvernent (`lib_reponses.MASQUES`), par une fusion JSON qui laisse le reste intact.
Tout est contrôlé AVANT la première écriture : un défaut n'écrit rien, nulle part.

Usage :
  appliquer-reponses.py                    écrit CLAUDE.md et settings.json du système
  appliquer-reponses.py --essai DOSSIER    écrit DOSSIER/CLAUDE.md et DOSSIER/settings.overrides.json,
                                           et rien d'autre ; part de DOSSIER/CLAUDE.md s'il existe,
                                           sinon de gabarits/CLAUDE.md
  appliquer-reponses.py --verifier [--essai DOSSIER]
                                           n'écrit rien ; rend 1 si le bloc ou les skillOverrides
                                           diffèrent de ce que les réponses imposent, si un fichier
                                           cité manque, si un marqueur manque ou est doublé, si une
                                           clé manque ou sort du contrat
  --reponses FICHIER                       au lieu de reglages/REPONSES

Codes : 0 conforme, ou écrit ; 1 le POSTE n'est pas conforme, défaut nommé, rien n'est écrit ;
2 l'APPEL ou le TEMPLATE est fautif — argument, contrat illisible, socle absent, fragment orphelin.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib_reponses as L  # noqa: E402


def dit(msg, err=False):
    print('[réponses] ' + msg, file=sys.stderr if err else sys.stdout)


def lit_texte(chemin):
    try:
        return open(chemin, encoding='utf-8', newline='').read(), None
    except FileNotFoundError:
        return None, 'absent'
    except (OSError, UnicodeDecodeError) as e:
        return None, 'illisible (%s)' % e


def main(argv):
    ap = argparse.ArgumentParser(prog='appliquer-reponses.py', add_help=True)
    ap.add_argument('--essai', metavar='DOSSIER')
    ap.add_argument('--verifier', action='store_true')
    ap.add_argument('--reponses', metavar='FICHIER')
    a = ap.parse_args(argv)          # une erreur d'argument sort en 2, comme le veut le contrat

    try:
        contrat = L.lit_contrat()
        orph = L.orphelins(contrat)
        if orph:
            raise L.Refus('fragment orphelin, qu\'aucune clé ni valeur du contrat ne nomme, donc jamais '
                          'importé : ' + ', '.join(orph))
    except L.Refus as e:
        dit('⛔ template : %s' % e, err=True)
        return 2

    f_rep = a.reponses or os.path.join(L.reglages(), 'REPONSES')
    valeurs, defauts = L.lit_reponses(f_rep)
    if valeurs is not None:
        defauts += L.defauts_reponses(contrat, valeurs)
    attendu = masques = None
    if not defauts:
        try:
            attendu = L.bloc_attendu(L.fragments_retenus(contrat, valeurs), valeurs)
        except L.Refus as e:
            dit('⛔ template : %s' % e, err=True)
            return 2
        masques = L.masques_attendus(valeurs)

    if a.essai:
        md = os.path.join(a.essai, 'CLAUDE.md')
        source = md if (a.verifier or os.path.exists(md)) else L.GABARIT
        js = os.path.join(a.essai, 'settings.overrides.json')
    else:
        md = source = os.path.join(L.RACINE, 'CLAUDE.md')
        js = os.path.join(L.RACINE, 'settings.json')

    texte, err = lit_texte(source)
    if texte is None:
        defauts.append('%s %s%s' % (source, err, '' if a.essai else
                                    ' — la plomberie le pose depuis gabarits/CLAUDE.md'))
    courant = None
    if texte is not None:
        try:
            courant = L.bloc_courant(texte)
        except ValueError as e:
            defauts.append('%s : %s' % (source, e))
    objet, err = L.lit_reglages_json(js)
    if err:
        defauts.append(err)

    if a.verifier:
        if courant is not None:
            for l in courant:
                if l.startswith('@'):
                    cite = l[1:].split()[0] if l[1:].split() else ''
                    # RTK.md est posé sur le poste par l'outil rtk, pas par le template : un essai
                    # ne peut pas le trouver dans le template, il n'y est contrôlé qu'en vrai.
                    if cite == 'RTK.md' and a.essai:
                        continue
                    if not cite or not os.path.isfile(os.path.join(L.RACINE, cite)):
                        defauts.append('fichier cité par le bloc, absent : %s' % (cite or l))
            if attendu is not None:
                defauts += L.ecarts_bloc(courant, attendu)
        if objet is not None and masques is not None:
            defauts += L.ecarts_masques(objet.get('skillOverrides', {}), masques)
        if defauts:
            dit('⛔ %d défaut(s) — %s :' % (len(defauts), md), err=True)
            for d in defauts:
                print('    - ' + d, file=sys.stderr)
            return 1
        dit('✅ conforme — bloc de %d import(s), skillOverrides à jour (%s)' % (len(attendu), md))
        return 0

    if defauts:
        dit('⛔ rien n\'est écrit, %d défaut(s) :' % len(defauts), err=True)
        for d in defauts:
            print('    - ' + d, file=sys.stderr)
        return 1

    neuf_md = L.avec_bloc(texte, attendu)
    if a.essai:
        neuf_js = {'skillOverrides': {s: 'off' for s, m in masques.items() if m}}
        os.makedirs(a.essai, exist_ok=True)
        L.ecrit_atomique(md, neuf_md)
        L.ecrit_atomique(js, json.dumps(neuf_js, ensure_ascii=False, indent=2) + '\n')
        etat_md, etat_js = 'écrit', 'écrit'
    else:
        neuf_js = L.avec_masques(objet, masques)
        etat_md = etat_js = 'inchangé'
        if neuf_md != texte:
            L.ecrit_atomique(md, neuf_md)
            etat_md = 'bloc réécrit'
        if neuf_js != objet:
            L.ecrit_atomique(js, json.dumps(neuf_js, ensure_ascii=False, indent=2) + '\n')
            etat_js = 'skillOverrides fusionnés'
    if not a.essai:
        absents = [l[1:] for l in attendu if not os.path.isfile(os.path.join(L.RACINE, l[1:]))]
        if absents:
            dit('⚠ bloc écrit, mais il cite un fichier absent du poste : %s — --verifier le refusera'
                % ', '.join(absents), err=True)
    noms = [l.lstrip('@').split('/')[-1] for l in attendu]
    dit('bloc : %d import(s) — %s' % (len(attendu), ', '.join(n[:-3] if n.endswith('.md') else n for n in noms)))
    caches = sorted(s for s, m in masques.items() if m)
    dit('skillOverrides : %s' % ('masquées : ' + ', '.join(caches) if caches else 'aucune compétence masquée'))
    dit('%s : %s ; %s : %s' % (md, etat_md, js, etat_js))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
