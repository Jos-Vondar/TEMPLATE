---
name: grilling
description: Interview the user relentlessly about a plan or design to stress-test it before building. Model-invocable, no slash command needed — invoke whenever the user asks to be grilled or to pressure-test a design, including trigger phrases like 'grill me', 'grille-moi', 'grillme', 'grille-moi dessus', 'cuisine-moi', or 'stress-test this'.
---

> **Emprunt ClaudeOS (bannière posée le 2026-08-07 · corps vérifié verbatim le 2026-08-09).** Corps repris **verbatim** de `mattpocock/skills · skills/productivity/grilling` (`https://raw.githubusercontent.com/mattpocock/skills/main/skills/productivity/grilling/SKILL.md`), licence en `LICENSE.mattpocock`. Le re-basage général du 2026-08-09 n'a rien eu à y changer : c'est la seule des neuf compétences empruntées qui portait déjà son corps amont intact, bannière au-dessus. Elle a servi de modèle aux huit autres. La dérive amont est surveillée par `check_upstream_drift.sh`, contrôle mensuel auto-limité qui alerte sans jamais écrire la compétence. Cette compétence n'avait aucune bannière jusqu'à cette date, ce qui la rendait invisible au recensement des emprunts.
>
> **Adoption du 2026-08-07** : le corps « une question à la fois » est remplacé par le modèle amont d'arbre de décision et de tours par frontière. Motif — trois audits consécutifs avaient signalé que l'amont avait matériellement dépassé notre copie, sans que la décision soit prise.
>
> **Un écart volontaire, et il est de fond.** L'amont fait poser les questions **en prose**, numérotées, avec une réponse recommandée. Ici elles passent par l'outil de question du règlement, jamais par de la prose : une question noyée dans du texte se répond en bloc ou se perd. Le modèle de l'amont s'y transpose sans perte — un tour de frontière est un appel de l'outil, chaque question porte sa recommandation en première option, et l'outil en accepte quatre par tour. Ce que l'amont écrit `❓ **Q1**` se lit donc ci-dessous comme « une question de l'appel en cours ». La seule exception du règlement — poser en prose quand le problème lui-même est mal posé — vaut ici aussi.

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled — the questions you can ask _now_ without guessing at answers you haven't heard yet. Ask the whole frontier in one round: number each question and give your recommended answer. Then wait for the user's answers before the next round.

Each question should be formatted like so:

```
❓ **Q1** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>
```

Each round the user answers reshapes the tree — settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier and ask the next round. A question whose answer depends on another question still open in this round belongs to a _later_ round, not this one.

Finding _facts_ is your job, never the user's. When a frontier question needs a fact from the environment (filesystem, tools, etc.), dispatch a sub-agent to find it — don't ask the user for anything you could look up yourself. Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report — ask the rest of the frontier now. The _decisions_ are the user's — put each to them and wait.

The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed. Do not act on it until the user confirms you have reached a shared understanding.
