#!/usr/bin/env python3
"""Harnais du refus unique de `rappel-fichiers-nommage.sh` — cas attendus, rejoués sans rien exécuter.

Le crochet ne s'éprouve que sur ses cas positifs ET sur ses pièges (`controles-et-alarmes`).
À rejouer après toute retouche du crochet ou de `creation-exemptee.py`, et sur chaque poste.

Usage : python3 harnais-refus-unique.py [<dossier des scripts du crochet>] [<préfixe de cas> ...]
  Sans dossier : `engine/hooks/`, voisin du dossier de ce fichier. Donner une COPIE corrigée
  pour l'éprouver avant de l'installer.
  Code retour : 0 si tous les cas sont conformes, 1 sinon.

ISOLATION. Les marqueurs `refus-*` vont dans un cache temporaire (XDG_CACHE_HOME), jamais dans
~/.cache/claudeos. Aucune commande simulée n'est exécutée : le crochet ne fait que la lire. Les
chemins visés n'ont pas besoin d'exister, sauf ceux des cas « existant », pris dans ~/.claude
installé. Les cas d'annexe lisent les annexes de `fichiers-et-nommage`, `memoire-et-verite` et
`reprise` sous ~/.claude/skills/ : le crochet n'exige pas une annexe absente du disque, et ces cas
sortent alors en KO, obtenu PASSE ou refus de la seule fiche.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import uuid

ICI = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'hooks')
HOME = os.path.expanduser('~')
S = '/private/tmp/claude-%d/harnais/harnais/scratchpad' % os.getuid()   # forme d'un scratchpad
DOC = HOME + '/Documents'
FN, MV = 'REFUS:fichiers-et-nommage', 'REFUS:memoire-et-verite'
ETAT = 'python3 ~/.claude/engine/etat.py'


def B(cmd, cwd=DOC, **k):
    return dict(tool_name='Bash', tool_input={'command': cmd}, cwd=cwd, **k)


def W(p, **k):
    return dict(tool_name='Write', tool_input={'file_path': p, 'content': 'x'}, cwd=DOC, **k)


def ED(p):
    return dict(tool_name='Edit', tool_input={'file_path': p, 'old_string': 'a', 'new_string': 'b'}, cwd=DOC)


def NB(p):
    return dict(tool_name='NotebookEdit', tool_input={'notebook_path': p, 'new_source': 'x'}, cwd=DOC)


def SK(nom):
    return dict(hook_event_name='PostToolUse', tool_name='Skill', tool_input={'skill': nom})


def LU(fiche, annexe):   # lecture d'une annexe par l'outil Read (PostToolUse, matcher Read)
    return dict(hook_event_name='PostToolUse', tool_name='Read',
                tool_input={'file_path': HOME + '/.claude/skills/%s/%s.md' % (fiche, annexe)})


FNA, MVA = 'REFUS:fichiers-et-nommage/SUPPRIMER_DEPLACER.md', 'REFUS:memoire-et-verite/SOURCES_DE_VERITE.md'
CLO, FER = 'REFUS:reprise/CLOTURE_PRINCIPALE.md', 'REFUS:reprise/FERMETURE_PROJET.md'
CLOTURE_CMD = 'bash ~/.claude/engine/claudeos-cloture.sh'
FERME = ('''if [ -n "${TMUX_PANE:-}" ]; then S=$(tmux display-message -p -t "$TMUX_PANE" '#S') && tmux run-shell -b "sleep 5; tmux kill-session -t =$S"
else echo "hors tmux"; fi''')
NV = 'REFUS:--no-verify'


# (nom, entrée, attendu) — attendu : PASSE | REFUS:<fiche> | RAPPEL:<fiche>
CAS = [
    # --- 1. aide d'etat.py
    ('aide-1 add --help', B(ETAT + ' add --help'), 'PASSE'),
    ('aide-2 add -h', B(ETAT + ' add -h'), 'PASSE'),
    ('aide-3 add sans aide', B(ETAT + ' add --type decision --id d-x "texte"'), MV),
    ('aide-4 --help-x', B(ETAT + ' add --help-x'), MV),
    ('aide-5 --help cité', B(ETAT + ' add --id d-x "voir --help"'), MV),
    ('aide-6 deux segments', B(ETAT + ' add --help; ' + ETAT + ' add --id d-x "t"'), MV),
    ('aide-7 aide en aval', B(ETAT + ' add --id d-x "t" | grep --help'), MV),
    ('aide-8 commentaire', B(ETAT + ' add --id d-x "t" # --help'), MV),
    ('aide-9 --help dans $( )', B(ETAT + ' add --id d-x $(echo t --help )'), MV),
    ('aide-10 continuation (côté sûr)', B(ETAT + ' add --id d-x \\\n  --help'), MV),
    ('aide-11 echo --help', B('echo --help ; ' + ETAT + ' add --id d-x t'), MV),
    # --- 2. Write et NotebookEdit
    ('write-1 existant', W(HOME + '/.claude/README.md'), 'PASSE'),
    ('write-2 neuf hors zone', W(DOC + '/neuf-harnais.md'), FN),
    ('write-3 neuf scratchpad', W(S + '/neuf.md'), 'PASSE'),
    ('write-4 CLAUDE.md existant', W(HOME + '/.claude/CLAUDE.md'), MV),
    ('write-5 dossier existant', W(HOME + '/.claude/engine'), 'PASSE'),
    ('write-6 faux préfixe', W(HOME + '/scratchpad/neuf.md'), FN),
    ('write-7 traversée', W(S + '/../../../../../..' + DOC + '/neuf-harnais.md'), FN),
    ('write-8 faux scratchpad', W(HOME + '/tmp/claude-501/a/b/scratchpad/neuf.md'), FN),
    ('write-9 neuf /tmp', W('/tmp/neuf-harnais.md'), 'PASSE'),
    ('write-10 NotebookEdit existant', NB(HOME + '/.claude/README.md'), 'PASSE'),
    ('write-11 NotebookEdit neuf hors zone', NB(DOC + '/neuf-harnais.ipynb'), FN),
    # --- 3. destruction et déplacement
    ('rm-1 scratchpad absolu', B('rm -rf %s/banc' % S), 'PASSE'),
    ('rm-2 scratchpad cité', B('rm -rf "%s/banc"' % S), 'PASSE'),
    ('rm-3 B=…; rm "$B"', B('B=%s/banc; rm -rf "$B"' % S), 'PASSE'),
    ('rm-4 relatif, cwd scratchpad', B('rm -rf banc', cwd=S), 'PASSE'),
    ('rm-5 cd scratchpad && rm', B('cd "%s" && rm -rf banc' % S), 'PASSE'),
    ('rm-6 hors zone', B('rm %s/vrai-fichier.txt' % DOC), FN),
    ('rm-7 hors zone, tilde', B('rm ~/Documents/vrai-fichier.txt'), FN),
    ('rm-8 ../.. relatif sort de /tmp', B('rm ../../../../../..%s/vrai-fichier' % DOC, cwd=S), FN),
    ('rm-9 traversée absolue', B('rm -rf %s/../../../../../..%s/vrai-fichier' % (S, DOC)), FN),
    ('rm-10 faux préfixe', B('rm -rf %s/scratchpad/vrai' % HOME), FN),
    ('rm-11 voisin /tmp', B('rm -rf %s-x/vrai' % S), 'PASSE'),
    ('rm-12 mixte absolu', B('rm -rf %s/banc %s/vrai-fichier' % (S, DOC)), FN),
    ('rm-13 mixte tilde', B('rm -rf %s/banc ~/Documents/vrai-fichier' % S), FN),
    ('rm-14 deux segments', B('rm -rf %s/banc; rm %s/vrai-fichier' % (S, DOC)), FN),
    ('rm-15 accolades tilde', B('rm -rf {banc,~/Documents/vrai-fichier}', cwd=S), FN),
    ('rm-16 accolades absolu', B('rm -rf {banc,%s/vrai-fichier}' % DOC, cwd=S), FN),
    ('rm-17 variable réaffectée', B('B=%s/vrai; rm -rf "$B"; B=%s/banc' % (DOC, S)), FN),
    ('rm-18 cd en sous-coquille', B('(cd %s); rm -rf vrai-dossier' % S, cwd=DOC), FN),
    ('rm-19 mv zone -> durable', B('mv %s/a %s/b' % (S, DOC)), FN),
    ('rm-20 mv durable -> zone', B('mv %s/a %s/b' % (DOC, S)), FN),
    ('rm-21 $(…) illisible', B('rm -rf %s/banc $(cat liste)' % S), FN),
    ('rm-22 joker dans la zone', B('rm -rf %s/banc/*' % S), 'PASSE'),
    ('rm-23 xargs rm (angle mort connu)', B('ls %s | xargs rm' % DOC), 'PASSE'),
    ('rm-24 git rm', B('git rm vrai-fichier', cwd=DOC), FN),
    ('rm-25 cd .. remonte', B('cd %s && cd ../../../../.. && rm -rf Users/x' % S), FN),
    ('rm-26 rm dans .claude', B('rm %s/.claude/vrai' % HOME), FN),
    ('rm-27 /tmp lui-même', B('rm -rf /tmp'), FN),
    ('rm-28 /var/folders', B('rm -rf /var/folders/xy/T/essai'), 'PASSE'),
    ('rm-29 sous-coquille rendue', B('(cd %s && rm -rf banc)' % S, cwd=DOC), 'PASSE'),
    # --- 4. contrôles : toute retouche du moteur charge controles-et-alarmes
    ('ctrl-1 Edit etat.py', ED(HOME + '/.claude/engine/etat.py'), 'REFUS:controles-et-alarmes'),
    ('ctrl-2 Edit crochet', ED(HOME + '/.claude/engine/hooks/x.sh'), 'REFUS:controles-et-alarmes'),
    ('ctrl-3 Edit hors moteur', ED(HOME + '/.claude/README.md'), 'PASSE'),
    ('ctrl-4 Edit SKILL.md', ED(HOME + '/.claude/skills/session/SKILL.md'), 'PASSE'),
    ('sess-1 lancer un agent', dict(tool_name='Agent', tool_input={'prompt': 'x'}, cwd=DOC), 'REFUS:session'),
    ('sess-2 agent, session chargée', dict(tool_name='Agent', tool_input={'prompt': 'x'}, cwd=DOC,
        avant=[SK('session')]), 'PASSE'),
    # --- 5. mécanique du refus unique
    ('meca-1 sous-agent', B('rm %s/vrai-fichier.txt' % DOC, agent_id='a1'), 'RAPPEL:fichiers-et-nommage'),
    ('meca-2 fiche chargée', W(DOC + '/neuf-harnais.md', avant=[SK('fichiers-et-nommage')]), 'PASSE'),
    ('meca-3 session sans identifiant', B('rm %s/vrai-fichier.txt' % DOC, session_id=''), 'RAPPEL:fichiers-et-nommage'),
    # --- 6. marqueurs de charge
    ('marq-1 /nom tapé', W(DOC + '/neuf-harnais.md', avant=[dict(hook_event_name='UserPromptExpansion',
        expansion_type='slash_command', command_name='fichiers-et-nommage')]), 'PASSE'),
    ('marq-2 préfixe de greffon', W(DOC + '/neuf-harnais.md', avant=[SK('x:fichiers-et-nommage')]), 'PASSE'),
    ('marq-3 compaction efface', B('rm %s/vrai-fichier.txt' % DOC, avant=[SK('fichiers-et-nommage'),
        dict(hook_event_name='SessionStart', source='compact')]), FN),
    ('marq-4 chargée par un sous-agent', B('rm %s/vrai-fichier.txt' % DOC,
        avant=[dict(SK('fichiers-et-nommage'), agent_id='a1')]), FN),
    ('marq-5 autre fiche chargée', B('rm %s/vrai-fichier.txt' % DOC, avant=[SK('session')]), FN),
    # --- 7. annexes gardées : un refus unique par annexe
    ('annexe-1 rm, fiche chargée, annexe non lue', B('rm %s/vrai-fichier.txt' % DOC,
        avant=[SK('fichiers-et-nommage')]), FNA),
    ('annexe-2 rm, fiche et annexe lues', B('rm %s/vrai-fichier.txt' % DOC,
        avant=[SK('fichiers-et-nommage'), LU('fichiers-et-nommage', 'SUPPRIMER_DEPLACER')]), 'PASSE'),
    ('annexe-3 rm, refus combiné déjà dit', B('rm %s/vrai-fichier.txt' % DOC,
        avant=[B('rm %s/autre-fichier.txt' % DOC)]), 'PASSE'),
    ('annexe-4 annexe lue par un sous-agent', B('rm %s/vrai-fichier.txt' % DOC,
        avant=[SK('fichiers-et-nommage'), dict(LU('fichiers-et-nommage', 'SUPPRIMER_DEPLACER'), agent_id='a1')]), FNA),
    ('annexe-5 lecture hors annexe', B('rm %s/vrai-fichier.txt' % DOC, avant=[SK('fichiers-et-nommage'),
        dict(LU('fichiers-et-nommage', 'x'), tool_input={'file_path': HOME + '/.claude/skills/fichiers-et-nommage/notes.md'}),
        dict(LU('fichiers-et-nommage', 'x'), tool_input={'file_path': HOME + '/.claude/SUPPRIMER_DEPLACER.md'})]), FNA),
    ('annexe-6 compaction efface la lecture', B('rm %s/vrai-fichier.txt' % DOC, avant=[SK('fichiers-et-nommage'),
        LU('fichiers-et-nommage', 'SUPPRIMER_DEPLACER'), dict(hook_event_name='SessionStart', source='compact'),
        SK('fichiers-et-nommage')]), FNA),
    ('annexe-7 création, fiche chargée', B('touch %s/neuf-harnais.txt' % DOC, avant=[SK('fichiers-et-nommage')]), 'PASSE'),
    ('verite-1 Edit CLAUDE.md, fiche chargée', ED(HOME + '/.claude/CLAUDE.md'), MV),
    ('verite-2 Edit CLAUDE.md, fiche seule', dict(ED(HOME + '/.claude/CLAUDE.md'), avant=[SK('memoire-et-verite')]), MVA),
    ('verite-3 Edit DESIGN.md, fiche et annexe', dict(ED(HOME + '/.claude/DESIGN.md'),
        avant=[SK('memoire-et-verite'), LU('memoire-et-verite', 'SOURCES_DE_VERITE')]), 'PASSE'),
    ('verite-4 Edit fiche de mémoire', dict(ED(HOME + '/.claude/memory/env_harnais.md'), avant=[SK('memoire-et-verite')]), MVA),
    ('verite-5 Edit MEMORY.md, fiche chargée', dict(ED(HOME + '/.claude/memory/MEMORY.md'), avant=[SK('memoire-et-verite')]), 'PASSE'),
    ('verite-6 etat.py add, fiche chargée', B(ETAT + ' add --id d-x "t"', avant=[SK('memoire-et-verite')]), 'PASSE'),
    ('verite-7 Edit REMINDERS.md', ED(HOME + '/.claude/memory/REMINDERS.md'), 'PASSE'),
    ('clo-1 cloture sans reprise', B(CLOTURE_CMD), 'REFUS:reprise'),
    ('clo-2 cloture, reprise chargée', B(CLOTURE_CMD, avant=[SK('reprise')]), CLO),
    ('clo-3 cloture, reprise et annexe', B(CLOTURE_CMD, avant=[SK('reprise'), LU('reprise', 'CLOTURE_PRINCIPALE')]), 'PASSE'),
    ('clo-4 CLAUDEOS_NATURE devant', B('CLAUDEOS_NATURE="chantier: d-x motif" ' + CLOTURE_CMD, avant=[SK('reprise')]), CLO),
    ('clo-5 chemin cité', B('bash "$HOME/.claude/engine/claudeos-cloture.sh"', avant=[SK('reprise')]), CLO),
    ('clo-6 après cd', B('cd ~/.claude && bash engine/claudeos-cloture.sh', avant=[SK('reprise')]), CLO),
    ('clo-7 grep le nomme', B('grep -n claudeos-cloture.sh ~/.claude/README.md', avant=[SK('reprise')]), 'PASSE'),
    ('clo-8 sous-agent', B(CLOTURE_CMD, agent_id='a1'), 'RAPPEL:reprise'),
    ('fer-1 bloc prescrit, reprise chargée', B(FERME, avant=[SK('reprise')]), FER),
    ('fer-2 kill-session improvisé', B('tmux kill-session -t =projet', avant=[SK('reprise')]), FER),
    ('fer-3 tmux list-sessions', B('tmux list-sessions', avant=[SK('reprise')]), 'PASSE'),
    ('fer-6 script prescrit', B('bash /opt/x/.claude/engine/fermer-projet.sh', avant=[SK('reprise')]), FER),
    ('fer-7 grep nomme le script', B('grep -n fermer-projet.sh x.md', avant=[SK('reprise')]), 'PASSE'),
    ('fer-5 heredoc qui nomme', B("python3 - <<'EOF'\nx = 'tmux kill-session -t =s'\nEOF", avant=[SK('reprise')]), 'PASSE'),
    ('clo-9 heredoc qui nomme', B("cat <<'EOF' | wc -l\nbash \"$HOME/.claude/engine/claudeos-cloture.sh\"\nEOF", avant=[SK('reprise')]), 'PASSE'),
    ('fer-4 bloc, reprise et annexe', B(FERME, avant=[SK('reprise'), LU('reprise', 'FERMETURE_PROJET')]), 'PASSE'),
    # --- 8. `--no-verify` et ses équivalents : refusés à chaque fois, chargée ou non
    ('nv-1 --no-verify', B('git commit --no-verify -m x'), NV),
    ('nv-2 abrégé --no-veri', B('git commit --no-veri -m x'), NV),
    ('nv-3 commit -n', B('git commit -n -m x'), NV),
    ('nv-4 grappe -anm', B('git commit -anm x'), NV),
    ('nv-5 -c core.hooksPath', B('git -c core.hooksPath=/dev/null commit -m x'), NV),
    ('nv-6 push --no-verify', B('git push --no-verify'), NV),
    ('nv-7 push -n (dry-run)', B('git push -n'), 'PASSE'),
    ('nv-8 grep -n voisin', B('git commit -m x && grep -n motif f'), 'PASSE'),
    ('nv-9 cité dans le message', B('git commit -m "retirer --no-verify"'), 'PASSE'),
    ('nv-10 levier tracé', B('FORCE_NO_VERIFY="motif" git commit --no-verify -m x'), 'PASSE'),
    ('nv-11 --no-verbose', B('git commit --no-verbose -m x'), 'PASSE'),
]


def lance(hook, tmp, entree):
    d = dict(session_id='harnais-' + uuid.uuid4().hex[:12], hook_event_name='PreToolUse',
             transcript_path=tmp + '/vide.jsonl')
    d.update(entree)
    env = dict(os.environ, XDG_CACHE_HOME=tmp + '/cache')
    for pre in d.pop('avant', []):   # gestes antérieurs de la même session
        subprocess.run(['bash', hook], input=json.dumps(dict(session_id=d['session_id'], **pre)),
                       capture_output=True, text=True, env=env, timeout=30)
    r = subprocess.run(['bash', hook], input=json.dumps(d), capture_output=True, text=True,
                       env=env, timeout=30)
    if not r.stdout.strip():
        return 'PASSE', r
    try:
        o = json.loads(r.stdout)['hookSpecificOutput']
        txt = o.get('permissionDecisionReason') or o.get('additionalContext') or ''
        fiche = txt.split('`')[1] if '`' in txt else '?'
        return ('REFUS:' if o.get('permissionDecision') == 'deny' else 'RAPPEL:') + fiche, r
    except (ValueError, KeyError, IndexError):
        return 'ILLISIBLE ' + r.stdout[:80], r


def main():
    a = sys.argv[1:]
    dossier = a.pop(0) if a and os.path.isdir(a[0]) else ICI
    hook = os.path.join(dossier, 'rappel-fichiers-nommage.sh')
    tmp = tempfile.mkdtemp(prefix='harnais-refus-')
    open(tmp + '/vide.jsonl', 'w').close()
    ko = 0
    try:
        for nom, entree, att in CAS:
            if a and not any(nom.startswith(f) for f in a):
                continue
            got, r = lance(hook, tmp, entree)
            ok = got == att and r.returncode == 0 and not r.stderr.strip()
            ko += not ok
            print('%-36s attendu %-28s obtenu %-28s %s%s' % (
                nom, att, got, 'OK' if ok else 'KO',
                (' rc=%d' % r.returncode if r.returncode else '') + (' STDERR ' + r.stderr.strip()[:80] if r.stderr.strip() else '')))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print('%s : %d KO' % (hook, ko))
    return 1 if ko else 0


if __name__ == '__main__':
    sys.exit(main())
