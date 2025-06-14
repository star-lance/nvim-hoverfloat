# Makefile for nvim-hoverfloat

.PHONY: build build-debug install install-debug install-no-stop install-debug-no-stop clean stop-processes copy-binary stop help status test test-quick test-unit-real test-integration-real test-with-lsp

# Configuration
BINARY_NAME := nvim-context-tui
DEBUG_BINARY_NAME := nvim-context-tui-debug
BUILD_DIR := build
DEBUG_BUILD_DIR := build/debug
INSTALL_DIR := $(HOME)/.local/bin

# Go build flags
GO_PROD_FLAGS := -ldflags="-s -w" -trimpath
GO_DEBUG_FLAGS := -gcflags="all=-N -l" -ldflags="-X main.DebugMode=true"

# Process management timeouts
GRACEFUL_TIMEOUT := 10
INTERMEDIATE_TIMEOUT := 5
FORCE_TIMEOUT := 3

# Colors
RED := \033[31m
GREEN := \033[32m
YELLOW := \033[33m
BLUE := \033[34m
CYAN := \033[36m
RESET := \033[0m

# Default target
all: build

# Production build
build:
	@printf "$(BLUE)[BUILD]$(RESET) Building $(BINARY_NAME) (production)...\n"
	@mkdir -p $(BUILD_DIR)
	@cd cmd/context-tui && go build $(GO_PROD_FLAGS) -o ../../$(BUILD_DIR)/$(BINARY_NAME) .
	@printf "$(GREEN)[SUCCESS]$(RESET) Production build complete: $(BUILD_DIR)/$(BINARY_NAME)\n"

# Debug build
build-debug:
	@printf "$(BLUE)[BUILD]$(RESET) Building $(DEBUG_BINARY_NAME) (debug)...\n"
	@mkdir -p $(DEBUG_BUILD_DIR)
	@cd cmd/context-tui && go build $(GO_DEBUG_FLAGS) -o ../../$(DEBUG_BUILD_DIR)/$(DEBUG_BINARY_NAME) .
	@printf "$(GREEN)[SUCCESS]$(RESET) Debug build complete: $(DEBUG_BUILD_DIR)/$(DEBUG_BINARY_NAME)\n"

# Install production binary
install: build
	@printf "$(BLUE)[INSTALL]$(RESET) Installing $(BINARY_NAME) to $(INSTALL_DIR)...\n"
	@mkdir -p $(INSTALL_DIR)
	@$(MAKE) stop-processes BINARY_TARGET=$(BINARY_NAME)
	@$(MAKE) copy-binary SOURCE=$(BUILD_DIR)/$(BINARY_NAME) TARGET=$(INSTALL_DIR)/$(BINARY_NAME)
	@printf "$(GREEN)[SUCCESS]$(RESET) Production binary installed\n"

# Install debug binary
install-debug: build-debug
	@printf "$(BLUE)[INSTALL]$(RESET) Installing $(DEBUG_BINARY_NAME) to $(INSTALL_DIR)...\n"
	@mkdir -p $(INSTALL_DIR)
	@$(MAKE) stop-processes BINARY_TARGET=$(DEBUG_BINARY_NAME)
	@$(MAKE) copy-binary SOURCE=$(DEBUG_BUILD_DIR)/$(DEBUG_BINARY_NAME) TARGET=$(INSTALL_DIR)/$(DEBUG_BINARY_NAME)
	@printf "$(GREEN)[SUCCESS]$(RESET) Debug binary installed\n"

# Controlled process stopping
stop-processes:
	@if [ -z "$(BINARY_TARGET)" ]; then \
		printf "$(RED)[ERROR]$(RESET) BINARY_TARGET not specified\n"; \
		exit 1; \
	fi
	@printf "$(CYAN)[PROCESS]$(RESET) Checking for running $(BINARY_TARGET) processes...\n"
	@PIDS=$$(pgrep -x "$(BINARY_TARGET)" 2>/dev/null || true); \
	if [ -n "$$PIDS" ]; then \
		printf "$(YELLOW)[PROCESS]$(RESET) Found processes: $$PIDS\n"; \
		printf "$(CYAN)[PROCESS]$(RESET) Sending TERM signal...\n"; \
		echo "$$PIDS" | xargs -r kill -TERM 2>/dev/null || true; \
		printf "$(CYAN)[PROCESS]$(RESET) Waiting $(GRACEFUL_TIMEOUT) seconds for graceful shutdown...\n"; \
		for i in $$(seq 1 $(GRACEFUL_TIMEOUT)); do \
			sleep 1; \
			REMAINING=$$(pgrep -x "$(BINARY_TARGET)" 2>/dev/null || true); \
			if [ -z "$$REMAINING" ]; then \
				printf "$(GREEN)[SUCCESS]$(RESET) All processes stopped gracefully\n"; \
				exit 0; \
			fi; \
		done; \
		REMAINING=$$(pgrep -x "$(BINARY_TARGET)" 2>/dev/null || true); \
		if [ -n "$$REMAINING" ]; then \
			printf "$(YELLOW)[PROCESS]$(RESET) Processes still running, sending INT signal...\n"; \
			echo "$$REMAINING" | xargs -r kill -INT 2>/dev/null || true; \
			sleep $(INTERMEDIATE_TIMEOUT); \
			REMAINING=$$(pgrep -x "$(BINARY_TARGET)" 2>/dev/null || true); \
			if [ -n "$$REMAINING" ]; then \
				printf "$(YELLOW)[PROCESS]$(RESET) Force killing remaining processes...\n"; \
				echo "$$REMAINING" | xargs -r kill -KILL 2>/dev/null || true; \
				sleep $(FORCE_TIMEOUT); \
				FINAL=$$(pgrep -x "$(BINARY_TARGET)" 2>/dev/null || true); \
				if [ -n "$$FINAL" ]; then \
					printf "$(RED)[ERROR]$(RESET) Failed to stop processes: $$FINAL\n"; \
					exit 1; \
				fi; \
			fi; \
		fi; \
		printf "$(GREEN)[SUCCESS]$(RESET) All processes stopped\n"; \
	else \
		printf "$(GREEN)[INFO]$(RESET) No processes found\n"; \
	fi

# Safe binary copying with retries
copy-binary:
	@if [ -z "$(SOURCE)" ] || [ -z "$(TARGET)" ]; then \
		printf "$(RED)[ERROR]$(RESET) SOURCE and TARGET must be specified\n"; \
		exit 1; \
	fi
	@if [ ! -f "$(SOURCE)" ]; then \
		printf "$(RED)[ERROR]$(RESET) Source file not found: $(SOURCE)\n"; \
		exit 1; \
	fi
	@printf "$(CYAN)[COPY]$(RESET) Copying $(SOURCE) to $(TARGET)...\n"
	@for i in 1 2 3; do \
		if cp "$(SOURCE)" "$(TARGET).tmp" 2>/dev/null; then \
			if mv "$(TARGET).tmp" "$(TARGET)" 2>/dev/null; then \
				chmod +x "$(TARGET)"; \
				printf "$(GREEN)[SUCCESS]$(RESET) Binary copied successfully\n"; \
				break; \
			fi; \
		fi; \
		if [ $$i -eq 3 ]; then \
			printf "$(RED)[ERROR]$(RESET) Failed to install after 3 attempts\n"; \
			rm -f "$(TARGET).tmp"; \
			exit 1; \
		fi; \
		printf "$(YELLOW)[RETRY]$(RESET) Attempt $$i failed, waiting 2 seconds...\n"; \
		sleep 2; \
	done

# Install without stopping processes (for development)
install-no-stop: build
	@printf "$(BLUE)[INSTALL]$(RESET) Installing $(BINARY_NAME) (no process stop)...\n"
	@mkdir -p $(INSTALL_DIR)
	@$(MAKE) copy-binary SOURCE=$(BUILD_DIR)/$(BINARY_NAME) TARGET=$(INSTALL_DIR)/$(BINARY_NAME)
	@printf "$(GREEN)[SUCCESS]$(RESET) Production binary installed\n"

install-debug-no-stop: build-debug
	@printf "$(BLUE)[INSTALL]$(RESET) Installing $(DEBUG_BINARY_NAME) (no process stop)...\n"
	@mkdir -p $(INSTALL_DIR)
	@$(MAKE) copy-binary SOURCE=$(DEBUG_BUILD_DIR)/$(DEBUG_BINARY_NAME) TARGET=$(INSTALL_DIR)/$(DEBUG_BINARY_NAME)
	@printf "$(GREEN)[SUCCESS]$(RESET) Debug binary installed\n"

# Stop all processes (gentle)
stop:
	@printf "$(CYAN)[PROCESS]$(RESET) Stopping all nvim-context-tui processes...\n"
	@PIDS=$$(pgrep -f "nvim-context-tui" 2>/dev/null || true); \
	if [ -n "$$PIDS" ]; then \
		printf "$(YELLOW)[PROCESS]$(RESET) Found processes: $$PIDS\n"; \
		echo "$$PIDS" | xargs -r kill -TERM 2>/dev/null || true; \
		printf "$(GREEN)[SUCCESS]$(RESET) TERM signal sent\n"; \
	else \
		printf "$(GREEN)[INFO]$(RESET) No processes found\n"; \
	fi

# Show current build status
status:
	@printf "$(BLUE)[STATUS]$(RESET) Build Status:\n"
	@echo "============="
	@echo "Production binary: $(BUILD_DIR)/$(BINARY_NAME)"
	@if [ -f "$(BUILD_DIR)/$(BINARY_NAME)" ]; then \
		printf "  $(GREEN)[BUILT]$(RESET) $$(date -r $(BUILD_DIR)/$(BINARY_NAME) '+%Y-%m-%d %H:%M:%S')\n"; \
	else \
		printf "  $(RED)[NOT BUILT]$(RESET)\n"; \
	fi
	@echo "Debug binary: $(DEBUG_BUILD_DIR)/$(DEBUG_BINARY_NAME)"
	@if [ -f "$(DEBUG_BUILD_DIR)/$(DEBUG_BINARY_NAME)" ]; then \
		printf "  $(GREEN)[BUILT]$(RESET) $$(date -r $(DEBUG_BUILD_DIR)/$(DEBUG_BINARY_NAME) '+%Y-%m-%d %H:%M:%S')\n"; \
	else \
		printf "  $(RED)[NOT BUILT]$(RESET)\n"; \
	fi
	@echo "Installed binaries:"
	@if [ -f "$(INSTALL_DIR)/$(BINARY_NAME)" ]; then \
		printf "  $(GREEN)[INSTALLED]$(RESET) Production: $(INSTALL_DIR)/$(BINARY_NAME)\n"; \
	else \
		printf "  $(RED)[NOT INSTALLED]$(RESET) Production\n"; \
	fi
	@if [ -f "$(INSTALL_DIR)/$(DEBUG_BINARY_NAME)" ]; then \
		printf "  $(GREEN)[INSTALLED]$(RESET) Debug: $(INSTALL_DIR)/$(DEBUG_BINARY_NAME)\n"; \
	else \
		printf "  $(RED)[NOT INSTALLED]$(RESET) Debug\n"; \
	fi

# Clean build artifacts
clean:
	@printf "$(CYAN)[CLEAN]$(RESET) Cleaning build artifacts...\n"
	@rm -rf $(BUILD_DIR)
	@printf "$(GREEN)[SUCCESS]$(RESET) Clean complete\n"

# Test targets using real Neovim environment
test-quick:
	@printf "$(BLUE)[TEST]$(RESET) Running quick tests (no LSP required)...\n"
	@chmod +x tests/run_real_tests.sh || true
	@cd tests && nvim --headless --noplugin \
		-c "lua package.path = package.path .. ';$(PWD)/lua/?.lua;$(PWD)/lua/?/init.lua'" \
		-c "lua dofile('real_unit_tests.lua')" \
		-c "qa!"
	@printf "$(GREEN)[SUCCESS]$(RESET) Quick tests completed\n"

test-unit-real:
	@printf "$(BLUE)[TEST]$(RESET) Running unit tests with real Neovim...\n"
	@chmod +x tests/run_real_tests.sh
	@tests/run_real_tests.sh
	@printf "$(GREEN)[SUCCESS]$(RESET) Real unit tests completed\n"

test-integration-real:
	@printf "$(BLUE)[TEST]$(RESET) Running integration tests with LSP...\n"
	@if [ ! -f tests/real_integration_tests.lua ]; then \
		printf "$(RED)[ERROR]$(RESET) Integration test file not found\n"; \
		exit 1; \
	fi
	@chmod +x tests/run_real_tests.sh
	@tests/run_real_tests.sh
	@printf "$(GREEN)[SUCCESS]$(RESET) Real integration tests completed\n"

test-with-lsp: build
	@printf "$(BLUE)[TEST]$(RESET) Running full test suite with LSP servers...\n"
	@printf "$(CYAN)[CHECK]$(RESET) Checking for LSP servers...\n"
	@if command -v lua-language-server >/dev/null 2>&1; then \
		printf "$(GREEN)[FOUND]$(RESET) lua-language-server\n"; \
	else \
		printf "$(YELLOW)[MISSING]$(RESET) lua-language-server\n"; \
	fi
	@if command -v gopls >/dev/null 2>&1; then \
		printf "$(GREEN)[FOUND]$(RESET) gopls\n"; \
	else \
		printf "$(YELLOW)[MISSING]$(RESET) gopls\n"; \
	fi
	@$(MAKE) test-unit-real
	@$(MAKE) test-integration-real
	@printf "$(GREEN)[SUCCESS]$(RESET) Full test suite completed\n"

# Main test target using real environment
test: test-quick
	@printf "$(GREEN)[SUCCESS]$(RESET) Real tests completed successfully\n"

# Show help
help:
	@printf "$(BLUE)nvim-context-tui Build System$(RESET)\n"
	@echo ""
	@printf "$(CYAN)Build:$(RESET)\n"
	@echo "  build                  Build production binary"
	@echo "  build-debug            Build debug binary"
	@echo "  clean                  Clean build artifacts"
	@echo ""
	@printf "$(CYAN)Install:$(RESET)\n"
	@echo "  install                Install production binary (stops processes)"
	@echo "  install-debug          Install debug binary (stops processes)"
	@echo "  install-no-stop        Install production without stopping processes"
	@echo "  install-debug-no-stop  Install debug without stopping processes"
	@echo ""
	@printf "$(CYAN)Process Management:$(RESET)\n"
	@echo "  stop                   Stop all processes (TERM signal)"
	@echo ""
	@printf "$(CYAN)Testing (Real Environment):$(RESET)\n"
	@echo "  test                   Run tests with real Neovim (no LSP required)"
	@echo "  test-quick             Quick unit tests with real Neovim API"
	@echo "  test-unit-real         Unit tests with real Neovim environment"
	@echo "  test-integration-real  Integration tests with LSP servers"
	@echo "  test-with-lsp          Full test suite (requires LSP servers)"
	@echo ""
	@printf "$(CYAN)Utility:$(RESET)\n"
	@echo "  status                 Show build and install status"
	@echo "  help                   Show this help"
	@echo ""
	@printf "$(CYAN)LSP Server Setup:$(RESET)\n"
	@echo "  Install LSP servers for comprehensive testing:"
	@echo "    lua-language-server  - For Lua code analysis"
	@echo "    gopls               - For Go code analysis"
