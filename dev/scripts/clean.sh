#!/bin/bash
# dev/scripts/clean.sh - Clean up processes and sockets (updated)

echo "🧹 Cleaning up development environment..."

# Kill any running TUI processes (both dev and production)
pkill -f "context-tui" 2>/dev/null || true
pkill -f "context-tui-dev" 2>/dev/null || true
pkill -f "mock-nvim-client" 2>/dev/null || true
pkill -f "nvim-context-tui" 2>/dev/null || true

# Remove socket files
rm -f /tmp/nvim_context.sock
rm -f /tmp/test_context.sock

# Kill any kitty instances with our titles
pkill -f "LSP Context" 2>/dev/null || true

# Kill any orphaned Go processes
pgrep -f "nvim-context-tui" | xargs -r kill 2>/dev/null || true

# Clean up any test artifacts
rm -f test_output.log
rm -f debug.log

echo "✅ Cleanup complete!"
