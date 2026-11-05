#!/usr/bin/env bash
# Shared engine for the per-session Brave Raycast commands (brave-iba, brave-gaming1).
# This is NOT a Raycast command: it carries no `@raycast.*` metadata, so Raycast
# ignores it and it never shows up as its own command.
#
# Usage: brave-session.sh <host>        host ∈ iba | gaming1

set -euo pipefail

# Resolve host → SOCKS port. A `case` (not an associative array) so this also
# runs under the macOS system bash 3.2 that Raycast may pick up.
host="${1:-}"
case "$host" in
  iba)     port=1080 ;;
  gaming1) port=1081 ;;
  *) echo "brave-session: missing or unknown host '${host}' (expected: iba|gaming1)" >&2; exit 1 ;;
esac

datadir="$HOME/.brave-sessions/$host"

# bring up the SSH SOCKS tunnel if not already running
if ! nc -z 127.0.0.1 "$port" 2>/dev/null; then
  ssh -fN -D "127.0.0.1:$port" "$host"
fi

# socks5:// makes Chromium resolve DNS through the SSH tunnel (remote name
# resolution), so there's no DNS leak and no need for --host-resolver-rules
# (which only triggered Brave's "unsupported command-line flag" warning).
open -na "Brave Browser" --args \
  --user-data-dir="$datadir" \
  --proxy-server="socks5://127.0.0.1:$port"
