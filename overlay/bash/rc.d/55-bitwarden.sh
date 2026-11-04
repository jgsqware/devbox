# devbox — Bitwarden CLI : un déverrouillage partagé par tous les shells.
# La clé de session (BW_SESSION) déchiffre tout le coffre. Elle est gardée
# dans $XDG_RUNTIME_DIR (tmpfs : en mémoire, effacé à la déconnexion /
# au reboot), lisible par ce seul utilisateur (600). Repli : ~/.cache.
#
#   bwu   déverrouille (mot de passe maître), partage la clé, synchronise
#   bwl   reverrouille partout et efface la clé
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
