---
name: claudeos-installateur
description: Installe ClaudeOS dans ~/.claude, le met à jour ou rejoue son entretien. Se lance seul, par `bash lancer.sh` depuis ~/claudeos-amorce ou ~/.claude, qui exécute `claude --settings installateur/settings.installation.json --permission-mode auto --effort high --agent claudeos-installateur`, jamais en sous-agent, qui n'a pas AskUserQuestion.
tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion, Skill
initialPrompt: "Lis en entier le fichier installateur/LANCEMENT.md du dossier qui porte ce lanceur, ~/claudeos-amorce ou ~/.claude une fois ClaudeOS installé, puis suis-le."
---
