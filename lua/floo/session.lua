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

-- TEMPORARY: diagnostic logging while chasing the "Invalid buffer id: 1"
-- startup error from lazy.nvim's event handler. Safe to remove once that's
-- confirmed or ruled out.
local DEBUG_LOG = vim.fn.stdpath("state") .. "/floo_debug.log"
local function log(msg)
  local fd = io.open(DEBUG_LOG, "a")
  if fd then
    -- hrtime (monotonic nanoseconds) alongside wall-clock time so log lines
    -- within the same second can still be ordered precisely.
    fd:write(string.format("[%s %d] %s\n", os.date("%H:%M:%S"), vim.loop.hrtime(), msg))
    fd:close()
  end
end

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
local function ensure_neo_tree_loaded()
  if package.loaded["neo-tree.command"] then
    return true
  end
  local ok_lazy, lazy = pcall(require, "lazy")
  if ok_lazy then
    pcall(lazy.load, { plugins = { "neo-tree.nvim" } })
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
  local blocked = {}
  while #vim.api.nvim_list_tabpages() > 1 do
    local closed_one = false
    for _, tabid in ipairs(vim.api.nvim_list_tabpages()) do
      if not switcher.is_pinned(tabid) then
        local ok = pcall(vim.cmd, vim.api.nvim_tabpage_get_number(tabid) .. "tabclose")
        if ok then
          closed_one = true
          break
        else
          blocked[switcher.get_name(tabid)] = true
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
  local has_neo_tree = neo_tree_config.enabled and ensure_neo_tree_loaded()
  log("restore: has_neo_tree=" .. tostring(has_neo_tree))

  for i, tabid in ipairs(vim.api.nvim_list_tabpages()) do
    local entry = meta[i]
    if entry then
      if entry.name then
        switcher.set_name(tabid, entry.name)
      end
      switcher.set_pinned(tabid, entry.pinned == true)
    end

    vim.api.nvim_set_current_tabpage(tabid)
    if has_neo_tree then
      local dir = vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(tabid))
      log("restore: tab " .. i .. " opening neo-tree for " .. dir)
      require("neo-tree.command").execute({ toggle = false, dir = dir })
      -- neo-tree's window creation isn't fully synchronous; without
      -- yielding here, back-to-back execute() calls across tabs can race
      -- and silently drop one tab's sidebar.
      vim.wait(50)
      log("restore: tab " .. i .. " neo-tree done")
    end
  end

  if vim.api.nvim_tabpage_is_valid(active_tab) then
    vim.api.nvim_set_current_tabpage(active_tab)
  end
  log("restore: done")
end

return M
