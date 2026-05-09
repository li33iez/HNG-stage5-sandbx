#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/../.env" 2>/dev/null || true

NAME="${1:-}"
TTL="${2:-1800}"

if [[ -z "$NAME" ]]; then
  echo "Usage: $0 <name> [ttl_seconds]"
  exit 1
fi

ENV_ID="env-$(echo $NAME | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-')-$(date +%s)"
PORT=$(shuf -i 3000-9000 -n 1)
CREATED_AT=$(date +%s)
STATE_FILE="$(dirname "$0")/../envs/$ENV_ID.json"
NGINX_CONF="$(dirname "$0")/../nginx/conf.d/$ENV_ID.conf"
LOG_DIR="$(dirname "$0")/../logs/$ENV_ID"

mkdir -p "$LOG_DIR"

# Create Docker network
docker network create "$ENV_ID" 2>/dev/null || true

# Start app container
docker run -d \
  --name "$ENV_ID" \
  --network "$ENV_ID" \
  --label "sandbox.env=$ENV_ID" \
  -p "$PORT:3000" \
  -e ENV_ID="$ENV_ID" \
  devops-sandbox-app

# state file
TEMP_FILE=$(mktemp)
cat > "$TEMP_FILE" <<EOF
{
  "id": "$ENV_ID",
  "name": "$NAME",
  "port": $PORT,
  "container_name": "$ENV_ID",
  "network_name": "$ENV_ID",
  "created_at": $CREATED_AT,
  "ttl": $TTL,
  "status": "running"
}
EOF
mv "$TEMP_FILE" "$STATE_FILE"

# Write Nginx config
cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name $ENV_ID.localhost;

    location / {
        proxy_pass http://localhost:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

# Reload Nginx
docker exec nginx nginx -s reload

# Start log shipping
mkdir -p "$LOG_DIR"
docker logs -f "$ENV_ID" >> "$LOG_DIR/app.log" 2>&1 &
echo $! > "$LOG_DIR/log_shipper.pid"

echo " Environment created"
echo "  ID:  $ENV_ID"
echo "  URL: http://$ENV_ID.localhost"
echo "  TTL: ${TTL}s (expires at $(date -d @$((CREATED_AT + TTL)) '+%H:%M:%S'))"
