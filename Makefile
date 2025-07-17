# Makefile for nvim-hoverfloat - Fixed paths and simplified

.PHONY: build build-debug install install-debug clean stop help status test test-quick

# Configuration
BINARY_NAME := nvim-context-tui
DEBUG_BINARY_NAME := nvim-context-tui-debug
BUILD_DIR := build
INSTALL_DIR := $(HOME)/.local/bin
GO_MOD_DIR := cmd/context-tui

# Ensure install directory exists
$(INSTALL_DIR):
	@mkdir -p $(INSTALL_DIR)

# Go build flags
GO_PROD_FLAGS := -ldflags="-s -w" -trimpath
GO_DEBUG_FLAGS := -gcflags="all=-N -l"

# Colors
RED := \033[31m
GREEN := \033[32m
YELLOW := \033[33m
BLUE := \033[34m
CYAN := \033[36m
RESET := \033[0m

# Default target
all: build install

# Production build
build:
	@printf "$(BLUE)[BUILD]$(RESET) Building $(BINARY_NAME) (production)...\n"
	@mkdir -p $(BUILD_DIR)
	@cd $(GO_MOD_DIR) && go build $(GO_PROD_FLAGS) -o ../../$(BUILD_DIR)/$(BINARY_NAME) .
	@printf "$(GREEN)[SUCCESS]$(RESET) Production build complete: $(BUILD_DIR)/$(BINARY_NAME)\n"

# Debug build
build-debug:
	@printf "$(BLUE)[BUILD]$(RESET) Building $(DEBUG_BINARY_NAME) (debug)...\n"
	@mkdir -p $(BUILD_DIR)
	@cd $(GO_MOD_DIR) && go build $(GO_DEBUG_FLAGS) -o ../../$(BUILD_DIR)/$(DEBUG_BINARY_NAME) .
	@printf "$(GREEN)[SUCCESS]$(RESET) Debug build complete: $(BUILD_DIR)/$(DEBUG_BINARY_NAME)\n"

# Install production binary with proper process management
install: build $(INSTALL_DIR)
	@printf "$(BLUE)[INSTALL]$(RESET) Installing $(BINARY_NAME) to $(INSTALL_DIR)...\n"
	@# Stop any running instances gracefully
	@pkill -f "$(BINARY_NAME)" || true
	@sleep 1
	@# Install the binary
	@cp $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME)
	@chmod +x $(INSTALL_DIR)/$(BINARY_NAME)
	@printf "$(GREEN)[SUCCESS]$(RESET) Production binary installed to $(INSTALL_DIR)/$(BINARY_NAME)\n"

# Install debug binary
install-debug: build-debug $(INSTALL_DIR)
	@printf "$(BLUE)[INSTALL]$(RESET) Installing $(DEBUG_BINARY_NAME) to $(INSTALL_DIR)...\n"
	@# Stop any running instances gracefully
	@pkill -f "$(DEBUG_BINARY_NAME)" || true
	@sleep 1
	@# Install the binary
	@cp $(BUILD_DIR)/$(DEBUG_BINARY_NAME) $(INSTALL_DIR)/$(DEBUG_BINARY_NAME)
	@chmod +x $(INSTALL_DIR)/$(DEBUG_BINARY_NAME)
	@printf "$(GREEN)[SUCCESS]$(RESET) Debug binary installed to $(INSTALL_DIR)/$(DEBUG_BINARY_NAME)\n"

# Stop all processes
stop:
	@printf "$(CYAN)[PROCESS]$(RESET) Stopping all nvim-context-tui processes...\n"
	@pkill -f "nvim-context-tui" || printf "$(YELLOW)[INFO]$(RESET) No processes found\n"
	@printf "$(GREEN)[SUCCESS]$(RESET) Process stop command sent\n"

# Show current build status
status:
	@printf "$(BLUE)[STATUS]$(RESET) Build Status:\n"
	@echo "============="
	@printf "Production binary: $(BUILD_DIR)/$(BINARY_NAME) "
	@if [ -f "$(BUILD_DIR)/$(BINARY_NAME)" ]; then \
		printf "$(GREEN)[BUILT]$(RESET) $$(stat -c %y $(BUILD_DIR)/$(BINARY_NAME) 2>/dev/null || stat -f %Sm $(BUILD_DIR)/$(BINARY_NAME) 2>/dev/null || echo 'exists')\n"; \
	else \
		printf "$(RED)[NOT BUILT]$(RESET)\n"; \
	fi
	@printf "Debug binary: $(BUILD_DIR)/$(DEBUG_BINARY_NAME) "
	@if [ -f "$(BUILD_DIR)/$(DEBUG_BINARY_NAME)" ]; then \
		printf "$(GREEN)[BUILT]$(RESET) $$(stat -c %y $(BUILD_DIR)/$(DEBUG_BINARY_NAME) 2>/dev/null || stat -f %Sm $(BUILD_DIR)/$(DEBUG_BINARY_NAME) 2>/dev/null || echo 'exists')\n"; \
	else \
		printf "$(RED)[NOT BUILT]$(RESET)\n"; \
	fi
	@echo "Installed binaries:"
	@printf "Production: $(INSTALL_DIR)/$(BINARY_NAME) "
	@if [ -f "$(INSTALL_DIR)/$(BINARY_NAME)" ]; then \
		printf "$(GREEN)[INSTALLED]$(RESET)\n"; \
	else \
		printf "$(RED)[NOT INSTALLED]$(RESET)\n"; \
	fi
	@printf "Debug: $(INSTALL_DIR)/$(DEBUG_BINARY_NAME) "
	@if [ -f "$(INSTALL_DIR)/$(DEBUG_BINARY_NAME)" ]; then \
		printf "$(GREEN)[INSTALLED]$(RESET)\n"; \
	else \
		printf "$(RED)[NOT INSTALLED]$(RESET)\n"; \
	fi

# Clean build artifacts
clean:
	@printf "$(CYAN)[CLEAN]$(RESET) Cleaning build artifacts...\n"
	@rm -rf $(BUILD_DIR)
	@# Also clean Go module cache for this project
	@cd $(GO_MOD_DIR) && go clean -cache -modcache -testcache || true
	@printf "$(GREEN)[SUCCESS]$(RESET) Clean complete\n"

# Test targets
test-quick:
	@printf "$(BLUE)[TEST]$(RESET) Running quick tests (no LSP required)...\n"
	@if [ -f "tests/run_tests_unified.sh" ]; then \
		chmod +x tests/run_tests_unified.sh && tests/run_tests_unified.sh --unit-only --no-lsp; \
	elif [ -f "tests/run_real_tests.sh" ]; then \
		chmod +x tests/run_real_tests.sh && tests/run_real_tests.sh; \
	else \
		printf "$(YELLOW)[WARNING]$(RESET) No test runner found\n"; \
	fi

test:
	@printf "$(BLUE)[TEST]$(RESET) Running all tests...\n"
	@if [ -f "tests/run_tests_unified.sh" ]; then \
		chmod +x tests/run_tests_unified.sh && tests/run_tests_unified.sh; \
	elif [ -f "tests/run_real_tests.sh" ]; then \
		chmod +x tests/run_real_tests.sh && tests/run_real_tests.sh; \
	else \
		printf "$(YELLOW)[WARNING]$(RESET) No test runner found\n"; \
	fi

# Development targets
dev-install: build-debug install-debug
	@printf "$(GREEN)[DEV]$(RESET) Development build installed\n"

dev-run: install
	@printf "$(CYAN)[DEV]$(RESET) Starting TUI in development mode...\n"
	@$(INSTALL_DIR)/$(BINARY_NAME) /tmp/nvim_context.sock

# Dependency management
deps:
	@printf "$(BLUE)[DEPS]$(RESET) Checking Go dependencies...\n"
	@cd $(GO_MOD_DIR) && go mod tidy && go mod verify
	@printf "$(GREEN)[SUCCESS]$(RESET) Dependencies checked\n"

# Show help
help:
	@printf "$(BLUE)nvim-hoverfloat Build System$(RESET)\n"
	@echo ""
	@printf "$(CYAN)Build Targets:$(RESET)\n"
	@echo "  build                  Build production binary"
	@echo "  build-debug            Build debug binary"
	@echo "  clean                  Clean build artifacts"
	@echo "  deps                   Update and verify Go dependencies"
	@echo ""
	@printf "$(CYAN)Install Targets:$(RESET)\n"
	@echo "  install                Build and install production binary"
	@echo "  install-debug          Build and install debug binary"
	@echo "  dev-install            Build and install debug binary (alias)"
	@echo ""
	@printf "$(CYAN)Development:$(RESET)\n"
	@echo "  dev-run                Build, install, and run TUI"
	@echo "  stop                   Stop all TUI processes"
	@echo ""
	@printf "$(CYAN)Testing:$(RESET)\n"
	@echo "  test                   Run all tests"
	@echo "  test-quick             Run quick tests (no LSP required)"
	@echo ""
	@printf "$(CYAN)Utility:$(RESET)\n"
	@echo "  status                 Show build and install status"
	@echo "  help                   Show this help"
	@echo ""
	@printf "$(CYAN)Quick Start:$(RESET)\n"
	@echo "  make install           # Build and install the plugin"
	@echo "  make test-quick        # Run basic tests"
	@echo "  make status            # Check installation status"
