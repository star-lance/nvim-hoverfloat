#!/bin/bash
# tests/run_tests.sh - Simple wrapper for real tests (replaces the old complex version)

set -e

# Colors for output - consistent with other scripts
RED='\033[31m'
GREEN='\033[32m'
BLUE='\033[34m'
CYAN='\033[36m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_status() {
    local color=$1
    local prefix=$2
    local message=$3
    printf '%s[%s]%s %s\n' "$color" "$prefix" "$RESET" "$message"
}

print_info() { print_status "$BLUE" "INFO" "$1"; }
print_success() { print_status "$GREEN" "SUCCESS" "$1"; }
print_error() { print_status "$RED" "ERROR" "$1"; }

print_info "Running nvim-hoverfloat tests with real Neovim environment..."
echo

# Validate that the real test runner exists
if [ ! -f "$SCRIPT_DIR/run_real_tests.sh" ]; then
    print_error "Real test runner not found: $SCRIPT_DIR/run_real_tests.sh"
    print_info "Expected file structure:"
    print_info "  tests/"
    print_info "    ├── run_tests.sh (this file)"
    print_info "    ├── run_real_tests.sh (main runner)"
    print_info "    ├── test_env.lua"
    print_info "    └── real_*.lua (test files)"
    exit 1
fi

# Make sure the real test runner is executable
if [ ! -x "$SCRIPT_DIR/run_real_tests.sh" ]; then
    print_info "Making run_real_tests.sh executable..."
    chmod +x "$SCRIPT_DIR/run_real_tests.sh"
    
    if [ ! -x "$SCRIPT_DIR/run_real_tests.sh" ]; then
        print_error "Failed to make run_real_tests.sh executable"
        exit 1
    fi
fi

# Run the real tests
if "$SCRIPT_DIR/run_real_tests.sh"; then
    echo
    print_success "All tests completed successfully!"
    echo
    print_info "NOTE: These tests use a real Neovim environment instead of mocks."
    print_info "For full LSP integration tests, ensure you have:"
    print_info "  • lua-language-server (for Lua code analysis)"
    print_info "  • gopls (for Go code analysis)"
    exit 0
else
    local exit_code=$?
    echo
    print_error "Tests failed!"
    print_info "Check the output above for error details"
    exit $exit_code
fi
