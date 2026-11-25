#!/usr/bin/env python3
"""Test de contrat d'`etat.py` : chaque op du contrat exercée contre la projection.

Rejouer après toute modification d'`engine/etat.py` :

    python3 ~/.claude/engine/tests/test_etat.py

Code retour 0 si tout est conforme, 1 sinon. Tout se joue dans un dossier temporaire : aucun
journal réel n'est touché. Les sous-commandes (`add`, `fils`, `projette`) sont lancées sur
`etat.py` lui-même, par son chemin. Il se joue dans les deux régimes : sans git utilisable, le
niveau jetable du témoin 7 se marque comme une racine sans git (`regime.py`).
"""
import json
import os
import subprocess
import sys

ENGINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETAT = os.path.join(ENGINE, "etat.py")
sys.path.insert(0, ENGINE)
import etat  # noqa: E402
from etat import (OPS, PREFIXE_REF, OPS_A_MOTIF, TEXTE_MAX_PROJETE, DORMANT_JOURS,  # noqa: E402
                  valide, projette, journaux)


def autotest():
    """Exerce CHAQUE op du contrat contre la PROJECTION, pas seulement contre le refus.

    Un témoin qui vérifie qu'un événement mal formé est refusé ne dit rien de ce que la
    projection fait d'un événement BIEN formé : une op au contrat mais inconnue du projecteur
    ferait sortir l'ancienne ref sans faire entrer la nouvelle, en silence, et un témoin qui ne
    regarderait que la sortie passerait au vert.

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
            #    LE MARQUEUR DÉPEND DU TYPE : une `decision` et un `du` sont projetés par leur
            #    REF, un `pointeur` par son TEXTE, un `etat` par son CHANTIER.
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

        # 4. LA BORNE PAR TYPE. Exercée sur `valide` et non sur la projection : cette borne
        #    REFUSE à l'écriture, donc c'est le refus qu'on mesure. Une garde sans test se perd
        #    au prochain remaniement, et un contrôle muet est PIRE qu'un contrôle absent — il
        #    fait croire à une couverture.
        #    LES DEUX BORDS SONT ÉPROUVÉS : `borne` doit passer, `borne + 1` doit être refusé
        #    PAR LA BORNE et non par autre chose — d'où le contrôle du mot dans le message : une
        #    sonde refusée pour un chantier hors forme de slug mesurerait la forme du chantier au
        #    lieu de la longueur du texte.
        def _sonde(t, op, n):
            ev = {"ts": "2026-01-01T09:00:00+01:00", "id": "e-20260101-090000-abcd",
                  "niveau": ".", "poste": "autotest", "type": t, "op": op, "texte": "x" * n}
            if t in PREFIXE_REF:
                ev["ref"] = PREFIXE_REF[t] + "sonde"
            if t in ("du", "etat"):
                ev["chantier"] = "autotest"
            # `source` est due sur pointeur ET observation. Oubliée sur le second, la sonde
            # mesurerait « source manquante » et non la longueur — le témoin ci-dessous le voit.
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

        # 5. LE GARDE « ref == remplace ». Même raison que la borne ci-dessus : une garde sans
        #    test se perd au prochain remaniement. Exercé sur `valide`, puisque le refus vit à
        #    l'écriture, sur `du` ET sur `decision`.
        #    LES DEUX BORDS, et le second est le témoin du premier : le cas SAIN — remplacement
        #    par une ref NEUVE — doit continuer de PASSER. Un garde qui refuserait les deux
        #    rendrait `remplace` inutilisable en se faisant passer pour une protection.
        #    LE DÉFAUT QU'IL FERME : `--ref X --remplace X` ferait sortir X de la projection par
        #    lui-même, `check` dirait conforme, et le fil disparaîtrait de ETAT.md sans un mot.
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

        # 6. LE GARDE D'EXISTENCE SUR LES RETRAITS. Le défaut qu'il ferme : `pointeur --op
        #    retire` sur une ref jamais ajoutée serait ACCEPTÉ, écrit au journal, et la
        #    projection ne bougerait pas — sans un mot ; l'auteur croirait le pointeur retiré.
        #    LE GARDE NE VIT PAS DANS `valide` — il a besoin du journal — donc il s'exerce à
        #    part, sur les six couples qui font sortir quelque chose de la projection, et sur
        #    LES DEUX BORDS : sans pose il doit refuser, avec pose il doit laisser passer.
        _garde = getattr(etat, "garde_existence", None)
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
            open(os.path.join(niv, etat.regime.MARQUE_RACINE), "w").close()
            _gi = subprocess.CompletedProcess([], 0, "", "")
        if _gi.returncode != 0:
            echecs.append(f"garde de bout en bout : `git init` du niveau jetable a échoué "
                          f"({_gi.stderr.strip()[:120]}) — témoin non joué")
        else:
            def _add(*args):
                r = subprocess.run([sys.executable, ETAT, "add",
                                    "--niveau", niv, *args], capture_output=True, text=True)
                return r.returncode, r.stderr
            ici = ETAT
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

        # 8. LA DORMANCE, LES DEUX BORDS. Un du touché AUJOURD'HUI reste
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
            # QUATRIÈME BORD : aussi vieux que le dormant, mais porté par l'utilisateur, dont un
            # du ne dort jamais — il reste dans `fils`.
            {"ts": f"{_vieux}T09:00:00+01:00", "id": "e-dorm-0003-cccc", "niveau": ".",
             "poste": "autotest", "type": "du", "op": "ouvre", "ref": "u-temoin-utilisateur",
             "chantier": "autotest", "texte": "geste de l utilisateur jamais retouche",
             "source": "engine/etat.py", "porteur": "utilisateur"},
        ]
        with open(os.path.join(niv2, "journal", f"{_auj:%Y-%m}.jsonl"), "w",
                  encoding="utf-8") as _f:
            for _e in _evs2:
                _f.write(json.dumps(_e, ensure_ascii=False) + "\n")

        def _fils(*args):
            r = subprocess.run([sys.executable, ETAT, "fils",
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
        if "u-temoin-utilisateur" not in out_a:
            echecs.append("dormance : le du de l'UTILISATEUR non touché est sorti de `fils` — "
                          "son geste disparaîtrait du bilan sans avoir été fait")
        if "1 dormant(s)" not in out_a:
            echecs.append(f"dormance : `fils` ne compte pas le dormant au pied de sa liste "
                          f"({out_a.strip()[-160:]!r}) — il sortirait sans un mot")

        joues += 1
        rc_b, out_b = _fils("--dormants")
        if "u-temoin-dormant" not in out_b or "u-temoin-actif" in out_b:
            echecs.append(f"dormance : `fils --dormants` ne rend pas EXACTEMENT les dormants "
                          f"({out_b.strip()[:200]!r}) — le dormant serait irrécupérable")

        joues += 1
        _r1 = subprocess.run([sys.executable, ETAT, "projette",
                              "--niveau", niv2], capture_output=True, text=True)
        _etat1 = open(os.path.join(niv2, "ETAT.md"), encoding="utf-8").read()
        if "u-temoin-dormant" not in _etat1:
            echecs.append("dormance : le du dormant a DISPARU d'ETAT.md — la règle a touché la "
                          "projection, donc `check` criera (code 23) au passage du seuil")

        # 9. UN FIL REFORMULÉ SORT UNE FOIS DE `fils`, dans sa DERNIÈRE formulation — la règle de
        #    la projection (`dernier_par_ref`). Sans elle, un du ouvert puis reformulé deux fois
        #    sortirait trois fois, ses anciens textes compris, et le total le compterait trois
        #    fois. Le fil jamais reformulé est le témoin du témoin : une vue vide rendrait aussi
        #    « aucune ligne en double ». MÊME PASSE : une `origine` EXPLICITE posée à la
        #    reformulation retire le tilde qu'une date du texte précédent avait posé — l'âge est
        #    alors mesuré, pas inféré.
        niv3 = os.path.join(tmp, "niveau-reformule")
        os.makedirs(os.path.join(niv3, "journal"))
        _evs3 = []
        for _i, (_ref, _txt, _orig) in enumerate([
                ("u-temoin-reformule", "formulation un", None),
                ("u-temoin-reformule", "formulation deux", None),
                ("u-temoin-reformule", "formulation trois", None),
                ("u-temoin-seul", "fil jamais reformule", None),
                ("u-temoin-tilde", "vu le 2026-01-05, a reprendre", None),
                ("u-temoin-tilde", "reformule avec sa naissance", "2026-01-03")], 1):
            _e = {"ts": f"{_auj}T09:00:{_i:02d}+01:00", "id": f"e-refo-000{_i}-abcd",
                  "niveau": ".", "poste": "autotest", "type": "du", "op": "ouvre",
                  "ref": _ref, "chantier": "autotest", "texte": _txt,
                  "source": "engine/etat.py"}
            if _orig:
                _e["origine"] = _orig
            _evs3.append(_e)
        with open(os.path.join(niv3, "journal", f"{_auj:%Y-%m}.jsonl"), "w",
                  encoding="utf-8") as _f:
            for _e in _evs3:
                _f.write(json.dumps(_e, ensure_ascii=False) + "\n")

        joues += 1
        _r3 = subprocess.run([sys.executable, ETAT, "fils", "--niveau", niv3],
                             capture_output=True, text=True)
        out_c = _r3.stdout
        _tetes = [l for l in out_c.splitlines() if l.startswith("[")]
        _n_ref = sum(1 for l in _tetes if l.endswith(" · u-temoin-reformule"))
        if _r3.returncode != 0 or not any(l.endswith(" · u-temoin-seul") for l in _tetes):
            echecs.append(f"fil reformulé : `fils` ne liste pas le fil témoin jamais reformulé "
                          f"(rc={_r3.returncode}, {_r3.stderr.strip()[:160]!r}) — aucun verdict "
                          f"ci-dessous ne vaut")
        if _n_ref != 1:
            echecs.append(f"fil reformulé : u-temoin-reformule sort {_n_ref} fois de `fils` au "
                          f"lieu d'une — chaque reformulation y reste, ancien texte compris")
        if "formulation trois" not in out_c or "formulation un" in out_c \
                or "formulation deux" in out_c:
            echecs.append("fil reformulé : `fils` ne montre pas SEULEMENT la dernière "
                          "formulation du fil")
        if "[etat] 3 du(s) ouvert(s)" not in out_c:
            echecs.append(f"fil reformulé : le total ne compte pas trois dus ouverts "
                          f"({[l for l in out_c.splitlines() if 'ouvert(s)' in l]!r}) — un fil "
                          f"reformulé y est compté plusieurs fois")
        if any(l.startswith("[~") and l.endswith(" · u-temoin-tilde") for l in _tetes):
            echecs.append("fil reformulé : l'âge de u-temoin-tilde reste marqué INFÉRÉ alors "
                          "qu'une origine explicite a été posée")

        # 10. POINTEUR DONT LA DERNIÈRE VERSION VIT DANS UN CHANTIER FERMÉ. Filtrer le chantier AVANT
        #    de prendre la dernière version par ref fait revenir une version ANTÉRIEURE, rangée
        #    ailleurs : un pointeur périmé ressort dans « Où trouver » sans un mot. Attendu : absent.
        joues += 1
        _evs3 = [
            {"ts": "2026-01-01T09:00:00+01:00", "id": "e-ptr-0001-aaaa", "niveau": ".",
             "poste": "autotest", "type": "pointeur", "op": "ajoute", "ref": "p-temoin-ferme",
             "texte": "version ancienne sans chantier", "source": "engine/etat.py"},
            {"ts": "2026-01-02T09:00:00+01:00", "id": "e-ptr-0002-bbbb", "niveau": ".",
             "poste": "autotest", "type": "pointeur", "op": "ajoute", "ref": "p-temoin-ferme",
             "chantier": "chantier-temoin", "texte": "version neuve", "source": "engine/etat.py"},
            {"ts": "2026-01-03T09:00:00+01:00", "id": "e-ptr-0003-cccc", "niveau": ".",
             "poste": "autotest", "type": "etat", "op": "ferme", "chantier": "chantier-temoin",
             "texte": "chantier clos"},
        ]
        _ptrs = [e.get("ref") for e in etat.projection_vivante(_evs3)[2]]
        if "p-temoin-ferme" in _ptrs:
            echecs.append("pointeur : la dernière version vit dans un chantier FERMÉ, et une "
                          "version antérieure rangée ailleurs est REVENUE dans la projection")

    if echecs:
        print(f"[etat] autotest : {len(echecs)} ÉCHEC(S) sur {joues} op exercées", file=sys.stderr)
        for e in echecs:
            print(f"       {e}", file=sys.stderr)
        return 1
    print(f"[etat] autotest : {joues} op du contrat exercées contre la projection, toutes conformes")
    return 0


if __name__ == "__main__":
    sys.exit(autotest())
