# devbox — Bitwarden CLI : déverrouillage à la demande, par shell.
# La clé de session (BW_SESSION) déchiffre tout le coffre : elle reste en
# mémoire dans ce shell, jamais écrite dans un fichier.
#
#   bwu   déverrouille (mot de passe maître) puis synchronise
#   bwl   reverrouille et oublie la clé
[[ $- == *i* ]] || return 0
command -v bw >/dev/null 2>&1 || return 0

bwu() {
  local s
  s="$(bw unlock --raw)" || { echo "❌ déverrouillage échoué" >&2; return 1; }
  export BW_SESSION="$s"
  bw sync >/dev/null && echo "🔓 coffre déverrouillé et synchronisé"
}

bwl() { bw lock >/dev/null; unset BW_SESSION; echo "🔒 coffre verrouillé"; }
