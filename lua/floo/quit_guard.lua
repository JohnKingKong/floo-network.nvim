-- floo/quit_guard.lua
-- Confirms before :q/:quit closes a pinned fireplace's last window, or
-- :qa/:qall/:quitall quits Neovim while any fireplace is pinned. Vim's own
-- "unsaved changes" prompt is buffer-dirty-state based and unrelated to
-- this -- a pinned fireplace with every buffer saved would otherwise close
-- with zero warning.
--
-- :q/:qa are builtin Ex commands, not something a plugin can hook directly.
-- cnoreabbrev, matched against the *entire* typed command line (not just a
-- word prefix), is the standard safe way to intercept only what the user
-- actually types at the command line -- vim.cmd("quit") calls made
-- programmatically by other code are untouched, and things like
-- `:g/foo/quit` don't false-trigger.
--
-- ! still confirms too: ! conventionally means "discard unsaved changes",
-- a different concern from "don't silently lose a pinned workspace" -- if !
-- bypassed this, pin protection would be defeated by anyone's habitual
-- :qa!.
local M = {}

local function any_pinned_tab()
  for _, tabid in ipairs(vim.api.nvim_list_tabpages()) do
    if require("floo").is_pinned(tabid) then
      return true
    end
  end
  return false
end

local function count_pinned_tabs()
  local count = 0
  for _, tabid in ipairs(vim.api.nvim_list_tabpages()) do
    if require("floo").is_pinned(tabid) then
      count = count + 1
    end
  end
  return count
end

local function confirm(msg)
  return vim.fn.confirm(msg, "&Yes\n&No", 2) == 1
end

function M.guard_quit(bang)
  local tabid = vim.api.nvim_get_current_tabpage()
  local closes_fireplace = #vim.api.nvim_tabpage_list_wins(tabid) == 1
  if closes_fireplace and require("floo").is_pinned(tabid) then
    local name = require("floo").get_name(tabid)
    if not confirm(string.format('Close pinned fireplace "%s"?', name)) then
      return
    end
  end
  vim.cmd("quit" .. (bang and "!" or ""))
end

function M.guard_quitall(bang)
  if any_pinned_tab() then
    local count = count_pinned_tabs()
    local msg = count == 1 and "1 pinned fireplace is still open. Quit anyway?"
      or (count .. " pinned fireplaces are still open. Quit anyway?")
    if not confirm(msg) then
      return
    end
  end
  vim.cmd("quitall" .. (bang and "!" or ""))
end

local function abbrev(word)
  vim.cmd(string.format(
    [[cnoreabbrev <expr> %s (getcmdtype() ==# ':' && getcmdline() ==# '%s') ? '%s' : '%s']],
    word,
    word,
    "Floo" .. word:sub(1, 1):upper() .. word:sub(2),
    word
  ))
end

function M.setup()
  vim.api.nvim_create_user_command("FlooQ", function(opts)
    M.guard_quit(opts.bang)
  end, { bang = true })
  vim.api.nvim_create_user_command("FlooQuit", function(opts)
    M.guard_quit(opts.bang)
  end, { bang = true })
  vim.api.nvim_create_user_command("FlooQa", function(opts)
    M.guard_quitall(opts.bang)
  end, { bang = true })
  vim.api.nvim_create_user_command("FlooQall", function(opts)
    M.guard_quitall(opts.bang)
  end, { bang = true })
  vim.api.nvim_create_user_command("FlooQuitall", function(opts)
    M.guard_quitall(opts.bang)
  end, { bang = true })

  abbrev("q")
  abbrev("quit")
  abbrev("qa")
  abbrev("qall")
  abbrev("quitall")
end

return M
