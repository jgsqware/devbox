# À faire

- [ ] **mini : pas de DNS internet** — `/etc/resolv.conf` ne pointe que sur
  MagicDNS (`100.100.100.100`), `systemd-resolved` inactif : les noms de la
  tailnet résolvent, `github.com` non. Le sync y échoue au `git pull`
  (`Could not resolve host: github.com`, log du 2026-09-26). Pistes :
  nameservers globaux dans la console Tailscale (DNS → Global nameservers),
  ou activer `systemd-resolved` sur mini pour que tailscaled s'y branche.
