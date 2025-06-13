# Makefile for nvim-context-tui

.PHONY: build build-debug install install-debug install-no-stop install-debug-no-stop clean stop-processes copy-binary stop help status

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
	@printf "$(BLUE)Building $(BINARY_NAME) (production)...$(RESET)\n"
	@mkdir -p $(BUILD_DIR)
	@cd cmd/context-tui && go build $(GO_PROD_FLAGS) -o ../../$(BUILD_DIR)/$(BINARY_NAME) .
	@printf "$(GREEN)Production build complete: $(BUILD_DIR)/$(BINARY_NAME)$(RESET)\n"

# Debug build
build-debug:
	@printf "$(BLUE)Building $(DEBUG_BINARY_NAME) (debug)...$(RESET)\n"
	@mkdir -p $(DEBUG_BUILD_DIR)
	@cd cmd/context-tui && go build $(GO_DEBUG_FLAGS) -o ../../$(DEBUG_BUILD_DIR)/$(DEBUG_BINARY_NAME) .
	@printf "$(GREEN)Debug build complete: $(DEBUG_BUILD_DIR)/$(DEBUG_BINARY_NAME)$(RESET)\n"

# Install production binary
install: build
	@printf "$(BLUE)Installing $(BINARY_NAME) to $(INSTALL_DIR)...$(RESET)\n"
	@mkdir -p $(INSTALL_DIR)
	@$(MAKE) stop-processes BINARY_TARGET=$(BINARY_NAME)
	@$(MAKE) copy-binary SOURCE=$(BUILD_DIR)/$(BINARY_NAME) TARGET=$(INSTALL_DIR)/$(BINARY_NAME)
	@printf "$(GREEN)Production binary installed$(RESET)\n"

# Install debug binary
install-debug: build-debug
	@printf "$(BLUE)Installing $(DEBUG_BINARY_NAME) to $(INSTALL_DIR)...$(RESET)\n"
	@mkdir -p $(INSTALL_DIR)
	@$(MAKE) stop-processes BINARY_TARGET=$(DEBUG_BINARY_NAME)
	@$(MAKE) copy-binary SOURCE=$(DEBUG_BUILD_DIR)/$(DEBUG_BINARY_NAME) TARGET=$(INSTALL_DIR)/$(DEBUG_BINARY_NAME)
	@printf "$(GREEN)Debug binary installed$(RESET)\n"

# Controlled process stopping
stop-processes:
	@if [ -z "$(BINARY_TARGET)" ]; then \
		printf "$(RED)Error: BINARY_TARGET not specified$(RESET)\n"; \
		exit 1; \
	fi
	@printf "$(CYAN)Checking for running $(BINARY_TARGET) processes...$(RESET)\n"
	@PIDS=$$(pgrep -x "$(BINARY_TARGET)" 2>/dev/null || true); \
	if [ -n "$$PIDS" ]; then \
		printf "$(YELLOW)Found processes: $$PIDS$(RESET)\n"; \
		printf "$(CYAN)Sending TERM signal...$(RESET)\n"; \
		echo "$$PIDS" | xargs -r kill -TERM 2>/dev/null || true; \
		printf "$(CYAN)Waiting $(GRACEFUL_TIMEOUT) seconds for graceful shutdown...$(RESET)\n"; \
		for i in $$(seq 1 $(GRACEFUL_TIMEOUT)); do \
			sleep 1; \
			REMAINING=$$(pgrep -x "$(BINARY_TARGET)" 2>/dev/null || true); \
			if [ -z "$$REMAINING" ]; then \
				printf "$(GREEN)All processes stopped gracefully$(RESET)\n"; \
				exit 0; \
			fi; \
		done; \
		REMAINING=$$(pgrep -x "$(BINARY_TARGET)" 2>/dev/null || true); \
		if [ -n "$$REMAINING" ]; then \
			printf "$(YELLOW)Processes still running, sending INT signal...$(RESET)\n"; \
			echo "$$REMAINING" | xargs -r kill -INT 2>/dev/null || true; \
			sleep $(INTERMEDIATE_TIMEOUT); \
			REMAINING=$$(pgrep -x "$(BINARY_TARGET)" 2>/dev/null || true); \
			if [ -n "$$REMAINING" ]; then \
				printf "$(YELLOW)Force killing remaining processes...$(RESET)\n"; \
				echo "$$REMAINING" | xargs -r kill -KILL 2>/dev/null || true; \
				sleep $(FORCE_TIMEOUT); \
				FINAL=$$(pgrep -x "$(BINARY_TARGET)" 2>/dev/null || true); \
				if [ -n "$$FINAL" ]; then \
					printf "$(RED)Failed to stop processes: $$FINAL$(RESET)\n"; \
					exit 1; \
				fi; \
			fi; \
		fi; \
		printf "$(GREEN)All processes stopped$(RESET)\n"; \
	else \
		printf "$(GREEN)No processes found$(RESET)\n"; \
	fi

# Safe binary copying with retries
copy-binary:
	@if [ -z "$(SOURCE)" ] || [ -z "$(TARGET)" ]; then \
		printf "$(RED)Error: SOURCE and TARGET must be specified$(RESET)\n"; \
		exit 1; \
	fi
	@if [ ! -f "$(SOURCE)" ]; then \
		printf "$(RED)Error: Source file not found: $(SOURCE)$(RESET)\n"; \
		exit 1; \
	fi
	@printf "$(CYAN)Copying $(SOURCE) to $(TARGET)...$(RESET)\n"
	@for i in 1 2 3; do \
		if cp "$(SOURCE)" "$(TARGET).tmp" 2>/dev/null; then \
			if mv "$(TARGET).tmp" "$(TARGET)" 2>/dev/null; then \
				chmod +x "$(TARGET)"; \
				printf "$(GREEN)Binary copied successfully$(RESET)\n"; \
				break; \
			fi; \
		fi; \
		if [ $$i -eq 3 ]; then \
			printf "$(RED)Failed to install after 3 attempts$(RESET)\n"; \
			rm -f "$(TARGET).tmp"; \
			exit 1; \
		fi; \
		printf "$(YELLOW)Retry $$i failed, waiting 2 seconds...$(RESET)\n"; \
		sleep 2; \
	done

# Install without stopping processes (for development)
install-no-stop: build
	@printf "$(BLUE)Installing $(BINARY_NAME) (no process stop)...$(RESET)\n"
	@mkdir -p $(INSTALL_DIR)
	@$(MAKE) copy-binary SOURCE=$(BUILD_DIR)/$(BINARY_NAME) TARGET=$(INSTALL_DIR)/$(BINARY_NAME)
	@printf "$(GREEN)Production binary installed$(RESET)\n"

install-debug-no-stop: build-debug
	@printf "$(BLUE)Installing $(DEBUG_BINARY_NAME) (no process stop)...$(RESET)\n"
	@mkdir -p $(INSTALL_DIR)
	@$(MAKE) copy-binary SOURCE=$(DEBUG_BUILD_DIR)/$(DEBUG_BINARY_NAME) TARGET=$(INSTALL_DIR)/$(DEBUG_BINARY_NAME)
	@printf "$(GREEN)Debug binary installed$(RESET)\n"

# Stop all processes (gentle)
stop:
	@printf "$(CYAN)Stopping all nvim-context-tui processes...$(RESET)\n"
	@PIDS=$$(pgrep -f "nvim-context-tui" 2>/dev/null || true); \
	if [ -n "$$PIDS" ]; then \
		printf "$(YELLOW)Found processes: $$PIDS$(RESET)\n"; \
		echo "$$PIDS" | xargs -r kill -TERM 2>/dev/null || true; \
		printf "$(GREEN)TERM signal sent$(RESET)\n"; \
	else \
		printf "$(GREEN)No processes found$(RESET)\n"; \
	fi

# Show current build status
status:
	@printf "$(BLUE)Build Status:$(RESET)\n"
	@echo "============="
	@echo "Production binary: $(BUILD_DIR)/$(BINARY_NAME)"
	@if [ -f "$(BUILD_DIR)/$(BINARY_NAME)" ]; then \
		printf "  $(GREEN)Built: $$(date -r $(BUILD_DIR)/$(BINARY_NAME) '+%Y-%m-%d %H:%M:%S')$(RESET)\n"; \
	else \
		printf "  $(RED)Not built$(RESET)\n"; \
	fi
	@echo "Debug binary: $(DEBUG_BUILD_DIR)/$(DEBUG_BINARY_NAME)"
	@if [ -f "$(DEBUG_BUILD_DIR)/$(DEBUG_BINARY_NAME)" ]; then \
		printf "  $(GREEN)Built: $$(date -r $(DEBUG_BUILD_DIR)/$(DEBUG_BINARY_NAME) '+%Y-%m-%d %H:%M:%S')$(RESET)\n"; \
	else \
		printf "  $(RED)Not built$(RESET)\n"; \
	fi
	@echo "Installed binaries:"
	@if [ -f "$(INSTALL_DIR)/$(BINARY_NAME)" ]; then \
		printf "  $(GREEN)Production: $(INSTALL_DIR)/$(BINARY_NAME)$(RESET)\n"; \
	else \
		printf "  $(RED)Production: Not installed$(RESET)\n"; \
	fi
	@if [ -f "$(INSTALL_DIR)/$(DEBUG_BINARY_NAME)" ]; then \
		printf "  $(GREEN)Debug: $(INSTALL_DIR)/$(DEBUG_BINARY_NAME)$(RESET)\n"; \
	else \
		printf "  $(RED)Debug: Not installed$(RESET)\n"; \
	fi

# Clean build artifacts
clean:
	@printf "$(CYAN)Cleaning build artifacts...$(RESET)\n"
	@rm -rf $(BUILD_DIR)
	@printf "$(GREEN)Clean complete$(RESET)\n"

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
	@printf "$(CYAN)Utility:$(RESET)\n"
	@echo "  status                 Show build and install status"
	@echo "  help                   Show this help"

# Test targets
.PHONY: test test-unit test-integration test-setup test-smoke test-debug

test-setup:
	@printf "$(CYAN)Setting up test environment...$(RESET)\n"
	@mkdir -p tests/sample_files
	@chmod +x tests/run_tests.sh tests/debug_test.sh

test-smoke: test-setup
	@printf "$(BLUE)Running smoke test...$(RESET)\n"
	@cd tests && nvim -l simple_runner.lua smoke_test.lua
	@printf "$(GREEN)Smoke test passed$(RESET)\n"

test-debug: test-setup
	@printf "$(BLUE)Running test environment debug...$(RESET)\n"
	@cd tests && ./debug_test.sh

test-unit: test-smoke
	@printf "$(BLUE)Running unit tests...$(RESET)\n"
	@cd tests && nvim -l simple_runner.lua unit_tests.lua
	@printf "$(GREEN)Unit tests passed$(RESET)\n"

test-integration: test-smoke
	@printf "$(BLUE)Running integration tests...$(RESET)\n"
	@cd tests && nvim -l simple_runner.lua integration_tests.lua
	@printf "$(GREEN)Integration tests passed$(RESET)\n"

test: test-setup
	@printf "$(BLUE)Running all tests...$(RESET)\n"
	@cd tests && ./run_tests.sh
	@printf "$(GREEN)All tests completed successfully$(RESET)\n"

# Help text addition
help:
	# ... existing help content ...
	@printf "$(CYAN)Testing:$(RESET)\n"
	@echo "  test                   Run all tests"
	@echo "  test-smoke             Run basic environment test"
	@echo "  test-unit              Run unit tests only"
	@echo "  test-integration       Run integration tests only"
	@echo "  test-debug             Debug test environment issues"
