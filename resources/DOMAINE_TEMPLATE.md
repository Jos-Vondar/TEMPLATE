# Gabarit de domaine — Stubs de création

Ce fichier est lu par Claude lors de la commande "crée un domaine".
Ne pas charger en session normale.

**Invariants de création, à tenir pour chaque stub ci-dessous :**

- **La racine d'un domaine dépend du régime** (`GIT` dans `reglages/REPONSES`), et
  `<RacineWS>` la désigne dans tout ce fichier. En `par-domaine`, `~/<NomDepot>/`, **la racine
  d'un dépôt git** : c'est le dépôt qui met le domaine dans le périmètre de sauvegarde, pas son
  emplacement — un dossier créé sous `~/` sans `git init` ni remote naît hors sauvegarde, et rien
  n'échoue pour le signaler. En `unique`, `~/.claude/travail/<NomDomaine>/`, dans le dépôt du
  système. En `aucun`, le même dossier, sans dépôt : rien ne sort du poste.
- **Si `CONFIDENTIEL=oui`**, tout dossier de **projet** reçoit un `_IGNORE/` à sa création :
  `mkdir -p <RacineWS>/<Projet>/_IGNORE`. C'est le réceptacle des documents confidentiels, tenu
  hors sauvegarde. Une **application** n'en reçoit pas, ni aucun sous-dossier de projet : un seul
  réceptacle par projet, à sa racine, et le confidentiel d'une app y va.
- Le nouveau domaine est ajouté à la table « Mes domaines » du `CLAUDE.md` racine — c'est la
  seule inscription qui reste. Deux oublis restent possibles : le routage et, en `par-domaine`, le
  dépôt lui-même. La procédure complète : compétence `nouveau-domaine`.

---

## Stub : CLAUDE.md domaine

**Destination :** `<RacineWS>/CLAUDE.md`

# CLAUDE.md — Domaine <NomDomaine>
Hérite de `~/.claude/CLAUDE.md`.

---

## 0. Routing Projets

Pour toute demande relative à un projet ci-dessous, charger son `CLAUDE.md` puis son `ETAT.md` en priorité. Un fait neuf s'écrit par `etat.py add --niveau <NomProjet>`.

| Projet | Dossier | Instructions locales |
|---|---|---|
| <NomProjet> | `<NomProjet>/` | `<NomProjet>/CLAUDE.md` + `<NomProjet>/ETAT.md` |

---

## 1. Règles techniques

<!-- À compléter selon le métier du domaine. -->

---

## Stub : ÉTAT du domaine — le même geste qu'au projet

**Destination :** `<RacineWS>/journal/`, puis `<RacineWS>/ETAT.md` engendré par projection. Même
geste que le « Stub : ÉTAT du projet » plus bas, lancé depuis `<RacineWS>` avec `--niveau .`.
**Aucun `MEMORY.md`** : l'état vivant d'un niveau est son journal.

---

## Stub : CLAUDE.md projet

**Destination :** `<RacineWS>/<NomProjet>/CLAUDE.md`

# CLAUDE.md — Projet <NomProjet>
Hérite de `<RacineWS>/CLAUDE.md`.

---

## 1. Routing Applications

| Application | Dossier |
|---|---|

---

## 2. Règles spécifiques

<!-- À compléter. -->

---

## Stub : ÉTAT du projet — un événement, jamais un fichier écrit à la main

**Destination :** `<RacineWS>/<NomProjet>/journal/`, puis `ETAT.md` engendré par projection.

Depuis `<RacineWS>` :

```bash
mkdir -p <NomProjet>/journal
python3 ~/.claude/engine/etat.py add --niveau <NomProjet> --type etat --op avance \
  --chantier statut --ref e-projet-monte --source "<NomProjet>/CLAUDE.md" \
  --texte "PROJET MONTE LE <AAAA-MM-JJ>, ET RIEN N EST CONSTRUIT. Objet : … Ce que la premiere seance doit etablir : …"
python3 ~/.claude/engine/etat.py projette --niveau <NomProjet>
```

`ETAT.md` est une PROJECTION : l'éditer à la main est refusé au commit (code 23). Il n'y a **aucun
plafond à recopier ici** — les plafonds vivent dans `~/.claude/engine/config.sh`, seule source.

---

## Ce qui ne se scaffolde PAS — le document de conception

La création s'arrête aux quatre stubs ci-dessus. Le document de conception d'un niveau, `DESIGN.md`
par convention, **n'est pas créé d'avance**, ni au niveau domaine ni au niveau projet : il naît
au premier besoin réel, la première décision d'architecture à consigner. Quand il naît, une ligne
d'en-tête suffit, sous son titre :

`<!-- Référence stable : comportements voulus, décisions d'architecture. Jamais d'événements datés → un événement du journal. -->`

Motif : une souche jamais remplie fait croire à un système plus grand qu'il n'est, et elle appelle
un contrôle de plus pour surveiller son vide. Un fichier créé le jour où il a quelque chose à
porter n'a besoin d'aucune surveillance.

**Aucune archive ne naît non plus.** Un récit qui doit quitter un document vivant devient un
événement `observation` du journal de son niveau : il survit, il se cherche au `grep`, et il
n'encombre aucun état projeté. La règle vit dans la compétence `memoire-et-verite`, § « Les
archives sont GELÉES », seule source.
