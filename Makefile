SHELL := /usr/bin/env bash
PYTHON ?= python3
VENV_DIR := .venv
VENV_BIN := $(VENV_DIR)/bin

.PHONY: help setup dev format format-check lint lint-python lint-helm lint-lula test test-unit clean ci build-image scan-trivy sbom

help: ## Display available make targets
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

$(VENV_BIN)/activate:
	@echo "==> Creating local virtual environment in $(VENV_DIR)..."
	$(PYTHON) -m venv $(VENV_DIR)
	@echo "==> Upgrading pip and installing dependencies..."
	$(VENV_BIN)/pip install --upgrade pip
	$(VENV_BIN)/pip install -r requirements.txt

setup: $(VENV_BIN)/activate ## Bootstrap local .venv and install development dependencies
dev: setup ## Alias for setup

format: setup ## Auto-format Python codebase with isort and black
	@echo "==> Running isort..."
	$(VENV_BIN)/isort src/ tests/
	@echo "==> Running black..."
	$(VENV_BIN)/black src/ tests/

format-check: setup ## Check code formatting without modifying files
	@echo "==> Checking isort import ordering..."
	$(VENV_BIN)/isort --check-only src/ tests/
	@echo "==> Checking black code formatting..."
	$(VENV_BIN)/black --check src/ tests/

lint-python: setup ## Run flake8 static analysis
	@echo "==> Running flake8 linting..."
	$(VENV_BIN)/flake8 src/ tests/

lint-helm: ## Validate Helm chart templates
	@echo "==> Linting Helm chart..."
	helm lint packages/helm/tactical-sdn

lint-lula: ## Lint Lula OSCAL compliance validations
	@echo "==> Linting Lula OSCAL component and validations..."
	@if command -v lula >/dev/null 2>&1; then \
		for f in compliance/lula/validations/*.yaml; do \
			echo " -> Validating $$f"; \
			lula dev lint -f "$$f"; \
		done; \
	else \
		echo " [!] Lula binary not found in PATH, skipping local lula lint."; \
	fi

lint: format-check lint-python lint-helm ## Run all formatting and static analysis linters

test-unit: setup ## Execute unit tests
	@echo "==> Running unit tests..."
	$(VENV_BIN)/python -m unittest discover -s tests/unit -p "test_*.py" -v

test: test-unit ## Run primary test suite

build-image: ## Build local CNF container image
	@echo "==> Building CNF container image tactical-sdn-stack:local..."
	docker build -t tactical-sdn-stack:local -f src/dataplane/Dockerfile .

scan-trivy: ## Run Trivy vulnerability scan on local container image
	@echo "==> Running Trivy vulnerability scan..."
	@if command -v trivy >/dev/null 2>&1; then \
		trivy image --severity HIGH,CRITICAL --ignore-unfixed --ignorefile .trivyignore --exit-code 1 tactical-sdn-stack:local; \
	elif [ -x /home/bjarrett/.local/bin/trivy ]; then \
		/home/bjarrett/.local/bin/trivy image --severity HIGH,CRITICAL --ignore-unfixed --ignorefile .trivyignore --exit-code 1 tactical-sdn-stack:local; \
	else \
		docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v $(PWD)/.trivyignore:/.trivyignore aquasec/trivy:latest image --severity HIGH,CRITICAL --ignore-unfixed --ignorefile /.trivyignore --exit-code 1 tactical-sdn-stack:local; \
	fi

sbom: ## Generate CycloneDX and SPDX SBOMs via Syft
	@echo "==> Generating Software Bill of Materials (SBOM) with Syft..."
	@mkdir -p compliance/sbom
	@if command -v syft >/dev/null 2>&1; then \
		syft tactical-sdn-stack:local -o cyclonedx-json > compliance/sbom/tactical-sdn-stack-cyclonedx.json; \
		syft tactical-sdn-stack:local -o spdx-json > compliance/sbom/tactical-sdn-stack-spdx.json; \
	else \
		docker run --rm -v /var/run/docker.sock:/var/run/docker.sock anchore/syft:latest tactical-sdn-stack:local -o cyclonedx-json > compliance/sbom/tactical-sdn-stack-cyclonedx.json; \
		docker run --rm -v /var/run/docker.sock:/var/run/docker.sock anchore/syft:latest tactical-sdn-stack:local -o spdx-json > compliance/sbom/tactical-sdn-stack-spdx.json; \
	fi
	@echo "==> Generated SBOMs in compliance/sbom/"

ci: lint test-unit ## Run complete local CI verification pipeline

clean: ## Clean build artifacts, pyc caches, and temporary files
	@echo "==> Cleaning cache and build artifacts..."
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
	rm -rf .pytest_cache .coverage htmlcov

