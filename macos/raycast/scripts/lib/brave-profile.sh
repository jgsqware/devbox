#!/usr/bin/env bash
# Moteur partagé : ouvre une fenêtre d'un profil du Brave PRINCIPAL (data-dir par défaut).
# Pas une commande Raycast (aucune métadonnée @raycast).
# Usage: brave-profile.sh <iba|gaming1|wk>
set -euo pipefail
case "${1:-}" in
  gaming1) dir="Default"   ;;   # nom affiché : Gaming1
  iba)     dir="Profile 1" ;;   # nom affiché : Iba
  wk)      dir="Profile 2" ;;   # nom affiché : wk
  *) echo "brave-profile: profil inconnu '${1:-}' (iba|gaming1|wk)" >&2; exit 1 ;;
esac
BRAVE_BIN="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
# Instance principale = process Brave lancé SANS --user-data-dir (ignore iba/gaming1 SOCKS + M365)
if ps -axo command= | grep -F "$BRAVE_BIN" | grep -v -e '--user-data-dir' -e '--type=' | grep -vq grep; then
  "$BRAVE_BIN" --profile-directory="$dir" >/dev/null 2>&1 &   # singleton → nouvelle fenêtre
  disown
else
  open -na "Brave Browser" --args --profile-directory="$dir"
fi
