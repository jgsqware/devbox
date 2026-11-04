# devbox — Bitwarden CLI : un déverrouillage partagé par tous les shells.
# La clé de session (BW_SESSION) déchiffre tout le coffre. Elle est gardée
# dans $XDG_RUNTIME_DIR (tmpfs : en mémoire, effacé à la déconnexion /
# au reboot), lisible par ce seul utilisateur (600). Repli : ~/.cache.
#
#   bwu   déverrouille (mot de passe maître), partage la clé, synchronise
#   bwl   reverrouille partout et efface la clé
#   bws   recherche fzf dans le coffre, copie mot de passe / user / TOTP
[[ $- == *i* ]] || return 0
command -v bw >/dev/null 2>&1 || return 0

_BW_SESSION_FILE="${XDG_RUNTIME_DIR:-$HOME/.cache}/bw-session"

# nouveau shell : reprend la clé d'un bwu fait ailleurs
[[ -z "${BW_SESSION:-}" && -r "$_BW_SESSION_FILE" ]] && export BW_SESSION="$(<"$_BW_SESSION_FILE")"

bwu() {
  local s
  s="$(bw unlock --raw)" && [[ -n "$s" ]] || { echo "❌ déverrouillage échoué" >&2; return 1; }
  mkdir -p "$(dirname "$_BW_SESSION_FILE")"
  (umask 077; printf '%s' "$s" > "$_BW_SESSION_FILE")
  export BW_SESSION="$s"
  bw sync >/dev/null && echo "🔓 coffre déverrouillé (tous les shells) et synchronisé"
}

bwl() {
  bw lock >/dev/null
  rm -f "$_BW_SESSION_FILE"
  unset BW_SESSION
  echo "🔒 coffre verrouillé (les autres shells redemanderont le mot de passe)"
}

# à chaque appel : la clé du fichier fait foi (shell ouvert avant le bwu,
# ou clé périmée après un bwl/bwu fait dans un autre shell)
bw() {
  [[ -r "$_BW_SESSION_FILE" ]] && export BW_SESSION="$(<"$_BW_SESSION_FILE")"
  command bw "$@"
}

# copie dans le presse-papier, puis le vide au bout de 30 s.
#   pbcopy d'abord (OrbStack : presse-papier du Mac en direct, marche même
#   quand le terminal est fermé — pane flottant Rex) ; sinon clip de
#   50-tmux.sh (OSC 52 via le terminal, marche en SSH).
_bw_clip() {
  local v="$1"
  if command -v pbcopy >/dev/null; then
    printf '%s' "$v" | pbcopy
    setsid -f sh -c 'sleep 30; printf "" | pbcopy' >/dev/null 2>&1 </dev/null
  elif declare -F clip >/dev/null; then
    printf '%s' "$v" | clip
    # double fork : pas de « [1] 12345 » affiché par le shell interactif
    ( ( sleep 30; printf ' ' | clip ) >/dev/null 2>&1 & )
  else
    echo "❌ pas de presse-papier (pbcopy / clip)" >&2; return 1
  fi
}

# écran de chargement : spinner + temps écoulé sur le terminal (rien si
# stderr n'est pas un terminal). Aucun secret ne passe par lui.
# Écrit sur /dev/tty : le 2>/dev/null qui masque « [1] 12345 » vaut aussi
# pour le sous-shell.
_bw_spin_start() {
  [[ -t 2 ]] || return 0
  local msg="$1"
  { (
      trap 'exit 0' TERM
      f=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏) i=0 t0=$SECONDS
      printf '\e[?25l' >/dev/tty
      while :; do
        printf '\r\e[K  \e[36m%s\e[0m 🔐 %s \e[2m%ds\e[0m' "${f[i++ % 10]}" "$msg" $((SECONDS - t0)) >/dev/tty
        sleep 0.08
      done
    ) & } 2>/dev/null
  _BW_SPIN_PID=$!
  disown "$_BW_SPIN_PID" 2>/dev/null
  trap '_bw_spin_stop; trap - INT; return 130' INT
}
_bw_spin_stop() {
  [[ -n "${_BW_SPIN_PID:-}" ]] || return 0
  kill "$_BW_SPIN_PID" 2>/dev/null
  while kill -0 "$_BW_SPIN_PID" 2>/dev/null; do sleep 0.02; done
  unset _BW_SPIN_PID
  printf '\r\e[K\e[?25h' >&2
  trap - INT
}

# bws [recherche] — liste fzf : nom · utilisateur · dossier · URL, aperçu à droite
#   Entrée   copie le mot de passe     ctrl-u   copie l'utilisateur
#   ctrl-t   copie le code TOTP (2FA)  ctrl-o   copie l'URL
# L'aperçu ne montre aucun secret : il lit une copie du coffre SANS mots de
# passe / TOTP / notes / champs (tmpfs, 600, effacée en sortie).
bws() {
  command -v fzf >/dev/null && command -v jq >/dev/null || { echo "❌ fzf et jq requis" >&2; return 1; }
  [[ -n "${BW_SESSION:-}" || -r "$_BW_SESSION_FILE" ]] || bwu || return 1

  local items folders view
  # --nointeraction : une clé périmée fait échouer bw au lieu d'afficher
  # « Master password: » sous le spinner → on déverrouille puis on relance
  _bw_spin_start "Chargement du coffre${1:+ « $* »}…"
  items="$(bw list items --nointeraction ${1:+--search "$*"} 2>/dev/null)"
  local rc=$?
  _bw_spin_stop
  if (( rc )); then
    bwu || return 1
    _bw_spin_start "Chargement du coffre${1:+ « $* »}…"
    items="$(bw list items --nointeraction ${1:+--search "$*"} 2>/dev/null)"; rc=$?
    _bw_spin_stop
    (( rc )) && { echo "❌ bw list a échoué" >&2; return 1; }
  fi
  _bw_spin_start "Dossiers…"
  folders="$(bw list folders --nointeraction 2>/dev/null || echo '[]')"
  _bw_spin_stop
  view="$(umask 077; mktemp "${XDG_RUNTIME_DIR:-$HOME/.cache}/bws.XXXXXX")" || return 1

  # copie sans secrets, dossiers résolus en noms
  jq --argjson f "$folders" '
    ($f | map({(.id // "none"): .name}) | add // {}) as $fn
    | map({
        id, name,
        user:   (.login.username // "-"),
        uris:   [.login.uris[]?.uri],
        folder: ($fn[.folderId // "none"] // "-"),
        org:    (if .organizationId then "partagé (organisation)" else "personnel" end),
        type:   ({"1":"login","2":"note","3":"carte","4":"identité","5":"clé SSH"}[.type|tostring] // "?"),
        totp:   (.login.totp != null),
        notes:  (.notes != null and .notes != ""),
        fields: ((.fields // []) | map(.name)),
        updated: (.revisionDate // "" | .[0:10])
      })' <<<"$items" > "$view"

  if [[ "$(jq length "$view")" == 0 ]]; then
    rm -f "$view"; echo "aucun élément pour « $* »"; return 1
  fi

  local out key id
  out="$(jq -r '.[] | [.id, .name, .user, .folder, (.uris[0] // "-")] | @tsv' "$view" \
    | column -t -s $'\t' -o $'\t' \
    | fzf --delimiter=$'\t' --with-nth=2.. \
          --expect=enter,ctrl-u,ctrl-t,ctrl-o \
          --prompt='🔐 ' --height=80% --layout=reverse --border=rounded \
          --border-label=' Bitwarden ' --info=inline \
          --header='Entrée mot de passe · ctrl-u utilisateur · ctrl-t TOTP · ctrl-o URL · Échap quitter' \
          --header-first \
          --preview-window='right,45%,wrap,border-left' \
          --preview="jq -r --arg id {1} '.[] | select(.id == (\$id|gsub(\" \";\"\"))) |
              \"\u001b[1m\(.name)\u001b[0m\n\",
              \"utilisateur  \(.user)\",
              \"mot de passe ••••••••\",
              \"2FA (TOTP)   \(if .totp then \"oui → ctrl-t\" else \"non\" end)\",
              \"type         \(.type)\",
              \"dossier      \(.folder)\",
              \"coffre       \(.org)\",
              \"modifié le   \(.updated)\",
              \"\nURL\", (if (.uris|length) > 0 then .uris[] | \"  \(.)\" else \"  -\" end),
              (if (.fields|length) > 0 then \"\nchamps\", (.fields[] | \"  \(.)\") else empty end),
              (if .notes then \"\n📝 a des notes (bw get notes \(.id))\" else empty end)' $view")"
  rm -f "$view"

  key="$(head -1 <<<"$out")"
  id="$(sed -n 2p <<<"$out" | cut -f1 | tr -d ' ')"
  [[ -n "$id" ]] || return 0
  local name; name="$(sed -n 2p <<<"$out" | cut -f2 | sed 's/ *$//')"

  local what val
  case "$key" in
    ctrl-u) what="utilisateur";  val="$(bw get username "$id")" ;;
    ctrl-t) what="code TOTP";    val="$(bw get totp "$id")" ;;
    ctrl-o) what="URL";          val="$(bw get uri "$id")" ;;
    *)      what="mot de passe"; val="$(bw get password "$id")" ;;
  esac
  [[ -n "$val" ]] || { echo "❌ pas de $what pour « $name »" >&2; return 1; }
  _bw_clip "$val" && echo "📋 $what de « $name » copié (effacé dans 30 s)"
}
