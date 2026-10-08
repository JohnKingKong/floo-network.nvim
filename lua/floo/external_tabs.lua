-- floo/external_tabs.lua
-- Gives a sensible identity to tabs floo-network didn't create itself.
--
-- The motivating case: lazygit's nvim-remote editor preset (what
-- snacks.nvim's lazygit integration auto-configures) always edits a file
-- via `nvim --server $NVIM --remote-tab {{filename}}` -- Neovim's own
-- --remote-tab RPC, which ALWAYS creates a brand-new tab with no "reuse if
-- already open" option, regardless of what floo-network does. Without this,
-- that new tab is invisible to floo's switcher state (no registered name or
-- cwd), so get_name()'s fallback -- fnamemodify(getcwd(-1, tabnr), ":t") --
-- shows whatever Neovim's GLOBAL cwd happened to be at startup (since a bare
-- new tab inherits that, not any fireplace's own :tcd'd directory), not the
-- actual directory of the file that was just opened. Editing several files
-- this way also leaves several of these untracked tabs behind.
--
-- TabNewEntered looks like the obvious hook but fires too early for this:
-- confirmed empirically that for `:tab drop {file}` (what --remote-tab
-- actually triggers), TabNewEntered fires while the new tab still shows the
-- PREVIOUS tab's buffer, before the target file loads. BufWinEnter fires
-- with the correct buffer, but twice per external open, and acting
-- synchronously inside it risks interfering with whatever external command
-- is still mid-flight (the same class of issue as the E36 "not enough room"
-- lesson from winbar-on-a-float earlier this project) -- so the actual work
-- is deferred one tick via vim.schedule, by which point the only state that
-- matters (tab validity, registration, current buffer) is settled.
local M = {}

local switcher = require("floo.switcher")

-- Nearest .git's parent directory, falling back to the file's own directory
-- if none is found (e.g. a file outside any git repo).
local function project_root_for(path)
  local git_dir = vim.fs.find(".git", { path = vim.fs.dirname(path), upward = true })[1]
  if git_dir then
    return vim.fs.dirname(git_dir)
  end
  return vim.fs.dirname(path)
end

local function handle(tabid, bufnr)
  if not vim.api.nvim_tabpage_is_valid(tabid) then
    return -- handled already by an earlier deferred firing for this same open
  end
  if switcher.is_registered(tabid) then
    return
  end
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "" then
    return
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    return
  end
  -- The buffer actually showing in this tab may have moved on since the
  -- event fired (e.g. the same tick closed it); only act if it's still what
  -- triggered this.
  if vim.api.nvim_win_get_buf(vim.api.nvim_tabpage_get_win(tabid)) ~= bufnr then
    return
  end

  local existing = switcher.find_fireplace_for_path(path)
  if existing and existing ~= tabid then
    local duplicate_tabnr = vim.api.nvim_tabpage_get_number(tabid)
    vim.api.nvim_set_current_tabpage(existing)
    vim.api.nvim_set_current_win(switcher.pick_edit_win(existing))
    vim.cmd.edit(vim.fn.fnameescape(path))
    pcall(vim.cmd, duplicate_tabnr .. "tabclose")
    return
  end

  local root = project_root_for(path)
  vim.cmd("tcd " .. vim.fn.fnameescape(root))
  switcher.set_name(tabid, vim.fn.fnamemodify(root, ":t"))
  pcall(vim.cmd, "redrawtabline")
end

function M.setup()
  vim.api.nvim_create_autocmd("BufWinEnter", {
    callback = function()
      local tabid = vim.api.nvim_get_current_tabpage()
      local bufnr = vim.api.nvim_get_current_buf()
      vim.schedule(function()
        handle(tabid, bufnr)
      end)
    end,
  })
end

return M
