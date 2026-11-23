#!/usr/bin/env bash
# devbox/macos/ov.sh — installe ou met à jour ov (la console de la flotte) sur
# ce Mac : clone ~/code/ov, build, config copiée du Mac mini, hôtes Rex vérifiés.
#
#   mise run ov                    tout
#   mise run ov -- -n              dry-run
#   mise run ov -- --from HOST     copie la config depuis HOST (défaut : juliens-mac-mini)
#   mise run ov -- --force-config  recopie la config même si elle existe
#
# Étapes : checks · repo · build · config · hosts
#
# Sur le Mac qui fait tourner `ov serve` (launchd io.jgsquare.ov.serve), le
# binaire ~/.local/bin/ov est celui du service : il n'est pas touché (le
# déploiement du serve suit le README d'ov, « Deploy a release »).
# Compatible bash 3.2.

set -uo pipefail

OV_REPO="${OV_REPO:-git@github.com:jgsqware/ov.git}"
OV_DIR="${OV_DIR:-$HOME/code/ov}"
FROM="${OV_CONFIG_FROM:-juliens-mac-mini}"
SERVE_PLIST="$HOME/Library/LaunchAgents/io.jgsquare.ov.serve.plist"
DRY_RUN=0; FORCE_CONFIG=0

B=$'\e[1m'; R=$'\e[0m'; DIM=$'\e[2m'; GRN=$'\e[32m'; YEL=$'\e[33m'; RED=$'\e[31m'; BLU=$'\e[34m'
step() { printf '\n%s┌─ %s%s\n' "$B$BLU" "$1" "$R"; }
ok()   { printf '  %s✅%s %s\n' "$GRN" "$R" "$*"; }
warn() { printf '  %s⚠️ %s %s\n' "$YEL" "$R" "$*"; }
info() { printf '  %s·%s %s\n' "$DIM" "$R" "$*"; }
skip() { printf '  %s🅿️  %s%s\n' "$DIM" "$*" "$R"; }
die()  { printf '\n  %s🔴 %s%s\n\n' "$RED$B" "$*" "$R" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }
run()  { if (( DRY_RUN )); then info "[dry-run] $*"; else "$@"; fi; }

while (( $# )); do
  case "$1" in
    -n|--dry-run) DRY_RUN=1 ;;
    --from) FROM="$2"; shift ;;
    --force-config) FORCE_CONFIG=1 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) die "option inconnue : $1" ;;
  esac
  shift
done

# ---------- checks ----------
step "checks"
[[ "$(uname -s)" == Darwin ]] || die "macOS uniquement : ov pilote l'app Rex du Mac"
has git || die "git absent"
has rex || die "rex absent : installe Rex for Mac (son CLI pose \`rex\`)"
ok "rex $(command -v rex)"
# `go version` et pas `has go` : un shim mise sans version globale existe mais échoue
go_ok() { go version >/dev/null 2>&1; }
if ! go_ok; then
  if has mise; then
    run mise use -g go@latest || die "mise n'a pas pu installer go"
    go_ok || (( DRY_RUN )) || eval "$(mise activate bash --shims)"
  else
    die "go absent, et mise aussi"
  fi
fi
if go_ok; then ok "$(go version)"; else (( DRY_RUN )) || die "go inutilisable"; fi
IS_SERVE=0; [[ -f "$SERVE_PLIST" ]] && IS_SERVE=1
(( IS_SERVE )) && info "ce Mac fait tourner ov serve : ~/.local/bin/ov ne sera pas touché"

# ---------- repo ----------
step "repo"
if [[ ! -d "$OV_DIR/.git" ]]; then
  run mkdir -p "$(dirname "$OV_DIR")"
  run git clone "$OV_REPO" "$OV_DIR" || die "clone de $OV_REPO impossible (clé SSH GitHub ?)"
  ok "cloné dans $OV_DIR"
else
  br="$(git -C "$OV_DIR" rev-parse --abbrev-ref HEAD)"
  if [[ -n "$(git -C "$OV_DIR" status --porcelain --untracked-files=no)" ]]; then
    warn "$OV_DIR a des changements locaux ($br) : pas de pull, build de l'état actuel"
  elif ! git -C "$OV_DIR" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    skip "$br n'a pas d'upstream : pas de pull"
  else
    run git -C "$OV_DIR" pull --ff-only -q && ok "$br à jour"
  fi
fi

# ---------- build ----------
step "build"
if (( DRY_RUN )) && [[ ! -d "$OV_DIR" ]]; then
  info "[dry-run] go build -o ov . (dans $OV_DIR)"
else
  ver="dev-$(git -C "$OV_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  run bash -c "cd '$OV_DIR' && CGO_ENABLED=0 go build -ldflags '-X main.version=$ver' -o ov ." \
    || die "build en échec"
  ok "$OV_DIR/ov ($ver)"
  if (( IS_SERVE )); then
    skip "~/.local/bin/ov (binaire du serve)"
  else
    # un nouveau fichier puis mv : réécrire un binaire signé en place le fait tuer par macOS
    run mkdir -p "$HOME/.local/bin"
    run cp "$OV_DIR/ov" "$HOME/.local/bin/.ov.new"
    run mv -f "$HOME/.local/bin/.ov.new" "$HOME/.local/bin/ov"
    ok "~/.local/bin/ov"
  fi
fi

# ---------- config ----------
step "config"
CFG="$HOME/.config/ov"
if [[ -f "$CFG/config.yaml" && $FORCE_CONFIG -eq 0 ]]; then
  ok "$CFG/config.yaml présent (--force-config pour la recopier)"
elif [[ "$(scutil --get LocalHostName 2>/dev/null | tr 'A-Z' 'a-z')" == "$(echo "$FROM" | tr 'A-Z' 'a-z')" ]]; then
  warn "ce Mac est $FROM, la source de la config : rien à copier"
else
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$FROM" true 2>/dev/null \
    || die "ssh $FROM impossible : copie ~/.config/ov/config.yaml à la main, ou --from HOST"
  run mkdir -p "$CFG"
  [[ -f "$CFG/config.yaml" ]] && run cp "$CFG/config.yaml" "$CFG/config.yaml.bak"
  run scp -q "$FROM:.config/ov/config.yaml" "$CFG/config.yaml" && ok "config.yaml ← $FROM"
  if ssh -o BatchMode=yes "$FROM" test -d .config/ov/xc; then
    run rsync -a "$FROM:.config/ov/xc/" "$CFG/xc/" && ok "xc/ ← $FROM"
  fi
  if ssh -o BatchMode=yes "$FROM" test -f .config/jira-token; then
    run scp -q "$FROM:.config/jira-token" "$HOME/.config/jira-token" && run chmod 600 "$HOME/.config/jira-token" \
      && ok "jira-token ← $FROM"
  fi
  info "web-token non copié : il appartient au serve de $FROM"
fi

# ---------- hosts ----------
step "hôtes Rex"
if [[ -f "$CFG/config.yaml" ]]; then
  want="$(sed -n 's/^ *order: *\[\(.*\)\].*/\1/p' "$CFG/config.yaml" | head -1 | tr -d ' ' | tr ',' ' ')"
  have=" $(rex hosts --json 2>/dev/null | jq -r '.hosts[].host.label' 2>/dev/null | tr '\n' ' ') "
  missing=""
  for h in $want; do
    case "$have" in *" $h "*) ok "$h" ;; *) warn "$h : absent de \`rex hosts\`"; missing="$missing $h" ;; esac
  done
  [[ -n "$missing" ]] && info "ajoute-les (rex hosts add) ou suis le même home Rex que le Mac mini"
else
  skip "pas de config : rien à vérifier"
fi

printf '\n%s✅ ov prêt%s — lance-le dans un onglet Rex : %scd %s && ./ov%s\n' "$B$GRN" "$R" "$B" "$OV_DIR" "$R"
(( IS_SERVE )) || info "PWA de dev, sans toucher la prod : ./ov serve -addr 127.0.0.1:7778"
