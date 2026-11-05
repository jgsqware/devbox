#!/usr/bin/env bash
# @raycast.schemaVersion 1
# @raycast.title Brave wk
# @raycast.mode silent
# @raycast.packageName Brave Sessions
# @raycast.icon 🦁
# Fenêtre du profil Brave principal "wk" — logique dans lib/brave-profile.sh
set -euo pipefail
exec "$(cd "$(dirname "$0")" && pwd)/lib/brave-profile.sh" wk
