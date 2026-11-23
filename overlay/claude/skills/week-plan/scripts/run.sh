#!/usr/bin/env bash
# Headless run of /week-plan (Monday timer, or by hand: run.sh reprio).
# Reads only; writes the Obsidian plan note and ~/.local/state/week-plan.
set -uo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin"
MODE="${1:-plan}"
S="$HOME/.claude/skills/week-plan/scripts"
ST="$HOME/.local/state/week-plan"
mkdir -p "$ST/logs" "$ST/applied"
LOG="$ST/logs/$(date +%F-%H%M)-$MODE.log"
cd "$ST"
M=mcp__claude_ai_Microsoft_365
O=mcp__claude_ai_obsidian
claude -p "/week-plan $MODE" \
  --allowedTools \
    "Skill" "Read" "Glob" "Grep" "ToolSearch" "PushNotification" \
    "Edit(/$ST/**)" \
    "Bash(python3 $S/tasks.py*)" "Bash(python3 $S/jira.py*)" "Bash(date*)" \
    "${O}__list_notes" "${O}__read_note" "${O}__search_notes" "${O}__get_note_metadata" "${O}__write_note" \
    "${M}__get_me" "${M}__outlook_email_search" "${M}__chat_message_search" \
    "${M}__outlook_calendar_search" "${M}__read_resource" "${M}__teams_list_chats" \
  --disallowedTools \
    "${O}__delete_note" "${O}__move_note" "${O}__edit_note" \
    "${M}__outlook_send_mail" "${M}__outlook_send_draft" "${M}__teams_send_chat_message" \
    "${M}__teams_send_channel_message" "${M}__teams_reply_channel_message" \
  >"$LOG" 2>&1
echo "exit=$?" >>"$LOG"
