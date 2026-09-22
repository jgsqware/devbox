// devbox — cible de thème zellij pour le moteur omarchy (headless).
// Déposé dans ~/.config/omarchy/themed/ : les templates utilisateur
// sont lus AVANT les templates intégrés, donc rien à patcher upstream.
themes {
    omarchy {
        fg "{{ foreground }}"
        bg "{{ background }}"
        black "{{ dark_background }}"
        red "{{ red }}"
        green "{{ green }}"
        yellow "{{ yellow }}"
        blue "{{ blue }}"
        magenta "{{ magenta }}"
        cyan "{{ cyan }}"
        white "{{ bright_foreground }}"
        orange "{{ orange }}"
    }
}
