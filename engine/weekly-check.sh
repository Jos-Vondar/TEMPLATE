#!/usr/bin/env bash
# GARDE D'ANALYSE — en TÊTE à dessein. Posée le 2026-09-22 en garde de VERSION, réécrite le
# 2026-09-23 quand le défaut de fond a été corrigé.
# LE DÉFAUT, constat C4 de `audits/2026-09-12-audit-portabilite-macos-engine.md` : bash 3.2, celui
# que macOS livre, apparie les accents graves jusque dans un heredoc à délimiteur quoté quand il
# est dans une substitution `$( … )`. Sept blocs Python y étaient ; ils vivent désormais dans des
# FONCTIONS `_claudeos_py_*`, dont le corps échappe à ce balayage. VÉRIFIÉ le 2026-09-23 :
# `/bin/bash -n` passe, et la passe complète sous bash 3.2 rend une sortie identique, ligne pour
# ligne, à celle de bash 5.
# POURQUOI LA GARDE RESTE. Bash exécute commande par commande : un bloc fautif ajouté plus tard
# laisserait tourner les premiers contrôles, puis ferait mourir le script À MI-PARCOURS sans
# verdict — une passe partielle lue comme complète. Le crochet de commit ne le voit pas, il analyse
# avec le bash 5 du poste. D'où ce contrôle : le bash qui EXÉCUTE analyse d'abord le fichier entier.
# RÈGLE pour tout bloc neuf : un programme Python se met dans une fonction, jamais dans un `$( … )`.
if ! "${BASH:-bash}" -n "${BASH_SOURCE[0]}" 2>/dev/null; then
    echo "[weekly] ⛔ REFUS — ce fichier ne s'analyse pas sous bash ${BASH_VERSION:-inconnu}." >&2
    echo "[weekly] Il mourrait à mi-parcours SANS rendre de verdict : RIEN n'a été contrôlé." >&2
    echo "[weekly] Cause probable : un bloc Python dans un \$( … ) — le mettre dans une fonction." >&2
    exit 1
fi
# =============================================================================
# WEEKLY-CHECK — les contrôles de CONTENU du système ClaudeOS.
#
# Né le 2026-08-22 du découpage de `selftest.sh` (étape 4.3 du plan de
# décomplexification). Ce que l'autotest portait en un bloc de 1 853 lignes, lancé
# avant CHAQUE sauvegarde, se répartit désormais selon ce que chaque contrôle
# regarde et à quelle vitesse il doit répondre :
#
#   • ce qui regarde CE QUI PART           → `hooks/pre-commit-alarmes.sh`, au commit ;
#   • ce qui regarde L'ARBRE VIVANT         → `controle-secrets.sh`, à la clôture ;
#   • ce qui regarde LES DOCUMENTS          → ICI, à la passe hebdomadaire ;
#   • ce qui regardait LA COPIE RSYNC       → supprimé avec elle.
#
# POURQUOI CE DÉCOUPAGE. Un contrôle de contenu ne doit jamais coûter le droit
# d'enregistrer son travail : un document qui ment se corrige, il ne se perd pas.
# La règle est écrite dans la compétence `controles-et-alarmes` — un défaut de
# contenu avertit, une corruption de plomberie bloque. Ici, presque tout avertit.
#
# APPELANT : la fiche d'hygiène de la compétence `os-audit`. Lançable à la main :
#   bash ~/.claude/engine/weekly-check.sh
#
# CODE RETOUR : 0 si rien de bloquant, 1 sinon. Les avertissements ne changent pas
# le code — ils se lisent.
# =============================================================================
set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"

FAIL=0
ok() { echo "  ✅ $1"; }
ko() { echo "  ❌ $1" >&2; FAIL=1; }
# warn : signale sans faire échouer. `ko` est réservé à ce dont le passage cause une PERTE
# IRRÉVERSIBLE, une FUITE, ou le DÉSARMEMENT SILENCIEUX d'une garde ; tout le reste avertit.
warn() { echo "  ⚠️  $1" >&2; }
# sans_objet CLE [partie] — vrai quand la réponse CLE vaut `non` : la règle que le contrôle garde
# n'est pas entrée chez l'installateur, donc il se SAUTE, et il le dit — jamais un vert muet.
# Une clé ABSENTE n'est pas `non` : le contrôle joue, un poste non réglé ne se devine pas.
sans_objet() {
    local v
    v="$(claudeos_reponse "$1")" || return 1
    [ "$v" = non ] || return 1
    echo "  ⏭  sans objet : $1=non${2:+ — $2}"
}

# Racines des DOSSIERS DE TRAVAIL, lues sur le disque par `claudeos_ws_roots` selon `GIT` : sous le
# dossier personnel par préfixe en `par-domaine`, sous `~/.claude/travail/` sinon. Leur discriminant
# est un `CLAUDE.md` à la racine.
# La PROFONDEUR reste figée chez chaque appelant : projet à 1 sous la racine, application à 2.
_WS=()
while IFS= read -r _r0; do
    [ -n "$_r0" ] && [ -d "$_r0" ] && _WS+=("$_r0")
done < <(claudeos_ws_roots)
if [ "${#_WS[@]}" -eq 0 ]; then
    # 2026-08-22 : la liste des numéros concernés (« 28, 29, 32, 33, 37 et la part domaine de
    # 22 et 27 ») est RETIRÉE. C'était l'inventaire recopié en dur que le contrôle 25 refuse aux
    # documents, et cette branche ne s'exécute jamais sur un poste qui a des domaines — donc
    # elle n'était jamais relue, et le premier contrôle ajouté l'aurait périmée en silence.
    echo "  ⏭  aucun dépôt client sur le disque : les contrôles à ce périmètre sont sans objet."
    echo "     Un dossier de travail porte un CLAUDE.md à sa racine (claudeos_ws_roots, selon GIT)."
fi
# DOCUMENTS DE RÉFÉRENCE de l'installateur, balayés en plus de `CLAUDE.md` et `DESIGN.md` : un motif
# de nom par ligne dans `reglages/DOCS_REFERENCE` (`SPEC_*.md`, `REFERENCE.md`…), `#` en tête pour
# un commentaire. Facultatif : absent, seuls les noms du template sont balayés.
_DOCS_REF=""
[ -f "$REG/DOCS_REFERENCE" ] && _DOCS_REF="$(grep -vE '^[[:space:]]*(#|$)' "$REG/DOCS_REFERENCE")"
_DOCS_FIND=(-name CLAUDE.md -o -name DESIGN.md)
while IFS= read -r _dr; do [ -n "$_dr" ] && _DOCS_FIND+=(-o -name "$_dr"); done <<< "$_DOCS_REF"

# Les CONDITIONS D'ENTRETIEN ont été retirées le 2026-08-22, au palier 5. Elles laissaient un
# destinataire du squelette décliner une fonction, et les contrôles ne l'exigeaient alors pas de
# lui. La chaîne d'export est supprimée : plus personne ne produit le fichier de réponses, donc
# toutes les conditions étaient vraies — ce qui était déjà le cas ici, ce fichier n'ayant jamais
# existé sur ce poste. Les quatre branches conditionnelles sont dépliées sur leur cas vrai.

# CAPTURE UNIQUE de `boot-check.sh`, partagée par les contrôles qui lisent sa sortie. Il est en
# lecture seule et déterministe à l'échelle d'un passage ; l'appeler quatre fois refaisait quatre
# fois ses scans. Si la capture échoue, la variable est vide et les contrôles échouent comme
# avant — le mode de défaillance ne change pas.
_BOOTOUT="$(bash "$SELF/boot-check.sh" 2>/dev/null)"

# CORPUS DES RÈGLES SITUATIONNELLES — partagé par les contrôles 21, 22 et 23.
# Il vivait en queue d'un contrôle de câblage supprimé le 2026-08-22 ; le déménagement l'aurait
# emporté avec lui et rendu trois contrôles muets d'un coup. Remonté ici, où sa portée est
# visible.
# Discriminant INTRINSÈQUE au corps, pour ne pas écrire ici une liste de slugs — un inventaire
# recopié est exactement ce que le contrôle 25 refuse. Chaque règle situationnelle ouvre sur une
# ligne de citation « > Fiche situationnelle ».
# L'ANCRE DE DÉBUT DE LIGNE EST LOAD-BEARING : sans elle, la compétence `os-audit` entre dans le
# corpus parce qu'elle nomme cette formule en prose — constaté en calibrant, l'assiette passait
# de 44 000 à 80 000 caractères.
_SITU="$(grep -rlE '^> Fiche situationnelle' "$HOME/.claude/skills"/*/SKILL.md 2>/dev/null | sort)"
# Un corpus VIDE est une mesure ratée, pas un petit corpus : il désarmerait trois contrôles sans
# rien dire. Il bloque.
[ -n "$_SITU" ] || ko "aucune règle situationnelle trouvée dans ~/.claude/skills/ (motif '^> Fiche situationnelle') — les contrôles 21, 22 et 23 seraient muets"

echo "[selftest] 2. Dépendances dures"
# `rsync` a quitté la liste le 2026-08-22 : il était la dépendance dure de la copie, et plus
# aucun script vivant ne l'appelle. Le garder aurait fait échouer une installation neuve pour
# un outil dont le système n'a plus besoin.
# git n'est une dépendance qu'en régime GitHub : sans git (`GIT=aucun`), son absence est le choix.
_deps="python3 git"; [ "$(claudeos_regime)" = aucun ] && { _deps="python3"; echo "  ⏭  sans objet : git — régime sans git (GIT=aucun)"; }
for dep in $_deps; do
    if command -v "$dep" >/dev/null 2>&1; then ok "$dep présent"; else ko "$dep MANQUANT"; fi
done

# CONTRÔLE 3 RETIRÉ le 2026-08-05 — il vérifiait que l'origin du dépôt vivant est le bon.
# Trois gardes portaient la même chose : le contrôle 12 exerce la FONCTION sur un faux dépôt
# (mauvais origin refusé, bon accepté), et `backup.sh` comme `sync.sh` appellent la garde en
# tête d'exécution, donc un mauvais origin échoue bruyamment avant tout transfert. Celui-ci
# n'ajoutait qu'une troisième lecture du même fait.

# SECONDE CAPTURE DE `boot-check.sh` RETIREE le 2026-08-22. Elle ecrasait la premiere (plus
# haut, avant le corpus des regles situationnelles) par une valeur identique, et faisait payer
# le scan deux fois : passe mesuree a 6,7 s dont ~6,6 s de double execution, plus deux `git
# fetch` reseau en trop. Le commentaire qu'elle portait vantait l'optimisation qu'elle annulait.

# retiré ce jour, et quatre contrôles suivants le lisent (37, 40 et deux autres).
# `_CMD` — le règlement racine. Défini ici depuis le 2026-09-08 : il vivait dans le contrôle 21,
_CMD="$HOME/.claude/CLAUDE.md"

# CONTRÔLE 5 RETIRÉ le 2026-09-08 (geste 2.7, décision D-G) — il vérifiait que la couche
# curatée 🧭 d'`INDEX.md` survivait au générateur. PLUS DE GÉNÉRATEUR : `build-index.sh` est
# supprimé le même jour, et `INDEX.md` est gelé — sa couche curatée est devenue `## Où trouver`
# d'`ETAT.md`, projeté. Un garde qui protège d'un écrasement que rien ne peut plus produire.

echo "[selftest] 22. Portabilité — aucun chemin propre à un poste dans les fichiers d'instruction"
# Rattaché à MULTIPOSTE le 2026-08-14 : la règle qu'il garde (« aucun chemin propre à un
# poste ») est retirée du règlement quand la condition est fausse. Exiger alors des
# instructions portables, c'est bloquer la sauvegarde pour un défaut que la personne a
# explicitement décliné — même faute que celle corrigée au contrôle 10.
# Lit MULTIPOSTE dans `reglages/REPONSES`, par `sans_objet` : à `non`, la règle qu'il garde n'est pas
# entrée chez l'installateur, et le contrôle se saute en le disant. Une clé absente le fait jouer.
# AVERTIT depuis le 2026-08-14 : un chemin propre à un poste est un défaut DOCUMENTAIRE —
# le contrôle 27 attrape ce qui pointe dans le vide. Bloquer ici faisait payer une erreur
# de carte par une interdiction de sauvegarder.
# Corps NON réindenté sous le `if` : un commit de la source se reporte ainsi tel quel (passe de
# report, `d-report-avant-version`).
if ! sans_objet MULTIPOSTE; then
_p=0
# Garde `_h` (slug exact du poste en dur) RETIRÉ le 2026-09-24 : sa formule ne pliait que le `/`,
# donc sur un compte à point il cherchait un slug inexistant et restait muet ; et depuis
# `autoMemoryDirectory` la mémoire ne dépend plus du slug. Le motif générique ci-dessous reste.
# Motif générique :
# tout '-home-…' / '-Users-…' dans une instruction est un nom de dossier de mémoire figé.
_h3=$(grep -rlE -- 'projects/-(home|Users|c|mnt)[A-Za-z0-9_-]*/' "$_CMD" "$HOME/.claude/skills" 2>/dev/null | sort -u)
[ -n "$_h3" ] && { warn "nom de dossier de mémoire figé (résoudre le slug, ne pas l'écrire) : $(echo "$_h3" | tr '\n' ' ')"; _p=1; }
# Chemins absolus dans les fichiers du système lui-même (périmètre où l'on est prescriptif).
# PÉRIMÈTRE INCHANGÉ AU 2026-08-09, volontairement : la conversion des fiches en compétences
# remplace `~/.claude/fiches` par les seules compétences SITUATIONNELLES ($_SITU), pas par
# tout `skills/`. Élargir à tout le dossier ferait entrer les compétences empruntées et celles
# qui documentent un chemin de conteneur (une compétence métier de l'auteur), donc un blocage neuf sur du
# préexistant sous couvert de recâblage. Cet élargissement est une décision à part.
# PÉRIMÈTRE ÉLARGI le 2026-08-28 aux instructions de DOMAINE, sur constat de l'audit du jour.
# Motif : le `CLAUDE.md` d'un projet personnel portait un chemin du dossier personnel
# Windows vu depuis WSL, qui a fait
# conclure à tort le 2026-08-23 sur le Mac que le corpus était hors de portée. Le MOTIF l'attrapait
# déjà (le motif des dossiers personnels macOS reconnaît aussi celui de Windows vu depuis
# WSL) — c'est le PÉRIMÈTRE qui ne le regardait pas.
# C'est un chemin ajouté à un contrôle existant, pas un contrôle neuf (interdit du 2026-08-17).
# Mesuré avant de poser : 35 fichiers balayés, ZÉRO faux positif une fois ce projet corrigé.
# La réserve du commentaire ci-dessus tient toujours pour `skills/` : elle n'est pas levée ici.
# `settings.json` AJOUTÉ le 2026-09-10, geste D6, APRÈS le geste A7 qui l'a nettoyé — l'ordre
# compte : posé avant, ce chemin aurait fait crier le contrôle dès la première passe sur ce que
# A7 corrige, et une alarme qui naît rouge s'apprend à être ignorée. Ce qu'il gardait ne
# gardait rien : le fichier est SUIVI, donc il voyage, et son bloc `autoMode.environment`
# nommait le dossier personnel de l'AUTRE poste comme dépôt de confiance — 35 entrées, dont
# un dépôt client privé et un hôte de service en ligne. Le périmètre est le fichier SUIVI et lui seul :
# `settings.local.json` est dans le `.gitignore`, ne voyage pas, et n'a rien à respecter ici.
# Un chemin de dossier personnel dans le fichier suivi est un défaut d'où qu'il vienne — il
# criera donc sur les deux postes, et c'est voulu.
# Mesuré avant de poser : après A7, `settings.json` ne porte AUCUN chemin absolu, donc zéro
# faux positif permanent. C'est un chemin ajouté à un contrôle existant, pas un contrôle neuf.
# RÉSERVE DE 2026-08-09 LEVÉE le 2026-09-17, sur décision de l'utilisateur à l'audit du jour, et
# sur MESURE — pas sur opinion. Elle craignait deux choses en élargissant `$_SITU` à tout
# `skills/` : faire entrer les emprunts, et faire entrer les fiches qui documentent un chemin de
# conteneur. Mesuré avant de lever, sur les 31 fiches : exactement DEUX portent un chemin absolu,
# deux compétences personnelles de l'auteur, et les DEUX sont maison — **zéro emprunt concerné**, la première
# crainte ne se réalisait pas. La seconde a été traitée à la source dans le même geste :
# la compétence de conteneur ne nomme plus de poste. Donc l'élargissement entre à zéro faux positif.
# CE QUI L'A RENDU DÛ : le contrôle ne voyait que 12 fiches sur 31, et l'autre compétence personnelle — fiche maison,
# ni empruntée ni documentant un conteneur — portait un chemin du dossier personnel Windows la
# veille d'un changement
# de poste, invisible par simple effet de bord. Le MOTIF l'attrapait, le PÉRIMÈTRE non : même
# diagnostic mot pour mot que l'élargissement du 2026-08-28, trois commentaires plus haut.
# `$_SITU` N'EST PAS TOUCHÉ : il sert aussi aux contrôles 21 et 23, dont la sémantique porte sur
# les règles SITUATIONNELLES et sur elles seules. Élargir la variable partagée aurait déplacé
# trois contrôles pour en corriger un.
_h2f=$(ls "$HOME"/.claude/skills/*/SKILL.md 2>/dev/null; echo "$_CMD"; echo "$HOME/.claude/DESIGN.md"; \
       echo "$HOME/.claude/settings.json"; \
       [ "${#_WS[@]}" -gt 0 ] && find -L "${_WS[@]}" \( "${_DOCS_FIND[@]}" \) 2>/dev/null)
# 2026-09-17 : le motif tolere une BARRE ECHAPPEE `\/`. Un serialiseur JSON de Foundation —
# celui de l'integration Claude Code d'iTerm2 — reecrit `settings.json` en echappant les `/`.
# Le motif nu rendait alors 0 sur un fichier qui portait DIX chemins absolus de poste : la garde
# posee pour ce fichier rendait vert sur exactement le cas qu'elle devait attraper. Mesure du
# jour : 0 sur le fichier stocke, 10 sur le meme contenu decode.
_h2=$(printf '%s\n' "$_h2f" | sed '/^$/d' | xargs grep -lE -- '\\?/home\\?/[a-z_][a-z0-9_-]*|\\?/Users\\?/[A-Za-z]' 2>/dev/null | sort -u)
# EXEMPTION NOMMEE (2026-09-17, arbitrage de l'utilisateur). Les dix crochets `cc-status` que
# l'integration Claude Code d'iTerm2 pose dans `settings.json` portent un chemin absolu de poste,
# et l'utilisateur a decide de le GARDER : remplacer par `$HOME` fait croire a iTerm2 que
# l'integration est cassee, et il la repose en dur. Sans exemption, ce controle avertirait chaque
# semaine sur une dette assumee — et c'est ainsi qu'on apprend a ne plus lire la ligne, le vrai
# signal se noyant avec. L'exemption porte sur ces LIGNES, pas sur le fichier : un fichier n'est
# retenu que s'il porte un chemin de poste AILLEURS que dans un crochet cc-status. La dette elle-meme
# vit au journal, `u-cc-status-chemin-dur`.
_h2=$(for _f in $_h2; do
        grep -E -- '\\?/home\\?/[a-z_][a-z0-9_-]*|\\?/Users\\?/[A-Za-z]' "$_f" \
          | grep -qvE 'cc-status' && printf '%s\n' "$_f"
      done)
[ -n "$_h2" ] && { warn "chemin absolu en dur dans le règlement, une règle situationnelle ou une instruction de domaine : $(echo "$_h2" | tr '\n' ' ')"; _p=1; }
# LES SCRIPTS DU MOTEUR entrent ici le 2026-09-10, EN MÊME TEMPS que la puce du règlement qui
# portait cette règle en sort : troc explicite, ce que le texte ne dit plus, la machine le tient.
# Sans ce bloc, le troc perdait une couverture — le périmètre ci-dessus ne voit aucun script, et
# le contrôle 27 ne voit un chemin d'un AUTRE poste que sur le poste où il est MORT, donc il se
# tait précisément là où le chemin est vrai et non portable.
# LES LIGNES DE COMMENTAIRE SONT ÉCARTÉES, comme au contrôle 27 et pour le même motif : elles
# citent des chemins d'un autre poste À DESSEIN — ce fichier en porte deux, qui documentent
# l'incident ayant posé le contrôle. Les compter ferait un faux positif à demeure.
# Mesuré avant de poser : hors commentaires, zéro script du moteur ne porte de chemin absolu.
_h2s=""
for _f in "$HOME"/.claude/engine/*.sh "$HOME"/.claude/engine/hooks/*.sh; do
    [ -f "$_f" ] || continue
    if grep -vE '^[[:space:]]*#' -- "$_f" | grep -qE -- '/home/[a-z_][a-z0-9_-]*/|/Users/[A-Za-z]'; then
        _h2s="$_h2s $(basename "$_f")"
    fi
done
[ -n "$_h2s" ] && { warn "chemin absolu en dur dans un script du moteur, hors commentaires :$_h2s"; _p=1; }
# D4 de l'audit du 2026-09-16, posé le 2026-09-17 — CHEMIN AJOUTÉ à ce contrôle, pas contrôle neuf.
# MOTIF, et c'est un défaut de PORTABILITÉ, d'où sa place ici : quand les racines `~/.claude`
# et `~/<PRÉFIXE>*` sont des LIENS, comme chez l'auteur sur le Mac, un `find` qui part de l'une d'elles SANS `-L` ne les déréférence pas
# et rend ZÉRO avec rc=0 — il marche sur WSL, il se tait sur le Mac, et un contrôle muet rend un
# vert. F-1 : sept `find` dans ce cas ont rendu les contrôles 28, 28bis, 33 et une moitié du 22/27
# aveugles, et DEUX AUDITS COMPLETS l'ont manqué. Corrigés le 2026-09-16 ; ce garde interdit le
# quatorzième. Les commentaires sont écartés, même motif que les deux blocs au-dessus.
# `-qP` SEUL, JAMAIS `-qE … -P` : les deux drapeaux sont EXCLUSIFS, GNU grep refuse avec
# « conflicting matchers specified » et rend rc=2. Combiné à un `2>/dev/null`, le garde rendait
# donc « rien trouvé » SUR UNE ERREUR D'EXÉCUTION — il était MUET, le défaut même qu'il traque.
# Mesuré à l'exercice le 2026-09-17 : son cas positif n'a pas crié. Et le test hors script passait,
# parce que le shell interactif route `grep` vers `ugrep`, qui tolère — un garde se teste DANS son
# script, jamais à côté. Le `2>/dev/null` est retiré : une erreur doit se voir.
# LE POINT DE DÉPART SEUL COMPTE, et ce motif a dû être resserré à l'exercice : `find` déréférence
# les composants INTERMÉDIAIRES d'un chemin de départ, seul le DERNIER composant n'est pas suivi
# s'il est un lien. Un premier motif plus large accusait `boot-check.sh:419`, qui part de
# `$HOME/.claude/plugins` — `plugins` n'est pas un lien, donc pas de défaut. On ne vise donc que les
# points de départ qui SONT une racine liée : `"$HOME/.claude"` terminé là, `"$HOME"/<PRÉFIXE>*`, ou une
# variable de racine. MESURÉ APRÈS RESSERRAGE : zéro signalement sur les scripts du moteur.
# PLUS DE `grep -P` — retiré le 2026-09-25, signalé par la session CLAUDE_OS_TEMPLATE. Le grep de
# macOS refuse `-P` (« invalid option -- P », rc=2) : le `if` passait alors au VERT sans rien lire,
# et le garde ne tenait que parce que le grep GNU de brew est en tête du PATH. Le lookahead
# `(?!-L)` devient deux `grep -E` : les lignes `find` partant d'une racine liée, puis celles qui
# n'ont PAS `-L`. Éprouvé le jour même, par script et sous les DEUX grep, sur deux lignes réelles du
# moteur (`find -L "${_WS[@]}"`, et un départ sous un préfixe) : `-L` retiré → détecté, `-L` présent →
# rien ; l'ancienne forme sous le grep de macOS rendait « rien » dans les deux cas.
# Les départs sous `"$HOME"/<PRÉFIXE>` se lisent dans `PREFIXES`, échappés pour l'ERE.
_h2Lre='"\$HOME/\.claude"|\$\{_WS\[@\]\}|claudeos_ws_roots|claudeos_repos'
while IFS= read -r _px; do
    [ -n "$_px" ] && _h2Lre="$_h2Lre|\"\\\$HOME\"/$(printf '%s' "$_px" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
done < <(claudeos_liste PREFIXES)
_h2L=""
for _f in "$HOME"/.claude/engine/*.sh "$HOME"/.claude/engine/hooks/*.sh; do
    [ -f "$_f" ] || continue
    if grep -vE '^[[:space:]]*#' -- "$_f" \
       | grep -E "find[[:space:]]+[^|;&]*($_h2Lre)" \
       | grep -vqE 'find[[:space:]]+-L'; then
        _h2L="$_h2L $(basename "$_f")"
    fi
done
[ -n "$_h2L" ] && { warn "\`find\` SANS \`-L\` partant d'une racine liée — muet sur le Mac, vert sur WSL :$_h2L"; _p=1; }
[ "$_p" = 0 ] && ok "règlement, règles situationnelles et instructions de domaine sans chemin propre à un poste"
fi

echo "[selftest] 23. Routage — règles situationnelles et registre des ratés"
# RECÂBLÉ le 2026-08-09 (conversion des fiches en compétences, DESIGN « Invariants de la couche situationnelle »).
# Ce que ce contrôle gardait avant : une fiche présente dans `~/.claude/fiches/` mais absente
# de la table `CLAUDE.md` §3.3 (orpheline, jamais chargée), et une fiche citée par la table
# mais absente du disque (pointeur mort). La table n'existe plus : le déclencheur EST la
# `description` du frontmatter, et c'est l'outil qui la charge. Les deux moitiés deviennent :
#   (a) toute règle situationnelle porte une `description` non vide — elle seule la route ;
#       une description absente est une règle qui ne se charge jamais, et rien ne le dirait ;
#   (b) toute compétence citée par une instruction du système existe sur le disque.
#   (c) AJOUTÉ le 2026-09-08 (geste 2.7) : tout dossier de `skills/` porte un `SKILL.md` au nom
#       EXACT. Motif, et il vient du geste même qui l'ajoute : supprimer une compétence se fait
#       en deux temps — déplacer son outil, puis retirer le dossier —, et un dossier resté sans
#       `SKILL.md` n'échoue nulle part : l'outil ne le charge pas, aucun contrôle ne le nomme, et
#       il ressemble à une compétence. La casse compte (`Skill.md` ne se charge pas non plus).
# `synced` EXCLU le 2026-09-17 : ce dossier n'est pas à nous — le harnais y dépose les compétences
#       synchronisées du compte (`anthropic-skills:*`), sous un dossier à UUID, et chacune porte son
#       `SKILL.md` un cran plus bas. Le contrôle le prenait pour une compétence maison amputée et
#       RENDAIT L'ÉCHEC BLOQUANT DE LA PASSE, sur un dossier que nous ne créons ni ne supprimons.
# BLOQUE dans les trois cas, par le partage de la compétence `controles-et-alarmes` : dans tous,
# une règle existe, le système croit l'appliquer, et elle ne se charge jamais.
_rt=0
while IFS= read -r _d; do
    [ -n "$_d" ] || continue
    [ -f "$_d/SKILL.md" ] || { ko "dossier de compétence SANS SKILL.md exact : skills/$(basename "$_d") — l'outil ne le charge pas, et rien d'autre ne le dit"; _rt=1; }
done < <(/usr/bin/find -L "$HOME/.claude/skills" -mindepth 1 -maxdepth 1 -type d -not -name synced 2>/dev/null)
while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    grep -qE '^description: *[^[:space:]]' "$_f" \
        || { ko "règle situationnelle sans description — donc sans déclencheur : $(basename "$(dirname "$_f")")"; _rt=1; }
done <<< "$_SITU"
# (b) MOTIF : la forme sous laquelle les instructions de ce système nomment une compétence —
# « compétence `slug` » en toutes lettres. On ne cherche PAS un slug nu entre guillemets
# obliques : trop courant pour discriminer, et le faux positif apprendrait à ignorer la
# catégorie entière. On ne cherche pas non plus « fiche `slug` » : la même forme désigne
# aussi des non-compétences dans ce corpus (`fiche pending`, ailleurs dans le corpus), donc le motif
# crierait sur du texte juste. Les pointeurs de cette forme ont été réécrits en
# « compétence » le 2026-08-09 pour tomber sous ce motif.
while read -r _n; do
    [ -z "$_n" ] && continue
    # La liste des compétences CONDITIONNELLES est tombée le 2026-08-22 avec la chaîne d'export :
    # elle reflétait la table de l'assembleur du squelette, seul autre endroit qui la connaissait.
    # Plus d'entretien, plus de conditions — toute compétence citée doit exister.
    [ -f "$HOME/.claude/skills/$_n/SKILL.md" ] \
        || { ko "compétence citée par une instruction mais absente du disque : $_n"; _rt=1; }
# LES FICHIERS GELÉS SORTENT DU PÉRIMÈTRE, ajouté le 2026-09-08 (geste 2.7). `HANDOFF.md` et
# `MEMORY.md` du système sont gelés : leur métier est de raconter le passé, donc ils nomment des
# compétences supprimées — et c'est correct. Les garder ici faisait BLOQUER la passe sur la
# mention historique d'`archivage`, mesuré le jour de sa suppression. Le filtre est l'en-tête de
# gel en PREMIÈRE ligne, jamais une liste de noms : les fichiers clients gelés en phase 3 en
# sortiront tout seuls.
done < <(for _gf in "$_CMD" "$HOME/.claude/DESIGN.md" \
                    "$HOME/.claude/MEMORY.md" "$HOME/.claude/skills"/*/SKILL.md \
                    "$HOME/.claude/skills"/*/*.md "$HOME/.claude/agents"/*.md; do
             [ -f "$_gf" ] || continue
             head -1 "$_gf" | grep -qF '> **GELÉ' && continue
             printf '%s\n' "$_gf"
         done | xargs -r grep -rhoE 'compétences? `[a-z][a-z0-9-]+`' 2>/dev/null \
           | grep -oE '`[a-z][a-z0-9-]+`' | tr -d '`' | sort -u)
# Le catalogue des règles est sorti de ce périmètre le 2026-08-22 : il n'était livré qu'avec le
# squelette, dont la chaîne est supprimée. Ce contrôle n'attrape que la forme « compétence `slug` » :
# une compétence désignée SANS slug (« la compétence qui la porte ») reste invisible à tout motif
# sans crier faux — cette classe-là se ferme à l'écriture, pas au contrôle.
# Le registre des ratés n'est exigé que si la règle qui l'alimente existe : elle est
# retirée du règlement quand MULTIDOMAINE est fausse (rattaché le 2026-08-14, même
# faute que celle corrigée au contrôle 10 — exiger ce qui a été décliné).
# Lit MULTIDOMAINE dans `reglages/REPONSES`, par `sans_objet` : à `non`, la règle qu'il garde n'est pas
# entrée chez l'installateur, et la partie du registre se saute en le disant. Une clé absente le fait jouer.
_rt_reg=""
if ! sans_objet MULTIDOMAINE "registre des ratés de routage"; then
    [ -f "$MEM/ROUTING_MISSES.md" ] || { ko "registre des ratés de routage absent ($MEM/ROUTING_MISSES.md)"; _rt=1; }
    grep -q 'ROUTING_MISSES' "$HOME/.claude/skills/os-audit/SKILL.md" 2>/dev/null \
        || { ko "l'audit ne lit pas le registre des ratés — la boucle de correction est morte"; _rt=1; }
    _rt_reg=", registre des ratés lu par l'audit"
fi
[ "$_rt" = 0 ] && ok "règles situationnelles toutes routées par leur description, compétences citées toutes présentes$_rt_reg"

# CONTRÔLE 24 RETIRÉ le 2026-09-08 (geste 2.7, décision D-G) — il mesurait le plafond du
# journal de session en JOURS et réclamait la rotation. REMPLACÉ par le découpage MENSUEL du
# journal d'événements : `journal/AAAA-MM.jsonl` n'a pas de plafond à tenir, il change de
# fichier tout seul. Le journal de session subsiste tant qu'un client n'a pas basculé ; sa
# rotation est un geste de la passe, plus une alarme.

echo "[selftest] 25. La documentation suit-elle le code ?"
# L'audit du 25/07 a montré le motif : le code bouge, les documents qui le décrivent restent.
# On garde deux affirmations mécaniquement vérifiables plutôt que d'espérer une relecture.
_doc=0
# Compté sur CE fichier depuis le 2026-08-22 : les contrôles ont quitté `selftest.sh`, qui
# n'est plus qu'une archive. Le motif reste le bandeau `[selftest] N.`, conservé exprès à
# travers le déménagement pour que chaque contrôle reste retrouvable par son numéro.
_real=$(grep -c '^echo "\[selftest\] [0-9]' "${BASH_SOURCE[0]}")
# Le nombre de contrôles est CALCULABLE depuis ce script : l'écrire ailleurs crée une copie
# qui se périme (trois documents divergents constatés le 25/07). Le correctif n'est pas de
# tenir les copies en phase, c'est de ne plus en écrire. On refuse donc tout compteur en dur.
while IFS= read -r _f; do
    [ -f "$_f" ] || continue
    # Motif élargi le 2026-07-27 : il ne voyait que les contrôles, et laissait donc passer
    # « six fiches », inscrit à QUATRE endroits de DESIGN.md et faux depuis la création de la
    # septième. Tout inventaire dont le compte se dérive du disque est concerné, pas seulement
    # celui des contrôles. Les nombres qui documentent une DÉCISION (un seuil choisi, une durée
    # retenue) restent légitimes : c'est pourquoi le motif cible des noms d'inventaire précis
    # et non « un nombre suivi d'un mot ».
    # Un compteur en CHIFFRES devant un nom d'inventaire annonce presque toujours un total.
    # `compétences` ajouté le 2026-08-09 avec la conversion des fiches : le nom de
    # l'inventaire a changé, le défaut qu'il guette non.
    _claim=$(grep -oiE '\b[0-9]+ (contrôles|tests|fiches|compétences|workstations)\b' "$_f" 2>/dev/null | head -3)
    # Les nombres ÉCRITS EN MOTS sont ambigus : « les trois contrôles qui gardent cette zone »
    # désigne un sous-ensemble, pas un total, et le flaguer produirait un faux positif — qu'on
    # apprendrait à ignorer, avec les vrais. On ne les retient donc que pour le seul cas où le
    # total est certain : un compte de règles sur la même ligne que le dossier qui les contient.
    # C'est la forme exacte des quatre occurrences de « six fiches » trouvées le 2026-07-27.
    # Borne de proximité en NOMBRE DE CARACTÈRES, pas « jusqu'au prochain point » : le chemin
    # du dossier contient lui-même des points (`~/.claude/skills/`), si bien qu'un motif borné
    # par `[^.]*` ne l'atteignait jamais et le contrôle restait muet sur le cas exact qu'il
    # visait — constaté à l'exercice de son cas positif.
    # DEUX FORMES DEPUIS LE 2026-08-09 : l'ancienne (`fiches` près de `fiches/`) reste, parce
    # qu'un document peut encore raconter l'état d'avant la conversion et y remettre un compte ;
    # la neuve (`compétences` près de `skills/`) est celle qui garde l'état courant.
    _claim="$_claim$(grep -oiE '\b(deux|trois|quatre|cinq|six|sept|huit|neuf|dix|onze|douze) (fiches\b.{0,60}fiches/|compétences\b.{0,60}skills/)' "$_f" 2>/dev/null | head -2)"
    [ -n "$_claim" ] && { warn "inventaire écrit en dur dans $(basename "$_f") ($(echo "$_claim" | tr '\n' ' ')) — il se compte à sa source ; retirer le nombre, ne pas le mettre à jour"; _doc=1; }
done <<EOF
$HOME/.claude/DESIGN.md
$MEM/INDEX.md
EOF
# BRANCHE RETIRÉE le 2026-08-07 : elle cherchait la chaîne littérale « 250 lignes » dans la
# conception. « plafond de deux cent cinquante lignes » la désarmait. C'est exactement la classe
# du contrôle 31, retiré le 2026-08-05 avec ce motif écrit : « il gardait UN incident daté sous
# une forme littérale que toute reformulation désarme ». Ce qui garde encore : la branche
# générique des inventaires ci-dessous, et l'audit sur la véracité de la conception. Au retour
# du défaut, c'est une dérive documentaire de classe avertissement, rattrapée à l'audit suivant.

# L'ancienne branche « DESIGN.md mentionne-t-il fiches/ ? » était VERTE PAR CONSTRUCTION : la
# chaîne y figure des dizaines de fois, donc le contrôle ne pouvait rien détecter et affichait
# pourtant « DESIGN.md à jour sur la couche des fiches ». C'est pire qu'un contrôle absent : il
# délivrait une assurance fausse. Remplacée le 2026-07-27 par trois vérifications qui peuvent
# échouer — et c'est ce trou qui a laissé l'inventaire des fiches incomplet et deux de ses
# déclencheurs divergents jusqu'à ce qu'un audit les trouve à la main.
_D="$HOME/.claude/DESIGN.md"
# (a) et (b) RETIRÉES le 2026-08-19, sur décision de l'utilisateur, avec la table qu'elles
#     gardaient (DESIGN « Invariants de la couche situationnelle »). Motifs, dans cet ordre :
#     * (a) exigeait que toute compétence du dossier figure au design. Elle FABRIQUAIT le travail
#       qu'elle mesurait : elle a crié le 2026-08-19 sur une compétence créée dix minutes plus tôt,
#       et le « correctif » consistait à recopier une `description` déjà chargée au démarrage. La
#       liste est calculable (`ls ~/.claude/skills/`), donc la doctrine « un fait calculable ne
#       s'écrit pas, il se lit » l'interdisait. Preuve empirique du retrait : la table listait 12
#       compétences quand le dossier en portait 28 — périmée de 16, sans que rien le signale.
#     * (b) cherchait une ligne de la table pointant une compétence disparue. Sans table, elle ne
#       peut plus rien attraper : elle serait MUETTE, et un contrôle muet est pire qu'absent
#       puisqu'on le croit.
#     Le sens du geste, à ne pas confondre avec un relâchement : c'est l'arbitrage du 2026-08-17
#     (« pas de nouveau contrôle, y en a assez ») pris dans l'autre sens — on en retire un.
#     (c) RESTE, et son rôle grandit : elle est désormais le garde qui empêche la table de revenir.
# (c) Anti-régression, RECIBLÉE le 2026-08-09. Elle guettait le retour de la colonne des
#     déclencheurs, retirée le 2026-07-27 parce qu'elle recopiait la table du racine. Cette
#     table n'existe plus : le déclencheur vit dans la `description` du frontmatter, et c'est
#     désormais ELLE qu'un inventaire pourrait recopier — même défaut, nouvelle source.
_claudeos_py_dup() {
python3 - "$_D" $_SITU <<'PYDUP' 2>/dev/null
import os, re, sys
design = open(sys.argv[1], encoding="utf-8").read()
out = []
for p in sys.argv[2:]:
    txt = open(p, encoding="utf-8").read()
    m = re.search(r'^description: *(.+)$', txt, re.M)
    if not m:
        continue
    # Fragment SUFFISAMMENT LONG pour ne pas coïncider par hasard : une description
    # entière ne serait jamais recopiée mot pour mot, c'est son ouverture qui migre.
    frag = m.group(1).strip()[:60]
    if len(frag) > 40 and frag in design:
        out.append(os.path.basename(os.path.dirname(p)))
print(" · ".join(out))
PYDUP
}
_dup=$(_claudeos_py_dup)
[ -n "$_dup" ] && { warn "déclencheur de règle situationnelle recopié dans DESIGN.md ($_dup) — il vit dans la description de la compétence, seule source du routage"; _doc=1; }
[ "$_doc" = 0 ] && ok "aucun inventaire en dur, inventaire situationnel de DESIGN.md complet dans les deux sens, aucun déclencheur recopié"

echo "[selftest] 26. Amorçage — le gabarit crée-t-il dans l'arbre sauvegardé ?"
# L'EXISTENCE DU GABARIT N'EST PLUS TESTÉE ICI (2026-08-07) : le contrôle 27 vérifie déjà, en
# bloquant, que tous les chemins cités par les règles existent — et le racine cite ce gabarit
# entre guillemets obliques, forme exacte qu'il balaie. Deux gardes pour le même défaut.
# CE QUI RESTE, et qui est unique : le gabarit crée-t-il DANS l'arbre sauvegardé.
_tpl="$HOME/.claude/resources/DOMAINE_TEMPLATE.md"
# SENS INVERSÉ le 2026-09-08 (geste 1.15), et il fallait l'inverser : jusqu'à la bascule le
# défaut était de créer HORS de `~/workstations/`, racine morte le 2026-09-08, et le motif cherché rendait 0 —
# donc le contrôle disait, après le 2026-09-08, « toutes les destinations sont sous ~/workstations/ » alors que ce
# dossier n'existait plus. Un OK MENSONGER, pas un silence. Ce qu'il mesure désormais, et rien
# de plus : le gabarit nomme-t-il encore le dossier mort. Un emplacement franchement arbitraire
# reste indétectable par un `grep`, et ce contrôle ne prétend pas le voir.
if [ ! -f "$_tpl" ]; then ok "⏭ sauté : gabarit absent — son existence est gardée par le contrôle 27"
elif grep -qF '~/workstations/' "$_tpl"; then   # racine des V1 et V2, morte le 2026-09-08
    warn "le gabarit crée sous ~/workstations/, dossier MORT depuis la bascule du 2026-09-08 — un client naîtrait hors de tout dépôt, sans que rien n'échoue"
else ok "le gabarit ne nomme plus ~/workstations/, morte le 2026-09-08"; fi

echo "[selftest] 27. Chemins morts dans les fichiers d'instruction"
# selftest 7 couvre les références entre scripts ; ici ce sont les chemins cités par les
# RÈGLES et les procédures. C'est ce qui aurait attrapé d'un coup les procédures mortes du 25/07.
# PÉRIMÈTRE RECÂBLÉ le 2026-08-09 : les fiches sont devenues des compétences, et les seules
# règles SITUATIONNELLES entrent ici — passées en arguments depuis `$_SITU`. Élargir à tout
# `skills/` ferait entrer les compétences empruntées et celles qui documentent des chemins de
# conteneur, donc un blocage neuf sur du préexistant sous couvert de recâblage. Cet
# élargissement est une décision à part, pas un effet de bord de la conversion.
# Les racines de domaine passent par l'ENVIRONNEMENT et non par argv : `$_SITU` y est
# volontairement non quoté (un fichier par mot), et y mêler des racines rendrait argv ambigu.
_claudeos_py_dead() {
CLAUDEOS_WS_ROOTS="$(printf '%s\n' ${_WS[@]+"${_WS[@]}"})" CLAUDEOS_DOCS_REF="$_DOCS_REF" \
    CLAUDEOS_AU_BESOIN="${CLAUDEOS_CHEMINS_AU_BESOIN:-}" python3 - $_SITU <<'PYEOF' 2>/dev/null
import re, os, glob, sys
H = os.path.expanduser('~')
files = [f'{H}/.claude/CLAUDE.md'] + sys.argv[1:] + glob.glob(f'{H}/.claude/resources/*.md')   # 2026-08-22 : `~/resources` a demenage sous `~/.claude/`
for _root in os.environ.get('CLAUDEOS_WS_ROOTS', '').splitlines():
    if not _root.strip(): continue
    files += glob.glob(f'{_root}/CLAUDE.md') + glob.glob(f'{_root}/*/CLAUDE.md')
skip = re.compile(r'[<>*{}]|MÉMOIRE|slug')       # gabarits et jokers : pas des chemins réels
out = []

# EXTENSION du 2026-09-09 (plan de correction de l'audit, lot 8/D6). Trois périmètres échappaient
# au contrôle : les mémoires thématiques, les scripts du moteur, et les documents de référence
# des dépôts, à leur racine (`reglages/DOCS_REFERENCE`). Ils citent des chemins et envoient une session dans le vide exactement comme une règle.
# ILS N'ENTRENT PAS DANS `files` : trois filtres les bornent, et sans eux la mesure à blanc de ce
# jour rendait **72** sorties, presque toutes de l'histoire — un contrôle qui déverse 72 lignes
# d'archive s'éteint à la première lecture. Avec les trois : 1 dans `memory/`, 0 ailleurs.
#   (i)   vivant seulement — un en-tête de gel ou `ARCHIVE` dans le nom sort le fichier ;
#   (ii)  chemins qui DOIVENT exister sur ce poste — sous `~/.claude/` ou sous un dépôt client.
#         Les fiches d'auto-mémoire décrivent la seedbox et le Mac : un chemin distant n'est pas
#         un chemin mort, et crier dessus serait un faux à demeure ;
#   (iii) pour les scripts, hors lignes de commentaire — elles racontent des chemins morts à
#         dessein, c'est même leur fonction (« ce dossier a disparu le … »).
# LE PÉRIMÈTRE HISTORIQUE N'EST PAS TOUCHÉ : les trois filtres ne s'appliquent qu'à l'extension.
# Les y étendre éteindrait en silence des alertes que le contrôle rend déjà.
_racines = [f'{H}/.claude'] + [r.strip() for r in os.environ.get('CLAUDEOS_WS_ROOTS', '').splitlines() if r.strip()]
extra = glob.glob(f'{H}/.claude/memory/*.md') + glob.glob(f'{H}/.claude/engine/*.sh')
for _root in _racines:
    for _m in os.environ.get('CLAUDEOS_DOCS_REF', '').splitlines():
        if _m.strip():
            extra += glob.glob(f'{_root}/{_m.strip()}')

def _vivant(path):
    if 'ARCHIVE' in os.path.basename(path).upper(): return False
    try:
        with open(path, encoding='utf-8') as fh:
            for line in fh:
                if not line.strip(): continue
                return not line.startswith('> **GELÉ')
    except OSError:
        return False
    return True

def _sous_racine(p):
    a = os.path.realpath(os.path.expanduser(p.rstrip('.,;:')))
    return any(a == r or a.startswith(r + '/') for r in (os.path.realpath(x) for x in _racines))

for f in sorted(set(extra)):
    if not _vivant(f): continue
    _code_seul = f.endswith('.sh')
    try: lignes = open(f, encoding='utf-8').read().splitlines()
    except OSError: continue
    for line in lignes:
        if _code_seul and line.lstrip().startswith('#'): continue
        for m in re.finditer(r'`(~/[^`\s]+)`', line):
            p = m.group(1)
            if skip.search(p): continue
            if not _sous_racine(p): continue
            if not os.path.exists(os.path.expanduser(p.rstrip('.,;:'))):
                out.append(f"{os.path.relpath(f, H)} → {p}")

for f in files:
    try: txt = open(f, encoding='utf-8').read()
    except OSError: continue
    for m in re.finditer(r'`(~/[^`\s]+)`', txt):
        p = m.group(1)
        if skip.search(p): continue
        if not os.path.exists(os.path.expanduser(p.rstrip('.,;:'))):
            out.append(f"{os.path.relpath(f, H)} → {p}")
# LES CHEMINS NÉS AU PREMIER BESOIN (copie du template, A6, 2026-10-01) : une installation neuve ne
# les porte pas encore, et certains n'existent jamais dans un régime — `RTK.md` sans proxy, les
# empreintes de clôture en régime GitHub. Les crier ferait une fausse alarme PERMANENTE, qui éteint
# sa catégorie : ils sont comptés à part, et le compte s'affiche. Liste : `config.sh`.
_besoin = set(os.environ.get('CLAUDEOS_AU_BESOIN', '').split())
def _au_besoin(p):
    p = p.rstrip('.,;:')
    return any(p == b or (b.endswith('/') and p.startswith(b)) for b in _besoin)
_vus = sorted(set(out))
print('\n'.join(l for l in _vus if not _au_besoin(l.split(' → ', 1)[1])))
print('#AU_BESOIN %d' % sum(1 for l in _vus if _au_besoin(l.split(' → ', 1)[1])))
PYEOF
}
_dead_tout=$(_claudeos_py_dead)
_dead=$(printf '%s\n' "$_dead_tout" | grep -v '^#AU_BESOIN ' | grep -v '^[[:space:]]*$')
_au_besoin=$(printf '%s\n' "$_dead_tout" | sed -n 's/^#AU_BESOIN //p')
[ "${_au_besoin:-0}" -gt 0 ] 2>/dev/null \
    && echo "  ⏭  ${_au_besoin} chemin(s) cité(s) qui naissent au premier besoin, encore absents — non comptés (CLAUDEOS_CHEMINS_AU_BESOIN)"
if [ -n "$_dead" ]; then
    # AVERTIT depuis le 2026-08-14 : un pointeur mort envoie la session dans le vide, il ne
    # désactive ni ne détruit rien — même classe que le contrôle 45. C'est ce contrôle qui a
    # refusé une première sauvegarde le jour de l'arbitrage.
    warn "chemin cité par une règle mais absent du disque :"; echo "$_dead" | sed 's/^/       /' >&2
else ok "tous les chemins cités par les règles et les procédures existent"; fi

echo "[selftest] 27bis. Chemins DÉCHUS — cités par une instruction vivante alors que leur autorité est morte"
# Né le 2026-08-22, de l'audit contradictoire de la refonte, qui a trouvé la classe que le
# contrôle 27 ne peut PAS voir. Lui teste `os.path.exists` : tant que `~/.claudeos` est sur le
# disque, ses 42 citations résolvent et passent au vert. Or l'archive est FIGÉE depuis le
# 2026-08-22 — un document qui y envoie une session ne pointe pas dans le vide, il pointe vers
# une autorité morte, ce qui est pire : la session y trouve un fichier plausible et le suit.
# Deux fiches faisaient ainsi EXÉCUTER un script archivé (l'ancien script de poussée, `backup.sh`).
# Mesuré avant écriture, comme l'exige la doctrine : 42 citations dans 14 fichiers.
# PÉRIMÈTRE plus large que le 27, volontairement : le 27 ne voit que les règles situationnelles
# passées par `$_SITU`, et c'est précisément ce qui laissait `pousser-son-dossier` dehors.
# ÉCHAPPATOIRE : une ligne qui porte le marqueur `[archive]` est passée — c'est la façon de
# dire « je parle de l'archive en connaissance de cause » (bandeau daté, récit historique).
# AVERTIT, ne bloque pas : même classe que le 27 et le 45.
# PORTABILITÉ, 2026-09-12 — LE DÉFAUT LE PLUS COÛTEUX DU MOTEUR, ET IL ÉTAIT INVISIBLE.
# Ce bloc Python vivait DANS un `$( … )`. Bash 3.2 apparie les accents graves à l'intérieur d'une
# substitution MÊME quand ils sont dans un heredoc à délimiteur quoté : l'expression régulière de la
# ligne `DECHU` en porte un, le parseur s'est désynchronisé, et l'erreur sortait 700 LIGNES PLUS BAS
# (l.1175, sur un `;;` de `case` sans rapport). Conséquence sous le bash d'Apple : sept contrôles
# tournaient, QUINZE mouraient, et le verdict final n'était jamais rendu. Le corps d'une FONCTION
# échappe à ce balayage. `bash -n` du hook de commit ne l'attrapait pas : il tourne avec le bash de
# la machine qui committe, donc bash 5, où le fichier est valide.
# Le PC sous WSL exécute le même fichier : l'enveloppe est neutre en bash 5 comme en 3.2.
_claudeos_py_27bis() {
python3 - <<'PYEOF' 2>/dev/null
import re, os, glob
H = os.path.expanduser('~')
files = [f'{H}/.claude/CLAUDE.md', f'{H}/.claude/DESIGN.md', f'{H}/.claude/memory/INDEX.md']
for pat in ('skills/*/*.md', 'resources/*.md', 'agents/*.md'):
    files += glob.glob(f'{H}/.claude/{pat}')
# RECENTRÉ le 2026-09-08 (geste 2.7). Le motif d'origine cherchait `~/.claudeos`, dont
# l'archive est morte sur les deux postes ; il est GARDÉ, et deux classes s'ajoutent :
#   - les dossiers morts de la bascule du 2026-09-08 — `~/workstations/` et `~/workstations.ancien-*` ;
#   - les fichiers d'état GELÉS du niveau système, dont une instruction vivante ne doit plus
#     faire une destination d'écriture.
# LE SECOND DISCRIMINANT N'EST PAS LE CHEMIN, C'EST CE QUE LA LIGNE DIT : nommer un fichier
# gelé POUR DIRE qu'il est gelé est exactement ce qu'on veut lire. Une ligne qui porte « gel »
# ou « GELÉ » passe donc, comme celle qui porte `[archive]`. Sans cette nuance, le contrôle
# crierait sur chaque pointeur correct — et un contrôle qui crie sur l'état voulu s'éteint.
DECHU = re.compile(r'~/\.claudeos[^\s`)"\']*'
                   r'|~/workstations(?:\.ancien-[0-9-]+)?(?:/[^\s`)"\']*)?')   # morts le 2026-09-08
# ANCRÉ SUR LE CHEMIN SYSTÈME, corrigé le 2026-09-08 en exerçant le contrôle : le premier
# motif cherchait `MEMORY.md` et `HANDOFF.md` nus et rendait **116 citations** le 2026-09-08. Or ces deux
# noms sont VIVANTS — ils désignent les fichiers d'état de quatre dépôts clients qui n'ont pas
# basculé. Seuls ceux du niveau SYSTÈME sont gelés, et ils se nomment par leur chemin.
SECRET4 = re.compile(r'CLAUDE\.md\s*§\s*4\b[^\n]{0,40}secret|secret[^\n]{0,60}CLAUDE\.md\s*§\s*4\b', re.I)
MORT_CODE = re.compile(r'HANDOFF\.md')   # mort le 2026-09-17
GELES = re.compile(r'~/\.claude/(?:MEMORY|HANDOFF)\.md'   # gelés le 2026-09-08
                   r'|~/\.claude/memory/(?:INDEX|LEARNING_PROPOSALS)\.md')
out = []
for f in sorted(set(files)):
    try: txt = open(f, encoding='utf-8').read()
    except OSError: continue
    gele_lui_meme = txt.startswith('> **GELÉ')
    for i, l in enumerate(txt.splitlines(), 1):
        if '[archive]' in l: continue
        for m in DECHU.finditer(l):
            out.append(f"{os.path.relpath(f, H)}:{i} → {m.group(0)[:70]}")
        if gele_lui_meme:
            continue                      # un fichier gelé parle du passé, c'est son métier
        bas = l.lower()
        if 'gel' in bas or 'gelé' in bas:
            continue
        for m in GELES.finditer(l):
            out.append(f"{os.path.relpath(f, H)}:{i} → {m.group(0)} (GELÉ — dis-le, ou pointe ETAT.md)")
        for m in SECRET4.finditer(l):
            out.append(f"{os.path.relpath(f, H)}:{i} → renvoi au règlement §4 pour les secrets (MORT — compétence secrets-detail)")
# NOMS MORTS DANS LE CODE DU MOTEUR, ajouté le 2026-09-22 (lot D de l'audit du soir). Le texte
# qu'un script INJECTE gagne sur toute fiche, et aucun audit ne le balayait : `boot-check.sh`
# ordonnait de créer un HANDOFF.md le jour de leur suppression, le 2026-09-22. Lignes de CODE seulement — un
# commentaire raconte le passé, c'est son métier (`controles-et-alarmes` : un garde-fou mesure le
# code). Témoin positif tiré des données : `git show <commit avant le 2026-09-22 soir>:engine/boot-check.sh`
# y rend trois lignes.
for f in sorted(glob.glob(f'{H}/.claude/engine/*.sh') + glob.glob(f'{H}/.claude/engine/hooks/*.sh')):
    try: lignes = open(f, encoding='utf-8').read().splitlines()
    except OSError: continue
    for i, l in enumerate(lignes, 1):
        if l.lstrip().startswith('#'): continue
        if MORT_CODE.search(l):
            out.append(f"{os.path.relpath(f, H)}:{i} → nom MORT dans le code : {l.strip()[:70]}")
print('\n'.join(out))
PYEOF
}
_dechu=$(_claudeos_py_27bis)
if [ -n "$_dechu" ]; then
    warn "instruction vivante qui renvoie à l'archive figée ($(printf '%s\n' "$_dechu" | wc -l | tr -d ' ') citation(s)) — réécrire sur le régime vivant, ou marquer la ligne \`[archive]\` :"
    printf '%s\n' "$_dechu" | sed 's/^/       /' >&2
    _r=1
else ok "aucune instruction vivante ne renvoie à l'archive figée"; fi

echo "[selftest] 27ter. Copies de script entre compétences — ont-elles divergé ?"
# La duplication d'un script entre compétences est ASSUMÉE — une compétence doit être
# auto-portante, elle s'exporte avec son dossier — mais rien ne détectait leur divergence :
# corriger un défaut dans l'une laisserait l'autre le porter, en silence.
# Ce contrôle ne demande pas de dédoublonner, il demande que les copies restent égales.
# Il ne surveille aucune paire nommée : il découvre les doublons de nom à chaque passage.
# ÉTENDU AUX DÉFINITIONS D'AGENTS le 2026-09-09, sur arbitrage de l'utilisateur (D-5 du plan de
# correction). Les définitions d'un domaine, `domaines/<D>/agents/`, existent en copies RÉELLES
# dans les `.claude/agents/` de dossiers de travail — pas des liens, mesuré à l'audit.
# La COUCHE DOMAINE FAIT FOI ; les deux autres sont des copies diffusées. Sans ce contrôle, la
# première correction portée sur une seule les fait diverger en silence.
# ÉTENDU AUX OUTILS le 2026-09-10 (geste D2 du plan de correction de l'audit du jour, constat C-4).
# `resources/tools/test_update_version.py` existe en copie RÉELLE sous
# `<DÉPÔT_A>/<APP>/tools/` — mesuré, ce n'est pas un lien. LA SOURCE EST
# `resources/tools/`, par la même lecture que « la couche domaine fait foi ».
# CE QUE L'AUDIT AVAIT DIT DE TROP, et il faut le savoir pour ne pas le rouvrir : son constat C-4
# nommait aussi les cinq `<dépôt>/.claude/rules/*.md`. Ce sont des LIENS SYMBOLIQUES vers
# `domaines/` — un lien ne peut pas diverger, il n'a pas de contenu propre. Le `md5sum` rendait
# l'empreinte de la CIBLE, ce qui fabriquait un faux doublon. Leçon qui dépasse ce cas : un doublon
# établi au `md5` seul n'est pas un doublon tant qu'on n'a pas testé `[ -L ]`.
# CE N'EST PAS UN CONTRÔLE DE PLUS : même `[selftest]`, même verdict, périmètre élargi — le cliquet
# `CLAUDEOS_CLIQUET_CONTROLES` compte les `echo "[selftest] N`, et il est à sa borne.
# EXISTENCE AVANT LECTURE, posé le 2026-10-01 — signalé par une session de projet pour deux
# lignes, recontrôlé sur toutes. Le `2>/dev/null` portait sur `sed` et non sur `find` dans la liste
# des noms, et les lignes `skills` et `domaines` n'en avaient aucun : un dossier disparu faisait
# imprimer l'erreur de `find` et rétrécissait le périmètre sans le dire. Désormais chaque racine est
# TESTÉE avant lecture, une par une pour les dossiers de travail, et plus rien n'est masqué : un
# dossier ABSENT se tait — il n'y a rien à comparer —, un dossier présent mais ILLISIBLE parle. Les
# deux listes changent ENSEMBLE : elles doivent garder le même périmètre (`controles-et-alarmes`,
# « une mesure comparative se change des deux côtés »). `_rac27`, parce que `_rt` est déjà pris plus haut.
_div=""
while IFS= read -r _n; do
    _c=(); while IFS= read -r _cf; do [ -n "$_cf" ] && _c+=("$_cf"); done < <( { [ -d "$HOME/.claude/skills" ] && find -L "$HOME/.claude/skills" -name "$_n" -type f -not -path '*/synced/*'
                         [ -d "$HOME/.claude/domaines" ] && find -L "$HOME/.claude/domaines" -path '*/agents/*' -name "$_n" -type f
                         [ "${#_WS[@]}" -gt 0 ] && for _rac27 in "${_WS[@]}"; do [ -d "$_rac27" ] && find -L "$_rac27" -path '*/.claude/agents/*' -name "$_n" -type f; done
                         [ -d "$HOME/.claude/resources/tools" ] && find -L "$HOME/.claude/resources/tools" -name "$_n" -type f
                         [ "${#_WS[@]}" -gt 0 ] && for _rac27 in "${_WS[@]}"; do [ -d "$_rac27" ] && find -L "$_rac27" -path '*/tools/*' -name "$_n" -type f; done
                       } | sort -u )
    [ "${#_c[@]}" -lt 2 ] && continue
    # PORTABILITÉ 2026-09-12 : `md5sum` et `realpath --relative-to` sont des outils GNU, absents
    # de macOS. Les deux côtés de la comparaison rendaient vide, donc "" = "", donc « identiques » :
    # vert par construction. Voir claudeos_hash_file dans config.sh. Le chemin relatif se fait par
    # retrait de préfixe, ce qui est POSIX et n'appelle aucun outil.
    _ref=$(claudeos_hash_file "${_c[0]}" || true)
    if [ -z "$_ref" ]; then
        warn "27ter : AUCUN HACHEUR DISPONIBLE (md5sum, shasum, md5) — la comparaison des copies n'a PAS eu lieu. Ne pas lire ce contrôle comme vert."
    else
    for _f in "${_c[@]:1}"; do
        [ "$(claudeos_hash_file "$_f" || true)" = "$_ref" ] || _div="$_div$_n : ${_c[0]#$HOME/} ≠ ${_f#$HOME/}\n"
    done
    fi
done < <( { [ -d "$HOME/.claude/skills" ] && find -L "$HOME/.claude/skills" -name "*.py" -type f -not -path '*/synced/*' | sed 's#.*/##'
            [ -d "$HOME/.claude/domaines" ] && find -L "$HOME/.claude/domaines" -path '*/agents/*' -name "*.md" -type f | sed 's#.*/##'
            [ "${#_WS[@]}" -gt 0 ] && for _rac27 in "${_WS[@]}"; do [ -d "$_rac27" ] && find -L "$_rac27" -path '*/.claude/agents/*' -name "*.md" -type f; done | sed 's#.*/##'
            [ -d "$HOME/.claude/resources/tools" ] && find -L "$HOME/.claude/resources/tools" -name "*.py" -type f | sed 's#.*/##'
            [ "${#_WS[@]}" -gt 0 ] && for _rac27 in "${_WS[@]}"; do [ -d "$_rac27" ] && find -L "$_rac27" -path '*/tools/*' -name "*.py" -type f; done | sed 's#.*/##'
          } | sort | uniq -d )
if [ -n "$_div" ]; then
    warn "copies divergentes (script de compétence, ou définition d'agent) — les réaligner sur la SOURCE :"
    echo "       pour un agent, la source est \`~/.claude/domaines/<D>/agents/\` (arbitrage du 2026-09-09)." >&2
    printf '%b' "$_div" | sed 's/^/       /' >&2
    _r=1
else ok "les scripts présents en plusieurs exemplaires sont identiques entre eux"; fi

echo "[selftest] 28. Réceptacle des documents client à la racine de chaque projet"
# Décision du 2026-07-25 : le réceptacle vit au niveau PROJET seulement
# (`<DÉPÔT>/<PROJET>`), pas au niveau application. On n'en attend donc
# aucun plus profond, et on n'en réclame pas un aux apps ni aux sous-dossiers.
# Rattaché à CONFIDENTIEL le 2026-08-14 : le réceptacle est la fonction que cette
# condition fait entrer, et l'exiger de qui l'a déclinée bloquait sa sauvegarde —
# même faute que celle corrigée au contrôle 10, il ne lisait pas la condition.
# Lit CONFIDENTIEL dans `reglages/REPONSES`, par `sans_objet` : à `non`, la règle qu'il garde n'est pas
# entrée chez l'installateur, et le contrôle se saute en le disant. Une clé absente le fait jouer.
if sans_objet CONFIDENTIEL "réceptacle confidentiel"; then
    :
elif [ "${#_WS[@]}" -eq 0 ]; then
    # Sans cette branche, `find` sur un ensemble vide balaierait le dossier courant.
    echo "  ⏭  sans objet : aucun dossier de travail sur le disque (dit en tête de la passe)"
else
# `-not -name ".*"` ajouté le 2026-08-18 : le contrôle accusait les quatre `.vscode/` des
# domaines, un par dépôt, faux positif constant depuis leur apparition. Un dossier caché
# au niveau domaine est de l'outillage d'éditeur, pas un projet, et aucun document client
# n'y atterrit. Le laisser crier apprenait à ignorer la catégorie entière.
# LE DISCRIMINANT N'EST PLUS LA PROFONDEUR — aligné le 2026-09-08 (geste 1.15) sur le critère
# que le contrôle 28bis, juste en dessous, avait déjà établi le 2026-08-17 : « un réceptacle sous
# un autre réceptacle ». Motif MESURÉ : la bascule des dépôts a décalé la profondeur d'un cran.
# `_WS` valait `~/workstations/<DOMAINE>` avant le 2026-09-08, donc « profondeur 1 » désignait un PROJET ; il vaut
# maintenant `~/<DÉPÔT>`, et « profondeur 1 » désigne une APPLICATION dans `<DÉPÔT_A>` — dont le
# règlement § 5 interdit nommément qu'elle porte un réceptacle. Le contrôle a donc réclamé 12 fois
# ce que la règle défend, dès le premier passage post-bascule. Un contrôle qui crie douze fois
# apprend à ignorer sa catégorie entière, vrais signaux compris.
# Le critère juste, et il ne suppose aucune forme d'arbre : un dossier a besoin de SON réceptacle
# seulement si aucun ancêtre, racine du dépôt comprise, n'en porte déjà un.
# `journal` exclu le 2026-09-09, passe de ménage : le régime `ETAT.md` a posé un dossier `journal/`
# à la racine de chaque niveau basculé, et ce n'est pas un projet — aucun document client n'y
# atterrit, il ne porte que des `.jsonl` écrits par `etat.py`. Deux faux positifs dès le premier
# passage après la phase 3, même classe que les douze de la bascule des dépôts ci-dessus.
_noign=$(find -L "${_WS[@]}" -mindepth 1 -maxdepth 1 -type d \
    -not -name "_IGNORE" \
    -not -name "journal" \
    -not -name ".*" \
    2>/dev/null | while read -r d; do
        [ -d "$d/_IGNORE" ] && continue
        _p=$(dirname "$d"); _cv=0
        while [ "$_p" != "$HOME" ] && [ "$_p" != "/" ]; do
            [ -d "$_p/_IGNORE" ] && { _cv=1; break; }
            _p=$(dirname "$_p")
        done
        [ "$_cv" = "0" ] && echo "${d#$HOME/}"
      done)
if [ -n "$_noign" ]; then
    # AVERTIT depuis le 2026-08-14 : la fuite elle-même est gardée par le contrôle 10 et par
    # les alarmes de backup.sh — ici c'est un réceptacle manquant, défaut de rangement.
    warn "projet sans réceptacle \`_IGNORE/\` à sa racine (le premier document client y atterrirait en zone sauvegardée) :"
    echo "$_noign" | sed 's/^/       /' >&2
else ok "tous les projets ont leur réceptacle à leur racine"; fi
fi

echo "[selftest] 28bis. Réceptacle confidentiel REDONDANT sous un autre (avertissement)"
# CONTRÔLE INVERSE du 28, ajouté le 2026-08-17 (lot D de l'audit du jour). Le 28 vérifie qu'un
# réceptacle EXISTE à la racine de chaque projet ; personne ne vérifiait qu'il n'en existe PAS
# ailleurs. C'est l'angle mort qui a laissé sept dossiers `_IGNORE/` vivre au niveau des apps,
# dont quatre peuplés de douze fichiers client — le règlement l'interdit nommément (§3.2, « jamais
# au niveau d'une app ») et rien ne le signalait. Rangés le même jour, ce contrôle est ce qui
# empêche la redégradation : sans lui, le prochain dépôt recrée le défaut en silence.
#
# POURQUOI ÇA COMPTE, et ce n'est pas cosmétique : un `_IGNORE/` est hors sauvegarde. Un document
# client rangé au niveau d'une app y est donc en SEUL EXEMPLAIRE local, invisible depuis l'autre
# poste, et perdu avec la machine. Le défaut ne fuite pas, il fait disparaître.
#
# AVERTIT, jamais ne bloque : c'est un défaut de rangement, pas une désactivation. Bloquer la
# sauvegarde sur un dossier mal placé ferait payer un rangement par une journée de travail.
#
# LE DISCRIMINANT N'EST PAS LA PROFONDEUR — première version corrigée dans la même séance, le
# 2026-08-17, parce qu'elle a produit un faux positif dès son premier passage. Elle tenait pour
# fautif tout `_IGNORE/` plus bas que `<WS>/<projet>/`, en supposant une hiérarchie à deux niveaux.
# L'arbre réel porte des SOUS-PROJETS à trois niveaux, chacun avec son `CLAUDE.md` et son
# `DESIGN.md` : leur réceptacle est légitime, et le contrôle les accusait tous.
#
# Le critère juste est UN RÉCEPTACLE SOUS UN AUTRE RÉCEPTACLE. Il ne suppose aucune forme
# d'arborescence, et il décrit exactement le défaut : quand un projet porte déjà son `_IGNORE/`,
# celui d'en dessous est redondant, et un document qu'on y dépose est au mauvais endroit sans que
# rien ne le dise. À l'inverse, un projet niché SANS réceptacle au-dessus de lui a besoin du sien —
# le critère de profondeur le condamnait, celui-ci l'accepte.
# Lit CONFIDENTIEL dans `reglages/REPONSES`, par `sans_objet` : à `non`, la règle qu'il garde n'est pas
# entrée chez l'installateur, et le contrôle se saute en le disant. Une clé absente le fait jouer.
if sans_objet CONFIDENTIEL "réceptacle confidentiel"; then
    :
elif [ "${#_WS[@]}" -eq 0 ]; then
    echo "  ⏭  sans objet : aucun dossier de travail sur le disque (dit en tête de la passe)"
else
# Le compte de fichiers est donné parce qu'un dossier VIDE mal placé et un dossier PEUPLÉ mal
# placé ne se traitent pas pareil : le premier se supprime, le second se déménage après
# classement — et rien ne se supprime dans un `_IGNORE/` sans classement.
_misign=$(find -L "${_WS[@]}" -mindepth 2 -type d -name "_IGNORE" 2>/dev/null | while read -r d; do
        # un réceptacle au-dessus de celui-ci ? On remonte de parent en parent jusqu'à la
        # domaine : `find` seul ne sait pas exprimer « sous un autre dossier de même nom ».
        _p=$(dirname "$d"); _couvert=0
        # La garde `$HOME/workstations` est tombée avec la bascule du 2026-09-08 : les dépôts
        # sont sous `~/` directement, donc la remontée s'arrête AU dépôt. Sans le `break`, la
        # boucle testait `~/_IGNORE` — un réceptacle hors de tout dépôt aurait fait déclarer
        # « déjà couvert » tous les `_IGNORE/` du parc d'un coup.
        while [ "$_p" != "$HOME" ] && [ "$_p" != "/" ]; do
            _p=$(dirname "$_p")
            [ "$_p" = "$HOME" ] && break
            [ -d "$_p/_IGNORE" ] && { _couvert=1; break; }
        done
        [ "$_couvert" = "1" ] && echo "${d#$HOME/} ($(find -L "$d" -type f 2>/dev/null | wc -l | tr -d ' ') fichier(s), déjà couvert par ${_p#$HOME/}/_IGNORE)"
      done)
if [ -n "$_misign" ]; then
    warn "réceptacle \`_IGNORE/\` REDONDANT — un autre existe au-dessus, donc un document déposé ici est au mauvais endroit et en seul exemplaire local :"
    echo "$_misign" | sed 's/^/       /' >&2
else ok "aucun réceptacle confidentiel redondant sous un autre"; fi
fi

# CONTRÔLE 29 RETIRÉ le 2026-09-08 (geste 2.7, décision D-G) — il exigeait que toute mémoire
# surveillée déclare un plafond concordant avec `config.sh`. REMPLACÉ par construction :
# l'état projeté est borné par ce que le journal contient d'ouvert, et une contradiction sort
# par les événements « remplace » plutôt que par un seuil. Les plafonds de `config.sh` restent
# lus par le crochet ; c'est leur DÉCLARATION en tête de fichier qui cesse d'être contrôlée.

echo "[selftest] 29bis. Formes normalisées des fiches de mémoire automatique"
# Ce que la compétence `memoire-et-verite` § « Formes normalisées » prescrit, mesuré une fois
# par semaine. Posé le 2026-08-22, en réponse à « garantir que tout ce qui s'écrit est
# normalisé » : la garantie a deux moitiés, le gabarit au moment d'écrire et ce balayage.
#
# LE CONTRÔLE NE RECOPIE PAS LA TABLE de correspondance préfixe↔type : il la LIT dans la fiche.
# Une seconde table ici divergerait de la première, et c'est celle que personne ne relit qui
# gagnerait. Si la fiche ou sa table disparaît, le contrôle le DIT au lieu de passer au vert.
# AVERTIT : une fiche mal formée se corrige, elle ne perd rien.
_FICHE="$HOME/.claude/skills/memoire-et-verite/SKILL.md"
_map=$(grep -oE '^\| `[a-z]+_` \| `[a-z]+` \|' "$_FICHE" 2>/dev/null | tr -d '`|' | awk '{print $1" "$2}')
if [ -z "$_map" ]; then
    warn "table préfixe↔type introuvable dans memoire-et-verite — ce contrôle est muet (fiche déplacée, ou table reformatée)"
else
    _f29=0
    for _m in "$MEM"/*.md; do
        _b="$(basename "$_m")"
        case "$_b" in user_*|proj_*|env_*|ref_*) ;; *) continue ;; esac
        _pre="${_b%%_*}_"
        _att=$(printf '%s\n' "$_map" | awk -v p="$_pre" '$1==p {print $2; exit}')
        [ -n "$_att" ] || continue
        _got=$(grep -m1 -E '^[[:space:]]+type:' "$_m" 2>/dev/null | sed 's/.*type:[[:space:]]*//' | tr -d ' \r')
        if [ -z "$_got" ]; then
            warn "fiche de mémoire sans \`type:\` dans son frontmatter : ${_m#$HOME/}"; _f29=1
        elif [ "$_got" != "$_att" ]; then
            warn "fiche de mémoire dont le NOM et le TYPE se contredisent : ${_m#$HOME/} — le préfixe \`$_pre\` annonce \`$_att\`, le frontmatter dit \`$_got\`"; _f29=1
        fi
        grep -qE '^description:' "$_m" 2>/dev/null || { warn "fiche de mémoire sans \`description:\` — elle ne sera rappelée par rien : ${_m#$HOME/}"; _f29=1; }
    done
    [ "$_f29" = 0 ] && ok "toute fiche de mémoire automatique porte une description, et son type s'accorde à son préfixe"
fi

echo "[selftest] 30. Rappel échu : le démarrage le sort-il vraiment ?"
# Motif (2026-07-26) : le bloc de rappels est resté MUET de sa création au 2026-07-26.
# `REMINDERS.md` n'avait pas de retour à la ligne final et `while IFS= read -r` abandonne
# alors sa dernière ligne — qui est, par construction, le rappel le plus récent, donc le
# seul actif. La vérification d'origine (2026-07-03) ne testait que le cas NÉGATIF — un
# rappel à échéance future n'est pas affiché — jamais le cas positif. Ce contrôle teste le
# cas positif, seul capable d'attraper la classe entière (cf. DESIGN « Les sondes du démarrage »).
# AVERTIT depuis le 2026-08-14, arbitré par l'utilisateur : la dette de sécurité a son
# propre bloc, et le contrôle 4 garde le bilan de démarrage lui-même — un rappel muet
# encombre, il ne désarme pas une garde de sauvegarde.
_r=0
# (a) Anti-régression : la garde de dernière ligne est-elle toujours dans la boucle ?
grep -qF 'read -r rline || [ -n "$rline" ]' "$SELF/boot-check.sh" \
    || { warn "garde de dernière ligne absente de la boucle des rappels (boot-check.sh) — un fichier sans retour à la ligne final reperdrait son rappel le plus récent"; _r=1; }
# (b) Cas positif, sur données réelles : tout rappel dont l'échéance est atteinte doit
#     apparaître dans le bilan injecté. Sans rappel échu au moment du contrôle, (b) est
#     inapplicable — on le dit, on ne le maquille pas en succès.
_claudeos_py_due() {
python3 - "$MEM/REMINDERS.md" <<'PY' 2>/dev/null || echo 0
import re, sys, datetime
try: t = open(sys.argv[1], encoding="utf-8").read()
except OSError: print(0); raise SystemExit
today = datetime.date.today()
n = sum(1 for d in re.findall(r"^- (\d{4}-\d{2}-\d{2}) *\|", t, re.M)
        if datetime.date.fromisoformat(d) <= today)
print(n)
PY
}
_due=$(_claudeos_py_due)
if [ "${_due:-0}" -gt 0 ]; then
    # DÉFAUT CORRIGÉ le 2026-08-22, trouvé en faisant échouer ce contrôle exprès au moment de
    # le transplanter : il comptait les ⏰ dans TOUT le contexte de démarrage. Or la consigne
    # de démarrage cite « ⏰ rappels » en prose pour dire au modèle quels signaux relayer. Le
    # compte valait donc au moins 1 en permanence, et le contrôle était MUET PAR CONSTRUCTION :
    # boot-check pouvait cesser de sortir les rappels sans que rien ne le dise. Vérifié sur
    # pièce — bloc des rappels neutralisé, le contrôle annonçait toujours « effectivement
    # sorti(s) ». On ne compte plus que les ⏰ en DÉBUT DE LIGNE, forme des alertes ; la
    # citation en prose vit en milieu de phrase. Rien du libellé de boot-check n'est recopié.
    _seen=$(printf '%s' "$_BOOTOUT" | python3 -c '
import json, sys
t = json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]
print(sum(1 for l in t.splitlines() if l.startswith("⏰")))
' 2>/dev/null || echo 0)
    [ "${_seen:-0}" -eq 0 ] && { warn "$_due rappel(s) échu(s) dans REMINDERS.md mais AUCUN dans le bilan de démarrage — le bloc est muet"; _r=1; }
    [ "$_r" = 0 ] && ok "garde de dernière ligne en place + $_due rappel(s) échu(s) effectivement sorti(s) au démarrage"
else
    [ "$_r" = 0 ] && ok "garde de dernière ligne en place (aucun rappel échu à ce jour — cas positif non exercé)"
fi

# CONTRÔLE 31 RETIRÉ le 2026-08-05 — il cherchait un plafond du règlement racine codé en dur
# dans une fiche de compétence. Motif d'origine réel : la fiche d'audit affirmait 14 000
# caractères pour un règlement qui avait abandonné tout plafond, et aurait fait conclure à un
# dépassement là où le système était conforme. Retiré parce qu'il gardait UN incident daté sous
# une forme littérale — quatre chiffres sur la même ligne qu'un mot parmi trois — que toute
# reformulation désarme. Ce qui protège vraiment de cette classe reste écrit : un fait calculable
# ne se recopie pas, il se lit à sa source (compétence `memoire-et-verite`), et les seuils vivent
# dans ce script et nulle part ailleurs.

# Contrôle 32 (« tout domaine avec une mémoire a une reprise ») RETIRÉ le 2026-09-22 avec les
# HANDOFF.md, supprimés le 2026-09-22 : toutes les racines portent ETAT.md, il était vert par construction.

echo "[selftest] 33. Tout dossier routé par un CLAUDE.md local existe sur le disque"
# Motif (2026-07-27) : les instructions d'un domaine de l'auteur posent un document de référence
# comme obligatoire pour chaque application, et deux applications routées n'en avaient pas. La
# liste auditée est celle de la table de ROUTAGE du projet, pas celle du disque : c'est le
# routage qui promet qu'une app est traitable, donc c'est lui qui crée la dette.
# CE QUE CE CONTRÔLE NE FAIT PLUS, et le paragraphe qui l'affirmait était faux jusqu'au
# 2026-08-07 : il ne lit AUCUN marqueur de tolérance. Il a porté un mécanisme d'exception
# déclarée en tête de la mémoire d'une app — « EN SOMMEIL », « EN CONCEPTION », « EN OUVERTURE » —
# emporté par la réécriture du 2026-08-06 avec l'exigence de document de référence qu'il gardait.
# Ce qui reste ici est la seule question « le dossier existe-t-il », et elle n'admet pas
# d'exception. Une mémoire qui déclare encore un de ces marqueurs ne se fait donc tolérer par
# personne : c'est l'audit qui porte cette classe depuis, pas ce contrôle.
# GÉNÉRALISÉ le 2026-08-06, à la demande de l'utilisateur. Le contrôle ne visait qu'un seul
# projet client : partout ailleurs, un routage pouvait promettre un dossier inexistant sans que
# rien ne le dise. Le motif d'origine s'appuyait sur la convention de nommage de ce projet ;
# le motif générique s'appuie sur la CONVENTION D'ÉCRITURE, vérifiée sur pièce avant réécriture —
# une table de routage écrit sa cible entre guillemets obliques avec une barre oblique finale
# (`NOM_DU_DOSSIER/`). C'est un meilleur discriminant que l'ancien, pas un moins bon :
# la barre oblique reste ce qui distingue un dossier d'une liste de données homonyme, et les
# guillemets excluent la prose. Portée : 24 fichiers de routage au lieu d'un.
_ghost=""
_routes=0
# Noms de dossiers qui relèvent de la CONVENTION et non du routage : les citer n'est pas
# promettre qu'ils existent. `_IGNORE/` a déjà son propre contrôle (#28) — le compter ici
# ferait crier deux contrôles pour un seul défaut.
_conventions="_IGNORE docs scripts specs plans extracted src tools assets rapports base-documentaire msapp"
while IFS= read -r _cm; do
    _dir="$(dirname "$_cm")"
    # SEULEMENT les lignes de TABLEAU. Première version : tout dossier entre guillemets
    # obliques, où qu'il soit. Elle a rendu cinq défauts dont quatre faux — des exemples de
    # convention de nommage cités en prose (`2023-2024/`) et une auto-référence d'un fichier
    # à son propre dossier. Le motif d'origine ne tenait pas grâce à la barre oblique seule,
    # mais parce qu'il lisait une TABLE DE ROUTAGE : c'est la table qui promet, pas la prose.
    for _t in $(grep -E '^[[:space:]]*\|' "$_cm" 2>/dev/null \
                | grep -oE '`[A-Za-z0-9_.-]+/`' | tr -d '`/' | sort -u); do
        case " $_conventions " in *" $_t "*) continue ;; esac
        _routes=$((_routes+1))
        [ -d "$_dir/$_t" ] || _ghost="${_ghost}${_dir#"$HOME"/}/$_t"$'\n'
    done
done < <([ "${#_WS[@]}" -gt 0 ] && find -L "${_WS[@]}" -name 'CLAUDE.md' -type f 2>/dev/null | sort)

if [ -n "$_ghost" ]; then
    # Avertissement et non échec : un dossier manquant est un vrai défaut de routage, mais
    # interdire d'enregistrer son travail pour autant ferait payer une erreur de carte par
    # une perte de travail.
    warn "dossier routé depuis un \`CLAUDE.md\` local mais ABSENT du disque — le routage promet ce qui n'existe pas :"
    printf '%s' "$_ghost" | sed 's/^/       /' >&2
else
    ok "$_routes dossier(s) routé(s) vérifié(s) sur l'ensemble des dépôts clients"
fi

# La moitié « toute app routée porte son document de référence » a été retirée le 2026-08-05 :
# c'était de la dette documentaire métier. Conséquence toujours vraie et à connaître : la mention
# « EN CONCEPTION » que porte la mémoire d'une app, et qui affirme que « le contrôle qui l'exige
# lit cette ligne », ne sert plus de tolérance à rien — plus personne ne la lit.

echo "[selftest] 37. Cascade d'instructions — un terme proscrit par un niveau n'est prescrit par aucun niveau sous lui"
# Classe de défaut que rien ne gardait, constatée le 2026-08-03 : deux niveaux de la cascade se
# contredisaient sur le nom d'une propriété d'écran de chargement (`AutoStart`, le niveau app
# disant `Start` qui n'existe pas), et c'est le niveau LOCAL qui prime — donc le faux gagnait.
# Aucun mécanisme ne regardait la cohérence d'une valeur entre deux niveaux.
#
# Ce que le contrôle exploite : quand un niveau tranche un nom, il l'écrit sous une forme
# négative explicite — « jamais `Start` », « aucune propriété `Start` n'existe ». Cette forme
# est la déclaration de l'interdit, donc elle est lisible par une machine. Le contrôle extrait
# les termes ainsi proscrits, puis vérifie qu'aucun document situé SOUS le niveau qui les
# proscrit ne les prescrit dans du code encadré.
#
# Limite à énoncer, elle est réelle : il ne voit que les interdits écrits sous cette forme.
# Un désaccord entre deux niveaux qu'aucun des deux n'a tranché lui échappe. Il réduit la
# surface, il ne certifie pas la cascade.
#
# AVERTIT : une contradiction de cascade fait répondre faux, elle ne désactive ni ne détruit
# rien, et elle se corrige dès qu'on la voit.
_r=0
_claudeos_py_casc() {
CLAUDEOS_DOCS_REF="$_DOCS_REF" python3 - ${_WS[@]+"${_WS[@]}"} <<'PY' 2>/dev/null
import os, re, sys

roots = sys.argv[1:]     # racines des dossiers de travail (`claudeos_ws_roots`)
# Les chemins rapportés sont relatifs au dossier personnel et non à « la » racine : il y en a
# désormais plusieurs, et une variable de boucle qui fuit aurait daté le message de la dernière.
H = os.path.expanduser("~")
# Documents prescriptifs de la cascade, du plus général au plus local : `CLAUDE.md`, plus les
# motifs de `reglages/DOCS_REFERENCE` que le shell passe par `CLAUDEOS_DOCS_REF`. Un dossier d'app
# peut porter plusieurs documents de référence suffixés par son nom : sans un motif à joker, ces
# gardes cessaient de balayer un document prescriptif sans rien dire (2026-08-18) — un garde qui
# perd sa couverture ne crie pas, il se tait.
import fnmatch
MOTIFS = ["CLAUDE.md"] + [m.strip() for m in os.environ.get("CLAUDEOS_DOCS_REF", "").splitlines() if m.strip()]
# « jamais `X` » / « aucune propriété `X` n'existe » / « `X` n'existe pas » / « pas `X` »
BAN = [
    re.compile(r"jamais\s+`([A-Za-z_][A-Za-z0-9_]*)`"),
    re.compile(r"aucune\s+propri[eé]t[eé]\s+`([A-Za-z_][A-Za-z0-9_]*)`\s+n'existe"),
    re.compile(r"`([A-Za-z_][A-Za-z0-9_]*)`\s*,?\s*(?:propri[eé]t[eé]\s+)?qui\s+n'existe\s+pas"),
]

docs = {}
for root in roots:
  for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in ("_IGNORE", "extracted", ".git")]
    for fn in filenames:
        if any(fnmatch.fnmatch(fn, m) for m in MOTIFS):
            p = os.path.join(dirpath, fn)
            try:
                docs[p] = open(p, encoding="utf-8").read()
            except OSError:
                pass

# Un terme proscrit par le document D vaut pour tout document situé dans un sous-dossier de D.
bans = {}          # terme -> (dossier du document qui le proscrit, chemin de ce document)
for p, txt in docs.items():
    for rx in BAN:
        for m in rx.finditer(txt):
            bans.setdefault(m.group(1), (os.path.dirname(p), p))

# Homonymes — correctif du 2026-08-07, faux positif diagnostiqué et corrigé le jour même.
# `Value` était proscrit comme propriété de sortie d'un contrôle (dont la sortie s'appelle
# `Text`) et prescrit comme nom de colonne d'un patron référentiel. Deux objets, un seul mot.
# Le contrôle appariait les deux et criait sur de la documentation exacte — et une alarme
# rouge en permanence apprend à ignorer la catégorie entière.
# Discriminant : si le document QUI PROSCRIT prescrit lui-même le terme ailleurs, dans une
# ligne non négative, alors le terme porte deux sens dans ce vocabulaire et l'interdit n'est
# pas global. On l'écarte, en le disant. Le cas légitime n'est pas touché : le document qui
# proscrivait `Start` ne le prescrit nulle part.
def prescrit_dans(txt, term):
    rx = re.compile(r"`[^`]*\b" + re.escape(term) + r"\b\s*[:=][^`]*`")
    for m in rx.finditer(txt):
        ls = txt.rfind("\n", 0, m.start()) + 1
        le = txt.find("\n", m.end())
        line = txt[ls:le if le != -1 else len(txt)]
        if not re.search(r"jamais|n'existe|pas\s+`|proscrit|interdit|Corrig", line):
            return True
    return False

homonymes = []
for term in list(bans):
    _, ban_file = bans[term]
    if prescrit_dans(docs.get(ban_file, ""), term):
        homonymes.append((term, os.path.relpath(ban_file, H)))
        del bans[term]

out = []
for term, (ban_dir, _bf) in bans.items():
    # Prescription = le terme apparaît encadré et suivi d'un signe d'affectation ( : ou = ),
    # forme sous laquelle ces documents énoncent une valeur de propriété.
    presc = re.compile(r"`[^`]*\b" + re.escape(term) + r"\b\s*[:=][^`]*`")
    for p, txt in docs.items():
        d = os.path.dirname(p)
        if not (d == ban_dir or d.startswith(ban_dir + os.sep)):
            continue          # hors de la portée du niveau qui proscrit
        if p.startswith(ban_dir) and os.path.dirname(p) == ban_dir:
            pass              # le niveau qui proscrit peut se citer lui-même
        for m in presc.finditer(txt):
            frag = m.group(0)
            # La ligne qui proscrit cite forcément le terme : on écarte les lignes négatives.
            line_start = txt.rfind("\n", 0, m.start()) + 1
            line_end = txt.find("\n", m.end())
            line = txt[line_start:line_end if line_end != -1 else len(txt)]
            if re.search(r"jamais|n'existe|pas\s+`|proscrit|interdit|Corrig", line):
                continue
            out.append("%s prescrit `%s`, proscrit par %s" % (
                os.path.relpath(p, H), term, os.path.relpath(ban_dir, H) or "."))
            break

for line in sorted(set(out))[:10]:
    print(line)
for term, f in sorted(set(homonymes)):
    print("HOMONYME\t%s\t%s" % (term, f))
PY
}
_casc=$(_claudeos_py_casc)
_homo="$(printf '%s\n' "$_casc" | sed -n 's/^HOMONYME\t//p')"
_casc="$(printf '%s\n' "$_casc" | grep -v '^HOMONYME' | sed '/^$/d')"
if [ -n "$_casc" ]; then
    warn "contradiction(s) de cascade — le niveau local prime, donc c'est le faux qui gagne :"
    echo "$_casc" | sed 's/^/       /' >&2
    _r=1
fi
if [ -n "$_homo" ]; then
    echo "  ℹ️  terme(s) écartés comme homonymes — proscrits et prescrits par le même document,"
    echo "$_homo" | awk -F'\t' '{printf "       `%s` dans %s\n", $1, $2}'
    echo "       donc l'interdit n'est pas global. Non compté comme contradiction."
fi
[ "$_r" = 0 ] && ok "aucun terme proscrit par un niveau n'est prescrit sous lui"

echo "[selftest] 40. Capacité déclarée opérante mais non invocable"
# BLOQUANT. C'est la classe que la fiche des contrôles range explicitement dans les blocages :
# une règle existe, le système croit l'appliquer, elle ne se charge jamais — rien n'échoue, donc
# seul un blocage l'attrape. Écrit en avertissement le 2026-08-07 le temps que son unique
# instance (`handoff`) soit arbitrée, puis passé bloquant le même soir dès qu'elle l'a été.
#
# La classe : une compétence que la référence de design ou une fiche désigne comme porteuse
# d'un geste, alors que son frontmatter porte `disable-model-invocation: true` et qu'aucune
# fiche ne dit à l'assistant de la proposer. Les deux côtés sont cohérents, rien n'échoue, et
# la capacité n'est jamais atteinte. Trois défauts de cette famille ont été trouvés dans le
# seul audit du 2026-08-07, tous nés de la réduction du rituel de clôture du 2026-07-27, et
# aucun par balayage — un par une question de l'utilisateur, deux par hasard.
#
# Ce qui débloque légitimement : soit une fiche dit de proposer la compétence à l'utilisateur
# (le geste est alors cherché, pas le nom — un nom cité peut n'être qu'une mention), soit
# l'interdiction d'auto-invocation est retirée, soit le document cesse de lui donner le rôle.
# Les trois sont des décisions ; la seule chose interdite est de laisser les trois en l'état.
_c40=""
for _sk in "$HOME"/.claude/skills/*/SKILL.md; do
    [ -f "$_sk" ] || continue
    grep -q '^disable-model-invocation: *true' "$_sk" || continue
    _n="$(basename "$(dirname "$_sk")")"
    # Cité comme opérant par la conception ou une fiche ?
    # `--exclude-dir` : sans lui, le grep trouve la compétence dans SON PROPRE corps et
    # déclare toute compétence « citée », ce qui rend le contrôle vert par construction
    # (2026-08-09, avec le déplacement du périmètre des fiches vers les compétences).
    _cite="$(grep -rl --exclude-dir="$_n" -- "$_n" "$HOME/.claude/DESIGN.md" "$HOME/.claude/skills/" 2>/dev/null | tr '\n' ' ')"
    [ -n "$_cite" ] || continue
    # Échappatoire légitime : une fiche dit de la PROPOSER à l'utilisateur. On cherche le
    # geste, pas le nom — un nom cité peut n'être qu'une mention.
    grep -rqE --exclude-dir="$_n" "(proposer|inviter|lancer|invoquer).{0,80}$_n|/$_n" "$HOME/.claude/skills/" 2>/dev/null && continue
    _c40="$_c40$_n (cité par : $_cite)"$'\n'
done
if [ -n "$(printf '%s' "$_c40" | tr -d '[:space:]')" ]; then
    ko "compétence(s) déclarées opérantes mais non invocables — le système croit la capacité active :"
    printf '%s' "$_c40" | sed '/^$/d; s/^/       /' >&2
    echo "       → soit une fiche dit de la proposer, soit retirer disable-model-invocation," >&2
    echo "         soit retirer son rôle du document qui la cite. Ne pas laisser les trois en l'état." >&2
else
    ok "aucune capacité déclarée opérante sans chemin d'invocation"
fi

echo "[selftest] 41. Fraîcheur des places de marché de greffons"
# AVERTIT — un greffon en retard encombre, il ne désactive rien. Motif : le clone du dépôt
# `power-platform-skills` était figé depuis cinq semaines quand les deux autres se
# rafraîchissaient le jour même. Le rafraîchissement tournait, mais pas pour celui-là : une
# cadence morte, pas lente, et rien ne pouvait le voir. On ne compare pas à une date absolue
# — on compare les places de marché ENTRE ELLES, ce qui distingue « personne ne s'est
# rafraîchi depuis longtemps » (normal hors ligne) de « un seul a décroché » (le défaut).
_MKT_LAG_DAYS=14
_km="$HOME/.claude/plugins/known_marketplaces.json"
if [ ! -f "$_km" ]; then
    ok "aucune place de marché déclarée (rien à contrôler)"
else
    _claudeos_py_c41() {
python3 - "$_km" "$_MKT_LAG_DAYS" <<'PY' 2>/dev/null
import json, sys, datetime
p, lag = sys.argv[1], int(sys.argv[2])
try:
    d = json.load(open(p, encoding="utf-8"))
except Exception:
    sys.exit(0)
items = d.get("marketplaces", d) if isinstance(d, dict) else {}
dates = {}
for name, v in (items.items() if isinstance(items, dict) else []):
    if not isinstance(v, dict):
        continue
    raw = v.get("lastUpdated")
    if raw is None:
        continue
    try:
        ts = float(raw)
        dt = datetime.datetime.fromtimestamp(ts / 1000 if ts > 1e11 else ts)
    except (TypeError, ValueError):
        try:
            dt = datetime.datetime.fromisoformat(str(raw).replace("Z", "+00:00")).replace(tzinfo=None)
        except ValueError:
            continue
    dates[name] = dt
if len(dates) < 2:
    sys.exit(0)
newest = max(dates.values())
for name, dt in sorted(dates.items()):
    behind = (newest - dt).days
    if behind >= lag:
        print(f"{name} : {behind} j derrière la plus fraîche ({dt:%Y-%m-%d})")
PY
    }
    _c41="$(_claudeos_py_c41)"
    if [ -n "$_c41" ]; then
        warn "place(s) de marché décrochée(s) de plus de $_MKT_LAG_DAYS jours sur les autres :"
        printf '%s\n' "$_c41" | sed 's/^/       /' >&2
        echo "       → rafraîchir le clone, ou diagnostiquer pourquoi lui seul ne se rafraîchit pas." >&2
    else
        ok "places de marché de greffons alignées entre elles"
    fi
fi

# --- 41bis. LE CACHE QUI SERT CONTRE LA COPIE TIRÉE, PAR LE CONTENU ET NON PAR LA VERSION.
# Prolonge le 41 et n'ouvre PAS de contrôle : le 41 mesure si le clone se rafraîchit, celui-ci
# mesure si le rafraîchissement ARRIVE JUSQU'À CE QUI EST SERVI. Les deux sont indépendants, et
# c'est le second qui a mordu.
#
# CE QU'IL ATTRAPE, payé le 2026-09-10 sur un greffon de la place de marché officielle. Un greffon vit en DEUX exemplaires :
# `plugins/marketplaces/…`, tiré par `autoUpdate`, et `plugins/cache/<place>/<greffon>/<clé>/`,
# celui qui est réellement CHARGÉ — reconnaissable à son marqueur `.in_use`. Deux régimes de clé
# de cache cohabitent, et un seul est sûr :
#   - clé = EMPREINTE (12 hexa) : un contenu qui bouge produit une clé neuve, donc une
#     réextraction. Rien à surveiller.
#   - clé = NUMÉRO DE VERSION : si l'amont livre du contenu SANS monter sa version, la clé ne
#     change pas et le cache reste figé POUR TOUJOURS. Mesuré ce jour-là : 15 fichiers
#     différents, 1 139 lignes présentes seulement en amont, et un fichier de référence ENTIER
#     absent du cache. Une session de projet a travaillé dessus sans le savoir.
# ET LA VOIE DOCUMENTÉE NE LE VOIT PAS : `claude plugin update` répond « already at the latest
# version (3.0.3) ». Il compare les NUMÉROS. C'est pour ça que ce contrôle compare le CONTENU.
#
# L'AMONT SE RÉSOUT PAR LE NOM DÉCLARÉ dans `plugin.json`, jamais par le nom de dossier : sur ce
# poste, le cache `code-apps-preview` correspond au dossier `code-apps`, et un greffon peut
# être la racine même de sa place de marché (cas d'`andrej-karpathy-skills`, désinstallé le
# 2026-09-22). Trois formes, un seul discriminant qui marche.
#
# CE QU'IL NE PEUT PAS JUGER, et il le DIT plutôt que de le taire : un greffon déclaré dans une
# place de marché mais servi d'ailleurs n'a aucune copie amont sur le disque — `superpowers` est
# dans ce cas. Un contrôle qui tairait l'étendue de ce qu'il ignore laisserait croire à une
# couverture totale.
# SON INTITULÉ N'EST PAS NUMÉROTÉ, ET CE N'EST PAS UN CONTOURNEMENT DU COMPTEUR : le cliquet
# `CLAUDEOS_CLIQUET_CONTROLES` compte les contrôles, motif `^echo "\[selftest\] [0-9]`, et ceci
# est une SECONDE MESURE À L'INTÉRIEUR du 41, pas un 22ᵉ contrôle. Le 41 demande « le clone se
# rafraîchit-il », celle-ci « le rafraîchissement arrive-t-il jusqu'à ce qui est chargé ». Leur
# verdict est commun : un clone frais dont le cache est figé n'est pas un greffon à jour.
# Numéroté à part, il aurait fallu financer un contrôle par un troc — pour une mesure qui ne
# tient pas debout sans celle d'au-dessus.
echo "[selftest]  · 41 suite — le cache qui sert, contre la copie tirée, par le contenu"
_claudeos_py_c41b() {
python3 - <<'PY' 2>/dev/null
import json, os, glob, re, subprocess
R = os.path.expanduser("~/.claude/plugins")
SHA = re.compile(r"^[0-9a-f]{12}$")
amont = {}
for pj in glob.glob(R + "/marketplaces/*/**/.claude-plugin/plugin.json", recursive=True):
    try:
        nom = json.load(open(pj, encoding="utf-8")).get("name")
    except Exception:
        continue
    if nom:
        amont.setdefault(nom, os.path.dirname(os.path.dirname(pj)))
ecarts, muets, juges = [], [], 0
for d in sorted(glob.glob(R + "/cache/*/*/*/")):
    if not os.path.exists(os.path.join(d, ".in_use")):
        continue
    # `.orphaned_at` AJOUTÉ le 2026-09-17 : une version REMPLACÉE garde son `.in_use` et n'est
    # plus servie — le harnais la marque orpheline. Faux positif MESURÉ ce jour-là : mcp-apps
    # criait 15 écarts sur sa 1.0.0, orpheline depuis le 2026-09-14, alors que la version
    # INSTALLÉE ET SERVIE est la 1.2.0 — vérifié dans installed_plugins.json — et qu'elle est
    # identique à l'amont, zéro écart. Le contrôle comparait une version que plus rien ne charge.
    if os.path.exists(os.path.join(d, ".orphaned_at")):
        continue
    cle = os.path.basename(d.rstrip("/"))
    if SHA.match(cle):
        continue                      # clé par empreinte : se réextrait seule
    try:
        nom = json.load(open(os.path.join(d, ".claude-plugin", "plugin.json"),
                             encoding="utf-8")).get("name")
    except Exception:
        nom = None
    src = amont.get(nom)
    if not src:
        muets.append("%s (%s) : aucune copie amont sur le disque" % (nom or "?", cle))
        continue
    juges += 1
    r = subprocess.run(["diff", "-rq", d.rstrip("/"), src], capture_output=True, text=True)
    lignes = [l for l in r.stdout.splitlines()
              if ".in_use" not in l and "/.git" not in l and not l.endswith(": .git")]
    if lignes:
        ecarts.append("%s (%s) : %d ecart(s) de contenu a version identique" % (nom, cle, len(lignes)))
for e in ecarts:
    print("ECART " + e)
for m in muets:
    print("MUET " + m)
print("BILAN %d juge(s), %d non jugeable(s)" % (juges, len(muets)))
PY
}
_c41b="$(_claudeos_py_c41b)"
if ! printf '%s' "$_c41b" | grep -q '^BILAN'; then
    warn "contrôle du cache de greffons : mesure RATÉE, aucun bilan rendu — ne pas lire comme un vert"
elif printf '%s' "$_c41b" | grep -q '^ECART'; then
    warn "greffon servi PÉRIMÉ — le cache diffère de la copie tirée à version identique :"
    printf '%s\n' "$_c41b" | grep '^ECART' | sed 's/^ECART /       /' >&2
    echo "       → recopier l'amont par-dessus le cache en préservant .in_use. \`claude plugin" >&2
    echo "         update\` NE SUFFIT PAS : il compare les numéros de version, pas le contenu." >&2
    printf '%s\n' "$_c41b" | grep '^MUET' | sed 's/^MUET /       non jugeable : /' >&2
else
    ok "$(printf '%s' "$_c41b" | grep '^BILAN' | sed 's/^BILAN /caches de greffons alignés sur leur amont — /')"
    printf '%s' "$_c41b" | grep '^MUET' | sed 's/^MUET /       non jugeable : /' >&2 || true
fi

echo "[selftest] 42. Compétences empruntées — origine épinglée et composition intacte"
# ADAPTÉ AU TEMPLATE le 2026-10-01 (A5). Chez l'auteur, ce contrôle exige une URL amont dans la
# bannière de chaque emprunt et un marqueur de dérive mensuel frais. Ici l'origine d'un emprunt est
# sa ligne de `engine/config/SKILLS_AMONT` — dépôt et commit épinglé —, et `engine/skills-amont.sh`
# le compose : la dérive de l'amont n'atteint pas le poste, qui ne suit jamais `main`. AVERTIT.
# Deux moitiés, sans appel réseau :
# (a) toute compétence qui se dit empruntée a sa ligne dans la table — sinon rien ne dit d'où vient
#     son corps, et rien ne le recompose ;
# (b) chaque optionnelle retenue est présente et égale à sa composition, recomposée depuis le cache
#     par `skills-amont.sh --verifier`, seule implémentation de la composition. Un cache absent rend
#     la compétence NON JUGÉE, dit comme tel : ce n'est pas un vert.
_c42=""
_T42="$SELF/config/SKILLS_AMONT"
for _sk in "$HOME"/.claude/skills/*/SKILL.md; do
    [ -f "$_sk" ] || continue
    _d42="$(dirname "$_sk")"; _n="$(basename "$_d42")"
    [ "$_n" = "os-audit" ] && continue   # parle des emprunts sans en être un
    grep -qE '\*\*Emprunt|\*\*Adaptation ClaudeOS' "$_sk" || [ -f "$_d42/LICENSE.amont" ] || continue
    awk -v n="$_n" '!/^[[:space:]]*(#|$)/ && $1 == n { t = 1 } END { exit !t }' "$_T42" 2>/dev/null \
        || _c42="$_c42$_n : emprunt sans ligne dans engine/config/SKILLS_AMONT"$'\n'
done
_v42="$(bash "$SELF/skills-amont.sh" --verifier 2>&1)"; _r42=$?
case "$_r42" in
    0) ;;
    1|3) _c42="$_c42$(printf '%s\n' "$_v42" | grep -E '⛔|⚠' | sed 's/^\[amont\] //')"$'\n' ;;
    *) _c42="${_c42}skills-amont.sh --verifier : mesure RATÉE (rc=$_r42) — $(printf '%s' "$_v42" | tail -n 1)"$'\n' ;;
esac
if [ -n "$(printf '%s' "$_c42" | tr -d '[:space:]')" ]; then
    warn "compétences empruntées :"
    printf '%s' "$_c42" | sed '/^$/d; s/^/       /' >&2
else
    ok "emprunts épinglés dans SKILLS_AMONT, compositions égales à leur commit"
fi

echo "[selftest] 45. Pointeurs de la carte — ETAT.md « Où trouver » (avertissement, ne bloque pas)"
# ÉCRIT LE 2026-08-09, sur le défaut du jour : la couche curatée pointait quinze fois vers
# `~/.claude/fiches/`, supprimé le matin même par la conversion des règles situationnelles en
# compétences. Or cette couche est la carte que le règlement fait consulter AVANT tout travail de
# fond : ses pointeurs morts n'ont fait échouer aucun script, ils ont simplement envoyé la
# session dans le vide. La classe se reproduira à chaque réorganisation — c'est ce qui la rend
# mécanisable, et c'est pour ça que le contrôle existe plutôt qu'un rappel dans une procédure.
# AVERTIT : un pointeur mort encombre la carte, il ne désactive aucune règle (une règle non
# routée, elle, bloque — voir contrôle 23).
# CE QU'IL JUGE, et rien d'autre : les compétences citées (`compétence <slug>` / `skill <slug>` /
# `skills/<slug>`) doivent exister dans `~/.claude/skills/`, et les chemins cités doivent se
# résoudre. CE QU'IL NE JUGE PAS, et le dit en clair dans sa sortie : les renvois de section
# (un renvoi de section), les repères de journal (`JOURNAL 2026-06-28`), les notes d'un coffre de notes
# (préfixe `wiki `, qui vit hors de l'arbre sauvegardé) et les noms
# nus sans chemin ni extension. Le compte des non-jugés est AFFICHÉ : un contrôle qui tairait
# l'étendue de ce qu'il ignore laisserait croire à une couverture totale.
# SORTI EN MODULE le 2026-09-10, geste D1 : `engine/resolveur_pointeurs.py`. Le calcul de
# resolution est desormais a UN SEUL endroit, importe aussi par `etat.py` qui REFUSE a
# l'ecriture un pointeur dont la cible ne resout pas. Motif : deux implantations du meme
# calcul derivent, et la derive produit un controle qui dit vert quand l'autre dit rouge.
# Le contrat de sortie est INCHANGE — les deux sorties ont ete comparees au caractere, sur
# le cas propre ET sur un cas fautif, avant le remplacement.
_ptr=$(python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolveur_pointeurs.py" "$HOME/.claude/ETAT.md" "$MEM" 2>/dev/null)
_bilan=$(printf '%s\n' "$_ptr" | grep -m1 '^#')
_ptr_ko=$(printf '%s\n' "$_ptr" | grep -v '^#' | grep -v '^[[:space:]]*$')
if [ -z "$_bilan" ] || [ "$_bilan" = "#VIDE" ]; then
    warn "pointeurs de la carte : AUCUNE citation lue dans ~/.claude/ETAT.md « Où trouver » — mesure ratée, ce contrôle est muet (fichier absent, couche 🧭 vidée, ou forme des citations changée)"
elif [ -n "$_ptr_ko" ]; then
    warn "pointeurs de la carte d'ETAT.md qui ne résolvent pas — ${_bilan#\#BILAN } :"
    printf '%s\n' "$_ptr_ko" | sed 's/^/       /' >&2
else
    ok "tous les pointeurs de la carte résolvent — ${_bilan#\#BILAN }"
fi

# CONTRÔLE 44 RETIRÉ le 2026-08-07, le soir même de son écriture. Il mesurait ce que le 21 ne
# comptait pas — descriptions de compétences et corps chargés d'office — et il avait raison sur
# le fait : le coût réel était d'environ 35 000 caractères contre 21 000 affichés. Mais la
# décision prise le même soir rend la mesure sans emploi : on ne borne plus un volume, on
# surveille une accumulation sans décision. Un chiffre qu'on n'arbitre plus est du bruit, et il
# invitait à des dégraissages qui déplacent le texte d'un fichier chargé vers un autre au lieu
# de le supprimer. Le fait qu'il a établi reste écrit dans le rapport d'audit du 2026-08-07.
echo "[selftest] 47. Personnalisation — le règlement porte-t-il encore des marques de gabarit ? (avertissement)"
# POURQUOI CE CONTRÔLE EXISTE. Le squelette `gabarits/CLAUDE.md` livre les rubriques du persona et
# la table « Mes domaines » marquées « à remplir » ; une V1 ou une V2 importée peut porter encore
# des notes `<!-- WIZARD -->`. Rien d'autre ne vérifie que la PERSONNALISATION a eu lieu : quelqu'un pouvait vivre des mois avec douze rubriques génériques et une table
# « *(à remplir)* » sans qu'aucun contrôle ne bronche (relevé d'audit du 2026-08-14). Chez
# l'auteur, dont le règlement n'a jamais porté ces marques, ce contrôle est vert et muet.
# AVERTISSEMENT, jamais ko : une dette de personnalisation n'est ni une perte irréversible, ni
# une fuite, ni le désarmement silencieux d'une garde (critère de warn(), en tête de fichier) —
# elle encombre, elle ne désactive rien, et bloquer la sauvegarde dessus ferait payer un
# entretien remis à plus tard par la perte du travail du jour.
_R47="$HOME/.claude/CLAUDE.md"
if [ ! -f "$_R47" ]; then
    warn "règlement introuvable ($_R47) — rien à contrôler ici, d'autres contrôles le diront"
else
    _m47="$(grep -n "<!-- WIZARD\|à remplir" "$_R47" | head -6)"
    if [ -n "$_m47" ]; then
        warn "le règlement porte encore des marques de gabarit — entretien non joué, ou persona/table de routage laissées en l'état :"
        printf '%s\n' "$_m47" | sed 's/^/       /' >&2
        echo "       Le remède : rejouer l'entretien — compétence claudeos-onboarding, ou l'agent livré. Une" >&2
        echo "       rubrique s'y règle, ou se retire quand l'utilisateur n'a rien de particulier à y mettre ;" >&2
        echo "       Identité reste. La ligne « à remplir » de « Mes domaines » cède au premier domaine." >&2
    else
        ok "aucune marque de gabarit dans le règlement"
    fi
fi
# Et les réponses (garantie 3 de `d-mesure-perso`, plan V3, lot 6, geste 4) : une clé d'entretien du
# contrat absente de `reglages/REPONSES` laisse le moteur la traiter en poste non réglé. Le démarrage
# le dit aussi (M-INACHEVEE, test a) ; ici, la passe mensuelle nomme chaque clé. Une clé vide est
# une réponse, pas un manque.
_c47="$CFG/REPONSES_CLES"
if [ -r "$_c47" ]; then
    _manq47=""
    while read -r _k47 _o47 _reste47; do
        case "$_k47" in ''|\#*) continue ;; esac
        [ "$_o47" = entretien ] || continue
        claudeos_reponse "$_k47" >/dev/null || _manq47="$_manq47 $_k47"
    done < "$_c47"
    if [ -n "$_manq47" ]; then
        warn "reglages/REPONSES ne porte pas ces clés d'entretien :$_manq47 — rejouer l'entretien (claudeos-onboarding, ou l'agent livré)"
    else
        ok "chaque clé d'entretien du contrat est dans reglages/REPONSES"
    fi
else
    warn "contrat des réponses illisible ($_c47) — les clés ne se comptent pas"
fi

# =============================================================================
echo "[selftest] 48. Renvois au règlement — la section citée porte-t-elle encore le CONTENU ? (avertissement)"
# CONTRÔLE NEUF, posé le 2026-09-04 sur arbitrage explicite de l'utilisateur — `controles-et-alarmes`
# réserve un contrôle neuf à un fait nouveau qu'il tranche, et c'en est un.
#
# LE FAIT NOUVEAU. Le commit `6f2bfab` du 2026-08-22 a retiré deux règles du règlement racine sans
# destination — le périmètre de modification du code, et les trois interdits sur les secrets. CINQ
# documents vivants ont continué treize jours d'affirmer qu'elles y vivaient. Aucun mécanisme ne
# pouvait sonner : le chemin existait, le numéro de section existait, le contrôle 27 des chemins
# morts était vert. SEUL LE CONTENU À L'ARRIVÉE MANQUAIT. Deux audits complets l'ont manqué.
#
# CE QU'IL MESURE, volontairement ÉTROIT. Pour chaque renvoi « racine §N » / « règlement §N » écrit
# dans une règle vivante : la section §N existe-t-elle dans le règlement, ET porte-t-elle au moins
# un mot significatif de la phrase qui la cite ?
#
# SA LIMITE, MESURÉE LE JOUR DE SON ÉCRITURE : il exige UN seul mot commun, donc un renvoi dont la
# phrase emploie un mot générique passe. Cas réel manqué — « Écriture immédiate, sans demander (règle
# mémoire, `CLAUDE.md` §2) » : le §2 contient « écriture » et « demander » à propos de tout autre
# chose, donc le renvoi est passé alors qu'il était orphelin. Trouvé à la main, pas par lui. Exiger
# deux mots communs monterait le rappel ET les faux positifs ensemble ; non fait, à trancher sur
# plusieurs passes.
# POURQUOI IL AVERTIT ET NE BLOQUE PAS — décision, pas réglage par défaut. La fiche range « une règle
# existe, le système croit l'appliquer, elle ne se charge jamais » dans ce qui BLOQUE. Celui-ci est
# HEURISTIQUE : il compare des mots, donc il ne distingue pas un renvoi mort d'une cible reformulée.
# Un faux positif bloquerait une journée de travail sur du vocabulaire — le mode d'échec que cette
# même fiche dit avoir payé deux fois. Le passer en bloquant, une fois sa précision établie sur
# plusieurs passes, sera une décision à écrire.
#
# VERDICT DE LA PASSE DU 2026-09-22, ecrit ici pour ne pas reinstruire les memes quatre a chaque
# passe : les QUATRE signalements courants sont des FAUX POSITIFS, chaque section ouverte une par
# une. Trois sont des reformulations exactes (memoire-et-verite, nouveau-domaine, session) ;
# le quatrieme (le CLAUDE.md d'un domaine de l'auteur) est un recit AU PASSE lu comme un renvoi vivant.
# ⛔ NE PAS REJOUER LA PISTE DU VERBE A L'IMPARFAIT pour filtrer ce dernier : deja tentee et
# MESUREE A 0 le 2026-09-17, note D9 ci-dessous. La sonde de l'audit du 2026-09-22 l'a reproposee
# sans avoir lu cette note. Un nouveau signalement, lui, se lit : ces quatre-la, non.
# SOLDE LE 2026-09-23 : les trois restants (nouveau-domaine, os-audit, session) ont ete
# REFORMULES pour partager un mot avec leur section, apres relecture de chacune ; le controle est
# vert. Le correctif porte sur les PHRASES, pas sur l'heuristique : sa limite reste entiere.
_claudeos_py_renvois_muets() {
python3 - "$HOME/.claude/CLAUDE.md" <<'PY'
import re, sys, os, glob
regl = open(sys.argv[1], encoding='utf-8').read()
sections = {}
ms = list(re.finditer(r'^## (\d+)\.\s*([^\n]*)$', regl, re.M))
for i, m in enumerate(ms):
    fin = ms[i+1].start() if i+1 < len(ms) else len(regl)
    sections[m.group(1)] = (m.group(2), regl[m.start():fin].lower())
STOP = set("dans pour avec sans sous cette celui celle leurs elles quand donc mais alors ainsi comme entre selon aussi encore toujours jamais chaque tout tous toute toutes autre autres même plus moins bien très fait faire vivent vivait vivre porte portent portait règle règles racine règlement section niveau déjà charge chargé chargée voir depuis avant après celles ceux".split())
def mots(t):
    t = re.sub(r'`[^`]*`', ' ', t.lower())
    return {w for w in re.findall(r"[a-zà-ÿ]{5,}", t) if w not in STOP}
HOME = os.path.expanduser('~')
# La COUCHE DOMAINE entre au corpus le 2026-09-08 : les règles de savoir-faire y ont été
# remontées au geste 1.4, et un renvoi muet au règlement y coûte autant qu'ailleurs.
_cl = [os.path.join(HOME, d) for d in sorted(os.listdir(HOME))
       if not d.startswith('.') and os.path.isfile(os.path.join(HOME, d, 'CLAUDE.md'))]
corpus = ([HOME + '/.claude/DESIGN.md']
          + sorted(glob.glob(HOME + '/.claude/skills/*/SKILL.md'))
          + sorted(glob.glob(HOME + '/.claude/domaines/*/CLAUDE.md'))
          + sorted(glob.glob(HOME + '/.claude/domaines/*/DESIGN.md'))
          + [f for c in _cl for f in sorted(glob.glob(c + '/CLAUDE.md'))]
          + [f for c in _cl for f in sorted(glob.glob(c + '/*/CLAUDE.md'))]
          + [f for c in _cl for f in sorted(glob.glob(c + '/DESIGN.md'))])
PAT = re.compile(r'(?:racine|règlement)[^.\n]{0,25}?§\s?(\d+)(?:\.\d+)*')
for f in corpus:
    if not os.path.exists(f): continue
    # PHRASES, PAS LIGNES (corrigé le 2026-09-04, à l'exercice). Le corpus est enroulé à ~100
    # colonnes : une phrase tient sur deux ou trois lignes physiques. Lire ligne par ligne faisait
    # mesurer un FRAGMENT — le filtre des renvois datés ratait une date passée à la ligne suivante,
    # et l'extraction de mots ne voyait qu'un tiers du sujet. Le contrôle criait alors sur sa propre
    # note de correction. On travaille donc sur le texte entier, en retrouvant le numéro de ligne
    # par le décalage du caractère.
    txt = open(f, encoding='utf-8').read()
    rel = f.replace(HOME + '/', '')
    debuts = [0]
    for c in txt:
        debuts.append(debuts[-1] + 1)
    def ligne_de(pos): return txt.count('\n', 0, pos) + 1
    # Une phrase court d'un point/point-virgule/fin de paragraphe au suivant.
    # LE POINT D'UN NUMÉRO DE SECTION N'EST PAS UNE FIN DE PHRASE (2026-09-04, à l'exercice) :
    # « (§3.2) le 2026-08-15 » se coupait sur le point de « 3.2 », la date tombait dans la phrase
    # suivante, et le filtre des récits datés la ratait. Un faux positif sur quatre en venait.
    for ph in re.finditer(r'[^.;\n][^.;]*?(?:(?<!\d)[.;](?!\d)|\n\n|$)', txt, re.S):
        phrase = ph.group(0)
        m = PAT.search(phrase)
        if not m: continue
        num = m.group(1)
        n = ligne_de(ph.start() + m.start())
        if num not in sections:
            print(rel + ":" + str(n) + " → §" + num + " N'EXISTE PAS dans le règlement"); continue
        # D9 TENTÉ PUIS RETIRÉ le 2026-09-17, deux pistes mesurées et écartées — ne pas les
        # rejouer sans lire l'observation du journal. (1) Élargir la recherche de date au
        # PARAGRAPHE règle ce même CLAUDE.md de domaine mais filtre 7 renvois sur 13 : plus de la
        # moitié du périmètre retirée pour un faux positif. (2) Filtrer sur un verbe à l'imparfait
        # (`renvoyait|affirmait|…`) n'attrape RIEN — mesuré à 0 sur tout le corpus, le fragment
        # de phrase analysé ne porte pas le verbe. Les 3 signalements restants sont des faux
        # positifs de VOCABULAIRE, pas de récit, et c'est la limite documentée plus haut.
        if re.search(r'20\d\d-\d\d-\d\d', phrase): continue
        titre, corps = sections[num]
        cles = mots(phrase)
        if not cles: continue
        if not (cles & mots(corps)):
            ap = ' '.join(sorted(cles)[:4])
            print(rel + ":" + str(n) + " → §" + num + " « " + titre + " » ne porte AUCUN mot du renvoi (" + ap + "…)")
PY
}
# UNE ANALYSE QUI MEURT N'EST PAS « RIEN À SIGNALER » (2026-10-01, A5) : sans `CLAUDE.md`, ou sur
# une erreur Python, la sortie est vide et le contrôle concluait au vert, sur la branche d'erreur.
if ! _renvois_muets=$(_claudeos_py_renvois_muets); then
    warn "renvois au règlement : analyse en échec (cause ci-dessus) — mesure RATÉE, ne pas lire comme un vert"
elif [ -n "$_renvois_muets" ]; then
    warn "renvoi(s) au règlement dont la section citée ne porte plus le sujet :"
    printf '%s\n' "$_renvois_muets" | sed 's/^/       /' >&2
    echo "       Heuristique : un renvoi vers une cible REFORMULÉE sort ici aussi. Ouvrir la section avant de conclure." >&2
else
    ok "tout renvoi « racine §N » résout vers une section qui porte encore son sujet"
fi

# =============================================================================
echo
if [ "$FAIL" = 0 ]; then
    echo "[weekly] ✅ contrôles de contenu passés (les avertissements ci-dessus, s'il y en a, sont à traiter)."
else
    echo "[weekly] ❌ au moins un contrôle bloquant a échoué." >&2
fi
exit "$FAIL"
