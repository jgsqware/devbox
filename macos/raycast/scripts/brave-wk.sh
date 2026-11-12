#!/usr/bin/env bash
# @raycast.schemaVersion 1
# @raycast.title Brave wk
# @raycast.mode silent
# @raycast.packageName Brave Sessions
# @raycast.icon 🦁
# Instance Brave dédiée "wk", UA Linux. Pas un profil du Brave principal :
# --user-agent vaut pour toute l'instance (tous ses profils), d'où un data-dir à part.
set -euo pipefail

BRAVE_BIN="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
DATADIR="$HOME/.brave-sessions/wk"

if pgrep -f -- "--user-data-dir=$DATADIR" >/dev/null; then
  # instance vivante → le singleton Chromium y ouvre une nouvelle fenêtre (UA déjà posé)
  "$BRAVE_BIN" --user-data-dir="$DATADIR" >/dev/null 2>&1 &
  disown
  exit 0
fi

MAJOR="$("$BRAVE_BIN" --version 2>/dev/null | awk '{print $3}' | cut -d. -f1)"
MAJOR="${MAJOR:-141}"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${MAJOR}.0.0.0 Safari/537.36"

open -na "Brave Browser" --args \
  --user-data-dir="$DATADIR" \
  --user-agent="$UA" \
  --no-first-run \
  --no-default-browser-check
