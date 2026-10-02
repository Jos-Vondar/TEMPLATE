#!/usr/bin/env python3
"""Résolveur des cibles de pointeurs de la carte — SOURCE UNIQUE, importée par DEUX appelants.

SORTI le 2026-09-10 du bloc Python inline du contrôle hebdomadaire 45, geste D1 du plan de
correction de l'audit du même jour. MOTIF, et il est écrit dans `config.sh` au commentaire de
`claudeos_plafond_de` : un même calcul en deux implantations dérive, et c'est la dérive qui produit
un contrôle qui dit vert quand l'autre dit rouge.

LES DEUX APPELANTS, et ils ne font PAS la même chose :

- `engine/weekly-check.sh`, contrôle 45 — juge les pointeurs DÉJÀ écrits, une fois par semaine, et
  AVERTIT. Il attrape les cibles qui meurent APRÈS coup, ce que le refus à l'écriture ne peut pas
  voir. Il appelle ce fichier en script : `python3 resolveur_pointeurs.py <ETAT.md> <mémoire>`.
- `engine/etat.py`, à l'`add` d'un `pointeur --op ajoute` — REFUSE en code 2 une cible qui ne
  résout pas, donc le faux n'entre jamais. Il importe `juge_cibles`.

POURQUOI LE REFUS EST À L'`add` ET JAMAIS AU `projette` : le journal est append-only. Un `projette`
qui refuserait rendrait le niveau IMPROJETABLE dès le premier pointeur mort déjà écrit — et il y en
avait deux le 2026-09-09, réaffirmés par la projection à chaque passage. C'est le constat R-2 de
l'audit, et sa racine : un générateur qui ne connaît pas le disque réaffirme du faux.

CE QUI EST JUGÉ, ET RIEN D'AUTRE : les compétences citées (`compétence <slug>` / `skill <slug>`),
les chemins, et la forme `FICHIER « Section »` — fichier ET titre. NE SONT PAS JUGÉS, et le compte
en est AFFICHÉ : les renvois de section numérotés, les notes d'un coffre de notes (préfixe `wiki `,
hors de l'arbre sauvegardé), et les noms nus sans chemin ni extension. Un contrôle qui tairait
l'étendue de ce qu'il ignore laisserait croire à une couverture totale.
"""

import fnmatch
import os
import re

HOME = os.path.expanduser("~")
MEM_DEFAUT = os.path.join(HOME, ".claude", "memory")

EXT = (".md", ".sh", ".json", ".yaml", ".yml", ".ps1", ".py", ".txt")

# Dossiers sautés au balayage : du runtime ou du transcript, jamais une cible de pointeur.
SKIP = {".git", "node_modules", "__pycache__", ".sync-backups", "plugins",
        "todos", "shell-snapshots", "statsig", "ide", "projects", ".venv"}

_cache = {}


def _arbre(mem):
    """Chemins de l'arbre balayé, calculés UNE fois par processus.

    Les dépôts clients se DÉCOUVRENT par leur discriminant — un `CLAUDE.md` à leur racine —
    jamais par une liste de noms : une liste en dur périme au premier client, et c'est
    exactement ce que `workstations` a fait ici.
    """
    if mem in _cache:
        return _cache[mem]
    clients = [os.path.join(HOME, d) for d in sorted(os.listdir(HOME))
               if not d.startswith(".") and os.path.isfile(os.path.join(HOME, d, "CLAUDE.md"))]
    roots = [os.path.join(HOME, p) for p in (".claude", ".claudeos", "resources", "docs")]
    roots += clients + [mem]
    paths = set()
    for r in roots:
        if not os.path.isdir(r):
            continue
        for dp, dns, fns in os.walk(r):
            dns[:] = [d for d in dns if d not in SKIP]
            for n in list(dns) + fns:
                paths.add(os.path.join(dp, n))
    ancres = [HOME, os.path.join(HOME, ".claude"), os.path.join(HOME, ".claudeos"), mem]
    _cache[mem] = (paths, ancres)
    return _cache[mem]


def resout(c, mem=MEM_DEFAUT):
    """Vrai si le chemin cité existe, par ancre ou par correspondance de FIN.

    2026-08-22 : les accents graves sont retirés AVANT toute résolution. La carte les emploie
    sur une partie de ses pointeurs et pas sur l'autre ; sans ce strip, les pointeurs entourés
    d'accents ne ressemblaient à aucun chemin et tombaient en « non jugés » — 43 sur 163, soit
    un quart de la couche jamais contrôlé, EN SILENCE.
    """
    paths, ancres = _arbre(mem)
    c = c.strip().strip("`").strip().rstrip("/")
    if c.startswith("~/"):
        c = c[2:]
    if c.startswith("<mémoire>/"):
        return os.path.exists(os.path.join(mem, c.split("/", 1)[1]))
    cands = [c]
    # Un agent se cite par son slug là où une compétence se cite par son dossier : compléter
    # en `.md` est la même convention, pas une indulgence.
    if not c.endswith(EXT):
        cands.append(c + ".md")
    for x in cands:
        if "*" in x:
            if any(fnmatch.filter(paths, os.path.join(a, x)) for a in ancres):
                return True
            if any(fnmatch.fnmatch(p, "*/" + x) for p in paths):
                return True
            continue
        if any(os.path.exists(os.path.join(a, x)) for a in ancres):
            return True
        if any(p.endswith(os.sep + x) for p in paths):
            return True
    return False


# D3 de l'audit du 2026-09-16, posé le 2026-09-17. Le contrôle savait qu'une cible EXISTE ; il ne
# savait pas si elle est VIVANTE. V-1 : trois questions d'état pointaient des `MEMORY.md` et des
# `HANDOFF.md` GELÉS le 2026-09-09, donc figés. Le contrôle rendait vert : le fichier existait.
# Corrigés un à un par A3 le 2026-09-16 ; ceci empêche la régression, qui est certaine autrement —
# le gel a figé 22 fichiers de reprise et 11 `MEMORY.md` d'un coup, et rien ne relit les pointeurs.
QUESTION_VIVANTE = re.compile(
    r"en cours|reste[- ]t[- ]il|reste à faire|où en est|qu['’]est-ce qui reste|avancement|statut actuel",
    re.I)


def chemin_resolu(c, mem=MEM_DEFAUT):
    """Le chemin sur disque d'une cible citée, ou None. Même résolution que `resout`."""
    paths, ancres = _arbre(mem)
    c = c.strip().strip("`").strip().rstrip("/")
    if c.startswith("~/"):
        c = c[2:]
    if c.startswith("<mémoire>/"):
        q = os.path.join(mem, c.split("/", 1)[1])
        return q if os.path.exists(q) else None
    for x in ([c] if c.endswith(EXT) else [c, c + ".md"]):
        if "*" in x:
            continue                      # un motif ne désigne pas UN fichier
        for a in ancres:
            q = os.path.join(a, x)
            if os.path.exists(q):
                return q
        for q in paths:
            if q.endswith(os.sep + x):
                return q
    return None


def est_gele(chemin):
    """Vrai si le fichier porte l'en-tête de gel en tête. Forme posée le 2026-09-08."""
    try:
        with open(chemin, encoding="utf-8") as f:
            for ligne in f:
                if ligne.strip():
                    return ligne.lstrip().startswith("> **GELÉ")
    except OSError:
        pass
    return False


def _titres_de(chemin):
    try:
        return {re.sub(r"\s+", " ", l.lstrip("#").strip()).lower()
                for l in open(chemin, encoding="utf-8") if l.startswith("#")}
    except OSError:
        return set()


def section_existe(nom_fichier, titre):
    """Vrai si `nom_fichier` porte une section dont le titre correspond.

    Correspondance par PRÉFIXE dans les DEUX sens : la carte tronque souvent un titre long à
    sa virgule, et un titre peut avoir gagné une queue depuis que le pointeur a été écrit.
    LIMITE CONNUE, mesurée à l'épreuve du 2026-08-22 : un titre AUGMENTÉ d'un suffixe passe,
    parce qu'il est indiscernable d'une citation tronquée. Le contrôle attrape le renommage et
    la suppression, PAS l'ajout en queue. C'est le prix de la troncature, et il est assumé.
    """
    cible = os.path.join(HOME, ".claude", nom_fichier)
    cle = ("titres", cible)
    if cle not in _cache:
        _cache[cle] = _titres_de(cible)
    t = re.sub(r"\s+", " ", titre).strip().lower()
    return any(t == x or x.startswith(t) or t.startswith(x) for x in _cache[cle])


def juge_item(item, mem=MEM_DEFAUT, vivante=False):
    """Juge UNE cible. Rend le message de défaut, ou None si elle résout ou n'est pas jugeable.

    Le second membre du couple dit si l'item a été JUGÉ : `(message, juge)`.
    """
    item = re.sub(r"\s*\([^)]*\)", "", item).strip()   # parenthèse d'aparté

    # (a) FICHIER « Section » — le fichier ET le titre doivent exister. C'était la première
    # cause de « non jugé » — 27 des 43 — parce qu'un item finissant par « » ne ressemble ni à
    # un chemin ni à une compétence. Or c'est précisément la classe de renvoi qui a été tuée en
    # masse le 2026-08-19 quand `DESIGN.md` a perdu sa numérotation.
    sec = re.search(r"«\s*(.+?)\s*»", item)
    if sec:
        f = re.search(r"`?([A-Za-z_]+\.md)`?", item)
        nom = f.group(1) if f else "DESIGN.md"   # sans fichier nommé : DESIGN par défaut
        if not os.path.exists(os.path.join(HOME, ".claude", nom)):
            return ("fichier cité introuvable : " + nom, True)
        if not section_existe(nom, sec.group(1)):
            return (f"section citée absente de {nom} : « {sec.group(1)} »", True)
        return (None, True)

    item = item.split(",")[0]                         # prose après une virgule
    item = re.sub(r"\s*§.*$", "", item).strip()       # renvoi de section numéroté
    if not item or item.startswith("wiki "):
        return (None, False)
    # Accents graves tolérés autour du nom : la carte les met sur une partie seulement.
    m = re.match(r"^(?:compétence|skill)\s+`?([a-z0-9-]+)`?$", item)
    if m:
        if not os.path.isdir(os.path.join(HOME, ".claude", "skills", m.group(1))):
            return ("compétence citée absente de ~/.claude/skills/ : " + m.group(1), True)
        return (None, True)
    if "/" in item or item.strip("`").endswith(EXT):
        if not resout(item, mem):
            return ("chemin cité introuvable : " + item, True)
        if vivante:
            q = chemin_resolu(item, mem)
            if q and est_gele(q):
                return ("question VIVANTE renvoyée vers une cible GELÉE : " + item, True)
        return (None, True)
    return (None, False)


def juge_cibles(cibles, mem=MEM_DEFAUT, vivante=False):
    """Juge une chaîne de cibles séparées par `·`. Rend `(juges, non_juges, defauts)`."""
    juges = non_juges = 0
    defauts = []
    for item in str(cibles).split("·"):
        msg, juge = juge_item(item, mem, vivante)
        if juge:
            juges += 1
            if msg:
                defauts.append(msg)
        else:
            non_juges += 1
    return juges, non_juges, defauts


def _principal(argv):
    """Mode script, pour le contrôle hebdomadaire 45. Contrat de sortie INCHANGÉ.

    Une sortie VIDE, ou `#VIDE`, est une mesure RATÉE et le bash appelant le dit : un corpus de
    citations vide n'est pas une carte propre.
    """
    idx = argv[1]
    mem = argv[2] if len(argv) > 2 else MEM_DEFAUT
    try:
        txt = open(idx, encoding="utf-8").read()
    except OSError:
        return 0
    # REBRANCHÉ le 2026-09-08 sur `## Où trouver` d'`ETAT.md`. Il lisait la couche curatée de
    # `memory/INDEX.md`, GELÉE depuis : un contrôle qui juge un fichier figé finit par crier sur
    # de l'histoire, et c'est arrivé le jour même.
    m = re.search(r"^## Où trouver\n(.*?)(?=^## |^---$|\Z)", txt, re.M | re.S)
    curated = m.group(1) if m else ""
    if not curated.strip():
        return 0
    juges = non_juges = 0
    # La forme projetée est « - **<question>** → `<cibles>` » : c'est le projecteur qui l'écrit,
    # donc elle ne varie pas.
    for question, bloc in re.findall(r"- \*\*(.*?)\*\*\s*→ `([^`]+)`", curated, re.S):
        j, nj, defauts = juge_cibles(bloc, mem, bool(QUESTION_VIVANTE.search(question)))
        juges += j
        non_juges += nj
        for d in defauts:
            print(d)
    print("#BILAN %d pointeur(s) jugé(s), %d non jugé(s)" % (juges, non_juges)
          if juges else "#VIDE")
    return 0


if __name__ == "__main__":
    import sys
    raise SystemExit(_principal(sys.argv))
