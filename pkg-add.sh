#!/usr/bin/env bash
# devbox — ajoute un paquet à TOUTE la flotte en une commande, de n'importe
# où (tâche mise globale, posée par bootstrap dans ~/.config/mise/conf.d/) :
#
#   0. propose de corriger ce qui bloque : identité git, branche ≠ main,
#      modifs en cours sur packages.txt / bootstrap.sh (commit séparé)
#   1. git pull --rebase du dépôt devbox (on part du dernier état)
#   2. cherche dans les dépôts pacman (core/extra/[omarchy]…) ET l'AUR
#   3. installe sur ce poste — rien n'est écrit si l'install échoue
#   4. ajoute à packages.txt (section au choix) ou, pour l'AUR, à
#      AUR_PACKAGES dans bootstrap.sh (exception au « zéro AUR », confirmée)
#   5. commite, pousse, resync la flotte en arrière-plan
#
#   mise run pkg-add [requête…] [options]
#     -s, --section <nom>   section de packages.txt (sous-chaîne, ex : réseau)
#     -y, --yes             oui à tout (corrections, AUR compris)
#     -n, --dry-run         montre ce qui serait fait, ne touche à rien
#     --no-sync             commite et pousse, sans resync de la flotte
#
# Une requête qui est le nom exact d'un paquet des dépôts est prise telle
# quelle ; sinon choix fzf (multi-sélection : Tab), avec aperçu -Si.
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PKG_FILE="$ROOT/packages.txt"
BOOT="$ROOT/bootstrap.sh"

B=$'\033[1m'; R=$'\033[0m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'
ok()   { printf '  %s✅%s %s\n' "$GRN" "$R" "$*"; }
info() { printf '  %s·%s %s\n' "$DIM" "$R" "$*"; }
warn() { printf '  %s⚠️ %s %s\n' "$YEL" "$R" "$*"; }
die()  { printf '  %s❌ %s%s\n' "$RED" "$*" "$R" >&2; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }
g()    { git -C "$ROOT" "$@"; }

query=() section="" yes=0 dry=0 sync=1
while (( $# )); do
  case "$1" in
    -s|--section) section="${2:?--section attend un nom}"; shift 2 ;;
    --section=*)  section="${1#*=}"; shift ;;
    -y|--yes)     yes=1; shift ;;
    -n|--dry-run) dry=1; shift ;;
    --no-sync)    sync=0; shift ;;
    -h|--help)    sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    -*)           die "option inconnue : $1 (voir --help)" ;;
    *)            query+=("$1"); shift ;;
  esac
done

# ---------------------------------------------------------------- préalables --
has pacman || die "pacman absent — pas une devbox Arch"
has fzf    || die "fzf absent (packages.txt) — mise run bootstrap"

# Chaque blocage est proposé à la correction plutôt que refusé :
# -y répond oui à tout ; sans terminal (et sans -y) → non, donc arrêt.
confirm() {
  (( yes )) && return 0
  [[ -t 0 ]] || return 1
  if has gum; then gum confirm "$1"
  else local a; read -rp "  $1 (o/N) " a; [[ "$a" == [oOyY]* ]]; fi
}
ask() { # ask "question" "défaut" → réponse
  local a
  if (( yes )) || [[ ! -t 0 ]]; then echo "$2"; return; fi
  if has gum; then gum input --value "$2" --header "$1"
  else read -rp "  $1 [$2] : " a; echo "${a:-$2}"; fi
}

# identité git : même chose que install_git_identity (bootstrap, étape shell)
if [[ -z "$(g config user.email)" ]]; then
  inc="${XDG_CONFIG_HOME:-$HOME/.config}/devbox/git/identity"
  [[ -r "$ROOT/overlay/git/identity" ]] || die "pas d'identité git (ni overlay/git/identity) — git config --global user.email …"
  warn "pas d'identité git sur ce poste"
  if (( dry )); then info "proposerait d'inclure $inc dans ~/.gitconfig (dry-run)"
  elif confirm "Poser l'identité devbox (overlay/git/identity → ~/.gitconfig) ?"; then
    mkdir -p "$(dirname "$inc")"
    cp -af "$ROOT/overlay/git/." "$(dirname "$inc")/"
    git config --file "$HOME/.gitconfig" --get-all include.path 2>/dev/null | grep -qxF "$inc" \
      || git config --file "$HOME/.gitconfig" --add include.path "$inc"
    ok "identité git : $(g config user.name) <$(g config user.email)>"
  else die "annulé — sans identité git, impossible de commiter"; fi
fi

# branche : la flotte suit main → on y bascule, et on revient à la fin
branch="$(g symbolic-ref --short HEAD 2>/dev/null || true)"
if [[ "$branch" != main ]]; then
  prev="${branch:-$(g rev-parse --short HEAD)}"
  warn "$ROOT est sur ${branch:-une HEAD détachée ($prev)}, pas sur main"
  if (( dry )); then info "proposerait git switch main (dry-run)"
  elif confirm "Basculer sur main le temps de l'ajout (retour sur $prev à la fin) ?"; then
    g switch -q main || die "git switch main impossible (modifs en conflit ?) — à régler à la main"
    trap 'g checkout -q "$prev" && info "retour sur $prev"' EXIT
    ok "sur main"
  else die "annulé — pkg-add ne commite que sur main (c'est elle que la flotte suit)"; fi
fi

# message proposé pour bootstrap.sh, tiré du diff : fonctions ajoutées (+)
# et fonctions touchées (en-têtes de hunk) — sinon message générique
boot_msg() {
  local d new touched
  d="$(g diff HEAD -U0 -- bootstrap.sh)"
  new="$(sed -nE 's/^\+([a-z_][a-z0-9_]*)\(\) \{.*/\1/p' <<<"$d" | sort -u)"
  touched="$(sed -nE 's/^@@ .* @@ ([a-z_][a-z0-9_]*)\(\) \{.*/\1/p' <<<"$d" | sort -u | grep -vxF -f <(printf '%s\n' "$new") || true)"
  new="$(paste -sd, <<<"$new" | sed 's/,/, /g')"
  touched="$(paste -sd, <<<"$touched" | sed 's/,/, /g')"
  if [[ -n "$new" && -n "$touched" ]]; then echo "bootstrap : + $new ; maj $touched"
  elif [[ -n "$new" ]]; then echo "bootstrap : + $new"
  elif [[ -n "$touched" ]]; then echo "bootstrap : maj $touched"
  else echo "bootstrap : modifs en cours"; fi
}

# modifs en cours sur nos deux fichiers : commitées d'abord, À PART, pour
# que le commit pkg-add ne contienne que le paquet ajouté
dirty=() msgs=()
for f in packages.txt bootstrap.sh; do
  g diff --quiet HEAD -- "$f" && continue
  dirty+=("$f")
  if [[ "$f" == packages.txt ]]; then msgs+=("$("$ROOT/pkg-commit.sh" -n)")
  else msgs+=("$(boot_msg)"); fi
done
if (( ${#dirty[@]} )); then
  warn "modifs non commitées : ${dirty[*]}"
  g --no-pager diff --stat HEAD -- "${dirty[@]}" | sed 's/^/    /'
  info "commit(s) proposé(s), sur main :"
  for i in "${!dirty[@]}"; do printf '      %s%s%s  ← %s\n' "$B" "${msgs[$i]}" "$R" "${dirty[$i]}"; done
  if (( dry )); then
    info "proposerait de les commiter avant l'ajout (dry-run)"
  else
    choice=non
    if (( yes )); then choice=oui
    elif [[ -t 0 ]]; then
      if has gum; then
        choice="$(gum choose --header "Commiter avec ce(s) message(s) ?" "oui" "modifier le message" "non" || echo non)"
      else
        read -rp "  commiter avec ce(s) message(s) ? (o = oui, m = modifier, N = non) " a
        case "$a" in [oOyY]*) choice=oui ;; [mM]*) choice="modifier le message" ;; esac
      fi
    fi
    [[ "$choice" == non ]] && die "annulé — commite-les ou annule-les d'abord (mise run pkg-commit pour packages.txt)"
    for i in "${!dirty[@]}"; do
      msg="${msgs[$i]}"
      [[ "$choice" == "modifier le message" ]] && msg="$(ask "message du commit pour ${dirty[$i]}" "$msg")"
      [[ -n "$msg" ]] || die "message vide — annulé"
      DEVBOX_NO_SYNC=1 g commit -q -m "$msg" -- "${dirty[$i]}"
      ok "commit : $(g log -1 --format=%s)"
    done
  fi
fi

# --rebase : garde les commits locaux pas encore poussés ; --autostash : les
# modifs en cours sur d'AUTRES fichiers du dépôt ne bloquent pas le pull
if (( dry )); then info "git pull --rebase (dry-run, non exécuté)"
else g pull -q --rebase --autostash origin main \
  || die "git pull --rebase a échoué — résous la divergence de $ROOT d'abord"
fi

# ------------------------------------------------------------------ recherche --
# comparaisons en chaîne fixe : un nom comme « gtk+ » n'est pas une regex
in_list() { sed -E 's/#.*//; s/^[[:space:]]+//; s/[[:space:]].*//' "$PKG_FILE" | grep -qxF -- "$1"; }
in_aur()  { sed -nE 's/^AUR_PACKAGES=\((.*)\).*/\1/p' "$BOOT" | tr ' ' '\n' | grep -qxF -- "$1"; }

# « nom \t dépôt \t version \t état \t description » depuis la sortie -Ss
fmt() {
  awk 'NR%2 { split($1, a, "/"); repo = a[1]; name = a[2]; ver = $2; next }
       { sub(/^ +/, ""); printf "%s\t%s\t%s\t%s\n", name, repo, ver, $0 }'
}
mark() {
  local name repo ver desc st
  while IFS=$'\t' read -r name repo ver desc; do
    st=""
    if [[ "$repo" == aur ]]; then in_aur "$name" && st="devbox"
    else in_list "$name" && st="devbox"; fi
    [[ -z "$st" ]] && pacman -Qq "$name" >/dev/null 2>&1 && st="installé"
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$repo" "$ver" "${st:--}" "$desc"
  done
}

if (( ! ${#query[@]} )); then
  if has gum; then query=("$(gum input --placeholder 'paquet à chercher')")
  else read -rp "paquet à chercher : " q; query=("$q"); fi
  [[ -n "${query[0]}" ]] || die "requête vide"
fi

picked=()   # « nom \t dépôt »
if (( ${#query[@]} == 1 )) && pacman -Si -- "${query[0]}" >/dev/null 2>&1; then
  repo="$(pacman -Si -- "${query[0]}" | awk -F': ' '/^Repository/{print $2; exit}')"
  picked=("${query[0]}"$'\t'"$repo")
else
  results="$( { pacman -Ss -- "${query[@]}" 2>/dev/null | fmt
                has yay && yay -Ss --aur -- "${query[@]}" 2>/dev/null | fmt; } | mark || true)"
  [[ -n "$results" ]] || die "aucun paquet trouvé pour « ${query[*]} » (dépôts pacman + AUR)"
  exact="$(awk -F'\t' -v q="${query[0]}" '$1 == q { print $1 "\t" $2; exit }' <<<"$results")"
  if (( ${#query[@]} == 1 )) && [[ -n "$exact" ]] && { (( yes )) || [[ ! -t 0 ]]; }; then
    picked=("$exact")   # nom exact (ex : AUR) : pas de choix à faire
  elif [[ ! -t 0 ]]; then
    die "pas de terminal pour choisir — donne un nom exact. Résultats :
$(cut -f1,2 <<<"$results" | head -20)"
  else
  mapfile -t picked < <(column -t -s $'\t' -o $'\t' <<<"$results" | fzf --multi --delimiter=$'\t' \
      --header='Tab : multi-sélection · état : devbox = déjà dans la liste' \
      --preview='n={1}; r={2}; n=${n// /}; r=${r// /}; if [ "$r" = aur ]; then yay -Si --aur "$n"; else pacman -Si "$n"; fi' \
      | awk -F'\t' '{ gsub(/ +$/, "", $1); gsub(/ +$/, "", $2); print $1 "\t" $2 }')
  fi
  (( ${#picked[@]} )) || die "rien sélectionné"
fi

# ------------------------------------------------------------------ tri -------
repo_new=() aur_new=() to_install=() aur_install=()
for p in "${picked[@]}"; do
  name="${p%%$'\t'*}" repo="${p#*$'\t'}"
  if [[ "$repo" == aur ]]; then
    in_aur "$name" && info "$name déjà dans AUR_PACKAGES" || aur_new+=("$name")
    pacman -Qq "$name" >/dev/null 2>&1 || aur_install+=("$name")
  else
    in_list "$name" && info "$name déjà dans packages.txt" || repo_new+=("$name")
    pacman -Qq "$name" >/dev/null 2>&1 || to_install+=("$name")
  fi
done

if (( ${#aur_new[@]} )); then
  warn "AUR : ${aur_new[*]} → AUR_PACKAGES (bootstrap.sh), exception au « zéro AUR » de packages.txt"
  if (( ! yes && ! dry )); then
    if has gum; then gum confirm "Ajouter ${aur_new[*]} depuis l'AUR ?" || die "annulé"
    else read -rp "  confirmer (o/N) ? " a; [[ "$a" == [oOyY]* ]] || die "annulé"; fi
  fi
fi

if (( ${#repo_new[@]} )); then
  mapfile -t sections < <(sed -nE 's/^# --- (.+[^ -]) -+$/\1/p' "$PKG_FILE")
  if [[ -n "$section" ]]; then
    section="$(printf '%s\n' "${sections[@]}" | grep -iF -- "$section" | head -1)" \
      || die "section introuvable — dispo : ${sections[*]}"
  elif (( yes )) || { (( dry )) && [[ ! -t 0 ]]; }; then
    section="${sections[-1]}"   # défaut : dernière section
  else
    section="$(printf '%s\n' "${sections[@]}" | fzf --header="section de packages.txt pour : ${repo_new[*]}" --height=15)" \
      || die "aucune section choisie"
  fi
fi

# ---------------------------------------------------------------- plan --------
printf '\n%s📦 pkg-add%s\n' "$B" "$R"
(( ${#to_install[@]} ))  && info "pacman -S : ${to_install[*]}"
(( ${#aur_install[@]} )) && info "yay -S (AUR) : ${aur_install[*]}"
(( ${#repo_new[@]} ))    && info "packages.txt [$section] : + ${repo_new[*]}"
(( ${#aur_new[@]} ))     && info "AUR_PACKAGES : + ${aur_new[*]}"
if (( ${#to_install[@]} + ${#aur_install[@]} + ${#repo_new[@]} + ${#aur_new[@]} == 0 )); then
  ok "rien à faire : déjà installé et déjà dans devbox"; exit 0
fi
(( dry )) && { info "dry-run : rien n'a été modifié"; exit 0; }

# ------------------------------------------------- 1. installation locale ----
# d'abord : un paquet qui ne s'installe pas ici n'entre pas dans la liste
(( ${#to_install[@]} ))  && { sudo pacman -S --needed --noconfirm "${to_install[@]}" || die "pacman a échoué — rien n'a été ajouté"; }
(( ${#aur_install[@]} )) && { has yay || die "yay absent — mise run bootstrap"
                              yay -S --needed --noconfirm "${aur_install[@]}" || die "yay a échoué — rien n'a été ajouté"; }
(( ${#to_install[@]} + ${#aur_install[@]} )) && ok "installé sur $(hostname)"

# ------------------------------------------------- 2. listes + commits -------
if (( ${#repo_new[@]} )); then
  NEW="$(printf '%s\n' "${repo_new[@]}")" SEC="$section" awk '
    { L[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) if (index(L[i], "# --- " ENVIRON["SEC"] " ") == 1) s = i
      e = NR; for (i = s + 1; i <= NR; i++) if (L[i] ~ /^# --- /) { e = i - 1; break }
      last = s; for (i = s + 1; i <= e; i++) if (L[i] !~ /^[[:space:]]*$/) last = i
      for (i = 1; i <= NR; i++) { print L[i]; if (i == last) print ENVIRON["NEW"] }
    }' "$PKG_FILE" > "$PKG_FILE.tmp" && mv "$PKG_FILE.tmp" "$PKG_FILE"
  DEVBOX_NO_SYNC=1 "$ROOT/pkg-commit.sh" >/dev/null
  ok "commit : $(g log -1 --format=%s)"
fi
if (( ${#aur_new[@]} )); then
  for a in "${aur_new[@]}"; do sed -i -E "s/^(AUR_PACKAGES=\(.*)\)/\1 $a)/" "$BOOT"; done
  for a in "${aur_new[@]}"; do in_aur "$a" || die "ajout de $a à AUR_PACKAGES échoué — vérifie $BOOT"; done
  DEVBOX_NO_SYNC=1 g commit -q -m "paquets : + $(printf '%s, ' "${aur_new[@]}" | sed 's/, $//') (AUR)" -- bootstrap.sh
  ok "commit : $(g log -1 --format=%s)"
fi

# ------------------------------------------------- 3. push + flotte ----------
if ! g push -q origin main; then
  # quelqu'un a poussé entre-temps : on rejoue nos commits par-dessus, une fois
  g pull -q --rebase --autostash origin main && g push -q origin main \
    || die "push échoué — commits gardés en local ; pousse à la main (git -C $ROOT push), la flotte n'est PAS resynchronisée"
fi
ok "poussé"
if (( sync )); then
  nohup "$ROOT/sync-fleet.sh" >/dev/null 2>&1 </dev/null & disown
  ok "flotte en resync en arrière-plan (logs : ~/.local/state/devbox/sync/latest/)"
else
  info "--no-sync : la flotte suivra au prochain mise run bootstrap / sync"
fi
