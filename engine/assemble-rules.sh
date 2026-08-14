#!/usr/bin/env bash
# =============================================================================
# ASSEMBLE-RULES — assemble le règlement à partir du gabarit et des conditions vraies.
#
# Appelé par la compétence d'accueil après l'entretien. Déterministe et rejouable :
# l'assemblage ne doit PAS reposer sur un modèle qui retire des blocs à la main à
# chaque installation. Un retrait raté ne se manifeste par rien — soit une règle
# manque, soit une règle sans objet reste, et dans les deux cas personne ne le voit.
#
#   assemble-rules.sh --vraies MULTIDOMAINE,CONFIDENTIEL[,…]
#   assemble-rules.sh --vraies "" --essai <dossier>   (essai à blanc sur une copie)
#
# Conditions reconnues : MULTIPOSTE MULTIDOMAINE LIVRABLE CONFIDENTIEL PROXY
#                        SUPERVISION CODE_RELU SOLLICITATIONS RIGUEUR_AFFICHEE CONCISION
# Les autres sont tenues pour vraies et n'ont pas de marqueur dans le gabarit.
# =============================================================================
set -uo pipefail

CONNUES="MULTIPOSTE MULTIDOMAINE LIVRABLE CONFIDENTIEL PROXY SUPERVISION CODE_RELU SOLLICITATIONS RIGUEUR_AFFICHEE CONCISION"
VRAIES=""
CIBLE="$HOME/.claude"
ESSAI=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --vraies) VRAIES="${2-}"; shift 2 ;;
        --essai)  CIBLE="${2-}"; ESSAI=1; [ -d "$CIBLE" ] || { echo "[assemble] ERREUR : dossier d'essai introuvable : $CIBLE" >&2; exit 2; }; shift 2 ;;
        *) echo "[assemble] ERREUR : argument inconnu '$1'. Attendu : --vraies <liste>, --essai <dossier>." >&2; exit 2 ;;
    esac
done
[ -n "${VRAIES+x}" ] || { echo "[assemble] ERREUR : --vraies est obligatoire (liste éventuellement vide)." >&2; exit 2; }

# Toute condition citée doit être connue. Une faute de frappe passerait sinon en
# silence et retirerait le bloc qu'on voulait garder — défaut invisible par excellence.
IFS=',' read -ra _v <<< "$VRAIES"
for c in "${_v[@]}"; do
    [ -n "$c" ] || continue
    case " $CONNUES " in *" $c "*) ;; *) echo "[assemble] ERREUR : condition inconnue '$c'. Connues : $CONNUES" >&2; exit 2 ;; esac
done

est_vraie() {
    local c="$1" x
    for x in "${_v[@]}"; do [ "$x" = "$c" ] && return 0; done
    return 1
}

# LES RÉPONSES SONT ÉCRITES, et pas seulement consommées. Jusqu'ici elles arrivaient par
# drapeau, servaient à retirer des blocs, et disparaissaient — donc plus rien, ensuite, ne
# savait ce que la personne avait choisi. L'autotest en particulier : il contrôlait les
# exclusions confidentielles et BLOQUAIT la sauvegarde de qui avait justement répondu ne pas
# vouloir cette fonction. Un contrôle qui exige ce qu'on a explicitement décliné n'est pas
# sévère, il est faux.
# Le fichier est la mémoire de l'entretien. Son ABSENCE vaut « tout est vrai » : un système
# installé autrement, ou plus ancien que ce mécanisme, doit être contrôlé au maximum, pas au
# minimum. Le défaut sûr est du côté qui vérifie trop.
# CE BLOC NE S'EXÉCUTE PAS EN MODE ESSAI, et c'est le point. Le chemin ci-dessous est résolu
# depuis l'emplacement du SCRIPT, jamais depuis la cible : sans cette garde, un essai à blanc
# écrivait ce fichier dans l'arborescence réelle, avec la liste passée à l'essai. Un essai à
# blanc qui écrit désarme en silence tous les contrôles conditionnels de l'autotest — le
# fichier existant, son absence ne vaut plus « tout est vrai ». Défaut mesuré le 2026-08-14,
# doctrine déjà énoncée plus bas (« l'essai ne touche que sa copie ») mais pas appliquée ici.
if [ "$ESSAI" -eq 1 ]; then
    echo "[assemble] Essai à blanc : conditions NON écrites (l'essai ne touche que sa copie)."
else
_CONF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config/CONDITIONS"
mkdir -p "$(dirname "$_CONF")"
{
    echo "# Réponses de l'entretien d'installation, une par ligne."
    echo "# Lu par l'autotest : un contrôle rattaché à une condition absente d'ici est sauté."
    echo "# Fichier absent = toutes les conditions tenues pour vraies, donc tout est contrôlé."
    for x in "${_v[@]}"; do [ -n "$x" ] && echo "$x"; done
} > "$_CONF"
echo "[assemble] Conditions écrites   : $_CONF"
fi

REGLEMENT="$CIBLE/CLAUDE.md"
[ -f "$REGLEMENT" ] || { echo "[assemble] ERREUR : règlement introuvable : $REGLEMENT" >&2; exit 2; }

# --- Retrait des blocs -------------------------------------------------------
# Deux formes : un bloc sur UNE ligne (ouverture et fermeture sur la même), et un
# bloc sur plusieurs lignes. Les deux sont traitées — n'en gérer qu'une laisserait
# passer l'autre sans rien dire.
RETIRES=""; GARDES=0
TMP="$(mktemp)"
SUPPRIME=0
while IFS= read -r ligne; do
    if [ "$SUPPRIME" = 1 ]; then
        case "$ligne" in *"<!-- FIN -->"*) SUPPRIME=0 ;; esac
        continue
    fi
    case "$ligne" in
        *"<!-- CONDITION "*)
            cond="$(printf '%s' "$ligne" | sed -n 's/.*<!-- CONDITION \([A-Z_]*\) -->.*/\1/p')"
            case " $CONNUES " in
                *" $cond "*) ;;
                *) echo "[assemble] ERREUR : le gabarit porte une condition inconnue : '$cond'" >&2; rm -f "$TMP"; exit 2 ;;
            esac
            if est_vraie "$cond"; then
                # Gardé : on retire les marqueurs, y compris les guillemets obliques
                # qui les entourent dans les tableaux, et l'espace qu'ils laissent.
                printf '%s\n' "$ligne" | sed -e 's/`<!-- CONDITION [A-Z_]* -->` //g' \
                                             -e 's/<!-- CONDITION [A-Z_]* --> //g' \
                                             -e 's/ `<!-- FIN -->`//g' -e 's/`<!-- FIN -->`//g' \
                                             -e 's/ <!-- FIN -->//g' -e 's/<!-- FIN -->//g' >> "$TMP"
                GARDES=$((GARDES+1))
            else
                RETIRES="$RETIRES $cond"
                case "$ligne" in *"<!-- FIN -->"*) ;; *) SUPPRIME=1 ;; esac
            fi
            ;;
        *"<!-- FIN -->"*)
            # Fermeture d'un bloc multi-lignes CONSERVÉ (le retiré est absorbé plus haut).
            # Sans ce cas, le marqueur passait tel quel et la garde finale échouait — le
            # chemin « bloc multi-lignes gardé » n'avait jamais été exercé avant 2026-08-14.
            printf '%s\n' "$ligne" | sed -e 's/ `<!-- FIN -->`//g' -e 's/`<!-- FIN -->`//g' \
                                         -e 's/ <!-- FIN -->//g' -e 's/<!-- FIN -->//g' >> "$TMP"
            ;;
        *) printf '%s\n' "$ligne" >> "$TMP" ;;
    esac
done < "$REGLEMENT"
[ "$SUPPRIME" = 1 ] && { echo "[assemble] ERREUR : un bloc conditionnel n'est pas fermé dans le gabarit." >&2; rm -f "$TMP"; exit 2; }

# Le bloc de consigne destiné à l'assemblage n'a plus lieu d'être une fois assemblé.
sed -i '/WIZARD : ce fichier est assemblé/,/L.OSSATURE DES SECTIONS NE CHANGE PAS/d' "$TMP"
sed -i '/^> `$/d' "$TMP"

mv "$TMP" "$REGLEMENT"

# --- Retrait des compétences devenues sans objet -----------------------------
# Le dossier de compétence ET sa ligne de déclencheur partent ensemble. Une compétence
# présente mais absente de la carte de rappel a perdu son déclencheur visible ; une ligne
# de déclencheur sans compétence envoie vers le vide. Ce sont les deux moitiés du même
# défaut, et la ligne a déjà été retirée ci-dessus.
# TROISIÈME moitié, et elle manquait : l'INVENTAIRE du document de conception.
# La compétence partait, sa ligne de déclencheur partait, et sa ligne d'inventaire restait.
# Or un contrôle de plomberie vérifie que chaque ligne de cet inventaire désigne une chose
# existante — donc toute personne répondant « non » à une condition héritait d'un
# avertissement permanent, dès son premier autotest, sur un système parfaitement conforme.
# C'est le pire genre de faux positif : il apparaît à l'installation, il ne part jamais, et
# il apprend à ignorer l'autotest. Un contrôle qu'on apprend à ignorer est un contrôle mort.
_retire_competence() {  # $1 = nom de la compétence, $2 = nom de la condition
    rm -rf "${CIBLE:?}/skills/$1"
    # LES DEUX EXEMPLAIRES PARTENT ENSEMBLE. Le dossier de configuration est sauvegardé en
    # régime additif : la sauvegarde ne propage jamais une suppression. Retirer le seul
    # exemplaire vivant laissait le miroir du dépôt en place, et le contrôle de dérive
    # (« fichier du repo absent en live ») bloquait la sauvegarde suivante — exercé sur
    # pièce le 2026-08-14, en rejouant l'entretien après une première sauvegarde. Le
    # miroir se retire donc ici, et la prochaine sauvegarde committe la disparition.
    # Jamais en mode essai : l'essai ne touche que sa copie.
    if [ "$CIBLE" = "$HOME/.claude" ]; then
        rm -rf "$HOME/.claudeos/system/skills/$1"
    fi
    sed -i "\#^| \`$1\` |#d" "$CIBLE/DESIGN.md" 2>/dev/null
    if grep -qF "\`$1\`" "$CIBLE/DESIGN.md" 2>/dev/null; then
        echo "[assemble] ⚠ $1 retirée, mais le document de conception la cite encore — à vérifier." >&2
    fi
    COMPETENCES_RETIREES="$COMPETENCES_RETIREES $1"
}
COMPETENCES_RETIREES=""
est_vraie LIVRABLE || _retire_competence "livrables" LIVRABLE
est_vraie PROXY    || _retire_competence "rtk-depannage" PROXY

# --- Compte rendu ------------------------------------------------------------
echo "[assemble] Conditions vraies : ${VRAIES:-(aucune)}"
echo "[assemble] Blocs conservés   : $GARDES"
echo "[assemble] Blocs retirés     :${RETIRES:- aucun}"
echo "[assemble] Compétences retirées :${COMPETENCES_RETIREES:- aucune}"

# Garde de dernier ressort : aucun marqueur ne doit survivre. Un marqueur resté en
# place signale un bloc ni retiré ni ouvert, donc un assemblage à moitié fait.
if grep -q "<!-- CONDITION\|<!-- FIN" "$REGLEMENT"; then
    echo "[assemble] ⛔ des marqueurs subsistent dans le règlement — assemblage incomplet." >&2
    grep -n "<!-- CONDITION\|<!-- FIN" "$REGLEMENT" >&2
    exit 1
fi
echo "[assemble] ✅ aucun marqueur résiduel."
