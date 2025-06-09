# nvim-hoverfloat

## Features

Real-time LSP context - Hover info, references, and definitions update as you move the cursor
- Interactive TUI - Navigate with hjkl keys, toggle sections on/off
- High performance - Built for performance with go
- Seamless integration - Works with any LSP server that can integrate with Neovim
- Separate window - dedicated terminal window with configurable launch parameters
## Installation

### Using lazy.nvim (Recommended)

```lua
{
  "star-lance/nvim-hoverfloat",
  build = "make install",
  config = function()
    require("hoverfloat").setup({
      -- Your configuration here
    })
  end,
}

```
for transparency, I have not actually tested any of these except for Lazy because I am lazy. If you use one of the below package managers and it does not work correctly, please either let me know and I will get off may ass and spend the 10 minutes it will take to install another plugin manager and fix it, or submit a PR. I will approve pretty much anything that's not malware if it fixes a bug, although I might revisit it later and change some elements.

### Using packer.nvim

```lua
use {
  'star-lance/nvim-hoverfloat',
  run = 'make install',
  config = function()
    require("hoverfloat").setup()
  end
}
```

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/star-lance/nvim-hoverfloat.git
   cd nvim-hoverfloat
   ```

2. Build and install the TUI binary:
   ```bash
   make install
   ```

3. Add to your Neovim configuration:
   ```lua
   require("hoverfloat").setup()
   ```

## Requirements

- Neovim 0.8+ with LSP support
- Go 1.21+ (for building)
- Terminal emulator - kitty (default), or any terminal that supports spawning windows
- LSP servers - Any LSP server configured in Neovim

## Usage

### Basic Usage

Once installed, the plugin automatically shows context information as you move your cursor:

```vim
:ContextWindow toggle    " Toggle the context window
:ContextWindow open      " Open the context window  
:ContextWindow close     " Close the context window
:ContextWindow restart   " Restart the context window
:ContextWindow status    " Show status information
```

### Key Bindings (Default)

| Key | Action |
|-----|--------|
| `<leader>ct` | Toggle context window |
| `<leader>co` | Open context window |
| `<leader>cc` | Close context window |
| `<leader>cr` | Restart context window |
| `<leader>cs` | Show status |

### Interactive TUI Controls

When the TUI is active:

| Key | Action |
|-----|--------|
| `hjkl` | Navigate between sections |
| `enter` / `space` | Toggle current section on/off |
| `H` | Toggle hover documentation |
| `R` | Toggle references |
| `D` | Toggle definition |
| `T` | Toggle type information |
| `?` / `F1` | Show help menu |
| `q` / `Ctrl+C` | Quit |

## Configuration

### Default Configuration

```lua
require("hoverfloat").setup({
  -- TUI settings
  tui = {
    binary_name = "nvim-context-tui",
    binary_path = nil,
    window_title = "LSP Context",
    window_size = { width = 80, height = 25 },
    terminal_cmd = "kitty",
  },
 
  -- Communication settings
  communication = {
    socket_path = "/tmp/nvim_context.sock",
    timeout = 5000,
    retry_attempts = 3,
    update_delay = 150,
  },
 
  -- LSP feature toggles
  features = {
    show_hover = true,
    show_references = true,
    show_definition = true,
    show_type_info = true,
    max_hover_lines = 15,
    max_references = 8,
  },
 
  -- Cursor tracking settings
  tracking = {
    excluded_filetypes = { "help", "qf", "netrw", "fugitive", "TelescopePrompt" },
    min_cursor_movement = 3, -- Minimum column movement to trigger update
  },
 
  -- Auto-start settings
  auto_start = true,
  auto_restart_on_error = true,
})
```

### Terminal Configuration

The plugin works best with kitty terminal. Example configurations are provided in the `examples/` directory:

- `examples/kitty_context.conf` - Kitty terminal configuration
- `examples/hyprland_rules.conf` - Hyprland window manager rules

### Custom Terminal

To use a different terminal:

```lua
require("hoverfloat").setup({
  tui = {
    terminal_cmd = "alacritty",
  }
})
```

## Development

### Building from Source

```bash
# Clone the repository
git clone https://github.com/star-lance/nvim-hoverfloat.git
cd nvim-hoverfloat

# Install dependencies
make deps

# Build the TUI binary
make build

# Run tests
make test

# Install locally
make install
```

### Development Framework

The plugin includes a comprehensive development framework for testing without disrupting your Neovim setup:

```bash
# Start interactive development session
make dev

# Run development tests
make dev-test

# Build development tools
make dev-build
```

### Contributing

1. Fork the repository
2. Create your feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes
4. Run tests: `make test`
5. Commit your changes: `git commit -m 'Add amazing feature'`
6. Push to the branch: `git push origin feature/amazing-feature`
7. Open a Pull Request

## Troubleshooting

### Health Check

Run the health check to diagnose issues:

```vim
:checkhealth nvim-hoverfloat
```

### Common Issues

TUI binary not found:
```bash
# Rebuild and reinstall
make clean && make install

# Or specify binary path manually
require("hoverfloat").set_binary_path("/path/to/nvim-context-tui")
```

Socket connection issues:
```bash
# Check if socket exists
ls -la /tmp/nvim_context.sock

# Restart the plugin
:ContextWindow restart
```

LSP not working:
```vim
# Check LSP status
:LspInfo

# Ensure LSP is attached to current buffer
:lua print(#vim.lsp.get_clients({ bufnr = 0 }))
```

### Debug Mode

Enable debug mode for verbose logging:

```lua
require("hoverfloat").setup({
  communication = {
    debug = true, -- Enable debug logging
  }
})
```

## Architecture

```
┌─────────────────┐    Unix Socket    ┌─────────────────┐
│   Neovim Plugin │◄──────────────────►│  Go TUI Process │
│   (Lua)         │   JSON Messages   │  (Bubble Tea)   │
└─────────────────┘                   └─────────────────┘
         ▲                                       ▲
         │                                       │
         ▼                                       ▼
┌─────────────────┐                   ┌─────────────────┐
│  LSP Servers    │                   │ Terminal Window │
│  (rust-analyzer,│                   │ (kitty, etc.)   │
│   gopls, etc.)  │                   │                 │
└─────────────────┘                   └─────────────────┘
```

### Components

- Lua Plugin - Integrates with Neovim, collects LSP data, manages TUI process
- Go TUI - Interactive terminal interface built with Bubble Tea
- Unix Socket - High-performance IPC between Lua and Go processes
- Development Framework - Mock client and testing tools for development

## Performance

- under 1ms latency for context updates
- Efficient caching of LSP responses to reduce server load  
- Debouncing to improve performance
- Minimal memory footprint (~5MB typical usage)

## License

MIT License - [LICENSE](LICENSE)

## Stack

- [Bubble Tea](https://github.com/charmbracelet/bubbletea) - Excellent TUI framework
- [Lip Gloss](https://github.com/charmbracelet/lipgloss) - Beautiful terminal styling
---
