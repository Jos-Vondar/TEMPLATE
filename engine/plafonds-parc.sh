#!/usr/bin/env bash
# plafonds-parc.sh — quels fichiers d'état dépassent leur plafond, sur TOUT le parc.
#
# POURQUOI CE SCRIPT EXISTE, et pourquoi il n'est PAS un contrôle de `weekly-check.sh`.
# Le contrôle 29 mesurait le parc ; il a été retiré le 2026-09-08 (geste 2.7). Depuis, seul le
# crochet de commit mesure — et il ne voit que ce qu'on met en file, donc jamais le parc. L'audit
# du 2026-09-09 a relevé le trou. Arbitrage de l'utilisateur le même jour, variante (a) :
# un script appelé par la passe hebdomadaire, HORS `weekly-check.sh`. Motif du hors-contrôle :
# `CLAUDEOS_CLIQUET_CONTROLES` est à sa borne exacte, donc un contrôle de plus n'entre qu'en
# faisant sortir un autre — et aucun ne le méritait.
# CE QUE ÇA COÛTE, écrit pour que personne ne le redécouvre : le parc n'est mesuré qu'au commit
# (par fichier, contrôle 8) et à la passe (ici, en entier). Jamais en continu.
#
# LES COMMENTAIRES HTML SONT EXCLUS, et ce n'est pas cosmétique : le contrôle 29 les excluait, le
# crochet qui lui survit ne le fait pas. Mesuré le 2026-09-09 — trois fichiers du parc passent
# sous leur plafond une fois l'en-tête de commentaire retiré. Les compter ferait verser du texte
# utile pour un défaut de méthode. Les deux mesures sont donc affichées, brute et nette.
#
# LES FICHIERS GELÉS SONT EXCLUS, et c'est ce qui rend ce script utile après la phase 3. Un fichier
# dont la première ligne porte l'en-tête de gel est en LECTURE SEULE — le contrôle 14 du crochet
# refuse toute modification (code 24). Le mesurer contre un plafond demande un allègement que la
# machine interdit. Mesuré le 2026-09-09 à la passe de ménage : les ONZE fichiers signalés étaient
# gelés, soit 100 % de faux positifs, tous nés de la bascule du jour même. Un signal dont on sait
# qu'il ne faut pas l'écouter fait ignorer la catégorie entière (`controles-et-alarmes`).
#
# UNITÉ : le CARACTÈRE, jamais l'octet (~3 % d'écart sur du français, et ce système l'a déjà payé).
# La valeur de chaque plafond se relit dans `engine/config.sh`, elle ne se recopie pas ici.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

_n=0
_gel=0
_vus=0
# `claudeos_racines` et `claudeos_suivis` (`lib_regime.sh`) : sans git, `~/.claude` et son périmètre.
for _r in $(claudeos_racines); do
    _repo="$(basename "$_r")"
    for _f in $(claudeos_suivis "$_r" '*MEMORY.md' '*ETAT.md' MEMORY.md ETAT.md 2>/dev/null); do
        _p="$(claudeos_plafond_de "$_repo/$_f" 2>/dev/null)" || continue   # hors régime : pas de plafond
        _full="$_r/$_f"
        [ -f "$_full" ] || continue
        # gelé = lecture seule, donc pas d'allègement possible : hors mesure (voir en-tête)
        case "$(head -1 "$_full")" in '> **GELÉ'*) _gel=$((_gel + 1)); continue ;; esac
        _vus=$((_vus + 1))
        # COMPTE PAR python3, POSÉ LE 2026-09-22. `wc -m` rend le bon compte sur ce Mac —
        # mesuré, `C.UTF-8` y existe et GNU comme BSD la respectent, donc ce n'est PAS une
        # panne réparée ici. Le motif est la DÉPENDANCE : le résultat tenait à quel `wc` le
        # PATH résout, à quelle locale et à quelle implémentation, trois variables dont
        # aucune n'est maîtrisée dans un hook. `python3` est déjà exigé par le moteur.
        _brut="$(python3 -c "import sys;print(len(open(sys.argv[1],encoding='utf-8',errors='surrogateescape').read()))" "$_full")"
        _net="$(python3 -c "import re,sys;print(len(re.sub(r'<!--.*?-->','',open(sys.argv[1],encoding='utf-8').read(),flags=re.S)))" "$_full")"
        if [ "$_brut" -gt "$_p" ] || [ "$_net" -gt "$_p" ]; then
            _n=$((_n + 1))
            printf 'brut=%6d net=%6d plafond=%5d %s\n' "$_brut" "$_net" "$_p" "$_repo/$_f"
        fi
    done
done
if [ "$_n" -eq 0 ]; then
    echo "[plafonds] ✅ aucun fichier d'état VIVANT au-dessus de son plafond, sur les $(claudeos_racines | wc -l | tr -d ' ') racine(s) — $_vus mesuré(s), $_gel gelé(s) écarté(s)."
else
    echo "[plafonds] ⚠ $_n fichier(s) au-dessus sur $_vus mesuré(s), $_gel gelé(s) écarté(s). « net » exclut les commentaires HTML : un fichier"
    echo "[plafonds]   au-dessus en brut mais sous en net n'a pas de contenu à verser, il a un en-tête."
fi
