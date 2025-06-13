#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$SCRIPT_DIR"
MINIMAL_INIT="$TEST_DIR/minimal_init.lua"

# Default test files
UNIT_TESTS="$TEST_DIR/test_hoverfloat.lua"
INTEGRATION_TESTS="$TEST_DIR/integration_performance_tests.lua"

# Command line options
RUN_UNIT=true
RUN_INTEGRATION=false
VERBOSE=false
FILTER=""

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_error() {
    print_status "$RED" "ERROR: $1" >&2
}

print_success() {
    print_status "$GREEN" "SUCCESS: $1"
}

print_info() {
    print_status "$BLUE" "INFO: $1"
}

print_warning() {
    print_status "$YELLOW" "WARNING: $1"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean test runner for nvim-hoverfloat plugin

OPTIONS:
    -h, --help              Show this help message
    -u, --unit              Run unit tests only (default)
    -i, --integration       Run integration tests only
    -a, --all               Run both unit and integration tests
    -v, --verbose           Enable verbose output
    -f, --filter PATTERN    Run only tests matching pattern

EXAMPLES:
    $0                      # Run unit tests only
    $0 --all                # Run all tests
    $0 -i                   # Run integration tests only
    $0 -f "position"        # Run tests matching "position"
    $0 --verbose --all      # Run all tests with verbose output

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -u|--unit)
                RUN_UNIT=true
                RUN_INTEGRATION=false
                shift
                ;;
            -i|--integration)
                RUN_UNIT=false
                RUN_INTEGRATION=true
                shift
                ;;
            -a|--all)
                RUN_UNIT=true
                RUN_INTEGRATION=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -f|--filter)
                FILTER="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check if nvim is available
    if ! command -v nvim &> /dev/null; then
        print_error "Neovim is not installed or not in PATH"
        exit 1
    fi
    
    # Check Neovim version
    local nvim_version
    nvim_version=$(nvim --version | head -n1 | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown")
    print_info "Found Neovim: $nvim_version"
    
    # Check if test files exist
    if [[ ! -f "$MINIMAL_INIT" ]]; then
        print_error "Test initialization file not found: $MINIMAL_INIT"
        exit 1
    fi
    
    if [[ "$RUN_UNIT" == true && ! -f "$UNIT_TESTS" ]]; then
        print_error "Unit test file not found: $UNIT_TESTS"
        exit 1
    fi
    
    if [[ "$RUN_INTEGRATION" == true && ! -f "$INTEGRATION_TESTS" ]]; then
        print_error "Integration test file not found: $INTEGRATION_TESTS"
        exit 1
    fi
    
    print_success "Prerequisites check complete"
}

# Run a specific test file - CLEAN VERSION
run_test_file() {
    local test_file=$1
    local test_name=$2
    
    print_info "Running $test_name tests: $(basename "$test_file")"
    
    # Build CLEAN nvim command - minimal_init handles ALL setup
    local nvim_cmd=(
        "nvim"
        "--headless"
        "-u" "$MINIMAL_INIT"
        "-c" "PlenaryBustedFile $test_file"
        "-c" "qa!"
    )
    
    if [[ "$VERBOSE" == true ]]; then
        print_info "Command: ${nvim_cmd[*]}"
    fi
    
    # Run the test
    local output
    local exit_code=0
    output=$("${nvim_cmd[@]}" 2>&1) || exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        print_success "$test_name tests passed"
        # Show important output
        if [[ -n "$output" ]]; then
            echo "$output" | grep -E "(✅|❌|Testing:|SUCCESS|PASSED)" || true
        fi
    else
        print_error "$test_name tests failed (exit code: $exit_code)"
        echo "$output"
        return $exit_code
    fi
}

# Clean up test artifacts
cleanup_test_artifacts() {
    print_info "Cleaning up test artifacts..."
    
    # Remove test socket files
    find /tmp -name "test_hoverfloat*.sock" -type f -delete 2>/dev/null || true
    find /tmp -name "*test_lsp*.lua" -type f -delete 2>/dev/null || true
    
    print_info "Cleanup completed"
}

# Run tests based on configuration
run_tests() {
    local total_tests=0
    local failed_tests=0
    
    if [[ "$RUN_UNIT" == true ]]; then
        total_tests=$((total_tests + 1))
        if ! run_test_file "$UNIT_TESTS" "Unit"; then
            failed_tests=$((failed_tests + 1))
        fi
    fi
    
    if [[ "$RUN_INTEGRATION" == true ]]; then
        total_tests=$((total_tests + 1))
        if ! run_test_file "$INTEGRATION_TESTS" "Integration"; then
            failed_tests=$((failed_tests + 1))
        fi
    fi
    
    # Print summary
    echo
    print_info "========================================="
    print_info "TEST SUMMARY"
    print_info "========================================="
    print_info "Total test suites: $total_tests"
    
    if [[ $failed_tests -eq 0 ]]; then
        print_success "All test suites passed! ✅"
        return 0
    else
        print_error "$failed_tests out of $total_tests test suites failed ❌"
        return 1
    fi
}

# Main execution
main() {
    parse_args "$@"
    
    print_info "nvim-hoverfloat Clean Test Runner"
    print_info "=================================="
    
    # Trap cleanup on exit
    trap cleanup_test_artifacts EXIT
    
    check_prerequisites
    cleanup_test_artifacts
    
    # Run the tests
    if run_tests; then
        print_success "All tests completed successfully! 🎉"
        exit 0
    else
        print_error "Some tests failed. Check output above for details."
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
