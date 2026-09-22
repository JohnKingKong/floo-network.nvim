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

Inside the dropdown: `<CR>` or click a line to switch, `r` to rename, `p`
to pin/unpin, `d` to close (confirms if pinned), `<Esc>` to close the
dropdown.

## License

MIT
