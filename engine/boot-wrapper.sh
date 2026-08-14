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
    # SAUF si le bilan de démarrage a été décliné à l'entretien. Sans cette garde, la
    # personne qui l'a décliné pose malgré elle une question à laquelle la consigne
    # injectée interdit de répondre par un bilan : elle voit sa propre question rester
    # sans réponse dès la première seconde d'usage. Fichier de conditions ABSENT =
    # toutes vraies, donc une installation sans entretien garde le comportement d'avant.
    if [ $# -eq 0 ] && [ -t 1 ]; then
        _cnd="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config/CONDITIONS"
        if [ -f "$_cnd" ] && ! grep -qx 'BILAN_DEMARRAGE' "$_cnd"; then
            unset _cnd
            command claude
            return
        fi
        unset _cnd
        command claude "tu es à jour ?"
        return
    fi
    # Tout le reste (sous-commandes, resume, args explicites) : inchangé.
    command claude "$@"
}
