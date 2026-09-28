#!/usr/bin/env bash
# socks5-test.sh — teste le proxy SOCKS5 posé par `bootstrap.sh --with-socks5`.
#
#   ./socks5-test.sh                  proxy de CE nœud (IP tailnet locale), port 1080
#   ./socks5-test.sh gaming1          proxy d'un autre nœud de la tailnet
#   ./socks5-test.sh gaming1 1081     port non standard (ou DEVBOX_SOCKS5_PORT)
#
# Contrôles : port joignable, requête HTTPS via le proxy (DNS résolu côté
# proxy, socks5h), IP de sortie via le proxy vs en direct.
set -euo pipefail

HOST="${1:-$(tailscale ip -4 2>/dev/null | head -1)}"
PORT="${2:-${DEVBOX_SOCKS5_PORT:-1080}}"
URL="${SOCKS5_TEST_URL:-https://example.com}"
IP_URL="https://ifconfig.me/ip"

if [[ -t 1 ]]; then GRN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; R=$'\033[0m'; else GRN=""; RED=""; DIM=""; R=""; fi
ok()   { printf '  %s✅%s %s\n' "$GRN" "$R" "$*"; }
fail() { printf '  %s❌%s %s\n' "$RED" "$R" "$*"; exit 1; }

[[ -n "$HOST" ]] || fail "pas d'IP tailnet locale — passe l'hôte en argument : $0 <hôte> [port]"
# nom d'hôte → IPv4 tailnet via tailscale : le proxy n'écoute que sur celle-ci,
# alors que le résolveur système peut rendre une IPv6 ou une IP locale
# (nœud courant via /etc/hosts, etc.) — faux ❌ garanti.
if [[ ! "$HOST" =~ ^[0-9.]+$ ]] && ts_ip="$(tailscale ip -4 "$HOST" 2>/dev/null | head -1)" && [[ -n "$ts_ip" ]]; then
  HOST="$ts_ip"
fi
command -v curl >/dev/null || fail "curl absent"
PROXY="socks5h://$HOST:$PORT"
printf '\nproxy %s\n' "$PROXY"

timeout 5 bash -c "exec 3<>/dev/tcp/$HOST/$PORT" 2>/dev/null \
  && ok "port $PORT joignable sur $HOST" \
  || fail "port $PORT injoignable sur $HOST (service arrêté ? ACL ? mauvais hôte ?)"

code="$(curl -sS -m 15 -o /dev/null -w '%{http_code}' --proxy "$PROXY" "$URL" 2>&1)" \
  && [[ "$code" =~ ^[23] ]] \
  && ok "$URL via le proxy → HTTP $code" \
  || fail "$URL via le proxy → $code"

via="$(curl -sS -m 10 --proxy "$PROXY" "$IP_URL" 2>/dev/null || echo '?')"
direct="$(curl -sS -m 10 "$IP_URL" 2>/dev/null || echo '?')"
ok "IP de sortie via le proxy : $via  ${DIM}(en direct : $direct)${R}"
printf '\n'
