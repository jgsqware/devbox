# devbox — environnement de base.
# Chargé APRÈS la chaîne omarchy : c'est ici qu'on la surcharge.

export OMARCHY_PATH="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
export OMARCHY_THEME_HEADLESS=1

case ":$PATH:" in
  *":$OMARCHY_PATH/bin:"*) ;;
  *) export PATH="$OMARCHY_PATH/bin:$PATH" ;;
esac

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Poste headless : pas de navigateur graphique à lancer.
# (EDITOR reste omarchy-launch-editor --inline, qui retombe sur nvim.)
unset BROWSER
