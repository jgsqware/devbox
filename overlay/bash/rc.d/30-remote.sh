# devbox — connexion distante : mosh si possible, sinon ssh.
#
#   s <hôte> [commande…]
#
# mosh survit aux changements de réseau et à la mise en veille, mais il faut
# mosh côté client ET mosh-server côté hôte. On sonde l'hôte une fois par
# shell (5 s max pour se connecter) et on mémorise le verdict ; sinon on
# retombe sur ssh tel quel. Les options ssh (-p, -J…) passent par ~/.ssh/config.
#
# Surcharge : DEVBOX_REMOTE=ssh  pour forcer ssh partout.

declare -gA _devbox_mosh_ok=()

s() {
  local host="${1:?usage: s <hôte> [commande…]}"
  shift

  if [[ "${DEVBOX_REMOTE:-}" != ssh ]] && command -v mosh >/dev/null 2>&1; then
    if [[ -z "${_devbox_mosh_ok[$host]:-}" ]]; then
      # pas de BatchMode : au premier contact, ssh doit pouvoir demander la clé d'hôte
      if ssh -o ConnectTimeout=5 "$host" 'command -v mosh-server' </dev/null >/dev/null; then
        _devbox_mosh_ok[$host]=1
      else
        _devbox_mosh_ok[$host]=0
      fi
    fi
    if [[ "${_devbox_mosh_ok[$host]}" == 1 ]]; then
      if (( $# )); then mosh "$host" -- "$@"; else mosh "$host"; fi
      return
    fi
    printf 'mosh-server absent sur %s (ou injoignable) — ssh\n' "$host" >&2
  fi

  ssh "$host" "$@"
}

# complétion : les mêmes hôtes que ssh (known_hosts, ~/.ssh/config)
declare -F _known_hosts >/dev/null && complete -F _known_hosts s

# tohost <fichier…> : envoie les fichiers dans ~/Downloads du Mac d'où l'on
# est connecté, puis les met dans SON presse-papier comme un Cmd+C du Finder
# (Cmd+V dans Slack les joint). Hôte = IP cliente de la connexion SSH (dans
# tmux : celle du dernier client attaché) ; surcharge : DEVBOX_HOST=<hôte>.
# Prérequis : la clé de cet hôte autorisée sur le Mac (ssh sans mot de passe).
tohost() {
  (( $# )) || { echo "usage: tohost <fichier…>" >&2; return 1; }
  local f host conn names=()
  for f in "$@"; do
    [[ -f $f && -r $f ]] || { echo "tohost: $f illisible" >&2; return 1; }
    names+=("${f##*/}")
  done
  host=${DEVBOX_HOST:-}
  if [[ -z $host ]]; then
    conn=$SSH_CONNECTION
    [[ -n $TMUX ]] && conn=$(tmux show-environment SSH_CONNECTION 2>/dev/null | sed -n 's/^SSH_CONNECTION=//p')
    host=${conn%% *}
  fi
  [[ -n $host ]] || { echo "tohost: pas de session SSH détectée — DEVBOX_HOST=<hôte>" >&2; return 1; }

  local opts=(-o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)
  scp -q "${opts[@]}" -- "$@" "$host:Downloads/" || return
  # ssh ne transmet qu'une chaîne : noms quotés ici, chemins absolus via $PWD là-bas.
  # JXA : NSPasteboard + URL de fichier, exactement ce que pose le Finder.
  local js='function run(argv){ObjC.import("AppKit");const pb=$.NSPasteboard.generalPasteboard;pb.clearContents;pb.writeObjects($(argv.map(p=>$.NSURL.fileURLWithPath(p))));}'
  local remote="cd ~/Downloads && osascript -l JavaScript -e $(printf %q "$js")" n
  for n in "${names[@]}"; do remote+=" \"\$PWD\"/$(printf %q "$n")"; done
  ssh "${opts[@]}" "$host" "$remote" >/dev/null || return
  printf '📋 %s → %s:~/Downloads (presse-papier)\n' "${names[*]}" "$host"
}
