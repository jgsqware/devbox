# devbox — sessions tmux nommées d'après le dossier courant (ou l'argument).
# « . » et « : » sont remplacés par « _ » (interdits dans un nom de session).
#
#   trs [nom]   renomme la session courante
#   ta  [nom]   crée la session (dans $PWD) ou la rejoint ; switch-client si déjà dans tmux
#   clip [fichier…]   copie dans le presse-papier du terminal HÔTE (OSC 52, passe le SSH)
#                     sans argument : lit l'entrée standard (cmd | clip)

_tmux_session_name() {
  local name=${1:-${PWD##*/}}
  printf '%s' "${name//[.:]/_}"
}

# Renomme la session courante d'après le dossier (ou l'argument)
rename-session() {
  tmux rename-session "$(_tmux_session_name "$1")"
}

# Crée ou rejoint une session nommée d'après le dossier (ou l'argument)
attach() {
  local name
  name=$(_tmux_session_name "$1")
  tmux has-session -t="$name" 2>/dev/null || tmux new -ds "$name" -c "$PWD"
  if [[ -n $TMUX ]]; then
    tmux switch-client -t "$name"
  else
    tmux attach -t "$name"
  fi
}

alias trs='rename-session'
alias ta='attach'

# Presse-papier du terminal hôte (Ghostty sur le Mac…) via OSC 52, même en SSH.
# Dans tmux : load-buffer -w (set-clipboard on + terminal-features *:clipboard).
# Hors tmux : séquence OSC 52 écrite directement sur le terminal.
clip() {
  local f
  for f in "$@"; do
    [[ -r $f ]] || { echo "clip: $f illisible" >&2; return 1; }
  done
  if [[ -n $TMUX ]]; then
    cat -- "$@" | tmux load-buffer -w -
  else
    printf '\e]52;c;%s\a' "$(cat -- "$@" | base64 | tr -d '\n')" > /dev/tty
  fi
}
