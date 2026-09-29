# devbox — alias git façon oh-my-zsh (plugin `git`), mêmes noms et même sens.
# Omarchy définit déjà g, gcm (commit -m ≠ omz : checkout main), gcam, gcad :
# on ne les touche pas.
[[ $- == *i* ]] || return 0

alias ga='git add'
alias gaa='git add --all'
alias gapa='git add --patch'

alias gb='git branch'
alias gba='git branch --all'
alias gbd='git branch --delete'
alias gbD='git branch --delete --force'

alias gc='git commit --verbose'
alias gca='git commit --verbose --all'
alias gcs='git commit --gpg-sign'
alias gcsm='git commit --signoff --message'
alias gcss='git commit --gpg-sign --signoff'
alias gcssm='git commit --gpg-sign --signoff --message'
alias gcl='git clone --recurse-submodules'
alias gcp='git cherry-pick'

alias gco='git checkout'
alias gcb='git checkout -b'
alias gsw='git switch'
alias gswc='git switch --create'

alias gd='git diff'
alias gds='git diff --staged'

alias gf='git fetch'
alias gfa='git fetch --all --tags --prune'
alias gl='git pull'
alias gpr='git pull --rebase'
alias gp='git push'
alias gpf='git push --force-with-lease'
alias gpsup='git push --set-upstream origin "$(git branch --show-current)"'

alias glo='git log --oneline --decorate'
alias glog='git log --oneline --decorate --graph'
alias gloga='git log --oneline --decorate --graph --all'

alias gm='git merge'
alias grb='git rebase'
alias grbi='git rebase --interactive'
alias grba='git rebase --abort'
alias grbc='git rebase --continue'

alias grh='git reset'
alias grhh='git reset --hard'
alias grs='git restore'
alias grst='git restore --staged'
alias grv='git remote --verbose'

alias gst='git status'
alias gss='git status --short'
alias gsta='git stash push'
alias gstp='git stash pop'
alias gstl='git stash list'

# Complétion git sur les alias (branches pour gco/gsw, fichiers pour ga…).
# La complétion git est chargée à la demande par bash-completion : on la
# force ici pour disposer de __git_complete.
if ! declare -F __git_complete >/dev/null && [[ -r /usr/share/bash-completion/completions/git ]]; then
  source /usr/share/bash-completion/completions/git
fi
if declare -F __git_complete >/dev/null; then
  __git_complete g __git_main
  __git_complete ga _git_add;       __git_complete gaa _git_add;   __git_complete gapa _git_add
  __git_complete gb _git_branch;    __git_complete gba _git_branch
  __git_complete gbd _git_branch;   __git_complete gbD _git_branch
  __git_complete gc _git_commit;    __git_complete gca _git_commit
  __git_complete gcs _git_commit;   __git_complete gcsm _git_commit
  __git_complete gcss _git_commit;  __git_complete gcssm _git_commit
  __git_complete gcp _git_cherry_pick
  __git_complete gco _git_checkout; __git_complete gcb _git_checkout
  __git_complete gsw _git_switch;   __git_complete gswc _git_switch
  __git_complete gd _git_diff;      __git_complete gds _git_diff
  __git_complete gf _git_fetch;     __git_complete gfa _git_fetch
  __git_complete gl _git_pull;      __git_complete gpr _git_pull
  __git_complete gp _git_push;      __git_complete gpf _git_push
  __git_complete glo _git_log;      __git_complete glog _git_log;  __git_complete gloga _git_log
  __git_complete gm _git_merge
  __git_complete grb _git_rebase;   __git_complete grbi _git_rebase
  __git_complete grh _git_reset;    __git_complete grhh _git_reset
  __git_complete grs _git_restore;  __git_complete grst _git_restore
  __git_complete gsta _git_stash;   __git_complete gstp _git_stash
fi
