#!/bin/bash
# verify_test_system.sh - Verify the new test system is working correctly

set -e

# Colors - using echo -e for proper rendering
print_status() {
    local color=$1
    local prefix=$2
    local message=$3
    echo -e "${color}[${prefix}]\033[0m ${message}"
}

print_info() { print_status "\033[34m" "INFO" "$1"; }
print_success() { print_status "\033[32m" "SUCCESS" "$1"; }
print_warning() { print_status "\033[33m" "WARNING" "$1"; }
print_error() { print_status "\033[31m" "ERROR" "$1"; }
print_check() { print_status "\033[36m" "CHECK" "$1"; }

# Get current directory (should be plugin root)
CURRENT_DIR="$(pwd)"

print_info "Verifying new test system for nvim-hoverfloat"
print_info "============================================="
print_info "Running from: $CURRENT_DIR"

# Step 1: Verify file structure
print_check "Checking file structure..."

required_files=(
    "tests/test_env.lua"
    "tests/real_unit_tests.lua"
    "tests/real_integration_tests.lua"
    "tests/run_real_tests.sh"
    "tests/run_tests.sh"
    "Makefile"
)

missing_files=()
for file in "${required_files[@]}"; do
    if [ ! -f "./$file" ]; then
        missing_files+=("$file")
    fi
done

if [ ${#missing_files[@]} -gt 0 ]; then
    print_error "Missing required files:"
    for file in "${missing_files[@]}"; do
        print_error "  - $file"
    done
    print_info "Current directory contents:"
    ls -la tests/ 2>/dev/null || echo "  tests/ directory not found"
    exit 1
fi

print_success "All required files present"

# Step 2: Check file permissions
print_check "Checking file permissions..."

executable_files=(
    "tests/run_real_tests.sh"
    "tests/run_tests.sh"
)

for file in "${executable_files[@]}"; do
    if [ ! -x "./$file" ]; then
        print_warning "$file is not executable, fixing..."
        chmod +x "./$file"
    fi
done

print_success "File permissions correct"

# Step 3: Verify no old test files remain
print_check "Checking for old test files..."

old_files=(
    "tests/integration_tests.lua"
    "tests/unit_tests.lua"
    "tests/smoke_test.lua"
    "tests/minimal_init.lua"
    "tests/simple_runner.lua"
    "tests/run_simple_tests.sh"
    "tests/run_test_file.lua"
    "tests/debug_test.sh"
    "tests/sample_files"
)

found_old_files=()
for file in "${old_files[@]}"; do
    if [ -e "./$file" ]; then
        found_old_files+=("$file")
    fi
done

if [ ${#found_old_files[@]} -gt 0 ]; then
    print_warning "Found old test files that should be removed:"
    for file in "${found_old_files[@]}"; do
        print_warning "  - $file"
    done
    print_info "Remove these with: rm -rf ${found_old_files[*]}"
else
    print_success "No old test files found"
fi

# Step 4: Check Neovim availability
print_check "Checking Neovim..."

if ! command -v nvim &> /dev/null; then
    print_error "Neovim not found in PATH"
    exit 1
fi

nvim_version=$(nvim --version 2>/dev/null | head -n1 | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' || echo "unknown")
print_success "Neovim found: $nvim_version"

# Step 5: Test basic Neovim functionality
print_check "Testing Neovim headless mode..."

if nvim --headless -c "lua print('test')" -c "qa!" >/dev/null 2>&1; then
    print_success "Neovim headless mode working"
else
    print_error "Neovim headless mode not working"
    exit 1
fi

# Step 6: Check LSP server availability
print_check "Checking LSP servers..."

lsp_servers=()
if command -v lua-language-server &> /dev/null; then
    lsp_servers+=("lua-language-server")
fi

if command -v gopls &> /dev/null; then
    lsp_servers+=("gopls")
fi

if [ ${#lsp_servers[@]} -eq 0 ]; then
    print_warning "No LSP servers found - tests will be limited"
    print_info "Install lua-language-server and/or gopls for full testing"
else
    print_success "Found LSP servers: ${lsp_servers[*]}"
fi

# Step 7: Test plugin module loading
print_check "Testing plugin module loading..."

module_test_output=$(nvim --headless --noplugin \
    -c "lua package.path = package.path .. ';$CURRENT_DIR/lua/?.lua'" \
    -c "lua local ok, result = pcall(require, 'hoverfloat.core.position'); print(ok and 'SUCCESS' or 'FAILED: ' .. result)" \
    -c "qa!" 2>&1)

if echo "$module_test_output" | grep -q "SUCCESS"; then
    print_success "Plugin modules load correctly"
else
    print_error "Plugin module loading failed:"
    echo "$module_test_output" | sed 's/^/    /'
    exit 1
fi

# Step 8: Test Makefile targets
print_check "Testing Makefile targets..."

# Check if test targets exist
if ! make help 2>/dev/null | grep -q "test-quick"; then
    print_error "Makefile test targets not found"
    print_info "Make sure you've updated the Makefile with the new test targets"
    exit 1
fi

print_success "Makefile test targets found"

# Step 9: Run a quick syntax check on test files
print_check "Checking test file syntax..."

test_files=(
    "tests/test_env.lua"
    "tests/real_unit_tests.lua"
    "tests/real_integration_tests.lua"
)

for test_file in "${test_files[@]}"; do
    if ! nvim --headless --noplugin \
        -c "lua package.path = package.path .. ';$CURRENT_DIR/lua/?.lua'" \
        -c "luafile $test_file" \
        -c "qa!" >/dev/null 2>&1; then
        print_error "Syntax error in $test_file"
        # Show the actual error
        nvim --headless --noplugin \
            -c "lua package.path = package.path .. ';$CURRENT_DIR/lua/?.lua'" \
            -c "luafile $test_file" \
            -c "qa!" 2>&1 | head -10
        exit 1
    fi
done

print_success "All test files have valid syntax"

# Step 10: Test the actual test runner (quick check)
print_check "Testing test runner basic functionality..."

if [ ! -x "./tests/run_real_tests.sh" ]; then
    print_error "run_real_tests.sh is not executable"
    exit 1
fi

# Just test that it starts correctly (don't run full tests)
test_runner_start=$(timeout 10s ./tests/run_real_tests.sh --help 2>&1 || echo "TIMEOUT_OR_NO_HELP")

if echo "$test_runner_start" | grep -q "Real Neovim Test Runner"; then
    print_success "Test runner starts correctly"
else
    print_warning "Test runner may have issues (this might be normal)"
    print_info "Try running: ./tests/run_real_tests.sh"
fi

# Step 11: Final system verification
print_info "============================================="
print_info "VERIFICATION SUMMARY"
print_info "============================================="

print_success "File structure: ✓"
print_success "Permissions: ✓"  
print_success "Neovim: ✓"
print_success "Plugin modules: ✓"
print_success "Makefile targets: ✓"
print_success "Test syntax: ✓"

if [ ${#lsp_servers[@]} -gt 0 ]; then
    print_success "LSP servers: ✓ (${lsp_servers[*]})"
else
    print_warning "LSP servers: ! (limited testing)"
fi

echo
print_info "Ready to run tests!"
print_info "Commands to try:"
print_info "  make test-quick              # Quick tests without LSP"
print_info "  make test-with-lsp           # Full tests with LSP integration"
print_info "  ./tests/run_real_tests.sh    # Direct test runner"
print_info "  ./tests/run_tests.sh         # Wrapper script"

echo
if [ ${#lsp_servers[@]} -eq 0 ]; then
    print_info "For complete testing, install LSP servers:"
    print_info "  lua-language-server: https://github.com/LuaLS/lua-language-server"
    print_info "  gopls: go install golang.org/x/tools/gopls@latest"
fi

print_success "Verification complete!"

# Show actual test file listing for confirmation
echo
print_info "Current test files:"
ls -la tests/ | sed 's/^/  /'
