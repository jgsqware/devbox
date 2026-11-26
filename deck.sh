#!/usr/bin/env bash
# deck.sh [APP] — lance `ov deck` dans ce pane Rex : les agents de toutes les
# machines, et l'agent choisi (⏎) dans son vrai onglet, à côté de la liste.
#
#   mise run deck              l'app Rex qui affiche ce pane (détectée)
#   mise run deck <app>        une app Rex précise (son label : rex client ls)
#
# `ov serve` tourne sur l'hôte OV_DECK_HOST (défaut dev) et sert les listes sur
# le port 7778, en IPv4 seulement : l'adresse est résolue par tailscale.
set -euo pipefail

app=${1:-${OV_DECK_CLIENT:-}}
host=${OV_DECK_HOST:-dev}

# l'app Rex propriétaire de ce pane (celle où les picks s'afficheront)
if [[ -z "$app" && -n "${REX_BLOCK:-}" ]] && command -v rex >/dev/null && command -v jq >/dev/null; then
  owner=$(rex block inspect "$REX_BLOCK" --json 2>/dev/null | jq -r '.block.owner // empty' || true)
  if [[ -n "$owner" ]]; then
    app=$(rex client ls --json 2>/dev/null \
      | jq -r --arg o "$owner" '.clients[] | select(.client_id == $o and .info.kind == "app") | .info.label // empty' || true)
  fi
fi

ip=""
if command -v tailscale >/dev/null; then
  ip=$(tailscale ip -4 "$host" 2>/dev/null | head -1 || true)
fi
url="http://${ip:-$host}:7778"

ov=$(command -v ov || echo "$HOME/.local/bin/ov")
args=(deck --url "$url")
[[ -n "$app" ]] && args+=(--client "$app")
echo "ov deck → $url${app:+ · app Rex : $app}" >&2
exec "$ov" "${args[@]}"
