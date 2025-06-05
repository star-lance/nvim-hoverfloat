#!/bin/bash
# dev/scripts/test-full-pipeline.sh - End-to-end testing

set -e

# Build everything first
./dev/scripts/build.sh

# Clean up any existing processes
./dev/scripts/clean.sh

SOCKET_PATH="/tmp/nvim_context.sock"

echo "🧪 Starting full pipeline test..."

# Start TUI in background
echo "📺 Starting TUI..."
kitty --title="LSP Context TUI Test" --hold -e ./dev/bin/context-tui &
TUI_PID=$!

# Give TUI time to start
sleep 3

# Verify socket exists
if [ ! -S "$SOCKET_PATH" ]; then
    echo "❌ Socket not created, TUI failed to start"
    kill $TUI_PID 2>/dev/null || true
    exit 1
fi

echo "✅ TUI started (PID: $TUI_PID)"

# Run test scenario
echo "📤 Sending test data..."
./dev/bin/mock-nvim-client scenario typescript_interface

sleep 2

echo "📤 Sending more test data..."
./dev/bin/mock-nvim-client scenario rust_generic_function

sleep 2

echo "📤 Testing edge case..."
./dev/bin/mock-nvim-client scenario empty_hover

echo ""
echo "🎯 Pipeline test complete!"
echo "📺 TUI is still running for manual testing"
echo "🛑 Run './dev/scripts/clean.sh' to stop everything"

# Keep TUI running
wait $TUI_PID
