// devbox — prefs du profil Zen « devbox » (copié par zen-setup, réappliqué à chaque lancement)
user_pref("privacy.userContext.enabled", true);          // containers
user_pref("privacy.userContext.ui.enabled", true);
user_pref("network.proxy.socks_remote_dns", true);       // DNS côté proxy (MAC force aussi proxyDNS)
// Pas de déchargement mémoire : Firefox ne sait pas exclure par URL → Teams perdrait ses notifications
user_pref("browser.tabs.unloadOnLowMemory", false);
user_pref("zen.tab-unloader.excluded-urls", "teams.microsoft.com,teams.cloud.microsoft,outlook.cloud.microsoft,outlook.office.com");
// aero-spawn possède les fenêtres : pas de restauration de session (sinon doublons au redémarrage)
user_pref("browser.startup.page", 1);
user_pref("browser.sessionstore.resume_from_crash", false);
// Notifications natives macOS
user_pref("alerts.useSystemBackend", true);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.aboutwelcome.enabled", false);
// Synchro des fenêtres ON (défaut Zen) : c'est elle qui rend les espaces persistants
// (zen-sessions.jsonlz4). Chaque fenêtre affiche SON espace → seulement ses onglets.
user_pref("zen.window-sync.enabled", true);
// Un onglet ouvert dans un container bascule sur l'espace Zen lié à ce container
user_pref("zen.workspaces.force-container-workspace", true);
user_pref("zen.workspaces.hide-default-container-indicator", false);
// Barre de favoris toujours visible (Zen la cache : défaut "never") — dossiers Gaming1/Iba/wk par espace
user_pref("browser.toolbars.bookmarks.visibility", "always");
