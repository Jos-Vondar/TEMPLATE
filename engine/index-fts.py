#!/usr/bin/env python3
"""index-fts.py — l'index dérivé, GESTE D'ESCALADE après un `grep` vide.

Les écarts décidés à l'écriture sont marqués ÉCART ci-dessous.

CE QUE CET INDEX N'EST PAS : un pilier. Il ne se consulte pas d'abord. Le chemin normal reste
`grep` sur le bon périmètre — c'est mesuré, et le verdict du 2026-09-08 est sans ambiguïté : sur
ce corpus, aucun modèle sémantique ne bat la recherche par mots, et le défaut qu'on croyait
technique était un défaut de PÉRIMÈTRE. Cet index sert quand `grep` a rendu vide sur plusieurs
motifs et qu'on ne sait plus où chercher : il cherche partout à la fois, et il classe.

  --reconstruit   rebâtit l'index depuis les dépôts de `claudeos_repos`. 132 ms et 3 978
                  morceaux mesurés le 2026-09-08 ; le plan annonçait 3 130 ms sur 11 518
                  morceaux, mesure d'un banc au corpus PLUS LARGE (il prenait tout le markdown).
  --requete X     interroge. DEUX PASSES, voir ci-dessous.
  --etat          où est l'index, de quand il date, ce qu'il contient.
  Bibliothèque standard SEULE (`sqlite3` en fait partie). Le binaire `sqlite3` est ABSENT de ce
  poste (vérifié `command -v`), d'où le passage par le module.

LA TRONCATURE PAR ÉTOILE EST DANS LE CODE, ET C'EST LE CŒUR DU GESTE.
Décision de l'utilisateur du 2026-09-08. Le tokenizer est `unicode61` SEUL : `porter` est
anglais-seulement (vérifié, documentation SQLite mot pour mot) et DÉGRADE sur ce corpus français
(6/8 contre 8/8, mesuré sur 11 518 morceaux). Sans `porter`, il n'y a AUCUNE racinisation. Ce qui
porte les dérivations est la troncature — `délég*` rend 4/8 là où les deux stemmers rendent 0/8.
Or une troncature écrite en prose dans une fiche ne sera pas tapée le jour où elle sert. Donc
elle est MÉCANIQUE : chaque requête part en deux passes, toujours, et la seconde est étiquetée.

  passe 1, EXACTE    — les mots tels qu'écrits. Ce sont les résultats à croire.
  passe 2, TRONQUÉE  — chaque mot ramené à son radical + `*`. Ce sont des DÉRIVATIONS : elles
                       incluent du bruit, et elles sont affichées à part pour qu'on le sache.

Le radical se fabrique par retrait du plus long suffixe français connu, plancher 5 caractères
(4 pour le pluriel nu), puis retrait d'UNE voyelle finale. C'est ce qui fait passer le cas mesuré
dans les deux sens : `déléguer` → `deleg*` et `délégation` → `deleg*`. Les accents sont retirés
du radical, ce qui est sans effet sur le résultat : `unicode61` retire les diacritiques PAR
DÉFAUT, donc `remove_diacritics 1` serait un no-op et n'est pas écrit.

TROIS ÉCARTS DÉCIDÉS À L'ÉCRITURE :

ÉCART 1 — les deux passes tournent TOUJOURS, pas en repli sur zéro résultat.
Le repli sur zéro paraît plus propre et ne marche pas : `déléguer` rend deux morceaux exacts,
donc il n'escaladerait JAMAIS, et il manquerait les quatre morceaux qui disent `délégation` —
c'est-à-dire exactement le défaut que ce geste existe pour couvrir. Le prix est deux requêtes
au lieu d'une, sur un index local : non mesurable.

ÉCART 2 — le critère du plan reste jouable, par `--exact`.
Le plan exige que `--requete 'déléguer'` NE rende PAS le morceau témoin. Avec la troncature
mécanique il le rend, en passe 2 et étiqueté comme dérivation. Le critère n'est pas faux, il est
antérieur à la décision. `--exact` coupe la passe 2 et rejoue le critère mot pour mot.

ÉCART 3 — l'index refuse de s'écrire hors d'un chemin ignoré par git.
Le plan dit « un `.db` sous `.gitignore` ». Écrit comme un garde, pas comme une consigne : 58 %
du corpus est du document client confidentiel, et un index en porte le texte VERBATIM. Il hérite
donc de la classification `_IGNORE/` — hors sauvegarde, jamais au dépôt. Le script vérifie par
`git check-ignore` avant d'écrire, et refuse en le disant.

ÉCART 5 — le corpus s'élargit aux fiches de `memory/` et aux `CLAUDE.md`, le 2026-09-23.
Arbitrage de l'utilisateur, sur mesure : deux requêtes dont la réponse était connue — « Mac
professionnel », « barre oblique finale » — ne rendaient pas la fiche qui PORTE la règle, parce
que le contrat n'indexait ni `memory/` ni les règlements. Or une fiche `memory/` est la référence
vivante, et c'est la fiche du parc qui manquait le matin même. Sort du corpus : l'index
`MEMORY.md`, déjà injecté à chaque session, et tout ce qui vit sous `_IGNORE/`, `extracted/`
ou `plugins/` — un greffon tiers porte son propre CLAUDE.md.

CODES DE SORTIE :
  0  fait
  1  usage, ou environnement qui manque
  2  refus de garde — la destination n'est pas ignorée par git
  4  index absent ou illisible alors qu'on l'interroge
"""

import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys
import time
import unicodedata
from datetime import datetime

import regime   # le régime sans git, propre au template (`d-regime-sans-git`)

BASE_DEFAUT = os.path.join(os.path.expanduser("~"), ".claude", "_IGNORE", "index-fts.db")

# --- Le corpus, transcrit du plan. Rien d'autre n'est indexé, et c'est voulu : un index qui
# --- avale tout devient un second exemplaire du parc, à un autre âge.
CORPUS = (
    ("journal", "journal/*.jsonl"),
    ("etat", "ETAT.md"),
    ("competence", "skills/*/SKILL.md"),
    ("competence", ".claude/skills/*/SKILL.md"),
    # ÉCART 5, 2026-09-23 — voir l'en-tête.
    ("memoire", "memory/*.md"),
    ("regle", "CLAUDE.md"),
    ("regle", "*/CLAUDE.md"),
    ("regle", "*/*/CLAUDE.md"),
    ("regle", "*/*/*/CLAUDE.md"),
)
# Ce qui ne s'indexe jamais, quel que soit le motif qui l'attrape : l'index de la mémoire, déjà
# chargé à chaque session, et le confidentiel ou le régénérable des dépôts clients.
HORS_CORPUS_NOM = {"MEMORY.md"}
# `/plugins/` : les greffons tiers portent leur propre CLAUDE.md, qui n'est pas une règle du parc.
HORS_CORPUS_DOSSIER = ("/_IGNORE/", "/extracted/", "/plugins/")
# Les archives ne se cherchent PAS par une liste de motifs de chemin. ÉCART 4, décidé à
# l'écriture, et mesuré : `ARCHIVE.md` + `memory/*ARCHIVE*.md` + `domaines/*/ARCHIVE.md` rendait
# 7 archives sur les 22 du parc — les 15 autres sont au niveau d'une APP (`<APP>/ARCHIVE.md`),
# à une profondeur qu'aucun de ces trois motifs n'atteint. Deux discriminants en UNION :
#   - le nom, à n'importe quelle profondeur, par `git ls-files -- '*ARCHIVE*.md'` ;
#   - l'en-tête de GEL en PREMIÈRE ligne, celui du contrôle 24 — il attrape ce que le geste 2.4
#     gèlera (`MEMORY.md`, les fichiers de reprise, `INDEX.md`) et qu'aucun nom ne désigne.
# L'union est nécessaire, pas une ceinture-bretelles : à cette date les 18 archives clients ne
# sont PAS gelées (le gel des clients est en phase 3), et les 4 fichiers gelés du système ne
# s'appelleront pas tous « ARCHIVE ».
# Première ligne, et non « contient » : un PLAN qui cite l'en-tête plus bas n'est pas une archive.
MARQUE_GEL = "> **GELÉ"

# Suffixes français, retirés du plus long au plus court. La liste est courte par choix : elle ne
# cherche pas à raciniser le français, seulement à ouvrir la famille du mot cherché.
SUFFIXES = (
    "ationnelles", "ationnels", "ationnelle", "ationnel", "issements", "issement",
    "ations", "ateurs", "atrices", "atrice", "ements", "ateur", "ation", "ement",
    "istes", "iques", "ismes", "ances", "ences", "tions", "sions", "euses",
    "iste", "ique", "isme", "ance", "ence", "tion", "sion", "eurs", "euse",
    "ages", "aient", "ants", "eur", "age", "ant", "ait", "ent", "ons",
    "ees", "es", "ez", "er", "ir", "ee", "e", "s",
)
VOYELLES = "aeiouy"
PLANCHER = 5
PLANCHER_PLURIEL = 4
# Opérateurs FTS5 : leur présence dit que l'appelant écrit sa requête lui-même. On ne la
# retouche pas — la troncature mécanique existe pour celui qui n'y pense pas, pas contre celui
# qui y pense.
OPERATEURS = re.compile(r'[*"()^:]|\b(?:AND|OR|NOT|NEAR)\b')
MOT = re.compile(r"[^\W\d_]{2,}", re.UNICODE)


def mourir(code, message):
    print(f"index-fts: {message}", file=sys.stderr)
    sys.exit(code)


def sans_accent(mot):
    return "".join(c for c in unicodedata.normalize("NFD", mot)
                   if not unicodedata.combining(c))


def radical(mot):
    """Le radical à étoiler. Retourne le mot nu si aucun retrait ne franchit le plancher."""
    m = sans_accent(mot.lower())
    for suf in sorted(SUFFIXES, key=len, reverse=True):
        if not m.endswith(suf) or len(m) <= len(suf):
            continue
        plancher = PLANCHER_PLURIEL if suf == "s" else PLANCHER
        coupe = m[: -len(suf)]
        if len(coupe) >= plancher:
            m = coupe
            break
    if len(m) > PLANCHER and m[-1] in VOYELLES:
        m = m[:-1]
    return m


def expression(requete, tronque):
    """La requête → une expression MATCH. Chaque mot est cité : sans les guillemets, un mot
    accentué ou ponctué casse la syntaxe FTS5 au lieu de chercher."""
    mots = MOT.findall(requete)
    if not mots:
        return None
    if tronque:
        return " ".join(f'"{radical(m)}"*' for m in mots)
    return " ".join(f'"{m}"' for m in mots)


# ------------------------------------------------------------------- le périmètre sur disque
def depots():
    """Les dépôts, par `claudeos_repos` — jamais une liste recopiée : elle serait fausse au
    prochain client."""
    conf = os.path.join(os.path.expanduser("~"), ".claude", "engine", "config.sh")
    if not os.path.isfile(conf):
        mourir(1, f"{conf} est absent — impossible d'énumérer les dépôts.")
    # `claudeos_racines` : sans git il n'y a aucun dépôt, mais `~/.claude` reste à indexer.
    r = subprocess.run(["bash", "-c", f'source "{conf}"; claudeos_racines'],
                       capture_output=True, text=True)
    if r.returncode != 0:
        mourir(1, f"claudeos_racines a échoué : {r.stderr.strip()}")
    return [d for d in r.stdout.split("\n") if d.strip() and os.path.isdir(d)]


def suivis(depot, motif):
    """Les fichiers SUIVIS d'un dépôt. `git ls-files` plutôt qu'un parcours : il ne descend ni
    dans `.git/` ni dans `_IGNORE/`, donc il ne peut pas ramener de confidentiel par accident.
    Sans git, le périmètre de `regime.py`, tiré des mêmes listes noires."""
    if regime.sans_git(depot):
        return [os.path.join(depot, rel) for rel in regime.suivis(depot, [motif])]
    r = subprocess.run(["git", "-C", depot, "ls-files", "-z", "--", motif],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return []
    return [os.path.join(depot, rel) for rel in r.stdout.split("\0") if rel]


def archives(depot):
    """Les archives du dépôt : le nom OU l'en-tête de gel. Voir MARQUE_GEL pour le motif."""
    trouve = set(suivis(depot, "*ARCHIVE*.md"))
    for chemin in suivis(depot, "*.md"):
        if chemin in trouve:
            continue
        try:
            with open(chemin, encoding="utf-8", errors="replace") as f:
                if f.readline().startswith(MARQUE_GEL):
                    trouve.add(chemin)
        except OSError:
            continue
    return sorted(trouve)


def fichiers():
    """(genre, chemin absolu) pour tout ce que le plan nomme, dédoublonné."""
    import glob as _glob
    vus, sortie = set(), []
    for depot in depots():
        # Les archives passent EN PREMIER : un fichier gelé que `memory/*.md` attrape aussi garde
        # son genre « archive », le dédoublonnage retenant la première occurrence.
        candidats = [("archive", c) for c in archives(depot)]
        candidats += [(g, c) for g, motif in CORPUS
                      for c in sorted(_glob.glob(os.path.join(depot, motif)))
                      if os.path.basename(c) not in HORS_CORPUS_NOM
                      and not any(d in c for d in HORS_CORPUS_DOSSIER)]
        for genre, chemin in candidats:
            reel = os.path.realpath(chemin)
            if reel in vus or not os.path.isfile(reel):
                continue
            vus.add(reel)
            sortie.append((genre, chemin))
    return sortie


def morceaux_md(chemin):
    """Un morceau par paragraphe, avec sa ligne de début : un résultat doit se citer en
    `fichier:ligne`, sinon il oblige à relire le fichier entier."""
    with open(chemin, encoding="utf-8", errors="replace") as f:
        lignes = f.read().split("\n")
    bloc, debut = [], 1
    for i, ligne in enumerate(lignes, 1):
        if ligne.strip():
            if not bloc:
                debut = i
            bloc.append(ligne)
            continue
        if bloc:
            yield debut, "\n".join(bloc)
            bloc = []
    if bloc:
        yield debut, "\n".join(bloc)


def morceaux_jsonl(chemin):
    """Un morceau par événement. Les valeurs textuelles seules : les `id` et les dates ne se
    cherchent pas au mot, elles se cherchent au `grep`."""
    with open(chemin, encoding="utf-8", errors="replace") as f:
        for i, ligne in enumerate(f, 1):
            ligne = ligne.strip()
            if not ligne:
                continue
            try:
                ev = json.loads(ligne)
            except ValueError:
                yield i, ligne
                continue
            if not isinstance(ev, dict):
                yield i, ligne
                continue
            textes = [str(v) for k, v in sorted(ev.items())
                      if isinstance(v, str) and k not in ("id", "date", "horodate", "poste")]
            if textes:
                yield i, " · ".join(textes)


# ---------------------------------------------------------------------------- reconstruction
def ignore_par_git(chemin):
    """Vrai si git ignore ce chemin. `--no-index` est obligatoire, et `-v` DÉTRUIRAIT le code
    retour — c'est écrit dans `controles-et-alarmes`, et c'est déjà arrivé."""
    dossier = os.path.dirname(chemin) or "."
    sonde = dossier
    while not os.path.isdir(sonde) and sonde != os.path.dirname(sonde):
        sonde = os.path.dirname(sonde)
    # Sans git, « ignoré » veut dire HORS DU PÉRIMÈTRE de `regime.py`, mêmes listes noires.
    rac = regime.racine(sonde)
    if rac and regime.sans_git(rac):
        rel = os.path.relpath(os.path.realpath(chemin), rac).replace(os.sep, "/")
        return not rel.startswith("..") and regime.Perimetre(rac).exclu_chemin(rel)
    r = subprocess.run(["git", "-C", sonde, "check-ignore", "--no-index", "-q", chemin],
                       capture_output=True, text=True)
    return r.returncode == 0


def cmd_reconstruit(a):
    base = os.path.abspath(a.base)
    if not ignore_par_git(base):
        mourir(2, f"REFUS : git n'ignore pas {base}.\n"
                  "  Un index porte le texte VERBATIM du corpus, dont 58 % de document client\n"
                  "  confidentiel. Il hérite de la classification `_IGNORE/` : hors sauvegarde,\n"
                  "  jamais au dépôt. Choisir un chemin ignoré, ou l'ignorer d'abord.")
    os.makedirs(os.path.dirname(base), exist_ok=True)
    depart = time.time()
    tmp = base + ".neuf"
    if os.path.exists(tmp):
        os.remove(tmp)
    co = sqlite3.connect(tmp)
    co.execute("CREATE VIRTUAL TABLE morceaux USING fts5("
               "texte, fichier UNINDEXED, ligne UNINDEXED, genre UNINDEXED,"
               " tokenize='unicode61')")
    co.execute("CREATE TABLE bati (cle TEXT PRIMARY KEY, valeur TEXT)")
    n_morceaux = 0
    # Horodate prise AVANT la lecture et gardée à la fraction de seconde — corrigé le 2026-09-23.
    # Prise à la FIN et tronquée à l'entier, elle faisait signaler « plus récent que l'index » un
    # fichier écrit dans la même seconde juste avant : deux ETAT.md projetés par la sauvegarde,
    # 10:12:09,03 contre une horodate de 10:12:09. Prise au début, tout fichier touché PENDANT la
    # construction est signalé, à raison : il a pu être lu avant sa modification.
    t0 = time.time()
    liste = fichiers()
    maison = os.path.expanduser("~") + os.sep
    for genre, chemin in liste:
        lecteur = morceaux_jsonl if chemin.endswith(".jsonl") else morceaux_md
        court = chemin[len(maison):] if chemin.startswith(maison) else chemin
        lot = [(t, court, ligne, genre) for ligne, t in lecteur(chemin) if len(t.strip()) >= 20]
        if lot:
            co.executemany("INSERT INTO morceaux(texte, fichier, ligne, genre)"
                           " VALUES (?, ?, ?, ?)", lot)
            n_morceaux += len(lot)
    co.executemany("INSERT INTO bati(cle, valeur) VALUES (?, ?)", [
        ("bati_le", datetime.now().strftime("%Y-%m-%d %H:%M")),
        ("horodate", repr(t0)),
        ("fichiers", str(len(liste))),
        ("morceaux", str(n_morceaux)),
    ])
    co.commit()
    co.close()
    os.replace(tmp, base)
    ms = int((time.time() - depart) * 1000)
    print(f"index bâti : {n_morceaux} morceaux · {len(liste)} fichiers · {ms} ms")
    print(f"  {base} ({os.path.getsize(base)} octets, ignoré par git)")


# ------------------------------------------------------------------------------ interrogation
def ouvre(base):
    if not os.path.isfile(base):
        mourir(4, f"{base} est absent. Lance d'abord : "
                  f"python3 {os.path.basename(__file__)} --reconstruit")
    try:
        co = sqlite3.connect(f"file:{base}?mode=ro", uri=True)
        co.execute("SELECT count(*) FROM morceaux").fetchone()
    except sqlite3.Error as e:
        mourir(4, f"{base} est illisible : {e}")
    return co


def meta(co):
    return dict(co.execute("SELECT cle, valeur FROM bati").fetchall())


def cherche(co, expr, limite):
    return co.execute(
        "SELECT fichier, ligne, genre,"
        " snippet(morceaux, 0, '«', '»', '…', 14) FROM morceaux"
        " WHERE morceaux MATCH ? ORDER BY rank LIMIT ?", (expr, limite)).fetchall()


def perime(co):
    """Les fichiers du corpus plus récents que l'index. Un index vieux qui rend vide fait
    conclure à une absence qui n'existe pas — c'est le piège que ce contrôle ferme."""
    h = float(meta(co).get("horodate", "0"))
    return [c for _, c in fichiers() if os.path.getmtime(c) > h]


def affiche(lignes, deja=None):
    vus = set()
    for fichier, ligne, genre, extrait in lignes:
        cle = (fichier, ligne)
        if deja is not None and cle in deja:
            continue
        if cle in vus:
            continue
        vus.add(cle)
        extrait = " ".join(extrait.split())
        print(f"  {fichier}:{ligne}  [{genre}]  {extrait}")
    return vus


def cmd_requete(a):
    co = ouvre(a.base)
    m = meta(co)
    brute = bool(OPERATEURS.search(a.requete))
    expr = a.requete if brute else expression(a.requete, tronque=False)
    if not expr:
        mourir(1, "requête sans aucun mot cherchable.")
    try:
        exactes = cherche(co, expr, a.limite)
    except sqlite3.OperationalError as e:
        mourir(1, f"expression refusée par FTS5 : {e}")
    etiquette = "écrite telle quelle" if brute else "recherche exacte"
    print(f"{a.requete} — {len(exactes)} morceau(x) ({etiquette})")
    deja = affiche(exactes)

    if brute or a.exact:
        raison = "l'appelant écrit sa propre expression" if brute else "--exact"
        print(f"  (passe tronquée non jouée : {raison})")
    else:
        tr = expression(a.requete, tronque=True)
        derivees = [l for l in cherche(co, tr, a.limite) if (l[0], l[1]) not in deja]
        print()
        if derivees:
            print(f"+ {len(derivees)} morceau(x) que seule la TRONCATURE « {tr} » trouve"
                  " — DÉRIVATIONS, à lire comme telles")
            affiche(derivees, deja)
        else:
            print(f"+ 0 morceau de plus par la troncature « {tr} »")

    if not exactes:
        print()
        print("PÉRIMÈTRE de cette recherche, parce qu'un vide ne prouve rien sans lui :")
        print(f"  {m.get('morceaux', '?')} morceaux · {m.get('fichiers', '?')} fichiers ·"
              f" index bâti le {m.get('bati_le', '?')}")
        print("  journal, ETAT.md, archives (par le nom OU l'en-tête de gel), compétences, fiches")
        print("  memory/ et CLAUDE.md, sur les dépôts de `claudeos_repos` — RIEN D'AUTRE. Ni l'index")
        print("  MEMORY.md, ni les plans, ni les rapports, ni _IGNORE/ ni extracted/.")
    retard = perime(co)
    if retard:
        print()
        print(f"⚠ index bâti le {m.get('bati_le', '?')} · {len(retard)} fichier(s) du corpus"
              " ont changé depuis. Relance --reconstruit avant de conclure à une absence.")


def cmd_etat(a):
    co = ouvre(a.base)
    m = meta(co)
    print(f"{a.base} · {os.path.getsize(a.base)} octets")
    print(f"bâti le {m.get('bati_le', '?')} · {m.get('morceaux', '?')} morceaux ·"
          f" {m.get('fichiers', '?')} fichiers")
    for genre, n in co.execute("SELECT genre, count(*) FROM morceaux"
                               " GROUP BY genre ORDER BY 2 DESC"):
        print(f"  {genre:12s} {n}")
    retard = perime(co)
    print(f"{len(retard)} fichier(s) plus récents que l'index"
          + (" — relance --reconstruit" if retard else ""))


def main():
    ap = argparse.ArgumentParser(prog="index-fts.py",
                                 description=__doc__.split("\n")[0])
    ap.add_argument("--reconstruit", action="store_true", help="rebâtir l'index")
    ap.add_argument("--requete", metavar="X", help="interroger (deux passes)")
    ap.add_argument("--etat", action="store_true", help="où en est l'index")
    ap.add_argument("--exact", action="store_true",
                    help="couper la passe tronquée (rejoue le critère du plan)")
    ap.add_argument("--limite", type=int, default=12, help="morceaux par passe (défaut 12)")
    ap.add_argument("--base", default=BASE_DEFAUT, help=f"chemin du .db (défaut {BASE_DEFAUT})")
    a = ap.parse_args()
    if a.reconstruit:
        cmd_reconstruit(a)
    elif a.requete:
        cmd_requete(a)
    elif a.etat:
        cmd_etat(a)
    else:
        ap.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
