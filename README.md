# nvim-hoverfloat

Interactive LSP context window for Neovim with real-time hover information, references, and definitions.

![Demo](https://your-screenshot-link-if-you-have-one)

## Features

- 🔍 **Real-time LSP context** - Hover info, references, and definitions update as you move the cursor
- 🎮 **Interactive TUI** - Navigate with hjkl keys, toggle sections on/off  
- 🎨 **Beautiful styling** - Tokyo Night theme matching your Neovim setup
- ⚡ **High performance** - Built with Go and Bubble Tea for responsiveness
- 🔌 **Seamless integration** - Works with any LSP server supported by Neovim
- 📱 **Separate window** - Runs in dedicated terminal window, won't disrupt your workflow

## Installation

### Using lazy.nvim (Recommended)

```lua
{
  "star-lance/nvim-hoverfloat",
  build = "make install", -- Builds and installs the TUI binary
  config = function()
    require("hoverfloat").setup({
      -- Your configuration here (optional)
    })
  end,
}
```

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

- **Neovim 0.8+** with LSP support
- **Go 1.21+** (for building)
- **Terminal emulator** - kitty (default), or any terminal that supports spawning windows
- **LSP servers** - Any LSP server configured in Neovim

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
    binary_path = nil, -- Auto-detect or specify path
    window_title = "LSP Context",
    window_size = { width = 80, height = 25 },
    terminal_cmd = "kitty", -- Terminal to spawn TUI in
  },
  
  -- Communication settings
  communication = {
    socket_path = "/tmp/nvim_context.sock",
    timeout = 5000,
    retry_attempts = 3,
    update_delay = 150, -- Debounce delay in milliseconds
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

The plugin works best with **kitty** terminal. Example configurations are provided in the `examples/` directory:

- `examples/kitty_context.conf` - Kitty terminal configuration
- `examples/hyprland_rules.conf` - Hyprland window manager rules

### Custom Terminal

To use a different terminal:

```lua
require("hoverfloat").setup({
  tui = {
    terminal_cmd = "alacritty", -- or "wezterm", "gnome-terminal", etc.
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

**TUI binary not found:**
```bash
# Rebuild and reinstall
make clean && make install

# Or specify binary path manually
require("hoverfloat").set_binary_path("/path/to/nvim-context-tui")
```

**Socket connection issues:**
```bash
# Check if socket exists
ls -la /tmp/nvim_context.sock

# Restart the plugin
:ContextWindow restart
```

**LSP not working:**
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

- **Lua Plugin** - Integrates with Neovim, collects LSP data, manages TUI process
- **Go TUI** - Interactive terminal interface built with Bubble Tea
- **Unix Socket** - High-performance IPC between Lua and Go processes
- **Development Framework** - Mock client and testing tools for development

## Performance

- **Sub-100ms latency** for context updates
- **Efficient caching** of LSP responses to reduce server load  
- **Debounced updates** to prevent excessive requests
- **Minimal memory footprint** (~5MB typical usage)

## Supported LSP Features

- ✅ **textDocument/hover** - Documentation and type information
- ✅ **textDocument/definition** - Go to definition
- ✅ **textDocument/references** - Find all references  
- ✅ **textDocument/typeDefinition** - Go to type definition
- 🔄 **Diagnostics** (planned)
- 🔄 **Code actions** (planned)

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Bubble Tea](https://github.com/charmbracelet/bubbletea) - Excellent TUI framework
- [Lip Gloss](https://github.com/charmbracelet/lipgloss) - Beautiful terminal styling
- [Tokyo Night](https://github.com/folke/tokyonight.nvim) - Color scheme inspiration

## Related Projects

- [lspsaga.nvim](https://github.com/nvimdev/lspsaga.nvim) - LSP UI improvements
- [trouble.nvim](https://github.com/folke/trouble.nvim) - Pretty diagnostics list
- [aerial.nvim](https://github.com/stevearc/aerial.nvim) - Code outline window

---

**Star** ⭐ this repository if you find it useful!
