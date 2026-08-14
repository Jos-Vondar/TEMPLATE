#!/usr/bin/env bash
# =============================================================================
# INSTALL — amorçage du système. Partie DÉTERMINISTE de l'installation.
#
# Ce script ne pose aucune question de goût. Il installe la machinerie, vérifie
# qu'elle fonctionne, et rend la main : le reste — qui tu es, ce que tu fais, quel
# assistant tu veux — se fait dans Claude Code, où la conversation a sa place.
#
# Idempotent : chaque étape vérifie d'abord si elle est déjà faite. Relançable
# autant de fois que nécessaire.
#
# Fail loud : à la première étape qui échoue, on s'arrête en disant où on en est.
# Un demi-système installé est pire qu'aucun — il a l'air de marcher.
# =============================================================================
set -uo pipefail

case "${1:-}" in
    "") ;;
    *)  echo "install : argument inconnu '${1}'. Ce script n'en prend aucun." >&2; exit 2 ;;
esac

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETAPE=0
etape() { ETAPE=$((ETAPE+1)); printf '\n[%d] %s\n' "$ETAPE" "$1"; }
mort()  { printf '\n⛔ ÉCHEC à l'"'"'étape %d : %s\n' "$ETAPE" "$1" >&2
          printf '   Rien de plus n'"'"'a été fait. Corrige, puis relance ce script.\n' >&2; exit 1; }
ok()    { printf '    ✓ %s\n' "$1"; }
deja()  { printf '    · déjà fait — %s\n' "$1"; }

echo "════════════════════════════════════════════════════════════"
echo "  Installation du système"
echo "════════════════════════════════════════════════════════════"

# --- 1. Dépendances ---------------------------------------------------------
etape "Dépendances"
for outil in git rsync curl python3; do
    command -v "$outil" >/dev/null 2>&1 || mort "$outil est absent. Installe-le d'abord."
    ok "$outil"
done
command -v claude >/dev/null 2>&1 || mort "Claude Code (\`claude\`) est absent. Installe-le d'abord : c'est ce que ce système configure."
ok "claude"

# Identité git. Vérifiée ICI et non au premier commit : sans elle, git refuse de committer,
# et le contrôle d'inscriptibilité de l'étape suivante conclurait « dépôt non inscriptible ».
# Diagnostic faux — le dépôt l'est, c'est l'identité qui manque. Une machine neuve, qui est
# précisément le cas d'usage de ce script, n'a souvent pas d'identité configurée.
# ON LA DEMANDE au lieu de refuser. La version précédente s'arrêtait en affichant les deux
# commandes à taper — un refus poli qui envoyait la personne faire à la main ce que le script
# pouvait faire, à la première étape de sa toute première installation. Elle est demandée ici
# et écrite dans la configuration GLOBALE, donc une seule fois par machine.
# Motif appuyé par l'expérience du jour : l'identité manquante ne se manifeste jamais quand
# on l'attend. Elle laisse passer le clonage, laisse passer la copie, et tombe au moment
# d'écrire — sur un message, « empty ident name », qui ne dit pas quoi faire. Chaque endroit
# qui ne la reçoit pas explicitement échoue à son tour, séparément.
GIT_NOM="$(git config --global user.name 2>/dev/null || true)"
GIT_MAIL="$(git config --global user.email 2>/dev/null || true)"
if [ -z "$GIT_NOM" ] || [ -z "$GIT_MAIL" ]; then
    printf '\n    Git n'"'"'a pas d'"'"'identité sur cette machine. Elle signera tes sauvegardes,\n'
    printf '    et sans elle rien ne peut être enregistré.\n\n'
    # Lecture sur l'ENTRÉE STANDARD, comme l'URL du dépôt demandée plus bas. Une première
    # version lisait sur le terminal : deux canaux différents dans le même script, et la
    # boucle tournait à vide dès qu'il n'y avait pas de terminal. Une seule lecture, et un
    # arrêt net si elle ne rend rien — une invite qui se répète sans fin est pire qu'un refus.
    printf '    Ton nom : '; read -r GIT_NOM || GIT_NOM=""
    printf '    Ton courriel : '; read -r GIT_MAIL || GIT_MAIL=""
    if [ -z "$GIT_NOM" ] || [ -z "$GIT_MAIL" ]; then
        mort "identité non fournie. Configure-la à la main puis relance :
     git config --global user.name \"Ton Nom\"
     git config --global user.email \"toi@exemple.com\""
    fi
    git config --global user.name "$GIT_NOM"  || mort "impossible d'"'"'écrire l'"'"'identité git."
    git config --global user.email "$GIT_MAIL" || mort "impossible d'"'"'écrire l'"'"'identité git."
    # Relecture depuis git, et non depuis les variables : c'est ce que git RÉPOND qui compte,
    # pas ce qu'on croit lui avoir dit. Une écriture qui échoue en silence se verrait ici.
    [ -n "$(git config --global user.name)" ] && [ -n "$(git config --global user.email)" ] \
        || mort "identité écrite mais git ne la relit pas — configuration git à examiner."
    ok "identité git enregistrée ($GIT_NOM)"
else
    ok "identité git ($GIT_NOM)"
fi

# --- 2. Dépôt de sauvegarde -------------------------------------------------
# Demandé AVANT toute écriture : un système installé sans destination de sauvegarde
# donne l'illusion d'être protégé, ce qui est pire que de ne rien avoir.
etape "Dépôt de sauvegarde"
echo "    Ce système sauvegarde sa configuration dans un dépôt git privé, qui la"
echo "    transporte aussi entre tes machines."
echo
echo "    Deux cas, et le script les distingue tout seul :"
echo "      · dépôt VIDE   → première machine, installation complète."
echo "      · dépôt DÉJÀ HABITÉ par ce système → machine supplémentaire, on"
echo "        récupère la configuration existante au lieu d'en créer une."
echo
printf '    URL du dépôt (ex. git@github.com:toi/mon-os.git) : '
read -r REMOTE_URL
[ -n "$REMOTE_URL" ] || mort "aucune URL fournie."

TMPCLONE="$(mktemp -d)"
trap 'rm -rf "$TMPCLONE"' EXIT
git clone --quiet "$REMOTE_URL" "$TMPCLONE/probe" 2>/dev/null \
    || mort "impossible de cloner $REMOTE_URL — vérifie l'URL et ton accès."
# NORMALISATION AVANT TOUT JUGEMENT, et c'est la correction d'un défaut à perte de données.
# Le test de vacuité qui suit regarde le CONTENU DÉBALLÉ du clone. Or un dépôt dont la tête
# désigne une branche absente se clone sans erreur et se déballe VIDE, alors qu'il contient
# tout. La sonde concluait donc « dépôt vierge, première machine » sur la sauvegarde d'une
# machine existante, et repartait de zéro par-dessus — une histoire divergente écrite sur le
# seul exemplaire d'une configuration. Exercé : dépôt portant `master`, tête sur `main`,
# verdict « dépôt VIDE — PREMIÈRE MACHINE ».
# La leçon, plus large que ce script : un contenant se juge sur ce qu'il CONTIENT, pas sur
# ce que l'outil a bien voulu en sortir. Le clone est ici l'outil, et il avait échoué en
# silence sur la seule partie qui comptait.
if ! git -C "$TMPCLONE/probe" rev-parse HEAD >/dev/null 2>&1; then
    _pb="$(git -C "$TMPCLONE/probe" for-each-ref --format='%(refname:strip=3)' refs/remotes/origin/ | head -1)"
    if [ -n "$_pb" ]; then
        git -C "$TMPCLONE/probe" checkout -q -B "$_pb" "origin/$_pb" 2>/dev/null \
            || mort "le dépôt porte la branche « $_pb » mais elle ne se déballe pas. Dépôt à examiner à la main avant toute installation."
        printf '    ⚠ tête du dépôt distant pendante — branche « %s » déballée pour l'"'"'examiner.\n' "$_pb"
    fi
fi
# Trois états possibles, et le troisième est le seul refus. Refuser tout dépôt non vide
# fermait le seul chemin praticable vers une deuxième machine : la personne se retrouvait
# devant un refus sec, alors que le dépôt contenait exactement ce qu'il lui fallait.
if [ -z "$(ls -A "$TMPCLONE/probe" 2>/dev/null | grep -v '^\.git$')" ]; then
    MODE=premier
elif [ -d "$TMPCLONE/probe/engine" ] && [ -d "$TMPCLONE/probe/system" ]; then
    MODE=second
else
    mort "le dépôt n'est pas vide, et son contenu n'est pas celui de ce système.
     Refus d'écrire par-dessus. Prends un dépôt vide, ou celui de ta première machine."
fi
# Vérifier l'écriture MAINTENANT, et pas à la première sauvegarde : un droit de
# lecture seule ne se manifeste qu'au moment du push, quand le travail est déjà fait.
# Les deux moitiés du test sont séparées : un échec de commit et un échec de push n'ont
# pas la même cause et ne se corrigent pas au même endroit. Les confondre envoie chercher
# un problème de droits là où il n'y en a pas.
( cd "$TMPCLONE/probe" && git commit --quiet --allow-empty -m "sonde" ) 2>/dev/null \
    || mort "impossible de créer un commit d'essai — problème git local, pas un problème de droits sur le dépôt."
# La sonde pousse sur une RÉFÉRENCE TEMPORAIRE, puis l'efface. Première version : elle
# poussait sur la branche, ce qui laissait un commit dans le dépôt et le rendait non vide.
# Le dépôt local créé juste après n'avait alors aucun ancêtre commun avec lui, et le vrai
# push était refusé — la sonde empoisonnait ce qu'elle mesurait. Trouvé en exécutant, pas
# en relisant : les deux moitiés marchaient séparément.
( cd "$TMPCLONE/probe" && git push --quiet origin HEAD:refs/heads/__sonde__ ) 2>/dev/null \
    || mort "le dépôt est clonable mais le push est refusé. Vérifie tes droits en ÉCRITURE sur $REMOTE_URL."
( cd "$TMPCLONE/probe" && git push --quiet origin :refs/heads/__sonde__ ) 2>/dev/null \
    || printf '    ⚠ la branche d'"'"'essai __sonde__ n'"'"'a pas pu être effacée — à retirer à la main.\n'
if [ "$MODE" = premier ]; then
    ok "dépôt vide, clonable et inscriptible (sonde effacée) — PREMIÈRE MACHINE"
else
    ok "dépôt habité par ce système, clonable et inscriptible (sonde effacée) — MACHINE SUPPLÉMENTAIRE"
    echo "    Ta configuration existe déjà : elle va être récupérée, pas recréée."
fi

# --- 3. Arborescence --------------------------------------------------------
etape "Arborescence"
for d in "$HOME/.claude" "$HOME/workstations" "$HOME/docs" "$HOME/resources"; do
    if [ -d "$d" ]; then deja "${d#"$HOME"/}"; else mkdir -p "$d" && ok "${d#"$HOME"/} créé"; fi
done

DEPOT="$HOME/.claudeos"

# --- 4bis. MACHINE SUPPLÉMENTAIRE : récupérer au lieu de créer ---------------
# Tout ce qui suit dans les étapes 4 à 7bis FABRIQUE une configuration : machinerie,
# manifeste, verrou, mémoire, premier commit. Sur une deuxième machine, ces choses
# existent déjà et sont dans le dépôt — les refabriquer les écraserait avec des valeurs
# par défaut, c'est-à-dire perdrait la configuration qu'on venait chercher.
# Le chemin est donc entièrement différent : cloner, s'enregistrer, projeter.
if [ "$MODE" = second ]; then
    etape "Récupération de la configuration existante"
    if [ -d "$DEPOT/.git" ]; then
        deja "dépôt local déjà cloné"
    else
        git clone --quiet "$REMOTE_URL" "$DEPOT" || mort "clonage de $REMOTE_URL vers ~/.claudeos impossible."
        # RATTRAPAGE D'UNE TÊTE PENDANTE. Un `git clone` dont la tête distante désigne une
        # branche inexistante RÉUSSIT, rapatrie tout, et laisse un dossier VIDE — le seul
        # signal est un avertissement sur la sortie d'erreur, que personne ne relie à
        # « mon travail est là, mais pas déballé ». Le contrôle juste en dessous concluait
        # alors « ce n'est pas une sauvegarde de ce système » : diagnostic faux, et c'est
        # le plus coûteux des deux, parce qu'il envoie douter du dépôt qui contient tout.
        # Le cas se produit dès que la machine d'origine a poussé une branche qui n'est pas
        # celle que l'hébergeur a mise en tête — exercé, 1 fichier récupéré sur 43.
        # Ici on ne devine pas : les branches sont là, on en prend une et on la déballe.
        if ! git -C "$DEPOT" rev-parse HEAD >/dev/null 2>&1; then
            _rec="$(git -C "$DEPOT" for-each-ref --format='%(refname:strip=3)' refs/remotes/origin/ | head -1)"
            [ -n "$_rec" ] || mort "le dépôt cloné ne contient aucune branche — rien à récupérer."
            git -C "$DEPOT" checkout -q -B "$_rec" "origin/$_rec" \
                || mort "impossible de déballer la branche « $_rec » du dépôt cloné."
            printf '    ⚠ la tête du dépôt distant désigne une branche absente ; branche « %s » déballée à la main.\n' "$_rec"
            printf '      À corriger côté hébergeur : passer la branche par défaut du dépôt à « %s ».\n' "$_rec"
        fi
        ok "dépôt cloné dans ~/.claudeos (le suivi de branche vient avec le clonage)"
    fi
    [ -f "$DEPOT/engine/sync.sh" ] || mort "le dépôt cloné ne porte pas de moteur — ce n'est pas une sauvegarde de ce système."

    # Le registre des postes sert au garde-fou multi-machines : il refuse de sauvegarder
    # depuis une machine en retard. Une machine absente du registre est une machine dont
    # personne ne surveille le retard — le garde-fou existe et ne la voit pas.
    REG="$DEPOT/engine/config/SYNC_MACHINES"
    if [ -f "$REG" ] && ! grep -q "^$(hostname)[[:space:]]" "$REG"; then
        _n=$(grep -cE '^[^#[:space:]]' "$REG" 2>/dev/null || echo 1)
        printf '%s  poste-%s  Machine ajoutée à l'"'"'installation\n' "$(hostname)" "$((_n+1))" >> "$REG"
        ok "cette machine inscrite au registre des postes (committée à la prochaine sauvegarde)"
    else
        deja "machine déjà inscrite au registre des postes"
    fi

    # Projection dépôt → live. C'est la synchronisation ordinaire : elle applique les
    # fichiers, puis déroule la liste de configuration automatique. Rien de spécifique
    # à une installation neuve — d'où l'absence, jusqu'ici, de tout chemin documenté.
    etape "Projection de la configuration sur cette machine"
    bash "$DEPOT/engine/restore.sh" || mort "la projection a échoué. Lis sa sortie : elle dit
     quel fichier a résisté. Rien n'est cassé côté dépôt."
    ok "configuration projetée sur ~/.claude et les dossiers de travail"

    # Le réceptacle des secrets de faible valeur n'est JAMAIS synchronisé, par construction.
    # Il n'arrive donc pas avec le clonage, et son absence casserait la politique des secrets.
    mkdir -p "$HOME/.claude/secrets-shared"
fi

# --- 4. Dépôt local et machinerie ------------------------------------------
if [ "$MODE" = premier ]; then
etape "Machinerie"
if [ -d "$DEPOT/.git" ]; then
    deja "dépôt local présent"
else
    cp -r "$RACINE/engine" "$DEPOT/engine" 2>/dev/null || { mkdir -p "$DEPOT"; cp -r "$RACINE/engine" "$DEPOT/"; }
    # LA BRANCHE, et c'est un piège à perte de données. `git init` prend la branche par
    # défaut de LA MACHINE — souvent `master`. La tête d'un dépôt GitHub neuf est `main`.
    # Pousser `master` sans rien aligner laisse un dépôt dont la tête désigne une branche
    # qui n'existe pas : la sauvegarde marche, le dépôt se remplit, et c'est la DEUXIÈME
    # machine qui paie — son clonage rend un dossier VIDE avec un simple avertissement,
    # « remote HEAD refers to nonexistent ref ». Exercé : un fichier récupéré sur 43.
    # Personne ne lit cet avertissement comme « ta sauvegarde est ailleurs » ; on le lit
    # comme « ma sauvegarde est perdue ».
    # Ordre de préférence : ce que le distant ANNONCE, puis le réglage de la machine, puis
    # `main`. Un dépôt vide n'annonce rien — vérifié, `ls-remote --symref` rend une sortie
    # vide sur un dépôt sans commit — d'où les deux replis, et surtout le contrôle d'après
    # poussée plus bas, qui est la vraie protection.
    _BR="$(git ls-remote --symref "$REMOTE_URL" HEAD 2>/dev/null \
           | sed -n 's#^ref: refs/heads/\(.*\)[[:space:]]HEAD$#\1#p' | head -1)"
    [ -n "$_BR" ] || _BR="$(git config --global init.defaultBranch 2>/dev/null)"
    [ -n "$_BR" ] || _BR="main"
    ( cd "$DEPOT" && git init --quiet && git symbolic-ref HEAD "refs/heads/$_BR" \
      && git remote add origin "$REMOTE_URL" ) || mort "initialisation du dépôt local impossible."
    ok "dépôt local initialisé sur la branche $_BR"
fi

# La configuration du moteur est RÉGÉNÉRÉE, jamais héritée : elle porte l'adresse du
# dépôt et le registre des postes, qui n'ont de sens que pour leur propriétaire.
mkdir -p "$DEPOT/engine/config"
printf '%s\n' "$(printf '%s' "$REMOTE_URL" | sed 's#.*[:/]\([^/]*/[^/]*\)\.git#\1#')" > "$DEPOT/engine/config/REMOTE"
printf '# Registre des postes — <hostname>  <id court>  <label>\n%s  poste-1  Premier poste\n' "$(hostname)" \
    > "$DEPOT/engine/config/SYNC_MACHINES"
cp "$RACINE/system/"*.md "$HOME/.claude/" 2>/dev/null
mkdir -p "$HOME/.claude/skills" "$HOME/.claude/output-styles"
cp -r "$RACINE/system/skills/"* "$HOME/.claude/skills/" 2>/dev/null
# Le style de sortie fourni est POSÉ, jamais activé : activer une voix est un choix de la
# personne, pas de l'installation. Aucune écriture de `outputStyle` dans ses réglages —
# le README dit comment l'allumer.
cp "$RACINE/system/output-styles/"*.md "$HOME/.claude/output-styles/" 2>/dev/null
ok "configuration du moteur régénérée, règles et compétences en place"

# L'EMPREINTE DE DÉPART, sans laquelle aucune mise à jour n'est possible plus tard.
# Elle enregistre ce que CETTE version a posé, fichier par fichier. Sans elle, la commande
# de mise à jour ne peut pas distinguer « modifié par la personne » de « modifié par la
# version précédente » : les deux se présentent comme un fichier local qui diffère de la
# nouvelle version. Confondre les deux, c'est écraser du travail ou ne jamais rien mettre
# à jour. On la prend maintenant, à l'instant où l'état posé est encore exactement le nôtre.
if [ -f "$RACINE/engine/manifest.sh" ]; then
    bash "$RACINE/engine/manifest.sh" "$RACINE" "$DEPOT/engine/config/MANIFEST_INSTALL" >/dev/null 2>&1 \
        && ok "empreinte de la version installée posée (permet la mise à jour incrémentale)" \
        || printf '    ⚠ empreinte non posée — la mise à jour incrémentale demandera une réinstallation.\n'
    # D'OÙ vient le squelette, pour savoir où chercher la version suivante. Lu depuis le
    # clone dont ce script est issu : la personne n'a rien à retaper, et rien à se rappeler.
    _orig="$(git -C "$RACINE" remote get-url origin 2>/dev/null)"
    if [ -n "$_orig" ]; then
        printf '# Dépôt du squelette, pour les mises à jour. Modifiable à la main.\n%s\n' "$_orig" \
            > "$DEPOT/engine/config/TEMPLATE_ORIGIN"
    else
        printf '    ⚠ origine du squelette inconnue — renseigne %s pour pouvoir te mettre à jour.\n' \
            "$DEPOT/engine/config/TEMPLATE_ORIGIN"
    fi
fi

# --- 5. Manifeste -----------------------------------------------------------
etape "Manifeste de sauvegarde"
MAP="$DEPOT/engine/config/SYNC_MAP"
if [ -f "$MAP" ]; then deja "manifeste présent"; else
cat > "$MAP" <<'MANIFESTE'
# Manifeste — source de vérité UNIQUE des correspondances local <-> dépôt.
# Colonnes : <chemin relatif au dossier personnel>  <sous-dossier du dépôt>  <régime>
#   additive = jamais de suppression (dossier co-habité avec un outil)
#   mirror   = le dépôt reflète le local, suppressions comprises
# AJOUTER UN DOMAINE DE TRAVAIL = AJOUTER UNE LIGNE ICI. Sans elle, le dossier
# n'est ni sauvegardé ni synchronisé, et rien ne te le dira.
#
# Un domaine par ligne, JAMAIS `workstations` en bloc. La première version de ce
# fichier prenait le raccourci, et il rendait faux tout ce que la documentation
# répète : un dossier était sauvegardé sans ligne, ajouter la ligne prescrite le
# faisait recopier deux fois, et retirer un domaine ne retirait rien puisque le
# miroir parent continuait. Une doctrine que l'implémentation dément est pire
# qu'une doctrine absente : elle enseigne à ne pas croire la documentation.
#
# Exemple, à décommenter et adapter — puis une ligne par domaine supplémentaire :
# workstations/MON_DOMAINE  workstations/MON_DOMAINE  mirror
.claude      system      additive
resources    resources    mirror
docs         docs         mirror
MANIFESTE
ok "manifeste créé"
fi

# Les artefacts de configuration qui naissent vides chez la personne — le fichier des
# créneaux hebdomadaires en tête. Ils sont décrits en UN SEUL LIEU, engine/provision-config.sh,
# parce que deux chemins doivent les poser : cette installation, et update.sh chez qui met à
# jour sans réinstaller — sans ce second appelant, une mise à jour laissait l'autotest en
# défaut (contrôle 27 : chemin cité par une règle mais jamais posé) et la sauvegarde refusée.
# Le script est idempotent : il ne crée que ce qui manque, il n'écrase aucune décision locale.
if bash "$RACINE/engine/provision-config.sh" >/dev/null 2>&1; then
    ok "artefacts de configuration posés (créneaux hebdomadaires, listes blanches)"
else
    printf '    ⚠ rattrapage de configuration en échec — l'\''autotest dira ce qui manque.\n'
fi

# Le fichier d'exclusion de la COPIE. Distinct du verrou git : le verrou décide de ce qui
# est committé, celui-ci décide de ce qui est seulement copié vers le dépôt. Sans lui, le
# réceptacle confidentiel serait recopié dans le dépôt avant même que git en décide.
IGN="$DEPOT/engine/config/SYNC_IGNORE"
if [ -f "$IGN" ]; then deja "exclusions de copie présentes"; else
cat > "$IGN" <<'EXCLUSIONS'
# Ce qui n'est JAMAIS copié vers le dépôt. Format rsync : un motif par ligne.
# Motif ancré par '/' en tête = racine de chaque dossier synchronisé.
# --- Réceptacle confidentiel : seul exemplaire, sur une seule machine ---
_IGNORE/
# --- Sources de messagerie et pièces jointes ---
*.eml
*.msg
# --- Binaires bureautiques : l'alarme de secret lit le texte et y est aveugle ---
*.pdf
*.docx
*.xlsx
*.pptx
# --- Runtime de l'outil : propre à chaque machine, lourd, jamais à versionner ---
# LISTE ÉTABLIE EN ÉNUMÉRANT UN `~/.claude` RÉEL, pas en devinant. La version précédente en
# couvrait neuf entrées sur vingt-quatre : tout le reste était recopié dans l'arbre du dépôt,
# où il restait indéfiniment — refusé au commit par le verrou, donc absent de `git status`,
# donc invisible. Dix-neuf chemins accumulés sur une seule installation avant qu'une revue
# manuelle ne les voie, dont **le fichier d'identifiants OAuth de l'outil**. Il n'était pas
# commité ; il était copié, ce qui suffit à en faire un second exemplaire hors de sa place,
# et un changement de règle du verrou l'aurait fait basculer côté commité sans un mot.
# Deux enseignements, dans cet ordre. Un fichier « pas commité » n'est pas un fichier « pas
# copié » — les deux verrous sont indépendants et personne ne le lisait comme ça. Et une
# liste d'exclusions se construit en énumérant ce qui existe, jamais en listant ce à quoi on
# pense : les entrées manquantes étaient précisément celles ajoutées par les versions
# récentes de l'outil, celles auxquelles personne n'avait eu l'occasion de penser.
/projects/
/plugins/
/cache/
/sessions/
/shell-snapshots/
/history.jsonl
/settings.local.json
/statsig/
/todos/
/ide/
/tasks/
/session-env/
/paste-cache/
/downloads/
/jobs/
/file-history/
/backups/
# Identifiants et état du démon. `.credentials.json` porte le jeton OAuth de l'outil : il
# n'a rien à faire dans un dépôt, même privé, même non commité.
/.credentials.json
/.last-cleanup
/.last-update-result.json
/mcp-needs-auth-cache.json
/policy-limits.json
/remote-settings.json
/stats-cache.json
*.lock
*.sock
# Le filet de sécurité de la synchronisation : `sync.sh` y dépose ce qu'il écrase avant de
# l'écraser. Deux scripts du moteur savaient déjà l'ignorer, chacun dans son coin et avec un
# commentaire expliquant pourquoi — mais le fichier censé PORTER cette liste ne le savait
# pas. Le savoir vivait dans le code applicatif au lieu de sa configuration, donc il ne
# valait que pour les deux scripts qui l'avaient appris. Conséquence observée : une version
# périmée et corrompue de la carte de rappel recopiée dans le dépôt à chaque sauvegarde.
/.sync-backups/
# --- Environnements et artefacts de construction ---
.venv/
venv/
node_modules/
__pycache__/
.DS_Store
EXCLUSIONS
ok "exclusions de copie créées"
fi

# Emplacement des secrets de faible valeur. Créé vide : son absence ferait échouer le
# câblage de la politique des secrets, et sa présence ne coûte rien.
mkdir -p "$HOME/.claude/secrets-shared"

# --- 6. Verrou de sauvegarde ------------------------------------------------
etape "Verrou de sauvegarde"
if [ -f "$DEPOT/.gitignore" ]; then deja "verrou présent"; else
cat > "$DEPOT/.gitignore" <<'VERROU'
# LISTE BLANCHE : tout est ignoré, on autorise ensuite nommément ou par motif.
# L'inversion est le point important — une liste noire laisse passer ce qu'on n'a
# pas pensé à interdire, qui est exactement la catégorie qui fuit.
# ATTENTION : ce verrou ne gouverne que la NOUVEAUTÉ. Un fichier déjà suivi continue
# de partir sans figurer ici. Qu'un fichier parte ne prouve donc pas qu'une règle l'autorise.
*
!*/
!.gitignore
!engine/**
# Les JOURNAUX ET MARQUEURS que le moteur régénère à chaque exécution. `!engine/**` autorisait
# tout le dossier sans distinction, donc ils partaient — et comme ils changent à chaque
# lancement, chaque sauvegarde portait un diff de bruit qui n'apprend rien à personne et
# grossit l'historique pour toujours. L'ORDRE COMPTE ICI : ces motifs doivent suivre
# `!engine/**`, parce que c'est le dernier motif correspondant qui gagne. Placés avant, ils
# n'auraient rien fait, et le fichier aurait eu l'air correct.
engine/*.log
engine/.last-offline-backup
# Le marqueur de dernière activité : écrit par la sauvegarde ENTRE la mise en file et le
# push. Non exclu, il est suivi dès la deuxième sauvegarde puis modifié après le commit,
# et le `pull --rebase` refuse — troisième sauvegarde impossible, exercé sur pièce le
# 2026-08-14 en rejouant deux sauvegardes sur une installation factice. Le moteur le
# déclare « local, jamais sauvegardé » : cette ligne rend le verrou conforme à sa doctrine.
engine/.derniere-activite
# LOCAL PAR DÉCISION, et exclu NOMMÉMENT pour cette raison. Le réceptacle des secrets de
# faible valeur ne voyage pas : un système livré ne pousse pas des secrets dans un dépôt à
# la place de quelqu'un qui n'a pas pesé ce choix. Il reste donc sur chaque machine, et il
# faut l'y reposer — c'est le prix, il est assumé.
# Pourquoi une ligne à lui alors que le motif attrape-tout le refuserait déjà : le rapport
# de fin de sauvegarde ne remonte que ce qui tombe sur l'attrape-tout. Sans cette ligne,
# chaque clôture énumérerait ces fichiers comme « NON sauvegardés », et une décision de
# conception se lirait comme une avarie, à chaque fois. Exclu nommément = voulu ; exclu par
# défaut = oublié. La ligne dit lequel des deux.
system/secrets-shared/
!system/*.md
!system/plans/*.md
# Les styles de sortie de l'outil : fournis par le squelette, à toi ensuite. Sans cette
# ligne, un style ajouté ou modifié resterait sur une seule machine, en silence.
!system/output-styles/*.md
# `settings.json` porte les réglages EFFECTIFS de l'outil — déclencheurs, permissions. La
# liste blanche de `system/` ne connaissait que `*.md`, donc le seul fichier qui décrit le
# comportement réel de l'installation ne partait pas : une machine restaurée depuis le dépôt
# revenait sans ses déclencheurs, en silence. `settings.local.json`, lui, reste dehors — il
# est propre à la machine, et c'est le fichier de la liste d'exclusions qui l'écarte.
!system/settings.json
# Les compétences EN ENTIER, et pas seulement leurs `.md`. Une compétence n'est pas un
# document : elle embarque ses scripts, ses licences, ses données. Restreindre aux `.md`
# laissait ses exécutables au bord de la route — copiés dans le dépôt par le manifeste,
# refusés au commit par ce verrou. Exactement le défaut que la ligne `resources/` juste
# en dessous raconte avoir déjà payé, et il se paie au même endroit : invisible sur la
# première machine, où le fichier est là parce qu'on vient de l'écrire ; mortel sur la
# deuxième, où il n'arrive jamais. Et le déclencheur qui l'appelle avale son échec, donc
# la compétence est simplement muette — le pire des symptômes, celui qu'on ne cherche pas.
!system/skills/**
!system/audits/*.md
!system-memory/*.md
!docs/**/*.md
# Les gabarits et outils de `resources/`. Ligne trouvée manquante en installant une
# DEUXIÈME machine : le manifeste porte ce dossier, la copie le dépose bien dans le
# dépôt, et le verrou le refusait en silence. Invisible sur la première machine, où le
# fichier existe localement parce que l'installation vient de l'y écrire ; visible
# seulement là où il aurait dû arriver par le dépôt et n'arrive pas.
!resources/**/*.md
!resources/*.md
# Tes domaines de travail : les fichiers TEXTE partent, le reste demande une décision.
# Ce partage n'est pas arbitraire. Le `.md` porte tes règles, ta mémoire, tes notes —
# ce que tu ne peux pas régénérer. Les binaires, tableurs et exports de données sont
# précisément ce par quoi un document client fuit, et ils se re-téléchargent.
# Sans ces deux lignes, un domaine n'est jamais sauvegardé même avec sa ligne au
# manifeste : le verrou refuse ce que la copie a déposé, en silence. Constaté en
# jouant l'installation d'un destinataire fictif jusqu'à sa première sauvegarde.
!workstations/**/*.md
!workstations/*.md
# Jamais sauvegardé, quoi qu'il arrive : réceptacles confidentiels et binaires.
_IGNORE/
*.pdf
*.docx
*.xlsx
*.pptx
VERROU
ok "verrou créé"
fi

# --- 6bis. Mémoire automatique ----------------------------------------------
# Le dossier porte un nom DÉRIVÉ du dossier personnel, donc différent d'une machine à
# l'autre : il se calcule, il ne s'écrit jamais en dur. Sans cette étape, les registres
# de la boucle d'apprentissage n'existent nulle part et la moitié des contrôles échoue.
etape "Mémoire automatique"
SLUG="$(printf '%s' "$HOME" | sed 's#/#-#g')"
MEM="$HOME/.claude/projects/$SLUG/memory"
mkdir -p "$MEM"
for f in "$RACINE/system-memory/"*.md; do
    [ -e "$f" ] || continue
    dest="$MEM/$(basename "$f")"
    [ -f "$dest" ] || cp "$f" "$dest"
done
[ -f "$MEM/MEMORY.md" ] || printf '# Index de mémoire\n\n' > "$MEM/MEMORY.md"
[ -f "$MEM/INDEX.md" ] || cat > "$MEM/INDEX.md" <<'INDEX'
# Carte de rappel

> Deux couches. La **curatée** 🧭 est écrite à la main : ce qu'il faut avoir en tête avant
> tout travail de fond. La couche AUTO est régénérée à chaque sauvegarde — ne pas l'éditer,
> elle sera écrasée.

## 🧭 Couche curatée

*(à remplir — l'entretien d'installation y met les premiers repères)*

<!-- AUTO:START — généré par build-index.sh, NE PAS éditer à la main -->
<!-- AUTO:END -->
INDEX
[ -f "$MEM/SESSION_JOURNAL.md" ] || printf '# Journal des sessions\n\n' > "$MEM/SESSION_JOURNAL.md"
[ -f "$MEM/REMINDERS.md" ] || printf '# Rappels datés — une ligne `- AAAA-MM-JJ | texte`\n\n' > "$MEM/REMINDERS.md"
[ -f "$MEM/SECURITY_DEBT.md" ] || printf '# Dette de sécurité — identité, emplacement, statut. JAMAIS de valeur.\n\n' > "$MEM/SECURITY_DEBT.md"
ok "mémoire initialisée (${MEM#"$HOME"/})"

# Gabarit de création d'un domaine de travail, cité par les règles.
if [ -f "$HOME/resources/WORKSTATION_TEMPLATE.md" ]; then deja "gabarit de domaine présent"
else cp "$RACINE/resources/WORKSTATION_TEMPLATE.md" "$HOME/resources/" 2>/dev/null && ok "gabarit de domaine en place"; fi

fi   # fin du chemin PREMIÈRE MACHINE (étapes 4 à 6bis)

# Ce qui suit vaut pour les DEUX chemins. Le proxy, les déclencheurs de l'outil et
# l'autotest sont propres à la machine : ils ne voyagent pas dans le dépôt, et une
# deuxième machine en a autant besoin que la première. Le commit initial, lui, est
# idempotent — sur une machine récupérée, il constate simplement que l'historique existe.

# --- 7. Proxy économe en jetons ---------------------------------------------
# Réduit le coût de session en réécrivant les commandes courantes. Optionnel dans
# l'absolu, mais son absence ne se manifeste par rien — d'où l'installation par défaut.
etape "Proxy économe en jetons"
if command -v rtk >/dev/null 2>&1; then
    deja "présent en version $(rtk --version 2>/dev/null | head -1)"
else
    if curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh; then
        ok "installé"
    else
        printf '    ⚠ installation impossible — le système marche sans, à un coût plus élevé.\n'
    fi
fi
if command -v rtk >/dev/null 2>&1; then
    rtk init -g >/dev/null 2>&1 && ok "hook de réécriture posé (redémarre Claude Code pour l'activer)" \
        || printf '    ⚠ hook non posé — lance `rtk init -g` à la main.\n'
    # LE RTK.md QUE L'OUTIL ÉCRIT EST GARDÉ TEL QUEL (aligné le 2026-08-14 sur la décision
    # du 2026-08-10 côté auteur). L'installation posait ici un pointeur court à sa place ;
    # la compétence de dépannage livrée dit désormais l'inverse — laisser `rtk init -g`
    # faire son travail, rien à restaurer après une montée de version — et un système qui
    # installe une chose pendant que sa doctrine en prescrit une autre livre une
    # contradiction. Coût assumé : la version de l'outil pèse sur chaque session.
fi
# LA TRACE DE DÉTECTION, sans laquelle l'entretien ne peut que deviner. Le catalogue
# promet « PROXY : détectée par le script d'installation » — mais le résultat ne
# survivait nulle part : au moment d'assembler les règles, le modèle devait se SOUVENIR
# que l'outil était là, et son oubli retirait la compétence de dépannage en silence.
# Écrite dans les DEUX sens : « non » quand l'installation vient d'échouer est le cas qui
# compte — une trace qui ne sait dire que « oui » ne détecte rien. Réécrite à chaque
# passage de ce script, parce que c'est ici que le résultat est frais ; lue par
# assemble-rules.sh, qui tranche PROXY sur elle et non sur une liste tapée de mémoire.
mkdir -p "$DEPOT/engine/config"
{
    echo "# PROXY — résultat de la détection du proxy économe, écrit par install.sh."
    echo "# Lu par assemble-rules.sh pour trancher la condition PROXY. « oui » = outil présent."
    if command -v rtk >/dev/null 2>&1; then echo "oui"; else echo "non"; fi
} > "$DEPOT/engine/config/PROXY"
ok "détection consignée : $(tail -1 "$DEPOT/engine/config/PROXY") (engine/config/PROXY)"

# --- 7bis. Premier commit ---------------------------------------------------
# Un dépôt sans aucun commit est un état bâtard : plusieurs outils du moteur refusent d'y
# travailler, à juste titre, et l'autotest échoue. Constaté à la vérification de bout en
# bout — le dépôt était initialisé mais vide, et la retombée documentaire refusait toute
# date au motif qu'aucun commit ne la précédait. Elle avait raison.
etape "Premier commit"
if git -C "$DEPOT" rev-parse HEAD >/dev/null 2>&1; then
    deja "le dépôt a déjà un historique"
else
    ( cd "$DEPOT" && git add -A && git commit --quiet -m "installation : machinerie et configuration" ) \
        && ok "socle committé" \
        || printf '    ⚠ commit initial impossible — la première sauvegarde le rattrapera.\n'
fi
# LE SUIVI DE BRANCHE, sans lequel la première sauvegarde échoue. Trouvé par un audit
# externe qui a rejoué la séquence : `git init` + `remote add` ne posent AUCUN suivi, donc
# le `pull --rebase` de la sauvegarde meurt sur « no tracking information » — et son
# gestionnaire d'erreur rhabille ça en « rebase en conflit », envoyant chercher un conflit
# qui n'existe pas. Pire encore, le calcul du retard en commits échouait en silence et
# rendait toujours zéro : le garde-fou multi-postes était mort-né sur tout poste installé
# par ce script.
if git -C "$DEPOT" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    deja "suivi de branche en place"
else
    _br="$(git -C "$DEPOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
    git -C "$DEPOT" push --quiet -u origin "$_br" 2>/dev/null \
        && ok "branche $_br suivie et poussée" \
        || mort "impossible de poser le suivi de branche. Sans lui, la sauvegarde échouera
     avec un message trompeur parlant d'un conflit inexistant."
fi
# CONTRÔLE D'APRÈS POUSSÉE, et c'est lui qui protège vraiment. L'alignement décidé plus haut
# repose sur une DEVINETTE quand le dépôt est vide, puisqu'un dépôt vide n'annonce pas sa
# tête. Ici le dépôt n'est plus vide : il annonce. On compare donc ce qu'il annonce à ce
# qu'on a poussé, et on parle fort si ça diffère — c'est le dernier moment où le défaut est
# encore gratuit à corriger. Après, il dort jusqu'à la deuxième machine.
# Volontairement un AVERTISSEMENT et non un arrêt : le système est installé et sauvegarde
# correctement sur cette machine. Refuser l'installation pour un défaut qui ne se paie
# qu'ailleurs coûterait plus qu'il ne protège — mais se taire n'est pas une option.
_tete="$(git ls-remote --symref "$REMOTE_URL" HEAD 2>/dev/null \
         | sed -n 's#^ref: refs/heads/\(.*\)[[:space:]]HEAD$#\1#p' | head -1)"
_locale="$(git -C "$DEPOT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
_nbheads="$(git ls-remote --heads "$REMOTE_URL" 2>/dev/null | wc -l)"
# Une tête PENDANTE ne s'annonce pas du tout : `--symref` rend le vide, exactement comme un
# dépôt injoignable. Une première version de ce contrôle comparait donc le vide à la branche
# locale, ne trouvait pas de différence, et se taisait — dans le seul cas qu'elle existait
# pour attraper. Le discriminant est ailleurs : des branches existent ET la tête ne se
# résout pas. C'est la signature du défaut, et elle est lisible en une commande.
if [ "$_nbheads" -gt 0 ] && [ -z "$_tete" ]; then
    printf '    ⚠ le dépôt de sauvegarde a une tête PENDANTE — elle désigne une branche absente.\n'
    printf '      Ton travail est bien poussé sur « %s », mais une DEUXIÈME machine qui\n' "$_locale"
    printf '      clonerait ce dépôt récupérerait un dossier VIDE.\n'
    printf '      À corriger côté hébergeur : passer la branche par défaut du dépôt à « %s ».\n' "$_locale"
    printf '      Sur GitHub : Settings → General → Default branch.\n'
elif [ -n "$_tete" ] && [ -n "$_locale" ] && [ "$_tete" != "$_locale" ]; then
    printf '    ⚠ le dépôt de sauvegarde a pour tête « %s » et ton travail part sur « %s ».\n' "$_tete" "$_locale"
    printf '      Une DEUXIÈME machine qui clonerait ce dépôt récupérerait un dossier VIDE.\n'
    printf '      À corriger côté hébergeur : passer la branche par défaut du dépôt à « %s ».\n' "$_locale"
    printf '      Sur GitHub : Settings → General → Default branch.\n'
elif [ -n "$_tete" ]; then
    ok "tête du dépôt distant alignée sur $_locale"
fi

# --- 7ter. Hooks de Claude Code ---------------------------------------------
# LA PIÈCE SANS LAQUELLE LA MOITIÉ DU SYSTÈME NE TOURNE PAS, et elle manquait — trouvée
# par un audit externe. Le bilan de démarrage, les rappels datés, la dette de sécurité,
# la distillation due, le filet de sauvegarde de fin de session : tout passe par ces
# déclencheurs. Sans eux, le système a l'air installé et n'observe rien. C'est exactement
# ce que sa propre conception appelle « ce qui désactive en silence ».
# Fusion et non écrasement : Claude Code peut déjà avoir une configuration, et un hook
# déjà présent n'est jamais dupliqué.
etape "Déclencheurs de Claude Code"
SETTINGS="$HOME/.claude/settings.json"
[ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"
RTK_PRESENT=0; command -v rtk >/dev/null 2>&1 && RTK_PRESENT=1
python3 - "$SETTINGS" "$RTK_PRESENT" <<'PYTHON'
import json, sys, collections
chemin, rtk = sys.argv[1], sys.argv[2] == "1"
try:
    conf = json.load(open(chemin, encoding="utf-8"))
except Exception:
    conf = {}
if not isinstance(conf, dict): conf = {}
hooks = conf.setdefault("hooks", {})

voulus = {
    "SessionStart": [
        {"hooks": [{"type": "command",
                    "command": 'bash "$HOME/.claudeos/engine/boot-check.sh"',
                    "statusMessage": "État du système..."}]},
        {"hooks": [{"type": "command",
                    "command": 'bash "$HOME/.claude/skills/grilling/check_upstream_drift.sh" 2>/dev/null || true',
                    "statusMessage": "Vérification mensuelle des compétences empruntées...",
                    "async": False}]},
    ],
    # PAS de déclencheur `Stop` → clean-ads : le nettoyage des flux Windows est appelé par
    # `backup.sh` avant la capture — une fois par sauvegarde suffit, c'est l'en-tête du
    # script lui-même qui le dit, et l'autotest garde cet appelant (contrôle 20). Le hook
    # le faisait tourner à CHAQUE tour d'assistant sur tout le périmètre du manifeste :
    # vestige d'avant la migration, retiré du gabarit le 2026-08-14.
    "SessionEnd": [
        # La garde de portée : une session de projet (ouverte dans tmux par le script de
        # session) ne sauvegarde pas, la sauvegarde appartient à la session principale.
        # Sans elle, le script de session promet un comportement que le hook n'a pas.
        {"hooks": [{"type": "command",
                    "command": 'if [ "${OS_SESSION_SCOPE:-}" = "projet" ]; then echo "[backup-hook] session de projet — sauvegarde sautee, elle appartient a la session principale" >> "$HOME/.claudeos/engine/backup-hook.log"; exit 0; fi; bash "$HOME/.claudeos/engine/backup.sh" >> "$HOME/.claudeos/engine/backup-hook.log" 2>&1 || true',
                    "timeout": 300}]},
    ],
}
if rtk:
    voulus["PreToolUse"] = [{"matcher": "Bash",
                             "hooks": [{"type": "command", "command": "rtk hook claude"}]}]

ajoutes = 0
for evenement, entrees in voulus.items():
    existantes = hooks.setdefault(evenement, [])
    if not isinstance(existantes, list): continue
    deja = json.dumps(existantes, ensure_ascii=False)
    for e in entrees:
        cmd = e["hooks"][0]["command"]
        if cmd in deja: continue          # idempotence : jamais de doublon
        existantes.append(e); ajoutes += 1

json.dump(conf, open(chemin, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print(f"    {'✓' if ajoutes else '·'} {ajoutes} déclencheur(s) ajouté(s)" if ajoutes
      else "    · déclencheurs déjà en place")
PYTHON
# Garde : le système ne doit pas se déclarer installé si le démarrage n'est pas câblé.
grep -q "boot-check.sh" "$SETTINGS" || mort "les déclencheurs n'ont pas été écrits — le démarrage n'observerait rien."
ok "démarrage, arrêt et fin de session câblés"

# --- 7quater. Calibration des alarmes de dérive -----------------------------
# Les seuils de poids livrés avec le moteur sont calibrés sur le corpus de l'installation
# qui les a produits. Portés tels quels sur un corpus d'une autre taille, ils ne mesurent
# plus rien : trop hauts, l'alarme ne parle jamais ; trop bas, elle crie sur du travail
# ordinaire, et un signal dont on sait qu'il ne veut rien dire apprend à ignorer la
# catégorie entière. On pose donc le point zéro sur le corpus réel.
# Écrit une seule fois : sur une machine récupérée, le fichier arrive avec le dépôt, et
# le recalculer ici le ferait diverger d'une machine à l'autre pour le même corpus.
etape "Calibration des alarmes de dérive"
if [ -f "$DEPOT/engine/config/SEUILS" ]; then
    deja "seuils déjà calibrés (ils viennent du dépôt)"
else
    bash "$DEPOT/engine/calibrate.sh" || printf '    ⚠ calibration impossible — les seuils livrés restent en place, ils peuvent être hors sujet.\n'
fi

# --- 8. Autotest ------------------------------------------------------------
etape "Autotest de la plomberie"
if [ -x "$DEPOT/engine/selftest.sh" ] || [ -f "$DEPOT/engine/selftest.sh" ]; then
    bash "$DEPOT/engine/selftest.sh" >/dev/null 2>&1 \
        && ok "plomberie vérifiée" \
        || printf '    ⚠ l'"'"'autotest ÉCHOUE. Ce n'"'"'est pas normal : une installation neuve doit\n      le passer. Lis sa sortie avant d'"'"'aller plus loin — la sauvegarde est\n      refusée tant qu'"'"'il échoue :\n        bash ~/.claudeos/engine/selftest.sh\n'
else
    mort "autotest introuvable — l'installation est incomplète."
fi

# --- Fin --------------------------------------------------------------------
if [ "$MODE" = second ]; then
cat <<'FIN2'

════════════════════════════════════════════════════════════
  Machine ajoutée. Ta configuration est là.
════════════════════════════════════════════════════════════

  Rien à personnaliser : règles, mémoire et domaines sont venus du dépôt.
  L'entretien d'installation ne se rejoue PAS ici — il produirait une
  deuxième réponse aux mêmes questions, et deux réponses à deux âges se
  contredisent. Il se rejoue quand ta SITUATION change, pas ta machine.

  Une seule chose a changé et elle compte : tu travailles maintenant à
  plusieurs postes. La règle qui va avec est simple et elle n'est pas
  facultative — un seul poste actif à la fois, on tire avant de produire,
  et on ne sauvegarde JAMAIS depuis un poste en retard. Le script refuse
  de lui-même ; ne pas outrepasser son refus.

  Si tes règles ont été assemblées quand tu n'avais qu'une machine, elles
  ne portent pas cette section. Dans Claude Code :

     /claudeos-onboarding

  et réponds « oui » à la question sur les machines multiples. C'est le
  seul motif de le relancer aujourd'hui.

  1. Ouvre Claude Code :   claude
  2. Vérifie que tu es à jour avant de produire quoi que ce soit :
        bash ~/.claudeos/engine/sync.sh

FIN2
exit 0
fi

cat <<FIN

════════════════════════════════════════════════════════════
  Machinerie en place. Il reste la moitié conversationnelle.
════════════════════════════════════════════════════════════

  1. Ouvre Claude Code :            claude

  2. Installe le socle de méthode, en deux commandes dans Claude Code —
     ce sont des commandes de l'outil, pas du terminal, et c'est pour ça
     qu'elles ne sont pas dans ce script :

        /plugin marketplace add anthropics/claude-plugins-official
        /plugin install superpowers@claude-plugins-official

  3. Lance l'entretien d'installation :

        /claudeos-onboarding

     Il te demandera qui tu es, sur quoi tu travailles, et quel assistant
     tu veux en face de toi. Il assemblera tes règles à partir du catalogue,
     en ne gardant que celles dont la condition est vraie chez toi.

  4. Il finira par une première sauvegarde complète. Ne saute pas cette étape :
     une installation qui n'a pas prouvé qu'elle sait sauvegarder n'est pas
     une installation, c'est une promesse.

FIN
