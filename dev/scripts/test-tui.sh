#!/bin/bash
# dev/scripts/test-tui.sh - Run TUI with mock data

set -e

# Ensure tools are built
./dev/scripts/build.sh

# Clean up any existing processes
./dev/scripts/clean.sh

SOCKET_PATH="/tmp/nvim_context.sock"

echo "🚀 Starting TUI test environment..."

# Check if TUI binary exists
if [ ! -f "dev/bin/context-tui" ]; then
    echo "❌ TUI binary not found. Build the context-tui first."
    exit 1
fi

# Start TUI in background
echo "📺 Starting context TUI..."
kitty --title="LSP Context TUI" --hold -e ./dev/bin/context-tui &
TUI_PID=$!

# Give TUI time to start and create socket
sleep 2

# Check if socket was created
if [ ! -S "$SOCKET_PATH" ]; then
    echo "❌ Socket not created. TUI may have failed to start."
    kill $TUI_PID 2>/dev/null || true
    exit 1
fi

echo "✅ TUI started successfully!"
echo "🔗 Socket available at: $SOCKET_PATH"
echo ""
echo "Now you can:"
echo "  • Send test data: ./dev/scripts/send-test-data.sh"
echo "  • Run interactive client: ./dev/bin/mock-nvim-client interactive"
echo "  • Stop everything: ./dev/scripts/clean.sh"
echo ""
echo "TUI PID: $TUI_PID"

# Keep script running to maintain TUI
wait $TUI_PID
