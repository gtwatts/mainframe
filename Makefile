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
TEST_RUNNER := $(TESTS_DIR)/run_bats_suite.sh
BATS_TEST_SHELL := $(shell if [ -x /opt/homebrew/bin/bash ]; then printf '/opt/homebrew/bin/bash'; elif [ -x /usr/local/bin/bash ]; then printf '/usr/local/bin/bash'; else command -v bash; fi)
BATS_CORE_COMMIT := eb7f42f8d608ac693d7a4b67474f6714ea68cfc5
BATS_SUPPORT_COMMIT := 24a72e14349690bcbf7c151b9d2d1cdd32d36eb1
BATS_ASSERT_COMMIT := f1e9280eaae8f86cbe278a687e6ba755bc802c1a
BATS_FILE_COMMIT := 13ad5e2ffcc360281432db3d43a306f7b3667d60
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
	@set -euo pipefail; \
	ensure_dep() { \
		local url="$$1" path="$$2" commit="$$3" current fresh=false; \
		if [[ ! -e "$$path" ]]; then \
			git clone --no-checkout --filter=blob:none "$$url" "$$path"; \
			fresh=true; \
		elif [[ ! -d "$$path/.git" ]]; then \
			printf 'Refusing non-Git test dependency path: %s\n' "$$path" >&2; \
			return 1; \
		fi; \
		if [[ "$$fresh" != "true" && -n "$$(git -C "$$path" status --porcelain)" ]]; then \
			printf 'Refusing modified test dependency; review or replace: %s\n' "$$path" >&2; \
			return 1; \
		fi; \
		if ! git -C "$$path" cat-file -e "$$commit^{commit}" 2>/dev/null; then \
			git -C "$$path" fetch --force --tags origin; \
		fi; \
		git -C "$$path" checkout --detach "$$commit"; \
		current="$$(git -C "$$path" rev-parse HEAD)"; \
		[[ "$$current" == "$$commit" ]] || return 1; \
		[[ -z "$$(git -C "$$path" status --porcelain)" ]] || return 1; \
	}; \
	ensure_dep https://github.com/bats-core/bats-core.git "$(TESTS_DIR)/bats" "$(BATS_CORE_COMMIT)"; \
	ensure_dep https://github.com/bats-core/bats-support.git "$(TESTS_DIR)/bats-support" "$(BATS_SUPPORT_COMMIT)"; \
	ensure_dep https://github.com/bats-core/bats-assert.git "$(TESTS_DIR)/bats-assert" "$(BATS_ASSERT_COMMIT)"; \
	ensure_dep https://github.com/bats-core/bats-file.git "$(TESTS_DIR)/bats-file" "$(BATS_FILE_COMMIT)"
	@printf "$(GREEN)Done!$(NC)\n"

# =============================================================================
# LINTING
# =============================================================================

.PHONY: lint
lint: lint-lib lint-scripts lint-hooks check-exports ## Run all linters

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

.PHONY: check-exports
check-exports: ## Enforce the exact top-level function export policy
	@python3 $(SCRIPTS_DIR)/check-function-exports.py --check

# =============================================================================
# TESTING
# =============================================================================

.PHONY: test
test: test-deps ## Run the full Bats matrix
	@printf "$(BLUE)Running the full Bats matrix...$(NC)\n"
	@BATS_TEST_SHELL="$(BATS_TEST_SHELL)" $(TEST_RUNNER) --scope all
	@printf "$(GREEN)Done!$(NC)\n"

.PHONY: test-unit
test-unit: test-deps ## Run unit and library contract tests
	@printf "$(BLUE)Running unit tests...$(NC)\n"
	@BATS_TEST_SHELL="$(BATS_TEST_SHELL)" $(TEST_RUNNER) --scope unit
	@printf "$(GREEN)Done!$(NC)\n"

.PHONY: test-top
test-top: test-deps ## Run top-level Bats suites in tests/*.bats
	@printf "$(BLUE)Running top-level tests...$(NC)\n"
	@BATS_TEST_SHELL="$(BATS_TEST_SHELL)" $(TEST_RUNNER) --scope top
	@printf "$(GREEN)Done!$(NC)\n"

.PHONY: test-integration
test-integration: test-deps ## Run integration tests only
	@printf "$(BLUE)Running integration tests...$(NC)\n"
	@BATS_TEST_SHELL="$(BATS_TEST_SHELL)" $(TEST_RUNNER) --scope integration
	@printf "$(GREEN)Done!$(NC)\n"

.PHONY: test-coverage
test-coverage: test-deps ## Run tests with coverage
	@printf "$(BLUE)Running tests with coverage...$(NC)\n"
	@mkdir -p coverage
	@BATS_TEST_SHELL="$(BATS_TEST_SHELL)" kcov --include-path=$(LIB_DIR)/,$(SCRIPTS_DIR)/ coverage $(BATS) $(TESTS_DIR)/unit/
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
release: build ## Validate and prepare tracked release metadata only
	@printf "$(BLUE)Preparing tracked release metadata...$(NC)\n"
	@./scripts/dev/release.sh --prepare
	@printf "$(GREEN)Release metadata is current; no package was assembled or published.$(NC)\n"

.PHONY: release-candidate
release-candidate: ## Prepare, test, assemble, and verify a coherent local release candidate
	@printf "$(BLUE)Preparing tracked release metadata before testing...$(NC)\n"
	@./scripts/dev/release.sh --prepare
	@$(MAKE) build
	@printf "$(BLUE)Assembling the local release candidate...$(NC)\n"
	@$(BATS_TEST_SHELL) ./scripts/dev/release-candidate.sh --prepare
	@printf "$(GREEN)Local release candidate is coherent; nothing was published.$(NC)\n"

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
install: ## Install MAINFRAME locally
	@./install.sh

.PHONY: uninstall
uninstall: ## Uninstall MAINFRAME recoverably (installation is backed up)
	@./uninstall.sh

.PHONY: uninstall-dry-run
uninstall-dry-run: ## Preview the exact MAINFRAME files an uninstall would change
	@./uninstall.sh --dry-run

.PHONY: uninstall-purge
uninstall-purge: ## Irreversibly uninstall MAINFRAME after ownership checks
	@./uninstall.sh --purge
