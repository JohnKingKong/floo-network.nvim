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
-- scoped to that tab's restored cwd — only if neo-tree.nvim is installed.
local M = {}

local switcher = require("floo.switcher")

local SESSION_FILE = vim.fn.stdpath("state") .. "/floo_session.vim"
local META_FILE = vim.fn.stdpath("state") .. "/floo_session.json"

local config = { enabled = true, persist = "pinned" }

function M.setup(opts)
  config = opts
end

-- Closes every unpinned tab, called only right before quitting (VimLeavePre)
-- so this has no user-visible effect — we're about to exit anyway. Files
-- stay loaded as hidden buffers, so nothing is lost, just not persisted.
local function close_unpinned_tabs()
  while #vim.api.nvim_list_tabpages() > 1 do
    local closed_one = false
    for _, tabid in ipairs(vim.api.nvim_list_tabpages()) do
      if not switcher.is_pinned(tabid) then
        local ok = pcall(vim.cmd, vim.api.nvim_tabpage_get_number(tabid) .. "tabclose")
        if ok then
          closed_one = true
          break
        end
      end
    end
    if not closed_one then
      break
    end
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
  if not (config.enabled and config.persist) then
    return
  end
  if vim.fn.filereadable(SESSION_FILE) ~= 1 then
    return
  end

  vim.cmd("silent! source " .. vim.fn.fnameescape(SESSION_FILE))

  local meta = {}
  if vim.fn.filereadable(META_FILE) == 1 then
    local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(META_FILE), "\n"))
    if ok and type(decoded) == "table" then
      meta = decoded
    end
  end

  local active_tab = vim.api.nvim_get_current_tabpage()
  local has_neo_tree = pcall(require, "neo-tree.command")

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
      require("neo-tree.command").execute({ toggle = false, dir = dir })
      -- neo-tree's window creation isn't fully synchronous; without
      -- yielding here, back-to-back execute() calls across tabs can race
      -- and silently drop one tab's sidebar.
      vim.wait(50)
    end
  end

  if vim.api.nvim_tabpage_is_valid(active_tab) then
    vim.api.nvim_set_current_tabpage(active_tab)
  end
end

return M
