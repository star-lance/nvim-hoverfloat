#!/bin/bash
# dev/scripts/test-tui.sh - Run TUI with mock data (updated)

set -e

# Ensure tools are built
./dev/scripts/build.sh

# Clean up any existing processes
./dev/scripts/clean.sh

SOCKET_PATH="/tmp/nvim_context.sock"

echo "🚀 Starting TUI test environment..."

# Check if TUI binary exists
if [ ! -f "dev/bin/context-tui-dev" ]; then
    echo "❌ TUI binary not found. Build failed."
    exit 1
fi

# Start TUI in background
echo "📺 Starting context TUI..."
kitty --title="LSP Context TUI - Dev" \
      --override=initial_window_width=80c \
      --override=initial_window_height=25c \
      --override=remember_window_size=no \
      --hold \
      -e ./dev/bin/context-tui-dev "$SOCKET_PATH" &
TUI_PID=$!

# Give TUI time to start and create socket
sleep 3

# Check if socket was created
if [ ! -S "$SOCKET_PATH" ]; then
    echo "❌ Socket not created. TUI may have failed to start."
    echo "Checking TUI process..."
    if ! kill -0 $TUI_PID 2>/dev/null; then
        echo "❌ TUI process died"
    else
        echo "⚠️  TUI process running but no socket"
    fi
    ./dev/scripts/clean.sh
    exit 1
fi

echo "✅ TUI started successfully!"
echo "🔗 Socket available at: $SOCKET_PATH"
echo "📺 TUI PID: $TUI_PID"
echo ""
echo "Now you can:"
echo "  • Send test data: ./dev/scripts/send-test-data.sh"
echo "  • Run interactive client: ./dev/bin/mock-nvim-client interactive"
echo "  • Stop everything: ./dev/scripts/clean.sh"
echo ""

# Keep script running to maintain TUI
echo "Press Ctrl+C to stop TUI and exit..."
trap "echo 'Cleaning up...'; ./dev/scripts/clean.sh; exit 0" INT

# Wait for TUI process or user interrupt
wait $TUI_PID 2>/dev/null || true
