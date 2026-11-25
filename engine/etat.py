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
  vue       « Ce qui reste » + « État courant » de tous les niveaux
  fils      les dus ouverts de tous les niveaux, par ancienneté
  Bibliothèque standard SEULE. Le système ne dépend que de bash et python, plus git en régime
  GitHub : SANS GIT, la racine et la garde append-only passent par `regime.py`, à côté.

DEUX ÉCARTS DÉCIDÉS À L'ÉCRITURE, tous deux pour ne pas fabriquer un contrôle menteur :

ÉCART 1 — le pied de page ne se compare PAS octet à octet.
Le plan prescrit un pied « projeté le AAAA-MM-JJ depuis N événements · M caractères ». Comparé
tel quel, le crochet crierait le LENDEMAIN (code 23) de chaque projection, sans qu'on ait touché à
rien : la date change, donc la projection diffère. Un contrôle qui crie tous les jours apprend
à ignorer sa catégorie entière. Donc `check` compare le
CORPS intégralement, et du pied il ne compare que `N` et `M`. La date reste écrite, elle
informe le lecteur ; elle n'entre pas dans le verdict.

ÉCART 2 — `check --staged` exige un PRÉFIXE, pas une inclusion.
Le plan dit « toute ligne de HEAD absente ou modifiée en file → 22 ». Implémenté en préfixe :
les N premières lignes de la version en file doivent être EXACTEMENT celles de `HEAD`. C'est
plus strict, et volontairement — ça attrape aussi le réordonnancement, qu'une comparaison
d'ensembles laisserait passer. Réserve nommée : après un `merge` avec `merge=union`, l'ordre
peut ne plus préserver le préfixe. C'est `check` SANS `--staged` qui cherche le doublon d'`id`,
qui est le dégât réel d'une fusion en union.

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
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import regime   # le régime sans git, propre au template (`d-regime-sans-git`)

# Le champ `poste` : le nom que rend `lib_poste.py` — le registre des postes, à défaut le nom
# réseau —, celui que le démarrage compare au journal. Sans `lib_poste.py`, le nom réseau seul.
try:
    from lib_poste import nom_poste
except ImportError:
    def nom_poste():
        return socket.gethostname()

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
# `motif` est dû sur ces quatre opérations : elles retirent quelque chose de l'état projeté, et
# un retrait sans motif est indistinguable d'un oubli.
OPS_A_MOTIF = {"abandonne", "remplace", "retire", "verse"}
# `verse` fait sortir une décision SANS successeur, là où `remplace` exige une ref NEUVE. Il
# dit OÙ va le contenu : `--source` y est dû comme `--motif`, et nomme la maison que la règle de
# tri lui donne (`DESIGN.md « <section> »` ou le document de référence du projet) — une décision
# qui sort sans destination est perdue. L'événement reste au journal ; seule la projection s'allège.
# `--remplace` accepte plusieurs refs séparées par une virgule (fusion N→1).
# Longueur maximale d'un `texte`, en CARACTÈRES — voir le motif à la validation.
TEXTE_MAX = 4500
# DORMANCE : un du dont le DERNIER événement date de plus de N jours sort de `fils` et du bilan
# de démarrage. Le dernier toucher et non la naissance : c'est un `ts` mesuré, jamais deviné.
# Règle de LECTURE, pas de projection : sinon `check` crierait (23) le jour où un du franchit le
# seuil sans que rien ait changé — l'ÉCART 1. Aucun événement n'est écrit : un du se réveille dès
# qu'on écrit dessus, et le compte en pied de `fils` empêche de l'oublier.
DORMANT_JOURS = 30
# Un du porté par l'UTILISATEUR ne dort jamais : c'est son geste, et l'oublier ne le règle pas. La
# dormance vaut pour l'assistant, les tiers et les dus sans porteur.
def dort(depuis, porteur):
    return depuis > DORMANT_JOURS and porteur != "utilisateur"
# `dormant` se compte depuis le dernier toucher ; une migration qui touche en masse remet toutes
# les horloges à zéro, et « aucun du dormant » se lirait « rien n'est vieux ». D'où un second
# compte, NOMMÉ à côté : l'ÂGE réel (`origine`, sinon inféré de la plus vieille date du texte et
# marqué d'un tilde), pour qu'un zéro ne puisse plus se lire comme deux.
VIEUX_JOURS = 30
# BORNE PAR TYPE sur ce qui est PROJETÉ — une borne de LISIBILITÉ, distincte de `TEXTE_MAX`
# (filet contre la substitution de commande). Elle ne vise que les ops qui entrent dans `ETAT.md` ;
# `observation` et `seance` gardent `TEXTE_MAX` : le journal ne pèse rien sur la projection.
# Deux motifs : `ETAT.md` est chargé EN ENTIER à chaque reprise de niveau ; et un texte long
# CAMOUFLE — un du court se relit, un du long se croit.
# Valeurs calibrées sur la longueur des `texte` par type dans tous les `journal/*.jsonl` du parc :
# assez pour changer l'écriture, pas assez pour interdire un fait normal. Une baisse se réécrit
# ici ; un relèvement se date et se motive, comme un cliquet.
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
# PORTEUR D'UN DU : QUI fait le prochain geste, un seul par fil ; un fil mixte change de porteur
# par une reformulation quand le geste passe. Un rôle et non un prénom : `utilisateur`,
# `assistant`, `tiers`. Un marqueur et non une couleur : le bilan arrive au modèle en texte
# (`additionalContext`), un code ANSI n'y survit pas.
PORTEURS = {"utilisateur": "👤", "assistant": "🤖", "tiers": "⏳"}
SANS_PORTEUR = "❔"
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
    # BORNE DE LONGUEUR. Un accent grave dans une chaîne shell entre guillemets est une SUBSTITUTION
    # DE COMMANDE, et le journal étant append-only la faute serait PERMANENTE. La borne n'empêche pas
    # la substitution (elle a lieu dans le shell, avant l'appel), seulement l'écriture du résultat :
    # c'est un filet ; la protection est la règle, dans la compétence `reprise`.
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
    # UNE REF NE SE REMPLACE PAS PAR ELLE-MÊME : `--ref X --remplace X` ferait sortir X de la
    # projection en silence (l'événement s'ajoute à `dus_sortis`/`remplacees` puis s'exclut de sa
    # propre liste), sur `du` comme sur `decision`, et `check` dirait conforme. Refus à la validation
    # et non au `projette` : le journal est append-only, un `projette` qui refuserait rendrait
    # improjetable tout niveau portant déjà l'événement fautif.
    if ev.get("op") == "remplace" and ev.get("ref") and ev.get("ref") == ev.get("remplace"):
        return (f"« ref » et « remplace » sont la meme chose ({ev['ref']}) — l'evenement se "
                f"ferait sortir lui-meme et DISPARAITRAIT de ETAT.md sans alerte. Un "
                f"remplacement porte une reference NEUVE ; l'ancienne va dans « --remplace ». "
                f"Pour reformuler sans renommer, employer « --op ouvre » : le dernier gagne.")
    # « remplace » N'EST ACCEPTÉ QU'AVEC L'OP « remplace ». `ensembles_de_sortie` lit ce champ sur
    # TOUT événement, mais seuls `decisions` et `dus` consultent ses ensembles : sur un `pointeur` il
    # ne remplacerait rien (les deux se projettent côte à côte), sur une `observation` il ferait
    # SORTIR le dû nommé, sans un mot. Pour changer un pointeur : `--op retire` puis `--op ajoute`
    # sous une ref NEUVE — le retrait sort tous les ajouts de la ref.
    if ev.get("remplace") and ev.get("op") != "remplace":
        return (f"« remplace » n'a de sens qu'avec « --op remplace » — reçu sur type "
                f"« {ev.get('type')} », op « {ev.get('op') or 'aucune'} ». Il serait ACCEPTÉ et "
                f"agirait de travers : sur un « pointeur » il ne remplace rien et laisse les deux "
                f"côte à côte ; sur une « observation » il FAIT SORTIR le dû nommé, sans un mot. "
                f"Un pointeur se change par « --op retire » puis « --op ajoute » sous une ref NEUVE.")
    if ev.get("op") in OPS_A_MOTIF and not ev.get("motif"):
        return (f"« motif » manquant sur op « {ev['op']} » — ce qui sort de l'état projeté "
                f"dit pourquoi, sinon un retrait est indistinguable d'un oubli")
    # UN POINTEUR NEUF NE PEUT PAS VISER UNE CIBLE MORTE (contrôle plus bas) : refus à l'écriture, pas
    # au `projette`, qui rendrait improjetable tout niveau portant déjà un pointeur mort. Le résolveur
    # est celui du contrôle hebdomadaire 45, importé et non recopié : deux implantations dérivent. Le
    # 45 garde les pointeurs DÉJÀ écrits et les cibles qui meurent après coup.
    # `origine` DATE LA NAISSANCE D'UN FIL : sens seulement sur un du qui s'ouvre ou se reformule ;
    # une date FUTURE est une faute de frappe qui rajeunirait le fil, donc refusée.
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
    if ev.get("porteur") is not None:
        if t != "du" or ev.get("op") not in ("ouvre", "remplace"):
            return "« porteur » n'a de sens que sur un du en « ouvre » ou « remplace »"
        if ev["porteur"] not in PORTEURS:
            return (f"« porteur » hors contrat : « {ev['porteur']} » — attendus : "
                    f"{', '.join(PORTEURS)}. C'est QUI FAIT LE PROCHAIN GESTE, un seul.")
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
        "poste": nom_poste(),
        "type": a.type,
    }
    for champ in ("op", "ref", "chantier", "texte", "source", "remplace", "motif", "origine",
                  "porteur"):
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
        # Sans ce refus, `int(brut)` remonterait un traceback nu au lieu du « REFUSÉ » des autres champs :
        # lu comme une panne de l'outil, et sans apprendre la valeur attendue.
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

    Le champ porte une ou plusieurs refs, séparées par une virgule (fusion N→1) ; un champ à une
    seule ref traverse inchangé. Ce découpage vit ici et nulle part ailleurs : `ensembles_de_sortie`,
    `garde_existence` et `porteurs` l'appellent, et des copies du même calcul dérivent au premier
    correctif porté sur une seule.
    """
    brut = ev.get("remplace")
    if not brut:
        return []
    return [r.strip() for r in str(brut).split(",") if r.strip()]


# ---------------------------------------------------------------------- projette
def ensembles_de_sortie(evs):
    """Ce que le journal a fait SORTIR de la projection : (remplacees, dus_sortis, retires,
    chantiers_fermes). UNE SEULE IMPLANTATION, lue par `projection_vivante` — donc par `projette`
    et par le garde d'existence des retraits — et par `cmd_fils` : des copies du même calcul
    dérivent au premier correctif porté sur une seule, et un garde qui dérive de ce qu'il garde ment.
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
    employer "--op ouvre" : le dernier gagne ». Sans déduplication, la projection EMPILE — deux
    `ouvre` sur la même ref rendent deux lignes, la formulation périmée juste au-dessus de la
    neuve, dans le seul fichier qu'une reprise lit EN ENTIER. Muet : ni refus, ni avertissement,
    et l'auteur croit avoir reformulé. Vaut pour les trois listes, comme `courant` pour les
    chantiers, et pour `cmd_fils`, qui l'appelle aussi.

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

    # `remplace` COMPTE COMME UNE POSE : sinon l'ancienne ref sort sans que la nouvelle entre, et
    # les deux disparaissent de l'état sans un mot.
    decisions = [e for e in evs
                 if e["type"] == "decision" and e.get("op") in ("pose", "remplace")
                 and e.get("ref") not in remplacees]
    decisions = dernier_par_ref(decisions)

    dus = [e for e in evs
           if e["type"] == "du" and e.get("op") in ("ouvre", "remplace")
           and e.get("ref") not in dus_sortis]
    dus = dernier_par_ref(dus)

    # LA DERNIÈRE VERSION D'ABORD, LE CHANTIER FERMÉ ENSUITE : filtré avant, le chantier fermé
    # écarte la version neuve et une version antérieure rangée ailleurs ressort, périmée, sans un mot.
    pointeurs = [e for e in evs
                 if e["type"] == "pointeur" and e.get("op") == "ajoute"
                 and e.get("ref") not in retires]
    pointeurs = [e for e in dernier_par_ref(pointeurs)
                 if e.get("chantier") not in chantiers_fermes]

    courant = {}
    for e in evs:
        if e["type"] == "etat" and e.get("op") == "avance":
            courant[e.get("chantier")] = e            # le DERNIER gagne, l'ordre est celui du journal
    courant = {k: v for k, v in courant.items() if k not in chantiers_fermes}
    return decisions, dus, pointeurs, courant


def garde_existence(ev, evs, depot):
    """Rend None si la cible d'un retrait EXISTE dans la projection courante, sinon le refus.

    UN RETRAIT DONT LA CIBLE N'EXISTE PAS NE RETIRE RIEN : accepté, il s'écrirait au journal
    sans que la projection bouge, et l'auteur croirait la cible retirée. C'est le cas que
    `controles-et-alarmes` fait BLOQUER : une règle existe, le système croit l'appliquer, et
    elle ne se charge jamais. Le refus dur est tranché par l'utilisateur.

    CE GARDE NE VIT PAS DANS `valide`, qui juge un événement ISOLÉ : il a besoin du journal.
    Il vit dans `cmd_add`, au point où le journal est déjà lu pour l'unicité de l'`id`. Pas
    dans `projette` — append-only, un `projette` qui refuserait rendrait improjetable tout
    niveau portant déjà un retrait orphelin, et l'historique en porte.

    `etat ferme` : DÉFINITION LARGE. Un chantier « existe » s'il porte un « État courant » OU au
    moins un du ouvert. Sans `ferme` dans l'historique pour calibrer une définition stricte, la
    large minimise le faux refus. À resserrer quand on pourra mesurer — le témoin 6 de
    `tests/test_etat.py` tient les deux bords.
    """
    t, op = ev["type"], ev.get("op")
    # CIBLES AU PLURIEL : une fusion N→1 nomme plusieurs refs, et CHACUNE doit exister. En vérifier
    # une seule laisserait passer les autres en silence.
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


def porteurs(evs):
    """ref -> porteur, pour chaque du. UNE SEULE IMPLANTATION, lue par `projette` et `cmd_fils`.

    HERITAGE, et c'est ce qui rend le champ tenable : une reformulation (`ouvre` sur la meme ref,
    « le dernier gagne ») qui ne nomme pas de porteur GARDE le dernier connu, et un `remplace` sans
    porteur reprend celui de la premiere ref qu'il fait sortir. Sans quoi chaque reformulation
    effacerait le porteur en silence, et la vue « a toi » se viderait toute seule.
    """
    P = {}
    for e in evs:
        if e.get("type") != "du" or e.get("op") not in ("ouvre", "remplace") or not e.get("ref"):
            continue
        if e.get("porteur"):
            P[e["ref"]] = e["porteur"]
        elif e.get("op") == "remplace" and e["ref"] not in P:
            for r in refs_remplacees(e):
                if r in P:
                    P[e["ref"]] = P[r]
                    break
    return P


def marque_porteur(p):
    return PORTEURS.get(p, SANS_PORTEUR)


def projette(evs):
    """Rend (corps, n_evenements). Le corps est tout `ETAT.md` sauf la ligne de pied."""
    decisions, dus, pointeurs, courant = projection_vivante(evs)
    P = porteurs(evs)

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
            L += [f"- `{e['ref']}`" + (f" {PORTEURS[P[e['ref']]]}" if e['ref'] in P else "")
                  + f" — {e['texte']} *(ouvert le {e['ts'][:10]})*"
                  for e in par_chantier[chantier]]
            L.append("")
        L.pop()
    else:
        L.append("*(aucun)*")

    L += ["", f"## {SECTIONS[2]}", ""]
    # Un texte qui porte déjà son gras (« **question ?** → réponse », la forme du gabarit) ne se
    # réenveloppe pas : sinon la ligne projetée sort en gras quadruple.
    L += [(f"- {e['texte']} → `{e['source']}`" if e['texte'].startswith('**')
           else f"- **{e['texte']}** → `{e['source']}`") for e in pointeurs] or ["*(aucun)*"]

    L += ["", f"## {SECTIONS[3]}", ""]
    L += [f"- **{c}** — {courant[c]['texte']} *({courant[c]['ts'][:10]})*"
          for c in sorted(courant)] or ["*(aucun)*"]

    corps = "\n".join(L) + "\n"
    return corps, len(evs)


def pied(corps, n, jour):
    return f"\n---\n\n*projeté le {jour} depuis {n} événements · {len(corps)} caractères*\n"


# LE MOTIF DU PIED, à un seul endroit : la clôture le lit ici au lieu de le recopier. Il doit
# rester l'exact reflet de `pied()` ci-dessus.
RE_PIED = re.compile(r"\n---\n\n\*projeté le (\S+) depuis (\d+) événements · (\d+) caractères\*\n?$")


def pied_conforme(contenu):
    """Rend None si `contenu` porte le pied de sa propre projection, sinon la raison.

    Lu par la clôture : un `ETAT.md` dont le corps
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
    # PAS de `rstrip` : le corps finit par exactement un saut de ligne, que le pied compte dans ses
    # M caractères. Le retirer décale d'un caractère et fait refuser (23) toute projection saine.
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

    LES SOUS-NIVEAUX SONT INDISPENSABLES : un dépôt client porte un niveau par app (« un seul
    écrivain par niveau »), et sans eux `check --tous` déclarerait le parc conforme sans avoir
    regardé les apps, et `vue --tous` — que le démarrage affiche — tairait leurs dus. Un contrôle
    muet rend la même chose qu'un contrôle vert.

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

    CE QUE CETTE COMMANDE FAIT DE PLUS QUE `vue` : elle calcule l'ANCIENNETE, qui est tout le
    signal. « Rappel ou fil reconduit trois fois : attaquer l'obstacle » (`session`) ne veut
    rien dire sans l'age. `vue` recopie des sections d'`ETAT.md` ; celle-ci lit les journaux et
    date chaque du a son evenement `ouvre`.

    ZERO RECOPIE DE LA REGLE DE SORTIE : les refs soldees viennent de la MEME logique que la
    projection — `fait`, `abandonne`, et tout `remplace` qui les nomme. Deux implantations du
    meme calcul divergent au premier correctif porte sur une seule.
    """
    import datetime
    aujourdhui = datetime.date.today()
    lignes = []
    for niveau in (niveaux_tous() if a.tous else [os.path.abspath(os.path.expanduser(a.niveau))]):
        evs = lit_evenements(niveau)
        if not evs:
            continue
        _, sortis, _, _ = ensembles_de_sortie(evs)
        P = porteurs(evs)
        # ÂGE D'UN FIL, trois sources dans cet ordre :
        #   1. le champ `origine`, explicite — c'est lui qui fait foi ;
        #   2. à défaut, la plus VIEILLE date du texte si elle précède le `ts`, marquée INFÉRÉE par un
        #      tilde : un âge inféré et marqué vaut mieux qu'un âge faux non marqué ;
        #   3. sinon le `ts` du PREMIER `ouvre` — un fil reformulé garde son âge, c'est la raison d'être
        #      de la ref stable (`reprise`, § identifiant de fil).
        # DERNIER TOUCHER par ref — tout événement `du`, quelle que soit son op : la seule donnée d'âge
        # qui ne soit jamais inférée.
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
                # Une origine EXPLICITE retire le tilde qu'un événement antérieur avait posé.
                inferee.discard(ref)
            elif ref not in origine_explicite:
                ts_ref = naissance.get(ref, e["ts"])[:10]
                vieilles = [d for d in re.findall(r"20[0-9]{2}-[01][0-9]-[0-3][0-9]",
                                                  e.get("texte", "")) if d < ts_ref]
                if vieilles:
                    naissance[ref] = min(vieilles)
                    inferee.add(ref)
        # UNE LIGNE PAR REF, dans sa dernière formulation — la règle de la projection, par la MÊME
        # fonction ; sinon un fil reformulé sortirait ici autant de fois qu'il l'a été.
        for e in dernier_par_ref([e for e in evs
                                  if e["type"] == "du" and e.get("op") in ("ouvre", "remplace")
                                  and e.get("ref") not in sortis]):
            ref = e.get("ref")
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
                           ref in inferee, depuis, P.get(ref)))
    lignes.sort(key=lambda x: -x[0])
    # SORTIE MACHINE pour le tableau d'`os-audit` et le démarrage : les MÊMES lignes, sans
    # leur texte — un texte de du peut porter du client, la page part sur claude.ai. Le tableau lit
    # ceci plutôt que de recalculer l'âge : une seule implantation.
    if getattr(a, "json", False):
        # Nommé depuis son DÉPÔT, jamais depuis le dossier personnel : les dépôts sont des liens
        # vers un chemin propre au poste, que `realpath` ferait entrer dans la page.
        racine_sys = os.path.realpath(os.path.expanduser("~/.claude"))
        def _nom(n):
            d = racine_depot(n)
            r = os.path.relpath(os.path.realpath(n), d)
            # Un sous-niveau du depot systeme garde son chemin : « systeme » seul le confondait
            # avec la racine, et le demarrage ne retrouvait plus son texte.
            return ("systeme" if d == racine_sys else os.path.basename(d)) + ("" if r == "." else "/" + r)
        print(json.dumps([{"niveau": _nom(niv), "ref": ref, "chantier": ch, "age": j,
                           "infere": inf, "depuis": dep, "dormant": dort(dep, por),
                           "porteur": por}
                          for j, niv, ref, ch, _t, inf, dep, por in lignes], ensure_ascii=False))
        return 0
    if not lignes:
        print("[etat] aucun du ouvert.")
        return 0
    dormants = [l for l in lignes if dort(l[6], l[7])]
    actifs = [l for l in lignes if not dort(l[6], l[7])]
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
    for jours, niveau, ref, chantier, texte, infere, depuis, porteur in (
            montres[:limite] if limite else montres):
        court = os.path.basename(niveau) if niveau != os.path.expanduser("~/.claude") else "systeme"
        age = (f"~{jours} j" if infere else f"{jours} j") if jours >= 0 else "date illisible"
        print(f"[{age}] {court} · {chantier} · {ref}")
        # Le marqueur ouvre la LIGNE DE TEXTE et non l'en-tete : `boot-check.sh` lit l'en-tete par
        # un motif ancre (`^\[age\] niveau · chantier · ref$`), qu'un emoji casserait en silence.
        print("    " + marque_porteur(porteur) + " " + re.sub(r"\s+", " ", texte).strip()[:170])
    n_inf = sum(1 for l in montres if l[5])
    print(f"\n[etat] {len(lignes)} du(s) ouvert(s) sur "
          f"{len(set(l[1] for l in lignes))} niveau(x).")
    _c = {}
    for l in montres:
        _c[l[7]] = _c.get(l[7], 0) + 1
    print("[etat] porteur des dus listés : " + " · ".join(
        f"{marque_porteur(k)} {k or 'sans porteur'} {_c[k]}"
        for k in [*PORTEURS, None] if _c.get(k)) + ".")
    if dormants and not getattr(a, "dormants", False):
        print(f"[etat] {len(dormants)} dormant(s) non touche(s) depuis plus de "
              f"{DORMANT_JOURS} j, hors de cette liste — etat.py fils "
              f"{'--tous' if getattr(a, 'tous', False) else '--niveau <niveau>'} --dormants")
    # DEUX COMPTES, JAMAIS UN. « dormant » = pas touché ; « vieux » = âge réel. Ils divergent dès
    # qu'une migration touche en masse.
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
    p.add_argument("--porteur", choices=list(PORTEURS),
                   help="sur un du : QUI fait le prochain geste — un seul ; herite sur reformulation")
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
    p.add_argument("--json", action="store_true",
                   help="tous les dus ouverts en JSON, sans leur texte (tableau d'os-audit)")
    p.set_defaults(fn=cmd_fils)

    a = ap.parse_args()
    if getattr(a, "tous", False) is False and getattr(a, "niveau", None) is None:
        ap.error("--niveau est requis sans --tous")
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
