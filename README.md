# floo-network.nvim

Fireplace tabs for Neovim: each tab is an independent fireplace scoped to
its own directory, with a dropdown switcher, rename, and pin. Pin a
fireplace and it survives closing other tabs, asks for confirmation before
you close it, and — uniquely — survives quitting Neovim entirely.

## Why "floo"?

In the Harry Potter books, the **Floo Network** connects fireplaces across
the wizarding world — you step into one, call out a destination by name,
and arrive instantly. Some fireplaces are permanently connected to the
Network; others are used for a single, one-off trip.

Each Neovim tab is a fireplace here:

- **Switching fireplaces** = flooing to a named destination
- **Pinning a fireplace** = permanently connecting it to the Network —
  reachable forever, survives a restart
- **An unpinned fireplace** = a one-off connection — useful for the
  session, gone once you quit

## Installation (lazy.nvim)

```lua
{
  "JohnKingKong/floo-network.nvim",
  event = "VeryLazy",
  opts = {},
}
```

Or with explicit config:

```lua
{
  "JohnKingKong/floo-network.nvim",
  event = "VeryLazy",
  opts = {
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
  },
}
```

Any key in `keys` can be set to `false` or left `nil` to disable that
specific binding without affecting the others.

## Optional integrations

- **neo-tree.nvim**: if installed, creating a fireplace auto-opens
  neo-tree scoped to its directory, `keys.explorer` opens the tree
  re-rooted to the current fireplace, and session restore reopens each
  restored fireplace's tree. Not required — everything else works without
  it. Set `neo_tree.enabled = false` to opt out of all of the above even
  if neo-tree.nvim is installed.
- **bufferline.nvim**: not wired automatically (floo-network.nvim doesn't own your
  bufferline config). To scope the buffer bar to the current fireplace,
  and show the current fireplace's name (with a pin icon when pinned) in
  the tabline itself, add this to your own bufferline spec:

  ```lua
  opts = {
    options = {
      custom_filter = function(bufnr)
        return require("floo").buf_belongs_to_current_workspace(bufnr)
      end,
      custom_areas = {
        left = function()
          return require("floo.tabline").custom_area()
        end,
      },
    },
  }
  ```

- **NvChad's tabufline**: `floo.tabline`'s `render()` is a bare no-arg
  function returning a plain string, the exact shape tabufline's own
  `modules` extension point expects — no separate adapter needed, just
  wire it into your `chadrc.lua` (wrapped, not passed directly: chadrc.lua's
  table is built eagerly at `require()` time, before lazy.nvim has loaded a
  `VeryLazy`-triggered plugin like this one on a fresh install):

  ```lua
  M.ui = {
    tabufline = {
      modules = { floo_name = function() return require("floo.tabline").render() end },
      order = { "treeOffset", "floo_name", "buffers", "tabs", "btns" },
    },
  }
  ```

  Scoping buffers to the current fireplace (the `custom_filter` equivalent
  above) isn't available for tabufline — it renders every buffer in
  `vim.t.bufs` directly rather than going through a filterable buffer list.

## Files opened from outside Neovim

Some external tools (lazygit's `nvim-remote` editor preset — what
[`snacks.nvim`'s lazygit integration](https://github.com/folke/snacks.nvim)
auto-configures when you press `e` there to edit a file — and anything else
using Neovim's own `--remote-tab`) always open a file in a brand-new tab via
RPC, with no option to reuse an existing one. Left alone, that produces
exactly the kind of mess fireplaces are meant to prevent: a file from a
project you already have open as a fireplace spawns an untracked duplicate
tab instead of landing in that fireplace, and its displayed name falls back
to whatever Neovim's global cwd happened to be at startup — not the file's
actual directory.

floo-network detects this (any new, unregistered tab that ends up showing a
real file) and handles it automatically: if the file belongs to an existing
fireplace, it's redirected there and the duplicate tab closes; otherwise the
new tab is registered as its own fireplace, named from the nearest `.git`
root (or the file's own directory if none is found) — the same as
`new_workspace()` does, just triggered automatically instead of only via the
explicit keymap.

### Opting another plugin's own tab out of this

If you maintain a plugin that deliberately opens its own tab as part of its
own UI (e.g. a review/diff view), set this tab-local variable right after
creating it so floo-network leaves it alone entirely — without it, such a
tab looks identical to one opened by an external tool, so it'd get silently
redirected into an existing fireplace and closed, taking your plugin's own
setup for that tab down with it:

```lua
vim.api.nvim_tabpage_set_var(vim.api.nvim_get_current_tabpage(), "floo_ignore_external_tab", true)
```

No dependency on floo-network needed — this is just a generic Neovim API
call, inert if floo-network isn't installed.

## Quit protection

`:q`/`:quit` and `:qa`/`:qall`/`:quitall` (including their `!` forms —
`!` only means "discard unsaved changes", a different concern from
"don't silently lose a pinned workspace") confirm first whenever they
would close a pinned fireplace: `:q` when it's about to close that
fireplace's last window, `:qa`/`:quitall` when any fireplace is pinned.
Vim's own unsaved-changes prompt is unrelated to this — a pinned
fireplace with every buffer saved would otherwise close with no warning
at all.

## Keymaps

| Key (default) | Action |
|---|---|
| `<leader><tab>w` | New fireplace (prompts for a folder) |
| `<leader><tab>n` | Rename the current fireplace |
| `<leader><tab>p` | Toggle pin on the current fireplace |
| `<leader><tab>s` | Open/close the fireplace dropdown |
| `<leader><tab>d` | Close the current fireplace (confirms if pinned) |
| `<leader><tab>o` | Close every other fireplace (confirms first for any pinned ones) |
| `<leader>bb` | Switch to another buffer open in this fireplace only |
| `<leader>e` | Open the file explorer scoped to this fireplace (requires neo-tree.nvim) |

Inside the dropdown: `<CR>` or click a line to switch, a number key (`1`-`9`)
to jump straight to that line, `r` to rename, `p` to pin/unpin, `d` to close
(confirms if pinned), `<Esc>` to close the dropdown.

## License

MIT
