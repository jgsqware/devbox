# devbox — atuin : historique shell (Ctrl-R, flèche haut).
# Chargé APRÈS la chaîne omarchy (rc.d passe en dernier), donc reprend Ctrl-R à
# fzf.
#
# ⚠️ atuin ≥ 18.x n'embarque PLUS bash-preexec : sans lui, __atuin_preexec ne se
# déclenche jamais et AUCUNE commande n'est enregistrée (flèche haut = vieil
# historique figé). On le charge ici, avant `atuin init`. Paquet `bash-preexec`
# (pacman : /usr/share/bash-preexec, brew : $HOMEBREW_PREFIX/etc/profile.d).
if [[ $- == *i* ]] && command -v atuin >/dev/null 2>&1; then
  if [[ -z ${bash_preexec_imported-}${__bp_imported-} ]]; then
    for _bp in /usr/share/bash-preexec/bash-preexec.sh \
               "${HOMEBREW_PREFIX:-/opt/homebrew}/etc/profile.d/bash-preexec.sh"; do
      [[ -r $_bp ]] && { source "$_bp"; break; }
    done
    unset _bp
  fi
  eval "$(atuin init bash)"
fi
