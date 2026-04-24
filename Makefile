SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

.DEFAULT_GOAL := help

# -----------------------------------------------------------------------------
# Tooling
# -----------------------------------------------------------------------------
DART ?= dart
FLUTTER ?= flutter
PRETTIER ?= prettier
PUB ?= $(DART) pub
TEST ?= $(DART) test

# -----------------------------------------------------------------------------
# Project settings
# -----------------------------------------------------------------------------
PROJECT_NAME ?= dtorrent_task_v2
SRC_DIRS ?= lib test example bin
EXAMPLE ?= example/example.dart
# dart fix uses the analyzer context, so ignores are controlled by
# analysis_options.yaml rather than .gitignore.
DART_FIX_TARGET ?= .
COVERAGE_DIR ?= coverage

# Optional passthrough args
TEST_ARGS ?=
ANALYZE_ARGS ?=
FLUTTER_ANALYZE_ARGS ?=
PUB_ARGS ?=
FIX_ARGS ?=
NO_COLOR ?= 0
# Safety regex for repository-wide Dart commands.
# Matches paths relative to repo root.
DART_SAFE_EXCLUDE_RE ?= ^(\.dart_tool/|tmp/|test_results/|coverage/|test_download_)
# Safety regex for repository-wide Markdown commands.
# Matches paths relative to repo root.
MD_SAFE_EXCLUDE_RE ?= ^(\.dart_tool/|tmp/|test_results/|coverage/|test_download_)

# -----------------------------------------------------------------------------
# Colors (disable with: make NO_COLOR=1 ...)
# -----------------------------------------------------------------------------
ifeq ($(NO_COLOR),1)
	C_RESET :=
	C_BOLD :=
	C_DIM :=
	C_GREEN :=
	C_CYAN :=
	C_YELLOW :=
	C_RED :=
else
	C_RESET := \033[0m
	C_BOLD := \033[1m
	C_DIM := \033[2m
	C_GREEN := \033[32m
	C_CYAN := \033[36m
	C_YELLOW := \033[33m
	C_RED := \033[31m
endif

.PHONY: \
	help check-tools \
	pub-get pub-upgrade pub-outdated \
	format format-check format-all format-all-check fix-dry-run fix-apply \
	md-format md-check \
	analyze flutter-analyze analyze-all \
	test test-verbose test-name test-file test-coverage test-all \
	run-example \
	clean check check-all ci dev

##@ General
help: ## Show this help (dynamic)
	@printf "$(C_BOLD)$(PROJECT_NAME) Make targets$(C_RESET)\n\n"
	@awk '\
		BEGIN {FS = ":.*##"; section = ""} \
		/^##@/ { \
			section = substr($$0, 5); \
			printf "\n$(C_CYAN)%s$(C_RESET)\n", section; \
			next; \
		} \
		/^[a-zA-Z0-9_.-]+:.*##/ { \
			printf "  $(C_GREEN)%-20s$(C_RESET) %s\n", $$1, $$2; \
		} \
	' $(MAKEFILE_LIST)

check-tools: ## Check required local tools
	@command -v $(DART) >/dev/null || { printf "$(C_RED)Missing tool: $(DART)$(C_RESET)\n"; exit 1; }
	@printf "$(C_GREEN)Found $(DART)$(C_RESET)\n"
	@command -v $(FLUTTER) >/dev/null \
		&& printf "$(C_GREEN)Found $(FLUTTER)$(C_RESET)\n" \
		|| printf "$(C_YELLOW)$(FLUTTER) not found (flutter-analyze target may fail)$(C_RESET)\n"
	@command -v $(PRETTIER) >/dev/null \
		&& printf "$(C_GREEN)Found $(PRETTIER)$(C_RESET)\n" \
		|| printf "$(C_YELLOW)$(PRETTIER) not found (md-format/md-check will be skipped)$(C_RESET)\n"

##@ Dependencies
pub-get: ## Install dependencies (dart pub get)
	@$(PUB) get $(PUB_ARGS)

pub-upgrade: ## Upgrade dependencies (dart pub upgrade)
	@$(PUB) upgrade $(PUB_ARGS)

pub-outdated: ## Show outdated dependencies
	@$(PUB) outdated $(PUB_ARGS)

##@ Formatting
format: ## Format source files
	@$(DART) format $(SRC_DIRS)

format-check: ## Check formatting (no changes written)
	@$(DART) format --output=none --set-exit-if-changed $(SRC_DIRS)

format-all: ## Format all Dart files in repository with safety ignores
	@files=(); \
	while IFS= read -r -d '' file; do \
		if [[ "$$file" =~ $(DART_SAFE_EXCLUDE_RE) ]]; then \
			continue; \
		fi; \
		files+=("$$file"); \
	done < <(git ls-files -z --cached --others --exclude-standard -- '*.dart'); \
	if [ "$${#files[@]}" -eq 0 ]; then \
		printf "$(C_YELLOW)No Dart files found for format-all$(C_RESET)\n"; \
		exit 0; \
	fi; \
	$(DART) format "$${files[@]}"

format-all-check: ## Check all Dart files in repository formatting with safety ignores
	@files=(); \
	while IFS= read -r -d '' file; do \
		if [[ "$$file" =~ $(DART_SAFE_EXCLUDE_RE) ]]; then \
			continue; \
		fi; \
		files+=("$$file"); \
	done < <(git ls-files -z --cached --others --exclude-standard -- '*.dart'); \
	if [ "$${#files[@]}" -eq 0 ]; then \
		printf "$(C_YELLOW)No Dart files found for format-all-check$(C_RESET)\n"; \
		exit 0; \
	fi; \
	$(DART) format --output=none --set-exit-if-changed "$${files[@]}"

fix-apply: ## Apply dart fix once using analysis_options excludes
	@$(DART) fix --apply $(FIX_ARGS) $(DART_FIX_TARGET)

fix-dry-run: ## Preview dart fixes once using analysis_options excludes
	@$(DART) fix --dry-run $(FIX_ARGS) $(DART_FIX_TARGET)

md-format: ## Format Markdown files with Prettier (uses .prettierrc.json/.prettierignore)
	@if ! command -v $(PRETTIER) >/dev/null; then \
		printf "$(C_YELLOW)Skip md-format: $(PRETTIER) not found$(C_RESET)\n"; \
	else \
		files=(); \
		while IFS= read -r -d '' file; do \
			if [[ "$$file" =~ $(MD_SAFE_EXCLUDE_RE) ]]; then \
				continue; \
			fi; \
			files+=("$$file"); \
		done < <(git ls-files -z --cached --others --exclude-standard -- '*.md'); \
		if [ "$${#files[@]}" -eq 0 ]; then \
			printf "$(C_YELLOW)No Markdown files found for md-format$(C_RESET)\n"; \
			exit 0; \
		fi; \
		$(PRETTIER) --write "$${files[@]}"; \
	fi

md-check: ## Check Markdown formatting with Prettier (no changes written)
	@if ! command -v $(PRETTIER) >/dev/null; then \
		printf "$(C_YELLOW)Skip md-check: $(PRETTIER) not found$(C_RESET)\n"; \
	else \
		files=(); \
		while IFS= read -r -d '' file; do \
			if [[ "$$file" =~ $(MD_SAFE_EXCLUDE_RE) ]]; then \
				continue; \
			fi; \
			files+=("$$file"); \
		done < <(git ls-files -z --cached --others --exclude-standard -- '*.md'); \
		if [ "$${#files[@]}" -eq 0 ]; then \
			printf "$(C_YELLOW)No Markdown files found for md-check$(C_RESET)\n"; \
			exit 0; \
		fi; \
		$(PRETTIER) --check "$${files[@]}"; \
	fi

##@ Analysis
analyze: ## Run Dart analyzer
	@$(DART) analyze $(SRC_DIRS) $(ANALYZE_ARGS)

flutter-analyze: ## Run Flutter analyzer (for consumers using Flutter toolchain)
	@if command -v $(FLUTTER) >/dev/null; then \
		$(FLUTTER) analyze $(SRC_DIRS) $(FLUTTER_ANALYZE_ARGS); \
	else \
		printf "$(C_YELLOW)Skip flutter-analyze: $(FLUTTER) not found$(C_RESET)\n"; \
	fi

analyze-all: analyze flutter-analyze ## Run both Dart and Flutter analyze
	@printf "$(C_GREEN)All analyzers completed$(C_RESET)\n"

##@ Tests
test: ## Run all tests
	@$(TEST) $(TEST_ARGS)

test-verbose: ## Run tests with expanded reporter
	@$(TEST) -r expanded $(TEST_ARGS)

test-name: ## Run tests filtered by name: make test-name TEST_NAME="some test"
	@if [ -z "$${TEST_NAME:-}" ]; then \
		printf "$(C_RED)TEST_NAME is required$(C_RESET)\n"; \
		exit 1; \
	fi
	@$(TEST) --plain-name "$$TEST_NAME" $(TEST_ARGS)

test-file: ## Run a specific test file: make test-file FILE=test/foo_test.dart
	@if [ -z "$${FILE:-}" ]; then \
		printf "$(C_RED)FILE is required$(C_RESET)\n"; \
		exit 1; \
	fi
	@$(TEST) "$$FILE" $(TEST_ARGS)

test-coverage: ## Run tests with coverage output to coverage/
	@rm -rf $(COVERAGE_DIR)
	@$(TEST) --coverage=$(COVERAGE_DIR) $(TEST_ARGS)
	@printf "$(C_GREEN)Coverage written to $(COVERAGE_DIR)/$(C_RESET)\n"

test-all: ## Unified test pipeline (single coverage run)
	@$(MAKE) --no-print-directory test-coverage
	@printf "$(C_GREEN)test-all completed$(C_RESET)\n"

##@ Run
run-example: ## Run one example file (default: example/example.dart)
	@$(DART) run $(EXAMPLE)

##@ Quality Gates
check: format-check md-check analyze test ## Local quality gate
	@printf "$(C_GREEN)Check passed$(C_RESET)\n"

check-all: ## Full local gate with auto-fixes: pub-get -> fix -> format -> analyze
	@$(MAKE) --no-print-directory check-tools
	@$(MAKE) --no-print-directory pub-get
	@$(MAKE) --no-print-directory fix-apply
	@$(MAKE) --no-print-directory format-all
	@$(MAKE) --no-print-directory md-format
	@$(MAKE) --no-print-directory analyze-all
	@printf "$(C_GREEN)check-all completed$(C_RESET)\n"

ci: pub-get check ## CI-like pipeline
	@printf "$(C_GREEN)CI pipeline passed$(C_RESET)\n"

dev: pub-get analyze test ## Developer flow: dependencies -> analyze -> tests
	@printf "$(C_GREEN)Dev flow completed$(C_RESET)\n"

##@ Cleanup
clean: ## Remove build/test artifacts
	@rm -rf .dart_tool $(COVERAGE_DIR)
	@printf "$(C_DIM)Cleaned .dart_tool and $(COVERAGE_DIR)$(C_RESET)\n"
