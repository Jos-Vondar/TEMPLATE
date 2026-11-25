#!/usr/bin/env bash
# plafonds-parc.sh — quels fichiers d'état dépassent leur plafond, sur TOUT le parc.
#
# Le crochet de commit (contrôle 8) ne mesure que ce qu'on met en file, jamais le parc entier :
# ce script le fait, à la passe, HORS `weekly-check.sh`. Le parc n'est donc mesuré qu'au commit
# (par fichier) et à la passe (en entier), jamais en continu.
#
# DEUX MESURES, brute et nette : la nette exclut les commentaires HTML, que le crochet compte. Un
# fichier au-dessus en brut seulement a un en-tête, pas de contenu à verser.
#
# LES FICHIERS GELÉS SONT EXCLUS : en lecture seule (le crochet refuse toute modification, code
# 24), ils demanderaient un allègement interdit — un faux positif certain, qui ferait ignorer la
# catégorie entière.
#
# UNITÉ : le CARACTÈRE, jamais l'octet (environ 3 % d'écart sur du français).
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
        # Compté par python3 et non `wc -m` : le résultat de `wc` dépend du binaire que le PATH
        # résout et de la locale, deux variables non maîtrisées. `python3` est déjà exigé.
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
