#!/usr/bin/env python3
"""lib_tri.py — date du dernier tri des fils d'un niveau. SOURCE UNIQUE du calcul.

Lu par `boot-check.sh` (échéance du bilan de session de projet, fils tenus trop souvent) et par la
passe mensuelle (`skills/os-audit/HYGIENE.md`, filet des dormants) : deux implantations du même
calcul dérivent, une seule vit ici.

Les événements, écrits par la compétence `tri-des-fils`, sont des `observation` du journal du niveau :
  - `o-tri-fils`          — un tri complet, chaque fil ouvert a eu son verdict ;
  - `o-tri-fils-reporte`  — un report décidé par l'utilisateur : il repousse l'échéance
    du bilan, il ne compte PAS comme un tri pour la passe mensuelle.
Un tri interrompu n'écrit rien : l'échéance reste due.

CLI : python3 ~/.claude/engine/lib_tri.py <niveau> [<niveau> …]
      → une ligne par niveau : dernier tri complet, dernier report, âge en jours.
"""
import datetime
import glob
import json
import os
import re
import sys

SEUIL_TRI_JOURS = 7       # jours calendaires : au-delà, le bilan dit « Tri des fils : DÛ »
FILET_MENSUEL_JOURS = 30  # jours calendaires : un niveau trié dans ce délai sort du filet de HYGIENE.md
PREFIXE = "o-tri-fils"            # la ref porte le sujet, la date est dans le ts (memoire-et-verite)
PREFIXE_REPORT = "o-tri-fils-reporte"


def derniers(niv, aujourdhui=None):
    """Rend (dernier tri complet, dernier report) en dates ISO, ou None. Un ts futur est ignoré."""
    today = (aujourdhui or datetime.date.today()).isoformat()
    tri = report = None
    for f in glob.glob(os.path.join(niv, "journal", "*.jsonl")):
        with open(f, encoding="utf-8", errors="replace") as fh:
            for l in fh:
                try:
                    e = json.loads(l)
                except ValueError:
                    continue
                if not isinstance(e, dict):
                    continue
                ref, d = str(e.get("ref", "")), str(e.get("ts", ""))[:10]
                if not (ref == PREFIXE or ref.startswith(PREFIXE + "-")) or len(d) != 10 or d > today:
                    continue
                try:
                    datetime.date.fromisoformat(d)
                except ValueError:
                    continue
                if ref == PREFIXE_REPORT or ref.startswith(PREFIXE_REPORT + "-"):
                    report = max(report or d, d)
                else:
                    tri = max(tri or d, d)
    return tri, report


SEUIL_RECONDUIT = 3  # tris complets où un fil reçoit « tenir » : à ce compte, attaquer l'obstacle


def reconduits(niv):
    """Rend {ref: nombre de tris complets où le fil a été tenu}, lu dans « tenus : … » du texte."""
    n = {}
    for f in glob.glob(os.path.join(niv, "journal", "*.jsonl")):
        with open(f, encoding="utf-8", errors="replace") as fh:
            for l in fh:
                try:
                    e = json.loads(l)
                except ValueError:
                    continue
                if not isinstance(e, dict) or e.get("ref") != PREFIXE:
                    continue
                m = re.search(r"tenus?\s*:\s*([^;]*)", str(e.get("texte", "")), re.I)
                for ref in set(re.findall(r"\bu-[a-z0-9-]+", m.group(1) if m else "")):
                    n[ref] = n.get(ref, 0) + 1
    return n


def age(d, aujourdhui=None):
    return None if d is None else ((aujourdhui or datetime.date.today()) - datetime.date.fromisoformat(d)).days


def main(args):
    if not args:
        print(__doc__.split("CLI : ", 1)[1].strip(), file=sys.stderr)
        return 2
    for niv in args:
        if not os.path.isfile(os.path.join(niv, "ETAT.md")):
            print(f"{niv} : pas un niveau (aucun ETAT.md)")
            continue
        tri, rep = derniers(niv)
        print(f"{niv} : dernier tri complet {tri or 'jamais'}"
              + (f" (il y a {age(tri)} j)" if tri else "")
              + f" ; dernier report {rep or '—'}"
              + (" ; DANS le filet mensuel" if tri is None or age(tri) > FILET_MENSUEL_JOURS else " ; hors filet mensuel"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
