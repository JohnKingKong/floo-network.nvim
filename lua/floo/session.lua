-- floo/session.lua
-- Persists workspace tabs (open files, splits, cursor position, cwd via
-- Neovim's built-in :mksession) across restarts, plus a small sidecar file
-- for floo's own workspace names/pins (which :mksession doesn't know
-- about). Which tabs get saved depends on config.session.persist:
--   "pinned" (default) - only pinned workspaces persist
--   "all"              - every open workspace persists
--   false              - session persistence is off
--
-- Pin already means "protect this workspace" within a running session
-- (survives "close others", asks for confirmation before closing) — the
-- "pinned" persist mode extends that same meaning across restarts, so
-- unpinned/throwaway workspaces don't pile up on every future launch.
--
-- Neo-tree windows are never captured by :mksession (its buffers are
-- unlisted/nofile), so they're reopened explicitly on restore, per tab,
-- scoped to that tab's restored cwd — only if neo-tree.nvim is installed
-- and config.neo_tree.enabled is true.
local M = {}

local switcher = require("floo.switcher")

local SESSION_FILE = vim.fn.stdpath("state") .. "/floo_session.vim"
local META_FILE = vim.fn.stdpath("state") .. "/floo_session.json"

local log = require("floo.debug_log").log

local config = { enabled = true, persist = "pinned" }
local neo_tree_config = { enabled = true }

function M.setup(opts, neo_tree_opts)
  config = opts
  neo_tree_config = neo_tree_opts or neo_tree_config
end

-- neo-tree.nvim is normally lazy-loaded on `:Neotree` (cmd trigger), so on a
-- cold start `require("neo-tree.command")` fails -- not because neo-tree
-- isn't installed, but because it just hasn't been triggered yet. Ask
-- lazy.nvim to load it explicitly first; pcall'd throughout so this is a
-- harmless no-op for anyone not using lazy.nvim or not having neo-tree
-- installed at all.
-- lazy.load() forces neo-tree.nvim's own lazy-load event handlers to fire,
-- which replays whatever autocmd event (FileType/BufReadPost) was queued
-- against Neovim's very first startup buffer before neo-tree ever loaded.
-- By restore() time that buffer has already been replaced by :mksession
-- sourcing, so the replay target is gone -- lazy.nvim's own event handler
-- (lazy/core/handler/event.lua) reports this via vim.notify as "Invalid
-- buffer id: 1". It's benign (confirmed: neo-tree still opens correctly)
-- and is lazy.nvim's own internal quirk, not something callable code can
-- prevent -- so this suppresses just that one notification for the
-- duration of the load call rather than lazy's notifications generally.
local function load_neo_tree_quietly(lazy)
  local original_notify = vim.notify
  vim.notify = function(msg, ...)
    if type(msg) == "string" and msg:find("Invalid buffer id", 1, true) then
      return
    end
    return original_notify(msg, ...)
  end
  local ok = pcall(lazy.load, { plugins = { "neo-tree.nvim" } })
  vim.notify = original_notify
  return ok
end

local function ensure_neo_tree_loaded()
  if package.loaded["neo-tree.command"] then
    return true
  end
  local ok_lazy, lazy = pcall(require, "lazy")
  if ok_lazy then
    load_neo_tree_quietly(lazy)
  end
  return pcall(require, "neo-tree.command")
end

-- Closes every unpinned tab, called only right before quitting (VimLeavePre).
-- Usually has no user-visible effect since we're about to exit anyway and
-- files stay loaded as hidden buffers — except when a tabclose fails (e.g.
-- unsaved changes, E37), which leaves that tab open and silently pulls it
-- into the saved session despite persist = "pinned"; that case is worth a
-- warning since it breaks the mode's documented guarantee without saying so.
local function close_unpinned_tabs()
  for _, tabid in ipairs(vim.api.nvim_list_tabpages()) do
    log(string.format("close_unpinned_tabs: tab %q is_pinned=%s", switcher.get_name(tabid), tostring(switcher.is_pinned(tabid))))
  end
  local blocked = {}
  while #vim.api.nvim_list_tabpages() > 1 do
    local closed_one = false
    for _, tabid in ipairs(vim.api.nvim_list_tabpages()) do
      if not switcher.is_pinned(tabid) then
        local name = switcher.get_name(tabid)
        local ok = pcall(vim.cmd, vim.api.nvim_tabpage_get_number(tabid) .. "tabclose")
        log(string.format("close_unpinned_tabs: closed %q ok=%s", name, tostring(ok)))
        if ok then
          closed_one = true
          break
        else
          blocked[name] = true
        end
      end
    end
    if not closed_one then
      break
    end
  end
  if next(blocked) then
    local names = {}
    for name in pairs(blocked) do
      table.insert(names, name)
    end
    vim.notify(
      "floo-network: could not close unpinned fireplace(s), they will be included in the "
        .. 'saved session despite persist = "pinned": '
        .. table.concat(names, ", "),
      vim.log.levels.WARN
    )
  end
end

function M.save()
  if not (config.enabled and config.persist) then
    return
  end

  switcher.close()

  if config.persist == "pinned" then
    close_unpinned_tabs()

    -- If the one remaining tab is itself unpinned (nothing was pinned at
    -- all), there's nothing worth restoring — clear any previously saved
    -- session rather than persist an unintended workspace.
    local tabs = vim.api.nvim_list_tabpages()
    if #tabs == 1 and not switcher.is_pinned(tabs[1]) then
      vim.fn.delete(SESSION_FILE)
      vim.fn.delete(META_FILE)
      return
    end
  end

  local meta = {}
  for _, tabid in ipairs(vim.api.nvim_list_tabpages()) do
    table.insert(meta, { name = switcher.get_name(tabid), pinned = switcher.is_pinned(tabid) })
  end
  vim.fn.writefile({ vim.json.encode(meta) }, META_FILE)

  vim.cmd("mksession! " .. vim.fn.fnameescape(SESSION_FILE))
end

function M.restore()
  log("restore: start")
  if not (config.enabled and config.persist) then
    log("restore: disabled, returning")
    return
  end
  if vim.fn.filereadable(SESSION_FILE) ~= 1 then
    log("restore: no session file, returning")
    return
  end

  -- The whole body below is deferred to the next tick rather than run
  -- synchronously inside floo's own VeryLazy handler. VeryLazy handler
  -- order across different plugins is unspecified, and two distinct races
  -- fall out of that:
  --   1. ":mksession" sourcing opens every restored file, firing
  --      BufReadPost/LazyFile for each -- if that happens before
  --      nvim-treesitter's own VeryLazy-triggered event handler has been
  --      wired up by lazy.nvim (nvim-treesitter is ALSO a VeryLazy/LazyFile
  --      handler), treesitter's lazy-load trigger never catches it and the
  --      restored buffers open with no syntax highlighting at all.
  --   2. ensure_neo_tree_loaded() can force neo-tree.nvim (a separately
  --      lazy-loaded plugin) to load via lazy.nvim's own load() API --
  --      doing that synchronously, in the middle of floo's own VeryLazy
  --      handler, raced with lazy.nvim's internal event-handler bookkeeping
  --      for other plugins' own lazy-load triggers and produced a real
  --      "Invalid buffer id: 1" error from lazy.nvim's own code.
  -- vim.schedule lets the current VeryLazy cycle -- every plugin's handler,
  -- including lazy.nvim's own bookkeeping for it -- finish first.
  vim.schedule(function()
    log("restore: sourcing session file")
    vim.cmd("silent! source " .. vim.fn.fnameescape(SESSION_FILE))
    log("restore: session file sourced, tabs=" .. #vim.api.nvim_list_tabpages())

    local meta = {}
    if vim.fn.filereadable(META_FILE) == 1 then
      local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(META_FILE), "\n"))
      if ok and type(decoded) == "table" then
        meta = decoded
      end
    end

    local active_tab = vim.api.nvim_get_current_tabpage()

    for i, tabid in ipairs(vim.api.nvim_list_tabpages()) do
      local entry = meta[i]
      if entry then
        if entry.name then
          switcher.set_name(tabid, entry.name)
        end
        switcher.set_pinned(tabid, entry.pinned == true)
      end
    end

    if vim.api.nvim_tabpage_is_valid(active_tab) then
      vim.api.nvim_set_current_tabpage(active_tab)
    end
    log("restore: names/pins applied")

    log("restore: deferred neo-tree reopen starting")
    local has_neo_tree = neo_tree_config.enabled and ensure_neo_tree_loaded()
    log("restore: has_neo_tree=" .. tostring(has_neo_tree))
    if not has_neo_tree then
      log("restore: done (no neo-tree reopen)")
      return
    end

    local reopen_active_tab = vim.api.nvim_get_current_tabpage()
    for _, tabid in ipairs(vim.api.nvim_list_tabpages()) do
      if vim.api.nvim_tabpage_is_valid(tabid) then
        vim.api.nvim_set_current_tabpage(tabid)
        local dir = vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(tabid))
        log("restore: tab opening neo-tree for " .. dir)
        require("neo-tree.command").execute({ toggle = false, dir = dir })
        -- neo-tree's window creation isn't fully synchronous; without
        -- yielding here, back-to-back execute() calls across tabs can race
        -- and silently drop one tab's sidebar.
        vim.wait(50)
        log("restore: tab neo-tree done")
      end
    end

    if vim.api.nvim_tabpage_is_valid(reopen_active_tab) then
      vim.api.nvim_set_current_tabpage(reopen_active_tab)
    end
    log("restore: deferred neo-tree reopen done")
  end)
end

return M
