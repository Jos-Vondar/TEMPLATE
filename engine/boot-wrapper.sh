# === ClaudeOS · wrapper de lancement ===
# Lancement `claude` sans argument → injecte le prompt « tu es à jour ? » pour que
# l'assistant produise le bilan de démarrage comme PREMIER message de la session.
# (Un hook de démarrage ne peut qu'injecter du contexte, pas déclencher un tour ;
#  seul un prompt soumis au lancement fait parler l'assistant en premier.)
# Sourcé depuis ~/.bashrc. Lecture seule, ne bloque JAMAIS le lancement (|| true).
# Vit dans le repo de config → synchronisé entre machines ; seul le `source` dans
# ~/.bashrc reste manuel par machine.



claude() {
    # Mode headless (claude -p / --print) : pas d'injection, sortie potentiellement pipée.
    case " $* " in
        *" -p "*|*" --print "*) command claude "$@"; return ;;
    esac
    # Lancement interactif sans argument : injecter le prompt de bilan.
    if [ $# -eq 0 ] && [ -t 1 ]; then
        command claude "tu es à jour ?"
        return
    fi
    # Tout le reste (sous-commandes, resume, args explicites) : inchangé.
    command claude "$@"
}
