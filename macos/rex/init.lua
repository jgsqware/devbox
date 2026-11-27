-- Fermer la session courante sans fermer la fenêtre :
-- on bascule d'abord le client sur la session suivante,
-- puis on tue l'ancienne une seconde plus tard.
rex.action{
  name        = "close_session_keep_window",
  title       = "Close Session (Keep Window)",
  description = "Passe à une autre session puis tue celle-ci, sans fermer la fenêtre.",
  keywords    = "kill close session keep window",
  run = function(ctx, args)
    local current = ctx.session_id
    if not current then error("aucune session courante", 0) end

    local list, err = rex.call("session.list")
    if not list then error(err, 0) end

    local target
    for _, s in ipairs(list.sessions or {}) do
      if s.session_id ~= current then target = s.session_id break end
    end
    if not target then
      error("aucune autre session sur ce host : ouvre-en une avant de fermer celle-ci", 0)
    end

    -- Exécuté par le client après le retour de run(). session.select ne marche
    -- pas sur un host distant (le client cherche l'ID sur son serveur local).
    rex.client.queue("session.next")

    -- Le kill attend que le client ait changé de session.
    local h, e = rex.exec.start(
      { "sh", "-c", 'sleep 1; exec /usr/local/bin/rex session kill "$1"', "sh", current },
      { detach = true }
    )
    if not h then error(e, 0) end
  end,
}

rex.bind("cmd+shift+k", "close_session_keep_window")

-- ---------------------------------------------------------------------------
-- Panes flottants, sur l'hôte de la session affichée (local ou distant :
-- ctx.server nomme l'hôte distant, rex.server(nom) lui parle).
local function host_api(ctx)
  if ctx.server and ctx.server ~= "" and rex.server then
    local api = rex.server(ctx.server)
    if api then return api end
  end
  return rex
end

-- process du pane focalisé (pid du shell, dossier courant), ou nil
local function focused_process(api, ctx)
  if not ctx.block_id then return nil end
  local r = api.call("block.method", { session_id = ctx.session_id, block_id = ctx.block_id, method = "process" })
  if type(r) ~= "table" then return nil end
  r = r.result or r
  return r.child
end

local function open_float(ctx, label, options)
  if not ctx.session_id then error("aucune session courante", 0) end
  local api = host_api(ctx)
  local child = focused_process(api, ctx)
  options = options(child)
  if child and child.cwd and not options.cwd then options.cwd = child.cwd end
  local r, err = api.call("session.new_layer", {
    session_id = ctx.session_id,
    bounds     = { 0.1, 0.1, 0.8, 0.75 },
    focus      = true,
    layout     = { block = { flavor = "com.superlogical.terminal.shell", label = label, options = options } },
  })
  if not r then error(err, 0) end
end

-- Pane flottant vide (shell), dans le dossier du pane focalisé.
rex.action{
  name        = "new_floating_pane",
  title       = "New Floating Pane",
  description = "Ouvre un shell dans un pane flottant, sur l'hôte de la session, dans le dossier du pane focalisé.",
  keywords    = "float floating pane popup new shell flottant",
  run = function(ctx, args)
    open_float(ctx, "float", function() return {} end)
  end,
}

-- Bitwarden : bws (devbox, rc.d/55-bitwarden.sh) dans un pane flottant.
-- BWS_CLEAR_TTY : terminal du pane d'origine (Linux : /proc), qui recevra
-- l'effacement du presse-papier après 30 s — le pane flottant sera fermé.
rex.action{
  name        = "bitwarden_search",
  title       = "Bitwarden Search",
  description = "Ouvre bws (recherche fzf dans le coffre Bitwarden) dans un pane flottant, sur l'hôte de la session.",
  keywords    = "bitwarden bw password mot de passe vault coffre",
  run = function(ctx, args)
    open_float(ctx, "bitwarden", function(child)
      local pre = ""
      if child and child.pid then
        pre = "export BWS_CLEAR_TTY=$(readlink /proc/" .. math.floor(child.pid) .. "/fd/0 2>/dev/null); "
      end
      return { command = { "bash", "-ic", pre .. "bws; sleep 1" } }
    end)
  end,
}

rex.bind("cmd+shift+f", "new_floating_pane")
rex.bind("cmd+shift+b", "bitwarden_search")

-- ---------------------------------------------------------------------------
-- Changer de pane à la vim : cmd+alt+h/j/k/l, en plus de cmd+alt+flèche.
-- Sert surtout au deck d'ov : cmd+alt+h → la liste, cmd+alt+l → l'agent.
-- Côté client seulement (ce fichier n'est posé que sur les Mac).
-- macOS : cmd+alt+h est aussi « Masquer les autres » ; s'il prend la touche,
-- le désactiver dans Réglages Système › Clavier › Raccourcis.
rex.bind("cmd+alt+h", "pane.focus.left")
rex.bind("cmd+alt+l", "pane.focus.right")
rex.bind("cmd+alt+k", "pane.focus.up")
rex.bind("cmd+alt+j", "pane.focus.down")

-- Défiler un pane au clavier.
--   cmd+alt+u / cmd+alt+n       : un pas vers le haut / le bas
--   cmd+alt+shift+u / shift+n   : une page entière de l'historique
--   cmd+alt+v                   : mode copie (curseur à la vim, recherche, copie)
--
-- Deux cas, selon ce qui tourne dans le pane :
-- * un shell : Rex garde l'historique. Il ne défile par petits pas qu'en mode
--   copie, donc le pas y entre puis déplace la vue de SCROLL_STEP lignes ;
--   esc pour en sortir (tant qu'on y est, les touches ne vont pas au shell).
-- * un programme plein écran (Claude Code, vim, less… : écran alternatif) :
--   Rex n'a aucun historique à défiler, c'est le programme qui défile. Le pas
--   lui envoie PageUp / PageDown.
local SCROLL_STEP = 10

-- vrai si le programme du pane a pris l'écran alternatif (modes 47, 1047, 1049)
local function full_screen(ctx)
  if not (ctx.session_id and ctx.block_id) then return false end
  local ok, r = pcall(function()
    return host_api(ctx).call("block.method", { session_id = ctx.session_id, block_id = ctx.block_id, method = "modes" })
  end)
  if not ok or type(r) ~= "table" then return false end
  local found = false
  local function walk(t, depth)
    if found or depth > 4 or type(t) ~= "table" then return end
    if (t.number == 47 or t.number == 1047 or t.number == 1049) and t.set == true then found = true return end
    for _, v in pairs(t) do walk(v, depth + 1) end
  end
  walk(r, 0)
  return found
end

local function scroll_step(name, title, to, key)
  rex.action{
    name        = name,
    title       = title,
    description = "Défile le pane d'un pas : " .. SCROLL_STEP .. " lignes d'historique, ou " .. key .. " pour un programme plein écran.",
    keywords    = "scroll défiler historique lignes clavier",
    run = function(ctx, args)
      if full_screen(ctx) then
        rex.client.queue("pane.send_key", { key = key })
        return
      end
      rex.client.queue("pane.copy_mode.enter")
      rex.client.queue("pane.copy_mode.move", { to = to, count = SCROLL_STEP })
    end,
  }
end

scroll_step("scroll_lines_up", "Scroll Lines Up", "scroll_up", "pageup")
scroll_step("scroll_lines_down", "Scroll Lines Down", "scroll_down", "pagedown")

rex.bind("cmd+alt+u", "scroll_lines_up")
rex.bind("cmd+alt+n", "scroll_lines_down")
rex.bind("cmd+alt+shift+u", "client.scroll.page_up")
rex.bind("cmd+alt+shift+n", "client.scroll.page_down")
rex.bind("cmd+alt+v", "pane.copy_mode.enter")

-- ---------------------------------------------------------------------------
-- ov : cmd+shift+o → onglet de la console ov (locale ou sur un host).
-- Source de vérité : dépôt jgsqware/ov (contrib/rex/goto_ov.lua). Cherché dans
-- le checkout de dev ($OV_DIR, sinon ~/code/ov, celui de `mise run ov`), puis
-- dans ~/overview (copie sans le code). Absent partout : pas de binding.
do
  local home = os.getenv("HOME")
  for _, dir in ipairs({ os.getenv("OV_DIR"), home .. "/code/ov", home .. "/overview" }) do
    local f = dir and (dir .. "/contrib/rex/goto_ov.lua")
    local h = f and io.open(f, "r")
    if h then h:close(); dofile(f); break end
  end
end
