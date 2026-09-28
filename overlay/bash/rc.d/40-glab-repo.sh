# devbox — aller à un dépôt GitLab : recherche floue, clone si absent, cd.
#
#   repo [requête]      sélecteur fzf (la requête pré-remplit la recherche)
#   repo --all [req.]   ignore le périmètre GLAB_REPO_GROUPS
#   repo --refresh      recharge la liste des projets depuis GitLab
#
# Les dépôts vivent sous ~/<hostname>/<chemin/complet> :
# sur gaming1 → ~/gaming1/landbased-gaming/devops/dockers.
# La liste des projets est mise en cache (~/.cache/devbox/) : elle est
# chargée une première fois, puis rafraîchie en arrière-plan au-delà de 24 h.
# Dans le sélecteur : ctrl-r recharge depuis GitLab. ● = déjà cloné.
#
# Périmètre : avec GLAB_REPO_GROUPS (ex. "landbased-gaming", plusieurs
# séparés par des virgules), seuls ces groupes sont proposés. ctrl-a élargit
# à tous les projets ; entrée sans résultat propose d'élargir. À régler par
# machine dans ~/.config/devbox/rc.d/05-local-glab-repo.sh (non versionné).
#
# Surcharges : GLAB_REPO_HOST=gitlab.exemple.com   (défaut : host glab)
#              GLAB_REPO_ROOT=/chemin               (défaut : ~/$(hostname -s))
#              GLAB_REPO_TTL=86400                  (âge max du cache, s)
#              GLAB_REPO_GROUPS=groupe[,groupe…]    (défaut : aucun, tout)

_glab_repo_host() {
  printf '%s\n' "${GLAB_REPO_HOST:-$(glab config get host 2>/dev/null)}"
}

# ~/<hostname de la machine> : ~/gaming1 sur gaming1
_glab_repo_root() {
  printf '%s\n' "${GLAB_REPO_ROOT:-$HOME/$(hostname -s 2>/dev/null || hostname)}"
}

_glab_repo_cache() {
  printf '%s/devbox/glab-repos-%s.tsv\n' \
    "${XDG_CACHE_HOME:-$HOME/.cache}" "$(_glab_repo_host)"
}

# Télécharge tous les projets (pages en parallèle), triés par activité
# récente : chemin<TAB>description. Écriture atomique du cache.
_glab_repo_fetch() {
  local host cache tmp dir pages rc=1
  host="$(_glab_repo_host)"
  cache="$(_glab_repo_cache)"
  mkdir -p "${cache%/*}"
  tmp="$(mktemp "$cache.XXXXXX")" || return 1
  dir="$(mktemp -d)" || { rm -f "$tmp"; return 1; }

  local q='projects?simple=true&archived=false&per_page=100&order_by=last_activity_at&sort=desc'
  pages="$(GITLAB_HOST="$host" glab api -i "$q&page=1" 2>/dev/null \
    | tr -d '\r' | awk -F': ' 'tolower($1)=="x-total-pages"{print $2; exit}')"
  [[ "$pages" =~ ^[0-9]+$ ]] || pages=1

  # une page par fichier : les sorties parallèles ne s'entremêlent pas
  if seq 1 "$pages" \
      | GITLAB_HOST="$host" Q="$q" D="$dir" xargs -P 8 -I{} \
          sh -c 'glab api "$Q&page=$1" >"$D/$1.json"' _ {} \
    && jq -rs 'add
        | sort_by(.last_activity_at) | reverse
        | .[] | [.path_with_namespace, ((.description // "") | gsub("[\t\r\n]+"; " "))]
        | @tsv' "$dir"/*.json >"$tmp" \
    && [[ -s "$tmp" ]]; then
    mv -f "$tmp" "$cache" && rc=0
  fi
  rm -rf "$tmp" "$dir"
  return "$rc"
}

# Lignes du sélecteur : marqueur cloné, chemin, description.
# $1 : groupes auxquels se limiter (séparés par virgule ou espace), vide = tout.
_glab_repo_list() {
  local root cache
  root="$(_glab_repo_root)"
  cache="$(_glab_repo_cache)"
  [[ -r "$cache" ]] || return 0
  local -a groups=()
  IFS=', ' read -ra groups <<<"${1:-}"
  local path desc mark g keep
  while IFS=$'\t' read -r path desc; do
    if (( ${#groups[@]} )); then
      keep=0
      for g in "${groups[@]}"; do
        g="${g%/}"
        [[ "$path" == "$g" || "$path" == "$g"/* ]] && { keep=1; break; }
      done
      (( keep )) || continue
    fi
    if [[ -d "$root/$path/.git" ]]; then mark=$'\e[32m●\e[0m'; else mark=' '; fi
    printf '%s\t%s\t\e[2m%s\e[0m\n' "$mark" "$path" "$desc"
  done <"$cache"
}

repo() {
  local cmd
  for cmd in glab gum fzf jq; do
    command -v "$cmd" >/dev/null 2>&1 || { printf 'repo: %s introuvable\n' "$cmd" >&2; return 1; }
  done

  local cache root
  cache="$(_glab_repo_cache)"
  root="$(_glab_repo_root)"

  if [[ "${1:-}" == --refresh ]] || [[ ! -s "$cache" ]]; then
    gum spin --title "Chargement des projets GitLab ($(_glab_repo_host))…" -- \
      bash -c "$(declare -f _glab_repo_host _glab_repo_cache _glab_repo_fetch); _glab_repo_fetch" \
      || { gum log --level error "échec du chargement des projets (glab auth status ?)"; return 1; }
    [[ "${1:-}" == --refresh ]] && { gum log --level info "$(wc -l <"$cache") projets en cache"; return 0; }
  else
    # cache périmé : on sert l'ancien et on rafraîchit en arrière-plan
    local age=$(( $(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || stat -f %m "$cache") ))
    if (( age > ${GLAB_REPO_TTL:-86400} )); then
      ( bash -c "$(declare -f _glab_repo_host _glab_repo_cache _glab_repo_fetch); _glab_repo_fetch" \
          >/dev/null 2>&1 & )
    fi
  fi

  # périmètre par défaut (GLAB_REPO_GROUPS), --all pour tout voir
  local groups="${GLAB_REPO_GROUPS:-}"
  [[ "${1:-}" == --all ]] && { groups=""; shift; }
  local query="$*"

  # fzf lance reload via $SHELL : on lui passe les fonctions explicitement
  local fns
  fns="$(declare -f _glab_repo_host _glab_repo_root _glab_repo_cache _glab_repo_fetch _glab_repo_list)"

  local out rc sel prompt header reload widen
  while :; do
    reload="bash -c $(printf '%q' "$fns; _glab_repo_fetch; _glab_repo_list $(printf '%q' "$groups")")"
    widen="bash -c $(printf '%q' "$fns; _glab_repo_list")"
    header='entrée : aller / cloner · ctrl-r : recharger depuis GitLab'
    if [[ -n "$groups" ]]; then
      prompt="$(_glab_repo_host) [$groups] › "
      header+=' · ctrl-a : tous les projets'
    else
      prompt="$(_glab_repo_host) › "
    fi

    # tri : meilleur score fzf d'abord, à égalité l'activité GitLab la plus récente
    out="$(_glab_repo_list "$groups" | fzf \
        --ansi --delimiter=$'\t' --nth=2 --with-nth=1,2,3 \
        --tiebreak=index --print-query \
        --query="$query" --prompt="$prompt" --header="$header" \
        --bind="ctrl-r:reload($reload)" \
        --bind="ctrl-a:reload($widen)+change-prompt($(_glab_repo_host) › )")"
    rc=$?
    query="$(sed -n 1p <<<"$out")"
    sel="$(sed -n 2p <<<"$out")"

    # entrée sans résultat dans le périmètre restreint : proposer d'élargir
    if (( rc == 1 )) && [[ -n "$groups" ]] \
      && gum confirm "Rien dans « $groups » pour « $query ». Chercher dans tous les projets ?"; then
      groups=""
      continue
    fi
    (( rc == 0 )) || return 0
    break
  done

  local path dest
  path="$(cut -f2 <<<"$sel")"
  [[ -n "$path" ]] || return 0
  dest="$root/$path"

  if [[ ! -d "$dest/.git" ]]; then
    mkdir -p "${dest%/*}" || return 1
    gum spin --show-error --title "Clonage de $path…" -- \
      env GITLAB_HOST="$(_glab_repo_host)" glab repo clone "$path" "$dest" \
      || { gum log --level error "échec du clonage de $path"; return 1; }
    gum log --level info "cloné → $dest"
  fi

  cd "$dest" || return 1
}
