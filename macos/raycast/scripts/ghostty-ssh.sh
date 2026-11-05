#!/usr/bin/env bash

# @raycast.schemaVersion 1
# @raycast.title Ghostty SSH
# @raycast.mode silent
# @raycast.packageName Terminal
# @raycast.icon 👻

set -euo pipefail

HOST="${GHOSTTY_SSH_HOST:-omarchy}"
SESSION="${GHOSTTY_SSH_SESSION:-Work}"
TITLE="${HOST}"

# 1. Fenêtre existante ? -> la mettre au premier plan
#    Chaque fenêtre SSH est une instance Ghostty dédiée (open -na) : on la retrouve
#    par PID via pgrep au lieu de scanner tous les process/fenêtres dans System Events
#    (~4 s -> ~0.2 s).
PID="$(pgrep -f -- "--title=${TITLE}( |\$)" | head -1 || true)"
if [[ -n "${PID}" ]] && osascript >/dev/null 2>&1 <<EOF; then
tell application "System Events" to tell (first process whose unix id is ${PID})
  set frontmost to true
  try
    perform action "AXRaise" of window 1
  end try
end tell
EOF
  exit 0
fi

# 2. Sinon, en créer une
open -na Ghostty --args \
  --title="${TITLE}" \
  --quit-after-last-window-closed=true \
  -e ssh -t "${HOST}" "tmux new-session -A -s ${SESSION}"
