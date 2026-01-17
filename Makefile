# =============================================================================
# Basher Makefile
# =============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Directories
ROOT_DIR := $(shell pwd)
SCRIPTS_DIR := $(ROOT_DIR)/scripts
LIB_DIR := $(ROOT_DIR)/lib
TESTS_DIR := $(ROOT_DIR)/tests
DEMOS_DIR := $(ROOT_DIR)/demos

# Tools
BATS := $(TESTS_DIR)/bats/bin/bats
SHELLCHECK := shellcheck
VHS := vhs

# Colors
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m

# =============================================================================
# HELP
# =============================================================================

.PHONY: help
help: ## Show this help message
	@printf "$(BLUE)Basher CLI Toolkit$(NC)\n\n"
	@printf "$(GREEN)Usage:$(NC) make <target>\n\n"
	@printf "$(GREEN)Targets:$(NC)\n"
	@awk 'BEGIN {FS = ":.*##"; } /^[a-zA-Z_-]+:.*?##/ { printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# =============================================================================
# DEVELOPMENT
# =============================================================================

.PHONY: setup
setup: ## Set up development environment
	@printf "$(BLUE)Setting up development environment...$(NC)\n"
	@mkdir -p $(SCRIPTS_DIR)/{data,agent,git,file,api,dev}
	@mkdir -p $(TESTS_DIR)/{unit,integration,fixtures}/{data,agent,git,file,api,dev}
	@mkdir -p $(DEMOS_DIR)/{tapes,gifs}/{data,agent,git,file,api,dev}
	@mkdir -p config completions
	@printf "$(GREEN)Done!$(NC)\n"

.PHONY: test-deps
test-deps: ## Install test dependencies (BATS)
	@printf "$(BLUE)Installing BATS...$(NC)\n"
	@if [ ! -d "$(TESTS_DIR)/bats" ]; then \
		git clone https://github.com/bats-core/bats-core.git $(TESTS_DIR)/bats; \
	fi
	@if [ ! -d "$(TESTS_DIR)/bats-support" ]; then \
		git clone https://github.com/bats-core/bats-support.git $(TESTS_DIR)/bats-support; \
	fi
	@if [ ! -d "$(TESTS_DIR)/bats-assert" ]; then \
		git clone https://github.com/bats-core/bats-assert.git $(TESTS_DIR)/bats-assert; \
	fi
	@if [ ! -d "$(TESTS_DIR)/bats-file" ]; then \
		git clone https://github.com/bats-core/bats-file.git $(TESTS_DIR)/bats-file; \
	fi
	@printf "$(GREEN)Done!$(NC)\n"

# =============================================================================
# LINTING
# =============================================================================

.PHONY: lint
lint: lint-lib lint-scripts lint-hooks ## Run all linters

.PHONY: lint-lib
lint-lib: ## Lint library files
	@printf "$(BLUE)Linting libraries...$(NC)\n"
	@$(SHELLCHECK) -x $(LIB_DIR)/*.sh
	@printf "$(GREEN)Done!$(NC)\n"

.PHONY: lint-scripts
lint-scripts: ## Lint script files
	@printf "$(BLUE)Linting scripts...$(NC)\n"
	@find $(SCRIPTS_DIR) -name '*.sh' -type f | xargs $(SHELLCHECK) -x 2>/dev/null || true
	@printf "$(GREEN)Done!$(NC)\n"

.PHONY: lint-hooks
lint-hooks: ## Lint hook files
	@printf "$(BLUE)Linting hooks...$(NC)\n"
	@find hooks -name '*.sh' -type f | xargs $(SHELLCHECK) -x 2>/dev/null || true
	@printf "$(GREEN)Done!$(NC)\n"

# =============================================================================
# TESTING
# =============================================================================

.PHONY: test
test: test-deps ## Run all tests
	@printf "$(BLUE)Running all tests...$(NC)\n"
	@$(BATS) $(TESTS_DIR)/unit/ $(TESTS_DIR)/integration/
	@printf "$(GREEN)Done!$(NC)\n"

.PHONY: test-unit
test-unit: test-deps ## Run unit tests only
	@printf "$(BLUE)Running unit tests...$(NC)\n"
	@$(BATS) $(TESTS_DIR)/unit/
	@printf "$(GREEN)Done!$(NC)\n"

.PHONY: test-integration
test-integration: test-deps ## Run integration tests only
	@printf "$(BLUE)Running integration tests...$(NC)\n"
	@$(BATS) $(TESTS_DIR)/integration/
	@printf "$(GREEN)Done!$(NC)\n"

.PHONY: test-coverage
test-coverage: test-deps ## Run tests with coverage
	@printf "$(BLUE)Running tests with coverage...$(NC)\n"
	@mkdir -p coverage
	@kcov --include-path=$(LIB_DIR)/,$(SCRIPTS_DIR)/ coverage $(BATS) $(TESTS_DIR)/unit/
	@printf "$(GREEN)Coverage report: coverage/index.html$(NC)\n"

.PHONY: test-watch
test-watch: ## Watch for changes and run tests
	@printf "$(BLUE)Watching for changes...$(NC)\n"
	@while true; do \
		inotifywait -e modify,create,delete -r $(LIB_DIR) $(SCRIPTS_DIR) $(TESTS_DIR); \
		make test-unit; \
	done

# =============================================================================
# DEMOS
# =============================================================================

.PHONY: demos
demos: ## Generate all VHS demos
	@printf "$(BLUE)Generating demos...$(NC)\n"
	@find $(DEMOS_DIR)/tapes -name '*.tape' -exec $(VHS) {} \;
	@printf "$(GREEN)Done!$(NC)\n"

.PHONY: demos-data
demos-data: ## Generate data script demos
	@find $(DEMOS_DIR)/tapes/data -name '*.tape' -exec $(VHS) {} \;

.PHONY: demos-agent
demos-agent: ## Generate agent script demos
	@find $(DEMOS_DIR)/tapes/agent -name '*.tape' -exec $(VHS) {} \;

# =============================================================================
# BUILD & RELEASE
# =============================================================================

.PHONY: build
build: lint test ## Build for release (lint + test)
	@printf "$(GREEN)Build complete!$(NC)\n"

.PHONY: release
release: build ## Create a release
	@printf "$(BLUE)Creating release...$(NC)\n"
	@./scripts/dev/release.sh
	@printf "$(GREEN)Done!$(NC)\n"

.PHONY: changelog
changelog: ## Generate changelog
	@printf "$(BLUE)Generating changelog...$(NC)\n"
	@git log --oneline --pretty=format:"- %s" > CHANGELOG.md
	@printf "$(GREEN)Done!$(NC)\n"

# =============================================================================
# DOCUMENTATION
# =============================================================================

.PHONY: docs
docs: ## Generate documentation
	@printf "$(BLUE)Generating documentation...$(NC)\n"
	@./scripts/dev/generate-docs.sh
	@printf "$(GREEN)Done!$(NC)\n"

.PHONY: docs-serve
docs-serve: ## Serve documentation locally
	@printf "$(BLUE)Serving docs at http://localhost:8000$(NC)\n"
	@cd docs && python3 -m http.server

# =============================================================================
# CLEANUP
# =============================================================================

.PHONY: clean
clean: ## Clean build artifacts
	@printf "$(BLUE)Cleaning...$(NC)\n"
	@rm -rf coverage/
	@rm -rf $(DEMOS_DIR)/gifs/*
	@find . -name '*.tmp' -delete
	@find . -name '*.bak' -delete
	@printf "$(GREEN)Done!$(NC)\n"

.PHONY: clean-all
clean-all: clean ## Clean everything including dependencies
	@rm -rf $(TESTS_DIR)/bats
	@rm -rf $(TESTS_DIR)/bats-support
	@rm -rf $(TESTS_DIR)/bats-assert
	@rm -rf $(TESTS_DIR)/bats-file

# =============================================================================
# INSTALLATION
# =============================================================================

.PHONY: install
install: ## Install basher locally
	@./install.sh

.PHONY: uninstall
uninstall: ## Uninstall basher
	@./uninstall.sh
