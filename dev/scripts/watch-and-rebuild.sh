#!/bin/bash
# dev/scripts/watch-and-rebuild.sh - Auto rebuild on changes (updated)

set -e

echo "👀 Watching for changes and auto-rebuilding..."
echo "📁 Monitoring: dev/mock-nvim-client/, dev/context-tui/, cmd/context-tui/"
echo "🛑 Press Ctrl+C to stop"

# Function to rebuild
rebuild() {
    echo ""
    echo "🔄 Changes detected, rebuilding..."
    ./dev/scripts/build.sh
    echo "✅ Rebuild complete at $(date)"
    echo ""
}

# Install fswatch if not available (optional)
if ! command -v fswatch &> /dev/null; then
    echo "⚠️  fswatch not found. Install with:"
    echo "   • macOS: brew install fswatch"
    echo "   • Linux: apt install fswatch or dnf install fswatch"
    echo ""
    echo "🔄 Falling back to simple polling..."
    
    # Polling fallback
    last_change=$(find dev/mock-nvim-client dev/context-tui cmd/context-tui -name "*.go" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
    
    while true; do
        sleep 2
        current_change=$(find dev/mock-nvim-client dev/context-tui cmd/context-tui -name "*.go" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
        if [ "$current_change" != "$last_change" ]; then
            rebuild
            last_change="$current_change"
        fi
    done
else
    # Use fswatch for efficient monitoring
    fswatch -o dev/mock-nvim-client/ dev/context-tui/ cmd/context-tui/ | while read; do
        rebuild
    done
fi
