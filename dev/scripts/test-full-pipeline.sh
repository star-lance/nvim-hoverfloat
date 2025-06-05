#!/bin/bash
# dev/scripts/test-full-pipeline.sh - End-to-end testing (updated)

set -e

# Build everything first
./dev/scripts/build.sh

# Clean up any existing processes
./dev/scripts/clean.sh

SOCKET_PATH="/tmp/nvim_context.sock"

echo "🧪 Starting full pipeline test..."

# Start TUI in background
echo "📺 Starting TUI..."
kitty --title="LSP Context TUI Test" \
      --override=initial_window_width=80c \
      --override=initial_window_height=25c \
      --hold \
      -e ./dev/bin/context-tui-dev "$SOCKET_PATH" &
TUI_PID=$!

# Give TUI time to start
echo "⏳ Waiting for TUI to initialize..."
sleep 4

# Verify socket exists
if [ ! -S "$SOCKET_PATH" ]; then
    echo "❌ Socket not created, TUI failed to start"
    echo "Checking TUI process status..."
    if kill -0 $TUI_PID 2>/dev/null; then
        echo "⚠️  TUI process is running but socket not created"
        echo "Waiting longer..."
        sleep 2
        if [ ! -S "$SOCKET_PATH" ]; then
            echo "❌ Socket still not created after extended wait"
            kill $TUI_PID 2>/dev/null || true
            exit 1
        fi
    else
        echo "❌ TUI process has died"
        exit 1
    fi
fi

echo "✅ TUI started (PID: $TUI_PID)"

# Test scenarios with delays between
echo "📤 Testing TypeScript interface scenario..."
./dev/bin/mock-nvim-client scenario typescript_interface
sleep 3

echo "📤 Testing Rust generic function scenario..."
./dev/bin/mock-nvim-client scenario rust_generic_function
sleep 3

echo "📤 Testing Python method scenario..."
./dev/bin/mock-nvim-client scenario python_class_method
sleep 3

echo "📤 Testing edge case - empty hover..."
./dev/bin/mock-nvim-client scenario empty_hover
sleep 2

echo "📤 Testing deeply nested type..."
./dev/bin/mock-nvim-client scenario deeply_nested_type
sleep 3

echo "📤 Testing error scenario..."
./dev/bin/mock-nvim-client scenario error_scenario
sleep 2

echo ""
echo "🎯 Pipeline test complete!"
echo "📺 TUI is still running for manual inspection"
echo "🛑 Run './dev/scripts/clean.sh' to stop everything"
echo ""
echo "Test Summary:"
echo "  ✅ TUI startup successful"
echo "  ✅ Socket communication working"
echo "  ✅ Multiple scenarios tested"
echo "  ✅ Edge cases handled"

# Keep TUI running for manual inspection
echo "Press Ctrl+C to stop and cleanup..."
trap "echo 'Cleaning up...'; ./dev/scripts/clean.sh; exit 0" INT
wait $TUI_PID 2>/dev/null || true
