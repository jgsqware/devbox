#!/usr/bin/env bash
# devbox/macos/bootstrap.sh — même shell que les devbox Linux, sur un hôte macOS
# (MacBook Air, Mac mini), plus les configs d'apps du Mac. Plus de chezmoi.
#
#   ./macos/bootstrap.sh              tout
#   ./macos/bootstrap.sh -n           dry-run
#   ./macos/bootstrap.sh --only apps  une étape (répétable)
#   ./macos/bootstrap.sh --skip brew  sauter une étape (répétable)
#   ./bootstrap.sh / mise run bootstrap  y renvoient d'eux-mêmes sur macOS
#
# Étapes : brew · mise · vendor · shell · apps · chezmoi · login-shell · hooks · verify
#
# Compatible bash 3.2 (celui de macOS) : il tourne avant que Homebrew pose bash 5.
# Les fichiers écrasés sont sauvegardés dans ~/.local/state/devbox/backup/<date>/.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"     # racine du dépôt devbox
MAC_DIR="$SCRIPT_DIR/macos"
OVERLAY_DIR="$SCRIPT_DIR/overlay"
OMARCHY_GIT="${OMARCHY_GIT:-https://github.com/omacom/omarchy.git}"
OMARCHY_HOME="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
RC_D="$HOME/.config/devbox/rc.d"
BACKUP_DIR="$HOME/.local/state/devbox/backup/$(date +%Y%m%d-%H%M%S)"
BREW=/opt/homebrew/bin/brew
BREW_BASH=/opt/homebrew/bin/bash

ALL_STEPS="brew mise vendor shell apps chezmoi login-shell hooks verify"
DRY_RUN=0; ONLY=""; SKIP=""

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
    --only) ONLY="$ONLY $2"; shift ;;
    --skip) SKIP="$SKIP $2"; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) info "option ignorée sur macOS : $1" ;;            # options Linux de bootstrap.sh
  esac
  shift
done

wanted() {
  case " $SKIP " in *" $1 "*) return 1 ;; esac
  [[ -z "$ONLY" ]] && return 0
  case " $ONLY " in *" $1 "*) return 0 ;; esac
  return 1
}

[[ "$(uname -s)" == Darwin ]] || die "macOS uniquement — sur Linux : ./bootstrap.sh"

# sauvegarde $1 (fichier, dossier ou lien) dans BACKUP_DIR, chemin relatif à $HOME
backup() {
  local p="$1" rel="${1#"$HOME"/}"
  [[ -e "$p" || -L "$p" ]] || return 0
  run mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
  run mv "$p" "$BACKUP_DIR/$rel"
  info "sauvegarde : ~/$rel → $BACKUP_DIR/$rel"
}

# copie $1 → $2 (sauvegarde de $2 s'il diffère)
install_file() {
  local src="$1" dst="$2"
  if [[ -f "$dst" && ! -L "$dst" ]] && cmp -s "$src" "$dst"; then return 0; fi
  backup "$dst"
  run mkdir -p "$(dirname "$dst")"
  run cp -p "$src" "$dst"
}

# lien $2 → $1 (le dépôt) : une modif sur le Mac atterrit dans git
install_link() {
  local src="$1" dst="$2"
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then return 0; fi
  backup "$dst"
  run mkdir -p "$(dirname "$dst")"
  run ln -s "$src" "$dst"
}

# ================================================================ brew ====
do_brew() {
  step "① Homebrew (macos/Brewfile)"
  if [[ ! -x "$BREW" ]]; then
    (( DRY_RUN )) && { info "[dry-run] installerait Homebrew"; return 0; }
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || die "installation de Homebrew échouée"
  fi
  eval "$("$BREW" shellenv)"
  if "$BREW" bundle check --no-upgrade --file "$MAC_DIR/Brewfile" >/dev/null 2>&1; then
    ok "Brewfile déjà satisfait"
  else
    run "$BREW" bundle install --no-upgrade --file "$MAC_DIR/Brewfile" \
      && ok "Brewfile installé" || warn "brew bundle : des paquets ont échoué"
  fi
}

# ================================================================ mise ====
do_mise() {
  step "② mise : outils CLI (macos/mise.toml)"
  if ! has mise && [[ ! -x "$HOME/.local/bin/mise" ]]; then
    run sh -c 'curl -fsSL https://mise.run | sh' || die "installation de mise échouée"
  fi
  export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
  local f="$HOME/.config/mise/conf.d/devbox-macos.toml"
  install_file "$MAC_DIR/mise.toml" "$f"
  run mise install --yes && ok "outils mise installés ($f)" || warn "mise install : des outils ont échoué"
}

# ============================================================== vendor ====
do_vendor() {
  step "③ Moteur Omarchy vendoré (le même que sur les devbox Linux)"
  if [[ -d "$OMARCHY_HOME/.git" ]]; then
    run git -C "$OMARCHY_HOME" fetch -q --depth=1 origin HEAD
    run git -C "$OMARCHY_HOME" reset -q --hard FETCH_HEAD
    ok "moteur mis à jour → $OMARCHY_HOME"
  else
    run git clone -q --depth=1 --filter=blob:none --sparse "$OMARCHY_GIT" "$OMARCHY_HOME" \
      || die "clone d'Omarchy échoué"
    ok "moteur cloné → $OMARCHY_HOME"
  fi
  # macOS : pas de thèmes (Ghostty a omarchy-ghostty-theme), juste le shell et les configs
  run git -C "$OMARCHY_HOME" sparse-checkout set --no-cone '/bin/**' '/default/**' '/config/**'
}

# =============================================================== shell ====
configure_starship_hostname() {
  local toml="$HOME/.config/starship.toml" host color h
  [[ -f "$toml" ]] || return 0
  host="$(hostname -s)"
  local palette=("#f38ba8" "#fab387" "#f9e2af" "#a6e3a1" "#94e2d5" "#89dceb" "#89b4fa" "#74c7ec" "#cba6f7" "#f5c2e7")
  h="$(printf '%s' "$host" | cksum | cut -d' ' -f1)"
  color="${palette[$(( h % ${#palette[@]} ))]}"
  (( DRY_RUN )) && { info "hostname du prompt : $host → $color"; return 0; }
  awk '/^\[hostname\]/ {skip=1; next} /^\[/ && skip {skip=0} !skip' "$toml" | awk '
    !done && /^\[/ { done=1 }
    !done && /^format[[:space:]]*=/ && $0 !~ /\$hostname/ { sub(/= *"/, "&$hostname ") }
    { print }' > "$toml.tmp" && mv "$toml.tmp" "$toml"
  printf '\n[hostname]\nssh_only = false\ndisabled = false\nstyle = "bold %s"\nformat = "[$hostname]($style) "\n' "$color" >> "$toml"
  ok "hostname du prompt : $host ($color)"
}

do_shell() {
  step "④ Shell : bash + chaîne Omarchy + rc.d devbox"
  [[ -d "$OMARCHY_HOME/default/bash" ]] || (( DRY_RUN )) || die "moteur absent — étape vendor d'abord"

  install_file "$OVERLAY_DIR/bash/bashrc" "$HOME/.bashrc"
  install_file "$MAC_DIR/bash/bash_profile" "$HOME/.bash_profile"
  ok "~/.bashrc (commun) + ~/.bash_profile (macOS : PATH brew/mise) déployés"

  run mkdir -p "$RC_D"
  run cp -p "$OVERLAY_DIR"/bash/rc.d/*.sh "$RC_D/"
  ok "rc.d déposés → $RC_D ($(ls "$OVERLAY_DIR"/bash/rc.d/*.sh | wc -l | tr -d ' ') fichiers, dont 15-macos.sh)"

  local pair
  for pair in config/starship.toml:.config/starship.toml \
              config/lazygit/config.yml:.config/lazygit/config.yml \
              config/btop/btop.conf:.config/btop/btop.conf \
              config/git/config:.config/git/config; do
    [[ -r "$OMARCHY_HOME/${pair%%:*}" ]] || continue
    install_file "$OMARCHY_HOME/${pair%%:*}" "$HOME/${pair#*:}"
  done
  ok "configs Omarchy : starship, lazygit, btop, git"
  configure_starship_hostname

  local dir="$HOME/.config/devbox/git" inc
  run mkdir -p "$dir"; run cp -p "$OVERLAY_DIR"/git/* "$dir/"
  inc="$dir/identity"
  if git config --file "$HOME/.gitconfig" --get-all include.path 2>/dev/null | grep -qxF "$inc"; then
    ok "identité git déjà incluse"
  else
    run git config --file "$HOME/.gitconfig" --add include.path "$inc" && ok "identité git incluse dans ~/.gitconfig"
  fi
}

# ================================================================ apps ====
do_apps() {
  step "⑤ Apps du Mac : AeroSpace, Rex, Raycast, scripts"
  install_link "$MAC_DIR/aerospace/aerospace.toml" "$HOME/.config/aerospace/aerospace.toml"
  install_link "$MAC_DIR/rex/init.lua"             "$HOME/.config/rex/init.lua"
  install_link "$MAC_DIR/raycast/scripts"          "$HOME/.config/raycast/scripts"
  install_link "$MAC_DIR/bin/brave-ms-app"         "$HOME/.local/bin/brave-ms-app"
  ok "liens vers le dépôt : aerospace.toml · rex/init.lua · raycast/scripts · brave-ms-app"
  # copie, pas lien : self-update réécrit son propre fichier (realpath)
  install_file "$MAC_DIR/omarchy-ghostty-theme" "$HOME/.local/bin/omarchy-ghostty-theme"
  run chmod +x "$HOME/.local/bin/omarchy-ghostty-theme"
  ok "omarchy-ghostty-theme → ~/.local/bin"
  info "Raycast : la première fois, Settings → Extensions → Script Commands → Add Directory → ~/.config/raycast/scripts"
  has aerospace && ! (( DRY_RUN )) && aerospace reload-config >/dev/null 2>&1 && ok "AeroSpace rechargé"
}

# ============================================================= chezmoi ====
# On ne supprime rien : les dotfiles shell de chezmoi partent dans la sauvegarde,
# son dépôt source (~/.local/share/chezmoi) reste là, mais n'est plus appliqué.
do_chezmoi() {
  step "⑥ Abandon de chezmoi (dotfiles zsh/sh rangés dans la sauvegarde)"
  local f moved=0
  for f in .zshenv .zshrc .zprofile .profile; do
    [[ -e "$HOME/$f" ]] || continue
    backup "$HOME/$f"; moved=1
  done
  (( moved )) && ok "dotfiles zsh/sh de chezmoi retirés de ~ (récupérables dans $BACKUP_DIR)" \
              || ok "plus de dotfiles chezmoi dans ~"
}

# ========================================================= login-shell ====
do_login_shell() {
  step "⑦ Shell de connexion : $BREW_BASH"
  [[ -x "$BREW_BASH" ]] || { warn "$BREW_BASH absent — étape brew d'abord"; return 0; }
  grep -qxF "$BREW_BASH" /etc/shells || run sudo sh -c "echo $BREW_BASH >> /etc/shells"
  local cur; cur="$(dscl . -read "/Users/$USER" UserShell | awk '{print $2}')"
  if [[ "$cur" == "$BREW_BASH" ]]; then ok "déjà $BREW_BASH"; return 0; fi
  if [[ -t 0 ]]; then
    run chsh -s "$BREW_BASH" && ok "shell de connexion → $BREW_BASH (nouveaux terminaux)"
  else
    warn "pas de terminal (sync) — à lancer à la main : chsh -s $BREW_BASH"
  fi
}

# =============================================================== hooks ====
do_hooks() {
  step "⑧ Hook git (push + sync de la flotte après un commit)"
  run git -C "$SCRIPT_DIR" config core.hooksPath hooks && ok "core.hooksPath=hooks"
  # même chemin que sur les devbox Linux (sync-fleet.sh, install.sh)
  if [[ ! -e "$HOME/devbox" && "$SCRIPT_DIR" != "$HOME/devbox" ]]; then
    run ln -s "$SCRIPT_DIR" "$HOME/devbox" && ok "~/devbox → $SCRIPT_DIR"
  fi
}

# ============================================================== verify ====
do_verify() {
  step "⑨ Vérification (nouveau shell de connexion bash)"
  (( DRY_RUN )) && { skip "dry-run"; return 0; }
  local out
  # script : un vrai pty, sinon bash -i n'active pas l'édition de ligne (bind)
  out="$(TERM=xterm-256color script -q /dev/null "$BREW_BASH" -lic '
    for c in mise starship zoxide fzf atuin eza bat nvim; do command -v $c >/dev/null && echo "ok $c" || echo "ko $c"; done
    bind -X 2>/dev/null | grep -q "__fzf_select__\|fzf-file-widget" && echo "ok fzf-ctrl-t" || echo "ko fzf-ctrl-t"
    [[ "$(type -t open)" == file ]] && echo "ok open-macos" || echo "ko open-macos"
    [[ -n "${STARSHIP_SHELL:-}" ]] && echo "ok starship-init" || echo "ko starship-init"
  ' 2>&1 </dev/null | tr -d '\r')"
  # erreurs au démarrage du shell (rc.d cassé…) : remontées telles quelles
  printf '%s\n' "$out" | grep -iE 'error|erreur|not found|introuvable|no such' | while IFS= read -r l; do
    warn "démarrage du shell : $l"
  done
  local l bad=0
  while IFS= read -r l; do
    case "$l" in
      "ok "*) ok "${l#ok }" ;;
      "ko "*) warn "manquant : ${l#ko }"; bad=1 ;;
    esac
  done < <(printf '%s\n' "$out" | grep -oE '(ok|ko) [a-z-]+')
  (( bad )) && warn "à corriger ci-dessus" || ok "shell conforme aux devbox"
}

for s in $ALL_STEPS; do
  wanted "$s" || continue
  case "$s" in
    brew) do_brew ;; mise) do_mise ;; vendor) do_vendor ;; shell) do_shell ;;
    apps) do_apps ;; chezmoi) do_chezmoi ;; login-shell) do_login_shell ;;
    hooks) do_hooks ;; verify) do_verify ;;
  esac
done
printf '\n%s🏁 devbox macOS terminé%s — ouvre un nouveau terminal.\n' "$B" "$R"
