#!/bin/bash
# dev/scripts/watch-and-rebuild.sh - Auto rebuild on changes

set -e

echo "👀 Watching for changes and auto-rebuilding..."
echo "📁 Monitoring: dev/mock-nvim-client/, dev/context-tui/"
echo "🛑 Press Ctrl+C to stop"

# Function to rebuild
rebuild() {
    echo ""
    echo "🔄 Changes detected, rebuilding..."
    ./dev/scripts/build.sh
    echo "✅ Rebuild complete!"
    echo ""
}

# Install fswatch if not available (optional)
if ! command -v fswatch &> /dev/null; then
    echo "⚠️  fswatch not found. Install with:"
    echo "   • macOS: brew install fswatch"
    echo "   • Linux: apt install fswatch or dnf install fswatch"
    echo ""
    echo "🔄 Falling back to simple polling..."
    
    while true; do
        sleep 2
        if find dev/mock-nvim-client dev/context-tui -name "*.go" -newer dev/bin/mock-nvim-client 2>/dev/null | grep -q .; then
            rebuild
        fi
    done
else
    # Use fswatch for efficient monitoring
    fswatch -o dev/mock-nvim-client/ dev/context-tui/ | while read; do
        rebuild
    done
fi
