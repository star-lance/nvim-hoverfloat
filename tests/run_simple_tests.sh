#!/bin/bash

# tests/run_simple_tests.sh - Simple Test Runner (No Plenary Required)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$SCRIPT_DIR"

print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_info() {
    print_status "$BLUE" "INFO: $1"
}

print_success() {
    print_status "$GREEN" "SUCCESS: $1"
}

print_error() {
    print_status "$RED" "ERROR: $1"
}

# Check if nvim is available
check_nvim() {
    if ! command -v nvim &> /dev/null; then
        print_error "Neovim is not installed or not in PATH"
        exit 1
    fi
    
    local nvim_version
    nvim_version=$(nvim --version | head -n1 | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown")
    print_info "Found Neovim: $nvim_version"
}

# Run a simple test file
run_simple_test() {
    local test_file=$1
    local test_name=$2
    
    print_info "Running $test_name: $(basename "$test_file")"
    
    # Create a simple test runner
    local test_runner=$(cat << 'EOF'
-- Add plugin to runtime path
local plugin_path = vim.fn.expand("<sfile>:h:h")
vim.opt.rtp:prepend(plugin_path)

-- Basic test configuration
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undofile = false

-- Set up module loading
package.path = package.path .. ";" .. plugin_path .. "/lua/?.lua"
package.path = package.path .. ";" .. plugin_path .. "/lua/?/init.lua"

-- Load the test file
local test_file = vim.fn.expand("<sfile>:h") .. "/" .. arg[1]
dofile(test_file)
EOF
)
    
    # Write temporary test runner
    local temp_runner="/tmp/test_runner_$$.lua"
    echo "$test_runner" > "$temp_runner"
    
    # Run the test
    local exit_code=0
    nvim --headless -u "$temp_runner" -- "$(basename "$test_file")" || exit_code=$?
    
    # Clean up
    rm -f "$temp_runner"
    
    if [[ $exit_code -eq 0 ]]; then
        print_success "$test_name completed"
        return 0
    else
        print_error "$test_name failed (exit code: $exit_code)"
        return $exit_code
    fi
}

# Main function
main() {
    print_info "Simple Test Runner for nvim-hoverfloat (No Plenary Required)"
    print_info "========================================="
    
    check_nvim
    
    local test_files=()
    
    # Find test files
    for file in "$TEST_DIR"/simple_test_*.lua; do
        if [[ -f "$file" ]]; then
            test_files+=("$file")
        fi
    done
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        print_error "No test files found matching pattern: simple_test_*.lua"
        print_info "Create test files like: simple_test_position.lua, simple_test_cache.lua, etc."
        exit 1
    fi
    
    local total_tests=0
    local failed_tests=0
    
    # Run each test file
    for test_file in "${test_files[@]}"; do
        total_tests=$((total_tests + 1))
        local test_name=$(basename "$test_file" .lua)
        
        if ! run_simple_test "$test_file" "$test_name"; then
            failed_tests=$((failed_tests + 1))
        fi
        echo
    done
    
    # Print summary
    print_info "========================================="
    print_info "SUMMARY"
    print_info "========================================="
    print_info "Total test files: $total_tests"
    
    if [[ $failed_tests -eq 0 ]]; then
        print_success "All tests passed! 🎉"
        exit 0
    else
        print_error "$failed_tests out of $total_tests test files failed"
        exit 1
    fi
}

main "$@"
