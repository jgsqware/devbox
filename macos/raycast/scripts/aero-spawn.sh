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
    local a
    for a in "$@"; do   # lanceur absent → échec immédiat, pas 30 s d'attente
      [[ $a == /* && ! -x $a ]] && { log "❌ $ws : lanceur introuvable $a"; return 1; }
    done
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

# spawn_zen <ws> <identité> — une fenêtre Zen par identité (container). Les titres ne
# disent pas le container → on mémorise l'id AeroSpace de la fenêtre qu'on a ouverte.
ZEN=app.zen-browser.zen
ZSTATE="$HOME/.cache/aero-spawn"; mkdir -p "$ZSTATE"
zen_ids() { aerospace list-windows --all --format '%{window-id}|%{app-bundle-id}' | awk -F'|' -v b=$ZEN '$2==b{print $1}'; }
spawn_zen() {
  local ws=$1 ident=$2 f="$ZSTATE/zen-$2" id="" before after i
  [[ -r $f ]] && id=$(<$f)
  if [[ -z $id ]] || ! zen_ids | grep -qx -- "$id"; then
    # Zen éteint : le démarrer à part, sa fenêtre d'accueil ne doit pas passer pour la nôtre
    if ! pgrep -xq zen; then
      open -a /Applications/Zen.app
      for i in {1..40}; do (( $(zen_ids | wc -l) > 0 )) && break; sleep 0.25; done
      sleep 3
    fi
    before=" $(zen_ids | tr '\n' ' ') "
    log "🚀 $ws ← zen-open $ident"
    "$HOME/.local/bin/zen-open" $ident >/dev/null 2>&1 &!
    id=""
    for i in {1..60}; do               # 30 s max
      sleep 0.5
      for after in $(zen_ids); do [[ $before == *" $after "* ]] || id=$after; done
      [[ -n $id ]] && break
    done
    [[ -z $id ]] && { log "❌ $ws : pas de fenêtre Zen pour $ident"; return 1; }
    echo $id >$f
  fi
  aerospace move-node-to-workspace --window-id $id $ws
  log "✅ $ws : Zen $ident (#$id)"
  LAST=$id
}

# rex_window <hôte> — fenêtre Rex.app sur la session « <hôte> » de cet hôte (créée si absente).
# Titre de la fenêtre = « <titre du pane> - <session> » → retrouvée par / - <hôte>$/.
REX=com.superlogical.rex
rex_window() {
  local h=$1 sid client before nid="" title junk jh jsid i
  sid=$(rex --timeout 6s -S $h ls --json | jq -r --arg l $h '.sessions[] | select(.label==$l) | .session_id' | head -1)
  [[ -z $sid ]] && sid=$(rex --timeout 6s -S $h new $h --json | jq -r '.session_id')
  client=$(rex client ls --json | jq -r '[.clients[] | select(.info.kind=="app")][0].client_id')
  before=" $(aerospace list-windows --all --format '%{window-id}|%{app-bundle-id}' | awk -F'|' -v b=$REX '$2==b{printf "%s ", $1}')"
  open -b $REX                                   # app au premier plan : la nouvelle fenêtre devient la clé
  rex -C $client do client.window.new || return 1
  for i in {1..20}; do
    sleep 0.25
    nid=$(aerospace list-windows --all --format '%{window-id}|%{app-bundle-id}' | awk -F'|' -v b=$REX '$2==b{print $1}' |
          while read -r i; do [[ $before == *" $i "* ]] || echo $i; done | tail -1)
    [[ -n $nid ]] && break
  done
  [[ -z $nid ]] && return 1
  aerospace focus --window-id $nid; sleep 0.3
  # client.window.new ouvre une session neuve (nom auto) : on la retient pour la tuer ensuite
  title=$(aerospace list-windows --all --format '%{window-id}|%{window-title}' | awk -F'|' -v w=$nid '$1==w{print $2}')
  junk=${title##* - }
  rex -C $client do session.select session_id=$sid || return 1
  sleep 0.5
  [[ $junk == $h ]] && return 0
  for jh in local iba gaming1 wk dev; do
    if [[ $jh == local ]]; then jsid=$(rex ls --json 2>/dev/null); else jsid=$(rex --timeout 4s -S $jh ls --json 2>/dev/null); fi
    jsid=$(jq -r --arg l "$junk" '.sessions[]? | select(.label==$l) | .session_id' <<<"$jsid" | head -1)
    [[ -z $jsid ]] && continue
    if [[ $jh == local ]]; then rex kill $jsid; else rex -S $jh kill $jsid; fi >/dev/null 2>&1 && log "🧹 session auto $junk ($jh) fermée"
    break
  done
}

SLACK=""

wait_network

# ── C : Claude ───────────────────────────────────────────────────────────────
spawn C com.anthropic.claudefordesktop - '.' open -b com.anthropic.claudefordesktop

# ── A : perso / Apple ────────────────────────────────────────────────────────
spawn A com.apple.iCal  - '.' open -b com.apple.iCal

# ── M : Mail + Music ─────────────────────────────────────────────────────────
spawn M com.apple.mail  - '.' open -b com.apple.mail
spawn M com.apple.Music - '.' open -b com.apple.Music

# ── G : Gaming1 ──────────────────────────────────────────────────────────────
spawn_zen G gaming1
host_up gaming1 && spawn G $REX - ' - gaming1$' rex_window gaming1

# ── I : Iba ──────────────────────────────────────────────────────────────────
spawn_zen I iba
host_up iba && spawn I $REX - ' - iba$' rex_window iba

# ── W : wk / Codabox ─────────────────────────────────────────────────────────
spawn W com.tinyspeck.slackmacgap - '.' open -b com.tinyspeck.slackmacgap && SLACK=$LAST
host_up wk && spawn W $REX - ' - wk$' rex_window wk
OUTLOOK="" TEAMS=""
spawn_zen W wk-outlook && OUTLOOK=$LAST
spawn_zen W wk         && TEAMS=$LAST

# Zen ouvre une fenêtre d'accueil vide au démarrage : on ferme les fenêtres Zen non suivies
# et sans page (titre nu « Zen Browser »)
tracked=" $(cat $ZSTATE/zen-* 2>/dev/null | tr '\n' ' ') "
aerospace list-windows --all --format '%{window-id}|%{app-bundle-id}|%{window-title}' |
while IFS='|' read -r id bid title; do
  [[ $bid == $ZEN && $title == "Zen Browser" && $tracked != *" $id "* ]] || continue
  aerospace close --window-id $id && log "🧹 Zen : fenêtre vide #$id fermée"
done

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
