# devbox — corrections de la chaîne Omarchy sur un hôte macOS.
# Sans effet ailleurs. Chargé avant 30-atuin.sh : atuin reprend Ctrl-R à fzf.
[[ "$OSTYPE" == darwin* ]] || return 0

# Omarchy redéfinit open() → xdg-open (Linux) : on rend le `open` de macOS.
unset -f open 2>/dev/null

# Omarchy charge fzf depuis /usr/share/fzf (Linux) : absent sur macOS, donc
# ni Ctrl-T ni Alt-C. fzf ≥ 0.48 fournit ses propres raccourcis.
if [[ $- == *i* ]] && command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --bash)"
fi

# bash-completion@2 de Homebrew (Omarchy le cherche dans /usr/share).
if [[ $- == *i* && -z "${BASH_COMPLETION_VERSINFO:-}" ]]; then
  _bc="${HOMEBREW_PREFIX:-/opt/homebrew}/etc/profile.d/bash_completion.sh"
  [[ -r "$_bc" ]] && source "$_bc"
  unset _bc
fi

# sff (Omarchy) utilise `find -printf`, qui n'existe que dans GNU find.
sff() {
  (( $# )) || { echo "Usage: sff <destination> (e.g. sff host:/tmp/)"; return 1; }
  local file
  file=$(find . -type f -exec stat -f '%m%t%N' {} + | sort -rn | cut -f2- | ff) \
    && [[ -n "$file" ]] && scp "$file" "$1"
}
