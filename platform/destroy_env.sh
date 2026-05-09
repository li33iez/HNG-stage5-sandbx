#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/../.env" 2>/dev/null || true

ENV_ID="${1:-}"

if [[ -z "$ENV_ID" ]]; then
  echo "Usage: $0 <env_id>"
  exit 1
fi

STATE_FILE="$(dirname "$0")/../envs/$ENV_ID.json"
NGINX_CONF="$(dirname "$0")/../nginx/conf.d/$ENV_ID.conf"
LOG_DIR="$(dirname "$0")/../logs/$ENV_ID"
ARCHIVE_DIR="$(dirname "$0")/../logs/archived/$ENV_ID"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "Error: environment $ENV_ID not found"
  exit 1
fi

echo "Destroying environment $ENV_ID..."

# Kill log shipper process
if [[ -f "$LOG_DIR/log_shipper.pid" ]]; then
  PID=$(cat "$LOG_DIR/log_shipper.pid")
  kill "$PID" 2>/dev/null || true
  rm -f "$LOG_DIR/log_shipper.pid"
fi

# Stop and remove all containers with this env label
docker ps -a --filter "label=sandbox.env=$ENV_ID" --format "{{.ID}}" | \
  xargs -r docker rm -f

# Remove Docker network
docker network rm "$ENV_ID" 2>/dev/null || true

# Delete Nginx config and reload
if [[ -f "$NGINX_CONF" ]]; then
  rm -f "$NGINX_CONF"
  docker exec nginx nginx -s reload
fi

# Archive logs
if [[ -d "$LOG_DIR" ]]; then
  mkdir -p "$ARCHIVE_DIR"
  cp -r "$LOG_DIR/." "$ARCHIVE_DIR/"
  rm -rf "$LOG_DIR"
fi

# Delete state file
rm -f "$STATE_FILE"

echo " Environment $ENV_ID destroyed"
echo "  Logs archived to: logs/archived/$ENV_ID/"
