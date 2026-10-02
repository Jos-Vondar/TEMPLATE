# Entretien — ce que ClaudeOS devient chez toi

Procédure unique de l'entretien, deux entrées :
- l'agent livré, en I6 d'une installation (mode **installation**) ou sur demande (mode
  **rejouer**) ;
- la compétence `claudeos-onboarding`, dans une session ordinaire (mode **rejouer**).

La plomberie a posé la machinerie ; il reste ce qu'un script ne peut pas faire, savoir qui est en
face. Questions, valeurs libres et validations suivent les bornes de `LANCEMENT.md` :
- `AskUserQuestion` pour chaque question, quatre questions au plus par appel ;
- une valeur libre se donne par « Autre » ;
- rien ne s'écrit sans avoir été montré dans un `preview`.

## 0. Avant la première question

- **Mode installation** : le régime est choisi depuis I4, et `reglages/REPONSES` ne porte encore que
  `GIT` et `PROXY`.
- **Mode rejouer** : les réponses existent. Chaque question montre la valeur en place comme une
  option, « Garder : <valeur> ».
- **Mode migration** (`MIGRER.md`, M4) : `import-v2.py --importer` a déjà écrit les réponses que la
  V1 ou la V2 connaissait, le persona qu'elle portait et « Mes domaines ». Ne pose que les clés que
  l'inventaire a nommées, et les rubriques encore marquées. Une rubrique importée se garde ou se
  reprend avec la personne, elle ne se repose pas.
- **Sur une machine de plus, ne rejoue jamais l'entretien** : il produirait une seconde réponse aux
  mêmes questions, et deux réponses à deux âges se contredisent. « J'ai une deuxième machine » se
  traite ici sur le premier poste, par la seule question `MULTIPOSTE` ; l'autre poste s'installe en
  machine de plus (`INSTALLER.md`).
- **Si le démarrage ne dit `INSTALLATION INACHEVÉE` que pour `sauvegarde` ou `clôture`**, les réponses
  sont faites : va au § 9.
- **Un `CLAUDE.md` d'avant ClaudeOS**, copié sous `~/.claude-avant-claudeos/`, verra ses règles
  proposées au § 6.

Dis trois choses avant de commencer :
- **L'entretien se rejoue.** Une réponse décrit un état, et l'état change : une deuxième machine, un
  premier client, un premier document qui sort de chez toi. Relance-le à ce moment-là, plutôt que de
  deviner quelle règle te manque.
- **Tu ne pars pas d'une page blanche, mais d'un héritage.** Les règles livrées viennent d'un autre
  système, où chacune est née d'un incident ; aucune n'a été méritée par toi. Le remède est la passe
  mensuelle `os-audit` : tes propres incidents produiront tes propres règles, dans « Mes règles ».
- **Rien ne s'écrit sans t'être montré d'abord.**

## 1. Le régime et les dépôts de travail

- **`GIT`** : en installation, il est choisi depuis I4. En rejouer, montre-le sans le reposer :
  changer de régime n'est pas prévu dans cette version, dis-le et n'y touche pas.
- **`PREFIXES`**, en `GIT=par-domaine` seulement. Question : « Chaque domaine sera un dépôt privé
  sous `~/`, nommé `<PRÉFIXE><NOM>`. Le préfixe range tes dépôts par famille, et le moteur reconnaît
  un dossier de travail à lui. Quels préfixes veux-tu ? »
  - La réponse se donne par « Autre » : des majuscules terminées par `_`, séparées par des virgules.
  - Deux options sans valeur : « Explique-moi d'abord » et « Je ne sais pas encore ». Sur la
    seconde, dis ce qui en dépend : le premier domaine, en I7, se nomme par un préfixe. Puis repose
    la question une fois.
- **`PREFIXES_CLIENT`**, en `GIT=par-domaine` seulement. Question : « Parmi ces familles, lesquelles
  porteront des documents de clients ? »
  - Leurs dépôts reçoivent la liste noire de référence, et le crochet de commit refuse un tel dépôt
    qui ne la porte pas.
  - Une question à choix multiple, une option par préfixe donné, plus « Aucune ».
- En `GIT=unique` comme en `GIT=aucun`, ces deux clés restent vides, et le dire : les domaines vivent
  sous `~/.claude/travail/<NOM>/`, sans dépôt à eux.

## 2. Les conditions de travail

Elles décident quelles règles entrent. Pose-les toutes, même si une réponse paraît évidente : c'est la
personne qui répond, pas toi. Un seul appel, quatre questions ; chaque option porte ce qu'elle fait
entrer ou sortir.

| Clé | Question | `oui` fait entrer | `non` |
| :--- | :--- | :--- | :--- |
| `MULTIPOSTE` | Travailles-tu, ou travailleras-tu, depuis plusieurs machines ? | jamais de clôture depuis un poste en retard ; aucun chemin propre à un poste dans un fichier suivi ; le démarrage sonde le retard de chaque dépôt | ni ces règles ni la sonde ; une deuxième machine plus tard se règle en rejouant cette seule question |
| `MULTIDOMAINE` | As-tu plusieurs domaines de travail bien distincts — des clients, des pans d'activité ? | la table « Mes domaines » et ses règles : identifier le domaine d'abord, un raté de recherche traité comme un trou de routage | une seule couche de règles pour tout ; la section « Mes domaines » se retire |
| `LIVRABLE` | Produis-tu des documents destinés à d'autres que toi ? | la compétence `livrables`, et un livrable qui suit ta rubrique « Périmètre du caractère » | la compétence se masque, la règle sort |
| `CONFIDENTIEL` | Manipules-tu des documents que tu ne peux pas versionner — pièces de clients, données personnelles ? | le réceptacle `_IGNORE/` à la racine de chaque projet, tenu hors sauvegarde ; une suppression y est définitive et se confirme ; deux contrôles hebdomadaires le gardent | aucun réceptacle : un document qui ne doit pas sortir n'a pas de place prévue |

**En `GIT=aucun`, `MULTIPOSTE` vaut `non` sans question**, et tu le dis : rien ne synchronise deux
postes sans dépôt.

## 3. La conduite de l'assistant

Même mécanisme, autre sujet : deux appels, quatre questions chacun. Pose chacune telle qu'elle est
écrite ici, avec les deux régimes et leur coût : c'est sur eux que la personne choisit.

- **`SUPERVISION`** — « Quand l'assistant travaille sur tes fichiers, veux-tu qu'il annonce chaque
  changement avant de le faire et qu'il te rende la main aux étapes clés, ou qu'il avance seul et te
  rende compte à la fin ? »
  - `non`, « avance seul », retire : l'explication avant de modifier un fichier, la demande avant de
    trancher ce qui entre dans une règle, le choix proposé sur une décision d'architecture et les
    paliers annoncés.
  - Restent dans tous les cas la confirmation avant l'irréversible et la dette de sécurité signalée.
  - `oui` : « qu'il annonce et rende la main ».
- **`SOLLICITATIONS`** — « Quand il a besoin d'une décision de ta part, préfères-tu qu'il s'arrête et te
  pose un choix explicite avec ses options, ou qu'il propose au fil du texte et continue ? »
  - `oui` : une question par l'outil de question, une décision par question, chaque option avec son
    coût.
  - `non` : la proposition au fil du texte. La question reste due quand il le faut : la règle régit
    sa forme, pas son existence.
- **`CONCISION`** — « Réponse courte — la conclusion et ce qui attend ta décision, le détail dans les
  fichiers —, ou compte rendu complet du raisonnement dans la réponse ? » `oui` : la réponse courte.
- **`RIGUEUR_AFFICHEE`** — « Veux-tu qu'il marque le statut de ce qu'il affirme — vérifié avec sa
  source, inféré, à confirmer — et qu'il dise sur quoi il a cherché quand il conclut qu'une chose
  n'existe pas ? Ou la réponse seule ? »
  - `non` ne retire que l'affichage. Varier les motifs d'une recherche avant de conclure reste dû :
    c'est au socle.
- **`CODE_RELU`** — « Ton code passe-t-il sous les yeux d'autres personnes — revue, pull request,
  équipe ? »
  - `oui` : le résumé des décisions retenues avant tout commit qui n'est pas une sauvegarde de
    routine.
  - `non` : il committe sans récapituler.
- **`REGLES_A_FROID`** — « Quand tu édictes une règle en pleine séance — « désormais, fais X » —,
  veux-tu qu'elle s'écrive tout de suite, ou qu'elle refroidisse ? »
  - Refroidir, c'est `oui` : la règle devient un dû du chantier `regles-candidates`, promu à la passe
    mensuelle, et elle n'entre que si une autre sort. Seul un interdit qui prévient de l'irréversible
    s'écrit à chaud.
- **`DOCS_SUR_DEMANDE`** — « Veux-tu qu'il ne crée jamais de fichier de documentation ni de README
  sans que tu l'aies demandé ? »
  - `non` l'autorise à en créer partout où il le juge utile.
- **`BILAN_DEMARRAGE`** — « Au démarrage de chaque session principale, veux-tu qu'il ouvre sa première
  réponse par un bilan — poste à jour ou non, tableau d'état, dernière séance, rappels et fils
  ouverts — suivi d'une proposition de travail pour la journée ? Ou qu'il réponde directement ? »
  - `non` retire l'état des lieux, la proposition et le relais des rappels et des fils, qu'il faudra
    aller chercher. Seule la dette de sécurité reste signalée.
  - Ne l'oriente pas, mais n'en cache rien : ce bilan est le cœur de ce que le système ajoute à
    l'outil nu.

## 4. Les compétences optionnelles

**`SKILLS_OPTION`** : une question à choix multiple, trois options et « Aucune ». Chacune est un
emprunt sous licence MIT de `mattpocock/skills`, téléchargé à son commit épinglé
(`engine/config/SKILLS_AMONT`) : la composer demande le réseau.

- `writing-for-agents` : une grille d'écriture pour tout document qu'un agent consomme, qu'il
  s'agisse de compétences, de `CLAUDE.md` ou de mémoires.
- `grilling` : un entretien contradictoire qui t'interroge jusqu'à ce qu'un plan tienne.
- `domain-modeling` : le vocabulaire d'un domaine, et ses décisions d'architecture consignées.

**Puis écris `reglages/REPONSES` d'un bloc.**
- Les dix-sept lignes, `CLE=valeur`, dans l'ordre de `engine/config/REPONSES_CLES`, sans
  commentaire.
- `PROXY` garde la valeur posée par la plomberie : c'est un fait du poste, jamais une question.
- Montre d'abord le bloc entier dans le `preview` d'une question de validation, avec deux issues :
  « Écrire ces réponses » ou « Corriger une réponse ».

## 5. Le persona — neuf rubriques

C'est la seule phase qui produise ce qui n'existe nulle part ailleurs : ne l'expédie pas. Les
rubriques vivent dans `## Persona` du `CLAUDE.md`, chacune sous son `### <Rubrique>` et sa marque
`*(réglage : à remplir)*`.

**Sans exemple ni valeur proposée.** Tu poses la question-guide, la personne répond par « Autre »,
avec ses mots. Les options ne portent que des issues sans valeur :
- **« Rien de particulier »** retire la rubrique : son titre, son commentaire et sa marque. **Sauf
  Identité**, qui ne se retire pas.
- **« Plus tard »** laisse la marque, et tu dis que l'installation reste inachevée tant qu'elle
  survit.
- En mode rejouer : **« Garder tel quel »**.

| Rubrique | Question-guide |
| :--- | :--- |
| Identité | Quel nom donnes-tu à ton assistant, et quel rapport veux-tu avec lui : un pair, un exécutant, un conseiller ? |
| Contradiction | Jusqu'où doit-il contester une idée ? À quoi reconnais-tu une objection réelle plutôt que fabriquée, et comment veux-tu qu'il concède quand tu as raison ? |
| Pushback, dosé par l'enjeu | Combien de fois doit-il insister avant d'exécuter, selon que le geste se rattrape ou non ? Peut-il contester le but, et pas seulement la méthode ? Que devient son désaccord une fois ta décision maintenue ? |
| Initiative | Que doit-il faire sans que tu le demandes — des angles que tu n'as pas sollicités, un chantier préparé parce qu'il se voit venir —, sans noyer la réponse à ta question ? |
| Pédagogie | Doit-il expliquer le pourquoi par défaut, ou seulement quand tu le demandes ? |
| Franchise | Quel degré d'atténuation tolères-tu quand il te dit ce qui ne va pas ? |
| Périmètre du caractère | Où sa personnalité s'exprime-t-elle, et où s'efface-t-elle ? Le dialogue avec toi et un document pour un tiers appellent-ils le même registre ? |
| Humour | En veux-tu, et d'où doit-il naître ? |
| Forme de la voix | Ordre de la réponse, registre, tutoiement ou vouvoiement, tics à proscrire, jargon traduit ou non ? |

**Écrire.**
- Une réponse se met en phrases sans rien ajouter. Remplace la marque sous son titre, et garde le
  commentaire : Claude Code retire les commentaires du contexte, ils ne coûtent rien.
- Montre les textes dans le `preview` d'une question de validation avant de les écrire, quatre
  rubriques au plus par appel.

**Un point à dire honnêtement** : le corpus de règles hérité est écrit dans une voix dense, faite
d'aphorismes. Même vidé de son contenu, il enseigne un style par imitation, et le persona en sera
teinté. On ne peut pas l'éviter ; on peut le savoir.

## 6. Tes domaines, tes règles, ton rythme, ton identité

- **« Mes domaines »**
  - `MULTIDOMAINE=oui` : retire la ligne `| *(à remplir)* | | |`. Le premier domaine y entre en
    I7, par la compétence `nouveau-domaine`, et chaque domaine suivant de même. Pose aussi le
    registre des ratés de routage, que la règle « Plusieurs domaines » fait remplir et que le contrôle
    hebdomadaire 23 exige :
    `mkdir -p ~/.claude/memory && cp -n ~/.claude/gabarits/ROUTING_MISSES.md ~/.claude/memory/`.
  - `MULTIDOMAINE=non` : retire la section entière, titre, commentaire et table.
  - En rejouer : un passage de `oui` à `non` qui ferait perdre des lignes se demande ; un passage de
    `non` à `oui` remet la section, son en-tête de table tiré de `gabarits/CLAUDE.md`, et une ligne
    par dossier de travail existant.
- **« Mes règles »**
  - S'il y avait un `CLAUDE.md` d'avant, propose ses règles une à une, avec deux issues : « La
    garder dans Mes règles » ou « La laisser ».
  - Puis demande : « As-tu déjà une règle à toi, que l'assistant doit suivre à chaque séance ? » La
    réponse se donne par « Autre », ou l'option « Pas pour l'instant ».
  - Une règle n'entre que si elle passe l'une des deux portes que le socle rappelle. Vide est permis
    et n'est pas inachevé.
- **Le rythme**, facultatif.
  - En rejouer seulement : un créneau se rattache à un domaine, et l'installation n'en a pas encore.
  - Question : « As-tu des jours attitrés par domaine ? » Réponse par « Autre », écrite dans
    `reglages/CRENEAUX`, une ligne `<dossier> <jours>` par domaine, jours en `lun,mar,…`. C'est le
    format que lit `engine/lib_creneaux.py`.
  - Sans réponse, pas de fichier.
- **L'identité git**, en régime GitHub, si `reglages/IDENTITE_GIT` porte une valeur vide.
  - Demande le nom et l'adresse des commits, par « Autre ».
  - Écris-les dans le fichier, dont les lignes de tête se gardent, puis lance
    `bash ~/.claude/engine/install-poste.sh`. Il les pose dans la configuration globale de git, sans
    jamais écraser une identité déjà là : un écart, il le dit.

## 7. Appliquer

Une réponse ne vaut qu'appliquée. Lance dans cet ordre, puis lis et relaie leurs comptes rendus :

```bash
python3 ~/.claude/engine/appliquer-reponses.py
bash ~/.claude/engine/skills-amont.sh
python3 ~/.claude/engine/appliquer-reponses.py --verifier
bash ~/.claude/engine/skills-amont.sh --verifier
```

- **`appliquer-reponses.py`** écrit le bloc d'imports du `CLAUDE.md`, et rien d'autre du fichier. Il
  écrit aussi les compétences masquées dans `settings.json`. Relaie la liste des fragments importés
  et des compétences masquées.
- **`skills-amont.sh`** compose les compétences optionnelles retenues et retire les autres. S'il
  rend **M-AMONT-ECHEC**, relaie le message tel quel avec ses trois issues : la compétence est
  optionnelle, et le système est complet sans elle.
- **Les deux `--verifier`** doivent rendre `0`.

**Puis dis ce qui a été écarté, et pourquoi** : c'est l'information la plus utile de l'entretien, et
la seule que la personne ne retrouverait pas seule, une règle absente ne se manifestant par rien.
- Les fragments de `~/.claude/noyau/regles/` que le bloc n'importe pas, chacun avec la réponse qui
  l'a écarté.
- Les compétences masquées, chacune avec sa réponse.

## 8. Les trois commandes d'`etat.py`, et les premiers événements

Enseigne-les en vrai, sur le niveau `~/.claude`, avec les premiers événements du système. **Le texte
d'un événement ne porte jamais d'accent grave** : entre guillemets, le shell exécuterait la commande
citée, et le journal ne s'efface pas.

1. **`add` écrit un fait** : un type parmi six, et une source qui est un chemin, jamais une valeur.
   Les premiers faits du système, écrits ensemble :

   ```bash
   python3 ~/.claude/engine/etat.py add --niveau ~/.claude --type observation --ref o-installation \
     --source reglages/REPONSES --texte "INSTALLATION DE CLAUDEOS LE <date> : …"
   python3 ~/.claude/engine/etat.py add --niveau ~/.claude --type pointeur --op ajoute \
     --ref p-rejouer-entretien --source skills/claudeos-onboarding/SKILL.md \
     --texte "Comment changer une réponse ou rejouer l'entretien ? → la compétence claudeos-onboarding, ou l'agent livré ; une réponse ne vaut qu'appliquée."
   ```

   En mode rejouer, une seule `observation`, qui dit ce qui a changé.
2. **`projette` réécrit `ETAT.md`** depuis le journal :
   `python3 ~/.claude/engine/etat.py projette --niveau ~/.claude`. Montre-lui sa carte « Où
   trouver ». `ETAT.md` ne s'édite jamais à la main.
3. **`fils` montre ce qui reste à faire**, tous niveaux, par ancienneté :
   `python3 ~/.claude/engine/etat.py fils --tous`.

Puis dis-le en clair : **la sauvegarde n'a lieu qu'à la clôture.** Aucun crochet ne sauvegarde en fin
de session. La reprise au fil de l'eau et la clôture sont la compétence `reprise`.

## 9. Pour finir

1. `python3 ~/.claude/engine/verifier.py entretien` rend `0`. Sinon, traite le défaut qu'il nomme et
   relance-le.
2. Dis ce qui a été écrit, et où : `reglages/REPONSES`, le `CLAUDE.md` — persona, domaines, règles,
   bloc d'imports —, les compétences composées et le journal du système.
3. Dis que l'entretien se rejoue quand la situation change : `/claudeos-onboarding`, ou l'agent
   livré, `cd ~/.claude && claude --permission-mode auto --agent claudeos-installateur`.
4. **En mode installation**, reviens à `INSTALLER.md`, I7. **En mode rejouer**, ce qui a changé
   partira à la prochaine clôture.

**Si seule la sauvegarde ou la clôture manquait (§ 0)**, joue la clôture de `INSTALLER.md`, I8,
geste 1 : en régime GitHub, demande avant de pousser.
