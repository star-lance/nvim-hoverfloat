#!/bin/bash
# tests/debug_test.sh - Debug test environment issues

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔍 Debugging test environment..."

# Check Neovim version
echo "📋 Neovim version:"
nvim --version | head -n 1

# Check if plenary is installed
echo ""
echo "📦 Checking for plenary.nvim..."
PLENARY_PATHS=(
    "$HOME/.local/share/nvim/lazy/plenary.nvim"
    "$HOME/.local/share/nvim/site/pack/packer/start/plenary.nvim"
    "$HOME/.config/nvim/pack/*/start/plenary.nvim"
)

PLENARY_FOUND=false
for path in "${PLENARY_PATHS[@]}"; do
    if [ -d "$path" ]; then
        echo "✅ Found plenary at: $path"
        PLENARY_FOUND=true
        break
    fi
done

if [ "$PLENARY_FOUND" = false ]; then
    echo "❌ plenary.nvim not found in standard locations"
    echo "Please install with your plugin manager:"
    echo "  lazy.nvim: { 'nvim-lua/plenary.nvim' }"
    echo "  packer: use 'nvim-lua/plenary.nvim'"
    exit 1
fi

# Test minimal init loading
echo ""
echo "🧪 Testing minimal init..."
nvim --headless --noplugin \
    -u "$SCRIPT_DIR/minimal_init.lua" \
    -c "lua print('Test environment loaded successfully')" \
    -c "qa!" 2>&1

# Test a simple plenary command
echo ""
echo "🧪 Testing plenary loading..."
nvim --headless --noplugin \
    -u "$SCRIPT_DIR/minimal_init.lua" \
    -c "lua local assert = require('luassert'); print('luassert loaded: ' .. tostring(assert ~= nil))" \
    -c "qa!" 2>&1

# Test the new simple runner approach
echo ""
echo "🧪 Testing simple runner..."
nvim -l "$SCRIPT_DIR/simple_runner.lua" "$SCRIPT_DIR/smoke_test.lua" 2>&1

echo ""
echo "✅ Debug complete"
