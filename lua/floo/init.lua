-- floo/init.lua
-- Public entry point. See README.md for the full config reference and the
-- Floo Network naming rationale.
local M = {}

local config_mod = require("floo.config")
local switcher = require("floo.switcher")
local session = require("floo.session")
local quit_guard = require("floo.quit_guard")

local function has_neo_tree()
  return pcall(require, "neo-tree.command")
end

-- Read by new_workspace(), which runs long after setup() returns (it's a
-- keymap callback), so the merged neo_tree config is kept at module scope
-- rather than only living inside setup()'s local `config`.
local neo_tree_config = { enabled = true }

function M.setup(opts)
  local config = config_mod.merge(opts)
  neo_tree_config = config.neo_tree
  switcher.setup(config)
  session.setup(config.session, config.neo_tree)
  quit_guard.setup()

  local keys = config.keys or {}

  local function map(lhs, rhs, desc)
    if lhs then
      vim.keymap.set("n", lhs, rhs, { desc = desc })
    end
  end

  map(keys.new, M.new_workspace, "Floo: New Fireplace")
  map(keys.rename, M.rename_current, "Floo: Rename Fireplace")
  map(keys.pin, M.toggle_pin_current, "Floo: Toggle Pin Fireplace")
  map(keys.switch, M.open_dropdown, "Floo: Switch Fireplace")
  map(keys.close, M.close_current, "Floo: Close Fireplace")
  map(keys.close_others, M.close_others, "Floo: Close Other Fireplaces")
  map(keys.switch_buffer, M.switch_to_other_buffer, "Floo: Switch to Other Buffer (this fireplace)")

  if keys.explorer and config.neo_tree.enabled and has_neo_tree() then
    map(keys.explorer, function()
      require("neo-tree.command").execute({ toggle = true, dir = vim.fn.getcwd(-1, 0) })
    end, "Floo: Explorer (Fireplace Dir)")
  end

  -- Harmless no-op for anyone not using the tabline.lua bufferline
  -- integration; keeps the current fireplace's name (which tabline.lua
  -- reads fresh on every render) in sync with the visible tab on switch.
  vim.api.nvim_create_autocmd("TabEnter", {
    callback = function()
      pcall(vim.cmd, "redrawtabline")
    end,
  })

  -- TEMPORARY: catches every window close, regardless of path (:q, ZQ,
  -- some other plugin's nvim_win_close, etc. -- not just floo's own
  -- close_tab/guard_quit/guard_quitall, which already log their own
  -- confirm() results), and logs unconditionally whenever it's about to
  -- close a PINNED fireplace's LAST window -- the "ground truth" signal
  -- for chasing pinned fireplaces occasionally disappearing during long
  -- Neovide sessions with no confirmed trigger yet. WinClosed fires
  -- before the window is actually invalidated (confirmed empirically), so
  -- the tab/pin state is still readable here. If this ever fires with no
  -- corresponding "confirmed=true" log line from one of the guarded
  -- paths, that's a close bypassing all of floo's own pin protection.
  vim.api.nvim_create_autocmd("WinClosed", {
    callback = function(args)
      local winid = tonumber(args.match)
      if not winid or not vim.api.nvim_win_is_valid(winid) then
        return
      end
      local ok_tab, tabid = pcall(vim.api.nvim_win_get_tabpage, winid)
      if not ok_tab then
        return
      end
      local wins = vim.api.nvim_tabpage_list_wins(tabid)
      local is_last = #wins == 1 and wins[1] == winid
      if is_last and switcher.is_pinned(tabid) then
        require("floo.debug_log").log(
          string.format("WinClosed: pinned fireplace %q's last window (win=%d) is closing", switcher.get_name(tabid), winid)
        )
      end
    end,
  })

  if config.session.enabled and config.session.persist then
    vim.api.nvim_create_autocmd("VimLeavePre", {
      callback = function()
        session.save()
      end,
    })
    if vim.fn.argc(-1) == 0 then
      session.restore()
    end
  end
end

function M.get_name(tabid)
  return switcher.get_name(tabid)
end

function M.set_name(tabid, name)
  switcher.set_name(tabid, name)
end

function M.is_pinned(tabid)
  return switcher.is_pinned(tabid)
end

function M.set_pinned(tabid, pinned)
  switcher.set_pinned(tabid, pinned)
end

function M.toggle_pin(tabid)
  switcher.toggle_pin(tabid)
end

function M.rename(tabid)
  switcher.rename(tabid)
end

-- Opens a new tab as a self-contained workspace scoped to a chosen folder.
function M.new_workspace()
  vim.ui.input({ prompt = "Fireplace folder: ", completion = "dir", default = vim.fn.getcwd() .. "/" }, function(input)
    if not input or input == "" then
      return
    end
    local dir = vim.fn.fnamemodify(input, ":p")
    vim.cmd("tabnew")
    -- Keep tabnew's initial [No Name] buffer as the workspace's actual empty
    -- edit area alongside neo-tree's sidebar, rather than deleting it: with
    -- neo-tree enabled it's the *only* other window right after creating a
    -- workspace, so deleting it leaves neo-tree alone - closing your last
    -- window then closes the whole tab (standard Vim behavior). Opening a
    -- real file from neo-tree replaces this buffer in place as normal, so
    -- there's nothing left over once you do.
    vim.cmd("tcd " .. vim.fn.fnameescape(dir))
    switcher.set_name(vim.api.nvim_get_current_tabpage(), vim.fn.fnamemodify(dir, ":h:t"))
    if neo_tree_config.enabled and has_neo_tree() then
      require("neo-tree.command").execute({ toggle = false, dir = dir })
    end
  end)
end

function M.rename_current()
  switcher.rename_current()
end

function M.toggle_pin_current()
  switcher.toggle_pin_current()
end

function M.open_dropdown()
  switcher.open_dropdown()
end

function M.close_current()
  switcher.close_current()
end

function M.close_others()
  switcher.close_others()
end

function M.switch_to_other_buffer()
  switcher.switch_to_other_buffer()
end

-- Bufferline integration hook. Not wired automatically — floo-network.nvim doesn't
-- own bufferline's config. Wire it into your own bufferline spec:
--   opts.options.custom_filter = function(bufnr)
--     return require("floo").buf_belongs_to_current_workspace(bufnr)
--   end
function M.buf_belongs_to_current_workspace(bufnr)
  return switcher.buf_belongs_to_tab(bufnr, vim.api.nvim_get_current_tabpage())
end

return M
