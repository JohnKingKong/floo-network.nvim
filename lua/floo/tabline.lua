-- floo/tabline.lua
-- Bufferline integration hook showing the current fireplace's name -- not
-- wired automatically, same as buf_belongs_to_current_workspace, since
-- floo-network.nvim doesn't own bufferline's config. Wire it into your own
-- bufferline spec:
--   opts.options.custom_areas.left = function()
--     return require("floo.tabline").custom_area()
--   end
local M = {}

local PIN_ICON = "󰐃 "
local ICON = "🔥 "

function M.render()
  local floo = require("floo")
  local tabid = vim.api.nvim_get_current_tabpage()
  local icon = floo.is_pinned(tabid) and PIN_ICON or ICON
  return icon .. floo.get_name(tabid)
end

function M.custom_area()
  return { { text = M.render() } }
end

return M
