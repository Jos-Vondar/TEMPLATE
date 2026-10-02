# Accueil — la lecture obligée

Cinq points avant toute installation (`d-apprentissage-lecture-obligee`). Chacun se dit en six lignes
au plus, puis se vérifie par **une question à une seule bonne réponse**, posée par `AskUserQuestion`.

- **Si la réponse est fausse**, réexplique autrement, avec une autre image et pas la même phrase
  redite. Puis repose la question, en changeant l'ordre des options.
- **Rien ne s'installe avant que les cinq points soient passés.**
- **Aucun script ne prouve la compréhension.** C'est toi qui tiens ce point ; le vérificateur ne
  constatera que la date.

Ouvre par deux lignes : « Avant d'installer, cinq choses sur la façon dont ClaudeOS travaille. Une
question après chacune : c'est court, et c'est ce qui t'évitera de perdre du travail. »

## 1. La clôture, seule sauvegarde

Dis « on arrête » en fin de séance, et la clôture démarre. Elle écrit l'état de la séance au journal
et fait tourner les contrôles, puis elle sauvegarde : avec GitHub, elle pousse tes dépôts privés ; sans
git, elle contrôle, et rien ne sort du poste. **Il n'y a pas d'autre sauvegarde** : aucun crochet ne
sauvegarde quand tu fermes le terminal. Une seule session clôture, la principale, celle de
`~/.claude`, après avoir demandé aux autres si elles ont fini.

**Question** : « Tu fermes ton terminal le soir sans avoir dit « on arrête ». Qu'est-ce qui est
sauvegardé de ta journée ? »
- a) Tout : ClaudeOS sauvegarde à la fermeture.
- b) Rien depuis la dernière clôture : tes fichiers sont sur le disque, mais la sauvegarde n'a lieu
  qu'à la clôture. **← la bonne**
- c) Seulement le journal de la séance.

## 2. La reprise s'écrit pendant, pas à la fin

Chaque projet a un `ETAT.md` : ce qui est décidé, ce qui reste, où trouver quoi. Il ne s'écrit jamais
à la main. Il est projeté depuis un journal d'événements, que l'assistant alimente au fil de la séance,
à chaque décision et à chaque palier (`etat.py add`). Demain, une session neuve relit cet `ETAT.md`
et reprend là où tu en étais, sans la conversation d'aujourd'hui. Ce qui n'a été dit qu'en
conversation est perdu à la session suivante.

**Question** : « Tu as pris une décision importante en séance. Qu'est-ce qui garantit que la session
de demain la connaîtra ? »
- a) La conversation : Claude Code la garde et la relit.
- b) La mémoire automatique, qui retient tout.
- c) Un événement écrit au journal du projet, que son `ETAT.md` projette. **← la bonne**

## 3. Une session par projet

Chaque projet s'ouvre dans sa propre session, `bash ~/.claude/engine/claudeos-session.sh <projet>`,
dans `tmux`. Son contexte ne porte que les règles et l'état de ce projet. La session principale,
ouverte dans `~/.claude`, tient le système : le règlement, la mémoire, la clôture. Une session de
projet écrit dans son projet, pousse son dossier si tu as GitHub, et laisse la clôture à la
principale.

**Question** : « Tu travailles cet après-midi sur deux projets. Comment t'organises-tu ? »
- a) Une session par projet, et la clôture reste à la session principale. **← la bonne**
- b) Une seule session pour les deux : je passe de l'un à l'autre.
- c) Une session par projet, et chacune fait sa propre clôture.

## 4. Le contexte et `/compact`

Une conversation a une capacité. Quand elle se remplit, Claude Code la résume, par `/compact` ou de
lui-même, et continue sur le résumé, qui perd des détails. C'est pourquoi l'état s'écrit au fil de
l'eau (point 2). Après un compactage, l'assistant relit l'`ETAT.md` du niveau, et il repart des faits
écrits, pas du souvenir.

**Question** : « La conversation est longue, et tu t'apprêtes à lancer `/compact`. Que faut-il avoir
fait avant ? »
- a) Rien : le résumé garde tout.
- b) S'assurer que l'état du travail est écrit au journal du projet. **← la bonne**
- c) Fermer la session et en ouvrir une autre.

## 5. Ce qui sort du poste

Avec GitHub, la clôture pousse sur tes dépôts **privés** tout ce que ClaudeOS tient : tes réglages, ton
persona, les journaux, la mémoire et les dossiers de travail. Ce que la liste noire exclut reste sur
le poste : les transcriptions de Claude Code, les caches, les identifiants, et chaque `_IGNORE/`,
réceptacle des documents qui ne doivent pas sortir. Sans git, rien ne sort. Un secret ne s'écrit
jamais dans un fichier suivi : le crochet de commit le refuse.

**Question** : « Si tu gardes ton système sur GitHub, qu'est-ce qui part sur ton dépôt privé à la
clôture ? »
- a) Seulement le code du moteur.
- b) Rien : GitHub ne sert qu'aux mises à jour.
- c) Tout ce que ClaudeOS tient, sauf ce que la liste noire exclut : transcriptions, caches,
  identifiants, et chaque `_IGNORE/`. **← la bonne**

## Fin de la lecture

Quand les cinq points sont passés, retiens la date du jour : la plomberie l'écrit dans
`reglages/ACCUEIL` (`INSTALLER.md`, I5). En mode essai, la réponse de chaque point se lit à sa ligne
`<n>=` du fichier `accueil`, et une réponse fausse arrête tout.
