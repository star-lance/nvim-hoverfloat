#!/bin/bash
# dev/scripts/clean.sh - Clean up processes and sockets

echo "🧹 Cleaning up development environment..."

# Kill any running TUI processes
pkill -f "context-tui" 2>/dev/null || true
pkill -f "mock-nvim-client" 2>/dev/null || true

# Remove socket files
rm -f /tmp/nvim_context.sock

# Kill any kitty instances with our titles
pkill -f "LSP Context" 2>/dev/null || true

echo "✅ Cleanup complete!"
