# Conception du système

> Ce document décrit **le système que tu as reçu** : ce qu'il fait, pourquoi il le fait ainsi, et où chaque chose vit. Il ne raconte pas l'histoire de son auteur — les décisions y sont énoncées, pas justifiées par des incidents que tu n'as pas vécus. Le raisonnement qui a produit chaque règle vit dans `RULES_CATALOG.md`, avec sa condition d'existence.
>
> Écris ici tes propres décisions d'architecture au fur et à mesure. Un système dont la conception n'est pas écrite redevient une accumulation en quelques semaines.

## 1. Ce que ce système est

Une configuration d'assistant qui **survit à la fermeture d'une session**. Quatre buts, et rien d'autre :

1. **Se souvenir** — des faits, des décisions et de leur date, sans les redemander.
2. **Ne pas mentir** — distinguer ce qui est vérifié de ce qui est supposé, et le dire.
3. **Ne rien perdre** — sauvegarde et synchronisation entre postes, avec des garde-fous qui refusent plutôt que d'écraser.
4. **Ne rien laisser fuir** — ce qui est confidentiel ne quitte pas la machine.

Tout ce qui ne sert aucun de ces quatre buts est du poids. C'est le critère qui tranche quand on hésite à ajouter quelque chose.

## 2. Architecture — deux copies, un manifeste

Le système vit à **deux endroits** : les fichiers **vivants**, là où l'assistant les lit, et le **dépôt**, versionné et poussé sur un serveur distant. Ils ne sont pas le même arbre.

Les correspondances entre les deux sont déclarées dans un **manifeste unique**, `engine/config/SYNC_MAP` — une ligne par dossier. Ajouter un domaine de travail se fait en ajoutant une ligne, jamais en modifiant un script. C'est la règle qui a le plus de valeur ici : **aucune liste de dossiers n'est écrite en dur dans le code**. Un système qui duplique son périmètre finit par en oublier une partie, et l'oubli ne se manifeste par rien.

Trois régimes de copie :

- **miroir** — le dépôt reflète exactement le local, suppressions comprises. Pour les dossiers dont tu es seul auteur.
- **additif** — jamais de suppression. Pour les dossiers qu'un outil partage avec toi et où il dépose ses propres fichiers.
- **mémoire** — régime dédié, avec une garde contre l'écrasement. Voir §7.

## 3. Sauvegarde — le local vers le dépôt

### 3.1 Le verrou : rien ne part sans décision

Le dépôt ignore **tout** par défaut, et n'autorise que par exceptions nommées. C'est une liste blanche, pas une liste noire, et l'inversion est le point important : une liste noire laisse passer ce qu'on n'a pas pensé à interdire, ce qui est exactement la catégorie qui fuit.

Conséquences à connaître, toutes les deux contre-intuitives :

- **Un fichier neuf est refusé en silence.** La sauvegarde annonce ce qu'elle a refusé, en fin d'exécution. Cette sortie doit être lue : c'est le seul endroit où le refus se voit.
- **Les fichiers déjà suivis continuent de partir**, même s'ils ne figurent dans aucune exception. Le verrou ne gouverne que la nouveauté. Un fichier qui part aujourd'hui ne prouve donc pas qu'une règle l'autorise.

### 3.2 Quatre gardes, et une leçon

La sauvegarde refuse avant de committer si elle détecte : un **binaire neuf** (contenu non scannable), un **nom de fichier évocateur d'un secret**, un **contenu ressemblant à un secret**, ou un **fichier texte de données** — la catégorie par laquelle des documents confidentiels fuient.

**Une exception vaut pour tous les gardes, pas pour le premier rencontré.** Autoriser un fichier dans le verrou ne suffit pas si une alarme le refuse aussi par un autre moyen. Chercher le chemin, le format et le nom du garde dans tout le moteur avant de conclure qu'un fichier est autorisé.

Devant un refus : présenter chaque fichier signalé, décider un par un — faux positif, document confidentiel à déplacer, ou suppression — puis relancer. Jamais de contournement global.

### 3.3 Le réceptacle confidentiel

Un dossier `_IGNORE/` à la racine de chaque projet, hors sauvegarde et hors synchronisation. C'est là que vont les documents qu'on ne peut pas versionner.

**Ce qu'il faut en savoir avant de s'en servir** : son contenu est le seul exemplaire, sur une seule machine. Aucun historique ne rattrape une suppression. Classer avant de supprimer, et faire confirmer.

### 3.4 Secrets

Trois interdits, dans la couche de règles et pas seulement ici : jamais de valeur de secret en clair dans une session ni dans un fichier sauvegardé ; la classification — valeur faible ou forte — se demande toujours à l'utilisateur ; un secret exposé une fois est compromis, il se régénère et l'affaire se consigne.

Un emplacement dédié, `~/.claude/secrets-shared/`, peut porter des secrets de **faible valeur** — clés de test, bacs à sable. Il est **local à chaque machine et ne voyage pas** : le verrou l'exclut nommément, et l'alarme de secret de la sauvegarde ne s'y applique pas. Les deux vont ensemble — c'est parce que rien n'en sort qu'on peut y déposer sans que l'alarme crie.

Ce choix est délibéré et il a un coût : les clés de test se reposent sur chaque poste. Il a été tranché ainsi parce qu'un système livré ne décide pas à la place de son utilisateur de pousser des secrets dans un dépôt git, même privé, même de faible valeur. Qui veut l'inverse ajoute une ligne d'autorisation au verrou — c'est une décision à prendre et à écrire, pas un réglage par défaut.

Les secrets de valeur forte restent hors de l'arbre sauvegardé, sans exception.

## 4. Synchronisation — le dépôt vers le local

### 4.1 « À jour côté dépôt » n'implique pas « à jour côté local »

Deux états distincts, et les confondre a coûté cher. Un poste peut avoir récupéré tous les commits sans jamais avoir appliqué leur contenu sur ses fichiers vivants. L'application s'exécute donc **systématiquement**, y compris quand le dépôt est déjà à jour.

### 4.2 Filet avant écrasement

L'application écrase les fichiers vivants divergents. Avant de le faire, elle en dépose une copie datée dans un dossier de secours. **Cette copie est périmée par construction** : elle date d'avant une synchronisation, elle n'est jamais une source de vérité, seulement un moyen de récupérer quelque chose qu'on n'aurait pas dû perdre.

### 4.3 Ce qui ne peut pas s'automatiser

Certaines actions ne peuvent pas être faites depuis le poste courant — une installation dans une interface graphique, une action sur un autre système. Elles vivent dans une file de rattrapage par poste, cochée quand c'est fait. Tout le reste — installation d'outil, ligne de configuration — se déclare dans la checklist idempotente qui s'exécute à la fin de chaque synchronisation, et s'applique alors seule sur tous les postes.

### 4.4 Dérive

Un module unique compare les deux copies et rend deux classes : ce qui est au dépôt et **absent** en local (la synchro n'a jamais été appliquée), et ce qui diffère en **contenu** (une édition locale non sauvegardée). La comparaison porte sur le contenu et non sur l'horodatage, et honore le même fichier d'exclusion que la sauvegarde — sans quoi elle signale à perpétuité des fichiers volontairement non suivis.

Cette mesure est lue par trois consommateurs : la synchronisation, l'autotest et le démarrage. Le démarrage la recalcule **à l'état courant** au lieu de rejouer le verdict de la dernière synchro : une dérive apparue après une synchro réussie ne serait vue par personne.

### 4.5 Un seul poste actif à la fois

Le modèle est séquentiel. On tire avant de produire, et la sauvegarde **refuse de tourner depuis un poste en retard** — elle committerait des fichiers périmés par-dessus du travail plus récent fait ailleurs. Ne pas outrepasser ce refus.

### 4.6 Ajouter un poste

Le dépôt ne sert pas qu'à sauvegarder : c'est aussi **le véhicule** entre les machines. Ajouter un poste, c'est donc récupérer, jamais réinstaller.

Sur la nouvelle machine, `install.sh`, avec **la même URL de dépôt** qu'ailleurs. Il reconnaît un dépôt déjà habité par ce système et bascule seul : il clone, inscrit la machine au registre des postes, projette la configuration sur `~/.claude` et les dossiers de travail, puis pose ce qui ne voyage pas — le proxy, les déclencheurs de l'outil, le réceptacle des secrets locaux.

Ce qu'il ne fait pas, et pourquoi : **il ne repose aucune question de personnalisation.** Les réponses existent, elles sont dans le dépôt. En reposer les questions produirait une deuxième série de réponses, et deux réponses à deux âges se contredisent — c'est exactement le défaut que tout le reste de ce document cherche à éviter.

Un seul cas demande une action supplémentaire : si le règlement a été assemblé quand il n'y avait qu'une machine, il ne porte pas les règles de travail à plusieurs postes. Elles s'ajoutent en relançant l'entretien **une fois, sur la machine d'origine**.

## 5. Démarrage

### 5.1 Ce qu'il fait, et ce qu'il ne fait pas

À l'ouverture d'une session, le système calcule son état et l'injecte dans le contexte : retard en commits, état de la mémoire, dernière session, ce qui reste à faire. **Il n'agit jamais seul** — il propose la commande, l'utilisateur décide. Une mutation automatique au démarrage écraserait du travail local sans que personne ne l'ait demandé.

### 5.2 Sondes de plomberie

Une machinerie qui casse en silence est pire qu'une absence de machinerie. Le démarrage émet un avertissement visible pour : une dépendance absente, une sauvegarde automatique en erreur ou muette depuis trop longtemps, une synchronisation incomplète, un journal périmé, une dérive à l'état courant, un rappel daté arrivé à échéance, une dette de sécurité non traitée.

Ces sondes sont en **lecture seule**. Elles observent l'état du poste ; elles ne testent pas la plomberie. C'est le rôle de l'autotest.

## 6. Autotest — ce qui bloque et ce qui avertit

L'autotest s'exécute **avant chaque sauvegarde** et la refuse s'il échoue. D'où une ligne de partage qui doit être tenue :

- **Avertit — ce qui encombre.** Un plafond de rangement dépassé, un inventaire incomplet, une reprise manquante. Rien n'est désactivé, rien n'est perdu, et ça se range plus tard. Bloquer là-dessus fait payer un défaut de rangement par la perte d'une journée de travail.
- **Bloque — ce qui désactive en silence.** Une règle présente mais jamais chargée, un chemin cité par une règle et absent du disque, une copie partielle, un secret en partance.

Le discriminant n'est pas la gravité ressentie mais la **détectabilité** : ce qui encombre se voit, donc un avertissement suffit ; ce qui désactive ne se manifeste par rien, donc seul un blocage l'attrape.

**Un contrôle neuf n'est pas vérifié tant qu'il n'a pas échoué exprès.** Introduire volontairement le défaut qu'il cherche, et constater qu'il crie. Un contrôle qui n'a jamais crié peut ne regarder rien.

**Un faux positif diagnostiqué se corrige dans la séance**, ou l'on écrit pourquoi on ne le corrige pas. Un contrôle qui crie à tort ne bloque pas : il apprend à être ignoré, et emporte les vrais signaux avec lui.

**Les seuils de poids se calibrent, ils ne s'héritent pas.** Trois alarmes surveillent la taille de ce qui est chargé à chaque session. Leur valeur n'a de sens que rapportée à un corpus précis : trop haute, l'alarme ne parle jamais ; trop basse, elle crie sur du travail ordinaire — et c'est le pire des deux, puisqu'un signal dont on sait qu'il ne veut rien dire apprend à ignorer la catégorie entière. `calibrate.sh` mesure l'assiette réelle et pose le point zéro dans `engine/config/SEUILS`. À lancer après l'installation, après l'assemblage du règlement, et après toute réorganisation voulue. **Jamais pour faire taire une alarme** : relever un seuil parce qu'il sonne est un contournement, et il sonnerait au double.

## 7. Mémoire

### 7.1 Deux couches

La couche **curatée**, écrite à la main : les faits durables, les décisions, les préférences. La couche **générée**, refaite à chaque sauvegarde : la carte de rappel, ce qui reste à faire par ancienneté, le fil du temps par projet, le journal des dernières sessions. Ne jamais éditer la seconde — elle sera écrasée.

### 7.2 Faits durables et faits vivants

Sont **durables** : l'identité, les préférences, le but d'un projet. Sont du **dernier état connu**, et se revérifient à leur source avant toute action conséquente : ce que contient un dossier, l'état d'un déploiement, le statut d'une demande externe, ce qui reste à faire. Un fait vivant écrit sans sa date et sa source est à revérifier, pas à croire.

### 7.3 Un fait vit en un seul lieu

Un comportement de l'assistant va dans la couche de règles. Un fait daté va dans la mémoire. Une décision d'architecture va ici. Deux copies à deux âges se contredisent, et c'est toujours la mauvaise qui est lue.

Corollaire : **un fait calculable ne s'écrit pas, il se lit.** Un compte, une taille, un seuil recopié dans un document devient faux sans prévenir.

## 8. Boucle d'apprentissage

C'est la partie qui distingue ce système d'un simple fichier de consignes, et **c'est elle qui compte à long terme** : les règles que tu as reçues viennent des incidents de quelqu'un d'autre, celles qui te serviront viendront des tiens.

Le cycle : un retour de l'utilisateur est **consigné**, pas appliqué à la volée. Les candidats s'accumulent dans un registre. Une **distillation** périodique décide lesquels deviennent des règles, lesquels partent en fiche sur déclencheur, et lesquels sont abandonnés. Le motif de chaque promotion est écrit dans un registre des origines — sans lui, une règle devient intouchable parce que plus personne ne sait pourquoi elle existe.

Un **audit** périodique relit l'ensemble : ce qui est affirmé est-il encore vrai, ce qui est routé existe-t-il, ce qui s'accumule sert-il encore. Il ne teste pas la plomberie, que l'autotest couvre déjà.

Registres livrés vides : candidats, origines, ratés de recherche, idées mises de côté.

## 9. Couche de règles

Trois niveaux, et la distinction entre eux est ce qui empêche le système de regrossir :

- **Le règlement** (`CLAUDE.md`) — chargé à **chaque** session, donc payé à chaque session. Une règle n'y entre que si son omission ferait commettre une erreur dans une session qui ne charge rien d'autre, **ou** si c'est une chose qui ne peut pas se convoquer elle-même — l'identité, la voix, la conduite par défaut, pour lesquelles aucun déclencheur ne dira jamais « sois toi ».
- **Les fiches** — chargées sur **déclencheur** seulement. Tout le reste va là. Une fiche sans déclencheur déclaré dans le règlement est une fiche qui ne se charge jamais : c'est un défaut qui bloque, parce qu'il ne se manifeste par rien.
- **Le catalogue** (`RULES_CATALOG.md`) — pour chaque règle, son énoncé, son motif et sa condition d'existence. C'est la notice de ton propre système : une règle dont la condition ne tient plus est une règle à retirer.

### Inventaire des fiches

Une fiche présente ici mais absente de la table des déclencheurs ne se charge jamais. Les deux listes se tiennent à jour ensemble.

| Fiche | Ce qu'elle porte |
| :--- | :--- |
| `MEMOIRE_ET_VERITE.md` | Écrire un fait, un statut, une décision ; toucher une source de vérité. |
| `FICHIERS_ET_NOMMAGE.md` | Créer, nommer, déplacer, supprimer un fichier ou un dossier. |
| `SECRETS_DETAIL.md` | Régimes de stockage d'un secret, et conduite devant un refus de sauvegarde. |
| `SESSION.md` | Reprise de contexte, distillation, clôture de séance. |
| `CONTROLES_ET_ALARMES.md` | Écrire, modifier ou désarmer un contrôle mécanique. |
| `LIVRABLES.md` | Produire un document destiné à un tiers, y avancer un fait sourcé. |
| `RTK_DEPANNAGE.md` | Panne ou mesure du proxy économe en jetons. |

Il n'y a **pas de plafond chiffré** au règlement. C'est le critère d'admission qui décide. Le poids est mesuré et affiché ; il avertit, il ne bloque pas.

## 10. Procédures

**Créer un domaine de travail** : un dossier, son fichier de règles local, sa mémoire, sa reprise, son réceptacle confidentiel, et **une ligne dans le manifeste** — sans elle, le dossier n'est ni sauvegardé ni synchronisé, et rien ne le dira.

**Clôturer une séance** : la reprise, la mémoire, la sauvegarde. L'entrée de journal s'ajoute brute. Elle doit exister et rester anonyme — le journal part au dépôt distant.
