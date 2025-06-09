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
for transparency, I have not actually tested any of these except for Lazy
because I am lazy. If you use one of the below package managers and it does
not work correctly, please either let me know and I will get off may ass
and spend the 10 minutes it will take to install another plugin manager and
fix it, or submit a PR. I will approve pretty much anything that's not malware
if it fixes a bug, although I might revisit it later and change some elements.

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

- Neovim 0.8+ with LSP support (I use Mason to manage my LSPs)
- Go 1.21+
- Terminal emulator - kitty is default, but config settings are coming
- LSP server - Must assosciate filetypes with the LSP you want to communicate
    with the plugin window

## Usage

### Basic Usage

Once installed, the floating window automatically shows context information
as you move your cursor over different tokens. NVIM commands:

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

### Interactive Controls

When the TUI is active:

| Key | Action |
|-----|--------|
| `hjkl` | Navigate between sections |
| `enter` / `space` | Toggle current section on/off |
| `H` | Toggle hover documentation |
| `R` | Toggle references |
| `D` | Toggle definition |
| `T` | Toggle type information |
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

The plugin works best with kitty terminal. Configuration files are provided in the `config/` directory.

### Custom Terminal

To use a different terminal:

```lua
require("hoverfloat").setup({
  tui = {
    terminal_cmd = "alacritty",
  }
})
```

<details>
<summary><strong>Advanced Configuration Files</strong></summary>

The plugin includes several configuration files in the `config/` directory for advanced customization:

#### Kitty Terminal Configuration (`config/kitty_context.conf`)

Optimized terminal settings for the LSP context window:

```bash
# Use with: kitty --config=config/kitty_context.conf -e nvim-context-tui
font_family      JetBrains Mono
font_size        11.0
initial_window_width  80c
initial_window_height 25c
background            #1a1b26
foreground            #c0caf5
# ... additional color and performance settings
```

Key features:
- Tokyo Night color scheme matching Neovim
- Optimized font rendering with JetBrains Mono
- Disabled unnecessary features for better performance
- Proper window sizing and positioning

#### Hyprland Window Manager Rules (`config/hyprland_rules.conf`)

Window management rules for Hyprland users:

```bash
# Add to ~/.config/hypr/hyprland.conf
windowrule = float, ^(lsp-context)$
windowrule = pin, ^(lsp-context)$
windowrule = size 640 600, ^(lsp-context)$
windowrule = move 1280 100, ^(lsp-context)$
```

Features:
- Floating window behavior
- Automatic positioning and sizing
- Multi-monitor support
- Special workspace integration
- Focus management to avoid interrupting coding

#### TUI Appearance Configuration (`config/aesthetics.conf`)

Advanced styling and theming options:

```ini
[colors.background]
primary    = "#020617"    # Main TUI background
secondary  = "#0f172a"    # Section backgrounds
accent     = "#64748b"    # Header/footer backgrounds

[colors.accent]
blue   = "#7aa2f7"       # Headers, titles
green  = "#9ece6a"       # Success states
yellow = "#e0af68"       # Warnings, emphasis

[formatting.sections]
consistent_backgrounds = true
full_width_backgrounds = true
border_style = "bottom_only"

[markdown]
use_glamour = true
theme = "dark"
code_highlighting = true
```

Configuration sections:
- **Colors**: Background, foreground, accent, and semantic colors
- **Formatting**: Text styles, section layouts, code highlighting
- **Layout**: Spacing, dimensions, and positioning
- **Markdown**: Rendering options for documentation
- **Accessibility**: High contrast and focus indicators
- **Debug**: Development and troubleshooting options

#### Usage

To use these configurations:

1. **Kitty**: Reference the config when starting the context window
2. **Hyprland**: Include rules in your Hyprland configuration
3. **Aesthetics**: The TUI automatically loads styling from `config/aesthetics.conf`

</details>

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
