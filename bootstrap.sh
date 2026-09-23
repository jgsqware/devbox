#!/usr/bin/env bash
# devbox/bootstrap.sh — provisionne un poste headless « omarchy-flavored »
# sur un Arch NU (WSL, Incus, VM, conteneur). N'installe JAMAIS la distro
# Omarchy : on ajoute son dépôt pacman public et on picore.
#
# Réf. : meta/analyses/analyse-forge-par-client-et-baux.md §10 et §11
#
# Se lance indifféremment :
#   · en ROOT   → crée l'utilisateur, prépare WSL, puis se relance en son nom
#   · en USER   → enchaîne directement l'installation
#
# Idempotent : rejouable autant de fois que voulu.

set -euo pipefail

VERSION="0.3.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# ---------------------------------------------------------------- réglages --
DEVBOX_USER="${DEVBOX_USER:-jgsqware}"
OMARCHY_CHANNEL="${OMARCHY_CHANNEL:-stable}"          # stable | rc | edge
OMARCHY_REPO_URL="https://pkgs.omarchy.org/${OMARCHY_CHANNEL}/\$arch"
OMARCHY_GIT="${OMARCHY_GIT:-https://github.com/omacom/omarchy.git}"
OMARCHY_HOME="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
THEME="${DEVBOX_THEME:-tokyo-night}"
LOCALES="${DEVBOX_LOCALES:-en_US.UTF-8 fr_BE.UTF-8}"   # 1re = LANG par défaut
CLAUDE_EMAIL="${CLAUDE_EMAIL:-kdhckrvddf@privaterelay.appleid.com}"   # étape cli-auth
START_DIR="${DEVBOX_START_DIR:-}"                      # vide = $HOME ; "keep" = off
TS_HOSTNAME="${DEVBOX_HOSTNAME:-$(hostname -s 2>/dev/null || echo devbox)}"
HOSTNAME_SET=0                                         # 1 = hostname demandé explicitement
[[ -n "${DEVBOX_HOSTNAME:-}" ]] && HOSTNAME_SET=1
ARCH="$(uname -m)"                                     # [omarchy] ne publie omarchy-keyring/
                                                        # omarchy-nvim/yay qu'en x86_64

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/devbox"
BACKUP_DIR="$STATE_DIR/backup/$(date +%Y%m%d-%H%M%S)"
PKG_FILE="$SCRIPT_DIR/packages.txt"
# Unique exception au "zéro AUR" de packages.txt (voir do_packages) — jamais
# dans packages.txt lui-même, qui reste strictement pacman officiel (sur quoi
# repose le check verify "paquets manquants").
AUR_PACKAGES=(worktrunk-bin)
OVERLAY_DIR="$SCRIPT_DIR/overlay"
RC_D="${XDG_CONFIG_HOME:-$HOME/.config}/devbox/rc.d"

STEPS=(user prereq repo packages locale hostname skel vendor shell theme tailscale cli-auth verify)
DRY_RUN=0
FORCE_SKEL=0
FORCE_FULL=0
IS_OMARCHY=0                                           # posé par detect_omarchy
OMARCHY_WHY=""
# étapes qui ÉCRASENT ce qu'un vrai Omarchy gère lui-même (locale, /etc/skel,
# moteur ~/.local/share/omarchy, bashrc/starship/tmux/btop/git, thème actif)
OMARCHY_PROTECTED=(locale skel vendor shell theme)
WITH_TAILSCALE=1                                      # actif par défaut — --no-tailscale pour désactiver
SUDO_NOPASSWD=0
NO_REEXEC=0
ROOT_MODE=0
SKIP_LIST=""
FROM_STEP=""
ONLY_STEP=""

# ------------------------------------------------------------------- sortie --
if [[ -t 1 ]]; then
  B=$'\033[1m'; R=$'\033[0m'; DIM=$'\033[2m'
  RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLU=$'\033[34m'
else
  B=""; R=""; DIM=""; RED=""; GRN=""; YEL=""; BLU=""
fi

step() { printf '\n%s┌─ %s %s%s\n' "$B$BLU" "$1" "$2" "$R"; }
ok()   { printf '  %s✅%s %s\n' "$GRN" "$R" "$*"; }
warn() { printf '  %s⚠️ %s %s\n' "$YEL" "$R" "$*"; }
die()  { printf '\n  %s🔴 %s%s\n\n' "$RED$B" "$*" "$R" >&2; exit 1; }
skip() { printf '  %s🅿️  %s%s\n' "$DIM" "$*" "$R"; }
info() { printf '  %s·%s %s\n' "$DIM" "$R" "$*"; }

run() {
  if (( DRY_RUN )); then printf '  %s$ %s%s\n' "$DIM" "$*" "$R"; return 0; fi
  "$@"
}
# idem mais pour une ligne shell complète (pipes, redirections, heredocs)
runsh() {
  if (( DRY_RUN )); then printf '  %s$ %s%s\n' "$DIM" "$1" "$R"; return 0; fi
  bash -c "$1"
}
# exécute en root : direct si on EST root, via sudo sinon
asroot() {
  if (( ROOT_MODE )); then run "$@"; else run sudo "$@"; fi
}
asrootsh() {
  if (( DRY_RUN )); then printf '  %s$ %s%s\n' "$DIM" "$1" "$R"; return 0; fi
  if (( ROOT_MODE )); then bash -c "$1"; else sudo bash -c "$1"; fi
}

has()      { command -v "$1" >/dev/null 2>&1; }
# 0 = fichiers identiques. cmp (diffutils) n'existe pas sur une Arch nue :
# on retombe sur une somme de contrôle, puis sur "toujours différents".
same_file() {
  [[ -e "$1" && -e "$2" ]] || return 1
  if has cmp;      then cmp -s "$1" "$2"
  elif has diff;   then diff -q "$1" "$2" >/dev/null 2>&1
  elif has sha256sum; then [[ "$(sha256sum <"$1")" == "$(sha256sum <"$2")" ]]
  elif has md5sum;    then [[ "$(md5sum    <"$1")" == "$(md5sum    <"$2")" ]]
  else return 1
  fi
}
is_wsl()   { grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; }

# Vrai Omarchy (distro installée) vs Arch nu que devbox habille : sur le
# premier, le moteur, /etc/skel, bashrc, thème et locale sont déjà gérés par
# Omarchy et par omarchy-update — les écraser casse la machine. Signaux :
# kernel *-omarchy, paquet `omarchy` (jamais installé par devbox, cf. README),
# /usr/share/omarchy, ou un checkout complet (install/ est exclu du
# sparse-checkout de devbox, donc absent d'un moteur vendoré).
detect_omarchy() {
  local why=""
  if [[ "$(uname -r)" == *omarchy* ]]; then why="kernel $(uname -r)"
  elif pacman -Qq omarchy >/dev/null 2>&1; then why="paquet omarchy installé"
  elif [[ -d /usr/share/omarchy ]]; then why="/usr/share/omarchy présent"
  elif [[ -d "$OMARCHY_HOME/install" ]]; then why="checkout complet dans $OMARCHY_HOME"
  fi
  if [[ -n "$why" ]]; then IS_OMARCHY=1; OMARCHY_WHY="$why"; fi
}
# 0 = cette étape est à sauter (ou à réduire) sur un vrai Omarchy
omarchy_guarded() {
  (( IS_OMARCHY )) && ! (( FORCE_FULL )) || return 1
  local x
  for x in "${OMARCHY_PROTECTED[@]}"; do [[ "$x" == "$1" ]] && return 0; done
  return 1
}
stamped()  { [[ -f "$STATE_DIR/stamp.$1" ]]; }
stamp()    { (( DRY_RUN )) || { mkdir -p "$STATE_DIR"; date -Iseconds > "$STATE_DIR/stamp.$1"; }; }

# pacman construit toujours <server>/<nom-de-section>.db : impossible de faire
# pointer un dépôt nommé "omarchy-any" sur le omarchy.db distant (404 garanti).
# Pour un paquet [omarchy] ARCH=any absent de l'arbre local (Omarchy ne les
# mirrore que sous x86_64 — trou de publication, zéro binaire dedans), on va
# donc chercher l'entrée exacte dans la base x86_64 et on récupère le fichier
# directement par URL. Écrit le chemin local sur stdout, ou renvoie 1 :
# refuse tout paquet dont %ARCH% n'est pas "any" (protège des vrais binaires
# x86_64 comme yay/1password-cli, qui ne doivent jamais atterrir sur ARM).
fetch_any_pkg() {
  local pkg="$1" cache="$STATE_DIR/cache"
  mkdir -p "$cache" 2>/dev/null
  local db="$cache/omarchy-x86_64.db"
  [[ -f "$db" ]] || curl -fsSL --max-time 30 \
    "https://pkgs.omarchy.org/${OMARCHY_CHANNEL}/x86_64/omarchy.db" -o "$db" 2>/dev/null || return 1
  local dirent desc arch_val fname
  dirent="$(tar --zstd -tf "$db" 2>/dev/null | grep -E "^${pkg}-[^/]+/\$" | head -1)"
  [[ -n "$dirent" ]] || return 1
  desc="$(tar --zstd -xOf "$db" "${dirent}desc" 2>/dev/null)"
  arch_val="$(printf '%s\n' "$desc" | awk '/^%ARCH%$/{getline; print; exit}')"
  [[ "$arch_val" == "any" ]] || return 1
  fname="$(printf '%s\n' "$desc" | awk '/^%FILENAME%$/{getline; print; exit}')"
  [[ -n "$fname" ]] || return 1
  local dest="$cache/$fname"
  [[ -f "$dest" ]] || curl -fsSL --max-time 60 \
    "https://pkgs.omarchy.org/${OMARCHY_CHANNEL}/x86_64/$fname" -o "$dest" 2>/dev/null || return 1
  printf '%s\n' "$dest"
}
# extrait un .pkg.tar.zst directement sur / (pas de .INSTALL, pas d'entrée
# dans la db pacman — vérifié sans script post-install pour omarchy-nvim ;
# pour omarchy-keyring le seul rôle du .INSTALL est le populate qu'on fait
# déjà nous-mêmes juste après).
extract_any_pkg() {
  asrootsh "tar --zstd -xf '$1' -C / --exclude='.BUILDINFO' --exclude='.INSTALL' --exclude='.MTREE' --exclude='.PKGINFO'"
}

usage() {
  cat <<'USAGE'
devbox/bootstrap.sh — Arch nu ──▶ poste headless omarchy-flavored

  --user <nom>          utilisateur cible (défaut: jgsqware, ou $DEVBOX_USER)
  --sudo-nopasswd       drop-in sudoers NOPASSWD pour wheel (confort, moins sûr)
  --from <étape>        démarre à cette étape (et continue)
  --only <étape>        n'exécute que celle-là
  --skip <a,b>          saute ces étapes
  --with-tailscale      rejoint la tailnet (`tailscale up`, interactif) — actif par défaut
  --no-tailscale        désactive l'étape tailscale (ni join, ni operator/ssh/tag)
  --theme <nom>         thème omarchy (défaut: tokyo-night)
  --locales "<a b>"     locales à générer (défaut: "en_US.UTF-8 fr_BE.UTF-8")
  --start-dir <chemin>  répertoire de démarrage sous WSL (défaut: $HOME, 'keep' = off)
  --hostname <nom>      change le hostname du poste (étape hostname) et celui
                        annoncé à la tailnet ; sans cette option, rien n'est modifié
  --channel <c>         stable (défaut) | rc | edge
  --force-skel          rejoue la copie de /etc/skel même si déjà faite
  --force-full          ignore la détection d'un vrai Omarchy et rejoue TOUTES les
                        étapes (écrase skel/moteur/bashrc/thème/locale d'Omarchy)
  --no-reexec           en root : ne pas se relancer en utilisateur (debug)
  -n, --dry-run         affiche les commandes sans rien exécuter
  -h, --help            cette aide

Étapes : user prereq repo packages locale hostname skel vendor shell theme tailscale cli-auth verify

  user      sudo + utilisateur + groupe wheel + sudoers   (ROOT uniquement)
  prereq    WSL: systemd=true, generateResolvConf=false, [user] default
  repo      pacman-key + dépôt [omarchy] + omarchy-keyring (danse œuf/poule)
  packages  installe packages.txt (ufw auto-skippé sur WSL)
  locale    génère les locales + /etc/locale.conf (Arch nu n'en a aucune)
  hostname  hostnamectl + /etc/hosts (+ wsl.conf, + tailscale si connecté)
            — seulement si --hostname / $DEVBOX_HOSTNAME est fourni
  skel      cp -af /etc/skel/. ~/   (sauvegarde préalable)
  vendor    sparse-checkout du moteur omarchy (~5 Mo) + export OMARCHY_PATH
  shell     ~/.bashrc + rc.d + prompt starship & configs du dépôt omarchy
  theme     omarchy-theme-set en headless + câblage nvim/tmux/zellij
  tailscale tailscaled + tailscale up + accès SSH via la tailnet   (par défaut, --no-tailscale pour désactiver)
  cli-auth  gh auth login + claude auth login --claudeai — interactif, sauté si déjà authentifié
  verify    la table de vérification de fin

Lancé en ROOT, le script s'arrête après `prereq` : il crée l'utilisateur puis
se relance en son nom (ou demande un `wsl --shutdown` d'abord, sous WSL).
USAGE
}

# ------------------------------------------------------------------- args ---
ARGV=("$@")
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)           DEVBOX_USER="$2"; shift 2 ;;
    --sudo-nopasswd)  SUDO_NOPASSWD=1; shift ;;
    --from)           FROM_STEP="$2"; shift 2 ;;
    --only)           ONLY_STEP="$2"; shift 2 ;;
    --skip)           SKIP_LIST="$2"; shift 2 ;;
    --with-tailscale) WITH_TAILSCALE=1; shift ;;
    --no-tailscale)   WITH_TAILSCALE=0; shift ;;
    --theme)          THEME="$2"; shift 2 ;;
    --locales)        LOCALES="$2"; shift 2 ;;
    --start-dir)      START_DIR="$2"; shift 2 ;;
    --hostname)       TS_HOSTNAME="$2"; HOSTNAME_SET=1; shift 2 ;;
    --channel)        OMARCHY_CHANNEL="$2"; OMARCHY_REPO_URL="https://pkgs.omarchy.org/${2}/\$arch"; shift 2 ;;
    --force-skel)     FORCE_SKEL=1; shift ;;
    --force-full)     FORCE_FULL=1; shift ;;
    --no-reexec)      NO_REEXEC=1; shift ;;
    -n|--dry-run)     DRY_RUN=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *) die "option inconnue : $1  (--help)" ;;
  esac
done

# arguments à repasser au script quand il se relance en utilisateur
passthru() {
  local a=(--from repo --user "$DEVBOX_USER" --theme "$THEME" --channel "$OMARCHY_CHANNEL" --hostname "$TS_HOSTNAME" --locales "$LOCALES")
  [[ -n "$START_DIR" ]] && a+=(--start-dir "$START_DIR")
  (( DRY_RUN ))        && a+=(--dry-run)
  (( FORCE_SKEL ))     && a+=(--force-skel)
  (( FORCE_FULL ))     && a+=(--force-full)
  (( WITH_TAILSCALE )) || a+=(--no-tailscale)
  [[ -n "$SKIP_LIST" ]] && a+=(--skip "$SKIP_LIST")
  printf '%q ' "${a[@]}"
}

wanted() {
  local s="$1"
  [[ -n "$ONLY_STEP" ]] && { [[ "$s" == "$ONLY_STEP" ]]; return; }
  [[ ",$SKIP_LIST," == *",$s,"* ]] && return 1
  if [[ -n "$FROM_STEP" ]]; then
    local seen=0 x
    for x in "${STEPS[@]}"; do
      [[ "$x" == "$FROM_STEP" ]] && seen=1
      [[ "$x" == "$s" ]] && { (( seen )); return; }
    done
  fi
  return 0
}

# ------------------------------------------------------------- garde-fous ---
preflight() {
  [[ "$(uname -s)" == "Linux" ]] || die "Linux uniquement (détecté: $(uname -s))."
  has pacman || die "pacman introuvable — ce script cible Arch (ou dérivé)."
  [[ -r "$PKG_FILE" ]] || die "packages.txt introuvable à côté du script ($PKG_FILE)."

  if [[ $EUID -eq 0 ]]; then
    ROOT_MODE=1
    if [[ -n "$ONLY_STEP" && "$ONLY_STEP" != "user" && "$ONLY_STEP" != "prereq" ]]; then
      die "En root, seules les étapes 'user' et 'prereq' sont permises.
  Les étapes suivantes écrivent dans \$HOME : elles doivent tourner en $DEVBOX_USER."
    fi
  else
    has sudo || die "sudo requis (ou relance ce script en root pour l'installer)."
    sudo -v || die "sudo refusé."
    if [[ "$(id -un)" != "$DEVBOX_USER" ]]; then
      warn "tu es '$(id -un)', pas '$DEVBOX_USER' — l'install ira dans $HOME"
    fi
  fi
  # un run précédent a pu créer ces dossiers en root (sudo garde $HOME) :
  # on répare plutôt que d'échouer sur un "Permission denied".
  if (( ! ROOT_MODE )); then
    local d
    for d in "$STATE_DIR" "$STATE_DIR/backup"; do
      if [[ -e "$d" && ! -w "$d" ]]; then
        warn "$d appartient à root (run précédent en sudo) — correction"
        sudo chown -R "$(id -un):$(id -gn)" "$STATE_DIR"
        break
      fi
    done
  fi
  mkdir -p "$STATE_DIR" 2>/dev/null || die "impossible d'écrire dans $STATE_DIR
  Vérifie les droits : ls -ld $STATE_DIR
  Réparation : sudo chown -R $(id -un):$(id -gn) \"$HOME/.local\""
}

# ======================================================== ⓪ utilisateur =====
do_user() {
  step "⓪" "Utilisateur $DEVBOX_USER"
  if (( ! ROOT_MODE )); then
    skip "déjà en utilisateur non-root ($(id -un))"
    return 0
  fi

  has sudo || { info "sudo absent — installation"; run pacman -Sy --noconfirm sudo; }

  if id -u "$DEVBOX_USER" >/dev/null 2>&1; then
    ok "l'utilisateur existe déjà"
  else
    run useradd -m -G wheel -s /bin/bash "$DEVBOX_USER"
    ok "utilisateur créé (home + bash + groupe wheel)"
    if (( DRY_RUN )); then
      info "mot de passe : passwd $DEVBOX_USER"
    elif [[ -t 0 ]]; then
      printf '\n  %sMot de passe pour %s :%s\n' "$B" "$DEVBOX_USER" "$R"
      until passwd "$DEVBOX_USER"; do warn "recommence"; done
    else
      warn "pas de TTY : mot de passe NON défini → compte verrouillé.
     Défini-le ensuite avec : passwd $DEVBOX_USER"
    fi
  fi

  # appartenance à wheel même si le compte préexistait
  id -nG "$DEVBOX_USER" | tr ' ' '\n' | grep -qx wheel \
    && ok "membre de wheel" \
    || { run usermod -aG wheel "$DEVBOX_USER"; ok "ajouté à wheel"; }

  # wheel → sudo
  if grep -qE '^[[:space:]]*%wheel[[:space:]]+ALL=\(ALL(:ALL)?\)[[:space:]]+ALL' /etc/sudoers; then
    ok "wheel déjà autorisé dans /etc/sudoers"
  else
    run cp -a /etc/sudoers "/etc/sudoers.devbox.bak"
    runsh "sed -i 's/^# *%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers"
    if ! (( DRY_RUN )) && ! visudo -c >/dev/null 2>&1; then
      cp -a /etc/sudoers.devbox.bak /etc/sudoers
      die "/etc/sudoers invalide après édition — restauré depuis la sauvegarde."
    fi
    ok "wheel autorisé dans /etc/sudoers (validé par visudo -c)"
  fi

  if (( SUDO_NOPASSWD )); then
    runsh "printf '%%wheel ALL=(ALL:ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/99-devbox-wheel-nopasswd"
    run chmod 440 /etc/sudoers.d/99-devbox-wheel-nopasswd
    warn "NOPASSWD actif pour wheel (/etc/sudoers.d/99-devbox-wheel-nopasswd)"
  else
    [[ -f /etc/sudoers.d/99-devbox-wheel-nopasswd ]] \
      && info "NOPASSWD déjà en place (posé par un run précédent)"
  fi
}

# ============================================================ ① prereq WSL ==
do_prereq() {
  step "①" "Prérequis WSL"
  if ! is_wsl; then
    skip "pas sous WSL — rien à faire"
    return 0
  fi

  local need_write=0
  if [[ ! -f /etc/wsl.conf ]]; then
    need_write=1
  else
    grep -qE '^[[:space:]]*systemd[[:space:]]*=[[:space:]]*true' /etc/wsl.conf || need_write=1
    grep -qE '^[[:space:]]*generateResolvConf[[:space:]]*=[[:space:]]*false' /etc/wsl.conf || need_write=1
    grep -qE "^[[:space:]]*default[[:space:]]*=[[:space:]]*$DEVBOX_USER" /etc/wsl.conf || need_write=1
  fi

  if (( need_write )); then
    if (( ! ROOT_MODE )) && ! sudo -n true 2>/dev/null; then :; fi
    if [[ -f /etc/wsl.conf ]]; then
      run mkdir -p "$BACKUP_DIR"
      asroot cp -a /etc/wsl.conf "$BACKUP_DIR/wsl.conf"
      info "sauvegarde: $BACKUP_DIR/wsl.conf"
    fi
    local conf="[boot]
systemd=true

[network]
generateResolvConf=false

[user]
default=$DEVBOX_USER"
    asrootsh "cat > /etc/wsl.conf <<'WSLCONF'
$conf
WSLCONF"
    ok "/etc/wsl.conf écrit (systemd=true, generateResolvConf=false, default=$DEVBOX_USER)"
  else
    ok "/etc/wsl.conf déjà conforme"
  fi

  if [[ ! -d /run/systemd/system ]]; then
    local distro="${WSL_DISTRO_NAME:-<Distro>}"
    printf '
  %s%s⏸  REDÉMARRAGE WSL REQUIS%s

  systemd n%st pas actif. Depuis %sPowerShell (côté Windows)%s :

      %swsl --manage %s --set-default-user %s%s
      %swsl --shutdown%s

  %s⚠️  La 1re ligne n%st PAS optionnelle :%s le %sDefaultUid%s du registre est
  prioritaire sur le %s[user] default%s de /etc/wsl.conf. Sans elle, la WSL
  rouvre en root. (WSL trop ancien pour --manage : %s%s.exe config --default-user %s%s)

  Rouvre ensuite la WSL — tu y seras %s%s%s — puis :

      %scd %s && ./%s --from repo%s

  %sDébloquage sans redémarrer :%s  %ssu - %s%s

' "$YEL" "$B" "$R" "'es" "$B" "$R" \
  "$B" "$distro" "$DEVBOX_USER" "$R" "$B" "$R" \
  "$YEL" "'es" "$R" "$B" "$R" "$B" "$R" "$B" "${distro,,}" "$DEVBOX_USER" "$R" \
  "$B" "$DEVBOX_USER" "$R" "$B" "$SCRIPT_DIR" "$SCRIPT_NAME" "$R" \
  "$DIM" "$R" "$B" "$DEVBOX_USER" "$R"
    exit 10
  fi
  ok "systemd actif ($(systemctl is-system-running 2>/dev/null || echo '?'))"

  [[ -e /dev/net/tun ]] \
    && ok "/dev/net/tun présent (tailscale en mode TUN)" \
    || warn "/dev/net/tun absent → tailscale tombera en userspace-networking"
}

# ------------------------------------- bascule root ──▶ utilisateur --------
reexec_as_user() {
  local target="$SCRIPT_DIR"
  # le script doit être lisible par l'utilisateur : /root ne l'est pas
  if [[ "$SCRIPT_DIR" == /root/* || "$SCRIPT_DIR" == /root ]]; then
    local home; home="$(getent passwd "$DEVBOX_USER" | cut -d: -f6)"
    target="$home/devbox"
    run mkdir -p "$target"
    run cp -a "$SCRIPT_DIR/." "$target/"
    run chown -R "$DEVBOX_USER:$DEVBOX_USER" "$target"
    info "script recopié dans $target (illisible depuis /root)"
  fi

  printf '\n  %s↪ bascule en %s%s\n' "$B$BLU" "$DEVBOX_USER" "$R"
  local cmd="cd $(printf '%q' "$target") && ./$(printf '%q' "$SCRIPT_NAME") $(passthru)"
  if (( DRY_RUN )); then
    printf '  %s$ su - %s -c "%s"%s\n\n' "$DIM" "$DEVBOX_USER" "$cmd" "$R"
    exit 0
  fi
  exec su - "$DEVBOX_USER" -c "$cmd"
}

# ====================================================== ② dépôt + keyring ===
do_repo() {
  step "②" "Keyring pacman + dépôt [omarchy] ($OMARCHY_CHANNEL)"

  # egress : le bootstrap vient d'internet direct, PAS de la tailnet
  local probe="https://pkgs.omarchy.org/${OMARCHY_CHANNEL}/x86_64/omarchy.db"
  if has curl; then
    if curl -fsI --max-time 15 "$probe" >/dev/null 2>&1; then
      ok "pkgs.omarchy.org joignable"
    else
      die "pkgs.omarchy.org injoignable ($probe).
  L'egress est probablement filtré. Deux issues :
    · faire de ce poste un client tailscale AVANT, avec un exit node :
        sudo pacman -S tailscale && sudo systemctl enable --now tailscaled
        sudo tailscale up --exit-node=<node> --hostname=$TS_HOSTNAME
    · ou passer par un proxy (XferCommand dans /etc/pacman.conf)"
    fi
  fi

  if [[ ! -d /etc/pacman.d/gnupg ]]; then
    asroot pacman-key --init
    asroot pacman-key --populate archlinux
    ok "keyring Arch initialisé"
  else
    ok "keyring Arch déjà initialisé"
  fi

  # nettoyage d'un run précédent : [omarchy-any] (repli par second dépôt,
  # abandonné car pacman réclame toujours <section>.db — jamais synchronisable)
  # a pu être écrit par une version antérieure de ce script.
  if grep -q '^\[omarchy-any\]' /etc/pacman.conf 2>/dev/null; then
    asrootsh "awk '
      /^# devbox \(repli/ {skip=1}
      /^\[omarchy-any\]/  {skip=1}
      skip && /^\[/ && \$0 !~ /^\[omarchy-any\]/ {skip=0}
      !skip
    ' /etc/pacman.conf > /etc/pacman.conf.devbox-tmp && mv /etc/pacman.conf.devbox-tmp /etc/pacman.conf"
    warn "[omarchy-any] (résidu d'un run précédent, jamais synchronisable) retiré de /etc/pacman.conf"
  fi

  local need_sync=0
  if grep -q '^\[omarchy\]' /etc/pacman.conf 2>/dev/null; then
    ok "dépôt [omarchy] déjà déclaré"
  else
    run mkdir -p "$BACKUP_DIR"
    asroot cp -a /etc/pacman.conf "$BACKUP_DIR/pacman.conf"
    info "sauvegarde: $BACKUP_DIR/pacman.conf"

    # ŒUF/POULE : le dépôt est signé mais son keyring est DANS le dépôt.
    # SigLevel = Never le temps d'un -Sy, puis on referme.
    asrootsh "printf '\n# devbox\n[omarchy]\nSigLevel = Never\nServer = $OMARCHY_REPO_URL\n' >> /etc/pacman.conf"
    need_sync=1
  fi

  (( need_sync )) && asroot pacman -Sy

  if grep -A3 '^\[omarchy\]' /etc/pacman.conf | grep -q 'SigLevel = Required'; then
    ok "dépôt [omarchy] déjà signé"
  elif pacman -Si omarchy-keyring >/dev/null 2>&1; then
    # x86_64 : omarchy-keyring est dans l'arbre local, chemin normal.
    asroot pacman -S --noconfirm --needed omarchy-keyring
    asroot pacman-key --populate omarchy
    asrootsh "sed -i '/^\[omarchy\]/,\$ s/^SigLevel = Never\$/SigLevel = Required DatabaseOptional/' /etc/pacman.conf"
    asroot pacman -Sy
    ok "dépôt [omarchy] ajouté et refermé (SigLevel = Required DatabaseOptional)"
  else
    # $ARCH != x86_64 : omarchy-keyring (ARCH=any) manque de l'arbre local —
    # trou de publication chez Omarchy, pas une contrainte technique (voir
    # fetch_any_pkg). On extrait le paquet directement plutôt que de rester
    # en SigLevel = Never indéfiniment.
    local pkgfile
    if pkgfile="$(fetch_any_pkg omarchy-keyring)"; then
      extract_any_pkg "$pkgfile"
      asroot pacman-key --populate omarchy
      asrootsh "sed -i '/^\[omarchy\]/,\$ s/^SigLevel = Never\$/SigLevel = Required DatabaseOptional/' /etc/pacman.conf"
      asroot pacman -Sy
      ok "omarchy-keyring récupéré depuis l'arbre x86_64 (ARCH=any) — dépôt [omarchy] refermé"
      info "installé hors pacman (fichiers seulement, pas de suivi par la db — 'pacman -Q omarchy-keyring' restera vide)"
    else
      warn "omarchy-keyring introuvable (ni $ARCH ni x86_64) — dépôt [omarchy] gardé en SigLevel = Never."
    fi
  fi
}

# ============================================================= ③ paquets ====
pkg_list() {
  # retire commentaires (pleine ligne ET de fin de ligne), espaces, lignes vides
  sed -e 's/#.*$//' -e 's/[[:space:]]//g' "$PKG_FILE" | grep -v '^$'
}

# yay n'a de binaire prébuilt que pour x86_64 (dépôt [omarchy]) — sur les
# autres ARCH (aarch64 notamment), aucun chemin pacman/fetch_any_pkg ne
# l'installe. yay est en Go, il compile sans souci sur ARM : dernier recours,
# build depuis l'AUR (git + makepkg -si). Appelée seulement si AUR_PACKAGES
# a besoin de yay et qu'il est encore absent après la boucle pacman normale.
bootstrap_yay_from_source() {
  has yay && return 0
  if (( DRY_RUN )); then
    info "yay absent — aurait construit depuis les sources (AUR : base-devel+git, makepkg -si)"
    return 0
  fi
  info "yay absent (aucun binaire pour $ARCH) — build depuis les sources (AUR)"
  asroot pacman -S --needed --noconfirm base-devel git \
    || { warn "base-devel/git indisponibles — build de yay impossible"; return 1; }
  local build_dir="$STATE_DIR/build/yay"
  rm -rf "$build_dir"
  mkdir -p "$(dirname "$build_dir")"
  git clone --depth 1 https://aur.archlinux.org/yay.git "$build_dir" \
    || { warn "git clone AUR/yay.git a échoué"; return 1; }
  ( cd "$build_dir" && makepkg -si --needed --noconfirm ) \
    || { warn "makepkg de yay a échoué — relance à la main : cd $build_dir && makepkg -si"; return 1; }
  has yay && ok "yay construit depuis les sources (AUR)"
}

# Fallback TEMPORAIRE pour worktrunk-bin : le PKGBUILD AUR a
# sha256sums_x86_64 == sha256sums_aarch64 alors que ce sont deux archives
# GitHub différentes — bug upstream (à retirer dès qu'il est corrigé côté
# AUR ; réf. commit 6518ea6). yay/makepkg refuse à raison d'installer un
# fichier dont le hash ne correspond pas au PKGBUILD. En attendant, on
# récupère le binaire `wt` directement depuis les releases GitHub du projet,
# vérifié contre le .sha256 publié par le projet pour cet asset précis (pas
# le PKGBUILD cassé) — donc pas d'install à l'aveugle malgré le contournement.
install_worktrunk_fallback() {
  has wt && return 0
  if (( DRY_RUN )); then
    info "worktrunk (wt) — aurait installé depuis les releases GitHub (dry-run)"
    return 0
  fi

  local gh_arch asset url tmp
  case "$ARCH" in
    x86_64|aarch64) gh_arch="$ARCH" ;;
    *) warn "worktrunk : pas de release GitHub connue pour $ARCH — sauté"; return 1 ;;
  esac
  asset="worktrunk-${gh_arch}-unknown-linux-musl.tar.xz"

  url="$(curl -fsSL https://api.github.com/repos/max-sixty/worktrunk/releases/latest \
    | grep -o "\"browser_download_url\": *\"[^\"]*${asset}\"" | grep -o 'https://[^"]*' | head -1)"
  [[ -n "$url" ]] || { warn "worktrunk : asset $asset introuvable dans la dernière release GitHub"; return 1; }

  tmp="$STATE_DIR/dl/worktrunk"
  rm -rf "$tmp"; mkdir -p "$tmp"
  curl -fsSL "$url" -o "$tmp/$asset" || { warn "worktrunk : téléchargement échoué ($url)"; return 1; }
  # le projet publie un .sha256 par asset (contrairement au PKGBUILD AUR,
  # qui lui est cassé) : vérification réelle, pas d'install à l'aveugle.
  curl -fsSL "${url}.sha256" -o "$tmp/$asset.sha256" \
    || { warn "worktrunk : téléchargement du .sha256 échoué — installation refusée sans vérification"; return 1; }
  ( cd "$tmp" && sha256sum -c "$asset.sha256" >/dev/null ) \
    || { warn "worktrunk : sha256 invalide — installation refusée"; return 1; }

  tar -xJf "$tmp/$asset" -C "$tmp" || { warn "worktrunk : extraction échouée"; return 1; }
  mkdir -p "$HOME/.local/bin"
  install -Dm755 "$tmp/worktrunk-${gh_arch}-unknown-linux-musl/wt" "$HOME/.local/bin/wt" \
    || { warn "worktrunk : installation du binaire échouée"; return 1; }
  rm -rf "$tmp"
  ok "worktrunk (wt) installé depuis les releases GitHub (sha256 vérifié) — fallback temporaire, PKGBUILD AUR cassé. ~/.local/bin/wt"
}

do_packages() {
  step "③" "Paquets"
  local pkgs=() dropped=() unavailable=() rescued=() p
  while read -r p; do
    if [[ "$p" == "ufw" ]] && is_wsl; then dropped+=("$p"); continue; fi
    # certains paquets (surtout ceux de [omarchy]) n'existent qu'en x86_64 —
    # on vérifie contre les dépôts synchronisés plutôt que de figer une liste.
    if pacman -Si "$p" >/dev/null 2>&1; then pkgs+=("$p"); continue; fi
    # absent de l'arbre local : peut-être un ARCH=any publié seulement en
    # x86_64 (cf. fetch_any_pkg) — sinon vrai binaire indispo pour $ARCH.
    local pkgfile
    if pkgfile="$(fetch_any_pkg "$p")"; then rescued+=("$p:$pkgfile"); else unavailable+=("$p"); fi
  done < <(pkg_list)

  (( ${#dropped[@]} )) && info "skippés sur WSL : ${dropped[*]} (pas de netfilter persistant)"
  (( ${#unavailable[@]} )) && warn "indisponibles pour $ARCH (absents de core/extra/[omarchy], même en ARCH=any) : ${unavailable[*]}
  → à installer/remplacer à la main si besoin (AUR proscrit ici)."
  info "${#pkgs[@]} paquets demandés"

  asroot pacman -S --needed --noconfirm "${pkgs[@]}" \
    || die "pacman a échoué. Relance à la main : sudo pacman -S --needed ${pkgs[*]}"
  ok "${#pkgs[@]} paquets installés / à jour"

  if (( ${#rescued[@]} )); then
    local names=("${rescued[@]%%:*}")
    for r in "${rescued[@]}"; do extract_any_pkg "${r#*:}"; done
    info "ARCH=any récupérés depuis l'arbre x86_64 : ${names[*]}
  (hors pacman — fichiers seulement, pas de suivi par la db)"
  fi

  if has docker; then
    asroot systemctl enable --now docker.socket || warn "docker.socket non activé"
    if ! id -nG "$(id -un)" | tr ' ' '\n' | grep -qx docker; then
      asroot usermod -aG docker "$(id -un)"
      info "groupe docker ajouté — effectif à la prochaine session"
    fi
  fi

  # AUR_PACKAGES : exception délibérée au "zéro AUR", jamais via `asroot` —
  # makepkg (derrière yay) refuse de tourner en root, sudo n'est appelé par
  # yay lui-même que pour le `pacman -U` final.
  if (( ${#AUR_PACKAGES[@]} )); then
    has yay || bootstrap_yay_from_source
    local a
    for a in "${AUR_PACKAGES[@]}"; do
      if pacman -Qq "$a" >/dev/null 2>&1; then
        ok "$a déjà installé (AUR)"
      elif ! has yay; then
        warn "$a (AUR) sauté — yay indisponible même après tentative de build depuis les sources"
      elif ! run yay -S --needed --noconfirm "$a"; then
        warn "$a (AUR) a échoué"
        [[ "$a" == worktrunk-bin ]] && install_worktrunk_fallback
      fi
    done
  fi
}

# ============================================================= ④ locales ====
do_locale() {
  step "④" "Locales"
  # Une Arch nue (image WSL, conteneur) ne génère AUCUNE locale : le .bashrc
  # livré par omarchy exporte LANG=en_US.UTF-8 → avalanche de warnings bash.
  local want first missing=()
  first="${LOCALES%% *}"
  for want in $LOCALES; do
    if locale -a 2>/dev/null | tr 'A-Z' 'a-z' | tr -d '-' | grep -qx "$(echo "$want" | tr 'A-Z' 'a-z' | tr -d '-')"; then
      info "$want déjà générée"
    else
      missing+=("$want")
    fi
  done

  if (( ${#missing[@]} )); then
    for want in "${missing[@]}"; do
      asrootsh "sed -i 's/^#\s*${want} \(UTF-8\)\?$/${want} UTF-8/' /etc/locale.gen"
      grep -qE "^${want}" /etc/locale.gen 2>/dev/null \
        || asrootsh "printf '%s UTF-8\n' '${want}' >> /etc/locale.gen"
    done
    asroot locale-gen
    ok "générées : ${missing[*]}"
  else
    ok "toutes les locales demandées sont présentes"
  fi

  if grep -qE "^LANG=${first}" /etc/locale.conf 2>/dev/null; then
    ok "/etc/locale.conf → LANG=$first"
  else
    asrootsh "printf 'LANG=%s\n' '${first}' > /etc/locale.conf"
    ok "/etc/locale.conf écrit (LANG=$first)"
  fi
}

# ============================================================ ④b hostname ====
do_hostname() {
  step "④b" "Hostname"
  if (( ! HOSTNAME_SET )); then
    skip "non demandé — relance avec --hostname <nom> (ou --only hostname --hostname <nom>)"
    return 0
  fi
  local new="$TS_HOSTNAME" cur
  cur="$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo '?')"

  # RFC 1123 : 1-63 car., alphanumérique + '-', ni début ni fin par '-'
  [[ "$new" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] \
    || die "hostname invalide : '$new' (a-z 0-9 et '-', 63 car. max, pas de '-' en bord)"

  if [[ "$cur" == "$new" ]]; then
    ok "hostname déjà '$new'"
  else
    if [[ -d /run/systemd/system ]] && has hostnamectl; then
      asroot hostnamectl set-hostname "$new"
    else
      asrootsh "printf '%s\n' '$new' > /etc/hostname"
      asroot hostname "$new"
    fi

    # /etc/hosts : 127.0.1.1 → nouveau nom (sudo résout le hostname via ce fichier)
    if grep -qE '^127\.0\.1\.1[[:space:]]' /etc/hosts 2>/dev/null; then
      asrootsh "sed -i -E 's/^(127\.0\.1\.1[[:space:]]+).*/\1$new/' /etc/hosts"
    else
      asrootsh "printf '127.0.1.1\t%s\n' '$new' >> /etc/hosts"
    fi
    ok "hostname : $cur ──▶ $new"
  fi

  # WSL réécrit /etc/hostname (et /etc/hosts) à chaque démarrage depuis wsl.conf
  if is_wsl && [[ -f /etc/wsl.conf ]]; then
    if grep -qE "^[[:space:]]*hostname[[:space:]]*=[[:space:]]*$new[[:space:]]*$" /etc/wsl.conf; then
      ok "wsl.conf [network] hostname=$new déjà en place"
    else
      run mkdir -p "$BACKUP_DIR"
      asroot cp -a /etc/wsl.conf "$BACKUP_DIR/wsl.conf.hostname"
      if grep -qE '^[[:space:]]*hostname[[:space:]]*=' /etc/wsl.conf; then
        asrootsh "sed -i -E 's/^([[:space:]]*hostname[[:space:]]*=).*/\1$new/' /etc/wsl.conf"
      elif grep -qE '^\[network\]' /etc/wsl.conf; then
        asrootsh "sed -i '/^\[network\]/a hostname=$new' /etc/wsl.conf"
      else
        asrootsh "printf '\n[network]\nhostname=%s\n' '$new' >> /etc/wsl.conf"
      fi
      ok "wsl.conf : hostname=$new (persistant au prochain wsl --shutdown)"
    fi
  fi

  # tailnet : le nom de la machine suit, sans repasser par l'auth interactive
  if ! (( DRY_RUN )) && has tailscale && tailscale status >/dev/null 2>&1; then
    asroot tailscale set --hostname="$new" && ok "tailscale : hostname=$new"
  fi
}

# ========================================================= ⑤ /etc/skel =====
do_skel() {
  step "⑤" "Configs livrées par les paquets (/etc/skel)"
  if stamped skel && ! (( FORCE_SKEL )); then
    skip "déjà fait le $(cat "$STATE_DIR/stamp.skel" 2>/dev/null) — --force-skel pour rejouer"
    return 0
  fi
  [[ -d /etc/skel ]] || die "/etc/skel absent — l'étape ③ a-t-elle réussi ?"

  # cp -af ÉCRASE : on sauvegarde ce qui existe déjà et qui serait touché
  local touched=() src rel
  while IFS= read -r -d '' src; do
    rel="${src#/etc/skel/}"
    [[ -e "$HOME/$rel" ]] && touched+=("$rel")
  done < <(find /etc/skel -mindepth 1 -maxdepth 1 -print0)

  if (( ${#touched[@]} )); then
    run mkdir -p "$BACKUP_DIR"
    for rel in "${touched[@]}"; do
      run cp -a "$HOME/$rel" "$BACKUP_DIR/" 2>/dev/null || true
    done
    warn "${#touched[@]} entrées existantes écrasées → sauvegardées dans $BACKUP_DIR"
  fi

  run cp -af /etc/skel/. "$HOME/"
  stamp skel
  ok "/etc/skel appliqué ($(du -sh /etc/skel 2>/dev/null | cut -f1))"
}

# ====================================================== ⑥ moteur omarchy ====
do_vendor() {
  step "⑥" "Moteur omarchy vendoré (~5 Mo)"
  # ⛔ surtout PAS `pacman -S omarchy` : 22 deps / 121 Mo (hyprland, sddm…)
  # Patterns no-cone : on prend bin/, default/ et themes/ SAUF les images
  # (fonds d'écran + previews = l'essentiel des 64 Mo de themes/).
  local sparse=(
    '/bin/**' '/default/**' '/config/**' '/themes/**'
    '!/themes/*/backgrounds/**' '!/themes/**/*.png'
    '!/themes/**/*.jpg' '!/themes/**/*.jpeg'
  )

  if [[ -d "$OMARCHY_HOME/.git" ]]; then
    run git -C "$OMARCHY_HOME" fetch --depth=1 origin HEAD
    run git -C "$OMARCHY_HOME" reset --hard FETCH_HEAD
    ok "moteur mis à jour"
  else
    run git clone --depth=1 --filter=blob:none --sparse "$OMARCHY_GIT" "$OMARCHY_HOME"
    ok "moteur cloné → $OMARCHY_HOME"
  fi

  # toujours ré-appliqué : rattrape un sparse-checkout trop étroit d'un run précédent
  run git -C "$OMARCHY_HOME" sparse-checkout set --no-cone "${sparse[@]}"

  if ! (( DRY_RUN )); then
    local n; n=$(ls "$OMARCHY_HOME/themes" 2>/dev/null | wc -l | tr -d ' ')
    (( n > 0 )) || die "aucun thème matérialisé dans $OMARCHY_HOME/themes — sparse-checkout ko."
    ok "$n thèmes disponibles"
  fi

  info "taille : $(du -sh "$OMARCHY_HOME" 2>/dev/null | cut -f1 || echo '?')"
}

# =============================================================== ⑦ shell ====
# Sur un vrai poste Omarchy, le prompt (starship), les alias, les fonctions et
# la chaîne bash viennent du paquet `omarchy` (/usr/share/omarchy + /etc/skel).
# On ne l'installe pas → on rétablit la même chaîne depuis le dépôt vendoré.
DOTCONFIGS=(
  config/starship.toml:.config/starship.toml
  config/tmux/tmux.conf:.config/tmux/tmux.conf
  config/lazygit/config.yml:.config/lazygit/config.yml
  config/btop/btop.conf:.config/btop/btop.conf
  config/git/config:.config/git/config
)

# module [hostname] du prompt : repère visuel rapide entre machines. starship
# affiche déjà $hostname si on l'active ; ici on lui donne en plus une
# couleur stable dérivée du hostname (mêmes 10 nœuds ──▶ mêmes 10 couleurs,
# jamais deux runs différents sur la même machine). DOTCONFIGS écrase
# starship.toml à chaque run (cp -af) : repartir d'une table [hostname]
# propre à chaque fois suffit, pas besoin de marqueurs pour dédupliquer.
configure_starship_hostname() {
  local toml="$HOME/.config/starship.toml"
  [[ -f "$toml" ]] || { warn "starship.toml absent — hostname du prompt non configuré"; return 0; }

  local host palette color h
  host="$(hostname -s 2>/dev/null || echo "$TS_HOSTNAME")"
  palette=(
    "#f38ba8" "#fab387" "#f9e2af" "#a6e3a1" "#94e2d5"
    "#89dceb" "#89b4fa" "#74c7ec" "#cba6f7" "#f5c2e7"
  )
  h="$(printf '%s' "$host" | cksum | cut -d' ' -f1)"
  color="${palette[$(( h % ${#palette[@]} ))]}"

  if (( DRY_RUN )); then
    info "hostname du prompt : $host → $color (dry-run, non écrit)"
    return 0
  fi

  # retire une éventuelle table [hostname] existante (vendorée ou d'un run précédent)
  # + injecte $hostname dans le `format` top-level : le vendoré omarchy a un
  # format personnalisé ("[$directory$git_branch$git_status]($style)$character",
  # sans $all) — activer [hostname] ne suffit pas, starship n'affiche QUE ce
  # que `format` référence explicitement.
  awk '
    /^\[hostname\]/ { skip=1; next }
    /^\[/ && skip   { skip=0 }
    !skip
  ' "$toml" | awk '
    !done && /^\[/ { done=1 }
    !done && /^format[[:space:]]*=/ && $0 !~ /\$hostname/ {
      sub(/= *"/, "&$hostname ")
    }
    { print }
  ' > "$toml.tmp" && mv "$toml.tmp" "$toml"

  cat >> "$toml" <<EOF

[hostname]
ssh_only = false
disabled = false
style = "bold $color"
format = "[\$hostname](\$style) "
EOF
  ok "hostname du prompt : $host ($color)"
}

# Sur un vrai Omarchy : ni ~/.bashrc, ni tmux/btop/git, ni le moteur — on ne
# touche qu'au hostname coloré du prompt, en place et avec sauvegarde de
# starship.toml avant la toute première modification.
do_shell_light() {
  step "⑦" "Prompt : hostname coloré (Omarchy détecté — reste de l'étape sauté)"
  local toml="$HOME/.config/starship.toml"
  if [[ -f "$toml" ]] && ! grep -q '^format.*\$hostname' "$toml"; then
    run mkdir -p "$BACKUP_DIR/.config"
    run cp -a "$toml" "$BACKUP_DIR/.config/starship.toml"
    info "sauvegarde: $BACKUP_DIR/.config/starship.toml"
  fi
  configure_starship_hostname
}

do_shell() {
  step "⑦" "Shell omarchy (prompt, alias, fonctions)"
  [[ -d "$OMARCHY_HOME/default/bash" ]] \
    || die "$OMARCHY_HOME/default/bash absent — l'étape ⑥ a-t-elle tourné ?"

  # ~/.bashrc et ~/.bash_profile appartiennent au dépôt : sauvegarde puis écrase
  local f dst
  for f in bashrc bash_profile; do
    dst="$HOME/.$f"
    [[ -r "$OVERLAY_DIR/bash/$f" ]] || continue
    if [[ -e "$dst" ]] && ! same_file "$OVERLAY_DIR/bash/$f" "$dst"; then
      run mkdir -p "$BACKUP_DIR"
      run cp -a "$dst" "$BACKUP_DIR/.$f"
      info "sauvegarde: $BACKUP_DIR/.$f"
    fi
    run cp -af "$OVERLAY_DIR/bash/$f" "$dst"
  done
  ok "~/.bashrc + ~/.bash_profile déployés (chaîne omarchy → \$OMARCHY_PATH)"

  # les rc.d : les vrais réglages, versionnés
  if [[ -d "$OVERLAY_DIR/bash/rc.d" ]]; then
    run mkdir -p "$RC_D"
    run cp -af "$OVERLAY_DIR/bash/rc.d/." "$RC_D/"
    ok "overlay rc.d déposé → $RC_D ($(ls "$OVERLAY_DIR/bash/rc.d" | wc -l | tr -d ' ') fichiers)"
  fi

  # override local (NE converge pas : propre à ce nœud)
  if [[ -n "$START_DIR" ]]; then
    run mkdir -p "$RC_D"
    runsh "printf 'export DEVBOX_START_DIR=%q\\n' '$START_DIR' > $(printf '%q' "$RC_D")/05-local-start-dir.sh"
    ok "override local : DEVBOX_START_DIR=$START_DIR"
  fi

  # configs livrées par le dépôt omarchy (prompt starship en tête)
  local pair src rel n=0
  for pair in "${DOTCONFIGS[@]}"; do
    src="$OMARCHY_HOME/${pair%%:*}"; rel="${pair#*:}"
    [[ -r "$src" ]] || { warn "absent du dépôt : ${pair%%:*}"; continue; }
    if [[ -e "$HOME/$rel" ]] && ! same_file "$src" "$HOME/$rel"; then
      run mkdir -p "$BACKUP_DIR/$(dirname "$rel")"
      run cp -a "$HOME/$rel" "$BACKUP_DIR/$rel"
    fi
    run mkdir -p "$HOME/$(dirname "$rel")"
    run cp -af "$src" "$HOME/$rel"
    n=$((n+1))
  done
  ok "$n configs installées (starship.toml, tmux, lazygit, btop, git)"
  configure_starship_hostname

  # terminfo Ghostty (TERM=xterm-ghostty) : Ghostty ne le publie pas en tant
  # que source (généré à sa compilation) et [omarchy] ne le publie qu'en
  # ARCH=x86_64 alors que le contenu est 100% portable (juste des séquences
  # d'échappement) — vendoré dans overlay/terminfo/, compilé ici avec tic.
  # Sans ça : `missing or unsuitable terminal: xterm-ghostty` en SSH depuis
  # un client Ghostty vers cette machine.
  local ti_src="$OVERLAY_DIR/terminfo/xterm-ghostty.terminfo"
  if [[ -r "$ti_src" ]] && has tic && ! infocmp xterm-ghostty >/dev/null 2>&1; then
    if asroot tic -x -o /usr/share/terminfo "$ti_src"; then
      ok "terminfo xterm-ghostty installé (/usr/share/terminfo)"
    else
      warn "tic a échoué sur $ti_src — TERM=xterm-ghostty restera cassé en SSH"
    fi
  fi
}

# ============================================================== ⑧ thème =====
do_theme() {
  step "⑧" "Thème headless : $THEME"
  export OMARCHY_PATH="$OMARCHY_HOME"
  export OMARCHY_THEME_HEADLESS=1
  export PATH="$OMARCHY_HOME/bin:$PATH"

  has omarchy-theme-set || die "omarchy-theme-set introuvable — l'étape ⑥ a-t-elle tourné ?"

  # overlay : les templates utilisateur priment sur les templates intégrés
  if [[ -d "$OVERLAY_DIR/omarchy/themed" ]]; then
    run mkdir -p "$HOME/.config/omarchy/themed"
    run cp -af "$OVERLAY_DIR/omarchy/themed/." "$HOME/.config/omarchy/themed/"
    ok "overlay templates déposé (zellij.kdl.tpl…)"
  fi

  run omarchy-theme-set "$THEME" || die "thème '$THEME' inconnu (voir $OMARCHY_HOME/themes/)"
  ok "thème appliqué → ~/.local/state/omarchy/current/theme/"

  # tmux : omarchy-theme-set-tmux exige une session vivante
  if has tmux && has omarchy-theme-set-tmux; then
    if ! (( DRY_RUN )); then
      local created=0
      tmux has-session -t devbox-theme 2>/dev/null || { tmux new -d -s devbox-theme; created=1; }
      omarchy-theme-set-tmux || warn "omarchy-theme-set-tmux a échoué"
      (( created )) && tmux kill-session -t devbox-theme 2>/dev/null || true
    fi
    ok "tmux thémé"
  fi

  # zellij : un lien + une ligne de config, zéro code
  if has zellij; then
    run mkdir -p "$HOME/.config/zellij/themes"
    run ln -nsf "$HOME/.local/state/omarchy/current/theme/zellij.kdl" \
                "$HOME/.config/zellij/themes/omarchy.kdl"
    if ! grep -q '^theme "omarchy"' "$HOME/.config/zellij/config.kdl" 2>/dev/null; then
      runsh "echo 'theme \"omarchy\"' >> \"\$HOME/.config/zellij/config.kdl\""
    fi
    ok "zellij câblé"
  fi
}

# ========================================================== ⑨ tailscale =====
# Pas de SERVEUR sshd : le seul accès entrant voulu est via la tailnet, donc
# c'est Tailscale SSH (`tailscale up --ssh`) qui sert — pas de port 22 ouvert
# ailleurs, l'ACL de la tailnet fait office de pare-feu. `--operator` évite
# d'avoir à sudo pour tailscale up/set/status au quotidien. Le paquet openssh
# reste installé : il fournit aussi le CLIENT `ssh` (git clone en ssh, etc.),
# qu'on ne veut surtout pas retirer — seul le service sshd est désactivé.

# sshd (le service, pas le paquet openssh — le binaire client ssh reste utile)
# n'a plus de raison de tourner une fois Tailscale SSH actif : son port 22
# resterait ouvert hors tailnet, contradiction directe avec l'ACL. N'est
# appelée qu'une fois la tailnet confirmée jointe (voir do_tailscale) —
# jamais tant qu'on n'a pas la certitude que la tailnet a pris le relais.
cleanup_sshd() {
  has sshd || return 0
  if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-enabled --quiet sshd 2>/dev/null; then
    asroot systemctl disable --now sshd
    ok "sshd désactivé — accès distant 100% Tailscale SSH (client ssh conservé)"
  fi
}

do_tailscale() {
  step "⑨" "Tailscale"
  has tailscale || die "tailscale non installé (étape ③)."
  asroot systemctl enable --now tailscaled

  # opérateur/ssh/tag/cleanup sont idempotents : à rejouer à CHAQUE run dès
  # que la tailnet est jointe, pas seulement le run où --with-tailscale a été
  # passé — sinon un simple `mise run bootstrap` sans ce flag les saute tout
  # le temps une fois la tailnet déjà rejointe une première fois.
  #
  # Tout dans UN SEUL `tailscale up` (pas de `set` séparé) : --advertise-tags
  # n'existe que sur `up`, pas `set` ("flag provided but not defined") — et
  # `up` en reconfiguration exige de RE-mentionner tous les prefs non-défaut
  # déjà actifs ("requires mentioning all non-default flags"), donc operator
  # et --ssh doivent être sur la même ligne à chaque run, jamais posés à part.
  local up_flags=(--hostname="$TS_HOSTNAME" --accept-dns=true --advertise-tags=tag:omarchy --operator="$DEVBOX_USER" --ssh)

  if ! (( DRY_RUN )) && tailscale status >/dev/null 2>&1; then
    ok "déjà connecté à la tailnet"
    asroot tailscale up "${up_flags[@]}" \
      || warn "mise à jour tailscale up a échoué — relance à la main : tailscale up ${up_flags[*]}"
  elif (( WITH_TAILSCALE )); then
    info "authentification interactive — l'IdP est en OTP seul (code par mail)"
    asroot tailscale up "${up_flags[@]}"
    ok "tailnet rejointe en tant que $TS_HOSTNAME (tag:omarchy)"
  else
    skip "désactivé (--no-tailscale) — relance sans ce flag pour rejoindre la tailnet"
    return 0
  fi

  ok "opérateur $DEVBOX_USER + Tailscale SSH actifs (tag:omarchy)"

  cleanup_sshd
}

# ============================================================ ⑩ cli-auth =====
# gh + claude : mêmes machines à provisionner à chaque fois, donc auth
# interactive par défaut ici plutôt que manuelle poste par poste — mais
# jamais si déjà authentifié (idempotent, même logique que `tailscale up`
# plus haut : on vérifie l'état avant de redéclencher un flow interactif).
do_cli_auth() {
  step "⑩" "Auth CLI (gh, claude)"

  if ! has gh; then
    warn "gh non installé (étape ③) — auth GitHub sautée"
  elif (( DRY_RUN )); then
    info "gh auth login (dry-run, non exécuté)"
  elif gh auth status >/dev/null 2>&1; then
    ok "gh déjà authentifié"
  else
    info "gh auth login — interactif (navigateur)"
    gh auth login --hostname github.com --git-protocol https --web \
      || warn "gh auth login a échoué/été annulé — relance à la main : gh auth login"
  fi

  # claude n'est pas un paquet pacman (zéro AUR) : installeur officiel
  # curl.claude.ai/install.sh, binaire autonome dans ~/.local/bin.
  if ! has claude; then
    if (( DRY_RUN )); then
      info "claude absent — aurait installé via https://claude.ai/install.sh"
    else
      info "claude absent — installation (https://claude.ai/install.sh)"
      curl -fsSL https://claude.ai/install.sh | bash \
        || warn "installation de claude échouée — relance à la main"
      export PATH="$HOME/.local/bin:$PATH"
    fi
  fi

  if ! has claude; then
    (( DRY_RUN )) || warn "claude toujours absent après installation — auth sautée"
  elif (( DRY_RUN )); then
    info "claude auth login --claudeai --email $CLAUDE_EMAIL (dry-run, non exécuté)"
  elif claude auth status --json 2>/dev/null | grep -q '"loggedIn": *true'; then
    ok "claude déjà authentifié"
  else
    info "claude auth login — interactif ($CLAUDE_EMAIL)"
    claude auth login --claudeai --email "$CLAUDE_EMAIL" \
      || warn "claude auth login a échoué/été annulé — relance à la main : claude auth login --claudeai --email $CLAUDE_EMAIL"
  fi
}

# ============================================================= ⑪ verify =====
CHECK_FAIL=0
check() { # check "libellé" "commande"
  local label="$1" cmd="$2" out rc
  # `out=$(...)` seul plante tout le script sous `set -e` dès que $cmd
  # échoue (l'affectation hérite du code de sortie) — un `if` l'exempte
  # d'errexit, indispensable puisque check() sert justement à tolérer
  # des échecs individuels sans interrompre la vérification.
  if out="$(bash -c "$cmd" 2>&1)"; then rc=0; else rc=$?; fi
  if (( rc == 0 )); then
    printf '  %s✅%s %-42s %s%s%s\n' "$GRN" "$R" "$label" "$DIM" "${out:0:38}" "$R"
  else
    printf '  %s❌%s %-42s %s%s%s\n' "$RED" "$R" "$label" "$DIM" "${out:0:38}" "$R"
    CHECK_FAIL=1
  fi
}

do_verify() {
  step "⑪" "Vérification"
  # contrôles propres à un devbox provisionné de bout en bout : sans objet sur
  # un vrai Omarchy, dont devbox n'a volontairement pas touché skel/bashrc/thème.
  local full=1
  omarchy_guarded skel && full=0
  export OMARCHY_PATH="$OMARCHY_HOME"
  export OMARCHY_THEME_HEADLESS=1
  export PATH="$OMARCHY_HOME/bin:$PATH"

  check "utilisateur non-root"    "test \"\$(id -un)\" != root && id -un"
  check "membre de wheel"         "id -nG | tr ' ' '\n' | grep -qx wheel && echo wheel"
  # getent (pas id -nG) : usermod écrit /etc/group immédiatement, mais la
  # session courante garde ses groupes en cache jusqu'à la prochaine
  # connexion — id -nG donnerait un faux ❌ juste après le run qui l'ajoute.
  has docker && check "membre de docker" "getent group docker | grep -qw \"\$(id -un)\" && echo docker"
  check "sudo fonctionnel"        "sudo -n true 2>/dev/null && echo 'sans mdp' || { sudo -v && echo 'avec mdp'; }"
  is_wsl && check "systemd actif" "systemctl is-system-running | grep -qE 'running|degraded' && systemctl is-system-running"
  is_wsl && check "wsl.conf: user par défaut" "grep -qE '^[[:space:]]*default[[:space:]]*=' /etc/wsl.conf && grep -E '^[[:space:]]*default' /etc/wsl.conf"
  is_wsl && check "WSL ouvre en non-root (DefaultUid)" "test \"\$(id -u)\" -ne 0 && echo \"uid \$(id -u)\""
  check "dépôt [omarchy] signé"   "grep -A3 '^\[omarchy\]' /etc/pacman.conf | grep -q 'SigLevel = Required' && echo 'Required'"
  # ufw (WSL) et tout paquet que pacman -Si ne résout pas pour cet ARCH
  # (indisponible — cf. do_packages `unavailable`, ou récupéré hors pacman
  # via fetch_any_pkg comme omarchy-nvim en aarch64) ne peuvent structurellement
  # pas apparaître dans `pacman -Qq` : les compter comme manquants est un faux négatif.
  local missing_real missing_cmd
  # || true : même piège errexit que check() ci-dessus — le code de sortie
  # de la dernière itération du while (ex: dernier paquet non résolvable)
  # se propagerait sinon à cette affectation et planterait tout le script.
  missing_real="$(comm -23 <(pkg_list | sort) <(pacman -Qq | sort) | while read -r p; do
    [[ "$p" == ufw ]] && is_wsl && continue
    pacman -Si "$p" >/dev/null 2>&1 && printf '%s ' "$p"
  done)" || true
  if [[ -z "$missing_real" ]]; then
    missing_cmd="echo '0 manquant'"
  else
    missing_cmd="printf '%s\n' $(printf '%q' "$missing_real"); exit 1"
  fi
  check "paquets manquants" "$missing_cmd"
  (( full )) && check "loader rc.d dans ~/.bashrc"  "grep -q 'devbox/rc.d' \"\$HOME/.bashrc\" && ls \"$RC_D\" | tr '\n' ' '"
  check "starship actif dans bash"  "bash -ic 'echo \"\${STARSHIP_SHELL:-KO}\"' 2>/dev/null | tail -1 | grep -qv KO && echo bash"
  check "prompt starship configuré" "test -r \"\$HOME/.config/starship.toml\" && head -1 \"\$HOME/.config/starship.toml\""
  check "hostname coloré dans le prompt" "grep -A3 '^\[hostname\]' \"\$HOME/.config/starship.toml\" 2>/dev/null | grep -o 'bold #[0-9a-fA-F]*' | head -1"
  (( full )) && check "locale utilisable"       "LC_ALL=${LOCALES%% *} locale >/dev/null 2>&1 && echo '${LOCALES%% *}'"
  (( full )) && check "configs /etc/skel"       "test -d \"\$HOME/.config/nvim\" && du -sh \"\$HOME/.config/nvim\" | cut -f1"
  (( full )) && check "plugins nvim pré-cachés" "test \$(ls \"\$HOME/.local/share/nvim/lazy\" 2>/dev/null | wc -l) -ge 40 && ls \"\$HOME/.local/share/nvim/lazy\" | wc -l"
  (( full )) && check "nvim démarre proprement" "nvim --headless +qa 2>&1 && echo 'exit 0'"
  check "aucun lien cassé"        "test -z \"\$(find \"\$HOME/.config\" \"\$HOME/.local/state\" -xtype l 2>/dev/null)\" && echo '0 lien mort'"
  (( full )) && check "thème appliqué (nvim)"   "grep -ho 'colorscheme[^,}]*' \"\$HOME/.local/state/omarchy/current/theme/neovim.lua\" | head -1"
  has zellij    && check "zellij config valide" "zellij setup --check 2>&1 | grep -qi 'well defined' && echo 'Well defined'"
  has tailscale && check "tailscale" "tailscale status >/dev/null 2>&1 && tailscale status --json | grep -o '\"BackendState\": *\"[^\"]*\"' | head -1"
  # `tailscale debug prefs` n'est PAS couvert par --operator (contrairement à
  # up/set/status/ping) : sudo -n requis, échec propre (❌, texte visible) si
  # NOPASSWD n'est pas actif plutôt qu'un grep -q muet sur une sortie vide.
  has tailscale && check "tailscale ssh actif" "sudo -n tailscale debug prefs 2>&1 | grep -q '\"RunSSH\": *true' && echo actif"
  has tailscale && check "opérateur tailscale" "sudo -n tailscale debug prefs 2>&1 | grep -q \"\\\"OperatorUser\\\": *\\\"\$(id -un)\\\"\" && id -un"
  has tailscale && check "tag:omarchy" "tailscale status --self --json 2>/dev/null | grep -q 'tag:omarchy' && echo 'tag:omarchy'"
  check "sshd désactivé"  "( ! command -v sshd >/dev/null 2>&1 || ! systemctl is-active --quiet sshd 2>/dev/null ) && echo 'ok'"
  check "client ssh présent"      "command -v ssh >/dev/null 2>&1 && ssh -V 2>&1"
  check "yay présent"             "command -v yay >/dev/null 2>&1 && yay --version 2>&1 | head -1"
  # worktrunk-bin installe le binaire `wt`, pas `worktrunk` — via pacman
  # (AUR/yay) OU via install_worktrunk_fallback (~/.local/bin/wt, GitHub direct)
  check "worktrunk (wt)"          "command -v wt >/dev/null 2>&1 && wt --version 2>&1 | head -1"
  has gh     && check "gh authentifié"     "gh auth status >/dev/null 2>&1 && gh auth status 2>&1 | grep -o 'Logged in to [^ ]* as [^ ]*' | head -1"
  has claude && check "claude installé"    "claude --version 2>&1 | head -1"
  has claude && check "claude authentifié" "claude auth status --json 2>/dev/null | grep -q '\"loggedIn\": *true' && claude auth status --json 2>/dev/null | grep -o '\"email\": *\"[^\"]*\"' | head -1"

  printf '\n'
  if (( CHECK_FAIL )); then
    printf '  %s🔴 des contrôles ont échoué — voir ci-dessus.%s\n\n' "$RED$B" "$R"
    return 1
  fi
  printf '  %s🟢 devbox conforme.%s\n\n' "$GRN$B" "$R"
}

# =============================================================== main ========
main() {
  preflight
  detect_omarchy
  printf '\n%s devbox bootstrap v%s %s  %s(%s · %s · canal %s%s)%s\n' \
    "$B$BLU" "$VERSION" "$R" "$DIM" \
    "$(is_wsl && echo WSL || { (( IS_OMARCHY )) && echo Omarchy || echo 'Arch nu'; })" \
    "$( (( ROOT_MODE )) && echo "root ▸ $DEVBOX_USER" || id -un)" \
    "$OMARCHY_CHANNEL" "$( (( DRY_RUN )) && echo ' · DRY-RUN')" "$R"

  if (( IS_OMARCHY )); then
    if (( FORCE_FULL )); then
      warn "Omarchy détecté ($OMARCHY_WHY) mais --force-full : TOUTES les étapes tournent, y compris celles qui écrasent sa config"
    else
      info "Omarchy détecté ($OMARCHY_WHY) — étapes sautées : ${OMARCHY_PROTECTED[*]} (--force-full pour forcer)"
    fi
  fi

  local s
  for s in "${STEPS[@]}"; do
    wanted "$s" || continue
    if omarchy_guarded "$s"; then
      [[ "$ONLY_STEP" == "$s" ]] && die "étape '$s' refusée : Omarchy détecté ($OMARCHY_WHY), elle écraserait sa config.
  Relance avec --force-full si c'est vraiment voulu."
      if [[ "$s" == shell ]]; then do_shell_light
      else step "·" "$s"; skip "géré par Omarchy — sauté (--force-full pour écraser)"
      fi
      continue
    fi
    case "$s" in
      user)      do_user ;;
      prereq)    do_prereq ;;
      repo)      do_repo ;;
      packages)  do_packages ;;
      locale)    do_locale ;;
      hostname)  do_hostname ;;
      skel)      do_skel ;;
      vendor)    do_vendor ;;
      shell)     do_shell ;;
      theme)     do_theme ;;
      tailscale) do_tailscale ;;
      cli-auth)  do_cli_auth ;;
      verify)    do_verify ;;
    esac
    # en root, tout ce qui suit prereq écrit dans $HOME : on bascule
    if (( ROOT_MODE )) && [[ "$s" == prereq ]] && wanted repo && ! (( NO_REEXEC )); then
      reexec_as_user
    fi
  done

  if (( ROOT_MODE )); then
    printf '\n  %sÉtapes root terminées.%s Reprends en %s%s%s :  %ssu - %s -c "cd %s && ./%s --from repo"%s\n\n' \
      "$B" "$R" "$B" "$DEVBOX_USER" "$R" "$B" "$DEVBOX_USER" "$SCRIPT_DIR" "$SCRIPT_NAME" "$R"
    return 0
  fi

  if (( IS_OMARCHY )) && ! (( FORCE_FULL )); then
    printf '\n  %sSuite :%s ouvrir un nouveau shell (prompt hostname, groupe docker)\n\n' "$B" "$R"
    return 0
  fi

  printf '
  %sSuite :%s
    %s·%s ouvrir un nouveau shell (ou %sexec bash%s) pour charger OMARCHY_PATH
    %s·%s changer de thème : %sOMARCHY_THEME_HEADLESS=1 omarchy-theme-set <nom>%s

' "$B" "$R" "$DIM" "$R" "$B" "$R" "$DIM" "$R" "$B" "$R"
}

main "$@"
