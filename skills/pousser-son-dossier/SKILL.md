---
name: pousser-son-dossier
description: "Pousser le dossier d'une session de projet vers le dépôt sans attendre la session principale. Déclenche aussi quand on demande à une session de projet de « sauvegarder » : confondre pousser et clôturer laisse croire un travail contrôlé qui ne l'est pas."
---

> **Régime GitHub seulement** — `GIT=par-domaine` ou `GIT=unique`. En `GIT=aucun`, rien ne se pousse et
> cette compétence est masquée (`skillOverrides`). Le dépôt ne se nomme pas, il **se résout depuis le
> dossier de travail**.

## Le geste

Il n'y a pas de script : le dossier de travail **est** dans l'arbre de son dépôt — celui de son
domaine en `par-domaine`, celui du système en `unique`.

```bash
# 0. Le dépôt se RÉSOUT, depuis le dossier de travail. Il ne se nomme pas.
D=$(git rev-parse --show-toplevel) && echo "$D"

# 1. Voir ce qui partirait, et rien d'autre.
git -C "$D" status --porcelain -- <chemin du dossier>

# 2. Mettre en file, puis committer. Le hook pre-commit passe les alarmes.
git -C "$D" add <chemin du dossier>
git -C "$D" commit -m "<projet ou app> : <ce qui a changé>"

# 3. Sortir de la machine.
git -C "$D" pull --rebase && git -C "$D" push
```

Plusieurs dépôts, et la session est déjà ouverte dans le bon : un dépôt nommé en dur serait faux
partout ailleurs.

**Le message se génère depuis la FILE, jamais depuis l'annonce** *(2026-09-09)*. Décrire ce que
`git diff --cached --stat` montre, pas ce qu'on avait prévu de faire : entre l'annonce et le commit
il y a eu des corrections, des renoncements et des trouvailles, et c'est le message qui devient la
seule trace de l'écart.

**Variante à connaître — la SEULE sortie propre quand plusieurs sessions écrivent.**
`git commit -F <message> -- <chemins>` committe le contenu du disque de ces seuls chemins, **quoi
qu'il y ait dans la file** : le travail qu'un pair y avait mis n'est pas emporté.

**Un fichier NEUF impose un `git add` préalable** — et c'est la seule limite. **Elle ne coûte PAS
l'isolation.** Mesuré sur pièce pendant qu'un pair écrivait dans le même dépôt :
`git add <les 2 fichiers neufs>` puis `git commit -F msg -- <dossier> <autre chemin>` a rendu
**5 fichiers exactement**, les 4 fichiers du pair restant dehors. Ajouter à la file
n'engage que ce qu'on nomme ; c'est le **pathspec du commit** qui borne, pas l'état de la file.

**Ordre des arguments, payé le même jour** : les chemins APRÈS `--`, le message AVANT.
`git commit -- <chemins> -m "…"` lit `-m` comme un chemin et échoue.

## Pousser n'est pas clôturer — le distinguo décide de tout

Deux choses portent le nom de « sauvegarder » dans la bouche de l'utilisateur, et une seule est
disponible depuis un onglet de projet.

| | **Pousser** — les trois commandes ci-dessus | **Clôturer** — `claudeos-cloture.sh` |
| :--- | :--- | :--- |
| Périmètre | un dossier de SON dépôt | **tous** les dépôts, système compris (`claudeos_repos`) |
| Qui peut l'appeler | n'importe quelle session | la principale seule |
| Alarmes du hook de commit | **oui** — le shim est le même pour tous | oui |
| Contrôle des secrets sur l'arbre entier | non | oui |
| Projection de TOUS les niveaux (`etat.py projette`) | non | oui |
| Reprise et mémoire à jour | non — c'est un geste humain, pas un script | attendues avant |

**La ligne qui coûte est la dernière.** Pousser met le travail hors de la machine ; ça ne rend ni
la reprise ni la mémoire à jour, et ça ne régénère rien. Annoncer un push comme une clôture laisse
l'utilisateur croire l'état du système consigné alors que seul son fichier a voyagé.

Quand il dit « sauvegarde », la question se pose **avant** d'agir :

- **faire sortir son travail de la machine, tout de suite** → pousser, ici.
- **un état consigné, projections et contrôles compris** → la principale. Le lui dire, et s'arrêter là.

## Une file sale à la principale emporte le travail des autres

`git commit` écrit **la file entière**, pas seulement ce qu'on vient d'ajouter. Un geste laissé en
file ailleurs — un `git rm` après un renommage, un `git add` préparatoire — part donc dans le commit
d'une session de projet, hors de son périmètre.

**Contrôle avant de committer**, et il ne se saute pas :

```bash
git -C "$D" diff --cached --name-only
```

Sortie qui déborde du dossier courant = quelqu'un d'autre travaille. **Ne jamais nettoyer la file
soi-même** : le remonter et attendre. La nettoyer détruirait le travail d'un tiers. La variante `git commit -- <chemins>` ci-dessus est la sortie.

*(Mesuré le 2026-08-20 sous l'ancien moteur : un `git rm` de trois chemins renommés, laissé non
commité, avait fait refuser le push d'une session de projet. Le script refusait une file non vide.
Git nu ne refuse rien — la garde a disparu avec lui, et c'est le contrôle ci-dessus qui la
remplace, à la main.)*

## Ce que le shim absent rend muet

Les hooks vivent sous `.git/`, que git ne suit pas : **ils ne voyagent pas avec le dépôt**. Un shim
absent ne fait pas échouer le commit, il le laisse passer **sans aucune alarme**.

```bash
test -x "$D/.git/hooks/pre-commit" && echo "alarmes armées" || echo "MUET — ne pas pousser"
```

Réparation : `bash ~/.claude/engine/install-poste.sh`, idempotent.

## Ce qui n'est pas vérifié

**TROU — la garde du milieu tombe en silence.** `git pull --rebase` refuse de tourner dès qu'il
existe **un seul fichier modifié non commité N'IMPORTE OÙ dans l'arbre**, y compris hors du
périmètre de la session qui pousse :

```
error: cannot pull with rebase: You have unstaged changes.
error: Please commit or stash them.
```

**Et le push réussit quand même**, si le commit local est déjà assis sur `origin/main` : il n'y a rien
à intégrer, donc rien n'est perdu. **Le résultat est identique à celui d'une procédure complète, et
l'étape de rebase n'a pas tourné.** C'est un faux vert : la garde ne crie pas, elle est sautée.

**Geste** : lire le code de retour du `pull --rebase`, ne jamais l'enchaîner en aveugle. S'il échoue
sur des modifications non commitées **hors de son périmètre**, ce n'est pas à la session de projet de
les ranger — le dire, pousser si le commit est déjà à jour avec le distant, et **déclarer que le
rebase n'a pas eu lieu**. Ne pas `stash` le travail d'un tiers.

**CE QUI RESTE NON VÉRIFIÉ, et c'est la seule branche qui manque** : la branche de **conflit réel au
rebase** n'a jamais été exercée en conditions réelles. Si elle survient, **le commit existe en local
et rien n'est perdu** — le remonter, ne pas le réparer sur place.
