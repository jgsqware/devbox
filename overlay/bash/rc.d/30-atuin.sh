# devbox — atuin : historique shell (Ctrl-R, flèche haut).
# Chargé APRÈS la chaîne omarchy (rc.d passe en dernier), donc reprend Ctrl-R à
# fzf. bash-preexec est embarqué dans `atuin init bash`, rien d'autre à installer.
if [[ $- == *i* ]] && command -v atuin >/dev/null 2>&1; then
  eval "$(atuin init bash)"
fi
