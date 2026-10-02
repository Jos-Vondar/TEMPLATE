#!/usr/bin/env python3
"""etat.py — le SEUL chemin d'écriture de l'état d'un niveau.

Le contrat est transcrit ci-dessous ; les écarts décidés à l'écriture sont marqués ÉCART.

LE PRINCIPE, et tout découle de lui : un état ne se réécrit jamais, il s'AJOUTE. Le journal
`<niveau>/journal/AAAA-MM.jsonl` est append-only ; `ETAT.md` en est une PROJECTION, jamais
une source. Éditer `ETAT.md` à la main est un défaut que le crochet refuse (code 23).

  add       ajoute un événement validé. REFUSE (code 2) tout événement incomplet, en nommant
            le champ manquant — il n'écrit jamais un événement partiel. REFUSE aussi (même
            code) un RETRAIT dont la cible est absente de la projection courante : il
            s'écrirait sans rien faire sortir de `ETAT.md`, et sans un mot.
  projette  réécrit `<niveau>/ETAT.md` depuis le journal entier.
  check     0 ok · 22 ligne passée modifiée ou id dupliqué · 23 ETAT.md ≠ projection
  stats     somme des compteurs de séance depuis une date, « non relu » compté à part
  vue       « Ce qui reste » + « État courant » de tous les niveaux
  Bibliothèque standard SEULE. Le système ne dépend que de bash et python, plus git en régime
  GitHub : SANS GIT, la racine et la garde append-only passent par `regime.py`, à côté.

DEUX ÉCARTS DÉCIDÉS À L'ÉCRITURE, tous deux pour ne pas fabriquer un contrôle menteur :

ÉCART 1 — le pied de page ne se compare PAS octet à octet.
Le plan prescrit un pied « projeté le AAAA-MM-JJ depuis N événements · M caractères ». Comparé
tel quel, le crochet crierait le LENDEMAIN (code 23) de chaque projection, sans qu'on ait touché à
rien : la date change, donc la projection diffère. Un contrôle qui crie tous les jours apprend
à ignorer sa catégorie entière — c'est écrit trois fois dans ce dépôt. Donc `check` compare le
CORPS intégralement, et du pied il ne compare que `N` et `M`. La date reste écrite, elle
informe le lecteur ; elle n'entre pas dans le verdict.

ÉCART 2 — `check --staged` exige un PRÉFIXE, pas une inclusion.
Le plan dit « toute ligne de HEAD absente ou modifiée en file → 22 ». Implémenté en préfixe :
les N premières lignes de la version en file doivent être EXACTEMENT celles de `HEAD`. C'est
plus strict, et volontairement — ça attrape aussi le réordonnancement, qu'une comparaison
d'ensembles laisserait passer. Réserve nommée : après un `merge` avec `merge=union`, l'ordre
peut ne plus préserver le préfixe. C'est pourquoi le filet d'après-`pull` (`claudeos-sync.sh`)
appelle `check` SANS `--staged` — lui cherche le doublon d'`id`, qui est le dégât réel d'une
fusion en union.

CODES DE SORTIE, et ils sont lus par le crochet `pre-commit` :
  0  conforme
  2  événement refusé — champ manquant, valeur hors contrat, ou retrait sur une cible absente
  22 journal réécrit : ligne passée modifiée, retirée, réordonnée, ou `id` dupliqué
  23 `ETAT.md` diffère de sa projection
  1  erreur d'usage ou d'environnement (dit laquelle ; ne se confond pas avec un verdict)
"""
import argparse
import glob
import json
import os
import re
import secrets
import socket
import subprocess
import sys
from datetime import datetime, timezone

import regime   # le régime sans git, propre au template (`d-regime-sans-git`)

# --- Le contrat § 3.1, transcrit. Une seule table, lue par la validation ET par l'aide :
# deux copies auraient divergé au premier champ ajouté.
OPS = {
    "decision": ("pose", "remplace", "verse"),
    "du": ("ouvre", "fait", "abandonne", "remplace"),
    "pointeur": ("ajoute", "retire"),
    "etat": ("avance", "ferme"),
    "seance": (),
    "observation": (),
}
PREFIXE_REF = {"decision": "d-", "du": "u-", "pointeur": "p-"}
# `motif` est dû sur ces trois opérations : elles retirent quelque chose de l'état projeté, et
# un retrait sans motif est indistinguable d'un oubli.
OPS_A_MOTIF = {"abandonne", "remplace", "retire", "verse"}
# UNE SORTIE POUR `decision`, POSÉE LE 2026-09-22 sur arbitrage de l'utilisateur, après mesure.
# CE QUI MANQUAIT, et c'est structurel : `du` avait `fait` et `abandonne`, `pointeur` avait
# `retire`, `etat` avait `ferme` — `decision` n'avait RIEN. Le compte des décisions projetées ne
# pouvait donc que MONTER, par construction : 13 le 2026-09-08, 48 le 2026-09-22, soit 64 poses
# pour 16 remplacements en quatorze jours. Reconstruit jour par jour sur le journal.
# `verse` DIT OÙ VA LE CONTENU — `--source` est DÛ, au même titre que `--motif` : une décision qui
# sort sans destination est une décision perdue, pas une décision rangée. La destination type est
# `DESIGN.md « <nom de section> »` ou le document de référence du projet, c'est-à-dire la maison que la règle de tri lui
# donne. L'événement reste au journal ; seule la projection s'allège.
# POURQUOI PAS `remplace` VERS RIEN : `remplace` exige une ref NEUVE qui prend la place. Verser,
# c'est sortir sans successeur — deux gestes différents, deux ops.
# FUSION N→1 : `--remplace` accepte désormais PLUSIEURS refs séparées par une virgule. Avant, il
# n'en portait qu'une, donc fusionner trois décisions en une laissait les deux autres orphelines
# À JAMAIS — il n'existait aucun geste pour les sortir.
# Longueur maximale d'un `texte`, en CARACTÈRES — voir le motif à la validation.
TEXTE_MAX = 4500
# DORMANCE — pose le 2026-09-15 sur decision de l'utilisateur. Un du dont le DERNIER evenement
# date de plus de N jours DORT : il sort de la liste de `fils` et du bilan de demarrage.
# POURQUOI LE DERNIER TOUCHER ET NON LA NAISSANCE : les vraies dates de naissance sont PERDUES
# — les depots ne sont sous git que depuis le 2026-08-22, et 94 ages sur 268 sont inferes de la
# plus vieille date du TEXTE. Le dernier toucher, lui, est le `ts` d'un evenement : mesure, jamais
# devine. POURQUOI C'EST UNE REGLE DE LECTURE ET NON DE PROJECTION : `ETAT.md` deviendrait
# dependant de la date, donc `check` crierait (code 23) le jour ou un du franchit le seuil sans
# que personne ait touche a rien — exactement l'ECART 1 de ce fichier. Donc `projette`, `check`
# et `ETAT.md` ne bougent PAS d'un octet, et aucun evenement n'est ecrit : un du se reveille des
# qu'on ecrit dessus, et le compte en pied de `fils` empeche de l'oublier.
DORMANT_JOURS = 30
# ANGLE MORT DE `DORMANT_JOURS`, MESURE LE 2026-09-22 A L'AUDIT OPUS, et ferme ici sur arbitrage
# de l'utilisateur. `dormant` se compte depuis le DERNIER TOUCHER, ce qui est le bon sens du mot :
# un du retravaille hier n'est pas dormant, quel que soit son age. MAIS la bascule du 2026-09-09 a
# reemis 241 dus en `ouvre` LE MEME JOUR, donc elle a remis 241 horloges a zero d'un coup : le
# mecanisme ne pouvait plus rien signaler avant le 2026-10-09, pendant que 40 dus depassaient
# reellement 30 jours d'AGE. Et le message « aucun du dormant » se lisait comme « rien n'est
# vieux » — un vert par construction, la famille de defaut que ce fichier traque partout ailleurs.
# LE REMEDE N'EST PAS DE CHANGER LE SENS DE `dormant` : c'est de NOMMER l'autre compte a cote, pour
# qu'un zero ne puisse plus se lire comme deux. L'age, lui, est deja calcule — explicite par
# `origine`, sinon INFERE de la plus vieille date du texte et marque d'un tilde. Chemin ajoute a un
# controle existant, jamais un controle neuf (`controles-et-alarmes`, marche 2).
VIEUX_JOURS = 30
# BORNE PAR TYPE SUR CE QUI EST *PROJETÉ*, posée le 2026-09-10 sur décision de l'utilisateur.
# `TEXTE_MAX` ci-dessus est un filet contre la substitution de commande ; ceci est autre chose :
# une borne de LISIBILITÉ. Elle ne s'applique qu'aux quatre opérations qui entrent dans `ETAT.md`
# — `decision` pose/remplace, `du` ouvre/remplace, `pointeur` ajoute, `etat` avance. Les autres,
# et surtout `observation` et `seance`, gardent `TEXTE_MAX` : le journal ne pèse RIEN sur la
# projection (mesuré le 2026-09-10 : trois observations de plus de mille caractères écrites
# d'affilée, `ETAT.md` inchangé à 52 288 caractères).
#
# CE QU'ELLE ÉVITE, ET LE SECOND MOTIF EST LE PLUS FORT.
#   1. Le coût. Le règlement fait charger `ETAT.md` EN ENTIER à chaque reprise de niveau. Ce
#      n'est PAS le démarrage : `boot-check.sh` n'en extrait que quatre lignes d'« État courant »
#      tronquées à 120 caractères. Les lignes de 1 700 caractères étaient donc écrites pour un
#      lecteur qui en lit 120.
#   2. LA JUSTESSE. Un texte long CAMOUFLE. Payé le 2026-09-10 sur
#      `<APP>` : un du de dix lignes dont six de leçon de méthode
#      portait deux phrases de fait FAUSSES, et personne ne les a relues — les trois colonnes
#      qu'il déclarait citées nulle part sont patchées deux fois chacune. Un du court se relit ;
#      un du long se croit.
#
# LES VALEURS SONT MESURÉES SUR LES 29 NIVEAUX À JOURNAL, jamais sur un fichier. Le taux de
# refus qu'elles auraient opposé à l'historique est le critère d'admission : assez pour changer
# l'écriture, pas assez pour interdire un fait normal. Le geste qui les remesure :
#   python3 - <<'X'
#   import json,glob,statistics
#   L={}
#   for f in glob.glob(os.path.expanduser('~/*/**/journal/*.jsonl'),recursive=True): pass
#   X
# — plus simplement : parcourir chaque `journal/*.jsonl` et grouper `len(texte)` par type.
# Relevé du 2026-09-10 (médiane · refus opposé à l'historique) : du 359 · 14 % ;
# decision 530 · 28 % ; pointeur 70 · 24 % ; etat/avance 878 · 34 %.
# UNE BAISSE SE RÉÉCRIT ICI. Un relèvement se date et se motive, comme un cliquet.
TEXTE_MAX_PROJETE = {
    ("decision", "pose"): 900,
    ("decision", "remplace"): 900,
    ("du", "ouvre"): 900,
    ("du", "remplace"): 900,
    # Un pointeur est une ADRESSE, pas un exposé : sa médiane est de 70 caractères sur le parc,
    # et les seuls longs sont des récits déposés au mauvais endroit.
    ("pointeur", "ajoute"): 300,
    # Le plus permissif, et c'est assumé : `etat` avance est le seul récit qu'une session lit
    # EN ENTIER en reprenant, et le projecteur n'en garde que le DERNIER par chantier — donc
    # le raccourcir ne demande jamais de retirer quoi que ce soit, seulement d'en écrire un neuf.
    ("etat", "avance"): 1200,
}
RE_ID = re.compile(r"^e-\d{8}-\d{6}-[0-9a-f]{4}$")
RE_SLUG = re.compile(r"^[a-z0-9][a-z0-9-]{1,60}$")

SECTIONS = ("Décisions en vigueur", "Ce qui reste", "Où trouver", "État courant")


def mourir(code, message):
    print(f"[etat] {message}", file=sys.stderr)
    sys.exit(code)


def git(racine, *args, texte=True):
    """Rend (rc, sortie). N'échoue jamais tout seul : l'appelant décide ce qu'une erreur veut dire."""
    try:
        r = subprocess.run(["git", "-C", str(racine), *args],
                           capture_output=True, text=texte, errors="replace")
    except FileNotFoundError:          # git absent du poste : le régime sans git
        return 127, ""
    return r.returncode, (r.stdout if texte else r.stdout)


def racine_depot(chemin):
    # Par git s'il y a un dépôt, sinon par la marque `.claudeos-racine` du régime sans git.
    r = regime.racine(chemin)
    if not r:
        mourir(1, f"« {chemin} » n'est ni dans un dépôt git ni sous une racine marquée "
                  f"{regime.MARQUE_RACINE} — le niveau se résout par l'un ou par l'autre.")
    return r


def niveau_relatif(niveau):
    """Le champ `niveau` du contrat : chemin relatif au dépôt, « . » pour la racine."""
    depot = racine_depot(niveau)
    rel = os.path.relpath(os.path.realpath(niveau), depot)
    return "." if rel == "." else rel.replace(os.sep, "/")


def dossier_journal(niveau):
    return os.path.join(niveau, "journal")


def journaux(niveau):
    return sorted(glob.glob(os.path.join(dossier_journal(niveau), "*.jsonl")))


def lit_evenements(niveau):
    """Tous les événements du niveau, dans l'ordre des fichiers puis des lignes.

    Une ligne illisible ARRÊTE la lecture au lieu d'être sautée : un journal partiellement
    lisible rendrait une projection partielle, qui ressemble à une projection complète.
    """
    evs = []
    for f in journaux(niveau):
        with open(f, encoding="utf-8") as fh:
            for n, ligne in enumerate(fh, 1):
                ligne = ligne.strip()
                if not ligne:
                    continue
                try:
                    evs.append(json.loads(ligne))
                except json.JSONDecodeError as e:
                    mourir(1, f"{f}:{n} — ligne JSON illisible ({e}). "
                              f"Rien n'est projeté sur un journal qu'on ne sait pas lire.")
    return evs


def valide(ev):
    """Rend None si l'événement respecte le contrat, sinon le message qui NOMME le champ."""
    for champ in ("ts", "id", "niveau", "poste", "type", "texte"):
        if not ev.get(champ):
            return f"champ obligatoire manquant : « {champ} »"
    t = ev["type"]
    if t not in OPS:
        return f"type inconnu : « {t} » — attendus : {', '.join(OPS)}"
    if not RE_ID.match(ev["id"]):
        return f"« id » hors forme : « {ev['id']} » — attendu e-AAAAMMJJ-HHMMSS-<4 hex>"
    attendues = OPS[t]
    if attendues:
        if not ev.get("op"):
            return f"champ « op » manquant pour type « {t} » — attendus : {', '.join(attendues)}"
        if ev["op"] not in attendues:
            return f"« op » hors contrat pour « {t} » : « {ev['op']} » — attendus : {', '.join(attendues)}"
    elif ev.get("op"):
        return f"« op » interdit sur type « {t} »"
    # `verse` DIT OÙ VA LE CONTENU, sinon ce n'est pas un rangement, c'est une perte. Le `motif`
    # est déjà dû par `OPS_A_MOTIF` — il dit POURQUOI ; `source` dit OÙ, et les deux sont
    # nécessaires. Refus à l'ÉCRITURE : une fois l'événement au journal append-only, la décision
    # a quitté la projection et plus rien ne dira où la chercher.
    if (t, ev.get("op")) == ("decision", "verse") and not ev.get("source"):
        return ("« source » manquant sur « decision verse » — verser une décision la fait SORTIR "
                "de la projection sans successeur, donc sans « source » plus rien ne dit où son "
                "contenu est parti. Nommer la destination : « DESIGN.md « <section> » » ou le "
                "document de référence du projet. Si la décision n'a plus d'objet et ne va nulle part, ce n'est pas "
                "un versement : employer « --op remplace » vers la décision qui prend sa place.")
    if t in PREFIXE_REF:
        if not ev.get("ref"):
            return f"champ « ref » manquant pour type « {t} »"
        pref = PREFIXE_REF[t]
        if not ev["ref"].startswith(pref) or not RE_SLUG.match(ev["ref"]):
            return f"« ref » hors forme : « {ev['ref']} » — attendu {pref}<slug>"
    if t in ("du", "etat") and not ev.get("chantier"):
        return f"champ « chantier » obligatoire sur type « {t} »"
    if ev.get("chantier") and not RE_SLUG.match(ev["chantier"]):
        return f"« chantier » hors forme : « {ev['chantier']} »"
    if t in ("pointeur", "observation") and not ev.get("source"):
        return (f"champ « source » obligatoire sur « {t} » — un chemin ou une commande, "
                f"JAMAIS une valeur : une valeur recopiée se périme, un chemin non.")
    # BORNE DE LONGUEUR, posée le 2026-09-09. Un accent grave dans une chaîne shell entre
    # guillemets est une SUBSTITUTION DE COMMANDE : la commande citée s'exécute et sa sortie
    # entre dans le texte. Payé le 2026-09-08 — 5 217 caractères de sortie de `weekly-check`
    # partis dans un événement, et le journal étant append-only la faute est PERMANENTE.
    # La borne ne prévient pas la substitution (elle a lieu dans le shell, avant qu'on soit
    # appelé) : elle empêche seulement le résultat d'être ÉCRIT. C'est un filet, pas la
    # protection — la protection est la règle, dans la compétence `reprise`.
    # 4 500 mesuré sur le journal du jour : le plus long texte LÉGITIME fait 3 397 caractères,
    # le seul au-dessus est précisément l'événement pollué.
    if len(ev.get("texte") or "") > TEXTE_MAX:
        return (f"« texte » démesuré : {len(ev['texte'])} caractères pour {TEXTE_MAX} au plus. "
                f"Une sortie de commande a-t-elle été substituée ? Un accent grave dans une "
                f"chaîne entre guillemets EXÉCUTE. Citer la commande sans délimiteur.")
    _borne = TEXTE_MAX_PROJETE.get((t, ev.get("op") or ""))
    if _borne is not None and len(ev.get("texte") or "") > _borne:
        return (f"« texte » trop long pour un {t} « {ev.get('op')} » : "
                f"{len(ev['texte'])} caractères pour {_borne} au plus. Cette opération est "
                f"PROJETÉE dans ETAT.md, lu en entier à chaque reprise de niveau — et un texte "
                f"long camoufle le fait qu'il porte. Garder ici l'énoncé, et verser le récit, "
                f"la méthode et la preuve en « --type observation » : le journal ne pèse RIEN "
                f"sur la projection. Borne baissable dans engine/etat.py, TEXTE_MAX_PROJETE.")
    if ev.get("op") == "remplace" and not ev.get("remplace"):
        return "« remplace » manquant : op « remplace » doit nommer la ref qui sort"
    # UNE REF NE SE REMPLACE PAS PAR ELLE-MEME. Refus a l'ECRITURE, 2026-09-13, sur constat
    # d'une session de projet : `--ref X --remplace X` fait DISPARAITRE X de la projection, en
    # silence, et `check` dit conforme. Le mecanisme est deux lignes plus bas dans `projette` —
    # l'evenement s'ajoute lui-meme a `dus_sortis` (ou `remplacees`), puis s'exclut de sa propre
    # liste. MESURE ICI le meme jour : la disparition frappe les `du` ET les `decision`, le
    # constat d'origine ne nommait que les `du`.
    # Le correctif du 2026-09-08 documente au-dessus de `projette` ne couvre pas ce cas : il a
    # fait reconnaitre `remplace` comme une pose, ce qui repare le remplacement par une ref
    # NEUVE — pas celui par la meme. Le refus vit a la validation et non a la projection, pour
    # la raison deja ecrite pour les pointeurs morts : le journal est append-only, un `projette`
    # qui refuserait rendrait improjetable tout niveau portant deja l'evenement fautif.
    if ev.get("op") == "remplace" and ev.get("ref") and ev.get("ref") == ev.get("remplace"):
        return (f"« ref » et « remplace » sont la meme chose ({ev['ref']}) — l'evenement se "
                f"ferait sortir lui-meme et DISPARAITRAIT de ETAT.md sans alerte. Un "
                f"remplacement porte une reference NEUVE ; l'ancienne va dans « --remplace ». "
                f"Pour reformuler sans renommer, employer « --op ouvre » : le dernier gagne.")
    # « remplace » N'EST ACCEPTÉ QU'AVEC L'OP « remplace ». Posé le 2026-09-17, sur un défaut
    # REPRODUIT et non déduit, remonté par la session <APP> puis élargi ici.
    # LA MÉCANIQUE : `ensembles_de_sortie` remplit `remplacees` ET `dus_sortis` depuis le champ
    # `remplace` de TOUT événement, quel que soit son type et son op. Mais seuls `decisions` et
    # `dus` consultent ces ensembles à la projection. D'où DEUX défauts, mesurés sur un dépôt
    # jetable :
    #   1. `pointeur --op ajoute --remplace <ref>` est accepté, écrit, et NE REMPLACE RIEN —
    #      les deux pointeurs se projettent côte à côte, l'ancien avec son texte périmé.
    #   2. PIRE, et personne ne l'avait vu : `observation --remplace u-xxx` fait SORTIR le dû
    #      `u-xxx` de l'état projeté. Une observation anodine efface un dû, sans un mot.
    # Le contrat `OPS` ne donne l'op `remplace` qu'à `decision` et `du` ; le champ suit l'op, et
    # un champ hors contrat ne doit pas passer en silence. Pour retirer un pointeur : `--op
    # retire` puis `--op ajoute` sous une ref NEUVE — le retrait sort tous les ajouts de la ref.
    if ev.get("remplace") and ev.get("op") != "remplace":
        return (f"« remplace » n'a de sens qu'avec « --op remplace » — reçu sur type "
                f"« {ev.get('type')} », op « {ev.get('op') or 'aucune'} ». Il serait ACCEPTÉ et "
                f"agirait de travers : sur un « pointeur » il ne remplace rien et laisse les deux "
                f"côte à côte ; sur une « observation » il FAIT SORTIR le dû nommé, sans un mot. "
                f"Un pointeur se change par « --op retire » puis « --op ajoute » sous une ref NEUVE.")
    if ev.get("op") in OPS_A_MOTIF and not ev.get("motif"):
        return (f"« motif » manquant sur op « {ev['op']} » — ce qui sort de l'état projeté "
                f"dit pourquoi, sinon un retrait est indistinguable d'un oubli")
    # UN POINTEUR NEUF NE PEUT PAS VISER UNE CIBLE MORTE. Refus à l'ÉCRITURE, geste D1 du plan
    # du 2026-09-10, sur la racine du constat R-2 : la projection réaffirmait deux cibles
    # supprimées la veille, parce qu'un générateur ne connaît pas le disque. Le refus ne peut
    # PAS vivre au `projette` — le journal est append-only, et un `projette` qui refuserait
    # rendrait improjetable tout niveau portant déjà un pointeur mort.
    # LE RÉSOLVEUR EST CELUI DU CONTRÔLE HEBDOMADAIRE 45, importé et non recopié : deux
    # implantations du même calcul dérivent. Il garde son rôle sur les pointeurs DÉJÀ écrits et
    # sur les cibles qui meurent après coup, ce que ce refus ne peut pas voir.
    # `origine` DATE LA NAISSANCE D'UN FIL, pas son evenement. Elle n'a de sens que sur un du
    # qui s'ouvre ou se reformule, et une date FUTURE serait une faute de frappe qui rajeunirait
    # le fil au lieu de le vieillir — donc elle est refusee.
    if ev.get("origine") is not None:
        if t != "du" or ev.get("op") not in ("ouvre", "remplace"):
            return "« origine » n'a de sens que sur un du en « ouvre » ou « remplace »"
        import datetime as _dt
        try:
            _o = _dt.date.fromisoformat(str(ev["origine"])[:10])
        except ValueError:
            return f"« origine » : date ISO AAAA-MM-JJ attendue, reçu « {ev['origine']} »"
        if _o > _dt.date.today():
            return f"« origine » dans le FUTUR ({_o}) — une naissance ne s'annonce pas"
    if t == "pointeur" and ev.get("op") == "ajoute":
        try:
            sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
            import resolveur_pointeurs as _rp
            _j, _nj, _defauts = _rp.juge_cibles(ev.get("source", ""))
        except Exception as _e:
            # Un résolveur injoignable ne DOIT PAS bloquer l'écriture : une plomberie muette
            # coûterait le droit de consigner. Il avertit, et le contrôle 45 reste le filet.
            print(f"[etat] ⚠ résolveur de pointeurs injoignable ({_e}) — cible NON contrôlée, "
                  f"le contrôle hebdomadaire 45 la jugera.", file=sys.stderr)
        else:
            if _defauts:
                return ("cible de pointeur qui ne résout pas — " + " ; ".join(_defauts)
                        + ". Une carte qui envoie dans le vide est pire qu'une carte muette : "
                        "corrige la cible, ou cite un CHEMIN et mets la commande dans le texte.")
    if t == "seance":
        for champ in ("manque_reprise", "manque_declencheur"):
            v = ev.get(champ)
            if v is None:
                return f"champ « {champ} » obligatoire sur une séance (entier ≥ 0, ou « non relu »)"
            if v == "non relu":
                continue
            if not isinstance(v, int) or isinstance(v, bool) or v < 0:
                return (f"« {champ} » : entier ≥ 0 ou la chaîne « non relu ». "
                        f"Une séance dont on n'a pas relu les gestes écrit « non relu », JAMAIS 0.")
    return None


# --------------------------------------------------------------------------- add
def cmd_add(a):
    niveau = os.path.abspath(os.path.expanduser(a.niveau))
    if not os.path.isdir(niveau):
        mourir(1, f"niveau introuvable : {niveau}")
    maintenant = datetime.now().astimezone()
    ev = {
        "ts": maintenant.isoformat(timespec="seconds"),
        "id": f"e-{maintenant:%Y%m%d-%H%M%S}-{secrets.token_hex(2)}",
        "niveau": niveau_relatif(niveau),
        "poste": socket.gethostname(),
        "type": a.type,
    }
    for champ in ("op", "ref", "chantier", "texte", "source", "remplace", "motif", "origine"):
        v = getattr(a, champ, None)
        if v:
            ev[champ] = v
    for champ, brut in (("manque_reprise", a.manque_reprise),
                        ("manque_declencheur", a.manque_declencheur)):
        if brut is None:
            continue
        if brut == "non relu":
            ev[champ] = brut
            continue
        # SANS CE REFUS, `int(brut)` remontait un ValueError NU jusqu'a l'appelant : traceback
        # Python au lieu du « evenement REFUSE » que rendent TOUS les autres champs. Releve le
        # 2026-09-21 par une session de projet, qui avait passe une chaine libre. Un traceback
        # au milieu de refus lisibles se lit comme une panne de l'outil, pas comme une faute de
        # saisie — et il n'apprend pas la valeur attendue.
        try:
            ev[champ] = int(brut)
        except ValueError:
            mourir(2, f"événement REFUSÉ, rien n'est écrit — champ « {champ} » : « {brut} » "
                      f"n'est ni un entier ni « non relu ». Un ENTIER compte les manques relevés, "
                      f"zéro compris ; « non relu » dit qu'on n'a PAS regardé. "
                      f"Ne jamais mettre 0 pour dire qu'on n'a pas regardé.")

    faute = valide(ev)
    if faute:
        mourir(2, f"événement REFUSÉ, rien n'est écrit — {faute}")

    # Le journal est lu UNE fois ici, pour deux contrôles : le garde d'existence des retraits
    # (qui a besoin de l'état projeté courant, ce que `valide` ne connaît pas) et l'unicité de
    # l'`id` dans TOUS les journaux du niveau, pas seulement le mois courant.
    evs_niveau = lit_evenements(niveau)
    faute = garde_existence(ev, evs_niveau, racine_depot(niveau))
    if faute:
        mourir(2, f"événement REFUSÉ, rien n'est écrit — {faute}")

    deja = {e.get("id") for e in evs_niveau}
    while ev["id"] in deja:                      # collision de 4 hex dans la même seconde
        ev["id"] = f"e-{maintenant:%Y%m%d-%H%M%S}-{secrets.token_hex(2)}"

    os.makedirs(dossier_journal(niveau), exist_ok=True)
    cible = os.path.join(dossier_journal(niveau), f"{maintenant:%Y-%m}.jsonl")
    with open(cible, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(ev, ensure_ascii=False, sort_keys=True) + "\n")
    print(f"[etat] {ev['id']} → {os.path.relpath(cible, niveau)}")
    return 0


def refs_remplacees(ev):
    """Les refs qu'un événement fait sortir par « remplace » — UNE SEULE IMPLANTATION.

    Le champ portait UNE ref jusqu'au 2026-09-22 ; il en porte plusieurs, séparées par une
    virgule, depuis la fusion N→1. Les événements anciens n'ont pas de virgule et traversent
    donc inchangés. Ce découpage vit ici et nulle part ailleurs : `ensembles_de_sortie` et
    `garde_existence` l'appellent tous deux, et trois copies du même calcul dérivent au premier
    correctif porté sur une seule — c'est le motif écrit d'`ensembles_de_sortie` juste dessous.
    """
    brut = ev.get("remplace")
    if not brut:
        return []
    return [r.strip() for r in str(brut).split(",") if r.strip()]


# ---------------------------------------------------------------------- projette
def ensembles_de_sortie(evs):
    """Ce que le journal a fait SORTIR de la projection : (remplacees, dus_sortis, retires,
    chantiers_fermes). UNE SEULE IMPLANTATION, extraite le 2026-09-14 : `projette` et `cmd_fils`
    la recopiaient chacun, et le garde d'existence des retraits en aurait été la troisième copie
    — trois copies du même calcul dérivent au premier correctif porté sur une seule, et un garde
    qui dérive de ce qu'il garde ment.
    """
    remplacees, dus_sortis, retires, chantiers_fermes = set(), set(), set(), set()
    for e in evs:
        for _r in refs_remplacees(e):
            remplacees.add(_r)
            dus_sortis.add(_r)
        # UNE DÉCISION VERSÉE SORT, comme une remplacée — mais sans successeur. Son contenu est
        # parti dans la source de vérité que son `source` nomme ; le journal garde tout.
        if e["type"] == "decision" and e.get("op") == "verse":
            remplacees.add(e.get("ref"))
        if e["type"] == "du" and e.get("op") in ("fait", "abandonne"):
            dus_sortis.add(e.get("ref"))
        if e["type"] == "pointeur" and e.get("op") == "retire":
            retires.add(e.get("ref"))
        if e["type"] == "etat" and e.get("op") == "ferme":
            chantiers_fermes.add(e.get("chantier"))
    return remplacees, dus_sortis, retires, chantiers_fermes


def dernier_par_ref(evs):
    """Une ref ne sort qu'UNE fois de la projection, dans sa DERNIÈRE formulation.

    CE QUI REND VRAI le message de refus de `remplace` : « pour reformuler sans renommer,
    employer "--op ouvre" : le dernier gagne ». La projection ne dédupliquait pas, donc elle
    EMPILAIT — deux `ouvre` sur la même ref rendaient deux lignes, la formulation périmée
    juste au-dessus de la neuve, dans le seul fichier qu'une reprise lit EN ENTIER. Muet :
    ni refus, ni avertissement, et l'auteur croit avoir reformulé.

    Relevé le 2026-09-21 depuis DEUX sessions et sur DEUX opérations distinctes — cinq `ouvre`
    empilés côté projet, trois `remplace` sur une ref réutilisée côté système — puis mesuré sur
    le parc : 2 doublons dans <APP>, 4 dans un projet personnel. `courant`
    appliquait déjà « le dernier gagne » pour les chantiers ; il manquait aux trois listes.

    La clef retombe sur l'`id` quand la ref manque, pour qu'un événement sans ref n'en avale
    jamais un autre.
    """
    par_clef = {}
    for e in sorted(evs, key=lambda e: e["ts"]):
        par_clef[e.get("ref") or e["id"]] = e
    return sorted(par_clef.values(), key=lambda e: e["ts"])


def projection_vivante(evs):
    """Ce qui est VISIBLE dans `ETAT.md` : (decisions, dus, pointeurs, courant) — trois listes
    d'événements triées par `ts`, et le dict chantier → dernier `etat avance`.

    D-J appliqué ici et nulle part ailleurs : une décision remplacée SORT, un pointeur dont le
    chantier est fermé SORT. L'histoire n'est pas dans ce fichier — elle est dans le journal.
    """
    remplacees, dus_sortis, retires, chantiers_fermes = ensembles_de_sortie(evs)

    # `remplace` COMPTE COMME UNE POSE, corrigé le 2026-09-08 en s'en servant. Le contrat autorise
    # `remplace` sur `decision` et sur `du`, et le projecteur ne reconnaissait que `pose`/`ouvre` :
    # l'événement de remplacement faisait donc sortir l'ANCIENNE ref sans faire entrer la nouvelle.
    # Les deux disparaissaient, et rien ne le disait — le journal gardait tout, l'état perdait la
    # chose. Le témoin (f) du plan ne l'aurait pas vu : il vérifie seulement que l'ancienne SORT.
    decisions = [e for e in evs
                 if e["type"] == "decision" and e.get("op") in ("pose", "remplace")
                 and e.get("ref") not in remplacees]
    decisions = dernier_par_ref(decisions)

    dus = [e for e in evs
           if e["type"] == "du" and e.get("op") in ("ouvre", "remplace")
           and e.get("ref") not in dus_sortis]
    dus = dernier_par_ref(dus)

    pointeurs = [e for e in evs
                 if e["type"] == "pointeur" and e.get("op") == "ajoute"
                 and e.get("ref") not in retires
                 and e.get("chantier") not in chantiers_fermes]
    pointeurs = dernier_par_ref(pointeurs)

    courant = {}
    for e in evs:
        if e["type"] == "etat" and e.get("op") == "avance":
            courant[e.get("chantier")] = e            # le DERNIER gagne, l'ordre est celui du journal
    courant = {k: v for k, v in courant.items() if k not in chantiers_fermes}
    return decisions, dus, pointeurs, courant


def garde_existence(ev, evs, depot):
    """Rend None si la cible d'un retrait EXISTE dans la projection courante, sinon le refus.

    UN RETRAIT DONT LA CIBLE N'EXISTE PAS NE RETIRE RIEN. Refus à l'ÉCRITURE, 2026-09-14, sur
    constat en session : `pointeur --op retire` sur une ref jamais ajoutée était accepté, écrit
    au journal, et la projection ne bougeait pas — l'auteur croyait le pointeur retiré. C'est
    le cas que `controles-et-alarmes` fait BLOQUER : une règle existe, le système croit
    l'appliquer, et elle ne se charge jamais. Mesuré le même jour sur les 30 niveaux : 8
    retraits orphelins dans l'historique — 6 soldages à la bascule de fils nés hors journal,
    1 réparation après le bug d'auto-remplacement, 1 erreur réelle.
    Les deux causes légitimes sont closes ; le refus dur est tranché par l'utilisateur.

    CE GARDE NE VIT PAS DANS `valide`, qui juge un événement ISOLÉ : il a besoin du journal.
    Il vit dans `cmd_add`, au point où le journal est déjà lu pour l'unicité de l'`id`. Pas
    dans `projette` — append-only, un `projette` qui refuserait rendrait improjetable tout
    niveau portant déjà un retrait orphelin, et il y en a huit.

    `etat ferme` : DÉFINITION LARGE, tranchée le 2026-09-14 faute d'occurrence à mesurer. Un
    chantier « existe » s'il porte un « État courant » OU au moins un du ouvert. Motif : zéro
    `ferme` dans tout l'historique interdit de calibrer une définition stricte, et la large
    minimise le faux refus sur un couple dont on ne sait rien. À resserrer le jour où l'on
    saura — le témoin 6 de l'autotest tient les deux bords.
    """
    t, op = ev["type"], ev.get("op")
    # CIBLES AU PLURIEL depuis le 2026-09-22 : une fusion N→1 nomme plusieurs refs, et CHACUNE
    # doit exister. En vérifier une seule laisserait passer les autres en silence — exactement le
    # défaut que ce garde existe pour fermer.
    if op == "remplace" and t in ("decision", "du"):
        cibles = refs_remplacees(ev)
    elif (t, op) in (("du", "fait"), ("du", "abandonne"), ("pointeur", "retire"),
                     ("decision", "verse")):
        cibles = [ev.get("ref")]
    elif (t, op) == ("etat", "ferme"):
        cibles = [ev.get("chantier")]
    else:
        return None
    decisions, dus, pointeurs, courant = projection_vivante(evs)
    manquantes = []
    for cible in cibles:
        if t == "decision":
            existe = any(e.get("ref") == cible for e in decisions)
            ou = "« Décisions en vigueur »"
        elif t == "du":
            existe = any(e.get("ref") == cible for e in dus)
            ou = "« Ce qui reste »"
        elif t == "pointeur":
            existe = any(e.get("ref") == cible for e in pointeurs)
            ou = "« Où trouver »"
        else:
            existe = cible in courant or any(e.get("chantier") == cible for e in dus)
            ou = "« État courant » ni « Ce qui reste »"
        if not existe:
            manquantes.append(cible)
    if not manquantes:
        return None
    cible = ", ".join(manquantes)
    # Sans git il n'y a qu'un poste : l'issue (a) n'existe pas, et l'énoncer ferait tirer un dépôt
    # qui n'existe pas non plus.
    issue_a = ("(a) — sans objet sans git : un seul poste, donc aucun journal en retard ; "
               if regime.sans_git(depot) else
               f"(a) la cible a été posée sur l'AUTRE poste et ce journal est en retard — le garde "
               f"lit le journal LOCAL — alors `git -C {depot} pull --rebase` puis réessayer ; ")
    return (f"« {cible} » n'existe pas dans la projection de ce niveau : ni dans {ou}, ni "
            f"nulle part. Un « {op} » sur cette cible s'écrirait au journal et NE FERAIT RIEN "
            f"SORTIR de ETAT.md — un retrait qui ne retire rien, sans un mot. Deux issues : "
            f"{issue_a}"
            f"(b) le geste n'a jamais été ouvert ici et l'on veut seulement le consigner — "
            f"employer « --type observation », qui ne pèse rien sur la projection. Pour voir "
            f"les refs vivantes : `etat.py vue --niveau <niveau>`.")


def projette(evs):
    """Rend (corps, n_evenements). Le corps est tout `ETAT.md` sauf la ligne de pied."""
    decisions, dus, pointeurs, courant = projection_vivante(evs)

    L = ["# ÉTAT — projeté par `etat.py`, jamais édité à la main", "",
         "> Ce fichier est une PROJECTION du journal `journal/*.jsonl`. Toute édition directe est",
         "> refusée par le crochet (code 23). Pour le changer : `etat.py add`, puis",
         "> `etat.py projette`. L'histoire — séances, décisions remplacées, dus soldés — n'est pas",
         "> ici : elle est dans le journal, cherchée au `grep`.", ""]

    L += [f"## {SECTIONS[0]}", ""]
    L += [f"- `{e['ref']}` — {e['texte']} *({e['ts'][:10]})*" for e in decisions] or ["*(aucune)*"]

    L += ["", f"## {SECTIONS[1]}", ""]
    if dus:
        par_chantier = {}
        for e in dus:
            par_chantier.setdefault(e["chantier"], []).append(e)
        for chantier in sorted(par_chantier):
            L.append(f"### {chantier}")
            L += [f"- `{e['ref']}` — {e['texte']} *(ouvert le {e['ts'][:10]})*"
                  for e in par_chantier[chantier]]
            L.append("")
        L.pop()
    else:
        L.append("*(aucun)*")

    L += ["", f"## {SECTIONS[2]}", ""]
    L += [f"- **{e['texte']}** → `{e['source']}`" for e in pointeurs] or ["*(aucun)*"]

    L += ["", f"## {SECTIONS[3]}", ""]
    L += [f"- **{c}** — {courant[c]['texte']} *({courant[c]['ts'][:10]})*"
          for c in sorted(courant)] or ["*(aucun)*"]

    corps = "\n".join(L) + "\n"
    return corps, len(evs)


def pied(corps, n, jour):
    return f"\n---\n\n*projeté le {jour} depuis {n} événements · {len(corps)} caractères*\n"


# LE MOTIF DU PIED, À UN SEUL ENDROIT — sorti de `_compare_projection` le 2026-10-01 pour que la
# clôture le lise ici au lieu de le recopier. Il doit rester l'exact reflet de `pied()` ci-dessus.
RE_PIED = re.compile(r"\n---\n\n\*projeté le (\S+) depuis (\d+) événements · (\d+) caractères\*\n?$")


def pied_conforme(contenu):
    """Rend None si `contenu` porte le pied de sa propre projection, sinon la raison.

    Posé le 2026-10-01 sur arbitrage de l'utilisateur, pour la clôture : un `ETAT.md` dont le corps
    ne fait plus les M caractères que son pied annonce a été touché HORS projection — à la main, ou
    par une fusion. Un fichier seulement EN RETARD sur son journal garde un pied exact, donc ce test
    ne crie pas quand le journal avance. LIMITE ASSUMÉE : une retouche qui garde au caractère près la
    longueur du corps passe.
    """
    m = RE_PIED.search(contenu)
    if not m:
        return "pied de projection absent ou hors forme"
    if len(contenu[:m.start()]) != int(m.group(3)):
        return f"le corps fait {len(contenu[:m.start()])} caractères, son pied en annonce {m.group(3)}"
    return None


def cmd_projette(a):
    niveau = os.path.abspath(os.path.expanduser(a.niveau))
    evs = lit_evenements(niveau)
    corps, n = projette(evs)
    contenu = corps + pied(corps, n, datetime.now().astimezone().strftime("%Y-%m-%d"))
    with open(os.path.join(niveau, "ETAT.md"), "w", encoding="utf-8") as fh:
        fh.write(contenu)
    # Le nombre annoncé est celui que le PIED porte — la taille du corps — et pas celle du
    # fichier entier. Deux nombres pour un seul objet se contredisent au premier report.
    print(f"[etat] {n} événements · {len(corps)} caractères de corps "
          f"({len(contenu)} au total) → {niveau}/ETAT.md")
    return 0


# ------------------------------------------------------------------------- check
def _compare_projection(attendu_corps, attendu_n, trouve):
    """Rend None si `trouve` est la projection attendue. ÉCART 1 : la date du pied est exclue.

    Ce qui est comparé : le corps intégralement, plus N et M du pied. Ce qui ne l'est pas : la
    date de projection — sinon le contrôle crierait le lendemain de chaque projection.
    """
    m = RE_PIED.search(trouve)
    if not m:
        return "pied de page absent ou hors forme"
    # PAS de `rstrip` ici, et c'est un défaut mesuré le 2026-09-08 : le corps se termine par
    # exactement un saut de ligne, que le pied compte dans ses M caractères. Retirer ce saut
    # avant comparaison faisait diverger de UN caractère — donc le crochet refusait TOUTE (code 23)
    # projection saine. Un contrôle neuf n'est pas vérifié tant qu'il n'a pas échoué exprès ;
    # celui-là a d'abord échoué sur du bon.
    if trouve[:m.start()] != attendu_corps:
        return (f"le CORPS diffère de la projection "
                f"({len(trouve[:m.start()])} caractères contre {len(attendu_corps)})")
    if int(m.group(2)) != attendu_n:
        return f"le pied annonce {m.group(2)} événements, le journal en porte {attendu_n}"
    if int(m.group(3)) != len(attendu_corps):
        return f"le pied annonce {m.group(3)} caractères, la projection en fait {len(attendu_corps)}"
    return None


def _doublons(evs):
    vus, dbl = set(), []
    for e in evs:
        i = e.get("id")
        (dbl.append(i) if i in vus else vus.add(i))
    return dbl


def check_niveau(niveau, staged=False):
    """Rend (code, lignes de rapport). Ne sort jamais tout seul : `--tous` agrège."""
    msgs = []
    evs = lit_evenements(niveau)

    dbl = _doublons(evs)
    if dbl:
        msgs.append(f"id DUPLIQUÉ ({len(dbl)}) : {', '.join(sorted(set(dbl))[:5])} — "
                    f"c'est la signature d'une fusion en `union` sur une ligne modifiée des deux "
                    f"côtés. Garder l'événement le plus récent, retirer l'autre par un commit qui "
                    f"porte son motif.")
        return 22, msgs

    if staged:
        depot = racine_depot(niveau)
        # SANS GIT, la dernière clôture tient lieu de `HEAD` et le disque de la file : les lignes se
        # comparent par leurs empreintes (`regime.py`), avec le même verdict de préfixe.
        sans_git = regime.sans_git(depot)
        ref, ici = ("la dernière clôture", "sur le disque") if sans_git else ("HEAD", "en file")
        for f in journaux(niveau):
            rel = os.path.relpath(f, depot).replace(os.sep, "/")
            if sans_git:
                lt = regime.lignes_cloture(depot, rel)
                if lt is None:
                    continue                          # neuf depuis la dernière clôture
                lf = regime.lignes_disque(depot, rel)
            else:
                rc_h, tete = git(depot, "show", f"HEAD:{rel}")
                if rc_h != 0:
                    continue                          # fichier neuf : rien à préserver
                rc_i, file = git(depot, "show", f":{rel}")
                if rc_i != 0:
                    continue                          # non mis en file : hors périmètre du commit
                lt, lf = tete.splitlines(), file.splitlines()
            if lf[:len(lt)] != lt:
                for n, (a_, b_) in enumerate(zip(lt, lf), 1):
                    if a_ != b_:
                        msgs.append(f"{rel}:{n} — ligne PASSÉE modifiée. Un journal s'AJOUTE, "
                                    f"il ne se réécrit pas. Le SEUL retrait licite est le "
                                    f"doublon d'une fusion en `union` ; le crochet le laisse "
                                    f"passer sur FORCE_JOURNAL nommé et tracé.")
                        break
                else:
                    msgs.append(f"{rel} — {len(lt) - len(lf)} ligne(s) de {ref} ont DISPARU {ici}.")
                return 22, msgs

    etat = os.path.join(niveau, "ETAT.md")
    if not os.path.exists(etat):
        return (0, msgs) if not evs else (23, msgs + [
            f"{len(evs)} événement(s) au journal et AUCUN ETAT.md — lance `etat.py projette`."])
    corps, n = projette(evs)
    if staged and not regime.sans_git(racine_depot(niveau)):
        depot = racine_depot(niveau)
        rel = os.path.relpath(etat, depot).replace(os.sep, "/")
        rc, trouve = git(depot, "show", f":{rel}")
        if rc != 0:
            trouve = open(etat, encoding="utf-8").read()
    else:
        trouve = open(etat, encoding="utf-8").read()
    faute = _compare_projection(corps, n, trouve)
    if faute:
        msgs.append(f"ETAT.md ≠ projection — {faute}. Lance `etat.py projette`.")
        return 23, msgs
    return 0, msgs


def niveaux_tous():
    """Les dépôts, PLUS tout sous-niveau qui porte déjà un `ETAT.md`.

    Les dépôts viennent de `config.sh` — SOURCE UNIQUE, on ne réimplémente pas le discriminant.

    LES SOUS-NIVEAUX ONT ÉTÉ AJOUTÉS le 2026-09-09, à l'ouverture de la phase 3. Un dépôt client
    porte un niveau par app (décision du 2026-09-08 « un seul écrivain par niveau »), et cette
    fonction n'en voyait aucun : `check --tous` déclarait le parc conforme sans avoir regardé ces
    niveaux, et `vue --tous` — que le démarrage affiche — aurait tu leurs dus. Un contrôle muet rend la même chose qu'un contrôle vert.

    LE DISCRIMINANT EST LA PRÉSENCE D'UN `ETAT.md`, jamais une liste : un niveau qui n'a pas
    basculé n'a rien à vérifier ici, et un niveau qui bascule est vu sans qu'on touche à ce code.
    Le crochet, lui, dérive ses niveaux des chemins en file — il n'a jamais eu ce trou.
    """
    # `claudeos_racines` et non `claudeos_repos` : sans git il n'y a aucun dépôt, mais `~/.claude`
    # reste la racine des niveaux (`lib_regime.sh`). En régime GitHub, les deux rendent la même liste.
    cfg = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.sh")
    r = subprocess.run(["bash", "-c", f'source "{cfg}"; claudeos_racines'],
                       capture_output=True, text=True)
    if r.returncode != 0:
        mourir(1, f"claudeos_racines a échoué ({cfg}) : {r.stderr.strip()[:200]}")
    depots = [l for l in r.stdout.splitlines() if l.strip() and os.path.isdir(l)]
    tous = list(depots)
    systeme = os.path.realpath(os.path.expanduser("~/.claude"))
    for d in depots:
        # Profondeur 3 : projet, puis application. `.git` et les réceptacles exclus.
        profs = ["*", "*/*", "*/*/*"]
        # En dépôt unique et sans git, les domaines vivent sous `travail/` du système : une
        # application y est à la profondeur 4, et restait invisible (audit de la v3.0.0).
        if os.path.realpath(d) == systeme:
            profs.append(os.path.join("travail", "*", "*", "*"))
        for prof in profs:
            for etat in glob.glob(os.path.join(d, prof, "ETAT.md")):
                niv = os.path.dirname(etat)
                if any(p in ("_IGNORE", "extracted", "node_modules") or p.startswith(".")
                       for p in os.path.relpath(niv, d).split(os.sep)):
                    continue
                if niv not in tous:
                    tous.append(niv)
    return tous


def cmd_check(a):
    if a.tous:
        pire = 0
        for niveau in niveaux_tous():
            code, msgs = check_niveau(niveau, a.staged)
            if code != 0:
                print(f"[etat] {niveau} → {code}", file=sys.stderr)
                for m in msgs:
                    print(f"       {m}", file=sys.stderr)
                pire = max(pire, code)
        if pire == 0:
            print("[etat] tous les niveaux conformes")
        return pire
    niveau = os.path.abspath(os.path.expanduser(a.niveau))
    code, msgs = check_niveau(niveau, a.staged)
    for m in msgs:
        print(f"[etat] {m}", file=sys.stderr)
    if code == 0:
        print("[etat] conforme")
    return code


# ------------------------------------------------------------------------- stats
def cmd_stats(a):
    niveau = os.path.abspath(os.path.expanduser(a.niveau))
    seances = [e for e in lit_evenements(niveau)
               if e["type"] == "seance" and e["ts"][:10] >= a.depuis]
    seances.sort(key=lambda e: e["ts"])
    sommes = {"manque_reprise": 0, "manque_declencheur": 0}
    non_relu = {"manque_reprise": 0, "manque_declencheur": 0}
    for e in seances:
        for c in sommes:
            v = e.get(c)
            if v == "non relu":
                non_relu[c] += 1
            elif isinstance(v, int):
                sommes[c] += v
    print(f"[etat] {len(seances)} séance(s) depuis {a.depuis}")
    for c in sommes:
        print(f"       {c:<20} somme {sommes[c]}   · « non relu » {non_relu[c]}")
    # La condition d'arrêt de la semaine d'essai (2.6) se LIT ici, elle ne se recopie pas :
    # sept séances consécutives à 0/0, aucune « non relu ».
    pret = (len(seances) >= 7 and sum(sommes.values()) == 0 and sum(non_relu.values()) == 0)
    print(f"       condition d'arrêt de l'essai (7 séances, 0/0, aucune « non relu ») : "
          f"{'ATTEINTE' if pret else 'non atteinte'}")
    return 0


# --------------------------------------------------------------------------- vue
def cmd_vue(a):
    for niveau in (niveaux_tous() if a.tous else [os.path.abspath(os.path.expanduser(a.niveau))]):
        etat = os.path.join(niveau, "ETAT.md")
        if not os.path.exists(etat):
            continue
        txt = open(etat, encoding="utf-8").read()
        print(f"\n=== {niveau} ===")
        for titre in (SECTIONS[1], SECTIONS[3]):
            m = re.search(rf"^## {re.escape(titre)}$(.*?)(?=^## |\n---\n)", txt, re.M | re.S)
            if m and m.group(1).strip():
                print(f"\n## {titre}{m.group(1).rstrip()}")
    return 0


def cmd_fils(a):
    """Les dus OUVERTS de tous les niveaux, du plus ancien au plus recent, avec leur age.

    REMPLACE `build-threads.sh` et sa vue `memory/OPEN_THREADS.md`, morts le 2026-09-09 : le
    generateur ratissait des TITRES dans les fichiers de reprise, et depuis la phase 3 toutes les
    reprises sont gelees — il ne voyait plus rien, et son fichier de sortie est gele lui aussi,
    donc le demarrage affichait une vue FIGEE au 2026-09-08.

    CE QUE CETTE COMMANDE FAIT DE PLUS QUE `vue` : elle calcule l'ANCIENNETE, qui est tout le
    signal. « A la troisieme reconduction d'un meme fil, chercher l'obstacle au lieu de le
    reconduire » (`os-audit`, HYGIENE geste 8) ne veut rien dire sans l'age. `vue` recopie des
    sections d'`ETAT.md` ; celle-ci lit les journaux et date chaque du a son evenement `ouvre`.

    ZERO RECOPIE DE LA REGLE DE SORTIE : les refs soldees viennent de la MEME logique que la
    projection — `fait`, `abandonne`, et tout `remplace` qui les nomme. Deux implantations du
    meme calcul auraient diverge au premier correctif porte sur une seule.
    """
    import datetime
    aujourdhui = datetime.date.today()
    lignes = []
    for niveau in (niveaux_tous() if a.tous else [os.path.abspath(os.path.expanduser(a.niveau))]):
        evs = lit_evenements(niveau)
        if not evs:
            continue
        _, sortis, _, _ = ensembles_de_sortie(evs)
        # Le ts du PREMIER `ouvre` date le fil, pas celui du dernier `remplace` : un fil reformule
        # garde son age. C'est la raison d'etre de la ref stable (`reprise`, § identifiant de fil).
        # TROIS SOURCES D'AGE, dans cet ordre, ajoutees le 2026-09-10 au geste D5 du plan.
        # MOTIF : la bascule de format des 2026-09-08 et 09 a reemis CHAQUE du comme `ouvre`
        # neuf, donc la vue rendait trois valeurs pour 249 dus — maximum DEUX JOURS. Un controle
        # qui affiche la meme valeur pour tout est ETEINT, et il a ete relaye tel quel dans un
        # bilan de demarrage.
        #   1. le champ `origine`, explicite, quand il est ecrit — c'est la source qui fait foi ;
        #   2. A DEFAUT, la plus VIEILLE date du texte du du, si elle precede son `ts`. L'age est
        #      alors marque INFERE par un tilde : 110 dus sur 310 portent une telle date, et les
        #      redater un par un couterait 110 evenements `remplace` a un ETAT.md deja au double
        #      de son plafond. Un age infere et MARQUE vaut mieux qu'un age faux non marque ;
        #   3. sinon le `ts` du PREMIER `ouvre` — un fil reformule garde son age, c'est la raison
        #      d'etre de la ref stable (`reprise`, § identifiant de fil).
        # DERNIER TOUCHER par ref — tout evenement `du`, quelle que soit son op. C'est la seule
        # donnee d'age qui ne soit jamais inferee.
        toucher = {}
        for e in evs:
            if e["type"] == "du" and e.get("ref"):
                d = e["ts"][:10]
                if e["ref"] not in toucher or d > toucher[e["ref"]]:
                    toucher[e["ref"]] = d
        naissance, origine_explicite, inferee = {}, set(), set()
        for e in evs:
            if e["type"] == "du" and e.get("op") == "ouvre":
                naissance.setdefault(e.get("ref"), e["ts"])
        for e in evs:
            if e["type"] != "du" or e.get("op") not in ("ouvre", "remplace"):
                continue
            ref = e.get("ref")
            if e.get("origine"):
                naissance[ref] = e["origine"]
                origine_explicite.add(ref)
            elif ref not in origine_explicite:
                ts_ref = naissance.get(ref, e["ts"])[:10]
                vieilles = [d for d in re.findall(r"20[0-9]{2}-[01][0-9]-[0-3][0-9]",
                                                  e.get("texte", "")) if d < ts_ref]
                if vieilles:
                    naissance[ref] = min(vieilles)
                    inferee.add(ref)
        for e in evs:
            if e["type"] != "du" or e.get("op") not in ("ouvre", "remplace"):
                continue
            ref = e.get("ref")
            if ref in sortis:
                continue
            ts = naissance.get(ref, e["ts"])
            try:
                jours = (aujourdhui - datetime.date.fromisoformat(ts[:10])).days
            except ValueError:
                jours = -1
            try:
                depuis = (aujourdhui - datetime.date.fromisoformat(
                    toucher.get(ref, ts)[:10])).days
            except ValueError:
                depuis = 0
            lignes.append((jours, niveau, ref, e.get("chantier", "—"), e.get("texte", ""),
                           ref in inferee, depuis))
    lignes.sort(key=lambda x: -x[0])
    if not lignes:
        print("[etat] aucun du ouvert.")
        return 0
    dormants = [l for l in lignes if l[6] > DORMANT_JOURS]
    actifs = [l for l in lignes if l[6] <= DORMANT_JOURS]
    montres = dormants if getattr(a, "dormants", False) else actifs
    if getattr(a, "dormants", False) and not dormants:
        _v = [l for l in lignes if l[0] > VIEUX_JOURS]
        print(f"[etat] aucun du dormant — les {len(lignes)} du(s) ouvert(s) ont tous ete "
              f"touches il y a {DORMANT_JOURS} jours ou moins.")
        if _v:
            print(f"[etat] ⚠ CE ZERO NE VEUT PAS DIRE « RIEN N'EST VIEUX » : {len(_v)} du(s) "
                  f"depassent {VIEUX_JOURS} j d'AGE. Une migration qui touche en masse remet les "
                  f"horloges de dormance a zero sans rajeunir les fils — etat.py fils --tous.")
        return 0
    limite = getattr(a, "limite", None)
    for jours, niveau, ref, chantier, texte, infere, depuis in (
            montres[:limite] if limite else montres):
        court = os.path.basename(niveau) if niveau != os.path.expanduser("~/.claude") else "systeme"
        age = (f"~{jours} j" if infere else f"{jours} j") if jours >= 0 else "date illisible"
        print(f"[{age}] {court} · {chantier} · {ref}")
        print("    " + re.sub(r"\s+", " ", texte).strip()[:170])
    n_inf = sum(1 for l in montres if l[5])
    print(f"\n[etat] {len(lignes)} du(s) ouvert(s) sur "
          f"{len(set(l[1] for l in lignes))} niveau(x).")
    if dormants and not getattr(a, "dormants", False):
        print(f"[etat] {len(dormants)} dormant(s) non touche(s) depuis plus de "
              f"{DORMANT_JOURS} j, hors de cette liste — etat.py fils --dormants")
    # DEUX COMPTES, JAMAIS UN. « dormant » = pas touche ; « vieux » = age reel. Ils divergent des
    # qu'une migration touche en masse, et c'est exactement ce qui est arrive le 2026-09-09.
    vieux = [l for l in lignes if l[0] > VIEUX_JOURS]
    if vieux:
        n_v_inf = sum(1 for l in vieux if l[5])
        print(f"[etat] {len(vieux)} du(s) de plus de {VIEUX_JOURS} j d'AGE — compte distinct des "
              f"dormants, qui se comptent depuis le dernier toucher"
              + (f" ; {n_v_inf} de ces ages sont INFERES" if n_v_inf else "") + ".")
    if n_inf:
        print(f"[etat] {n_inf} age(s) marque(s) d'un TILDE sont INFERES de la plus vieille date "
              f"du texte, faute de champ « origine » — a ne pas lire comme mesures.")
    return 0


# ---------------------------------------------------------------------- autotest
def cmd_autotest(a):
    """Exerce CHAQUE op du contrat contre la PROJECTION, pas seulement contre le refus.

    Écrit le 2026-09-09, sur la règle du même jour (`DESIGN.md`, « Les contrôles mécaniques »).
    Un témoin qui vérifie qu'un événement mal formé est refusé ne dit rien de ce que la
    projection fait d'un événement BIEN formé. Sur pièce : `remplace` était au contrat et
    inconnu du projecteur — l'ancienne ref sortait, la nouvelle n'entrait pas, en silence.
    Le témoin d'alors ne regardait que la sortie, donc il est passé au vert.

    Chaque cas dit ce qui doit ENTRER **et** ce qui doit SORTIR. Tout est joué dans un dossier
    temporaire : le journal réel n'est jamais touché.
    """
    import tempfile
    # (type, op, prépare, attendu_present, attendu_absent)
    # `prépare` est la liste d'événements posés AVANT celui qu'on exerce.
    cas = []
    for t, ops in OPS.items():
        pref = PREFIXE_REF.get(t, "")
        for op in (ops or (None,)):
            cas.append((t, op, pref))

    echecs, joues = [], 0
    with tempfile.TemporaryDirectory() as tmp:
        jdir = os.path.join(tmp, "journal")
        os.makedirs(jdir)
        for t, op, pref in cas:
            joues += 1
            base = f"{pref}temoin-{t}-{op or 'sans-op'}"
            evs = []

            def _ev(**kw):
                e = {"ts": f"2026-01-0{1 + len(evs)}T09:00:00+01:00",
                     "id": f"e-20260101-09000{len(evs)}-abcd",
                     "niveau": ".", "poste": "autotest", "type": t}
                e.update(kw)
                return e

            # Une op qui RETIRE ou REMPLACE a besoin d'une chose à retirer : on la pose d'abord.
            op_pose = {"decision": "pose", "du": "ouvre", "pointeur": "ajoute",
                       "etat": "avance"}.get(t)
            if op and op_pose and op != op_pose:
                evs.append(_ev(op=op_pose, ref=base, chantier="autotest",
                               texte="temoin pose", source="engine/etat.py"))
            kw = {"texte": f"temoin {t} {op or 'sans op'}", "source": "engine/etat.py"}
            if op:
                kw["op"] = op
            if pref or t in ("du", "etat"):
                kw["ref"] = base if op != "remplace" else f"{pref}temoin-nouveau-{t}"
            if t in ("du", "etat"):
                kw["chantier"] = "autotest"
            if op in OPS_A_MOTIF:
                kw["motif"] = "temoin"
            if op == "remplace":
                kw["remplace"] = base
            if t == "seance":
                kw["manque_reprise"] = 0
                kw["manque_declencheur"] = 0
            evs.append(_ev(**kw))

            # 1. Le contrat accepte-t-il le cas ? Un cas refusé ici est un défaut du TÉMOIN.
            faute = next((valide(e) for e in evs if valide(e)), None)
            if faute:
                echecs.append(f"{t}/{op or '—'} : témoin invalide — {faute}")
                continue

            # 2. La projection reflète-t-elle l'op ?
            #    LE MARQUEUR DÉPEND DU TYPE, et s'être trompé de marqueur est le premier défaut
            #    qu'a rendu cet autotest le jour de son écriture : une `decision` et un `du` sont
            #    projetés par leur REF, un `pointeur` par son TEXTE, un `etat` par son CHANTIER.
            #    Chercher la ref sur les deux derniers rend « absent » quoi qu'il arrive — donc
            #    un faux échec sur `ajoute`/`avance`, et un faux SUCCÈS sur `retire`/`ferme`.
            corps, _n = projette(evs)
            marque = {"decision": kw.get("ref"), "du": kw.get("ref"),
                      "pointeur": kw["texte"], "etat": kw.get("chantier")}.get(t)
            pose_marque = {"decision": base, "du": base,
                           "pointeur": "temoin pose", "etat": kw.get("chantier")}.get(t)
            if op == "remplace":
                if base in corps:
                    echecs.append(f"{t}/remplace : l'ancienne ref « {base} » n'est PAS sortie")
                if marque not in corps:
                    echecs.append(f"{t}/remplace : la nouvelle ref « {marque} » n'est PAS entrée")
            elif op in ("fait", "abandonne", "ferme", "retire"):
                if pose_marque and pose_marque in corps:
                    echecs.append(f"{t}/{op} : « {pose_marque} » aurait dû sortir de la projection")
            elif op in ("pose", "ouvre", "ajoute", "avance"):
                if marque and marque not in corps:
                    echecs.append(f"{t}/{op} : « {marque} » n'est PAS entré dans la projection")
            elif t == "seance":
                pass   # une séance ne projette rien : c'est son contrat, pas un défaut
            elif t == "observation":
                if kw["texte"] in corps:
                    echecs.append("observation : projetée alors qu'elle doit rester au journal seul")

        # 3. TÉMOIN DU TÉMOIN — un cas qui DOIT échouer, sinon on ne sait pas si l'on mesure.
        #    Sans lui, un autotest dont la comparaison serait cassée rendrait « tout va bien ».
        faux = [{"ts": "2026-01-01T09:00:00+01:00", "id": "e-20260101-090000-abcd",
                 "niveau": ".", "poste": "autotest", "type": "du", "op": "ouvre",
                 "ref": "u-temoin-negatif", "chantier": "autotest",
                 "texte": "x", "source": "engine/etat.py"}]
        corps_faux, _ = projette(faux)
        if "u-temoin-negatif" not in corps_faux:
            echecs.append("TÉMOIN NÉGATIF : une ref ouverte n'apparaît pas — la mesure est cassée, "
                          "aucun verdict ci-dessus ne vaut")

        # 4. LA BORNE PAR TYPE, ajoutée le 2026-09-10 avec elle. Exercée sur `valide` et non
        #    sur la projection : cette borne REFUSE à l'écriture, donc c'est le refus qu'on
        #    mesure. Une garde sans test se perd au prochain remaniement, et un contrôle muet
        #    est PIRE qu'un contrôle absent — il fait croire à une couverture.
        #    LES DEUX BORDS SONT ÉPROUVÉS : `borne` doit passer, `borne + 1` doit être refusé
        #    PAR LA BORNE et non par autre chose — d'où le contrôle du mot dans le message.
        #    Le piège que ça ferme a été payé le 2026-09-10 : une première épreuve rendait
        #    rc=2 sur un chantier nommé « c », hors forme de slug, et mesurait donc la forme
        #    du chantier au lieu de la longueur du texte.
        def _sonde(t, op, n):
            ev = {"ts": "2026-01-01T09:00:00+01:00", "id": "e-20260101-090000-abcd",
                  "niveau": ".", "poste": "autotest", "type": t, "op": op, "texte": "x" * n}
            if t in PREFIXE_REF:
                ev["ref"] = PREFIXE_REF[t] + "sonde"
            if t in ("du", "etat"):
                ev["chantier"] = "autotest"
            # `source` est due sur pointeur ET observation. Oubliée sur le second, la sonde
            # mesurait « source manquante » et non la longueur : le témoin ci-dessous l'a
            # attrapé le jour même, ce pour quoi il existe.
            if t in ("pointeur", "observation"):
                ev["source"] = "engine/etat.py"
            if op == "remplace":
                ev["remplace"] = PREFIXE_REF.get(t, "") + "vieux"
                ev["motif"] = "sonde d autotest"
            return valide(ev)

        for (t, op), borne in sorted(TEXTE_MAX_PROJETE.items()):
            joues += 1
            sous = _sonde(t, op, borne)
            if sous is not None:
                echecs.append(f"borne {t}/{op} : un texte de {borne} caractères, PILE à la "
                              f"borne, est refusé — elle mord un caractère trop tôt ({sous})")
            au_dessus = _sonde(t, op, borne + 1)
            if au_dessus is None or "trop long" not in au_dessus:
                echecs.append(f"borne {t}/{op} : {borne + 1} caractères ne sont PAS refusés par "
                              f"la borne — elle est MUETTE sur ce couple type/op")
        # TÉMOIN : `observation` ne projette rien, donc aucune borne de type ne doit l'atteindre.
        # Sans ce témoin, une borne qui fuirait sur tous les types passerait pour un succès.
        joues += 1
        if _sonde("observation", "", 4000) is not None:
            echecs.append("TÉMOIN : une observation de 4 000 caractères est refusée — la borne "
                          "par type a fui sur un type qui ne projette pas, et le journal cesse "
                          "d'être la destination gratuite du récit")

        # 5. LE GARDE « ref == remplace », ajouté le 2026-09-13 avec lui. Même raison que la
        #    borne ci-dessus : une garde sans test se perd au prochain remaniement. Exercé sur
        #    `valide`, puisque le refus vit à l'écriture.
        #    LES DEUX BORDS, et le second est le témoin du premier : le cas SAIN — remplacement
        #    par une ref NEUVE — doit continuer de PASSER. Un garde qui refuserait les deux
        #    rendrait `remplace` inutilisable en se faisant passer pour une protection.
        #    LE DÉFAUT QU'IL FERME : `--ref X --remplace X` faisait sortir X de la projection
        #    par lui-même, `check` disait conforme, et le fil disparaissait de ETAT.md sans un
        #    mot. Mesuré le jour même sur `du` ET sur `decision` — le constat d'origine, venu
        #    d'une session de projet, ne nommait que les `du`.
        def _sonde_remplace(t, ref, remplace):
            ev = {"ts": "2026-01-01T09:00:00+01:00", "id": "e-20260101-090000-abcd",
                  "niveau": ".", "poste": "autotest", "type": t, "op": "remplace",
                  "ref": ref, "texte": "x", "remplace": remplace,
                  "motif": "sonde d autotest"}
            if t == "du":
                ev["chantier"] = "autotest"
            return valide(ev)

        for t in ("du", "decision"):
            pref = PREFIXE_REF[t]
            joues += 1
            meme = _sonde_remplace(t, pref + "sonde", pref + "sonde")
            if meme is None or "meme chose" not in meme:
                echecs.append(f"garde ref==remplace : un {t} qui se remplace LUI-MEME n'est pas "
                              f"refusé par le garde — il disparaîtrait de la projection en silence")
            joues += 1
            neuve = _sonde_remplace(t, pref + "neuve", pref + "vieille")
            if neuve is not None:
                echecs.append(f"TÉMOIN du garde ref==remplace : un {t} remplacé par une ref NEUVE "
                              f"est refusé à tort ({neuve}) — le garde mord trop large et rend "
                              f"« remplace » inutilisable")

        # 6. LE GARDE D'EXISTENCE SUR LES RETRAITS, ajouté le 2026-09-14 avec lui. Le défaut
        #    qu'il ferme : `pointeur --op retire` sur une ref jamais ajoutée était ACCEPTÉ, écrit
        #    au journal, et la projection ne bougeait pas — sans un mot. L'auteur croyait le
        #    pointeur retiré. Mesuré le même jour sur les 30 niveaux : 8 retraits orphelins dans
        #    l'historique, 7 nés de la bascule ou du bug d'auto-remplacement, 1 erreur réelle
        #    (un projet personnel).
        #    LE GARDE NE VIT PAS DANS `valide` — il a besoin du journal — donc il s'exerce à
        #    part, sur les six couples qui font sortir quelque chose de la projection, et sur
        #    LES DEUX BORDS : sans pose il doit refuser, avec pose il doit laisser passer.
        _garde = globals().get("garde_existence")
        retraits = [("decision", "remplace", "pose"), ("du", "remplace", "ouvre"),
                    ("du", "fait", "ouvre"), ("du", "abandonne", "ouvre"),
                    ("pointeur", "retire", "ajoute"), ("etat", "ferme", "avance")]
        for t, op, op_pose in retraits:
            pref = PREFIXE_REF.get(t, "")
            base = f"{pref}cible-{t}"
            pose = {"ts": "2026-01-01T09:00:00+01:00", "id": "e-20260101-090000-aaaa",
                    "niveau": ".", "poste": "autotest", "type": t, "op": op_pose, "ref": base,
                    "chantier": "autotest", "texte": "cible posee", "source": "engine/etat.py"}
            retrait = {"ts": "2026-01-02T09:00:00+01:00", "id": "e-20260102-090000-bbbb",
                       "niveau": ".", "poste": "autotest", "type": t, "op": op,
                       "ref": f"{pref}neuve" if op == "remplace" else base,
                       "chantier": "autotest", "texte": "x", "motif": "sonde d autotest"}
            if op == "remplace":
                retrait["remplace"] = base
            joues += 1
            if _garde is None:
                echecs.append(f"garde d'existence {t}/{op} : la fonction « garde_existence » "
                              f"n'existe pas — un retrait orphelin est accepté en silence")
                continue
            seul = _garde(retrait, [], depot="/depot")
            if seul is None or "existe pas" not in seul:
                echecs.append(f"garde d'existence {t}/{op} : un retrait sur « {base} » JAMAIS "
                              f"posée n'est pas refusé ({seul!r}) — la projection ne bougerait "
                              f"pas et rien ne le dirait")
            joues += 1
            apres_pose = _garde(retrait, [pose], depot="/depot")
            if apres_pose is not None:
                echecs.append(f"TÉMOIN du garde d'existence {t}/{op} : un retrait sur une cible "
                              f"POSÉE est refusé à tort ({apres_pose}) — le garde mord trop "
                              f"large et rend « {op} » inutilisable")

        # 7. LE MÊME GARDE DE BOUT EN BOUT, par `add`, sur un niveau jetable `git init` : un
        #    témoin sur la fonction seule ne prouve pas que `cmd_add` l'APPELLE. Le retrait
        #    orphelin doit rendre 2 et n'écrire AUCUNE ligne ; les deux gestes sains, 0.
        joues += 1
        niv = os.path.join(tmp, "niveau-jetable")
        os.makedirs(niv)
        # Sans git utilisable sur le poste — absent, ou qui échoue —, le niveau jetable se marque
        # comme une racine sans git (`regime.py`) : le témoin porte sur le garde d'`etat.py`, pas sur
        # git, et il se joue dans les deux régimes, jamais « non joué » faute d'outil.
        try:
            _gi = subprocess.run(["git", "init", "-q", niv], capture_output=True, text=True)
        except FileNotFoundError:
            _gi = None
        if _gi is None or _gi.returncode != 0:
            open(os.path.join(niv, regime.MARQUE_RACINE), "w").close()
            _gi = subprocess.CompletedProcess([], 0, "", "")
        if _gi.returncode != 0:
            echecs.append(f"garde de bout en bout : `git init` du niveau jetable a échoué "
                          f"({_gi.stderr.strip()[:120]}) — témoin non joué")
        else:
            def _add(*args):
                r = subprocess.run([sys.executable, os.path.abspath(__file__), "add",
                                    "--niveau", niv, *args], capture_output=True, text=True)
                return r.returncode, r.stderr
            ici = os.path.abspath(__file__)
            rc1, _ = _add("--type", "pointeur", "--op", "ajoute", "--ref", "p-vrai",
                          "--texte", "pointeur sain", "--source", ici)
            rc2, err2 = _add("--type", "pointeur", "--op", "retire", "--ref", "p-fantome",
                             "--texte", "x", "--source", ici, "--motif", "sonde")
            lignes = sum(len(open(f, encoding="utf-8").read().splitlines())
                         for f in journaux(niv))
            rc3, err3 = _add("--type", "pointeur", "--op", "retire", "--ref", "p-vrai",
                             "--texte", "x", "--source", ici, "--motif", "sonde")
            if rc1 != 0:
                echecs.append(f"garde de bout en bout : l'ajout SAIN rend {rc1} au lieu de 0")
            if rc2 != 2 or "p-fantome" not in err2:
                echecs.append(f"garde de bout en bout : `add` d'un retrait sur « p-fantome » "
                              f"jamais ajouté rend {rc2} au lieu de 2, ou ne nomme pas la ref "
                              f"({err2.strip()[:160]!r})")
            if lignes != 1:
                echecs.append(f"garde de bout en bout : {lignes} ligne(s) au journal après le "
                              f"retrait orphelin, attendu 1 — un refus n'écrit RIEN")
            if rc3 != 0:
                echecs.append(f"TÉMOIN de bout en bout : le retrait SAIN de « p-vrai » rend "
                              f"{rc3} au lieu de 0 ({err3.strip()[:160]!r})")

        # 8. LA DORMANCE, LES DEUX BORDS — posée le 2026-09-15. Un du touché AUJOURD'HUI reste
        #    dans `fils` ; un du dont le dernier événement date de `DORMANT_JOURS + 60` en sort,
        #    est COMPTÉ au pied, et ressort seul sous `--dormants`. Le journal est écrit à la
        #    main : `add` horodate lui-même, donc il ne sait pas fabriquer un événement vieux.
        #    TROISIÈME BORD, et c'est celui qui garde la règle honnête : `ETAT.md` doit être le
        #    MÊME avant et après, octet pour octet — la dormance est une règle de LECTURE, et si
        #    elle touchait la projection, `check` crierait tout seul au passage du seuil.
        import datetime as _dt
        niv2 = os.path.join(tmp, "niveau-dormance")
        os.makedirs(os.path.join(niv2, "journal"))
        _auj = _dt.date.today()
        _vieux = _auj - _dt.timedelta(days=DORMANT_JOURS + 60)
        _evs2 = [
            {"ts": f"{_vieux}T09:00:00+01:00", "id": "e-dorm-0001-aaaa", "niveau": ".",
             "poste": "autotest", "type": "du", "op": "ouvre", "ref": "u-temoin-dormant",
             "chantier": "autotest", "texte": "du jamais retouche", "source": "engine/etat.py"},
            {"ts": f"{_auj}T09:00:00+01:00", "id": "e-dorm-0002-bbbb", "niveau": ".",
             "poste": "autotest", "type": "du", "op": "ouvre", "ref": "u-temoin-actif",
             "chantier": "autotest", "texte": "du touche aujourd hui", "source": "engine/etat.py"},
        ]
        with open(os.path.join(niv2, "journal", f"{_auj:%Y-%m}.jsonl"), "w",
                  encoding="utf-8") as _f:
            for _e in _evs2:
                _f.write(json.dumps(_e, ensure_ascii=False) + "\n")

        def _fils(*args):
            r = subprocess.run([sys.executable, os.path.abspath(__file__), "fils",
                                "--niveau", niv2, *args], capture_output=True, text=True)
            return r.returncode, r.stdout

        joues += 1
        rc_a, out_a = _fils()
        if "u-temoin-actif" not in out_a:
            echecs.append("dormance : le du touché AUJOURD'HUI est absent de `fils` — la règle "
                          "mord trop large et cacherait du travail vivant")
        if "u-temoin-dormant" in out_a:
            echecs.append(f"dormance : le du non touché depuis {DORMANT_JOURS + 60} j est TOUJOURS "
                          f"listé par `fils` — la règle ne mord pas")
        if "1 dormant(s)" not in out_a:
            echecs.append(f"dormance : `fils` ne compte pas le dormant au pied de sa liste "
                          f"({out_a.strip()[-160:]!r}) — il sortirait sans un mot")

        joues += 1
        rc_b, out_b = _fils("--dormants")
        if "u-temoin-dormant" not in out_b or "u-temoin-actif" in out_b:
            echecs.append(f"dormance : `fils --dormants` ne rend pas EXACTEMENT les dormants "
                          f"({out_b.strip()[:200]!r}) — le dormant serait irrécupérable")

        joues += 1
        _r1 = subprocess.run([sys.executable, os.path.abspath(__file__), "projette",
                              "--niveau", niv2], capture_output=True, text=True)
        _etat1 = open(os.path.join(niv2, "ETAT.md"), encoding="utf-8").read()
        if "u-temoin-dormant" not in _etat1:
            echecs.append("dormance : le du dormant a DISPARU d'ETAT.md — la règle a touché la "
                          "projection, donc `check` criera (code 23) au passage du seuil")

    if echecs:
        print(f"[etat] autotest : {len(echecs)} ÉCHEC(S) sur {joues} op exercées", file=sys.stderr)
        for e in echecs:
            print(f"       {e}", file=sys.stderr)
        return 1
    print(f"[etat] autotest : {joues} op du contrat exercées contre la projection, toutes conformes")
    return 0


def main():
    ap = argparse.ArgumentParser(prog="etat.py", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("add", help="ajoute un événement validé")
    p.add_argument("--niveau", required=True)
    p.add_argument("--type", required=True, choices=list(OPS))
    p.add_argument("--op")
    p.add_argument("--ref")
    p.add_argument("--chantier")
    p.add_argument("--texte", required=True)
    p.add_argument("--source", help="chemin ou commande ; JAMAIS une valeur")
    p.add_argument("--origine", help="date ISO de NAISSANCE du fil, quand elle precede l'evenement "
                                     "— sinon l'age se compte a l'ecriture")
    p.add_argument("--remplace")
    p.add_argument("--motif")
    p.add_argument("--manque-reprise", dest="manque_reprise",
                   help="entier >= 0, ou la chaine « non relu » — JAMAIS 0 pour dire qu'on n'a pas regarde")
    p.add_argument("--manque-declencheur", dest="manque_declencheur",
                   help="entier >= 0, ou la chaine « non relu » — JAMAIS 0 pour dire qu'on n'a pas regarde")
    p.set_defaults(fn=cmd_add)

    p = sub.add_parser("projette", help="réécrit ETAT.md depuis le journal")
    p.add_argument("--niveau", required=True)
    p.set_defaults(fn=cmd_projette)

    p = sub.add_parser("check", help="0 ok · 22 journal réécrit · 23 ETAT.md ≠ projection")
    p.add_argument("--niveau")
    p.add_argument("--staged", action="store_true")
    p.add_argument("--tous", action="store_true")
    p.set_defaults(fn=cmd_check)

    p = sub.add_parser("stats", help="compteurs de séance depuis une date")
    p.add_argument("--niveau", required=True)
    p.add_argument("--depuis", required=True, metavar="AAAA-MM-JJ")
    p.set_defaults(fn=cmd_stats)

    p = sub.add_parser("autotest", help="exerce chaque op du contrat contre la projection")
    p.add_argument("--niveau", default=".")
    p.set_defaults(fn=cmd_autotest)

    p = sub.add_parser("vue", help="« Ce qui reste » et « État courant » de tous les niveaux")
    p.add_argument("--niveau")
    p.add_argument("--tous", action="store_true")
    p.set_defaults(fn=cmd_vue)

    p = sub.add_parser("fils", help="les dus ouverts par ancienneté, tous niveaux")
    p.add_argument("--niveau")
    p.add_argument("--tous", action="store_true")
    p.add_argument("--limite", type=int, default=None)
    p.add_argument("--dormants", action="store_true",
                   help=f"n'afficher QUE les dus non touches depuis plus de {DORMANT_JOURS} j")
    p.set_defaults(fn=cmd_fils)

    a = ap.parse_args()
    if getattr(a, "tous", False) is False and getattr(a, "niveau", None) is None:
        ap.error("--niveau est requis sans --tous")
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
