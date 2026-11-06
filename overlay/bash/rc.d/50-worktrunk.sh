# devbox — worktrunk (`wt`, installé par bootstrap.sh).
# Sans cette intégration, `wt` est le binaire brut : il ne peut pas faire
# de cd dans le shell courant, donc `wt switch` ne bouge pas.
[[ $- == *i* ]] || return 0
command -v wt >/dev/null 2>&1 || return 0

eval "$(command wt config shell init bash)"

# ws : sélecteur interactif des worktrees (aperçu diff/log), puis cd.
#   ws          → choisir dans la liste
#   ws <branche> / ws - / ws ^  → aller directement
alias ws='wt switch'
