-- floo/switcher.lua
-- Workspace switching: a dropdown listing every open workspace tab, hidden
-- until triggered. Click a line (or <CR>) to switch, `r` to rename, `p` to
-- pin/unpin. See README.md for why pin means what it means (Floo Network).
local M = {}

local log = require("floo.debug_log").log

local NAMESPACE = vim.api.nvim_create_namespace("floo_switcher")
local PIN_ICON = "󰐃 "
local DEFAULT_GUICURSOR = vim.o.guicursor

vim.api.nvim_set_hl(0, "FlooCursor", { link = "Normal" })

local config = { dropdown = { position = "top-right", border = "rounded" } }

function M.setup(opts)
  config = opts
end

-- Only one dropdown can be open at a time.
-- { tabid, winid, bufnr, origin_win, line_to_tab }
local current = nil

local function tab_var(tabid, name)
  local ok, value = pcall(vim.api.nvim_tabpage_get_var, tabid, name)
  if ok then
    return value
  end
  return nil
end

function M.get_name(tabid)
  local name = tab_var(tabid, "floo_workspace_name")
  if name then
    return name
  end
  local tabnr = vim.api.nvim_tabpage_get_number(tabid)
  local cwd = vim.fn.getcwd(-1, tabnr)
  return vim.fn.fnamemodify(cwd, ":t")
end

function M.set_name(tabid, name)
  vim.api.nvim_tabpage_set_var(tabid, "floo_workspace_name", name)
end

-- Whether a buffer's file lives under the given tab's cwd (unnamed scratch
-- buffers always count). Unlisted buffers (neo-tree's tree, etc.) never
-- count: neo-tree's internal buffer name is literally
-- "<cwd>/neo-tree filesystem [N]", which would otherwise pass the cwd-prefix
-- check below and get treated as a switchable file.
function M.buf_belongs_to_tab(bufnr, tabid)
  if not vim.bo[bufnr].buflisted then
    return false
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then
    return true
  end
  local tabnr = vim.api.nvim_tabpage_get_number(tabid)
  local cwd = vim.fn.getcwd(-1, tabnr)

  -- Terminal buffers (:terminal buffers are buflisted=true by default) are
  -- named "term://<cwd>//<pid>:<cmd>", where <cwd> is Neovim's own cwd at
  -- the moment :terminal was invoked (tilde-shortened when under $HOME) --
  -- not a literal path prefix like every other buffer name, so the plain
  -- startswith check below always rejected them even when opened from
  -- exactly this tab (e.g. a button whose command `cd`s further down: that
  -- cd happens inside the spawned shell, after the buffer name is already
  -- fixed). Without this, a still-running dev-server terminal disappears
  -- from the fireplace's bufferline the moment its window closes, with no
  -- obvious way back to it.
  if vim.bo[bufnr].buftype == "terminal" then
    local term_cwd = name:match("^term://(.-)//")
    if not term_cwd then
      return false
    end
    term_cwd = vim.fn.fnamemodify(term_cwd, ":p"):gsub("/$", "")
    return term_cwd == cwd or vim.startswith(term_cwd, cwd .. "/")
  end

  -- A plain vim.startswith(name, cwd) has no path-boundary check, so a
  -- workspace at ~/proj would wrongly claim a buffer from ~/proj-old too
  -- (the string "~/proj-old" textually starts with "~/proj").
  return name == cwd or vim.startswith(name, cwd .. "/")
end

-- Tab-aware replacement for ":e #". Vim's alternate buffer register isn't
-- reset by :tabnew — a freshly created workspace tab inherits whatever file
-- was alternate in the tab it was created from, so plain ":e #" can silently
-- open a file from a completely different workspace. Prefer the alternate
-- buffer if it belongs to this tab; otherwise fall back to the most
-- recently used buffer that does.
function M.switch_to_other_buffer()
  local tabid = vim.api.nvim_get_current_tabpage()
  local current_buf = vim.api.nvim_get_current_buf()

  local alt = vim.fn.bufnr("#")
  if alt ~= -1 and alt ~= current_buf and vim.api.nvim_buf_is_valid(alt) and M.buf_belongs_to_tab(alt, tabid) then
    vim.cmd("buffer " .. alt)
    return
  end

  local best, best_lastused = nil, -1
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if info.bufnr ~= current_buf and M.buf_belongs_to_tab(info.bufnr, tabid) and info.lastused > best_lastused then
      best, best_lastused = info.bufnr, info.lastused
    end
  end

  if best then
    vim.cmd("buffer " .. best)
  else
    vim.notify("No other buffer open in this fireplace", vim.log.levels.INFO)
  end
end

function M.is_pinned(tabid)
  return tab_var(tabid, "floo_workspace_pinned") == true
end

function M.toggle_pin(tabid)
  vim.api.nvim_tabpage_set_var(tabid, "floo_workspace_pinned", not M.is_pinned(tabid))
  -- Harmless no-op for anyone not using the tabline.lua bufferline
  -- integration (see its own comment); redraws it immediately for anyone
  -- who is, rather than waiting for some unrelated redraw to trigger it.
  pcall(vim.cmd, "redrawtabline")
end

function M.set_pinned(tabid, pinned)
  vim.api.nvim_tabpage_set_var(tabid, "floo_workspace_pinned", pinned)
end

function M.rename(tabid)
  vim.ui.input({ prompt = "Fireplace name: ", default = M.get_name(tabid) }, function(input)
    if input and input ~= "" then
      M.set_name(tabid, input)
      pcall(vim.cmd, "redrawtabline")
      if current and current.tabid == tabid then
        M.refresh_open()
      end
    end
  end)
end

function M.rename_current()
  M.rename(vim.api.nvim_get_current_tabpage())
end

function M.toggle_pin_current()
  M.toggle_pin(vim.api.nvim_get_current_tabpage())
  M.refresh_open()
end

-- Closes a given tab, confirming first if it's pinned. If the dropdown is
-- open in that tab, closes the dropdown first: tabclose would otherwise
-- destroy it without going through M.close(), leaving `current` pointing at
-- a dead win/buf so the next open_dropdown() thinks one is already open and
-- no-ops.
-- Returns true if the tab was actually closed.
local function close_tab(tabid)
  if M.is_pinned(tabid) then
    local choice = vim.fn.confirm(string.format('Close pinned fireplace "%s"?', M.get_name(tabid)), "&Yes\n&No", 2)
    log(string.format("close_tab: pinned fireplace %q, confirm choice=%d", M.get_name(tabid), choice))
    if choice ~= 1 then
      return false
    end
  end
  if current and current.tabid == tabid then
    M.close()
  end
  local tabnr = vim.api.nvim_tabpage_get_number(tabid)
  local ok, err = pcall(vim.cmd, tabnr .. "tabclose")
  if not ok then
    vim.notify(err, vim.log.levels.WARN)
    return false
  end
  return true
end

-- Closes the current tab, confirming first if it's pinned.
function M.close_current()
  close_tab(vim.api.nvim_get_current_tabpage())
end

-- Closes every tab except the current one, confirming first for any pinned
-- ones (same as close_current/close_at_cursor) rather than silently skipping
-- them.
function M.close_others()
  local current_tab = vim.api.nvim_get_current_tabpage()
  for _, tabid in ipairs(vim.api.nvim_list_tabpages()) do
    if tabid ~= current_tab and vim.api.nvim_tabpage_is_valid(tabid) then
      close_tab(tabid)
    end
  end
  -- Refresh rather than close: the dropdown (if open) lives in current_tab,
  -- which survives, but its line_to_tab entries for the now-closed tabs are
  -- stale until the list is rebuilt.
  M.refresh_open()
end

local function sorted_tabs()
  local tabs = vim.api.nvim_list_tabpages()
  table.sort(tabs, function(a, b)
    local pinned_a, pinned_b = M.is_pinned(a), M.is_pinned(b)
    if pinned_a ~= pinned_b then
      return pinned_a
    end
    return vim.api.nvim_tabpage_get_number(a) < vim.api.nvim_tabpage_get_number(b)
  end)
  return tabs
end

-- Computes the dropdown's row/col from config.dropdown.position, given the
-- window's current width/height.
local function compute_geometry(width, height)
  local position = config.dropdown.position or "top-right"
  local col
  if position == "top-left" or position == "bottom-left" then
    col = 0
  else
    col = vim.o.columns - width
  end
  local row
  if position == "bottom-left" or position == "bottom-right" then
    row = vim.o.lines - height - vim.o.cmdheight - 1
  else
    row = 0
  end
  return row, col
end

-- Closes the dropdown (if open) and restores focus/cursor. Safe to call
-- when nothing is open.
function M.close()
  if not current then
    return
  end
  local c = current
  current = nil

  vim.o.guicursor = DEFAULT_GUICURSOR

  if vim.api.nvim_win_is_valid(c.winid) then
    vim.api.nvim_win_close(c.winid, true)
  end

  if c.origin_win and vim.api.nvim_win_is_valid(c.origin_win) then
    pcall(vim.api.nvim_set_current_win, c.origin_win)
  end
end

local function switch_at_cursor()
  if not current then
    return
  end
  local line = vim.api.nvim_win_get_cursor(current.winid)[1]
  local target = current.line_to_tab[line]
  M.close()
  if target and vim.api.nvim_tabpage_is_valid(target) then
    vim.api.nvim_set_current_tabpage(target)
  end
end

-- Single deterministic click handler: reads the real click position via
-- getmousepos() rather than relying on default cursor placement, and is
-- also bound to double/triple/quadruple-click so a fast click never falls
-- through to Vim's default word/line/block visual-mode selection.
local function handle_click()
  if not current then
    return
  end
  local mouse = vim.fn.getmousepos()
  if mouse.winid ~= current.winid then
    return
  end
  -- A click on/near the floating window's border can report a line outside
  -- the buffer's actual content (e.g. line 0), which nvim_win_set_cursor
  -- throws on ("Cursor position outside buffer") rather than clamping.
  local line_count = vim.api.nvim_buf_line_count(current.bufnr)
  if mouse.line < 1 or mouse.line > line_count then
    return
  end
  vim.api.nvim_win_set_cursor(current.winid, { mouse.line, 0 })
  switch_at_cursor()
end

local function rename_at_cursor()
  if not current then
    return
  end
  local line = vim.api.nvim_win_get_cursor(current.winid)[1]
  local target = current.line_to_tab[line]
  if target then
    M.rename(target)
  end
end

local function toggle_pin_at_cursor()
  if not current then
    return
  end
  local line = vim.api.nvim_win_get_cursor(current.winid)[1]
  local target = current.line_to_tab[line]
  if target then
    M.toggle_pin(target)
    M.refresh_open()
  end
end

local function close_at_cursor()
  if not current then
    return
  end
  local line = vim.api.nvim_win_get_cursor(current.winid)[1]
  local target = current.line_to_tab[line]
  if not target or not vim.api.nvim_tabpage_is_valid(target) then
    return
  end
  -- close_tab() closes the dropdown itself (via M.close()) if `target` is the
  -- tab it lives in, so `current` is correctly nil by the time refresh_open()
  -- runs in that case and it safely no-ops.
  if close_tab(target) then
    M.refresh_open()
  end
end

-- Rewrites the open dropdown's contents/size in place (e.g. after a
-- rename/pin) without closing it.
function M.refresh_open()
  if not current then
    return
  end
  local tabid = current.tabid
  local tabs = sorted_tabs()
  local lines = {}
  local current_line = nil
  current.line_to_tab = {}
  local width = 10
  for i, id in ipairs(tabs) do
    local icon = M.is_pinned(id) and PIN_ICON or "  "
    local text = " " .. icon .. M.get_name(id) .. " "
    lines[i] = text
    width = math.max(width, vim.fn.strdisplaywidth(text) + 2)
    current.line_to_tab[i] = id
    if id == tabid then
      current_line = i
    end
  end

  vim.bo[current.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(current.bufnr, 0, -1, false, lines)
  vim.bo[current.bufnr].modifiable = false

  vim.api.nvim_buf_clear_namespace(current.bufnr, NAMESPACE, 0, -1)
  if current_line then
    vim.api.nvim_buf_set_extmark(current.bufnr, NAMESPACE, current_line - 1, 0, {
      line_hl_group = "PmenuSel",
    })
  end

  local row, col = compute_geometry(width, #lines)
  vim.api.nvim_win_set_config(current.winid, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = #lines,
  })

  if current_line then
    pcall(vim.api.nvim_win_set_cursor, current.winid, { current_line, 0 })
  end
end

local function make_buf()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "floo-dropdown"
  vim.bo[bufnr].modifiable = false

  local opts = { buffer = bufnr, nowait = true, silent = true }
  vim.keymap.set("n", "<CR>", switch_at_cursor, opts)
  for _, lhs in ipairs({ "<LeftMouse>", "<2-LeftMouse>", "<3-LeftMouse>", "<4-LeftMouse>" }) do
    vim.keymap.set("n", lhs, handle_click, opts)
  end
  vim.keymap.set("n", "r", rename_at_cursor, opts)
  vim.keymap.set("n", "p", toggle_pin_at_cursor, opts)
  vim.keymap.set("n", "d", close_at_cursor, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)

  -- Cursor visibility follows focus, but the window itself stays open until
  -- an explicit close (select / <Esc> / toggle keystroke) — clicking into
  -- the editor or a file tree should not dismiss it.
  vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
    buffer = bufnr,
    callback = function()
      vim.o.guicursor = "a:FlooCursor"
    end,
  })
  vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
    buffer = bufnr,
    callback = function()
      vim.o.guicursor = DEFAULT_GUICURSOR
    end,
  })

  return bufnr
end

-- Opens the dropdown for the current tab (or, if one is already open,
-- closes it — the bound key acts as a toggle).
function M.open_dropdown()
  if current then
    M.close()
    return
  end

  local tabid = vim.api.nvim_get_current_tabpage()
  local origin_win = vim.api.nvim_get_current_win()
  local bufnr = make_buf()
  local row, col = compute_geometry(10, 1)
  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row = row,
    col = col,
    width = 10,
    height = 1,
    style = "minimal",
    border = config.dropdown.border or "rounded",
    zindex = 200,
    focusable = true,
  })
  vim.wo[winid].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"

  current = { tabid = tabid, winid = winid, bufnr = bufnr, origin_win = origin_win, line_to_tab = {} }
  M.refresh_open()
end

return M
