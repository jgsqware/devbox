#!/usr/bin/env bash
# One compact, read-only digest for /overview: Claude sessions, MRs/PRs, Jira,
# from all devboxes in parallel. Full JSON is kept in $OUT for drill-down.
#   overview.sh [HOURS]    sessions window, default 48 (use 72+ on Monday)
set -uo pipefail
HOURS="${1:-48}"
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${OVERVIEW_OUT:-${XDG_STATE_HOME:-$HOME/.local/state}/overview}"
mkdir -p "$OUT"

"$DIR/fleet.sh" sessions "$HOURS" >"$OUT/sessions.json" 2>"$OUT/sessions.err" &
"$DIR/fleet.sh" mrs                 >"$OUT/mrs.json"      2>"$OUT/mrs.err" &
"$DIR/fleet.sh" jira                >"$OUT/jira.json"     2>"$OUT/jira.err" &
wait

echo "# raw JSON: $OUT/{sessions,mrs,jira}.json"
cat "$OUT"/*.err 2>/dev/null | grep -v '^Warning' | sort -u | sed 's/^/# /'

echo; echo "## SESSIONS (last ${HOURS} h) — host | open/status | last | turns | title | cwd | branch | git | keys | mrs | ends_with_question"
jq -r '.[] | [.host, (if .open then "OPEN/\(.status)" else "closed" end), .last, .turns, .title,
  .cwd, .branch,
  (.git | if .exists == false then "cwd gone" elif .git == false then "no git"
          else "dirty=\(.dirty // "?") ahead=\(.ahead // "-")" end),
  (.keys | join(",")), (.mrs | map("!" + .) | join(",")), .ends_with_question] | @tsv' "$OUT/sessions.json"

echo; echo "## SESSION TAILS — id | first prompt ⟶ last prompt ⟶ last reply (end)"
jq -r '.[] | "\(.host) \(.id[0:8]) | \(.first_prompt[0:120]) ⟶ \(.last_prompt[0:120]) ⟶ …\(.last_reply_tail[-300:])"' "$OUT/sessions.json"

echo; echo "## MR/PR (updated < 60 d) — forge | role | ref | draft | merge status | pipeline | conflicts | approved_by | unresolved | updated | title"
jq -r --arg since "$(date -d '-60 days' +%F 2>/dev/null || date -v-60d +%F)" '
  .[] | if .error then "ERROR \(.box) \(.forge): \(.error)"
  elif .updated >= $since then
    [.forge, .role, .ref, (if .draft then "draft" else "" end), (.status // ""), (.pipeline // ""),
     (if .conflicts then "CONFLICT" else "" end), ((.approved_by // []) | join(",")),
     (.unresolved // ""), .updated, .title[0:80]] | @tsv
  else empty end' "$OUT/mrs.json"
echo "# older open MR/PR ignored: $(jq --arg since "$(date -d '-60 days' +%F 2>/dev/null || date -v-60d +%F)" '[.[] | select(.error|not) | select(.updated < $since)] | length' "$OUT/mrs.json")"

echo; echo "## JIRA — key | role | status | prio | due | updated | sprint | ball_in_my_court | last comment by | summary"
jq -r '.[] | if .error then "ERROR \(.box): \(.error)" else
  [.key, .role, .status, .priority, .due, .updated, .sprint, .ball_in_my_court, .last_comment_by, .summary[0:80]] | @tsv end' "$OUT/jira.json"
