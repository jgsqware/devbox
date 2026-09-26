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
