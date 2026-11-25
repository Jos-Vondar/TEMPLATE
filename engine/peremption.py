#!/usr/bin/env python3
"""peremption.py — ce qui a périmé dans les fichiers VIVANTS d'un niveau.

Lancé par la compétence `tri-des-fils`, étape 2 ; lecture seule, n'écrit rien. Trois familles :

  1. REFS FERMÉES — un `u-…` ou `d-…` cité alors qu'aucun ETAT.md du parc ne le porte plus
     (soldé, abandonné, remplacé, versé), ou qu'aucun journal ne le connaît (introuvable).
  2. RENVOIS GELÉS — un fichier vivant qui renvoie à un MEMORY.md ou un ARCHIVE.md de niveau, gelés.
  3. ÉCHÉANCES PASSÉES — une date précédée d'un mot d'échéance (« avant le », « jusqu'au »,
     « à la consultation du »…) et antérieure à aujourd'hui.

Une ligne qui dit elle-même l'état — « soldé », « remplacé », « gelé », « [archive] » — passe : nommer
une chose close POUR DIRE qu'elle est close est ce qu'on veut lire (même nuance que le contrôle 27bis
de weekly-check.sh).

Usage : python3 ~/.claude/engine/peremption.py <dossier du niveau>
Sortie : un bloc par famille, `chemin:ligne → constat` ; rc 0 si le balayage a tourné, 2 sinon.
"""
import datetime
import json
import os
import re
import subprocess
import sys

H = os.path.expanduser("~")


def racines():
    """Les racines du parc, par `claudeos_racines` de `config.sh` — source unique, comme pour
    `etat.py` : les dépôts en régime GitHub, `~/.claude` seul sans git. Barre finale : une racine
    peut être un lien. Rend (liste, None) ou (None, la raison de l'échec)."""
    cfg = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.sh")
    r = subprocess.run(["bash", "-c", f'source "{cfg}"; claudeos_racines'],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None, f"claudeos_racines a échoué ({cfg}) : {r.stderr.strip()[:200]}"
    return [l.rstrip("/") + "/" for l in r.stdout.splitlines()
            if l.strip() and os.path.isdir(l)], None

REF = re.compile(r"(?<![\w/.-])([ud]-[a-z0-9]+(?:-[a-z0-9]+)+)(?![\w-])")
GELE = re.compile(r"(?<![\w/.-])(?:(?:[\w.-]+/)*)(MEMORY|ARCHIVE)\.md\b")
ECHEANCE = re.compile(
    r"(avant le|jusqu['’]au|d['’]ici (?:le|au)|au plus tard (?:le )?|prévue? (?:le|pour le)|"
    r"à revoir (?:le|au|à la [\wé ]+ du)|à (?:la |le )?(?:consultation|rendez-vous|rdv|séance) du|"
    r"échéance(?: du| le| :)?|à faire (?:le|avant le))\s*(20\d\d-\d\d-\d\d)", re.I)
# Second cas d'échéance : « à revoir avant S13, à la lumière de la
# consultation du 2026-11-02 » — l'attente et la date sont dans la ligne sans se toucher.
EN_ATTENTE = re.compile(r"\bà (?:revoir|dire|faire|trancher|confirmer|décider|reprendre)\b|en attente|reste à", re.I)
PROVENANCE = re.compile(r"(?:décision|décidée?|trouvée?s?|lue?s?|mesurée?s?|vue?s?|constatée?s?|relevée?s?|"
                        r"écrite?s?|posée?s?|arbitrage|journal|séance|depuis)\s+(?:du|le|au)?\s*$", re.I)
DATE = re.compile(r"(?<!\d)(20\d\d-\d\d-\d\d)(?!\d)")
DIT_SON_ETAT = re.compile(r"sold[ée]|abandonn|remplac|fermé|versé|retiré|gel[ée]|\[archive\]|"
                          r"historique|récit|déplacé|\b(?:était|avait|vivait|portait|disait|annonçait|prescrivait|pointait|"
                          r"renvoyait|citait|tenait)\b", re.I)   # un imparfait raconte ; « serait » ne raconte pas
EXTS = (".md", ".sh", ".py", ".yaml", ".yml")
# Instantanés datés (audits, plans, rapports) et dépôts d'outil : ils racontent un état passé, c'est leur
# métier ; et le cache des greffons noierait le balayage.
EXCLUS = {"journal", "_IGNORE", "extracted", ".git", "node_modules", "rapports", "audits",
          "plans", "specs", "plugins", "projects", "cache", "todos", "shell-snapshots", "file-history",
          "session-env", "statsig", "ide", "__pycache__", "backups", "downloads"}
remplacee = {}   # ref → l'événement qui l'a remplacée par une autre ref


def vivants(niv):
    """Fichiers vivants du niveau, sans descendre dans un sous-niveau (qui a son propre ETAT.md)."""
    for d, dirs, files in os.walk(niv):
        if d != niv and os.path.exists(os.path.join(d, "ETAT.md")):
            dirs[:] = []
            continue
        dirs[:] = [x for x in dirs if x not in EXCLUS and not (x.startswith(".") and x != ".claude")]
        for f in files:
            p = os.path.join(d, f)
            # Un lien (`.claude/rules/*.md` vers une couche de domaine) appartient à sa cible, pas au niveau.
            if os.path.islink(p) or not f.endswith(EXTS) or f in ("ETAT.md", "MEMORY.md", "ARCHIVE.md") or re.match(r"20\d\d-\d\d-\d\d", f):
                continue
            try:
                txt = open(p, encoding="utf-8").read()
            except (OSError, UnicodeDecodeError):
                continue
            if txt.startswith("> **GELÉ"):
                continue
            yield p, txt


def index_refs(liste):
    """ref → niveaux (dossiers) dont le journal la connaît ; et ref → dernier événement."""
    global remplacee
    niveaux, dernier = {}, {}
    for r in liste:
        for d, dirs, files in os.walk(r):
            dirs[:] = [x for x in dirs if x not in ("_IGNORE", ".git", "node_modules", "extracted")]
            if os.path.basename(d) != "journal":
                continue
            niv = os.path.dirname(d)
            for f in files:
                if not f.endswith(".jsonl"):
                    continue
                for l in open(os.path.join(d, f), encoding="utf-8"):
                    try:
                        e = json.loads(l)
                    except ValueError:
                        continue
                    for k in ("ref", "remplace"):
                        ref = e.get(k)
                        if ref:
                            niveaux.setdefault(ref, set()).add(niv)
                    if e.get("remplace") and e.get("remplace") != e.get("ref"):
                        remplacee[e["remplace"]] = e
                    ref = e.get("ref")
                    if ref and str(e.get("ts", "")) >= str(dernier.get(ref, {}).get("ts", "")):
                        dernier[ref] = e
    return niveaux, dernier


def ouverte(ref, niveaux, etats):
    for niv in niveaux.get(ref, ()):
        if niv not in etats:
            try:
                etats[niv] = open(os.path.join(niv, "ETAT.md"), encoding="utf-8").read()
            except OSError:
                etats[niv] = ""
        if f"`{ref}`" in etats[niv]:
            return True
    return False


def main():
    if len(sys.argv) != 2 or not os.path.isdir(sys.argv[1]):
        print("usage : peremption.py <dossier du niveau>", file=sys.stderr)
        return 2
    niv = os.path.abspath(sys.argv[1])
    today = datetime.date.today().isoformat()
    liste, raison = racines()
    if raison:
        print(f"[peremption] {raison} — balayage sans valeur.", file=sys.stderr)
        return 2
    niveaux, dernier = index_refs(liste)
    if not niveaux:
        print("[peremption] aucun journal lu sur le parc — balayage sans valeur.", file=sys.stderr)
        return 2
    etats, refs, geles, dates, nfic = {}, [], [], [], 0
    for p, txt in vivants(niv):
        nfic += 1
        rel = os.path.relpath(p, niv)
        for i, l in enumerate(txt.splitlines(), 1):
            if DIT_SON_ETAT.search(l):
                continue
            for m in REF.finditer(l):
                ref = m.group(1)
                if ref not in niveaux:
                    refs.append(f"{rel}:{i} → {ref} introuvable dans tous les journaux du parc")
                elif not ouverte(ref, niveaux, etats) and not (
                        ref not in remplacee and dernier.get(ref, {}).get("op") == "verse"):
                    # Une décision VERSÉE vit dans sa source de vérité : la citer y est sa provenance.
                    r = remplacee.get(ref)
                    e = r or dernier.get(ref, {})
                    quoi = f"remplacé par {r['ref']}" if r else f"{e.get('type', '?')} {e.get('op', '')}".strip()
                    refs.append(f"{rel}:{i} → {ref} n'est plus ouvert ({quoi} le {str(e.get('ts', '?'))[:10]})")
            for m in GELE.finditer(l):
                if "memory/MEMORY.md" in m.group(0):   # l'index de mémoire automatique est vivant
                    continue
                geles.append(f"{rel}:{i} → renvoie à {m.group(0)}, gelé — pointer ETAT.md ou le journal")
            vues = set()
            for m in ECHEANCE.finditer(l):
                if m.group(2) < today:
                    vues.add(m.group(2))
                    dates.append(f"{rel}:{i} → « {m.group(0).strip()} », échéance passée")
            a = EN_ATTENTE.search(l)
            if a:
                # Seule une date qui SUIT l'attente, et qui n'est pas une date de PROVENANCE, la borne.
                # Faux positifs écartés : « Décision du 2026-10-18 … à revoir avant S13 » (date avant
                # l'attente), « à confirmer … trouvée le 2026-11-01 » (provenance).
                for m in DATE.finditer(l, a.end()):
                    d = m.group(1)
                    if d < today and d not in vues and not PROVENANCE.search(l[max(0, m.start() - 25):m.start()]):
                        dates.append(f"{rel}:{i} → attente « {a.group(0)} » liée au {d}, passé")
    print(f"[peremption] {os.path.relpath(niv, H)} — {nfic} fichier(s) vivant(s) balayé(s), "
          f"{len(niveaux)} ref(s) connues du parc, au {today}.")
    for titre, lst in (("1. Refs fermées ou introuvables", refs),
                       ("2. Renvois vers un fichier gelé", geles),
                       ("3. Échéances passées", dates)):
        print(f"{titre} : {len(lst) or 'aucun'}")
        for x in sorted(set(lst)):
            print(f"   {x}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
