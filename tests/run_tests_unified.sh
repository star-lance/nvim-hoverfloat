#!/bin/bash
# tests/run_tests_unified.sh - Unified test runner for nvim-hoverfloat
# Replaces run_tests.sh, run_real_tests.sh, and run_tests_clean.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[31m'
GREEN='\033[32m'
BLUE='\033[34m'
YELLOW='\033[33m'
CYAN='\033[36m'
RESET='\033[0m'

print_status() {
    local color=$1
    local prefix=$2
    local message=$3
    printf '%s[%s]%s %s\n' "$color" "$prefix" "$RESET" "$message"
}

print_info() { print_status "$BLUE" "INFO" "$1"; }
print_success() { print_status "$GREEN" "SUCCESS" "$1"; }
print_warning() { print_status "$YELLOW" "WARNING" "$1"; }
print_error() { print_status "$RED" "ERROR" "$1"; }

# Configuration
ISOLATED_MODE=false
WITH_LSP=true
UNIT_TESTS=true
INTEGRATION_TESTS=true
VERIFY_ONLY=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --isolated)
            ISOLATED_MODE=true
            shift
            ;;
        --no-lsp)
            WITH_LSP=false
            shift
            ;;
        --unit-only)
            INTEGRATION_TESTS=false
            shift
            ;;
        --integration-only)
            UNIT_TESTS=false
            shift
            ;;
        --verify-only)
            VERIFY_ONLY=true
            UNIT_TESTS=false
            INTEGRATION_TESTS=false
            shift
            ;;
        --help)
            cat << EOF
Usage: $0 [OPTIONS]

Test runner options:
  --isolated           Use completely isolated Neovim environment
  --no-lsp            Skip LSP-dependent tests
  --unit-only         Run only unit tests
  --integration-only  Run only integration tests
  --verify-only       Only verify test environment
  --help              Show this help message

Test modes:
  Default: Run all tests with user's Neovim configuration
  --isolated: Run tests with stock Neovim (no user config)

Examples:
  $0                    # Run all tests normally
  $0 --isolated         # Run all tests in isolated environment
  $0 --unit-only        # Run only unit tests
  $0 --no-lsp          # Skip LSP integration tests
EOF
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check Neovim
    if ! command -v nvim &> /dev/null; then
        print_error "Neovim is required but not found in PATH"
        exit 1
    fi
    
    local nvim_version
    nvim_version=$(nvim --version 2>/dev/null | head -n1 | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown")
    print_info "Found Neovim: $nvim_version"
    
    # Check plugin structure
    if [ ! -d "$PROJECT_ROOT/lua/hoverfloat" ]; then
        print_error "Plugin Lua modules not found at $PROJECT_ROOT/lua/hoverfloat"
        exit 1
    fi
    
    # Check test files
    local required_files=(
        "$SCRIPT_DIR/test_framework.lua"
        "$SCRIPT_DIR/test_lsp_setup.lua"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            print_error "Required file not found: $file"
            exit 1
        fi
    done
    
    # Check LSP availability if needed
    if [ "$WITH_LSP" = true ]; then
        if command -v lua-language-server &> /dev/null; then
            print_success "Found lua-language-server"
        else
            print_warning "lua-language-server not found, some tests may be skipped"
        fi
    fi
    
    print_success "Prerequisites check completed"
}

# Create test configuration based on mode
create_test_config() {
    local config_file="/tmp/hoverfloat_test_config_$$.lua"
    
    if [ "$ISOLATED_MODE" = true ]; then
        # Isolated mode - completely separate from user config
        cat > "$config_file" << EOF
-- Isolated test configuration
vim.env.XDG_CONFIG_HOME = '/tmp/nvim_test_config_' .. vim.fn.getpid()
vim.env.XDG_DATA_HOME = '/tmp/nvim_test_data_' .. vim.fn.getpid()
vim.env.XDG_STATE_HOME = '/tmp/nvim_test_state_' .. vim.fn.getpid()

-- Create temporary directories
vim.fn.mkdir(vim.env.XDG_CONFIG_HOME, 'p')
vim.fn.mkdir(vim.env.XDG_DATA_HOME, 'p')
vim.fn.mkdir(vim.env.XDG_STATE_HOME, 'p')

-- Stock Neovim settings
vim.opt.compatible = false
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.undofile = false
vim.opt.hidden = true
vim.opt.updatetime = 100

-- Add plugin to runtime path
vim.opt.rtp:prepend('$PROJECT_ROOT')

-- Set test mode
_G.TEST_MODE = true
_G.ISOLATED_MODE = true

print("[TEST] Isolated test environment loaded")
EOF
    else
        # Normal mode - use existing user config but add test setup
        cat > "$config_file" << EOF
-- Normal test configuration (uses user config)
-- Add plugin to runtime path
vim.opt.rtp:prepend('$PROJECT_ROOT')

-- Set test mode
_G.TEST_MODE = true
_G.ISOLATED_MODE = false

print("[TEST] Normal test environment loaded")
EOF
    fi
    
    echo "$config_file"
}

# Run a specific test file
run_test_file() {
    local test_file=$1
    local test_name
    test_name=$(basename "$test_file" .lua)
    
    print_info "Running $test_name..."
    
    if [ ! -f "$test_file" ]; then
        print_error "Test file not found: $test_file"
        return 1
    fi
    
    # Create test config
    local config_file
    config_file=$(create_test_config)
    
    # Ensure cleanup
    trap "rm -f '$config_file'" EXIT
    
    # Build Neovim command
    local nvim_cmd=(
        nvim
        --headless
        $([ "$ISOLATED_MODE" = true ] && echo "--clean")
        -u "$config_file"
        -c "lua package.path = package.path .. ';$PROJECT_ROOT/lua/?.lua;$PROJECT_ROOT/lua/?/init.lua'"
        -c "lua package.path = package.path .. ';$SCRIPT_DIR/?.lua'"
    )
    
    # Add LSP setup if needed
    if [ "$WITH_LSP" = true ]; then
        if [ "$ISOLATED_MODE" = true ]; then
            nvim_cmd+=(-c "lua dofile('$SCRIPT_DIR/test_with_lsp.lua')")
        else
            nvim_cmd+=(-c "lua require('tests.test_lsp_setup').setup_test_lsp_environment()")
        fi
    fi
    
    # Add test file and quit
    nvim_cmd+=(
        -c "lua dofile('$test_file')"
        -c "qa!"
    )
    
    # Run test
    local exit_code=0
    local test_output
    
    test_output=$("${nvim_cmd[@]}" 2>&1) || exit_code=$?
    
    # Clean up config file
    rm -f "$config_file"
    trap - EXIT
    
    # Process results
    if [ $exit_code -eq 0 ]; then
        print_success "$test_name completed"
        
        # Show important output
        if [[ -n "$test_output" ]]; then
            echo "$test_output" | while IFS= read -r line; do
                if [[ "$line" =~ (✅|❌|📝|⚠️|WARNING|SUCCESS|ERROR) ]]; then
                    echo "    $line"
                fi
            done
        fi
        
        return 0
    else
        print_error "$test_name failed (exit code: $exit_code)"
        
        if [[ -n "$test_output" ]]; then
            echo "$test_output" | sed 's/^/    /'
        fi
        
        return $exit_code
    fi
}

# Verify test environment
verify_environment() {
    print_info "Verifying test environment..."
    
    local config_file
    config_file=$(create_test_config)
    
    local verify_ok=true
    local verify_output
    
    verify_output=$(nvim --headless $([ "$ISOLATED_MODE" = true ] && echo "--clean") -u "$config_file" \
        -c "lua package.path = package.path .. ';$PROJECT_ROOT/lua/?.lua;$PROJECT_ROOT/lua/?/init.lua'" \
        -c "lua package.path = package.path .. ';$SCRIPT_DIR/?.lua'" \
        -c "lua local tf = require('tests.test_framework'); tf.validate_test_environment()" \
        -c "qa!" 2>&1) || verify_ok=false
    
    rm -f "$config_file"
    
    if [ "$verify_ok" = true ]; then
        print_success "Test environment verified"
        return 0
    else
        print_error "Test environment verification failed"
        if [[ -n "$verify_output" ]]; then
            echo "$verify_output" | sed 's/^/    /'
        fi
        return 1
    fi
}

# Main execution
main() {
    print_info "nvim-hoverfloat Unified Test Runner"
    print_info "=================================="
    print_info "Mode: $([ "$ISOLATED_MODE" = true ] && echo "Isolated" || echo "Normal")"
    print_info "LSP: $([ "$WITH_LSP" = true ] && echo "Enabled" || echo "Disabled")"
    echo
    
    check_prerequisites
    
    # Verify environment
    if ! verify_environment; then
        exit 1
    fi
    
    if [ "$VERIFY_ONLY" = true ]; then
        print_success "Environment verification complete"
        exit 0
    fi
    
    # Find test files
    local test_files=()
    
    if [ "$UNIT_TESTS" = true ] && [ -f "$SCRIPT_DIR/real_unit_tests.lua" ]; then
        test_files+=("$SCRIPT_DIR/real_unit_tests.lua")
    fi
    
    if [ "$INTEGRATION_TESTS" = true ] && [ -f "$SCRIPT_DIR/real_integration_tests.lua" ]; then
        test_files+=("$SCRIPT_DIR/real_integration_tests.lua")
    fi
    
    if [ ${#test_files[@]} -eq 0 ]; then
        print_error "No test files found to run"
        exit 1
    fi
    
    print_info "Running ${#test_files[@]} test file(s)..."
    echo
    
    # Run tests
    local total_tests=0
    local failed_tests=0
    
    for test_file in "${test_files[@]}"; do
        total_tests=$((total_tests + 1))
        
        if ! run_test_file "$test_file"; then
            failed_tests=$((failed_tests + 1))
        fi
        echo
    done
    
    # Summary
    print_info "=================================="
    print_info "TEST SUMMARY"
    print_info "=================================="
    print_info "Total test files: $total_tests"
    
    if [ $failed_tests -eq 0 ]; then
        print_success "All tests passed!"
        exit 0
    else
        print_error "$failed_tests out of $total_tests test files failed"
        exit 1
    fi
}

# Error handling
trap 'print_error "Script interrupted"; exit 130' INT
trap 'print_error "Script terminated"; exit 143' TERM

main "$@"