# floo-network.nvim

Workspace tabs for Neovim: each tab is an independent workspace scoped to
its own directory, with a dropdown switcher, rename, and pin. Pin a
workspace and it survives closing other tabs, asks for confirmation before
you close it, and — uniquely — survives quitting Neovim entirely.

## Why "floo"?

In the Harry Potter books, the **Floo Network** connects fireplaces across
the wizarding world — you step into one, call out a destination by name,
and arrive instantly. Some fireplaces are permanently connected to the
Network; others are used for a single, one-off trip.

That's exactly the model here:

- **Switching workspaces** = flooing to a named destination
- **Renaming a workspace** = naming the fireplace
- **Pinning a workspace** = a fireplace permanently connected to the
  Network — reachable forever, survives a restart
- **An unpinned workspace** = a one-off connection — useful for the
  session, gone once you quit

## Installation (lazy.nvim)

```lua
{
  "your-github-username/floo-network.nvim",
  event = "VeryLazy",
  opts = {},
}
```

Or with explicit config:

```lua
{
  "your-github-username/floo-network.nvim",
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

- **neo-tree.nvim**: if installed, creating a workspace auto-opens
  neo-tree scoped to its directory, `keys.explorer` opens the tree
  re-rooted to the current workspace, and session restore reopens each
  pinned workspace's tree. Not required — everything else works without it.
- **bufferline.nvim**: not wired automatically (floo-network.nvim doesn't own your
  bufferline config). To scope the buffer bar to the current workspace,
  add this to your own bufferline spec:

  ```lua
  opts = {
    options = {
      custom_filter = function(bufnr)
        return require("floo").buf_belongs_to_current_workspace(bufnr)
      end,
    },
  }
  ```

## Keymaps

| Key (default) | Action |
|---|---|
| `<leader><tab>w` | New workspace (prompts for a folder) |
| `<leader><tab>n` | Rename the current workspace |
| `<leader><tab>p` | Toggle pin on the current workspace |
| `<leader><tab>s` | Open/close the workspace dropdown |
| `<leader><tab>d` | Close the current workspace (confirms if pinned) |
| `<leader><tab>o` | Close every workspace except the current and any pinned ones |
| `<leader>bb` | Switch to another buffer open in this workspace only |
| `<leader>e` | Open the file explorer scoped to this workspace (requires neo-tree.nvim) |

Inside the dropdown: `<CR>` or click a line to switch, `r` to rename, `p`
to pin/unpin, `<Esc>` to close.

## License

MIT
