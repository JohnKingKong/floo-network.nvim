-- floo/init.lua
-- Public entry point. See README.md for the full config reference and the
-- Floo Network naming rationale.
local M = {}

local config_mod = require("floo.config")
local switcher = require("floo.switcher")
local session = require("floo.session")

local function has_neo_tree()
  return pcall(require, "neo-tree.command")
end

function M.setup(opts)
  local config = config_mod.merge(opts)
  switcher.setup(config)
  session.setup(config.session)

  local keys = config.keys or {}

  local function map(lhs, rhs, desc)
    if lhs then
      vim.keymap.set("n", lhs, rhs, { desc = desc })
    end
  end

  map(keys.new, M.new_workspace, "Floo: New Workspace")
  map(keys.rename, M.rename_current, "Floo: Rename Workspace")
  map(keys.pin, M.toggle_pin_current, "Floo: Toggle Pin Workspace")
  map(keys.switch, M.open_dropdown, "Floo: Switch Workspace")
  map(keys.close, M.close_current, "Floo: Close Workspace")
  map(keys.close_others, M.close_others, "Floo: Close Other Workspaces")
  map(keys.switch_buffer, M.switch_to_other_buffer, "Floo: Switch to Other Buffer (this workspace)")

  if keys.explorer and config.neo_tree.enabled and has_neo_tree() then
    map(keys.explorer, function()
      require("neo-tree.command").execute({ toggle = true, dir = vim.fn.getcwd(-1, 0) })
    end, "Floo: Explorer (Workspace Dir)")
  end

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
  vim.ui.input({ prompt = "Workspace folder: ", completion = "dir", default = vim.fn.getcwd() .. "/" }, function(input)
    if not input or input == "" then
      return
    end
    local dir = vim.fn.fnamemodify(input, ":p")
    vim.cmd("tabnew")
    vim.cmd("tcd " .. vim.fn.fnameescape(dir))
    switcher.set_name(vim.api.nvim_get_current_tabpage(), vim.fn.fnamemodify(dir, ":h:t"))
    if has_neo_tree() then
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
