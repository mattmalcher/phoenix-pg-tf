VAULT_ADDR  := http://localhost:8200
VAULT_TOKEN := root
COMPOSE     := docker compose
TF          := terraform

.PHONY: up infra-up tf-init tf-apply phoenix-start psql-tables down logs clean

## Full workflow: infra → terraform → phoenix
up: infra-up tf-apply phoenix-start

## Start Postgres and Vault, block until healthchecks pass
infra-up:
	$(COMPOSE) up -d --wait postgres vault

## Initialize Terraform providers (idempotent)
tf-init:
	$(TF) init

## Apply the module against the local Docker services
tf-apply: tf-init
	$(TF) apply -auto-approve

## Read phoenix credentials from Vault, write .env, start Phoenix container
phoenix-start:
	@echo "Reading phoenix credentials from Vault..."
	@( \
	    SECRET_JSON=$$($(COMPOSE) exec -e VAULT_TOKEN=$(VAULT_TOKEN) vault \
	        vault kv get -address=http://127.0.0.1:8200 -format=json \
	        secret/postgres/phoenix/phoenix) ; \
	    USERNAME=$$(echo "$$SECRET_JSON" | jq -r '.data.data.username') ; \
	    PASSWORD=$$(echo "$$SECRET_JSON" | jq -r '.data.data.password' | \
	        python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip(),safe=''))") ; \
	    DATABASE=$$(echo "$$SECRET_JSON" | jq -r '.data.data.database') ; \
	    printf 'PHOENIX_SQL_DATABASE_URL=postgresql://%s:%s@postgres:5432/%s\n' \
	        "$$USERNAME" "$$PASSWORD" "$$DATABASE" > .env \
	)
	@echo "Wrote .env with PHOENIX_SQL_DATABASE_URL"
	$(COMPOSE) --profile phoenix up -d phoenix

## List tables in the phoenix database (sorted by schema + name)
psql-tables:
	$(COMPOSE) exec postgres psql -U postgres -d phoenix -c \
	    "\dt public.*"

## Stop all containers and remove volumes
down:
	$(COMPOSE) --profile phoenix down -v

## Tail logs for all services
logs:
	$(COMPOSE) --profile phoenix logs -f

## Destroy Terraform resources and remove all generated files
clean: down
	$(TF) destroy -auto-approve || true
	rm -f .env
	rm -rf .terraform terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl
