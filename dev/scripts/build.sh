#!/bin/bash
# dev/scripts/build.sh - Build all Go components

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

# Build TUI (when it exists)
if [ -d "dev/context-tui" ]; then
    echo "📦 Building context TUI..."
    cd dev/context-tui
    go mod tidy
    go build -o ../bin/context-tui .
    cd ../..
else
    echo "⚠️  Context TUI directory not found, skipping..."
fi

echo "✅ Build complete! Binaries available in dev/bin/"

