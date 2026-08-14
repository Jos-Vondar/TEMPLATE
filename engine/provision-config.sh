#!/usr/bin/env bash
# =============================================================================
# PROVISION-CONFIG — les artefacts de configuration que le squelette exige mais
# qu'aucune copie de fichiers ne pose : ils naissent VIDES chez la personne, ils ne
# viennent pas de l'arbre livré, donc ni l'installation par manifeste ni la mise à
# jour incrémentale ne les voient.
#
# Deux chemins doivent les poser — install.sh à l'installation, update.sh à chaque
# passage (depuis la version NEUVE) — et deux descriptions à deux endroits finissent
# toujours par diverger : ce script est le seul lieu qui les décrit. Sans le second
# appelant, une mise à jour laissait l'autotest en défaut (« chemin cité par une règle
# mais absent du disque ») et la sauvegarde refusée. Exercé sur pièce (v1.1.0 → v2.0.0).
#
# IDEMPOTENT, et c'est sa loi : il ne crée que ce qui manque, il n'écrase ni ne
# réécrit jamais une décision locale. Le relancer cent fois ne change rien.
# =============================================================================
set -uo pipefail
DEPOT="$HOME/.claudeos"
CONF="$DEPOT/engine/config"
mkdir -p "$CONF" "$HOME/.claude/output-styles"

# --- 1. Le fichier des créneaux hebdomadaires --------------------------------
# Cité par la compétence `session`, lu par le bilan de démarrage et par le générateur
# de fils ouverts — les deux tolèrent son absence, mais l'autotest exige que tout
# chemin cité par une règle existe (contrôle 27) : sans ce fichier, la sauvegarde est
# refusée. Créé avec son mode d'emploi en tête et sans contenu — vide, il ne filtre
# rien ; c'est l'entretien d'installation qui l'écrit, à partir du rythme déclaré.
CRN="$CONF/CRENEAUX"
if [ -f "$CRN" ]; then
    echo "[provision] créneaux : déjà en place"
else
cat > "$CRN" <<'CRENEAUX'
# CRENEAUX — les créneaux hebdomadaires par domaine. Lu par le bilan de démarrage
# (filtre de la proposition du jour) et par le générateur de fils ouverts, qui compte
# l'ancienneté d'un fil en créneaux manqués plutôt qu'en jours calendaires.
#
# Colonnes (séparées par des espaces) :
#   1. domaine   nom du dossier sous ~/workstations/ (le même que dans SYNC_MAP)
#   2. jours     liste séparée par des virgules, parmi : lun mar mer jeu ven sam dim
#
# Exemple :
# MON_DOMAINE  lun,mar
#
# Un domaine absent de ce fichier n'a PAS de créneau : il est proposable tous les jours
# et son ancienneté se compte en jours. C'est le défaut, et il est sain — vide, ce
# fichier ne filtre rien. L'entretien d'installation le remplit avec le rythme déclaré ;
# un changement de rythme s'écrit ici, seule source que les scripts lisent.
CRENEAUX
    echo "[provision] créneaux : fichier créé, vide — l'entretien le remplit"
fi

# --- 2. Le verrou de sauvegarde : lignes de liste blanche nées après coup ----
# Le verrou (.gitignore du dépôt) naît complet à l'installation — c'est install.sh qui
# l'écrit, avec le récit de chaque ligne. Mais une ligne née avec une VERSION n'existe
# pas chez qui a installé la version d'avant : le contenu livré arrive, le verrou le
# refuse, et l'autotest le signale comme « chemin qu'aucune liste n'a tranché ». On
# n'ajoute ici que des AUTORISATIONS de contenu livré par le squelette lui-même —
# jamais une exclusion, jamais une réécriture : le verrou reste la décision de la
# personne, on ne fait que laisser passer ce que la mise à jour vient de poser.
# L'ORDRE COMPTE : une autorisation s'ajoute en FIN de fichier, après l'attrape-tout,
# parce que c'est le dernier motif correspondant qui gagne.
VERROU="$DEPOT/.gitignore"
if [ -f "$VERROU" ]; then
    for ligne in '!system/output-styles/*.md'; do
        if grep -qxF "$ligne" "$VERROU"; then
            echo "[provision] verrou : $ligne déjà en place"
        else
            {
                echo "# Ligne ajoutée par une mise à jour (provision-config.sh) : ce contenu est livré"
                echo "# par le squelette, la liste blanche doit le laisser partir en sauvegarde."
                echo "$ligne"
            } >> "$VERROU"
            echo "[provision] verrou : $ligne ajoutée en liste blanche"
        fi
    done
else
    # Pas de verrou = installation en cours, install.sh l'écrira complet juste après.
    echo "[provision] verrou : absent — install.sh le crée avec ses lignes à jour"
fi

# --- 3. La trace de détection du proxy économe -------------------------------
# Lue par assemble-rules.sh pour trancher la condition PROXY sans compter sur la mémoire
# d'un modèle. install.sh l'écrit à l'étape du proxy et la RÉÉCRIT à chaque passage —
# c'est lui l'autorité, au moment où le résultat est frais. Une installation antérieure
# au mécanisme n'en a pas : on la crée ici par sonde directe, pour que rejouer
# l'entretien après une mise à jour lise un fait et non une devinette. Créée seulement
# si absente — la loi du script — et donc jamais en travers d'install.sh, qui passe
# après ce script et écrase avec le résultat de son installation.
PRX="$CONF/PROXY"
if [ -f "$PRX" ]; then
    echo "[provision] trace proxy : déjà en place"
else
    {
        echo "# PROXY — résultat de la détection du proxy économe (install.sh, sinon provision-config.sh)."
        echo "# Lu par assemble-rules.sh pour trancher la condition PROXY. « oui » = outil présent."
        if command -v rtk >/dev/null 2>&1; then echo "oui"; else echo "non"; fi
    } > "$PRX"
    echo "[provision] trace proxy : écrite — $(tail -1 "$PRX")"
fi
