#!/bin/bash
# fermer-projet.sh — ferme la session de PROJET courante, en dernier geste de sa clôture
# (skills/reprise/FERMETURE_PROJET.md). La principale ne se ferme jamais : hors d'une session de
# projet (`CLAUDEOS_SESSION_SCOPE` autre que `projet`), rien n'est fermé et le script rend 1.
# Sous tmux, le serveur tue la session après 5 s d'attente, pour que le dernier message s'affiche ;
# le terminal attaché par `claudeos-session.sh --attach` (`exec tmux attach`) la suit. Hors tmux, la
# session reste ouverte, et le script le dit.
[ "${CLAUDEOS_SESSION_SCOPE:-}" = projet ] || { echo "pas une session de projet : rien n'est fermé (la principale ne se ferme jamais)"; exit 1; }
if [ -n "${TMUX_PANE:-}" ]; then
    S=$(tmux display-message -p -t "$TMUX_PANE" '#S') && tmux run-shell -b "sleep 5; tmux kill-session -t =$S"
else
    echo "hors tmux : session laissée ouverte"
fi
