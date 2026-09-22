#!/usr/bin/env bash
# devbox/install.sh — point d'entrée curl | bash pour une devbox toute neuve.
# Clone (ou met à jour) le dépôt puis enchaîne sur bootstrap.sh.
#
#   curl -fsSL https://raw.githubusercontent.com/jgsqware/devbox/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/jgsqware/devbox/main/install.sh | bash -s -- --user jgsqware
#
# Idempotent : si ~/devbox existe déjà, on la met juste à jour (git pull).

set -euo pipefail

DEVBOX_REPO_URL="${DEVBOX_REPO_URL:-https://github.com/jgsqware/devbox.git}"
DEVBOX_DIR="${DEVBOX_DIR:-$HOME/devbox}"

log()  { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[install]\033[0m %s\n' "$*" >&2; }

if ! command -v git >/dev/null 2>&1; then
  log "git absent, installation via pacman"
  if [[ "$(id -u)" -eq 0 ]]; then
    pacman -Sy --noconfirm --needed git
  else
    sudo pacman -Sy --noconfirm --needed git
  fi
fi

if [[ -d "$DEVBOX_DIR/.git" ]]; then
  log "dépôt déjà présent dans $DEVBOX_DIR, mise à jour"
  git -C "$DEVBOX_DIR" pull --ff-only
else
  if [[ -e "$DEVBOX_DIR" ]]; then
    warn "$DEVBOX_DIR existe déjà et n'est pas un dépôt git — déplace-le ou fixe DEVBOX_DIR"
    exit 1
  fi
  log "clonage de $DEVBOX_REPO_URL dans $DEVBOX_DIR"
  git clone "$DEVBOX_REPO_URL" "$DEVBOX_DIR"
fi

log "lancement de bootstrap.sh $*"
exec "$DEVBOX_DIR/bootstrap.sh" "$@"
