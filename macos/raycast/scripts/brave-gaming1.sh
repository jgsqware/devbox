#!/usr/bin/env bash
# @raycast.schemaVersion 1
# @raycast.title Brave Gaming1
# @raycast.mode silent
# @raycast.packageName Brave Sessions
# @raycast.icon 🦁
#
# Opens an isolated Brave profile routed through the SSH SOCKS tunnel to `gaming1`.
# Thin wrapper — all the logic lives in lib/brave-session.sh (shared, hidden from Raycast).

set -euo pipefail
dir="$(cd "$(dirname "$0")" && pwd)"
exec "$dir/lib/brave-session.sh" gaming1
