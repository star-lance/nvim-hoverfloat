#!/bin/bash
# dev/scripts/send-test-data.sh - Quick data sender

set -e

SOCKET_PATH="/tmp/nvim_context.sock"

if [ ! -S "$SOCKET_PATH" ]; then
    echo "❌ Socket not found. Is the TUI running?"
    echo "💡 Start TUI with: ./dev/scripts/test-tui.sh"
    exit 1
fi

if [ $# -eq 0 ]; then
    echo "📤 Sending default test scenario..."
    ./dev/bin/mock-nvim-client scenario typescript_interface
else
    echo "📤 Sending scenario: $1"
    ./dev/bin/mock-nvim-client scenario "$1"
fi
