# devbox — sessions tmux nommées d'après le dossier courant (ou l'argument).
# « . » et « : » sont remplacés par « _ » (interdits dans un nom de session).
#
#   trs [nom]   renomme la session courante
#   ta  [nom]   crée la session (dans $PWD) ou la rejoint ; switch-client si déjà dans tmux

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
