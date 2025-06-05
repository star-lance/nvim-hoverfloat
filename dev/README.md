# Neovim Plugin Development Framework

This development framework allows you to test and iterate on the Neovim plugin without using Neovim itself, preventing disruption to your coding environment.

## Quick Start

1. **Build everything:**
   ```bash
   ./dev/scripts/build.sh
   ```

2. **Run interactive test session:**
   ```bash
   ./dev/scripts/interactive-test.sh
   ```

3. **Clean up when done:**
   ```bash
   ./dev/scripts/clean.sh
   ```

## Components

### Mock Neovim Client (`dev/mock-nvim-client/`)
Simulates the Neovim Lua plugin by sending realistic LSP data over Unix sockets.

**Usage:**
```bash
# Interactive mode - menu-driven scenario selection
./dev/bin/mock-nvim-client interactive

# Run specific scenario
./dev/bin/mock-nvim-client scenario typescript_interface

# Continuous cycling through scenarios
./dev/bin/mock-nvim-client continuous

# Send one test and exit
./dev/bin/mock-nvim-client single
```

### Context TUI (`dev/context-tui/`)
Your Bubble Tea TUI implementation that receives and displays LSP data.

### Test Data (`dev/mock-nvim-client/scenarios.json`)
Realistic test scenarios including:
- Complex TypeScript interfaces
- Rust generic functions with trait bounds
- Python methods with extensive docstrings
- Edge cases (empty data, errors, minimal info)
- Large reference lists
- Deeply nested types

## Development Workflows

### 1. TUI Development
Test the TUI independently without Neovim:
```bash
# Start TUI
./dev/scripts/test-tui.sh

# In another terminal, send test data
./dev/scripts/send-test-data.sh typescript_interface
```

### 2. Full Pipeline Testing
Test complete communication pipeline:
```bash
./dev/scripts/test-full-pipeline.sh
```

### 3. Auto-rebuild on Changes
Automatically rebuild when Go files change:
```bash
./dev/scripts/watch-and-rebuild.sh
```

### 4. Interactive Testing
Menu-driven testing session:
```bash
./dev/scripts/interactive-test.sh
```

## File Structure
```
dev/
├── mock-nvim-client/           # Mock LSP data sender
│   ├── main.go                # Client implementation
│   ├── scenarios.json         # Test scenarios
│   └── go.mod                 # Go module
├── context-tui/               # Bubble Tea TUI (to be created)
│   ├── main.go
│   ├── models/
│   ├── components/
│   └── go.mod
├── scripts/                   # Development automation
│   ├── build.sh              # Build all components
│   ├── test-tui.sh           # Test TUI with mock data
│   ├── test-full-pipeline.sh # End-to-end testing
│   ├── send-test-data.sh     # Quick data sender
│   ├── clean.sh              # Cleanup processes
│   ├── watch-and-rebuild.sh  # Auto-rebuild
│   └── interactive-test.sh   # Interactive session
├── bin/                      # Built binaries (created by build.sh)
│   ├── mock-nvim-client
│   └── context-tui
└── README.md                 # This file
```

## Extending Test Scenarios

Add new scenarios to `scenarios.json`:
```json
{
  "name": "your_scenario",
  "description": "Description of the test case",
  "delay_ms": 500,
  "data": {
    "file": "src/example.rs",
    "line": 42,
    "col": 15,
    "hover": ["Documentation lines..."],
    "definition": {"file": "...", "line": 10, "col": 4},
    "references_count": 5,
    "references": [...]
  }
}
```

## Socket Communication

The framework uses Unix domain sockets at `/tmp/nvim_context.sock` with JSON messages:

```json
{
  "type": "context_update",
  "timestamp": 1704067200000,
  "data": {
    "file": "src/main.rs",
    "line": 42,
    "hover": ["..."],
    "definition": {"file": "...", "line": 10, "col": 4},
    "references": [...],
    "references_count": 5
  }
}
```

## Troubleshooting

### Socket Issues
```bash
# Check if socket exists
ls -la /tmp/nvim_context.sock

# Remove stale socket
rm -f /tmp/nvim_context.sock
```

### Process Management
```bash
# List relevant processes
ps aux | grep -E "(context-tui|mock-nvim-client)"

# Kill all related processes
./dev/scripts/clean.sh
```

### Build Issues
```bash
# Clean build
rm -rf dev/bin/
./dev/scripts/build.sh
```

## Next Steps

1. **Create the Bubble Tea TUI** in `dev/context-tui/`
2. **Test menu navigation** with hjkl keys
3. **Implement field toggling** (hover, references, definitions)
4. **Add styling** with Lip Gloss
5. **Performance testing** with large datasets

This framework allows rapid iteration without disrupting your main development environment!
