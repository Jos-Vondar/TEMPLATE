#!/usr/bin/env python3
"""fusionner-reglages.py — le fragment de réglages du template, fusionné dans settings.json.

Écrit le 2026-10-01, plan complet de templating § 1.1 et A6, geste 7. Code PROPRE AU TEMPLATE ; il
reprend la fusion par `python3` d'`install.sh` v2.2.0 (l. 635-701), sans son crochet de sauvegarde en
fin de session, que la V3 n'a pas (`d-sauvegarde-cloture-seule`).

`settings.json` appartient à l'installateur et à Claude Code, qui l'écrit aussi. CE SCRIPT N'Y TOUCHE
QUE CE QUE LE TEMPLATE POSSÈDE, et tout le reste ressort tel qu'il est entré :
- les crochets dont la commande vise `/.claude/engine/` : ce sont ceux du template, retirés puis
  reposés depuis `gabarits/settings.fragment.json`. Une version qui change ou retire un crochet le
  change ou le retire donc ici, et deux passes ne font jamais de doublon ;
- le crochet `rtk hook claude`, ajouté s'il manque quand `reglages/REPONSES` porte `PROXY=oui`, et
  jamais retiré : `rtk` l'a peut-être posé lui-même (`rtk init -g`) ;
- `autoMemoryDirectory`, posé s'il manque. S'il vaut AUTRE CHOSE, rien n'est écrit : la mémoire de
  ClaudeOS vit sous `~/.claude/memory`, et déplacer celle de quelqu'un se décide avec lui ;
- `spinnerTipsOverride`, posé s'il manque, mis au fragment s'il porte déjà le `tipsFile` de ClaudeOS,
  laissé tel quel s'il est à toi — dit, sans défaut.
Les `skillOverrides` ne sont pas d'ici : `appliquer-reponses.py` les écrit depuis les réponses.

Usage :
  fusionner-reglages.py                    fusionne dans ~/.claude/settings.json (lien suivi)
  fusionner-reglages.py --essai DOSSIER    écrit DOSSIER/settings.json, et rien d'autre
  fusionner-reglages.py --verifier [--essai DOSSIER]
                                           n'écrit rien ; rend 1 et nomme ce qui manque, est en double
                                           ou périmé
  --reponses FICHIER                       au lieu de reglages/REPONSES

Codes : 0 conforme, ou écrit ; 1 le POSTE n'est pas conforme, défaut nommé, rien n'est écrit ;
2 l'APPEL ou le TEMPLATE est fautif — argument, fragment illisible.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib_reponses as L  # noqa: E402

FRAGMENT = os.path.join(L.RACINE, 'gabarits', 'settings.fragment.json')
MOTEUR = '/.claude/engine/'
RTK = 'rtk hook claude'


def dit(msg, err=False):
    print('[réglages] ' + msg, file=sys.stderr if err else sys.stdout)


def meme_dossier(a, b):
    """Deux écritures d'un chemin désignent-elles le même dossier ? `~` développé, liens résolus."""
    if not isinstance(a, str) or not isinstance(b, str):
        return a == b
    return os.path.realpath(os.path.expanduser(a)) == os.path.realpath(os.path.expanduser(b))


def commandes(groupe):
    return [h.get('command', '') for h in groupe.get('hooks', []) if isinstance(h, dict)]


def du_template(cmd):
    return MOTEUR in cmd


def deja_poses(hooks, fragment):
    """True si chaque groupe du template est là, une fois, tel que le fragment le porte, et qu'aucun
    autre crochet du moteur ne traîne — y compris mêlé à un groupe de l'utilisateur."""
    attendus = {evt: [json.dumps(g, sort_keys=True) for g in gs] for evt, gs in fragment.get('hooks', {}).items()}
    for evt in set(hooks) | set(attendus):
        trouves = []
        for g in hooks.get(evt, []) if isinstance(hooks.get(evt, []), list) else []:
            if not isinstance(g, dict):
                continue
            cmds = commandes(g)
            if any(du_template(c) for c in cmds):
                if not all(du_template(c) for c in cmds):
                    return False
                trouves.append(json.dumps(g, sort_keys=True))
        if sorted(trouves) != sorted(attendus.get(evt, [])) or len(set(trouves)) != len(trouves):
            return False
    return True


def lit_fragment():
    try:
        f = json.load(open(FRAGMENT, encoding='utf-8'))
    except (OSError, ValueError) as e:
        raise L.Refus('fragment illisible : %s (%s)' % (FRAGMENT, e))
    if not isinstance(f, dict) or not isinstance(f.get('hooks', {}), dict):
        raise L.Refus('fragment mal formé : %s' % FRAGMENT)
    return f


def fusion(objet, fragment, proxy):
    """L'objet fusionné, et les remarques qui ne sont pas des défauts. ValueError nomme un refus."""
    neuf = json.loads(json.dumps(objet))
    remarques = []
    # 1. Les crochets du template : retirés partout, puis reposés depuis le fragment — SAUF quand ils
    #    sont déjà exactement ceux du fragment, groupes à part et à leur place : on n'y touche alors
    #    pas, et une seconde passe ne déplace rien (la première passe réordonnait un groupe à elle).
    hooks = neuf.get('hooks', {})
    if not isinstance(hooks, dict):
        raise ValueError('settings.json : hooks doit être un objet')
    if deja_poses(hooks, fragment):
        hooks = None
    for evt in list(hooks or {}):
        groupes = []
        for g in hooks[evt] if isinstance(hooks[evt], list) else []:
            if not isinstance(g, dict):
                groupes.append(g)
                continue
            garde = [h for h in g.get('hooks', []) if not (isinstance(h, dict) and du_template(h.get('command', '')))]
            if garde:
                g = dict(g, hooks=garde)
                groupes.append(g)
            elif not g.get('hooks'):
                groupes.append(g)
        if groupes:
            hooks[evt] = groupes
        else:
            del hooks[evt]
    if hooks is None:
        hooks = neuf.get('hooks', {})
    else:
        for evt, groupes in fragment.get('hooks', {}).items():
            hooks.setdefault(evt, [])
            hooks[evt] += json.loads(json.dumps(groupes))
    # 2. rtk, si le poste porte le proxy : ajouté s'il manque, jamais retiré.
    if proxy:
        deja = any(RTK == c.strip() for gs in hooks.values() if isinstance(gs, list)
                   for g in gs if isinstance(g, dict) for c in commandes(g))
        if not deja:
            for evt, groupes in fragment.get('_si_proxy', {}).get('hooks', {}).items():
                hooks.setdefault(evt, [])
                hooks[evt] += json.loads(json.dumps(groupes))
    if hooks:
        neuf['hooks'] = hooks
    # 3. La mémoire automatique. Deux écritures du MÊME dossier ne sont pas un écart : `~/…` contre
    # le chemin absolu, ou à travers un lien (audit de la v3.0.0, une plomberie bloquée pour rien).
    voulu = fragment.get('autoMemoryDirectory')
    actuel = neuf.get('autoMemoryDirectory')
    if voulu and actuel is None:
        neuf['autoMemoryDirectory'] = voulu
    elif voulu and not meme_dossier(actuel, voulu):
        raise ValueError('autoMemoryDirectory vaut %r, ClaudeOS attend %r : la mémoire de ClaudeOS vit là. '
                         'Rien n\'est écrit — déplacer une mémoire se décide avec la personne.' % (actuel, voulu))
    # 4. Les astuces.
    tips = fragment.get('spinnerTipsOverride')
    if tips:
        en_place = neuf.get('spinnerTipsOverride')
        if en_place is None:
            neuf['spinnerTipsOverride'] = tips
        elif isinstance(en_place, dict) and en_place.get('tipsFile') == tips.get('tipsFile'):
            neuf['spinnerTipsOverride'] = dict(en_place, **tips)
        else:
            remarques.append('spinnerTipsOverride est déjà réglé, et pas par ClaudeOS : laissé tel quel, '
                             'les astuces de ClaudeOS ne défileront pas')
    return neuf, remarques


def ecarts(objet, fragment, proxy):
    """Ce qui sépare settings.json de la fusion, en clair ; [] s'il est conforme."""
    d = []
    hooks = objet.get('hooks', {}) if isinstance(objet.get('hooks', {}), dict) else {}
    present = {}
    for evt, gs in hooks.items():
        for g in gs if isinstance(gs, list) else []:
            if isinstance(g, dict):
                for c in commandes(g):
                    if du_template(c):
                        present.setdefault((evt, c), 0)
                        present[(evt, c)] += 1
    attendus = {(evt, c) for evt, gs in fragment.get('hooks', {}).items() for g in gs for c in commandes(g)}
    for evt, c in sorted(attendus):
        n = present.get((evt, c), 0)
        if n == 0:
            d.append('crochet %s absent : %s' % (evt, c))
        elif n > 1:
            d.append('crochet %s en %d exemplaires : %s' % (evt, n, c))
    for evt, c in sorted(set(present) - attendus):
        d.append('crochet %s du moteur périmé, que le fragment ne porte plus : %s' % (evt, c))
    if proxy and not any(RTK == c.strip() for gs in hooks.values() if isinstance(gs, list)
                         for g in gs if isinstance(g, dict) for c in commandes(g)):
        d.append('PROXY=oui et aucun crochet « %s »' % RTK)
    voulu = fragment.get('autoMemoryDirectory')
    if voulu and not meme_dossier(objet.get('autoMemoryDirectory'), voulu):
        d.append('autoMemoryDirectory vaut %r, ClaudeOS attend %r' % (objet.get('autoMemoryDirectory'), voulu))
    return d


def main(argv):
    ap = argparse.ArgumentParser(prog='fusionner-reglages.py')
    ap.add_argument('--essai', metavar='DOSSIER')
    ap.add_argument('--verifier', action='store_true')
    ap.add_argument('--reponses', metavar='FICHIER')
    a = ap.parse_args(argv)
    try:
        fragment = lit_fragment()
    except L.Refus as e:
        dit('⛔ template : %s' % e, err=True)
        return 2
    f_rep = a.reponses or os.path.join(L.reglages(), 'REPONSES')
    valeurs, defauts = L.lit_reponses(f_rep)
    proxy = (valeurs or {}).get('PROXY')
    if proxy not in ('oui', 'non'):
        dit('⛔ PROXY inconnu dans %s (%r) : la plomberie l\'écrit avant la fusion, le crochet rtk en dépend.'
            % (f_rep, proxy), err=True)
        return 1
    proxy = proxy == 'oui'
    cible = os.path.join(a.essai, 'settings.json') if a.essai else os.path.join(L.RACINE, 'settings.json')
    objet, err = L.lit_reglages_json(cible)
    if err:
        dit('⛔ %s — rien n\'est écrit.' % err, err=True)
        return 1
    if a.verifier:
        d = ecarts(objet, fragment, proxy)
        if d:
            dit('⛔ %d défaut(s) — %s :' % (len(d), cible), err=True)
            for x in d:
                print('    - ' + x, file=sys.stderr)
            return 1
        try:
            _, remarques = fusion(objet, fragment, proxy)
        except ValueError:
            remarques = []
        for x in remarques:
            dit('⚠ ' + x)
        dit('✅ conforme — %s' % cible)
        return 0
    try:
        neuf, remarques = fusion(objet, fragment, proxy)
    except ValueError as e:
        dit('⛔ %s' % e, err=True)
        return 1
    for x in remarques:
        dit('⚠ ' + x)
    if neuf == objet:
        dit('%s : inchangé, déjà conforme' % cible)
        return 0
    if a.essai:
        os.makedirs(a.essai, exist_ok=True)
    L.ecrit_atomique(cible, json.dumps(neuf, ensure_ascii=False, indent=2) + '\n')
    dit('%s : fragment fusionné — crochets du moteur reposés%s, mémoire sous %s'
        % (cible, ', crochet rtk' if proxy else '', neuf.get('autoMemoryDirectory')))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
