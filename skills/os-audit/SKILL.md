---
name: os-audit
description: "**LA PASSE MENSUELLE du système ClaudeOS** — frictions du mois, trois indicateurs, veille Claude Code, contrôle au jugement sur le travail, puis au plus cinq options que l'utilisateur tranche. Déclencheurs — « audite le système », « lance la passe », « lance un check-up complet », « mon setup est-il périmé », ou le constat que l'agent rate des choses qui existent."
argument-hint: "[optionnel : AAAA-MM, le mois mesuré]"
---

# OS Audit — la passe mensuelle

## Ce que la passe sert

**Deux buts, à égalité.**
1. **Protéger le travail** de l'utilisateur — ses dossiers de travail, que rend `claudeos_ws_roots` :
   qu'aucun fait faux ou périmé du système ne le fasse mal travailler.
2. **Améliorer le système, au sens strict** : plus performant (moins de contexte chargé, moins
   d'étapes, moins d'erreurs), une mémoire plus juste et plus trouvable, plus simple. **Une
   proposition qui ajoute une pièce sans gain mesuré n'est pas une amélioration** ; celle qui en
   retire une passe devant.

**La passe ne se clôt pas avec I3 ou le code en hausse**, sauf une ligne « croissance décidée : +N
octets pour X » au condensé.

**Budget : une passe par mois, trente minutes de présence de l'utilisateur.** Un second passage le
même mois est un test : il n'écrit pas de condensé, qui écraserait celui du jour. Tout le reste tourne
sans lui. **Seuil** : une passe qui n'apporte ni constat exclusif touchant le travail — qu'aucune
garde mécanique ni l'usage n'aurait vu —, ni gain mesuré sur un indicateur, le dit en tête de son
condensé : c'est le signal d'espacer.

**Récurrence** : un constat qui revient à deux passes devient une garde de `engine/` et sort de
cette fiche — **seulement s'il a touché le travail** ; sinon il sort sans remplaçant.

## Règles de mesure

- **La mesure est read-only.** Rien ne se corrige pendant les étapes 0 à 4 ; seules les étapes 5 et 6 écrivent.
- **Dates** : les mtimes sont faux (`git checkout` les réécrit). Dater par `git log` et par le `ts`
  des événements de journal, jamais par `ls -lt` ni `find -mtime`.
- **Nommer le poste mesuré** : un constat de présence, d'absence ou d'usage ne vaut que pour lui.
- **Une sortie vide ne prouve rien** : varier le motif, dire le périmètre, vérifier qu'un proxy n'a
  pas intercepté. Sur une racine qui est un lien, une barre oblique finale : `~/.claude/`.
- **Un zéro peut venir d'un empêchement**, pas d'une absence d'usage : chercher ce qui bloquait.

## Étape 0 — La passe précédente

Le dernier condensé : en régime GitHub, le dernier ajouté ou modifié,
`git -C ~/.claude log -1 --diff-filter=AM --format= --name-only -- 'audits/os-audit-*.md'` — sans
le filtre, une suppression de condensés rend les noms supprimés ; en `GIT=aucun`, le plus récent par
son nom, `ls ~/.claude/audits/os-audit-*.md | sort | tail -n 1`. Il donne la base des indicateurs
et ce que l'utilisateur avait choisi : ce qui a été fait, ce qui ne l'a pas été.
Un condensé sans indicateurs — ancien format, ou aucune passe — donne sa base par l'en-tête de
`engine/indicateurs-audit.sh`.

## Étape 1 — Les chiffres, sans l'utilisateur

```bash
bash ~/.claude/engine/indicateurs-audit.sh          # I1 frictions, I2 octets chargés, I3 taille
bash ~/.claude/engine/weekly-check.sh               # lire les AVERTISSEMENTS, pas seulement le verdict
bash ~/.claude/engine/plafonds-parc.sh
python3 ~/.claude/engine/etat.py fils --tous | head -8   # les trois plus vieux fils ; les totaux sont en queue
```

Variation de chaque indicateur contre la passe précédente, dans son unité.

## Étape 2 — Les frictions du mois, entrée principale

Ce qui a coincé **en séance**, pas ce qu'une inspection de fichiers pourrait trouver :
- `memory/ROUTING_MISSES.md`, si `MULTIDOMAINE=oui` — trier en deux classes avant tout : **carte
  fausse** (chemin mort, `description` muette sur le moment du danger) → option de correction ;
  **carte juste, fiche non chargée** → comptée, pas re-diagnostiquée : c'est une mécanique de
  déclenchement, tenue par le refus unique du crochet de fichiers
  (`engine/hooks/rappel-fichiers-nommage.sh`), jugé sur I1.
- les événements `seance` du mois : leurs `manque_declencheur` et `manque_reprise` nommés, les
  rétractations, les gestes refaits à la main.
- **le sur-clôturage** : chaque refus de crochet du mois, rejoué contre son juge
  (`engine/hooks/creation-exemptee.py` pour le nommage), répond à « qu'a-t-il protégé ? ». Un refus
  qui ne protégeait aucune règle de la fiche exigée est une option : élargir l'exemption, ou retirer
  la règle.

**Regrouper par cause** : trois frictions d'une même cause font une option, pas trois.

## Étape 3 — La veille, un sous-agent

**Sans objet si rien n'est paru** : `gh api repos/anthropics/claude-code/releases --jq '.[0].published_at'`
antérieur à la passe précédente → pas de sous-agent. Sinon, un sous-agent, libellé qui nomme son
modèle (compétence `session`), en lecture seule, qui rend **au plus deux** options :
- **Claude Code d'abord, en entier** : journal des versions et documentation officiels depuis la
  passe précédente. Pour chaque nouveauté : **quelle pièce du système elle remplace** — script de
  `engine/`, fiche, crochet —, et ce qui sortirait.
- **Le domaine « IA OS » et la gestion de mémoire** : une idée n'entre que si elle retire une pièce
  nommée, ou améliore la performance ou la mémoire avec un gain nommé.
- Ce qui ne passe pas ce filtre va à `IDEES_FROIDES.md`, jamais au menu. Reddit est bloqué par
  conception : GitHub à la place.

**Recontrôler son rapport** avant d'en faire une option (règlement, socle, « Trois interdits, jamais conditionnés »).

## Étape 4 — Le jugement, sur le travail seulement (dix minutes)

Ce qu'aucune machine ne sait juger. Trois à cinq faits, **pris dans les dépôts de travail** :
- **Un pointeur résout mais ne répond plus** : ouvrir la source pointée par trois entrées de
  `## Où trouver` d'un `ETAT.md` de travail, vérifier qu'elle répond encore à la question.
- **Un fait vivant contre sa source** : une version, un statut, une règle de dépôt affirmés dans un
  document de conception ou dans l'index `memory/MEMORY.md` (payé à chaque session), confrontés à
  l'export, au journal ou au code.
- **Deux sources d'un même fait de travail qui se contredisent** : la cascade tranche-t-elle ?

**Un document du système pointé par une friction de l'étape 2** entre dans ce jugement au même titre :
c'est la seule voie par laquelle le faux et la contradiction côté système sont encore cherchés.

## Étape 5 — Le menu, puis le condensé

Les options viennent des étapes 1 à 4 et de [`HYGIENE.md`](HYGIENE.md) — règles candidates, fils
dormants, rangement, fiche au-dessus de son plafond. **Les classer toutes, n'en présenter que
cinq**, chacune avec son gain attendu et son coût dans l'unité du créneau, par `AskUserQuestion` —
**l'utilisateur choisit**. L'outil tient quatre options par question : deux questions à choix
multiple, système d'un côté, travail et fils de l'autre. Le reste est listé au condensé, sans question.

Écrire alors `~/.claude/audits/os-audit-AAAA-MM-JJ.md`, une page :

```
# Passe mensuelle — {date} · poste {nom}
Seuil : {franchi — par quel constat ou quel gain | NON FRANCHI — espacer}
| Indicateur | Précédente | Ce mois | Variation |   (I1, I2, I3)
Avertissements mécaniques : {liste | aucun}
Frictions du mois, par cause : {liste | registre vide et séances sans manque — le dire}
Veille : {options retenues | rien qui passe le filtre}
Jugement sur le travail : {faits vérifiés, constats | rien de faux sur N faits}
(chaque avertissement, friction et constat porte son mode : [trop] · [manquant] · [faux] · [contradictoire])
Choisi par l'utilisateur :
1. {option} …
Écarté : {options | rien}
Dus ouverts par la passe : {`u-…`, `u-…` | aucun — tout fait dans la passe}
```

**Le tableau de l'étape 6 lit ce condensé à la lettre** : les en-têtes de section ci-dessus en
début de ligne, un tag de mode par élément, `**corrigé**` dans un élément corrigé pendant la passe,
les options choisies en liste numérotée, les refs des dus entre accents graves sur la ligne « Dus
ouverts ». Un élément sans tag n'est pas compté.

**Chaque option choisie se fait DANS la passe** : un dû renvoyé à la passe suivante s'ajoute à
ceux qu'elle ouvrira, et la pile ne se solde jamais. Ce qui ne tient pas se fait quand même,
s'écarte avec son motif, ou se confie à la session de son niveau avec une date — jamais « à la
prochaine passe ». Les dus encore ouverts par la passe précédente se soldent en tête de celle-ci.
La ligne « Dus ouverts par la passe » du condensé vise donc « aucun ».

## Étape 6 — Le tableau

La passe finit par une page visuelle, sauf au second passage du même mois, qui n'a pas de condensé.

```bash
python3 ~/.claude/engine/tableau-audit.py --condense ~/.claude/audits/os-audit-AAAA-MM-JJ.md \
  --sortie <scratchpad>/passe-mensuelle.html
```

Le gabarit `TABLEAU.html` porte la mise en page et ne se réécrit pas à la passe. Le script ne sort
que des comptes, des noms de niveau et des refs, jamais un texte de dû ou de constat : une page qui
en montrerait un ne se publie pas.

**Publier la page la fait sortir du poste** : seulement si l'outil `Artifact` est disponible, et sur
l'accord de l'utilisateur, demandé à chaque passe. La première publication pose son URL en pointeur
`p-tableau-passe` au journal de `~/.claude` ; les suivantes font `read` sur cette URL, puis `publish`
du fichier avec cette `url`. Sans l'outil ou sans accord, le chemin du fichier local se donne à
l'utilisateur.

**Fini quand** la page est écrite, et que le condensé nomme son lien publié ou son chemin local.
Script en échec : le dire au condensé.
