---
name: claudeos-onboarding
description: Rejouer l'entretien d'installation de ClaudeOS — changer une réponse, régler le persona, ajouter un poste. Déclencheurs — « rejoue l'entretien », « refais l'onboarding », « change mes réponses », « j'ai une deuxième machine ».
---

# Rejouer l'entretien

> Fiche situationnelle. Une procédure, deux entrées : l'agent livré, en mode « rejouer
> l'entretien » (`cd ~/.claude && claude --settings installateur/settings.installation.json --permission-mode auto --agent claudeos-installateur`), et cette compétence, dans
> une session ordinaire. **La procédure vit dans `~/.claude/installateur/ENTRETIEN.md`, seule
> autorité** : cette fiche ne la recopie pas.

1. **Lire `~/.claude/installateur/ENTRETIEN.md` en entier, puis la suivre dans cette session.** Ses
   questions passent par `AskUserQuestion`, que cette session porte ; un sous-agent ne l'a pas, donc
   l'entretien ne se délègue jamais.
2. **« J'ai une deuxième machine »** est sa question `MULTIPOSTE`, posée sur ce poste ; l'autre
   poste s'installe ensuite par l'agent, depuis une amorce, en machine de plus, sans rejouer
   l'entretien. En `GIT=aucun`, elle est sans objet : rien ne synchronise deux postes sans dépôt, et
   passer de sans git à GitHub n'est pas prévu dans cette version — le dire, et ne rien changer.
3. **Une réponse changée ne vaut qu'appliquée.** `reglages/REPONSES` réécrit, rien ne bouge tant que
   `python3 ~/.claude/engine/appliquer-reponses.py` n'a pas réécrit le bloc d'imports et les masques
   de compétences, et que `bash ~/.claude/engine/skills-amont.sh` n'a pas recomposé les compétences
   optionnelles. Puis `python3 ~/.claude/engine/appliquer-reponses.py --verifier` rend `0`.
