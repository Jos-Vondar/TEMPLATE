#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# BACKUP — ClaudeOS. Sens live -> repo -> push.
# Lancé par le rituel de clôture ET par le hook SessionEnd (filet ; log backup-hook.log).
# Manuel : bash ~/.claudeos/engine/backup.sh
# Périmètre 100% dérivé du manifeste (config.sh / SYNC_MAP) — aucune liste en dur.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"
source "$SELF/synclib.sh"   # claudeos_mem_backup (régime mémoire, extrait ici)

# --- Refus des arguments inconnus ---
# Ce script ne prend AUCUN argument et commite pour de vrai. Un drapeau ignoré en silence
# (« --dry-run » par exemple, qui n'existe pas ici) fait croire à une simulation alors que
# la sauvegarde a lieu. Mieux vaut refuser que d'agir sur un malentendu.
if [ "$#" -gt 0 ]; then
    echo "[backup] ERREUR : argument inattendu ('$*'). backup.sh ne prend aucun argument et commite réellement." >&2
    echo "[backup] Pour inspecter sans écrire : git -C \"$ROOT\" status --short" >&2
    exit 2
fi

# --- Garde-fou remote (lu depuis config/REMOTE) ---
claudeos_require_remote backup || exit 1

# --- Verrou de concurrence (backup manuel vs hook SessionEnd, double session) ---
claudeos_lock backup || exit 1

# #4 : overrides granulaires, un par garde-fou — chacun n'éteint QUE le sien :
# FORCE_FRESH (fraîcheur), FORCE_SELFTEST, FORCE_SECRET, FORCE_BINARY, et FORCE_MEM_DELETE
# (garde anti-écrasement mémoire, plus bas — geste dédié car une perte de mémoire est grave).
# Pas de master global : outrepasser un garde-fou est un choix explicite, garde par garde.

# --- Garde-fou de fraîcheur : refuser de sauvegarder une machine en retard ---
# #7 : hors-ligne, le garde-fou de fraîcheur s'évalue sur une ref périmée (dégradé).
# On pose un marqueur pour que le boot le signale (sinon le WARN passe inaperçu en hook).
if git -C "$ROOT" fetch --quiet 2>/dev/null; then
    rm -f "$SELF/.last-offline-backup"
else
    echo "[backup] WARN : fetch impossible (hors-ligne ?) — garde-fou fraîcheur évalué sur ref périmée." >&2
    date '+%Y-%m-%d %H:%M' > "$SELF/.last-offline-backup"
fi
BEHIND="$(git -C "$ROOT" rev-list --count HEAD..@{u} 2>/dev/null || echo 0)"
if [[ "$BEHIND" -gt 0 && "${FORCE_FRESH:-0}" != "1" ]]; then
    echo "[backup] ERREUR : cette machine est en retard de $BEHIND commit(s) sur le remote." >&2
    echo "[backup] Probablement non synchronisée — backup refusé pour ne pas écraser du travail récent." >&2
    echo "[backup] Lance d'abord : bash ~/.claudeos/engine/sync.sh" >&2
    echo "[backup] Backup VOULU malgré le retard : FORCE_FRESH=1 bash ~/.claudeos/engine/backup.sh" >&2
    exit 1
fi

# Compteur d'échecs de copie : un backup partiel ne doit JAMAIS committer ni se
# taguer « known good ». Toute branche de copie l'incrémente ; refus avant commit.
COPY_ERRS=0
copy_file() {
    local src="$1" dest="$2"
    cp "$src" "$dest" || { echo "[backup] ERREUR : échec copie '$src' -> '$dest'" >&2; COPY_ERRS=$((COPY_ERRS+1)); }
    return 0
}

# --- Selftest plomberie (« fail before you ship ») ---
if ! bash "$SELF/selftest.sh" >/dev/null 2>&1; then
    if [[ "${FORCE_SELFTEST:-0}" != "1" ]]; then
        echo "[backup] ERREUR : selftest de plomberie en échec — backup refusé." >&2
        echo "[backup] Diagnostic : bash ~/.claudeos/engine/selftest.sh" >&2
        echo "[backup] Outrepasser : FORCE_SELFTEST=1 bash ~/.claudeos/engine/backup.sh" >&2
        exit 1
    fi
    echo "[backup] WARN : selftest en échec mais override actif — on continue." >&2
fi

# --- Régénérer l'index de rappel avant la copie mémoire ---
bash "$SELF/build-index.sh" >/dev/null || echo "[backup] WARN : échec build-index.sh" >&2
# Le registre des livrables n'est PLUS régénéré ici — décision du 2026-08-05. Il l'était à
# chaque fin de session, soit environ une fois par jour, pour un fichier de 15 Ko qu'aucun
# script ne lit et qui n'a été ouvert qu'une fois sur un mois. Il est désormais rafraîchi par
# la passe hebdomadaire d'audit, qui est le seul consommateur plausible : sa fraîcheur devient
# hebdomadaire et bornée au lieu d'être quotidienne et inutile. Le générateur reste en place.
bash "$SELF/build-threads.sh" >/dev/null || echo "[backup] WARN : échec build-threads (vue des fils ouverts non régénérée)" >&2

# --- Copie live -> repo, pilotée par le manifeste ---
# En SAUVEGARDE, tout dossier est capturé en miroir (--delete, denylist SYNC_IGNORE) :
# le dépôt reflète l'état authoré du live. Le régime additif/miroir ne joue qu'en sync.
# Seule la mémoire auto (régime 'memory') a un traitement dédié (garde anti-écrasement).
while IFS=$'\t' read -r live repo regime; do
    if [[ "$regime" == "memory" ]]; then
        # Régime mémoire : garde anti-écrasement + copie (voir synclib.sh). Codes :
        # 2 = anti-écrasement (abandon) · 3 = live absent (ignorer) · 1 = échec copie.
        rc=0; claudeos_mem_backup "$live" "$repo" || rc=$?
        case $rc in
            2) exit 1 ;;
            3) continue ;;
            1) COPY_ERRS=$((COPY_ERRS+1)) ;;
        esac
    else
        [[ -d "$live" ]] || continue
        mkdir -p "$repo"
        rsync -a --delete --exclude-from="$SYNC_IGNORE" "$live/" "$repo/" \
            || { echo "[backup] ERREUR : échec rsync $(basename "$repo")" >&2; COPY_ERRS=$((COPY_ERRS+1)); }
    fi
done < <(claudeos_pairs)

# --- Refus d'un backup partiel : une copie ratée = repo incomplet, jamais committé ---
# Pas d'override FORCE_* : un point de restauration « known good » sur un état partiel
# n'a aucun cas d'usage légitime.
if [[ "$COPY_ERRS" -gt 0 ]]; then
    echo "[backup] ⛔ ERREUR : $COPY_ERRS copie(s) en échec — le repo serait PARTIEL. Backup refusé (pas de commit, pas de tag)." >&2
    exit 1
fi

# --- Git staging ---
git -C "$ROOT" add -A

# --- Alarme binaires (#6) : bloque tout NOUVEAU binaire mis en file. L'alarme secret
# ci-dessous ne lit que le TEXTE (git diff) — elle est aveugle au contenu binaire, trou
# par lequel des .pdf/.docx client ont fuité. --diff-filter=A : seuls les AJOUTS comptent
# (un binaire déjà suivi et assumé ne re-sonne pas). numstat émet '-\t-\t<path>' si binaire.
# Aucune autorisation par défaut. Modèle, tiré d'un cas réel : un projet
# personnel sans donnée client : ses documents mis en page et ses ressources graphiques
# y sont des livrables assumés, pas un vecteur de fuite.
# Contrepartie côté synchronisation : même chemin en exception dans SYNC_IGNORE, sinon le PDF
# n'atteindrait jamais la file. Portée étroite et volontaire — ailleurs l'alarme reste armée.
NEW_BIN="$(git -C "$ROOT" diff --cached --numstat --diff-filter=A \
        2>/dev/null \
    | awk -F'\t' '$1=="-" && $2=="-" {print $3}' | head -10)"
if [[ -n "$NEW_BIN" && "${FORCE_BINARY:-0}" != "1" ]]; then
    echo "[backup] ⛔ ALARME BINAIRE : nouveau(x) binaire(s) en file (contenu non scannable) :" >&2
    echo "$NEW_BIN" | sed 's/^/    /' >&2
    echo "[backup] Exclus-le (SYNC_IGNORE) ou assume : FORCE_BINARY=1 bash ~/.claudeos/engine/backup.sh" >&2
    exit 1
fi

# --- Alarme secret par NOM (#8) : bloque tout fichier AJOUTÉ dont le NOM annonce un
# secret. L'alarme de contenu ci-dessous scanne ligne par ligne et rate une valeur nue
# dont le mot-clé vit sur une autre ligne — trou par lequel service_api_key.txt a fui
# le 2026-07-03. Whitelist : secrets-shared/ ; .md exclu (doc SUR les secrets
# ≠ porteur de valeur). --diff-filter=A : seuls les ajouts sonnent (parité alarme binaire).
# Motif remonté dans config.sh le 2026-08-03 (source unique, partagée avec le contrôle de
# rangement de selftest.sh) : ne pas le redéfinir ici.
SECRET_NAME_RE="$CLAUDEOS_SECRET_NAME_RE"
NEW_SECRET_NAMES="$(git -C "$ROOT" diff --cached --name-only --diff-filter=A \
        -- ':!system/secrets-shared/' ':!*.md' 2>/dev/null \
    | grep -Ei "$SECRET_NAME_RE" | head -10 || true)"
if [[ -n "$NEW_SECRET_NAMES" && "${FORCE_SECRET:-0}" != "1" ]]; then
    echo "[backup] ⛔ ALARME SECRET (nom) : nouveau(x) fichier(s) au nom évocateur d'un secret :" >&2
    echo "$NEW_SECRET_NAMES" | sed 's/^/    /' >&2
    echo "[backup] Faible valeur → ~/.claude/secrets-shared/ ; haute valeur → hors arbre + SYNC_IGNORE." >&2
    echo "[backup] Faux positif ? Outrepasser : FORCE_SECRET=1 bash ~/.claudeos/engine/backup.sh" >&2
    exit 1
fi

# --- Alarme secrets : scanne le CONTENU texte mis en file (filet derrière SYNC_IGNORE).
# Whitelist : 'system/secrets-shared/' (~/.claude/secrets-shared/) est l'emplacement
# synchronisé dédié aux secrets faible valeur (CLAUDE.md §4 / le document de conception) — exclu du scan.
# Deux passes, et c'est la casse qui les sépare (corrigé le 2026-07-27) :
#
#   FORMES — préfixes imposés par les éditeurs (AWS, GitHub, GitLab, Google, Slack, clé PEM).
#   Tous ont une casse EXACTE : 'AKIA' et 'AIza' en capitales, 'ghp_'/'glpat-'/'xoxb-' en bas
#   de casse. Comparer sans la casse ne rattrape donc aucun secret réel, mais fait sonner
#   n'importe quel bloc base64 : sur quelques centaines de kilo-octets, 'akia' suivi de seize
#   caractères alphanumériques finit par sortir par pur hasard. C'est ce qui a bloqué la
#   sauvegarde du 2026-07-27 sur des images intégrées dans une page autonome.
#
#   MOTS — 'api_key', 'secret', 'password', 'token' suivis d'une valeur. Là la casse varie
#   selon qui écrit le fichier, donc l'insensibilité est utile et on la garde.
# Les deux motifs vivent dans config.sh depuis le 2026-08-03 (source unique) : le détail du
# raisonnement casse-sensible/casse-insensible y est reporté en commentaire, pas dupliqué ici.
SECRET_RE_FORMES="$CLAUDEOS_SECRET_RE_FORMES"
SECRET_RE_MOTS="$CLAUDEOS_SECRET_RE_MOTS"
SECRET_DIFF="$(git -C "$ROOT" diff --cached -U0 --no-color -- ':!system/secrets-shared/' 2>/dev/null \
    | grep -E '^\+' || true)"
SECRET_HITS="$( { printf '%s\n' "$SECRET_DIFF" | grep -E  "$SECRET_RE_FORMES" || true
                  printf '%s\n' "$SECRET_DIFF" | grep -Ei "$SECRET_RE_MOTS"   || true
                } | head -5 )"
if [[ -n "$SECRET_HITS" ]]; then
    if [[ "${FORCE_SECRET:-0}" != "1" ]]; then
        echo "[backup] ⛔ ALARME SECRET : du contenu ressemblant à un secret va être sauvegardé :" >&2
        echo "$SECRET_HITS" | sed 's/^/    /' >&2
        echo "[backup] Retire le secret (ou ajoute le fichier à SYNC_IGNORE / secrets-shared/), puis relance." >&2
        echo "[backup] Faux positif ? Outrepasser : FORCE_SECRET=1 bash ~/.claudeos/engine/backup.sh" >&2
        exit 1
    fi
    echo "[backup] WARN : secret potentiel détecté mais override actif — on continue." >&2
fi

# --- Alarme donnée client (#9) : bloque tout fichier TEXTE de données AJOUTÉ (.csv/.txt/
# .tsv/.json/.xml/.eml/.msg, insensible à la casse) dans une zone synchronisée. On ne sait
# pas distinguer par le contenu un document client d'un artefact de travail légitime — mais
# ces formats sont le vecteur des fuites texte (compte_rendu.txt, export_table.csv, 2026-07-03),
# que ni l'alarme binaire ni les alarmes secret n'attrapent. .md exclu (base de connaissance :
# specs, mémoire, prompts). Whitelist : secrets-shared/. --diff-filter=A : seuls les ajouts
# sonnent. Réponse attendue : déplacer dans un _IGNORE/ (doc client) ou assumer via FORCE_DATA.
# Exemption system/settings.json : c'est la configuration EFFECTIVE de l'outil — déclencheurs
# et permissions —, un artefact voulu et versionné, pas une donnée. Sans elle, l'alarme
# refuse la toute PREMIÈRE sauvegarde de toute installation neuve, celle qui ajoute ce
# fichier. Le refus arrive au pire moment : la personne vient d'installer, elle n'a aucun
# moyen de juger si l'alarme a raison, et la seule issue affichée est de la forcer. Une
# alarme dont la première rencontre s'apprend à contourner ne protège plus rien ensuite.
NEW_DATA="$(git -C "$ROOT" diff --cached --name-only --diff-filter=A \
        -- ':!system/secrets-shared/' ':!system/settings.json' 2>/dev/null \
    | grep -Ei '\.(csv|tsv|txt|json|xml|eml|msg)$' | head -10 || true)"
if [[ -n "$NEW_DATA" && "${FORCE_DATA:-0}" != "1" ]]; then
    echo "[backup] ⛔ ALARME DONNÉE : nouveau(x) fichier(s) texte de données en file (fuite doc client possible) :" >&2
    echo "$NEW_DATA" | sed 's/^/    /' >&2
    echo "[backup] Document client → déplace-le dans le _IGNORE/ de son app. Artefact légitime → assume :" >&2
    echo "[backup] FORCE_DATA=1 bash ~/.claudeos/engine/backup.sh" >&2
    exit 1
fi

# --- Ce que la liste blanche a refusé (2026-07-27) ----------------------------
# Le verrou de `.gitignore` empêche tout fichier NOUVEAU de partir. Sans ce rapport le
# refus serait MUET : le dépôt cache ce qu'il ignore, donc le silence ressemblerait à
# « tout est sauvegardé », et un fichier resterait sur une seule machine sans que
# personne le sache. On ne bloque pas — on nomme, l'utilisateur décide.
# On ne remonte que ce qui est refusé par la règle du verrou (motif `*`), pas les
# journaux et verrous exclus nommément avant lui.
REFUSES=$(git -C "$ROOT" ls-files --others --ignored --exclude-standard -z 2>/dev/null \
    | xargs -0 -r git -C "$ROOT" check-ignore -v -- 2>/dev/null \
    | awk -F'\t' '$1 ~ /:\*$/ {print $2}')
if [ -n "$REFUSES" ]; then
    echo "[backup] ⚠ $(printf '%s\n' "$REFUSES" | wc -l) fichier(s) NON sauvegardé(s), hors liste blanche :"
    printf '%s\n' "$REFUSES" | sed 's/^/    /'
    echo "[backup] Pour en autoriser un : ligne '!<chemin>' dans ~/.claudeos/.gitignore."
fi

if git -C "$ROOT" diff --cached --quiet; then
    echo "[backup] Aucun changement à sauvegarder."
    exit 0
fi
git -C "$ROOT" commit -m "backup: $(date '+%Y-%m-%d %H:%M')"

echo "[backup] Pull --rebase avant push..."
if ! git -C "$ROOT" pull --rebase; then
    echo "[backup] ERREUR : rebase en conflit — annulé proprement." >&2
    git -C "$ROOT" rebase --abort 2>/dev/null || true
    echo "[backup] État : ton commit de backup existe EN LOCAL ($(git -C "$ROOT" log -1 --format=%h)) mais n'est PAS poussé — rien n'est perdu." >&2
    echo "[backup] À faire : git -C \"$ROOT\" pull --rebase (résous les conflits), puis git push." >&2
    exit 1
fi

git -C "$ROOT" push

# --- Point de restauration nommé « known good » (1/jour max) ---
TAG="claudeos-ok-$(date +%Y%m%d)"
if ! git -C "$ROOT" rev-parse "$TAG" >/dev/null 2>&1; then
    git -C "$ROOT" tag "$TAG" && git -C "$ROOT" push origin "$TAG" 2>/dev/null \
        && echo "[backup] Point de restauration : $TAG"
fi

echo "[backup] Sauvegarde terminée — $(git -C "$ROOT" log -1 --format='%h %s')"
