---
name: os-audit
description: Audit read-only du système — véracité du contenu (carte de rappel, mémoires, statuts de conception), cohérence du routage (table des domaines ↔ dossiers réels, cascade multi-niveaux), divergence de contenu dépôt↔live, accumulation et duplication, classification durable vs opérationnel. À utiliser quand l'utilisateur dit "audite le système", "os audit", "mon setup est-il périmé", "la carte de rappel dit-elle encore vrai", ou signale que l'assistant rate des choses qui existent pourtant. Complémentaire de selftest.sh et boot-check.sh : ne re-teste pas la plomberie qu'ils couvrent déjà.
argument-hint: "[optionnel : un domaine ou un sous-dossier pour restreindre l'audit]"
---

# Audit du système — dit-il encore vrai ?

Le règlement, la carte de rappel et les mémoires sont des **affirmations** sur ce qui existe et ce qui est courant. Cet audit confronte chaque affirmation à la réalité. Les problèmes de structure sont bruyants ; les problèmes de fraîcheur sont silencieux : « l'assistant oublie des choses » signifie presque toujours qu'il lit fidèlement un index gelé.

**Read-only.** Ne rien corriger, déplacer, renommer ou supprimer pendant l'audit. La seule écriture est le rapport final. Les correctifs viennent après validation.

## Le terrain

Cet audit ne porte pas sur un projet : il porte sur le système lui-même.

- **Dualité dépôt↔live.** Source de vérité = le dépôt `~/.claudeos/` (contenu système dans `~/.claudeos/system/`), recopié vers le live `~/.claude/` où Claude Code lit. Correspondances dans `~/.claudeos/engine/config/SYNC_MAP`. Régimes : `~/.claude` = **additif** (dossier co-habité avec l'outil, du contenu live-only y est normal) ; domaines de travail, `~/resources`, `~/docs` = **miroir** (toute divergence est un écart) ; mémoire automatique = régime spécial. Le dossier de mémoire dérive du dossier personnel et **diffère selon la machine** : le résoudre, jamais l'écrire en dur. L'audit porte sur les **deux** côtés et signale les divergences de **contenu**, pas seulement de présence.
- **Deux couches de règles.** `~/.claude/CLAUDE.md` est la couche *règlement*, payée à chaque session ; `~/.claude/skills/` porte les règles *situationnelles* en compétences, chargées sur déclencheur — la `description` de chacune est ce déclencheur. **Leur nombre se compte dans le dossier et dans la carte de rappel du règlement, jamais ici** — un compteur recopié se périme. Auditer les deux : une compétence absente de la carte a perdu son déclencheur visible, et une règle extraite dont la description ne couvre pas le moment du danger est invisible précisément quand elle protège.
- **Le règlement est une cascade.** `~/.claude/CLAUDE.md` → `~/workstations/<DOMAINE>/CLAUDE.md` → `<projet>/CLAUDE.md`. Chaque niveau prime sur le précédent. `~/.claude/DESIGN.md` porte le comportement voulu du système. Règle de tri : `CLAUDE.md` = règles seules ; `MEMORY.md` = faits datés ; `DESIGN.md` = architecture stable.
- **Mémoire automatique** : `MEMORY.md` (index), `INDEX.md` (deux couches — `## 🧭` curatée à la main, et un bloc `<!-- AUTO:START -->…<!-- AUTO:END -->` régénéré à chaque sauvegarde), `SESSION_JOURNAL.md` (plafond déclaré en tête du fichier), `SESSION_ARCHIVE.md`, `LEARNING_PROPOSALS.md`, `SECURITY_DEBT.md`, `REMINDERS.md`, `ROUTING_MISSES.md`, le marqueur de distillation, et les fichiers thématiques.
- **Cadences.** Aucune tâche planifiée au niveau du système : tout passe par les déclencheurs de `~/.claude/settings.json` et par des rituels exécutés en session.

## Règle dure — dates et fraîcheur

La synchronisation écrase les dates de fichiers en masse. **Les dates du système de fichiers sous `~/.claude`, `~/workstations` et `~/resources` ne sont pas fiables.** Interdit de fonder un diagnostic de fraîcheur sur `find -mtime`, `ls -lt` ou tout équivalent : le faux diagnostic serait quasi systématique. Seuls signaux admis :

- l'historique du dépôt : `git -C ~/.claudeos log`, et `git -C ~/.claudeos log -1 --format=%ci -- <chemin>` pour dater un fichier précis ;
- les dates portées par le **contenu** : en-têtes de séance du journal, mention de génération de la carte de rappel, dates de section, entrées de mémoire.

## Ne re-teste pas la plomberie

`selftest.sh` couvre déjà — et **son nombre de contrôles se compte dans le script, jamais ici** : dérive live↔dépôt sur les chemins du manifeste, régimes de copie, exclusions confidentielles, alarmes de secret, verrou de concurrence, intégrité de copie, alarme sur les binaires, syntaxe des scripts, forme de la carte de rappel, plafonds auto-déclarés des mémoires, poids du bilan de démarrage, poids de la couche toujours-chargée, portabilité des chemins, compétences et carte de rappel alignées dans les deux sens, plafond du journal. Il est lancé par la sauvegarde, qui **refuse de sauvegarder** si un seul contrôle échoue. `boot-check.sh` couvre la carte de rappel absente ou trop vieille, et la présence des dossiers de compétences — **présence seulement, pas contenu**.

Refaire ces contrôles n'apporte rien. L'audit ne vaut que sur ce que ces scripts ne regardent pas :

1. **Véracité du contenu** — une carte de rappel bien formée mais périmée en substance, une mémoire qui affirme un statut dépassé, un « implémenté » sans code derrière.
2. **Cohérence du routage** — table des domaines ↔ dossiers réels, cascade multi-niveaux, chemins morts ou mal dirigés dans les compétences et les déclencheurs.
3. **Accumulation et duplication** — orphelins, doublons, pollution du bloc automatique, plafonds dépassés.
4. **Classification** — la règle de tri et la distinction durable / opérationnel, jamais vérifiées mécaniquement.

**Trois classes de défaut n'ont aucun garde mécanique** et ne sont vérifiées nulle part ailleurs qu'ici : un dossier routé qui n'existe pas ou qui n'a pas son document de référence (check 2) ; l'accumulation de règles sans décision (check 5) ; un fait calculable recopié à la main quelque part (check 6).

**Et un détecteur reste entièrement manuel** : vérifier que les corps des compétences ne sont pas préchargés. Aucun script ne peut le faire — il ne voit pas ce que l'outil injecte dans une session. Le geste : ouvrir une session neuve et chercher le contenu d'une compétence (pas sa seule description, qui est chargée par conception) dans le contexte reçu. Présent = le corpus entier est repayé à chaque session sans que rien ne le signale. À refaire après toute mise à jour de Claude Code, et à la première ouverture sur une machine neuve.

## Pièges de jugement

Ceux-ci visent le raisonnement de l'auditeur, pas le système. Chacun a déjà produit une conclusion fausse en conditions réelles.

- **Un verdict « jamais employé » ne vaut que pour la machine mesurée.** Les compteurs d'usage et les historiques de conversation vivent dans des fichiers exclus de la sauvegarde. Une compétence à zéro usage ici peut être celle qu'on emploie tous les jours ailleurs. Nommer la machine avant de conclure.
- **Un zéro peut venir d'un empêchement, pas d'une absence d'usage.** Un outil déclaré inutilisé sur zéro appel, alors que le zéro venait d'un réglage de permission qui refusait la connexion sans jamais la présenter. Chercher ce qui bloquait avant de conclure à l'inutilité.
- **Un contrôle ou un artefact porte souvent deux choses de valeur inégale.** Séparer avant de trancher : la moitié qui ne sert plus part, l'autre reste.
- **Compter des octets en les appelant caractères inverse un verdict près d'un seuil.** L'écart atteint quelques pour cent sur de la prose accentuée. Vérifier à la main ce qu'un contrôle compte avant de le contredire.
- **Une unité qu'un contrôle ne reconnaît pas produit un faux positif ou un contrôle muet, jamais une erreur.** Vérifier qu'un contrôle de plafond connaît l'unité déclarée avant de croire son verdict.
- **Une suppression voulue se déclare au dépôt.** Sinon la sentinelle de dérive la lit comme une machine en retard et bloque la sauvegarde. Son message le dit ; le lire.
- **Simple n'est pas partiel.** Réduire le nombre de types d'artefacts, jamais la couverture. Quand une simplification ferait sortir du contenu de la couverture, corriger le lecteur plutôt que déplacer le contenu.

## Hygiène — la passe hebdomadaire

**Ce fichier est la seule autorité sur cette procédure.** Le règlement et la conception n'en portent que le déclencheur et le motif, et pointent ici.

La clôture de séance est volontairement réduite à trois gestes (reprise, mémoire, sauvegarde), parce qu'une clôture trop longue est une clôture sautée. Tout le reste vit ici et se fait **une fois par semaine**. Rien n'est supprimé pour autant : ce qui n'est pas fait ici n'est fait nulle part.

À exécuter **avant** les six contrôles, dans cet ordre :

1. **Plomberie** — `bash ~/.claudeos/engine/selftest.sh`. Lire les **avertissements**, pas seulement le verdict : ils ne bloquent rien, donc personne ne les voit sans les chercher.
2. **Retombée documentaire** — `bash ~/.claudeos/engine/impact.sh --since <dernière passe>`. Il rend les **sections** des documents qui nomment ce qui a bougé, triées par force de correspondance. Relire celles marquées à relire, corriger ce qui ne dit plus vrai. Ni une liste vide ni un « tri impossible » ne valent quitus.
3. **Hygiène des mémoires** — parcourir les `MEMORY.md` touchés depuis la passe précédente, repérer ce qui est résolu, obsolète, ou devenu une règle stable ; **faire valider avant tout déplacement**, puis porter dans l'archive du bon niveau à la date du jour. Vérifier à la main le plafond de la mémoire de niveau système — il est **déclaré en tête du fichier avec son unité**, le lire là plutôt qu'en supposer la valeur.
4. **Journal** — compresser les entrées de séance et faire la rotation vers l'archive au-delà du plafond **déclaré en tête du journal**. Toutes les machines écrivent dans le même fichier versionné, donc la passe voit l'ensemble ; les historiques de conversation, eux, restent locaux et ne servent qu'à retrouver un détail sur la machine courante.
5. **Distillation** — relire une semaine de journal, de reprises et de retours, et proposer les règles candidates : proposition, validation, écriture. **Jamais d'auto-règle.** Et **une règle n'entre que si une autre sort** — nommer laquelle, ou dire pourquoi rien ne peut sortir. Inscrire ensuite la semaine courante dans le marqueur de distillation.
6. **Carte de rappel** — mettre à jour la couche curatée, puis sonder trois entrées au hasard : ouvrir la source pointée, vérifier qu'elle existe et qu'elle répond encore à la question. C'est une carte de **questions**, pas un résumé : n'y écrire ni chiffre, ni version, ni date, ni statut.
7. **Ratés de routage** — lire le registre. Non vide = trous de carte à réparer maintenant, puis purger.
8. **Rappels et fils ouverts** — parcourir la vue par ancienneté. **À la troisième reconduction d'un même fil, chercher l'obstacle** au lieu de le reconduire une fois de plus.
9. **Registre des livrables** — `bash ~/.claudeos/engine/build-portfolio.sh`. Rafraîchi ici et pas plus souvent : c'est un fichier qu'aucun script ne lit, sa fraîcheur hebdomadaire suffit. Le geste sert aussi le check 3 — c'est la seule vue qui dise ce qu'on a réellement produit.
10. **Le chargement des corps de compétences est-il toujours paresseux ?** L'audit ne peut pas le vérifier lui-même : il tourne dans une session déjà ouverte, et le fait ne se lit qu'à l'ouverture. Il le **rappelle**, et le rapport porte la réponse de la dernière ouverture connue. Ce détecteur n'a aucun mécanisme : il n'existe que si quelqu'un s'en souvient.
11. **Rangement des fichiers** — le seul geste de cette liste qui **déplace** quelque chose, donc le seul à faire valider avant d'agir. Quatre passes :
    - **Ce qui n'a pas de maison.** Fichier de travail à la racine d'un dossier qui attend des sous-dossiers, export laissé où il est tombé, document daté hors de `docs/`. Le classer, ou dire pourquoi il reste là.
    - **Ce qui traîne d'une séance.** Essais, sondes, témoins, caches, rapports régénérables. **Ne supprimer que ce qu'on a créé, nommément** — jamais en effaçant le dossier qui les contient, qui existait peut-être avant.
    - **Ce qui est vide ou en double.** Souche jamais remplie, dossier vide, fichier de zéro octet, deux fichiers au même propos à deux âges. Une souche vide fait croire à un système plus grand qu'il n'est, et un doublon à deux âges se contredit — c'est le défaut le plus coûteux de ce système.
    - **Ce qui est mal nommé.** Nom non devinable, date absente d'un artefact daté. Renommer coûte des références à réécrire : chercher qui cite le fichier **avant** de le renommer, et se souvenir qu'un renommage dans `~/.claude` ne se propage pas aux autres machines, ce dossier s'y synchronisant en régime additif.

    **Deux interdits.** Ne jamais supprimer dans un `_IGNORE/` sans classer et faire confirmer — c'est hors sauvegarde, donc l'unique exemplaire, sur une seule machine. Et **déclarer au dépôt toute suppression voulue** (`git -C ~/.claudeos rm <chemin>`), sinon la sentinelle de dérive la lit comme une machine en retard et bloque la sauvegarde suivante.

## Contexte du jour

- **Date** : la vraie date du jour ; tout le calcul de fraîcheur en dépend.
- **Périmètre** : tout le système, ou le domaine passé en argument.

## La grille : quatre modes de défaillance, deux couches

Chaque constat de l'audit est un risque sur l'une des quatre façons dont le contexte casse :

- **Poisoning** — du faux là où l'assistant lit, et le modèle traite tout le contexte comme vrai. Un statut périmé affirmé au présent.
- **Bloat** — trop de matière, le fil se perd. Fichiers toujours-chargés obèses, brouillons dans l'arbre de connaissance.
- **Confusion** — il manque ce qu'il faut, ou il y a du hors-sujet. Domaine non routé, règle enterrée dans une mémoire.
- **Clash** — deux morceaux de contexte se contredisent, en général l'ancien contre le nouveau. Fait dupliqué à deux âges, dépôt et live divergents.

Ancrage : poisoning = faux, bloat = trop, confusion = manquant ou déplacé, clash = contradictoire. **Tagger chaque constat avec le mode qu'il alimente.** Un constat qui n'alimente aucun des quatre est probablement cosmétique : le dire, et le classer dernier.

Seconde grille — *quand le contexte charge* :

- **Couche permanente**, chargée à chaque session : la chaîne des `CLAUDE.md`, l'index de mémoire, la couche curatée de la carte de rappel. Chaque mot y est payé à chaque session.
- **Couche situationnelle**, chargée à la demande : conception, mémoires thématiques, journal, reprises, fichiers de projet.

Un fait vivant figé dans un fichier préchargé **pourrira** (poisoning) en taxant chaque session (bloat). Une règle durable enterrée dans un dossier de projet est invisible au moment utile (confusion). C'est l'objet du check 6.

## Étape 0 — Rapport antérieur

1. Chercher les rapports dans `~/.claude/audits/`. S'il en existe, lire le plus récent : le rapport final devra porter une section « Depuis le dernier audit ».
2. Si un audit a tourné dans la semaine, réutiliser ses preuves encore valides et ne re-vérifier que ce qui a pu changer.
3. **Lire le registre des ratés de routage.** Chaque ligne est un endroit où la carte a échoué en conditions réelles — c'est la seule preuve terrain dont dispose l'audit, et elle prime sur toute inspection théorique. En tirer les correctifs durables, les porter dans la liste de correctifs, et **purger les lignes traitées** une fois validées. Registre vide = soit la carte tient, soit la règle de consignation n'est pas appliquée : le dire, plutôt que de conclure au premier.

## Exécution

Pour un audit complet, déléguer : un sous-agent d'exploration par check, avec les instructions du check **verbatim** plus les sections « Terrain », « Règle dure » et « Ne re-teste pas la plomberie », puis fusionner leurs rapports. Pour un périmètre restreint, exécuter les checks soi-même dans l'ordre.

### Check 1 — Dépôt↔live (« les deux côtés disent-ils la même chose ? »)

1. **Le filet tourne-t-il ?** Date du dernier commit de sauvegarde contre la dernière séance du journal. Des séances postérieures au dernier point de sauvegarde = du travail jamais capturé. [clash]
2. **Compétences** : le démarrage ne contrôle que la présence du dossier. Comparer le **contenu** entre dépôt et live, dans les deux sens — une compétence live sans pendant au dépôt n'est jamais sauvegardée ; des contenus différents signifient que la version exécutée n'est pas celle de la source de vérité.
3. **Ce que le manifeste ne couvre pas** : un dossier de travail réel absent du manifeste n'est ni sauvegardé ni synchronisé, et **rien ne le dit**. C'est le défaut le plus silencieux du système. Lister les dossiers de premier niveau et confronter au manifeste.
4. **Contenu live-only sous `~/.claude`** : légitime en régime additif, mais tout ce qui porte de la règle ou de la mémoire doit être au dépôt. Distinguer les deux.

### Check 2 — Routage (« la carte pointe-t-elle le réel ? »)

1. **Table des domaines** → chaque dossier existe, avec son `CLAUDE.md` et son `MEMORY.md`. Sens inverse : un domaine réel absent de la table est invisible pour une session fraîche.
2. **Table des artefacts** → chaque chemin cité existe. Sens inverse, c'est l'invariant du système : tout dossier de premier niveau réel et tout fichier de mémoire doit être atteignable depuis cette table. Vérifier aussi que chaque compétence est dans la carte de rappel et que chaque compétence citée existe — **une compétence orpheline n'a plus de déclencheur visible**.
3. **Cascade** : dans chaque domaine, le règlement local route-t-il vers des projets qui existent ? Chaque niveau déclaré a-t-il ses fichiers ? Cas dur à voir : un projet routé **sans document de référence** — il est atteignable, mais toute question dessus se répond au doigt mouillé. [confusion]
4. **Chemins en dur** dans les règlements, la conception, les compétences et les déclencheurs de `settings.json` : vérifier l'existence. Un chemin **existant mais qui n'est plus le bon** est pire qu'un chemin mort, parce que rien n'échoue.
5. **Capacités mortes** : dossier de compétence dont le fichier n'est pas exactement `SKILL.md`, en-tête sans `description`. Ça ne charge jamais et n'échoue jamais.
6. **Index de mémoire** : chaque entrée résout vers un fichier existant ; les fichiers de mémoire absents de l'index sont des orphelins.

### Check 3 — Véracité du contenu (« la carte et les mémoires disent-elles encore vrai ? »)

1. **Couche curatée de la carte de rappel** : pour chaque entrée, le fichier pointé existe-t-il, et le résumé est-il encore vrai **en substance** ? La plomberie ne vérifie que la forme ; bien formé ≠ vrai.
2. **Bloc automatique** : il est régénéré par balayage et peut référencer des copies périmées. Le compter et le lister, **jamais s'appuyer dessus comme preuve**. [poisoning]
3. **Faits opérationnels affirmés comme courants** dans les mémoires et les reprises : statuts, compteurs, adresses, événements au futur désormais passés. Recouper avec le journal et l'historique du dépôt, signaler ceux qui sont **prouvablement** périmés — ce sont des « derniers états connus », pas des vérités.
4. **Statuts « implémenté » ou « livré »** dans la conception : en sonder trois à cinq contre le code réel. Jamais de statut sur intention seule.
5. **Conclure sur la date qui compte** : « la connaissance du système s'arrête effectivement au … », signaux fiables uniquement.

### Check 4 — Fraîcheur et cadences (« les rituels tournent-ils vraiment ? »)

Aucune tâche planifiée : toute cadence est portée par un déclencheur ou un rituel manuel. Une cadence qui décroche est la cause racine habituelle des gels silencieux ; le dire explicitement.

1. **Distillation** : le marqueur contre la semaine courante, **et** les traces d'exécution réelle (registre des propositions traité, couche curatée mise à jour) — pas seulement le marqueur.
2. **Rappels datés** : échus et non purgés. Ils devaient l'être au traitement. [poisoning]
3. **Dette de sécurité** : entrées ouvertes et leur âge. Vérifier qu'**aucune ne contient une valeur de secret** — seulement identité, emplacement, statut.
4. **Journal** : plafond respecté, tel que déclaré en tête du fichier. Fils ouverts anciens jamais repris → « Questions pour toi ».
5. **Rythme multi-machines** : si le journal montre une machine dont les séances ne sont pas suivies d'un point de sauvegarde, la synchronisation est en risque — une séance sur l'autre machine divergerait.
6. **Outillage externe en retard.** Le système dépend d'outils tiers qui bougent sans prévenir, et **rien ne surveille leur version** : ni la plomberie, ni le démarrage. Comparer **l'installé au publié**, et donner l'écart en versions, pas seulement « à jour / en retard ».
   - **Le proxy économe** : version locale par `rtk --version`, dernière publiée sur `github.com/rtk-ai/rtk/releases`. Mise à jour par le même script d'installation. Après une montée de version, `rtk init -g` remet le déclencheur à jour et réécrit `~/.claude/RTK.md` avec la version de l'outil : **c'est voulu, on la garde — rien à restaurer** (doctrine et pièges dans la compétence `rtk-depannage`).
   - **Les greffons** : versions installées dans `~/.claude/plugins/installed_plugins.json`, dépôts d'origine dans `known_marketplaces.json`. Comparer à ce que publie chaque dépôt. Un cache qui garde plusieurs versions n'est pas un défaut : c'est la version déclarée installée qui compte.
   - **Le dépôt amont des compétences empruntées.** Si une compétence vient d'un dépôt tiers, deux choses à faire et pas une : vérifier que le **mécanisme de contrôle de dérive tourne encore** — un marqueur figé signale un contrôle mort, pas une absence de dérive — et **regarder le dépôt lui-même**, ce qu'aucun mécanisme ne fait : il ne surveille que ce qui est déjà adopté et ne dira jamais qu'une **nouvelle** compétence est apparue.
   - **Ne pas mettre à jour depuis l'audit** : il est en lecture seule. L'écart va dans « Questions pour toi », avec la commande à lancer.
   - **Ne jamais écrire la version constatée dans un fichier** : c'est un fait calculable, il se relit à chaque passage. L'écrire le périmerait à la première mise à jour.

### Check 5 — Accumulation, duplication, organisation

1. **Plafonds déclarés** : les lire en tête de chaque fichier, **jamais supposer la valeur ni l'unité**. Mesurer ; un dépassement est la violation d'une règle écrite, pas une opinion. **Le règlement n'a pas de plafond chiffré** — ne jamais en inventer un : lire le critère d'admission en tête du fichier, et pour le poids, lire les seuils dans la plomberie plutôt que les recopier ici.
2. **Poids de la couche permanente** : c'est la plomberie qui le mesure. L'audit ne refait pas la mesure — il lit le verdict et juge la **tendance** : ce qui s'est réaccumulé depuis le dernier audit, et si la marge restante laisse encore entrer une règle sans extraction.
3. **Doublons** : documents de conception en plusieurs exemplaires, deux dossiers au même propos, fichiers de mémoire redondants avec une règle déjà promue au règlement. Recommander le canonique pour chaque paire.
4. **Orphelins et souches** : projet sans règlement ni routage, dossiers vides, fichiers de zéro octet, réceptacle confidentiel manquant à la racine d'un dossier **projet** — jamais au niveau d'un sous-dossier, un seul réceptacle par projet, sinon le premier document confidentiel atterrit en zone synchronisée.
5. **Contamination par les brouillons** : fichiers temporaires, dumps, caches, exports d'une séance laissés dans l'arbre de connaissance, où une recherche aveugle les prendra pour du savoir.
6. **Test d'intuitivité** : prendre trois artefacts récents que l'utilisateur demanderait plausiblement, et descendre l'arborescence comme un humain, sans recherche. Un dossier au nom non devinable, ou un artefact trouvé par détour, est un constat.

### Check 6 — Classification et placement (« la règle de tri est-elle respectée ? »)

Personne ne la vérifie mécaniquement.

1. **Règlements, tous niveaux** : des règles, uniquement. Signaler tout narratif, résumé, fait daté ou statut.
2. **Mémoires** : entrées « comportement voulu » sans contrepartie dans la conception ; règles de comportement enterrées en mémoire et jamais promues — **aucune session fraîche ne les verra**. [confusion]
3. **Conception** : faits opérationnels (statuts vivants, adresses, compteurs) qui relèvent de la mémoire. Le correctif est un **pointeur**, jamais une copie plus fraîche.
4. **Durable contre opérationnel** : un fait opérationnel formulé comme durable dans la couche permanente = poisoning garanti, plus bloat à chaque session.
5. **Un fait calculable recopié à la main** : un compte, une taille, un seuil. Il devient faux sans prévenir, et rien ne le signale.
6. **Précédence** : sonder trois à cinq faits importants à travers les niveaux. Vivent-ils en un seul endroit plus des pointeurs, ou en plusieurs copies à plusieurs âges ? Plusieurs âges = clash, et la copie la plus vieille est le risque de poisoning.

## Sortie — le rapport

Afficher dans la conversation, puis enregistrer dans `~/.claude/audits/os-audit-AAAA-MM-JJ.md` (créer le dossier si besoin ; c'est la seule écriture de cette compétence).

```
# Audit du système — {date}

**Connaissance du système à jour jusqu'au : {date effective du check 3}**

| Check | Verdict | Pire constat |
|---|---|---|
| Dépôt↔live                  | VERT/ORANGE/ROUGE | … |
| Routage                     | VERT/ORANGE/ROUGE | … |
| Véracité du contenu         | VERT/ORANGE/ROUGE | … |
| Fraîcheur et cadences       | VERT/ORANGE/ROUGE | … |
| Accumulation et duplication | VERT/ORANGE/ROUGE | … |
| Classification et placement | VERT/ORANGE/ROUGE | … |

## Exposition aux modes de défaillance

| Mode | Exposition | Alimenté par |
|---|---|---|
| Poisoning (faux)                 | HAUTE/MOYENNE/BASSE | {les constats qui l'alimentent} |
| Bloat (trop)                     | HAUTE/MOYENNE/BASSE | … |
| Confusion (manquant ou déplacé)  | HAUTE/MOYENNE/BASSE | … |
| Clash (contradictoire)           | HAUTE/MOYENNE/BASSE | … |

## Depuis le dernier audit
{seulement si un rapport antérieur existe : corrigé / aggravé / nouveau. Omettre au premier passage.}

## Ce qui te ferait donner une mauvaise réponse aujourd'hui
{2 à 4 puces : les constats qui produisent « il dit que ça n'existe pas alors que c'est là »,
ou des réponses périmées assurées}

## Constats par check
{puces concises ; chaque constat nomme un chemin concret ET finit par son tag
[poisoning] [bloat] [confusion] [clash]}

## Questions pour toi
{ce que seul le propriétaire peut trancher : élément abandonné volontairement ?
fil ouvert encore vivant ? statut réel d'un « implémenté » douteux ?}

## Liste de correctifs (par lots, attendre validation)
- Lot A — sécurité et capacités mortes (en premier)
- Lot B — routage, manifeste, réconciliation dépôt↔live
- Lot C — rattrapage de contenu (carte de rappel, mémoires périmées, statuts, purge des rappels)
- Lot D — durabilité : promouvoir en contrôle mécanique tout constat vérifiable par un script,
  pour que ça ne regèle plus en silence
```

**Règles de verdict.** ROUGE = au moins un constat qui produirait une mauvaise réponse aujourd'hui : carte mentant en substance, routage mort ou mal dirigé, travail live jamais capturé au dépôt, fait périmé dans un fichier toujours-chargé, valeur de secret dans l'arbre sauvegardé. ORANGE = dérive qui y mène. VERT = vérifié et propre. Un élément que l'utilisateur confirme abandonné ne compte plus pour ROUGE une fois que le système cesse de le présenter comme courant. **Être honnête : un premier passage sur un système réellement utilisé est rarement tout vert.**

**Règles d'exposition.** Un mode est HAUTE quand un constat ROUGE l'alimente, MOYENNE quand seuls des ORANGE l'alimentent, BASSE sinon. Ce tableau est le moment pédagogique de l'audit : pas seulement ce qui est cassé, mais **comment ça mordra**.

## Notes

- **Ne rien corriger pendant l'audit, même trivial.** Le rapport d'abord ; la liste de correctifs est le livrable.
- L'application des correctifs suit les règles du système : une modification de fond de la conception s'écrit directement, le niveau d'une règle émergente se tranche avec l'utilisateur, et jamais de valeur de secret dans l'arbre.
- Rappel de la règle dure : **aucun verdict de fraîcheur fondé sur une date de fichier.** En cas de doute, l'historique du dépôt fait foi.
- Un instantané local d'une donnée dont la source vive est un service externe est un problème d'**étiquetage**, pas de fraîcheur : le correctif est la mention « instantané — le vivant est dans X », pas une re-synchronisation sans fin.
- **Relancer une fois par semaine**, ou après toute réorganisation. Le démarrage le signale au-delà du délai. La section « Depuis le dernier audit » est le gain des rapports datés.
