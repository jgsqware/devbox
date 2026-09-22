# devbox — répertoire de démarrage.
#
# wsl.exe lance le shell dans le répertoire Windows courant (/mnt/c/Users/...).
# On rentre à la maison, mais UNIQUEMENT :
#   · en shell interactif       → `wsl -e bash -lc "cd /mnt/c/… && …"` reste intact
#   · si on part d'un /mnt/*    → un `cd` volontaire vers /mnt est respecté
#
# Surcharge : export DEVBOX_START_DIR=/chemin  avant le chargement,
# ou DEVBOX_START_DIR=keep pour désactiver complètement ce comportement.

devbox_start_dir() {
  local target="${DEVBOX_START_DIR:-$HOME}"

  [[ "$target" == keep ]] && return 0
  [[ $- == *i* ]]         || return 0
  [[ -n "${WSL_DISTRO_NAME:-}" ]] || return 0
  [[ -d "$target" ]]      || return 0

  case "$PWD" in
    /mnt/*) cd "$target" || return 0 ;;
  esac
}

devbox_start_dir
