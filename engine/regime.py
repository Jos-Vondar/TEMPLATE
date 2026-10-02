#!/usr/bin/env python3
"""regime.py — ce que le moteur ajoute pour tourner SANS git (`d-regime-sans-git`).

Écrit le 2026-10-01, plan complet de templating § 2, A3. Code PROPRE AU TEMPLATE : le moteur
reporté de la source suppose git, et tout ce que le régime `GIT=aucun` demande en plus vit ici
et dans `lib_regime.sh`, pour que les fichiers reportés ne changent que de quelques lignes et
que la passe de report reste un diff (geste 7). Bibliothèque standard seule.

SANS GIT, LA DERNIÈRE CLÔTURE TIENT LIEU DE `HEAD`. Elle laisse sous
`<racine>/.claudeos/empreintes/MANIFESTE.json`, pour chaque fichier du périmètre, l'empreinte de
son contenu, sa première ligne et l'empreinte de chacune de ses lignes. AUCUNE COPIE DU CONTENU :
sans git il n'y a ni historique ni retour arrière — c'est le prix dit à l'installateur au choix
du régime —, et une copie de l'arbre doublerait chaque résultat d'un `grep` sur le système.

LE PÉRIMÈTRE est ce que git suivrait : tout l'arbre de la racine, moins sa liste noire
(`.gitignore` de la racine) et celle des dossiers de travail (`engine/config/gitignore-documents`),
lues TELLES QUELLES — aucune liste n'est recopiée ici —, et moins `.git/` et `.claudeos/`.
LIMITES DITES, et elles refusent plutôt que de se taire : un `.gitignore` de sous-dossier n'est pas
lu ; un motif à barre oblique inverse, ou une étoile double hors d'un segment entier, est REFUSÉ et
nommé. Une exclusion mal comprise ferait sortir un fichier des contrôles sans un mot.

LA RACINE : celle du dépôt git s'il y en a un, sinon le plus proche ancêtre qui porte
`.claudeos-racine` ; les deux à la fois, la plus profonde l'emporte.

  racine <chemin>              la racine, sur la sortie ; rc=1 si aucune
  changes <racine>             une ligne `A|M|D<tab>chemin` par fichier changé depuis la dernière
                               clôture, triée ; avant toute clôture, tout est `A`
  binaires <racine>            parmi les chemins lus sur l'entrée, ceux dont le contenu est binaire
                               (un octet nul dans les 8 000 premiers, la règle de git)
  ajouts <racine> [chemin…]    les lignes absentes de l'empreinte de clôture du fichier ; sans
                               chemin, ceux de l'entrée. Un binaire n'en rend aucune, comme git
  tete <racine> <chemin>       la première ligne à la dernière clôture ; rc=1 si le fichier est neuf
  egal <racine> <chemin> <n>   rc=0 si le fichier privé de ses n premières lignes est celui de la
                               dernière clôture, sauts de ligne finaux exclus — le commit de gel
  suivis <racine> <motif>…     les fichiers du périmètre que désigne un motif, comme `git ls-files`
  exclu <racine> <chemin>      rc=0 si le chemin est hors du périmètre, comme `git check-ignore`
  ecrit <racine> [--sauf F]    réécrit les empreintes depuis le disque, sauf les chemins listés
                               dans F — le dernier geste d'une clôture qui a passé ses contrôles
  pose <racine> <amorce>       l'installation sans git : copie dans la racine chaque fichier livré
                               par l'amorce qui y manque, puis écrit l'ÉTAT LIVRÉ. Un fichier en
                               place qui diffère de sa version livrée est un CONFLIT : tous sont
                               nommés, et RIEN n'est écrit (rc=1)
  livre <racine>               rc=0 si chaque fichier de l'état livré est en place, intact ou gardé
                               par choix à la dernière mise à jour (une ligne `gardé<tab>chemin`
                               chacun) ; sinon les écarts, une ligne `absent|modifié<tab>chemin`
                               chacun (rc=1)

L'ÉTAT LIVRÉ, sous `<racine>/.claudeos/livre/` (plan complet § 1.9 et A8) : `MANIFESTE`, une ligne
`<sha256>  <chemin>` par fichier livré, triée — la forme de `shasum -a 256`, que
`shasum -a 256 -c .claudeos/livre/MANIFESTE` relit depuis la racine —, et `VERSION`, la version
livrée, copiée d'`engine/VERSION` (« inconnue » sans lui). C'est ce que `verifier.py plomberie`
compare, et la base de la mise à jour sans git (A8). Écrit le 2026-10-01, A6.
S'y ajoutent, le 2026-10-01 (A8), deux fichiers :
- `ARBRE.tar.gz`, la copie de l'arbre livré : la base de la fusion à trois, et le seul moyen de
  MONTRER ce que la personne a changé dans un fichier livré — une empreinte dit qu'il diffère, pas
  en quoi. Elle est COMPRIMÉE pour la raison qui interdit plus haut toute copie en clair : un `grep`
  sur le système trouverait chaque texte livré deux fois. L'amorce, elle, est proposée à la
  suppression en fin d'installation, et rien d'autre ne garde ce contenu.
- `GARDES`, écrit par `mettre-a-jour.py` : une ligne `<sha256|absent>  <chemin>` par fichier livré
  que la personne a choisi de garder différent de la version, ou que la version ne touchait pas.
  Un écart qui y figure, dans le même état, n'est plus un défaut ; un écart neuf en reste un.

CODES : 0 fait · 1 rien à rendre (pas de racine, fichier neuf, non exclu, non égal) · 2 REFUS de
lire — motif non pris en charge, fichier illisible, empreintes corrompues. Un 2 ne se lit jamais
comme « rien ».
"""
import fnmatch
import hashlib
import json
import os
import re
import subprocess
import sys
from collections import Counter
from datetime import datetime

MARQUE_RACINE = ".claudeos-racine"
DOSSIER = ".claudeos"
MANIFESTE = os.path.join(DOSSIER, "empreintes", "MANIFESTE.json")
LISTES_NOIRES = (".gitignore", os.path.join("engine", "config", "gitignore-documents"))
VERSION = 1
TETE_MAX = 200          # la première ligne gardée, en caractères : assez pour un en-tête de gel
LIVRE = os.path.join(DOSSIER, "livre")
LIVRE_ARBRE = "ARBRE.tar.gz"
LIVRE_GARDES = "GARDES"
# Ce qu'une amorce porte sans le livrer : son propre dépôt, l'état d'un système, et le bruit ordinaire.
LIVRE_HORS = {".git", DOSSIER, "__pycache__", ".DS_Store"}


class Refus(Exception):
    """« Je n'ai pas pu lire » : jamais confondu avec « il n'y a rien »."""


# ------------------------------------------------------------------------------------ racine
def _racine_git(chemin):
    try:
        r = subprocess.run(["git", "-C", chemin, "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True)
    except (FileNotFoundError, NotADirectoryError):      # git absent du poste
        return None
    out = r.stdout.strip()
    return os.path.realpath(out) if r.returncode == 0 and out else None


def _racine_marquee(chemin):
    d = os.path.realpath(chemin)
    while True:
        if os.path.isfile(os.path.join(d, MARQUE_RACINE)):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def racine(chemin):
    g, m = _racine_git(chemin), _racine_marquee(chemin)
    if g and m:
        return g if len(g) >= len(m) else m
    return g or m


def sans_git(rac):
    """Vrai si la racine est marquée et ne porte pas de dépôt : c'est la dernière clôture, et
    non `HEAD`, qui fait référence."""
    return (os.path.isfile(os.path.join(rac, MARQUE_RACINE))
            and not os.path.exists(os.path.join(rac, ".git")))


# --------------------------------------------------------------------------------- périmètre
def _motif_en_regex(g):
    """Un motif de liste noire → une expression. `*` et `?` ne franchissent pas `/` ; `**` vaut
    zéro ou plusieurs dossiers, seulement comme segment entier — la grammaire de git."""
    out, i, n = [], 0, len(g)
    while i < n:
        c = g[i]
        if g.startswith("**", i):
            if not ((i == 0 or g[i - 1] == "/") and (i + 2 == n or g[i + 2] == "/")):
                raise ValueError("étoile double hors d'un segment entier")
            if i + 2 == n:
                out.append(".*")
                i += 2
            else:
                out.append("(?:.*/)?")
                i += 3
        elif c == "*":
            out.append("[^/]*")
            i += 1
        elif c == "?":
            out.append("[^/]")
            i += 1
        elif c == "[":
            j = g.find("]", i + 2)
            if j < 0:
                raise ValueError("crochet non fermé")
            classe = g[i + 1:j]
            if classe.startswith("!"):
                classe = "^" + classe[1:]
            out.append("[" + classe + "]")
            i = j + 1
        else:
            out.append(re.escape(c))
            i += 1
    return "".join(out)


class Perimetre:
    """Ce que git suivrait sous la racine, d'après les listes noires livrées."""

    def __init__(self, rac):
        self.rac = rac
        self.regles = []           # (expression, sur le seul nom, dossiers seuls, négation)
        for rel in LISTES_NOIRES:
            f = os.path.join(rac, rel)
            if not os.path.isfile(f):
                continue
            try:
                with open(f, encoding="utf-8") as fh:
                    lignes = fh.read().split("\n")
            except (OSError, UnicodeDecodeError) as e:
                raise Refus(f"liste noire illisible : {f} ({e})")
            for n, brut in enumerate(lignes, 1):
                self._ajoute(brut.rstrip("\r"), f"{rel}:{n}")

    def _ajoute(self, ligne, ou):
        if not ligne.strip() or ligne.startswith("#"):
            return
        if "\\" in ligne:
            raise Refus(f"{ou} — motif « {ligne} » : la barre oblique inverse ne se lit pas sans "
                        f"git. Réécrire le motif sans elle.")
        motif = ligne.rstrip(" ")              # git ignore les espaces finaux non échappés
        negation = motif.startswith("!")
        if negation:
            motif = motif[1:]
        dossiers_seuls = motif.endswith("/")
        motif = motif.rstrip("/")
        ancre = "/" in motif                   # une barre ailleurs qu'en fin ancre sur la racine
        motif = motif.lstrip("/")
        if not motif:
            raise Refus(f"{ou} — motif « {ligne} » vide une fois lu.")
        try:
            rx = re.compile("^" + _motif_en_regex(motif) + "$")
        except (ValueError, re.error) as e:
            raise Refus(f"{ou} — motif « {ligne} » non pris en charge sans git : {e}.")
        self.regles.append((rx, not ancre, dossiers_seuls, negation))

    def exclu(self, rel, est_dossier):
        """Le verdict sur UN chemin, ses parents supposés inclus. La dernière règle qui répond
        l'emporte, comme dans git."""
        parts = rel.split("/")
        if ".git" in parts or parts[0] == DOSSIER:
            return True
        nom, hors = parts[-1], False
        for rx, sur_nom, dossiers_seuls, negation in self.regles:
            if dossiers_seuls and not est_dossier:
                continue
            if rx.match(nom if sur_nom else rel):
                hors = not negation
        return hors

    def exclu_chemin(self, rel):
        """Le verdict sur un chemin ET sur chacun de ses parents : un dossier exclu emporte tout
        ce qu'il contient, sans retour possible — la règle de git."""
        parts = rel.strip("/").split("/")
        for i in range(1, len(parts) + 1):
            sous = "/".join(parts[:i])
            est_dossier = i < len(parts) or os.path.isdir(os.path.join(self.rac, sous))
            if self.exclu(sous, est_dossier):
                return True
        return False

    def fichiers(self):
        """Les chemins relatifs du périmètre, triés. Un dossier illisible REFUSE : il ne
        rétrécit pas le périmètre en silence. Un lien se prend comme git le prend, par sa cible
        écrite, sans le suivre."""
        sortie = []

        def illisible(e):
            raise Refus(f"illisible : {e.filename} ({e.strerror})")

        for d, dirs, files in os.walk(self.rac, onerror=illisible, followlinks=False):
            reld = os.path.relpath(d, self.rac)
            reld = "" if reld == "." else reld.replace(os.sep, "/")
            garde = []
            for x in sorted(dirs):
                rel = f"{reld}/{x}" if reld else x
                if os.path.islink(os.path.join(d, x)):
                    if not self.exclu(rel, False):
                        sortie.append(rel)
                    continue
                if not self.exclu(rel, True):
                    garde.append(x)
            dirs[:] = garde
            for x in files:
                rel = f"{reld}/{x}" if reld else x
                if not self.exclu(rel, False):
                    sortie.append(rel)
        return sorted(sortie)


# -------------------------------------------------------------------------------- empreintes
def contenu(rac, rel):
    p = os.path.join(rac, rel)
    try:
        if os.path.islink(p):
            return ("lien:" + os.readlink(p)).encode("utf-8", "surrogateescape")
        with open(p, "rb") as fh:
            return fh.read()
    except OSError as e:
        raise Refus(f"illisible : {p} ({e.strerror})")


def est_binaire(data):
    return b"\0" in data[:8000]


def _lignes(data):
    lignes = data.split(b"\n")
    if lignes and lignes[-1] == b"":
        lignes.pop()
    return lignes


def _h(b):
    return hashlib.sha256(b).hexdigest()


def _hl(b):
    return hashlib.sha256(b).hexdigest()[:16]


def empreinte(data):
    e = {"h": _h(data), "hr": _h(data.rstrip(b"\n"))}
    if est_binaire(data):
        e["b"] = True
        return e
    lignes = _lignes(data)
    e["t"] = lignes[0].decode("utf-8", "replace")[:TETE_MAX] if lignes else ""
    e["l"] = [_hl(x) for x in lignes]
    return e


def lit_manifeste(rac):
    """Les empreintes de la dernière clôture, `{}` avant la première."""
    p = os.path.join(rac, MANIFESTE)
    if not os.path.exists(p):
        return {}
    try:
        with open(p, encoding="utf-8") as fh:
            m = json.load(fh)
        if m.get("version") != VERSION or not isinstance(m.get("fichiers"), dict):
            raise ValueError("forme inattendue")
        return m["fichiers"]
    except (OSError, ValueError) as e:
        raise Refus(f"empreintes de la dernière clôture illisibles ({p}) : {e}. Sans elles, rien "
                    f"ne dit ce qui a changé ni si un journal a été réécrit. Les reposer par "
                    f"`regime.py ecrit` fait de l'état présent la nouvelle référence : ce qui a "
                    f"changé depuis la clôture précédente ne sera plus contrôlé.")


def ecrit(rac, sauf=()):
    fichiers = {rel: empreinte(contenu(rac, rel))
                for rel in Perimetre(rac).fichiers() if rel not in sauf}
    p = os.path.join(rac, MANIFESTE)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".neuf"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump({"version": VERSION,
                   "ecrit": datetime.now().astimezone().isoformat(timespec="seconds"),
                   "fichiers": fichiers}, fh, ensure_ascii=False, sort_keys=True)
    os.replace(tmp, p)
    return len(fichiers)


def changes(rac):
    anc = lit_manifeste(rac)
    vus, sortie = set(), []
    for rel in Perimetre(rac).fichiers():
        vus.add(rel)
        if rel not in anc:
            sortie.append(("A", rel))
        elif anc[rel].get("h") != _h(contenu(rac, rel)):
            sortie.append(("M", rel))
    sortie += [("D", rel) for rel in anc if rel not in vus]
    return sorted(sortie, key=lambda x: x[1])


def ajouts(rac, rel, anc):
    """Les lignes du fichier qu'aucune ligne de la dernière clôture ne portait, une par une :
    une ligne déplacée n'est pas ajoutée, une ligne doublée l'est."""
    data = contenu(rac, rel)
    if est_binaire(data):
        return []
    lignes = _lignes(data)
    e = anc.get(rel)
    if not e or "l" not in e:
        return lignes
    reste, sortie = Counter(e["l"]), []
    for x in lignes:
        k = _hl(x)
        if reste[k] > 0:
            reste[k] -= 1
        else:
            sortie.append(x)
    return sortie


# ---- pour `etat.py` : le journal append-only sans `HEAD` -----------------------------------
def lignes_cloture(rac, rel):
    """Les empreintes des lignes du fichier à la dernière clôture, `None` s'il est neuf."""
    e = lit_manifeste(rac).get(rel)
    return None if not e or "l" not in e else list(e["l"])


def lignes_disque(rac, rel):
    return [_hl(x) for x in _lignes(contenu(rac, rel))]


def suivis(rac, motifs):
    """Les fichiers du périmètre qu'un motif désigne, au sens de `git ls-files` : `*` y franchit
    `/`, et un nom de dossier vaut tout ce qu'il contient."""
    sortie = []
    for rel in Perimetre(rac).fichiers():
        for m in motifs:
            m = m.rstrip("/")
            if fnmatch.fnmatchcase(rel, m) or rel.startswith(m + "/"):
                sortie.append(rel)
                break
    return sortie


# ------------------------------------------------------------------------------------- appel
# ------------------------------------------------------------------------------- état livré
def livres(amorce):
    """Les chemins livrés par l'amorce, relatifs et triés."""
    sortie = []
    for d, sous, fs in os.walk(amorce):
        sous[:] = sorted(s for s in sous if s not in LIVRE_HORS)
        for f in fs:
            if f in LIVRE_HORS:
                continue
            sortie.append(os.path.relpath(os.path.join(d, f), amorce).replace(os.sep, "/"))
    return sorted(sortie)


def _sha_fichier(p):
    h = hashlib.sha256()
    with open(p, "rb") as fh:
        for bloc in iter(lambda: fh.read(1 << 16), b""):
            h.update(bloc)
    return h.hexdigest()


def livre_lit(rac):
    """{chemin: sha256} de l'état livré ; {} s'il n'y en a pas. Une ligne illisible REFUSE."""
    p = os.path.join(rac, LIVRE, "MANIFESTE")
    if not os.path.exists(p):
        return {}
    sortie = {}
    try:
        lignes = open(p, encoding="utf-8").read().splitlines()
    except (OSError, UnicodeDecodeError) as e:
        raise Refus(f"état livré illisible : {p} ({e})")
    for n, l in enumerate(lignes, 1):
        m = re.match(r"^([0-9a-f]{64})  (.+)$", l)
        if not m:
            raise Refus(f"état livré, {p} ligne {n} illisible : {l!r}")
        sortie[m.group(2)] = m.group(1)
    return sortie


def livre_gardes(rac):
    """{chemin: sha256 | "absent"} des écarts gardés par choix ; {} sans fichier GARDES."""
    p = os.path.join(rac, LIVRE, LIVRE_GARDES)
    if not os.path.exists(p):
        return {}
    sortie = {}
    try:
        lignes = open(p, encoding="utf-8").read().splitlines()
    except (OSError, UnicodeDecodeError) as e:
        raise Refus(f"écarts gardés illisibles : {p} ({e})")
    for n, l in enumerate(lignes, 1):
        m = re.match(r"^([0-9a-f]{64}|absent)  (.+)$", l)
        if not m:
            raise Refus(f"écarts gardés, {p} ligne {n} illisible : {l!r}")
        sortie[m.group(2)] = m.group(1)
    return sortie


def livre_ecarts(rac):
    """([(chemin, absent|modifié)], nombre de fichiers livrés, [chemins des écarts gardés]). Un
    écart que `GARDES` porte dans le même état n'en est plus un : la personne l'a choisi à la mise
    à jour."""
    livre, gardes = livre_lit(rac), livre_gardes(rac)
    ecarts, tenus = [], []
    for rel, h in sorted(livre.items()):
        p = os.path.join(rac, rel)
        etat = "absent" if not os.path.isfile(p) else _sha_fichier(p)
        if etat == h:
            continue
        if gardes.get(rel) == etat:
            tenus.append(rel)
            continue
        ecarts.append((rel, "absent" if etat == "absent" else "modifié"))
    return ecarts, len(livre), tenus


def livre_arbre(rac):
    """{chemin: octets} de la copie livrée ; None si elle manque. Une archive illisible REFUSE."""
    import tarfile
    p = os.path.join(rac, LIVRE, LIVRE_ARBRE)
    if not os.path.exists(p):
        return None
    try:
        with tarfile.open(p, "r:gz") as t:
            return {m.name: t.extractfile(m).read() for m in t.getmembers() if m.isfile()}
    except (OSError, tarfile.TarError, EOFError) as e:
        raise Refus(f"copie livrée illisible : {p} ({e})")


def livre_arbre_ecarts(rac):
    """Ce qui fait de la copie livrée une base fausse, une phrase par défaut ; [] si elle est
    conforme au MANIFESTE, fichier par fichier."""
    arbre = livre_arbre(rac)
    if arbre is None:
        return [f"{LIVRE_ARBRE} absente"]
    sortie = []
    for rel, h in sorted(livre_lit(rac).items()):
        if rel not in arbre:
            sortie.append(f"{rel} manque à la copie")
        elif _h(arbre[rel]) != h:
            sortie.append(f"{rel} : la copie diffère du MANIFESTE")
    return sortie


def ecrit_livre(rac, source, chemins, empreintes, version, gardes=None):
    """L'état livré entier, depuis l'arbre `source` : la copie comprimée, les écarts gardés, puis
    le MANIFESTE et la VERSION, en dernier. Chaque fichier s'écrit à côté puis se renomme : une
    coupure laisse l'ancien fichier ou le neuf, jamais une moitié."""
    import tarfile
    dossier = os.path.join(rac, LIVRE)
    os.makedirs(dossier, exist_ok=True)
    tmp = os.path.join(dossier, LIVRE_ARBRE + ".neuf")
    with tarfile.open(tmp, "w:gz") as t:
        for rel in chemins:
            t.add(os.path.join(source, rel), arcname=rel, recursive=False)
    os.replace(tmp, os.path.join(dossier, LIVRE_ARBRE))
    p = os.path.join(dossier, LIVRE_GARDES)
    if gardes:
        with open(p + ".neuf", "w", encoding="utf-8") as fh:
            fh.write("".join(f"{gardes[r]}  {r}\n" for r in sorted(gardes)))
        os.replace(p + ".neuf", p)
    elif os.path.exists(p):
        os.remove(p)
    for nom, texte in (("MANIFESTE", "".join(f"{empreintes[r]}  {r}\n" for r in chemins)),
                       ("VERSION", version + "\n")):
        tmp = os.path.join(dossier, nom + ".neuf")
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(texte)
        os.replace(tmp, os.path.join(dossier, nom))


def pose(rac, amorce):
    """(conflits, copiés, égaux). Tout se contrôle AVANT la première écriture."""
    import shutil
    if not os.path.isdir(amorce):
        raise Refus(f"amorce introuvable : {amorce}")
    if os.path.realpath(amorce) == os.path.realpath(rac):
        raise Refus("l'amorce et la racine sont le même dossier : rien à poser.")
    chemins = livres(amorce)
    if not chemins:
        raise Refus(f"l'amorce {amorce} ne livre aucun fichier.")
    conflits, a_copier, egaux, empreintes = [], [], 0, {}
    for rel in chemins:
        src, dst = os.path.join(amorce, rel), os.path.join(rac, rel)
        h = _sha_fichier(src)
        empreintes[rel] = h
        if os.path.lexists(dst):
            if os.path.isfile(dst) and not os.path.islink(dst) and _sha_fichier(dst) == h:
                egaux += 1
            else:
                conflits.append(rel)
        else:
            parent = os.path.dirname(dst)
            while parent and parent != rac and not os.path.isdir(parent):
                if os.path.lexists(parent):
                    conflits.append(f"{rel} (le chemin {os.path.relpath(parent, rac)} n'est pas un dossier)")
                    break
                parent = os.path.dirname(parent)
            else:
                a_copier.append(rel)
    if conflits:
        return conflits, 0, egaux
    for rel in a_copier:
        dst = os.path.join(rac, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(os.path.join(amorce, rel), dst)
    ecrit_livre(rac, amorce, chemins, empreintes, _version_livree(amorce))
    return [], len(a_copier), egaux


def _version_livree(amorce):
    try:
        v = open(os.path.join(amorce, "engine", "VERSION"), encoding="utf-8").read().strip()
    except OSError:
        v = ""
    return v or "inconnue"


def _ecrit_lignes(lignes):
    out = sys.stdout.buffer
    for x in lignes:
        out.write(x + b"\n")
    out.flush()


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 1
    cmd, args = argv[0], argv[1:]
    rac = os.path.realpath(args[0])
    if cmd == "racine":
        r = racine(args[0])
        if not r:
            return 1
        print(r)
        return 0
    if cmd == "changes":
        for s, rel in changes(rac):
            print(f"{s}\t{rel}")
        return 0
    if cmd == "binaires":
        for rel in sys.stdin.read().split("\n"):
            if rel and os.path.isfile(os.path.join(rac, rel)) and est_binaire(contenu(rac, rel)[:8000]):
                print(rel)
        return 0
    if cmd == "ajouts":
        anc = lit_manifeste(rac)
        rels = args[1:] or [r for r in sys.stdin.read().split("\n") if r]
        for rel in rels:
            if os.path.isfile(os.path.join(rac, rel)):
                _ecrit_lignes(ajouts(rac, rel, anc))
        return 0
    if cmd == "tete":
        e = lit_manifeste(rac).get(args[1])
        if not e:
            return 1
        print(e.get("t", ""))
        return 0
    if cmd == "egal":
        rel, n = args[1], int(args[2])
        e = lit_manifeste(rac).get(rel)
        attendu = e["hr"] if e else _h(b"")
        reste = b"\n".join(_lignes(contenu(rac, rel))[n:])
        return 0 if _h(reste.rstrip(b"\n")) == attendu else 1
    if cmd == "suivis":
        for rel in suivis(rac, args[1:]):
            print(rel)
        return 0
    if cmd == "exclu":
        cible = os.path.realpath(os.path.join(rac, args[1])) if not os.path.isabs(args[1]) \
            else os.path.realpath(args[1])
        rel = os.path.relpath(cible, rac).replace(os.sep, "/")
        if rel == ".." or rel.startswith("../"):
            raise Refus(f"{args[1]} n'est pas sous la racine {rac}.")
        return 0 if Perimetre(rac).exclu_chemin(rel) else 1
    if cmd == "ecrit":
        sauf = set()
        if len(args) >= 3 and args[1] == "--sauf":
            with open(args[2], encoding="utf-8") as fh:
                sauf = {x for x in fh.read().split("\n") if x}
        n = ecrit(rac, sauf)
        print(f"[regime] empreintes de clôture réécrites : {n} fichier(s) → {os.path.join(rac, MANIFESTE)}")
        return 0
    if cmd == "pose":
        if len(args) != 2:
            raise Refus("pose <racine> <amorce> : deux arguments.")
        conflits, copies, egaux = pose(rac, os.path.realpath(args[1]))
        if conflits:
            print(f"[regime] ⛔ {len(conflits)} conflit(s) : un fichier en place diffère de sa version "
                  f"livrée, ou n'est pas un fichier. RIEN n'a été écrit.", file=sys.stderr)
            for rel in conflits:
                print(f"    {rel}", file=sys.stderr)
            return 1
        print(f"[regime] livré : {copies} fichier(s) copié(s), {egaux} déjà en place à l'identique ; "
              f"état livré écrit → {os.path.join(rac, LIVRE)}")
        return 0
    if cmd == "livre":
        ecarts, n, tenus = livre_ecarts(rac)
        if n == 0:
            print(f"[regime] aucun état livré sous {os.path.join(rac, LIVRE)}", file=sys.stderr)
            return 1
        for rel in tenus:
            print(f"gardé\t{rel}")
        for rel, etat in ecarts:
            print(f"{etat}\t{rel}")
        return 1 if ecarts else 0
    print(f"[regime] commande inconnue : {cmd}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Refus as e:
        print(f"[regime] ⛔ {e}", file=sys.stderr)
        sys.exit(2)
