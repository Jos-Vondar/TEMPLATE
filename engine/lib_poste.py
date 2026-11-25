"""Identification du poste — SOURCE UNIQUE de la lecture du registre `reglages/POSTES`.

Le nom réseau d'une machine ne l'identifie pas : sur macOS, `socket.gethostname()` suit le réseau
tant que le nom d'hôte n'est pas fixé, et une même machine écrirait au journal sous plusieurs noms.
L'empreinte se dérive de la machine elle-même — l'IOPlatformUUID sur macOS, le `machine-id` sous
Linux et WSL —, hachée (sha256, 16 premiers caractères) : le haché seul voyage au dépôt, jamais
l'identifiant.

Le registre est `reglages/POSTES` (`CLAUDEOS_REG` déplace le dossier, comme pour `config.sh`), à
l'installateur, FACULTATIF : il ne sert qu'à qui travaille depuis plusieurs postes
(`MULTIPOSTE=oui`). Sans lui, ou pour une machine qu'il ne porte pas, le nom du poste est le nom
réseau, et l'empreinte n'est même pas calculée.
Format d'une ligne : `<empreinte> | <poste> | <libellé>`, `#` en commentaire.
  poste    la valeur écrite dans le champ `poste` du journal. Garder celle que l'historique porte
           déjà : sinon une machine se fragmente en deux postes dans les comptes.
  libellé  le nom lisible de la machine.

Lancé seul : imprime `poste|libellé|empreinte`, ou `INCONNU||<empreinte>` — c'est ainsi qu'on lit
l'empreinte d'une machine à enregistrer.
Python 3.8 au moins : le `python3` de macOS est l'un des interprètes visés.
"""

import hashlib
import os
import socket
import subprocess

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def registre():
    return os.path.join(os.environ.get("CLAUDEOS_REG") or os.path.join(RACINE, "reglages"), "POSTES")


def _identifiant():
    """L'identifiant brut de la machine : IOPlatformUUID (macOS), puis machine-id. None sinon."""
    try:
        sortie = subprocess.run(["ioreg", "-rd1", "-c", "IOPlatformExpertDevice"],
                                capture_output=True, text=True, timeout=5).stdout
        for ligne in sortie.splitlines():
            if '"IOPlatformUUID"' in ligne:
                return ligne.split('"')[3]
    except (OSError, subprocess.SubprocessError, IndexError):
        pass
    for chemin in ("/etc/machine-id", "/var/lib/dbus/machine-id"):
        try:
            with open(chemin, encoding="utf-8") as f:
                valeur = f.read().strip()
        except OSError:
            continue
        if valeur:
            return valeur
    return None


def empreinte():
    """sha256 de l'identifiant de la machine, 16 caractères. None s'il est illisible."""
    i = _identifiant()
    return hashlib.sha256(i.encode()).hexdigest()[:16] if i else None


def poste_courant(toujours_empreinte=False):
    """Rend {poste, libelle, empreinte} ; poste vide si la machine n'est pas au registre.

    Sans registre, l'empreinte ne se calcule que sur demande (`toujours_empreinte`) : rien ne la lirait.
    """
    chemin = registre()
    e = empreinte() if (toujours_empreinte or os.path.isfile(chemin)) else None
    if e:
        try:
            with open(chemin, encoding="utf-8") as f:
                for ligne in f:
                    ligne = ligne.strip()
                    if not ligne or ligne.startswith("#"):
                        continue
                    champs = [c.strip() for c in ligne.split("|")]
                    if len(champs) >= 3 and champs[0] == e:
                        return {"poste": champs[1], "libelle": champs[2], "empreinte": e}
        except OSError:
            pass
    return {"poste": "", "libelle": "", "empreinte": e or ""}


def nom_poste():
    """Le nom à écrire au journal : celui du registre, à défaut le nom réseau."""
    return poste_courant()["poste"] or socket.gethostname()


if __name__ == "__main__":
    p = poste_courant(toujours_empreinte=True)
    print(f"{p['poste'] or 'INCONNU'}|{p['libelle']}|{p['empreinte']}")
