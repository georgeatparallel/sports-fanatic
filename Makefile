.PHONY: help setup server test lint format migrate seed security \
        docker-up docker-down docker-build docker-logs \
        clean deps

# Default target
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} \
	/^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

##
## Development
##

setup: ## Install deps, create DB, run migrations, install assets
	mix setup

deps: ## Fetch mix dependencies
	mix deps.get

server: ## Start Phoenix dev server
	mix phx.server

iex: ## Start Phoenix dev server in IEx
	iex -S mix phx.server

##
## Database
##

migrate: ## Run pending migrations
	mix ecto.migrate

migrate-rollback: ## Roll back the last migration
	mix ecto.rollback

seed: ## Seed the database
	mix run priv/repo/seeds.exs

db-create: ## Create the database
	mix ecto.create

db-drop: ## Drop the database
	mix ecto.drop

db-reset: ## Drop, create, migrate, and seed
	mix ecto.reset

##
## Code Quality
##

lint: ## Run Credo static analysis
	mix credo --strict

format: ## Run mix format
	mix format

format-check: ## Check formatting without writing
	mix format --check-formatted

compile-check: ## Compile with warnings as errors
	mix compile --warnings-as-errors

##
## Testing
##

test: ## Run all tests (creates + migrates test DB automatically)
	mix test

test-unit: ## Run only unit tests (no DB required)
	mix test.unit

test-watch: ## Run tests in watch mode
	mix test.watch

test-cover: ## Run tests with coverage report
	mix test --cover

##
## Security
##

security: ## Run dependency audit
	mix deps.audit

##
## Docker
##

docker-build: ## Build all Docker images
	docker compose build

docker-up: ## Start all services (detached)
	docker compose up -d

docker-down: ## Stop and remove containers
	docker compose down

docker-logs: ## Tail logs for all services
	docker compose logs -f

docker-logs-web: ## Tail web service logs
	docker compose logs -f web

docker-logs-python: ## Tail python-bridge service logs
	docker compose logs -f python-bridge

docker-shell: ## Open IEx shell in running web container
	docker compose exec web bin/sports_fanatic remote

docker-dev: ## Start services including stripe-cli (dev profile)
	docker compose --profile dev up -d

##
## Utilities
##

clean: ## Remove build artifacts
	mix deps.clean --all
	rm -rf _build/ deps/ assets/node_modules/

routes: ## Print all Phoenix routes
	mix phx.routes

check: format-check compile-check lint test ## Run all checks (CI-equivalent locally)
