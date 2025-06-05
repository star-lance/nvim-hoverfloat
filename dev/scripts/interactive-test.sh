#!/bin/bash
# dev/scripts/interactive-test.sh - Interactive testing session

set -e

echo "🎮 Interactive Testing Session"
echo "============================="

# Build everything
./dev/scripts/build.sh

# Clean up
./dev/scripts/clean.sh

echo ""
echo "Starting components..."

# Start TUI
echo "📺 Starting TUI..."
kitty --title="LSP Context TUI - Interactive" --hold -e ./dev/bin/context-tui &
TUI_PID=$!

sleep 3

# Check if TUI started
if [ ! -S "/tmp/nvim_context.sock" ]; then
    echo "❌ TUI failed to start"
    exit 1
fi

echo "✅ TUI started (PID: $TUI_PID)"
echo ""

# Start interactive client
echo "🎯 Starting interactive mock client..."
echo "   Use this to send different scenarios to the TUI"
echo ""

# Run the interactive client
./dev/bin/mock-nvim-client interactive

echo ""
echo "🧹 Cleaning up..."
kill $TUI_PID 2>/dev/null || true
./dev/scripts/clean.sh

echo "✅ Session complete!"
