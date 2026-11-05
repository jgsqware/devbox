#!/usr/bin/env bash
# @raycast.schemaVersion 1
# @raycast.title Brave profil Gaming1
# @raycast.mode silent
# @raycast.packageName Brave Sessions
# @raycast.icon 🦁
# Fenêtre du profil Brave principal "gaming1" — logique dans lib/brave-profile.sh
set -euo pipefail
exec "$(cd "$(dirname "$0")" && pwd)/lib/brave-profile.sh" gaming1
