#!/usr/bin/env bash
# upgrade.sh — met à jour tout ce qui est installé sur CE nœud.
#
#   ./upgrade.sh              pacman (+ keyring) · AUR (yay) · mise · claude
#   ./upgrade.sh -n           dry-run : liste les mises à jour sans rien toucher
#
# Chaque étape est indépendante : un échec est signalé et on passe à la
# suivante (un AUR cassé ne doit pas bloquer mise). Code retour ≠ 0 si au
# moins une étape a échoué.
set -uo pipefail

DRY_RUN=0
[[ "${1:-}" == "-n" || "${1:-}" == "--dry-run" ]] && DRY_RUN=1

if [[ -t 1 ]]; then B=$'\033[1m'; BLU=$'\033[34m'; GRN=$'\033[32m'; YEL=$'\033[33m'; DIM=$'\033[2m'; R=$'\033[0m'; else B=""; BLU=""; GRN=""; YEL=""; DIM=""; R=""; fi
step() { printf '\n%s┌─ %s%s\n' "$B$BLU" "$*" "$R"; }
ok()   { printf '  %s✅%s %s\n' "$GRN" "$R" "$*"; }
warn() { printf '  %s⚠️ %s %s\n' "$YEL" "$R" "$*"; }
skip() { printf '  %s🅿️  %s%s\n' "$DIM" "$*" "$R"; }
has()  { command -v "$1" >/dev/null 2>&1; }

failed=()

# --- pacman --------------------------------------------------------------
# keyring d'abord : une clé expirée fait échouer tout le -Syu sinon.
step "pacman"
if (( DRY_RUN )); then
  if has checkupdates; then checkupdates || skip "rien à mettre à jour"; else skip "checkupdates absent (pacman-contrib)"; fi
else
  sudo pacman -Sy --needed --noconfirm archlinux-keyring \
    && sudo pacman -Su --noconfirm \
    && ok "paquets système à jour" || { warn "pacman a échoué"; failed+=(pacman); }
fi

# --- AUR -----------------------------------------------------------------
# -Sua : AUR seulement (pacman déjà fait). Jamais en root : makepkg refuse.
step "AUR (yay)"
if ! has yay; then
  skip "yay absent"
elif ! pacman -Qqm >/dev/null 2>&1 || [[ -z "$(pacman -Qqm)" ]]; then
  skip "aucun paquet AUR installé"
elif (( DRY_RUN )); then
  yay -Qua || skip "rien à mettre à jour"
else
  yay -Sua --noconfirm --cleanafter && ok "paquets AUR à jour" || { warn "yay a échoué"; failed+=(aur); }
fi

# --- mise ----------------------------------------------------------------
# MISE_MINIMUM_RELEASE_AGE=0 : comme omarchy-update-mise, on veut les versions
# du jour, pas celles retenues par le cooldown.
step "mise"
if ! has mise; then
  skip "mise absent"
elif (( DRY_RUN )); then
  MISE_MINIMUM_RELEASE_AGE=0 mise outdated || skip "rien à mettre à jour"
else
  MISE_MINIMUM_RELEASE_AGE=0 mise up && ok "outils mise à jour" || { warn "mise up a échoué"; failed+=(mise); }
fi

# --- claude --------------------------------------------------------------
# installé par https://claude.ai/install.sh (hors pacman) : il se met à jour seul.
step "claude"
if ! has claude; then
  skip "claude absent"
elif (( DRY_RUN )); then
  skip "claude $(claude --version 2>/dev/null | head -1) — aurait lancé claude update"
else
  claude update && ok "claude à jour" || { warn "claude update a échoué"; failed+=(claude); }
fi

echo
if (( ${#failed[@]} )); then
  warn "étapes en échec : ${failed[*]}"
  exit 1
fi
(( DRY_RUN )) && ok "dry-run terminé — rien n'a été modifié" || ok "tout est à jour"
