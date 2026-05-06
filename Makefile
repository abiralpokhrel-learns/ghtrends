# Common project commands. Run "make help" to see all targets.

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Load .env if present
ifneq (,$(wildcard .env))
    include .env
    export
endif

.PHONY: help bootstrap tf-init tf-plan tf-apply tf-destroy lambda-package dbt-build dbt-test \
        embed-run embed-test streamlit-up clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# --- Phase 1: bootstrap ---

bootstrap: ## One-time: create S3 + DynamoDB for terraform state
	@bash bootstrap/create_state_backend.sh

# --- Terraform ---

tf-init: ## terraform init
	cd terraform && terraform init

tf-plan: ## terraform plan
	cd terraform && terraform plan -var-file=envs/dev/terraform.tfvars

tf-apply: ## terraform apply
	cd terraform && terraform apply -var-file=envs/dev/terraform.tfvars

tf-destroy: ## terraform destroy (use with caution)
	cd terraform && terraform destroy -var-file=envs/dev/terraform.tfvars

# --- Lambda ---

lambda-package: ## Build lambda deployment zip
	@bash lambda/ingest_gh_archive/build.sh

# --- dbt ---

dbt-build: ## Run all dbt models
	cd dbt && dbt build

dbt-test: ## Run dbt tests only
	cd dbt && dbt test

# --- Embeddings (offline; runs on your laptop) ---

embed-run: ## Build the numpy vector index in S3 (Phase 5)
	cd embeddings && python embed_repos.py --top 500

embed-test: ## Smoke-test the index with a sample query
	cd embeddings && python test_search.py "data engineering python pipelines"

# --- Streamlit (local dev only — production runs on Streamlit Community Cloud) ---

streamlit-up: ## Start streamlit dashboard locally
	cd streamlit && streamlit run app.py --server.port=$${STREAMLIT_PORT:-8501}

# --- Housekeeping ---

clean: ## Remove local build artifacts
	rm -rf lambda/*/build lambda/*/*.zip dbt/target dbt/dbt_packages dbt/logs
	find . -type d -name __pycache__ -exec rm -rf {} +
