#!/usr/bin/env bash
# @raycast.schemaVersion 1
# @raycast.title Brave profil Iba
# @raycast.mode silent
# @raycast.packageName Brave Sessions
# @raycast.icon 🦁
# Fenêtre du profil Brave principal "iba" — logique dans lib/brave-profile.sh
set -euo pipefail
exec "$(cd "$(dirname "$0")" && pwd)/lib/brave-profile.sh" iba
