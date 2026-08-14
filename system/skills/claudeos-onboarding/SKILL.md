---
name: claudeos-onboarding
description: Entretien d'installation du système — à lancer UNE FOIS après install.sh, et rejouable ensuite quand une condition change (nouvelle machine, nouveau domaine, premiers livrables). Établit qui est l'utilisateur, sur quoi il travaille et quel assistant il veut, puis assemble son fichier de règles à partir du catalogue en ne gardant que les règles dont la condition est vraie. Déclencheurs — « /claudeos-onboarding », « installe mon système », « personnalise ma configuration », « rejoue le grill », « j'ai une deuxième machine maintenant ».
---

# Entretien d'installation

`install.sh` a posé la machinerie. Il reste ce qu'un script ne peut pas faire : savoir qui tu as en face.

## Avant de commencer — trois choses à te dire

**Cette compétence est rejouable.** Les réponses ne sont pas gravées : elles décrivent un état, et l'état change. Une deuxième machine, un premier client, un premier document qui sort de chez toi — chacun rend vraie une condition qui était fausse. Relance-la à ce moment-là plutôt que de deviner quelle règle te manque.

**Tu ne pars pas d'une page blanche mais d'un héritage.** Les règles proposées viennent d'un autre système, où chacune est née d'un incident précis. Aucune n'a été méritée par toi. C'est le défaut fondamental de ce transfert, et le seul remède est la boucle d'apprentissage : tes propres incidents produiront tes propres règles. `RULES_CATALOG.md` porte, pour chaque règle, le motif qui l'a fait naître.

**Rien n'est appliqué sans être montré.** À chaque étape, ce qui va être écrit est présenté avant de l'être.

**Si la personne dit « j'ai une deuxième machine », commencer par distinguer deux choses.** Elles se confondent facilement et le remède n'est pas le même :

- **Installer le système sur la nouvelle machine** — ce n'est pas le travail de cet entretien. Là-bas : relancer `install.sh` depuis le dossier du squelette, et donner **la même URL de dépôt**. Le script reconnaît un dépôt déjà habité, clone, inscrit la machine au registre des postes et projette la configuration. Il ne repose aucune question : la configuration existe, elle est récupérée. **Ne jamais rejouer l'entretien sur la nouvelle machine** — il produirait une deuxième réponse aux mêmes questions, et deux réponses à deux âges se contredisent.
- **Faire entrer les règles de travail à plusieurs postes** — ça, c'est ici, et ça se fait **une seule fois, sur la machine d'origine**. C'est la condition `MULTIPOSTE` de la phase 2.

## Phase 1 — Qui tu es

Quatre questions, une à la fois, par l'outil de question et jamais en prose. Chaque option porte sa conséquence.

1. **Ton métier et ton contexte** — de quoi tu vis, dans quel type d'organisation. Ce qui détermine le vocabulaire que l'assistant peut employer sans traduire.
2. **Ton rythme** — as-tu des créneaux de travail distincts, et lesquels. Ce qui permet de ne jamais te proposer un travail impossible dans le créneau courant. La réponse a une seconde destination, machine celle-là : le fichier des créneaux, écrit en phase 2 une fois les domaines nommés — pas ici, un créneau se rattache à un domaine.
3. **Ton niveau technique, par domaine** — où tu es expert, où tu es débutant. Ce qui détermine quand l'assistant explique et quand il se tait.
4. **Ce qui t'agace chez un assistant** — question ouverte, en prose, la seule de tout l'entretien. C'est celle qui rendra le persona juste, et un menu d'options y présupposerait justement ce qu'on cherche.

**Écrire** : un fichier par fait dans le dossier de mémoire automatique, plus une ligne d'index. Ne jamais entasser ces réponses dans un seul fichier — la mémoire se relit par fait, pas par entretien.

## Phase 2 — Sur quoi tu travailles

### Les quatre questions de condition

Elles décident quelles règles entrent. Poser les quatre, même si une réponse paraît évidente : c'est la personne qui répond, pas toi.

| Question | Condition | Ce qu'elle fait entrer |
| :--- | :--- | :--- |
| Travailles-tu depuis plusieurs machines ? | `MULTIPOSTE` | Les règles de séquencement — un seul poste actif, tirer avant de produire, ne jamais sauvegarder depuis un poste en retard. Et l'interdiction des chemins propres à une machine. |
| As-tu plusieurs domaines de travail bien distincts ? | `MULTIDOMAINE` | La table de routage et ses règles de chargement. Sans elle, une seule couche de règles pour tout. |
| Produis-tu des documents destinés à d'autres que toi ? | `LIVRABLE` | La compétence des livrables, et la règle de bascule en ton neutre. |
| Manipules-tu des documents que tu ne peux pas versionner ? | `CONFIDENTIEL` | Le réceptacle local et ses règles de suppression. |

**Ce qui n'est pas demandé, et pourquoi.** La mémoire, la plomberie et le code sont tenus pour vrais : le moteur est livré et l'installation a posé ses hooks, donc « non » n'est pas une réponse possible. Le proxy économe est détecté par le script. **Les règles sur les secrets et le recontrôle des rapports d'agents ne sont jamais conditionnées** — quelqu'un qui répond « je ne manipule pas de secrets » et colle un jeton trois semaines plus tard n'aurait aucune règle au moment précis où l'absence de règle est définitive.

### La profondeur des dossiers de travail — à demander avant la table

**Question à poser, une seule, et sa réponse commande tout le reste de cette phase :** combien de niveaux tes dossiers de travail ont-ils ?

| Réponse | Forme | Pour qui |
| :--- | :--- | :--- |
| **Un seul** | `~/workstations/<DOMAINE>/` | Un domaine par sujet, sans sous-découpage. Un fichier de règles, une mémoire, une reprise par domaine. |
| **Deux** | `~/workstations/<DOMAINE>/<PROJET>/` | Un domaine porte plusieurs projets qui ont chacun leur contexte propre. Le niveau projet porte sa mémoire ; le domaine ne porte que ce qui vaut pour tous ses projets. |
| **Trois ou plus** | `~/workstations/<DOMAINE>/<PROJET>/<COMPOSANT>/` | Un projet se subdivise en objets qu'on ouvre séparément — applications, services, produits livrables distincts. |

Trois choses en dépendent, et aucune ne se rattrape facilement plus tard :

- **La cascade de chargement.** Les règles locales priment sur les globales, niveau par niveau. À trois niveaux, une demande charge trois fichiers de règles et trois mémoires ; à un seul, une seule. Annoncer une profondeur qu'on n'a pas fait chercher des fichiers qui n'existent pas ; en annoncer moins qu'on en a fait travailler l'assistant sur un contexte tronqué sans qu'il s'en aperçoive.
- **Où va un fait.** Un fait qui vaut pour tout un domaine n'a rien à faire dans la mémoire d'un de ses projets, et l'inverse est pire — un fait de projet écrit au niveau du domaine devient un faux pour ses voisins.
- **Ce que le manifeste de sauvegarde doit couvrir.** Il liste des racines, pas des feuilles ; mais un niveau intermédiaire oublié emporte tout ce qu'il contient.

**Ne pas deviner cette réponse à partir du nombre de domaines cités.** Quelqu'un peut avoir un seul domaine et trois niveaux dedans, ou six domaines tous plats. La profondeur et la largeur sont deux questions distinctes, et les confondre produit une arborescence que la personne n'a pas demandée.

**Le nombre de niveaux se change plus tard**, mais il faut alors déplacer des dossiers et réécrire la table. Le dire au moment de poser la question : c'est le genre de choix qu'on fait mieux en sachant ce qu'il coûte de revenir dessus.

### La table de routage

Si `MULTIDOMAINE` est vrai : une ligne par domaine, avec son dossier, **à la profondeur retenue ci-dessus**. Créer chaque dossier avec son fichier de règles local, sa mémoire, sa reprise et son réceptacle confidentiel.

Aux niveaux intermédiaires, ne créer que ce qui a un contenu propre : un niveau qui n'existe que pour en contenir un autre n'a besoin ni de mémoire ni de reprise. Une mémoire vide à chaque étage est du bruit qu'il faudra lire à chaque reprise.

**Et une ligne au manifeste de sauvegarde pour chacun.** C'est l'étape qu'on oublie, et son oubli ne se manifeste par rien : le dossier existe, on y travaille, il n'est simplement jamais sauvegardé. Vérifier après création que chaque domaine y figure.

### Les créneaux

Reprendre la réponse « rythme » de la phase 1 et l'écrire dans `~/.claudeos/engine/config/CRENEAUX` — une ligne par domaine qui a des jours attitrés, au format que le fichier documente en tête : `NOM_DU_DOMAINE  lun,mar`. Un domaine sans jours attitrés ne reçoit pas de ligne : absent du fichier, il est proposable tous les jours. Sans domaine du tout, le fichier reste vide — rien à filtrer.

C'est ce fichier que les scripts lisent : le bilan de démarrage y prend le filtre du jour, le générateur de fils ouverts l'unité d'ancienneté. Le fichier de mémoire écrit en phase 1 porte le rythme en prose, comme fait durable — jamais comme source des scripts ; un changement de rythme se pose d'abord ici.

## Phase 3 — Quel assistant tu veux

Invoquer la compétence de grill. Douze rubriques, dont les énoncés génériques sont déjà dans le fichier de règles ; l'entretien remplit le réglage de chacune.

Ne pas expédier cette phase : c'est la seule qui produise quelque chose qui n'existe nulle part ailleurs. Les règles, on peut les relire ; un persona mal réglé se subit sans savoir pourquoi.

**Un point à énoncer honnêtement pendant l'entretien** : le corpus de règles hérité est écrit dans une voix — dense, aphoristique. Même vidé de son contenu, il enseigne un style par imitation. Le persona construit ici en sera teinté. On ne peut pas l'éviter, on peut le savoir.

## Phase 4 — Assembler

### Le fichier de règles

Il est livré en **gabarit**, avec les règles conditionnelles entre marqueurs. **L'assemblage ne se fait pas à la main** — un retrait improvisé à chaque installation ne se vérifie pas, et son erreur, règle manquante ou règle sans objet, ne se manifeste par rien.

```bash
bash ~/.claudeos/engine/assemble-rules.sh --vraies MULTIDOMAINE,CONFIDENTIEL
```

La liste ne contient que les conditions **vraies**, séparées par des virgules, éventuellement vide. Le script :

- retire les blocs dont la condition est fausse, et **les marqueurs des blocs conservés** ;
- retire les compétences devenues sans objet **et leur ligne de déclencheur ensemble** — une ligne de déclencheur sans compétence envoie vers le vide, une compétence hors de la carte de rappel a perdu son déclencheur visible, ce sont les deux moitiés du même défaut ;
- refuse une condition inconnue plutôt que de l'ignorer, parce qu'une faute de frappe retirerait en silence le bloc qu'on voulait garder ;
- vérifie qu'aucun marqueur ne subsiste, et échoue s'il en reste.

Lire son compte rendu : il dit combien de blocs sont conservés, lesquels sont retirés, et quelles compétences sont parties.

**Ce qui reste à faire à la main après lui** : remplir la table de routage et le bloc persona. **Ne pas renuméroter les sections** — les compétences y renvoient par numéro, et une section déplacée casse un renvoi en silence.

### Recalibrer les alarmes de poids

```bash
bash ~/.claudeos/engine/calibrate.sh
```

**À lancer après l'assemblage, et pas avant.** Le système surveille le poids de ce qui est chargé à chaque session, pour attraper une réaccumulation silencieuse. Ses seuils ont été posés à l'installation, sur un règlement encore à l'état de gabarit — donc plus gros que celui qui vient d'être assemblé. Laissés là, ils laisseraient passer une dérive entière avant de parler.

Ne jamais le relancer pour faire taire une alarme : une alarme qui sonne demande qu'on regarde ce qui a grossi, pas qu'on relève la barre. Elle resonnerait au double.

### Vérifier

```bash
bash ~/.claudeos/engine/selftest.sh
```

Il vérifie notamment que les compétences présentes et la carte de rappel se répondent, et que tout chemin cité par une règle existe. C'est le contrôle qui attrape ce que l'assemblage a pu casser.

## Phase 5 — La preuve

```bash
bash ~/.claudeos/engine/backup.sh
```

**Ne pas sauter cette étape et ne pas la déclarer faite sans l'avoir lue.** Une installation qui n'a pas prouvé qu'elle sait sauvegarder n'est pas une installation, c'est une promesse.

Deux choses à lire dans sa sortie, pas seulement le succès final :

- **Le rapport de refus.** La sauvegarde ignore tout par défaut et n'autorise que par exceptions. Tout fichier neuf hors exception est refusé, et **ce rapport est le seul endroit où ce refus se voit**. S'il nomme quelque chose qui devrait être sauvegardé, c'est maintenant qu'il faut ajouter la ligne.
- **Le push.** Un commit local n'est pas une sauvegarde tant qu'il n'est pas parti.

## Pour finir

Dire à la personne, en clair :

- Ce qui a été écrit, et où.
- **Quelles règles ont été écartées et pourquoi** — c'est l'information la plus utile de tout l'entretien, et la seule qu'elle ne pourra pas retrouver seule. Une règle absente ne se manifeste par rien.
- Que `RULES_CATALOG.md` porte la condition de chacune, et que relancer cet entretien est la façon prévue d'en récupérer quand sa situation change.
