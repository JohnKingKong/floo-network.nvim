-- floo/config.lua
-- Default configuration and the merge used by setup(). See README.md for
-- what each option does and why pin means what it means.
local M = {}

M.defaults = {
  keys = {
    new = "<leader><tab>w",
    rename = "<leader><tab>n",
    pin = "<leader><tab>p",
    switch = "<leader><tab>s",
    close = "<leader><tab>d",
    close_others = "<leader><tab>o",
    switch_buffer = "<leader>bb",
    explorer = "<leader>e",
  },
  dropdown = {
    position = "top-right", -- "top-right" | "top-left" | "bottom-right" | "bottom-left"
    border = "rounded",
  },
  session = {
    enabled = true,
    persist = "pinned", -- "pinned" | "all" | false
  },
  neo_tree = {
    enabled = true,
  },
}

function M.merge(opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
