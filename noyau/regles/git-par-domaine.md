## Git : un dépôt par domaine

- **`~/.claude` est le dépôt du système, chaque domaine un dépôt privé sous `~/`** dont le nom
  commence par un préfixe de la réponse `PREFIXES` ; un domaine se résout par son dépôt, jamais de
  mémoire.
- **La sauvegarde sort du poste à la clôture**, commit et push de chaque dépôt, par la session
  principale seule ; une session de projet ne pousse que son dossier → `pousser-son-dossier`.
