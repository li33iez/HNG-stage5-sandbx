#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/../.env" 2>/dev/null || true

ENVS_DIR="$(dirname "$0")/../envs"
LOG_FILE="$(dirname "$0")/../logs/cleanup.log"
DESTROY_SCRIPT="$(dirname "$0")/destroy_env.sh"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Cleanup daemon started (PID $$)"

while true; do
  NOW=$(date +%s)

  for STATE_FILE in "$ENVS_DIR"/*.json; do
    # skip if no files exist
    [[ -f "$STATE_FILE" ]] || continue

    ENV_ID=$(basename "$STATE_FILE" .json)
    CREATED_AT=$(jq -r '.created_at' "$STATE_FILE")
    TTL=$(jq -r '.ttl' "$STATE_FILE")
    EXPIRES_AT=$((CREATED_AT + TTL))

    if [[ "$NOW" -ge "$EXPIRES_AT" ]]; then
      log "TTL expired for $ENV_ID — destroying..."
      bash "$DESTROY_SCRIPT" "$ENV_ID" >> "$LOG_FILE" 2>&1 && \
        log "✓ $ENV_ID destroyed successfully" || \
        log "✗ Failed to destroy $ENV_ID"
    else
      REMAINING=$((EXPIRES_AT - NOW))
      log "  $ENV_ID OK — ${REMAINING}s remaining"
    fi
  done

  sleep 60
done
