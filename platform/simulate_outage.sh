#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/../.env" 2>/dev/null || true

ENV_ID=""
MODE=""

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_ID="$2"; shift 2;;
    --mode) MODE="$2"; shift 2;;
    *) echo "Unknown flag: $1"; exit 1;;
  esac
done

if [[ -z "$ENV_ID" || -z "$MODE" ]]; then
  echo "Usage: $0 --env <env_id> --mode <crash|pause|network|recover|stress>"
  exit 1
fi

STATE_FILE="$(dirname "$0")/../envs/$ENV_ID.json"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "Error: environment $ENV_ID not found"
  exit 1
fi

# Guard — never run against Nginx or daemon container
CONTAINER_NAME=$(docker ps -a --filter "label=sandbox.env=$ENV_ID" --format "{{.Names}}" | head -1)

if [[ -z "$CONTAINER_NAME" ]]; then
  echo "Error: no running container found for $ENV_ID"
  exit 1
fi

if [[ "$CONTAINER_NAME" == "nginx" || "$CONTAINER_NAME" == "cleanup_daemon" ]]; then
  echo "Error: refusing to simulate outage on protected container: $CONTAINER_NAME"
  exit 1
fi

echo "Running '$MODE' simulation on $CONTAINER_NAME..."

case "$MODE" in
  crash)
    docker kill "$CONTAINER_NAME"
    echo " Container killed — health monitor should detect within 90s"
    ;;

  pause)
    docker pause "$CONTAINER_NAME"
    echo " Container paused — run with --mode recover to unpause"
    ;;

  network)
    docker network disconnect "$ENV_ID" "$CONTAINER_NAME"
    echo " Container disconnected from network $ENV_ID"
    ;;

  recover)
    # Unpause if paused
    STATUS=$(docker inspect --format "{{.State.Status}}" "$CONTAINER_NAME" 2>/dev/null || echo "missing")

    if [[ "$STATUS" == "paused" ]]; then
      docker unpause "$CONTAINER_NAME"
      echo " Container unpaused"
    elif [[ "$STATUS" == "exited" || "$STATUS" == "dead" ]]; then
      docker start "$CONTAINER_NAME"
      echo " Container restarted"
    else
      # Try reconnecting to network
      docker network connect "$ENV_ID" "$CONTAINER_NAME" 2>/dev/null && \
        echo " Container reconnected to network" || \
        echo "  Container already connected"
    fi

    # Reset status in state file
    TEMP=$(mktemp)
    jq '.status = "running"' "$STATE_FILE" > "$TEMP" && mv "$TEMP" "$STATE_FILE"
    echo "Status reset to running"
    ;;

  stress)
    if ! docker exec "$CONTAINER_NAME" which stress-ng &>/dev/null; then
      echo "Error: stress-ng not found in container"
      exit 1
    fi
    docker exec -d "$CONTAINER_NAME" stress-ng --cpu 2 --timeout 60s
    echo " CPU stress started for 60s inside $CONTAINER_NAME"
    ;;

  *)
    echo "Error: unknown mode '$MODE'. Use: crash, pause, network, recover, stress"
    exit 1
    ;;
esac
