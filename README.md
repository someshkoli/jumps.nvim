> **Disclaimer**: This plugin was AI-generated and vibe-coded for personal usage. Use at your own risk.

A Neovim plugin for filtered navigation through your cross-file jumplist. Only shows jumps to different files within your current root directory.

## Features

- Root directory filtering (only shows jumps within `getcwd()`)
- Cross-file only (filters out same-file jumps)
- Telescope picker interface
- Backward/forward navigation through filtered jump history

## Requirements

- Neovim >= 0.7.0
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'someshkoli/jumps.nvim',
  dependencies = { 'nvim-telescope/telescope.nvim' },
  config = function()
    require('jumps').setup({
      keymap = '<leader>fj',         -- Open jump picker
      keymap_back = '<A-o>',     -- Jump backward
      keymap_forward = '<A-i>',  -- Jump forward
    })
  end
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'someshkoli/jumps.nvim',
  requires = { 'nvim-telescope/telescope.nvim' },
  config = function()
    require('jumps').setup({
      keymap = '<leader>fj',
      keymap_back = '<A-o>',     -- Jump backward
      keymap_forward = '<A-i>',  -- Jump forward
    })
  end
}
```

## Configuration

All keymaps are `nil` by default:

```lua
require('jumps').setup({
  keymap = '<leader>fj',         -- Open Telescope picker (optional)
  keymap_back = '<leader>o',     -- Jump backward (optional)
  keymap_forward = '<leader>i',  -- Jump forward (optional)

  telescope = {                   -- Telescope options (optional)
    layout_strategy = 'horizontal',
    layout_config = {
      width = 0.9,
      height = 0.9,
    },
  },
})
```

## Usage

### Commands

```vim
:Jumps          " Open the cross-file jumplist picker
:JumpsBack      " Jump backward in filtered history
:JumpsForward   " Jump forward in filtered history
:JumpsDebug     " Debug jumplist filtering
```

### Keymaps

Set keymaps in your configuration, then use them to navigate through your filtered jump history.

## License

Apache License 2.0
# jumps.nvim
