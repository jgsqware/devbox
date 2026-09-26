#!/usr/bin/env bash
# devbox/sync-fleet.sh — rejoue le bootstrap sur toutes les machines de la
# tailnet taguées tag:omarchy (en ligne), en parallèle — CELLE-CI COMPRISE :
# le hook post-commit est posé sur chaque nœud, un commit fait n'importe où
# resynchronise toute la flotte, y compris la machine d'où il part.
#
#   ./sync-fleet.sh              toutes les machines tag:omarchy
#   ./sync-fleet.sh mini iba     seulement celles-là (noms tailnet)
#   DEVBOX_SYNC_EXCLUDE="a b"    machines exclues (défaut : obsidian-mcp)
#   DEVBOX_SYNC_SELF=0           ne pas rejouer le bootstrap sur cette machine
#   mise run sync
#
# Sur chaque hôte, via `tailscale ssh` : cd ~/devbox && git pull --ff-only
# && ./bootstrap.sh --skip cli-auth. Non interactif de bout en bout :
#   · cli-auth sauté (gh/claude login attendraient un humain)
#   · sudo DOIT être sans mot de passe (--sudo-nopasswd) — sinon l'hôte est
#     signalé en échec, à relancer à la main
#   · un hôte sans ~/devbox (pas une devbox) est ignoré, pas en échec
#
# Logs : ~/.local/state/devbox/sync/<horodatage>/<hôte>.log

set -uo pipefail

TAG="${DEVBOX_SYNC_TAG:-tag:omarchy}"
REMOTE_USER="${DEVBOX_USER:-jgsqware}"
TIMEOUT="${DEVBOX_SYNC_TIMEOUT:-30m}"                  # par hôte
# taguées tag:omarchy mais PAS des devbox à resynchroniser (noms courts, espaces)
EXCLUDE="${DEVBOX_SYNC_EXCLUDE-obsidian-mcp}"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/devbox/sync/$(date +%Y%m%d-%H%M%S)"

command -v tailscale >/dev/null && command -v jq >/dev/null \
  || { echo "tailscale et jq requis" >&2; exit 1; }

SELF=""
if (( $# )); then
  hosts=("$@")
else
  (( ${DEVBOX_SYNC_SELF:-1} )) && SELF="$(tailscale status --self --json | jq -r --arg tag "$TAG" '
    .Self | select((.Tags // []) | index($tag)) | .DNSName | rtrimstr(".")')"
  mapfile -t hosts < <(tailscale status --json | jq -r --arg tag "$TAG" --arg ex "$EXCLUDE" '
    ($ex | split(" ") | map(select(. != ""))) as $skip
    | .Peer[] | select(.Online and ((.Tags // []) | index($tag)))
    | .DNSName | rtrimstr(".") | select((split(".")[0]) as $n | $skip | index($n) | not)')
fi
[[ -n "$SELF" ]] && hosts+=("$SELF")
(( ${#hosts[@]} )) || { echo "aucune machine $TAG en ligne"; exit 0; }

mkdir -p "$LOG_DIR"
ln -sfn "$LOG_DIR" "$(dirname "$LOG_DIR")/latest"

# Ni `set -e` ni `exit` : dans un shell de login, `exit` fait lire
# ~/.bash_logout, et sous set -e son moindre échec (clear_console absent sur
# Ubuntu) écrase le code de sortie — un SKIP ressortait alors en échec.
remote='d="$HOME/devbox"
if [ ! -d "$d/.git" ]; then
  echo "SKIP: pas de ~/devbox sur cet hôte"
elif ! sudo -n true 2>/dev/null; then
  echo "ÉCHEC: sudo demande un mot de passe — bootstrap à lancer à la main (ou --sudo-nopasswd)"
  false
else
  cd "$d" && git pull --ff-only && ./bootstrap.sh --skip cli-auth
fi'

echo "sync → ${#hosts[@]} machine(s) : ${hosts[*]}"
echo "logs : $LOG_DIR"

declare -A pids=()
for h in "${hosts[@]}"; do
  # tailscale ssh (pas ssh) : vérifie la clé d'hôte annoncée par la tailnet —
  # un ssh nu en BatchMode échoue sur "Host key verification failed" pour
  # tout hôte jamais visité. Il n'accepte pas -o : timeout borne la durée.
  if [[ "$h" == "$SELF" ]]; then
    # soi-même : même script, en local — pas de ssh vers sa propre machine
    timeout "$TIMEOUT" bash -lc "$remote" </dev/null >"$LOG_DIR/${h%%.*}.log" 2>&1 &
  else
    timeout "$TIMEOUT" tailscale ssh "$REMOTE_USER@$h" "bash -lc $(printf '%q' "$remote")" \
      </dev/null >"$LOG_DIR/${h%%.*}.log" 2>&1 &
  fi
  pids[$h]=$!
done

okc=0; failed=()
for h in "${hosts[@]}"; do
  if wait "${pids[$h]}"; then
    okc=$((okc + 1))
    grep -q '^SKIP:' "$LOG_DIR/${h%%.*}.log" && echo "  🅿️  ${h%%.*} (pas une devbox)" || echo "  ✅ ${h%%.*}"
  else
    failed+=("${h%%.*}")
    echo "  🔴 ${h%%.*} — $(tail -1 "$LOG_DIR/${h%%.*}.log")"
  fi
done

summary="devbox sync : $okc/${#hosts[@]} ok"
(( ${#failed[@]} )) && summary+=" — échecs : ${failed[*]}"
echo "$summary" | tee "$LOG_DIR/summary"
command -v notify-send >/dev/null && notify-send "devbox sync" "$summary" 2>/dev/null
(( ${#failed[@]} == 0 ))
