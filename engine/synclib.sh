#!/usr/bin/env bash
# =============================================================================
# SYNCLIB — détection de dérive live<->repo. À SOURCER, pas exécuter.
# Dérive le périmètre du MANIFESTE (claudeos_pairs, config.sh) — plus aucune liste
# codée en dur (corrige le bug historique : une workstation ignoré par la dérive).
# Requiert config.sh déjà sourcé (ROOT, claudeos_pairs, SYNC_IGNORE).
# =============================================================================

# claudeos_drift MISSING DIFFERS : remplit deux tableaux de CHEMINS LIVE ABSOLUS.
#   MISSING = présent dans le miroir repo, ABSENT en live (sync jamais appliqué).
#   DIFFERS = présent des deux côtés, CONTENU différent (édition live non sauvegardée).
#
# Délégué à rsync le 2026-08-06, avec le MÊME fichier d'exclusion que backup/sync.
# Motif : la boucle bash précédente parcourait le repo sans lire SYNC_IGNORE, donc tout
# fichier committé AVANT son exclusion ressortait en DIFFERS à perpétuité — des dizaines de fantômes
# venant de fichiers gelés par une exclusion posée après coup. DIFFERS était devenu inexploitable, au point
# que le post-check de sync.sh avait cessé de le lire : une mesure fausse a désarmé le
# contrôle qu'elle devait servir.
# --checksum compare le CONTENU et pas l'horodatage : la mémoire auto est copiée par cp
# sans -p, son mtime diffère donc toujours des deux côtés sans que rien n'ait bougé.
# Le cas 'dossier live absent' (poste neuf) reste couvert : rsync -n sur une destination
# inexistante rend tout le contenu en +++++++++ sans rien créer. Vérifié sur pièce.
claudeos_drift() {
    local -n _missing="$1" _differs="$2"
    _missing=(); _differs=()
    local live_root repo_root regime code rel line
    while IFS=$'\t' read -r live_root repo_root regime; do
        [[ -d "$repo_root" ]] || continue
        while IFS= read -r line; do
            code="${line%% *}"; rel="${line#* }"
            [[ "$code" == ">f"* ]] || continue          # dossiers et méta ignorés
            if [[ "$code" == ">f+++++++++" ]]; then _missing+=("$live_root/$rel")
            else _differs+=("$live_root/$rel"); fi
        done < <(rsync -rin --dry-run --checksum --exclude-from="$SYNC_IGNORE" \
                       "$repo_root/" "$live_root/" 2>/dev/null)
    done < <(claudeos_pairs)
}

# =============================================================================
# claudeos_refused_by_lock : émet un chemin de dépôt par ligne — les fichiers présents dans
# l'arbre du dépôt et refusés par la RÈGLE DU VERROU (`*`) de `.gitignore`. Les journaux et
# verrous exclus NOMMÉMENT avant le verrou sont écartés : ils sont refusés par décision, les
# remonter ferait du bruit qu'on apprend à ignorer.
#
# On n'imite pas git, on l'interroge : `check-ignore -v` dit par QUELLE règle chaque fichier
# est refusé, et c'est la règle citée qui discrimine — un motif `*` en fin de champ.
#
# EXTRAITE de backup.sh le 2026-08-09 pour un second appelant, `boot-check.sh`. Motif :
# le refus du verrou n'était annoncé qu'au moment de la sauvegarde, donc en fin de séance,
# dans une sortie que le hook redirige vers un journal que personne ne lit. Un fichier refusé
# n'existe plus que sur un poste, et c'est la perte de continuité la plus sournoise du système.
# Une seule implémentation pour les deux appelants : deux copies de cette logique vieilliraient
# à deux âges, et c'est le plus silencieux des deux qui deviendrait muet sans le dire.
claudeos_refused_by_lock() {
    git -C "$ROOT" ls-files --others --ignored --exclude-standard -z 2>/dev/null \
        | xargs -0 -r git -C "$ROOT" check-ignore -v -- 2>/dev/null \
        | awk -F'\t' '$1 ~ /:\*$/ {print $2}'
}

# =============================================================================
# Avertissements de l'autotest — état partagé entre la sauvegarde et le démarrage.
#
# MOTIF (2026-08-14) : backup.sh lançait selftest.sh en jetant TOUTE sa sortie
# (>/dev/null 2>&1) et n'en gardait que le code de retour. Or l'autotest porte des
# dizaines d'appels à `warn`, et dans le chemin automatique — le hook de fin de
# session — aucun n'était jamais vu par personne : un avertissement n'existait que si
# quelqu'un relançait la commande à la main. Reclasser un contrôle de bloquant à
# avertissement revenait donc à l'éteindre en silence.
#
# LE MÉCANISME. La sauvegarde enregistre les lignes ⚠ du dernier passage dans
# `engine/selftest-warnings.log`, première ligne = la DATE DEPUIS LAQUELLE L'ENSEMBLE
# EST INCHANGÉ. Les deux canaux existants relaient : la fin de sauvegarde (backup.sh)
# et le bilan de démarrage (boot-check.sh, bloc ALERTES). ANTI-BRUIT, et c'est le
# point : le détail ne s'affiche que le jour où l'ensemble change ; ensuite une seule
# ligne — compte, ancienneté, commande de détail — parce qu'un avertissement répété à
# l'identique pendant des semaines apprend à ignorer la catégorie entière (doctrine de
# la compétence controles-et-alarmes). L'ancienneté affichée dit d'elle-même qu'un
# avertissement traîne ; le traiter fait disparaître la ligne à la sauvegarde suivante.
# Le fichier est LOCAL, jamais sauvegardé : chez l'auteur par une ligne nommée du
# verrou, chez un destinataire par le motif `engine/*.log` que l'installeur pose —
# c'est ce motif qui a décidé du nom. Une seule implémentation pour les deux lecteurs,
# même règle que claudeos_refused_by_lock : deux copies vieilliraient à deux âges.
# =============================================================================

# claudeos_selftest_warns_record FICHIER — extrait les ⚠ de la sortie complète de
# selftest.sh et met l'état à jour. Aucun avertissement = fichier retiré : l'alerte
# disparaît quand on la traite, jamais avant.
claudeos_selftest_warns_record() {
    local etat="$SELF/selftest-warnings.log" nouveaux="" depuis
    nouveaux="$(grep '⚠' "$1" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)"
    if [ -z "$nouveaux" ]; then rm -f "$etat"; return 0; fi
    depuis="$(date '+%Y-%m-%d')"
    if [ -f "$etat" ] && [ "$nouveaux" = "$(tail -n +2 "$etat")" ]; then
        depuis="$(head -1 "$etat")"
    fi
    { echo "$depuis"; printf '%s\n' "$nouveaux"; } > "$etat"
    return 0
}

# claudeos_selftest_warns_bilan — émet « DEPUIS<TAB>COMPTE » puis les lignes ⚠, et
# rien du tout s'il n'y a aucun avertissement enregistré.
claudeos_selftest_warns_bilan() {
    local etat="$SELF/selftest-warnings.log" n
    [ -f "$etat" ] || return 0
    n="$(tail -n +2 "$etat" | grep -c . || true)"
    [ "${n:-0}" -gt 0 ] || return 0
    printf '%s\t%s\n' "$(head -1 "$etat")" "$n"
    tail -n +2 "$etat"
    return 0
}

# =============================================================================
# Régime 'memory' — gestion dédiée (extraite de backup.sh / sync.sh). Les deux sens
# font un travail de SÉCURITÉ différent (pas de duplication) : la sauvegarde garde
# contre l'écrasement, la restauration snapshot + propage les suppressions. Requiert
# config.sh sourcé (SYNC_MEM_MARKERS). Ces fonctions restent le seul cas particulier
# du régime memory ; additif/miroir demeurent des one-liners rsync inline.
# =============================================================================

# claudeos_mem_backup LIVE REPO — copie la mémoire auto live -> repo.
# Garde anti-écrasement : refuse de retirer du repo un .md absent en local (poste
# probablement non synchronisé), sauf FORCE_MEM_DELETE=1. Codes de retour :
#   0 ok · 1 échec de copie · 2 anti-écrasement (message émis, abandon requis)
#   3 dossier mémoire live absent (message émis, à ignorer/continuer)
claudeos_mem_backup() {
    local live="$1" repo="$2" repo_f base marker live_md rc=0
    [[ -d "$live" ]] || { echo "[backup] WARN : dossier mémoire auto introuvable ($live)" >&2; return 3; }
    if [[ -d "$repo" ]]; then
        local -a MISSING=()
        for repo_f in "$repo"/*.md; do
            [[ -e "$repo_f" ]] || continue
            base="$(basename "$repo_f")"
            [[ -f "$live/$base" ]] || MISSING+=("$base")
        done
        if [[ ${#MISSING[@]} -gt 0 && "${FORCE_MEM_DELETE:-0}" != "1" ]]; then
            echo "[backup] ERREUR : fichiers mémoire dans le repo mais absents en local :" >&2
            for base in "${MISSING[@]}"; do echo "  - $base" >&2; done
            echo "[backup] Machine probablement non synchronisée. Lance : bash ~/.claudeos/engine/sync.sh" >&2
            echo "[backup] Suppression VOULUE : FORCE_MEM_DELETE=1 bash ~/.claudeos/engine/backup.sh" >&2
            return 2
        fi
    fi
    # ÉCRITURE SANS FENÊTRE DE DESTRUCTION (2026-08-09). Avant : `rm -rf "$repo"` PUIS copie.
    # Un échec de copie — disque plein, fichier illisible, process tué entre les deux — laissait
    # le dépôt VIDÉ de sa mémoire jusqu'au prochain passage réussi, et le refus d'état partiel de
    # `backup.sh` empêchait alors de committer, donc rien ne réparait tout seul. La mémoire auto
    # est la seule chose de ce système qu'aucune autre copie ne porte : une fenêtre où elle
    # n'existe nulle part est le pire état atteignable.
    # Désormais : on remplit un répertoire temporaire à CÔTÉ de la cible, et on ne bascule
    # qu'après une copie entièrement réussie. L'ancien contenu survit à tout échec, et la
    # bascule est un couple de renommages dans le même système de fichiers — le dépôt est
    # soit entièrement à l'ancien état, soit entièrement au nouveau, jamais à moitié.
    # Le temporaire est nettoyé À L'ENTRÉE autant qu'à la sortie : un résidu de passage tué
    # serait sinon remonté par le rapport des refus de la liste blanche à chaque sauvegarde.
    local tmp="$repo.tmp" old="$repo.old"
    rm -rf "$tmp" "$old"
    mkdir -p "$tmp" || { echo "[backup] ERREUR : temporaire mémoire impossible ($tmp)" >&2; return 1; }
    # BOUCLE EXPLICITE et non `find -exec` (2026-08-09). Le `|| rc=1` posé sur `find` ne
    # pouvait PAS se déclencher : `find` ne répercute pas le code de retour de son `-exec`, il
    # ne rend non nul que ses propres erreurs de parcours. Exercé sur pièce en rendant un
    # fichier source illisible — `cp` criait, `find` rendait 0, la garde restait muette et la
    # copie basculait AMPUTÉE de ce fichier. La garde d'écriture sans fenêtre écrite juste
    # au-dessus n'aurait donc rien gardé : elle repose entièrement sur la détection de l'échec.
    # `-print0` + `read -d ''` : les noms de fichiers de mémoire sont sages, mais un séparateur
    # nul est le seul qui ne puisse pas se trouver dans un nom.
    while IFS= read -r -d '' live_md; do
        cp "$live_md" "$tmp/" \
            || { echo "[backup] ERREUR : échec copie mémoire auto ('$live_md')" >&2; rc=1; }
    done < <(find "$live" -maxdepth 1 -name "*.md" -print0)
    for marker in "${SYNC_MEM_MARKERS[@]}"; do
        [[ -f "$live/$marker" ]] && { cp "$live/$marker" "$tmp/$marker" || rc=1; }
    done
    if [[ $rc -ne 0 ]]; then
        rm -rf "$tmp"
        echo "[backup] mémoire auto : le dépôt garde son état antérieur (aucune suppression faite)." >&2
        return $rc
    fi
    # Bascule. Si le premier renommage échoue, rien n'a bougé ; si le second échoue, on remet
    # l'ancien en place — dans les deux cas le dépôt sort de cette fonction dans un état complet.
    if [[ -d "$repo" ]]; then
        mv "$repo" "$old" || { rm -rf "$tmp"; echo "[backup] ERREUR : bascule mémoire impossible ($repo)" >&2; return 1; }
    fi
    if ! mv "$tmp" "$repo"; then
        echo "[backup] ERREUR : bascule mémoire échouée — restauration de l'état antérieur." >&2
        [[ -d "$old" ]] && mv "$old" "$repo"
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$old"
    return $rc
}

# claudeos_mem_restore LIVE REPO BK_DIR — applique la mémoire auto repo -> live.
# Filet : snapshot dans BK_DIR de tout .md live écrasé par une version DIFFÉRENTE ou
# retiré (absent du repo), AVANT le geste — jamais de perte sèche d'un écrit non commité.
# Propage les suppressions (parité avec le miroir). Codes : 0 ok · 1 échec de copie.
claudeos_mem_restore() {
    local live="$1" repo="$2" bk="$3" repo_f live_f base marker rc=0
    mkdir -p "$live"
    for repo_f in "$repo"/*.md; do
        [[ -e "$repo_f" ]] || continue
        base="$(basename "$repo_f")"
        if [[ -f "$live/$base" ]] && ! cmp -s "$repo_f" "$live/$base"; then
            mkdir -p "$bk/$(basename "$live")"
            cp "$live/$base" "$bk/$(basename "$live")/$base"
        fi
    done
    # LE `2>/dev/null` GLOBAL EST RETIRÉ (2026-08-09). Il était là pour absorber le seul cas
    # bénin — un dépôt sans aucun `.md`, où le motif ne se développe pas et `cp` se plaint d'un
    # fichier littéral inexistant. Mais il absorbait AUSSI tous les autres : droits, disque
    # plein, fichier illisible. On voyait `rc=1` sans jamais savoir pourquoi, sur le sens de
    # transfert qui écrit dans la mémoire VIVANTE. Le cas bénin est désormais traité par un
    # test, ce qui rend au message d'erreur son unique métier : dire ce qui a réellement cassé.
    local -a repo_mds=("$repo"/*.md)
    if [[ -e "${repo_mds[0]}" ]]; then
        cp "${repo_mds[@]}" "$live/" || { echo "[sync] ERREUR : échec mémoire auto (copie dépôt -> live)" >&2; rc=1; }
    else
        echo "[sync] WARN : aucun .md dans le dépôt ($repo) — rien à restaurer côté mémoire auto." >&2
    fi
    for live_f in "$live"/*.md; do
        [[ -e "$live_f" ]] || continue
        base="$(basename "$live_f")"
        if [[ ! -f "$repo/$base" ]]; then
            mkdir -p "$bk/$(basename "$live")"
            mv "$live_f" "$bk/$(basename "$live")/$base" \
                && echo "[sync] mémoire : '$base' absent du repo → retiré du live (filet : $bk)"
        fi
    done
    # MARQUEURS SNAPSHOTÉS eux aussi (2026-08-09). Les `.md` l'étaient depuis l'origine, pas
    # eux : le marqueur de distillation était écrasé en sec par la version du dépôt. Or il porte
    # une SEMAINE — l'écraser par une valeur plus ancienne redéclare la distillation due, et par
    # une plus récente la déclare faite alors qu'elle ne l'est pas sur ce poste. Dans les deux
    # cas l'écrit local disparaissait sans filet, seul de son espèce dans cette fonction.
    for marker in "${SYNC_MEM_MARKERS[@]}"; do
        [[ -f "$repo/$marker" ]] || continue
        if [[ -f "$live/$marker" ]] && ! cmp -s "$repo/$marker" "$live/$marker"; then
            mkdir -p "$bk/$(basename "$live")"
            cp "$live/$marker" "$bk/$(basename "$live")/$marker" || rc=1
        fi
        cp "$repo/$marker" "$live/$marker" \
            || { echo "[sync] ERREUR : échec copie du marqueur '$marker'" >&2; rc=1; }
    done
    return $rc
}
