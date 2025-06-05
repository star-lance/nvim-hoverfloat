#!/bin/bash
# dev/scripts/build.sh - Build all Go components (updated)

set -e

echo "🔨 Building development tools..."

# Create bin directory if it doesn't exist
mkdir -p dev/bin

# Build mock client
echo "📦 Building mock Neovim client..."
cd dev/mock-nvim-client
go mod tidy
go build -o ../bin/mock-nvim-client .
cd ../..

# Build dev TUI (simple version for testing)
if [ -d "dev/context-tui" ] && [ -f "dev/context-tui/main.go" ]; then
    echo "📦 Building dev context TUI..."
    cd dev/context-tui
    go mod tidy
    go build -o ../bin/context-tui-dev .
    cd ../..
else
    echo "⚠️  Dev TUI not implemented, using production TUI..."
    if [ -f "build/nvim-context-tui" ]; then
        cp build/nvim-context-tui dev/bin/context-tui-dev
    elif [ -f "cmd/context-tui/nvim-context-tui" ]; then
        cp cmd/context-tui/nvim-context-tui dev/bin/context-tui-dev
    else
        echo "📦 Building production TUI for dev use..."
        cd cmd/context-tui
        go mod tidy
        go build -o ../../dev/bin/context-tui-dev .
        cd ../..
    fi
fi

echo "✅ Build complete! Binaries available in dev/bin/"
