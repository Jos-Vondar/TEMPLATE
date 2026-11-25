#!/usr/bin/env python3
"""Tableau de la passe mensuelle — les données de l'artefact visuel d'`os-audit`, étape 6.

Usage : tableau-audit.py --condense audits/os-audit-AAAA-MM-JJ.md --sortie <page.html>
        tableau-audit.py --condense … --json        # les données seules, pour contrôle

POURQUOI : l'utilisateur lit la passe en trente minutes ; une page lui montre d'un coup d'œil où
l'information pourrit et où les fils s'entassent. La page s'écrit en local ; la publier est un
geste à part, que l'étape 6 d'`os-audit` soumet à l'accord de l'utilisateur.

AUCUN JUGEMENT ICI, ET AUCUN CALCUL RECOPIÉ. Le script COMPTE ce que d'autres ont établi :
  - les quatre modes — [faux] [trop] [manquant] [contradictoire] — se lisent dans le CONDENSÉ, où la
    passe les a posés. Couche « jugé » : sections Frictions et Jugement. Couche « machine » : section
    Avertissements mécaniques, plus les fils dormants, comptés ici comme un signal [trop] ;
  - les fils viennent d'`etat.py fils --tous --json`, seule implantation de l'âge et de la dormance ;
  - les indicateurs I1 à I3 se lisent dans le tableau de chaque condensé, colonne « Ce mois » ;
  - les ratés de routage depuis la passe précédente, dans `memory/ROUTING_MISSES.md`, par compétence ;
  - les dus ouverts par chaque passe, ligne « Dus ouverts par la passe » du condensé, et leur sort au
    journal. Un condensé sans cette ligne est dit « non mesuré ».

CE QUI NE SORT PAS : le TEXTE d'un dû, d'un constat ou d'une friction. Une page publiée quitte le
poste, et un texte peut porter du confidentiel. Des comptes, des noms de niveau, des identifiants
de fil.
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys

ICI = os.path.dirname(os.path.abspath(__file__))
SYS = os.path.dirname(ICI)
sys.path.insert(0, ICI)
import etat  # noqa: E402 — niveaux_tous et lit_evenements, sans réimplémenter le discriminant

MODES = ("faux", "trop", "manquant", "contradictoire")
RE_TAG = re.compile(r"\[(faux|trop|manquant|contradictoire)[^\]]*\]")
RE_NOMBRE = re.compile(r"\d+(?:[   ]\d{3})*(?:[.,]\d+)?")
RE_DATE = re.compile(r"os-audit-(\d{4}-\d{2}-\d{2})")
# En-têtes de section du gabarit de condensé (`os-audit/SKILL.md`, étape 5). Une section court
# jusqu'à l'en-tête suivant.
SECTIONS = {"Avertissements mécaniques": "machine", "Frictions du mois": "juge",
            "Jugement sur le travail": "juge"}
AUTRES = ("Seuil", "Veille", "Choisi par", "Écarté", "Dus ouverts par la passe", "|", "#")


def condenses():
    """Tous les condensés, dans l'ordre des passes : date du nom, puis le nom entier."""
    fs = glob.glob(os.path.join(SYS, "audits", "os-audit-*.md"))
    return sorted((f for f in fs if RE_DATE.search(f)),
                  key=lambda f: (RE_DATE.search(f).group(1), os.path.basename(f)))


def nombre(cellule):
    m = RE_NOMBRE.search(cellule or "")
    if not m:
        return None
    return float(re.sub(r"[   ]", "", m.group(0)).replace(",", "."))


def indicateurs(texte):
    """{I1: (précédente, ce mois)} — la précédente sert à voir une RUPTURE de définition."""
    out = {}
    for ligne in texte.splitlines():
        m = re.match(r"\|\s*(I[123])\b", ligne)
        if m:
            cols = [c.strip() for c in ligne.strip().strip("|").split("|")]
            if len(cols) >= 3:
                out[m.group(1)] = (nombre(cols[1]), nombre(cols[2]))
    return out


def series(passes):
    """Une série par indicateur. RUPTURE quand la « précédente » d'un condensé s'écarte de plus de
    1 % du « ce mois » du condensé d'avant : la définition a changé, et relier les deux points
    dessinerait une chute qui n'a pas eu lieu."""
    out = {}
    for k in ("I1", "I2", "I3"):
        pts, avant = [], None
        for p in passes:
            v = p["indicateurs"].get(k)
            if not v or v[1] is None:
                continue
            prec, cour = v
            rupture = bool(avant is not None and prec and abs(prec - avant) > 0.01 * abs(avant))
            pts.append({"passe": p["passe"], "valeur": cour, "rupture": rupture})
            avant = cour
        out[k] = pts
    return out


def modes(texte):
    """Tags comptés par ÉLÉMENT — une puce « - » et ses lignes de suite, ou une ligne d'en-tête.
    Un élément qui porte « **corrigé** » compte aussi dans `corriges` : corrigé dans la passe."""
    compte = {c: {m: 0 for m in MODES} for c in ("juge", "machine")}
    corr = {c: {m: 0 for m in MODES} for c in ("juge", "machine")}
    couche, elements = None, []
    for ligne in texte.splitlines():
        tete = ligne.lstrip()
        neuve = next((c for nom, c in SECTIONS.items() if tete.startswith(nom)), None)
        if neuve or tete.startswith(AUTRES):
            couche = neuve
            elements.append([couche, ligne])
        elif couche and tete.startswith("- "):
            elements.append([couche, ligne])
        elif couche and elements:
            elements[-1][1] += "\n" + ligne
    for c, txt in elements:
        if not c:
            continue
        fait = "**corrigé" in txt.lower()
        for m in RE_TAG.finditer(txt):
            compte[c][m.group(1)] += 1
            corr[c][m.group(1)] += fait
    return compte, corr


def choix(texte):
    """Options choisies (liste numérotée sous « Choisi par ») et dus ouverts par la passe."""
    n, dedans, refs = 0, False, None
    for ligne in texte.splitlines():
        if ligne.startswith("Choisi par"):
            dedans = True
            continue
        if dedans:
            if re.match(r"\s*\d+\.\s", ligne):
                n += 1
            elif ligne.strip() and not ligne.startswith(" "):
                dedans = False
        if ligne.startswith("Dus ouverts par la passe"):
            refs = re.findall(r"`([udp]-[a-z0-9-]+)`", ligne)
    return n, refs


def sort_des_refs(refs, ouverts):
    if not refs:
        return {}
    voulu, sort = set(refs), {}
    for niv in etat.niveaux_tous():
        for e in etat.lit_evenements(niv):
            if e.get("ref") in voulu and e.get("type") == "du" and e.get("op") in ("fait", "abandonne"):
                sort[e["ref"]] = "solde" if e["op"] == "fait" else "abandonne"
    return {r: ("ouvert" if r in ouverts else sort.get(r, "introuvable")) for r in refs}


def rates(depuis, jusqua):
    """Ratés de routage datés après `depuis` et jusqu'à `jusqua`, par compétence du 4e champ."""
    competences = {os.path.basename(os.path.dirname(p))
                   for p in glob.glob(os.path.join(SYS, "skills", "*", "SKILL.md"))}
    chemin = os.path.join(SYS, "memory", "ROUTING_MISSES.md")
    compte = {}
    try:
        lignes = open(chemin, encoding="utf-8").read().splitlines()
    except OSError:
        return None
    for ligne in lignes:
        m = re.match(r"(\d{4}-\d{2}-\d{2})", ligne)
        if not m or not depuis < m.group(1) <= jusqua:
            continue
        champs = ligne.split(" · ")
        cible = champs[3] if len(champs) >= 4 else ligne
        noms = [t for t in re.findall(r"`([a-z0-9:-]+)`", cible) if t in competences]
        for t in dict.fromkeys(noms):
            compte[t] = compte.get(t, 0) + 1
    return dict(sorted(compte.items(), key=lambda kv: -kv[1]))


def fils():
    r = subprocess.run([sys.executable, os.path.join(ICI, "etat.py"), "fils", "--tous", "--json"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"[tableau] etat.py fils --json a échoué : {r.stderr.strip()[:200]}")
    return json.loads(r.stdout)


def par_niveau(lignes):
    out = {}
    for l in lignes:
        t = out.setdefault(l["niveau"], {"moins30": 0, "de30a60": 0, "plus60": 0,
                                         "dormants": 0, "inferes": 0})
        a = l["age"]
        t["moins30" if a < 30 else "de30a60" if a <= 60 else "plus60"] += 1
        t["dormants"] += l["dormant"]
        t["inferes"] += l["infere"]
    return dict(sorted(out.items(), key=lambda kv: -sum(kv[1][k] for k in ("moins30", "de30a60", "plus60"))))


def donnees(condense):
    tous = condenses()
    courant = os.path.abspath(condense)
    if courant not in map(os.path.abspath, tous):
        tous.append(courant)
    texte = open(courant, encoding="utf-8").read()
    i = [os.path.abspath(f) for f in tous].index(courant)
    precedent = RE_DATE.search(tous[i - 1]).group(1) if i > 0 else "0000-00-00"
    lignes = fils()
    ouverts = {l["ref"] for l in lignes}
    m, corriges = modes(texte)
    dormants = sum(l["dormant"] for l in lignes)
    if dormants:
        m["machine"]["trop"] += 1
    titre = texte.splitlines()[0] if texte else ""
    passes = []
    for f in tous[: i + 1]:
        t = open(f, encoding="utf-8").read()
        n, refs = choix(t)
        passes.append({"passe": os.path.basename(f)[len("os-audit-"):-3],
                       "indicateurs": indicateurs(t), "choisies": n,
                       "dus": sort_des_refs(refs, ouverts) if refs is not None else None})
    return {
        "passe": RE_DATE.search(courant).group(1),
        "poste": titre.split("poste", 1)[1].strip() if "poste" in titre else None,
        "precedente": precedent if i > 0 else None,
        "modes": m,
        "corriges": corriges,
        "dormants": dormants,
        "fils": {"total": len(lignes), "dormants": dormants,
                 "plus30": sum(l["age"] > 30 for l in lignes),
                 "inferes": sum(l["infere"] for l in lignes), "niveaux": par_niveau(lignes)},
        "rates": rates(precedent, RE_DATE.search(courant).group(1)),
        "indicateurs": series(passes),
        "passes": [{k: v for k, v in p.items() if k != "indicateurs"} for p in passes
                   if p["choisies"] or p["dus"] is not None][-6:],
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--condense", required=True)
    p.add_argument("--sortie")
    p.add_argument("--gabarit", default=os.path.join(SYS, "skills", "os-audit", "TABLEAU.html"))
    p.add_argument("--json", action="store_true")
    a = p.parse_args()
    d = donnees(a.condense)
    if a.json or not a.sortie:
        print(json.dumps(d, ensure_ascii=False, indent=1))
        return 0
    page = open(a.gabarit, encoding="utf-8").read()
    if "/*__DONNEES__*/null" not in page:
        sys.exit("[tableau] marqueur /*__DONNEES__*/null absent du gabarit — rien d'écrit.")
    # `</` échappé : une donnée ne doit jamais pouvoir refermer la balise script.
    page = page.replace("/*__DONNEES__*/null", json.dumps(d, ensure_ascii=False).replace("</", "<\\/"))
    with open(a.sortie, "w", encoding="utf-8") as h:
        h.write(page)
    print(f"[tableau] {a.sortie} — passe {d['passe']}, {d['fils']['total']} fils sur "
          f"{len(d['fils']['niveaux'])} niveaux.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
