#!/bin/bash
# tests/run_tests.sh - Simple test runner

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Make debug script executable
chmod +x "$SCRIPT_DIR/debug_test.sh" 2>/dev/null || true

echo "🧪 Running nvim-hoverfloat tests..."

# Run smoke test first
echo "💨 Running smoke test..."
nvim --headless --noplugin \
  -u "$SCRIPT_DIR/minimal_init.lua" \
  -c "PlenaryBustedFile $SCRIPT_DIR/smoke_test.lua" \
  -c "qa!"

echo "✅ Smoke test passed"

# Create sample files directory and files
mkdir -p "$SCRIPT_DIR/sample_files"

# Create the sample Lua file
cat > "$SCRIPT_DIR/sample_files/test_file.lua" << 'EOF'
-- Sample Lua file for LSP testing
local M = {}

local VERSION = "1.0.0"

local function calculate_sum(a, b)
    return a + b
end

function M.add_numbers(x, y)
    local result = calculate_sum(x, y)
    return result
end

local Calculator = {
    value = 0
}

function Calculator:new()
    local calc = setmetatable({}, { __index = Calculator })
    calc.value = 0
    return calc
end

M.Calculator = Calculator

M.DEFAULT_CONFIG = {
    timeout = 5000,
    retry_count = 3,
    debug = false
}

function M.setup(user_config)
    local config = vim.tbl_deep_extend('force', M.DEFAULT_CONFIG, user_config or {})
    return config
end

return M
EOF

# Create the sample Go file
cat > "$SCRIPT_DIR/sample_files/test_file.go" << 'EOF'
package main

import (
	"fmt"
	"time"
)

const (
	DefaultTimeout = 30 * time.Second
	MaxRetries     = 3
)

type Config struct {
	Host    string        `json:"host"`
	Port    int           `json:"port"`
	Timeout time.Duration `json:"timeout"`
}

func (c *Config) GetAddress() string {
	return fmt.Sprintf("%s:%d", c.Host, c.Port)
}

func NewConfig(host string, port int) *Config {
	return &Config{
		Host:    host,
		Port:    port,
		Timeout: DefaultTimeout,
	}
}

var GlobalConfig = &Config{
	Host:    "localhost",
	Port:    8080,
	Timeout: DefaultTimeout,
}

func GetServerAddress() string {
	return GlobalConfig.GetAddress()
}

func main() {
	config := NewConfig("localhost", 8080)
	fmt.Printf("Server: %s\n", config.GetAddress())
}
EOF

# Run unit tests
echo "📝 Running unit tests..."
nvim --headless --noplugin \
  -u "$SCRIPT_DIR/minimal_init.lua" \
  -c "PlenaryBustedFile $SCRIPT_DIR/unit_tests.lua" \
  -c "qa!"

echo "✅ Unit tests passed"

# Run integration tests  
echo "🔧 Running integration tests..."
nvim --headless --noplugin \
  -u "$SCRIPT_DIR/minimal_init.lua" \
  -c "PlenaryBustedFile $SCRIPT_DIR/integration_tests.lua" \
  -c "qa!"

echo "✅ Integration tests passed"

# Cleanup
rm -rf "$SCRIPT_DIR/sample_files"

echo "🎉 All tests passed!"
