#!/bin/zsh
# @raycast.schemaVersion 1
# @raycast.title AeroSpace Spawn All
# @raycast.mode silent
# @raycast.packageName AeroSpace
# @raycast.icon 🪟
# @raycast.description Lance toutes les apps de travail et les range dans leur workspace
#
# aero-spawn — lance (ou retrouve) chaque fenêtre et la range dans son workspace AeroSpace.
# Idempotent : une fenêtre déjà ouverte n'est pas relancée, juste re-rangée.
# Appelé au démarrage par AeroSpace (after-startup-command) et dispo dans Raycast.
# Log : ~/Library/Logs/aero-spawn.log

setopt no_unset pipe_fail
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

S="$HOME/.config/raycast/scripts"
LOG="$HOME/Library/Logs/aero-spawn.log"
exec >>"$LOG" 2>&1
echo "──── $(date '+%F %T') aero-spawn start"

log() { echo "$(date '+%T') $*"; }

# ── helpers ──────────────────────────────────────────────────────────────────

# find_windows <bundle> <pid-pattern|-> <title-regex>  → ids des fenêtres qui matchent
find_windows() {
  local bundle=$1 pidpat=$2 re=$3 pid="" id wpid bid ws title
  if [[ $pidpat != - ]]; then
    pid=$(pgrep -o -f -- "$pidpat" 2>/dev/null) || return 0
  fi
  aerospace list-windows --all --format '%{window-id}|%{app-pid}|%{app-bundle-id}|%{workspace}|%{window-title}' |
  while IFS='|' read -r id wpid bid ws title; do
    [[ $bid == $bundle ]] || continue
    [[ -z $pid || $wpid == $pid ]] || continue
    [[ $title =~ $re ]] || continue
    echo $id
  done
}

# Au boot réseau/Tailscale sont lents : on attend UNE fois (max 60 s) que iba réponde,
# ensuite chaque hôte n'a droit qu'à un essai court → un hôte éteint (gaming1) ne bloque pas.
wait_network() {
  local i
  for i in {1..30}; do nc -z -G 2 iba 22 2>/dev/null && return 0; sleep 2; done
  log "⚠️  réseau pas prêt après 60 s"
}
host_up() {
  nc -z -G 3 "$1" 22 2>/dev/null && return 0
  log "⚠️  $1 injoignable — skip (relance « AeroSpace Spawn All » quand il revient)"; return 1
}

# spawn <ws> <bundle> <pid-pattern|-> <title-regex> <launcher...>
spawn() {
  local ws=$1 bundle=$2 pidpat=$3 re=$4; shift 4
  local ids i
  ids=($(find_windows $bundle $pidpat $re))
  if (( ${#ids} == 0 )); then
    log "🚀 $ws ← $*"
    "$@" >/dev/null 2>&1 &!
    for i in {1..60}; do              # 30 s max
      sleep 0.5
      ids=($(find_windows $bundle $pidpat $re))
      (( ${#ids} )) && break
    done
  fi
  if (( ${#ids} == 0 )); then log "❌ $ws : pas de fenêtre pour $bundle /$re/"; return 1; fi
  for i in $ids; do aerospace move-node-to-workspace --window-id $i $ws; done
  log "✅ $ws : ${#ids} fenêtre(s) $bundle /$re/"
  LAST=$ids[-1]
}

GHOSTTY=com.mitchellh.ghostty
SLACK=""
BRAVE=com.brave.Browser
M365="--user-data-dir=$HOME/Library/Application Support/BraveLinuxTeams"

wait_network

# ── C : Claude ───────────────────────────────────────────────────────────────
spawn C com.anthropic.claudefordesktop - '.' open -b com.anthropic.claudefordesktop

# ── A : perso / Apple ────────────────────────────────────────────────────────
spawn A com.apple.iCal  - '.' open -b com.apple.iCal
host_up omarchy && spawn A $GHOSTTY '--title=omarchy( |$)' '.' env GHOSTTY_SSH_HOST=omarchy "$S/ghostty-ssh.sh"

# ── M : Mail + Music ─────────────────────────────────────────────────────────
spawn M com.apple.mail  - '.' open -b com.apple.mail
spawn M com.apple.Music - '.' open -b com.apple.Music

# ── G : Gaming1 ──────────────────────────────────────────────────────────────
spawn G $BRAVE - '– Gaming1$' "$S/brave-profile-gaming1.sh"
host_up gaming1 && spawn G $GHOSTTY '--title=gaming1( |$)' '.' "$S/ghostty-ssh-gaming1.sh"
spawn G com.microsoft.teams2 - '.' open -b com.microsoft.teams2

# ── I : Iba ──────────────────────────────────────────────────────────────────
spawn I $BRAVE - '– Iba$' "$S/brave-profile-iba.sh"
host_up iba && spawn I $GHOSTTY '--title=iba( |$)' '.' "$S/ghostty-ssh-iba.sh"
spawn I com.apple.Safari.WebApp.9C2750D5-E82B-4888-8C62-777BCA91E557 - '.' open "$HOME/Applications/Iba - Teams.app"

# ── W : wk / Codabox ─────────────────────────────────────────────────────────
spawn W $BRAVE - '– wk$' "$S/brave-wk.sh"
spawn W com.tinyspeck.slackmacgap - '.' open -b com.tinyspeck.slackmacgap && SLACK=$LAST
host_up wk && spawn W $GHOSTTY '--title=wk( |$)' '.' "$S/ghostty-ssh-wk.sh"
OUTLOOK="" TEAMS=""
spawn W $BRAVE "$M365" 'Outlook|Sign in to your account' "$S/outlook-linux.sh"        && OUTLOOK=$LAST
spawn W $BRAVE "$M365" 'Microsoft Teams' "$S/teams-linux.sh"  && TEAMS=$LAST

# ── Layouts ──────────────────────────────────────────────────────────────────
for ws in 1 A; do
  id=$(aerospace list-windows --workspace $ws --format '%{window-id} %{window-layout}' | awk '$2!="floating"{print $1; exit}')
  [[ -n $id ]] && aerospace layout --window-id $id h_accordion && log "🪗 $ws → h_accordion"
done
# W : Outlook + Slack + Teams empilés dans un sous-conteneur v_accordion (best-effort).
# On aplatit W, on renvoie les 3 en fin de ligne (aller-retour par un WS temporaire)
# pour qu'ils soient voisins dans l'ordre Outlook, Slack, Teams, puis on les regroupe.
if [[ -n $OUTLOOK && -n $SLACK && -n $TEAMS ]]; then
  aerospace flatten-workspace-tree --workspace W
  for i in $OUTLOOK $SLACK $TEAMS; do
    aerospace move-node-to-workspace --window-id $i spawntmp
    aerospace move-node-to-workspace --window-id $i W
  done
  aerospace focus --window-id $SLACK && aerospace join-with left \
    && aerospace focus --window-id $TEAMS && aerospace move left \
    && aerospace layout --window-id $TEAMS v_accordion \
    && log "🪗 W → Outlook+Slack+Teams en v_accordion"
fi

aerospace workspace W
log "🏁 terminé"
