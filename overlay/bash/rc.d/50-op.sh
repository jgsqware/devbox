# 1Password : compte de service en LECTURE SEULE sur le coffre `infra`
# (cf. ~/.claude/CLAUDE.md § Secrets). Le jeton est dans un fichier 0600, hors
# de tout repo ; sans lui, `op` reste sans compte et rien ne casse.
if [[ -r "$HOME/.config/op/service-account-token" ]]; then
  OP_SERVICE_ACCOUNT_TOKEN="$(< "$HOME/.config/op/service-account-token")"
  export OP_SERVICE_ACCOUNT_TOKEN
fi
