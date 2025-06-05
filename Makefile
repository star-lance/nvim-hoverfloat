# Makefile for nvim-hoverfloat

.PHONY: build install clean dev test dev-build dev-test lint format help

# Configuration
BINARY_NAME := nvim-context-tui
BUILD_DIR := build
INSTALL_DIR := $(HOME)/.local/bin
DEV_BIN_DIR := dev/bin

# Go build flags
GO_BUILD_FLAGS := -ldflags="-s -w" -trimpath
GO_VERSION := 1.23

# Default target
all: build

# Build production binary
build:
	@echo "🔨 Building $(BINARY_NAME)..."
	@mkdir -p $(BUILD_DIR)
	@cd cmd/context-tui && go build $(GO_BUILD_FLAGS) -o ../../$(BUILD_DIR)/$(BINARY_NAME) .
	@echo "✅ Build complete: $(BUILD_DIR)/$(BINARY_NAME)"

# Install binary to user's local bin (automatically stops running processes)
install: build
	@echo "📦 Installing $(BINARY_NAME) to $(INSTALL_DIR)..."
	@mkdir -p $(INSTALL_DIR)
	@if [ -f "$(INSTALL_DIR)/$(BINARY_NAME)" ]; then \
		echo "🔄 Gracefully stopping $(BINARY_NAME) processes..."; \
		pgrep -f "^$(INSTALL_DIR)/$(BINARY_NAME)" | head -10 | xargs -r kill -TERM 2>/dev/null || true; \
		sleep 1; \
		pgrep -f "^$(INSTALL_DIR)/$(BINARY_NAME)" | head -10 | xargs -r kill -KILL 2>/dev/null || true; \
		sleep 1; \
	fi
	@for i in 1 2 3; do \
		if cp $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME).tmp 2>/dev/null; then \
			mv $(INSTALL_DIR)/$(BINARY_NAME).tmp $(INSTALL_DIR)/$(BINARY_NAME) && break; \
		else \
			echo "⚠️  Binary still in use, waiting (attempt $$i/3)..."; \
			if [ $$i -eq 3 ]; then \
				echo "❌ Failed to install after 3 attempts. Please manually stop $(BINARY_NAME) processes and retry."; \
				exit 1; \
			fi; \
			sleep 2; \
		fi; \
	done
	@chmod +x $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "✅ Installed to $(INSTALL_DIR)/$(BINARY_NAME)"
	@echo "💡 Make sure $(INSTALL_DIR) is in your PATH"

# Install for development (symlink to avoid rebuilding)
install-dev: build
	@echo "🔗 Creating development symlink..."
	@mkdir -p $(INSTALL_DIR)
	@ln -sf $(PWD)/$(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "✅ Development symlink created"

# Build development tools
dev-build:
	@echo "🛠️  Building development tools..."
	@./dev/scripts/build.sh

# Development environment
dev: dev-build
	@echo "🚀 Starting development environment..."
	@./dev/scripts/interactive-test.sh

# Run all tests
test:
	@echo "🧪 Running tests..."
	@cd cmd/context-tui && go test -v ./...
	@cd dev/mock-nvim-client && go test -v ./...
	@echo "✅ All tests passed"

# Run development tests
dev-test: dev-build
	@echo "🧪 Running development tests..."
	@./dev/scripts/test-full-pipeline.sh

# Lint Go code
lint:
	@echo "🔍 Linting Go code..."
	@if command -v golangci-lint >/dev/null 2>&1 || [ -x "$(HOME)/go/bin/golangci-lint" ]; then \
		LINTER=$$(command -v golangci-lint || echo "$(HOME)/go/bin/golangci-lint"); \
		(cd cmd/context-tui && $$LINTER run ./... || true); \
		(cd dev/mock-nvim-client && $$LINTER run . || true); \
	else \
		echo "⚠️  golangci-lint not found, using go vet"; \
		(cd cmd/context-tui && go vet ./...); \
		(cd dev/mock-nvim-client && go vet .); \
	fi
	@echo "✅ Linting complete"

# Format Go code
format:
	@echo "🎨 Formatting Go code..."
	@gofmt -s -w ./cmd/context-tui/
	@gofmt -s -w ./dev/mock-nvim-client/
	@if command -v goimports >/dev/null 2>&1; then \
		goimports -w ./cmd/context-tui/; \
		goimports -w ./dev/mock-nvim-client/; \
	fi
	@echo "✅ Formatting complete"

# Clean build artifacts
clean:
	@echo "🧹 Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)
	@rm -rf $(DEV_BIN_DIR)
	@./dev/scripts/clean.sh
	@echo "✅ Clean complete"

# Clean and rebuild everything
rebuild: clean build

# Check Go version
check-go:
	@echo "🔍 Checking Go version..."
	@go version
	@if ! go version | grep -q "go$(GO_VERSION)"; then \
		echo "⚠️  Warning: This project is designed for Go $(GO_VERSION)"; \
	fi

# Initialize go modules
mod-tidy:
	@echo "📦 Tidying Go modules..."
	@cd cmd/context-tui && go mod tidy
	@cd dev/mock-nvim-client && go mod tidy
	@cd dev/context-tui && go mod tidy
	@echo "✅ Modules tidied"

# Download dependencies
deps:
	@echo "📥 Downloading dependencies..."
	@cd cmd/context-tui && go mod download
	@cd dev/mock-nvim-client && go mod download
	@cd dev/context-tui && go mod download
	@echo "✅ Dependencies downloaded"

# Build for multiple platforms
build-all:
	@echo "🌍 Building for multiple platforms..."
	@mkdir -p $(BUILD_DIR)
	
	@echo "  • Building for Linux (amd64)..."
	@cd cmd/context-tui && GOOS=linux GOARCH=amd64 go build $(GO_BUILD_FLAGS) -o ../../$(BUILD_DIR)/$(BINARY_NAME)-linux-amd64 .
	
	@echo "  • Building for macOS (amd64)..."
	@cd cmd/context-tui && GOOS=darwin GOARCH=amd64 go build $(GO_BUILD_FLAGS) -o ../../$(BUILD_DIR)/$(BINARY_NAME)-darwin-amd64 .
	
	@echo "  • Building for macOS (arm64)..."
	@cd cmd/context-tui && GOOS=darwin GOARCH=arm64 go build $(GO_BUILD_FLAGS) -o ../../$(BUILD_DIR)/$(BINARY_NAME)-darwin-arm64 .
	
	@echo "  • Building for Windows (amd64)..."
	@cd cmd/context-tui && GOOS=windows GOARCH=amd64 go build $(GO_BUILD_FLAGS) -o ../../$(BUILD_DIR)/$(BINARY_NAME)-windows-amd64.exe .
	
	@echo "✅ Multi-platform build complete"

# Package releases
package: build-all
	@echo "📦 Creating release packages..."
	@mkdir -p $(BUILD_DIR)/releases
	
	@cd $(BUILD_DIR) && tar -czf releases/$(BINARY_NAME)-linux-amd64.tar.gz $(BINARY_NAME)-linux-amd64
	@cd $(BUILD_DIR) && tar -czf releases/$(BINARY_NAME)-darwin-amd64.tar.gz $(BINARY_NAME)-darwin-amd64
	@cd $(BUILD_DIR) && tar -czf releases/$(BINARY_NAME)-darwin-arm64.tar.gz $(BINARY_NAME)-darwin-arm64
	@cd $(BUILD_DIR) && zip -q releases/$(BINARY_NAME)-windows-amd64.zip $(BINARY_NAME)-windows-amd64.exe
	
	@echo "✅ Release packages created in $(BUILD_DIR)/releases/"

# Quick development cycle
quick: format lint build
	@echo "✅ Quick development cycle complete"

# Full development cycle
full: clean deps format lint test build
	@echo "✅ Full development cycle complete"

# Check if required tools are installed
check-tools:
	@echo "🔧 Checking required tools..."
	@command -v go >/dev/null 2>&1 || { echo "❌ Go is required but not installed"; exit 1; }
	@command -v git >/dev/null 2>&1 || { echo "❌ Git is required but not installed"; exit 1; }
	@command -v make >/dev/null 2>&1 || { echo "❌ Make is required but not installed"; exit 1; }
	
	@echo "🔧 Checking optional tools..."
	@command -v golangci-lint >/dev/null 2>&1 || echo "⚠️  golangci-lint not found (optional but recommended)"
	@command -v goimports >/dev/null 2>&1 || echo "⚠️  goimports not found (optional but recommended)"
	@command -v kitty >/dev/null 2>&1 || echo "⚠️  kitty terminal not found (required for runtime)"
	
	@echo "✅ Tool check complete"

# Show help
help:
	@echo "nvim-hoverfloat Build System"
	@echo "============================"
	@echo ""
	@echo "Production targets:"
	@echo "  build          Build the TUI binary"
	@echo "  install        Install binary to ~/.local/bin"
	@echo "  install-dev    Create development symlink"
	@echo "  clean          Clean build artifacts"
	@echo "  rebuild        Clean and rebuild"
	@echo ""
	@echo "Development targets:"
	@echo "  dev            Start interactive development session"
	@echo "  dev-build      Build development tools"
	@echo "  dev-test       Run development pipeline test"
	@echo ""
	@echo "Quality targets:"
	@echo "  test           Run all tests"
	@echo "  lint           Lint Go code"
	@echo "  format         Format Go code"
	@echo "  quick          Format + lint + build"
	@echo "  full           Full development cycle"
	@echo ""
	@echo "Release targets:"
	@echo "  build-all      Build for multiple platforms"
	@echo "  package        Create release packages"
	@echo ""
	@echo "Utility targets:"
	@echo "  deps           Download dependencies"
	@echo "  mod-tidy       Tidy Go modules"
	@echo "  check-go       Check Go version"
	@echo "  check-tools    Check required tools"
	@echo "  help           Show this help"
	@echo ""
	@echo "Configuration:"
	@echo "  BINARY_NAME    = $(BINARY_NAME)"
	@echo "  BUILD_DIR      = $(BUILD_DIR)"
	@echo "  INSTALL_DIR    = $(INSTALL_DIR)"
	@echo "  GO_VERSION     = $(GO_VERSION)"
