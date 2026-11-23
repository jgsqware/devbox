# devbox — presse-papier sans xclip/xsel/wl-clipboard (poste headless, SSH).
#
#   clip [fichier…]   copie dans le presse-papier : pbcopy si présent (OrbStack :
#                     celui du Mac en direct), sinon OSC 52 vers le terminal HÔTE
#                     (Ghostty sur le Mac…), ce qui passe le SSH.
#                     sans argument : lit l'entrée standard (cmd | clip)
clip() {
  local f
  for f in "$@"; do
    [[ -r $f ]] || { echo "clip: $f illisible" >&2; return 1; }
  done
  if command -v pbcopy >/dev/null; then
    cat -- "$@" | pbcopy
  else
    printf '\e]52;c;%s\a' "$(cat -- "$@" | base64 | tr -d '\n')" > /dev/tty
  fi
}

# lazygit : le config.yml d'Omarchy, puis la surcouche devbox (copie au
# presse-papier par pbcopy / OSC 52 — sinon « No clipboard utilities available »).
_lg_overlay="${XDG_CONFIG_HOME:-$HOME/.config}/devbox/lazygit.yml"
if [[ -r $_lg_overlay ]]; then
  _lg_main="${XDG_CONFIG_HOME:-$HOME/.config}/lazygit/config.yml"
  [[ -r $_lg_main ]] && export LG_CONFIG_FILE="$_lg_main,$_lg_overlay" \
                     || export LG_CONFIG_FILE="$_lg_overlay"
fi
unset _lg_overlay _lg_main
