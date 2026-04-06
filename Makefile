.PHONY: help build test lint fmt clean install dev test-kimi test-minimax

ZIG ?= zig
ZIG_VERSION := $(shell $(ZIG) version 2>/dev/null)

# Colors
RED  := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m # No Color

## help - Show this help message
help:
	@echo "llmlite - Zig LLM SDK"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN { FS = ":.*?## " } /^[a-zA-Z_-]+:.*?## / { printf "  $(GREEN)%-15s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

## build - Build the project
build:
	@echo "Building llmlite..."
	$(ZIG) build

## test - Run all tests
test:
	@echo "Running tests..."
	$(ZIG) build test

## test-kimi - Run Kimi provider tests
test-kimi: build
	@echo "Running Kimi tests..."
	KIMI_API_KEY=$$(grep -oP 'KIMI_API_KEY=\K+' .env 2>/dev/null || echo "") && \
		$(ZIG) build kimi-test

## test-minimax - Run Minimax provider tests
test-minimax: build
	@echo "Running Minimax tests..."
	MINIMAX_API_KEY=$$(grep -oP 'MINIMAX_API_KEY=\K+' .env 2>/dev/null || echo "") && \
		$(ZIG) build minimax-test

## test-minimax-native - Run Minimax native API tests
test-minimax-native: build
	@echo "Running Minimax native tests..."
	MINIMAX_API_KEY=$$(grep -oP 'MINIMAX_API_KEY=\K+' .env 2>/dev/null || echo "") && \
		$(ZIG) build minimax-native-test

## run - Run the main executable
run:
	@echo "Running llmlite..."
	$(ZIG) build run

## run-kimi - Run Kimi example
run-kimi: build
	@echo "Running Kimi example..."
	$(ZIG) build run-kimi

## clean - Clean build artifacts
clean:
	@echo "Cleaning..."
	$(ZIG) build clean
	rm -rf .zig-cache zig-out

## fmt - Format code
fmt:
	@echo "Formatting code..."
	$(ZIG) fmt src/

## lint - Run linter checks
lint:
	@echo "Running linter checks..."
	@# Check for common issues
	@grep -r "as any" src/ && echo "$(RED)Found 'as any' type suppression!$(NC)" || true
	@grep -r "@ts-ignore" src/ && echo "$(RED)Found @ts-ignore!$(NC)" || true

## check - Run all checks (format, lint, build)
check: fmt lint build

## install - Install dependencies (for development)
install:
	@echo "Installing..."
	@which $(ZIG) > /dev/null || (echo "$(RED)Error: Zig not found. Install from https://ziglang.org/download/$(NC)" && exit 1)
	@echo "Zig version: $(ZIG_VERSION)"

## dev - Setup development environment
dev: install check test

## build-release - Build release version
build-release:
	@echo "Building release..."
	$(ZIG) build -Doptimize=ReleaseSafe
	$(ZIG) build -Doptimize=ReleaseFast
	$(ZIG) build -Doptimize=ReleaseSmall

## docker-build - Build Docker image
docker-build:
	docker build -t llmlite .

## docker-run - Run container
docker-run:
	docker run --rm -it llmlite

## info - Show project info
info:
	@echo "Project: llmlite"
	@echo "Zig: $(ZIG_VERSION)"
	@echo "Location: $(shell pwd)"
