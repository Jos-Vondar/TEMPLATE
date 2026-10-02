#!/usr/bin/env python3
"""lib_reponses.py — le contrat des réponses, et ce qu'elles font du règlement.

Écrit le 2026-10-01, plan complet de templating § 1.2 et § 1.3, A4. Code PROPRE AU TEMPLATE.
Une seule implémentation du choix des fragments, lue par `appliquer-reponses.py`, qui écrit le
bloc d'imports, et par `mesure-personnalisation.py`, qui le mesure : deux copies de ce choix
finiraient par diverger, et la mesure porterait alors sur un autre règlement que celui qui est écrit.

Trois sources, chacune à un seul endroit :
- le contrat des clés, `engine/config/REPONSES_CLES` : leur ordre, leur type, leurs valeurs ;
- les réponses du poste, `reglages/REPONSES` (`CLAUDEOS_REG` déplace le dossier, comme pour
  `config.sh`), lues comme `claudeos_reponse` les lit : la clé avant le premier `=`, comparée
  exactement, la valeur telle quelle — un `oui ` traînant d'une espace n'est pas `oui` ;
- les fragments, `noyau/regles/` : `socle.md`, plus un `<cle>-<valeur>.md` par valeur qui porte
  des règles, la clé en minuscules et `_` devenu `-`.
Python 3.8 au moins : le `python3` de macOS est l'un des interprètes visés.
"""
import json
import os

ICI = os.path.dirname(os.path.abspath(__file__))
RACINE = os.path.dirname(ICI)
CONTRAT = os.path.join(ICI, 'config', 'REPONSES_CLES')
REGLES = os.path.join(RACINE, 'noyau', 'regles')
GABARIT = os.path.join(RACINE, 'gabarits', 'CLAUDE.md')
SOCLE = 'socle.md'

DEBUT = '<!-- CLAUDEOS IMPORTS : DEBUT'
FIN = '<!-- CLAUDEOS IMPORTS : FIN'

# Les compétences que les réponses masquent par `skillOverrides` (§ 1.2) : clé, valeur qui masque,
# compétence. Masquée, elle vaut "off" ; visible, son entrée est RETIRÉE, une compétence absente de
# `skillOverrides` valant "on" (vérifié le 2026-10-01, doc skills, « Override skill visibility from
# settings »). Ces trois entrées appartiennent aux réponses : une valeur posée à la main y est
# réécrite. Les autres entrées de `skillOverrides` ne sont jamais touchées.
MASQUES = (('LIVRABLE', 'non', 'livrables'),
           ('PROXY', 'non', 'rtk-depannage'),
           ('GIT', 'aucun', 'pousser-son-dossier'))


class Refus(Exception):
    """Le template ou l'appel est fautif — contrat illisible, socle absent, fragment orphelin : code 2."""


def reglages():
    return os.environ.get('CLAUDEOS_REG') or os.path.join(RACINE, 'reglages')


def elements(valeur):
    """Les éléments d'une réponse à virgules, comme `claudeos_liste` : espaces rognés, vides écartés."""
    return [e.strip() for e in valeur.split(',') if e.strip()]


def lit_contrat(chemin=CONTRAT):
    try:
        lignes = open(chemin, encoding='utf-8').read().splitlines()
    except (OSError, UnicodeDecodeError) as e:
        raise Refus('contrat des réponses illisible : %s (%s)' % (chemin, e))
    cles = []
    for n, l in enumerate(lignes, 1):
        if not l.strip() or l.lstrip().startswith('#'):
            continue
        c = l.split()
        if (len(c) != 4 or c[1] not in ('entretien', 'machine')
                or c[2] not in ('choix', 'liste', 'libre') or (c[3] == '-') != (c[2] == 'libre')):
            raise Refus('contrat des réponses, ligne %d illisible : %r' % (n, l))
        cles.append({'cle': c[0], 'origine': c[1], 'type': c[2],
                     'valeurs': [] if c[3] == '-' else c[3].split(',')})
    if not cles:
        raise Refus('contrat des réponses vide : %s' % chemin)
    return cles


def lit_reponses(chemin):
    """Rend (valeurs, défauts). `valeurs` vaut None si le fichier ne se lit pas."""
    try:
        lignes = open(chemin, encoding='utf-8').read().split('\n')
    except FileNotFoundError:
        return None, ['réponses absentes : %s — le poste n\'est pas réglé' % chemin]
    except (OSError, UnicodeDecodeError) as e:
        return None, ['réponses illisibles : %s (%s)' % (chemin, e)]
    valeurs, defauts = {}, []
    for n, l in enumerate(lignes, 1):
        if not l.strip() or l.startswith('#'):
            continue
        if '=' not in l:
            defauts.append('réponses, ligne %d sans « = » : %r' % (n, l))
            continue
        k, v = l.split('=', 1)
        if k in valeurs:
            defauts.append('clé %s écrite deux fois (ligne %d) : le moteur ne lit que la première' % (k, n))
            continue
        valeurs[k] = v
    return valeurs, defauts


def defauts_reponses(contrat, valeurs):
    """Ce qui écarte les réponses du contrat : clé absente, inconnue, valeur hors contrat, contradiction."""
    d = []
    connues = [c['cle'] for c in contrat]
    d += ['clé inconnue du contrat : %r' % k for k in valeurs if k not in connues]
    for c in contrat:
        k = c['cle']
        if k not in valeurs:
            d.append('clé absente : %s' % k)
        elif c['type'] == 'choix' and valeurs[k] not in c['valeurs']:
            d.append('%s=%r hors du contrat : attendu %s' % (k, valeurs[k], ' | '.join(c['valeurs'])))
        elif c['type'] == 'liste':
            hors = [e for e in elements(valeurs[k]) if e not in c['valeurs']]
            if hors:
                d.append('%s : %s hors de %s' % (k, ', '.join(hors), ','.join(c['valeurs'])))
    # Les contradictions du § 1.2 : sans git, aucun second poste ni dépôt de travail ; en dépôt
    # unique, aucun dépôt de travail non plus.
    git = valeurs.get('GIT')
    if git == 'aucun' and valeurs.get('MULTIPOSTE') == 'oui':
        d.append('MULTIPOSTE=oui impossible avec GIT=aucun : rien ne synchronise deux postes sans dépôt')
    if git in ('unique', 'aucun'):
        d += ['%s doit être vide avec GIT=%s : aucun dépôt de travail' % (k, git)
              for k in ('PREFIXES', 'PREFIXES_CLIENT') if elements(valeurs.get(k, ''))]
    prefixes = elements(valeurs.get('PREFIXES', ''))
    hors = [e for e in elements(valeurs.get('PREFIXES_CLIENT', '')) if e not in prefixes]
    if hors:
        d.append('PREFIXES_CLIENT : %s absent de PREFIXES' % ', '.join(hors))
    return d


def nom_fragment(cle, valeur):
    return '%s-%s.md' % (cle.lower().replace('_', '-'), valeur)


def orphelins(contrat, dossier=REGLES):
    """Un fragment qu'aucune clé ni valeur du contrat ne nomme ne serait jamais importé, sans un mot."""
    possibles = {SOCLE} | {nom_fragment(c['cle'], v) for c in contrat for v in c['valeurs']}
    try:
        presents = sorted(f for f in os.listdir(dossier) if f.endswith('.md'))
    except OSError as e:
        raise Refus('fragments illisibles : %s (%s)' % (dossier, e))
    return [f for f in presents if f not in possibles]


def fragments_retenus(contrat, valeurs, dossier=REGLES):
    """Le socle, puis un fragment par valeur qui en porte un, dans l'ordre du contrat."""
    if not os.path.isfile(os.path.join(dossier, SOCLE)):
        raise Refus('socle absent : %s' % os.path.join(dossier, SOCLE))
    retenus = [SOCLE]
    for c in contrat:
        v = valeurs.get(c['cle'], '')
        if c['type'] == 'choix':
            choisies = [v]
        elif c['type'] == 'liste':
            choisies = [e for e in c['valeurs'] if e in elements(v)]
        else:
            choisies = []
        retenus += [nom_fragment(c['cle'], x) for x in choisies
                    if os.path.isfile(os.path.join(dossier, nom_fragment(c['cle'], x)))]
    return retenus


def bloc_attendu(retenus, valeurs):
    """Les lignes du bloc : un import par fragment, puis `RTK.md` si le poste porte le proxy (§ 1.3)."""
    lignes = ['@noyau/regles/' + f for f in retenus]
    if valeurs.get('PROXY') == 'oui':
        lignes.append('@RTK.md')
    return lignes


def masques_attendus(valeurs):
    """{compétence: True si les réponses la masquent}, pour les seules compétences de MASQUES."""
    return {s: valeurs.get(k) == v for k, v, s in MASQUES}


def localise_bloc(lignes):
    """(i, j), index des deux lignes de marqueur ; ValueError qui nomme le défaut sinon."""
    deb = [i for i, l in enumerate(lignes) if l.strip().startswith(DEBUT)]
    fin = [i for i, l in enumerate(lignes) if l.strip().startswith(FIN)]
    for nom, trouves in (('DEBUT', deb), ('FIN', fin)):
        if len(trouves) != 1:
            raise ValueError('marqueur %s du bloc d\'imports %s' % (
                nom, 'absent' if not trouves else 'présent %d fois' % len(trouves)))
    if fin[0] < deb[0]:
        raise ValueError('marqueur FIN du bloc d\'imports avant le marqueur DEBUT')
    return deb[0], fin[0]


def bloc_courant(texte):
    lignes = texte.splitlines(keepends=True)
    i, j = localise_bloc(lignes)
    return [l.rstrip('\r\n') for l in lignes[i + 1:j]]


def avec_bloc(texte, attendu):
    """Le texte, son bloc remplacé : hors des marqueurs, rien ne change, octet pour octet."""
    lignes = texte.splitlines(keepends=True)
    i, j = localise_bloc(lignes)
    nl = '\r\n' if lignes[i].endswith('\r\n') else '\n'
    return ''.join(lignes[:i + 1] + [l + nl for l in attendu] + lignes[j:])


def ecarts_bloc(courant, attendu):
    """Ce qui sépare le bloc écrit de celui que les réponses imposent, en clair."""
    if courant == attendu:
        return []
    manque = [l for l in attendu if l not in courant]
    trop = [l for l in courant if l not in attendu]
    d = []
    if manque:
        d.append('bloc d\'imports : il manque ' + ', '.join(manque))
    if trop:
        d.append('bloc d\'imports : en trop ' + ', '.join(repr(l) for l in trop))
    if not d:
        d.append('bloc d\'imports : les bonnes lignes, dans un autre ordre ou en double')
    return d


def lit_reglages_json(chemin):
    """(objet, défaut) : un fichier absent vaut {}, un fichier illisible rend un défaut nommé."""
    try:
        texte = open(chemin, encoding='utf-8').read()
    except FileNotFoundError:
        return {}, None
    except (OSError, UnicodeDecodeError) as e:
        return None, '%s illisible (%s)' % (chemin, e)
    try:
        objet = json.loads(texte)
    except ValueError as e:
        return None, '%s n\'est pas du JSON valide (%s)' % (chemin, e)
    if not isinstance(objet, dict):
        return None, '%s : un objet JSON est attendu' % chemin
    if not isinstance(objet.get('skillOverrides', {}), dict):
        return None, '%s : skillOverrides doit être un objet' % chemin
    return objet, None


def avec_masques(objet, masques):
    """Une copie de l'objet où seules les entrées gouvernées de `skillOverrides` ont changé."""
    neuf = json.loads(json.dumps(objet))
    so = dict(neuf.get('skillOverrides', {}))
    for s, masque in masques.items():
        if masque:
            so[s] = 'off'
        else:
            so.pop(s, None)
    if so or 'skillOverrides' in neuf:
        neuf['skillOverrides'] = so
    return neuf


def ecarts_masques(so, masques):
    d = []
    for s, masque in masques.items():
        if masque and so.get(s) != 'off':
            d.append('skillOverrides : %s doit valoir "off" (%s)' % (
                s, 'absente' if s not in so else 'vaut %s' % json.dumps(so[s])))
        elif not masque and s in so:
            d.append('skillOverrides : %s ne doit pas y figurer, les réponses la veulent visible (vaut %s)'
                     % (s, json.dumps(so[s])))
    return d


def ecrit_atomique(chemin, texte):
    """Écrit à côté puis remplace : jamais de fichier à moitié écrit. Un lien est suivi, pas remplacé."""
    cible = os.path.realpath(chemin)
    neuf = cible + '.neuf'
    with open(neuf, 'w', encoding='utf-8', newline='') as f:
        f.write(texte)
    if os.path.exists(cible):
        os.chmod(neuf, os.stat(cible).st_mode & 0o7777)
    os.replace(neuf, cible)
