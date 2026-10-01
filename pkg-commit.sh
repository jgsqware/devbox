#!/usr/bin/env bash
# devbox — commite packages.txt (et lui seul) avec un message généré depuis
# le diff : « paquets : + ouch, − foo ». Le hook post-commit pousse et resync
# la flotte comme pour tout commit sur main.
#
#   mise run pkg-commit          commite
#   mise run pkg-commit -- -n    affiche le message sans commiter
set -euo pipefail
cd "$(dirname "$0")"

dry=0
[[ "${1:-}" == -n ]] && dry=1

# nom du paquet = 1er mot de la ligne, hors commentaires/lignes vides
names() { grep -E "^[$1][^$1#]" | sed -E "s/^[$1][[:space:]]*//; s/[[:space:]#].*//" | grep -v '^$' || true; }
diff="$(git diff HEAD -U0 -- packages.txt | grep -vE '^(\+\+\+|---)' || true)"
mapfile -t added   < <(names + <<<"$diff")
mapfile -t removed < <(names - <<<"$diff")

# un paquet déplacé (retiré puis rajouté ailleurs) n'est ni ajouté ni retiré
declare -A seen=()
for p in "${added[@]}"; do seen[$p]=1; done
moved=()
for p in "${removed[@]}"; do [[ -n "${seen[$p]:-}" ]] && moved+=("$p"); done
filter() { local p m; for p; do for m in "${moved[@]}"; do [[ "$p" == "$m" ]] && continue 2; done; echo "$p"; done; }
mapfile -t added   < <(filter "${added[@]}")
mapfile -t removed < <(filter "${removed[@]}")

parts=()
(( ${#added[@]} ))   && parts+=("$(printf '+ %s, ' "${added[@]}" | sed 's/, $//')")
(( ${#removed[@]} )) && parts+=("$(printf '− %s, ' "${removed[@]}" | sed 's/, $//')")
if (( ${#parts[@]} )); then
  msg="paquets : $(printf '%s ; ' "${parts[@]}" | sed 's/ ; $//')"
elif [[ -n "$diff" ]]; then
  msg="paquets : réorganisation de packages.txt"
else
  echo "packages.txt inchangé — rien à commiter" >&2
  exit 1
fi

if (( dry )); then
  echo "$msg"
  exit 0
fi
git commit -m "$msg" -- packages.txt
