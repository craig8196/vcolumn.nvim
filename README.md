# vcolumn

Draw virtual column guides on whitespace and past the end of lines without
covering text. Tested with Neovim 0.11.6.

## Install

For [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "craig8196/vcolumn.nvim",
  opts = {
    cols = { 80, 100 },
  },
}
```

## Usage

With another plugin manager, install `craig8196/vcolumn.nvim` and call setup:

```lua
require("vcolumn").setup({
  cols = "80,100",       -- Or a list: { 80, 100 }
  char = "▏",            -- Guide character (default)
  priority = 1,          -- Extmark priority (default)
})
```

Columns are one-based. Signed strings are relative to a positive `textwidth`:
`cols = { "-10", "+0" }` draws at columns 70 and 80 when `textwidth` is 80.
The default column list is empty, so set `cols` to show guides.

The default highlight group is `vcolumn_hl`. The plugin clears `ColorColumn`
highlighting to replace the built-in column shading. To customize the guides:

```lua
vim.api.nvim_set_hl(0, "MyColumnGuide", { fg = "#555555" })
require("vcolumn").setup({
  cols = { 80 },
  highlight_group = "MyColumnGuide",
})
```

`highlight_group` also accepts a list. Highlights cycle by column-list position
from left to right, wrapping when there are more columns than highlights:

```lua
vim.api.nvim_set_hl(0, "GuideSoft", { fg = "#555555" })
vim.api.nvim_set_hl(0, "GuideHard", { fg = "#aa5555" })
require("vcolumn").setup({
  cols = { 80, 100, 120 },
  highlight_group = { "GuideSoft", "GuideHard" }, -- Soft, Hard, Soft
})
```

An empty highlight list uses the default `vcolumn_hl` group.

After setup, changing `colorcolumn` also updates the guides, for example
`:set colorcolumn=80,100`.

## Tests

Run from the project root:

```sh
lua test/range_tracker.test.lua
lua test/options.test.lua
nvim --headless -u NONE -i NONE -n -l test/highlights.test.lua
```
