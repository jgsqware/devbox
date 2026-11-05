#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Teams (Linux UA)
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 💬
# @raycast.packageName M365 Linux
# @raycast.description Teams dans Brave dédié (UA Linux), session partagée, instance unique

exec "${HOME}/.local/bin/brave-ms-app" teams
