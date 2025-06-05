# nvim-hoverfloat

Live-updating LSP hover window in a floating panel for Neovim.

![screenshot](https://your-screenshot-link-if-you-have-one)

## Features

- Shows hover info from LSP in a dedicated floating window
- Always updates as you move the cursor
- Fully automatic, no keybinds required

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "star-lance/nvim-hoverfloat",
  config = function()
    require("hoverfloat").setup()
  end,
}
