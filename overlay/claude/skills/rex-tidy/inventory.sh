#!/usr/bin/env bash
# Inventaire LECTURE SEULE des sessions Rex de tous les hôtes connus.
# Sortie TSV : host  session_id  label  blocks  busy  detail
#   blocks = nombre de blocs vivants (les blocs fantômes « not found » ne comptent pas)
#   busy   = 1 si au moins un bloc a autre chose qu'un shell au premier plan
#   detail = « programme@cwd [titre] » des blocs actifs, séparés par « ; »
# Usage : inventory.sh [host...]   (défaut : local + hôtes de l'app Rex)
set -uo pipefail

SHELLS='^(-?bash|-?zsh|-?fish|-?sh|login)$'
ENDPOINTS="$HOME/Library/Application Support/rex/overlay/hosts/everywhere.json"

hosts=("$@")
if [ ${#hosts[@]} -eq 0 ]; then
  hosts=(local)
  if [ -f "$ENDPOINTS" ]; then
    while read -r h; do hosts+=("$h"); done < <(jq -r '.entries[].label' "$ENDPOINTS")
  fi
fi

for H in "${hosts[@]}"; do
  if [ "$H" = local ]; then R=(rex); else R=(rex --timeout 6s -S "$H"); fi
  L=$("${R[@]}" ls --json 2>/dev/null) || { printf '%s\t-\t-\t-\t-\tINJOIGNABLE\n' "$H"; continue; }
  echo "$L" | jq -r '.sessions[] | "\(.session_id)\t\(.label)"' | while IFS=$'\t' read -r S LBL; do
    n=0; busy=0; detail=""
    for B in $("${R[@]}" block ls -s "$S" --json 2>/dev/null | jq -r '.blocks[].block_id'); do
      P=$("${R[@]}" block call -b "$B" process 2>/dev/null) || continue   # bloc fantôme
      n=$((n + 1))
      fg=$(jq -r '.foreground.name // ""' <<<"$P")
      [[ "$fg" =~ $SHELLS ]] && continue
      busy=1
      argv=$(jq -r '.foreground.argv0 // .foreground.name // "?"' <<<"$P")
      cwd=$(jq -r '.foreground.cwd // ""' <<<"$P" | sed -E "s|^(/Users/[^/]+\|/home/[^/]+)|~|")
      title=$("${R[@]}" block call -b "$B" title 2>/dev/null | jq -r '.title // ""')
      detail+="${argv}@${cwd} [${title}]; "
    done
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$H" "$S" "$LBL" "$n" "$busy" "${detail%; }"
  done
done
