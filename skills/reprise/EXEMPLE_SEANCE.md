# Un événement `seance` réussi

> Exemple construit sur la forme d'une séance principale réussie : niveaux, refs et poste sont
> fictifs. La commande ajoute `--niveau`. Le `--texte` tient sur UNE ligne : il est coupé ici pour la
> lecture ; 881 caractères. **Il donne la forme.** Chaque valeur — date, poste, sessions, refs,
> comptes des manques et `source` — vient de la séance en cours. Les manques se comptent sur ses
> gestes relus, et `--source memory/ROUTING_MISSES.md` ne vaut que si la séance y a écrit une ligne.

```
--type seance --source memory/ROUTING_MISSES.md --manque-reprise 1 --manque-declencheur 1
--texte "SÉANCE PRINCIPALE DU 2026-11-20, poste portable. Bilan de démarrage. Remontées de sessions
traitées : BUDGET, compétence non chargée avant etat.py, cause vérifiée dans le journal du niveau et
corrigée, d-budget-categories ; JARDIN, fiche mémoire env_arrosage écrite après relecture des deux
relevés, push vérifié par git log origin/main. Sessions lancées : BUDGET, JARDIN, VOYAGE ; BUDGET et
JARDIN closes et poussées, vérifié par merge-base. MANQUE DE REPRISE 1 : la décision sur les catégories
du budget n'a été journalisée qu'à la clôture, pas au moment où elle a été rendue, dans le journal de
BUDGET. MANQUE DE DÉCLENCHEUR 1 : livrables non chargée avant de rédiger le courrier au syndic, relu
après coup et réécrit, non rattrapé par le crochet, ligne au registre. PROCHAIN : rejouer le démarrage
sur le second poste après pull et constater que le bilan nomme ses compétences."
```

## Pourquoi il marche

- **L'en-tête dit le type de séance, la date et le poste**, c'est-à-dire ce qu'on cherche au `grep`.
- **Chaque fait vérifié dit par quoi il l'est** (« vérifié par merge-base », « cause vérifiée dans le
  journal du niveau »).
- **Les décisions de la séance sont citées par leur `ref`** (`d-budget-categories`), pas racontées
  une deuxième fois.
- **Chaque manque compté est nommé, selon la règle du geste 1** : un manque de reprise nomme la chose
  demandée et le fichier qui aurait dû la porter ; un manque de déclencheur nomme la compétence, le
  geste qu'elle couvrait et ce qui a été fait à la place. Le chiffre seul ne servirait à rien.
- **Seul un raté que le crochet n'a pas rattrapé va au registre**, d'où la `--source` ; un raté
  rattrapé par le refus unique se compte dans la séance et nulle part ailleurs.
- **Il finit sur `PROCHAIN :`, un seul geste faisable** (`SKILL.md`, geste 1).
- **Le récit reste brut** : une phrase par temps de la séance, sans travail de rédaction.
