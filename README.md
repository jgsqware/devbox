# devbox

Provisionne un poste de travail **headless « omarchy-flavored »** sur un **Arch nu**
(WSL, conteneur Incus, VM, Mac-en-conteneur) — sans jamais installer la distro Omarchy.

Le principe : Omarchy publie un **vrai dépôt pacman public**. On l'ajoute à un Arch nu
et on **picore**. L'écrémage est dans `packages.txt`, pas dans un nettoyage a posteriori.

```
Arch nu ──▶ [omarchy] ──▶ 46 paquets ──▶ /etc/skel ──▶ moteur vendoré ──▶ shell ──▶ thème
```

## Usage

Le script se lance **indifféremment en root ou en utilisateur**.

```bash
git clone <url> devbox && cd devbox
./bootstrap.sh -n          # dry-run : affiche tout, n'exécute rien
./bootstrap.sh             # pour de vrai
./bootstrap.sh --only tailscale --with-tailscale
```

### Depuis un root nu (WSL fraîche, conteneur Incus)

```bash
./bootstrap.sh --user jgsqware [--sudo-nopasswd]
```

En root, le script installe `sudo`, **crée l'utilisateur s'il n'existe pas**
(home + bash + `wheel`), demande son mot de passe, autorise `wheel` dans
`/etc/sudoers` (validé par `visudo -c`), puis **se relance en son nom** — en
recopiant le dépôt hors de `/root` si besoin.

Sous **WSL**, il s'arrête d'abord après l'étape ① : `/etc/wsl.conf` y pose aussi
`[user] default=<user>`, donc après

```powershell
wsl --shutdown
```

la WSL rouvre **directement sur le bon utilisateur**. Reprendre avec :

```bash
cd ~/devbox && ./bootstrap.sh --from repo
```

## Fichiers

| Fichier | Rôle |
|---|---|
| `bootstrap.sh` | les 9 étapes, idempotentes, rejouables (root ou user) |
| `packages.txt` | **la source de vérité** des paquets — tout ajout se propage à tous les nœuds |
| `overlay/bash/bashrc` | le `~/.bashrc` déployé — rebranche la chaîne omarchy sur le moteur vendoré |
| `overlay/bash/bash_profile` | `~/.bash_profile` (WSL et ssh lancent un shell de login) |
| `overlay/bash/rc.d/*.sh` | **les réglages shell** — déposés dans `~/.config/devbox/rc.d/` |
| `overlay/omarchy/themed/*.tpl` | cibles de thème supplémentaires (zellij) |

## D'où vient le prompt

Sur un vrai poste Omarchy, le prompt (starship), les alias et les fonctions
viennent du paquet `omarchy` : `/usr/share/omarchy/default/bash/*` + un
`/etc/skel/.bashrc` qui les source. On n'installe **pas** ce paquet, donc
l'étape `shell` rétablit la même chaîne depuis le dépôt vendoré :

```
~/.bashrc  (overlay/bash/bashrc)
   └─▶ $OMARCHY_PATH/default/bash/rc
         ├── envs · shell · aliases · functions
         ├── init  →  mise · starship · zoxide · fzf
         └── inputrc
   └─▶ ~/.config/devbox/rc.d/*.sh        ← nos overrides, chargés en dernier
```

Les configs copiées depuis le dépôt : `starship.toml` `tmux.conf`
`lazygit/config.yml` `btop.conf` `git/config`. Ajouter une cible = une ligne
dans `DOTCONFIGS` (dans `bootstrap.sh`).

## Override bash

`~/.bashrc` ne contient **qu'un loader** qui ne bouge plus jamais :

```bash
# >>> devbox >>>
for _devbox_rc in "$HOME"/.config/devbox/rc.d/*.sh; do
  [[ -r "$_devbox_rc" ]] && source "$_devbox_rc"
done
unset _devbox_rc
# <<< devbox <<<
```

Tout le reste vit dans des fichiers versionnés, chargés **dans l'ordre des noms** :

| Fichier | Rôle | Converge ? |
|---|---|---|
| `10-env.sh` | `OMARCHY_PATH`, `OMARCHY_THEME_HEADLESS`, `PATH` (idempotent) | ✅ |
| `20-start-dir.sh` | sous WSL, revient dans `$HOME` quand le shell démarre dans `/mnt/*` | ✅ |
| `05-local-start-dir.sh` | posé par `--start-dir`, propre au nœud | ❌ local |

Ajouter un réglage = déposer un `NN-truc.sh` dans `overlay/bash/rc.d/` et rejouer
`./bootstrap.sh --only vendor`. Rien à toucher dans `~/.bashrc`.

### Répertoire de démarrage

```bash
./bootstrap.sh --only vendor --start-dir /work     # démarrer ailleurs
./bootstrap.sh --only vendor --start-dir keep      # désactiver le cd
```

`20-start-dir.sh` n'agit **que** si le shell est interactif, sous WSL, et que le
`$PWD` de départ est sous `/mnt/` — un `wsl -e bash -lc "cd /mnt/c/… && …"` reste
intact.

## Règles

- ⛔ **Ne jamais `pacman -S omarchy`** : 22 dépendances / 121 Mo (hyprland, sddm,
  quickshell…) et tout l'écrémage part à la poubelle. Le moteur de thème est
  vendoré en sparse-checkout **no-cone** (~5 Mo : `bin/`, `default/`, `themes/` sans les images).
- ✅ **Zéro AUR** : les 46 paquets sont binaires (`core`/`extra` + 3 de `[omarchy]` :
  `omarchy-nvim`, `mise-bin`, `yay`).
- 🚫 **Ne converge jamais** : identité git, clés SSH/GPG, tokens, historique shell,
  `~/.claude/`, `/work`, `/leases`.
- 🌐 Le bootstrap sort sur **internet direct** (`pkgs.omarchy.org`), pas sur la tailnet.
  Tailscale est la **dernière** étape — sauf egress filtré, où il devient la première
  (exit node).

## Référence

`meta/analyses/analyse-forge-par-client-et-baux.md` §10 (procédure) et §11 (thèmes headless).
