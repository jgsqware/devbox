#!/usr/bin/env bash
# Run one read-only collector on ALL my devboxes in parallel, merge the JSON.
#   fleet.sh sessions [HOURS]     Claude Code sessions (default 48 h)
#   fleet.sh mrs                  open MRs / PRs (every forge each box is logged in to)
#   fleet.sh jira                 Jira items waiting on me (boxes that have twg)
#   FLEET_HOSTS="wk iba" fleet.sh …   only these boxes (default: this box + tag:devbox peers online)
# stdout: one merged JSON array (MRs deduplicated by url).
# stderr: "UNREACHABLE <host>" for a box that did not answer (never retried).
set -uo pipefail
WHAT="${1:?usage: fleet.sh sessions|mrs [args]}"; shift
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$DIR/$WHAT.py"; [[ -f "$SCRIPT" ]] || { echo "no collector $WHAT" >&2; exit 2; }
ARGS=("$@")
[[ "$WHAT" == sessions ]] && ARGS=("${1:-48}")   # the remote side must not skip my session id
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

TS="$(command -v tailscale || echo /Applications/Tailscale.app/Contents/MacOS/Tailscale)"
me="$(hostname -s 2>/dev/null || hostname)"; me="${me%%.*}"

if [[ -n "${FLEET_HOSTS:-}" ]]; then
  read -ra hosts <<<"$FLEET_HOSTS"
else
  hosts=()
  [[ -x "$TS" ]] && mapfile -t hosts < <("$TS" status --json 2>/dev/null | jq -r '
    .Peer[] | select(.Online and ((.Tags // []) | index("tag:devbox")))
    | .DNSName | split(".")[0]' | sort -u)
fi

# this box: locally (sessions.py skips the session that runs /overview)
python3 "$SCRIPT" "${ARGS[@]}" >"$TMP/$me.json" 2>/dev/null || echo '[]' >"$TMP/$me.json" &

for h in "${hosts[@]}"; do
  [[ "$h" == "$me" ]] && continue
  (
    if [[ "$(uname)" == Darwin ]]; then SSH=(ssh -o BatchMode=yes -o ConnectTimeout=8 "$h")
    else SSH=("$TS" ssh "jgsqware@$h"); fi
    timeout 90 "${SSH[@]}" python3 - "${ARGS[@]}" <"$SCRIPT" >"$TMP/$h.json" 2>/dev/null \
      && jq -e 'type == "array"' "$TMP/$h.json" >/dev/null 2>&1 \
      || { echo "UNREACHABLE $h" >&2; echo '[]' >"$TMP/$h.json"; }
  ) &
done
wait

if [[ "$WHAT" == mrs ]]; then
  jq -s 'add | (map(select(.error)) | unique_by(.forge + .error))
              + (map(select(.error | not)) | unique_by(.url) | sort_by(.updated) | reverse)' "$TMP"/*.json
elif [[ "$WHAT" == jira ]]; then
  jq -s 'add | (map(select(.error))) + (map(select(.error | not)) | unique_by(.key) | sort_by(.updated) | reverse)' "$TMP"/*.json
else
  jq -s 'add | sort_by(.last) | reverse' "$TMP"/*.json
fi
