# Bilan de démarrage — session de projet

> Branche de `demarrage` pour un bloc injecté « démarrage d'une session de PROJET ».

**En-tête, une ligne** : le niveau, et la synchro de son dépôt avec son motif s'il n'est pas tiré.

**Les quatre rubriques, dans cet ordre, toutes bornées au niveau :**
1. **À faire aujourd'hui** — deux ou trois lignes tirées des fils du niveau et du PROCHAIN de sa
   dernière séance, composées selon le § 3 de la fiche. Quand le bloc dit « Tri des fils : DÛ », la première
   ligne est **FAIRE** — le tri, avec la ligne du bloc, et la compétence `tri-des-fils` pose sa
   question d'entrée après le bilan. Toute autre ligne « Tri des fils » se rend telle quelle dans
   « Rappels », y compris « non mesurée » ou « indisponible », avec sa cause.
2. **Fait la dernière fois** — date, poste, l'essentiel, PROCHAIN. Une question « qu'est-ce qui a
   bougé depuis ? » par `AskUserQuestion` dans deux cas seulement : la séance a plus de 7 jours, ou un
   fil attend un événement extérieur dont la date est passée.
3. **Rappels** — ceux que le bloc rattache au niveau, affichés. Leur traitement appartient à la
   principale : proposer de le lui remonter. La ligne « Plafond de l'état », si le bloc la porte, se
   rend ici telle quelle.
4. **Fils ouverts du niveau** — tous ceux du bloc, **groupés par porteur, « 👤 À toi » en tête** :
   la première ligne du bloc donne les comptes, le marqueur ouvre le texte de chaque fil. Puis ceux
   de l'assistant, ❔ sans porteur, et la ligne « ⏳ en attente ». Un « … et N autre(s) » se rend tel
   quel.

Le global reste à la principale ; seule la dette de sécurité 🔐 se relaie, si le bloc la porte. Les
garde-fous du bloc tiennent toute la séance : ils se suivent, ils ne se recopient pas à l'écran.

**Fini quand** les quatre rubriques sont rendues pour ce seul niveau, et qu'un tri DÛ a sa question.
