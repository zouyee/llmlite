# llmlite - Zig LLM SDK
#
# Licensed under AGPL-3.0

PROJECT_DIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))
ZIG ?= zig
ZIG_VERSION := $(shell $(ZIG) version 2>/dev/null)

IMAGE_NAME := llmlite
IMAGE_TAG ?= latest

.PHONY: help
help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

build: ## Build the project
	$(ZIG) build

build-release: ## Build release version
	$(ZIG) build -Doptimize=ReleaseSafe
	$(ZIG) build -Doptimize=ReleaseFast
	$(ZIG) build -Doptimize=ReleaseSmall

run: build ## Run the application
	$(ZIG) build run

test: ## Run unit tests
	$(ZIG) build test

test-all: test test-property test-integration test-persistence test-savings-reporter test-gain test-proxy ## Run all tests

test-property: build ## Run property-based correctness tests
	$(ZIG) build property-test

test-integration: build ## Run proxy-cmd integration tests
	$(ZIG) build integration-test

test-persistence: build ## Run proxy SQLite persistence tests
	$(ZIG) build persistence-test

test-savings-reporter: build ## Run savings reporter unit tests
	$(ZIG) build savings-reporter-test

test-gain: build ## Run gain command unit tests
	$(ZIG) build gain-test

test-proxy: build ## Run proxy component tests
	$(ZIG) build proxy-test

test-kimi: build ## Run Kimi provider tests
	KIMI_API_KEY=$$(grep -oP 'KIMI_API_KEY=\K+' .env 2>/dev/null || echo "") && \
		$(ZIG) build kimi-test

test-minimax: build ## Run Minimax provider tests
	MINIMAX_API_KEY=$$(grep -oP 'MINIMAX_API_KEY=\K+' .env 2>/dev/null || echo "") && \
		$(ZIG) build minimax-test

test-minimax-native: build ## Run Minimax native API tests
	MINIMAX_API_KEY=$$(grep -oP 'MINIMAX_API_KEY=\K+' .env 2>/dev/null || echo "") && \
		$(ZIG) build minimax-native-test

##@ Cleaning

clean: ## Clean build artifacts
	rm -rf .zig-cache zig-out zig-cache

##@ Code Quality

fmt: ## Format code
	$(ZIG) fmt src/

lint: ## Run linter checks
	@grep -r "as any" src/ && echo "Found 'as any' type suppression!" || true
	@grep -r "@ts-ignore" src/ && echo "Found @ts-ignore!" || true

check: fmt lint build ## Run all checks

##@ Docker

docker-build: ## Build Docker image
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .

docker-run: ## Run Docker container
	docker run --rm -it $(IMAGE_NAME):$(IMAGE_TAG)

docker-test: ## Run tests in Docker
	docker build --target test -t $(IMAGE_NAME)-test .
	docker run --rm $(IMAGE_NAME)-test

##@ Installation

install: ## Verify Zig installation
	@which $(ZIG) > /dev/null || (echo "Error: Zig not found. Install from https://ziglang.org/download/" && exit 1)
	@echo "Zig version: $(ZIG_VERSION)"

dev: install check test ## Setup development environment

##@ Info

info: ## Show project info
	@echo "Project: llmlite"
	@echo "Zig: $(ZIG_VERSION)"
	@echo "Location: $(PROJECT_DIR)"
