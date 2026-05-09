.PHONY: up down create destroy logs health simulate clean test

SHELL := /bin/bash
ENV_FILE := .env
-include $(ENV_FILE)

# ── Start everything ────────────────────────────────────────
up:
	@echo "Starting Nginx..."
	docker rm -f nginx 2>/dev/null || true
	docker run -d \
		--name nginx \
		--network host \
		-v $(PWD)/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
		-v $(PWD)/nginx/conf.d:/etc/nginx/conf.d:ro \
		nginx:alpine
	@echo "Starting health poller..."
	nohup python3 monitor/health_poller.py >> logs/health_poller.log 2>&1 &
	echo $$! > logs/health_poller.pid
	@echo "Starting cleanup daemon..."
	nohup bash platform/cleanup_daemon.sh >> logs/cleanup.log 2>&1 &
	echo $$! > logs/daemon.pid
	@echo "Starting control API..."
	nohup python3 platform/api.py >> logs/api.log 2>&1 &
	echo $$! > logs/api.pid
	sleep 2
	@echo " Platform is up"
	@echo "  API: API is running on port 8000"
        @echo "  Nginx: is running on port 80"






# ── Stop everything ─────────────────────────────────────────
down:
	@echo "Destroying all environments..."
	@for f in envs/*.json; do \
		[ -f "$$f" ] || continue; \
		ENV_ID=$$(basename $$f .json); \
		bash platform/destroy_env.sh $$ENV_ID; \
	done
	@echo "Stopping Nginx..."
	docker rm -f nginx 2>/dev/null || true
	@echo "Stopping background processes..."
	@for pid_file in logs/health_poller.pid logs/daemon.pid logs/api.pid; do \
		[ -f "$$pid_file" ] || continue; \
		kill $$(cat $$pid_file) 2>/dev/null || true; \
		rm -f "$$pid_file"; \
	done
	@echo "✓ Platform is down"

# ── Create environment ──────────────────────────────────────
create:
	@read -p "Environment name: " name; \
	read -p "TTL in seconds [1800]: " ttl; \
	ttl=$${ttl:-1800}; \
	bash platform/create_env.sh "$$name" "$$ttl"

# ── Destroy specific environment ────────────────────────────
destroy:
ifndef ENV
	$(error ENV is required. Usage: make destroy ENV=<env_id>)
endif
	bash platform/destroy_env.sh $(ENV)

# ── Tail env logs ───────────────────────────────────────────
logs:
ifndef ENV
	$(error ENV is required. Usage: make logs ENV=<env_id>)
endif
	tail -f logs/$(ENV)/app.log

# ── Show all env health statuses ────────────────────────────
health:
	@echo "Environment health statuses:"
	@echo "─────────────────────────────────────────"
	@for f in envs/*.json; do \
		[ -f "$$f" ] || { echo "  No active environments"; break; }; \
		ENV_ID=$$(jq -r '.id' $$f); \
		NAME=$$(jq -r '.name' $$f); \
		STATUS=$$(jq -r '.status' $$f); \
		TTL=$$(jq -r '.ttl' $$f); \
		CREATED=$$(jq -r '.created_at' $$f); \
		NOW=$$(date +%s); \
		REMAINING=$$((CREATED + TTL - NOW)); \
		echo "  $$ENV_ID ($$NAME) — $$STATUS — $${REMAINING}s remaining"; \
	done
	@echo "─────────────────────────────────────────"

# ── Run outage simulation ───────────────────────────────────
simulate:
ifndef ENV
	$(error ENV is required. Usage: make simulate ENV=<env_id> MODE=<mode>)
endif
ifndef MODE
	$(error MODE is required. Usage: make simulate ENV=<env_id> MODE=<mode>)
endif
	bash platform/simulate_outage.sh --env $(ENV) --mode $(MODE)

# ── Wipe all state, logs, archives ─────────────────────────
clean:
	@echo "Wiping all state and logs..."
	rm -rf envs/*.json
	rm -rf logs/*
	rm -rf nginx/conf.d/*.conf
	@echo " Clean complete"

# Run all tests
test:
	@echo "Running shell tests..."
	bash tests/test_platform.sh
	@echo "Running API tests..."
	pytest tests/test_api.py -v
