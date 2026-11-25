# Bilan de démarrage — session principale

> Branche de `demarrage` pour un bloc injecté « démarrage de la session PRINCIPALE ».

**Avant de rendre, lire [`EXEMPLE_PRINCIPALE.md`](EXEMPLE_PRINCIPALE.md)** et prendre sa
forme ; le contenu vient du bloc du jour.

**En-tête, deux lignes.**
- La machine, telle que la donne `Poste :`, jamais déduite d'un chemin ni de la dernière séance. La
  croisière du bloc suit, sur la même ligne.
- La synchro : « à jour », ou chaque dépôt non à jour avec le motif que donne le bloc ; une ligne
  `Synchro :` qui dit le retard non sondé ou la synchro sans objet se rend telle quelle. Pour un
  dépôt « tirable sans risque », proposer la commande de son alerte, que l'utilisateur lance ou fait
  lancer.

Puis « État hors du vert », s'il y a des lignes.

**Les quatre rubriques, dans cet ordre :**
1. **À faire aujourd'hui** — deux ou trois lignes tirées du PROCHAIN de la dernière principale et
   des fils que liste le bloc, composées selon le § 3 de la fiche.
2. **Fait depuis ta dernière principale** — la dernière séance principale de CE poste (date,
   l'essentiel, son PROCHAIN), puis celles qu'un autre poste a écrites après elle, puis les séances
   de projet que le bloc liste, une ligne par niveau.
3. **Rappels** — la ligne « Rappels : N lus, M échus », puis chaque ⏰ échu. Les autres alertes du
   bloc (🔐 ⚠️ ⛔ 📌 🔓 🔍) suivent, une ligne chacune ; « fichiers non commités » se dit seulement
   s'il pèse sur ce qu'on propose.
4. **Fils ouverts** — **en tête, le groupe « 👤 À toi »** : les fils proposables de la ligne « À ta
   charge », chacun avec son niveau et son ancienneté, puis sa ligne « Ailleurs » ; vide, le dire en
   une ligne. Puis les fils de l'assistant ou sans porteur qu'il liste, avec leur marqueur, la ligne
   « ⏳ en attente », la ligne « Porteurs des fils actifs », les comptes des autres domaines, le total
   et les sessions de projet ouvertes. Le marqueur vient du champ `porteur` du fil, jamais du texte :
   un fil ❔ ne se classe pas à l'œil au rendu.

Puis, pour **chaque** rappel échu, une question `AskUserQuestion` — une par rappel, trois issues :
tenir maintenant · replanifier à une date · abandonner. L'application de la réponse suit la
compétence `session`, [`PROPOSITION_DU_JOUR.md`](../session/PROPOSITION_DU_JOUR.md).

**Fini quand** l'exemple a été lu dans cette séance, que les quatre rubriques sont rendues et que
chaque rappel échu a sa question.
