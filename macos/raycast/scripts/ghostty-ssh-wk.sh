#!/usr/bin/env bash
# @raycast.schemaVersion 1
# @raycast.title Ghostty SSH wk
# @raycast.mode silent
# @raycast.packageName Terminal
# @raycast.icon 👻
# @raycast.mode fullOutput
exec > >(tee -a /tmp/ghostty-ssh.log) 2>&1
set -x
env | sort | head -30
GHOSTTY_SSH_HOST=wk \
  exec "$HOME/.config/raycast/scripts/ghostty-ssh.sh"
