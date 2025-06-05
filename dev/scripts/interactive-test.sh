#!/bin/bash
# dev/scripts/interactive-test.sh - Interactive testing session (updated)

set -e

echo "🎮 Interactive Testing Session"
echo "=============================="

# Build everything
./dev/scripts/build.sh

# Clean up
./dev/scripts/clean.sh

echo ""
echo "Starting components..."

# Start TUI
echo "📺 Starting TUI..."
kitty --title="LSP Context TUI - Interactive" \
      --override=initial_window_width=80c \
      --override=initial_window_height=25c \
      --hold \
      -e ./dev/bin/context-tui-dev /tmp/nvim_context.sock &
TUI_PID=$!

echo "⏳ Waiting for TUI to initialize..."
sleep 4

# Check if TUI started
if [ ! -S "/tmp/nvim_context.sock" ]; then
    echo "❌ TUI failed to start"
    if kill -0 $TUI_PID 2>/dev/null; then
        echo "⚠️  TUI process running but no socket - trying longer wait..."
        sleep 3
        if [ ! -S "/tmp/nvim_context.sock" ]; then
            echo "❌ Socket still not created"
            kill $TUI_PID 2>/dev/null || true
            exit 1
        fi
    else
        echo "❌ TUI process died during startup"
        exit 1
    fi
fi

echo "✅ TUI started successfully (PID: $TUI_PID)"
echo ""

# Start interactive client
echo "🎯 Starting interactive mock client..."
echo "   Use this to send different scenarios to the TUI"
echo "   Available scenarios:"
echo "     1. typescript_interface"
echo "     2. python_class_method"
echo "     3. rust_generic_function"
echo "     4. empty_hover"
echo "     5. minimal_info"
echo "     6. deeply_nested_type"
echo "     7. error_scenario"
echo ""

# Setup cleanup trap
trap "echo ''; echo '🧹 Cleaning up...'; kill $TUI_PID 2>/dev/null || true; ./dev/scripts/clean.sh; echo '✅ Session complete!'; exit 0" INT

# Run the interactive client
./dev/bin/mock-nvim-client interactive

echo ""
echo "🧹 Cleaning up..."
kill $TUI_PID 2>/dev/null || true
./dev/scripts/clean.sh

echo "✅ Session complete!"
