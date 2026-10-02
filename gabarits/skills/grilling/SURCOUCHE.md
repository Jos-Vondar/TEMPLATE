---
name: grilling
description: Interview the user relentlessly about a plan or design to stress-test it before building. Invoke whenever the user asks to be grilled or to pressure-test a design — 'grill me', 'grille-moi', 'cuisine-moi', 'stress-test this'.
---

> **Emprunt ClaudeOS.** Corps repris verbatim de `mattpocock/skills · skills/productivity/grilling`, au commit épinglé dans `engine/config/SKILLS_AMONT`, licence MIT en `LICENSE.amont`. Le frontmatter et cette bannière sont à ClaudeOS, le corps est à l'amont : `engine/skills-amont.sh` le recompose à chaque passe, une retouche du corps s'y perd.
>
> **Un écart volontaire, et il est de fond.** L'amont fait poser les questions **en prose**, numérotées, avec une réponse recommandée. Ici elles passent par l'outil `AskUserQuestion`, jamais par de la prose : une question noyée dans du texte se répond en bloc ou se perd. Le modèle de l'amont s'y transpose sans perte — un tour de frontière est un appel de l'outil, chaque question porte sa recommandation en première option, et l'outil en accepte quatre par tour. Ce que l'amont écrit `❓ **Q1**` se lit donc ci-dessous comme « une question de l'appel en cours ». Une seule exception : quand le problème lui-même est mal posé, questionner en prose, en disant qu'on change de mode.
