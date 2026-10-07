-- floo/tabline.lua
-- Bufferline integration hook showing the current fireplace's name -- not
-- wired automatically, same as buf_belongs_to_current_workspace, since
-- floo-network.nvim doesn't own bufferline's config. Wire it into your own
-- bufferline spec:
--   opts.options.custom_areas.left = function()
--     return require("floo.tabline").custom_area()
--   end
--
-- M.render() itself is engine-agnostic (a bare function returning a plain
-- string), so it also drops straight into NvChad's tabufline, which has the
-- same kind of extension point under a different name -- opts.modules (a
-- table of plain no-arg functions merged into its built-ins) plus opts.order
-- (where they render), instead of bufferline's custom_areas. Wire it into
-- your chadrc.lua. Wrap it, don't pass render directly: chadrc.lua's table
-- is built eagerly at require() time, before lazy.nvim has loaded a
-- VeryLazy-triggered plugin like this one on a fresh install.
--   M.ui = {
--     tabufline = {
--       modules = { floo_name = function() return require("floo.tabline").render() end },
--       order = { "treeOffset", "floo_name", "buffers", "tabs", "btns" },
--     },
--   }
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
