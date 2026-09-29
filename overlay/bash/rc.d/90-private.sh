# devbox — couche privée : réglages qui n'ont rien à faire dans ce dépôt public
# (hôtes internes, URL de travail…).
#
# Ils vivent dans un dépôt git séparé, jamais publié, cloné par bootstrap.sh
# dans ~/.config/devbox/private (étape shell). Ce fichier se contente d'en
# charger les rc.d, APRÈS ceux du dépôt public : le privé peut donc surcharger.
# Pas de clone (machine sans accès) : rien n'est chargé, sans erreur.
#
# Surcharge : DEVBOX_PRIVATE_DIR=/chemin   (défaut : ~/.config/devbox/private)

for _devbox_rc in "${DEVBOX_PRIVATE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/devbox/private}"/rc.d/*.sh; do
  [[ -r "$_devbox_rc" ]] && source "$_devbox_rc"
done
unset _devbox_rc
