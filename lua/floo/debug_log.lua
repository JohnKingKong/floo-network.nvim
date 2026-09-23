-- floo/debug_log.lua
-- TEMPORARY: shared diagnostic logging while chasing intermittent floo
-- bugs -- the earlier "Invalid buffer id: 1" startup race, and now pinned
-- fireplaces occasionally disappearing during long-running Neovide
-- sessions with no clear trigger yet. Safe to remove once these are
-- confirmed fixed or ruled out -- not meant to be permanent.
local M = {}

local LOG_FILE = vim.fn.stdpath("state") .. "/floo_debug.log"

function M.log(msg)
  local fd = io.open(LOG_FILE, "a")
  if fd then
    -- hrtime (monotonic nanoseconds) alongside wall-clock time so log
    -- lines within the same second can still be ordered precisely.
    fd:write(string.format("[%s %d] %s\n", os.date("%H:%M:%S"), vim.loop.hrtime(), msg))
    fd:close()
  end
end

return M
