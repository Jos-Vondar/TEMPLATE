"""Lecture du fichier de créneaux — SOURCE UNIQUE du format.

Créé le 2026-08-22, sur constat de l'audit contradictoire : le même parseur était écrit
deux fois. Changer le format du fichier
demandait donc d'éditer deux scripts, et **celui qu'on aurait oublié aurait menti sans
le dire** — il aurait simplement ignoré les lignes qu'il ne sait plus lire, et un domaine
serait sorti du créneau sans qu'aucune alarme ne sonne.

Le fichier est `reglages/CRENEAUX`, à l'installateur, FACULTATIF : sans lui, aucun créneau,
et aucun fil n'est dit hors créneau.
Format d'une ligne : `<dépôt> <jours séparés par des virgules>`, `#` en commentaire.
Exemple : `<DÉPÔT> ven` — la clé est le nom du DÉPÔT sous `~/`, pas un domaine.
"""

DAYS = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim']
DAYNAME = {'lun': 'lundi', 'mar': 'mardi', 'mer': 'mercredi', 'jeu': 'jeudi',
           'ven': 'vendredi', 'sam': 'samedi', 'dim': 'dimanche'}


def parse_creneaux(chemin):
    """Rend {domaine: [indices de jours, 0 = lundi]}. Fichier absent → dict vide.

    Un fichier absent n'est pas une erreur : un poste neuf n'en a pas encore.
    """
    creneaux = {}
    try:
        for line in open(chemin, encoding='utf-8'):
            line = line.split('#', 1)[0].strip()
            if not line:
                continue
            f = line.split()
            if len(f) < 2:
                continue
            idx = sorted({DAYS.index(j) for j in f[1].split(',') if j in DAYS})
            if idx:
                creneaux[f[0]] = idx
    except OSError:
        pass
    return creneaux
