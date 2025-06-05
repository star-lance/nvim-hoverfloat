# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial release of nvim-hoverfloat
- Interactive TUI with Bubble Tea framework
- Real-time LSP context updates
- hjkl navigation support
- Toggleable sections (hover, references, definitions, type info)
- Tokyo Night theme integration
- Unix socket communication between Neovim and TUI
- Comprehensive development framework with mock client
- Support for multiple terminal emulators
- Health check functionality
- Performance optimizations with caching
- Multi-platform build support (Linux, macOS, Windows)

### Features

#### Core Functionality
- **Real-time LSP context** - Display hover information, references, and definitions as you move cursor
- **Interactive navigation** - Navigate between sections with hjkl keys
- **Section toggling** - Show/hide different types of LSP information dynamically
- **Beautiful styling** - Tokyo Night theme matching Neovim aesthetics
- **High performance** - Sub-100ms latency for context updates

#### TUI Interface
- **Bubble Tea framework** - Modern, efficient terminal UI
- **Responsive design** - Adapts to different terminal sizes
- **Keyboard controls** - Full keyboard navigation without mouse dependency
- **Help system** - Built-in help menu with F1 or ?
- **Status indicators** - Connection status and last update timestamps

#### LSP Integration
- **textDocument/hover** - Documentation and type information
- **textDocument/definition** - Go to definition location
- **textDocument/references** - Find all references with count
- **textDocument/typeDefinition** - Type definition location
- **Smart caching** - Reduces LSP server load with intelligent caching
- **Error handling** - Graceful handling of LSP timeouts and errors

#### Development Experience
- **Comprehensive dev framework** - Test without disrupting your Neovim setup
- **Mock LSP client** - Realistic test scenarios for development
- **Hot reloading** - Automatic rebuilds during development
- **Performance benchmarking** - Built-in performance testing
- **Health checks** - Diagnostic tools for troubleshooting

#### Configuration
- **Flexible terminal support** - Works with kitty, alacritty, wezterm, and more
- **Window management** - Hyprland rules and terminal configurations
- **Customizable behavior** - Debounce delays, update frequency, display limits
- **Auto-start options** - Automatic startup and error recovery

### Technical Implementation

#### Architecture
- **Go TUI process** - Separate high-performance TUI written in Go
- **Lua Neovim plugin** - Lightweight integration with Neovim LSP
- **Unix socket IPC** - Efficient communication between processes
- **Modular design** - Clean separation of concerns

#### Performance
- **Efficient rendering** - Optimized Bubble Tea components
- **Smart updates** - Debounced cursor movement detection
- **Memory optimization** - Bounded cache sizes and cleanup
- **Resource management** - Proper cleanup and error recovery

#### Development Tools
- **Mock client** - Simulates Neovim plugin for testing
- **Test scenarios** - Realistic LSP data for different languages
- **Build system** - Comprehensive Makefile with multiple targets
- **CI/CD pipeline** - Automated testing and releases

### Documentation
- **Comprehensive README** - Installation, usage, and configuration
- **Help documentation** - Built-in Neovim help with `:help nvim-hoverfloat`
- **Example configurations** - Kitty terminal and Hyprland window manager
- **API documentation** - Complete Lua API reference
- **Troubleshooting guide** - Common issues and solutions

### Quality Assurance
- **Unit tests** - Core functionality testing
- **Integration tests** - End-to-end pipeline testing
- **Linting** - Go and Lua code quality checks
- **Security scanning** - Automated security vulnerability detection
- **Performance monitoring** - Benchmark tracking

## [1.0.0] - 2024-12-XX

### Added
- Initial stable release
- All core features implemented and tested
- Production-ready build system
- Comprehensive documentation
- Multi-platform support

## Development Milestones

### Phase 1: Core Implementation ✅
- [x] Go TUI with Bubble Tea
- [x] Basic socket communication
- [x] Lua plugin integration
- [x] Simple display of LSP data

### Phase 2: Interactive Features ✅
- [x] hjkl navigation
- [x] Section toggling
- [x] Help menu system
- [x] Status indicators

### Phase 3: Polish & Performance ✅
- [x] Tokyo Night styling
- [x] Performance optimizations
- [x] Error handling
- [x] Health checks

### Phase 4: Development Framework ✅
- [x] Mock client for testing
- [x] Development scripts
- [x] Build system
- [x] CI/CD pipeline

### Phase 5: Documentation & Release ✅
- [x] Comprehensive documentation
- [x] Example configurations
- [x] Installation guides
- [x] API reference

## Future Roadmap

### Planned Features
- [ ] **Diagnostics display** - Show LSP diagnostics in context window
- [ ] **Code actions** - Quick access to available code actions
- [ ] **Symbol outline** - Document structure overview
- [ ] **Call hierarchy** - Function call relationships
- [ ] **Workspace symbols** - Project-wide symbol search

### Enhancements
- [ ] **Multiple themes** - Additional color schemes beyond Tokyo Night
- [ ] **Layout options** - Different arrangements of information sections
- [ ] **Plugin ecosystem** - Support for third-party extensions
- [ ] **Performance profiling** - Built-in performance monitoring
- [ ] **Remote LSP support** - Work with remote language servers

### Platform Support
- [ ] **Windows improvements** - Better Windows terminal support
- [ ] **WSL optimization** - Enhanced WSL integration
- [ ] **SSH workflows** - Remote development support
- [ ] **Container support** - Docker development environments

## Contributing

We welcome contributions! Please see our contributing guidelines for:

- Code style and standards
- Testing requirements
- Documentation updates
- Bug reports and feature requests

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

Special thanks to:
- **Charm.sh team** for the excellent Bubble Tea framework
- **Neovim community** for the robust LSP implementation  
- **Tokyo Night theme** creators for the beautiful color scheme
- **Go community** for the powerful standard library
- **All contributors** who help make this project better

---

For more detailed information about any release, please see the corresponding [GitHub releases](https://github.com/star-lance/nvim-hoverfloat/releases) page.
